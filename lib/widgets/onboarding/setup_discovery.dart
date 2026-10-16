import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Shared activity indicator for Bluetooth and hotspot setup.
class SetupActivityIndicator extends StatelessWidget {
  final String semanticsLabel;

  const SetupActivityIndicator({super.key, required this.semanticsLabel});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 20,
    height: 20,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: KalinkaColors.accentTint,
      semanticsLabel: semanticsLabel,
    ),
  );
}

/// Discovery section with a spinner while searching and a rescan action at rest.
class SetupDiscoveryHeader extends StatelessWidget {
  final String title;
  final String activityLabel;
  final bool searching;
  final VoidCallback? onScan;

  const SetupDiscoveryHeader({
    super.key,
    required this.title,
    required this.activityLabel,
    required this.searching,
    this.onScan,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(title, style: KalinkaTextStyles.sectionHeaderMuted)),
      if (searching)
        SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: SetupActivityIndicator(semanticsLabel: activityLabel),
          ),
        )
      else
        IconButton(
          tooltip: 'Scan again',
          onPressed: onScan,
          icon: const Icon(
            Icons.refresh_rounded,
            color: KalinkaColors.textSecondary,
          ),
        ),
    ],
  );
}

/// Setup activity card with an optional spinner and wrapping guidance.
class SetupLoadingCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool loading;

  const SetupLoadingCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.loading = true,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: KalinkaColors.surfaceRaised,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: KalinkaColors.borderDefault),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (loading) ...[
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: SetupActivityIndicator(semanticsLabel: title),
          ),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: KalinkaTextStyles.trayRowLabel.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: KalinkaTextStyles.trayRowSublabel.copyWith(
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
