import 'dart:io';

import 'display_power.dart';

DisplayPower createDisplayPower() {
  // Only the packaged flutter-pi launcher supplies this path, after granting
  // its service access. A desktop test launch must never power off the laptop.
  final path = Platform.environment['KALINKA_DISPLAY_BACKLIGHT'];
  if (!Platform.isLinux || path == null || path.isEmpty) {
    return const NoDisplayPower();
  }
  return BacklightDisplayPower(File(path));
}

/// Linux's documented backlight ABI: 4 powers down, 0 turns on. Read and save
/// the original value so wake and teardown restore the previous power mode.
class BacklightDisplayPower implements DisplayPower {
  final File control;
  Future<bool> _operation = Future.value(true);
  String? _restorePower;
  bool _poweredDown = false;

  BacklightDisplayPower(this.control);

  @override
  Future<bool> get available async {
    try {
      final value = (await control.readAsString()).trim();
      if (int.tryParse(value) case final power? when power >= 0 && power <= 4) {
        // Opening for append checks write permission without changing the
        // hardware or truncating the attribute while checking capability.
        final handle = await control.open(mode: FileMode.append);
        await handle.close();
        return true;
      }
    } on FileSystemException {
      // Not every panel exposes a backlight, and permissions can change.
    }
    return false;
  }

  @override
  Future<bool> setBlanked(bool blanked) {
    // A quick wake must finish after an in-flight power-off write.
    return _operation = _operation.then((_) async {
      try {
        if (blanked) {
          if (_poweredDown) return true;
          if (!await available) return false;
          final previous = (await control.readAsString()).trim();
          _restorePower ??= previous;
          await control.writeAsString('4');
          _poweredDown = (await control.readAsString()).trim() == '4';
          return _poweredDown;
        } else if (_restorePower case final previous?) {
          await control.writeAsString(previous);
          _restorePower = null;
          _poweredDown = false;
        }
        return true;
      } on FileSystemException {
        // Keep the saved value after a failed restore so a later wake or
        // disposal can retry. Black-screen blanking remains available.
        return false;
      }
    });
  }
}
