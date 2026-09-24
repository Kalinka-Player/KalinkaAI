import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/browse_filters.dart';
import '../../data_model/data_model.dart' show SearchType;
import '../../providers/browse_genres_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';
import '../source_badge.dart';

/// Default idle time before a keystroke becomes a query — long enough that
/// typing a word is one request, short enough to feel live. Staged surfaces
/// (the filter overlay) pass [Duration.zero] instead: nothing is sent until
/// the sheet is applied, so there is nothing to coalesce.
const kFilterTextDebounce = Duration(milliseconds: 300);

/// The filter controls themselves: a search field over one labelled group per
/// facet. Which groups appear — and which are live rather than muted
/// placeholders — is entirely [BrowseFilterCapabilities]' call, so catalog
/// pages, favourites and future library surfaces share one form and each shows
/// only what its source can do.
///
/// The form owns no filter state: it renders [query] and reports edits through
/// [onChanged]. Its host decides whether those edits apply straight away or
/// stage until confirmed.
class BrowseFilterForm extends StatelessWidget {
  final BrowseFilterCapabilities capabilities;
  final BrowseFilterQuery query;
  final ValueChanged<BrowseFilterQuery> onChanged;

  /// Placeholder text for the search field, e.g. "Search Popular Albums".
  final String searchHint;

  /// One quiet line under the search field, where what that field does needs
  /// saying.
  final String? searchCaption;

  final Duration textDebounce;

  const BrowseFilterForm({
    super.key,
    required this.capabilities,
    required this.query,
    required this.onChanged,
    this.searchHint = 'Search',
    this.searchCaption,
    this.textDebounce = kFilterTextDebounce,
  });

  bool get _showTypes =>
      capabilities.type != FacetSupport.hidden && capabilities.types.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (capabilities.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (capabilities.text != FacetSupport.hidden) ...[
          FilterSearchField(
            enabled: capabilities.text == FacetSupport.supported,
            value: query.text,
            hint: searchHint,
            debounce: textDebounce,
            onChanged: (text) => onChanged(query.copyWith(text: text)),
          ),
          if (searchCaption != null) ...[
            const SizedBox(height: 8),
            _FacetCaption(searchCaption!),
          ],
          const SizedBox(height: 18),
        ],
        if (capabilities.kind == FacetSupport.supported) ...[
          _KindGroup(
            selected: query.kind,
            onSelected: (kind) => onChanged(
              kind == null
                  ? query.copyWith(clearKind: true)
                  : query.copyWith(kind: kind),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_showTypes) ...[
          _TypeGroup(
            capabilities: capabilities,
            selected: query.type,
            onSelected: capabilities.type == FacetSupport.supported
                ? (type) => onChanged(
                    type == null
                        ? query.copyWith(clearType: true)
                        : query.copyWith(type: type),
                  )
                : null,
          ),
          const SizedBox(height: 16),
        ],
        if (capabilities.source == FacetSupport.supported &&
            capabilities.sources.isNotEmpty) ...[
          _SourceGroup(
            capabilities: capabilities,
            selected: query.sources,
            onChanged: (sources) => onChanged(query.copyWith(sources: sources)),
          ),
          const SizedBox(height: 16),
        ],
        if (capabilities.genre != FacetSupport.hidden) ...[
          _GenreGroup(
            capabilities: capabilities,
            selected: query.genreIds,
            onChanged: (ids) => onChanged(query.copyWith(genreIds: ids)),
          ),
          if (capabilities.order == FacetSupport.supported)
            const SizedBox(height: 16),
        ],
        if (capabilities.order == FacetSupport.supported)
          _OrderGroup(
            selected: query.order,
            onSelected: (order) => onChanged(query.copyWith(order: order)),
          ),
      ],
    );
  }
}

/// The search field. Disabled it keeps its full shape in muted tones — the
/// affordance a source will grow into, not a control that quietly does
/// nothing.
class FilterSearchField extends StatefulWidget {
  final bool enabled;
  final String value;
  final String hint;
  final ValueChanged<String> onChanged;

  /// Zero reports every keystroke immediately (staged hosts want that).
  final Duration debounce;

  const FilterSearchField({
    super.key,
    required this.enabled,
    required this.value,
    required this.hint,
    required this.onChanged,
    this.debounce = kFilterTextDebounce,
  });

  @override
  State<FilterSearchField> createState() => _FilterSearchFieldState();
}

