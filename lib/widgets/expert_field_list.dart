import 'dart:async';

import 'package:flutter/material.dart';
// Not re-exported through material.dart as of Flutter 3.44.
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../data_model/presentation_schema.dart';
import '../theme/app_theme.dart';
import 'settings_controls/settings_binding.dart';
import 'settings_renderer.dart' show buildFieldControl;
import 'configuration_appearance.dart';
import 'settings_controls/issue_notes.dart';
import 'settings_controls/settings_row.dart' show kSettingsGutter;

/// About:config-style flat search across every settable field of one store.
///
/// Takes the fields and the [SettingsBinding] behind them rather than reading a
/// provider, so the same list serves the server's settings and a renderer's —
/// two stores with different transports and save semantics, one power-user
/// surface.
///
/// Drawn as the simple page draws its settings — rows in one card, the same
/// colours, gutters and staged marking — with each row's full dotted path in
/// mono under its name, which is what this view is for. Editing semantics are
/// identical to simple settings: same control widgets, same staging flow.
class ExpertFieldList extends StatefulWidget {
  /// Every settable field, both tiers, in the order they should be listed.
  final List<FieldSpec> fields;

  /// The store the rows read and stage against. A new instance means the rows
  /// below should rebuild.
  final SettingsBinding binding;

  /// Built as a sliver, for a scroll view of the host's own (its search bar
  /// pinned under whatever the host pins); else a scroll view of its own.
  final bool sliver;

  const ExpertFieldList({
    super.key,
    required this.fields,
    required this.binding,
    this.sliver = false,
  });

  @override
  State<ExpertFieldList> createState() => _ExpertFieldListState();
}

