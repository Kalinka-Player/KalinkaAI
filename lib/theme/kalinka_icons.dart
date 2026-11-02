import 'package:flutter/widgets.dart';

/// Glyphs Material Icons lacks, from `assets/fonts/KalinkaIcons.ttf`, which
/// `scripts/build_icon_font.py` builds from the SVGs in `scripts/icons/`.
class KalinkaIcons {
  KalinkaIcons._();

  static const _family = 'KalinkaIcons';

  /// Material Design Icons' `usb-flash-drive`.
  static const usbFlashDrive = IconData(0xE000, fontFamily: _family);

  /// Material Symbols' `hard_drive`, outlined.
  static const hardDriveOutlined = IconData(0xE001, fontFamily: _family);
}
