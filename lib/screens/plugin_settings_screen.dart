import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/plugin_catalog.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/plugin_catalog_entry.dart';
import '../widgets/plugin_page.dart';
import '../widgets/settings_controls/settings_binding.dart';
import '../widgets/settings_renderer.dart';

/// One installed plugin's configuration, opened from its row: its switch and
/// upkeep at the top, About at the top right, then the rows its card holds
/// in Server settings.
class PluginSettingsScreen extends ConsumerWidget {
  final CatalogPlugin plugin;
  final PluginEntryActions actions;
  final VoidCallback onClose;
  final bool handlesBack;

  const PluginSettingsScreen({
    super.key,
    required this.plugin,
    required this.actions,
    required this.onClose,
    this.handlesBack = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    return PluginPage(
      plugin: plugin,
      title: '${plugin.name} settings',
      description: plugin.description,
      id: 'settings',
      onClose: onClose,
      handlesBack: handlesBack,
      headerAction: IconButton(
        key: ValueKey('plugin-about-${plugin.id}'),
        tooltip: 'About ${plugin.name}',
        onPressed: actions.onOpenAbout,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        color: KalinkaColors.textSecondary,
        icon: const Icon(Icons.info_outline, size: 22),
      ),
      builder: (state, gutter) => [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: PluginControls(plugin: plugin, state: state, actions: actions),
        ),
        const SizedBox(height: 18),
        if (state.module case final module? when state.hasSettings)
          Container(
            margin: EdgeInsets.symmetric(horizontal: gutter),
            decoration: BoxDecoration(
              color: KalinkaColors.surfaceRaised,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: KalinkaColors.borderSubtle),
            ),
            clipBehavior: Clip.antiAlias,
            child: SettingsScope(
              binding: ServerSettingsBinding(settings, notifier),
              child: SchemaModuleBody(
                module: module,
                underHeader: false,
                showLiveMessage: false,
              ),
            ),
          )
        else
          Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: Text(
              'The server lists no other settings for this plugin.',
              style: KalinkaTextStyles.trayRowSublabel,
            ),
          ),
      ],
    );
  }
}
