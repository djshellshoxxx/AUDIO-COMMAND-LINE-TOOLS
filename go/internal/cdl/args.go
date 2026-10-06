package cdl

import "fmt"

type ParsedArgs struct {
	Positionals []string
	Bools       map[string]bool
	Values      map[string]string
}

func ParseArgs(args []string, boolFlags, valueFlags map[string]bool) (ParsedArgs, error) {
	p := ParsedArgs{Bools: map[string]bool{}, Values: map[string]string{}}
	for i := 0; i < len(args); i++ {
		a := args[i]
		if boolFlags[a] {
			p.Bools[a] = true
			continue
		}
		if valueFlags[a] {
			if i+1 >= len(args) {
				return p, fmt.Errorf("missing value for %s", a)
			}
			i++
			p.Values[a] = args[i]
			continue
		}
		if len(a) > 0 && a[0] == '-' {
			return p, fmt.Errorf("unknown option: %s", a)
		}
		p.Positionals = append(p.Positionals, a)
	}
	return p, nil
}
