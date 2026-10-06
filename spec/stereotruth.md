# stereotruth (Beta)

`stereotruth` looks for stereo files whose channel relationship suggests dual-mono content, sustained polarity inversion, or a large left/right RMS imbalance.

## Usage

```bash
bash bash/stereotruth.sh mix.wav --json
bash bash/stereotruth.sh mix.wav --dual-mono-correlation 0.998 --negative-correlation -0.95 --imbalance-db 2.5 --json
```

```powershell
./powershell/stereotruth.ps1 mix.wav -Json
./powershell/stereotruth.ps1 mix.wav -DualMonoCorrelation 0.998 -NegativeCorrelation -0.95 -ImbalanceDb 2.5 -Json
```

## Internals

FFmpeg's `aphasemeter` metadata supplies a stream of stereo phase/correlation values. The scripts count windows that meet the configured high-correlation and negative-correlation thresholds. FFmpeg `astats` supplies left/right RMS levels and the scripts compare their absolute dB difference against `imbalance-db`.

Findings are `dual_mono_candidate`, `polarity_inversion_candidate`, and `channel_imbalance`. Source audio is never modified.

## Output and exits

JSON reports the correlation ratios, mean correlation, left/right RMS values, RMS balance, effective thresholds and findings. Exit `0` means no findings, `1` means review findings exist, and `2` means analysis could not be completed.

## v0.1 scope

Draft controls for custom window size, delay search and activity gating were removed from the v0.1 Beta CLI because those values were previously recorded but did not alter the DSP path. They will only return if implemented and regression-tested.

## Limitations

High correlation can be intentional and negative correlation does not by itself prove a wiring defect or mono incompatibility. Treat results as evidence for listening and technical review.
