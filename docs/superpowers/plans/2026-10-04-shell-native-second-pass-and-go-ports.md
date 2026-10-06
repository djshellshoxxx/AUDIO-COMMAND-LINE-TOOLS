# Shell-Native Audio QC Second-Pass and Go Ports Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair second-pass safety and robustness defects in the Bash/PowerShell audio-QC tools, then add tested Go implementations for all seven tools with three-way parity and cross-platform builds.

**Architecture:** Keep FFmpeg/FFprobe as the low-level measurement engine in all three implementations. Fix safety at shared report/path layers first, then build a small Go shared package for process execution, probing, file discovery, path safety, report writing, and findings; each Go command owns only flags and tool-specific policy.

**Tech Stack:** Bash 4.4+, PowerShell 7+, Go 1.24+, Python unittest harness, FFmpeg/FFprobe, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-04-shell-native-second-pass-and-go-ports-design.md`

## Global Constraints

- Source audio is read-only in every success and error path.
- Exit `0` = clean analysis, `1` = valid analysis with review findings, `2` = dependency/argument/input/report failure.
- Existing v0.1 JSON field names remain compatible.
- Deferred CLI flags stay rejected until they have real behavior and tests.
- Go v1 continues to shell out directly to FFmpeg/FFprobe without shell interpolation.
- Go development artifacts do not replace or mutate existing `v0.1-beta` tags.
- Supported Go build targets: windows/amd64, linux/amd64, darwin/amd64, darwin/arm64.

## Review Focus

1. Report path aliases, including symlinks, must never overwrite analyzed audio.
2. Corrupt/empty files must fail predictably rather than emit malformed reports or stack traces.
3. Unix filenames containing control characters must still produce valid JSON.
4. Extreme finite numeric values must not overflow or produce invalid FFmpeg filters.
5. Silent/very-short stereo must not create NaN/Inf JSON values or false crashes.

---

### Task 1: Add second-pass adversarial regression tests

**Files:**
- Modify: `tests/test_shell_native_tools.py`
- Create: `tests/test_shell_native_adversarial.py`

**Interfaces:**
- Consumes: existing Bash/PowerShell CLIs.
- Produces: failing tests that define source-output alias rejection, malformed-input behavior, JSON control-character safety, Unicode/shell-sensitive paths, silent/short audio, and numeric boundary behavior.

- [ ] **Step 1: Write failing source-output alias tests** for every single-file and directory tool, asserting exit `2` and byte-for-byte + mtime source preservation.
- [ ] **Step 2: Run the focused tests** with `python -m unittest -v tests.test_shell_native_adversarial` and confirm failures reproduce the current overwrite vulnerability.
- [ ] **Step 3: Add failing tests for corrupt/empty audio, mono misuse, silent stereo, Unicode/shell-sensitive paths, and invalid output destinations.**
- [ ] **Step 4: Add Unix-only control-character filename JSON test** and numeric extreme/boundary cases for all public numeric flags.
- [ ] **Step 5: Run the adversarial suite again** and record the exact failing behaviors before production changes.

### Task 2: Repair shared Bash and PowerShell safety/robustness

**Files:**
- Modify: `bash/lib/common.sh`
- Modify: `powershell/lib/Common.ps1`
- Modify only as required by focused failures: `bash/*.sh`, `powershell/*.ps1`
- Test: `tests/test_shell_native_adversarial.py`, `tests/test_shell_native_tools.py`

**Interfaces:**
- Consumes: Task 1 failing cases.
- Produces: Bash `validate_report_target OUTPUT SOURCES...`; PowerShell `Assert-CDLReportTarget -Output <string> -Sources <string[]>`; safe/atomic report writers; complete JSON string escaping in Bash.

- [ ] **Step 1: Implement path-alias guards in shared helpers** using resolved/canonical paths; validate all sources before report writes.
- [ ] **Step 2: Run alias tests** and require all to pass while preserving sources.
- [ ] **Step 3: Implement atomic report writing** via temp file in the destination directory followed by rename/replace only after validation.
- [ ] **Step 4: Fix Bash JSON escaping** for U+0000..U+001F representable filename characters and rerun the control-character JSON test.
- [ ] **Step 5: Fix only reproduced malformed-input/numeric defects** at the owning shared or CLI layer.
- [ ] **Step 6: Run `python -m unittest -v tests.test_shell_native_tools tests.test_shell_native_adversarial`** and require zero failures.

### Task 3: Create the Go shared runtime with unit tests

**Files:**
- Create: `go/go.mod`
- Create: `go/internal/cdl/exec.go`
- Create: `go/internal/cdl/ffprobe.go`
- Create: `go/internal/cdl/ffmpeg.go`
- Create: `go/internal/cdl/paths.go`
- Create: `go/internal/cdl/files.go`
- Create: `go/internal/cdl/report.go`
- Create: `go/internal/cdl/findings.go`
- Create: `go/internal/cdl/*_test.go`

**Interfaces:**
- Produces: `Run(ctx,name,args...)`, `ProbeStreamValue`, `ProbeFormatValue`, `FindAudioFiles`, `ValidateReportTarget`, `WriteReportAtomic`, `StatusFromFindings`, and FFmpeg parser helpers used by Tasks 4-6.

- [ ] **Step 1: Write failing Go tests** for deterministic discovery, resolved-path alias rejection, atomic report writing, JSON encoding, dependency execution, and parser helpers.
- [ ] **Step 2: Run `cd go && go test ./internal/cdl/...`** and verify RED failures are feature-missing failures.
- [ ] **Step 3: Implement the minimal shared package APIs** named above without shell interpolation.
- [ ] **Step 4: Re-run `go test ./internal/cdl/...`** and require PASS.
- [ ] **Step 5: Run `go vet ./...`** and fix only concrete vet findings.

### Task 4: Port formattruth and transcodeaudit to Go

**Files:**
- Create: `go/cmd/formattruth/main.go`
- Create: `go/cmd/formattruth/main_test.go`
- Create: `go/cmd/transcodeaudit/main.go`
- Create: `go/cmd/transcodeaudit/main_test.go`

**Interfaces:**
- Consumes: Task 3 runtime.
- Produces: Go CLIs matching v0.1 Bash long flags, exit classes, measurement field names, deterministic order, and findings.

- [ ] **Step 1: Write command tests** for help, valid JSON, malformed input, source-output alias rejection, and finding categories.
- [ ] **Step 2: Run command tests and verify RED.**
- [ ] **Step 3: Implement formattruth minimally to match current Bash/PowerShell semantics.**
- [ ] **Step 4: Implement transcodeaudit minimally to match current semantics and provenance limitation wording.**
- [ ] **Step 5: Run `go test ./cmd/formattruth ./cmd/transcodeaudit` and `go test ./...`.**

### Task 5: Port batchsilence and albumcontract to Go

**Files:**
- Create: `go/cmd/batchsilence/main.go`
- Create: `go/cmd/batchsilence/main_test.go`
- Create: `go/cmd/albumcontract/main.go`
- Create: `go/cmd/albumcontract/main_test.go`

**Interfaces:**
- Consumes: Task 3 runtime.
- Produces: deterministic directory tools with the same per-file ledgers, threshold findings, contract inference, optional loudness measurement, source-safety invariant, and exit classes.

- [ ] **Step 1: Write failing integration tests** using generated FFmpeg fixtures for padded silence and mixed sample-rate/channel batches.
- [ ] **Step 2: Implement batchsilence** using forward and reversed silence detection consistent with the PowerShell fix.
- [ ] **Step 3: Implement albumcontract** with deterministic dominant-value tie-breaking identical to the current contract.
- [ ] **Step 4: Run the two command suites and then `go test ./...`.**

### Task 6: Port loudwalk, stereotruth, and phasewatch to Go

**Files:**
- Create: `go/cmd/loudwalk/main.go`
- Create: `go/cmd/loudwalk/main_test.go`
- Create: `go/cmd/stereotruth/main.go`
- Create: `go/cmd/stereotruth/main_test.go`
- Create: `go/cmd/phasewatch/main.go`
- Create: `go/cmd/phasewatch/main_test.go`

**Interfaces:**
- Consumes: Task 3 EBU R128, phase, and astats helpers.
- Produces: Go implementations with current v0.1 thresholds, findings, and JSON fields; stereo-only commands reject non-stereo input with exit `2`.

- [ ] **Step 1: Write failing fixture-based tests** for loudness timeline, dual-mono finding, phase windows, silent/short stereo, threshold boundaries, and mono rejection.
- [ ] **Step 2: Implement loudwalk** with integrated/LRA/short-term parsing, median, jump and deviation findings.
- [ ] **Step 3: Implement stereotruth** with dual-mono ratio, negative-correlation ratio, RMS imbalance, and current finding policies.
- [ ] **Step 4: Implement phasewatch** with timestamped windows, critical-correlation and regime-change findings.
- [ ] **Step 5: Run these command tests and then `go test ./...`.**

### Task 7: Add three-way parity and executable integration testing

**Files:**
- Create: `tests/test_go_shell_native_parity.py`
- Modify: `tests/test_shell_native_adversarial.py`

**Interfaces:**
- Consumes: compiled Go commands plus Bash and PowerShell tools.
- Produces: parity evidence for top-level status, scalar measurements, finding-category sets, deterministic ordering, and exit-code classes.

- [ ] **Step 1: Write parity tests** for all seven tools using the existing synthetic fixture patterns.
- [ ] **Step 2: Build Go binaries into a temporary test directory** and run parity tests; fix only semantic mismatches against the approved v0.1 behavior.
- [ ] **Step 3: Use numeric tolerances for floating-point measurements** while requiring exact category/order/status parity where defined.
- [ ] **Step 4: Run the complete Python shell-native + adversarial + Go parity suite.**

### Task 8: Add Go CI builds and development artifacts

**Files:**
- Modify: `.github/workflows/verify-and-publish.yml`
- Create: `.github/workflows/build-go-audio-qc.yml`
- Modify: `README.md`
- Create: `docs/GO_PORTS.md`

**Interfaces:**
- Consumes: all Go commands and test suites.
- Produces: Linux test/parity job, Windows Go + PowerShell tests, macOS Go tests, and cross-compiled binaries for windows/amd64, linux/amd64, darwin/amd64, darwin/arm64 as workflow artifacts only.

- [ ] **Step 1: Add CI jobs** installing Go and FFmpeg, running Go tests and appropriate parity suites by platform.
- [ ] **Step 2: Add cross-platform build commands** for all seven binaries and four required target tuples.
- [ ] **Step 3: Document Go status as development ports** and do not attach them to historical `v0.1-beta` releases.
- [ ] **Step 4: Push the branch and inspect the workflow run; debug any failures systematically.**

### Task 9: Final verification and audit

**Files:**
- Modify as needed only for verified defects discovered by final review.
- Create: `docs/SHELL_NATIVE_SECOND_PASS_AUDIT.md`

**Interfaces:**
- Consumes: all prior tasks.
- Produces: evidence-backed audit record and release-readiness status.

- [ ] **Step 1: Run Bash syntax checks, PowerShell functional suite, Go test/vet, Python adversarial/parity suites, and repository-wide existing tests.**
- [ ] **Step 2: Verify all required Go target binaries build.**
- [ ] **Step 3: Re-read the spec requirement-by-requirement and record coverage/gaps in the audit.**
- [ ] **Step 4: Inspect GitHub Actions for the exact head commit and record job conclusions.**
- [ ] **Step 5: Do not publish new releases in this task; report whether a patch Beta is justified based on the safety fixes and green CI.**
