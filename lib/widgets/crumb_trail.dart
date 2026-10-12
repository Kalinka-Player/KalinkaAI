import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'breadcrumb_crumb.dart';

/// A row of crumbs from a page's top down to the place shown. Every crumb but
/// the last is a way straight back to the place it names. A long name is cut
/// short, and a trail too long for the width keeps its first crumb and as
/// many of its last as fit, folding the ones between into an ellipsis that
/// leads to the innermost of them.
class CrumbTrail extends StatelessWidget {
  /// The widest a crumb grows before its name ends in an ellipsis.
  static const crumbWidth = 160.0;

  static const _ellipsis = '…';

  /// What the place shown keeps, however narrow: the first crumb gives way
  /// before it does.
  static const _lastMinWidth = 48.0;

  /// From the top down; the last is the place shown.
  final List<String> names;

  /// Drawn before the first crumb.
  final IconData? icon;

  /// Called with the depth of the crumb tapped, never the last.
  final ValueChanged<int> onNavigate;

  /// The widest any one crumb grows; a short trail can lift it.
  final double maxCrumbWidth;

  const CrumbTrail({
    super.key,
    required this.names,
    required this.onNavigate,
    this.icon,
    this.maxCrumbWidth = crumbWidth,
  });

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final style = KalinkaTextStyles.pathLabel;
    final last = names.length - 1;
    const separatorPadding = EdgeInsets.symmetric(horizontal: 2);
    final separator = Padding(
      padding: separatorPadding,
      child: Text('›', style: style.copyWith(color: KalinkaColors.textMuted)),
    );

    Widget crumb(int depth, {String? label, double? maxWidth}) =>
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth ?? maxCrumbWidth),
          child: BreadcrumbCrumb(
            label: label ?? names[depth],
            semanticsLabel: 'Back to ${names[depth]}',
            icon: depth == 0 ? icon : null,
            style: style,
            onTap: depth == last ? null : () => onNavigate(depth),
          ),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        double widthOf(String label, {bool withIcon = false}) =>
            BreadcrumbCrumb.widthOf(
              label,
              style,
              scaler,
              withIcon: withIcon,
            ).clamp(0, maxCrumbWidth);
        final widths = [
          for (var depth = 0; depth <= last; depth++)
            widthOf(names[depth], withIcon: depth == 0 && icon != null),
        ];
        final separatorWidth =
            BreadcrumbCrumb.labelWidth('›', style, scaler) +
            separatorPadding.horizontal;
        final start = foldedTailStart(
          widths,
          separator: separatorWidth,
          ellipsis: widthOf(_ellipsis),
          available: constraints.maxWidth,
        );
        var rest = start > 1 ? separatorWidth + widthOf(_ellipsis) : 0.0;
        for (var depth = start; depth <= last; depth++) {
          rest +=
              separatorWidth +
              (depth == last
                  ? math.min(widths[depth], _lastMinWidth)
                  : widths[depth]);
        }
        final firstWidth = (constraints.maxWidth - rest).clamp(
          0.0,
          maxCrumbWidth,
        );

        return Row(
          children: [
            if (last == 0)
              Flexible(child: crumb(0))
            else
              crumb(0, maxWidth: firstWidth),
            if (start > 1) ...[separator, crumb(start - 1, label: _ellipsis)],
            for (var depth = start; depth <= last; depth++) ...[
              separator,
              if (depth == last)
                Flexible(child: crumb(depth))
              else
                crumb(depth),
            ],
          ],
        );
      },
    );
  }
}

/// The depth from which a trail of crumbs this wide is shown in full, given
/// that its first crumb always stays and every crumb between that and this
/// depth is folded into one [ellipsis] crumb. 1 when nothing need fold.
@visibleForTesting
int foldedTailStart(
  List<double> widths, {
  required double separator,
  required double ellipsis,
  required double available,
}) {
  final last = widths.length - 1;
  final whole =
      widths.fold(0.0, (sum, width) => sum + width) + separator * last;
  if (last < 2 || whole <= available) return 1;

  var room = available - widths.first - widths.last - ellipsis - 2 * separator;
  var start = last;
  while (start > 1 && widths[start - 1] + separator <= room) {
    room -= widths[start - 1] + separator;
    start--;
  }
  return start;
}
