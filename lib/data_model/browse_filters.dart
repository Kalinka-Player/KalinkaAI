import 'dart:convert';

import 'data_model.dart'
    show
        FilterKind,
        FilterOp,
        FilterSpec,
        FilterValue,
        SearchType,
        SearchTypeExtension;

/// The field id every source uses for the entity kind — the one values
/// field a consumer may recognise by name rather than by vocabulary.
const kTypeFieldId = 'type';

/// The field id sources give genre. Search results narrow by their own genres
/// under it, and filters saved while genre was the only values facet load
/// their genres into it.
const kGenreFieldId = 'genre';

/// The genre facet of search results, over the genres of what they hold: an
/// item matches when it has any one of those chosen.
const kResultsGenreField = FilterSpec(
  id: kGenreFieldId,
  kind: FilterKind.choice,
  label: 'Genre',
  ops: [FilterOp.any],
);

/// Which vocabulary fills a values facet: one catalog's one field. Scoped to
/// the catalog rather than the source because a field is declared per shelf —
/// Jamendo offers genre on its track shelf alone.
typedef FilterVocabulary = ({String catalogId, String field});

/// How far one filter facet is supported by the data source behind a surface.
enum FacetSupport {
  /// Not applicable — the control is not rendered at all.
  hidden,

  /// Rendered, but inert and muted: nothing behind this surface can honour it
  /// yet (or the answer is fixed). A placeholder never reaches
  /// [BrowseFilterQuery.serverKey], so it can never trigger a refetch that
  /// would quietly come back unfiltered.
  unsupported,

  /// Live — the selection is part of the request.
  supported,
}

/// The two blocks a search answers with: what was looked up by name, and
/// what was found for it.
enum ResultKind { nameMatches, recommendations }

/// How the name matches are ordered. Recommendations keep their own order
/// regardless: it is the source's ranking, and nothing here can improve it.
enum NameMatchOrder { relevance, alphabetical }

/// One source a results surface can be narrowed to.
typedef SourceOption = ({String name, String title});

extension SourceOptions on List<SourceOption> {
  /// The title [name] shows under, or the name itself where it is not listed.
  String titleOf(String name) {
    for (final option in this) {
      if (option.name == name) return option.title;
    }
    return name;
  }
}

/// A field narrowed to some of its values — genre, decade, or any other its
/// source declares — as one surface offers it.
class ChoiceFacet {
  /// The field as declared: the id a filter addresses it by, the label its
  /// group goes under, and the combination its source honours.
  final FilterSpec field;

  final FacetSupport support;

  /// Where its values are fetched from. Null where [options] holds them.
  final FilterVocabulary? vocabulary;

  /// The values held in hand, in the order to offer them — a surface that
  /// already knows what it holds, like loaded search results, fills the
  /// facet without a fetch.
  final List<FilterValue>? options;

  const ChoiceFacet({
    required this.field,
    this.support = FacetSupport.supported,
    this.vocabulary,
    this.options,
  });

  String get id => field.id;

  ChoiceFacet withSupport(FacetSupport support) => ChoiceFacet(
    field: field,
    support: support,
    vocabulary: vocabulary,
    options: options,
  );
}

/// What a browsable surface can be filtered by. Facets the backend can honour
/// are [FacetSupport.supported]; the rest render as placeholders or not at all.
///
/// Derived per surface from the shape of the endpoint behind it. Keeping it a
/// descriptor rather than a pile of booleans on each screen is what lets one
/// form serve catalog pages, search results, and whatever comes next.
class BrowseFilterCapabilities {
  /// Free-text filtering over the collection.
  final FacetSupport text;

  /// Filtering by entity kind. [unsupported] still renders [types] — a
  /// single-type collection reports what it holds rather than filtering it.
  final FacetSupport type;

  /// Entity kinds to render, in display order. Empty hides the row.
  final List<SearchType> types;

  /// The subset of [types] this collection actually contains. Others render
  /// dimmed; when [type] is [FacetSupport.unsupported] these read as selected.
  final Set<SearchType> presentTypes;

  /// The values fields on offer, in the order their source declared them.
  final List<ChoiceFacet> choices;

  /// The free-text field as its source declared it; its label says what that
  /// source matches, which differs between sources.
  final FilterSpec? textField;

  /// The entity-kind field as its source declared it. Only a listing that
  /// mixes kinds has one.
  final FilterSpec? typeField;

