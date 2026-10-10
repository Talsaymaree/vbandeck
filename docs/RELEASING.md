# Releasing VBAN Deck

## Supported deliverables

- Android APK (`VBANDeck-Android-<version>.apk`)
- Steam Deck / Linux Flatpak (`VBANDeck-<version>.flatpak`)
- Decky Loader plugin (`VBANDeck-<version>.zip`)
- macOS archive, built and signed on macOS (`VBANDeck-<version>-macOS.zip`)

## Before tagging

1. Update the version in `flatpak/VERSION`, `android/app/build.gradle`, and `decky/package.json`.
2. Add the release notes to `CHANGELOG.md`.
3. Build and smoke-test each supported platform.
4. For Android, use a private release keystore; never publish the debug APK.
5. For macOS, archive in Xcode and sign/notarize before distributing outside the App Store.

### GitHub Actions secrets

Configure these in the repository's protected `release` environment before pushing a tag:

- `ANDROID_KEYSTORE_BASE64` — base64-encoded release keystore
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

## Publish

1. Commit the release changes and push `main`.
2. Create and push an annotated tag, for example `git tag -a v0.2.1 -m "VBAN Deck 0.2.1"` then `git push origin v0.2.1`.
3. The GitHub release workflow builds the signed Android APK and creates the draft release.
4. Upload the Flatpak, Decky ZIP, and signed/notarized macOS ZIP to that draft. Review the generated notes and publish it.

The release workflow deliberately does not fabricate unsigned production artifacts. A release is published only after the platform artifacts have been verified.
