import 'package:flutter/material.dart';

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

  /// How many items to request per chunk.
  final int chunkSize;
  final EdgeInsets padding;

  /// Scrolls above the items (title, attribution, …).
  final Widget? header;

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

  /// Told how many items are loaded once a fetch settles, so a page can shape
  /// chrome it draws outside the list — a header action with nothing to act
  /// on. Never called during a build.
  final ValueChanged<int>? onLoadedCount;

  const InfiniteListView({
    super.key,
    required this.fetchChunk,
    required this.itemBuilder,
    this.separatorBuilder,
    this.chunkSize = 30,
    this.padding = EdgeInsets.zero,
    this.header,
    this.initialPlaceholder,
    this.loadMorePlaceholder,
    this.emptyBuilder,
    this.errorBuilder,
    this.prefetchExtent = 600,
    this.reloadKey,
    this.refreshKey,
    this.onLoadedCount,
  });

  @override
  State<InfiniteListView<T>> createState() => _InfiniteListViewState<T>();
}

class _InfiniteListViewState<T> extends State<InfiniteListView<T>> {
  final ScrollController _controller = ScrollController();
  final List<T> _items = [];

  int _total = -1;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  Object? _initialError;
  int _generation = 0;
  bool _reachedShortChunk = false;

  bool get _hasMore =>
      _total < 0 ? !_reachedShortChunk : _items.length < _total;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void didUpdateWidget(covariant InfiniteListView<T> old) {
    super.didUpdateWidget(old);
    if (old.reloadKey != widget.reloadKey) {
      _restart();
    } else if (old.refreshKey != widget.refreshKey) {
      _refresh();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _restart() {
    setState(() {
      _items.clear();
      _total = -1;
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
      widget.onLoadedCount?.call(_items.length);
      _maybeFillViewport();
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _initialError = e;
        _initialLoading = false;
      });
      // A listing that failed holds nothing, whatever it held before.
      widget.onLoadedCount?.call(0);
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
        final chunk = await widget.fetchChunk(fresh.length, widget.chunkSize);
        if (!mounted || gen != _generation) return;
        fresh.addAll(chunk.items);
        total = chunk.total;
        short = chunk.items.length < widget.chunkSize;
      }
    } catch (_) {
      return;
    }
    setState(() {
      _items
        ..clear()
        ..addAll(fresh);
      _total = total;
      _reachedShortChunk = short;
      _loadingMore = false;
      _loadMoreFailed = false;
    });
    widget.onLoadedCount?.call(_items.length);
    _maybeFillViewport();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loadMoreFailed || !_hasMore) return;
    setState(() => _loadingMore = true);
    final gen = _generation;
    try {
      final chunk = await widget.fetchChunk(_items.length, widget.chunkSize);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(chunk.items);
        if (chunk.total >= 0) _total = chunk.total;
        if (chunk.items.length < widget.chunkSize) _reachedShortChunk = true;
        _loadingMore = false;
      });
      widget.onLoadedCount?.call(_items.length);
      _maybeFillViewport();
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

  void _onScroll() {
    if (!_controller.hasClients) return;
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

  @override
  Widget build(BuildContext context) {
    if (_initialLoading) {
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
      return err != null ? err(context, _restart) : const SizedBox.shrink();
    }

    if (_items.isEmpty) {
      final empty =
          widget.emptyBuilder?.call(context) ?? const SizedBox.shrink();
      // Empty state doesn't scroll; a Center-based placeholder needs bounded
      // height, so stack (not ListView) the optional header above it.
      if (widget.header == null) return empty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.header!,
          Expanded(child: empty),
        ],
      );
    }

    final hasHeader = widget.header != null;
    final headerCount = hasHeader ? 1 : 0;
    final footerCount =
        (_loadingMore && widget.loadMorePlaceholder != null) || _loadMoreFailed
        ? 1
        : 0;

    return ListView.builder(
      controller: _controller,
      padding: widget.padding,
      itemCount: headerCount + _items.length + footerCount,
      itemBuilder: (context, index) {
        var i = index;
        if (hasHeader) {
          if (i == 0) return widget.header!;
          i -= 1;
        }

        if (i < _items.length) {
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

        // Footer: retry link on failure, otherwise the load-more placeholder.
        if (_loadMoreFailed) {
          return _RetryFooter(onRetry: _retryLoadMore);
        }
        return widget.loadMorePlaceholder!;
      },
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
