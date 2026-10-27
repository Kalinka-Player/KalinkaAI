import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/toast_provider.dart';
import '../theme/app_theme.dart';

/// The list in [child], pulled down at its top, reloads with [onRefresh]. A
/// reload that throws leaves what was shown and says it could not reload.
///
/// The list must be scrollable when it is short, or it cannot be pulled
/// ([AlwaysScrollableScrollPhysics]).
class PullToRefresh extends ConsumerStatefulWidget {
  final Future<void> Function() onRefresh;
  final Widget child;

  const PullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  @override
  ConsumerState<PullToRefresh> createState() => _PullToRefreshState();
}

class _PullToRefreshState extends ConsumerState<PullToRefresh> {
  /// The indicator kept the list from showing its latest overscroll, which
  /// it does for a pull: the list's request never got past it.
  bool _pulling = false;

  Future<void> _refresh() async {
    try {
      await widget.onRefresh();
    } catch (_) {
      showSafeToast('Could not reload', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<OverscrollNotification>(
        // What stretches along with the list (an album's cover) must not
        // stretch while the list does not.
        onNotification: (notification) => notification.depth == 0 && _pulling,
        child: NotificationListener<OverscrollIndicatorNotification>(
          onNotification: (notification) {
            if (notification.depth == 0) _pulling = false;
            return false;
          },
          child: RefreshIndicator(
            onRefresh: _refresh,
            color: KalinkaColors.accent,
            backgroundColor: KalinkaColors.surfaceRaised,
            child: NotificationListener<OverscrollIndicatorNotification>(
              onNotification: (notification) {
                if (notification.depth == 0) _pulling = true;
                return false;
              },
              child: widget.child,
            ),
          ),
        ),
      );
}
