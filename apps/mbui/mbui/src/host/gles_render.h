// The OpenGL ES 3 renderer of the hosts that draw with it, Android's (android_host.c) and Linux's (linux_render.c):
// the same instances and shader as Metal and WebGL2, glass's passes, the frame presented last kept to be drawn again,
// its pixels read back. Included once, by the file that has GLES 3's functions declared (Android's <GLES3/gl3.h>,
// Linux's epoxy) and, before it:
//   LOG(...)                          a line of the host's log, printf's way
//   static GLuint image_tex(int id);  the texture an instance's image (slot 20) is drawn from; 0: none (yet)
//   static void view_parts_in(int tid, int32_t start, int32_t end);  a native view's picture's run (draw_kept below)
//   MB_VIEW_TEX                       the first of a native view picture's image ids (src/hostapi/host.mbt)
//   MB_VIEWS_UNDER (optional)         the host keeps its native views under the surface (Linux's pages), not drawn in it
//                                     (Android's; Linux's players): a view's run for which the host's
//                                     static int view_under(int tid) is true takes the canvas away where it shows
//                                     (draw_kept below)
// What is drawn where is the host's to say: the frame's size in points and its scale (cur_w, cur_h, cur_scale), the
// surface's in pixels (fb_w, fb_h), the framebuffer drawn into (target_fb); gl_setup once its context is current.
#include "contained.h"

// the numbers of an instance (src/ui/scene.mbt)
#define MB_INST 60
// the glyphs' atlases, square, what goes where in them MoonBit's (hostapi's atlas.mbt): the words' (a byte a texel,
// how much of it the glyph covers: drawn in the text's colour; as many bytes as one RGBA atlas half as wide) and colour
// glyphs' (RGBA: an emoji's own). A colour glyph's place across is MB_ATLAS_COLOR_U past its place in its atlas (what
// MoonBit says of it, @hostapi.colour_atlas_u): the shader takes the atlas by it, as Apple's does.
#define MB_ATLAS 4096
#define MB_ATLAS_COLOR 1024
#define MB_ATLAS_COLOR_U 16384

static const char *VS =
    "#version 300 es\n"
    "layout(location=0) in vec4 a_rect;\n"
    "layout(location=1) in vec4 a_p;\n"
    "layout(location=2) in vec4 a_color;\n"
    "layout(location=3) in vec4 a_c2;\n"
    "layout(location=4) in vec4 a_clip;\n"
    "layout(location=5) in vec4 a_pad;\n"
    "layout(location=6) in vec4 a_rc;\n"
    "layout(location=7) in vec4 a_rs;\n"
    "layout(location=8) in vec4 a_rot;\n"
    "layout(location=9) in vec4 a_rr;\n"
    "layout(location=10) in vec4 a_oclip;\n"
    "layout(location=11) in vec4 a_orc;\n"
    "layout(location=12) in vec4 a_ors;\n"
    "layout(location=13) in vec4 a_fade;\n"
    "layout(location=14) in vec4 a_fadex;\n"
    "uniform vec2 u_vp;\n"
    "uniform vec4 u_gb;\n"
    "out vec2 v_pos; out vec2 v_cpos;\n"
    "flat out vec4 v_rect; flat out vec4 v_p; flat out vec4 v_color; flat out vec4 v_c2; flat out vec4 v_clip; flat out vec4 v_pad;\n"
    "flat out vec4 v_rc; flat out vec4 v_rs; flat out vec4 v_rr; flat out vec4 v_oclip; flat out vec4 v_orc; flat out vec4 v_ors;\n"
    "// how far each pixel is into its fades (scene.mbt 52-59: from its left, top, right, foot; 1 and past: whole), worked\n"
    "// out where it is drawn at its corners and taken across it as it goes straight\n"
    "out vec4 v_ramp;\n"
    "void main() {\n"
    "  int vid = gl_VertexID;\n"
    "  vec2 corner = vec2((vid == 1 || vid == 4 || vid == 5) ? 1.0 : 0.0, (vid == 2 || vid == 3 || vid == 5) ? 1.0 : 0.0);\n"
    "  int kind = int(a_p.y + 0.5);\n"
    "  float grow = kind == 2 ? a_p.w * 3.0 + 2.0 : ((kind == 0 || kind == 4 || kind == 5) ? 1.0 : 0.0);\n"
    "  vec2 pos = a_rect.xy - grow + corner * (a_rect.zw + 2.0 * grow);\n"
    "  if (kind == 6) pos = mix(u_gb.xy, u_gb.zw, corner);\n"
    "  // the pieces of shapes (kind 12): nothing drawn\n"
    "  if (kind == 12) pos = vec2(0.0);\n"
    "  // turned (scene.mbt 32-35): drawn turned about its point, everything of how in its own place (v_pos), its clip\n"
    "  // there too or (35: one from outside what turned) where it is drawn (v_cpos)\n"
    "  vec2 at = pos;\n"
    "  if (a_rot.x != 0.0) { vec2 d = pos - a_rot.yz; float c = cos(a_rot.x), s = sin(a_rot.x); at = a_rot.yz + vec2(c * d.x - s * d.y, s * d.x + c * d.y); }\n"
    "  gl_Position = vec4(at.x / u_vp.x * 2.0 - 1.0, 1.0 - at.y / u_vp.y * 2.0, 0.0, 1.0);\n"
    "  v_pos = pos; v_cpos = a_rot.w > 0.5 ? at : pos; v_rect = a_rect; v_p = a_p; v_color = a_color; v_c2 = a_c2; v_clip = a_clip; v_pad = a_pad; v_rc = a_rc; v_rs = a_rs; v_rr = a_rr;\n"
    "  v_oclip = a_oclip; v_orc = a_orc; v_ors = a_ors;\n"
    "  vec2 cq = a_rot.w > 0.5 ? at : pos;\n"
    "  v_ramp = vec4(a_fadex.y > 0.0 ? (cq.x - a_fadex.x) / a_fadex.y : 2.0, a_fade.y > 0.0 ? (cq.y - a_fade.x) / a_fade.y : 2.0,\n"
    "    a_fadex.w > 0.0 ? (a_fadex.z - cq.x) / a_fadex.w : 2.0, a_fade.w > 0.0 ? (a_fade.z - cq.y) / a_fade.w : 2.0);\n"
    "}\n";

