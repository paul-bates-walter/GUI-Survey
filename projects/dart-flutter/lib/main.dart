import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'png_text.dart';

void main() {
  runApp(const SurveyPaintApp());
}

class SurveyPaintApp extends StatelessWidget {
  const SurveyPaintApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GUI Survey Flutter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF005B4A),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const SurveyPaintHome(),
    );
  }
}

enum ToolMode { path, rectangle, circle }

class SurveyPaintHome extends StatefulWidget {
  const SurveyPaintHome({super.key});

  @override
  State<SurveyPaintHome> createState() => _SurveyPaintHomeState();
}

class _SurveyPaintHomeState extends State<SurveyPaintHome> {
  static const Size _defaultCanvasSize = Size(1024, 768);
  static const XTypeGroup _pngTypeGroup = XTypeGroup(
    label: 'PNG images',
    extensions: <String>['png'],
    mimeTypes: <String>['image/png'],
    uniformTypeIdentifiers: <String>['public.png'],
  );

  final TextEditingController _loadPathController = TextEditingController();
  final TextEditingController _savePathController =
      TextEditingController(text: 'output.png');

  final List<DrawElement> _elements = <DrawElement>[];
  final List<List<TextEditingController>> _metadataRows =
      <List<TextEditingController>>[];

  ToolMode _tool = ToolMode.path;
  Color _color = const Color(0xFF0D5C63);
  double _radius = 8;
  Size _canvasSize = _defaultCanvasSize;
  ui.Image? _backgroundImage;
  Offset? _anchorPoint;
  Offset? _previewPoint;
  List<Offset> _activePath = <Offset>[];
  bool _penDown = false;
  String _status = 'Ready.';

  @override
  void dispose() {
    _loadPathController.dispose();
    _savePathController.dispose();
    _clearMetadataRows();
    super.dispose();
  }

  void _clearMetadataRows() {
    for (final List<TextEditingController> row in _metadataRows) {
      row[0].dispose();
      row[1].dispose();
    }
    _metadataRows.clear();
  }

  void _addMetadataRow(String key, String value) {
    _metadataRows.add(<TextEditingController>[
      TextEditingController(text: key),
      TextEditingController(text: value),
    ]);
  }

  List<MapEntry<String, String>> _collectMetadata() {
    return _metadataRows
        .where(
          (List<TextEditingController> row) => row[0].text.trim().isNotEmpty,
        )
        .map(
          (List<TextEditingController> row) =>
              MapEntry<String, String>(row[0].text.trim(), row[1].text),
        )
        .toList();
  }

  Future<void> _pickAndLoadPng() async {
    try {
      final XFile? pickedFile = await openFile(
        acceptedTypeGroups: <XTypeGroup>[_pngTypeGroup],
      );

      if (pickedFile == null) {
        _setStatus('Load canceled.');
        return;
      }

      _loadPathController.text = pickedFile.path;
      await _loadPngFromPath(pickedFile.path);
    } on MissingPluginException {
      _setStatus(_missingFilePickerPluginMessage);
    } catch (error) {
      _setStatus('Open dialog failed: $error');
    }
  }

  Future<void> _loadTypedPngPath() async {
    await _loadPngFromPath(_loadPathController.text);
  }

  Future<void> _loadPngFromPath(String path) async {
    final String rawPath = path.trim();
    if (rawPath.isEmpty) {
      _setStatus('Enter a PNG path to load.');
      return;
    }

    final File file = File(rawPath);
    if (!await file.exists()) {
      _setStatus('File not found: $rawPath');
      return;
    }

    try {
      final Uint8List bytes = await file.readAsBytes();
      final ui.Image image = await _decodeImage(bytes);
      final List<MapEntry<String, String>> textEntries = readTextEntries(bytes);
      setState(() {
        _backgroundImage = image;
        _canvasSize = Size(
          image.width.toDouble(),
          image.height.toDouble(),
        );
        _elements.clear();
        _cancelInFlightGesture();
        _savePathController.text = rawPath;
        _clearMetadataRows();
        for (final MapEntry<String, String> entry in textEntries) {
          _addMetadataRow(entry.key, entry.value);
        }
        _status = 'Loaded ${image.width}x${image.height} PNG.';
      });
    } catch (error) {
      _setStatus('Load failed: $error');
    }
  }

