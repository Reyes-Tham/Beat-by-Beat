# tools

## beat_reader.py

Extracts a beat grid from a song so charts can use real timestamps instead of
a constant-tempo grid. A tempo estimate plus a computed grid drifts against the
recording — half a BPM of error is a whole beat by the end of a three-minute
song — and timestamps cannot drift.

Method: RMS onset envelope → autocorrelation tempo estimate with fractional
lag → Ellis-style dynamic-programming beat tracking.

```bash
# 1. mono PCM for analysis (any AVFoundation-readable input, incl. .mp4)
afconvert -f WAVE -d LEI16@22050 -c 1 song.mp4 analysis.wav

# 2. audio track for the app
afconvert -f m4af -d aac -b 128000 song.mp4 demo_song_2.m4a

# 3. beat grid
python3 beat_reader.py analysis.wav demo_song_2_beats.json
```

Then add a `Song` to `Song.catalog` with the reported BPM, and drop both
files into `BeatByBeat/Resources/`.

Check the reported interval standard deviation. Under ~15 ms means a confident
track on a steady tempo; much higher means the estimate needs a listen before
it is trusted.

Detected pulses are sometimes every *other* beat — a backbeat. Judge it by the
reported tempo: if it lands implausibly slow for the track (demo_song came out
at 71.9), run `finegrid.py <beats.json>` to interpolate midpoints and recover
the real grid. If the tempo is already plausible (demo_song_2 at 117.4), leave
it alone — doubling it would invent beats the song does not have.

After interpolating, only *even* indices are detected beats, which is why every
difficulty's spacing is even.