static const char *FS =
    "#version 300 es\n"
    "precision highp float;\n"
    "in vec2 v_pos; in vec2 v_cpos;\n"
    "flat in vec4 v_rect; flat in vec4 v_p; flat in vec4 v_color; flat in vec4 v_c2; flat in vec4 v_clip; flat in vec4 v_pad;\n"
    "flat in vec4 v_rc; flat in vec4 v_rs; flat in vec4 v_rr; flat in vec4 v_oclip; flat in vec4 v_orc; flat in vec4 v_ors;\n"
    "in vec4 v_ramp;\n"
    "uniform float u_scale;\n"
    "uniform sampler2D u_atlas;\n"
    "uniform sampler2D u_catlas;\n"
    "uniform sampler2D u_img;\n"
    "// glass (src/ui/glass.mbt): the blurred copy under it and where a point is in it (uv = p * u_map.xy + u_map.zw, kept\n"
    "// in u_uvc), a liquid group's shapes and corners, how many\n"
    "uniform highp sampler2D u_bd;\n"
    "uniform vec4 u_map;\n"
    "uniform vec4 u_uvc;\n"
    "uniform vec4 u_shape[8];\n"
    "uniform vec4 u_rad[2];\n"
    "uniform int u_n;\n"
    "// the pieces of the frame's shapes (src/ui/shape.mbt: the instances of kind 12 after every one drawn), 2040 fours\n"
    "// (136 instances) a row\n"
    "uniform highp sampler2D u_segs;\n"
    "out vec4 o;\n"
    "#define float2 vec2\n"
    "#define float4 vec4\n"
    MB_CORNER_SL
    "float sd_rr(vec2 p, vec4 r, vec4 rad) {\n"
    "  vec2 hs = r.zw * 0.5;\n"
    "  return mb_sd_box(p - r.xy - hs, hs, mb_corner_of(p - r.xy - hs, rad), 1e9);\n"
    "}\n"
    "// a notch cut into the top edge (scene.mbt 21-23): a circle about the top's middle (pad.y below it, pad.z its radius),\n"
    "// met by the edge through fillets (pad.w): the rounded intersection with what is outside the circle\n"
    "float notch_cut(float d, vec2 p, vec4 r, vec4 pad) {\n"
    "  if (pad.z <= 0.0) return d;\n"
    "  float b = pad.z - length(p - vec2(r.x + r.z * 0.5, r.y + pad.y));\n"
    "  float f = max(pad.w, 0.0);\n"
    "  vec2 u = max(vec2(f + d, f + b), 0.0);\n"
    "  return min(-f, max(d, b)) + length(u);\n"
    "}\n"
    "float smin_k(float a, float b, float k) {\n"
    "  if (k <= 0.0) return min(a, b);\n"
    "  float h = max(k - abs(a - b), 0.0) / k;\n"
    "  return min(a, b) - h * h * k * 0.25;\n"
    "}\n"
    "float sd_group(vec2 p, float k) {\n"
    "  float d = 1e9;\n"
    "  for (int i = 0; i < 8; i++) {\n"
    "    if (i >= u_n) break;\n"
    "    d = smin_k(d, sd_rr(p, u_shape[i], vec4(u_rad[i / 4][i % 4])), k);\n"
    "  }\n"
    "  return d;\n"
    "}\n"
    "vec3 backdrop(vec2 p) {\n"
    "  return texture(u_bd, clamp(p * u_map.xy + u_map.zw, u_uvc.xy, u_uvc.zw)).rgb;\n"
    "}\n"
    "float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }\n"
    "// how much of the pixel at p its rounded clip keeps (r: the corners' radii, top left, then clockwise; s: how smooth\n"
    "// each is), its edge covered as a box's own (0.5 - d * scale), so what it cuts meets the ground of the box that cuts it\n"
    "float clip_cover(vec2 p, vec4 c, vec4 r, vec4 s, float scale) {\n"
    "  float d = mb_sd_clip(p, c, r, s, 1.0 + 2.0 / scale);\n"
    "  return clamp(0.5 - d * scale, 0.0, 1.0);\n"
    "}\n"
    "// what it shows at p, as if uncut\n"
    "void shade(vec2 p) {\n"
    "  int kind = int(v_p.y + 0.5);\n"
    "  // where a native view shows: its picture (NativeViews.Picture), the part of it c2 says, cut to its corners\n"
    "  if (kind == 9) { vec2 hh = v_rect.zw * 0.5; float rr = min(mb_corner_of(p - v_rect.xy - hh, v_rr), min(hh.x, hh.y)); vec2 q = abs(p - v_rect.xy - hh) - hh + rr; float a = clamp(0.5 - (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rr) * u_scale, 0.0, 1.0); if (a <= 0.0) discard; vec2 uv = v_c2.xy + clamp((p - v_rect.xy) / v_rect.zw, 0.0, 1.0) * v_c2.zw; if (uv.y < 0.0 || uv.y > 1.0) discard; o = texture(u_img, uv) * a; return; }\n"
    "  vec4 col = v_color;\n"
    "  if (kind == 11) {\n"
    "    // a band of a shape (src/ui/shape.mbt): c2.y of its pieces from c2.x; p.x half its stroke's width (0: a fill,\n"
    "    // c2.z 1 by the even-odd rule)\n"
    "    int first = int(v_c2.x + 0.5), n = int(v_c2.y + 0.5);\n"
    "    float a;\n"
    "    if (v_p.x > 0.0) {\n"
    "      float d = 1e9;\n"
    "      for (int i = first; i < first + n; i++) { int t = (i / 6) * 15 + mb_seg_slot(i); d = min(d, mb_seg_dist(texelFetch(u_segs, ivec2(t % 2040, t / 2040), 0), v_rect, p)); }\n"
    "      a = clamp(0.5 - (d - v_p.x) * u_scale, 0.0, 1.0);\n"
    "    } else {\n"
    "      vec4 w = vec4(0.0);\n"
    "      for (int i = first; i < first + n; i++) { int t = (i / 6) * 15 + mb_seg_slot(i); w += mb_path_rows(texelFetch(u_segs, ivec2(t % 2040, t / 2040), 0), v_rect, p, u_scale); }\n"
    "      a = mb_path_cover(w, v_c2.z);\n"
    "    }\n"
    "    o = vec4(col.rgb, 1.0) * col.a * a;\n"
    "    return;\n"
    "  }\n"
    "  if (kind == 10) {\n"
    "    // a piece of a line (scene.mbt): from c2.xy to c2.zw (shares of its rect), p.x half its width, its ends round\n"
    "    vec2 a = v_rect.xy + v_c2.xy * v_rect.zw, ab = v_rect.xy + v_c2.zw * v_rect.zw - a;\n"
    "    float h = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-8), 0.0, 1.0);\n"
    "    float d = length(p - a - ab * h) - v_p.x;\n"
    "    o = vec4(col.rgb, 1.0) * col.a * clamp(0.5 - d * u_scale, 0.0, 1.0);\n"
    "    return;\n"
    "  }\n"
    "  if (kind == 1 || kind == 3 || kind == 7) {\n"
    "    // within its own cell (c2: where in the atlas, in texels; a colour glyph's 16384 across past its place in theirs),\n"
    "    // however its rect is stretched or turned: a sample past the cell's edge texels would blend in what lies beside\n"
    "    // it (another glyph, one left there before). The words' atlas has a glyph's cover alone: white, premultiplied, as\n"
    "    // the colour one would have it\n"
    "    bool colour = v_c2.x >= 16384.0;\n"
    "    vec2 at = vec2(v_c2.x - (colour ? 16384.0 : 0.0), v_c2.y);\n"
    "    vec2 uv = clamp(at + (p - v_rect.xy) / v_rect.zw * v_c2.zw, at + 0.5, at + v_c2.zw - 0.5);\n"
    "    vec4 t = colour ? textureLod(u_catlas, uv / vec2(textureSize(u_catlas, 0)), 0.0)\n"
    "                    : vec4(textureLod(u_atlas, uv / vec2(textureSize(u_atlas, 0)), 0.0).r);\n"
    "    if (kind == 7) {\n"
    "      // inked by how light what is under its glass is, looked at round the glass's middle\n"
    "      vec2 c = v_pad.yz; float r = v_pad.w * 0.5;\n"
    "      float l = (luma(backdrop(c)) + luma(backdrop(c + vec2(r, 0.0))) + luma(backdrop(c - vec2(r, 0.0))) +\n"
    "                 luma(backdrop(c + vec2(0.0, r))) + luma(backdrop(c - vec2(0.0, r)))) / 5.0;\n"
    "      vec3 ink = mix(vec3(1.0), vec3(0.11, 0.11, 0.12), smoothstep(0.42, 0.6, l));\n"
    "      o = vec4(ink, 1.0) * (t.a * col.a);\n"
    "      return;\n"
    "    }\n"
    "    o = kind == 1 ? vec4(col.rgb, 1.0) * (t.a * col.a) : t * col.a;\n"
    "    return;\n"
    "  }\n"
    "  if (kind == 6) {\n"
    "    // liquid: one shape of the group's, merged; what is under it bent along the bezel, the colours split a little\n"
    "    float k = v_pad.w;\n"
    "    float d = sd_group(p, k);\n"
    "    float a = clamp(0.5 - d * u_scale, 0.0, 1.0);\n"
    "    if (a <= 0.0) discard;\n"
    "    float e = 0.5;\n"
    "    vec2 grad = vec2(sd_group(p + vec2(e, 0.0), k) - sd_group(p - vec2(e, 0.0), k),\n"
    "                     sd_group(p + vec2(0.0, e), k) - sd_group(p - vec2(0.0, e), k));\n"
    "    vec2 n = grad / max(length(grad), 1e-4);\n"
    "    float bezel = max(v_c2.y, 1.0);\n"
    "    float edge = 1.0 - clamp(-d / bezel, 0.0, 1.0);\n"
    "    float disp = v_pad.y * (1.0 - sqrt(max(1.0 - edge * edge, 0.0)));\n"
    "    vec2 off = -n * disp;\n"
    "    float ch = v_pad.z;\n"
    "    vec3 c = vec3(backdrop(p + off * (1.0 + ch)).r, backdrop(p + off).g, backdrop(p + off * (1.0 - ch)).b);\n"
    "    c = max(mix(vec3(luma(c)), c, v_p.z), 0.0);\n"
    "    c = c * (1.0 - col.a) + col.rgb * col.a;\n"
    "    // the rim lit from the top left, and less across from it\n"
    "    float ndl = dot(n, vec2(-0.6, -0.8));\n"
    "    float band = clamp(1.0 + d / 2.5, 0.0, 1.0);\n"
    "    float spec = v_c2.x * (band * (0.9 * pow(max(ndl, 0.0), 1.5) + 0.45 * pow(max(-ndl, 0.0), 1.5)) +\n"
    "                           0.3 * edge * edge * max(ndl, 0.0));\n"
    "    // the edge shaded, more on the side away from the light, so the shape reads over a light ground too\n"
    "    c *= 1.0 - v_c2.x * band * (0.1 + 0.25 * max(-ndl, 0.0));\n"
    "    c = c + (1.0 - c) * clamp(spec, 0.0, 1.0);\n"
    "    c += mb_dither(p * u_scale) / 255.0;\n"
    "    o = vec4(c, 1.0) * (a * v_c2.w);\n"
    "    return;\n"
    "  }\n"
    "  vec2 hs = v_rect.zw * 0.5;\n"
    "  vec2 c = v_rect.xy + hs;\n"
    "  // worked out as near the curve as its cover, its edge or its blur reaches\n"
    "  float band = 1.0 + 2.0 / u_scale + (kind == 2 ? max(v_p.w, 0.5) : max(v_p.z, 0.0));\n"
    "  // (its corner by p: v_rr, each its own)\n"
    "  float rad = mb_corner_of(p - c, v_rr);\n"
    "  float d = mb_sd_box(p - c, hs, rad, band);\n"
    "  if (kind == 0 || kind == 5) d = notch_cut(d, p, v_rect, v_pad);\n"
    "  if (kind == 4) {\n"
    "    vec2 uv = v_c2.xy + clamp((p - v_rect.xy) / v_rect.zw, 0.0, 1.0) * v_c2.zw;\n"
    "    o = texture(u_img, uv) * (col.a * clamp(0.5 - d * u_scale, 0.0, 1.0));\n"
    "    return;\n"
    "  }\n"
    "  if (kind == 2) {\n"
    "    // as Core Animation's: the shape blurred, sigma its radius (corner.sl mb_shadow)\n"
    "    float a = mb_shadow(p - c, hs, rad, max(v_p.w, 0.25));\n"
    "    // glass's: only outside its box (c2.y above it)\n"
    "    if (v_c2.x > 0.5) {\n"
    "      vec2 q = p - c + vec2(0.0, v_c2.y);\n"
    "      float db = mb_sd_box(q, hs, mb_corner_of(q, v_rr), band);\n"
    "      a *= clamp(0.5 + db * u_scale, 0.0, 1.0);\n"
    "    }\n"
    "    o = vec4(col.rgb, 1.0) * col.a * a;\n"
    "    return;\n"
    "  }\n"
    "  float a = clamp(0.5 - d * u_scale, 0.0, 1.0);\n"
    "  if (kind == 5) {\n"
    "    // frosted: the blurred copy, saturated, the tint over it; the rim (a hairline inside the edge, the top left lit,\n"
    "    // the foot and right less), 0.5 wide\n"
    "    vec3 g3 = backdrop(p);\n"
    "    g3 = max(mix(vec3(luma(g3)), g3, v_p.z), 0.0);\n"
    "    g3 = g3 * (1.0 - col.a) + col.rgb * col.a;\n"
    "    if (v_c2.x + v_c2.y + v_c2.z > 0.0) {\n"
    "      float edge = clamp(0.5 + (d + 0.5) * u_scale, 0.0, 1.0);\n"
    "      float lit = clamp(0.5 + notch_cut(sd_rr(p - 0.5, v_rect, v_rr), p - 0.5, v_rect, v_pad) * u_scale, 0.0, 1.0);\n"
    "      float back = clamp(0.5 + notch_cut(sd_rr(p + 0.5, v_rect, v_rr), p + 0.5, v_rect, v_pad) * u_scale, 0.0, 1.0);\n"
    "      g3 = mix(g3, vec3(1.0), v_c2.x * edge);\n"
    "      g3 = mix(g3, vec3(1.0), v_c2.y * lit);\n"
    "      g3 = mix(g3, vec3(1.0), v_c2.z * back);\n"
    "    }\n"
    "    // dithered as it is written to 8 bits, so its slopes do not band (corner.sl mb_dither)\n"
    "    g3 += mb_dither(p * u_scale) / 255.0;\n"
    "    o = vec4(g3, 1.0) * (a * v_c2.w);\n"
    "    return;\n"
    "  }\n"
    "  vec4 fill = vec4(col.rgb, 1.0) * col.a;\n"
    "  if (v_p.z > 0.0) {\n"
    "    float inner = clamp(0.5 - (d + v_p.z) * u_scale, 0.0, 1.0);\n"
    "    vec4 bc = vec4(v_c2.rgb, 1.0) * v_c2.a;\n"
    "    fill = mix(bc, fill, inner);\n"
    "  }\n"
    "  o = fill * a;\n"
    "}\n"
    "// cut to its clip: a rect's, hard; a rounded one's, covered as edges are\n"
    "void main() {\n"
    "  vec2 p = v_pos, cp = v_cpos;\n"
    "  float cover = 1.0;\n"
    "  if (max(max(v_rc.x, v_rc.y), max(v_rc.z, v_rc.w)) > 0.0) {\n"
    "    cover = clip_cover(cp, v_clip, v_rc, v_rs, u_scale);\n"
    "    if (cover <= 0.0) discard;\n"
    "  } else if (cp.x < v_clip.x || cp.y < v_clip.y || cp.x > v_clip.z || cp.y > v_clip.w) discard;\n"
    "  // and by the clip outside it, where it has one (scene.mbt 40-51: a pane round an image's frame in its corner)\n"
    "  if (max(max(v_orc.x, v_orc.y), max(v_orc.z, v_orc.w)) > 0.0) {\n"
    "    cover *= clip_cover(cp, v_oclip, v_orc, v_ors, u_scale);\n"
    "    if (cover <= 0.0) discard;\n"
    "  }\n"
    "  // and faded out towards a cut, each pixel by where it is (scene.mbt 52-59)\n"
    "  vec4 ramp = clamp(v_ramp, 0.0, 1.0);\n"
    "  cover *= ramp.x * ramp.y * ramp.z * ramp.w;\n"
    "  if (cover <= 0.0) discard;\n"
    "  shade(p);\n"
    "  o *= cover;\n"
    "}\n";

