#!/usr/bin/env lua5.4
-- tunecents - detect the TUNING REFERENCE of a recording: how many cents it sits off A=440 equal temperament
-- (A=432 tracks, detuned vinyl rips, 442/443 orchestras, pitched samples). Pure Lua 5.3+, no libraries.
-- Method: crude 4x-decimated mono, per-frame normalized autocorrelation pitch with parabolic interpolation,
-- keep only clearly periodic frames, fold each pitch onto the semitone grid, circular-mean the deviation.
-- usage: lua tunecents.lua FILE.wav [FILE.wav ...]     (PCM 16/24/32-bit int or 32-bit float WAV)
local function readwav(path)
  local f = assert(io.open(path, "rb")); local d = f:read("a"); f:close()
  assert(d:sub(1, 4) == "RIFF" and d:sub(9, 12) == "WAVE", "not a WAV file")
  local pos, fmt, data = 13
  while pos + 8 <= #d do
    local id, size = d:sub(pos, pos + 3), string.unpack("<I4", d, pos + 4)
    if id == "fmt " then fmt = { string.unpack("<I2I2I4I4I2I2", d, pos + 8) }
      if fmt[1] == 0xFFFE and size >= 26 then fmt[1] = string.unpack("<I2", d, pos + 32) end  -- EXTENSIBLE subformat
    elseif id == "data" then data = { pos + 8, math.min(size, #d - pos - 7) } end
    pos = pos + 8 + size + (size % 2)
  end
  assert(fmt and data, "missing fmt or data chunk")
  local tag, ch, sr, _, align, bits = table.unpack(fmt)
  local bps, code = bits // 8
  if tag == 3 then code = "<f" elseif bps == 2 then code = "<i2" elseif bps == 3 then code = "<i3" elseif bps == 4 then code = "<i4"
  else error("unsupported bit depth " .. bits) end
  local scale = tag == 3 and 1 or 2 ^ (bits - 1)
  local dec = math.max(1, sr // 11025); local maxf = math.min(data[2] // align, sr * 60)
  local x, n = {}, 0
  for i = 0, maxf - dec, dec do                 -- average `dec` frames of all channels = crude low-pass + decimate
    local s = 0
    for k = 0, dec - 1 do for c = 0, ch - 1 do s = s + string.unpack(code, d, data[1] + (i + k) * align + c * bps) end end
    n = n + 1; x[n] = s / (dec * ch * scale)
  end
  return x, sr / dec
end
local function analyse(path)
  local x, sr = readwav(path)
  local W, H = 1024, 512
  local minlag, maxlag = math.floor(sr / 600), math.ceil(sr / 80)
  local sx, sy, used, frames = 0, 0, 0, 0
  for st = 1, #x - W - maxlag, H do
    frames = frames + 1
    local e = 0; for i = st, st + W - 1 do e = e + x[i] * x[i] end
    if e > 1e-4 * W then
      local best, bl, r = -1, nil, {}
      for lag = minlag - 1, maxlag + 1 do
        local s, e2 = 0, 0
        for i = st, st + W - 1 do local y = x[i + lag]; s = s + x[i] * y; e2 = e2 + y * y end
        r[lag] = s / math.sqrt(e * e2 + 1e-12)
      end
      for lag = minlag, maxlag do                      -- first strong peak avoids octave errors
        if r[lag] > r[lag - 1] and r[lag] >= r[lag + 1] and r[lag] > 0.9 then best, bl = r[lag], lag; break end
      end
      if bl then
        local a, b, c = r[bl - 1], r[bl], r[bl + 1]
        local den = a - 2 * b + c
        local lag = bl + (den ~= 0 and 0.5 * (a - c) / den or 0)
        local cents = 1200 * math.log(sr / lag / 440, 2)
        local dev = cents - 100 * math.floor(cents / 100 + 0.5)
        local th = dev / 100 * 2 * math.pi
        sx, sy, used = sx + math.cos(th), sy + math.sin(th), used + 1
      end
    end
  end
  if used < 5 then print(string.format("%s: not enough pitched material (%d/%d frames)", path, used, frames)); return end
  local dev = math.atan(sy, sx) / (2 * math.pi) * 100
  local conf = math.sqrt(sx * sx + sy * sy) / used
  print(string.format("%s: %+.1f cents vs A440  ->  A = %.1f Hz  (confidence %.2f, %d/%d pitched frames)%s",
    path, dev, 440 * 2 ^ (dev / 1200), conf, used, frames, conf < 0.5 and "  [low confidence]" or ""))
end
if #arg == 0 then io.stderr:write("usage: lua tunecents.lua FILE.wav [...]\n"); os.exit(2) end
for _, p in ipairs(arg) do local ok, err = pcall(analyse, p); if not ok then print(p .. ": ERROR " .. tostring(err)) end end
