# subphase (Beta)

`bash/subphase.sh` isolates the low-frequency part of a stereo signal and produces timestamped correlation/balance review events. The purpose is to answer questions such as “where does the sub/bass become negative or unusually wide?” without letting higher-frequency stereo content dominate the result.

## Dependencies and CLI

Requires Bash 4.4+, FFmpeg, FFprobe, awk, `od`, `mktemp`, and coreutils.

```text
bash/subphase.sh [options] FILE
```

Common options: `--help`, `--version`, `--format text|tsv|jsonl`, `--output PATH`, `--no-header`, `--quiet`, `--keep-temp`.

| Option | Default | Meaning |
| --- | ---: | --- |
| `--crossover-hz N` | 120 | Equal low-pass cutoff applied to both channels |
| `--window-ms N` | 250 | Correlation/RMS analysis window |
| `--active-db DB` | -55 | Ignore low-band windows below this activity level |
| `--weak-correlation X` | +0.20 | Weak-correlation boundary |
| `--negative-correlation X` | 0.00 | Negative-correlation boundary |
| `--critical-correlation X` | -0.50 | Critical negative-correlation boundary |
| `--min-run-ms N` | 500 | Minimum contiguous run before correlation review is emitted |
| `--imbalance-db DB` | 4 | Left/right low-band RMS difference review threshold |
| `--allow-mono` | off | Allow mono input to complete without phase findings |

## Signal/data flow

1. FFprobe verifies channel count and sample rate. Stereo is required unless `--allow-mono` is selected.
2. FFmpeg decodes the selected audio stream to signed 16-bit stereo PCM while applying the same low-pass filter to both channels.
3. Awk groups interleaved samples into fixed windows and calculates left/right sums, energies, cross-products, RMS and covariance.
4. Windows below the configured active threshold are excluded before normalized correlation is calculated.
5. Correlation is normalized covariance: `cov(L,R) / sqrt(var(L)*var(R))`. Constant/degenerate active windows are treated conservatively rather than divided by zero.
6. Correlation windows are classified as weak, negative, or critical. Adjacent windows of the same class are merged; the run is emitted only when its duration reaches `--min-run-ms`.
7. Left/right low-band RMS imbalance is evaluated independently.

## Events

- `weak_sub_correlation`
- `negative_sub_correlation`
- `critical_sub_correlation`
- `sub_balance_imbalance`
- `sub_phase_regime_change` when a qualifying correlation regime is entered

Events include timestamps and measurement details. Correlation is evidence about channel relationship, not a declaration that stereo bass is technically wrong.

## Output and exit codes

Text is for terminal inspection. TSV uses the shared columns `path`, `tool`, `event`, `start_seconds`, `end_seconds`, `severity`, `details`. JSONL emits independent JSON objects plus a final summary. Diagnostics use stderr.

Exit `0`: completed without review findings. Exit `1`: completed with one or more review findings. Exit `2`: invalid options/input/layout, missing dependency, FFmpeg/FFprobe failure, or report-write failure.

## Examples

```bash
bash bash/subphase.sh mix.wav --crossover-hz 120 --format jsonl
bash bash/subphase.sh mix.wav --crossover-hz 80 --min-run-ms 1000 --format text

bash bash/subphase.sh mix.wav --format tsv |
  awk -F '\t' '$3 ~ /negative_sub_correlation|critical_sub_correlation/'
```

## Performance and limitations

Processing is linear in decoded samples and uses one canonical low-passed PCM stream. Results depend on crossover choice, window size, source content, and the decoded representation. Creative stereo bass, stereo ambience, delays, phase rotation, or asymmetric low-frequency content can legitimately produce review events. A correlation value alone does not predict mono audibility or playback-system behavior.

Very quiet windows are deliberately ignored because normalized correlation is unstable and operationally unhelpful near silence. The current implementation uses a fixed FFmpeg low-pass topology rather than exposing filter order/Q as version-1 parameters.

## Internals and test coverage

Shared dependency/temp/output behavior lives in `bash/lib/`. Functional fixtures include in-phase 60 Hz, inverted 60 Hz, mono rejection/allowance, silence handling, low-band imbalance behavior, paths with unusual names, and a short negative-correlation region proving `--min-run-ms` suppression. Audit regression coverage also verifies `sub_phase_regime_change` and that a single bad window does not become a sustained finding when the minimum run is longer.
