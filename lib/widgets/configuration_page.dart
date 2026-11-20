import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'settings_page_intro.dart';
import 'settings_top_bar.dart';
import 'slide_in_panel.dart';

/// One fixed page title, with the introduction scrolling with its content;
/// a page without a [description] has none.
class ConfigurationPage extends StatelessWidget {
  final String title;
  final String? description;

  /// A single icon action in the fixed title bar.
  final Widget? action;
  final VoidCallback onClose;
  final bool handlesBack;
  final Widget Function(Widget heading) bodyBuilder;
  final List<Widget> overlays;

  const ConfigurationPage({
    super.key,
    required this.title,
    this.description,
    this.action,
    required this.onClose,
    required this.bodyBuilder,
    this.handlesBack = true,
    this.overlays = const [],
  });

  @override
  Widget build(BuildContext context) {
    return SlideInPanel(
      onClose: onClose,
      handlesBack: handlesBack,
      overlays: overlays,
      child: Material(
        color: KalinkaColors.background,
        child: SafeArea(
          top: false,
          child: Builder(
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsTopBar(title: title, action: action),
                Expanded(
                  child: bodyBuilder(
                    description == null
                        ? const SizedBox.shrink()
                        : SettingsPageIntro(description: description),
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
