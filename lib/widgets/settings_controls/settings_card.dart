import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../configuration_appearance.dart';

/// Card container for groups of setting rows.
///
/// Background: #16161B, border-radius 14px, auto-inserts dividers between children.
class SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const SettingsCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final gutter = ConfigurationAppearance.active(context)
        ? ConfigurationAppearance.gutter(context)
        : 16.0;
    return Container(
      margin: EdgeInsets.fromLTRB(gutter, 0, gutter, 12),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KalinkaColors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildWithDividers(),
      ),
    );
  }

  List<Widget> _buildWithDividers() {
    final result = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      result.add(children[i]);
      if (i < children.length - 1) {
        result.add(
          const Divider(
            height: 1,
            thickness: 1,
            color: KalinkaColors.borderSubtle,
          ),
        );
      }
    }
    return result;
  }
}