// glass's passes over its copy of what is under it
static const char *PVS =
    "#version 300 es\n"
    "void main() {\n"
    "  gl_Position = vec4(gl_VertexID == 1 ? 3.0 : -1.0, gl_VertexID == 2 ? 3.0 : -1.0, 0.0, 1.0);\n"
    "}\n";

static const char *PFS =
    "#version 300 es\n"
    "precision highp float;\n"
    "#define float2 vec2\n"
    "#define float4 vec4\n"
    MB_CORNER_SL
    "// The backdrop's passes: u_a.xy the source's texel, u_a.z 1 halving (dual Kawase's down), 2 a Gaussian along u_b.zw\n"
    "// of deviation u_a.w (texels); u_b.xy the last texel's centre of what the source holds\n"
    "uniform highp sampler2D u_src;\n"
    "uniform vec4 u_a;\n"
    "uniform vec4 u_b;\n"
    "uniform vec4 u_c[9];\n"
    "out vec4 o;\n"
    "void main() {\n"
    "  vec2 ts = u_a.xy;\n"
    "  vec2 lo = ts * 0.5, hi = u_b.xy;\n"
    "  if (u_a.z > 2.5) {\n"
    "    vec2 p = u_c[0].xy + gl_FragCoord.xy * u_c[0].zw;\n"
    "    p = mb_contained_point(p, u_c[1], u_c[2], u_c[3], u_c[4], u_c[5], u_c[6], u_c[7], u_c[8], u_c[0].z);\n"
    "    o = texture(u_src, clamp((p - u_c[0].xy) / u_c[0].zw * ts, lo, hi));\n"
    "    return;\n"
    "  }\n"
    "  if (u_a.z < 1.5) {\n"
    "    vec2 uv = gl_FragCoord.xy * 2.0 * ts;\n"
    "    vec4 s = texture(u_src, clamp(uv, lo, hi)) * 4.0;\n"
    "    s += texture(u_src, clamp(uv - ts, lo, hi));\n"
    "    s += texture(u_src, clamp(uv + ts, lo, hi));\n"
    "    s += texture(u_src, clamp(uv + vec2(ts.x, -ts.y), lo, hi));\n"
    "    s += texture(u_src, clamp(uv + vec2(-ts.x, ts.y), lo, hi));\n"
    "    o = s / 8.0;\n"
    "    return;\n"
    "  }\n"
    "  vec2 uv = gl_FragCoord.xy * ts;\n"
    "  vec2 dir = u_b.zw * ts;\n"
    "  float sg = u_a.w;\n"
    "  float k = -0.5 / (sg * sg);\n"
    "  vec4 s = texture(u_src, clamp(uv, lo, hi));\n"
    "  float wsum = 1.0;\n"
    "  int n = int(ceil(sg * 3.0));\n"
    "  for (int i = 1; i <= 64; i += 2) {\n"
    "    if (i > n) break;\n"
    "    float w1 = exp(float(i * i) * k), w2 = exp(float((i + 1) * (i + 1)) * k);\n"
    "    float w = w1 + w2;\n"
    "    float off = (float(i) * w1 + float(i + 1) * w2) / w;\n"
    "    s += (texture(u_src, clamp(uv + dir * off, lo, hi)) + texture(u_src, clamp(uv - dir * off, lo, hi))) * w;\n"
    "    wsum += 2.0 * w;\n"
    "  }\n"
    "  o = s / wsum;\n"
    "}\n";

