#!/usr/bin/env bash
set -euo pipefail
BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); source "$BASE/lib/common.sh"
help(){ cat <<'EOF'
loudwalk BETA - turn FFmpeg EBU R128 measurements into a loudness timeline
Usage: loudwalk.sh INPUT [--jump-db DB] [--deviation-db DB] [--top N] [--json] [--output PATH]
EOF
}
json=0; jump=5; dev=6; top=10; output=""; input=""
while (($#)); do case "$1" in --help|-h) help; exit 0;; --json) json=1;; --jump-db) shift; jump=${1-};; --deviation-db) shift; dev=${1-};; --top) shift; top=${1-};; --output) shift; output=${1-};; --interval) shift; : "${1-}";; --*) die "unknown option: $1";; *) [[ -z "$input" ]]||die 'one input only'; input=$1;; esac; shift; done
[[ -n "$input" ]]||die 'input required'; require_tools; need_file "$input"; [[ $top =~ ^[0-9]+$ ]]||die 'invalid --top'
log=$(LC_ALL=C ffmpeg -hide_banner -nostats -i "$input" -filter_complex ebur128=peak=true -f null - 2>&1 || true)
mapfile -t pts < <(printf '%s\n' "$log"|awk '/Parsed_ebur128/ && / t: /{for(i=1;i<=NF;i++)if($i=="t:")t=$(i+1);for(i=1;i<=NF;i++)if($i=="S:"){s=$(i+1);gsub(/[^0-9+.-]/,"",s);if(s!=""&&s+0>-100)print t" "s}}')
vals=(); for x in "${pts[@]}"; do vals+=("${x#* }"); done
median=null; if ((${#vals[@]})); then median=$(printf '%s\n' "${vals[@]}"|sort -n|awk '{a[NR]=$1}END{if(NR%2)print a[(NR+1)/2];else printf "%.3f",(a[NR/2]+a[NR/2+1])/2}'); fi
integrated=$(printf '%s\n' "$log"|awk '/Integrated loudness:/{f=1;next} f&&/^[[:space:]]*I:/{print $2;exit}'); lra=$(printf '%s\n' "$log"|awk '/Loudness range:/{f=1;next} f&&/^[[:space:]]*LRA:/{print $2;exit}')
timeline='['; findings='['; first=1; ff=1; nf=0; prev=""
for row in "${pts[@]}"; do t=${row%% *}; s=${row#* }; item="{\"time_seconds\":$(json_num "$t"),\"short_term_lufs\":$(json_num "$s")}"; [[ $first -eq 1 ]]||timeline+=','; timeline+="$item"; first=0
 add(){ fi="{\"category\":$(json_string "$1"),\"time_seconds\":$(json_num "$t"),\"message\":$(json_string "$2")}"; [[ $ff -eq 1 ]]||findings+=','; findings+="$fi"; ff=0; nf=$((nf+1)); }
 if [[ -n "$prev" ]]; then awk -v a="$prev" -v b="$s" -v j="$jump" 'BEGIN{d=b-a;if(d<0)d=-d;exit !(d>=j)}' && add abrupt_loudness_transition "adjacent short-term loudness changed from $prev to $s LUFS"; fi
 if [[ "$median" != null ]]; then awk -v a="$median" -v b="$s" -v d="$dev" 'BEGIN{x=b-a;if(x<0)x=-x;exit !(x>=d)}' && add relative_loudness_outlier "short-term loudness $s differs from median $median LUFS"; fi
 prev=$s
done
timeline+=']'; findings+=']'; status=$(status_from_count "$nf")
report="{\"tool\":\"loudwalk\",\"version\":\"$CDL_VERSION\",\"generated_utc\":$(json_string "$(now_utc)"),\"inputs\":[$(json_string "$input")],\"dependencies\":{\"ffmpeg\":$(json_string "$(ffmpeg_version)"),\"ffprobe\":$(json_string "$(ffprobe_version)")},\"options\":{\"jump_db\":$(json_num "$jump"),\"deviation_db\":$(json_num "$dev"),\"top\":$top},\"measurements\":{\"integrated_lufs\":$(json_num "$integrated"),\"loudness_range_lu\":$(json_num "$lra"),\"median_short_term_lufs\":$(json_num "$median"),\"timeline\":$timeline},\"findings\":$findings,\"status\":\"$status\"}"
((json))&&write_or_stdout "$output" "$report"||write_or_stdout "$output" "loudwalk BETA: integrated=$integrated LUFS median=$median status=$status"
((nf>0))&&exit 1||exit 0
