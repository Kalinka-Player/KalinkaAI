import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/selection_state_provider.dart';
import 'package:kalinka/providers/server_refusal.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/toast_provider.dart';
import 'package:kalinka/providers/wire_event_provider.dart'
    show playQueueEventBusProvider;
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/search_cards/browse_item_rows.dart';
import 'package:kalinka/widgets/search_cards/row_columns.dart';
import 'package:kalinka/widgets/search_cards/row_enqueue_button.dart';
import 'package:kalinka/widgets/search_cards/row_favorite_button.dart';
import 'package:kalinka/widgets/search_cards/search_track_row.dart';

import 'support/favorites_server.dart';
import 'support/home_shell.dart';
import 'support/queue_api.dart';

class _Api extends QueueApi with FavoritesServer {}

/// A track of [source], three minutes and five seconds long.
BrowseItem _track(String source, int index) {
  final id = 'kalinka:$source:track:$index';
  return BrowseItem(
    id: id,
    name: 'Song $index',
    canBrowse: false,
    canAdd: true,
    track: Track(
      id: id,
      title: 'Song $index',
      duration: 185,
      performer: Artist(id: 'artist', name: 'Someone'),
      album: Album(id: 'album', title: 'An album'),
    ),
  );
}

BrowseItem _album(String source, int index) => BrowseItem(
  id: 'kalinka:$source:album:$index',
  name: 'Album $index',
  canBrowse: true,
  canAdd: true,
  album: Album(
    id: '$index',
    title: 'Album $index',
    trackCount: 12,
    artist: Artist(id: 'artist', name: 'Someone'),
  ),
);

/// Wide enough for a track's Album column and its +; and a phone's.
const _wide = 700.0;
const _narrow = 343.0;

final _hearts = find.byType(RowFavoriteButton);
final _plus = find.byType(RowEnqueueButton);

/// Where a heart's own semantics are.
final _heartNode = find.descendant(
  of: _hearts,
  matching: find.byType(MergeSemantics),
);

Finder _row(BrowseItem item) => find.byWidgetPredicate(
  (widget) => widget is SearchTrackRow && widget.item.id == item.id,
);

Finder _in(BrowseItem item, Finder matching) =>
    find.descendant(of: _row(item), matching: matching);

Rect _time(WidgetTester tester, BrowseItem item) =>
    tester.getRect(_in(item, find.text('3:05')));

Icon _heartIcon(WidgetTester tester, BrowseItem item) => tester.widget<Icon>(
  find.descendant(of: _in(item, _hearts), matching: find.byType(Icon)),
);

