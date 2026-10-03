# Launcher, not a native PowerShell audio engine. Requires Python and NumPy.
& python (Join-Path $PSScriptRoot 'drift_audio.py') @args
exit $LASTEXITCODE
