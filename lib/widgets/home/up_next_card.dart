import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/source_modules_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../now_playing_bars.dart';
import '../procedural_album_art.dart';
import '../search_cards/track_row_support.dart' show formatTotalDuration;
import '../shelf_heading.dart';

/// How many of the queue's rows Home shows, the playing one included.
const _kPeekRows = 3;

/// Home's view of the queue: what plays now and what follows, each opening
/// the player on its queue. Absent while the queue is empty.
class UpNextCard extends ConsumerWidget {
  final VoidCallback onOpenQueue;

  const UpNextCard({super.key, required this.onOpenQueue});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The list's identity changes only with the queue, never with playback
    // position, so progress ticks leave Home alone.
    final queue = ref.watch(
      playQueueStateStoreProvider.select(
        (s) => (tracks: s.trackList, index: s.playbackState.index ?? 0),
      ),
    );
    final control = ref.watch(playbackControlProvider);
    final tracks = queue.tracks;
    if (tracks.isEmpty) return const SizedBox.shrink();

    final current = queue.index.clamp(0, tracks.length);
    final remaining = tracks.sublist(current);
    final seconds = remaining.fold<int>(0, (sum, t) => sum + t.duration);
    final count = remaining.length == 1
        ? '1 track'
        : '${remaining.length} tracks';

    final Widget body;
    if (control.isExclusive) {
      body = _Note(_onHoldText(ref, control));
    } else if (remaining.isEmpty) {
      body = const _Note('Everything in the queue has played.');
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < remaining.length && i < _kPeekRows; i++)
            _PeekRow(track: remaining[i], playing: i == 0, onTap: onOpenQueue),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShelfHeading(
            title: 'UP NEXT',
            subtitle: remaining.isEmpty || control.isExclusive
                ? null
                : seconds > 0
                ? '$count · ${formatTotalDuration(seconds)}'
                : count,
            onViewAll: onOpenQueue,
            viewAllLabel: 'QUEUE',
          ),
          const SizedBox(height: 10),
          body,
        ],
      ),
    );
  }

  String _onHoldText(WidgetRef ref, PlaybackControl control) {
    final source = ref.watch(sourceDisplayInfoProvider)[control.pluginId];
    final appName = source?.title ?? control.title ?? 'another app';
    return 'Your queue is on hold while $appName plays.';
  }
}

class _Note extends StatelessWidget {
  final String text;

  const _Note(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: KalinkaTextStyles.trackRowSubtitle);
  }
}

class _PeekRow extends ConsumerWidget {
  final Track track;
  final bool playing;
  final VoidCallback onTap;

  const _PeekRow({
    required this.track,
    required this.playing,
    required this.onTap,
  });

  static const double _art = 44;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = track.album?.image;
    final path = image?.small ?? image?.thumbnail ?? image?.large;
    final url = path == null ? null : ref.read(urlResolverProvider).abs(path);
    final fallback = ProceduralAlbumArt(trackId: track.id, size: _art);
    final cacheSize = (_art * MediaQuery.devicePixelRatioOf(context)).round();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox.square(
                dimension: _art,
                child: url == null
                    ? fallback
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        cacheWidth: cacheSize,
                        errorBuilder: (_, _, _) => fallback,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.title,
                    style: KalinkaTextStyles.trackRowTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.performer?.name ?? 'Unknown Artist',
                    style: KalinkaTextStyles.trackRowSubtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (playing) ...[const SizedBox(width: 12), const NowPlayingBars()],
          ],
        ),
      ),
    );
  }
}
