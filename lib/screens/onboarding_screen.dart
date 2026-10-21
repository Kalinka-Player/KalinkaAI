import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/presentation_schema.dart' show ModuleSpec;
import '../providers/connection_settings_provider.dart';
import '../providers/kalinka_player_api_provider.dart';
import '../providers/network_setup_api.dart' show hotspotAddress;
import '../providers/networked_boxes_provider.dart';
import '../providers/onboarding_provider.dart';
import '../providers/renderer_provider.dart';
import '../providers/renderer_settings_provider.dart';
import '../providers/restart_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/soundcard_provider.dart';
import '../providers/supervisor_api.dart';
import '../providers/toast_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/discovery_screen.dart';
import '../widgets/kalinka_button.dart';
import '../widgets/onboarding/onboarding_fields.dart';
import '../widgets/onboarding/onboarding_step_scaffold.dart';
import '../widgets/onboarding/resume_connect.dart';
import '../widgets/onboarding/soundcard_restart_overlay.dart';
import '../widgets/onboarding/step_amp_control.dart';
import '../widgets/onboarding/step_music_sources.dart';
import '../widgets/onboarding/step_network.dart';
import '../widgets/onboarding/step_output.dart';
import '../widgets/onboarding/step_review.dart';
import '../widgets/onboarding/step_sound.dart';
import '../widgets/onboarding/step_source_setup.dart';
import '../widgets/onboarding/timezone_section.dart';
import '../widgets/restart_overlay.dart';
import '../widgets/soundcard_row.dart' show SoundcardHost, soundcardTrouble;

