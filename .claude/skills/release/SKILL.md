---
name: release
description: Cut a new Kalinka app release — bump the version, write the changelogs, tag, and let the GitHub Actions pipeline build and publish the release. Use when the user asks to "release", "publish a release", "bump the version", "cut a version", or "make a new release".
---

# Kalinka release

Cuts a Kalinka app release. Covers a patch, minor, or major bump. The repo is
`madenvel/KalinkaAI`; a tag push triggers the release pipeline
(`.github/workflows/release.yml`), which builds everything and publishes to
GitHub Releases — nothing is built locally.

## Versioning

`pubspec.yaml` holds `version: <semver>+<build>` (e.g. `0.2.0+3`).
- **patch** `0.1.1 → 0.1.2`, **minor** `0.1.1 → 0.2.0`, **major** `0.1.1 → 1.0.0`.
- The **build number** (`+N`) increments by 1 every release, regardless of bump type.
- Android `versionCode = flutter.versionCode` = the build number. Only the
  universal APK is built (per-ABI splits dropped after 0.5.0 — their offset
  versionCodes blocked cross-variant upgrades). Name the fastlane changelog
  file after the plain build number (build `10` → `10.txt`).

## Steps

1. **Find the current version.** `grep '^version:' pubspec.yaml`. Decide the new
   semver per the bump type the user asked for, and increment the build number.

2. **Bump `pubspec.yaml`.** Edit the `version:` line to `<newsemver>+<newbuild>`.

3. **Write the changelogs.**
   - Add a `## <newsemver>` section to `CHANGELOG.md` (Added / Changed / Fixed,
     curated and user-facing, summarizing `git log <prev-tag>..HEAD --oneline`).
     The pipeline pulls this section into the GitHub Release body; without it
     the body is footer + auto-notes only.
   - Create `fastlane/metadata/android/en-US/changelogs/<build>.txt` (plain
     build number, e.g. `10.txt`). Short, bulleted, user-facing.

4. **Commit, tag, push.** The pipeline builds from the tag, so commit and tag
   *before* pushing.
   ```bash
   git add pubspec.yaml CHANGELOG.md fastlane/metadata/android/en-US/changelogs/<build>.txt
   git commit -m "Bump version to <newsemver>"   # no trailer, see CONTRIBUTING.md
   git tag -a v<newsemver> -m "Kalinka <newsemver>"
   git push origin main && git push origin v<newsemver>
   ```
   `main` is protected but the maintainer's pushes bypass the rule — a
   "Bypassed rule violations" notice on push is expected, not an error.

5. **Watch the pipeline.** The tag push triggers `.github/workflows/release.yml`
   (~8 min): it verifies tag == pubspec version, builds the signed universal
   APK, Linux tarball, Windows zip + Inno Setup installer, and the kalinka-web
   .deb, then publishes the GitHub Release with md5.txt and the version-less
   alias assets (`kalinka-android-universal.apk` etc.) for permanent
   latest-download links. NEVER build locally.
   ```bash
   gh run list --workflow=release.yml --limit 1   # then monitor to completion
   ```

6. **Verify the release.** `gh release view v<v>` — check all assets are
   attached and the body starts with the CHANGELOG section. Expected signing
   cert SHA-256 (printed in the build-android job log):
   `79e0051195d444fd531637202870223455fb436b80b75d55ce2c133aa33e11fb`.

## Notes

- We ship: universal APK, Linux tarball, Windows zip + setup.exe, kalinka-web
  .deb, md5.txt, plus version-less aliases. No per-ABI APKs (dropped after
  0.5.0 — offset versionCodes blocked cross-variant upgrades; IzzyOnDroid
  rejected the app so its 30 MB budget no longer matters).
