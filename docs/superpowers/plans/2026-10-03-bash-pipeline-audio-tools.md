# Bash Pipeline Audio Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement six Beta Bash-native audio QC/forensic tools that compose cleanly in Unix pipelines, publish them in the repository/site, and finish with a full spec/code/test/security/performance audit.

**Architecture:** Shared Bash libraries own dependency checks, safe temp/output handling, FFprobe metadata, canonical PCM decoding, numeric validation, TSV/JSONL emission, and cleanup. Each tool remains a focused entrypoint with tool-specific analysis and thresholds. Python is used only by the existing unittest harness to generate deterministic FFmpeg fixtures and drive integration tests; no Bash runtime invokes Python/Node.

**Tech Stack:** Bash 4.4+, FFmpeg, FFprobe, awk/sed/sort/coreutils, Python 3 unittest test harness, GitHub Actions, static GitHub Pages.

**Spec:** `docs/superpowers/specs/2026-10-03-bash-pipeline-audio-tools-design.md`

## Global Constraints

- Bash 4.4+.
- FFmpeg and FFprobe are required runtime dependencies.
- Runtime may use standard Unix/POSIX/GNU tools listed in the spec, but no Python, Node, Perl, Ruby, jq, or compiled helper dependency.
- Inputs are never modified; temporary PCM is cleaned on success/failure/interrupt unless `--keep-temp` is explicitly used.
- `LC_ALL=C`; stdout is report data only, diagnostics are stderr only.
- Every tool supports `--help`, `--version`, `--format text|tsv|jsonl`, `--output`, `--quiet`, `--keep-temp`; TSV also supports `--no-header`.
- Exit codes: 0 clean analysis, 1 review finding(s), 2 usage/dependency/input/analysis/output error, 130 interrupted after cleanup.
- JSONL does not require jq and emits one complete object per line; TSV has stable columns and escaped tabs/newlines.
- All new tools are Beta; novelty wording must remain evidence-based rather than claiming universal uniqueness.
- Existing Python/JavaScript/browser behavior remains unchanged except documentation/site/package integration.

## Review Focus

- Filenames containing spaces, tabs/newlines, Unicode, quotes, glob characters, and a leading `-` must not be split, interpreted as options, or injected into subprocesses.
- Silent/near-silent input must not cause divide-by-zero, NaN JSON, false phase/transient/band findings, or bogus medians.
- Very short files and final partial windows/blocks must have deterministic boundary handling and must not read past decoded PCM.
- Report output failures and SIGINT must remove temporary/partial files while preserving the intended exit code.
- Large inputs must respect decoded-size/event limits and avoid quadratic algorithms, especially repeated-block matching.

---

### Task 1: Shared Bash runtime and harness

**Files:**
- Create: `bash/lib/audio-common.sh`
- Create: `bash/lib/output.sh`
- Create: `bash/lib/pcm.sh`
- Create: `tests/test_bash_pipeline_tools.py`

**Interfaces:**
- Produces: `die`, dependency/version probes, strict numeric validators, `probe_audio`, temp-dir/trap lifecycle, deterministic file collection, atomic report writer, TSV/JSON escaping/emission, canonical `s16le`/`f32le` decode helpers, frame/byte/time conversion helpers.
- Consumes: Bash 4.4+, `ffmpeg`, `ffprobe`, standard shell utilities.

- [ ] **Step 1: Write failing shared-runtime tests** for `--help` without input, missing dependency, paths with spaces/leading dash, TSV/JSON escaping, atomic output failure, temp cleanup, `LC_ALL=C`, and source checksum/mtime preservation.
- [ ] **Step 2: Run the focused suite** with `python -m unittest tests.test_bash_pipeline_tools -v`; expected result is failure because the Bash runtime/entrypoints do not exist.
- [ ] **Step 3: Implement shared libraries** with quoted arrays, no `eval`, safe `--` boundaries, trap-preserved exit status, and explicit JSON finite-number handling.
- [ ] **Step 4: Run focused tests and syntax checks**: `bash -n bash/lib/*.sh`; expected PASS.
- [ ] **Step 5: Commit** shared runtime + harness.

### Task 2: `edgeguard.sh`

**Files:**
- Create: `bash/edgeguard.sh`
- Create: `spec/edgeguard.md`
- Test: `tests/test_bash_pipeline_tools.py`

