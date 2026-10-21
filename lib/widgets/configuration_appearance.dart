import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared spacing for Configuration, logs and server/output settings. On a
/// wide panel the gutter grows, so the content keeps to
/// [kKalinkaContentMaxWidth], centred.
class ConfigurationAppearance extends StatelessWidget {
  final Widget child;

  const ConfigurationAppearance({super.key, required this.child});

  static _ConfigurationScope? _scope(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ConfigurationScope>();

  static bool active(BuildContext context) => _scope(context) != null;

  static double gutter(BuildContext context) {
    final base = MediaQuery.sizeOf(context).width < kKalinkaTabletBreakpoint
        ? 20.0
        : 25.0;
    final width = _scope(context)?.width ?? double.infinity;
    if (!width.isFinite) return base;
    return math.max(base, (width - kKalinkaContentMaxWidth) / 2);
  }

  /// A page-level side inset: the gutter on a settings page, 20 elsewhere.
  static double sideInset(BuildContext context) =>
      active(context) ? gutter(context) : 20;

  static EdgeInsets sectionPadding(BuildContext context) {
    final configured = active(context);
    final inset = sideInset(context);
    return EdgeInsets.fromLTRB(inset, configured ? 20 : 28, inset, 10);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _ConfigurationScope(width: constraints.maxWidth, child: child),
  );
}

class _ConfigurationScope extends InheritedWidget {
  /// The panel's width, which the gutter centres the content in.
  final double width;

  const _ConfigurationScope({required this.width, required super.child});

  @override
  bool updateShouldNotify(_ConfigurationScope oldWidget) =>
      oldWidget.width != width;
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
