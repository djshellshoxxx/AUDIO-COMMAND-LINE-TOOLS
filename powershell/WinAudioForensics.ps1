[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Command = 'help',
    [string]$Output,
    [string]$Before,
    [string]$After,
    [string]$Snapshot,
    [string]$Diff,
    [string]$OutputDirectory = '.\winaudioforensics-watch',
    [ValidateRange(1,720)][int]$EventHours = 24,
    [ValidateRange(2,86400)][int]$IntervalSeconds = 5,
    [ValidateRange(0,2147483647)][int]$Count = 0,
    [switch]$IncludeEvents,
    [switch]$Compact
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'WinAudioForensics.psm1'
Import-Module $modulePath -Force

function Write-WafJson {
    param($Value, [string]$Path, [switch]$CompactOutput)
    $json = if ($CompactOutput) { $Value | ConvertTo-Json -Depth 12 -Compress } else { $Value | ConvertTo-Json -Depth 12 }
    if ([string]::IsNullOrWhiteSpace($Path)) {
        [Console]::Out.WriteLine($json)
    } else {
        $parent = Split-Path -Parent $Path
        if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [IO.File]::WriteAllText((Resolve-WafPathForWrite $Path), $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    }
}

function Resolve-WafPathForWrite {
    param([string]$Path)
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

function Read-WafJson {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "File not found: $Path" }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Show-WafHelp {
@'
WinAudioForensics (beta) — Windows audio-state snapshot, diff, and diagnostics

Usage:
  .\WinAudioForensics.ps1 snapshot [-Output PATH] [-IncludeEvents] [-EventHours N] [-Compact]
  .\WinAudioForensics.ps1 diff -Before PATH -After PATH [-Output PATH] [-Compact]
  .\WinAudioForensics.ps1 doctor [-Snapshot PATH] [-Diff PATH] [-Output PATH] [-Compact]
  .\WinAudioForensics.ps1 watch [-OutputDirectory PATH] [-IntervalSeconds N] [-Count N] [-EventHours N]
  .\WinAudioForensics.ps1 help

Commands:
  snapshot  Capture Windows Audio services, PnP devices, signed drivers,
            MMDevices endpoints, Core Audio defaults, and optional recent events.
  diff      Compare two WinAudioForensics snapshot JSON files.
  doctor    Emit evidence-based findings from a snapshot and optional diff.
  watch     Poll audio state and write a snapshot + diff only when state changes.
  help      Show this text.

The beta is read-only with respect to Windows audio configuration. It writes only
report files you explicitly request.

Exit codes: 0 success; 1 doctor found an error-severity finding; 2 invalid input/runtime failure.
'@ | Write-Output
}

try {
    switch ($Command.ToLowerInvariant()) {
        'help' { Show-WafHelp; exit 0 }
        '--help' { Show-WafHelp; exit 0 }
        '-h' { Show-WafHelp; exit 0 }
        'snapshot' {
            $snap = Get-WafSnapshot -IncludeEvents:$IncludeEvents -EventHours $EventHours
            Write-WafJson -Value $snap -Path $Output -CompactOutput:$Compact
            exit 0
        }
        'diff' {
            if ([string]::IsNullOrWhiteSpace($Before) -or [string]::IsNullOrWhiteSpace($After)) { throw 'diff requires -Before PATH and -After PATH.' }
            $beforeObj = Read-WafJson $Before
            $afterObj = Read-WafJson $After
            $result = Compare-WafSnapshot -Before $beforeObj -After $afterObj
            Write-WafJson -Value $result -Path $Output -CompactOutput:$Compact
            exit 0
        }
        'doctor' {
            $snapObj = if ([string]::IsNullOrWhiteSpace($Snapshot)) { Get-WafSnapshot -IncludeEvents:$IncludeEvents -EventHours $EventHours } else { Read-WafJson $Snapshot }
            $diffObj = if ([string]::IsNullOrWhiteSpace($Diff)) { $null } else { Read-WafJson $Diff }
            $findings = @(Get-WafFindings -Snapshot $snapObj -Diff $diffObj)
            $report = [pscustomobject]@{
                schema = 'circuit-drift.winaudioforensics.doctor.v1'
                generated_at_utc = [DateTime]::UtcNow.ToString('o')
                findings = $findings
                summary = [pscustomobject]@{
                    error = @($findings | Where-Object severity -eq 'error').Count
                    warning = @($findings | Where-Object severity -eq 'warning').Count
                    info = @($findings | Where-Object severity -eq 'info').Count
                }
            }
            Write-WafJson -Value $report -Path $Output -CompactOutput:$Compact
            if ($report.summary.error -gt 0) { exit 1 }
            exit 0
        }
        'watch' {
            $dir = Resolve-WafPathForWrite $OutputDirectory
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $previous = Get-WafSnapshot -EventHours $EventHours
            $previousFingerprint = Get-WafStateFingerprint $previous
            $iterations = 0
            while ($Count -eq 0 -or $iterations -lt $Count) {
                Start-Sleep -Seconds $IntervalSeconds
                $iterations++
                $current = Get-WafSnapshot -EventHours $EventHours
                $fingerprint = Get-WafStateFingerprint $current
                if ($fingerprint -ne $previousFingerprint) {
                    $stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
                    $snapPath = Join-Path $dir "winaudio-$stamp.snapshot.json"
                    $diffPath = Join-Path $dir "winaudio-$stamp.diff.json"
                    $delta = Compare-WafSnapshot -Before $previous -After $current
                    Write-WafJson -Value $current -Path $snapPath -CompactOutput:$Compact
                    Write-WafJson -Value $delta -Path $diffPath -CompactOutput:$Compact
                    Write-Host ("Audio state changed: {0} change(s) -> {1}" -f @($delta.changes).Count, $diffPath)
                    $previous = $current
                    $previousFingerprint = $fingerprint
                }
            }
            exit 0
        }
        default { throw "Unknown command '$Command'. Run 'help' for usage." }
    }
} catch {
    [Console]::Error.WriteLine("WinAudioForensics: $($_.Exception.Message)")
    exit 2
}
