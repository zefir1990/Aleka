import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

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
      title: 'Aleka',
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
typedef SaveAlekaFn = Future<bool> Function(String content);
typedef LoadAlekaFn = Future<String?> Function();

class PaintScreen extends StatefulWidget {
  final SaveStrokesFn? saveStrokes;
  final LoadStrokesFn? loadStrokes;
  final CapturePngFn? capturePngOverride;
  final SavePngFn? savePngOverride;
  final SaveVideoFn? saveVideoOverride;
  final EncodeVideoFn? videoEncodeOverride;
  final SaveAlekaFn? saveAlekaOverride;
  final LoadAlekaFn? loadAlekaOverride;

  const PaintScreen({
    super.key,
    this.saveStrokes,
    this.loadStrokes,
    this.capturePngOverride,
    this.savePngOverride,
    this.saveVideoOverride,
    this.videoEncodeOverride,
    this.saveAlekaOverride,
    this.loadAlekaOverride,
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
  bool _fillTool = false;

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
  CapturePngFn get _captureFn => widget.capturePngOverride ?? capturePng;
  SavePngFn get _savePngFn => widget.savePngOverride ?? savePngToFile;
  SaveVideoFn get _saveVideoFn => widget.saveVideoOverride ?? saveVideoToFile;
  SaveAlekaFn get _saveAlekaFn => widget.saveAlekaOverride ?? saveAlekaContent;
  LoadAlekaFn get _loadAlekaFn => widget.loadAlekaOverride ?? loadAlekaContent;

  // ---------------------------------------------------------------------------
  // Movie mode helpers
  // ---------------------------------------------------------------------------

  void _toggleMovieMode() {
    setState(() {
      _movieMode = !_movieMode;
      if (_movieMode) {
        // Fill tool and movie mode are mutually exclusive.
        _fillTool = false;
      }
    });

    if (_movieMode) {
      // Just entered movie mode — capture current strokes as the first frame
      // without clearing the canvas so the user still sees their content.
      if (_canvasController.strokes.isNotEmpty) {
        _movieController.addFrame(
          strokes: List.from(_canvasController.strokes),
        );
      }
    }
  }

  void _toggleFillTool() {
    setState(() {
      _fillTool = !_fillTool;
      if (_fillTool) {
        // Fill tool and movie mode are mutually exclusive.
        _movieMode = false;
      }
    });
  }

  /// Flood-fills the canvas at [localPosition] with the current color.
  Future<void> _onFillTap(Offset localPosition) async {
    final fillRgba = _colorToRgba(_currentColor);

    // Fast path: if the canvas has no strokes, just fill the entire background
    // with a solid-colour image — no need to capture or run BFS.
    if (_canvasController.strokes.isEmpty) {
      final solid = await _createSolidFill(fillRgba);
      if (!mounted) return;
      if (solid != null) {
        _canvasController.setFillImage(solid);
        if (_movieMode) _saveCanvasToCurrentFrame();
      }
      return;
    }

    // 1. Capture the current canvas as PNG bytes at 1× resolution so that
    //    logical tap coordinates map 1:1 to image pixels.
    final pngBytes = await capturePng(_canvasRepaintKey, pixelRatio: 1.0);
    if (!mounted) return;
    if (pngBytes == null) {
      _showSnackBar('Fill failed — could not capture canvas.', isError: true);
      return;
    }

    // 2. Decode the PNG for pixel manipulation.
    final image = img.decodePng(pngBytes);
    if (image == null) {
      _showSnackBar('Fill failed — could not decode canvas image.', isError: true);
      return;
    }

    // 3. Map logical tap position to image-pixel coordinates (pixelRatio 1.0
    //    means logical pixels == image pixels).
    final px = localPosition.dx.round();
    final py = localPosition.dy.round();

    // Bounds check.
    if (px < 0 || py < 0 || px >= image.width || py >= image.height) {
      _showSnackBar('Fill failed — tap is outside canvas bounds.', isError: true);
      return;
    }

    // 4. Get the target color at the tap point.
    final targetPixel = image.getPixel(px, py);

    // If the target already matches the fill colour, there is nothing to do.
    final targetRgba = _pixelToRgba(targetPixel);
    if (_colorDistance(targetRgba, fillRgba) <= 5) {
      return;
    }

    // 5. BFS flood fill with tolerance (handles anti-aliased stroke edges).
    final filledCount = _floodFill(image, px, py, targetRgba, fillRgba);

    if (filledCount == 0) {
      return; // No pixels matched the target colour.
    }

    // 6. Encode the modified image back to PNG bytes…
    final filledPng = img.encodePng(image);

    // 7. …and decode as a ui.Image so the painter can draw it.
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(filledPng));
    final frameInfo = await codec.getNextFrame();
    final uiImage = frameInfo.image;

    if (!mounted) return;

    // 8. Store in the controller so it appears beneath strokes.
    _canvasController.setFillImage(uiImage);

    // If in movie mode, save the fill state to the current frame.
    if (_movieMode) {
      _saveCanvasToCurrentFrame();
    }
  }

  /// Creates a solid-colour 1×1 [ui.Image] from [fillRgba].
  ///
  /// A 1×1 image is enough — the painter stretches it to fill the canvas.
  Future<ui.Image?> _createSolidFill(_Rgba fillRgba) async {
    final solidImage = img.Image(width: 1, height: 1);
    solidImage.setPixelRgba(0, 0, fillRgba.r, fillRgba.g, fillRgba.b, fillRgba.a);
    final pngBytes = img.encodePng(solidImage);
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(pngBytes));
    final frameInfo = await codec.getNextFrame();
    return frameInfo.image;
  }

