import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/box_control_provider.dart';
import '../providers/catalog_sources_provider.dart';
import '../providers/pinned_catalogs_provider.dart';
import '../providers/server_info_provider.dart';
import '../providers/shell_nav_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/browse_rows_shimmer.dart' show LoadingSpinner;
import '../widgets/configuration_appearance.dart';
import '../widgets/home/catalog_pin_button.dart';
import '../widgets/home/home_preview_switch.dart';
import '../widgets/kalinka_button.dart';
import '../widgets/kalinka_dialog.dart';
import '../widgets/search/catalog_cards_section.dart';
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
    // Nothing here can be changed until the server has said who it is.
    final pins =
        ref.watch(
          serverStorageKeyProvider.select((key) => key?.confirmed ?? false),
        )
        ? ref.watch(pinnedCatalogsProvider)
        : null;
    final noSources =
        pins != null &&
        pins.isEmpty &&
        ref.watch(catalogSourcesProvider).asData?.value.isEmpty == true;
    final notifier = ref.read(pinnedCatalogsProvider.notifier);
    // The background slides in with the panel; outside it, Home would go
    // black before the panel arrives.
    return SlideInPanel(
      onClose: widget.onClose,
      handlesBack: widget.handlesBack,
      beforeClose: _beforeClose,
      child: Scaffold(
        backgroundColor: KalinkaColors.background,
        body: ConfigurationAppearance(
          child: Builder(
            builder: (context) {
              // Under the appearance, which sets how wide the gutter is.
              final gutter = ConfigurationAppearance.gutter(context);
              return SafeArea(
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SettingsTopBar(title: 'Customise Home'),
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.only(bottom: 32),
                        header: switch (pins) {
                          null => const LoadingSpinner(),
                          [] => null,
                          _ => const _HomeLayoutIntro(),
                        },
                        footer: pins != null && pins.isEmpty
                            ? Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: gutter,
                                  vertical: 20,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Nothing pinned yet',
                                      style: KalinkaTextStyles.trayRowLabel,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      noSources
                                          ? 'Enable a music source in Configuration to start pinning catalogs.'
                                          : 'Choose a source below, browse to a catalog and use '
                                                '“Pin catalog to Home” to choose its preview.',
                                      style:
                                          KalinkaTextStyles.settingsDescription,
                                    ),
                                    const SizedBox(height: 24),
                                    Builder(
                                      builder: (panelContext) =>
                                          CatalogCardsSection(
                                            onSourceOpened: () =>
                                                SlideInPanel.closeOf(
                                                  panelContext,
                                                ),
                                          ),
                                    ),
                                    if (noSources &&
                                        ref.watch(pluginCatalogEnabledProvider))
                                      KalinkaButton(
                                        label: 'Configure music sources',
                                        variant: KalinkaButtonVariant.neutral,
                                        fullWidth: true,
                                        onTap: () => ref
                                            .read(
                                              musicSourcesSettingsRequestProvider
                                                  .notifier,
                                            )
                                            .open(),
                                      ),
                                  ],
                                ),
                              )
                            : null,
                        buildDefaultDragHandles: false,
                        itemCount: pins?.length ?? 0,
                        onReorderItem: (oldIndex, newIndex) => saveHomeChange(
                          context,
                          notifier.reorder(
                            oldIndex,
                            newIndex > oldIndex ? newIndex + 1 : newIndex,
                          ),
                        ),
                        itemBuilder: (_, index) {
                          final pin = pins![index];
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
                                                      color: KalinkaColors
                                                          .textMuted,
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
                                                style: KalinkaTextStyles
                                                    .trayRowLabel,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                [
                                                  if (pin
                                                      .description
                                                      .isNotEmpty)
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
              );
            },
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
  final server = ref.read(serverStorageKeyProvider);
  final confirmed = await showKalinkaDialog<bool>(
    context: context,
    builder: (dialogContext) => KalinkaDialog(
      side: KalinkaDialogSide.browsing,
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
  if (ref.read(serverStorageKeyProvider) != server) return;
  final pins = ref.read(pinnedCatalogsProvider);
  if (pins == null || !pins.any((item) => item.key == pin.key)) return;
  await saveHomeChange(
    context,
    ref.read(pinnedCatalogsProvider.notifier).unpin(pin.key),
  );
}
