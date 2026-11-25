import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/server_refusal.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/toast_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/browse_filters/presentation_toggle.dart';
import 'package:kalinka/widgets/fitted_title.dart';
import 'package:kalinka/widgets/home/catalog_pin_button.dart';
import 'package:kalinka/widgets/search/album_page_header.dart';
import 'package:kalinka/widgets/search/artist_page_header.dart';
import 'package:kalinka/widgets/search/catalog_page_view.dart';
import 'package:kalinka/widgets/search/page_favorite_button.dart';
import 'package:kalinka/widgets/search/search_session_view.dart';
import 'package:kalinka/widgets/search/track_group_actions.dart';
import 'package:kalinka/widgets/search_cards/artwork_grid_card.dart';
import 'package:kalinka/widgets/search_cards/cover_favorite_button.dart';
import 'package:kalinka/widgets/search_cards/row_favorite_button.dart';
import 'package:kalinka/widgets/search_cards/row_play_button.dart';
import 'package:kalinka/widgets/server_chip.dart';

import 'support/favorites_server.dart';
import 'support/home_shell.dart';

/// Lists forty tracks under an album or a playlist, and forty albums under
/// anything else, all of the source the page is of.
class _Api extends HomeApi with FavoritesServer {
  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    final source = sourceOfId(id)!;
    final tracks = id.contains(':album:') || id.contains(':playlist:');
    return BrowseItemsList(offset, limit, 40, [
      for (var i = offset; i < 40 && i < offset + limit; i++)
        if (tracks)
          BrowseItem(
            id: 'kalinka:$source:track:$i',
            name: 'Song $i',
            canBrowse: false,
            canAdd: true,
            track: Track(
              id: 'kalinka:$source:track:$i',
              title: 'Song $i',
              duration: 185 + i,
              trackNumber: i + 1,
              performer: Artist(id: 'artist', name: 'Night traveller'),
              album: Album(id: 'album', title: 'Midnight journeys'),
            ),
          )
        else
          BrowseItem(
            id: 'kalinka:$source:album:$i',
            name: 'Album $i',
            canBrowse: true,
            canAdd: true,
            album: Album(
              id: '$i',
              title: 'Album $i',
              year: 1990 + i,
              artist: Artist(id: 'artist', name: 'Night traveller'),
            ),
          ),
    ]);
  }

  @override
  Future<BrowseItem> getMetadata(String id) async => BrowseItem(
    id: id,
    name: 'Night traveller',
    canBrowse: true,
    canAdd: false,
  );

  @override
  Future<FilterValueList> getFilterValues(
    String catalogId,
    String field, {
    int offset = 0,
    int limit = 50,
    String query = '',
  }) async => const FilterValueList(offset: 0, limit: 50, total: 0, items: []);
}

CatalogPage _album(String source) => CatalogPage.category(
  id: 'kalinka:$source:album:midnight',
  title: 'Midnight journeys',
  description: 'Night traveller',
  provider: source,
);

CatalogPage _artist(String source) => CatalogPage.category(
  id: 'kalinka:$source:artist:traveller',
  title: 'Night traveller',
  provider: source,
);

CatalogPage _playlist(String source) => CatalogPage.category(
  id: 'kalinka:$source:playlist:evening',
  title: 'Evening mix',
  provider: source,
  canAdd: true,
);

CatalogPage _albums(String source) => CatalogPage.category(
  id: 'kalinka:$source:catalog:albums',
  title: 'New albums',
  provider: source,
  preview: Preview(
    type: PreviewType.imageText,
    contentType: PreviewContentType.album,
  ),
);

const _wide = Size(1200, 800);
const _phone = Size(375, 812);

final _heart = find.byType(PageFavoriteButton).hitTestable();

/// The page's heart saying it would add, and saying it would remove.
final _add = find.descendant(
  of: _heart,
  matching: find.byTooltip('Add to favourites'),
);
final _remove = find.descendant(
  of: _heart,
  matching: find.byTooltip('Remove from favourites'),
);

