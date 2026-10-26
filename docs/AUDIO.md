# Audio provenance and limits

All public-build audio comes from `scripts/generate_audio.c`, original code in this repository. There are no downloaded samples, copied website scripts, or external audio libraries. Generation is deterministic for a given toolchain; exact float output can vary across compilers/architectures.

The generator uses a seeded xorshift32 sequence, two independent channels, and a biquad band-pass filter per layer. Centers: 31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000 and 14000 Hz. Q is 1.2. It discards one second of filter warm-up, applies 20 ms raised-cosine edges, and normalizes toward 0.18 RMS with a 0.9 peak ceiling. The bands overlap; this is a sound-design tool, not a calibrated equalizer.

Twenty files (two per layer) contain stereo interleaved float32 PCM at 44100 Hz. Lengths decrease from 24 to 15 seconds. Each B stream starts half a loop after A, covering short seam fades. Generated assets are build outputs, ignored by Git, and included in packaged applications under MIT.

## Relationship to myNoise

The private prototype was inspired by myNoise White Noise & Co and used personal listening samples. Those recordings and research downloads are excluded from this repository and release workflow. The public application uses the original generator above.

The myNoise page marks its content for personal use: <https://mynoise.net/NoiseMachines/whiteNoiseGenerator.php>. Public distribution of its recordings is not part of this project's license. QuietBar is unaffiliated with myNoise BV or Stéphane Pigeon.

The link importer reads only settings. Slider response, soft movement and nominal compressor parameters may resemble the referenced player, but audio content, filtering, compressor detector, timing and random sequences differ. QuietBar does not claim waveform equivalence or an exact replica.
