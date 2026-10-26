import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart' show SearchSuggestion;
import '../../providers/catalog_cards_provider.dart';
import '../../providers/collections_provider.dart';
import '../../providers/pinned_catalogs_provider.dart';
import '../../providers/search_session_provider.dart';
import '../../providers/shell_nav_provider.dart';
import '../../providers/source_modules_provider.dart';
import '../../theme/app_theme.dart';
import '../home/home_layout.dart';
import '../home/pinned_catalogs_section.dart';
import '../measure_size.dart';
import '../modifier_click.dart';
import 'collections_section.dart';

/// The Catalogs root body: the search invitation (passed in via [leading]),
/// your collections, source tiles, then pinned catalogs.
/// Suggestions and recent searches live in the focused
/// search overlay ([SearchSuggestionsList]), not here.
/// Home's side inset; what reaches the window edge bleeds past it by this.
const kHomeSideInset = 16.0;

class SearchZeroState extends ConsumerWidget {
  /// Opens a catalog page directly (browse id + resolved provider label).
  final OpenCatalog onOpenCatalog;

  /// Shares the root's scroll position with Home's backdrop and pinned bar.
  final ScrollController? controller;

  /// Widgets pinned to the top of the scroll — the "What shall we play?"
  /// heading and the search entry — so they scroll with the
  /// content rather than sitting sticky above it.
  final List<Widget> leading;

  /// Off where the navigation rail lists Collections instead.
  final bool showCollections;

  /// The line of music sources under the search. Shown while [showSources],
  /// and always while Home holds nothing of the listener's own: then it is
  /// the way in, rail or not.
  final Widget? sources;
  final bool showSources;

  /// Under the ways in: what the library is doing while it works. Brings
  /// its own gap under it, so it takes no room while idle.
  final Widget? activity;

  /// How far down the search sits while centred, so the glow behind it
  /// follows.
  final ValueChanged<double>? onCentringShift;

  /// Height Home has only for now, lent by a bar that has slid away (the
  /// mini-player while the search is up). Centring leaves it out, so the bar
  /// coming back moves nothing.
  final ValueListenable<double>? roomLent;

  const SearchZeroState({
    super.key,
    required this.onOpenCatalog,
    this.controller,
    this.leading = const [],
    this.showCollections = true,
    this.sources,
    this.showSources = true,
    this.activity,
    this.onCentringShift,
    this.roomLent,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pins = ref.watch(pinnedCatalogsProvider);
    // Nothing of the listener's own on Home yet: no pins and no collections
    // shown here (the rail carries them where it shows). Still loading counts
    // as none, so a new listener's Home never jumps.
    final collections = showCollections
        ? ref.watch(collectionsShelfProvider).value
        : null;
    final empty = pins.isEmpty && (collections == null || collections.isEmpty);
    const top = 8.0;
    return RefreshIndicator(
      onRefresh: ref.read(searchSessionProvider.notifier).refreshAll,
      color: KalinkaColors.accent,
      backgroundColor: KalinkaColors.surfaceRaised,
      child: LayoutBuilder(
        builder: (context, constraints) => ListView(
          // Coming back from a catalog returns to where the root was left, not
          // to its top — the shelf you came from is where you look next.
          key: const PageStorageKey('discoverRoot'),
          controller: controller,
          // Pullable even when Home is shorter than the screen.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            kHomeSideInset,
            top,
            kHomeSideInset,
            kHomeSectionGap,
          ),
          children: [
            ValueListenableBuilder<double>(
              valueListenable: roomLent ?? const AlwaysStoppedAnimation(0.0),
              builder: (context, lent, child) => _Centring(
                centred: empty,
                room: constraints.maxHeight - top - kHomeSectionGap - lent,
                onShift: onCentringShift,
                child: child!,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...leading,
                  // Close under the prompts and over what follows, as one
                  // line of ways in; without it, the search's full gap.
                  if (sources != null && (showSources || empty)) ...[
                    sources!,
                    const SizedBox(height: 16),
                  ] else
                    const SizedBox(height: 12),
                  ?activity,
                  if (empty)
                    _PinHint(
                      onCustomise: () =>
                          ref.read(homeCustomisationProvider.notifier).open(),
                    ),
                ],
              ),
            ),
            if (!empty && showCollections)
              CollectionsSection(onOpenCatalog: onOpenCatalog),
            if (pins.isNotEmpty) ...[
              PinnedCatalogsSection(pins: pins),
              // After the pins, quietly: where to change them.
              _CustomiseLine(
                onCustomise: () =>
                    ref.read(homeCustomisationProvider.notifier).open(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// While Home holds nothing of the listener's own, its top — the question,
/// the search and the sources — sits in the middle of the [room] it has;
/// once a pin or a collection arrives it rises to the top, making room for
/// them. [onShift] hears how far down it sits as it moves.
class _Centring extends StatefulWidget {
  final bool centred;
  final double room;
  final ValueChanged<double>? onShift;
  final Widget child;

  const _Centring({
    required this.centred,
    required this.room,
    required this.onShift,
    required this.child,
  });

  @override
  State<_Centring> createState() => _CentringState();
}

class _CentringState extends State<_Centring>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
    value: widget.centred ? 1 : 0,
  )..addListener(_report);
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );
  double? _height;

  /// How far below the top the child sits at [t] of the way to centred.
  double _shiftAt(double t) {
    final height = _height;
    if (height == null) return 0;
    return math.max(0.0, widget.room * t - height) * t / 2;
  }

  void _report() => widget.onShift?.call(_shiftAt(_curve.value));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 450);
  }

  @override
  void didUpdateWidget(_Centring old) {
    super.didUpdateWidget(old);
    if (old.centred != widget.centred) {
      widget.centred ? _controller.forward() : _controller.reverse();
    }
    if (old.room != widget.room) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _report();
      });
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _curve,
    builder: (context, child) {
      final t = _curve.value;
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: math.max(0.0, widget.room * t)),
        child: Align(alignment: Alignment(0, t - 1), child: child),
      );
    },
    child: MeasureSize(
      onChange: (size) {
        _height = size.height;
        _report();
      },
      child: widget.child,
    ),
  );
}

