// Browser host for the MoonBit UI prototype: a WebGL2 canvas drawing the
// same instances as the Metal renderer, canvas-2D text rasterized into an
// atlas, and a hidden textarea that receives the system input method.
(() => {
  const FAMILY = 'system-ui, -apple-system, "PingFang SC", "Noto Sans CJK SC", "Segoe UI", sans-serif';
  const ATLAS = 2048;
  const params = new URLSearchParams(location.search);
  const H = {};
  let cb = null;
  let canvas, gl, prog, vao, instBuf, atlasTex, ta;
  let cssW = 0, cssH = 0, dpr = 1;
  let f32 = new Float32Array(24 * 4096);
  let pending = false;
  window.__logs = [];

  // ---- frames ----
  function tick() {
    pending = false;
    resize();
    cb.frame(cssW, cssH, dpr, performance.now());
  }
  H.requestFrame = () => {
    if (!pending && cb) {
      pending = true;
      requestAnimationFrame(tick);
    }
  };
  H.wakeAfter = (ms) => setTimeout(H.requestFrame, ms);

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
  uniform vec2 u_vp;
  out vec2 v_pos;
  flat out vec4 v_rect; flat out vec4 v_p; flat out vec4 v_color; flat out vec4 v_c2; flat out vec4 v_clip;
  void main() {
    int vid = gl_VertexID;
    vec2 corner = vec2((vid == 1 || vid == 4 || vid == 5) ? 1.0 : 0.0, (vid == 2 || vid == 3 || vid == 5) ? 1.0 : 0.0);
    int kind = int(a_p.y + 0.5);
    float grow = kind == 2 ? a_p.w * 2.0 + 2.0 : ((kind == 0 || kind == 4) ? 1.0 : 0.0);
    vec2 pos = a_rect.xy - grow + corner * (a_rect.zw + 2.0 * grow);
    gl_Position = vec4(pos.x / u_vp.x * 2.0 - 1.0, 1.0 - pos.y / u_vp.y * 2.0, 0.0, 1.0);
    v_pos = pos; v_rect = a_rect; v_p = a_p; v_color = a_color; v_c2 = a_c2; v_clip = a_clip;
  }`;
  const FS = `#version 300 es
  precision highp float;
  in vec2 v_pos;
  flat in vec4 v_rect; flat in vec4 v_p; flat in vec4 v_color; flat in vec4 v_c2; flat in vec4 v_clip;
  uniform float u_scale;
  uniform sampler2D u_atlas;
  uniform sampler2D u_img;
  out vec4 o;
  void main() {
    vec2 p = v_pos;
    if (p.x < v_clip.x || p.y < v_clip.y || p.x > v_clip.z || p.y > v_clip.w) discard;
    int kind = int(v_p.y + 0.5);
    vec4 col = v_color;
    if (kind == 1 || kind == 3) {
      vec2 uv = (v_c2.xy + (p - v_rect.xy) / v_rect.zw * v_c2.zw) / ${ATLAS}.0;
      vec4 t = texture(u_atlas, uv);
      o = kind == 1 ? vec4(col.rgb, 1.0) * (t.a * col.a) : t * col.a;
      return;
    }
    vec2 hs = v_rect.zw * 0.5;
    vec2 c = v_rect.xy + hs;
    float r = min(v_p.x, min(hs.x, hs.y));
    vec2 q = abs(p - c) - hs + r;
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    if (kind == 4) {
      vec2 uv = v_c2.xy + clamp((p - v_rect.xy) / v_rect.zw, 0.0, 1.0) * v_c2.zw;
      o = texture(u_img, uv) * (col.a * clamp(0.5 - d * u_scale, 0.0, 1.0));
      return;
    }
    if (kind == 2) {
      float b = max(v_p.w, 0.5);
      float a = 1.0 - smoothstep(-b, b, d);
      o = vec4(col.rgb, 1.0) * col.a * a;
      return;
    }
    float a = clamp(0.5 - d * u_scale, 0.0, 1.0);
    vec4 fill = vec4(col.rgb, 1.0) * col.a;
    if (v_p.z > 0.0) {
      float inner = clamp(0.5 - (d + v_p.z) * u_scale, 0.0, 1.0);
      vec4 bc = vec4(v_c2.rgb, 1.0) * v_c2.a;
      fill = mix(bc, fill, inner);
    }
    o = fill * a;
  }`;

  function compile(type, src) {
    const s = gl.createShader(type);
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
    return s;
  }

  function setupGL() {
    gl = canvas.getContext('webgl2', { premultipliedAlpha: true, antialias: false, alpha: false });
    prog = gl.createProgram();
    gl.attachShader(prog, compile(gl.VERTEX_SHADER, VS));
    gl.attachShader(prog, compile(gl.FRAGMENT_SHADER, FS));
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(prog));
    vao = gl.createVertexArray();
    gl.bindVertexArray(vao);
    instBuf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, instBuf);
    for (let i = 0; i < 5; i++) {
      const loc = i;
      // instance layout: rect, p, color, c2, clip, pad (vec4 each)
      gl.enableVertexAttribArray(loc);
      gl.vertexAttribPointer(loc, 4, gl.FLOAT, false, 96, i * 16);
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

  H.present = (buf, n, r, g, b) => {
    const len = n * 24;
    if (f32.length < len) f32 = new Float32Array(len * 2);
    for (let i = 0; i < len; i++) f32[i] = buf[i];
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.clearColor(r, g, b, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);
    if (n === 0) return;
    gl.useProgram(prog);
    gl.bindVertexArray(vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, instBuf);
    gl.bufferData(gl.ARRAY_BUFFER, f32.subarray(0, len), gl.STREAM_DRAW);
    gl.uniform2f(gl.getUniformLocation(prog, 'u_vp'), cssW, cssH);
    gl.uniform1f(gl.getUniformLocation(prog, 'u_scale'), dpr);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, atlasTex);
    gl.uniform1i(gl.getUniformLocation(prog, 'u_atlas'), 0);
    gl.uniform1i(gl.getUniformLocation(prog, 'u_img'), 1);
    // one draw per run of instances showing the same image (slot 20); WebGL
    // has no base instance, so the attributes start at the run instead
    let start = 0;
    while (start < n) {
      const tid = f32[start * 24 + 20] | 0;
      let end = start + 1;
      while (end < n && (f32[end * 24 + 20] | 0) === tid) end++;
      const im = tid ? images.get(tid) : null;
      gl.activeTexture(gl.TEXTURE1);
      gl.bindTexture(gl.TEXTURE_2D, im && im.tex ? im.tex : atlasTex);
      for (let i = 0; i < 5; i++) gl.vertexAttribPointer(i, 4, gl.FLOAT, false, 96, start * 96 + i * 16);
      gl.drawArraysInstanced(gl.TRIANGLES, 0, 6, end - start);
      start = end;
    }
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
      im.state = -1;
    }
    H.requestFrame();
  }
  H.imageLoad = (src, maxPx) => {
    const id = ++nextImage;
    images.set(id, { state: 0 });
    fetch(src).then((r) => (r.ok ? r.blob() : Promise.reject(r.status)))
      .then((b) => decodeImage(id, b, maxPx))
      .catch(() => { const im = images.get(id); if (im) im.state = -1; H.requestFrame(); });
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

  // ---- text ----
  const seg = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
  const mctx = document.createElement('canvas').getContext('2d');
  const advCache = new Map();
  const keys = new Map();
  const entries = [];
  let packX = 0, packY = 0, packH = 0, generation = 0;
  const rc = document.createElement('canvas');
  const rctx = rc.getContext('2d', { willReadFrequently: true });
  const emojiRe = /\p{Extended_Pictographic}/u;
  const font = (size, weight) => `${weight} ${size}px ${FAMILY}`;

  H.fontMetrics = (size, weight, out) => {
    mctx.font = font(size, weight);
    const m = mctx.measureText('Hg国');
    out[0] = m.fontBoundingBoxAscent;
    out[1] = m.fontBoundingBoxDescent;
    out[2] = Math.round(size * 1.42);
  };

  H.shape = (text, size, weight, out) => {
    const f = font(size, weight);
    mctx.font = f;
    const cap = out.length / 4;
    let k = 0;
    for (const s of seg.segment(text)) {
      if (k >= cap) break;
      const c = s.segment;
      const ak = f + '\x01' + c;
      let adv = advCache.get(ak);
      if (adv === undefined) {
        adv = mctx.measureText(c).width;
        advCache.set(ak, adv);
      }
      let key = -1;
      if (c === '\n') adv = 0;
      else if (c !== ' ' && c !== '\t') {
        const kk = c + '\x01' + size + '\x01' + weight;
        key = keys.get(kk);
        if (key === undefined) {
          key = entries.length;
          entries.push({ c, size, weight, done: false });
          keys.set(kk, key);
        }
      }
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
    mctx.font = font(e.size, e.weight);
    const m = mctx.measureText(e.c);
    const left = m.actualBoundingBoxLeft, right = m.actualBoundingBoxRight;
    const asc = m.actualBoundingBoxAscent, desc = m.actualBoundingBoxDescent;
    const pad = 1;
    const pw = Math.ceil((left + right) * sc) + 2 * pad, ph = Math.ceil((asc + desc) * sc) + 2 * pad;
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
    rctx.font = font(e.size * sc, e.weight);
    rctx.fillStyle = '#fff';
    rctx.textBaseline = 'alphabetic';
    rctx.fillText(e.c, pad + left * sc, pad + asc * sc);
    const img = rctx.getImageData(0, 0, pw, ph);
    gl.bindTexture(gl.TEXTURE_2D, atlasTex);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
    gl.texSubImage2D(gl.TEXTURE_2D, 0, packX, packY, pw, ph, gl.RGBA, gl.UNSIGNED_BYTE, img);
    e.u = packX;
    e.v = packY;
    e.w = pw / sc;
    e.h = ph / sc;
    e.ox = -left - pad / sc;
    e.oy = -asc - pad / sc;
    e.color = emojiRe.test(e.c) ? 1 : 0;
    packX += pw + 1;
    packH = Math.max(packH, ph);
  }

  H.glyph = (key, out) => {
    const e = entries[key];
    if (!e) { for (let i = 0; i < 7; i++) out[i] = 0; return; }
    if (!e.done) rasterize(e);
    out[0] = e.u || 0; out[1] = e.v || 0; out[2] = e.w || 0; out[3] = e.h || 0;
    out[4] = e.ox || 0; out[5] = e.oy || 0; out[6] = e.color || 0;
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

  function setupInput() {
    canvas.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      canvas.setPointerCapture(e.pointerId);
      const [x, y] = pos(e);
      cb.pointer(0, x, y, e.button);
      // keep the keyboard on the textarea while an editor has focus
      if (imeActive) ta.focus({ preventScroll: true });
    });
    canvas.addEventListener('pointermove', (e) => { const [x, y] = pos(e); cb.pointer(1, x, y, 0); });
    canvas.addEventListener('pointerup', (e) => { const [x, y] = pos(e); cb.pointer(2, x, y, 0); });
    canvas.addEventListener('pointercancel', (e) => { const [x, y] = pos(e); cb.pointer(3, x, y, 0); });
    canvas.addEventListener('wheel', (e) => {
      e.preventDefault();
      const k = e.deltaMode === 1 ? 16 : e.deltaMode === 2 ? cssH : 1;
      const [x, y] = pos(e);
      cb.wheel(x, y, e.deltaX * k, e.deltaY * k, 0);
    }, { passive: false });
    const keymap = { Backspace: 1, Delete: 2, ArrowLeft: 3, ArrowRight: 4, ArrowUp: 5, ArrowDown: 6, Enter: 7, Home: 8, End: 9 };
    ta.addEventListener('keydown', (e) => {
      if (e.isComposing || e.keyCode === 229) return;
      const mods = (e.shiftKey ? 1 : 0) | (e.ctrlKey ? 2 : 0) | (e.altKey ? 4 : 0) | (e.metaKey ? 8 : 0);
      if (e.metaKey || e.ctrlKey) {
        const c = e.key.toLowerCase();
        if (c === 'a') { cb.key(12, mods); e.preventDefault(); }
        else if (c === 'c') { cb.key(13, mods); e.preventDefault(); }
        else if (c === 'x') { cb.key(14, mods); e.preventDefault(); }
        return; // paste arrives as a paste event
      }
      const code = keymap[e.key];
      if (code) { cb.key(code, mods); e.preventDefault(); }
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

  H.clipboardSet = (s) => { navigator.clipboard?.writeText(s).catch(() => {}); };
  H.log = (s) => { console.log(s); window.__logs.push(s); };
  H.benchMode = () => Number(params.get('bench') || 0);
  H.exit = (code) => { window.__done = code; document.title = 'DONE ' + code; };
  H.memBytes = () => (performance.memory ? performance.memory.usedJSHeapSize : 0);

  H.run = (title, frame, pointer, wheel, key, text) => {
    document.title = title;
    cb = { frame, pointer, wheel, key, text };
    window.__mb = cb;
    canvas = document.getElementById('c');
    ta = document.getElementById('ime');
    setupGL();
    setupInput();
    resize();
    H.requestFrame();
  };

  globalThis.__mbhost = H;
})();
