// Browser host for the MoonBit UI prototype: a WebGL2 canvas drawing the
// same instances as the Metal renderer, canvas-2D text rasterized into an
// atlas, and a hidden textarea that receives the system input method.
(() => {
  const FAMILY = 'system-ui, -apple-system, "PingFang SC", "Noto Sans CJK SC", "Segoe UI", sans-serif';
  // the code face (style bit 2), its Han from the system's sans
  // the serif face (style bit 4): a reader's 宋体
  const SERIF = '"Songti SC", "Noto Serif CJK SC", "Source Han Serif SC", SimSun, serif';
  const MONO = 'ui-monospace, "SF Mono", Menlo, Consolas, "JetBrains Mono", "PingFang SC", "Noto Sans CJK SC", monospace';
  const ATLAS = 2048;
  const params = new URLSearchParams(location.search);
  const H = {};
  let cb = null;
  let canvas, gl, prog, post, vao, instBuf, atlasTex, ta;
  const U = {}, PU = {};
  let cssW = 0, cssH = 0, dpr = 1;
  // the numbers of an instance (src/ui/scene.mbt)
  const INST = 32;
  let f32 = new Float32Array(INST * 4096);
  let pending = false;
  window.__logs = [];

  // ---- frames ----
  // A picture at a declared moment (?shot_at=MS, scripts/web-shot.mjs): the run's frames are on a clock of their own,
  // 1/60 s a frame from 0, as a stable run's on macOS (mac_app.m), and drawn one a display frame whether the app asks
  // for them or not, until that clock reaches MS; that frame drawn, no other, and the page says so (window.__shot:
  // its frame and time, "SHOT n t" on the log). The clock stands still while the app awaits the host (an image
  // decoding: what its last frame said), so the picture is of the app at MS on its own clock, however fast the
  // machine is. The app's timers and its reads of the clock are on that clock too.
  // shot_at=rest: at the first frame that left nothing that ends to come (no motion short of its end, no wake owed,
  // nothing of the app's runtime running: @ui's Ctx::at_rest; nothing posted that no frame took; a spinner turns on, at
  // its clock's turn), a failure saying what kept it (window.__shot.fail, "SHOT FAIL") when none has by a minute on
  // its clock.
  const shotRest = params.get('shot_at') === 'rest';
  const shotAt = shotRest ? 0 : params.has('shot_at') ? Number(params.get('shot_at')) : -1;
  let unrest = '-';
  let clock = 0;
  let frames = 0, inFrame = false;
  function tick() {
    pending = false;
    resize();
    inFrame = true;
    const t = shotAt >= 0 ? clock : performance.now();
    cb.frame(cssW, cssH, dpr, t);
    inFrame = false;
    frames++;
    if (shotAt < 0) return;
    if (awaiting > 0) return;  // the clock stands still; the host's answer asks for the next frame
    const rested = unrest === '' && posted.length === 0;
    if (shotRest && !rested && (t >= 60000 || unrest.startsWith('never: '))) {
      const fail = unrest.startsWith('never: ') ? 'at rest, but ' + unrest.slice(7)
        : 'not at rest after 60 s on its clock: ' + (unrest || 'a message posted that no frame took');
      window.__shot = { frame: frames, t, fail };
      H.log('SHOT FAIL: ' + fail);
      return;
    }
    if (shotRest ? rested : t >= shotAt) {
      window.__shot = { frame: frames, t };
      H.log(`SHOT ${frames} ${t}`);
      return;
    }
    clock = frames * (1000 / 60);
    H.requestFrame();
  }
  // (no frame before the host knows what it decodes: H.run)
  let known = false;
  H.requestFrame = () => {
    if (!pending && cb && known && window.__done === undefined && window.__shot === undefined) {
      pending = true;
      requestAnimationFrame(tick);
    }
  };
  // (a run to a declared moment draws every frame to it: its timers are on its clock, due at the frame they fall in)
  H.wakeAfter = (ms) => { if (shotAt < 0) setTimeout(H.requestFrame, ms); };
  H.now = () => (shotAt >= 0 ? clock : performance.now());
  H.ownClock = () => shotAt >= 0;
  // the time of day (@host.wall_ms): a run to a declared moment's from a fixed day (@ui.tester_wall's), on with its
  // clock, so what it shows of it is the same each run
  H.wallMs = () => (shotAt >= 0 ? 1790000000000 + clock : Date.now());

  // ---- messages from outside the frames (src/ui/messages.mbt; mbui's mb_post on the native hosts) ----
  // H.post(channel, json, bytes?): kept for the next frame, which takes all that came and hands them on in their
  // order; the first since a frame took the last asks for that frame, the rest wait for it.
  const posted = [];
  let postTaken = [], postCur = null;
  H.post = (channel, json, bytes) => {
    if (!channel) return;
    const first = posted.length === 0;
    posted.push([String(channel), String(json), bytes ? new Uint8Array(bytes) : new Uint8Array(0)]);
    if (first) H.requestFrame();
  };
  H.postTake = () => {
    postTaken = postTaken.concat(posted.splice(0));
    return postTaken.length;
  };
  H.postNext = () => {
    postCur = postTaken.shift() || null;
    return postCur ? postCur[0] : '';
  };
  H.postJson = () => (postCur ? postCur[1] : '');
  H.postBytes = () => (postCur ? postCur[2] : new Uint8Array(0));

  // ---- what the app awaits of the host (effect.mb's outside: src/ui/hostcall.mbt) ----
  // The app is told (outside(kind, id, state)) as the work it asked for is done: kind 1 an image decoded (id: the
  // image), 2 a native view ready (a page loaded, a video's first frame showable); state 1 done, -1 failed, once an
  // item; and (a view, 0) each time it waits on the app instead (a player's read asked of it): not the host's work
  // until the app answers. Always from the event loop, never inside a call of the app's (a frame, a read answered).
  // Each frame says at its end how many of its asks the host has not answered and what they are: a run to a declared
  // moment (shot_at) keeps its clock still while any is.
  // its kinds, named as src/ui/hostcall.mbt's outside_* (this host has no picker, gallery, marks or update; a frame
  // grab asked of a video fails at once, told so)
  const OUTSIDE_IMAGE = 1, OUTSIDE_VIEW = 2, OUTSIDE_GRAB = 6;
  let outside = null, awaiting = 0, why = '';
  const told = new Set();
  H.setOutside = (f) => { outside = f; return true; };
  H.frameAwaiting = (n, what, u) => { awaiting = n; why = what; unrest = u; };
  function tell(kind, id, state) {
    if (!outside) return;
    if (state !== 0) {
      const k = kind + ':' + id;
      if (told.has(k)) return;
      told.add(k);
    }
    queueMicrotask(() => outside(kind, id, state));
  }
  function resize() {
    dpr = window.devicePixelRatio || 1;
    cssW = canvas.clientWidth;
    cssH = canvas.clientHeight;
    const w = Math.round(cssW * dpr), h = Math.round(cssH * dpr);
    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
    }
  }

  // ---- WebGL2 renderer ----
  const VS = `#version 300 es
  layout(location=0) in vec4 a_rect;
  layout(location=1) in vec4 a_p;
  layout(location=2) in vec4 a_color;
  layout(location=3) in vec4 a_c2;
  layout(location=4) in vec4 a_clip;
  layout(location=5) in vec4 a_pad;
  layout(location=6) in vec4 a_rc;
  layout(location=7) in vec4 a_rs;
  uniform vec2 u_vp;
  uniform vec4 u_gb;
  out vec2 v_pos;
  flat out vec4 v_rect; flat out vec4 v_p; flat out vec4 v_color; flat out vec4 v_c2; flat out vec4 v_clip; flat out vec4 v_pad;
  flat out vec4 v_rc; flat out vec4 v_rs;
  void main() {
    int vid = gl_VertexID;
    vec2 corner = vec2((vid == 1 || vid == 4 || vid == 5) ? 1.0 : 0.0, (vid == 2 || vid == 3 || vid == 5) ? 1.0 : 0.0);
    int kind = int(a_p.y + 0.5);
    float grow = kind == 2 ? a_p.w * 2.0 + 2.0 : ((kind == 0 || kind == 4 || kind == 5) ? 1.0 : 0.0);
    vec2 pos = a_rect.xy - grow + corner * (a_rect.zw + 2.0 * grow);
    if (kind == 6) pos = mix(u_gb.xy, u_gb.zw, corner);
    gl_Position = vec4(pos.x / u_vp.x * 2.0 - 1.0, 1.0 - pos.y / u_vp.y * 2.0, 0.0, 1.0);
    v_pos = pos; v_rect = a_rect; v_p = a_p; v_color = a_color; v_c2 = a_c2; v_clip = a_clip; v_pad = a_pad; v_rc = a_rc; v_rs = a_rs;
  }`;
  const FS = `#version 300 es
  precision highp float;
  in vec2 v_pos;
  flat in vec4 v_rect; flat in vec4 v_p; flat in vec4 v_color; flat in vec4 v_c2; flat in vec4 v_clip; flat in vec4 v_pad;
  flat in vec4 v_rc; flat in vec4 v_rs;
  uniform float u_scale;
  uniform sampler2D u_atlas;
  uniform sampler2D u_img;
  // glass (src/ui/glass.mbt): the blurred copy under it and where a point is in it (uv = p * u_map.xy + u_map.zw, kept
  // in u_uvc), a liquid group's shapes and corners, how many
  uniform sampler2D u_bd;
  uniform vec4 u_map;
  uniform vec4 u_uvc;
  uniform vec4 u_shape[8];
  uniform vec4 u_rad[2];
  uniform int u_n;
  out vec4 o;
  // corner.sl begin (scripts/corner_sl.py: not edited here)
  #define float2 vec2
  // mbui's corners (src/ui/smooth.mbt: these are its smoothness, sd_corner and sd_box, number for number), the one copy
  // every renderer draws by: Metal's, Direct3D's and both GLs' shaders take it in as it is (corner_sl.h; web/host.js
  // between its "corner.sl" lines), written in what the four have in common (float2: GLSL's vec2, defined so before it).
  // Made into those by scripts/corner_sl.py, which CI runs with --check.
  //
  // How smooth a corner of radius r is where room is half its box's shorter side: 0 a circle's or a capsule's end, 1
  // superellipse(1.5) over r a quarter longer; between, as far as the room goes.
  float mb_smoothness(float r, float room) {
    return r <= 0.0 ? 0.0 : clamp((room - r) / (0.25 * r), 0.0, 1.0);
  }
  // The signed distance of p (from a box's middle) from that box, hs its half sides, its corners r (at most the shorter
  // half) s smooth: |x|^n + |y|^n = R^n about each corner's centre, n from 2 to 2^1.5 and R from r to 1.25 r as s goes
  // from 0 to 1. 0 on the curve; off it, the curve's value over how fast it grows there (along its normal, to first
  // order). At s = 0 a round corner's, as before. Only within band of the curve is it worked out (two powers a pixel):
  // the curve lies between the circle of R and that of R 2^(1/2 - 1/n) (under 1.107 R), and further than band inside
  // the one or outside the other the round distance has its sign and is as far, which is all a cover, an edge band
  // wide or a shadow that blurred says of it.
  float mb_sd_corner(float2 p, float2 hs, float r, float s, float band) {
    float R = min(r * (1.0 + 0.25 * s), min(hs.x, hs.y));
    float2 q = abs(p) - hs + R;
    float2 m = max(q, 0.0);
    float l = length(m);
    if (s <= 0.0 || min(m.x, m.y) <= 0.0 || l <= R - band || l >= 1.107 * R + band) return l + min(max(q.x, q.y), 0.0) - R;
    float hi = max(m.x, m.y);
    float t = min(m.x, m.y) / hi;
    if (s >= 1.0) {
      // wholly smooth (nearly every corner): the two factors below as polynomials in t, no power (smooth.mbt
      // smooth_a, smooth_b: within 2e-5 of them, a hundredth of a pixel over a radius of 200)
      float A = 1.0000098 + t * (-0.00106380035 + t * (0.0390446602 + t * (1.21491043 + t * (-1.49650831 + t * (1.90947795 + t * (-2.77580972 + t * (2.11536546 + t * -0.591224537)))))));
      float B = 1.00001404 + t * (-0.00136262193 + t * (0.039570688 + t * (0.648050719 + t * (-0.725922772 + t * (0.327888394 + t * (-0.914717465 + t * (1.13728689 + t * -0.403984265)))))));
      return hi * A - R * B;
    }
    float n = 2.0 + 0.8284271247461903 * s;
    float tn1 = pow(t, n - 1.0);
    float tn = tn1 * t;
    float u = pow(1.0 + tn, 1.0 / n);
    return (hi * u - R) * (1.0 + tn) / (u * sqrt(1.0 + tn1 * tn1));
  }
  // A box's own corners: r at most its shorter half, as smooth as its size has room for (band: mb_sd_corner's).
  float mb_sd_box(float2 p, float2 hs, float r, float band) {
    float room = min(hs.x, hs.y);
    float rr = min(r, room);
    return mb_sd_corner(p, hs, rr, mb_smoothness(rr, room), band);
  }
  // corner.sl end
  float sd_rr(vec2 p, vec4 r, float rad) {
    vec2 hs = r.zw * 0.5;
    return mb_sd_box(p - r.xy - hs, hs, rad, 1e9);
  }
  // a notch cut into the top edge (scene.mbt 21-23): a circle about the top's middle (pad.y below it, pad.z its
  // radius), met by the edge through fillets (pad.w): the rounded intersection with what is outside the circle
  float notch_cut(float d, vec2 p, vec4 r, vec4 pad) {
    if (pad.z <= 0.0) return d;
    float b = pad.z - length(p - vec2(r.x + r.z * 0.5, r.y + pad.y));
    float f = max(pad.w, 0.0);
    vec2 u = max(vec2(f + d, f + b), 0.0);
    return min(-f, max(d, b)) + length(u);
  }
  float smin_k(float a, float b, float k) {
    if (k <= 0.0) return min(a, b);
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
  }
  float sd_group(vec2 p, float k) {
    float d = 1e9;
    for (int i = 0; i < 8; i++) {
      if (i >= u_n) break;
      d = smin_k(d, sd_rr(p, u_shape[i], u_rad[i / 4][i % 4]), k);
    }
    return d;
  }
  vec3 backdrop(vec2 p) {
    return texture(u_bd, clamp(p * u_map.xy + u_map.zw, u_uvc.xy, u_uvc.zw)).rgb;
  }
  float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
  // how much of the pixel at p its rounded clip keeps (r: the corners' radii, top left, then clockwise; s: how smooth
  // each is), its edge covered as a box's own (0.5 - d * scale), so what it cuts meets the ground of the box that cuts it
  float clip_cover(vec2 p, vec4 c, vec4 r, vec4 s, float scale) {
    vec2 hs = (c.zw - c.xy) * 0.5;
    vec2 m = c.xy + hs;
    float rr = p.x < m.x ? (p.y < m.y ? r.x : r.w) : (p.y < m.y ? r.y : r.z);
    float ss = p.x < m.x ? (p.y < m.y ? s.x : s.w) : (p.y < m.y ? s.y : s.z);
    float d = mb_sd_corner(p - m, hs, min(rr, min(hs.x, hs.y)), ss, 1.0 + 2.0 / scale);
    return clamp(0.5 - d * scale, 0.0, 1.0);
  }
  // what it shows at p, as if uncut
  void shade(vec2 p) {
    int kind = int(v_p.y + 0.5);
    if (kind == 9) { vec2 hh = v_rect.zw * 0.5; float rr = min(v_p.x, min(hh.x, hh.y)); vec2 q = abs(p - v_rect.xy - hh) - hh + rr; if (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rr > 0.0) discard; o = vec4(0.0); return; }
    vec4 col = v_color;
    if (kind == 10) {
      // a piece of a line (scene.mbt): from c2.xy to c2.zw (shares of its rect), p.x half its width, its ends round
      vec2 a = v_rect.xy + v_c2.xy * v_rect.zw, ab = v_rect.xy + v_c2.zw * v_rect.zw - a;
      float h = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-8), 0.0, 1.0);
      float d = length(p - a - ab * h) - v_p.x;
      o = vec4(col.rgb, 1.0) * col.a * clamp(0.5 - d * u_scale, 0.0, 1.0);
      return;
    }
    if (kind == 1 || kind == 3 || kind == 7) {
      vec2 uv = (v_c2.xy + (p - v_rect.xy) / v_rect.zw * v_c2.zw) / ${ATLAS}.0;
      vec4 t = texture(u_atlas, uv);
      if (kind == 7) {
        // inked by how light what is under its glass is, looked at round the glass's middle
        vec2 c = v_pad.yz; float r = v_pad.w * 0.5;
        float l = (luma(backdrop(c)) + luma(backdrop(c + vec2(r, 0.0))) + luma(backdrop(c - vec2(r, 0.0))) +
                   luma(backdrop(c + vec2(0.0, r))) + luma(backdrop(c - vec2(0.0, r)))) / 5.0;
        vec3 ink = mix(vec3(1.0), vec3(0.11, 0.11, 0.12), smoothstep(0.42, 0.6, l));
        o = vec4(ink, 1.0) * (t.a * col.a);
        return;
      }
      o = kind == 1 ? vec4(col.rgb, 1.0) * (t.a * col.a) : t * col.a;
      return;
    }
    if (kind == 6) {
      // liquid: one shape of the group's, merged; what is under it bent along the bezel, the colours split a little
      float k = v_pad.w;
      float d = sd_group(p, k);
      float a = clamp(0.5 - d * u_scale, 0.0, 1.0);
      if (a <= 0.0) discard;
      float e = 0.5;
      vec2 grad = vec2(sd_group(p + vec2(e, 0.0), k) - sd_group(p - vec2(e, 0.0), k),
                       sd_group(p + vec2(0.0, e), k) - sd_group(p - vec2(0.0, e), k));
      vec2 n = grad / max(length(grad), 1e-4);
      float bezel = max(v_c2.y, 1.0);
      float edge = 1.0 - clamp(-d / bezel, 0.0, 1.0);
      float disp = v_pad.y * (1.0 - sqrt(max(1.0 - edge * edge, 0.0)));
      vec2 off = -n * disp;
      float ch = v_pad.z;
      vec3 c = vec3(backdrop(p + off * (1.0 + ch)).r, backdrop(p + off).g, backdrop(p + off * (1.0 - ch)).b);
      c = max(mix(vec3(luma(c)), c, v_p.z), 0.0);
      c = c * (1.0 - col.a) + col.rgb * col.a;
      // the rim lit from the top left, and less across from it
      float ndl = dot(n, vec2(-0.6, -0.8));
      float band = clamp(1.0 + d / 2.5, 0.0, 1.0);
      float spec = v_c2.x * (band * (0.9 * pow(max(ndl, 0.0), 1.5) + 0.45 * pow(max(-ndl, 0.0), 1.5)) +
                             0.3 * edge * edge * max(ndl, 0.0));
      // the edge shaded, more on the side away from the light, so the shape reads over a light ground too
      c *= 1.0 - v_c2.x * band * (0.1 + 0.25 * max(-ndl, 0.0));
      c = c + (1.0 - c) * clamp(spec, 0.0, 1.0);
      o = vec4(c, 1.0) * (a * v_c2.w);
      return;
    }
    vec2 hs = v_rect.zw * 0.5;
    vec2 c = v_rect.xy + hs;
    // worked out as near the curve as its cover, its edge or its blur reaches
    float band = 1.0 + 2.0 / u_scale + (kind == 2 ? max(v_p.w, 0.5) : max(v_p.z, 0.0));
    float d = mb_sd_box(p - c, hs, v_p.x, band);
    if (kind == 0 || kind == 5) d = notch_cut(d, p, v_rect, v_pad);
    if (kind == 4) {
      vec2 uv = v_c2.xy + clamp((p - v_rect.xy) / v_rect.zw, 0.0, 1.0) * v_c2.zw;
      o = texture(u_img, uv) * (col.a * clamp(0.5 - d * u_scale, 0.0, 1.0));
      return;
    }
    if (kind == 2) {
      float b = max(v_p.w, 0.5);
      float a = 1.0 - smoothstep(-b, b, d);
      // glass's: only outside its box (c2.y above it)
      if (v_c2.x > 0.5) {
        float db = mb_sd_box(p - c + vec2(0.0, v_c2.y), hs, v_p.x, band);
        a *= clamp(0.5 + db * u_scale, 0.0, 1.0);
      }
      o = vec4(col.rgb, 1.0) * col.a * a;
      return;
    }
    float a = clamp(0.5 - d * u_scale, 0.0, 1.0);
    if (kind == 5) {
      // frosted: the blurred copy, saturated, the tint over it; the rim (a hairline inside the edge, the top left lit,
      // the foot and right less), 0.5 wide
      vec3 g3 = backdrop(p);
      g3 = max(mix(vec3(luma(g3)), g3, v_p.z), 0.0);
      g3 = g3 * (1.0 - col.a) + col.rgb * col.a;
      if (v_c2.x + v_c2.y + v_c2.z > 0.0) {
        float edge = clamp(0.5 + (d + 0.5) * u_scale, 0.0, 1.0);
        float lit = clamp(0.5 + notch_cut(sd_rr(p - 0.5, v_rect, v_p.x), p - 0.5, v_rect, v_pad) * u_scale, 0.0, 1.0);
        float back = clamp(0.5 + notch_cut(sd_rr(p + 0.5, v_rect, v_p.x), p + 0.5, v_rect, v_pad) * u_scale, 0.0, 1.0);
        g3 = mix(g3, vec3(1.0), v_c2.x * edge);
        g3 = mix(g3, vec3(1.0), v_c2.y * lit);
        g3 = mix(g3, vec3(1.0), v_c2.z * back);
      }
      o = vec4(g3, 1.0) * (a * v_c2.w);
      return;
    }
    vec4 fill = vec4(col.rgb, 1.0) * col.a;
    if (v_p.z > 0.0) {
      float inner = clamp(0.5 - (d + v_p.z) * u_scale, 0.0, 1.0);
      vec4 bc = vec4(v_c2.rgb, 1.0) * v_c2.a;
      fill = mix(bc, fill, inner);
    }
    o = fill * a;
  }
  // cut to its clip: a rect's, hard; a rounded one's, covered as edges are
  void main() {
    vec2 p = v_pos;
    float cover = 1.0;
    if (max(max(v_rc.x, v_rc.y), max(v_rc.z, v_rc.w)) > 0.0) {
      cover = clip_cover(p, v_clip, v_rc, v_rs, u_scale);
      if (cover <= 0.0) discard;
    } else if (p.x < v_clip.x || p.y < v_clip.y || p.x > v_clip.z || p.y > v_clip.w) discard;
    shade(p);
    o *= cover;
  }`;
  // glass's passes over its copy of what is under it
  const PVS = `#version 300 es
  void main() {
    gl_Position = vec4(gl_VertexID == 1 ? 3.0 : -1.0, gl_VertexID == 2 ? 3.0 : -1.0, 0.0, 1.0);
  }`;
  const PFS = `#version 300 es
  precision highp float;
  // The backdrop's passes: u_a.xy the source's texel, u_a.z 1 halving (dual Kawase's down), 2 a Gaussian along u_b.zw
  // of deviation u_a.w (texels); u_b.xy the last texel's centre of what the source holds
  uniform sampler2D u_src;
  uniform vec4 u_a;
  uniform vec4 u_b;
  out vec4 o;
  void main() {
    vec2 ts = u_a.xy;
    vec2 lo = ts * 0.5, hi = u_b.xy;
    if (u_a.z < 1.5) {
      vec2 uv = gl_FragCoord.xy * 2.0 * ts;
      vec4 s = texture(u_src, clamp(uv, lo, hi)) * 4.0;
      s += texture(u_src, clamp(uv - ts, lo, hi));
      s += texture(u_src, clamp(uv + ts, lo, hi));
      s += texture(u_src, clamp(uv + vec2(ts.x, -ts.y), lo, hi));
      s += texture(u_src, clamp(uv + vec2(-ts.x, ts.y), lo, hi));
      o = s / 8.0;
      return;
    }
    vec2 uv = gl_FragCoord.xy * ts;
    vec2 dir = u_b.zw * ts;
    float sg = u_a.w;
    float k = -0.5 / (sg * sg);
    vec4 s = texture(u_src, clamp(uv, lo, hi));
    float wsum = 1.0;
    int n = int(ceil(sg * 3.0));
    for (int i = 1; i <= 64; i += 2) {
      if (i > n) break;
      float w1 = exp(float(i * i) * k), w2 = exp(float((i + 1) * (i + 1)) * k);
      float w = w1 + w2;
      float off = (float(i) * w1 + float(i + 1) * w2) / w;
      s += (texture(u_src, clamp(uv + dir * off, lo, hi)) + texture(u_src, clamp(uv - dir * off, lo, hi))) * w;
      wsum += 2.0 * w;
    }
    o = s / wsum;
  }`;

  function compile(type, src) {
    const s = gl.createShader(type);
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
    return s;
  }

  function setupGL() {
    // with alpha: native views (below) show through the holes the app paints (kind 9); every frame is opaque elsewhere
    gl = canvas.getContext('webgl2', { premultipliedAlpha: true, antialias: false, alpha: true });
    prog = gl.createProgram();
    gl.attachShader(prog, compile(gl.VERTEX_SHADER, VS));
    gl.attachShader(prog, compile(gl.FRAGMENT_SHADER, FS));
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(prog));
    post = gl.createProgram();
    gl.attachShader(post, compile(gl.VERTEX_SHADER, PVS));
    gl.attachShader(post, compile(gl.FRAGMENT_SHADER, PFS));
    gl.linkProgram(post);
    if (!gl.getProgramParameter(post, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(post));
    for (const n of ['u_vp', 'u_scale', 'u_atlas', 'u_img', 'u_bd', 'u_map', 'u_uvc', 'u_gb', 'u_shape', 'u_rad', 'u_n']) U[n] = gl.getUniformLocation(prog, n);
    for (const n of ['u_src', 'u_a', 'u_b']) PU[n] = gl.getUniformLocation(post, n);
    vao = gl.createVertexArray();
    gl.bindVertexArray(vao);
    instBuf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, instBuf);
    for (let i = 0; i < 8; i++) {
      const loc = i;
      // instance layout: rect, p, color, c2, clip, pad, the clip's corners' radii, how smooth (vec4 each)
      gl.enableVertexAttribArray(loc);
      gl.vertexAttribPointer(loc, 4, gl.FLOAT, false, INST * 4, i * 16);
      gl.vertexAttribDivisor(loc, 1);
    }
    atlasTex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, atlasTex);
    gl.texStorage2D(gl.TEXTURE_2D, 1, gl.RGBA8, ATLAS, ATLAS);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
  }

  // ---- glass (src/ui/glass.mbt) ----
  // When the instances reach a run of glass (slot 20 negative: the capture it shares), what is drawn so far under it
  // (its rects with room for the blur round them) is copied out of the canvas, halved down to where the blur is a
  // few texels wide (dual Kawase's downsample, at most 1/8), blurred there by a Gaussian of what deviation is left,
  // and drawn through. Level j is 1/2^j of the canvas, tmp a Gaussian's first half.
  let lv = null, lvW = 0, lvH = 0, bdTex = null;
  const gmap = new Float32Array(4), guvc = new Float32Array(4), ggb = new Float32Array(4);
  const gshape = new Float32Array(32), grad = new Float32Array(8);
  let gn = 0;
  function levelTex(w, h) {
    const t = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texStorage2D(gl.TEXTURE_2D, 1, gl.RGBA8, Math.max(1, w), Math.max(1, h));
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    const fb = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t, 0);
    return { t, fb, w: Math.max(1, w), h: Math.max(1, h) };
  }
  function ensureLevels(w, h) {
    if (lv && lvW >= w && lvH >= h) return;
    if (lv) for (const l of lv) { gl.deleteTexture(l.t); gl.deleteFramebuffer(l.fb); }
    lvW = Math.max(w, lvW); lvH = Math.max(h, lvH);
    lv = [];
    for (let j = 0; j < 4; j++) lv.push(levelTex((lvW + (1 << j) - 1) >> j, (lvH + (1 << j) - 1) >> j));
    lv.push(levelTex(lvW, lvH));
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  }
  function postPass(src, sw, sh, dst, w, h, mode, sg, dx, dy) {
    gl.bindFramebuffer(gl.FRAMEBUFFER, dst.fb);
    gl.viewport(0, 0, w, h);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, src.t);
    gl.uniform1i(PU.u_src, 0);
    gl.uniform4f(PU.u_a, 1 / src.w, 1 / src.h, mode, sg);
    gl.uniform4f(PU.u_b, (sw - 0.5) / src.w, (sh - 0.5) / src.h, dx, dy);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }
  // what the run [start, end) of glass sees; false when none of it shows
  // what the run [start, end) of glass sees, frosted glass of the same capture further on (glass.mbt
  // shares_capture) too; false when none of it shows
  function capture(start, end, count) {
    const a = start * INST;
    const blur = f32[a + 7], kind = Math.round(f32[a + 5]);
    const margin = 3 * blur + (kind === 6 ? f32[a + 21] * (1 + f32[a + 22]) + f32[a + 23] : 0) + 2;
    let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
    gn = 0;
    for (let i = start; i < end; i++) {
      const b = i * INST;
      let bx0 = Math.max(f32[b], f32[b + 16]), by0 = Math.max(f32[b + 1], f32[b + 17]);
      let bx1 = Math.min(f32[b] + f32[b + 2], f32[b + 18]), by1 = Math.min(f32[b + 1] + f32[b + 3], f32[b + 19]);
      if (kind === 6) {
        const m = f32[a + 23];
        bx0 = f32[b] - m; by0 = f32[b + 1] - m; bx1 = f32[b] + f32[b + 2] + m; by1 = f32[b + 1] + f32[b + 3] + m;
        if (gn < 8) {
          for (let k = 0; k < 4; k++) gshape[gn * 4 + k] = f32[b + k];
          grad[gn] = f32[b + 4];
          gn++;
        }
      }
      x0 = Math.min(x0, bx0); y0 = Math.min(y0, by0); x1 = Math.max(x1, bx1); y1 = Math.max(y1, by1);
    }
    for (let i = end; kind === 5 && i < count; i++) {
      const b = i * INST;
      if (f32[b + 20] !== f32[a + 20]) continue;
      x0 = Math.min(x0, Math.max(f32[b], f32[b + 16])); y0 = Math.min(y0, Math.max(f32[b + 1], f32[b + 17]));
      x1 = Math.max(x1, Math.min(f32[b] + f32[b + 2], f32[b + 18])); y1 = Math.max(y1, Math.min(f32[b + 1] + f32[b + 3], f32[b + 19]));
    }
    ggb[0] = x0 - 2; ggb[1] = y0 - 2; ggb[2] = x1 + 2; ggb[3] = y1 + 2;
    const W = canvas.width, Hh = canvas.height, sc = dpr;
    // in the canvas's pixels, from its foot (GL's way up)
    const px0 = Math.max(0, Math.floor((x0 - margin) * sc)), px1 = Math.min(W, Math.ceil((x1 + margin) * sc));
    const pb0 = Math.max(0, Hh - Math.ceil((y1 + margin) * sc)), pb1 = Math.min(Hh, Hh - Math.floor((y0 - margin) * sc));
    if (px1 <= px0 || pb1 <= pb0 || x1 <= x0 || y1 <= y0) return false;
    const w = px1 - px0, h = pb1 - pb0;
    ensureLevels(W, Hh);
    gl.disable(gl.BLEND);
    gl.bindFramebuffer(gl.READ_FRAMEBUFFER, null);
    gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, lv[0].fb);
    gl.blitFramebuffer(px0, pb0, px1, pb1, 0, 0, w, h, gl.COLOR_BUFFER_BIT, gl.NEAREST);
    gl.useProgram(post);
    const sp = blur * sc;
    let k = 0;
    while (k < 3 && sp / (1 << (k + 1)) >= 2) k++;
    const lw = [w], lh = [h];
    for (let j = 1; j <= k; j++) {
      lw[j] = (lw[j - 1] + 1) >> 1;
      lh[j] = (lh[j - 1] + 1) >> 1;
      postPass(lv[j - 1], lw[j - 1], lh[j - 1], lv[j], lw[j], lh[j], 1, 0, 0, 0);
    }
    // what is left of the deviation once the halvings' and the last look's (bilinear) spread are taken out
    const sk = sp / (1 << k);
    const pre = k > 0 ? 0.75 * (1 - Math.pow(0.25, k)) / 3 + 1 / 6 : 0;
    const sg = Math.sqrt(Math.max(sk * sk - pre, 0));
    if (sg > 0.3) {
      postPass(lv[k], lw[k], lh[k], lv[4], lw[k], lh[k], 2, sg, 1, 0);
      postPass(lv[4], lw[k], lh[k], lv[k], lw[k], lh[k], 2, sg, 0, 1);
    }
    const L = lv[k], d = 1 << k;
    bdTex = L.t;
    gmap[0] = sc / d / L.w; gmap[1] = -sc / d / L.h;
    gmap[2] = -px0 / d / L.w; gmap[3] = (Hh - pb0) / d / L.h;
    guvc[0] = 0.5 / L.w; guvc[1] = 0.5 / L.h; guvc[2] = (lw[k] - 0.5) / L.w; guvc[3] = (lh[k] - 0.5) / L.h;
    return true;
  }
  // the main program's state, after the passes
  function mainState() {
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.enable(gl.BLEND);
    gl.useProgram(prog);
    gl.bindVertexArray(vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, instBuf);
    gl.uniform2f(U.u_vp, cssW, cssH);
    gl.uniform1f(U.u_scale, dpr);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, atlasTex);
    gl.uniform1i(U.u_atlas, 0);
    gl.uniform1i(U.u_img, 1);
    gl.activeTexture(gl.TEXTURE2);
    gl.bindTexture(gl.TEXTURE_2D, bdTex || atlasTex);
    gl.uniform1i(U.u_bd, 2);
    gl.uniform4fv(U.u_map, gmap);
    gl.uniform4fv(U.u_uvc, guvc);
    gl.uniform4fv(U.u_gb, ggb);
    gl.uniform4fv(U.u_shape, gshape);
    gl.uniform4fv(U.u_rad, grad);
    gl.uniform1i(U.u_n, gn);
  }

  H.present = (buf, n, r, g, b) => {
    const len = n * INST;
    if (f32.length < len) f32 = new Float32Array(len * 2);
    for (let i = 0; i < len; i++) f32[i] = buf[i];
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.clearColor(r, g, b, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);
    if (n === 0) return;
    bdTex = null;
    gmap.fill(0); guvc.fill(0); ggb.fill(0); gn = 0;
    gl.useProgram(prog);
    gl.bindVertexArray(vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, instBuf);
    gl.bufferData(gl.ARRAY_BUFFER, f32.subarray(0, len), gl.STREAM_DRAW);
    mainState();
    // one draw per run of instances showing the same image (slot 20), or sharing one capture of glass (negative);
    // WebGL has no base instance, so the attributes start at the run instead
    // (and per run of holes, kind 9: written transparent with no blending, where a native view shows)
    const hole = (i) => Math.round(f32[i * INST + 5]) === 9;
    let start = 0, bound = 0, shows = false;
    while (start < n) {
      const tid = f32[start * INST + 20] | 0;
      const h = hole(start);
      let end = start + 1;
      while (end < n && (f32[end * INST + 20] | 0) === tid && hole(end) === h) end++;
      if (tid < 0) {
        if (tid !== bound) {
          shows = capture(start, end, n);
          bound = tid;
          mainState();
        }
        if (shows) {
          for (let i = 0; i < 8; i++) gl.vertexAttribPointer(i, 4, gl.FLOAT, false, INST * 4, start * INST * 4 + i * 16);
          // liquid: the group as one shape, drawn once
          gl.drawArraysInstanced(gl.TRIANGLES, 0, 6, Math.round(f32[start * INST + 5]) === 6 ? 1 : end - start);
        }
        start = end;
        continue;
      }
      // a stream's picture (STREAM_TEX + its id): nothing until a frame of its own shows
      const im = tid > STREAM_TEX ? streams.get(tid - STREAM_TEX) : tid ? images.get(tid) : null;
      if (tid > STREAM_TEX && !(im && im.tex)) {
        start = end;
        continue;
      }
      gl.activeTexture(gl.TEXTURE1);
      gl.bindTexture(gl.TEXTURE_2D, im && im.tex ? im.tex : atlasTex);
      for (let i = 0; i < 8; i++) gl.vertexAttribPointer(i, 4, gl.FLOAT, false, INST * 4, start * INST * 4 + i * 16);
      if (h) gl.disable(gl.BLEND);
      gl.drawArraysInstanced(gl.TRIANGLES, 0, 6, end - start);
      if (h) gl.enable(gl.BLEND);
      start = end;
    }
  };

  // ---- native views over the canvas (src/ui/native.mbt) ----
  // DOM elements in a layer under the canvas, shown through its holes: a <video> whose bytes come through the app
  // (read in parts, then played from a Blob), a sandboxed <iframe> (scripts only) for a page of HTML.
  const views = new Map();
  let nextView = 0, viewLayer = null;
  function layer() {
    if (!viewLayer) {
      viewLayer = document.createElement('div');
      // over the page's own ground, under the canvas (both positioned: the body's ground would cover a layer below 0)
      viewLayer.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:0';
      document.body.insertBefore(viewLayer, document.body.firstChild);
      canvas.style.zIndex = '1';
    }
    return viewLayer;
  }
  const info = (v) => v.info || (v.info = [-1, 0, 0, 0, 0, 0, 0, 0]);
  // first in a page's frame: mbuiHost.post to this window, and the scripts this window sends run
  const PAGE_BRIDGE = '<script>window.mbuiHost={post:function(t){parent.postMessage({mbuiSaid:String(t)},"*")}};' +
    'addEventListener("message",function(e){if(e.source===parent&&e.data&&typeof e.data.mbuiScript==="string")(0,eval)(e.data.mbuiScript)});</script>';
  const runScripts = (v) => {
    if (!v.there || !v.el.contentWindow) return;
    for (const js of v.scripts) v.el.contentWindow.postMessage({ mbuiScript: js }, '*');
    v.scripts = [];
  };
  // what a page's frame says, from that frame only (no other window may speak for it)
  window.addEventListener('message', (e) => {
    if (!e.data || typeof e.data.mbuiSaid !== 'string') return;
    for (const v of views.values()) {
      if (v.kind !== 2 || e.source !== v.el.contentWindow) continue;
      v.said.push(JSON.stringify({ said: e.data.mbuiSaid }));
      v.there = true;
      runScripts(v);
      H.requestFrame();
    }
  });
  H.viewSiteNext = (id) => {
    const v = views.get(id);
    return v && v.said && v.said.length ? v.said.shift() : '';
  };
  H.viewTell = (id, what, text) => {
    const v = views.get(id);
    if (!v || v.kind !== 2) return;
    if (what === 1) { v.scripts.push(text); runScripts(v); }
  };
  // a view ready (or failed) told to the app, once; not once it is closed (the app let it go)
  const ready = (id, v, state) => {
    if (v.ready || !views.has(id)) return;
    v.ready = true;
    tell(OUTSIDE_VIEW, id, state);
  };
  H.viewOpen = (kind, arg) => {
    if (kind !== 1 && kind !== 2) return 0;
    const id = ++nextView;
    const clip = document.createElement('div');
    clip.style.cssText = 'position:absolute;overflow:hidden;display:none;background:' + (kind === 1 ? '#000' : '#fff');
    const v = { kind, clip, state: 0, reads: [], waiting: new Map(), nextRead: 0, parts: [], have: 0, total: -1 };
    info(v);
    if (kind === 1) {
      const el = document.createElement('video');
      el.playsInline = true;
      el.style.cssText = 'position:absolute;object-fit:fill';
      el.addEventListener('loadedmetadata', () => {
        v.state = 1;
        v.info[0] = el.duration * 1000;
        v.info[3] = el.videoWidth;
        v.info[4] = el.videoHeight;
        H.requestFrame();
      });
      // its first frame can be shown: ready for the app
      el.addEventListener('loadeddata', () => { v.info[6] = 1; ready(id, v, 1); H.requestFrame(); });
      el.addEventListener('error', () => { v.state = -1; ready(id, v, -1); H.requestFrame(); });
      // the app asks for frames only while it plays and is not waiting for what it needs (info 7): a frame as that
      // changes
      for (const e of ['play', 'playing', 'waiting', 'pause', 'stalled', 'canplay', 'ended']) el.addEventListener(e, H.requestFrame);
      v.el = el;
      v.type = arg;
      // the whole file read through the app, a part at a time, then played
      // (the player waits on the app's bytes now: not the host's work until they come)
      v.ask = (offset) => {
        const r = { id: ++v.nextRead, offset, length: 4 << 20 };
        v.reads.push(r);
        v.waiting.set(r.id, r);
        if (!v.ready) tell(OUTSIDE_VIEW, id, 0);
        H.requestFrame();
      };
      v.ask(0);
    } else {
      const el = document.createElement('iframe');
      el.setAttribute('sandbox', 'allow-scripts');
      el.style.cssText = 'position:absolute;border:0;background:#fff';
      // loaded: what a screenshot shows of it is the page itself (in the page's own picture)
      el.addEventListener('load', () => { v.state = 1; v.info[6] = 1; ready(id, v, 1); v.there = true; runScripts(v); H.requestFrame(); });
      el.addEventListener('error', () => { v.state = -1; ready(id, v, -1); H.requestFrame(); });
      // its way to the app (mbuiHost.post, as the other hosts' pages have it) and the app's scripts run in it: messages
      // between this window and the frame's own, each side taking only the other's
      v.said = [];
      v.scripts = [];
      v.there = false;
      el.srcdoc = PAGE_BRIDGE + arg;
      v.info[5] = new TextEncoder().encode(arg).length;
      v.el = el;
    }
    clip.appendChild(v.el);
    layer().appendChild(clip);
    views.set(id, v);
    return id;
  };
  H.viewPlace = (id, x, y, w, h, cx0, cy0, cx1, cy1, shown, radius = 0) => {
    const v = views.get(id);
    if (!v) return;
    Object.assign(v.clip.style, { left: cx0 + 'px', top: cy0 + 'px', width: Math.max(0, cx1 - cx0) + 'px',
      height: Math.max(0, cy1 - cy0) + 'px', display: shown ? 'block' : 'none' });
    // (its corners round, as the hole the app paints for it: the element cut to them, what it shows with it)
    Object.assign(v.el.style, { left: x - cx0 + 'px', top: y - cy0 + 'px', width: w + 'px', height: h + 'px',
      borderRadius: radius > 0 ? radius + 'px' : '', overflow: radius > 0 ? 'hidden' : '' });
    // where it is now, in device pixels, as the page laid it out (scripts/host_contract.sh web views: against VIEWTOLD)
    if (shown && H.log) {
      const d = window.devicePixelRatio || 1, r = v.el.getBoundingClientRect(), k = v.clip.getBoundingClientRect();
      const cv = (H.canvas || document.querySelector('canvas'));
      const o = cv ? cv.getBoundingClientRect() : { left: 0, top: 0 };
      const f = (n) => n.toFixed(4);
      H.log(`VIEWAT ${id} ${f((r.left - o.left) * d)} ${f((r.top - o.top) * d)} ${f(r.width * d)} ${f(r.height * d)} ` +
        `${f((k.left - o.left) * d)} ${f((k.top - o.top) * d)} ${f((k.right - o.left) * d)} ${f((k.bottom - o.top) * d)} ` +
        `${f((parseFloat(v.el.style.borderRadius) || 0) * d)}`);
    }
  };
  H.viewClose = (id) => {
    const v = views.get(id);
    if (!v) return;
    views.delete(id);
    if (v.kind === 1) { v.el.pause(); if (v.url) URL.revokeObjectURL(v.url); }
    v.clip.remove();
  };
  H.viewControl = (id, op, value) => {
    const v = views.get(id);
    if (!v || v.kind !== 1) return;
    if (op === 1) v.el.play().catch(() => {});
    else if (op === 2) v.el.pause();
    else if (op === 3) v.el.currentTime = value / 1000;
    else if (op === 4) v.el.playbackRate = value;
    // a frame grabbed (op 21): this host grabs none; failed, said so (viewText's 2: "-1", once)
    else if (op === 21) {
      v.grab = '-1';
      tell(OUTSIDE_GRAB, id, -1);
    }
  };
  H.viewText = (id, what) => {
    const v = views.get(id);
    if (!v || what !== 2 || v.grab === undefined) return '';
    const g = v.grab;
    v.grab = undefined;
    return g;
  };
  H.viewInfo = (id, out) => {
    const v = views.get(id);
    if (!v) return -1;
    if (v.kind === 1) {
      v.info[1] = v.el.currentTime * 1000;
      v.info[2] = v.el.paused || v.el.ended ? 0 : 1;
      // waiting for what it needs to go on playing
      v.info[7] = v.info[2] && v.el.readyState < 3 ? 1 : 0;
      // how far on it has what it needs: the end of the buffered range the playhead is in; whether it played to its end
      const b = v.el.buffered, t = v.el.currentTime;
      v.info[8] = 0;
      for (let i = 0; i < b.length; i++) if (b.start(i) <= t + 0.001) v.info[8] = Math.max(v.info[8], b.end(i) * 1000);
      v.info[9] = v.el.ended ? 1 : 0;
    }
    for (let i = 0; i < 10; i++) out[i] = v.info[i] || 0;
    return v.state;
  };
  H.viewReadNext = (id, out) => {
    const v = views.get(id);
    const r = v && v.reads.shift();
    if (!r) return 0;
    out[0] = r.offset;
    out[1] = r.length;
    return r.id;
  };
  H.viewReadAnswer = (id, req, data, total) => {
    const v = views.get(id);
    if (!v || !v.waiting.delete(req)) return;
    if (total === -2) { v.state = -1; ready(id, v, -1); H.requestFrame(); return; }
    const part = new Uint8Array(data);
    v.parts.push(part);
    v.have += part.length;
    v.info[5] = v.have;
    if (total >= 0) v.total = total;
    if (part.length > 0 && (v.total < 0 || v.have < v.total)) return v.ask(v.have);
    v.url = URL.createObjectURL(new Blob(v.parts, { type: v.type }));
    v.el.src = v.url;
  };

  // ---- images ----
  // Decoded by the browser off the main thread (createImageBitmap, which
  // also applies the EXIF orientation), scaled to the size asked for, kept
  // as premultiplied textures.
  const images = new Map();
  let nextImage = 0;
  async function decodeImage(id, blob, maxPx) {
    const im = images.get(id);
    try {
      let bmp = await createImageBitmap(blob);
      const ow = bmp.width, oh = bmp.height;
      const k = Math.min(1, maxPx / Math.max(ow, oh));
      if (k < 1) {
        const small = await createImageBitmap(bmp, {
          resizeWidth: Math.max(1, Math.round(ow * k)),
          resizeHeight: Math.max(1, Math.round(oh * k)),
          resizeQuality: 'high',
        });
        bmp.close();
        bmp = small;
      }
      if (!images.has(id)) return bmp.close();
      const tex = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, tex);
      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, bmp);
      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      Object.assign(im, { state: 1, tex, w: bmp.width, h: bmp.height, ow, oh });
      bmp.close();
    } catch (e) {
      if (!images.has(id)) return;
      im.state = -1;
    }
    tell(OUTSIDE_IMAGE, id, im.state);
    H.requestFrame();
  }
  H.imageLoad = (src, maxPx) => {
    const id = ++nextImage;
    images.set(id, { state: 0 });
    fetch(src).then((r) => (r.ok ? r.blob() : Promise.reject(r.status)))
      .then((b) => decodeImage(id, b, maxPx))
      .catch(() => {
        const im = images.get(id);
        if (!im || im.state !== 0) return;
        im.state = -1;
        tell(OUTSIDE_IMAGE, id, -1);
        H.requestFrame();
      });
    return id;
  };
  H.imageLoadBytes = (bytes, maxPx) => {
    const id = ++nextImage;
    images.set(id, { state: 0 });
    decodeImage(id, new Blob([bytes]), maxPx);
    return id;
  };
  H.imageInfo = (id, out) => {
    const im = images.get(id);
    if (!im) return -1;
    if (im.state === 1) {
      out[0] = im.w; out[1] = im.h; out[2] = im.ow; out[3] = im.oh;
    }
    return im.state;
  };
  H.imageFree = (id) => {
    const im = images.get(id);
    if (im && im.tex) gl.deleteTexture(im.tex);
    images.delete(id);
  };

  // ---- streams (src/host/stream.mbt) ----
  // A picture decoded frame by frame: H.264 by WebCodecs' VideoDecoder where the browser has one (AVCC as it is, the
  // avcC its description), JPEG by createImageBitmap. Each frame decoded is kept until the app shows it ("f TS W H",
  // then streamShow: uploaded into the stream's texture), or a later one; frames let go ("d TS": no decoder or not past
  // a key frame, the older of two it holds, those inside as it starts anew, a JPEG that does not decode) and the
  // decoder broken ("b": an error) told the same way, each asking for a frame.
  const STREAM_TEX = 4194304;
  const streams = new Map();
  let nextStream = 0;
  // (a VideoDecoder that takes no H.264, as Chromium's own build has: asked once as the page loads, the app's first
  // frame held until it is answered, so that h264_here is the same from the app's start). Asked of what a station
  // sends: constrained baseline (its helper's VideoToolbox, AutoLevel: ScreenView.swift) at a 1920 × 1080 view's
  // level, 4.2 (a viewer's maxWidth, Android's ScreenSession).
  let hasVideoDecoder = false;
  const h264Asked = typeof VideoDecoder === 'undefined'
    ? Promise.resolve()
    : VideoDecoder.isConfigSupported({ codec: 'avc1.42E02A', codedWidth: 1920, codedHeight: 1080, optimizeForLatency: true })
      .then((r) => { hasVideoDecoder = !!r.supported; }, () => {});
  H.h264Here = () => (hasVideoDecoder ? 1 : 0);
  const num = (v) => String(v);
  function say(s, e) {
    if (s.closed) return;
    s.events.push(e);
    H.requestFrame();
  }
  // the decoder for the config there is (none without one): whether there is one now
  function startDecoder(s) {
    stopDecoder(s);
    if (!s.config || s.closed || !hasVideoDecoder) return false;
    const gen = ++s.gen;
    try {
      const d = new VideoDecoder({
        output: (frame) => {
          if (gen !== s.gen || s.closed) return frame.close();
          const ts = frame.timestamp;
          while (s.inside.length && s.inside[0] <= ts) s.inside.shift();
          s.decoded.push({ ts, frame, w: frame.displayWidth, h: frame.displayHeight });
          say(s, `f ${num(ts)} ${frame.displayWidth} ${frame.displayHeight}`);
        },
        error: (e) => {
          if (gen !== s.gen) return;
          console.warn('stream ' + s.id + ': the H.264 decoder failed', e);
          // anew, from the next key frame
          if (startDecoder(s)) say(s, 'b');
        },
      });
      d.configure(s.config);
      s.decoder = d;
      s.needKey = true;
      return true;
    } catch (e) {
      console.warn('stream ' + s.id + ': no H.264 decoder', e);
      return false;
    }
  }
  function stopDecoder(s) {
    if (s.decoder) {
      try { s.decoder.close(); } catch (e) {}
      s.decoder = null;
    }
    s.gen++;
    if (s.inside.length) say(s, 'd ' + num(Math.max(...s.inside)));
    s.inside = [];
    s.needKey = true;
  }
  H.streamOpen = () => {
    const id = ++nextStream;
    streams.set(id, { id, events: [], decoded: [], inside: [], gen: 0, needKey: true, decoder: null, config: null,
      tex: null, closed: false, jpegs: Promise.resolve() });
    return id;
  };
  H.streamH264 = (id, avcc, w, h) => {
    const s = streams.get(id);
    if (!s) return;
    const a = new Uint8Array(avcc);
    const hex = (b) => b.toString(16).padStart(2, '0');
    s.config = a.length >= 4 && a[0] === 1
      ? { codec: 'avc1.' + hex(a[1]) + hex(a[2]) + hex(a[3]), description: a.slice(), codedWidth: w, codedHeight: h,
          optimizeForLatency: true }
      : null;
    // the sender's next frame after a config is a key frame
    if (!s.config) stopDecoder(s);
    else startDecoder(s);
  };
  H.streamFrame = (id, data, key, ts) => {
    const s = streams.get(id);
    if (!s) return;
    if (!s.decoder || (s.needKey && !key)) return say(s, 'd ' + num(ts));
    s.needKey = false;
    try {
      s.inside.push(ts);
      s.decoder.decode(new EncodedVideoChunk({ type: key ? 'key' : 'delta', timestamp: ts, data: new Uint8Array(data) }));
    } catch (e) {
      // not a frame it takes: the next key frame asked for
      s.inside = s.inside.filter((t) => t !== ts);
      say(s, 'd ' + num(ts));
      if (startDecoder(s)) say(s, 'b');
      return;
    }
    // a decoder that holds frames back would wait for more while the sender waits: with two inside, the older taken
    if (s.inside.length >= 2) say(s, 'd ' + num(s.inside.shift()));
  };
  H.streamJpeg = (id, data, ts) => {
    const s = streams.get(id);
    if (!s) return;
    const blob = new Blob([new Uint8Array(data)], { type: 'image/jpeg' });
    // (in the order they came, each decoded off the page's thread)
    s.jpegs = s.jpegs.then(() => createImageBitmap(blob).then((bmp) => {
      if (s.closed) return bmp.close();
      s.decoded.push({ ts, frame: bmp, w: bmp.width, h: bmp.height });
      say(s, `f ${num(ts)} ${bmp.width} ${bmp.height}`);
    }, () => say(s, 'd ' + num(ts))));
  };
  H.streamNext = (id) => {
    const s = streams.get(id);
    return s && s.events.length ? s.events.shift() : '';
  };
  H.streamShow = (id, ts) => {
    const s = streams.get(id);
    if (!s) return;
    const at = s.decoded.findIndex((f) => f.ts === ts);
    if (at < 0) return;
    const f = s.decoded[at];
    // it, and those decoded before it passed over
    s.decoded = s.decoded.filter((g) => {
      if (g.ts > ts) return true;
      if (g !== f) g.frame.close();
      return false;
    });
    if (!s.tex) {
      s.tex = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, s.tex);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    }
    gl.bindTexture(gl.TEXTURE_2D, s.tex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, f.frame);
    f.frame.close();
  };
  H.streamClose = (id) => {
    const s = streams.get(id);
    if (!s) return;
    stopDecoder(s);
    s.closed = true;
    for (const f of s.decoded) f.frame.close();
    s.decoded = [];
    if (s.tex) gl.deleteTexture(s.tex);
    streams.delete(id);
  };

  // ---- text ----
  const seg = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
  const mctx = document.createElement('canvas').getContext('2d');
  const advCache = new Map();
  const keys = new Map();
  const entries = [];
  let packX = 0, packY = 0, packH = 0, generation = 0;
  const rc = document.createElement('canvas');
  const rctx = rc.getContext('2d', { willReadFrequently: true });
  // style: 1 slanted, 2 the code face
  const font = (size, weight, style) => `${style & 1 ? 'italic ' : ''}${weight} ${size}px ${style & 2 ? MONO : style & 4 ? SERIF : FAMILY}`;

  H.fontMetrics = (size, weight, style, out) => {
    mctx.font = font(size, weight, style);
    const m = mctx.measureText('Hg国');
    out[0] = m.fontBoundingBoxAscent;
    out[1] = m.fontBoundingBoxDescent;
    out[2] = Math.round(size * 1.42);
    // the Han font's: a canvas tells only the first face's box, so the font's own
    out[3] = out[0];
    out[4] = out[1];
    // lines as asked, not on whole pixels
    out[5] = 0;
  };

  const textKey = (c, size, weight, style) => {
    const kk = c + '\x01' + size + '\x01' + weight + '\x01' + style;
    let key = keys.get(kk);
    if (key === undefined) {
      key = entries.length;
      entries.push({ c, size, weight, style, done: false });
      keys.set(kk, key);
    }
    return key;
  };
  H.textKey = textKey;
  // a width the canvas measures, kept
  const width = (f, s) => {
    const ak = f + '\x01' + s;
    let w = advCache.get(ak);
    if (w === undefined) {
      w = mctx.measureText(s).width;
      advCache.set(ak, w);
    }
    return w;
  };

  H.shape = (text, size, weight, style, out) => {
    const f = font(size, weight, style);
    mctx.font = f;
    const cap = out.length / 4;
    const segs = [...seg.segment(text)];
    // the canvas says no more of a cluster than its width alone; within a word, a cluster starts where the word up
    // to and with it ends, less its own width: kerning moves it as the browser does, the spacing the browser trims
    // between CJK punctuation is trimmed, and the word ends where the canvas ends it (letters that join)
    const blank = (c) => /^\s+$/.test(c);
    // no ligatures (style & 8, words with letter spacing): a canvas has no font-variant-ligatures, so the word is
    // measured with a zero width non-joiner between its clusters, which keeps the browser from making one
    const upTo = style & 8
      ? (w, i) => segs.slice(w, i + 1).map((s) => s.segment).join('\u200C')
      : (w, i) => text.slice(segs[w].index, segs[i].index + segs[i].segment.length);
    const xs = new Array(segs.length);
    let word = 0;
    for (let i = 0; i < segs.length; i++) {
      const c = segs[i].segment;
      if (blank(c)) {
        word = i + 1;
        continue;
      }
      xs[i] = width(f, upTo(word, i)) - width(f, c);
    }
    let k = 0;
    word = 0;
    for (let i = 0; i < segs.length && k < cap; i++) {
      const s = segs[i];
      const c = s.segment;
      let adv;
      if (blank(c)) {
        adv = width(f, c);
      } else {
        const last = i + 1 >= segs.length || blank(segs[i + 1].segment);
        const end = last ? width(f, upTo(word, i)) : xs[i + 1];
        adv = Math.max(0, end - xs[i]);
      }
      if (blank(c)) word = i + 1;
      let key = -1;
      if (c === '\n') adv = 0;
      else if (c !== ' ' && c !== '\t') key = textKey(c, size, weight, style);
      out[k * 4] = s.index;
      out[k * 4 + 1] = c.length;
      out[k * 4 + 2] = adv;
      out[k * 4 + 3] = key;
      k++;
    }
    return k;
  };

  H.atlasGeneration = () => generation;

  function rasterize(e) {
    e.done = true;
    const sc = dpr;
    mctx.font = font(e.size, e.weight, e.style);
    const m = mctx.measureText(e.c);
    const left = m.actualBoundingBoxLeft, right = m.actualBoundingBoxRight;
    const asc = m.actualBoundingBoxAscent, desc = m.actualBoundingBoxDescent;
    // whole pixels each way from the baseline, so every glyph's baseline is
    // on a pixel row of its bitmap and glyphs on one line line up
    const pad = 1;
    const l = Math.ceil(left * sc), r = Math.ceil(right * sc);
    const a = Math.ceil(asc * sc), d = Math.ceil(desc * sc);
    const pw = l + r + 2 * pad, ph = a + d + 2 * pad;
    e.w = 0;
    if (pw <= 2 || ph <= 2 || pw > 512 || ph > 512) return;
    if (packX + pw + 1 > ATLAS) { packX = 0; packY += packH + 1; packH = 0; }
    if (packY + ph + 1 > ATLAS) {
      for (const x of entries) x.done = false;
      e.done = true;
      packX = packY = packH = 0;
      generation++;
    }
    rc.width = pw;
    rc.height = ph;
    rctx.clearRect(0, 0, pw, ph);
    rctx.font = font(e.size * sc, e.weight, e.style);
    rctx.fillStyle = '#fff';
    rctx.textBaseline = 'alphabetic';
    rctx.fillText(e.c, pad + l, pad + a);
    const img = rctx.getImageData(0, 0, pw, ph);
    // drawn in white: a cluster with colours of its own (grey ones too: any pixel of some opacity not white) is an
    // emoji's
    let color = 0;
    for (let i = 0; i < img.data.length && !color; i += 4) {
      if (img.data[i + 3] > 64 && Math.min(img.data[i], img.data[i + 1], img.data[i + 2]) < 224) color = 1;
    }
    gl.bindTexture(gl.TEXTURE_2D, atlasTex);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
    gl.texSubImage2D(gl.TEXTURE_2D, 0, packX, packY, pw, ph, gl.RGBA, gl.UNSIGNED_BYTE, img);
    e.u = packX;
    e.v = packY;
    e.w = pw / sc;
    e.h = ph / sc;
    e.ox = -(l + pad) / sc;
    e.oy = -(a + pad) / sc;
    e.color = color;
    packX += pw + 1;
    packH = Math.max(packH, ph);
  }

  H.glyph = (key, out) => {
    const e = entries[key];
    if (!e) { for (let i = 0; i < 8; i++) out[i] = 0; return; }
    if (!e.done) rasterize(e);
    out[0] = e.u || 0; out[1] = e.v || 0; out[2] = e.w || 0; out[3] = e.h || 0;
    out[4] = e.ox || 0; out[5] = e.oy || 0; out[6] = e.color || 0;
  };

  // ---- the platform's own text drawing (textref_js.mbt, src/textdiff) ----
  // A 2D canvas drawn with fillText at the places mbui draws the same words, and the window's own picture read back
  // as it is drawn; both kept as PNG data URLs in window.__mbref for whoever drives the page (scripts/textdiff-web.mjs).
  window.__mbref = {};
  let refCanvas = null, refCtx = null, refFrameName = null;
  const hex = (c) => '#' + (c & 0xffffff).toString(16).padStart(6, '0');
  H.refBegin = (w, h, s, bg) => {
    refCanvas = document.createElement('canvas');
    refCanvas.width = Math.round(w * s);
    refCanvas.height = Math.round(h * s);
    refCtx = refCanvas.getContext('2d');
    refCtx.fillStyle = hex(bg);
    refCtx.fillRect(0, 0, refCanvas.width, refCanvas.height);
    refCtx.scale(s, s);
  };
  H.refText = (text, size, weight, style, x, base, color, out) => {
    for (let i = 0; i < 5; i++) out[i] = 0;
    if (!refCtx) return;
    refCtx.font = font(size, weight, style);
    refCtx.fillStyle = hex(color);
    refCtx.textBaseline = 'alphabetic';
    refCtx.fillText(text, x, base);
    const m = refCtx.measureText(text);
    out[0] = m.width;
    out[1] = -m.actualBoundingBoxLeft;
    out[2] = -m.actualBoundingBoxAscent;
    out[3] = m.actualBoundingBoxRight;
    out[4] = m.actualBoundingBoxDescent;
  };
  H.refEnd = (name) => {
    if (!refCanvas) return false;
    window.__mbref[name] = refCanvas.toDataURL('image/png');
    refCanvas = refCtx = null;
    return true;
  };
  // the next frame drawn, read back before the browser shows it (a WebGL canvas keeps nothing after)
  H.refFrame = (name) => { refFrameName = name; return true; };
  const presentFrame = H.present;
  H.present = (buf, n, r, g, b) => {
    presentFrame(buf, n, r, g, b);
    if (refFrameName === null) return;
    const w = canvas.width, h = canvas.height;
    const px = new Uint8Array(w * h * 4);
    gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, px);
    const c2 = document.createElement('canvas');
    c2.width = w;
    c2.height = h;
    const x2 = c2.getContext('2d');
    const img = x2.createImageData(w, h);
    for (let y = 0; y < h; y++) img.data.set(px.subarray((h - 1 - y) * w * 4, (h - y) * w * 4), y * w * 4);
    x2.putImageData(img, 0, 0);
    window.__mbref[refFrameName] = c2.toDataURL('image/png');
    refFrameName = null;
  };

  // ---- input ----
  let imeActive = false;
  H.setIme = (active, x, y, w, h, text, s, e) => {
    imeActive = active;
    ta.style.left = `${x}px`;
    ta.style.top = `${y}px`;
    ta.style.height = `${h}px`;
    if (active && document.activeElement !== ta) ta.focus({ preventScroll: true });
    if (!active && document.activeElement === ta) ta.blur();
  };

  function pos(e) {
    const r = canvas.getBoundingClientRect();
    return [e.clientX - r.left, e.clientY - r.top];
  }

  // a pointer event, with its own time (performance.now's clock) while MoonBit handles it
  let evT = -1;
  function ptr(kind, e, button) {
    const [x, y] = pos(e);
    evT = e.timeStamp;
    try { cb.pointer(kind, x, y, button); } finally { evT = -1; }
  }

  function setupInput() {
    canvas.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      canvas.setPointerCapture(e.pointerId);
      ptr(0, e, e.button);
      // keep the keyboard on the textarea while an editor has focus
      if (imeActive) ta.focus({ preventScroll: true });
    });
    canvas.addEventListener('pointermove', (e) => ptr(1, e, 0));
    canvas.addEventListener('pointerup', (e) => ptr(2, e, e.button === 2 ? 2 : 0));
    canvas.addEventListener('pointercancel', (e) => ptr(3, e, 0));
    // the pointer gone out of the page (nothing hovered); a right click is the app's (its context menus)
    canvas.addEventListener('pointerleave', (e) => { if (e.pointerType === 'mouse') cb.pointer(7, -1, -1, 0); });
    canvas.addEventListener('contextmenu', (e) => e.preventDefault());
    canvas.addEventListener('wheel', (e) => {
      e.preventDefault();
      const k = e.deltaMode === 1 ? 16 : e.deltaMode === 2 ? cssH : 1;
      const [x, y] = pos(e);
      // lines (a mouse wheel's notches, as Firefox says them): eased in by the app (phase 4)
      cb.wheel(x, y, e.deltaX * k, e.deltaY * k, e.deltaMode === 1 ? 4 : 0);
    }, { passive: false });
    const keymap = { Backspace: 1, Delete: 2, ArrowLeft: 3, ArrowRight: 4, ArrowUp: 5, ArrowDown: 6, Enter: 7, Home: 8, End: 9, PageUp: 15, PageDown: 16, Escape: 17, Tab: 18 };
    // the browser's own shortcuts left to it (reload, close, a new tab or window, the address bar, quit)
    const browsers = new Set(['r', 'w', 't', 'n', 'l', 'q', 'v']);
    const modsOf = (e) => (e.shiftKey ? 1 : 0) | (e.ctrlKey ? 2 : 0) | (e.altKey ? 4 : 0) | (e.metaKey ? 8 : 0);
    ta.addEventListener('keydown', (e) => {
      if (e.isComposing || e.keyCode === 229) return;
      const mods = modsOf(e);
      if ((e.metaKey || e.ctrlKey) && !keymap[e.key]) {
        const c = e.key.toLowerCase();
        if (c === 'a') { cb.key(12, mods); e.preventDefault(); }
        else if (c === 'c') { cb.key(13, mods); e.preventDefault(); }
        else if (c === 'x') { cb.key(14, mods); e.preventDefault(); }
        else if (c.length === 1 && !browsers.has(c)) { cb.key(1000 + c.charCodeAt(0), mods); e.preventDefault(); }
        return; // paste arrives as a paste event
      }
      const code = keymap[e.key];
      if (code) { cb.key(code, mods); e.preventDefault(); }
    });
    // with no field focused, the keys are the app's (its shortcuts, Escape, the arrows; a character as 1000 + it)
    window.addEventListener('keydown', (e) => {
      if (e.target === ta || imeActive || e.isComposing) return;
      if (e.altKey && e.key === 'ArrowLeft') return; // back (below)
      const mods = modsOf(e);
      const code = keymap[e.key];
      if (code) { cb.key(code, mods); e.preventDefault(); return; }
      const c = e.key.length === 1 ? e.key.toLowerCase() : '';
      if (!c) return;
      if ((e.metaKey || e.ctrlKey) && browsers.has(c)) return;
      // select all, copy (the words picked with the pointer), cut: the editor's codes
      const own = (e.metaKey || e.ctrlKey) ? { a: 12, c: 13, x: 14 }[c] : undefined;
      cb.key(own ?? 1000 + c.charCodeAt(0), mods);
      e.preventDefault();
    });
    ta.addEventListener('input', (e) => {
      if (e.isComposing) return;
      if (e.inputType === 'insertText' || e.inputType === 'insertReplacementText') {
        if (e.data) cb.text(0, e.data, 0, 0);
      }
      ta.value = '';
    });
    ta.addEventListener('paste', (e) => {
      const t = e.clipboardData.getData('text/plain');
      if (t) cb.text(0, t, 0, 0);
      e.preventDefault();
    });
    ta.addEventListener('compositionupdate', (e) => cb.text(1, e.data || '', (e.data || '').length, 0));
    ta.addEventListener('compositionend', (e) => {
      cb.text(1, '', 0, 0);
      if (e.data) cb.text(0, e.data, 0, 0);
      ta.value = '';
    });
    window.addEventListener('resize', H.requestFrame);
  }

  // the pointer's shape (@host.set_cursor)
  const cursors = ['default', 'pointer', 'text', 'ew-resize', 'ns-resize', 'grab'];
  H.setCursor = (k) => { canvas.style.cursor = cursors[k] || 'default'; };
  H.clipboardSet = (s) => { navigator.clipboard?.writeText(s).catch(() => {}); };
  // the word around a UTF-16 offset as the browser finds words (Intl.Segmenter: a dictionary's in Chinese), start × 2³²
  // + end; -1 without one
  const words = typeof Intl !== 'undefined' && Intl.Segmenter ? new Intl.Segmenter(undefined, { granularity: 'word' }) : null;
  H.wordAt = (t, o) => {
    if (!words) return -1;
    const seg = words.segment(t).containing(o);
    return seg ? seg.index * 4294967296 + seg.index + seg.segment.length : -1;
  };
  // a URL handed to the browser: a tab of its own (noopener: the page cannot reach this one; window.open then answers
  // null whether or not it opened, so it is taken as handed over)
  H.openUrl = (u) => {
    window.__opened = (window.__opened || []).concat([u]);
    window.open(u, '_blank', 'noopener');
    return true;
  };
  H.log = (s) => { console.log(s); window.__logs.push(s); };
  H.benchMode = () => Number(params.get('bench') || 0);
  // the app's end: no frame after it (a page cannot close itself; whoever drives it reads __done)
  H.exit = (code) => { window.__done = code; document.title = 'DONE ' + code; };
  H.eventTime = () => evT;
  H.reduceTransparency = () => !!(window.matchMedia && matchMedia('(prefers-reduced-transparency: reduce)').matches);
  H.gpuMs = () => -1;
  H.memBytes = () => (performance.memory ? performance.memory.usedJSHeapSize : 0);

  // ---- back ----
  // No system back gesture here (the page's own edge swipe is MoonBit's): Alt+Left and a mouse's back button go
  // back, when the app takes it.
  let back = null, backOn = false;
  H.setBack = (b) => { back = b; };
  H.backEnabled = (on) => { backOn = on; };
  const goBack = (e) => { if (back && backOn) { e.preventDefault(); back(2, 0, 1, 0); } };
  window.addEventListener('keydown', (e) => { if (e.altKey && e.key === 'ArrowLeft') goBack(e); });
  window.addEventListener('mouseup', (e) => { if (e.button === 3) goBack(e); });

  H.run = (title, frame, pointer, wheel, key, text) => {
    document.title = title;
    canvas = document.getElementById('c');
    ta = document.getElementById('ime');
    setupGL();
    setupInput();
    cb = { frame, pointer, wheel, key, text };
    window.__mb = cb;
    resize();
    // (the app's first frame once the host knows what it decodes: h264Asked)
    h264Asked.then(() => {
      known = true;
      H.requestFrame();
    });
  };

  // ---- mbui-render (src/render, scripts/render_web.mjs): no frames, no input ----
  // The canvas the size a window's would be, its text at the list's scale; a frame is drawn into it as any
  // (H.present) and read back at once (the drawing buffer is not kept past the task), top row first.
  H.renderInit = (w, h, scale) => {
    canvas = document.getElementById('c');
    cssW = w;
    cssH = h;
    dpr = scale;
    canvas.width = Math.round(w * scale);
    canvas.height = Math.round(h * scale);
    canvas.style.width = w + 'px';
    canvas.style.height = h + 'px';
    setupGL();
  };
  H.renderPixels = () => {
    const w = canvas.width, h = canvas.height, row = w * 4;
    const px = new Uint8Array(row * h), out = new Uint8Array(row * h);
    gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, px);
    for (let y = 0; y < h; y++) out.set(px.subarray((h - 1 - y) * row, (h - y) * row), y * row);
    return { w, h, px: out };
  };
  H.renderInfo = () => {
    const x = gl.getExtension('WEBGL_debug_renderer_info');
    return x ? gl.getParameter(x.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
  };

  globalThis.__mbhost = H;
})();