/// The end of the pins: a muted question and a bright, neutral Customise
/// Home, against the trailing edge, so it never reads as part of a preview.
class _CustomiseLine extends StatelessWidget {
  final VoidCallback onCustomise;

  const _CustomiseLine({required this.onCustomise});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Text(
            'Want Home to look different?',
            style: KalinkaTextStyles.trackRowSubtitle.copyWith(
              color: KalinkaColors.textMuted,
            ),
          ),
          TextButton.icon(
            key: const ValueKey('customise-home-button'),
            onPressed: onCustomise,
            style: TextButton.styleFrom(
              foregroundColor: KalinkaColors.textPrimary,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: KalinkaFonts.sans(
                fontSize: KalinkaTypography.baseSize + 1,
                fontWeight: FontWeight.w600,
              ),
            ),
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Customise Home'),
          ),
        ],
      ),
    );
  }
}

/// Under the sources while nothing is pinned: what pinning does, and the
/// way to set Home up.
class _PinHint extends StatelessWidget {
  final VoidCallback onCustomise;

  const _PinHint({required this.onCustomise});

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('home-pin-hint'),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 350),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.pin,
                size: 20,
                color: KalinkaColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Pin any catalogue or saved search to see it here.',
                  style: KalinkaTextStyles.trackRowSubtitle.copyWith(
                    fontSize: KalinkaTypography.baseSize + 3,
                    color: KalinkaColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TextButton.icon(
          key: const ValueKey('home-pin-hint-customise'),
          onPressed: onCustomise,
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            foregroundColor: KalinkaColors.textPrimary,
            textStyle: KalinkaFonts.sans(
              fontSize: KalinkaTypography.baseSize + 3,
              fontWeight: FontWeight.w500,
            ),
          ),
          icon: const Icon(Icons.tune, size: 20),
          label: const Text('Customise Home'),
        ),
      ],
    );
  }
}

/// The focused search body under the field. At rest: an **AI SUGGESTIONS**
/// section with the curated (validated) suggestions, a friendly lead-in
/// introducing the serendipity pick, then **RECENT SEARCHES**.
/// While the user types, the prompts drop away and both lists narrow to plain
/// rows containing the typed text; when nothing matches the free-typed query
/// itself becomes the one action so the field never dead-ends. Tap runs a
/// suggestion / history query, long-press drops a suggestion into the field;
/// recent searches clear individually (✕) or all at once.
class SearchSuggestionsList extends ConsumerWidget {
  final String query;
  final ValueChanged<String> onInsert;
  final ValueChanged<String> onSubmit;

  /// Drives the open animation (0→1). Each tile fades + slides in on a
  /// staggered interval so they appear one by one, top to bottom. Null = no
  /// entrance animation (already open).
  final Animation<double>? reveal;

