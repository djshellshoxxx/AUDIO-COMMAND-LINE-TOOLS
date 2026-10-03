# Batch audio workflow gap research — October 2026

This review looked for folder-scale audio workflows where existing tools provide the underlying DSP primitives or DAW workflow, but a focused, scriptable batch command is still useful. It does **not** claim that no related software exists anywhere; the selection criterion is a practical CLI workflow gap rather than absolute novelty.

## 1. onsetpack

FFmpeg already provides `silencedetect` and `silenceremove`, which can detect and remove leading/trailing silence. Those tools answer a level/silence question. The selected gap is slightly different: for a sample library, standardize where the *first meaningful transient* lands relative to file start while keeping a user-selected amount of pre-roll. That makes hundreds of one-shots more consistent in samplers without forcing the transient to frame zero.

Reference: FFmpeg filter documentation, especially `silencedetect` and `silenceremove`: https://ffmpeg.org/ffmpeg-filters.html

## 2. phasebatch

Multi-microphone time/phase alignment is a well-established production need. Sound Radix Auto-Align 2 demonstrates clear demand and provides automatic time and spectral alignment inside supported DAWs, including multi-channel grouping. The gap targeted here is narrower: a transparent, report-first command-line batch tool for folders of synchronized WAV exports, with explicit integer delay/polarity measurements and optional corrected copies rather than a DAW plug-in/session workflow.

Reference: Sound Radix Auto-Align 2: https://www.soundradix.com/products/auto-align/

The beta implementation intentionally does less than Auto-Align: it performs integer-sample time-domain correlation and polarity correction only. It does not attempt spectral phase optimization, fractional delay, automatic grouping, or acoustic transfer-function correction.

## 3. packdelta

Duplicate tooling exists. The beets `duplicates` plug-in can identify duplicate music items and can delegate checksum generation to tools such as FFmpeg. Sample managers also increasingly include duplicate detection and synchronization. The missing workflow selected here is version-control-like reporting between *two complete audio asset trees*: unchanged, modified-at-the-same-path, added, removed, exact-content renamed files, and duplicate families in one deterministic report.

References:

- beets duplicates plug-in: https://beets.readthedocs.io/en/stable/plugins/duplicates.html
- beets Chromaprint search (useful for perceptual/recording similarity, a different problem): https://beets.readthedocs.io/en/stable/plugins/chroma.html

`packdelta` deliberately uses exact decoded-content identity rather than perceptual fingerprints. This makes it suitable for release/package auditing where an exact asset change matters.

## 4. edgeguard

Click/pop detection is also established. Essentia's `ClickDetector` detects impulsive noises inside audio using LPC prediction error and matched filtering. That is broader restoration/QC functionality. The selected batch gap is specifically *file-boundary risk* across sample packs: identify files that begin/end at a large nonzero value or steep boundary slope and optionally apply a bounded micro-fade to separate copies.

References:

- Essentia ClickDetector: https://essentia.upf.edu/reference/std_ClickDetector.html
- Essentia click/pop tutorial: https://essentia.upf.edu/tutorial_audioproblems_clickdetector.html

This tool does not replace an internal de-clicker. It only evaluates and optionally treats the start/end boundaries.

## Selection rationale

The existing repository already covers focused per-file measurements such as loop seams, tails, mono cancellation, local gaps, near-rail runs, DC movement, gain budget, stem contracts, cue grids, and render deltas. The new set therefore emphasizes operations whose value grows with **hundreds or thousands of files**:

1. make one-shot timing consistent (`onsetpack`),
2. inspect/correct synchronized recording sets (`phasebatch`),
3. compare asset-pack revisions (`packdelta`), and
4. audit/repair sample boundaries (`edgeguard`).

All four remain local/offline, emit machine-readable reports, avoid source modification, and use a small dependency footprint.