# Shell-native Audio QC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement seven Beta audio QC utilities as independent Bash and PowerShell programs using FFmpeg/FFprobe, with matching behavior, documentation, tests, CI coverage, and GitHub Pages integration.

**Architecture:** Each shell family gets shared dependency, argument/output, FFprobe, FFmpeg-analysis, and serialization helpers. Tool entrypoints remain small: they validate tool-specific flags, call shared measurement primitives, derive findings, and emit a normalized report. Python is used only for deterministic test-fixture generation and test orchestration; runtime tools never invoke Python or the repository's existing Python/JavaScript engines.

**Tech Stack:** Bash 4.4+, PowerShell 7+, FFmpeg, FFprobe, Python 3 unittest test harness, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-03-shell-native-audio-qc-design.md`

## Global Constraints

- FFmpeg and FFprobe are required runtime dependencies.
- Bash implementations require Bash 4.4+ and common Linux/POSIX utilities; JSON output must not require `jq`.
- PowerShell implementations require PowerShell 7+ and built-in PowerShell/.NET only, plus FFmpeg/FFprobe.
- Runtime scripts must not invoke Python or JavaScript.
- Input audio files are read-only and must never be modified.
- Exit code 0 means completed with no policy/threshold failures; 1 means completed with review findings; 2 means invalid arguments, dependency/input/FFmpeg/FFprobe/report-write failure.
- JSON reports include tool, version, generated_utc, inputs, dependency versions, effective options, measurements, findings, and status.
- Batch results use deterministic path ordering and support paths containing spaces.
- All seven new tools are labelled Beta.

## Review Focus

- Filenames containing spaces, quotes, brackets, Unicode, and leading dashes must be passed to FFmpeg/FFprobe without command injection or argument splitting.
- Silent or near-silent stereo windows must not produce false correlation/phase findings or division-by-zero failures.
- FFmpeg/FFprobe output varies by version/platform; parsers must tolerate absent optional fields and locale-independent numeric forms.
- Directory scans must be deterministic, must not recurse through unsupported entries accidentally, and must not overwrite a report located inside the scanned directory.
- Partial analysis failures in a batch must produce a clear error outcome rather than silently dropping files or inventing dominant/median values.

---

### Task 1: Shared Bash runtime

**Files:**
- Create: `bash/lib/common.sh`
- Create: `bash/lib/ffmpeg.sh`
- Create: `bash/lib/json.sh`
- Test: `tests/test_shell_native_tools.py`

**Interfaces:**
- Produces: dependency checks, safe temp-file lifecycle, error/exit helpers, deterministic file discovery, FFprobe JSON extraction, FFmpeg invocation helpers, locale forcing, JSON string/number/array/object serialization, report-output helper.
- Consumes: `ffmpeg`, `ffprobe`, Bash 4.4+.

- [ ] Write failing harness tests for dependency detection, safe paths, deterministic discovery, JSON escaping, report output, and no-input modification.
- [ ] Run the targeted tests and confirm failure because Bash helpers/entrypoints are absent.
- [ ] Implement the shared Bash helpers with no Python/jq runtime dependency.
- [ ] Run targeted helper tests and shell syntax checks (`bash -n`) until passing.
- [ ] Commit the shared Bash runtime and tests.

### Task 2: Shared PowerShell runtime

**Files:**
- Create: `powershell/lib/Common.ps1`
- Create: `powershell/lib/FFmpeg.ps1`
- Test: `tests/test_shell_native_tools.py`

**Interfaces:**
- Produces: PowerShell equivalents of Task 1 helpers using built-in JSON and .NET facilities.
- Consumes: `ffmpeg`, `ffprobe`, PowerShell 7+.

- [ ] Add failing parity tests for dependency detection, path handling, deterministic discovery, JSON serialization, and report output.
- [ ] Run the targeted tests and confirm failure because PowerShell helpers/entrypoints are absent.
- [ ] Implement the PowerShell shared helpers.
- [ ] Run targeted tests and PowerShell parser/smoke checks until passing.
- [ ] Commit the shared PowerShell runtime and tests.

### Task 3: `formattruth` and `transcodeaudit`

**Files:**
- Create: `bash/formattruth.sh`, `powershell/formattruth.ps1`
- Create: `bash/transcodeaudit.sh`, `powershell/transcodeaudit.ps1`
- Create: `spec/formattruth.md`, `spec/transcodeaudit.md`
- Test: `tests/test_shell_native_tools.py`

**Interfaces:**
- `formattruth`: consumes one file and FFprobe metadata; emits normalized technical facts plus consistency findings.
- `transcodeaudit`: consumes one file or directory and normalized FFprobe facts; emits provenance-review heuristics without claiming actual transcode history.

- [ ] Add fixtures/tests for WAV, FLAC, MP3, extension/container mismatch, non-audio streams where practical, unusual container/codec combinations, metadata/tag extraction, low-bitrate thresholds, spaces/Unicode paths, and Bash/PowerShell parity.
- [ ] Run targeted tests and confirm the new commands fail because they do not exist.
- [ ] Implement both commands in Bash and PowerShell with matching flags/status categories.
- [ ] Run targeted functional/parity tests until passing.
- [ ] Write detailed specs covering pipelines, calculations, flags/defaults, JSON/text examples, internals, limitations, and examples.
- [ ] Commit the two tools, tests, and docs.

### Task 4: `batchsilence` and `albumcontract`

**Files:**
- Create: `bash/batchsilence.sh`, `powershell/batchsilence.ps1`
- Create: `bash/albumcontract.sh`, `powershell/albumcontract.ps1`
- Create: `spec/batchsilence.md`, `spec/albumcontract.md`
- Test: `tests/test_shell_native_tools.py`

**Interfaces:**
- `batchsilence`: consumes a directory scan plus FFmpeg silence measurements; emits per-file leading/trailing silence and comparative outliers.
- `albumcontract`: consumes normalized per-file metadata and optional integrated loudness; emits dominant/expected property contract and outliers.

- [ ] Add deterministic directory fixtures for silence lengths, mostly-silent input, sample-rate/channel outliers, required/missing tags, duplicate track/disc numbers, optional loudness, nested recursion, and report-inside-directory behavior.
- [ ] Run targeted tests and confirm failure for missing commands.
- [ ] Implement Bash and PowerShell versions using shared discovery/measurement helpers.
- [ ] Run functional/parity tests until passing, including partial-analysis-failure behavior.
- [ ] Write full internals/usage docs for both tools.
- [ ] Commit the two tools, tests, and docs.

### Task 5: `loudwalk`

**Files:**
- Create: `bash/loudwalk.sh`
- Create: `powershell/loudwalk.ps1`
- Create: `spec/loudwalk.md`
- Test: `tests/test_shell_native_tools.py`

**Interfaces:**
- Consumes one FFmpeg-decodable file and parses EBU R128 measurements at stable intervals.
- Produces integrated/LRA values when available, short-term timeline, median/percentile spread, jump candidates, deviation candidates, findings, and normalized report.

- [ ] Add deterministic stepped-level and quiet-middle fixtures plus tests for median/deviation/jump categories, top-N limiting, missing optional EBU fields, and parity tolerances.
- [ ] Run targeted tests and confirm failure for missing command.
- [ ] Implement Bash and PowerShell EBU parsing/aggregation using locale-forced FFmpeg output.
- [ ] Run targeted tests until passing.
- [ ] Write full internals/usage documentation.
- [ ] Commit `loudwalk`, tests, and docs.

### Task 6: `stereotruth` and `phasewatch`

**Files:**
- Create: `bash/stereotruth.sh`, `powershell/stereotruth.ps1`
- Create: `bash/phasewatch.sh`, `powershell/phasewatch.ps1`
- Create: `spec/stereotruth.md`, `spec/phasewatch.md`
- Test: `tests/test_shell_native_tools.py`

**Interfaces:**
- Both consume exactly two decoded channels and shared correlation/window measurements.
- `stereotruth` adds RMS/peak balance, dual-mono/negative-correlation proportions, variable-stereo evidence, and bounded delay-search evidence.
- `phasewatch` emits a correlation ledger and contiguous warn/critical/regime-change segments while excluding inactive windows.

- [ ] Add fixtures for dual mono, inverted polarity, imbalance, decorrelated channels, known inter-channel delay, silence, and changing phase regimes.
- [ ] Add tests for conservative defaults, configurable thresholds, inactivity exclusion, no divide-by-zero/non-finite JSON, delay-search bounds, and Bash/PowerShell parity.
- [ ] Run targeted tests and confirm failure for missing commands.
- [ ] Implement the shared window/correlation primitive and both tool entrypoints in both shells.
- [ ] Run functional/parity tests until passing.
- [ ] Write detailed docs explaining formulas, interpretation limits, and false positives.
- [ ] Commit both tools, tests, and docs.

### Task 7: Repository integration and CI

**Files:**
- Modify: `README.md`
- Modify: `docs/RESEARCH.md`
- Modify: `site/index.html` and related existing site assets only as required by current site structure
- Modify/Create: GitHub Actions workflow files under `.github/workflows/` as appropriate
- Test: existing tests plus `tests/test_shell_native_tools.py`

**Interfaces:**
- Consumes all seven completed tool pairs/specs.
- Produces user-facing discovery/install instructions and supported-platform automated verification.

- [ ] Add README and Pages sections/cards for all seven Beta shell-native tools, FFmpeg install/dependency notes, Bash and PowerShell examples, and links to specs/internals.
- [ ] Update research documentation to distinguish shell-native orchestration from the existing Python/JavaScript tools and avoid novelty claims.
- [ ] Extend CI to run Bash tools on Ubuntu, PowerShell on Ubuntu, and PowerShell on Windows with FFmpeg available.
- [ ] Run all existing repository tests plus shell-native tests locally where dependencies are available.
- [ ] Run packaging/site tests and verify existing Python/JavaScript behavior remains unchanged.
- [ ] Commit integration/CI changes.

### Task 8: Final verification and audit

**Files:**
- Modify only files required to correct defects discovered by verification.

**Interfaces:**
- Consumes the complete implementation.
- Produces evidence that all acceptance criteria are met.

- [ ] Run syntax/static checks across every `.sh` and `.ps1` entrypoint/helper.
- [ ] Run the complete Python test suite and shell-native functional/parity suite.
- [ ] Generate all functional fixtures and manually smoke-test all fourteen entrypoints (`7 x Bash`, `7 x PowerShell`) against representative fixtures.
- [ ] Verify every JSON output parses and contains no NaN/Infinity/non-finite values.
- [ ] Verify source hashes/timestamps do not change during analysis.
- [ ] Verify runtime scripts contain no invocation of Python/Node/repository DSP engines.
- [ ] Compare implementation against every numbered acceptance criterion in the approved spec; correct any gap and rerun affected tests.
- [ ] Check GitHub Actions on the final commit and correct any platform-specific failures that are reproducible from the workflow logs.
- [ ] Commit final verification fixes, if any, and record the final tested commit SHA in the completion report.
