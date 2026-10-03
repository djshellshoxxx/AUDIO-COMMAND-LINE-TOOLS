# loudwalk (Beta)

`loudwalk` converts FFmpeg's EBU R128 measurements into a time-coded loudness consistency report. It is intended for finding abrupt or unusual sections inside one program rather than checking a streaming-service target.

## Usage

```bash
bash bash/loudwalk.sh mix.wav --json
bash bash/loudwalk.sh mix.wav --jump-db 4 --deviation-db 7 --output loudness.json
```

```powershell
./powershell/loudwalk.ps1 mix.wav -Json
./powershell/loudwalk.ps1 mix.wav -JumpDb 4 -DeviationDb 7 -Output loudness.json
```

Runtime dependencies are FFmpeg and FFprobe, plus Bash 4.4+ or PowerShell 7+.

## Internals

FFmpeg runs the `ebur128=peak=true` filter. The scripts parse its time-coded short-term (`S`) loudness samples and final integrated loudness/LRA summary. Values below the useful short-term measurement floor are excluded from the timeline. The remaining short-term values are sorted to calculate a median.

Each adjacent pair is compared. If the absolute change is at least the configured `jump-db`, an `abrupt_loudness_transition` review item is emitted. Every short-term sample is also compared with the file median; samples whose absolute deviation exceeds `deviation-db` produce `relative_loudness_outlier` evidence.

Bash performs parsing and aggregation with `awk`, `sort` and shell arrays. PowerShell performs the same aggregation using regular expressions, arrays and .NET doubles. Neither version reimplements loudness DSP; FFmpeg performs the EBU R128 analysis.

## Output

JSON includes integrated LUFS, LRA when FFmpeg reports it, median short-term loudness, the time-coded timeline, findings, dependency versions and the effective thresholds. Text mode is a compact summary suitable for an interactive shell.

Exit `0` means no review findings, `1` means findings were produced, and `2` means invalid input or an analysis/runtime error.

## Limitations

Short programs may not accumulate enough material for stable short-term loudness values. A large jump can be musically intentional. Median-relative deviations compare a recording with itself and are not broadcast, podcast or streaming compliance measurements. Results can vary slightly across FFmpeg versions, so automated tests compare categories and numeric values with tolerance rather than exact stderr text.