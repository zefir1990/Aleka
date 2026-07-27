import 'package:flutter/material.dart';

import 'movie_controller.dart';

/// A horizontal timeline widget for viewing and managing animation frames.
///
/// Shown at the bottom of the screen when movie mode is active. Provides:
/// - Scrollable frame thumbnails with selection
/// - Add / remove frame buttons
/// - Per-frame duration controls
/// - FPS selector
class MovieTimeline extends StatefulWidget {
  final MovieController controller;
  final VoidCallback onAddFrame;
  final VoidCallback onRemoveFrame;
  final ValueChanged<int> onFrameSelected;
  final VoidCallback onPlayPause;

  const MovieTimeline({
    super.key,
    required this.controller,
    required this.onAddFrame,
    required this.onRemoveFrame,
    required this.onFrameSelected,
    required this.onPlayPause,
  });

  @override
  State<MovieTimeline> createState() => _MovieTimelineState();
}

class _MovieTimelineState extends State<MovieTimeline> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant MovieTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-scroll to the newly added frame.
    if (widget.controller.frameCount > oldWidget.controller.frameCount &&
        widget.controller.hasCurrentFrame) {
      _scrollToCurrentFrame();
    }
  }

  void _scrollToCurrentFrame() {
    if (!_scrollController.hasClients) return;
    final index = widget.controller.currentFrameIndex;
    const frameWidth = 72.0;
    const gap = 6.0;
    final offset = index * (frameWidth + gap);
    final viewportWidth = _scrollController.position.viewportDimension;
    if (offset < _scrollController.offset ||
          offset + frameWidth > _scrollController.offset + viewportWidth) {
      _scrollController.animateTo(
        (offset - viewportWidth / 2 + frameWidth / 2).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final frames = widget.controller.frames;
        final currentIndex = widget.controller.currentFrameIndex;

        return Container(
          height: 100,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border(
              top: BorderSide(
                color: theme.dividerColor,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Scrollable frame strip.
              Expanded(
                child: frames.isEmpty
                    ? Center(
                        child: Text(
                          'No frames — tap + to add one',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        itemCount: frames.length,
                        itemBuilder: (context, index) {
                          final frame = frames[index];
                          final isSelected = index == currentIndex;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: _FrameThumbnail(
                              index: index,
                              frame: frame,
                              isSelected: isSelected,
                              isDark: isDark,
                              theme: theme,
                              onTap: () => widget.onFrameSelected(index),
                            ),
                          );
                        },
                      ),
              ),

              // Right-side controls: duration, FPS, add, remove.
              if (frames.isNotEmpty)
                _ControlsPanel(
                  controller: widget.controller,
                  onAddFrame: widget.onAddFrame,
                  onRemoveFrame: widget.onRemoveFrame,
                  onPlayPause: widget.onPlayPause,
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: IconButton.filled(
                    icon: const Icon(Icons.add),
                    tooltip: 'Add frame',
                    onPressed: widget.onAddFrame,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A single frame thumbnail in the timeline.
class _FrameThumbnail extends StatelessWidget {
  final int index;
  final Frame frame;
  final bool isSelected;
  final bool isDark;
  final ThemeData theme;
  final VoidCallback onTap;

  const _FrameThumbnail({
    required this.index,
    required this.frame,
    required this.isSelected,
    required this.isDark,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasContent = frame.strokes.isNotEmpty;
    final dominantColor = hasContent ? frame.strokes.first.color : Colors.grey;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        decoration: BoxDecoration(
          color: hasContent
              ? dominantColor.withValues(alpha: isDark ? 0.3 : 0.12)
              : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : (isDark ? Colors.white24 : Colors.black26),
            width: isSelected ? 2.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${index + 1}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${frame.displayDuration.inMilliseconds} ms',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 9,
              ),
            ),
            Text(
              '${frame.strokes.length} stroke${frame.strokes.length == 1 ? '' : 's'}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Right-side panel with duration slider, FPS, and add/remove controls.
class _ControlsPanel extends StatelessWidget {
  final MovieController controller;
  final VoidCallback onAddFrame;
  final VoidCallback onRemoveFrame;
  final VoidCallback onPlayPause;

  const _ControlsPanel({
    required this.controller,
    required this.onAddFrame,
    required this.onRemoveFrame,
    required this.onPlayPause,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frame = controller.currentFrame;
    final durationMs = frame?.displayDuration.inMilliseconds ?? 500;
    final isPlaying = controller.isPlaying;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play / pause button.
          IconButton(
            icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
            tooltip: isPlaying ? 'Pause' : 'Play',
            onPressed: onPlayPause,
            iconSize: 22,
          ),
          // Loop toggle.
          IconButton(
            icon: Icon(
              Icons.loop,
              color: controller.looping
                  ? theme.colorScheme.primary
                  : null,
            ),
            tooltip: controller.looping ? 'Looping on' : 'Looping off',
            onPressed: () => controller.setLooping(!controller.looping),
            iconSize: 20,
          ),
          const SizedBox(width: 4),

          // Duration slider for current frame.
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${durationMs.round()} ms',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(
                width: 80,
                height: 20,
                child: Slider(
                  value: durationMs.toDouble().clamp(50, 5000),
                  min: 50,
                  max: 5000,
                  onChanged: (v) {
                    controller.setFrameDuration(
                      controller.currentFrameIndex,
                      Duration(milliseconds: v.round()),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),

          // FPS selector.
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('FPS', style: theme.textTheme.labelSmall),
              SizedBox(
                width: 60,
                child: _FpsDropdown(
                  value: controller.fps,
                  onChanged: (v) => controller.setFps(v),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),

          // Add frame button.
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Add frame',
            onPressed: onAddFrame,
            iconSize: 22,
          ),
          // Remove frame button — disabled for the first frame.
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: controller.currentFrameIndex == 0
                ? 'Cannot remove first frame'
                : 'Remove current frame',
            onPressed: controller.hasCurrentFrame &&
                    controller.currentFrameIndex != 0
                ? onRemoveFrame
                : null,
            iconSize: 22,
          ),
        ],
      ),
    );
  }
}

/// A compact dropdown for selecting FPS.
class _FpsDropdown extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _FpsDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<double>(
        value: _nearestFps(value),
        isExpanded: true,
        isDense: true,
        style: Theme.of(context).textTheme.bodySmall,
        items: const [
          DropdownMenuItem(value: 6, child: Text('6')),
          DropdownMenuItem(value: 8, child: Text('8')),
          DropdownMenuItem(value: 12, child: Text('12')),
          DropdownMenuItem(value: 15, child: Text('15')),
          DropdownMenuItem(value: 24, child: Text('24')),
          DropdownMenuItem(value: 30, child: Text('30')),
          DropdownMenuItem(value: 60, child: Text('60')),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }

  static double _nearestFps(double v) {
    const options = [6.0, 8.0, 12.0, 15.0, 24.0, 30.0, 60.0];
    return options.reduce((a, b) => (a - v).abs() < (b - v).abs() ? a : b);
  }
}
