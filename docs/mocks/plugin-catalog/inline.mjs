// Alternative presentation only. Shared fixtures and simulated operations live
// in prototype.mjs; neither mock calls the server or downloads a package.
export function createInlineCatalog({
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
  escapeHTML,
}) {
  const busy = () => ["waiting", "restarting"].includes(state.operation);

  function status(p) {
    if (state.operationIds.includes(p.id) && busy())
      return state.operation === "waiting" ? "Waiting for idle" : "Installing…";
    if (p.blocked) return "Needs server 6.0 · SDK 4.0";
    if (p.planned) return "Proposed · no release available";
    if (p.manual) return "Unregistered · manual updates";
    if (p.bundled)
      return p.device ? "Included · check your model" : "Included with Kalinka Player";
    if (p.installed === p.version) return `Installed · ${p.version}`;
    if (p.installed) return `Update available · ${p.installed} → ${p.version}`;
    return "";
  }

  function panel(p, update = false) {
    const eligible =
      !p.planned && !p.blocked && !p.bundled && p.installed !== p.version;
    const compatibility = p.blocked
      ? "Needs server ≥ 6.0 and SDK ≥ 4.0, < 5. This server: 5.4.1 / SDK 3.6."
      : p.bundled
        ? "Updated with your Kalinka Player server, not separately."
        : p.manual
          ? "Not in the catalog. New releases must be installed manually."
          : "Server ≥ 5.0 · SDK ≥ 3.6, < 4. Your server: 5.4.1 / SDK 3.6 ✓";
    const title = p.blocked
      ? "Requirements not met"
      : p.manual
        ? "Manual updates only"
        : p.bundled
          ? "Managed by Kalinka Player"
          : "Compatible with this server";
    let action = p.planned
      ? btn("blocked", "Not released", "secondary", "disabled")
      : p.blocked
        ? btn("blocked", "Server update required", "primary", "disabled")
        : eligible
          ? btn(
              "plan",
              p.manual
                ? "Install this release"
                : p.installed
                  ? "Update plugin"
                  : "Install plugin",
              "primary",
              `id="install-${p.id}"`,
            )
          : btn(
              "configure",
              "Configure",
              "secondary",
              `id="configure-${p.id}"`,
            );
    if (eligible && (busy() || state.catalogOffline))
      action = btn(
        "blocked",
        busy() ? "Installation in progress" : "Catalog unavailable",
        "primary",
        "disabled",
      );
    return `<div id="panel-${p.id}" class="inline-panel" role="region" aria-labelledby="expand-${p.id}" ${state.expanded === p.id ? "" : "hidden"}>
      ${p.device ? deviceDetails(p) : `<p class="inline-lede">${p.long || p.description}</p><p class="source-device-note">${icon(p.kind === "device" ? "speaker" : "music")}${p.kind === "device" ? "Optional device controls · check hardware support with the author" : "Adds a music source · no amplifier-specific support needed"}</p>`}
      <dl class="inline-facts">
        <div><dt>Created by</dt><dd>${p.creator}</dd></div>
        <div><dt>${p.bundled ? "Bundle" : "Release"}</dt><dd>${p.version}${p.size ? ` · ${p.size}` : ""}</dd></div>
        <div><dt>Server platforms</dt><dd>${p.planned ? "Not verified" : p.platform || "Supported Kalinka Player servers"}</dd></div>
        <div><dt>Publisher and maturity</dt><dd>${p.tier} · ${p.experimental ? "Experimental" : p.manual ? "Not verified" : "Stable"}</dd></div>
      </dl>
      ${p.planned ? "" : `<div class="inline-compatibility ${p.blocked ? "warning" : ""}">${icon(p.blocked ? "alert" : p.manual || p.bundled ? "info" : "check-circle")}<div><strong>${title}</strong><p>${compatibility}</p></div></div>`}
      ${p.notes ? `<section class="inline-notes"><h3>${p.manual ? "Updates" : `What’s new in ${p.version}`}</h3><p>${p.notes}</p></section>` : ""}
      <div class="inline-actions"><button class="text-button" data-action="source" id="publisher-${p.id}">Source & license ${icon("external")}</button>${update ? `<span class="inline-batch-hint">Select above, then update below</span>` : action}</div>
      ${eligible && !update ? `<p class="inline-footnote">${p.manual ? "Only install code from a creator you trust." : "Dependencies checked before install."} One server restart to finish.</p>` : ""}
    </div>`;
  }

  function row(p, update = false) {
    const label = status(p);
    return `<article class="inline-item ${state.expanded === p.id ? "expanded" : ""}">
      <div class="inline-header">
        ${update ? `<label class="inline-select"><span class="sr-only">Select ${p.name} update</span><input type="checkbox" data-update="${p.id}" ${state.selection.has(p.id) ? "checked" : ""} ${busy() ? "disabled" : ""}></label>` : ""}
        <button id="expand-${p.id}" class="inline-toggle" data-action="expand" data-id="${p.id}" aria-expanded="${state.expanded === p.id}" aria-controls="panel-${p.id}">
          ${tile(p)}<span class="plugin-copy"><span class="plugin-name">${p.name}</span><span class="plugin-description">${p.id === "musiccast" ? "Yamaha · volume, power & configured input" : p.description}</span>${label ? `<span class="inline-state ${p.blocked ? "warning" : p.installed && p.installed !== p.version && !p.manual ? "update" : ""}">${label}</span>` : ""}</span><span class="expand-affordance">${icon("chevron-down")}</span>
        </button>
      </div>${state.expanded === p.id ? panel(p, update) : `<div id="panel-${p.id}" hidden></div>`}
    </article>`;
  }

  function modelResult(p) {
    if (state.modelQuery.trim())
      return `<strong>Model support not verified</strong><p>No verified record for “${escapeHTML(state.modelQuery.trim())}” in this sample catalog. Not listed does not mean unsupported. Check the author’s model list${p.planned ? " when published" : " or test this device’s connection"}.</p>`;
    return `<strong>${p.planned ? "No supported-model list yet" : "Check your exact model"}</strong><p>${p.device.models}</p>`;
  }

  function deviceDetails(p) {
    return `<div class="device-summary"><p class="eyebrow">DEVICE CONTROL · ${p.device.brand}</p><p class="inline-lede">${p.planned ? p.long : "Adds controls for your amplifier or AVR. It does not add a music source or change where audio is played."}</p><div class="capability-list">${p.device.controls.map((c) => `<span>${icon("check")}${c}</span>`).join("") || `<span class="unverified">Control capabilities not verified</span>`}</div><p class="device-transport">${icon("link")}${p.device.transport}</p><p class="device-limits">${p.device.limits}</p></div>
    <section class="model-lookup"><h3>Will it work with my device?</h3><label class="search-box">${icon("search")}<input id="model-search" type="search" value="${escapeHTML(state.modelQuery)}" placeholder="Search an exact model" aria-label="Search supported models" autocomplete="off"></label><div id="model-result" class="model-result" role="status">${modelResult(p)}</div>${!p.planned ? `<button id="check-device" class="text-button" data-action="check-device">${icon("wifi")}Check connected device</button><p class="device-probe-note">${state.deviceChecked ? "Demo result: network API responds; volume and power are reported. Exact model remains unverified. No commands were sent to hardware." : "Read-only connection check · no volume or power changes. Simulated in this mock."}</p>` : ""}</section>`;
  }

  function filters() {
    return `<div class="kind-filters" role="group" aria-label="Plugin type">${[
      ["all", "All"],
      ["source", "Input sources"],
      ["device", "Device control"],
    ]
      .map(
        ([id, name]) =>
          `<button data-action="kind" data-id="${id}" aria-pressed="${state.kind === id}">${id === "source" ? icon("music") : id === "device" ? icon("speaker") : ""}${name}</button>`,
      )
      .join(
        "",
      )}</div><p class="kind-description">${state.kind === "source" ? "Music services and libraries, independent of your amplifier." : state.kind === "device" ? "Optional amplifier and AVR controls. Check model support." : "Music sources and optional controls for your hi-fi."}</p>`;
  }

  function listContent() {
    const query = state.query.trim().toLowerCase();
    const pool = (
      state.tab === "installed"
        ? installed()
        : visiblePlugins().filter((p) => !p.manual && p.id !== "dummydevice")
    ).filter(
      (p) =>
        (state.kind === "all" || p.kind === state.kind) &&
        `${p.name} ${p.description} ${p.tier} ${p.device?.brand || ""} ${(p.device?.controls || []).join(" ")}`
          .toLowerCase()
          .includes(query),
    );
    if (!pool.length)
      return `<div class="empty">${icon("search")}<h2>No matching plugins</h2><p>Try another name or choose All plugin types.</p></div>`;
    const groups =
      state.kind === "all"
        ? [
            ["Input sources", pool.filter((p) => p.kind === "source")],
            ["Device control", pool.filter((p) => p.kind === "device")],
          ]
        : state.tab === "installed"
          ? [
              [
                "Independent plugins",
                pool.filter((p) => !p.bundled && !p.manual),
              ],
              ["Included with Kalinka Player", pool.filter((p) => p.bundled)],
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
    return groups
      .filter(([, items]) => items.length)
      .map(
        ([name, items]) =>
          `<h2 class="group-label">${name} <span>${items.length}</span></h2>${items.map((p) => row(p)).join("")}`,
      )
      .join("");
  }

  function operation() {
    if (!state.operation) return "";
    const waiting = state.operation === "waiting";
    const done = state.operation === "complete";
    const failed = state.operation === "failed";
    const title = waiting
      ? "Ready when playback stops"
      : done
        ? "Installation complete"
        : failed
          ? "Update failed · previous version restored"
          : "Restarting · reconnecting to Kalinka Player";
    const description = waiting
      ? "Package checked. Your music keeps playing."
      : done
        ? "Plugins are ready. Your settings are preserved."
        : failed
          ? "Qobuz Connect 1.4.0 is still installed. Automatic retry is paused."
          : "Progress is saved on the server. You can keep browsing.";
    return `<aside class="inline-operation ${done ? "done" : ""} ${failed ? "warning" : ""}" role="status">${icon(waiting ? "clock" : done ? "check-circle" : failed ? "alert" : "refresh")}<div><strong>${title}</strong><p>${description}</p></div>${waiting ? btn("restart-confirm", "Restart now", "text-button") : done || failed ? `<button class="icon-button" data-action="clear-operation" aria-label="Dismiss installation status">${icon("close")}</button>` : ""}</aside>`;
  }

  function updateContent() {
    const available = updates();
    const selected = available.filter((p) => state.selection.has(p.id));
    return `<div class="scroll-area" data-view="updates"><div class="updates-intro"><p>${available.length ? `${available.length} updates for this server` : "Your plugins are up to date"}</p><button class="text-button" data-action="policy">${icon("settings")}Auto updates</button></div><div class="plugin-list">${available.map((p) => row(p, true)).join("")}</div><div class="notice">${icon("info")}<span>Included plugins update with Kalinka Player. Unregistered plugins stay manual.</span></div><div class="update-footer">${state.automatic ? "Official stable releases update while idle, 03:00–06:00." : "Automatic updates are off. You choose when to install."}</div></div><div class="sticky-action"><div class="action-info">${selected.length} plugins selected<small>One restart for all selected updates</small></div>${btn("plan-updates", "Update selected", "primary", selected.length && !busy() && !state.catalogOffline ? "" : "disabled")}</div>`;
  }

  function screen() {
    return `<div class="screen">${topbar()}<div class="page-heading"><p class="eyebrow">ON THIS SERVER</p><div class="heading-row"><h1>Plugins</h1><button class="text-button" data-action="manual">${icon("link")}Install from URL</button></div><p class="heading-description">Music sources and controls for your hi-fi.</p></div>${tabs()}${operation()}${state.catalogOffline ? `<div class="notice offline">${icon("wifi")}<span>Catalog unavailable · showing yesterday’s list.</span><button data-action="check">Retry</button></div>` : ""}
    ${
      state.tab === "updates"
        ? updateContent()
        : `<div class="scroll-area" data-view="${state.tab}">
      ${filters()}<div class="search-wrap"><label class="search-box">${icon("search")}<input id="plugin-search" type="search" value="${escapeHTML(state.query)}" placeholder="${state.kind === "device" ? "Search brand, plugin or control" : "Search plugins"}" aria-label="Search plugins" autocomplete="off"></label></div>
      <div class="inline-hint">Tap a plugin to see details and actions</div><div class="plugin-list">${listContent()}</div></div><div class="catalog-foot"><span>${state.catalogOffline ? "Last checked yesterday" : "Catalog checked just now"}</span><button class="text-button" data-action="check">${icon("refresh")}Check again</button></div>`
    }${miniPlayer()}</div>`;
  }
  return { row, screen, listContent, modelResult };
}
