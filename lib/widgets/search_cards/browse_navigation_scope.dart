import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/search_session_provider.dart';

/// Where the rows below open what they stand for, when that is not a visit of
/// the browsing history.
class BrowseNavigationScope extends InheritedWidget {
  final ValueChanged<BrowseItem> onOpen;

  const BrowseNavigationScope({
    super.key,
    required this.onOpen,
    required super.child,
  });

  static BrowseNavigationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BrowseNavigationScope>();

  @override
  bool updateShouldNotify(BrowseNavigationScope oldWidget) =>
      onOpen != oldWidget.onOpen;
}

/// Opens [item]'s own page — a source, catalog, folder, album, artist,
/// playlist or collection — the same way from every row and card. Opening
/// never touches playback.
void openBrowsable(BuildContext context, WidgetRef ref, BrowseItem item) {
  if (!item.canBrowse) return;
  final open =
      BrowseNavigationScope.maybeOf(context)?.onOpen ??
      ref.read(searchSessionProvider.notifier).openBrowseItem;
  open(item);
}