static GLuint prog, vao, vbo, atlas, catlas, post;
static GLint u_vp, u_scale, u_atlas, u_catlas, u_img, u_bd, u_map, u_uvc, u_gb, u_shape, u_rad, u_n, pu_src, pu_a, pu_b, pu_c;
static float *fbuf;
// the pieces of the frame's shapes (src/ui/shape.mbt: the instances of kind 12 after every one drawn), for the shader
// to read (u_segs): a float texture of SEGS_ROW fours a row (136 instances' 15), as many rows as they take
#define SEGS_ROW 2040
static GLint u_segs;
static GLuint segs_tex;
static int segs_rows;
// the pieces segs_tex holds (as they were uploaded): a frame whose pieces are the same (a part drawn again, a mark's
// look moving on) uploads none, the texture the GPU may still be drawing the last frame from not written again
static float *segs_had;
static size_t segs_had_n, segs_had_cap;
static size_t fcap;
static int fb_w, fb_h;
static double cur_w, cur_h, cur_scale;
// what is drawn into: the surface (0), or mbui-render's offscreen framebuffer (mb_render_init_offscreen)
static GLuint target_fb;

static void glass_lost(void);
static void canvas_lost(void);

static GLuint compile(GLenum type, const char *src) {
  GLuint s = glCreateShader(type);
  glShaderSource(s, 1, &src, NULL);
  glCompileShader(s);
  GLint ok = 0;
  glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
  if (!ok) {
    char log[2048];
    glGetShaderInfoLog(s, sizeof log, NULL, log);
    LOG("shader: %s", log);
  }
  return s;
}

// The programs, the instances' buffer and the glyphs' atlases made in the context now current (a new one has none of
// the old: the host makes again what else it had in it).
static void gl_setup(void) {
  prog = glCreateProgram();
  glAttachShader(prog, compile(GL_VERTEX_SHADER, VS));
  glAttachShader(prog, compile(GL_FRAGMENT_SHADER, FS));
  glLinkProgram(prog);
  u_vp = glGetUniformLocation(prog, "u_vp");
  u_scale = glGetUniformLocation(prog, "u_scale");
  u_atlas = glGetUniformLocation(prog, "u_atlas");
  u_catlas = glGetUniformLocation(prog, "u_catlas");
  u_img = glGetUniformLocation(prog, "u_img");
  u_bd = glGetUniformLocation(prog, "u_bd");
  u_map = glGetUniformLocation(prog, "u_map");
  u_uvc = glGetUniformLocation(prog, "u_uvc");
  u_gb = glGetUniformLocation(prog, "u_gb");
  u_shape = glGetUniformLocation(prog, "u_shape");
  u_rad = glGetUniformLocation(prog, "u_rad");
  u_n = glGetUniformLocation(prog, "u_n");
  u_segs = glGetUniformLocation(prog, "u_segs");
  segs_tex = 0;
  segs_rows = 0;
  segs_had_n = 0;
  post = glCreateProgram();
  glAttachShader(post, compile(GL_VERTEX_SHADER, PVS));
  glAttachShader(post, compile(GL_FRAGMENT_SHADER, PFS));
  glLinkProgram(post);
  pu_src = glGetUniformLocation(post, "u_src");
  pu_a = glGetUniformLocation(post, "u_a");
  pu_b = glGetUniformLocation(post, "u_b");
  pu_c = glGetUniformLocation(post, "u_c");
  glass_lost();
  canvas_lost();
  glGenVertexArrays(1, &vao);
  glBindVertexArray(vao);
  glGenBuffers(1, &vbo);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);
  for (int i = 0; i < MB_INST / 4; i++) {
    glEnableVertexAttribArray(i);
    glVertexAttribPointer(i, 4, GL_FLOAT, GL_FALSE, MB_INST * 4, (void *)(intptr_t)(i * 16));
    glVertexAttribDivisor(i, 1);
  }
  // the words' atlas a byte a texel, colour glyphs' four (MB_ATLAS above)
  GLuint *texs[2] = {&atlas, &catlas};
  for (int k = 0; k < 2; k++) {
    glGenTextures(1, texs[k]);
    glBindTexture(GL_TEXTURE_2D, *texs[k]);
    if (k == 0) glTexStorage2D(GL_TEXTURE_2D, 1, GL_R8, MB_ATLAS, MB_ATLAS);
    else glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, MB_ATLAS_COLOR, MB_ATLAS_COLOR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  }
  glEnable(GL_BLEND);
  glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
}

// ---------------------------------------------------------------------------
// Glass (src/ui/glass.mbt): when the instances reach a run of glass (slot 20 negative: the capture it shares), what
// is drawn so far under it (its rects with room for the blur round them) is copied out of the surface, halved down
// to where the blur is a few texels wide (dual Kawase's downsample, at most 1/8), blurred there by a Gaussian of what
// deviation is left, and drawn through. Level j is 1/2^j of the largest capture yet (the glass and the blur's margin
// round it, not the surface: a composer's strip, not the screen), [4] a Gaussian's first half. Level 0, the
// copy, has 8 bits a channel as the surface has; what the passes write keeps 10 (RGB10_A2, in as many bytes): at 8 each
// pass rounds the frost's slow slopes into flat steps, a texel of the last level 8 pixels wide on the screen (a blur
// under 4 pixels, too narrow to halve, is written back into the copy: it leaves no slope that wide).

typedef struct { GLuint t, fb; int w, h; } level;
static level lv[5];
static int lv_w, lv_h;
static GLuint bd_tex;
static float gmap[4], guvc[4], ggb[4], gshape[32], grad[8];
static int gn;
// the app's part of the surface (MBView: the soft keyboard over the rest), in its pixels from the foot
static int vy0, vhp;

// a new context has none of the old textures
static void glass_lost(void) {
  memset(lv, 0, sizeof lv);
  lv_w = lv_h = 0;
}

