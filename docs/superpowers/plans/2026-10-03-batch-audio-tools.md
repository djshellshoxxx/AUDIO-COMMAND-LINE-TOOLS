# Batch Audio Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four tested folder-scale batch audio utilities and expose them in the repository/site with universal beta labeling.

**Architecture:** Add one shared Python engine (`python/batch_audio.py`) plus four thin entry points. Keep all source trees immutable by default; optional transforms write to separate output trees. Reuse NumPy only, keeping deployment aligned with the current repo dependency model.

**Tech Stack:** Python 3.10+, NumPy, stdlib `wave`, `argparse`, `hashlib`, `csv`, unittest, GitHub Pages static HTML/JSON.

**Spec:** `docs/superpowers/specs/2026-10-03-batch-audio-tools-design.md`

## Global Constraints

- All tools are BETA.
- No in-place source modification.
- Recursive WAV scanning; `.wav` extension case-insensitive.
- PCM WAV 8/16/24/32-bit input; 16-bit PCM transformed output.
- JSON reports; optional CSV for row-oriented results.
- Deterministic ordering and exit code 2 on input/I/O failure.

## Review Focus

- Duplicate-content rename ambiguity must be deterministic.
- Phase correction must preserve source files and require matching sample rates.
- Output collisions must fail unless `--overwrite` is explicit.
- Files that never cross onset threshold must remain intact.
- Repairs must affect only output copies and only flagged edge files.

---

### Task 1: Regression tests

**Files:**
- Create: `tests/test_batch_tools.py`

**Interfaces:**
- Consumes: public functions in `python/batch_audio.py` once implemented.
- Produces: regression contract for all four tools and shared scanning/output safety.

- [ ] Write synthetic WAV tests for onset/preroll, phase delay/polarity, pack classifications/duplicates, edge repair, recursive scan, overwrite safety, and source immutability.
- [ ] Run tests and verify they fail because `batch_audio` does not exist.

### Task 2: Shared batch engine and entry points

**Files:**
- Create: `python/batch_audio.py`
- Create: `python/onsetpack.py`
- Create: `python/phasebatch.py`
- Create: `python/packdelta.py`
- Create: `python/edgeguard.py`

**Interfaces:**
- Produces: `scan_wavs`, `read_wav`, `write_wav`, `analyze_onset`, `onsetpack`, `compare_phase`, `phasebatch`, `diff_packs`, `analyze_edges`, `repair_edges`, `edgeguard`, and CLI `main`/`main_for`.

- [ ] Implement minimal behavior needed by the failing tests.
- [ ] Run `python -m unittest tests.test_batch_tools -v` and verify green.
- [ ] Run syntax/help smoke tests for all four entry points.

### Task 3: Specs and public documentation

**Files:**
- Create: `spec/onsetpack.md`, `spec/phasebatch.md`, `spec/packdelta.md`, `spec/edgeguard.md`
- Modify: `README.md`
- Modify: `site/catalog.json`
- Modify: `site/index.html`

**Interfaces:**
- Consumes: shipped CLI flags and limitations.
- Produces: user-facing install/usage documentation with BETA labels on all tools.

- [ ] Document each command, examples, limits, and output behavior.
- [ ] Mark all legacy catalog entries and all README tool rows BETA.
- [ ] Add a Pages batch-tools section linking specs/source.

### Task 4: Packaging and audit

**Files:**
- Modify as needed: `scripts/package.py`, `docs/AUDIT.md`, tests discovered during audit.

**Interfaces:**
- Consumes: final tool set and current packaging/test conventions.
- Produces: downloadable package inclusion and audit evidence.

- [ ] Inspect packaging logic and include new Python scripts/specs.
- [ ] Audit advertised flags against parser wiring and specs.
- [ ] Audit path safety, deterministic output, edge cases, and syntax.
- [ ] Add regression tests for every reproduced defect, fix, and rerun the complete available suite.
