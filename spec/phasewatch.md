# phasewatch (Beta)

`phasewatch` turns stereo phase/correlation metadata into a timestamped ledger so short-lived changes are not hidden by one whole-file statistic.

## Usage

```bash
bash bash/phasewatch.sh mix.wav --json
bash bash/phasewatch.sh mix.wav --critical-correlation -0.2 --min-duration-ms 150 --output phase.json
```

```powershell
./powershell/phasewatch.ps1 mix.wav -Json
./powershell/phasewatch.ps1 mix.wav -CriticalCorrelation -0.2 -MinDurationMs 150 -Output phase.json
```

## Internals

FFprobe first verifies that the decoded input has exactly two channels. FFmpeg then runs `aphasemeter=video=0` and `ametadata=print` to expose `lavfi.aphasemeter.phase` values along with frame timestamps. The shell implementations parse those metadata frames into `{time_seconds, correlation}` records.

The current release compares each correlation value with the configured critical threshold and reports `negative_correlation_segment` evidence when the threshold is crossed. It also compares adjacent values; a large absolute change produces `correlation_regime_change` evidence. The warning threshold, nominal window size, minimum duration and minimum-active level are preserved in the report so future releases can tighten sustained-run grouping without changing the CLI contract.

Bash performs metadata parsing and comparisons using regular expressions and `awk`. PowerShell uses regex parsing and .NET doubles. Neither implementation calculates correlation from raw samples; FFmpeg's phase meter remains the DSP source.

## Output

JSON reports contain the complete correlation window ledger, effective thresholds, findings, dependency versions and final status. Text mode is intentionally compact.

Exit `0` means no review findings, `1` means review findings were generated and `2` means invalid input, missing dependencies, non-stereo material or an analysis failure.

## Limitations

Correlation alone does not diagnose the cause of a phase relationship and does not prove mono incompatibility. Wide stereo effects can legitimately be weak or negative. The timestamps correspond to FFmpeg phase-meter metadata frames rather than a user-selected sample-exact sliding window. Treat every finding as a location to inspect rather than an automatic fault.