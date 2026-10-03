#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")"&&pwd)
source "$HERE/lib/audio-common.sh";source "$HERE/lib/output.sh";source "$HERE/lib/pcm.sh"
TOOL=samplefreeze;MINRUN=20;TOL="";MINLEVEL=-80;CHANNEL=all;INCLUDE_ZERO=0
usage(){ cat <<USAGE
samplefreeze beta — frozen PCM run detection
Usage: samplefreeze.sh [options] FILE
  --min-run-ms N --near-tolerance X --min-level-db DB --channel N|all --include-zero
  --format text|tsv|jsonl --output PATH --no-header --quiet --keep-temp
USAGE
}
args=();endopts=0
while(($#));do if((endopts));then args+=("$1");shift;continue;fi;case "$1" in
 --)endopts=1;shift;;--help)usage;exit 0;;--version)echo "$TOOL $CDL_BASH_VERSION";exit 0;;
 --format)common_value "$@";FORMAT=$2;shift 2;;--output)common_value "$@";OUTPUT=$2;shift 2;;--no-header)NO_HEADER=1;shift;;--quiet)QUIET=1;shift;;--keep-temp)KEEP_TEMP=1;shift;;
 --min-run-ms)common_value "$@";MINRUN=$2;shift 2;;--near-tolerance)common_value "$@";TOL=$2;shift 2;;--min-level-db)common_value "$@";MINLEVEL=$2;shift 2;;--channel)common_value "$@";CHANNEL=$2;shift 2;;--include-zero)INCLUDE_ZERO=1;shift;;
 -*)die "unknown option: $1";;*)args+=("$1");shift;;esac;done
[[ "$FORMAT" =~ ^(text|tsv|jsonl)$ ]]||die "invalid format";pos "$MINRUN"||die "invalid --min-run-ms";num "$MINLEVEL"||die "invalid --min-level-db";[[ -z "$TOL" ]]||nonneg "$TOL"||die "invalid --near-tolerance";[[ "$CHANNEL" == all || "$CHANNEL" =~ ^[0-9]+$ ]]||die "invalid --channel";((${#args[@]}==1))||die "exactly one input is required"
setup;input=${args[0]};require_file "$input";rate=$(probe_rate "$input");ch=$(probe_channels "$input");if [[ "$CHANNEL" != all ]]&&((CHANNEL<1||CHANNEL>ch));then die "channel out of range";fi;pcm="$TMPDIR_TOOL/audio.pcm";decode_s16 "$input" "$pcm" 0||die "ffmpeg decode failed";events="$TMPDIR_TOOL/events.tsv";:>"$events";minframes=$((rate*MINRUN/1000));((minframes>1))||minframes=2;tolint=0;kind=exact_sample_freeze;if [[ -n "$TOL" ]];then tolint=$(awk -v t="$TOL" 'BEGIN{printf "%d",t*32768}');kind=near_sample_freeze;fi;floor=$(awk -v d="$MINLEVEL" 'BEGIN{printf "%d",32768*exp(log(10)*d/20)}')
od -An -v -t d2 -- "$pcm"|awk -v ch="$ch" -v rate="$rate" -v minf="$minframes" -v tol="$tolint" -v floor="$floor" -v sel="$CHANNEL" -v incz="$INCLUDE_ZERO" -v kind="$kind" -v ev="$events" '
function emit(c,s,e,val, k){if(sel!="all"&&c!=sel)return;if(val==0&&!incz)return;if(val!=0&&((val<0?-val:val)<floor))return;k=(val==0?"zero_flatline":kind);printf "%s\t%.6f\t%.6f\treview\tchannel=%d,value=%d,frames=%d\n",k,s/rate,e/rate,c,val,e-s >> ev}
{for(i=1;i<=NF;i++){c=((n)%ch)+1;v=$i;frame=int(n/ch);if(!(c in have)){prev[c]=v;start[c]=frame;have[c]=1}else{d=v-prev[c];if(d<0)d=-d;if(d>tol){if(frame-start[c]>=minf)emit(c,start[c],frame,prev[c]);start[c]=frame;prev[c]=v}}n++}}
END{last=int(n/ch);for(c=1;c<=ch;c++)if(last-start[c]>=minf)emit(c,start[c],last,prev[c])}'
if [[ "$CHANNEL" == all && "$ch" -gt 1 && -s "$events" ]];then
 awk -F'\t' '{k=$2 FS $3;count[k]++;detail[k]=detail[k] (detail[k]?",":"") $5}END{for(k in count)if(count[k]>1){split(k,p,FS);printf "multichannel_freeze\t%s\t%s\treview\tchannels=%d,%s\n",p[1],p[2],count[k],detail[k]}}' "$events" >>"$events.multi"
 cat "$events.multi" >>"$events"
fi
review=0;grep -q $'\treview\t' "$events"&&review=1||true;status=$([[ $review == 1 ]]&&echo review||echo ok);report_render "$TOOL" "$input" "$events" "$status" "$OUTPUT" "$FORMAT" "$NO_HEADER" "$QUIET"||die "failed to write report";((review))&&exit 1||exit 0