void main() {
  late SharedPreferences prefs;

  setUpAll(loadAppFonts);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<ProviderContainer> pumpRows(
    WidgetTester tester,
    List<BrowseItem> items, {
    required double width,
    _Api? api,
    List<ModuleInfo>? sources,
    StreamController<PlayQueueEvent>? events,
  }) async {
    tester.view.physicalSize = Size(width + 32, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        kalinkaProxyProvider.overrideWithValue(api ?? _Api()),
        connectionStateProvider.overrideWith(SettableConnection.new),
        playerStateProvider.overrideWithValue(PlaybackState.empty),
        sourceModulesProvider.overrideWith(
          (ref) =>
              sources ??
              [
                favoritesSource('qobuz'),
                favoritesSource('jamendo', favorites: false),
              ],
        ),
        playQueueEventBusProvider.overrideWith(
          (ref) => events?.stream ?? const Stream.empty(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: BrowseItemRows(items: items),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  group('where a track row\'s heart stands', () {
    testWidgets('after the time and before the +, a gap apart, when wide', (
      tester,
    ) async {
      final items = [_track('qobuz', 1), _track('qobuz', 2)];
      await pumpRows(tester, items, width: _wide);

      for (final item in items) {
        final row = tester.getRect(_row(item));
        final time = _time(tester, item);
        final heart = tester.getRect(_in(item, _hearts));
        final plus = tester.getRect(_in(item, _plus));
        expect(heart.size, const Size.square(44));
        expect(heart.left - time.right, closeTo(8, 0.01));
        expect(plus.left - heart.right, closeTo(16, 0.01));
        expect(row.right - plus.right, closeTo(8, 0.01));
        expect(heart.center.dy, closeTo(plus.center.dy, 0.01));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'at the row\'s end after the time, a whole target, on a phone',
      (tester) async {
        final items = [_track('qobuz', 1), _track('qobuz', 2)];
        await pumpRows(tester, items, width: _narrow);

        expect(_plus, findsNothing);
        for (final item in items) {
          final row = tester.getRect(_row(item));
          final time = _time(tester, item);
          final heart = tester.getRect(_in(item, _hearts));
          expect(heart.size, const Size.square(48));
          expect(heart.left - time.right, closeTo(8, 0.01));
          expect(row.right - heart.right, closeTo(8, 0.01));
          expect(heart.height, lessThanOrEqualTo(row.height));
        }
        expect(tester.takeException(), isNull);
      },
    );

    for (final width in [_wide, _narrow]) {
      testWidgets('nowhere in a listing whose sources keep none, at $width', (
        tester,
      ) async {
        final api = _Api();
        final items = [_track('jamendo', 1), _track('jamendo', 2)];
        await pumpRows(tester, items, width: width, api: api);

        expect(_hearts, findsNothing);
        expect(api.asked, isEmpty);
        final row = tester.getRect(_row(items[0]));
        final time = _time(tester, items[0]);
        if (width == _wide) {
          final plus = tester.getRect(_in(items[0], _plus));
          expect(plus.left - time.right, closeTo(8, 0.01));
          expect(row.right - plus.right, closeTo(8, 0.01));
        } else {
          expect(row.right - time.right, closeTo(8, 0.01));
        }
      });

      testWidgets('in an empty slot where a row of a mixed listing cannot be '
          'marked, at $width', (tester) async {
        final marked = _track('qobuz', 1);
        final plain = _track('jamendo', 2);
        await pumpRows(tester, [marked, plain], width: width);

        expect(_in(marked, _hearts), findsOneWidget);
        expect(_in(plain, _hearts), findsNothing);
        expect(
          _time(tester, plain).right,
          closeTo(_time(tester, marked).right, 0.01),
        );
        if (width == _wide) {
          expect(
            tester.getRect(_in(plain, _plus)).left,
            tester.getRect(_in(marked, _plus)).left,
          );
        }
      });
    }

    for (final width in [_wide, _narrow]) {
      testWidgets('without making a row taller, at $width', (tester) async {
        final plain = [_track('jamendo', 1)];
        await pumpRows(tester, plain, width: width);
        final height = tester.getSize(_row(plain[0])).height;

        final marked = _track('qobuz', 1);
        final mixed = _track('jamendo', 2);
        final container = await pumpRows(tester, [marked, mixed], width: width);
        expect(tester.getSize(_row(marked)).height, height);
        expect(tester.getSize(_row(mixed)).height, height);

        container
            .read(selectionStateProvider.notifier)
            .enterSelectionMode(mixed.id);
        await tester.pump();
        expect(_hearts, findsNothing);
        expect(tester.getSize(_row(marked)).height, height);
      });
    }

    for (final source in ['qobuz', 'jamendo']) {
      testWidgets('TIME stays over the times of $source', (tester) async {
        final items = [_track(source, 1), _track(source, 2)];
        await pumpRows(tester, items, width: _wide);

        expect(find.byType(RowColumnsHeader), findsOneWidget);
        expect(
          tester.getRect(find.text('TIME')).right,
          closeTo(_time(tester, items[0]).right, 0.01),
        );
        expect(
          tester.getRect(find.text('ALBUM')).left,
          closeTo(tester.getRect(find.text('An album').first).left, 0.01),
        );
      });
    }

    testWidgets('the time keeps its size beside the heart', (tester) async {
      final plain = [_track('jamendo', 1)];
      await pumpRows(tester, plain, width: _narrow);
      final natural = _time(tester, plain[0]).size;

      final items = [_track('qobuz', 1)];
      await pumpRows(tester, items, width: _wide);
      expect(find.byType(RowColumnsHeader), findsOneWidget);
      expect(_time(tester, items[0]).size, natural);
    });

    testWidgets('albums of a source that keeps favourites align as before', (
      tester,
    ) async {
      final rects = <Rect>[];
      for (final source in ['jamendo', 'qobuz']) {
        await pumpRows(tester, [
          _album(source, 1),
          _album(source, 2),
        ], width: 900);
        expect(_hearts, findsNothing);
        rects.add(tester.getRect(find.text('DETAILS')));
      }
      expect(rects[1], rects[0]);
    });
  });

  group('a track row\'s heart', () {
    testWidgets('is bare and muted at rest', (tester) async {
      final items = [_track('qobuz', 1)];
      await pumpRows(tester, items, width: _wide);

      final icon = _heartIcon(tester, items[0]);
      expect(icon.icon, Icons.favorite_border_rounded);
      expect(icon.color, KalinkaColors.textMuted);
      expect(icon.size, 20);
      expect(
        find.descendant(
          of: _hearts,
          matching: find.byWidgetPredicate(
            (widget) => widget is DecoratedBox || widget is Container,
          ),
        ),
        findsNothing,
      );
      expect(find.byTooltip('Add to favourites'), findsOneWidget);
      expect(
        tester.getSemantics(_heartNode),
        matchesSemantics(
          label: 'Add to favourites',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
    });

    testWidgets('is filled and bright once marked, never in the accent', (
      tester,
    ) async {
      final items = [_track('qobuz', 1), _track('qobuz', 2)];
      final api = _Api()..favorites.add(items[0].id);
      await pumpRows(tester, items, width: _wide, api: api);

      expect(api.asked, ['qobuz']);
      final marked = _heartIcon(tester, items[0]);
      expect(marked.icon, Icons.favorite_rounded);
      expect(marked.color, KalinkaColors.textPrimary);
      expect(_heartIcon(tester, items[1]).color, KalinkaColors.textMuted);
      expect(find.byTooltip('Remove from favourites'), findsOneWidget);
      expect(
        tester.getSemantics(_in(items[0], _heartNode)),
        matchesSemantics(
          label: 'Remove from favourites',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
    });

    testWidgets('lifts under the pointer, with a hand', (tester) async {
      final items = [_track('qobuz', 1)];
      await pumpRows(tester, items, width: _wide);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await mouse.moveTo(tester.getCenter(_hearts));
      await tester.pump();
      expect(_heartIcon(tester, items[0]).color, KalinkaColors.textPrimary);
      expect(_heartIcon(tester, items[0]).icon, Icons.favorite_border_rounded);
      expect(
        tester.binding.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );

      await mouse.moveTo(tester.getCenter(find.text('Song 1')));
      await tester.pump();
      expect(_heartIcon(tester, items[0]).color, KalinkaColors.textMuted);
    });

    testWidgets('marks at once, sends once, and never plays its row', (
      tester,
    ) async {
      final items = [_track('qobuz', 1), _track('qobuz', 2)];
      final api = _Api()..held = Completer<void>();
      final container = await pumpRows(tester, items, width: _wide, api: api);

      await tester.tap(_in(items[0], _hearts));
      await tester.pump();
      expect(_heartIcon(tester, items[0]).icon, Icons.favorite_rounded);
      await tester.tap(_in(items[0], _hearts));
      await tester.pump();
      expect(api.marked, [items[0].id]);
      expect(api.unmarked, isEmpty);

      api.held!.complete();
      await tester.pumpAndSettle();
      expect(_heartIcon(tester, items[0]).icon, Icons.favorite_rounded);
      expect(_heartIcon(tester, items[1]).icon, Icons.favorite_border_rounded);
      expect(api.replaced, isEmpty);
      expect(api.played, isEmpty);
      expect(container.read(toastProvider), isEmpty);

      await tester.tap(_in(items[0], _hearts));
      await tester.pump();
      expect(api.unmarked, [items[0].id]);
      expect(_heartIcon(tester, items[0]).icon, Icons.favorite_border_rounded);
      expect(api.replaced, isEmpty);
    });

    testWidgets('takes a near miss in its square rather than play the row', (
      tester,
    ) async {
      final items = [_track('qobuz', 1)];
      final api = _Api();
      await pumpRows(tester, items, width: _wide, api: api);

      await tester.tapAt(tester.getRect(_hearts).topLeft + const Offset(2, 2));
      await tester.pump();

      expect(api.marked, [items[0].id]);
      expect(api.replaced, isEmpty);
    });

    testWidgets('keeps a Ctrl-click for itself', (tester) async {
      final items = [_track('qobuz', 1)];
      final api = _Api();
      final container = await pumpRows(tester, items, width: _wide, api: api);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await mouse.down(tester.getCenter(_hearts));
      await mouse.up();
      await tester.pump();
      expect(api.marked, [items[0].id]);
      expect(container.read(selectionStateProvider).isActive, isFalse);

      // The same click on the row's words selects it.
      await mouse.down(tester.getCenter(find.text('Song 1')));
      await mouse.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(container.read(selectionStateProvider).isActive, isTrue);
      expect(api.replaced, isEmpty);
    });

    testWidgets('takes no tap until its source\'s favourites are known', (
      tester,
    ) async {
      final items = [_track('qobuz', 1)];
      final api = _Api()..away.add('qobuz');
      await pumpRows(tester, items, width: _wide, api: api);

      expect(_hearts, findsOneWidget);
      await tester.tap(_hearts);
      await tester.pump();

      expect(api.marked, isEmpty);
      expect(api.replaced, isEmpty);
      expect(
        tester.getSemantics(_heartNode),
        matchesSemantics(
          label: 'Add to favourites',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );

      // Asked again a few times while it stays away, inert all the while.
      await tester.pump(const Duration(seconds: 16));
      await tester.tap(_hearts);
      await tester.pump();
      expect(api.asked, ['qobuz', 'qobuz', 'qobuz', 'qobuz', 'qobuz']);
      expect(api.marked, isEmpty);
    });

    testWidgets('goes with the + while tracks are selected, its room kept', (
      tester,
    ) async {
      final items = [_track('qobuz', 1), _track('qobuz', 2)];
      final container = await pumpRows(tester, items, width: _wide);
      final time = _time(tester, items[1]);

      container
          .read(selectionStateProvider.notifier)
          .enterSelectionMode(items[0].id);
      await tester.pump();

      expect(_hearts, findsNothing);
      expect(_plus, findsNothing);
      expect(_time(tester, items[1]), time);
    });

    testWidgets('follows a change made elsewhere', (tester) async {
      final events = StreamController<PlayQueueEvent>();
      addTearDown(events.close);
      final items = [_track('qobuz', 1), _track('qobuz', 2)];
      final api = _Api();
      await pumpRows(tester, items, width: _wide, api: api, events: events);

      events.add(
        PlayQueueEvent.favoriteChanged(id: items[1].id, favorite: true, seq: 1),
      );
      await tester.pump();
      await tester.pump();

      expect(_heartIcon(tester, items[1]).icon, Icons.favorite_rounded);
      expect(_heartIcon(tester, items[0]).icon, Icons.favorite_border_rounded);
      expect(api.asked, ['qobuz']);
    });

    testWidgets('rebuilds only the row whose mark changed', (tester) async {
      final items = [_track('qobuz', 1), _track('qobuz', 2)];
      await pumpRows(tester, items, width: _wide);

      await tester.tap(_in(items[0], _hearts));

      expect(tester.element(_row(items[0])).dirty, isTrue);
      expect(tester.element(_row(items[1])).dirty, isFalse);
      expect(tester.element(find.byType(BrowseItemRows)).dirty, isFalse);
      await tester.pump();
    });
  });

  group('a track row\'s semantics', () {
    // The row's own node, which reads its words after its name.
    Finder node(String name) => find.ancestor(
      of: find.text(name),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == name,
      ),
    );

    Iterable<String?> actionsOf(WidgetTester tester, String name) => [
      for (final id
          in tester
                  .getSemantics(node(name))
                  .getSemanticsData()
                  .customSemanticsActionIds ??
              const <int>[])
        CustomSemanticsAction.getAction(id)?.label,
    ];

    testWidgets('offer the mark as an action of the row', (tester) async {
      final items = [_track('qobuz', 1), _track('jamendo', 2)];
      final api = _Api();
      await pumpRows(tester, items, width: _narrow, api: api);

      expect(actionsOf(tester, 'Song 1'), [
        'Add to queue',
        'Play next',
        'Add to favourites',
      ]);
      expect(actionsOf(tester, 'Song 2'), ['Add to queue', 'Play next']);

      tester.semantics.customAction(
        find.semantics.byLabel(RegExp('^Song 1')),
        const CustomSemanticsAction(label: 'Add to favourites'),
      );
      await tester.pump();

      expect(api.marked, [items[0].id]);
      expect(api.replaced, isEmpty);
      expect(actionsOf(tester, 'Song 1'), [
        'Add to queue',
        'Play next',
        'Remove from favourites',
      ]);
    });
  });

  group('a mark the server does not make', () {
    for (final (failure, said) in [
      (Exception('connection reset'), 'Could not add this track to favourites'),
      (
        ServerRefusalException(
          DioException(requestOptions: RequestOptions()),
          favoriteRefused,
          'A track of your own cannot be a favourite.',
        ),
        'A track of your own cannot be a favourite.',
      ),
    ]) {
      testWidgets('is taken back: $said', (tester) async {
        final items = [_track('qobuz', 1)];
        final api = _Api()..failure = failure;
        final container = await pumpRows(tester, items, width: _wide, api: api);

        await tester.tap(_hearts);
        await tester.pump();

        expect(api.marked, [items[0].id]);
        expect(
          _heartIcon(tester, items[0]).icon,
          Icons.favorite_border_rounded,
        );
        final toast = container.read(toastProvider).single;
        expect(toast.message, said);
        expect(toast.isError, isTrue);
        expect(toast.inPanel, isFalse);
        // What the server holds is asked again: the change may have been
        // made all the same.
        await tester.pump();
        expect(api.asked, ['qobuz', 'qobuz']);
        await tester.pump(const Duration(seconds: 30));
      });
    }

    testWidgets('keeps a mark it could not take off, and says so', (
      tester,
    ) async {
      final items = [_track('qobuz', 1)];
      final api = _Api()
        ..favorites.add(items[0].id)
        ..failure = Exception('connection reset');
      final container = await pumpRows(tester, items, width: _wide, api: api);

      await tester.tap(_hearts);
      await tester.pump();

      expect(api.unmarked, [items[0].id]);
      expect(_heartIcon(tester, items[0]).icon, Icons.favorite_rounded);
      expect(
        container.read(toastProvider).single.message,
        'Could not remove this track from favourites',
      );
      await tester.pump(const Duration(seconds: 30));
    });
  });
}
