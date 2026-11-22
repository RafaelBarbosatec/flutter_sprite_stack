import 'dart:async';

import 'sprite_stack.dart';

/// Shares decoded strips between widgets, components and scenes.
///
/// Decoding a strip allocates a GPU texture; loading the same asset once per
/// prop is wasteful. The cache keys entries by `assetPath + sliceCount`, so
/// the same file can still be used with different slice counts.
///
/// ```dart
/// final stack = await SpriteStackCache.instance.load(
///   'assets/tree.png',
///   sliceCount: 28,
/// );
/// ```
///
/// Entries are shared: do **not** call [SpriteStack.dispose] on a cached stack.
/// Use [evict] or [clear] instead.
class SpriteStackCache {
  SpriteStackCache._();

  /// Process-wide cache instance.
  static final SpriteStackCache instance = SpriteStackCache._();

  final Map<String, Future<SpriteStack>> _entries =
      <String, Future<SpriteStack>>{};

  /// Number of cached entries, including ones still loading.
  int get length => _entries.length;

  /// Whether [key] is cached.
  bool containsKey(String key) => _entries.containsKey(key);

  /// Cache key used by [load].
  static String keyFor(String assetPath, int sliceCount) =>
      '$assetPath#$sliceCount';

  /// Returns a cached stack for [assetPath], loading and decoding it once.
  ///
  /// Failed loads are removed from the cache so a later call can retry.
  Future<SpriteStack> load(String assetPath, {required int sliceCount}) {
    final key = keyFor(assetPath, sliceCount);
    final cached = _entries[key];
    if (cached != null) return cached;

    final future = SpriteStack.load(assetPath, sliceCount: sliceCount);
    _entries[key] = future;
    // Remove failed entries; also consumes the error so it is not reported as
    // unhandled when the caller attaches their own handler later.
    future.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _entries.remove(key);
      },
    ).ignore();
    return future;
  }

  /// Stores an already-built stack under [key].
  ///
  /// Useful for tests and for stacks created with [SpriteStack.fromImage].
  void put(String key, SpriteStack stack) {
    _entries[key] = Future<SpriteStack>.value(stack);
  }

  /// Removes [key] from the cache.
  ///
  /// When [dispose] is true the cached stack is disposed as soon as it is
  /// available. Only do that when no other code is still using it.
  void evict(String key, {bool dispose = false}) {
    final entry = _entries.remove(key);
    if (dispose && entry != null) {
      entry
          .then<void>(
            (stack) => stack.dispose(),
            onError: (Object error, StackTrace stack) {},
          )
          .ignore();
    }
  }

  /// Removes every entry. Disposes cached stacks by default.
  void clear({bool dispose = true}) {
    final entries = _entries.values.toList();
    _entries.clear();
    if (!dispose) return;
    for (final entry in entries) {
      entry
          .then<void>(
            (stack) => stack.dispose(),
            onError: (Object error, StackTrace stack) {},
          )
          .ignore();
    }
  }
}
