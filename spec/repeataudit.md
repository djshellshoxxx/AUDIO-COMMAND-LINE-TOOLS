# repeataudit (Beta)

`repeataudit.sh` detects exact repeated decoded PCM blocks. It targets recorder/buffer repetition and accidental duplicated audio, not musical similarity.

The input is decoded to frame-aligned signed 16-bit PCM. Blocks are hashed with SHA-256, silence-like blocks below the configured RMS threshold are ignored, adjacent identical hashes are grouped, and candidates are checked in deterministic block order. Non-adjacent grouping avoids all-pairs comparison.

Defaults: 100 ms blocks, 300 ms adjacent threshold, 500 ms non-adjacent threshold, -70 dBFS ignore floor, 4 GiB decoded-size guard. `--adjacent-only` disables non-adjacent search. `--hash-command` selects `sha256sum`, `shasum`, or auto detection.

```bash
bash/repeataudit.sh capture.wav --format jsonl
```

Events: `adjacent_exact_repeat`, `nonadjacent_exact_repeat`, `long_exact_repeat` (reserved for extended reporting). Exact repetition is evidence, not proof of the cause. Exit 0 clean, 1 review, 2 error.
