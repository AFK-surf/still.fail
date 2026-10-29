// Direct3D 11 renderer: one pipeline, one instanced quad per scene instance,
// the Metal/GLES shader in HLSL. Without a usable GPU (CI) the device is WARP.
// The canvas is a composition swap chain with alpha in a DirectComposition
// tree, over a visual the native views (win_views.cpp) go in: they show through
// the holes the app paints (kind 9, written transparent without blending), as
// on the other hosts. Where DirectComposition cannot be had, the swap chain is
// the window's own and there are no native views.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <dcomp.h>
#include <d3dcompiler.h>
#include <wincodec.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "win.h"
#include "corner_sl.h"

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "d3dcompiler.lib")
#pragma comment(lib, "dcomp.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "windowscodecs.lib")
#pragma comment(lib, "ole32.lib")

int mb_atlas_size = 2048;

static ID3D11Device *dev;
static ID3D11DeviceContext *ctx;
static IDXGISwapChain1 *chain;
static ID3D11RenderTargetView *rtv;
static ID3D11VertexShader *vs;
static ID3D11PixelShader *ps;
static ID3D11InputLayout *layout;
static ID3D11Buffer *vbuf, *ubuf;
static size_t vbuf_cap;
static ID3D11Texture2D *atlas;
static ID3D11ShaderResourceView *atlas_srv;
static ID3D11SamplerState *sampler;
static ID3D11BlendState *blend;
// the composition: its root, the native views' visual under the canvas's (NULL: the swap chain is the window's own)
static IDCompositionDevice *dcomp;
static IDCompositionTarget *dtarget;
static IDCompositionVisual *droot, *dunder, *dcanvas;
static ID3D11RasterizerState *raster, *raster_cut;
static int fb_w, fb_h;
// the swap chain is a flip model's (its Present1 takes the part that changed)
static int flip_chain;
static double vw = 800, vh = 600, vscale = 1;
// glass (src/ui/glass.mbt): its passes, their constants, the copies they work in (level j 1/2^j of the largest
// capture yet, the glass and the blur's margin round it, not of the target: a composer's strip, not the window; [4] a
// Gaussian's first half), the glass's own constants, the blurred copy in view
static ID3D11VertexShader *pvs;
static ID3D11PixelShader *pps;
static ID3D11Buffer *pbuf, *gbuf;
struct level { ID3D11Texture2D *t; ID3D11RenderTargetView *rtv; ID3D11ShaderResourceView *srv; int w, h; };
static level lv[5];
static int lv_w, lv_h;
struct GU { float map[4]; float uvc[4]; float gb[4]; float shape[8][4]; float rad[8][4]; float misc[4]; };
static GU gu;
static ID3D11ShaderResourceView *gsrv;
// the last frame, kept for snapshots (the vertex buffer still holds it) and
// to find the runs of each image
static int32_t last_count;
static float *last_inst;
static size_t last_cap;
static float last_bg[3];

// the numbers of an instance (src/ui/scene.mbt)
#define MB_INST 60

