# Audio Command Line Tools

Fifteen beta-stage audio utilities from **Circuit Drift Labs**. Ten tools analyze individual WAV files in Python, Node, or the browser, four process complete folders and asset trees, and **WinAudioForensics** is a Windows-native PowerShell troubleshooting tool for capturing and comparing system audio state.

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

The batch tools are aimed at operations that become tedious or error-prone when repeated over hundreds or thousands of files. They are deliberately report-first: analysis is read-only and transformed audio is written to a different output tree.

## WinAudioForensics: native PowerShell

[WinAudioForensics](spec/winaudioforensics.md) is a Windows-only, PowerShell 7+ audio-state forensics CLI. It is read-only with respect to Windows audio configuration and uses CIM/PnP, signed-driver metadata, services, MMDevices registry state, Windows event logs, and documented Core Audio enumeration to answer a different question from the WAV tools: **what changed between a working audio state and a broken one?**

```powershell
.\powershell\WinAudioForensics.ps1 snapshot -Output working.json
# reproduce an audio-routing/device problem
.\powershell\WinAudioForensics.ps1 snapshot -IncludeEvents -EventHours 4 -Output broken.json
.\powershell\WinAudioForensics.ps1 diff -Before working.json -After broken.json -Output change.json
.\powershell\WinAudioForensics.ps1 doctor -Snapshot broken.json -Diff change.json
```

For intermittent problems:

```powershell
.\powershell\WinAudioForensics.ps1 watch -OutputDirectory .\audio-watch -IntervalSeconds 5
```

See the [usage guide](docs/WINAUDIOFORENSICS.md) and [research/demand check](docs/WINAUDIOFORENSICS_RESEARCH.md).

## Install

Python 3.10+ and NumPy for the Python audio tools:

```sh
python -m pip install -r requirements.txt
```

The original ten Python entry points use the shared `python/drift_audio.py` engine. The four batch tools use `python/batch_audio.py`. WinAudioForensics has no external PowerShell module dependency.

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
python python/drift_audio.py cueclock song.wav --bpm 123 --every-bars 8
```

Bash, PowerShell, and batch files in `python/` are launchers for the original shared Python engine, not independent DSP ports.

## JavaScript and browser tools

The original ten tools also have native JavaScript ports under `site/js/`, and the GitHub Pages workbench uses that engine locally in the browser.

```sh
node site/js/loopbudget.mjs loop.wav --bpm 127 --bars 4
node site/js/renderdelta.mjs A.wav B.wav --window-ms 50 --output changes.json
node site/js/cli.mjs gainbudget mix.wav --gain-db 2 --ceiling-db -1 --audio-out gained.wav
```

The four folder-scale batch tools and WinAudioForensics are featured on Pages but do not execute in the browser.

## Formats and safety

The original ten tools support little-endian RIFF WAV PCM 8/16/24/32-bit and IEEE float 32/64-bit, 1–32 channels, 1–384000 Hz, with the documented size limits in [COMMON](spec/COMMON.md). The batch tools currently support uncompressed PCM WAV 8/16/24/32-bit and write transformed audio as 16-bit PCM WAV.

MP3, FLAC, and compressed WAV are rejected by the native audio engines. Convert externally when needed, for example:

```sh
ffmpeg -i input.flac -c:a pcm_s24le input.wav
```

Measurements and WinAudioForensics findings are evidence to inspect, not automatic diagnoses. WinAudioForensics reports correlation/state change rather than claiming causality.

## Verify and build

```sh
python -m unittest discover -s tests -v
python scripts/package.py
python -m http.server 8000 --directory site
```

On Windows with PowerShell 7+:

```powershell
.\tests\winaudioforensics.tests.ps1
```

GitHub Actions runs the Python/Node suite across Linux, Windows, and macOS, WinAudioForensics tests and a live snapshot smoke test on Windows, packaging checks, and browser workbench tests before Pages deployment.

License: MIT. Research links document overlap and alternatives; no third-party source code or audio is copied.
