import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/url_resolver.dart';
import 'package:kalinka/providers/wire_event_provider.dart'
    show playQueueEventBusProvider;
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/catalog_art.dart';
import 'package:kalinka/widgets/fitted_art.dart';
import 'package:kalinka/widgets/search_cards/artwork_grid.dart';
import 'package:kalinka/widgets/search_cards/artwork_grid_card.dart';
import 'package:kalinka/widgets/search_cards/browse_navigation_scope.dart';
import 'package:kalinka/widgets/search_cards/cover_favorite_button.dart';
import 'package:kalinka/widgets/search_cards/row_play_button.dart';

import 'support/favorites_server.dart';
import 'support/focus.dart';
import 'support/home_shell.dart' show SettableConnection;

class _Api implements KalinkaPlayerProxy {
  final replaced = <List<String>>[];
  final played = <int?>[];
  @override
  Future<StatusMessage> replace(List<String> ids) async {
    replaced.add(ids);
    return StatusMessage(count: 1);
  }

  @override
  Future<StatusMessage> play([int? index]) async {
    played.add(index);
    return StatusMessage();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FavoritesApi extends _Api with FavoritesServer {}

/// One source that keeps favourites, and one that keeps none.
final _sources = [
  favoritesSource('qobuz'),
  favoritesSource('jamendo', favorites: false),
];

BrowseItem _albumOf(String source) => BrowseItem(
  id: 'kalinka:$source:album:1',
  canBrowse: true,
  canAdd: true,
  album: Album(id: '1', title: 'Album'),
);

final _coverHeart = find.byType(CoverFavoriteButton);

BrowseItem _catalog({String? image, double? ratio, String? description}) =>
    BrowseItem(
      id: 'kalinka:demo:catalog:mixes',
      name: 'Mixes',
      canBrowse: true,
      canAdd: false,
      catalog: Catalog(
        id: 'mixes',
        title: 'Mixes',
        description: description,
        image: image == null
            ? null
            : AlbumImage(large: image, aspectRatio: ratio),
      ),
    );

final _drawn = find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is CatalogArtPainter,
);

Future<void> _mount(
  WidgetTester tester,
  BrowseItem item, {
  _Api? api,
  ValueChanged<BrowseItem>? onOpen,
  double shape = 1,
  double width = 300,
  double? dpr,
  List<ModuleInfo> sources = const [],
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      sourceModulesProvider.overrideWith((ref) => sources),
      urlResolverProvider.overrideWithValue(UrlResolver('https://art.example')),
      connectionStateProvider.overrideWith(SettableConnection.new),
      playQueueEventBusProvider.overrideWith((ref) => const Stream.empty()),
      if (api != null) kalinkaProxyProvider.overrideWithValue(api),
    ],
    child: MaterialApp(
      builder: (context, child) => dpr == null
          ? child!
          : MediaQuery(
              data: MediaQuery.of(context).copyWith(devicePixelRatio: dpr),
              child: child!,
            ),
      home: Scaffold(
        body: BrowseNavigationScope(
          onOpen: onOpen ?? (_) {},
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width + 2 * ArtworkGridCard.inset,
              child: ArtworkGridCard(item: item, shape: shape),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('a reused grid updates metadata for unchanged item IDs', (
    tester,
  ) async {
    Future<void> show(String title) => tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourceModulesProvider.overrideWith((ref) => const <ModuleInfo>[]),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverArtworkGrid(
                  items: [
                    BrowseItem(
                      id: 'kalinka:demo:album:same',
                      canBrowse: true,
                      canAdd: false,
                      album: Album(id: 'same', title: title),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await show('Before metadata refresh');
    await tester.pump();
    expect(find.text('Before metadata refresh'), findsOneWidget);
    await show('After metadata refresh');
    await tester.pump();
    expect(find.text('Before metadata refresh'), findsNothing);
    expect(find.text('After metadata refresh'), findsOneWidget);
  });

  final albumWithArt = BrowseItem(
    id: 'kalinka:demo:album:art',
    canBrowse: true,
    canAdd: false,
    album: Album(
      id: 'art',
      title: 'Artwork',
      image: AlbumImage(large: '/cover.jpg'),
    ),
  );

  testWidgets('cover decoding follows screen density without undersizing', (
    tester,
  ) async {
    for (final dpr in [1.0, 2.0, 3.0]) {
      await _mount(tester, albumWithArt, width: 200, dpr: dpr);
      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image as ResizeImage;
      // Enough pixels for this display, with less than one size bucket spare.
      expect(provider.width, greaterThanOrEqualTo(200 * dpr));
      expect(provider.width, lessThan(200 * dpr + 64));
      expect(provider.height, isNull);
      expect(image.fit, BoxFit.cover);
    }
  });

  testWidgets('small resizes reuse the same decoded cover cache entry', (
    tester,
  ) async {
    await _mount(tester, albumWithArt, width: 200, dpr: 1);
    final before = await tester
        .widget<Image>(find.byType(Image))
        .image
        .obtainKey(const ImageConfiguration());
    await _mount(tester, albumWithArt, width: 201, dpr: 1);
    final after = await tester
        .widget<Image>(find.byType(Image))
        .image
        .obtainKey(const ImageConfiguration());
    expect(after, before);
  });

  testWidgets('a contained square cover decodes by its displayed height', (
    tester,
  ) async {
    await _mount(tester, albumWithArt, width: 300, shape: 2, dpr: 1);
    final image = tester.widget<Image>(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.fit == BoxFit.contain,
      ),
    );
    final provider = image.image as ResizeImage;
    expect(provider.width, isNull);
    expect(provider.height, greaterThanOrEqualTo(150));
    expect(provider.height, lessThan(150 + 64));
    expect(find.byType(SoftImageFill), findsOneWidget);
  });

  testWidgets('a catalog is a 3:1 card with its name on it', (tester) async {
    await _mount(tester, _catalog(description: 'Made for you'));
    final card = tester.getRect(find.byType(CatalogCard));
    expect(card.size, const Size(300, 100));
    expect(_drawn, findsOneWidget);
    expect(card.contains(tester.getCenter(find.text('Mixes'))), isTrue);
    expect(card.contains(tester.getCenter(find.text('Made for you'))), isTrue);
    expect(find.bySemanticsLabel('Mixes, Made for you'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a catalog card keeps its shape when any art fails', (
    tester,
  ) async {
    for (final ratio in [null, 3.0, 1.0]) {
      await _mount(tester, _catalog(image: '/mixes.jpg', ratio: ratio));
      await tester.pumpAndSettle();
      final card = tester.getRect(find.byType(CatalogCard));
      expect(card.size, const Size(300, 100));
      expect(tester.getRect(_drawn), card);
      expect(
        (tester.widget<CustomPaint>(_drawn).painter! as CatalogArtPainter).icon,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a cover takes its shelf\'s shape and fits inside it', (
    tester,
  ) async {
    BrowseItem playlist(double? ratio) => BrowseItem(
      id: 'kalinka:demo:playlist:p',
      name: 'Jazz Classics',
      canBrowse: true,
      canAdd: false,
      playlist: Playlist(
        id: 'p',
        name: 'Jazz Classics',
        image: AlbumImage(large: '/cover.jpg', aspectRatio: ratio),
      ),
    );
    final cover = find.byWidgetPredicate(
      (widget) => widget is Image && widget.fit != BoxFit.cover,
    );
    for (final (ratio, shape, fills) in [
      (2.1, 2.1, true),
      (null, 2.1, false),
      (2.1, 1.0, false),
      (1.0, 1.0, true),
    ]) {
      await _mount(tester, playlist(ratio), shape: shape);
      await tester.pumpAndSettle();
      final art = tester.getRect(find.byType(AspectRatio));
      expect(art.width / art.height, closeTo(shape, 0.001));
      expect(find.byType(SoftImageFill), fills ? findsNothing : findsOneWidget);
      expect(cover, fills ? findsNothing : findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Jazz Classics')).dy,
        greaterThan(art.bottom),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('album art stays square and Play is separate from opening', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final api = _Api();
    final opened = <BrowseItem>[];
    final item = BrowseItem(
      id: 'kalinka:demo:album:1',
      canBrowse: true,
      canAdd: true,
      album: Album(id: '1', title: 'Album'),
    );
    await _mount(tester, item, api: api, onOpen: opened.add);
    await tester.pumpAndSettle();
    final art = tester.getRect(find.byType(AspectRatio).first);
    expect(art.width, art.height);
    final play = tester.getRect(find.byType(RowPlayButton));
    expect(art.contains(play.center), isTrue);
    expect(find.bySemanticsLabel('Play Album'), findsOneWidget);
    expect(find.bySemanticsLabel('Album'), findsOneWidget);
    await tester.tap(find.byType(RowPlayButton));
    await tester.pumpAndSettle();
    expect(api.replaced, [
      [item.id],
    ]);
    expect(api.played, [0]);
    expect(opened, isEmpty);
    await tester.tap(find.text('Album'));
    await tester.pumpAndSettle();
    expect(opened, [item]);
    expect(api.played, [0]);

    final target = traversableFocusNodesIn(find.byType(ArtworkGridCard)).single;
    target.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(opened, [item]);
    expect(api.replaced, [
      [item.id],
      [item.id],
    ]);
    expect(api.played, [0, 0]);
    expect(target.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, [item, item]);
    expect(api.played, [0, 0]);

    await tester.longPress(find.text('Album'));
    await tester.pumpAndSettle();
    expect(find.byType(RowPlayButton), findsNothing);
    target.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.byType(RowPlayButton), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.byType(RowPlayButton), findsOneWidget);
    expect(opened, [item, item]);
    expect(api.played, [0, 0]);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  group('a cover\'s heart', () {
    testWidgets('stands opposite Play, in its circle', (tester) async {
      final api = _FavoritesApi();
      await _mount(tester, _albumOf('qobuz'), api: api, sources: _sources);
      await tester.pumpAndSettle();

      final art = tester.getRect(find.byType(AspectRatio).first);
      final heart = tester.getRect(_coverHeart);
      final play = tester.getRect(find.byType(RowPlayButton));
      expect(api.asked, ['qobuz']);
      expect(heart.size, play.size);
      expect(heart.top, play.top);
      expect(heart.left - art.left, art.right - play.right);
      expect(art.contains(heart.topLeft), isTrue);

      BoxDecoration circleOf(Finder button) =>
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: button,
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      final circle = circleOf(_coverHeart);
      expect(circle.shape, BoxShape.circle);
      expect(circle.color, KalinkaColors.surfaceElevated);
      expect(circle.border, Border.all(color: KalinkaColors.borderDefault));
      expect(circle, circleOf(find.byType(RowPlayButton)));
      expect(
        tester.getSize(
          find.descendant(
            of: _coverHeart,
            matching: find.byType(AnimatedContainer),
          ),
        ),
        const Size.square(32),
      );
      final icon = tester.widget<Icon>(
        find.descendant(of: _coverHeart, matching: find.byType(Icon)),
      );
      expect(icon.icon, Icons.favorite_border_rounded);
      expect(icon.color, KalinkaColors.textPrimary);
      expect(find.byTooltip('Add to favourites'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('comes and goes with Play', (tester) async {
      await _mount(
        tester,
        _albumOf('qobuz'),
        api: _FavoritesApi(),
        sources: _sources,
      );
      await tester.pumpAndSettle();
      final play = find.byType(RowPlayButton);
      // On a touch screen, both always.
      expect(_coverHeart.hitTestable(), findsOneWidget);
      expect(play.hitTestable(), findsOneWidget);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(700, 500));
      addTearDown(mouse.removePointer);
      await tester.pumpAndSettle();
      expect(_coverHeart.hitTestable(), findsNothing);
      expect(play.hitTestable(), findsNothing);

      await mouse.moveTo(tester.getCenter(find.text('Album')));
      await tester.pumpAndSettle();
      expect(_coverHeart.hitTestable(), findsOneWidget);
      expect(play.hitTestable(), findsOneWidget);

      await mouse.moveTo(const Offset(700, 500));
      await tester.pumpAndSettle();
      expect(_coverHeart.hitTestable(), findsNothing);
      expect(play.hitTestable(), findsNothing);
    });

    testWidgets('marks without opening or playing', (tester) async {
      final api = _FavoritesApi();
      final opened = <BrowseItem>[];
      final item = _albumOf('qobuz');
      await _mount(
        tester,
        item,
        api: api,
        onOpen: opened.add,
        sources: _sources,
      );
      await tester.pumpAndSettle();

      await tester.tap(_coverHeart);
      await tester.pump();

      expect(api.marked, [item.id]);
      expect(opened, isEmpty);
      expect(api.replaced, isEmpty);
      final icon = tester.widget<Icon>(
        find.descendant(of: _coverHeart, matching: find.byType(Icon)),
      );
      expect(icon.icon, Icons.favorite_rounded);
      expect(icon.color, KalinkaColors.textPrimary);
      expect(find.byTooltip('Remove from favourites'), findsOneWidget);

      await tester.tap(_coverHeart);
      await tester.pump();
      expect(api.unmarked, [item.id]);
      expect(opened, isEmpty);
    });

    testWidgets('leaves the card one keyboard stop, and goes in selection', (
      tester,
    ) async {
      await _mount(
        tester,
        _albumOf('qobuz'),
        api: _FavoritesApi(),
        sources: _sources,
      );
      await tester.pumpAndSettle();

      expect(
        traversableFocusNodesIn(find.byType(ArtworkGridCard)),
        hasLength(1),
      );

      await tester.longPress(find.text('Album'));
      await tester.pumpAndSettle();
      expect(_coverHeart, findsNothing);
      expect(find.byType(RowPlayButton), findsNothing);
    });

    testWidgets('is a playlist\'s too', (tester) async {
      final api = _FavoritesApi()..favorites.add('kalinka:qobuz:playlist:p');
      await _mount(
        tester,
        BrowseItem(
          id: 'kalinka:qobuz:playlist:p',
          name: 'Jazz Classics',
          canBrowse: true,
          canAdd: true,
          playlist: Playlist(id: 'p', name: 'Jazz Classics'),
        ),
        api: api,
        sources: _sources,
      );
      await tester.pumpAndSettle();

      expect(_coverHeart, findsOneWidget);
      expect(find.byTooltip('Remove from favourites'), findsOneWidget);
    });

    testWidgets('is no artist\'s, no catalog\'s, and none where the source '
        'keeps none', (tester) async {
      final api = _FavoritesApi();
      for (final item in [
        BrowseItem(
          id: 'kalinka:qobuz:artist:1',
          name: 'Someone',
          canBrowse: true,
          canAdd: false,
          artist: Artist(id: '1', name: 'Someone'),
        ),
        BrowseItem(
          id: 'kalinka:qobuz:catalog:mixes',
          name: 'Mixes',
          canBrowse: true,
          canAdd: false,
          catalog: Catalog(id: 'mixes', title: 'Mixes'),
        ),
        _albumOf('jamendo'),
      ]) {
        await _mount(tester, item, api: api, sources: _sources);
        await tester.pumpAndSettle();
        expect(_coverHeart, findsNothing);
      }
      expect(find.byType(RowPlayButton), findsOneWidget);
      expect(api.asked, isEmpty);
    });
  });
}
