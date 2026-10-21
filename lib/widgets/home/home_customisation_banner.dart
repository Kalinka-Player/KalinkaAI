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
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kHomeBannerMaxWidth),
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
                480 * MediaQuery.textScalerOf(context).scale(14) / 14;
            final illustration = ExcludeSemantics(
              child: SvgPicture.asset(
                'assets/images/home_customisation_collage.svg',
                width: 200,
                height: horizontal ? 120 : 88,
                fit: BoxFit.contain,
              ),
            );
            final invitation = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Make Home your own',
                  style: KalinkaFonts.display(
                    fontSize: 22,
                    height: 1.2,
                    color: KalinkaColors.frost,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pin your favourite catalogs and choose how each section looks.',
                  style: KalinkaTextStyles.settingsDescription,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  key: const ValueKey('customise-home-invitation'),
                  onPressed: () =>
                      ref.read(homeCustomisationProvider.notifier).open(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KalinkaColors.textPrimary,
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    side: const BorderSide(color: KalinkaColors.borderDefault),
                    shape: const StadiumBorder(),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: horizontal
                  ? Row(
                      children: [
                        Expanded(child: invitation),
                        const SizedBox(width: 20),
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