static const char *shader_src =
    "cbuffer U : register(b0) { float2 vp; float scale; float pad; };\n"
    "// glass (src/ui/glass.mbt): where a point is in the blurred copy under it (uv = p * gmap.xy + gmap.zw, kept in guvc),\n"
    "// a liquid group's bounds, shapes, corners (x of each), how many\n"
    "cbuffer G : register(b1) { float4 gmap; float4 guvc; float4 ggb; float4 gshape[8]; float4 grad[8]; float4 gmisc; };\n"
    "Texture2D atlas : register(t0);\n"
    "Texture2D img : register(t1);\n"
    "Texture2D bd : register(t2);\n"
    "// the pieces of the frame's shapes (src/ui/shape.mbt: the instances of kind 12 after every one drawn), 15 fours each\n"
    "Buffer<float4> segs : register(t3);\n"
    "SamplerState samp : register(s0);\n"
    "struct VIn { float4 rect : INST0; float4 p : INST1; float4 color : INST2; float4 c2 : INST3;\n"
    "  float4 clip : INST4; float4 pd : INST5; float4 rc : INST6; float4 rs : INST7; float4 rot : INST8;\n"
    "  float4 rr : INST9; float4 oclip : INST10; float4 orc : INST11; float4 ors : INST12; float4 fade : INST13; float4 fadex : INST14;\n"
    "  uint vid : SV_VertexID; };\n"
    "struct VOut { float4 pos : SV_Position; float2 p : POS; float2 cp : CPOS;\n"
    "  nointerpolation float4 rect : INST0; nointerpolation float4 prm : INST1;\n"
    "  nointerpolation float4 color : INST2; nointerpolation float4 c2 : INST3;\n"
    "  nointerpolation float4 clip : INST4; nointerpolation float4 pd : INST5; nointerpolation float4 rc : INST6;\n"
    "  nointerpolation float4 rs : INST7; nointerpolation float4 rr : INST8;\n"
    "  nointerpolation float4 oclip : INST9; nointerpolation float4 orc : INST10; nointerpolation float4 ors : INST11;\n"
    "  nointerpolation float4 fade : INST12; nointerpolation float4 fadex : INST13; };\n"
    "VOut vmain(VIn I) {\n"
    "  uint vid = I.vid;\n"
    "  float2 corner = float2((vid == 1 || vid == 4 || vid == 5) ? 1.0 : 0.0,\n"
    "                         (vid == 2 || vid == 3 || vid == 5) ? 1.0 : 0.0);\n"
    "  int kind = int(I.p.y + 0.5);\n"
    "  float grow = kind == 2 ? I.p.w * 3.0 + 2.0 : ((kind == 0 || kind == 4 || kind == 5) ? 1.0 : 0.0);\n"
    "  float2 pos = I.rect.xy - grow + corner * (I.rect.zw + 2.0 * grow);\n"
    "  if (kind == 6) pos = lerp(ggb.xy, ggb.zw, corner);\n"
    "  // the pieces of shapes (kind 12): nothing drawn\n"
    "  if (kind == 12) pos = float2(0.0, 0.0);\n"
    "  // turned (scene.mbt 32-35): drawn turned about its point, everything of how in its own place (o.p), its clip\n"
    "  // there too or (35: one from outside what turned) where it is drawn (o.cp)\n"
    "  float2 at = pos;\n"
    "  if (I.rot.x != 0.0) { float2 d = pos - I.rot.yz; float c = cos(I.rot.x), s = sin(I.rot.x);\n"
    "    at = I.rot.yz + float2(c * d.x - s * d.y, s * d.x + c * d.y); }\n"
    "  VOut o;\n"
    "  o.pos = float4(at.x / vp.x * 2.0 - 1.0, 1.0 - at.y / vp.y * 2.0, 0.0, 1.0);\n"
    "  o.p = pos; o.cp = I.rot.w > 0.5 ? at : pos; o.rect = I.rect; o.prm = I.p; o.color = I.color; o.c2 = I.c2; o.clip = I.clip; o.pd = I.pd; o.rc = I.rc; o.rs = I.rs; o.rr = I.rr;\n"
    "  o.oclip = I.oclip; o.orc = I.orc; o.ors = I.ors; o.fade = I.fade; o.fadex = I.fadex;\n"
    "  return o;\n"
    "}\n"
    MB_CORNER_SL
    "float sd_rr(float2 p, float4 r, float4 rad) {\n"
    "  float2 hs = r.zw * 0.5;\n"
    "  return mb_sd_box(p - r.xy - hs, hs, mb_corner_of(p - r.xy - hs, rad), 1e9);\n"
    "}\n"
    "// a notch cut into the top edge (scene.mbt 21-23): a circle about the top's middle (pad.y below it, pad.z its radius),\n"
    "// met by the edge through fillets (pad.w): the rounded intersection with what is outside the circle\n"
    "float notch_cut(float d, float2 p, float4 r, float4 pad) {\n"
    "  if (pad.z <= 0.0) return d;\n"
    "  float b = pad.z - length(p - float2(r.x + r.z * 0.5, r.y + pad.y));\n"
    "  float f = max(pad.w, 0.0);\n"
    "  float2 u = max(float2(f + d, f + b), 0.0);\n"
    "  return min(-f, max(d, b)) + length(u);\n"
    "}\n"
    "float smin_k(float a, float b, float k) {\n"
    "  if (k <= 0.0) return min(a, b);\n"
    "  float h = max(k - abs(a - b), 0.0) / k;\n"
    "  return min(a, b) - h * h * k * 0.25;\n"
    "}\n"
    "float sd_group(float2 p, float k) {\n"
    "  float d = 1e9;\n"
    "  int n = int(gmisc.x + 0.5);\n"
    "  [loop] for (int i = 0; i < 8; i++) {\n"
    "    if (i >= n) break;\n"
    "    d = smin_k(d, sd_rr(p, gshape[i], grad[i].xxxx), k);\n"
    "  }\n"
    "  return d;\n"
    "}\n"
    "float3 backdrop(float2 p) {\n"
    "  return bd.SampleLevel(samp, clamp(p * gmap.xy + gmap.zw, guvc.xy, guvc.zw), 0).rgb;\n"
    "}\n"
    "float luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }\n"
    "// how much of the pixel at p its rounded clip keeps (r: the corners' radii, top left, then clockwise; s: how smooth\n"
    "// each is), its edge covered as a box's own (0.5 - d * scale), so what it cuts meets the ground of the box that cuts\n"
    "// it\n"
    "float clip_cover(float2 p, float4 c, float4 r, float4 s, float sc) {\n"
    "  float2 hs = (c.zw - c.xy) * 0.5;\n"
    "  float2 m = c.xy + hs;\n"
    "  float rr = p.x < m.x ? (p.y < m.y ? r.x : r.w) : (p.y < m.y ? r.y : r.z);\n"
    "  float ss = p.x < m.x ? (p.y < m.y ? s.x : s.w) : (p.y < m.y ? s.y : s.z);\n"
    "  float d = mb_sd_corner(p - m, hs, min(rr, min(hs.x, hs.y)), ss, 1.0 + 2.0 / sc);\n"
    "  return saturate(0.5 - d * sc);\n"
    "}\n"
    "// A glyph's coverage, a pixel's three stripes each its own (ClearType: win_text.cpp draw_layout), blended stripe by\n"
    "// stripe as the second source (the blend's INV_SRC1_COLOR); what else is drawn, by its alpha as before. Every\n"
    "// target is cleared opaque (encode), so the stripes always fall on a ground of the pixel's own.\n"
    "static float3 stripes;\n"
    "static bool striped;\n"
    "float4 fmain0(VOut I);\n"
    "struct FOut { float4 c : SV_Target0; float4 w : SV_Target1; };\n"
    "FOut fmain(VOut I) {\n"
    "  striped = false;\n"
    "  FOut o;\n"
    "  o.c = fmain0(I);\n"
    "  o.w = striped ? float4(stripes, o.c.a) : o.c.aaaa;\n"
    "  return o;\n"
    "}\n"
    "float4 fmain0(VOut I) {\n"
    "  float2 p = I.p, cp = I.cp;\n"
    "  // cut to its clip: a rect's, hard; a rounded one's, covered as edges are\n"
    "  float cover = 1.0;\n"
    "  if (max(max(I.rc.x, I.rc.y), max(I.rc.z, I.rc.w)) > 0.0) {\n"
    "    cover = clip_cover(cp, I.clip, I.rc, I.rs, scale);\n"
    "    if (cover <= 0.0) discard;\n"
    "  } else if (cp.x < I.clip.x || cp.y < I.clip.y || cp.x > I.clip.z || cp.y > I.clip.w) discard;\n"
    "  // and by the clip outside it, where it has one (scene.mbt 40-51: a pane round an image's frame in its corner)\n"
    "  if (max(max(I.orc.x, I.orc.y), max(I.orc.z, I.orc.w)) > 0.0) {\n"
    "    cover *= clip_cover(cp, I.oclip, I.orc, I.ors, scale);\n"
    "    if (cover <= 0.0) discard;\n"
    "  }\n"
    "  // and faded out towards a cut, each pixel by where it is (scene.mbt 52-59)\n"
    "  if (I.fade.y > 0.0) cover *= saturate((cp.y - I.fade.x) / I.fade.y);\n"
    "  if (I.fade.w > 0.0) cover *= saturate((I.fade.z - cp.y) / I.fade.w);\n"
    "  if (I.fadex.y > 0.0) cover *= saturate((cp.x - I.fadex.x) / I.fadex.y);\n"
    "  if (I.fadex.w > 0.0) cover *= saturate((I.fadex.z - cp.x) / I.fadex.w);\n"
    "  if (cover <= 0.0) discard;\n"
    "  int kind = int(I.prm.y + 0.5);\n"
    "  if (kind == 9) { float2 hh = I.rect.zw * 0.5; float rr = min(mb_corner_of(p - I.rect.xy - hh, I.rr), min(hh.x, hh.y)); float2 q = abs(p - I.rect.xy - hh) - hh + rr; if (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rr > 0.0) discard; return (float4(0.0, 0.0, 0.0, 0.0)) * cover; }\n"
    "  float4 col = I.color;\n"
    "  if (kind == 11) {\n"
    "    // a band of a shape (src/ui/shape.mbt): c2.y of its pieces from c2.x; prm.x half its stroke's width (0: a fill,\n"
    "    // c2.z 1 by the even-odd rule)\n"
    "    int first = int(I.c2.x + 0.5), n = int(I.c2.y + 0.5);\n"
    "    float a;\n"
    "    if (I.prm.x > 0.0) {\n"
    "      float d = 1e9;\n"
    "      for (int i = first; i < first + n; i++) d = min(d, mb_seg_dist(segs.Load((i / 6) * 15 + mb_seg_slot(i)), I.rect, p));\n"
    "      a = saturate(0.5 - (d - I.prm.x) * scale);\n"
    "    } else {\n"
    "      float4 w = float4(0.0, 0.0, 0.0, 0.0);\n"
    "      for (int i = first; i < first + n; i++) w += mb_path_rows(segs.Load((i / 6) * 15 + mb_seg_slot(i)), I.rect, p, scale);\n"
    "      a = mb_path_cover(w, I.c2.z);\n"
    "    }\n"
    "    return (float4(col.rgb, 1.0) * col.a * a) * cover;\n"
    "  }\n"
    "  if (kind == 10) {\n"
    "    // a piece of a line (scene.mbt): from c2.xy to c2.zw (shares of its rect), prm.x half its width, its ends round\n"
    "    float2 a = I.rect.xy + I.c2.xy * I.rect.zw, ab = I.rect.xy + I.c2.zw * I.rect.zw - a;\n"
    "    float h = saturate(dot(p - a, ab) / max(dot(ab, ab), 1e-8));\n"
    "    float d = length(p - a - ab * h) - I.prm.x;\n"
    "    return (float4(col.rgb, 1.0) * col.a * saturate(0.5 - d * scale)) * cover;\n"
    "  }\n"
    "  if (kind == 1 || kind == 3 || kind == 7) {\n"
    "    // within its own cell (c2: where in the atlas, in texels), however its rect is stretched or turned: a sample\n"
    "    // past the cell's edge texels would blend in what lies beside it (another glyph, one left from before the atlas\n"
    "    // started over)\n"
    "    float2 uv = clamp(I.c2.xy + (p - I.rect.xy) / I.rect.zw * I.c2.zw, I.c2.xy + 0.5, I.c2.xy + I.c2.zw - 0.5) / 2048.0;\n"
    "    float4 t = atlas.SampleLevel(samp, uv, 0);\n"
    "    if (kind == 1) {\n"
    "      // (a mask drawn in gray has its three the same as its alpha: as before; a glyph drawn larger or smaller than\n"
    "      // its picture, its stripes no longer on the screen's: in gray, their mean)\n"
    "      float2 off = abs(I.rect.zw * scale - I.c2.zw);\n"
    "      float3 cov = max(off.x, off.y) > 0.5 ? t.aaa : t.rgb;\n"
    "      stripes = cov * (col.a * cover);\n"
    "      striped = true;\n"
    "      return float4(col.rgb * stripes, dot(stripes, float3(1.0, 1.0, 1.0) / 3.0));\n"
    "    }\n"
    "    if (kind == 7) {\n"
    "      // inked by how light what is under its glass is, looked at round the glass's middle\n"
    "      float2 c = I.pd.yz; float r = I.pd.w * 0.5;\n"
    "      float l = (luma(backdrop(c)) + luma(backdrop(c + float2(r, 0.0))) + luma(backdrop(c - float2(r, 0.0))) +\n"
    "                 luma(backdrop(c + float2(0.0, r))) + luma(backdrop(c - float2(0.0, r)))) / 5.0;\n"
    "      float3 ink = lerp(float3(1.0, 1.0, 1.0), float3(0.11, 0.11, 0.12), smoothstep(0.42, 0.6, l));\n"
    "      return (float4(ink, 1.0) * (t.a * col.a)) * cover;\n"
    "    }\n"
    "    return (t * col.a) * cover;\n"
    "  }\n"
    "  if (kind == 6) {\n"
    "    // liquid: one shape of the group's, merged; what is under it bent along the bezel, the colours split a little\n"
    "    float k = I.pd.w;\n"
    "    float d = sd_group(p, k);\n"
    "    float a = saturate(0.5 - d * scale);\n"
    "    if (a <= 0.0) discard;\n"
    "    float e = 0.5;\n"
    "    float2 grad2 = float2(sd_group(p + float2(e, 0.0), k) - sd_group(p - float2(e, 0.0), k),\n"
    "                          sd_group(p + float2(0.0, e), k) - sd_group(p - float2(0.0, e), k));\n"
    "    float2 n = grad2 / max(length(grad2), 1e-4);\n"
    "    float bezel = max(I.c2.y, 1.0);\n"
    "    float edge = 1.0 - saturate(-d / bezel);\n"
    "    float disp = I.pd.y * (1.0 - sqrt(max(1.0 - edge * edge, 0.0)));\n"
    "    float2 off = -n * disp;\n"
    "    float ch = I.pd.z;\n"
    "    float3 c = float3(backdrop(p + off * (1.0 + ch)).r, backdrop(p + off).g, backdrop(p + off * (1.0 - ch)).b);\n"
    "    float lc = luma(c);\n"
    "    c = max(lerp(float3(lc, lc, lc), c, I.prm.z), 0.0);\n"
    "    c = c * (1.0 - col.a) + col.rgb * col.a;\n"
    "    // the rim lit from the top left, and less across from it\n"
    "    float ndl = dot(n, float2(-0.6, -0.8));\n"
    "    float band = saturate(1.0 + d / 2.5);\n"
    "    float spec = I.c2.x * (band * (0.9 * pow(max(ndl, 0.0), 1.5) + 0.45 * pow(max(-ndl, 0.0), 1.5)) +\n"
    "                           0.3 * edge * edge * max(ndl, 0.0));\n"
    "    // the edge shaded, more on the side away from the light, so the shape reads over a light ground too\n"
    "    c *= 1.0 - I.c2.x * band * (0.1 + 0.25 * max(-ndl, 0.0));\n"
    "    c = c + (1.0 - c) * saturate(spec);\n"
    "    c += mb_dither(p * scale) / 255.0;\n"
    "    return (float4(c, 1.0) * (a * I.c2.w)) * cover;\n"
    "  }\n"
    "  float2 hs = I.rect.zw * 0.5;\n"
    "  float2 c = I.rect.xy + hs;\n"
    "  // worked out as near the curve as its cover, its edge or its blur reaches\n"
    "  float band = 1.0 + 2.0 / scale + (kind == 2 ? max(I.prm.w, 0.5) : max(I.prm.z, 0.0));\n"
    "  // (its corner by p: rr, each its own)\n"
    "  float rad = mb_corner_of(p - c, I.rr);\n"
    "  float d = mb_sd_box(p - c, hs, rad, band);\n"
    "  if (kind == 0 || kind == 5) d = notch_cut(d, p, I.rect, I.pd);\n"
    "  if (kind == 4) {\n"
    "    float2 uv = I.c2.xy + saturate((p - I.rect.xy) / I.rect.zw) * I.c2.zw;\n"
    "    return (img.SampleLevel(samp, uv, 0) * (col.a * saturate(0.5 - d * scale))) * cover;\n"
    "  }\n"
    "  if (kind == 2) {\n"
    "    // as Core Animation's: the shape blurred, sigma its radius (corner.sl mb_shadow)\n"
    "    float a = mb_shadow(p - c, hs, rad, max(I.prm.w, 0.25));\n"
    "    // glass's: only outside its box (c2.y above it)\n"
    "    if (I.c2.x > 0.5) {\n"
    "      float2 q = p - c + float2(0.0, I.c2.y);\n"
    "      float db = mb_sd_box(q, hs, mb_corner_of(q, I.rr), band);\n"
    "      a *= saturate(0.5 + db * scale);\n"
    "    }\n"
    "    return (float4(col.rgb, 1.0) * col.a * a) * cover;\n"
    "  }\n"
    "  float a = clamp(0.5 - d * scale, 0.0, 1.0);\n"
    "  if (kind == 5) {\n"
    "    // frosted: the blurred copy, saturated, the tint over it; the rim (a hairline inside the edge, the top left lit,\n"
    "    // the foot and right less), 0.5 wide\n"
    "    float3 g3 = backdrop(p);\n"
    "    float lg = luma(g3);\n"
    "    g3 = max(lerp(float3(lg, lg, lg), g3, I.prm.z), 0.0);\n"
    "    g3 = g3 * (1.0 - col.a) + col.rgb * col.a;\n"
    "    if (I.c2.x + I.c2.y + I.c2.z > 0.0) {\n"
    "      float edge = saturate(0.5 + (d + 0.5) * scale);\n"
    "      float lit = saturate(0.5 + notch_cut(sd_rr(p - 0.5, I.rect, I.rr), p - 0.5, I.rect, I.pd) * scale);\n"
    "      float back = saturate(0.5 + notch_cut(sd_rr(p + 0.5, I.rect, I.rr), p + 0.5, I.rect, I.pd) * scale);\n"
    "      g3 = lerp(g3, float3(1.0, 1.0, 1.0), I.c2.x * edge);\n"
    "      g3 = lerp(g3, float3(1.0, 1.0, 1.0), I.c2.y * lit);\n"
    "      g3 = lerp(g3, float3(1.0, 1.0, 1.0), I.c2.z * back);\n"
    "    }\n"
    "    // dithered as it is written to 8 bits, so its slopes do not band (corner.sl mb_dither)\n"
    "    g3 += mb_dither(p * scale) / 255.0;\n"
    "    return (float4(g3, 1.0) * (a * I.c2.w)) * cover;\n"
    "  }\n"
    "  float4 fill = float4(col.rgb, 1.0) * col.a;\n"
    "  float bw = I.prm.z;\n"
    "  if (bw > 0.0) {\n"
    "    float inner = clamp(0.5 - (d + bw) * scale, 0.0, 1.0);\n"
    "    float4 bc = float4(I.c2.rgb, 1.0) * I.c2.a;\n"
    "    fill = lerp(bc, fill, inner);\n"
    "  }\n"
    "  return (fill * a) * cover;\n"
    "}\n";

