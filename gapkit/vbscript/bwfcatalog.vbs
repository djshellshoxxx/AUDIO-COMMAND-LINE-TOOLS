' bwfcatalog - BATCH catalogue of Broadcast-WAV / field-recorder metadata to CSV on ANY Windows PC, with
' nothing to install (cscript is built in). Reads bext (description, originator, date, time reference ->
' timecode), iXML (project, scene, take, tape, circled, note, timecode rate) and LIST/INFO tags, recursing
' through a folder. Made for locked-down post-production / broadcast workstations.
' usage: cscript //nologo bwfcatalog.vbs FOLDER|FILE.wav ... [OUT.csv] [fps]   (or drag files/folders onto it)
'        default OUT: bwf_catalog.csv beside the first argument, fps 25 (iXML TIMECODE_RATE wins when present)
Option Explicit
Dim fso, outPath, fps, out, count, a, i, targets
Set fso = CreateObject("Scripting.FileSystemObject")
If WScript.Arguments.Count < 1 Then WScript.Echo "usage: cscript //nologo bwfcatalog.vbs FOLDER|FILE.wav ... [OUT.csv] [fps]" : WScript.Quit 2
fps = 25 : outPath = "" : Set targets = CreateObject("Scripting.Dictionary")
For i = 0 To WScript.Arguments.Count - 1
  a = WScript.Arguments(i)
  If LCase(Right(a, 4)) = ".csv" Then
    outPath = a
  ElseIf IsNumeric(a) And Not fso.FileExists(a) And Not fso.FolderExists(a) Then
    fps = CDbl(a)
  ElseIf fso.FolderExists(a) Or fso.FileExists(a) Then
    targets.Add targets.Count, a
  Else
    WScript.Echo "not found: " & a : WScript.Quit 2
  End If
Next
If targets.Count = 0 Then WScript.Echo "no folder or WAV given" : WScript.Quit 2
If outPath = "" Then
  If fso.FolderExists(targets.Item(0)) Then outPath = fso.BuildPath(targets.Item(0), "bwf_catalog.csv") Else outPath = fso.BuildPath(fso.GetParentFolderName(fso.GetAbsolutePathName(targets.Item(0))), "bwf_catalog.csv")
End If
Set out = fso.CreateTextFile(outPath, True)
out.WriteLine "file,folder,sample_rate,bits,channels,duration_s,description,originator,originator_ref,date,time,time_reference,timecode,project,scene,take,tape,circled,note,title,artist,comment"
count = 0
For i = 0 To targets.Count - 1
  a = targets.Item(i)
  If fso.FolderExists(a) Then Walk fso.GetFolder(a) Else Catalog fso.GetAbsolutePathName(a)
Next
out.Close
WScript.Echo count & " WAV file(s) catalogued -> " & outPath

Function U32(s, p) ' little-endian unsigned 32-bit from a byte string (1-based p)
  U32 = CDbl(Asc(Mid(s, p, 1)) And 255) + CDbl(Asc(Mid(s, p + 1, 1)) And 255) * 256 + CDbl(Asc(Mid(s, p + 2, 1)) And 255) * 65536 + CDbl(Asc(Mid(s, p + 3, 1)) And 255) * 16777216
End Function
Function U16(s, p) : U16 = (Asc(Mid(s, p, 1)) And 255) + (Asc(Mid(s, p + 1, 1)) And 255) * 256 : End Function
Function Txt(s) ' cut at first NUL, trim
  Dim i : i = InStr(s, Chr(0)) : If i > 0 Then s = Left(s, i - 1)
  Txt = Trim(s)
End Function
Function Tag(x, name) ' first <NAME>value</NAME> in iXML
  Dim a, b : a = InStr(1, x, "<" & name & ">", 1) : Tag = ""
  If a = 0 Then Exit Function
  a = a + Len(name) + 2 : b = InStr(a, x, "</" & name & ">", 1)
  If b > a Then Tag = Trim(Mid(x, a, b - a))
End Function
Function Info(lst, id) ' value of an INFO sub-chunk inside a LIST chunk body
  Dim p, n : Info = "" : p = 5
  If Left(lst, 4) <> "INFO" Then Exit Function
  Do While p + 8 <= Len(lst)
    n = U32(lst, p + 4)
    If Mid(lst, p, 4) = id Then Info = Txt(Mid(lst, p + 8, n)) : Exit Function
    p = p + 8 + n + (n Mod 2)
  Loop
