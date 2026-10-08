import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records, in order, every haptic the app asks the platform for.
///
/// Platform haptics are recorded by their [HapticFeedback] type name
/// (`selectionClick`, `lightImpact`, ...); the native swipe compositions as
/// `native:<method>`. Installed per test and removed on tear-down.
class HapticRecorder {
  HapticRecorder._();

  static const _native = MethodChannel('org.kalinka.kalinka/media_session');

  final List<String> calls = [];

  /// The native channel's answer for a composition; null makes it throw.
  bool? nativePlays = true;

  static HapticRecorder install() {
    final recorder = HapticRecorder._();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        final type = call.arguments as String? ?? 'vibrate';
        recorder.calls.add(type.replaceFirst('HapticFeedbackType.', ''));
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_native, (call) async {
      if (!call.method.startsWith('haptic')) return null;
      recorder.calls.add('native:${call.method}');
      return recorder.nativePlays ??
          (throw PlatformException(code: 'unavailable'));
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      messenger.setMockMethodCallHandler(_native, null);
    });
    return recorder;
  }
}
