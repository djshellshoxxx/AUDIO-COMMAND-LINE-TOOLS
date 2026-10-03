#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$HERE/lib/audio-common.sh"; source "$HERE/lib/output.sh"; source "$HERE/lib/pcm.sh"
TOOL=banddrift; WINDOW=1000; DEV=8; ACTIVE=-60; MINRUN=2; TOP=20
NAMES=(sub bass lowmid highmid high); LOWS=(20 80 250 1000 5000); HIGHS=(80 250 1000 5000 20000); CUSTOM=0
usage(){ cat <<USAGE
banddrift beta — time-coded tonal-balance drift analysis
Usage: banddrift.sh [options] FILE
  --window-ms N --band NAME:LOW:HIGH (repeatable) --deviation-pct N --active-db DB
  --min-run-windows N --top N --format text|tsv|jsonl --output PATH --no-header --quiet --keep-temp
USAGE
}
args=();endopts=0
while (($#));do
 if ((endopts));then args+=("$1");shift;continue;fi
 case "$1" in
  --)endopts=1;shift;;--help)usage;exit 0;;--version)echo "$TOOL $CDL_BASH_VERSION";exit 0;;
  --format)common_value "$@";FORMAT=$2;shift 2;;--output)common_value "$@";OUTPUT=$2;shift 2;;--no-header)NO_HEADER=1;shift;;--quiet)QUIET=1;shift;;--keep-temp)KEEP_TEMP=1;shift;;
  --window-ms)common_value "$@";WINDOW=$2;shift 2;;--deviation-pct)common_value "$@";DEV=$2;shift 2;;--active-db)common_value "$@";ACTIVE=$2;shift 2;;--min-run-windows)common_value "$@";MINRUN=$2;shift 2;;--top)common_value "$@";TOP=$2;shift 2;;
  --band)common_value "$@";if((!CUSTOM));then NAMES=();LOWS=();HIGHS=();CUSTOM=1;fi;IFS=: read -r bn bl bh extra<<<"$2";[[ -n "$bn"&&-n "$bl"&&-n "$bh"&&-z "${extra:-}" ]]||die "invalid --band";pos "$bl"||die "invalid band low";pos "$bh"||die "invalid band high";awk -v l="$bl" -v h="$bh" 'BEGIN{exit !(h>l)}'||die "band high must exceed low";NAMES+=("$bn");LOWS+=("$bl");HIGHS+=("$bh");shift 2;;
  -*)die "unknown option: $1";;*)args+=("$1");shift;;esac
