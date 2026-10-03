Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SnapshotSchema = 'circuit-drift.winaudioforensics.snapshot.v1'
$script:DiffSchema = 'circuit-drift.winaudioforensics.diff.v1'

function Get-WafProp {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $Default }
    return $p.Value
}

function Test-WafSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Snapshot)
    if ($null -eq $Snapshot) { return $false }
    if ((Get-WafProp $Snapshot 'schema') -ne $script:SnapshotSchema) { return $false }
    foreach ($name in @('captured_at_utc','host','services','pnp_devices','drivers','endpoints','defaults','events','warnings')) {
        if ($null -eq $Snapshot.PSObject.Properties[$name]) { return $false }
    }
    return $true
}

function New-WafChange {
    param([string]$Type, [string]$Key, $Before, $After, [string]$Message)
    [pscustomobject]@{
        type = $Type
        key = $Key
        before = $Before
        after = $After
        message = $Message
    }
}

function New-WafIndex {
    param([array]$Items, [scriptblock]$KeySelector)
    $index = @{}
    foreach ($item in @($Items)) {
        $key = & $KeySelector $item
        if (-not [string]::IsNullOrWhiteSpace([string]$key)) { $index[[string]$key] = $item }
    }
    return $index
}

function Test-WafFieldsChanged {
    param($Before, $After, [string[]]$Fields)
    foreach ($field in $Fields) {
        $a = Get-WafProp $Before $field
        $b = Get-WafProp $After $field
        if ([string]$a -ne [string]$b) { return $true }
    }
    return $false
}

