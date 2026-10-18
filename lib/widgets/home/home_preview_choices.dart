import 'package:flutter/material.dart';

import '../../providers/pinned_catalogs_provider.dart';
import '../../theme/app_theme.dart';
import '../kalinka_bottom_sheet.dart';
import '../tap_highlight.dart';
import 'home_preview_illustration.dart';

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
  final Color sourceColor;

  const HomePreviewChoices({
    super.key,
    this.selected,
    required this.onSelected,
    this.sourceColor = KalinkaColors.accent,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: kSheetGutter),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        for (final type in HomePreviewType.values)
          HomePreviewOption(
            type: type,
            selected: type == selected,
            sourceColor: sourceColor,
            onPressed: () => onSelected(type),
          ),
      ],
    ),
  );
}

/// A compact visual picker, adapting to two columns for enlarged text.
class HomePreviewGrid extends StatelessWidget {
  final double width;
  final HomePreviewType selected;
  final ValueChanged<HomePreviewType> onSelected;
  final Color sourceColor;

  const HomePreviewGrid({
    super.key,
    required this.width,
    required this.selected,
    required this.onSelected,
    this.sourceColor = KalinkaColors.accent,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final columns = width >= 4 * 68 * scale + 24 ? 4 : 2;
    final optionWidth = (width - (columns - 1) * 8) / columns;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final type in HomePreviewType.values)
          SizedBox(
            width: optionWidth,
            child: HomePreviewOption(
              type: type,
              selected: type == selected,
              sourceColor: sourceColor,
              compact: true,
              onPressed: () => onSelected(type),
            ),
          ),
      ],
    );
  }
}

/// Native button semantics and keyboard feedback with a visual layout example.
class HomePreviewOption extends StatelessWidget {
  final HomePreviewType type;
  final bool selected;
  final bool compact;
  final Color sourceColor;
  final VoidCallback onPressed;

  const HomePreviewOption({
    super.key,
    required this.type,
    required this.selected,
    required this.onPressed,
    this.compact = false,
    this.sourceColor = KalinkaColors.accent,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    inMutuallyExclusiveGroup: true,
    label: '${type.label}. ${type.description}',
    child: Tooltip(
      message: type.label,
      excludeFromSemantics: true,
      child: TextButton(
        key: ValueKey('home-preview-option-${type.name}'),
        onPressed: onPressed,
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(
            KalinkaColors.textPrimary,
          ),
          backgroundColor: WidgetStatePropertyAll(
            selected ? KalinkaColors.accentSubtle : KalinkaColors.surfaceRaised,
          ),
          overlayColor: kalinkaOverlay,
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          padding: WidgetStatePropertyAll(
            compact
                ? const EdgeInsets.symmetric(horizontal: 6, vertical: 16)
                : const EdgeInsets.all(10),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.focused)
                  ? KalinkaColors.textSecondary
                  : selected
                  ? KalinkaColors.accentTint
                  : compact
                  ? Colors.transparent
                  : KalinkaColors.borderSubtle,
              width: selected || states.contains(WidgetState.focused) ? 2 : 1,
            ),
          ),
        ),
        child: ExcludeSemantics(
          child: compact ? _compactContent() : _rowContent(),
        ),
      ),
    ),
  );

  Widget _compactContent() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      HomePreviewIllustration(type: type, sourceColor: sourceColor),
      const SizedBox(height: 6),
      SizedBox(
        height: 18,
        child: selected
            ? const DecoratedBox(
                decoration: BoxDecoration(
                  color: KalinkaColors.accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: KalinkaColors.textPrimary,
                ),
              )
            : null,
      ),
      const SizedBox(height: 4),
      Text(
        type.label,
        textAlign: TextAlign.center,
        style: KalinkaTextStyles.trayRowSublabel.copyWith(
          color: selected
              ? KalinkaColors.textPrimary
              : KalinkaColors.textSecondary,
        ),
      ),
    ],
  );

  Widget _rowContent() => LayoutBuilder(
    builder: (context, constraints) => Row(
      children: [
        SizedBox(
          width: (constraints.maxWidth * .38).clamp(72.0, 120.0),
          child: HomePreviewIllustration(type: type, sourceColor: sourceColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(type.label, style: KalinkaTextStyles.trayRowLabel),
              const SizedBox(height: 4),
              Text(type.description, style: KalinkaTextStyles.trayRowSublabel),
            ],
          ),
        ),
      ],
    ),
  );
}
