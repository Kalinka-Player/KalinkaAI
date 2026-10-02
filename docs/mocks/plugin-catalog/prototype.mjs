import { createInlineCatalog } from "./inline.mjs";

const inlineMode =
  new URLSearchParams(location.search).get("layout") !== "pages";
document.body.classList.toggle("inline-mode", inlineMode);
document
  .querySelector(`[data-variant="${inlineMode ? "inline" : "pages"}"]`)
  .setAttribute("aria-current", "page");
if (inlineMode)
  document.querySelector('[data-scene="details"]').textContent = "Expanded";

const paths = {
  back: '<path d="m14 6-6 6 6 6"/>',
  "chevron-right": '<path d="m9 5 7 7-7 7"/>',
  "chevron-down": '<path d="m6 9 6 6 6-6"/>',
  "arrow-right": '<path d="M4 12h16m-6-6 6 6-6 6"/>',
  close: '<path d="m6 6 12 12M6 18 18 6"/>',
  more: '<circle cx="12" cy="5" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="12" cy="19" r="1"/>',
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4 4"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  "check-circle": '<circle cx="12" cy="12" r="9"/><path d="m8 12 3 3 5-6"/>',
  circle: '<circle cx="12" cy="12" r="8"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  refresh:
    '<path d="M20 7v5h-5M4 17v-5h5"/><path d="M6.5 6a8 8 0 0 1 13 4M4.5 14a8 8 0 0 0 13 4"/>',
  puzzle:
    '<path d="M4 4h6a3 3 0 1 1 6 0h4v6a3 3 0 1 0 0 6v4h-6a3 3 0 1 0-6 0H4v-6a3 3 0 1 0 0-6z"/>',
  radio:
    '<rect x="3" y="8" width="18" height="13" rx="3"/><path d="m5 8 13-5"/><circle cx="9" cy="14.5" r="3"/><path d="M15 12h3m-3 4h3"/>',
  headphones:
    '<path d="M4 14v-3a8 8 0 0 1 16 0v3"/><rect x="3" y="12" width="4" height="8" rx="2"/><rect x="17" y="12" width="4" height="8" rx="2"/>',
  library: '<path d="M4 4v16M9 4v16m5-15 6 14M3 20h7m4-15 3-1m1 16 3-1"/>',
  speaker:
    '<rect x="6" y="2" width="12" height="20" rx="2"/><circle cx="12" cy="15" r="3"/><circle cx="12" cy="6" r="1"/>',
  wave: '<path d="M3 10v4m4-8v12m5-16v20m5-16v12m4-8v4"/>',
  flask:
    '<path d="M9 3h6m-5 0v7l-6 9a1 1 0 0 0 1 2h14a1 1 0 0 0 1-2l-6-9V3M7 16h10"/>',
  music:
    '<path d="M9 17V5l11-2v12M9 8l11-2"/><ellipse cx="6" cy="18" rx="3" ry="2"/><ellipse cx="17" cy="16" rx="3" ry="2"/>',
  heart:
    '<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8z"/>',
  settings:
    '<circle cx="12" cy="12" r="3"/><path d="m10 3-1 3-3 1-3-1-1 4 3 2-1 3-2 2 3 3 3-1 2 2 4-1 1-3 3-1 3 1 1-4-3-2 1-3 2-2-3-3-3 1-2-2z"/>',
  globe:
    '<circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><path d="M3 12h18"/>',
  logout: '<path d="M9 3H4v18h5m5-14 5 5-5 5M8 12h11"/>',
  link: '<path d="m9 15 6-6m-7 9-1 1a4 4 0 0 1-6-6l5-5a4 4 0 0 1 6 0m0-2 1-1a4 4 0 0 1 6 6l-5 5a4 4 0 0 1-6 0" transform="translate(2 0)"/>',
  download: '<path d="M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5"/>',
  external: '<path d="M14 3h7v7m0-7L10 14M10 3H3v18h18v-7"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6m0-10v.1"/>',
  alert: '<path d="m12 3 10 18H2zM12 9v5m0 3v.1"/>',
  wifi: '<path d="M2 8a17 17 0 0 1 20 0M5 12a12 12 0 0 1 14 0m-11 4a6 6 0 0 1 8 0m-4 4v.1"/>',
  cast: '<path d="M8 4h13v14h-7M3 10a11 11 0 0 1 11 11M3 15a6 6 0 0 1 6 6M3 20v1h1"/>',
  pause: '<path d="M8 5v14M16 5v14"/>',
  play: '<path d="m8 4 12 8-12 8z"/>',
  prev: '<path d="M5 5v14m14-14L8 12l11 7z"/>',
  next: '<path d="M19 5v14M5 5l11 7-11 7z"/>',
  shuffle:
    '<path d="M3 5h3l12 14h3m-4-4 4 4-4 3M3 19h3l12-14h3m-4-3 4 3-4 4"/>',
  repeat: '<path d="m16 2 4 4-4 4M4 11V6h16M8 22l-4-4 4-4m12-1v5H4"/>',
  volume:
    '<path d="M3 9h4l5-4v14l-5-4H3zm13-2a7 7 0 0 1 0 10m3-13a11 11 0 0 1 0 16"/>',
  drag: '<path d="M5 10h14M5 14h14"/>',
  sparkles:
    '<path d="m9 3 2.5 6.5L18 12l-6.5 2.5L9 21l-2.5-6.5L0 12l6.5-2.5zM19 1l1.2 3.8L24 6l-3.8 1.2L19 11l-1.2-3.8L14 6l3.8-1.2z"/>',
};
const icon = (name) =>
  `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">${paths[name] || paths.puzzle}</svg>`;
const escapeHTML = (text) =>
  String(text).replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
