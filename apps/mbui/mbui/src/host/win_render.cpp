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
static ID3D11RasterizerState *raster;
static int fb_w, fb_h;
static double vw = 800, vh = 600, vscale = 1;
// glass (src/ui/glass.mbt): its passes, their constants, the copies they work in (level j 1/2^j of the target, [4] a
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
#define MB_INST 32

static const char *shader_src =
    "cbuffer U : register(b0) { float2 vp; float scale; float pad; };\n"
    "// glass (src/ui/glass.mbt): where a point is in the blurred copy under it (uv = p * gmap.xy + gmap.zw, kept in guvc),\n"
    "// a liquid group's bounds, shapes, corners (x of each), how many\n"
    "cbuffer G : register(b1) { float4 gmap; float4 guvc; float4 ggb; float4 gshape[8]; float4 grad[8]; float4 gmisc; };\n"
    "Texture2D atlas : register(t0);\n"
    "Texture2D img : register(t1);\n"
    "Texture2D bd : register(t2);\n"
    "SamplerState samp : register(s0);\n"
    "struct VIn { float4 rect : INST0; float4 p : INST1; float4 color : INST2; float4 c2 : INST3;\n"
    "  float4 clip : INST4; float4 pd : INST5; float4 rc : INST6; float4 rs : INST7; uint vid : SV_VertexID; };\n"
    "struct VOut { float4 pos : SV_Position; float2 p : POS;\n"
    "  nointerpolation float4 rect : INST0; nointerpolation float4 prm : INST1;\n"
    "  nointerpolation float4 color : INST2; nointerpolation float4 c2 : INST3;\n"
    "  nointerpolation float4 clip : INST4; nointerpolation float4 pd : INST5; nointerpolation float4 rc : INST6;\n"
    "  nointerpolation float4 rs : INST7; };\n"
    "VOut vmain(VIn I) {\n"
    "  uint vid = I.vid;\n"
    "  float2 corner = float2((vid == 1 || vid == 4 || vid == 5) ? 1.0 : 0.0,\n"
    "                         (vid == 2 || vid == 3 || vid == 5) ? 1.0 : 0.0);\n"
    "  int kind = int(I.p.y + 0.5);\n"
    "  float grow = kind == 2 ? I.p.w * 2.0 + 2.0 : ((kind == 0 || kind == 4 || kind == 5) ? 1.0 : 0.0);\n"
    "  float2 pos = I.rect.xy - grow + corner * (I.rect.zw + 2.0 * grow);\n"
    "  if (kind == 6) pos = lerp(ggb.xy, ggb.zw, corner);\n"
    "  VOut o;\n"
    "  o.pos = float4(pos.x / vp.x * 2.0 - 1.0, 1.0 - pos.y / vp.y * 2.0, 0.0, 1.0);\n"
    "  o.p = pos; o.rect = I.rect; o.prm = I.p; o.color = I.color; o.c2 = I.c2; o.clip = I.clip; o.pd = I.pd; o.rc = I.rc; o.rs = I.rs;\n"
    "  return o;\n"
    "}\n"
    MB_CORNER_SL
    "float sd_rr(float2 p, float4 r, float rad) {\n"
    "  float2 hs = r.zw * 0.5;\n"
    "  return mb_sd_box(p - r.xy - hs, hs, rad, 1e9);\n"
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
    "    d = smin_k(d, sd_rr(p, gshape[i], grad[i].x), k);\n"
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
    "float4 fmain(VOut I) : SV_Target {\n"
    "  float2 p = I.p;\n"
    "  // cut to its clip: a rect's, hard; a rounded one's, covered as edges are\n"
    "  float cover = 1.0;\n"
    "  if (max(max(I.rc.x, I.rc.y), max(I.rc.z, I.rc.w)) > 0.0) {\n"
    "    cover = clip_cover(p, I.clip, I.rc, I.rs, scale);\n"
    "    if (cover <= 0.0) discard;\n"
    "  } else if (p.x < I.clip.x || p.y < I.clip.y || p.x > I.clip.z || p.y > I.clip.w) discard;\n"
    "  int kind = int(I.prm.y + 0.5);\n"
    "  if (kind == 9) { float2 hh = I.rect.zw * 0.5; float rr = min(I.prm.x, min(hh.x, hh.y)); float2 q = abs(p - I.rect.xy - hh) - hh + rr; if (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rr > 0.0) discard; return (float4(0.0, 0.0, 0.0, 0.0)) * cover; }\n"
    "  float4 col = I.color;\n"
    "  if (kind == 10) {\n"
    "    // a piece of a line (scene.mbt): from c2.xy to c2.zw (shares of its rect), prm.x half its width, its ends round\n"
    "    float2 a = I.rect.xy + I.c2.xy * I.rect.zw, ab = I.rect.xy + I.c2.zw * I.rect.zw - a;\n"
    "    float h = saturate(dot(p - a, ab) / max(dot(ab, ab), 1e-8));\n"
    "    float d = length(p - a - ab * h) - I.prm.x;\n"
    "    return (float4(col.rgb, 1.0) * col.a * saturate(0.5 - d * scale)) * cover;\n"
    "  }\n"
    "  if (kind == 1 || kind == 3 || kind == 7) {\n"
    "    float2 uv = (I.c2.xy + (p - I.rect.xy) / I.rect.zw * I.c2.zw) / 2048.0;\n"
    "    float4 t = atlas.SampleLevel(samp, uv, 0);\n"
    "    if (kind == 1) return (float4(col.rgb, 1.0) * (t.a * col.a)) * cover;\n"
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
    "    return (float4(c, 1.0) * (a * I.c2.w)) * cover;\n"
    "  }\n"
    "  float2 hs = I.rect.zw * 0.5;\n"
    "  float2 c = I.rect.xy + hs;\n"
    "  // worked out as near the curve as its cover, its edge or its blur reaches\n"
    "  float band = 1.0 + 2.0 / scale + (kind == 2 ? max(I.prm.w, 0.5) : max(I.prm.z, 0.0));\n"
    "  float d = mb_sd_box(p - c, hs, I.prm.x, band);\n"
    "  if (kind == 0 || kind == 5) d = notch_cut(d, p, I.rect, I.pd);\n"
    "  if (kind == 4) {\n"
    "    float2 uv = I.c2.xy + saturate((p - I.rect.xy) / I.rect.zw) * I.c2.zw;\n"
    "    return (img.SampleLevel(samp, uv, 0) * (col.a * saturate(0.5 - d * scale))) * cover;\n"
    "  }\n"
    "  if (kind == 2) {\n"
    "    float b = max(I.prm.w, 0.5);\n"
    "    float a = 1.0 - smoothstep(-b, b, d);\n"
    "    // glass's: only outside its box (c2.y above it)\n"
    "    if (I.c2.x > 0.5) {\n"
    "      float db = mb_sd_box(p - c + float2(0.0, I.c2.y), hs, I.prm.x, band);\n"
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
    "      float lit = saturate(0.5 + notch_cut(sd_rr(p - 0.5, I.rect, I.prm.x), p - 0.5, I.rect, I.pd) * scale);\n"
    "      float back = saturate(0.5 + notch_cut(sd_rr(p + 0.5, I.rect, I.prm.x), p + 0.5, I.rect, I.pd) * scale);\n"
    "      g3 = lerp(g3, float3(1.0, 1.0, 1.0), I.c2.x * edge);\n"
    "      g3 = lerp(g3, float3(1.0, 1.0, 1.0), I.c2.y * lit);\n"
    "      g3 = lerp(g3, float3(1.0, 1.0, 1.0), I.c2.z * back);\n"
    "    }\n"
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

