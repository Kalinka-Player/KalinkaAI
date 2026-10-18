import 'package:flutter/material.dart';

import '../../data_model/data_model.dart';

/// Row titles navigate; the trailing chevron unfolds one level only.
/// With [allowInline] off, both the row and its right chevron navigate.
/// Search surfaces without this scope retain their existing inline behavior.
class BrowseNavigationScope extends InheritedWidget {
  final ValueChanged<BrowseItem> onOpen;
  final bool allowInline;

  const BrowseNavigationScope({
    super.key,
    required this.onOpen,
    this.allowInline = true,
    required super.child,
  });

  static BrowseNavigationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BrowseNavigationScope>();

  @override
  bool updateShouldNotify(BrowseNavigationScope oldWidget) =>
      onOpen != oldWidget.onOpen || allowInline != oldWidget.allowInline;
}