**Interfaces:**
- Consumes: shared runtime; one or more FFmpeg-decodable files.
- Produces: boundary metrics/events `active_at_start`, `active_at_end`, `start_discontinuity`, `end_discontinuity`, `no_start_fade_evidence`, `no_end_fade_evidence`, `possible_truncated_start`, `possible_truncated_end`.

- [ ] **Step 1: Add failing fixtures/tests** for hard start/end, clean 100 ms fades, leading/trailing silence, natural zero-crossing transient, short file, and exact default thresholds from the spec.
- [ ] **Step 2: Run edgeguard-only tests** and verify RED.
- [ ] **Step 3: Implement edgeguard** using 100 ms boundary windows, 10 ms envelope subdivisions, -60 dBFS activity, -24 dBFS review RMS, 0.15 discontinuity, and combination-only `possible_truncated_*` rules.
- [ ] **Step 4: Run focused tests + `bash -n bash/edgeguard.sh`**; expected PASS.
- [ ] **Step 5: Commit** tool/spec/tests.

### Task 3: `subphase.sh`

**Files:**
- Create: `bash/subphase.sh`
- Create: `spec/subphase.md`
- Test: `tests/test_bash_pipeline_tools.py`

**Interfaces:**
- Consumes: stereo decoded low-pass float PCM from shared helpers.
- Produces: active-window correlation/balance ledger and merged `weak_sub_correlation`, `negative_sub_correlation`, `critical_sub_correlation`, `sub_balance_imbalance`, `sub_phase_regime_change` events.

- [ ] **Step 1: Add failing tests** for in-phase/inverted 60 Hz, mono sub with unrelated highs, inverted sub with mono highs, 4+ dB low-band imbalance, mono reject/`--allow-mono`, and near-silence exclusion.
- [ ] **Step 2: Run subphase-only tests** and verify RED.
- [ ] **Step 3: Implement subphase** with 120 Hz crossover, 250 ms windows, -55 dBFS activity, +0.20/0.00/-0.50 thresholds, 500 ms minimum run, 4 dB imbalance default.
- [ ] **Step 4: Verify focused tests, JSONL finite values, and syntax**; expected PASS.
- [ ] **Step 5: Commit** tool/spec/tests.

### Task 4: `banddrift.sh`

**Files:**
- Create: `bash/banddrift.sh`
- Create: `spec/banddrift.md`
- Test: `tests/test_bash_pipeline_tools.py`

**Interfaces:**
- Consumes: FFmpeg-filtered per-band measurements and shared emitters.
- Produces: per-window relative band shares, medians/deviations, merged `band_share_high`, `band_share_low`, `broad_tonal_shift` events.

- [ ] **Step 1: Add failing tests** for 60 Hz, 500 Hz, 3 kHz, 10 kHz sequential sections; stable broadband control; repeated `--band`; overlap/invalid-edge rejection; final partial window.
- [ ] **Step 2: Run banddrift-only tests** and verify RED.
- [ ] **Step 3: Implement banddrift** with default five non-overlapping bands, 1 s windows, -60 dBFS active threshold, 8 percentage-point deviation, two-window minimum run, deterministic median calculation.
- [ ] **Step 4: Verify focused tests + syntax**; expected PASS.
- [ ] **Step 5: Commit** tool/spec/tests.

### Task 5: `repeataudit.sh`

**Files:**
- Create: `bash/repeataudit.sh`
- Create: `spec/repeataudit.md`
- Test: `tests/test_bash_pipeline_tools.py`

**Interfaces:**
- Consumes: frame-aligned canonical `s16le` PCM and SHA-256 command abstraction.
- Produces: verified repeated-range events `adjacent_exact_repeat`, `nonadjacent_exact_repeat`, `long_exact_repeat`.

- [ ] **Step 1: Add failing tests** for normal varying audio, adjacent repeat, non-adjacent repeat, silence-only control, low-level repeated block, partial final block, hash fallback, decoded-size guard.
- [ ] **Step 2: Run repeataudit-only tests** and verify RED.
- [ ] **Step 3: Implement repeataudit** with 100 ms blocks, 300/500 ms thresholds, -70 dBFS silence exclusion, 4 GiB guard, hash grouping via sort/awk, byte verification of hash candidates, and no O(n²) pairwise scan.
- [ ] **Step 4: Verify focused tests and a performance assertion** that candidate comparisons scale with duplicate groups rather than all-pairs; expected PASS.
- [ ] **Step 5: Commit** tool/spec/tests.

