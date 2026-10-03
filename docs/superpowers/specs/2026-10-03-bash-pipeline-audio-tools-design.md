# Bash-native audio pipeline tools design

Date: 2026-10-03
Status: design approved; written specification awaiting review

## Goal

Add six Bash-native audio quality-control and forensic workflow tools to `AUDIO-COMMAND-LINE-TOOLS`. The tools must be useful as standalone commands and as composable Unix pipeline stages. Runtime implementations must be Bash plus standard Unix tooling and FFmpeg/FFprobe; they must not invoke the repository's Python or JavaScript engines.

The family is intentionally different from generic audio conversion, normalization, silence trimming, LUFS measurement, waveform display, or spectral plotting. Each utility targets a narrower workflow gap that is awkward to perform repeatedly with raw FFmpeg commands alone.

The six tools are:

1. `edgeguard.sh` — suspicious boundary/truncation analysis
2. `subphase.sh` — low-frequency stereo phase/correlation analysis
3. `banddrift.sh` — time-coded tonal-balance drift analysis
4. `repeataudit.sh` — exact repeated decoded-audio block detection
5. `samplefreeze.sh` — frozen/near-frozen PCM run detection
6. `transientledger.sh` — transient-density and crest-behaviour timeline

All tools are Beta.

## Design principles

- Bash 4.4+.
- FFmpeg and FFprobe are required external audio engines.
- Standard POSIX/GNU utilities may be used: `awk`, `sed`, `grep`, `sort`, `cut`, `paste`, `od`, `dd`, `cksum`, `sha256sum`/`shasum`, `mktemp`, `find`, `xargs`, and coreutils equivalents.
- No Python, Node, Perl, Ruby, or compiled helper runtime dependency.
- `jq` is optional downstream tooling, never a runtime requirement.
- Input files are never modified.
- Temporary decoded PCM must be removed with traps on success, failure, or interruption.
- Human-readable text is available, but TSV and JSONL are first-class output formats for pipelines.
- stdout contains only requested records/report output. Diagnostics go to stderr.
- File iteration is deterministic.
- Paths containing spaces and newlines must be handled safely where shell/platform tooling permits; directory traversal uses NUL delimiters internally.
- Numerical locale must be forced to `LC_ALL=C`.
- Heuristic findings are review candidates, not proof of mastering defects, corruption, provenance, or intent.

## Shared repository layout

```text
bash/
  edgeguard.sh
  subphase.sh
  banddrift.sh
  repeataudit.sh
  samplefreeze.sh
  transientledger.sh
  lib/
    audio-common.sh
    output.sh
    pcm.sh
spec/
  edgeguard.md
  subphase.md
  banddrift.md
  repeataudit.md
  samplefreeze.md
  transientledger.md
tests/
  test_bash_pipeline_tools.py
  bash-fixtures/        # generated during tests; not committed audio binaries
```

Python is permitted only as the repository's existing test harness. It is not a runtime dependency of any Bash tool.

## Shared CLI contract

Every script supports:

```text
--help
--version
--format text|tsv|jsonl
--output PATH
--quiet
--keep-temp          # diagnostic use only; prints temp path to stderr
```

Directory-capable tools additionally support:

```text
--recursive
--extensions LIST
```

Where appropriate, tools accept one or more files. A path of `-` may be supported only if the algorithm can consume a single FFmpeg-readable stdin stream without seeking or running multiple passes. Tools requiring multiple passes must reject `-` with exit 2 and explain why.

### Exit codes

- `0`: analysis completed; no threshold-triggered review findings.
- `1`: analysis completed; one or more configured review findings were emitted.
- `2`: invalid arguments, missing dependency, unreadable input, unsupported stream layout, FFmpeg/FFprobe failure, temporary-file failure, or report-write failure.
- `130`: SIGINT propagated after cleanup.

### TSV rules

- UTF-8 text.
- One record per line.
- Header emitted by default; `--no-header` suppresses it.
- Path is the first field.
- Numeric fields use `.` decimal separator.
- Tabs/newlines in path fields are escaped as `\\t` and `\\n`.
- No prose appears in TSV stdout.

### JSONL rules

- One complete JSON object per line.
- No surrounding array.
- Every event object contains at minimum `tool`, `version`, `path`, `event`, `start_seconds`, `end_seconds`, `severity`, and `details`.
- Summary objects use `event: "summary"`.
- Strings are escaped by a shared shell JSON encoder; the implementation must not require `jq`.

## Shared shell libraries

### `audio-common.sh`