/// First-run setup wizard (OOBE).
///
/// Eight steps: find server → review network → choose sources → set up sources → choose
/// output → amplifier control → sound → review & start. Only the
/// source setup gates progress; the rest say in their own copy what
/// leaving them alone means, and leaving the sound step while a sound card
/// it found does not play asks first. The questions the config steps ask
/// come from the server's `setup` tags (see [Setup]); the connection is
/// held in memory only and config changes are merely staged until the final
/// step, so killing the app mid-setup restarts the wizard from the
/// beginning; backgrounding keeps the current step (widget state stays
/// alive). On success the server connection is persisted, the
/// `oobeComplete` flag is set, and the wizard pops back to the play queue.
///
/// Setting a sound card up may restart the Pi the output plays on, which
/// can be the server's own. The wizard follows it through the restart and
/// stays on the step. Before it starts, it saves what is staged to the
/// server and remembers the server and the step ([OobeResume]): a run the
/// app lost meanwhile reconnects to that server on the next launch, or on
/// the next page load on web, and carries on at the same step.
///
/// Whether the *server* is set up is its own config flag
/// (`base_config.server.oobe_complete`): the wizard reads it after
/// connecting and goes straight to the app if another client completed
/// setup — unless the box is on its own hotspot, which still needs Network.
/// With [startAtSetup] the discovery step is skipped instead — for an
/// already-connected server that reports the flag false: an existing install
/// pointing at a fresh server, or the web UI, whose connection always comes
/// from the origin serving the page.
///
/// Network is skipped for a box this app just put on a network
/// ([offerNetworkSetup]); [offerNetwork] carries that answer in for
/// [startAtSetup].
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({
    super.key,
    this.startAtSetup = false,
    this.offerNetwork = true,
  });

  final bool startAtSetup;
  final bool offerNetwork;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _stepCount = 8;
  static const _stepLabels = [
    'SERVER',
    'NETWORK',
    'SOURCES',
    'SETUP',
    'OUTPUT',
    'CONTROL',
    'SOUND',
    'FINISH',
  ];
  static const _soundStep = 6;
  bool _networkBusy = false;

  /// Set up already, and here only for Network: the box is on its hotspot.
  bool _alreadySetUp = false;

  /// Network is not offered, so Back steps over it.
  late bool _networkSkipped = widget.startAtSetup && !widget.offerNetwork;

  int get _backStep => _step - 1 == 1 && _networkSkipped ? 0 : _step - 1;

  /// Whether a sound test ran this session — flips the test step's Next
  /// from "Skip for now" to "Continue" and feeds the review row.
  bool _soundTested = false;

  /// A run the app lost while a Pi restarted, reconnecting to its server in
  /// place of discovery until it is back or the person looks elsewhere.
  late OobeResume? _resuming = widget.startAtSetup
      ? null
      : ref.read(oobeResumeProvider);

  late int _step = _initialStep();

  /// Discovery, or the setup steps for a connection made outside the wizard
  /// — at the step a lost run stood at when that connection is its server.
  int _initialStep() {
    if (!widget.startAtSetup) return 0;
    final resume = ref.read(oobeResumeProvider);
    if (resume == null ||
        resume.address != ref.read(connectionSettingsProvider).address) {
      return widget.offerNetwork ? 1 : 2;
    }
    ref.read(oobeResumeProvider.notifier).forget().ignore();
    return _resumedStep(resume);
  }

  static int _resumedStep(OobeResume resume) =>
      resume.step.clamp(1, _stepCount - 1);

  late final _soundcardHost = SoundcardHost(
    setUp: _setUpSoundcard,
    confirmNote: 'Setup carries on here.',
  );

  /// The sound card change the wizard follows, from the moment it starts
  /// until the Pi is back or the person moves on without it.
  ({SoundcardBox box, SoundcardOption card, bool notBack})? _soundcardRun;

  /// The lowest step the user can walk back to: discovery is not part of
  /// the flow when the connection came from outside the wizard.
  late final int _firstStep = widget.startAtSetup ? 1 : 0;
  bool _restartOverlayOpen = false;

  // Start runs one last check before the restart; without this a second tap
  // could start another in the gap.
  bool _starting = false;
  // Set when the restart succeeded and persistence was kicked off;
  // completes once the connection and the first-run flag are written.
  Future<void>? _commitFuture;

  // Captured at finish from the Volume & power step, applied after the
  // restart: the device module the wizard's output is handed to (null =
  // the renderer keeps control), and which output that is.
  bool _attachPrepared = false;
  String? _attachModuleId;
  String _attachModuleTitle = '';
  String? _attachRendererId;

  /// Moves on from discovery, or to the step a resumed run stood at.
  Future<void> _onConnected({int step = 1}) async {
    // The discovery step keeps its "connecting" state up while this runs.
    await ref.read(settingsProvider.notifier).loadConfig();
    final offerNetwork = await offerNetworkSetup(ref);
    if (!mounted) return;
    final values = ref.read(settingsProvider).values;
    _alreadySetUp =
        !OnboardingStatusNotifier.forceOobe &&
        values[OnboardingStatusNotifier.serverOobeFlagPath] == true;
    // Another client already set up the server: just persist the
    // connection. The coach-mark tour still runs once per install.
    if (_alreadySetUp &&
        ref.read(connectionSettingsProvider).host != hotspotAddress) {
      await _commitSetup();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await ref.read(oobeResumeProvider.notifier).forget();
    if (!mounted) return;
    setState(() {
      _resuming = null;
      _networkBusy = false;
      _networkSkipped = !_alreadySetUp && !offerNetwork;
      _step = _alreadySetUp
          ? 1
          : step == 1 && !offerNetwork
          ? 2
          : step;
    });
  }

  /// Gives up on reconnecting a lost run, for discovery.
  void _findAnotherServer() {
    ref.read(oobeResumeProvider.notifier).forget().ignore();
    setState(() => _resuming = null);
  }

  /// Leaves the sound step, asking first while a card the Pi found or is set
  /// up for does not play; putting it right stays on the step.
  Future<void> _leaveSoundStep() async {
    final soundcard = ref.read(outputSoundcardProvider).value;
    final trouble = soundcard == null
        ? null
        : soundcardTrouble(soundcard.report);
    if (soundcard == null || trouble == null) return _goTo(_step + 1);
    final leave = await askLeavingSilentSoundcard(
      context,
      trouble: trouble,
      fixLabel: fixSoundcardLabel(soundcard.report),
    );
    if (!mounted || leave == null) return;
    if (leave) return _goTo(_step + 1);
    await fixSoundcard(
      context,
      soundcard.box,
      soundcard.report,
      _soundcardHost,
    );
  }

  Future<void> _setUpSoundcard(SoundcardBox box, SoundcardOption card) async {
    if (_soundcardRun != null) return;
    setState(() => _soundcardRun = (box: box, card: card, notBack: false));
    await _saveProgress();
    final change = ref.read(soundcardChangeProvider(box).notifier);
    try {
      _settleSoundcard(await change.apply(card));
    } on BoxActionException catch (e) {
      ref.read(toastProvider.notifier).show(e.message, isError: true);
      await _endSoundcardRun();
    }
  }

  /// Saves what is staged and remembers the server and the step, so a run the
  /// app loses while the Pi restarts can carry on. Whatever the server
  /// refuses stays staged here, and is lost only with the app.
  Future<void> _saveProgress() async {
    final settings = ref.read(settingsProvider);
    if (settings.stagedChanges.isNotEmpty && !settings.hasBlockingIssues) {
      try {
        await ref.read(settingsProvider.notifier).applyChanges();
      } catch (e) {
        debugPrint('Onboarding: could not save progress: $e');
      }
    }
    final connection = ref.read(connectionSettingsProvider);
    await ref
        .read(oobeResumeProvider.notifier)
        .remember(
          OobeResume(
            name: connection.name,
            address: connection.address,
            step: _step,
          ),
        );
  }

  Future<void> _keepWaiting() async {
    final run = _soundcardRun;
    if (run == null) return;
    setState(
      () => _soundcardRun = (box: run.box, card: run.card, notBack: false),
    );
    _settleSoundcard(
      await ref
          .read(soundcardChangeProvider(run.box).notifier)
          .keepWaiting(run.card),
    );
  }

  void _settleSoundcard(SoundcardOutcome outcome) {
    final run = _soundcardRun;
    if (!mounted || run == null) return;
    if (outcome != SoundcardOutcome.notBack) {
      _endSoundcardRun();
      return;
    }
    setState(
      () => _soundcardRun = (box: run.box, card: run.card, notBack: true),
    );
  }

  /// Back on the step: what the restart may have changed is read again.
  Future<void> _endSoundcardRun() async {
    final run = _soundcardRun;
    if (!mounted || run == null) return;
    setState(() => _soundcardRun = null);
    final restarted = ref
        .read(soundcardChangeProvider(run.box).notifier)
        .restarted;
    await ref.read(oobeResumeProvider.notifier).forget();
    if (!mounted || !restarted) return;
    unawaited(ref.read(rendererListProvider.notifier).refresh());
    // A change that settled reloaded these itself; this one stopped waiting.
    if (run.box.rendererId case final id? when run.notBack) {
      unawaited(ref.read(rendererSettingsProvider(id).notifier).load());
    }
    // The server restarted with what was saved; nothing staged is lost.
    if (run.box.identity.serverId != null &&
        ref.read(settingsProvider).stagedChanges.isEmpty) {
      await ref.read(settingsProvider.notifier).loadConfig();
    }
  }

  Future<void> _finish() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await _startListening();
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// Moves the wizard to [step]. A refusal is only rechecked when something
  /// is staged, so one the server may since have dropped (a share that was
  /// briefly down) is asked about again on the way: otherwise it would hold
  /// the step, or Start, until the user edited something.
  void _goTo(int step) {
    setState(() => _step = step);
    if (ref.read(settingsProvider).hasBlockingIssues) {
      unawaited(ref.read(settingsProvider.notifier).validateStaged());
    }
  }

  Future<void> _startListening() async {
    final notifier = ref.read(settingsProvider.notifier);
    // Mark the server set up; rides along with the staged config.
    notifier.stageChange(OnboardingStatusNotifier.serverOobeFlagPath, true);

    final ready = await notifier.readyToApply();
    // Navigation is held while the check runs, but the review must still be
    // what the user is looking at when it answers.
    if (!mounted || !ready || _step != _stepCount - 1) return;

    // The Volume & power choice can't be applied yet — a freshly enabled
    // module only loads with the restart — so capture it here and hand the
    // output over once the server is back.
    final settings = ref.read(settingsProvider);
    ModuleSpec? chosen;
    for (final m in setupDeviceModules(settings.schema)) {
      if (settings.getEffective('devices.${m.id}.enabled') == true) {
        chosen = m;
        break;
      }
    }
    final renderers = ref.read(rendererListProvider);
    _attachPrepared = renderers.supported;
    _attachModuleId = chosen?.id;
    _attachModuleTitle = chosen?.title ?? '';
    _attachRendererId = renderers.active?.rendererId;

    setState(() => _restartOverlayOpen = true);
    ref.read(restartProvider.notifier).executeRestart();
  }

  /// Persist the connection and flip the first-run flag — only once the
  /// restart sequence has fully succeeded. If the app dies mid-restart the
  /// wizard simply runs again on next launch.
  Future<void> _commitSetup() async {
    final connection = ref.read(connectionSettingsProvider);
    final stagedName = ref
        .read(settingsProvider)
        .getEffective('base_config.server.service_name');
    final name = (stagedName is String && stagedName.trim().isNotEmpty)
        ? stagedName.trim()
        : connection.name;
    await ref
        .read(connectionSettingsProvider.notifier)
        .setDevice(
          name,
          connection.host,
          connection.port,
          scheme: connection.scheme,
        );
    await ref.read(onboardingStatusProvider.notifier).markOobeComplete();
    await ref.read(oobeResumeProvider.notifier).forget();

    // Detached on purpose: the wizard pops right after this commit, and the
    // attach outlives it (the module loads and the renderer redials on its
    // own schedule). Everything it needs is captured up front.
    if (_attachPrepared) {
      _attachPrepared = false;
      unawaited(
        _attachVolumeControl(
          api: ref.read(kalinkaProxyProvider),
          toasts: ref.read(toastProvider.notifier),
          moduleId: _attachModuleId,
          moduleTitle: _attachModuleTitle,
          rendererId: _attachRendererId,
        ),
      );
    }
  }

  Future<void> _onRestartDismissed() async {
    setState(() => _restartOverlayOpen = false);
    final commit = _commitFuture;
    if (commit == null) return; // Restart failed — stay in the wizard.
    // The overlay's auto-dismiss can fire while the prefs writes are still
    // in flight; don't leave the wizard until they've finished.
    await commit;
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final run = _soundcardRun;
    // Rebuilt on every step, which is when the change records a restart.
    final restarting =
        run != null &&
        ref.watch(soundcardChangeProvider(run.box)) != SoundcardStep.idle &&
        ref.read(soundcardChangeProvider(run.box).notifier).restarted;
    ref.listen(restartProvider, (prev, next) {
      if (next.isDone && prev?.isDone != true && _commitFuture == null) {
        // A failed write is benign — the wizard would simply run again on
        // the next launch — so log and still let the user into the app.
        _commitFuture = _commitSetup().catchError((Object e) {
          debugPrint('Onboarding: failed to persist setup: $e');
        });
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // System back walks one step backwards; never leaves the wizard.
        if (_backStep >= _firstStep &&
            !_restartOverlayOpen &&
            !_starting &&
            _soundcardRun == null) {
          _goTo(_backStep);
        }
      },
      child: Scaffold(
        backgroundColor: KalinkaColors.background,
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: KeyedSubtree(
                key: ValueKey('oobe_step_$_step'),
                child: _buildStep(),
              ),
            ),
            if (run != null && (run.notBack || restarting))
              Positioned.fill(
                child: SoundcardRestartOverlay(
                  box: run.box,
                  card: run.card,
                  notBack: run.notBack,
                  onKeepWaiting: _keepWaiting,
                  onContinue: _endSoundcardRun,
                ),
              ),
            if (_restartOverlayOpen)
              Positioned.fill(
                child: RestartOverlay(onDismiss: _onRestartDismissed),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    if (_step == 0 && _resuming != null) {
      final resume = _resuming!;
      return ResumeConnect(
        key: const ValueKey('oobe_resume'),
        resume: resume,
        onConnected: () => _onConnected(step: _resumedStep(resume)),
        onFindAnother: _findAnotherServer,
      );
    }
    if (_step == 0) {
      final connection = ref.read(connectionSettingsProvider);
      return DiscoveryScreen(
        allowCancel: false,
        persistConnection: false,
        currentServerHost: null,
        onConnected: _onConnected,
        // Re-entering after "Back": preselect nothing, fresh scan.
        key: ValueKey('oobe_discovery_${connection.host}'),
      );
    }

    final settings = ref.watch(settingsProvider);

    // No OPTIONAL/RECOMMENDED badges: a step that says plainly what happens
    // if you leave it alone tells the user more than a label does.
    final (title, subtitle, body, nextLabel) = switch (_step) {
      1 => (
        'Network',
        'Use Ethernet or Wi-Fi to connect your box. Keep the current connection or choose another network.',
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NetworkSetupPanel(
              endpoint: ref
                  .read(connectionSettingsProvider)
                  .baseUrl
                  .replace(port: supervisorPort),
              onReconnect: () async {
                if (kIsWeb) {
                  await launchUrl(
                    Uri(
                      scheme: 'http',
                      host: 'kalinka.local',
                      port: ref.read(connectionSettingsProvider).port,
                    ),
                    webOnlyWindowName: '_self',
                  );
                } else {
                  _goTo(0);
                }
              },
              onBusy: (busy) {
                if (mounted && busy != _networkBusy) {
                  setState(() => _networkBusy = busy);
                }
              },
            ),
            const OnboardingTimezoneSection(),
          ],
        ) as Widget,
        'Keep this connection',
      ),
      2 => (
        'Music sources',
        'Choose what feeds your library — at least one. More can be '
            'connected later in Settings.',
        const OnboardingMusicSourcesStep() as Widget,
        'Continue',
      ),
      3 => (
        'Set up your sources',
        'Each source asks only for what it needs; the rest lives in '
            'Settings.',
        const OnboardingSourceSetupStep() as Widget,
        'Continue',
      ),
      4 => (
        'Audio output',
        'Pick where the music comes out. You can switch outputs any time '
            'from the player.',
        const OnboardingOutputStep() as Widget,
        'Continue',
      ),
      5 => (
        'Amplifier or receiver',
        'Hand volume and power to an amplifier the music plays into, or '
            'leave them with the output. You can change this later.',
        const OnboardingAmpControlStep() as Widget,
        'Continue',
      ),
      _soundStep => (
        'Sound',
        'Make sure the output you picked plays: its sound card, the device '
            'it plays through, and a short test you can skip.',
        OnboardingSoundStep(
          onTested: () => setState(() => _soundTested = true),
          soundcardHost: _soundcardHost,
        ) as Widget,
        _soundTested ? 'Continue' : 'Skip for now',
      ),
      _ => (
        'Almost there',
        'Check your choices; starting restarts the server to apply them.',
        OnboardingReviewStep(
          soundTested: _soundTested,
          // Held while Start checks with the server.
          onEdit: _starting ? null : _goTo,
        ) as Widget,
        'Start listening',
      ),
    };

    // The source-setup gate is the wizard's one hard requirement. Start
    // waits for everything staged to be accepted; the review says what is
    // not.
    final nextEnabled = switch (_step) {
      1 => !_networkBusy,
      3 => setupStepReady(settings),
      _ when _step == _stepCount - 1 =>
        !settings.hasBlockingIssues && !_starting,
      _soundStep => _soundcardRun == null,
      _ => true,
    };

    return OnboardingStepScaffold(
      stepNumber: _step + 1,
      stepCount: _stepCount,
      stepLabels: _stepLabels,
      title: title,
      subtitle: subtitle,
      onBack: _backStep >= _firstStep && !_starting && _soundcardRun == null
          ? () => _goTo(_backStep)
          : null,
      onNext: switch (_step) {
        1 when _alreadySetUp => () async {
          await _commitSetup();
          if (mounted) Navigator.of(context).pop();
        },
        _ when _step == _stepCount - 1 => _finish,
        _soundStep => _leaveSoundStep,
        _ => () => _goTo(_step + 1),
      },
      nextLabel: nextLabel,
      nextEnabled: nextEnabled,
      children: [_wrapSettingsState(body)],
    );
  }

  /// Steps after connect need the server config; gate on its load state.
  Widget _wrapSettingsState(Widget child) {
    final settings = ref.watch(settingsProvider);
    if (settings.isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(KalinkaColors.accent),
          ),
        ),
      );
    }
    if (settings.schema == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: KalinkaColors.statusOffline,
                size: 32,
              ),
              const SizedBox(height: 12),
              Text(
                'Could not load server settings',
                style: KalinkaTextStyles.cardTitle,
              ),
              if (settings.error != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    settings.error!,
                    textAlign: TextAlign.center,
                    style: KalinkaTextStyles.trayRowSublabel,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              KalinkaButton(
                label: 'Retry',
                variant: KalinkaButtonVariant.accent,
                size: KalinkaButtonSize.compact,
                onTap: () => ref.read(settingsProvider.notifier).loadConfig(),
              ),
            ],
          ),
        ),
      );
    }
    return child;
  }
}

