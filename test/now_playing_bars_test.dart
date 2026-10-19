import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/selection_state_provider.dart';
import 'package:kalinka/widgets/now_playing_bars.dart';
import 'package:kalinka/widgets/search_cards/browse_item_rows.dart';
import 'package:kalinka/widgets/search_cards/search_track_row.dart';

Track _track(String id) =>
    Track(id: 'kalinka:x:track:$id', title: 'Song $id', duration: 100);

BrowseItem _item(String id) => BrowseItem(
  id: 'kalinka:x:track:$id',
  name: 'Song $id',
  canBrowse: false,
  canAdd: true,
  track: _track(id),
);

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<ProviderContainer> pump(
    WidgetTester tester,
    PlaybackState player, {
    bool reduceMotion = false,
  }) async {
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        playerStateProvider.overrideWithValue(player),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: Scaffold(
              body: BrowseItemRows(items: [_item('a'), _item('b')]),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  /// Which frame of the loop the bars are showing.
  int frame(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(NowPlayingBars),
        matching: find.byType(CustomPaint),
      ),
    );
    return (paint.painter as NowPlayingBarsPainter).step.value;
  }

  Finder row(String id) => find.ancestor(
    of: find.text('Song $id'),
    matching: find.byType(SearchTrackRow),
  );

  testWidgets('the current track carries the bars, beside its duration', (
    tester,
  ) async {
    await pump(
      tester,
      PlaybackState(state: PlayerStateType.playing, currentTrack: _track('a')),
    );

    expect(find.byType(NowPlayingBars), findsOneWidget);
    expect(
      find.descendant(of: row('a'), matching: find.byType(NowPlayingBars)),
      findsOneWidget,
    );
    final bars = tester.getRect(find.byType(NowPlayingBars));
    final duration = tester.getRect(
      find.descendant(of: row('a'), matching: find.text('1:40')),
    );
    expect(bars.right, lessThan(duration.left));
    expect(bars.center.dy, closeTo(duration.center.dy, 2));

    // Playing, they move: stepped at ten frames a second.
    final before = frame(tester);
    await tester.pump(const Duration(milliseconds: 250));
    expect(frame(tester), before + 2);
  });

  testWidgets('paused, the bars stand still', (tester) async {
    await pump(
      tester,
      PlaybackState(state: PlayerStateType.paused, currentTrack: _track('a')),
    );

    expect(find.byType(NowPlayingBars), findsOneWidget);
    final before = frame(tester);
    // Would time out if anything were still animating.
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(frame(tester), before);
  });

  testWidgets('with motion reduced, the bars stand while playing', (
    tester,
  ) async {
    await pump(
      tester,
      PlaybackState(state: PlayerStateType.playing, currentTrack: _track('a')),
      reduceMotion: true,
    );

    expect(find.byType(NowPlayingBars), findsOneWidget);
    final before = frame(tester);
    await tester.pumpAndSettle();
    expect(frame(tester), before);
  });

  testWidgets('nothing in the player, no bars', (tester) async {
    await pump(tester, PlaybackState.empty);
    expect(find.byType(NowPlayingBars), findsNothing);
  });

  testWidgets('a selection hides them with the rest of the now-playing dress', (
    tester,
  ) async {
    final container = await pump(
      tester,
      PlaybackState(state: PlayerStateType.playing, currentTrack: _track('a')),
    );
    container
        .read(selectionStateProvider.notifier)
        .enterSelectionMode('kalinka:x:track:b');
    await tester.pump();
    expect(find.byType(NowPlayingBars), findsNothing);
  });
}
