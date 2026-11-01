// Metal renderer: one pipeline, one instanced quad per scene instance.
#import "apple.h"
#include "corner_sl.h"
#include "contained.h"
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>

// the numbers of an instance (src/ui/scene.mbt)
#define MB_INST 60

static id<MTLDevice> dev;
static id<MTLCommandQueue> queue;
static id<MTLRenderPipelineState> mpipe;
static id<MTLRenderPipelineState> rpipe_off;
// holes for native views (kind 9): written, not blended
static id<MTLRenderPipelineState> hpipe;
// the words' glyphs (R8) and colour glyphs (RGBA), square (apple.h)
static id<MTLTexture> atlas, catlas;
static CAMetalLayer *mlayer;
static id<MTLBuffer> bufs[3];
static size_t buf_cap[3];
static int buf_i;
static dispatch_semaphore_t inflight;
static double vw = 800, vh = 600, vscale = 2;
// the last frame, kept for snapshots
static float *last_inst;
static int32_t last_count;
static size_t last_cap;
static double last_bg[3];
// glass (src/ui/glass.mbt): the passes that blur what is under it (into the copy, 8 bits a channel, and into the rest,
// half floats), the copies they work in (level j is 1/2^j of the largest capture yet, the glass and the blur's margin
// round it, not of the target: a composer's strip, not the window; tmp for a Gaussian's first half), the GPU's time of
// the last frame done
static id<MTLRenderPipelineState> ppipe, ppipe_deep;
static id<MTLTexture> lv[4], ltmp;
static int lv_w, lv_h;
static double last_gpu = -1;

