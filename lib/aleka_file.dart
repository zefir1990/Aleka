import 'dart:convert';
import 'dart:io' as io show File;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'paint_canvas.dart';
import 'web_download_stub.dart'
    if (dart.library.html) 'web_download_web.dart';

/// The header used to identify .aleka files.
const _alekaMagic = 'aleka';
const _alekaVersion = '1.1';

/// Serializes a list of [Stroke]s into the .aleka JSON format.
String serializeStrokes(List<Stroke> strokes) {
  final json = <String, dynamic>{
    _alekaMagic: _alekaVersion,
    'strokes': _strokesToJson(strokes),
  };
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(json);
}

List<Map<String, dynamic>> _strokesToJson(List<Stroke> strokes) {
  return strokes.map((s) {
    return {
      'color': s.color.toARGB32(),
      'strokeWidth': s.strokeWidth,
      'points': s.points
          .map((p) => [p.dx, p.dy])
          .toList(),
    };
  }).toList();
}

List<Stroke> _strokesFromJson(List<dynamic> strokesList) {
  return strokesList.map((s) {
    final map = s as Map<String, dynamic>;
    final points = (map['points'] as List<dynamic>).map((p) {
      final pair = p as List<dynamic>;
      return Offset(
        (pair[0] as num).toDouble(),
        (pair[1] as num).toDouble(),
      );
    }).toList();

    return Stroke(
      points: points,
      color: Color(map['color'] as int),
      strokeWidth: (map['strokeWidth'] as num).toDouble(),
    );
  }).toList();
}

/// Deserializes the .aleka JSON [source] into a list of [Stroke]s.
/// Returns `null` if the data is not a valid .aleka file.
List<Stroke>? deserializeStrokes(String source) {
  try {
    final json = jsonDecode(source) as Map<String, dynamic>;
    if (json[_alekaMagic] == null) return null;

    final strokesList = json['strokes'] as List<dynamic>?;
    if (strokesList == null) return const [];

    return _strokesFromJson(strokesList);
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Movie (animation) serialization
// ---------------------------------------------------------------------------

/// A single deserialized movie frame.
typedef MovieFrameData = ({
  List<Stroke> strokes,
  int durationMs,
});

/// The result of deserializing a movie-mode .aleka file.
typedef MovieLoadResult = ({
  double fps,
  List<MovieFrameData> frames,
});

/// Serializes all movie frames and FPS into the .aleka JSON format.
///
/// The resulting string is also valid for [deserializeStrokes] — the strokes
/// from the first frame are written at the top level so older versions of the
/// app can still read the drawing (in paint mode).
String serializeMovie({
  required double fps,
  required List<MovieFrameData> frames,
}) {
  final json = <String, dynamic>{
    _alekaMagic: _alekaVersion,
    'strokes': frames.isNotEmpty ? _strokesToJson(frames.first.strokes) : [],
    'movie': {
      'fps': fps,
      'frames': frames.map((f) {
        return {
          'strokes': _strokesToJson(f.strokes),
          'durationMs': f.durationMs,
        };
      }).toList(),
    },
  };
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(json);
}

/// Deserializes the .aleka JSON [source] into movie data.
///
/// Returns `null` if the data does not contain a valid movie section.
MovieLoadResult? deserializeMovie(String source) {
  try {
    final json = jsonDecode(source) as Map<String, dynamic>;
    if (json[_alekaMagic] == null) return null;

    final movie = json['movie'] as Map<String, dynamic>?;
    if (movie == null) return null; // Paint-mode file — no movie data.

    final fps = (movie['fps'] as num?)?.toDouble() ?? 12.0;
    final framesJson = movie['frames'] as List<dynamic>?;
    if (framesJson == null || framesJson.isEmpty) {
      return (fps: fps, frames: const []);
    }

    final frames = framesJson.map((f) {
      final map = f as Map<String, dynamic>;
      final strokes = _strokesFromJson(
          map['strokes'] as List<dynamic>? ?? []);
      final durationMs = (map['durationMs'] as num?)?.toInt() ?? 500;
      return (strokes: strokes, durationMs: durationMs);
    }).toList();

    return (fps: fps, frames: frames);
  } catch (_) {
    return null;
  }
}

/// Prompts the user to save [content] to a `.aleka` file.
///
/// [fileName] defaults to `drawing.aleka`.
///
/// Returns `true` on success, `false` if cancelled or errored.
Future<bool> saveAlekaContent(String content, {String fileName = 'drawing.aleka'}) async {
  final bytes = utf8.encode(content);

  try {
    if (kIsWeb) {
      return await downloadBytes(fileName, bytes);
    } else {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save drawing as .aleka',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['aleka'],
      );
      if (path == null) return false; // User cancelled.
      await io.File(path).writeAsBytes(bytes);
      return true;
    }
  } catch (_) {
    return false;
  }
}

/// Prompts the user to open a `.aleka` file and returns its raw content.
///
/// Returns `null` if cancelled, errored, or the file could not be read.
Future<String?> loadAlekaContent() async {
  try {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open .aleka drawing',
      type: FileType.custom,
      allowedExtensions: ['aleka'],
      withData: kIsWeb, // Read bytes in memory on web.
    );

    if (result == null || result.files.isEmpty) return null;

    if (kIsWeb) {
      final bytes = result.files.single.bytes;
      if (bytes == null) return null;
      return utf8.decode(bytes);
    } else {
      final path = result.files.single.path;
      if (path == null) return null;
      return await io.File(path).readAsString();
    }
  } catch (_) {
    return null;
  }
}

