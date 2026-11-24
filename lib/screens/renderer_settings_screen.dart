import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'room_eq_screen.dart';

import '../data_model/presentation_schema.dart' show SectionSpec;
import '../data_model/renderer_config.dart' show RendererApplyCost;
import '../providers/kalinka_player_api_provider.dart';
import '../providers/renderer_provider.dart';
import '../providers/renderer_settings_provider.dart';
import '../providers/renderer_settings_route_provider.dart';
import '../providers/settings_provider.dart' show expertModeProvider;
import '../providers/soundcard_provider.dart';
import '../providers/supervisor_api.dart';
import '../providers/toast_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/keyboard/app_keyboard_navigation.dart';
import '../widgets/connection_banner.dart';
import '../widgets/configuration_appearance.dart';
import '../widgets/settings_top_bar.dart';
import '../widgets/renderer_settings_dashboard.dart';
import '../widgets/room_eq/eq_card.dart';
import '../widgets/expert_field_list.dart';
import '../widgets/demo_read_only_dialog.dart';
import '../widgets/expert_mode_toggle.dart';
import '../widgets/kalinka_button.dart';
import '../widgets/kalinka_dialog.dart' show showKalinkaDialog;
import '../widgets/onboarding/soundcard_restart_overlay.dart';
import '../widgets/onboarding/speaker_test_dialog.dart';
import '../widgets/pending_changes.dart';
import '../widgets/settings_controls/settings_binding.dart';
import '../widgets/settings_renderer.dart';
import '../widgets/slide_in_panel.dart';
import '../widgets/soundcard_row.dart';

/// One renderer's own settings, drawn by the same schema renderer as the
/// server's settings page.
///
/// A separate page rather than a section of server settings, because the
/// values live on the renderer: they are read from it on demand, written path
/// by path, and apply without restarting the server.
///
/// Hosted the same way as Configuration — a [SlideInPanel] the host places
/// over the whole screen on phone and inside the browsing pane on tablet.
class RendererSettingsScreen extends ConsumerStatefulWidget {
  final String rendererId;
  final String rendererName;

  /// Close callback for overlay mode. When null the panel behaves as a route
  /// and pops itself.
  final VoidCallback? onClose;

  /// Fires `true` once the slide-in finishes and `false` as the slide-out
  /// begins, so the host can stop painting what the panel covers.
  final ValueChanged<bool>? onCoverageChanged;

  const RendererSettingsScreen({
    super.key,
    required this.rendererId,
    required this.rendererName,
    this.onClose,
    this.onCoverageChanged,
  });

  /// The key its host gives the page open for [route], by which [mayLeave]
  /// finds it.
  static GlobalKey<RendererSettingsScreenState> keyFor(
    RendererSettingsRoute route,
  ) => GlobalObjectKey<RendererSettingsScreenState>(route);

  /// Whether the page open for [route], if any, may be closed or replaced:
  /// with edits staged it asks what becomes of them first. Every way out of
  /// the page goes through here, since its edits go with it.
  static Future<bool> mayLeave(RendererSettingsRoute? route) async {
    if (route == null) return true;
    return await keyFor(route).currentState?.prepareToNavigate() ?? true;
  }

  @override
  ConsumerState<RendererSettingsScreen> createState() =>
      RendererSettingsScreenState();
}

