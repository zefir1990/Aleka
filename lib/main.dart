import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'paint_canvas.dart';
import 'toolbar.dart';
import 'aleka_file.dart';
import 'movie_controller.dart';
import 'movie_timeline.dart';
import 'video_export.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const AlekaApp());
}

class AlekaApp extends StatelessWidget {
  const AlekaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aleka Paint',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const PaintScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Injectable I/O function types — default to real file_picker implementations
// but can be replaced with mocks during testing.
// ---------------------------------------------------------------------------
typedef SaveStrokesFn = Future<bool> Function(List<Stroke> strokes);
typedef LoadStrokesFn = Future<List<Stroke>?> Function();
typedef CapturePngFn = Future<Uint8List?> Function(GlobalKey key);
typedef SavePngFn = Future<bool> Function(Uint8List bytes);
typedef SaveVideoFn = Future<bool> Function(Uint8List bytes);

class PaintScreen extends StatefulWidget {
  final SaveStrokesFn? saveStrokes;
  final LoadStrokesFn? loadStrokes;
  final CapturePngFn? capturePngOverride;
  final SavePngFn? savePngOverride;
  final SaveVideoFn? saveVideoOverride;

  const PaintScreen({
    super.key,
    this.saveStrokes,
    this.loadStrokes,
    this.capturePngOverride,
    this.savePngOverride,
    this.saveVideoOverride,
  });

  @override
  State<PaintScreen> createState() => _PaintScreenState();
}

class _PaintScreenState extends State<PaintScreen> {
  Color _currentColor = Colors.black;
  double _strokeWidth = 3.0;
  final PaintCanvasController _canvasController = PaintCanvasController();
  final GlobalKey _canvasRepaintKey = GlobalKey();
  final MovieController _movieController = MovieController();
  bool _movieMode = false;

  // Whether we are currently loading frame strokes (suppress saving during
  // setState triggered by frame selection).
  bool _loadingFrameStrokes = false;

  @override
  void initState() {
    super.initState();
    _movieController.addListener(_onMovieControllerChanged);
  }

  @override
  void dispose() {
    _movieController.removeListener(_onMovieControllerChanged);
    _movieController.dispose();
    super.dispose();
  }

  /// Loads frame strokes onto the canvas when playback advances frames.
  void _onMovieControllerChanged() {
    if (_movieController.isPlaying && _movieController.hasCurrentFrame) {
      _loadFrameToCanvas(_movieController.currentFrame!);
    }
  }

  void _onUndo() {
    _canvasController.undo();
    if (_movieMode) {
      _saveCanvasToCurrentFrame();
    }
  }

  void _onClear() {
    _canvasController.clear();
    if (_movieMode) {
      _saveCanvasToCurrentFrame();
    }
  }

  SaveStrokesFn get _saveFn => widget.saveStrokes ?? saveToFile;
  LoadStrokesFn get _loadFn => widget.loadStrokes ?? loadFromFile;
  CapturePngFn get _captureFn => widget.capturePngOverride ?? capturePng;
  SavePngFn get _savePngFn => widget.savePngOverride ?? savePngToFile;
  SaveVideoFn get _saveVideoFn => widget.saveVideoOverride ?? saveVideoToFile;

  // ---------------------------------------------------------------------------
  // Movie mode helpers
  // ---------------------------------------------------------------------------

  void _toggleMovieMode() {
    setState(() {
      _movieMode = !_movieMode;
    });

    if (_movieMode) {
      // Just entered movie mode — save current strokes as the first frame if
      // the canvas is not empty and there are no frames yet.
      if (_canvasController.strokes.isNotEmpty && !_movieController.hasFrames) {
        _addFrameFromCanvas();
      }
    }
  }

  /// Saves the current canvas strokes to the currently selected frame.
  void _saveCanvasToCurrentFrame() {
    if (_loadingFrameStrokes) return;
    _movieController.updateCurrentFrameStrokes(_canvasController.strokes);
  }

  void _addFrameFromCanvas() {
    _movieController.addFrame(strokes: List.from(_canvasController.strokes));
    // Clear canvas for the next frame.
    _canvasController.clear();
    if (!mounted) return;
    _showSnackBar('Frame ${_movieController.frameCount} added.');
  }

  void _onAddFrame() {
    _addFrameFromCanvas();
  }

  void _onRemoveFrame() {
    if (!_movieController.hasCurrentFrame) return;
    final index = _movieController.currentFrameIndex;
    _movieController.removeFrame(index);
    if (!mounted) return;

    if (_movieController.hasCurrentFrame) {
      // Load the newly selected frame onto the canvas.
      _loadFrameToCanvas(_movieController.currentFrame!);
    } else {
      _canvasController.clear();
    }
    _showSnackBar('Frame removed.');
  }

  void _onSelectFrame(int index) {
    // Pause playback if the user manually selects a frame.
    if (_movieController.isPlaying) _movieController.pause();

    // Ignore if already on this frame.
    if (index == _movieController.currentFrameIndex) return;

    // Save current canvas strokes to the currently selected frame first.
    _saveCanvasToCurrentFrame();

    _movieController.selectFrame(index);
    final frame = _movieController.currentFrame;
    if (frame != null) {
      _loadFrameToCanvas(frame);
    }
  }

