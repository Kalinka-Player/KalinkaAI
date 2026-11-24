import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/field_decoration.dart';
import '../kalinka_button.dart';
import '../kalinka_dialog.dart';
import '../keyboard/app_keyboard_navigation.dart';
import '../tap_highlight.dart';

Future<String?> editEqValue(
  BuildContext context, {
  required String title,
  required String label,
  required String initial,
  required String? Function(String) validate,
  String action = 'Set',
  IconData? icon,
  String hint = '',
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
    icon: icon,
    hint: hint,
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
  final String title, label, initial, action, hint;
  final IconData? icon;
  final String? message;
  final bool numeric;
  final String? Function(String) validate;
  const _ValueDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.action,
    required this.icon,
    required this.hint,
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
  bool edited = false;
  String? get error => widget.validate(controller.text.trim());

  void accept() {
    if (error != null) {
      setState(() => edited = true);
      return;
    }
    Navigator.pop(context, controller.text.trim());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KalinkaDialog(
    side: KalinkaDialogSide.browsing,
    icon: widget.icon,
    iconGlyphColor: KalinkaColors.accentTint,
    iconBeside: widget.icon != null,
    title: widget.title,
    message: widget.message,
    content: MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.label, style: KalinkaTextStyles.trayRowLabel),
          const SizedBox(height: 8),
          AppKeyboardTextEntry(
            child: TextField(
              autofocus: true,
              controller: controller,
              keyboardType: widget.numeric
                  ? const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    )
                  : TextInputType.text,
              textInputAction: TextInputAction.done,
              style: kalinkaFieldText(),
              decoration: kalinkaFieldDecoration(hint: widget.hint)
                  .copyWith(errorText: edited ? error : null, errorMaxLines: 3),
              onChanged: (_) => setState(() => edited = true),
              onSubmitted: (_) => accept(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      KalinkaButton(
        label: 'Cancel',
        fullWidth: true,
        variant: KalinkaButtonVariant.neutral,
        onTap: () => Navigator.pop(context),
      ),
      KalinkaButton(
        label: widget.action,
        enabled: error == null,
        fullWidth: true,
        onTap: accept,
      ),
    ],
  );
}

Future<Map<String, String>?> chooseRewPreset(
  BuildContext context,
  String rendererName,
) => showKalinkaDialog<Map<String, String>>(
  context: context,
  builder: (_) => _RewImportDialog(rendererName: rendererName),
);

class _RewImportDialog extends StatefulWidget {
  final String rendererName;
  const _RewImportDialog({required this.rendererName});

  @override
  State<_RewImportDialog> createState() => _RewImportDialogState();
}

class _RewImportDialogState extends State<_RewImportDialog> {
  static const maxCharacters = 65536;
  final name = TextEditingController();
  final files = <String, ({String name, String text})>{};
  final fileErrors = <String, String>{};
  bool separate = false;
  bool picking = false;
  bool nameEdited = false;

  List<String> get channels =>
      separate ? const ['left', 'right'] : const ['shared'];
  String? get nameError => validatePresetName(name.text);
  bool get canImport =>
      !picking && nameError == null && channels.every(files.containsKey);

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void suggestName() {
    if (nameEdited) return;
    final first = channels
        .map((channel) => files[channel])
        .nonNulls
        .firstOrNull;
    name.text =
        first?.name.replaceFirst(RegExp(r'\.txt$', caseSensitive: false), '') ??
        '';
  }

  Future<void> pick(String channel) async {
    if (picking) return;
    setState(() => picking = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'REW text',
            extensions: ['txt'],
            mimeTypes: ['text/plain'],
            uniformTypeIdentifiers: ['public.plain-text'],
          ),
        ],
      );
      if (!mounted || file == null) return;
      const tooLong = 'Choose an export with up to 65,536 characters.';
      if (await file.length() > maxCharacters * 4) {
        throw const FormatException(tooLong);
      }
      final bytes = await file.readAsBytes();
      final String content;
      try {
        content = utf8.decode(bytes);
      } on FormatException {
        throw const FormatException('Choose a UTF-8 text export from REW.');
      }
      if (content.runes.length > maxCharacters) {
        throw const FormatException(tooLong);
      }
      if (content.trim().isEmpty) {
        throw const FormatException(
          'This file is empty. Choose a REW text export.',
        );
      }
      if (!mounted) return;
      setState(() {
        files[channel] = (name: file.name, text: content);
        fileErrors.remove(channel);
        suggestName();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          files.remove(channel);
          fileErrors[channel] = e is FormatException
              ? e.message
              : 'Couldn’t open the file. Choose it again.';
          suggestName();
        });
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  void accept() {
    if (!canImport) return;
    Navigator.pop(context, {
      'name': name.text.trim(),
      for (final channel in channels) channel: files[channel]!.text,
    });
  }

  Widget fileRow(String channel) {
    final label = switch (channel) {
      'left' => 'Left channel',
      'right' => 'Right channel',
      _ => 'Both channels',
    };
    final filename = files[channel]?.name;
    final error = fileErrors[channel];
    final radius = BorderRadius.circular(12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          enabled: !picking,
          label: filename == null
              ? '$label, choose file'
              : '$label, $filename, choose a replacement',
          child: TapHighlight(
            focusable: true,
            borderRadius: radius,
            onTap: picking ? null : () => pick(channel),
            child: ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: KalinkaColors.surfaceElevated,
                  borderRadius: radius,
                  border: Border.all(
                    color: error == null
                        ? KalinkaColors.borderDefault
                        : KalinkaColors.statusError,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: KalinkaTextStyles.trayRowSublabel),
                          const SizedBox(height: 3),
                          Text(
                            filename ?? 'Choose file…',
                            style: KalinkaTextStyles.trayRowLabel,
                            maxLines: filename == null ? null : 2,
                            overflow: filename == null
                                ? null
                                : TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.folder_open_outlined,
                      size: 20,
                      color: KalinkaColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: KalinkaTextStyles.trayRowSublabel.copyWith(
                  color: KalinkaColors.statusError,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => KalinkaDialog(
    side: KalinkaDialogSide.player,
    iconBeside: true,
    title: 'Import REW preset',
    message: 'Choose a Generic EQ text export (.txt) from Room EQ Wizard.',
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Separate channel files',
              style: KalinkaTextStyles.trayRowLabel,
            ),
            value: separate,
            onChanged: picking
                ? null
                : (value) => setState(() {
                    separate = value;
                    suggestName();
                  }),
          ),
        ),
        const SizedBox(height: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [for (final channel in channels) fileRow(channel)],
        ),
        const SizedBox(height: 20),
        Text('Preset name', style: KalinkaTextStyles.trayRowLabel),
        const SizedBox(height: 8),
        Semantics(
          label: 'Preset name',
          child: AppKeyboardTextEntry(
            child: TextField(
              controller: name,
              textInputAction: TextInputAction.done,
              style: kalinkaFieldText(),
              decoration: kalinkaFieldDecoration(hint: 'Name this preset')
                  .copyWith(
                    errorText: nameEdited || channels.any(files.containsKey)
                        ? nameError
                        : null,
                    errorMaxLines: 3,
                  ),
              onChanged: (_) => setState(() => nameEdited = true),
              onSubmitted: (_) => accept(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Import selects this preset on ${widget.rendererName}.',
          style: KalinkaTextStyles.trayRowSublabel,
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
        enabled: canImport,
        fullWidth: true,
        onTap: accept,
      ),
    ],
  );
}
