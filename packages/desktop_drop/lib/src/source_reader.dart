import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import 'virtual_directory.dart';
import 'save_file_stub.dart' if (dart.library.io) 'save_file_io.dart';

import 'package:flutter/services.dart';

import 'native_transport_stub.dart'
    if (dart.library.io) 'native_transport.dart';

// These are access references, not snapshots. The native provider can expire
// independently of the Dart objects; reads propagate its errors to the caller.
XFile sourceFile(Map<Object?, Object?> source, String name) =>
    _SourceFile(source, name);

XDirectory sourceDirectory(Map<Object?, Object?> source) =>
    _SourceDirectory(source);

/// Explicit access request; ordinary reads never show platform UI.
Future<void> requestSourceDirectoryAccess(XDirectory directory) async {
  final platform = directory;
  if (platform is! _SourceDirectory) {
    throw UnsupportedError('Directory is not backed by an Android drop source');
  }
  if (platform._disposed) throw StateError('Dropped source has been released');
  await _invoke<void>(platform.source, 'requestAccess');
}

Future<T?> _invoke<T>(
  Map<Object?, Object?> source,
  String operation, [
  Map<String, Object?> arguments = const {},
]) => NativeTransport.instance.invoke<T>('readSource', {
  ...source,
  'op': operation,
  ...arguments,
});

// Some providers receive a file on disk before it can be read. Resolve once;
// ordinary file operations then use the existing filesystem implementation.
Future<String?> _resolvePath(Map<Object?, Object?> source) async {
  if (source['resolvePath'] != true) return null;
  final path = await _invoke<String>(source, 'resolve');
  if (path == null || path.isEmpty) {
    throw StateError('Source did not return a file path');
  }
  return path;
}

final class _SourceFile extends XFile {
  _SourceFile(this.source, this.fileName) : super('');

  final Map<Object?, Object?> source;
  final String fileName;
  late final Future<XFile?> _file = _resolvePath(source)
      .then((path) => path == null ? null : XFile(path));
  bool _disposed = false;

  void _check() {
    if (_disposed) throw StateError('Dropped source has been released');
  }

  Future<bool> exists() async {
    _check();
    try {
      final file = await _file;
      if (file != null) {
        await file.length();
        return true;
      }
      await _invoke<Object>(source, 'stat');
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> canRead() => exists();
  Future<void> dispose() async {
    _disposed = true;
  }

  @override
  Future<DateTime> lastModified() async {
    _check();
    return await (await _file)?.lastModified() ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  Future<int> length() async {
    _check();
    final file = await _file;
    if (file != null) return file.length();
    final value = await _invoke<Map>(source, 'stat');
    return value?['length'] as int? ?? (await readAsBytes()).length;
  }

  @override
  String get name => fileName;
  @override
  String get path => '';
  @override
  Future<void> saveTo(String path) => saveFile(this, path);
  @override
  Future<Uint8List> readAsBytes() async {
    final builder = BytesBuilder(copy: false);
    await for (final bytes in openRead()) {
      builder.add(bytes);
    }
    return builder.takeBytes();
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      encoding.decodeStream(openRead());
  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    _check();
    final file = await _file;
    _check();
    if (file != null) {
      yield* file.openRead(start, end);
      return;
    }
    final stream = await _invoke<int>(source, 'open', {'start': start ?? 0});
    if (stream == null) throw StateError('Source did not return a reader');
    var remaining = end == null ? null : end - (start ?? 0);
    try {
      while (remaining == null || remaining > 0) {
        _check();
        final bytes = await _invoke<Uint8List>(source, 'read', {
          'stream': stream,
          'count': remaining == null ? 65536 : remaining.clamp(0, 65536),
        });
        if (bytes == null) throw StateError('Source did not return file data');
        if (bytes.isEmpty) break;
        yield bytes;
        if (remaining != null) remaining -= bytes.length;
      }
    } finally {
      // Release can race a read or a new drag. Do not mask the read error if the
      // provider has already closed this stream.
      try {
        await _invoke<void>(source, 'close', {'stream': stream});
      } on PlatformException {
        /* The source has already expired. */
      }
    }
  }
}

final class _SourceDirectory extends XDirectory {
  _SourceDirectory(this.source);
  @override
  String get name => source['name'] as String? ?? '';

  final Map<Object?, Object?> source;
  late final Future<XDirectory?> _directory = _resolvePath(source)
      .then((path) => path == null ? null : XDirectory.fileSystem(path: path));
  bool _disposed = false;
  @override
  Future<bool> exists() async {
    if (_disposed) return false;
    try {
      final directory = await _directory;
      if (directory != null) return await directory.exists();
      await _invoke<Object>(source, 'stat');
      return true;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> canRead() => exists();
  @override
  Future<void> dispose() async {
    _disposed = true;
  }

  @override
  Stream<Object> list() async* {
    if (_disposed) throw StateError('Dropped source has been released');
    final directory = await _directory;
    if (_disposed) throw StateError('Dropped source has been released');
    if (directory != null) {
      yield* directory.list();
      return;
    }
    final children = await _invoke<List>(source, 'list');
    if (children == null) {
      throw StateError('Source did not return directory entries');
    }
    for (final child in children.cast<Map>()) {
      if (_disposed) throw StateError('Dropped source has been released');
      final name = child['name'] as String? ?? '';
      final reference = <Object?, Object?>{
        ...source,
        'source': child['source'],
        'name': name,
      };
      final entity = child['isDirectory'] == true
          ? sourceDirectory(reference)
          : sourceFile(reference, name);
      yield entity;
    }
  }
}
