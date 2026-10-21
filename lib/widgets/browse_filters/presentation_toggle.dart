import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/listing_presentation_provider.dart';
import '../../theme/app_theme.dart';

/// Grid or List for one listing. It changes how the page lays out what it
/// already shows — never what it shows, nor the history — and the choice is
/// kept for that listing on this device.
///
/// Grey on purpose: it is chrome that stays for the whole visit, so the
/// chosen side is lifted in the depth scale rather than marked in berry.
class PresentationToggle extends ConsumerWidget {
  static const width = 2 * kKalinkaPillTarget;
  final ListingLayout layout;

  /// One round button that switches to the other presentation, for a bar
  /// with no room for both choices.
  final bool compact;

  const PresentationToggle({
    super.key,
    required this.layout,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chosen = watchPresentation(ref, layout);
    final notifier = ref.read(listingPresentationProvider.notifier);
    if (compact) {
      final grid = chosen == ListingPresentation.grid;
      final label = grid ? 'List view' : 'Grid view';
      return Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: () => notifier.set(
          layout,
          grid ? ListingPresentation.list : ListingPresentation.grid,
        ),
        child: Tooltip(
          message: label,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: () => notifier.set(
              layout,
              grid ? ListingPresentation.list : ListingPresentation.grid,
            ),
            customBorder: const CircleBorder(),
            focusColor: KalinkaColors.surfaceOverlay,
            child: SizedBox.square(
              dimension: kKalinkaPillTarget,
              child: Center(
                child: Container(
                  width: kKalinkaPillHeight,
                  height: kKalinkaPillHeight,
                  decoration: const ShapeDecoration(
                    color: KalinkaColors.surfaceElevated,
                    shape: CircleBorder(
                      side: BorderSide(color: KalinkaColors.borderDefault),
                    ),
                  ),
                  child: Icon(
                    grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                    size: 18,
                    color: KalinkaColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget side(ListingPresentation presentation, IconData icon, String label) {
      final on = presentation == chosen;
      return Semantics(
        button: true,
        selected: on,
        label: '$label view',
        excludeSemantics: true,
        onTap: () => notifier.set(layout, presentation),
        child: Tooltip(
          message: '$label view',
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: () => notifier.set(layout, presentation),
            customBorder: const StadiumBorder(),
            focusColor: KalinkaColors.surfaceOverlay,
            child: SizedBox(
              width: kKalinkaPillTarget,
              height: kKalinkaPillTarget,
              child: Padding(
                // 3dp inside the pill's edge on every side.
                padding: const EdgeInsets.symmetric(
                  horizontal: 3,
                  vertical: (kKalinkaPillTarget - kKalinkaPillHeight) / 2 + 3,
                ),
                child: AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 120),
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: on
                        ? KalinkaColors.surfaceOverlay
                        : Colors.transparent,
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: on
                            ? KalinkaColors.textMuted
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: on
                        ? KalinkaColors.textPrimary
                        : KalinkaColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // The Play all pill's chrome and height, centred in the choices' targets.
    return SizedBox(
      width: width,
      height: kKalinkaPillTarget,
      child: Stack(
        children: [
          const Positioned.fill(
            top: (kKalinkaPillTarget - kKalinkaPillHeight) / 2,
            bottom: (kKalinkaPillTarget - kKalinkaPillHeight) / 2,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: KalinkaColors.surfaceElevated,
                shape: StadiumBorder(
                  side: BorderSide(color: KalinkaColors.borderDefault),
                ),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              side(ListingPresentation.grid, Icons.grid_view_rounded, 'Grid'),
              side(ListingPresentation.list, Icons.view_list_rounded, 'List'),
            ],
          ),
        ],
      ),
    );
  }
}
