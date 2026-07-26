import 'dart:typed_data';

/// Stub for non-web platforms — returns `null`.
Future<Uint8List?> encodeVideoWeb(
  List<Uint8List> pngFrames,
  List<int> delaysMs,
  double fps,
) async {
  return null;
}
