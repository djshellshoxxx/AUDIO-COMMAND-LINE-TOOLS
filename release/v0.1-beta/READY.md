# Shell-native v0.1 Beta release gate

This marker triggers the one-time v0.1 Beta release workflow for the seven FFmpeg/FFprobe-backed shell-native tools:

- stereotruth
- loudwalk
- formattruth
- albumcontract
- phasewatch
- batchsilence
- transcodeaudit

Release QA requirements:

1. Bash syntax checks pass for all Bash entrypoints and shared libraries.
2. The shell-native regression/parity suite passes with FFmpeg/FFprobe and PowerShell 7 available.
3. Deferred draft CLI switches that previously had no analysis effect are rejected rather than silently accepted.
4. Invalid Bash numeric thresholds fail with command-error exit status 2.
5. JSON output-to-file is parsed during regression testing.
6. Source-audio immutability remains verified by the existing test harness.
7. Each release is published as a GitHub prerelease with one ZIP containing Bash, PowerShell, shared helpers, the matching specification, and LICENSE.

Target version: v0.1 Beta.