### Task 6: `samplefreeze.sh`

**Files:**
- Create: `bash/samplefreeze.sh`
- Create: `spec/samplefreeze.md`
- Test: `tests/test_bash_pipeline_tools.py`

**Interfaces:**
- Consumes: channel-aware PCM stream.
- Produces: `exact_sample_freeze`, `near_sample_freeze`, `zero_flatline`, `multichannel_freeze` ranges with channel metadata.

- [ ] **Step 1: Add failing tests** for non-zero constant segment, digital zero segment, slowly varying near-flat segment, normal sine, one-frozen-channel stereo, channel selector, `--include-zero` behavior.
- [ ] **Step 2: Run samplefreeze-only tests** and verify RED.
- [ ] **Step 3: Implement samplefreeze** with 20 ms default minimum, -80 dBFS non-zero floor, exact mode default, optional absolute delta tolerance, per-channel runs and multichannel merge.
- [ ] **Step 4: Verify focused tests + syntax**; expected PASS.
- [ ] **Step 5: Commit** tool/spec/tests.

### Task 7: `transientledger.sh`

**Files:**
- Create: `bash/transientledger.sh`
- Create: `spec/transientledger.md`
- Test: `tests/test_bash_pipeline_tools.py`

**Interfaces:**
- Consumes: peak/RMS/envelope measurements.
- Produces: per-window crest/density metrics and `transient_density_low`, `transient_density_high`, `crest_factor_low`, `crest_factor_high`, `transient_regime_change` events.

- [ ] **Step 1: Add failing tests** for impulse train, sustained sine, noise bursts, alternating dense/sustained regions, near-silent control, and short final window.
- [ ] **Step 2: Run transientledger-only tests** and verify RED.
- [ ] **Step 3: Implement transientledger** with 2 s analysis windows, 10 ms envelope, +6 dB rise, 30 ms minimum spacing, -60 dBFS active threshold, 60% density deviation, 6 dB crest deviation.
- [ ] **Step 4: Verify focused tests + syntax**; assert relative regimes/timestamps rather than brittle exact transient counts.
- [ ] **Step 5: Commit** tool/spec/tests.

### Task 8: Full CLI/output contract hardening

**Files:**
- Modify: `bash/lib/audio-common.sh`
- Modify: `bash/lib/output.sh`
- Modify: `bash/lib/pcm.sh`
- Modify: `tests/test_bash_pipeline_tools.py`

**Interfaces:**
- Consumes: all six entrypoints.
- Produces: consistent shared CLI/output/error behavior across every tool.

- [ ] **Step 1: Add parameterized failing tests** for every tool covering `--version`, invalid/missing values, nonexistent file, leading-dash filename after `--`, text/TSV/JSONL, `--no-header`, atomic `--output`, quiet mode, stderr/stdout separation, temp cleanup, SIGINT where practical, and deterministic multi-file ordering.
- [ ] **Step 2: Run shared contract tests** and verify any gaps fail.
- [ ] **Step 3: Fix only shared/runtime or entrypoint inconsistencies** needed to satisfy the contract.
- [ ] **Step 4: Run `python -m unittest tests.test_bash_pipeline_tools -v`, `bash -n bash/*.sh bash/lib/*.sh`, and `shellcheck bash/*.sh bash/lib/*.sh` when available**; expected PASS or documented justified shellcheck exceptions only.
- [ ] **Step 5: Commit** contract hardening.

### Task 9: Packaging, README, research wording, and GitHub Pages

**Files:**
- Modify: `README.md`
- Modify: `docs/RESEARCH.md`
- Modify: `scripts/package.py`
- Modify: `site/index.html`
- Modify: `site/style.css`
- Create: `site/bash-pipeline-tools.json` or equivalent static data if useful
- Modify/Test: `tests/browser.cjs`

**Interfaces:**
- Consumes: six completed Bash tools/specs.
- Produces: a Bash download bundle, a distinct site collection with Beta cards, raw source/spec links, standalone/pipeline examples, dependencies, event types, and evidence-based novelty copy.

