import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/shell_nav_provider.dart';
import '../theme/app_theme.dart';
import '../utils/click_cursor.dart';

/// The player's two views as tabs in the section headings' caps, the chosen
/// one underlined in berry.
class PlayerViewSwitch extends ConsumerWidget {
  const PlayerViewSwitch({super.key});

  static const _views = [
    (view: PlayerView.nowPlaying, label: 'PLAYING', spoken: 'Now playing'),
    (view: PlayerView.queue, label: 'QUEUE', spoken: 'Queue'),
  ];
  static const _gap = 8.0;
  static const _horizontalPadding = 8.0;

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
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
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
                  child: _ViewTab(
                    label: _views[i].label,
                    spoken: _views[i].spoken,
                    labelWidth: labelWidths[i],
                    active: _views[i].view == current,
                    duration: duration,
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

class _ViewTab extends StatelessWidget {
  final String label;
  final String spoken;
  final double labelWidth;
  final bool active;
  final Duration duration;
  final VoidCallback onTap;

  const _ViewTab({
    required this.label,
    required this.spoken,
    required this.labelWidth,
    required this.active,
    required this.duration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: spoken,
      button: true,
      selected: active,
      inMutuallyExclusiveGroup: true,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          focusColor: KalinkaColors.surfaceOverlay,
          hoverColor: KalinkaColors.surfaceInput,
          mouseCursor: clickCursor(interactive: !active),
          child: Stack(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PlayerViewSwitch._horizontalPadding,
                    vertical: 12,
                  ),
                  child: Center(
                    heightFactor: 1,
                    child: AnimatedDefaultTextStyle(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      style: PlayerViewSwitch._labelStyle.copyWith(
                        color: active
                            ? KalinkaColors.textPrimary
                            : KalinkaColors.textSecondary,
                      ),
                      child: Text(label, textAlign: TextAlign.center),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 4,
                child: Center(
                  child: AnimatedContainer(
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    width: labelWidth,
                    height: 2,
                    decoration: BoxDecoration(
                      color: active ? KalinkaColors.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
