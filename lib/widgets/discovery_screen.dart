import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/connection_settings_provider.dart';
import '../providers/demo_mode.dart';
import '../providers/discovery_provider.dart';
import '../providers/server_address.dart';
import '../providers/server_connect.dart';
import '../theme/app_theme.dart';
import 'kalinka_button.dart';
import 'sonar_animation.dart';

/// Full-screen discovery overlay for finding and connecting to Kalinka servers.
///
/// Used on first launch (no cancel) and when switching servers (with cancel).
class DiscoveryScreen extends ConsumerStatefulWidget {
  /// Close callback for overlay mode. Null only when embedded in the setup
  /// wizard, where [onConnected] takes over and there is no cancel path.
  final VoidCallback? onClose;
  final bool allowCancel;
  final String? currentServerHost;
  final bool isTablet;

  /// When false, the selected server is held in memory only (no
  /// SharedPreferences write). Used by the setup wizard so an interrupted
  /// run leaves no stored server behind.
  final bool persistConnection;

  /// When set, called after a successful connect instead of closing the
  /// screen — for embedded use (setup wizard step).
  final VoidCallback? onConnected;

  const DiscoveryScreen({
    super.key,
    this.onClose,
    this.allowCancel = true,
    this.currentServerHost,
    this.isTablet = false,
    this.persistConnection = true,
    this.onConnected,
  });

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;