const plugins = [
  {
    id: "radio",
    name: "Internet Radio",
    description: "Your favourite stations, all in one place.",
    long: "Bring live radio into your library. Browse stations from around the world or add a stream you already love.",
    icon: "radio",
    tier: "Official",
    creator: "Kalinka team",
    version: "1.2.0",
    size: "1.8 MB",
    platform: "All server platforms",
    features: [
      "Browse stations by country and genre",
      "Save favourites alongside your music",
      "Add a station with its stream URL",
    ],
    notes: "Adds station favourites and improves reconnecting to live streams.",
  },
  {
    id: "qobuz",
    name: "Qobuz Connect",
    description: "Play from the Qobuz app through Kalinka.",
    long: "Choose Kalinka as an output in the Qobuz app and listen through your connected renderer.",
    icon: "headphones",
    tier: "Official",
    creator: "Kalinka team",
    version: "1.5.0",
    installed: "1.4.0",
    size: "4.2 MB",
    platform: "Linux · arm64, amd64",
    features: [
      "Control playback from the Qobuz app",
      "Play through your selected Kalinka output",
      "Keep track information in sync",
    ],
    notes:
      "More reliable reconnection after a network change. Improves track information during continuous playback.",
  },
  {
    id: "lastfm",
    name: "Last.fm Scrobbler",
    description: "Keep your listening history in sync.",
    long: "Send the music you play in Kalinka to your Last.fm profile. Connect your account once and keep your listening history up to date.",
    icon: "wave",
    tier: "Unofficial",
    creator: "Community maintainer",
    version: "0.9.0",
    installed: "0.8.2",
    size: "680 KB",
    platform: "All server platforms",
    features: [
      "Scrobble tracks from your music sources",
      "Keep a queue while Last.fm is unavailable",
      "Connect your own Last.fm account",
    ],
    notes:
      "Queues scrobbles while offline and sends them when the connection returns.",
  },
  {
    id: "listenbrainz",
    name: "ListenBrainz",
    description: "Share your listens with an open music community.",
    long: "Connect your ListenBrainz account to build a personal listening history from the music you play in Kalinka.",
    icon: "heart",
    tier: "Unofficial",
    creator: "Community maintainer",
    version: "0.4.0",
    size: "520 KB",
    platform: "All server platforms",
    features: [
      "Submit listens from Kalinka",
      "Connect with your personal token",
      "Pause sharing at any time",
    ],
    notes: "Improves duplicate-listen detection.",
  },
  {
    id: "room",
    name: "Room Correction",
    description: "Explore room-aware playback adjustments.",
    long: "An early experiment in applying room correction profiles to a compatible Kalinka renderer.",
    icon: "wave",
    tier: "Unofficial",
    experimental: true,
    creator: "Community maintainer",
    version: "0.2.0",
    size: "18.6 MB",
    platform: "Linux · arm64",
    blocked: true,
    features: [
      "Try a room correction profile",
      "Adjust processing for a supported renderer",
      "Switch back to unprocessed playback",
    ],
    notes:
      "Experimental preview. Needs a newer Kalinka server and a compatible renderer.",
  },
  {
    id: "localfiles",
    name: "My Library",
    description: "Your music files, metadata and smart search.",
    icon: "library",
    tier: "Official",
    creator: "Dmitry Savin",
    version: "5.4.1",
    installed: "5.4.1",
    bundled: true,
  },
  {
    id: "jamendo",
    name: "Jamendo",
    description: "Discover independent music from Jamendo.",
    icon: "music",
    tier: "Official",
    creator: "Dmitry Savin",
    version: "5.4.1",
    installed: "5.4.1",
    bundled: true,
  },
  {
    id: "musiccast",
    name: "MusicCast",
    description: "Volume, power and input control for Yamaha.",
    icon: "speaker",
    tier: "Official",
    creator: "Dmitry Savin",
    version: "5.4.1",
    installed: "5.4.1",
    bundled: true,
  },
  {
    id: "upnp",
    name: "UPnP",
    description: "Play from a UPnP control app on your network.",
    icon: "cast",
    tier: "Official",
    creator: "Dmitry Savin",
    version: "5.4.1",
    installed: "5.4.1",
    bundled: true,
  },
  {
    id: "dummydevice",
    name: "Dummy Device",
    description: "A simulated device for development and testing.",
    icon: "flask",
    tier: "Official",
    experimental: true,
    creator: "Dmitry Savin",
    version: "5.4.1",
    installed: "5.4.1",
    bundled: true,
  },
  {
    id: "studio",
    name: "Studio Bridge",
    description: "A custom connection to your studio system.",
    long: "A plugin installed directly from its author’s repository. Kalinka can show its status and settings, but the plugin is not registered in the catalog.",
    icon: "puzzle",
    tier: "Unregistered",
    creator: "Plugin author",
    version: "0.3.2",
    installed: "0.3.2",
    manual: true,
    size: "940 KB",
    platform: "All server platforms",
    features: ["Connect your studio system", "Configure it on this server"],
    notes: "Check the source repository for new releases.",
  },
];
// The chosen design uses the catalog's explicit SDK type. Keep old fixtures
// without a supported type only in the superseded detail-page comparison.
for (const p of plugins) {
  if (["radio", "qobuz", "localfiles", "jamendo", "upnp"].includes(p.id))
    p.type = "input_module";
  if (["musiccast", "dummydevice", "studio"].includes(p.id))
    p.type = "output_device";
}
getMusicCastMetadata();
function getMusicCastMetadata() {
  const p = plugins.find((p) => p.id === "musiccast");
  p.device = {
    brand: "Yamaha",
    transport: "Local network · Yamaha Extended Control API",
    controls: [
      "Read & set volume",
      "Power on / standby",
      "Power status",
      "Configured input switching",
    ],
    limits:
      "Mute is not exposed. Input switching selects Kalinka’s configured input, not an arbitrary input. Power readiness also depends on that input being selected.",
    models:
      "Yamaha MusicCast / Extended Control family. Exact model coverage is not yet verified in this catalog.",
  };
}
plugins.push({
  id: "marantz",
  name: "Marantz Control",
  description: "Proposed amplifier and AVR integration.",
  long: "A placeholder for future Marantz device support. No package, supported-model list or control capabilities have been verified yet.",
  icon: "speaker",
  type: "output_device",
  tier: "Unofficial",
  experimental: true,
  creator: "Maintainer to be confirmed",
  version: "Not released",
  planned: true,
  inlineOnly: true,
  device: {
    brand: "Marantz",
    transport: "To be confirmed per model · network or RS-232",
    controls: [],
    limits:
      "Volume, power, mute and input control are requirements to investigate, not promised features.",
    models:
      "No verified models yet. A REST endpoint or RS-232 socket alone does not establish protocol support.",
  },
});
plugins.push({
  id: "networkradio",
  name: "Network Radio Preview",
  description: "Try an early network radio integration.",
  long: "An illustrative preview for a newer Kalinka server. This example demonstrates a blocked installation without adding a details screen.",
  icon: "radio",
  type: "input_module",
  tier: "Unofficial",
  experimental: true,
  creator: "Community maintainer",
  version: "0.2.0",
  size: "1.8 MB",
  platform: "All server platforms",
  blocked: true,
  inlineOnly: true,
  notes: "Design fixture. Requires server 6.0 and SDK 4.0.",
});
// `kind` is only a presentation alias, never another catalog classification.
for (const p of plugins)
  p.kind = { input_module: "source", output_device: "device" }[p.type];
const visiblePlugins = () =>
  plugins.filter((p) => (inlineMode ? p.kind : !p.inlineOnly));
