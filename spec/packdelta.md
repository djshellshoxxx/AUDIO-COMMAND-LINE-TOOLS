# packdelta — BETA

Compare two revisions of an audio asset tree by decoded audio content instead of filenames alone.

## CLI

```sh
python python/packdelta.py OLD_DIR NEW_DIR [--output report.json] [--csv changes.csv] [--overwrite]
```

Both trees are recursively scanned for WAV files. Identity hashes include sample rate, channel count, and decoded samples quantized into a stable 24-bit-equivalent integer domain. The report classifies `unchanged`, `modified`, `added`, `removed`, and exact-content `renamed` files. It also reports duplicate-content groups in each tree.

A rename is only inferred when decoded audio is identical. When duplicate content creates multiple possible rename pairings, candidate names are ranked by filename similarity and then lexical order so reports remain deterministic.

## Output

JSON contains the classifications plus duplicate groups and their decoded-audio hashes. The report also contains a flat `changes` ledger used for optional CSV output. CSV rows contain `status` and `path`; renamed rows additionally contain `from_path`.

Existing JSON or CSV outputs are not replaced unless `--overwrite` is supplied.

## Limits

This is exact decoded-content comparison, not perceptual similarity, fingerprinting, or metadata comparison. Gain changes, time shifts, resampling, encoding artifacts, and edits produce a different content identity. WAV metadata is intentionally ignored.
