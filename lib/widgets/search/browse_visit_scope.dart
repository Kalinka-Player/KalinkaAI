import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/search_session_provider.dart';

/// The visit a page in the browsing pane belongs to. Pages Back can return
/// to stay built under the current one, each reading its own visit, so their
/// listings, filters and scroll are there when Back reaches them.
class BrowseVisitScope extends InheritedWidget {
  final SearchSessionState visit;

  const BrowseVisitScope({
    super.key,
    required this.visit,
    required super.child,
  });

  static SearchSessionState? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<BrowseVisitScope>()
      ?.visit;

  @override
  bool updateShouldNotify(BrowseVisitScope oldWidget) =>
      !identical(visit, oldWidget.visit);
}

/// The visit [context] shows: its own when it is inside a [BrowseVisitScope],
/// otherwise the session's current one.
SearchSessionState visitOf(BuildContext context, WidgetRef ref) =>
    BrowseVisitScope.maybeOf(context) ?? ref.watch(searchSessionProvider);
