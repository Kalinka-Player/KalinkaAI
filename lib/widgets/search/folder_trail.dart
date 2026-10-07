import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/search_session_provider.dart';
import '../../theme/app_theme.dart';
import '../breadcrumb_crumb.dart';

/// The breadcrumb over a page of folders, held under the title bar while the
/// folder scrolls: the page itself, then each folder down to the one shown.
/// Every crumb but the last is a way straight back to the folder it names. A
/// long folder name is cut short, and a trail too long for the width keeps
/// its first crumb and as many of its last as fit, folding the folders
/// between into an ellipsis that leads to the innermost of them.
class FolderTrail extends ConsumerWidget {
  /// The widest a crumb grows before its name ends in an ellipsis.
  static const crumbWidth = 160.0;

  static const _inset = 9.0;
  static const _ellipsis = '…';

  const FolderTrail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(searchSessionProvider.select((s) => s.folderPath));
    final top = ref.watch(
      searchSessionProvider.select((s) => s.catalogPage.title),
    );
    final notifier = ref.read(searchSessionProvider.notifier);
    final scaler = MediaQuery.textScalerOf(context);
    final style = KalinkaTextStyles.pathLabel;
    final names = [
      top ?? 'Home',
      for (final folder in path) folder.title ?? '',
    ];
    final last = names.length - 1;
    const separatorPadding = EdgeInsets.symmetric(horizontal: 2);
    final separator = Padding(
      padding: separatorPadding,
      child: Text('›', style: style.copyWith(color: KalinkaColors.textMuted)),
    );

    Widget crumb(int depth, {String? label}) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: crumbWidth),
      child: BreadcrumbCrumb(
        label: label ?? names[depth],
        semanticsLabel: 'Back to ${names[depth]}',
        icon: depth == 0 ? Icons.folder_outlined : null,
        style: style,
        onTap: depth == last ? null : () => notifier.showFolderAt(depth),
      ),
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: KalinkaColors.borderSubtle)),
      ),
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _inset),
          child: LayoutBuilder(
            builder: (context, constraints) {
              double widthOf(String label, {bool withIcon = false}) =>
                  BreadcrumbCrumb.widthOf(
                    label,
                    style,
                    scaler,
                    withIcon: withIcon,
                  ).clamp(0, crumbWidth);
              final start = foldedTailStart(
                [
                  for (var depth = 0; depth <= last; depth++)
                    widthOf(names[depth], withIcon: depth == 0),
                ],
                separator:
                    BreadcrumbCrumb.labelWidth('›', style, scaler) +
                    separatorPadding.horizontal,
                ellipsis: widthOf(_ellipsis),
                available: constraints.maxWidth,
              );

              return Row(
                children: [
                  if (last == 0) Flexible(child: crumb(0)) else crumb(0),
                  if (start > 1) ...[
                    separator,
                    crumb(start - 1, label: _ellipsis),
                  ],
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
          ),
        ),
      ),
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
