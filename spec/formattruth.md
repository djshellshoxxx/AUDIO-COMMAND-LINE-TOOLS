# formattruth (Beta)

`formattruth` inspects an audio file's detected container, codec and stream layout and reports inconsistencies that deserve review.

## Usage

```bash
bash bash/formattruth.sh track.wav --json
bash bash/formattruth.sh track.wav --json --output formattruth.json
```

```powershell
./powershell/formattruth.ps1 track.wav -Json
./powershell/formattruth.ps1 track.wav -Json -Output formattruth.json
```

## Internals

FFprobe reads the first audio stream's codec, sample rate, channel count/layout, sample format, bit depth and bitrate plus container duration/name. All stream types are enumerated so non-audio streams can be surfaced. The filename extension is compared with the detected container for common WAV, FLAC, MP3, Ogg/Opus, M4A and AAC deliveries.

Findings are `extension_container_mismatch`, `non_audio_stream`, and `ambiguous_channel_layout`. Source files are read-only.

## Output and exits

JSON includes dependencies, measurements, findings and `ok`/`review` status. Exit `0` means no findings, `1` means review findings exist, and `2` means analysis could not be completed.

## v0.1 scope

Earlier design drafts mentioned configurable tag checks and a strict-extension switch. Those controls are intentionally deferred because they did not yet change analysis behavior. They are not part of the v0.1 Beta CLI.

## Limitations

Container/extension mismatches and unusual stream layouts can be intentional. A finding is evidence for review, not proof that a file is defective.