function Compare-WafSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Before,
        [Parameter(Mandatory)]$After
    )
    if (-not (Test-WafSnapshot $Before)) { throw 'Before snapshot is not a valid WinAudioForensics v1 snapshot.' }
    if (-not (Test-WafSnapshot $After)) { throw 'After snapshot is not a valid WinAudioForensics v1 snapshot.' }

    $changes = New-Object System.Collections.Generic.List[object]

    $beforeDevices = New-WafIndex @($Before.pnp_devices) { param($x) Get-WafProp $x 'instance_id' }
    $afterDevices = New-WafIndex @($After.pnp_devices) { param($x) Get-WafProp $x 'instance_id' }
    foreach ($key in @($beforeDevices.Keys + $afterDevices.Keys | Sort-Object -Unique)) {
        if (-not $beforeDevices.ContainsKey($key)) {
            $changes.Add((New-WafChange 'device_added' $key $null $afterDevices[$key] "Audio/PnP device added: $key"))
        } elseif (-not $afterDevices.ContainsKey($key)) {
            $changes.Add((New-WafChange 'device_removed' $key $beforeDevices[$key] $null "Audio/PnP device removed: $key"))
        } elseif (Test-WafFieldsChanged $beforeDevices[$key] $afterDevices[$key] @('status','present','problem_code','friendly_name','class','service')) {
            $changes.Add((New-WafChange 'device_status_changed' $key $beforeDevices[$key] $afterDevices[$key] "Audio/PnP device state changed: $key"))
        }
    }

    $beforeDrivers = New-WafIndex @($Before.drivers) { param($x) Get-WafProp $x 'device_id' }
    $afterDrivers = New-WafIndex @($After.drivers) { param($x) Get-WafProp $x 'device_id' }
    foreach ($key in @($beforeDrivers.Keys + $afterDrivers.Keys | Sort-Object -Unique)) {
        if (-not $beforeDrivers.ContainsKey($key)) {
            $changes.Add((New-WafChange 'driver_added' $key $null $afterDrivers[$key] "Audio driver added: $key"))
        } elseif (-not $afterDrivers.ContainsKey($key)) {
            $changes.Add((New-WafChange 'driver_removed' $key $beforeDrivers[$key] $null "Audio driver removed: $key"))
        } elseif (Test-WafFieldsChanged $beforeDrivers[$key] $afterDrivers[$key] @('provider','driver_version','driver_date','inf_name','device_name')) {
            $changes.Add((New-WafChange 'driver_changed' $key $beforeDrivers[$key] $afterDrivers[$key] "Audio driver metadata changed: $key"))
        }
    }

    $beforeEndpoints = New-WafIndex @($Before.endpoints) { param($x) '{0}|{1}' -f (Get-WafProp $x 'flow'), (Get-WafProp $x 'endpoint_id') }
    $afterEndpoints = New-WafIndex @($After.endpoints) { param($x) '{0}|{1}' -f (Get-WafProp $x 'flow'), (Get-WafProp $x 'endpoint_id') }
    foreach ($key in @($beforeEndpoints.Keys + $afterEndpoints.Keys | Sort-Object -Unique)) {
        if (-not $beforeEndpoints.ContainsKey($key)) {
            $changes.Add((New-WafChange 'endpoint_added' $key $null $afterEndpoints[$key] "Audio endpoint added: $key"))
        } elseif (-not $afterEndpoints.ContainsKey($key)) {
            $changes.Add((New-WafChange 'endpoint_removed' $key $beforeEndpoints[$key] $null "Audio endpoint removed: $key"))
        } elseif (Test-WafFieldsChanged $beforeEndpoints[$key] $afterEndpoints[$key] @('state','friendly_name','device_interface')) {
            $changes.Add((New-WafChange 'endpoint_state_changed' $key $beforeEndpoints[$key] $afterEndpoints[$key] "Audio endpoint state changed: $key"))
        }
    }

    $beforeDefaults = New-WafIndex @($Before.defaults) { param($x) '{0}|{1}' -f (Get-WafProp $x 'flow'), (Get-WafProp $x 'role') }
    $afterDefaults = New-WafIndex @($After.defaults) { param($x) '{0}|{1}' -f (Get-WafProp $x 'flow'), (Get-WafProp $x 'role') }
    foreach ($key in @($beforeDefaults.Keys + $afterDefaults.Keys | Sort-Object -Unique)) {
        $b = if ($beforeDefaults.ContainsKey($key)) { $beforeDefaults[$key] } else { $null }
        $a = if ($afterDefaults.ContainsKey($key)) { $afterDefaults[$key] } else { $null }
        if (([string](Get-WafProp $b 'endpoint_id')) -ne ([string](Get-WafProp $a 'endpoint_id'))) {
            $changes.Add((New-WafChange 'default_changed' $key $b $a "Default audio endpoint changed for $key"))
        }
    }

    $beforeServices = New-WafIndex @($Before.services) { param($x) Get-WafProp $x 'name' }
    $afterServices = New-WafIndex @($After.services) { param($x) Get-WafProp $x 'name' }
    foreach ($key in @($beforeServices.Keys + $afterServices.Keys | Sort-Object -Unique)) {
        $b = if ($beforeServices.ContainsKey($key)) { $beforeServices[$key] } else { $null }
        $a = if ($afterServices.ContainsKey($key)) { $afterServices[$key] } else { $null }
        if ($null -eq $b -or $null -eq $a -or (Test-WafFieldsChanged $b $a @('status','start_type'))) {
            $changes.Add((New-WafChange 'service_state_changed' $key $b $a "Audio service state changed: $key"))
        }
    }

    $sortedChanges = @($changes | Sort-Object type,key)
    $summary = [ordered]@{}
    foreach ($group in @($sortedChanges | Group-Object type | Sort-Object Name)) { $summary[$group.Name] = $group.Count }

    [pscustomobject]@{
        schema = $script:DiffSchema
        before = [string]$Before.captured_at_utc
        after = [string]$After.captured_at_utc
        changes = $sortedChanges
        summary = [pscustomobject]$summary
    }
}

function New-WafFinding {
    param([string]$Id, [string]$Severity, [string]$Title, [string]$Evidence, [string]$Suggestion)
    [pscustomobject]@{ id=$Id; severity=$Severity; title=$Title; evidence=$Evidence; suggestion=$Suggestion }
}

