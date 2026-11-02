import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/widgets/browse_metadata_link.dart';
import 'package:kalinka/widgets/mini_player.dart';
import 'package:kalinka/widgets/now_playing_content.dart';
import 'package:kalinka/widgets/search/album_page_header.dart';
import 'package:kalinka/widgets/search/artist_page_header.dart';

import 'support/home_shell.dart';

const _artistId = 'kalinka:localfiles:artist:performer';
const _albumId = 'kalinka:localfiles:album:record';

class _Api extends HomeApi {
  final browsed = <String>[];

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    browsed.add(id);
    return BrowseItemsList(offset, limit, 0, const []);
  }
}

PlayQueueState _queue({
  String artistId = _artistId,
  String albumId = _albumId,
}) {
  final artist = Artist(id: artistId, name: 'Current artist');
  return queueOf(1).copyWith(
    seq: 0,
    trackList: [
      Track(
        id: 'kalinka:localfiles:track:song',
        title: 'Current song',
        duration: 200,
        performer: artist,
        album: Album(
          id: albumId,
          title: 'Current album',
          year: 2026,
          artist: artist,
        ),
      ),
    ],
  );
}

Finder _playerText(String text) => find.descendant(
  of: find.byType(NowPlayingContent),
  matching: find.text(text),
);

void main() {
  for (final size in [const Size(375, 812), const Size(1440, 900)]) {
    for (final album in [false, true]) {
      testWidgets('opens current ${album ? 'album' : 'artist'} at $size', (
        tester,
      ) async {
        final api = _Api();
        final queue = _queue();
        final container = await pumpHomeShell(
          tester,
          queue: SettableQueue(queue),
          api: api,
          size: size,
          themed: true,
        );
        final phone = size.width < 1000;
        if (phone) {
          await tester.tap(find.byType(MiniPlayer));
          await tester.pumpAndSettle();
        }
        final name = album ? 'Current album' : 'Current artist';
        final link = _playerText(album ? '$name · 2026' : name);
        final semantics = tester.ensureSemantics();
        expect(
          tester.getSemantics(
            find.ancestor(of: link, matching: find.byType(BrowseMetadataLink)),
          ),
          matchesSemantics(
            label: 'Open $name',
            isLink: true,
            hasTapAction: true,
          ),
        );
        semantics.dispose();
        await tester.tap(link);
        await tester.pumpAndSettle();

        final page = container.read(searchSessionProvider).catalogPage;
        expect(page.id, album ? _albumId : _artistId);
        expect(page.title, name);
        expect(api.browsed, contains(page.id));
        expect(
          find.byType(NowPlayingContent),
          phone ? findsNothing : findsOneWidget,
        );
        expect(
          find.byType(album ? AlbumPageHeader : ArtistPageHeader),
          phone || !album ? findsOneWidget : findsNothing,
        );
        if (album && !phone) {
          expect(find.byType(AlbumIdentityColumn), findsOneWidget);
        }
        expect(container.read(playQueueStateStoreProvider), same(queue));

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          container.read(searchSessionProvider).catalogPage.isRoot,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('album artist link shares keyboard navigation with the player', (
    tester,
  ) async {
    final container = await pumpHomeShell(
      tester,
      queue: SettableQueue(_queue()),
      api: _Api(),
      size: const Size(375, 812),
    );
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    final album = _playerText('Current album · 2026');
    Focus.of(tester.element(album)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(container.read(searchSessionProvider).catalogPage.id, _albumId);

    await tester.tap(
      find.descendant(
        of: find.byType(AlbumPageHeader),
        matching: find.text('Current artist'),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(searchSessionProvider).catalogPage.id, _artistId);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(container.read(searchSessionProvider).catalogPage.id, _albumId);
    expect(tester.takeException(), isNull);
  });

  for (final id in ['', 'bare-id', 'kalinka:localfiles:track:wrong-type']) {
    testWidgets('metadata without a browsable id stays plain: "$id"', (
      tester,
    ) async {
      final container = await pumpHomeShell(
        tester,
        queue: SettableQueue(_queue(artistId: id, albumId: id)),
        api: _Api(),
      );
      await tester.tap(find.byType(MiniPlayer));
      await tester.pumpAndSettle();
      for (final name in ['Current artist', 'Current album · 2026']) {
        final label = _playerText(name);
        expect(tester.widget<Text>(label).style?.decoration, isNull);
        await tester.tap(label);
        await tester.pumpAndSettle();
      }
      expect(container.read(searchSessionProvider).catalogPage.isRoot, isTrue);
      expect(find.byType(NowPlayingContent), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
