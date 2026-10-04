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
function Convert-CDLIntOrNull {
    param($Value)
    $text = "$Value".Trim(); if (-not $text -or $text -eq 'N/A') { return $null }
    $n = 0; if ([int]::TryParse($text,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$n)) { return $n }; return $null
}
function Convert-CDLLongOrNull {
    param($Value)
    $text = "$Value".Trim(); if (-not $text -or $text -eq 'N/A') { return $null }
    $n = [long]0; if ([long]::TryParse($text,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$n)) { return $n }; return $null
}
function Convert-CDLDoubleOrNull {
    param($Value)
    $text = "$Value".Trim(); if (-not $text -or $text -eq 'N/A') { return $null }
    $n = [double]0; if ([double]::TryParse($text,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$n) -and [double]::IsFinite($n)) { return $n }; return $null
}
function Resolve-CDLCanonicalPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $full) {
        $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        while ($item.PSObject.Properties['LinkType'] -and $item.LinkType) {
            if (-not $seen.Add($item.FullName)) { throw "symbolic-link cycle while resolving: $Path" }
            $target = @($item.Target)[0]
            if ([string]::IsNullOrWhiteSpace($target)) { break }
            if (-not [IO.Path]::IsPathRooted($target)) { $target = Join-Path $item.DirectoryName $target }
            $full = [IO.Path]::GetFullPath($target)
            $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
        }
        return $item.FullName
    }
    $parent = [IO.Path]::GetDirectoryName($full)
    if ([string]::IsNullOrWhiteSpace($parent) -or -not (Test-Path -LiteralPath $parent -PathType Container)) { throw "report parent directory does not exist: $parent" }
    $resolvedParent = (Resolve-Path -LiteralPath $parent -ErrorAction Stop).Path
    return [IO.Path]::Combine($resolvedParent,[IO.Path]::GetFileName($full))
}
function Assert-CDLReportTarget {
    param([string]$Output,[string[]]$Sources=@())
    if (-not $Output) { return }
    try {
        if (Test-Path -LiteralPath $Output -PathType Container) { throw "report output is a directory: $Output" }
        $dest = Resolve-CDLCanonicalPath $Output
        $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
        foreach ($source in $Sources) {
            if (-not $source) { continue }
            $src = Resolve-CDLCanonicalPath $source
            if ([string]::Equals($dest,$src,$comparison)) { throw "report output must not replace analyzed source: $Output" }
        }
    } catch {
        [Console]::Error.WriteLine($_.Exception.Message); exit 2
    }
}
function Write-CDLReport {
    param($Report,[switch]$Json,[string]$Output,[string]$Text)
    $payload = if ($Json) { $Report | ConvertTo-Json -Depth 10 -Compress } else { $Text }
    if (-not $Output) { $payload; return }
    $tmp = $null
    try {
        if (Test-Path -LiteralPath $Output -PathType Container) { throw "report output is a directory: $Output" }
        $full = [IO.Path]::GetFullPath($Output)
        $parent = [IO.Path]::GetDirectoryName($full)
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw "report parent directory does not exist: $parent" }
        $tmp = Join-Path $parent ('.cdl-report-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::WriteAllText($tmp,$payload,[Text.UTF8Encoding]::new($false))
        [IO.File]::Move($tmp,$full,$true)
        $tmp = $null
    } catch {
        if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        [Console]::Error.WriteLine($_.Exception.Message); exit 2
    }
}
function New-CDLFinding { param([string]$Category,[string]$Message,[string]$Path=''); $h=[ordered]@{category=$Category;message=$Message}; if($Path){$h.path=$Path}; [pscustomobject]$h }
