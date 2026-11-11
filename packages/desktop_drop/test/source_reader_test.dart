import 'dart:io';

import 'package:desktop_drop/src/native_transport.dart';
import 'package:desktop_drop/src/source_reader.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final transport = NativeTransport.testing();
  const reference = <Object?, Object?>{
    'view': 0,
    'generation': 1,
    'session': 2,
    'source': 3,
  };
  late Directory temporary;

  setUp(() async {
    NativeTransport.debugOverride = transport;
    temporary = await Directory.systemTemp.createTemp('desktop_drop_source_');
  });
  tearDown(() async {
    NativeTransport.debugOverride = null;
    transport.invokeHandler = null;
    await temporary.delete(recursive: true);
  });

  test(
    'provider files save all streamed bytes and close their reader',
    () async {
      final chunks = [
        Uint8List.fromList([1, 2]),
        Uint8List.fromList([3]),
      ];
      final operations = <String>[];
      transport.invokeHandler = (call) async {
        final args = call.arguments as Map;
        expect(args['source'], 3);
        final operation = args['op'] as String;
        operations.add(operation);
        return switch (operation) {
          'open' => 4,
          'read' => chunks.isEmpty ? Uint8List(0) : chunks.removeAt(0),
          'close' => null,
          _ => throw StateError('Unexpected operation: $operation'),
        };
      };
      final source = sourceFile(reference, 'song.pdf');
      final destination = File('${temporary.path}/copy.pdf');

      expect(source.name, 'song.pdf');
      expect(source.path, isEmpty);
      await source.saveTo(destination.path);

      expect(await destination.readAsBytes(), [1, 2, 3]);
      expect(operations, ['open', 'read', 'read', 'read', 'close']);
    },
  );

  test('length falls back to reading when a provider has no size', () async {
    var read = false;
    transport.invokeHandler = (call) async {
      final operation = (call.arguments as Map)['op'];
      switch (operation) {
        case 'stat':
          return <String, Object?>{};
        case 'open':
          return 4;
        case 'read':
          if (read) return Uint8List(0);
          read = true;
          return Uint8List.fromList([1, 2, 3]);
        case 'close':
          return null;
      }
      throw StateError('Unexpected operation: $operation');
    };

    expect(await sourceFile(reference, 'song.pdf').length(), 3);
  });

  test('promised files resolve once and copy through cross_file 0.3', () async {
    final original = File('${temporary.path}/promised.pdf');
    await original.writeAsBytes([5, 6, 7]);
    var resolutions = 0;
    transport.invokeHandler = (call) async {
      expect((call.arguments as Map)['op'], 'resolve');
      resolutions++;
      return original.path;
    };
    final source = sourceFile({...reference, 'resolvePath': true}, 'song.pdf');
    final destination = File('${temporary.path}/copy.pdf');

    expect(await source.readAsBytes(), [5, 6, 7]);
    await source.saveTo(destination.path);

    expect(resolutions, 1);
    expect(await destination.readAsBytes(), [5, 6, 7]);
    expect(await original.readAsBytes(), [5, 6, 7]);
  });

  test(
    'failed provider copies close the reader and propagate the error',
    () async {
      var closed = false;
      transport.invokeHandler = (call) async {
        switch ((call.arguments as Map)['op']) {
          case 'open':
            return 4;
          case 'read':
            throw PlatformException(code: 'source_expired');
          case 'close':
            closed = true;
            return null;
        }
        throw StateError('Unexpected operation');
      };

      await expectLater(
        sourceFile(reference, 'song.pdf').saveTo('${temporary.path}/copy.pdf'),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'source_expired',
          ),
        ),
      );
      expect(closed, isTrue);
    },
  );
}