  int? _selectedIndex;
  bool _showManualEntry = false;
  bool _isConnecting = false;
  String? _connectError;
  VoidCallback? _retry;

  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '8000');

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();

    // Start scanning
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(discoveryProvider.notifier).startScan();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _connectToServer(
    String name,
    String host,
    int port, {
    String scheme = 'http',
    String failure = 'Could not connect. Check the address and try again.',
  }) async {
    setState(() {
      _isConnecting = true;
      _connectError = null;
      _retry = () =>
          _connectToServer(name, host, port, scheme: scheme, failure: failure);
    });

    try {
      await connectToServer(
        ref,
        name: name,
        address: (scheme: scheme, host: host, port: port),
        persist: widget.persistConnection,
      );

      // Success — hand off to the embedding wizard, or close discovery
      if (mounted) {
        if (widget.onConnected != null) {
          widget.onConnected!();
        } else {
          await _animateClose();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _connectError = failure);
      }
    }
  }

  /// The address field as it has always read — a bare host means port 8000 —
  /// plus a scheme for a server behind TLS.
  static ServerAddress? _manualAddress(String input) {
    if (input.isEmpty) return null;
    if (input.contains('://')) return parseServerAddress(input);
    return parseServerAddress(input.contains(':') ? input : '$input:8000');
  }

  void _tryDemo() {
    final demo = demoServer();
    _connectToServer(
      demoServerName,
      demo.host,
      demo.port,
      scheme: demo.scheme,
      failure: demoServerUnreachable,
    );
  }

  Future<void> _animateClose() async {
    await _fadeController.reverse();
    widget.onClose?.call();
  }

  void _rescan() {
    // The new list may come back in a different order — let the
    // auto-select in _buildServerList re-pick.
    setState(() => _selectedIndex = null);
    ref.read(discoveryProvider.notifier).rescan();
  }

  @override
  Widget build(BuildContext context) {
    final discoveryState = ref.watch(discoveryProvider);
    final showGradient = _isConnecting || discoveryState.isScanning;

    final content = FadeTransition(
      opacity: _fadeController,
      child: Container(
        decoration: BoxDecoration(
          color: KalinkaColors.background,
          gradient: showGradient
              ? const RadialGradient(
                  center: Alignment(0, -0.16),
                  radius: 0.42,
                  colors: [
                    KalinkaColors.surfaceRaised,
                    KalinkaColors.background,
                  ],
                )
              : null,
        ),
        child: SafeArea(
          child: Row(
            children: [
              if (widget.isTablet)
                const Flexible(
                  flex: 5,
                  child: SizedBox(width: double.infinity),
                ),
              Flexible(
                flex: 10,
                child: Column(
                  children: [
                    // Top bar with optional cancel
                    _buildTopBar(),
                    Expanded(
                      child: _isConnecting
                          ? _buildConnectingOverlay()
                          : discoveryState.isScanning
                          ? _buildScanningState()
                          : discoveryState.servers.isEmpty
                          ? _buildEmptyState()
                          : _buildServerList(discoveryState),
                    ),
                  ],
                ),
              ),
              if (widget.isTablet)
                const Flexible(
                  flex: 5,
                  child: SizedBox(width: double.infinity),
                ),
            ],
          ),
        ),
      ),
    );

    // Overlay mode: system back animates the overlay away. The wizard embed
    // (null onClose) manages its own navigation.
    if (widget.onClose == null) return content;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _animateClose();
      },
      child: content,
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (widget.allowCancel)
            _HoverLink(
              label: 'Cancel',
              style: KalinkaTextStyles.cancelButton,
              onTap: _animateClose,
            ),
        ],
      ),
    );
  }

  Widget _buildScanningState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 2),
        _buildScanningArt(),
        const SizedBox(height: 32),
        Text(
          'Looking for Kalinka',
          style: KalinkaTextStyles.expandedTitle.copyWith(
            fontSize: KalinkaTypography.baseSize + 12,
            color: KalinkaColors.frost,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Scanning your local network\u2026',
          style: KalinkaTextStyles.trayRowSublabel.copyWith(
            fontSize: KalinkaTypography.baseSize + 2,
          ),
        ),
        const Spacer(flex: 3),
      ],
    );
  }

  Widget _buildScanningArt() {
    return SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SonarAnimation(
            minRadius: 28,
            maxRadius: 88,
            interval: const Duration(milliseconds: 600),
            fadingFactor: 1.4,
            color: KalinkaColors.accentTint.withValues(alpha: 0.85),
            ringCount: 3,
            strokeWidth: 2.4,
          ),
          // Centre icon
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: KalinkaColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.dns_outlined,
              size: 24,
              color: KalinkaColors.accentTint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    // No mDNS in the browser — explain instead of offering a futile rescan.
    // Normally unreachable: the web UI hides every path into discovery.
    if (kIsWeb) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Server discovery isn\'t available in the browser.\n'
            'This player controls the server that serves this page —\n'
            'reload the page to reconnect.',
            textAlign: TextAlign.center,
            style: KalinkaTextStyles.trayRowSublabel.copyWith(
              fontSize: KalinkaTypography.baseSize + 2,
              color: KalinkaColors.textSecondary,
              height: 1.6,
            ),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 80),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: KalinkaColors.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.dns_outlined,
              size: 26,
              color: KalinkaColors.textMuted,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Nothing found',
            style: KalinkaTextStyles.cardTitle.copyWith(
              color: KalinkaColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No Kalinka servers found on this network.\n'
            'Make sure the server is running and\nyou\'re on the same Wi-Fi.',
            textAlign: TextAlign.center,
            style: KalinkaTextStyles.trayRowSublabel.copyWith(
              fontSize: KalinkaTypography.baseSize + 2,
              color: KalinkaColors.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          // Scan again button
          KalinkaButton(
            label: 'Scan again',
            variant: KalinkaButtonVariant.accent,
            size: KalinkaButtonSize.normal,
            fullWidth: true,
            onTap: _rescan,
          ),
          const SizedBox(height: 12),
          KalinkaButton(
            label: 'Try demo server',
            variant: KalinkaButtonVariant.neutral,
            size: KalinkaButtonSize.normal,
            fullWidth: true,
            onTap: _tryDemo,
          ),
          const SizedBox(height: 20),
          // Separator
          Divider(color: Colors.white.withValues(alpha: 0.07), height: 1),
          const SizedBox(height: 16),
          // Manual entry section
          Text(
            'OR ENTER ADDRESS MANUALLY',
            style: KalinkaTextStyles.sectionHeaderMuted,
          ),
          const SizedBox(height: 12),
          _buildManualEntryFields(),
        ],
      ),
    );
  }

  /// Any of the server's endpoints may be the connected address — grouping
  /// lists a multi-homed Core under its fastest one, not necessarily ours.
  bool _isCurrent(DiscoveredServer server) {
    final current = widget.currentServerHost;
    return current != null && server.reachableAt(current);
  }

  Widget _buildServerList(DiscoveryState discoveryState) {
    final servers = discoveryState.servers;
    final serverCount = servers.length;

    // Auto-select first non-current server if nothing selected yet
    if (_selectedIndex == null) {
      final firstIdx = servers.indexWhere((s) => !_isCurrent(s));
      if (firstIdx >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selectedIndex = firstIdx);
        });
      }
    }

    return Column(
      children: [
        const SizedBox(height: 32),
        Text(
          'Looking for Kalinka',
          style: KalinkaTextStyles.expandedTitle.copyWith(
            fontSize: KalinkaTypography.baseSize + 12,
            color: KalinkaColors.frost,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$serverCount server${serverCount == 1 ? '' : 's'} '
          'found on your network',
          style: KalinkaTextStyles.trayRowSublabel.copyWith(
            fontSize: KalinkaTypography.baseSize + 2,
          ),
        ),
        const SizedBox(height: 24),
        // Server list — settings-style adjacent rows in a single card
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: KalinkaColors.surfaceRaised,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: KalinkaColors.borderDefault),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (int i = 0; i < servers.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.white.withValues(alpha: 0.07),
                      indent: 0,
                      endIndent: 0,
                    ),
                  _buildServerRow(
                    servers[i],
                    i,
                    _selectedIndex == i && !_isCurrent(servers[i]),
                    _isCurrent(servers[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
        const Spacer(),
        // Rescan + Connect, mirroring the wizard footer's neutral/accent pair.
        // A found list can still be missing a server whose announcement was
        // dropped, and the wizard embed has no other way back into scanning.
        if (!_showManualEntry) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                KalinkaButton(
                  label: 'Rescan',
                  variant: KalinkaButtonVariant.neutral,
                  size: KalinkaButtonSize.normal,
                  leading: const Icon(
                    Icons.refresh_rounded,
                    size: 16,
                    color: KalinkaColors.textSecondary,
                  ),
                  onTap: _rescan,
                ),
                const SizedBox(width: 12),
                Expanded(child: _buildConnectButton(servers)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 24,
              runSpacing: 8,
              children: [
                _HoverLink(
                  label: 'Enter Address Manually',
                  style: _footerLinkStyle,
                  onTap: () => setState(() => _showManualEntry = true),
                ),
                _HoverLink(
                  label: 'Try Demo Server',
                  style: _footerLinkStyle,
                  onTap: _tryDemo,
                ),
              ],
            ),
          ),
        ],
        if (_showManualEntry) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: _buildManualEntryFields(),
          ),
        ],
      ],
    );
  }

  static final _footerLinkStyle = KalinkaTextStyles.trayRowSublabel.copyWith(
    fontSize: KalinkaTypography.baseSize + 2,
    decoration: TextDecoration.underline,
  );

  Widget _buildServerRow(
    DiscoveredServer server,
    int index,
    bool isSelected,
    bool isCurrent,
  ) {
    final latencyLabel = server.latencyMs > 0
        ? '${server.latencyMs}ms'
        : 'Latency Unknown';
    final version = server.version;
    final versionLabel = (version != null && version.isNotEmpty)
        ? 'v$version'
        : 'Version unknown';

    return GestureDetector(
      onTap: isCurrent
          ? null
          : () => setState(() {
              _selectedIndex = index;
              _showManualEntry = false;
            }),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          // Row content
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.fromLTRB(13, 13, 15, 13),
            color: isSelected
                ? KalinkaColors.surfaceElevated
                : Colors.transparent,
            child: Row(
              children: [
                // Icon tile
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: KalinkaColors.surfaceOverlay,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.dns_outlined,
                    size: 18,
                    color: KalinkaColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                // Name + details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.name,
                        style: KalinkaTextStyles.trayRowLabel.copyWith(
                          fontSize: KalinkaTypography.baseSize + 3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${server.host} \u00b7 $latencyLabel',
                        style: KalinkaTextStyles.trayRowSublabel.copyWith(
                          fontSize: KalinkaTypography.baseSize + 2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        versionLabel,
                        style: KalinkaTextStyles.trayRowSublabel.copyWith(
                          fontSize: KalinkaTypography.baseSize + 2,
                          color: KalinkaColors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Current pill or signal bars
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: KalinkaColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: KalinkaColors.borderDefault),
                    ),
                    child: Text(
                      'CURRENT',
                      style: KalinkaTextStyles.tagPill.copyWith(
                        color: KalinkaColors.textMuted,
                        fontSize: KalinkaTypography.baseSize,
                        letterSpacing: 0.8,
                      ),
                    ),
                  )
                else
                  _buildSignalBars(server.signalStrength),
              ],
            ),
          ),
          // Top-half accent selection bar
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.topCenter,
              child: FractionallySizedBox(
                heightFactor: 0.5,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 2,
                  color: isSelected ? KalinkaColors.accent : Colors.transparent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalBars(int strength) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final heights = [5.0, 8.0, 11.0, 14.0];
        final isActive = i < strength;
        return Container(
          width: 3,
          height: heights[i],
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: isActive
                ? KalinkaColors.textSecondary
                : KalinkaColors.textMuted,
            borderRadius: BorderRadius.circular(1.5),
          ),
        );
      }),
    );
  }

  Widget _buildConnectButton(List<DiscoveredServer> servers) {
    final hasSelection =
        _selectedIndex != null && _selectedIndex! < servers.length;
    final selected = hasSelection ? servers[_selectedIndex!] : null;

    return KalinkaButton(
      label: hasSelection ? 'Connect to ${selected!.name}' : 'Select a server',
      variant: KalinkaButtonVariant.accent,
      size: KalinkaButtonSize.normal,
      fullWidth: true,
      enabled: hasSelection,
      onTap: hasSelection
          ? () => _connectToServer(selected!.name, selected.host, selected.port)
          : null,
    );
  }

  Widget _buildManualEntryFields() {
    return Row(
      children: [
        // Host field
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: KalinkaColors.surfaceInput,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: KalinkaColors.borderDefault),
            ),
            child: TextField(
              controller: _hostController,
              style: KalinkaTextStyles.searchBarInput.copyWith(
                fontSize: KalinkaTypography.baseSize + 2,
              ),
              decoration: InputDecoration(
                hintText: '192.168.50.85:8000',
                hintStyle: KalinkaTextStyles.searchPlaceholder.copyWith(
                  fontSize: KalinkaTypography.baseSize + 2,
                  color: KalinkaColors.textSecondary,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                isDense: true,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Connect button
        KalinkaButton(
          label: 'Connect',
          variant: KalinkaButtonVariant.accent,
          size: KalinkaButtonSize.compact,
          onTap: () {
            final address = _manualAddress(_hostController.text.trim());
            if (address == null) return;
            _connectToServer(
              'Kalinka Server',
              address.host,
              address.port,
              scheme: address.scheme,
            );
          },
        ),
      ],
    );
  }

  Widget _buildConnectingOverlay() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Spinner
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: const AlwaysStoppedAnimation(KalinkaColors.accent),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Connecting\u2026',
            style: KalinkaTextStyles.expandedTitle.copyWith(
              fontSize: KalinkaTypography.baseSize + 8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Reaching ${ref.read(connectionSettingsProvider).host}',
            style: KalinkaTextStyles.trayRowSublabel.copyWith(
              fontSize: KalinkaTypography.baseSize + 2,
            ),
          ),
          if (_connectError != null) ...[
            const SizedBox(height: 24),
            Text(
              _connectError!,
              textAlign: TextAlign.center,
              style: KalinkaTextStyles.trayRowSublabel.copyWith(
                color: KalinkaColors.statusOffline,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                KalinkaButton(
                  label: 'Try again',
                  variant: KalinkaButtonVariant.neutral,
                  size: KalinkaButtonSize.compact,
                  onTap: () => _retry?.call(),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isConnecting = false;
                      _connectError = null;
                    });
                  },
                  child: Text('Cancel', style: KalinkaTextStyles.cancelButton),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Text link that answers the pointer: brightens and lifts onto a faint
/// surface under the mouse, and shows the click cursor. Without it "Cancel"
/// and "Enter Address Manually" read as captions rather than controls.
class _HoverLink extends StatefulWidget {
  final String label;
  final TextStyle style;
  final VoidCallback onTap;

  const _HoverLink({
    required this.label,
    required this.style,
    required this.onTap,
  });

  @override
  State<_HoverLink> createState() => _HoverLinkState();
}

class _HoverLinkState extends State<_HoverLink> {
  bool _hovered = false;

  void _setHover(bool value) {
    if (value != _hovered) setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final color = _hovered
        ? KalinkaColors.textPrimary
        : KalinkaColors.textSecondary;

    return Semantics(
      label: widget.label,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHover(true),
        onExit: (_) => _setHover(false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _hovered
                  ? KalinkaColors.surfaceElevated
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.label,
              style: widget.style.copyWith(
                color: color,
                decorationColor: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
