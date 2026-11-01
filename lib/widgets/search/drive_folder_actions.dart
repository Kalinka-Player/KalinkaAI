import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/storage.dart';
import '../../providers/kalinka_player_api_provider.dart';
import '../../providers/restart_provider.dart';
import '../../providers/search_session_provider.dart';
import '../../providers/source_modules_provider.dart';
import '../../providers/storage_volumes_provider.dart';
import '../../providers/toast_provider.dart';
import '../../theme/app_theme.dart';
import '../demo_read_only_dialog.dart';
import '../kalinka_button.dart';
import '../kalinka_bottom_sheet.dart';
import '../kalinka_dialog.dart';
import '../search_cards/action_pill_button.dart';
import '../source_badge.dart';

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

/// A Drives folder's own actions beside Play all: add it to the library or
/// take it out again, and eject at the top of a removable drive. Pills where
/// the row has room for them, else one More pill that offers them in a sheet.
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
    final eject = location.subpath.isEmpty && (volume?.isRemovable ?? false)
        ? volume
        : null;
    if (library == null && eject == null) return const SizedBox.shrink();
    final libraryIcon =
        ref.watch(sourceDisplayInfoProvider)[library?.module]?.icon ??
        Icons.library_music_outlined;
    return LayoutBuilder(
      builder: (context, box) {
        final widths = [
          if (library != null)
            ActionPillButton.widthOf(context, _libraryLabel(library)),
          if (eject != null) ActionPillButton.iconOnlyWidth,
        ];
        final needed =
            widths.fold(0.0, (sum, w) => sum + w) + 8 * (widths.length - 1);
        final Widget actions = needed <= box.maxWidth
            ? Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  if (library != null) _libraryPill(context, ref, library),
                  if (eject != null) _ejectPill(context, ref, eject),
                ],
              )
            : ActionPillButton(
                key: const ValueKey('drive-more'),
                icon: Icons.more_horiz_rounded,
                semanticsLabel: 'More for $title',
                onTap: () =>
                    _showMenu(context, ref, library, eject, libraryIcon),
              );
        return Align(alignment: Alignment.centerLeft, child: actions);
      },
    );
  }

  static String _libraryLabel(LocationLibrary library) =>
      library.holds ? 'In library' : 'Add to library';

  Widget _libraryPill(
    BuildContext context,
    WidgetRef ref,
    LocationLibrary library,
  ) {
    final changeable = !library.holds || library.removable;
    return Tooltip(
      message: !library.holds
          ? 'Add to ${library.title}'
          : library.removable
          ? 'Remove from ${library.title}'
          : 'In ${library.title} with a folder above it',
      child: ActionPillButton(
        key: const ValueKey('drive-library'),
        label: _libraryLabel(library),
        // The library's own tile, as its rows are badged, says which one.
        leading: library.holds
            ? null
            : SourceTile(source: library.module, size: 18),
        icon: library.holds ? Icons.check_rounded : null,
        semanticsLabel: library.holds
            ? 'In ${library.title}'
            : 'Add to ${library.title}',
        enabled: changeable,
        onTap: changeable ? () => _change(context, ref, library) : null,
      ),
    );
  }

  Widget _ejectPill(
    BuildContext context,
    WidgetRef ref,
    StorageVolume volume,
  ) => Tooltip(
    message: 'Eject ${volume.label}',
    child: ActionPillButton(
      key: const ValueKey('drive-eject'),
      icon: Icons.eject_rounded,
      semanticsLabel: 'Eject ${volume.label}',
      onTap: () => _eject(context, ref, volume),
    ),
  );

  Future<void> _showMenu(
    BuildContext context,
    WidgetRef ref,
    LocationLibrary? library,
    StorageVolume? eject,
    IconData libraryIcon,
  ) async {
    final chosen = await showKalinkaBottomSheet<_DriveAction>(
      context: context,
      contentBuilder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: eject != null ? 'DRIVE' : 'FOLDER',
            summary: title,
          ),
          if (library != null)
            SheetRow(
              key: const ValueKey('drive-menu-library'),
              icon: libraryIcon,
              iconBackground: KalinkaColors.surfaceElevated,
              iconColor: KalinkaColors.textSecondary,
              label: library.holds
                  ? 'Remove from ${library.title}'
                  : 'Add to ${library.title}',
              sublabel: !library.holds
                  ? 'Index its music and keep it'
                  : library.removable
                  ? 'Its files stay on the drive'
                  : 'In ${library.title} with a folder above it',
              onTap: !library.holds || library.removable
                  ? () => Navigator.pop(sheet, _DriveAction.library)
                  : null,
            ),
          if (library != null && eject != null) const SheetDivider(),
          if (eject != null)
            SheetRow(
              key: const ValueKey('drive-menu-eject'),
              icon: Icons.eject_rounded,
              iconBackground: KalinkaColors.surfaceElevated,
              iconColor: KalinkaColors.textSecondary,
              label: 'Eject ${eject.label}',
              sublabel: 'So it can be unplugged',
              onTap: () => Navigator.pop(sheet, _DriveAction.eject),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
    // Acted on from the page: the sheet's own context goes with the sheet.
    if (chosen == null || !context.mounted) return;
    switch (chosen) {
      case _DriveAction.library:
        await _change(context, ref, library!);
      case _DriveAction.eject:
        await _eject(context, ref, eject!);
    }
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

enum _DriveAction { library, eject }
