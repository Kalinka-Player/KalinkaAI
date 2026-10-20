import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../providers/shell_nav_provider.dart';
import '../../theme/app_theme.dart';
import 'home_layout.dart';

/// An invitation in place of the pinned shelves, until the first catalog is pinned.
class HomeCustomisationBanner extends ConsumerWidget {
  const HomeCustomisationBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kHomeSearchMaxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: KalinkaColors.surfaceRaised,
          border: Border.all(color: KalinkaColors.borderSubtle),
          borderRadius: BorderRadius.circular(20),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal =
                constraints.maxWidth >=
                640 * MediaQuery.textScalerOf(context).scale(14) / 14;
            final illustration = ExcludeSemantics(
              child: SvgPicture.asset(
                'assets/images/home_customisation_collage.svg',
                width: horizontal ? 300 : 280,
                height: horizontal ? 180 : 124,
                fit: BoxFit.contain,
              ),
            );
            final invitation = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Make Home your own',
                  style: KalinkaFonts.display(
                    fontSize: 26,
                    height: 1.2,
                    color: KalinkaColors.frost,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Pin your favourite catalogs and choose how each section looks.',
                  style: KalinkaTextStyles.settingsDescription,
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  key: const ValueKey('customise-home-invitation'),
                  onPressed: () =>
                      ref.read(homeCustomisationProvider.notifier).open(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KalinkaColors.textPrimary,
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    side: const BorderSide(color: KalinkaColors.borderDefault),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: KalinkaFonts.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  icon: const Icon(Icons.tune, size: 20),
                  label: const Text('Customise Home'),
                ),
              ],
            );
            return Padding(
              // Trim the artwork and vertical space for a roughly 15% shorter
              // banner, keeping text and the button free to grow at large text.
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: horizontal
                  ? Row(
                      children: [
                        Expanded(child: invitation),
                        const SizedBox(width: 24),
                        illustration,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(child: illustration),
                        const SizedBox(height: 8),
                        invitation,
                      ],
                    ),
            );
          },
        ),
      ),
    ),
  );
}
