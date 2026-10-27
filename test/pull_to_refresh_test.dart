import 'dart:async';

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
import 'package:kalinka/providers/toast_provider.dart';
import 'package:kalinka/widgets/browse_rows_shimmer.dart';
import 'package:kalinka/widgets/pull_to_refresh.dart';
import 'package:kalinka/widgets/search/browse_visit_scope.dart';
import 'package:kalinka/widgets/search/catalog_page_view.dart';

const _playlistId = 'kalinka:demo:playlist:p1';
const _artistId = 'kalinka:demo:artist:miles';
const _libraryId = 'kalinka:demo:catalog:library';
const _recentId = 'kalinka:demo:catalog:recent';
const _lovedId = 'kalinka:demo:catalog:loved';

BrowseItem _track(String n) => BrowseItem(
  id: 'kalinka:demo:track:$n',
  name: 'Song $n',
  canBrowse: false,
  canAdd: true,
  track: Track(id: n, title: 'Song $n', duration: 100),
);

BrowseItem _album(String n) => BrowseItem(
  id: 'kalinka:demo:album:$n',
  name: 'Album $n',
  canBrowse: true,
  canAdd: true,
  album: Album(id: n, title: 'Album $n'),
);

BrowseItem _shelf(String id, String title) => BrowseItem(
  id: id,
  name: title,
  canBrowse: true,
  canAdd: false,
  catalog: Catalog(
    id: id,
    title: title,
    previewConfig: Preview(
      type: PreviewType.imageText,
      contentType: PreviewContentType.track,
      itemsCount: 3,
    ),
  ),
);

/// Answers each id with what [listings] holds when asked, after [gate] if
/// one is set.
class _Api implements KalinkaPlayerProxy {
  final Map<String, List<BrowseItem>> listings;
  final asked = <(String, int)>[];
  Completer<void>? gate;
  bool failing = false;

  _Api(this.listings);

