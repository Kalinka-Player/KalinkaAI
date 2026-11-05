import 'support/receivers.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/main.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/indexer_status_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/kiosk_provider.dart';
import 'package:kalinka/providers/onboarding_provider.dart';
import 'package:kalinka/providers/renderer_host_provider.dart';
import 'package:kalinka/providers/websocket_provider.dart';
import 'package:kalinka/screens/kiosk_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _EpochNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}

final _epochProvider = NotifierProvider<_EpochNotifier, int>(
  _EpochNotifier.new,
);

/// Home's sections ask the server for catalogs; the real client would keep a
/// ten-minute keep-alive timer running past the test.
class _NoServer implements KalinkaPlayerProxy {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeIndexerStatusNotifier extends IndexerStatusNotifier {
  @override
  IndexerStatusState build() => const IndexerStatusState();

  @override
  void acquire() {}

  @override
  void release() {}
}

class _Tracks extends PlayQueueStateStore {
  @override
  PlayQueueState build() => PlayQueueState.empty;

  void showTrack(int number) {
    final track = Track(
      id: 'kalinka:qobuz:track:$number',
      title: 'Track $number',
      duration: 240,
    );
    state = state.copyWith(
      trackList: [track],
      playbackState: PlaybackState(
        state: PlayerStateType.playing,
        currentTrack: track,
        index: 0,
      ),
      seq: number,
    );
  }
}

void main() {
  for (final localDisplay in [false, true]) {
    testWidgets('renderer host stays active under an opaque route '
        '(local display: $localDisplay)', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        ConnectionSettingsNotifier.sharedPrefName: 'Test',
        ConnectionSettingsNotifier.sharedPrefHost: 'localhost',
        ConnectionSettingsNotifier.sharedPrefPort: 8080,
        OnboardingStatusNotifier.sharedPrefOobeComplete: true,
        OnboardingStatusNotifier.sharedPrefCoachMarksShown: true,
      });
      final prefs = await SharedPreferences.getInstance();
      var hostBuilds = 0;
      final tracks = _Tracks();
      final container = ProviderContainer(
        overrides: [
          noReceivers,
          sharedPrefsProvider.overrideWithValue(prefs),
          localDisplayKioskProvider.overrideWithValue(localDisplay),
          playQueueStateStoreProvider.overrideWith(() => tracks),
          indexerStatusProvider.overrideWith(_FakeIndexerStatusNotifier.new),
          kalinkaProxyProvider.overrideWithValue(_NoServer()),
          rendererHostProvider.overrideWith((ref) {
            ref.watch(_epochProvider);
            hostBuilds++;
          }),
          webSocketProvider.overrideWith(
            (ref, path) => Completer<WebSocketChannel>().future,
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const KalinkaApp(),
        ),
      );
      expect(hostBuilds, 1);

      if (localDisplay) {
        expect(find.byType(KioskScreen), findsOneWidget);
        await tester.pump(const Duration(seconds: 4));
        await tester.pump();
        await tester.tap(find.byIcon(Icons.home_outlined));
        await tester.pump();
        expect(find.byType(KioskScreen), findsNothing);
        tracks.showTrack(1);
        await tester.pump();
        expect(container.read(kioskActiveProvider), isFalse);
        expect(find.byType(KioskScreen), findsNothing);
        await tester.pump(const Duration(seconds: 5));
        tracks.showTrack(2);
        await tester.pump();
        expect(container.read(kioskActiveProvider), isFalse);
        expect(find.byType(KioskScreen), findsNothing);
      }

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push<void>(
        PageRouteBuilder<void>(
          opaque: true,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) =>
              const SizedBox.expand(key: ValueKey('open-route')),
        ),
      );
      await tester.pump();

      container.read(_epochProvider.notifier).increment();
      await tester.pump();
      expect(hostBuilds, 2);
      expect(find.byType(KioskScreen), findsNothing);

      if (localDisplay) {
        await tester.pump(const Duration(seconds: 24));
        expect(find.byType(KioskScreen), findsNothing);
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(KioskScreen), findsOneWidget);
        expect(find.byKey(const ValueKey('open-route')), findsNothing);
        await tester.tap(find.byIcon(Icons.home_outlined));
        await tester.pump();
        expect(find.byType(KioskScreen), findsNothing);
        expect(find.byKey(const ValueKey('open-route')), findsOneWidget);
        expect(hostBuilds, 2);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
  }
}
