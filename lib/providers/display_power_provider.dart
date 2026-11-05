import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/display_power.dart';
import '../utils/display_power_io.dart'
    if (dart.library.js_interop) '../utils/display_power_web.dart'
    as platform;

final displayPowerProvider = Provider<DisplayPower>((ref) {
  final power = platform.createDisplayPower();
  ref.onDispose(() => unawaited(power.setBlanked(false)));
  return power;
});

final displayPowerAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(displayPowerProvider).available,
);
