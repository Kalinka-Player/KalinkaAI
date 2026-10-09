import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';

/// Records the queue requests a widget makes. [refusal], if set, is thrown
/// by [replace]. Ids in [unresolved] are left out of the queue a replace
/// makes, as the server leaves out tracks it can't resolve.
class QueueApi implements KalinkaPlayerProxy {
  QueueApi({this.refusal, this.unresolved = const {}});

  final Exception? refusal;
  final Set<String> unresolved;

  final List<(List<String>, int?)> added = [];
  final List<List<String>> replaced = [];
  final List<int?> played = [];
  int cleared = 0;
  int listed = 0;
  List<String> _queue = const [];

  @override
  Future<StatusMessage> add(List<String> items, {int? index}) async {
    added.add((items, index));
    return StatusMessage(count: items.length);
  }

  @override
  Future<StatusMessage> replace(List<String> items) async {
    replaced.add(items);
    if (refusal != null) throw refusal!;
    _queue = items.where((id) => !unresolved.contains(id)).toList();
    return StatusMessage(count: _queue.length);
  }

  @override
  Future<TrackList> listTracks({int offset = 0, int limit = 100}) async {
    listed++;
    final page = _queue.skip(offset).take(limit);
    return TrackList(offset, limit, _queue.length, [
      for (final id in page) Track(id: id, title: id, duration: 0),
    ]);
  }

  @override
  Future<void> clear() async => cleared++;

  @override
  Future<StatusMessage> play([int? index]) async {
    played.add(index);
    return StatusMessage();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
