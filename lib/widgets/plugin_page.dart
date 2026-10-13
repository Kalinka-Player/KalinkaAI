import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/plugin_catalog.dart';
import '../providers/plugin_state.dart';
import '../theme/app_theme.dart';
import 'configuration_appearance.dart';
import 'plugin_catalog_entry.dart';
import 'settings_page_intro.dart';
import 'settings_top_bar.dart';
import 'slide_in_panel.dart';

/// A plugin's settings or About page, with Back returning to its opener.
class PluginPage extends ConsumerWidget {
  final CatalogPlugin plugin;

  /// Names the page and the plugin together: "About Qobuz".
  final String title;

  /// Which page this is, for its scroll's key.
  final String id;
  final String? description;
  final VoidCallback onClose;

  final bool handlesBack;

  /// Held under the title bar, outside the scroll.
  final Widget? notice;

  /// The page's content under its introduction, inset by the page gutter.
  final List<Widget> Function(PluginState state, double gutter) builder;

  /// A single icon action in the fixed title bar, such as About.
  final Widget? headerAction;

  /// An action alongside the plugin's status in the scrolling introduction.
  final Widget? Function(PluginState state)? trailing;

  const PluginPage({
    super.key,
    required this.plugin,
    required this.title,
    required this.id,
    required this.onClose,
    required this.builder,
    this.description,
    this.notice,
    this.trailing,
    this.headerAction,
    this.handlesBack = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pluginStateProvider(plugin));
    final gutter = ConfigurationAppearance.gutter(context);
    final trailing = this.trailing?.call(state);
    return SlideInPanel(
      onClose: onClose,
      handlesBack: handlesBack,
      child: Material(
        color: KalinkaColors.background,
        child: SafeArea(
          top: false,
          // Below the panel, which the Back button closes.
          child: Builder(
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsTopBar(title: title, action: headerAction),
                ?notice,
                Expanded(
                  child: ListView(
                    key: ValueKey('plugin-page-$id'),
                    padding: const EdgeInsets.only(bottom: 32),
                    children: [
                      SettingsPageIntro(
                        description: description,
                        action: trailing,
                        status: PluginStatusSummary(
                          pluginName: plugin.name,
                          state: state,
                        ),
                      ),
                      ...builder(state, gutter),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