const initialInstalled = new Map(plugins.map((p) => [p.id, p.installed]));
const initialVersions = new Map(plugins.map((p) => [p.id, p.version]));
const state = {
  scene: "entry",
  selected: "radio",
  tab: "catalog",
  query: "",
  modal: null,
  restart: "idle",
  selection: new Set(["qobuz", "lastfm"]),
  automatic: false,
  operation: null,
  operationIds: [],
  source: "",
  manualPreview: false,
  catalogOffline: false,
  expanded: null,
  kind: "source",
  modelQuery: "",
  deviceChecked: false,
};
let modalReturnFocus = null;
let timers = [];
const left = document.querySelector("#left-pane");
const getPlugin = (id) => plugins.find((p) => p.id === id) || plugins[0];
const updates = () =>
  visiblePlugins().filter(
    (p) => p.installed && !p.bundled && !p.manual && p.installed !== p.version,
  );
const installed = () => visiblePlugins().filter((p) => p.installed);
const tile = (p) => `<span class="plugin-icon ${p.id}">${icon(p.icon)}</span>`;
const badge = (text, kind = "") => `<span class="badge ${kind}">${text}</span>`;
const btn = (action, label, style = "secondary", extra = "") =>
  `<button class="${style}" data-action="${action}" ${extra}>${label}</button>`;
const miniPlayer = () =>
  `<div class="mini-player"><div class="mini-cover"></div><div><strong>God Sometimes</strong><small>Julia Jacklin</small></div>${icon("pause")}</div>`;
const captions = {
  entry:
    "01 / Entry point — Plugins sits directly below Server settings in the existing server sheet.",
  catalog:
    "02 / Catalog — Server tools use the left tablet pane; the queue remains in place.",
  details:
    "03 / Plugin details — Publisher, compatibility and restart impact before installation.",
  installed:
    "04 / Installed — Independent, bundled and manually installed plugins have clear ownership.",
  updates:
    "05 / Updates — Review changes together and restart once; automatic updates are a separate choice.",
  restart:
    "06 / Restart — A lost connection is expected. Progress belongs to the server, not this screen.",
  complete:
    "07 / Ready — Installation finishes with a clear route into configuration.",
  failed:
    "08 / Recovery — Report the failed update and confirm that the previous version was restored.",
  incompatible:
    "09 / Requirements — Explain what blocks installation; don’t offer an install that cannot work.",
  manual:
    "10 / Direct installation — An unregistered source is explicit and never gains automatic updates.",
  offline: "11 / Offline — Keep the cached catalog readable and label its age.",
  confirm:
    "12 / Installation — Review one restart decision, including an option to wait until playback stops.",
  settings:
    "Settings — A secondary Plugins link makes the same destination available from settings.",
};
const inlineCatalog = createInlineCatalog({
  state,
  visiblePlugins,
  installed,
  updates,
  icon,
  tile,
  badge,
  btn,
  miniPlayer,
  topbar,
  tabs,
  listContent,
  escapeHTML,
});

function topbar(label = "My Kalinka Service", back = "close") {
  return `<header class="topbar"><button class="icon-button" data-action="${back}" aria-label="${back === "back" ? "Back to plugins" : "Back to player"}">${icon("back")}</button><span class="topbar-title">${label}</span><button class="icon-button" data-action="${label === "Plugins" ? "close" : "manual"}" aria-label="${label === "Plugins" ? "Close plugins" : "Install from URL"}">${icon(label === "Plugins" ? "close" : "more")}</button></header>`;
}

function tabs() {
  return `<nav class="tabs" aria-label="Plugin views">${[
    ["catalog", "Browse", null],
    ["installed", "Installed", installed().length],
    ["updates", "Updates", updates().length],
  ]
    .map(
      ([id, name, count]) =>
        `<button class="tab ${state.tab === id ? "active" : ""}" data-action="tab" data-id="${id}" ${state.tab === id ? 'aria-current="page"' : ""}>${name}${count !== null ? `<span class="count ${id === "updates" && count ? "updates" : ""}">${count}</span>` : ""}</button>`,
    )
    .join("")}</nav>`;
}

function row(p) {
  if (inlineMode) return inlineCatalog.row(p);
  let label = p.blocked
    ? "Needs server 6.0"
    : p.manual
      ? "Manual updates"
      : p.bundled
        ? "Included"
        : p.installed === p.version
          ? "Installed"
          : p.installed
            ? "Update available"
            : "";
  const kind = p.blocked
    ? "incompatible"
    : p.installed && p.installed !== p.version
      ? "update"
      : "";
  return `<button class="plugin-row" data-action="detail" data-id="${p.id}" aria-label="${p.name}${label ? `, ${label}` : ""}">${tile(p)}<span class="plugin-copy"><span class="plugin-name">${p.name}</span><span class="plugin-description">${p.description}</span>${state.tab === "installed" ? `<span class="plugin-meta">v${p.installed} · ${p.manual ? "Not in catalog" : p.bundled ? "Server bundle" : p.tier}</span>` : ""}</span>${label ? `<span class="row-state ${kind}">${label}</span>` : ""}${icon("chevron-right")}</button>`;
}

function listContent() {
  if (inlineMode) return inlineCatalog.listContent();
  const query = state.query.trim().toLowerCase();
  const matches = (p) =>
    `${p.name} ${p.description} ${p.tier}`.toLowerCase().includes(query);
  const pool = (
    state.tab === "installed"
      ? installed()
      : visiblePlugins().filter((p) => !p.manual && (query || !p.bundled))
  ).filter(matches);
  const groups =
    state.tab === "installed"
      ? [
          ["Independent plugins", pool.filter((p) => !p.bundled && !p.manual)],
          ["Included with Kalinka", pool.filter((p) => p.bundled)],
          ["Installed manually", pool.filter((p) => p.manual)],
        ]
      : [
          [
            "Official",
            pool.filter((p) => p.tier === "Official" && !p.experimental),
          ],
          [
            "Unofficial",
            pool.filter((p) => p.tier === "Unofficial" && !p.experimental),
          ],
          ["Experimental", pool.filter((p) => p.experimental)],
        ];
  if (!pool.length)
    return `<div class="empty">${icon("search")}<h2>No plugins found</h2><p>Try a name, source or integration.</p>${btn("clear-search", "Clear search")}</div>`;
  return (
    groups
      .filter(([, items]) => items.length)
      .map(
        ([name, items]) =>
          `<h2 class="group-label">${name === "Experimental" ? icon("flask") : ""}${name} <span>${items.length}</span></h2>${items.map(row).join("")}`,
      )
      .join("") +
    (state.tab === "catalog" && !query
      ? `<button class="included-link" data-action="tab" data-id="installed">${icon("library")}5 more plugins are included with your server${icon("chevron-right")}</button>`
      : "")
  );
}

