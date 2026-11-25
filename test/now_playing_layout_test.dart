import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/data_model/kalinka_ws_api.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/kalinka_ws_api_provider.dart';
import 'package:kalinka/providers/queue_features_provider.dart';
import 'package:kalinka/providers/renderer_provider.dart';
import 'package:kalinka/providers/renderer_host_provider.dart';
import 'package:kalinka/renderer/renderer_identity.dart';
import 'package:kalinka/providers/shell_nav_provider.dart';
import 'package:kalinka/providers/server_refusal.dart';
import 'package:kalinka/providers/toast_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/now_playing_content.dart';
import 'package:kalinka/widgets/player_header.dart';
import 'package:kalinka/widgets/player_view_switch.dart';
import 'package:kalinka/widgets/play_pause_glyph.dart';
import 'package:kalinka/widgets/renderer_switcher.dart';
import 'package:kalinka/widgets/playback_progress_slider.dart';
import 'package:kalinka/widgets/transport_button.dart';
import 'package:kalinka/widgets/transport_controls.dart';

import 'support/home_shell.dart';

class _Api extends KalinkaWsApi {
  _Api(super.ref);
  final sent = <QueueCommand>[];
  @override
  Future<void> sendQueueCommand(QueueCommand command) async =>
      sent.add(command);
}

class _Renderers extends RendererListNotifier {
  _Renderers([this.name = 'Living room']);
  final String name;

  @override
  RendererListState build() => RendererListState(
    loaded: true,
    renderers: [
      RendererInfo(
        rendererId: 'amp',
        friendlyName: name,
        status: 'connected',
        active: true,
      ),
    ],
  );

  @override
  Future<void> refresh() async {}
}

/// Turns the playing track down as a server would: [playing] false is its
/// 409, nothing playing.
class _DislikeApi extends HomeApi {
  _DislikeApi({this.playing = true});

  final bool playing;
  int disliked = 0;

  @override
  Future<bool> dislikeCurrent() async {
    disliked++;
    return playing;
  }
}

/// Keeps favourites as a server would: [favorites] are the source's marked
/// tracks. An add or a remove fails with [failure] where it is set, and waits
/// for [held] where that is.
class _FavoritesApi extends _DislikeApi {
  _FavoritesApi({this.favorites = const {}, this.failure, this.held});

  final Set<String> favorites;
  final Exception? failure;
  final Completer<void>? held;
  final List<String?> asked = [];
  final List<String> added = [];
  final List<String> removed = [];

  @override
  Future<FavoriteIds> getFavoriteIds({String? source}) async {
    asked.add(source);
    return FavoriteIds(
      albums: [],
      tracks: [...favorites],
      artists: [],
      playlists: [],
    );
  }

  @override
  Future<StatusMessage> addFavorite(String id) async {
    added.add(id);
    return _answer();
  }

  @override
  Future<StatusMessage> removeFavorite(String id) async {
    removed.add(id);
    return _answer();
  }

  Future<StatusMessage> _answer() async {
    await held?.future;
    if (failure != null) throw failure!;
    return StatusMessage(message: 'Ok');
  }
}

const _dislikes = QueueFeatures(similar: true, dislike: true);
final _dislike = find.byTooltip('Not like this');
final _heart = find.byTooltip('Add to favourites');
final _hearted = find.byTooltip('Remove from favourites');

/// Which of the thumb-down and the heart a layout is checked with.
const _titleActionCases = [
  (false, false),
  (true, false),
  (false, true),
  (true, true),
];

/// The source the queue's tracks come from where they need one.
const _qobuz = 'qobuz';

ModuleInfo _source({bool favorites = true}) => ModuleInfo(
  name: _qobuz,
  title: 'Qobuz',
  enabled: true,
  state: ModuleState.ready,
  capabilities: [if (favorites) ModuleCapability.favorites],
);

final _preview = find.byKey(const ValueKey('now-playing-up-next'));
final _art = find.byKey(const ValueKey('now-playing-artwork'));
final _presentation = find.byKey(const ValueKey('now-playing-presentation'));
final _metadata = find.byKey(const ValueKey('now-playing-metadata'));
Finder _row(int index) => find.byKey(ValueKey('up-next-track-$index'));
Finder get _rows => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('up-next-track-'),
);

