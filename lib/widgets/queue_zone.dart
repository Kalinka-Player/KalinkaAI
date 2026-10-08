import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data_model/data_model.dart';
import '../data_model/kalinka_ws_api.dart' show QueueCommand;
import '../providers/app_state_provider.dart';
import '../providers/connection_state_provider.dart';
import '../providers/kalinka_ws_api_provider.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';
import 'empty_queue_state.dart';
import 'exclusive_queue_card.dart';
import 'queue_item_row.dart';
import 'queue_section_header.dart';
import 'search_cards/action_pill_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

/// Height of the pinned section header.
const double _kHeaderHeight = QueueSectionHeader.height;

/// The saved queue while a plugin plays: set back, yet not as far as the
/// offline queue, since it can still be edited and played from.
const double _kNotPlayingOpacity = 0.6;

// ─────────────────────────────────────────────────────────────────────────────
// QueueZone
// ─────────────────────────────────────────────────────────────────────────────

/// The main queue content area, split into "Up next" and "Previously played".
///
/// While a plugin plays exclusively the queue is not playing: it is shown whole
/// and in order under a card naming the plugin, with a way to play it again.
class QueueZone extends ConsumerStatefulWidget {
  final double bottomPadding;
  final bool isTablet;
  final VoidCallback? onOpenManagementTray;

  const QueueZone({
    super.key,
    this.bottomPadding = 72,
    this.isTablet = false,
    this.onOpenManagementTray,
  });

  @override
  ConsumerState<QueueZone> createState() => _QueueZoneState();
}

class _QueueZoneState extends ConsumerState<QueueZone> {
  // ── Scroll ────────────────────────────────────────────────────────────────
  final _scrollController = ScrollController();

  // ── Drag state ────────────────────────────────────────────────────────────
  bool _isDragging = false;

  // ── Live references (updated each build, used by reorder callback) ────────
  int _currentIndex = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ── Management tray ───────────────────────────────────────────────────────

  /// The tray is a bottom sheet on phone and a panel overlay on tablet; both
  /// are hosted by the screen (the tablet overlay must cover the search dock),
  /// so this just forwards to it.
  void _openManagementTray() => widget.onOpenManagementTray?.call();

  // ── Reorder ───────────────────────────────────────────────────────────────

