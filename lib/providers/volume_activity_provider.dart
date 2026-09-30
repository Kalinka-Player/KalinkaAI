import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A native key press also needs feedback when already at the volume limit.
/// Commands remain native; this channel only asks the UI to show the indicator.
class VolumeActivityNotifier extends Notifier<int> {
  static const _channel = MethodChannel('org.kalinka.kalinka/media_session');

  @override
  int build() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'volumeActivity') state++;
      });
      ref.onDispose(() => _channel.setMethodCallHandler(null));
    }
    return 0;
  }
}

final volumeActivityProvider = NotifierProvider<VolumeActivityNotifier, int>(
  VolumeActivityNotifier.new,
);
