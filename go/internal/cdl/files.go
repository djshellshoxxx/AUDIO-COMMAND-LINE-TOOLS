package cdl

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

var audioExt = map[string]bool{".wav":true,".flac":true,".mp3":true,".m4a":true,".aac":true,".ogg":true,".opus":true,".aiff":true,".aif":true,".wma":true}
func FindAudioFiles(path string, recursive bool) ([]string,error) {
	st,err:=os.Stat(path); if err!=nil{return nil,fmt.Errorf("unreadable input: %s",path)}
	if !st.IsDir(){abs,_:=filepath.Abs(path); return []string{abs},nil}
	var files []string
	if recursive { err=filepath.WalkDir(path,func(p string,d os.DirEntry,e error)error{if e!=nil{return e}; if !d.IsDir()&&audioExt[strings.ToLower(filepath.Ext(d.Name()))]{a,_:=filepath.Abs(p); files=append(files,a)}; return nil}) } else { entries,e:=os.ReadDir(path); if e!=nil{return nil,e}; for _,d:=range entries{if !d.IsDir()&&audioExt[strings.ToLower(filepath.Ext(d.Name()))]{a,_:=filepath.Abs(filepath.Join(path,d.Name())); files=append(files,a)}} }
	if err!=nil{return nil,err}; sort.Strings(files); return files,nil
}
