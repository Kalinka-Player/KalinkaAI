import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/widgets/search/browse_visit_scope.dart';
import 'package:kalinka/widgets/search/catalog_page_view.dart';

const _artistId = 'kalinka:demo:artist:miles';

BrowseItem _album(int n) => BrowseItem(
  id: 'kalinka:demo:album:a$n',
  name: 'Album $n',
  canBrowse: true,
  canAdd: true,
  album: Album(id: 'a$n', title: 'Album $n'),
);

BrowseItem _track(int n) => BrowseItem(
  id: 'kalinka:demo:track:t$n',
  name: 'Song $n',
  canBrowse: false,
  canAdd: true,
  track: Track(id: 't$n', title: 'Song $n', duration: 100),
);

class _ArtistApi implements KalinkaPlayerProxy {
  final List<BrowseItem> items;

  _ArtistApi(this.items);

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async => BrowseItemsList(
    offset,
    limit,
    items.length,
    items.skip(offset).take(limit).toList(),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  List<BrowseItem> items,
) async {
  final container = ProviderContainer(
    overrides: [
      kalinkaProxyProvider.overrideWithValue(_ArtistApi(items)),
      sharedPrefsProvider.overrideWithValue(
        await SharedPreferences.getInstance(),
      ),
      sourceModulesProvider.overrideWith((ref) => const <ModuleInfo>[]),
      playerStateProvider.overrideWithValue(PlaybackState.empty),
    ],
  );
  addTearDown(container.dispose);
  container
      .read(searchSessionProvider.notifier)
      .openBrowseItem(
        BrowseItem(
          id: _artistId,
          name: 'Miles Davis',
          canBrowse: true,
          canAdd: false,
          artist: Artist(id: 'miles', name: 'Miles Davis', albumCount: 2),
        ),
      );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              final visit = ref.watch(searchSessionProvider);
              return BrowseVisitScope(
                visit: visit,
                child: CatalogPageView(
                  key: ValueKey(visit.visitId),
                  page: visit.catalogPage,
                  onBackToCatalogs: () {},
                ),
              );
            },
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

  testWidgets('releases and tracks each take a tab, releases first', (
    tester,
  ) async {
    final container = await _pump(tester, [
      _album(1),
      _album(2),
      _track(1),
      _track(2),
    ]);

    expect(find.text('Miles Davis'), findsOneWidget);
    expect(find.textContaining('2 albums'), findsOneWidget);
    expect(find.text('ALBUMS'), findsOneWidget);
    expect(find.text('Album 1'), findsOneWidget);
    expect(find.text('Song 1'), findsNothing);

    final visits = container.read(searchSessionProvider).previousVisits.length;
    await tester.tap(find.text('TRACKS'));
    await tester.pumpAndSettle();
    expect(find.text('Song 1'), findsOneWidget);
    expect(find.text('Album 1'), findsNothing);
    // A tab is not a visit.
    expect(container.read(searchSessionProvider).previousVisits.length, visits);

    // Back to the artist from a release lands on the tab it was left on.
    container.read(searchSessionProvider.notifier).openBrowseItem(_album(9));
    container.read(searchSessionProvider.notifier).goBack();
    await tester.pumpAndSettle();
    expect(
      container.read(searchSessionProvider).artistTab,
      ArtistRelation.tracks,
    );
    expect(find.text('Song 1'), findsOneWidget);
  });

  testWidgets('one relation shows directly, without an empty tab set', (
    tester,
  ) async {
    await _pump(tester, [_album(1), _album(2)]);

    expect(find.text('ALBUMS'), findsNothing);
    expect(find.text('TRACKS'), findsNothing);
    expect(find.text('Album 2'), findsOneWidget);
  });
}