  /// Choosing between the result blocks. Only a search answers with two.
  final FacetSupport kind;

  /// Narrowing to a source. Only a surface that holds several has a choice.
  final FacetSupport source;

  /// Sources to render, in display order.
  final List<SourceOption> sources;

  /// Ordering the name matches.
  final FacetSupport order;

  const BrowseFilterCapabilities({
    this.text = FacetSupport.hidden,
    this.type = FacetSupport.hidden,
    this.types = const [],
    this.presentTypes = const {},
    this.choices = const [],
    this.textField,
    this.typeField,
    this.kind = FacetSupport.hidden,
    this.source = FacetSupport.hidden,
    this.sources = const [],
    this.order = FacetSupport.hidden,
  });

  /// What a surface offers, from what its source declared for it. A facet the
  /// source did not declare is hidden: the app never decides for itself what a
  /// source can honour, so a control is shown only where it will be.
  factory BrowseFilterCapabilities.fromSpecs(
    List<FilterSpec> specs, {
    required String catalogId,
    List<SearchType> types = const [],
  }) {
    FilterSpec? find(bool Function(FilterSpec) test) {
      for (final spec in specs) {
        if (test(spec)) return spec;
      }
      return null;
    }

    final textField = find((s) => s.kind == FilterKind.text);
    // `type` is the one values field every source spells the same way, so it
    // is matched by id; every other is a facet of its own, filled from its
    // own vocabulary.
    final typeField = find(
      (s) => s.kind == FilterKind.choice && s.id == kTypeFieldId,
    );
    return BrowseFilterCapabilities(
      text: textField == null ? FacetSupport.hidden : FacetSupport.supported,
      type: typeField == null || types.isEmpty
          ? FacetSupport.hidden
          : FacetSupport.supported,
      types: typeField == null ? const [] : types,
      presentTypes: typeField == null ? const {} : types.toSet(),
      choices: [
        for (final spec in specs)
          if (spec.kind == FilterKind.choice && spec.id != kTypeFieldId)
            ChoiceFacet(
              field: spec,
              vocabulary: (catalogId: catalogId, field: spec.id),
            ),
      ],
      textField: textField,
      typeField: typeField,
    );
  }

  /// The facet over [field], where this surface offers one.
  ChoiceFacet? choice(String field) {
    for (final facet in choices) {
      if (facet.id == field) return facet;
    }
    return null;
  }

  /// Whether any values facet renders.
  bool get hasChoices =>
      choices.any((facet) => facet.support != FacetSupport.hidden);

  /// True when nothing at all would render — callers skip the bar entirely.
  bool get isEmpty =>
      text == FacetSupport.hidden &&
      !hasChoices &&
      (type == FacetSupport.hidden || types.isEmpty) &&
      kind == FacetSupport.hidden &&
      (source == FacetSupport.hidden || sources.isEmpty) &&
      order == FacetSupport.hidden;

  /// The canonical entity-kind row. Order is the one the mockups use.
  static const allTypes = <SearchType>[
    SearchType.artist,
    SearchType.album,
    SearchType.track,
    SearchType.playlist,
  ];
}

/// One facet of a query. [choice] stands for every values field at once.
enum BrowseFacet { text, type, choice, kind, source, order }

/// The active filter selection — one request object rather than a widening
/// list of arguments, so the surfaces above it never learn how it travels.
/// A catalog page sends the facets its source declared; search results apply
/// every facet to what they already hold.
class BrowseFilterQuery {
  final String text;

  /// Null means "all kinds".
  final SearchType? type;

  /// The values chosen in each values field, by field id. A field missing or
  /// empty is unconstrained.
  final Map<String, List<String>> selections;

  /// Null means both blocks.
  final ResultKind? kind;

  /// Empty means every source.
  final List<String> sources;

  final NameMatchOrder order;

  /// Values an app from before several values fields saved for its one
  /// values facet, which stood for whichever field the shelf declared first:
  /// [fittedTo] files them under that field.
  final List<String> legacyChoice;

  const BrowseFilterQuery({
    this.text = '',
    this.type,
    this.selections = const {},
    this.kind,
    this.sources = const [],
    this.order = NameMatchOrder.relevance,
    this.legacyChoice = const [],
  });

  /// The values chosen in [field].
  List<String> selected(String field) => selections[field] ?? const [];

  List<String> get genreIds => selected(kGenreFieldId);

