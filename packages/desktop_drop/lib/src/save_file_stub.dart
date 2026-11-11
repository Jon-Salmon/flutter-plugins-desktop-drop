import 'package:cross_file/cross_file.dart';

Future<void> saveFile(XFile file, String path) async {
  await XFile.fromData(await file.readAsBytes(), name: file.name).saveTo(path);
}