class _ExpertFieldListState extends State<ExpertFieldList> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _query = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// 150 ms debounce — fast enough to feel live, slow enough to skip
  /// rebuild churn while the user is mid-word. The expert list is at
  /// most a few hundred entries, so filtering itself is cheap; the
  /// debounce mainly avoids tearing down + rebuilding every row's
  /// state on every keystroke.
  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() => _query = _searchController.text);
    });
  }

  /// AND-search across terms: each whitespace-delimited token must
  /// appear somewhere in the field's path, label, or help text.
  /// Substring + case-insensitive — fastest mental model for users
  /// who already know roughly what they're looking for.
  bool _matches(FieldSpec f, List<String> terms) {
    if (terms.isEmpty) return true;
    final haystack = '${f.path} ${f.label} ${f.help ?? ''}'.toLowerCase();
    for (final t in terms) {
      if (!haystack.contains(t)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.fields;

    final terms = _query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final filtered = terms.isEmpty
        ? all
        : all.where((f) => _matches(f, terms)).toList();
    final gutter = ConfigurationAppearance.active(context)
        ? ConfigurationAppearance.gutter(context)
        : 16.0;

    final list = SliverMainAxisGroup(
      slivers: [
        PinnedHeaderSliver(
          child: _SearchBar(
            controller: _searchController,
            focusNode: _searchFocusNode,
            gutter: gutter,
            // Tiny match counter inside the search field only when the
            // query is actually narrowing things — avoids permanent
            // chrome that adds visual noise the rest of the time.
            matchCount: _query.trim().isEmpty
                ? null
                : '${filtered.length} / ${all.length}',
          ),
        ),
        if (filtered.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 48),
              child: _EmptyState(query: _query),
            ),
          )
        else
          // One card, as the simple page groups its rows, drawn around
          // however much of the list is laid out.
          SliverPadding(
            padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 32),
            sliver: DecoratedSliver(
              decoration: BoxDecoration(
                color: KalinkaColors.surfaceRaised,
                borderRadius: BorderRadius.circular(_cardRadius),
                border: Border.all(color: KalinkaColors.borderSubtle),
              ),
              sliver: SliverList.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const Divider(
                  height: 1,
                  thickness: 1,
                  color: KalinkaColors.borderSubtle,
                ),
                itemBuilder: (_, i) => ClipRRect(
                  // Inside the card's rounded ends, so a staged row's tint
                  // keeps to them.
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(i == 0 ? _cardRadius - 1 : 0),
                    bottom: Radius.circular(
                      i == filtered.length - 1 ? _cardRadius - 1 : 0,
                    ),
                  ),
                  child: _ExpertRow(
                    key: ValueKey(filtered[i].path),
                    field: filtered[i],
                    binding: widget.binding,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    if (widget.sliver) return list;
    return CustomScrollView(
      // Cache more than the default — the rows are stable, so caching a
      // generous window avoids re-init of TextInput controllers when the
      // user scrolls back to a row they just touched.
      scrollCacheExtent: const ScrollCacheExtent.pixels(600),
      slivers: [list],
    );
  }

  static const _cardRadius = 14.0;
}

// ---------------------------------------------------------------------------
// Search bar
// ---------------------------------------------------------------------------

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? matchCount;
  final double gutter;
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.gutter,
    this.matchCount,
  });

  @override
  Widget build(BuildContext context) {
    // The page's own ground, opaque so rows scroll under it unseen.
    return Container(
      color: KalinkaColors.background,
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: gutter),
      child: Container(
        decoration: BoxDecoration(
          color: KalinkaColors.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: KalinkaColors.borderDefault),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const Icon(
              Icons.search,
              size: 16,
              color: KalinkaColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autocorrect: false,
                enableSuggestions: false,
                style: KalinkaTextStyles.textFieldInput,
                decoration: InputDecoration(
                  hintText: 'Search settings… (space = AND)',
                  hintStyle: KalinkaTextStyles.searchPlaceholder.copyWith(
                    fontSize: KalinkaTypography.baseSize + 2,
                    color: KalinkaColors.textSecondary,
                  ),
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: InputBorder.none,
                ),
              ),
            ),
            if (matchCount != null) ...[
              const SizedBox(width: 8),
              Text(
                matchCount!,
                style: KalinkaFonts.mono(
                  fontSize: KalinkaTypography.baseSize - 1,
                  color: KalinkaColors.textMuted,
                ),
              ),
            ],
            if (controller.text.isNotEmpty)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  controller.clear();
                  focusNode.requestFocus();
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: KalinkaColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final String query;
  const _EmptyState({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off,
              size: 32,
              color: KalinkaColors.textMuted,
            ),
            const SizedBox(height: 12),
            Text('No settings match', style: KalinkaTextStyles.cardTitle),
            const SizedBox(height: 6),
            Text(
              query.trim().isEmpty
                  ? 'Nothing to show.'
                  : 'Try fewer or different terms — search uses '
                        'AND across whitespace-separated words.',
              textAlign: TextAlign.center,
              style: KalinkaTextStyles.trayRowSublabel,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// One expert row
// ---------------------------------------------------------------------------

/// One field as a settings row (SettingsRow's padding, type and staged
/// marking), stacked so a long dotted path never squashes its control:
///
///     Audio device                           ← its name
///     base_config.output.alsa.device         ← mono path
///     Hardware output…                       ← optional help
///     [ control — full width ]               ← editable input
class _ExpertRow extends StatelessWidget {
  final FieldSpec field;
  final SettingsBinding binding;
  const _ExpertRow({super.key, required this.field, required this.binding});

  @override
  Widget build(BuildContext context) {
    final value = binding.effectiveValue(field.path) ?? field.defaultValue;
    final isStaged = binding.isStaged(field.path);
    final isReadonly = field.readonly;

    final control = isReadonly
        ? _ReadOnlyValue(value: value)
        : buildFieldControl(
            field: field,
            value: value,
            options: binding,
            secretHidden: binding.hasHiddenSecret(field.path),
            onChanged: (v) => binding.stage(field.path, v),
            // Expert rows allocate the full row width to each
            // control — let narrow widgets like the numeric input
            // stretch to fill rather than stranding on the left.
            compact: false,
          );

    return Container(
      color: isStaged
          ? KalinkaColors.statusPending.withValues(alpha: 0.04)
          : Colors.transparent,
      // As SettingsRow marks a staged row: painted over it, so staging never
      // shifts the content, and kept present so the control never remounts.
      foregroundDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: isStaged ? KalinkaColors.statusPending : Colors.transparent,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: kSettingsGutter,
        vertical: 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(field.label, style: KalinkaTextStyles.trayRowLabel),
              if (isStaged && ConfigurationAppearance.active(context))
                const ChangedSettingLabel(),
            ],
          ),
          const SizedBox(height: 2),
          SelectableText(
            field.path,
            style: KalinkaFonts.mono(
              fontSize: KalinkaTypography.baseSize,
              color: KalinkaColors.textMuted,
              height: 1.3,
            ),
          ),
          if (field.help != null && field.help!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(field.help!, style: KalinkaTextStyles.trayRowSublabel),
          ],
          const SizedBox(height: 10),
          control,
          IssueNotes(issues: binding.issuesFor(field.path)),
        ],
      ),
    );
  }
}

class _ReadOnlyValue extends StatelessWidget {
  final dynamic value;
  const _ReadOnlyValue({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceBase,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: KalinkaColors.borderSubtle),
      ),
      child: Text(
        (value ?? '').toString(),
        style: KalinkaFonts.mono(
          fontSize: KalinkaTypography.baseSize,
          color: KalinkaColors.textSecondary,
        ),
      ),
    );
  }
}