static NSString *shader_src = @
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"// scene.mbt's 60 numbers: clip, rc and rs the rounded rect it is cut to (its rect x0 y0 x1 y1, its corners' radii,\n"
"// how smooth they are); rot how it is turned (radians, about rot.yz; its clip where it is drawn when rot.w is 1); rr\n"
"// a box's corners' radii (top left, top right, bottom right, bottom left); oclip, orc, ors the rounded clip outside\n"
"// its own that its own cuts through, as clip, rc, rs (none where orc is 0); fade where it fades out towards a cut\n"
"// (from its top: 0 at x, whole y below it; from its foot: 0 at z, whole w above it; none where y, w are 0), fadex\n"
"// the same across (from its left, from its right)\n"
"struct Inst { float4 rect; float4 p; float4 color; float4 c2; float4 clip; float4 pad; float4 rc; float4 rs; float4 rot; float4 rr; float4 oclip; float4 orc; float4 ors; float4 fade; float4 fadex; };\n"
"struct U { float2 vp; float scale; float pad; };\n"
"// glass: where a point's backdrop is in the blurred copy (uv = p * map.xy + map.zw, kept in uvc), a liquid group's\n"
"// bounds, shapes and corners, how many (misc.x); misc.y 1 where what it copied of a native view's hole is let through\n"
"// (glass_through)\n"
"struct G { float4 map; float4 uvc; float4 gb; float4 shape[8]; float4 rad[2]; float4 misc; };\n"
"struct VOut { float4 pos [[position]]; float2 p; float2 cp; uint iid [[flat]]; };\n"
"vertex VOut vmain(uint vid [[vertex_id]], uint iid [[instance_id]],\n"
"    const device Inst* inst [[buffer(0)]], constant U& u [[buffer(1)]], constant G& g [[buffer(2)]]) {\n"
"  Inst I = inst[iid];\n"
"  float2 corner = float2((vid == 1 || vid == 4 || vid == 5) ? 1.0 : 0.0,\n"
"                         (vid == 2 || vid == 3 || vid == 5) ? 1.0 : 0.0);\n"
"  int kind = int(I.p.y + 0.5);\n"
"  float grow = kind == 2 ? I.p.w * 3.0 + 2.0 : ((kind == 0 || kind == 4 || kind == 5) ? 1.0 : 0.0);\n"
"  float2 pos = I.rect.xy - grow + corner * (I.rect.zw + 2.0 * grow);\n"
"  if (kind == 6) pos = mix(g.gb.xy, g.gb.zw, corner);\n"
"  // the pieces of shapes (kind 12): nothing drawn\n"
"  if (kind == 12) pos = float2(0.0, 0.0);\n"
"  // turned (scene.mbt 32-35): drawn turned about its point, everything of how in its own place (o.p), its clip there\n"
"  // too or (35: one from outside what turned) where it is drawn (o.cp)\n"
"  float2 at = pos;\n"
"  if (I.rot.x != 0.0) { float2 d = pos - I.rot.yz; float c = cos(I.rot.x), s = sin(I.rot.x); at = I.rot.yz + float2(c * d.x - s * d.y, s * d.x + c * d.y); }\n"
"  VOut o;\n"
"  o.pos = float4(at.x / u.vp.x * 2.0 - 1.0, 1.0 - at.y / u.vp.y * 2.0, 0.0, 1.0);\n"
"  o.p = pos; o.cp = I.rot.w > 0.5 ? at : pos; o.iid = iid;\n"
"  return o;\n"
"}\n"
MB_CORNER_SL
"static float sd_rr(float2 p, float4 r, float4 rad) {\n"
"  float2 hs = r.zw * 0.5;\n"
"  return mb_sd_box(p - r.xy - hs, hs, mb_corner_of(p - r.xy - hs, rad), 1e9);\n"
"}\n"
"// a notch cut into the top edge (scene.mbt 21-23): a circle about the top's middle (pad.y below it, pad.z its radius),\n"
"// met by the edge through fillets (pad.w): the rounded intersection with what is outside the circle\n"
"static float notch_cut(float d, float2 p, float4 r, float4 pad) {\n"
"  if (pad.z <= 0.0) return d;\n"
"  float b = pad.z - length(p - float2(r.x + r.z * 0.5, r.y + pad.y));\n"
"  float f = max(pad.w, 0.0);\n"
"  float2 u = max(float2(f + d, f + b), 0.0);\n"
"  return min(-f, max(d, b)) + length(u);\n"
"}\n"
"static float smin_k(float a, float b, float k) {\n"
"  if (k <= 0.0) return min(a, b);\n"
"  float h = max(k - abs(a - b), 0.0) / k;\n"
"  return min(a, b) - h * h * k * 0.25;\n"
"}\n"
"static float sd_group(float2 p, constant G& g, float k) {\n"
"  float d = 1e9;\n"
"  int n = int(g.misc.x + 0.5);\n"
"  for (int i = 0; i < 8; i++) {\n"
"    if (i >= n) break;\n"
"    d = smin_k(d, sd_rr(p, g.shape[i], float4(g.rad[i / 4][i % 4])), k);\n"
"  }\n"
"  return d;\n"
"}\n"
"static float4 backdrop4(texture2d<float> bd, constant G& g, float2 p) {\n"
"  constexpr sampler s(filter::linear, address::clamp_to_edge);\n"
"  float2 uv = clamp(p * g.map.xy + g.map.zw, g.uvc.xy, g.uvc.zw);\n"
"  return bd.sample(s, uv);\n"
"}\n"
"static float3 backdrop(texture2d<float> bd, constant G& g, float2 p) { return backdrop4(bd, g, p).rgb; }\n"
"static float luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }\n"
"// how much of the pixel at p its rounded clip keeps (r: the corners' radii, top left, then clockwise; s: how smooth\n"
"// each is), its edge covered as a box's own (0.5 - d * scale), so what it cuts meets the ground of the box that cuts it\n"
"static float clip_cover(float2 p, float4 c, float4 r, float4 s, float scale) {\n"
"  float d = mb_sd_clip(p, c, r, s, 1.0 + 2.0 / scale);\n"
"  return clamp(0.5 - d * scale, 0.0, 1.0);\n"
"}\n"
"fragment float4 fmain(VOut in [[stage_in]], const device Inst* inst [[buffer(0)]],\n"
"    constant U& u [[buffer(1)]], constant G& g [[buffer(2)]], texture2d<float> atlas [[texture(0)]],\n"
"    texture2d<float> img [[texture(1)]], texture2d<float> bd [[texture(2)]], texture2d<float> catlas [[texture(3)]]) {\n"
"  Inst I = inst[in.iid];\n"
"  float2 p = in.p, cp = in.cp;\n"
"  // cut to its clip: a rect's, hard; a rounded one's, covered as edges are\n"
"  float cover = 1.0;\n"
"  if (max(max(I.rc.x, I.rc.y), max(I.rc.z, I.rc.w)) > 0.0) {\n"
"    cover = clip_cover(cp, I.clip, I.rc, I.rs, u.scale);\n"
"    if (cover <= 0.0) discard_fragment();\n"
"  } else if (cp.x < I.clip.x || cp.y < I.clip.y || cp.x > I.clip.z || cp.y > I.clip.w) discard_fragment();\n"
"  // and by the clip outside it, where it has one (a pane round an image's frame in its corner)\n"
"  if (max(max(I.orc.x, I.orc.y), max(I.orc.z, I.orc.w)) > 0.0) {\n"
"    cover *= clip_cover(cp, I.oclip, I.orc, I.ors, u.scale);\n"
"    if (cover <= 0.0) discard_fragment();\n"
"  }\n"
"  // and faded out towards a cut, each pixel by where it is (scene.mbt 52-59)\n"
"  if (I.fade.y > 0.0) cover *= clamp((cp.y - I.fade.x) / I.fade.y, 0.0, 1.0);\n"
"  if (I.fade.w > 0.0) cover *= clamp((I.fade.z - cp.y) / I.fade.w, 0.0, 1.0);\n"
"  if (I.fadex.y > 0.0) cover *= clamp((cp.x - I.fadex.x) / I.fadex.y, 0.0, 1.0);\n"
"  if (I.fadex.w > 0.0) cover *= clamp((I.fadex.z - cp.x) / I.fadex.w, 0.0, 1.0);\n"
"  if (cover <= 0.0) discard_fragment();\n"
"  int kind = int(I.p.y + 0.5);\n"
"  float4 col = I.color;\n"
"  if (kind == 1 || kind == 3 || kind == 7) {\n"
"    constexpr sampler s(filter::linear, coord::pixel);\n"
"    // within its own cell (c2: where in the atlas, in texels; a colour glyph's MB_ATLAS_COLOR_U across past its place\n"
"    // in theirs), however its rect is stretched or turned: a sample past the cell's edge texels would blend in what\n"
"    // lies beside it (another glyph, one left from before the atlas started over). The words' atlas has a glyph's\n"
"    // cover alone: white, premultiplied, as the colour one would have it.\n"
"    bool colour = I.c2.x >= 16384.0;\n"
"    float2 at = float2(I.c2.x - (colour ? 16384.0 : 0.0), I.c2.y);\n"
"    float2 uv = clamp(at + (p - I.rect.xy) / I.rect.zw * I.c2.zw, at + 0.5, at + I.c2.zw - 0.5);\n"
"    float4 t = colour ? catlas.sample(s, uv) : float4(atlas.sample(s, uv).r);\n"
"    if (kind == 1) return (float4(col.rgb, 1.0) * (t.a * col.a)) * cover;\n"
"    if (kind == 7) {\n"
"      // inked by how light what is under its glass is, looked at round the glass's middle\n"
"      float2 c = I.pad.yz; float r = I.pad.w * 0.5;\n"
"      float l = (luma(backdrop(bd, g, c)) + luma(backdrop(bd, g, c + float2(r, 0.0))) +\n"
"                 luma(backdrop(bd, g, c - float2(r, 0.0))) + luma(backdrop(bd, g, c + float2(0.0, r))) +\n"
"                 luma(backdrop(bd, g, c - float2(0.0, r)))) / 5.0;\n"
"      float3 ink = mix(float3(1.0), float3(0.11, 0.11, 0.12), smoothstep(0.42, 0.6, l));\n"
"      return (float4(ink, 1.0) * (t.a * col.a)) * cover;\n"
"    }\n"
"    return (t * col.a) * cover;\n"
"  }\n"
"  if (kind == 6) {\n"
"    // liquid: one shape of the group's, merged; what is under it bent along the bezel, the colours split a little\n"
"    float k = I.pad.w;\n"
"    float d = sd_group(p, g, k);\n"
"    float a = clamp(0.5 - d * u.scale, 0.0, 1.0);\n"
"    if (a <= 0.0) discard_fragment();\n"
"    float e = 0.5;\n"
"    float2 grad = float2(sd_group(p + float2(e, 0.0), g, k) - sd_group(p - float2(e, 0.0), g, k),\n"
"                         sd_group(p + float2(0.0, e), g, k) - sd_group(p - float2(0.0, e), g, k));\n"
"    float2 n = grad / max(length(grad), 1e-4);\n"
"    float bezel = max(I.c2.y, 1.0);\n"
"    float edge = 1.0 - clamp(-d / bezel, 0.0, 1.0);\n"
"    float disp = I.pad.y * (1.0 - sqrt(max(1.0 - edge * edge, 0.0)));\n"
"    float2 off = -n * disp;\n"
"    float ch = I.pad.z;\n"
"    float3 c = float3(backdrop(bd, g, p + off * (1.0 + ch)).r, backdrop(bd, g, p + off).g,\n"
"                      backdrop(bd, g, p + off * (1.0 - ch)).b);\n"
"    c = max(mix(float3(luma(c)), c, I.p.z), 0.0);\n"
"    c = c * (1.0 - col.a) + col.rgb * col.a;\n"
"    // the rim lit from the top left, and less across from it\n"
"    float2 L = float2(-0.6, -0.8);\n"
"    float ndl = dot(n, L);\n"
"    float band = clamp(1.0 + d / 2.5, 0.0, 1.0);\n"
"    float spec = I.c2.x * (band * (0.9 * pow(max(ndl, 0.0), 1.5) + 0.45 * pow(max(-ndl, 0.0), 1.5)) +\n"
"                           0.3 * edge * edge * max(ndl, 0.0));\n"
"    // the edge shaded, more on the side away from the light, so the shape reads over a light ground too\n"
"    c *= 1.0 - I.c2.x * band * (0.1 + 0.25 * max(-ndl, 0.0));\n"
"    c = c + (1.0 - c) * clamp(spec, 0.0, 1.0);\n"
"    c += mb_dither(p * u.scale) / 255.0;\n"
"    return (float4(c, 1.0) * (a * I.c2.w)) * cover;\n"
"  }\n"
"  if (kind == 10) {\n"
"    // a piece of a line (scene.mbt): from c2.xy to c2.zw (shares of its rect), p.x half its width, its ends round\n"
"    float2 a = I.rect.xy + I.c2.xy * I.rect.zw, ab = I.rect.xy + I.c2.zw * I.rect.zw - a;\n"
"    float h = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-8), 0.0, 1.0);\n"
"    float d = length(p - a - ab * h) - I.p.x;\n"
"    return (float4(col.rgb, 1.0) * col.a * clamp(0.5 - d * u.scale, 0.0, 1.0)) * cover;\n"
"  }\n"
"  if (kind == 11) {\n"
"    // a band of a shape (src/ui/shape.mbt): c2.y of its pieces from c2.x, among those after every instance drawn\n"
"    // (kind 12, from instance u.pad on); p.x half its stroke's width (0: a fill, c2.z 1 by the even-odd rule)\n"
"    const device float4* sg = (const device float4*)inst;\n"
"    int first = int(I.c2.x + 0.5), n = int(I.c2.y + 0.5), base = int(u.pad + 0.5);\n"
"    float a;\n"
"    if (I.p.x > 0.0) {\n"
"      float d = 1e9;\n"
"      for (int i = first; i < first + n; i++) d = min(d, mb_seg_dist(sg[(base + i / 6) * 15 + mb_seg_slot(i)], I.rect, p));\n"
"      a = clamp(0.5 - (d - I.p.x) * u.scale, 0.0, 1.0);\n"
"    } else {\n"
"      float4 w = float4(0.0);\n"
"      for (int i = first; i < first + n; i++) w += mb_path_rows(sg[(base + i / 6) * 15 + mb_seg_slot(i)], I.rect, p, u.scale);\n"
"      a = mb_path_cover(w, I.c2.z);\n"
"    }\n"
"    return (float4(col.rgb, 1.0) * col.a * a) * cover;\n"
"  }\n"
"  float2 hs = I.rect.zw * 0.5;\n"
"  float2 c = I.rect.xy + hs;\n"
"  // worked out as near the curve as its cover, its edge or its blur reaches\n"
"  float band = 1.0 + 2.0 / u.scale + (kind == 2 ? max(I.p.w, 0.5) : max(I.p.z, 0.0));\n"
"  // (its corner by p: rr, each its own)\n"
"  float rad = mb_corner_of(p - c, I.rr);\n"
"  float d = mb_sd_box(p - c, hs, rad, band);\n"
"  if (kind == 0 || kind == 5) d = notch_cut(d, p, I.rect, I.pad);\n"
"  if (kind == 9) { float rr = min(rad, min(hs.x, hs.y)); float2 q = abs(p - c) - hs + rr; if (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rr > 0.0) discard_fragment(); return (float4(0.0)) * cover; }\n"
"  if (kind == 4) {\n"
"    constexpr sampler si(filter::linear, address::clamp_to_edge);\n"
"    float2 uv = I.c2.xy + clamp((p - I.rect.xy) / I.rect.zw, 0.0, 1.0) * I.c2.zw;\n"
"    float4 pic = img.sample(si, clamp(uv, 0.0, 1.0));\n"
"    float edge = clamp(0.5 - d * u.scale, 0.0, 1.0);\n"
"    if (I.pad.z > 0.5) {\n"
"      // Only picture edges inside the frame cut it; the frame's clip covers shared edges once.\n"
"      float2 size = I.rect.zw / I.c2.zw, lo = I.rect.xy - I.c2.xy * size, hi = lo + size;\n"
"      float2 a = lo - p, b = p - hi;\n"
"      if (I.c2.x >= 0.0) a.x = -1e9; if (I.c2.y >= 0.0) a.y = -1e9;\n"
"      if (I.c2.x + I.c2.z <= 1.0) b.x = -1e9; if (I.c2.y + I.c2.w <= 1.0) b.y = -1e9;\n"
"      float2 q = max(a, b);\n"
"      float pd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);\n"
"      pic *= I.pad.w * clamp(0.5 - pd * u.scale, 0.0, 1.0);\n"
"      pic += float4(col.rgb * I.pad.y, I.pad.y) * (1.0 - pic.a);\n"
"      if (I.rot.w < 0.5 && max(max(I.rr.x, I.rr.y), max(I.rr.z, I.rr.w)) <= 0.0 &&\n"
"          max(max(I.rc.x, I.rc.y), max(I.rc.z, I.rc.w)) > 0.0 &&\n"
"          all(I.clip.xy >= I.rect.xy) && all(I.clip.zw <= I.rect.xy + I.rect.zw)) edge = 1.0;\n"
"    }\n"
"    return (pic * (col.a * edge)) * cover;\n"
"  }\n"
"  if (kind == 2) {\n"
"    // as Core Animation's: the shape blurred, sigma its radius (corner.sl mb_shadow)\n"
"    float a = mb_shadow(p - c, hs, rad, max(I.p.w, 0.25));\n"
"    // glass's: only outside its box (c2.y above it)\n"
"    if (I.c2.x > 0.5) {\n"
"      float2 q = p - c + float2(0.0, I.c2.y);\n"
"      float db = mb_sd_box(q, hs, mb_corner_of(q, I.rr), band);\n"
"      a *= clamp(0.5 + db * u.scale, 0.0, 1.0);\n"
"    }\n"
"    return (float4(col.rgb, 1.0) * col.a * a) * cover;\n"
"  }\n"
"  float a = clamp(0.5 - d * u.scale, 0.0, 1.0);\n"
"  if (kind == 5) {\n"
"    // frosted: the blurred copy, saturated, the tint over it; the rim (a hairline inside the edge, the top left lit,\n"
"    // the foot and right less), 0.5 wide. Through (misc.y): as much of it as was a native view's hole left out (its\n"
"    // alpha), for the view's own frost under the canvas to show there\n"
"    float4 b4 = backdrop4(bd, g, p);\n"
"    float3 g3 = max(mix(float3(luma(b4.rgb)), b4.rgb, I.p.z), 0.0);\n"
"    float ga = g.misc.y > 0.5 ? b4.a : 1.0;\n"
"    g3 = g3 * (1.0 - col.a) + col.rgb * col.a;\n"
"    ga = ga * (1.0 - col.a) + col.a;\n"
"    if (I.c2.x + I.c2.y + I.c2.z > 0.0) {\n"
"      float edge = clamp(0.5 + (d + 0.5) * u.scale, 0.0, 1.0);\n"
"      float lit = clamp(0.5 + notch_cut(sd_rr(p - 0.5, I.rect, I.rr), p - 0.5, I.rect, I.pad) * u.scale, 0.0, 1.0);\n"
"      float back = clamp(0.5 + notch_cut(sd_rr(p + 0.5, I.rect, I.rr), p + 0.5, I.rect, I.pad) * u.scale, 0.0, 1.0);\n"
"      float4 w4 = mix(float4(g3, ga), float4(1.0), I.c2.x * edge);\n"
"      w4 = mix(w4, float4(1.0), I.c2.y * lit);\n"
"      w4 = mix(w4, float4(1.0), I.c2.z * back);\n"
"      g3 = w4.rgb; ga = w4.a;\n"
"    }\n"
"    // dithered as it is written to 8 bits, so its slopes do not band (corner.sl mb_dither)\n"
"    g3 += mb_dither(p * u.scale) / 255.0;\n"
"    return (float4(g3, ga) * (a * I.c2.w)) * cover;\n"
"  }\n"
"  float4 fill = float4(col.rgb, 1.0) * col.a;\n"
"  float bw = I.p.z;\n"
"  if (bw > 0.0) {\n"
"    float inner = clamp(0.5 - (d + bw) * u.scale, 0.0, 1.0);\n"
"    float4 bc = float4(I.c2.rgb, 1.0) * I.c2.a;\n"
"    fill = mix(bc, fill, inner);\n"
"  }\n"
"  return (fill * a) * cover;\n"
"}\n"
"// The backdrop's passes: a.xy the source's texel, a.z 1 halving (dual Kawase's down), 2 a Gaussian along b.zw of\n"
"// deviation a.w (texels); b.xy the last texel's centre of what the source holds\n"
"struct PU { float4 a; float4 b; float4 map, box, rr, clip, rc, rs, outer, orc, ors; };\n"
"vertex float4 vpost(uint vid [[vertex_id]]) {\n"
"  float2 c = float2(vid == 1 ? 3.0 : -1.0, vid == 2 ? 3.0 : -1.0);\n"
"  return float4(c, 0.0, 1.0);\n"
"}\n"
"fragment float4 fpost(float4 pos [[position]], texture2d<float> src [[texture(0)]], constant PU& u [[buffer(0)]]) {\n"
"  constexpr sampler s(filter::linear, address::clamp_to_edge);\n"
"  float2 ts = u.a.xy;\n"
"  float2 lo = ts * 0.5, hi = u.b.xy;\n"
"  if (u.a.z > 2.5) {\n"
"    float2 p = u.map.xy + pos.xy * u.map.zw;\n"
"    p = mb_contained_point(p, u.box, u.rr, u.clip, u.rc, u.rs, u.outer, u.orc, u.ors, u.map.z);\n"
"    return src.sample(s, clamp((p - u.map.xy) / u.map.zw * ts, lo, hi));\n"
"  }\n"
"  if (u.a.z < 1.5) {\n"
"    float2 uv = pos.xy * 2.0 * ts;\n"
"    float4 o = src.sample(s, clamp(uv, lo, hi)) * 4.0;\n"
"    o += src.sample(s, clamp(uv - ts, lo, hi));\n"
"    o += src.sample(s, clamp(uv + ts, lo, hi));\n"
"    o += src.sample(s, clamp(uv + float2(ts.x, -ts.y), lo, hi));\n"
"    o += src.sample(s, clamp(uv + float2(-ts.x, ts.y), lo, hi));\n"
"    return o / 8.0;\n"
"  }\n"
"  float2 uv = pos.xy * ts;\n"
"  float2 dir = u.b.zw * ts;\n"
"  float sg = u.a.w;\n"
"  float k = -0.5 / (sg * sg);\n"
"  float4 o = src.sample(s, clamp(uv, lo, hi));\n"
"  float wsum = 1.0;\n"
"  int n = int(ceil(sg * 3.0));\n"
"  for (int i = 1; i <= 64; i += 2) {\n"
"    if (i > n) break;\n"
"    float w1 = exp(float(i * i) * k), w2 = exp(float((i + 1) * (i + 1)) * k);\n"
"    float w = w1 + w2;\n"
"    float off = (float(i) * w1 + float(i + 1) * w2) / w;\n"
"    o += (src.sample(s, clamp(uv + dir * off, lo, hi)) + src.sample(s, clamp(uv - dir * off, lo, hi))) * w;\n"
"    wsum += 2.0 * w;\n"
"  }\n"
"  return o / wsum;\n"
"}\n";

