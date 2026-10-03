# WinAudioForensics — specification

Status: beta target
Language: native PowerShell 7+ on Windows
Primary command: `WinAudioForensics.ps1`

## Purpose

WinAudioForensics is a Windows-native audio troubleshooting and change-forensics CLI. It captures an explainable snapshot of the Windows audio environment, compares snapshots, and reports configuration changes that can help explain symptoms such as a default output suddenly changing, a USB interface disappearing, a driver revision changing, an endpoint becoming disabled, or Windows Audio services stopping.

It is deliberately not a DSP tool. PowerShell is the implementation target because the useful evidence lives in Windows-native management surfaces: PnP/CIM, services, the registry, Windows event logs, installed driver metadata, and Core Audio endpoint state.

## Research rationale and gap

Existing PowerShell projects such as AudioDeviceCmdlets are good at listing devices, selecting defaults, and changing volume/mute. WindowsAudioConfigurator focuses on configuring/enable-disable behavior. NirSoft SoundVolumeView provides extensive profile and routing controls. The unmet workflow targeted here is *forensics across time*: produce a portable JSON state capture, diff two captures, correlate meaningful changes, and emit machine-readable findings without requiring a GUI or third-party runtime.

Windows itself can rerun its endpoint-selection logic when endpoint state changes, including when devices are inserted, removed, installed, enabled, or disabled. This makes before/after state comparison useful when the visible symptom is simply “Windows switched audio devices.”

The project must not claim that no overlapping software exists. The differentiation is the combined evidence model, snapshot/diff workflow, Windows-native implementation, deterministic JSON output, and testable rule engine.

## Scope

### In scope

1. Capture machine and PowerShell metadata.
2. Capture Windows Audio service state (`Audiosrv`, `AudioEndpointBuilder`).
3. Capture audio-related PnP devices and endpoints.
4. Capture signed audio driver metadata where available.
5. Capture MMDevices render/capture endpoint registry metadata without modifying it.
6. Capture current Core Audio default endpoint IDs for render/capture and console/multimedia/communications roles when Core Audio enumeration succeeds.
7. Capture recent relevant Windows event-log records from configurable providers/time windows.
8. Diff two snapshot JSON files.
9. Produce diagnostic findings from a snapshot and/or a diff.
10. Optional watch mode that periodically captures state and writes a snapshot only when the canonical audio-state fingerprint changes.
11. Human-readable console output plus JSON output suitable for automation.

### Out of scope for beta

- Changing the default device.
- Enabling/disabling devices.
- Editing MMDevices registry values.
- Changing sample formats or exclusive-mode settings.
- ASIO control-panel automation.
- Measuring DPC latency or real-time audio latency.
- Packet/audio capture.
- Inferring that a specific event *caused* a problem when only correlation is available.

## Safety model

All beta commands are read-only. The tool may create JSON/report files specified by the user but must not alter audio settings, devices, services, registry keys, or drivers.

## CLI

```text
WinAudioForensics.ps1 snapshot [-Output PATH] [-EventHours N] [-IncludeEvents] [-Compact]
WinAudioForensics.ps1 diff -Before PATH -After PATH [-Output PATH] [-Compact]
WinAudioForensics.ps1 doctor [-Snapshot PATH] [-Diff PATH] [-Output PATH] [-Compact]
WinAudioForensics.ps1 watch [-OutputDirectory PATH] [-IntervalSeconds N] [-Count N] [-EventHours N]
WinAudioForensics.ps1 help
```

### Exit codes

- `0`: command completed successfully; doctor found no `error`-severity finding.
- `1`: doctor completed and found one or more `error`-severity findings.
- `2`: invalid arguments, unsupported platform, malformed snapshot, or I/O/runtime failure.

## Snapshot schema

```json
{
  "schema": "circuit-drift.winaudioforensics.snapshot.v1",
  "captured_at_utc": "2026-10-03T20:00:00.0000000Z",
  "host": {"computer_name":"WORKSTATION","windows_version":"...","powershell_version":"..."},
  "services": [],
  "pnp_devices": [],
  "drivers": [],
  "endpoints": [],
  "defaults": [],
  "events": [],
  "warnings": []
}
```

Missing evidence is represented as `null`, an empty array, or a warning; one unavailable evidence source must not discard the rest of the snapshot.

## Canonical records

PnP/audio device fields: `instance_id`, `friendly_name`, `class`, `status`, `present`, `problem_code`, `manufacturer`, `service`.

Driver fields: `device_id`, `device_name`, `provider`, `driver_version`, `driver_date`, `inf_name`.

Endpoint fields: `flow`, `endpoint_id`, `friendly_name`, `device_interface`, `state`.

