import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/connection_settings_provider.dart';
import '../providers/connection_state_provider.dart';
import '../theme/app_theme.dart';

/// Server status chip — top-right of the header.
///
/// Shows connection state (online, reconnecting, offline, no server)
/// with a colored dot and server name label. Tappable to open the
/// server sheet. With [compact] set, only the status dot is shown (with a
/// padded hit target); the label lives in semantics.
class ServerChip extends ConsumerStatefulWidget {
  final VoidCallback? onTap;

  /// Render just the status dot — for surfaces where the full chip would
  /// crowd the row (the search header).
  final bool compact;

  const ServerChip({super.key, this.onTap, this.compact = false});

  @override
  ConsumerState<ServerChip> createState() => _ServerChipState();
}

class _ServerChipState extends ConsumerState<ServerChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 0.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionStateProvider);
    final settings = ref.watch(connectionSettingsProvider);

    // Start/stop pulse animation based on state
    if (connectionState == ConnectionStatus.reconnecting) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
        _pulseController.value = 1.0;
      }
    }

    final chipData = _getChipData(connectionState, settings.name);

    if (widget.compact) {
      return Semantics(
        label: chipData.label,
        button: widget.onTap != null,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: _buildDot(connectionState, chipData.dotColor),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
        decoration: BoxDecoration(
          color: chipData.bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: chipData.borderColor, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status dot
            _buildDot(connectionState, chipData.dotColor),
            const SizedBox(width: 6),
            // Label
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                chipData.label,
                style: KalinkaTextStyles.serverChipLabel.copyWith(
                  color: chipData.labelColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            // Chevron
            Icon(
              Icons.keyboard_arrow_down,
              size: 14,
              color: chipData.labelColor.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(ConnectionStatus state, Color color) {
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: state == ConnectionStatus.connected
            ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)]
            : null,
      ),
    );

    if (state == ConnectionStatus.reconnecting) {
      return FadeTransition(opacity: _pulseAnimation, child: dot);
    }
    return dot;
  }

  _ChipData _getChipData(ConnectionStatus state, String serverName) {
    switch (state) {
      case ConnectionStatus.connected:
        return _ChipData(
          dotColor: KalinkaColors.statusOnline,
          label: serverName.isNotEmpty ? serverName : 'Connected',
          labelColor: KalinkaColors.textPrimary,
          borderColor: KalinkaColors.statusOnline.withValues(alpha: 0.25),
          bgColor: KalinkaColors.statusOnline.withValues(alpha: 0.06),
        );
      case ConnectionStatus.reconnecting:
        return _ChipData(
          dotColor: KalinkaColors.statusPending,
          label: 'Reconnecting\u2026',
          labelColor: KalinkaColors.textPrimary,
          borderColor: KalinkaColors.statusPending.withValues(alpha: 0.25),
          bgColor: KalinkaColors.statusPending.withValues(alpha: 0.06),
        );
      case ConnectionStatus.offline:
        return _ChipData(
          dotColor: KalinkaColors.statusOffline,
          label: serverName.isNotEmpty ? serverName : 'Offline',
          labelColor: KalinkaColors.textPrimary,
          borderColor: KalinkaColors.statusOffline.withValues(alpha: 0.25),
          bgColor: KalinkaColors.statusOffline.withValues(alpha: 0.06),
        );
      case ConnectionStatus.none:
        return _ChipData(
          dotColor: KalinkaColors.textMuted,
          label: 'No server',
          labelColor: KalinkaColors.textMuted,
          borderColor: Colors.transparent,
          bgColor: KalinkaColors.surfaceInput,
        );
      case ConnectionStatus.connecting:
        return _ChipData(
          dotColor: KalinkaColors.statusPending,
          label: 'Connecting\u2026',
          labelColor: KalinkaColors.textSecondary,
          borderColor: KalinkaColors.statusPending.withValues(alpha: 0.15),
          bgColor: KalinkaColors.statusPending.withValues(alpha: 0.04),
        );
    }
  }
}

class _ChipData {
  final Color dotColor;
  final String label;
  final Color labelColor;
  final Color borderColor;
  final Color bgColor;

  const _ChipData({
    required this.dotColor,
    required this.label,
    required this.labelColor,
    required this.borderColor,
    required this.bgColor,
  });
}