static id<MTLRenderPipelineState> make_pipe(id<MTLLibrary> lib, MTLPixelFormat fmt, BOOL blend) {
  MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new];
  d.vertexFunction = [lib newFunctionWithName:@"vmain"];
  d.fragmentFunction = [lib newFunctionWithName:@"fmain"];
  d.colorAttachments[0].pixelFormat = fmt;
  d.colorAttachments[0].blendingEnabled = blend;
  d.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
  d.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
  d.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
  d.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
  NSError *err = nil;
  id<MTLRenderPipelineState> p = [dev newRenderPipelineStateWithDescriptor:d error:&err];
  if (!p) NSLog(@"pipeline: %@", err);
  return p;
}

// An atlas `side` texels square: the words' a byte a texel, colour glyphs' four.
static id<MTLTexture> atlas_texture(int color, int side) {
  MTLTextureDescriptor *td = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:color ? MTLPixelFormatRGBA8Unorm : MTLPixelFormatR8Unorm
                                   width:(NSUInteger)side
                                  height:(NSUInteger)side
                               mipmapped:NO];
  td.usage = MTLTextureUsageShaderRead;
  return [dev newTextureWithDescriptor:td];
}

// The device, the shaders compiled and the pipelines made: what drawing needs whatever it draws into, on a queue of its
// own from as the program loads (prepare, below), so that compiling the shaders (most of a start's time before its
// window, as AppKit waited on Metal's compiler: 2026-10-27) goes on while the program starts and AppKit makes the app
// and its window; what is drawn into waits for it only as it is made (mb_render_init).
static dispatch_group_t prepared;

static void prepare_gpu(void) {
  dev = MTLCreateSystemDefaultDevice();
  queue = [dev newCommandQueue];
  NSError *err = nil;
  id<MTLLibrary> lib = [dev newLibraryWithSource:shader_src options:nil error:&err];
  if (!lib) NSLog(@"shader: %@", err);
  mpipe = make_pipe(lib, MTLPixelFormatBGRA8Unorm, YES);
  hpipe = make_pipe(lib, MTLPixelFormatBGRA8Unorm, NO);
  rpipe_off = mpipe;
  MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
  pd.vertexFunction = [lib newFunctionWithName:@"vpost"];
  pd.fragmentFunction = [lib newFunctionWithName:@"fpost"];
  pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
  ppipe = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
  if (!ppipe) NSLog(@"post pipeline: %@", err);
  pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;
  ppipe_deep = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
  if (!ppipe_deep) NSLog(@"post pipeline: %@", err);
  atlas = atlas_texture(0, MB_ATLAS_SIDE);
  catlas = atlas_texture(1, MB_ATLAS_COLOR_SIDE);
  inflight = dispatch_semaphore_create(3);
}

__attribute__((constructor)) static void prepare(void) {
  prepared = dispatch_group_create();
  dispatch_group_async(prepared, dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{ prepare_gpu(); });
}

void mb_render_init(CAMetalLayer *layer) {
  dispatch_group_wait(prepared, DISPATCH_TIME_FOREVER);
  mlayer = layer;
  layer.device = dev;
  layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
  // glass copies what is drawn so far out of the drawable
  layer.framebufferOnly = NO;
  // native views show under it through holes (mb_views_*); a frame clears opaque
  layer.opaque = NO;
}

id<MTLDevice> mb_render_device(void) {
  dispatch_group_wait(prepared, DISPATCH_TIME_FOREVER);
  return dev;
}

void mb_render_set_size(double w, double h, double scale) {
  vw = w;
  vh = h;
  vscale = scale;
  CGSize want = CGSizeMake(round(w * scale), round(h * scale));
  if (!CGSizeEqualToSize(mlayer.drawableSize, want)) mlayer.drawableSize = want;
}

void mb_atlas_upload(int color, int x, int y, int w, int h, const void *px) {
  [(color ? catlas : atlas) replaceRegion:MTLRegionMake2D(x, y, w, h) mipmapLevel:0 withBytes:px
                              bytesPerRow:(NSUInteger)w * (color ? 4 : 1)];
}

// ---------------------------------------------------------------------------
// Glass: when the instances reach a run of glass (slot 20 negative: the capture it shares), what is drawn so far
// under it (its rects with room for the blur round them) is copied out, halved down to where the blur is a few texels
// wide (dual Kawase's downsample, at most 1/8), blurred there by a Gaussian of what deviation is left, and drawn
// through. Level 0, the copy, has 8 bits a channel as the target has; what the passes write keeps more (half floats,
// its alpha too: how much of it was a native view's hole, glass_through): at 8 each pass rounds the frost's slow
// slopes into flat steps, a texel of the last level 8 pixels wide on the screen (a blur under 4 pixels, too narrow to
// halve, is written back into the copy: it leaves no slope that wide).

