<?php
// peakforge - BATCH waveform-peak generator in pure PHP for web players (peaks.js / wavesurfer.js).
// Emits audiowaveform-compatible JSON (version 2) so shared hosting WITHOUT shell access, ffmpeg or the
// audiowaveform binary can still pre-compute waveforms on upload. Streams the file: constant memory.
// usage: php peakforge.php [--spp=512] [--bits=8|16] [--out=DIR] FILE.wav|DIR ...
//   writes NAME.peaks.json next to each WAV (or in --out). PCM 8/16/24/32-bit, float32, WAVE_FORMAT_EXTENSIBLE.
$opt = ['spp' => 512, 'bits' => 8, 'out' => null]; $targets = [];
foreach (array_slice($argv, 1) as $a) {
    if (preg_match('/^--(spp|bits|out)=(.+)$/', $a, $m)) $opt[$m[1]] = $m[2]; else $targets[] = $a;
}
if (!$targets) { fwrite(STDERR, "usage: php peakforge.php [--spp=512] [--bits=8|16] [--out=DIR] FILE|DIR ...\n"); exit(2); }
$spp = max(1, (int)$opt['spp']); $obits = (int)$opt['bits'] === 16 ? 16 : 8; $omax = (1 << ($obits - 1)) - 1;

function wav_open(string $path): array {
    $h = fopen($path, 'rb'); $hdr = fread($h, 12);
    if (strlen($hdr) < 12 || substr($hdr, 0, 4) !== 'RIFF' || substr($hdr, 8, 4) !== 'WAVE') throw new Exception('not a RIFF/WAVE file');
    $fmt = null;
    while (($c = fread($h, 8)) !== false && strlen($c) === 8) {
        ['id' => $id, 'n' => $n] = unpack('a4id/Vn', $c);
        if ($id === 'fmt ') { $raw = fread($h, $n); $fmt = unpack('vtag/vch/Vsr/Vbr/valign/vbits', $raw); if ($n & 1) fread($h, 1);
            if ($fmt['tag'] === 0xFFFE && $n >= 26) $fmt['tag'] = unpack('v', $raw, 24)[1]; /* extensible: real codec in SubFormat GUID */ }
        elseif ($id === 'data') { if (!$fmt) throw new Exception('data before fmt'); return [$h, $fmt, $n]; }
        else fseek($h, $n + ($n & 1), SEEK_CUR);
    }
    throw new Exception('no data chunk');
}
function decode(string $buf, array $f): array {   // -> list of floats in -1..1, interleaved
    $b = $f['bits'];
    if ($f['tag'] === 3 && $b === 32) return array_values(unpack('g*', $buf));
    if ($b === 16) return array_map(fn($v) => $v / 32768, array_values(unpack("s*", $buf)));
    if ($b === 8) return array_map(fn($v) => ($v - 128) / 128, array_values(unpack('C*', $buf)));
    if ($b === 32) return array_map(fn($v) => $v / 2147483648, array_values(unpack('l*', $buf)));
    if ($b === 24) { $o = []; $n = intdiv(strlen($buf), 3);
        for ($i = 0; $i < $n; $i++) { $v = unpack('V', substr($buf, $i * 3, 3) . "\0")[1]; if ($v & 0x800000) $v -= 0x1000000; $o[] = $v / 8388608; }
        return $o; }
    throw new Exception("unsupported bit depth $b");
}
function wavs(string $p): array {
    if (is_dir($p)) { $r = []; foreach (new RecursiveIteratorIterator(new RecursiveDirectoryIterator($p, FilesystemIterator::SKIP_DOTS)) as $f)
        if (preg_match('/\.wav$/i', $f)) $r[] = (string)$f; sort($r); return $r; }
    return [$p];
}
$fail = 0; $done = 0;
foreach (array_merge(...array_map('wavs', $targets)) as $path) {
    try {
        [$h, $f, $left] = wav_open($path);
        $ch = $f['ch']; $block = $spp * $f['align']; $data = [];
        while ($left > 0 && ($buf = fread($h, min($block, $left))) !== '' && $buf !== false) {
            $left -= strlen($buf); $s = decode($buf, $f);
            if (!$s) break;
            $lo = min($s); $hi = max($s);              // all channels merged, like audiowaveform's default
            $data[] = (int)round(max(-1, $lo) * $omax); $data[] = (int)round(min(1, $hi) * $omax);
        }
        fclose($h);
        $json = ['version' => 2, 'channels' => 1, 'sample_rate' => $f['sr'], 'samples_per_pixel' => $spp,
                 'bits' => $obits, 'length' => count($data) / 2, 'data' => $data];
        $dst = ($opt['out'] ? rtrim($opt['out'], '/') . '/' . basename($path) : $path);
        if ($opt['out'] && !is_dir($opt['out'])) mkdir($opt['out'], 0777, true);
        $dst = preg_replace('/\.wav$/i', '', $dst) . '.peaks.json';
        file_put_contents($dst, json_encode($json));
        printf("%-40s %6d px  %dch %d Hz %d-bit -> %s\n", basename($path), $json['length'], $ch, $f['sr'], $f['bits'], $dst); $done++;
    } catch (Throwable $e) { fprintf(STDERR, "%s: %s\n", $path, $e->getMessage()); $fail++; }
}
echo "$done file(s) done, $fail failed\n"; exit($fail ? 1 : 0);
