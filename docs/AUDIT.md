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
| packdelta | Duplicate content initially made rename pairing ambiguous. Matching candidates are now paired deterministically by filename similarity then lexical order. Inventory decoding was reduced from twice per file to once. `--csv` initially had no flat row representation; the report now includes a deterministic `changes` ledger and CSV export for unchanged/modified/added/removed/renamed entries. Non-directory roots fail explicitly. |
| edgeguard | Verified boundary peak/slope detection and separate-output micro-fade repair. `--repair` now requires an output directory up front, nested output trees are rejected, negative fade lengths fail explicitly, and existing output files remain protected unless `--overwrite` is supplied. |

## Second batch hardening audit

A second adversarial pass was run after the first merge instead of relying on the original CI result. Five additional code defects and one specification defect were reproduced.

- `phasebatch` accepted search windows longer than the available overlap and iterated through zero-length comparisons, producing potentially thousands of NumPy runtime warnings. The search is now bounded independently for positive and negative offsets so every tested offset retains at least two frames.
- Non-finite numeric values such as `nan` and `inf` were accepted by `argparse`. `inf` could escape normal CLI error handling as `OverflowError`; `nan` thresholds could silently make every onset appear absent. Batch timing and threshold values are now required to be finite before arithmetic.
- `edgeguard` accepted `fade_ms=0` but still zeroed the first and last samples because the implementation forced a one-frame fade. Zero-length repairs are now rejected; repair durations must be finite and greater than zero.
- JSON and CSV outputs could point to the same path. With overwrite enabled, the later CSV write could replace the JSON report. Identical resolved report paths are now rejected before either file is created.
- A separate output root could contain a symlink that redirected a generated relative path back into the input tree. With overwrite enabled this could violate the source-immutability guarantee. Every transformed output path is now resolved before writing and is rejected if it escapes the chosen output tree or resolves into the source tree. Direct `repair_edges()` calls also reject an output path resolving to the source file itself.
- `packdelta` intentionally canonicalizes decoded samples to a 24-bit-equivalent integer domain, but its documentation also described the comparison as bit-exact decoded-content identity. The code behavior is retained for stable cross-bit-depth comparison; the specification now explicitly states the 24-bit-equivalent precision and that smaller high-resolution differences can compare equal.

The new adversarial regression file covers long phase-search windows, negative delay/inversion, non-finite parameters and CLI return codes, zero fade, direct source replacement, JSON/CSV path collisions, output-tree symlink redirection, and quiet onset files. An additional randomized local phase test exercised 100 combinations of clip length, positive/negative integer delay, and polarity with no sign/polarity mismatches after the fix.

A performance probe of the current direct time-domain correlation measured roughly 4.6 seconds for a 10-second 48 kHz mono pair with a ±10 ms search window in the audit environment. This is not a correctness defect, but it makes long files and wide search windows expensive; the limitation is now documented rather than replacing the algorithm with an unreviewed FFT implementation during the hardening pass.

## Shared audit findings

- All fourteen tools are visibly marked **BETA** in the README/site presentation. The ten browser catalog entries also carry explicit beta metadata/titles.
- Batch analysis is read-only. Optional transformed audio must be written outside the input tree, preventing recursive re-ingestion or accidental source replacement; resolved output paths are also checked for symlink escapes.
- Batch JSON and CSV report files no longer overwrite existing files unless `--overwrite` is explicit, and the JSON/CSV paths must differ.
- Batch scanning requires a directory and accepts `.wav` case-insensitively through recursive subdirectories.
- Batch transformed outputs preserve relative paths and use 16-bit PCM WAV. Unsupported/compressed WAV input fails explicitly.
- `packdelta` uses deterministic 24-bit-equivalent decoded-audio identity rather than container metadata and reports duplicate families separately from version classifications.
- Existing JavaScript CLI behavior retains the prior strict argument parsing, WAV validation, output-alias protection, bounded reports, and browser-input validation from the original audit.
- `scripts/package.py` discovers every Python file and every `spec/*.md` automatically, so the four new entry points, shared batch engine, and new specs are included in the Python download bundle without a special-case package list.

## Regression coverage

The original native suite had 68 tests. `tests/test_batch_tools.py` added fourteen synthetic regressions during the batch expansion. `tests/test_batch_tools_audit.py` adds a second adversarial layer covering the newly reproduced failures and additional negative-delay/source-safety cases.

The repository workflow runs `python -m unittest discover -s tests -v` and `python scripts/package.py` on Ubuntu, Windows, and macOS. A separate Chromium/Playwright job packages the site and exercises the browser workflows and responsive layout. CI status for this hardening pass is verified from the pull-request workflow before merge.

## Intentional limits

The original tool limits remain documented in [COMMON](../spec/COMMON.md). The batch tools currently accept uncompressed PCM WAV 8/16/24/32-bit and write transformed audio as 16-bit PCM. `phasebatch` is integer-sample time-domain correlation/polarity alignment rather than fractional or frequency-dependent phase correction, and its current direct search can be slow on long files. `packdelta` is 24-bit-equivalent decoded-content comparison, not a bit-exact high-resolution comparator or perceptual fingerprint. `edgeguard` treats file boundaries only, not internal clicks. `onsetpack` uses an amplitude threshold rather than a learned/perceptual onset detector.

This audit reduces known implementation/specification gaps; it is not a claim of exhaustive proof of correctness or perceptual audio quality.
