import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/connection_settings_provider.dart';
import '../providers/connection_state_provider.dart';
import '../theme/app_theme.dart';
import 'box_actions.dart';
import 'kalinka_button.dart';

/// Card that appears above the mini-player after 30s of failed reconnection.
///
/// Offers "Scan for servers" — or "Restart server" when the server's box still
/// answers — and "Retry", plus a dismiss link.
/// Once dismissed, it won't reappear until the app restarts.
class EscalationCard extends ConsumerStatefulWidget {
  final VoidCallback onScanForServers;

  const EscalationCard({super.key, required this.onScanForServers});

  @override
  ConsumerState<EscalationCard> createState() => _EscalationCardState();
}

class _EscalationCardState extends ConsumerState<EscalationCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _entryController;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionStateProvider);
    final notifier = ref.read(connectionStateProvider.notifier);
    final settings = ref.watch(connectionSettingsProvider);
    final name = settings.name.isNotEmpty ? settings.name : settings.host;

    // Only show when offline/reconnecting AND escalation reached AND not dismissed
    final shouldShow =
        (connectionState == ConnectionStatus.offline ||
            connectionState == ConnectionStatus.reconnecting) &&
        notifier.escalationReached &&
        !notifier.escalationDismissed;

    if (!shouldShow) return const SizedBox.shrink();

    // The box still answers at this address, so the server has not moved:
    // restarting it is the remedy, not scanning for it.
    final boxAnswers = ref.watch(canRestartServerThroughBoxProvider);

    return AnimatedBuilder(
      animation: _entryController,
      builder: (context, child) {
        final curve = Curves.easeOut.transform(_entryController.value);
        return Transform.translate(
          offset: Offset(0, 20 * (1 - curve)),
          child: Opacity(opacity: curve, child: child),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: KalinkaColors.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: KalinkaColors.statusOffline.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Red info icon tile
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: KalinkaColors.statusOffline.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: KalinkaColors.statusOffline,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$name is unavailable',
                      style: KalinkaTextStyles.trayRowLabel.copyWith(
                        fontSize: KalinkaTypography.baseSize + 3,
                      ),
                      maxLines: 2,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                boxAnswers
                    ? 'The server hasn\'t responded for over 30 seconds, but '
                          'its box is still on the network. Restarting the '
                          'server may bring it back.'
                    : 'The server hasn\'t responded for over 30 seconds. '
                          'It may be offline or unreachable on the network.',
                style: KalinkaTextStyles.trayRowSublabel.copyWith(
                  fontSize: KalinkaTypography.baseSize + 0,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              // Web has no mDNS to scan with, so there it is Retry alone.
              Row(
                children: [
                  if (boxAnswers) ...[
                    KalinkaButton(
                      label: 'Restart server',
                      variant: KalinkaButtonVariant.accent,
                      size: KalinkaButtonSize.compact,
                      onTap: () => restartServerThroughBox(context, ref),
                    ),
                    const Spacer(),
                  ] else if (!kIsWeb) ...[
                    // Scan for servers
                    KalinkaButton(
                      label: 'Scan for servers',
                      variant: KalinkaButtonVariant.accent,
                      size: KalinkaButtonSize.compact,
                      onTap: widget.onScanForServers,
                    ),
                    const Spacer(),
                  ],
                  // Retry
                  KalinkaButton(
                    label: 'Retry',
                    variant: kIsWeb && !boxAnswers
                        ? KalinkaButtonVariant.accent
                        : KalinkaButtonVariant.neutral,
                    size: KalinkaButtonSize.compact,
                    onTap: () =>
                        ref.read(connectionStateProvider.notifier).retryNow(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
