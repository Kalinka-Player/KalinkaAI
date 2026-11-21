import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data_model/presentation_schema.dart' show OptionSpec;
import '../data_model/wifi_countries.dart';
import '../providers/box_control_provider.dart';
import '../theme/app_theme.dart';
import '../theme/field_decoration.dart';
import 'kalinka_bottom_sheet.dart';
import 'keyboard/app_keyboard_navigation.dart';
import 'settings_controls/option_picker.dart';
import 'settings_controls/settings_action_row.dart';

/// The first of [locales] whose country is a Wi-Fi region. flutter-pi lists a
/// bare `en` before `en_GB`, so the first locale alone may have none.
String? localeWifiCountry(Iterable<Locale> locales) {
  for (final locale in locales) {
    final country = locale.countryCode?.toUpperCase();
    if (wifiCountries.containsKey(country)) return country;
  }
  return null;
}

/// The Wi-Fi region last chosen in setup for the streamer [serverId].
String? savedWifiCountry(SharedPreferences prefs, String? serverId) {
  if (serverId == null || serverId.isEmpty) return null;
  final country = prefs.getString(
    ServerStorageKey.ofServer(serverId).wifiCountry,
  );
  return wifiCountries.containsKey(country) ? country : null;
}

void saveWifiCountry(
  SharedPreferences prefs,
  String? serverId,
  String country,
) {
  if (serverId == null || serverId.isEmpty) return;
  prefs
      .setString(ServerStorageKey.ofServer(serverId).wifiCountry, country)
      .ignore();
}

/// Selects the regulatory region used for Wi-Fi scanning and joining.
class WifiCountrySelector extends StatefulWidget {
  final String? country;
  final ValueChanged<String>? onChanged;

  const WifiCountrySelector({super.key, this.country, required this.onChanged});

  @override
  State<WifiCountrySelector> createState() => _WifiCountrySelectorState();
}

class _WifiCountrySelectorState extends State<WifiCountrySelector> {
  Future<void> _choose() async {
    final selected = widget.country;
    final country = await showKalinkaBottomSheet<String>(
      context: context,
      dialogMaxWidth: kKalinkaContentMaxWidth,
      mayFillScreen: true,
      contentBuilder: (_) => _CountryPicker(selected: selected),
    );
    if (mounted && country != null && country != widget.country) {
      widget.onChanged?.call(country);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = wifiCountries[widget.country];
    return SettingsActionRow(
      label: 'Wi-Fi region',
      sublabel: name == null ? 'Choose a country' : '$name (${widget.country})',
      onTap: widget.onChanged == null ? null : _choose,
    );
  }
}

class _CountryPicker extends StatefulWidget {
  final String? selected;
  const _CountryPicker({this.selected});

  @override
  State<_CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends State<_CountryPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final first = query.isEmpty ? widget.selected : query.toUpperCase();
    final options = [
      if (wifiCountries[first] case final name?)
        OptionSpec(value: first!, label: '$name ($first)'),
      for (final entry in wifiCountries.entries)
        if (entry.key != first &&
            (entry.value.toLowerCase().contains(query) ||
                entry.key.toLowerCase().contains(query)))
          OptionSpec(value: entry.key, label: '${entry.value} (${entry.key})'),
    ];
    return Shortcuts(
      shortcuts: directionalFocusShortcuts,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: AppKeyboardTextEntry(
                child: TextField(
                  key: const ValueKey('country-search'),
                  style: kalinkaFieldText(KalinkaTextStyles.textFieldInput),
                  decoration: kalinkaFieldDecoration(hint: 'Search countries'),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
            ),
            Flexible(
              child: OptionPicker(
                options: options,
                selectedValue: widget.selected,
                emptyMessage: 'No country matches “${_query.trim()}”.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
