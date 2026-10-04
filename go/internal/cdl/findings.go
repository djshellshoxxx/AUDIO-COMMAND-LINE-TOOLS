package cdl

type Finding struct { Category string `json:"category"`; Message string `json:"message"`; Path string `json:"path,omitempty"`; TimeSeconds *float64 `json:"time_seconds,omitempty"` }
func StatusFromFindings(findings []Finding) string { if len(findings)>0{return "review"}; return "ok" }
