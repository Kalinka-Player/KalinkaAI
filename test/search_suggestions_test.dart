import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';

/// A real `/ai_search/suggestions` response captured from the server, so the
/// wire format is pinned end to end (fields, nulls, the experimental slot).
const _livePayload = '''
{"suggestions":[
  {"query":"piano music to fall asleep to","context":"night","experimental":false,"score":0.325},
  {"query":"atmospheric electronic music","context":"night","experimental":false,"score":0.585},
  {"query":"rock to fall asleep to","context":"night","experimental":false,"score":0.455},
  {"query":"country music to fall asleep to","context":"night","experimental":true,"score":null}
],"attested":true}
''';

/// Fake proxy serving the captured payload; everything else throws.
class _FakeApi implements KalinkaPlayerProxy {
  int suggestionCalls = 0;
  int? lastTzOffsetMin;

  @override
  Future<SearchSuggestionList> searchSuggestions({
    int count = 4,
    int? tzOffsetMin,
  }) async {
    suggestionCalls++;
    lastTzOffsetMin = tzOffsetMin;
    return SearchSuggestionList.fromJson(
      Map<String, dynamic>.from(jsonDecode(_livePayload) as Map),
    );
  }

  @override
  Future<BrowseItemsList> getFavorite(
    SearchType queryType, {
    int offset = 0,
    int limit = 10,
    String filter = '',
  }) async {
    return BrowseItemsList(0, limit, 0, []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'Kalinka.host': 'localhost',
      'Kalinka.port': 8080,
      'Kalinka.name': 'Test',
    });
    prefs = await SharedPreferences.getInstance();
  });

  ProviderContainer makeContainer(KalinkaPlayerProxy api) {
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        kalinkaProxyProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('SearchSuggestionList parses the live wire format', () {
    final list = SearchSuggestionList.fromJson(
      Map<String, dynamic>.from(jsonDecode(_livePayload) as Map),
    );
    expect(list.attested, isTrue);
    expect(list.suggestions, hasLength(4));
    expect(list.suggestions.first.query, 'piano music to fall asleep to');
    expect(list.suggestions.first.context, 'night');
    expect(list.suggestions.first.experimental, isFalse);
    expect(list.suggestions.last.experimental, isTrue);
  });

  test('zero state shows static fallback until the fetch lands', () {
    final container = makeContainer(_FakeApi());
    final state = container.read(searchSessionProvider);
    expect(state.suggestions, isNotEmpty);
    expect(state.suggestions.every((s) => s.query.isNotEmpty), isTrue);
  });

  test('open() fetches suggestions and replaces the fallback', () async {
    final api = _FakeApi();
    final container = makeContainer(api);
    final notifier = container.read(searchSessionProvider.notifier);

    notifier.refresh();
    await Future.delayed(const Duration(milliseconds: 50));

    expect(api.suggestionCalls, 1);
    final state = container.read(searchSessionProvider);
    expect(state.suggestions.map((s) => s.query), [
      'piano music to fall asleep to',
      'atmospheric electronic music',
      'rock to fall asleep to',
      'country music to fall asleep to',
    ]);
    expect(state.suggestions.last.experimental, isTrue);
  });

  test('a failing fetch keeps the fallback suggestions', () async {
    final failing = _ThrowingApi();
    final container = makeContainer(failing);
    final notifier = container.read(searchSessionProvider.notifier);

    notifier.refresh();
    await Future.delayed(const Duration(milliseconds: 50));

    final state = container.read(searchSessionProvider);
    expect(state.suggestions, isNotEmpty, reason: 'fallback must remain');
    expect(state.aiSuggestions, isEmpty);
  });
}

/// Proxy whose every member throws — including [searchSuggestions] via
/// noSuchMethod — mimicking an older server without the endpoint.
class _ThrowingApi implements KalinkaPlayerProxy {
  @override
  Future<BrowseItemsList> getFavorite(
    SearchType queryType, {
    int offset = 0,
    int limit = 10,
    String filter = '',
  }) async {
    return BrowseItemsList(0, limit, 0, []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