Responsibilities:

- strict-mode bootstrap (`set -euo pipefail` where safe; functions must deliberately neutralize expected non-zero probes)
- dependency discovery
- FFmpeg/FFprobe version capture
- numeric argument validation
- readable/writable path validation
- deterministic file collection
- temporary directory creation and cleanup traps
- signal handling
- duration/sample-rate/channel probing
- extension filtering

### `output.sh`

Responsibilities:

- TSV escaping
- JSON string escaping
- text/TSV/JSONL record dispatch
- output-file atomic write pattern (`mktemp` in destination directory then `mv`)
- common summary records

### `pcm.sh`

Responsibilities:

- FFmpeg decode helpers to canonical PCM
- canonical formats:
  - signed 16-bit little-endian mono/stereo for exact sample/block workflows
  - `f32le` where floating-point DSP measurements are preferable
- channel split/filter helpers
- sample-count to seconds conversion
- safe byte-offset calculations

## Tool 1: edgeguard.sh

### Purpose

Detect exports that may begin or end abruptly, have audio energy pressed against a file boundary, or end with a discontinuity inconsistent with a normal fade or natural decay. This is not a silence trimmer.

### Inputs

One or more FFmpeg-decodable audio files.

### Core measurements

For both start and end boundaries:

- RMS over configurable boundary windows
- peak level over boundary windows
- first/last active sample timestamp relative to boundary
- sample-to-sample discontinuity at the exact boundary region
- zero-crossing proximity for the first/last active sample
- short RMS envelope slope over configurable sub-windows
- fade evidence: monotonic or near-monotonic energy change across the boundary region

### Default analysis

- boundary window: 100 ms
- envelope subdivision: 10 ms
- activity threshold: -60 dBFS
- hard-boundary review RMS: -24 dBFS
- discontinuity threshold: 0.15 normalized full scale
- fade tolerance: permit one non-monotonic sub-window before marking `no_fade_evidence`

### Findings

- `active_at_start`
- `active_at_end`
- `start_discontinuity`
- `end_discontinuity`
- `no_start_fade_evidence`
- `no_end_fade_evidence`
- `possible_truncated_start`
- `possible_truncated_end`

The `possible_truncated_*` finding requires a combination of evidence, not a single threshold. Default rule: boundary RMS above threshold plus either a discontinuity or absence of fade evidence.

### Flags

```text
--window-ms N
--subwindow-ms N
--active-db DB
--boundary-rms-db DB
--discontinuity X
--fade-tolerance N
--side start|end|both
```

### Pipeline examples

```bash
find renders -type f -name '*.wav' -print0 |
  xargs -0 -n1 bash/edgeguard.sh --format tsv --no-header |
  awk -F '\t' '$6 == "review"'
```

## Tool 2: subphase.sh

### Purpose

Analyze stereo correlation and balance only below a user-selectable crossover frequency so bass/sub compatibility can be inspected independently from the rest of the stereo image.

### Inputs

Stereo audio only. Non-stereo inputs return exit 2 unless `--allow-mono` is explicitly set, in which case mono produces an informational summary and no phase findings.

### Signal path

1. Decode stereo audio through FFmpeg.
2. Low-pass both channels at the configured crossover frequency using the same filter topology/order.
3. Divide into fixed windows.
4. Exclude windows whose low-band RMS is below the active threshold.
5. For each active window calculate normalized Pearson-style correlation from decoded float samples.
6. Calculate left/right low-band RMS balance.
7. Merge adjacent windows that remain below configured correlation thresholds.

### Defaults

- crossover: 120 Hz
- window: 250 ms
- active threshold: -55 dBFS
- weak correlation threshold: +0.20
- negative correlation threshold: 0.00
- critical correlation threshold: -0.50
- minimum run duration: 500 ms
- imbalance warning: 4 dB

### Findings

- `weak_sub_correlation`
- `negative_sub_correlation`
- `critical_sub_correlation`
- `sub_balance_imbalance`
- `sub_phase_regime_change`

Correlation is evidence only; the tool must not claim that a creative stereo bass treatment is wrong.

### Flags

```text
--crossover-hz N
--window-ms N
--active-db DB
--weak-correlation X
--negative-correlation X
--critical-correlation X
--min-run-ms N
--imbalance-db DB
--allow-mono
```

## Tool 3: banddrift.sh

### Purpose

Create a time-coded ledger of changing spectral balance relative to the same file's median behaviour. It identifies unusual tonal sections without attempting reference matching or automatic EQ.

