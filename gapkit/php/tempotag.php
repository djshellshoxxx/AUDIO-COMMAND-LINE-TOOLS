<?php
// tempotag - BATCH BPM detector in pure PHP (no ffmpeg, no extensions, no exec()). For DJ-pool / sample-store
// upload pipelines on shared hosting that need a tempo tag at upload time. Outputs CSV (default) or JSON.
// 'alt_octave' gives the half/double-time reading, since onset-based tempo is octave-ambiguous by nature.
// Method: 2.5 ms log-energy onset envelope -> autocorrelation over the allowed BPM range with a mild preference
// for 120 BPM (octave-error guard) -> parabolic refinement. Confidence = peak autocorrelation height.
// usage: php tempotag.php [--min=70] [--max=180] [--json] FILE.wav|DIR ...
$opt = ['min' => 70, 'max' => 180, 'json' => false]; $targets = [];
foreach (array_slice($argv, 1) as $a) {
    if ($a === '--json') $opt['json'] = true;
    elseif (preg_match('/^--(min|max)=([\d.]+)$/', $a, $m)) $opt[$m[1]] = (float)$m[2]; else $targets[] = $a;
}
if (!$targets) { fwrite(STDERR, "usage: php tempotag.php [--min=70] [--max=180] [--json] FILE|DIR ...\n"); exit(2); }

function envelope(string $path, int $rate, ?float &$real = null): array {   // energy per 1/$rate s of a PCM/float WAV, streamed
    $h = fopen($path, 'rb'); $hd = fread($h, 12);
    if (substr($hd, 0, 4) !== 'RIFF' || substr($hd, 8, 4) !== 'WAVE') throw new Exception('not a RIFF/WAVE file');
    $f = null;
    while (strlen($c = fread($h, 8)) === 8) {
        ['id' => $id, 'n' => $n] = unpack('a4id/Vn', $c);
        if ($id === 'fmt ') { $raw = fread($h, $n); $f = unpack('vtag/vch/Vsr/Vbr/valign/vbits', $raw); if ($n & 1) fread($h, 1);
            if ($f['tag'] === 0xFFFE && $n >= 26) $f['tag'] = unpack('v', $raw, 24)[1]; }   // WAVE_FORMAT_EXTENSIBLE
        elseif ($id === 'data') break; else fseek($h, $n + ($n & 1), SEEK_CUR);
    }
    if (!$f || !isset($n)) throw new Exception('missing fmt/data');
    $hop = intdiv($f['sr'], $rate); $real = $f["sr"] / $hop; $env = []; $left = min($n, $f['sr'] * $f['align'] * 240);   // first 4 minutes   // $real: true envelope rate (44100/110 = 400.9 Hz)
    $bps = $f['bits'] / 8; $float = $f['tag'] === 3;
    while ($left > 0 && strlen($buf = fread($h, min($hop * $f['align'], $left))) > 0) {
        $left -= strlen($buf); $e = 0.0;
        if ($float) foreach (unpack('g*', $buf) as $v) $e += $v * $v;
        elseif ($bps == 2) foreach (unpack('s*', $buf) as $v) $e += ($v / 32768) ** 2;
        else for ($i = 0, $k = strlen($buf); $i + $bps <= $k; $i += $bps) {   // 24/32-bit: use the top 16 bits
            $v = unpack('s', substr($buf, $i + $bps - 2, 2))[1]; $e += ($v / 32768) ** 2; }
        $env[] = $e;
    }
    fclose($h); return $env;
}
function bpm(array $env, float $rate, float $lo, float $hi): array {
    $n = count($env); if ($n < $rate * 4) throw new Exception('need at least 4 s of audio');
    $sm = [];                                   // 10 ms sliding window: removes bass-ripple jitter from the envelope
    for ($i = 0; $i < $n; $i++) $sm[] = $env[$i] + ($env[$i - 1] ?? 0) + ($env[$i - 2] ?? 0) + ($env[$i - 3] ?? 0);
    $env = $sm;
    $on = [0.0]; for ($i = 1; $i < $n; $i++) $on[] = max(0, log10($env[$i] + 1e-9) - log10($env[$i - 1] + 1e-9));
    $m = array_sum($on) / $n; foreach ($on as &$v) $v -= $m; unset($v);
    $r0 = 0; foreach ($on as $v) $r0 += $v * $v; if ($r0 <= 0) throw new Exception('no onsets found');
    $minLag = (int)floor(60 * $rate / $hi); $maxLag = (int)ceil(60 * $rate / $lo); $r = [];
    for ($L = $minLag - 1; $L <= $maxLag + 1; $L++) { $s = 0; for ($i = $L; $i < $n; $i++) $s += $on[$i] * $on[$i - $L]; $r[$L] = $s / $r0; }
    $best = $minLag; $bw = -INF;
    for ($L = $minLag; $L <= $maxLag; $L++) {
        $w = $r[$L] * exp(-0.5 * (log(60 * $rate / $L / 120, 2) / 1.4) ** 2);   // gentle 120-BPM prior
        if ($r[$L] >= $r[$L - 1] && $r[$L] >= $r[$L + 1] && $w > $bw) { $bw = $w; $best = $L; }
    }
    $a = $r[$best - 1]; $b = $r[$best]; $c = $r[$best + 1]; $d = $a - 2 * $b + $c;
    $lag = $best + ($d != 0 ? 0.5 * ($a - $c) / $d : 0);
    return [round(60 * $rate / $lag, 2), round(max(0, $b), 3)];
}
function wavs(string $p): array {
    if (is_dir($p)) { $r = []; foreach (new RecursiveIteratorIterator(new RecursiveDirectoryIterator($p, FilesystemIterator::SKIP_DOTS)) as $f)
        if (preg_match('/\.wav$/i', $f)) $r[] = (string)$f; sort($r); return $r; }
    return [$p];
}
$rows = []; $fail = 0; $rate = 400;
foreach (array_merge(...array_map('wavs', $targets)) as $p) {
    try { $env = envelope($p, $rate, $real); [$b, $c] = bpm($env, $real, $opt['min'], $opt['max']);
          $rows[] = ['file' => $p, 'bpm' => $b, 'alt' => round($b * 2 <= $opt['max'] ? $b * 2 : $b / 2, 2), 'confidence' => $c]; }
    catch (Throwable $e) { $rows[] = ['file' => $p, 'bpm' => null, 'alt' => null, 'confidence' => 0, 'error' => $e->getMessage()]; $fail++; }
}
if ($opt['json']) echo json_encode($rows, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES), "\n";
else { $o = fopen('php://stdout', 'w'); fputcsv($o, ['file', 'bpm', 'alt_octave', 'confidence', 'error'], ',', '"', '');
       foreach ($rows as $r) fputcsv($o, [$r['file'], $r['bpm'], $r['alt'], $r['confidence'], $r['error'] ?? ''], ',', '"', ''); }
exit($fail ? 1 : 0);