static level level_tex(GLenum format, int w, int h) {
  level l = {0, 0, w > 0 ? w : 1, h > 0 ? h : 1};
  glGenTextures(1, &l.t);
  glBindTexture(GL_TEXTURE_2D, l.t);
  glTexStorage2D(GL_TEXTURE_2D, 1, format, l.w, l.h);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glGenFramebuffers(1, &l.fb);
  glBindFramebuffer(GL_FRAMEBUFFER, l.fb);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, l.t, 0);
  return l;
}

static void ensure_levels(int w, int h) {
  if (lv[0].t && lv_w >= w && lv_h >= h) return;
  for (int j = 0; j < 5; j++)
    if (lv[j].t) {
      glDeleteTextures(1, &lv[j].t);
      glDeleteFramebuffers(1, &lv[j].fb);
    }
  lv_w = w > lv_w ? w : lv_w;
  lv_h = h > lv_h ? h : lv_h;
  for (int j = 0; j < 4; j++)
    lv[j] = level_tex(j == 0 ? GL_RGBA8 : GL_RGB10_A2, (lv_w + (1 << j) - 1) >> j, (lv_h + (1 << j) - 1) >> j);
  lv[4] = level_tex(GL_RGB10_A2, lv_w, lv_h);
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

static void post_pass(level *src, int sw, int sh, level *dst, int w, int h, int mode, float sg, float dx, float dy) {
  glBindFramebuffer(GL_FRAMEBUFFER, dst->fb);
  glViewport(0, 0, w, h);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, src->t);
  glUniform1i(pu_src, 0);
  glUniform4f(pu_a, 1.0f / src->w, 1.0f / src->h, (float)mode, sg);
  glUniform4f(pu_b, (sw - 0.5f) / src->w, (sh - 0.5f) / src->h, dx, dy);
  glDrawArrays(GL_TRIANGLES, 0, 3);
}

// Partial redraw (docs/partial-redraw.md): the surface's frame is drawn into a canvas of its own (canvas_fb), kept
// across frames, and copied onto the surface (what the surface held is gone once shown); where the app says only some
// parts differ from the frame before (@hostapi.render_dirty), only those parts of the canvas are drawn again, each cut
// to it (the scissor, `cut`: x, y from the foot, w, h; while `cut_on`), the frame's ground over it first (the instance
// after the frame's, gl_present's), then every instance. Without the surface the offscreen framebuffer is the canvas.
static GLuint canvas_fb, canvas_tex;
static int canvas_w, canvas_h, offscreen;
// what the canvas (or the offscreen framebuffer) holds is the last frame given
static int canvas_ok;
// the parts of the next frame that differ (points: x, y, w, h), all of it (`dirty_whole`), and whether any was said
#define MB_PARTS 8
static double dirty[MB_PARTS][4];
static int dirty_n, dirty_whole, dirty_told;
// a picture the frame drawn last had none of yet (drawn without it): the next drawn whole
static int pictures_missing, encode_missing;
static int cut_on;
static int cut[4];

void mb_host_render_dirty(double x, double y, double w, double h) {
  dirty_told = 1;
  if (w < 0 || h < 0) {
    dirty_whole = 1;
  } else if (w > 0 && h > 0) {
    // (more than it keeps: the last one grown round it)
    if (dirty_n == MB_PARTS) {
      double *d = dirty[MB_PARTS - 1];
      double x1 = fmax(d[0] + d[2], x + w), y1 = fmax(d[1] + d[3], y + h);
      d[0] = fmin(d[0], x);
      d[1] = fmin(d[1], y);
      d[2] = x1 - d[0];
      d[3] = y1 - d[1];
    } else {
      double *d = dirty[dirty_n++];
      d[0] = x; d[1] = y; d[2] = w; d[3] = h;
    }
  }
}

// The parts of the frame the next one draws, from what was said of them (taken: a frame nothing was said for is drawn
// whole), into `r` (as `cut`): how many (0 none), -1 all of it. `kept`: the target holds the frame before. In the
// surface's pixels, the app's top the surface's.
static int take_parts(int kept, int r[MB_PARTS][4]) {
  int told = dirty_told, whole = dirty_whole, n = dirty_n;
  dirty_told = dirty_whole = dirty_n = 0;
  if (!told || whole || !kept || pictures_missing) return -1;
  int k = 0;
  for (int i = 0; i < n; i++) {
    // (whole pixels round it, and one more)
    int x0 = (int)floor(dirty[i][0] * cur_scale) - 1, y0 = (int)floor(dirty[i][1] * cur_scale) - 1;
    int x1 = (int)ceil((dirty[i][0] + dirty[i][2]) * cur_scale) + 1;
    int y1 = (int)ceil((dirty[i][1] + dirty[i][3]) * cur_scale) + 1;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > fb_w) x1 = fb_w;
    if (y1 > fb_h) y1 = fb_h;
    if (x1 <= x0 || y1 <= y0) continue;
    r[k][0] = x0;
    r[k][1] = fb_h - y1;
    r[k][2] = x1 - x0;
    r[k][3] = y1 - y0;
    k++;
  }
  return k;
}

static void draw_into(GLuint fb, int part);

// The frame kept drawn into `fb`, only its parts that differ (take_parts) where it holds the frame before (`kept`),
// else whole.
static void draw_parts(GLuint fb, int kept) {
  int parts[MB_PARTS][4];
  int n = take_parts(kept, parts);
  int missing = 0;
  if (n < 0) {
    draw_into(fb, 0);
    missing = encode_missing;
  }
  for (int i = 0; i < n; i++) {
    memcpy(cut, parts[i], sizeof cut);
    draw_into(fb, 1);
    missing |= encode_missing;
  }
  if (n != 0) pictures_missing = missing;
}

// The canvas gone with the context it was made in (a new one: gl_setup), nothing of it given back.
static void canvas_lost(void) {
  canvas_fb = canvas_tex = 0;
  canvas_w = canvas_h = 0;
  canvas_ok = 0;
}

// The canvas the surface's frames are drawn into, its size: made again at another size (or once the context is new:
// gl_setup), what it held lost.
static void ensure_canvas(void) {
  if (canvas_fb && canvas_w == fb_w && canvas_h == fb_h) return;
  if (canvas_fb) {
    glDeleteFramebuffers(1, &canvas_fb);
    glDeleteTextures(1, &canvas_tex);
  }
  canvas_fb = canvas_tex = 0;
  canvas_ok = 0;
  canvas_w = fb_w;
  canvas_h = fb_h;
  if (fb_w <= 0 || fb_h <= 0) return;
  glGenTextures(1, &canvas_tex);
  glBindTexture(GL_TEXTURE_2D, canvas_tex);
  glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, fb_w, fb_h);
  glGenFramebuffers(1, &canvas_fb);
  glBindFramebuffer(GL_FRAMEBUFFER, canvas_fb);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, canvas_tex, 0);
  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    glDeleteFramebuffers(1, &canvas_fb);
    glDeleteTextures(1, &canvas_tex);
    canvas_fb = canvas_tex = 0;
  }
}

