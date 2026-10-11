# VBAN Deck for Nintendo Switch (experimental)

This directory begins the Switch port as a small, standalone homebrew proof of
concept. It sends a continuous 440 Hz test tone as a valid VBAN PCM stream.
That verifies the network, configuration, packet format, and receiver before
we attempt CFW-only game-audio capture.

It is **not** a game-audio sender yet. A standard `.nro` does not have access
to audio produced by another running title. The planned game-audio sender is a
separate Atmosphere sysmodule which will use the console recording-audio path.

## Build prerequisites

Use devkitPro with `devkitA64`, `libnx`, and `switch-tools` installed. From a
devkitPro shell:

```sh
cd switch/poc
make
```

The output is `VBANDeckSwitchTest.nro`.

## Configure and run

1. Copy the resulting `.nro` to `sdmc:/switch/VBANDeckSwitchTest/`.
2. Copy [`config.ini`](poc/config.ini) to
   `sdmc:/switch/vbandeck-switch/config.ini` and edit `host` to the LAN IPv4
   address of the VBAN receiver.
3. In Voicemeeter or another receiver, listen for the configured stream name
   (default `SwitchTest`) on UDP port `6980`.
4. Launch the `.nro` from the Homebrew Menu. You should hear a 440 Hz tone.
   Press **Plus** to exit.

The test sender is intended only for a CFW/homebrew development environment.
It does not install or modify the console firmware.

## Next phase

After the tone test succeeds on a real console, the work is to create a
CFW-only sysmodule and replace `generate_tone()` with 48 kHz stereo PCM from
the game-recording service. The VBAN sender and configuration format can stay
the same. This path will have title compatibility limits: titles that disable
the system video recorder may not expose usable game audio.
