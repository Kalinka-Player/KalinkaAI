import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/search_session_provider.dart';
import '../../providers/selection_state_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/click_cursor.dart';
import 'long_press_ring_painter.dart';
import 'track_row_support.dart';

/// A folder of a file-backed source: its cover — composed from the covers
/// under it — how many tracks it holds, and a tap that shows it in place of
/// the folder it is listed in. It never unrolls. Held, it joins a selection
/// whole, every track below it included; while one is open, a tap toggles it.
class SearchFolderRow extends ConsumerStatefulWidget {
  final BrowseItem item;

  const SearchFolderRow({super.key, required this.item});

  @override
  ConsumerState<SearchFolderRow> createState() => _SearchFolderRowState();
}

class _SearchFolderRowState extends ConsumerState<SearchFolderRow>
    with LongPressRingMixin {
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final subname = item.subname ?? '';
    final selectionMode = ref.watch(
      selectionStateProvider.select((s) => s.isActive),
    );
    final selected = ref.watch(
      selectionStateProvider.select((s) => s.isContainerSelected(item.id)),
    );
    void toggle() =>
        ref.read(selectionStateProvider.notifier).toggleContainer(item.id);

    return Semantics(
      button: true,
      selected: selectionMode ? selected : null,
      label: selectionMode
          ? '${selected ? 'Deselect' : 'Select'} folder ${item.name}'
          : 'Open folder ${item.name}',
      child: MouseRegion(
        cursor: clickCursor(interactive: true),
        child: GestureDetector(
          onTap: () {
            if (selectionMode) {
              toggle();
              return;
            }
            ref.read(searchSessionProvider.notifier).openFolder(item);
          },
          onLongPressStart: selectionMode
              ? null
              : (_) => startLongPressRing(toggle),
          onLongPressEnd: selectionMode ? null : (_) => cancelLongPressRing(),
          onLongPressCancel: selectionMode ? null : cancelLongPressRing,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            color: selected
                ? KalinkaColors.accent.withValues(alpha: 0.07)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 68,
                  height: 68,
                  child: Stack(
                    children: [
                      TrackThumb(item: item, size: 68, radius: 8),
                      const Positioned(
                        right: 4,
                        bottom: 4,
                        child: CornerGlyph(Icons.folder_outlined),
                      ),
                      if (longPressing && longPressProgress > 0)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: LongPressRingPainter(
                              progress: longPressProgress,
                              color: KalinkaColors.accent,
                            ),
                          ),
                        ),
                      if (selected)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: KalinkaColors.accent.withValues(
                                alpha: 0.4,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.name ?? '',
                        style: KalinkaTextStyles.trackRowTitle.copyWith(
                          color: selected ? KalinkaColors.accentTint : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subname.isEmpty ? 'Folder' : 'Folder · $subname',
                        style: KalinkaTextStyles.trackRowSubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: KalinkaColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