function Get-WafFindings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Snapshot,
        $Diff = $null
    )
    if (-not (Test-WafSnapshot $Snapshot)) { throw 'Snapshot is not a valid WinAudioForensics v1 snapshot.' }
    $findings = New-Object System.Collections.Generic.List[object]

    foreach ($svc in @($Snapshot.services)) {
        $name = [string](Get-WafProp $svc 'name')
        $status = [string](Get-WafProp $svc 'status')
        if (($name -in @('Audiosrv','AudioEndpointBuilder')) -and $status -and $status -ne 'Running') {
            $findings.Add((New-WafFinding 'audio-service-stopped' 'error' "$name is not running" "$name status=$status" 'Inspect the service failure and related Service Control Manager events before changing audio configuration.'))
        }
    }

    foreach ($dev in @($Snapshot.pnp_devices)) {
        $status = [string](Get-WafProp $dev 'status')
        $problem = Get-WafProp $dev 'problem_code' 0
        if (($status -and $status -ne 'OK') -or ([int]$problem -ne 0)) {
            $id = [string](Get-WafProp $dev 'instance_id')
            $findings.Add((New-WafFinding 'audio-device-problem' 'warning' 'Audio/PnP device reports a problem' "$id status=$status problem_code=$problem" 'Review Device Manager/PnP events and the matching driver record.'))
        }
    }

    $renderEndpoints = @($Snapshot.endpoints | Where-Object { (Get-WafProp $_ 'flow') -eq 'render' })
    $captureEndpoints = @($Snapshot.endpoints | Where-Object { (Get-WafProp $_ 'flow') -eq 'capture' })
    $renderDefaults = @($Snapshot.defaults | Where-Object { (Get-WafProp $_ 'flow') -eq 'render' })
    $captureDefaults = @($Snapshot.defaults | Where-Object { (Get-WafProp $_ 'flow') -eq 'capture' })
    if ($renderEndpoints.Count -gt 0 -and $renderDefaults.Count -eq 0) {
        $findings.Add((New-WafFinding 'no-active-render-default' 'warning' 'No render default was collected' 'Render endpoints exist but no render default role was returned.' 'Check endpoint state and any Core Audio collection warning in the snapshot.'))
    }
    if ($captureEndpoints.Count -gt 0 -and $captureDefaults.Count -eq 0) {
        $findings.Add((New-WafFinding 'no-active-capture-default' 'info' 'No capture default was collected' 'Capture endpoints exist but no capture default role was returned.' 'If capture is expected, check microphone endpoint state and Core Audio warnings.'))
    }

    if ($null -ne $Diff) {
        foreach ($change in @($Diff.changes)) {
            switch ([string]$change.type) {
                'default_changed' {
                    $findings.Add((New-WafFinding 'default-endpoint-changed' 'warning' 'A default audio endpoint changed' ([string]$change.message) 'Compare device add/remove/state changes at the same time; the diff shows correlation, not proof of cause.'))
                }
                'driver_changed' {
                    $findings.Add((New-WafFinding 'driver-version-changed' 'info' 'Audio driver metadata changed' ([string]$change.message) 'Compare driver version/date/provider and nearby installation/PnP events.'))
                }
                { $_ -in @('device_added','device_removed') } {
                    $findings.Add((New-WafFinding 'audio-device-added-or-removed' 'info' 'Audio device topology changed' ([string]$change.message) 'Check whether this coincides with a changed default endpoint.'))
                }
                'endpoint_state_changed' {
                    $findings.Add((New-WafFinding 'endpoint-state-changed' 'warning' 'Audio endpoint state changed' ([string]$change.message) 'Check device/PnP state and any default-endpoint changes in the same diff.'))
                }
            }
        }
    }

    $rank = @{ error=0; warning=1; info=2 }
    return @($findings | Sort-Object @{Expression={ $rank[[string]$_.severity] }},id,evidence)
}

