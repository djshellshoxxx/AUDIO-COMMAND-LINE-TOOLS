#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")"&&pwd)
source "$HERE/lib/audio-common.sh";source "$HERE/lib/output.sh";source "$HERE/lib/pcm.sh"
TOOL=transientledger;WINDOW=2000;ENV=10;RISE=6;SPACING=30;ACTIVE=-60;DENSDEV=60;CRESTDEV=6;TOP=20
usage(){ cat <<USAGE
transientledger beta — transient-density and crest-factor timeline
Usage: transientledger.sh [options] FILE
  --window-ms N --envelope-ms N --rise-db DB --min-spacing-ms N --active-db DB
  --density-deviation-pct N --crest-deviation-db DB --top N
  --format text|tsv|jsonl --output PATH --no-header --quiet --keep-temp
USAGE
}
args=();endopts=0
while(($#));do if((endopts));then args+=("$1");shift;continue;fi;case "$1" in
 --)endopts=1;shift;;--help)usage;exit 0;;--version)echo "$TOOL $CDL_BASH_VERSION";exit 0;;
 --format)common_value "$@";FORMAT=$2;shift 2;;--output)common_value "$@";OUTPUT=$2;shift 2;;--no-header)NO_HEADER=1;shift;;--quiet)QUIET=1;shift;;--keep-temp)KEEP_TEMP=1;shift;;
 --window-ms)common_value "$@";WINDOW=$2;shift 2;;--envelope-ms)common_value "$@";ENV=$2;shift 2;;--rise-db)common_value "$@";RISE=$2;shift 2;;--min-spacing-ms)common_value "$@";SPACING=$2;shift 2;;--active-db)common_value "$@";ACTIVE=$2;shift 2;;--density-deviation-pct)common_value "$@";DENSDEV=$2;shift 2;;--crest-deviation-db)common_value "$@";CRESTDEV=$2;shift 2;;--top)common_value "$@";TOP=$2;shift 2;;
 -*)die "unknown option: $1";;*)args+=("$1");shift;;esac;done
[[ "$FORMAT" =~ ^(text|tsv|jsonl)$ ]]||die "invalid format";pos "$WINDOW"||die "invalid --window-ms";pos "$ENV"||die "invalid --envelope-ms";num "$RISE"||die "invalid --rise-db";pos "$SPACING"||die "invalid --min-spacing-ms";num "$ACTIVE"||die "invalid --active-db";nonneg "$DENSDEV"||die "invalid --density-deviation-pct";nonneg "$CRESTDEV"||die "invalid --crest-deviation-db";pos "$TOP"||die "invalid --top";((${#args[@]}==1))||die "exactly one input is required"
setup;input=${args[0]};require_file "$input";rate=$(probe_rate "$input");pcm="$TMPDIR_TOOL/audio.pcm";decode_s16 "$input" "$pcm" 1||die "ffmpeg decode failed";events="$TMPDIR_TOOL/events.tsv";:>"$events";wf=$((rate*WINDOW/1000));ef=$((rate*ENV/1000));gap=$((rate*SPACING/1000));((wf>0&&ef>0))||die "windows too small";metrics="$TMPDIR_TOOL/metrics.tsv"
od -An -v -t d2 -- "$pcm"|awk -v rate="$rate" -v wf="$wf" -v ef="$ef" -v gap="$gap" -v rise="$RISE" -v active="$ACTIVE" '
function dbpow(s,n){return (!n||s<=0)?-240:20*log(sqrt(s/n)/32768)/log(10)}function dbamp(p){return p<=0?-240:20*log(p/32768)/log(10)}
{for(i=1;i<=NF;i++){v=$i;av=v<0?-v:v;w=int(n/wf);e=int(n/ef);ss[w]+=v*v;nn[w]++;if(av>pk[w])pk[w]=av;es[e]+=v*v;en[e]++;n++}}
END{ne=int((n-1)/ef);nw=int((n-1)/wf);last=-999999;for(e=0;e<=ne;e++){edb[e]=dbpow(es[e],en[e]);if(e>0&&edb[e]-edb[e-1]>=rise){sample=e*ef;if(sample-last>=gap){tw=int(sample/wf);tc[tw]++;last=sample}}}for(w=0;w<=nw;w++){if(!nn[w])continue;r=dbpow(ss[w],nn[w]);if(r<active)continue;p=dbamp(pk[w]);crest=p-r;dur=nn[w]/rate;dens=tc[w]/dur;printf "%d\t%.6f\t%.6f\t%.6f\t%.6f\n",w,r,p,crest,dens}}' >"$metrics"
awk -F'\t' -v wf="$wf" -v rate="$rate" -v ddev="$DENSDEV" -v cdev="$CRESTDEV" -v ev="$events" '
{m++;w[m]=$1;crest[m]=$4;dens[m]=$5}function med(a,n, b,i,j,t){for(i=1;i<=n;i++)b[i]=a[i];for(i=1;i<=n;i++)for(j=i+1;j<=n;j++)if(b[j]<b[i]){t=b[i];b[i]=b[j];b[j]=t}return n%2?b[(n+1)/2]:(b[n/2]+b[n/2+1])/2}
END{if(m<2)exit;md=med(dens,m);mc=med(crest,m);for(i=1;i<=m;i++){st=w[i]*wf/rate;en=(w[i]+1)*wf/rate;if(md>0){pct=100*(dens[i]-md)/md;if(pct<0)ap=-pct;else ap=pct;if(ap>=ddev){k=pct>0?"transient_density_high":"transient_density_low";printf "%s\t%.6f\t%.6f\treview\tdensity=%.3f,median=%.3f,deviation_pct=%.1f\n",k,st,en,dens[i],md,ap >> ev}}cd=crest[i]-mc;ac=cd<0?-cd:cd;if(ac>=cdev){k=cd>0?"crest_factor_high":"crest_factor_low";printf "%s\t%.6f\t%.6f\treview\tcrest_db=%.3f,median=%.3f\n",k,st,en,crest[i],mc >> ev}}}' "$metrics"
review=0;grep -q $'\treview\t' "$events"&&review=1||true;status=$([[ $review == 1 ]]&&echo review||echo ok);report_render "$TOOL" "$input" "$events" "$status" "$OUTPUT" "$FORMAT" "$NO_HEADER" "$QUIET"||die "failed to write report";((review))&&exit 1||exit 0
