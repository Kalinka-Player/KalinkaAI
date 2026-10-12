import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'configuration_appearance.dart';
import 'page_banner.dart';
import 'plugin_top_bar.dart';
import 'slide_in_panel.dart';

/// Keeps navigation fixed while the heading scrolls with the page's content.
class ConfigurationPage extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final String parent;
  final VoidCallback onClose;
  final bool handlesBack;
  final Widget Function(Widget heading) bodyBuilder;
  final List<Widget> overlays;

  const ConfigurationPage({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.onClose,
    required this.bodyBuilder,
    this.parent = 'Kalinka server',
    this.handlesBack = true,
    this.overlays = const [],
  });

  @override
  Widget build(BuildContext context) {
    final gutter = ConfigurationAppearance.gutter(context);
    return SlideInPanel(
      onClose: onClose,
      handlesBack: handlesBack,
      overlays: overlays,
      child: Material(
        color: KalinkaColors.background,
        child: SafeArea(
          child: Builder(
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PluginTopBar(
                  trail: [parent, title],
                  onNavigate: (_) => SlideInPanel.closeOf(context),
                ),
                Expanded(
                  child: bodyBuilder(
                    PageBanner(
                      key: const ValueKey('configuration-page-heading'),
                      title: title,
                      subtitle: description,
                      subtitleLines: null,
                      titleLeading: Icon(
                        icon,
                        color: KalinkaColors.textSecondary,
                        size: 40,
                      ),
                      widthFactor: 1,
                      padding: EdgeInsets.fromLTRB(gutter, 18, gutter, 20),
                    ),
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
