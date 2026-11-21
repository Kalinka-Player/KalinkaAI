import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [app] under a ProviderScope holding [prefs], or empty preferences.
Future<Widget> withPrefs(Widget app, [SharedPreferences? prefs]) async {
  if (prefs == null) {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  }
  return ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: app,
  );
}
