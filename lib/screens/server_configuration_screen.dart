import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/configuration_sections.dart';
import '../data_model/presentation_schema.dart';
import '../providers/settings_provider.dart';
import '../providers/connection_settings_provider.dart';
import '../providers/server_info_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/box_section.dart';
import '../widgets/expert_settings_screen.dart';
import '../widgets/configuration_page.dart';
import '../widgets/settings_controls/settings_action_row.dart';
import '../widgets/settings_controls/settings_binding.dart';
import '../widgets/settings_controls/settings_card.dart';
import '../widgets/settings_renderer.dart';
import '../widgets/configuration_appearance.dart';
import '../widgets/server_update_banner.dart';
import '../providers/server_update_provider.dart';
import 'log_export_screen.dart';
import 'configuration_review_screen.dart' show configurationFields;

enum ServerSettingsGroup {
  maintenance(
    'Maintenance',
    'Restart Kalinka, get help or manage your streamer.',
    Icons.build_outlined,
  );

  final String title;
  final String description;
  final IconData icon;
  const ServerSettingsGroup(this.title, this.description, this.icon);
}

class ServerSettingsBody extends ConsumerWidget {
  const ServerSettingsBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final sections = ConfigurationSections(settings.schema);
    final update = ref.watch(serverUpdateProvider).value;
    return SettingsScope(
      binding: ServerSettingsBinding(
        settings,
        ref.read(settingsProvider.notifier),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final banner in sections.banners) SchemaBanner(banner: banner),
          for (final section in sections.server)
            SchemaSectionRenderer(
              section: section,
              isTopLevel: true,
              showServerUpdate: false,
            ),
          if (sections.playback.isNotEmpty)
            SchemaSectionRenderer(
              section: SectionSpec(
                id: 'configuration.playback',
                title: 'Playback',
                fields: sections.playback,
              ),
              isTopLevel: true,
            ),
          if (sections.updates.isNotEmpty ||
              (update != null &&
                  (!update.updateAvailable || update.upgradeSupported))) ...[
            Padding(
              padding: ConfigurationAppearance.sectionPadding(context),
              child: Text(
                'SOFTWARE UPDATES',
                style: KalinkaTextStyles.sectionHeaderMuted,
              ),
            ),
            const ServerUpdateBanner(),
            if (sections.updates.isNotEmpty)
              SettingsCard(
                children: [
                  for (final field in sections.updates)
                    SchemaFieldRenderer(field: field),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class ServerConfigurationScreen extends ConsumerStatefulWidget {
  final ServerSettingsGroup group;
  final VoidCallback onClose;
  final VoidCallback onRestart;
  final bool handlesBack;

  const ServerConfigurationScreen({
    super.key,
    required this.group,
    required this.onClose,
    required this.onRestart,
    this.handlesBack = true,
  });

  @override
  ConsumerState<ServerConfigurationScreen> createState() =>
      _ServerConfigurationScreenState();
}

class _ServerConfigurationScreenState
    extends ConsumerState<ServerConfigurationScreen> {
  bool _expert = false;
  bool _logs = false;
  bool _details = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final group = widget.group;
    return ConfigurationPage(
      parent: 'Streamer',
      title: group.title,
      description: group.description,
      icon: group.icon,
      onClose: widget.onClose,
      handlesBack: widget.handlesBack && !_expert && !_logs && !_details,
      overlays: [
        if (_expert)
          ConfigurationPage(
            key: const ValueKey('server-expert'),
            parent: 'Maintenance',
            title: 'Advanced settings',
            description:
                'All player settings. Search for the setting you need.',
            icon: Icons.tune,
            onClose: () => setState(() => _expert = false),
            handlesBack: widget.handlesBack,
            bodyBuilder: (heading) => ExpertSettingsScreen(heading: heading),
          ),
        if (_details)
          _SystemDetails(
            key: const ValueKey('server-system-details'),
            onClose: () => setState(() => _details = false),
            handlesBack: widget.handlesBack,
          ),
        if (_logs)
          LogExportScreen(
            key: const ValueKey('server-logs'),
            onClose: () => setState(() => _logs = false),
            handlesBack: widget.handlesBack,
          ),
      ],
      bodyBuilder: (heading) => SettingsScope(
        binding: ServerSettingsBinding(
          settings,
          ref.read(settingsProvider.notifier),
        ),
        child: ListView(
          key: ValueKey('server-group-${group.name}-settings'),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            heading,
            if (group == ServerSettingsGroup.maintenance) ...[
              SettingsCard(
                children: [
                  SettingsActionRow(
                    label: 'Restart Kalinka',
                    sublabel: 'Restarts the player software. Music will stop briefly.',
                    leading: Icons.restart_alt,
                    trailing: null,
                    onTap: widget.onRestart,
                  ),
                  SettingsActionRow(
                    label: 'System details',
                    sublabel: 'Player address, software version and service information.',
                    leading: Icons.info_outline,
                    onTap: () => setState(() => _details = true),
                  ),
                  SettingsActionRow(
                    label: 'Download server logs',
                    sublabel:
                        'An archive of recent logs to attach to a bug report.',
                    leading: Icons.description_outlined,
                    onTap: () => setState(() => _logs = true),
                  ),
                  SettingsActionRow(
                    label: 'Advanced settings',
                    sublabel: 'Find every setting by name.',
                    leading: Icons.tune,
                    onTap: () => setState(() => _expert = true),
                  ),
                ],
              ),
              const BoxSection(),
            ],
          ],
        ),
      ),
    );
  }
}

class _SystemDetails extends ConsumerWidget {
  final VoidCallback onClose;
  final bool handlesBack;
  const _SystemDetails({
    super.key,
    required this.onClose,
    required this.handlesBack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(connectionSettingsProvider);
    final version = ref.watch(serverInfoProvider).value?.version;
    final settings = ref.watch(settingsProvider);
    final supervisor = configurationFields(settings.schema)
        .where((f) => f.path == 'base_config.server.supervisor_status')
        .firstOrNull;
    return ConfigurationPage(
      title: 'System details',
      description: 'Information about your player, useful when getting help.',
      icon: Icons.info_outline,
      parent: 'Maintenance',
      onClose: onClose,
      handlesBack: handlesBack,
      bodyBuilder: (heading) => SettingsScope(
        binding: ServerSettingsBinding(
          settings,
          ref.read(settingsProvider.notifier),
        ),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            heading,
            SettingsCard(
              children: [
                for (final detail in [
                  ('Player address', '${connection.host}:${connection.port}'),
                  ('Software version', version ?? 'Not available'),
                ])
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(detail.$1, style: KalinkaTextStyles.trayRowLabel),
                        const SizedBox(height: 6),
                        SelectableText(
                          detail.$2,
                          style: KalinkaTextStyles.trayRowSublabel,
                        ),
                      ],
                    ),
                  ),
                if (supervisor != null) SchemaFieldRenderer(field: supervisor),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
