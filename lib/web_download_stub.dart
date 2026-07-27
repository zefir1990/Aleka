import 'dart:typed_data';

/// Stub for non-web platforms — returns false.
Future<bool> downloadBytes(String fileName, Uint8List bytes, {String? mimeType}) async {
  return false;
}