class _FilterSearchFieldState extends State<FilterSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  Timer? _debounce;

  @override
  void didUpdateWidget(FilterSearchField old) {
    super.didUpdateWidget(old);
    // Follow an external reset (Reset / Cancel), but never fight the user
    // mid-type.
    if (widget.value != old.value && widget.value != _controller.text) {
      _debounce?.cancel();
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    if (widget.debounce == Duration.zero) {
      widget.onChanged(text);
      return;
    }
    _debounce = Timer(widget.debounce, () => widget.onChanged(text));
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final edge = enabled
        ? KalinkaColors.accentBorder
        : KalinkaColors.borderDefault;
    final leadColor = enabled ? KalinkaColors.accent : KalinkaColors.textMuted;

    return Semantics(
      textField: true,
      enabled: enabled,
      label: enabled
          ? widget.hint
          : '${widget.hint} — not supported by this source',
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: KalinkaColors.surfaceInput,
          borderRadius: BorderRadius.circular(23),
          border: Border.all(color: edge, width: 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 19, color: leadColor),
            const SizedBox(width: 10),
            Expanded(
              // The field stays in the tree when disabled so the placeholder
              // measures and aligns exactly like the live one.
              child: TextField(
                controller: _controller,
                enabled: enabled,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                style: KalinkaFonts.mono(
                  fontSize: KalinkaTypography.baseSize + 2,
                  color: KalinkaColors.textPrimary,
                ),
                cursorColor: KalinkaColors.accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: widget.hint,
                  hintStyle: KalinkaFonts.mono(
                    fontSize: KalinkaTypography.baseSize + 2,
                    color: KalinkaColors.textMuted,
                  ),
                ),
              ),
            ),
            if (enabled)
              // Listens to the controller rather than the reported query, so
              // the clear affordance appears with the first keystroke.
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) {
                  if (value.text.isEmpty) return const SizedBox.shrink();
                  return GestureDetector(
                    onTap: _clear,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: KalinkaColors.textMuted,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// One labelled facet: a mono caption over a wrap of pills.
class _FacetGroup extends StatelessWidget {
  final String label;
  final List<Widget> pills;

  /// One quiet line under the pills, where a group needs a word of
  /// explanation.
  final String? caption;

  const _FacetGroup({required this.label, required this.pills, this.caption});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: KalinkaFonts.mono(
            fontSize: KalinkaTypography.baseSize,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.8,
            color: KalinkaColors.textSectionLabel,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 7, runSpacing: 7, children: pills),
        if (caption != null) ...[
          const SizedBox(height: 8),
          _FacetCaption(caption!),
        ],
      ],
    );
  }
}

/// One quiet line under a control, saying what it does.
class _FacetCaption extends StatelessWidget {
  final String text;

  const _FacetCaption(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: KalinkaTextStyles.trackRowSubtitle.copyWith(
        color: KalinkaColors.textMuted,
      ),
    );
  }
}

/// Which of a search's two blocks to show.
class _KindGroup extends StatelessWidget {
  final ResultKind? selected;
  final ValueChanged<ResultKind?> onSelected;

  const _KindGroup({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return _FacetGroup(
      label: 'RESULT KIND',
      caption: 'Choose lookup, discovery, or both',
      pills: [
        FilterPill(
          label: 'All results',
          selected: selected == null,
          onTap: () => onSelected(null),
        ),
        for (final kind in ResultKind.values)
          FilterPill(
            label: resultKindLabel(kind),
            selected: selected == kind,
            onTap: () => onSelected(kind),
          ),
      ],
    );
  }
}

/// The sources to keep, each pill leading with the source's own mark.
class _SourceGroup extends StatelessWidget {
  final BrowseFilterCapabilities capabilities;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  const _SourceGroup({
    required this.capabilities,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _FacetGroup(
      label: 'SOURCE',
      pills: [
        FilterPill(
          label: 'All sources',
          selected: selected.isEmpty,
          onTap: selected.isEmpty ? null : () => onChanged(const []),
        ),
        for (final source in capabilities.sources)
          FilterPill(
            label: source.title,
            leading: SourceTile(source: source.name),
            selected: selected.contains(source.name),
            onTap: () => onChanged(
              selected.contains(source.name)
                  ? [...selected.where((name) => name != source.name)]
                  : [...selected, source.name],
            ),
          ),
      ],
    );
  }
}

/// How the name matches are ordered. The recommendations are not on offer:
/// their order is the source's ranking, which nothing here can improve on.
class _OrderGroup extends StatelessWidget {
  final NameMatchOrder selected;
  final ValueChanged<NameMatchOrder> onSelected;

  const _OrderGroup({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return _FacetGroup(
      label: 'SORT NAME MATCHES',
      caption: 'Recommendations keep their smart order.',
      pills: [
        FilterPill(
          label: 'Relevance',
          selected: selected == NameMatchOrder.relevance,
          onTap: () => onSelected(NameMatchOrder.relevance),
        ),
        FilterPill(
          label: 'A–Z',
          selected: selected == NameMatchOrder.alphabetical,
          onTap: () => onSelected(NameMatchOrder.alphabetical),
        ),
      ],
    );
  }
}

/// The entity-kind group. With [onSelected] it filters; without one it is a
/// read-out — a single-kind collection lights the kind it holds and greys the
/// rest, which is all a catalog page can honestly say.
class _TypeGroup extends StatelessWidget {
  final BrowseFilterCapabilities capabilities;
  final SearchType? selected;
  final ValueChanged<SearchType?>? onSelected;