function catalogScreen() {
  if (inlineMode) return inlineCatalog.screen();
  const offline = state.scene === "offline";
  const operation = state.operation === "waiting";
  return `<div class="screen">${topbar()}<div class="page-heading"><p class="eyebrow">ON THIS SERVER</p><div class="heading-row"><h1>Plugins</h1><button class="text-button" data-action="manual">${icon("link")}Install from URL</button></div><p class="heading-description">More ways to listen. Make Kalinka yours.</p></div>${tabs()}${state.tab === "updates" ? updateContent() : `<div class="scroll-area">${offline ? `<div class="notice offline">${icon("wifi")}<span>Catalog unavailable · showing yesterday’s list.</span><button data-action="check">Retry</button></div>` : ""}${operation ? `<div class="notice">${icon("clock")}<span>Install ready. Waiting for playback to stop.</span><button data-action="operation">View</button></div>` : ""}<div class="search-wrap"><label class="search-box">${icon("search")}<input id="plugin-search" type="search" value="${escapeHTML(state.query)}" placeholder="${state.tab === "installed" ? "Search installed plugins" : "Search plugins"}" aria-label="Search plugins" autocomplete="off"></label></div><div class="plugin-list">${listContent()}</div></div><div class="catalog-foot"><span>${offline ? "Last checked yesterday" : "Catalog checked just now"}</span><button class="text-button" data-action="check">${icon("refresh")}Check again</button></div>`}${miniPlayer()}</div>`;
}

function compatibility(p) {
  if (p.blocked)
    return `<div class="compatibility warning">${icon("info")}<div><strong>A newer server is needed</strong><p>Requires Kalinka 6.0 or later. This server is on 5.4.1.</p></div></div>`;
  if (p.manual)
    return `<div class="compatibility neutral">${icon("link")}<div><strong>Updates managed manually</strong><p>This plugin isn’t in the catalog. Install new releases from its source.</p></div></div>`;
  if (p.bundled)
    return `<div class="compatibility neutral">${icon("puzzle")}<div><strong>Included with your server</strong><p>This plugin updates together with Kalinka.</p></div></div>`;
  return `<div class="compatibility">${icon("check-circle")}<div><strong>Compatible with this server</strong><p>Dependencies will be checked before installation.</p></div></div>`;
}

function detailScreen() {
  const p = getPlugin(state.selected);
  let action = p.blocked
    ? btn("blocked", "Server update required", "primary", "disabled")
    : p.bundled
      ? btn("configure", "Configure", "secondary")
      : p.manual && state.manualPreview
        ? btn("plan", "Install this release", "primary")
        : p.installed === p.version
          ? btn("configure", "Configure", "primary")
          : btn(
              "plan",
              `${icon(p.installed ? "refresh" : "download")}${p.installed ? "Update plugin" : "Install plugin"}`,
              "primary",
            );
  if (
    state.catalogOffline &&
    !p.manual &&
    !p.bundled &&
    p.installed !== p.version
  ) {
    action = btn("blocked", "Catalog unavailable", "primary", "disabled");
  }
  const info = p.blocked
    ? "Not available for this server"
    : p.bundled
      ? `Installed · v${p.installed}`
      : p.installed === p.version
        ? `Installed · v${p.version}`
        : p.installed
          ? `v${p.installed} → ${p.version}`
          : `v${p.version} · ${p.size}`;
  return `<div class="screen">${topbar("Plugins", "back")}<div class="scroll-area"><div class="detail-body"><div class="detail-identity">${tile(p)}<div><h1>${p.name}</h1><div class="badge-line">${badge(p.tier)}${p.experimental ? badge("Experimental", "pending") : badge(p.bundled ? "Included" : "Stable")}</div></div></div><p class="detail-lede">${p.long || p.description}</p>${compatibility(p)}<dl class="facts"><div><dt>Created by</dt><dd>${p.creator}</dd></div><div><dt>Platforms</dt><dd>${p.platform || "Supported Kalinka servers"}</dd></div><div><dt>${p.bundled ? "Bundle version" : p.manual ? "Selected release" : "Latest release"}</dt><dd>${p.version}</dd></div><div><dt>License</dt><dd>GPL-3.0-or-later</dd></div></dl>${p.bundled ? "" : `<section class="detail-section"><h2>What it adds</h2>${(p.features || []).map((f, i) => `<div class="feature-line">${icon(["music", "heart", "settings"][i % 3])}<span>${f}</span></div>`).join("")}</section><section class="detail-section"><h2>${p.manual ? "Keeping it up to date" : `What’s new in ${p.version}`}</h2><p>${p.notes}</p></section>`}<details ${p.blocked ? "open" : ""}><summary>Server requirements</summary><table class="requirements"><tbody><tr><td>Kalinka server</td><td>${p.blocked ? "≥ 6.0" : "≥ 5.0"}</td><td class="${p.blocked ? "fail" : ""}">${p.blocked ? "5.4.1 installed" : "5.4.1 ✓"}</td></tr><tr><td>Plugin SDK</td><td>${p.blocked ? "≥ 4.0, < 5" : "≥ 3.6, < 4"}</td><td class="${p.blocked ? "fail" : ""}">${p.blocked ? "3.6 installed" : "3.6 ✓"}</td></tr><tr><td>Platform</td><td>${p.platform || "Linux"}</td><td>Linux arm64 ✓</td></tr></tbody></table></details><section class="detail-section"><button class="text-button" data-action="source">${icon("external")}Source & publisher</button></section></div></div><div class="sticky-action"><div class="action-info">${info}<small>${p.blocked ? "See requirements above" : p.bundled ? "Managed by the server bundle" : p.installed === p.version ? "Ready to configure" : "One server restart to finish"}</small></div>${action}</div>${miniPlayer()}</div>`;
}

function updateContent() {
  const available = updates();
  const selected = available.filter((p) => state.selection.has(p.id));
  return `<div class="scroll-area"><div class="updates-intro"><p>${available.length ? `${available.length} updates for this server` : "Your plugins are up to date"}</p><button class="text-button" data-action="policy">${icon("settings")}Auto updates</button></div>${available.map((p) => `<article class="update-card"><header>${tile(p)}<div><strong>${p.name}</strong><div class="version-change">${p.installed}${icon("arrow-right")}${p.version}</div></div><label><span class="sr-only">Select ${p.name} update</span><input type="checkbox" data-update="${p.id}" ${state.selection.has(p.id) ? "checked" : ""}></label></header><p>${p.notes}</p><div>${badge(p.tier)} <button class="text-button" data-action="detail" data-id="${p.id}">View release ${icon("chevron-right")}</button></div></article>`).join("")}<div class="notice">${icon("info")}<span>Included plugins update with the server. Unregistered plugins are updated manually.</span></div><div class="update-footer">${state.automatic ? "Automatic updates: official stable releases, 03:00–06:00 while idle." : "Automatic updates are off. You choose when to install."}</div></div><div class="sticky-action"><div class="action-info">${selected.length} ${selected.length === 1 ? "plugin" : "plugins"} selected<small>${selected.length ? "One restart for all selected updates" : "Choose an update above"}</small></div>${btn("plan-updates", "Update selected", "primary", selected.length ? "" : "disabled")}</div>`;
}

