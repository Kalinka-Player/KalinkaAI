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
  final ListingLayout layout;

  const PresentationToggle({super.key, required this.layout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chosen =
        ref.watch(listingPresentationProvider)[layout.id] ?? layout.byDefault;
    final notifier = ref.read(listingPresentationProvider.notifier);

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
            onTap: () => notifier.set(layout, presentation),
            borderRadius: BorderRadius.circular(6),
            focusColor: KalinkaColors.surfaceOverlay,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              constraints: const BoxConstraints(minHeight: 26, minWidth: 34),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? KalinkaColors.surfaceOverlay : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                icon,
                size: 15,
                color: on ? KalinkaColors.textPrimary : KalinkaColors.textMuted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KalinkaColors.borderDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          side(ListingPresentation.grid, Icons.grid_view_rounded, 'Grid'),
          side(ListingPresentation.list, Icons.view_list_rounded, 'List'),
        ],
      ),
    );
  }
}
