import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/search_session_provider.dart';
import '../../theme/app_theme.dart';
import 'browse_navigation_scope.dart';
import 'track_row_support.dart';

/// Catalogs open as pages so their subcatalogs, filters and pin action remain
/// reachable. Only media containers use inline expansion.
class SearchCatalogRow extends ConsumerWidget {
  final BrowseItem item;
  const SearchCatalogRow({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Material(
    type: MaterialType.transparency,
    child: ListTile(
      contentPadding: const EdgeInsets.only(left: 3),
      minVerticalPadding: 8,
      horizontalTitleGap: 12,
      leading: TrackThumb(item: item, size: 60, radius: 10),
      title: Text(
        item.catalog?.title ?? item.name ?? 'Catalog',
        style: KalinkaTextStyles.trackRowTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: item.description?.isNotEmpty == true
          ? Text(
              item.description!,
              style: KalinkaTextStyles.trackRowSubtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: const SizedBox(
        width: 48,
        height: 48,
        child: Icon(Icons.chevron_right),
      ),
      onTap: item.canBrowse
          ? () =>
                (BrowseNavigationScope.maybeOf(context)?.onOpen ??
                ref.read(searchSessionProvider.notifier).openBrowseItem)(item)
          : null,
    ),
  );
}