function playerScreen() {
  return `<div class="full-player"><div class="player-eyebrow"><span>NOW PLAYING</span><span class="renderer-label">${icon("cast")}Kalinka Test Renderer ${icon("chevron-down")}</span></div><div class="album-art" role="img" aria-label="Julia Jacklin, The Gem album artwork from the supplied reference"></div><h1 class="song-title">God Sometimes</h1><div class="song-artist">Julia Jacklin</div><div class="song-album">The Gem</div><div class="song-format"><span class="source-tag">♫ Qobuz Connect</span>Qobuz · FLAC 24-bit · 96 kHz</div><div class="progress-track"></div><div class="song-times"><span>1:53</span><span>3:41</span></div><div class="transport">${icon("shuffle")}${icon("prev")}<span class="play">${icon("pause")}</span>${icon("next")}${icon("repeat")}</div><div class="volume">${icon("volume")}<div class="volume-line"></div>${icon("volume")}</div></div>`;
}

function serverMenu() {
  return `<div class="sheet-scrim" data-backdrop="menu"><section class="server-sheet" role="dialog" aria-modal="true" aria-label="Server menu" tabindex="-1"><div class="handle"></div><p class="eyebrow">SERVER</p><div class="server-card"><span class="online-dot"></span><div><strong>My Kalinka Service</strong><small>kalinka.local:8000 · v5.4.1 · 12 ms</small></div>${badge("Online", "status")}</div><button class="sheet-row" data-action="settings"><span class="tile">${icon("settings")}</span><span class="sheet-row-copy"><strong>Server settings</strong><small>Modules, audio, enrichment</small></span>${icon("chevron-right")}</button><button class="sheet-row featured" data-action="plugins"><span class="tile">${icon("puzzle")}</span><span class="sheet-row-copy"><strong>Plugins</strong><small>Browse, install & update</small></span><span class="count updates">${updates().length}</span>${icon("chevron-right")}</button><div class="sheet-row"><span class="tile">${icon("globe")}</span><span class="sheet-row-copy"><strong>Connect to different server</strong><small>Scan network for other instances</small></span>${icon("chevron-right")}</div><div class="sheet-row"><span class="tile">${icon("logout")}</span><span class="sheet-row-copy"><strong>Disconnect</strong></span></div><div class="sheet-footer">Kalinka 0.15.1</div></section></div>`;
}

function operationScreen() {
  const done = state.scene === "complete";
  const failed = state.scene === "failed";
  const waiting = state.operation === "waiting";
  const batch = state.operationIds.length > 1;
  const p = getPlugin(state.operationIds[0] || state.selected);
  const title = done
    ? batch
      ? "Your plugins are updated"
      : `${p.name} is installed`
    : failed
      ? "Your previous version is back"
      : waiting
        ? "Ready when you are"
        : "Reconnecting to Kalinka";
  const message = done
    ? batch
      ? "All selected updates are installed. Your settings are preserved, and Kalinka is ready to play."
      : "Everything is ready. Configure the plugin to start using it."
    : failed
      ? "Qobuz Connect couldn’t start after its update. Kalinka restored version 1.4.0 and your settings."
      : waiting
        ? "The plugin is prepared. Installation will finish when playback stops, with one server restart."
        : "The server is restarting to finish the installation. This usually takes less than a minute.";
  const steps = waiting
    ? [
        ["Download & check package", "done"],
        ["Prepare installation", "done"],
        ["Wait for playback to stop", "active"],
        ["Restart & reconnect", ""],
      ]
    : [
        ["Download & check package", "done"],
        ["Install plugin", "done"],
        ["Restart server", done ? "done" : "active"],
        ["Reconnect", done ? "done" : ""],
      ];
  return `<div class="screen">${topbar("Plugins", "back")}<div class="scroll-area" style="display:flex"><div class="operation-body"><div class="operation-emblem ${done ? "success" : ""}">${icon(done ? "check-circle" : failed ? "refresh" : waiting ? "clock" : "wifi")}</div><p class="eyebrow">MY KALINKA SERVICE</p><h1>${title}</h1><p>${message}</p>${failed ? `<div class="compatibility warning">${icon("info")}<div><strong>The update wasn’t applied</strong><p>Your library and plugin settings are unchanged. We won’t retry this release automatically.</p></div></div>` : `<div class="operation-steps">${steps.map(([name, status]) => `<div class="operation-step ${status}">${icon(status === "done" ? "check-circle" : status === "active" ? "clock" : "circle")}<span>${name}</span>${status === "active" ? "<small>In progress</small>" : ""}</div>`).join("")}</div>`}${done ? (batch ? btn("installed", "View installed plugins", "primary") : btn("configure", "Configure plugin", "primary")) : failed ? btn("updates", "Back to updates", "secondary") : waiting ? btn("restart-now", "Restart now", "primary") : ""}${btn("plugins", done ? "Back to plugins" : waiting ? "Keep listening" : "You can leave this screen", "text-button")}<p class="operation-small">${done ? (batch ? "One restart applied all selected updates." : "Available in Server settings → Input modules.") : failed ? "Playback can continue. Check the release details before trying again." : "Progress is saved on the server. Reopening Plugins will show the same installation."}</p></div></div>${miniPlayer()}</div>`;
}

