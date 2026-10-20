import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/server_update_provider.dart';
import '../providers/upgrade_provider.dart';
import '../theme/app_theme.dart';
import 'kalinka_dialog.dart' show showKalinkaDialog;
import 'upgrade_confirm_dialog.dart';
import 'configuration_appearance.dart';

/// Update status, optionally embedded in the Streamer's software settings card.
/// Package updates name their own versions, even when the server is current.
class ServerUpdateBanner extends ConsumerWidget {
  final bool embedded;
  const ServerUpdateBanner({super.key, this.embedded = false});

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

    final row = Row(
      children: [
        Icon(
          update.updateAvailable
              ? Icons.system_update_alt
              : Icons.check_circle_outline,
          size: 22,
          color: update.updateAvailable
              ? KalinkaColors.statusPending
              : KalinkaColors.statusOnline,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                update.updateAvailable
                    ? 'Software updates available'
                    : embedded
                    ? 'Up to date'
                    : 'Your player is up to date',
                style: KalinkaTextStyles.trayRowLabel,
              ),
              for (final change in update.changes)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(change, style: KalinkaTextStyles.trayRowSublabel),
                ),
            ],
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

    final content = Padding(padding: const EdgeInsets.all(16), child: row);
    final body = canUpgrade
        ? Semantics(
            button: true,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                mouseCursor: WidgetStateMouseCursor.clickable,
                onTap: () => _confirmUpgrade(context, ref, update),
                hoverColor: KalinkaColors.surfaceOverlay,
                highlightColor: KalinkaColors.surfaceOverlay,
                child: content,
              ),
            ),
          )
        : content;
    if (embedded) return body;
    return Container(
      margin: EdgeInsets.fromLTRB(gutter, 0, gutter, 12),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KalinkaColors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: body,
    );
  }

  Future<void> _confirmUpgrade(
    BuildContext context,
    WidgetRef ref,
    ServerUpdateInfo update,
  ) async {
    final confirmed = await showKalinkaDialog<bool>(
      context: context,
      builder: (_) => UpgradeConfirmDialog(update: update),
    );
    if (confirmed != true) return;
    ref.read(upgradeProvider.notifier).executeUpgrade(update.latestVersion!);
  }
}