- [ ] **Step 1: Add failing packaging/browser/static assertions** that all six tools/specs are packaged and all six cards/links/examples/Beta labels render without disturbing the existing ten-tool browser workbench.
- [ ] **Step 2: Run packaging/browser checks** and verify RED before integration.
- [ ] **Step 3: Extend `scripts/package.py`** with deterministic `cdl-audio-bash.zip` including `bash/`, relevant specs, README, LICENSE.
- [ ] **Step 4: Update README/research/site** with installation, FFmpeg dependency, the six-tool table, composable pipeline examples, and wording that research did not identify a well-established standalone command with the same narrow workflow.
- [ ] **Step 5: Run packaging and browser/static tests**; expected PASS.
- [ ] **Step 6: Commit** docs/site/package integration.

### Task 10: CI integration

**Files:**
- Modify: `.github/workflows/verify-and-publish.yml`

**Interfaces:**
- Produces: Ubuntu Bash verification while preserving existing Python/Node/browser matrix.

- [ ] **Step 1: Add/adjust CI assertions** in the repository tests if needed so missing Bash suite execution is detectable.
- [ ] **Step 2: Update workflow** to verify/install FFmpeg as needed, run `bash -n`, run shellcheck when available, and run `python -m unittest tests.test_bash_pipeline_tools -v` on Ubuntu before publish dependencies complete.
- [ ] **Step 3: Validate YAML and inspect workflow paths/commands** against actual repo paths.
- [ ] **Step 4: Commit** CI integration.

### Task 11: Full implementation audit and fixes

**Files:**
- Create: `docs/BASH_PIPELINE_AUDIT.md`
- Modify as needed: `bash/**/*.sh`, `spec/*.md`, `README.md`, `site/*`, `tests/test_bash_pipeline_tools.py`, workflow/package files.

**Interfaces:**
- Consumes: entire implementation and approved spec.
- Produces: evidence-backed audit record and any regression tests/fixes discovered during audit.

- [ ] **Step 1: Spec-to-code matrix**: enumerate every approved requirement and mark implemented/tested/documented/deferred; no silent omission.
- [ ] **Step 2: Shell correctness review** for quoting, splitting, globbing, injection, traps, `set -e`, pipeline statuses, locales, arithmetic/byte offsets, leading-dash/whitespace filenames, and atomic reports. Every discovered bug first gets a failing regression test, then a fix.
- [ ] **Step 3: Algorithm review** against hand-computable synthetic fixtures for dB conversion, correlation, medians, band shares, transient density, byte/frame/time conversion, block/run merging, inactive windows, and partial final windows. Add regression tests for every mismatch.
- [ ] **Step 4: False-positive controls** for all six tools and document expected borderline behavior.
- [ ] **Step 5: Performance audit** on representative synthetic files; verify no accidental quadratic loop and specifically inspect repeataudit grouping behavior.
- [ ] **Step 6: Output/dependency audit**: parse all TSV/JSONL outputs, test stdout/stderr separation, exit codes, deterministic ordering, masked optional hash commands, and missing required dependency errors.
- [ ] **Step 7: Documentation/site/link audit**: every documented command must execute, every spec/raw link must exist, Beta labels must be present, and unsupported novelty claims must be absent.
- [ ] **Step 8: Run complete verification**: `python -m unittest discover -s tests -v`; `bash -n bash/*.sh bash/lib/*.sh`; shellcheck if available; `python scripts/package.py`; browser tests according to existing workflow.
- [ ] **Step 9: Write `docs/BASH_PIPELINE_AUDIT.md`** with date, commit tested, environment/tool versions, exact commands, test counts, failures discovered, fixes applied, known limitations, performance notes, and 16-item acceptance matrix.
- [ ] **Step 10: Re-run complete verification after the final audit fix**, then commit audit + final fixes.

## Self-review result

- Spec coverage: all six tools, shared runtime/output contracts, synthetic fixtures, CI, packaging/site, and mandatory 10-part post-build audit map to explicit tasks.
- Step scan: each task has a RED/GREEN verification cycle and a reviewer-sized deliverable; documentation-only changes are paired with packaging/browser assertions rather than artificial unit tests.
- Interface consistency: the common libraries are created before every analyzer; all later tasks consume those helpers rather than defining alternate output/temp conventions.
- Review Focus coverage: hostile filenames/task 1+8; silence/NaN/task 3+4+7+8; short/partial windows/tasks 2-7; cleanup/output/task 1+8; large/performance/task 5+11.
- Proportion: implementation details remain in the approved spec; this plan fixes file ownership, test checkpoints, defaults, and verification commands without transcribing the programs.