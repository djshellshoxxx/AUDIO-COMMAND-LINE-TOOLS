# WinAudioForensics research and demand check

Research date: 2026-10-03.

## Why this tool

The useful PowerShell-shaped gap is not another WAV DSP command. Windows audio troubleshooting spans APIs and state stores that PowerShell can query naturally: services, CIM/PnP, signed driver metadata, registry endpoint records, event logs, and .NET/COM access to Core Audio.

The recurring user problem is also stateful. People report that a previously selected default endpoint changes after a new audio-capable device appears, a monitor/controller/dock reconnects, sleep/resume occurs, or software re-enables a virtual endpoint. Windows documentation confirms that endpoint state transitions such as insertion, removal, installation, enable, and disable can cause the default-endpoint selection logic to run again.

A snapshot/diff tool therefore addresses the part of troubleshooting that is usually missing: preserving enough evidence to say what changed between “working” and “broken.”

## Existing tools reviewed

### AudioDeviceCmdlets

Project: https://github.com/frgnca/AudioDeviceCmdlets

AudioDeviceCmdlets already provides useful PowerShell commands to list audio devices, inspect defaults, set default playback/recording/communications devices, and control volume/mute. WinAudioForensics should not duplicate that configuration role.

### WindowsAudioConfigurator

Project: https://github.com/h4ppywastaken/WindowsAudioConfigurator

This PowerShell project configures root audio devices and endpoints, default-device choices, and exclusive-mode options. It confirms that PowerShell is practical for Windows audio administration, while leaving a separate opportunity for a read-only historical evidence workflow.

### SoundVolumeView / SoundVolumeCommandLine

Project documentation: https://www.nirsoft.net/utils/sound_volume_view.html

SoundVolumeView is substantially broader than a simple volume tool. It can save/restore sound profiles, select default devices, change per-app defaults, modify default format, exclusive-mode settings, spatial sound, mute/volume, and more. This means WinAudioForensics should not claim novelty around profile capture or default-device control.

The differentiation is that WinAudioForensics combines Windows management evidence that a sound profile does not attempt to preserve: PnP problem state, signed driver metadata, service state, endpoint registry identity, optional relevant event-log records, deterministic before/after changes, and evidence rules.

## Windows platform behavior

Microsoft documentation:

- Default audio endpoint selection: https://learn.microsoft.com/en-us/windows-hardware/drivers/audio/default-audio-endpoint-selection
- Exclusive-mode streams: https://learn.microsoft.com/en-us/windows/win32/coreaudio/exclusive-mode-streams

Microsoft documents that only active endpoints participate in default selection and that events changing endpoint state can cause the audio subsystem to determine a new default endpoint. That behavior makes topology and endpoint-state changes directly relevant evidence when a user reports an unexpected route/default change.

The Core Audio exclusive-mode documentation also shows why endpoint configuration can affect application behavior, but the beta intentionally remains read-only rather than changing these options.

## Demand examples

Public troubleshooting discussions sampled during research include repeated requests to understand or prevent Windows default-audio switching when new devices are connected, monitors/controllers expose audio endpoints, or devices return after sleep/hibernate. Examples include:

- WindowsHelp, 2024: default audio device changes when a new device is detected: https://www.reddit.com/r/WindowsHelp/comments/1d3qcsm/
- WindowsHelp, 2025: smart-monitor updates create a newly recognized endpoint that becomes default: https://www.reddit.com/r/WindowsHelp/comments/1j30o9f/
- WindowsHelp, 2023: PS4 controller / VR headset endpoint switching: https://www.reddit.com/r/WindowsHelp/comments/10rhqdq/
- WindowsHelp, 2024: output switches while an apparently disabled device is involved: https://www.reddit.com/r/WindowsHelp/comments/1arwfft/
- Windows discussion, 2025: request for more control over audio Plug and Play/default behavior: https://www.reddit.com/r/windows/comments/1jknxng/

These posts are evidence of recurring troubleshooting demand, not a statistical market-size estimate.

## Selected product shape

Three candidate PowerShell tools were considered:

1. **Audio profile manager.** Strong PowerShell fit, but existing tools such as SoundVolumeView and AudioDeviceCmdlets already cover much of the useful behavior.
2. **DAW readiness/tuning auditor.** PowerShell could inspect power plans, USB power management, services, and drivers, but established tools such as LatencyMon already occupy important parts of the diagnostic space and many tuning recommendations are hardware/vendor specific.
3. **Windows audio state forensics.** Snapshot Windows-native evidence, diff it across time, derive conservative findings, and optionally watch for meaningful state changes.

The third option was selected because it uses PowerShell's strongest Windows-native capabilities while overlapping less with existing audio control tools.

## Claims and limits

The research does **not** establish that no other program can snapshot or compare Windows audio state. Individual primitives are widely available. The beta is positioned as an original integration of those primitives into a read-only, JSON-first troubleshooting workflow.

The tool must not claim that a changed driver, endpoint, service, or default *caused* an audio failure merely because it occurred between snapshots. It reports state change and correlation so a user can investigate with better evidence.
