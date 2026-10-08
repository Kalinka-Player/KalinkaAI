import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/collections_provider.dart';
import '../../providers/kalinka_player_api_provider.dart';
import '../../providers/toast_provider.dart';
import '../search_cards/action_pill_button.dart';
import 'add_to_collection_sheet.dart';

/// Offers an empty collection the queue as it stands: one tap adds every
/// queued track in playing order, with no sheet, since the destination and
/// the terms are already settled. Hidden while the queue is empty.
class AddQueueChip extends ConsumerStatefulWidget {
  final BrowseItem item;

  const AddQueueChip({super.key, required this.item});

  @override
  ConsumerState<AddQueueChip> createState() => _AddQueueChipState();
}

class _AddQueueChipState extends ConsumerState<AddQueueChip> {
  /// Stays set once the write lands: the rows replace the chip, and a second
  /// tap must not add again meanwhile.
  bool _busy = false;

  String get _name =>
      widget.item.playlist?.name ?? widget.item.name ?? 'the collection';

  Future<void> _add(List<String> trackIds) async {
    if (_busy) return;
    setState(() => _busy = true);
    // Read before the await: the row may be gone by the time the write lands.
    final api = ref.read(kalinkaProxyProvider);
    final toast = ref.read(toastProvider.notifier);
    final revision = ref.read(collectionsRevisionProvider.notifier);
    try {
      final outcome = await api.addToCollection(widget.item.id, trackIds);
      // Every write bumps the revision; everything showing the collection
      // follows.
      revision.bump();
      toast.show(collectionAddReport(_name, outcome, created: false));
    } catch (e) {
      toast.show('Could not add to $_name: $e', isError: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final queued = ref.watch(playQueueProvider);
    if (queued.isEmpty) return const SizedBox.shrink();
    final n = queued.length;
    return ActionPillButton(
      label: 'Add $n ${n == 1 ? 'track' : 'tracks'} from the queue',
      icon: Icons.playlist_add_rounded,
      accent: true,
      enabled: !_busy,
      onTap: () => _add([for (final track in queued) track.id]),
      semanticsLabel: 'Add the play queue to $_name',
    );
  }
}
