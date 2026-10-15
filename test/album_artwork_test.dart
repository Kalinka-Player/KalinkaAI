import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/url_resolver.dart';
import 'package:kalinka/widgets/procedural_album_art.dart';
import 'package:kalinka/widgets/search/album_page_header.dart';

void main() {
  testWidgets('resizing reuses artwork and keeps its frame during upgrades', (
    tester,
  ) async {
    const firstUrl = 'https://art.example/first.jpg';
    const secondUrl = 'https://art.example/second.jpg';
    final firstFrame = (await tester.runAsync(
      () => createTestImage(width: 20),
    ))!;
    final largerFrame = (await tester.runAsync(
      () => createTestImage(width: 40),
    ))!;
    addTearDown(firstFrame.dispose);
    addTearDown(largerFrame.dispose);
    addTearDown(() {
      imageCache.clear();
      imageCache.clearLiveImages();
    });

    // Controlled decode completions let us inspect every frame while a
    // replacement is pending, without a real network or timing assumptions.
    final decodes = <(String, int), Completer<ImageInfo>>{};
    for (final url in [firstUrl, secondUrl]) {
      for (final size in [512, 1024, 1536, 2048]) {
        final completion = Completer<ImageInfo>();
        decodes[(url, size)] = completion;
        final provider = ResizeImage(NetworkImage(url), width: size);
        final key = await provider.obtainKey(ImageConfiguration.empty);
        imageCache.putIfAbsent(
          key,
          () => OneFrameImageStreamCompleter(completion.future),
        );
      }
    }

    final container = ProviderContainer(
      overrides: [
        urlResolverProvider.overrideWithValue(
          UrlResolver('https://art.example'),
        ),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> resize(
      double width, {
      String? url = firstUrl,
      double density = 1,
    }) => tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: MediaQueryData(devicePixelRatio: density),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                height: 450,
                child: AlbumArtwork(
                  page: CatalogPage.category(
                    id: 'kalinka:demo:album:$url',
                    title: 'Album',
                    artPath: url,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    ImageProvider provider() => tester.widget<Image>(find.byType(Image)).image;
    RawImage frame() => tester.widget<RawImage>(find.byType(RawImage));

    await resize(375);
    expect(frame().image, isNull);
    decodes[(firstUrl, 512)]!.complete(ImageInfo(image: firstFrame.clone()));
    await tester.pumpAndSettle();
    final originalProvider = provider();
    expect(frame().image!.isCloneOf(firstFrame), isTrue);

    for (final width in [376.0, 400.0, 480.0, 510.0, 450.0, 375.0]) {
      await resize(width);
      expect(provider(), originalProvider);
      expect(frame().image!.isCloneOf(firstFrame), isTrue);
    }

    // Crossing a decode boundary must not clear the already painted image.
    await resize(700);
    expect(provider(), isNot(originalProvider));
    expect(frame().image!.isCloneOf(firstFrame), isTrue);
    decodes[(firstUrl, 1024)]!.complete(ImageInfo(image: largerFrame.clone()));
    await tester.pumpAndSettle();
    final upgradedProvider = provider();
    expect(frame().image!.isCloneOf(largerFrame), isTrue);

    for (final width in [375.0, 700.0, 1020.0, 400.0]) {
      await resize(width);
      expect(provider(), upgradedProvider);
      expect(frame().image!.isCloneOf(largerFrame), isTrue);
    }

    // Moving to a denser display can upgrade too, with no empty frame.
    await resize(700, density: 2);
    expect(provider(), isNot(upgradedProvider));
    expect(frame().image!.isCloneOf(largerFrame), isTrue);

    // Retention applies only to the same cover, not when opening another album.
    await resize(375, url: secondUrl);
    expect(frame().image, isNull);
    decodes[(secondUrl, 512)]!.complete(ImageInfo(image: firstFrame.clone()));
    await tester.pumpAndSettle();
    expect(frame().image, isNotNull);

    await resize(375, url: null);
    expect(find.byType(ProceduralAlbumArt), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
