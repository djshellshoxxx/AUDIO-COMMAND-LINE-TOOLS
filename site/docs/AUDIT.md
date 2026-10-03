# Program audit — October 2026

Audited all ten specifications, Python entry points and shared engine, native JavaScript entry points and engine, shell launchers, and browser worker/workbench. Every advertised tool-specific flag is wired in both engines. Help now explains numeric flags and defaults; corrected two multi-input specification examples.

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

## Shared fixes

- JavaScript CLI rejects empty output values, missing values followed by another flag, and values on boolean switches. Parsing respects `--`, literal values such as `--expect=--help`, decimal integer syntax, and hyphenated flag names.
- Validate output parents and file types before writing an audio result. Detect output aliases through symlink parents as well as existing hard links; never overwrite an input.
- Limit CLI input files to 128 MiB combined (64 MiB per file); retain the browser's 64 MiB combined limit. Window/event limits produce actionable errors instead of unbounded reports.
- Reject malformed WAV fmt extension lengths and single-byte partial extensions in both decoders.
- Reduce JavaScript temporary copies and flattened channel arrays; preserve numerical parity.
- Validate browser input counts before reading files. Disable startup controls until the catalog loads, retaining them disabled if loading fails.

## Evidence

`tests/test_audit.py` adds 27 regression tests to the existing 41, including CLI/API subcases in both languages. `tests/browser.cjs` additionally verifies catalog failure controls and actual downloaded WAV samples against a quiet gain ceiling. The complete native suite passes locally: 68 tests. CI runs the same suite on Ubuntu, Windows, and macOS and the workbench flows in Chromium before Pages deployment. See [Actions](https://github.com/djshellshoxxx/AUDIO-COMMAND-LINE-TOOLS/actions) for published run results.

The intentional format and measurement limits remain documented in [COMMON](../spec/COMMON.md). This review does not claim exhaustive proof of correctness or perceptual audio-quality testing.
