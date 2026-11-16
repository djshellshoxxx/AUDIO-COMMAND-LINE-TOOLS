# sweepir - capture IMPULSE RESPONSES (rooms, cabinets, reverbs, speakers) with the exponential-sine-sweep method,
# then report the direct sound and strongest early reflections. JRuby: WAV I/O goes through the JVM's
# javax.sound.sampled, so it runs anywhere Java runs with a single jar and no native libraries.
# usage:
#   jruby sweepir.rb sweep  OUT_SWEEP.wav [--rate=48000] [--seconds=4] [--f1=20] [--f2=20000]
#        -> writes the sweep (+1 s silence) and OUT_SWEEP.inv.wav (Farina inverse filter)
#   jruby sweepir.rb deconv RECORDING.wav OUT_SWEEP.inv.wav IR.wav [--length=1.5]
#        -> FFT-deconvolves the recorded sweep into a normalised 24-bit IR and lists reflections
#   (without a jruby install:  java -jar jruby-complete.jar sweepir.rb ...)
require 'java'
java_import 'javax.sound.sampled.AudioSystem'
java_import 'javax.sound.sampled.AudioFormat'
java_import 'javax.sound.sampled.AudioInputStream'
java_import 'javax.sound.sampled.AudioFileFormat'
java_import 'java.io.ByteArrayInputStream'

def opts(args) = args.select { _1.start_with?('--') }.to_h { k, v = _1[2..].split('=', 2); [k.to_sym, v.to_f] }

def read_wav(path)   # -> [mono samples (Float), sample rate] using Java Sound
  ais = AudioSystem.getAudioInputStream(java.io.File.new(path))
  f = ais.getFormat
  raise "#{path}: only PCM_SIGNED WAV supported (got #{f.getEncoding})" unless f.getEncoding.toString == 'PCM_SIGNED'
  bytes = String.from_java_bytes(ais.readAllBytes); ais.close
  bps = f.getSampleSizeInBits / 8; ch = f.getChannels; big = f.isBigEndian
  full = 2.0**(f.getSampleSizeInBits - 1); e = big ? '>' : '<'
  ints = case bps
         when 2 then bytes.unpack("s#{e}*")
         when 4 then bytes.unpack("l#{e}*")
         when 3 then b = bytes.unpack('C*'); Array.new(b.size / 3) { |i| x = big ? (b[3 * i] << 16 | b[3 * i + 1] << 8 | b[3 * i + 2]) : (b[3 * i + 2] << 16 | b[3 * i + 1] << 8 | b[3 * i]); x >= 0x800000 ? x - 0x1000000 : x }
         else raise "#{bps * 8}-bit not supported"
         end
  [ints.each_slice(ch).map { _1.sum / (full * ch) }, f.getSampleRate.to_i]
end

def write_wav(path, x, rate)  # 24-bit mono PCM via AudioSystem.write
  buf = Java::byte[x.size * 3].new
  x.each_with_index do |v, i|
    q = (v.clamp(-1.0, 1.0) * 8_388_607).round
    3.times { |k| b = (q >> (8 * k)) & 0xff; buf[i * 3 + k] = b > 127 ? b - 256 : b }
  end
  fmt = AudioFormat.new(rate, 24, 1, true, false)
  AudioSystem.write(AudioInputStream.new(ByteArrayInputStream.new(buf), fmt, x.size), AudioFileFormat::Type::WAVE, java.io.File.new(path))
end

def fft(re, im, inv = false)   # in-place iterative radix-2
  n = re.size; j = 0
  (1...n).each do |i|
    bit = n >> 1
    while j & bit != 0 do j ^= bit; bit >>= 1 end
    j |= bit
    if i < j then re[i], re[j] = re[j], re[i]; im[i], im[j] = im[j], im[i] end
  end
  len = 2
  while len <= n
    ang = 2 * Math::PI / len * (inv ? 1 : -1); wr = Math.cos(ang); wi = Math.sin(ang); h = len / 2
    (0...n).step(len) do |s|
      cr = 1.0; ci = 0.0
      h.times do |k|
        a = s + k; b = a + h
        tr = re[b] * cr - im[b] * ci; ti = re[b] * ci + im[b] * cr
        re[b] = re[a] - tr; im[b] = im[a] - ti; re[a] += tr; im[a] += ti
        cr, ci = cr * wr - ci * wi, cr * wi + ci * wr
      end
    end
    len <<= 1
  end
  if inv then n.times { |i| re[i] /= n; im[i] /= n } end
