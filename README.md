# Audio Command Line Tools

Focused audio utilities from **Circuit Drift Labs**. The original ten tools run in Python, Node, or the browser. A second collection adds six **Beta Bash-native pipeline tools** built around FFmpeg/FFprobe and ordinary Unix utilities.

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

These are useful combinations of established audio techniques. Related tools already exist; the research does not establish that every workflow is unprecedented.

## Bash pipeline tools — Beta

These six programs are native Bash implementations. They do **not** call the repository's Python or JavaScript engine. Runtime dependencies are Bash 4.4+, FFmpeg, FFprobe, awk and ordinary Unix/coreutils commands. `jq` is optional for downstream processing only.

| Tool | Narrow workflow | Typical output |
|---|---|---|
| [edgeguard](spec/edgeguard.md) | Find hard starts/ends and possible truncated render boundaries | Boundary/fade review events |
| [subphase](spec/subphase.md) | Inspect stereo correlation and balance only below a chosen crossover | Time-coded low-band phase events |
| [banddrift](spec/banddrift.md) | Find tonal-balance sections that depart from the file's own median behavior | Relative band-share drift ledger |
| [repeataudit](spec/repeataudit.md) | Detect exact repeated decoded PCM blocks | Adjacent/non-adjacent repeat events |
| [samplefreeze](spec/samplefreeze.md) | Detect non-zero or near-flat frozen PCM sample runs | Channel-aware freeze ranges |
| [transientledger](spec/transientledger.md) | Compare transient density and crest factor across a file | Relative transient/crest regimes |

Research did not identify a **well-established standalone** command with the same narrow purpose for each of these composed workflows. That is not a claim that no comparable implementation exists anywhere.

All six share the same automation-friendly contract:

```text
--help
--version
--format text|tsv|jsonl
--output PATH
--no-header        # TSV
--quiet
--keep-temp
```

Exit `0` means clean analysis, `1` means one or more review events were emitted, and `2` means usage/dependency/input/analysis/output failure. Reports go to stdout unless `--output` is used; diagnostics go to stderr. Inputs are never modified.

Examples:

```bash
bash bash/edgeguard.sh render.wav --format jsonl
bash bash/subphase.sh mix.wav --crossover-hz 120 --format tsv
bash bash/banddrift.sh master.wav --window-ms 500 --format jsonl
bash bash/repeataudit.sh capture.wav --block-ms 100 --format jsonl
bash bash/samplefreeze.sh recording.wav --min-run-ms 20 --format tsv
bash bash/transientledger.sh drums.wav --window-ms 1000 --format jsonl
```

The main reason for Bash here is composition:

```bash
find renders -type f -name '*.wav' -print0 |
  xargs -0 -n1 bash bash/edgeguard.sh --format tsv --no-header |
  awk -F '\t' '$0 ~ /possible_truncated/'

bash bash/subphase.sh mix.wav --format tsv |
  awk -F '\t' '$0 ~ /negative_sub_correlation|critical_sub_correlation/'

bash bash/banddrift.sh master.wav --format tsv |
  sort -t $'\t' -k7,7

bash bash/repeataudit.sh capture.wav --format jsonl > repeats.jsonl
bash bash/samplefreeze.sh capture.wav --format jsonl > freezes.jsonl
cat repeats.jsonl freezes.jsonl | grep -v '"event":"summary"'
```

The generated download bundle is `site/downloads/cdl-audio-bash.zip` and includes the six entry scripts, shared Bash libraries, their specs, README and license.

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

The legacy `python/drift-audio.sh`, `.ps1`, and `.cmd` files are launchers for the Python engine. They are separate from the native programs under `bash/`.

## Run JavaScript

Node 20+; no package install. These are native JavaScript ports, and the browser workbench uses the same engine.

```sh
node site/js/loopbudget.mjs loop.wav --bpm 127 --bars 4
node site/js/renderdelta.mjs A.wav B.wav --window-ms 50 --output changes.json
node site/js/cli.mjs gainbudget mix.wav --gain-db 2 --ceiling-db -1 --audio-out gained.wav
```

## Inputs and outputs

The original Python/JavaScript family parses WAV directly: little-endian RIFF WAV PCM 8/16/24/32-bit or IEEE float 32/64-bit, 1–32 channels, 1–384000 Hz, maximum 64 MiB per file and 128 MiB combined CLI input. The browser limit is 64 MiB total.

The Bash pipeline family accepts formats FFmpeg can decode. Analysis is performed on temporary canonical PCM and the original file is never rewritten. Temporary files are deleted on normal success/failure/interrupt unless `--keep-temp` is explicitly selected.

The Bash heuristics intentionally report review evidence rather than asserting mastering errors, provenance, corruption causes or creative intent.

## Verify and build

```sh
python -m unittest discover -s tests -v
bash -n bash/*.sh bash/lib/*.sh
shellcheck -x -e SC1091 bash/*.sh bash/lib/*.sh
python scripts/package.py
python -m http.server 8000 --directory site
```

GitHub Actions tests the original Python/JavaScript family on Linux, Windows and macOS, runs the Bash/FFmpeg suite and ShellCheck on Ubuntu, exercises the browser workbench with Playwright, builds all bundles, and publishes GitHub Pages from `main` after required jobs pass.

License: MIT. Research links describe alternatives and underlying methods; no third-party source code or audio is copied.