  /// This query with [ids] chosen in [field] instead.
  BrowseFilterQuery withSelected(String field, List<String> ids) => copyWith(
    selections: {
      for (final MapEntry(:key, :value) in selections.entries)
        if (key != field) key: value,
      if (ids.isNotEmpty) field: ids,
    },
  );

  bool get isEmpty =>
      text.isEmpty &&
      type == null &&
      selections.values.every((ids) => ids.isEmpty) &&
      kind == null &&
      sources.isEmpty &&
      order == NameMatchOrder.relevance;

  /// How many separate answers this query carries — the number on the filter
  /// button's badge, and the number of chips shown above the rows. Each value
  /// and each source counts on its own, because each is separately removable.
  int get activeCount =>
      (text.isEmpty ? 0 : 1) +
      (type == null ? 0 : 1) +
      selections.values.fold<int>(0, (count, ids) => count + ids.length) +
      (kind == null ? 0 : 1) +
      sources.length +
      (order == NameMatchOrder.relevance ? 0 : 1);

  /// Whether every answer this query carries is live under [capabilities].
  /// False means a surface built on them would list as if unfiltered: the
  /// look of a filter with none of its effect.
  bool isHonouredBy(BrowseFilterCapabilities capabilities) =>
      (text.isEmpty || capabilities.text == FacetSupport.supported) &&
      (type == null || capabilities.type == FacetSupport.supported) &&
      selections.entries.every(
        (selection) =>
            selection.value.isEmpty ||
            capabilities.choice(selection.key)?.support ==
                FacetSupport.supported,
      ) &&
      (kind == null || capabilities.kind == FacetSupport.supported) &&
      (sources.isEmpty || capabilities.source == FacetSupport.supported) &&
      (order == NameMatchOrder.relevance ||
          capabilities.order == FacetSupport.supported);

  /// Whether the filter includes this result kind and source.
  /// A null source matches any source.
  bool shows(ResultKind kind, String? source) =>
      (this.kind == null || this.kind == kind) &&
      (source == null || sources.isEmpty || sources.contains(source));

  /// Removes selections this screen cannot display or apply.
  BrowseFilterQuery fittedTo(BrowseFilterCapabilities capabilities) {
    bool live(FacetSupport support) => support == FacetSupport.supported;
    final offeredSources = {for (final s in capabilities.sources) s.name};
    final legacyField = capabilities.choices.firstOrNull?.id;
    final filed = legacyChoice.isEmpty || legacyField == null
        ? this
        : withSelected(legacyField, [
            ...selected(legacyField),
            for (final id in legacyChoice)
              if (!selected(legacyField).contains(id)) id,
          ]);
    // Values fetched on demand are not known here, so they are kept.
    List<String> offered(ChoiceFacet facet) {
      final options = facet.options == null
          ? null
          : {for (final value in facet.options!) value.id};
      return [
        for (final id in filed.selected(facet.id))
          if (options == null || options.contains(id)) id,
      ];
    }

    return BrowseFilterQuery(
      text: live(capabilities.text) ? text : '',
      type: live(capabilities.type) && capabilities.types.contains(type)
          ? type
          : null,
      selections: {
        for (final facet in capabilities.choices)
          if (live(facet.support)) facet.id: offered(facet),
      }..removeWhere((_, ids) => ids.isEmpty),
      kind: live(capabilities.kind) ? kind : null,
      sources: live(capabilities.source)
          ? [
              for (final source in sources)
                if (offeredSources.contains(source)) source,
            ]
          : const [],
      order: live(capabilities.order) ? order : NameMatchOrder.relevance,
    );
  }

  Set<BrowseFacet> facetsChangedFrom(BrowseFilterQuery other) {
    bool same(List<String> a, List<String> b) {
      final picked = a.toSet();
      return picked.length == b.toSet().length && picked.containsAll(b);
    }

    final fields = {...selections.keys, ...other.selections.keys};
    return {
      if (text != other.text) BrowseFacet.text,
      if (type != other.type) BrowseFacet.type,
      if (!fields.every(
        (field) => same(selected(field), other.selected(field)),
      ))
        BrowseFacet.choice,
      if (kind != other.kind) BrowseFacet.kind,
      if (!same(sources, other.sources)) BrowseFacet.source,
      if (order != other.order) BrowseFacet.order,
    };
  }

