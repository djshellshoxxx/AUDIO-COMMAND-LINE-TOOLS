package testutil

import("os/exec";"path/filepath";"testing")
func RunFFmpeg(t *testing.T,args ...string){t.Helper();cmd:=exec.Command("ffmpeg",args...);if out,err:=cmd.CombinedOutput();err!=nil{t.Fatalf("ffmpeg: %v\n%s",err,out)}}
func Stereo(t *testing.T,dir,name string)string{t.Helper();p:=filepath.Join(dir,name);RunFFmpeg(t,"-hide_banner","-loglevel","error","-y","-f","lavfi","-i","sine=frequency=440:duration=1","-filter_complex","[0:a]asplit=2[l][r];[l][r]amerge=inputs=2[out]","-map","[out]","-ar","48000",p);return p}
func LongStereo(t *testing.T,dir,name string)string{t.Helper();p:=filepath.Join(dir,name);RunFFmpeg(t,"-hide_banner","-loglevel","error","-y","-f","lavfi","-i","sine=frequency=440:duration=5","-filter_complex","[0:a]asplit=2[l][r];[l][r]amerge=inputs=2[out]","-map","[out]","-ar","48000",p);return p}
func Mono(t *testing.T,dir,name string)string{t.Helper();p:=filepath.Join(dir,name);RunFFmpeg(t,"-hide_banner","-loglevel","error","-y","-f","lavfi","-i","sine=frequency=220:duration=1","-ac","1","-ar","44100",p);return p}
func Padded(t *testing.T,dir,name string)string{t.Helper();p:=filepath.Join(dir,name);RunFFmpeg(t,"-hide_banner","-loglevel","error","-y","-f","lavfi","-i","anullsrc=r=48000:cl=stereo:d=0.25","-f","lavfi","-i","sine=frequency=330:duration=0.5","-f","lavfi","-i","anullsrc=r=48000:cl=stereo:d=0.35","-filter_complex","[1:a]pan=stereo|c0=c0|c1=c0[mid];[0:a][mid][2:a]concat=n=3:v=0:a=1[out]","-map","[out]",p);return p}
