using System;
using System.Collections.Generic;
using System.IO;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Media;
using Avalonia.Media.Imaging;

namespace AvaloniaPngEditor.Controls;

public enum DrawMode { Path, Circle, Rectangle }

/// The drawing surface (spec Feature: 2D Canvas Drawing). Holds a base bitmap
/// (blank or loaded PNG) plus a list of vector draw ops rendered over it. The
/// control is sized 1:1 to the image and hosted in a ScrollViewer, so pointer
/// coordinates map directly to image pixels.
public sealed class CanvasControl : Control
{
    private abstract record DrawOp;
    private sealed record StrokeOp(List<Point> Points, Color Color, double Width) : DrawOp;
    private sealed record CircleOp(Point Center, double Radius, Color Color, double Thickness) : DrawOp;
    private sealed record RectOp(Rect Bounds, Color Color, double Thickness) : DrawOp;

    private Bitmap? _base;
    private PixelSize _size = new(800, 600);
    private readonly List<DrawOp> _ops = new();

    // Interaction state.
    private StrokeOp? _currentStroke;   // path mode: pen currently down
    private Point? _pendingPoint;       // circle/rect: first click captured
    private Point _cursor;
    private bool _hasCursor;

    private bool _modified;

    public event EventHandler? ModifiedChanged;

    public DrawMode Mode { get; private set; } = DrawMode.Path;
    public Color PenColor { get; set; } = Colors.Black;
    public double PenRadius { get; set; } = 4;

    public bool IsModified
    {
        get => _modified;
        private set
        {
            if (_modified != value)
            {
                _modified = value;
                ModifiedChanged?.Invoke(this, EventArgs.Empty);
            }
        }
    }

    public CanvasControl() => NewImage(800, 600);

    public void SetMode(DrawMode mode)
    {
        Mode = mode;
        ResetInteraction();
        InvalidateVisual();
    }

    public void NewImage(int width, int height)
    {
        _size = new PixelSize(Math.Max(1, width), Math.Max(1, height));
        _base = CreateFilled(_size, Brushes.White);
        _ops.Clear();
        ResetInteraction();
        InvalidateMeasure();
        InvalidateVisual();
        IsModified = false;
    }

    public void SetImage(Bitmap bitmap)
    {
        _base = bitmap;
        _size = bitmap.PixelSize;
        _ops.Clear();
        ResetInteraction();
        InvalidateMeasure();
        InvalidateVisual();
        IsModified = false;
    }

    public void MarkSaved() => IsModified = false;

    /// Rasterize base + ops to PNG bytes (without tEXt metadata; PngText adds it).
    public byte[] ExportPng()
    {
        var rtb = new RenderTargetBitmap(_size, new Vector(96, 96));
        using (var ctx = rtb.CreateDrawingContext())
        {
            DrawScene(ctx);
        }
        using var ms = new MemoryStream();
        rtb.Save(ms);
        return ms.ToArray();
    }

    protected override Size MeasureOverride(Size availableSize) =>
        new(_size.Width, _size.Height);

    public override void Render(DrawingContext context)
    {
        DrawScene(context);

        // Live preview of the in-progress shape.
        if (_currentStroke != null)
        {
            DrawStroke(context, _currentStroke);
        }
        else if (_pendingPoint is { } start && _hasCursor)
        {
            var pen = new Pen(new SolidColorBrush(PenColor), Math.Max(1, PenRadius));
            if (Mode == DrawMode.Circle)
            {
                double r = Distance(start, _cursor);
                context.DrawEllipse(null, pen, start, r, r);
            }
            else if (Mode == DrawMode.Rectangle)
            {
                context.DrawRectangle(null, pen, Normalize(start, _cursor));
            }
        }
    }

    private void DrawScene(DrawingContext ctx)
    {
        if (_base != null)
            ctx.DrawImage(_base, new Rect(0, 0, _size.Width, _size.Height));
        foreach (var op in _ops)
            DrawOp_(ctx, op);
    }

    private static void DrawOp_(DrawingContext ctx, DrawOp op)
    {
        switch (op)
        {
            case StrokeOp s:
                DrawStroke(ctx, s);
                break;
            case CircleOp c:
                ctx.DrawEllipse(null, new Pen(new SolidColorBrush(c.Color), c.Thickness),
                    c.Center, c.Radius, c.Radius);
                break;
            case RectOp r:
                ctx.DrawRectangle(null, new Pen(new SolidColorBrush(r.Color), r.Thickness), r.Bounds);
                break;
        }
    }

    private static void DrawStroke(DrawingContext ctx, StrokeOp s)
    {
        var brush = new SolidColorBrush(s.Color);
        if (s.Points.Count == 1)
        {
            double rad = s.Width / 2;
            ctx.DrawEllipse(brush, null, s.Points[0], rad, rad);
            return;
        }
        var pen = new Pen(brush, s.Width, lineCap: PenLineCap.Round, lineJoin: PenLineJoin.Round);
        for (int i = 1; i < s.Points.Count; i++)
            ctx.DrawLine(pen, s.Points[i - 1], s.Points[i]);
    }

    protected override void OnPointerPressed(PointerPressedEventArgs e)
    {
        base.OnPointerPressed(e);
        Point pos = e.GetPosition(this);

        switch (Mode)
        {
            case DrawMode.Path:
                _currentStroke = new StrokeOp(new List<Point> { pos }, PenColor, Math.Max(1, PenRadius * 2));
                break;

            case DrawMode.Circle:
            case DrawMode.Rectangle:
                if (_pendingPoint is null)
                {
                    _pendingPoint = pos;
                }
                else
                {
                    if (Mode == DrawMode.Circle)
                        _ops.Add(new CircleOp(_pendingPoint.Value, Distance(_pendingPoint.Value, pos),
                            PenColor, Math.Max(1, PenRadius)));
                    else
                        _ops.Add(new RectOp(Normalize(_pendingPoint.Value, pos), PenColor, Math.Max(1, PenRadius)));
                    _pendingPoint = null;
                    IsModified = true;
                }
                break;
        }
        InvalidateVisual();
    }

    protected override void OnPointerMoved(PointerEventArgs e)
    {
        base.OnPointerMoved(e);
        _cursor = e.GetPosition(this);
        _hasCursor = true;

        if (_currentStroke != null)
        {
            _currentStroke.Points.Add(_cursor);
            InvalidateVisual();
        }
        else if (_pendingPoint != null)
        {
            InvalidateVisual(); // update circle/rect preview
        }
    }

    protected override void OnPointerReleased(PointerReleasedEventArgs e)
    {
        base.OnPointerReleased(e);
        if (_currentStroke != null)
        {
            _ops.Add(_currentStroke);
            _currentStroke = null;
            IsModified = true;
            InvalidateVisual();
        }
    }

    private void ResetInteraction()
    {
        _currentStroke = null;
        _pendingPoint = null;
    }

    private static Bitmap CreateFilled(PixelSize size, IBrush brush)
    {
        var rtb = new RenderTargetBitmap(size, new Vector(96, 96));
        using var ctx = rtb.CreateDrawingContext();
        ctx.FillRectangle(brush, new Rect(0, 0, size.Width, size.Height));
        return rtb;
    }

    private static double Distance(Point a, Point b)
    {
        double dx = a.X - b.X, dy = a.Y - b.Y;
        return Math.Sqrt(dx * dx + dy * dy);
    }

    private static Rect Normalize(Point a, Point b) =>
        new(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y), Math.Abs(a.X - b.X), Math.Abs(a.Y - b.Y));
}
