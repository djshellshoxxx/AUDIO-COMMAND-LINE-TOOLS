# stemcontract: Repeatable stem delivery contract

## Purpose

Check exported files against an explicit rate, channel, length and filename contract.

## Interface

```sh
python python/stemcontract.py input.wav --rate 48000 --channels 2 --frames 96000 --require-active --expect drums.wav --expect bass.wav
node site/js/stemcontract.mjs input.wav --rate 48000 --channels 2 --frames 96000 --require-active --expect drums.wav --expect bass.wav
```

For stemcontract pass all stems; for renderdelta pass A.wav B.wav. Every command supports `--output report.json` / `-o`, `--overwrite`, and `--help`. Reports go to stdout by default. No audio mutation.

| Flag | Default |
|---|---|
| `--rate` | `0` |
| `--channels` | `0` |
| `--frames` | `0` |
| `--threshold-db` | `-60.0` |
| `--require-active` | `False` |
| `--expect` | `[]` |

## Pseudocode

```text
Validate options, input count and output paths
Read and validate source RIFF WAV without resampling
Contract defaults to first file unless explicit values supplied
For each file compare rate, channels and frames to contract
Optionally reject files entirely below activity threshold
Compute missing expected basenames; reject duplicate input basenames
Return passed=false and CLI exit 1 when contract fails
Serialize JSON report with finite numbers
Write optional audio result to a new path
Write report or print to stdout
```

## Output and semantics

Reports include tool, sample_rate, frames, channels, duration_seconds and input basenames. Timeline intervals are half-open, [start, end), in source seconds. Channels are numbered starting at 1. Decibel values use amplitude ratios relative to full scale; zero is represented as -240 dB. All rounding is half-up for nonnegative quantities. See the shared contract in spec/COMMON.md and the runnable examples on the website.

## Limits

Checks export structure and activity, not phase alignment or correctness of the music. Expected basenames are exact and case sensitive. Extra filenames are allowed.

## Acceptance

Synthetic audio with known faults must produce known locations or numeric results. Python and JavaScript reports must agree within floating-point tolerance. Invalid inputs, malformed WAV, nonfinite flags and accidental overwrites must fail. Optional audio output must decode with the specified sample rate, channel count and expected frame count. Tool-specific tests live in tests/test_tools.py.
