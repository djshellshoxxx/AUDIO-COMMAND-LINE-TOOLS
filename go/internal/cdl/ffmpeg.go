package cdl

import (
	"context"
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

type LoudnessPoint struct { TimeSeconds float64 `json:"time_seconds"`; ShortTermLUFS float64 `json:"short_term_lufs"` }
type PhasePoint struct { TimeSeconds float64 `json:"time_seconds"`; Correlation float64 `json:"correlation"` }

var ebuLine=regexp.MustCompile(` t:\s*([-0-9.]+).* S:\s*([-0-9.]+)`)
var numLine=regexp.MustCompile(`^\s*(I|LRA):\s*([-0-9.]+)`)
var ptsLine=regexp.MustCompile(`pts_time:([^\s]+)`)
var phaseLine=regexp.MustCompile(`lavfi\.aphasemeter\.phase=([-0-9.]+)`)
var rms1Line=regexp.MustCompile(`lavfi\.astats\.1\.RMS_level=([-0-9.]+)`)
var rms2Line=regexp.MustCompile(`lavfi\.astats\.2\.RMS_level=([-0-9.]+)`)
var silenceStart=regexp.MustCompile(`silence_start:\s*([-0-9.]+)`)
var silenceEnd=regexp.MustCompile(`silence_end:\s*([-0-9.]+)`)
func parseFloat(s string)(float64,error){return strconv.ParseFloat(strings.TrimSpace(s),64)}
func floatPtr(v float64)*float64{return &v}
func Ebur128(ctx context.Context,path string)([]LoudnessPoint,*float64,*float64,error){r,err:=Run(ctx,"ffmpeg","-hide_banner","-nostats","-i",path,"-filter_complex","ebur128=peak=true","-f","null","-"); if err!=nil{return nil,nil,nil,err}; if r.ExitCode!=0{return nil,nil,nil,fmt.Errorf("ffmpeg ebur128 failed: %s",strings.TrimSpace(r.Stderr))}; var points []LoudnessPoint; var integrated,lra *float64; mode:=""; for _,line:=range strings.Split(r.Stderr,"\n"){if m:=ebuLine.FindStringSubmatch(line);m!=nil{t,_:=parseFloat(m[1]);s,_:=parseFloat(m[2]);if s>-100{points=append(points,LoudnessPoint{t,s})}}; if strings.Contains(line,"Integrated loudness:"){mode="I";continue}; if strings.Contains(line,"Loudness range:"){mode="LRA";continue}; if m:=numLine.FindStringSubmatch(line);m!=nil&&m[1]==mode{v,e:=parseFloat(m[2]);if e==nil{if mode=="I"{integrated=floatPtr(v)}else{lra=floatPtr(v)}};mode=""}}; return points,integrated,lra,nil}
func PhaseSamples(ctx context.Context,path string)([]PhasePoint,error){r,err:=Run(ctx,"ffmpeg","-hide_banner","-loglevel","error","-i",path,"-af","aphasemeter=video=0,ametadata=print:key=lavfi.aphasemeter.phase:file=-","-f","null","-");if err!=nil{return nil,err};if r.ExitCode!=0{return nil,fmt.Errorf("ffmpeg phase analysis failed: %s",strings.TrimSpace(r.Stderr))};text:=r.Stdout+"\n"+r.Stderr;current:=0.0;var out []PhasePoint;for _,line:=range strings.Split(text,"\n"){if m:=ptsLine.FindStringSubmatch(line);m!=nil{current,_=parseFloat(m[1])};if m:=phaseLine.FindStringSubmatch(line);m!=nil{p,e:=parseFloat(m[1]);if e==nil{out=append(out,PhasePoint{current,p})}}};return out,nil}
func RMSLevels(ctx context.Context,path string)(*float64,*float64,error){r,err:=Run(ctx,"ffmpeg","-hide_banner","-loglevel","error","-i",path,"-af","astats=metadata=1:reset=0,ametadata=print:file=-","-f","null","-");if err!=nil{return nil,nil,err};if r.ExitCode!=0{return nil,nil,fmt.Errorf("ffmpeg astats failed: %s",strings.TrimSpace(r.Stderr))};text:=r.Stdout+"\n"+r.Stderr;var left,right *float64;for _,line:=range strings.Split(text,"\n"){if left==nil{if m:=rms1Line.FindStringSubmatch(line);m!=nil{if v,e:=parseFloat(m[1]);e==nil{left=floatPtr(v)}}};if right==nil{if m:=rms2Line.FindStringSubmatch(line);m!=nil{if v,e:=parseFloat(m[1]);e==nil{right=floatPtr(v)}}}};return left,right,nil}
func EdgeSilence(ctx context.Context,path string,threshold,minSilence float64,reverse bool)(float64,error){filter:=fmt.Sprintf("silencedetect=noise=%gdB:d=%g",threshold,minSilence);if reverse{filter="areverse,"+filter};r,err:=Run(ctx,"ffmpeg","-hide_banner","-nostats","-i",path,"-af",filter,"-f","null","-");if err!=nil{return 0,err};if r.ExitCode!=0{return 0,fmt.Errorf("ffmpeg silencedetect failed: %s",strings.TrimSpace(r.Stderr))};started:=false;for _,line:=range strings.Split(r.Stderr,"\n"){if !started{if m:=silenceStart.FindStringSubmatch(line);m!=nil{v,_:=parseFloat(m[1]);if v<=0.0001{started=true}else{return 0,nil}}}else if m:=silenceEnd.FindStringSubmatch(line);m!=nil{v,e:=parseFloat(m[1]);return v,e}};return 0,nil}
