# gainbudget: Requested gain versus sample peak ceiling

## Purpose

Calculate a gain budget before changing audio and show which channels set the limit.

## Interface

```sh
python python/gainbudget.py input.wav --gain-db 3 --ceiling-db -1 --audio-out gained.wav
node site/js/gainbudget.mjs input.wav --gain-db 3 --ceiling-db -1 --audio-out gained.wav
```

For stemcontract pass all stems; for renderdelta pass A.wav B.wav. Every command supports `--output report.json` / `-o`, `--overwrite`, and `--help`. Reports go to stdout by default. Also supports --audio-out result.wav.

| Flag | Default |
|---|---|
| `--gain-db` | `0.0` |
| `--ceiling-db` | `-1.0` |

## Pseudocode

```text
Validate options, input count and output paths
Read and validate source RIFF WAV without resampling
Measure per-channel sample peaks and RMS
safe_gain = ceiling_db - 20*log10(actual_peak) (null for digital silence)
Use the actual nonzero peak even below the report display floor
Predict peak after multiplying by 10^(gain_db/20)
Report whether requested gain fits ceiling
Only export if requested gain fits the ceiling
Bound rounded PCM integers to floor(10^(ceiling_db/20)*32768)
Serialize JSON report with finite numbers
Write optional audio result to a new path
Write report or print to stdout
```

## Output and semantics

Reports include tool, sample_rate, frames, channels, duration_seconds and input basenames. Timeline intervals are half-open, [start, end), in source seconds. Channels are numbered starting at 1. Decibel values use amplitude ratios relative to full scale; zero is represented as -240 dB. All rounding is half-up for nonnegative quantities. See the shared contract in spec/COMMON.md and the runnable examples on the website.

## Limits

Sample peak only, not true peak or LUFS. No limiter. No guarantee against intersample peaks. Export is 16-bit; PCM rounding is bounded by the requested ceiling, and ceilings below one PCM step can yield silence.

## Acceptance

Synthetic audio with known faults must produce known locations or numeric results. Python and JavaScript reports must agree within floating-point tolerance. Invalid inputs, malformed WAV, nonfinite flags and accidental overwrites must fail. Optional audio output must decode with the specified sample rate, channel count and expected frame count. Tool-specific tests live in tests/test_tools.py.
