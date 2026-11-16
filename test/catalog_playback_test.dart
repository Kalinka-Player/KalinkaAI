import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/widgets/search/search_session_view.dart';

import 'support/adaptive_home_fixtures.dart';
import 'support/home_shell.dart';

const _catalogId = 'kalinka:webradio:catalog:popular';

BrowseItem _catalog({bool individual = false}) => BrowseItem(
  id: _catalogId,
  name: 'Popular stations',
  canBrowse: true,
  canAdd: false,
  catalog: Catalog(
    id: _catalogId,
    title: 'Popular stations',
    playIndividually: individual,
    previewConfig: Preview(
      type: PreviewType.imageText,
      contentType: PreviewContentType.track,
      itemsCount: 3,
    ),
  ),
);

List<BrowseItem> get _tracks => [
  for (var i = 1; i <= 3; i++)
    BrowseItem(
      id: 'kalinka:webradio:track:$i',
      name: 'Station $i',
      canBrowse: false,
      canAdd: true,
      track: Track(
        id: 'kalinka:webradio:track:$i',
        title: 'Station $i',
        duration: 0,
      ),
    ),
];

void main() {
  test('older catalog metadata keeps contextual playback', () {
    final catalog = Catalog.fromJson({'id': _catalogId, 'title': 'Tracks'});
    expect(catalog.playIndividually, isFalse);
    expect(CatalogPage.fromItem(_catalog()).playIndividually, isFalse);
    expect(
      CatalogPage.fromJson({'id': _catalogId, 'title': 'Tracks'})
          .playIndividually,
      isFalse,
    );
  });

  test('individual playback survives model copies and saved navigation', () {
    final item = BrowseItem.fromJson(_catalog(individual: true).toJson());
    final catalog = item.catalog!.copyWith(title: 'Renamed');
    expect(Catalog.fromJson(catalog.toJson()).playIndividually, isTrue);
    final page = CatalogPage.fromJson(CatalogPage.fromItem(item).toJson())
        .retitled('Pinned stations');
    expect(page.playIndividually, isTrue);
    expect(page.live, isFalse);
  });

  for (final individual in [true, false]) {
    for (final sections in [false, true]) {
      testWidgets(
        'station activation individual=$individual sections=$sections',
        (tester) async {
          final tracks = _tracks;
          final api = AdaptiveHomeApi()..listings[_catalogId] = tracks;
          final container = await pumpHomeShell(
            tester,
            queue: SettableQueue(queueOf(2)),
            api: api,
            size: const Size(900, 800),
            screen: const Scaffold(body: SearchSessionView()),
          );
          final section = _catalog(individual: individual);
          final page = sections
              ? CatalogPage.category(
                  id: 'kalinka:webradio:catalog:root',
                  title: 'Radio',
                  sections: [section],
                )
              : CatalogPage.fromJson(CatalogPage.fromItem(section).toJson());
          container.read(searchSessionProvider.notifier).openPage(page);
          await tester.pumpAndSettle();
          expect(
            container.read(searchSessionProvider).catalogPage.playIndividually,
            sections ? false : individual,
          );
          await tester.tap(find.text('Station 2'));
          await tester.pumpAndSettle();
          expect(api.replaced, [
            individual ? [tracks[1].id] : tracks.map((t) => t.id).toList(),
          ]);
          expect(api.played, [individual ? 0 : 1]);

          // The next station replaces the previous queue as well.
          await tester.tap(find.text('Station 3'));
          await tester.pumpAndSettle();
          expect(
            api.replaced.last,
            individual ? [tracks[2].id] : tracks.map((t) => t.id).toList(),
          );
          expect(api.played.last, individual ? 0 : 2);
          expect(tester.takeException(), isNull);
          await tester.pump(const Duration(seconds: 30));
        },
      );
    }
  }

  testWidgets('keyboard activation plays just the chosen station', (
    tester,
  ) async {
    final tracks = _tracks;
    final api = AdaptiveHomeApi()..listings[_catalogId] = tracks;
    final container = await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(2)),
      api: api,
      size: const Size(900, 800),
      screen: const Scaffold(body: SearchSessionView()),
    );
    container
        .read(searchSessionProvider.notifier)
        .openBrowseItem(_catalog(individual: true));
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.text('Station 2'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(api.replaced, [
      [tracks[1].id],
    ]);
    expect(api.played, [0]);
    await tester.pump(const Duration(seconds: 30));
  });
}
