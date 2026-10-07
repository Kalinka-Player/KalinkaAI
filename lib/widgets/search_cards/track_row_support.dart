import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/kalinka_player_api_provider.dart';
import '../../providers/toast_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';
import '../../utils/play_next.dart';
import '../now_playing_bars.dart';
import '../procedural_album_art.dart';

/// Shared behaviour for the search-result row widgets (album / artist /
/// playlist / track). These rows were originally copy-pasted per entity type;
/// the genuinely identical logic lives here so the per-type widgets only carry
/// what actually differs (their layout).

/// The cover a track row leads with: what the item carries, and the
/// generated stand-in where it carries none or the fetch fails.
class TrackThumb extends ConsumerWidget {
  final BrowseItem item;
  final double size;
  final double radius;

  const TrackThumb({
    super.key,
    required this.item,
    this.size = 44,
    this.radius = 6,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path =
        item.image?.small ?? item.image?.thumbnail ?? item.image?.large;
    final stand = ProceduralAlbumArt(trackId: item.id, size: size);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: path == null
          ? stand
          : Image.network(
              ref.read(urlResolverProvider).abs(path),
              width: size,
              height: size,
              cacheWidth: (size * 3).round(),
              cacheHeight: (size * 3).round(),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, __, ___) => stand,
            ),
    );
  }
}

/// The small mark in a row thumbnail's corner that says what kind of thing
/// the art stands for — a playlist, a catalog, a folder.
class CornerGlyph extends StatelessWidget {
  final IconData icon;

  const CornerGlyph(this.icon, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, size: 11, color: Colors.white),
    );
  }
}

/// The mark a name hit earns when it is the query itself, word for word.
/// Shown above the title, so the eye lands on why this row leads.
class MatchBadge extends StatelessWidget {
  const MatchBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: KalinkaColors.accentSubtle,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: KalinkaColors.accentBorder),
      ),
      child: Text(
        'EXACT NAME',
        style: KalinkaFonts.mono(
          fontSize: KalinkaTypography.baseSize - 3,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: KalinkaColors.accentTint,
        ),
      ),
    );
  }
}

/// A track row's trailing end: the now-playing bars when this is the track
/// in the player, then the duration.
class TrackRowTrailing extends StatelessWidget {
  final String? duration;
  final bool current;

  const TrackRowTrailing({
    super.key,
    required this.duration,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (current) const NowPlayingBars(),
        if (current && duration != null) const SizedBox(width: 8),
        if (duration != null)
          Text(duration!, style: KalinkaTextStyles.trackRowSubtitle),
      ],
    );
  }
}

/// The badge slot above a row's title: the mark and its gap for an exact
/// hit, nothing otherwise.
List<Widget> matchBadge(BrowseItem item) => item.match?.tier == MatchTier.exact
    ? const [
        Align(alignment: Alignment.centerLeft, child: MatchBadge()),
        SizedBox(height: 3),
      ]
    : const [];

/// Subtitle span with a bold entity-type prefix — "Track · artist · album",
/// "Album · 2019 · 12 tracks", "Artist · 4 albums" — so the tile types are
/// tellable apart at a glance. [rest] may be empty, leaving just the type.
TextSpan entityTypeSubtitle(String type, String rest) {
  return TextSpan(
    style: KalinkaTextStyles.trackRowSubtitle,
    children: [
      TextSpan(
        text: type,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      if (rest.isNotEmpty) TextSpan(text: ' · $rest'),
    ],
  );
}

/// Formats a container's total length in seconds as e.g. `34 min` or
/// `1 hr 12 min`, for the unrolled album/playlist info line.
String formatTotalDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return m > 0 ? '$h hr $m min' : '$h hr';
  if (m > 0) return '$m min';
  return '$seconds sec';
}

/// Formats a track length given in milliseconds as `m:ss` (e.g. `3:07`).
/// Returns null when [ms] is null so callers can omit the duration entirely.
String? formatTrackDuration(int? ms) {
  if (ms == null) return null;
  final seconds = ms ~/ 1000;
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Single-track queue actions shared by the search rows. These are extension
/// methods on [ConsumerState] (rather than free functions) so they can reuse
/// [runQueueActivity], which keeps the toast alive even if the row is disposed
/// mid-request.
extension TrackRowQueueActions<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  /// Adds a single track [item] to the end of the play queue, with the
  /// standard pending/done/failed toast feedback.
  Future<void> addTrackToQueue(BrowseItem item) async {
    final api = ref.read(kalinkaProxyProvider);
    final title = item.track?.title ?? item.name ?? 'track';
    await runQueueActivity(
      pending: 'Adding to queue…',
      action: () => api.add([item.id]),
      done: (_) => '"$title" added to queue',
      failed: (e) => 'Failed to add: $e',
    );
  }

  /// Inserts a single track [item] immediately after the current track.
  Future<void> playTrackNext(BrowseItem item) async {
    final api = ref.read(kalinkaProxyProvider);
    final title = item.track?.title ?? item.name ?? 'track';
    final insertIndex = playNextInsertIndex(ref);
    await runQueueActivity(
      pending: 'Queueing next…',
      action: () => api.add([item.id], index: insertIndex),
      done: (_) => '"$title" playing next',
      failed: (e) => 'Failed to add: $e',
    );
  }
}

/// Drives the radial "hold to multi-select" ring shared by every search row.
///
/// The ring fills over ~500ms; on completion it fires a medium haptic and
/// invokes the caller-supplied action (which selection it triggers differs per
/// row — container vs. single track vs. enter-mode). Mix this into a [State]
/// and render the ring from [longPressProgress].
mixin LongPressRingMixin<T extends StatefulWidget> on State<T> {
  bool longPressing = false;
  double longPressProgress = 0.0;
  Timer? _longPressTimer;

  void startLongPressRing(VoidCallback onComplete) {
    longPressing = true;
    longPressProgress = 0.0;
    _longPressTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted || !longPressing) {
        timer.cancel();
        if (mounted) setState(() => longPressProgress = 0.0);
        return;
      }
      setState(() {
        longPressProgress = min(1.0, longPressProgress + 16 / 500);
      });
      if (longPressProgress >= 1.0) {
        timer.cancel();
        KalinkaHaptics.mediumImpact();
        if (!mounted) return;
        onComplete();
        if (!mounted) return;
        setState(() {
          longPressing = false;
          longPressProgress = 0.0;
        });
      }
    });
  }

  void cancelLongPressRing() {
    longPressing = false;
    _longPressTimer?.cancel();
    if (mounted) setState(() => longPressProgress = 0.0);
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }
}
