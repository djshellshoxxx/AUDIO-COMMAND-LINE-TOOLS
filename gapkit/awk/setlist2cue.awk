#!/usr/bin/gawk -f
# setlist2cue - turn a DJ-mix / live-set / podcast tracklist into a CUE sheet, a YouTube chapter list or an
# FFmpeg FFMETADATA chapter file (embed with: ffmpeg -i mix.mp3 -i chap.txt -map_metadata 1 -c copy out.mp3),
# and validate it (out-of-order times, YouTube's 0:00 / 10 s / 3-chapter rules, CUE 75-fps frames).
# Accepts lines like:  00:00 Artist - Title | [1:02:33] Artist – Title | 12:30.5  Title only | 01:03:05 1. Artist - Title
# usage: gawk -f setlist2cue.awk [-v fmt=cue|youtube|ffmeta] [-v file=mix.mp3] [-v total=SECONDS] setlist.txt
function secs(t,   p, n) { n = split(t, p, ":"); return n == 3 ? p[1] * 3600 + p[2] * 60 + p[3] : p[1] * 60 + p[2] }
function hms(s) { return s >= 3600 ? sprintf("%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : sprintf("%d:%02d", s / 60, s % 60) }
function esc(s) { gsub(/[\\=;#]/, "\\\\&", s); return s }   # FFMETADATA escaping
function q(s) { gsub(/"/, "'", s); return s }
BEGIN { if (fmt == "") fmt = "cue"; if (file == "") file = "mix.mp3"; warn = 0 }
{ sub(/\r$/, "") }
match($0, /^[[:space:]]*\[?([0-9]+(:[0-9]{1,2}){1,2}(\.[0-9]+)?)\]?[[:space:]]*(-|–|—|\.|\))?[[:space:]]*(.*)$/, m) {
  t = secs(m[1]); rest = m[5]; sub(/^[0-9]+[.)][[:space:]]+/, "", rest)
  if (n && t <= T[n]) { printf "line %d: %s is not after previous track (%s)\n", NR, m[1], hms(T[n]) > "/dev/stderr"; warn++ }
  n++; T[n] = t
  if (split(rest, a, /[[:space:]]+(-|–|—)[[:space:]]+/) >= 2) { A[n] = a[1]; N[n] = substr(rest, length(a[1]) + 1); sub(/^[[:space:]]+(-|–|—)[[:space:]]+/, "", N[n]) }
  else { A[n] = ""; N[n] = rest }
  next
}
/[^[:space:]]/ { printf "line %d ignored (no timestamp): %s\n", NR, $0 > "/dev/stderr" }
END {
  if (!n) { print "no timestamped lines found" > "/dev/stderr"; exit 2 }
  if (fmt == "youtube") {
    if (T[1] != 0) { print "youtube: first chapter must start at 0:00" > "/dev/stderr"; warn++ }
    if (n < 3) { print "youtube: needs at least 3 chapters" > "/dev/stderr"; warn++ }
    for (i = 1; i <= n; i++) {
      if (i > 1 && T[i] - T[i-1] < 10) { printf "youtube: chapter %d is shorter than 10 s\n", i - 1 > "/dev/stderr"; warn++ }
      printf "%s %s%s\n", hms(int(T[i])), A[i] != "" ? A[i] " - " : "", N[i]
    }
  } else if (fmt == "ffmeta") {
    print ";FFMETADATA1"
    for (i = 1; i <= n; i++) {
      end = i < n ? T[i+1] : (total ? total : T[i] + 1)
      printf "[CHAPTER]\nTIMEBASE=1/1000\nSTART=%d\nEND=%d\ntitle=%s\n", T[i] * 1000, end * 1000, esc((A[i] != "" ? A[i] " - " : "") N[i])
    }
  } else {
    ext = toupper(file); sub(/.*\./, "", ext); type = (ext == "WAV" || ext == "AIFF" || ext == "FLAC") ? "WAVE" : "MP3"
    printf "FILE \"%s\" %s\n", q(file), type
    for (i = 1; i <= n; i++) {
      fr = int(T[i] * 75 + 0.5)
      printf "  TRACK %02d AUDIO\n", i
      if (A[i] != "") printf "    PERFORMER \"%s\"\n", q(A[i])
      printf "    TITLE \"%s\"\n    INDEX 01 %02d:%02d:%02d\n", q(N[i]), int(fr / 4500), int(fr / 75) % 60, fr % 75
    }
    if (n > 99) { print "cue: more than 99 tracks is not valid Red Book" > "/dev/stderr"; warn++ }
  }
  if (total && T[n] >= total) { print "last timestamp is beyond total length" > "/dev/stderr"; warn++ }
  printf "%d track(s), %d warning(s)\n", n, warn > "/dev/stderr"
  exit warn ? 1 : 0
}
