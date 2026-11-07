import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/storage.dart';
import '../../providers/kalinka_player_api_provider.dart';
import '../../providers/server_info_provider.dart';
import '../../theme/app_theme.dart';
import '../infinite_list_view.dart';
import '../kalinka_bottom_sheet.dart';
import '../kalinka_button.dart';
import '../search_cards/track_row_support.dart' show itemIcon;
import '../tap_highlight.dart' show kalinkaIconButtonStyle;

/// Opens [FolderPickerSheet] and answers the path of the folder chosen, or
/// null when the sheet is closed without one.
Future<String?> showFolderPicker(BuildContext context) =>
    showKalinkaBottomSheet<String>(
      context: context,
      dialogMaxWidth: kKalinkaContentMaxWidth,
      mayFillScreen: true,
      contentBuilder: (_) => const FolderPickerSheet(),
    );

/// A folder button beside a path field, on a server that can be browsed;
/// nothing on one that cannot, where the field is typed as before.
class FolderPickerButton extends ConsumerWidget {
  final ValueChanged<String> onPicked;

  const FolderPickerButton({super.key, required this.onPicked});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(storageSupportedProvider)) return const SizedBox.shrink();
    return IconButton(
      key: const ValueKey('folder-picker-button'),
      tooltip: 'Choose a folder on the server',
      style: kalinkaIconButtonStyle,
      color: KalinkaColors.textSecondary,
      icon: const Icon(Icons.folder_open_outlined, size: 20),
      onPressed: () async {
        final path = await showFolderPicker(context);
        if (path != null) onPicked(path);
      },
    );
  }
}

/// Walks the server's places and the folders in them, and gives back the
/// path of the folder chosen.
///
/// Its confirming button is the one crimson fill: the sheet is where the
/// choice is made.
class FolderPickerSheet extends ConsumerStatefulWidget {
  const FolderPickerSheet({super.key});

  @override
  ConsumerState<FolderPickerSheet> createState() => _FolderPickerSheetState();
}

class _FolderPickerSheetState extends ConsumerState<FolderPickerSheet> {
  /// The folders walked into, from the places, which have no path.
  final _trail = <({String? path, String name})>[(path: null, name: 'Places')];

  Future<ItemChunk<ServerFolder>> _folders(
    String? path,
    int offset,
    int limit,
  ) async {
    final listing = await ref
        .read(kalinkaProxyProvider)
        .listServerFolders(path: path, offset: offset, limit: limit);
    return ItemChunk(items: listing.folders, total: listing.total);
  }

  void _go(void Function() change) => setState(change);

  @override
  Widget build(BuildContext context) {
    final atPlaces = _trail.length == 1;
    final folder = _trail.last.path;
    final trail = _trail.skip(1).map((step) => step.name).join(' › ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: 'CHOOSE A MUSIC FOLDER',
          summary: atPlaces ? 'On this server, its drives and shares' : trail,
        ),
        if (!atPlaces)
          SheetRow(
            key: const ValueKey('folder-picker-up'),
            icon: Icons.arrow_upward_rounded,
            iconBackground: KalinkaColors.surfaceElevated,
            iconColor: KalinkaColors.textSecondary,
            label: _trail[_trail.length - 2].name,
            onTap: () => _go(_trail.removeLast),
          ),
        Flexible(
          child: InfiniteListView<ServerFolder>(
            key: ValueKey(folder),
            shrinkWrap: true,
            chunkSize: 50,
            fetchChunk: (offset, limit) => _folders(folder, offset, limit),
            initialPlaceholder: const _Loading(),
            loadMorePlaceholder: const _Loading(),
            emptyBuilder: (_) => _Note(
              atPlaces ? 'Nothing to choose from.' : 'No folders inside.',
            ),
            errorBuilder: (_, _) => const _Note('This folder cannot be read.'),
            itemBuilder: (context, item, _, _) => SheetRow(
              key: ValueKey('folder-picker-${item.path}'),
              icon: itemIcon(item.icon) ?? Icons.folder_rounded,
              iconBackground: KalinkaColors.surfaceElevated,
              iconColor: KalinkaColors.textSecondary,
              label: item.name,
              sublabel: item.subname ?? '',
              trailing: const SheetChevron(),
              onTap: () =>
                  _go(() => _trail.add((path: item.path, name: item.name))),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(kSheetGutter, 12, kSheetGutter, 8),
          child: KalinkaButton(
            key: const ValueKey('folder-picker-choose'),
            label: 'Use this folder',
            variant: KalinkaButtonVariant.accent,
            fullWidth: true,
            onTap: atPlaces
                ? null
                : () => Navigator.of(context).pop(_trail.last.path),
          ),
        ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _Note extends StatelessWidget {
  final String text;

  const _Note(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(kSheetGutter),
    child: Text(text, style: KalinkaTextStyles.trackRowSubtitle),
  );
}
