import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';
import 'home/home_layout.dart';
import 'server_chip.dart';
import 'tap_highlight.dart';

/// Slim top app bar for the main screen: Kalinka wordmark on the left,
/// connection chip (via [ServerChip], which carries the green status dot) on
/// the right. Home's pages below its top level swap it for a back arrow and
/// breadcrumb (see SearchSessionView).
class KalinkaTopBar extends StatelessWidget {
  final VoidCallback? onServerChipTap;
  final VoidCallback? onResultsTap;

  /// Home's search entry once it has scrolled away. It shares the bar only
  /// when there is room beside the wordmark and server chip.
  final Widget? searchEntry;

  /// Compact search action when [searchEntry] cannot fit. Omitted when a
  /// saved search already supplies a way back to results.
  final Widget? searchFallback;

  /// Anchor for the first-run coach-mark spotlight on the connection chip.
  final GlobalKey? connectionKey;

  /// No fill, rule or shadow: the surface below shows through, as Home's
  /// bloom does.
  final bool transparent;

  const KalinkaTopBar({
    super.key,
    this.onServerChipTap,
    this.onResultsTap,
    this.searchEntry,
    this.searchFallback,
    this.connectionKey,
    this.transparent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: transparent ? null : kKalinkaTopBarDecoration,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kKalinkaTopBarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth < 300 ||
                    MediaQuery.textScalerOf(context).scale(12) > 18;
                return Row(
                  children: [
                    Expanded(child: _buildLeading()),
                    if (onResultsTap != null)
                      IconButton(
                        tooltip: 'Back to search results',
                        style: kalinkaIconButtonStyle,
                        onPressed: onResultsTap,
                        icon: const Icon(Icons.manage_search, size: 24),
                      ),
                    KeyedSubtree(
                      key: connectionKey,
                      child: SizedBox(
                        height: 48,
                        width: compact ? 48 : null,
                        child: Center(
                          child: ServerChip(
                            onTap: onServerChipTap,
                            compact: compact,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final search = searchEntry;
            final fallback = search != null && onResultsTap == null
                ? searchFallback
                : null;
            if (search != null &&
                onResultsTap == null &&
                constraints.maxWidth >=
                    KalinkaWordmark.width +
                        24 +
                        MediaQuery.textScalerOf(context).scale(200)) {
              return Row(
                children: [
                  const KalinkaWordmark(),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Align(
                      alignment: Alignment.center,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: kHomeSearchMaxWidth,
                        ),
                        child: search,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                ],
              );
            }
            final wordmark = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Flexible(child: KalinkaWordmark()),
                if (!kReleaseMode &&
                    constraints.maxWidth - (fallback == null ? 0 : 48) >
                        160) ...[
                  const SizedBox(width: 10),
                  Flexible(child: _buildDebugBadge()),
                ],
              ],
            );
            return fallback == null
                ? wordmark
                : Row(
                    children: [
                      Expanded(child: wordmark),
                      fallback,
                    ],
                  );
          },
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

/// The Kalinka wordmark at the top bar's size.
class KalinkaWordmark extends StatelessWidget {
  const KalinkaWordmark({super.key});

  /// Its width at that size, from the artwork's proportions.
  static const double width = kKalinkaWordmarkHeight * 18.378336 / 8.1929674;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/kalinka_logo.svg',
      height: kKalinkaWordmarkHeight,
      width: width,
      fit: BoxFit.contain,
    );
  }
}