function dialogContent() {
  const p = getPlugin(state.selected);
  if (state.modal === "restart-confirm")
    return `<p class="eyebrow">INSTALLATION PREPARED</p><h2>Restart Kalinka now?</h2><p>Playback will stop briefly while the server finishes installing. Your queued installation can also keep waiting for playback to stop.</p><div class="dialog-actions">${btn("dismiss", "Keep waiting")}${btn("restart-now", "Restart now", "primary")}</div>`;
  if (state.modal === "manual")
    return `<p class="eyebrow">INSTALL FROM A SOURCE</p><h2>Add your own plugin</h2><p>Paste the link to a plugin’s release manifest. Kalinka will check the package and show you what will be installed.</p><label class="input-label" for="source-url">Release manifest URL</label><input id="source-url" class="url-input" type="url" placeholder="https://…/kalinka-plugin.json" value="${escapeHTML(state.source)}"><div id="source-error" class="input-error" role="alert"></div><button class="text-button" data-action="example-url">Use example link</button><div class="compatibility neutral">${icon("info")}<div><strong>Automatic updates won’t be available</strong><p>Only install plugins from a creator you trust.</p></div></div><div class="dialog-actions">${btn("dismiss", "Cancel")}${btn("inspect-source", "Review plugin", "primary")}</div>`;
  if (state.modal === "policy")
    return `<p class="eyebrow">THIS SERVER</p><h2>Automatic updates</h2><p>Checks run in the background. Choose how registered plugins are updated.</p><label class="radio-choice"><input type="radio" name="policy" value="notify" ${!state.automatic ? "checked" : ""}><span><strong>Notify me</strong><small>Review each update and choose when to restart.</small></span></label><label class="radio-choice"><input type="radio" name="policy" value="automatic" ${state.automatic ? "checked" : ""}><span><strong>Update official, stable plugins</strong><small>Between 03:00 and 06:00, only while nothing is playing.</small></span></label><p>Unofficial and experimental plugins keep their own opt-in. Unregistered plugins are never updated automatically.</p><div class="dialog-actions">${btn("dismiss", "Cancel")}${btn("save-policy", "Save preference", "primary")}</div>`;
  if (state.modal === "source" && p.planned)
    return `<p class="eyebrow">PROPOSED INTEGRATION</p><h2>${p.name}</h2><p>No publisher, repository, license or released package has been verified for this proposal. These details must be reviewed before a real catalog entry can offer installation.</p><div class="dialog-actions">${btn("dismiss", "Done", "primary")}</div>`;
  if (state.modal === "source")
    return `<p class="eyebrow">PUBLISHER</p><h2>${p.name}</h2><p>Created by ${p.creator}. ${p.tier === "Official" ? "Maintained by the Kalinka project." : p.manual ? "Installed from a source outside the catalog." : "Maintained independently of the Kalinka project."}</p><div class="plan-summary"><div><span>Catalog status</span><strong>${p.tier}</strong></div><div><span>Source</span><strong>GitHub repository</strong></div><div><span>License</span><strong>GPL-3.0-or-later</strong></div></div><p>Check the source repository for the code, issues and release history.</p><div class="dialog-actions">${btn("dismiss", "Done", "primary")}</div>`;
  if (state.modal === "configure")
    return `<p class="eyebrow">SERVER SETTINGS</p><h2>${p.name}</h2><p>${p.id === "radio" ? "Internet Radio is ready. Enable it to add stations to your music sources." : "Enable this plugin on My Kalinka Service. Its connection settings are available in Server settings."}</p><label class="radio-choice"><input type="checkbox" id="enable-plugin" checked><span><strong>Enable ${p.name}</strong><small>${p.kind === "device" ? "Use controls for your configured device." : "Show this source in Kalinka."}</small></span></label><div class="dialog-actions">${btn("dismiss", "Back")}${btn("configured", "Save", "primary")}</div>`;
  const batch = state.modal === "confirm-updates";
  const selected = batch
    ? updates().filter((p) => state.selection.has(p.id))
    : [p];
  return `${tile(p)}<p class="eyebrow">READY TO ${batch || p.installed ? "UPDATE" : "INSTALL"}</p><h2>${batch ? `Update ${selected.length} plugins?` : `${p.installed ? "Update" : "Install"} ${p.name}?`}</h2><p>Kalinka needs to restart to finish. Choose when to briefly stop playback.</p><div class="plan-summary">${selected.map((p) => `<div><span>${p.name}</span><strong>${p.installed ? `${p.installed} → ` : ""}${p.version}</strong></div>`).join("")}<div><span>Compatibility</span><strong>Requirements checked ${icon("check")}</strong></div><div><span>Server restarts</span><strong>One</strong></div></div><label class="radio-choice"><input type="radio" name="restart" value="idle" ${state.restart === "idle" ? "checked" : ""}><span><strong>When playback stops</strong><small>Keep listening. Finish the installation once idle.</small></span></label><label class="radio-choice"><input type="radio" name="restart" value="now" ${state.restart === "now" ? "checked" : ""}><span><strong>Restart now</strong><small>Playback will stop during the restart.</small></span></label>${p.manual ? "<p>This source is not registered. Future updates stay manual.</p>" : ""}<div class="dialog-actions">${btn("dismiss", "Cancel")}${btn("execute", state.restart === "idle" ? "Install when idle" : "Install & restart", "primary")}</div>`;
}

function settingsScreen() {
  return `<div class="screen">${topbar()}<div class="page-heading"><p class="eyebrow">MY KALINKA SERVICE</p><h1>Server settings</h1></div><div class="tabs"><span class="tab active">General</span><span class="tab">Input modules</span><span class="tab">Devices</span></div><div class="plugin-list"><h2 class="group-label">SERVER</h2><div class="plugin-row"><span class="plugin-copy"><span class="plugin-name">Service name</span><span class="plugin-description">My Kalinka Service</span></span></div><button class="plugin-row" data-action="plugins"><span class="plugin-icon">${icon("puzzle")}</span><span class="plugin-copy"><span class="plugin-name">Plugins</span><span class="plugin-description">Browse, install and manage plugins on this server</span></span><span class="count updates">${updates().length}</span>${icon("chevron-right")}</button></div></div>`;
}

