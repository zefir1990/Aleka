// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:typed_data';

import 'package:ffmpeg_wasm/ffmpeg_wasm.dart';
import 'package:flutter/foundation.dart' show debugPrint;

// ---------------------------------------------------------------------------
// Lazy ffmpeg.wasm singleton — loading the WASM binary is expensive (~25 MB
// download + compilation), so we reuse the instance across exports.
// ---------------------------------------------------------------------------
FFmpeg? _ffmpeg;
bool _ffmpegLoadAttempted = false;
String? _ffmpegLoadError;

Future<FFmpeg?> _getFfmpeg() async {
  if (_ffmpeg != null) return _ffmpeg;
  if (_ffmpegLoadAttempted) return null;
  _ffmpegLoadAttempted = true;

  try {
    final ffmpeg = createFFmpeg(CreateFFmpegParam(log: false));
    await ffmpeg.load();
    _ffmpeg = ffmpeg;
    return ffmpeg;
  } catch (e) {
    debugPrint('ffmpeg.wasm: failed to load — $e');
    _ffmpegLoadError = '$e';
    return null;
  }
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Web path: encodes PNG frames to MP4 video using ffmpeg.wasm.
///
/// Returns a record with `bytes` set on success, or `error` on failure.
Future<({Uint8List? bytes, String? error})> encodeVideoWeb(
  List<Uint8List> pngFrames,
  List<int> delaysMs,
  double fps,
) async {
  if (pngFrames.isEmpty) {
    return (bytes: null, error: 'No frames to encode.');
  }

  final ffmpeg = await _getFfmpeg();
  if (ffmpeg == null) {
    final detail = _ffmpegLoadError ?? 'unknown reason';
    return (bytes: null, error: 'ffmpeg.wasm failed to load: $detail');
  }

  // Capture ffmpeg's own error output so we can surface it when something
  // goes wrong instead of just saying "empty file".
  final stderrLines = <String>[];
  ffmpeg.setLogger((logger) {
    if (logger.type == 'fferr') {
      stderrLines.add(logger.message);
    }
  });

  try {
    // Write each PNG frame to ffmpeg's in-memory filesystem (MEMFS).
    final fileNames = <String>[];
    for (var i = 0; i < pngFrames.length; i++) {
      final name = 'frame_${(i + 1).toString().padLeft(4, '0')}.png';
      ffmpeg.writeFile(name, pngFrames[i]);
      fileNames.add(name);
    }

    // Build a concat demuxer file with per-frame durations.
    final concatLines = <String>[];
    for (var i = 0; i < pngFrames.length; i++) {
      concatLines.add("file '${fileNames[i]}'");
      concatLines.add('duration ${delaysMs[i] / 1000.0}');
    }
    // Concat quirk: last frame needs a second file reference.
    if (pngFrames.isNotEmpty) {
      concatLines.add("file '${fileNames.last}'");
    }
    ffmpeg.writeFile('concat.txt', Uint8List.fromList(
        concatLines.join('\n').codeUnits));

    // Encode: concat demuxer → H.264 MP4.
    // `-vf pad=...` ensures even dimensions (required by libx264).
    // NOTE: runCommand splits by spaces and passes tokens directly to ffmpeg
    // (no shell).  Do NOT add shell-style quoting around filter arguments.
    await ffmpeg.runCommand(
      '-y -f concat -safe 0 -i concat.txt '
      '-c:v libx264 -pix_fmt yuv420p '
      '-vf pad=ceil(iw/2)*2:ceil(ih/2)*2 '
      'output.mp4',
    );

    // Read the output file.
    final output = ffmpeg.readFile('output.mp4');

    // Clean up MEMFS to free memory.
    for (final name in fileNames) {
      ffmpeg.unlink(name);
    }
    ffmpeg.unlink('concat.txt');
    ffmpeg.unlink('output.mp4');

    if (output.isEmpty) {
      final detail = stderrLines.isNotEmpty
          ? stderrLines.join('; ')
          : 'ffmpeg produced no output (no stderr captured)';
      return (bytes: null, error: 'ffmpeg.wasm: $detail');
    }
    return (bytes: output, error: null);
  } catch (e, st) {
    debugPrint('ffmpeg.wasm encode error: $e\n$st');
    final detail = stderrLines.isNotEmpty
        ? '${stderrLines.join('; ')} ($e)'
        : '$e';
    return (bytes: null, error: 'ffmpeg.wasm: $detail');
  }
}
