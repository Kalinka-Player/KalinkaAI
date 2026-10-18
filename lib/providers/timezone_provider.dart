import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/local_timezone.dart';
import 'box_control_provider.dart';
import 'connection_settings_provider.dart' show sharedPrefsProvider;
import 'supervisor_api.dart';
import 'toast_provider.dart';

/// The connected server's box, as far as its time zone goes.
class BoxTimezone {
  /// The box's supervisor, or why there is none.
  final BoxProbe probe;

  /// The zone the box is on; null when it cannot be set, or names none.
  final String? zone;

  const BoxTimezone(this.probe, {this.zone});

  BoxControl? get control => probe.control;

  bool get settable => control?.info.setsTimezone ?? false;
}

/// Read again each time it is shown, since the zone can also change on the
/// box itself, through DietPi's own tools.
final boxTimezoneProvider = FutureProvider.autoDispose<BoxTimezone>((
  ref,
) async {
  final probe = await ref.watch(boxProbeProvider.future);
  final api = ref.watch(supervisorApiProvider);
  final box = BoxTimezone(probe);
  if (api == null || !box.settable) return box;
  return BoxTimezone(probe, zone: await api.timezone());
});

/// This device's own zone, which setup proposes for the box. Read again each
/// time it is shown, since a phone that travels changes its zone.
final localTimezoneProvider = FutureProvider.autoDispose<String?>(
  (ref) => localTimezone(),
);

/// How a zone reads: tzdata's underscores stand for spaces.
String timezoneLabel(String zone) => zone.replaceAll('_', ' ');

/// Sets the connected server's box to a zone. The state is the zone being
/// set, null while none is.
class TimezoneChange extends Notifier<String?> {
  @override
  String? build() => null;

  /// Old zone names, `from=to`, each with the zone a box set when asked for
  /// it; kept across launches, since the box names only the zone it is on.
  static const _linksKey = 'Kalinka.timezoneLinks';

  Map<String, String> _links(SharedPreferences prefs) => {
    for (final link in prefs.getStringList(_linksKey) ?? const <String>[])
      if (link.split('=') case [final from, final to]) from: to,
  };

  /// Whether a box on [boxZone] is on [zone]: the same zone, or the one a box
  /// set when asked for [zone] under an old name such as `Asia/Calcutta`.
  bool isOn(String zone, String? boxZone) =>
      (_links(ref.read(sharedPrefsProvider))[zone] ?? zone) == boxZone;

  /// Returns whether the box took [zone]; the outcome is reported in a toast.
  Future<bool> apply(String zone, {bool inPanel = false}) async {
    final control = ref.read(boxProbeProvider).value?.control;
    final api = ref.read(supervisorApiProvider);
    if (state != null || control == null || api == null) return false;
    final toast = ref.read(toastProvider.notifier);
    final prefs = ref.read(sharedPrefsProvider);
    state = zone;
    try {
      final set = await api.setTimezone(
        zone,
        BoxIdentity(serverId: control.serverId),
      );
      if (set != zone) {
        final links = {..._links(prefs), zone: set};
        await prefs.setStringList(_linksKey, [
          for (final MapEntry(:key, :value) in links.entries) '$key=$value',
        ]);
      }
      if (!ref.mounted) return true;
      ref.invalidate(boxTimezoneProvider);
      toast.show(
        'The box shows the time in ${timezoneLabel(set)}.',
        inPanel: inPanel,
      );
      return true;
    } on BoxActionException catch (e) {
      toast.show(e.message, isError: true, inPanel: inPanel);
      return false;
    } finally {
      if (ref.mounted) state = null;
    }
  }
}

final timezoneChangeProvider = NotifierProvider<TimezoneChange, String?>(
  TimezoneChange.new,
);
