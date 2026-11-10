import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/on_screen_keyboard_provider.dart';
import '../theme/app_theme.dart';
import 'configuration_appearance.dart';
import 'settings_controls/settings_card.dart';
import 'settings_controls/settings_row.dart';

class ClientSettingsSection extends ConsumerWidget {
  const ClientSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: ConfigurationAppearance.sectionPadding(context),
        child: Text('THIS DEVICE', style: KalinkaTextStyles.sectionHeaderMuted),
      ),
      SettingsCard(
        children: [
          SettingsRow(
            label: 'On-screen keyboard',
            sublabel:
                'Show a touch keyboard when editing text. '
                'Saved on this device only; takes effect immediately.',
            control: Semantics(
              label: 'On-screen keyboard',
              child: Switch(
                key: const ValueKey('on-screen-keyboard-setting'),
                value: ref.watch(onScreenKeyboardProvider),
                onChanged: (value) => unawaited(
                  ref.read(onScreenKeyboardProvider.notifier).setEnabled(value),
                ),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
            ),
          ),
        ],
      ),
    ],
  );
}
