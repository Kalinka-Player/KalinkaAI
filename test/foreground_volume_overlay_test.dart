import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/ext_device_events.dart';
import 'package:kalinka/data_model/kalinka_ws_api.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/kalinka_ws_api_provider.dart';
import 'package:kalinka/providers/kiosk_provider.dart';
import 'package:kalinka/widgets/foreground_volume_overlay.dart';
import 'package:kalinka/widgets/kiosk/kiosk_volume_control.dart';

ExtDeviceState _state(int value, {bool supported = true}) => ExtDeviceState(
  powerOn: true,
  volume: DeviceVolume(
    currentVolume: value,
    maxVolume: 100,
    volumeGain: 0,
    supported: supported,
  ),
  seq: value,
);

class _Device extends ExtDeviceStateStore {
  _Device(this.initial);
  final ExtDeviceState initial;
  @override
  ExtDeviceState build() => initial;
  void emit(int value) => state = _state(value);
}

class _Api extends KalinkaWsApi {
  _Api(super.ref);
  final commands = <DeviceCommand>[];
  @override
  Future<void> sendDeviceCommand(DeviceCommand command) async {
    commands.add(command);
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  bool kiosk = false,
  bool supported = true,
  PlayerStateType player = PlayerStateType.playing,
}) async {
  final container = ProviderContainer(
    overrides: [
      kioskActiveProvider.overrideWithValue(kiosk),
      playerStateProvider.overrideWithValue(PlaybackState(state: player)),
      extDeviceStateStoreProvider.overrideWith(
        () => _Device(_state(30, supported: supported)),
      ),
      kalinkaWsApiProvider.overrideWith((ref) => _Api(ref)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (_, child) => ForegroundVolumeOverlay(child: child!),
        home: const Scaffold(body: Center(child: Text('Player'))),
      ),
    ),
  );
  await tester.pump();
  return container;
}

Future<void> _nativeKey(WidgetTester tester, {int? level}) async {
  final done = Completer<void>();
  // Simulate the native plugin's message, including its method-channel codec.
  tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'org.kalinka.kalinka/media_session',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall(
        'volumeActivity',
        level == null ? null : {'level': level, 'max': 100},
      ),
    ),
    (_) => done.complete(),
  );
  await done.future;
  await tester.pump();
}

double _opacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(KioskVolumeControl),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

void main() {
  testWidgets(
    'native keys show the indicator, each press keeps it 2 s, no duplicate command',
    (tester) async {
      final container = await _pump(tester);
      expect(_opacity(tester), 0);
      await _nativeKey(tester);
      expect(_opacity(tester), 1);
      expect(
        tester.getSize(find.byType(KioskVolumeControl)).width,
        closeTo(76, 0.01),
      );
      expect(tester.getSize(find.byType(KioskVolumeControl)).height, 280);
      await tester.pump(const Duration(milliseconds: 1500));
      await _nativeKey(tester);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(_opacity(tester), 1);
      await tester.pump(const Duration(milliseconds: 500));
      expect(_opacity(tester), 0);
      expect((container.read(kalinkaWsApiProvider) as _Api).commands, isEmpty);
    },
  );

  testWidgets(
    'volume changes from elsewhere do not bring it up; only keys do',
    (tester) async {
      final container = await _pump(tester);
      final device =
          container.read(extDeviceStateStoreProvider.notifier) as _Device;
      device.emit(45);
      await tester.pump();
      expect(_opacity(tester), 0);
      await _nativeKey(tester);
      expect(_opacity(tester), 1);
      await tester.pump(const Duration(seconds: 2));
      expect(_opacity(tester), 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      device.emit(55);
      await tester.pump();
      expect(_opacity(tester), 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(_opacity(tester), 0);
      await _nativeKey(tester);
      expect(_opacity(tester), 1);
    },
  );

  testWidgets('overlay can adjust volume with the existing control', (
    tester,
  ) async {
    final container = await _pump(tester);
    await _nativeKey(tester);
    await tester.pump(const Duration(milliseconds: 400));
    final bar = find.descendant(
      of: find.byType(KioskVolumeControl),
      matching: find.byType(GestureDetector),
    );
    await tester.drag(bar, const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 100));
    final commands = (container.read(kalinkaWsApiProvider) as _Api).commands;
    expect(commands.last, isA<SetVolumeCommand>());
    expect((commands.last as SetVolumeCommand).volume, greaterThan(30));
  });

  testWidgets('a key press shows its level before the server echoes it', (
    tester,
  ) async {
    final container = await _pump(tester);
    final device =
        container.read(extDeviceStateStoreProvider.notifier) as _Device;
    String? shown() => tester
        .widget<Semantics>(
          find.descendant(
            of: find.byType(KioskVolumeControl),
            matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.label == 'Volume',
            ),
          ),
        )
        .properties
        .value;

    await _nativeKey(tester, level: 31);
    await _nativeKey(tester, level: 32);
    expect(shown(), '32%');
    // The first press's echo arrives late; the bar stays on the newest level.
    device.emit(29);
    await tester.pump(const Duration(milliseconds: 100));
    expect(shown(), '32%');
    device.emit(32);
    await tester.pump(const Duration(milliseconds: 350));
    device.emit(40);
    await tester.pump();
    expect(shown(), '40%');
  });

  testWidgets('without playback there is no volume to show', (tester) async {
    for (final player in [PlayerStateType.stopped, PlayerStateType.error]) {
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, player: player);
      await _nativeKey(tester, level: 40);
      expect(find.byType(AnimatedOpacity), findsNothing);
    }
  });

  testWidgets('fixed volume stays hidden', (tester) async {
    await _pump(tester, supported: false);
    await _nativeKey(tester);
    expect(find.byType(AnimatedOpacity), findsNothing);
  });

  testWidgets('kiosk retains its own indicator', (tester) async {
    await _pump(tester, kiosk: true);
    await _nativeKey(tester);
    expect(find.byType(KioskVolumeControl), findsNothing);
  });

  testWidgets(
    'other platforms retain their existing UI',
    (tester) async {
      await _pump(tester);
      expect(find.byType(KioskVolumeControl), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
