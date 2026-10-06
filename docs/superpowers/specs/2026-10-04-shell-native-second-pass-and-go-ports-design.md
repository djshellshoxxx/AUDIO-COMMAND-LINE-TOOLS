# Shell-Native Audio QC Second-Pass QA and Go Ports Design

## Purpose

Perform a second adversarial QA pass over the seven shell-native audio QC tools, repair reproducible defects without weakening existing behavior, then add a third implementation of each tool in Go. The Go ports should preserve the current CLI intent and JSON contract while producing portable binaries for Windows, Linux, and macOS.

Tools in scope:

- `formattruth`
- `transcodeaudit`
- `batchsilence`
- `albumcontract`
- `loudwalk`
- `stereotruth`
- `phasewatch`

## Existing implementations

Each tool already has Bash and PowerShell implementations using FFmpeg/FFprobe as the measurement engine. They share these external behavior rules:

- source audio must remain read-only;
- exit `0` means analysis completed with no review findings;
- exit `1` means analysis completed with one or more review findings;
- exit `2` means the command could not complete due to dependency, argument, input, or report-output failure;
- JSON output uses the common `tool`, `version`, `generated_utc`, `inputs`, `dependencies`, `options`, `measurements`, `findings`, `status` shape;
- findings are evidence for review, not definitive proof of artistic, technical, or provenance faults.

## Second-pass QA goals

The previous QA covered normal execution, basic invalid options, selected Bash/PowerShell parity, deferred-option rejection, deterministic ordering, paths with spaces, JSON report output, and ordinary source immutability. The second pass adds adversarial coverage that deliberately attacks assumptions in the implementations.

### Source overwrite protection

A report output path must never resolve to any analyzed source audio file. This applies to both single-file and directory tools. The protection must compare resolved paths, so relative-path aliases and symlink aliases cannot bypass it.

For a single-file tool, `--output INPUT` / `-Output INPUT` must fail with exit `2` before any write occurs.

For a directory tool, the output path must be checked against every analyzed audio file before the report is written. If any resolved path matches, the command fails with exit `2` and leaves every source unchanged.

### Output-path failures

Report writing must fail cleanly with exit `2` when:

- the parent directory does not exist;
- the destination is a directory rather than a regular file target;
- permissions prevent creating or replacing the report;
- a path alias resolves to source audio.

Partial report files must not be left behind when the tool can reasonably validate the target before writing.

### JSON robustness

Bash JSON string encoding must correctly escape all JSON control characters that can occur in Unix paths or metadata, including at minimum:

- quotation mark;
- backslash;
- newline;
- carriage return;
- tab;
- other bytes in the U+0000 to U+001F range that can legally appear in Unix filenames except NUL and `/`.

Reports produced from such paths must parse with a standards-compliant JSON parser.

### Input and decoding failures

Each tool must be exercised against:

- zero-length files with supported extensions;
- corrupted files with supported extensions;
- unsupported files;
- Unicode filenames;
- filenames containing shell-sensitive characters;
- multiple audio streams where applicable;
- mono audio supplied to stereo-only tools;
- silent stereo audio;
- very short audio;
- FFmpeg/FFprobe returning no expected measurement values.

Expected behavior is either a valid report using `null` for unavailable measurements where the analysis can still be meaningful, or exit `2` where the required measurement cannot be obtained safely. The tool must not emit malformed JSON or crash with an implementation-specific stack trace.

### Numeric boundary validation

All public numeric controls must reject non-finite values, malformed values, and values outside their documented domain. Tests should include normal minimum/maximum boundaries and extreme finite values that could trigger integer or floating-point overflow in derived arithmetic.

At minimum:

- correlations remain in `[-1, 1]`;
- non-negative decibel-distance or duration controls reject negative values;
- duration thresholds that must be positive reject zero;
- expected sample rates and channel counts remain positive integers;
- bitrate floors remain non-negative integers.

### Parity

For fixtures where platform and FFmpeg output are equivalent, Bash, PowerShell, and Go should agree on:

- top-level tool name and status;
- core scalar measurements;
- finding category sets;
- deterministic file ordering;
- exit-code class.

Small floating-point formatting differences are acceptable when values remain numerically equivalent within a documented tolerance.

## Repair policy

Repairs must follow test-first debugging:

1. reproduce a defect with a focused failing regression test;
2. identify the root cause;
3. apply the smallest fix at the owning shared layer when possible;
4. rerun the focused test;
5. rerun the full shell-native suite;
6. rerun the repository-wide suite.

Do not reintroduce deferred CLI controls merely to satisfy the older design documents. A control returns only when it changes behavior and has regression coverage.

## Go architecture

Go is the third maintained implementation language for all seven tools.

### Runtime model

The first Go generation continues to use installed FFmpeg and FFprobe executables as low-level measurement engines. It does not reimplement the DSP filters in Go. This preserves comparable measurement semantics while providing standalone compiled command binaries around the orchestration, validation, aggregation, findings, and reporting logic.

