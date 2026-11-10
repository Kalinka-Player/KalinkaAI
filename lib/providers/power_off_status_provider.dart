import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'box_control_provider.dart';
import 'connection_settings_provider.dart';
import 'connection_state_provider.dart';
import 'supervisor_api.dart';

/// Poll even without a timer: another client may schedule or cancel it.
/// A new connection drops the old server's countdown immediately.
final powerOffStatusProvider = FutureProvider.autoDispose<BoxPowerStatus?>((
  ref,
) async {
  final box = ref.watch(boxControlProvider).value;
  final api = ref.watch(supervisorApiProvider);
  if (box == null ||
      api == null ||
      !box.info.supportsPowerOffSchedule ||
      !box.offers(BoxAction.powerOff)) {
    return null;
  }
  // Invalidation runs disposal callbacks before the old Ref stops reporting
  // mounted. A response in that gap must not create a timer after cleanup.
  var current = true;
  Timer? refresh;
  ref.onDispose(() {
    current = false;
    refresh?.cancel();
  });
  try {
    final status = await api.powerStatus();
    if (status?.serverId != box.serverId) return null;
    if (current && ref.mounted) {
      ref.read(scheduledPowerOffProvider.notifier).follow(status!);
    }
    return status;
  } finally {
    if (current && ref.mounted) {
      refresh = Timer(const Duration(seconds: 5), () {
        if (current && ref.mounted) ref.invalidateSelf();
      });
    }
  }
});

/// Keep the last reading while polling, but never across a server change.
final currentPowerOffStatusProvider = Provider.autoDispose<BoxPowerStatus?>((
  ref,
) {
  final status = ref.watch(powerOffStatusProvider);
  if (status.isLoading && !status.isRefreshing) return null;
  final box = ref.watch(boxControlProvider).value;
  return box?.info.supportsPowerOffSchedule == true &&
          status.value?.serverId == box?.serverId
      ? status.value
      : null;
});

/// When the connected server's box powers off on its timer.
typedef PowerOffDue = ({String serverId, DateTime at});

final scheduledPowerOffProvider =
    NotifierProvider<ScheduledPowerOffNotifier, PowerOffDue?>(
      ScheduledPowerOffNotifier.new,
    );

/// Remembers the box's power-off timer, as set or last read here, so the
/// connection dropping once it is due is taken for the box powering off.
class ScheduledPowerOffNotifier extends Notifier<PowerOffDue?> {
  ScheduledPowerOffNotifier({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// The countdown is rounded up to the second, and polled every 5 seconds.
  static const _early = Duration(seconds: 10);

  @override
  PowerOffDue? build() {
    ref.watch(connectionSettingsProvider.select((s) => s.address));
    ref.listen<ConnectionStatus>(connectionStateProvider, (previous, next) {
      if (previous == ConnectionStatus.connected &&
          next == ConnectionStatus.reconnecting) {
        _checkDrop();
      } else if (next == ConnectionStatus.connected && previous != next) {
        // The box is on after the timer was due, so it did not fire.
        if (state case final due? when !_now().isBefore(due.at)) state = null;
      }
    });
    return null;
  }

  void schedule(String serverId, int minutes) =>
      state = (serverId: serverId, at: _now().add(Duration(minutes: minutes)));

  void cancel() => state = null;

  /// Follows what the box's supervisor reported.
  void follow(BoxPowerStatus status) {
    state = switch (status) {
      BoxPowerStatus(state: 'scheduled', :final remainingSeconds?) => (
        serverId: status.serverId,
        at: _now().add(Duration(seconds: remainingSeconds)),
      ),
      BoxPowerStatus(state: 'powering_off') => (
        serverId: status.serverId,
        at: _now(),
      ),
      _ => null,
    };
  }

  Future<void> _checkDrop() async {
    final due = state;
    if (due == null || _now().isBefore(due.at.subtract(_early))) return;
    // The supervisor may outlive the server for a moment while the box
    // shuts down. Silence is a box already off.
    final status = await ref.read(supervisorApiProvider)?.powerStatus();
    // A poll meanwhile re-reads the same timer with a new `at`; only a cancel
    // or a server change calls this off.
    if (!ref.mounted || state?.serverId != due.serverId) return;
    if (status != null &&
        status.serverId == due.serverId &&
        status.state != 'powering_off') {
      follow(status);
      return;
    }
    if (!ref.read(connectionStateProvider).isInterrupted) return;
    state = null;
    ref.read(connectionStateProvider.notifier).poweredOff();
  }
}
