@echo off
rem Launcher, not a native batch audio engine. Requires Python and NumPy.
python "%~dp0drift_audio.py" %*
exit /b %ERRORLEVEL%