// what the run [start, end) of glass sees, frosted glass of the same capture further on (glass.mbt shares_capture)
// too; 0 when none of it shows
static int capture(const float *f, int32_t start, int32_t end, int32_t count) {
  const float *a = f + start * MB_INST;
  // A negative blur is contained: its straight edges are the capture's edges, its curved ones extended separately.
  float blur = fabsf(a[7]);
  int kind = (int)(a[5] + 0.5f);
  float margin = a[7] < 0.0f ? 0.0f : 3.0f * blur + (kind == 6 ? a[21] * (1.0f + a[22]) + a[23] : 0.0f) + 2.0f;
  float x0 = 1e9f, y0 = 1e9f, x1 = -1e9f, y1 = -1e9f;
  gn = 0;
  for (int32_t i = start; i < end; i++) {
    const float *b = f + i * MB_INST;
    float bx0 = b[0] > b[16] ? b[0] : b[16], by0 = b[1] > b[17] ? b[1] : b[17];
    float bx1 = b[0] + b[2] < b[18] ? b[0] + b[2] : b[18], by1 = b[1] + b[3] < b[19] ? b[1] + b[3] : b[19];
    if (kind == 6) {
      bx0 = b[0] - a[23]; by0 = b[1] - a[23]; bx1 = b[0] + b[2] + a[23]; by1 = b[1] + b[3] + a[23];
      if (gn < 8) {
        for (int k = 0; k < 4; k++) gshape[gn * 4 + k] = b[k];
        grad[gn] = b[4];
        gn++;
      }
    }
    if (bx0 < x0) x0 = bx0;
    if (by0 < y0) y0 = by0;
    if (bx1 > x1) x1 = bx1;
    if (by1 > y1) y1 = by1;
  }
  for (int32_t i = end; kind == 5 && i < count; i++) {
    const float *b = f + i * MB_INST;
    if (b[20] != a[20]) continue;
    float bx0 = b[0] > b[16] ? b[0] : b[16], by0 = b[1] > b[17] ? b[1] : b[17];
    float bx1 = b[0] + b[2] < b[18] ? b[0] + b[2] : b[18], by1 = b[1] + b[3] < b[19] ? b[1] + b[3] : b[19];
    if (bx0 < x0) x0 = bx0;
    if (by0 < y0) y0 = by0;
    if (bx1 > x1) x1 = bx1;
    if (by1 > y1) y1 = by1;
  }
  ggb[0] = x0 - 2; ggb[1] = y0 - 2; ggb[2] = x1 + 2; ggb[3] = y1 + 2;
  float sc = (float)cur_scale;
  // in the surface's pixels, from its foot (GL's way up)
  int top = vy0 + vhp;
  int px0 = (int)floorf((x0 - margin) * sc), px1 = (int)ceilf((x1 + margin) * sc);
  int pb0 = top - (int)ceilf((y1 + margin) * sc), pb1 = top - (int)floorf((y0 - margin) * sc);
  if (px0 < 0) px0 = 0;
  if (px1 > fb_w) px1 = fb_w;
  if (pb0 < vy0) pb0 = vy0;
  if (pb1 > top) pb1 = top;
  if (px1 <= px0 || pb1 <= pb0 || x1 <= x0 || y1 <= y0) return 0;
  // (a capture outside the part drawn: neither copied nor drawn. One that meets it is in it whole: @damage)
  if (cut_on && (px1 <= cut[0] || cut[0] + cut[2] <= px0 || pb1 <= cut[1] || cut[1] + cut[3] <= pb0)) return 0;
  int w = px1 - px0, h = pb1 - pb0;
  ensure_levels(w, h);
  glDisable(GL_BLEND);
  // (the copy and the passes whole, not cut to the part: a blit is cut by the scissor too)
  glDisable(GL_SCISSOR_TEST);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, target_fb);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, lv[0].fb);
  glBlitFramebuffer(px0, pb0, px1, pb1, 0, 0, w, h, GL_COLOR_BUFFER_BIT, GL_NEAREST);
  glUseProgram(post);
  MBContained edge;
  int contained = mb_contained_make(&edge, a, px0 / sc, (top - pb0) / sc, 1.0f / sc, -1.0f / sc);
  if (contained) {
    glUniform4fv(pu_c, 9, (const float *)&edge);
    post_pass(&lv[0], w, h, &lv[4], w, h, 3, 0, 0, 0);
  }
  float sp = blur * sc;
  int k = 0;
  while (k < 3 && sp / (float)(1 << (k + 1)) >= 2.0f) k++;
  int lw[4] = {w}, lh[4] = {h};
  for (int j = 1; j <= k; j++) {
    lw[j] = (lw[j - 1] + 1) / 2;
    lh[j] = (lh[j - 1] + 1) / 2;
    post_pass(j == 1 && contained ? &lv[4] : &lv[j - 1], lw[j - 1], lh[j - 1], &lv[j], lw[j], lh[j], 1, 0, 0, 0);
  }
  // what is left of the deviation once the halvings' and the last look's (bilinear) spread are taken out
  float sk = sp / (float)(1 << k);
  float pre = k > 0 ? 0.75f * (1.0f - powf(0.25f, (float)k)) / 3.0f + 1.0f / 6.0f : 0.0f;
  float sg = sqrtf(sk * sk - pre > 0 ? sk * sk - pre : 0);
  if (sg > 0.3f) {
    level *from = contained && k == 0 ? &lv[4] : &lv[k];
    level *tmp = contained && k == 0 ? &lv[0] : &lv[4];
    post_pass(from, lw[k], lh[k], tmp, lw[k], lh[k], 2, sg, 1, 0);
    post_pass(tmp, lw[k], lh[k], from, lw[k], lh[k], 2, sg, 0, 1);
  }
  level *L = contained && k == 0 ? &lv[4] : &lv[k];
  float d = (float)(1 << k);
  bd_tex = L->t;
  gmap[0] = sc / d / L->w; gmap[1] = -sc / d / L->h;
  gmap[2] = -(float)px0 / d / L->w; gmap[3] = (float)(top - pb0) / d / L->h;
  guvc[0] = 0.5f / L->w; guvc[1] = 0.5f / L->h; guvc[2] = (lw[k] - 0.5f) / L->w; guvc[3] = (lh[k] - 0.5f) / L->h;
  return 1;
}

// the main program's state (after the passes)
static void main_state(void) {
  glBindFramebuffer(GL_FRAMEBUFFER, target_fb);
  glViewport(0, vy0, fb_w, vhp);
  if (cut_on) {
    glEnable(GL_SCISSOR_TEST);
    glScissor(cut[0], cut[1], cut[2], cut[3]);
  } else {
    glDisable(GL_SCISSOR_TEST);
  }
  glEnable(GL_BLEND);
  glUseProgram(prog);
  glBindVertexArray(vao);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);
  glUniform2f(u_vp, (float)cur_w, (float)cur_h);
  glUniform1f(u_scale, (float)cur_scale);
  glActiveTexture(GL_TEXTURE4);
  glBindTexture(GL_TEXTURE_2D, catlas);
  glUniform1i(u_catlas, 4);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, atlas);
  glUniform1i(u_atlas, 0);
  glUniform1i(u_img, 1);
  // (the shapes' pieces before the backdrop: the unit left active as it was, 2, which a stream's SurfaceTexture is
  // latched on as its picture is asked for: Streams.show)
  glActiveTexture(GL_TEXTURE3);
  glBindTexture(GL_TEXTURE_2D, segs_tex ? segs_tex : atlas);
  glUniform1i(u_segs, 3);
  glActiveTexture(GL_TEXTURE2);
  glBindTexture(GL_TEXTURE_2D, bd_tex ? bd_tex : atlas);
  glUniform1i(u_bd, 2);
  glUniform4fv(u_map, 1, gmap);
  glUniform4fv(u_uvc, 1, guvc);
  glUniform4fv(u_gb, 1, ggb);
  glUniform4fv(u_shape, 8, gshape);
  glUniform4fv(u_rad, 2, grad);
  glUniform1i(u_n, gn);
}

// What the app does not paint left clear, what is under the surface showing (Android's over another app: OverActivity,
// Native.overOther).
static volatile int over_other;

// The pieces of the frame's shapes (src/ui/shape.mbt: the instances of kind 12 after every one drawn) into segs_tex.

static void segs_upload(int32_t count) {
  int32_t d = count;
  while (d > 0 && (int)(fbuf[(d - 1) * MB_INST + 5] + 0.5f) == 12) d--;
  if (d == count) return;
  int rows = (int)(((size_t)(count - d) * (MB_INST / 4) + SEGS_ROW - 1) / SEGS_ROW);
  const float *pieces = fbuf + (size_t)d * MB_INST;
  size_t n = (size_t)(count - d) * MB_INST;
  // (the same as the texture holds: nothing to upload)
  if (segs_tex && rows <= segs_rows && n == segs_had_n && memcmp(segs_had, pieces, n * sizeof(float)) == 0) return;
  if (n > segs_had_cap) {
    segs_had_cap = n * 2;
    segs_had = realloc(segs_had, segs_had_cap * sizeof(float));
  }
  memcpy(segs_had, pieces, n * sizeof(float));
  segs_had_n = n;
  glActiveTexture(GL_TEXTURE3);
  if (!segs_tex || rows > segs_rows) {
    if (segs_tex) glDeleteTextures(1, &segs_tex);
    glGenTextures(1, &segs_tex);
    glBindTexture(GL_TEXTURE_2D, segs_tex);
    segs_rows = rows * 2;
    glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA32F, SEGS_ROW, segs_rows);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  }
  glBindTexture(GL_TEXTURE_2D, segs_tex);
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, SEGS_ROW, rows, GL_RGBA, GL_FLOAT, fbuf + (size_t)d * MB_INST);
}

