import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'fast_scroller.dart';

/// One chunk of a longer list, plus the collection's [total] so the scroller
/// knows when it has reached the end. [total] < 0 means "unknown" — it then
/// keeps loading until a short chunk comes back.
class ItemChunk<T> {
  final List<T> items;
  final int total;

  const ItemChunk({required this.items, this.total = -1});
}

/// Loads the next chunk: up to [limit] items starting at [offset]. This is the
/// only place the backend's chunking shows through — there is no page model
/// above it.
typedef ChunkFetcher<T> = Future<ItemChunk<T>> Function(int offset, int limit);

/// Where a list was left: what it had loaded and how far down it was, to
/// open there again. Items left under another reload key are not the list's.
class ListPlace<T> {
  final List<T> items;
  final int total;
  final bool ended;
  final double offset;
  final Object? reloadKey;
  final Object? refreshKey;

  const ListPlace({
    required this.items,
    required this.total,
    required this.ended,
    required this.offset,
    this.reloadKey,
    this.refreshKey,
  });
}

/// A reusable infinite-scroll list. It loads an initial chunk, then keeps
/// pulling the next one as the viewport nears the end — no page numbers, no
/// "next" control, just one continuous scroll. While a chunk is in flight it
/// trails [loadMorePlaceholder] (typically a shimmer) so the list grows
/// smoothly instead of snapping to a spinner.
///
/// Deliberately data-source agnostic: it knows nothing about the API or item
/// type. Callers supply [fetchChunk] and [itemBuilder], so catalog pages,
/// browse grids, and search sections can all drive it. Give it a distinct
/// [Key] (or change [reloadKey]) to restart from the top for a new source.
class InfiniteListView<T> extends StatefulWidget {
  final ChunkFetcher<T> fetchChunk;

  /// Builds one row. [loaded] is every item scrolled in so far, so builders
  /// that need list context (e.g. "play this whole list from here") can use
  /// it without the list threading state back out.
  final Widget Function(BuildContext context, T item, int index, List<T> loaded)
  itemBuilder;

  /// Divider/gap drawn *before* each item after the first, given the item it
  /// follows — a separator that has to line up with the row above it can only
  /// do that if it knows which row that is. Omit for no gaps.
  final Widget Function(BuildContext context, int index, T above)?
  separatorBuilder;

  /// How many items share a row. Above one, items read left to right and
  /// then down, in equal columns, [rowGap] apart; a row is as tall as its
  /// tallest item and [separatorBuilder] is not used.
  final int columns;
  final double columnGap;
  final double rowGap;

  /// Insets the rows of a multi-column listing, which the header does not
  /// share.
  final EdgeInsets rowPadding;

  /// How many items to request per chunk.
  final int chunkSize;
  final EdgeInsets padding;

  /// Scrolls above the items (title, attribution, …); beside a [sideHeader],
  /// above the items' own column.
  final Widget? header;

  /// A pinned/collapsible header, preceding [header] in the same viewport.
  /// With this set, [errorBuilder] supplies a non-scrolling body.
  final Widget? sliverHeader;

  /// An alternative header beside the items, sharing their scroll offset.
  /// Supply non-scrolling content here and in [errorBuilder] when used.
  final Widget? sideHeader;
  final double sideHeaderWidth;

  /// Shown while the first chunk loads (typically a shimmer list).
  final Widget? initialPlaceholder;

  /// Appended while the next chunk loads.
  final Widget? loadMorePlaceholder;

  final WidgetBuilder? emptyBuilder;
  final Widget Function(BuildContext context, VoidCallback retry)? errorBuilder;

  /// Distance from the bottom (px) at which the next chunk is prefetched, so
  /// it lands before the user hits the end.
  final double prefetchExtent;

  /// Changing this restarts from the top (alternative to re-keying).
  final Object? reloadKey;

  /// Changing this refetches what is loaded and swaps it in place, the rows
  /// staying up, where a restart would drop them to the placeholder.
  final Object? refreshKey;

  /// Told how many items are loaded once a fetch settles, and whether that
  /// fetch only added to them, so a page can shape chrome it draws outside
  /// the list — a header action with nothing to act on. Never called during
  /// a build.
  final void Function(int count, bool appended)? onLoadedCount;

  /// What, of the loaded items, a row depends on beyond its own. Given, rows
  /// already built are kept while more items only arrive — a chunk landing
  /// rebuilds none of them — until this changes or the list is rebuilt from
  /// outside. Null rebuilds every row whenever the list does.
  final Object? Function(List<T> loaded)? rowsDependOn;

  /// Where this list was left before, to open there at once with what it had
  /// loaded rather than at the top. Read only when the list is first built.
  final ListPlace<T>? place;

