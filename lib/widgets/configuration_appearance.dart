import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Presentation changes for Configuration, leaving the comparison menu intact.
class ConfigurationAppearance extends InheritedWidget {
  const ConfigurationAppearance({super.key, required super.child});

  static bool active(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ConfigurationAppearance>() !=
      null;

  static double gutter(BuildContext context) =>
      MediaQuery.sizeOf(context).width < kKalinkaTabletBreakpoint ? 20 : 25;

  static EdgeInsets sectionPadding(BuildContext context) {
    final configured = active(context);
    final inset = configured ? gutter(context) : 20.0;
    return EdgeInsets.fromLTRB(inset, configured ? 20 : 28, inset, 10);
  }

  @override
  bool updateShouldNotify(ConfigurationAppearance oldWidget) => false;
}

class ChangedSettingLabel extends StatelessWidget {
  const ChangedSettingLabel({super.key});

  @override
  Widget build(BuildContext context) => Text(
    'Changed',
    style: KalinkaTextStyles.trayRowSublabel.copyWith(
      fontSize: KalinkaTypography.baseSize,
      color: KalinkaColors.statusPending,
    ),
  );
}

/// The same icon tile for every row on the Configuration overview.
class ConfigurationItemIcon extends StatelessWidget {
  final IconData icon;
  const ConfigurationItemIcon({super.key, required this.icon});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 32, color: KalinkaColors.textSecondary),
    ),
  );
}