### Signal path

1. Decode/measure using FFmpeg filter graphs.
2. Split audio into configurable bands.
3. Produce RMS energy per band per window.
4. Convert energy to dBFS.
5. Convert each band's energy to a relative share of active-band energy for that window.
6. Calculate per-band median share across active windows.
7. Calculate absolute deviation from median per window.
8. Flag windows exceeding configured deviation.
9. Merge adjacent compatible findings.

### Default bands

```text
sub       20-80 Hz
bass      80-250 Hz
lowmid    250-1000 Hz
highmid   1000-5000 Hz
high      5000-20000 Hz
```

Band edges are configurable with repeated `--band NAME:LOW:HIGH` arguments. Bands may not overlap in version 1.

### Defaults

- window: 1.0 s
- active threshold: -60 dBFS combined
- deviation: 8 percentage points of relative energy share
- minimum run: 2 windows

### Findings

- `band_share_high`
- `band_share_low`
- `broad_tonal_shift`

`broad_tonal_shift` requires at least two bands to exceed deviation thresholds in the same directionally meaningful redistribution.

### Flags

```text
--window-ms N
--band NAME:LOW:HIGH        # repeatable
--deviation-pct N
--active-db DB
--min-run-windows N
--top N
```

## Tool 4: repeataudit.sh

### Purpose

Detect unexpectedly repeated exact decoded-audio blocks that can indicate capture-buffer repetition, accidental duplicate concatenation, or frozen digital regions. It intentionally looks for exact repeated decoded PCM, not musical similarity.

### Signal path

1. Decode audio to canonical signed 16-bit PCM preserving channel count.
2. Split PCM into fixed-size blocks aligned to sample frames.
3. Hash each block using SHA-256 when available, falling back to platform SHA-256 command variants.
4. Record block index and hash.
5. Find adjacent identical blocks and repeated non-adjacent runs.
6. Verify candidate hash matches by byte comparison before reporting, eliminating hash-collision assumptions.
7. Merge adjacent repeated block sequences.

### Defaults

- block duration: 100 ms
- minimum adjacent repeated duration: 300 ms
- non-adjacent search enabled
- minimum non-adjacent repeated duration: 500 ms
- ignore blocks whose RMS is below -70 dBFS, preventing silence from dominating the report
- maximum decoded size: configurable; default 4 GiB temporary PCM guard

### Findings

- `adjacent_exact_repeat`
- `nonadjacent_exact_repeat`
- `long_exact_repeat`

### Flags

```text
--block-ms N
--min-adjacent-ms N
--min-nonadjacent-ms N
--ignore-below-db DB
--adjacent-only
--max-decoded-bytes N
--hash-command auto|sha256sum|shasum
```

### Performance constraints

Non-adjacent matching must avoid O(n^2) pairwise comparison. The implementation groups hashes with `sort`/`awk` and verifies only duplicate-hash candidates.

## Tool 5: samplefreeze.sh

### Purpose

Detect runs where decoded PCM remains exactly or nearly unchanged for an implausibly long time, including non-zero frozen values that ordinary silence detectors miss.

### Signal path

1. Decode to signed PCM or float PCM according to mode.
2. Examine each channel independently.
3. Compare each sample with the preceding sample.
4. Exact mode: sample values must match exactly.
5. Near mode: absolute delta must remain below tolerance.
6. Track contiguous runs and merge across channels for summary output.
7. Distinguish near-zero runs from non-zero frozen runs.

### Defaults

- exact mode
- minimum run: 20 ms
- minimum absolute level for a non-zero freeze: -80 dBFS
- near-mode tolerance: disabled unless requested

### Findings

- `exact_sample_freeze`
- `near_sample_freeze`
- `zero_flatline`
- `multichannel_freeze`

### Relationship to existing tools

This differs from existing `railruns`, which detects consecutive samples near full scale. `samplefreeze` detects unchanged or nearly unchanged sample values at any level.

### Flags

```text
--min-run-ms N
--near-tolerance X
--min-level-db DB
--channel N|all
--include-zero
```

## Tool 6: transientledger.sh

### Purpose

Create a timestamped transient-density and crest-factor timeline suitable for comparing sections or batch exports without opening a DAW.

### Signal path

For each analysis window:

1. Decode/measure peak and RMS.
2. Calculate crest factor `peak_dBFS - rms_dBFS`.
3. Derive a short-term energy envelope using smaller sub-windows.
4. Count transient candidates where the positive envelope delta exceeds a configurable dB threshold and the transient is separated by the minimum spacing.
5. Calculate transient density as events per second.
6. Compare window density and crest factor against file medians.
7. Merge adjacent low/high-density review regions.

