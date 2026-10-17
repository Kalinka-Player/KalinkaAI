import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/url_resolver.dart';
import 'package:kalinka/widgets/home/catalog_artwork.dart';
import 'package:kalinka/widgets/loading_shimmer.dart';

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
                  preview: Preview(
                    type: PreviewType.imageText,
                    aspectRatio: ratio,
                  ),
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

  testWidgets('artwork uses a valid hint or a 3:1 placeholder', (tester) async {
    for (final (hint, expected) in [
      (null, 3.0),
      (2.0, 2.0),
      (0.0, 3.0),
      (-1.0, 3.0),
      (double.infinity, 3.0),
    ]) {
      await mount(tester, ratio: hint);
      final size = tester.getSize(find.byType(AspectRatio));
      expect(size.width / size.height, closeTo(expected, 0.001));
      expect(
        tester.getCenter(find.text('Art')).dy,
        closeTo(tester.getCenter(find.bySemanticsLabel('Open Art')).dy, 0.01),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('caption scales with the card and stays vertically centered', (
    tester,
  ) async {
    const description = 'Picked for you';
    Future<(Size, Size)> captionAt(double width, {double ratio = 3}) async {
      await mount(tester, width: width, ratio: ratio, description: description);
      final titleRect = tester.getRect(find.text('Art'));
      final descriptionRect = tester.getRect(find.text(description));
      final cardRect = tester.getRect(find.bySemanticsLabel('Open Art'));
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

    // A square image's height cap makes its card narrow even in a wide panel.
    final (squareTitle, squareDescription) = await captionAt(800, ratio: 1);
    expect(squareTitle.height, smallTitle.height);
    expect(squareDescription.height, smallDescription.height);
  });

  for (final (width, height) in [(120, 40), (100, 50), (40, 80)]) {
    testWidgets('loaded $width × $height art keeps its native proportions', (
      tester,
    ) async {
      final frame = (await tester.runAsync(
        () => createTestImage(width: width, height: height),
      ))!;
      addTearDown(frame.dispose);
      addTearDown(() {
        imageCache.clear();
        imageCache.clearLiveImages();
      });
      const url = 'https://art.example/catalog.jpg';
      final decode = Completer<ImageInfo>();
      final provider = ResizeImage(const NetworkImage(url), width: 1024);
      final key = await provider.obtainKey(ImageConfiguration.empty);
      imageCache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(decode.future),
      );
      await mount(tester, path: '/catalog.jpg', ratio: 1);
      expect(find.byType(ShimmerPulse), findsOneWidget);
      expect(
        tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
        1,
      );
      decode.complete(ImageInfo(image: frame.clone()));
      await tester.pumpAndSettle();
      expect(find.byType(ShimmerPulse), findsNothing);
      final size = tester.getSize(find.byType(AspectRatio));
      expect(size.width / size.height, closeTo(width / height, 0.001));
      expect(size.height, lessThanOrEqualTo(320));
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
      await mount(tester);
      await tester.pumpAndSettle();
      expect(
        tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
        3,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
