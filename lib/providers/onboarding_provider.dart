import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_settings_provider.dart';
import 'server_address.dart';

/// First-run state persisted across launches.
///
/// Whether the *server* has been set up lives in the server's own config
/// (`base_config.server.oobe_complete`) — the wizard reads it after
/// connecting and skips straight to the app when another client already
/// completed setup. The flags here are per-install only:
///
/// `oobeComplete` records that this install finished the first-run flow —
/// either the full wizard or the connect-only fast path against an
/// already-set-up server. An interrupted run — app killed mid-wizard —
/// leaves it false and, because the wizard connects ephemerally, no stored
/// server either, so the next launch restarts setup from the beginning.
/// Backgrounding does not reset anything: the wizard's widget state stays
/// alive while the app is alive.
///
/// `coachMarksShown` flips after the one-time UI tour on the play queue.
class OnboardingStatus {
  final bool oobeComplete;
  final bool coachMarksShown;

  const OnboardingStatus({
    required this.oobeComplete,
    required this.coachMarksShown,
  });

  OnboardingStatus copyWith({bool? oobeComplete, bool? coachMarksShown}) {
    return OnboardingStatus(
      oobeComplete: oobeComplete ?? this.oobeComplete,
      coachMarksShown: coachMarksShown ?? this.coachMarksShown,
    );
  }
}

class OnboardingStatusNotifier extends Notifier<OnboardingStatus> {
  static const String sharedPrefOobeComplete = 'Kalinka.oobeComplete';
  static const String sharedPrefCoachMarksShown = 'Kalinka.coachMarksShown';

  /// Dotted config path of the server-side "setup finished" flag.
  static const String serverOobeFlagPath = 'base_config.server.oobe_complete';

  /// Testing hook: `flutter run --dart-define=KALINKA_FORCE_OOBE=true`
  /// replays the setup wizard and the coach-mark tour on every launch,
  /// regardless of stored flags, a stored server, or the server-side flag
  /// (the fast path is disabled too). Finishing the wizard still behaves
  /// normally within the session; the next launch resets.
  static const bool forceOobe = bool.fromEnvironment('KALINKA_FORCE_OOBE');

  @override
  OnboardingStatus build() {
    if (forceOobe) {
      return const OnboardingStatus(
        oobeComplete: false,
        coachMarksShown: false,
      );
    }

    final prefs = ref.read(sharedPrefsProvider);
    var oobeComplete = prefs.getBool(sharedPrefOobeComplete) ?? false;

    // Upgrade path: installs that predate the wizard already have a server
    // stored. Treat them as set up — they only get the coach-mark tour.
    if (!oobeComplete && ref.read(connectionSettingsProvider).isSet) {
      oobeComplete = true;
      // Intentionally fire-and-forget: build() is synchronous and the
      // in-memory state already carries the answer. If the write never
      // lands, the next launch re-derives the same result from the stored
      // server, so a failure here is benign.
      prefs.setBool(sharedPrefOobeComplete, true).ignore();
    }

    return OnboardingStatus(
      oobeComplete: oobeComplete,
      coachMarksShown: prefs.getBool(sharedPrefCoachMarksShown) ?? false,
    );
  }

  Future<void> markOobeComplete() async {
    await ref.read(sharedPrefsProvider).setBool(sharedPrefOobeComplete, true);
    state = state.copyWith(oobeComplete: true);
  }

  Future<void> markCoachMarksShown() async {
    await ref
        .read(sharedPrefsProvider)
        .setBool(sharedPrefCoachMarksShown, true);
    state = state.copyWith(coachMarksShown: true);
  }
}

final onboardingStatusProvider =
    NotifierProvider<OnboardingStatusNotifier, OnboardingStatus>(
      OnboardingStatusNotifier.new,
    );

/// Where a setup run stood when it restarted a box to set its sound card up,
/// so a run the app lost meanwhile picks up there, on the same server. Holds
/// no settings: the wizard saves what it collected to the server first.
class OobeResume {
  final String name;
  final ServerAddress address;
  final int step;

  const OobeResume({
    required this.name,
    required this.address,
    required this.step,
  });

  Map<String, Object> toJson() => {
    'name': name,
    'scheme': address.scheme,
    'host': address.host,
    'port': address.port,
    'step': step,
  };

  /// Null for anything this build did not write.
  static OobeResume? fromJson(Object? json) {
    if (json case {
      'name': final String name,
      'scheme': final String scheme,
      'host': final String host,
      'port': final int port,
      'step': final int step,
    }) {
      return OobeResume(
        name: name,
        address: (scheme: scheme, host: host, port: port),
        step: step,
      );
    }
    return null;
  }
}

class OobeResumeNotifier extends Notifier<OobeResume?> {
  static const String sharedPref = 'Kalinka.oobeResume';

  @override
  OobeResume? build() {
    final raw = ref.read(sharedPrefsProvider).getString(sharedPref);
    if (raw == null) return null;
    try {
      return OobeResume.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  Future<void> remember(OobeResume resume) async {
    await ref
        .read(sharedPrefsProvider)
        .setString(sharedPref, jsonEncode(resume.toJson()));
    state = resume;
  }

  Future<void> forget() async {
    await ref.read(sharedPrefsProvider).remove(sharedPref);
    state = null;
  }
}

final oobeResumeProvider = NotifierProvider<OobeResumeNotifier, OobeResume?>(
  OobeResumeNotifier.new,
);
