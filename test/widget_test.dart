import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/main.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/indexer_status_provider.dart';
import 'package:kalinka/providers/onboarding_provider.dart';
import 'package:kalinka/providers/renderer_host_provider.dart';
import 'package:kalinka/providers/websocket_provider.dart';
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

class _FakeIndexerStatusNotifier extends IndexerStatusNotifier {
  @override
  IndexerStatusState build() => const IndexerStatusState();

  @override
  void acquire() {}

  @override
  void release() {}
}

void main() {
  testWidgets('renderer host stays active under an opaque route', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      ConnectionSettingsNotifier.sharedPrefName: 'Test',
      ConnectionSettingsNotifier.sharedPrefHost: 'localhost',
      ConnectionSettingsNotifier.sharedPrefPort: 8080,
      OnboardingStatusNotifier.sharedPrefOobeComplete: true,
      OnboardingStatusNotifier.sharedPrefCoachMarksShown: true,
    });
    final prefs = await SharedPreferences.getInstance();
    var hostBuilds = 0;
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        indexerStatusProvider.overrideWith(_FakeIndexerStatusNotifier.new),
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

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => const SizedBox.expand(),
      ),
    );
    await tester.pump();

    container.read(_epochProvider.notifier).increment();
    await tester.pump();
    expect(hostBuilds, 2);
  });
}
