import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/kalinka_ws_api.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_ws_api_provider.dart';
import 'package:kalinka/widgets/gradient_progress_line.dart';
import 'package:kalinka/widgets/mini_player.dart';
import 'package:kalinka/widgets/now_playing_content.dart';
import 'package:kalinka/widgets/player_view_switch.dart';
import 'package:kalinka/widgets/procedural_album_art.dart';
import 'package:kalinka/widgets/transport_button.dart';

import 'support/focus.dart';
import 'support/home_shell.dart';

class _RecordingWsApi extends KalinkaWsApi {
  _RecordingWsApi(super.ref);

  final List<QueueCommand> sent = [];

  @override
  Future<void> sendQueueCommand(QueueCommand command) async {
    sent.add(command);
  }
}

Finder _inPlayer(Finder finder) =>
    find.descendant(of: find.byType(NowPlayingContent), matching: finder);

Finder _dimmed(Finder finder) => find.ancestor(
  of: finder,
  matching: find.byWidgetPredicate(
    (w) => w is AnimatedOpacity && w.opacity == 0.45,
  ),
);

void main() {
  for (final tablet in [false, true]) {
    testWidgets('${tablet ? 'tablet' : 'phone'}: while the server is away, '
        'Now Playing dims and its controls send nothing', (tester) async {
      late _RecordingWsApi ws;
      final container = await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(3)),
        size: tablet ? const Size(1280, 800) : const Size(400, 800),
        overrides: [
          kalinkaWsApiProvider.overrideWith((ref) => ws = _RecordingWsApi(ref)),
        ],
      );
      if (!tablet) {
        await tester.tap(find.byType(MiniPlayer));
        await tester.pumpAndSettle();
      }
      final connection = container.read(
        connectionStateProvider.notifier,
      ) as SettableConnection;

      await tester.tap(_inPlayer(find.byIcon(Icons.skip_next_rounded)));
      await tester.pump();
      expect(ws.sent, [const QueueCommand.next()]);
      expect(_inPlayer(find.byType(GradientProgressLine)), findsNothing);

      for (final (status, mode) in const [
        (ConnectionStatus.reconnecting, GradientProgressLineMode.reconnecting),
        (ConnectionStatus.offline, GradientProgressLineMode.offline),
      ]) {
        connection.set(status);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(_dimmed(_inPlayer(find.text('Track t0'))), findsOneWidget);
        expect(
          _dimmed(_inPlayer(find.byType(ProceduralAlbumArt))),
          findsOneWidget,
        );
        expect(
          tester
              .widget<GradientProgressLine>(
                _inPlayer(find.byType(GradientProgressLine)),
              )
              .mode,
          mode,
        );

        await tester.tap(
          _inPlayer(find.byIcon(Icons.skip_next_rounded)),
          warnIfMissed: false,
        );
        await tester.tap(
          _inPlayer(find.byIcon(Icons.pause_rounded)),
          warnIfMissed: false,
        );
        await tester.drag(
          _inPlayer(find.byType(Slider)),
          const Offset(120, 0),
          warnIfMissed: false,
        );
        await tester.pump();
        expect(ws.sent, [const QueueCommand.next()]);
      }
    });
  }

  testWidgets('phone: while the server is away, Tab reaches no control that '
      'would send', (tester) async {
    late _RecordingWsApi ws;
    final container = await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(3)),
      overrides: [
        kalinkaWsApiProvider.overrideWith((ref) => ws = _RecordingWsApi(ref)),
      ],
    );
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    Finder transport(IconData icon) => find.ancestor(
      of: _inPlayer(find.byIcon(icon)),
      matching: find.byType(TransportButton),
    );

    expect(await tabTo(tester, transport(Icons.pause_rounded)), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(ws.sent, [const QueueCommand.pause(paused: true)]);

    (container.read(connectionStateProvider.notifier) as SettableConnection)
        .set(ConnectionStatus.reconnecting);
    await tester.pump();
    for (final control in [
      transport(Icons.pause_rounded),
      transport(Icons.skip_next_rounded),
      _inPlayer(find.byType(Slider)),
    ]) {
      expect(await tabTo(tester, control), isFalse);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(ws.sent, [const QueueCommand.pause(paused: true)]);
  });

  testWidgets('phone: with no server the player sheet closes and the '
      'mini-player goes', (tester) async {
    final container = await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(3)),
    );
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingContent), findsOneWidget);

    (container.read(connectionStateProvider.notifier) as SettableConnection)
        .set(ConnectionStatus.none);
    await tester.pumpAndSettle();

    expect(find.byType(NowPlayingContent), findsNothing);
    expect(find.byType(MiniPlayer), findsNothing);
    expect(find.text('No server connected'), findsOneWidget);
  });

  testWidgets('tablet: with no server the player panel says so', (
    tester,
  ) async {
    final container = await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(3)),
      size: const Size(1280, 800),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(PlayerViewSwitch),
        matching: find.text('QUEUE'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MiniPlayer), findsOneWidget);

    (container.read(connectionStateProvider.notifier) as SettableConnection)
        .set(ConnectionStatus.none);
    await tester.pumpAndSettle();

    expect(find.byType(NowPlayingContent), findsNothing);
    expect(find.byType(MiniPlayer), findsNothing);
    expect(find.text('No server connected'), findsNWidgets(2));
    expect(find.text('Scan for servers'), findsOneWidget);
  });
}
