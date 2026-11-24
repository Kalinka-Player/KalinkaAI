import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/browse_filters.dart'
    show ChoiceFacet, FacetSupport, FilterVocabulary;
import '../data_model/data_model.dart' show FilterValue;
import 'kalinka_player_api_provider.dart';

/// The values one catalog offers for one field, in the source's order. Only
/// reached from a surface whose capabilities say that field is honoured, so a
/// shelf without the vocabulary is never asked.
final filterValuesProvider =
    FutureProvider.family<List<FilterValue>, FilterVocabulary>((
      ref,
      vocabulary,
    ) async {
      final api = ref.watch(kalinkaProxyProvider);
      final list = await api.getFilterValues(
        vocabulary.catalogId,
        vocabulary.field,
      );
      return list.items;
    });

/// The values [facet] offers: those it holds, or its vocabulary's once fetched
/// while the facet is live. Null until known.
List<FilterValue>? watchChoiceValues(WidgetRef ref, ChoiceFacet facet) {
  if (facet.options case final options?) return options;
  final vocabulary = facet.vocabulary;
  if (facet.support != FacetSupport.supported || vocabulary == null) {
    return null;
  }
  return ref.watch(filterValuesProvider(vocabulary)).value;
}
