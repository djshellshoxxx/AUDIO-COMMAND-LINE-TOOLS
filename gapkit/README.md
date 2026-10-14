# gapkit: audio tools for real workflow gaps

> **BETA:** like the rest of this repository. Keep backups, and check the output before you rely on it.

There are 17 small tools here, written in 12 languages and runtimes. Each one covers a job that has no free
command-line tool, or whose only tools are GUI-only, paid, or tied to a heavy runtime. They run on their own and
need nothing from the rest of the repo. Tools marked **batch** take folders or many files at once.

| Tool | Language | Batch | What it fills |
|---|---|:-:|---|
| [`termwave`](bash/termwave) | Bash pipeline: `ffprobe \| ffmpeg \| od \| awk` | | Draws a colour waveform of any audio file right in the terminal. You can see clipping and the shape of a song over SSH or PuTTY with no GUI |
| [`stemnull`](bash/stemnull) | Bash pipeline: `ffprobe \| ffmpeg (amix, invert, astats) \| awk` | | Null test that checks whether your stems add up to the master. It also gives the time ranges where they don't, and exits 0 or 1 so you can use it in CI |
| [`fuzzydupe`](bash/fuzzydupe) | Bash pipeline: `find \| xargs -P ffmpeg \| od \| awk \| sort \| awk` | ✓ | Finds the same recording saved as mp3, flac or wav, even at a different gain or with silence added at the start. Hash-based duplicate finders miss these |
| [`spectrosheet`](bash/spectrosheet) | Bash pipeline: `find \| sort \| xargs -P (ffmpeg ebur128 \| awk; showspectrumpic)` → `ffmpeg tile` | ✓ | Puts a spectrogram of every file in a folder on one PNG, labelled with LUFS, true peak and length |
| [`riffscrub.tcl`](tcl/riffscrub.tcl) | Tcl | ✓ | Strips private metadata from WAVs (bext originator, iXML notes and location, LIST/INFO, id3, XMP) without changing a single audio sample |
| [`tunecents.lua`](lua/tunecents.lua) | Lua 5.3+ | | Works out what tuning a recording uses, e.g. "+10 cents, so A = 442.5 Hz" (432 Hz tracks, detuned rips, orchestras) |
| [`setlist2cue.awk`](awk/setlist2cue.awk) | GNU awk | | Turns a DJ-mix or podcast tracklist into a CUE sheet, a YouTube chapter list or FFmpeg chapter metadata, and checks it for errors |
| [`dropnorm.cmd`](windows/dropnorm.cmd) | Windows batch | ✓ | Drag and drop to get **true two-pass** linear EBU R128 loudness normalisation. It warns when FFmpeg had to switch to dynamic (compressing) mode |
| [`previewcut.cmd`](windows/previewcut.cmd) | Windows batch | ✓ | Makes store and promo preview clips from the **loudest part** of each track instead of the intro |
| [`peakforge.php`](php/peakforge.php) | PHP 7.4+ | ✓ | Waveform JSON compatible with audiowaveform for peaks.js and wavesurfer.js. Runs on shared hosting with no `exec()`, ffmpeg or binaries |
| [`tempotag.php`](php/tempotag.php) | PHP 7.4+ | ✓ | BPM detection in pure PHP for upload pipelines, with CSV or JSON output and the half/double-time reading |
| [`autoloop.js`](javascript/autoloop.js) | Node.js | ✓ | Finds seamless sustain-loop points in instrument samples and **writes the WAV `smpl` chunk** so samplers loop them automatically |
| [`playlistmend.pl`](perl/playlistmend.pl) | Perl 5 | ✓ | Fixes M3U, M3U8 and PLS playlists that broke after a library was moved, renamed or converted (mp3 to flac). Handles Windows paths and `file://` URIs |
| [`sweepir.rb`](jruby/sweepir.rb) | JRuby (javax.sound) | | Captures impulse responses with a sine sweep (Farina method) and lists the early reflections |
| [`bwfcatalog.vbs`](vbscript/bwfcatalog.vbs) | VBScript | ✓ | Builds a CSV catalogue of BWF and iXML metadata (scene, take, tape, timecode, notes) on any Windows PC with nothing to install. Accepts drag and drop |
| [`wavheal.asm`](asm-x86_64/wavheal.asm) | x86-64 assembly (NASM) | ✓ | Repairs WAVs left with a 0 or bad header after a crash. It rewrites only the 8 bytes of the two size fields, in place |
| [`pcm2wav.S`](asm-arm64/pcm2wav.S) | ARM64 assembly (GNU as) | | Wraps headerless raw PCM (ADC/I2S, `arecord -t raw`, SDR or firmware dumps) into a WAV. Static binary with no libc, made for the Raspberry Pi |

## Paste-and-run quick start (Linux / SSH / PuTTY)

Each block is one paste. Paste it into the terminal and press Enter.

```bash
cd ~/AUDIO-COMMAND-LINE-TOOLS/gapkit && chmod +x bash/* test.sh && bash test.sh
```

```bash
cd ~/AUDIO-COMMAND-LINE-TOOLS/gapkit && ./bash/termwave ~/Music/song.flac
./bash/stemnull master.wav stems/*.wav            # exit 0 = nulls
./bash/fuzzydupe ~/Music > dupes.tsv              # similarity <TAB> fileA <TAB> fileB
./bash/spectrosheet -c 4 ~/Samples sheet.png
```

