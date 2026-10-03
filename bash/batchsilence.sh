#!/usr/bin/env bash
set -euo pipefail
BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); source "$BASE/lib/common.sh"
help(){ cat <<'EOF'
batchsilence BETA - compare leading/trailing silence across a batch
Usage: batchsilence.sh DIR [--threshold-db DB] [--min-silence SEC] [--max-leading SEC] [--max-trailing SEC] [--recursive] [--json] [--output PATH]
EOF
}
json=0; rec=0; th=-60; mins=0.10; maxlead=""; maxtrail=""; output=""; input=""
while (($#)); do case "$1" in --help|-h) help; exit 0;; --json) json=1;; --recursive) rec=1;; --threshold-db) shift; th=${1-};; --min-silence) shift; mins=${1-};; --max-leading) shift; maxlead=${1-};; --max-trailing) shift; maxtrail=${1-};; --output) shift; output=${1-};; --*) die "unknown option: $1";; *) [[ -z "$input" ]]||die 'one directory only'; input=$1;; esac; shift; done
[[ -n "$input" ]]||die 'directory required'; require_tools; files=(); while IFS= read -r -d '' f; do files+=("$f"); done < <(find_audio_files "$input" "$rec"); ((${#files[@]}))||die 'no supported audio files'
rows='['; finds='['; first=1; ff=1; nf=0
for f in "${files[@]}"; do dur=$(probe_value "$f" duration format); log=$(LC_ALL=C ffmpeg -hide_banner -nostats -i "$f" -af "silencedetect=noise=${th}dB:d=$mins" -f null - 2>&1 || true)
 lead=$(printf '%s\n' "$log"|awk '/silence_start:/{if($NF+0<=0.0001){lead=1;next}} lead&&/silence_end:/{for(i=1;i<=NF;i++)if($i=="silence_end:"){print $(i+1);exit}}'); [[ -n "$lead" ]]||lead=0
 last_start=$(printf '%s\n' "$log"|awk '/silence_start:/{v=$NF}END{print v}'); last_end=$(printf '%s\n' "$log"|awk '/silence_end:/{for(i=1;i<=NF;i++)if($i=="silence_end:")v=$(i+1)}END{print v}')
 trail=0; if [[ -n "$last_start" && "$dur" =~ ^[0-9] ]]; then trail=$(awk -v d="$dur" -v s="$last_start" 'BEGIN{v=d-s;if(v<0)v=0;printf "%.6f",v}'); if [[ -n "$last_end" ]]; then near=$(awk -v d="$dur" -v e="$last_end" 'BEGIN{print (d-e<0.02)?1:0}'); [[ $near -eq 1 ]]||trail=0; fi; fi
 ratioL=$(awk -v a="$lead" -v d="$dur" 'BEGIN{if(d>0)printf "%.6f",a/d;else print 0}'); ratioT=$(awk -v a="$trail" -v d="$dur" 'BEGIN{if(d>0)printf "%.6f",a/d;else print 0}')
 row="{\"path\":$(json_string "$f"),\"duration_seconds\":$(json_num "$dur"),\"leading_silence_seconds\":$(json_num "$lead"),\"trailing_silence_seconds\":$(json_num "$trail"),\"leading_ratio\":$(json_num "$ratioL"),\"trailing_ratio\":$(json_num "$ratioT")}"; [[ $first -eq 1 ]]||rows+=','; rows+="$row"; first=0
 add(){ item="{\"category\":$(json_string "$1"),\"path\":$(json_string "$f"),\"message\":$(json_string "$2")}"; [[ $ff -eq 1 ]]||finds+=','; finds+="$item"; ff=0; nf=$((nf+1)); }
 if [[ -n "$maxlead" ]] && awk -v a="$lead" -v b="$maxlead" 'BEGIN{exit !(a>b)}'; then add excessive_leading_silence "leading silence $lead exceeds $maxlead"; fi
 if [[ -n "$maxtrail" ]] && awk -v a="$trail" -v b="$maxtrail" 'BEGIN{exit !(a>b)}'; then add excessive_trailing_silence "trailing silence $trail exceeds $maxtrail"; fi
done
rows+=']'; finds+=']'; status=$(status_from_count "$nf")
report="{\"tool\":\"batchsilence\",\"version\":\"$CDL_VERSION\",\"generated_utc\":$(json_string "$(now_utc)"),\"inputs\":[$(json_string "$input")],\"dependencies\":{\"ffmpeg\":$(json_string "$(ffmpeg_version)"),\"ffprobe\":$(json_string "$(ffprobe_version)")},\"options\":{\"threshold_db\":$(json_num "$th"),\"min_silence\":$(json_num "$mins")},\"measurements\":{\"files\":$rows},\"findings\":$finds,\"status\":\"$status\"}"
((json))&&write_or_stdout "$output" "$report"||write_or_stdout "$output" "batchsilence BETA: ${#files[@]} files status=$status"
((nf>0))&&exit 1||exit 0
