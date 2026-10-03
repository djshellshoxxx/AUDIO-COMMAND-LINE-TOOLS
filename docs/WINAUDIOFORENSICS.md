# WinAudioForensics

**Status: beta**  
**Platform: Windows**  
**Runtime: PowerShell 7+**

WinAudioForensics is a read-only PowerShell troubleshooting tool for answering a practical question: **what changed in Windows audio state?**

It captures audio services, PnP devices, signed drivers, MMDevices endpoints, Core Audio default roles, and optionally recent Windows events into JSON. Two captures can then be diffed to show endpoint, default-device, driver, service, and topology changes.

It does not change Windows audio settings.

## Why PowerShell

The useful evidence for this workflow is Windows-native rather than DSP-heavy. PowerShell can query CIM/PnP, services, the registry, Windows event logs, and load a small documented Core Audio interop layer without requiring Python or a separate executable.

Existing tools already handle tasks such as switching defaults, profiles, volume, exclusive mode, and application routing. This tool focuses on preserving and comparing troubleshooting evidence across time. See [the research and demand check](WINAUDIOFORENSICS_RESEARCH.md) for the alternatives reviewed and the reasoning behind this tool shape.

## Download

The GitHub Pages build produces:

`cdl-winaudioforensics-powershell.zip`

The bundle contains:

- `WinAudioForensics.ps1` — command-line entry point
- `WinAudioForensics.psm1` — collectors, diff engine, findings, fingerprinting
- project specifications and license

No external PowerShell modules are required for the beta.

## Snapshot

```powershell
.\WinAudioForensics.ps1 snapshot -Output before.json
```

Include recent relevant System log events:

```powershell
.\WinAudioForensics.ps1 snapshot -IncludeEvents -EventHours 12 -Output before.json
```

The snapshot can contain:

- `Audiosrv` and `AudioEndpointBuilder` state
- audio/media PnP devices and problem codes
- signed audio driver version/provider/date/INF data
- MMDevices render and capture endpoint registry metadata
- default render/capture endpoint IDs for Console, Multimedia, and Communications roles
- recent selected Windows event records when requested
- collector warnings when optional evidence cannot be read

One failed collector does not discard the rest of the snapshot.

## Compare two states

Capture the system while audio is working, then capture again after a problem appears:

```powershell
.\WinAudioForensics.ps1 snapshot -Output working.json
# reproduce the issue
.\WinAudioForensics.ps1 snapshot -IncludeEvents -EventHours 4 -Output broken.json
.\WinAudioForensics.ps1 diff -Before working.json -After broken.json -Output change.json
```

The diff can report:

- device added/removed
- device status/problem-code changes
- driver added/removed/version changes
- endpoint added/removed/state changes
- default endpoint changes by render/capture role
- Windows Audio service-state changes

All change records are ordered deterministically so JSON is practical to diff in source control or automation.

## Doctor report

Analyze a saved state:

```powershell
.\WinAudioForensics.ps1 doctor -Snapshot broken.json
```

Analyze a snapshot together with a diff:

```powershell
.\WinAudioForensics.ps1 doctor -Snapshot broken.json -Diff change.json -Output findings.json
```

Initial evidence rules include:

- Windows Audio service stopped
- audio/PnP device reporting a problem
- missing collected render/capture defaults when corresponding endpoints exist
- default endpoint changed
- driver metadata changed
- audio topology changed
- endpoint state changed

Findings describe evidence and next inspection steps. They do not claim that a temporally adjacent change caused the symptom.

## Watch for changes

```powershell
.\WinAudioForensics.ps1 watch -OutputDirectory .\audio-watch -IntervalSeconds 5
```

Watch mode fingerprints only meaningful state. Capture timestamp, event payloads, and collector warnings do not trigger a change by themselves.

When state changes, the tool writes:

- a new snapshot JSON file
- a diff from the previous state
- a concise console summary

Stop with `Ctrl+C`, or use `-Count` for a fixed number of polling iterations:

```powershell
.\WinAudioForensics.ps1 watch -IntervalSeconds 3 -Count 20
```

## Compact JSON

Add `-Compact` to `snapshot`, `diff`, or `doctor` when the output is intended for scripts rather than reading:

```powershell
.\WinAudioForensics.ps1 snapshot -Compact > state.json
```

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | command completed; `doctor` found no error-severity finding |
| `1` | `doctor` completed and found at least one error-severity finding |
| `2` | invalid arguments, malformed input, unsupported platform, or runtime/I/O failure |

## Example troubleshooting cases

### USB interface stopped being the default

Take a known-good snapshot. Reproduce a disconnect/reconnect, dock cycle, sleep/resume, controller insertion, driver update, or other trigger. Take a second snapshot and diff them.

A useful report might show a newly present endpoint, a driver change, or a changed Console default at the same time. That narrows the investigation without asserting causality.

### Audio disappeared after an update

Use `doctor` on the post-update snapshot and inspect:

- audio services
- device problem codes
- driver version/date/provider changes
- endpoint presence
- recent PnP/Service Control Manager events

### Intermittent route changes

Use `watch` during normal use. Because it writes only on state changes, it can leave a compact history of what Windows audio state actually changed rather than requiring constant manual screenshots.

## Limits

- Windows only.
- PowerShell 7+ is the tested/supported beta runtime.
- Beta collectors are read-only.
- No DPC-latency measurement.
- No ASIO control-panel automation.
- No sample-rate/exclusive-mode modification.
- Event log provider availability differs across Windows versions and driver stacks.
- Core Audio default enumeration may fail on unusual/headless systems; this becomes a snapshot warning rather than a fatal failure.
- A diff identifies correlation and state change, not root-cause proof.

See [`spec/winaudioforensics.md`](../spec/winaudioforensics.md) for the full engineering specification and pseudocode.