/// Hands the wizard's output to the chosen device module — or back to the
/// renderer itself — once the restarted server is up.
///
/// The mapping is per renderer and the server refuses it until the module is
/// loaded, which only happens with the restart; the renderer also has to
/// redial the restarted server. So this retries for a while and reports a
/// failed hand-over as a toast — the mapping can always be set later from
/// the output's settings. Clearing (null [moduleId]) fails silently: it only
/// matters on a wizard re-run, and the default is what it resets to.
Future<void> _attachVolumeControl({
  required KalinkaPlayerProxy api,
  required ToastNotifier toasts,
  required String? moduleId,
  required String moduleTitle,
  required String? rendererId,
}) async {
  const attempts = 10;
  for (var i = 0; i < attempts; i++) {
    if (i > 0) await Future<void>.delayed(const Duration(seconds: 3));
    try {
      var target = rendererId;
      if (target == null) {
        // No output was connected while the wizard ran — take the one
        // playback would use now.
        for (final r in await api.listRenderers()) {
          if (r.active) {
            target = r.rendererId;
            break;
          }
        }
        if (target == null) continue;
      }
      await api.setRendererVolumeControl(target, moduleId);
      return;
    } on RenderersUnsupportedException {
      return; // Older server — nothing to attach.
    } catch (_) {
      // Server still coming back or renderer not redialled yet — try again.
    }
  }
  if (moduleId != null) {
    toasts.show(
      'Couldn’t hand volume control to $moduleTitle — set it in the '
      'output’s settings.',
      isError: true,
    );
  }
}