function Get-WafStateFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Snapshot)
    if (-not (Test-WafSnapshot $Snapshot)) { throw 'Snapshot is not a valid WinAudioForensics v1 snapshot.' }
    $canonical = [ordered]@{
        services = @($Snapshot.services | Sort-Object name | ForEach-Object { [ordered]@{ name=(Get-WafProp $_ 'name'); status=(Get-WafProp $_ 'status'); start_type=(Get-WafProp $_ 'start_type') } })
        pnp_devices = @($Snapshot.pnp_devices | Sort-Object instance_id | ForEach-Object { [ordered]@{ instance_id=(Get-WafProp $_ 'instance_id'); friendly_name=(Get-WafProp $_ 'friendly_name'); class=(Get-WafProp $_ 'class'); status=(Get-WafProp $_ 'status'); present=(Get-WafProp $_ 'present'); problem_code=(Get-WafProp $_ 'problem_code'); manufacturer=(Get-WafProp $_ 'manufacturer'); service=(Get-WafProp $_ 'service') } })
        drivers = @($Snapshot.drivers | Sort-Object device_id | ForEach-Object { [ordered]@{ device_id=(Get-WafProp $_ 'device_id'); device_name=(Get-WafProp $_ 'device_name'); provider=(Get-WafProp $_ 'provider'); driver_version=(Get-WafProp $_ 'driver_version'); driver_date=(Get-WafProp $_ 'driver_date'); inf_name=(Get-WafProp $_ 'inf_name') } })
        endpoints = @($Snapshot.endpoints | Sort-Object flow,endpoint_id | ForEach-Object { [ordered]@{ flow=(Get-WafProp $_ 'flow'); endpoint_id=(Get-WafProp $_ 'endpoint_id'); friendly_name=(Get-WafProp $_ 'friendly_name'); device_interface=(Get-WafProp $_ 'device_interface'); state=(Get-WafProp $_ 'state') } })
        defaults = @($Snapshot.defaults | Sort-Object flow,role | ForEach-Object { [ordered]@{ flow=(Get-WafProp $_ 'flow'); role=(Get-WafProp $_ 'role'); endpoint_id=(Get-WafProp $_ 'endpoint_id'); friendly_name=(Get-WafProp $_ 'friendly_name') } })
    }
    $json = $canonical | ConvertTo-Json -Depth 10 -Compress
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($json)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Get-WafServiceState {
    $result = @()
    foreach ($name in @('Audiosrv','AudioEndpointBuilder')) {
        try {
            $svc = Get-CimInstance Win32_Service -Filter "Name='$name'" -ErrorAction Stop
            if ($null -ne $svc) {
                $result += [pscustomobject]@{ name=$name; status=[string]$svc.State; start_type=[string]$svc.StartMode }
            }
        } catch {
            try {
                $svc2 = Get-Service -Name $name -ErrorAction Stop
                $result += [pscustomobject]@{ name=$name; status=[string]$svc2.Status; start_type=$null }
            } catch { }
        }
    }
    return @($result | Sort-Object name)
}

function Get-WafPnpDevices {
    $items = @()
    try {
        $rows = Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object {
            $_.PNPClass -in @('AudioEndpoint','MEDIA','Sound') -or $_.Service -match 'audio|portcls|usbaudio'
        }
        foreach ($d in $rows) {
            $items += [pscustomobject]@{
                instance_id = [string]$d.PNPDeviceID
                friendly_name = [string]$d.Name
                class = [string]$d.PNPClass
                status = [string]$d.Status
                present = $d.Present
                problem_code = if ($null -ne $d.ConfigManagerErrorCode) { [int]$d.ConfigManagerErrorCode } else { 0 }
                manufacturer = [string]$d.Manufacturer
                service = [string]$d.Service
            }
        }
    } catch { throw "PnP collector failed: $($_.Exception.Message)" }
    return @($items | Sort-Object instance_id)
}