  /// Told where the list was left, when it goes.
  final ValueChanged<ListPlace<T>>? onLeave;

  /// Gives a long list a thumb to drag through all of it, where lists have
  /// no scrollbar of their own ([FastScroller.wanted]).
  final bool fastScroll;

  /// What the held thumb says about the item it is at.
  final String? Function(T item)? fastScrollLabel;

  /// Keeps the thumb clear of what [sliverHeader] pins over the list.
  final EdgeInsets fastScrollPadding;

  const InfiniteListView({
    super.key,
    required this.fetchChunk,
    required this.itemBuilder,
    this.separatorBuilder,
    this.columns = 1,
    this.columnGap = 16,
    this.rowGap = 16,
    this.rowPadding = EdgeInsets.zero,
    this.chunkSize = 30,
    this.padding = EdgeInsets.zero,
    this.header,
    this.sliverHeader,
    this.sideHeader,
    this.sideHeaderWidth = 0,
    this.initialPlaceholder,
    this.loadMorePlaceholder,
    this.emptyBuilder,
    this.errorBuilder,
    this.prefetchExtent = 600,
    this.reloadKey,
    this.refreshKey,
    this.onLoadedCount,
    this.rowsDependOn,
    this.place,
    this.onLeave,
    this.fastScroll = false,
    this.fastScrollLabel,
    this.fastScrollPadding = EdgeInsets.zero,
  }) : assert(sideHeader == null || sideHeaderWidth > 0),
       assert(sideHeader == null || sliverHeader == null);

  @override
  State<InfiniteListView<T>> createState() => _InfiniteListViewState<T>();
}

class _InfiniteListViewState<T> extends State<InfiniteListView<T>> {
  /// The most a jump far into the list loads at once.
  static const _largestChunk = 500;

  late final DeferringScrollController _controller;
  final List<T> _items = [];

  /// How far down the list is, kept as it scrolls: by the time the list
  /// goes, its scrollable has let go of the controller.
  double _offset = 0;

  /// How many items the fast scroller has asked for.
  int _wanted = 0;

  int _total = -1;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  Object? _initialError;
  int _generation = 0;
  bool _reachedShortChunk = false;

  /// Rows kept for [InfiniteListView.rowsDependOn], by row, with the items
  /// they were built from.
  final _kept = <int, ({List<T> items, Widget row})>{};
  Object? _keptFor;

  bool get _hasMore =>
      _total < 0 ? !_reachedShortChunk : _items.length < _total;

