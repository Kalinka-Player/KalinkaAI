import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/power_off_status_provider.dart';
import 'package:kalinka/providers/supervisor_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Supervisor implements SupervisorApi {
  BoxPowerStatus? answer;
  Completer<void>? reply;
  int asked = 0;

  @override
  Future<BoxPowerStatus?> powerStatus() async {
    asked++;
    await reply?.future;
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Connection extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;

  void set(ConnectionStatus next) => state = next;
}

void main() {
  late DateTime now;
  late _Supervisor supervisor;
  late _Connection connection;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'Kalinka.name': 'Living room',
      'Kalinka.host': 'kalinka.local',
      'Kalinka.port': 8000,
    });
    final prefs = await SharedPreferences.getInstance();
    now = DateTime(2026, 11, 10, 23);
    supervisor = _Supervisor();
    connection = _Connection();
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        supervisorApiProvider.overrideWithValue(supervisor),
        connectionStateProvider.overrideWith(() => connection),
        scheduledPowerOffProvider.overrideWith(
          () => ScheduledPowerOffNotifier(now: () => now),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(connectionStateProvider);
  });

  ScheduledPowerOffNotifier timer() =>
      container.read(scheduledPowerOffProvider.notifier);

  Future<void> drop() async {
    connection.set(ConnectionStatus.reconnecting);
    await pumpEventQueue();
  }

  ConnectionStatus status() => container.read(connectionStateProvider);

  for (final answer in [
    null,
    const BoxPowerStatus(serverId: 'box-1', state: 'powering_off'),
  ]) {
    test(
      'a drop once the timer is due is the power-off, '
      '${answer == null ? 'with the box silent' : 'as the box says'}',
      () async {
        timer().schedule('box-1', 30);
        supervisor.answer = answer;
        now = now.add(const Duration(minutes: 30));

        await drop();
        expect(status(), ConnectionStatus.offline);
        expect(connection.boxPoweredOff, isTrue);
        expect(container.read(scheduledPowerOffProvider), isNull);
      },
    );
  }

  test('a drop a little early still counts', () async {
    timer().schedule('box-1', 30);
    now = now.add(const Duration(minutes: 30) - const Duration(seconds: 8));

    await drop();
    expect(connection.boxPoweredOff, isTrue);
  });

  test('a drop before the timer is due is an ordinary one', () async {
    timer().schedule('box-1', 30);
    now = now.add(const Duration(minutes: 29));

    await drop();
    expect(status(), ConnectionStatus.reconnecting);
    expect(connection.boxPoweredOff, isFalse);
    expect(supervisor.asked, 0);
  });

  for (final (name, answer) in [
    (
      'its timer was cancelled',
      const BoxPowerStatus(serverId: 'box-1', state: 'on'),
    ),
    (
      'it is still counting down',
      const BoxPowerStatus(
        serverId: 'box-1',
        state: 'scheduled',
        remainingSeconds: 600,
      ),
    ),
  ]) {
    test('a box that says $name dropped for another reason', () async {
      timer().schedule('box-1', 30);
      supervisor.answer = answer;
      now = now.add(const Duration(minutes: 30));

      await drop();
      expect(status(), ConnectionStatus.reconnecting);
      expect(connection.boxPoweredOff, isFalse);
      expect(
        container.read(scheduledPowerOffProvider),
        answer.state == 'on'
            ? isNull
            : (serverId: 'box-1', at: now.add(const Duration(minutes: 10))),
      );
    });
  }

  test('a cancelled timer is forgotten', () async {
    timer().schedule('box-1', 30);
    timer().cancel();
    now = now.add(const Duration(minutes: 30));

    await drop();
    expect(status(), ConnectionStatus.reconnecting);
    expect(supervisor.asked, 0);
  });

  test('a box seen on after its timer was due has spent it', () async {
    timer().schedule('box-1', 30);
    now = now.add(const Duration(minutes: 31));
    connection.set(ConnectionStatus.connecting);
    connection.set(ConnectionStatus.connected);
    expect(container.read(scheduledPowerOffProvider), isNull);

    await drop();
    expect(status(), ConnectionStatus.reconnecting);
  });

  test('a connection back before the box answers is left alone', () async {
    timer().schedule('box-1', 30);
    supervisor.reply = Completer<void>();
    now = now.add(const Duration(minutes: 30));
    await drop();
    expect(supervisor.asked, 1);

    connection.set(ConnectionStatus.connected);
    supervisor.reply!.complete();
    await pumpEventQueue();
    expect(status(), ConnectionStatus.connected);
    expect(connection.boxPoweredOff, isFalse);
  });

  test('a poll landing while the box is asked still counts', () async {
    timer().schedule('box-1', 30);
    supervisor.reply = Completer<void>();
    now = now.add(const Duration(minutes: 30));
    await drop();

    const off = BoxPowerStatus(serverId: 'box-1', state: 'powering_off');
    now = now.add(const Duration(seconds: 1));
    timer().follow(off);
    supervisor.answer = off;
    supervisor.reply!.complete();
    await pumpEventQueue();
    expect(status(), ConnectionStatus.offline);
    expect(connection.boxPoweredOff, isTrue);
  });

  test('follows what the box reports', () {
    timer().follow(
      const BoxPowerStatus(
        serverId: 'box-1',
        state: 'scheduled',
        remainingSeconds: 120,
      ),
    );
    expect(container.read(scheduledPowerOffProvider), (
      serverId: 'box-1',
      at: now.add(const Duration(minutes: 2)),
    ));
    timer().follow(
      const BoxPowerStatus(serverId: 'box-1', state: 'powering_off'),
    );
    expect(container.read(scheduledPowerOffProvider), (
      serverId: 'box-1',
      at: now,
    ));
    timer().follow(const BoxPowerStatus(serverId: 'box-1', state: 'on'));
    expect(container.read(scheduledPowerOffProvider), isNull);
  });

  test('a timer belongs to the server it was set on', () {
    timer().schedule('box-1', 30);
    container
        .read(connectionSettingsProvider.notifier)
        .setDeviceEphemeral('Kitchen', 'kitchen.local', 8000);
    expect(container.read(scheduledPowerOffProvider), isNull);
  });
}
