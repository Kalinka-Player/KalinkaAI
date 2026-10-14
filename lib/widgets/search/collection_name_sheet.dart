import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/collections_provider.dart';
import '../../providers/kalinka_player_api_provider.dart';
import '../../providers/toast_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/field_decoration.dart';
import '../kalinka_bottom_sheet.dart';
import '../kalinka_button.dart';

/// Asks for a name and makes the collection, reporting through the shared
/// toast. Returns the new collection's browse id, or null if it was dismissed
/// or the server refused.
///
/// Whatever showed the collections refetches on its own: the write bumps
/// [collectionsRevisionProvider] rather than handing a row back to a caller
/// that would then have to place it.
Future<String?> showNewCollectionSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final made = await createCollectionByName(context, ref);
  if (made == null) return null;
  ref.read(toastProvider.notifier).show('${made.name} created');
  return made.id;
}

/// Asks for a name and makes the collection, answering with it. Says nothing
/// on success: a caller that goes on to do something with the new collection
/// reports both at once rather than raising two toasts in a row. A refusal is
/// reported here, since it ends the flow either way.
Future<({String id, String name})?> createCollectionByName(
  BuildContext context,
  WidgetRef ref,
) async {
  final name = await _askForName(
    context,
    heading: 'NEW COLLECTION',
    note: 'Tracks from any source, in the order you choose.',
    action: 'CREATE',
  );
  if (name == null || !context.mounted) return null;

  final api = ref.read(kalinkaProxyProvider);
  try {
    final id = await api.createCollection(name);
    ref.read(collectionsRevisionProvider.notifier).bump();
    return (id: id, name: name);
  } catch (e) {
    ref
        .read(toastProvider.notifier)
        .show('Could not create the collection: $e', isError: true);
    return null;
  }
}

/// Asks what [item] should be called instead, and renames it. A name that
/// comes back unchanged writes nothing — a rename counts as a change, and
/// would move the collection to the front of a listing for nothing.
Future<void> showRenameCollectionSheet(
  BuildContext context,
  WidgetRef ref,
  BrowseItem item,
) async {
  final was = item.playlist?.name ?? item.name ?? '';
  final name = await _askForName(
    context,
    heading: 'RENAME COLLECTION',
    action: 'RENAME',
    initial: was,
  );
  if (name == null || name == was || !context.mounted) return;

  final api = ref.read(kalinkaProxyProvider);
  final toast = ref.read(toastProvider.notifier);
  try {
    await api.renameCollection(item.id, name);
    ref.read(collectionsRevisionProvider.notifier).bump();
    toast.show('Renamed to $name');
  } catch (e) {
    toast.show('Could not rename the collection: $e', isError: true);
  }
}

Future<String?> _askForName(
  BuildContext context, {
  required String heading,
  required String action,
  String note = '',
  String initial = '',
}) {
  return showKalinkaBottomSheet<String>(
    context: context,
    contentBuilder: (_) => _NameForm(
      heading: heading,
      action: action,
      note: note,
      initial: initial,
    ),
  );
}

/// The sheet body: one field and the two ways out. Pops the name it was given.
class _NameForm extends StatefulWidget {
  final String heading;
  final String action;
  final String note;
  final String initial;

  const _NameForm({
    required this.heading,
    required this.action,
    required this.note,
    required this.initial,
  });

  @override
  State<_NameForm> createState() => _NameFormState();
}

class _NameFormState extends State<_NameForm> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    // Typing replaces the name being changed rather than appending to it.
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
    // The action button follows what is typed.
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _name => _controller.text.trim();

  void _submit() {
    if (_name.isEmpty) return;
    Navigator.of(context).pop(_name);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Clears the keyboard the field itself raises.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.heading, style: KalinkaTextStyles.sectionLabel),
            if (widget.note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(widget.note, style: KalinkaTextStyles.trackRowSubtitle),
            ],
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              // The sheet exists to be typed into.
              autofocus: true,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 200,
              onSubmitted: (_) => _submit(),
              style: KalinkaTextStyles.cardTitle,
              decoration: kalinkaFieldDecoration(hint: 'Name it'),
            ),
            const SizedBox(height: 18),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 12,
              overflowSpacing: 12,
              children: [
                KalinkaButton(
                  label: 'CANCEL',
                  variant: KalinkaButtonVariant.neutral,
                  onTap: () => Navigator.of(context).pop(),
                ),
                KalinkaButton(
                  label: widget.action,
                  enabled: _name.isNotEmpty,
                  onTap: _submit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