typedef struct { float map[4]; float uvc[4]; float gb[4]; float shape[8][4]; float rad[2][4]; float misc[4]; } GU;
static GU gu;
static id<MTLTexture> gtex;  // the blurred copy the glass in view shows

static id<MTLTexture> level_tex(MTLPixelFormat format, int w, int h) {
  MTLTextureDescriptor *td = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:format width:(NSUInteger)(w > 0 ? w : 1)
                                  height:(NSUInteger)(h > 0 ? h : 1) mipmapped:NO];
  td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
  td.storageMode = MTLStorageModePrivate;
  return [dev newTextureWithDescriptor:td];
}

// the blur kept in the levels is of the last capture while it is (kept_ok, below)
static int kept_ok;

static void ensure_levels(int w, int h) {
  if (lv_w >= w && lv_h >= h && lv[0]) return;
  lv_w = w > lv_w ? w : lv_w;
  lv_h = h > lv_h ? h : lv_h;
  for (int j = 0; j < 4; j++)
    lv[j] = level_tex(j == 0 ? MTLPixelFormatBGRA8Unorm : MTLPixelFormatRGBA16Float, (lv_w + (1 << j) - 1) >> j,
                      (lv_h + (1 << j) - 1) >> j);
  ltmp = level_tex(MTLPixelFormatRGBA16Float, lv_w, lv_h);
  kept_ok = 0;
}

