import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/plugin_catalog.dart';
import '../providers/plugin_state.dart';
import '../theme/app_theme.dart';
import 'configuration_appearance.dart';
import 'page_banner.dart';
import 'plugin_catalog_entry.dart';
import 'plugin_top_bar.dart';
import 'slide_in_panel.dart';

/// A plugin's settings or About page, under the Configuration breadcrumb.
class PluginPage extends ConsumerWidget {
  final CatalogPlugin plugin;

  /// Names the page and the plugin together: "About Qobuz".
  final String title;

  /// Which page this is, for its scroll's key.
  final String id;
  final String? description;
  final VoidCallback onClose;

  /// Called as the trail's first crumb takes the page back to the overview,
  /// to put away any page under this one.
  final VoidCallback? onHome;
  final bool handlesBack;

  /// Held under the title bar, outside the scroll.
  final Widget? notice;

  /// The page's content under its banner, inset by the page gutter.
  final List<Widget> Function(PluginState state, double gutter) builder;

  /// Drawn at the top right, level with the title.
  final Widget? Function(PluginState state)? trailing;

  const PluginPage({
    super.key,
    required this.plugin,
    required this.title,
    required this.id,
    required this.onClose,
    required this.builder,
    this.onHome,
    this.description,
    this.notice,
    this.trailing,
    this.handlesBack = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pluginStateProvider(plugin));
    final gutter = ConfigurationAppearance.gutter(context);
    final trailing = this.trailing?.call(state);
    final banner = PageBanner(
      title: title,
      subtitle: description ?? state.detail ?? '',
      // The word its settings card shows, as on its row.
      subtitleLeading: description == null
          ? pluginBadge(state, notInstalled: true)
          : null,
      subtitleLines: description == null ? 1 : null,
      subtitleWraps: true,
      padding: EdgeInsets.fromLTRB(
        gutter,
        18,
        trailing == null ? gutter : 12,
        20,
      ),
    );
    return SlideInPanel(
      onClose: onClose,
      handlesBack: handlesBack,
      child: Material(
        color: KalinkaColors.background,
        child: SafeArea(
          // Below the panel, which the crumbs close.
          child: Builder(
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PluginTopBar(
                  trail: ['Configuration', title],
                  onNavigate: (_) {
                    onHome?.call();
                    SlideInPanel.closeOf(context);
                  },
                ),
                ?notice,
                Expanded(
                  child: ListView(
                    key: ValueKey('plugin-page-$id'),
                    padding: const EdgeInsets.only(bottom: 32),
                    children: [
                      if (trailing == null)
                        banner
                      else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: banner),
                            Padding(
                              // Level with the title's first line.
                              padding: EdgeInsets.only(top: 24, right: gutter),
                              child: trailing,
                            ),
                          ],
                        ),
                      if (description != null)
                        Padding(
                          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 16),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ?pluginBadge(state, notInstalled: true),
                              if (state.detail case final detail?)
                                Text(
                                  detail,
                                  style: KalinkaTextStyles.trayRowSublabel,
                                ),
                            ],
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
