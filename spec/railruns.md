# railruns: Clipping threshold event ledger

## Purpose

Map consecutive near-full-scale samples by channel instead of reporting only a peak.

## Interface

```sh
python python/railruns.py input.wav --threshold-db -0.1 --min-run 3
node site/js/railruns.mjs input.wav --threshold-db -0.1 --min-run 3
```

For stemcontract pass all stems; for renderdelta pass A.wav B.wav. Every command supports `--output report.json` / `-o`, `--overwrite`, and `--help`. Reports go to stdout by default. No audio mutation.

| Flag | Default |
|---|---|
| `--threshold-db` | `-0.1` |
| `--min-run` | `3` |

## Pseudocode

```text
Validate options, input count and output paths
Read and validate source RIFF WAV without resampling
For each channel, mark abs(sample) >= amplitude_threshold
Group consecutive marked frames
Keep runs containing at least min_run samples
Report half-open start/end times, frame count and overall sample peak
Serialize JSON report with finite numbers
Write optional audio result to a new path
Write report or print to stdout
```

## Output and semantics

Reports include tool, sample_rate, frames, channels, duration_seconds and input basenames. Timeline intervals are half-open, [start, end), in source seconds. Channels are numbered starting at 1. Decibel values use amplitude ratios relative to full scale; zero is represented as -240 dB. All rounding is half-up for nonnegative quantities. See the shared contract in spec/COMMON.md and the runnable examples on the website.

## Limits

Detects threshold runs, not analog clipping or true peaks. Single transient peaks can be excluded by the run length.

## Acceptance

Synthetic audio with known faults must produce known locations or numeric results. Python and JavaScript reports must agree within floating-point tolerance. Invalid inputs, malformed WAV, nonfinite flags and accidental overwrites must fail. Optional audio output must decode with the specified sample rate, channel count and expected frame count. Tool-specific tests live in tests/test_tools.py.
