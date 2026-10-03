#!/usr/bin/env bash
json_escape(){
  local s=${1-}
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\t'/\\t}; s=${s//$'\r'/\\r}; s=${s//$'\n'/\\n}
  printf '%s' "$s"
}
tsv_escape(){ local s=${1-}; s=${s//$'\t'/\\t}; s=${s//$'\r'/\\r}; s=${s//$'\n'/\\n}; printf '%s' "$s"; }
report_render(){
  local tool=$1 path=$2 events=$3 status=$4 out=$5 fmt=$6 nohead=$7 quiet=$8
  local target tmpout=""
  if [[ -n "$out" ]]; then
    local dir base; dir=$(dirname -- "$out"); base=$(basename -- "$out")
    [[ -d "$dir" && -w "$dir" ]] || { err "report destination is not writable: $out"; return 2; }
    tmpout=$(mktemp "$dir/.${base}.tmp.XXXXXX") || return 2
    target=$tmpout
  else target=/dev/stdout; fi
  if [[ "$fmt" == tsv ]]; then
    if (( ! nohead )); then printf 'path\ttool\tevent\tstart_seconds\tend_seconds\tseverity\tdetails\n' >"$target"; else : >"$target"; fi
    while IFS=$'\t' read -r ev st en sev det; do
      [[ -n "$ev" ]] || continue
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(tsv_escape "$path")" "$tool" "$ev" "$st" "$en" "$sev" "$(tsv_escape "$det")" >>"$target"
    done <"$events"
    printf '%s\t%s\tsummary\t0\t0\t%s\tstatus=%s\n' "$(tsv_escape "$path")" "$tool" "$status" "$status" >>"$target"
  elif [[ "$fmt" == jsonl ]]; then
    : >"$target"
    while IFS=$'\t' read -r ev st en sev det; do
      [[ -n "$ev" ]] || continue
      printf '{"tool":"%s","version":"%s","path":"%s","event":"%s","start_seconds":%s,"end_seconds":%s,"severity":"%s","details":"%s"}\n' \
        "$(json_escape "$tool")" "$CDL_BASH_VERSION" "$(json_escape "$path")" "$(json_escape "$ev")" "${st:-0}" "${en:-0}" "$(json_escape "$sev")" "$(json_escape "$det")" >>"$target"
    done <"$events"
    printf '{"tool":"%s","version":"%s","path":"%s","event":"summary","start_seconds":0,"end_seconds":0,"severity":"%s","details":"status=%s","status":"%s"}\n' \
      "$(json_escape "$tool")" "$CDL_BASH_VERSION" "$(json_escape "$path")" "$status" "$status" "$status" >>"$target"
  else
    : >"$target"
    if (( ! quiet )); then printf '%s beta — %s\n' "$tool" "$path" >>"$target"; fi
    while IFS=$'\t' read -r ev st en sev det; do
      [[ -n "$ev" ]] || continue
      printf '%-28s %10ss..%-10ss %-7s %s\n' "$ev" "$st" "$en" "$sev" "$det" >>"$target"
    done <"$events"
    printf 'status: %s\n' "$status" >>"$target"
  fi
  if [[ -n "$out" ]]; then mv -f -- "$tmpout" "$out" || { rm -f -- "$tmpout"; return 2; }; fi
}