### Defaults

- analysis window: 2 s
- envelope sub-window: 10 ms
- transient rise threshold: +6 dB
- minimum transient spacing: 30 ms
- active threshold: -60 dBFS
- density deviation threshold: 60% relative to active-window median
- crest deviation threshold: 6 dB

### Findings

- `transient_density_low`
- `transient_density_high`
- `crest_factor_low`
- `crest_factor_high`
- `transient_regime_change`

This tool reports relative structure. It does not label material over-compressed or under-compressed.

### Flags

```text
--window-ms N
--envelope-ms N
--rise-db DB
--min-spacing-ms N
--active-db DB
--density-deviation-pct N
--crest-deviation-db DB
--top N
```

## Batch and composition workflows

The project page must show that these are designed to be combined with ordinary Unix tools.

Examples:

```bash
# Find suspiciously chopped renders
find export -type f -name '*.wav' -print0 |
  xargs -0 -n1 bash/edgeguard.sh --format tsv --no-header |
  awk -F '\t' '$0 ~ /possible_truncated/'

# Show only negative-correlation bass windows
bash/subphase.sh mix.wav --format tsv |
  awk -F '\t' '$0 ~ /negative_sub_correlation|critical_sub_correlation/'

# Rank tonal drift events by magnitude
bash/banddrift.sh master.wav --format tsv |
  sort -t $'\t' -k8,8nr |
  head -20

# Audit a recorder capture for repeated blocks and frozen samples
bash/repeataudit.sh capture.wav --format jsonl > repeats.jsonl
bash/samplefreeze.sh capture.wav --format jsonl > freezes.jsonl
cat repeats.jsonl freezes.jsonl | grep -v '"event":"summary"'

# Compare transient character across a sample pack
find pack -type f -name '*.wav' -print0 |
  xargs -0 -n1 bash/transientledger.sh --format tsv --no-header > transient-pack.tsv
```

## Detailed per-tool documentation

Each `spec/<tool>.md` page must contain:

1. purpose and workflow gap
2. dependencies
3. exact CLI syntax
4. complete flag/default table
5. signal/data flow
6. formulas
7. event taxonomy
8. text output example
9. TSV schema
10. JSONL schema/examples
11. exit-code rules
12. pipeline examples
13. performance characteristics
14. limitations and false-positive cases
15. implementation internals
16. testing notes

## GitHub Pages integration

Update the existing site to add a dedicated `Bash pipeline tools` collection.

Each card must show:

- Beta badge
- tool name
- one-sentence purpose
- key dependencies
- one standalone invocation
- one pipeline invocation
- principal event types
- link to full specification/internals
- direct link to raw `.sh` source

The page must explicitly distinguish these from the existing Python/JavaScript WAV utilities. It must not state that no comparable software exists anywhere. Preferred wording: these tools target specialized combinations and pipeline workflows for which research did not identify a well-established standalone command with the same narrow purpose.

## Testing strategy

Tests generate all fixtures at runtime with FFmpeg and standard wave-generation filters. No third-party audio fixture is committed.

### General CLI tests for every tool

- `--help` returns 0 without an input
- `--version` returns 0
- missing input returns 2
- unreadable/nonexistent input returns 2
- missing FFmpeg/FFprobe produces a clear dependency error
- invalid numeric values return 2
- paths containing spaces work
- text output works
- TSV parses with stable column count
- `--no-header` suppresses only the header
- JSONL contains one valid object per non-empty line
- `--output` uses atomic write behaviour
- source file checksum and timestamps remain unchanged
- temp files are removed on success and ordinary failure
- Ctrl-C cleanup is covered where practical

### edgeguard fixtures

Generate:

- tone that starts abruptly at sample 0
- tone with 100 ms fade-in
- tone ending abruptly
- tone with fade-out
- signal with leading/trailing silence
- percussive sound naturally beginning near zero crossing

Assert that combination rules distinguish clean fades from hard boundaries.

### subphase fixtures

Generate stereo files with:

- in-phase 60 Hz tone
- 180-degree inverted right-channel 60 Hz tone
- unrelated high-frequency stereo content but mono sub
- mono high-frequency content but inverted sub
- known low-band imbalance
- silence/near-silence

Assert correlation categories and timestamps within one analysis window tolerance.

### banddrift fixtures

Generate a file containing consecutive sections dominated by:

