import 'package:flutter/material.dart';

import '../data_model/plugin_catalog.dart';
import '../widgets/plugin_catalog_entry.dart';
import '../widgets/plugin_page.dart';

/// Everything the catalog says about one plugin, opened from its row or from
/// its configuration page: what it does, who made it, what it needs, with
/// Install or Uninstall at the top right and Update at the foot.
class PluginAboutScreen extends StatelessWidget {
  final CatalogPlugin plugin;
  final PluginEntryActions actions;
  final VoidCallback onClose;

  /// Puts away the configuration page under this one, where there is one,
  /// as the trail goes back to the overview.
  final VoidCallback? onHome;
  final bool handlesBack;

  const PluginAboutScreen({
    super.key,
    required this.plugin,
    required this.actions,
    required this.onClose,
    this.onHome,
    this.handlesBack = true,
  });

  @override
  Widget build(BuildContext context) => PluginPage(
    plugin: plugin,
    title: 'About ${plugin.name}',
    id: 'about',
    onClose: onClose,
    onHome: onHome,
    handlesBack: handlesBack,
    trailing: (state) => pluginAboutAction(plugin, state, actions),
    builder: (state, gutter) => [
      Padding(
        padding: EdgeInsets.symmetric(horizontal: gutter),
        child: PluginAbout(
          key: ValueKey('plugin-details-${plugin.id}'),
          plugin: plugin,
          state: state,
          actions: actions,
        ),
      ),
    ],
  );
}
