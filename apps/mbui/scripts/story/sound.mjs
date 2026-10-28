// Film 1's sound (compose_sim.mjs): a light music bed made here (no samples: soft pads, a plucked arpeggio, a bass and,
// once the agent works, a soft beat) and the sounds of what happens on the phone, on the film's marks: a click where a
// finger taps, a whoosh as the words go, a chime as the answer comes, the hinge as it opens, a rising chime as it is
// merged. Written as a 48 kHz stereo WAV `seconds` long.
import { writeFileSync } from 'node:fs';

const RATE = 48000;

// a seeded noise, the same each run
function noise(seed = 1) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 2 ** 31 - 1;
  };
}

// a biquad (RBJ's cookbook): 'lp', 'hp' or 'bp' at f with q
function biquad(type, f, q) {
  const w = 2 * Math.PI * f / RATE, cw = Math.cos(w), a = Math.sin(w) / (2 * q);
  let b0, b1, b2;
  if (type === 'lp') [b0, b1, b2] = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2];
  else if (type === 'hp') [b0, b1, b2] = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2];
  else [b0, b1, b2] = [a, 0, -a];
  const a0 = 1 + a, a1 = -2 * cw, a2 = 1 - a;
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  return (x) => {
    const y = (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0;
    x2 = x1; x1 = x; y2 = y1; y1 = y;
    return y;
  };
}

const hz = (midi) => 440 * 2 ** ((midi - 69) / 12);

