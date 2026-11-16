#!/usr/bin/env node
// autoloop - find seamless sustain-loop points in instrument samples and WRITE them into the WAV 'smpl' chunk,
// so samplers (Kontakt, EXS/Sampler, Decent Sampler, SFZ, hardware) loop the note automatically. Batch-capable.
// Scores every rising zero crossing as a loop end by how well the audio on BOTH sides of the seam matches
// (normalized correlation before+after) and how close the levels are. Pure Node.js, no dependencies.
// usage: node autoloop.js [--start=0.3] [--min=0.25] [--win=15] [--write] [--out=DIR] FILE.wav|DIR ...
//        node autoloop.js --info FILE.wav          (print existing smpl loops)
//   --start  loop start as fraction of length (default 0.3)   --min  minimum loop length in seconds
//   --win    seam comparison window in ms                      --write  add/replace smpl chunk (copy in --out, else in place)
'use strict';
const fs = require('fs'), path = require('path');
const opt = { start: 0.3, min: 0.25, win: 15, write: false, out: null, info: false }, targets = [];
for (const a of process.argv.slice(2)) {
  const m = a.match(/^--(\w+)(?:=(.*))?$/);
  if (!m) targets.push(a); else opt[m[1]] = m[2] === undefined ? true : (isNaN(m[2]) ? m[2] : +m[2]);
}
if (!targets.length) { console.error('usage: node autoloop.js [--start=0.3] [--min=0.25] [--win=15] [--write] [--out=DIR] FILE|DIR ...'); process.exit(2); }