```bash
tclsh tcl/riffscrub.tcl -list ~/FieldRecs                 # chunk map only
tclsh tcl/riffscrub.tcl -out ~/FieldRecs_clean ~/FieldRecs
lua lua/tunecents.lua track.wav
gawk -f awk/setlist2cue.awk -v file=mix.mp3 setlist.txt > mix.cue
gawk -f awk/setlist2cue.awk -v fmt=youtube setlist.txt
php php/peakforge.php --spp=512 --out=public/peaks uploads/
php php/tempotag.php --min=70 --max=180 crate/ > bpm.csv
node javascript/autoloop.js --write --out=looped/ samples/
perl perl/playlistmend.pl --lib ~/Music --relative ~/Playlists/*.m3u
jruby jruby/sweepir.rb sweep sweep.wav --seconds=4                 # play + record it, then:
jruby jruby/sweepir.rb deconv recording.wav sweep.inv.wav room_ir.wav
```

Assembly tools (build once, then run):

```bash
nasm -f elf64 asm-x86_64/wavheal.asm -o /tmp/wh.o && ld -o ~/bin/wavheal /tmp/wh.o && wavheal crashed/*.wav
as asm-arm64/pcm2wav.S -o /tmp/p.o && ld -o ~/bin/pcm2wav /tmp/p.o && pcm2wav capture.raw capture.wav 48000 2 24   # on ARM64
```

Windows: drag files or folders onto `dropnorm.cmd`, `previewcut.cmd` or `bwfcatalog.vbs`. You can also use the console:

```bat
set DROPNORM_TARGET=-16 & dropnorm.cmd "D:\Podcast\Episodes"
set PREVIEW_LEN=45 & previewcut.cmd "D:\Releases\EP01"
cscript //nologo bwfcatalog.vbs "E:\Day 3" "E:\day3.csv" 23.976
```

The `.cmd` tools need `ffmpeg.exe` and `ffprobe.exe` on your PATH or in the same folder.

## How each gap was chosen

* **Seamless loop points + `smpl`**: the main open-source loop finder (PyMusicLooper) is aimed at looping music. It does not write sampler `smpl` loop chunks for instrument samples, and the GUI tools that do (Endless Wave and similar) are paid.
* **Stem null test**: the stem checkers people discuss are DAW templates, macOS GUI apps, or features inside mastering products. None of them is a scriptable CLI that reports where the stems fail.
* **Waveform JSON in PHP**: existing peak generators (audiowaveform, wav2json, audio2json, waveform-util) all need a compiled binary or ffmpeg, which shared hosting rarely allows.
* **WAV header repair**: the usual advice is "edit the size fields in a hex editor" or "script SoX yourself". wavheal is a tiny batch tool that does exactly that.
* Others come from familiar forum pain points: playlists broken after a move, BWF catalogues on locked-down Windows PCs, privacy-scrubbing field recordings, 432 Hz and detune questions, previews that start on the intro, and LUFS normalisation without a GUI.

## Testing

`bash gapkit/test.sh` makes synthetic fixtures and runs all 18 checks. Every check passed during development on Linux. The Windows tools were tested under Wine 9 with the Windows FFmpeg 7.1 build, ARM64 under `qemu-aarch64-static`, and JRuby 9.4 with the `jruby-complete` jar. Each check runs the tool on a known input and compares the result with the right answer:

* termwave runs on a test track and prints its waveform and peak level.
* stemnull reports that a matching stem set nulls, and flags a 0.5 s dropout in a damaged stem at 3.0 s.
* fuzzydupe flags the mp3 copy and a silence-padded, gain-changed flac copy as duplicates (similarity 0.90–0.99). Unrelated files score at most 0.73 and are not reported.
* spectrosheet writes a contact-sheet PNG for the test folder.
* riffscrub removes the bext and LIST chunks and leaves the audio MD5 unchanged.
* tunecents reads A = 432.0 Hz for a 432 Hz tone. During development it also gave +10.0 cents (A = 442.5 Hz) for a 442.5 Hz tone.
* setlist2cue converts a 7:02.5 timestamp to the CUE frame `07:02:38` and the chapter start 422500 ms.
* tempotag gets 127.97 BPM for a 128 BPM click track and 174.19 BPM for a 174 BPM one.
* peakforge writes version-2 waveform JSON with peaks at the expected level.
* autoloop finds a loop of exactly 1.000 s (whole tremolo cycles) and the `smpl` chunk reads back correctly.
* playlistmend re-links a Windows path to a renamed `.flac` and marks the file that no longer exists.
* sweepir measures 3.00 ms latency and a −6.0 dB inverted reflection at +20 ms on a simulated room.
* wavheal restores a broken header byte for byte, and healthy files are left untouched.
* pcm2wav wraps raw 24-bit PCM losslessly: the decoded audio MD5 matches the input.
* dropnorm.cmd brings a test file to −14.0 LUFS (−16.0 when the target is set to −16).
* previewcut.cmd finds the loud section at 42 s and cuts the preview around it.
* bwfcatalog.vbs reads the originator and timecode into the CSV. During development it also produced the 23.976 fps iXML timecode `10:00:01:00`.

Known limits: tempo detection based on onsets can be off by a factor of two, so `tempotag` also prints `alt_octave`. The `.cmd` tools can't handle file names that contain `!` (a delayed-expansion limitation in cmd). `bwfcatalog.vbs` reads bytes through FSO in ASCII mode, which is reliable on single-byte Windows code pages.