  int askedFor(String id) => asked.where((ask) => ask.$1 == id).length;

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    asked.add((id, offset));
    if (gate case final gate?) await gate.future;
    if (failing) throw Exception('unreachable');
    final items = listings[id] ?? const <BrowseItem>[];
    return BrowseItemsList(
      offset,
      limit,
      items.length,
      items.skip(offset).take(limit).toList(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<(_Api, ProviderContainer)> _pump(
  WidgetTester tester,
  Map<String, List<BrowseItem>> listings,
  void Function(SearchSessionNotifier session) open,
) async {
  final api = _Api(listings);
  final container = ProviderContainer(
    overrides: [
      kalinkaProxyProvider.overrideWithValue(api),
      sharedPrefsProvider.overrideWithValue(
        await SharedPreferences.getInstance(),
      ),
      sourceModulesProvider.overrideWith((ref) => const <ModuleInfo>[]),
      playerStateProvider.overrideWithValue(PlaybackState.empty),
    ],
  );
  addTearDown(container.dispose);
  open(container.read(searchSessionProvider.notifier));
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
  return (api, container);
}

void _openPlaylist(SearchSessionNotifier session) => session.openBrowseItem(
  BrowseItem(
    id: _playlistId,
    name: 'Evening',
    canBrowse: true,
    canAdd: true,
    playlist: Playlist(id: 'p1', name: 'Evening', trackCount: 3),
  ),
);

void _openLibrary(SearchSessionNotifier session) => session.openCatalog(
  id: _libraryId,
  title: 'My Library',
  sections: [_shelf(_recentId, 'Recent'), _shelf(_lovedId, 'Loved')],
);

/// Pulls the page down from its top, far enough that it reloads.
Future<void> _pull(WidgetTester tester) async {
  await tester.fling(find.byType(Scrollable).first, const Offset(0, 400), 1000);
  // The drag ends, and the indicator snaps into place and starts the reload.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a short listing pulled down loads again from its top, its '
      'rows staying up meanwhile', (tester) async {
    final listing = [_track('1'), _track('2'), _track('3')];
    final (api, _) = await _pump(tester, {_playlistId: listing}, _openPlaylist);
    expect(find.text('Song 1'), findsOneWidget);
    final asked = api.askedFor(_playlistId);

    api.gate = Completer();
    listing.add(_track('4'));
    await _pull(tester);

    expect(api.askedFor(_playlistId), asked + 1);
    expect(api.asked.last, (_playlistId, 0));
    expect(find.text('Song 1'), findsOneWidget);
    expect(find.byType(BrowseRowsShimmer), findsNothing);

    api.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Song 4'), findsOneWidget);
  });

  testWidgets('a reload that fails keeps what was shown and says so', (
    tester,
  ) async {
    final (api, container) = await _pump(tester, {
      _playlistId: [_track('1'), _track('2')],
    }, _openPlaylist);

    api.failing = true;
    await _pull(tester);
    await tester.pumpAndSettle();

    expect(find.text('Song 1'), findsOneWidget);
    expect(
      container.read(toastProvider).map((toast) => toast.message),
      contains('Could not reload'),
    );
    // The toast's own timer.
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a catalog of shelves pulled down asks each shelf again', (
    tester,
  ) async {
    final recent = [_track('1')];
    final (api, _) = await _pump(tester, {
      _recentId: recent,
      _lovedId: [_track('2')],
    }, _openLibrary);
    expect(find.text('Song 1'), findsOneWidget);
    final asked = (api.askedFor(_recentId), api.askedFor(_lovedId));

    recent.insert(0, _track('5'));
    await _pull(tester);
    await tester.pumpAndSettle();

    expect(
      (api.askedFor(_recentId), api.askedFor(_lovedId)),
      (asked.$1 + 1, asked.$2 + 1),
    );
    expect(find.text('Song 5'), findsOneWidget);
  });

  testWidgets('shelves that were all empty show once a pull finds something', (
    tester,
  ) async {
    final loved = <BrowseItem>[];
    final (_, _) = await _pump(tester, {_lovedId: loved}, _openLibrary);
    expect(find.text('Nothing here yet'), findsOneWidget);

    loved.add(_track('7'));
    await _pull(tester);
    await tester.pumpAndSettle();

    expect(find.text('Nothing here yet'), findsNothing);
    expect(find.text('Song 7'), findsOneWidget);
  });

  testWidgets('an artist pulled down asks again what they hold, keeping the '
      'page up meanwhile', (tester) async {
    final listing = [_album('1'), _album('2')];
    final (api, _) = await _pump(
      tester,
      {_artistId: listing},
      (session) => session.openBrowseItem(
        BrowseItem(
          id: _artistId,
          name: 'Miles Davis',
          canBrowse: true,
          canAdd: false,
          artist: Artist(id: 'miles', name: 'Miles Davis', albumCount: 2),
        ),
      ),
    );
    expect(find.text('Album 1'), findsOneWidget);
    final asked = api.askedFor(_artistId);

    api.gate = Completer();
    listing.add(_album('3'));
    await _pull(tester);

    // The list's first chunk, and what the artist holds.
    expect(api.askedFor(_artistId), asked + 2);
    expect(find.byType(LoadingSpinner), findsNothing);
    expect(find.text('Album 1'), findsOneWidget);

    api.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Album 3'), findsOneWidget);
  });

  testWidgets('an overscroll taken for a pull goes no further than the list', (
    tester,
  ) async {
    var overscrolls = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: NotificationListener<OverscrollNotification>(
            onNotification: (_) {
              overscrolls++;
              return false;
            },
            child: PullToRefresh(
              onRefresh: () async {},
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  for (var i = 0; i < 40; i++)
                    SizedBox(height: 50, child: Text('Row $i')),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.text('Row 1'), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(overscrolls, 0);

    // At the far end, the list's overscroll is anyone's.
    await tester.fling(find.text('Row 1'), const Offset(0, -4000), 4000);
    await tester.pumpAndSettle();
    await tester.drag(find.text('Row 39'), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(overscrolls, greaterThan(0));
  });
}
