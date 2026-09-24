import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data_model/data_model.dart';
import '../providers/app_state_provider.dart';
import '../providers/connection_settings_provider.dart';
import '../providers/connection_state_provider.dart';
import '../providers/kalinka_player_api_provider.dart';
import '../providers/onboarding_provider.dart';
import '../providers/playback_failure_provider.dart';
import '../providers/renderer_host_provider.dart' show rendererIdentityProvider;
import '../providers/renderer_provider.dart';
import '../providers/renderer_settings_route_provider.dart';
import '../providers/search_session_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/toast_provider.dart';
import '../theme/app_theme.dart';
import '../utils/renderer_fault_text.dart';
import '../widgets/clear_all_confirm_dialog.dart';
import '../widgets/coach_marks_overlay.dart';
import '../widgets/connection_banner.dart';
import '../widgets/discovery_screen.dart';
import '../widgets/escalation_card.dart';
import '../widgets/kalinka_button.dart';
import '../widgets/kalinka_top_bar.dart';
import '../widgets/kalinka_bottom_sheet.dart';
import '../widgets/kalinka_dialog.dart';
import '../widgets/measure_size.dart';
import '../widgets/mini_player.dart';
import '../widgets/now_playing_content.dart';
import '../widgets/playback_error_dialog.dart';
import '../widgets/queue_management_tray.dart';
import '../widgets/queue_zone.dart';
import '../widgets/renderer_switcher.dart' show rendererDisplayName;
import '../widgets/search/add_to_collection_sheet.dart';
import '../widgets/search/search_dock.dart';
import '../widgets/search/search_session_view.dart';
import '../widgets/server_sheet.dart';
import 'onboarding_screen.dart';
import 'renderer_settings_screen.dart';
import 'settings_screen.dart';
import '../widgets/kalinka_toast_overlay.dart';
import '../widgets/sheet_anchor.dart';
import '../providers/media_notification_provider.dart';

class MusicPlayerScreen extends ConsumerStatefulWidget {
  const MusicPlayerScreen({super.key});