  const _TypeGroup({
    required this.capabilities,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final interactive = onSelected != null;
    return _FacetGroup(
      label: 'TYPE',
      pills: [
        // "All" is a choice, so it only exists where there is a choice to make.
        if (interactive)
          FilterPill(
            label: 'All',
            selected: selected == null,
            onTap: () => onSelected!(null),
          ),
        for (final type in capabilities.types)
          FilterPill(
            label: filterTypeLabel(type),
            // Inert row: the kind the collection holds reads as the standing
            // answer.
            selected: interactive
                ? selected == type
                : capabilities.presentTypes.contains(type),
            muted: !capabilities.presentTypes.contains(type),
            onTap: interactive && capabilities.presentTypes.contains(type)
                ? () => onSelected!(type)
                : null,
          ),
      ],
    );
  }
}

/// Genre pills, live. Stays a lone muted placeholder while the taxonomy loads
/// and if it comes back empty — a source can declare the capability and still
/// have no genres.
class _GenreGroup extends ConsumerWidget {
  final BrowseFilterCapabilities capabilities;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  const _GenreGroup({
    required this.capabilities,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vocabulary = capabilities.genreVocabulary;
    final live =
        capabilities.genre == FacetSupport.supported && vocabulary != null;
    final genres =
        capabilities.genreOptions ??
        (live ? ref.watch(browseGenresProvider(vocabulary)).value : null);
    final ready = genres != null && genres.isNotEmpty;

    return _FacetGroup(
      label: 'GENRE',
      pills: [
        FilterPill(
          label: 'All genres',
          selected: ready && selected.isEmpty,
          muted: !ready,
          onTap: ready && selected.isNotEmpty
              ? () => onChanged(const [])
              : null,
        ),
        if (ready)
          for (final genre in genres)
            FilterPill(
              label: genre.name,
              selected: selected.contains(genre.id),
              onTap: () => onChanged(
                selected.contains(genre.id)
                    ? [...selected.where((id) => id != genre.id)]
                    : [...selected, genre.id],
              ),
            ),
      ],
    );
  }
}

String resultKindLabel(ResultKind kind) => switch (kind) {
  ResultKind.nameMatches => 'Name matches',
  ResultKind.recommendations => 'Recommendations',
};

String filterTypeLabel(SearchType type) {
  switch (type) {
    case SearchType.artist:
      return 'Artists';
    case SearchType.album:
      return 'Albums';
    case SearchType.track:
      return 'Tracks';
    case SearchType.playlist:
      return 'Playlists';
    case SearchType.invalid:
      return '';
  }
}

/// A filter pill: a filled crimson segment when it carries the current answer,
/// plain surface when it is an available alternative, outline-only when the
/// surface does not offer it.
///
/// A solid fill because that is what a chosen value looks like everywhere else
/// in the app — the settings segmented control, a toggle that is on, the
/// primary button. Crimson *outlines* are reserved for things that are
/// accent-flavoured without being a value: the action a set leads with, the
/// current-item row tint. What a choice leaves behind — the chips above the
/// listing — is grey.
class FilterPill extends StatefulWidget {
  final String label;
  final bool selected;

  /// Not offered here — dimmed, and inert regardless of [onTap].
  final bool muted;

  final VoidCallback? onTap;

  /// A mark ahead of the label, such as a source's tile.
  final Widget? leading;

  const FilterPill({
    super.key,
    required this.label,
    this.selected = false,
    this.muted = false,
    this.onTap,
    this.leading,
  });

  @override
  State<FilterPill> createState() => _FilterPillState();
}

class _FilterPillState extends State<FilterPill> {
  bool _hovering = false;

  void _setHovering(bool value) {
    if (value == _hovering) return;
    setState(() => _hovering = value);
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.selected && !widget.muted;
    final enabled = widget.onTap != null && !widget.muted;
    final hovered = _hovering && enabled;

    final Color fg;
    final Color bg;
    final Color border;
    if (on) {
      fg = KalinkaColors.textPrimary;
      // Hover lightens the crimson itself — berry over the base red.
      bg = hovered ? KalinkaColors.accentTint : KalinkaColors.accent;
      border = bg;
    } else if (widget.muted) {
      fg = KalinkaColors.textMuted;
      bg = Colors.transparent;
      border = KalinkaColors.borderSubtle;
    } else {
      fg = KalinkaColors.textPrimary;
      bg = hovered
          ? KalinkaColors.surfaceOverlay
          : KalinkaColors.surfaceElevated;
      border = hovered ? KalinkaColors.textMuted : KalinkaColors.borderDefault;
    }

    // Sized by its padding, never by an alignment: a Container with one
    // expands to the constraints it is handed, and a Wrap hands out the full
    // line width — which turned a row of chips into a column of slabs.
    Widget pill = AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(widget.leading == null ? 14 : 8, 7, 14, 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(width: 8),
          ],
          Text(
            widget.label,
            style: KalinkaFonts.sans(
              fontSize: KalinkaTypography.baseSize + 1,
              fontWeight: FontWeight.w500,
              color: fg,
            ),
          ),
        ],
      ),
    );

    if (enabled) {
      pill = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovering(true),
        onExit: (_) => _setHovering(false),
        child: GestureDetector(
          onTap: () {
            KalinkaHaptics.selectionClick();
            widget.onTap!();
          },
          behavior: HitTestBehavior.opaque,
          child: pill,
        ),
      );
    }

    return Semantics(
      button: enabled,
      selected: on,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: pill,
    );
  }
}
