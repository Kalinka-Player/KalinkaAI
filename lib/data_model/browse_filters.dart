import 'dart:convert';

import 'data_model.dart'
    show FilterKind, FilterSpec, Genre, SearchType, SearchTypeExtension;

/// The field id every source uses for the entity kind — the one values
/// field a consumer may recognise by name rather than by vocabulary.
const kTypeFieldId = 'type';

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

  final FacetSupport genre;

  /// The catalog whose vocabulary fills the genre facet, and the field id it
  /// is filled from. Null where there is no genre facet to fill, or where
  /// [genreOptions] already holds it.
  final ({String catalogId, String field})? genreVocabulary;

  /// The genre vocabulary held in hand — a surface that already knows what
  /// it holds, like loaded search results, fills the facet without a fetch.
  final List<Genre>? genreOptions;

  /// The genre field as its source declared it — the id the request addresses
  /// it by, and the combination the source honours.
  final FilterSpec? genreField;

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
    this.genre = FacetSupport.hidden,
    this.genreVocabulary,
    this.genreOptions,
    this.genreField,
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
    // is matched by id; any other is the vocabulary the genre facet fills from.
    final typeField = find(
      (s) => s.kind == FilterKind.choice && s.id == kTypeFieldId,
    );
    final genreField = find(
      (s) => s.kind == FilterKind.choice && s.id != kTypeFieldId,
    );
    return BrowseFilterCapabilities(
      text: textField == null ? FacetSupport.hidden : FacetSupport.supported,
      type: typeField == null || types.isEmpty
          ? FacetSupport.hidden
          : FacetSupport.supported,
      types: typeField == null ? const [] : types,
      presentTypes: typeField == null ? const {} : types.toSet(),
      genre: genreField == null ? FacetSupport.hidden : FacetSupport.supported,
      genreVocabulary: genreField == null
          ? null
          : (catalogId: catalogId, field: genreField.id),
      genreField: genreField,
      textField: textField,
      typeField: typeField,
    );
  }

  /// True when nothing at all would render — callers skip the bar entirely.
  bool get isEmpty =>
      text == FacetSupport.hidden &&
      genre == FacetSupport.hidden &&
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

enum BrowseFacet { text, type, genre, kind, source, order }

/// The active filter selection — one request object rather than a widening
/// list of arguments, so the surfaces above it never learn how it travels.
/// A catalog page sends the facets its source declared; search results apply
/// every facet to what they already hold.
class BrowseFilterQuery {
  final String text;

  /// Null means "all kinds".
  final SearchType? type;

  final List<String> genreIds;

  /// Null means both blocks.
  final ResultKind? kind;

  /// Empty means every source.
  final List<String> sources;

  final NameMatchOrder order;

  const BrowseFilterQuery({
    this.text = '',
    this.type,
    this.genreIds = const [],
    this.kind,
    this.sources = const [],
    this.order = NameMatchOrder.relevance,
  });

  bool get isEmpty =>
      text.isEmpty &&
      type == null &&
      genreIds.isEmpty &&
      kind == null &&
      sources.isEmpty &&
      order == NameMatchOrder.relevance;

  /// How many separate answers this query carries — the number on the filter
  /// button's badge, and the number of chips shown above the rows. Each genre
  /// and each source counts on its own, because each is separately removable.
  int get activeCount =>
      (text.isEmpty ? 0 : 1) +
      (type == null ? 0 : 1) +
      genreIds.length +
      (kind == null ? 0 : 1) +
      sources.length +
      (order == NameMatchOrder.relevance ? 0 : 1);

  /// Whether every answer this query carries is live under [capabilities].
  /// False means a surface built on them would list as if unfiltered: the
  /// look of a filter with none of its effect.
  bool isHonouredBy(BrowseFilterCapabilities capabilities) =>
      (text.isEmpty || capabilities.text == FacetSupport.supported) &&
      (type == null || capabilities.type == FacetSupport.supported) &&
      (genreIds.isEmpty || capabilities.genre == FacetSupport.supported) &&
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
    final offeredGenres = capabilities.genreOptions == null
        ? null
        : {for (final g in capabilities.genreOptions!) g.id};
    return BrowseFilterQuery(
      text: live(capabilities.text) ? text : '',
      type: live(capabilities.type) && capabilities.types.contains(type)
          ? type
          : null,
      // Genres fetched on demand are not known here, so they are kept.
      genreIds: !live(capabilities.genre)
          ? const []
          : [
              for (final id in genreIds)
                if (offeredGenres == null || offeredGenres.contains(id)) id,
            ],
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

    return {
      if (text != other.text) BrowseFacet.text,
      if (type != other.type) BrowseFacet.type,
      if (!same(genreIds, other.genreIds)) BrowseFacet.genre,
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
    genreIds: facets.contains(BrowseFacet.genre) ? other.genreIds : genreIds,
    kind: facets.contains(BrowseFacet.kind) ? other.kind : kind,
    sources: facets.contains(BrowseFacet.source) ? other.sources : sources,
    order: facets.contains(BrowseFacet.order) ? other.order : order,
  );

  Map<String, Object> toJson() => {
    if (text.isNotEmpty) 'text': text,
    if (type case final type?) 'type': type.name,
    if (genreIds.isNotEmpty) 'genreIds': genreIds,
    if (kind case final kind?) 'kind': kind.name,
    if (sources.isNotEmpty) 'sources': sources,
    if (order != NameMatchOrder.relevance) 'order': order.name,
  };

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
    return BrowseFilterQuery(
      text: text is String ? text : '',
      type: type == SearchType.invalid ? null : type,
      genreIds: strings(json['genreIds']),
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
    List<String>? genreIds,
    ResultKind? kind,
    bool clearKind = false,
    List<String>? sources,
    NameMatchOrder? order,
  }) {
    return BrowseFilterQuery(
      text: text ?? this.text,
      type: clearType ? null : (type ?? this.type),
      genreIds: genreIds ?? this.genreIds,
      kind: clearKind ? null : (kind ?? this.kind),
      sources: sources ?? this.sources,
      order: order ?? this.order,
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

    final genreField = capabilities.genreField;
    if (genreField != null &&
        capabilities.genre == FacetSupport.supported &&
        genreIds.isNotEmpty) {
      fields[genreField.id] = {genreField.defaultOp.name: genreIds};
    }

    return fields.isEmpty ? null : jsonEncode(fields);
  }
}