done
[[ "$FORMAT" =~ ^(text|tsv|jsonl)$ ]]||die "invalid format";pos "$WINDOW"||die "invalid --window-ms";nonneg "$DEV"||die "invalid --deviation-pct";num "$ACTIVE"||die "invalid --active-db";pos "$MINRUN"||die "invalid --min-run-windows";pos "$TOP"||die "invalid --top";((${#args[@]}==1))||die "exactly one input is required"
for((i=0;i<${#NAMES[@]};i++));do for((j=i+1;j<${#NAMES[@]};j++));do awk -v a="${LOWS[i]}" -v b="${HIGHS[i]}" -v c="${LOWS[j]}" -v d="${HIGHS[j]}" 'BEGIN{exit !((a<d)&&(c<b))}'&&die "bands overlap: ${NAMES[i]} and ${NAMES[j]}"||true;done;done
setup;input=${args[0]};require_file "$input";rate=$(probe_rate "$input");events="$TMPDIR_TOOL/events.tsv";:>"$events";frames=$((rate*WINDOW/1000));((frames>0))||die "window too small"
metric_files=()
for((b=0;b<${#NAMES[@]};b++));do
 out="$TMPDIR_TOOL/b$b.pcm";met="$TMPDIR_TOOL/b$b.txt";filter="highpass=f=${LOWS[b]},lowpass=f=${HIGHS[b]}";decode_s16 "$input" "$out" 1 "$filter"||die "ffmpeg band decode failed"
 od -An -v -t d2 -- "$out"|awk -v f="$frames" '{for(i=1;i<=NF;i++){k=int(n/f);s[k]+=$i*$i;c[k]++;n++}}END{for(k=0;k<=int((n-1)/f);k++)if(c[k])printf "%d %.12f %d\n",k,s[k],c[k]}' >"$met";metric_files+=("$met")
done
paste "${metric_files[@]}" >"$TMPDIR_TOOL/all.txt"; raw="$TMPDIR_TOOL/events.raw"
awk -v nb="${#NAMES[@]}" -v names="$(IFS=,;echo "${NAMES[*]}")" -v rate="$rate" -v frames="$frames" -v dev="$DEV" -v active="$ACTIVE" -v minrun="$MINRUN" -v ev="$raw" '
BEGIN{split(names,nm,",")}
{w=$1;total=0;for(b=1;b<=nb;b++){off=(b-1)*3;ss[b]=$(off+2);cc[b]=$(off+3);total+=ss[b]}if(total<=0)next;tdb=20*log(sqrt(total/(cc[1]*nb))/32768)/log(10);if(tdb<active)next;activew[++m]=w;for(b=1;b<=nb;b++){share[m,b]=100*ss[b]/total;vals[b,m]=share[m,b]}}
function sortv(a,n, i,j,t){for(i=1;i<=n;i++)for(j=i+1;j<=n;j++)if(a[j]<a[i]){t=a[i];a[i]=a[j];a[j]=t}}
function emitband(b,s,e,sign, maxdev, kind){if(e-s+1<minrun)return;kind=sign>0?"band_share_high":"band_share_low";printf "%s\t%.6f\t%.6f\treview\tband=%s,windows=%d,max_deviation=%.3f\n",kind,activew[s]*frames/rate,(activew[e]*frames+frames)/rate,nm[b],e-s+1,maxdev >> ev}
function emitbroad(s,e){if(e-s+1<minrun)return;printf "broad_tonal_shift\t%.6f\t%.6f\treview\twindows=%d\n",activew[s]*frames/rate,(activew[e]*frames+frames)/rate,e-s+1 >> ev}
END{
 if(!m)exit;for(b=1;b<=nb;b++){delete tmp;for(i=1;i<=m;i++)tmp[i]=vals[b,i];sortv(tmp,m);med[b]=(m%2)?tmp[(m+1)/2]:(tmp[m/2]+tmp[m/2+1])/2}
 for(b=1;b<=nb;b++){rs=0;rsign=0;rmax=0;prevw=-2;for(i=1;i<=m;i++){d=share[i,b]-med[b];ad=d<0?-d:d;sign=(ad>=dev?(d>0?1:-1):0);cont=(sign!=0&&sign==rsign&&activew[i]==prevw+1);if(cont){re=i;if(ad>rmax)rmax=ad}else{if(rsign!=0)emitband(b,rs,re,rsign,rmax);if(sign!=0){rs=i;re=i;rsign=sign;rmax=ad}else rsign=0}prevw=activew[i]}if(rsign!=0)emitband(b,rs,re,rsign,rmax)}
 bs=0;bin=0;prevw=-2;for(i=1;i<=m;i++){hits=0;for(b=1;b<=nb;b++){d=share[i,b]-med[b];if((d<0?-d:d)>=dev)hits++}good=(hits>=2);if(good&&bin&&activew[i]==prevw+1){be=i}else{if(bin)emitbroad(bs,be);if(good){bs=i;be=i;bin=1}else bin=0}prevw=activew[i]}if(bin)emitbroad(bs,be)
}' "$TMPDIR_TOOL/all.txt"
if [[ -s "$raw" ]];then head -n "$TOP" "$raw" >"$events";fi
review=0;grep -q $'\treview\t' "$events"&&review=1||true;status=$([[ $review == 1 ]]&&echo review||echo ok);report_render "$TOOL" "$input" "$events" "$status" "$OUTPUT" "$FORMAT" "$NO_HEADER" "$QUIET"||die "failed to write report";((review))&&exit 1||exit 0
