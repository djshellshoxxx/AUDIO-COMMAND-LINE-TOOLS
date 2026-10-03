#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$HERE/lib/audio-common.sh"; source "$HERE/lib/output.sh"; source "$HERE/lib/pcm.sh"
TOOL=edgeguard; WINDOW=100; SUB=10; ACTIVE=-60; BOUND=-24; DISC=0.15; FADE_TOL=1; SIDE=both
usage(){ cat <<USAGE
edgeguard beta — suspicious audio boundary/truncation analysis
Usage: edgeguard.sh [options] FILE
  --window-ms N --subwindow-ms N --active-db DB --boundary-rms-db DB
  --discontinuity X --fade-tolerance N --side start|end|both
  --format text|tsv|jsonl --output PATH --no-header --quiet --keep-temp --version --help
USAGE
}
args=(); endopts=0
while (($#)); do
  if (( endopts )); then args+=("$1"); shift; continue; fi
  case "$1" in
    --) endopts=1; shift;; --help) usage; exit 0;; --version) echo "$TOOL $CDL_BASH_VERSION"; exit 0;;
    --format) common_value "$@"; FORMAT=$2; shift 2;; --output) common_value "$@"; OUTPUT=$2; shift 2;; --no-header) NO_HEADER=1; shift;; --quiet) QUIET=1; shift;; --keep-temp) KEEP_TEMP=1; shift;;
    --window-ms) common_value "$@"; WINDOW=$2; shift 2;; --subwindow-ms) common_value "$@"; SUB=$2; shift 2;; --active-db) common_value "$@"; ACTIVE=$2; shift 2;; --boundary-rms-db) common_value "$@"; BOUND=$2; shift 2;; --discontinuity) common_value "$@"; DISC=$2; shift 2;; --fade-tolerance) common_value "$@"; FADE_TOL=$2; shift 2;; --side) common_value "$@"; SIDE=$2; shift 2;;
    -*) die "unknown option: $1";; *) args+=("$1"); shift;; esac
done
[[ "$FORMAT" =~ ^(text|tsv|jsonl)$ ]] || die "invalid format"; pos "$WINDOW" || die "invalid --window-ms"; pos "$SUB" || die "invalid --subwindow-ms"; num "$ACTIVE" || die "invalid --active-db"; num "$BOUND" || die "invalid --boundary-rms-db"; range "$DISC" 0 2 || die "invalid --discontinuity"; nonneg "$FADE_TOL" || die "invalid --fade-tolerance"; [[ "$SIDE" =~ ^(start|end|both)$ ]] || die "invalid --side"; ((${#args[@]}==1)) || die "exactly one input is required"
setup; input=${args[0]}; require_file "$input"; pcm="$TMPDIR_TOOL/audio.pcm"; decode_s16 "$input" "$pcm" 1 || die "ffmpeg decode failed"; rate=$(probe_rate "$input"); [[ "$rate" =~ ^[0-9]+$ ]] || die "cannot determine sample rate"; events="$TMPDIR_TOOL/events.tsv"; : >"$events"
win=$(( rate * WINDOW / 1000 )); sub=$(( rate * SUB / 1000 )); ((win>0&&sub>0)) || die "window too small for sample rate"
od -An -v -t d2 -- "$pcm" | awk -v rate="$rate" -v win="$win" -v subframes="$sub" -v active="$ACTIVE" -v bound="$BOUND" -v disc="$DISC" -v tol="$FADE_TOL" -v side="$SIDE" -v ev="$events" '
function db(sum,n){return (!n||sum<=0)?-240:20*log(sqrt(sum/n)/32768)/log(10)}
{for(i=1;i<=NF;i++) a[++n]=$i}
END{
 if(n<2) exit 0; w=(win<n?win:n); k=int((w+subframes-1)/subframes);
 for(i=1;i<=w;i++){ss+=a[i]*a[i]; j=int((i-1)/subframes)+1; se[j]+=a[i]*a[i]; sn[j]++}
 for(i=n-w+1;i<=n;i++){ee+=a[i]*a[i]; j=int((i-(n-w+1))/subframes)+1; xe[j]+=a[i]*a[i]; xn[j]++}
 sdb=db(ss,w); edb=db(ee,w); sfail=0; efail=0;
 for(j=1;j<k;j++){x=db(se[j],sn[j]);y=db(se[j+1],sn[j+1]);if(y+0.75<x)sfail++;x=db(xe[j],xn[j]);y=db(xe[j+1],xn[j+1]);if(y>x+0.75)efail++}
 sflat=(sfail>tol || (db(se[k],sn[k])-db(se[1],sn[1])<6)); eflat=(efail>tol || (db(xe[1],xn[1])-db(xe[k],xn[k])<6));
 dstart=sqrt((a[1]/32768)^2); dend=sqrt((a[n]/32768)^2);
 if(side!="end" && sdb>active) printf "active_at_start\t0\t%.6f\tinfo\trms_db=%.3f\n",w/rate,sdb >> ev;
 if(side!="start" && edb>active) printf "active_at_end\t%.6f\t%.6f\tinfo\trms_db=%.3f\n",(n-w)/rate,n/rate,edb >> ev;
 if(side!="end" && dstart>=disc) printf "start_discontinuity\t0\t%.6f\treview\tdelta=%.6f\n",1/rate,dstart >> ev;
 if(side!="start" && dend>=disc) printf "end_discontinuity\t%.6f\t%.6f\treview\tdelta=%.6f\n",(n-1)/rate,n/rate,dend >> ev;
 if(side!="end" && sdb>bound && sflat) printf "no_start_fade_evidence\t0\t%.6f\treview\trms_db=%.3f\n",w/rate,sdb >> ev;
 if(side!="start" && edb>bound && eflat) printf "no_end_fade_evidence\t%.6f\t%.6f\treview\trms_db=%.3f\n",(n-w)/rate,n/rate,edb >> ev;
 if(side!="end" && sdb>bound && (sflat || dstart>=disc)) printf "possible_truncated_start\t0\t%.6f\treview\trms_db=%.3f\n",w/rate,sdb >> ev;
 if(side!="start" && edb>bound && (eflat || dend>=disc)) printf "possible_truncated_end\t%.6f\t%.6f\treview\trms_db=%.3f\n",(n-w)/rate,n/rate,edb >> ev;
}'
review=0; grep -q $'\treview\t' "$events" && review=1 || true; status=$([[ $review == 1 ]] && echo review || echo ok); report_render "$TOOL" "$input" "$events" "$status" "$OUTPUT" "$FORMAT" "$NO_HEADER" "$QUIET" || die "failed to write report"; ((review)) && exit 1 || exit 0
