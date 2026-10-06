#!/usr/bin/env bash
set -euo pipefail
BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); source "$BASE/lib/common.sh"; source "$BASE/lib/ffmpeg.sh"
help(){ cat <<'EOF'
albumcontract BETA - find technical outliers in an audio delivery folder
Usage: albumcontract.sh DIR [--recursive] [--expected-rate HZ] [--expected-channels N] [--loudness] [--json] [--output PATH]
EOF
}
json=0; rec=0; loud=0; er=""; ec=""; output=""; input=""
while (($#)); do case "$1" in --help|-h) help; exit 0;; --json) json=1;; --recursive) rec=1;; --loudness) loud=1;; --expected-rate) shift; (($#))||die 'missing --expected-rate value'; er=$1; [[ $er =~ ^[1-9][0-9]*$ ]]||die 'invalid --expected-rate';; --expected-channels) shift; (($#))||die 'missing --expected-channels value'; ec=$1; [[ $ec =~ ^[1-9][0-9]*$ ]]||die 'invalid --expected-channels';; --output) shift; (($#))||die 'missing --output value'; output=$1;; --*) die "unknown option: $1";; *) [[ -z "$input" ]]||die 'one directory only'; input=$1;; esac; shift; done
[[ -n "$input" ]]||die 'directory required'; require_tools; need_dir "$input"; files=(); while IFS= read -r -d '' f; do files+=("$f"); done < <(find_audio_files "$input" "$rec"); ((${#files[@]}))||die 'no supported audio files'; validate_report_target "$output" "${files[@]}"
rates=(); chans=(); fmts=(); for f in "${files[@]}"; do rates+=("$(probe_value "$f" sample_rate)"); chans+=("$(probe_value "$f" channels)"); fmts+=("$(probe_value "$f" sample_fmt)"); done
mode(){ printf '%s\n' "$@"|sort|uniq -c|sort -k1,1nr -k2,2|awk 'NR==1{$1="";sub(/^ /,"");print;exit}'; }
dr=${er:-$(mode "${rates[@]}")}; dc=${ec:-$(mode "${chans[@]}")}; df=$(mode "${fmts[@]}")
rows='['; finds='['; first=1; ff=1; nfind=0
for i in "${!files[@]}"; do f=${files[$i]}; rate=${rates[$i]}; ch=${chans[$i]}; fmt=${fmts[$i]}; cont=$(probe_value "$f" format_name format); codec=$(probe_value "$f" codec_name); lufs=""; ((loud))&&lufs=$(measure_integrated_lufs "$f" || true)
 row="{\"path\":$(json_string "$f"),\"sample_rate\":$(json_num "$rate"),\"channels\":$(json_num "$ch"),\"sample_format\":$(json_string "$fmt"),\"codec\":$(json_string "$codec"),\"container\":$(json_string "$cont"),\"integrated_lufs\":$(json_num "$lufs")}"; [[ $first -eq 1 ]]||rows+=','; rows+="$row"; first=0
 add(){ local cat=$1 msg=$2; item="{\"category\":$(json_string "$cat"),\"path\":$(json_string "$f"),\"message\":$(json_string "$msg")}"; [[ $ff -eq 1 ]]||finds+=','; finds+="$item"; ff=0; nfind=$((nfind+1)); }
 [[ "$rate" == "$dr" ]]||add sample_rate_outlier "sample rate $rate differs from contract $dr"; [[ "$ch" == "$dc" ]]||add channel_count_outlier "channel count $ch differs from contract $dc"; [[ "$fmt" == "$df" ]]||add sample_format_outlier "sample format $fmt differs from dominant $df"
done
rows+=']'; finds+=']'; status=$(status_from_count "$nfind"); report="{\"tool\":\"albumcontract\",\"version\":\"$CDL_VERSION\",\"generated_utc\":$(json_string "$(now_utc)"),\"inputs\":[$(json_string "$input")],\"dependencies\":{\"ffmpeg\":$(json_string "$(ffmpeg_version)"),\"ffprobe\":$(json_string "$(ffprobe_version)")},\"options\":{\"recursive\":$([[ $rec -eq 1 ]]&&echo true||echo false),\"loudness\":$([[ $loud -eq 1 ]]&&echo true||echo false),\"expected_rate\":$(json_num "$er"),\"expected_channels\":$(json_num "$ec")},\"measurements\":{\"dominant_sample_rate\":$(json_num "$dr"),\"dominant_channels\":$(json_num "$dc"),\"dominant_sample_format\":$(json_string "$df"),\"files\":$rows},\"findings\":$finds,\"status\":\"$status\"}"
((json))&&write_or_stdout "$output" "$report"||write_or_stdout "$output" "albumcontract BETA: ${#files[@]} files, contract=${dr}Hz/${dc}ch/$df status=$status"; ((nfind>0))&&exit 1||exit 0
