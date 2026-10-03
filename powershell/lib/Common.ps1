$script:CDLVersion = '0.1.0-beta'
function Assert-CDLDependencies {
    foreach ($name in @('ffmpeg','ffprobe')) {
        if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { [Console]::Error.WriteLine("$name not found"); exit 2 }
    }
}
function Get-CDLProbeValue {
    param([string]$Path,[string]$Key,[ValidateSet('stream','format')]$Scope='stream')
    $args = @('-v','error')
    if ($Scope -eq 'stream') { $args += @('-select_streams','a:0','-show_entries',"stream=$Key") }
    else { $args += @('-show_entries',"format=$Key") }
    $args += @('-of','default=nw=1:nk=1',$Path)
    $v = & ffprobe @args 2>$null | Select-Object -First 1
    if ($null -eq $v) { return '' }
    return "$v".Trim()
}
function Get-CDLTag {
    param([string]$Path,[string]$Key)
    $v = & ffprobe -v error -show_entries "format_tags=$Key`:stream_tags=$Key" -of default=nw=1:nk=1 $Path 2>$null | Select-Object -First 1
    if ($null -eq $v) { return '' }; "$v".Trim()
}
function Get-CDLAudioFiles {
    param([string]$Path,[switch]$Recursive)
    $ext = @('.wav','.flac','.mp3','.m4a','.aac','.ogg','.opus','.aiff','.aif','.wma')
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return ,(Get-Item -LiteralPath $Path).FullName }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "unreadable input: $Path" }
    $items = Get-ChildItem -LiteralPath $Path -File -Recurse:$Recursive | Where-Object { $ext -contains $_.Extension.ToLowerInvariant() } | Sort-Object FullName
    return @($items.FullName)
}
function Get-CDLVersions {
    [ordered]@{ ffmpeg = ((& ffmpeg -version 2>$null | Select-Object -First 1) -as [string]); ffprobe = ((& ffprobe -version 2>$null | Select-Object -First 1) -as [string]) }
}
function Write-CDLReport {
    param($Report,[switch]$Json,[string]$Output,[string]$Text)
    $payload = if ($Json) { $Report | ConvertTo-Json -Depth 10 -Compress } else { $Text }
    if ($Output) { Set-Content -LiteralPath $Output -Value $payload -Encoding utf8 } else { $payload }
}
function New-CDLFinding { param([string]$Category,[string]$Message,[string]$Path=''); $h=[ordered]@{category=$Category;message=$Message}; if($Path){$h.path=$Path}; [pscustomobject]$h }
