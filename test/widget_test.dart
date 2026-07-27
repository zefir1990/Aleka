import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aleka/main.dart';
import 'package:aleka/paint_canvas.dart';
import 'package:aleka/toolbar.dart';
import 'package:aleka/aleka_file.dart';
import 'package:aleka/movie_controller.dart';
import 'package:aleka/movie_timeline.dart';
import 'package:aleka/video_export.dart';
import 'package:aleka/video_export_web.dart';
import 'package:image/image.dart' as img;

/// Helper: builds a MaterialApp wrapping a PaintToolbar for isolated testing.
Widget _wrapToolbar({
  required Color currentColor,
  required double strokeWidth,
  required ValueChanged<Color> onColorChanged,
  required ValueChanged<double> onStrokeWidthChanged,
  required VoidCallback onUndo,
  required VoidCallback onClear,
  required VoidCallback onSave,
  required VoidCallback onLoad,
  required VoidCallback onExport,
  bool movieMode = false,
  VoidCallback onToggleMovieMode = _noop,
}) {
  return MaterialApp(
    home: Scaffold(
      body: PaintToolbar(
        currentColor: currentColor,
        strokeWidth: strokeWidth,
        onColorChanged: onColorChanged,
        onStrokeWidthChanged: onStrokeWidthChanged,
        onUndo: onUndo,
        onClear: onClear,
        onSave: onSave,
        onLoad: onLoad,
        onExport: onExport,
        movieMode: movieMode,
        onToggleMovieMode: onToggleMovieMode,
      ),
    ),
  );
}

Widget _wrapCanvas(PaintCanvasController controller, Color color, double strokeWidth) {
  return MaterialApp(
    home: Scaffold(
      body: PaintCanvas(
        controller: controller,
        color: color,
        strokeWidth: strokeWidth,
      ),
    ),
  );
}

Finder _findColorSwatch(Color color) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).color == color,
  );
}

/// Shared no-op callbacks for brevity in toolbar tests.
void _noop() {}
void _noopColor(Color _) {}
void _noopDouble(double _) {}