- 60 Hz
- 500 Hz
- 3 kHz
- 10 kHz

Plus a stable broadband control. Assert correct band redistribution events and no large drift finding for the stable control.

### repeataudit fixtures

Generate:

- normal varying audio
- exact adjacent repeated PCM block
- non-adjacent repeated region
- long silence only
- repeated low-level silence-like block

Assert silence filtering, exact byte verification, and run merging.

### samplefreeze fixtures

Generate:

- constant non-zero PCM segment
- exact digital zero segment
- slowly varying near-flat segment
- ordinary sine wave
- multichannel file where one channel freezes and the other continues

Assert channel-aware events and exact/near modes.

### transientledger fixtures

Generate:

- impulse train
- sustained sine
- noise burst sequence
- alternating transient-dense and sustained sections
- near-silent control

Assert relative density and crest regimes rather than brittle exact counts across FFmpeg versions.

## CI

Extend GitHub Actions on Ubuntu to install/verify FFmpeg and execute the Bash pipeline tests. Existing Python/Node/browser tests remain unchanged. Bash test coverage is required on Ubuntu; macOS Bash compatibility may be smoke-tested separately but Bash 3.2 is not a supported target.

Shell syntax/static checks:

- `bash -n bash/*.sh bash/lib/*.sh`
- `shellcheck` when available in CI

Runtime test harness:

```bash
python -m unittest tests.test_bash_pipeline_tools -v
```

Full repository verification remains:

```bash
python -m unittest discover -s tests -v
python scripts/package.py
```

## Audit requirements after implementation

A complete post-build audit is mandatory before completion is claimed.

### 1. Spec-to-code audit

For every requirement in this document and every per-tool spec:

- implemented
- tested
- documented
- or explicitly deferred with rationale

No silent omissions.

### 2. Shell correctness audit

Inspect for:

- quoting errors
- word splitting
- glob expansion hazards
- unsafe `eval`
- command-injection paths
- unchecked temporary files
- `set -e` surprises
- pipeline exit-status loss
- locale dependence
- integer overflow in shell arithmetic
- filenames beginning with `-`
- filenames containing whitespace
- traps that mask original exit codes
- partial report files

### 3. Algorithm audit

Verify formulas manually against small deterministic fixtures. Review threshold direction, dB conversion, sample/frame byte arithmetic, time conversion, median calculations, run merging, window-end handling, and inactive-window exclusion.

### 4. False-positive audit

Run controls designed to *not* trigger each heuristic and document any expected borderline behaviour.

### 5. Performance audit

Measure representative short and long synthetic files. Confirm no accidental quadratic loops. In particular, verify `repeataudit` groups hash candidates rather than pairwise comparing all blocks.

### 6. Output-contract audit

Validate:

- text readability
- TSV column stability
- TSV escaping
- JSONL correctness
- stderr/stdout separation
- deterministic ordering
- exit codes

### 7. Dependency audit

Run with intentionally masked optional commands to confirm documented fallback paths and clean dependency errors.

### 8. Documentation/site audit

Verify every page command matches the actual CLI, every linked source/spec exists, raw download links work, Beta labeling is present, and novelty wording remains evidence-based.

### 9. Regression audit

Run all pre-existing repository tests and packaging after the new family passes its own tests.

### 10. Final audit record

Write results to `docs/BASH_PIPELINE_AUDIT.md` with:

- date
- commit tested
- environment/tool versions
- commands run
- test counts
- failures discovered
- fixes applied
- known limitations
- acceptance-criteria matrix

## Acceptance criteria

Implementation is complete only when all of the following are true:

1. All six Bash tools exist and are executable.
2. No Bash runtime script invokes repository Python or JavaScript engines.
3. Shared shell libraries exist and are used where appropriate.
4. Text, TSV, and JSONL contracts work as specified.
5. All six tools have per-tool documentation/spec pages.
6. Synthetic functional tests cover positive and negative controls.
7. `bash -n` passes on all Bash sources.
8. Shellcheck passes or every remaining warning is documented and justified.
9. GitHub Actions runs the Bash test suite.
10. Existing repository tests still pass.
11. README includes the Bash tool family.
12. GitHub Pages features all six tools and pipeline examples.
13. All new tools are labelled Beta.
14. Research/novelty wording does not make unsupported universal claims.
15. The full post-build audit is completed and committed as `docs/BASH_PIPELINE_AUDIT.md`.
16. Any bug or missing implementation discovered during the audit is fixed and tests are rerun before completion is claimed.
