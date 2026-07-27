import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

/// The color palette available in the toolbar.
const List<Color> _paletteColors = [
  Colors.black,
  Colors.white,
  Colors.grey,
  Colors.red,
  Colors.orange,
  Colors.yellow,
  Colors.green,
  Colors.teal,
  Colors.blue,
  Colors.indigo,
  Colors.purple,
  Colors.pink,
  Colors.brown,
  Color(0xFFFFF3E0), // light cream
  Color(0xFF8D6E63), // warm brown
];

/// A toolbar with color swatches, a brush-size slider, fill bucket, undo, and clear.
class PaintToolbar extends StatelessWidget {
  final Color currentColor;
  final double strokeWidth;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onStrokeWidthChanged;
  final VoidCallback onUndo;
  final VoidCallback onClear;
  final VoidCallback onSave;
  final VoidCallback onLoad;
  final VoidCallback onExport;
  final bool movieMode;
  final VoidCallback onToggleMovieMode;
  final bool fillTool;
  final VoidCallback onToggleFillTool;

  const PaintToolbar({
    super.key,
    required this.currentColor,
    required this.strokeWidth,
    required this.onColorChanged,
    required this.onStrokeWidthChanged,
    required this.onUndo,
    required this.onClear,
    required this.onSave,
    required this.onLoad,
    required this.onExport,
    this.movieMode = false,
    this.onToggleMovieMode = _noop,
    this.fillTool = false,
    this.onToggleFillTool = _noop,
  });

  static void _noop() {}

  bool _isCustomColor() => !_paletteColors.contains(currentColor);

  void _showColorPicker(BuildContext context) {
    Color pickedColor = currentColor;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Pick a color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: currentColor,
              onColorChanged: (color) => pickedColor = color,
              enableAlpha: false,
              labelTypes: const [],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                onColorChanged(pickedColor);
                Navigator.of(ctx).pop();
              },
              child: const Text('Select'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Color swatches
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ..._paletteColors.map((color) {
                      final isSelected = color == currentColor;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: GestureDetector(
                          onTap: () => onColorChanged(color),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : (isDark
                                        ? Colors.white24
                                        : Colors.black26),
                                width: isSelected ? 3 : 1,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: color.withValues(alpha: 0.5),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      );
                    }),
                    // Color picker button — highlighted when current color
                    // is not a preset (i.e. was chosen via the picker).
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: GestureDetector(
                        onTap: () => _showColorPicker(context),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _isCustomColor()
                                  ? (isDark ? Colors.white : Colors.black87)
                                  : (isDark ? Colors.white38 : Colors.black38),
                              width: _isCustomColor() ? 3 : 1.5,
                            ),
                            gradient: const SweepGradient(
                              colors: [
                                Colors.red,
                                Colors.yellow,
                                Colors.green,
                                Colors.cyan,
                                Colors.blue,
                                Colors.purple,
                                Colors.red,
                              ],
                            ),
                            boxShadow: _isCustomColor()
                                ? [
                                    BoxShadow(
                                      color: currentColor.withValues(alpha: 0.5),
                                      blurRadius: 6,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                          child: const Center(
                            child: Icon(Icons.add, size: 18, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const VerticalDivider(width: 20),

            // Brush size slider
            SizedBox(
              width: 120,
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: strokeWidth + 6,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: strokeWidth,
                      min: 1,
                      max: 30,
                      divisions: 29,
                      onChanged: onStrokeWidthChanged,
                    ),
                  ),
                ],
              ),
            ),

            const VerticalDivider(width: 20),

            // Fill bucket toggle
            IconButton(
              icon: Icon(Icons.format_color_fill),
              tooltip: fillTool ? 'Fill mode (on)' : 'Fill bucket',
              color: fillTool
                  ? Theme.of(context).colorScheme.primary
                  : null,
              onPressed: onToggleFillTool,
            ),

            // Undo
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Undo',
              onPressed: onUndo,
            ),

            // Clear
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear all',
              onPressed: onClear,
            ),

            const VerticalDivider(width: 20),

            // Save
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Save (.aleka)',
              onPressed: onSave,
            ),

            // Load
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: 'Load (.aleka)',
              onPressed: onLoad,
            ),

            const VerticalDivider(width: 20),

            // Movie mode toggle
            IconButton(
              icon: Icon(
                Icons.movie,
                color: movieMode
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              tooltip: movieMode ? 'Exit movie mode' : 'Movie mode',
              onPressed: onToggleMovieMode,
            ),

            // Export (PNG in draw mode, video in movie mode)
            IconButton(
              icon: Icon(movieMode ? Icons.videocam : Icons.image),
              tooltip: movieMode ? 'Export video' : 'Export as PNG',
              onPressed: onExport,
            ),
          ],
        ),
      ),
    );
  }
}
