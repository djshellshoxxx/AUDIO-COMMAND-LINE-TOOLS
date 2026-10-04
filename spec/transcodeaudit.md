# transcodeaudit (Beta)

`transcodeaudit` triages file and batch characteristics that can justify provenance review without claiming to prove transcoding history.

## Usage

```bash
bash bash/transcodeaudit.sh music --recursive --json
bash bash/transcodeaudit.sh track.mp3 --min-bitrate 192000 --json
```

```powershell
./powershell/transcodeaudit.ps1 music -Recursive -Json
./powershell/transcodeaudit.ps1 track.mp3 -MinBitrate 192000 -Json
```

## Internals

FFprobe supplies codec, container, sample rate, channels, reported bitrate, duration and encoder metadata. File size is recorded with a shell-portable byte count in Bash and `.Length` in PowerShell. Directory scans are deterministic.

A configured bitrate floor produces `low_reported_bitrate`. FLAC in an uncommon MP4/MOV delivery container produces `unusual_lossless_container`. Encoder metadata is always included when present.

## Output and exits

JSON contains a per-file ledger, findings and an explicit limitation that the observations cannot prove lossy-to-lossless transcode history. Exit `0` means no review findings, `1` means findings exist, and `2` means analysis could not be completed.

## v0.1 scope

A previous `show-tags` draft flag was removed from the v0.1 Beta interface because it did not change behavior. Encoder metadata remains part of the normal report.

## Limitations

This tool does not perform spectral-cutoff guessing and cannot establish an encoding chain. Treat every finding as a review cue, not provenance proof.
