import 'package:flutter/material.dart';

/// Represents a single stroke drawn by the user.
class Stroke {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  Stroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });
}

/// Controller for managing strokes and undo/clear operations.
class PaintCanvasController extends ChangeNotifier {
  final List<Stroke> _strokes = [];
  final List<Stroke> _redoStack = [];

  List<Stroke> get strokes => List.unmodifiable(_strokes);
  bool get canUndo => _strokes.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void addStroke(Stroke stroke) {
    _strokes.add(stroke);
    _redoStack.clear();
    notifyListeners();
  }

  void undo() {
    if (_strokes.isNotEmpty) {
      _redoStack.add(_strokes.removeLast());
      notifyListeners();
    }
  }

  void redo() {
    if (_redoStack.isNotEmpty) {
      _strokes.add(_redoStack.removeLast());
      notifyListeners();
    }
  }

  void clear() {
    if (_strokes.isNotEmpty) {
      _strokes.clear();
      _redoStack.clear();
      notifyListeners();
    }
  }

  /// Replaces all strokes (used when loading a file).
  void replaceStrokes(List<Stroke> newStrokes) {
    _strokes.clear();
    _strokes.addAll(newStrokes);
    _redoStack.clear();
    notifyListeners();
  }
}

/// The drawing canvas that handles pointer input across all platforms.
class PaintCanvas extends StatefulWidget {
  final PaintCanvasController controller;
  final Color color;
  final double strokeWidth;

  const PaintCanvas({
    super.key,
    required this.controller,
    required this.color,
    required this.strokeWidth,
  });

  @override
  State<PaintCanvas> createState() => _PaintCanvasState();
}

class _PaintCanvasState extends State<PaintCanvas> {
  Stroke? _currentStroke;

  void _onPointerDown(PointerDownEvent event) {
    final box = context.findRenderObject() as RenderBox;
    final localPosition = box.globalToLocal(event.position);

    _currentStroke = Stroke(
      points: [localPosition],
      color: widget.color,
      strokeWidth: widget.strokeWidth,
    );
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_currentStroke == null) return;

    final box = context.findRenderObject() as RenderBox;
    final localPosition = box.globalToLocal(event.position);

    setState(() {
      _currentStroke!.points.add(localPosition);
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_currentStroke == null) return;

    if (_currentStroke!.points.length == 1) {
      // Single tap: add a tiny dot so it's visible.
      final p = _currentStroke!.points.first;
      _currentStroke!.points.add(Offset(p.dx + 0.5, p.dy + 0.5));
    }

    widget.controller.addStroke(_currentStroke!);
    _currentStroke = null;
    setState(() {});
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _currentStroke = null;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: CustomPaint(
            painter: _CanvasPainter(
              strokes: widget.controller.strokes,
              currentStroke: _currentStroke,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

/// Custom painter that renders all strokes on the canvas.
class _CanvasPainter extends CustomPainter {
  final List<Stroke> strokes;
  final Stroke? currentStroke;

  _CanvasPainter({
    required this.strokes,
    this.currentStroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fill background with white (or transparent grid for dark mode).
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    // Draw completed strokes.
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }

    // Draw the stroke currently in progress.
    if (currentStroke != null) {
      _drawStroke(canvas, currentStroke!);
    }
  }

  void _drawStroke(Canvas canvas, Stroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    if (stroke.points.length == 1) {
      // Draw a single dot.
      canvas.drawCircle(stroke.points.first, stroke.strokeWidth / 2, paint);
      return;
    }

    final path = Path();
    path.moveTo(stroke.points.first.dx, stroke.points.first.dy);

    for (var i = 1; i < stroke.points.length - 1; i++) {
      final p0 = stroke.points[i];
      final p1 = stroke.points[i + 1];
      final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
    }

    final last = stroke.points.last;
    path.lineTo(last.dx, last.dy);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) => true;
}