End Function
Function Q(v) : Q = """" & Replace(Replace(Replace(CStr(v), """", """"""), vbCr, " "), vbLf, " ") & """" : End Function
Function TC(samples, sr, rate)
  Dim t, h, m, s, f
  If sr = 0 Or samples = "" Then TC = "" : Exit Function
  t = samples / sr : h = Int(t / 3600) : m = Int((t - h * 3600) / 60) : s = Int(t - h * 3600 - m * 60)
  f = Int((t - Int(t)) * rate + 0.0001)
  TC = Right("0" & h, 2) & ":" & Right("0" & m, 2) & ":" & Right("0" & s, 2) & ":" & Right("0" & f, 2)
End Function
Function RateOf(x) ' iXML TIMECODE_RATE like 24000/1001 or 25/1
  Dim r, k : r = Tag(x, "TIMECODE_RATE") : RateOf = fps
  k = InStr(r, "/")
  If k > 1 Then
    If CDbl(Mid(r, k + 1)) > 0 Then RateOf = CDbl(Left(r, k - 1)) / CDbl(Mid(r, k + 1))
  End If
End Function

Sub SkipBytes(ts, ByVal n) ' TextStream.Skip, falling back to read-and-discard where Skip is unavailable
  Dim k
  Do While n > 0
    k = n : If k > 1000000000 Then k = 1000000000
    On Error Resume Next : ts.Skip k
    If Err.Number <> 0 Then
      Err.Clear : On Error GoTo 0
      Do While k > 0
        If k > 1048576 Then ts.Read 1048576 : k = k - 1048576 : n = n - 1048576 Else ts.Read k : n = n - k : k = 0
      Loop
    Else
      On Error GoTo 0 : n = n - k
    End If
  Loop
End Sub

Sub Walk(folder)
  Dim f, sf
  For Each f In folder.Files
    If LCase(fso.GetExtensionName(f.Name)) = "wav" Then Catalog fso.BuildPath(folder.Path, f.Name)
  Next
  For Each sf In folder.SubFolders : Walk sf : Next
End Sub

Sub Catalog(path) ' path string (not a File object: keeps it portable to minimal FSO implementations)
  Dim ts, hdr, ck, id, n, body, remain, sr, bits, ch, dataLen, bext, ixml, lst, tr, dur
  Set ts = fso.OpenTextFile(path, 1, False, 0) ' ASCII mode: one char per byte, binary-safe on single-byte code pages
  remain = fso.GetFile(path).Size : hdr = ts.Read(12) : remain = remain - 12
  If Len(hdr) < 12 Or Left(hdr, 4) <> "RIFF" Or Mid(hdr, 9, 4) <> "WAVE" Then ts.Close : WScript.Echo "skip (not WAV): " & path : Exit Sub
  sr = 0 : bits = 0 : ch = 0 : dataLen = 0 : bext = "" : ixml = "" : lst = ""
  Do While remain >= 8
    ck = ts.Read(8) : remain = remain - 8 : If Len(ck) < 8 Then Exit Do
    id = Left(ck, 4) : n = U32(ck, 5) : If n > remain Then n = remain
    Select Case id
      Case "fmt " : body = ts.Read(n) : ch = U16(body, 3) : sr = U32(body, 5) : bits = U16(body, 15)
      Case "bext" : bext = ts.Read(n)
      Case "iXML" : ixml = ts.Read(n)
      Case "LIST" : lst = ts.Read(n)
      Case Else
        If id = "data" Then dataLen = n
        SkipBytes ts, n
    End Select
    remain = remain - n
    If n Mod 2 = 1 And remain > 0 Then SkipBytes ts, 1 : remain = remain - 1
  Loop
  ts.Close
  tr = ""
  If Len(bext) >= 346 Then tr = U32(bext, 339) + U32(bext, 343) * 4294967296
  dur = "" : If sr * ch * bits > 0 Then dur = Round(dataLen / (sr * ch * bits / 8), 3)
  out.WriteLine Q(fso.GetFileName(path)) & "," & Q(fso.GetParentFolderName(path)) & "," & sr & "," & bits & "," & ch & "," & _
    Q(dur) & "," & _
    Q(Txt(Mid(bext, 1, 256))) & "," & Q(Txt(Mid(bext, 257, 32))) & "," & Q(Txt(Mid(bext, 289, 32))) & "," & _
    Q(Txt(Mid(bext, 321, 10))) & "," & Q(Txt(Mid(bext, 331, 8))) & "," & Q(tr) & "," & Q(TC(tr, sr, RateOf(ixml))) & "," & _
    Q(Tag(ixml, "PROJECT")) & "," & Q(Tag(ixml, "SCENE")) & "," & Q(Tag(ixml, "TAKE")) & "," & Q(Tag(ixml, "TAPE")) & "," & _
    Q(Tag(ixml, "CIRCLED")) & "," & Q(Tag(ixml, "NOTE")) & "," & Q(Info(lst, "INAM")) & "," & Q(Info(lst, "IART")) & "," & Q(Info(lst, "ICMT"))
  count = count + 1
End Sub
