# banddrift (Beta)

`banddrift.sh` creates a time-coded ledger of spectral-balance changes relative to the same file. FFmpeg performs identical band filtering and Bash/awk calculates per-window energy share and median deviation.

Default non-overlapping bands: sub 20–80 Hz, bass 80–250 Hz, lowmid 250–1000 Hz, highmid 1–5 kHz, high 5–20 kHz. Replace them with repeatable `--band NAME:LOW:HIGH`; overlaps are rejected.

Defaults: 1000 ms windows, -60 dBFS active threshold, 8 percentage-point deviation, two-window review target. Events: `band_share_high`, `band_share_low`, `broad_tonal_shift`.

```bash
bash/banddrift.sh master.wav --format tsv
bash/banddrift.sh master.wav --band low:20:200 --band high:200:12000 --deviation-pct 10
```

The tool is not reference matching and does not recommend EQ. Output is text/TSV/JSONL; 0 clean, 1 review, 2 error.
