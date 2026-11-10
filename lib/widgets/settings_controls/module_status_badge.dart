import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Status of a module/device.
///
/// `warning` is used when the module is enabled and partially functional
/// — some non-required sub-feature has failed (e.g. an optional package
/// is missing). The badge tints amber/gold.
enum ModuleStatus { ready, warning, error, disabled }

/// A module's state in a word, in its colour, as its settings card shows it.
class ModuleStatusBadge extends StatelessWidget {
  static final style = KalinkaTextStyles.tagPill.copyWith(
    fontSize: KalinkaTypography.baseSize,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
  );

  /// Padding and border either side of the label.
  static const inset = 18.0;

  final String label;
  final Color color;

  /// Quiet text and an icon for a plugin identity, rather than a boxed tag.
  final bool inline;

  /// The glyph before an [inline] label, where the one its word names would
  /// not do.
  final IconData? icon;

  const ModuleStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.inline = false,
    this.icon,
  });

  /// The word and colour for [status].
  ModuleStatusBadge.of(ModuleStatus status, {Key? key, bool inline = false})
    : this(
        key: key,
        inline: inline,
        label: switch (status) {
          ModuleStatus.ready => 'READY',
          ModuleStatus.warning => 'WARNING',
          ModuleStatus.error => 'ERROR',
          ModuleStatus.disabled => 'DISABLED',
        },
        color: switch (status) {
          ModuleStatus.ready => KalinkaColors.statusOnline,
          ModuleStatus.warning => KalinkaColors.statusPending,
          ModuleStatus.error => KalinkaColors.statusError,
          ModuleStatus.disabled => KalinkaColors.textMuted,
        },
      );

  @override
  Widget build(BuildContext context) {
    if (inline) {
      final textColor = switch (color) {
        KalinkaColors.statusOnline => KalinkaColors.statusOnlineLight,
        KalinkaColors.statusPending => KalinkaColors.statusPendingLight,
        KalinkaColors.textMuted => KalinkaColors.textSecondary,
        _ => color,
      };
      final icon =
          this.icon ??
          switch (label) {
            'READY' => Icons.check_circle_outline,
            'ERROR' => Icons.error_outline,
            'WARNING' => Icons.warning_amber_rounded,
            'DISABLED' => Icons.pause_circle_outline,
            'INSTALLING' || 'UPDATING' || 'UNINSTALLING' => Icons.sync,
            _ => Icons.radio_button_unchecked,
          };
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(child: Icon(icon, size: 16, color: textColor)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label.isEmpty
                  ? label
                  : label[0] + label.substring(1).toLowerCase(),
              style: KalinkaTextStyles.trayRowSublabel.copyWith(
                color: textColor,
                height: 1.4,
              ),
            ),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: style.copyWith(
          color: color == KalinkaColors.statusOnline
              ? KalinkaColors.statusOnlineLight
              : color,
        ),
      ),
    );
  }
}
