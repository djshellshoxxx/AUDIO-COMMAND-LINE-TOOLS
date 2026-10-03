$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repo 'powershell/WinAudioForensics.psm1'
$cliPath = Join-Path $repo 'powershell/WinAudioForensics.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT TRUE FAILED: $Message" }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "ASSERT EQUAL FAILED: $Message`nExpected: $Expected`nActual:   $Actual"
    }
}

function New-FixtureSnapshot {
    param(
        [string]$Timestamp = '2026-10-03T20:00:00.0000000Z',
        [array]$Services = @(),
        [array]$PnpDevices = @(),
        [array]$Drivers = @(),
        [array]$Endpoints = @(),
        [array]$Defaults = @(),
        [array]$Events = @(),
        [array]$Warnings = @()
    )
    [pscustomobject]@{
        schema = 'circuit-drift.winaudioforensics.snapshot.v1'
        captured_at_utc = $Timestamp
        host = [pscustomobject]@{ computer_name = 'TEST'; windows_version = 'test'; powershell_version = $PSVersionTable.PSVersion.ToString() }
        services = @($Services)
        pnp_devices = @($PnpDevices)
        drivers = @($Drivers)
        endpoints = @($Endpoints)
        defaults = @($Defaults)
        events = @($Events)
        warnings = @($Warnings)
    }
}

if (-not (Test-Path $modulePath)) {
    throw "Expected module does not exist yet: $modulePath"
}
Import-Module $modulePath -Force

# schema validation
$valid = New-FixtureSnapshot
Assert-True (Test-WafSnapshot -Snapshot $valid) 'v1 snapshot should validate'
$invalid = $valid.PSObject.Copy()
$invalid.schema = 'wrong.schema'
Assert-True (-not (Test-WafSnapshot -Snapshot $invalid)) 'wrong schema should fail validation'

# rich diff fixture
$before = New-FixtureSnapshot `
    -Services @(
        [pscustomobject]@{ name='Audiosrv'; status='Running'; start_type='Automatic' },
        [pscustomobject]@{ name='AudioEndpointBuilder'; status='Running'; start_type='Automatic' }
    ) `
    -PnpDevices @(
        [pscustomobject]@{ instance_id='DEV_A'; friendly_name='Interface A'; class='MEDIA'; status='OK'; present=$true; problem_code=0; manufacturer='Acme'; service='acme' }
    ) `
    -Drivers @(
        [pscustomobject]@{ device_id='DEV_A'; device_name='Interface A'; provider='Acme'; driver_version='1.0.0'; driver_date='2026-01-01'; inf_name='oem1.inf' }
    ) `
    -Endpoints @(
        [pscustomobject]@{ flow='render'; endpoint_id='END_A'; friendly_name='Interface A Out'; device_interface='DEV_A'; state='Active' }
    ) `
    -Defaults @(
        [pscustomobject]@{ flow='render'; role='console'; endpoint_id='END_A'; friendly_name='Interface A Out' },
        [pscustomobject]@{ flow='render'; role='communications'; endpoint_id='END_A'; friendly_name='Interface A Out' }
    )

$after = New-FixtureSnapshot `
    -Timestamp '2026-10-03T21:00:00.0000000Z' `
    -Services @(
        [pscustomobject]@{ name='Audiosrv'; status='Stopped'; start_type='Automatic' },
        [pscustomobject]@{ name='AudioEndpointBuilder'; status='Running'; start_type='Automatic' }
    ) `
    -PnpDevices @(
        [pscustomobject]@{ instance_id='DEV_A'; friendly_name='Interface A'; class='MEDIA'; status='Error'; present=$true; problem_code=10; manufacturer='Acme'; service='acme' },
        [pscustomobject]@{ instance_id='DEV_B'; friendly_name='USB Headset'; class='AudioEndpoint'; status='OK'; present=$true; problem_code=0; manufacturer='Example'; service='usbaudio' }
    ) `
    -Drivers @(
        [pscustomobject]@{ device_id='DEV_A'; device_name='Interface A'; provider='Acme'; driver_version='2.0.0'; driver_date='2026-09-30'; inf_name='oem2.inf' },
        [pscustomobject]@{ device_id='DEV_B'; device_name='USB Headset'; provider='Microsoft'; driver_version='10.0.1'; driver_date='2026-08-01'; inf_name='wdma_usb.inf' }
    ) `
    -Endpoints @(
        [pscustomobject]@{ flow='render'; endpoint_id='END_A'; friendly_name='Interface A Out'; device_interface='DEV_A'; state='Active' },
        [pscustomobject]@{ flow='render'; endpoint_id='END_B'; friendly_name='USB Headset'; device_interface='DEV_B'; state='Active' }
    ) `
    -Defaults @(
        [pscustomobject]@{ flow='render'; role='console'; endpoint_id='END_B'; friendly_name='USB Headset' },
        [pscustomobject]@{ flow='render'; role='communications'; endpoint_id='END_A'; friendly_name='Interface A Out' }
    )

$diff = Compare-WafSnapshot -Before $before -After $after
Assert-Equal $diff.schema 'circuit-drift.winaudioforensics.diff.v1' 'diff schema'
$types = @($diff.changes | ForEach-Object type)
foreach ($expected in @('device_added','device_status_changed','driver_added','driver_changed','endpoint_added','default_changed','service_state_changed')) {
    Assert-True ($types -contains $expected) "diff should contain $expected"
}
Assert-Equal (@($diff.changes | Where-Object type -eq 'default_changed').Count) 1 'one default change expected'

# deterministic change ordering
$ordered = @($diff.changes | ForEach-Object { '{0}|{1}' -f $_.type, $_.key })
$sorted = @($ordered | Sort-Object)
Assert-Equal ($ordered -join "`n") ($sorted -join "`n") 'changes should be sorted by type then key'

# doctor rules
$findings = @(Get-WafFindings -Snapshot $after -Diff $diff)
Assert-True ((@($findings | Where-Object id -eq 'audio-service-stopped').Count) -ge 1) 'stopped Audiosrv should be reported'
Assert-True ((@($findings | Where-Object id -eq 'audio-device-problem').Count) -ge 1) 'problem device should be reported'
Assert-True ((@($findings | Where-Object id -eq 'default-endpoint-changed').Count) -ge 1) 'default change should be reported'
Assert-True ((@($findings | Where-Object id -eq 'driver-version-changed').Count) -ge 1) 'driver change should be reported'

# fingerprint ignores volatile evidence but detects meaningful state changes
$f1 = Get-WafStateFingerprint -Snapshot $before
$volatileOnly = New-FixtureSnapshot `
    -Timestamp '2026-10-04T01:02:03.0000000Z' `
    -Services $before.services -PnpDevices $before.pnp_devices -Drivers $before.drivers -Endpoints $before.endpoints -Defaults $before.defaults `
    -Events @([pscustomobject]@{ event_id=1 }) -Warnings @('collector warning')
