#!/usr/bin/env tclsh
# riffscrub - BATCH privacy/size scrubber for WAV files. Lists every RIFF chunk and rewrites the file keeping
# only the chunks you allow. Strips metadata that leaks who/where/what (bext originator, iXML location/notes,
# LIST/INFO, embedded id3, XMP _PMX, JUNK/PAD padding) WITHOUT touching a single audio sample.
# usage: tclsh riffscrub.tcl ?-keep fmt,data,fact,smpl,cue,inst? ?-out DIR? ?-list? FILE|DIR ...
#   -list   only print the chunk map (nothing is written)
#   -out    write scrubbed copies to DIR (default: alongside, as NAME.scrubbed.wav)
set keep {fmt data fact smpl cue inst}; set out ""; set listonly 0; set targets {}
for {set i 0} {$i < [llength $argv]} {incr i} {
    switch -- [lindex $argv $i] {
        -keep { set keep [split [lindex $argv [incr i]] ,] }
        -out  { set out [lindex $argv [incr i]] }
        -list { set listonly 1 }
        default { lappend targets [lindex $argv $i] }
    }
}
if {![llength $targets]} { puts stderr "usage: riffscrub.tcl ?-keep ids? ?-out DIR? ?-list? FILE|DIR ..."; exit 2 }
proc wavs {p} {
    if {[file isdirectory $p]} {
        set r {}
        foreach c [lsort [glob -nocomplain -directory $p *]] { lappend r {*}[wavs $c] }
        return $r
    }
    if {[string match -nocase *.wav $p] && ![string match *.scrubbed.wav $p]} { return [list $p] }
    return {}
}
proc chunks {data} {
    if {[string range $data 0 3] ne "RIFF" || [string range $data 8 11] ne "WAVE"} { error "not a RIFF/WAVE file" }
    set pos 12; set r {}; set n [string length $data]
    while {$pos + 8 <= $n} {
        binary scan $data @${pos}a4iu id size
        set end [expr {min($pos + 8 + $size, $n)}]
        lappend r [list [string trimright $id] $pos [expr {$end - $pos - 8}]]
        set pos [expr {$end + ($size & 1)}]
    }
    return $r
}
set status 0; set total 0
foreach f [concat {*}[lmap t $targets { wavs $t }]] {
    set fh [open $f rb]; set data [read $fh]; close $fh
    if {[catch { set cl [chunks $data] } err]} { puts "SKIP  $f: $err"; set status 1; continue }
    set body ""; set removed {}
    foreach c $cl {
        lassign $c id pos size
        if {$id in $keep} {
            append body [string range $data $pos [expr {$pos + 7 + $size}]]
            if {$size & 1} { append body \0 }
        } else { lappend removed "$id ($size B)" }
    }
    puts "[file tail $f]: [join [lmap c $cl { lindex $c 0 }] { }]"
    if {$listonly} continue
    if {![llength $removed]} { puts "  clean, nothing to strip"; continue }
    set dst [expr {$out eq "" ? "[file rootname $f].scrubbed.wav" : [file join $out [file tail $f]]}]
    if {$out ne ""} { file mkdir $out }
    set fh [open $dst wb]
    puts -nonewline $fh "RIFF[binary format iu [expr {4 + [string length $body]}]]WAVE$body"; close $fh
    puts "  stripped: [join $removed {, }]  ->  $dst"
    incr total
}
puts "$total file(s) scrubbed"
exit $status
