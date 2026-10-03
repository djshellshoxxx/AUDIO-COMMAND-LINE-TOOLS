# Batch Audio Tools Design

Date: 2026-10-03

## Goal

Add four folder-scale audio utilities to complement the existing single-file analysis tools: `onsetpack`, `phasebatch`, `packdelta`, and `edgeguard`. All tools are beta-stage utilities and must default to read-only analysis. Any transformed audio is written to a separate output tree and never modifies sources in place.

## Shared behavior

The reference implementation is Python 3.10+ with NumPy. Batch tools recursively scan WAV files, preserve relative paths in output trees, emit JSON reports, optionally emit CSV for row-oriented reports, use deterministic ordering, and return exit code 2 for invalid input or I/O failures. Existing files are not overwritten unless `--overwrite` is supplied.

Batch WAV input supports uncompressed PCM WAV at 8, 16, 24, or 32 bits. Output audio is 16-bit PCM WAV. Unsupported/compressed WAV data fails explicitly instead of being silently converted. Filenames are processed case-insensitively for the `.wav` extension.

## onsetpack

Purpose: standardize sample-library leading space around the actual transient rather than merely trimming silence.

For each WAV, find the first frame whose maximum absolute channel sample meets `--threshold-db`. Report onset frame/time and the calculated trim start. `--preroll-ms` keeps a configurable amount of existing audio before the transient. With `--output-dir`, write a copy beginning at the calculated trim point. Files with no threshold crossing remain untrimmed and are identified in the report.

## phasebatch

Purpose: batch-check synchronized multi-microphone or multi-channel exports for delay and polarity relationships.

The user supplies an input tree and `--reference` WAV inside that tree. Each other WAV is downmixed to mono for comparison against the reference. Search integer-sample offsets within `--max-shift-ms` and select the offset with greatest absolute normalized correlation. Report delay, correlation, and whether polarity is inverted. With `--correct --output-dir`, write length-matched copies shifted to align with the reference and polarity-inverted when required. No resampling is performed; sample rates must match.

## packdelta

Purpose: compare two revisions of an audio asset tree by decoded audio content rather than filenames alone.

Build deterministic inventories of both trees. Hash sample rate, channel count, and decoded sample values quantized to a stable 24-bit-equivalent integer domain. Report `unchanged`, `modified`, `added`, `removed`, `renamed`, and duplicate-content groups. A rename requires exact decoded-audio identity. When duplicate content makes rename pairing ambiguous, pair candidates deterministically using filename similarity followed by lexical order.

## edgeguard

Purpose: batch-audit sample-pack file boundaries for likely clicks caused by nonzero or steep start/end edges.

For each WAV, measure first/last sample peak magnitude and first/last sample-to-sample slope. Flag an edge when either exceeds `--threshold-db`. With `--repair --output-dir`, write only flagged files using a bounded linear fade of `--fade-ms` at each end. The repair does not attempt internal click restoration.

## Site and documentation

The README and GitHub Pages site must mark every existing and new tool as **BETA**. The site gains a batch-tools section describing all four commands and linking to their specs/source. Browser execution remains limited to the original ten local single-file tools; batch tools are presented as downloadable CLI workflows because browser directory permissions and large-tree processing vary by platform.

## Testing

Synthetic regression tests cover recursive scanning, onset/preroll calculations, delay and polarity detection, pack diff classifications including duplicate ambiguity, edge detection/repair, CLI help, source immutability, output overwrite protection, and report determinism. After implementation, run a repository-wide audit against advertised flags/specs and correct defects found.