  /// BFS flood fill: replaces pixels whose colour is within [kTolerance]
  /// distance of [target] with [fill], using 4-way connectivity.
  ///
  /// Returns the number of pixels that were filled.
  static const _kFillTolerance = 1000;

  int _floodFill(
    img.Image image,
    int startX,
    int startY,
    _Rgba target,
    _Rgba fill,
  ) {
    final width = image.width;
    final height = image.height;

    final queue = Queue<(int, int)>();
    final visited = <int>{};
    var filled = 0;

    queue.add((startX, startY));
    visited.add(startY * width + startX);

    while (queue.isNotEmpty) {
      final (x, y) = queue.removeFirst();

      image.setPixelRgba(x, y, fill.r, fill.g, fill.b, fill.a);
      filled++;

      // Check 4 neighbours.
      void tryAdd(int nx, int ny) {
        if (nx < 0 || ny < 0 || nx >= width || ny >= height) return;
        final key = ny * width + nx;
        if (visited.contains(key)) return;
        final p = image.getPixel(nx, ny);
        final c = _Rgba(p.r.toInt(), p.g.toInt(), p.b.toInt(), p.a.toInt());
        if (_colorDistance(c, target) > _kFillTolerance) return;
        visited.add(key);
        queue.add((nx, ny));
      }

      tryAdd(x - 1, y);
      tryAdd(x + 1, y);
      tryAdd(x, y - 1);
      tryAdd(x, y + 1);
    }

    return filled;
  }

  /// Squared RGB distance between two colours (ignores alpha).
  ///
  /// Max value is ~195 075 (3 × 255²). With [_kFillTolerance] = 1000 each
  /// channel may differ by up to ~18 from the target — enough to cross
  /// anti-aliased stroke edges without leaking through solid strokes.
  static int _colorDistance(_Rgba a, _Rgba b) {
    final dr = a.r - b.r;
    final dg = a.g - b.g;
    final db = a.b - b.b;
    return dr * dr + dg * dg + db * db;
  }

  /// Converts an image-package [img.Pixel] to an [_Rgba].
  static _Rgba _pixelToRgba(img.Pixel p) => _Rgba(
        p.r.toInt(),
        p.g.toInt(),
        p.b.toInt(),
        p.a.toInt(),
      );

  /// Converts a Flutter [Color] to RGBA components.
  static _Rgba _colorToRgba(Color c) => _Rgba(
        (c.r * 255).round(),
        (c.g * 255).round(),
        (c.b * 255).round(),
        (c.a * 255).round(),
      );

  /// Saves the current canvas strokes to the currently selected frame.
  void _saveCanvasToCurrentFrame() {
    if (_loadingFrameStrokes) return;
    _movieController.updateCurrentFrameStrokes(_canvasController.strokes);
  }

  void _addFrameFromCanvas() {
    _movieController.addFrame(strokes: List.from(_canvasController.strokes));
    // Clear canvas for the next frame.
    _canvasController.clear();
  }

  void _onAddFrame() {
    _addFrameFromCanvas();
  }

