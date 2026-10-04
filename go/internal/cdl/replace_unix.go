//go:build !windows

package cdl

import "os"
func replaceFileAtomic(tmp,dst string)error{return os.Rename(tmp,dst)}
