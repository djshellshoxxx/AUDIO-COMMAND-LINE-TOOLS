# tailbudget: Tail trimming with an explicit keep budget

## Purpose

Find the last sample above a threshold and budget how much quiet tail to keep.

## Interface

```sh
python python/tailbudget.py input.wav --threshold-db -65 --pad-ms 200 --audio-out trimmed.wav
node site/js/tailbudget.mjs input.wav --threshold-db -65 --pad-ms 200 --audio-out trimmed.wav
```

For stemcontract pass all stems; for renderdelta pass A.wav B.wav. Every command supports `--output report.json` / `-o`, `--overwrite`, and `--help`. Reports go to stdout by default. Also supports --audio-out result.wav.

| Flag | Default |
|---|---|
| `--threshold-db` | `-60.0` |
| `--pad-ms` | `100.0` |
| `--window-ms` | `100.0` |

## Pseudocode

```text
Validate options, input count and output paths
Read and validate source RIFF WAV without resampling
Find last frame where any channel exceeds threshold
keep = clamp(last_active_end + round_half_up(pad_ms * rate / 1000), 1, frames)
Report retained/removable frames and final-window RMS
If requested, export the first keep frames
Serialize JSON report with finite numbers
Write optional audio result to a new path
Write report or print to stdout
```

## Output and semantics

Reports include tool, sample_rate, frames, channels, duration_seconds and input basenames. Timeline intervals are half-open, [start, end), in source seconds. Channels are numbered starting at 1. Decibel values use amplitude ratios relative to full scale; zero is represented as -240 dB. All rounding is half-up for nonnegative quantities. See the shared contract in spec/COMMON.md and the runnable examples on the website.

## Limits

Uses sample amplitude, not a perceptual reverb detector. Pad keeps existing silence; it does not append silence. An all-quiet input retains at least one frame.

## Acceptance

Synthetic audio with known faults must produce known locations or numeric results. Python and JavaScript reports must agree within floating-point tolerance. Invalid inputs, malformed WAV, nonfinite flags and accidental overwrites must fail. Optional audio output must decode with the specified sample rate, channel count and expected frame count. Tool-specific tests live in tests/test_tools.py.
