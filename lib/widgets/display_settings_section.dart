import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/display_power_provider.dart';
import '../providers/display_settings_provider.dart';
import '../providers/kiosk_provider.dart';
import '../providers/on_screen_keyboard_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import 'dialog_scroll_scope.dart';
import 'settings_controls/settings_card.dart';
import 'settings_controls/settings_enum_pills.dart';
import 'settings_controls/settings_row.dart';

/// Preferences for the display on which Settings was opened.
class DisplaySettingsSection extends ConsumerWidget {
  const DisplaySettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeouts =
        ref.watch(kioskLaunchProvider) ||
        (ref.watch(localDisplayKioskProvider) &&
            ref.watch(
              settingsProvider.select(
                (s) => s.values['base_config.display.enabled'] == true,
              ),
            ));
    final settings = ref.watch(displaySettingsProvider);
    final notifier = ref.read(displaySettingsProvider.notifier);
    final power = timeouts ? ref.watch(displayPowerAvailableProvider) : null;
    final powerNote = switch (power) {
      AsyncData(value: true) => 'Backlight power-off supported.',
      AsyncData(value: false) || AsyncError() => 'Black screen only.',
      _ => 'Checking backlight…',
    };
    return SettingsCard(
      key: const ValueKey('display-settings'),
      children: [
        if (timeouts) ...[
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
            help: 'While paused or stopped.',
            status: powerNote,
            value: settings.blankSeconds,
            choices: const [0, 300, 600, 900, 1800],
            fieldKey: const ValueKey('display-blank-seconds'),
            onChanged: notifier.setBlankSeconds,
          ),
        ],
        const _TimeFormatRow(),
        _SwitchRow(
          label: 'Pixel shift',
          help: 'Shift Now Playing once a minute to reduce burn-in.',
          value: ref.watch(kioskPixelShiftProvider),
          onChanged: ref.read(kioskPixelShiftProvider.notifier).setEnabled,
        ),
        _SwitchRow(
          label: 'On-screen keyboard',
          help: 'Show a touch keyboard when typing.',
          switchKey: const ValueKey('on-screen-keyboard-setting'),
          value: ref.watch(onScreenKeyboardProvider),
          onChanged: ref.read(onScreenKeyboardProvider.notifier).setEnabled,
        ),
      ],
    );
  }
}

class _TimeFormatRow extends ConsumerWidget {
  static const _twelveHour = '12hr';
  static const _twentyFourHour = '24hr';

  const _TimeFormatRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final use24Hour =
        ref.watch(use24HourClockProvider) ??
        MediaQuery.alwaysUse24HourFormatOf(context);
    return LayoutBuilder(
      builder: (context, constraints) => SettingsRow(
        label: 'Time format',
        sublabel: 'For the Now Playing clock and other times.',
        // Beside the label only while the label keeps room to wrap by words.
        isVertical:
            constraints.maxWidth <
            300 * MediaQuery.textScalerOf(context).scale(1),
        // Equal segments as wide as the longer label, not the whole row.
        control: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: 1,
          child: IntrinsicWidth(
            child: SettingsEnumPills(
              key: const ValueKey('display-time-format'),
              options: const [_twelveHour, _twentyFourHour],
              selected: use24Hour ? _twentyFourHour : _twelveHour,
              onChanged: (choice) => unawaited(
                ref
                    .read(use24HourClockProvider.notifier)
                    .set(choice == _twentyFourHour),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String help;
  final Key? switchKey;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.label,
    required this.help,
    this.switchKey,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => SettingsRow(
    label: label,
    sublabel: help,
    control: Semantics(
      label: label,
      child: Switch(
        key: switchKey,
        value: value,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
  );
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
            child: DialogScrollScope(
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
                  constraints: const BoxConstraints(
                    minHeight: 48,
                    minWidth: 80,
                  ),
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
    ),
  );
}