  void _onPlayPause() {
    _movieController.togglePlayPause();
    // If starting playback and there's a current frame, load it.
    if (_movieController.isPlaying && _movieController.hasCurrentFrame) {
      _loadFrameToCanvas(_movieController.currentFrame!);
    }
  }

  void _loadFrameToCanvas(Frame frame) {
    _loadingFrameStrokes = true;
    _canvasController.replaceStrokes(List.from(frame.strokes));
    _loadingFrameStrokes = false;
  }

  // ---------------------------------------------------------------------------
  // I/O actions
  // ---------------------------------------------------------------------------

  Future<void> _onSave() async {
    final strokes = _canvasController.strokes;
    if (strokes.isEmpty) {
      _showSnackBar('Nothing to save — canvas is empty.');
      return;
    }
    final ok = await _saveFn(strokes);
    if (!mounted) return;
    _showSnackBar(ok ? 'Saved as .aleka' : 'Save cancelled or failed.');
  }

  Future<void> _onLoad() async {
    final loaded = await _loadFn();
    if (!mounted) return;
    if (loaded == null) {
      _showSnackBar('Load cancelled or file is invalid.');
      return;
    }
    _canvasController.replaceStrokes(loaded);
    _showSnackBar('Loaded ${loaded.length} stroke${loaded.length == 1 ? '' : 's'}.');
  }

  Future<void> _onExport() async {
    if (_movieMode) {
      await _exportVideo();
    } else {
      await _exportPng();
    }
  }

  Future<void> _exportPng() async {
    final bytes = await _captureFn(_canvasRepaintKey);
    if (!mounted) return;
    if (bytes == null) {
      _showSnackBar('Export failed — could not capture canvas.');
      return;
    }
    final ok = await _savePngFn(bytes);
    if (!mounted) return;
    _showSnackBar(ok ? 'Exported as PNG' : 'Export cancelled or failed.');
  }

  Future<void> _exportVideo() async {
    if (!_movieController.hasFrames) {
      _showSnackBar('Nothing to export — no frames in timeline.');
      return;
    }

    _showSnackBar('Rendering frames…');

    // Save current canvas strokes to the current frame before exporting.
    _saveCanvasToCurrentFrame();

    final frameImages = <Uint8List>[];
    final delaysMs = <int>[];

    // Render each frame by loading its strokes onto the canvas, capturing,
    // and collecting the PNG bytes.
    final currentIndex = _movieController.currentFrameIndex;
    for (var i = 0; i < _movieController.frameCount; i++) {
      final frame = _movieController.frames[i];
      _loadFrameToCanvas(frame);

      // Let the canvas repaint.
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final pngBytes = await _captureFn(_canvasRepaintKey);
      if (pngBytes != null) {
        frameImages.add(pngBytes);
        delaysMs.add(frame.displayDuration.inMilliseconds);
      }
    }

    // Restore the previously selected frame.
    if (currentIndex >= 0 && currentIndex < _movieController.frameCount) {
      _loadFrameToCanvas(_movieController.frames[currentIndex]);
    }

    if (!mounted) return;

    if (frameImages.isEmpty) {
      _showSnackBar('Export failed — could not capture frames.');
      return;
    }

    // Encode to MP4 (desktop) or WebM (web) and save.
    final videoBytes = await encodeVideo(
      pngFrames: frameImages,
      delaysMs: delaysMs,
      fps: _movieController.fps,
    );

    if (!mounted) return;

    if (videoBytes == null) {
      _showSnackBar(
        kIsWeb
            ? 'Video export failed — see console for details.'
            : 'Video export failed — is ffmpeg installed?',
      );
      return;
    }

    final ok = await _saveVideoFn(videoBytes);
    if (!mounted) return;
    _showSnackBar(
      ok
          ? 'Exported as video (${_movieController.frameCount} frames)'
          : 'Export cancelled or failed.',
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          PaintToolbar(
            currentColor: _currentColor,
            strokeWidth: _strokeWidth,
            onColorChanged: (color) {
              setState(() => _currentColor = color);
            },
            onStrokeWidthChanged: (width) {
              setState(() => _strokeWidth = width);
            },
            onUndo: _onUndo,
            onClear: _onClear,
            onSave: _onSave,
            onLoad: _onLoad,
            onExport: _onExport,
            movieMode: _movieMode,
            onToggleMovieMode: _toggleMovieMode,
          ),
          Expanded(
            child: RepaintBoundary(
              key: _canvasRepaintKey,
              child: PaintCanvas(
                controller: _canvasController,
                color: _currentColor,
                strokeWidth: _strokeWidth,
              ),
            ),
          ),
          if (_movieMode)
            MovieTimeline(
              controller: _movieController,
              onAddFrame: _onAddFrame,
              onRemoveFrame: _onRemoveFrame,
              onFrameSelected: _onSelectFrame,
              onPlayPause: _onPlayPause,
            ),
        ],
      ),
    );
  }
}
