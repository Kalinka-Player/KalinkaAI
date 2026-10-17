import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/connection_settings_provider.dart';
import '../../providers/pinned_catalogs_provider.dart';
import '../../theme/app_theme.dart';
import '../tap_highlight.dart';
import 'catalog_pin_button.dart';
import 'home_preview_choices.dart';

/// An anchored icon bar; choices save immediately and restart its idle timer.
class HomePreviewSwitch extends ConsumerStatefulWidget {
  final PinnedCatalog pin;
  final ValueChanged<VoidCallback?> onMenuChanged;
  const HomePreviewSwitch({
    super.key,
    required this.pin,
    required this.onMenuChanged,
  });

  @override
  ConsumerState<HomePreviewSwitch> createState() => _HomePreviewSwitchState();
}

class _HomePreviewSwitchState extends ConsumerState<HomePreviewSwitch> {
  final _menu = MenuController();
  final _buttonFocus = FocusNode();
  Timer? _idle;
  Uri? _openedServer;

  void _resetIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 3), () {
      if (mounted && _menu.isOpen) _menu.close();
    });
  }

  void _opened() {
    _openedServer = ref.read(connectionSettingsProvider).baseUrl;
    widget.onMenuChanged(_menu.close);
    _resetIdle();
  }

  void _closed() {
    _idle?.cancel();
    widget.onMenuChanged(null);
  }

  @override
  void dispose() {
    _idle?.cancel();
    widget.onMenuChanged(null);
    _buttonFocus.dispose();
    super.dispose();
  }

  void _select(HomePreviewType type) {
    if (ref.read(connectionSettingsProvider).baseUrl != _openedServer) {
      _menu.close();
      return;
    }
    _resetIdle();
    saveHomeChange(
      context,
      ref
          .read(pinnedCatalogsProvider.notifier)
          .setPreview(widget.pin.key, type),
    );
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
    controller: _menu,
    childFocusNode: _buttonFocus,
    consumeOutsideTap: true,
    onOpen: _opened,
    onClose: _closed,
    style: MenuStyle(
      backgroundColor: const WidgetStatePropertyAll(
        KalinkaColors.surfaceRaised,
      ),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(12)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: KalinkaColors.borderDefault),
        ),
      ),
      alignment: AlignmentDirectional.bottomEnd,
    ),
    menuChildren: [
      Listener(
        onPointerDown: (_) => _resetIdle(),
        child: MouseRegion(
          onHover: (_) => _resetIdle(),
          child: Focus(
            onKeyEvent: (_, _) {
              _resetIdle();
              return KeyEventResult.ignored;
            },
            child: SizedBox(
              key: const ValueKey('home-preview-switch-menu'),
              width: 248,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      for (final type in HomePreviewType.values)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: IconButton(
                              tooltip: type.label,
                              isSelected: type == widget.pin.preview,
                              onPressed: () => _select(type),
                              style: kalinkaIconButtonStyle.copyWith(
                                backgroundColor: WidgetStatePropertyAll(
                                  type == widget.pin.preview
                                      ? KalinkaColors.accent
                                      : Colors.transparent,
                                ),
                                foregroundColor: const WidgetStatePropertyAll(
                                  KalinkaColors.textPrimary,
                                ),
                              ),
                              icon: Icon(homePreviewIcon(type), size: 22),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${widget.pin.preview.label}: ${widget.pin.preview.description}',
                    style: KalinkaTextStyles.trackRowSubtitle,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
    builder: (_, controller, _) => IconButton(
      focusNode: _buttonFocus,
      tooltip: 'Preview for ${widget.pin.page.title ?? 'Catalog'}',
      style: kalinkaIconButtonStyle,
      icon: Icon(homePreviewIcon(widget.pin.preview), size: 22),
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
    ),
  );
}
