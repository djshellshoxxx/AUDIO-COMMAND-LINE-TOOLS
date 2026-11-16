@echo off
rem dropnorm - drag and drop audio FILES or FOLDERS onto this file (or pass them as arguments) for TRUE
rem two-pass EBU R128 loudness normalisation with FFmpeg: measure, then apply in linear mode so the dynamics
rem are untouched. Warns when FFmpeg had to fall back to dynamic (compressing) mode to respect the true-peak
rem ceiling, and re-measures every result. Output: 24-bit WAV at the source sample rate in a "normalised"
rem folder beside each source. Needs ffmpeg.exe + ffprobe.exe on PATH or next to this script.
rem   set DROPNORM_TARGET=-16   (LUFS, default -14)     set DROPNORM_TP=-1.5 (dBTP, default -1)
rem   set NOPAUSE=1             (do not wait for a key at the end)
setlocal EnableExtensions EnableDelayedExpansion
set "HERE=%~dp0" & call set "PATH=%%HERE:~0,-1%%;%%PATH%%"
set "TARGET=-14" & set "TP=-1" & set "LRA=11"
if defined DROPNORM_TARGET set "TARGET=%DROPNORM_TARGET%"
if defined DROPNORM_TP set "TP=%DROPNORM_TP%"
ffmpeg -version >nul 2>nul
if errorlevel 1 (echo ffmpeg.exe not found on PATH or next to this script & goto end)
if "%~1"=="" (echo usage: dropnorm.cmd FILE^|FOLDER ...   ^(or drag and drop^) & goto end)
echo Target %TARGET% LUFS integrated, true peak %TP% dBTP
set /a ok=0, fail=0
:nextarg
if "%~1"=="" goto summary
if exist "%~1\*" (call :folder "%~1") else (call :one "%~f1")
shift
goto nextarg

:folder
for /r "%~1" %%F in (*.wav *.flac *.mp3 *.m4a *.ogg *.aif *.aiff *.opus) do call :maybe "%%~fF"
goto :eof

:maybe
rem skip our own output folder so re-runs never process results again
set "P=%~dp1"
if /i "!P:\normalised\=!"=="!P!" call :one "%~1"
goto :eof

:one
set "IN=%~1" & set "OUTDIR=%~dp1normalised" & set "OUT=%~dp1normalised\%~n1.wav"
set "J=%TEMP%\dropnorm_%RANDOM%%RANDOM%.txt"
if not exist "!OUTDIR!" mkdir "!OUTDIR!"
set "SR="
for /f "delims=" %%r in ('ffprobe -v error -select_streams a:0 -show_entries stream^=sample_rate -of csv^=p^=0 "!IN!"') do set "SR=%%r"
if not defined SR (echo   FAIL %~nx1: no audio stream & set /a fail+=1 & goto :eof)
for %%k in (input_i input_tp input_lra input_thresh target_offset normalization_type) do set "%%k="
ffmpeg -hide_banner -nostdin -i "!IN!" -af loudnorm=I=%TARGET%:TP=%TP%:LRA=%LRA%:print_format=json -f null - 2> "!J!"
for /f "tokens=1,2 delims=:,	 " %%a in ('findstr /c:"input_" /c:"target_offset" "!J!"') do set "%%~a=%%~b"
if not defined input_i (echo   FAIL %~nx1: measurement failed & set /a fail+=1 & del "!J!" 2>nul & goto :eof)
rem FFmpeg treats measured_LRA=0 as "not supplied" and silently drops to dynamic mode; steady material
rem (tones, drones, noise) really measures 0.00, so pass the smallest non-zero value instead.
if "!input_lra!"=="0.00" set "input_lra=0.01"
ffmpeg -hide_banner -nostdin -y -i "!IN!" -af loudnorm=I=%TARGET%:TP=%TP%:LRA=%LRA%:measured_I=!input_i!:measured_TP=!input_tp!:measured_LRA=!input_lra!:measured_thresh=!input_thresh!:offset=!target_offset!:linear=true:print_format=json -ar !SR! -c:a pcm_s24le "!OUT!" 2> "!J!"
if errorlevel 1 (echo   FAIL %~nx1: encode failed & set /a fail+=1 & del "!J!" 2>nul & goto :eof)
for /f "tokens=1,2 delims=:,	 " %%a in ('findstr /c:"normalization_type" "!J!"') do set "%%~a=%%~b"
set "after="
ffmpeg -hide_banner -nostdin -i "!OUT!" -af ebur128=framelog=verbose -f null - 2> "!J!"
for /f "tokens=1,2" %%a in ('findstr /c:"I:" "!J!"') do if "%%a"=="I:" set "after=%%b"
del "!J!" 2>nul
set "NOTE=" & if /i "!normalization_type!"=="dynamic" set "NOTE=  [dynamic mode: true-peak or loudness-range limit blocked plain linear gain]"
echo   OK   %~nx1: !input_i! LUFS ^(TP !input_tp!^) -^> !after! LUFS!NOTE!
set /a ok+=1
goto :eof

:summary
echo.
echo !ok! file^(s^) normalised, !fail! failed.
:end
if not defined NOPAUSE pause
endlocal & exit /b %fail%
