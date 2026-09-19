import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/connection_state_provider.dart';
import '../providers/restart_provider.dart';
import '../providers/server_update_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/upgrade_provider.dart';
import '../data_model/presentation_schema.dart' show PageSpec;
import '../theme/app_theme.dart';
import '../widgets/connection_banner.dart';
import '../widgets/kalinka_dialog.dart' show showKalinkaDialog;
import '../widgets/kalinka_button.dart';
import '../widgets/pending_changes_banner.dart';
import '../widgets/restart_confirm_dialog.dart';
import '../widgets/restart_overlay.dart';
import '../widgets/upgrade_overlay.dart';
import '../widgets/expert_mode_toggle.dart';
import '../widgets/expert_settings_screen.dart';
import '../widgets/settings_controls/settings_binding.dart';
import '../widgets/slide_in_panel.dart';
import '../widgets/settings_renderer.dart';

/// Full-screen settings overlay with tabbed content (General / Modules / Devices).
///
/// Slides in from the right, loads server config on init.
class SettingsScreen extends ConsumerStatefulWidget {
  /// Optional close callback for overlay mode (phone full-screen / tablet left
  /// panel). When null, [Navigator.pop] is used instead.
  final VoidCallback? onClose;

  /// Fires `true` once the slide-in finishes (the panel now fully covers what's
  /// behind it) and `false` the moment the slide-out begins. Lets the host stop
  /// painting the occluded content without flashing during the animation.
  final ValueChanged<bool>? onCoverageChanged;

