import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/box_control_provider.dart';
import 'package:kalinka/providers/power_off_status_provider.dart';
import 'package:kalinka/providers/supervisor_api.dart';

const _box = BoxControl(
  SupervisorInfo(
    version: '0.3.0',
    protocol: 1,
    minProtocol: 1,
    serverId: 'box-1',
    actions: {'poweroff'},
    supportsPowerOffSchedule: true,
  ),
  'box-1',
);

const _status = BoxPowerStatus(serverId: 'box-1', state: 'on');

class _Api implements SupervisorApi {
  final requests = <Completer<BoxPowerStatus?>>[];

  @override
  Future<BoxPowerStatus?> powerStatus() {
    final request = Completer<BoxPowerStatus?>();
    requests.add(request);
    return request.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

ProviderContainer _container(_Api api) => ProviderContainer(
  overrides: [
    boxControlProvider.overrideWith((ref) => _box),
    supervisorApiProvider.overrideWithValue(api),
  ],
  retry: (_, _) => null,
);

void main() {
  test('polls every five seconds and cancels polling on disposal', () {
    fakeAsync((clock) {
      final api = _Api();
      final container = _container(api);
      container.listen(currentPowerOffStatusProvider, (_, _) {});
      clock.flushMicrotasks();
      expect(api.requests, hasLength(1));

      api.requests.single.complete(_status);
      clock.flushMicrotasks();
      expect(container.read(currentPowerOffStatusProvider), _status);
      clock.elapse(const Duration(seconds: 4));
      expect(api.requests, hasLength(1));
      clock.elapse(const Duration(seconds: 1));
      expect(api.requests, hasLength(2));
      api.requests.last.complete(_status);
      clock.flushMicrotasks();

      container.dispose();
      clock.elapse(const Duration(seconds: 10));
      expect(api.requests, hasLength(2));
      expect(clock.pendingTimers, isEmpty);
    });
  });

  for (final fails in [false, true]) {
    test(
      'late ${fails ? 'failure' : 'response'} after invalidation cannot start a stale timer',
      () {
        fakeAsync((clock) {
          final api = _Api();
          final container = _container(api);
          container.listen(currentPowerOffStatusProvider, (_, _) {});
          clock.flushMicrotasks();
          expect(api.requests, hasLength(1));

          // Disposal runs immediately, but the replacement build waits for the
          // next event-loop turn. Complete the old request in that gap.
          container.invalidate(powerOffStatusProvider);
          if (fails) {
            api.requests.first.completeError(StateError('Server restarting'));
          } else {
            api.requests.first.complete(_status);
          }
          clock.flushMicrotasks();
          clock.elapse(Duration.zero);
          expect(api.requests, hasLength(2));

          const replacement = BoxPowerStatus(
            serverId: 'box-1',
            state: 'scheduled',
            remainingSeconds: 600,
          );
          api.requests.last.complete(replacement);
          clock.flushMicrotasks();
          expect(container.read(currentPowerOffStatusProvider), replacement);

          // Only the replacement build may poll. The old timer used to throw
          // here when it called invalidateSelf on the disposed Ref.
          clock.elapse(const Duration(seconds: 5));
          expect(api.requests, hasLength(3));
          expect(container.read(currentPowerOffStatusProvider), replacement);
          container.dispose();
          api.requests.last.complete(_status);
          clock.flushMicrotasks();
          clock.elapse(const Duration(seconds: 10));
          expect(clock.pendingTimers, isEmpty);
        });
      },
    );

    test(
      'late ${fails ? 'failure' : 'response'} after closing settings leaves no timer',
      () {
        fakeAsync((clock) {
          final api = _Api();
          final container = _container(api);
          final subscription = container.listen(
            currentPowerOffStatusProvider,
            (_, _) {},
          );
          clock.flushMicrotasks();
          expect(api.requests, hasLength(1));
          subscription.close();
          clock.elapse(Duration.zero);
          expect(container.read(powerOffStatusProvider.exists), isFalse);

          if (fails) {
            api.requests.single.completeError(StateError('Server restarting'));
          } else {
            api.requests.single.complete(_status);
          }
          clock.flushMicrotasks();
          clock.elapse(const Duration(seconds: 10));
          expect(api.requests, hasLength(1));
          expect(clock.pendingTimers, isEmpty);
          container.dispose();
        });
      },
    );
  }
}
