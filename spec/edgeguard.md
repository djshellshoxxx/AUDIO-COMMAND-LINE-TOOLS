# edgeguard — BETA

Batch-audit sample/file boundaries for likely clicks caused by hot or steep edges, with optional bounded repair copies.

## CLI

```sh
python python/edgeguard.py INPUT_DIR [--threshold-db -45] [--repair --fade-ms 5 --output-dir DIR] [--output report.json] [--csv report.csv] [--overwrite]
```

For each WAV, the tool measures the first/last sample peak magnitude plus the first/last sample-to-sample slope. An edge is flagged when either measurement reaches the amplitude represented by `--threshold-db`.

With `--repair`, only flagged files receive a linear fade-in and fade-out of `--fade-ms` and are written beneath the separate output tree. Repair fade duration must be finite and greater than zero. Sources are never changed. Existing output files fail unless `--overwrite` is explicit. Output paths that resolve through symlinks outside the selected output tree, or back into the source tree, are rejected.

## Output

Per-file JSON/CSV rows include start/end peak, start/end slope, threshold, sample rate, frame count, and boolean start/end risk flags.

## Limits

This checks file boundaries only. It is not an internal de-clicker and does not prove a flagged edge is audible. Long fades can alter intentionally hard attacks; keep repairs short and review critical samples.
