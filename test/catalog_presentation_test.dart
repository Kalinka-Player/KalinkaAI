import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:kalinka/widgets/keyboard/app_keyboard_navigation.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/search_cards/action_pill_button.dart';

import 'support/focus.dart';

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

/// The local library's root as the server lists it while AI search is on.
class _LibraryRootApi extends _AlbumsApi {
  static const root = 'kalinka:localfiles:catalog:root';
  static const forYou = 'kalinka:localfiles:catalog:for-you';

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    if (id != root) return super.browse(id, offset: offset, limit: limit);
    final card = BrowseItem.fromJson({
      'id': forYou,
      'name': 'Albums you may like',
      'subname': 'Picked from what you play to the end',
      'can_browse': true,
      'can_add': false,
      'catalog': {
        'id': forYou,
        'title': 'Albums you may like',
        'description': 'Picked from what you play to the end',
        'image': {
          'thumbnail': '/resource/catalog-art/albums-v1-thumbnail.jpg',
          'small': '/resource/catalog-art/albums-v1-small.jpg',
          'large': '/resource/catalog-art/albums-v1-large.jpg',
          'aspect_ratio': 3.0,
        },
        'preview_config': {
          'type': 'image',
          'content_type': 'album',
          'icon': 'ai_suggestions',
          'items_count': 10,
          'rows_count': 1,
          'card_size': 'small',
        },
        'role': 'discovery',
      },
    });
    return BrowseItemsList(offset, limit, 1, [card]);
  }
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

  for (final compact in [false, true]) {
    testWidgets(
      'focus follows the active Play and view buttons (compact $compact)',
      (tester) async {
        const layout = ListingLayout(
          'album',
          byDefault: ListingPresentation.grid,
        );
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
            child: MaterialApp(
              home: Scaffold(
                body: AppKeyboardNavigation(
                  child: AppKeyboardRegion(
                    area: AppKeyboardArea.content,
                    child: Row(
                      children: [
                        ActionPillButton(
                          label: 'Play all',
                          primary: true,
                          onTap: () {},
                        ),
                        PresentationToggle(layout: layout, compact: compact),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final play = find.byType(ActionPillButton);
        final toggle = find.byType(PresentationToggle);
        Finder ring(Finder target) =>
            focusOutlineIn(target, KalinkaColors.textPrimary);
        expect(ring(play), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(ring(play), findsOneWidget);
        expect(
          tester.getRect(ring(play)),
          tester.getRect(
            find.descendant(of: play, matching: find.byType(InkWell)),
          ),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(ring(play), findsNothing);
        if (!compact) {
          expect(ring(find.byTooltip('Grid view')), findsOneWidget);
          expect(ring(find.byTooltip('List view')), findsNothing);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
        }
        final listRing = ring(find.byTooltip('List view'));
        final bounds = tester.getRect(toggle);
        expect(
          tester.getRect(listRing),
          Rect.fromCenter(
            center: compact
                ? bounds.center
                : Offset(
                    bounds.right - kKalinkaPillTarget / 2,
                    bounds.center.dy,
                  ),
            width: compact ? kKalinkaPillHeight : kKalinkaPillTarget,
            height: kKalinkaPillHeight,
          ),
        );
        final shape =
            (tester.widget<DecoratedBox>(listRing).decoration
                    as ShapeDecoration)
                .shape;
        if (compact) {
          expect(shape, isA<CircleBorder>());
        } else {
          expect(
            (shape as RoundedRectangleBorder).borderRadius,
            const BorderRadiusDirectional.horizontal(
              end: Radius.circular(kKalinkaPillRadius),
            ),
          );
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          ProviderScope.containerOf(tester.element(toggle))
              .read(listingPresentationProvider)[layout.id],
          ListingPresentation.list,
        );
        expect(focusIsOn(toggle), isTrue);
        expect(ring(toggle), findsOneWidget);
      },
    );
  }

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

  testWidgets('the library\'s recommended albums open as an album grid', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      const Size(1000, 900),
      page: const CatalogPage.category(
        id: _LibraryRootApi.root,
        title: 'My Library',
        provider: 'localfiles',
      ),
      api: _LibraryRootApi(),
    );

    final card = find.text('Albums you may like');
    expect(card, findsOneWidget);
    await tester.tap(card);
    await tester.pumpAndSettle();

    final opened = container.read(searchSessionProvider).catalogPage;
    expect(opened.id, _LibraryRootApi.forYou);
    expect(opened.preview?.contentType, PreviewContentType.album);
    // The harness shows the page it was given, so show the one opened.
    await _pump(tester, const Size(1000, 900), page: opened);
    expect(find.byType(ArtworkGridCard), findsWidgets);
    expect(find.byType(SearchAlbumRow), findsNothing);
    expect(find.text('Album 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  // Banners stay at least 300 across: one to a row in a 516 window, two
  // side by side once there is room for both.
  for (final declared in [true, false]) {
    for (final (width, across) in [(516.0, false), (700.0, true)]) {
      testWidgets(
        'category banners have room with metadata=$declared at $width',
        (tester) async {
          await _pump(
            tester,
            Size(width, 800),
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
          expect(tester.getSize(cards.first).width, greaterThanOrEqualTo(300));
          final first = tester.getRect(cards.at(0));
          final second = tester.getRect(cards.at(1));
          if (across) {
            expect(second.top, first.top);
            expect(second.left, greaterThan(first.left));
          } else {
            expect(second.top, greaterThan(first.top));
            expect(second.left, first.left);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
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