  const SearchSuggestionsList({
    super.key,
    required this.query,
    required this.onInsert,
    required this.onSubmit,
    this.reveal,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(searchSessionProvider);
    final notifier = ref.read(searchSessionProvider.notifier);
    final needle = query.trim().toLowerCase();
    // Without smart search, mood prompts would only run as name searches.
    final offered = (ref.watch(smartSearchAvailableProvider) ?? true)
        ? session.suggestions
        : const <SearchSuggestion>[];
    // A row saying only what the field already holds would be the entry
    // twice over.
    bool matches(String text) {
      final folded = text.trim().toLowerCase();
      return folded.contains(needle) && folded != needle;
    }

    final suggestions = needle.isEmpty
        ? offered
        : offered.where((s) => matches(s.query)).toList(growable: false);
    final history = needle.isEmpty
        ? session.history
        : session.history.where(matches).toList(growable: false);

    // While typing, headers and prompts drop away: just the matching rows.
    // At rest the curated suggestions sit under AI SUGGESTIONS and the
    // serendipity pick gets a lead-in explaining the compass mark.
    final curated = suggestions.where((s) => !s.experimental);
    final serendipity = suggestions.where((s) => s.experimental);

    Widget tile(SearchSuggestion s) => _SuggestionTile(
      text: s.query,
      highlight: needle,
      experimental: s.experimental,
      onInsert: () => onInsert(s.query),
      onRun: () => onSubmit(s.query),
    );

    // A flat row list — lead-ins, section labels and tiles — so the staggered
    // entrance lands them one by one top-to-bottom across all sections.
    final rows = <Widget>[
      if (needle.isEmpty) ...[
        if (curated.isNotEmpty) ...[_aiHeader(), ...curated.map(tile)],
        for (final s in serendipity)
          _SerendipityCard(
            text: s.query,
            onInsert: () => onInsert(s.query),
            onRun: () => onSubmit(s.query),
          ),
      ] else
        ...suggestions.map(tile),
      if (history.isNotEmpty) ...[
        _recentHeader(
          divider: suggestions.isNotEmpty,
          onClear: notifier.clearHistory,
        ),
        for (final q in history)
          _HistoryTile(
            query: q,
            onTap: () => onSubmit(q),
            onDelete: () => notifier.removeHistoryItem(q),
          ),
      ],
    ];

    // Nothing matching leaves no rows: the field's own arrow sends it.

    // shrinkWrap: the container hugs the rows and only scrolls if they outgrow
    // the space left above the keyboard.
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      children: [
        for (var i = 0; i < rows.length; i++)
          _staggered(i, rows.length, rows[i]),
      ],
    );
  }

  /// Overlay section heading: the mono section label, larger but dimmed.
  static TextStyle get _sectionTitle => KalinkaTextStyles.sectionLabel.copyWith(
    fontSize: KalinkaTypography.baseSize + 3,
    color: KalinkaColors.textMuted,
  );

  /// The curated list's heading — text only.
  Widget _aiHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
    child: Text('IDEAS TO TRY', style: _sectionTitle),
  );

  /// RECENT SEARCHES heading with a trailing "Clear". [divider] separates it
  /// from a preceding section.
  Widget _recentHeader({
    required bool divider,
    required VoidCallback onClear,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (divider)
        Container(
          height: 1,
          margin: const EdgeInsets.fromLTRB(8, 18, 8, 0),
          color: KalinkaColors.borderSubtle,
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 18, 4, 6),
        child: Row(
          children: [
            Expanded(child: Text('RECENT SEARCHES', style: _sectionTitle)),
            TextButton(
              onPressed: onClear,
              style: TextButton.styleFrom(
                foregroundColor: KalinkaColors.textMuted,
                textStyle: KalinkaTextStyles.clearAllChips,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Clear'),
            ),
          ],
        ),
      ),
    ],
  );

  /// Wrap a tile in a fade + short upward slide keyed to its row, so rows land
  /// top-to-bottom as the overlay opens.
  Widget _staggered(int index, int count, Widget child) {
    final reveal = this.reveal;
    if (reveal == null) return child;
    // Spread the entrances across the back half of the open animation.
    final step = count <= 1 ? 0.0 : 0.5 / count;
    final start = (0.35 + index * step).clamp(0.0, 1.0);
    final anim = CurvedAnimation(
      parent: reveal,
      curve: Interval(
        start,
        (start + 0.4).clamp(0.0, 1.0),
        curve: Curves.easeOut,
      ),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(anim),
        child: child,
      ),
    );
  }
}

/// AI prompt suggestion. Tapping runs it straight away — the expected action;
/// long-pressing drops it into the composer to edit before sending.
/// Curated picks lead with the gold AI sparkle; [experimental] marks the
/// server's serendipity pick (context-matched but not validated against the
/// library) with a compass instead.
class _SuggestionTile extends StatelessWidget {
  final String text;
  final bool experimental;

