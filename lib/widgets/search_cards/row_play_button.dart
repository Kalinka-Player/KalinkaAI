import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/kalinka_player_api_provider.dart';
import '../../providers/toast_provider.dart';
import '../../theme/app_theme.dart';

/// Plays a whole album, playlist or collection from its first track,
/// replacing the queue. It sits beside the row's way in, so playing never
/// needs opening, and opening never plays. Grey: a shortcut on a row, not the
/// screen's one decision. Hover warms the circle so it reads as its own
/// control rather than as part of the row it sits on.
class RowPlayButton extends ConsumerStatefulWidget {
  final BrowseItem item;

  const RowPlayButton({super.key, required this.item});

  /// The name a container goes by in the row's label and its toasts.
  static String nameOf(BrowseItem item) =>
      item.album?.title ?? item.playlist?.name ?? item.name ?? 'Unknown';

  @override
  ConsumerState<RowPlayButton> createState() => _RowPlayButtonState();
}

class _RowPlayButtonState extends ConsumerState<RowPlayButton> {
  bool _starting = false;
  bool _hovering = false;

  Future<void> _play() async {
    if (_starting) return;
    setState(() => _starting = true);
    final api = ref.read(kalinkaProxyProvider);
    final name = RowPlayButton.nameOf(widget.item);
    await runQueueActivity(
      pending: 'Starting playback…',
      action: () async {
        final added = await api.replace([widget.item.id]);
        await api.play(0);
        return added;
      },
      done: (r) {
        final n = r.count ?? 0;
        return 'Playing $name — $n ${n == 1 ? 'track' : 'tracks'}';
      },
      failed: (e) => 'Failed to play: $e',
    );
    if (mounted) setState(() => _starting = false);
  }

  void _setHover(bool value) {
    if (value == _hovering) return;
    setState(() => _hovering = value);
  }

  @override
  Widget build(BuildContext context) {
    final hot = _hovering && !_starting;

    return MergeSemantics(
      child: Semantics(
        button: true,
        label: 'Play ${RowPlayButton.nameOf(widget.item)}',
        child: SizedBox(
          width: 44,
          height: 48,
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                mouseCursor: WidgetStateMouseCursor.clickable,
                customBorder: const CircleBorder(),
                onTap: _starting ? null : _play,
                onHover: _setHover,
                focusColor: KalinkaColors.surfaceOverlay,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hot
                        ? KalinkaColors.surfaceOverlay
                        : KalinkaColors.surfaceElevated,
                    border: Border.all(
                      color: hot
                          ? KalinkaColors.textMuted
                          : KalinkaColors.borderDefault,
                    ),
                  ),
                  child: Icon(
                    _starting
                        ? Icons.hourglass_empty_rounded
                        : Icons.play_arrow_rounded,
                    size: 18,
                    color: KalinkaColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
