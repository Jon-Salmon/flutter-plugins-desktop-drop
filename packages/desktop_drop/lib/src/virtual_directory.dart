import 'directory_stub.dart' if (dart.library.io) 'directory_io.dart';

/// Read-only directory abstraction supplied by desktop_drop.
///
/// cross_file 0.3 has no directory type. Entries are either XFile or XDirectory;
/// consume provider-backed entries before the onDrop callback completes.
abstract class XDirectory {
  XDirectory();
  factory XDirectory.fileSystem({required String path}) =>
      fileSystemDirectory(path);

  String get name;
  Future<bool> exists();
  Future<bool> canRead() => exists();
  Stream<Object> list();
  Future<void> dispose();
}

XDirectory virtualDirectory(String name, Stream<Object> Function() list) =>
    _VirtualDirectory(name, list);

final class _VirtualDirectory extends XDirectory {
  _VirtualDirectory(this.name, this.children);

  @override
  final String name;

  final Stream<Object> Function() children;
  bool _disposed = false;

  @override
  Future<bool> exists() async => !_disposed;
  @override
  Future<void> dispose() async {
    _disposed = true;
  }

  @override
  Stream<Object> list() async* {
    if (_disposed) throw StateError('Dropped directory has been released');
    await for (final entity in children()) {
      if (_disposed) throw StateError('Dropped directory has been released');
      yield entity;
    }
  }
}
