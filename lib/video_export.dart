import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'video_export_stub.dart'
    if (dart.library.html) 'video_export_web.dart';

/// Result of a video encoding operation.
///
/// When [bytes] is non-null the encoding succeeded and the field contains the
/// MP4 / WebM file.  When [bytes] is null, [error] provides a human-readable
/// description of what went wrong (e.g. "ffmpeg not found" or the stderr
/// produced by the ffmpeg CLI).
typedef VideoEncodeResult = ({Uint8List? bytes, String? error});

/// Signature for pluggable video encoding — used for testability.
typedef EncodeVideoFn = Future<VideoEncodeResult> Function({
  required List<Uint8List> pngFrames,
  required List<int> delaysMs,
  required double fps,
});

/// Encodes a list of PNG frames into an MP4 video.
///
/// [pngFrames] — PNG-encoded bytes for each frame.
/// [delaysMs] — display duration for each frame in milliseconds.
/// [fps] — output framerate (frames per second).
///
/// On desktop: uses ffmpeg CLI to produce H.264 MP4. Requires ffmpeg
/// installed (detected at runtime; returns error message if missing or
/// if ffmpeg exits with a non-zero code).
///
/// On web: uses ffmpeg.wasm to produce H.264 MP4.
Future<VideoEncodeResult> encodeVideo({
  required List<Uint8List> pngFrames,
  required List<int> delaysMs,
  required double fps,
}) async {
  if (pngFrames.isEmpty) {
    return (bytes: null, error: 'No frames to encode.');
  }

  if (kIsWeb) {
    return await encodeVideoWeb(pngFrames, delaysMs, fps);
  }

  return await _encodeVideoDesktop(pngFrames, delaysMs, fps);
}

/// Desktop path: use system ffmpeg CLI.
Future<VideoEncodeResult> _encodeVideoDesktop(
  List<Uint8List> pngFrames,
  List<int> delaysMs,
  double fps,
) async {
  // Check for ffmpeg.
  final (:path, :error) = await _findFfmpeg();
  if (path == null) {
    return (bytes: null, error: error ?? 'ffmpeg not found.');
  }

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
      final result = await io.Process.run(path, [
        '-y', // Overwrite.
        '-f', 'concat',
        '-safe', '0',
        '-i', 'concat.txt',
        '-c:v', 'libx264',
        '-pix_fmt', 'yuv420p',
        '-vf', "pad=ceil(iw/2)*2:ceil(ih/2)*2", // Even dimensions.
        outputPath,
      ], workingDirectory: tempDir.path);

      if (result.exitCode != 0) {
        final stderr = (result.stderr as String).trim();
        return (bytes: null, error: 'ffmpeg error (exit ${result.exitCode}): $stderr');
      }

      final outputFile = io.File(outputPath);
      if (!outputFile.existsSync()) {
        return (bytes: null, error: 'ffmpeg completed but output file was not created.');
      }

      return (bytes: outputFile.readAsBytesSync(), error: null);
    } finally {
      // Clean up temp directory.
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  } catch (e) {
    return (bytes: null, error: 'ffmpeg encoding failed: $e');
  }
}

/// Result of looking for the ffmpeg binary.
typedef _FfmpegLocation = ({String? path, String? error});

/// Locates ffmpeg on the system PATH.
Future<_FfmpegLocation> _findFfmpeg() async {
  // Try `which ffmpeg` first.
  try {
    final result = await io.Process.run('which', ['ffmpeg']);
    if (result.exitCode == 0) {
      final path = (result.stdout as String).trim();
      if (path.isNotEmpty) return (path: path, error: null);
    }
  } catch (_) {}

  // Try common paths.
  for (final path in [
    '/usr/local/bin/ffmpeg',
    '/opt/homebrew/bin/ffmpeg',
    '/usr/bin/ffmpeg',
  ]) {
    if (io.File(path).existsSync()) return (path: path, error: null);
  }

  return (
    path: null,
    error: 'ffmpeg not found. Install ffmpeg to export videos:\n'
        '  macOS:  brew install ffmpeg\n'
        '  Linux:  sudo apt install ffmpeg\n'
        '  Windows: choco install ffmpeg',
  );
}
