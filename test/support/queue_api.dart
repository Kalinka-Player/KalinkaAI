import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';

/// Records the queue requests a widget makes. [refusal], if set, is thrown
/// by [replace].
class QueueApi implements KalinkaPlayerProxy {
  QueueApi({this.refusal});

  final Exception? refusal;

  final List<(List<String>, int?)> added = [];
  final List<List<String>> replaced = [];
  final List<int?> played = [];
  int cleared = 0;

  @override
  Future<StatusMessage> add(List<String> items, {int? index}) async {
    added.add((items, index));
    return StatusMessage(count: items.length);
  }

  @override
  Future<StatusMessage> replace(List<String> items) async {
    replaced.add(items);
    if (refusal != null) throw refusal!;
    return StatusMessage(count: items.length);
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
