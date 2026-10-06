function Get-CDLPhaseSamples {
    param([string]$Path)
    $lines = & ffmpeg -hide_banner -loglevel error -i $Path -af 'aphasemeter=video=0,ametadata=print:key=lavfi.aphasemeter.phase:file=-' -f null - 2>&1
    $time = 0.0; $out = @()
    foreach($line in $lines){
        $s="$line"
        if($s -match 'pts_time:([^\s]+)'){ $time=[double]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture) }
        elseif($s -match 'lavfi\.aphasemeter\.phase=([-0-9.]+)'){ $p=[double]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture); $out += [pscustomobject]@{time_seconds=$time;correlation=$p} }
    }
    return $out
}
function Get-CDLIntegratedLufs {
    param([string]$Path)
    $lines=& ffmpeg -hide_banner -nostats -i $Path -filter_complex 'ebur128=peak=true' -f null - 2>&1
    $seen=$false
    foreach($line in $lines){$s="$line"; if($s -match 'Integrated loudness:'){ $seen=$true; continue }; if($seen -and $s -match '^\s*I:\s*([-0-9.]+)'){ return [double]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture) }}
    return $null
}
