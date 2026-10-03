# Audio Command Line Tools

Ten focused audio utilities from **Circuit Drift Labs**. Run them in Python, Node, or the browser. Every tool includes a spec with pseudocode, JSON reports, adjustable flags, and synthetic regression tests.

**[Open the browser workbench](https://djshellshoxxx.github.io/AUDIO-COMMAND-LINE-TOOLS/)** · [Circuit Drift Labs](https://djshellshoxxx.github.io/circuitdriftlabs/) · [Research and existing alternatives](docs/RESEARCH.md) · [Program audit](docs/AUDIT.md)

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

The Python ZIP places the entry scripts and shared engine in the same folder. Run `python loopbudget.py ...` there. Keep `drift_audio.py` alongside every entry script. Bash, PowerShell, and batch files are **launchers**, not independent DSP ports:

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

Supported: little-endian RIFF WAV PCM 8/16/24/32-bit or IEEE float 32/64-bit, 1–32 channels, 1–384000 Hz, maximum 64 MiB per file. CLI inputs are limited to 128 MiB combined. Browser uploads are also limited to 64 MiB total. MP3, FLAC and compressed WAV are rejected explicitly. Extensible PCM/float WAV is supported when valid bits equal container bits. Convert to ordinary PCM WAV externally, for example with FFmpeg:

```sh
ffmpeg -i input.flac -c:a pcm_s24le input.wav
```

Reports are JSON on stdout unless `--output` is given. Each script supports `--help` with flag descriptions and defaults. Windowed analyses and event reports are capped at 100000 windows/entries; increase window/run/gap sizes or split the input if needed. Timeline ends are exclusive. Decibel silence floor is -240 dB. `--audio-out` is supported by tailbudget, monoledger, dcjourney, gainbudget, and renderdelta. Exports are 16-bit PCM with original sample rate, without metadata or dithering. Original files cannot be overwritten, even with `--overwrite`.

Measurements are sample peaks and RMS, not true peaks or LUFS. Gap and rail events are evidence to inspect, not proof of a recording fault. Renderdelta uses a user-supplied offset and reports only overlapping samples plus unmatched frame counts; it does not automatically align or resample. DCjourney removes global means only when exporting.

Exit codes: **0** finished; **1** stem contract failed; **2** input, flag, or I/O error. Other tools leave threshold decisions to the user. Above-full-scale audio exports fail instead of clipping. Gain exports additionally require the requested ceiling to be met, including after PCM rounding. Very low ceilings below one PCM step can yield silence.

## Verify and build

```sh
python -m unittest discover -s tests -v
python scripts/package.py
python -m http.server 8000 --directory site
```

Then open `http://localhost:8000`. Serve over HTTP(S); opening `index.html` as a local file will block ES modules/workers. `tests/browser.cjs` tests all ten browser flows with Playwright after starting the server and installing Playwright/Chromium. GitHub Actions runs Python/Node parity tests on Linux, Windows and macOS, then deploys the site through GitHub Pages.

License: MIT. Research links describe alternatives and underlying methods; no third-party source code or audio is copied.
