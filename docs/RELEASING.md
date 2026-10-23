# Releasing VBAN Deck

## Supported deliverables

- Steam Deck / Linux Flatpak (`VBANDeck-<version>.flatpak`)
- Decky Loader plugin (`VBANDeck-<version>.zip`)

## Before tagging

1. Update `flatpak/VERSION`, `decky/package.json`, and the Flatpak AppStream release metadata.
2. Add the release notes to `CHANGELOG.md` and `docs/releases/v<version>.md`.
3. Build the Decky ZIP with `decky/build-decky.sh` and the Flatpak with `flatpak/build-release.sh`.
4. Test both builds, including entering the receiver IP, starting and stopping audio, and restoring saved settings.

## Publish

1. Commit the release changes and push `main`.
2. Create and push an annotated version tag, for example `git tag -a v0.2.3 -m "VBAN Deck 0.2.3"` then `git push origin v0.2.3`.
3. Manually run the **Draft release** workflow from GitHub Actions with that tag. It checks both versions and creates a draft using the patch notes for that version.
4. Upload the tested Flatpak and Decky ZIP to the draft. Review the patch notes and publish it.

The workflow creates a draft only. Publish after both tested downloads are attached and verified.
