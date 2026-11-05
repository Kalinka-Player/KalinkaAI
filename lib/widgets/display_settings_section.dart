import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/display_power_provider.dart';
import '../providers/display_settings_provider.dart';
import '../providers/kiosk_provider.dart';
import '../theme/app_theme.dart';
import 'configuration_appearance.dart';
import 'settings_controls/settings_card.dart';
import 'settings_controls/settings_row.dart';

/// These values belong to the local screen, so a remote client must not offer
/// controls that would only change its own, unrelated SharedPreferences.
/// An explicit kiosk launch also allows editing for display testing.
class DisplaySettingsSection extends ConsumerWidget {
  const DisplaySettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local =
        ref.watch(localDisplayKioskProvider) || ref.watch(kioskLaunchProvider);
    final settings = ref.watch(displaySettingsProvider);
    final notifier = ref.read(displaySettingsProvider.notifier);
    final power = local ? ref.watch(displayPowerAvailableProvider) : null;
    final powerNote = switch (power) {
      AsyncData(value: true) => 'Backlight power-off supported.',
      AsyncData(value: false) || AsyncError() => 'Black screen only.',
      _ => 'Checking backlight…',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: ConfigurationAppearance.sectionPadding(context),
          child: Text('DISPLAY', style: KalinkaTextStyles.sectionHeaderMuted),
        ),
        SettingsCard(
          key: const ValueKey('display-settings'),
          children: [
            if (!local)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Set the display timeouts on the streamer’s screen. '
                  'They are saved on that device.',
                  style: KalinkaTextStyles.trayRowSublabel,
                ),
              )
            else ...[
              _TimeoutRow(
                label: 'Return to now playing',
                help: 'After inactivity.',
                value: settings.kioskSeconds,
                choices: const [15, 30, 60, 120],
                fieldKey: const ValueKey('display-kiosk-seconds'),
                onChanged: notifier.setKioskSeconds,
              ),
              _TimeoutRow(
                label: 'Blank screen after',
                help: 'When idle and paused or stopped.',
                status: powerNote,
                value: settings.blankSeconds,
                choices: const [0, 300, 600, 900, 1800],
                fieldKey: const ValueKey('display-blank-seconds'),
                onChanged: notifier.setBlankSeconds,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _TimeoutRow extends StatelessWidget {
  final String label;
  final String help;
  final String? status;
  final int value;
  final List<int> choices;
  final Key fieldKey;
  final Future<void> Function(int) onChanged;

  const _TimeoutRow({
    required this.label,
    required this.help,
    this.status,
    required this.value,
    required this.choices,
    required this.fieldKey,
    required this.onChanged,
  });

  String _durationLabel(int seconds) {
    if (seconds == 0) return 'Off';
    if (seconds % 60 == 0) return '${seconds ~/ 60} min';
    return '$seconds s';
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SettingsRow(
      label: label,
      sublabel: help,
      status: status,
      control: ConstrainedBox(
        // Reserve space for the label even with large text or a saved custom
        // duration. The value may wrap inside the control on narrow screens.
        constraints: BoxConstraints(
          maxWidth: (constraints.maxWidth - 2 * kSettingsGutter - 12) * 0.6,
        ),
        child: Semantics(
          label: label,
          button: true,
          child: Material(
            color: KalinkaColors.surfaceElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: KalinkaColors.borderDefault),
            ),
            clipBehavior: Clip.antiAlias,
            child: PopupMenuButton<int>(
              key: fieldKey,
              tooltip: label,
              initialValue: value,
              position: PopupMenuPosition.under,
              constraints: const BoxConstraints(minWidth: 168, maxWidth: 280),
              color: KalinkaColors.surfaceRaised,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: KalinkaColors.borderDefault),
              ),
              onSelected: (seconds) => unawaited(onChanged(seconds)),
              itemBuilder: (_) => [
                for (final seconds in choices)
                  PopupMenuItem<int>(
                    value: seconds,
                    child: Semantics(
                      selected: seconds == value,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _durationLabel(seconds),
                              style: KalinkaTextStyles.trayRowLabel,
                            ),
                          ),
                          if (seconds == value) ...[
                            const SizedBox(width: 12),
                            const Icon(
                              Icons.check,
                              size: 18,
                              color: KalinkaColors.textSecondary,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 80),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _durationLabel(value),
                          style: KalinkaTextStyles.trayRowLabel,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.keyboard_arrow_down,
                        size: 18,
                        color: KalinkaColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
