import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/configuration_sections.dart';
import '../data_model/presentation_schema.dart';
import '../providers/connection_settings_provider.dart';
import '../providers/server_info_provider.dart';
import '../providers/server_update_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../theme/field_decoration.dart';
import '../widgets/box_section.dart';
import '../widgets/configuration_appearance.dart';
import '../widgets/kalinka_button.dart';
import '../widgets/kalinka_bottom_sheet.dart';
import '../widgets/server_update_banner.dart';
import '../widgets/settings_controls/settings_action_row.dart';
import '../widgets/settings_controls/settings_binding.dart';
import '../widgets/settings_controls/settings_card.dart';
import '../widgets/settings_controls/issue_notes.dart';
import '../widgets/settings_controls/settings_row.dart';
import '../widgets/settings_renderer.dart';

/// The Streamer tab keeps server information and management beside its settings.
class ServerSettingsBody extends ConsumerWidget {
  final VoidCallback onRestart;
  final VoidCallback onDownloadLogs;
  final VoidCallback onAdvanced;
  final VoidCallback? onNetwork;

  const ServerSettingsBody({
    super.key,
    required this.onRestart,
    required this.onDownloadLogs,
    required this.onAdvanced,
    this.onNetwork,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final sections = ConfigurationSections(settings.schema);
    final update = ref.watch(serverUpdateProvider).value;
    final showUpdate =
        update != null && (!update.updateAvailable || update.upgradeSupported);
    return SettingsScope(
      binding: ServerSettingsBinding(
        settings,
        ref.read(settingsProvider.notifier),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: ConfigurationAppearance.sectionPadding(context),
            child: Text('SERVER', style: KalinkaTextStyles.sectionHeaderMuted),
          ),
          _ServerSummary(
            nameField: settings.isLoading ? null : sections.serviceName,
            details: sections.details,
          ),
          if (settings.isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (settings.schema == null)
            Padding(
              padding: EdgeInsets.all(ConfigurationAppearance.gutter(context)),
              child: Column(
                children: [
                  Text(
                    'Could not load the player settings. Check that your player is connected and try again.',
                    style: KalinkaTextStyles.trayRowSublabel,
                  ),
                  const SizedBox(height: 12),
                  KalinkaButton(
                    label: 'Retry',
                    onTap: () =>
                        ref.read(settingsProvider.notifier).loadConfig(),
                  ),
                ],
              ),
            )
          else ...[
            for (final banner in sections.banners) SchemaBanner(banner: banner),
            for (final section in sections.server)
              SchemaSectionRenderer(
                section: section,
                isTopLevel: true,
                showServerUpdate: false,
              ),
          ],
          if (sections.updates.isNotEmpty || showUpdate) ...[
            Padding(
              padding: ConfigurationAppearance.sectionPadding(context),
              child: Text(
                'SOFTWARE UPDATES',
                style: KalinkaTextStyles.sectionHeaderMuted,
              ),
            ),
            SettingsCard(
              key: const ValueKey('server-software-updates'),
              children: [
                if (showUpdate) const ServerUpdateBanner(embedded: true),
                for (final field in sections.updates)
                  _AutomaticUpdates(field: field),
              ],
            ),
          ],
          BoxSection(
            title: 'MANAGEMENT',
            onNetwork: onNetwork,
            leadingActions: [
              SettingsActionRow(
                label: 'Restart Kalinka',
                sublabel:
                    'Restarts the player software. Music will stop briefly.',
                leading: Icons.restart_alt,
                trailing: null,
                onTap: onRestart,
              ),
            ],
          ),
          Padding(
            padding: ConfigurationAppearance.sectionPadding(context),
            child: Text('SUPPORT', style: KalinkaTextStyles.sectionHeaderMuted),
          ),
          SettingsCard(
            children: [
              SettingsActionRow(
                label: 'Download server logs',
                sublabel:
                    'An archive of recent logs to attach to a bug report.',
                leading: Icons.description_outlined,
                onTap: onDownloadLogs,
              ),
              SettingsActionRow(
                label: 'Advanced settings',
                sublabel: 'Find every setting by name.',
                leading: Icons.tune,
                onTap: onAdvanced,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ServerSummary extends ConsumerWidget {
  final FieldSpec? nameField;
  final List<FieldSpec> details;
  const _ServerSummary({required this.nameField, required this.details});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(connectionSettingsProvider);
    final info = ref.watch(serverInfoProvider);
    final binding = SettingsScope.of(context);
    return SettingsCard(
      key: const ValueKey('server-summary'),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ServerName(
              field: nameField,
              fallbackName:
                  connection.name == 'Unknown' || connection.name.isEmpty
                  ? 'Kalinka server'
                  : connection.name,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Server address',
                    style: KalinkaTextStyles.trayRowSublabel,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    connection.isSet
                        ? connection.baseUrl.toString()
                        : 'Not connected',
                    style: KalinkaTextStyles.trayRowLabel.copyWith(
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _ServerDetail(
                label: 'Server version',
                value:
                    info.value?.version ??
                    (info.isLoading ? 'Loading…' : 'Not available'),
              ),
              for (final field in details) ...[
                const SizedBox(height: 8),
                // The status itself stays visible, including failures. The
                // schema's explanatory prose remains in Advanced settings.
                _ServerDetail(
                  label: field.label,
                  value:
                      (binding.effectiveValue(field.path) ??
                              field.defaultValue ??
                              'Not available')
                          .toString(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ServerDetail extends StatelessWidget {
  final String label;
  final String value;
  const _ServerDetail({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final caption = Text(label, style: KalinkaTextStyles.trayRowSublabel);
    SelectableText text({TextAlign? align}) => SelectableText(
      value,
      textAlign: align,
      style: KalinkaTextStyles.trayRowSublabel.copyWith(
        color: KalinkaColors.textPrimary,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <
            280 * MediaQuery.textScalerOf(context).scale(1)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [caption, const SizedBox(height: 4), text()],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: caption),
            const SizedBox(width: 16),
            Expanded(child: text(align: TextAlign.end)),
          ],
        );
      },
    );
  }
}

class _AutomaticUpdates extends StatelessWidget {
  final FieldSpec field;
  const _AutomaticUpdates({required this.field});

  @override
  Widget build(BuildContext context) {
    if (field.readonly || field.widget != WidgetKind.toggle) {
      return SchemaFieldRenderer(field: field);
    }
    final binding = SettingsScope.of(context);
    return SettingsRow(
      label: 'Automatic updates',
      sublabel: 'Between 3–6 AM when idle. Restarts after updating.',
      isStaged: binding.isStaged(field.path),
      issues: binding.issuesFor(field.path),
      control: Semantics(
        label: 'Automatic updates',
        child: Switch(
          value:
              (binding.effectiveValue(field.path) ?? field.defaultValue) ==
              true,
          onChanged: (value) => binding.stage(field.path, value),
          activeTrackColor: KalinkaColors.accent,
          activeThumbColor: KalinkaColors.textPrimary,
          materialTapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
    );
  }
}

/// The pencil opens a local draft; only Done stages the new server name.
class _ServerName extends StatelessWidget {
  final FieldSpec? field;
  final String fallbackName;
  const _ServerName({required this.field, required this.fallbackName});

  @override
  Widget build(BuildContext context) {
    final binding = SettingsScope.of(context);
    final field = this.field;
    final value =
        (binding.effectiveValue(ConfigurationSections.namePath) ??
                field?.defaultValue ??
                fallbackName)
            .toString();
    final staged = binding.isStaged(ConfigurationSections.namePath);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: staged ? KalinkaColors.statusPendingSurface : null,
        border: Border(
          left: BorderSide(
            color: staged ? KalinkaColors.statusPending : Colors.transparent,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value.isEmpty ? 'Unnamed server' : value,
                      style: KalinkaFonts.display(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                        color: KalinkaColors.textPrimary,
                      ),
                    ),
                    if (staged) const ChangedSettingLabel(),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (field != null && !field.readonly)
                IconButton(
                  key: const ValueKey('server-name-edit'),
                  tooltip: 'Edit server name',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 20,
                    color: KalinkaColors.textSecondary,
                  ),
                  onPressed: () async {
                    final name = await showKalinkaBottomSheet<String>(
                      context: context,
                      contentBuilder: (_) =>
                          _ServerNameSheet(field: field, initialValue: value),
                    );
                    if (name == null || name == value || !context.mounted) {
                      return;
                    }
                    SettingsScope.of(context).stage(field.path, name);
                  },
                ),
            ],
          ),
          IssueNotes(issues: binding.issuesFor(ConfigurationSections.namePath)),
        ],
      ),
    );
  }
}

class _ServerNameSheet extends StatefulWidget {
  final FieldSpec field;
  final String initialValue;
  const _ServerNameSheet({required this.field, required this.initialValue});

  @override
  State<_ServerNameSheet> createState() => _ServerNameSheetState();
}

class _ServerNameSheetState extends State<_ServerNameSheet> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initialValue.length,
    );
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _name => _controller.text.trim();

  void _submit() {
    if (_name.isNotEmpty) Navigator.of(context).pop(_name);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('SERVER NAME', style: KalinkaTextStyles.sectionLabel),
            if (widget.field.help case final help?) ...[
              const SizedBox(height: 6),
              Text(help, style: KalinkaTextStyles.trayRowSublabel),
            ],
            const SizedBox(height: 20),
            TextField(
              key: const ValueKey('server-name-input'),
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              maxLength: widget.field.constraints?.maxLength,
              onSubmitted: (_) => _submit(),
              style: KalinkaTextStyles.textFieldInput,
              decoration: kalinkaFieldDecoration(hint: widget.field.label)
                  .copyWith(labelText: widget.field.label),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: KalinkaButton(
                    label: 'Cancel',
                    fullWidth: true,
                    variant: KalinkaButtonVariant.neutral,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: KalinkaButton(
                    label: 'Done',
                    fullWidth: true,
                    enabled: _name.isNotEmpty,
                    onTap: _submit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