// The frame presented last, kept (in fbuf): its instances and its ground, drawn again as a native view's picture
// changes (Android's Native.redraw), the app not asked.
static int32_t kept_count;
static double kept_r, kept_g, kept_b;
static void draw_kept(void);

static void canvas_shown(void);

// Whether the frame kept draws a native view's picture into the canvas (Android's views, Linux's players): what it
// shows changes under the same instances, so the frame is drawn whole.
static int views_drawn_in(void) {
  for (int32_t i = 0; i < kept_count; i++) {
    int tid = (int)fbuf[i * MB_INST + 20];
    if (tid <= MB_VIEW_TEX) continue;
#ifdef MB_VIEWS_UNDER
    if (view_under(tid)) continue;
#endif
    return 1;
  }
  return 0;
}

// A frame presented (the host's mb_host_present, its glyphs in the atlases first): kept, and drawn into the canvas,
// only the part that differs where it holds the frame before, then onto target_fb.
static void gl_present(double *buf, int32_t count, double r, double g, double b) {
  size_t n = (size_t)(count > 0 ? count : 0) * MB_INST;
  // (and the frame's ground after it, and a row of the shapes' pieces more: segs_upload reads whole rows)
  if (fcap < n + MB_INST + SEGS_ROW * 4) {
    fcap = n * 2 + MB_INST + SEGS_ROW * 4;
    fbuf = realloc(fbuf, fcap * sizeof(float));
  }
  for (size_t i = 0; i < n; i++) fbuf[i] = (float)buf[i];
  kept_count = count;
  kept_r = r;
  kept_g = g;
  kept_b = b;
  if (views_drawn_in()) dirty_told = 0;
  if (offscreen) {
    draw_parts(target_fb, canvas_ok);
    canvas_ok = 1;
    return;
  }
  ensure_canvas();
  if (!canvas_fb) {
    dirty_told = dirty_whole = dirty_n = 0;
    draw_into(target_fb, 0);
    return;
  }
  draw_parts(canvas_fb, canvas_ok);
  canvas_ok = 1;
  canvas_shown();
}

// The canvas onto the surface (target_fb), whole.
static void canvas_shown(void) {
  glDisable(GL_SCISSOR_TEST);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, canvas_fb);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, target_fb);
  glBlitFramebuffer(0, 0, fb_w, fb_h, 0, 0, fb_w, fb_h, GL_COLOR_BUFFER_BIT, GL_NEAREST);
  glBindFramebuffer(GL_FRAMEBUFFER, target_fb);
}

// The frame presented last, drawn again into a framebuffer of its own the surface's size (as on the surface: what the
// surface holds is gone once it is shown): read_fb, bound as it returns.
static GLuint read_fb, read_tex;
static int read_w, read_h;

static void draw_kept_read(void) {
  if (!read_fb || read_w != fb_w || read_h != fb_h) {
    if (read_fb) {
      glDeleteFramebuffers(1, &read_fb);
      glDeleteTextures(1, &read_tex);
    }
    glGenTextures(1, &read_tex);
    glBindTexture(GL_TEXTURE_2D, read_tex);
    glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, fb_w, fb_h);
    glGenFramebuffers(1, &read_fb);
    glBindFramebuffer(GL_FRAMEBUFFER, read_fb);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, read_tex, 0);
    read_w = fb_w;
    read_h = fb_h;
  }
  draw_into(read_fb, 0);
  glBindFramebuffer(GL_FRAMEBUFFER, read_fb);
}

// That frame's pixels in the rectangle x, y, w × h (from the top left) into `out` as RGBA, premultiplied, rows from
// the top (host_native.mbt drawn_pixels; on the thread MoonBit runs on, its context current): 1 when read, 0 where the
// rectangle is not all in the frame.
int32_t mb_render_drawn_pixels(int32_t x, int32_t y, int32_t w, int32_t h, moonbit_bytes_t out) {
  if (kept_count <= 0 || fb_w <= 0 || fb_h <= 0 || w <= 0 || h <= 0 || x < 0 || y < 0 || x + w > fb_w || y + h > fb_h)
    return 0;
  if ((size_t)Moonbit_array_length(out) < (size_t)w * h * 4) return 0;
  GLuint was = target_fb;
  draw_kept_read();
  size_t row = (size_t)w * 4;
  unsigned char *px = malloc(row * h);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, read_fb);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  // (GL's rows from the foot: the app's top is the surface's)
  glReadPixels(x, fb_h - y - h, w, h, GL_RGBA, GL_UNSIGNED_BYTE, px);
  for (int r = 0; r < h; r++) memcpy(out + row * r, px + row * (h - 1 - r), row);
  free(px);
  glBindFramebuffer(GL_FRAMEBUFFER, was);
  return 1;
}

// Instances never presented (a shot's, mbui/src/ui/shot.mbt) drawn as a frame is, but `scale` pixels a point into a
// picture of their own w × h (their 0, 0 its top left), on the ground r, g, b, and its pixels into `out` as
// mb_render_drawn_pixels gives the frame's: the frame kept, and the size frames are drawn at, set aside while they are
// drawn in its place, then put back (what a native view's picture redraws is the frame as it was). 1 when read.
int32_t mb_render_pixels_of(const double *inst, int32_t count, double r, double g, double b, double scale, int32_t w,
                            int32_t h, moonbit_bytes_t out) {
  if (count <= 0 || !(scale > 0) || w <= 0 || h <= 0) return 0;
  float *kf = fbuf;
  size_t kc = fcap;
  int32_t kn = kept_count;
  double kr = kept_r, kg = kept_g, kb = kept_b;
  int kfw = fb_w, kfh = fb_h;
  double kw = cur_w, kh = cur_h, ks = cur_scale;
  size_t n = (size_t)count * MB_INST;
  // (a row of the shapes' pieces more: segs_upload reads whole rows)
  fcap = n + SEGS_ROW * 4;
  fbuf = malloc(fcap * sizeof(float));
  for (size_t i = 0; i < n; i++) fbuf[i] = (float)inst[i];
  kept_count = count;
  kept_r = r;
  kept_g = g;
  kept_b = b;
  fb_w = w;
  fb_h = h;
  cur_scale = scale;
  cur_w = w / scale;
  cur_h = h / scale;
  int32_t ok = mb_render_drawn_pixels(0, 0, w, h, out);
  free(fbuf);
  fbuf = kf;
  fcap = kc;
  kept_count = kn;
  kept_r = kr;
  kept_g = kg;
  kept_b = kb;
  fb_w = kfw;
  fb_h = kfh;
  cur_w = kw;
  cur_h = kh;
  cur_scale = ks;
  return ok;
}

// The frame kept drawn whole onto the surface again (a native view's picture changed: Android's Native.redraw), through
// the canvas as a frame presented is.
static void draw_kept(void) {
  if (offscreen || !canvas_fb) {
    draw_into(target_fb, 0);
    return;
  }
  draw_into(canvas_fb, 0);
  canvas_ok = 1;
  canvas_shown();
}