export function filmSound({ seconds, marks, taps, unfold, flip, end, out }) {
  const n = Math.ceil(seconds * RATE);
  const L = new Float32Array(n), R = new Float32Array(n);
  const add = (t0, len, fn, gain = 1, pan = 0) => {
    const i0 = Math.max(0, Math.round(t0 * RATE)), m = Math.min(n - i0, Math.round(len * RATE));
    const gl = gain * Math.cos((pan + 1) * Math.PI / 4), gr = gain * Math.sin((pan + 1) * Math.PI / 4);
    for (let i = 0; i < m; i++) {
      const v = fn(i / RATE);
      L[i0 + i] += v * gl;
      R[i0 + i] += v * gr;
    }
  };

  // ---- the music: 100 a minute, four chords two bars each, round and round ----
  const beat = 60 / 100, bar = beat * 4;
  const chords = [
    [53, 57, 60, 64], // Fmaj7
    [55, 59, 62, 64], // G6
    [52, 55, 59, 62], // Em7
    [57, 60, 64, 67], // Am7
  ];
  const fadeIn = 1.2, musicEnd = end + 1.4;
  const level = (t) => Math.min(1, t / fadeIn) * Math.max(0, Math.min(1, (musicEnd - t) / 1.6));
  for (let b = 0; b * bar < musicEnd; b += 2) {
    const ch = chords[(b / 2) % chords.length], t0 = b * bar, len = bar * 2 + 0.6;
    // a pad: each note three sines a little apart, slow in and out
    for (const [k, m] of ch.entries()) {
      const f = hz(m), pan = (k - 1.5) * 0.35;
      add(t0, len, (t) => {
        const env = Math.min(1, t / 0.9) * Math.min(1, (len - t) / 0.7);
        return env * (Math.sin(2 * Math.PI * f * t) + 0.5 * Math.sin(2 * Math.PI * f * 1.003 * t + 1) +
          0.35 * Math.sin(2 * Math.PI * f * 2.001 * t + 2) * 0.5) * level(t0 + t);
      }, 0.028, pan);
    }
    // the bass: the root on each bar's first beat and its third
    for (let q = 0; q < 4; q++) {
      const tb = t0 + q * beat * 2, f = hz(ch[0] - 12);
      add(tb, beat * 2, (t) => Math.exp(-t * 2.2) * Math.min(1, t / 0.01) *
        (Math.sin(2 * Math.PI * f * t) + 0.3 * Math.sin(4 * Math.PI * f * t)) * level(tb + t), 0.11);
    }
    // a pluck on each eighth, up and down the chord an octave up
    const order = [0, 1, 2, 3, 2, 1, 2, 3];
    for (let e = 0; e < 16; e++) {
      const te = t0 + e * beat / 2, f = hz(ch[order[e % 8]] + 12);
      add(te, 0.9, (t) => Math.exp(-t * 6) * Math.min(1, t / 0.004) *
        (Math.sin(2 * Math.PI * f * t) + 0.25 * Math.sin(6 * Math.PI * f * t) * Math.exp(-t * 14)) * level(te + t),
        0.045, e % 2 ? 0.3 : -0.3);
    }
  }
  // the beat, from the agent at work till the end: a soft kick on each beat, a hat on the offbeats
  const r = noise(7);
  const hat = biquad('hp', 7000, 0.7);
  for (let t0 = Math.ceil(marks.working / beat) * beat; t0 < end; t0 += beat) {
    add(t0, 0.3, (t) => Math.sin(2 * Math.PI * (50 + 70 * Math.exp(-t * 30)) * t) * Math.exp(-t * 12) * level(t0 + t), 0.16);
    add(t0 + beat / 2, 0.06, (t) => hat(r()) * Math.exp(-t * 60) * level(t0 + t), 0.05, 0.2);
  }

  // ---- what happens on the phone ----
  // a finger's tap: a short soft click
  for (const t0 of taps) {
    const lp = biquad('bp', 2400, 1.2), rr = noise(Math.round(t0 * 1000));
    add(t0, 0.03, (t) => (lp(rr()) * 2 + Math.sin(2 * Math.PI * 1800 * t) * 0.5) * Math.exp(-t * 220), 0.32);
  }
  // typing: a key's tick for each key pressed, the words of each `type=` mark coming in over the time before the next
  // mark (a character of Chinese some three keys of its pinyin, one of a Latin script one), a little uneven
  {
    const names = Object.keys(marks).filter((k) => k.startsWith('type=')).sort((a, b) => marks[a] - marks[b]);
    const all = Object.values(marks).sort((a, b) => a - b);
    const rr = noise(31);
    for (const k of names) {
      const t0 = marks[k], words = k.slice(5);
      const next = all.find((t) => t > t0 + 1e-3) ?? t0 + 0.5;
      const keys = [...words].reduce((n, ch) => n + (/[\u3400-\u9fff]/.test(ch) ? 3 : /\s/.test(ch) ? 1 : 1), 0);
      const span = Math.max(0.15, Math.min(next - t0 - 0.05, keys * 0.11));
      for (let i = 0; i < keys; i++) {
        const tk = t0 - span + span * (i + 0.5 * (1 + 0.6 * (rr() * 0.5))) / keys;
        const bp = biquad('bp', 3200 + 900 * rr(), 1.6), lp = biquad('lp', 900, 0.8), r2 = noise(Math.round(tk * 997));
        add(tk, 0.035, (t) => (bp(r2()) * 1.6 + lp(r2()) * 0.8) * Math.exp(-t * 160) * Math.min(1, t / 0.0008), 0.22,
          0.15 * (rr() * 0.5));
      }
    }
  }
  // the words sent: a whoosh going up
  {
    const t0 = marks['tap=send'] + 0.08, len = 0.38, rr = noise(11);
    let f = biquad('bp', 600, 1.5);
    add(t0, len, (t) => {
      if (Math.round(t * RATE) % 64 === 0) f = biquad('bp', 500 + 3500 * (t / len), 1.4);
      return f(rr()) * Math.sin(Math.PI * t / len) ** 2;
    }, 0.5, 0.1);
  }
  // the answer come: two soft bell notes
  for (const [d, m] of [[0, 81], [0.12, 88]]) {
    const t0 = marks.answer + 0.05 + d, f = hz(m);
    add(t0, 1.4, (t) => Math.exp(-t * 4) * Math.min(1, t / 0.003) *
      (Math.sin(2 * Math.PI * f * t) + 0.3 * Math.sin(2 * Math.PI * f * 2.76 * t) * Math.exp(-t * 8)), 0.12, 0.15);
  }
  // the phone opening: a low swoosh over the flip, and the hinge settling at its end
  {
    const rr = noise(23);
    let f = biquad('bp', 300, 0.9);
    add(unfold, flip, (t) => {
      if (Math.round(t * RATE) % 64 === 0) f = biquad('bp', 250 + 900 * Math.sin(Math.PI * t / flip), 0.9);
      return f(rr()) * Math.sin(Math.PI * t / flip) ** 1.5;
    }, 0.55);
    const t1 = unfold + flip * 0.92;
    add(t1, 0.12, (t) => (Math.sin(2 * Math.PI * 140 * t) + 0.4 * Math.sin(2 * Math.PI * 420 * t)) * Math.exp(-t * 45), 0.3);
  }
  // merged: a rising chime
  for (const [d, m] of [[0, 72], [0.09, 76], [0.18, 79], [0.27, 84]]) {
    const t0 = marks.merged + 0.05 + d, f = hz(m + 12);
    add(t0, 1.6, (t) => Math.exp(-t * 3.2) * Math.min(1, t / 0.003) *
      (Math.sin(2 * Math.PI * f * t) + 0.25 * Math.sin(2 * Math.PI * f * 3 * t) * Math.exp(-t * 9)), 0.09, (d - 0.13) * 2);
  }

  // ---- out: kept under full scale, 16 bit ----
  let peak = 0;
  for (let i = 0; i < n; i++) peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
  const g = peak > 0.89 ? 0.89 / peak : 1;
  const buf = Buffer.alloc(44 + n * 4);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * 4, 4); buf.write('WAVE', 8); buf.write('fmt ', 12);
  buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22); buf.writeUInt32LE(RATE, 24);
  buf.writeUInt32LE(RATE * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34); buf.write('data', 36);
  buf.writeUInt32LE(n * 4, 40);
  for (let i = 0; i < n; i++) {
    buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, L[i] * g)) * 32767), 44 + i * 4);
    buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, R[i] * g)) * 32767), 46 + i * 4);
  }
  writeFileSync(out, buf);
}
