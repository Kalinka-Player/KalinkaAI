import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/url_resolver.dart';
import 'package:kalinka/widgets/loading_shimmer.dart';
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

BrowseItem _catalog({String? image}) => BrowseItem(
  id: 'kalinka:demo:catalog:mixes',
  name: 'Mixes',
  canBrowse: true,
  canAdd: false,
  catalog: Catalog(
    id: 'mixes',
    title: 'Mixes',
    image: image == null ? null : AlbumImage(large: image),
  ),
);

Future<void> _mount(
  WidgetTester tester,
  BrowseItem item, {
  double? hint,
  _Api? api,
  ValueChanged<BrowseItem>? onOpen,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      sourceModulesProvider.overrideWith((ref) => const <ModuleInfo>[]),
      urlResolverProvider.overrideWithValue(UrlResolver('https://art.example')),
      if (api != null) kalinkaProxyProvider.overrideWithValue(api),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: BrowseNavigationScope(
          onOpen: onOpen ?? (_) {},
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300 + 2 * ArtworkGridCard.inset,
              child: ArtworkGridCard(item: item, catalogAspectRatio: hint),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('catalog placeholders use a valid parent hint', (tester) async {
    for (final (hint, ratio) in [
      (null, 3.0),
      (2.0, 2.0),
      (0.0, 3.0),
      (double.infinity, 3.0),
    ]) {
      await _mount(tester, _catalog(), hint: hint);
      final size = tester.getSize(find.byType(AspectRatio));
      expect(size.width / size.height, closeTo(ratio, 0.001));
    }
    expect(tester.takeException(), isNull);
  });

  for (final ratio in [2, 3]) {
    testWidgets('decoded category artwork keeps its $ratio:1 shape', (
      tester,
    ) async {
      final frame = (await tester.runAsync(
        () => createTestImage(width: 40 * ratio, height: 40),
      ))!;
      addTearDown(frame.dispose);
      addTearDown(() {
        imageCache.clear();
        imageCache.clearLiveImages();
      });
      final decode = Completer<ImageInfo>();
      final provider = ResizeImage(
        const NetworkImage('https://art.example/mixes.jpg'),
        width: 750,
      );
      final key = await provider.obtainKey(ImageConfiguration.empty);
      imageCache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(decode.future),
      );
      await _mount(tester, _catalog(image: '/mixes.jpg'), hint: 1);
      expect(find.byType(ShimmerPulse), findsOneWidget);
      expect(tester.getSize(find.byType(Image)), const Size(300, 300));
      decode.complete(ImageInfo(image: frame.clone()));
      await tester.pumpAndSettle();
      expect(find.byType(ShimmerPulse), findsNothing);
      final art = tester.getSize(find.byType(Image));
      expect(art.width / art.height, closeTo(ratio, 0.001));
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
      expect(tester.getTopLeft(find.text('Mixes')).dy, greaterThan(art.height));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

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
    await _mount(tester, item, hint: 3, api: api, onOpen: opened.add);
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
