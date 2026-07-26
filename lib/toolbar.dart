import 'package:flutter/material.dart';

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

/// A toolbar with color swatches, a brush-size slider, undo, and clear.
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
  });

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
                  children: _paletteColors.map((color) {
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
                  }).toList(),
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

            // Export PNG
            IconButton(
              icon: const Icon(Icons.image),
              tooltip: 'Export as PNG',
              onPressed: onExport,
            ),
          ],
        ),
      ),
    );
  }
}