function render() {
  const oldScroller = inlineMode ? left.querySelector(".scroll-area") : null;
  const oldScroll = oldScroller?.scrollTop || 0;
  const oldView = oldScroller?.dataset.view;
  const focusId = inlineMode && document.activeElement?.id;
  const mainView = ["catalog", "installed", "updates", "offline"].includes(
    state.scene,
  )
    ? catalogScreen()
    : ["details", "incompatible"].includes(state.scene)
      ? detailScreen()
      : ["restart", "complete", "failed"].includes(state.scene)
        ? operationScreen()
        : state.scene === "settings"
          ? settingsScreen()
          : playerScreen();
  left.innerHTML = mainView;
  if (inlineMode) {
    const scroller = left.querySelector(".scroll-area");
    if (scroller && scroller.dataset.view === oldView)
      scroller.scrollTop = oldScroll;
    if (focusId && !state.modal)
      document.getElementById(focusId)?.focus({ preventScroll: true });
    if (!state.modal && modalReturnFocus) {
      const target =
        left.querySelector(modalReturnFocus) ||
        left.querySelector(`[id="expand-${state.expanded}"]`) ||
        left.querySelector(".tab.active");
      target?.focus({ preventScroll: true });
      modalReturnFocus = null;
    }
  }
  document.querySelector("#server-overlay").innerHTML =
    state.scene === "entry" ? serverMenu() : "";
  document
    .querySelector(".app-layout")
    .classList.toggle(
      "entry-scene",
      state.scene === "entry" || state.scene === "home",
    );
  document
    .querySelector(".app-window")
    .classList.toggle(
      "is-restarting",
      inlineMode
        ? state.operation === "restarting"
        : state.scene === "restart" && state.operation !== "waiting",
    );
  document
    .querySelector("#server-chip")
    .setAttribute("aria-expanded", state.scene === "entry");
  document.querySelector("#review-caption").textContent =
    inlineMode && state.scene === "catalog"
      ? "Chosen / Expand in place — One Plugins destination. Details, release notes and progress stay here."
      : captions[state.scene] || captions.catalog;
  document
    .querySelectorAll("[data-scene]")
    .forEach((button) =>
      button.classList.toggle("active", button.dataset.scene === state.scene),
    );
  document.querySelector("#more-scenes").value = [
    ...document.querySelector("#more-scenes").options,
  ].some((o) => o.value === state.scene)
    ? state.scene
    : "";
  if (state.modal) {
    left.insertAdjacentHTML(
      "beforeend",
      `<div class="modal-layer"><section class="dialog" role="dialog" aria-modal="true" aria-label="${state.modal}" tabindex="-1">${dialogContent()}</section></div>`,
    );
    left.querySelector(".screen")?.setAttribute("inert", "");
    left.querySelector(".dialog").focus({ preventScroll: true });
  }
  if (state.scene === "entry")
    document.querySelector(".server-sheet").focus({ preventScroll: true });
  document.querySelector("#announcer").textContent = state.modal
    ? `${state.modal} dialog`
    : state.scene === "entry"
      ? "Server menu opened"
      : `Showing ${state.scene}`;
}

function go(scene, id) {
  state.modal = null;
  state.query = "";
  if (id) state.selected = id;
  if (["catalog", "installed", "updates"].includes(scene)) state.tab = scene;
  if (
    inlineMode &&
    [
      "details",
      "incompatible",
      "restart",
      "complete",
      "failed",
      "offline",
      "installed",
      "updates",
    ].includes(scene)
  ) {
    if (["details", "incompatible"].includes(scene)) {
      state.expanded = state.selected;
      state.kind = getPlugin(state.selected).kind || "all";
      if (getPlugin(state.selected).manual) state.tab = "installed";
    }
    scene = "catalog";
  }
  state.scene = scene;
  history.replaceState(
    null,
    "",
    `#${scene}${scene === "details" ? `:${state.selected}` : ""}`,
  );
  render();
}

function showScenario(scene) {
  timers.forEach(clearTimeout);
  timers = [];
  state.operation = null;
  state.modal = null;
  state.restart = "idle";
  state.catalogOffline = scene === "offline";
  state.manualPreview = false;
  state.selection = new Set(["qobuz", "lastfm"]);
  state.automatic = false;
  state.expanded = null;
  state.tab = "catalog";
  state.kind = "source";
  state.modelQuery = "";
  state.deviceChecked = false;
  if (inlineMode) left.querySelector(".scroll-area")?.scrollTo(0, 0);
  for (const plugin of plugins) {
    plugin.installed = initialInstalled.get(plugin.id);
    plugin.version = initialVersions.get(plugin.id);
  }
  if (scene === "details") return go("details", "radio");
  if (scene === "incompatible")
    return go(scene, inlineMode ? "networkradio" : "room");
  if (scene === "manual" || scene === "confirm") {
    go(scene === "manual" ? "catalog" : "details", "radio");
    state.modal = scene;
    state.source = "";
    history.replaceState(null, "", `#${scene}`);
    render();
    document.querySelector("#review-caption").textContent = captions[scene];
    document.querySelector("#more-scenes").value = scene;
    return;
  }
  if (scene === "restart" || scene === "complete") {
    state.operationIds = ["radio"];
    state.operation = scene === "restart" ? "restarting" : "complete";
    state.selected = "radio";
    if (scene === "complete")
      getPlugin("radio").installed = getPlugin("radio").version;
    if (inlineMode) state.expanded = "radio";
  }
  if (inlineMode && scene === "failed") {
    state.operation = "failed";
    state.operationIds = ["qobuz"];
    state.expanded = "qobuz";
    state.tab = "updates";
  }
  if (scene === "offline") state.tab = "catalog";
  go(scene);
}

function startRestart() {
  state.operation = "restarting";
  if (inlineMode) {
    state.modal = null;
    render();
  } else go("restart");
  timers.push(
    setTimeout(() => {
      for (const id of state.operationIds)
        getPlugin(id).installed = getPlugin(id).version;
      state.operation = "complete";
      if (state.scene === "restart") go("complete");
      else render();
    }, 4200),
  );
}

function toast(message) {
  left.querySelector(".toast")?.remove();
  left.insertAdjacentHTML(
    "beforeend",
    `<div class="toast" role="status">${escapeHTML(message)}</div>`,
  );
  timers.push(setTimeout(() => left.querySelector(".toast")?.remove(), 2600));
}