// glass's passes over its copy of what is under it
static const char *post_src =
    "// The backdrop's passes: pa.xy the source's texel, pa.z 1 halving (dual Kawase's down), 2 a Gaussian along pb.zw of\n"
    "// deviation pa.w (texels); pb.xy the last texel's centre of what the source holds\n"
    "cbuffer PU : register(b0) { float4 pa; float4 pb; };\n"
    "Texture2D src : register(t0);\n"
    "SamplerState samp : register(s0);\n"
    "float4 vpost(uint vid : SV_VertexID) : SV_Position {\n"
    "  return float4(vid == 1 ? 3.0 : -1.0, vid == 2 ? -3.0 : 1.0, 0.0, 1.0);\n"
    "}\n"
    "float4 fpost(float4 pos : SV_Position) : SV_Target {\n"
    "  float2 ts = pa.xy;\n"
    "  float2 lo = ts * 0.5, hi = pb.xy;\n"
    "  if (pa.z < 1.5) {\n"
    "    float2 uv = pos.xy * 2.0 * ts;\n"
    "    float4 s = src.SampleLevel(samp, clamp(uv, lo, hi), 0) * 4.0;\n"
    "    s += src.SampleLevel(samp, clamp(uv - ts, lo, hi), 0);\n"
    "    s += src.SampleLevel(samp, clamp(uv + ts, lo, hi), 0);\n"
    "    s += src.SampleLevel(samp, clamp(uv + float2(ts.x, -ts.y), lo, hi), 0);\n"
    "    s += src.SampleLevel(samp, clamp(uv + float2(-ts.x, ts.y), lo, hi), 0);\n"
    "    return s / 8.0;\n"
    "  }\n"
    "  float2 uv = pos.xy * ts;\n"
    "  float2 dir = pb.zw * ts;\n"
    "  float sg = pa.w;\n"
    "  float k = -0.5 / (sg * sg);\n"
    "  float4 s = src.SampleLevel(samp, clamp(uv, lo, hi), 0);\n"
    "  float wsum = 1.0;\n"
    "  int n = int(ceil(sg * 3.0));\n"
    "  [loop] for (int i = 1; i <= 64; i += 2) {\n"
    "    if (i > n) break;\n"
    "    float w1 = exp(float(i * i) * k), w2 = exp(float((i + 1) * (i + 1)) * k);\n"
    "    float w = w1 + w2;\n"
    "    float off = (float(i) * w1 + float(i + 1) * w2) / w;\n"
    "    s += (src.SampleLevel(samp, clamp(uv + dir * off, lo, hi), 0) + src.SampleLevel(samp, clamp(uv - dir * off, lo, hi), 0)) * w;\n"
    "    wsum += 2.0 * w;\n"
    "  }\n"
    "  return s / wsum;\n"
    "}\n";

static ID3DBlob *compile(const char *entry, const char *target, const char *src = shader_src) {
  ID3DBlob *code = NULL, *err = NULL;
  HRESULT hr = D3DCompile(src, strlen(src), "mbui", NULL, NULL, entry, target,
                          D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &code, &err);
  if (FAILED(hr)) fprintf(stderr, "shader %s: %s\n", entry, err ? (char *)err->GetBufferPointer() : "?");
  if (err) err->Release();
  return code;
}

static HRESULT make_device(D3D_DRIVER_TYPE type, UINT flags) {
  D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0};
  return D3D11CreateDevice(NULL, type, NULL, D3D11_CREATE_DEVICE_BGRA_SUPPORT | flags, levels, 3,
                           D3D11_SDK_VERSION, &dev, NULL, &ctx);
}

// The canvas as a composition swap chain (premultiplied alpha) on top of a DirectComposition tree whose other visual,
// under it, holds the native views; 0 (nothing made) where that cannot be had. MBUI_NO_DCOMP=1: not tried.
static int make_composed(IDXGIDevice1 *xdev, IDXGIFactory2 *factory, HWND hwnd) {
  const char *no = getenv("MBUI_NO_DCOMP");
  if (no && *no && *no != '0') return 0;
  RECT rc;
  GetClientRect(hwnd, &rc);
  DXGI_SWAP_CHAIN_DESC1 sd = {};
  sd.Width = rc.right > 0 ? (UINT)rc.right : 1;
  sd.Height = rc.bottom > 0 ? (UINT)rc.bottom : 1;
  sd.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  sd.SampleDesc.Count = 1;
  sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
  sd.BufferCount = 2;
  sd.Scaling = DXGI_SCALING_STRETCH;
  sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
  sd.AlphaMode = DXGI_ALPHA_MODE_PREMULTIPLIED;
  HRESULT hr = DCompositionCreateDevice(xdev, __uuidof(IDCompositionDevice), (void **)&dcomp);
  if (SUCCEEDED(hr)) hr = dcomp->CreateTargetForHwnd(hwnd, TRUE, &dtarget);
  if (SUCCEEDED(hr)) hr = factory->CreateSwapChainForComposition(dev, &sd, NULL, &chain);
  if (SUCCEEDED(hr)) hr = dcomp->CreateVisual(&droot);
  if (SUCCEEDED(hr)) hr = dcomp->CreateVisual(&dunder);
  if (SUCCEEDED(hr)) hr = dcomp->CreateVisual(&dcanvas);
  if (SUCCEEDED(hr)) hr = dcanvas->SetContent(chain);
  if (SUCCEEDED(hr)) hr = droot->AddVisual(dunder, FALSE, NULL);
  if (SUCCEEDED(hr)) hr = droot->AddVisual(dcanvas, TRUE, dunder);
  if (SUCCEEDED(hr)) hr = dtarget->SetRoot(droot);
  if (SUCCEEDED(hr)) hr = dcomp->Commit();
  if (SUCCEEDED(hr)) {
    fb_w = (int)sd.Width;
    fb_h = (int)sd.Height;
    return 1;
  }
  fprintf(stderr, "no DirectComposition (0x%08lx): the window's own swap chain, no native views\n", (unsigned long)hr);
  if (dcanvas) dcanvas->Release();
  if (dunder) dunder->Release();
  if (droot) droot->Release();
  if (chain) chain->Release();
  if (dtarget) dtarget->Release();
  if (dcomp) dcomp->Release();
  dcanvas = dunder = droot = NULL;
  chain = NULL;
  dtarget = NULL;
  dcomp = NULL;
  return 0;
}

