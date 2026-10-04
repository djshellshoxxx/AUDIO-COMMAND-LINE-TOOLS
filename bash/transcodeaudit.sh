#!/usr/bin/env bash
set -euo pipefail
BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); source "$BASE/lib/common.sh"
help(){ cat <<'EOF'
transcodeaudit BETA - triage technical characteristics for provenance review
Usage: transcodeaudit.sh FILE|DIR [--recursive] [--min-bitrate BPS] [--json] [--output PATH]
EOF
}
json=0; recursive=0; minbit=0; output=""; input=""
while (($#)); do case "$1" in --help|-h) help; exit 0;; --json) json=1;; --recursive) recursive=1;; --min-bitrate) shift; (($#))||die 'missing --min-bitrate value'; [[ $1 =~ ^[0-9]+$ ]]||die 'invalid --min-bitrate'; minbit=$1;; --output) shift; (($#))||die 'missing --output value'; output=$1;; --*) die "unknown option: $1";; *) [[ -z "$input" ]]||die 'one input only'; input=$1;; esac; shift; done
[[ -n "$input" ]]||die 'input required'; require_tools
files=(); if [[ -d "$input" ]]; then while IFS= read -r -d '' f; do files+=("$f"); done < <(find_audio_files "$input" "$recursive"); else need_file "$input"; files+=("$input"); fi; ((${#files[@]}))||die 'no supported audio files found'
rows='['; findings='['; rc=0; first=1; ff=1
for f in "${files[@]}"; do codec=$(probe_value "$f" codec_name); container=$(probe_value "$f" format_name format); rate=$(probe_value "$f" sample_rate); channels=$(probe_value "$f" channels); bitrate=$(probe_value "$f" bit_rate); [[ -n "$bitrate" ]]||bitrate=$(probe_value "$f" bit_rate format); size=$(wc -c < "$f"|tr -d ' '); dur=$(probe_value "$f" duration format); enc=$(probe_tag "$f" encoder)
 row="{\"path\":$(json_string "$f"),\"codec\":$(json_string "$codec"),\"container\":$(json_string "$container"),\"sample_rate\":$(json_num "$rate"),\"channels\":$(json_num "$channels"),\"bit_rate\":$(json_num "$bitrate"),\"duration_seconds\":$(json_num "$dur"),\"file_size\":$(json_num "$size"),\"encoder\":$(json_string "$enc")}"; [[ $first -eq 1 ]]||rows+=','; rows+="$row"; first=0
 if ((minbit>0)) && [[ "$bitrate" =~ ^[0-9]+$ ]] && ((bitrate<minbit)); then item="{\"category\":\"low_reported_bitrate\",\"path\":$(json_string "$f"),\"message\":$(json_string "reported bitrate $bitrate is below configured floor $minbit")}"; [[ $ff -eq 1 ]]||findings+=','; findings+="$item"; ff=0; rc=1; fi
 case "$codec:$container" in flac:*mp4*|flac:*mov*) item="{\"category\":\"unusual_lossless_container\",\"path\":$(json_string "$f"),\"message\":\"lossless codec in an uncommon delivery container; inspect provenance if unexpected\"}"; [[ $ff -eq 1 ]]||findings+=','; findings+="$item"; ff=0; rc=1;; esac
done
rows+=']'; findings+=']'; status=$(status_from_count "$rc"); report="{\"tool\":\"transcodeaudit\",\"version\":\"$CDL_VERSION\",\"generated_utc\":$(json_string "$(now_utc)"),\"inputs\":[$(json_string "$input")],\"dependencies\":{\"ffmpeg\":$(json_string "$(ffmpeg_version)"),\"ffprobe\":$(json_string "$(ffprobe_version)")},\"options\":{\"recursive\":$([[ $recursive -eq 1 ]]&&echo true||echo false),\"min_bitrate\":$minbit},\"measurements\":{\"files\":$rows},\"findings\":$findings,\"status\":\"$status\",\"limitations\":\"These observations cannot prove lossy-to-lossless transcode history.\"}"
((json))&&write_or_stdout "$output" "$report"||write_or_stdout "$output" "transcodeaudit BETA: ${#files[@]} file(s), status=$status"; exit $rc
