# Bash edgeguard (Beta)

`bash/edgeguard.sh` reviews the beginning and end of an audio file for evidence consistent with an abruptly truncated render: sustained boundary energy, endpoint discontinuity, and a short energy envelope that does not resemble a fade. It is read-only and does not repair or trim audio. This is distinct from the repository's Python batch `edgeguard`, which audits folders and can write repaired copies.

## Dependencies and syntax

Runtime: Bash 4.4+, FFmpeg, FFprobe, awk, `od`, `mktemp`, and ordinary coreutils.

```text
bash/edgeguard.sh [options] FILE
```

Common options: `--help`, `--version`, `--format text|tsv|jsonl`, `--output PATH`, `--no-header`, `--quiet`, `--keep-temp`.

Tool options and defaults:

| Option | Default | Meaning |
| --- | ---: | --- |
| `--window-ms N` | 100 | Boundary region inspected at each selected side |
| `--subwindow-ms N` | 10 | Envelope subdivision used for fade evidence |
| `--active-db DB` | -60 | Minimum boundary RMS considered active |
| `--boundary-rms-db DB` | -24 | RMS threshold required for truncation review |
| `--discontinuity X` | 0.15 | Absolute normalized full-scale endpoint threshold |
| `--fade-tolerance N` | 1 | Number of envelope-direction violations tolerated |
| `--side start|end|both` | both | Boundary or boundaries to inspect |

## Data flow and calculations

1. FFprobe obtains the decoded audio sample rate.
2. FFmpeg decodes the first audio stream to canonical mono signed 16-bit PCM in a temporary directory.
3. `od` exposes signed sample values to awk without a Python/Node runtime.
4. The first/last `window-ms` regions are divided into `subwindow-ms` segments.
5. RMS is `sqrt(sum(sample²)/N) / 32768`; dBFS is `20*log10(RMS)`, with digital silence represented by the implementation floor.
6. Endpoint discontinuity is the absolute first or last decoded sample normalized by 32768, representing the jump from/to the implicit zero outside the file.
7. Fade evidence compares consecutive subwindow RMS values. A start normally rises away from the boundary; an end normally falls toward it. A largely flat/high-energy boundary is evidence to inspect.
8. `possible_truncated_start` / `possible_truncated_end` require boundary RMS above the review threshold plus either missing fade evidence or endpoint discontinuity. A single low-level endpoint value does not establish truncation.

## Events

- `active_at_start`, `active_at_end`: informational boundary activity.
- `start_discontinuity`, `end_discontinuity`: endpoint magnitude meets the configured discontinuity threshold.
- `no_start_fade_evidence`, `no_end_fade_evidence`: high boundary energy without the expected envelope direction.
- `possible_truncated_start`, `possible_truncated_end`: combined review evidence.

Event ranges are timestamped in seconds. Findings describe evidence only; hard cuts and one-shot transients can be intentional.

## Output contracts

Text is intended for terminal review. TSV columns are stable: `path`, `tool`, `event`, `start_seconds`, `end_seconds`, `severity`, `details`. JSONL emits one object per event plus a final `event:"summary"` object. Structured stdout contains no diagnostic prose; errors go to stderr.

Exit codes: `0` completed without review findings; `1` completed with one or more review findings; `2` invalid arguments, dependencies, input, decode, or report write. Interrupt cleanup propagates the signal exit path. `--output` writes through a temporary file in the destination directory and renames it only after the report is complete.

## Examples

```bash
bash bash/edgeguard.sh render.wav --format jsonl
bash bash/edgeguard.sh render.wav --side end --window-ms 150 --format text

find renders -type f -name '*.wav' -print0 |
  xargs -0 -n1 bash bash/edgeguard.sh --format tsv --no-header |
  awk -F '\t' '$3 ~ /possible_truncated/'
```

## Performance and limitations

The PCM scan is linear in decoded samples and holds decoded sample values in awk for the boundary calculation. It is intended for ordinary rendered audio, not multi-day captures. FFmpeg's decoded representation is what is measured. Resampling is not requested; FFmpeg preserves the decoded stream rate unless its decoder requires otherwise.

A natural percussive onset, deliberate hard edit, non-zero-crossing creative cut, or sustained ending may trigger review. A truncated file that happens to end near zero or includes a short fade may not trigger. The tool does not measure true peak, loudness, perceptual click audibility, or source-file corruption.

## Implementation internals and tests

Shared lifecycle/validation is in `bash/lib/audio-common.sh`; report serialization/atomic output is in `bash/lib/output.sh`; PCM decoding helpers are in `bash/lib/pcm.sh`. Temporary files are removed on success, ordinary failure, and interrupt unless `--keep-temp` is explicitly selected.

Synthetic regression tests cover abrupt starts/ends, clean fades, paths with spaces and leading dashes, JSONL/TSV contracts, invalid values, output-file behavior, source immutability, and explicit no-fade event generation. The Ubuntu CI job runs `bash -n`, ShellCheck, and the Bash regression suite with FFmpeg installed.