static void make_pipeline(void);

int mb_render_init(void *hwnd) {
  // (with its video side where the GPU has one: a remote screen decoded and shown by the GPU, win_stream.cpp)
  if (FAILED(make_device(D3D_DRIVER_TYPE_HARDWARE, D3D11_CREATE_DEVICE_VIDEO_SUPPORT)) &&
      FAILED(make_device(D3D_DRIVER_TYPE_HARDWARE, 0)) && FAILED(make_device(D3D_DRIVER_TYPE_WARP, 0))) {
    fprintf(stderr, "no Direct3D 11 device\n");
    return 0;
  }
  IDXGIDevice1 *xdev = NULL;
  IDXGIAdapter *adapter = NULL;
  IDXGIFactory2 *factory = NULL;
  dev->QueryInterface(__uuidof(IDXGIDevice1), (void **)&xdev);
  xdev->SetMaximumFrameLatency(1);  // input to photon over throughput
  xdev->GetAdapter(&adapter);
  adapter->GetParent(__uuidof(IDXGIFactory2), (void **)&factory);
  DXGI_SWAP_CHAIN_DESC1 sd = {};
  sd.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  sd.SampleDesc.Count = 1;
  sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
  sd.BufferCount = 2;
  sd.Scaling = DXGI_SCALING_NONE;
  sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
  flip_chain = 1;
  if (make_composed(xdev, factory, (HWND)hwnd)) {
    // the composition's swap chain, made at the window's size (its first buffers' view: at the first frame's size)
    fb_w = fb_h = 0;
  } else if (FAILED(factory->CreateSwapChainForHwnd(dev, (HWND)hwnd, &sd, NULL, NULL, &chain))) {
    // before Windows 10
    sd.Scaling = DXGI_SCALING_STRETCH;
    sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
    sd.BufferCount = 1;
    flip_chain = 0;
    factory->CreateSwapChainForHwnd(dev, (HWND)hwnd, &sd, NULL, NULL, &chain);
  }
  factory->MakeWindowAssociation((HWND)hwnd, DXGI_MWA_NO_ALT_ENTER);
  factory->Release();
  adapter->Release();
  xdev->Release();
  make_pipeline();
  return chain != NULL;
}

// The shaders, buffers, atlas and states every target is drawn with (the window's, the offscreen one).
static void make_pipeline(void) {
  ID3DBlob *vcode = compile("vmain", "vs_4_0"), *pcode = compile("fmain", "ps_4_0");
  dev->CreateVertexShader(vcode->GetBufferPointer(), vcode->GetBufferSize(), NULL, &vs);
  dev->CreatePixelShader(pcode->GetBufferPointer(), pcode->GetBufferSize(), NULL, &ps);
  // the instance's fifteen float4s (scene.mbt): rect, p, color, c2, clip, pad, the clip's corners' radii, how smooth,
  // how it is turned, a box's corners' radii, the outer clip's rect, corners' radii and how smooth, how it fades down
  // and across
  D3D11_INPUT_ELEMENT_DESC el[15];
  for (UINT i = 0; i < 15; i++)
    el[i] = {"INST", i, DXGI_FORMAT_R32G32B32A32_FLOAT, 0, i * 16, D3D11_INPUT_PER_INSTANCE_DATA, 1};
  dev->CreateInputLayout(el, 15, vcode->GetBufferPointer(), vcode->GetBufferSize(), &layout);
  vcode->Release();
  pcode->Release();
  ID3DBlob *pv = compile("vpost", "vs_4_0", post_src), *pp = compile("fpost", "ps_4_0", post_src);
  dev->CreateVertexShader(pv->GetBufferPointer(), pv->GetBufferSize(), NULL, &pvs);
  dev->CreatePixelShader(pp->GetBufferPointer(), pp->GetBufferSize(), NULL, &pps);
  pv->Release();
  pp->Release();

  D3D11_BUFFER_DESC ud = {16, D3D11_USAGE_DEFAULT, D3D11_BIND_CONSTANT_BUFFER, 0, 0, 0};
  dev->CreateBuffer(&ud, NULL, &ubuf);
  D3D11_BUFFER_DESC pd = {32, D3D11_USAGE_DEFAULT, D3D11_BIND_CONSTANT_BUFFER, 0, 0, 0};
  dev->CreateBuffer(&pd, NULL, &pbuf);
  D3D11_BUFFER_DESC gd = {(UINT)sizeof(GU), D3D11_USAGE_DEFAULT, D3D11_BIND_CONSTANT_BUFFER, 0, 0, 0};
  dev->CreateBuffer(&gd, NULL, &gbuf);

  D3D11_TEXTURE2D_DESC td = {};
  td.Width = td.Height = (UINT)mb_atlas_size;
  td.MipLevels = td.ArraySize = 1;
  td.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
  td.SampleDesc.Count = 1;
  td.Usage = D3D11_USAGE_DEFAULT;
  td.BindFlags = D3D11_BIND_SHADER_RESOURCE;
  dev->CreateTexture2D(&td, NULL, &atlas);
  dev->CreateShaderResourceView(atlas, NULL, &atlas_srv);

  D3D11_SAMPLER_DESC smp = {};
  smp.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
  smp.AddressU = smp.AddressV = smp.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
  smp.MaxLOD = D3D11_FLOAT32_MAX;
  dev->CreateSamplerState(&smp, &sampler);

  // premultiplied alpha, as on Metal and GLES
  D3D11_BLEND_DESC bd = {};
  D3D11_RENDER_TARGET_BLEND_DESC &b = bd.RenderTarget[0];
  b.BlendEnable = TRUE;
  b.SrcBlend = b.SrcBlendAlpha = D3D11_BLEND_ONE;
  b.DestBlend = D3D11_BLEND_INV_SRC1_COLOR;
  b.DestBlendAlpha = D3D11_BLEND_INV_SRC1_ALPHA;
  b.BlendOp = b.BlendOpAlpha = D3D11_BLEND_OP_ADD;
  b.RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
  dev->CreateBlendState(&bd, &blend);

  D3D11_RASTERIZER_DESC rd = {};
  rd.FillMode = D3D11_FILL_SOLID;
  rd.CullMode = D3D11_CULL_NONE;
  rd.DepthClipEnable = TRUE;
  dev->CreateRasterizerState(&rd, &raster);
  // (a part drawn again: cut to it, docs/partial-redraw.md)
  rd.ScissorEnable = TRUE;
  dev->CreateRasterizerState(&rd, &raster_cut);
}

void *mb_render_device(void) { return dev; }
void *mb_render_context(void) { return ctx; }

void *mb_render_dcomp(void) { return dcomp; }
void *mb_render_views_visual(void) { return dunder; }
void mb_render_commit(void) {
  if (dcomp) dcomp->Commit();
}

// A view placed (win_views.cpp apply_place) is committed with the frame that paints its hole where it now is: just
// after that frame's Present, both then taken by the same composition. Committed as it was placed, the view moved a
// frame ahead of its hole while a list scrolled, the window's black showing along its edge in the hole (2026-10-29).
static bool commit_after_present;
extern "C" void mb_host_request_frame(void);
void mb_render_commit_with_frame(void) {
  commit_after_present = true;
  mb_host_request_frame();
}
void mb_render_commit_soon(void) {
  if (!commit_after_present) mb_render_commit();
}
static void commit_presented(void) {
  if (!commit_after_present) return;
  commit_after_present = false;
  mb_render_commit();
}

static void ensure_canvas(int tw, int th);

void mb_render_set_size(int pw, int ph, double w, double h, double scale) {
  vw = w;
  vh = h;
  vscale = scale;
  if (!chain || (pw == fb_w && ph == fb_h && rtv)) return;
  if (rtv) rtv->Release();
  rtv = NULL;
  ctx->OMSetRenderTargets(0, NULL, NULL);
  ensure_canvas(0, 0);
  chain->ResizeBuffers(0, (UINT)pw, (UINT)ph, DXGI_FORMAT_UNKNOWN, 0);
  ID3D11Texture2D *back = NULL;
  if (SUCCEEDED(chain->GetBuffer(0, __uuidof(ID3D11Texture2D), (void **)&back))) {
    dev->CreateRenderTargetView(back, NULL, &rtv);
    back->Release();
  }
  fb_w = pw;
  fb_h = ph;
}

