import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state_provider.dart';
import '../providers/connection_state_provider.dart';
import '../providers/kalinka_player_api_provider.dart';
import '../providers/toast_provider.dart';
import '../theme/app_theme.dart';
import 'clear_all_confirm_dialog.dart';
import 'kalinka_bottom_sheet.dart';
import 'kalinka_dialog.dart';
import 'queue_management_tray.dart';
import 'search/add_to_collection_sheet.dart';

/// The queue's ⋮, in the player's header: there while the queue has tracks
/// and the server is reachable.
class QueueMenuButton extends ConsumerWidget {
  const QueueMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasTracks = ref.watch(
      playQueueStateStoreProvider.select((s) => s.trackList.isNotEmpty),
    );
    final connected =
        ref.watch(connectionStateProvider) == ConnectionStatus.connected;
    if (!hasTracks || !connected) return const SizedBox.shrink();
    return Tooltip(
      message: 'Queue options',
      child: Material(
        color: KalinkaColors.surfaceInput,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: const BorderSide(color: KalinkaColors.borderDefault),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showQueueManagementTray(context, ref),
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
      ),
    );
  }
}

/// Opens the queue menu as a bottom sheet and acts on the choice.
Future<void> showQueueManagementTray(
  BuildContext context,
  WidgetRef ref,
) async {
  final action = await showKalinkaBottomSheet<TrayAction>(
    context: context,
    contentBuilder: (_) => const QueueManagementTrayContent(),
  );
  if (action == null || !context.mounted) return;
  await runQueueTrayAction(context, ref, action);
}

/// Carries out a queue menu choice.
Future<void> runQueueTrayAction(
  BuildContext context,
  WidgetRef ref,
  TrayAction action,
) async {
  switch (action) {
    case TrayAction.saveToCollection:
      await saveQueueToCollection(context, ref);
    case TrayAction.clearPlayed:
      await _clearPlayed(ref);
    case TrayAction.clearAll:
      // Let the menu finish closing before the dialog rises.
      await Future.delayed(const Duration(milliseconds: 160));
      if (!context.mounted) return;
      await showKalinkaDialog<bool>(
        context: context,
        builder: (_) =>
            ClearAllConfirmDialog(onConfirmClearAll: () => _clearAll(ref)),
      );
  }
}

/// Opens the destination sheet on the queue as it stands; what becomes of
/// what the chosen collection already holds is decided in there.
Future<void> saveQueueToCollection(BuildContext context, WidgetRef ref) async {
  final tracks = ref.read(playQueueProvider);
  if (tracks.isEmpty) {
    ref.read(toastProvider.notifier).show('Nothing in the queue yet');
    return;
  }
  await showAddToCollectionSheet(
    context,
    CollectionAddition.queue([for (final track in tracks) track.id]),
  );
}

Future<void> _clearPlayed(WidgetRef ref) async {
  final queueState = ref.read(playQueueStateStoreProvider);
  final currentIndex = queueState.playbackState.index ?? 0;
  final api = ref.read(kalinkaProxyProvider);
  final toast = ref.read(toastProvider.notifier);
  for (int i = currentIndex - 1; i >= 0; i--) {
    try {
      await api.remove(i);
    } catch (e) {
      toast.show('Failed to clear played: $e', isError: true);
      return;
    }
  }
  toast.show('Played tracks cleared');
}

Future<void> _clearAll(WidgetRef ref) async {
  final api = ref.read(kalinkaProxyProvider);
  final toast = ref.read(toastProvider.notifier);
  await api.clear();
  toast.show('Queue cleared');
}
