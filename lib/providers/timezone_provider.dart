import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/local_timezone.dart';
import 'box_control_provider.dart';
import 'supervisor_api.dart';
import 'toast_provider.dart';

/// The connected server's box, as far as its time zone goes.
class BoxTimezone {
  /// The box's supervisor; null for a server that runs without one.
  final BoxControl? control;

  /// The zone the box is on; null when it cannot be set, or names none.
  final String? zone;

  const BoxTimezone({this.control, this.zone});

  bool get settable => control?.info.setsTimezone ?? false;
}

/// Read again each time it is shown, since the zone can also change on the
/// box itself, through DietPi's own tools.
final boxTimezoneProvider = FutureProvider.autoDispose<BoxTimezone>((
  ref,
) async {
  final control = await ref.watch(boxControlProvider.future);
  final api = ref.watch(supervisorApiProvider);
  if (control == null || api == null || !control.info.setsTimezone) {
    return BoxTimezone(control: control);
  }
  return BoxTimezone(control: control, zone: await api.timezone());
});

/// This device's own zone, which setup proposes for the box.
final localTimezoneProvider = FutureProvider<String?>((ref) => localTimezone());

/// How a zone reads: tzdata's underscores stand for spaces.
String timezoneLabel(String zone) => zone.replaceAll('_', ' ');

/// Sets the connected server's box to a zone. The state is the zone being
/// set, null while none is.
class TimezoneChange extends Notifier<String?> {
  @override
  String? build() => null;

  final _setFor = <String, String>{};

  /// Whether a box on [boxZone] is on [zone]: the same zone, or the one the
  /// box set when asked for [zone] under an old name such as `Asia/Calcutta`.
  bool isOn(String zone, String? boxZone) => (_setFor[zone] ?? zone) == boxZone;

  /// Returns whether the box took [zone]; the outcome is reported in a toast.
  Future<bool> apply(String zone, {bool inPanel = false}) async {
    final control = ref.read(boxControlProvider).value;
    final api = ref.read(supervisorApiProvider);
    if (state != null || control == null || api == null) return false;
    final toast = ref.read(toastProvider.notifier);
    state = zone;
    try {
      final set = await api.setTimezone(
        zone,
        BoxIdentity(serverId: control.serverId),
      );
      _setFor[zone] = set;
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
