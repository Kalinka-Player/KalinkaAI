<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/kalinka_logo.svg">
  <img src="docs/images/kalinka_logo_light.svg" alt="Kalinka" width="380">
</picture>

### The Kalinka remote control

Cross-platform app for the self-hosted Kalinka music system — Android, Windows, Linux desktop and the browser. Ask for a mood, get a queue.

[![Release](https://github.com/Kalinka-Player/KalinkaAI/actions/workflows/release.yml/badge.svg)](https://github.com/Kalinka-Player/KalinkaAI/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/Kalinka-Player/KalinkaAI?label=release&color=2ea043)](https://github.com/Kalinka-Player/KalinkaAI/releases/latest)
[![License](https://img.shields.io/badge/code-Apache--2.0-2ea043)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Windows%20%7C%20Linux%20%7C%20Web-2ea043)](#-install)

**[📱 Download](https://github.com/Kalinka-Player/KalinkaAI/releases/latest) · [🖥️ Music server](https://github.com/Kalinka-Player/KalinkaPlayer) · [💿 Flash an image](https://github.com/Kalinka-Player/KalinkaPlayer/releases?q=kalinka-image-v&expanded=true) · [🌐 kalinkaplayer.com](https://kalinkaplayer.com)**

<img src="docs/images/demo.gif" alt="Semantic search demo: searching for 'something melancholic for tonight'" width="280">

</div>

---

## What is it

> **Kalinka needs a server.** This app is the remote: it plays nothing without a Kalinka server on your network. Install the server first — **[installation steps](https://github.com/Kalinka-Player/KalinkaPlayer#installation)**.

This repository is the **app** — the remote control. The music is served by the separate [Kalinka Music Server](https://github.com/Kalinka-Player/KalinkaPlayer): a lightweight backend with a C++/ALSA audio engine, the library indexer and metadata-enrichment pipeline, and the CLAP semantic-search engine.

You need both. The app finds a server on your network over mDNS, or takes an address by hand. If you would rather not install anything at all, the server also serves a browser player — open `http://<server-ip>:8000` and it plays there.

Semantic search turns a phrase like *"something melancholic for tonight"* into matching tracks, running on your own hardware. No cloud, no subscription, no account.

## 📱 Install

### Android

**With Obtainium (recommended).** [Obtainium](https://github.com/ImranR98/Obtainium) installs the app straight from GitHub Releases and keeps it up to date. Install Obtainium, then tap this badge on your phone; it fills in this repository for you:

<a href="https://apps.obtainium.imranr.dev/redirect.html?r=obtainium://add/https://github.com/Kalinka-Player/KalinkaAI"><img src="https://raw.githubusercontent.com/ImranR98/Obtainium/main/assets/graphics/badge_obtainium.png" alt="Get it on Obtainium" height="54"></a>

**Or download the APK yourself.** On the phone, download [`kalinka-android-universal.apk`](https://github.com/Kalinka-Player/KalinkaAI/releases/latest/download/kalinka-android-universal.apk) from the latest release and open it. Android asks once to allow installs from your browser. To update later, download and open the new APK the same way.

All release APKs are signed with the Kalinka release key. Certificate SHA-256, which Obtainium can pin:

```
79e0051195d444fd531637202870223455fb436b80b75d55ce2c133aa33e11fb
```

### Other platforms

| Platform | What to do |
|---|---|
| 🪟 **Windows (x64)** | Download and run [`kalinka-windows-x64-setup.exe`](https://github.com/Kalinka-Player/KalinkaAI/releases/latest/download/kalinka-windows-x64-setup.exe). The installer is not code-signed, so Windows may warn about it: choose **More info → Run anyway**. |
| 🐧 **Linux desktop (x64)** | Download [`kalinka-linux-x64.tar.gz`](https://github.com/Kalinka-Player/KalinkaAI/releases/latest/download/kalinka-linux-x64.tar.gz), extract it and run `./install.sh` to add a launcher icon (`--uninstall` reverses it), or just run the `kalinka` binary. |
| 🌐 **Browser** | Nothing to install: open `http://<server-address>:8000`. The server serves the web player itself, and the browser can play the music too. |

Everything is also on the [releases page](https://github.com/Kalinka-Player/KalinkaAI/releases).

## 🚀 Getting started

1. **[Install the server](https://github.com/Kalinka-Player/KalinkaPlayer#installation)** — required. The quickest route is a ready-made image for a Raspberry Pi or any x86-64 box; it starts straight into a working player.
2. **Install the app** as described [above](#-install), or use a browser.
3. **Follow the setup wizard** the first time you connect.

| | |
|---|---|
| [Installing the server](https://github.com/Kalinka-Player/KalinkaPlayer/blob/main/docs/installation.md) | Images for a Raspberry Pi or PC, virtual machines, the one-command install, adding music and outputs in other rooms |
| [First-run setup](docs/first-run-setup.md) | What the setup wizard asks for, step by step, in the app and in the browser, and how updates work |
| [App manual](docs/app-manual.md) | Illustrated tour — the wizard, the server chip and settings, music folders, AI search and queueing |

## License

Source code is **Apache-2.0** — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

The visual assets are not. Icons, logos, images and related artwork are covered by the [Kalinka Asset License](LICENSE-ASSETS) and require the author's permission to use or redistribute. You may distribute the code under Apache-2.0, but replace the branding with your own unless you have that permission.

Bundled IBM Plex fonts are under the SIL Open Font License 1.1 — see [`assets/fonts/OFL-IBMPlex.txt`](assets/fonts/OFL-IBMPlex.txt).

Permission contact: MadEnvel &lt;support@kalinkaplayer.com&gt;
