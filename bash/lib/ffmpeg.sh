#!/usr/bin/env bash
# Shared FFmpeg measurement helpers. Source common.sh first.
measure_duration(){ probe_value "$1" duration format; }
measure_integrated_lufs(){
  LC_ALL=C ffmpeg -hide_banner -nostats -i "$1" -filter_complex ebur128=peak=true -f null - 2>&1 | awk '/Integrated loudness:/{seen=1;next} seen && /^[[:space:]]*I:/{print $2; exit}'
}
phase_metadata(){
  LC_ALL=C ffmpeg -hide_banner -loglevel error -i "$1" -af "aphasemeter=video=0,ametadata=print:key=lavfi.aphasemeter.phase:file=-" -f null - 2>/dev/null
}
