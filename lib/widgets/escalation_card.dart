import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connection_settings_provider.dart';
import '../providers/connection_state_provider.dart';
import '../theme/app_theme.dart';
import 'box_actions.dart';
import 'kalinka_button.dart';
import 'kalinka_toast_overlay.dart';

/// Card that appears above the mini-player after 30s of failed reconnection,
/// or as soon as the box is known to be powering off.
///
/// Offers "Scan for servers" — or "Restart server" when the server's box still
/// answers — and "Retry". Like the toasts that stack above it, it sits at the
/// right of its pane, capped at [kToastMaxWidth].
class EscalationCard extends ConsumerStatefulWidget {
  final VoidCallback onScanForServers;

  /// Keeps the tablet toasts' wider right gutter, so their edges line up.
  final bool isTablet;

  /// Web has no mDNS to scan with, so there it is Retry alone.
  final bool canScan;

  const EscalationCard({
    super.key,
    required this.onScanForServers,
    this.isTablet = false,
    this.canScan = !kIsWeb,
  });

  /// Marks the card itself, so placement tests can measure where it landed.
  @visibleForTesting
  static const cardKey = Key('escalation_card');

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

    final poweredOff = notifier.boxPoweredOff;
    // The box still answers at this address, so the server has not moved:
    // restarting it is the remedy, not scanning for it. A box shutting down
    // can still answer for a moment.
    final boxAnswers =
        !poweredOff && ref.watch(canRestartServerThroughBoxProvider);

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
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          widget.isTablet ? kToastTabletGutter : 16,
          18,
        ),
        child: Align(
          alignment: Alignment.centerRight,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kToastMaxWidth),
            child: _buildCard(name, boxAnswers, poweredOff),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(String name, bool boxAnswers, bool poweredOff) {
    final primary = boxAnswers
        ? KalinkaButton(
            label: 'Restart server',
            variant: KalinkaButtonVariant.accent,
            size: KalinkaButtonSize.compact,
            onTap: () => restartServerThroughBox(context, ref),
          )
        : !widget.canScan
        ? null
        : KalinkaButton(
            label: 'Scan for servers',
            variant: KalinkaButtonVariant.accent,
            size: KalinkaButtonSize.compact,
            onTap: widget.onScanForServers,
          );
    final retry = KalinkaButton(
      label: 'Retry',
      variant: primary == null
          ? KalinkaButtonVariant.accent
          : KalinkaButtonVariant.neutral,
      size: KalinkaButtonSize.compact,
      onTap: () => ref.read(connectionStateProvider.notifier).retryNow(),
    );
    final message = poweredOff
        ? 'The streamer is powered off. Turn it back on, then Retry'
              '${widget.canScan ? ', or scan for another server' : ''}.'
        : boxAnswers
        ? 'The server hasn\'t responded for over 30 seconds, but its streamer '
              'is still on the network. Restarting the server may bring it '
              'back.'
        : 'The server hasn\'t responded for over 30 seconds. It may be '
              'offline or unreachable on the network.';
    return Container(
      key: EscalationCard.cardKey,
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
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: KalinkaTextStyles.trayRowSublabel.copyWith(
              fontSize: KalinkaTypography.baseSize + 0,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          // Retry keeps the trailing edge, and drops below the primary
          // when enlarged text leaves no room beside it.
          OverflowBar(
            alignment: primary == null
                ? MainAxisAlignment.end
                : MainAxisAlignment.spaceBetween,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: 10,
            overflowSpacing: 8,
            children: [?primary, retry],
          ),
        ],
      ),
    );
  }
}
