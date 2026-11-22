import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../kalinka_button.dart';
import '../kalinka_dialog.dart';
import '../keyboard/app_keyboard_navigation.dart';

Future<String?> editEqValue(
  BuildContext context, {
  required String title,
  required String label,
  required String initial,
  required String? Function(String) validate,
  String action = 'Set',
  String? message,
  bool numeric = false,
}) => showKalinkaDialog<String>(
  context: context,
  builder: (_) => _ValueDialog(
    title: title,
    label: label,
    initial: initial,
    validate: validate,
    action: action,
    message: message,
    numeric: numeric,
  ),
);

String? validatePresetName(String value) {
  if (value.trim().isEmpty) return 'Enter a preset name.';
  if (utf8.encode(value.trim()).length > 120 ||
      value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    return 'Use a shorter, printable name (up to 120 UTF-8 bytes).';
  }
  return null;
}

class _ValueDialog extends StatefulWidget {
  final String title, label, initial, action;
  final String? message;
  final bool numeric;
  final String? Function(String) validate;
  const _ValueDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.action,
    required this.message,
    required this.numeric,
    required this.validate,
  });
  @override
  State<_ValueDialog> createState() => _ValueDialogState();
}

class _ValueDialogState extends State<_ValueDialog> {
  late final controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
  String? error;
  void accept() {
    final text = controller.text.trim(), problem = widget.validate(text);
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KalinkaDialog(
    side: KalinkaDialogSide.player,
    title: widget.title,
    message: widget.message,
    content: AppKeyboardTextEntry(
      child: TextField(
        autofocus: true,
        controller: controller,
        keyboardType: widget.numeric
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        decoration: InputDecoration(labelText: widget.label, errorText: error),
        onSubmitted: (_) => accept(),
      ),
    ),
    actions: [
      KalinkaButton(
        label: 'Cancel',
        fullWidth: true,
        variant: KalinkaButtonVariant.neutral,
        onTap: () => Navigator.pop(context),
      ),
      KalinkaButton(label: widget.action, fullWidth: true, onTap: accept),
    ],
  );
}

Future<Map<String, String>?> chooseRewPreset(BuildContext context) =>
    showKalinkaDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _RewImportDialog(),
    );

class _RewImportDialog extends StatefulWidget {
  const _RewImportDialog();
  @override
  State<_RewImportDialog> createState() => _RewImportDialogState();
}

class _RewImportDialogState extends State<_RewImportDialog> {
  final name = TextEditingController();
  final files = <String, XFile>{};
  bool stereo = false, busy = false;
  String? error;
  List<String> get channels => stereo ? ['left', 'right'] : ['shared'];
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> pick(String channel) async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'REW text',
            extensions: ['txt'],
            mimeTypes: ['text/plain'],
            uniformTypeIdentifiers: ['public.plain-text'],
          ),
        ],
      );
      if (!mounted || file == null) return;
      setState(() {
        files[channel] = file;
        if (name.text.isEmpty) {
          name.text = file.name.replaceFirst(
            RegExp(r'\.txt$', caseSensitive: false),
            '',
          );
        }
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = 'Couldn’t open that file: $e');
    }
  }

  Future<void> accept() async {
    final problem = validatePresetName(name.text);
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    setState(() => busy = true);
    try {
      final payload = {'name': name.text.trim()};
      for (final channel in channels) {
        final file = files[channel]!;
        if (await file.length() > 262144) {
          throw const FormatException(
            'Export up to 65,536 characters per channel.',
          );
        }
        payload[channel] = await file.readAsString(encoding: utf8);
      }
      if (mounted) Navigator.pop(context, payload);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Couldn’t read REW text: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => KalinkaDialog(
    side: KalinkaDialogSide.player,
    title: 'Import REW preset',
    message:
        'Choose filter settings exported as text with REW’s Generic equaliser.',
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Separate left and right files'),
            value: stereo,
            onChanged: busy ? null : (v) => setState(() => stereo = v),
          ),
        ),
        for (final channel in channels)
          OutlinedButton.icon(
            onPressed: busy ? null : () => pick(channel),
            icon: const Icon(Icons.upload_file_rounded),
            label: Text(
              files[channel]?.name ??
                  (stereo ? 'Choose $channel file' : 'Choose REW file'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const SizedBox(height: 12),
        AppKeyboardTextEntry(
          child: TextField(
            controller: name,
            enabled: !busy,
            decoration: const InputDecoration(labelText: 'Preset name'),
          ),
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
    actions: [
      KalinkaButton(
        label: 'Cancel',
        variant: KalinkaButtonVariant.neutral,
        fullWidth: true,
        onTap: () => Navigator.pop(context),
      ),
      KalinkaButton(
        label: 'Import',
        enabled: !busy && channels.every(files.containsKey),
        fullWidth: true,
        onTap: accept,
      ),
    ],
  );
}
