import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bound inactive width/filter/revision variants without background timers.
/// Active pins are retained by their consumers; Home's normal refresh supplies
/// freshness. Quick return visits reuse the most recently viewed entries.
const homePreviewIdleCacheSize = 32;

final _idleHomePreviewsProvider = Provider((ref) => _IdleHomePreviews());

class _IdleHomePreviews {
  final _entries = <Object, void Function()>{};

  void remove(Object key) => _entries.remove(key);

  void retain(Object key, void Function() release) {
    _entries.remove(key);
    _entries[key] = release;
    while (_entries.length > homePreviewIdleCacheSize) {
      _entries.remove(_entries.keys.first)!();
    }
  }
}

/// Returns a release callback so failures do not occupy a cache entry.
void Function() retainHomePreview(Ref ref) {
  final cache = ref.read(_idleHomePreviewsProvider);
  final key = Object();
  final link = ref.keepAlive();
  ref.onCancel(() {
    if (ref.mounted) cache.retain(key, link.close);
  });
  ref.onResume(() => cache.remove(key));
  ref.onDispose(() => cache.remove(key));
  return () {
    cache.remove(key);
    link.close();
  };
}

/// A resize within one bucket reuses the same request. The widest preview is
/// still bounded; artist probes have their own existing 100-item budget.
int homePreviewFetchLimit(int visibleCount) {
  var limit = 8;
  while (limit < visibleCount && limit < 64) {
    limit *= 2;
  }
  return limit;
}
