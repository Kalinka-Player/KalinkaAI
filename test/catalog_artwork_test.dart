import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/url_resolver.dart';
import 'package:kalinka/widgets/catalog_art.dart';
import 'package:kalinka/widgets/home/catalog_artwork.dart';

final _drawn = find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is CatalogArtPainter,
);

void main() {
  test('preview aspect ratio survives wire decoding, copying and encoding', () {
    final preview = Preview.fromJson({'type': 'image', 'aspect_ratio': 3});
    expect(preview.aspectRatio, 3.0);
    expect(
      Preview.fromJson(preview.copyWith(itemsCount: 5).toJson()).aspectRatio,
      3.0,
    );
    expect(preview.copyWith(aspectRatio: 2), isNot(preview));
  });

  test('an image says its shape, and a bad one says none', () {
    expect(
      AlbumImage.fromJson({'large': '/a', 'aspect_ratio': 3}).aspectRatio,
      3,
    );
    for (final bad in [0, -1, double.infinity, double.nan, '3', null]) {
      expect(AlbumImage.fromJson({'aspect_ratio': bad}).aspectRatio, isNull);
    }
    final image = AlbumImage.fromJson(
      AlbumImage(large: '/a', aspectRatio: 1.375).toJson(),
    );
    expect(image.aspectRatio, 1.375);
  });

  test('a pinned page keeps its art shape', () {
    final page = CatalogPage.fromJson(
      const CatalogPage.category(
        id: 'kalinka:source:catalog:a',
        title: 'Art',
        artPath: '/a.jpg',
        artAspectRatio: 1.375,
      ).toJson(),
    );
    expect(page.artAspectRatio, 1.375);
  });

  test(
    'a title keeps its colour whatever describes it; both set the rings',
    () {
      final jazz = CatalogArtSeed.of('Jazz', null);
      final described = CatalogArtSeed.of('  JAZZ ', 'From bebop on');
      expect(described.key, jazz.key);
      expect(described.geometry, isNot(jazz.geometry));
      expect(CatalogArtSeed.of('jazz', ''), jazz);
      expect(CatalogArtSeed.keys, contains(jazz.key));
    },
  );

  test('the seed hash is FNV-1a, the same on every platform', () {
    expect(fnv1a(''), 0x811c9dc5);
    expect(fnv1a('a'), 0xe40c292c);
    expect(fnv1a('foobar'), 0xbf9cf968);
  });

  testWidgets('a row leads with the catalog\'s thumbnail, square', (
    tester,
  ) async {
    BrowseItem catalog(AlbumImage? image) => BrowseItem(
      id: 'kalinka:demo:catalog:c',
      name: 'Jazz',
      canBrowse: true,
      canAdd: false,
      catalog: Catalog(id: 'c', title: 'Jazz', image: image),
    );
    Future<void> thumb(BrowseItem item) => tester.pumpWidget(
      ProviderScope(
        overrides: [
          urlResolverProvider.overrideWithValue(
            UrlResolver('https://art.example'),
          ),
        ],
        child: MaterialApp(
          home: Center(child: CatalogThumb(item: item, size: 60)),
        ),
      ),
    );

    await thumb(
      catalog(
        AlbumImage(large: '/card.jpg', thumbnail: '/thumb.jpg', aspectRatio: 3),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    final provider = (image.image as ResizeImage).imageProvider as NetworkImage;
    expect(provider.url, 'https://art.example/thumb.jpg');
    expect(image.fit, BoxFit.cover);
    expect(tester.getSize(find.byType(Image)), const Size(60, 60));

    await thumb(catalog(null));
    final drawn = tester.widget<CustomPaint>(_drawn);
    expect((drawn.painter! as CatalogArtPainter).captioned, isFalse);
    expect(tester.getSize(_drawn), const Size(60, 60));
    expect(tester.takeException(), isNull);
  });

  Future<void> mount(
    WidgetTester tester, {
    String? path,
    double? ratio,
    double width = 400,
    String? description,
  }) => tester.pumpWidget(
    ProviderScope(
      overrides: [
        urlResolverProvider.overrideWithValue(
          UrlResolver('https://art.example'),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: CatalogArtwork(
                page: CatalogPage.category(
                  id: 'kalinka:source:catalog:a',
                  title: 'Art',
                  artPath: path,
                  artAspectRatio: ratio,
                  // Describes the catalog's children, never its own card.
                  preview: Preview(type: PreviewType.imageText, aspectRatio: 1),
                ),
                description: description,
                onOpen: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Rect card(WidgetTester tester) =>
      tester.getRect(find.bySemanticsLabel('Open Art'));

  testWidgets('a catalog without art is a drawn 3:1 card under its caption', (
    tester,
  ) async {
    await mount(tester);
    expect(card(tester).width / card(tester).height, closeTo(3, 0.001));
    expect(_drawn, findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(
      tester.getCenter(find.text('Art')).dy,
      closeTo(card(tester).center.dy, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('caption scales with the card and stays vertically centered', (
    tester,
  ) async {
    const description = 'Picked for you';
    Future<(Size, Size)> captionAt(double width) async {
      await mount(tester, width: width, description: description);
      final titleRect = tester.getRect(find.text('Art'));
      final descriptionRect = tester.getRect(find.text(description));
      final cardRect = card(tester);
      final captionRect = titleRect.expandToInclude(descriptionRect);
      expect(captionRect.center.dy, closeTo(cardRect.center.dy, 0.01));
      expect(cardRect.contains(captionRect.topLeft), isTrue);
      expect(cardRect.contains(captionRect.bottomRight), isTrue);
      expect(tester.takeException(), isNull);
      return (titleRect.size, descriptionRect.size);
    }

    final (smallTitle, smallDescription) = await captionAt(400);
    final (largeTitle, largeDescription) = await captionAt(800);
    expect(largeTitle.height, closeTo(smallTitle.height * 2, 1));
    expect(largeDescription.height, closeTo(smallDescription.height * 2, 1));
  });

  testWidgets('a wide panel stops the card at about 320dp tall', (
    tester,
  ) async {
    tester.view.physicalSize =
        const Size(1600, 1200) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await mount(tester, width: 1400);
    expect(card(tester).height, closeTo(320, 0.5));
  });

  for (final ratio in [null, 3.0]) {
    testWidgets('card art (ratio $ratio) covers the card it is laid out for', (
      tester,
    ) async {
      await mount(tester, path: '/card.jpg', ratio: ratio);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.cover);
      expect(tester.getRect(find.byType(Image)), card(tester));
      // Until it arrives, and when it fails, the drawn card stands in.
      await tester.pumpAndSettle();
      expect(_drawn, findsOneWidget);
      expect(card(tester).width / card(tester).height, closeTo(3, 0.001));
      expect(tester.takeException(), isNull);
    });
  }

  for (final ratio in [1.0, 1100 / 800]) {
    testWidgets('$ratio:1 art sits on the right of a drawn card', (
      tester,
    ) async {
      await mount(tester, path: '/square.jpg', ratio: ratio);
      final cardRect = card(tester);
      final art = tester.getRect(find.byType(Image));
      expect(cardRect.width / cardRect.height, closeTo(3, 0.001));
      expect(art.width / art.height, closeTo(ratio, 0.001));
      expect(art.right, lessThan(cardRect.right));
      expect(art.left, greaterThan(tester.getRect(find.text('Art')).right));
      expect(cardRect.contains(art.topLeft), isTrue);
      expect(_drawn, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
