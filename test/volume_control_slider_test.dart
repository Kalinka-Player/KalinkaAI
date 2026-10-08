import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/ext_device_events.dart';
import 'package:kalinka/data_model/kalinka_ws_api.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/kalinka_ws_api_provider.dart';
import 'package:kalinka/widgets/volume_control_slider.dart';

import 'support/haptic_recorder.dart';

// ── Fakes ──────────────────────────────────────────────────────────────────────

class _SettableExtDeviceNotifier extends ExtDeviceStateStore {
  _SettableExtDeviceNotifier(this._initial);
  final ExtDeviceState _initial;

  @override
  ExtDeviceState build() => _initial;

  void emit(ExtDeviceState s) => state = s;
}

/// Subclass that overrides sendDeviceCommand to avoid real WebSocket usage.
class _FakeWsApi extends KalinkaWsApi {
  _FakeWsApi(super.ref);
  final List<DeviceCommand> sentCommands = [];

  @override
  Future<void> sendDeviceCommand(DeviceCommand command) async {
    sentCommands.add(command);
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

ExtDeviceState _deviceState({
  int currentVolume = 50,
  int maxVolume = 100,
  bool supported = true,
  int seq = 0,
}) => ExtDeviceState(
  powerOn: true,
  volume: DeviceVolume(
    currentVolume: currentVolume,
    maxVolume: maxVolume,
    volumeGain: 0,
    supported: supported,
  ),
  seq: seq,
);

/// Pumps [NowPlayingVolumeControl] in an isolated [ProviderContainer].
///
/// Returns the container so tests can push new state via
/// `container.read(extDeviceStateStoreProvider.notifier) as
///  _SettableExtDeviceNotifier`.
///
/// The [_FakeWsApi] instance is accessible after first user interaction via
/// `container.read(kalinkaWsApiProvider) as _FakeWsApi`.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  ExtDeviceState? initialState,
  PlayerStateType player = PlayerStateType.playing,
}) async {
  final state = initialState ?? _deviceState();

  final container = ProviderContainer(
    overrides: [
      extDeviceStateStoreProvider.overrideWith(
        () => _SettableExtDeviceNotifier(state),
      ),
      kalinkaWsApiProvider.overrideWith((ref) => _FakeWsApi(ref)),
      playerStateProvider.overrideWithValue(PlaybackState(state: player)),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 400, child: NowPlayingVolumeControl()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  return container;
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  group('NowPlayingVolumeControl', () {
    // ── Visibility ────────────────────────────────────────────────────────────

    testWidgets('hidden unless playback holds the renderer', (tester) async {
      for (final player in [PlayerStateType.stopped, PlayerStateType.error]) {
        await tester.pumpWidget(const SizedBox());
        await _pump(tester, player: player);
        expect(find.byType(Slider), findsNothing);
      }
      for (final player in [
        PlayerStateType.playing,
        PlayerStateType.buffering,
        PlayerStateType.paused,
      ]) {
        await tester.pumpWidget(const SizedBox());
        await _pump(tester, player: player);
        expect(find.byType(Slider), findsOneWidget);
      }
    });

    testWidgets('hidden when volume is not supported', (tester) async {
      await _pump(tester, initialState: _deviceState(supported: false));

      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('visible and at correct position when volume is supported', (
      tester,
    ) async {
      await _pump(
        tester,
        initialState: _deviceState(currentVolume: 30, maxVolume: 100),
      );

      expect(find.byType(Slider), findsOneWidget);
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, closeTo(0.30, 0.01));
    });

    // ── Mid-drag server echo must not reset the slider ────────────────────────

    testWidgets(
      'server echo during drag does not snap slider back to server value',
      (tester) async {
        // Arrange: server at 30 %, seq = 5.
        final container = await _pump(
          tester,
          initialState: _deviceState(currentVolume: 30, maxVolume: 100, seq: 5),
        );

        final sliderFinder = find.byType(Slider);

        // Act: start a drag gesture at the slider centre and move right.
        // The Slider fires onChanged on pointer-move, setting _isAdjustingVolume
        // = true and _localVolumeProgress to the new position.
        final gesture = await tester.startGesture(
          tester.getCenter(sliderFinder),
        );
        await gesture.moveBy(const Offset(100, 0));
        await tester.pump();

        final valueAfterDrag = tester.widget<Slider>(sliderFinder).value;
        // Sanity check: the drag moved the slider away from 30 %.
        expect(valueAfterDrag, isNot(closeTo(0.30, 0.05)));

        // A server event arrives mid-drag; the thumb must stay with the finger.
        (container.read(extDeviceStateStoreProvider.notifier)
                as _SettableExtDeviceNotifier)
            .emit(_deviceState(currentVolume: 30, maxVolume: 100, seq: 6));
        await tester.pump();

        // Assert: slider must still show the local drag position.
        final valueAfterEcho = tester.widget<Slider>(sliderFinder).value;
        expect(valueAfterEcho, closeTo(valueAfterDrag, 0.001));

        // Cleanup: let the post-release hold expire.
        await gesture.up();
        await tester.pump(const Duration(seconds: 5));
      },
    );

    // ── Settling after release ────────────────────────────────────────────────

    /// Drags from 30 % and releases; returns the sent level and the thumb's spot.
    Future<(_SettableExtDeviceNotifier, int, double)> dragAndRelease(
      WidgetTester tester,
    ) async {
      final container = await _pump(
        tester,
        initialState: _deviceState(currentVolume: 30, maxVolume: 100, seq: 5),
      );
      final sliderFinder = find.byType(Slider);
      final gesture = await tester.startGesture(tester.getCenter(sliderFinder));
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      final held = tester.widget<Slider>(sliderFinder).value;
      final target = (held * 100).round();
      final notifier =
          container.read(extDeviceStateStoreProvider.notifier)
              as _SettableExtDeviceNotifier;
      return (notifier, target, held);
    }

    double sliderValue(WidgetTester tester) =>
        tester.widget<Slider>(find.byType(Slider)).value;

    testWidgets('late echoes of the drag do not pull the slider back', (
      tester,
    ) async {
      final (device, target, held) = await dragAndRelease(tester);

      // A slow output replays the levels it was sent during the drag.
      for (var (i, level) in [40, 45, 50].indexed) {
        device.emit(_deviceState(currentVolume: level, seq: 6 + i));
        await tester.pump(const Duration(milliseconds: 100));
        expect(sliderValue(tester), closeTo(held, 0.001));
      }
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('releases once the target is reported and echoes go quiet', (
      tester,
    ) async {
      final (device, target, held) = await dragAndRelease(tester);

      device.emit(_deviceState(currentVolume: target, seq: 6));
      await tester.pump(const Duration(milliseconds: 350));

      // Back under server control: another client's change shows.
      device.emit(_deviceState(currentVolume: 20, seq: 7));
      await tester.pump();
      expect(sliderValue(tester), closeTo(0.20, 0.001));
    });

    testWidgets('a backlog echo after the target keeps holding', (
      tester,
    ) async {
      final (device, target, held) = await dragAndRelease(tester);

      device.emit(_deviceState(currentVolume: target, seq: 6));
      await tester.pump(const Duration(milliseconds: 100));
      device.emit(_deviceState(currentVolume: 40, seq: 7));
      await tester.pump(const Duration(milliseconds: 350));
      expect(sliderValue(tester), closeTo(held, 0.001));

      device.emit(_deviceState(currentVolume: target, seq: 8));
      await tester.pump(const Duration(milliseconds: 350));
      device.emit(_deviceState(currentVolume: 20, seq: 9));
      await tester.pump();
      expect(sliderValue(tester), closeTo(0.20, 0.001));
    });

    testWidgets('gives up when the target is never reported', (tester) async {
      await dragAndRelease(tester);

      await tester.pump(const Duration(seconds: 5));
      expect(sliderValue(tester), closeTo(0.30, 0.001));
    });

    // ── Haptics ───────────────────────────────────────────────────────────────

    testWidgets('a drag ticks every tenth and is silent otherwise', (
      tester,
    ) async {
      final haptics = HapticRecorder.install();
      await _pump(tester, initialState: _deviceState(currentVolume: 50));
      final slider = tester.widget<Slider>(find.byType(Slider));

      slider.onChanged!(0.50);
      slider.onChanged!(0.56);
      await tester.pump();
      expect(haptics.calls, isEmpty);

      slider.onChanged!(0.62);
      await tester.pump();
      expect(haptics.calls, ['selectionClick']);

      slider.onChangeEnd!(0.62);
      await tester.pump(const Duration(seconds: 5));
      expect(haptics.calls, ['selectionClick']);
    });

    // ── Commands ──────────────────────────────────────────────────────────────

    testWidgets('sends set_volume on every move of the drag', (tester) async {
      final container = await _pump(
        tester,
        initialState: _deviceState(currentVolume: 50, maxVolume: 100),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Slider)),
      );
      for (var i = 0; i < 3; i++) {
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump(const Duration(seconds: 5));

      // The provider is now initialised; cast is safe after interaction.
      final wsApi = container.read(kalinkaWsApiProvider) as _FakeWsApi;
      // Every move is sent as it happens, not held back until a pause.
      expect(wsApi.sentCommands.length, greaterThanOrEqualTo(3));
      expect(wsApi.sentCommands, everyElement(isA<SetVolumeCommand>()));
    });
  });
}
