import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'box_control_provider.dart';
import 'supervisor_api.dart';

const boxPowerOffEnabledPath = 'base_config.server.box_power_off_enabled';
const boxPowerOffMinutesPath = 'base_config.server.box_power_off_minutes';
const boxPowerOffPaths = {boxPowerOffEnabledPath, boxPowerOffMinutesPath};

/// Only the connected server's supervisor may offer an inactivity shutdown.
final boxPowerOffTimerAvailableProvider = Provider<bool>((ref) {
  final box = ref.watch(boxControlProvider).value;
  return box != null &&
      box.offers(BoxAction.powerOff) &&
      box.info.supportsPowerOffTimer;
});
