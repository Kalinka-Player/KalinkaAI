import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import '../providers/app_state_provider.dart';
import '../providers/catalog_sources_provider.dart';
import '../providers/collections_provider.dart';
import '../providers/connection_settings_provider.dart';
import '../providers/connection_state_provider.dart';
import '../providers/demo_mode.dart';
import '../providers/networked_boxes_provider.dart';
import '../providers/onboarding_provider.dart';
import '../providers/playback_failure_provider.dart';
import '../providers/renderer_host_provider.dart' show rendererIdentityProvider;
import '../providers/renderer_provider.dart';
import '../providers/renderer_settings_route_provider.dart';
import '../providers/restart_provider.dart';
import '../providers/search_session_provider.dart';
import '../providers/server_connect.dart';
import '../providers/settings_provider.dart';
import '../providers/shell_nav_provider.dart';
import '../providers/server_info_provider.dart';
import '../providers/supervisor_api.dart';
import '../providers/toast_provider.dart';
import '../providers/upgrade_provider.dart';
import '../theme/app_theme.dart';
import '../utils/renderer_fault_text.dart';
import '../widgets/box_actions.dart';
import '../widgets/coach_marks_overlay.dart';
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
import '../widgets/player_queue_view.dart';
import '../widgets/player_sheet.dart';
import '../widgets/renderer_switcher.dart' show rendererDisplayName;
import '../widgets/search/search_session_view.dart';
import '../widgets/server_sheet.dart';
import 'onboarding_screen.dart';
import 'customise_home_screen.dart';
import 'renderer_settings_screen.dart';
import 'settings_screen.dart';
import 'plugin_catalog_screen.dart';
import '../widgets/kalinka_toast_overlay.dart';
import '../widgets/sheet_anchor.dart';
import '../widgets/shell_navigation.dart';

class MusicPlayerScreen extends ConsumerStatefulWidget {
  const MusicPlayerScreen({super.key});

