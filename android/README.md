# VBAN Deck for Android

VBAN Deck is the Android port based on the Steam Deck Decky plugin settings and VBAN behavior. It supports Android 14/15 media-projection lifecycle handling.

## What it does

- Captures Android playback audio using `AudioPlaybackCapture` + `MediaProjection`.
- Sends native VBAN AUDIO packets over UDP.
- Fixed format: 48 kHz, stereo, signed 16-bit PCM.
- Uses 256 audio frames per packet, matching the Steam Deck build.
- Default VBAN port: 6980.
- Destination IP, port and stream name are saved locally.

## Requirements

- Android 10 / API 29 or newer.
- The source app/game must allow playback capture. Apps can opt out; those apps may produce silence.
- Receiver must be on a reachable network/VPN and configured for the same VBAN stream name.

## Build in Android Studio

1. Open this folder in Android Studio.
2. Let Gradle sync and install Android SDK 35 if prompted.
3. Build > Build Bundle(s) / APK(s) > Build APK(s).
4. Debug APK will be under `app/build/outputs/apk/debug/app-debug.apk`.

## Command line

With Android SDK Platform 35 and Build Tools 35 available:

```bash
./gradlew assembleDebug
```

On Windows, use `gradlew.bat :app:assembleDebug` instead. Android Studio detects the included Gradle wrapper automatically.

The included GitHub Actions workflow also produces `app-debug.apk` as a downloadable artifact.

## Release signing

The debug APK is suitable for personal testing and is signed with the Android debug key. Do not publish it as a production release. Before a public Android release, create a private upload/release keystore, keep it out of Git, add a `release` signing configuration locally or through protected CI secrets, and build `:app:assembleRelease`.

## Notes

Android 14+ requires user consent for each MediaProjection capture session, so the system capture prompt appears each time streaming starts.