function Get-WafDrivers {
    $items = @()
    try {
        $rows = Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop | Where-Object {
            $_.DeviceClass -eq 'MEDIA' -or $_.DeviceName -match 'audio|sound|microphone|speaker|headset'
        }
        foreach ($d in $rows) {
            $date = $null
            if ($null -ne $d.DriverDate) {
                try { $date = ([Management.ManagementDateTimeConverter]::ToDateTime([string]$d.DriverDate)).ToUniversalTime().ToString('o') } catch { $date = [string]$d.DriverDate }
            }
            $items += [pscustomobject]@{
                device_id = [string]$d.DeviceID
                device_name = [string]$d.DeviceName
                provider = [string]$d.DriverProviderName
                driver_version = [string]$d.DriverVersion
                driver_date = $date
                inf_name = [string]$d.InfName
            }
        }
    } catch { throw "Driver collector failed: $($_.Exception.Message)" }
    return @($items | Sort-Object device_id)
}

function Get-WafEndpoints {
    $items = @()
    foreach ($flow in @('Render','Capture')) {
        $root = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\$flow"
        if (-not (Test-Path $root)) { continue }
        foreach ($key in @(Get-ChildItem $root -ErrorAction SilentlyContinue)) {
            $friendly = $null; $iface = $null; $state = $null
            try {
                $props = Get-ItemProperty (Join-Path $key.PSPath 'Properties') -ErrorAction Stop
                $friendly = Get-WafProp $props '{a45c254e-df1c-4efd-8020-67d146a850e0},2'
                $iface = Get-WafProp $props '{b3f8fa53-0004-438e-9003-51a46e139bfc},6'
            } catch { }
            try {
                $base = Get-ItemProperty $key.PSPath -ErrorAction Stop
                $state = Get-WafProp $base 'DeviceState'
            } catch { }
            $items += [pscustomobject]@{
                flow = $flow.ToLowerInvariant()
                endpoint_id = [string]$key.PSChildName
                friendly_name = if ($null -ne $friendly) { [string]$friendly } else { $null }
                device_interface = if ($null -ne $iface) { [string]$iface } else { $null }
                state = if ($null -ne $state) { [string]$state } else { $null }
            }
        }
    }
    return @($items | Sort-Object flow,endpoint_id)
}

