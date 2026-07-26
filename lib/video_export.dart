import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'video_export_stub.dart'
    if (dart.library.html) 'video_export_web.dart';

/// Encodes a list of PNG frames into an MP4 video.
///
/// [pngFrames] — PNG-encoded bytes for each frame.
/// [delaysMs] — display duration for each frame in milliseconds.
/// [fps] — output framerate (frames per second).
///
/// On desktop: uses ffmpeg CLI to produce H.264 MP4. Requires ffmpeg
/// installed (detected at runtime; returns `null` with error message if
/// missing).
///
/// On web: uses ffmpeg.wasm via the [ffmpeg_wasm] package to produce MP4.
Future<Uint8List?> encodeVideo({
  required List<Uint8List> pngFrames,
  required List<int> delaysMs,
  required double fps,
}) async {
  if (pngFrames.isEmpty) return null;

  if (kIsWeb) {
    return await encodeVideoWeb(pngFrames, delaysMs, fps);
  }

  return await _encodeVideoDesktop(pngFrames, delaysMs, fps);
}

/// Desktop path: use system ffmpeg CLI.
Future<Uint8List?> _encodeVideoDesktop(
  List<Uint8List> pngFrames,
  List<int> delaysMs,
  double fps,
) async {
  // Check for ffmpeg.
  final ffmpegPath = await _findFfmpeg();
  if (ffmpegPath == null) return null;

  try {
    // Write frames to a temp directory.
    final tempDir = io.Directory.systemTemp.createTempSync('aleka_video_');
    try {
      // Write each PNG frame.
      for (var i = 0; i < pngFrames.length; i++) {
        final file = io.File(
          '${tempDir.path}/frame_${(i + 1).toString().padLeft(4, '0')}.png',
        );
        file.writeAsBytesSync(pngFrames[i]);
      }

      // Create concat file for per-frame timing.
      final concatFile = io.File('${tempDir.path}/concat.txt');
      final concatLines = <String>[];
      for (var i = 0; i < pngFrames.length; i++) {
        final durationSec = delaysMs[i] / 1000.0;
        concatLines.add(
          "file 'frame_${(i + 1).toString().padLeft(4, '0')}.png'",
        );
        concatLines.add('duration $durationSec');
      }
      // Last frame needs a second file reference (concat quirk).
      if (pngFrames.isNotEmpty) {
        concatLines.add(
          "file 'frame_${pngFrames.length.toString().padLeft(4, '0')}.png'",
        );
      }
      concatFile.writeAsStringSync(concatLines.join('\n'));

      // Run ffmpeg.
      final outputPath = '${tempDir.path}/output.mp4';
      final result = await io.Process.run(ffmpegPath, [
        '-y', // Overwrite.
        '-f', 'concat',
        '-safe', '0',
        '-i', 'concat.txt',
        '-c:v', 'libx264',
        '-pix_fmt', 'yuv420p',
        '-vf', "pad=ceil(iw/2)*2:ceil(ih/2)*2", // Even dimensions.
        outputPath,
      ], workingDirectory: tempDir.path);

      if (result.exitCode != 0) return null;

      final outputFile = io.File(outputPath);
      if (!outputFile.existsSync()) return null;

      return outputFile.readAsBytesSync();
    } finally {
      // Clean up temp directory.
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  } catch (_) {
    return null;
  }
}

/// Locates ffmpeg on the system PATH.
Future<String?> _findFfmpeg() async {
  try {
    final result = await io.Process.run('which', ['ffmpeg']);
    if (result.exitCode == 0) {
      final path = (result.stdout as String).trim();
      if (path.isNotEmpty) return path;
    }
  } catch (_) {}

  // Try common paths.
  for (final path in [
    '/usr/local/bin/ffmpeg',
    '/opt/homebrew/bin/ffmpeg',
    '/usr/bin/ffmpeg',
  ]) {
    if (io.File(path).existsSync()) return path;
  }

  return null;
}
