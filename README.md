# QuietBar

[![CI](https://github.com/pedroscardua/my-noise/actions/workflows/ci.yml/badge.svg)](https://github.com/pedroscardua/my-noise/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A native macOS menu bar app for a personal noise mix. Ten adjustable layers, local audio, no browser, no account, no runtime network requests.

**[Português](docs/README.pt-BR.md)** · [User guide](docs/USAGE.md) · [Architecture](docs/ARCHITECTURE.md) · [Contributing](CONTRIBUTING.md)

## Features

- Compact menu bar popover with playback, volume, presets and sleep timer.
- Native Liquid Glass on macOS 26; translucent system material on earlier macOS.
- Full controls for ten frequency layers, stereo width, compression and gentle movement.
- Named presets, JSON import/export, and limited myNoise parameter-link import.
- Sleep timer with a three-second fade. Starts paused; closing the panel keeps playback running.
- Original noise generated during the build. No third-party recordings or audio downloads.

The interface is currently in Brazilian Portuguese. The project is independent of myNoise. Importing a link transfers settings only: **the sound is different**. See [audio provenance](docs/AUDIO.md).

## Build and run

Requires macOS, Apple's Swift/Clang tools with the **macOS 26 SDK** (Xcode 26 or corresponding Command Line Tools), and Python 3 for tests. Runtime deployment target: macOS 13+. macOS 13–25 compatibility is not yet verified on physical machines. Builds target the current Mac's architecture; CI covers Apple Silicon and Intel on macOS 26.

```sh
git clone https://github.com/pedroscardua/my-noise.git
cd my-noise
./build.sh
open build/QuietBar.app
```

Click the waveform icon in the menu bar. Choose **Abrir controles** for the full panel. To install, drag `build/QuietBar.app` into Applications. Quit any previous QuietBar instance first.

The build generates about 131 MiB of PCM audio on disk; those files are streamed through fixed buffers. Disk size is not RAM consumption. No universal memory/CPU figures are promised; measure on your Mac.

## Downloads

[Releases](https://github.com/pedroscardua/my-noise/releases) provide source tags and, when available, an Apple Silicon app archive. Builds are ad-hoc signed, **not Apple-notarized**. macOS may block downloaded builds; building from source is the recommended route. See [release and signing notes](docs/RELEASING.md).

## Development

```sh
./Tests/run_background_checks.sh
python3 scripts/check_repository.py
```

Tests generate their own audio, render silently, isolate saved state, and do not show windows. They check mixer output against an independent sample reference, stream stability, presets, animation, timer fade, missing audio, and quick-panel synchronization/layout. They do not replace listening and interactive accessibility testing.

| Path | Purpose |
| --- | --- |
| `Sources/` | Swift AppKit interface and C streaming mixer |
| `scripts/` | Original audio generation and repository checks |
| `Tests/` | Silent integration and audio checks |
| `docs/` | Usage, architecture, audio provenance and releases |
| `.github/` | CI, Dependabot, ownership and contribution templates |

## Privacy and license

Preferences are stored locally in `~/Library/Application Support/QuietBar-OpenSource/state.json`. There is no telemetry, backend or automatic update service. Importing a myNoise link parses its text locally without contacting the website.

Code, documentation and the original generator are [MIT licensed](LICENSE). Generated noise may be used and redistributed under the same license. myNoise recordings, website source, logos and private user data are not part of this repository. [Third-party notice](THIRD_PARTY_NOTICES.md).