/// Prompts the user to save strokes to a `.aleka` file.
///
/// Returns `true` on success, `false` if cancelled or errored.
Future<bool> saveToFile(List<Stroke> strokes) async {
  return saveAlekaContent(serializeStrokes(strokes));
}

/// Prompts the user to load strokes from a `.aleka` file.
///
/// Returns the deserialized strokes on success, or `null` if cancelled/errored.
Future<List<Stroke>?> loadFromFile() async {
  final content = await loadAlekaContent();
  if (content == null) return null;
  return deserializeStrokes(content);
}

/// Captures the widget behind [repaintKey] as PNG bytes.
///
/// [repaintKey] must be attached to a [RepaintBoundary].
///
/// On web the pixel ratio defaults to 1.0 because CanvasKit already renders
/// at the device pixel ratio — stacking another multiplier on top produces
/// enormous images that strain browser memory during video encoding.
/// Desktop defaults to 2.0 for higher-quality captures.
Future<Uint8List?> capturePng(GlobalKey repaintKey, {double? pixelRatio}) async {
  final effectiveRatio = pixelRatio ?? (kIsWeb ? 1.0 : 2.0);
  try {
    final boundary =
        repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final image = await boundary.toImage(pixelRatio: effectiveRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;
    // Use offsetInBytes / lengthInBytes — byteData may be a view into a
    // larger buffer, and asUint8List() without parameters reads from offset 0
    // which can include garbage bytes that break PNG decoders.
    return byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
  } catch (_) {
    return null;
  }
}

/// Prompts the user to save PNG [bytes] to a file.
///
/// Returns `true` on success, `false` if cancelled or errored.
Future<bool> savePngToFile(Uint8List bytes) async {
  const fileName = 'drawing.png';

  try {
    if (kIsWeb) {
      return await downloadBytes(fileName, bytes);
    } else {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export as PNG',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['png'],
      );
      if (path == null) return false;
      await io.File(path).writeAsBytes(bytes);
      return true;
    }
  } catch (_) {
    return false;
  }
}

/// Prompts the user to save video [bytes] to a file.
///
/// Returns `true` on success, `false` if cancelled or errored.
Future<bool> saveVideoToFile(Uint8List bytes) async {
  const fileName = 'animation.mp4';
  const extensions = <String>['mp4'];

  try {
    if (kIsWeb) {
      return await downloadBytes(fileName, bytes, mimeType: 'video/mp4');
    } else {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export video',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: extensions,
      );
      if (path == null) return false;
      await io.File(path).writeAsBytes(bytes);
      return true;
    }
  } catch (_) {
    return false;
  }
}
