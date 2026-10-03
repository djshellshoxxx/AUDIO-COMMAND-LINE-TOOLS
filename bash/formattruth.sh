#!/usr/bin/env bash
set -euo pipefail
BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$BASE/lib/common.sh"
help(){ cat <<'EOF'
formattruth BETA - inspect container/codec/stream consistency
Usage: formattruth.sh INPUT [--strict-extension] [--tags a,b] [--json] [--output PATH]
EOF
}
json=0; output=""; strict=0; tags="artist,title,album,track,disc"; input=""
while (($#)); do case "$1" in --help|-h) help; exit 0;; --json) json=1;; --strict-extension) strict=1;; --tags) shift; (($#))||die 'missing --tags value'; tags=$1;; --output) shift; (($#))||die 'missing --output value'; output=$1;; --*) die "unknown option: $1";; *) [[ -z "$input" ]]||die 'only one input is supported'; input=$1;; esac; shift; done
[[ -n "$input" ]]||die 'input required'; require_tools; need_file "$input"
codec=$(probe_value "$input" codec_name); long=$(probe_value "$input" codec_long_name); rate=$(probe_value "$input" sample_rate); channels=$(probe_value "$input" channels); layout=$(probe_value "$input" channel_layout); sample_fmt=$(probe_value "$input" sample_fmt); bits=$(probe_value "$input" bits_per_raw_sample); [[ -n "$bits" ]]||bits=$(probe_value "$input" bits_per_sample); bitrate=$(probe_value "$input" bit_rate); duration=$(probe_value "$input" duration format); format=$(probe_value "$input" format_name format)
streams=$(ffprobe -v error -show_entries stream=codec_type -of csv=p=0 -- "$input" 2>/dev/null || true); stream_count=$(printf '%s\n' "$streams"|sed '/^$/d'|wc -l|tr -d ' '); nona=$(printf '%s\n' "$streams"|grep -vc '^audio$' || true)
ext=${input##*.}; ext=$(printf '%s' "$ext"|tr '[:upper:]' '[:lower:]'); mismatch=0
case "$ext" in wav) [[ "$format" == *wav* ]]||mismatch=1;; flac) [[ "$format" == *flac* ]]||mismatch=1;; mp3) [[ "$format" == *mp3* ]]||mismatch=1;; ogg|opus) [[ "$format" == *ogg* ]]||mismatch=1;; m4a|aac) [[ "$format" == *mp4* || "$format" == *mov* || "$format" == *aac* ]]||mismatch=1;; esac
findings='[]'; count=0
add(){ local c=$1 m=$2; local item="{\"category\":$(json_string "$c"),\"message\":$(json_string "$m")}"; if [[ $count -eq 0 ]]; then findings="[$item]"; else findings="${findings%]} ,$item]"; fi; count=$((count+1)); }
((mismatch))&&add extension_container_mismatch "extension .$ext does not match detected container $format"
((nona>0))&&add non_audio_stream "file contains $nona non-audio stream(s)"
[[ -n "$layout" ]]||add ambiguous_channel_layout 'channel layout is absent or ambiguous'
status=$(status_from_count "$count")
report="{\"tool\":\"formattruth\",\"version\":\"$CDL_VERSION\",\"generated_utc\":$(json_string "$(now_utc)"),\"inputs\":[$(json_string "$input")],\"dependencies\":{\"ffmpeg\":$(json_string "$(ffmpeg_version)"),\"ffprobe\":$(json_string "$(ffprobe_version)")},\"options\":{\"strict_extension\":$([[ $strict -eq 1 ]]&&echo true||echo false),\"tags\":$(json_string "$tags")},\"measurements\":{\"extension\":$(json_string "$ext"),\"container\":$(json_string "$format"),\"codec\":$(json_string "$codec"),\"codec_long_name\":$(json_string "$long"),\"sample_format\":$(json_string "$sample_fmt"),\"bits_per_sample\":$(json_num "$bits"),\"sample_rate\":$(json_num "$rate"),\"channels\":$(json_num "$channels"),\"channel_layout\":$(json_string "$layout"),\"bit_rate\":$(json_num "$bitrate"),\"duration_seconds\":$(json_num "$duration"),\"stream_count\":$stream_count,\"non_audio_stream_count\":$nona},\"findings\":$findings,\"status\":\"$status\"}"
if ((json)); then write_or_stdout "$output" "$report"; else text="formattruth BETA\n$input\ncontainer=$format codec=$codec rate=$rate channels=$channels sample_fmt=$sample_fmt\nstatus=$status findings=$count"; write_or_stdout "$output" "$(printf '%b' "$text")"; fi
[[ "$status" == review ]] && exit 1 || exit 0
