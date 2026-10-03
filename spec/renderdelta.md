# renderdelta: Offset-aware residual timeline

## Purpose

Compare two renders at a supplied sample offset and report changed sections.

## Interface

```sh
python python/renderdelta.py A.wav B.wav --offset-frames 0 --window-ms 100 --threshold-db -80 --audio-out residual.wav
node site/js/renderdelta.mjs A.wav B.wav --offset-frames 0 --window-ms 100 --threshold-db -80 --audio-out residual.wav
```

For stemcontract pass all stems; for renderdelta pass A.wav B.wav. Every command supports `--output report.json` / `-o`, `--overwrite`, and `--help`. Reports go to stdout by default. Also supports --audio-out result.wav.

| Flag | Default |
|---|---|
| `--window-ms` | `100.0` |
| `--threshold-db` | `-60.0` |
| `--offset-frames` | `0` |

## Pseudocode

```text
Validate options, input count and output paths
Read and validate source RIFF WAV without resampling
Require equal source sample rate and channel count
Positive offset skips frames from B; negative offset skips frames from A
Subtract corresponding samples over overlapping frames only
Record windows whose residual peak exceeds threshold
Report peak/RMS residual, overlap and unmatched counts; optionally export residual
Serialize JSON report with finite numbers
Write optional audio result to a new path
Write report or print to stdout
```

## Output and semantics

Reports include tool, sample_rate, frames, channels, duration_seconds and input basenames. Timeline intervals are half-open, [start, end), in source seconds. Channels are numbered starting at 1. Decibel values use amplitude ratios relative to full scale; zero is represented as -240 dB. All rounding is half-up for nonnegative quantities. See the shared contract in spec/COMMON.md and the runnable examples on the website.

## Limits

No automatic alignment or gain matching. A null does not imply perceptual equivalence; reports are sample differences. Unmatched frames are counted, not compared. Residual export refuses levels above full scale.

## Acceptance

Synthetic audio with known faults must produce known locations or numeric results. Python and JavaScript reports must agree within floating-point tolerance. Invalid inputs, malformed WAV, nonfinite flags and accidental overwrites must fail. Optional audio output must decode with the specified sample rate, channel count and expected frame count. Tool-specific tests live in tests/test_tools.py.
