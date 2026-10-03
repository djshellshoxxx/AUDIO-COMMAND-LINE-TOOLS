# Validation

The regression suite has 68 tests with additional subcases. Fixtures are generated from known sample values; no copyrighted audio or external files are required.

## Engine checks

- Audit regressions: empty/missing flag values, strict decimal tokens, option terminators, Unicode basename ordering, symlink parent aliases, output-parent preflight, aggregate input limits, report limits, constant correlation, sub-floor gain budgets, quantized ceilings, cue origins, cross-chunk runs, quiet flank precision, active threshold bounds, and malformed fmt extensions.
- Musical frame counts, seam jumps, and single-frame loops.
- Last activity, per-channel activity, quiet tails, retained padding, and all-quiet input.
- Stereo polarity inversion, identical channels, silence, and non-stereo rejection.
- Interior quiet gaps, active flanks, edge exclusions, and channel-specific quiet samples.
- Channel-specific threshold runs and short transient exclusion.
- Global DC versus local offset windows.
- Requested gain and ceiling budget; silent inputs; refused unsafe exports.
- Explicit/inherited stem contracts, missing names, duplicate basenames, and silent stems.
- Independent cue rounding, origin/spacing, and entry cap.
- Identical renders, changed sections, positive/negative sample offsets, unmatched frames, incompatible formats, and no overlap.
- Python/JavaScript report agreement for all ten tools and custom flags.
- Byte-identical PCM exports for all five export tools.
- Report paths, overwrite flags, input protection (including hard links), help text, missing paths, unknown flags, nonfinite and pathological numeric flags.
- PCM 8/16/24/32, float 32/64, extensible PCM/float, ancillary chunks, truncated headers, invalid format metadata, nonfinite/extreme samples.
- Unified entry points, equals-form flags, Bash launcher, and Windows PowerShell/batch launchers with spaces in input paths.

Run: `python -m unittest discover -s tests -v`. GitHub Actions runs it on Ubuntu, Windows, and macOS with Python 3.11 and Node 22. Local development used NumPy 2.3.5 and Node 24.

## Browser checks

`tests/browser.cjs` uses Playwright/Chromium. It exercises all ten tools through the workbench with synthetic audio, JSON downloads, processed WAV downloads, real file uploads, malformed files, missing files, ceiling enforcement before export and after PCM rounding, catalog-load failure controls, stale-result reset, bundle downloads, specification links, skip-link keyboard navigation, and page overflow at 320/768/1024/1440 px. Browser page errors fail the test. The workflow records a full-page screenshot as the `browser-preview` artifact.

The browser, CLI, and Python suite cover deterministic processing. Listening quality remains a user judgement: thresholds do not establish a fault, sample peaks are not true peaks, and the suite does not claim hardware audio-device or DAW integration testing.

## Downloads and deployment

`python scripts/package.py` creates deterministic Python and JavaScript ZIP bundles and copies specs/research for the static site. ZIP integrity is checked during development, and the browser suite downloads both bundles. GitHub Pages deployment depends on both the engine and browser jobs succeeding.

[Latest workflow results](https://github.com/djshellshoxxx/AUDIO-COMMAND-LINE-TOOLS/actions)
