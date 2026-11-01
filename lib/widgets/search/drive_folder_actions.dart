import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/storage.dart';
import '../../providers/kalinka_player_api_provider.dart';
import '../../providers/restart_provider.dart';
import '../../providers/search_session_provider.dart';
import '../../providers/storage_volumes_provider.dart';
import '../../providers/toast_provider.dart';
import '../../theme/app_theme.dart';
import '../demo_read_only_dialog.dart';
import '../kalinka_button.dart';
import '../kalinka_dialog.dart';
import '../struck_icon.dart';

/// Where a Drives page is on storage, asked again as the volumes change.
/// Null for a page that is not a folder of a volume, and on an older server.
final driveLocationProvider = FutureProvider.autoDispose
    .family<StorageLocation?, String>((ref, entityId) async {
      ref.watch(storageVolumesProvider.select((v) => v.value));
      try {
        return await ref.read(kalinkaProxyProvider).storageLocation(entityId);
      } catch (_) {
        return null;
      }
    });

/// A Drives folder's own actions, icons beside Play all as Pin is: add it to
/// the library or, struck through, take it out again, and eject at the top
/// of a removable drive.
class DriveFolderActions extends ConsumerWidget {
  final String entityId;
  final String title;

  const DriveFolderActions({
    super.key,
    required this.entityId,
    required this.title,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(driveLocationProvider(entityId)).value;
    if (location == null) return const SizedBox.shrink();
    final volumes = ref.watch(storageVolumesProvider).value ?? const [];
    StorageVolume? volume;
    for (final v in volumes) {
      if (v.id == location.volumeId) volume = v;
    }
    final library = location.library;
    final ejectable =
        location.subpath.isEmpty && (volume?.isRemovable ?? false);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (library != null)
          IconButton(
            key: const ValueKey('drive-library'),
            tooltip: !library.holds
                ? 'Add to ${library.title}'
                : library.removable
                ? 'Remove from ${library.title}'
                : 'In ${library.title} with a folder above it',
            iconSize: 20,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            isSelected: library.holds,
            icon: const Icon(Icons.library_add_outlined),
            selectedIcon: const StruckIcon(Icons.library_add_outlined),
            onPressed: !library.holds || library.removable
                ? () => _change(context, ref, library)
                : null,
          ),
        if (ejectable)
          IconButton(
            key: const ValueKey('drive-eject'),
            tooltip: 'Eject ${volume!.label}',
            iconSize: 20,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.eject_outlined),
            onPressed: () => _eject(context, ref, volume!),
          ),
      ],
    );
  }

  /// Adds the folder to [library], or takes it out of the library holding it.
  Future<void> _change(
    BuildContext context,
    WidgetRef ref,
    LocationLibrary library,
  ) async {
    final adding = !library.holds;
    if (await refusedAsDemo(context, ref)) return;
    if (!context.mounted) return;
    final confirmed = await showKalinkaDialog<bool>(
      context: context,
      builder: (_) =>
          LibraryChangeDialog(folder: title, library: library, adding: adding),
    );
    if (confirmed != true || !context.mounted) return;
    final api = ref.read(kalinkaProxyProvider);
    final toast = ref.read(toastProvider.notifier);
    final restart = ref.read(restartProvider.notifier);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final result = adding
          ? await api.adoptStorage(entityId)
          : await api.releaseStorage(entityId);
      container.invalidate(driveLocationProvider(entityId));
      if (result.restartRequired) {
        try {
          await api.restartServer();
        } catch (_) {
          // The server may close the connection as it goes down.
        }
        await restart.followRestart(
          subtitle: adding
              ? 'Adding $title to ${library.title}…'
              : 'Taking $title out of ${library.title}…',
        );
      } else {
        toast.show(
          adding
              ? 'Added to ${library.title}'
              : 'Removed from ${library.title}',
        );
      }
    } catch (e) {
      toast.show('$e'.replaceFirst('Exception: ', ''), isError: true);
    }
  }

  Future<void> _eject(
    BuildContext context,
    WidgetRef ref,
    StorageVolume volume,
  ) async {
    if (await refusedAsDemo(context, ref)) return;
    if (!context.mounted) return;
    final toast = ref.read(toastProvider.notifier);
    final session = ref.read(searchSessionProvider.notifier);
    try {
      await ref.read(kalinkaProxyProvider).ejectVolume(volume.id);
      session.closeStorageSources();
      toast.show('${volume.label} can be unplugged');
    } catch (e) {
      toast.show('$e'.replaceFirst('Exception: ', ''), isError: true);
    }
  }
}

/// Confirms adding a Drives folder to the library, or taking it out: a
/// decision surface, so its confirming button is the filled one.
class LibraryChangeDialog extends StatelessWidget {
  final String folder;
  final LocationLibrary library;
  final bool adding;

  const LibraryChangeDialog({
    super.key,
    required this.folder,
    required this.library,
    required this.adding,
  });

  @override
  Widget build(BuildContext context) {
    final restart = !library.restartRequired
        ? ''
        : adding
        ? ' The server restarts to start reading it.'
        : ' The server restarts to stop reading it.';
    return KalinkaDialog(
      side: KalinkaDialogSide.browsing,
      icon: adding ? Icons.library_add_outlined : Icons.folder_off_outlined,
      iconColor: adding ? KalinkaColors.accent : KalinkaColors.actionDelete,
      iconGlyphColor: adding ? KalinkaColors.accentTint : null,
      title: adding
          ? 'Add “$folder” to ${library.title}?'
          : 'Remove “$folder” from ${library.title}?',
      message: adding
          ? 'Kalinka will index its music and fill in the details. The drive '
                'needs to stay connected to play it; while it’s unplugged its '
                'tracks show as unavailable.$restart'
          : 'Its tracks leave ${library.title}. The files on the drive stay '
                'as they are, and the folder can still be played from '
                'Drives.$restart',
      actions: [
        KalinkaButton(
          label: 'Cancel',
          variant: KalinkaButtonVariant.neutral,
          fullWidth: true,
          onTap: () => Navigator.pop(context, false),
        ),
        KalinkaButton(
          label: adding ? 'Add to library' : 'Remove',
          variant: KalinkaButtonVariant.accent,
          fullWidth: true,
          onTap: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}
