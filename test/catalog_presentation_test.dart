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
import 'package:kalinka/widgets/browse_filters/presentation_toggle.dart';
import 'package:kalinka/widgets/search/catalog_page_view.dart';
import 'package:kalinka/widgets/search_cards/artwork_grid_card.dart';
import 'package:kalinka/widgets/search_cards/search_album_row.dart';
import 'package:kalinka/widgets/source_badge.dart';

BrowseItem _album(int n) => BrowseItem(
  id: 'kalinka:demo:album:a$n',
  name: 'Album $n',
  canBrowse: true,
  canAdd: true,
  album: Album(id: 'a$n', title: 'Album $n', year: 2000 + n),
);

class _AlbumsApi implements KalinkaPlayerProxy {
  final bool catalogs;
  final bool mixed;
  _AlbumsApi({this.catalogs = false, this.mixed = false});
  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    final items = [
      for (var n = offset; n < 7 && n < offset + limit; n++)
        if (catalogs)
          BrowseItem(
            id: 'kalinka:demo:catalog:$n',
            name: 'Category $n',
            canBrowse: true,
            canAdd: false,
            catalog: Catalog(id: '$n', title: 'Category $n'),
          )
        else if (mixed && n == 1)
          BrowseItem(
            id: 'kalinka:other:album:$n',
            canBrowse: true,
            canAdd: true,
            album: Album(id: '$n', title: 'Album $n'),
          )
        else
          _album(n),
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
  provider: 'demo',
  preview: Preview(
    type: PreviewType.imageText,
    contentType: PreviewContentType.album,
  ),
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Size size, {
  CatalogPage? page,
  _AlbumsApi? api,
}) async {
  final shown = page ?? _page;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      kalinkaProxyProvider.overrideWithValue(api ?? _AlbumsApi()),
      sharedPrefsProvider.overrideWithValue(
        await SharedPreferences.getInstance(),
      ),
      sourceModulesProvider.overrideWith(
        (ref) => [
          for (final name in ['demo', 'other'])
            ModuleInfo(
              name: name,
              title: name,
              enabled: true,
              state: ModuleState.ready,
            ),
        ],
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(searchSessionProvider.notifier).openPage(shown);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          // Grid/List sits in the bar above the page, as Find Music sets it.
          body: Column(
            children: [
              Consumer(
                builder: (context, ref, _) {
                  final layout = CatalogPageView.presentationLayoutOf(
                    ref.watch(searchSessionProvider),
                  );
                  return layout == null
                      ? const SizedBox.shrink()
                      : PresentationToggle(layout: layout);
                },
              ),
              Expanded(
                child: CatalogPageView(page: shown, onBackToCatalogs: () {}),
              ),
            ],
          ),
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

  testWidgets('List is a table, one row per line on a wide pane', (
    tester,
  ) async {
    final container = await _pump(tester, const Size(1000, 900));

    await tester.tap(find.bySemanticsLabel('List view'));
    await tester.pumpAndSettle();

    expect(find.byType(ArtworkGridCard), findsNothing);
    expect(find.byType(SearchAlbumRow), findsWidgets);
    final first = tester.getRect(find.byType(SearchAlbumRow).at(0));
    final second = tester.getRect(find.byType(SearchAlbumRow).at(1));
    expect(second.top, greaterThan(first.bottom));
    expect(second.left, first.left);
    // Remembered for this listing, on this device.
    expect(
      container.read(listingPresentationProvider)[_page.id],
      ListingPresentation.list,
    );
  });

  testWidgets('another album catalog keeps its own default', (tester) async {
    SharedPreferences.setMockInitialValues({
      'Kalinka.listingPresentation.v2': '{"kalinka:demo:catalog:old":"list"}',
    });
    await _pump(tester, const Size(1000, 900));
    expect(find.byType(ArtworkGridCard), findsWidgets);
  });

  testWidgets('a catalog previewed as rows opens as rows', (tester) async {
    await _pump(
      tester,
      const Size(1000, 900),
      page: CatalogPage.category(
        id: 'kalinka:demo:catalog:tiles',
        title: 'Tiles',
        preview: Preview(
          type: PreviewType.tile,
          contentType: PreviewContentType.album,
        ),
      ),
    );
    expect(find.byType(ArtworkGridCard), findsNothing);
    expect(find.byType(SearchAlbumRow), findsWidgets);
    expect(find.bySemanticsLabel('Grid view'), findsOneWidget);
  });

  testWidgets('a catalog of tracks offers no grid', (tester) async {
    await _pump(
      tester,
      const Size(1000, 900),
      page: CatalogPage.category(
        id: 'kalinka:demo:catalog:tracks',
        title: 'Tracks',
        preview: Preview(
          type: PreviewType.imageText,
          contentType: PreviewContentType.track,
        ),
      ),
    );
    expect(find.bySemanticsLabel('Grid view'), findsNothing);
    expect(find.byType(ArtworkGridCard), findsNothing);
  });

  testWidgets('a phone keeps one row per album in List', (tester) async {
    final container = await _pump(tester, const Size(390, 800));
    container
        .read(listingPresentationProvider.notifier)
        .set(
          ListingLayout.of(_page.id!, _page.preview)!,
          ListingPresentation.list,
        );
    await tester.pumpAndSettle();

    final first = tester.getRect(find.byType(SearchAlbumRow).at(0));
    final second = tester.getRect(find.byType(SearchAlbumRow).at(1));
    expect(second.top, greaterThan(first.bottom - 1));
    expect(tester.takeException(), isNull);
  });

  for (final declared in [true, false]) {
    testWidgets('category banners have room with metadata=$declared', (
      tester,
    ) async {
      await _pump(
        tester,
        const Size(516, 800),
        api: _AlbumsApi(catalogs: true),
        page: CatalogPage.category(
          id: 'kalinka:demo:catalog:home',
          title: 'Home',
          provider: 'demo',
          preview: Preview(
            type: PreviewType.imageText,
            contentType: declared ? PreviewContentType.catalog : null,
          ),
        ),
      );
      final cards = find.byType(ArtworkGridCard);
      expect(tester.getSize(cards.first).width, greaterThanOrEqualTo(220));
      final first = tester.getRect(cards.at(0));
      final second = tester.getRect(cards.at(1));
      expect(second.top, first.top);
      expect(second.left, greaterThan(first.left));
      expect(tester.takeException(), isNull);
    });
  }

  for (final mixed in [false, true]) {
    testWidgets('source attribution in grid and list: mixed=$mixed', (
      tester,
    ) async {
      await _pump(tester, const Size(516, 800), api: _AlbumsApi(mixed: mixed));
      for (final rows in [false, true]) {
        if (rows) {
          await tester.tap(find.bySemanticsLabel('List view'));
          await tester.pumpAndSettle();
        }
        final items = find.byType(rows ? SearchAlbumRow : ArtworkGridCard);
        final badges = find.descendant(
          of: items,
          matching: find.byType(SourceBadge),
        );
        expect(badges, mixed ? findsWidgets : findsNothing);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('wide single-source rows omit the redundant Source column', (
    tester,
  ) async {
    await _pump(
      tester,
      const Size(1200, 800),
      page: CatalogPage.category(
        id: 'kalinka:demo:catalog:wide',
        title: 'Albums',
        provider: 'demo',
        preview: Preview(type: PreviewType.tile),
      ),
    );
    expect(find.text('SOURCE'), findsNothing);
    expect(find.text('ARTIST'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SearchAlbumRow),
        matching: find.byType(SourceBadge),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
