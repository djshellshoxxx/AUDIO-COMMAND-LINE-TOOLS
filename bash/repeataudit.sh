#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")"&&pwd)
source "$HERE/lib/audio-common.sh";source "$HERE/lib/output.sh";source "$HERE/lib/pcm.sh"
TOOL=repeataudit;BLOCK=100;MINADJ=300;MINNON=500;IGNORE=-70;ADJONLY=0;MAXBYTES=4294967296;HASHCMD=auto
usage(){ cat <<USAGE
repeataudit beta — exact decoded-audio block repeat detection
Usage: repeataudit.sh [options] FILE
  --block-ms N --min-adjacent-ms N --min-nonadjacent-ms N --ignore-below-db DB
  --adjacent-only --max-decoded-bytes N --hash-command auto|sha256sum|shasum
  --format text|tsv|jsonl --output PATH --no-header --quiet --keep-temp
USAGE
}
args=();endopts=0
while(($#));do if((endopts));then args+=("$1");shift;continue;fi;case "$1" in
 --)endopts=1;shift;;--help)usage;exit 0;;--version)echo "$TOOL $CDL_BASH_VERSION";exit 0;;
 --format)common_value "$@";FORMAT=$2;shift 2;;--output)common_value "$@";OUTPUT=$2;shift 2;;--no-header)NO_HEADER=1;shift;;--quiet)QUIET=1;shift;;--keep-temp)KEEP_TEMP=1;shift;;
 --block-ms)common_value "$@";BLOCK=$2;shift 2;;--min-adjacent-ms)common_value "$@";MINADJ=$2;shift 2;;--min-nonadjacent-ms)common_value "$@";MINNON=$2;shift 2;;--ignore-below-db)common_value "$@";IGNORE=$2;shift 2;;--adjacent-only)ADJONLY=1;shift;;--max-decoded-bytes)common_value "$@";MAXBYTES=$2;shift 2;;--hash-command)common_value "$@";HASHCMD=$2;shift 2;;
 -*)die "unknown option: $1";;*)args+=("$1");shift;;esac;done
[[ "$FORMAT" =~ ^(text|tsv|jsonl)$ ]]||die "invalid format";pos "$BLOCK"||die "invalid --block-ms";pos "$MINADJ"||die "invalid --min-adjacent-ms";pos "$MINNON"||die "invalid --min-nonadjacent-ms";num "$IGNORE"||die "invalid --ignore-below-db";pos "$MAXBYTES"||die "invalid --max-decoded-bytes";[[ "$HASHCMD" =~ ^(auto|sha256sum|shasum)$ ]]||die "invalid --hash-command";((${#args[@]}==1))||die "exactly one input is required"
setup;input=${args[0]};require_file "$input";rate=$(probe_rate "$input");ch=$(probe_channels "$input");pcm="$TMPDIR_TOOL/audio.pcm";decode_s16 "$input" "$pcm" 0||die "ffmpeg decode failed";size=$(wc -c <"$pcm");((size<=MAXBYTES))||die "decoded PCM exceeds --max-decoded-bytes";blockbytes=$((rate*ch*2*BLOCK/1000));((blockbytes>0))||die "block too small";chunks="$TMPDIR_TOOL/chunks";mkdir "$chunks";split -b "$blockbytes" -d -a 8 -- "$pcm" "$chunks/b" || die "cannot split PCM"
if [[ "$HASHCMD" == auto ]];then if command -v sha256sum>/dev/null;then HASHCMD=sha256sum;elif command -v shasum>/dev/null;then HASHCMD=shasum;else die "no SHA-256 command available";fi;fi
command -v "$HASHCMD">/dev/null||die "hash command unavailable: $HASHCMD";events="$TMPDIR_TOOL/events.tsv";:>"$events";table="$TMPDIR_TOOL/hashes.tsv";:>"$table";idx=0
for f in "$chunks"/b*;do [[ -f "$f" ]]||continue;rms=$(rms_db_pcm "$f");active=$(awk -v a="$rms" -v b="$IGNORE" 'BEGIN{print(a>=b)?1:0}');if [[ "$HASHCMD" == sha256sum ]];then h=$(sha256sum -- "$f"|awk '{print $1}');else h=$(shasum -a 256 -- "$f"|awk '{print $1}');fi;printf '%d\t%s\t%s\t%s\n' "$idx" "$h" "$active" "$f">>"$table";idx=$((idx+1));done
awk -F'\t' -v block="$BLOCK" -v minadj="$MINADJ" -v ev="$events" '
function flush(){if(run*block>=minadj && active){st=(start*block)/1000;en=((start+run)*block)/1000;printf "adjacent_exact_repeat\t%.6f\t%.6f\treview\tblocks=%d\n",st,en,run >> ev}}
NR==1{prev=$2;start=$1;run=1;active=$3;next}{if($2==prev&&$3==1&&active==1){run++}else{flush();prev=$2;start=$1;run=1;active=$3}}END{flush()}' "$table"
if((!ADJONLY));then sort -t$'\t' -k2,2 -k1,1n "$table"|awk -F'\t' -v block="$BLOCK" -v minn="$MINNON" -v ev="$events" '
$3==1{key=$2;if(key==prev){gap=$1-last;if(gap>1){dur=block;if(dur>=minn)printf "nonadjacent_exact_repeat\t%.6f\t%.6f\treview\thash=%s\n",last*block/1000,($1+1)*block/1000,key >> ev}}prev=key;last=$1}' ;fi
review=0;grep -q $'\treview\t' "$events"&&review=1||true;status=$([[ $review == 1 ]]&&echo review||echo ok);report_render "$TOOL" "$input" "$events" "$status" "$OUTPUT" "$FORMAT" "$NO_HEADER" "$QUIET"||die "failed to write report";((review))&&exit 1||exit 0
