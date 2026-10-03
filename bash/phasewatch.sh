#!/usr/bin/env bash
set -euo pipefail
BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); source "$BASE/lib/common.sh"; source "$BASE/lib/ffmpeg.sh"
help(){ cat <<'EOF'
phasewatch BETA - timestamp stereo phase/correlation behavior
Usage: phasewatch.sh INPUT [--warn-correlation X] [--critical-correlation X] [--min-duration-ms MS] [--json] [--output PATH]
EOF
}
json=0; warn=0.25; crit=0; mindur=100; output=""; input=""; window=100; minactive=-70
while (($#)); do case "$1" in --help|-h) help; exit 0;; --json) json=1;; --warn-correlation) shift; warn=${1-};; --critical-correlation) shift; crit=${1-};; --min-duration-ms) shift; mindur=${1-};; --window-ms) shift; window=${1-};; --min-active-db) shift; minactive=${1-};; --output) shift; output=${1-};; --*) die "unknown option: $1";; *) [[ -z "$input" ]]||die 'one input only'; input=$1;; esac; shift; done
[[ -n "$input" ]]||die 'input required'; require_tools; need_file "$input"; ch=$(probe_value "$input" channels); [[ "$ch" == 2 ]]||die 'phasewatch requires exactly two decoded channels'
raw=$(phase_metadata "$input" || true); windows='['; findings='['; first=1; ff=1; nf=0; current_t=0; prev=""
while IFS= read -r line; do if [[ $line =~ pts_time:([^[:space:]]+) ]]; then current_t=${BASH_REMATCH[1]}; elif [[ $line =~ lavfi\.aphasemeter\.phase=([-0-9.]+) ]]; then p=${BASH_REMATCH[1]}; item="{\"time_seconds\":$(json_num "$current_t"),\"correlation\":$(json_num "$p")}"; [[ $first -eq 1 ]]||windows+=','; windows+="$item"; first=0
 add(){ fi="{\"category\":$(json_string "$1"),\"time_seconds\":$(json_num "$current_t"),\"message\":$(json_string "$2")}"; [[ $ff -eq 1 ]]||findings+=','; findings+="$fi"; ff=0; nf=$((nf+1)); }
 awk -v p="$p" -v c="$crit" 'BEGIN{exit !(p<c)}' && add negative_correlation_segment "correlation $p is below critical threshold $crit"
 if [[ -n "$prev" ]]; then awk -v a="$prev" -v b="$p" 'BEGIN{d=b-a;if(d<0)d=-d;exit !(d>.65)}' && add correlation_regime_change "correlation changed sharply from $prev to $p"; fi; prev=$p; fi; done <<< "$raw"
windows+=']'; findings+=']'; status=$(status_from_count "$nf")
report="{\"tool\":\"phasewatch\",\"version\":\"$CDL_VERSION\",\"generated_utc\":$(json_string "$(now_utc)"),\"inputs\":[$(json_string "$input")],\"dependencies\":{\"ffmpeg\":$(json_string "$(ffmpeg_version)"),\"ffprobe\":$(json_string "$(ffprobe_version)")},\"options\":{\"warn_correlation\":$(json_num "$warn"),\"critical_correlation\":$(json_num "$crit"),\"min_duration_ms\":$(json_num "$mindur"),\"window_ms\":$(json_num "$window"),\"min_active_db\":$(json_num "$minactive")},\"measurements\":{\"windows\":$windows},\"findings\":$findings,\"status\":\"$status\"}"
((json))&&write_or_stdout "$output" "$report"||write_or_stdout "$output" "phasewatch BETA: status=$status findings=$nf"
((nf>0))&&exit 1||exit 0
