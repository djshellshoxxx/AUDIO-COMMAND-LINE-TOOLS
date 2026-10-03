# Program audit — October 2026

This audit covers all fourteen beta-stage tools, their specifications and advertised flags, both existing shared engines, the four new batch entry points, packaging, and the GitHub Pages workbench. The original ten-tool audit remains applicable; the batch-tool audit below records the additional defects found and fixed during this expansion.

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

## Shared audit findings

- All fourteen tools are visibly marked **BETA** in the README/site presentation. The ten browser catalog entries also carry explicit beta metadata/titles.
- Batch analysis is read-only. Optional transformed audio must be written outside the input tree, preventing recursive re-ingestion or accidental source replacement.
- Batch JSON and CSV report files no longer overwrite existing files unless `--overwrite` is explicit.
- Batch scanning requires a directory and accepts `.wav` case-insensitively through recursive subdirectories.
- Batch transformed outputs preserve relative paths and use 16-bit PCM WAV. Unsupported/compressed WAV input fails explicitly.
- `packdelta` uses decoded audio identity rather than container metadata and reports duplicate families separately from version classifications.
- Existing JavaScript CLI behavior retains the prior strict argument parsing, WAV validation, output-alias protection, bounded reports, and browser-input validation from the original audit.
- `scripts/package.py` discovers every Python file and every `spec/*.md` automatically, so the four new entry points, shared batch engine, and new specs are included in the Python download bundle without a special-case package list.

## Regression coverage

The existing native suite had 68 tests. `tests/test_batch_tools.py` adds fourteen synthetic regression tests covering onset/preroll, source immutability, nested-output rejection, phase delay/polarity, silent phase tie-breaking, required correction/repair output paths, pack classifications and duplicates, pack CSV rows, edge detection/repair, overwrite protection, recursive discovery, directory validation, and invalid negative time parameters.

The repository workflow runs `python -m unittest discover -s tests -v` and `python scripts/package.py` on Ubuntu, Windows, and macOS. A separate Chromium/Playwright job packages the site and exercises the browser workflows and responsive layout. Final test/deployment status is recorded by GitHub Actions for the merge commit.

## Intentional limits

The original tool limits remain documented in [COMMON](../spec/COMMON.md). The batch tools currently accept uncompressed PCM WAV 8/16/24/32-bit and write transformed audio as 16-bit PCM. `phasebatch` is integer-sample time-domain correlation/polarity alignment rather than fractional or frequency-dependent phase correction. `packdelta` is exact decoded-content comparison, not perceptual fingerprinting. `edgeguard` treats file boundaries only, not internal clicks. `onsetpack` uses an amplitude threshold rather than a learned/perceptual onset detector.

This audit reduces known implementation/specification gaps; it is not a claim of exhaustive proof of correctness or perceptual audio quality.