// The frame kept drawn into framebuffer `fb` (the surface's size): `part` 1, only the part `cut` over what it holds
// (the frame's ground there first), else all of it, cleared to the ground. Whether a picture was missing in
// encode_missing.
static void draw_into(GLuint fb, int part) {
  int32_t count = kept_count;
  double r = kept_r, g = kept_g, b = kept_b;
  GLuint was = target_fb;
  target_fb = fb;
  encode_missing = 0;
  cut_on = part == 1;
  glBindFramebuffer(GL_FRAMEBUFFER, target_fb);
  glViewport(0, 0, fb_w, fb_h);
  if (!cut_on) {
    glDisable(GL_SCISSOR_TEST);
    if (over_other) glClearColor(0, 0, 0, 0);
    else glClearColor((float)r, (float)g, (float)b, 1);
    glClear(GL_COLOR_BUFFER_BIT);
  }
  // the app drawn in the surface's top part, as tall as it was told (the soft keyboard over the rest: MBView)
  int vh = (int)(cur_h * cur_scale + 0.5);
  vy0 = 0;
  vhp = fb_h;
  if (vh > 0 && vh < fb_h) {
    vy0 = fb_h - vh;
    vhp = vh;
  }
  glViewport(0, vy0, fb_w, vhp);
  if (count <= 0 && !cut_on) {
    target_fb = was;
    return;
  }
  size_t n = (size_t)count * MB_INST;
  // the frame's ground after its instances: a rect over all the window, opaque (clear over another app), a part drawn
  // again first
  float *gr = fbuf + n;
  memset(gr, 0, MB_INST * sizeof(float));
  gr[0] = -16.0f; gr[1] = -16.0f; gr[2] = (float)cur_w + 32.0f; gr[3] = (float)cur_h + 32.0f;
  if (!over_other) {
    gr[8] = (float)r; gr[9] = (float)g; gr[10] = (float)b; gr[11] = 1.0f;
  }
  gr[16] = -1e9f; gr[17] = -1e9f; gr[18] = 1e9f; gr[19] = 1e9f;
  segs_upload(count);
  bd_tex = 0;
  memset(gmap, 0, sizeof gmap);
  memset(guvc, 0, sizeof guvc);
  memset(ggb, 0, sizeof ggb);
  gn = 0;
  glUseProgram(prog);
  glBindVertexArray(vao);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);
  glBufferData(GL_ARRAY_BUFFER, (n + MB_INST) * sizeof(float), fbuf, GL_STREAM_DRAW);
  main_state();
  if (cut_on) {
    for (int i = 0; i < MB_INST / 4; i++)
      glVertexAttribPointer(i, 4, GL_FLOAT, GL_FALSE, MB_INST * 4, (void *)(intptr_t)(count * MB_INST * 4 + i * 16));
    glDisable(GL_BLEND);
    glDrawArraysInstanced(GL_TRIANGLES, 0, 6, 1);
    glEnable(GL_BLEND);
  }
  // one draw per run of instances showing the same image (slot 20; 0: none, the atlas stands in; a native view's
  // picture where it shows, kind 9: nothing until it has one), or sharing one capture of glass (negative); GLES has no
  // base instance, so the attributes start at the run instead
  int32_t start = 0;
  int bound = 0, shows = 0;
  while (start < count) {
    int tid = (int)fbuf[start * MB_INST + 20];
    int32_t end = start + 1;
    while (end < count && (int)fbuf[end * MB_INST + 20] == tid) end++;
    if (tid < 0) {
      if (tid != bound) {
        shows = capture(fbuf, start, end, count);
        bound = tid;
        main_state();
      }
      if (shows) {
        for (int i = 0; i < MB_INST / 4; i++)
          glVertexAttribPointer(i, 4, GL_FLOAT, GL_FALSE, MB_INST * 4, (void *)(intptr_t)(start * MB_INST * 4 + i * 16));
        // liquid: the group as one shape, drawn once
        glDrawArraysInstanced(GL_TRIANGLES, 0, 6, (int)(fbuf[start * MB_INST + 5] + 0.5f) == 6 ? 1 : end - start);
      }
      start = end;
      continue;
    }
    GLuint t = tid ? image_tex(tid) : atlas;
    if (!t && tid > 0 && tid <= MB_STREAM_TEX) encode_missing = 1;
    if (t) {  // 0: lost with the context, decoding again; a stream's or a view's with no picture yet
      if (tid > MB_VIEW_TEX) view_parts_in(tid, start, end);
      glActiveTexture(GL_TEXTURE1);
      glBindTexture(GL_TEXTURE_2D, t);
      for (int i = 0; i < MB_INST / 4; i++)
        glVertexAttribPointer(i, 4, GL_FLOAT, GL_FALSE, MB_INST * 4, (void *)(intptr_t)(start * MB_INST * 4 + i * 16));
#ifdef MB_VIEWS_UNDER
      // (a view under the surface: its picture a white texel, so what kind 9 draws is how much of each pixel it covers,
      // and that much of the canvas is taken away there: a hole the view shows through, its round edge as soft as a
      // drawn one's; what is drawn after it draws over it)
      int under = tid > MB_VIEW_TEX && view_under(tid);
      if (under) glBlendFunc(GL_ZERO, GL_ONE_MINUS_SRC_ALPHA);
#endif
      glDrawArraysInstanced(GL_TRIANGLES, 0, 6, end - start);
#ifdef MB_VIEWS_UNDER
      if (under) glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
#endif
    }
    start = end;
  }
  if (cut_on) glDisable(GL_SCISSOR_TEST);
  cut_on = 0;
  target_fb = was;
}

// ---------------------------------------------------------------------------
// Without the surface (mbui-render, src/render: a frame drawn as on the surface, read back as a PNG): a framebuffer of
// its own the size the surface would be, drawn into.

static GLuint off_tex;

static void gl_offscreen(double w, double h, double scale) {
  offscreen = 1;
  cur_w = w;
  cur_h = h;
  cur_scale = scale;
  fb_w = (int)floor(w * scale + 0.5);
  fb_h = (int)floor(h * scale + 0.5);
  glGenTextures(1, &off_tex);
  glBindTexture(GL_TEXTURE_2D, off_tex);
  glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, fb_w, fb_h);
  glGenFramebuffers(1, &target_fb);
  glBindFramebuffer(GL_FRAMEBUFFER, target_fb);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, off_tex, 0);
  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) LOG("mbui-render: no framebuffer");
}

// The offscreen framebuffer as its frames left it (not the last frame drawn again: what drawing only the parts that
// differ made of it, mbui-render's MBUI_DL_FROM), as a PNG.
static int gl_png(const char *path, GLuint fb);

int mb_render_snapshot_drawn(const char *path) { return offscreen && target_fb ? gl_png(path, target_fb) : 0; }

static void png_chunk(FILE *f, const char *type, const unsigned char *data, uint32_t n) {
  unsigned char be[4] = {n >> 24, n >> 16, n >> 8, n};
  fwrite(be, 1, 4, f);
  fwrite(type, 1, 4, f);
  if (n) fwrite(data, 1, n, f);
  uLong c = crc32(0, (const Bytef *)type, 4);
  if (n) c = crc32(c, data, n);
  unsigned char cb[4] = {c >> 24, c >> 16, c >> 8, c};
  fwrite(cb, 1, 4, f);
}

// What framebuffer `fb` holds (the surface's size) as a PNG (8-bit RGBA, top row first, zlib's level 6): 1 when
// written.
static int gl_png(const char *path, GLuint fb) {
  if (fb_w <= 0 || fb_h <= 0) return 0;
  size_t row = (size_t)fb_w * 4;
  unsigned char *px = malloc(row * fb_h), *raw = malloc((row + 1) * fb_h);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, fb);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glReadPixels(0, 0, fb_w, fb_h, GL_RGBA, GL_UNSIGNED_BYTE, px);
  // GL's rows are from the foot up
  for (int y = 0; y < fb_h; y++) {
    raw[(row + 1) * y] = 0;
    memcpy(raw + (row + 1) * y + 1, px + row * (fb_h - 1 - y), row);
  }
  uLongf zn = compressBound((uLong)((row + 1) * fb_h));
  unsigned char *z = malloc(zn);
  int ok = compress2(z, &zn, raw, (uLong)((row + 1) * fb_h), 6) == Z_OK;
  FILE *f = ok ? fopen(path, "wb") : NULL;
  if (f) {
    static const unsigned char sig[8] = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'};
    unsigned char ihdr[13] = {fb_w >> 24, fb_w >> 16, fb_w >> 8, fb_w, fb_h >> 24, fb_h >> 16, fb_h >> 8, fb_h,
                              8, 6, 0, 0, 0};
    fwrite(sig, 1, 8, f);
    png_chunk(f, "IHDR", ihdr, 13);
    png_chunk(f, "IDAT", z, (uint32_t)zn);
    png_chunk(f, "IEND", NULL, 0);
    ok = fclose(f) == 0;
  } else {
    ok = 0;
  }
  free(z);
  free(raw);
  free(px);
  return ok;
}
