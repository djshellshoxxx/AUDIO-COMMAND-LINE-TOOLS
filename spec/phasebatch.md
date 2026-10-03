# phasebatch — BETA

Batch-check synchronized WAV exports for integer-sample delay and polarity relative to a chosen reference.

## CLI

```sh
python python/phasebatch.py INPUT_DIR --reference ref.wav [--max-shift-ms 10] [--correct --output-dir DIR] [--output report.json] [--csv report.csv] [--overwrite]
```

All WAVs are recursively discovered. The reference must be a WAV inside the input tree. Each file is downmixed to mono for comparison. The tool searches integer offsets within `--max-shift-ms` and chooses the offset with the greatest absolute normalized correlation. The requested search window is bounded to offsets that retain at least two overlapping frames, so a window longer than the source cannot create invalid zero-length comparisons. A positive delay means the target occurs later than the reference. Negative correlation is reported as polarity inversion.

With `--correct`, each target is shifted to align with the reference, inverted when required, length-matched to the reference, and written to the output tree. Sources are never modified. Sample rates must match; no resampling is performed. Search-window values must be finite and non-negative. Output paths that resolve through symlinks outside the selected output tree, or back into the input tree, are rejected.

## Output

Each comparison reports reference, target, sample rate, delay in frames/milliseconds, correlation, and polarity state.

## Limits

This is a time-domain integer-delay/polarity tool, not a fractional-delay, frequency-dependent phase, or acoustic transfer-function solver. Repetitive material can create multiple strong correlation peaks; listen and inspect before adopting corrections. Correlation currently scans the requested valid offsets directly, so long files and wide search windows can be computationally expensive.
