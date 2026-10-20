
import zlib from "node:zlib";

export function decodePNG(buf) {
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error("not png");
  let off = 8, width = 0, height = 0, bitDepth = 0, colorType = 0;
  const idat = [];
  while (off < buf.length) {
    const len = buf.readUInt32BE(off); const type = buf.toString("ascii", off + 4, off + 8);
    const data = buf.subarray(off + 8, off + 8 + len);
    if (type === "IHDR") {
      width = data.readUInt32BE(0); height = data.readUInt32BE(4);
      bitDepth = data[8]; colorType = data[9];
      if (bitDepth !== 8) throw new Error("bit depth " + bitDepth);
      if (colorType !== 6 && colorType !== 2) throw new Error("color type " + colorType);
    } else if (type === "IDAT") idat.push(data);
    else if (type === "IEND") break;
    off += 12 + len;
  }
  const channels = colorType === 6 ? 4 : 3;
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = width * channels;
  const out = Buffer.alloc(width * height * channels);
  let pos = 0;
  for (let y = 0; y < height; y++) {
    const f = raw[pos++];
    const line = raw.subarray(pos, pos + stride); pos += stride;
    const prev = y > 0 ? out.subarray((y - 1) * stride, y * stride) : null;
    const cur = out.subarray(y * stride, (y + 1) * stride);
    for (let x = 0; x < stride; x++) {
      const a = x >= channels ? cur[x - channels] : 0;
      const b = prev ? prev[x] : 0;
      const c = prev && x >= channels ? prev[x - channels] : 0;
      let v = line[x];
      if (f === 1) v = (v + a) & 255;
      else if (f === 2) v = (v + b) & 255;
      else if (f === 3) v = (v + ((a + b) >> 1)) & 255;
      else if (f === 4) {
        const p = a + b - c; const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        v = (v + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c)) & 255;
      }
      cur[x] = v;
    }
  }
  return { width, height, channels, data: out };
}

export function pixel(img, x, y) {
  const i = (y * img.width + x) * img.channels;
  const d = img.data;
  return [d[i], d[i + 1], d[i + 2], img.channels === 4 ? d[i + 3] : 255];
}

// luminance ascii: chars dark -> light
const RAMP = " .:-=+*#%@";
export function asciiPreview(img, opts = {}) {
  const cols = opts.cols || 110;
  const rows = opts.rows || Math.max(12, Math.round(cols * (img.height / img.width) * 0.5));
  const color = opts.color || false;
  let out = "";
  for (let ry = 0; ry < rows; ry++) {
    let line = "";
    for (let rx = 0; rx < cols; rx++) {
      const x0 = Math.floor(rx * img.width / cols), x1 = Math.max(x0 + 1, Math.floor((rx + 1) * img.width / cols));
      const y0 = Math.floor(ry * img.height / rows), y1 = Math.max(y0 + 1, Math.floor((ry + 1) * img.height / rows));
      let r = 0, g = 0, b = 0, n = 0;
      for (let y = y0; y < y1; y += 2) for (let x = x0; x < x1; x += 2) {
        const p = pixel(img, x, y); r += p[0]; g += p[1]; b += p[2]; n++;
      }
      r /= n; g /= n; b /= n;
      const lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      let ch = RAMP[Math.min(RAMP.length - 1, Math.max(0, Math.round(lum / 255 * (RAMP.length - 1))))];
      if (color) {
        const bucket = (r >> 5) * 64 + (g >> 5) * 8 + (b >> 5);
        ch = String.fromCharCode(0x2580 + (bucket % 16)); // not real color; placeholder
      }
      line += ch;
    }
    out += line + "\n";
  }
  return out;
}

// average color over a rectangle given in 0..1 normalized coords
export function regionAvg(img, rx0, ry0, rx1, ry1) {
  const x0 = Math.floor(rx0 * img.width), x1 = Math.ceil(rx1 * img.width);
  const y0 = Math.floor(ry0 * img.height), y1 = Math.ceil(ry1 * img.height);
  let r = 0, g = 0, b = 0, n = 0;
  for (let y = y0; y < y1; y += 2) for (let x = x0; x < x1; x += 2) {
    const p = pixel(img, x, y); r += p[0]; g += p[1]; b += p[2]; n++;
  }
  return [Math.round(r / n), Math.round(g / n), Math.round(b / n)];
}

export function globalStats(img) {
  const d = img.data, ch = img.channels;
  let n = 0, sum = 0, min = 255, max = 0, dark = 0, bright = 0;
  let rs = 0, gs = 0, bs = 0;
  for (let i = 0; i < d.length; i += ch * 17) {
    const r = d[i], g = d[i + 1], b = d[i + 2];
    const l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    sum += l; n++; rs += r; gs += g; bs += b;
    if (l < min) min = l; if (l > max) max = l;
    if (l < 12) dark++; if (l > 243) bright++;
  }
  return { meanLum: +(sum / n).toFixed(1), minLum: +min.toFixed(1), maxLum: +max.toFixed(1),
    darkFrac: +(dark / n).toFixed(3), brightFrac: +(bright / n).toFixed(3),
    avgR: Math.round(rs / n), avgG: Math.round(gs / n), avgB: Math.round(bs / n) };
}

// distinct quantized colors summary: top N colors by frequency
export function topColors(img, n = 10) {
  const counts = new Map();
  const d = img.data, ch = img.channels;
  for (let i = 0; i < d.length; i += ch * 7) {
    const key = ((d[i] >> 4) << 8) | ((d[i + 1] >> 4) << 4) | (d[i + 2] >> 4);
    counts.set(key, (counts.get(key) || 0) + 1);
  }
  const total = [...counts.values()].reduce((a, b) => a + b, 0);
  return [...counts.entries()].sort((a, b) => b[1] - a[1]).slice(0, n).map(([k, c]) => {
    const r = ((k >> 8) & 15) * 17, g = ((k >> 4) & 15) * 17, b = (k & 15) * 17;
    return { hex: "#" + [r, g, b].map(v => v.toString(16).padStart(2, "0")).join(""), frac: +(c / total).toFixed(3) };
  });
}
