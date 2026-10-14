---
name: verify
description: Build, launch, drive, and screenshot the Kalinka Flutter app on Linux desktop to verify UI changes at runtime. Use when a change needs visual/behavioral confirmation in the running app.
---

# Verify Kalinka app changes on Linux desktop

## Launch

A Kalinka server is usually already running on port 8000 (check
`ss -tlnp | grep 8000`); otherwise start one from the RpiPlayer repo with
`make dev-run KALINKA_PREFIX=$HOME/kalinka`. The app keeps its saved
connection settings, so it connects on its own.

```bash
cd ~/Source/KalinkaAI-1
GDK_BACKEND=x11 flutter run -d linux --no-pub   # background task
# wait for: "A Dart VM Service on Linux is available at: http://127.0.0.1:PORT/TOKEN=/"
```

`GDK_BACKEND=x11` puts the window on XWayland so XTEST input works.

## Screenshot — VM service, not X grabs

`import`/`gnome-screenshot`/`grim` are unavailable or hang on this Wayland
session. `flutter screenshot --type=skia` emits an SKP binary, not a PNG.
What works: the engine's `_flutter.screenshot` RPC over the VM-service
websocket (returns base64 PNG of the Flutter frame):

```python
# python with `websockets` (RpiPlayer venv has it): ws://127.0.0.1:PORT/TOKEN=/ws
await ws.send(json.dumps({'jsonrpc':'2.0','id':1,'method':'_flutter.screenshot','params':{}}))
# response: result.screenshot = base64 PNG
```

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
  engine frame; map fractions against the engine screenshot's pixel size
  (e.g. 2560x1440), anchored at the client origin.
- Programmatic window resize fails: mutter ignores both XConfigureWindow and
  _NET_MOVERESIZE_WINDOW for this (tiled/maximized) XWayland window. Don't
  burn time on responsive-width probes via resize.
- The session is the USER'S live Wayland desktop. When they are actively
  using it, GNOME's focus-stealing prevention blocks activation and XTEST
  clicks can land in their other windows — stop driving input and hand
  visual checks to them instead.
- Quit by stopping the `flutter run` task (it terminates the app).
