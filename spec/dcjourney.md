# dcjourney: Windowed DC offset history

## Purpose

Measure DC offset over time and distinguish local drift from the whole-file mean.

## Interface

```sh
python python/dcjourney.py input.wav --window-ms 250 --threshold-db -40 --audio-out centered.wav
node site/js/dcjourney.mjs input.wav --window-ms 250 --threshold-db -40 --audio-out centered.wav
```

For stemcontract pass all stems; for renderdelta pass A.wav B.wav. Every command supports `--output report.json` / `-o`, `--overwrite`, and `--help`. Reports go to stdout by default. Also supports --audio-out result.wav.

| Flag | Default |
|---|---|
| `--window-ms` | `100.0` |
| `--threshold-db` | `-40.0` |

## Pseudocode

```text
Validate options, input count and output paths
Read and validate source RIFF WAV without resampling
Compute mean sample value for each channel in each window
Flag a window if any abs(mean) exceeds threshold
Report global per-channel means and maximum local offset
If requested subtract only each global channel mean and export
Serialize JSON report with finite numbers
Write optional audio result to a new path
Write report or print to stdout
```

## Output and semantics

Reports include tool, sample_rate, frames, channels, duration_seconds and input basenames. Timeline intervals are half-open, [start, end), in source seconds. Channels are numbered starting at 1. Decibel values use amplitude ratios relative to full scale; zero is represented as -240 dB. All rounding is half-up for nonnegative quantities. See the shared contract in spec/COMMON.md and the runnable examples on the website.

## Limits

Global mean removal does not correct time-varying drift. Asymmetric audio can legitimately have nonzero local means. Export refuses samples above full scale.

## Acceptance

Synthetic audio with known faults must produce known locations or numeric results. Python and JavaScript reports must agree within floating-point tolerance. Invalid inputs, malformed WAV, nonfinite flags and accidental overwrites must fail. Optional audio output must decode with the specified sample rate, channel count and expected frame count. Tool-specific tests live in tests/test_tools.py.