void mb_atlas_upload(int x, int y, int w, int h, const void *rgba) {
  D3D11_BOX box = {(UINT)x, (UINT)y, 0, (UINT)(x + w), (UINT)(y + h), 1};
  ctx->UpdateSubresource(atlas, 0, &box, rgba, (UINT)w * 4, 0);
}

// ---------------------------------------------------------------------------
// Glass: when the instances reach a run of glass (slot 20 negative: the capture it shares), what is drawn so far
// under it (its rects with room for the blur round them) is copied out, halved down to where the blur is a few texels
// wide (dual Kawase's downsample, at most 1/8), blurred there by a Gaussian of what deviation is left, and drawn
// through. Level 0, the copy, has 8 bits a channel as the target has; what the passes write keeps 10 (R10G10B10A2, in
// as many bytes): at 8 each pass rounds the frost's slow slopes into flat steps, a texel of the last level 8 pixels
// wide on the screen (a blur under 4 pixels, too narrow to halve, is written back into the copy: it leaves no slope
// that wide).

static level level_tex(DXGI_FORMAT format, int w, int h) {
  level l = {NULL, NULL, NULL, w > 0 ? w : 1, h > 0 ? h : 1};
  D3D11_TEXTURE2D_DESC td = {};
  td.Width = (UINT)l.w;
  td.Height = (UINT)l.h;
  td.MipLevels = td.ArraySize = 1;
  td.Format = format;
  td.SampleDesc.Count = 1;
  td.Usage = D3D11_USAGE_DEFAULT;
  td.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  dev->CreateTexture2D(&td, NULL, &l.t);
  dev->CreateRenderTargetView(l.t, NULL, &l.rtv);
  dev->CreateShaderResourceView(l.t, NULL, &l.srv);
  return l;
}

static void ensure_levels(int w, int h) {
  if (lv[0].t && lv_w >= w && lv_h >= h) return;
  for (int j = 0; j < 5; j++)
    if (lv[j].t) {
      lv[j].srv->Release();
      lv[j].rtv->Release();
      lv[j].t->Release();
    }
  lv_w = w > lv_w ? w : lv_w;
  lv_h = h > lv_h ? h : lv_h;
  for (int j = 0; j < 4; j++)
    lv[j] = level_tex(j == 0 ? DXGI_FORMAT_B8G8R8A8_UNORM : DXGI_FORMAT_R10G10B10A2_UNORM, (lv_w + (1 << j) - 1) >> j,
                      (lv_h + (1 << j) - 1) >> j);
  lv[4] = level_tex(DXGI_FORMAT_R10G10B10A2_UNORM, lv_w, lv_h);
}

static void post_pass(level *src, int sw, int sh, level *dst, int w, int h, int mode, float sg, float dx, float dy) {
  ID3D11ShaderResourceView *none[3] = {NULL, NULL, NULL};
  ctx->PSSetShaderResources(0, 3, none);
  ctx->OMSetRenderTargets(1, &dst->rtv, NULL);
  D3D11_VIEWPORT vp = {0, 0, (float)w, (float)h, 0, 1};
  ctx->RSSetViewports(1, &vp);
  float u[8] = {1.0f / src->w, 1.0f / src->h, (float)mode, sg, (sw - 0.5f) / src->w, (sh - 0.5f) / src->h, dx, dy};
  ctx->UpdateSubresource(pbuf, 0, NULL, u, 0, 0);
  ctx->PSSetConstantBuffers(0, 1, &pbuf);
  ctx->PSSetShaderResources(0, 1, &src->srv);
  ctx->Draw(3, 0);
}

// Partial redraw (docs/partial-redraw.md): a window's frame is drawn into a canvas of its own, kept across frames, and
// copied into the swap chain's buffer (a flip model's holds a frame before the last); where the app says only some
// parts differ from the frame before (@hostapi.render_dirty), only those parts of the canvas are drawn again, each cut
// to it (the scissor, `cut`, while `cut_on`), the frame's ground over it first (the instance after the frame's,
// submit's), then every instance. Without a window the offscreen target is the canvas.
static ID3D11Texture2D *canvas;
static ID3D11RenderTargetView *canvas_rtv;
static int canvas_w, canvas_h;
// what the canvas holds is the last frame given; what the offscreen target holds, the frame drawn last
static int canvas_ok, off_ok;
// the parts of the next frame that differ (points: x, y, w, h), all of it (`dirty_whole`), and whether any was said
#define MB_PARTS 8
static double dirty[MB_PARTS][4];
static int dirty_n, dirty_whole, dirty_told;
// a picture the frame drawn last had none of yet (drawn without it): the next drawn whole
static int pictures_missing, encode_missing;
static int cut_on;
static D3D11_RECT cut;

extern "C" void mb_host_render_dirty(double x, double y, double w, double h) {
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
static int take_parts(int tw, int th, int kept, D3D11_RECT r[MB_PARTS]) {
  int told = dirty_told, whole = dirty_whole, n = dirty_n;
  dirty_told = dirty_whole = dirty_n = 0;
  if (!told || whole || !kept || pictures_missing) return -1;
  int k = 0;
  for (int i = 0; i < n; i++) {
    // (whole pixels round it, and one more)
    int x0 = (int)floor(dirty[i][0] * vscale) - 1, y0 = (int)floor(dirty[i][1] * vscale) - 1;
    int x1 = (int)ceil((dirty[i][0] + dirty[i][2]) * vscale) + 1, y1 = (int)ceil((dirty[i][1] + dirty[i][3]) * vscale) + 1;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > tw) x1 = tw;
    if (y1 > th) y1 = th;
    if (x1 > x0 && y1 > y0) r[k++] = {x0, y0, x1, y1};
  }
  return k;
}

// The canvas a window's frames are drawn into, tw × th pixels: made again at another size, what it held lost.
static void ensure_canvas(int tw, int th) {
  if (canvas && canvas_w == tw && canvas_h == th) return;
  if (canvas_rtv) canvas_rtv->Release();
  if (canvas) canvas->Release();
  canvas = NULL;
  canvas_rtv = NULL;
  canvas_ok = 0;
  canvas_w = tw;
  canvas_h = th;
  if (tw <= 0 || th <= 0) return;
  D3D11_TEXTURE2D_DESC td = {};
  td.Width = (UINT)tw;
  td.Height = (UINT)th;
  td.MipLevels = td.ArraySize = 1;
  td.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  td.SampleDesc.Count = 1;
  td.Usage = D3D11_USAGE_DEFAULT;
  td.BindFlags = D3D11_BIND_RENDER_TARGET;
  if (FAILED(dev->CreateTexture2D(&td, NULL, &canvas))) {
    canvas = NULL;
    return;
  }
  if (FAILED(dev->CreateRenderTargetView(canvas, NULL, &canvas_rtv))) {
    canvas->Release();
    canvas = NULL;
    canvas_rtv = NULL;
  }
}

