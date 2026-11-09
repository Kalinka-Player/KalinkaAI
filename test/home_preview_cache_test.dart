import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/home_preview_cache.dart';

void main() {
  test('inactive previews are bounded, reuse recent entries and do not evict active pins', () async {
    final built = <int, int>{};
    final provider = Provider.autoDispose.family<int, int>((ref, id) {
      retainHomePreview(ref);
      built.update(id, (count) => count + 1, ifAbsent: () => 1);
      return id;
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final active = container.listen(provider(-1), (_, _) {});
    for (var i = 0; i <= homePreviewIdleCacheSize; i++) {
      container.listen(provider(i), (_, _) {}).close();
      await container.pump();
    }
    expect(container.read(provider(0).exists), isFalse);
    expect(container.read(provider(-1).exists), isTrue);
    expect(container.read(provider(1).exists), isTrue);
    // Returning to a retained entry needs no rebuild and refreshes its recency.
    container.listen(provider(1), (_, _) {}).close();
    await container.pump();
    expect(built[1], 1);
    container.listen(provider(1000), (_, _) {}).close();
    await container.pump();
    expect(container.read(provider(1).exists), isTrue);
    expect(container.read(provider(2).exists), isFalse);
    active.close();
  });

  test('failed loads can release their cache entry immediately', () async {
    final provider = Provider.autoDispose<int>((ref) {
      retainHomePreview(ref)();
      return 0;
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(provider, (_, _) {}).close();
    await container.pump();
    expect(container.read(provider.exists), isFalse);
  });
}
