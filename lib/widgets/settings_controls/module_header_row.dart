import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'settings_toggle.dart';

/// Status of a module/device.
///
/// `warning` is used when the module is enabled and partially functional
/// — some non-required sub-feature has failed (e.g. an optional package
/// is missing). The badge tints amber/gold; the message goes on a
/// `WarningNote` inside the expanded module body.
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

  const ModuleStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.inline = false,
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
      final icon = switch (label) {
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

/// Rich header row for module/device cards with icon tile, status badge, and chevron.
class ModuleHeaderRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final ModuleStatus? status;
  final bool expanded;
  final VoidCallback onToggle;

  /// Whether there is anything to expand below the header. When false the
  /// chevron is hidden and the left zone no longer reacts to taps.
  final bool hasBody;

  /// Optional integrated enable/disable switch. When [enabled] is non-null
  /// the header grows a second tap zone on the right, separated by a thin
  /// vertical divider — same pattern as [SettingsToggleableSection].
  final bool? enabled;
  final ValueChanged<bool>? onEnabledChanged;

  const ModuleHeaderRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    this.status,
    required this.expanded,
    required this.onToggle,
    this.hasBody = true,
    this.enabled,
    this.onEnabledChanged,
  });

  /// Determine icon and color based on module name.
  static (IconData, Color) iconForModule(String moduleName) {
    final name = moduleName.toLowerCase();
    if (name.contains('local') || name.contains('file')) {
      return (Icons.folder_outlined, KalinkaColors.textSecondary);
    }
    if (name.contains('qobuz')) {
      return (Icons.music_note_outlined, KalinkaColors.gold);
    }
    if (name.contains('tidal')) {
      return (Icons.waves_outlined, const Color(0xFF4AC4D0));
    }
    if (name.contains('spotify')) {
      return (Icons.music_note_outlined, const Color(0xFF1DB954));
    }
    return (Icons.extension_outlined, KalinkaColors.textSecondary);
  }

  /// Determine icon and color for a device.
  static (IconData, Color) iconForDevice(String deviceName) {
    return (Icons.speaker_outlined, KalinkaColors.textSecondary);
  }

  @override
  Widget build(BuildContext context) {
    final showSwitch = enabled != null && onEnabledChanged != null;

    final expandInner = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          // Icon tile
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 15, color: iconColor),
          ),
          const SizedBox(width: 10),
          // Module info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: KalinkaTextStyles.trayRowLabel.copyWith(
                    fontSize: KalinkaTypography.baseSize + 5,
                    letterSpacing: -0.01,
                    // Muted when disabled, mirroring SettingsToggleableSection.
                    color: showSwitch && enabled == false
                        ? KalinkaColors.textSecondary
                        : KalinkaColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: KalinkaTextStyles.trayRowSublabel.copyWith(
                    fontSize: KalinkaTypography.baseSize + 2,
                  ),
                ),
              ],
            ),
          ),
          // Status badge
          if (status case final status? when status != ModuleStatus.disabled)
            Padding(
              padding: EdgeInsets.only(right: hasBody ? 10 : 0),
              child: ModuleStatusBadge.of(status),
            ),
          // Chevron — only shown when there's something to expand.
          if (hasBody)
            AnimatedRotation(
              turns: expanded ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 220),
              child: const Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: KalinkaColors.textMuted,
              ),
            ),
        ],
      ),
    );

    final expandZone = hasBody
        ? GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: expandInner,
          )
        : expandInner;

    if (!showSwitch) {
      return Container(
        decoration: const BoxDecoration(color: KalinkaColors.surfaceInput),
        child: expandZone,
      );
    }

    return Container(
      decoration: const BoxDecoration(color: KalinkaColors.surfaceInput),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: expandZone),
            const VerticalDivider(
              width: 1,
              thickness: 1,
              color: KalinkaColors.borderSubtle,
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onEnabledChanged!(!enabled!),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  widthFactor: 1.0,
                  child: SettingsToggle(
                    value: enabled!,
                    onChanged: onEnabledChanged!,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