// what the run [start, end) of glass sees, from target (pw × ph) into gsrv and gu, frosted glass of the same capture
// further on (glass.mbt shares_capture) too; 0 when none of it shows
static int capture(ID3D11RenderTargetView *target, int pw, int ph, const float *f, int32_t start, int32_t end,
                   int32_t count) {
  const float *a = f + start * MB_INST;
  float blur = a[7];
  int kind = (int)(a[5] + 0.5f);
  float margin = 3.0f * blur + (kind == 6 ? a[21] * (1.0f + a[22]) + a[23] : 0.0f) + 2.0f;
  float x0 = 1e9f, y0 = 1e9f, x1 = -1e9f, y1 = -1e9f;
  int n = 0;
  for (int32_t i = start; i < end; i++) {
    const float *b = f + i * MB_INST;
    float bx0 = b[0] > b[16] ? b[0] : b[16], by0 = b[1] > b[17] ? b[1] : b[17];
    float bx1 = b[0] + b[2] < b[18] ? b[0] + b[2] : b[18], by1 = b[1] + b[3] < b[19] ? b[1] + b[3] : b[19];
    if (kind == 6) {
      bx0 = b[0] - a[23]; by0 = b[1] - a[23]; bx1 = b[0] + b[2] + a[23]; by1 = b[1] + b[3] + a[23];
      if (n < 8) {
        for (int k = 0; k < 4; k++) gu.shape[n][k] = b[k];
        gu.rad[n][0] = b[4];
        n++;
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
  gu.misc[0] = (float)n;
  gu.gb[0] = x0 - 2; gu.gb[1] = y0 - 2; gu.gb[2] = x1 + 2; gu.gb[3] = y1 + 2;
  float sc = (float)vscale;
  int px0 = (int)floorf((x0 - margin) * sc), py0 = (int)floorf((y0 - margin) * sc);
  int px1 = (int)ceilf((x1 + margin) * sc), py1 = (int)ceilf((y1 + margin) * sc);
  if (px0 < 0) px0 = 0;
  if (py0 < 0) py0 = 0;
  if (px1 > pw) px1 = pw;
  if (py1 > ph) py1 = ph;
  if (px1 <= px0 || py1 <= py0 || x1 <= x0 || y1 <= y0) return 0;
  // (a capture outside the part drawn: neither copied nor drawn. One that meets it is in it whole: @damage)
  if (cut_on && (px1 <= cut.left || cut.right <= px0 || py1 <= cut.top || cut.bottom <= py0)) return 0;
  int w = px1 - px0, h = py1 - py0;
  ensure_levels(w, h);
  ID3D11Resource *res = NULL;
  target->GetResource(&res);
  D3D11_BOX box = {(UINT)px0, (UINT)py0, 0, (UINT)px1, (UINT)py1, 1};
  ctx->CopySubresourceRegion(lv[0].t, 0, 0, 0, 0, res, 0, &box);
  res->Release();
  ctx->VSSetShader(pvs, NULL, 0);
  ctx->PSSetShader(pps, NULL, 0);
  ctx->IASetInputLayout(NULL);
  ctx->OMSetBlendState(NULL, NULL, 0xffffffff);
  // (the passes over the levels whole, not cut to the part)
  ctx->RSSetState(raster);
  float sp = blur * sc;
  int k = 0;
  while (k < 3 && sp / (float)(1 << (k + 1)) >= 2.0f) k++;
  int lw[4] = {w}, lh[4] = {h};
  for (int j = 1; j <= k; j++) {
    lw[j] = (lw[j - 1] + 1) / 2;
    lh[j] = (lh[j - 1] + 1) / 2;
    post_pass(&lv[j - 1], lw[j - 1], lh[j - 1], &lv[j], lw[j], lh[j], 1, 0, 0, 0);
  }
  // what is left of the deviation once the halvings' and the last look's (bilinear) spread are taken out
  float sk = sp / (float)(1 << k);
  float pre = k > 0 ? 0.75f * (1.0f - powf(0.25f, (float)k)) / 3.0f + 1.0f / 6.0f : 0.0f;
  float sg = sqrtf(sk * sk - pre > 0 ? sk * sk - pre : 0);
  if (sg > 0.3f) {
    post_pass(&lv[k], lw[k], lh[k], &lv[4], lw[k], lh[k], 2, sg, 1, 0);
    post_pass(&lv[4], lw[k], lh[k], &lv[k], lw[k], lh[k], 2, sg, 0, 1);
  }
  ID3D11ShaderResourceView *none[3] = {NULL, NULL, NULL};
  ctx->PSSetShaderResources(0, 3, none);
  level *L = &lv[k];
  float d = (float)(1 << k);
  gsrv = L->srv;
  gu.map[0] = sc / d / L->w; gu.map[1] = sc / d / L->h;
  gu.map[2] = -(float)px0 / d / L->w; gu.map[3] = -(float)py0 / d / L->h;
  gu.uvc[0] = 0.5f / L->w; gu.uvc[1] = 0.5f / L->h; gu.uvc[2] = (lw[k] - 0.5f) / L->w; gu.uvc[3] = (lh[k] - 0.5f) / L->h;
  return 1;
}

// The pieces of the frame's shapes (src/ui/shape.mbt: the instances of kind 12 after every one drawn), for the pixel
// shader to read (segs, t3): as they are, 15 fours an instance.
static ID3D11Buffer *segs_buf;
static ID3D11ShaderResourceView *segs_srv;
static size_t segs_cap;

static void segs_upload(const float *f, int32_t count) {
  int32_t d = count;
  while (d > 0 && (int)(f[(d - 1) * MB_INST + 5] + 0.5f) == 12) d--;
  if (d == count) return;
  size_t need = (size_t)(count - d) * MB_INST * sizeof(float);
  if (segs_cap < need) {
    if (segs_srv) segs_srv->Release();
    if (segs_buf) segs_buf->Release();
    segs_srv = NULL;
    segs_cap = need * 2;
    D3D11_BUFFER_DESC bd = {(UINT)segs_cap, D3D11_USAGE_DYNAMIC, D3D11_BIND_SHADER_RESOURCE, D3D11_CPU_ACCESS_WRITE, 0, 0};
    if (FAILED(dev->CreateBuffer(&bd, NULL, &segs_buf))) {
      segs_buf = NULL;
      segs_cap = 0;
      return;
    }
    D3D11_SHADER_RESOURCE_VIEW_DESC sd = {};
    sd.Format = DXGI_FORMAT_R32G32B32A32_FLOAT;
    sd.ViewDimension = D3D11_SRV_DIMENSION_BUFFER;
    sd.Buffer.FirstElement = 0;
    sd.Buffer.NumElements = (UINT)(segs_cap / 16);
    dev->CreateShaderResourceView(segs_buf, &sd, &segs_srv);
  }
  D3D11_MAPPED_SUBRESOURCE m;
  if (FAILED(ctx->Map(segs_buf, 0, D3D11_MAP_WRITE_DISCARD, 0, &m))) return;
  memcpy(m.pData, f + (size_t)d * MB_INST, need);
  ctx->Unmap(segs_buf, 0);
}

// the main pipeline's state, at the start and after the passes
static void main_state(ID3D11RenderTargetView *target, int pw, int ph) {
  D3D11_VIEWPORT vp = {0, 0, (float)pw, (float)ph, 0, 1};
  UINT stride = MB_INST * sizeof(float), off = 0;
  ctx->OMSetRenderTargets(1, &target, NULL);
  ctx->RSSetViewports(1, &vp);
  ctx->RSSetState(cut_on ? raster_cut : raster);
  if (cut_on) ctx->RSSetScissorRects(1, &cut);
  ctx->IASetInputLayout(layout);
  ctx->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  ctx->IASetVertexBuffers(0, 1, &vbuf, &stride, &off);
  ctx->UpdateSubresource(gbuf, 0, NULL, &gu, 0, 0);
  ID3D11Buffer *cbs[2] = {ubuf, gbuf};
  ctx->VSSetShader(vs, NULL, 0);
  ctx->VSSetConstantBuffers(0, 2, cbs);
  ctx->PSSetShader(ps, NULL, 0);
  ctx->PSSetConstantBuffers(0, 2, cbs);
  ctx->PSSetShaderResources(0, 1, &atlas_srv);
  ctx->PSSetShaderResources(2, 1, gsrv ? &gsrv : &atlas_srv);
  ctx->PSSetShaderResources(3, 1, &segs_srv);
  ctx->PSSetSamplers(0, 1, &sampler);
  ctx->OMSetBlendState(blend, NULL, 0xffffffff);
}

// `part`: only that part of the target drawn again, over what it holds (the frame's ground first: the instance after
// the frame's in the vertex buffer, submit's); NULL, all of it, cleared to the ground.
static void encode(ID3D11RenderTargetView *target, int pw, int ph, int32_t count, const float *bg,
                   const float *f, const D3D11_RECT *part = NULL) {
  float clear[4] = {bg[0], bg[1], bg[2], 1};
  encode_missing = 0;
  ctx->OMSetRenderTargets(1, &target, NULL);
  cut_on = part != NULL;
  if (part) cut = *part;
  else ctx->ClearRenderTargetView(target, clear);
  if (count <= 0 && !part) return;
  struct { float vp[2]; float scale; float pad; } u = {{(float)vw, (float)vh}, (float)vscale, 0};
  ctx->UpdateSubresource(ubuf, 0, NULL, &u, 0, 0);
  memset(&gu, 0, sizeof gu);
  gsrv = NULL;
  segs_upload(f, count);
  main_state(target, pw, ph);
  if (part) {
    ctx->OMSetBlendState(NULL, NULL, 0xffffffff);
    ctx->DrawInstanced(6, 1, 0, (UINT)count);
    ctx->OMSetBlendState(blend, NULL, 0xffffffff);
  }
  // one draw per run of instances showing the same image (slot 20; 0: none, the atlas stands in), or sharing one
  // capture of glass (negative)
  int32_t start = 0;
  int bound = 0, shows = 0;
  while (start < count) {
    int tid = (int)f[start * MB_INST + 20];
    int32_t end = start + 1;
    while (end < count && (int)f[end * MB_INST + 20] == tid) end++;
    if (tid < 0) {
      if (tid != bound) {
        shows = capture(target, pw, ph, f, start, end, count);
        bound = tid;
        main_state(target, pw, ph);
      }
      // liquid: the group as one shape, drawn once
      if (shows) ctx->DrawInstanced(6, (int)(f[start * MB_INST + 5] + 0.5f) == 6 ? 1 : (UINT)(end - start), 0, (UINT)start);
      start = end;
      continue;
    }
    // holes for native views (kind 9) apart, written without blending: transparent there
    int hole = (int)(f[start * MB_INST + 5] + 0.5f) == 9;
    end = start + 1;
    while (end < count && (int)f[end * MB_INST + 20] == tid && ((int)(f[end * MB_INST + 5] + 0.5f) == 9) == hole) end++;
    // (a hole's image is its view's, src/hostapi/host.mbt view_tex_base + its id: the view is under the canvas here)
    ID3D11ShaderResourceView *t = hole ? atlas_srv
                                  : tid > MB_STREAM_TEX ? (ID3D11ShaderResourceView *)mb_stream_srv(tid - MB_STREAM_TEX)
                                  : tid ? (ID3D11ShaderResourceView *)mb_image_srv(tid) : atlas_srv;
    // (a stream with no frame of its own yet: nothing, not the atlas)
    if (!hole && tid > MB_STREAM_TEX && !t) {
      start = end;
      continue;
    }
    if (!hole && tid > 0 && tid <= MB_STREAM_TEX && !t) encode_missing = 1;
    ctx->PSSetShaderResources(1, 1, t ? &t : &atlas_srv);
    if (hole) ctx->OMSetBlendState(NULL, NULL, 0xffffffff);
    ctx->DrawInstanced(6, (UINT)(end - start), 0, (UINT)start);
    if (hole) ctx->OMSetBlendState(blend, NULL, 0xffffffff);
    start = end;
  }
  if (cut_on) ctx->RSSetState(raster);
  cut_on = 0;
}

// The frame's instances into the vertex buffer and kept (a snapshot draws them again), then drawn into the target: a
// window's (`chain`) into the canvas, only the parts that differ where it holds the frame before; how many in
// `parts_out` (-1 all of it, 0 none), the parts in `cuts`.
static int submit(const double *inst, int32_t count, double r, double g, double b, int *parts_out = NULL,
                  D3D11_RECT *cuts = NULL) {
  if (!rtv) return 0;
  size_t need = (size_t)(count > 0 ? count : 1) * MB_INST * sizeof(float);
  // (and the frame's ground after its instances: a rect over all the window, opaque, a part drawn again first)
  size_t room = need + MB_INST * sizeof(float);
  if (vbuf_cap < room) {
    if (vbuf) vbuf->Release();
    vbuf_cap = room * 2;
    D3D11_BUFFER_DESC bd = {(UINT)vbuf_cap, D3D11_USAGE_DYNAMIC, D3D11_BIND_VERTEX_BUFFER,
                            D3D11_CPU_ACCESS_WRITE, 0, 0};
    dev->CreateBuffer(&bd, NULL, &vbuf);
  }
  D3D11_MAPPED_SUBRESOURCE m;
  if (FAILED(ctx->Map(vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, &m))) return 0;
  float *f = (float *)m.pData;
  int32_t n = count * MB_INST;
  if (last_cap < need) {
    last_cap = need * 2;
    last_inst = (float *)realloc(last_inst, last_cap);
  }
  for (int32_t i = 0; i < n; i++) last_inst[i] = (float)inst[i];
  memcpy(f, last_inst, (size_t)n * sizeof(float));
  float *gr = f + n;
  memset(gr, 0, MB_INST * sizeof(float));
  gr[0] = -16.0f; gr[1] = -16.0f; gr[2] = (float)vw + 32.0f; gr[3] = (float)vh + 32.0f;
  gr[8] = (float)r; gr[9] = (float)g; gr[10] = (float)b; gr[11] = 1.0f;
  gr[16] = -1e9f; gr[17] = -1e9f; gr[18] = 1e9f; gr[19] = 1e9f;
  ctx->Unmap(vbuf, 0);
  last_count = count;
  last_bg[0] = (float)r;
  last_bg[1] = (float)g;
  last_bg[2] = (float)b;
  // a window's into its canvas; without one, the offscreen target is kept as a canvas is
  ID3D11RenderTargetView *target = rtv;
  int *kept = &off_ok;
  if (chain) {
    ensure_canvas(fb_w, fb_h);
    if (!canvas_rtv) {
      dirty_told = dirty_whole = dirty_n = 0;
      encode(rtv, fb_w, fb_h, count, last_bg, last_inst);
      if (parts_out) *parts_out = -1;
      return 1;
    }
    target = canvas_rtv;
    kept = &canvas_ok;
  }
  D3D11_RECT parts[MB_PARTS];
  int np = take_parts(fb_w, fb_h, *kept, parts);
  int missing = 0;
  if (np < 0) {
    encode(target, fb_w, fb_h, count, last_bg, last_inst);
    missing = encode_missing;
  }
  for (int i = 0; i < np; i++) {
    encode(target, fb_w, fb_h, count, last_bg, last_inst, &parts[i]);
    missing |= encode_missing;
  }
  if (np != 0) pictures_missing = missing;
  *kept = 1;
  if (parts_out) *parts_out = np;
  if (cuts) for (int i = 0; i < np; i++) cuts[i] = parts[i];
  if (chain) {
    // the canvas whole into the swap chain's buffer
    ID3D11Resource *back = NULL;
    rtv->GetResource(&back);
    ctx->CopyResource(back, canvas);
    back->Release();
  }
  return 1;
}

void mb_render_present(const double *inst, int32_t count, double r, double g, double b) {
  int n = -1;
  D3D11_RECT parts[MB_PARTS];
  if (!submit(inst, count, r, g, b, &n, parts) || !chain) {
    commit_presented();
    return;
  }
  // a hidden or minimized window does not wait for vsync; pace it as if it did. A flip model's swap chain is told the
  // parts that changed (what the compositor takes again; none: a pixel's), all of its buffer the canvas's
  HRESULT hr;
  if (flip_chain && n >= 0) {
    RECT dr[MB_PARTS];
    for (int i = 0; i < n; i++) dr[i] = {parts[i].left, parts[i].top, parts[i].right, parts[i].bottom};
    if (n == 0) dr[n++] = {0, 0, 1, 1};
    DXGI_PRESENT_PARAMETERS pp = {};
    pp.DirtyRectsCount = (UINT)n;
    pp.pDirtyRects = dr;
    hr = chain->Present1(1, 0, &pp);
  } else {
    hr = chain->Present(1, 0);
  }
  commit_presented();
  if (hr == DXGI_STATUS_OCCLUDED) Sleep(16);
}

// Without a window (mbui-render, src/render): WARP's device whatever the machine has (the same rasterizer on every
// Windows: what the references are of, docs/determinism.md), a texture the size a window's swap chain would be as
// the target, the text at the list's scale. A frame drawn there is drawn as a window's is, and its snapshot is of it.
static ID3D11Texture2D *off_target;

extern "C" void mb_render_init_offscreen(double w, double h, double scale) {
  CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
  if (FAILED(make_device(D3D_DRIVER_TYPE_WARP, 0))) {
    fprintf(stderr, "no Direct3D 11 WARP device\n");
    return;
  }
  // which WARP drew it (the app's own beside it, as render_windows.sh puts the pinned one, or the system's)
  HMODULE warp = GetModuleHandleW(L"d3d10warp.dll");
  wchar_t warp_path[MAX_PATH];
  if (warp && GetModuleFileNameW(warp, warp_path, MAX_PATH)) fwprintf(stderr, L"WARP %ls\n", warp_path);
  make_pipeline();
  vw = w;
  vh = h;
  vscale = scale;
  fb_w = (int)floor(w * scale + 0.5);
  fb_h = (int)floor(h * scale + 0.5);
  D3D11_TEXTURE2D_DESC td = {};
  td.Width = (UINT)fb_w;
  td.Height = (UINT)fb_h;
  td.MipLevels = td.ArraySize = 1;
  td.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  td.SampleDesc.Count = 1;
  td.Usage = D3D11_USAGE_DEFAULT;
  td.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  dev->CreateTexture2D(&td, NULL, &off_target);
  dev->CreateRenderTargetView(off_target, NULL, &rtv);
  mb_text_set_scale(scale);
}

// A frame drawn into the offscreen target and finished: out[0] the CPU's time of it, out[1] the GPU's (not measured
// here: -1), in ms.
extern "C" void mb_render_draw_timed(const double *inst, int32_t count, double r, double g, double b, double *out) {
  LARGE_INTEGER f, t0, t1;
  QueryPerformanceFrequency(&f);
  QueryPerformanceCounter(&t0);
  submit(inst, count, r, g, b);
  ctx->Flush();
  QueryPerformanceCounter(&t1);
  out[0] = (double)(t1.QuadPart - t0.QuadPart) * 1000.0 / (double)f.QuadPart;
  out[1] = -1;
}

static int write_png(const wchar_t *path, const uint8_t *bgra, int w, int h, int stride) {
  IWICImagingFactory *wic = NULL;
  IWICStream *stream = NULL;
  IWICBitmapEncoder *enc = NULL;
  IWICBitmapFrameEncode *frame = NULL;
  int ok = 0;
  CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
  if (SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER,
                                 __uuidof(IWICImagingFactory), (void **)&wic)) &&
      SUCCEEDED(wic->CreateStream(&stream)) &&
      SUCCEEDED(stream->InitializeFromFilename(path, GENERIC_WRITE)) &&
      SUCCEEDED(wic->CreateEncoder(GUID_ContainerFormatPng, NULL, &enc)) &&
      SUCCEEDED(enc->Initialize(stream, WICBitmapEncoderNoCache)) &&
      SUCCEEDED(enc->CreateNewFrame(&frame, NULL)) && SUCCEEDED(frame->Initialize(NULL)) &&
      SUCCEEDED(frame->SetSize((UINT)w, (UINT)h))) {
    WICPixelFormatGUID fmt = GUID_WICPixelFormat32bppBGRA;
    ok = SUCCEEDED(frame->SetPixelFormat(&fmt)) &&
         SUCCEEDED(frame->WritePixels((UINT)h, (UINT)stride, (UINT)(stride * h), (BYTE *)bgra)) &&
         SUCCEEDED(frame->Commit()) && SUCCEEDED(enc->Commit());
  }
  if (frame) frame->Release();
  if (enc) enc->Release();
  if (stream) stream->Release();
  if (wic) wic->Release();
  return ok;
}

// Instances `f` (`count` of them) drawn on the ground `bg` into a texture of their own, `w` × `h`, and copied where the
// CPU reads it (a staging texture, to Map; NULL where it could not be made). What the vertex buffer holds is drawn: the
// caller has put `f` there.
static ID3D11Texture2D *redrawn_of(int w, int h, int32_t count, const float *bg, const float *f) {
  D3D11_TEXTURE2D_DESC td = {};
  td.Width = (UINT)w;
  td.Height = (UINT)h;
  td.MipLevels = td.ArraySize = 1;
  td.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  td.SampleDesc.Count = 1;
  td.Usage = D3D11_USAGE_DEFAULT;
  td.BindFlags = D3D11_BIND_RENDER_TARGET;
  ID3D11Texture2D *tex = NULL, *staging = NULL;
  ID3D11RenderTargetView *view = NULL;
  if (FAILED(dev->CreateTexture2D(&td, NULL, &tex))) return NULL;
  if (FAILED(dev->CreateRenderTargetView(tex, NULL, &view))) {
    tex->Release();
    return NULL;
  }
  encode(view, w, h, count, bg, f);
  td.Usage = D3D11_USAGE_STAGING;
  td.BindFlags = 0;
  td.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  if (SUCCEEDED(dev->CreateTexture2D(&td, NULL, &staging))) ctx->CopyResource(staging, tex);
  view->Release();
  tex->Release();
  if (rtv) ctx->OMSetRenderTargets(1, &rtv, NULL);
  return staging;
}

// The last presented frame drawn again (its instances are what the vertex buffer holds), as redrawn_of draws.
static ID3D11Texture2D *redrawn(int w, int h) {
  return redrawn_of(w, h, last_count, last_bg, last_inst);
}

// `count` instances of `f` into the vertex buffer, grown to hold them: 0 where it could not be written.
static int fill_vbuf(const float *f, int32_t count) {
  size_t need = (size_t)(count > 0 ? count : 1) * MB_INST * sizeof(float);
  if (vbuf_cap < need) {
    if (vbuf) vbuf->Release();
    vbuf_cap = need * 2;
    D3D11_BUFFER_DESC bd = {(UINT)vbuf_cap, D3D11_USAGE_DYNAMIC, D3D11_BIND_VERTEX_BUFFER,
                            D3D11_CPU_ACCESS_WRITE, 0, 0};
    dev->CreateBuffer(&bd, NULL, &vbuf);
  }
  D3D11_MAPPED_SUBRESOURCE m;
  if (!vbuf || FAILED(ctx->Map(vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, &m))) return 0;
  if (count > 0) memcpy(m.pData, f, (size_t)count * MB_INST * sizeof(float));
  ctx->Unmap(vbuf, 0);
  return 1;
}

// Instances never presented (a shot's, mbui/src/ui/shot.mbt) drawn as a frame is, but `scale` pixels a point into a
// picture of their own w × h (their 0, 0 its top left), on the ground r, g, b, and its pixels into `out` as
// mb_render_drawn_pixels gives the frame's; the size frames are drawn at put back after, and the vertex buffer given
// back the frame's (a snapshot draws it again). 1 when read.
extern "C" int32_t mb_render_pixels_of(const double *inst, int32_t count, double r, double g, double b, double scale,
                                       int32_t w, int32_t h, moonbit_bytes_t out) {
  if (!dev || count <= 0 || !(scale > 0) || w <= 0 || h <= 0) return 0;
  if ((size_t)Moonbit_array_length(out) < (size_t)w * h * 4) return 0;
  size_t n = (size_t)count * MB_INST;
  float *f = (float *)malloc(n * sizeof(float));
  for (size_t i = 0; i < n; i++) f[i] = (float)inst[i];
  float bg[3] = {(float)r, (float)g, (float)b};
  double kw = vw, kh = vh, ks = vscale;
  vscale = scale;
  vw = w / scale;
  vh = h / scale;
  ID3D11Texture2D *staging = fill_vbuf(f, count) ? redrawn_of(w, h, count, bg, f) : NULL;
  vw = kw;
  vh = kh;
  vscale = ks;
  free(f);
  // (the frame's own back where it was)
  if (last_inst) fill_vbuf(last_inst, last_count);
  if (!staging) return 0;
  int ok = 0;
  D3D11_MAPPED_SUBRESOURCE m;
  if (SUCCEEDED(ctx->Map(staging, 0, D3D11_MAP_READ, 0, &m))) {
    for (int k = 0; k < h; k++) {
      const uint8_t *s = (const uint8_t *)m.pData + (size_t)k * m.RowPitch;
      uint8_t *d = out + (size_t)k * w * 4;
      for (int j = 0; j < w; j++, s += 4, d += 4) {
        d[0] = s[2];
        d[1] = s[1];
        d[2] = s[0];
        d[3] = s[3];
      }
    }
    ctx->Unmap(staging, 0);
    ok = 1;
  }
  staging->Release();
  return ok;
}

extern "C" int32_t mb_render_drawn_pixels(int32_t x, int32_t y, int32_t w, int32_t h, moonbit_bytes_t out) {
  int fw = fb_w, fh = fb_h;
  if (!dev || !last_inst || fw <= 0 || fh <= 0 || w <= 0 || h <= 0 || x < 0 || y < 0 || x + w > fw || y + h > fh) return 0;
  if ((size_t)Moonbit_array_length(out) < (size_t)w * h * 4) return 0;
  ID3D11Texture2D *staging = redrawn(fw, fh);
  if (!staging) return 0;
  int ok = 0;
  D3D11_MAPPED_SUBRESOURCE m;
  if (SUCCEEDED(ctx->Map(staging, 0, D3D11_MAP_READ, 0, &m))) {
    for (int r = 0; r < h; r++) {
      const uint8_t *s = (const uint8_t *)m.pData + (size_t)(y + r) * m.RowPitch + (size_t)x * 4;
      uint8_t *d = out + (size_t)r * w * 4;
      for (int k = 0; k < w; k++, s += 4, d += 4) {
        d[0] = s[2];
        d[1] = s[1];
        d[2] = s[0];
        d[3] = s[3];
      }
    }
    ctx->Unmap(staging, 0);
    ok = 1;
  }
  staging->Release();
  return ok;
}

int mb_render_snapshot(const wchar_t *path) {
  int w = fb_w, h = fb_h;
  if (!dev || w <= 0 || h <= 0) return 0;
  ID3D11Texture2D *staging = redrawn(w, h);
  if (!staging) return 0;
  int ok = 0;
  D3D11_MAPPED_SUBRESOURCE m;
  if (SUCCEEDED(ctx->Map(staging, 0, D3D11_MAP_READ, 0, &m))) {
    const uint8_t *px = (const uint8_t *)m.pData;
    int stride = (int)m.RowPitch;
    uint8_t *out = NULL;
    if (mb_views_count() > 0) {
      // the native views' pictures under the canvas, seen through its holes (premultiplied: canvas + under × (1 - α))
      out = (uint8_t *)calloc((size_t)w * h, 4);
      mb_views_draw_under(out, w, h, vscale);
      for (int y = 0; y < h; y++) {
        const uint8_t *s = px + (size_t)y * stride;
        uint8_t *d = out + (size_t)y * w * 4;
        for (int x = 0; x < w; x++, s += 4, d += 4) {
          int k = 255 - s[3];
          for (int c = 0; c < 3; c++) d[c] = (uint8_t)(s[c] + (d[c] * k + 127) / 255);
          d[3] = (uint8_t)(s[3] + (d[3] * k + 127) / 255);
        }
      }
      px = out;
      stride = w * 4;
    }
    ok = write_png(path, px, w, h, stride);
    free(out);
    ctx->Unmap(staging, 0);
  }
  staging->Release();
  return ok;
}

// The offscreen target as its frames left it (not the last frame drawn again: what drawing only the parts that differ
// made of it, mbui-render's MBUI_DL_FROM), as a PNG.
extern "C" int mb_render_snapshot_drawn(const wchar_t *path) {
  if (!off_target) return 0;
  D3D11_TEXTURE2D_DESC td = {};
  off_target->GetDesc(&td);
  td.Usage = D3D11_USAGE_STAGING;
  td.BindFlags = 0;
  td.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  ID3D11Texture2D *staging = NULL;
  if (FAILED(dev->CreateTexture2D(&td, NULL, &staging))) return 0;
  ctx->CopyResource(staging, off_target);
  int ok = 0;
  D3D11_MAPPED_SUBRESOURCE m;
  if (SUCCEEDED(ctx->Map(staging, 0, D3D11_MAP_READ, 0, &m))) {
    ok = write_png(path, (const uint8_t *)m.pData, (int)td.Width, (int)td.Height, (int)m.RowPitch);
    ctx->Unmap(staging, 0);
  }
  staging->Release();
  return ok;
}

// What the screen shows of the window's client area (the desktop's composition: the canvas over the native views),
// as a PNG: a check of what the snapshot above puts together itself.
int mb_screen_snapshot(void *hwnd, const wchar_t *path) {
  RECT rc;
  GetClientRect((HWND)hwnd, &rc);
  POINT o = {0, 0};
  ClientToScreen((HWND)hwnd, &o);
  int w = rc.right, h = rc.bottom;
  if (w <= 0 || h <= 0) return 0;
  HDC screen = GetDC(NULL), mem = CreateCompatibleDC(screen);
  BITMAPINFO bi = {};
  bi.bmiHeader.biSize = sizeof bi.bmiHeader;
  bi.bmiHeader.biWidth = w;
  bi.bmiHeader.biHeight = -h;
  bi.bmiHeader.biPlanes = 1;
  bi.bmiHeader.biBitCount = 32;
  void *bits = NULL;
  HBITMAP bm = CreateDIBSection(mem, &bi, DIB_RGB_COLORS, &bits, NULL, 0);
  int ok = 0;
  if (bm) {
    HGDIOBJ was = SelectObject(mem, bm);
    if (BitBlt(mem, 0, 0, w, h, screen, o.x, o.y, SRCCOPY | CAPTUREBLT)) {
      GdiFlush();
      uint8_t *px = (uint8_t *)bits;
      for (int i = 0; i < w * h; i++) px[i * 4 + 3] = 255;
      ok = write_png(path, px, w, h, w * 4);
    }
    SelectObject(mem, was);
    DeleteObject(bm);
  }
  DeleteDC(mem);
  ReleaseDC(NULL, screen);
  return ok;
}

// The GPU's time is not measured here.
extern "C" double mb_host_gpu_ms(void) { return -1; }
