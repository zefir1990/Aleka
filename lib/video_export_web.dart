// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:typed_data';

import 'package:ffmpeg_wasm/ffmpeg_wasm.dart';

/// Web path: use ffmpeg.wasm to encode PNG frames to MP4.
///
/// Requires ffmpeg.wasm to be loaded (via a script tag in index.html) and
/// SharedArrayBuffer support (COOP/COEP headers).
Future<Uint8List?> encodeVideoWeb(
  List<Uint8List> pngFrames,
  List<int> delaysMs,
  double fps,
) async {
  try {
    final ffmpeg = createFFmpeg(CreateFFmpegParam(
      log: false,
      corePath:
          'https://unpkg.com/@ffmpeg/core@0.11.0/dist/ffmpeg-core.js',
    ));

    if (!ffmpeg.isLoaded()) {
      await ffmpeg.load();
    }

    if (!ffmpeg.isLoaded()) return null;

    // Write each PNG frame to the virtual filesystem.
    for (var i = 0; i < pngFrames.length; i++) {
      final fileName =
          'frame_${(i + 1).toString().padLeft(4, '0')}.png';
      ffmpeg.writeFile(fileName, pngFrames[i]);
    }

    // Build a concat file for per-frame timing.
    final concatLines = <String>[];
    for (var i = 0; i < pngFrames.length; i++) {
      final durationSec = delaysMs[i] / 1000.0;
      concatLines.add(
        "file 'frame_${(i + 1).toString().padLeft(4, '0')}.png'",
      );
      concatLines.add('duration ${durationSec.toStringAsFixed(6)}');
    }
    // Last frame needs a second file reference (concat demuxer quirk).
    if (pngFrames.isNotEmpty) {
      concatLines.add(
        "file 'frame_${pngFrames.length.toString().padLeft(4, '0')}.png'",
      );
    }
    ffmpeg.writeFile(
      'concat.txt',
      Uint8List.fromList(concatLines.join('\n').codeUnits),
    );

    // Run ffmpeg to create MP4.
    await ffmpeg.run([
      '-y',
      '-f', 'concat',
      '-safe', '0',
      '-i', 'concat.txt',
      '-c:v', 'libx264',
      '-pix_fmt', 'yuv420p',
      '-vf', "pad=ceil(iw/2)*2:ceil(ih/2)*2",
      'output.mp4',
    ]);

    // Read the output.
    final mp4Bytes = ffmpeg.readFile('output.mp4');

    // Clean up.
    ffmpeg.exit();

    return mp4Bytes;
  } catch (_) {
    return null;
  }
}
