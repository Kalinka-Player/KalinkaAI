import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the queue page is open over Home. Anything can open it — Home's
/// Up next card, the Now Playing sheet — and the main screen hosts it.
class QueuePageNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void open() => state = true;

  void close() => state = false;
}

final queuePageProvider = NotifierProvider<QueuePageNotifier, bool>(
  QueuePageNotifier.new,
);

/// Ticks when something outside Home asks it to lift its search overlay, such
/// as the empty queue's "Find music".
class HomeSearchRequest extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

final homeSearchRequestProvider = NotifierProvider<HomeSearchRequest, int>(
  HomeSearchRequest.new,
);