  BrowseFilterQuery withFacetsFrom(
    BrowseFilterQuery other,
    Set<BrowseFacet> facets,
  ) => BrowseFilterQuery(
    text: facets.contains(BrowseFacet.text) ? other.text : text,
    type: facets.contains(BrowseFacet.type) ? other.type : type,
    selections: facets.contains(BrowseFacet.choice)
        ? other.selections
        : selections,
    kind: facets.contains(BrowseFacet.kind) ? other.kind : kind,
    sources: facets.contains(BrowseFacet.source) ? other.sources : sources,
    order: facets.contains(BrowseFacet.order) ? other.order : order,
  );

  Map<String, Object> toJson() {
    final values = {
      for (final field in selections.keys.toList()..sort())
        if (selected(field).isNotEmpty) field: selected(field),
    };
    return {
      if (text.isNotEmpty) 'text': text,
      if (type case final type?) 'type': type.name,
      // Genre also under the key older apps read, so they still load it.
      if (genreIds.isNotEmpty || legacyChoice.isNotEmpty)
        'genreIds': genreIds.isNotEmpty ? genreIds : legacyChoice,
      if (values.isNotEmpty) 'values': values,
      if (kind case final kind?) 'kind': kind.name,
      if (sources.isNotEmpty) 'sources': sources,
      if (order != NameMatchOrder.relevance) 'order': order.name,
    };
  }

  /// Ignores unknown values from older saved filters.
  factory BrowseFilterQuery.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? value) => value is List
        ? [
            for (final item in value)
              if (item is String) item,
          ]
        : const [];
    final type = SearchType.values.asNameMap()[json['type']];
    final text = json['text'];
    final values = json['values'];
    final savedWithGenre = values is Map && values.containsKey(kGenreFieldId);
    return BrowseFilterQuery(
      text: text is String ? text : '',
      type: type == SearchType.invalid ? null : type,
      selections: {
        if (values is Map)
          for (final MapEntry(:key, :value) in values.entries)
            if (key is String && strings(value).isNotEmpty) key: strings(value),
      },
      legacyChoice: savedWithGenre ? const [] : strings(json['genreIds']),
      kind: ResultKind.values.asNameMap()[json['kind']],
      sources: strings(json['sources']),
      order:
          NameMatchOrder.values.asNameMap()[json['order']] ??
          NameMatchOrder.relevance,
    );
  }

  BrowseFilterQuery copyWith({
    String? text,
    SearchType? type,
    bool clearType = false,
    Map<String, List<String>>? selections,
    ResultKind? kind,
    bool clearKind = false,
    List<String>? sources,
    NameMatchOrder? order,
  }) {
    return BrowseFilterQuery(
      text: text ?? this.text,
      type: clearType ? null : (type ?? this.type),
      selections: selections ?? this.selections,
      kind: clearKind ? null : (kind ?? this.kind),
      sources: sources ?? this.sources,
      order: order ?? this.order,
      legacyChoice: legacyChoice,
    );
  }

  /// Identity of the part of this query the backend will actually see, under
  /// [capabilities]. Lists reload on this string alone — so touching an inert
  /// facet costs nothing, and a facet that starts being honoured begins
  /// triggering refetches the moment its capability flips.
  ///
  /// It is [encoded] itself rather than a parallel encoding of the same
  /// facets, so the key and the request can never disagree about what travels.
  String serverKey(BrowseFilterCapabilities capabilities) =>
      encoded(capabilities) ?? '';

  /// The filter as the server's document — field id to selector — or null when
  /// nothing this surface declared is constrained.
  ///
  /// Only facets the surface declared travel, and a values field carries the
  /// operation its source said it honours, so chips never imply a union a
  /// source will not perform.
  String? encoded(BrowseFilterCapabilities capabilities) {
    final fields = <String, dynamic>{};

    final textField = capabilities.textField;
    if (textField != null &&
        capabilities.text == FacetSupport.supported &&
        text.isNotEmpty) {
      fields[textField.id] = {'contains': text};
    }

    final typeField = capabilities.typeField;
    final type = this.type;
    if (typeField != null &&
        capabilities.type == FacetSupport.supported &&
        type != null) {
      fields[typeField.id] = {
        typeField.defaultOp.name: [type.toStringValue()],
      };
    }

    for (final facet in capabilities.choices) {
      final ids = selected(facet.id);
      if (facet.support == FacetSupport.supported && ids.isNotEmpty) {
        fields[facet.id] = {facet.field.defaultOp.name: ids};
      }
    }

    return fields.isEmpty ? null : jsonEncode(fields);
  }
}
