import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';
import 'server_chip.dart';

/// Slim top app bar for the main/queue screen: Kalinka wordmark on the left,
/// connection chip (via [ServerChip], which carries the green status dot) on
/// the right. The search screen replaces this bar with its own header row
/// (see SearchSessionView).
class KalinkaTopBar extends StatelessWidget {
  final VoidCallback? onServerChipTap;

  /// Anchor for the first-run coach-mark spotlight on the connection chip.
  final GlobalKey? connectionKey;

  const KalinkaTopBar({super.key, this.onServerChipTap, this.connectionKey});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: kKalinkaTopBarDecoration,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kKalinkaTopBarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(child: _buildLeading()),
                KeyedSubtree(
                  key: connectionKey,
                  child: ServerChip(onTap: onServerChipTap),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeading() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/images/kalinka_logo.svg',
              height: kKalinkaWordmarkHeight,
              fit: BoxFit.contain,
            ),
            if (!kReleaseMode) ...[
              const SizedBox(width: 10),
              Flexible(child: _buildDebugBadge()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDebugBadge() {
    // Shrinks rather than overflows beside a long server name on a narrow phone.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: KalinkaColors.statusOnline,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'DEBUG',
          style: KalinkaTextStyles.tagPill.copyWith(
            color: KalinkaColors.textPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}
