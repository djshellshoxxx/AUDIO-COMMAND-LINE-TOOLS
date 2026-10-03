# Audio Command Line Tools

Twenty-one focused audio utilities from **Circuit Drift Labs**. The original ten tools analyze individual WAV files in Python, Node, or the browser. Four Python batch tools process complete folders and asset trees. Seven additional **Beta shell-native QC tools** provide matched Bash and PowerShell workflows powered directly by FFmpeg/FFprobe.

> **BETA:** Every tool in this repository and on the GitHub Pages workbench is currently beta-stage software. Keep source audio backed up and review generated reports/outputs before using them in production workflows.

**[Open the browser workbench](https://djshellshoxxx.github.io/AUDIO-COMMAND-LINE-TOOLS/)** · [Circuit Drift Labs](https://djshellshoxxx.github.io/circuitdriftlabs/) · [Research and existing alternatives](docs/RESEARCH.md) · [Program audit](docs/AUDIT.md)

## Single-file and small-set tools

| Stage | Tool | What it does | Useful controls / output |
|---|---|---|---|
| BETA | [loopbudget](spec/loopbudget.md) | Loop seam and musical length audit | BPM, bars, meter; frame error and boundary metrics |
| BETA | [tailbudget](spec/tailbudget.md) | Budget and trim quiet tails | Activity threshold, kept padding; trimmed WAV |
| BETA | [monoledger](spec/monoledger.md) | Time-coded mono cancellation audit | Window size, loss threshold; mono preview WAV |
| BETA | [gapcontext](spec/gapcontext.md) | Quiet gap candidates with active flanks | Gap duration, flank RMS threshold; timestamp ledger |
| BETA | [railruns](spec/railruns.md) | Consecutive near-full-scale sample runs | Amplitude threshold, run length; channel event ledger |
| BETA | [dcjourney](spec/dcjourney.md) | Local DC offset history versus global offset | Windows, offset threshold; globally centered WAV |
| BETA | [gainbudget](spec/gainbudget.md) | Requested gain versus sample peak ceiling | Gain, ceiling; safe gain budget and optional WAV |
| BETA | [stemcontract](spec/stemcontract.md) | Structural export contract for stems | Required rate/channels/frames, expected names, activity |
| BETA | [cueclock](spec/cueclock.md) | Sample-rounded bar cue grid | BPM, meter, spacing, origin; cues and rounding errors |
| BETA | [renderdelta](spec/renderdelta.md) | Offset-aware render difference timeline | Sample offset, window, threshold; optional residual WAV |

## Batch-processing tools

| Stage | Tool | Batch workflow | Optional transformed output |
|---|---|---|---|
| BETA | [onsetpack](spec/onsetpack.md) | Recursively find the actual transient in one-shots/samples and standardize pre-roll | Trimmed copies in a separate output tree |
| BETA | [phasebatch](spec/phasebatch.md) | Compare a folder of synchronized recordings against a reference for delay/polarity | Integer-shifted, polarity-corrected copies |
| BETA | [packdelta](spec/packdelta.md) | Compare two audio asset trees by decoded content, including renames and duplicate families | Report only |
| BETA | [edgeguard](spec/edgeguard.md) | Audit start/end click risk across an entire sample tree | Short-fade repaired copies of flagged files |

The batch tools are report-first: analysis is read-only and transformed audio is written to a different output tree.

## Shell-native FFmpeg/FFprobe tools

The top-level `bash/` and `powershell/` directories contain independent implementations. They are not wrappers around the Python engine. FFmpeg/FFprobe perform decoding and measurement; the shell code handles deterministic discovery, aggregation, thresholds, reports and exit codes.

| Stage | Tool | Workflow gap | Main evidence / output |
|---|---|---|---|
| BETA | [stereotruth](spec/stereotruth.md) | Stereo files that may actually be dual-mono, inverted or imbalanced | Correlation proportions, per-channel RMS, review findings |
| BETA | [loudwalk](spec/loudwalk.md) | Raw EBU R128 logs are awkward for locating unusual sections | Short-term LUFS timeline, median, jumps and relative outliers |
| BETA | [formattruth](spec/formattruth.md) | Extensions, containers, codecs and stream metadata can disagree | Normalized FFprobe facts and consistency findings |
| BETA | [albumcontract](spec/albumcontract.md) | Accidental technical outliers inside a delivery folder | Dominant/expected rate, channels and sample format |
| BETA | [phasewatch](spec/phasewatch.md) | Whole-file correlation hides brief phase changes | Timestamped correlation ledger and regime-change candidates |
| BETA | [batchsilence](spec/batchsilence.md) | Export sets need comparative leading/trailing silence QC | Per-file silence seconds/ratios and optional limit findings |
| BETA | [transcodeaudit](spec/transcodeaudit.md) | Libraries need technical provenance triage without false certainty | Codec/container/bitrate/encoder ledger and review heuristics |

Requirements: Bash 4.4+ on Linux or PowerShell 7+, plus `ffmpeg` and `ffprobe` on `PATH`.

```sh
sudo apt update && sudo apt install ffmpeg
bash bash/stereotruth.sh mix.wav --json
bash bash/albumcontract.sh exports --recursive --expected-rate 48000 --expected-channels 2 --json
```

```powershell
winget install Gyan.FFmpeg
./powershell/stereotruth.ps1 mix.wav -Json
./powershell/batchsilence.ps1 exports -MaxLeading 1.0 -MaxTrailing 2.0 -Json
```

Shell-native exit codes are **0** = completed without policy findings, **1** = completed with review findings, **2** = invalid arguments/dependency/input/analysis/report failure. Source audio is read-only.

## Install Python tools

Python 3.10+ and NumPy:

```sh
python -m pip install -r requirements.txt
```

The original ten Python entry points use `python/drift_audio.py`. The four Python batch tools use `python/batch_audio.py`.

## Batch examples

```sh
python python/onsetpack.py ./samples --threshold-db -24 --preroll-ms 12 \
  --output-dir ./samples-onset --output onset-report.json --csv onset-report.csv
python python/phasebatch.py ./multimic --reference kick-in.wav --max-shift-ms 8 \
  --correct --output-dir ./multimic-aligned --output phase-report.json
python python/packdelta.py ./pack-v1 ./pack-v2 --output pack-delta.json
python python/edgeguard.py ./oneshots --threshold-db -42 --repair --fade-ms 4 \
  --output-dir ./oneshots-edge-fixed --output edge-report.json --csv edge-report.csv
```

Use `--overwrite` only when you intentionally want existing generated output/report files replaced. Batch audio output directories are rejected if they are inside the input tree.

## Original Python tools

```sh
python python/loopbudget.py loop.wav --bpm 127 --bars 4 --output loop.json
python python/monoledger.py mix.wav --window-ms 100 --loss-db 6 --audio-out mono.wav
python python/stemcontract.py drums.wav bass.wav --rate 48000 --channels 2 --require-active --expect drums.wav --expect bass.wav
python python/renderdelta.py A.wav B.wav --offset-frames 12 --audio-out residual.wav
```

The Bash, PowerShell, and batch files inside `python/` remain launchers for the original Python engine. They are separate from the independent top-level `bash/` and `powershell/` tools.

## JavaScript and browser tools

The original ten tools also have native JavaScript ports under `site/js/`, and the GitHub Pages workbench uses that engine locally in the browser.

```sh
node site/js/loopbudget.mjs loop.wav --bpm 127 --bars 4
node site/js/renderdelta.mjs A.wav B.wav --window-ms 50 --output changes.json
```

## Formats and safety

The original ten tools support the WAV formats documented in [COMMON](spec/COMMON.md). The four Python batch tools currently support uncompressed PCM WAV 8/16/24/32-bit. The shell-native tools accept formats supported by the installed FFmpeg build.

Measurements and findings are evidence to inspect, not automatic diagnoses. `transcodeaudit` cannot prove lossy-to-lossless history. Correlation does not prove a wiring fault or mastering error. Source audio is protected from modification by the shell-native analysis tools.

## Verify and build

```sh
python -m unittest discover -s tests -v
python scripts/package.py
python -m http.server 8000 --directory site
```

GitHub Actions runs the Python/Node suite across Linux, Windows and macOS, browser workbench tests, Bash regression tests on Ubuntu, and PowerShell parity checks on Ubuntu and Windows before Pages deployment.

License: MIT. Research links document overlap and alternatives; no third-party source code or audio is copied.