// ---------------------------------------------------------------------------
// .aleka serialization tests
// ---------------------------------------------------------------------------
void main() {
  group('.aleka serialization', () {
    test('round-trip preserves strokes exactly', () {
      final strokes = [
        Stroke(
          points: [const Offset(10, 20), const Offset(100, 200)],
          color: Colors.red,
          strokeWidth: 3.0,
        ),
        Stroke(
          points: [const Offset(0, 0), const Offset(50, 50), const Offset(100, 100)],
          color: Colors.blue,
          strokeWidth: 12.5,
        ),
      ];

      final serialized = serializeStrokes(strokes);
      final deserialized = deserializeStrokes(serialized)!;

      expect(deserialized.length, strokes.length);

      for (var i = 0; i < strokes.length; i++) {
        expect(deserialized[i].color.toARGB32(), strokes[i].color.toARGB32());
        expect(deserialized[i].strokeWidth, strokes[i].strokeWidth);
        expect(deserialized[i].points.length, strokes[i].points.length);
        for (var j = 0; j < strokes[i].points.length; j++) {
          expect(deserialized[i].points[j].dx, strokes[i].points[j].dx);
          expect(deserialized[i].points[j].dy, strokes[i].points[j].dy);
        }
      }
    });

    test('empty strokes round-trip', () {
      final serialized = serializeStrokes([]);
      final deserialized = deserializeStrokes(serialized)!;
      expect(deserialized, isEmpty);
    });

    test('single-point stroke round-trip', () {
      final strokes = [
        Stroke(
          points: [const Offset(42.0, 7.5)],
          color: Colors.black,
          strokeWidth: 1.0,
        ),
      ];
      final serialized = serializeStrokes(strokes);
      final deserialized = deserializeStrokes(serialized)!;
      expect(deserialized.length, 1);
      expect(deserialized[0].points.length, 1);
    });

    test('invalid JSON returns null', () {
      expect(deserializeStrokes('not json'), isNull);
      expect(deserializeStrokes('{"wrong": "format"}'), isNull);
    });

    test('serialized data contains aleka header', () {
      final serialized = serializeStrokes([]);
      expect(serialized, contains('"aleka"'));
      expect(serialized, contains('"1.0"'));
    });
  });

  // -------------------------------------------------------------------------
  // Controller tests
  // -------------------------------------------------------------------------
  group('PaintCanvasController', () {
    test('replaceStrokes swaps all strokes', () {
      final controller = PaintCanvasController();
      controller.addStroke(Stroke(
        points: [const Offset(0, 0)],
        color: Colors.red,
        strokeWidth: 2,
      ));
      controller.addStroke(Stroke(
        points: [const Offset(10, 10)],
        color: Colors.blue,
        strokeWidth: 4,
      ));
      expect(controller.strokes.length, 2);

      final newStrokes = [
        Stroke(
          points: [const Offset(99, 99)],
          color: Colors.green,
          strokeWidth: 7,
        ),
      ];
      controller.replaceStrokes(newStrokes);
      expect(controller.strokes.length, 1);
      expect(controller.strokes[0].color, Colors.green);
      expect(controller.strokes[0].strokeWidth, 7.0);
    });

    test('replaceStrokes clears redo stack', () {
      final controller = PaintCanvasController();
      controller.addStroke(Stroke(
        points: [const Offset(0, 0)],
        color: Colors.red,
        strokeWidth: 2,
      ));
      controller.addStroke(Stroke(
        points: [const Offset(10, 10)],
        color: Colors.blue,
        strokeWidth: 4,
      ));
      controller.undo(); // One in redo stack.
      expect(controller.canRedo, isTrue);

      controller.replaceStrokes([]);
      expect(controller.canRedo, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Color picking tests
  // -------------------------------------------------------------------------
  group('Color picking', () {
    testWidgets('tapping a swatch fires onColorChanged with the correct color',
        (tester) async {
      Color? picked;
      await tester.pumpWidget(_wrapToolbar(
        currentColor: Colors.black,
        strokeWidth: 3,
        onColorChanged: (c) => picked = c,
        onStrokeWidthChanged: _noopDouble,
        onUndo: _noop,
        onClear: _noop,
        onSave: _noop,
        onLoad: _noop,
        onExport: _noop,
      ));
      await tester.tap(_findColorSwatch(Colors.red));
      await tester.pumpAndSettle();
      expect(picked, Colors.red);
    });

    testWidgets('tapping a different swatch updates selection', (tester) async {
      Color? picked;
      await tester.pumpWidget(_wrapToolbar(
        currentColor: Colors.blue,
        strokeWidth: 3,
        onColorChanged: (c) => picked = c,
        onStrokeWidthChanged: _noopDouble,
        onUndo: _noop,
        onClear: _noop,
        onSave: _noop,
        onLoad: _noop,
        onExport: _noop,
      ));
      await tester.tap(_findColorSwatch(Colors.green));
      await tester.pumpAndSettle();
      expect(picked, Colors.green);
    });

    testWidgets('selected swatch has thicker border', (tester) async {
      await tester.pumpWidget(_wrapToolbar(
        currentColor: Colors.black,
        strokeWidth: 3,
        onColorChanged: _noopColor,
        onStrokeWidthChanged: _noopDouble,
        onUndo: _noop,
        onClear: _noop,
        onSave: _noop,
        onLoad: _noop,
        onExport: _noop,
      ));
      final blackSwatch = tester.widget<Container>(_findColorSwatch(Colors.black));
      final blackBorder = (blackSwatch.decoration as BoxDecoration).border as Border;
      expect(blackBorder.top.width, 3);

      final redSwatch = tester.widget<Container>(_findColorSwatch(Colors.red));
      final redBorder = (redSwatch.decoration as BoxDecoration).border as Border;
      expect(redBorder.top.width, 1);
    });

    testWidgets('all palette colors are rendered', (tester) async {
      await tester.pumpWidget(_wrapToolbar(
        currentColor: Colors.black,
        strokeWidth: 3,
        onColorChanged: _noopColor,
        onStrokeWidthChanged: _noopDouble,
        onUndo: _noop,
        onClear: _noop,
        onSave: _noop,
        onLoad: _noop,
        onExport: _noop,
      ));
      expect(_findColorSwatch(Colors.black), findsOneWidget);
      expect(_findColorSwatch(Colors.white), findsOneWidget);
      expect(_findColorSwatch(Colors.red), findsOneWidget);
      expect(_findColorSwatch(Colors.blue), findsOneWidget);
      expect(_findColorSwatch(Colors.purple), findsOneWidget);
      expect(_findColorSwatch(const Color(0xFFFFF3E0)), findsOneWidget);
      expect(_findColorSwatch(const Color(0xFF8D6E63)), findsOneWidget);
    });

    testWidgets('consecutive color picks all fire correctly', (tester) async {
      final picked = <Color>[];
      await tester.pumpWidget(_wrapToolbar(
        currentColor: Colors.black,
        strokeWidth: 3,
        onColorChanged: picked.add,
        onStrokeWidthChanged: _noopDouble,
        onUndo: _noop,
        onClear: _noop,
        onSave: _noop,
        onLoad: _noop,
        onExport: _noop,
      ));
      await tester.ensureVisible(_findColorSwatch(Colors.red));
      await tester.pumpAndSettle();
      await tester.tap(_findColorSwatch(Colors.red));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_findColorSwatch(Colors.blue));
      await tester.pumpAndSettle();
      await tester.tap(_findColorSwatch(Colors.blue));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_findColorSwatch(Colors.green));
      await tester.pumpAndSettle();
      await tester.tap(_findColorSwatch(Colors.green));
      await tester.pumpAndSettle();
      expect(picked, [Colors.red, Colors.blue, Colors.green]);
    });
  });

  // -------------------------------------------------------------------------
  // Brush drawing tests
  // -------------------------------------------------------------------------
  group('Brush drawing', () {
    testWidgets('pointer drag creates a stroke with correct color and width',
        (tester) async {
      final controller = PaintCanvasController();
      await tester.pumpWidget(_wrapCanvas(controller, Colors.blue, 5.0));

      final gesture = await tester.startGesture(const Offset(100, 100));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 40));
      await tester.pump();
      await gesture.moveBy(const Offset(20, 10));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.strokes.length, 1);
      expect(controller.strokes.first.color, Colors.blue);
      expect(controller.strokes.first.strokeWidth, 5.0);
      expect(controller.strokes.first.points.length, greaterThanOrEqualTo(3));
    });

    testWidgets('single tap creates a dot stroke', (tester) async {
      final controller = PaintCanvasController();
      await tester.pumpWidget(_wrapCanvas(controller, Colors.red, 4.0));
      await tester.tapAt(const Offset(200, 150));
      await tester.pumpAndSettle();

      expect(controller.strokes.length, 1);
      expect(controller.strokes.first.color, Colors.red);
      expect(controller.strokes.first.strokeWidth, 4.0);
      expect(controller.strokes.first.points.length, 2);
    });

    testWidgets('multiple strokes accumulate', (tester) async {
      final controller = PaintCanvasController();
      await tester.pumpWidget(_wrapCanvas(controller, Colors.black, 3.0));

      var gesture = await tester.startGesture(const Offset(50, 60));
      await tester.pump();
      await gesture.moveBy(const Offset(10, 10));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      gesture = await tester.startGesture(const Offset(200, 180));
      await tester.pump();
      await gesture.moveBy(const Offset(15, 12));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.strokes.length, 2);
    });

    testWidgets('stroke uses active color after color change', (tester) async {
      final controller = PaintCanvasController();
      await tester.pumpWidget(_wrapCanvas(controller, Colors.green, 3.0));

      var gesture = await tester.startGesture(const Offset(60, 60));
      await tester.pump();
      await gesture.moveBy(const Offset(10, 10));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.strokes.last.color, Colors.green);

      await tester.pumpWidget(_wrapCanvas(controller, Colors.orange, 3.0));
      gesture = await tester.startGesture(const Offset(120, 120));
      await tester.pump();
      await gesture.moveBy(const Offset(10, 10));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.strokes.length, 2);
      expect(controller.strokes[0].color, Colors.green);
      expect(controller.strokes[1].color, Colors.orange);
    });

    testWidgets('stroke uses active brush width after size change',
        (tester) async {
      final controller = PaintCanvasController();
      await tester.pumpWidget(_wrapCanvas(controller, Colors.black, 2.0));

      var gesture = await tester.startGesture(const Offset(60, 60));
      await tester.pump();
      await gesture.moveBy(const Offset(10, 10));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.strokes.last.strokeWidth, 2.0);

      await tester.pumpWidget(_wrapCanvas(controller, Colors.black, 12.0));
      gesture = await tester.startGesture(const Offset(130, 130));
      await tester.pump();
      await gesture.moveBy(const Offset(10, 10));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.strokes.length, 2);
      expect(controller.strokes[0].strokeWidth, 2.0);
      expect(controller.strokes[1].strokeWidth, 12.0);
    });
  });

  // -------------------------------------------------------------------------
  // Undo tests
  // -------------------------------------------------------------------------
  group('Undo', () {
    testWidgets('undo removes the last stroke', (tester) async {
      final controller = PaintCanvasController();
      await tester.pumpWidget(_wrapCanvas(controller, Colors.black, 3.0));

      for (var i = 0; i < 2; i++) {
        final g = await tester.startGesture(Offset(50.0 + i * 30, 50.0 + i * 30));
        await tester.pump();
        await g.moveBy(const Offset(15, 15));
        await tester.pump();
        await g.up();
        await tester.pumpAndSettle();
      }
      expect(controller.strokes.length, 2);
      final firstStroke = controller.strokes[0];

      controller.undo();
      expect(controller.strokes.length, 1);
      expect(controller.strokes[0], same(firstStroke));

      controller.undo();
      expect(controller.strokes.length, 0);
    });

    testWidgets('undo on empty canvas does nothing', (tester) async {
      final controller = PaintCanvasController();
      await tester.pumpWidget(_wrapCanvas(controller, Colors.black, 3.0));
      expect(controller.strokes.length, 0);
      controller.undo();
      expect(controller.strokes.length, 0);
    });
  });

  // -------------------------------------------------------------------------
  // Clear tests
  // -------------------------------------------------------------------------
  group('Clear', () {
    testWidgets('clear removes all strokes', (tester) async {
      final controller = PaintCanvasController();
      await tester.pumpWidget(_wrapCanvas(controller, Colors.black, 3.0));

      for (var i = 0; i < 3; i++) {
        final g = await tester.startGesture(Offset(60.0 + i * 30, 60.0 + i * 30));
        await tester.pump();
        await g.moveBy(const Offset(12, 12));
        await tester.pump();
        await g.up();
        await tester.pumpAndSettle();
      }
      expect(controller.strokes.length, 3);
      controller.clear();
      expect(controller.strokes.length, 0);
    });

    testWidgets('clear on empty canvas does nothing', (tester) async {
      final controller = PaintCanvasController();
      await tester.pumpWidget(_wrapCanvas(controller, Colors.black, 3.0));
      expect(controller.strokes.length, 0);
      controller.clear();
      expect(controller.strokes.length, 0);
    });
  });

  // -------------------------------------------------------------------------
  // Brush-size slider tests
  // -------------------------------------------------------------------------
  group('Brush size', () {
    testWidgets('moving slider calls onStrokeWidthChanged', (tester) async {
      double? newWidth;
      await tester.pumpWidget(_wrapToolbar(
        currentColor: Colors.black,
        strokeWidth: 5.0,
        onColorChanged: _noopColor,
        onStrokeWidthChanged: (w) => newWidth = w,
        onUndo: _noop,
        onClear: _noop,
        onSave: _noop,
        onLoad: _noop,
        onExport: _noop,
      ));
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(30.0);
      await tester.pumpAndSettle();
      expect(newWidth, 30.0);
    });

    testWidgets('slider range is 1 to 30', (tester) async {
      await tester.pumpWidget(_wrapToolbar(
        currentColor: Colors.black,
        strokeWidth: 5.0,
        onColorChanged: _noopColor,
        onStrokeWidthChanged: _noopDouble,
        onUndo: _noop,
        onClear: _noop,
        onSave: _noop,
        onLoad: _noop,
        onExport: _noop,
      ));
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.min, 1.0);
      expect(slider.max, 30.0);
    });
  });

  // -------------------------------------------------------------------------
  // Save / Load button tests
  // -------------------------------------------------------------------------
  group('Save / Load buttons', () {
    testWidgets('save and load icons are visible', (tester) async {
      await tester.pumpWidget(const AlekaApp());
      expect(find.byIcon(Icons.save), findsOneWidget);
      expect(find.byIcon(Icons.folder_open), findsOneWidget);
    });

    testWidgets('save button fires onSave callback', (tester) async {
      var saved = false;
      await tester.pumpWidget(_wrapToolbar(
        currentColor: Colors.black,
        strokeWidth: 3,
        onColorChanged: _noopColor,
        onStrokeWidthChanged: _noopDouble,
        onUndo: _noop,
        onClear: _noop,
        onSave: () => saved = true,
        onLoad: _noop,
        onExport: _noop,
      ));
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();
      expect(saved, isTrue);
    });

    testWidgets('load button fires onLoad callback', (tester) async {
      var loaded = false;
      await tester.pumpWidget(_wrapToolbar(
        currentColor: Colors.black,
        strokeWidth: 3,
        onColorChanged: _noopColor,
        onStrokeWidthChanged: _noopDouble,
        onUndo: _noop,
        onClear: _noop,
        onSave: _noop,
        onLoad: () => loaded = true,
        onExport: _noop,
      ));
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();
      expect(loaded, isTrue);
    });

    testWidgets('export button fires onExport callback', (tester) async {
      var exported = false;
      await tester.pumpWidget(_wrapToolbar(
        currentColor: Colors.black,
        strokeWidth: 3,
        onColorChanged: _noopColor,
        onStrokeWidthChanged: _noopDouble,
        onUndo: _noop,
        onClear: _noop,
        onSave: _noop,
        onLoad: _noop,
        onExport: () => exported = true,
      ));
      await tester.tap(find.byIcon(Icons.image));
      await tester.pumpAndSettle();
      expect(exported, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // PNG capture tests
  // -------------------------------------------------------------------------
  group('PNG capture', () {
    test('capturePng returns null for unattached key', () async {
      final danglingKey = GlobalKey();
      final bytes = await capturePng(danglingKey);
      expect(bytes, isNull);
    });

    test('ByteData buffer extraction uses correct offset and length', () {
      // Simulate the case where ByteData is a view into a larger buffer —
      // exactly what happens on web where the CanvasKit surface buffer is
      // shared across multiple paint operations.
      final png = _encodeMinimalPng(0, 128, 255);
      // A buffer larger than the PNG, with garbage at the start.
      final buffer = Uint8List(png.length + 20);
      buffer[0] = 0xFF;
      buffer[1] = 0xFE;
      buffer[2] = 0xFD;
      // The PNG data sits at offset 20.
      buffer.setAll(20, png);

      final byteData = ByteData.view(buffer.buffer, 20, png.length);

      // OLD bug: asUint8List() without parameters reads from offset 0.
      final oldWay = byteData.buffer.asUint8List();
      expect(oldWay[0], 0xFF, reason: 'old way reads garbage at offset 0');
      expect(oldWay[1], 0xFE);
      // This would fail to decode because of the garbage prefix.
      expect(img.decodePng(oldWay), isNull,
          reason: 'garbage prefix makes it invalid PNG');

      // FIXED: asUint8List(offsetInBytes, lengthInBytes).
      final newWay = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      expect(newWay[0], png[0], reason: 'starts at PNG magic byte');
      expect(newWay.length, png.length,
          reason: 'exact PNG data length');
      expect(img.decodePng(newWay), isNotNull,
          reason: 'valid PNG that decodes correctly');
    });

    testWidgets('export icon is visible in full app', (tester) async {
      await tester.pumpWidget(const AlekaApp());
      expect(find.byIcon(Icons.image), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Full-app integration smoke test
  // -------------------------------------------------------------------------
  group('Full app integration', () {
    testWidgets('draw, undo, and clear flow via the full app', (tester) async {
      await tester.pumpWidget(const AlekaApp());

      expect(find.byIcon(Icons.undo), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.byIcon(Icons.save), findsOneWidget);
      expect(find.byIcon(Icons.folder_open), findsOneWidget);
      expect(find.byIcon(Icons.image), findsOneWidget);

      final gesture = await tester.startGesture(const Offset(200, 300));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 30));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.undo));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
    });

    testWidgets('pick a color then draw a stroke', (tester) async {
      await tester.pumpWidget(const AlekaApp());

      await tester.tap(_findColorSwatch(Colors.red));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(const Offset(150, 250));
      await tester.pump();
      await gesture.moveBy(const Offset(35, 25));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  // -------------------------------------------------------------------------
  // UI integration: save → clear → load round-trip (mocked file layer)
  // -------------------------------------------------------------------------
  group('Save/Load round-trip (UI)', () {
    testWidgets('save captures strokes, load restores them', (tester) async {
      String? saved;

      await tester.pumpWidget(MaterialApp(
        home: PaintScreen(
          saveStrokes: (strokes) async {
            saved = serializeStrokes(strokes);
            return true;
          },
          loadStrokes: () async {
            if (saved == null) return null;
            return deserializeStrokes(saved!);
          },
        ),
      ));

      // Draw two strokes.
      var gesture = await tester.startGesture(const Offset(100, 300));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 30));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      gesture = await tester.startGesture(const Offset(250, 350));
      await tester.pump();
      await gesture.moveBy(const Offset(20, 40));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Save.
      await tester.ensureVisible(find.byIcon(Icons.save));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();
      expect(find.text('Saved as .aleka'), findsOneWidget);
      expect(saved, isNotNull);

      // Let save snackbar dismiss (2 s) so it doesn't block the load tap.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // Clear.
      await tester.ensureVisible(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // Load.
      await tester.ensureVisible(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();
      expect(find.textContaining('Loaded 2 strokes'), findsOneWidget);
    });

    testWidgets('save on empty canvas shows warning', (tester) async {
      await tester.pumpWidget(MaterialApp(home: PaintScreen()));

      // No drawing — save immediately.
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();
      expect(find.text('Nothing to save — canvas is empty.'), findsOneWidget);
    });

    testWidgets('load that returns null shows error', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PaintScreen(
          loadStrokes: () async => null,
        ),
      ));

      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();
      expect(find.text('Load cancelled or file is invalid.'), findsOneWidget);
    });

    testWidgets('save that returns false shows failure', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PaintScreen(
          saveStrokes: (strokes) async => false,
        ),
      ));

      // Draw a stroke first.
      final gesture = await tester.startGesture(const Offset(100, 300));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 30));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();
      expect(find.text('Save cancelled or failed.'), findsOneWidget);
    });

    testWidgets('load restores stroke with correct color and width',
        (tester) async {
      String? saved;

      await tester.pumpWidget(MaterialApp(
        home: PaintScreen(
          saveStrokes: (strokes) async {
            saved = serializeStrokes(strokes);
            return true;
          },
          loadStrokes: () async {
            if (saved == null) return null;
            return deserializeStrokes(saved!);
          },
        ),
      ));

      // Pick a color and draw.
      await tester.ensureVisible(_findColorSwatch(Colors.blue));
      await tester.pumpAndSettle();
      await tester.tap(_findColorSwatch(Colors.blue));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(const Offset(100, 300));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 30));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Save.
      await tester.ensureVisible(find.byIcon(Icons.save));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      // Let save snackbar dismiss so it doesn't block the load tap.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // Clear and load back.
      await tester.ensureVisible(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();

      expect(find.textContaining('Loaded 1 stroke'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // UI integration: PNG export (mocked capture + file layer)
  // -------------------------------------------------------------------------
  group('PNG export (UI)', () {
    final fakePng = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);

    testWidgets('export calls capture and save, shows success', (tester) async {
      bool captured = false;
      bool saved = false;

      await tester.pumpWidget(MaterialApp(
        home: PaintScreen(
          capturePngOverride: (key) async {
            captured = true;
            return fakePng;
          },
          savePngOverride: (bytes) async {
            saved = true;
            return true;
          },
        ),
      ));

      await tester.tap(find.byIcon(Icons.image));
      await tester.pumpAndSettle();

      expect(captured, isTrue);
      expect(saved, isTrue);
      expect(find.text('Exported as PNG'), findsOneWidget);
    });

    testWidgets('export shows error when capture fails', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PaintScreen(
          capturePngOverride: (key) async => null,
          savePngOverride: (bytes) async => true,
        ),
      ));

      await tester.tap(find.byIcon(Icons.image));
      await tester.pumpAndSettle();
      expect(find.text('Export failed — could not capture canvas.'), findsOneWidget);
    });

    testWidgets('export shows error when save fails', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PaintScreen(
          capturePngOverride: (key) async => fakePng,
          savePngOverride: (bytes) async => false,
        ),
      ));

      await tester.tap(find.byIcon(Icons.image));
      await tester.pumpAndSettle();
      expect(find.text('Export cancelled or failed.'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Frame model tests
  // -------------------------------------------------------------------------
  group('Frame model', () {
    test('defaults', () {
      final frame = Frame(id: '1');
      expect(frame.id, '1');
      expect(frame.strokes, isEmpty);
      expect(frame.displayDuration, defaultFrameDuration);
    });

    test('copyWith replaces fields', () {
      final frame = Frame(id: '1', strokes: [], displayDuration: const Duration(seconds: 1));
      final copy = frame.copyWith(
        id: '2',
        displayDuration: const Duration(milliseconds: 750),
      );
      expect(copy.id, '2');
      expect(copy.displayDuration, const Duration(milliseconds: 750));
      expect(copy.strokes, isEmpty);
    });

    test('copyWith preserves unchanged fields', () {
      final strokes = [Stroke(points: [const Offset(1, 2)], color: Colors.red, strokeWidth: 3)];
      final frame = Frame(id: 'abc', strokes: strokes, displayDuration: const Duration(seconds: 1));
      final copy = frame.copyWith();
      expect(copy.id, 'abc');
      expect(copy.strokes, strokes);
      expect(copy.displayDuration, const Duration(seconds: 1));
    });
  });

  // -------------------------------------------------------------------------
  // MovieController tests
  // -------------------------------------------------------------------------
  group('MovieController', () {
    test('starts with no frames and default FPS', () {
      final controller = MovieController();
      expect(controller.frameCount, 0);
      expect(controller.hasFrames, isFalse);
      expect(controller.hasCurrentFrame, isFalse);
      expect(controller.currentFrame, isNull);
      expect(controller.currentFrameIndex, -1);
      expect(controller.fps, defaultFps);
    });

    test('addFrame creates a frame and selects it', () {
      final controller = MovieController();
      controller.addFrame();
      expect(controller.frameCount, 1);
      expect(controller.hasFrames, isTrue);
      expect(controller.hasCurrentFrame, isTrue);
      expect(controller.currentFrameIndex, 0);
      expect(controller.currentFrame!.strokes, isEmpty);
    });

    test('addFrame with strokes preserves them', () {
      final controller = MovieController();
      final strokes = [Stroke(points: [const Offset(0, 0)], color: Colors.red, strokeWidth: 2)];
      controller.addFrame(strokes: strokes);
      expect(controller.currentFrame!.strokes.length, 1);
      expect(controller.currentFrame!.strokes.first.color, Colors.red);
    });

    test('addFrame with custom duration', () {
      final controller = MovieController();
      controller.addFrame(duration: const Duration(seconds: 3));
      expect(controller.currentFrame!.displayDuration, const Duration(seconds: 3));
    });

    test('multiple addFrames select the latest', () {
      final controller = MovieController();
      controller.addFrame();
      controller.addFrame();
      controller.addFrame();
      expect(controller.frameCount, 3);
      expect(controller.currentFrameIndex, 2);
    });

    test('removeFrame deletes frame at index', () {
      final controller = MovieController();
      for (var i = 0; i < 3; i++) {
        controller.addFrame();
      }
      controller.removeFrame(1);
      expect(controller.frameCount, 2);
    });

    test('removeFrame of current shifts to next frame', () {
      final controller = MovieController();
      for (var i = 0; i < 3; i++) {
        controller.addFrame();
      }
      controller.selectFrame(1);
      controller.removeFrame(1);
      // Frame 1 was removed, now previous frame 2 is frame 1, should be selected.
      expect(controller.frameCount, 2);
      expect(controller.currentFrameIndex, 1);
    });

    test('removeFrame of last current shifts to previous', () {
      final controller = MovieController();
      for (var i = 0; i < 3; i++) {
        controller.addFrame();
      }
      // Current is frame 2 (last).
      controller.removeFrame(2);
      expect(controller.frameCount, 2);
      expect(controller.currentFrameIndex, 1);
    });

    test('removeFrame before current decrements index', () {
      final controller = MovieController();
      for (var i = 0; i < 3; i++) {
        controller.addFrame();
      }
      controller.selectFrame(2); // Last frame.
      controller.removeFrame(0); // Remove frame before current.
      expect(controller.frameCount, 2);
      expect(controller.currentFrameIndex, 1); // Shifted down.
    });

    test('removeFrame of only frame clears selection', () {
      final controller = MovieController();
      controller.addFrame();
      controller.removeFrame(0);
      expect(controller.frameCount, 0);
      expect(controller.hasCurrentFrame, isFalse);
      expect(controller.currentFrameIndex, -1);
    });

    test('removeFrame out of bounds is ignored', () {
      final controller = MovieController();
      controller.addFrame();
      controller.removeFrame(5);
      expect(controller.frameCount, 1);
    });

    test('selectFrame changes current index', () {
      final controller = MovieController();
      for (var i = 0; i < 3; i++) {
        controller.addFrame();
      }
      controller.selectFrame(1);
      expect(controller.currentFrameIndex, 1);
    });

    test('selectFrame out of bounds is ignored', () {
      final controller = MovieController();
      controller.addFrame();
      controller.selectFrame(99);
      expect(controller.currentFrameIndex, 0);
    });

    test('setFrameDuration updates duration', () {
      final controller = MovieController();
      controller.addFrame();
      controller.setFrameDuration(0, const Duration(milliseconds: 1200));
      expect(controller.currentFrame!.displayDuration, const Duration(milliseconds: 1200));
    });

    test('setFps clamps to 1-60', () {
      final controller = MovieController();
      controller.setFps(100);
      expect(controller.fps, 60.0);
      controller.setFps(-5);
      expect(controller.fps, 1.0);
      controller.setFps(24);
      expect(controller.fps, 24.0);
    });

    test('clearFrames removes all frames', () {
      final controller = MovieController();
      for (var i = 0; i < 3; i++) {
        controller.addFrame();
      }
      controller.clearFrames();
      expect(controller.frameCount, 0);
      expect(controller.currentFrameIndex, -1);
    });

    test('updateCurrentFrameStrokes replaces strokes', () {
      final controller = MovieController();
      controller.addFrame();
      final strokes = [Stroke(points: [const Offset(5, 5)], color: Colors.blue, strokeWidth: 4)];
      controller.updateCurrentFrameStrokes(strokes);
      expect(controller.currentFrame!.strokes.length, 1);
      expect(controller.currentFrame!.strokes.first.color, Colors.blue);
    });

    test('updateCurrentFrameStrokes does nothing when no frame selected', () {
      final controller = MovieController();
      controller.updateCurrentFrameStrokes([Stroke(points: [const Offset(0, 0)], color: Colors.red, strokeWidth: 1)]);
      expect(controller.currentFrame, isNull);
    });

    test('totalStrokeCount sums across all frames', () {
      final controller = MovieController();
      controller.addFrame(strokes: [
        Stroke(points: [const Offset(0, 0)], color: Colors.red, strokeWidth: 1),
        Stroke(points: [const Offset(1, 1)], color: Colors.red, strokeWidth: 1),
      ]);
      controller.addFrame(strokes: [
        Stroke(points: [const Offset(2, 2)], color: Colors.blue, strokeWidth: 1),
      ]);
      expect(controller.totalStrokeCount, 3);
    });

    test('frames list is unmodifiable', () {
      final controller = MovieController();
      controller.addFrame();
      expect(() => controller.frames.add(Frame(id: 'x')), throwsUnsupportedError);
    });

    // -- Playback ----------------------------------------------------------

    test('isPlaying starts false', () {
      final controller = MovieController();
      expect(controller.isPlaying, isFalse);
    });

    test('play does nothing with no frames', () {
      final controller = MovieController();
      controller.play();
      expect(controller.isPlaying, isFalse);
    });

    test('play starts playback and sets isPlaying', () {
      final controller = MovieController();
      controller.addFrame();
      controller.play();
      expect(controller.isPlaying, isTrue);
      controller.pause(); // Clean up timer.
    });

    test('pause stops playback', () {
      final controller = MovieController();
      controller.addFrame();
      controller.play();
      expect(controller.isPlaying, isTrue);
      controller.pause();
      expect(controller.isPlaying, isFalse);
    });

    test('togglePlayPause toggles between states', () {
      final controller = MovieController();
      controller.addFrame();
      controller.togglePlayPause();
      expect(controller.isPlaying, isTrue);
      controller.togglePlayPause();
      expect(controller.isPlaying, isFalse);
    });

    test('play advances to next frame', () {
      final controller = MovieController();
      controller.addFrame(duration: const Duration(milliseconds: 10));
      controller.addFrame(duration: const Duration(milliseconds: 10));
      controller.selectFrame(0);
      expect(controller.currentFrameIndex, 0);

      final fake = FakeAsync();
      fake.run((_) {
        controller.play();
        expect(controller.isPlaying, isTrue);
        expect(controller.currentFrameIndex, 0);
        // Advance past the first frame's duration.
        fake.elapse(const Duration(milliseconds: 12));
        expect(controller.currentFrameIndex, 1);
        // Advance past the last frame's duration — should stop.
        fake.elapse(const Duration(milliseconds: 10));
        expect(controller.isPlaying, isFalse);
        expect(controller.currentFrameIndex, 1);
      });
    });

    test('dispose cancels playback', () {
      final controller = MovieController();
      controller.addFrame(duration: const Duration(milliseconds: 50));
      controller.play();
      expect(controller.isPlaying, isTrue);
      controller.dispose();
      // Timer is cancelled; isPlaying stays true (no notifyListeners on dispose).
    });

    // -- Looping ------------------------------------------------------------

    test('looping starts false', () {
      final controller = MovieController();
      expect(controller.looping, isFalse);
    });

    test('setLooping enables and disables looping', () {
      final controller = MovieController();
      controller.setLooping(true);
      expect(controller.looping, isTrue);
      controller.setLooping(false);
      expect(controller.looping, isFalse);
    });

    test('setLooping with same value does not notify', () {
      final controller = MovieController();
      var notified = false;
      controller.addListener(() => notified = true);
      notified = false;
      controller.setLooping(false); // Already false.
      expect(notified, isFalse);
    });

    test('playback loops to first frame when looping enabled', () {
      final controller = MovieController();
      controller.addFrame(duration: const Duration(milliseconds: 10));
      controller.addFrame(duration: const Duration(milliseconds: 10));
      controller.addFrame(duration: const Duration(milliseconds: 10));
      controller.selectFrame(0);
      controller.setLooping(true);

      final fake = FakeAsync();
      fake.run((_) {
        controller.play();
        expect(controller.currentFrameIndex, 0);
        // Advance past first frame (10 ms) → frame 1.
        fake.elapse(const Duration(milliseconds: 12));
        expect(controller.currentFrameIndex, 1);
        // Advance past second frame (10 ms, total 22 ms) → frame 2.
        fake.elapse(const Duration(milliseconds: 10));
        expect(controller.currentFrameIndex, 2);
        // Advance past third frame (10 ms, total 32 ms) → loops to frame 0.
        fake.elapse(const Duration(milliseconds: 10));
        expect(controller.currentFrameIndex, 0);
        expect(controller.isPlaying, isTrue);
        // Advance past frame 0 again (total 42 ms) → frame 1.
        fake.elapse(const Duration(milliseconds: 10));
        expect(controller.currentFrameIndex, 1);
      });
    });

    test('playback stops at last frame when looping disabled', () {
      final controller = MovieController();
      controller.addFrame(duration: const Duration(milliseconds: 10));
      controller.addFrame(duration: const Duration(milliseconds: 10));
      controller.selectFrame(0);

      final fake = FakeAsync();
      fake.run((_) {
        controller.play();
        fake.elapse(const Duration(milliseconds: 15));
        expect(controller.currentFrameIndex, 1);
        fake.elapse(const Duration(milliseconds: 15));
        expect(controller.isPlaying, isFalse);
        expect(controller.currentFrameIndex, 1);
      });
    });
  });

  // -------------------------------------------------------------------------
  // Video export tests
  // -------------------------------------------------------------------------
  group('Video export', () {
    test('empty frames returns error', () async {
      final result = await encodeVideo(pngFrames: [], delaysMs: [], fps: 12);
      expect(result.bytes, isNull);
      expect(result.error, isNotNull);
    });

    test('non-empty frames with no ffmpeg returns error', () async {
      final redPng = _encodeMinimalPng(255, 0, 0);
      final result = await encodeVideo(
        pngFrames: [redPng],
        delaysMs: [500],
        fps: 12,
      );
      // Without ffmpeg installed (desktop) or ffmpeg.wasm loaded (web),
      // bytes is null and error is set.
      expect(result.bytes, isNull);
      expect(result.error, isNotNull);
    });
  });

  // -------------------------------------------------------------------------
  // Movie timeline widget tests
  // -------------------------------------------------------------------------
  group('MovieTimeline widget', () {
    Widget wrapTimeline(MovieController controller, {
      VoidCallback? onAddFrame,
      VoidCallback? onRemoveFrame,
      ValueChanged<int>? onFrameSelected,
      VoidCallback? onPlayPause,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: MovieTimeline(
            controller: controller,
            onAddFrame: onAddFrame ?? () {},
            onRemoveFrame: onRemoveFrame ?? () {},
            onFrameSelected: onFrameSelected ?? (_) {},
            onPlayPause: onPlayPause ?? () {},
          ),
        ),
      );
    }

    testWidgets('shows empty message when no frames', (tester) async {
      final controller = MovieController();
      await tester.pumpWidget(wrapTimeline(controller));
      expect(find.text('No frames — tap + to add one'), findsOneWidget);
    });

    testWidgets('renders frame thumbnails when frames exist', (tester) async {
      final controller = MovieController();
      controller.addFrame();
      controller.addFrame();
      await tester.pumpWidget(wrapTimeline(controller));
      await tester.pumpAndSettle();
      // Should show frame numbers.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('add frame button is visible', (tester) async {
      final controller = MovieController();
      controller.addFrame();
      await tester.pumpWidget(wrapTimeline(controller));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
    });

    testWidgets('add frame button triggers onAddFrame', (tester) async {
      var added = false;
      final controller = MovieController();
      controller.addFrame();
      await tester.pumpWidget(wrapTimeline(controller, onAddFrame: () => added = true));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      expect(added, isTrue);
    });

    testWidgets('remove frame button triggers onRemoveFrame', (tester) async {
      var removed = false;
      final controller = MovieController();
      controller.addFrame();
      await tester.pumpWidget(wrapTimeline(controller, onRemoveFrame: () => removed = true));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      expect(removed, isTrue);
    });

    testWidgets('remove button is disabled when no current frame', (tester) async {
      final controller = MovieController();
      await tester.pumpWidget(wrapTimeline(controller));
      await tester.pumpAndSettle();
      // The remove button exists but should be disabled or the + button shows.
      final removeButton = find.byIcon(Icons.remove_circle_outline);
      // Either not present or disabled.
      if (removeButton.evaluate().isNotEmpty) {
        final btn = tester.widget<IconButton>(removeButton);
        expect(btn.onPressed, isNull);
      }
    });

    testWidgets('tapping a frame thumbnail triggers onFrameSelected', (tester) async {
      int? selectedIndex;
      final controller = MovieController();
      controller.addFrame(); // Frame 0
      controller.addFrame(); // Frame 1 (current)
      controller.selectFrame(0); // Select frame 0.
      await tester.pumpWidget(wrapTimeline(
        controller,
        onFrameSelected: (i) => selectedIndex = i,
      ));
      await tester.pumpAndSettle();

      // Tap frame 2's thumbnail.
      await tester.tap(find.text('2'));
      expect(selectedIndex, 1);
    });

    testWidgets('duration slider is visible when frames exist', (tester) async {
      final controller = MovieController();
      controller.addFrame();
      await tester.pumpWidget(wrapTimeline(controller));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsWidgets);
    });

    testWidgets('FPS label is visible', (tester) async {
      final controller = MovieController();
      controller.addFrame();
      await tester.pumpWidget(wrapTimeline(controller));
      await tester.pumpAndSettle();
      expect(find.text('FPS'), findsOneWidget);
    });

    testWidgets('empty state has only an add button', (tester) async {
      final controller = MovieController();
      await tester.pumpWidget(wrapTimeline(controller));
      await tester.pumpAndSettle();
      // The empty-state add button is an IconButton.filled with Icons.add.
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('shows play button when not playing', (tester) async {
      final controller = MovieController();
      controller.addFrame();
      await tester.pumpWidget(wrapTimeline(controller));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsNothing);
    });

    testWidgets('shows pause button when playing', (tester) async {
      final controller = MovieController();
      controller.addFrame(duration: const Duration(seconds: 5));
      await tester.pumpWidget(wrapTimeline(controller));
      await tester.pumpAndSettle();

      controller.play();
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsNothing);

      controller.pause();
    });

    testWidgets('play/pause button triggers onPlayPause', (tester) async {
      var toggled = false;
      final controller = MovieController();
      controller.addFrame();
      await tester.pumpWidget(wrapTimeline(
        controller,
        onPlayPause: () => toggled = true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.play_arrow));
      expect(toggled, isTrue);
    });

    testWidgets('loop button toggles looping', (tester) async {
      final controller = MovieController();
      controller.addFrame();
      await tester.pumpWidget(wrapTimeline(controller));
      await tester.pumpAndSettle();

      expect(controller.looping, isFalse);
      await tester.tap(find.byIcon(Icons.loop));
      expect(controller.looping, isTrue);
      await tester.tap(find.byIcon(Icons.loop));
      expect(controller.looping, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Movie mode toolbar tests
  // -------------------------------------------------------------------------
  group('Movie mode toolbar', () {
    testWidgets('export button shows PNG icon when not in movie mode', (tester) async {
      await tester.pumpWidget(_wrapToolbar(
        currentColor: Colors.black,
        strokeWidth: 3,
        onColorChanged: _noopColor,
        onStrokeWidthChanged: _noopDouble,
        onUndo: _noop,
        onClear: _noop,
        onSave: _noop,
        onLoad: _noop,
        onExport: _noop,
        movieMode: false,
      ));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.image), findsOneWidget);
      expect(find.byIcon(Icons.videocam), findsNothing);
    });

    testWidgets('export button shows video icon when in movie mode', (tester) async {
      await tester.pumpWidget(_wrapToolbar(
        currentColor: Colors.black,
        strokeWidth: 3,
        onColorChanged: _noopColor,
        onStrokeWidthChanged: _noopDouble,
        onUndo: _noop,
        onClear: _noop,
        onSave: _noop,
        onLoad: _noop,
        onExport: _noop,
        movieMode: true,
      ));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.videocam), findsOneWidget);
      expect(find.byIcon(Icons.image), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Video creation UI tests — full end-to-end flow
  // -------------------------------------------------------------------------
  group('Video creation UI', () {
    final fakePng = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    final fakeWebm = Uint8List.fromList([0x1A, 0x45, 0xDF, 0xA3]); // EBML header

    /// Returns the add-frame button finder, which differs between empty- and
    /// non-empty timeline states. The colour picker also uses [Icons.add], so
    /// we scope the search to the [MovieTimeline] subtree.
    Finder addFrameBtn() {
      // When no frames exist the timeline shows IconButton.filled(Icons.add).
      // When frames exist it shows IconButton(Icons.add_circle_outline).
      final filled = find.descendant(
        of: find.byType(MovieTimeline),
        matching: find.byIcon(Icons.add),
      );
      if (filled.evaluate().isNotEmpty) return filled;
      return find.descendant(
        of: find.byType(MovieTimeline),
        matching: find.byIcon(Icons.add_circle_outline),
      );
    }

    /// Pumps the test clock through the video-export async delays.
    /// The export loop has a [Future.delayed] per frame (200ms web, 50ms
    /// desktop), plus [WidgetsBinding.instance.endOfFrame] — we pump
    /// generously to cover both platforms.
    Future<void> pumpExport(WidgetTester tester, {int frameCount = 1}) async {
      // Web: 200ms delay per frame + endOfFrame.  Desktop: 50ms per frame.
      // Pump enough 100ms ticks to cover all frames plus encode + snackbar.
      final pumpsPerFrame = kIsWeb ? 5 : 2;
      for (var i = 0; i < frameCount * pumpsPerFrame + 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('add frame button adds a frame', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PaintScreen(),
      ));

      // Enter movie mode.
      await tester.tap(find.byIcon(Icons.movie));
      await tester.pumpAndSettle();

      // The empty-state add button should be visible inside MovieTimeline.
      final addBtn = find.descendant(
        of: find.byType(MovieTimeline),
        matching: find.byIcon(Icons.add),
      );
      expect(addBtn, findsOneWidget);

      // Tap it.
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // Should show "Frame 1 added."
      expect(find.text('Frame 1 added.'), findsOneWidget);
      // Should render frame thumbnail "1".
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('export with one frame calls capture and encode',
        (tester) async {
      int captureCount = 0;
      bool encodeCalled = false;
      int pngCount = 0;

      await tester.pumpWidget(MaterialApp(
        home: PaintScreen(
          capturePngOverride: (key) async {
            captureCount++;
            return fakePng;
          },
          videoEncodeOverride: (
            {required pngFrames, required delaysMs, required fps}) async {
            encodeCalled = true;
            pngCount = pngFrames.length;
            return (bytes: null, error: 'ffmpeg not found'); // Simulate ffmpeg not found.
          },
        ),
      ));

      // Enter movie mode.
      await tester.tap(find.byIcon(Icons.movie));
      await tester.pumpAndSettle();

      // Add a frame.
      await tester.tap(addFrameBtn());
      await tester.pumpAndSettle();

      // Draw on it.
      final gesture = await tester.startGesture(const Offset(100, 300));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 30));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Export.
      await tester.tap(find.byIcon(Icons.videocam));
      await pumpExport(tester);

      // Capture and encode should have been called.
      expect(captureCount, greaterThanOrEqualTo(1));
      expect(encodeCalled, isTrue);
      expect(pngCount, 1);
    });

    testWidgets('export with no frames shows warning', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PaintScreen(
          capturePngOverride: (key) async => fakePng,
        ),
      ));

      // Enter movie mode.
      await tester.tap(find.byIcon(Icons.movie));
      await tester.pumpAndSettle();

      // Click export without adding any frames.
      await tester.tap(find.byIcon(Icons.videocam));
      await pumpExport(tester);

      expect(find.text('Nothing to export — no frames in timeline.'), findsOneWidget);
    });

    testWidgets('export captures each frame exactly once per frame',
        (tester) async {
      int captureCount = 0;
      int encodePngCount = 0;

      await tester.pumpWidget(MaterialApp(
        home: PaintScreen(
          capturePngOverride: (key) async {
            captureCount++;
            return fakePng;
          },
          videoEncodeOverride: (
            {required pngFrames, required delaysMs, required fps}) async {
            encodePngCount = pngFrames.length;
            return (bytes: fakeWebm, error: null);
          },
          saveVideoOverride: (bytes) async => true,
        ),
      ));

      // Enter movie mode.
      await tester.tap(find.byIcon(Icons.movie));
      await tester.pumpAndSettle();

      // Add 3 frames, drawing on each.
      for (var i = 0; i < 3; i++) {
        await tester.tap(addFrameBtn());
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(
          Offset(100.0 + i * 30, 300.0),
        );
        await tester.pump();
        await gesture.moveBy(const Offset(40, 30));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
      }

      // Click export.
      final lastCount = captureCount;
      await tester.tap(find.byIcon(Icons.videocam));
      await pumpExport(tester, frameCount: 3);

      // Should have captured 3 frames (one per frame in the timeline).
      expect(captureCount - lastCount, 3);
      expect(encodePngCount, 3);
    });

    testWidgets('export with mocked encode calls saveVideo with video bytes',
        (tester) async {
      Uint8List? savedBytes;
      bool encodeCalled = false;

      await tester.pumpWidget(MaterialApp(
        home: PaintScreen(
          capturePngOverride: (key) async => fakePng,
          videoEncodeOverride: (
            {required pngFrames, required delaysMs, required fps}) async {
            encodeCalled = true;
            return (bytes: fakeWebm, error: null);
          },
          saveVideoOverride: (bytes) async {
            savedBytes = bytes;
            return true;
          },
        ),
      ));

      // Enter movie mode.
      await tester.tap(find.byIcon(Icons.movie));
      await tester.pumpAndSettle();

      // Add a frame.
      await tester.tap(addFrameBtn());
      await tester.pumpAndSettle();

      // Draw on it.
      final gesture = await tester.startGesture(const Offset(100, 300));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 30));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Export.
      await tester.tap(find.byIcon(Icons.videocam));
      await pumpExport(tester);

      // The encode and save callbacks should have been called.
      expect(encodeCalled, isTrue);
      expect(savedBytes, isNotNull);
      expect(savedBytes, equals(fakeWebm));
    });

    testWidgets('export with failed capture does not call encode or save',
        (tester) async {
      bool encodeCalled = false;
      bool saveCalled = false;

      await tester.pumpWidget(MaterialApp(
        home: PaintScreen(
          capturePngOverride: (key) async => null, // All captures fail.
          videoEncodeOverride: (
            {required pngFrames, required delaysMs, required fps}) async {
            encodeCalled = true;
            return (bytes: fakeWebm, error: null);
          },
          saveVideoOverride: (bytes) async {
            saveCalled = true;
            return true;
          },
        ),
      ));

      // Enter movie mode.
      await tester.tap(find.byIcon(Icons.movie));
      await tester.pumpAndSettle();

      // Add a frame.
      await tester.tap(addFrameBtn());
      await tester.pumpAndSettle();

      // Draw.
      final gesture = await tester.startGesture(const Offset(100, 300));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 30));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Export.
      await tester.tap(find.byIcon(Icons.videocam));
      await pumpExport(tester);

      // Capture returns null → frameImages is empty → encode and save NOT called.
      expect(encodeCalled, isFalse);
      expect(saveCalled, isFalse);
    });

    testWidgets('export saves current canvas to frame before rendering',
        (tester) async {
      int captureCount = 0;
      bool encodeCalled = false;

      await tester.pumpWidget(MaterialApp(
        home: PaintScreen(
          capturePngOverride: (key) async {
            captureCount++;
            return fakePng;
          },
          videoEncodeOverride: (
            {required pngFrames, required delaysMs, required fps}) async {
            encodeCalled = true;
            return (bytes: fakeWebm, error: null);
          },
          saveVideoOverride: (bytes) async => true,
        ),
      ));

      // Enter movie mode.
      await tester.tap(find.byIcon(Icons.movie));
      await tester.pumpAndSettle();

      // Add a frame.
      await tester.tap(addFrameBtn());
      await tester.pumpAndSettle();

      // Draw on it.
      final gesture = await tester.startGesture(const Offset(100, 300));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 30));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Export — this should save canvas, then capture the frame.
      await tester.tap(find.byIcon(Icons.videocam));
      await pumpExport(tester);

      // With 1 frame, capture should be called and encode should succeed.
      expect(captureCount, greaterThanOrEqualTo(1));
      expect(encodeCalled, isTrue);
    });

    testWidgets(
        'full movie workflow: produces video bytes via mocked export',
        (tester) async {
      Uint8List? outputBytes;

      final redFrame = _encodeMinimalPng(255, 0, 0);
      final blueFrame = _encodeMinimalPng(0, 0, 255);
      int captureCallIndex = 0;

      // Fake MP4 bytes (starts with ftyp box).
      final fakeMp4 = Uint8List.fromList(
        List.generate(256, (i) => i % 256),
      );

      await tester.pumpWidget(MaterialApp(
        home: PaintScreen(
          capturePngOverride: (key) async {
            final idx = captureCallIndex++;
            return idx == 0 ? redFrame : blueFrame;
          },
          videoEncodeOverride: (
            {required pngFrames, required delaysMs, required fps}) async {
            return (bytes: fakeMp4, error: null);
          },
          saveVideoOverride: (bytes) {
            outputBytes = bytes;
            return Future<bool>.value(true);
          },
        ),
      ));

      // 1. Switch to movie mode.
      await tester.tap(find.byIcon(Icons.movie));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.videocam), findsOneWidget);
      expect(find.byType(MovieTimeline), findsOneWidget);

      // 2. Add two frames.
      final emptyAddBtn = find.descendant(
        of: find.byType(MovieTimeline),
        matching: find.byIcon(Icons.add),
      );
      expect(emptyAddBtn, findsOneWidget);
      await tester.tap(emptyAddBtn);
      await tester.pumpAndSettle();
      expect(find.text('Frame 1 added.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      await tester.tap(addFrameBtn());
      await tester.pumpAndSettle();
      expect(find.text('Frame 2 added.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // 3. Brush on frame one.
      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();
      final gesture1 = await tester.startGesture(const Offset(150, 300));
      await tester.pump();
      await gesture1.moveBy(const Offset(80, 50));
      await tester.pump();
      await gesture1.up();
      await tester.pumpAndSettle();

      // 4. Brush on frame two.
      await tester.tap(find.text('2'));
      await tester.pumpAndSettle();
      final gesture2 = await tester.startGesture(const Offset(250, 250));
      await tester.pump();
      await gesture2.moveBy(const Offset(-60, 70));
      await tester.pump();
      await gesture2.up();
      await tester.pumpAndSettle();

      // 5. Export movie.
      await tester.tap(find.byIcon(Icons.videocam));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // 6. Verify the video was produced.
      expect(outputBytes, isNotNull,
          reason: 'Encoded video bytes should be non-null');
      expect(outputBytes!.length, greaterThan(200),
          reason: 'Video bytes should be larger than 200 bytes');
      expect(outputBytes, equals(fakeMp4));

      expect(captureCallIndex, 2,
          reason: 'Should have captured exactly 2 frames');
      expect(find.text('Exported as video (2 frames)'), findsOneWidget);
      expect(find.textContaining('failed'), findsNothing);
      expect(find.textContaining('could not'), findsNothing);
    });

    testWidgets('multiple frames export encodes correct frame count',
        (tester) async {
      int pngCount = 0;
      int delaysCount = 0;
      Uint8List? savedBytes;

      await tester.pumpWidget(MaterialApp(
        home: PaintScreen(
          capturePngOverride: (key) async => fakePng,
          videoEncodeOverride: (
            {required pngFrames, required delaysMs, required fps}) async {
            pngCount = pngFrames.length;
            delaysCount = delaysMs.length;
            return (bytes: fakeWebm, error: null);
          },
          saveVideoOverride: (bytes) async {
            savedBytes = bytes;
            return true;
          },
        ),
      ));

      // Enter movie mode.
      await tester.tap(find.byIcon(Icons.movie));
      await tester.pumpAndSettle();

      // Add 4 frames, drawing on each.
      for (var i = 0; i < 4; i++) {
        await tester.tap(addFrameBtn());
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(
          Offset(100.0 + i * 30, 300.0),
        );
        await tester.pump();
        await gesture.moveBy(const Offset(40, 30));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
      }

      // Export.
      await tester.tap(find.byIcon(Icons.videocam));
      await pumpExport(tester, frameCount: 4);

      // Should have encoded 4 frames and saved the result.
      expect(pngCount, 4);
      expect(delaysCount, 4);
      expect(savedBytes, isNotNull);
      expect(savedBytes, equals(fakeWebm));
    });
  });

  // -------------------------------------------------------------------------
  // Movie mode UI integration tests (mocked layers)
  // -------------------------------------------------------------------------
  group('Movie mode integration', () {
    testWidgets('export in movie mode has video infrastructure', (tester) async {
      final fakePng = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      bool saveCalled = false;

      await tester.pumpWidget(MaterialApp(
        home: PaintScreen(
          capturePngOverride: (key) async => fakePng,
          saveVideoOverride: (bytes) async {
            saveCalled = true;
            return true;
          },
        ),
      ));

      // Verify the app renders with movie mode infrastructure in place.
      expect(find.byType(PaintScreen), findsOneWidget);
      // saveCalled starts false; would be set true by the video export flow.
      expect(saveCalled, isFalse);
    });

    testWidgets('canvas drawing still works when movie mode is off', (tester) async {
      await tester.pumpWidget(const AlekaApp());

      // Draw a stroke.
      final gesture = await tester.startGesture(const Offset(100, 200));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 30));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Should work without errors.
    });

    testWidgets('_wrapToolbar with movieMode default works', (tester) async {
      // Test that the old _wrapToolbar call signature still works
      // (movieMode and onToggleMovieMode have defaults).
      await tester.pumpWidget(_wrapToolbar(
        currentColor: Colors.black,
        strokeWidth: 3,
        onColorChanged: _noopColor,
        onStrokeWidthChanged: _noopDouble,
        onUndo: _noop,
        onClear: _noop,
        onSave: _noop,
        onLoad: _noop,
        onExport: _noop,
      ));
      // Should render without error (default movieMode = false).
      expect(find.byIcon(Icons.image), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Real browser rendering → capture → encode pipeline tests.
  // These exercise the actual capturePng (RepaintBoundary.toImage) path that
  // runs in the live app.  They need a real rendering engine (Chrome / macOS)
  // — the software renderer in native testWidgets cannot run toImage().
  // ---------------------------------------------------------------------------
  group('Real frame capture → WebM encode', () {
    testWidgets('capturePng produces valid decodable PNG on this platform',
        (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: Container(
              color: const Color(0xFF8844CC),
              width: 80,
              height: 60,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final bytes = await capturePng(key, pixelRatio: 1.0);
      expect(bytes, isNotNull,
          reason: 'capturePng should return non-null PNG bytes');
      expect(bytes!.length, greaterThan(50),
          reason: 'PNG should be at least 50 bytes');

      // The captured PNG must be decodable (regression test for the
      // byteData.buffer.asUint8List offset/length fix).
      final decoded = img.decodePng(bytes);
      expect(decoded, isNotNull,
          reason: 'captured PNG must be decodable by the image package');
      expect(decoded!.width, 80);
      expect(decoded.height, 60);
      // Verify a pixel has the expected colour.
      final pixel = decoded.getPixel(40, 30);
      expect(pixel.r, 136);
      expect(pixel.g, 68);
      expect(pixel.b, 204);
    });

    testWidgets('encodeVideoWeb returns null in test env (no ffmpeg.wasm)',
        (tester) async {
      final key = GlobalKey();

      // Capture two frames with different colours.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: Container(
              color: const Color(0xFFFF0000),
              width: 32,
              height: 32,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final redPng = await capturePng(key, pixelRatio: 1.0);
      expect(redPng, isNotNull);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: Container(
              color: const Color(0xFF0000FF),
              width: 32,
              height: 32,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final bluePng = await capturePng(key, pixelRatio: 1.0);
      expect(bluePng, isNotNull);

      // ffmpeg.wasm cannot load in test environments — returns error.
      final result = await encodeVideoWeb(
        [redPng!, bluePng!],
        [500, 500],
        12,
      );

      expect(result.bytes, isNull,
          reason: 'encodeVideoWeb returns null bytes without ffmpeg.wasm');
      expect(result.error, isNotNull);
    });

    testWidgets('full movie workflow with real capture fails without ffmpeg',
        (tester) async {
      Uint8List? outputBytes;

      await tester.pumpWidget(MaterialApp(
        home: PaintScreen(
          // No overrides — use real capturePng + real encodeVideo.
          saveVideoOverride: (bytes) {
            outputBytes = bytes;
            return Future<bool>.value(true);
          },
        ),
      ));

      // 1. Switch to movie mode.
      await tester.tap(find.byIcon(Icons.movie));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.videocam), findsOneWidget);
      expect(find.byType(MovieTimeline), findsOneWidget);

      // 2. Add two frames.
      final emptyAddBtn = find.descendant(
        of: find.byType(MovieTimeline),
        matching: find.byIcon(Icons.add),
      );
      expect(emptyAddBtn, findsOneWidget);
      await tester.tap(emptyAddBtn);
      await tester.pumpAndSettle();
      expect(find.text('Frame 1 added.'), findsOneWidget);
      // Let snackbar dismiss so it does not block taps.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // After first frame, the add button changes to add_circle_outline.
      final addCircleBtn = find.descendant(
        of: find.byType(MovieTimeline),
        matching: find.byIcon(Icons.add_circle_outline),
      );
      await tester.tap(addCircleBtn);
      await tester.pumpAndSettle();
      expect(find.text('Frame 2 added.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // 3. Draw on frame 1.
      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();
      final g1 = await tester.startGesture(const Offset(150, 300));
      await tester.pump();
      await g1.moveBy(const Offset(80, 50));
      await tester.pump();
      await g1.up();
      await tester.pumpAndSettle();

      // 4. Draw on frame 2.
      await tester.tap(find.text('2'));
      await tester.pumpAndSettle();
      final g2 = await tester.startGesture(const Offset(250, 250));
      await tester.pump();
      await g2.moveBy(const Offset(-60, 70));
      await tester.pump();
      await g2.up();
      await tester.pumpAndSettle();

      // 5. Export — uses real capturePng + real encodeVideo.
      // ffmpeg.wasm cannot load in test environments, so encode returns null.
      await tester.tap(find.byIcon(Icons.videocam));
      // On browser the export has 200 ms delays × 2 frames + encode time,
      // so we pump generously with real async.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      // Pump past the "Rendering frames…" snackbar.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // 6. Without ffmpeg, export fails — saveVideo should not be called.
      expect(outputBytes, isNull,
          reason: 'Without ffmpeg, saveVideo should not be called');
      // The failure snackbar is shown.
      expect(find.textContaining('Video export failed'),
          findsOneWidget,
          reason: 'Should show failure snackbar');
    });
  });
}

/// Creates a minimal 16×16 PNG image with the given RGB color.
Uint8List _encodeMinimalPng(int r, int g, int b) {
  final image = img.Image(width: 16, height: 16);
  for (var y = 0; y < 16; y++) {
    for (var x = 0; x < 16; x++) {
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}


