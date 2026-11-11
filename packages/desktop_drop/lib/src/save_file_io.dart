import 'dart:io';

import 'package:cross_file/cross_file.dart';

Future<void> saveFile(XFile file, String path) async {
  final sink = File(path).openWrite();
  try {
    await sink.addStream(file.openRead());
  } catch (_) {
    // addStream may already have closed the sink. Preserve the provider error.
    try {
      await sink.close();
    } catch (_) {}
    rethrow;
  }
  await sink.close();
}