  // onReorderItem delivers newIndex as the final position (already adjusted
  // for the removal) and only fires when the position actually changed.
  void _onReorderItem(int oldIndex, int newIndex) {
    final from = _currentIndex + oldIndex;
    final to = _currentIndex + newIndex;

    ref
        .read(playQueueStateStoreProvider.notifier)
        .optimisticallyReorder(from, to);
    ref
        .read(kalinkaWsApiProvider)
        .sendQueueCommand(QueueCommand.move(fromIndex: from, toIndex: to));
    KalinkaHaptics.lightImpact();
  }

  Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = Curves.easeOut.transform(animation.value);
        return Transform.scale(
          scale: 1.0 + 0.04 * t,
          child: Material(
            elevation: 12 * t,
            shadowColor: Colors.black54,
            borderRadius: BorderRadius.circular(6),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final queueSnapshot = ref.watch(
      playQueueStateStoreProvider.select(
        (s) => (
          trackList: s.trackList,
          playbackIndex: s.playbackState.index ?? 0,
          shuffleEnabled: s.playbackMode.shuffle,
        ),
      ),
    );
    final trackList = queueSnapshot.trackList;
    final playbackIndex = queueSnapshot.playbackIndex;
    final currentIndex = playbackIndex.clamp(0, trackList.length);
    final shuffleEnabled = queueSnapshot.shuffleEnabled;
    final connectionState = ref.watch(connectionStateProvider);
    final control = ref.watch(playbackControlProvider);

    final isOfflineOrNone =
        connectionState == ConnectionStatus.offline ||
        connectionState == ConnectionStatus.none;
    final isOffline =
        connectionState == ConnectionStatus.reconnecting ||
        connectionState == ConnectionStatus.offline;

    if (control.isExclusive) {
      // The saved queue is listed from its start, so reorder indices are
      // already absolute.
      _currentIndex = 0;
      return _buildExclusive(
        control,
        trackList,
        isOffline: isOffline,
        isOfflineOrNone: isOfflineOrNone,
      );
    }

    final upNextTracks = currentIndex < trackList.length
        ? trackList.sublist(currentIndex).cast<Track>()
        : <Track>[];
    final previousTracks = currentIndex > 0
        ? trackList.sublist(0, currentIndex).cast<Track>().reversed.toList()
        : <Track>[];

    final nowPlayingTrack = upNextTracks.isNotEmpty ? upNextTracks[0] : null;
    final queueTracks = upNextTracks.length > 1
        ? upNextTracks.sublist(1).cast<Track>()
        : <Track>[];

    // Keep live reference for reorder callback.
    // Queue section starts one past the currently playing track.
    _currentIndex = currentIndex + 1;

    final isQueueEmpty = upNextTracks.isEmpty && previousTracks.isEmpty;

    if (isQueueEmpty) {
      return EmptyQueueState(isOffline: isOfflineOrNone);
    }

    if (connectionState == ConnectionStatus.none) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        if (isOffline)
          // No Expanded here: this Stack child must size from the Stack's
          // constraints (like the connected branch below). Expanded inside a
          // Stack applies FlexParentData to a RenderStack child and throws at
          // layout — in release that renders as a gray ErrorWidget.
          IgnorePointer(
            child: Opacity(
              opacity: 0.4,
              child: _buildQueueContent(
                nowPlayingTrack,
                queueTracks,
                previousTracks,
                currentIndex,
                shuffleEnabled,
              ),
            ),
          )
        else
          _buildQueueContent(
            nowPlayingTrack,
            queueTracks,
            previousTracks,
            currentIndex,
            shuffleEnabled,
          ),

        // Floating menu button — always sits in the pinned header area.
        if (!isOffline)
          Positioned(
            top: (_kHeaderHeight - 36) / 2,
            right: 20,
            child: _buildMenuButton(),
          ),
      ],
    );
  }

  Widget _buildExclusive(
    PlaybackControl control,
    List<Track> trackList, {
    required bool isOffline,
    required bool isOfflineOrNone,
  }) {
    final Widget list;
    if (trackList.isEmpty) {
      list = EmptyQueueState(isOffline: isOfflineOrNone);
    } else if (isOffline) {
      list = IgnorePointer(
        child: Opacity(opacity: 0.4, child: _buildSavedQueue(trackList)),
      );
    } else {
      list = Opacity(
        opacity: _kNotPlayingOpacity,
        child: _buildSavedQueue(trackList),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExclusiveQueueCard(control: control),
        _SavedQueueHeader(
          trackCount: trackList.length,
          onPlay: trackList.isEmpty || isOffline ? null : _playQueue,
          menuButton: isOffline ? null : _buildMenuButton(),
        ),
        Expanded(child: list),
      ],
    );
  }

  /// The queue takes the output back and plays from its current track.
  void _playQueue() {
    ref.read(kalinkaWsApiProvider).sendQueueCommand(const QueueCommand.play());
  }

  Widget _buildSavedQueue(List<Track> trackList) {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverReorderableList(
          itemCount: trackList.length,
          onReorderItem: _onReorderItem,
          onReorderStart: (i) => setState(() => _isDragging = true),
          onReorderEnd: (i) => setState(() => _isDragging = false),
          proxyDecorator: _proxyDecorator,
          itemBuilder: (context, i) {
            final track = trackList[i];
            return QueueItemRow(
              key: ValueKey('saved_${track.id}'),
              track: track,
              index: i,
              displayIndex: i,
              isDragging: _isDragging,
            );
          },
        ),
        SliverPadding(
          padding: EdgeInsets.only(bottom: widget.bottomPadding + 16),
        ),
      ],
    );
  }

  Widget _buildMenuButton() {
    return Material(
      color: KalinkaColors.surfaceInput,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: const BorderSide(color: KalinkaColors.borderDefault),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openManagementTray,
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return Colors.white.withValues(alpha: 0.08);
          }
          return null;
        }),
        child: const SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            Icons.more_vert,
            size: 16,
            color: KalinkaColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildQueueContent(
    Track? nowPlayingTrack,
    List<Track> queueTracks,
    List<Track> previousTracks,
    int currentIndex,
    bool shuffleEnabled,
  ) {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // ── NOW PLAYING ────────────────────────────────────────────────────
        if (nowPlayingTrack != null)
          SliverMainAxisGroup(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: const _NowPlayingHeaderDelegate(),
              ),
              SliverToBoxAdapter(
                child: QueueItemRow(
                  key: ValueKey('nowplaying_${nowPlayingTrack.id}'),
                  track: nowPlayingTrack,
                  index: currentIndex,
                  displayIndex: 0,
                  isCurrentTrack: true,
                  showDragHandle: false,
                  isDragging: _isDragging,
                ),
              ),
            ],
          ),

        // ── UP NEXT ────────────────────────────────────────────────────────
        SliverMainAxisGroup(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _UpNextHeaderDelegate(
                trackCount: queueTracks.length,
                showShuffleBadge: shuffleEnabled,
              ),
            ),
            if (queueTracks.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  child: Text(
                    'Queue is empty',
                    style: KalinkaTextStyles.queueItemArtist,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              SliverReorderableList(
                itemCount: queueTracks.length,
                onReorderItem: _onReorderItem,
                onReorderStart: (i) => setState(() => _isDragging = true),
                onReorderEnd: (i) => setState(() => _isDragging = false),
                proxyDecorator: _proxyDecorator,
                itemBuilder: (context, i) {
                  final track = queueTracks[i];
                  final absoluteIndex = currentIndex + 1 + i;
                  return QueueItemRow(
                    key: ValueKey('upnext_${track.id}'),
                    track: track,
                    index: absoluteIndex,
                    displayIndex: i,
                    isDragging: _isDragging,
                    upNextCount: queueTracks.length,
                  );
                },
              ),
            if (previousTracks.isNotEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(color: Color(0x26FFFFFF)),
                ),
              ),
          ],
        ),

        // ── PREVIOUSLY PLAYED ──────────────────────────────────────────────
        if (previousTracks.isNotEmpty)
          SliverMainAxisGroup(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: const _HistoryHeaderDelegate(),
              ),
              SliverList.builder(
                itemCount: previousTracks.length,
                itemBuilder: (context, i) {
                  final track = previousTracks[i];
                  final queueIndex = currentIndex - 1 - i;
                  return QueueItemRow(
                    key: ValueKey('history_${track.id}_$i'),
                    track: track,
                    index: queueIndex,
                    displayIndex: i,
                    isHistory: true,
                    isDragging: _isDragging,
                  );
                },
              ),
            ],
          ),

        // Bottom padding
        SliverPadding(
          padding: EdgeInsets.only(bottom: widget.bottomPadding + 16),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SavedQueueHeader — heads Kalinka's queue while a plugin plays exclusively.
// ─────────────────────────────────────────────────────────────────────────────

class _SavedQueueHeader extends StatelessWidget {
  final int trackCount;

  /// Plays the queue; null when there is nothing to play or no connection.
  final VoidCallback? onPlay;
  final Widget? menuButton;

  const _SavedQueueHeader({
    required this.trackCount,
    required this.onPlay,
    required this.menuButton,
  });

  @override
  Widget build(BuildContext context) {
    final count = switch (trackCount) {
      0 => 'No tracks',
      1 => '1 track',
      _ => '$trackCount tracks',
    };
    final onPlay = this.onPlay;
    final menuButton = this.menuButton;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'SAVED KALINKA QUEUE',
                  style: KalinkaTextStyles.sectionHeader,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$count · Not playing',
                  style: KalinkaTextStyles.trackCountBadge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onPlay != null) ...[
            const SizedBox(width: 12),
            ActionPillButton(
              label: 'Play queue',
              icon: Icons.play_arrow_rounded,
              accent: true,
              onTap: onPlay,
            ),
          ],
          if (menuButton != null) ...[const SizedBox(width: 8), menuButton],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _UpNextHeaderDelegate — pinned "UP NEXT" header.
//
// This header keeps full height while scrolling the UP NEXT section, and then
// yields the pinned slot as the PREVIOUSLY PLAYED section reaches the top.
// ─────────────────────────────────────────────────────────────────────────────

class _UpNextHeaderDelegate extends SliverPersistentHeaderDelegate {
  final int trackCount;
  final bool showShuffleBadge;

  const _UpNextHeaderDelegate({
    required this.trackCount,
    required this.showShuffleBadge,
  });

  @override
  double get minExtent => _kHeaderHeight;

  @override
  double get maxExtent => _kHeaderHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final hasRows = trackCount > 0;
    return SizedBox(
      height: _kHeaderHeight,
      child: ColoredBox(
        color: KalinkaColors.background,
        child: Stack(
          children: [
            QueueSectionHeader(
              label: 'UP NEXT',
              trackCount: trackCount,
              showShuffleBadge: showShuffleBadge,
            ),
            // Continuation of the now-playing accent bar. Solid through the
            // header when at least one UP NEXT row exists; otherwise the fade
            // happens inside the header (end of UP NEXT == end of bar).
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: SizedBox(
                  width: 4,
                  child: hasRows
                      ? const ColoredBox(color: KalinkaColors.accentBorder)
                      : const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                KalinkaColors.accentBorder,
                                Color(0x00C2394B),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_UpNextHeaderDelegate old) =>
      trackCount != old.trackCount || showShuffleBadge != old.showShuffleBadge;
}

// ─────────────────────────────────────────────────────────────────────────────
// _NowPlayingHeaderDelegate — pinned "NOW PLAYING" header.
// ─────────────────────────────────────────────────────────────────────────────

class _NowPlayingHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _NowPlayingHeaderDelegate();

  @override
  double get minExtent => _kHeaderHeight;

  @override
  double get maxExtent => _kHeaderHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return const SizedBox(
      height: _kHeaderHeight,
      child: ColoredBox(
        color: KalinkaColors.background,
        child: _NowPlayingHeaderContent(),
      ),
    );
  }

  @override
  bool shouldRebuild(_NowPlayingHeaderDelegate old) => false;
}

/// Header label + format suffix for the NOW PLAYING section.
///
/// The label tracks the player state: PLAYING / PAUSED / READY / CAN'T PLAY.
/// Buffering never replaces the label — it holds the last stable value so the
/// header doesn't strobe on a flaky connection. A failed track does show,
/// because it persists until someone acts on it, and it is the one state the
/// transport controls deliberately don't advertise.
class _NowPlayingHeaderContent extends ConsumerStatefulWidget {
  const _NowPlayingHeaderContent();

  @override
  ConsumerState<_NowPlayingHeaderContent> createState() =>
      _NowPlayingHeaderContentState();
}

class _NowPlayingHeaderContentState
    extends ConsumerState<_NowPlayingHeaderContent> {
  String _label = 'NOW PLAYING';

  String? _labelFor(PlayerStateType? state) {
    switch (state) {
      case PlayerStateType.playing:
        return 'NOW PLAYING';
      case PlayerStateType.paused:
        return 'PAUSED';
      case PlayerStateType.stopped:
        return 'READY';
      case PlayerStateType.error:
        return "CAN'T PLAY";
      case PlayerStateType.buffering:
      case null:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = ref.watch(
      playerStateProvider.select(
        (s) => (
          state: s.state,
          mimeType: s.mimeType,
          bitsPerSample: s.audioInfo?.bitsPerSample ?? 0,
          sampleRate: s.audioInfo?.sampleRate ?? 0,
        ),
      ),
    );

    final candidate = _labelFor(fmt.state);
    if (candidate != null) {
      _label = candidate;
    }

    return QueueSectionHeader(
      label: _label,
      suffix: _buildFormatSuffix(
        mimeType: fmt.mimeType,
        bitsPerSample: fmt.bitsPerSample,
        sampleRate: fmt.sampleRate,
      ),
    );
  }
}

/// Builds "FLAC 24-bit · 96 kHz" (or any subset of those parts) from the live
/// playback state. Returns null when nothing meaningful is known yet.
String? _buildFormatSuffix({
  required String? mimeType,
  required int bitsPerSample,
  required int sampleRate,
}) {
  String? mime;
  if (mimeType != null) {
    if (mimeType.contains('flac')) {
      mime = 'FLAC';
    } else if (mimeType.contains('wav')) {
      mime = 'WAV';
    } else if (mimeType.contains('mp3') || mimeType.contains('mpeg')) {
      mime = 'MP3';
    } else if (mimeType.contains('aac')) {
      mime = 'AAC';
    } else if (mimeType.contains('opus')) {
      mime = 'OPUS';
    } else if (mimeType.contains('ogg')) {
      mime = 'OGG';
    } else if (mimeType.isNotEmpty) {
      mime = mimeType.split('/').last.toUpperCase();
    }
  }

  final parts = <String>[];
  if (mime != null) {
    parts.add(bitsPerSample > 0 ? '$mime $bitsPerSample-bit' : mime);
  } else if (bitsPerSample > 0) {
    parts.add('$bitsPerSample-bit');
  }
  if (sampleRate > 0) {
    final khz = sampleRate / 1000;
    final khzLabel = sampleRate % 1000 == 0
        ? khz.toStringAsFixed(0)
        : khz.toStringAsFixed(1);
    parts.add('$khzLabel kHz');
  }
  return parts.isEmpty ? null : parts.join(' · ');
}

// ─────────────────────────────────────────────────────────────────────────────
// _HistoryHeaderDelegate — pinned "PREVIOUSLY PLAYED" header.
//
// Fixed minExtent=maxExtent=_kHeaderHeight.
// ─────────────────────────────────────────────────────────────────────────────

class _HistoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _HistoryHeaderDelegate();

  @override
  double get minExtent => _kHeaderHeight;

  @override
  double get maxExtent => _kHeaderHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox(
      height: _kHeaderHeight,
      child: ColoredBox(
        color: KalinkaColors.background,
        child: const QueueSectionHeader(label: 'PREVIOUSLY PLAYED'),
      ),
    );
  }

  @override
  bool shouldRebuild(_HistoryHeaderDelegate old) => false;
}
