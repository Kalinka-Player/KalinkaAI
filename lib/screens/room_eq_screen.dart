import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/presentation_schema.dart';
import '../data_model/room_eq.dart';
import '../providers/kalinka_player_api_provider.dart';
import '../providers/renderer_settings_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/connection_banner.dart';
import '../widgets/demo_read_only_dialog.dart';
import '../widgets/kalinka_button.dart';
import '../widgets/kalinka_dialog.dart';
import '../widgets/room_eq/editor_dialogs.dart';
import '../widgets/room_eq/filter_inspector.dart';
import '../widgets/room_eq/response_graph.dart';
import '../widgets/settings_top_bar.dart';

class RoomEqScreen extends ConsumerStatefulWidget {
  const RoomEqScreen({
    super.key,
    required this.rendererId,
    required this.rendererName,
  });
  final String rendererId, rendererName;
  static const fieldPaths = {
    'dsp.profile',
    'dsp.enabled',
    'dsp.bypass',
    'dsp.preamp',
    'dsp.preamp_db',
  };
  @override
  ConsumerState<RoomEqScreen> createState() => _RoomEqScreenState();
}

class _RoomEqScreenState extends ConsumerState<RoomEqScreen> {
  EqCurve curve = EqCurve.empty();
  EqChannel channel = EqChannel.shared;
  int selected = 0;
  bool preamp = false,
      graphPage = false,
      dirty = false,
      busy = true,
      readFailed = false;
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
      if (mounted) await run(() => readPreset(presetId));
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
    setState(() {
      curve = curve.withBands(channel, next);
      selected = index;
      dirty = true;
    });
  }

  void changeBand(EqBand value) =>
      edit([...bands]..[selected] = value, selected);

  Future<bool> discard() async {
    if (!dirty) return true;
    return await showKalinkaDialog<bool>(
          context: context,
          builder: (ctx) => KalinkaDialog(
            side: KalinkaDialogSide.player,
            title: 'Discard filter edits?',
            message:
                'Your changes to this curve haven’t been saved as a preset.',
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

  Future<void> back() async {
    if (busy) return;
    if (graphPage) {
      setState(() => graphPage = false);
      return;
    }
    if (await discard() && mounted) Navigator.pop(context);
  }

  Future<void> choosePreset() async {
    final options = settings.options['dsp.profile'] ?? [];
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: KalinkaColors.surfaceDialog,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: .65,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text('Room presets', style: KalinkaTextStyles.cardTitle),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final option in options)
                    ListTile(
                      title: Text(option.label),
                      leading: const Icon(Icons.graphic_eq_rounded),
                      trailing: option.value == presetId
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () => Navigator.pop(ctx, option.value.toString()),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
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

  Future<void> useFlatResponse() async {
    if (busy || await refusedAsDemo(context, ref) || !mounted) return;
    await selectPreset('none');
  }

  Future<void> publish({required bool importing}) async {
    if (busy || await refusedAsDemo(context, ref) || !mounted) return;
    final Map<String, String>? payload;
    if (importing) {
      if (!await discard() || !mounted) return;
      payload = await chooseRewPreset(context);
    } else {
      final title = await editEqValue(
        context,
        title: 'Save room preset',
        label: 'Preset name',
        initial: curve.name.isEmpty ? '' : '${curve.name} (edited)',
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

  Widget stages(RendererSettingsState s, {required bool wide}) {
    final enabled =
        s.values['dsp.enabled'] != false && s.values['dsp.bypass'] != true;
    final hasPreamp =
        s.values.containsKey('dsp.preamp') ||
        s.values.containsKey('dsp.preamp_db');
    final count = curve.channels.values.fold<int>(0, (v, c) => v + c.length);
    Widget stage(
      String name,
      String detail,
      IconData icon,
      bool isPreamp,
    ) => ListTile(
      dense: !wide,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      selected: preamp == isPreamp,
      selectedColor: KalinkaColors.textPrimary,
      selectedTileColor: KalinkaColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Icon(
        icon,
        color: preamp == isPreamp
            ? KalinkaColors.accentTint
            : KalinkaColors.textSecondary,
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(detail),
      trailing: Icon(
        preamp == isPreamp
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
        size: 16,
      ),
      onTap: () => setState(() => preamp = isPreamp),
    );
    final mode = s.values['dsp.preamp'];
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (s.values.containsKey('dsp.enabled') ||
              s.values.containsKey('dsp.bypass')) ...[
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('Room correction'),
              subtitle: Text(
                '${enabled ? "On" : "Off"} · ${widget.rendererName}',
              ),
              value: enabled,
              onChanged:
                  busy ||
                      !(writable('dsp.enabled') ||
                          writable('dsp.bypass') &&
                              s.values['dsp.enabled'] != false)
                  ? null
                  : (v) => changeSetting({
                      if (writable('dsp.enabled')) 'dsp.enabled': v.toString(),
                      if (writable('dsp.bypass') &&
                          (!writable('dsp.enabled') ||
                              v && s.values['dsp.bypass'] == true))
                        'dsp.bypass': (!v).toString(),
                    }),
            ),
            const Divider(height: 28),
          ],
          const _Label('Signal stages'),
          const SizedBox(height: 8),
          if (hasPreamp)
            stage(
              'Preamp',
              mode == 'auto'
                  ? 'Automatic headroom'
                  : '${s.values["dsp.preamp_db"] ?? 0} dB',
              Icons.linear_scale_rounded,
              true,
            ),
          stage(
            'Parametric EQ',
            readFailed
                ? 'Preset unavailable'
                : '$count ${count == 1 ? "band" : "bands"}',
            Icons.graphic_eq_rounded,
            false,
          ),
          if (!wide) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() => graphPage = true),
              icon: const Icon(Icons.show_chart_rounded),
              label: const Text('Open frequency response'),
            ),
          ],
        ],
      ),
    );
  }

  Widget preampControls(RendererSettingsState s) {
    final modes = s.options['dsp.preamp'] ?? <OptionSpec>[],
        mode = s.values['dsp.preamp'];
    final db = s.expertFields
        .where((f) => f.path == 'dsp.preamp_db')
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Preamp', style: KalinkaTextStyles.cardTitle),
        if (modes.isNotEmpty)
          Wrap(
            spacing: 8,
            children: [
              for (final option in modes)
                ChoiceChip(
                  label: Text(option.label),
                  selected: mode == option.value,
                  onSelected: writable('dsp.preamp')
                      ? (v) {
                          if (v) {
                            changeSetting({
                              'dsp.preamp': option.value.toString(),
                            });
                          }
                        }
                      : null,
                ),
            ],
          ),
        if (mode == 'auto')
          const Text(
            'The renderer reserves headroom for boosts in each channel.',
            style: TextStyle(color: KalinkaColors.textSecondary),
          ),
        if (db != null && (mode == 'manual' || mode == null))
          EqValueControl(
            label: db.label,
            unit: 'dB',
            value: double.tryParse('${s.values[db.path]}') ?? 0,
            min: db.constraints?.ge ?? -30,
            max: db.constraints?.le ?? 0,
            onChanged: writable(db.path)
                ? (v) => changeSetting({db.path: v.toString()})
                : null,
          ),
      ],
    );
  }

  Widget graph() {
    final outOfRange = bands.any((b) => b.hz >= 24000 && b.active);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              graphPage && curve.name.isNotEmpty
                  ? curve.name
                  : 'Filter response',
              style: KalinkaTextStyles.cardTitle,
            ),
            const Text(
              'dB  /  Hz     ·     48 kHz reference',
              style: TextStyle(
                fontSize: 12,
                color: KalinkaColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (outOfRange)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'This curve includes a filter at or above 24 kHz and cannot run at the 48 kHz reference rate.',
            ),
          )
        else
          ResponseGraph(
            bands: bands,
            selected: selected,
            onSelect: (i) => setState(() => selected = i),
            onMove: (b) {
              if (writable('dsp.profile')) changeBand(b);
            },
          ),
        if (!outOfRange && bands.length > 1)
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 14,
            runSpacing: 6,
            children: [
              _TraceLabel(color: KalinkaColors.accentBright, label: 'Combined'),
              _TraceLabel(
                color: KalinkaColors.textMuted,
                label: 'Band ${selected + 1}',
              ),
            ],
          ),
      ],
    );
  }

  Widget inspector() {
    if (readFailed) return const SizedBox.shrink();
    return FilterInspector(
      bands: bands,
      selected: selected,
      onSelect: (i) => setState(() => selected = i),
      editable: writable('dsp.profile'),
      onChange: changeBand,
      onAdd: (shape) => edit([...bands, EqBand(shape: shape)], bands.length),
      onRemove: () =>
          edit([...bands]..removeAt(selected), math.max(0, selected - 1)),
    );
  }

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
                  selected = 0;
                }),
              ),
          ],
        );

  Widget dock(RendererSettingsState s, {required bool wide}) {
    final opts = s.options['dsp.profile'] ?? [];
    final preset =
        opts.where((o) => o.value == presetId).firstOrNull?.label ??
        (presetId == 'none' ? 'None' : curve.name);
    final editable = writable('dsp.profile');
    final saveLabel = hasActiveBand ? 'Save preset' : 'Use flat EQ';
    final saveIcon = hasActiveBand
        ? Icons.save_outlined
        : Icons.horizontal_rule_rounded;
    final VoidCallback? saveAction = !editable
        ? null
        : hasActiveBand
        ? () => publish(importing: false)
        : opts.any((o) => o.value == 'none')
        ? useFlatResponse
        : null;
    return Material(
      color: KalinkaColors.surfaceBase,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: KalinkaColors.borderDefault)),
        ),
        padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 12, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: wide ? const Icon(Icons.library_music_outlined) : null,
                title: const _Label('Room preset'),
                subtitle: Text(
                  preset,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    color: KalinkaColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: const Icon(Icons.unfold_more_rounded, size: 18),
                onTap: editable && opts.isNotEmpty ? choosePreset : null,
              ),
            ),
            if (editable) ...[
              const SizedBox(width: 8),
              if (wide)
                OutlinedButton.icon(
                  onPressed: () => publish(importing: true),
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('Import REW'),
                )
              else
                IconButton(
                  tooltip: 'Import REW',
                  onPressed: () => publish(importing: true),
                  icon: const Icon(Icons.file_upload_outlined),
                ),
            ],
            if (dirty) ...[
              const SizedBox(width: 6),
              if (wide)
                FilledButton.icon(
                  onPressed: saveAction,
                  icon: Icon(saveIcon, size: 18),
                  label: Text(saveLabel),
                )
              else
                IconButton.filled(
                  tooltip: saveLabel,
                  onPressed: saveAction,
                  icon: Icon(saveIcon),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget panel(Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: KalinkaColors.surfaceRaised,
      border: Border.all(color: KalinkaColors.borderSubtle),
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );

  Widget workspace(RendererSettingsState s, BoxConstraints box) {
    final textSize = MediaQuery.textScalerOf(context).scale(16);
    final wide =
        box.maxWidth >= 600 &&
        MediaQuery.sizeOf(context).shortestSide >= 500 &&
        textSize <= 24;
    final pinned = box.maxHeight >= 420 && textSize <= 24;
    final graphOnly = graphPage && !wide;
    final controls = ListView(
      key: PageStorageKey(graphOnly ? 'eq-graph' : 'eq-controls'),
      padding: EdgeInsets.all(wide ? 24 : 12),
      children: [
        if (!wide && !graphOnly) panel(stages(s, wide: false)),
        if (!readFailed && curve.channels.length > 1) channelStrip(),
        if (!readFailed && (wide || graphOnly)) panel(graph()),
        if (preamp && !graphOnly)
          panel(preampControls(s))
        else if (!readFailed)
          panel(inspector()),
        if (dirty)
          Text(
            hasActiveBand
                ? 'Unsaved filter edits · Save a preset to hear this curve.'
                : 'All filters are flat. Use flat EQ to select the None preset.',
            style: const TextStyle(
              fontSize: 13,
              color: KalinkaColors.statusPendingLight,
            ),
          ),
        if (!pinned) dock(s, wide: wide),
      ].expand((w) => [w, const SizedBox(height: 12)]).toList(),
    );
    final body = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: box.maxWidth >= 950 ? 252 : 204,
                padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
                decoration: const BoxDecoration(
                  color: KalinkaColors.surfaceBase,
                  border: Border(
                    right: BorderSide(color: KalinkaColors.borderSubtle),
                  ),
                ),
                child: ListView(children: [stages(s, wide: true)]),
              ),
              Expanded(child: controls),
            ],
          )
        : controls;
    return AbsorbPointer(
      absorbing: busy,
      child: Column(
        children: [
          Expanded(child: body),
          if (pinned) dock(s, wide: wide),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(rendererSettingsProvider(widget.rendererId));
    final available = s.values.containsKey('dsp.profile');
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
            foregroundColor: KalinkaColors.accentTint,
          ),
        ),
        chipTheme: theme.chipTheme.copyWith(
          color: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? KalinkaColors.accentFaded
                : KalinkaColors.surfaceInput,
          ),
          side: WidgetStateBorderSide.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.selected)
                  ? KalinkaColors.accentBorder
                  : KalinkaColors.borderDefault,
            ),
          ),
          labelStyle: KalinkaTextStyles.filterPillInactive,
          secondaryLabelStyle: KalinkaTextStyles.filterPillActive.copyWith(
            color: KalinkaColors.accentTint,
          ),
        ),
      ),
      child: PopScope(
        canPop: !graphPage && !busy && !dirty,
        onPopInvokedWithResult: (p, _) {
          if (!p) back();
        },
        child: Scaffold(
          backgroundColor: KalinkaColors.background,
          body: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsTopBar(
                  title: graphPage ? 'Frequency response' : 'Room EQ',
                  onBack: back,
                ),
                const ConnectionBanner(),
                if (busy) const LinearProgressIndicator(minHeight: 2),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            error!,
                            style: const TextStyle(
                              color: KalinkaColors.statusPendingLight,
                            ),
                          ),
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
                      : LayoutBuilder(
                          builder: (context, box) => workspace(s, box),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.value);
  final String value;
  @override
  Widget build(BuildContext context) =>
      Text(value.toUpperCase(), style: KalinkaTextStyles.sectionHeaderMuted);
}

class _TraceLabel extends StatelessWidget {
  const _TraceLabel({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(color: color, height: 2, width: 14),
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
