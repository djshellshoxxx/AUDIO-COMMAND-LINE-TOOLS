# phasewatch (Beta)

`phasewatch` creates a timestamped stereo phase/correlation ledger and flags correlation values below a configurable critical threshold plus abrupt correlation regime changes.

## Usage

```bash
bash bash/phasewatch.sh mix.wav --json
bash bash/phasewatch.sh mix.wav --critical-correlation -0.1 --json
```

```powershell
./powershell/phasewatch.ps1 mix.wav -Json
./powershell/phasewatch.ps1 mix.wav -CriticalCorrelation -0.1 -Json
```

## Internals

FFmpeg's `aphasemeter` metadata supplies timestamped correlation values. Each value is retained in the report. Correlation below `critical-correlation` produces `negative_correlation_segment`; a change larger than 0.65 between adjacent measured values produces `correlation_regime_change`.

## Output and exits

JSON contains the phase/correlation timeline, effective critical threshold and findings. Exit `0` means no findings, `1` means review findings exist, and `2` means analysis could not be completed.

## v0.1 scope

Draft warning-threshold, minimum-duration, custom-window and activity-gating controls were removed because they were not yet connected to the DSP path. The v0.1 Beta interface only exposes the threshold that changes classification.

## Limitations

Correlation alone cannot diagnose the cause of a stereo issue. Intentional widening, decorrelation and creative polarity processing can generate findings. Review flagged sections by ear and with appropriate metering.
