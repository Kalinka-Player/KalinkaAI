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
}) async {
  final container = ProviderContainer(
    overrides: [
      kioskActiveProvider.overrideWithValue(kiosk),
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

Future<void> _nativeKey(WidgetTester tester) async {
  final done = Completer<void>();
  // Simulate the native plugin's message, including its method-channel codec.
  tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'org.kalinka.kalinka/media_session',
    const StandardMethodCodec().encodeMethodCall(
      const MethodCall('volumeActivity'),
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
    'native keys show compact indicator, extend timeout, send no duplicate command',
    (tester) async {
      final container = await _pump(tester);
      expect(_opacity(tester), 0);
      await _nativeKey(tester);
      expect(_opacity(tester), 1);
      expect(
        tester.getSize(find.byType(KioskVolumeControl)).width,
        closeTo(54.72, 0.01),
      );
      expect(tester.getSize(find.byType(KioskVolumeControl)).height, 196);
      await tester.pump(const Duration(seconds: 2));
      await _nativeKey(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(_opacity(tester), 1);
      await tester.pump(const Duration(seconds: 1));
      expect(_opacity(tester), 0);
      expect((container.read(kalinkaWsApiProvider) as _Api).commands, isEmpty);
    },
  );

  testWidgets(
    'controller changes update indicator; background changes stay hidden',
    (tester) async {
      final container = await _pump(tester);
      final device =
          container.read(extDeviceStateStoreProvider.notifier) as _Device;
      device.emit(45);
      await tester.pump();
      expect(_opacity(tester), 1);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.bySemanticsLabel('Volume'), findsOneWidget);
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
