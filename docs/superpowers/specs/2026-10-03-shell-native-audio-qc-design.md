# Shell-native audio QC tools design

Date: 2026-10-03
Status: design approved in principle; implementation pending written-spec review

## Goal

Add a family of genuinely native Bash and PowerShell audio utilities to AUDIO-COMMAND-LINE-TOOLS. These are not launchers for the existing Python programs. They use FFmpeg and FFprobe as required external audio engines, while each shell implementation performs its own argument parsing, orchestration, aggregation, interpretation, JSON/text reporting, threshold evaluation, and exit-code handling.

The purpose is to fill practical command-line workflow gaps where FFmpeg exposes useful measurements but leaves users to assemble and interpret them manually. The tools should favor batch processing and automation, remain transparent about heuristics, and have equivalent Bash and PowerShell interfaces wherever practical.

## Dependencies

Required:

- FFmpeg
- FFprobe
- Bash 4.4+ for `.sh` implementations
- PowerShell 7+ for `.ps1` implementations

Bash implementation may use standard POSIX/GNU utilities available on common Linux distributions. JSON output must not require `jq`; scripts should construct valid JSON themselves or use FFprobe's JSON and carefully serialize derived values. Tests may use Python 3 solely as a test harness and fixture generator because the repository already uses Python for regression testing. Runtime scripts must not depend on Python.

PowerShell implementation must rely on built-in PowerShell/.NET facilities plus FFmpeg/FFprobe and must not depend on Python.

## Shared CLI contract

Every tool has matching Bash and PowerShell forms:

```text
bash/<tool>.sh [input(s)] [options]
powershell/<tool>.ps1 [input(s)] [options]
```

Common behavior:

- `--help` / `-Help`
- `--json` / `-Json` for structured JSON output
- `--output PATH` / `-Output PATH` to write a report instead of stdout
- `--recursive` / `-Recursive` for directory tools
- `--extensions` / `-Extensions` where directory scanning is supported
- deterministic ordering of batch results
- paths containing spaces are supported
- input files are never modified
- errors go to stderr
- exit 0: completed with no policy/threshold failures
- exit 1: completed but one or more user-selected checks failed
- exit 2: invalid arguments, missing dependency, unreadable input, FFmpeg/FFprobe failure, or report-write failure

Every JSON report includes:

- `tool`
- `version`
- `generated_utc`
- input path(s)
- FFmpeg/FFprobe version summary
- effective thresholds/options
- measurements
- findings
- final `status` (`ok`, `review`, or `error`)

Heuristic findings must be worded as evidence to inspect, not claims of provenance or defects that the measurement cannot prove.

## Tool 1: stereotruth

### Problem

Many files labelled stereo are actually dual-mono, polarity-inverted copies, strongly imbalanced, or nearly identical channels with a small delay. FFmpeg can expose channel statistics/correlation primitives, but users otherwise need several commands and manual interpretation.

### Inputs

One audio file at a time; any FFmpeg-decodable format with exactly two decoded channels.

### Measurements

- left/right RMS and peak level
- RMS balance in dB
- normalized correlation over configurable windows
- proportion of windows above a `dual-mono` correlation threshold
- proportion of strongly negative-correlation windows
- optional small-delay sweep within a configurable ±millisecond range using channel delays and correlation measurements

### Findings

- likely dual-mono candidate
- possible polarity inversion candidate
- sustained channel imbalance
- highly variable stereo relationship
- possible small inter-channel timing offset

Defaults must be conservative and configurable. Silence/near-silence windows are excluded from normalized correlation findings.

### Key flags

`--window-ms`, `--dual-mono-correlation`, `--negative-correlation`, `--imbalance-db`, `--delay-search-ms`, `--min-active-db`, `--json`, `--output`.

## Tool 2: loudwalk

### Problem

Integrated LUFS is insufficient for finding unusual sections inside a long file. FFmpeg's `ebur128` filter provides momentary/short-term data, but the raw stream is inconvenient for automated review.

### Measurements

- integrated loudness
- loudness range when reported by FFmpeg
- time-coded short-term loudness samples
- median short-term loudness
- percentile spread
- largest adjacent-window loudness jumps
- sections deviating from the file median by more than a configurable threshold

### Findings

- abrupt loudness transition candidates
- unusually quiet/loud sections relative to the same program
- unusually high internal loudness spread

This is a relative consistency tool, not a streaming-platform compliance validator.

### Key flags

`--interval`, `--jump-db`, `--deviation-db`, `--top N`, `--json`, `--output`.

