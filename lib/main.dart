import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'paint_canvas.dart';
import 'toolbar.dart';
import 'aleka_file.dart';

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

class PaintScreen extends StatefulWidget {
  final SaveStrokesFn? saveStrokes;
  final LoadStrokesFn? loadStrokes;
  final CapturePngFn? capturePngOverride;
  final SavePngFn? savePngOverride;

  const PaintScreen({
    super.key,
    this.saveStrokes,
    this.loadStrokes,
    this.capturePngOverride,
    this.savePngOverride,
  });

  @override
  State<PaintScreen> createState() => _PaintScreenState();
}

class _PaintScreenState extends State<PaintScreen> {
  Color _currentColor = Colors.black;
  double _strokeWidth = 3.0;
  final PaintCanvasController _canvasController = PaintCanvasController();
  final GlobalKey _canvasRepaintKey = GlobalKey();

  void _onUndo() {
    _canvasController.undo();
  }

  void _onClear() {
    _canvasController.clear();
  }

  SaveStrokesFn get _saveFn => widget.saveStrokes ?? saveToFile;
  LoadStrokesFn get _loadFn => widget.loadStrokes ?? loadFromFile;
  CapturePngFn get _captureFn => widget.capturePngOverride ?? capturePng;
  SavePngFn get _savePngFn => widget.savePngOverride ?? savePngToFile;

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
        ],
      ),
    );
  }
}
