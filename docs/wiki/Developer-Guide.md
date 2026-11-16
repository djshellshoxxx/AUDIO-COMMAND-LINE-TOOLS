# Developer Guide

## Test commands (checked on this snapshot)

```sh
python -m unittest discover -s tests -v      # 116 tests: OK, 13 skipped (Python 3.10+, NumPy)
cd go && go test ./...                       # Go CDL tool: passes
```

Windows: `.\tests\winaudioforensics.tests.ps1` (PowerShell 7+; not run here).

Packaging and the browser workbench: `python scripts/package.py`, and `python -m http.server 8000 --directory site`.

CI (`.github/workflows/`) runs the Python/Node suite on Linux, Windows and macOS, WinAudioForensics tests,
a live Windows smoke test, Bash regressions on Ubuntu, and PowerShell QC tests on Ubuntu and Windows.

## Conventions

- Each tool has a spec in `spec/` and tests in `tests/`. Update the spec when behaviour changes.
- Shared Bash code lives in `bash/lib/`; keep the Bash and PowerShell versions in parity (the CI includes cross-shell parity checks).
- Do not copy third-party code or audio into the repository (README "Licence" note).
