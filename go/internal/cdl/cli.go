package cdl

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"strconv"
	"strings"
)

func Dependencies(ctx context.Context) map[string]string {
	return map[string]string{"ffmpeg": ToolVersion(ctx, "ffmpeg"), "ffprobe": ToolVersion(ctx, "ffprobe")}
}
func Emit(w io.Writer, report Report, jsonOut bool, output, text string) error {
	var b []byte
	var err error
	if jsonOut {
		b, err = json.Marshal(report)
		if err == nil { b = append(b, '\n') }
	} else { b = []byte(text + "\n") }
	if err != nil { return err }
	if output != "" { return WriteBytesAtomic(output, b) }
	_, err = w.Write(b); return err
}
func ParseFiniteFloat(value, name string) (float64, error) {
	v, err := strconv.ParseFloat(value, 64)
	if err != nil || math.IsNaN(v) || math.IsInf(v, 0) { return 0, fmt.Errorf("invalid %s", name) }
	return v, nil
}
func ParseNonNegativeFloat(value, name string) (float64, error) { v,e:=ParseFiniteFloat(value,name); if e!=nil{return 0,e}; if v<0{return 0,fmt.Errorf("%s must be >= 0",name)}; return v,nil }
func ParsePositiveFloat(value, name string) (float64, error) { v,e:=ParseFiniteFloat(value,name); if e!=nil{return 0,e}; if v<=0{return 0,fmt.Errorf("%s must be > 0",name)}; return v,nil }
func ParseNonNegativeInt64(value, name string) (int64, error) { if strings.HasPrefix(value,"-"){return 0,fmt.Errorf("%s must be >= 0",name)}; v,e:=strconv.ParseInt(value,10,64); if e!=nil||v<0{return 0,fmt.Errorf("invalid %s",name)}; return v,nil }
func ParsePositiveInt(value, name string) (int, error) { v,e:=strconv.Atoi(value); if e!=nil||v<=0{return 0,fmt.Errorf("invalid %s",name)}; return v,nil }
func IntOrNil(s string) any { if s==""||s=="N/A"{return nil}; v,e:=strconv.Atoi(s); if e!=nil{return nil}; return v }
func Int64OrNil(s string) any { if s==""||s=="N/A"{return nil}; v,e:=strconv.ParseInt(s,10,64); if e!=nil{return nil}; return v }
func FloatOrNil(s string) any { if s==""||s=="N/A"{return nil}; v,e:=strconv.ParseFloat(s,64); if e!=nil||math.IsNaN(v)||math.IsInf(v,0){return nil}; return v }
