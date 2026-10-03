# monoledger: Time-coded mono cancellation ledger

## Purpose

Locate active stereo windows that lose energy when folded to mono.

## Interface

```sh
python python/monoledger.py input.wav --window-ms 100 --loss-db 6 --audio-out mono.wav
node site/js/monoledger.mjs input.wav --window-ms 100 --loss-db 6 --audio-out mono.wav
```

For stemcontract pass all stems; for renderdelta pass A.wav B.wav. Every command supports `--output report.json` / `-o`, `--overwrite`, and `--help`. Reports go to stdout by default. Also supports --audio-out result.wav.

| Flag | Default |
|---|---|
| `--window-ms` | `100.0` |
| `--threshold-db` | `-60.0` |
| `--loss-db` | `6.0` |

## Pseudocode

```text
Validate options, input count and output paths
Read and validate source RIFF WAV without resampling
Split into fixed nonoverlapping windows, including the final partial window
energy = mean(all channel sample squares)
mono = (left + right) / 2; loss_db = 20*log10(rms(mono)/sqrt(energy))
If active and loss_db < -loss_limit, record window and centered-channel correlation
Optionally export the full arithmetic mono fold
Serialize JSON report with finite numbers
Write optional audio result to a new path
Write report or print to stdout
```

## Output and semantics

Reports include tool, sample_rate, frames, channels, duration_seconds and input basenames. Timeline intervals are half-open, [start, end), in source seconds. Channels are numbered starting at 1. Decibel values use amplitude ratios relative to full scale; zero is represented as -240 dB. All rounding is half-up for nonnegative quantities. See the shared contract in spec/COMMON.md and the runnable examples on the website.

## Limits

Requires stereo. Loss is measured against average channel energy. Silent windows are ignored; correlation is null for constant channels.

## Acceptance

Synthetic audio with known faults must produce known locations or numeric results. Python and JavaScript reports must agree within floating-point tolerance. Invalid inputs, malformed WAV, nonfinite flags and accidental overwrites must fail. Optional audio output must decode with the specified sample rate, channel count and expected frame count. Tool-specific tests live in tests/test_tools.py.

Correlation is null for constant channels, including nonzero constants, because centered variance is zero. Finite correlation is bounded to [-1, 1].
