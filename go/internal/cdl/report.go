package cdl

import("encoding/json";"fmt";"os";"path/filepath";"time")
const Version="0.1.0-beta-go-dev"
type Report struct{Tool string `json:"tool"`;Version string `json:"version"`;GeneratedUTC string `json:"generated_utc"`;Inputs []string `json:"inputs"`;Dependencies map[string]string `json:"dependencies"`;Options map[string]any `json:"options"`;Measurements map[string]any `json:"measurements"`;Findings []Finding `json:"findings"`;Status string `json:"status"`;Limitations string `json:"limitations,omitempty"`}
func NewReport(tool string,inputs []string)Report{return Report{Tool:tool,Version:Version,GeneratedUTC:time.Now().UTC().Format("2006-01-02T15:04:05Z"),Inputs:inputs,Dependencies:map[string]string{},Options:map[string]any{},Measurements:map[string]any{},Findings:[]Finding{},Status:"ok"}}
func WriteBytesAtomic(path string,data []byte)error{parent:=filepath.Dir(path);if st,err:=os.Stat(parent);err!=nil||!st.IsDir(){return fmt.Errorf("report parent directory does not exist: %s",parent)};if st,err:=os.Stat(path);err==nil&&st.IsDir(){return fmt.Errorf("report output is a directory: %s",path)};f,err:=os.CreateTemp(parent,".cdl-report-*.tmp");if err!=nil{return err};tmp:=f.Name();ok:=false;defer func(){f.Close();if !ok{os.Remove(tmp)}}();if _,err=f.Write(data);err!=nil{return err};if err=f.Sync();err!=nil{return err};if err=f.Close();err!=nil{return err};if err=replaceFileAtomic(tmp,path);err!=nil{return err};ok=true;return nil}
func WriteReportAtomic(path string,report Report)error{b,err:=json.Marshal(report);if err!=nil{return err};return WriteBytesAtomic(path,append(b,'\n'))}
func ReportJSON(report Report)([]byte,error){return json.Marshal(report)}
