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

The optional loudness pass asks FFmpeg's `ebur128` filter for integrated LUFS. That value is reported per file; version 0.1 does not use it to rewrite or normalize audio.

Each file is compared with the batch contract. Differences produce `sample_rate_outlier`, `channel_count_outlier` or `sample_format_outlier` findings. Ties in the inferred contract are resolved deterministically by the shell's sorted/grouped ordering rather than filesystem order.

Bash uses FFprobe plus `sort`, `uniq` and shell arrays. PowerShell uses FFprobe plus `Group-Object`, deterministic sorting and .NET values. Both versions only read source files.

## Output

The JSON report includes the inferred/expected contract and a per-file ledger. That makes the output usable by CI, ingest scripts and release checks without reparsing console text.

Exit `0` means every analyzed file matched the evaluated contract, `1` means one or more outliers were found, and `2` means analysis could not be completed.

## Limitations

The most common value is not necessarily the correct artistic or delivery specification. Mixed-format albums, surround bonus tracks and intentional sample-rate changes can legitimately trigger findings. For strict delivery work, prefer explicit expected values over inference.