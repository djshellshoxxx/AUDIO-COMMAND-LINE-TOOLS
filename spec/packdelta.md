# packdelta — BETA

Compare two revisions of an audio asset tree by decoded audio content instead of filenames alone.

## CLI

```sh
python python/packdelta.py OLD_DIR NEW_DIR [--output report.json] [--csv changes.csv] [--overwrite]
```

Both trees are recursively scanned for WAV files. Identity hashes include sample rate, channel count, and decoded samples quantized into a stable 24-bit-equivalent integer domain. The report classifies `unchanged`, `modified`, `added`, `removed`, and 24-bit-equivalent content `renamed` files. It also reports duplicate-content groups in each tree.

A rename is only inferred when the 24-bit-equivalent decoded identity matches. When duplicate content creates multiple possible rename pairings, candidate names are ranked by filename similarity and then lexical order so reports remain deterministic.

## Output

JSON contains the classifications plus duplicate groups and their decoded-audio hashes. The report also contains a flat `changes` ledger used for optional CSV output. CSV rows contain `status` and `path`; renamed rows additionally contain `from_path`.

Existing JSON or CSV outputs are not replaced unless `--overwrite` is supplied. JSON and CSV outputs must use different paths.

## Limits

This is deterministic 24-bit-equivalent decoded-content comparison, not bit-exact comparison of every possible higher-resolution source sample, perceptual similarity, fingerprinting, or metadata comparison. Differences below the canonical 24-bit-equivalent quantization step can intentionally compare equal. Gain changes, time shifts, resampling, larger encoding differences, and edits produce a different content identity. WAV metadata is intentionally ignored.
