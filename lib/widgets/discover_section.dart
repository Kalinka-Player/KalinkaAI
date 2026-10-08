import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data_model/data_model.dart';
import '../providers/connection_state_provider.dart';
import '../providers/discover_provider.dart';
import '../theme/app_theme.dart';
import 'search_cards/browse_item_rows.dart';

/// Discover — ID-agnostic catalog browsing on the zero-state surface.
/// Walks root → modules → catalogs via [discoverShelfPlansProvider] and
/// renders one shelf per plan. Rows delegate to the same Search*Row
/// widgets the rest of the app uses, so swipe-to-enqueue, tap-to-expand
/// album tracks, and long-press multi-select all work identically here.
class DiscoverSection extends ConsumerWidget {
  const DiscoverSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Discover shelves are plain FutureProviders that cache their result (or
    // error) indefinitely. After a reconnect, drop those snapshots so the
    // shelves re-fetch instead of showing pre-outage data — or a stuck error
    // from a fetch that failed during the outage.
    ref.listen(connectionStateProvider, (prev, next) {
      if (next == ConnectionStatus.connected &&
          prev != ConnectionStatus.connected) {
        ref.invalidate(discoverShelfPlansProvider);
        ref.invalidate(discoverShelfItemsProvider); // family → all shelves
      }
    });

    final plansAsync = ref.watch(discoverShelfPlansProvider);

    return plansAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (shelves) {
        // BrowseItemRows dispatches by entity type; raw catalog items have
        // no row widget, so those shelves would render blank — skip them.
        final renderable = shelves
            .where((s) => s.contentType != PreviewContentType.catalog)
            .toList();
        if (renderable.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Text('DISCOVER', style: KalinkaTextStyles.sectionLabel),
            for (final shelf in renderable) _DiscoverShelf(shelf: shelf),
          ],
        );
      },
    );
  }
}

class _DiscoverShelf extends ConsumerStatefulWidget {
  final DiscoverShelf shelf;
  const _DiscoverShelf({required this.shelf});

  @override
  ConsumerState<_DiscoverShelf> createState() => _DiscoverShelfState();
}

class _DiscoverShelfState extends ConsumerState<_DiscoverShelf> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final itemsAsync =
        ref.watch(discoverShelfItemsProvider(widget.shelf.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        _ShelfHeader(shelf: widget.shelf),
        const SizedBox(height: 6),
        itemsAsync.when(
          loading: () => const _ShelfPlaceholder(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: KalinkaColors.accent,
              ),
            ),
          ),
          error: (_, _) => _ShelfPlaceholder(
            child: Text(
              "Couldn't load ${widget.shelf.title}",
              style: KalinkaTextStyles.trackRowSubtitle,
            ),
          ),
          data: (list) {
            if (list.items.isEmpty) {
              return _ShelfPlaceholder(
                child: Text(
                  'Nothing in ${widget.shelf.title} yet',
                  style: KalinkaTextStyles.trackRowSubtitle,
                ),
              );
            }
            return BrowseItemRows(
              items: list.items,
              visibleLimit: _defaultVisibleLimit(widget.shelf),
              isExpanded: _expanded,
              onToggleExpand: () => setState(() => _expanded = !_expanded),
            );
          },
        ),
      ],
    );
  }

  // Uniform default across shelves keeps the surface scannable. Featured
  // shelves get a little more air because the backend hints they're the
  // editorial highlight.
  int _defaultVisibleLimit(DiscoverShelf s) =>
      s.role == CatalogRole.featured ? 5 : 4;
}

class _ShelfHeader extends StatelessWidget {
  final DiscoverShelf shelf;
  const _ShelfHeader({required this.shelf});

  @override
  Widget build(BuildContext context) {
    final source = shelf.moduleTitle;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            shelf.title.toUpperCase(),
            style: KalinkaTextStyles.sectionLabel,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (source.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text('\u00B7 $source', style: KalinkaTextStyles.clearAllChips),
        ],
      ],
    );
  }
}

class _ShelfPlaceholder extends StatelessWidget {
  final Widget child;
  const _ShelfPlaceholder({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(child: child),
    );
  }
}
