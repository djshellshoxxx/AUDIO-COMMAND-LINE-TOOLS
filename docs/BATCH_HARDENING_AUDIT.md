# Batch audio hardening audit — 2026-10-03

This second-pass audit covers `onsetpack`, `phasebatch`, `packdelta`, and `edgeguard` after their initial merge. It was performed independently of the original happy-path suite and focused on adversarial numeric inputs, pathological search windows, filesystem aliasing, source immutability, and specification/implementation mismatches.

## Reproduced defects and fixes

1. **Oversized phase search windows.** `phasebatch` could iterate offsets with zero-length overlap when `--max-shift-ms` exceeded the available audio, producing large numbers of NumPy runtime warnings. Positive and negative searches are now bounded independently to offsets retaining at least two overlapping frames.
2. **Non-finite numeric options.** `nan` and `inf` values were accepted by the float parser. `inf` could escape the CLI error path as `OverflowError`, while `nan` thresholds could silently alter analysis. Threshold, pre-roll, phase-window, and fade values are now required to be finite before arithmetic.
3. **Zero-duration edge repair.** `edgeguard` accepted `fade_ms=0`, but the implementation forced a one-frame fade and zeroed edge samples. Repair fade duration must now be finite and greater than zero.
4. **Report path aliasing.** JSON and CSV could target the same resolved path. With overwrite enabled, the CSV write could replace the JSON report. Identical resolved report paths are rejected before either file is written.
5. **Output-tree symlink escape.** A nominally separate output tree could contain a symlink that redirected a generated relative path back into the input tree. With overwrite enabled this violated the source-immutability guarantee. Every transformed output path is now resolved and rejected if it escapes the selected output tree or resolves into the source tree. Direct `repair_edges()` calls also reject an output path resolving to the input file.
6. **`packdelta` precision wording.** The implementation intentionally canonicalizes decoded samples into a 24-bit-equivalent integer domain, but earlier documentation described that as exact decoded-content identity. The behavior is retained; the specification now accurately states that differences below the canonical 24-bit-equivalent step can compare equal.

## Additional testing

The new `tests/test_batch_tools_audit.py` regression layer covers:

- phase windows longer than the source without runtime warnings;
- negative delay plus polarity inversion;
- non-finite threshold, pre-roll, phase-window, and fade values;
- CLI handling of `--max-shift-ms inf` with normal error exit code;
- zero-duration fade rejection;
- direct source replacement rejection;
- JSON/CSV output path collision rejection;
- symlinked output paths attempting to redirect into the input tree;
- quiet onset files remaining untrimmed.

A separate randomized local phase test exercised 100 combinations of source length, positive and negative integer delays, and polarity inversion. No delay-sign or polarity mismatches were observed after the fix.

## Performance observation

The current `phasebatch` implementation uses a direct time-domain correlation scan. A local probe of a 10-second, 48 kHz mono pair with a ±10 ms search window took approximately 4.6 seconds in the audit environment. This is a performance limitation rather than a correctness failure. The beta documentation now calls out that long files and wide search windows can be computationally expensive. An FFT-based correlation path should be treated as a separate design/performance change rather than folded into this correctness hardening pass.

## Verification scope

The repository pull-request workflow runs the full Python/JavaScript native suite and packaging on Ubuntu, Windows, and macOS, including these new regressions, and separately runs the Chromium browser/responsive suite. Final merge should only occur after those checks succeed on the rebased hardening branch.
