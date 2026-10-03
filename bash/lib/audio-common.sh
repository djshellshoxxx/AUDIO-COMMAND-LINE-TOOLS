#!/usr/bin/env bash
set -o pipefail
export LC_ALL=C
CDL_BASH_VERSION="0.1.0-beta"
FORMAT="text"
OUTPUT=""
NO_HEADER=0
QUIET=0
KEEP_TEMP=0
TMPDIR_TOOL=""

err(){ printf '%s\n' "$*" >&2; }
die(){ err "$*"; cleanup 2; }
need(){ command -v "$1" >/dev/null 2>&1 || die "missing required dependency: $1"; }
num(){ awk -v v="$1" 'BEGIN{exit !(v ~ /^[-+]?[0-9]+([.][0-9]+)?$/)}'; }
pos(){ num "$1" && awk -v v="$1" 'BEGIN{exit !(v>0)}'; }
nonneg(){ num "$1" && awk -v v="$1" 'BEGIN{exit !(v>=0)}'; }
range(){ num "$1" && awk -v v="$1" -v lo="$2" -v hi="$3" 'BEGIN{exit !(v>=lo && v<=hi)}'; }
require_file(){ [[ -r "$1" && -f "$1" ]] || die "unreadable input: $1"; }
probe(){ ffprobe -v error -select_streams a:0 -show_entries "stream=$2" -of default=nw=1:nk=1 -- "$1" | head -n1; }
probe_rate(){ probe "$1" sample_rate; }
probe_channels(){ probe "$1" channels; }
probe_duration(){ ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 -- "$1" | head -n1; }
setup(){
  need ffmpeg; need ffprobe; need awk; need od; need mktemp
  TMPDIR_TOOL=$(mktemp -d "${TMPDIR:-/tmp}/cdl-audio.XXXXXX") || { err "cannot create temp directory"; exit 2; }
  trap 'rc=$?; cleanup "$rc"' EXIT
  trap 'trap - EXIT; cleanup 130' INT
  trap 'trap - EXIT; cleanup 143' TERM
}
cleanup(){
  local rc=${1:-$?}
  if [[ -n "${TMPDIR_TOOL:-}" && -d "$TMPDIR_TOOL" ]]; then
    if (( KEEP_TEMP )); then err "temporary files kept at: $TMPDIR_TOOL"; else rm -rf -- "$TMPDIR_TOOL"; fi
  fi
  trap - EXIT INT TERM
  exit "$rc"
}
common_value(){ [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "missing value for $1"; }
common_parse(){ :; }
status_from_events(){ [[ -s "$1" ]] && printf 'review' || printf 'ok'; }
finish_rc(){ [[ "$1" == review ]] && return 1 || return 0; }
