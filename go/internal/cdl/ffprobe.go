package cdl

import (
	"context"
	"fmt"
	"strings"
)

func ProbeValue(ctx context.Context,path,key,scope string)(string,error){args:=[]string{"-v","error"}; if scope=="format"{args=append(args,"-show_entries","format="+key)}else{args=append(args,"-select_streams","a:0","-show_entries","stream="+key)}; args=append(args,"-of","default=nw=1:nk=1",path); r,err:=Run(ctx,"ffprobe",args...); if err!=nil{return "",err}; if r.ExitCode!=0{return "",fmt.Errorf("ffprobe failed: %s",strings.TrimSpace(r.Stderr))}; return FirstLine(r.Stdout),nil}
func ProbeTag(ctx context.Context,path,key string)(string,error){r,err:=Run(ctx,"ffprobe","-v","error","-show_entries","format_tags="+key+":stream_tags="+key,"-of","default=nw=1:nk=1",path); if err!=nil{return "",err}; if r.ExitCode!=0{return "",fmt.Errorf("ffprobe failed: %s",strings.TrimSpace(r.Stderr))}; return FirstLine(r.Stdout),nil}
func StreamTypes(ctx context.Context,path string)([]string,error){r,err:=Run(ctx,"ffprobe","-v","error","-show_entries","stream=codec_type","-of","csv=p=0",path); if err!=nil{return nil,err}; if r.ExitCode!=0{return nil,fmt.Errorf("ffprobe failed: %s",strings.TrimSpace(r.Stderr))}; var out []string; for _,s:=range strings.Split(r.Stdout,"\n"){s=strings.TrimSpace(s); if s!=""{out=append(out,s)}}; return out,nil}