  void _onRemoveFrame() {
    if (!_movieController.hasCurrentFrame) return;
    // First frame (index 0) cannot be removed.
    if (_movieController.currentFrameIndex == 0) return;
    final index = _movieController.currentFrameIndex;
    _movieController.removeFrame(index);
    if (!mounted) return;

    if (_movieController.hasCurrentFrame) {
      // Load the newly selected frame onto the canvas.
      _loadFrameToCanvas(_movieController.currentFrame!);
    } else {
      _canvasController.clear();
    }
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
    if (_movieMode && _movieController.hasFrames) {
      // Save current canvas strokes to the current frame first.
      _saveCanvasToCurrentFrame();

      // Serialize all frames with FPS.
      final movieFrames = _movieController.frames.map((f) => (
            strokes: f.strokes,
            durationMs: f.displayDuration.inMilliseconds,
          )).toList();
      final content = serializeMovie(
        fps: _movieController.fps,
        frames: movieFrames,
      );
      final ok = await _saveAlekaFn(content);
      if (!mounted) return;
      final n = _movieController.frameCount;
      _showSnackBar(
        ok
            ? 'Saved as .aleka ($n frame${n == 1 ? '' : 's'})'
            : 'Save cancelled or failed.',
      );
      return;
    }

    // Paint mode: save canvas strokes.
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
    final content = await _loadAlekaFn();
    if (!mounted) return;
    if (content == null) {
      _showSnackBar('Load cancelled or file is invalid.');
      return;
    }

    // Try movie data first — if the file contains a movie section, restore
    // the full animation timeline.
    final movieData = deserializeMovie(content);
    if (movieData != null) {
      // Switch to movie mode and restore frames.
      if (!_movieMode) {
        setState(() => _movieMode = true);
      }
      _movieController.clearFrames();
      for (final frame in movieData.frames) {
        _movieController.addFrame(
          strokes: frame.strokes,
          duration: Duration(milliseconds: frame.durationMs),
        );
      }
      _movieController.setFps(movieData.fps);
      if (_movieController.hasCurrentFrame) {
        _loadFrameToCanvas(_movieController.currentFrame!);
      }
      final n = _movieController.frameCount;
      _showSnackBar('Loaded animation ($n frame${n == 1 ? '' : 's'}).');
      return;
    }

    // No movie section — paint-mode file. Load strokes onto the canvas and
    // exit movie mode if we were in it.
    final strokes = deserializeStrokes(content);
    if (strokes == null) {
      _showSnackBar('Load cancelled or file is invalid.');
      return;
    }

    // Exit movie mode so the loaded strokes are visible on the paint canvas.
    if (_movieMode) {
      setState(() => _movieMode = false);
    }
    _canvasController.replaceStrokes(strokes);
    _showSnackBar('Loaded ${strokes.length} stroke${strokes.length == 1 ? '' : 's'}.');
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

      // Wait for the framework to schedule and paint a new frame.
      await WidgetsBinding.instance.endOfFrame;
      // On web, CanvasKit rasterisation is async — give it extra time
      // before calling toImage() on the RepaintBoundary.
      await Future<void>.delayed(Duration(
        milliseconds: kIsWeb ? 200 : 50,
      ));

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
      _showSnackBar(
        'Export failed — could not capture frames '
        '(0 of ${_movieController.frameCount} frames rendered).',
        isError: true,
      );
      return;
    }

    // Encode to MP4 (desktop / web) and save.
    final encodeFn = widget.videoEncodeOverride ?? encodeVideo;
    final (:bytes, :error) = await encodeFn(
      pngFrames: frameImages,
      delaysMs: delaysMs,
      fps: _movieController.fps,
    );

    if (!mounted) return;

    if (bytes == null) {
      _showSnackBar(
        'Video export failed — ${error ?? 'unknown error'}.',
        isError: true,
      );
      return;
    }

    final ok = await _saveVideoFn(bytes);
    if (!mounted) return;
    _showSnackBar(
      ok
          ? 'Exported as video (${_movieController.frameCount} frames)'
          : 'Export cancelled or failed.',
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Canvas fills the entire body — behind all panels.
          Positioned.fill(
            child: RepaintBoundary(
              key: _canvasRepaintKey,
              child: PaintCanvas(
                controller: _canvasController,
                color: _currentColor,
                strokeWidth: _strokeWidth,
                fillTool: _fillTool,
                onFillTap: _onFillTap,
              ),
            ),
          ),
          // Toolbar floats on top of the canvas.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: PaintToolbar(
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
              fillTool: _fillTool,
              onToggleFillTool: _toggleFillTool,
            ),
          ),
          // Timeline floats at the bottom.
          if (_movieMode)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: MovieTimeline(
                controller: _movieController,
                onAddFrame: _onAddFrame,
                onRemoveFrame: _onRemoveFrame,
                onFrameSelected: _onSelectFrame,
                onPlayPause: _onPlayPause,
              ),
            ),
        ],
      ),
    );
  }
}

/// Lightweight RGBA value for pixel comparisons during flood fill.
class _Rgba {
  final int r, g, b, a;
  const _Rgba(this.r, this.g, this.b, this.a);
}