  Future<void> _pickAndSavePng() async {
    try {
      final FileSaveLocation? saveLocation = await getSaveLocation(
        acceptedTypeGroups: <XTypeGroup>[_pngTypeGroup],
        suggestedName: _suggestedSaveName,
      );

      if (saveLocation == null) {
        _setStatus('Save canceled.');
        return;
      }

      _savePathController.text = saveLocation.path;
      await _savePngToPath(saveLocation.path);
    } on MissingPluginException {
      _setStatus(_missingFilePickerPluginMessage);
    } catch (error) {
      _setStatus('Save dialog failed: $error');
    }
  }

  Future<void> _saveTypedPngPath() async {
    await _savePngToPath(_savePathController.text);
  }

  Future<void> _savePngToPath(String path) async {
    final String rawPath = path.trim();
    if (rawPath.isEmpty) {
      _setStatus('Enter a PNG path to save.');
      return;
    }

    try {
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      _paintScene(canvas);

      final ui.Image image = await recorder.endRecording().toImage(
            _canvasSize.width.round(),
            _canvasSize.height.round(),
          );
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        _setStatus('Save failed: PNG encoder returned no data.');
        return;
      }

      final File file = File(rawPath);
      await file.parent.create(recursive: true);
      final Uint8List plain = byteData.buffer.asUint8List();
      final Uint8List? combined = writeTextEntries(plain, _collectMetadata());
      await file.writeAsBytes(combined ?? plain);
      _setStatus(
        'Saved ${_canvasSize.width.round()}x${_canvasSize.height.round()} PNG to $rawPath',
      );
    } catch (error) {
      _setStatus('Save failed: $error');
    }
  }

  String get _suggestedSaveName {
    final String rawPath = _savePathController.text.trim();
    if (rawPath.isEmpty) {
      return 'output.png';
    }

    return rawPath.split(Platform.pathSeparator).last;
  }

  String get _missingFilePickerPluginMessage {
    return 'File picker plugin is not registered. Stop the app and run '
        'flutter clean, flutter pub get, then flutter run -d linux.';
  }

  void _undo() {
    if (_elements.isEmpty) {
      _setStatus('Nothing to undo.');
      return;
    }

    setState(() {
      _elements.removeLast();
      _status = 'Removed the last drawing operation.';
    });
  }

  void _clearDrawing() {
    setState(() {
      _elements.clear();
      _cancelInFlightGesture();
      _status = 'Cleared vector drawing layers.';
    });
  }

  void _newBlankCanvas() {
    setState(() {
      _backgroundImage = null;
      _canvasSize = _defaultCanvasSize;
      _elements.clear();
      _cancelInFlightGesture();
      _status = 'Created a blank 1024x768 canvas.';
    });
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    return completer.future;
  }

  void _setStatus(String value) {
    setState(() {
      _status = value;
    });
  }

  Color _replaceColor({
    int? red,
    int? green,
    int? blue,
  }) {
    return Color.fromARGB(
      _colorComponent(_color.a),
      red ?? _colorComponent(_color.r),
      green ?? _colorComponent(_color.g),
      blue ?? _colorComponent(_color.b),
    );
  }

  void _cancelInFlightGesture() {
    _anchorPoint = null;
    _previewPoint = null;
    _activePath = <Offset>[];
    _penDown = false;
  }

  void _handlePointerDown(PointerDownEvent event) {
    final Offset point = _clampToCanvas(event.localPosition);

    setState(() {
      if (_tool == ToolMode.path) {
        _activePath = <Offset>[point];
        _previewPoint = point;
        _penDown = true;
        return;
      }

      if (_anchorPoint == null) {
        _anchorPoint = point;
        _previewPoint = point;
        return;
      }

      _commitShape(_anchorPoint!, point);
      _anchorPoint = null;
      _previewPoint = null;
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final Offset point = _clampToCanvas(event.localPosition);

    setState(() {
      if (_tool == ToolMode.path) {
        if (!_penDown) {
          return;
        }

        if (_activePath.isEmpty || (_activePath.last - point).distance >= 0.5) {
          _activePath = <Offset>[..._activePath, point];
        }
        _previewPoint = point;
        return;
      }

      if (_anchorPoint != null) {
        _previewPoint = point;
      }
    });
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_tool != ToolMode.path || !_penDown) {
      return;
    }

    final Offset point = _clampToCanvas(event.localPosition);
    setState(() {
      if (_activePath.isEmpty || (_activePath.last - point).distance >= 0.5) {
        _activePath = <Offset>[..._activePath, point];
      }

      if (_activePath.isNotEmpty) {
        _elements.add(
          PathElement(
            points: List<Offset>.from(_activePath),
            color: _color,
            radius: _radius,
          ),
        );
        _status = 'Committed path with ${_activePath.length} points.';
      }

      _activePath = <Offset>[];
      _penDown = false;
      _previewPoint = null;
    });
  }

  void _commitShape(Offset start, Offset end) {
    switch (_tool) {
      case ToolMode.path:
        break;
      case ToolMode.rectangle:
        _elements.add(
          RectangleElement(
            start: start,
            end: end,
            color: _color,
            strokeWidth: _radius * 2,
          ),
        );
        _status = 'Committed rectangle.';
        break;
      case ToolMode.circle:
        _elements.add(
          CircleElement(
            center: start,
            edge: end,
            color: _color,
            strokeWidth: _radius * 2,
          ),
        );
        _status = 'Committed circle.';
        break;
    }
  }

  Offset _clampToCanvas(Offset point) {
    return Offset(
      point.dx.clamp(0.0, _canvasSize.width).toDouble(),
      point.dy.clamp(0.0, _canvasSize.height).toDouble(),
    );
  }

  void _paintScene(Canvas canvas) {
    if (_backgroundImage != null) {
      final Paint imagePaint = Paint();
      canvas.drawImage(_backgroundImage!, Offset.zero, imagePaint);
    }

    for (final DrawElement element in _elements) {
      element.paint(canvas);
    }
  }

  @override
  Widget build(BuildContext context) {
    final EditorPainter painter = EditorPainter(
      canvasSize: _canvasSize,
      backgroundImage: _backgroundImage,
      elements: _elements,
      activePath: _activePath,
      anchorPoint: _anchorPoint,
      previewPoint: _previewPoint,
      tool: _tool,
      color: _color,
      radius: _radius,
    );

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 320,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    right: BorderSide(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                ),
                child: Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            'GUI Survey Painter',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_canvasSize.width.round()} x ${_canvasSize.height.round()} px',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 12),
                          _StatusMessage(text: _status),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        children: <Widget>[
                          Text(
                            'Tool',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: ToolMode.values
                                .map(
                                  (ToolMode tool) => ChoiceChip(
                                    label: Text(_toolLabel(tool)),
                                    selected: _tool == tool,
                                    onSelected: (_) {
                                      setState(() {
                                        _tool = tool;
                                        _cancelInFlightGesture();
                                      });
                                    },
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Brush Radius',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Slider(
                            min: 1,
                            max: 48,
                            divisions: 47,
                            value: _radius,
                            label: _radius.round().toString(),
                            onChanged: (double value) {
                              setState(() {
                                _radius = value;
                              });
                            },
                          ),
                          Text('${_radius.round()} px'),
                          const SizedBox(height: 20),
                          Text(
                            'Color',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          _ColorChannelSlider(
                            label: 'Red',
                            color: Colors.red,
                            value: _colorComponent(_color.r).toDouble(),
                            onChanged: (double value) {
                              setState(() {
                                _color = _replaceColor(red: value.round());
                              });
                            },
                          ),
                          _ColorChannelSlider(
                            label: 'Green',
                            color: Colors.green,
                            value: _colorComponent(_color.g).toDouble(),
                            onChanged: (double value) {
                              setState(() {
                                _color = _replaceColor(green: value.round());
                              });
                            },
                          ),
                          _ColorChannelSlider(
                            label: 'Blue',
                            color: Colors.blue,
                            value: _colorComponent(_color.b).toDouble(),
                            onChanged: (double value) {
                              setState(() {
                                _color = _replaceColor(blue: value.round());
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: _color,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.black.withAlpha(28),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Filesystem',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _loadPathController,
                            decoration: const InputDecoration(
                              labelText: 'Load PNG path',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: _pickAndLoadPng,
                            child: const Text('Choose and Load PNG'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: _loadTypedPngPath,
                            child: const Text('Load Typed Path'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _savePathController,
                            decoration: const InputDecoration(
                              labelText: 'Save PNG path',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: _pickAndSavePng,
                            child: const Text('Choose Save Location'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: _saveTypedPngPath,
                            child: const Text('Save Typed Path'),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                'tEXt Metadata',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              OutlinedButton(
                                onPressed: () {
                                  setState(() {
                                    _addMetadataRow('', '');
                                  });
                                },
                                child: const Text('Add'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ..._metadataRows.asMap().entries.map(
                            (
                              MapEntry<int, List<TextEditingController>> row,
                            ) =>
                                Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: <Widget>[
                                  Expanded(
                                    child: TextField(
                                      controller: row.value[0],
                                      decoration: const InputDecoration(
                                        labelText: 'Key',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: row.value[1],
                                      decoration: const InputDecoration(
                                        labelText: 'Value',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () {
                                      setState(() {
                                        final List<TextEditingController>
                                            removed =
                                            _metadataRows.removeAt(row.key);
                                        removed[0].dispose();
                                        removed[1].dispose();
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Edit',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: <Widget>[
                              OutlinedButton(
                                onPressed: _undo,
                                child: const Text('Undo'),
                              ),
                              OutlinedButton(
                                onPressed: _clearDrawing,
                                child: const Text('Clear Drawing'),
                              ),
                              OutlinedButton(
                                onPressed: _newBlankCanvas,
                                child: const Text('Blank Canvas'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Rectangle and circle tools use two clicks. Path mode starts on mouse down and commits on mouse up.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      Color(0xFFF7F2E8),
                      Color(0xFFE6F0EA),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            blurRadius: 30,
                            offset: const Offset(0, 20),
                            color: Colors.black.withAlpha(18),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Scrollbar(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SingleChildScrollView(
                              child: MouseRegion(
                                cursor: SystemMouseCursors.precise,
                                child: Listener(
                                  onPointerDown: _handlePointerDown,
                                  onPointerMove: _handlePointerMove,
                                  onPointerUp: _handlePointerUp,
                                  onPointerCancel: (_) {
                                    if (_penDown || _anchorPoint != null) {
                                      setState(_cancelInFlightGesture);
                                    }
                                  },
                                  child: SizedBox(
                                    width: _canvasSize.width,
                                    height: _canvasSize.height,
                                    child: CustomPaint(
                                      painter: painter,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _toolLabel(ToolMode tool) {
    switch (tool) {
      case ToolMode.path:
        return 'Path';
      case ToolMode.rectangle:
        return 'Rectangle';
      case ToolMode.circle:
        return 'Circle';
    }
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _ColorChannelSlider extends StatelessWidget {
  const _ColorChannelSlider({
    required this.label,
    required this.color,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final Color color;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('$label ${value.round()}'),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            thumbColor: color,
            overlayColor: color.withAlpha(40),
          ),
          child: Slider(
            min: 0,
            max: 255,
            divisions: 255,
            value: value,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

abstract class DrawElement {
  void paint(Canvas canvas);
}

class PathElement extends DrawElement {
  PathElement({
    required this.points,
    required this.color,
    required this.radius,
  });

  final List<Offset> points;
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = radius * 2;

    if (points.isEmpty) {
      return;
    }

    if (points.length == 1) {
      canvas.drawCircle(points.first, radius, Paint()..color = color);
      return;
    }

    final Path path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final Offset point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }
}

class RectangleElement extends DrawElement {
  RectangleElement({
    required this.start,
    required this.end,
    required this.color,
    required this.strokeWidth,
  });

  final Offset start;
  final Offset end;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawRect(_normalizeRect(start, end), paint);
  }
}

class CircleElement extends DrawElement {
  CircleElement({
    required this.center,
    required this.edge,
    required this.color,
    required this.strokeWidth,
  });

  final Offset center;
  final Offset edge;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, (edge - center).distance, paint);
  }
}

class EditorPainter extends CustomPainter {
  EditorPainter({
    required this.canvasSize,
    required this.backgroundImage,
    required this.elements,
    required this.activePath,
    required this.anchorPoint,
    required this.previewPoint,
    required this.tool,
    required this.color,
    required this.radius,
  });

  final Size canvasSize;
  final ui.Image? backgroundImage;
  final List<DrawElement> elements;
  final List<Offset> activePath;
  final Offset? anchorPoint;
  final Offset? previewPoint;
  final ToolMode tool;
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    _paintCheckerboard(canvas, size);

    if (backgroundImage != null) {
      canvas.drawImage(backgroundImage!, Offset.zero, Paint());
    }

    for (final DrawElement element in elements) {
      element.paint(canvas);
    }

    if (activePath.isNotEmpty) {
      PathElement(
        points: activePath,
        color: color.withAlpha(180),
        radius: radius,
      ).paint(canvas);
    }

    if (anchorPoint != null && previewPoint != null) {
      switch (tool) {
        case ToolMode.path:
          break;
        case ToolMode.rectangle:
          RectangleElement(
            start: anchorPoint!,
            end: previewPoint!,
            color: color.withAlpha(180),
            strokeWidth: radius * 2,
          ).paint(canvas);
          break;
        case ToolMode.circle:
          CircleElement(
            center: anchorPoint!,
            edge: previewPoint!,
            color: color.withAlpha(180),
            strokeWidth: radius * 2,
          ).paint(canvas);
          break;
      }
    }

    if (anchorPoint != null) {
      canvas.drawCircle(
        anchorPoint!,
        math.max(radius, 4),
        Paint()..color = color.withAlpha(200),
      );
    }
  }

  void _paintCheckerboard(Canvas canvas, Size size) {
    const double tile = 24;
    final Paint light = Paint()..color = const Color(0xFFF6F2EC);
    final Paint dark = Paint()..color = const Color(0xFFE0D7CA);

    for (double y = 0; y < size.height; y += tile) {
      for (double x = 0; x < size.width; x += tile) {
        final bool useLight = ((x / tile).floor() + (y / tile).floor()).isEven;
        canvas.drawRect(
          Rect.fromLTWH(x, y, tile, tile),
          useLight ? light : dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(EditorPainter oldDelegate) {
    return true;
  }
}

Rect _normalizeRect(Offset start, Offset end) {
  return Rect.fromLTRB(
    math.min(start.dx, end.dx),
    math.min(start.dy, end.dy),
    math.max(start.dx, end.dx),
    math.max(start.dy, end.dy),
  );
}

int _colorComponent(double value) {
  return (value * 255).round().clamp(0, 255);
}