static HRESULT make_device(D3D_DRIVER_TYPE type) {
  D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0};
  return D3D11CreateDevice(NULL, type, NULL, D3D11_CREATE_DEVICE_BGRA_SUPPORT, levels, 3,
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
  if (FAILED(make_device(D3D_DRIVER_TYPE_HARDWARE)) && FAILED(make_device(D3D_DRIVER_TYPE_WARP))) {
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
  if (make_composed(xdev, factory, (HWND)hwnd)) {
    // the composition's swap chain, made at the window's size (its first buffers' view: at the first frame's size)
    fb_w = fb_h = 0;
  } else if (FAILED(factory->CreateSwapChainForHwnd(dev, (HWND)hwnd, &sd, NULL, NULL, &chain))) {
    // before Windows 10
    sd.Scaling = DXGI_SCALING_STRETCH;
    sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
    sd.BufferCount = 1;
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
  // the instance's eight float4s (scene.mbt): rect, p, color, c2, clip, pad, the clip's corners' radii, how smooth
  D3D11_INPUT_ELEMENT_DESC el[8];
  for (UINT i = 0; i < 8; i++)
    el[i] = {"INST", i, DXGI_FORMAT_R32G32B32A32_FLOAT, 0, i * 16, D3D11_INPUT_PER_INSTANCE_DATA, 1};
  dev->CreateInputLayout(el, 8, vcode->GetBufferPointer(), vcode->GetBufferSize(), &layout);
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
  b.DestBlend = b.DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA;
  b.BlendOp = b.BlendOpAlpha = D3D11_BLEND_OP_ADD;
  b.RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
  dev->CreateBlendState(&bd, &blend);

  D3D11_RASTERIZER_DESC rd = {};
  rd.FillMode = D3D11_FILL_SOLID;
  rd.CullMode = D3D11_CULL_NONE;
  rd.DepthClipEnable = TRUE;
  dev->CreateRasterizerState(&rd, &raster);
}

void *mb_render_device(void) { return dev; }

void *mb_render_dcomp(void) { return dcomp; }
void *mb_render_views_visual(void) { return dunder; }
void mb_render_commit(void) {
  if (dcomp) dcomp->Commit();
}

void mb_render_set_size(int pw, int ph, double w, double h, double scale) {
  vw = w;
  vh = h;
  vscale = scale;
  if (!chain || (pw == fb_w && ph == fb_h && rtv)) return;
  if (rtv) rtv->Release();
  rtv = NULL;
  ctx->OMSetRenderTargets(0, NULL, NULL);
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
// through.

static level level_tex(int w, int h) {
  level l = {NULL, NULL, NULL, w > 0 ? w : 1, h > 0 ? h : 1};
  D3D11_TEXTURE2D_DESC td = {};
  td.Width = (UINT)l.w;
  td.Height = (UINT)l.h;
  td.MipLevels = td.ArraySize = 1;
  td.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
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
  for (int j = 0; j < 4; j++) lv[j] = level_tex((lv_w + (1 << j) - 1) >> j, (lv_h + (1 << j) - 1) >> j);
  lv[4] = level_tex(lv_w, lv_h);
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
  int w = px1 - px0, h = py1 - py0;
  ensure_levels(pw, ph);
  ID3D11Resource *res = NULL;
  target->GetResource(&res);
  D3D11_BOX box = {(UINT)px0, (UINT)py0, 0, (UINT)px1, (UINT)py1, 1};
  ctx->CopySubresourceRegion(lv[0].t, 0, 0, 0, 0, res, 0, &box);
  res->Release();
  ctx->VSSetShader(pvs, NULL, 0);
  ctx->PSSetShader(pps, NULL, 0);
  ctx->IASetInputLayout(NULL);
  ctx->OMSetBlendState(NULL, NULL, 0xffffffff);
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

// the main pipeline's state, at the start and after the passes
static void main_state(ID3D11RenderTargetView *target, int pw, int ph) {
  D3D11_VIEWPORT vp = {0, 0, (float)pw, (float)ph, 0, 1};
  UINT stride = MB_INST * sizeof(float), off = 0;
  ctx->OMSetRenderTargets(1, &target, NULL);
  ctx->RSSetViewports(1, &vp);
  ctx->RSSetState(raster);
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
  ctx->PSSetSamplers(0, 1, &sampler);
  ctx->OMSetBlendState(blend, NULL, 0xffffffff);
}

static void encode(ID3D11RenderTargetView *target, int pw, int ph, int32_t count, const float *bg,
                   const float *f) {
  float clear[4] = {bg[0], bg[1], bg[2], 1};
  ctx->OMSetRenderTargets(1, &target, NULL);
  ctx->ClearRenderTargetView(target, clear);
  if (count <= 0) return;
  struct { float vp[2]; float scale; float pad; } u = {{(float)vw, (float)vh}, (float)vscale, 0};
  ctx->UpdateSubresource(ubuf, 0, NULL, &u, 0, 0);
  memset(&gu, 0, sizeof gu);
  gsrv = NULL;
  main_state(target, pw, ph);
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
    ID3D11ShaderResourceView *t = tid > MB_STREAM_TEX ? (ID3D11ShaderResourceView *)mb_stream_srv(tid - MB_STREAM_TEX)
                                  : tid ? (ID3D11ShaderResourceView *)mb_image_srv(tid) : atlas_srv;
    // (a stream with no frame of its own yet: nothing, not the atlas)
    if (tid > MB_STREAM_TEX && !t) {
      start = end;
      continue;
    }
    ctx->PSSetShaderResources(1, 1, t ? &t : &atlas_srv);
    if (hole) ctx->OMSetBlendState(NULL, NULL, 0xffffffff);
    ctx->DrawInstanced(6, (UINT)(end - start), 0, (UINT)start);
    if (hole) ctx->OMSetBlendState(blend, NULL, 0xffffffff);
    start = end;
  }
}

// The frame's instances into the vertex buffer and kept (a snapshot draws them again), then drawn into the target.
static int submit(const double *inst, int32_t count, double r, double g, double b) {
  if (!rtv) return 0;
  size_t need = (size_t)(count > 0 ? count : 1) * MB_INST * sizeof(float);
  if (vbuf_cap < need) {
    if (vbuf) vbuf->Release();
    vbuf_cap = need * 2;
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
  ctx->Unmap(vbuf, 0);
  last_count = count;
  last_bg[0] = (float)r;
  last_bg[1] = (float)g;
  last_bg[2] = (float)b;
  encode(rtv, fb_w, fb_h, count, last_bg, last_inst);
  return 1;
}

void mb_render_present(const double *inst, int32_t count, double r, double g, double b) {
  if (!submit(inst, count, r, g, b) || !chain) return;
  // a hidden or minimized window does not wait for vsync; pace it as if it did
  if (chain->Present(1, 0) == DXGI_STATUS_OCCLUDED) Sleep(16);
}

// Without a window (mbui-render, src/render): WARP's device whatever the machine has (the same rasterizer on every
// Windows: what the references are of, docs/determinism.md), a texture the size a window's swap chain would be as
// the target, the text at the list's scale. A frame drawn there is drawn as a window's is, and its snapshot is of it.
static ID3D11Texture2D *off_target;

extern "C" void mb_render_init_offscreen(double w, double h, double scale) {
  CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
  if (FAILED(make_device(D3D_DRIVER_TYPE_WARP))) {
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

int mb_render_snapshot(const wchar_t *path) {
  int w = fb_w, h = fb_h;
  if (!dev || w <= 0 || h <= 0) return 0;
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
  dev->CreateTexture2D(&td, NULL, &tex);
  dev->CreateRenderTargetView(tex, NULL, &view);
  encode(view, w, h, last_count, last_bg, last_inst);
  td.Usage = D3D11_USAGE_STAGING;
  td.BindFlags = 0;
  td.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  dev->CreateTexture2D(&td, NULL, &staging);
  ctx->CopyResource(staging, tex);
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
  view->Release();
  tex->Release();
  if (rtv) ctx->OMSetRenderTargets(1, &rtv, NULL);
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
