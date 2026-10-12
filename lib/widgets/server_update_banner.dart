import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/server_update_provider.dart';
import '../providers/upgrade_provider.dart';
import '../theme/app_theme.dart';
import 'kalinka_dialog.dart' show showKalinkaDialog;
import 'upgrade_confirm_dialog.dart';
import 'configuration_appearance.dart';

/// One-line server update status banner under the SERVER section header.
///
/// Update available → "A new version X is available ›" with an amber
/// exclamation; tapping opens the update confirmation dialog and, on
/// confirm, starts the upgrade (the overlay follows via upgradeProvider).
/// Up to date → green tick with dim "The server is up to date" text.
/// Hidden while the update state is unknown (old server, check failed).
class ServerUpdateBanner extends ConsumerWidget {
  const ServerUpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(serverUpdateProvider).value;
    if (update == null ||
        (update.updateAvailable && !update.upgradeSupported)) {
      return const SizedBox.shrink();
    }
    final configuration = ConfigurationAppearance.active(context);
    final gutter = configuration
        ? ConfigurationAppearance.gutter(context)
        : 16.0;
    final canUpgrade = update.canUpgrade;
    final version = update.latestVersion;

    final row = Row(
      children: [
        Icon(
          canUpgrade ? Icons.warning_amber_rounded : Icons.check_circle,
          size: 18,
          color: canUpgrade
              ? KalinkaColors.statusPending
              : KalinkaColors.statusOnline,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            canUpgrade
                ? 'A new version $version is available'
                : configuration
                ? 'Your player is up to date'
                : 'The server is up to date',
            style: canUpgrade
                ? KalinkaTextStyles.trayRowLabel
                : KalinkaTextStyles.trayRowLabel.copyWith(
                    color: KalinkaColors.textSecondary,
                  ),
            maxLines: configuration ? null : 1,
            overflow: configuration ? TextOverflow.clip : TextOverflow.ellipsis,
          ),
        ),
        if (canUpgrade)
          const Icon(
            Icons.chevron_right,
            size: 20,
            color: KalinkaColors.textSecondary,
          ),
      ],
    );

    if (configuration && !canUpgrade) {
      return Padding(
        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 12),
        child: row,
      );
    }
    return Container(
      margin: EdgeInsets.fromLTRB(gutter, 0, gutter, 12),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KalinkaColors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: canUpgrade
          ? Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _confirmUpgrade(context, ref, version!),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  child: row,
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: row,
            ),
    );
  }

  Future<void> _confirmUpgrade(
    BuildContext context,
    WidgetRef ref,
    String version,
  ) async {
    final confirmed = await showKalinkaDialog<bool>(
      context: context,
      builder: (_) => UpgradeConfirmDialog(version: version),
    );
    if (confirmed != true) return;
    ref.read(upgradeProvider.notifier).executeUpgrade(version);
  }
}
