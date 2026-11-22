import 'sprite_stack.dart';

/// Shares decoded [SpriteStack]s by asset path.
///
/// Decoding a strip costs an image decode plus a full RGBA read-back and the
/// footprint mask build. Loading the same asset once per prop is pure waste, so
/// route every load through a cache — [instance] is the app-wide one, or create
/// your own to scope its lifetime:
///
/// ```dart
/// final stacks = SpriteStackCache();
/// final tree = await stacks.load('sprites/tree.png', sliceCount: 43);
/// final house = await stacks.load('sprites/house.png', sliceCount: 29);
/// // ...
/// stacks.clear(); // disposes both images
/// ```
class SpriteStackCache {
  /// Creates a cache.
  ///
  /// [loader] defaults to [SpriteStack.load]; override it to plug a custom
  /// decoder (or a fake in tests).
  SpriteStackCache({
    Future<SpriteStack> Function(String assetPath, int sliceCount)? loader,
  }) : _loader = loader ?? _defaultLoader;

  /// Process-wide cache, handy for examples and small games.
  static final SpriteStackCache instance = SpriteStackCache();

  final Future<SpriteStack> Function(String assetPath, int sliceCount) _loader;

  static Future<SpriteStack> _defaultLoader(
    String assetPath,
    int sliceCount,
  ) =>
      SpriteStack.load(assetPath, sliceCount: sliceCount);

  final Map<String, SpriteStack> _stacks = {};
  final Map<String, Future<SpriteStack>> _loading = {};

  /// How many assets are currently cached.
  int get length => _stacks.length;

  /// The cached stack for [assetPath], or `null` when it is not loaded.
  SpriteStack? operator [](String assetPath) => _stacks[assetPath];

  /// Whether [assetPath] is already decoded, without triggering a load.
  bool contains(String assetPath) => _stacks.containsKey(assetPath);

  /// Loads [assetPath] once and reuses the decoded stack afterwards.
  ///
  /// Concurrent calls for the same path share a single in-flight load.
  Future<SpriteStack> load(String assetPath, {required int sliceCount}) {
    final cached = _stacks[assetPath];
    if (cached != null) return Future.value(cached);

    final pending = _loading[assetPath];
    if (pending != null) return pending;

    final future = _loader(assetPath, sliceCount).then(
      (stack) {
        _stacks[assetPath] = stack;
        _loading.remove(assetPath);
        return stack;
      },
      onError: (Object error, StackTrace stackTrace) {
        _loading.remove(assetPath);
        throw error;
      },
    );
    _loading[assetPath] = future;
    return future;
  }

  /// Drops and disposes the stack cached for [assetPath].
  ///
  /// Do not evict an asset that is still being rendered.
  void evict(String assetPath) {
    _stacks.remove(assetPath)?.dispose();
  }

  /// Drops and disposes every cached stack.
  void clear() {
    for (final stack in _stacks.values) {
      stack.dispose();
    }
    _stacks.clear();
    _loading.clear();
  }
}
