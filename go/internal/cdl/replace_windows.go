//go:build windows

package cdl

import("syscall";"unsafe")
var kernel32Move=syscall.NewLazyDLL("kernel32.dll").NewProc("MoveFileExW")
const(movefileReplaceExisting=0x1;movefileWriteThrough=0x8)
func replaceFileAtomic(tmp,dst string)error{from,err:=syscall.UTF16PtrFromString(tmp);if err!=nil{return err};to,err:=syscall.UTF16PtrFromString(dst);if err!=nil{return err};r1,_,e1:=kernel32Move.Call(uintptr(unsafe.Pointer(from)),uintptr(unsafe.Pointer(to)),uintptr(movefileReplaceExisting|movefileWriteThrough));if r1==0{return e1};return nil}