## Tool 3: formattruth

### Problem

Batch libraries often contain misleading file extensions, odd container/codec pairings, inconsistent sample formats, or metadata that contradicts the decoded stream. FFprobe reports the raw facts but does not turn them into a concise consistency audit.

### Measurements

- file extension
- detected container
- codec name/long name
- sample format and bits-per-sample fields when available
- sample rate
- channel count/layout
- bit rate when meaningful
- duration
- stream count and non-audio stream presence
- selected tags

### Findings

- extension/container mismatch candidate
- unexpected non-audio streams
- missing/ambiguous channel layout
- suspiciously inconsistent bit-depth metadata
- duplicate/conflicting selected metadata tags when observable

No claim that a mismatch is corrupt; containers legitimately support multiple codecs.

### Key flags

`--tags`, `--strict-extension`, `--allow-stream-types`, `--json`, `--output`.

## Tool 4: albumcontract

### Problem

A folder representing an album, DJ set export, sample pack, podcast season, or delivery batch often contains one or two accidental outliers. Existing single-file tools do not summarize the dominant contract of a directory and identify deviations.

### Operation

Scan a directory, run FFprobe metadata extraction for every supported file, optionally collect loudness using FFmpeg, determine dominant/common technical properties, then report outliers.

### Measurements

Per file:

- codec/container
- sample rate
- sample format/bit-depth evidence
- channels/layout
- duration
- optional integrated LUFS
- selected tags

Batch summary:

- dominant sample rate
- dominant channel count/layout
- dominant sample format
- codec/container distribution
- optional median integrated loudness

### Findings

- sample-rate outlier
- channel-layout outlier
- sample-format/bit-depth outlier
- codec/container outlier
- loudness outlier relative to batch median
- missing required tags
- duplicate track/disc-number candidates where parseable

### Key flags

`--recursive`, `--extensions`, `--loudness`, `--loudness-tolerance-db`, `--require-tag`, `--expected-rate`, `--expected-channels`, `--json`, `--output`.

Explicit expected values override inferred dominant values.

## Tool 5: phasewatch

### Problem

Whole-file correlation can hide brief phase problems. The useful workflow is a timestamped phase/correlation ledger that identifies sustained changes.

### Measurements

- normalized correlation in configurable windows
- contiguous runs below warning/critical thresholds
- minimum, median, and percentile correlation
- active/silent window classification

### Findings

- sustained negative-correlation segment
- sustained weak-correlation segment
- abrupt phase/correlation regime change

It does not diagnose the cause of a phase relationship or claim mono incompatibility from correlation alone.

### Key flags

`--window-ms`, `--warn-correlation`, `--critical-correlation`, `--min-duration-ms`, `--min-active-db`, `--json`, `--output`.

## Tool 6: batchsilence

### Problem

Single-file silence trimming tools exist, including this repository's `tailbudget`, but large exports often need comparative QC: finding tracks whose starts/ends differ markedly from the rest of a batch.

### Measurements

For each file:

- leading silence duration
- trailing silence duration
- total duration
- leading/trailing silence ratio

Batch summary:

- medians and percentiles of leading/trailing silence
- outliers relative to explicit limits or configurable deviation from batch median

### Findings

- excessive leading silence
- excessive trailing silence
- unusually short pre-roll/post-roll compared with peer files
- all/mostly-silent candidate when detected by threshold analysis

### Key flags

`--threshold-db`, `--min-silence`, `--max-leading`, `--max-trailing`, `--deviation-ms`, `--recursive`, `--json`, `--output`.

## Tool 7: transcodeaudit

### Problem

FFprobe exposes codec/container/bitrate facts, but libraries often need a quick triage report for files whose technical characteristics suggest they deserve provenance review.

### Measurements

- codec/container
- sample rate/channels
- reported bit rate where meaningful
- encoder/writing-library tags
- duration and file size
- derived nominal bits-per-second per channel

### Findings

Rule-based review candidates such as:

- lossless codec stored in an unusual container
- low reported bitrate for the codec/channel arrangement according to a user-configurable floor
- lossy codec carrying high-resolution PCM-style metadata claims
- encoder metadata inconsistent across a delivery batch when batch mode is used

The tool must explicitly state that lossy-to-lossless transcoding history cannot be proven from these observations alone. Spectral-cutoff guessing is excluded from version 1 because it would create too many codec- and source-dependent false conclusions.

### Key flags

`--recursive`, `--min-bitrate`, `--show-tags`, `--json`, `--output`.