// one pass of the blur: src into dst's top left (w × h); mode 1 halving, 2 a Gaussian of deviation sg along (dx, dy)
static void post_pass(id<MTLCommandBuffer> cb, id<MTLTexture> src, int sw, int sh, id<MTLTexture> dst, int w, int h,
                      int mode, float sg, float dx, float dy, const MBContained *edge) {
  MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
  rp.colorAttachments[0].texture = dst;
  rp.colorAttachments[0].loadAction = MTLLoadActionDontCare;
  rp.colorAttachments[0].storeAction = MTLStoreActionStore;
  id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
  [e setRenderPipelineState:dst.pixelFormat == MTLPixelFormatRGBA16Float ? ppipe_deep : ppipe];
  [e setViewport:(MTLViewport){0, 0, (double)w, (double)h, 0, 1}];
  [e setScissorRect:(MTLScissorRect){0, 0, (NSUInteger)w, (NSUInteger)h}];
  float tw = 1.0f / (float)src.width, th = 1.0f / (float)src.height;
  struct { float a[4]; float b[4]; MBContained edge; } u = {{tw, th, (float)mode, sg}, {((float)sw - 0.5f) * tw, ((float)sh - 0.5f) * th, dx, dy}, {0}};
  if (edge) u.edge = *edge;
  [e setFragmentBytes:&u length:sizeof u atIndex:0];
  [e setFragmentTexture:src atIndex:0];
  [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
  [e endEncoding];
}

// Glass over a native view (a page, a video: under the canvas, seen through its hole) frosts what the view shows too.
// The canvas holds none of it (a hole is nothing in it), so that part of the frost is Core Animation's: a backdrop
// over the views, under the canvas (apple_views.m mb_views_frost), each the shape of a glass instance, blurred and
// saturated as the glass is; the canvas's glass leaves out as much of its frost as was the hole (its copy's alpha,
// gu.misc.y), for that to show there. The captures that do (their slot 20, through_tid), found as a frame is
// presented; none in a frame drawn otherwise (offscreen, read back, a snapshot: no views under it).
#define MB_THROUGH 16
#define MB_HOLES 32
static int through_n;
static float through_tid[MB_THROUGH];

static int is_through(float tid) {
  for (int i = 0; i < through_n; i++)
    if (through_tid[i] == tid) return 1;
  return 0;
}

// what of instance b shows: its rect cut by its clip's (x0 y0 x1 y1); 0 when nothing does
static int shows_of(const double *b, float r[4]) {
  r[0] = (float)fmax(b[0], b[16]); r[1] = (float)fmax(b[1], b[17]);
  r[2] = (float)fmin(b[0] + b[2], b[18]); r[3] = (float)fmin(b[1] + b[3], b[19]);
  return r[2] > r[0] && r[3] > r[1];
}

// The frame's frosted glass over holes (kind 9) painted before it: its captures through, and every instance of them
// a backdrop over the views whose holes were painted before it (the last of them: `under`), at that view's place
// among them. Told to the views (which say whether they can frost: else none is through, the glass as before).
static void glass_through(const double *f, int32_t count) {
  // Instances are in content points; the system views underneath are placed in window points.
  double zoom = mlayer && mlayer.contentsScale > 0 ? vscale / mlayer.contentsScale : 1.0;
  float holes[MB_HOLES][4];
  int nh = 0;
  through_n = 0;
  for (int32_t i = 0; i < count; i++) {
    const double *b = f + i * MB_INST;
    int kind = (int)(b[5] + 0.5);
    float r[4];
    if (kind == 9) {
      if (nh < MB_HOLES && shows_of(b, r)) memcpy(holes[nh++], r, sizeof r);
      continue;
    }
    if (kind != 5 || b[20] >= 0 || !nh || through_n >= MB_THROUGH || is_through((float)b[20]) || !shows_of(b, r))
      continue;
    // (its blur reaches a hole near it too)
    float m = 3.0f * fabsf((float)b[7]);
    for (int h = 0; h < nh; h++)
      if (holes[h][0] < r[2] + m && r[0] - m < holes[h][2] && holes[h][1] < r[3] + m && r[1] - m < holes[h][3]) {
        through_tid[through_n++] = (float)b[20];
        break;
      }
  }
  double frosts[MB_FROSTS * MB_FROST_N];
  int n = 0;
  int32_t under = 0;
  for (int32_t i = 0; i < count && through_n; i++) {
    const double *b = f + i * MB_INST;
    int kind = (int)(b[5] + 0.5);
    if (kind == 9) under = (int32_t)(b[20] + 0.5) - MB_VIEW_TEX;
    float r[4];
    if (kind != 5 || !is_through((float)b[20]) || under <= 0 || n >= MB_FROSTS || !shows_of(b, r)) continue;
    double *e = frosts + n++ * MB_FROST_N;
    for (int k = 0; k < 4; k++) {
      e[k] = r[k] * zoom;
      e[4 + k] = b[k] * zoom;
      e[8 + k] = b[36 + k] * zoom;
    }
    e[12] = fabs(b[7]) * zoom;
    e[13] = b[6];
    e[14] = b[15];
    e[15] = under;
  }
  if (!mb_views_frost(n, frosts)) through_n = 0;
}

// What a capture of glass is of, worked out before any of the GPU's work: its rectangle in the target's pixels, how
// many times it is halved (k, at most 3) and the Gaussian left after (sg), and the glass's own numbers (gu's but map
// and uvc, which follow from these and the level's size). Zeroed whole first, so two of the same compare the same.
typedef struct { int px0, py0, w, h, k, contained; float sg; GU g; MBContained edge; } Grab;

// The capture the run [start, end) of glass makes, of a target tw × th pixels; 0 when none of it shows.
// Frosted glass of the same capture further on (glass.mbt shares_capture) is under it too.
static int grab_of(Grab *m, const float *f, int32_t start, int32_t end, int32_t count, int tw, int th) {
  memset(m, 0, sizeof *m);
  const float *a = f + start * MB_INST;
  // A negative blur is contained: its straight edges are the capture's edges, its curved ones extended separately.
  float blur = fabsf(a[7]);
  int kind = (int)(a[5] + 0.5f);
  float margin = a[7] < 0.0f ? 0.0f : 3.0f * blur + (kind == 6 ? a[21] * (1.0f + a[22]) + a[23] : 0.0f) + 2.0f;
  float x0 = 1e9f, y0 = 1e9f, x1 = -1e9f, y1 = -1e9f;
  int n = 0;
  for (int32_t i = start; i < end; i++) {
    const float *b = f + i * MB_INST;
    // what of it shows: its clip
    float bx0 = fmaxf(b[0], b[16]), by0 = fmaxf(b[1], b[17]);
    float bx1 = fminf(b[0] + b[2], b[18]), by1 = fminf(b[1] + b[3], b[19]);
    if (kind == 6) {
      bx0 = b[0] - a[23]; by0 = b[1] - a[23]; bx1 = b[0] + b[2] + a[23]; by1 = b[1] + b[3] + a[23];
      if (n < 8) {
        for (int k = 0; k < 4; k++) m->g.shape[n][k] = b[k];
        m->g.rad[n / 4][n % 4] = b[4];
        n++;
      }
    }
    x0 = fminf(x0, bx0); y0 = fminf(y0, by0); x1 = fmaxf(x1, bx1); y1 = fmaxf(y1, by1);
  }
  if (kind == 5) {
    for (int32_t i = end; i < count; i++) {
      const float *b = f + i * MB_INST;
      if (b[20] != a[20]) continue;
      x0 = fminf(x0, fmaxf(b[0], b[16])); y0 = fminf(y0, fmaxf(b[1], b[17]));
      x1 = fmaxf(x1, fminf(b[0] + b[2], b[18])); y1 = fmaxf(y1, fminf(b[1] + b[3], b[19]));
    }
  }
  m->g.misc[0] = (float)n;
  m->g.misc[1] = is_through(a[20]) ? 1.0f : 0.0f;
  m->g.gb[0] = x0 - 2; m->g.gb[1] = y0 - 2; m->g.gb[2] = x1 + 2; m->g.gb[3] = y1 + 2;
  float sc = (float)vscale;
  int px0 = (int)floorf((x0 - margin) * sc), py0 = (int)floorf((y0 - margin) * sc);
  int px1 = (int)ceilf((x1 + margin) * sc), py1 = (int)ceilf((y1 + margin) * sc);
  if (px0 < 0) px0 = 0;
  if (py0 < 0) py0 = 0;
  if (px1 > tw) px1 = tw;
  if (py1 > th) py1 = th;
  if (px1 <= px0 || py1 <= py0 || x1 <= x0 || y1 <= y0) return 0;
  m->px0 = px0; m->py0 = py0; m->w = px1 - px0; m->h = py1 - py0;
  m->contained = mb_contained_make(&m->edge, a, px0 / sc, py0 / sc, 1.0f / sc, 1.0f / sc);
  // down to where the deviation is 2 texels or more, at most 1/8
  float sp = blur * sc;
  int k = 0;
  while (k < 3 && sp / (float)(1 << (k + 1)) >= 2.0f) k++;
  // what is left of the deviation once the halvings' and the last look's (bilinear) spread are taken out
  float sk = sp / (float)(1 << k);
  float pre = k > 0 ? 0.75f * (1.0f - powf(0.25f, (float)k)) / 3.0f + 1.0f / 6.0f : 0.0f;
  m->k = k;
  m->sg = sqrtf(fmaxf(sk * sk - pre, 0.0f));
  return 1;
}

// The size of a grab's level k (its passes write each level's top left)
static void grab_levels(const Grab *m, int lw[4], int lh[4]) {
  lw[0] = m->w; lh[0] = m->h;
  for (int j = 1; j <= 3; j++) {
    lw[j] = (lw[j - 1] + 1) / 2;
    lh[j] = (lh[j - 1] + 1) / 2;
  }
}

// What the glass shows of a grab blurred in the levels: gtex, and gu, its numbers with where in level k it is.
static void show_blur(const Grab *m) {
  int lw[4], lh[4];
  grab_levels(m, lw, lh);
  gu = m->g;
  gtex = m->contained && m->k == 0 ? ltmp : lv[m->k];
  float sc = (float)vscale;
  float W = (float)gtex.width, H = (float)gtex.height, d = (float)(1 << m->k);
  gu.map[0] = sc / d / W; gu.map[1] = sc / d / H;
  gu.map[2] = -(float)m->px0 / d / W; gu.map[3] = -(float)m->py0 / d / H;
  gu.uvc[0] = 0.5f / W; gu.uvc[1] = 0.5f / H;
  gu.uvc[2] = ((float)lw[m->k] - 0.5f) / W; gu.uvc[3] = ((float)lh[m->k] - 0.5f) / H;
}

// A grab of target blurred into the levels: what is drawn so far in its rectangle copied out, halved k times, the
// Gaussian left (passes of their own, the target's pass ended before), then shown (show_blur).
static void blur(id<MTLCommandBuffer> cb, id<MTLTexture> target, const Grab *m) {
  ensure_levels(m->w, m->h);
  id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
  [bl copyFromTexture:target sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(m->px0, m->py0, 0)
           sourceSize:MTLSizeMake(m->w, m->h, 1) toTexture:lv[0] destinationSlice:0 destinationLevel:0
    destinationOrigin:MTLOriginMake(0, 0, 0)];
  [bl endEncoding];
  int lw[4], lh[4];
  grab_levels(m, lw, lh);
  int k = m->k;
  if (m->contained) post_pass(cb, lv[0], lw[0], lh[0], ltmp, lw[0], lh[0], 3, 0, 0, 0, &m->edge);
  for (int j = 1; j <= k; j++) post_pass(cb, j == 1 && m->contained ? ltmp : lv[j - 1], lw[j - 1], lh[j - 1], lv[j], lw[j], lh[j], 1, 0, 0, 0, NULL);
  if (m->sg > 0.3f) {
    id<MTLTexture> from = m->contained && k == 0 ? ltmp : lv[k];
    id<MTLTexture> tmp = m->contained && k == 0 ? lv[0] : ltmp;
    post_pass(cb, from, lw[k], lh[k], tmp, lw[k], lh[k], 2, m->sg, 1, 0, NULL);
    post_pass(cb, tmp, lw[k], lh[k], from, lw[k], lh[k], 2, m->sg, 0, 1, NULL);
  }
  show_blur(m);
}

// The blur the levels hold, as long as no capture came after it (kept_ok): what it was of. What a capture copies is
// what the frame drew before it (its instances up to the glass, the pieces of the frame's shapes they are drawn by,
// the ground the frame cleared to) in the grab's rectangle of a target of that size: a frame that draws all that the
// same under the same glass (a caret blinking in a composer over a chat at rest) shows the blur as it is, with no copy,
// no passes, and its pass not broken in two. A stream drawn under it (its pictures change under the same instances)
// is blurred anew each frame.
static float *kept_under;
static size_t kept_under_cap, kept_under_n;
static Grab kept_grab;
static double kept_key[7];

// The floats a capture of the run at start is of, and their count: those before it and the shapes' pieces (from
// seg_base on), 0 when a stream is among them.
static size_t under_of(const float *f, int32_t start, int32_t count, int32_t pieces) {
  for (int32_t i = 0; i < start; i++)
    if (f[i * MB_INST + 20] > (float)MB_STREAM_TEX) return 0;
  return (size_t)(start + (count - pieces)) * MB_INST;
}

static int same_under(const float *f, int32_t start, int32_t count, int32_t pieces, const Grab *m, const double key[7]) {
  size_t n = under_of(f, start, count, pieces);
  if (!kept_ok || n == 0 || n != kept_under_n || memcmp(&kept_grab, m, sizeof *m) != 0 || memcmp(kept_key, key, sizeof kept_key) != 0)
    return 0;
  size_t a = (size_t)start * MB_INST;
  return memcmp(kept_under, f, a * sizeof(float)) == 0 &&
         memcmp(kept_under + a, f + (size_t)pieces * MB_INST, (n - a) * sizeof(float)) == 0;
}

static void keep_under(const float *f, int32_t start, int32_t count, int32_t pieces, const Grab *m, const double key[7]) {
  size_t n = under_of(f, start, count, pieces);
  kept_ok = 0;
  if (n == 0) return;
  if (kept_under_cap < n) {
    kept_under = realloc(kept_under, n * sizeof(float));
    kept_under_cap = n;
  }
  size_t a = (size_t)start * MB_INST;
  memcpy(kept_under, f, a * sizeof(float));
  memcpy(kept_under + a, f + (size_t)pieces * MB_INST, (n - a) * sizeof(float));
  kept_under_n = n;
  kept_grab = *m;
  memcpy(kept_key, key, sizeof kept_key);
  kept_ok = 1;
}

// where the pieces of the frame's shapes start (src/ui/shape.mbt: the instances of kind 12 after every one drawn)
static int32_t seg_base;

// Partial redraw (docs/partial-redraw.md): a window's frame is drawn into a canvas of its own, kept across frames, and
// copied into the drawable; where the app says only some parts of it differ from the frame before
// (@hostapi.render_dirty), only those parts of the canvas are drawn again, a pass each: it loads what the canvas holds,
// cut to the part (the pass's scissor, `sc`, while `sc_on`), the frame's ground drawn over the part first (the
// instance after the frame's, upload's), then every instance (what falls outside is cut away).
static id<MTLTexture> canvas;
// what the canvas holds is the last frame given (none lost: a frame not drawn into it, its size another)
static int canvas_ok;
// the parts of the next frame that differ (points: x, y, w, h), all of it (`dirty_whole`), and whether any was said
#define MB_PARTS 8
static double dirty[MB_PARTS][4];
static int dirty_n, dirty_whole, dirty_told;
// a picture the frame drawn last had none of yet (its texture not made: drawn without it): the next drawn whole, as
// what it shows changes under the same numbers
static int pictures_missing, encode_missing;
static int sc_on;
static MTLScissorRect sc;

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

// The parts of a target tw × th pixels the next frame draws, from what was said of them (taken: a frame nothing was
// said for is drawn whole), into `r`: how many (0 none), -1 all of it. `kept`: the target holds the frame before.
static int take_parts(int tw, int th, int kept, MTLScissorRect r[MB_PARTS]) {
  int told = dirty_told, whole = dirty_whole, n = dirty_n;
  dirty_told = dirty_whole = dirty_n = 0;
  if (!told || whole || !kept || pictures_missing) return -1;
  int k = 0;
  for (int i = 0; i < n; i++) {
    // (whole pixels round it, and one more: the app's part reaches its pixels' antialiasing, not their rounding)
    int x0 = (int)floor(dirty[i][0] * vscale) - 1, y0 = (int)floor(dirty[i][1] * vscale) - 1;
    int x1 = (int)ceil((dirty[i][0] + dirty[i][2]) * vscale) + 1, y1 = (int)ceil((dirty[i][1] + dirty[i][3]) * vscale) + 1;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > tw) x1 = tw;
    if (y1 > th) y1 = th;
    if (x1 > x0 && y1 > y0) r[k++] = (MTLScissorRect){(NSUInteger)x0, (NSUInteger)y0, (NSUInteger)(x1 - x0), (NSUInteger)(y1 - y0)};
  }
  return k;
}

// Whether a grab's rectangle meets the part drawn (all of it where the frame is drawn whole).
static int grab_in_part(const Grab *m) {
  if (!sc_on) return 1;
  return m->px0 < (int)(sc.x + sc.width) && (int)sc.x < m->px0 + m->w && m->py0 < (int)(sc.y + sc.height) &&
         (int)sc.y < m->py0 + m->h;
}