  @override
  void initState() {
    super.initState();
    final place = widget.place;
    final restored =
        place != null &&
        place.items.isNotEmpty &&
        place.reloadKey == widget.reloadKey;
    _controller = DeferringScrollController(
      initialScrollOffset: restored ? place.offset : 0,
    )..addListener(_onScroll);
    if (!restored) {
      _loadInitial();
      return;
    }
    _items.addAll(place.items);
    _total = place.total;
    _reachedShortChunk = place.ended;
    _initialLoading = false;
    _offset = place.offset;
    // Opening far down lays out every row above it on the way, only to drop
    // them: none should ask for its image.
    _controller.deferLoading = place.offset > 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.deferLoading = false;
      if (mounted) widget.onLoadedCount?.call(_items.length, false);
    });
    if (place.refreshKey != widget.refreshKey) _refresh();
    _maybeFillViewport();
  }

  @override
  void didUpdateWidget(covariant InfiniteListView<T> old) {
    super.didUpdateWidget(old);
    // Its builders may read anything that changed.
    _kept.clear();
    if (old.reloadKey != widget.reloadKey) {
      _restart();
    } else if (old.refreshKey != widget.refreshKey) {
      _refresh();
    }
  }

  @override
  void dispose() {
    if (!_initialLoading && _items.isNotEmpty) {
      widget.onLeave?.call(
        ListPlace(
          items: List.of(_items),
          total: _total,
          ended: _reachedShortChunk,
          offset: _offset,
          reloadKey: widget.reloadKey,
          refreshKey: widget.refreshKey,
        ),
      );
    }
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _restart() {
    setState(() {
      _items.clear();
      _kept.clear();
      _total = -1;
      _wanted = 0;
      _reachedShortChunk = false;
      _initialLoading = true;
      _loadingMore = false;
      _loadMoreFailed = false;
      _initialError = null;
    });
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final gen = ++_generation;
    try {
      final chunk = await widget.fetchChunk(0, widget.chunkSize);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items
          ..clear()
          ..addAll(chunk.items);
        _total = chunk.total;
        _reachedShortChunk = chunk.items.length < widget.chunkSize;
        _initialLoading = false;
      });
      widget.onLoadedCount?.call(_items.length, false);
      _maybeFillViewport();
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _initialError = e;
        _initialLoading = false;
      });
      // A listing that failed holds nothing, whatever it held before.
      widget.onLoadedCount?.call(0, false);
    }
  }

  /// Refetches the loaded range and swaps it in whole. A failed chunk leaves
  /// what was there: a refresh has no error state of its own.
  Future<void> _refresh() async {
    if (_initialLoading || _initialError != null) {
      _restart();
      return;
    }
    final gen = ++_generation;
    final loaded = _items.isEmpty ? 1 : _items.length;
    final fresh = <T>[];
    var total = _total;
    var short = false;
    try {
      while (fresh.length < loaded && !short) {
        // A list taken far down by the fast scroller refetches in big steps.
        final limit = math.max(
          widget.chunkSize,
          math.min(loaded - fresh.length, _largestChunk),
        );
        final chunk = await widget.fetchChunk(fresh.length, limit);
        if (!mounted || gen != _generation) return;
        fresh.addAll(chunk.items);
        total = chunk.total;
        short = chunk.items.length < limit;
      }
    } catch (_) {
      return;
    }
    setState(() {
      _kept.clear();
      _items
        ..clear()
        ..addAll(fresh);
      _total = total;
      _reachedShortChunk = short;
      _loadingMore = false;
      _loadMoreFailed = false;
    });
    widget.onLoadedCount?.call(_items.length, false);
    _maybeFillViewport();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loadMoreFailed || !_hasMore) return;
    setState(() => _loadingMore = true);
    final gen = _generation;
    final limit = math.max(
      widget.chunkSize,
      math.min(_wanted - _items.length, _largestChunk),
    );
    try {
      final chunk = await widget.fetchChunk(_items.length, limit);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(chunk.items);
        if (chunk.total >= 0) _total = chunk.total;
        if (chunk.items.length < limit) _reachedShortChunk = true;
        _loadingMore = false;
      });
      widget.onLoadedCount?.call(_items.length, true);
      if (_items.length < _wanted) {
        _loadMore();
      } else {
        _maybeFillViewport();
      }
    } catch (_) {
      if (!mounted || gen != _generation) return;
      // Stop auto-retrying on error; a tap on the retry footer resumes.
      setState(() {
        _loadingMore = false;
        _loadMoreFailed = true;
      });
    }
  }

  void _retryLoadMore() {
    setState(() => _loadMoreFailed = false);
    _loadMore();
  }

  /// Loads the first [count] items, the fast scroller having been taken
  /// past those loaded.
  void _reach(int count) {
    // Where the thumb is now: taken back up, it no longer wants the rest.
    _wanted = count;
    if (count > _items.length) _loadMore();
  }

  void _onScroll() {
    if (_controller.hasClients) _offset = math.max(0.0, _controller.offset);
    if (_initialLoading || _initialError != null || !_controller.hasClients) {
      return;
    }
    final pos = _controller.position;
    if (pos.pixels >= pos.maxScrollExtent - widget.prefetchExtent) {
      _loadMore();
    }
  }

  /// If the loaded items don't fill the viewport there's nothing to scroll and
  /// the scroll listener never fires — pull the next chunk eagerly instead.
  void _maybeFillViewport() {
    if (!_hasMore) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      if (_controller.position.maxScrollExtent <= 0) _loadMore();
    });
  }

  /// Both columns are slivers in one viewport, so the track list remains
  /// lazy and pagination follows scrolling over either column.
  bool get _customLayout =>
      widget.sideHeader != null || widget.sliverHeader != null;

  Widget _customScroll(Widget items) => CustomScrollView(
    controller: _controller,
    slivers: [
      ?widget.sliverHeader,
      SliverPadding(
        padding: widget.padding,
        sliver: widget.sideHeader == null
            ? items
            : SliverCrossAxisGroup(
                slivers: [
                  SliverConstrainedCrossAxis(
                    maxExtent: widget.sideHeaderWidth,
                    sliver: SliverToBoxAdapter(child: widget.sideHeader!),
                  ),
                  items,
                ],
              ),
      ),
    ],
  );

  Widget _stateSliver(Widget body) =>
      SliverList.list(children: [?widget.header, body]);

  @override
  Widget build(BuildContext context) {
    final list = _buildList(context);
    if (!widget.fastScroll || !FastScroller.wanted(context)) return list;
    final label = widget.fastScrollLabel;
    return FastScroller(
      controller: _controller,
      loaded: _items.length,
      total: _total,
      onReach: _reach,
      labelAt: label == null
          ? null
          : (index) => index < _items.length ? label(_items[index]) : null,
      padding: widget.fastScrollPadding,
      child: list,
    );
  }

  Widget _buildList(BuildContext context) {
    if (_initialLoading) {
      if (_customLayout) {
        return _customScroll(
          _stateSliver(widget.initialPlaceholder ?? const SizedBox.shrink()),
        );
      }
      return ListView(
        padding: widget.padding,
        children: [
          if (widget.header != null) widget.header!,
          if (widget.initialPlaceholder != null) widget.initialPlaceholder!,
        ],
      );
    }

    if (_initialError != null && _items.isEmpty) {
      final err = widget.errorBuilder;
      final body = err != null
          ? err(context, _restart)
          : const SizedBox.shrink();
      return _customLayout ? _customScroll(_stateSliver(body)) : body;
    }

    if (_items.isEmpty) {
      final empty =
          widget.emptyBuilder?.call(context) ?? const SizedBox.shrink();
      if (_customLayout) {
        return _customScroll(_stateSliver(empty));
      }
      // Keep a short empty state centred in the remaining viewport, but let
      // a tall header scroll on small screens and with enlarged system text.
      if (widget.header == null) return empty;
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: widget.header!),
          // Avoid intrinsic sizing: some empty states use LayoutBuilder to
          // adapt their card, which cannot answer intrinsic-height queries.
          SliverLayoutBuilder(
            builder: (context, constraints) => SliverToBoxAdapter(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      (constraints.viewportMainAxisExtent -
                              constraints.precedingScrollExtent)
                          .clamp(0.0, double.infinity),
                ),
                child: empty,
              ),
            ),
          ),
        ],
      );
    }

    final hasHeader = widget.header != null;
    final headerCount = hasHeader ? 1 : 0;
    final footerCount =
        (_loadingMore && widget.loadMorePlaceholder != null) || _loadMoreFailed
        ? 1
        : 0;
    final columns = widget.columns.clamp(1, 12);
    final rows = (_items.length / columns).ceil();
    final dependsOn = widget.rowsDependOn;
    final depends = dependsOn?.call(_items);
    if (dependsOn == null || depends != _keptFor) {
      _kept.clear();
      _keptFor = depends;
    }

    /// Row [key] as built before from the items [from] to [to], while they
    /// are the same items; otherwise [build]'s, kept for next time.
    Widget kept(int key, int from, int to, Widget Function() build) {
      if (dependsOn == null) return build();
      final entry = _kept[key];
      if (entry != null && entry.items.length == to - from) {
        var same = true;
        for (var k = from; k < to && same; k++) {
          same = identical(entry.items[k - from], _items[k]);
        }
        if (same) return entry.row;
      }
      final row = build();
      _kept[key] = (items: _items.sublist(from, to), row: row);
      return row;
    }

    Widget buildItem(BuildContext context, int index) {
      var i = index;
      if (hasHeader) {
        if (i == 0) return widget.header!;
        i -= 1;
      }

      if (columns > 1 && i < rows) {
        final first = i * columns;
        Widget line() => Padding(
          padding: widget.rowPadding.copyWith(
            top: widget.rowPadding.top + (i == 0 ? 0 : widget.rowGap),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) SizedBox(width: widget.columnGap),
                Expanded(
                  child: first + c < _items.length
                      ? widget.itemBuilder(
                          context,
                          _items[first + c],
                          first + c,
                          _items,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        );
        // A line still short of items gains them as more arrive.
        return first + columns <= _items.length
            ? kept(i, first, first + columns, line)
            : line();
      }
      if (columns > 1) i -= rows - _items.length;

      if (i < _items.length) {
        Widget row() {
          final item = widget.itemBuilder(context, _items[i], i, _items);
          if (widget.separatorBuilder != null && i > 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                widget.separatorBuilder!(context, i - 1, _items[i - 1]),
                item,
              ],
            );
          }
          return item;
        }

        // The separator is drawn from the item above.
        return kept(i, i > 0 ? i - 1 : 0, i + 1, row);
      }

      // Footer: retry link on failure, otherwise the load-more placeholder.
      if (_loadMoreFailed) {
        return _RetryFooter(onRetry: _retryLoadMore);
      }
      return widget.loadMorePlaceholder!;
    }

    final itemCount = headerCount + rows + footerCount;
    if (_customLayout) {
      return _customScroll(
        SliverList.builder(itemCount: itemCount, itemBuilder: buildItem),
      );
    }
    return ListView.builder(
      controller: _controller,
      padding: widget.padding,
      itemCount: itemCount,
      itemBuilder: buildItem,
    );
  }
}

class _RetryFooter extends StatelessWidget {
  final VoidCallback onRetry;

  const _RetryFooter({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Retry'),
        ),
      ),
    );
  }
}
