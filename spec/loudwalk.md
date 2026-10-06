# loudwalk (Beta)

`loudwalk` converts FFmpeg EBU R128 measurements into a time-coded short-term loudness walk and highlights abrupt changes or sections far from the file median.

## Usage

```bash
bash bash/loudwalk.sh track.wav --json
bash bash/loudwalk.sh track.wav --jump-db 4 --deviation-db 5 --json
```

```powershell
./powershell/loudwalk.ps1 track.wav -Json
./powershell/loudwalk.ps1 track.wav -JumpDb 4 -DeviationDb 5 -Json
```

## Internals

FFmpeg's `ebur128` filter supplies short-term loudness samples, integrated LUFS and LRA. The scripts compute the median short-term loudness, compare adjacent samples against `jump-db`, and compare each sample with the median against `deviation-db`.

Findings are `abrupt_loudness_transition` and `relative_loudness_outlier`. Source audio is read-only.

## Output and exits

JSON contains the complete timeline, integrated loudness, LRA, median short-term loudness, effective thresholds and findings. Exit `0` means no findings, `1` means findings exist, and `2` means analysis could not be completed.

## v0.1 scope

Draft `interval` and `top` controls were removed from the Beta CLI because they were previously accepted without changing analysis. The v0.1 timeline follows FFmpeg's native EBU R128 sample cadence and reports all threshold crossings.

## Limitations

This is a review aid, not a streaming-platform compliance validator or loudness normalizer. Intentional drops, breakdowns and mastering contrasts can trigger findings.