static id<MTLRenderCommandEncoder> begin_pass(id<MTLCommandBuffer> cb, id<MTLTexture> target, id<MTLRenderPipelineState> p,
                                              id<MTLBuffer> buf, int clear, double r, double g, double b, double alpha) {
  MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
  rp.colorAttachments[0].texture = target;
  rp.colorAttachments[0].loadAction = clear ? MTLLoadActionClear : MTLLoadActionLoad;
  rp.colorAttachments[0].storeAction = MTLStoreActionStore;
  rp.colorAttachments[0].clearColor = MTLClearColorMake(r, g, b, alpha);
  id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
  struct { float vp[2]; float scale; float pad; } u = {{(float)vw, (float)vh}, (float)vscale, (float)seg_base};
  [enc setRenderPipelineState:p];
  [enc setVertexBuffer:buf offset:0 atIndex:0];
  [enc setVertexBytes:&u length:sizeof(u) atIndex:1];
  [enc setVertexBytes:&gu length:sizeof(gu) atIndex:2];
  [enc setFragmentBuffer:buf offset:0 atIndex:0];
  [enc setFragmentBytes:&u length:sizeof(u) atIndex:1];
  [enc setFragmentBytes:&gu length:sizeof(gu) atIndex:2];
  [enc setFragmentTexture:atlas atIndex:0];
  [enc setFragmentTexture:catlas atIndex:3];
  [enc setFragmentTexture:(gtex ?: atlas) atIndex:2];
  if (sc_on) [enc setScissorRect:sc];
  return enc;
}

// `part`: only that part of the target drawn again, over what it holds (the frame's ground first: the instance after
// the frame's, upload's); NULL, all of it, cleared to the ground.
static void encode(id<MTLCommandBuffer> cb, id<MTLTexture> target, id<MTLRenderPipelineState> p,
                   id<MTLBuffer> buf, int32_t count, double r, double g, double b, double alpha, const MTLScissorRect *part) {
  gtex = nil;
  memset(&gu, 0, sizeof gu);
  encode_missing = 0;
  const float *f = (const float *)buf.contents;
  seg_base = count;
  while (seg_base > 0 && (int)(f[(seg_base - 1) * MB_INST + 5] + 0.5f) == 12) seg_base--;
  sc_on = part != NULL;
  if (part) sc = *part;
  id<MTLRenderCommandEncoder> enc = begin_pass(cb, target, p, buf, part ? 0 : 1, r, g, b, alpha);
  if (part) {
    [enc setRenderPipelineState:hpipe];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:1 baseInstance:count];
  }
  // one draw per run of instances showing the same image (slot 20; 0:
  // none, the atlas stands in), or sharing one capture of glass (negative),
  // and holes for native views (kind 9) apart, unblended. Glass over a hole
  // sees the hole (the canvas only, not the view under it).
  int32_t start = 0;
  int bound = 0, shows = 0;
  while (start < count) {
    int tid = (int)f[start * MB_INST + 20];
    int hole = (int)(f[start * MB_INST + 5] + 0.5f) == 9;
    int32_t end = start + 1;
    while (end < count && (int)f[end * MB_INST + 20] == tid && ((int)(f[end * MB_INST + 5] + 0.5f) == 9) == hole) end++;
    if (tid < 0) {
      if (tid != bound) {
        Grab m;
        shows = grab_of(&m, f, start, end, count, (int)target.width, (int)target.height);
        // (a capture outside the part drawn: neither copied nor drawn, the blur kept as it was. One that meets it is
        // in it whole: the app's part takes in all a capture it reaches copies, @damage)
        shows = shows && grab_in_part(&m);
        double key[7] = {target.width, target.height, vscale, r, g, b, alpha};
        if (shows && same_under(f, start, count, seg_base, &m, key)) {
          // what it sees is what the levels hold: shown on in this pass
          show_blur(&m);
          [enc setVertexBytes:&gu length:sizeof gu atIndex:2];
          [enc setFragmentBytes:&gu length:sizeof gu atIndex:2];
          [enc setFragmentTexture:gtex atIndex:2];
        } else if (shows) {
          [enc endEncoding];
          blur(cb, target, &m);
          keep_under(f, start, count, seg_base, &m, key);
          enc = begin_pass(cb, target, p, buf, 0, r, g, b, alpha);
        }
        bound = tid;
      }
      [enc setRenderPipelineState:p];
      // liquid: the group as one shape, drawn once
      if (shows) {
        int liquid = (int)(f[start * MB_INST + 5] + 0.5f) == 6;
        [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6
                instanceCount:liquid ? 1 : end - start baseInstance:start];
      }
      start = end;
      continue;
    }
    [enc setRenderPipelineState:(hole ? hpipe : p)];
    // (a hole's image is its view's, src/hostapi/host.mbt view_tex_base + its id: the view is under the canvas here)
    id<MTLTexture> t = hole ? nil : tid > MB_STREAM_TEX ? mb_stream_texture(tid - MB_STREAM_TEX) : tid ? mb_image_texture(tid) : nil;
    // (a stream with no frame of its own yet, or lost: nothing, not the atlas)
    if (!hole && tid > MB_STREAM_TEX && !t) {
      start = end;
      continue;
    }
    if (!hole && tid > 0 && tid <= MB_STREAM_TEX && !t) encode_missing = 1;
    [enc setFragmentTexture:(t ?: atlas) atIndex:1];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6
            instanceCount:end - start baseInstance:start];
    start = end;
  }
  [enc endEncoding];
  sc_on = 0;
}

// The frame in `buf` drawn into `target`, only its parts that differ (take_parts) where it holds the frame before
// (`kept`), a pass each, else whole: how many parts (-1 whole, 0 none).
static int draw_parts(id<MTLCommandBuffer> cb, id<MTLTexture> target, id<MTLBuffer> buf, int32_t count, double r,
                      double g, double b, int kept) {
  MTLScissorRect parts[MB_PARTS];
  int n = take_parts((int)target.width, (int)target.height, kept, parts);
  int missing = 0;
  if (n < 0) {
    encode(cb, target, mpipe, buf, count, r, g, b, 1, NULL);
    missing = encode_missing;
  }
  for (int i = 0; i < n; i++) {
    encode(cb, target, mpipe, buf, count, r, g, b, 1, &parts[i]);
    missing |= encode_missing;
  }
  if (n != 0) pictures_missing = missing;
  return n;
}

// The instances into the next buffer of the ring (as floats), and a copy
// kept for snapshots.
static id<MTLBuffer> upload(const double *inst, int32_t count, double r, double g, double b) {
  buf_i = (buf_i + 1) % 3;
  size_t need = (size_t)(count > 0 ? count : 1) * MB_INST * sizeof(float);
  // (and the frame's ground after its instances: a rect over all the window, opaque, a part drawn again first)
  size_t room = need + MB_INST * sizeof(float);
  if (buf_cap[buf_i] < room) {
    size_t cap = room * 2;
    bufs[buf_i] = [dev newBufferWithLength:cap options:MTLResourceStorageModeShared];
    buf_cap[buf_i] = cap;
  }
  float *f = (float *)bufs[buf_i].contents;
  int32_t n = count * MB_INST;
  for (int32_t i = 0; i < n; i++) f[i] = (float)inst[i];
  float *gr = f + n;
  memset(gr, 0, MB_INST * sizeof(float));
  gr[0] = -16.0f; gr[1] = -16.0f; gr[2] = (float)vw + 32.0f; gr[3] = (float)vh + 32.0f;
  gr[8] = (float)r; gr[9] = (float)g; gr[10] = (float)b; gr[11] = 1.0f;
  gr[16] = -1e9f; gr[17] = -1e9f; gr[18] = 1e9f; gr[19] = 1e9f;
  // keep a copy for snapshots
  if (last_cap < need) {
    last_inst = realloc(last_inst, need);
    last_cap = need;
  }
  memcpy(last_inst, f, (size_t)n * sizeof(float));
  last_count = count;
  last_bg[0] = r; last_bg[1] = g; last_bg[2] = b;
  return bufs[buf_i];
}

// The frame on the screen: its size as it was drawn (mb_render_set_size's), and whether it shows a stream (whose
// pictures change under the same instances); its instances and ground are upload's copy (last_inst, last_bg).
static double shown_w, shown_h, shown_scale;
static int shown_ok, shown_streams;

// Whether a frame is the one on the screen to the last number: then it draws nothing and takes no drawable (the app
// builds a frame for what it waits on, as a clock's next second, that may show nothing new). Not one a layer presents
// with its transaction (a resize's: mac_app.m drawWithWindow), which the window's change waits for.
static int same_as_shown(const double *inst, int32_t count, double r, double g, double b) {
  if (!shown_ok || shown_streams || mlayer.presentsWithTransaction || count != last_count) return 0;
  if (vw != shown_w || vh != shown_h || vscale != shown_scale || r != last_bg[0] || g != last_bg[1] || b != last_bg[2]) return 0;
  int32_t n = count * MB_INST;
  for (int32_t i = 0; i < n; i++)
    if ((float)inst[i] != last_inst[i]) return 0;
  return 1;
}

// The canvas a window's frames are drawn into (partial redraw, above), tw × th pixels: made again at another size,
// what it held lost.
static void ensure_canvas(int tw, int th) {
  if (canvas && (int)canvas.width == tw && (int)canvas.height == th) return;
  canvas = nil;
  canvas_ok = 0;
  if (tw <= 0 || th <= 0) return;
  MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                width:(NSUInteger)tw
                                                                               height:(NSUInteger)th
                                                                            mipmapped:NO];
  td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
  td.storageMode = MTLStorageModePrivate;
  canvas = [dev newTextureWithDescriptor:td];
}

// MBUI_PARTIAL_CHECK=1 (a device's run, by hand: slow): each frame drawn in part compared with itself drawn whole,
// a line on the log where they differ, once its commands (`cb`, committed) are done.
static int partial_check = -1, partial_frames;

static uint8_t *read_texture(id<MTLTexture> src, int *pw, int *ph);
static uint8_t *read_last(int *pw, int *ph);

