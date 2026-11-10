import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/url_resolver.dart';
import 'package:kalinka/widgets/catalog_art.dart';
import 'package:kalinka/widgets/fitted_art.dart';
import 'package:kalinka/widgets/search_cards/artwork_grid.dart';
import 'package:kalinka/widgets/search_cards/artwork_grid_card.dart';
import 'package:kalinka/widgets/search_cards/browse_navigation_scope.dart';
import 'package:kalinka/widgets/search_cards/row_play_button.dart';

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
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      sourceModulesProvider.overrideWith((ref) => const <ModuleInfo>[]),
      urlResolverProvider.overrideWithValue(UrlResolver('https://art.example')),
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
        (tester.widget<CustomPaint>(_drawn).painter! as CatalogArtPainter)
            .questionMark,
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
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
