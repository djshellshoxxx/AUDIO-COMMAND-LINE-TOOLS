# edgeguard (Beta)

`edgeguard.sh` detects audio that reaches the beginning or end of a file with sustained energy and no convincing fade envelope. It is intended to flag possible truncated renders for review; it does not prove that an artistic hard cut is incorrect.

Runtime: Bash 4.4+, FFmpeg, FFprobe, awk and coreutils.

```bash
bash/edgeguard.sh render.wav --format text
bash/edgeguard.sh render.wav --window-ms 100 --subwindow-ms 10 --format jsonl
```

Defaults: 100 ms boundary window, 10 ms envelope window, -60 dBFS activity, -24 dBFS boundary review threshold, 0.15 normalized discontinuity, fade tolerance 1. `--side start|end|both` limits inspection.

Events: `active_at_start`, `active_at_end`, `start_discontinuity`, `end_discontinuity`, `possible_truncated_start`, `possible_truncated_end`. A `possible_truncated_*` event requires elevated boundary RMS plus missing fade evidence.

Output modes are `text`, `tsv`, and `jsonl`. Exit 0 means no review event, 1 means a review event was emitted, and 2 means a usage/dependency/input/analysis/output error. Input files are never modified.

Pipeline example:

```bash
find renders -name '*.wav' -print0 | xargs -0 -n1 bash bash/edgeguard.sh --format tsv --no-header
```
