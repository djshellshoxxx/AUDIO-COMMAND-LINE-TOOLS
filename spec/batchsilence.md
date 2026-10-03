# batchsilence (Beta)

`batchsilence` measures leading and trailing silence across an audio directory so export anomalies can be reviewed as a batch instead of one file at a time.

## Usage

```bash
bash bash/batchsilence.sh exports --json
bash bash/batchsilence.sh exports --threshold-db -55 --min-silence 0.15 --max-leading 1.0 --max-trailing 2.0
```

```powershell
./powershell/batchsilence.ps1 exports -Json
./powershell/batchsilence.ps1 exports -ThresholdDb -55 -MinSilence 0.15 -MaxLeading 1.0 -MaxTrailing 2.0
```

## Internals

Files are enumerated in deterministic path order. FFprobe provides duration. FFmpeg runs `silencedetect` using the configured threshold and minimum silence duration. The scripts parse the first silence run when it begins at time zero as leading silence. They inspect the final silence run and count it as trailing silence when it extends to the end of the file. Leading/trailing ratios are then calculated against total duration.

Optional maximum leading/trailing values turn measurements into policy checks. Exceeding a configured limit generates `excessive_leading_silence` or `excessive_trailing_silence`. Without explicit limits the tool remains informational.

Bash uses null-delimited `find` output, FFmpeg log parsing and `awk` for ratios. PowerShell uses `Get-ChildItem`, regular expressions and .NET doubles. Source files are never modified.

## Output

JSON includes a per-file ledger containing duration, leading/trailing silence seconds and ratios, plus effective thresholds, findings and dependency versions. Text mode summarizes the batch.

Exit `0` means the scan completed without configured-limit findings, `1` means one or more files exceeded configured limits, and `2` means the scan could not be completed.

## Limitations

Silence is threshold-dependent. Noise floors, dithering, room tone and lossy codec artifacts can shorten or eliminate detected silence. A long pre-roll or tail may be intentional. This tool reports timing evidence; it does not trim or rewrite audio.