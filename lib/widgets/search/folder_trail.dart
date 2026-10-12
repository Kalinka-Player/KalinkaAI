import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/search_session_provider.dart';
import '../../theme/app_theme.dart';
import '../crumb_trail.dart';

export '../crumb_trail.dart' show foldedTailStart;

/// The breadcrumb over a page of folders, held under the title bar while the
/// folder scrolls: the page itself, then each folder down to the one shown.
class FolderTrail extends ConsumerWidget {
  /// The widest a crumb grows before its name ends in an ellipsis.
  static const crumbWidth = CrumbTrail.crumbWidth;

  static const _inset = 9.0;

  const FolderTrail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(searchSessionProvider.select((s) => s.folderPath));
    final top = ref.watch(
      searchSessionProvider.select((s) => s.catalogPage.title),
    );
    final notifier = ref.read(searchSessionProvider.notifier);

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: KalinkaColors.borderSubtle)),
      ),
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _inset),
          child: CrumbTrail(
            names: [
              top ?? 'Home',
              for (final folder in path) folder.title ?? '',
            ],
            icon: Icons.folder_outlined,
            onNavigate: notifier.showFolderAt,
          ),
        ),
      ),
    );
  }
}