  const SettingsScreen({super.key, this.onClose, this.onCoverageChanged});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _tabIndex = 0;
  bool _restartOverlayOpen = false;
  // The check before the restart is a round trip, and the banner stays up
  // for it; without this a second restart could start in the gap.
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    // The release check resolves once and is cached for the app session, so
    // an answer fetched minutes before a release would stand until restart.
    ref.invalidate(serverUpdateProvider);
    // Load config
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(settingsProvider.notifier).loadConfig();
    });
  }

  Future<void> _onApply() async {
    if (_applying) return;
    setState(() => _applying = true);
    try {
      // Last word before a restart is spent: a debounced check may still be
      // pending, and the server may have changed its mind since the last one.
      await ref.read(settingsProvider.notifier).validateStaged();
      if (!mounted || ref.read(settingsProvider).hasBlockingIssues) return;
      setState(() => _restartOverlayOpen = true);
      ref.read(restartProvider.notifier).executeRestart();
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsState = ref.watch(settingsProvider);
    final expertMode = ref.watch(expertModeProvider);
    final connectionState = ref.watch(connectionStateProvider);
    final disconnected =
        connectionState == ConnectionStatus.reconnecting ||
        connectionState == ConnectionStatus.offline;

    // Reload the settings once the connection comes back, so stale or
    // half-loaded config from before the drop is replaced.
    ref.listen<ConnectionStatus>(connectionStateProvider, (prev, next) {
      if (next == ConnectionStatus.connected &&
          (prev == ConnectionStatus.reconnecting ||
              prev == ConnectionStatus.offline)) {
        ref.read(settingsProvider.notifier).loadConfig();
      }
    });

    return SlideInPanel(
      onClose: widget.onClose,
      onCoverageChanged: widget.onCoverageChanged,
      overlays: [
        // Restart overlay
        if (_restartOverlayOpen)
          RestartOverlay(
            onDismiss: () {
              setState(() => _restartOverlayOpen = false);
              // Reload config after restart
              ref.read(settingsProvider.notifier).loadConfig();
            },
          ),
        // Upgrade overlay — provider-driven (the server update banner starts
        // the flow); no dismiss until it succeeds or errors out.
        if (ref.watch(upgradeProvider).isUpgrading)
          UpgradeOverlay(
            onDismiss: () {
              ref.read(settingsProvider.notifier).loadConfig();
            },
          ),
      ],
      child: Container(
        color: KalinkaColors.background,
        child: SafeArea(
          child: Column(
            children: [
              // Header (carries the Expert mode toggle on the right)
              _buildHeader(),
              // Reconnecting / offline indicator — the same banner the
              // queue screen shows. Self-hides when connected.
              const ConnectionBanner(),
              if (disconnected)
                // Server unreachable: replace the apply bar, tab bar and
                // settings body with a placeholder. Settings reload
                // automatically once the connection returns (the
                // ref.listen above), swapping this back for the apply bar.
                _buildDisconnectedPlaceholder()
              else ...[
                // Pending changes banner — only actionable while
                // connected, since applying restarts the server.
                PendingChangesBanner(
                  pendingCount: settingsState.pendingCount,
                  consequence: 'restart required',
                  blocked: settingsState.hasBlockingIssues,
                  busy: _applying,
                  onDiscard: () =>
                      ref.read(settingsProvider.notifier).discardAll(),
                  onApply: _onApply,
                ),
                // Tab bar — only meaningful in simple mode; expert is
                // a single flat about:config-style screen.
                if (!expertMode) _buildTabBar(settingsState.schema?.pages),
                // Loading / error state
                if (settingsState.isLoading)
                  const Expanded(
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(
                          KalinkaColors.accent,
                        ),
                      ),
                    ),
                  )
                else if (settingsState.error != null &&
                    settingsState.schema == null)
                  Expanded(
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
                            'Could not load settings',
                            style: KalinkaTextStyles.cardTitle,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            settingsState.error!,
                            textAlign: TextAlign.center,
                            style: KalinkaTextStyles.trayRowSublabel,
                          ),
                          const SizedBox(height: 16),
                          KalinkaButton(
                            label: 'Retry',
                            variant: KalinkaButtonVariant.accent,
                            size: KalinkaButtonSize.compact,
                            onTap: () => ref
                                .read(settingsProvider.notifier)
                                .loadConfig(),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (settingsState.schema != null)
                  Expanded(
                    child: expertMode
                        ? const ExpertSettingsScreen()
                        : SettingsScope(
                            binding: ServerSettingsBinding(
                              settingsState,
                              ref.read(settingsProvider.notifier),
                            ),
                            child: IndexedStack(
                              index: _tabIndex.clamp(
                                0,
                                settingsState.schema!.pages.length - 1,
                              ),
                              children: [
                                for (final page in settingsState.schema!.pages)
                                  SchemaPageRenderer(
                                    key: ValueKey('page_${page.id}'),
                                    page: page,
                                  ),
                              ],
                            ),
                          ),
                  )
                else
                  const Expanded(child: SizedBox.shrink()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: kKalinkaTopBarDecoration,
      // Shared top-bar height so this lines up with the queue and search bars.
      child: SizedBox(
        height: kKalinkaTopBarHeight,
        child: Padding(
          padding: const EdgeInsets.only(left: 6, right: 20),
          child: Row(
            children: [
              // Back — same plain, borderless style as the Find Music close.
              // Builder: the panel scope is *below* this State's context.
              Semantics(
                label: 'Back',
                button: true,
                child: Builder(
                  builder: (context) => GestureDetector(
                    onTap: () => SlideInPanel.closeOf(context),
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox(
                      width: 42,
                      height: 42,
                      child: Icon(
                        Icons.arrow_back,
                        size: 22,
                        color: KalinkaColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Kalinka logo
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SvgPicture.asset(
                    'assets/images/kalinka_logo.svg',
                    height: kKalinkaWordmarkHeight,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              // Restart the server. Available even with no pending changes
              // (the pending-changes banner only restarts when applying), so
              // there's always a way to reboot — e.g. to fire an armed
              // "Rebuild library on next restart" toggle.
              Material(
                color: KalinkaColors.surfaceInput,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                  side: const BorderSide(color: KalinkaColors.borderDefault),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _onRestart,
                  overlayColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.pressed)) {
                      return Colors.white.withValues(alpha: 0.08);
                    }
                    return null;
                  }),
                  child: const SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(
                      Icons.restart_alt,
                      size: 16,
                      color: KalinkaColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // View-mode switch: simple ↔ expert (about:config-style).
              // Sits where the connection status pill used to live —
              // connection state surfaces clearly enough through the
              // loading/error UI below, so the prime header slot is better
              // spent on a control the user actually interacts with.
              const ExpertModeToggle(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onRestart() async {
    final confirmed = await showKalinkaDialog<bool>(
      context: context,
      builder: (_) => const RestartConfirmDialog(),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _restartOverlayOpen = true);
    ref.read(restartProvider.notifier).executeRestart();
  }

  /// Shown in place of the settings body while the server is unreachable.
  /// The [ConnectionBanner] above already explains the reconnecting/offline
  /// state, so this stays a calm, minimal placeholder.
  Widget _buildDisconnectedPlaceholder() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              color: KalinkaColors.textSecondary,
              size: 32,
            ),
            const SizedBox(height: 12),
            Text('Server not connected', style: KalinkaTextStyles.cardTitle),
            const SizedBox(height: 8),
            Text(
              'Settings will reload once the connection is restored.',
              textAlign: TextAlign.center,
              style: KalinkaTextStyles.trayRowSublabel,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(List<PageSpec>? pages) {
    final tabs = (pages == null || pages.isEmpty)
        ? const ['General', 'Modules', 'Devices']
        : pages.map((p) => p.title).toList();
    return Container(
      decoration: const BoxDecoration(
        color: KalinkaColors.surfaceBase,
        border: Border(bottom: BorderSide(color: KalinkaColors.borderSubtle)),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final isActive = i == _tabIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tabIndex = i),
              behavior: HitTestBehavior.opaque,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      tabs[i].toUpperCase(),
                      textAlign: TextAlign.center,
                      style: KalinkaTextStyles.sectionHeaderMuted.copyWith(
                        letterSpacing: 1.0,
                        color: isActive
                            ? KalinkaColors.textPrimary
                            : KalinkaColors.textSecondary,
                      ),
                    ),
                  ),
                  // Neutral underline, matching the Find Music tabs.
                  Container(
                    height: 2,
                    color: isActive
                        ? KalinkaColors.textPrimary
                        : Colors.transparent,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
