import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'box_control_provider.dart';
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
  Timer? refresh;
  ref.onDispose(() => refresh?.cancel());
  try {
    final status = await api.powerStatus();
    return status?.serverId == box.serverId ? status : null;
  } finally {
    if (ref.mounted) {
      refresh = Timer(const Duration(seconds: 5), ref.invalidateSelf);
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
