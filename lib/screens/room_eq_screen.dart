import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/presentation_schema.dart';
import '../data_model/renderer_config.dart';
import '../data_model/room_eq.dart';
import '../generated/kalinka/renderer/v1/renderer.pb.dart' show FirProfile;
import '../providers/kalinka_player_api_provider.dart';
import '../providers/app_state_provider.dart';
import '../providers/renderer_settings_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/browse_filters/browse_filter_form.dart' show FilterPill;
import '../widgets/connection_banner.dart';
import '../widgets/demo_read_only_dialog.dart';
import '../widgets/kalinka_button.dart';
import '../widgets/kalinka_bottom_sheet.dart';
import '../widgets/settings_controls/option_picker.dart';
import '../widgets/settings_controls/settings_help_button.dart';
import '../widgets/keyboard/app_keyboard_navigation.dart';
import '../widgets/kalinka_dialog.dart';
import '../widgets/room_eq/editor_dialogs.dart';
import '../widgets/room_eq/eq_card.dart';
import '../widgets/room_eq/filter_inspector.dart';
import '../widgets/room_eq/filter_shape_icon.dart';
import '../widgets/room_eq/response_graph.dart';
import '../widgets/settings_top_bar.dart';
import '../widgets/settings_controls/settings_jump_target.dart';
import '../widgets/tap_highlight.dart'
    show kalinkaIconButtonStyle, kalinkaOverlay;
import '../widgets/settings_renderer.dart' show SchemaFieldRenderer;

class RoomEqScreen extends ConsumerStatefulWidget {
  const RoomEqScreen({
    super.key,
    required this.rendererId,
    required this.rendererName,
    this.initialSection,
  });
  final String rendererId, rendererName;
  final RoomEqSection? initialSection;
  static const firPath = RendererConfigField.rewFirProfile;
  static const fieldPaths = {
    firPath,
    'dsp.profile',
    'dsp.enabled',
    'dsp.bypass',
    'dsp.preamp',
    'dsp.preamp_db',
  };
  @override
  ConsumerState<RoomEqScreen> createState() => RoomEqScreenState();
}

class RoomEqScreenState extends ConsumerState<RoomEqScreen> {
  EqCurve curve = EqCurve.empty();
  EqChannel channel = EqChannel.shared;
  int selected = 0;
  final inspectorKey = GlobalKey();
  final _initialTarget = GlobalKey<SettingsJumpTargetState>();

