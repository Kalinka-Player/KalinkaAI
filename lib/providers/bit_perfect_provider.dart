import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import 'app_state_provider.dart';

/// Whether what is playing reaches the device untouched.
///
/// Takes both halves because they arrive apart: the path settles when a stream
/// starts, the volume moves with the slider. Anything the renderer cannot
/// describe is a no — an unknown backend is not a claim that it is harmless —
/// and so is a signal path with any step that alters the samples, whatever
/// the lossless flag says.
bool isBitPerfect(OutputInfo? output, DeviceVolume volume) {
  if (output == null ||
      !output.losslessPath ||
      (output.signalPath?.steps.any((step) => !step.bitPerfect) ?? false)) {
    return false;
  }
  return switch (volume.backend) {
    VolumeBackend.hardware || VolumeBackend.none => true,
    VolumeBackend.software => volume.currentVolume >= volume.maxVolume,
    VolumeBackend.unknown => false,
  };
}

/// The two halves, each read off the bus it is current on.
///
/// The selectors are object-typed on purpose: what reaches a widget is the
/// bool, and Riverpod holds that still while the states behind it churn.
final bitPerfectProvider = Provider<bool>((ref) {
  final output = ref.watch(
    playerStateProvider.select((s) => s.audioInfo?.output),
  );
  final volume = ref.watch(extDeviceStateStoreProvider.select((s) => s.volume));
  return isBitPerfect(output, volume);
});
