@echo off
rem previewcut - BATCH: make store/promo PREVIEW clips (default 30 s MP3 with fades) from the LOUDEST /
rem most energetic part of every track, not the quiet intro. Drag files or folders onto it, or pass them.
rem Finds the hottest 3-second window via FFmpeg astats, starts the clip a third of its length before it (kept inside the
rem track), fades in 1 s / out 2 s. Output: "previews\NAME_preview.mp3" beside each source.
rem   set PREVIEW_LEN=45   (seconds, default 30)      set NOPAUSE=1   (do not wait for a key at the end)
setlocal EnableExtensions EnableDelayedExpansion
set "HERE=%~dp0" & call set "PATH=%%HERE:~0,-1%%;%%PATH%%"
set "LEN=30" & if defined PREVIEW_LEN set "LEN=%PREVIEW_LEN%"
ffmpeg -version >nul 2>nul
if errorlevel 1 (echo ffmpeg.exe not found on PATH or next to this script & goto end)
if "%~1"=="" (echo usage: previewcut.cmd FILE^|FOLDER ...   ^(or drag and drop^) & goto end)
set /a ok=0, fail=0
:nextarg
if "%~1"=="" goto summary
if exist "%~1\*" (call :folder "%~1") else (call :one "%~f1")
shift
goto nextarg

:folder
for /r "%~1" %%F in (*.wav *.flac *.mp3 *.m4a *.ogg *.aif *.aiff) do call :maybe "%%~fF"
goto :eof

:maybe
rem skip our own output folder so re-runs never process results again
set "P=%~dp1"
if /i "!P:\previews\=!"=="!P!" call :one "%~1"
goto :eof

:one
set "IN=%~1" & set "OUTDIR=%~dp1previews" & set "OUT=%~dp1previews\%~n1_preview.mp3"
set "MN=previewcut_%RANDOM%%RANDOM%.txt"
set "M=%TEMP%\%MN%"
set "DUR=" & set "SR="
for /f "delims=" %%a in ('ffprobe -v error -select_streams a:0 -show_entries stream^=sample_rate -of csv^=p^=0 "!IN!"') do set "SR=%%a"
for /f "delims=" %%a in ('ffprobe -v error -show_entries format^=duration -of csv^=p^=0 "!IN!"') do set "DUR=%%a"
if not defined SR (echo   FAIL %~nx1: unreadable & set /a fail+=1 & goto :eof)
if not defined DUR (echo   FAIL %~nx1: unreadable & set /a fail+=1 & goto :eof)
for /f "delims=." %%d in ("%DUR%") do set /a DURI=%%d
set /a WIN=SR*3
rem run from %TEMP% with a bare file name: a "C:" drive colon inside a filter option would need double escaping
pushd "%TEMP%"
ffmpeg -hide_banner -nostdin -v error -i "!IN!" -af "aformat=channel_layouts=mono,asetnsamples=n=!WIN!,astats=metadata=1:reset=1,ametadata=mode=print:key=lavfi.astats.Overall.RMS_level:file=!MN!" -f null - 2>nul
popd
set /a best=-999999, bestT=0, t=0
for /f "tokens=1,2 delims==" %%a in ('type "%M%"') do call :line "%%a" "%%b"
del "!M!" 2>nul
set /a start=bestT-LEN/3
set /a maxstart=DURI-LEN
if !start! gtr !maxstart! set /a start=maxstart
if !start! lss 0 set /a start=0
set /a clip=LEN & if !DURI! lss !LEN! set /a clip=DURI
set /a fo=clip-2 & if !fo! lss 0 set /a fo=0
if not exist "!OUTDIR!" mkdir "!OUTDIR!"
ffmpeg -hide_banner -nostdin -v error -y -ss !start! -t !clip! -i "!IN!" -af "afade=t=in:d=1,afade=t=out:st=!fo!:d=2" -c:a libmp3lame -b:a 192k "!OUT!"
if errorlevel 1 (echo   FAIL %~nx1: encode failed & set /a fail+=1 & goto :eof)
set /a bdb=best/1000, cend=start+clip
echo   OK   %~nx1: loudest 3 s at !bestT! s ^(!bdb! dBFS RMS^) -^> preview !start!-!cend! s
set /a ok+=1
goto :eof

:line
rem one line of ametadata output: "frame:N pts:N pts_time:T"  or  "lavfi.astats.Overall.RMS_level=-20.123456"
set "k=%~1" & set "val=%~2"
if "!k:~0,6!"=="frame:" goto frameline
if "!val!"=="" goto :eof
if "!val!"=="-inf" goto :eof
set "ip=" & set "fp="
for /f "tokens=1,2 delims=." %%x in ("%val%") do (set "ip=%%x" & set "fp=%%y000")
rem dB value -> integer millibels (batch arithmetic is integer only); "1xxx-1000" avoids octal parsing of 0xx
set /a "v=ip*1000"
set /a "f=1!fp:~0,3!-1000"
if "!ip:~0,1!"=="-" (set /a v-=f) else (set /a v+=f)
if !v! gtr !best! (set /a best=v & set /a bestT=t)
goto :eof
:frameline
for /f "tokens=3" %%p in ("%k%") do set "pt=%%p"
set "pt=!pt:pts_time:=!"
for /f "delims=." %%i in ("%pt%") do set /a t=%%i
goto :eof

:summary
echo.
echo !ok! preview^(s^) written, !fail! failed.
:end
if not defined NOPAUSE pause
endlocal & exit /b %fail%
