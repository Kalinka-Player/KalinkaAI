# Plugin catalog interaction mocks

Reviewable tablet and phone mocks for discovering, installing and updating Kalinka Player server plugins. The primary entry point is **server chip → Plugins**, directly below **Server settings** in the existing server sheet. As revised on 2026-10-02, the tablet app places Plugins and Settings over the right-hand queue, leaving Now Playing usable on the left. The original mock images and prototype retain the earlier left-pane placement for reference; they have not been removed. On phone the app uses a full-width overlay.

**Chosen design: Expand in place.** Plugin details, hardware lookup and operation progress stay inside the Plugins destination. This is the implementation target and the default mock. The separate detail-page flow is superseded and accessible only as an archived comparison.

This is an interactive HTML prototype, not a change to the Flutter app. It makes no API calls, downloads no plugins and never changes a server. All plugin availability, release versions, compatibility results and installation outcomes are illustrative. Internet Radio, Last.fm Scrobbler, ListenBrainz, Room Correction and Studio Bridge are design fixtures, not announcements of available plugins. The Qobuz release numbers are also fictional. Existing bundled-plugin names are included to illustrate package ownership.

## Open the prototype

From the KalinkaAI-1 repository root:

```sh
python3 -m http.server 8767 --bind 127.0.0.1
```

