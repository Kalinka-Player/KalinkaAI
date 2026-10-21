import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../configuration_appearance.dart';

/// Muted footer text displayed below the last card in a tab section.
class FooterNote extends StatelessWidget {
  final String text;

  const FooterNote({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final inset = ConfigurationAppearance.sideInset(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 10, inset, 0),
      child: Text(
        text,
        style: KalinkaTextStyles.trayRowSublabel.copyWith(
          fontSize: KalinkaTypography.baseSize + 1,
          color: KalinkaColors.textMuted,
          height: 1.7,
        ),
      ),
    );
  }
}