Minimum target: Go 1.24 or the repository CI-supported stable Go release if newer when implemented.

### Layout

```text
go/
  go.mod
  internal/cdl/
    exec.go
    ffprobe.go
    ffmpeg.go
    paths.go
    report.go
    files.go
    findings.go
  cmd/
    formattruth/main.go
    transcodeaudit/main.go
    batchsilence/main.go
    albumcontract/main.go
    loudwalk/main.go
    stereotruth/main.go
    phasewatch/main.go
```

Shared responsibilities:

- `exec.go`: execute FFmpeg/FFprobe without shell interpolation and return captured stdout/stderr/exit status;
- `ffprobe.go`: first-audio-stream and format probing helpers;
- `ffmpeg.go`: EBU R128, phase/correlation, silence, and astats measurement helpers;
- `paths.go`: resolved-path equality, safe report target checks, and output validation;
- `files.go`: supported extension discovery and deterministic ordering;
- `report.go`: common versioned JSON model and atomic report writing;
- `findings.go`: shared finding structure and status calculation.

Each `cmd/<tool>/main.go` owns only its CLI parsing, tool-specific policy, and report assembly.

## Go CLI compatibility

The Go tools should use the same long flag names as Bash where practical:

```text
formattruth INPUT [--json] [--output PATH]
transcodeaudit FILE|DIR [--recursive] [--min-bitrate BPS] [--json] [--output PATH]
batchsilence DIR [--threshold-db DB] [--min-silence SEC] [--max-leading SEC] [--max-trailing SEC] [--recursive] [--json] [--output PATH]
albumcontract DIR [--recursive] [--expected-rate HZ] [--expected-channels N] [--loudness] [--json] [--output PATH]
loudwalk INPUT [--jump-db DB] [--deviation-db DB] [--json] [--output PATH]
stereotruth INPUT [--dual-mono-correlation X] [--negative-correlation X] [--imbalance-db DB] [--json] [--output PATH]
phasewatch INPUT [--critical-correlation X] [--json] [--output PATH]
```

`--help` exits `0`. Argument errors exit `2`. Findings exit `1` after a valid report is emitted.

## Go report compatibility

The Go JSON report must retain the same top-level schema and tool-specific measurement field names used by the Bash and PowerShell v0.1 Beta implementations. Go-specific dependency metadata may additionally include a `go_runtime` or `implementation` field only if this is added consistently without breaking existing consumers.

Version for the initial Go development ports should remain development-labelled and must not imply a new stable release until parity and CI pass. The existing `v0.1-beta` release artifacts are not replaced automatically.

## Testing strategy

### Existing-language regression layer

Extend `tests/test_shell_native_tools.py` with focused tests for:

- output path equal to source;
- resolved/symlink output aliases to source where supported by the runner;
- corrupted and zero-length audio;
- silent stereo and mono misuse;
- Unicode and shell-sensitive paths;
- Bash JSON control-character escaping on Unix;
- invalid and extreme numeric boundaries;
- unwritable/invalid report destinations;
- source content and modification time preservation after every error path.

### Go unit tests

Add Go tests for shared path validation, deterministic discovery, JSON encoding, argument validation, report writing, command execution, and parser helpers without requiring real audio where unit isolation is possible.

### Go integration/parity tests

Use synthetic FFmpeg fixtures to run all seven Go commands. Extend the Python regression harness or add an equivalent parity harness so the same fixtures compare Go against Bash and PowerShell for core measurements and finding categories.

### Platform matrix

CI must at minimum exercise:

- Linux: Bash + PowerShell + Go + three-way parity;
- Windows: PowerShell + Go;
- macOS: Go build/test and existing repository suite.

Cross-compile or native-build artifacts for:

- `windows/amd64`;
- `linux/amd64`;
- `darwin/amd64`;
- `darwin/arm64`.

`linux/arm64` may be added if the build remains trivial and tested enough to avoid implying runtime certification.

## Release policy

The existing seven `v0.1-beta` releases remain historical Beta artifacts. Second-pass fixes land on the development branch first. If a source-safety defect is repaired, future replacement release tags should use a new patch prerelease version rather than mutating existing tags.

The Go ports begin as development artifacts. They can be attached to a later Beta only after:

- all Go unit tests pass;
- all seven Go integration tests pass;
- supported three-way parity checks pass;
- source-overwrite regression tests pass in every implementation;
- repository-wide CI passes on the release commit.

## Non-goals for this phase

- replacing FFmpeg DSP with native Go DSP;
- restoring previously deferred advanced options without implementation;
- GUI development;
- real-time audio processing;
- proving lossy provenance from technical observations;
- changing the existing JSON schema unnecessarily;
- silently rewriting existing v0.1 Beta release tags.

## Success criteria

This phase is successful when all known second-pass defects have reproducible regression coverage and fixes, the existing Bash and PowerShell tools pass the expanded adversarial suite, all seven Go commands exist and pass functional tests, parity is demonstrated for core behavior, CI builds the supported Go binaries, and no implementation can overwrite analyzed source audio via its report-output option.
