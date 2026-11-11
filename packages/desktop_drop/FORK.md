# SongbookPro compatibility fork

Based on [desktop_drop 0.9.2](https://pub.dev/packages/desktop_drop/versions/0.9.2)
from its published package archive (SHA-256
`1180229beb0342f7da0a407a33ea9dc9f7dafa5917458fe664c169f02ca63b50`).
The upstream license, native implementations,
FFI bindings, and tests are retained. The example app is adapted to the compatibility API.

This Git dependency retains iOS support while using `cross_file ^0.3.5+5`,
which is compatible with SongbookPro's file picker and sharing plugins. It does
not override their dependency constraints.

Changes from upstream:

- Remove the package and example from the monorepo workspace so they can be
  resolved independently, and remove the cross_file 0.4 federated packages.
- Construct local files with `XFile(path)`.
- Implement provider-backed files as `XFile` subclasses. `saveTo` streams to disk
  on native platforms; provider reads and errors still use the upstream transport.
  A provider without a reported size is read to determine its length. Unknown
  modification times use the Unix epoch; provider files have no filesystem path.
- Supply a package-local read-only `XDirectory`, since cross_file 0.3 has no
  directory API. Its `list()` stream contains `XFile` or `XDirectory` objects.
  It supports local, provider-backed, and virtual directories.
- Wrap browser files in `XFile` using Blob URLs and revoke them after `onDrop`.
- Adapt upstream tests and add provider-copy regression tests.

The app consumes provider files before its awaited `onDrop` callback completes,
so native providers remain available while files are staged for import.

From this package directory:

```sh
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter test --no-pub --platform chrome test/browser/web_drop_test.dart
dart run tool/test_native_bridge.dart
```