  /// Lower-cased substring the list filtered on; the matching run inside [text]
  /// is emphasised so the user sees why it surfaced. Empty = no emphasis.
  final String highlight;
  final VoidCallback onInsert;
  final VoidCallback onRun;

  const _SuggestionTile({
    required this.text,
    required this.onInsert,
    required this.onRun,
    this.experimental = false,
    this.highlight = '',
  });

  /// The prompt text, emphasising the run that matched the current filter so
  /// the user sees why this suggestion surfaced. Plain text when unfiltered.
  Widget _buildText() {
    final base = KalinkaTextStyles.searchOverlayRow;
    final needle = highlight;
    final start = needle.isEmpty ? -1 : text.toLowerCase().indexOf(needle);
    if (start < 0) {
      return Text(
        text,
        style: base,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }
    final end = start + needle.length;
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: text.substring(start, end),
            style: const TextStyle(
              color: KalinkaColors.accentTint,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: experimental
          ? 'Run experimental suggestion: $text'
          : 'Run suggestion: $text',
      hint: 'Long press to edit before sending',
      button: true,
      child: _Tile(
        onTap: onRun,
        onLongPress: onInsert,
        child: Row(
          children: [
            _GlyphTile(
              icon: experimental ? Icons.explore_outlined : Icons.auto_awesome,
            ),
            const SizedBox(width: 12),
            Expanded(child: _buildText()),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 15,
              color: KalinkaColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// A historical query tile. Tapping the row runs the query again (the hover
/// lift carries the affordance); the single trailing ✕ deletes just this entry.
class _HistoryTile extends StatelessWidget {
  final String query;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _HistoryTile({
    required this.query,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Search again for $query',
      button: true,
      child: _Tile(
        onTap: onTap,
        child: Row(
          children: [
            // History mark keeps recents visually apart from the AI rows.
            const SizedBox(
              width: 32,
              child: Icon(
                Icons.history_rounded,
                size: 17,
                color: KalinkaColors.textMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                query,
                style: KalinkaTextStyles.searchOverlayRow,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.close_rounded, size: 18),
              color: KalinkaColors.textMuted,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              tooltip: 'Remove from history',
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared shell for the overlay rows: an [InkWell] on a transparent [Material]
/// so hover, press ripple, and pointer cursor are the standard ones. Rounded 14
/// to match the card.
class _HoverRow extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  const _HoverRow({required this.onTap, this.onLongPress, required this.child});

  @override
  Widget build(BuildContext context) {
    return ModifierClick(
      onModifiedClick: onLongPress,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(14),
          hoverColor: KalinkaColors.surfaceElevated,
          highlightColor: KalinkaColors.surfaceOverlay,
          splashColor: KalinkaColors.surfaceOverlay,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 11, 10, 11),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A bordered row inside the search card — the shape the card's own controls
/// use, so the ideas read as things to press rather than lines of a list.
class _Tile extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  /// Accent-tinted, for the one row that is not an ordinary idea.
  final bool accent;

  const _Tile({
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: accent ? KalinkaColors.accentSubtle : KalinkaColors.surfaceInput,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent
              ? KalinkaColors.accentBorder
              : KalinkaColors.borderSubtle,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: _HoverRow(onTap: onTap, onLongPress: onLongPress, child: child),
    );
  }
}

/// The accent tile that leads a row, matching the mark in the card's header.
class _GlyphTile extends StatelessWidget {
  final IconData icon;

  const _GlyphTile({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: KalinkaColors.accentSubtle,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: KalinkaColors.accentBorder),
      ),
      child: Center(
        child: Icon(icon, size: 16, color: KalinkaColors.accentBright),
      ),
    );
  }
}

/// The server's serendipity pick: context-matched but not validated against
/// the library, so it is offered as a departure rather than a fourth idea.
class _SerendipityCard extends StatelessWidget {
  final String text;
  final VoidCallback onInsert;
  final VoidCallback onRun;

  const _SerendipityCard({
    required this.text,
    required this.onInsert,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Run experimental suggestion: $text',
      hint: 'Long press to edit before sending',
      button: true,
      child: _Tile(
        onTap: onRun,
        onLongPress: onInsert,
        accent: true,
        child: Row(
          children: [
            const _GlyphTile(icon: Icons.explore_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'DISCOVER SOMETHING NEW',
                    style: KalinkaFonts.mono(
                      fontSize: KalinkaTypography.baseSize - 2,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.4,
                      color: KalinkaColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    text,
                    style: KalinkaTextStyles.searchOverlayRow.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Beyond your library',
                    style: KalinkaTextStyles.trackRowSubtitle.copyWith(
                      color: KalinkaColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 15,
              color: KalinkaColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
