// iOS's Liquid Glass over a picture, as github.com/iyinchao/liquid-glass-studio renders it (MIT: LICENSE-liquid-glass-
// studio; its fragment-main.glsl's last step, its SDFs, its colour helpers and its default parameters kept as it has
// them), for shapes of our own: rounded rects (capsules and discs) in the picture's pixels. glassOver(canvas, shapes,
// dpr) draws the picture with the shapes as glass over it into a canvas of its size and gives it.
const VERT = `#version 300 es
in vec2 a_pos; out vec2 v_uv;
void main() { v_uv = a_pos * 0.5 + 0.5; gl_Position = vec4(a_pos, 0.0, 1.0); }`;
const COMMON = `#version 300 es
precision highp float;
#define PI (3.14159265359)
#define MAXS 12
in vec2 v_uv;
uniform vec2 u_resolution;
uniform float u_dpr;
uniform int u_count;
uniform vec4 u_shapes[MAXS];   // centre x, y (pixels, from the foot), half width, half height
uniform float u_radius[MAXS];  // corner radius in pixels
float superellipseCornerSDF(vec2 p, float r, float n) {
  p = abs(p);
  float v = pow(pow(p.x, n) + pow(p.y, n), 1.0 / n);
  return v - r;
}
float roundedRect(vec2 p, vec2 half_, float cr, float n) {
  vec2 d = abs(p) - half_;
  if (d.x > -cr && d.y > -cr) {
    vec2 cc = sign(p) * (half_ - vec2(cr));
    return superellipseCornerSDF(p - cc, cr, n);
  }
  return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}
// the shapes' distance in pixels, over the resolution's height (the studio's units)
float mainSDF(vec2 px) {
  float d = 1e9;
  for (int i = 0; i < MAXS; i++) {
    if (i >= u_count) break;
    d = min(d, roundedRect(px - u_shapes[i].xy, u_shapes[i].zw, u_radius[i], 2.0));
  }
  return d / u_resolution.y;
}
`;
const BG = COMMON + `
uniform sampler2D u_tex;
uniform float u_shadowExpand;
uniform float u_shadowFactor;
uniform vec2 u_shadowPosition;
out vec4 fragColor;
void main() {
  vec3 bg = texture(u_tex, v_uv).rgb;
  vec2 res1x = u_resolution / u_dpr;
  float merged = mainSDF(gl_FragCoord.xy + u_shadowPosition * u_dpr);
  float shadow = exp(-1.0 / u_shadowExpand * abs(merged) * res1x.y) * 0.6 * u_shadowFactor;
  fragColor = vec4(bg - vec3(shadow), 1.0);
}`;
const MAIN = COMMON + `
const float N_R = 1.0 - 0.02;
const float N_G = 1.0;
const float N_B = 1.0 + 0.02;
uniform sampler2D u_blurredBg;
uniform sampler2D u_bg;
uniform vec4 u_tint;
uniform float u_refThickness;
uniform float u_refDistance;
uniform float u_refFactor;
uniform float u_refDispersion;
uniform float u_refFresnelRange;
uniform float u_refFresnelFactor;
uniform float u_refFresnelHardness;
uniform float u_glareRange;
uniform float u_glareConvergence;
uniform float u_glareOppositeFactor;
uniform float u_glareFactor;
uniform float u_glareHardness;
uniform float u_glareAngle;
uniform int u_blurEdge;
out vec4 fragColor;
float safeAsin(float x) { return asin(clamp(x, -1.0, 1.0)); }
// Color space conversions: HSV / sRGB / linear RGB / XYZ / Lab / LCH.
// Pure helper functions (no uniforms) — meant to be #included into a shader
// that already declares #version and precision.
// LCH stack from https://github.com/Rachmanin0xFF/GLSL-Color-Functions/blob/main/color-functions.glsl

vec3 hsv2rgb(vec3 c) {
  vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
  return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

//                          0.3127/0.3290  1.0  (1.0-0.3127-0.3290)/0.329
const vec3 D65_WHITE = vec3(0.95045592705, 1.0, 1.08905775076);
//                          0.3457/0.3585  1.0  (1.0-0.3457-0.3585)/0.3585
const vec3 D50_WHITE = vec3(0.96429567643, 1.0, 0.82510460251);
vec3 WHITE = D65_WHITE;
const mat3 RGB_TO_XYZ_M = mat3(
  0.4124, 0.3576, 0.1805,
  0.2126, 0.7152, 0.0722,
  0.0193, 0.1192, 0.9505
);
const mat3 XYZ_TO_XYZ50_M = mat3(
   1.0479298208405488  ,  0.022946793341019088, -0.05019222954313557 ,
   0.029627815688159344,  0.990434484573249   , -0.01707382502938514 ,
  -0.009243058152591178,  0.015055144896577895,  0.7518742899580008
);
const mat3 XYZ_TO_RGB_M = mat3(
   3.2406255, -1.537208 , -0.4986286,
  -0.9689307,  1.8757561,  0.0415175,
   0.0557101, -0.2040211,  1.0569959
);
const mat3 XYZ50_TO_XYZ_M = mat3(
   0.9554734527042182  , -0.023098536874261423,  0.0632593086610217  ,
  -0.028369706963208136,  1.0099954580058226  ,  0.021041398966943008,
   0.012314001688319899, -0.020507696433477912,  1.3303659366080753
);
float UNCOMPAND_SRGB(float a) {
  return a > 0.04045
    ? pow((a + 0.055) / 1.055, 2.4)
    : a / 12.92;
}
float COMPAND_RGB(float a) {
  return a <= 0.0031308
    ? 12.92 * a
    : 1.055 * pow(a, 0.41666666666) - 0.055;
}
vec3 RGB_TO_XYZ(vec3 rgb) {
  return WHITE == D65_WHITE
    ? rgb * RGB_TO_XYZ_M
    : rgb * RGB_TO_XYZ_M * XYZ_TO_XYZ50_M;
}
vec3 SRGB_TO_RGB(vec3 srgb) {
  return vec3(UNCOMPAND_SRGB(srgb.x), UNCOMPAND_SRGB(srgb.y), UNCOMPAND_SRGB(srgb.z));
}
vec3 RGB_TO_SRGB(vec3 rgb) {
  return vec3(COMPAND_RGB(rgb.x), COMPAND_RGB(rgb.y), COMPAND_RGB(rgb.z));
}
vec3 SRGB_TO_XYZ(vec3 srgb) {
  return RGB_TO_XYZ(SRGB_TO_RGB(srgb));
}
float XYZ_TO_LAB_F(float x) {
  //          (24/116)^3                         1/(3*(6/29)^2)     4/29
  return x > 0.00885645167
    ? pow(x, 0.333333333)
    : 7.78703703704 * x + 0.13793103448;
}
vec3 XYZ_TO_LAB(vec3 xyz) {
  vec3 xyz_scaled = xyz / WHITE;
  xyz_scaled = vec3(
    XYZ_TO_LAB_F(xyz_scaled.x),
    XYZ_TO_LAB_F(xyz_scaled.y),
    XYZ_TO_LAB_F(xyz_scaled.z)
  );
  return vec3(
    116.0 * xyz_scaled.y - 16.0,
    500.0 * (xyz_scaled.x - xyz_scaled.y),
    200.0 * (xyz_scaled.y - xyz_scaled.z)
  );
}
vec3 SRGB_TO_LAB(vec3 srgb) {
  return XYZ_TO_LAB(SRGB_TO_XYZ(srgb));
}
vec3 LAB_TO_LCH(vec3 Lab) {
  return vec3(Lab.x, sqrt(dot(Lab.yz, Lab.yz)), atan(Lab.z, Lab.y) * 57.2957795131);
}
vec3 SRGB_TO_LCH(vec3 srgb) {
  return LAB_TO_LCH(SRGB_TO_LAB(srgb));
}
vec3 XYZ_TO_RGB(vec3 xyz) {
  return WHITE == D65_WHITE
    ? xyz * XYZ_TO_RGB_M
    : xyz * XYZ50_TO_XYZ_M * XYZ_TO_RGB_M;
}
vec3 XYZ_TO_SRGB(vec3 xyz) {
  return RGB_TO_SRGB(XYZ_TO_RGB(xyz));
}
float LAB_TO_XYZ_F(float x) {
  //                                     3*(6/29)^2         4/29
  return x > 0.206897
    ? x * x * x
    : 0.12841854934 * (x - 0.137931034);
}
vec3 LAB_TO_XYZ(vec3 Lab) {
  float w = (Lab.x + 16.0) / 116.0;
  return WHITE *
  vec3(LAB_TO_XYZ_F(w + Lab.y / 500.0), LAB_TO_XYZ_F(w), LAB_TO_XYZ_F(w - Lab.z / 200.0));
}
vec3 LAB_TO_SRGB(vec3 lab) {
  return XYZ_TO_SRGB(LAB_TO_XYZ(lab));
}
vec3 LCH_TO_LAB(vec3 LCh) {
  return vec3(LCh.x, LCh.y * cos(LCh.z * 0.01745329251), LCh.y * sin(LCh.z * 0.01745329251));
}
vec3 LCH_TO_SRGB(vec3 lch) {
  return LAB_TO_SRGB(LCH_TO_LAB(lch));
}

vec2 getNormal(vec2 p) {
  vec2 h = vec2(1.0, 1.0);
  vec2 grad = vec2(mainSDF(p + vec2(h.x, 0.0)) - mainSDF(p - vec2(h.x, 0.0)), mainSDF(p + vec2(0.0, h.y)) - mainSDF(p - vec2(0.0, h.y))) / (2.0 * h);
  return grad * 1.414213562 * 1000.0;
}
float vec2ToAngle(vec2 v) { float a = atan(v.y, v.x); if (a < 0.0) a += 2.0 * PI; return a; }
vec4 getTextureDispersion(sampler2D tex1, sampler2D tex2, float mixRate, vec2 offset, float factor) {
  vec4 pixel = vec4(1.0);
  float bgR = texture(tex1, v_uv + offset * (1.0 - (N_R - 1.0) * factor)).r;
  float bgG = texture(tex1, v_uv + offset * (1.0 - (N_G - 1.0) * factor)).g;
  float bgB = texture(tex1, v_uv + offset * (1.0 - (N_B - 1.0) * factor)).b;
  float blurR = texture(tex2, v_uv + offset * (1.0 - (N_R - 1.0) * factor)).r;
  float blurG = texture(tex2, v_uv + offset * (1.0 - (N_G - 1.0) * factor)).g;
  float blurB = texture(tex2, v_uv + offset * (1.0 - (N_B - 1.0) * factor)).b;
  pixel.r = mix(bgR, blurR, mixRate);
  pixel.g = mix(bgG, blurG, mixRate);
  pixel.b = mix(bgB, blurB, mixRate);
  return pixel;
}
void main() {
  vec2 u_resolution1x = u_resolution.xy / u_dpr;
  float merged = mainSDF(gl_FragCoord.xy);
  vec4 outColor;
  if (merged < 0.005) {
    float nmerged = -1.0 * (merged * u_resolution1x.y);
    float x_R_ratio = 1.0 - nmerged / u_refThickness;
    float thetaI = safeAsin(pow(x_R_ratio, 2.0));
    float thetaT = safeAsin(1.0 / u_refFactor * sin(thetaI));
    float edgeFactor = -1.0 * tan(thetaT - thetaI);
    if (nmerged >= u_refThickness) edgeFactor = 0.0;
    if (edgeFactor <= 0.0) {
      outColor = texture(u_blurredBg, v_uv);
      outColor = mix(outColor, vec4(u_tint.r, u_tint.g, u_tint.b, 1.0), u_tint.a * 0.8);
    } else {
      float edgeH = nmerged / u_refThickness;
      vec2 normal = getNormal(gl_FragCoord.xy);
      vec4 blurredPixel = getTextureDispersion(u_bg, u_blurredBg, u_blurEdge > 0 ? 1.0 : edgeH,
        -normal * edgeFactor * u_refDistance * u_dpr * vec2(u_resolution.y / (u_resolution1x.x * u_dpr), 1.0), u_refDispersion);
      outColor = mix(blurredPixel, vec4(u_tint.r, u_tint.g, u_tint.b, 1.0), u_tint.a * 0.8);
      float fresnelFactor = clamp(pow(1.0 + merged * u_resolution1x.y / 1500.0 * pow(500.0 / u_refFresnelRange, 2.0) + u_refFresnelHardness, 5.0), 0.0, 1.0);
      vec3 fresnelTintLCH = SRGB_TO_LCH(mix(vec3(1.0), vec3(u_tint.r, u_tint.g, u_tint.b), u_tint.a * 0.5));
      fresnelTintLCH.x += 20.0 * fresnelFactor * u_refFresnelFactor;
      fresnelTintLCH.x = clamp(fresnelTintLCH.x, 0.0, 100.0);
      outColor = mix(outColor, vec4(LCH_TO_SRGB(fresnelTintLCH), 1.0), fresnelFactor * u_refFresnelFactor * 0.7 * length(normal));
      float glareGeoFactor = clamp(pow(1.0 + merged * u_resolution1x.y / 1500.0 * pow(500.0 / u_glareRange, 2.0) + u_glareHardness, 5.0), 0.0, 1.0);
      float glareAngle = (vec2ToAngle(normalize(normal)) - PI / 4.0 + u_glareAngle) * 2.0;
      int glareFarside = 0;
      if (glareAngle > PI * (2.0 - 0.5) && glareAngle < PI * (4.0 - 0.5) || glareAngle < PI * (0.0 - 0.5)) glareFarside = 1;
      float glareAngleFactor = (0.5 + sin(glareAngle) * 0.5) * (glareFarside == 1 ? 1.2 * u_glareOppositeFactor : 1.2) * u_glareFactor;
      glareAngleFactor = clamp(pow(glareAngleFactor, 0.1 + u_glareConvergence * 2.0), 0.0, 1.0);
      vec3 glareTintLCH = SRGB_TO_LCH(mix(blurredPixel.rgb, vec3(u_tint.r, u_tint.g, u_tint.b), u_tint.a * 0.5));
      glareTintLCH.x += 150.0 * glareAngleFactor * glareGeoFactor;
      glareTintLCH.y += 30.0 * glareAngleFactor * glareGeoFactor;
      glareTintLCH.x = clamp(glareTintLCH.x, 0.0, 120.0);
      outColor = mix(outColor, vec4(LCH_TO_SRGB(glareTintLCH), 1.0), glareAngleFactor * glareGeoFactor * length(normal));
    }
  } else {
    outColor = texture(u_bg, v_uv);
  }
  outColor = mix(outColor, texture(u_bg, v_uv), smoothstep(-0.001, 0.001, merged));
  fragColor = outColor;
}`;
const BLUR = (dir) => `#version 300 es
precision highp float;
in vec2 v_uv; uniform sampler2D u_prev; uniform vec2 u_resolution; uniform int u_r; uniform float u_w[64];
out vec4 fragColor;
void main() {
  vec2 t = ${dir} / u_resolution;
  vec4 c = texture(u_prev, v_uv) * u_w[0];
  for (int i = 1; i < 64; i++) { if (i > u_r) break; c += (texture(u_prev, v_uv + t * float(i)) + texture(u_prev, v_uv - t * float(i))) * u_w[i]; }
  fragColor = c;
}`;
// the studio's defaults (its Controls.tsx), as App.tsx hands them to the shader
export const DEFAULTS = {
  refThickness: 20, refDistance: .05, refFactor: 1.4, refDispersion: 7, refFresnelRange: 30, refFresnelHardness: .2,
  refFresnelFactor: .2, glareRange: 30, glareHardness: .2, glareFactor: .9, glareConvergence: .5, glareOppositeFactor: .8,
  glareAngle: -45 * Math.PI / 180, blurRadius: 1, blurEdge: 1, tint: [1, 1, 1, 0], shadowExpand: 25, shadowFactor: .15, shadowPosition: [0, -10],
};
let gl, progs, fbs = {}, size = [0, 0], quad;
function compile(fs) {
  const p = gl.createProgram();
  for (const [type, src] of [[gl.VERTEX_SHADER, VERT], [gl.FRAGMENT_SHADER, fs]]) {
    const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
    gl.attachShader(p, s);
  }
  gl.bindAttribLocation(p, 0, 'a_pos'); gl.linkProgram(p);
  if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
  return p;
}
function target(name, w, h) {
  if (fbs[name] && fbs[name].w === w && fbs[name].h === h) return fbs[name];
  const tex = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, tex);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
  for (const [k, v] of [[gl.TEXTURE_MIN_FILTER, gl.LINEAR], [gl.TEXTURE_MAG_FILTER, gl.LINEAR], [gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE], [gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE]]) gl.texParameteri(gl.TEXTURE_2D, k, v);
  const fb = gl.createFramebuffer(); gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
  gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0);
  return (fbs[name] = { tex, fb, w, h });
}
function kernel(r) {
  const s = Math.max(r / 2, .5), w = []; let sum = 0;
  for (let i = 0; i <= r; i++) { w[i] = Math.exp(-(i * i) / (2 * s * s)); sum += i ? 2 * w[i] : w[i]; }
  return w.map((x) => x / sum).concat(Array(64).fill(0)).slice(0, 64);
}
const glCanvas = document.createElement('canvas');
export function glassOver(src, shapes, dpr, params = {}) {
  const P = { ...DEFAULTS, ...params };
  const w = src.width, h = src.height;
  if (!gl) {
    gl = glCanvas.getContext('webgl2', { premultipliedAlpha: false, preserveDrawingBuffer: true });
    progs = { bg: compile(BG), v: compile(BLUR('vec2(0.0, 1.0)')), h: compile(BLUR('vec2(1.0, 0.0)')), main: compile(MAIN) };
    quad = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, quad);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
  }
  if (size[0] !== w || size[1] !== h) { glCanvas.width = w; glCanvas.height = h; size = [w, h]; }
  gl.bindBuffer(gl.ARRAY_BUFFER, quad); gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
  const srcTex = target('src', w, h);
  gl.bindTexture(gl.TEXTURE_2D, srcTex.tex);
  gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, src);
  const sh = new Float32Array(48), rad = new Float32Array(12);
  shapes.slice(0, 12).forEach((s, i) => { sh.set([s.x + s.w / 2, h - (s.y + s.h / 2), s.w / 2, s.h / 2], i * 4); rad[i] = s.r; });
  const run = (prog, out, texes, uni) => {
    gl.useProgram(prog);
    gl.bindFramebuffer(gl.FRAMEBUFFER, out ? out.fb : null); gl.viewport(0, 0, w, h);
    texes.forEach(([name, t], i) => { gl.activeTexture(gl.TEXTURE0 + i); gl.bindTexture(gl.TEXTURE_2D, t); gl.uniform1i(gl.getUniformLocation(prog, name), i); });
    const u = (n) => gl.getUniformLocation(prog, n);
    gl.uniform2f(u('u_resolution'), w, h); gl.uniform1f(u('u_dpr'), dpr); gl.uniform1i(u('u_count'), Math.min(12, shapes.length));
    gl.uniform4fv(u('u_shapes'), sh); gl.uniform1fv(u('u_radius'), rad);
    uni(u); gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  };
  const bg = target('bg', w, h), vb = target('vb', w, h), hb = target('hb', w, h);
  run(progs.bg, bg, [['u_tex', srcTex.tex]], (u) => { gl.uniform1f(u('u_shadowExpand'), P.shadowExpand); gl.uniform1f(u('u_shadowFactor'), P.shadowFactor); gl.uniform2f(u('u_shadowPosition'), -P.shadowPosition[0], -P.shadowPosition[1]); });
  const r = Math.max(1, Math.round(P.blurRadius * dpr)), k = kernel(Math.min(r, 63));
  run(progs.v, vb, [['u_prev', bg.tex]], (u) => { gl.uniform1i(u('u_r'), Math.min(r, 63)); gl.uniform1fv(u('u_w'), k); });
  run(progs.h, hb, [['u_prev', vb.tex]], (u) => { gl.uniform1i(u('u_r'), Math.min(r, 63)); gl.uniform1fv(u('u_w'), k); });
  run(progs.main, null, [['u_blurredBg', hb.tex], ['u_bg', bg.tex]], (u) => {
    gl.uniform4fv(u('u_tint'), P.tint);
    for (const k of ['refThickness', 'refDistance', 'refFactor', 'refDispersion', 'refFresnelRange', 'refFresnelFactor', 'refFresnelHardness', 'glareRange', 'glareConvergence', 'glareOppositeFactor', 'glareFactor', 'glareHardness', 'glareAngle']) gl.uniform1f(u('u_' + k), P[k]);
    gl.uniform1i(u('u_blurEdge'), P.blurEdge);
  });
  return glCanvas;
}
