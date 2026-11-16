# User Guide

## Install

- Python tools: Python 3.10+ and NumPy: `python -m pip install -r requirements.txt`
- Shell tools: Bash with FFmpeg and FFprobe on the path
- WinAudioForensics and PowerShell QC: PowerShell 7+ on Windows
- Browser workbench: https://djshellshoxxx.github.io/AUDIO-COMMAND-LINE-TOOLS/ (or serve `site/` locally)

## Use

Each tool has a page in `spec/` and a row in the README tables (single-file, batch, shell-native QC).
Examples from the README:

```sh
python python/onsetpack.py ./samples --threshold-db -24 --preroll-ms 12 \
  --output-dir ./samples-onset --output onset-report.json --csv onset-report.csv
python python/packdelta.py ./pack-v1 ./pack-v2 --output pack-delta.json
```

## Formats and limits

The original ten tools read little-endian RIFF WAV PCM (8/16/24/32-bit) and IEEE float (32/64-bit),
1 to 32 channels, 1 to 384000 Hz (limits in `spec/COMMON.md`). The batch tools support a narrower set;
see the README "Formats and safety" section.

## Reading results

Measurements are evidence to inspect, not diagnoses. `transcodeaudit` cannot prove lossy-to-lossless
history, and correlation does not prove a wiring fault.