Open [the interactive prototype](http://127.0.0.1:8767/docs/mocks/plugin-catalog/#entry). Serve the repository root so the mock can load Kalinka Player’s bundled fonts and logo. Opening the HTML directly with a `file:` URL may prevent its JavaScript module from loading.

Use the review toolbar above the mock to jump between screens; **More states** exposes confirmations, restart, completion, rollback, incompatibility, manual installation and offline browsing. These controls are outside the proposed app UI. Each scenario starts with its own demo state. App controls preserve state while you walk through an interaction.

## Chosen design

**Expand in place** keeps plugin details, model lookup and operation progress within the Plugins destination. Open [the chosen prototype](http://127.0.0.1:8767/docs/mocks/plugin-catalog/#catalog). [Design rationale and Material references](inline-design.md) explain the navigation constraint, archived alternatives and hardware-support contract.

Browse and Installed distinguish **Input sources** from **Device control** with filter chips. The catalog's required `type` mirrors the SDK: `input_module` or `output_device`. After installation Kalinka Player's detected type is authoritative. Output-device metadata must name supported models, families, or both, with readable requirements and limitations. These fields enable search without loading plugin code.

MusicCast shows its current control capabilities and a model-coverage lookup; Marantz is a proposed, non-installable entry with unverified capabilities. No actual model compatibility or network connection is claimed. The chosen mock omits the original synthetic utilities instead of treating them as one of the two plugin families.

| Chosen design state | Tablet | Phone |
| --- | --- | --- |
| Input source catalog | [View](previews/tablet-inline-catalog.png) | [View](previews/phone-inline-catalog.png) |
| Expanded source | [View](previews/tablet-inline-expanded.png) | [View](previews/phone-inline-expanded.png) |
| Device control catalog | [View](previews/tablet-inline-devices.png) | Responsive in prototype |
| MusicCast controls and model lookup | [View](previews/tablet-inline-musiccast.png) | [View](previews/phone-inline-musiccast.png) |
| Proposed Marantz support | [View](previews/tablet-inline-marantz.png) | Responsive in prototype |
| Expanded update | [View](previews/tablet-inline-updates.png) | Responsive in prototype |
| Restart decision | [View](previews/tablet-inline-confirm.png) | Responsive in prototype |
| Waiting without leaving the list | [View](previews/tablet-inline-waiting.png) | Responsive in prototype |
| Reconnecting inline | [View](previews/tablet-inline-restart.png) | Responsive in prototype |
| Compact tablet | [Expanded source](previews/compact-inline-expanded.png) | [Device support](previews/compact-inline-musiccast.png) |

The chosen mock was checked in Chromium at 1440 × 1040, 1024 × 768 and 390 × 844. Checks covered unchanged route/history on expansion, single-open behavior, keyboard collapse, dialog focus return, inline install/restart/completion, independent update selection, type filtering, model search, simulated connection checks, blocked/proposed releases, manual installation and offline behavior. New expansion/filter targets met the 48 px height check, no horizontal overflow was found, and the archived detail-page flow still passed its browser checks. These are prototype checks, not hardware or screen-reader certification.

The historical sections below are **not implementation guidance**. The chosen design replaces their detail/progress navigation and promotes plugin type without changing the server-menu entry point. Both HTML variants are mock-only; the separate [plugin hub](https://github.com/Kalinka-Player/kalinka-plugins) now publishes the public browsing feed.

## Current Flutter preview

The app implements read-only browsing behind **Server settings → General → Plugin catalog preview**, an expert setting that defaults to false. Plugins appears in the server menu only after the connected server reports that the saved setting is enabled. The app reads the server's cache, not GitHub directly. Installation, update checks and server restart are not exposed.

The implemented layout uses the right-hand queue pane on tablet and a full-screen panel on phone. It keeps one expanded plugin at a time, model/family search, a clear-search button, and the settings typography and colors. The large Plugins heading shrinks and supporting text fades with scrolling; Back, connection status and Browse/Reload remain visible. Each expanded plugin header pins below them only within its own entry. Reload rereads cached data and capabilities, not an immediate upstream refresh. Server-reported metadata compatibility is displayed with blocking reasons, without claiming package, signature or device verification.

Current Flutter visual snapshots live in [`test/goldens/plugin-catalog`](../../../test/goldens/plugin-catalog), including expanded, partially collapsed and compact-header states. Original design previews above are retained unchanged. Widget tests cover phone/tablet resizing, large text, reduced-motion settings, keyboard collapse, server switching and opt-in revocation. Run `flutter analyze` and `flutter test` before merging. Physical-device acceptance should check scrolling, the keyboard and clear-search control, server-menu opt-in, connection loss, and Now Playing controls while a tablet management panel is open; automated coverage does not replace that check.

## Archived detail page design

Open this superseded version only with [the explicit archive link](http://127.0.0.1:8767/docs/mocks/plugin-catalog/?layout=pages#catalog). Older screenshots retain the original A/B review labels.

| Screen | Tablet preview | Phone preview |
| --- | --- | --- |
| Server menu entry point | [View](previews/tablet-entry.png) | [View](previews/phone-entry.png) |
| Catalog | [View](previews/tablet-catalog.png) | [View](previews/phone-catalog.png) |
| Compact tablet catalog | [1024 × 768](previews/tablet-compact.png) | — |
| Plugin details | [View](previews/tablet-details.png) | [View](previews/phone-details.png) |
| Installed plugins | [View](previews/tablet-installed.png) | Responsive in prototype |
| Available updates | [View](previews/tablet-updates.png) | [View](previews/phone-updates.png) |
| Install confirmation | [View](previews/tablet-confirm.png) | Responsive in prototype |
| Restart and reconnect | [View](previews/tablet-restart.png) | Responsive in prototype |
| Server requirement not met | [View](previews/tablet-incompatible.png) | Responsive in prototype |
| Install from URL | [View](previews/tablet-manual.png) | Responsive in prototype |
| Failed update with rollback | [View](previews/tablet-failed.png) | Responsive in prototype |
| Cached catalog while offline | [View](previews/tablet-offline.png) | Responsive in prototype |

The supplied tablet screenshot is retained as `assets/tablet-reference.png`. CSS uses it for the existing album artwork; it is not an external image dependency. The mock reuses the repository’s wordmark and IBM Plex Sans, IBM Plex Mono and Playfair Display fonts. Their existing asset and font licenses continue to apply.

### Archived design decisions

The server chip is already the entrance to server management, so Plugins belongs beside Server settings. It is not part of the Discover music search. A small count on the Plugins row shows available updates. A secondary link in General settings leads to the same destination.

**Browse, Installed and Updates** are the primary views. Official and Unofficial are sections in Browse; Experimental has its own section and remains a separate maturity badge in details. This keeps maintenance authority distinct from readiness. Default browsing emphasizes independent additions; bundled plugins are available through Installed and search.

Rows show a name, one-line description and relevant state. Details show the creator, platform coverage, version, license, release notes and requirements. A disabled action explains incompatible server versions. SDK details stay under **Server requirements**, where they explain a blocked installation rather than adding noise to every catalog row. A package that passes the initial checks still has its dependencies checked before the confirmation step.

**Installed** distinguishes independently managed plugins, plugins included with the server, and manually installed unregistered plugins. Included plugins have a Configure action and update with Kalinka Player. Unregistered plugins retain configuration access and direct-install options, with an explicit manual-update label.

The Updates view lets users review and select releases together, with one restart for the batch. Automatic update policy is separate from checking for updates. The default is notification; official stable releases can be updated during quiet hours, while unofficial and experimental plugins retain individual opt-in. Unregistered plugins never inherit automatic updates.

The install confirmation exposes the actual interruption: finish when playback stops or restart now. Waiting does not stop music. The restart screen says **Reconnecting**, retains progress, and allows navigation away. Success leads to configuration. The failure example explicitly confirms that the previous version was restored; it does not disguise a failed update as success.

### Archived interaction walkthrough

1. Open the server sheet and choose Plugins.
2. Open Internet Radio, choose Install plugin, and leave **When playback stops** selected.
3. Choose Install when idle. The mock shows the prepared installation waiting for playback.
4. Choose Restart now to simulate restarting and reconnecting. After a few seconds the success view offers Configure plugin.
5. Return to Plugins and try search, Installed, Updates, selection checkboxes and automatic-update preferences.
6. Open Install from URL. Use the example link to inspect a synthetic unregistered release. The mock validates the URL form but does not contact that address.

Keyboard focus remains inside dialogs and the server sheet; Escape dismisses them. Controls have accessible names and visible focus indicators. The prototype uses the app’s 900 px tablet breakpoint. Phone content scrolls independently above the persistent install action and mini-player.

## Flutter integration for the chosen design

These are proposed implementation changes, not edits made by this mock:

| Existing file | Proposed integration |
| --- | --- |
| `lib/widgets/server_sheet.dart` | Add `openPlugins` to `ServerSheetAction`, a callback for tablet mode, and the Plugins row to both sheet variants. |
| `lib/screens/music_player_screen.dart` | Host Plugins as a full-width overlay on phone and over the tablet’s right-hand queue, using the same ownership, clipping and slide behavior as Settings. Close the server sheet before opening it. |
| `lib/screens/settings_screen.dart` | Optional secondary link from General; complex Configure tasks replace Plugins with peer Server settings, preserving the return location, rather than pushing a third level. |
| `lib/theme/app_theme.dart` | Reuse existing colors, fonts, 52 px top bar, 900 px breakpoint and panel conventions. |
| New plugin providers and Plugins view | Read catalog, inventory and updates from the connected server. Use one expanded plugin ID, type filters, inline model lookup and persistent operation status; no details/progress route. Keep operation IDs scoped to that server, and resume polling after reconnect. |

Use the proposed server API from the KalinkaPlayer plugin catalog design. The UI must not infer update ownership from package names, claim dependencies are resolved from metadata alone, or lose an operation because the server restarts. Hide installation actions when the server does not advertise a supported installation capability; explain whether upgrading the server enables it.

## Archived design verification

The prototype was exercised in Chromium at 1440 × 1040 and 390 × 844. Checks covered server-menu navigation, catalog search including bundled plugins, empty results, the install/wait/restart/success flow, update selection, manual URL validation, offline installation blocking, dialog dismissal and horizontal overflow. Additional checks at 1024 × 768, 900 × 720 and 375 × 667 confirmed the install action stays visible. The previews were inspected for clipping, font loading and action placement. Flutter tests were not run because no Flutter code changed.
