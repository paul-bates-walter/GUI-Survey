import 'dart:typed_data';

const List<int> _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

int _crc32(List<int> data) {
  int crc = 0xffffffff;
  for (final int byte in data) {
    crc ^= byte & 0xff;
    for (int bit = 0; bit < 8; bit++) {
      final int mask = (crc & 1) != 0 ? 0xedb88320 : 0;
      crc = (crc >> 1) ^ mask;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

int _readU32(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

void _writeU32(List<int> out, int value) {
  out.add((value >> 24) & 0xff);
  out.add((value >> 16) & 0xff);
  out.add((value >> 8) & 0xff);
  out.add(value & 0xff);
}

bool _isPng(Uint8List bytes) {
  if (bytes.length < 8) {
    return false;
  }
  for (int i = 0; i < 8; i++) {
    if (bytes[i] != _pngSignature[i]) {
      return false;
    }
  }
  return true;
}

List<List<int>>? _chunkRanges(Uint8List png) {
  if (!_isPng(png)) {
    return null;
  }
  final List<List<int>> chunks = <List<int>>[];
  int offset = 8;
  while (offset + 12 <= png.length) {
    final int dataLen = _readU32(png, offset);
    final int total = 12 + dataLen;
    if (offset + total > png.length) {
      return null;
    }
    chunks.add(<int>[offset, total]);
    final String kind = String.fromCharCodes(png, offset + 4, offset + 8);
    offset += total;
    if (kind == 'IEND') {
      return chunks;
    }
  }
  return null;
}

String _latin1String(Uint8List bytes, int start, int end) {
  return String.fromCharCodes(bytes.sublist(start, end));
}

List<int> _latin1Bytes(String text) {
  final List<int> out = <int>[];
  for (final int code in text.codeUnits) {
    if (code > 0 && code < 256) {
      out.add(code);
    }
  }
  return out;
}

List<MapEntry<String, String>> readTextEntries(Uint8List png) {
  final List<List<int>>? chunks = _chunkRanges(png);
  if (chunks == null) {
    return <MapEntry<String, String>>[];
  }
  final List<MapEntry<String, String>> entries = <MapEntry<String, String>>[];
  for (final List<int> chunk in chunks) {
    final int start = chunk[0];
    final int total = chunk[1];
    final String kind = String.fromCharCodes(png, start + 4, start + 8);
    if (kind != 'tEXt') {
      continue;
    }
    final int dataStart = start + 8;
    final int dataEnd = start + total - 4;
    int split = -1;
    for (int i = dataStart; i < dataEnd; i++) {
      if (png[i] == 0) {
        split = i;
        break;
      }
    }
    if (split < 0) {
      continue;
    }
    entries.add(MapEntry<String, String>(
      _latin1String(png, dataStart, split),
      _latin1String(png, split + 1, dataEnd),
    ));
  }
  return entries;
}

List<int> _textChunk(String key, String value) {
  List<int> keyword = _latin1Bytes(key.trim());
  if (keyword.length > 79) {
    keyword = keyword.sublist(0, 79);
  }
  final List<int> body = <int>[
    ...'tEXt'.codeUnits,
    ...keyword,
    0,
    ..._latin1Bytes(value),
  ];
  final List<int> chunk = <int>[];
  _writeU32(chunk, body.length - 4);
  chunk.addAll(body);
  _writeU32(chunk, _crc32(body));
  return chunk;
}

Uint8List? writeTextEntries(
  Uint8List png,
  List<MapEntry<String, String>> entries,
) {
  final List<List<int>>? chunks = _chunkRanges(png);
  if (chunks == null) {
    return null;
  }
  final List<int> out = <int>[..._pngSignature];
  for (final List<int> chunk in chunks) {
    final int start = chunk[0];
    final int total = chunk[1];
    final String kind = String.fromCharCodes(png, start + 4, start + 8);
    if (kind == 'tEXt') {
      continue;
    }
    if (kind == 'IEND') {
      for (final MapEntry<String, String> entry in entries) {
        if (entry.key.trim().isEmpty) {
          continue;
        }
        out.addAll(_textChunk(entry.key, entry.value));
      }
    }
    out.addAll(png.sublist(start, start + total));
  }
  return Uint8List.fromList(out);
}
