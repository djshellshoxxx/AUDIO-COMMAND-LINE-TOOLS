#!/usr/bin/env perl
# playlistmend - BATCH repair of broken M3U/M3U8/PLS playlists after a music library was moved, renamed,
# re-organised or converted (mp3 -> flac). Re-links every dead entry by: 1) same file name anywhere in the
# library (ties broken by matching parent folders), 2) same normalised title with ANY audio extension.
# Understands Windows paths (C:\Music\..), file:// URIs with %20, EXTINF lines and PLS FileN= entries.
# usage: perl playlistmend.pl --lib DIR [--out DIR] [--relative] PLAYLIST ...
#   writes NAME.fixed.m3u8 (or into --out); exit 1 if anything stayed unresolved
use strict; use warnings; use File::Find; use File::Spec; use File::Basename; use Getopt::Long; use Cwd 'abs_path';
my ($lib, $out, $rel) = (undef, undef, 0);
GetOptions('lib=s' => \$lib, 'out=s' => \$out, 'relative' => \$rel) && $lib && @ARGV
  or die "usage: perl playlistmend.pl --lib DIR [--out DIR] [--relative] PLAYLIST ...\n";
my $AUD = qr/\.(mp3|flac|wav|aiff?|m4a|aac|ogg|opus|wma|alac|ape|wv)$/i;
sub norm { my $s = lc shift; $s =~ s/$AUD//; $s =~ s/^\s*\d{1,3}(\s*[-._)]\s*|\s+)//; $s =~ s/[^a-z0-9]+//g; $s }
my (%byname, %bystem);
find({ no_chdir => 1, wanted => sub {
  return unless -f && /$AUD/; my $p = abs_path($_);
  push @{ $byname{ lc basename($p) } }, $p; push @{ $bystem{ norm(basename($p)) } }, $p } }, $lib);
printf "indexed %d audio files under %s\n", scalar(map { @$_ } values %byname), $lib;
sub pick {   # prefer the candidate sharing the most trailing folder names with the old path
  my ($old, @c) = @_; my @o = reverse grep { length } split m{[/\\]}, lc $old; shift @o;
  my ($best, $bs) = ($c[0], -1);
  for my $c (@c) { my @p = reverse split m{/}, lc $c; shift @p; my $s = 0; $s++ while $s < @o && $s < @p && $o[$s] eq $p[$s];
                   ($best, $bs) = ($c, $s) if $s > $bs }
  return $best;
}
my $bad = 0;
for my $pl (@ARGV) {
  open my $fh, '<:raw', $pl or do { warn "$pl: $!\n"; $bad++; next };
  my @lines = map { s/\r?\n$//r } <$fh>; close $fh; $lines[0] =~ s/^\xEF\xBB\xBF// if @lines;
  my $base = dirname(abs_path($pl)); my (@entries, $extinf);
  if ($pl =~ /\.pls$/i) {
    my (%f, %t); for (@lines) { $f{$1} = $2 if /^File(\d+)=(.*)$/i; $t{$1} = $2 if /^Title(\d+)=(.*)$/i }
    @entries = map { [ $f{$_}, defined $t{$_} ? "#EXTINF:-1,$t{$_}" : undef ] } sort { $a <=> $b } keys %f;
  } else {
    for (@lines) { if (/^#EXTINF/i) { $extinf = $_ } elsif (/\S/ && !/^#/) { push @entries, [ $_, $extinf ]; $extinf = undef } }
  }
  my @res = ('#EXTM3U'); my ($ok, $fixed, $miss) = (0, 0, 0);
  for my $e (@entries) {
    my ($raw, $inf) = @$e; my $p = $raw;
    if ($p =~ m{^file://}i) { $p =~ s{^file://(localhost)?}{}i; $p =~ s/%([0-9A-Fa-f]{2})/chr hex $1/ge; $p =~ s{^/([A-Za-z]:)}{$1} }
    (my $unix = $p) =~ tr{\\}{/};
    my $abs = File::Spec->file_name_is_absolute($unix) ? $unix : "$base/$unix";
    my $new;
    if ($unix !~ /^[A-Za-z]:/ && -f $abs) { $new = abs_path($abs); $ok++ }
    else {
      my $name = lc basename($unix);
      my @c = @{ $byname{$name} // [] }; @c = @{ $bystem{ norm($name) } // [] } unless @c;
      if (@c) { $new = pick($unix, @c); $fixed++; print "  relinked: $raw\n        -> $new\n" }
      else { $miss++; print "  MISSING : $raw\n"; push @res, "# UNRESOLVED: $raw"; next }
    }
    push @res, $inf if $inf;
    push @res, $rel ? File::Spec->abs2rel($new, $out ? abs_path($out) // $out : $base) : $new;
  }
  my $dst = ($out ? File::Spec->catfile($out, basename($pl)) : $pl) =~ s/\.(m3u8?|pls)$//ir . '.fixed.m3u8';
  mkdir $out if $out && !-d $out;
  open my $w, '>:raw', $dst or die "$dst: $!"; print $w join("\n", @res), "\n"; close $w;
  printf "%s: %d ok, %d relinked, %d missing -> %s\n", basename($pl), $ok, $fixed, $miss, $dst;
  $bad += $miss;
}
exit($bad ? 1 : 0);
