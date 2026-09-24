import 'dart:async';

import 'package:flutter/material.dart';
// Not re-exported through material.dart as of Flutter 3.44.
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../data_model/presentation_schema.dart';
import '../theme/app_theme.dart';
import 'settings_controls/settings_binding.dart';
import 'settings_renderer.dart' show buildFieldControl;

/// About:config-style flat search across every settable field of one store.
///
/// Takes the fields and the [SettingsBinding] behind them rather than reading a
/// provider, so the same list serves the server's settings and a renderer's —
/// two stores with different transports and save semantics, one power-user
/// surface.
///
/// Deliberately styled so users can't confuse it with the simple page:
/// monospaced full dotted paths as row titles, flat continuous list (no cards),
/// tighter vertical rhythm. Editing semantics are identical to simple settings
/// — same control widgets, same staging flow, same amber pending pill.
class ExpertFieldList extends StatefulWidget {
  /// Every settable field, both tiers, in the order they should be listed.
  final List<FieldSpec> fields;

  /// The store the rows read and stage against. A new instance means the rows
  /// below should rebuild.
  final SettingsBinding binding;

  const ExpertFieldList({
    super.key,
    required this.fields,
    required this.binding,
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

    return Column(
      children: [
        _SearchBar(
          controller: _searchController,
          focusNode: _searchFocusNode,
          // Tiny match counter inside the search field only when the
          // query is actually narrowing things — avoids permanent
          // chrome that adds visual noise the rest of the time.
          matchCount: _query.trim().isEmpty
              ? null
              : '${filtered.length} / ${all.length}',
        ),
        Expanded(
          child: filtered.isEmpty
              ? _EmptyState(query: _query)
              : ListView.separated(
                  // Cache more than the default — paths are mono and
                  // the rows are stable, so caching a generous window
                  // avoids re-init of TextInput controllers when the
                  // user scrolls back to a row they just touched.
                  scrollCacheExtent: ScrollCacheExtent.pixels(600),
                  padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
                  itemCount: filtered.length,
                  // 8 px gap between rows; each row carries its own
                  // horizontal margin so it reads as a discrete card.
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _ExpertRow(
                    key: ValueKey(filtered[i].path),
                    field: filtered[i],
                    binding: widget.binding,
                  ),
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Search bar
// ---------------------------------------------------------------------------

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? matchCount;
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    this.matchCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: KalinkaColors.surfaceBase,
        border: Border(bottom: BorderSide(color: KalinkaColors.borderSubtle)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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

/// Dense flat row for one field. Layout (all stacked, full-width):
///
///     ┃ base_config.output.alsa.device         ← mono path, top
///     ┃ Audio device                           ← human label
///     ┃ Hardware output…                       ← optional help
///     ┃ [ control — full width ]               ← editable input
///     ┃ Staged                                 ← pill when pending
///
/// The path always occupies the full row width — keeps long dotted
/// paths from being squashed against an inline control, and means the
/// vertical rhythm is the same no matter which widget kind the field
/// uses (no inline-vs-stacked branching). Each row sits on a
/// surfaceRaised slab with a small gap to its neighbours, supplying
/// the visual separation without inheriting the simple-page card
/// chrome. The amber left-edge appears when staged, matching the
/// simple-row convention so the pending-state cue is consistent.
class _ExpertRow extends StatelessWidget {
  final FieldSpec field;
  final SettingsBinding binding;
  const _ExpertRow({super.key, required this.field, required this.binding});

  @override
  Widget build(BuildContext context) {
    final value = binding.effectiveValue(field.path) ?? field.defaultValue;
    final isStaged = binding.isStaged(field.path);
    final isReadonly = field.readonly;

    final pathStyle = KalinkaFonts.mono(
      fontSize: KalinkaTypography.baseSize + 1,
      color: KalinkaColors.textPrimary,
      letterSpacing: -0.1,
      height: 1.3,
    );
    final labelStyle = KalinkaTextStyles.trayRowLabel.copyWith(
      fontSize: KalinkaTypography.baseSize,
      color: KalinkaColors.textSecondary,
      fontWeight: FontWeight.w400,
    );
    final helpStyle = KalinkaTextStyles.trayRowSublabel.copyWith(
      fontSize: KalinkaTypography.baseSize - 1,
      color: KalinkaColors.textMuted,
    );

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
      // Horizontal margin + rounded corners mirror the simple-page
      // cards' shape so each row reads as a discrete tile rather
      // than a slab spanning the full viewport edge to edge.
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isStaged
            ? KalinkaColors.statusPending.withValues(alpha: 0.06)
            : KalinkaColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isStaged
              ? KalinkaColors.statusPending.withValues(alpha: 0.4)
              : KalinkaColors.borderSubtle,
        ),
      ),
      // Clip so the staged tint and any selection highlights stay
      // inside the rounded outline.
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(field.path, style: pathStyle),
          const SizedBox(height: 4),
          Text(field.label, style: labelStyle),
          if (field.help != null && field.help!.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(field.help!, style: helpStyle),
          ],
          const SizedBox(height: 12),
          control,
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
