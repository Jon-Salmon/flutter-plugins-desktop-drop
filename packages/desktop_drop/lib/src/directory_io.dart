import 'dart:io';

import 'package:cross_file/cross_file.dart';

import 'virtual_directory.dart';

XDirectory fileSystemDirectory(String path) =>
    _FileSystemDirectory(Directory(path));

final class _FileSystemDirectory extends XDirectory {
  _FileSystemDirectory(this.directory);
  final Directory directory;

  @override
  String get name {
    final segments = directory.uri.pathSegments.where(
      (part) => part.isNotEmpty,
    );
    return segments.isEmpty ? directory.path : segments.last;
  }

  @override
  Future<bool> exists() => directory.exists();
  @override
  Future<void> dispose() async {}
  @override
  Stream<Object> list() async* {
    await for (final entity in directory.list()) {
      if (entity is Directory) {
        yield _FileSystemDirectory(entity);
      } else if (entity is File) {
        yield XFile(entity.path);
      }
    }
  }
}
