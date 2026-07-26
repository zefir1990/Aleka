import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aleka/main.dart';
import 'package:aleka/paint_canvas.dart';
import 'package:aleka/toolbar.dart';
import 'package:aleka/aleka_file.dart';

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
      await tester.tap(_findColorSwatch(Colors.red));
      await tester.pumpAndSettle();
      await tester.tap(_findColorSwatch(Colors.blue));
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
}
