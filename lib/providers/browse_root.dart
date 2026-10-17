import '../data_model/data_model.dart';
import 'kalinka_player_api_provider.dart';

/// All source roots in backend order, retaining the IDs returned by browse.
Future<List<BrowseItem>> browseAllRoots(KalinkaPlayerProxy api) async {
  final roots = <BrowseItem>[];
  var offset = 0;
  while (true) {
    final page = await api.browse('', offset: offset, limit: 100);
    roots.addAll(page.items);
    // A server may return fewer items than requested before reaching total.
    offset += page.items.length;
    if (page.items.isEmpty || offset >= page.total) return roots;
  }
}
