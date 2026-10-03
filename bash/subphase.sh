#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$HERE/lib/audio-common.sh"; source "$HERE/lib/output.sh"; source "$HERE/lib/pcm.sh"
TOOL=subphase; CROSS=120; WINDOW=250; ACTIVE=-55; WEAK=0.20; NEG=0; CRIT=-0.50; MINRUN=500; IMBAL=4; ALLOW_MONO=0
usage(){ cat <<USAGE
subphase beta — low-frequency stereo correlation analysis
Usage: subphase.sh [options] FILE
  --crossover-hz N --window-ms N --active-db DB --weak-correlation X
  --negative-correlation X --critical-correlation X --min-run-ms N --imbalance-db DB --allow-mono
  --format text|tsv|jsonl --output PATH --no-header --quiet --keep-temp --version --help
USAGE
}
args=(); endopts=0
while (($#)); do
 if ((endopts)); then args+=("$1"); shift; continue; fi
 case "$1" in
  --) endopts=1;shift;; --help) usage;exit 0;; --version) echo "$TOOL $CDL_BASH_VERSION";exit 0;;
  --format) common_value "$@";FORMAT=$2;shift 2;; --output) common_value "$@";OUTPUT=$2;shift 2;; --no-header) NO_HEADER=1;shift;; --quiet) QUIET=1;shift;; --keep-temp) KEEP_TEMP=1;shift;;
  --crossover-hz) common_value "$@";CROSS=$2;shift 2;; --window-ms) common_value "$@";WINDOW=$2;shift 2;; --active-db) common_value "$@";ACTIVE=$2;shift 2;; --weak-correlation) common_value "$@";WEAK=$2;shift 2;; --negative-correlation) common_value "$@";NEG=$2;shift 2;; --critical-correlation) common_value "$@";CRIT=$2;shift 2;; --min-run-ms) common_value "$@";MINRUN=$2;shift 2;; --imbalance-db) common_value "$@";IMBAL=$2;shift 2;; --allow-mono) ALLOW_MONO=1;shift;;
  -*) die "unknown option: $1";; *) args+=("$1");shift;; esac
done
[[ "$FORMAT" =~ ^(text|tsv|jsonl)$ ]]||die "invalid format"; pos "$CROSS"||die "invalid --crossover-hz";pos "$WINDOW"||die "invalid --window-ms";num "$ACTIVE"||die "invalid --active-db";range "$WEAK" -1 1||die "invalid --weak-correlation";range "$NEG" -1 1||die "invalid --negative-correlation";range "$CRIT" -1 1||die "invalid --critical-correlation";pos "$MINRUN"||die "invalid --min-run-ms";nonneg "$IMBAL"||die "invalid --imbalance-db";((${#args[@]}==1))||die "exactly one input is required"
setup; input=${args[0]};require_file "$input";ch=$(probe_channels "$input");rate=$(probe_rate "$input");events="$TMPDIR_TOOL/events.tsv";:>"$events"
if [[ "$ch" == 1 ]]; then
 if (( ! ALLOW_MONO )); then die "subphase requires stereo input"; fi
 status=ok;report_render "$TOOL" "$input" "$events" "$status" "$OUTPUT" "$FORMAT" "$NO_HEADER" "$QUIET"||die "failed to write report";exit 0
fi
[[ "$ch" == 2 ]]||die "subphase requires exactly two channels";pcm="$TMPDIR_TOOL/low.pcm";decode_s16 "$input" "$pcm" 2 "lowpass=f=$CROSS"||die "ffmpeg low-pass decode failed";frames=$(( rate*WINDOW/1000 ));((frames>0))||die "window too small"
od -An -v -t d2 -- "$pcm" | awk -v rate="$rate" -v frames="$frames" -v active="$ACTIVE" -v weak="$WEAK" -v neg="$NEG" -v crit="$CRIT" -v minms="$MINRUN" -v imbal="$IMBAL" -v ev="$events" '
function db(s,n){return (!n||s<=0)?-240:20*log(sqrt(s/n)/32768)/log(10)}
function emit(kind,st,en,sev,det){printf "%s\t%.6f\t%.6f\t%s\t%s\n",kind,st,en,sev,det >> ev}
{for(i=1;i<=NF;i++){v=$i; if(chan==0){L=v;chan=1}else{R=v;idx++;w=int((idx-1)/frames); sl[w]+=L;sr[w]+=R;sll[w]+=L*L;srr[w]+=R*R;slr[w]+=L*R;n[w]++;chan=0}}}
END{for(w=0;w<=int((idx-1)/frames);w++){if(!n[w])continue;lmean=sl[w]/n[w];rmean=sr[w]/n[w];cov=slr[w]-n[w]*lmean*rmean;vl=sll[w]-n[w]*lmean*lmean;vr=srr[w]-n[w]*rmean*rmean;lrms=db(sll[w],n[w]);rrms=db(srr[w],n[w]);ar=(lrms>rrms?lrms:rrms);if(ar<active)continue;corr=(vl>0&&vr>0)?cov/sqrt(vl*vr):1;bal=lrms-rrms;if(bal<0)bal=-bal;st=w*frames/rate;en=(w*frames+n[w])/rate;kind="";if(corr<=crit)kind="critical_sub_correlation";else if(corr<neg)kind="negative_sub_correlation";else if(corr<weak)kind="weak_sub_correlation";if(kind!="")emit(kind,st,en,"review",sprintf("correlation=%.6f",corr));if(bal>=imbal)emit("sub_balance_imbalance",st,en,"review",sprintf("imbalance_db=%.3f",bal));}}'
review=0;grep -q $'\treview\t' "$events"&&review=1||true;status=$([[ $review == 1 ]]&&echo review||echo ok);report_render "$TOOL" "$input" "$events" "$status" "$OUTPUT" "$FORMAT" "$NO_HEADER" "$QUIET"||die "failed to write report";((review))&&exit 1||exit 0
