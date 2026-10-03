# Program audit — October 2026

This audit covers all fifteen beta-stage tools, their specifications and advertised flags, the shared audio engines, the four batch entry points, WinAudioForensics, packaging, and the GitHub Pages workbench. The original ten-tool and batch-tool audits remain applicable; the WinAudioForensics section records the additional implementation, integration, and test findings from the PowerShell expansion.

## Original ten tools

| Program | Findings and fixes |
|---|---|
| loopbudget | No tool-specific calculation defect reproduced. Shared strict numeric parsing, WAV validation, and output-path fixes apply. |
| tailbudget | No tool-specific trimming defect reproduced. Shared WAV/output checks and byte-identical export regressions apply. |
| monoledger | Constant nonzero channels produced correlation even though variance is zero. Return null; bound finite correlation and cap window counts. |
| gapcontext | Active-flank threshold accepted invalid values; event generation was unbounded and repeated flank scans costly. Validate -240..0, cap entries, use cumulative energy with a direct-summation fallback for very quiet context after loud audio. |
| railruns | Threshold masks created potentially huge eager span lists. Stream spans, preserve runs crossing chunk boundaries, and cap event entries. |
| dcjourney | Tiny windows could produce excessive reports. Reject more than 100000 analysis windows before processing. |
| gainbudget | Safe gain used the display-floor peak for extremely quiet audio; PCM rounding could exceed the requested ceiling. Compute gain from the actual peak and bound quantized export integers, including browser exports. |
| stemcontract | Empty expected names were accepted; Unicode missing-name ordering differed between ports. Reject empty names and match code-point ordering. |
| cueclock | Entry-limit check ignored the selected origin. Account for origin and rounded endpoint; origins after the source return an empty grid. |
| renderdelta | Tiny windows could create excessive reports and allocate a residual first. Validate the window limit before allocation. Correct the two-input example. |

## New batch tools

| Program | Audit findings and corrections |
|---|---|
| onsetpack | Verified recursive/case-insensitive WAV discovery, threshold onset, pre-roll arithmetic, source immutability, and output-tree preservation. Added explicit rejection of negative pre-roll, non-directory inputs, and output trees nested inside their source tree. Files without a threshold crossing remain untrimmed. |
| phasebatch | Verified integer-delay and polarity detection against synthetic delayed/inverted audio. Silent/constant material initially tied at every shift and selected the first negative extreme; tie-breaking now prefers the smallest absolute delay, so silence reports zero. `--correct` now requires an output directory before analysis, nested output trees are rejected, negative search ranges are rejected, and sample-rate mismatches fail rather than resampling. |
| packdelta | Duplicate content initially made rename pairing ambiguous. Exact-content candidates are now paired deterministically by filename similarity then lexical order. Inventory decoding was reduced from twice per file to once. `--csv` initially had no flat row representation; the report now includes a deterministic `changes` ledger and CSV export for unchanged/modified/added/removed/renamed entries. Non-directory roots fail explicitly. |
| edgeguard | Verified boundary peak/slope detection and separate-output micro-fade repair. `--repair` now requires an output directory up front, nested output trees are rejected, negative fade lengths fail explicitly, and existing output files remain protected unless `--overwrite` is supplied. |

## WinAudioForensics audit — 2026-10-03

WinAudioForensics was audited against `spec/winaudioforensics.md`, its CLI help, user guide, research note, automated tests, Windows smoke behavior, packaging, and Pages integration.

### Scope and PowerShell fit

The implementation stays within the intended Windows-native evidence workflow. It collects Windows Audio service state, audio-related CIM/PnP devices, signed-driver metadata, MMDevices endpoint registry metadata, Core Audio default roles, and optional recent event records. PowerShell is used where it has a material platform advantage rather than as a wrapper around the existing Python DSP engine.

Existing tools reviewed during the demand check already cover default-device switching, profiles, volume, routing, exclusive mode, and related configuration. WinAudioForensics therefore remains focused on preserving, comparing, and reporting evidence over time instead of duplicating those configuration tools.

### Read-only and mutation audit

- The PowerShell collectors use CIM/service queries, registry reads, Windows event-log reads, and Core Audio enumeration.
- The embedded Core Audio interop exposes enumeration/default-endpoint reads only; it contains no default-device setter or configuration mutation method.
- The beta does not enable/disable PnP devices, start/stop services, edit MMDevices keys, install/uninstall drivers, or change sample format/exclusive-mode settings.
- Filesystem writes are limited to JSON reports, watch snapshots/diffs, and the requested downloadable package.
- Doctor findings explicitly describe correlation/evidence and do not claim that a temporally adjacent change caused the reported audio problem.

### Data model and deterministic behavior

- Snapshot and diff schemas are versioned.
- PnP devices, drivers, endpoints, defaults, and services use stable comparison keys documented in the spec.
- Change records sort by type and key for deterministic automation/source-control use.
- The state fingerprint intentionally excludes capture timestamp, event payloads, and collector warnings, so watch mode does not write a new state merely because volatile evidence changed.
- Optional collector failures are isolated into snapshot warnings instead of discarding evidence collected successfully from other sources.

