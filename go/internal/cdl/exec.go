package cdl

import (
	"bytes"
	"context"
	"errors"
	"os/exec"
	"strings"
)

type CommandResult struct { Stdout, Stderr string; ExitCode int }

func Run(ctx context.Context, name string, args ...string) (CommandResult, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	var out, er bytes.Buffer
	cmd.Stdout=&out; cmd.Stderr=&er
	err:=cmd.Run(); result:=CommandResult{Stdout:out.String(),Stderr:er.String(),ExitCode:0}
	if err!=nil { var ee *exec.ExitError; if errors.As(err,&ee){result.ExitCode=ee.ExitCode(); return result,nil}; return result,err }
	return result,nil
}
func RequireTools(names ...string) error { for _,n:=range names { if _,err:=exec.LookPath(n); err!=nil{return err} }; return nil }
func FirstLine(s string) string { if i:=strings.IndexByte(s,'\n'); i>=0{s=s[:i]}; return strings.TrimSpace(s) }
func ToolVersion(ctx context.Context,name string) string { r,err:=Run(ctx,name,"-version"); if err!=nil{return ""}; return FirstLine(r.Stdout) }
