import 'package:flutter/foundation.dart';

import 'paint_canvas.dart';

/// The default duration for a newly created frame.
const defaultFrameDuration = Duration(milliseconds: 500);

/// The default frames-per-second for export.
const defaultFps = 12.0;

/// Represents one frame in the animation timeline.
///
/// Each frame holds its own list of [strokes] and a [displayDuration] that
/// controls how long the frame is shown during video export.
class Frame {
  final String id;
  final List<Stroke> strokes;
  final Duration displayDuration;

  Frame({
    required this.id,
    this.strokes = const [],
    this.displayDuration = defaultFrameDuration,
  });

  /// Creates a copy with optionally replaced fields.
  Frame copyWith({
    String? id,
    List<Stroke>? strokes,
    Duration? displayDuration,
  }) {
    return Frame(
      id: id ?? this.id,
      strokes: strokes ?? this.strokes,
      displayDuration: displayDuration ?? this.displayDuration,
    );
  }
}

/// Manages the list of animation frames and the currently selected frame.
///
/// Extends [ChangeNotifier] so that the timeline and canvas widgets can listen
/// for changes.
class MovieController extends ChangeNotifier {
  final List<Frame> _frames = [];
  int _currentFrameIndex = -1;
  double _fps = defaultFps;

  /// The list of all frames in the timeline.
  List<Frame> get frames => List.unmodifiable(_frames);

  /// The number of frames.
  int get frameCount => _frames.length;

  /// The index of the currently selected frame, or -1 if there are no frames.
  int get currentFrameIndex => _currentFrameIndex;

  /// The FPS used for video export (frames per second).
  double get fps => _fps;

  /// Whether there is a currently selected frame.
  bool get hasCurrentFrame => _currentFrameIndex >= 0 && _currentFrameIndex < _frames.length;

  /// The currently selected frame, or `null` if there are no frames.
  Frame? get currentFrame =>
      hasCurrentFrame ? _frames[_currentFrameIndex] : null;

  /// The total number of strokes across all frames.
  int get totalStrokeCount =>
      _frames.fold<int>(0, (sum, f) => sum + f.strokes.length);

  /// Whether there are any frames.
  bool get hasFrames => _frames.isNotEmpty;

  /// Sets the FPS for export.
  void setFps(double newFps) {
    final clamped = newFps.clamp(1.0, 60.0);
    if ((_fps - clamped).abs() < 0.05) return;
    _fps = clamped;
    notifyListeners();
  }

  /// Adds a new frame with the given [strokes] and [duration].
  ///
  /// The new frame becomes the currently selected frame.
  void addFrame({List<Stroke> strokes = const [], Duration? duration}) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _frames.add(Frame(
      id: id,
      strokes: strokes,
      displayDuration: duration ?? defaultFrameDuration,
    ));
    _currentFrameIndex = _frames.length - 1;
    notifyListeners();
  }

  /// Removes the frame at [index].
  ///
  /// If the removed frame was the currently selected frame, selection moves to
  /// the nearest available frame. If the last frame is removed, selection is
  /// cleared.
  void removeFrame(int index) {
    if (index < 0 || index >= _frames.length) return;
    _frames.removeAt(index);
    if (_frames.isEmpty) {
      _currentFrameIndex = -1;
    } else if (_currentFrameIndex >= _frames.length) {
      _currentFrameIndex = _frames.length - 1;
    } else if (_currentFrameIndex > index) {
      _currentFrameIndex--;
    }
    notifyListeners();
  }

  /// Removes all frames.
  void clearFrames() {
    if (_frames.isEmpty) return;
    _frames.clear();
    _currentFrameIndex = -1;
    notifyListeners();
  }

  /// Selects the frame at [index].
  void selectFrame(int index) {
    if (index < 0 || index >= _frames.length) return;
    if (_currentFrameIndex == index) return;
    _currentFrameIndex = index;
    notifyListeners();
  }

  /// Sets the display duration for the frame at [index].
  void setFrameDuration(int index, Duration duration) {
    if (index < 0 || index >= _frames.length) return;
    _frames[index] = _frames[index].copyWith(displayDuration: duration);
    notifyListeners();
  }

  /// Saves [strokes] to the currently selected frame.
  ///
  /// Does nothing if no frame is selected.
  void updateCurrentFrameStrokes(List<Stroke> strokes) {
    if (!hasCurrentFrame) return;
    _frames[_currentFrameIndex] =
        _frames[_currentFrameIndex].copyWith(strokes: strokes);
    notifyListeners();
  }
}
