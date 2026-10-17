import 'package:flutter/material.dart';

import '../../providers/pinned_catalogs_provider.dart';
import '../../theme/app_theme.dart';
import '../kalinka_bottom_sheet.dart';

IconData homePreviewIcon(HomePreviewType type) => switch (type) {
  HomePreviewType.cards => Icons.view_carousel_outlined,
  HomePreviewType.artwork => Icons.image_outlined,
  HomePreviewType.list => Icons.view_list_outlined,
  HomePreviewType.compact => Icons.view_agenda_outlined,
};

/// The same layout names and visual cues when pinning or editing a pin.
class HomePreviewChoices extends StatelessWidget {
  final HomePreviewType? selected;
  final ValueChanged<HomePreviewType> onSelected;

  const HomePreviewChoices({
    super.key,
    this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final type in HomePreviewType.values)
        Semantics(
          button: true,
          selected: type == selected,
          inMutuallyExclusiveGroup: true,
          child: SheetRow(
            icon: homePreviewIcon(type),
            iconBackground: KalinkaColors.surfaceElevated,
            iconColor: KalinkaColors.textSecondary,
            label: type.label,
            sublabel: type.description,
            trailing: type == selected
                ? const Icon(
                    Icons.check_rounded,
                    color: KalinkaColors.accentTint,
                    size: 20,
                  )
                : null,
            onTap: () => onSelected(type),
          ),
        ),
    ],
  );
}
