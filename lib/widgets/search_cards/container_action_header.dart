import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/selection_state_provider.dart';
import '../../theme/app_theme.dart';
import '../search/track_group_actions.dart';
import 'track_row_support.dart';

/// Header shown at the top of an unrolled album, playlist or collection: an
/// info line (track count · duration · what a tap does) over the Play all /
/// Enqueue pair, acting on the container as a whole. The same two chips a
/// section of results carries, so one action reads the same everywhere.
///
/// It stays through multi-select: the pair still means the whole container,
/// and a header that came and went would move every row under it. What
/// changes is the line, which reports the tally instead of the tap that no
/// longer plays.
class ContainerActionHeader extends ConsumerWidget {
  /// The album, playlist or collection this header plays/enqueues. It goes to
  /// the server as one id, which the server expands into its tracks.
  final BrowseItem item;

  /// The tracks under this header: how many there are, and which of them a
  /// running selection has taken.
  final List<String> trackIds;

  /// How many the container holds, where the rows under it are only a page of
  /// it. Play all sends the container's id and the server expands the lot, so
  /// the line has to count what will play rather than what is on screen.
  final int? totalTracks;

  final int? totalDurationSeconds;

  /// An action on the container itself rather than on its music, set apart at
  /// the trailing end. A collection puts renaming there.
  final Widget? trailing;

  const ContainerActionHeader({
    super.key,
    required this.item,
    required this.trackIds,
    this.totalTracks,
    this.totalDurationSeconds,
    this.trailing,
  });

  String get _name =>
      item.album?.title ?? item.playlist?.name ?? item.name ?? 'Unknown';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selecting = ref.watch(
      selectionStateProvider.select((s) => s.isActive),
    );
    final taken = ref.watch(
      selectionStateProvider.select((s) => s.selectedWithin(item.id, trackIds)),
    );

    final count = totalTracks ?? trackIds.length;
    final duration = totalDurationSeconds;
    final info = <String>[
      '$count ${count == 1 ? 'track' : 'tracks'}',
      if (duration != null && duration > 0) formatTotalDuration(duration),
      if (selecting) '$taken selected' else 'tap a track to play from there',
    ];

    return SizedBox(
      // The header is content-sized, so without this it would be centred by
      // whatever column holds it rather than starting where the tracks do.
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              info.join(' · '),
              style: KalinkaTextStyles.trackRowSubtitle.copyWith(
                color: KalinkaColors.textMuted,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      PlayAllChip(trackIds: [item.id], trackCount: count),
                      AddAllChip(
                        trackIds: [item.id],
                        trackCount: count,
                        name: _name,
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ],
        ),
      ),
    );
  }
}