end

cmd, *rest = ARGV; o = opts(rest); pos = rest.reject { _1.start_with?('--') }
case cmd
when 'sweep'
  abort 'usage: sweepir.rb sweep OUT.wav [--rate=48000] [--seconds=4] [--f1=20] [--f2=20000]' if pos.size != 1
  rate = (o[:rate] || 48_000).to_i; t = o[:seconds] || 4.0; f1 = o[:f1] || 20.0; f2 = [o[:f2] || 20_000.0, rate / 2.0 * 0.95].min
  n = (rate * t).to_i; l = t / Math.log(f2 / f1)
  sweep = Array.new(n) { |i| 0.5 * Math.sin(2 * Math::PI * f1 * l * (Math.exp(i.to_f / rate / l) - 1)) }
  fade = (rate * 0.01).to_i; fade.times { |i| g = i.to_f / fade; sweep[i] *= g; sweep[n - 1 - i] *= g }
  inv = Array.new(n) { |i| sweep[n - 1 - i] * Math.exp(-(i.to_f / rate) / l) }   # time-reversed, -6 dB/oct
  write_wav(pos[0], sweep + Array.new(rate, 0.0), rate)
  im = inv.map(&:abs).max
  write_wav(pos[0].sub(/\.wav\z/i, '') + '.inv.wav', inv.map { _1 / im }, rate)
  puts "sweep #{f1.round}-#{f2.round} Hz, #{t} s @ #{rate} Hz -> #{pos[0]} (+ .inv.wav). Play it, record it, then run deconv."
when 'deconv'
  abort 'usage: sweepir.rb deconv RECORDING.wav SWEEP.inv.wav IR.wav [--length=1.5]' if pos.size != 3
  rec, rate = read_wav(pos[0]); inv, r2 = read_wav(pos[1])
  abort "sample rates differ (#{rate} vs #{r2})" if rate != r2
  n = 1; n <<= 1 while n < rec.size + inv.size
  ar = rec + Array.new(n - rec.size, 0.0); ai = Array.new(n, 0.0)
  br = inv + Array.new(n - inv.size, 0.0); bi = Array.new(n, 0.0)
  fft(ar, ai); fft(br, bi)
  n.times { |i| ar[i], ai[i] = ar[i] * br[i] - ai[i] * bi[i], ar[i] * bi[i] + ai[i] * br[i] }
  fft(ar, ai, true)
  peak = (0...n).max_by { ar[_1].abs }; pre = (rate * 0.005).to_i
  len = ((o[:length] || 1.5) * rate).to_i; st = [peak - pre, 0].max
  ir = ar[st, len]; g = ir.map(&:abs).max; ir.map! { _1 / g }
  write_wav(pos[2], ir, rate)
  noise = ir[-(len / 10)..].sum { _1 * _1 } / (len / 10); snr = 10 * Math.log10(1.0 / (noise + 1e-30))
  puts "IR: #{pos[2]}  #{len} samples @ #{rate} Hz, direct sound at #{'%.2f' % ((peak - (inv.size - 1)).to_f / rate * 1000)} ms latency, peak-to-tail #{snr.round(1)} dB"
  gap = (rate * 0.001).to_i; picks = []                               # strongest local maxima >= 1 ms apart
  (pre + gap...ir.size - 1).sort_by { -ir[_1].abs }.each do |i|
    break if picks.size >= 5 || ir[i].abs < 0.03
    picks << i if picks.all? { (_1 - i).abs > gap } && (i - pre).abs > gap
  end
  picks.sort.each { |i| printf "  reflection +%7.2f ms  %6.1f dB%s\n", (i - pre) * 1000.0 / rate, 20 * Math.log10(ir[i].abs), ir[i] < 0 ? '  (inverted)' : '' }
else
  abort "usage: sweepir.rb sweep|deconv ...  (see header)"
end
