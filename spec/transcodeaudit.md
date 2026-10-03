# transcodeaudit (Beta)

`transcodeaudit` is a batch triage tool for technical characteristics that may deserve provenance review. It does not claim to reconstruct an encoding history.

## Usage

```bash
bash bash/transcodeaudit.sh library --json
bash bash/transcodeaudit.sh library --recursive --min-bitrate 160000 --show-tags --output audit.json
```

```powershell
./powershell/transcodeaudit.ps1 library -Json
./powershell/transcodeaudit.ps1 library -Recursive -MinBitrate 160000 -ShowTags -Output audit.json
```

## Internals

Supported audio files are scanned in deterministic path order. FFprobe supplies codec, container, sample rate, channel count, bitrate, duration and encoder/writing-library tags when present. The scripts also record file size and normalize all values into one machine-readable ledger.

Rules are intentionally narrow. A user-configured bitrate floor can produce `low_reported_bitrate` evidence. FLAC in a MOV/MP4-family container produces `unusual_lossless_container` review evidence because it is uncommon in normal delivery workflows. The report always includes a limitation statement that these observations cannot prove lossy-to-lossless transcoding.

The Bash version performs discovery, comparisons and JSON serialization with shell built-ins plus common command-line utilities. The PowerShell version uses built-in .NET file APIs and `ConvertTo-Json`. FFprobe is the technical metadata source in both implementations.

## Output

Each file record contains path, codec/container, sample rate, channel count, reported bitrate, duration, file size and encoder metadata when available. Findings contain stable category names, the affected path and a short explanation.

Exit `0` means no configured rule generated a finding. Exit `1` means one or more files were flagged for review. Exit `2` means arguments, dependencies, inputs or report writing prevented completion.

## Limitations

Bitrate alone is not a quality score. Variable-bitrate codecs can report values differently. Encoder tags are optional and can be changed or removed. A lossless container does not reveal what happened to the signal before encoding. Spectral cutoff guessing is deliberately excluded because it creates too many codec- and source-dependent false positives.