static void check_part(id<MTLCommandBuffer> cb, int parts) {
  if (partial_check < 0) {
    const char *v = getenv("MBUI_PARTIAL_CHECK");
    partial_check = v && v[0] == '1';
  }
  if (!partial_check) return;
  [cb waitUntilCompleted];
  int w, h, fw, fh;
  uint8_t *drawn = read_texture(canvas, &w, &h);
  uint8_t *whole = read_last(&fw, &fh);
  long apart = 0;
  int most = 0, ax = -1, ay = -1;
  if (fw == w && fh == h) {
    for (long i = 0; i < (long)w * h * 4; i++) {
      int d = abs((int)drawn[i] - (int)whole[i]);
      if (d) {
        if (!apart) { ax = (int)(i / 4 % w); ay = (int)(i / 4 / w); }
        apart++;
        if (d > most) most = d;
      }
    }
  }
  partial_frames++;
  if (apart || fw != w || fh != h || partial_frames % 120 == 1)
    fprintf(stderr, "PARTIAL check %d: %d parts of %dx%d: %ld bytes apart (at most %d, first at %d,%d)\n",
            partial_frames, parts, w, h, apart, most, ax, ay);
  free(drawn);
  free(whole);
}

// MBUI_PROBE=1 (src/ui/app.mbt's probe): where a present's time goes, said every 240 of them: waiting for a buffer of
// the ring (the GPU three frames behind), the instances into it, waiting for a drawable (the display's), and the
// drawing encoded and committed (ms, on average). On the log, and into the performance record while it is kept
// (ios_app.m's mb_perf_note: none on a Mac, these defaults).
static int present_probing = -1, present_n;
static double present_ms[4];

__attribute__((weak)) int mb_perf_on(void) { return 0; }
__attribute__((weak)) void mb_perf_note(const char *line) { (void)line; }

static void present_probe(double ring, double upload_s, double drawable, double encode_s) {
  if (present_probing < 0) {
    const char *v = getenv("MBUI_PROBE");
    present_probing = v && v[0] == '1';
  }
  if (!present_probing && !mb_perf_on()) return;
  present_ms[0] += ring * 1000.0;
  present_ms[1] += upload_s * 1000.0;
  present_ms[2] += drawable * 1000.0;
  present_ms[3] += encode_s * 1000.0;
  if (++present_n < 240) return;
  char line[160];
  snprintf(line, sizeof line, "present avg: ring wait %.2f, upload %.2f, drawable wait %.2f, encode %.2f ms",
           present_ms[0] / present_n, present_ms[1] / present_n, present_ms[2] / present_n, present_ms[3] / present_n);
  if (present_probing) fprintf(stderr, "PROBE %s\n", line);
  mb_perf_note(line);
  present_n = 0;
  memset(present_ms, 0, sizeof present_ms);
}

// What drawing holds, given back as the window stops being the one in front (mac_app.m tell_state: another app's
// in front, the window covered, minimized or hidden): Core Animation keeps the layer's drawables (three or four, each
// the window's size in pixels: 22 MB at 3024 × 1890), and the glass its levels. The drawables shrink to a pixel, which
// frees all but the one shown (Core Animation shows it on), and the levels go; a frame after makes what it needs again
// at full size (mb_render_set_size). (The driver's own memory, 30 to 100 MB of the footprint's "owned unmapped
// (graphics)", it gives back itself a second or two after the last frame: same_as_shown and the caret at rest are what
// stop the frames.)
void mb_render_trim(void) {
  if (!mlayer || CGSizeEqualToSize(mlayer.drawableSize, CGSizeMake(1, 1))) return;
  // (nothing of the GPU's still in flight uses what goes)
  for (int i = 0; i < 3; i++) dispatch_semaphore_wait(inflight, DISPATCH_TIME_FOREVER);
  for (int i = 0; i < 3; i++) dispatch_semaphore_signal(inflight);
  for (int j = 0; j < 4; j++) lv[j] = nil;
  ltmp = nil;
  gtex = nil;
  lv_w = lv_h = 0;
  kept_ok = 0;
  // (and the canvas: the next frame drawn whole into one made again)
  canvas = nil;
  canvas_ok = 0;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  mlayer.drawableSize = CGSizeMake(1, 1);
  [CATransaction commit];
}

void mb_render_present(const double *inst, int32_t count, double r, double g, double b) {
  // a frame that put a native view elsewhere (apple_views.m: a page in a message, as the list scrolls) presented in
  // the transaction that puts it there (the frame's: mac_app.m drawFrame, ios_app.m tick), so the view and the hole it
  // shows through change on the same refresh. Presented by itself the drawable is shown once the GPU has drawn it,
  // apart from the view's move, which the frame's transaction takes to the screen: a refresh or two apart, the page
  // out of step with its hole as the list moved
  // (the views' frost of glass over them put where it shows now, with them: glass_through)
  glass_through(inst, count);
  int with_views = mb_views_take_moved() && !mlayer.presentsWithTransaction;
  if (same_as_shown(inst, count, r, g, b)) {
    // (what was said of it, nothing changed, not left for the next)
    dirty_told = dirty_whole = dirty_n = 0;
    return;
  }
  if (with_views) mlayer.presentsWithTransaction = YES;
  double p0 = CACurrentMediaTime();
  dispatch_semaphore_wait(inflight, DISPATCH_TIME_FOREVER);
  double p1 = CACurrentMediaTime();
  id<MTLBuffer> buf = upload(inst, count, r, g, b);
  double p2 = CACurrentMediaTime();
  id<CAMetalDrawable> drawable = [mlayer nextDrawable];
  double p3 = CACurrentMediaTime();
  id<MTLCommandBuffer> cb = [queue commandBuffer];
  // drawn into the canvas, only the part that differs where it holds the frame before, then copied into the drawable;
  // a drawable of another size than the canvas (a resize between) drawn into whole
  int tw = (int)mlayer.drawableSize.width, th = (int)mlayer.drawableSize.height;
  int checked = 0;
  if (drawable && ((int)drawable.texture.width != tw || (int)drawable.texture.height != th)) {
    encode(cb, drawable.texture, mpipe, buf, count, r, g, b, 1, NULL);
    canvas_ok = 0;
    dirty_told = dirty_whole = dirty_n = 0;
  } else {
    ensure_canvas(tw, th);
    checked = draw_parts(cb, canvas, buf, count, r, g, b, canvas_ok);
    canvas_ok = 1;
    if (drawable) {
      id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
      [bl copyFromTexture:canvas sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0)
               sourceSize:MTLSizeMake(tw, th, 1) toTexture:drawable.texture destinationSlice:0 destinationLevel:0
        destinationOrigin:MTLOriginMake(0, 0, 0)];
      [bl endEncoding];
    }
  }
  __block dispatch_semaphore_t sem = inflight;
  [cb addCompletedHandler:^(id<MTLCommandBuffer> done) {
    last_gpu = (done.GPUEndTime - done.GPUStartTime) * 1000.0;
    dispatch_semaphore_signal(sem);
  }];
  shown_ok = drawable != nil;
  if (drawable) {
    shown_w = vw;
    shown_h = vh;
    shown_scale = vscale;
    shown_streams = 0;
    const float *f = (const float *)buf.contents;
    for (int32_t i = 0; i < count && !shown_streams; i++) shown_streams = f[i * MB_INST + 20] > (float)MB_STREAM_TEX;
  }
  // (a layer that presents with its transaction: shown with the window's change it was drawn for, mac_app.m
  // drawWithWindow, or the views' moves; once its commands are scheduled, as Core Animation asks)
  if (drawable && mlayer.presentsWithTransaction) {
    [cb commit];
    [cb waitUntilScheduled];
    [drawable present];
  } else {
    if (drawable) [cb presentDrawable:drawable];
    [cb commit];
  }
  if (with_views) mlayer.presentsWithTransaction = NO;
  through_n = 0;
  present_probe(p1 - p0, p2 - p1, p3 - p2, CACurrentMediaTime() - p3);
  if (checked > 0) check_part(cb, checked);
}

// MBUI_SAFE's bands (mac_app.m), in points, and their ground
static double band_top, band_bottom;
static uint32_t band_ground;

void mb_render_set_bands(double top, double bottom, uint32_t ground) {
  band_top = top;
  band_bottom = bottom;
  band_ground = ground;
}

// the texture the last frame is drawn again into for the CPU to read (read_last), kept while its size is
static id<MTLTexture> read_tex;

// Instances `f` (`count` of them, as upload copies a frame's) drawn on the ground `bg` into a texture the CPU reads,
// and its pixels: BGRA, premultiplied, rows from the top, the size set (mb_render_set_size), *pw × *ph; the caller
// frees them.
static uint8_t *read_of(const float *f, int32_t count, const double bg[3], double alpha, int *pw, int *ph) {
  int w = (int)round(vw * vscale), h = (int)round(vh * vscale);
  if (!read_tex || (int)read_tex.width != w || (int)read_tex.height != h) {
    MTLTextureDescriptor *td = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:w height:h mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget;
#if TARGET_OS_OSX
    td.storageMode = MTLStorageModeManaged;
#else
    td.storageMode = MTLStorageModeShared;
#endif
    read_tex = [dev newTextureWithDescriptor:td];
  }
  id<MTLTexture> tex = read_tex;
  id<MTLBuffer> buf = [dev newBufferWithBytes:f length:(count > 0 ? count : 1) * MB_INST * sizeof(float) options:MTLResourceStorageModeShared];
  id<MTLCommandBuffer> cb = [queue commandBuffer];
  encode(cb, tex, rpipe_off, buf, count, bg[0], bg[1], bg[2], alpha, NULL);
#if TARGET_OS_OSX
  id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
  [bl synchronizeResource:tex];
  [bl endEncoding];
#endif
  [cb commit];
  [cb waitUntilCompleted];
  size_t bpr = (size_t)w * 4;
  uint8_t *px = malloc(bpr * h);
  [tex getBytes:px bytesPerRow:bpr fromRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0];
  *pw = w;
  *ph = h;
  return px;
}