function parse(buf) {
  if (buf.toString('ascii', 0, 4) !== 'RIFF' || buf.toString('ascii', 8, 12) !== 'WAVE') throw new Error('not a RIFF/WAVE file');
  const chunks = [];
  for (let p = 12; p + 8 <= buf.length;) {
    const id = buf.toString('ascii', p, p + 4), size = buf.readUInt32LE(p + 4);
    chunks.push({ id, start: p, size: Math.min(size, buf.length - p - 8) });
    p += 8 + size + (size & 1);
  }
  const fc = chunks.find(c => c.id === 'fmt '), dc = chunks.find(c => c.id === 'data');
  if (!fc || !dc) throw new Error('missing fmt/data');
  let tag = buf.readUInt16LE(fc.start + 8);
  if (tag === 0xfffe) tag = buf.readUInt16LE(fc.start + 32);
  const ch = buf.readUInt16LE(fc.start + 10), sr = buf.readUInt32LE(fc.start + 12), bits = buf.readUInt16LE(fc.start + 22);
  return { chunks, tag, ch, sr, bits, data: dc };
}
function mono(buf, w) {
  const bps = w.bits / 8, align = bps * w.ch, n = Math.floor(w.data.size / align), x = new Float64Array(n);
  const rd = w.tag === 3 ? (o => buf.readFloatLE(o)) : bps === 2 ? (o => buf.readInt16LE(o) / 32768)
    : bps === 3 ? (o => buf.readIntLE(o, 3) / 8388608) : bps === 4 ? (o => buf.readInt32LE(o) / 2147483648)
    : bps === 1 ? (o => (buf[o] - 128) / 128) : null;
  if (!rd) throw new Error(`unsupported ${w.bits}-bit`);
  for (let i = 0, o = w.data.start + 8; i < n; i++) { let s = 0; for (let c = 0; c < w.ch; c++, o += bps) s += rd(o); x[i] = s / w.ch; }
  return x;
}
function corr(x, a, b, n) {     // normalized correlation of x[a..a+n) and x[b..b+n)
  let s = 0, ea = 0, eb = 0;
  for (let i = 0; i < n; i++) { const p = x[a + i], q = x[b + i]; s += p * q; ea += p * p; eb += q * q; }
  return { r: s / Math.sqrt(ea * eb + 1e-20), ea, eb };
}
function findLoop(x, sr) {
  const W = Math.max(16, Math.round(opt.win * sr / 1000)), n = x.length;
  const zc = []; for (let i = W + 1; i < n - W - 1; i++) if (x[i - 1] < 0 && x[i] >= 0) zc.push(i);
  if (zc.length < 2) throw new Error('no zero crossings (silence or DC?)');
  const want = Math.floor(n * opt.start);
  const S = zc.reduce((b, z) => Math.abs(z - want) < Math.abs(b - want) ? z : b, zc[0]);
  const minE = S + Math.round(opt.min * sr); let best = null;
  for (const E of zc) {
    if (E < minE || E + W >= n) continue;
    const after = corr(x, S, E, W), before = corr(x, S - W, E - W, W);
    const lvl = Math.min(after.ea, after.eb) / (Math.max(after.ea, after.eb) + 1e-20);
    const score = 0.45 * after.r + 0.45 * before.r + 0.1 * lvl;
    if (!best || score > best.score) best = { start: S, end: E, score, jump: Math.abs(x[E] - x[S]) };
  }
  if (!best) throw new Error('file too short for --min loop length');
  return best;
}
function smpl(sr, s, e) {
  const b = Buffer.alloc(8 + 36 + 24); b.write('smpl', 0, 'ascii'); b.writeUInt32LE(60, 4);
  b.writeUInt32LE(Math.round(1e9 / sr), 8 + 8); b.writeUInt32LE(60, 8 + 12); b.writeUInt32LE(1, 8 + 28);
  b.writeUInt32LE(0, 44); b.writeUInt32LE(0, 48); b.writeUInt32LE(s, 52); b.writeUInt32LE(e - 1, 56);   // end is inclusive
  return b;
}
function files(p) {
  if (fs.statSync(p).isDirectory()) return fs.readdirSync(p).sort().flatMap(f => files(path.join(p, f)));
  return /\.wav$/i.test(p) ? [p] : [];
}
let fail = 0;
for (const f of targets.flatMap(files)) {
  try {
    const buf = fs.readFileSync(f), w = parse(buf);
    if (opt.info) {
      const c = w.chunks.find(c => c.id === 'smpl'); if (!c) { console.log(`${f}: no smpl chunk`); continue; }
      const k = buf.readUInt32LE(c.start + 8 + 28);
      for (let i = 0; i < k; i++) { const o = c.start + 8 + 36 + i * 24; console.log(`${f}: loop ${i} start ${buf.readUInt32LE(o + 8)} end ${buf.readUInt32LE(o + 12)}`); }
      continue;
    }
    const L = findLoop(mono(buf, w), w.sr);
    console.log(`${path.basename(f)}: loop ${L.start}-${L.end} (${(L.start / w.sr).toFixed(3)}s-${(L.end / w.sr).toFixed(3)}s, ${((L.end - L.start) / w.sr).toFixed(3)}s)  score ${L.score.toFixed(4)}  seam jump ${L.jump.toFixed(5)}${L.score < 0.9 ? '  [weak: material may not be loopable]' : ''}`);
    if (opt.write) {
      const keep = w.chunks.filter(c => c.id !== 'smpl').map(c => buf.subarray(c.start, c.start + 8 + c.size + (c.size & 1)));
      const body = Buffer.concat([...keep, smpl(w.sr, L.start, L.end)]), hdr = Buffer.alloc(12);
      hdr.write('RIFF', 0, 'ascii'); hdr.writeUInt32LE(body.length + 4, 4); hdr.write('WAVE', 8, 'ascii');
      const dst = opt.out ? path.join(opt.out, path.basename(f)) : f;
      if (opt.out) fs.mkdirSync(opt.out, { recursive: true });
      fs.writeFileSync(dst, Buffer.concat([hdr, body])); console.log(`  smpl chunk written -> ${dst}`);
    }
  } catch (e) { console.error(`${f}: ${e.message}`); fail++; }
}
process.exit(fail ? 1 : 0);
