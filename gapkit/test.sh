#!/usr/bin/env bash
# gapkit/test.sh - builds synthetic fixtures with FFmpeg and checks every gapkit tool end-to-end.
# Tools whose runtime is missing are SKIPPED (not failed): wine (+ ffmpeg.exe/ffprobe.exe on its PATH) for
# .cmd/.vbs, qemu-aarch64-static + aarch64 binutils for ARM64 (or a native ARM64 host), JRuby or
# JRUBY_JAR=/path/jruby-complete.jar for sweepir.     usage: bash gapkit/test.sh
set -uo pipefail
K=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0; skip=0
ok()   { echo "PASS  $1"; pass=$((pass+1)); }
bad()  { echo "FAIL  $1"; fail=$((fail+1)); }
sk()   { echo "SKIP  $1 ($2)"; skip=$((skip+1)); }
chk()  { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
has()  { command -v "$1" >/dev/null 2>&1; }
ff()   { ffmpeg -nostdin -v error -y "$@"; }
winp() { echo "Z:${1//\//\\}"; }
has ffmpeg || { echo "ffmpeg is required for fixtures"; exit 2; }

# ---------- fixtures ----------
mkdir -p "$T/lib/sub" "$T/bpm" "$T/loops" "$T/win/Album"
ff -f lavfi -i "sine=440:d=8,volume='0.5*(1+sin(2*PI*t*0.7))':eval=frame" -ar 44100 -ac 2 -c:a pcm_f32le "$T/stemA.wav"
ff -f lavfi -i "anoisesrc=d=8:a=0.2:c=pink:seed=7,volume='if(lt(mod(t,2),0.3),1,0.05)':eval=frame" -ar 44100 -ac 2 -c:a pcm_f32le "$T/stemB.wav"
ff -i "$T/stemA.wav" -i "$T/stemB.wav" -filter_complex amix=2:normalize=0 -c:a pcm_f32le "$T/mix.wav"
ff -i "$T/stemB.wav" -af "volume='if(between(t,3,3.5),0,1)':eval=frame" -c:a pcm_f32le "$T/stemB_bad.wav"
cp "$T/mix.wav" "$T/lib/song.wav"; ff -i "$T/mix.wav" -b:a 128k "$T/lib/sub/song.mp3"
ff -f lavfi -i "anullsrc=d=1.5:r=44100:cl=stereo" -i "$T/mix.wav" -filter_complex "[0][1]concat=n=2:v=0:a=1,volume=0.6" -ar 48000 "$T/lib/padded.flac"
ff -f lavfi -i "anoisesrc=d=8.1:c=white:seed=3" -ar 44100 "$T/lib/noise.wav"
mk() { ff -f lavfi -i "aevalsrc='0.8*sin(2*PI*60*t)*exp(-30*mod(t,60/$1))+0.2*sin(2*PI*5000*t)*exp(-80*mod(t+30/$1,60/$1))':d=20:s=44100" -c:a "$2" "$3"; }
mk 128 pcm_s16le "$T/bpm/k128.wav"; mk 174 pcm_f32le "$T/bpm/d174.wav"
ff -f lavfi -i "sine=432:d=3" -ar 48000 -c:a pcm_s24le "$T/a432.wav"
ff -f lavfi -i "aevalsrc='(0.4*sin(2*PI*220*t)+0.2*sin(2*PI*440*t+1))*(0.8+0.2*sin(2*PI*5*t))':d=3:s=44100" -c:a pcm_s24le "$T/loops/pad.wav"
ff -f lavfi -i "sine=330:d=2" -write_bext 1 -metadata originator=Jane -metadata time_reference=1728000000 -metadata title=Take3 -ar 48000 -c:a pcm_s16le "$T/meta.wav"

# ---------- bash pipelines ----------
chk "termwave draws"            "NO_COLOR=1 '$K/bash/termwave' '$T/mix.wav' 60 3 | grep -q 'peak'"
chk "stemnull: stems null"      "'$K/bash/stemnull' '$T/mix.wav' '$T/stemA.wav' '$T/stemB.wav'"
chk "stemnull: dropout caught"  "! '$K/bash/stemnull' '$T/mix.wav' '$T/stemA.wav' '$T/stemB_bad.wav' && { '$K/bash/stemnull' '$T/mix.wav' '$T/stemA.wav' '$T/stemB_bad.wav' || true; } | grep -q 'FAIL *3.0s'"
out=$("$K/bash/fuzzydupe" "$T/lib" 2>/dev/null)
chk "fuzzydupe: mp3+padded flac found, noise not" "[ \$(echo \"\$out\" | wc -l) -eq 3 ] && ! echo \"\$out\" | grep -q noise"
chk "spectrosheet renders"      "'$K/bash/spectrosheet' -c 2 '$T/lib' '$T/sheet.png' && [ -s '$T/sheet.png' ]"
# ---------- obscure scripting ----------
if has tclsh; then chk "riffscrub strips bext/LIST, audio identical" "tclsh '$K/tcl/riffscrub.tcl' -out '$T/clean' '$T/meta.wav' && [ \"\$(tclsh '$K/tcl/riffscrub.tcl' -list '$T/clean' | head -1)\" = 'meta.wav: fmt data' ] && [ \"\$(ffmpeg -v error -i '$T/meta.wav' -f md5 -)\" = \"\$(ffmpeg -v error -i '$T/clean/meta.wav' -f md5 -)\" ]"; else sk riffscrub tclsh; fi
if has lua5.4 || has lua; then L=$(has lua5.4 && echo lua5.4 || echo lua); chk "tunecents finds A=432" "$L '$K/lua/tunecents.lua' '$T/a432.wav' | grep -q 'A = 432.0 Hz'"; else sk tunecents lua; fi
if has gawk; then printf '0:00 Intro\n3:15 DJ A – Rise\n7:02.5 2. B - Night\n' > "$T/set.txt"; chk "setlist2cue cue+ffmeta" "gawk -f '$K/awk/setlist2cue.awk' '$T/set.txt' | grep -q 'INDEX 01 07:02:38' && gawk -f '$K/awk/setlist2cue.awk' -v fmt=ffmeta '$T/set.txt' | grep -q 'START=422500'"; else sk setlist2cue gawk; fi
# ---------- php / js / perl / jruby ----------
if has php; then
  chk "tempotag 128 and 174 BPM" "php '$K/php/tempotag.php' '$T/bpm' | awk -F, 'NR>1{b=\$2+0; a=\$3+0; if(!((b>127.5&&b<128.5)||(b>173.5&&b<174.5)||(a>173.5&&a<174.5))) bad=1} END{exit bad}'"
  chk "peakforge JSON v2" "php '$K/php/peakforge.php' --out='$T/peaks' '$T/bpm' && php -r '\$j=json_decode(file_get_contents(\"$T/peaks/k128.peaks.json\"),1); exit(\$j[\"version\"]==2 && max(\$j[\"data\"])>90 ? 0 : 1);'"
else sk "tempotag/peakforge" php; fi
if has node; then chk "autoloop writes smpl loop" "node '$K/javascript/autoloop.js' --write --out='$T/looped' '$T/loops' | grep -q 'score 1.0000' && node '$K/javascript/autoloop.js' --info '$T/looped/pad.wav' | grep -q 'loop 0'"; else sk autoloop node; fi
if has perl; then
  mkdir -p "$T/music/A/One" "$T/pl"; : > "$T/music/A/One/01 - Song.flac"; printf '#EXTM3U\r\nC:\\Old\\A\\One\\01 - Song.mp3\r\n/gone/none.mp3\r\n' > "$T/pl/x.m3u"
  perl "$K/perl/playlistmend.pl" --lib "$T/music" "$T/pl/x.m3u" >/dev/null 2>&1
  chk "playlistmend relinks mp3->flac" "grep -q 'One/01 - Song.flac' '$T/pl/x.fixed.m3u8' && grep -q 'UNRESOLVED: /gone/none.mp3' '$T/pl/x.fixed.m3u8'"
else sk playlistmend perl; fi
JR=""; has jruby && JR=jruby; [ -z "$JR" ] && [ -f "${JRUBY_JAR:-/opt/jruby/jruby-complete.jar}" ] && JR="java -jar ${JRUBY_JAR:-/opt/jruby/jruby-complete.jar}"
if [ -n "$JR" ]; then
  $JR "$K/jruby/sweepir.rb" sweep "$T/sw.wav" --seconds=2 >/dev/null 2>&1
  ff -i "$T/sw.wav" -filter_complex "[0]asplit=2[a][b];[a]adelay=3[a1];[b]adelay=23,volume=-0.5[b1];[a1][b1]amix=2:normalize=0" -c:a pcm_s16le "$T/rec.wav"
  chk "sweepir finds -6 dB reflection at +20 ms" "$JR '$K/jruby/sweepir.rb' deconv '$T/rec.wav' '$T/sw.inv.wav' '$T/ir.wav' --length=0.3 2>/dev/null | grep -q '+  20.00 ms    -6.0 dB'"
else sk sweepir jruby; fi
# ---------- assembly ----------
if has nasm && has ld && [ "$(uname -m)" = x86_64 ]; then
  nasm -f elf64 "$K/asm-x86_64/wavheal.asm" -o "$T/wh.o" && ld -o "$T/wavheal" "$T/wh.o"
  python3 -c "import struct,sys;b=bytearray(open(sys.argv[1],'rb').read());i=b.find(b'data');struct.pack_into('<I',b,4,0);struct.pack_into('<I',b,i+4,0);open(sys.argv[2],'wb').write(b)" "$T/meta.wav" "$T/broken.wav"
  chk "wavheal restores header" "'$T/wavheal' '$T/broken.wav' | grep -q FIXED && cmp '$T/broken.wav' '$T/meta.wav'"
else sk wavheal "nasm/x86_64"; fi
ARM=""; [ "$(uname -m)" = aarch64 ] && has as && ARM=native; has aarch64-linux-gnu-as && has qemu-aarch64-static && ARM=qemu
if [ -n "$ARM" ]; then
  if [ $ARM = native ]; then as "$K/asm-arm64/pcm2wav.S" -o "$T/p.o" && ld -o "$T/pcm2wav" "$T/p.o"; RUN=""; else aarch64-linux-gnu-as "$K/asm-arm64/pcm2wav.S" -o "$T/p.o" && aarch64-linux-gnu-ld -o "$T/pcm2wav" "$T/p.o"; RUN=qemu-aarch64-static; fi
  ff -f lavfi -i "sine=440:d=1" -ac 2 -f s24le "$T/cap.raw"
  chk "pcm2wav lossless wrap" "$RUN '$T/pcm2wav' '$T/cap.raw' '$T/cap.wav' 44100 2 24 && [ \"\$(ffmpeg -v error -f s24le -ar 44100 -ac 2 -i '$T/cap.raw' -f md5 -)\" = \"\$(ffmpeg -v error -i '$T/cap.wav' -f md5 -)\" ]"
else sk pcm2wav "aarch64 toolchain"; fi
# ---------- Windows (via wine) ----------
if has wine && WINEDEBUG=-all wine cmd /c "ffmpeg -version" >/dev/null 2>&1; then
  export WINEDEBUG=-all NOPAUSE=1
  ff -f lavfi -i "sine=200:d=60" -af "volume='if(between(t,40,46),0.9,0.05)':eval=frame" "$T/win/Album/t.wav"
  ff -f lavfi -i "anoisesrc=d=10:c=pink:a=0.1:seed=1" "$T/win/n.wav"
  chk "dropnorm.cmd -> -14 LUFS" "wine cmd /c '$(winp "$K/windows/dropnorm.cmd")' '$(winp "$T/win/n.wav")' 2>/dev/null | grep -q -- '-> -14.0 LUFS'"
  chk "previewcut.cmd finds loud part" "wine cmd /c '$(winp "$K/windows/previewcut.cmd")' '$(winp "$T/win/Album")' 2>/dev/null | grep -q 'loudest 3 s at 42 s' && [ -s '$T/win/Album/previews/t_preview.mp3' ]"
  chk "bwfcatalog.vbs CSV" "wine cscript //nologo '$(winp "$K/vbscript/bwfcatalog.vbs")' '$(winp "$T/meta.wav")' '$(winp "$T/cat.csv")' >/dev/null 2>&1; grep -q '\"Jane\".*\"10:00:00:00\"' '$T/cat.csv'"
else sk "dropnorm/previewcut/bwfcatalog" "wine + ffmpeg.exe"; fi
echo "---- $pass passed, $fail failed, $skip skipped"
exit $fail