PlayQueueState _queue({
  int index = 0,
  int count = 10,
  bool exclusive = false,
  int seq = 1,
  bool longNames = false,
  String? source,
}) => PlayQueueState(
  trackList: [
    for (var i = 0; i < count; i++)
      Track(
        id: source == null ? 'track-$i' : 'kalinka:$source:track:$i',
        title: longNames
            ? 'Evening track $i — a live recording from the northern coast'
            : 'Evening track $i',
        duration: 200,
        performer: Artist(
          id: 'kalinka:demo:artist:artist',
          name: longNames
              ? 'A favourite artist with the late night orchestra'
              : 'A favourite artist',
        ),
        album: Album(
          id: 'kalinka:demo:album:album',
          title: 'Evening sessions',
          year: 2026,
        ),
      ),
  ],
  playbackState: PlaybackState(index: index, state: PlayerStateType.playing),
  playbackMode: PlaybackMode.empty,
  playbackControl: exclusive
      ? const PlaybackControl.exclusive(pluginId: 'connect', title: 'Connect')
      : const PlaybackControl.queue(),
  seq: seq,
);

/// The thumb-down and the heart beside [title] where [dislike] and [favorite]
/// say they show, each a whole 48dp target inside the window, its top at the
/// title's top. Flush left they follow the title, thumb-down first; else the
/// thumb-down comes before it and the heart after it, and the title keeps the
/// centre of the details whichever shows. A short window scales the
/// presentation they sit in down, so their size is measured in its own terms.
void _expectTitleActions(
  WidgetTester tester,
  String title, {
  required bool dislike,
  required bool favorite,
  required bool leftAligned,
}) {
  final text = tester.getRect(find.text(title));
  final shown = <Rect>[];
  for (final (button, on) in [(_dislike, dislike), (_heart, favorite)]) {
    if (!on) {
      expect(button, findsNothing);
      continue;
    }
    expect(button.hitTestable(), findsOneWidget);
    expect(tester.getSize(button), const Size.square(48));
    final bounds = tester.getRect(button);
    expect(bounds.top, closeTo(text.top, 0.5));
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(
      bounds.right,
      lessThanOrEqualTo(tester.view.physicalSize.width - 16),
    );
    shown.add(bounds);
  }
  if (leftAligned) {
    var after = text.right;
    for (final bounds in shown) {
      expect(bounds.left, greaterThanOrEqualTo(after));
      after = bounds.right;
    }
    return;
  }
  if (dislike) {
    expect(tester.getRect(_dislike).right, lessThanOrEqualTo(text.left));
  }
  if (favorite) {
    expect(tester.getRect(_heart).left, greaterThanOrEqualTo(text.right));
  }
  expect(text.center.dx, closeTo(tester.getCenter(_metadata).dx, 0.5));
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required SettableQueue queue,
  Size size = const Size(432, 1280),
  double scale = 1,
  Key? captureKey,
  bool overlay = false,
  Key? outputKey,
  String outputName = 'Living room',
  QueueFeatures? features,
  KalinkaPlayerProxy? api,
  List<ModuleInfo> sources = const [],
}) async {
  final container = await pumpHomeShell(
    tester,
    queue: queue,
    size: size,
    api: api,
    sources: sources,
    overrides: [
      if (features != null)
        queueFeaturesProvider.overrideWith((ref) async => features),
      kalinkaWsApiProvider.overrideWith((ref) => _Api(ref)),
      rendererListProvider.overrideWith(() => _Renderers(outputName)),
      rendererIdentityProvider.overrideWith(
        (ref) async => const RendererIdentity(
          rendererId: 'this-device',
          instanceId: 'test',
          friendlyName: 'Test',
          softwareVersion: 'test',
          os: 'linux',
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: RepaintBoundary(
            key: captureKey,
            child: Scaffold(
              body: NowPlayingContent(
                isTablet: !overlay,
                showOverlayHeader: overlay,
                onClose: () {},
                outputSwitcherKey: outputKey,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  final captures = Platform.environment['KALINKA_REVIEW_DIR'];
  group('thumbs-down', () {
    testWidgets('a server without a dislike offers none', (tester) async {
      await _pump(
        tester,
        queue: SettableQueue(_queue()),
        features: QueueFeatures.none,
      );
      expect(find.text('Evening track 0'), findsOneWidget);
      expect(_dislike, findsNothing);
    });

    for (final (name, queue) in [
      ('an empty queue', PlayQueueState.empty),
      ('a plugin playing', _queue(exclusive: true)),
    ]) {
      testWidgets('$name has nothing of the queue\'s to turn down', (
        tester,
      ) async {
        await _pump(tester, queue: SettableQueue(queue), features: _dislikes);
        expect(_dislike, findsNothing);
      });
    }

    testWidgets('turning a track down skips it and says so', (tester) async {
      final api = _DislikeApi();
      final container = await _pump(
        tester,
        queue: SettableQueue(_queue()),
        features: _dislikes,
        api: api,
      );
      expect(
        tester.getSemantics(_dislike),
        matchesSemantics(
          label: 'Not like this',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );

      await tester.tap(_dislike);
      await tester.pump();

      expect(api.disliked, 1);
      final toast = container.read(toastProvider).single;
      expect(toast.message, 'Skipped — this queue will avoid tracks like it');
      expect(toast.isError, isFalse);
      expect(toast.inPanel, isTrue);
      expect((container.read(kalinkaWsApiProvider) as _Api).sent, isEmpty);
      await tester.pump(const Duration(seconds: 30));
    });

    testWidgets('with nothing playing on the server it says nothing', (
      tester,
    ) async {
      final api = _DislikeApi(playing: false);
      final container = await _pump(
        tester,
        queue: SettableQueue(_queue()),
        features: _dislikes,
        api: api,
      );

      await tester.tap(_dislike);
      await tester.pump();

      expect(api.disliked, 1);
      expect(container.read(toastProvider), isEmpty);
    });

    testWidgets('a server away takes no dislike', (tester) async {
      final api = _DislikeApi();
      final container = await _pump(
        tester,
        queue: SettableQueue(_queue()),
        features: _dislikes,
        api: api,
      );
      (container.read(connectionStateProvider.notifier) as SettableConnection)
          .set(ConnectionStatus.offline);
      await tester.pump();

      await tester.tap(_dislike, warnIfMissed: false);
      await tester.pump();

      expect(api.disliked, 0);
    });
  });

  group('favourite heart', () {
    const playing = 'kalinka:$_qobuz:track:0';

    Future<ProviderContainer> pumpHeart(
      WidgetTester tester,
      _FavoritesApi api, {
      PlayQueueState? queue,
      List<ModuleInfo>? sources,
    }) => _pump(
      tester,
      queue: SettableQueue(queue ?? _queue(source: _qobuz)),
      features: QueueFeatures.none,
      api: api,
      sources: sources ?? [_source()],
    );

    Icon heartIcon(WidgetTester tester, Finder heart) => tester.widget<Icon>(
      find.descendant(of: heart, matching: find.byType(Icon)),
    );

    for (final (name, queue, sources) in [
      ('a source that keeps no favourites', null, [_source(favorites: false)]),
      ('a track of another source', _queue(source: 'jamendo'), null),
      ('a plugin playing', _queue(source: _qobuz, exclusive: true), null),
      ('an empty queue', PlayQueueState.empty, null),
    ]) {
      testWidgets('$name offers none', (tester) async {
        final api = _FavoritesApi();
        await pumpHeart(tester, api, queue: queue, sources: sources);
        expect(_heart, findsNothing);
        expect(_hearted, findsNothing);
        expect(api.asked, isEmpty);
      });
    }

    testWidgets('shows what the track\'s source has marked', (tester) async {
      final api = _FavoritesApi(favorites: {playing});
      await pumpHeart(tester, api);

      expect(api.asked, [_qobuz]);
      expect(_hearted, findsOneWidget);
      expect(_heart, findsNothing);
      final icon = heartIcon(tester, _hearted);
      expect(icon.icon, Icons.favorite_rounded);
      expect(icon.color, KalinkaColors.accent);
      expect(icon.size, 20);
      expect(
        tester.getSemantics(_hearted),
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

    testWidgets('a tap marks it at once, and sends once', (tester) async {
      final held = Completer<void>();
      final api = _FavoritesApi(held: held);
      final container = await pumpHeart(tester, api);
      final icon = heartIcon(tester, _heart);
      expect(icon.icon, Icons.favorite_border_rounded);
      expect(icon.color, KalinkaColors.textSecondary);

      await tester.tap(_heart);
      await tester.pump();
      expect(_hearted, findsOneWidget);
      await tester.tap(_hearted, warnIfMissed: false);
      await tester.pump();
      expect(api.added, [playing]);
      expect(api.removed, isEmpty);

      held.complete();
      await tester.pump();
      expect(_hearted, findsOneWidget);
      expect(container.read(toastProvider), isEmpty);
    });

    testWidgets('a tap on a favourite takes it off', (tester) async {
      final api = _FavoritesApi(favorites: {playing});
      await pumpHeart(tester, api);

      await tester.tap(_hearted);
      await tester.pump();

      expect(api.removed, [playing]);
      expect(api.added, isEmpty);
      expect(_heart, findsOneWidget);
    });

    for (final (failure, said) in [
      (Exception('connection reset'), 'Could not add this track to favourites'),
      (
        ServerRefusalException(
          DioException(requestOptions: RequestOptions()),
          'demo_read_only',
          'This is a read-only demo server.',
        ),
        'This is a read-only demo server.',
      ),
    ]) {
      testWidgets('a failed mark is taken back: $said', (tester) async {
        final api = _FavoritesApi(failure: failure);
        final container = await pumpHeart(tester, api);

        await tester.tap(_heart);
        await tester.pump();

        expect(api.added, [playing]);
        expect(_heart, findsOneWidget);
        expect(_hearted, findsNothing);
        final toast = container.read(toastProvider).single;
        expect(toast.message, said);
        expect(toast.isError, isTrue);
        expect(toast.inPanel, isTrue);
        await tester.pump(const Duration(seconds: 30));
      });
    }

    testWidgets('a failed removal says so and keeps the mark', (tester) async {
      final api = _FavoritesApi(
        favorites: {playing},
        failure: Exception('connection reset'),
      );
      final container = await pumpHeart(tester, api);

      await tester.tap(_hearted);
      await tester.pump();

      expect(api.removed, [playing]);
      expect(_hearted, findsOneWidget);
      expect(
        container.read(toastProvider).single.message,
        'Could not remove this track from favourites',
      );
      await tester.pump(const Duration(seconds: 30));
    });

    testWidgets('a server away takes no tap', (tester) async {
      final api = _FavoritesApi();
      final container = await pumpHeart(tester, api);
      (container.read(connectionStateProvider.notifier) as SettableConnection)
          .set(ConnectionStatus.offline);
      await tester.pump();

      await tester.tap(_heart, warnIfMissed: false);
      await tester.pump();

      expect(api.added, isEmpty);
    });

    testWidgets('a two-line title keeps both on its first line', (
      tester,
    ) async {
      final queue = _queue(source: _qobuz, longNames: true);
      await _pump(
        tester,
        queue: SettableQueue(queue),
        size: const Size(375, 812),
        features: _dislikes,
        api: _FavoritesApi(),
        sources: [_source()],
      );
      final title = tester.getRect(find.text(queue.trackList.first.title));

      _expectTitleActions(
        tester,
        queue.trackList.first.title,
        dislike: true,
        favorite: true,
        leftAligned: false,
      );
      expect(title.height, greaterThan(tester.getRect(_heart).height));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Now Playing updates when only the audio codec changes', (
    tester,
  ) async {
    PlayQueueState playing(String? codec) {
      final state = _queue();
      state.playbackState
        ..mimeType = 'application/dash+xml'
        ..audioCodec = codec;
      return state;
    }

    final queue = SettableQueue(playing('flac'));
    final captureKey = GlobalKey();
    await _pump(tester, queue: queue, captureKey: captureKey);
    expect(find.text('FLAC'), findsOneWidget);
    expect(find.textContaining('DASH+XML'), findsNothing);
    if (captures != null) {
      await tester.runAsync(() async {
        final boundary =
            captureKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$captures/audio-codec.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    queue.set(playing('aac'));
    await tester.pumpAndSettle();
    expect(find.text('AAC'), findsOneWidget);
    expect(find.text('FLAC'), findsNothing);
    queue.set(playing(null));
    await tester.pumpAndSettle();
    expect(find.text('DASH+XML'), findsOneWidget);
  });

  setUpAll(() async {
    if (captures == null) return;
    for (final (family, file) in [
      ('IBM Plex Sans', 'IBMPlexSans-Regular.ttf'),
      ('IBM Plex Sans', 'IBMPlexSans-SemiBold.ttf'),
      ('IBM Plex Mono', 'IBMPlexMono-Regular.ttf'),
      ('Playfair Display', 'PlayfairDisplay-Regular.ttf'),
    ]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$file'))).load();
    }
    final material = File(
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (material.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(material.readAsBytesSync())),
          ))
          .load();
    }
  });

  testWidgets('preview follows queue order and plays the existing occurrence', (
    tester,
  ) async {
    final queue = SettableQueue(_queue(index: 2));
    final container = await _pump(tester, queue: queue);
    final semantics = tester.ensureSemantics();
    expect(_rows, findsNWidgets(5));
    expect(
      find.descendant(of: _preview, matching: find.text('UP NEXT')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _preview, matching: find.text('· 7')),
      findsOneWidget,
    );
    expect(_row(2), findsNothing);
    expect(_row(3), findsOneWidget);
    expect(_row(7), findsOneWidget);
    expect(_row(8), findsNothing);
    final original = container.read(playQueueStateStoreProvider);
    expect(
      tester.getSemantics(_row(4)),
      matchesSemantics(
        label: 'Evening track 4, A favourite artist',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    await tester.tap(_row(4));
    await tester.pump();
    expect((container.read(kalinkaWsApiProvider) as _Api).sent, [
      const QueueCommand.play(index: 4),
    ]);
    expect(container.read(playQueueStateStoreProvider), same(original));
    queue.set(_queue(index: 5, seq: 2));
    await tester.pumpAndSettle();
    expect(_rows, findsNWidgets(4));
    expect(_row(6), findsOneWidget);
    expect(_row(3), findsNothing);
    expect(
      find.descendant(of: _preview, matching: find.text('· 4')),
      findsOneWidget,
    );
    final advanced = container.read(playQueueStateStoreProvider);
    queue.set(
      advanced.copyWith(
        trackList: [
          ...advanced.trackList.take(6),
          ...advanced.trackList.skip(6).toList().reversed,
        ],
        seq: 3,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _row(6), matching: find.text('Evening track 9')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('View queue'));
    await tester.pumpAndSettle();
    expect(container.read(playerViewProvider), PlayerView.queue);
    expect(_preview, findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('preview highlights stay neutral, inset and clickable', (
    tester,
  ) async {
    final captureKey = GlobalKey();
    final container = await _pump(
      tester,
      queue: SettableQueue(_queue()),
      captureKey: captureKey,
    );
    final heading = find.byTooltip('View queue');
    final headingRect = tester.getRect(heading);
    final label = find.descendant(of: heading, matching: find.text('UP NEXT'));
    final chevron = find.descendant(
      of: heading,
      matching: find.byIcon(Icons.chevron_right),
    );
    expect(
      tester.getRect(label).left - headingRect.left,
      greaterThanOrEqualTo(12),
    );
    expect(
      headingRect.right - tester.getRect(chevron).right,
      greaterThanOrEqualTo(12),
    );
    final artwork = find.descendant(
      of: _row(1),
      matching: find.byType(ClipRRect),
    );
    expect(
      tester.getRect(artwork).left - tester.getRect(_row(1)).left,
      greaterThanOrEqualTo(12),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    for (final target in [heading, _row(1)]) {
      await mouse.moveTo(tester.getCenter(target));
      await tester.pumpAndSettle();
      expect(
        tester.binding.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );
      final ink = tester.widget<InkWell>(
        find.descendant(of: target, matching: find.byType(InkWell)),
      );
      for (final state in [
        WidgetState.hovered,
        WidgetState.pressed,
        WidgetState.focused,
      ]) {
        final color = ink.overlayColor!.resolve({state})!;
        expect(color.a, greaterThan(0));
        // Neutral surfaces can have a small warm tint, but no berry hue.
        expect((color.r - color.g).abs(), lessThan(0.02));
        expect((color.g - color.b).abs(), lessThan(0.02));
      }
    }
    if (captures != null) {
      await tester.runAsync(() async {
        final boundary =
            captureKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$captures/hover.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    (container.read(connectionStateProvider.notifier) as SettableConnection)
        .set(ConnectionStatus.offline);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.binding.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.basic,
    );
    // Opening the cached queue remains available while playback is offline.
    await mouse.moveTo(tester.getCenter(heading));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.binding.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'resizing fits one to five rows without moving or shrinking the cover',
    (tester) async {
      final queue = SettableQueue(_queue());
      final container = await _pump(tester, queue: queue);
      final original = container.read(playQueueStateStoreProvider);
      final art = tester.getRect(_art);
      final previewTop = tester.getRect(_preview).top;
      final headerHeight = tester.getRect(_row(1)).top - previewTop;
      final rowHeight = tester.getSize(_row(1)).height;
      final minimumHeight = previewTop + headerHeight + rowHeight + 16;
      for (final rows in [1, 2, 3, 4, 5]) {
        tester.view.physicalSize = Size(
          432,
          minimumHeight + (rows - 1) * rowHeight + 0.5,
        );
        await tester.pumpAndSettle();
        expect(_rows, findsNWidgets(rows));
        expect(tester.getRect(_art), art);
        expect(container.read(playQueueStateStoreProvider), same(original));
      }
      tester.view.physicalSize = Size(432, minimumHeight - 1);
      await tester.pumpAndSettle();
      expect(_preview, findsNothing);
      expect(tester.getRect(_art), art);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline preview stays readable and inactive; exclusive or empty queue hides it, and its end says so',
    (tester) async {
      final queue = SettableQueue(_queue());
      final container = await _pump(tester, queue: queue);
      (container.read(connectionStateProvider.notifier) as SettableConnection)
          .set(ConnectionStatus.offline);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_preview, findsOneWidget);
      final button = tester.widget<TextButton>(
        find.descendant(of: _row(1), matching: find.byType(TextButton)),
      );
      expect(button.onPressed, isNull);
      (container.read(connectionStateProvider.notifier) as SettableConnection)
          .set(ConnectionStatus.connected);
      queue.set(_queue(exclusive: true, seq: 2));
      await tester.pumpAndSettle();
      expect(_preview, findsNothing);
      // At the end of the queue it says the queue is empty, as the queue does.
      queue.set(_queue(index: 9, seq: 3));
      await tester.pumpAndSettle();
      expect(_preview, findsOneWidget);
      expect(
        find.descendant(of: _preview, matching: find.text('Queue is empty')),
        findsOneWidget,
      );
      queue.set(PlayQueueState.empty);
      await tester.pumpAndSettle();
      expect(_preview, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('resizing rearranges the cover without changing playback', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      queue: SettableQueue(_queue()),
      size: const Size(432, 900),
    );
    final original = container.read(playQueueStateStoreProvider);
    final title = find.text('Evening track 0');
    expect(tester.getRect(title).top, greaterThan(tester.getRect(_art).bottom));
    tester.view.physicalSize = const Size(432, 500);
    await tester.pumpAndSettle();
    expect(tester.getRect(title).left, greaterThan(tester.getRect(_art).right));
    expect(
      tester.getCenter(_metadata).dy,
      closeTo(
        tester
            .getCenter(find.byKey(const ValueKey('now-playing-metadata-area')))
            .dy,
        0.1,
      ),
    );
    tester.view.physicalSize = const Size(432, 900);
    await tester.pumpAndSettle();
    expect(tester.getRect(title).top, greaterThan(tester.getRect(_art).bottom));
    expect(container.read(playQueueStateStoreProvider), same(original));
    expect((container.read(kalinkaWsApiProvider) as _Api).sent, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final empty in [true, false]) {
    testWidgets('short wide player fits artwork with empty queue: $empty', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        queue: SettableQueue(empty ? PlayQueueState.empty : _queue(count: 1)),
        size: const Size(936, 360),
      );
      final original = container.read(playQueueStateStoreProvider);
      for (final height in [360.0, 420.0, 340.0]) {
        tester.view.physicalSize = Size(936, height);
        await tester.pumpAndSettle();
        final art = tester.getRect(_art);
        expect(art.height, greaterThan(0));
        expect(art.bottom, lessThanOrEqualTo(height));
        expect(
          find.byType(RendererSwitcherDropdown).hitTestable(),
          findsOneWidget,
        );
        expect(
          tester.getRect(find.byType(PlaybackProgressSlider)).bottom,
          lessThanOrEqualTo(height),
        );
        final scroll = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(NowPlayingContent),
            matching: find.byType(Scrollable),
          ),
        );
        expect(scroll.position.maxScrollExtent, 0);
        expect(container.read(playQueueStateStoreProvider), same(original));
        expect((container.read(kalinkaWsApiProvider) as _Api).sent, isEmpty);
        expect(tester.takeException(), isNull);
      }
    });
  }

  for (final (dislike, favorite) in _titleActionCases) {
    for (final (size, scale, overlay) in [
      (const Size(936, 600), 1.0, false),
      (const Size(1200, 800), 1.0, false),
      (const Size(936, 1200), 1.0, false),
      (const Size(1600, 1200), 2.0, false),
      (const Size(908, 636), 1.0, true),
      (const Size(1600, 1200), 2.0, true),
      (const Size(2400, 1600), 3.2, true),
    ]) {
      testWidgets(
        'wide player groups controls beside the cover at $size / $scale / overlay $overlay / dislike $dislike / favourite $favorite',
        (tester) async {
          final key = GlobalKey();
          final outputKey = GlobalKey();
          final container = await _pump(
            tester,
            queue: SettableQueue(_queue(source: _qobuz)),
            size: size,
            scale: scale,
            captureKey: key,
            overlay: overlay,
            outputKey: outputKey,
            outputName: scale > 1
                ? 'Living room amplifier with a very long device name'
                : 'SMSL-SU1',
            features: dislike ? _dislikes : null,
            sources: [_source(favorites: favorite)],
            api: favorite ? _FavoritesApi() : null,
          );
          final original = container.read(playQueueStateStoreProvider);
          _expectTitleActions(
            tester,
            'Evening track 0',
            dislike: dislike,
            favorite: favorite,
            leftAligned: true,
          );
          final cover = tester.getRect(_art);
          final controls = find.byKey(
            const ValueKey('now-playing-landscape-controls'),
          );
          expect(controls, findsOneWidget);
          expect(cover.width, closeTo(320, .01));
          expect(cover.height, closeTo(320, .01));
          final progress = tester.getRect(find.byType(PlaybackProgressSlider));
          expect(progress.left, greaterThan(cover.right));
          expect(progress.width, lessThanOrEqualTo(560));
          expect(
            tester.widget<Text>(find.text('Evening track 0')).style!.fontSize,
            32,
          );
          expect(_rows.evaluate().length, inInclusiveRange(1, 5));
          expect(
            tester.getRect(_preview).bottom,
            lessThanOrEqualTo(size.height),
          );
          expect(
            find.byType(RendererSwitcherDropdown).hitTestable(),
            findsOneWidget,
          );
          final headerOutput = find.descendant(
            of: find.byType(PlayerHeader),
            matching: find.byKey(outputKey),
          );
          expect(headerOutput, findsOneWidget);
          final output = tester.getRect(headerOutput);
          final fullscreen = tester.getRect(
            find.byTooltip('Now-playing display'),
          );
          final tabs = tester.getRect(find.byType(PlayerViewSwitch));
          expect(output.height, greaterThanOrEqualTo(48));
          expect(output.width, lessThanOrEqualTo(280));
          expect(output.right + 8, closeTo(fullscreen.left, .01));
          expect(output.center.dy, closeTo(fullscreen.center.dy, .01));
          expect(output.left, greaterThanOrEqualTo(tabs.right + 8));
          expect(tabs.center.dx, closeTo(size.width / 2, .01));
          final play = tester.getRect(
            find.ancestor(
              of: find.byType(PlayPauseGlyph),
              matching: find.byType(TransportButton),
            ),
          );
          expect(play.width, 68);
          expect(play.center.dx, closeTo(progress.center.dx, .01));
          expect(
            tester.getRect(find.byType(ShuffleButton)).left,
            progress.left,
          );
          expect(
            tester.getRect(find.byType(RepeatButton)).right,
            progress.right,
          );
          final scroll = tester.state<ScrollableState>(
            find.descendant(
              of: find.byType(NowPlayingContent),
              matching: find.byType(Scrollable),
            ),
          );
          expect(scroll.position.maxScrollExtent, 0);
          if (captures != null) {
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '$captures/playing-${size.width}-${size.height}-$scale-$overlay-$dislike-$favorite.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          tester.view.physicalSize = const Size(432, 900);
          await tester.pumpAndSettle();
          expect(controls, findsNothing);
          expect(headerOutput, findsNothing);
          expect(find.byKey(outputKey), findsOneWidget);
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          expect(controls, findsOneWidget);
          expect(headerOutput, findsOneWidget);
          expect(container.read(playQueueStateStoreProvider), same(original));
          expect((container.read(kalinkaWsApiProvider) as _Api).sent, isEmpty);
          if (overlay && scale == 1) {
            await tester.tap(headerOutput);
            await tester.pumpAndSettle();
            expect(find.byType(RendererPickerContent), findsOneWidget);
            await tester.tap(find.byTooltip('Close output picker'));
            await tester.pumpAndSettle();
            expect(find.byType(RendererPickerContent), findsNothing);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final (dislike, favorite) in _titleActionCases) {
    for (final (name, size, scale, sideBySide) in [
      ('short', const Size(432, 720), 1.0, false),
      ('long-text', const Size(375, 812), 1.0, false),
      ('desktop', const Size(432, 1080), 1.0, false),
      ('tall', const Size(432, 1200), 1.0, false),
      ('large-text', const Size(375, 812), 2.0, false),
      ('landscape', const Size(812, 375), 1.0, true),
      ('near-square', const Size(432, 540), 1.0, true),
      ('square', const Size(800, 800), 1.0, true),
      ('square-long-text', const Size(640, 640), 2.0, true),
      ('square-large-text', const Size(432, 500), 2.0, false),
      ('touch-display-large-text', const Size(936, 600), 2.0, true),
      ('narrow-square', const Size(320, 400), 1.0, false),
    ]) {
      testWidgets(
        '$name fits artwork, details and controls without scrolling / dislike $dislike / favourite $favorite',
        (tester) async {
          final captureKey = GlobalKey();
          final queue = _queue(
            longNames: name.endsWith('long-text'),
            source: _qobuz,
          );
          await _pump(
            tester,
            queue: SettableQueue(queue),
            size: size,
            scale: scale,
            captureKey: captureKey,
            features: dislike ? _dislikes : null,
            sources: [_source(favorites: favorite)],
            api: favorite ? _FavoritesApi() : null,
          );
          _expectTitleActions(
            tester,
            queue.trackList.first.title,
            dislike: dislike,
            favorite: favorite,
            leftAligned: sideBySide,
          );
          expect(
            tester.getTopLeft(_presentation).dy,
            closeTo(
              tester.getRect(find.byType(PlayerHeader)).bottom +
                  (sideBySide ? 8 : 32),
              0.1,
            ),
          );
          final title = find.text(queue.trackList.first.title);
          final titleBounds = tester.getRect(title);
          final artBounds = tester.getRect(_art);
          final output = find.byType(RendererSwitcherDropdown);
          expect(output, findsOneWidget);
          if (name == 'square') {
            expect(titleBounds.left, greaterThan(artBounds.right));
            expect(
              tester.getRect(find.byType(PlaybackProgressSlider)).left,
              greaterThan(artBounds.right),
            );
            expect(artBounds.width, 320);
          } else if (sideBySide) {
            expect(titleBounds.left, greaterThan(artBounds.right));
            expect(
              tester.getCenter(_metadata).dy,
              closeTo(
                tester
                    .getCenter(
                      find.byKey(const ValueKey('now-playing-metadata-area')),
                    )
                    .dy,
                0.1,
              ),
            );
            final outputBounds = tester.getRect(output);
            expect(outputBounds.left, closeTo(titleBounds.left, 0.1));
            expect(
              outputBounds.bottom,
              closeTo(tester.getRect(_presentation).bottom, 0.1),
            );
            expect(
              artBounds.center.dy,
              closeTo(tester.getRect(_presentation).center.dy, 0.1),
            );
            expect(
              outputBounds.top,
              greaterThan(tester.getRect(_metadata).bottom),
            );
            expect(outputBounds.right, lessThanOrEqualTo(size.width - 16));
            expect(tester.widget<Text>(title).textAlign, TextAlign.left);
            for (final text in [
              queue.trackList.first.performer!.name,
              'Evening sessions · 2026',
            ]) {
              expect(
                tester.getRect(find.text(text).first).left,
                titleBounds.left,
              );
            }
          } else {
            expect(titleBounds.top, greaterThanOrEqualTo(artBounds.bottom));
          }
          if (size.height >= 1080) {
            expect(_preview, findsOneWidget);
            expect(_rows.evaluate().length, inInclusiveRange(1, 5));
            expect(
              tester.getRect(_preview).bottom,
              lessThanOrEqualTo(size.height),
            );
            expect(
              tester.getRect(_rows.first).top,
              greaterThan(
                tester.getRect(find.byType(RendererSwitcherDropdown)).bottom,
              ),
            );
          } else if (!sideBySide) {
            expect(_preview, findsNothing);
          }
          if (name == 'square') {
            expect(_rows.evaluate().length, inInclusiveRange(1, 5));
            expect(
              tester.getRect(_preview).bottom,
              lessThanOrEqualTo(size.height),
            );
          }
          if (captures != null) {
            await tester.runAsync(() async {
              final boundary =
                  captureKey.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File('$captures/$name-$dislike-$favorite.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          final scroll = tester.state<ScrollableState>(
            find.descendant(
              of: find.byType(NowPlayingContent),
              matching: find.byType(Scrollable),
            ),
          );
          expect(scroll.position.maxScrollExtent, closeTo(0, 0.1));
          expect(scroll.position.pixels, closeTo(0, 0.1));
          final before = tester.getRect(_presentation);
          await tester.dragFrom(
            tester.getTopLeft(_presentation) + const Offset(4, 4),
            const Offset(0, -150),
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(_presentation), before);
          expect(scroll.position.pixels, closeTo(0, 0.1));
          expect(
            find.byType(RendererSwitcherDropdown).hitTestable(),
            findsOneWidget,
          );
          expect(
            tester.getBottomRight(find.byType(RendererSwitcherDropdown)).dy,
            lessThanOrEqualTo(size.height),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
