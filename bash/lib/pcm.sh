#!/usr/bin/env bash
decode_s16(){
  local input=$1 out=$2 channels=${3:-0} filter=${4:-}
  local args=(-v error -nostdin -i "$input" -map 0:a:0)
  [[ -n "$filter" ]] && args+=(-af "$filter")
  (( channels > 0 )) && args+=(-ac "$channels")
  ffmpeg "${args[@]}" -f s16le -acodec pcm_s16le -y "$out" || return 2
}
rms_db_pcm(){
  od -An -v -t d2 -- "$1" | awk '{for(i=1;i<=NF;i++){s+=$i*$i;n++}}END{if(!n||s==0)print -240;else printf "%.6f\n",20*log(sqrt(s/n)/32768)/log(10)}'
}
frames_to_seconds(){ awk -v f="$1" -v r="$2" 'BEGIN{printf "%.6f",f/r}'; }
