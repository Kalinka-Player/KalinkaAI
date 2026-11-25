import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/presentation_schema.dart';
import '../data_model/renderer_config.dart';
import '../providers/renderer_settings_provider.dart';
import '../theme/app_theme.dart';
import '../theme/field_decoration.dart';
import 'demo_read_only_dialog.dart';
import 'failure_note.dart';
import 'kalinka_button.dart';
import 'kalinka_dialog.dart';
import 'keyboard/app_keyboard_navigation.dart';

class RendererNameDialog extends ConsumerStatefulWidget {
  final String rendererId;
  final FieldSpec field;

  const RendererNameDialog({
    super.key,
    required this.rendererId,
    required this.field,
  });

  @override
  ConsumerState<RendererNameDialog> createState() => _RendererNameDialogState();
}

class _RendererNameDialogState extends ConsumerState<RendererNameDialog> {
  late final TextEditingController _name;
  String? _error;

  @override
  void initState() {
    super.initState();
    final state = ref.read(rendererSettingsProvider(widget.rendererId));
    final name =
        (state.staged[widget.field.path] ??
                state.values[widget.field.path] ??
                '')
            .toString();
    _name = TextEditingController.fromValue(
      TextEditingValue(
        text: name,
        selection: TextSelection(baseOffset: 0, extentOffset: name.length),
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final provider = rendererSettingsProvider(widget.rendererId);
    final path = widget.field.path;
    final state = ref.read(provider);
    if (state.saving) return;
    final name = _name.text.trim();
    if (name == state.values[path] && !state.staged.containsKey(path)) return;
    if (name != state.values[path]) {
      if (await refusedAsDemo(context, ref) || !mounted) return;
      await ref.read(provider.notifier).save(immediate: {path: name});
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (ref.read(provider).error case final message?) {
        setState(() => _error = message);
        return;
      }
    }
    // A successful reset can resolve to the stored default. It also replaces
    // any draft for this same field that was left in the expert editor.
    ref.read(provider.notifier).stage(path, ref.read(provider).values[path]);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rendererSettingsProvider(widget.rendererId));
    final path = widget.field.path;
    final changed =
        _name.text.trim() != state.values[path] ||
        state.staged.containsKey(path);
    return KalinkaDialog(
      side: KalinkaDialogSide.browsing,
      icon: Icons.edit_outlined,
      iconGlyphColor: KalinkaColors.accentTint,
      iconBeside: true,
      title: 'Rename renderer',
      message: switch (state.applyCosts[path]) {
        RendererApplyCost.restartRequired =>
          'The new name takes effect when the renderer restarts.',
        RendererApplyCost.interruptsPlayback =>
          'Saving the name interrupts playback on this output.',
        _ => null,
      },
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Renderer name', style: KalinkaTextStyles.trayRowLabel),
                const SizedBox(height: 8),
                AppKeyboardTextEntry(
                  child: TextField(
                    controller: _name,
                    autofocus: true,
                    readOnly: state.saving,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    style: kalinkaFieldText(),
                    decoration: kalinkaFieldDecoration(
                      hint: widget.field.defaultValue?.toString() ?? '',
                    ),
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => _save(),
                  ),
                ),
              ],
            ),
          ),
          if (_error case final message?) ...[
            const SizedBox(height: 8),
            Semantics(liveRegion: true, child: FailureNote(message: message)),
          ],
          if (widget.field.help case final help?
              when help.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(help, style: KalinkaTextStyles.trayRowSublabel),
          ],
        ],
      ),
      actions: [
        KalinkaButton(
          label: 'Cancel',
          fullWidth: true,
          enabled: !state.saving,
          variant: KalinkaButtonVariant.neutral,
          onTap: () => Navigator.pop(context),
        ),
        KalinkaButton(
          label: state.saving ? 'Saving…' : 'Save',
          fullWidth: true,
          enabled: changed && !state.saving,
          onTap: _save,
        ),
      ],
    );
  }
}
