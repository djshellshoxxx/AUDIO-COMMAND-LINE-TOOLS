# onsetpack — BETA

Batch-standardize the amount of audio before a sample's first threshold-crossing transient.

## CLI

```sh
python python/onsetpack.py INPUT_DIR [--threshold-db -30] [--preroll-ms 10] [--output-dir DIR] [--output report.json] [--csv report.csv] [--overwrite]
```

The input tree is scanned recursively for `.wav` files, case-insensitively. For each file, onset is the first frame where the maximum absolute channel sample reaches `--threshold-db`. `--preroll-ms` keeps existing audio before that frame. Without `--output-dir`, the command only reports measurements. With an output directory, a trimmed 16-bit PCM copy is written under the same relative path.

Files that never cross the threshold are reported with `all_below_threshold: true` and remain untrimmed in output. Sources are never modified. Existing outputs fail unless `--overwrite` is supplied.

## Output

JSON includes sample rate, frame count, onset frame/time, trim-start frame/time, threshold, and quiet status. Optional CSV contains the per-file rows.

## Limits

Threshold crossing is amplitude-based, not perceptual onset detection. A noisy leading edge can trigger early; use a higher threshold for noisy material. Input support is uncompressed PCM WAV 8/16/24/32-bit. Output audio is 16-bit PCM.