import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/kalinka_player_api_provider.dart';
import '../../providers/toast_provider.dart';
import 'row_circle_button.dart';

/// Plays a whole album, playlist or collection from its first track,
/// replacing the queue. It sits beside the row's way in, so playing never
/// needs opening, and opening never plays.
class RowPlayButton extends ConsumerStatefulWidget {
  final BrowseItem item;
  final FocusNode? focusNode;

  const RowPlayButton({super.key, required this.item, this.focusNode});

  /// The name a container goes by in the row's label and its toasts.
  static String nameOf(BrowseItem item) =>
      item.album?.title ?? item.playlist?.name ?? item.name ?? 'Unknown';

  @override
  ConsumerState<RowPlayButton> createState() => _RowPlayButtonState();
}

class _RowPlayButtonState extends ConsumerState<RowPlayButton> {
  bool _starting = false;

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

  @override
  Widget build(BuildContext context) => RowCircleButton(
    label: 'Play ${RowPlayButton.nameOf(widget.item)}',
    icon: _starting ? Icons.hourglass_empty_rounded : Icons.play_arrow_rounded,
    busy: _starting,
    onTap: _play,
    focusNode: widget.focusNode,
  );
}
