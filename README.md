# Aleka Paint

A cross-platform paint application built with [Flutter](https://flutter.dev). Draw, save, load, and export your sketches — works on the web, mobile phones, and desktop.

<img src="screenshot.png" alt="Aleka Paint screenshot" width="720"/>

## Features

- **Freehand drawing** — smooth strokes with quadratic Bézier interpolation
- **15-color palette** — pick from a curated set of colors with visual selection feedback
- **Adjustable brush size** — slider from 1 px to 30 px
- **Undo** — step backward through your strokes
- **Clear canvas** — wipe everything in one tap
- **Save** — persist your drawing as a `.aleka` file (JSON-based format)
- **Load** — open a `.aleka` file and continue drawing
- **Export as PNG** — capture the canvas at 3× resolution and download as a PNG image
- **🎬 Movie mode** — create frame-by-frame animations with an interactive timeline:
  - Add and remove frames, each holding their own drawing
  - Per-frame display duration (50 ms – 5 s)
  - Adjustable framerate (6, 8, 12, 15, 24, 30, or 60 FPS)
  - Export as **MP4 video** while in movie mode (requires ffmpeg on desktop; uses ffmpeg.wasm on web)
- **Light & dark theme** — follows your system preference via Material 3

## Supported platforms

| Platform | Status |
|----------|--------|
| Web (Chrome, Edge, Safari, Firefox) | ✅ |
| macOS | ✅ |
| Windows | ✅ |
| Linux | ✅ |
| iOS | ✅ |
| Android | ✅ |

## Getting started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.12+

### Install dependencies

```bash
flutter pub get
```

### Run

```bash
# Web
flutter run -d chrome

# macOS
flutter run -d macos

# Windows
flutter run -d windows

# Linux
flutter run -d linux

# iOS / Android (requires emulator or device)
flutter run
```

### Run tests

```bash
# All tests (widget + unit — 79 tests)
flutter test

# Code analysis
flutter analyze
```

## .aleka file format

A `.aleka` file is a human-readable JSON document:

```json
{
  "aleka": "1.0",
  "strokes": [
    {
      "color": 4278190080,
      "strokeWidth": 3.0,
      "points": [[100.0, 200.0], [150.0, 250.0]]
    }
  ]
}
```

| Field | Description |
|-------|-------------|
| `aleka` | Magic string + format version (`"1.0"`) |
| `strokes[]` | Ordered list of strokes |
| `.color` | ARGB32-encoded color (`Color.toARGB32()`) |
| `.strokeWidth` | Stroke width in logical pixels |
| `.points[]` | Ordered list of `[x, y]` coordinates |

## Project structure

```
lib/
├── main.dart             # App entry point, theme, PaintScreen with I/O wiring
├── paint_canvas.dart     # Stroke model, PaintCanvasController, CustomPainter
├── toolbar.dart          # Color palette, brush slider, action buttons
├── aleka_file.dart       # .aleka serialization, PNG capture, file I/O
├── movie_controller.dart # Frame model, MovieController for animation state
├── movie_timeline.dart   # Timeline widget with frame thumbnails & controls
├── video_export.dart     # MP4 video encoder (ffmpeg desktop / ffmpeg.wasm web)
├── video_export_web.dart # Web-specific MP4 export via ffmpeg.wasm
├── video_export_stub.dart# Non-web video export stub
├── web_download_web.dart # Web-specific file download (dart:html)
└── web_download_stub.dart# Non-web download stub
test/
└── widget_test.dart      # 79 tests: serialization, drawing, color picking,
                          #   undo, clear, save/load round-trip, PNG/video export,
                          #   Frame model, MovieController, timeline, movie mode
```

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
