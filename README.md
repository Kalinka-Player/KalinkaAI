<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/kalinka_logo.svg">
  <img src="docs/images/kalinka_logo_light.svg" alt="Kalinka" width="380">
</picture>

### The Kalinka remote control

The app for Kalinka, a self-hosted music system. It runs on Android, Windows, macOS, Linux and in the browser. Ask for a mood, get a queue.

[![Latest release](https://img.shields.io/github/v/release/Kalinka-Player/KalinkaAI?label=release&color=2ea043)](https://github.com/Kalinka-Player/KalinkaAI/releases/latest)
[![License](https://img.shields.io/badge/code-Apache--2.0-2ea043)](LICENSE)

**[Google Play](https://play.google.com/store/apps/details?id=org.kalinka.kalinka) · [Downloads](https://github.com/Kalinka-Player/KalinkaAI/releases/latest) · [Kalinka server](https://github.com/Kalinka-Player/KalinkaPlayer) · [kalinkaplayer.com](https://kalinkaplayer.com)**

<img src="docs/images/demo.gif" alt="Semantic search demo: searching for 'something melancholic for tonight'" width="280">

</div>

## What is it

This app is the remote. The music lives on a [Kalinka server](https://github.com/Kalinka-Player/KalinkaPlayer), which runs on a Raspberry Pi or a Linux computer on your network. The app plays nothing without one, so [install the server](https://github.com/Kalinka-Player/KalinkaPlayer#installation) first. The app then finds it by itself, or takes its address by hand.

Search takes descriptions as well as names. Ask for *"something melancholic for tonight"* and it finds tracks that fit, all on your own hardware. No cloud, no subscription, no account.

<a id="-install"></a>

## Install

### Android

Install Kalinka from [Google Play](https://play.google.com/store/apps/details?id=org.kalinka.kalinka), which keeps it up to date.

<a href="https://play.google.com/store/apps/details?id=org.kalinka.kalinka"><img src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" alt="Get it on Google Play" height="54"></a>

Without Google Play, [Obtainium](https://github.com/ImranR98/Obtainium) installs the app from GitHub Releases and keeps it up to date. Install Obtainium, then tap this badge on your phone:

<a href="https://apps.obtainium.imranr.dev/redirect.html?r=obtainium://add/https://github.com/Kalinka-Player/KalinkaAI"><img src="https://raw.githubusercontent.com/ImranR98/Obtainium/main/assets/graphics/badge_obtainium.png" alt="Get it on Obtainium" height="54"></a>

Or download [`kalinka-android-universal.apk`](https://github.com/Kalinka-Player/KalinkaAI/releases/latest/download/kalinka-android-universal.apk) on the phone and open it. Android asks once to allow installs from your browser. To update, download and open the newer APK the same way.

The APKs on GitHub Releases are signed with the Kalinka release key. Its certificate SHA-256, which Obtainium can pin:

```
79e0051195d444fd531637202870223455fb436b80b75d55ce2c133aa33e11fb
```

### Windows

Download and run [`kalinka-windows-x64-setup.exe`](https://github.com/Kalinka-Player/KalinkaAI/releases/latest/download/kalinka-windows-x64-setup.exe). The installer is not code-signed, so Windows may warn about it: choose **More info → Run anyway**.

### Linux

Download [`kalinka-linux-x64.tar.gz`](https://github.com/Kalinka-Player/KalinkaAI/releases/latest/download/kalinka-linux-x64.tar.gz), extract it and run the `kalinka` binary. `./install.sh` adds a launcher icon, and `./install.sh --uninstall` removes it.

### macOS

Download [`kalinka-macos-beta.dmg`](https://github.com/Kalinka-Player/KalinkaAI/releases/latest/download/kalinka-macos-beta.dmg), open it and drag Kalinka to Applications. It runs on Intel and Apple Silicon. The build is a beta and is not notarized, so the first launch needs your approval: right-click the app and choose **Open**, or allow it in **System Settings → Privacy & Security**.

### Browser

Nothing to install: open `http://<server-address>:8000`. The server serves the web player itself, and the browser can play the music too.

## Getting started

1. [Install the server](https://github.com/Kalinka-Player/KalinkaPlayer#installation). The quickest way is a ready-made image for a Raspberry Pi or a PC, which starts straight into a working player.
2. Install the app, or open the browser player.
3. Follow the setup the app shows the first time it connects.

A streamer that is not on your network yet can be set up from the app, over Bluetooth or the streamer's own temporary Wi-Fi. [Connect your streamer to the network](https://github.com/Kalinka-Player/KalinkaPlayer/blob/main/docs/installation.md#connect-your-streamer-to-the-network) has the steps, including how to do it from a laptop without the app.

The [installation guide](https://github.com/Kalinka-Player/KalinkaPlayer/blob/main/docs/installation.md) covers the rest: the images, virtual machines, the one-command install, adding music and outputs in other rooms, and troubleshooting.

## License

The source code is under **Apache-2.0**: see [LICENSE](LICENSE) and [NOTICE](NOTICE).

The visual assets are not. Icons, logos, images and related artwork are covered by the [Kalinka Asset License](LICENSE-ASSETS) and require the author's permission to use or redistribute. You may distribute the code under Apache-2.0, but replace the branding with your own unless you have that permission.

Bundled IBM Plex fonts are under the SIL Open Font License 1.1: see [`assets/fonts/OFL-IBMPlex.txt`](assets/fonts/OFL-IBMPlex.txt).

Permission contact: MadEnvel &lt;support@kalinkaplayer.com&gt;
