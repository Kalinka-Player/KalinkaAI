import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/utils/haptics.dart';

const _native = MethodChannel('org.kalinka.kalinka/media_session');
const _vibration = MethodChannel('vibration');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a haptic the device cannot play is dropped quietly', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final vibrations = <MethodCall>[];
    messenger.setMockMethodCallHandler(
      _native,
      (_) async => throw MissingPluginException(),
    );
    messenger.setMockMethodCallHandler(_vibration, (call) async {
      vibrations.add(call);
      throw MissingPluginException();
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_native, null);
      messenger.setMockMethodCallHandler(_vibration, null);
    });

    KalinkaHaptics.selectionClick();
    KalinkaHaptics.lightImpact();
    KalinkaHaptics.mediumImpact();
    KalinkaHaptics.heavyImpact();
    await KalinkaHaptics.doublePulse();
    await KalinkaHaptics.successCrescendo();
    await KalinkaHaptics.corkPop();
    await KalinkaHaptics.hapticDelete();
    await Future<void>.delayed(Duration.zero);

    expect(vibrations, hasLength(8));
  });
}
