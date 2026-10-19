import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/listing_presentation_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/widgets/search/catalog_page_view.dart';
import 'package:kalinka/widgets/search_cards/artwork_grid_card.dart';
import 'package:kalinka/widgets/search_cards/search_album_row.dart';

BrowseItem _album(int n) => BrowseItem(
  id: 'kalinka:demo:album:a$n',
  name: 'Album $n',
  canBrowse: true,
  canAdd: true,
  album: Album(id: 'a$n', title: 'Album $n', year: 2000 + n),
);

class _AlbumsApi implements KalinkaPlayerProxy {
  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    final items = [
      for (var n = offset; n < 7 && n < offset + limit; n++) _album(n),
    ];
    return BrowseItemsList(offset, limit, 7, items);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final _page = CatalogPage.category(
  id: 'kalinka:demo:catalog:new',
  title: 'New Releases',
  preview: Preview(
    type: PreviewType.imageText,
    contentType: PreviewContentType.album,
  ),
);

Future<ProviderContainer> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      kalinkaProxyProvider.overrideWithValue(_AlbumsApi()),
      sharedPrefsProvider.overrideWithValue(
        await SharedPreferences.getInstance(),
      ),
      sourceModulesProvider.overrideWith((ref) => const <ModuleInfo>[]),
    ],
  );
  addTearDown(container.dispose);
  container.read(searchSessionProvider.notifier).openPage(_page);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: CatalogPageView(page: _page, onBackToCatalogs: () {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('an album catalog opens as a grid read across, then down', (
    tester,
  ) async {
    await _pump(tester, const Size(1000, 900));

    expect(find.byType(ArtworkGridCard), findsWidgets);
    expect(find.byType(SearchAlbumRow), findsNothing);
    final first = tester.getRect(find.text('Album 0'));
    final second = tester.getRect(find.text('Album 1'));
    expect(second.top, first.top);
    expect(second.left, greaterThan(first.left));
    // Covers stay about 180–220 wide rather than stretching to the pane.
    final card = tester.getSize(find.byType(ArtworkGridCard).first);
    expect(card.width, inInclusiveRange(150, 240));
  });

  testWidgets('List keeps rows, compact items across a wide pane', (
    tester,
  ) async {
    final container = await _pump(tester, const Size(1000, 900));

    await tester.tap(find.bySemanticsLabel('List view'));
    await tester.pumpAndSettle();

    expect(find.byType(ArtworkGridCard), findsNothing);
    expect(find.byType(SearchAlbumRow), findsWidgets);
    final first = tester.getRect(find.byType(SearchAlbumRow).at(0));
    final second = tester.getRect(find.byType(SearchAlbumRow).at(1));
    expect(second.top, first.top);
    expect(second.left, greaterThan(first.right));
    // Remembered for the family, not for this one page.
    expect(
      container
          .read(listingPresentationProvider.notifier)
          .of(ListingFamily.albums),
      ListingPresentation.list,
    );
  });

  testWidgets('a phone keeps one row per album in List', (tester) async {
    final container = await _pump(tester, const Size(390, 800));
    container
        .read(listingPresentationProvider.notifier)
        .set(ListingFamily.albums, ListingPresentation.list);
    await tester.pumpAndSettle();

    final first = tester.getRect(find.byType(SearchAlbumRow).at(0));
    final second = tester.getRect(find.byType(SearchAlbumRow).at(1));
    expect(second.top, greaterThan(first.bottom - 1));
    expect(tester.takeException(), isNull);
  });
}
