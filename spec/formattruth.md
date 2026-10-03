# formattruth (Beta)

`formattruth` turns FFprobe's low-level stream/container facts into a concise consistency audit. It is useful when extensions, containers, codecs, bit-depth fields or stream layouts do not line up as expected.

## Usage

```bash
bash bash/formattruth.sh "track 01.wav" --json
bash bash/formattruth.sh suspect.flac --strict-extension --output format.json
```

```powershell
./powershell/formattruth.ps1 "track 01.wav" -Json
./powershell/formattruth.ps1 suspect.flac -StrictExtension -Output format.json
```

## Internals

FFprobe supplies the first audio stream's codec name, long codec name, sample format, raw/sample bit depth when available, sample rate, channel count/layout and bitrate. A format-level probe supplies duration and detected container names. A separate stream enumeration counts non-audio streams.

The shell layer compares the filename extension with a deliberately small mapping of common container families. For example `.wav` is expected to probe as WAV, `.flac` as FLAC, and `.m4a` as a MOV/MP4-family container. Because many containers legitimately carry multiple codecs, the tool reports mismatches as review candidates rather than corruption.

Bash serializes the normalized result without `jq`; PowerShell uses built-in `ConvertTo-Json`. Both preserve the same core measurement and finding names.

## Findings

`extension_container_mismatch` means the extension and detected container family differ. `non_audio_stream` means the file contains additional stream types. `ambiguous_channel_layout` means FFprobe could not provide a useful layout string.

## Output and exit codes

JSON contains dependency versions, effective options, all normalized measurements, findings and final status. Text output is a short summary. Exit `0` means no findings, `1` means completed with review findings, and `2` means invalid arguments, missing dependencies, unreadable input or probe/report failure.

## Limitations

A container/extension mismatch is not proof of corruption. Bit-depth metadata is format-dependent and some codecs do not expose meaningful `bits_per_sample`. The tool does not decode every stream to prove that every packet is valid; it is a fast structural audit.