// What a texture the GPU keeps (a canvas: private) holds, once what is drawn into it is done, read back as read_of
// reads: the caller frees it.
static uint8_t *read_texture(id<MTLTexture> src, int *pw, int *ph) {
  int w = (int)src.width, h = (int)src.height;
  uint8_t *px = malloc((size_t)w * h * 4);
  @autoreleasepool {
    MTLTextureDescriptor *td = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:w height:h mipmapped:NO];
#if TARGET_OS_OSX
    td.storageMode = MTLStorageModeManaged;
#else
    td.storageMode = MTLStorageModeShared;
#endif
    id<MTLTexture> tex = [dev newTextureWithDescriptor:td];
    id<MTLCommandBuffer> cb = [queue commandBuffer];
    id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
    [bl copyFromTexture:src sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0)
             sourceSize:MTLSizeMake(w, h, 1) toTexture:tex destinationSlice:0 destinationLevel:0
      destinationOrigin:MTLOriginMake(0, 0, 0)];
#if TARGET_OS_OSX
    [bl synchronizeResource:tex];
#endif
    [bl endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    [tex getBytes:px bytesPerRow:(size_t)w * 4 fromRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0];
  }
  *pw = w;
  *ph = h;
  return px;
}

// The last frame's instances (upload's copy) drawn again, read back as read_of reads them.
static uint8_t *read_last(int *pw, int *ph) {
  return read_of(last_inst, last_count, last_bg, 1, pw, ph);
}

// A frame drawn offscreen and read back (a film's, mbui/src/film): `inst` as mb_render_present takes them, kept as
// the last frame, and its pixels as read_last gives them.
uint8_t *mb_render_read(const double *inst, int32_t count, double r, double g, double b, int *pw, int *ph) {
  @autoreleasepool {
    upload(inst, count, r, g, b);
    return read_last(pw, ph);
  }
}

// The frame presented last drawn again (read_last), and its pixels in the rectangle x, y, w × h (from its top left)
// into `out` as RGBA, premultiplied, rows from the top (host_native.mbt drawn_pixels): 1 when read, 0 where the
// rectangle is not all in the frame or none was presented.
int32_t mb_render_drawn_pixels(int32_t x, int32_t y, int32_t w, int32_t h, moonbit_bytes_t out) {
  if (!dev || !last_inst || w <= 0 || h <= 0 || x < 0 || y < 0) return 0;
  if ((size_t)Moonbit_array_length(out) < (size_t)w * h * 4) return 0;
  @autoreleasepool {
    int fw, fh;
    uint8_t *px = read_last(&fw, &fh);
    if (x + w > fw || y + h > fh) {
      free(px);
      return 0;
    }
    for (int r = 0; r < h; r++) {
      const uint8_t *s = px + ((size_t)(y + r) * fw + x) * 4;
      uint8_t *d = out + (size_t)r * w * 4;
      for (int k = 0; k < w; k++, s += 4, d += 4) {
        d[0] = s[2];
        d[1] = s[1];
        d[2] = s[0];
        d[3] = s[3];
      }
    }
    free(px);
  }
  return 1;
}

// Instances never presented (a shot's, mbui/src/ui/shot.mbt) drawn as a frame is, but `scale` pixels a point into a
// picture of their own w × h (their 0, 0 its top left), on the ground r, g, b, and its pixels into `out` as
// mb_render_drawn_pixels gives the frame's (the last frame kept as it was, the size frames are drawn at put back):
// 1 when read.
int32_t mb_render_pixels_of(const double *inst, int32_t count, double r, double g, double b, double scale, int32_t w,
                            int32_t h, moonbit_bytes_t out) {
  if (!dev || count < 0 || !(scale > 0) || w <= 0 || h <= 0) return 0;
  if ((size_t)Moonbit_array_length(out) < (size_t)w * h * 4) return 0;
  int ok = 0;
  @autoreleasepool {
    size_t n = (size_t)count * MB_INST;
    float *f = malloc((n > 0 ? n : MB_INST) * sizeof(float));
    for (size_t i = 0; i < n; i++) f[i] = (float)inst[i];
    double bg[3] = {r, g, b};
    // (drawn as a frame of that size is: read_of draws the size set, put back after)
    double kw = vw, kh = vh, ks = vscale;
    vscale = scale;
    vw = w / scale;
    vh = h / scale;
    int fw, fh;
    uint8_t *px = read_of(f, count, bg, 1, &fw, &fh);
    vw = kw;
    vh = kh;
    vscale = ks;
    free(f);
    if (fw == w && fh == h) {
      for (int k = 0; k < h; k++) {
        const uint8_t *s = px + (size_t)k * fw * 4;
        uint8_t *d = out + (size_t)k * w * 4;
        for (int j = 0; j < w; j++, s += 4, d += 4) {
          d[0] = s[2];
          d[1] = s[1];
          d[2] = s[0];
          d[3] = s[3];
        }
      }
      ok = 1;
    }
    free(px);
  }
  return ok;
}

// Pixels `px` (read_of's, w × h, freed here) into a PNG at `path`, the native views under them and the bands round
// them as the window shows them.
static int snapshot_of(uint8_t *px, int w, int h, const char *path) {
  size_t bpr = (size_t)w * 4;
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGContextRef ctx = CGBitmapContextCreate(px, w, h, 8, bpr, cs,
      kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
  CGImageRef img = CGBitmapContextCreateImage(ctx);
  if (mb_views_count() > 0) {
    // the native views' content under the canvas, seen through its holes
    CGContextRef under = CGBitmapContextCreate(NULL, w, h, 8, bpr, cs,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    double view_scale = mlayer && mlayer.contentsScale > 0 ? mlayer.contentsScale : vscale;
    mb_views_draw_under(under, view_scale);
    CGContextDrawImage(under, CGRectMake(0, 0, w, h), img);
    CGImageRelease(img);
    img = CGBitmapContextCreateImage(under);
    CGContextRelease(under);
  }
  if (band_top > 0 || band_bottom > 0) {
    // the window as it shows: the bands above and under the app's view in their ground
    int bt = (int)round(band_top * vscale), bb = (int)round(band_bottom * vscale);
    int fh = h + bt + bb;
    CGContextRef whole = CGBitmapContextCreate(NULL, w, fh, 8, bpr, cs,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGContextSetRGBFillColor(whole, ((band_ground >> 16) & 0xFF) / 255.0, ((band_ground >> 8) & 0xFF) / 255.0,
                             (band_ground & 0xFF) / 255.0, 1);
    CGContextFillRect(whole, CGRectMake(0, 0, w, fh));
    // (a bitmap context's y up: the bottom band first)
    CGContextDrawImage(whole, CGRectMake(0, bb, w, h), img);
    CGImageRelease(img);
    img = CGBitmapContextCreateImage(whole);
    CGContextRelease(whole);
  }
  CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, strlen(path), false);
  CGImageDestinationRef dst = CGImageDestinationCreateWithURL(url, CFSTR("public.png"), 1, NULL);
  int ok = 0;
  if (dst) {
    CGImageDestinationAddImage(dst, img, NULL);
    ok = CGImageDestinationFinalize(dst);
    CFRelease(dst);
  }
  CFRelease(url);
  CGImageRelease(img);
  CGContextRelease(ctx);
  CGColorSpaceRelease(cs);
  free(px);
  return ok;
}

int mb_render_snapshot(const char *path) {
  int w, h;
  uint8_t *px = read_last(&w, &h);
  return snapshot_of(px, w, h, path);
}

// The same last frame over a transparent ground, for an image used in another composition. Clear RGB to zero with
// alpha so the readback remains premultiplied; the window and video paths continue to clear opaque.
int mb_render_snapshot_transparent(const char *path) {
  int w, h;
  const double clear[3] = {0, 0, 0};
  uint8_t *px = read_of(last_inst, last_count, clear, 0, &w, &h);
  return snapshot_of(px, w, h, path);
}

static id<MTLTexture> off_target;

// The offscreen target as its frames left it (not the last frame drawn again: what drawing only the parts that
// differ made of it, mbui-render's MBUI_DL_FROM), as a PNG.
int mb_render_snapshot_drawn(const char *path) {
  if (!off_target) return 0;
  int w, h;
  uint8_t *px = read_texture(off_target, &w, &h);
  return snapshot_of(px, w, h, path);
}

// Without a window (the bench, src/bench): the renderer with no layer, and
// frames drawn into a texture kept across frames, the size a window's
// drawable would be, as nanoui's hill-climb draws its own (off_target, above);
// whether it holds the frame drawn last (partial redraw: draw_parts).
static int off_ok;

void mb_render_init_offscreen(double w, double h, double scale) {
  mb_render_init(nil);
  mb_render_set_size(w, h, scale);
  mb_text_set_scale(scale);
  MTLTextureDescriptor *td = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                   width:(NSUInteger)round(w * scale)
                                  height:(NSUInteger)round(h * scale)
                               mipmapped:NO];
  td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
  td.storageMode = MTLStorageModePrivate;
  off_target = [dev newTextureWithDescriptor:td];
}

// Draws a frame into the offscreen texture as a window's frame is drawn
// (the ring of buffers, one command buffer), waits for it and times it:
// out[0] the CPU time of uploading and encoding it, out[1] its GPU time
// (the command buffer's timestamps), in ms.
void mb_render_draw_timed(const double *inst, int32_t count, double r, double g, double b, double *out) {
  @autoreleasepool {
    dispatch_semaphore_wait(inflight, DISPATCH_TIME_FOREVER);
    double t0 = CACurrentMediaTime();
    id<MTLBuffer> buf = upload(inst, count, r, g, b);
    id<MTLCommandBuffer> cb = [queue commandBuffer];
    // (only the parts said to differ, as a window's canvas is drawn: the target is kept across frames too)
    draw_parts(cb, off_target, buf, count, r, g, b, off_ok);
    off_ok = 1;
    [cb commit];
    double t1 = CACurrentMediaTime();
    [cb waitUntilCompleted];
    out[0] = (t1 - t0) * 1000.0;
    out[1] = (cb.GPUEndTime - cb.GPUStartTime) * 1000.0;
    dispatch_semaphore_signal(inflight);
  }
}

// The GPU's time for the last frame presented that it finished (ms).
double mb_host_gpu_ms(void) { return last_gpu; }
