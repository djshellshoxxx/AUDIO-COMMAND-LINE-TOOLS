# albumcontract (Beta)

`albumcontract` audits a directory as one delivery set. It identifies files whose technical properties differ from the dominant batch contract or from explicit expected values.

## Usage

```bash
bash bash/albumcontract.sh album --json
bash bash/albumcontract.sh exports --recursive --expected-rate 48000 --expected-channels 2 --loudness
```

```powershell
./powershell/albumcontract.ps1 album -Json
./powershell/albumcontract.ps1 exports -Recursive -ExpectedRate 48000 -ExpectedChannels 2 -Loudness
```

## Internals

Files are discovered in deterministic path order. FFprobe extracts sample rate, decoded channel count, sample format, codec and container for every supported audio file. The scripts count each property and select the most common value as the inferred contract. Explicit expected rate/channel arguments override inference.

The optional loudness pass asks FFmpeg's `ebur128` filter for integrated LUFS and reports the value per file. Version 0.1 does not use loudness to rewrite, normalize or classify files.

Each file is compared with the batch contract. Differences produce `sample_rate_outlier`, `channel_count_outlier` or `sample_format_outlier` findings.

## Output and exits

JSON includes the inferred or expected contract, effective options and a per-file ledger. Exit `0` means every analyzed file matched the evaluated contract, `1` means one or more outliers were found, and `2` means analysis could not be completed.

## v0.1 scope

A draft loudness-tolerance option was removed because it was not wired to a finding rule. Loudness is measurement-only in v0.1 Beta.

## Limitations

The dominant value is not necessarily the correct artistic or delivery specification. Mixed-format albums, surround bonus tracks and intentional sample-rate changes can legitimately trigger findings. For strict delivery work, prefer explicit expected values over inference.
