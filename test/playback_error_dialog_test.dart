import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/kalinka_ws_api.dart';
import 'package:kalinka/providers/kalinka_ws_api_provider.dart';
import 'package:kalinka/widgets/kalinka_dialog.dart';
import 'package:kalinka/widgets/playback_error_dialog.dart';

// The playback-error dialog used to live in MiniPlayer; it now renders via
// showKalinkaDialog (driven from MusicPlayerScreen so it also shows on
// tablet, where MiniPlayer isn't mounted). These tests cover the dialog widget
// and the show-helper integration directly.

/// Records queue commands instead of hitting the websocket.
class _FakeWsApi extends KalinkaWsApi {
  _FakeWsApi(super.ref);

  final List<QueueCommand> sent = [];

  @override
  Future<void> sendQueueCommand(QueueCommand command) async {
    sent.add(command);
  }
}

List<Override> _overrides() => [
  kalinkaWsApiProvider.overrideWith((ref) => _FakeWsApi(ref)),
];

void main() {
  group('PlaybackErrorDialog widget', () {
    testWidgets('renders title, message and both actions', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(),
          child: const MaterialApp(
            home: Scaffold(
              body: PlaybackErrorDialog(message: 'Unsupported codec'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Playback error'), findsOneWidget);
      expect(find.text('Unsupported codec'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
    });

    testWidgets('falls back to default text when message is null',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(),
          child: const MaterialApp(
            home: Scaffold(body: PlaybackErrorDialog()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('This track couldn’t be played.'), findsOneWidget);
    });

    testWidgets('wide (tablet) layout keeps the card in the player panel', (
      tester,
    ) async {
      // The tablet/phone split is decided reactively from layout constraints,
      // so drive it with a wide surface rather than a constructor flag.
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(),
          child: const MaterialApp(
            home: Scaffold(body: PlaybackErrorDialog(message: 'Boom')),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Playback error'), findsOneWidget);
      expect(find.text('Boom'), findsOneWidget);
      // Left half of the window — the Now Playing side.
      expect(
        tester.getRect(find.byKey(KalinkaDialog.cardKey)).right,
        lessThanOrEqualTo(600),
      );
    });
  });

  group('showKalinkaDialog + PlaybackErrorDialog', () {
    Future<void> openDialog(
      WidgetTester tester,
      ProviderContainer container, {
      String? message,
    }) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => showKalinkaDialog<void>(
                      context: context,
                      builder: (_) => PlaybackErrorDialog(message: message),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the dialog with the message', (tester) async {
      final container = ProviderContainer(overrides: _overrides());
      addTearDown(container.dispose);

      await openDialog(tester, container, message: 'Network down');

      expect(find.text('Playback error'), findsOneWidget);
      expect(find.text('Network down'), findsOneWidget);
    });

    testWidgets('Dismiss closes without sending a command', (tester) async {
      final container = ProviderContainer(overrides: _overrides());
      addTearDown(container.dispose);

      await openDialog(tester, container, message: 'Boom');
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();

      expect(find.text('Playback error'), findsNothing);
      final api = container.read(kalinkaWsApiProvider) as _FakeWsApi;
      expect(api.sent, isEmpty);
    });

    testWidgets('Skip sends QueueCommand.next() and closes', (tester) async {
      final container = ProviderContainer(overrides: _overrides());
      addTearDown(container.dispose);

      await openDialog(tester, container, message: 'Boom');
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('Playback error'), findsNothing);
      final api = container.read(kalinkaWsApiProvider) as _FakeWsApi;
      expect(api.sent, [const QueueCommand.next()]);
    });
  });
}
