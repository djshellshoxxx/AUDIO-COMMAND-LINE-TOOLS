# Codebase Map: where to find what

| I want to... | Look in |
|---|---|
| Original Python engine and tools | `python/` (`drift_audio.py`, one entry per tool) |
| Batch tools | `python/batch_audio.py` and the four batch entry points |
| Python tests | `tests/test_tools.py`, `test_batch_tools*.py` |
| Go CDL tool | `go/internal/cdl/` (`cli.go`, `ffmpeg.go`, `findings.go`, `report.go`), tests in `cdl_test.go` |
| Bash QC tools and shared helpers | `bash/` (tools), `bash/lib/` (`common.sh`, `ffmpeg.sh`, `json.sh`) |
| Shell-native regression tests | `tests/test_shell_native_*.py` |
| PowerShell tools (WinAudioForensics, QC) | `powershell/` |
| PowerShell tests | `tests/winaudioforensics.tests.ps1` |
| Browser workbench | `site/` (`site/js`, `site/spec`, `site/docs`) |
| Per-tool specifications | `spec/` |
| Packaging and release scripts | `scripts/`, `shared/scripts/`, `release/` |
| Audits and research | `docs/` (`AUDIT.md`, `RESEARCH.md`, `VALIDATION.md`, `WINAUDIOFORENSICS*.md`) |
| CI | `.github/workflows/` |
| Licence and trademark | `LICENSE` (MIT), `COPYRIGHT-TRADEMARK.md` |
