# gapcontext: Silence candidates with active flanks

## Purpose

Find interior quiet runs bordered by active audio, with context energy attached.

## Interface

```sh
python python/gapcontext.py input.wav --threshold-db -70 --min-ms 3 --flank-ms 20 --active-db -35
node site/js/gapcontext.mjs input.wav --threshold-db -70 --min-ms 3 --flank-ms 20 --active-db -35
```

For stemcontract pass all stems; for renderdelta pass A.wav B.wav. Every command supports `--output report.json` / `-o`, `--overwrite`, and `--help`. Reports go to stdout by default. No audio mutation.

| Flag | Default |
|---|---|
| `--threshold-db` | `-60.0` |
| `--min-ms` | `2.0` |
| `--flank-ms` | `20.0` |
| `--active-db` | `-35.0` |

## Pseudocode

```text
Validate options, input count and output paths
Read and validate source RIFF WAV without resampling
Mark frames quiet only when every channel is at or below threshold
Group consecutive quiet frames into half-open spans
Reject leading/trailing runs and runs shorter than min_ms
Measure RMS in available flank_ms before and after
Keep candidates only when both flanks reach active_db
Serialize JSON report with finite numbers
Write optional audio result to a new path
Write report or print to stdout
```

## Output and semantics

Reports include tool, sample_rate, frames, channels, duration_seconds and input basenames. Timeline intervals are half-open, [start, end), in source seconds. Channels are numbered starting at 1. Decibel values use amplitude ratios relative to full scale; zero is represented as -240 dB. All rounding is half-up for nonnegative quantities. See the shared contract in spec/COMMON.md and the runnable examples on the website.

## Limits

Candidates can be musical rests. No automatic deletion, interpolation or diagnosis of recording failure.

## Acceptance

Synthetic audio with known faults must produce known locations or numeric results. Python and JavaScript reports must agree within floating-point tolerance. Invalid inputs, malformed WAV, nonfinite flags and accidental overwrites must fail. Optional audio output must decode with the specified sample rate, channel count and expected frame count. Tool-specific tests live in tests/test_tools.py.

Active flank thresholds must be within -240..0 dBFS. Context RMS uses cumulative mean-square energy, with direct summation when subtraction would lose a very quiet flank after loud audio.