### Defects and integration issues found during the audit

1. The first PowerShell test harness revision contained four malformed assertion calls. The test syntax was corrected before treating any implementation result as valid.
2. The initial documentation claimed Windows PowerShell 5.1 compatibility while the implementation/test contract was actually PowerShell 7 oriented. The supported beta runtime was narrowed to PowerShell 7+ so the public contract matches CI.
3. Expanding the Pages navigation and feature sections exposed a real 320 px horizontal overflow. The responsive layout was hardened with zero-minimum grid tracks, narrower mobile navigation, wrap-safe buttons/text, and single-column controls at phone width. The 320/768/1024/1440 browser regression now passes.
4. `main` changed concurrently while the feature was being built, adding the four batch tools. The PowerShell feature branch was rebuilt on that newer main instead of overwriting it. The final diff preserves the batch tools and layers WinAudioForensics on top.
5. Packaging originally produced only the Python and JavaScript archives. `scripts/package.py` now creates a reproducible `cdl-winaudioforensics-powershell.zip` containing the CLI/module plus common documentation/specs.
6. The existing browser integration test originally knew about two bundles and ten specs. It now verifies the PowerShell bundle, WinAudioForensics guide/spec, all four batch specs, existing browser flows, and narrow viewport geometry.

### WinAudioForensics regression coverage

`tests/winaudioforensics.tests.ps1` uses synthetic before/after fixtures plus a real Windows collection smoke test. It covers:

- v1 snapshot schema acceptance/rejection;
- device addition and device-status/problem changes;
- driver addition/version changes;
- endpoint addition;
- default-role changes;
- service-state changes;
- deterministic change ordering;
- doctor rules for stopped audio services, PnP problems, default changes, and driver changes;
- state fingerprint volatility exclusions;
- CLI help success;
- an actual Windows `snapshot -Compact` invocation whose stdout must parse as v1 JSON with all required top-level collections.

The Windows CI job runs the existing Python suite first, then the PowerShell regression/smoke suite, then the packaging build. Linux and macOS continue to run the existing audio suite and packaging. Chromium exercises all ten browser tools, the generated download bundles, published spec/guide resources, error paths, download behavior, and responsive viewport checks.

## Shared audit findings

- All fifteen tools are visibly marked **BETA** in the README/site presentation. The ten browser catalog entries also carry explicit beta metadata/titles.
- Batch analysis is read-only. Optional transformed audio must be written outside the input tree, preventing recursive re-ingestion or accidental source replacement.
- WinAudioForensics is read-only with respect to Windows audio configuration and writes only requested reports/watch evidence.
- Batch JSON and CSV report files no longer overwrite existing files unless `--overwrite` is explicit.
- Batch scanning requires a directory and accepts `.wav` case-insensitively through recursive subdirectories.
- Batch transformed outputs preserve relative paths and use 16-bit PCM WAV. Unsupported/compressed WAV input fails explicitly.
- `packdelta` uses decoded audio identity rather than container metadata and reports duplicate families separately from version classifications.
- Existing JavaScript CLI behavior retains the prior strict argument parsing, WAV validation, output-alias protection, bounded reports, and browser-input validation from the original audit.
- `scripts/package.py` discovers every Python file and every `spec/*.md` automatically and now additionally builds the native PowerShell bundle when the `powershell/` directory exists.

## Regression coverage

The existing native suite had 68 tests before the batch expansion. `tests/test_batch_tools.py` adds fourteen synthetic regression tests covering onset/preroll, source immutability, nested-output rejection, phase delay/polarity, silent phase tie-breaking, required correction/repair output paths, pack classifications and duplicates, pack CSV rows, edge detection/repair, overwrite protection, recursive discovery, directory validation, and invalid negative time parameters. WinAudioForensics adds a separate PowerShell regression/smoke suite as described above.

The repository workflow runs `python -m unittest discover -s tests -v` and `python scripts/package.py` on Ubuntu, Windows, and macOS. Windows additionally runs `tests/winaudioforensics.tests.ps1`. A separate Chromium/Playwright job packages the site and exercises the browser workflows, three downloadable bundles, documentation resources, and responsive layout. Final test/deployment status is recorded by GitHub Actions for the merge commit.

## Intentional limits

The original tool limits remain documented in [COMMON](../spec/COMMON.md). The batch tools currently accept uncompressed PCM WAV 8/16/24/32-bit and write transformed audio as 16-bit PCM. `phasebatch` is integer-sample time-domain correlation/polarity alignment rather than fractional or frequency-dependent phase correction. `packdelta` is exact decoded-content comparison, not perceptual fingerprinting. `edgeguard` treats file boundaries only, not internal clicks. `onsetpack` uses an amplitude threshold rather than a learned/perceptual onset detector.

WinAudioForensics is Windows-only, PowerShell 7+, and intentionally does not measure DPC latency, automate ASIO control panels, alter default endpoints, alter sample/exclusive formats, or prove root cause from temporal correlation. Event/provider availability can vary by Windows and driver stack; unavailable optional evidence is reported as a warning.

This audit reduces known implementation/specification gaps; it is not a claim of exhaustive proof of correctness or perceptual audio quality.
