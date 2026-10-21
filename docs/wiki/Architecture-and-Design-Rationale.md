# Architecture and Design Rationale

Sources: README, `docs/RESEARCH.md`, `docs/AUDIT.md`, `docs/superpowers/specs/`. *(inferred)* marks conclusions from the layout.

- **Several implementations of the same tools.** The repo has Python, Node/browser, Go, Bash and PowerShell versions. *(inferred: each host environment is served without requiring a runtime the user lacks; the README calls the shell and PowerShell tools "FFmpeg/FFprobe-powered QC workflows".)*
- **Evidence, not verdicts.** Reports state what was measured. The README repeats that `transcodeaudit` cannot prove history and that correlation is not proof of a fault.
- **Shell-native parity.** Bash and PowerShell tools are kept in parity, with cross-shell tests in CI.
- **Shared helpers.** `bash/lib/common.sh`, `ffmpeg.sh` and `json.sh` are shared by the Bash tools; `python/drift_audio.py` is the engine for the original Python tools.
- **Research before building.** `docs/RESEARCH.md` documents existing alternatives, and the README says no third-party source or audio is copied.
- **Formats are explicit.** Supported WAV variants and limits are written down in `spec/COMMON.md`, not implied.