  @override
  ConsumerState<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends ConsumerState<MusicPlayerScreen>
    with SingleTickerProviderStateMixin {
  final _searchDockKey = GlobalKey();
  final _connectionDotKey = GlobalKey();
  // The output switcher moves house across the breakpoint — mini-player on
  // phone, Now Playing header on tablet — and the two are different widgets.
  // One key serves both: the layouts are mutually exclusive, so only ever one
  // is mounted, and a resize re-parents the key to the other.
  final _outputSwitcherKey = GlobalKey();
  // Same trick for the settings panel, so a resize moves it rather than
  // remounting it (which would reload config and drop staged edits).
  final _settingsKey = GlobalKey();

  // Drives the mini-player sliding down out of view while the search entry
  // overlay is up (0 = shown, 1 = hidden). The keyboard is held back until
  // this completes, so the bar clears before the IME rises.
  late final AnimationController _miniPlayerHide;
  late final Animation<double> _miniPlayerReveal;
  late final Animation<Offset> _miniPlayerSlide;

  // In-screen overlays. Settings and discovery render in both layouts;
  // the server sheet overlay is tablet-only (phone uses a modal sheet).
  bool _serverSheetOpen = false;
  bool _settingsOpen = false;
  // True once the settings panel fully covers the content behind it (after its
  // slide-in). Used to Offstage the occluded content so it isn't painted while
  // hidden — but only after the animation, so the slide-in still shows it.
  bool _settingsCovering = false;
  bool _discoveryOpen = false;
  // Tablet-only: the queue management tray, hosted here (not inside QueueZone)
  // so its overlay covers the search dock like the connection sheet.
  bool _queueTrayOpen = false;

  // The wizard connects, which fires `connected` — these keep the
  // connected-listener from stacking a second wizard or racing itself.
  bool _wizardOpen = false;
  bool _setupCheckBusy = false;

  // Tracks the on-screen playback-error dialog so a re-fired error (the state
  // store re-syncs on resume/reconnect) doesn't stack another copy. The token
  // identifies the latest requested dialog, so a show still waiting on its
  // post-frame callback can be cancelled.
  ModalRoute<void>? _playbackErrorRoute;
  String? _playbackErrorMessage;
  int _playbackErrorShowToken = 0;

  // Live height of the floating dock (plus escalation card, when shown) so the
  // queue behind it can reserve matching bottom space and clear the bar.
  double _dockClusterHeight = 0;

  double? _publishedToastInset;

  void _onDockClusterMeasured(double height) {
    if (!mounted || _dockClusterHeight == height) return;
    setState(() => _dockClusterHeight = height);
  }

  /// Tell the toast host how much of the bottom edge this screen is using.
  /// Deferred to the post-frame because it is called from build, and a
  /// provider cannot be written while the tree reading it is being built.
  void _publishToastInset(double inset) {
    if (_publishedToastInset == inset) return;
    _publishedToastInset = inset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(toastBottomInsetProvider.notifier).set(inset);
    });
  }

  @override
  void initState() {
    super.initState();

    _miniPlayerHide = AnimationController(
      vsync: this,
      duration: kMiniPlayerHideDuration,
    );
    final curved = CurvedAnimation(
      parent: _miniPlayerHide,
      curve: Curves.easeInOutCubic,
    );
    _miniPlayerReveal = Tween<double>(begin: 1, end: 0).animate(curved);
    _miniPlayerSlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, 1),
    ).animate(curved);

    // Every connection — at launch, via discovery, or seeded from the
    // serving origin on web — checks whether the server itself still needs
    // setup (see _checkServerNeedsSetup). On web it is the only route in.
    ref.listenManual(connectionStateProvider, (_, next) {
      if (next == ConnectionStatus.connected) {
        _checkServerNeedsSetup();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Web has its connection already (main.dart) and no mDNS, so neither
      // branch below applies.
      if (kIsWeb) return;
      // First launch: run the setup wizard. The provider marks pre-wizard
      // installs (server already stored) as complete on its own, so they
      // fall through to the regular flow below.
      if (!ref.read(onboardingStatusProvider).oobeComplete) {
        _openWizard();
        return;
      }
      // Set up but no stored server (e.g. after Disconnect): plain discovery.
      if (!ref.read(connectionSettingsProvider).isSet) {
        setState(() => _discoveryOpen = true);
      }
    });
  }

  @override
  void dispose() {
    _miniPlayerHide.dispose();
    super.dispose();
  }

  void _openWizard({bool startAtSetup = false}) {
    _wizardOpen = true;
    Navigator.of(context)
        .push(_onboardingRoute(startAtSetup: startAtSetup))
        .whenComplete(() => _wizardOpen = false);
  }

  /// A connected server reporting `oobe_complete: false` was never set up —
  /// a fresh server behind a stored connection, one just picked in
  /// discovery, or a setup run that was killed midway. Run the wizard's
  /// setup steps; the connection already exists, so discovery is skipped.
  Future<void> _checkServerNeedsSetup() async {
    if (_wizardOpen || _setupCheckBusy) return;
    _setupCheckBusy = true;
    try {
      await ref.read(settingsProvider.notifier).loadConfig();
      if (!mounted || _wizardOpen) return;
      final values = ref.read(settingsProvider).values;
      if (values[OnboardingStatusNotifier.serverOobeFlagPath] == false) {
        _openWizard(startAtSetup: true);
      }
    } finally {
      _setupCheckBusy = false;
    }
  }

  Route<void> _onboardingRoute({required bool startAtSetup}) {
    return PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => Material(
        type: MaterialType.transparency,
        child: OnboardingScreen(startAtSetup: startAtSetup),
      ),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    );
  }

  // ---------------------------------------------------------------------------
  // Route & modal helpers
  // ---------------------------------------------------------------------------

  Future<void> _showServerSheet() async {
    final result = await showKalinkaBottomSheet<ServerSheetAction>(
      context: context,
      contentBuilder: (_) => const ServerSheetContent(),
    );
    if (!mounted) return;
    switch (result) {
      case ServerSheetAction.openSettings:
        setState(() => _settingsOpen = true);
      case ServerSheetAction.openDiscovery:
        setState(() => _discoveryOpen = true);
      case null:
        break;
    }
  }

  Future<void> _showQueueManagementTray() async {
    final result = await showKalinkaBottomSheet<TrayAction>(
      context: context,
      contentBuilder: (_) => const QueueManagementTrayContent(),
    );
    if (!mounted) return;
    switch (result) {
      case TrayAction.saveToCollection:
        await _saveQueueToCollection();
      case TrayAction.clearPlayed:
        await _clearPlayed();
      case TrayAction.clearAll:
        await Future.delayed(const Duration(milliseconds: 160));
        if (!mounted) return;
        await showKalinkaDialog<bool>(
          context: context,
          builder: (_) => ClearAllConfirmDialog(onConfirmClearAll: _clearAll),
        );
      case null:
        break;
    }
  }

  /// Tablet: act on the panel-level queue management tray's selection.
  Future<void> _onTabletTrayAction(TrayAction action) async {
    switch (action) {
      case TrayAction.saveToCollection:
        await _saveQueueToCollection();
      case TrayAction.clearPlayed:
        await _clearPlayed();
      case TrayAction.clearAll:
        await Future.delayed(const Duration(milliseconds: 160));
        if (!mounted) return;
        await showKalinkaDialog<bool>(
          context: context,
          builder: (_) => ClearAllConfirmDialog(onConfirmClearAll: _clearAll),
        );
    }
  }

  void _showExpandedPlayer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: KalinkaColors.background,
      barrierColor: Colors.transparent,
      useSafeArea: true,
      // Override the M3 default 640px cap so the sheet fills the window and
      // resizes smoothly instead of centering with the layout poking out.
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (_) => const _ExpandedPlayerSheet(),
    );
  }

  // ---------------------------------------------------------------------------
  // Queue actions
  // ---------------------------------------------------------------------------

  /// Opens the destination sheet on the queue as it stands; what becomes of
  /// what the chosen collection already holds is decided in there.
  Future<void> _saveQueueToCollection() async {
    final tracks = ref.read(playQueueProvider);
    if (tracks.isEmpty) {
      ref.read(toastProvider.notifier).show('Nothing in the queue yet');
      return;
    }
    await showAddToCollectionSheet(
      context,
      CollectionAddition.queue([for (final track in tracks) track.id]),
    );
  }

  Future<void> _clearPlayed() async {
    final queueState = ref.read(playQueueStateStoreProvider);
    final currentIndex = queueState.playbackState.index ?? 0;
    final api = ref.read(kalinkaProxyProvider);
    final toast = ref.read(toastProvider.notifier);
    for (int i = currentIndex - 1; i >= 0; i--) {
      try {
        await api.remove(i);
      } catch (e) {
        toast.show('Failed to clear played: $e', isError: true);
        return;
      }
    }
    toast.show('Played tracks cleared');
  }

  Future<void> _clearAll() async {
    final api = ref.read(kalinkaProxyProvider);
    final toast = ref.read(toastProvider.notifier);
    await api.clear();
    toast.show('Queue cleared');
  }

  Widget _buildDisconnectedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: KalinkaColors.textMuted,
            ),
            const SizedBox(height: 20),
            Text(
              'No server connected',
              style: KalinkaTextStyles.emptyQueueTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              kIsWeb
                  ? 'Reload the page to reconnect to the server.'
                  : 'Scan your network to find a Kalinka server and start listening.',
              style: KalinkaTextStyles.emptyQueueSubtitle,
              textAlign: TextAlign.center,
            ),
            // No mDNS in the browser — reloading re-seeds the connection.
            if (!kIsWeb) ...[
              const SizedBox(height: 32),
              KalinkaButton(
                label: 'Scan for servers',
                variant: KalinkaButtonVariant.accent,
                size: KalinkaButtonSize.normal,
                leading: const Icon(
                  Icons.wifi_tethering_rounded,
                  size: 16,
                  color: KalinkaColors.accentTint,
                ),
                onTap: () => setState(() => _discoveryOpen = true),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// An output failure arrives in the server's words, which name renderers by
  /// id. Puts back the names the picker shows — see [nameRenderersIn].
  String? _namedFault(String? message) {
    if (message == null || message.isEmpty) return message;
    final ownId = ref.read(rendererIdentityProvider).value?.rendererId;
    return nameRenderersIn(message, {
      for (final r in ref.read(rendererListProvider).renderers)
        r.rendererId: rendererDisplayName(r, isSelf: r.rendererId == ownId),
    });
  }

  void _showPlaybackErrorDialog(String? message) {
    if (!mounted) return;
    // Claimed here, not in the callback: an error that clears in the same
    // frame has to cancel this pending show rather than race it.
    final token = ++_playbackErrorShowToken;
    // Defer to the next frame: the error listener fires mid-connect while the
    // provider graph is still settling, and inserting the dialog in that frame
    // rebuilds the overlay against dirty providers (setState during build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != _playbackErrorShowToken) return;
      // Only one playback-error dialog at a time. An identical error while one
      // is up (state re-sync on resume) keeps the existing dialog; a different
      // error replaces it.
      if (_playbackErrorRoute != null) {
        if (message == _playbackErrorMessage) return;
        _removePlaybackErrorRoute();
      }
      _playbackErrorMessage = message;
      ModalRoute<void>? shown;
      showKalinkaDialog<void>(
        context: context,
        builder: (dialogContext) {
          shown = ModalRoute.of<void>(dialogContext);
          _playbackErrorRoute = shown;
          return PlaybackErrorDialog(message: message);
        },
      ).whenComplete(() {
        // Closed (dismissed, skipped, or replaced). A replacement already owns
        // the fields — don't clear its state.
        if (identical(_playbackErrorRoute, shown)) {
          _playbackErrorRoute = null;
          _playbackErrorMessage = null;
        }
      });
    });
  }

  /// Takes the playback-error dialog down when the error it describes stops
  /// being true — playback recovered, or another client skipped past the
  /// failing track and the server pushed the new state.
  void _dismissPlaybackErrorDialog() {
    // Also cancels a show that is still waiting for its post-frame callback.
    _playbackErrorShowToken++;

    final route = _playbackErrorRoute;
    if (route == null) return;

    // Same-frame reasoning as the show path: removing a route rebuilds the
    // overlay, which can't happen while the provider graph is settling.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!identical(_playbackErrorRoute, route)) return;
      _removePlaybackErrorRoute();
    });
  }

  void _removePlaybackErrorRoute() {
    final route = _playbackErrorRoute;
    if (route == null) return;
    _playbackErrorRoute = null;
    _playbackErrorMessage = null;
    if (route.isActive) Navigator.of(context).removeRoute(route);
  }

  @override
  Widget build(BuildContext context) {
    ref.read(mediaNotificationProvider);
    // Arm the failure recorder from app start. Left to the queue rows that
    // read it, it would miss an error that lands while the queue isn't built
    // — during a search session, say.
    ref.read(playbackFailuresProvider);

    // Surface playback errors as a dialog in both phone and tablet layouts.
    // Lives here (not in MiniPlayer) because the mini player is only mounted
    // in the phone layout.
    ref.listen(
      playQueueStateStoreProvider.select(
        (s) => (
          state: s.playbackState.state,
          message: s.playbackState.message,
          // Identity of the track the error is about. Watched so a skip from
          // another client — which arrives as a plain state update — retires
          // or replaces the dialog instead of leaving it stranded.
          trackId: s.playbackState.currentTrack?.id,
        ),
      ),
      (prev, next) {
        if (next.state != PlayerStateType.error) {
          _dismissPlaybackErrorDialog();
          return;
        }
        if (prev?.state != PlayerStateType.error ||
            prev?.message != next.message ||
            prev?.trackId != next.trackId) {
          _showPlaybackErrorDialog(_namedFault(next.message));
        }
      },
    );

    // Slide the mini-player down when the search entry overlay opens, back up
    // when it closes. Driven here (not in the phone layout) so the animation
    // survives a tablet⇄phone rebuild.
    ref.listen(searchEntryModeProvider, (_, hidden) {
      if (hidden) {
        _miniPlayerHide.forward();
      } else {
        _miniPlayerHide.reverse();
      }
    });

    return Scaffold(
      backgroundColor: KalinkaColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isTablet = constraints.maxWidth >= kKalinkaTabletBreakpoint;
          return Stack(
            // Tight constraints keep the layout root a relayout boundary.
            fit: StackFit.expand,
            children: [
              isTablet
                  ? _buildTabletLayout(context)
                  : _buildPhoneLayout(context),
              // Hosted above the phone/tablet switch so an in-progress scan
              // (and its state) survives resizing across the breakpoint.
              if (_discoveryOpen) _buildDiscoveryOverlay(isTablet),
            ],
          );
        },
      ),
    );
  }

  // Swaps the queue and the search session without cross-fading them. Only the
  // incoming child is laid out ([_topmostScreenLayout] drops the outgoing one
  // immediately) so the now-playing queue never bleeds through the
  // half-transparent search view as it fades in ("flashing underneath"). The
  // incoming screen fades and lifts a touch over the near-black canvas.
  static Widget _topmostScreenLayout(
    Widget? currentChild,
    List<Widget> previousChildren,
  ) => currentChild ?? const SizedBox.shrink();

  static Widget _screenSwitcherTransition(
    Widget child,
    Animation<double> animation,
  ) => FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.02),
        end: Offset.zero,
      ).animate(animation),
      child: child,
    ),
  );

  /// The renderer settings panel, wired to close through the same route
  /// provider that opened it. Coverage rides on [_settingsCovering] — only one
  /// settings panel is ever up, and both hide the same content behind them.
  Widget _buildRendererSettings(RendererSettingsRoute route) {
    return RendererSettingsScreen(
      // Keyed by the open route: a resize re-homes the panel like
      // [_settingsKey], while switching targets rebuilds rather than reusing
      // the previous renderer's page and its staged edits.
      key: GlobalObjectKey(route),
      rendererId: route.rendererId,
      rendererName: route.rendererName,
      onClose: () {
        ref.read(rendererSettingsRouteProvider.notifier).close();
        setState(() => _settingsCovering = false);
      },
      onCoverageChanged: (covering) =>
          setState(() => _settingsCovering = covering),
    );
  }

  Widget _buildPhoneLayout(BuildContext context) {
    final searchOpen = ref.watch(searchSessionProvider.select((s) => s.isOpen));
    final rendererSettings = ref.watch(rendererSettingsRouteProvider);
    final connectionState = ref.watch(connectionStateProvider);
    final showCoachMarks = _showCoachMarks;
    // Clear the mini-player, and off search the dock cluster too — on search
    // the bar lives in the header, so nothing else docks at the bottom.
    _publishToastInset(
      searchOpen ? kMiniPlayerHeight : kMiniPlayerHeight + _dockClusterHeight,
    );

    return PopScope(
      canPop: !searchOpen && !_settingsOpen && rendererSettings == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Settings is a full-screen overlay here; it owns its own back via an
        // internal PopScope (animated close), so leave it alone — as does the
        // renderer settings panel. Search owns its own layered back too
        // (SearchSessionView's PopScope).
        if (_settingsOpen || rendererSettings != null) return;
      },
      child: Stack(
        children: [
          // Main content: TopBar + Banner + Content + Escalation + Dock +
          // MiniPlayer. When search is open the dock/escalation give way and the
          // content becomes the chat session (whose composer is the sole bottom
          // element); the miniplayer slides itself away.
          Visibility(
            visible: !_settingsCovering,
            maintainState: true,
            maintainAnimation: true,
            maintainSize: true,
            child: Column(
              children: [
                // The search session carries its own header (roundel + search
                // bar + connection dot), so the shared top bar leaves with it.
                if (!searchOpen) ...[
                  RepaintBoundary(
                    child: KalinkaTopBar(
                      onServerChipTap: _showServerSheet,
                      connectionKey: _connectionDotKey,
                    ),
                  ),
                  // Find Music signals connection state via its header dot; the
                  // banner would only push its content down.
                  const ConnectionBanner(),
                ],
                Expanded(
                  // The dock (and escalation card) float over the content, which
                  // scrolls behind them and fades into the page; the mini-player
                  // below stays solid.
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          layoutBuilder: _topmostScreenLayout,
                          transitionBuilder: _screenSwitcherTransition,
                          child: searchOpen
                              ? SearchSessionView(
                                  key: const ValueKey('search'),
                                  onServerTap: _showServerSheet,
                                )
                              : KeyedSubtree(
                                  key: const ValueKey('queue'),
                                  child:
                                      connectionState == ConnectionStatus.none
                                      ? _buildDisconnectedState()
                                      : RepaintBoundary(
                                          child: QueueZone(
                                            bottomPadding: _dockClusterHeight,
                                            onOpenManagementTray:
                                                _showQueueManagementTray,
                                          ),
                                        ),
                                ),
                        ),
                      ),
                      if (!searchOpen)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: MeasureSize(
                            onChange: (size) =>
                                _onDockClusterMeasured(size.height),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                EscalationCard(
                                  onScanForServers: () =>
                                      setState(() => _discoveryOpen = true),
                                ),
                                SearchDock(
                                  buttonKey: _searchDockKey,
                                  onTap: () => ref
                                      .read(searchSessionProvider.notifier)
                                      .open(),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Always mounted so it can slide (not just vanish); the
                // SizeTransition collapses its slot as it goes so the content
                // above settles down with it.
                SizeTransition(
                  sizeFactor: _miniPlayerReveal,
                  alignment: AlignmentDirectional.bottomStart,
                  child: SlideTransition(
                    position: _miniPlayerSlide,
                    child: MiniPlayer(
                      onTap: _showExpandedPlayer,
                      outputSwitcherKey: _outputSwitcherKey,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Settings — full-screen overlay on phone (slides in from the right).
          // The same flag renders it in the left panel on tablet, so resizing
          // across the breakpoint just re-homes it.
          if (_settingsOpen)
            Positioned.fill(
              child: SettingsScreen(
                key: _settingsKey,
                onClose: () => setState(() {
                  _settingsOpen = false;
                  _settingsCovering = false;
                }),
                onCoverageChanged: (covering) =>
                    setState(() => _settingsCovering = covering),
              ),
            ),
          // A renderer's own settings, hosted exactly like the server's.
          if (rendererSettings != null)
            Positioned.fill(child: _buildRendererSettings(rendererSettings)),
          // One-time first-run tour
          if (showCoachMarks) _buildCoachMarks(),
        ],
      ),
    );
  }

  /// Whether the one-time tour should run: first time the queue is visible
  /// with a live connection (right after the setup wizard, or an upgrade).
  /// Never in the browser — there the local first-run flag is set from the
  /// seeded connection, so the tour would greet every new browser, whether
  /// or not the server has been set up.
  bool get _showCoachMarks {
    if (kIsWeb) return false;
    final onboarding = ref.watch(onboardingStatusProvider);
    return onboarding.oobeComplete &&
        !onboarding.coachMarksShown &&
        ref.watch(connectionStateProvider) == ConnectionStatus.connected &&
        !ref.watch(searchSessionProvider.select((s) => s.isOpen));
  }

  /// The tour itself. Shared by both layouts — only where the controls sit
  /// differs, which the keys take care of.
  Widget _buildCoachMarks() {
    // Mirror the switcher's own visibility rule: a stop with no target on
    // screen shows as a centred card describing a control the user hasn't got.
    final hasOutputSwitcher = ref.watch(
      rendererListProvider.select((s) => s.switcherVisible),
    );
    return Positioned.fill(
      child: CoachMarksOverlay(
        stops: [
          CoachMarkStop(
            targetKey: _searchDockKey,
            title: 'Find music',
            body:
                'Search and browse from here — by name, or by describing '
                'what you want, like “mellow late-night jazz”, when smart '
                'search is on. Results stage below; nothing plays until '
                'you add it.',
          ),
          if (hasOutputSwitcher)
            CoachMarkStop(
              targetKey: _outputSwitcherKey,
              title: 'Choose where it plays',
              body:
                  'The cast icon switches between the outputs on your '
                  'network — a speaker, another machine, this device. Its '
                  'gear opens that output’s own settings.',
            ),
          CoachMarkStop(
            targetKey: _connectionDotKey,
            title: 'Your server lives here',
            body:
                'The green dot shows you’re connected. Tap it '
                'for server status, settings, and switching '
                'servers.',
          ),
        ],
        onDismiss: () =>
            ref.read(onboardingStatusProvider.notifier).markCoachMarksShown(),
      ),
    );
  }

  Widget _buildDiscoveryOverlay(bool isTablet) {
    return Positioned.fill(
      // Consumer keeps settings churn from the overlay's own connect flow
      // from rebuilding the occluded layout below.
      child: Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(connectionSettingsProvider);
          return DiscoveryScreen(
            allowCancel: settings.isSet,
            currentServerHost: settings.isSet ? settings.host : null,
            onClose: () => setState(() => _discoveryOpen = false),
            isTablet: isTablet,
          );
        },
      ),
    );
  }

  Widget _buildTabletLayout(BuildContext context) {
    final searchOpen = ref.watch(searchSessionProvider.select((s) => s.isOpen));
    final rendererSettings = ref.watch(rendererSettingsRouteProvider);
    // Lifted clear of the search dock, or of the composer when search is open.
    _publishToastInset(searchOpen ? 116 : 80);
    return PopScope(
      canPop:
          !searchOpen &&
          !_settingsOpen &&
          !_serverSheetOpen &&
          rendererSettings == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Settings, renderer settings and search own their back via internal
        // PopScopes.
        if (_settingsOpen || rendererSettings != null) return;
        if (_serverSheetOpen) {
          setState(() => _serverSheetOpen = false);
          return;
        }
      },
      child: Stack(
        children: [
          Row(
            children: [
              // Left panel: Now Playing with local overlays.
              // SizedBox.expand() clamps infinity to the available size on both
              // axes, giving RepaintBoundary tight constraints so it becomes a
              // Flutter relayout boundary. Without this, layout invalidations
              // (e.g. progress slider ticks) propagate up to the Row and cause
              // the right panel to relayout and repaint unnecessarily.
              // SheetAnchor aligns modal bottom sheets launched from this
              // panel (e.g. settings pickers) with its bounds.
              Expanded(
                child: SizedBox.expand(
                  child: RepaintBoundary(
                    child: SheetAnchor(
                      child: Stack(
                        children: [
                          // Not painted once settings fully covers the left panel.
                          Visibility(
                            visible: !_settingsCovering,
                            maintainState: true,
                            maintainAnimation: true,
                            maintainSize: true,
                            child: SafeArea(
                              child: NowPlayingContent(
                                isTablet: true,
                                outputSwitcherKey: _outputSwitcherKey,
                              ),
                            ),
                          ),
                          // Settings screen overlay (left panel only). ClipRect
                          // keeps the slide-in within the left half — the Stack
                          // doesn't clip a paint-time transform, so without it the
                          // animation bleeds over the queue on the right.
                          if (_settingsOpen)
                            Positioned.fill(
                              child: ClipRect(
                                child: SettingsScreen(
                                  key: _settingsKey,
                                  onClose: () => setState(() {
                                    _settingsOpen = false;
                                    _settingsCovering = false;
                                  }),
                                  onCoverageChanged: (covering) => setState(
                                    () => _settingsCovering = covering,
                                  ),
                                ),
                              ),
                            ),
                          // A renderer's settings share the left panel and the
                          // same clip, so the slide reads identically.
                          if (rendererSettings != null)
                            Positioned.fill(
                              child: ClipRect(
                                child: _buildRendererSettings(rendererSettings),
                              ),
                            ),
                          // Sheets opened here are anchored to this panel,
                          // so their answers belong over it too.
                          Positioned(
                            left: 20,
                            right: 20,
                            bottom: 24,
                            child: const IgnorePointer(
                              child: KalinkaToastOverlay(
                                isTablet: true,
                                scope: ToastScope.panel,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Divider
              Container(width: 1, color: KalinkaColors.borderSubtle),
              // Right panel — mirrors the phone main screen: a top bar carrying
              // the connection dot, the queue (or the chat search session), and
              // the bottom search dock. There is no miniplayer here — Now Playing
              // lives in the left panel — so the dock/composer is the sole bottom
              // element. SizedBox.expand() gives RepaintBoundary tight constraints
              // so its layout invalidations don't cross into the left panel.
              Expanded(
                child: SizedBox.expand(
                  child: RepaintBoundary(
                    child: Column(
                      children: [
                        // The whole right panel — including the search dock — sits
                        // in a Stack so the connection sheet overlays it as a
                        // bottom card, covering the dock rather than stopping above
                        // it.
                        Expanded(
                          child: Stack(
                            children: [
                              Column(
                                children: [
                                  // Search brings its own header row; the
                                  // shared top bar yields to it.
                                  if (!searchOpen) ...[
                                    KalinkaTopBar(
                                      onServerChipTap: () => setState(
                                        () => _serverSheetOpen = true,
                                      ),
                                      connectionKey: _connectionDotKey,
                                    ),
                                    // Search signals connection via its header
                                    // dot — no banner while it is up.
                                    const ConnectionBanner(),
                                  ],
                                  Expanded(
                                    // Dock floats over the queue, which fades
                                    // behind it (same as phone, minus the
                                    // mini-player).
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: AnimatedSwitcher(
                                            duration: const Duration(
                                              milliseconds: 200,
                                            ),
                                            layoutBuilder: _topmostScreenLayout,
                                            transitionBuilder:
                                                _screenSwitcherTransition,
                                            child: searchOpen
                                                ? SearchSessionView(
                                                    key: const ValueKey(
                                                      'search',
                                                    ),
                                                    onServerTap: () => setState(
                                                      () => _serverSheetOpen =
                                                          true,
                                                    ),
                                                  )
                                                : KeyedSubtree(
                                                    key: const ValueKey(
                                                      'queue',
                                                    ),
                                                    child: RepaintBoundary(
                                                      child: QueueZone(
                                                        bottomPadding:
                                                            _dockClusterHeight,
                                                        isTablet: true,
                                                        onOpenManagementTray:
                                                            () => setState(
                                                              () =>
                                                                  _queueTrayOpen =
                                                                      true,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                          ),
                                        ),
                                        if (!searchOpen)
                                          Positioned(
                                            left: 0,
                                            right: 0,
                                            bottom: 0,
                                            child: MeasureSize(
                                              onChange: (size) =>
                                                  _onDockClusterMeasured(
                                                    size.height,
                                                  ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  EscalationCard(
                                                    onScanForServers: () =>
                                                        setState(
                                                          () => _discoveryOpen =
                                                              true,
                                                        ),
                                                  ),
                                                  SearchDock(
                                                    buttonKey: _searchDockKey,
                                                    bottomSafeArea: true,
                                                    onTap: () => ref
                                                        .read(
                                                          searchSessionProvider
                                                              .notifier,
                                                        )
                                                        .open(),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (_serverSheetOpen)
                                Positioned.fill(
                                  child: ServerSheet(
                                    onClose: () => setState(
                                      () => _serverSheetOpen = false,
                                    ),
                                    onOpenDiscovery: () =>
                                        setState(() => _discoveryOpen = true),
                                    onOpenSettings: () =>
                                        setState(() => _settingsOpen = true),
                                  ),
                                ),
                              // Queue management tray — same panel-level overlay
                              // so it covers the search dock too.
                              if (_queueTrayOpen)
                                Positioned.fill(
                                  child: TabletQueueManagementTray(
                                    onClose: () =>
                                        setState(() => _queueTrayOpen = false),
                                    onAction: _onTabletTrayAction,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          // The same one-time tour as the phone. It used to be phone-only, so
          // anyone who first ran the app on a wide window never saw it.
          if (_showCoachMarks) _buildCoachMarks(),
        ],
      ),
    );
  }
}

/// Full-screen Now Playing shown as a modal sheet in the phone layout. It
/// self-dismisses once the window grows past the tablet breakpoint, where the
/// player instead lives permanently in the left panel — otherwise the sheet
/// would float on top of the tablet layout.
class _ExpandedPlayerSheet extends StatefulWidget {
  const _ExpandedPlayerSheet();

  @override
  State<_ExpandedPlayerSheet> createState() => _ExpandedPlayerSheetState();
}

class _ExpandedPlayerSheetState extends State<_ExpandedPlayerSheet> {
  bool _dismissing = false;

  @override
  Widget build(BuildContext context) {
    // Dismiss exactly once when crossing into the tablet layout. Scheduling a
    // pop on every resize frame re-ran after the route was gone and threw
    // "No element" (Navigator.pop on empty history) mid-resize.
    if (!_dismissing &&
        MediaQuery.of(context).size.width >= kKalinkaTabletBreakpoint) {
      _dismissing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
          Navigator.of(context).pop();
        }
      });
    }
    return SizedBox.expand(
      child: NowPlayingContent(
        showOverlayHeader: true,
        onClose: () => Navigator.of(context).pop(),
      ),
    );
  }
}
