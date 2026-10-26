# User guide

QuietBar starts paused, with a waveform icon in the menu bar and no Dock icon.

1. Click the icon to open quick controls. Click **Reproduzir** to start; **Pausar** to pause.
2. Adjust **Volume**, choose a preset, toggle movement or select a timer.
3. Select **Abrir controles** for the full panel, including ten layers, stereo width and compression.

Right-click the icon for playback, full controls and quit. Closing a panel does not stop audio. Quitting does.

## Presets

**Salvar…** creates or updates a named mix. **Remover** removes a saved mix after confirmation. The built-in **Foco · QuietBar** cannot be removed; **Restaurar original** restores it.

JSON import loads a mix without overwriting a named preset. Save it to retain it in the list. Export writes a JSON file you choose. Import supports a named object with `name` and `mix`; see [example](../examples/focus.json). There are ten levels (0–0.99), volume (0–1), width (0–2), animation and dynamics booleans, and speed (0.25, 0.5, 1, 2 or 4).

myNoise import accepts only White Noise & Co links and supported level/soft-animation parameters. It does not download audio or reproduce myNoise's sound. Unsupported tuning is rejected rather than silently interpreted.

## Timer and movement

Timers run for 15, 30, 60 or 90 minutes, then fade over three seconds and pause. Timers are session-only. The fade does not overwrite your saved volume. macOS sleep can delay timer delivery until wake; this is not an alarm clock.

Movement varies the levels around your mix. Sliders show your base mix, not the temporary animated values.

## Troubleshooting

- No sound: verify playback, volume, individual layers and macOS output device. After a device change, start playback again if macOS stopped the audio engine.
- Missing resources: rebuild with `./build.sh`; move the entire `.app`, not just its executable.
- Reset preferences: quit, back up and remove `~/Library/Application Support/QuietBar-OpenSource/state.json`, then reopen.
- Remove: quit, delete the app, and optionally remove that preferences folder.

The app currently has no launch-at-login option, automatic updater or English UI. Start at a comfortable volume; the compressor and sample ceiling are not hearing-safety guarantees.
