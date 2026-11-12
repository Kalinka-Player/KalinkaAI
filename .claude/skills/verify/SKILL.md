---
name: verify
description: Build, launch, drive, and screenshot the Kalinka Flutter app on Linux desktop to verify UI changes at runtime. Use when a change needs visual/behavioral confirmation in the running app.
---

# Verify Kalinka app changes on Linux desktop

## Launch

The app keeps its saved connection settings and connects on its own, to the
server that `flutter.Kalinka.host` and `flutter.Kalinka.port` name in
`~/.local/share/com.example.kalinka/shared_preferences.json`. Where that is a
streamer on the network and it is up, nothing else is needed. Where it is this
machine, a server is usually already running on port 8000 (check
`ss -tlnp | grep 8000`); otherwise start one from the RpiPlayer repo with
`make dev-run KALINKA_PREFIX=$HOME/kalinka`.

Run from the checkout under test, as a background task with its output in a
file:

```bash
GDK_BACKEND=x11 flutter run -d linux --no-pub > run.log 2>&1
# wait for: "A Dart VM Service on Linux is available at: http://127.0.0.1:PORT/TOKEN=/"
```

`GDK_BACKEND=x11` puts the window on XWayland so XTEST input works. The
scripts below take that address as `ws://127.0.0.1:PORT/TOKEN=/ws`, and need a
python with `websockets`: `~/Source/RpiPlayer/.venv/bin/python` has it.

## Screenshot — widget inspector, not X grabs

`import`/`gnome-screenshot`/`grim` are unavailable or hang on this Wayland
session. `flutter screenshot --type=skia` emits an SKP binary, not a PNG. The
engine's `_flutter.screenshot` RPC no longer works either: the Linux build
renders with Impeller, and the call fails with "Could not capture image
screenshot" ("Compressed screenshots not supported for Impeller" in the run
log).

What works is the widget inspector's own screenshot, over the VM-service
websocket; `screenshot.py`, beside this file, does it:

```bash
~/Source/RpiPlayer/.venv/bin/python .claude/skills/verify/screenshot.py \
  ws://127.0.0.1:PORT/TOKEN=/ws out.png
```

It asks `ext.flutter.inspector.getRootWidgetTree` for the root and passes its
`valueId` to `ext.flutter.inspector.screenshot`. The PNG is in physical
pixels, and the script prints the device pixel ratio to divide by: 2048x1274
at a ratio of 2 is a 1024x637 window, narrow enough for the rail's icons to
stand over their labels and short enough for some of them to fold behind More.

## Text size — in the app's process, not the desktop's

`text_scale.py`, beside this file, gives the running app a system text scale
without touching the desktop's settings:

```bash
~/Source/RpiPlayer/.venv/bin/python .claude/skills/verify/text_scale.py \
  ws://127.0.0.1:PORT/TOKEN=/ws 1.4
```

It evaluates `PlatformDispatcher.instance._updateUserSettingsData(...)` inside
`dart:ui`, which is what the engine calls when the platform's settings change.
Only that process sees it, until it quits; pass 1 to put it back. Let a frame
or two pass before the screenshot.

## Drive — XTEST via python-xlib

No xdotool on this machine. `pip install python-xlib` into a scratch venv,
then fake pointer input on DISPLAY=:0. Find the app window by walking the
tree for WM name containing "kalinka" and **take the largest match** (a
20×20 icon window matches too). Click/scroll at window-relative fractions;
mouse wheel = buttons 4/5. Working click/scroll scripts from a past session:
`click.py` / `scroll.py` pattern — motion, then ButtonPress/Release with
`d.sync()` between.

Gotchas:
- The app opens on Home; search opens from the field under "What shall we play?", and the queue from QUEUE beside Up next.
- GTK CSD: the X window is bigger than the visible frame by invisible shadow
  extents — read the `_GTK_FRAME_EXTENTS` property and subtract before
  mapping fractions. Even then the client height can disagree with the
  engine frame; map fractions against the screenshot's pixel size
  (e.g. 2560x1440), anchored at the client origin.
- Programmatic window resize fails: mutter ignores both XConfigureWindow and
  _NET_MOVERESIZE_WINDOW for this (tiled/maximized) XWayland window. Don't
  burn time on responsive-width probes via resize.
- The session is the USER'S live Wayland desktop. When they are actively
  using it, GNOME's focus-stealing prevention blocks activation and XTEST
  clicks can land in their other windows — stop driving input and hand
  visual checks to them instead.
- Quit by stopping the `flutter run` task (it terminates the app).