/// The colour the page's heart is drawn in.
Color? _heartColor(WidgetTester tester) => tester
    .widget<RichText>(
      find.descendant(of: _heart, matching: find.byType(RichText)),
    )
    .text
    .style!
    .color;

/// An artist's Grid/List once the bar has taken it.
final _barPresentation = find.byKey(const ValueKey('artist-bar-presentation'));

/// A control still in the page's header, not the bar's.
Finder _inPage(Finder matching) =>
    find.descendant(of: find.byType(CatalogPageView), matching: matching);

Finder get _scrollable => find
    .descendant(
      of: find.byType(CatalogPageView),
      matching: find.byType(Scrollable),
    )
    .first;

Future<ProviderContainer> _pump(
  WidgetTester tester,
  CatalogPage page, {
  _Api? api,
  Size size = _wide,
  List<ModuleInfo>? sources,
  GlobalKey? captureKey,
}) async {
  final container = await pumpHomeShell(
    tester,
    queue: SettableQueue(queueOf(0)),
    api: api ?? _Api(),
    size: size,
    sources:
        sources ??
        [
          favoritesSource('qobuz'),
          favoritesSource('jamendo', favorites: false),
        ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: RepaintBoundary(
          key: captureKey,
          child: const Scaffold(body: SearchSessionView()),
        ),
      ),
    ),
  );
  container.read(searchSessionProvider.notifier).openPage(page);
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUpAll(loadAppFonts);

  group('an album\'s heart', () {
    testWidgets('follows Play all and Enqueue in the wide header', (
      tester,
    ) async {
      final api = _Api()
        ..favorites.addAll(['kalinka:qobuz:track:1', 'kalinka:qobuz:track:4']);
      final key = GlobalKey();
      await _pump(tester, _album('qobuz'), api: api, captureKey: key);

      final header = find.byType(WideAlbumHeader);
      final heart = tester.getRect(_heart);
      final enqueue = tester.getRect(
        find.descendant(of: header, matching: find.byType(AddAllChip)),
      );
      final status = tester.getRect(
        find.descendant(of: header, matching: find.byType(ServerChip)),
      );
      expect(find.descendant(of: header, matching: _heart), findsOneWidget);
      expect(heart.size, const Size.square(48));
      expect(heart.left, closeTo(enqueue.right, 0.01));
      expect(heart.center.dy, closeTo(enqueue.center.dy, 0.01));
      expect(heart.right, lessThanOrEqualTo(status.left));
      expect(find.text('Play all'), findsOneWidget);
      expect(find.text('Enqueue'), findsOneWidget);
      expect(
        find.descendant(
          of: _heart,
          matching: find.byIcon(Icons.favorite_border_rounded),
        ),
        findsOneWidget,
      );
      expect(_add, findsOneWidget);

      await tester.tap(_heart);
      await tester.pump();
      expect(api.marked, ['kalinka:qobuz:album:midnight']);
      expect(_remove, findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureForReview(tester, key, 'favourites-album-wide');
    });

    testWidgets('ends the title\'s line on a phone', (tester) async {
      final api = _Api()..favorites.add('kalinka:qobuz:album:midnight');
      final key = GlobalKey();
      await _pump(
        tester,
        _album('qobuz'),
        api: api,
        size: _phone,
        captureKey: key,
      );

      final header = find.byType(AlbumPageHeader);
      final heart = tester.getRect(_heart);
      final title = tester.getRect(
        find.descendant(of: header, matching: find.byType(FittedTitle)),
      );
      final enqueue = tester.getRect(
        find.descendant(of: header, matching: find.byType(AddAllChip)),
      );
      expect(find.descendant(of: header, matching: _heart), findsOneWidget);
      expect(heart.size, const Size.square(48));
      expect(heart.right, closeTo(tester.getRect(header).right - 16, 0.01));
      expect(heart.left, greaterThanOrEqualTo(title.right + 8));
      expect(heart.center.dy, closeTo(title.center.dy, 0.01));
      expect(heart.bottom, lessThan(enqueue.top));
      expect(_remove, findsOneWidget);
      expect(
        find.descendant(
          of: _heart,
          matching: find.byIcon(Icons.favorite_rounded),
        ),
        findsOneWidget,
      );
      // Neutral marked or not: its state is in its shape.
      expect(_heartColor(tester), KalinkaColors.textPrimary);

      await tester.tap(_heart);
      await tester.pump();
      expect(api.unmarked, ['kalinka:qobuz:album:midnight']);
      expect(_add, findsOneWidget);
      expect(_heartColor(tester), KalinkaColors.textPrimary);
      expect(tester.takeException(), isNull);
      await captureForReview(tester, key, 'favourites-album-phone');
    });

    for (final size in [_wide, _phone]) {
      testWidgets('is absent where the source keeps none, at $size', (
        tester,
      ) async {
        final api = _Api();
        await _pump(tester, _album('jamendo'), api: api, size: size);

        expect(find.byType(PlayAllChip), findsOneWidget);
        expect(_heart, findsNothing);
        expect(find.byType(RowFavoriteButton), findsNothing);
        expect(api.asked, isEmpty);
      });
    }
  });

  group('an artist\'s heart', () {
    testWidgets('ends the name\'s line and joins the bar with Pin', (
      tester,
    ) async {
      final api = _Api();
      final key = GlobalKey();
      await _pump(tester, _artist('qobuz'), api: api, captureKey: key);

      final header = find.byType(ArtistPageHeader);
      final pin = find.byType(CatalogPinButton).hitTestable();
      final name = tester.getRect(
        find.descendant(of: header, matching: find.text('Night traveller')),
      );
      expect(find.descendant(of: header, matching: _heart), findsOneWidget);
      expect(find.descendant(of: header, matching: pin), findsOneWidget);
      expect(tester.getSize(_heart), const Size.square(48));
      expect(
        tester.getRect(_heart).right,
        closeTo(tester.getRect(header).right - 16, 0.01),
      );
      expect(tester.getRect(pin).left, closeTo(name.right + 8, 0.01));
      expect(
        tester.getRect(_heart).left,
        greaterThan(tester.getRect(pin).right),
      );
      expect(tester.getRect(_heart).center.dy, tester.getRect(pin).center.dy);
      await captureForReview(tester, key, 'favourites-artist-wide');

      final back = tester.getRect(find.byTooltip('Back').first).center.dy;
      final position = tester.state<ScrollableState>(_scrollable).position;
      position.jumpTo(600);
      await tester.pumpAndSettle();
      final status = tester.getRect(find.byType(ServerChip).first);
      expect(find.descendant(of: header, matching: _heart), findsNothing);
      expect(_heart, findsOneWidget);
      expect(pin, findsOneWidget);
      expect(tester.getRect(_heart).center.dy, back);
      expect(tester.getRect(_heart).left, tester.getRect(pin).right);
      expect(tester.getRect(_heart).right, lessThanOrEqualTo(status.left));
      // Grid/List joins too, left of Pin, so the heart stays at the right.
      final grid = tester.getRect(_barPresentation);
      expect(grid.right, lessThanOrEqualTo(tester.getRect(pin).left));
      expect(grid.center.dy, closeTo(back, 0.01));
      await captureForReview(tester, key, 'favourites-artist-wide-collapsed');

      await tester.tap(_heart);
      await tester.pump();
      expect(api.marked, ['kalinka:qobuz:artist:traveller']);

      position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.descendant(of: header, matching: _heart), findsOneWidget);
      expect(_heart, findsOneWidget);
      expect(_remove, findsOneWidget);
      expect(_barPresentation, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('leaves Grid/List in the header until it is under the bar', (
      tester,
    ) async {
      await _pump(tester, _artist('qobuz'));

      final header = find.byType(ArtistPageHeader);
      final position = tester.state<ScrollableState>(_scrollable).position;
      double? heartJoined;
      for (var offset = 0.0; offset <= 600; offset += 4) {
        position.jumpTo(offset);
        await tester.pump();
        await tester.pump();
        final heartInBar = find
            .descendant(of: header, matching: _heart)
            .evaluate()
            .isEmpty;
        final gridInBar = _barPresentation.evaluate().isNotEmpty;
        if (heartInBar) heartJoined ??= offset;
        if (gridInBar) {
          // Pin and the heart went first, a little further up the page.
          expect(heartJoined, isNotNull);
          expect(offset, greaterThan(heartJoined!));
          expect(
            find.descendant(
              of: header,
              matching: find.byType(PresentationToggle),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          return;
        }
      }
      fail('Grid/List never joined the bar');
    });

    testWidgets('joins the bar on its own where the artist cannot be pinned', (
      tester,
    ) async {
      await _pump(
        tester,
        _artist('library'),
        sources: [
          ModuleInfo(
            name: 'library',
            title: 'Library',
            enabled: true,
            state: ModuleState.ready,
            builtin: true,
            capabilities: const [ModuleCapability.favorites],
          ),
        ],
      );

      final header = find.byType(ArtistPageHeader);
      expect(find.byType(CatalogPinButton).hitTestable(), findsNothing);
      expect(find.descendant(of: header, matching: _heart), findsOneWidget);

      final back = tester.getRect(find.byTooltip('Back').first).center.dy;
      tester.state<ScrollableState>(_scrollable).position.jumpTo(600);
      await tester.pumpAndSettle();
      expect(_heart, findsOneWidget);
      expect(tester.getRect(_heart).center.dy, back);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is absent where the source keeps none', (tester) async {
      await _pump(tester, _artist('jamendo'));

      expect(find.byType(CatalogPinButton).hitTestable(), findsOneWidget);
      expect(_heart, findsNothing);
    });

    testWidgets('lets the bar take Pin only once a phone\'s Pin is under it', (
      tester,
    ) async {
      await _pump(tester, _artist('qobuz'), size: _phone);

      final header = find.byType(ArtistPageHeader);
      final headerPin = find.descendant(
        of: header,
        matching: find.byType(CatalogPinButton),
      );
      // Under the name, below the heart's row.
      expect(
        tester.getRect(headerPin).top,
        greaterThanOrEqualTo(tester.getRect(_heart).bottom - 1),
      );
      final barBottom =
          tester.getRect(_scrollable).top +
          tester
              .getSize(
                find
                    .descendant(
                      of: find.byType(PinnedHeaderSliver),
                      matching: find.byType(SizedBox),
                    )
                    .first,
              )
              .height;
      final position = tester.state<ScrollableState>(_scrollable).position;
      for (var offset = 0.0; offset <= 400; offset += 4) {
        position.jumpTo(offset);
        await tester.pump();
        await tester.pump();
        final pins = find.byType(CatalogPinButton).evaluate().length;
        if (pins > headerPin.evaluate().length) {
          final glyphBottom =
              tester.getRect(headerPin).center.dy +
              CatalogPinButton.iconSize / 2;
          expect(glyphBottom, lessThanOrEqualTo(barBottom + 4));
          return;
        }
      }
      fail('Pin never joined the bar');
    });

    testWidgets('fits a phone beside the name', (tester) async {
      final key = GlobalKey();
      await _pump(tester, _artist('qobuz'), size: _phone, captureKey: key);

      expect(_heart, findsOneWidget);
      expect(tester.getRect(_heart).right, lessThanOrEqualTo(_phone.width));
      expect(tester.takeException(), isNull);
      await captureForReview(tester, key, 'favourites-artist-phone');
    });
  });

  group('a playlist\'s heart', () {
    for (final (size, name) in [(_wide, 'wide'), (_phone, 'phone')]) {
      testWidgets('ends the title\'s line and joins the bar, $name', (
        tester,
      ) async {
        final api = _Api()
          ..favorites.addAll([
            'kalinka:qobuz:track:1',
            'kalinka:qobuz:track:4',
          ]);
        final key = GlobalKey();
        await _pump(
          tester,
          _playlist('qobuz'),
          api: api,
          size: size,
          captureKey: key,
        );

        final title = tester.getRect(
          find.byKey(const ValueKey('catalog-expanded-title')),
        );
        expect(_inPage(_heart), findsOneWidget);
        expect(_heart, findsOneWidget);
        expect(tester.getSize(_heart), const Size.square(48));
        expect(
          tester.getRect(_heart).right,
          closeTo(
            tester.getRect(find.byType(CatalogPageView)).right - 16,
            0.01,
          ),
        );
        expect(
          tester.getRect(_heart).left,
          greaterThanOrEqualTo(title.right + 8),
        );
        expect(
          tester.getRect(_heart).center.dy,
          closeTo(title.center.dy, 0.01),
        );
        expect(find.byType(CatalogPinButton).hitTestable(), findsNothing);
        await captureForReview(tester, key, 'favourites-playlist-$name');

        final back = tester.getRect(find.byTooltip('Back').first).center.dy;
        final position = tester.state<ScrollableState>(_scrollable).position;
        position.jumpTo(300);
        await tester.pumpAndSettle();
        expect(_inPage(_heart), findsNothing);
        expect(_heart, findsOneWidget);
        expect(tester.getRect(_heart).center.dy, back);
        expect(
          tester.getRect(_heart).left,
          greaterThanOrEqualTo(
            tester
                .getRect(find.byKey(const ValueKey('catalog-collapsed-title')))
                .left,
          ),
        );
        await captureForReview(
          tester,
          key,
          'favourites-playlist-$name-collapsed',
        );

        await tester.tap(_heart);
        await tester.pump();
        expect(api.marked, ['kalinka:qobuz:playlist:evening']);

        position.jumpTo(0);
        await tester.pumpAndSettle();
        // Android's fast scroller holds the trailing edge until it rests.
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(_inPage(_heart), findsOneWidget);
        expect(_remove, findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('says why a playlist of one\'s own is refused, and empties', (
      tester,
    ) async {
      final api = _Api()
        ..failure = ServerRefusalException(
          DioException(requestOptions: RequestOptions()),
          favoriteRefused,
          'A playlist of your own cannot be a favourite.',
        );
      final container = await _pump(tester, _playlist('qobuz'), api: api);

      await tester.tap(_heart);
      await tester.pump();

      expect(api.marked, ['kalinka:qobuz:playlist:evening']);
      expect(_add, findsOneWidget);
      expect(_remove, findsNothing);
      final toast = container.read(toastProvider).single;
      expect(toast.message, 'A playlist of your own cannot be a favourite.');
      expect(toast.isError, isTrue);
      await tester.pump(const Duration(seconds: 30));
    });

    testWidgets('is absent where the source keeps none', (tester) async {
      await _pump(tester, _playlist('jamendo'));

      expect(
        find.byKey(const ValueKey('catalog-expanded-title')),
        findsOneWidget,
      );
      expect(_heart, findsNothing);
      expect(find.byType(RowFavoriteButton), findsNothing);
    });
  });

  group('a catalog', () {
    testWidgets('has no heart of its own, and one on each cover', (
      tester,
    ) async {
      final api = _Api()..favorites.add('kalinka:qobuz:album:1');
      final key = GlobalKey();
      await _pump(tester, _albums('qobuz'), api: api, captureKey: key);

      expect(find.byType(PageFavoriteButton), findsNothing);
      expect(find.byType(CatalogPinButton).hitTestable(), findsOneWidget);
      final cards = find.byType(ArtworkGridCard);
      expect(cards, findsWidgets);
      expect(
        find.descendant(
          of: cards.first,
          matching: find.byType(CoverFavoriteButton),
        ),
        findsOneWidget,
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(cards.at(1)));
      await tester.pumpAndSettle();
      expect(
        find
            .descendant(of: cards.at(1), matching: find.byType(RowPlayButton))
            .hitTestable(),
        findsOneWidget,
      );
      expect(
        find
            .descendant(of: cards.at(0), matching: find.byType(RowPlayButton))
            .hitTestable(),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await captureForReview(tester, key, 'favourites-albums-grid');
    });
  });
}
