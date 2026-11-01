// Assemble mbui pictures and films on a frame-addressed timeline without opening a window or browser.
import { createHash } from 'node:crypto';
import { closeSync, existsSync, mkdirSync, mkdtempSync, openSync, readFileSync, readSync, realpathSync,
  renameSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, extname, isAbsolute, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const usage = 'media-compose.mjs film TIMELINE.json OUTPUT.mp4 | still TIMELINE.json FRAME OUTPUT.png';
function fail(message) { throw new Error(`media-compose: ${message}`); }
function whole(value, name, min = 0) {
  if (!Number.isSafeInteger(value) || value < min) fail(`${name} must be a whole number of at least ${min}`);
  return value;
}
function fileHash(file) {
  const fd = openSync(file, 'r');
  const hash = createHash('sha256');
  const buf = Buffer.allocUnsafe(1024 * 1024);
  try {
    for (;;) {
      const n = readSync(fd, buf, 0, buf.length, null);
      if (!n) break;
      hash.update(buf.subarray(0, n));
    }
    return hash.digest('hex');
  } finally { closeSync(fd); }
}
function call(command, argv, capture = false) {
  const result = spawnSync(command, argv, { encoding: 'utf8', stdio: capture ? ['ignore', 'pipe', 'pipe'] : 'inherit' });
  if (result.error) fail(`${command}: ${result.error.message}`);
  if (result.status !== 0) fail(`${command} failed${capture && result.stderr ? `: ${result.stderr.trim()}` : ''}`);
  return result.stdout;
}

function main() {
  const [, , mode, manifestArg, fourth, fifth, ...rest] = process.argv;
  if (rest.length || !manifestArg || !fourth || !['film', 'still'].includes(mode) ||
      (mode === 'film' && fifth !== undefined) || (mode === 'still' && !fifth)) fail(usage);
  const frame = mode === 'still' ? whole(Number(fourth), 'frame') : null;
  const output = resolve(mode === 'film' ? fourth : fifth);
  if (extname(output).toLowerCase() !== (mode === 'film' ? '.mp4' : '.png')) fail(usage);
  const manifestPath = realpathSync(resolve(manifestArg));
  const manifestText = readFileSync(manifestPath, 'utf8');
  const manifestSha = createHash('sha256').update(manifestText).digest('hex');
  const toolSha = fileHash(fileURLToPath(import.meta.url));
  const manifest = JSON.parse(manifestText);
  const width = whole(manifest.width, 'width', 2), height = whole(manifest.height, 'height', 2);
  const fps = whole(manifest.fps, 'fps', 1);
  if (width % 2 || height % 2) fail('width and height must be even');
  if (!Array.isArray(manifest.scenes) || !manifest.scenes.length) fail('at least one scene is required');
  const colour = manifest.background ?? '#000000';
  if (typeof colour !== 'string' || !/^#[0-9a-fA-F]{6}$/.test(colour)) fail('background must be #RRGGBB');
  const base = dirname(manifestPath);
  const inputs = new Map();
  function input(name, label) {
    if (typeof name !== 'string' || !name) fail(`${label} needs a path`);
    const absolute = realpathSync(isAbsolute(name) ? name : resolve(base, name));
    const stat = statSync(absolute, { bigint: true });
    if (!stat.isFile()) fail(`${label} is not a file`);
    if (!inputs.has(absolute)) inputs.set(absolute, { path: name, sha256: fileHash(absolute),
      stamp: [stat.dev, stat.ino, stat.size, stat.mtimeNs, stat.ctimeNs] });
    return absolute;
  }
  const scenes = manifest.scenes.map((s, i) => {
    if (!s || typeof s !== 'object') fail(`scene ${i} is not an object`);
    const kind = s.kind ?? 'film';
    if (kind !== 'film' && kind !== 'picture') fail(`scene ${i} kind must be film or picture`);
    const start = whole(s.start_frame ?? 0, `scene ${i} start_frame`);
    const frames = whole(s.frames, `scene ${i} frames`, 1);
    if (!Number.isSafeInteger(start + frames)) fail(`scene ${i} is too long`);
    return { path: input(s.path, `scene ${i}`), kind, start, frames };
  });
  const total = scenes.reduce((n, s) => n + s.frames, 0);
  whole(total, 'total frames', 1);
  if (frame !== null && frame >= total) fail(`frame ${frame} is outside the ${total}-frame timeline`);
  if (manifest.overlays !== undefined && !Array.isArray(manifest.overlays)) fail('overlays must be an array');
  if (manifest.audio !== undefined && !Array.isArray(manifest.audio)) fail('audio must be an array');
  const overlays = (manifest.overlays ?? []).map((o, i) => {
    if (!o || typeof o !== 'object') fail(`overlay ${i} is not an object`);
    const at = whole(o.at, `overlay ${i} at`), until = whole(o.until, `overlay ${i} until`, 1);
    if (at >= until || until > total) fail(`overlay ${i} has an invalid frame range`);
    const x = whole(o.x ?? 0, `overlay ${i} x`, -Number.MAX_SAFE_INTEGER);
    const y = whole(o.y ?? 0, `overlay ${i} y`, -Number.MAX_SAFE_INTEGER);
    return { path: input(o.path, `overlay ${i}`), at, until, x, y };
  });
  const audio = (manifest.audio ?? []).map((a, i) => {
    if (!a || typeof a !== 'object') fail(`audio ${i} is not an object`);
    const at = whole(a.at ?? 0, `audio ${i} at`), gain = a.gain ?? 1;
    if (at >= total || typeof gain !== 'number' || !Number.isFinite(gain) || gain < 0) fail(`audio ${i} has invalid timing or gain`);
    return { path: input(a.path, `audio ${i}`), at, gain };
  });
  if (inputs.has(output) || output === manifestPath ||
      (existsSync(output) && (inputs.has(realpathSync(output)) || realpathSync(output) === manifestPath))) {
    fail('output cannot overwrite an input');
  }
  const recordPath = output + '.timeline.json';
  if (inputs.has(recordPath) || recordPath === manifestPath ||
      (existsSync(recordPath) && (inputs.has(realpathSync(recordPath)) || realpathSync(recordPath) === manifestPath))) {
    fail('record cannot overwrite an input');
  }
  const available = Number(process.env.STILLFAIL_CPUS ?? 4);
  const threads = Number.isSafeInteger(available) && available > 0 ? Math.min(available, 4) : 1;
  const argv = ['-hide_banner', '-loglevel', 'error', '-y', '-filter_complex_threads', String(threads)];
  for (const s of scenes) {
    if (s.kind === 'picture') argv.push('-loop', '1', '-framerate', String(fps));
    argv.push('-i', s.path);
  }
  for (const o of overlays) argv.push('-loop', '1', '-framerate', String(fps), '-i', o.path);
  if (mode === 'film') for (const a of audio) argv.push('-i', a.path);
  const filters = [];
  scenes.forEach((s, i) => {
    filters.push(`[${i}:v:0]fps=${fps},trim=start_frame=${s.start}:end_frame=${s.start + s.frames},` +
      `setpts=PTS-STARTPTS,scale=${width}:${height}:force_original_aspect_ratio=decrease,` +
      `pad=${width}:${height}:(ow-iw)/2:(oh-ih)/2:color=0x${colour.slice(1)},setsar=1,format=rgba[scene${i}]`);
  });
  filters.push(`${scenes.map((_, i) => `[scene${i}]`).join('')}concat=n=${scenes.length}:v=1:a=0[base]`);
  let video = 'base';
  overlays.forEach((o, i) => {
    const overlay = scenes.length + i, next = `over${i}`;
    filters.push(`[${video}][${overlay}:v:0]overlay=x=${o.x}:y=${o.y}:format=auto:` +
      `enable='between(n,${o.at},${o.until - 1})':eof_action=repeat[${next}]`);
    video = next;
  });
  if (mode === 'still') {
    filters.push(`[${video}]select='eq(n,${frame})'[picture]`);
    video = 'picture';
  } else {
    filters.push(`[${video}]format=yuv420p[film]`);
    video = 'film';
  }
  if (mode === 'film' && audio.length) {
    audio.forEach((a, i) => {
      const index = scenes.length + overlays.length + i;
      const delay = Math.round(a.at * 48000 / fps);
      filters.push(`[${index}:a:0]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,` +
        `asetpts=PTS-STARTPTS,volume=${a.gain},adelay=${delay}S:all=1[audio${i}]`);
    });
    const end = Math.round(total * 48000 / fps);
    filters.push(`${audio.map((_, i) => `[audio${i}]`).join('')}amix=inputs=${audio.length}:` +
      `duration=longest:dropout_transition=0:normalize=0,apad,atrim=end_sample=${end}[sound]`);
  }
  argv.push('-filter_complex', filters.join(';'), '-map', `[${video}]`);
  if (mode === 'film' && audio.length) argv.push('-map', '[sound]', '-c:a', 'aac', '-b:a', '192k');
  if (mode === 'film') argv.push('-c:v', 'libx264', '-preset', 'veryfast', '-threads', String(threads), '-pix_fmt', 'yuv420p',
    '-r', String(fps), '-frames:v', String(total), '-movflags', '+faststart');
  else argv.push('-frames:v', '1', '-fps_mode', 'passthrough');
  mkdirSync(dirname(output), { recursive: true });
  const tmp = mkdtempSync(join(dirname(output), '.mbui-compose-'));
  try {
    const result = join(tmp, mode === 'film' ? 'result.mp4' : 'result.png');
    call('ffmpeg', [...argv, result]);
    if (mode === 'film') {
      const info = JSON.parse(call('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-show_entries',
        'stream=width,height,r_frame_rate,nb_frames', '-of', 'json', result], true)).streams?.[0];
      if (!info || info.width !== width || info.height !== height || info.r_frame_rate !== `${fps}/1` ||
          Number(info.nb_frames) !== total) fail('the completed film has the wrong dimensions, frame rate or length');
    } else {
      const header = Buffer.alloc(24);
      const fd = openSync(result, 'r');
      let read;
      try { read = readSync(fd, header, 0, header.length, 0); } finally { closeSync(fd); }
      if (read < 24 || header.readUInt32BE(16) !== width || header.readUInt32BE(20) !== height) {
        fail('the completed picture has the wrong dimensions');
      }
    }
    for (const [path, info] of inputs) {
      const stat = statSync(path, { bigint: true });
      const now = [stat.dev, stat.ino, stat.size, stat.mtimeNs, stat.ctimeNs];
      if (now.some((value, i) => value !== info.stamp[i])) fail(`input changed during rendering: ${info.path}`);
    }
    const record = { version: 1, kind: mode, frame, timeline: manifest, timeline_sha256: manifestSha,
      tool_sha256: toolSha, node: process.version,
      ffmpeg: call('ffmpeg', ['-version'], true).split('\n')[0],
      inputs: [...inputs.values()].map(({ path, sha256 }) => ({ path, sha256 })), output_sha256: fileHash(result) };
    writeFileSync(join(tmp, 'record.json'), JSON.stringify(record, null, 2) + '\n');
    renameSync(result, output);
    renameSync(join(tmp, 'record.json'), recordPath);
    console.log(`media-compose: ${output} (${mode === 'film' ? `${total} frames at ${fps} fps` : `frame ${frame}`})`);
    console.log(`media-compose: ${recordPath}`);
  } finally { rmSync(tmp, { recursive: true, force: true }); }
}

try { main(); } catch (error) { console.error(error.message); process.exitCode = 1; }