class RendererSettingsScreenState
    extends ConsumerState<RendererSettingsScreen> {
  String? _section;
  void _openSection(String? id) {
    setState(() => _section = id);
    _focusBody();
  }

  void _focusBody() {
    final body = _bodyKey.currentContext;
    if (body != null) {
      AppKeyboardNavigation.focusAfterBuild(body, AppKeyboardArea.content);
    }
  }

  String? _expertField;
  RoomEqSection? _roomEqSection;
  bool _roomEqOpen = false;
  bool _roomEqCovered = false;
  final _eqKey = GlobalKey<RoomEqScreenState>();
  final _bodyKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notifier.load();
    });
  }

  RendererSettingsNotifier get _notifier =>
      ref.read(rendererSettingsProvider(widget.rendererId).notifier);

  late final _soundcardHost = SoundcardHost(setUp: _setUpSoundcard);

  /// The box a change from this page last set up.
  SoundcardBox? _changing;

  Future<void> _setUpSoundcard(SoundcardBox box, SoundcardOption card) {
    _changing = box;
    return _runSoundcardChange(
      card,
      ref.read(soundcardChangeProvider(box).notifier).apply,
    );
  }

  /// Closed during the apply, the page would be gone by the time the box
  /// restarts, leaving nothing to end the wait if it does not come back.
  bool _mayClose(SoundcardBox? restarting) {
    final changing = _changing;
    return restarting == null &&
        (changing == null ||
            ref.read(soundcardChangeProvider(changing)) !=
                SoundcardStep.applying);
  }

  Future<void> _keepWaiting(SoundcardBox box, SoundcardOption card) =>
      _runSoundcardChange(
        card,
        ref.read(soundcardChangeProvider(box).notifier).keepWaiting,
      );

  Future<void> _apply() async {
    if (!await refusedAsDemo(context, ref)) await _notifier.save();
  }

  Future<void> _edit(String path, dynamic value) async {
    final state = ref.read(rendererSettingsProvider(widget.rendererId));
    if (state.saving) return;
    if (path == RoomEqScreen.firPath &&
        state.applyCosts[path] == RendererApplyCost.instant) {
      if (state.values[path] != value &&
          !await refusedAsDemo(context, ref) &&
          mounted) {
        await _notifier.save(immediate: {path: value});
      }
      return;
    }
    _notifier.stage(path, value);
  }

  /// Leaving with edits staged asks what becomes of them: they live only as
  /// long as the page does.
  Future<bool> _beforeClose(SoundcardBox? restarting) async {
    if (!_mayClose(restarting)) return false;
    final eq = _eqKey.currentState;
    if (eq != null && !await eq.mayLeave()) return false;
    if (!mounted) return false;
    final state = ref.read(rendererSettingsProvider(widget.rendererId));
    if (state.saving) return false;
    if (!state.hasPendingChanges) return true;
    final choice = await askAboutPendingChanges(
      context,
      items: describeRendererChanges(state, state.staged.keys),
      message: switch (state.pendingCost) {
        RendererApplyCost.interruptsPlayback =>
          'Applying them stops playback on this output.',
        RendererApplyCost.restartRequired =>
          'Applying them restarts this output.',
        _ => null,
      },
    );
    if (!mounted) return false;
    switch (choice) {
      case PendingChangesChoice.discard:
        _notifier.discard();
        return true;
      case PendingChangesChoice.apply:
        await _apply();
        if (!mounted) return false;
        // A refusal is said on the page, which stays open to show it.
        final after = ref.read(rendererSettingsProvider(widget.rendererId));
        return !after.hasPendingChanges && after.error == null;
      case null:
        return false;
    }
  }

  /// The shell's destinations leave the page as Back does.
  Future<bool> prepareToNavigate() => _beforeClose(
    ref
        .read(restartingBoxesProvider)
        .where((b) => b.rendererId == widget.rendererId)
        .firstOrNull,
  );

  /// The change tells in toasts how it went once the box took the card; this
  /// covers it failing before then, or outright.
  Future<void> _runSoundcardChange(
    SoundcardOption card,
    Future<SoundcardOutcome> Function(SoundcardOption card) run,
  ) async {
    final toasts = ref.read(toastProvider.notifier);
    try {
      await run(card);
    } on BoxActionException catch (e) {
      toasts.show(e.message, isError: true);
    } catch (e) {
      toasts.show('Could not set up ${card.label}: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rendererSettingsProvider(widget.rendererId));
    final expertMode = ref.watch(expertModeProvider);

    final section = state.sections.where((s) => s.id == _section).firstOrNull;
    final name = state.configuredName ?? widget.rendererName;
    final title = _expertField != null
        ? 'Expert settings'
        : expertMode
        ? name
        : section?.title ?? name;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The renderer is what the page is for, so it is the title.
        SettingsTopBar(
          title: title,
          entryFocus: KeyboardEntryFocus.scope,
          action: _expertField == null ? const ExpertModeToggle() : null,
        ),
        const ConnectionBanner(),
        if (state.saving) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: AbsorbPointer(
            absorbing: state.saving,
            child: _buildBody(state, expertMode),
          ),
        ),
      ],
    );
    // A sound card change that restarts the box takes the output away: the
    // page waits under the restart, as it does under the server's.
    final box = ref.watch(
      restartingBoxesProvider.select(
        (boxes) =>
            boxes.where((b) => b.rendererId == widget.rendererId).firstOrNull,
      ),
    );
    final change = box == null
        ? null
        : ref.read(soundcardChangeProvider(box).notifier);
    final card = change?.card;

    return PendingChangesScope(
      changes: PendingChanges(
        count: state.pendingCount,
        consequence: state.pendingCost.warning,
        busy: state.saving,
        onDiscard: _notifier.discard,
        onApply: _apply,
      ),
      child: SlideInPanel(
        contentEntryFocus: KeyboardEntryFocus.none,
        onClose: widget.onClose,
        handlesBack: !_roomEqOpen,
        beforeClose: () async {
          if (_expertField != null) {
            if (_mayClose(box) && !state.saving) {
              setState(() => _expertField = null);
              _focusBody();
            }
            return false;
          }
          if (!expertMode && _section != null) {
            if (_mayClose(box) && !state.saving) _openSection(null);
            return false;
          }
          return _beforeClose(box);
        },
        onCoverageChanged: widget.onCoverageChanged,
        overlays: [
          if (_roomEqOpen)
            SlideInPanel(
              key: const ValueKey('room-eq-panel'),
              contentEntryFocus: KeyboardEntryFocus.none,
              handlesBack: box == null || card == null,
              beforeClose: () async =>
                  await _eqKey.currentState?.mayLeave() ?? false,
              onCoverageChanged: (covered) =>
                  setState(() => _roomEqCovered = covered),
              onClose: () {
                setState(() => _roomEqOpen = false);
                _focusBody();
              },
              child: SettingsScope(
                binding: RendererSettingsBinding(state, _edit),
                child: RoomEqScreen(
                  key: _eqKey,
                  initialSection: _roomEqSection,
                  rendererId: widget.rendererId,
                  rendererName: name,
                ),
              ),
            ),
          if (box != null && change != null && card != null)
            SoundcardRestartOverlay(
              box: box,
              card: card,
              afterwards: 'The output comes back by itself.',
              onKeepWaiting: () => _keepWaiting(box, card),
              onContinue: change.stopWaiting,
              continueLabel: 'Continue',
            ),
        ],
        child: SizedBox.expand(
          child: Offstage(
            offstage: _roomEqCovered,
            child: IgnorePointer(
              ignoring: _roomEqOpen,
              child: Material(
                color: KalinkaColors.background,
                child: ConfigurationAppearance(
                  child: SafeArea(top: false, child: content),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(RendererSettingsState state, bool expertMode) {
    if (state.loading && !state.loaded) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(KalinkaColors.accent),
        ),
      );
    }

    final binding = RendererSettingsBinding(state, _edit);

    // Expert: every field the renderer declared, by path, searchable — the
    // same list the server's settings show, pointed at this renderer. No
    // speaker test here; it belongs with the page, not the flat list.
    if (expertMode || _expertField != null) {
      if (state.expertFields.isEmpty) return _buildLoadFailure(state.error);
      return Column(
        key: _bodyKey,
        children: [
          if (state.error != null) _ErrorNote(message: state.error!),
          Expanded(
            child: ExpertFieldList(
              initialQuery: _expertField ?? '',
              fields: state.expertFields,
              binding: binding,
            ),
          ),
        ],
      );
    }

    final hasPeq = state.values.containsKey('dsp.profile');
    final hasFir = state.values.containsKey(RoomEqScreen.firPath);
    final hasEq = hasPeq || hasFir;
    if (state.sections.isEmpty && !hasEq) {
      // Told apart from "nothing at all": the renderer does have settings,
      // they are just all expert-tier, so point at the switch that shows them.
      if (state.expertFields.isNotEmpty) return _buildExpertOnlyNote();
      return _buildLoadFailure(state.error);
    }

    final section = state.sections.where((s) => s.id == _section).firstOrNull;
    final cardBox = ref
        .watch(rendererSoundcardBoxProvider(widget.rendererId))
        .value;
    final card = cardBox == null
        ? null
        : ref.watch(soundcardReportProvider(cardBox)).value;
    return SettingsScope(
      key: _bodyKey,
      binding: binding,
      splitEditableRows: true,
      child: ListView(
        key: PageStorageKey(_section ?? 'renderer-index'),
        padding: const EdgeInsets.symmetric(vertical: 20),
        children: [
          if (state.error != null) _ErrorNote(message: state.error!),
          if (section != null)
            SchemaSectionRenderer(
              section: section,
              isTopLevel: true,
              showHeading: false,
              replaced: hasEq ? RoomEqScreen.fieldPaths : const {},
              subtitle: section.id == 'renderer'
                  ? _RendererAddressBadge(rendererId: widget.rendererId)
                  : null,
            )
          else
            RendererSettingsDashboard(
              state: state,
              rendererId: widget.rendererId,
              rendererName: widget.rendererName,
              onSection: _openSection,
              roomEqFields: hasEq ? RoomEqScreen.fieldPaths : const {},
              firPath: RoomEqScreen.firPath,
              onRoomEq: (section) => setState(() {
                _roomEqSection = section;
                _roomEqOpen = true;
              }),
              onExpertField: (path) {
                setState(() => _expertField = path);
                _focusBody();
              },
              onSpeakerTest: () => showKalinkaDialog<void>(
                context: context,
                builder: (_) => SpeakerTestDialog(
                  targetName: state.configuredName ?? widget.rendererName,
                  playTone: (channel) => ref
                      .read(kalinkaProxyProvider)
                      .testTone(channel, rendererId: widget.rendererId),
                ),
              ),
              soundcard: card != null && cardBox != null
                  ? SoundcardRow(
                      box: cardBox,
                      report: card,
                      host: _soundcardHost,
                    )
                  : null,
            ),
        ],
      ),
    );
  }

  /// Shown when the renderer marked every setting it has as expert — the page
  /// proper has nothing to draw, but the settings are one switch away.
  Widget _buildExpertOnlyNote() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              ExpertModeToggle.icon,
              color: KalinkaColors.textSecondary,
              size: 32,
            ),
            const SizedBox(height: 12),
            Text('Expert settings only', style: KalinkaTextStyles.cardTitle),
            const SizedBox(height: 8),
            Text(
              'This output keeps all of its settings in expert view. Turn on '
              'Expert settings at the top to see them by path.',
              textAlign: TextAlign.center,
              style: KalinkaTextStyles.trayRowSublabel,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadFailure(String? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.speaker_outlined,
              color: KalinkaColors.textSecondary,
              size: 32,
            ),
            const SizedBox(height: 12),
            Text(
              error == null ? 'No settings to show' : 'Couldn’t load settings',
              style: KalinkaTextStyles.cardTitle,
            ),
            const SizedBox(height: 8),
            Text(
              error ?? 'This output reports no settings of its own.',
              textAlign: TextAlign.center,
              style: KalinkaTextStyles.trayRowSublabel,
            ),
            if (error != null) ...[
              const SizedBox(height: 16),
              KalinkaButton(
                label: 'Retry',
                variant: KalinkaButtonVariant.accent,
                size: KalinkaButtonSize.compact,
                onTap: _notifier.load,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The staged [paths] as the leave dialog lists them: each setting by its
/// label, with the section that shows it.
List<PendingChangeItem> describeRendererChanges(
  RendererSettingsState state,
  Iterable<String> paths,
) {
  String? whereIs(List<SectionSpec> sections, String path) {
    for (final section in sections) {
      if (whereIs(section.sections, path) case final inner?) return inner;
      if (section.fields.any((f) => f.path == path)) return section.title;
    }
    return null;
  }

  return [
    for (final path in paths)
      PendingChangeItem(
        state.expertFields.where((f) => f.path == path).firstOrNull?.label ??
            path,
        where: whereIs(state.sections, path),
      ),
  ];
}

/// `host · vX.Y` under the RENDERER section title, from the same list the
/// renderer switcher shows.
class _RendererAddressBadge extends ConsumerWidget {
  final String rendererId;
  const _RendererAddressBadge({required this.rendererId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(
      rendererListProvider.select(
        (s) => s.renderers.where((r) => r.rendererId == rendererId).firstOrNull,
      ),
    );
    if (info == null) return const SizedBox.shrink();
    final parts = <String>[
      if (info.hostname.isNotEmpty) info.hostname,
      if (info.softwareVersion.isNotEmpty) 'v${info.softwareVersion}',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join(' · '),
      style: KalinkaTextStyles.trayRowSublabel.copyWith(
        fontSize: KalinkaTypography.baseSize + 1,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Amber inline note for a save the renderer partly refused. Distinct from the
/// full-page failure: the page still holds good content.
class _ErrorNote extends StatelessWidget {
  final String message;
  const _ErrorNote({required this.message});

  @override
  Widget build(BuildContext context) {
    final inset = ConfigurationAppearance.sideInset(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 16, inset, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_rounded,
            size: 15,
            color: KalinkaColors.statusPendingLight,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: KalinkaTextStyles.trayRowSublabel.copyWith(
                color: KalinkaColors.statusPendingLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
