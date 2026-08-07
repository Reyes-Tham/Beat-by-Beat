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
afconvert -f m4af -d aac -b 128000 song.mp4 demo_song.m4a

# 3. beat grid
python3 beat_reader.py          # reads analysis.wav, writes demo_song_beats.json
```

Check the reported interval standard deviation. Under ~15 ms means a confident
track on a steady tempo; much higher means the estimate needs a listen before
it is trusted.

Detected pulses are often every *other* beat (a backbeat). `finegrid` style
interpolation of midpoints recovers the full grid; because every difficulty's
spacing is even, notes still land on detected beats.
