# Audio Command Line Tools

Ten focused Python/JavaScript audio utilities plus seven **Beta shell-native FFmpeg/FFprobe QC tools** from **Circuit Drift Labs**. The original tools run in Python, Node, or the browser. The new Bash and PowerShell tools are independent shell implementations that orchestrate FFmpeg/FFprobe directly; they do not call the repository's Python or JavaScript DSP engines.

**[Open the browser workbench](https://djshellshoxxx.github.io/AUDIO-COMMAND-LINE-TOOLS/)** · [Circuit Drift Labs](https://djshellshoxxx.github.io/circuitdriftlabs/) · [Research and existing alternatives](docs/RESEARCH.md) · [Program audit](docs/AUDIT.md)

## Original Python / JavaScript tools

| Tool | What it does | Useful controls / output |
|---|---|---|
| [loopbudget](spec/loopbudget.md) | Loop seam and musical length audit | BPM, bars, meter; frame error and boundary metrics |
| [tailbudget](spec/tailbudget.md) | Budget and trim quiet tails | Activity threshold, kept padding; trimmed WAV |
| [monoledger](spec/monoledger.md) | Time-coded mono cancellation audit | Window size, loss threshold; mono preview WAV |
| [gapcontext](spec/gapcontext.md) | Quiet gap candidates with active flanks | Gap duration, flank RMS threshold; timestamp ledger |
| [railruns](spec/railruns.md) | Consecutive near-full-scale sample runs | Amplitude threshold, run length; channel event ledger |
| [dcjourney](spec/dcjourney.md) | Local DC offset history versus global offset | Windows, offset threshold; globally centered WAV |
| [gainbudget](spec/gainbudget.md) | Requested gain versus sample peak ceiling | Gain, ceiling; safe gain budget and optional WAV |
| [stemcontract](spec/stemcontract.md) | Structural export contract for stems | Required rate/channels/frames, expected names, activity |
| [cueclock](spec/cueclock.md) | Sample-rounded bar cue grid | BPM, meter, spacing, origin; cues and rounding errors |
| [renderdelta](spec/renderdelta.md) | Offset-aware render difference timeline | Sample offset, window, threshold; optional residual WAV |

These are useful combinations of established audio techniques. Related tools already exist; the research does not establish that every workflow is unprecedented. No trained models or external audio services are used.

## Shell-native FFmpeg/FFprobe tools (Beta)

These seven tools live in `bash/` and `powershell/`. Bash requires Bash 4.4+; PowerShell requires PowerShell 7+. Both require `ffmpeg` and `ffprobe` on `PATH`.

| Tool | Gap it targets | Main evidence / output |
|---|---|---|
| [stereotruth](spec/stereotruth.md) | Stereo files that may actually be dual-mono, polarity-inverted or imbalanced | Phase/correlation proportions, per-channel RMS, review findings |
| [loudwalk](spec/loudwalk.md) | Raw EBU R128 logs are awkward for locating unusual sections | Short-term LUFS timeline, median, abrupt jumps, relative outliers |
| [formattruth](spec/formattruth.md) | Extensions/containers/codecs/stream metadata can disagree | Normalized FFprobe facts, extension/container and stream findings |
| [albumcontract](spec/albumcontract.md) | One or two accidental outliers inside a delivery folder | Dominant/expected sample rate, channels and sample format; outlier ledger |
| [phasewatch](spec/phasewatch.md) | Whole-file correlation hides brief stereo phase changes | Timestamped correlation ledger and regime-change candidates |
| [batchsilence](spec/batchsilence.md) | Large exports need comparative leading/trailing silence QC | Per-file silence seconds/ratios and configurable limit findings |
| [transcodeaudit](spec/transcodeaudit.md) | Libraries need quick technical triage without false provenance claims | Codec/container/bitrate/encoder ledger and review heuristics |

Install FFmpeg on Debian/Ubuntu:

```sh
sudo apt update
sudo apt install ffmpeg
```

On Windows, install a current FFmpeg build and ensure both `ffmpeg.exe` and `ffprobe.exe` are on `PATH` (for example with `winget install Gyan.FFmpeg`).

Examples:

```sh
bash bash/stereotruth.sh mix.wav --json
bash bash/loudwalk.sh master.wav --jump-db 4 --deviation-db 7
bash bash/albumcontract.sh exports --recursive --expected-rate 48000 --expected-channels 2 --json
bash bash/batchsilence.sh exports --max-leading 1.0 --max-trailing 2.0 --json
```

```powershell
./powershell/stereotruth.ps1 mix.wav -Json
./powershell/loudwalk.ps1 master.wav -JumpDb 4 -DeviationDb 7 -Json
./powershell/albumcontract.ps1 exports -Recursive -ExpectedRate 48000 -ExpectedChannels 2 -Json
./powershell/batchsilence.ps1 exports -MaxLeading 1.0 -MaxTrailing 2.0 -Json
```

Shell-native JSON reports contain the tool/version, UTC generation time, input paths, FFmpeg/FFprobe versions, effective options, measurements, findings and a final `status`. Their exit codes are **0** = completed with no policy findings, **1** = completed with review findings, **2** = invalid arguments/dependency/input/analysis/report failure. They never modify source audio.

## Run Python

Python 3.10+ and NumPy. From a checkout:

```sh
python -m pip install -r requirements.txt
python python/loopbudget.py loop.wav --bpm 127 --bars 4 --output loop.json
python python/monoledger.py mix.wav --window-ms 100 --loss-db 6 --audio-out mono.wav
python python/stemcontract.py drums.wav bass.wav --rate 48000 --channels 2 --require-active --expect drums.wav --expect bass.wav
python python/renderdelta.py A.wav B.wav --offset-frames 12 --audio-out residual.wav
python python/drift_audio.py cueclock song.wav --bpm 123 --every-bars 8
```

The Python ZIP places the entry scripts and shared engine in the same folder. Run `python loopbudget.py ...` there. Keep `drift_audio.py` alongside every entry script. The files under `python/` named `drift-audio.sh`, `drift-audio.ps1`, and `drift-audio.cmd` are launchers for the Python engine; they are separate from the independent tools under top-level `bash/` and `powershell/`.

```sh
bash python/drift-audio.sh loopbudget loop.wav --bpm 127
```

```powershell
.\python\drift-audio.ps1 loopbudget loop.wav --bpm 127
```

```bat
python\drift-audio.cmd loopbudget loop.wav --bpm 127
```

## Run JavaScript

Node 20+; no package install. These are native JavaScript ports, and the browser uses the same engine.

```sh
node site/js/loopbudget.mjs loop.wav --bpm 127 --bars 4
node site/js/renderdelta.mjs A.wav B.wav --window-ms 50 --output changes.json
node site/js/cli.mjs gainbudget mix.wav --gain-db 2 --ceiling-db -1 --audio-out gained.wav
```

The JavaScript ZIP places all modules in one folder. Keep `engine.mjs` and `cli.mjs` alongside the ten entry modules.

## Inputs and outputs

The original Python/JavaScript/browser engine supports little-endian RIFF WAV PCM 8/16/24/32-bit or IEEE float 32/64-bit, 1–32 channels, 1–384000 Hz, maximum 64 MiB per file. CLI inputs are limited to 128 MiB combined. Browser uploads are also limited to 64 MiB total. MP3, FLAC and compressed WAV are rejected explicitly by that engine. Extensible PCM/float WAV is supported when valid bits equal container bits.

The shell-native tools accept formats that the installed FFmpeg build can decode. Their findings are evidence to inspect, not proof of corruption, mastering error or encoding provenance. `transcodeaudit` explicitly cannot prove lossy-to-lossless history, and correlation tools cannot determine the artistic intent behind stereo phase relationships.

## Verify and build

```sh
python -m unittest discover -s tests -v
python scripts/package.py
python -m http.server 8000 --directory site
```

For the shell-native tools, ensure FFmpeg/FFprobe are installed before running the suite. PowerShell parity tests run when `pwsh` is available. GitHub Actions exercises Bash on Ubuntu and PowerShell on Ubuntu and Windows in addition to the existing Python/Node/browser checks.

License: MIT. Research links describe alternatives and underlying methods; no third-party source code or audio is copied.
