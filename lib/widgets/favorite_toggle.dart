import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import '../providers/favorites_provider.dart';
import '../providers/server_refusal.dart';
import '../providers/toast_provider.dart';

/// Whether [id] can be marked a favourite, for whatever lays a heart out: it
/// names a track, an album, an artist or a playlist whose own source keeps
/// favourites.
bool watchCanFavorite(WidgetRef ref, String id) => ref.watch(
  favoriteSourcesProvider.select(
    (keeping) => favoriteSourceOf(id, keeping) != null,
  ),
);

/// How an entity stands in its source's favourites, and the tap that changes
/// it.
class FavoriteMark {
  final bool favorite;

  /// Null until the source's favourites are first known and while the last
  /// tap is answered, so one tap sends once.
  final VoidCallback? toggle;

  const FavoriteMark({required this.favorite, required this.toggle});

  String get label => favorite ? 'Remove from favourites' : 'Add to favourites';

  IconData get icon =>
      favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded;
}

/// Marks an entity a favourite of its source, or no longer one, for the
/// widget that mixes it in to draw as a heart: the change shows at once and
/// is taken back with an error toast where the server does not make it.
mixin FavoriteMarking<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool _answering = false;

  /// [id]'s mark, watched so that only a change to it rebuilds this widget;
  /// null where [id] cannot be marked. [inPanel] says the heart stands in the
  /// player's pane, where a failure is then told.
  FavoriteMark? watchFavorite(String id, {bool inPanel = false}) {
    final source = ref.watch(
      favoriteSourcesProvider.select(
        (keeping) => favoriteSourceOf(id, keeping),
      ),
    );
    if (source == null) return null;
    final (favorite, known) = ref.watch(
      favoritesProvider(source)
          .select((ids) => (ids.value?.contains(id) ?? false, ids.hasValue)),
    );
    return FavoriteMark(
      favorite: favorite,
      toggle: _answering || !known
          ? null
          : () => _toggle(source, id, adding: !favorite, inPanel: inPanel),
    );
  }

  Future<void> _toggle(
    String source,
    String id, {
    required bool adding,
    required bool inPanel,
  }) async {
    final toast = ref.read(toastProvider.notifier);
    final favorites = ref.read(favoritesProvider(source).notifier);
    setState(() => _answering = true);
    try {
      await favorites.toggle(id);
    } catch (e) {
      final kind = EntityId.fromString(id).type.toValue();
      toast.show(
        e is ServerRefusalException
            ? '$e'
            : adding
            ? 'Could not add this $kind to favourites'
            : 'Could not remove this $kind from favourites',
        isError: true,
        inPanel: inPanel,
      );
    } finally {
      if (mounted) setState(() => _answering = false);
    }
  }
}

/// A heart for [id] as [builder] draws it, and nothing where [id] cannot be
/// marked.
class FavoriteToggle extends ConsumerStatefulWidget {
  final String id;

  /// The heart stands in the player's pane.
  final bool inPanel;
  final Widget Function(BuildContext context, FavoriteMark mark) builder;

  const FavoriteToggle({
    super.key,
    required this.id,
    required this.builder,
    this.inPanel = false,
  });

  @override
  ConsumerState<FavoriteToggle> createState() => _FavoriteToggleState();
}

class _FavoriteToggleState extends ConsumerState<FavoriteToggle>
    with FavoriteMarking {
  @override
  Widget build(BuildContext context) {
    final mark = watchFavorite(widget.id, inPanel: widget.inPanel);
    return mark == null
        ? const SizedBox.shrink()
        : widget.builder(context, mark);
  }
}