  Widget _section(RoomEqSection? section, Widget child) =>
      section != null && widget.initialSection == section
      ? SettingsJumpTarget(key: _initialTarget, child: child)
      : child;
  EqBand? sliderPreview;
  bool dirty = false, busy = true, readFailed = false;
  bool running = false;
  String? error;
  List<EqBand> get bands => curve.channels[channel]!;
  RendererSettingsState get settings =>
      ref.read(rendererSettingsProvider(widget.rendererId));
  KalinkaPlayerProxy get api => ref.read(kalinkaProxyProvider);
  bool writable(String path) =>
      settings.expertFields.any((f) => f.path == path && !f.readonly);
  String get presetId => settings.values['dsp.profile']?.toString() ?? 'none';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!settings.loaded) {
        await ref
            .read(rendererSettingsProvider(widget.rendererId).notifier)
            .load();
      }
      if (!mounted) return;
      await run(() => readPreset(presetId));
      if (mounted && widget.initialSection != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _initialTarget.currentState?.reveal(),
        );
      }
    });
  }

  Future<void> run(Future<void> Function() work) async {
    if (running) return;
    running = true;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      running = false;
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> readPreset(String id) async {
    try {
      final next = id == 'none' ? EqCurve.empty() : await api.getEqCurve(id);
      if (!mounted) return;
      setState(() {
        curve = next;
        sliderPreview = null;
        channel = next.channels.keys.first;
        selected = 0;
        dirty = false;
        readFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => readFailed = true);
      rethrow;
    }
  }

  /// Refresh the renderer's authoritative values while preserving pending edits
  /// made elsewhere in its settings.
  Future<void> write(Map<String, String> changes) async {
    final reply = await api.updateRendererConfig(widget.rendererId, changes);
    await refreshAfter(reply);
  }

  Future<void> refreshAfter(RendererConfigResult reply) async {
    if (!mounted) return;
    await ref
        .read(rendererSettingsProvider(widget.rendererId).notifier)
        .load(keepStaged: true);
    if (!mounted) return;
    if (reply.rejected.isNotEmpty) {
      final refusal = reply.rejected.first;
      throw RendererConfigException(
        refusal.error.isEmpty
            ? 'The renderer refused ${refusal.path}.'
            : refusal.error,
      );
    }
    if (settings.error != null) throw RendererConfigException(settings.error!);
  }

  Future<void> changeSetting(Map<String, String> changes) async {
    if (busy || await refusedAsDemo(context, ref) || !mounted) return;
    await run(() => write(changes));
  }

  void edit(List<EqBand> next, int index) {
    if (busy) return;
    setState(() {
      sliderPreview = null;
      curve = curve.withBands(channel, next);
      selected = index;
      dirty = true;
    });
    applyEdit();
  }

  Future<void> applyEdit() async {
    if (busy || await refusedAsDemo(context, ref) || !mounted) return;
    await run(() async {
      if (hasActiveBand) {
        await refreshAfter(
          await api.editEqCurve(widget.rendererId, curve.toRew('Current EQ')),
        );
      } else {
        await write({'dsp.profile': 'none'});
      }
      if (mounted) setState(() => dirty = false);
    });
  }

  void changeBand(EqBand value) {
    final original = bands[selected];
    if (original.hz == value.hz &&
        original.gain == value.gain &&
        original.q == value.q &&
        original.shape == value.shape) {
      if (sliderPreview != null) setState(() => sliderPreview = null);
      return;
    }
    edit([...bands]..[selected] = value, selected);
  }

  void selectBand(int i) => setState(() {
    sliderPreview = null;
    selected = i;
  });

  Future<bool> discard() async {
    if (!dirty) return true;
    return await showKalinkaDialog<bool>(
          context: context,
          builder: (ctx) => KalinkaDialog(
            side: KalinkaDialogSide.player,
            title: 'Discard unapplied edits?',
            message: 'The renderer hasn’t confirmed these EQ changes.',
            actions: [
              KalinkaButton(
                label: 'Keep editing',
                variant: KalinkaButtonVariant.neutral,
                fullWidth: true,
                onTap: () => Navigator.pop(ctx, false),
              ),
              KalinkaButton(
                label: 'Discard',
                fullWidth: true,
                onTap: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> mayLeave() async => !busy && !settings.saving && await discard();

  Future<void> choosePreset() async {
    final options = settings.options['dsp.profile'] ?? [];
    final picked = await showKalinkaBottomSheet<String>(
      context: context,
      dialogMaxWidth: kKalinkaContentMaxWidth,
      contentBuilder: (_) =>
          OptionPicker(options: options, selectedValue: presetId),
    );
    if (!mounted ||
        picked == null ||
        picked == presetId ||
        !await discard() ||
        !mounted ||
        await refusedAsDemo(context, ref) ||
        !mounted) {
      return;
    }
    await selectPreset(picked);
  }

  Future<void> selectPreset(String id) => run(() async {
    await write({'dsp.profile': id});
    if (mounted) await readPreset(presetId);
  });

  bool get hasActiveBand =>
      curve.channels.values.expand((c) => c).any((b) => b.active);

  Future<void> importImpulse() async {
    if (busy || await refusedAsDemo(context, ref) || !mounted) return;
    await run(() async {
      final files = await openFiles(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Impulse WAVs',
            extensions: ['wav', 'wave'],
            mimeTypes: ['audio/wav', 'audio/x-wav', 'audio/wave'],
            uniformTypeIdentifiers: ['com.microsoft.waveform-audio'],
          ),
        ],
      );
      if (!mounted || files.isEmpty) return;
      if (files.length > 8) {
        throw RendererConfigException(
          'Choose up to eight WAVs, one per sample rate.',
        );
      }
      final title = await editEqValue(
        context,
        title: 'Import impulse WAV',
        label: 'Filter name',
        initial: files.first.name.replaceFirst(
          RegExp(r'\.(wav|wave)$', caseSensitive: false),
          '',
        ),
        message:
            '${files.map((file) => file.name).join(', ')}\n\nYou can include one WAV per sample rate in this preset. This filter will be selected on ${widget.rendererName}.',
        action: 'Import',
        validate: validatePresetName,
      );
      if (title == null || !mounted) return;
      final profile = FirProfile(name: title);
      var size = profile.writeToBuffer().length;
      for (final file in files) {
        size += await file.length() + 6;
        if (size > 32 * 1024 * 1024) {
          throw RendererConfigException('Choose WAVs totalling up to 32 MiB.');
        }
        profile.impulseWav.add(await file.readAsBytes());
      }
      final id = await api.importFirProfile(profile.writeToBuffer());
      if (mounted) await write({RoomEqScreen.firPath: id});
    });
  }

  Future<void> publish({required bool importing}) async {
    if (busy || await refusedAsDemo(context, ref) || !mounted) return;
    final Map<String, String>? payload;
    if (importing) {
      if (!await discard() || !mounted) return;
      payload = await chooseRewPreset(context, widget.rendererName);
    } else {
      final title = await editEqValue(
        context,
        title: 'Save EQ preset',
        icon: Icons.save_outlined,
        hint: 'Name this preset',
        label: 'Preset name',
        initial: curve.name.isEmpty || curve.name == 'Current EQ'
            ? ''
            : '${curve.name} (edited)',
        validate: validatePresetName,
        action: 'Save',
        message:
            'Save this curve to the Core and select it on ${widget.rendererName}.',
      );
      payload = title == null ? null : curve.toRew(title);
    }
    if (!mounted || payload == null) return;
    await run(() async {
      final id = await api.importEqCurve(payload!);
      if (!mounted) return;
      try {
        await write({'dsp.profile': id});
      } catch (e) {
        throw RendererConfigException(
          'Preset saved to the Core. Renderer settings: $e',
        );
      }
      if (mounted) await readPreset(presetId);
    });
  }

  Widget settingSwitch(RendererSettingsState s, String label, String path) {
    final enabled = s.values[path] == true;
    final canToggle = !busy && !s.saving && writable(path);
    void toggle(bool value) => changeSetting({path: value.toString()});
    return MergeSemantics(
      child: InkWell(
        onTap: canToggle ? () => toggle(!enabled) : null,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 6),
            Flexible(child: Text(label)),
            const SizedBox(width: 4),
            Switch(value: enabled, onChanged: canToggle ? toggle : null),
          ],
        ),
      ),
    );
  }

  Widget preampControls(RendererSettingsState s) {
    final modes = s.options['dsp.preamp'] ?? <OptionSpec>[],
        mode = s.values['dsp.preamp'];
    final db = s.expertFields
        .where((f) => f.path == 'dsp.preamp_db')
        .firstOrNull;
    final manual = mode == 'manual';
    final canChangeMode = !busy && !s.saving && writable('dsp.preamp');
    final gainControl = db == null
        ? null
        : EqValueControl(
            step: db.constraints?.step ?? .1,
            label: 'Preamp gain',
            unit: 'dB',
            value: double.tryParse('${s.values[db.path]}') ?? 0,
            min: db.constraints?.ge ?? -30,
            max: db.constraints?.le ?? 0,
            onChanged: (manual || mode == null) && writable(db.path)
                ? (v) => changeSetting({db.path: v.toString()})
                : null,
          );
    final automaticHelp = Text(
      'Gain is set automatically to leave headroom for EQ boosts.',
      style: KalinkaTextStyles.trayRowSublabel,
    );

    Widget modeChip(OptionSpec option) {
      final selected = mode == option.value;
      void choose() {
        if (!selected) changeSetting({'dsp.preamp': option.value});
      }

      final onTap = canChangeMode ? choose : null;
      return PillTarget(
        onTap: onTap,
        child: FilterPill(
          label: option.label,
          selected: selected,
          muted: !canChangeMode && !selected,
          onTap: onTap,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EqCard.title('Preamp'),
            if (s.values.containsKey('dsp.enabled') ||
                s.values.containsKey('dsp.bypass'))
              IndexedStack(
                index: s.values['dsp.bypass'] == true
                    ? 2
                    : s.values['dsp.enabled'] == false
                    ? 0
                    : 1,
                children: [
                  for (final status in [
                    'PEQ is off',
                    'Active with PEQ',
                    'DSP bypassed',
                  ])
                    Text(status, style: KalinkaTextStyles.trayRowSublabel),
                ],
              ),
          ],
        ),
        if (modes.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: modes.map(modeChip).toList(),
          ),
        if (manual || mode == 'auto')
          // Both modes occupy the same space, including when text wraps.
          IndexedStack(
            index: manual ? 1 : 0,
            alignment: AlignmentDirectional.centerStart,
            children: [
              automaticHelp,
              gainControl ?? const Text('The preamp uses a fixed gain.'),
            ],
          )
        else if (mode == null && gainControl != null)
          gainControl,
      ],
    );
  }

  void revealInspector() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = inspectorKey.currentContext;
      if (target != null) Scrollable.ensureVisible(target, alignment: .05);
    });
  }

  void addBand(EqBand band, {required bool reveal}) {
    if (busy || !writable('dsp.profile') || bands.length >= 20) return;
    edit([...bands, band], bands.length);
    if (reveal) revealInspector();
  }

  Widget addBandButton() {
    final enabled = !busy && !readFailed && bands.length < 20;
    return PopupMenuButton<FilterShape>(
      enabled: enabled,
      tooltip: 'Add band',
      requestFocus: true,
      position: PopupMenuPosition.under,
      color: KalinkaColors.surfaceDialog,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: KalinkaColors.borderDefault),
      ),
      onSelected: (shape) => addBand(EqBand(shape: shape), reveal: true),
      itemBuilder: (_) => [
        for (final shape in FilterShape.values)
          PopupMenuItem(
            value: shape,
            child: Row(
              children: [
                FilterShapeIcon(shape),
                const SizedBox(width: 12),
                Flexible(child: Text(shape.label)),
              ],
            ),
          ),
      ],
      icon: const Icon(Icons.add_rounded),
      iconSize: 22,
      iconColor: enabled ? KalinkaColors.textPrimary : KalinkaColors.textMuted,
      style: kalinkaIconButtonStyle.copyWith(
        visualDensity: VisualDensity.standard,
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? KalinkaColors.surfaceOverlay
              : kalinkaOverlay.resolve(states),
        ),
      ),
    );
  }

  Widget graph({
    required List<EqBand> plotted,
    required double height,
    required RendererSettingsState settings,
    Widget? toggle,
  }) {
    final bypassed = settings.values['dsp.bypass'] == true;
    final peqOff = settings.values['dsp.enabled'] == false;
    final responseColor = bypassed || peqOff
        ? KalinkaColors.textSecondary
        : KalinkaColors.accent;
    final fir = settings.firResponse;
    final rate = fir?.sampleRate ?? 48000;
    final hasPeq = settings.values.containsKey('dsp.profile');
    final outOfRange = plotted.any((b) => b.hz >= rate / 2 && b.active);
    final showPeq = hasPeq && !outOfRange && !readFailed;
    final stereo = fir != null && fir.rightDb.isNotEmpty;
    String traceLabel(String name) => bypassed ? '$name (bypassed)' : name;
    final traces = <FirTrace>[
      if (fir != null && (!stereo || channel != EqChannel.right))
        (
          db: fir.leftDb,
          color: KalinkaColors.textPrimary,
          dash: 7.0,
          label: traceLabel(stereo ? 'FIR L' : 'FIR'),
        ),
      if (fir != null && stereo && channel != EqChannel.left)
        (
          db: fir.rightDb,
          color: KalinkaColors.textSecondary,
          dash: 3.0,
          label: traceLabel('FIR R'),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) => Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(child: EqCard.title('Filter response')),
                    SettingsHelpButton(
                      label: 'Filter response',
                      details: [
                        if (hasPeq)
                          'The solid line shows the configured PEQ at ${graphRateLabel(rate)}. It turns gray when PEQ is off or DSP is bypassed.',
                        if (fir != null)
                          'Dashed lines show the selected FIR filter at ${graphRateLabel(rate)}, using the renderer’s most recent stereo PCM rate or 48 kHz before first playback. ${fir.sourceRate == rate ? 'The WAV matches this rate.' : 'The renderer converted the ${graphRateLabel(fir.sourceRate)} WAV for this preview.'} The graph shows the configured filter even with DSP bypassed. Deep cuts can extend below the graph.'
                        else if (settings.values[RoomEqScreen.firPath] !=
                                null &&
                            settings.values[RoomEqScreen.firPath] != 'off')
                          'This output has not supplied a FIR response.',
                        'Each trace shows an individual filter response. Room measurements and measured gain margin are unavailable.',
                        if (writable('dsp.profile')) 'Drag a point horizontally to change frequency. For peaks and shelves, drag vertically to change gain. Double-tap empty space to add a peak band, or use the + button to choose a shape.',
                      ].join('\n\n'),
                    ),
                  ],
                ),
              ),
              if (toggle != null)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth / 2),
                  child: toggle,
                ),
            ],
          ),
        ),
        if (!readFailed && curve.channels.length > 1) channelStrip(),
        const SizedBox(height: 8),
        if (hasPeq && (readFailed || outOfRange))
          SizedBox(
            height: fir == null ? height : null,
            child: Center(
              child: Text(
                readFailed
                    ? 'Preset unavailable'
                    : 'This curve includes a filter at or above ${graphRateLabel(rate ~/ 2)} for the ${graphRateLabel(rate)} preview.',
              ),
            ),
          ),
        if (showPeq || fir != null)
          ResponseGraph(
            key: ValueKey(channel),
            bands: showPeq ? plotted : const [],
            showPeq: showPeq,
            rate: rate,
            fir: traces,
            responseColor: responseColor,
            selected: selected,
            height: height,
            onSelect: selectBand,
            onMove: writable('dsp.profile')
                ? (i, band) => edit([...bands]..[i] = band, i)
                : null,
            onAdd: showPeq && writable('dsp.profile') && bands.length < 20
                ? (b) => addBand(b, reveal: false)
                : null,
          ),
        if (showPeq || fir != null)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 4,
            spacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (showPeq)
                    _TraceLabel(
                      color: responseColor,
                      label: bypassed
                          ? 'PEQ (bypassed)'
                          : peqOff
                          ? 'PEQ (off)'
                          : 'PEQ',
                    ),
                  for (final trace in traces)
                    _TraceLabel(
                      color: trace.color,
                      label: trace.label,
                      dash: trace.dash,
                    ),
                  if (showPeq && bands.length > 1)
                    _TraceLabel(
                      color: KalinkaColors.textMuted,
                      label: 'Band ${selected + 1}',
                    ),
                ],
              ),
              Text(
                fir == null ? 'dB / Hz' : 'Preview · ${graphRateLabel(rate)}',
                style: KalinkaTextStyles.trayRowSublabel,
              ),
            ],
          ),
      ],
    );
  }

  Widget inspector({required bool vertical}) => KeyedSubtree(
    key: inspectorKey,
    child: FilterInspector(
      key: ValueKey((channel, selected)),
      preview: sliderPreview,
      vertical: vertical,
      onPreview: (value) => setState(() => sliderPreview = value),
      band: bands[selected],
      number: selected + 1,
      editable: writable('dsp.profile'),
      onChange: changeBand,
      onRemove: () =>
          edit([...bands]..removeAt(selected), math.max(0, selected - 1)),
    ),
  );

  Widget channelStrip() => curve.channels.length == 1
      ? const SizedBox.shrink()
      : Wrap(
          spacing: 8,
          children: [
            for (final ch in curve.channels.keys)
              ChoiceChip(
                label: Text(
                  ch == EqChannel.left ? 'Left channel' : 'Right channel',
                ),
                selected: ch == channel,
                onSelected: (_) => setState(() {
                  channel = ch;
                  sliderPreview = null;
                  selected = 0;
                }),
              ),
          ],
        );

  Widget presetCard(RendererSettingsState s) {
    final opts = s.options['dsp.profile'] ?? [];
    final preset =
        opts.where((o) => o.value == presetId).firstOrNull?.label ??
        (presetId == 'none' ? 'None' : curve.name);
    final editable = writable('dsp.profile');
    return EqCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Semantics(
            button: true,
            child: InkWell(
              onTap: editable && opts.isNotEmpty ? choosePreset : null,
              borderRadius: BorderRadius.circular(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: EqCard.title('EQ preset')),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                    ],
                  ),
                  Text(
                    preset,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: KalinkaTextStyles.textFieldInput,
                  ),
                ],
              ),
            ),
          ),
          if (editable) ...[
            KalinkaButton(
              label: 'Save preset',
              fullWidth: true,
              enabled: hasActiveBand && !busy && !s.saving,
              onTap: () => publish(importing: false),
            ),
            KalinkaButton(
              label: 'Import REW',
              fullWidth: true,
              variant: KalinkaButtonVariant.neutral,
              enabled: !busy && !s.saving,
              onTap: () => publish(importing: true),
            ),
          ],
        ],
      ),
    );
  }

  Widget workspace(RendererSettingsState s, BoxConstraints box) {
    final fir = s.expertFields
        .where((f) => f.path == RoomEqScreen.firPath)
        .firstOrNull;
    final firControl = fir == null
        ? null
        : EqCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SchemaFieldRenderer(
                  field: fir,
                  contentPadding: EdgeInsets.zero,
                ),
                if (s.supportsFirImport && !fir.readonly) ...[
                  const SizedBox(height: 8),
                  KalinkaButton(
                    label: 'Import impulse WAV',
                    leading: const Icon(Icons.file_upload_outlined, size: 18),
                    variant: KalinkaButtonVariant.neutral,
                    fullWidth: true,
                    onTap: busy ? null : importImpulse,
                  ),
                ],
              ],
            ),
          );
    if (!s.values.containsKey('dsp.profile')) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (s.firResponse != null)
            EqCard(
              child: graph(plotted: const [], height: 186, settings: s),
            ),
          if (firControl != null) _section(RoomEqSection.fir, firControl),
        ],
      );
    }
    final scale = math.max(
      1.0,
      MediaQuery.textScalerOf(context).scale(16) / 16,
    );
    final wide = box.maxWidth >= 760 * scale;
    final gutter = wide ? 16.0 : 12.0;
    final hasPreamp =
        s.values.containsKey('dsp.preamp') ||
        s.values.containsKey('dsp.preamp_db');
    final hasSwitch = s.values.containsKey('dsp.enabled');
    final editable = writable('dsp.profile');
    final plotted = sliderPreview == null
        ? bands
        : ([...bands]..[selected] = sliderPreview!);
    final graphHeight = wide
        ? (box.maxHeight * .36).clamp(216.0, 352.0)
        : 186.0;
    // Leave room for the graph header, bands and parameter editor at this text size.
    final compactBands = !wide || box.maxHeight - graphHeight < 470 * scale;
    final plot = EqCard(
      child: graph(
        plotted: plotted,
        height: graphHeight,
        settings: s,
        toggle: hasSwitch
            ? settingSwitch(s, 'Enable PEQ', 'dsp.enabled')
            : null,
      ),
    );
    final processing = [
      if (hasPreamp)
        _section(RoomEqSection.preamp, EqCard(child: preampControls(s))),
      if (firControl != null) _section(RoomEqSection.fir, firControl),
      presetCard(s),
    ];
    final main = SingleChildScrollView(
      key: const PageStorageKey('eq-workspace'),
      padding: EdgeInsets.all(gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          _section(readFailed || !editable ? RoomEqSection.bands : null, plot),
          if (!readFailed)
            _section(
              editable ? RoomEqSection.bands : null,
              EqCard(
                child: EqBandList(
                  key: ValueKey(channel),
                  bands: plotted,
                  selected: selected,
                  compact: compactBands,
                  onSelect: selectBand,
                  addButton: editable ? addBandButton() : null,
                ),
              ),
            ),
          if (!readFailed && bands.isNotEmpty)
            EqCard(child: inspector(vertical: !wide)),
          if (!wide) ...processing,
        ],
      ),
    );
    return AbsorbPointer(
      absorbing: busy,
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: main),
                SizedBox(
                  width: (box.maxWidth * .26).clamp(210 * scale, 340 * scale),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(0, gutter, gutter, gutter),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: processing,
                    ),
                  ),
                ),
              ],
            )
          : main,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(rendererSettingsProvider(widget.rendererId));
    if (s.matchesFirRates && s.values[RoomEqScreen.firPath] != 'off') {
      ref.listen(
        playQueueStateStoreProvider.select((queue) {
          if (queue.currentRendererId != widget.rendererId) return null;
          final output = queue.playbackState.audioInfo?.output;
          if (output == null ||
              output.channels != 2 ||
              output.sampleFormat.startsWith('DSD') ||
              output.sampleFormat.startsWith('DoP')) {
            return null;
          }
          return output.sampleRate;
        }),
        (_, rate) {
          if (rate != null &&
              rate > 0 &&
              rate != settings.firResponse?.sampleRate) {
            ref
                .read(rendererSettingsProvider(widget.rendererId).notifier)
                .load(keepStaged: true);
          }
        },
      );
    }
    final available =
        s.values.containsKey('dsp.profile') ||
        s.values.containsKey(RoomEqScreen.firPath);
    final message = error ?? s.error;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: KalinkaColors.textPrimary,
            side: const BorderSide(color: KalinkaColors.borderDefault),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: KalinkaColors.textPrimary,
          ),
        ),
        chipTheme: theme.chipTheme.copyWith(
          color: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? KalinkaColors.surfaceElevated
                : KalinkaColors.surfaceInput,
          ),
          side: WidgetStateBorderSide.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.selected)
                  ? KalinkaColors.textPrimary
                  : KalinkaColors.borderDefault,
            ),
          ),
          labelStyle: KalinkaTextStyles.filterPillInactive,
          secondaryLabelStyle: KalinkaTextStyles.filterPillActive.copyWith(
            color: KalinkaColors.textPrimary,
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: KalinkaColors.background,
        body: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                fit: StackFit.passthrough,
                children: [
                  SettingsTopBar(
                    title: 'Room EQ',
                    entryFocus: KeyboardEntryFocus.scope,
                    action: s.values.containsKey('dsp.bypass')
                        ? Tooltip(
                            message: 'Bypass FIR, parametric EQ and preamp',
                            excludeFromSemantics: true,
                            child: settingSwitch(s, 'Bypass DSP', 'dsp.bypass'),
                          )
                        : null,
                  ),
                  if (busy || s.saving)
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 1,
                      child: LinearProgressIndicator(
                        minHeight: 1,
                        color: KalinkaColors.accent,
                        backgroundColor: Colors.transparent,
                        semanticsLabel: 'Updating Room EQ',
                      ),
                    ),
                ],
              ),
              const ConnectionBanner(),
              if (message != null && available)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          message,
                          style: const TextStyle(
                            color: KalinkaColors.statusPendingLight,
                          ),
                        ),
                      ),
                      if (dirty && !readFailed)
                        TextButton(
                          onPressed: busy ? null : applyEdit,
                          child: const Text('Retry'),
                        ),
                      if (readFailed)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => run(() => readPreset(presetId)),
                          child: const Text('Retry'),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: !available
                    ? Center(
                        child: Text(
                          s.error ??
                              (busy
                                  ? 'Loading renderer…'
                                  : 'Room EQ is unavailable on this output.'),
                        ),
                      )
                    : AbsorbPointer(
                        absorbing: s.saving,
                        child: LayoutBuilder(
                          builder: (context, box) => workspace(s, box),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TraceLabel extends StatelessWidget {
  const _TraceLabel({required this.color, required this.label, this.dash});
  final double? dash;
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (dash == null)
        Container(color: color, height: 2, width: 14)
      else
        Row(
          spacing: 3,
          children: [
            for (var i = 0; i < 2; i++)
              Container(color: color, height: 2, width: dash),
          ],
        ),
      const SizedBox(width: 6),
      Text(
        label,
        style: KalinkaFonts.sans(
          fontSize: 12,
          color: KalinkaColors.textSecondary,
        ),
      ),
    ],
  );
}
