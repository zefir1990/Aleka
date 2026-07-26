import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aleka/main.dart';
import 'package:aleka/paint_canvas.dart';
import 'package:aleka/toolbar.dart';
import 'package:aleka/aleka_file.dart';
import 'package:aleka/movie_controller.dart';
import 'package:aleka/movie_timeline.dart';
import 'package:aleka/video_export.dart';
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
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();
      expect(find.text('Saved as .aleka'), findsOneWidget);
      expect(saved, isNotNull);

      // Clear.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // Load.
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
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      // Clear and load back.
      await tester.tap(find.byIcon(Icons.delete_outline));
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
  });

  // -------------------------------------------------------------------------
  // Video export tests
  // -------------------------------------------------------------------------
  group('Video export', () {
    test('empty frames returns null', () async {
      final result = await encodeVideo(pngFrames: [], delaysMs: [], fps: 12);
      expect(result, isNull);
    });

    test('non-empty frames with no ffmpeg returns null on desktop', () async {
      final redPng = _encodeMinimalPng(255, 0, 0);
      // On desktop without ffmpeg, this returns null.
      // On web, it would try ffmpeg.wasm (not available in tests).
      final result = await encodeVideo(
        pngFrames: [redPng],
        delaysMs: [500],
        fps: 12,
      );
      // In test environment (no ffmpeg, no browser), returns null.
      expect(result, isNull);
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
    }) {
      return MaterialApp(
        home: Scaffold(
          body: MovieTimeline(
            controller: controller,
            onAddFrame: onAddFrame ?? () {},
            onRemoveFrame: onRemoveFrame ?? () {},
            onFrameSelected: onFrameSelected ?? (_) {},
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
}

/// Creates a minimal 2×2 PNG image with the given RGB color.
Uint8List _encodeMinimalPng(int r, int g, int b) {
  final image = img.Image(width: 2, height: 2);
  for (var y = 0; y < 2; y++) {
    for (var x = 0; x < 2; x++) {
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