$f2 = Get-WafStateFingerprint -Snapshot $volatileOnly
Assert-Equal $f1 $f2 'timestamp/events/warnings should not affect state fingerprint'
$f3 = Get-WafStateFingerprint -Snapshot $after
Assert-True ($f1 -ne $f3) 'meaningful state changes should affect fingerprint'

# CLI help should be side-effect free and return success
if (-not (Test-Path $cliPath)) { throw "Expected CLI does not exist yet: $cliPath" }
& pwsh -NoProfile -File $cliPath help | Out-Null
Assert-Equal $LASTEXITCODE 0 'help should return exit code 0'

# Real Windows collector smoke test: stdout must remain parseable JSON even when optional collectors warn.
$snapshotText = (& pwsh -NoProfile -File $cliPath snapshot -Compact | Out-String).Trim()
Assert-Equal $LASTEXITCODE 0 'snapshot smoke test should return exit code 0'
Assert-True (-not [string]::IsNullOrWhiteSpace($snapshotText)) 'snapshot smoke test should emit JSON'
$smoke = $snapshotText | ConvertFrom-Json
Assert-Equal $smoke.schema 'circuit-drift.winaudioforensics.snapshot.v1' 'snapshot smoke schema'
Assert-True ($null -ne $smoke.host) 'snapshot should contain host metadata'
Assert-True ($null -ne $smoke.services) 'snapshot should contain services collection'
Assert-True ($null -ne $smoke.pnp_devices) 'snapshot should contain PnP collection'
Assert-True ($null -ne $smoke.drivers) 'snapshot should contain driver collection'
Assert-True ($null -ne $smoke.endpoints) 'snapshot should contain endpoint collection'
Assert-True ($null -ne $smoke.defaults) 'snapshot should contain defaults collection'
Assert-True ($null -ne $smoke.warnings) 'snapshot should contain warnings collection'

Write-Host 'WinAudioForensics tests passed.'