  @override
  ConsumerState<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends ConsumerState<MusicPlayerScreen>
    with SingleTickerProviderStateMixin {
  final _searchEntryKey = GlobalKey();
  final _connectionDotKey = GlobalKey();
  // The output switcher moves house across the breakpoint — mini-player on
  // phone, Now Playing header on tablet — and the two are different widgets.
  // One key serves both: the layouts are mutually exclusive, so only ever one
  // is mounted, and a resize re-parents the key to the other.
  final _outputSwitcherKey = GlobalKey();
  final _playerPaneKey = GlobalKey();
  final _browsingPaneKey = GlobalKey();
  final _homeKey = GlobalKey<SearchSessionViewState>();
  // Same trick for the settings panel, so a resize moves it rather than
  // remounting it (which would reload config and drop staged edits).
  final _settingsKey = GlobalKey();
  final _pluginsKey = GlobalKey<PluginCatalogScreenState>();
  bool _navigating = false;

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
  bool _pluginsOpen = false;

  /// Configuration slides in over what it was opened from, but is switched
  /// to in place from the rail or Customise Home, as destinations are.
  bool _pluginsSlide = true;
  // True once the settings panel fully covers the content behind it (after its
  // slide-in). Used to Offstage the occluded content so it isn't painted while
  // hidden — but only after the animation, so the slide-in still shows it.
  bool _settingsCovering = false;
  bool _discoveryOpen = false;

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

  // Live height of the escalation card, when shown, so toasts clear it.
  double _escalationHeight = 0;

  // The phone's player sheet while it is open.
  PlayerSheetRoute? _expandedPlayer;

  double? _publishedToastInset;

  void _onEscalationMeasured(double height) {
    if (!mounted || _escalationHeight == height) return;
    setState(() => _escalationHeight = height);
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
      // Without a server the player has no track to show.
      if (next == ConnectionStatus.none) _closeExpandedPlayer();
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

  void _openWizard({bool startAtSetup = false, bool offerNetwork = true}) {
    _wizardOpen = true;
    Navigator.of(context)
        .push(
          _onboardingRoute(
            startAtSetup: startAtSetup,
            offerNetwork: offerNetwork,
          ),
        )
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
      if (await leaveDemoAddressIfNotADemo(ref)) {
        showSafeToast(demoServerUnavailable, isError: true);
        return;
      }
      final values = ref.read(settingsProvider).values;
      if (values[OnboardingStatusNotifier.serverOobeFlagPath] == false) {
        final offerNetwork = await offerNetworkSetup(ref);
        if (!mounted || _wizardOpen) return;
        _openWizard(startAtSetup: true, offerNetwork: offerNetwork);
      }
    } finally {
      _setupCheckBusy = false;
    }
  }

  Route<void> _onboardingRoute({
    required bool startAtSetup,
    bool offerNetwork = true,
  }) {
    return PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) => Material(
        type: MaterialType.transparency,
        child: OnboardingScreen(
          startAtSetup: startAtSetup,
          offerNetwork: offerNetwork,
        ),
      ),
      transitionsBuilder: (_, anim, _, child) =>
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
        _openSettings();
      case ServerSheetAction.openDiscovery:
        setState(() => _discoveryOpen = true);
      case ServerSheetAction.openPlugins:
        _openPlugins();
      case ServerSheetAction.powerOff:
        await _powerOffServer();
      case null:
        break;
    }
  }

  Future<void> _powerOffServer() async {
    if (!mounted) return;
    await runBoxAction(
      context,
      ref,
      BoxAction.powerOff,
      dialogSide: KalinkaDialogSide.browsing,
    );
  }

  void _openSettings() => setState(() {
    _pluginsOpen = false;
    _settingsCovering = false;
    _settingsOpen = true;
  });

  void _openPlugins({bool slide = true}) {
    if (!ref.read(pluginCatalogEnabledProvider)) return;
    ref.read(rendererSettingsRouteProvider.notifier).close();
    setState(() {
      _settingsOpen = false;
      _settingsCovering = false;
      if (!_pluginsOpen) _pluginsSlide = slide;
      _pluginsOpen = true;
    });
  }

  /// Beside the rail it is left by another destination, so it offers no
  /// Back of its own; the system back still returns where it came from.
  Widget _buildPlugins({
    required bool handlesBack,
    required bool navigationVisible,
  }) => PluginCatalogScreen(
    key: _pluginsKey,
    handlesBack: handlesBack,
    showBack: !navigationVisible,
    slides: _pluginsSlide,
    onClose: () => setState(() {
      _pluginsOpen = false;
      _settingsCovering = false;
    }),
    onCoverageChanged: (covering) =>
        setState(() => _settingsCovering = covering),
  );

  void _requestHomeSearch() {
    ref.read(homeSearchRequestProvider.notifier).request();
  }

  Widget _navigation({required bool extended}) => ShellNavigation(
    extended: extended,
    configurationOpen:
        _pluginsOpen ||
        _settingsOpen ||
        ref.watch(rendererSettingsRouteProvider) != null,
    changeServerOpen: _discoveryOpen,
    // The picker can be left for another destination only where it could
    // be cancelled: with no server to go back to, it is the way on.
    enabled:
        !_navigating &&
        !(_discoveryOpen && !ref.watch(connectionSettingsProvider).isSet) &&
        !ref.watch(upgradeProvider).isUpgrading &&
        !ref.watch(
          restartProvider.select(
            (state) => state.isRestarting && !state.isDone,
          ),
        ),
    onNavigate: _navigate,
    onAction: _onShellAction,
  );

  void _onShellAction(ShellAction action) {
    _closeExpandedPlayer();
    switch (action) {
      case ShellAction.restart:
        runBoxAction(
          context,
          ref,
          BoxAction.reboot,
          dialogSide: KalinkaDialogSide.browsing,
        );
      case ShellAction.changeServer:
        setState(() => _discoveryOpen = true);
      case ShellAction.powerOff:
        _powerOffServer();
    }
  }

  Future<void> _navigate(
    ShellDestination destination,
    CatalogSource? source,
  ) async {
    if (_navigating) return;
    // The phone's player sits beside the rail; where the rail goes shows.
    _closeExpandedPlayer();
    // Any other destination leaves the server picker as its Cancel does,
    // back to what it covered, then goes on there.
    if (_discoveryOpen) setState(() => _discoveryOpen = false);
    if (destination == ShellDestination.configuration && _pluginsOpen) return;
    setState(() => _navigating = true);
    try {
      if (_pluginsOpen &&
          !await (_pluginsKey.currentState?.prepareToNavigate() ??
              Future.value(false))) {
        return;
      }
      if (!mounted) return;
      final home = _homeKey.currentState;
      if (home != null && !await home.prepareToNavigate()) return;
      if (!mounted) return;
      ref.read(homeCustomisationProvider.notifier).close();
      ref.read(rendererSettingsRouteProvider.notifier).close();
      setState(() {
        _serverSheetOpen = false;
        _settingsOpen = false;
        _settingsCovering = false;
        _pluginsOpen = false;
      });
      // Each destination comes back as it was left; the one shown stays
      // as it is.
      final browsing = ref.read(searchSessionProvider.notifier);
      switch (destination) {
        case ShellDestination.home:
          browsing.showHome();
        case ShellDestination.results:
          browsing.showResults();
        case ShellDestination.source:
          if (source != null) browsing.openSource(source);
        case ShellDestination.collections:
          final plan = ref.read(collectionsShelfProvider).value?.plan;
          if (plan != null) browsing.openCollections(plan);
        case ShellDestination.configuration:
          _openPlugins(slide: false);
      }
    } finally {
      if (mounted) setState(() => _navigating = false);
    }
  }

  void _showExpandedPlayer() {
    ref.read(playerViewProvider.notifier).show(PlayerView.nowPlaying);
    final navigator = Navigator.of(context);
    final sheet = PlayerSheetRoute(
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: (sheetContext) => _ExpandedPlayerSheet(
        // The empty queue's way out: back to Home with search up.
        onFindMusic: () {
          Navigator.of(sheetContext).pop();
          _requestHomeSearch();
        },
      ),
    );
    _expandedPlayer = sheet;
    navigator.push(sheet).whenComplete(() {
      if (identical(_expandedPlayer, sheet)) _expandedPlayer = null;
    });
  }

  void _closeExpandedPlayer() {
    final sheet = _expandedPlayer;
    if (!mounted || sheet == null || !sheet.isActive) return;
    // What the player opened goes with it, rather than left over Home.
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route == sheet || !sheet.isActive);
    if (sheet.isCurrent) navigator.pop();
  }

  /// Without [actions], only the notice: the tablet's player panel, beside
  /// Home's own disconnected state.
  Widget _buildDisconnectedState({bool actions = true}) {
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
            if (actions) ...[
              const SizedBox(height: 8),
              Text(
                kIsWeb ? 'Reload the page to reconnect to the server.' : 'Scan your network to find a Kalinka server and start listening.',
                style: KalinkaTextStyles.emptyQueueSubtitle,
                textAlign: TextAlign.center,
              ),
            ],
            // No mDNS in the browser — reloading re-seeds the connection.
            if (actions && !kIsWeb) ...[
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
              const SizedBox(height: 12),
              KalinkaButton(
                label: 'Try demo server',
                variant: KalinkaButtonVariant.neutral,
                size: KalinkaButtonSize.normal,
                onTap: _tryDemo,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _tryDemo() async {
    try {
      await connectToServer(
        ref,
        name: demoServerName,
        address: demoServer(),
        persist: true,
      );
    } catch (_) {
      showSafeToast(demoServerUnavailable, isError: true);
    }
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
    ref.listen(
      musicSourcesSettingsRequestProvider,
      (_, _) => _openPlugins(slide: !ref.read(homeCustomisationProvider)),
    );
    final customiseOpen = ref.watch(homeCustomisationProvider);
    final rendererSettings = ref.watch(rendererSettingsRouteProvider);
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
      if (MediaQuery.disableAnimationsOf(context)) {
        _miniPlayerHide.value = hidden ? 1 : 0;
        return;
      }
      if (hidden) {
        _miniPlayerHide.forward();
      } else {
        _miniPlayerHide.reverse();
      }
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final windowWidth = constraints.maxWidth;
        final railWidth = kalinkaNavigationRailWidth(
          windowWidth,
          textScaler: MediaQuery.textScalerOf(context),
        );
        final isTablet = kalinkaSplitLayout(
          windowWidth,
          textScaler: MediaQuery.textScalerOf(context),
        );
        return Scaffold(
          backgroundColor: KalinkaColors.background,
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (railWidth > 0)
                SizedBox(
                  key: const ValueKey('navigation-rail'),
                  width: railWidth,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      border: Border(
                        right: BorderSide(color: KalinkaColors.borderSubtle),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 1),
                      child: _navigation(
                        extended: railWidth > kKalinkaRailWidth,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Stack(
                  // Tight constraints keep the layout root a relayout boundary.
                  fit: StackFit.expand,
                  children: [
                    isTablet
                        ? _buildTabletLayout(
                            context,
                            windowWidth,
                            railWidth > 0,
                          )
                        : _buildPhoneLayout(context, railWidth > 0),
                    if (customiseOpen &&
                        !_settingsOpen &&
                        !_pluginsOpen &&
                        !_serverSheetOpen &&
                        rendererSettings == null)
                      Positioned(
                        left: 0,
                        right: isTablet
                            ? kalinkaPlayerPaneWidth(constraints.maxWidth) + 1
                            : 0,
                        top: 0,
                        bottom:
                            !isTablet &&
                                ref.watch(connectionStateProvider) !=
                                    ConnectionStatus.none
                            ? kalinkaMiniPlayerHeight(context) +
                                  MediaQuery.paddingOf(context).bottom
                            : 0,
                        child: SheetAnchor(
                          child: ClipRect(
                            child: CustomiseHomeScreen(
                              handlesBack: !_discoveryOpen,
                              onClose: () => ref
                                  .read(homeCustomisationProvider.notifier)
                                  .close(),
                            ),
                          ),
                        ),
                      ),
                    // Hosted above the phone/tablet switch so an in-progress scan
                    // (and its state) survives resizing across the breakpoint.
                    if (_discoveryOpen) _buildDiscoveryOverlay(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
        setState(() => _settingsCovering = _settingsOpen || _pluginsOpen);
      },
      onCoverageChanged: (covering) => setState(
        () => _settingsCovering = covering || _settingsOpen || _pluginsOpen,
      ),
    );
  }

  Widget _buildPhoneLayout(BuildContext context, bool navigationVisible) {
    final rendererSettings = ref.watch(rendererSettingsRouteProvider);
    final showCoachMarks = _showCoachMarks;
    // Without a server there is no track for the mini-player to show.
    final miniPlayer =
        ref.watch(connectionStateProvider) != ConnectionStatus.none;
    // Clear the mini-player, and the escalation card when it is up.
    _publishToastInset(
      (miniPlayer ? kalinkaMiniPlayerHeight(context) : 0) + _escalationHeight,
    );

    // Settings, configuration and renderer panels handle their own layered
    // Back navigation; Home its own at its top level.
    return PopScope(
      canPop: !_settingsOpen && !_pluginsOpen && rendererSettings == null,
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SheetAnchor(
                  key: _browsingPaneKey,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Visibility(
                        visible: !_settingsCovering,
                        maintainState: true,
                        maintainAnimation: true,
                        maintainSize: true,
                        child: _buildHome(
                          isTablet: false,
                          navigationVisible: navigationVisible,
                        ),
                      ),
                      _buildEscalation(isTablet: false),
                      // Configuration and every nested page share the space
                      // above the mini-player, including its safe-area inset.
                      if (_pluginsOpen)
                        MediaQuery.removePadding(
                          context: context,
                          removeBottom: true,
                          child: ClipRect(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _buildPlugins(
                                  handlesBack: rendererSettings == null,
                                  navigationVisible: navigationVisible,
                                ),
                                if (rendererSettings != null)
                                  _buildRendererSettings(rendererSettings),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (miniPlayer)
                Visibility(
                  visible: !_settingsCovering || _pluginsOpen,
                  maintainState: true,
                  maintainAnimation: true,
                  maintainSize: true,
                  child: SizeTransition(
                    sizeFactor: _pluginsOpen
                        ? const AlwaysStoppedAnimation(1.0)
                        : _miniPlayerReveal,
                    alignment: AlignmentDirectional.bottomStart,
                    child: SlideTransition(
                      position: _pluginsOpen
                          ? const AlwaysStoppedAnimation(Offset.zero)
                          : _miniPlayerSlide,
                      child: MiniPlayer(
                        onTap: _showExpandedPlayer,
                        outputSwitcherKey: _outputSwitcherKey,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Settings — full-screen overlay on phone (slides in from the right).
          // The same flag renders it in the browsing pane on tablet, so
          // resizing across the breakpoint just re-homes it.
          if (_settingsOpen)
            Positioned.fill(
              child: SettingsScreen(
                key: _settingsKey,
                handlesBack: rendererSettings == null,
                onClose: () => setState(() {
                  _settingsOpen = false;
                  _settingsCovering = false;
                }),
                onCoverageChanged: (covering) =>
                    setState(() => _settingsCovering = covering),
              ),
            ),
          // A renderer's own settings, hosted exactly like the server's.
          if (rendererSettings != null && !_pluginsOpen)
            Positioned.fill(child: _buildRendererSettings(rendererSettings)),
          // One-time first-run tour
          if (showCoachMarks) _buildCoachMarks(),
        ],
      ),
    );
  }

  /// Whether the one-time tour should run: first time Home's top level is
  /// up with a live connection (right after the setup wizard, or an
  /// upgrade). Never in the browser — there the local first-run flag is set
  /// from the seeded connection, so the tour would greet every new browser,
  /// whether or not the server has been set up.
  bool get _showCoachMarks {
    if (kIsWeb) return false;
    final onboarding = ref.watch(onboardingStatusProvider);
    return onboarding.oobeComplete &&
        !onboarding.coachMarksShown &&
        ref.watch(connectionStateProvider) == ConnectionStatus.connected &&
        !ref.watch(searchEntryModeProvider) &&
        ref.watch(
          searchSessionProvider.select(
            (s) =>
                s.activeView == FindMusicView.catalogs && s.catalogPage.isRoot,
          ),
        );
  }

  /// The tour itself. Shared by both layouts — only where the controls sit
  /// differs, which the keys take care of.
  Widget _buildCoachMarks() {
    // Mirror the switcher's own visibility rule: a stop with no target on
    // screen would describe a control the user hasn't got.
    final hasOutputSwitcher = ref.watch(
      rendererListProvider.select((s) => s.switcherVisible),
    );
    return Positioned.fill(
      child: CoachMarksOverlay(
        stops: [
          CoachMarkStop(
            targetKey: _searchEntryKey,
            title: 'Find music',
            body:
                'Search from here — by name, or by describing what you '
                'want, like “mellow late-night jazz”, when smart search is '
                'on. Nothing plays until you add it.',
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

  /// Home, or what stands in for it without a server.
  Widget _buildHome({required bool isTablet, required bool navigationVisible}) {
    final disconnected =
        ref.watch(connectionStateProvider) == ConnectionStatus.none;
    final rendererSettings = ref.watch(rendererSettingsRouteProvider);
    final VoidCallback onServerTap = isTablet
        ? () => setState(() => _serverSheetOpen = true)
        : _showServerSheet;
    // Whatever is open over Home takes the back press instead.
    final covered =
        ref.watch(homeCustomisationProvider) ||
        _settingsOpen ||
        _pluginsOpen ||
        _discoveryOpen ||
        rendererSettings != null ||
        (isTablet && _serverSheetOpen);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      layoutBuilder: _topmostScreenLayout,
      transitionBuilder: _screenSwitcherTransition,
      child: disconnected
          ? KeyedSubtree(
              key: const ValueKey('disconnected'),
              child: Column(
                children: [
                  KalinkaTopBar(
                    onServerChipTap: onServerTap,
                    connectionKey: _connectionDotKey,
                  ),
                  Expanded(child: _buildDisconnectedState()),
                ],
              ),
            )
          : SearchSessionView(
              key: _homeKey,
              onServerTap: onServerTap,
              entryKey: _searchEntryKey,
              connectionKey: _connectionDotKey,
              handlesBack: !covered,
              navigationVisible: navigationVisible,
            ),
    );
  }

  /// The escalation card, floating over the foot of Home.
  Widget _buildEscalation({required bool isTablet}) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: MeasureSize(
        onChange: (size) => _onEscalationMeasured(size.height),
        // No mini-player below it on tablet, so it keeps clear of the inset.
        child: SafeArea(
          top: false,
          bottom: isTablet,
          child: EscalationCard(
            onScanForServers: () => setState(() => _discoveryOpen = true),
          ),
        ),
      ),
    );
  }

  Widget _buildDiscoveryOverlay() {
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
          );
        },
      ),
    );
  }

  Widget _buildTabletLayout(
    BuildContext context,
    double windowWidth,
    bool navigationVisible,
  ) {
    final rendererSettings = ref.watch(rendererSettingsRouteProvider);
    final disconnected =
        ref.watch(connectionStateProvider) == ConnectionStatus.none;
    _publishToastInset(24 + _escalationHeight);
    return PopScope(
      canPop:
          !_settingsOpen &&
          !_pluginsOpen &&
          !_serverSheetOpen &&
          rendererSettings == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Settings, renderer settings and Home own their back via internal
        // PopScopes.
        if (_settingsOpen || _pluginsOpen || rendererSettings != null) return;
        if (_serverSheetOpen) {
          setState(() => _serverSheetOpen = false);
          return;
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final playerWidth = kalinkaPlayerPaneWidth(windowWidth);
          // The queue's mini-player spans the window, so browsing ends above
          // it while it shows.
          final barShowing =
              !disconnected &&
              ref.watch(playerViewProvider) == PlayerView.queue;
          final barHeight =
              kalinkaMiniPlayerHeight(context) +
              MediaQuery.paddingOf(context).bottom;
          // Only the foot animates: the sides follow the window at once, so
          // sheets anchored here track a resize.
          final browsing = TweenAnimationBuilder<double>(
            tween: Tween(end: barShowing ? barHeight : 0),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : kMiniPlayerHideDuration,
            curve: Curves.easeOutCubic,
            builder: (context, bottom, child) => Positioned(
              left: 0,
              top: 0,
              bottom: bottom,
              width: width - playerWidth - 1,
              child: child!,
            ),
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: barShowing,
              child: SizedBox.expand(
                child: RepaintBoundary(
                  child: SheetAnchor(
                    key: _browsingPaneKey,
                    child: Stack(
                      children: [
                        Visibility(
                          visible: !_settingsCovering,
                          maintainState: true,
                          maintainAnimation: true,
                          maintainSize: true,
                          child: _buildHome(
                            isTablet: true,
                            navigationVisible: navigationVisible,
                          ),
                        ),
                        _buildEscalation(isTablet: true),
                        if (_serverSheetOpen)
                          Positioned.fill(
                            child: ServerSheet(
                              onClose: () =>
                                  setState(() => _serverSheetOpen = false),
                              onOpenDiscovery: () =>
                                  setState(() => _discoveryOpen = true),
                              onOpenSettings: _openSettings,
                              onOpenPlugins: _openPlugins,
                              onPowerOff: _powerOffServer,
                            ),
                          ),
                        // Management overlays share browsing's bounds,
                        // including their sheets and slide motion.
                        if (_settingsOpen)
                          Positioned.fill(
                            child: SheetAnchor(
                              child: ClipRect(
                                child: SettingsScreen(
                                  key: _settingsKey,
                                  handlesBack: rendererSettings == null,
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
                          ),
                        if (_pluginsOpen)
                          Positioned.fill(
                            child: SheetAnchor(
                              child: ClipRect(
                                child: _buildPlugins(
                                  handlesBack: rendererSettings == null,
                                  navigationVisible: navigationVisible,
                                ),
                              ),
                            ),
                          ),
                        if (rendererSettings != null)
                          Positioned.fill(
                            child: SheetAnchor(
                              child: ClipRect(
                                child: _buildRendererSettings(rendererSettings),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          return Stack(
            children: [
              browsing,
              // The panes' divider stops short of the bar they share and
              // fades in below it.
              Positioned(
                left: width - playerWidth - 1,
                top: MediaQuery.paddingOf(context).top + kKalinkaTopBarHeight,
                bottom: 0,
                width: 1,
                // Stretched: an empty box in a column is otherwise as narrow
                // as it may be, which is nothing.
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 48,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x00000000),
                              KalinkaColors.borderSubtle,
                            ],
                          ),
                        ),
                        child: SizedBox.expand(),
                      ),
                    ),
                    Expanded(
                      child: ColoredBox(color: KalinkaColors.borderSubtle),
                    ),
                  ],
                ),
              ),
              // The player's pane, at the window's right: Now Playing with
              // local overlays.
              // SizedBox.expand() clamps infinity to the available size on both
              // axes, giving RepaintBoundary tight constraints so it becomes a
              // Flutter relayout boundary. Without this, layout invalidations
              // (e.g. progress slider ticks) propagate up to the Row and cause
              // the browsing pane to relayout and repaint unnecessarily.
              // SheetAnchor aligns modal bottom sheets launched from this
              // panel (e.g. the output switcher) with its bounds.
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: playerWidth,
                child: SizedBox.expand(
                  child: RepaintBoundary(
                    child: SheetAnchor(
                      key: _playerPaneKey,
                      child: Stack(
                        children: [
                          // Playback stays visible and interactive while the
                          // management panels cover browsing.
                          SafeArea(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              layoutBuilder: _topmostScreenLayout,
                              transitionBuilder: _screenSwitcherTransition,
                              child: disconnected
                                  ? KeyedSubtree(
                                      key: const ValueKey('disconnected'),
                                      child: _buildDisconnectedState(
                                        actions: false,
                                      ),
                                    )
                                  : NowPlayingContent(
                                      key: const ValueKey('player'),
                                      isTablet: true,
                                      outputSwitcherKey: _outputSwitcherKey,
                                      onFindMusic: _requestHomeSearch,
                                    ),
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
              if (!disconnected)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  // The bar is the player's, so its sheets open over its pane.
                  child: SheetAnchor(
                    target: _playerPaneKey,
                    child: QueueMiniPlayer(
                      outputSwitcherKey: _outputSwitcherKey,
                    ),
                  ),
                ),
              // The same one-time tour as the phone. It used to be phone-only, so
              // anyone who first ran the app on a wide window never saw it.
              if (_showCoachMarks) _buildCoachMarks(),
            ],
          );
        },
      ),
    );
  }
}

/// Full-screen Now Playing shown as a modal sheet in the phone layout. It
/// self-dismisses once the window grows past the tablet breakpoint, where the
/// player instead lives permanently in its own pane — otherwise the sheet
/// would float on top of the tablet layout.
class _ExpandedPlayerSheet extends StatefulWidget {
  final VoidCallback onFindMusic;

  const _ExpandedPlayerSheet({required this.onFindMusic});

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
        kalinkaSplitLayout(
          MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        )) {
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
        onFindMusic: widget.onFindMusic,
      ),
    );
  }
}
