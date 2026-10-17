import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data_model/data_model.dart' show Genre;
import 'kalinka_player_api_provider.dart';

/// Which vocabulary to fetch: one catalog's one field. Scoped to the catalog
/// rather than the source because a field is declared per shelf — Jamendo
/// offers genre on its track shelf alone.
typedef GenreVocabulary = ({String catalogId, String field});

/// The genre values one catalog offers. Only reached from a surface whose
/// capabilities say genre filtering is honoured, so a shelf without a
/// vocabulary is never asked.
final browseGenresProvider =
    FutureProvider.family<List<Genre>, GenreVocabulary>((
      ref,
      vocabulary,
    ) async {
      final api = ref.watch(kalinkaProxyProvider);
      final list = await api.getFilterValues(
        vocabulary.catalogId,
        vocabulary.field,
      );
      return [
        for (final value in list.items) Genre(id: value.id, name: value.name),
      ];
    });
