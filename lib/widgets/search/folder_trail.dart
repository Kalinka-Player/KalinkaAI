import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/search_session_provider.dart';
import '../crumb_trail.dart';
import 'browse_visit_scope.dart';

export '../crumb_trail.dart' show foldedTailStart;

/// The breadcrumb of a page of folders, in the bar in place of its title:
/// the page itself, then each folder down to the one shown.
class FolderTrail extends ConsumerWidget {
  /// The widest a crumb grows before its name ends in an ellipsis.
  static const crumbWidth = CrumbTrail.crumbWidth;

  const FolderTrail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = visitOf(context, ref);
    final path = visit.folderPath;
    final top = visit.catalogPage.title;
    final notifier = ref.read(searchSessionProvider.notifier);

    return CrumbTrail(
      names: [top ?? 'Home', for (final folder in path) folder.title ?? ''],
      icon: Icons.folder_outlined,
      onNavigate: notifier.showFolderAt,
    );
  }
}
