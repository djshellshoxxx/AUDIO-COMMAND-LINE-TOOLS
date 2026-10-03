#!/usr/bin/env bash
set -o pipefail
CDL_VERSION="0.1.0-beta"

err(){ printf '%s\n' "$*" >&2; }
die(){ err "$*"; exit 2; }
require_tools(){ command -v ffmpeg >/dev/null 2>&1 || die 'ffmpeg not found'; command -v ffprobe >/dev/null 2>&1 || die 'ffprobe not found'; }
need_file(){ [[ -f "$1" && -r "$1" ]] || die "unreadable input: $1"; }
need_dir(){ [[ -d "$1" && -r "$1" ]] || die "unreadable directory: $1"; }
now_utc(){ date -u +'%Y-%m-%dT%H:%M:%SZ'; }
first_line(){ local s=${1-}; printf '%s\n' "${s%%$'\n'*}"; }
ffmpeg_version(){ local out; out=$(ffmpeg -version 2>/dev/null || true); first_line "$out"; }
ffprobe_version(){ local out; out=$(ffprobe -version 2>/dev/null || true); first_line "$out"; }
json_escape(){ local s=${1-}; s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}; s=${s//$'\t'/\\t}; printf '%s' "$s"; }
json_string(){ printf '"%s"' "$(json_escape "${1-}")"; }
json_num(){ local v=${1-}; if [[ "$v" =~ ^-?([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]]; then [[ "$v" == .* ]] && v="0$v"; [[ "$v" == -.* ]] && v="-0${v#-}"; printf '%s' "$v"; else printf 'null'; fi; }
write_or_stdout(){ local output=${1-}; local data=$2; if [[ -n "$output" ]]; then printf '%s\n' "$data" > "$output" || die "cannot write report: $output"; else printf '%s\n' "$data"; fi; }
find_audio_files(){ local root=$1 recursive=${2:-0}; need_dir "$root"; if [[ "$recursive" == 1 ]]; then find "$root" -type f \( -iname '*.wav' -o -iname '*.flac' -o -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.ogg' -o -iname '*.opus' -o -iname '*.aiff' -o -iname '*.aif' -o -iname '*.wma' \) -print0 | sort -z; else find "$root" -maxdepth 1 -type f \( -iname '*.wav' -o -iname '*.flac' -o -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.ogg' -o -iname '*.opus' -o -iname '*.aiff' -o -iname '*.aif' -o -iname '*.wma' \) -print0 | sort -z; fi; }
probe_value(){ local f=$1 key=$2 scope=${3:-stream} out; if [[ "$scope" == format ]]; then out=$(ffprobe -v error -show_entries "format=$key" -of default=nw=1:nk=1 -- "$f" 2>/dev/null || true); else out=$(ffprobe -v error -select_streams a:0 -show_entries "stream=$key" -of default=nw=1:nk=1 -- "$f" 2>/dev/null || true); fi; first_line "$out"; }
probe_tag(){ local f=$1 key=$2 out; out=$(ffprobe -v error -show_entries "format_tags=$key:stream_tags=$key" -of default=nw=1:nk=1 -- "$f" 2>/dev/null || true); first_line "$out"; }
status_from_count(){ [[ ${1:-0} -gt 0 ]] && printf review || printf ok; }
