# Audio Command Line Tools

Twenty-two beta-stage audio utilities from **Circuit Drift Labs**. Ten tools analyze individual WAV files in Python, Node, or the browser, four process complete folders and asset trees, **WinAudioForensics** captures and compares Windows audio state, and seven matched Bash/PowerShell tools provide FFmpeg/FFprobe-powered QC workflows.

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

## WinAudioForensics: native PowerShell

[WinAudioForensics](spec/winaudioforensics.md) is a Windows-only, PowerShell 7+ audio-state forensics CLI. It is read-only with respect to Windows audio configuration and uses CIM/PnP, signed-driver metadata, services, MMDevices registry state, Windows event logs, and documented Core Audio enumeration to answer a different question from the file-analysis tools: **what changed between a working audio state and a broken one?**

```powershell
.\powershell\WinAudioForensics.ps1 snapshot -Output working.json
.\powershell\WinAudioForensics.ps1 snapshot -IncludeEvents -EventHours 4 -Output broken.json
.\powershell\WinAudioForensics.ps1 diff -Before working.json -After broken.json -Output change.json
.\powershell\WinAudioForensics.ps1 doctor -Snapshot broken.json -Diff change.json
```

For intermittent problems:

```powershell
.\powershell\WinAudioForensics.ps1 watch -OutputDirectory .\audio-watch -IntervalSeconds 5
```

See the [usage guide](docs/WINAUDIOFORENSICS.md) and [research/demand check](docs/WINAUDIOFORENSICS_RESEARCH.md).

## Shell-native FFmpeg/FFprobe QC

The top-level `bash/` and matching PowerShell scripts are independent shell implementations. They do **not** invoke the repository's Python or JavaScript engines. FFmpeg/FFprobe perform decoding and measurements while the shell code handles discovery, aggregation, thresholds, JSON/text reports and exit semantics.

| Stage | Tool | Workflow | Main evidence / output |
|---|---|---|---|
| BETA | [stereotruth](spec/stereotruth.md) | Find stereo that behaves like dual-mono, strongly negative correlation, or channel imbalance | Correlation proportions, channel RMS and findings |
| BETA | [loudwalk](spec/loudwalk.md) | Turn verbose EBU R128 output into a useful internal-consistency timeline | Short-term LUFS, median, jumps and relative outliers |
| BETA | [formattruth](spec/formattruth.md) | Detect disagreements between extension, container, codec and stream metadata | Normalized FFprobe facts and consistency findings |
| BETA | [albumcontract](spec/albumcontract.md) | Infer or enforce a technical contract across a delivery folder | Rate/channel/sample-format contract and outliers |
| BETA | [phasewatch](spec/phasewatch.md) | Preserve timestamped stereo phase/correlation evidence | Correlation ledger and regime-change candidates |
| BETA | [batchsilence](spec/batchsilence.md) | Compare leading/trailing silence across a whole export set | Per-file silence seconds/ratios and optional policy findings |
| BETA | [transcodeaudit](spec/transcodeaudit.md) | Triage codec/container/bitrate/encoder combinations for review | Technical ledger and provenance-review heuristics |

Requirements: Bash 4.4+ for the Bash versions or PowerShell 7+ for the PowerShell versions, plus `ffmpeg` and `ffprobe` on `PATH`.

Ubuntu/Debian:

```sh
sudo apt update && sudo apt install ffmpeg
bash bash/stereotruth.sh mix.wav --json
bash bash/albumcontract.sh exports --recursive --expected-rate 48000 --expected-channels 2 --json
bash bash/batchsilence.sh exports --max-leading 1.0 --max-trailing 2.0 --json
```

Windows PowerShell:

```powershell
winget install Gyan.FFmpeg
./powershell/stereotruth.ps1 mix.wav -Json
./powershell/loudwalk.ps1 master.wav -JumpDb 4 -DeviationDb 7 -Json
./powershell/batchsilence.ps1 exports -MaxLeading 1.0 -MaxTrailing 2.0 -Json
```

Shell-native exit codes are **0** = completed without policy findings, **1** = completed with review findings, **2** = invalid arguments/dependency/input/analysis/report failure. Source audio is read-only. Findings are evidence to inspect rather than automatic claims of corruption, mastering error or encoding history.

## gapkit: 17 workflow-gap tools in 12 languages

[gapkit/](gapkit/README.md) holds 17 standalone tools for jobs that have no free command-line tool. They are written as Bash pipelines and in Tcl, Lua, GNU awk, Windows batch, PHP, Node.js, Perl, JRuby, VBScript, x86-64 assembly and ARM64 assembly. Examples include an in-terminal waveform, a stem-vs-master null test, cross-format duplicate detection, auto loop points written to the `smpl` chunk, pure-PHP waveform peaks and BPM detection, crash-damaged WAV header repair, and raw-PCM-to-WAV for the Raspberry Pi. Run `bash gapkit/test.sh` to check them all.

## Install Python tools

Python 3.10+ and NumPy:

```sh
python -m pip install -r requirements.txt
```

The original ten Python entry points use `python/drift_audio.py`. The four batch tools use `python/batch_audio.py`. The launcher files under `python/` remain wrappers around the Python engine; they are separate from the independent top-level `bash/` and `powershell/` QC tools.

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

## JavaScript and browser tools

The original ten tools also have native JavaScript ports under `site/js/`, and the GitHub Pages workbench uses that engine locally in the browser.

```sh
node site/js/loopbudget.mjs loop.wav --bpm 127 --bars 4
node site/js/renderdelta.mjs A.wav B.wav --window-ms 50 --output changes.json
node site/js/cli.mjs gainbudget mix.wav --gain-db 2 --ceiling-db -1 --audio-out gained.wav
```

The four folder-scale batch tools, seven shell-native QC tools, and WinAudioForensics are featured on Pages but do not execute in the browser.

## Formats and safety

The original ten tools support little-endian RIFF WAV PCM 8/16/24/32-bit and IEEE float 32/64-bit, 1–32 channels, 1–384000 Hz, with the documented limits in [COMMON](spec/COMMON.md). The four Python batch tools currently support uncompressed PCM WAV 8/16/24/32-bit and write transformed audio as 16-bit PCM WAV. The shell-native QC tools accept audio formats that the installed FFmpeg build can decode.

Measurements and findings are evidence to inspect, not automatic diagnoses. `transcodeaudit` cannot prove lossy-to-lossless history. Correlation does not prove a wiring fault or mastering error. WinAudioForensics reports state change/correlation rather than claiming causality.

## Downloads

`scripts/package.py` builds reproducible bundles for the Python tools, JavaScript tools, WinAudioForensics, Bash QC tools, and PowerShell QC tools:

- `cdl-audio-python.zip`
- `cdl-audio-javascript.zip`
- `cdl-winaudioforensics-powershell.zip`
- `cdl-audio-bash.zip`
- `cdl-audio-powershell.zip`

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

GitHub Actions runs the Python/Node suite across Linux, Windows and macOS, WinAudioForensics tests and a live Windows smoke test, Bash shell-native regressions on Ubuntu, native PowerShell QC tests on Ubuntu and Windows, cross-shell parity checks where both shells are available, packaging checks, and browser workbench tests before Pages deployment.

License: MIT. Research links document overlap and alternatives; no third-party source code or audio is copied.