function Initialize-WafCoreAudio {
    if ('CircuitDrift.WinAudio.CoreAudioProbe' -as [type]) { return }
    $src = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace CircuitDrift.WinAudio {
  public enum EDataFlow { Render=0, Capture=1, All=2 }
  public enum ERole { Console=0, Multimedia=1, Communications=2 }
  [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDevice {
    int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object interfacePointer);
    int OpenPropertyStore(int stgmAccess, out IntPtr properties);
    int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
    int GetState(out int state);
  }
  [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDeviceEnumerator {
    int EnumAudioEndpoints(EDataFlow dataFlow, int stateMask, out IntPtr devices);
    int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice endpoint);
    int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
    int RegisterEndpointNotificationCallback(IntPtr client);
    int UnregisterEndpointNotificationCallback(IntPtr client);
  }
  [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
  class MMDeviceEnumeratorComObject { }
  public class DefaultEndpoint {
    public string Flow { get; set; }
    public string Role { get; set; }
    public string EndpointId { get; set; }
  }
  public static class CoreAudioProbe {
    public static DefaultEndpoint[] GetDefaults() {
      var e = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
      var list = new List<DefaultEndpoint>();
      foreach (EDataFlow flow in new [] { EDataFlow.Render, EDataFlow.Capture }) {
        foreach (ERole role in new [] { ERole.Console, ERole.Multimedia, ERole.Communications }) {
          IMMDevice device;
          int hr = e.GetDefaultAudioEndpoint(flow, role, out device);
          if (hr == 0 && device != null) {
            string id;
            if (device.GetId(out id) == 0) {
              list.Add(new DefaultEndpoint { Flow=flow.ToString().ToLowerInvariant(), Role=role.ToString().ToLowerInvariant(), EndpointId=id });
            }
            Marshal.ReleaseComObject(device);
          }
        }
      }
      Marshal.ReleaseComObject(e);
      return list.ToArray();
    }
  }
}
'@
    Add-Type -TypeDefinition $src -Language CSharp -ErrorAction Stop
}

function Get-WafDefaults {
    param([array]$Endpoints)
    Initialize-WafCoreAudio
    $byId = @{}
    foreach ($ep in @($Endpoints)) { $byId[[string]$ep.endpoint_id] = $ep }
    $result = @()
    foreach ($d in [CircuitDrift.WinAudio.CoreAudioProbe]::GetDefaults()) {
        $friendly = $null
        $rawId = [string]$d.EndpointId
        $brace = [regex]::Match($rawId, '\{[0-9a-fA-F-]{36}\}$')
        if ($brace.Success -and $byId.ContainsKey($brace.Value)) { $friendly = $byId[$brace.Value].friendly_name }
        $result += [pscustomobject]@{ flow=[string]$d.Flow; role=[string]$d.Role; endpoint_id=$rawId; friendly_name=$friendly }
    }
    return @($result | Sort-Object flow,role)
}

function Get-WafEvents {
    param([int]$Hours = 24)
    $start = (Get-Date).AddHours(-1 * $Hours)
    $events = @()
    try {
        $rows = Get-WinEvent -FilterHashtable @{ LogName='System'; StartTime=$start } -ErrorAction Stop |
            Where-Object { $_.ProviderName -match 'Audio|Kernel-PnP|UserPnp|Service Control Manager' } |
            Select-Object -First 500
        foreach ($e in $rows) {
            $msg = [string]$e.Message
            $msg = ($msg -replace '[\r\n]+',' ' -replace '\s+',' ').Trim()
            if ($msg.Length -gt 1200) { $msg = $msg.Substring(0,1200) }
            $events += [pscustomobject]@{
                time_created_utc = if ($null -ne $e.TimeCreated) { $e.TimeCreated.ToUniversalTime().ToString('o') } else { $null }
                log_name = [string]$e.LogName
                provider = [string]$e.ProviderName
                event_id = [int]$e.Id
                level = [string]$e.LevelDisplayName
                message = $msg
            }
        }
    } catch { throw "Event collector failed: $($_.Exception.Message)" }
    return @($events | Sort-Object time_created_utc,provider,event_id)
}

function Get-WafSnapshot {
    [CmdletBinding()]
    param(
        [switch]$IncludeEvents,
        [ValidateRange(1,720)][int]$EventHours = 24
    )
    if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) { throw 'WinAudioForensics snapshot collection requires Windows.' }
    if ($PSVersionTable.PSVersion.Major -lt 6 -and $env:OS -ne 'Windows_NT') { throw 'WinAudioForensics snapshot collection requires Windows.' }

    $warnings = New-Object System.Collections.Generic.List[string]
    $services = @(); $pnp = @(); $drivers = @(); $endpoints = @(); $defaults = @(); $events = @()
    try { $services = @(Get-WafServiceState) } catch { $warnings.Add($_.Exception.Message) }
    try { $pnp = @(Get-WafPnpDevices) } catch { $warnings.Add($_.Exception.Message) }
    try { $drivers = @(Get-WafDrivers) } catch { $warnings.Add($_.Exception.Message) }
    try { $endpoints = @(Get-WafEndpoints) } catch { $warnings.Add("Endpoint registry collector failed: $($_.Exception.Message)") }
    try { $defaults = @(Get-WafDefaults -Endpoints $endpoints) } catch { $warnings.Add("Core Audio default collector failed: $($_.Exception.Message)") }
    if ($IncludeEvents) {
        try { $events = @(Get-WafEvents -Hours $EventHours) } catch { $warnings.Add($_.Exception.Message) }
    }

    [pscustomobject]@{
        schema = $script:SnapshotSchema
        captured_at_utc = [DateTime]::UtcNow.ToString('o')
        host = [pscustomobject]@{
            computer_name = [Environment]::MachineName
            windows_version = [Environment]::OSVersion.VersionString
            powershell_version = $PSVersionTable.PSVersion.ToString()
        }
        services = $services
        pnp_devices = $pnp
        drivers = $drivers
        endpoints = $endpoints
        defaults = $defaults
        events = $events
        warnings = @($warnings)
    }
}

Export-ModuleMember -Function Get-WafSnapshot,Compare-WafSnapshot,Get-WafFindings,Get-WafStateFingerprint,Test-WafSnapshot
