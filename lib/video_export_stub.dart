import 'dart:typed_data';

/// Stub for non-web platforms — returns an error result.
Future<({Uint8List? bytes, String? error})> encodeVideoWeb(
  List<Uint8List> pngFrames,
  List<int> delaysMs,
  double fps,
) async {
  return (bytes: null, error: 'encodeVideoWeb is not supported on this platform.');
}