Default fields: `flow`, `role`, `endpoint_id`, `friendly_name`.

## Diff model

Diff output schema:

```json
{"schema":"circuit-drift.winaudioforensics.diff.v1","before":"timestamp","after":"timestamp","changes":[],"summary":{}}
```

Change types:

- `device_added`
- `device_removed`
- `device_status_changed`
- `driver_added`
- `driver_removed`
- `driver_changed`
- `endpoint_added`
- `endpoint_removed`
- `endpoint_state_changed`
- `default_changed`
- `service_state_changed`

Each change contains `type`, `key`, `before`, `after`, and `message`.

Comparison keys: PnP `instance_id`; driver `device_id`; endpoint `flow|endpoint_id`; default `flow|role`; service name. Ordering is deterministic by `type`, then `key`.

## Doctor rules

Rules are evidence statements, not diagnoses:

1. `audio-service-stopped` — error when `Audiosrv` or `AudioEndpointBuilder` is present and not running.
2. `audio-device-problem` — warning for audio PnP devices with non-OK status/problem code.
3. `no-active-render-default` — warning when render endpoints exist but no render default was collected.
4. `no-active-capture-default` — info when capture endpoints exist but no capture default was collected.
5. `default-endpoint-changed` — warning when any default role changes.
6. `driver-version-changed` — info when driver metadata changes.
7. `audio-device-added-or-removed` — info for topology changes.
8. `endpoint-state-changed` — warning when endpoint state/identity metadata changes.

Finding fields: `id`, `severity`, `title`, `evidence`, `suggestion`. Rules must never claim causality from temporal correlation alone.

## Event collection

With `-IncludeEvents`, query recent System events and retain compact fields: `time_created_utc`, `log_name`, `provider`, `event_id`, `level`, `message`. Candidate providers include Kernel-PnP, UserPnp, Service Control Manager, and available audio-related providers. Missing providers/logs are warnings, not fatal errors. Messages are normalized to one line and length-capped.

## Watch mode

Watch mode takes an initial snapshot, computes a canonical fingerprint excluding volatile fields (`captured_at_utc`, events, warnings), then polls at `IntervalSeconds`. When the fingerprint changes it writes the new snapshot, creates a diff from the previous state, writes the diff, and prints a one-line summary. `Count=0` means run until interrupted; minimum interval is 2 seconds.

## Architecture

```text
powershell/WinAudioForensics.psm1   # collectors + pure comparison/rule functions
powershell/WinAudioForensics.ps1    # CLI entry point
spec/winaudioforensics.md           # specification
site/docs/WINAUDIOFORENSICS.md      # published user guide
```

Public module functions: `Get-WafSnapshot`, `Compare-WafSnapshot`, `Get-WafFindings`, `Get-WafStateFingerprint`, `Test-WafSnapshot`.

Private helpers isolate registry/Core Audio/event-log access from pure data transforms.

## Core Audio access

Use an embedded minimal C# interop definition loaded through `Add-Type` to access documented Core Audio interfaces needed to enumerate default endpoints. If compilation/enumeration fails, add a warning and continue collecting remaining evidence. Do not include undocumented setters or configuration-changing COM calls.

## Pseudocode

```text
Get-WafSnapshot(options):
  assert Windows
  collect host + services + PnP + drivers + MMDevices endpoints
  try Core Audio defaults; warning on failure
  optionally collect recent events; warning on failure
  return normalized deterministic v1 snapshot

Compare-WafSnapshot(before, after):
  validate schemas
  index each collection by stable key
  emit additions/removals/meaningful field changes
  compare defaults by flow+role
  sort type+key and return summary counts

Get-WafFindings(snapshot, diff?):
  validate snapshot
  apply snapshot rules
  apply diff rules when supplied
  sort error, warning, info; then id

watch:
  previous = snapshot
  previousHash = fingerprint(previous)
  loop:
    current = snapshot
    if fingerprint(current) changed:
      write current and diff(previous,current)
      previous = current
```

## Testing requirements

Tests cover schema validation, added/removed devices, status changes, driver changes, default changes, service changes, deterministic ordering, doctor rules, fingerprint volatility exclusions, CLI help, and a Windows snapshot smoke test. Existing Python/JavaScript/browser tests must continue to pass. Windows CI runs the PowerShell test script.

## Documentation requirements

The project homepage must feature WinAudioForensics as a beta Windows-native PowerShell tool and clearly distinguish it from the existing Python/JavaScript WAV analysis tools. Documentation includes install/run examples, JSON behavior, troubleshooting use cases, limits, and the read-only guarantee.
