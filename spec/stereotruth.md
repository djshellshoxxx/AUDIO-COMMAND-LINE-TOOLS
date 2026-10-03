# stereotruth (Beta)

`stereotruth` audits stereo files for relationships that are easy to miss in a normal metadata dump: near-identical channels, sustained negative correlation, and channel-level imbalance. It is an evidence tool, not a mastering diagnosis.

## Dependencies

Runtime: FFmpeg, FFprobe, plus Bash 4.4+ for `bash/stereotruth.sh` or PowerShell 7+ for `powershell/stereotruth.ps1`.

## Usage

```bash
bash bash/stereotruth.sh mix.wav --json
bash bash/stereotruth.sh mix.wav --dual-mono-correlation 0.998 --imbalance-db 2 --output stereo.json
```

```powershell
./powershell/stereotruth.ps1 mix.wav -Json
./powershell/stereotruth.ps1 mix.wav -DualMonoCorrelation 0.998 -ImbalanceDb 2 -Output stereo.json
```

Important controls are the dual-mono correlation threshold, negative-correlation threshold, imbalance threshold, nominal window size, minimum-active level and delay-search bound. Version 0.1 reports the configured delay-search bound but does not claim an automatic delay estimate.

## Internals

The script first asks FFprobe for the decoded channel count and rejects anything except two channels. FFmpeg then runs `aphasemeter=video=0` and prints the `lavfi.aphasemeter.phase` frame metadata. Those values form the correlation timeline used to calculate mean correlation, the proportion of windows at or above the dual-mono threshold, and the proportion at or below the negative-correlation threshold.

A second FFmpeg pass runs `astats=metadata=1` and prints per-channel RMS metadata. The scripts calculate the absolute difference between left and right RMS levels. Bash performs only aggregation and threshold comparisons with `awk`; PowerShell performs the same aggregation with .NET numeric types. FFmpeg remains the DSP engine in both versions.

Default findings are conservative. A `dual_mono_candidate` is emitted only when at least 90% of measured phase windows meet the configured near-unity threshold. A `polarity_inversion_candidate` requires at least half the measured windows to be strongly negative. `channel_imbalance` compares the RMS difference with the configured dB limit.

## JSON

Reports contain `tool`, `version`, `generated_utc`, dependency versions, effective options, measurements, findings and `status`. Finding categories are stable machine-readable strings. Status is `review` when a finding is present and `ok` otherwise.

## Exit codes

- `0`: analysis completed with no findings
- `1`: analysis completed and one or more review findings were produced
- `2`: invalid arguments, missing dependencies, unreadable input, non-stereo input or FFmpeg/FFprobe failure

## Limitations

Correlation is not a complete mono-compatibility test. Highly correlated stereo may be intentional. Negative correlation may be an intentional spatial effect. RMS imbalance may be musically correct. Silence and extremely quiet material can make correlation less useful, so findings should be verified in context. The tool does not prove wiring faults, mastering mistakes or provenance.