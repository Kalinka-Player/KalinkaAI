import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/shell_nav_provider.dart';
import '../theme/app_theme.dart';
import 'section_tab_button.dart';

/// The player's two views as tabs in the section headings' caps, the chosen
/// one underlined in berry.
class PlayerViewSwitch extends ConsumerWidget {
  const PlayerViewSwitch({super.key});

  static const _views = [
    (view: PlayerView.nowPlaying, label: 'PLAYING', spoken: 'Now playing'),
    (view: PlayerView.queue, label: 'QUEUE', spoken: 'Queue'),
  ];
  static const _gap = SectionTabButton.spacing;
  static const _horizontalPadding = SectionTabButton.horizontalPadding;

  /// The section headings' caps.
  static final _labelStyle = KalinkaTextStyles.sectionLabel;

  static List<double> _labelWidths(BuildContext context) => [
    for (final view in _views) _labelWidth(context, view.label),
  ];

  static double _labelWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: _labelStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return width;
  }

  static double _targetWidth(double labelWidth) =>
      (labelWidth + 2 * _horizontalPadding).clamp(48.0, double.infinity);

  /// Labels keep their natural widths so the tabs fit beside the phone's
  /// header actions. Enlarged text can move them onto a separate row.
  static double preferredWidth(BuildContext context) =>
      _labelWidths(context)
          .fold(_gap, (sum, width) => sum + _targetWidth(width));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(playerViewProvider);
    final labelWidths = _labelWidths(context);
    final width = labelWidths.fold(
      _gap,
      (sum, labelWidth) => sum + _targetWidth(labelWidth),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep large text at the requested size, stacking whole labels when
        // the header cannot accommodate them side by side.
        final vertical = constraints.maxWidth < width;
        return SizedBox(
          width: vertical ? constraints.maxWidth : width,
          child: Flex(
            direction: vertical ? Axis.vertical : Axis.horizontal,
            mainAxisSize: MainAxisSize.min,
            spacing: _gap,
            children: [
              for (var i = 0; i < _views.length; i++)
                SizedBox(
                  width: vertical
                      ? constraints.maxWidth
                      : _targetWidth(labelWidths[i]),
                  child: SectionTabButton(
                    label: _views[i].label,
                    semanticLabel: _views[i].spoken,
                    selected: _views[i].view == current,
                    onTap: () => ref
                        .read(playerViewProvider.notifier)
                        .show(_views[i].view),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