## Repository layout

```text
bash/
  stereotruth.sh
  loudwalk.sh
  formattruth.sh
  albumcontract.sh
  phasewatch.sh
  batchsilence.sh
  transcodeaudit.sh
  lib/
    common.sh
    ffmpeg.sh
    json.sh
powershell/
  stereotruth.ps1
  loudwalk.ps1
  formattruth.ps1
  albumcontract.ps1
  phasewatch.ps1
  batchsilence.ps1
  transcodeaudit.ps1
  lib/
    Common.ps1
    FFmpeg.ps1
spec/
  stereotruth.md
  loudwalk.md
  formattruth.md
  albumcontract.md
  phasewatch.md
  batchsilence.md
  transcodeaudit.md
tests/
  test_shell_native_tools.py
  fixtures/ (generated at test time, not committed binaries)
```

Existing Python and JavaScript implementations remain unchanged unless documentation links need updating.

## Internals documentation

Each tool gets a spec page containing:

1. purpose and gap addressed
2. exact FFmpeg/FFprobe primitives used
3. command pipeline/data flow
4. calculation formulas and threshold definitions
5. flags and defaults
6. JSON schema example
7. text output example
8. exit-code behavior
9. limitations/false-positive cases
10. Bash internals
11. PowerShell internals
12. usage examples, including batch examples

README and GitHub Pages are updated with a dedicated "Shell-native tools" section that clearly labels FFmpeg/FFprobe as dependencies and distinguishes these from the existing Python/JavaScript tools.

## Testing strategy

Tests generate deterministic WAV fixtures with FFmpeg at runtime. No third-party audio is committed.

### Dependency and CLI tests

For every Bash and PowerShell tool:

- help works without an input file
- missing FFmpeg/FFprobe is detected cleanly where practical
- missing input returns exit 2
- invalid numeric flags return exit 2
- paths containing spaces work
- JSON parses successfully
- `--output` writes a valid report
- deterministic input ordering
- scripts never modify source file timestamps/content

### Cross-shell parity

The same generated fixture is run through `.sh` and `.ps1` implementations. Tests compare:

- status
- finding categories
- rounded numeric measurements with documented tolerance
- exit code

Exact raw text formatting need not match.

### Functional fixtures

Generate at least:

- identical-channel dual mono
- polarity-inverted stereo
- intentionally imbalanced stereo
- decorrelated/different stereo channels
- stereo with a known small channel delay
- file with controlled loudness step
- file with quiet middle section
- WAV/FLAC/MP3/container variants
- folder with one sample-rate outlier
- folder with one mono outlier among stereo files
- files with known leading/trailing silence
- batch with duplicate/missing selected tags where FFmpeg can generate them

### Platform coverage

GitHub Actions matrix should execute:

- Bash tools on Ubuntu
- PowerShell tools on Ubuntu using `pwsh`
- PowerShell tools on Windows

Where FFmpeg package versions differ, tests use tolerances and compare categorical findings rather than brittle exact stderr strings.

## Page integration

The project page gains cards for the seven shell-native tools with:

- one-sentence purpose
- Bash command example
- PowerShell command example
- key findings produced
- dependency/install instructions for FFmpeg on Windows/Linux
- links to detailed internals/spec documentation

All tools remain labelled Beta, consistent with the project's current stage.

## Non-goals for version 1

- replacing FFmpeg DSP with shell arithmetic
- modifying audio files
- automatic normalization or repair
- claiming definitive encoding provenance
- automatic source separation
- ML-based audio classification
- proving clipping, corruption, or mastering errors from a single heuristic
- platform-specific GUI integration

## Research basis

The design relies on documented FFprobe machine-readable stream/container inspection and FFmpeg audio analysis filters including EBU R128 loudness, statistics, silence detection, and correlation. Existing specialist tools already perform broader loudness normalization and delivery QC; these additions intentionally focus on small transparent batch/QC workflows and shell-native automation rather than duplicating a mastering suite.

## Acceptance criteria

Implementation is complete when:

1. all seven tools exist as independent Bash and PowerShell implementations;
2. no runtime script invokes the repository's Python or JavaScript engines;
3. shared flags and exit codes behave consistently;
4. functional and parity tests pass on supported CI platforms;
5. each tool has detailed usage and internals documentation;
6. README and GitHub Pages list and explain all seven tools;
7. dependencies and limitations are explicit;
8. all new tools are labelled Beta;
9. existing tests continue to pass;
10. a final manual smoke test is performed against generated fixtures before completion is claimed.