document.addEventListener("click", (event) => {
  const sceneButton = event.target.closest("[data-scene]");
  if (sceneButton) return showScenario(sceneButton.dataset.scene);
  if (event.target.matches('[data-backdrop="menu"]')) return go("home");
  const button = event.target.closest("[data-action]");
  if (!button || button.disabled) return;
  const action = button.dataset.action;
  if (inlineMode && action === "expand") {
    const top = button.getBoundingClientRect().top;
    state.expanded =
      state.expanded === button.dataset.id ? null : button.dataset.id;
    state.selected = button.dataset.id;
    state.modelQuery = "";
    state.deviceChecked = false;
    render();
    const next = document.getElementById(button.id);
    const scroller = left.querySelector(".scroll-area");
    scroller.scrollTop += next.getBoundingClientRect().top - top;
    next.focus({ preventScroll: true });
    return;
  }
  if (inlineMode && action === "kind") {
    state.kind = button.dataset.id;
    state.expanded = null;
    state.query = "";
    render();
    left
      .querySelector(`[data-action="kind"][data-id="${state.kind}"]`)
      ?.focus({ preventScroll: true });
    left.querySelector(".scroll-area")?.scrollTo(0, 0);
    return;
  }
  if (inlineMode && action === "check-device") {
    state.deviceChecked = true;
    render();
    document
      .querySelector('[data-action="check-device"]')
      ?.focus({ preventScroll: true });
    return;
  }
  if (
    inlineMode &&
    [
      "manual",
      "policy",
      "source",
      "configure",
      "plan",
      "plan-updates",
      "restart-confirm",
    ].includes(action)
  ) {
    modalReturnFocus = button.id
      ? `#${button.id}`
      : `[data-action="${action}"]`;
  }
  if (action === "restart-confirm") {
    state.modal = action;
    render();
    return;
  }
  if (action === "clear-operation") {
    state.operation = null;
    render();
    return;
  }
  if (action === "server-menu")
    return go(state.scene === "entry" ? "home" : "entry");
  if (action === "close") return go("home");
  if (action === "back") return go(state.tab);
  if (action === "plugins") return go("catalog");
  if (action === "updates") return go("updates");
  if (action === "installed") return go("installed");
  if (action === "settings") return go("settings");
  if (action === "tab") return go(button.dataset.id);
  if (action === "detail") return go("details", button.dataset.id);
  if (action === "clear-search") {
    state.query = "";
    render();
    return;
  }
  if (action === "dismiss") {
    state.modal = null;
    render();
    return;
  }
  if (["manual", "policy", "source", "configure"].includes(action)) {
    state.modal = action;
    render();
    return;
  }
  if (action === "configured") {
    state.modal = null;
    render();
    toast("Plugin settings saved");
    return;
  }
  if (action === "check") {
    state.catalogOffline = false;
    if (state.scene === "offline") go("catalog");
    else if (inlineMode) render();
    toast("Catalog checked. You have the latest list.");
    return;
  }
  if (action === "plan" || action === "plan-updates") {
    state.modal = action === "plan-updates" ? "confirm-updates" : "confirm";
    if (action === "plan-updates")
      state.selected =
        updates().find((p) => state.selection.has(p.id))?.id || "qobuz";
    state.restart = "idle";
    render();
    return;
  }
  if (action === "save-policy") {
    state.automatic =
      document.querySelector('input[name="policy"]:checked').value ===
      "automatic";
    state.modal = null;
    render();
    toast("Update preference saved");
    return;
  }
  if (action === "example-url") {
    state.source =
      "https://example.invalid/studio-bridge/releases/v0.4.0/kalinka-plugin.json";
    document.querySelector("#source-url").value = state.source;
    return;
  }
  if (action === "inspect-source") {
    const value = document.querySelector("#source-url").value.trim();
    let valid = false;
    try {
      const url = new URL(value);
      valid = url.protocol === "https:" && !url.username && !url.password;
    } catch {}
    if (!valid) {
      document.querySelector("#source-error").textContent =
        "Enter a complete HTTPS release manifest URL.";
      return;
    }
    state.source = value;
    state.manualPreview = true;
    getPlugin("studio").version = "0.4.0";
    go("details", "studio");
    return;
  }
  if (action === "execute") {
    state.operationIds =
      state.modal === "confirm-updates"
        ? updates()
            .filter((p) => state.selection.has(p.id))
            .map((p) => p.id)
        : [state.selected];
    if (state.restart === "now") startRestart();
    else {
      state.operation = "waiting";
      if (inlineMode) {
        state.modal = null;
        render();
      } else go("restart");
    }
    return;
  }
  if (action === "restart-now") return startRestart();
  if (action === "operation") return go("restart");
});

document.addEventListener("input", (event) => {
  if (inlineMode && event.target.id === "model-search") {
    state.modelQuery = event.target.value;
    document.querySelector("#model-result").innerHTML =
      inlineCatalog.modelResult(getPlugin(state.selected));
    return;
  }
  if (event.target.id === "plugin-search") {
    state.query = event.target.value;
    document.querySelector(".plugin-list").innerHTML = listContent();
  }
});
document.addEventListener("change", (event) => {
  if (event.target.id === "more-scenes" && event.target.value)
    return showScenario(event.target.value);
  if (event.target.name === "restart") {
    state.restart = event.target.value;
    document.querySelector('[data-action="execute"]').textContent =
      state.restart === "idle" ? "Install when idle" : "Install & restart";
  }
  if (event.target.dataset.update) {
    event.target.checked
      ? state.selection.add(event.target.dataset.update)
      : state.selection.delete(event.target.dataset.update);
    const selected = updates().filter((p) => state.selection.has(p.id)).length;
    document.querySelector(".sticky-action .action-info").innerHTML =
      `${selected} ${selected === 1 ? "plugin" : "plugins"} selected<small>${selected ? "One restart for all selected updates" : "Choose an update above"}</small>`;
    document.querySelector('[data-action="plan-updates"]').disabled = !selected;
  }
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    if (state.modal) {
      state.modal = null;
      render();
    } else if (state.scene === "entry") go("home");
    else if (inlineMode && state.expanded) {
      const expanded = state.expanded;
      state.expanded = null;
      render();
      document
        .getElementById(`expand-${expanded}`)
        ?.focus({ preventScroll: true });
    } else if (inlineMode) go("home");
    else go("catalog");
    return;
  }
  if (event.key === "Tab") {
    const modal =
      document.querySelector(".dialog") ||
      document.querySelector(".server-sheet");
    if (!modal) return;
    const controls = [
      ...modal.querySelectorAll("button:not(:disabled),input,select,a[href]"),
    ];
    if (!controls.length) return;
    const index = controls.indexOf(document.activeElement);
    if (
      (event.shiftKey && index <= 0) ||
      (!event.shiftKey && (index === controls.length - 1 || index === -1))
    ) {
      event.preventDefault();
      controls[event.shiftKey ? controls.length - 1 : 0].focus();
    }
  }
});

document
  .querySelectorAll("[data-icon]")
  .forEach((el) => (el.outerHTML = icon(el.dataset.icon)));
document.querySelector("#queue-tracks").innerHTML = [
  ["Day after Day", "7:03"],
  ["Earth Girl", "3:31"],
  ["Second Song", "11:15"],
  ["Casting Me Away From You", "2:38"],
  ["Soon I Might Be Going", "9:14"],
  ["I’ll Love You Forever", "4:29"],
]
  .map(
    ([title, duration]) =>
      `<div class="track"><div class="queue-art"></div><div><strong>${title}</strong><p><span class="source-tag">♫</span>Neil Young</p></div><span class="duration">${duration}</span>${icon("drag")}</div>`,
  )
  .join("");
const [initialScene, initialId] = location.hash.slice(1).split(":");
showScenario(captions[initialScene] ? initialScene : "entry");
if (initialId) {
  state.selected = initialId;
  if (inlineMode) {
    state.expanded = initialId;
    state.kind = getPlugin(initialId).kind || "all";
  }
  render();
}
window.addEventListener("hashchange", () => {
  const [scene, id] = location.hash.slice(1).split(":");
  showScenario(captions[scene] ? scene : "entry");
  if (id) {
    state.selected = id;
    if (inlineMode) {
      state.expanded = id;
      state.kind = getPlugin(id).kind || "all";
    }
    render();
  }
});
