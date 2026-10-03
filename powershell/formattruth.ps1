[CmdletBinding()]
param(
 [Parameter(Position=0)][string]$InputPath,
 [switch]$Json,
 [switch]$StrictExtension,
 [string]$Tags='artist,title,album,track,disc',
 [string]$Output,
 [switch]$Help
)
. "$PSScriptRoot/lib/Common.ps1"
if($Help -or -not $InputPath){ if($Help){'formattruth BETA - inspect container/codec/stream consistency'; 'Usage: .\formattruth.ps1 INPUT [-StrictExtension] [-Tags list] [-Json] [-Output path]'; exit 0}; [Console]::Error.WriteLine('input required'); exit 2 }
Assert-CDLDependencies
if(-not (Test-Path -LiteralPath $InputPath -PathType Leaf)){[Console]::Error.WriteLine("unreadable input: $InputPath");exit 2}
$p=(Resolve-Path -LiteralPath $InputPath).Path
$codec=Get-CDLProbeValue $p codec_name; $long=Get-CDLProbeValue $p codec_long_name; $rate=Get-CDLProbeValue $p sample_rate; $channels=Get-CDLProbeValue $p channels; $layout=Get-CDLProbeValue $p channel_layout; $sf=Get-CDLProbeValue $p sample_fmt; $bits=Get-CDLProbeValue $p bits_per_raw_sample; if(-not $bits){$bits=Get-CDLProbeValue $p bits_per_sample}; $br=Get-CDLProbeValue $p bit_rate; $dur=Get-CDLProbeValue $p duration format; $fmt=Get-CDLProbeValue $p format_name format
$types=@(& ffprobe -v error -show_entries stream=codec_type -of csv=p=0 $p 2>$null); $nonAudio=@($types|Where-Object{$_ -ne 'audio'}).Count
$ext=[IO.Path]::GetExtension($p).TrimStart('.').ToLowerInvariant(); $mismatch=$false
switch($ext){'wav'{$mismatch=$fmt -notmatch 'wav'};'flac'{$mismatch=$fmt -notmatch 'flac'};'mp3'{$mismatch=$fmt -notmatch 'mp3'};'ogg'{$mismatch=$fmt -notmatch 'ogg'};'opus'{$mismatch=$fmt -notmatch 'ogg'};'m4a'{$mismatch=$fmt -notmatch 'mov|mp4'};'aac'{$mismatch=$fmt -notmatch 'aac|mov|mp4'}}
$find=@(); if($mismatch){$find+=New-CDLFinding 'extension_container_mismatch' "extension .$ext does not match detected container $fmt"}; if($nonAudio){$find+=New-CDLFinding 'non_audio_stream' "file contains $nonAudio non-audio stream(s)"}; if(-not $layout){$find+=New-CDLFinding 'ambiguous_channel_layout' 'channel layout is absent or ambiguous'}
$status=if($find.Count){'review'}else{'ok'}
$report=[ordered]@{tool='formattruth';version=$script:CDLVersion;generated_utc=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ');inputs=@($p);dependencies=Get-CDLVersions;options=[ordered]@{strict_extension=[bool]$StrictExtension;tags=$Tags};measurements=[ordered]@{extension=$ext;container=$fmt;codec=$codec;codec_long_name=$long;sample_format=$sf;bits_per_sample=if($bits){[int]$bits}else{$null};sample_rate=if($rate){[int]$rate}else{$null};channels=if($channels){[int]$channels}else{$null};channel_layout=$layout;bit_rate=if($br){[long]$br}else{$null};duration_seconds=if($dur){[double]$dur}else{$null};stream_count=$types.Count;non_audio_stream_count=$nonAudio};findings=$find;status=$status}
Write-CDLReport $report -Json:$Json -Output $Output -Text "formattruth BETA`n$p`ncontainer=$fmt codec=$codec rate=$rate channels=$channels`nstatus=$status findings=$($find.Count)"
if($find.Count){exit 1};exit 0
