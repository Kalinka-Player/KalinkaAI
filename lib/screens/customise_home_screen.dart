import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connection_settings_provider.dart';
import '../providers/pinned_catalogs_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/configuration_appearance.dart';
import '../widgets/home/catalog_pin_button.dart';
import '../widgets/home/home_preview_switch.dart';
import '../widgets/kalinka_button.dart';
import '../widgets/kalinka_dialog.dart';
import '../widgets/settings_top_bar.dart';
import '../widgets/slide_in_panel.dart';
import '../widgets/tap_highlight.dart';

/// Names and controls only: the preview content stays on Home.
class CustomiseHomeScreen extends ConsumerStatefulWidget {
  final VoidCallback? onClose;
  final bool handlesBack;
  const CustomiseHomeScreen({super.key, this.onClose, this.handlesBack = true});

  @override
  ConsumerState<CustomiseHomeScreen> createState() =>
      _CustomiseHomeScreenState();
}

class _CustomiseHomeScreenState extends ConsumerState<CustomiseHomeScreen> {
  String? _openMenuKey;
  VoidCallback? _closePreviewMenu;

  void _menuChanged(String key, VoidCallback? close) {
    if (close != null) {
      if (_openMenuKey != key) _closePreviewMenu?.call();
      _openMenuKey = key;
      _closePreviewMenu = close;
    } else if (_openMenuKey == key) {
      _openMenuKey = null;
      _closePreviewMenu = null;
    }
  }

  Future<bool> _beforeClose() async {
    final closeMenu = _closePreviewMenu;
    if (closeMenu == null) return true;
    closeMenu();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final pins = ref.watch(pinnedCatalogsProvider);
    final notifier = ref.read(pinnedCatalogsProvider.notifier);
    final gutter = ConfigurationAppearance.gutter(context);
    // The background slides in with the panel; outside it, Home would go
    // black before the panel arrives.
    return SlideInPanel(
      onClose: widget.onClose,
      handlesBack: widget.handlesBack,
      beforeClose: _beforeClose,
      child: Scaffold(
        backgroundColor: KalinkaColors.background,
        body: ConfigurationAppearance(
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SettingsTopBar(title: 'Customise Home'),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 32),
                    header: const _HomeLayoutIntro(),
                    footer: pins.isEmpty
                        ? Padding(
                            padding: EdgeInsets.symmetric(horizontal: gutter),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'No pinned catalogs yet',
                                  style: KalinkaTextStyles.trayRowLabel,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Open a source, browse to a catalog and pin it to Home.',
                                  style: KalinkaTextStyles.settingsDescription,
                                ),
                              ],
                            ),
                          )
                        : null,
                    buildDefaultDragHandles: false,
                    itemCount: pins.length,
                    onReorderItem: (oldIndex, newIndex) => saveHomeChange(
                      context,
                      notifier.reorder(
                        oldIndex,
                        newIndex > oldIndex ? newIndex + 1 : newIndex,
                      ),
                    ),
                    itemBuilder: (_, index) {
                      final pin = pins[index];
                      final title = pin.page.title ?? 'Catalog';
                      return Material(
                        key: ValueKey(pin.key),
                        color: KalinkaColors.background,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: gutter),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: Semantics(
                                        label: 'Reorder $title',
                                        child: Tooltip(
                                          message: 'Drag to reorder $title',
                                          child: const MouseRegion(
                                            cursor: SystemMouseCursors.grab,
                                            child: ColoredBox(
                                              color: Colors.transparent,
                                              child: SizedBox(
                                                width: 48,
                                                height: 48,
                                                child: Icon(
                                                  Icons.drag_indicator,
                                                  size: 22,
                                                  color:
                                                      KalinkaColors.textMuted,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            title,
                                            style:
                                                KalinkaTextStyles.trayRowLabel,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            [
                                              if (pin.description.isNotEmpty)
                                                pin.description,
                                              '${pin.preview.label} preview',
                                            ].join(' · '),
                                            style: KalinkaTextStyles
                                                .trayRowSublabel,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    HomePreviewSwitch(
                                      pin: pin,
                                      onMenuChanged: (close) =>
                                          _menuChanged(pin.key, close),
                                    ),
                                    IconButton(
                                      tooltip: 'Unpin $title',
                                      style: kalinkaIconButtonStyle,
                                      icon: const Icon(
                                        CupertinoIcons.pin_slash,
                                        size: 20,
                                      ),
                                      onPressed: () =>
                                          _confirmUnpin(context, ref, pin),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(
                                height: 1,
                                color: KalinkaColors.borderSubtle,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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

class _HomeLayoutIntro extends StatelessWidget {
  const _HomeLayoutIntro();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: EdgeInsets.symmetric(
          horizontal: ConfigurationAppearance.gutter(context),
          vertical: 20,
        ),
        child: Text(
          'Drag catalogs to reorder.\nSearch, collections and sources stay in place.',
          style: KalinkaTextStyles.settingsDescription,
        ),
      ),
      const Divider(
        key: ValueKey('customise-home-intro-divider'),
        height: 1,
        color: KalinkaColors.borderSubtle,
      ),
      const SizedBox(height: 8),
    ],
  );
}

Future<void> _confirmUnpin(
  BuildContext context,
  WidgetRef ref,
  PinnedCatalog pin,
) async {
  final server = ref.read(connectionSettingsProvider).baseUrl;
  final confirmed = await showKalinkaDialog<bool>(
    context: context,
    builder: (dialogContext) => KalinkaDialog(
      side: KalinkaDialogSide.right,
      centered: true,
      icon: CupertinoIcons.pin_slash,
      iconGlyphColor: KalinkaColors.accentTint,
      title: 'Unpin catalog?',
      message: 'Remove “${pin.page.title ?? 'Catalog'}” from Home?',
      actions: [
        KalinkaButton(
          label: 'Cancel',
          variant: KalinkaButtonVariant.neutral,
          fullWidth: true,
          onTap: () => Navigator.pop(dialogContext, false),
        ),
        KalinkaButton(
          label: 'Unpin',
          fullWidth: true,
          onTap: () => Navigator.pop(dialogContext, true),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  if (ref.read(connectionSettingsProvider).baseUrl != server) return;
  if (!ref.read(pinnedCatalogsProvider).any((item) => item.key == pin.key)) {
    return;
  }
  await saveHomeChange(
    context,
    ref.read(pinnedCatalogsProvider.notifier).unpin(pin.key),
  );
}
