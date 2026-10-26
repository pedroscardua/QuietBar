"""Check generator output: duration, finite samples, amplitude, loop edges."""
from array import array
from pathlib import Path
import math
root = Path(__file__).resolve().parents[1] / 'build/audio'
for band in range(10):
    for side in 'ab':
        samples = array('f')
        samples.frombytes((root / f'{band}{side}.f32').read_bytes())
        assert len(samples) == (24-band)*44100*2
        assert all(math.isfinite(x) and abs(x) <= .901 for x in samples)
        assert .05 < math.sqrt(sum(x*x for x in samples)/len(samples)) < .20
        assert samples[0] == samples[1] == samples[-1] == samples[-2] == 0
print('20 generated layers: duration, levels, finite samples and loop edges passed.')
