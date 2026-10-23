# Changelog

All notable changes to VBAN Deck are documented here.

## [0.2.2] - 2026-10-23

### Fixed

- Decky status polling no longer resets the destination IP or other settings while editing in Game Mode.
- Removed the preset destination IP from Decky, Flatpak, Android, and macOS; fresh installs require the user's receiver address.
- Decky displays settings validation and save errors when starting a stream instead of a generic Python exception.
- Fixed Decky settings initialization to use the supported plugin settings directory constant.

## [0.2.1] - 2026-10-10

### Added

- A shared VBAN Deck logo and native app icon assets for Android, Flatpak, Decky Loader, and macOS.
- A tag-driven GitHub release workflow and release checklist.

### Changed

- Unified the public app name as **VBAN Deck**.
- Aligned supported desktop, Decky, and Android release versioning at 0.2.1.

### Removed

- Unfinished iOS and iPadOS source and the duplicate iPad Xcode project.

## [0.2.0] - 2026-08-15

- Initial Flatpak release.
