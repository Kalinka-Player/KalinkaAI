import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'configuration_appearance.dart';

/// A scrolling introduction without repeating the fixed page title.
class SettingsPageIntro extends StatelessWidget {
  final String? description;
  final Widget? status;
  final Widget? action;

  const SettingsPageIntro({
    super.key,
    this.description,
    this.status,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final gutter = ConfigurationAppearance.gutter(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 20, gutter, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (status != null || action != null)
            LayoutBuilder(
              builder: (context, constraints) {
                final stack =
                    constraints.maxWidth < 320 ||
                    MediaQuery.textScalerOf(context).scale(14) > 18.2;
                if (stack) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ?status,
                      if (status != null && action != null)
                        const SizedBox(height: 12),
                      ?action,
                    ],
                  );
                }
                return Row(
                  children: [
                    if (status != null)
                      Expanded(child: status!)
                    else
                      const Spacer(),
                    if (action != null) ...[const SizedBox(width: 12), action!],
                  ],
                );
              },
            ),
          if (description?.isNotEmpty == true) ...[
            if (status != null || action != null) const SizedBox(height: 12),
            Text(description!, style: KalinkaTextStyles.settingsDescription),
          ],
        ],
      ),
    );
  }
}
