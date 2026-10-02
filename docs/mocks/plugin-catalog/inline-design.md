# Expandable plugin catalog design

**Chosen design.** Use one Plugins destination with inline expansion. This respects Kalinka’s two-level navigation limit while keeping source plugins distinct from amplifier and AVR controls. The default prototype now opens this design. The original detail-page mock is superseded and retained only as a historical comparison; it is not the implementation target.

Open [the chosen prototype](http://127.0.0.1:8767/docs/mocks/plugin-catalog/#catalog), then choose **Device control** to inspect MusicCast. The [preview index](README.md#chosen-design) includes tablet and phone captures. This is a local HTML mock, not an implemented Flutter feature or hardware compatibility database.

## One destination with two plugin families

The entry point stays **server chip → Plugins**. On tablet, the catalog occupies the left pane and preserves the queue on the right. Browse, Installed and Updates are local views of this destination, not pushes onto the navigation stack.

Within Browse and Installed, use **All**, **Input sources** and **Device control** filter chips. Default Browse to Input sources; remember the user’s last choice in production. These are filters, not another row of navigation tabs. Material’s chip guidance describes filter chips as category-based content filters. [Material Web chips](https://material-web.dev/components/chip/)

| Dimension | What it answers | Presentation |
| --- | --- | --- |
| Input sources or Device control | What does this plugin add? | Prominent type filters; separate sections when All is selected |
| Official or Unofficial | Who maintains it? | Sections within the selected type; publisher information when expanded |
| Stable or Experimental | How ready is it? | Maturity label; Experimental section with publisher still explicit |
| Independent, included or manual | Who updates it? | Installed-state label and ownership sections in Installed |

Input sources add services or libraries independently of the amplifier brand. They still have server, account, network and format requirements; “any amplifier” must not become a blanket compatibility guarantee. Device control is optional and adds controls for a particular hi-fi system, not another way to supply music. Each catalog entry has one required `type`, matching the current SDK: `input_module` or `output_device`. Supporting a dual-type entry would require an explicit SDK/catalog change rather than ambiguous category tags.

The curated catalog copies the plugin's existing `PLUGIN_TYPE.value`; the UI displays those values as Input sources and Device control. Before installation, this declaration enables filtering without executing code. After installation, Kalinka's existing detection is authoritative, including for unregistered plugins. Keep catalog-declared and detected types separate in the inventory; report a mismatch for catalog correction without reinterpreting the plugin or moving its settings. An import failure makes detection unknown, not a third plugin type. `categories` remains descriptive search metadata, never a type fallback.

The expanded MusicCast entry shows controls supported by the checked-out implementation: volume read/set, power on/standby and power readiness. Configured input switching is described separately from an arbitrary input selector. Mute is not exposed. Power readiness includes whether Kalinka’s configured input is selected, so it is not simply a raw hardware power bit. These claims come from `KalinkaPlayer/packages/kalinka-plugin-musiccast/src/kalinka_plugin_musiccast/musiccast.py`, especially `supported_functions`, `_set_input` and `is_power_on`, and its `config_model.py`.

Marantz is a **proposed** entry with installation disabled. No real models, transport guarantees, capabilities or releases are invented. The original mock’s synthetic scrobbling and processing plugins are omitted from the chosen design rather than misclassified as input sources or device controls.

## Expansion without deeper navigation

Tap the row or downward chevron to expand it. Show the creator, release, server platforms, requirements, short release notes and relevant action in place. Keep blocking requirements visible; no nested accordion for essential information. Opening another row closes the previous one. The expanded header remains visible while scrolling within that entry, so its identity and collapse control do not disappear.

Material’s original expansion-panel guidance describes summary content expanding in place; this is legacy guidance, not a claim that M3 has a separately named accordion component. Current Material Components documentation explicitly covers expandable list-item semantics. [Material expansion panels](https://m1.material.io/components/expansion-panels.html), [Material Components lists](https://github.com/material-components/material-components-android/blob/master/docs/components/List.md#expandable-list-items)

One open row is our choice to bound scroll growth, not a Material requirement. Flutter provides this behavior through `ExpansionPanelList.radio`; controlled expansion tiles could also share a single expanded plugin ID. [Flutter radio expansion list](https://api.flutter.dev/flutter/material/ExpansionPanelList/ExpansionPanelList.radio.html)

Expansion retains scroll context and keyboard focus without changing the route. Update checkboxes select packages; the adjacent row independently expands release details. Install/update opens one short restart confirmation. After approval, persistent inline status reports waiting, reconnecting, completion or rollback across the local views. Collapsing an entry does not cancel installation. A transport disconnect is not an installation failure.

A confirmation is a transient decision, not another app destination. This assumes the navigation limit permits modal decisions. If it forbids overlays too, the restart choices can replace the action area inside the same expanded row. Avoid a details sheet opening another confirmation sheet. Legacy Material dialog guidance explicitly favors inline expansion for nonessential interruptions and discourages dialog stacking. [Material dialogs](https://m1.material.io/components/dialogs.html#dialogs-behavior)

## Hardware support is a separate question

Every device plugin needs three distinct answers: **Can the server run it? What controls can it provide? Will those controls work with my model?** A green server-compatibility result answers only the first.

An expanded device entry contains:

1. Brand and protocol/connection: network API or serial connection, with model-specific restrictions. REST and RS-232 describe interfaces, not universal device compatibility.
2. Explicit capability labels: volume read and write separately, mute, power status, power on, standby and input selection. Distinguish implemented, conditional and unsupported controls; don’t present a checklist of aspirations as support.
3. A supported-model search with aliases and model/firmware/zone coverage. Keep this inside the entry. Large result sets need bounded results and “Load more,” not another scrolling panel.
4. A read-only check of the selected device, when the installed plugin can safely provide it. Show the connection result separately from catalog verification. Never test support by changing volume, input or power.

Use model coverage states **Verified**, **Reported**, **Protocol match only**, **Unsupported**, and **Unknown**. Include the tested plugin version and firmware; conditional support should enumerate the missing controls. No match means “not verified,” not “unsupported.” An offline device is “not checked,” not “incompatible.” A brand match alone proves nothing.

The mock shows honest unknown coverage because the local catalog has no verified model matrix. Model search and the connection check are simulated. A responding API can suggest capabilities but cannot establish that every action has been tested. An uninstalled plugin cannot run discovery code just to decorate its catalog entry; use catalog records until installation, unless an existing trusted server probe is available.

The catalog schema now requires `type: "input_module"` or `type: "output_device"`; category tags do not determine these families. Output devices also require `device_support.models`, `device_support.families` and `device_support.notes`. At least one model or family must be named, with manufacturer-qualified labels and readable prerequisites/limitations. Index the names for discovery and show them directly inside the expanded entry. Empty exact-model coverage is acceptable when the supported family is known; do not invent model names to fill a list.

The remaining proposed extension is versioned device-support records containing manufacturer, exact model identifiers and aliases, firmware/zone scope, transport/protocol, capability status and conditions, verification level, date and evidence. The server should return hardware-match results separately from installation eligibility. An update that removes a required control or model must be flagged and excluded from unattended application until reviewed. The current basic model/family lists are not a verified per-release compatibility matrix.

## Alternatives and limits

| Option | Where it works | Trade-off here |
| --- | --- | --- |
| Expandable rows | Short evaluation and install/update decisions | Chosen; model matrices can make a row long |
| Details bottom sheet | Occasional quick preview | Obscures the catalog and risks stacked decisions; not the default |
| Permanent list and inspector | Wide management workspace | Would squeeze or replace the existing tablet queue |
| Full detail page | Long documentation and complex setup | Clear structure, but exceeds the stated navigation depth |

Do not turn each expansion into a complete setup wizard. Keep extended documentation and the full support database as explicitly external author links. Simple enable/settings decisions can use a single dialog. Complex device setup should reuse Server settings as a **peer** destination, preserving a return location instead of pushing a third-level page. Serial port selection, connection credentials and multi-zone mapping deserve that space.

The accordion is therefore a good fit for browsing, but not a universal substitute for navigation. Test it with long descriptions, large text, small phones and realistic model data before committing to it. If the decision-critical content routinely occupies several screens, a wider management workspace is preferable to progressively nesting more controls.

## Accessibility and implementation notes

Use a full-row expansion target, an announced expanded/collapsed state, visible keyboard focus and separate controls for install and batch selection. Restore focus after dialogs. New touch controls target at least 48 logical pixels; Google’s accessibility guidance relates this to Material’s 48 dp recommendation. [Android touch target guidance](https://support.google.com/accessibility/android/answer/7101858?hl=en)

In Flutter, keep `expandedPluginId`, type filter, search and per-view scroll position in the Plugins presentation state, while operation IDs and hardware results belong to server-scoped providers. Do not use `Navigator.push` for expansion, model lookup or progress. Preserve filters and scroll on return; system Back dismisses a dialog first and otherwise leaves Plugins. The mock also supports Escape to collapse the open row as a keyboard convenience. Honor reduced motion and text scaling, and announce compatibility and completion in words rather than color alone.

This prototype demonstrates interaction and layout, not screen-reader certification, real discovery, installation, persistent preferences or a complete configuration editor. Verify those in the Flutter implementation.
