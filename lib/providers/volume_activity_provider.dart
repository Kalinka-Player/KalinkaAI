import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A native volume-key press: the level it asked for, out of [max]. Each
/// press is a new instance, so listeners fire even for a repeated level.
class VolumeActivity {
  final int? level;
  final int? max;

  const VolumeActivity({this.level, this.max});
}

/// A native key press also needs feedback when already at the volume limit.
/// Commands remain native; this channel only asks the UI to show the level.
class VolumeActivityNotifier extends Notifier<VolumeActivity?> {
  static const _channel = MethodChannel('org.kalinka.kalinka/media_session');

  @override
  VolumeActivity? build() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'volumeActivity') return;
        final args = call.arguments;
        state = args is Map
            ? VolumeActivity(
                level: args['level'] as int?,
                max: args['max'] as int?,
              )
            // Not const: identical instances would not notify.
            : VolumeActivity();
      });
      ref.onDispose(() => _channel.setMethodCallHandler(null));
    }
    return null;
  }

  @override
  bool updateShouldNotify(VolumeActivity? previous, VolumeActivity? next) =>
      !identical(previous, next);
}

final volumeActivityProvider =
    NotifierProvider<VolumeActivityNotifier, VolumeActivity?>(
      VolumeActivityNotifier.new,
    );
