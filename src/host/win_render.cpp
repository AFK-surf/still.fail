// Direct3D 11 renderer: one pipeline, one instanced quad per scene instance,
// the Metal/GLES shader in HLSL. Without a usable GPU (CI) the device is WARP.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <d3dcompiler.h>
#include <wincodec.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "win.h"

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "d3dcompiler.lib")
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
static ID3D11RasterizerState *raster;
static int fb_w, fb_h;
static double vw = 800, vh = 600, vscale = 1;
// the last frame, kept for snapshots (the vertex buffer still holds it) and
// to find the runs of each image
static int32_t last_count;
static float *last_inst;
static size_t last_cap;
static float last_bg[3];

static const char *shader_src =
    "cbuffer U : register(b0) { float2 vp; float scale; float pad; };\n"
    "Texture2D atlas : register(t0);\n"
    "Texture2D img : register(t1);\n"
    "SamplerState samp : register(s0);\n"
    "struct VIn { float4 rect : INST0; float4 p : INST1; float4 color : INST2; float4 c2 : INST3;\n"
    "  float4 clip : INST4; uint vid : SV_VertexID; };\n"
    "struct VOut { float4 pos : SV_Position; float2 p : POS;\n"
    "  nointerpolation float4 rect : INST0; nointerpolation float4 prm : INST1;\n"
    "  nointerpolation float4 color : INST2; nointerpolation float4 c2 : INST3;\n"
    "  nointerpolation float4 clip : INST4; };\n"
    "VOut vmain(VIn I) {\n"
    "  uint vid = I.vid;\n"
    "  float2 corner = float2((vid == 1 || vid == 4 || vid == 5) ? 1.0 : 0.0,\n"
    "                         (vid == 2 || vid == 3 || vid == 5) ? 1.0 : 0.0);\n"
    "  int kind = int(I.p.y + 0.5);\n"
    "  float grow = kind == 2 ? I.p.w * 2.0 + 2.0 : ((kind == 0 || kind == 4) ? 1.0 : 0.0);\n"
    "  float2 pos = I.rect.xy - grow + corner * (I.rect.zw + 2.0 * grow);\n"
    "  VOut o;\n"
    "  o.pos = float4(pos.x / vp.x * 2.0 - 1.0, 1.0 - pos.y / vp.y * 2.0, 0.0, 1.0);\n"
    "  o.p = pos; o.rect = I.rect; o.prm = I.p; o.color = I.color; o.c2 = I.c2; o.clip = I.clip;\n"
    "  return o;\n"
    "}\n"
    "float4 fmain(VOut I) : SV_Target {\n"
    "  float2 p = I.p;\n"
    "  if (p.x < I.clip.x || p.y < I.clip.y || p.x > I.clip.z || p.y > I.clip.w) discard;\n"
    "  int kind = int(I.prm.y + 0.5);\n"
    "  float4 col = I.color;\n"
    "  if (kind == 1 || kind == 3) {\n"
    "    float2 uv = (I.c2.xy + (p - I.rect.xy) / I.rect.zw * I.c2.zw) / 2048.0;\n"
    "    float4 t = atlas.SampleLevel(samp, uv, 0);\n"
    "    if (kind == 1) return float4(col.rgb, 1.0) * (t.a * col.a);\n"
    "    return t * col.a;\n"
    "  }\n"
    "  float2 hs = I.rect.zw * 0.5;\n"
    "  float2 c = I.rect.xy + hs;\n"
    "  float r = min(I.prm.x, min(hs.x, hs.y));\n"
    "  float2 q = abs(p - c) - hs + r;\n"
    "  float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;\n"
    "  if (kind == 4) {\n"
    "    float2 uv = I.c2.xy + saturate((p - I.rect.xy) / I.rect.zw) * I.c2.zw;\n"
    "    return img.SampleLevel(samp, uv, 0) * (col.a * saturate(0.5 - d * scale));\n"
    "  }\n"
    "  if (kind == 2) {\n"
    "    float b = max(I.prm.w, 0.5);\n"
    "    float a = 1.0 - smoothstep(-b, b, d);\n"
    "    return float4(col.rgb, 1.0) * col.a * a;\n"
    "  }\n"
    "  float a = clamp(0.5 - d * scale, 0.0, 1.0);\n"
    "  float4 fill = float4(col.rgb, 1.0) * col.a;\n"
    "  float bw = I.prm.z;\n"
    "  if (bw > 0.0) {\n"
    "    float inner = clamp(0.5 - (d + bw) * scale, 0.0, 1.0);\n"
    "    float4 bc = float4(I.c2.rgb, 1.0) * I.c2.a;\n"
    "    fill = lerp(bc, fill, inner);\n"
    "  }\n"
    "  return fill * a;\n"
    "}\n";

static ID3DBlob *compile(const char *entry, const char *target) {
  ID3DBlob *code = NULL, *err = NULL;
  HRESULT hr = D3DCompile(shader_src, strlen(shader_src), "mbui", NULL, NULL, entry, target,
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
  if (FAILED(factory->CreateSwapChainForHwnd(dev, (HWND)hwnd, &sd, NULL, NULL, &chain))) {
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

  ID3DBlob *vcode = compile("vmain", "vs_4_0"), *pcode = compile("fmain", "ps_4_0");
  dev->CreateVertexShader(vcode->GetBufferPointer(), vcode->GetBufferSize(), NULL, &vs);
  dev->CreatePixelShader(pcode->GetBufferPointer(), pcode->GetBufferSize(), NULL, &ps);
  D3D11_INPUT_ELEMENT_DESC el[5];
  for (UINT i = 0; i < 5; i++)
    el[i] = {"INST", i, DXGI_FORMAT_R32G32B32A32_FLOAT, 0, i * 16, D3D11_INPUT_PER_INSTANCE_DATA, 1};
  dev->CreateInputLayout(el, 5, vcode->GetBufferPointer(), vcode->GetBufferSize(), &layout);
  vcode->Release();
  pcode->Release();

  D3D11_BUFFER_DESC ud = {16, D3D11_USAGE_DEFAULT, D3D11_BIND_CONSTANT_BUFFER, 0, 0, 0};
  dev->CreateBuffer(&ud, NULL, &ubuf);

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
  return chain != NULL;
}

void *mb_render_device(void) { return dev; }

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

static void encode(ID3D11RenderTargetView *target, int pw, int ph, int32_t count, const float *bg,
                   const float *f) {
  float clear[4] = {bg[0], bg[1], bg[2], 1};
  ctx->OMSetRenderTargets(1, &target, NULL);
  ctx->ClearRenderTargetView(target, clear);
  if (count <= 0) return;
  D3D11_VIEWPORT vp = {0, 0, (float)pw, (float)ph, 0, 1};
  struct { float vp[2]; float scale; float pad; } u = {{(float)vw, (float)vh}, (float)vscale, 0};
  UINT stride = 24 * sizeof(float), off = 0;
  ctx->UpdateSubresource(ubuf, 0, NULL, &u, 0, 0);
  ctx->RSSetViewports(1, &vp);
  ctx->RSSetState(raster);
  ctx->IASetInputLayout(layout);
  ctx->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  ctx->IASetVertexBuffers(0, 1, &vbuf, &stride, &off);
  ctx->VSSetShader(vs, NULL, 0);
  ctx->VSSetConstantBuffers(0, 1, &ubuf);
  ctx->PSSetShader(ps, NULL, 0);
  ctx->PSSetConstantBuffers(0, 1, &ubuf);
  ctx->PSSetShaderResources(0, 1, &atlas_srv);
  ctx->PSSetSamplers(0, 1, &sampler);
  ctx->OMSetBlendState(blend, NULL, 0xffffffff);
  // one draw per run of instances showing the same image (slot 20; 0: none,
  // the atlas stands in)
  int32_t start = 0;
  while (start < count) {
    int tid = (int)f[start * 24 + 20];
    int32_t end = start + 1;
    while (end < count && (int)f[end * 24 + 20] == tid) end++;
    ID3D11ShaderResourceView *t = tid ? (ID3D11ShaderResourceView *)mb_image_srv(tid) : atlas_srv;
    ctx->PSSetShaderResources(1, 1, t ? &t : &atlas_srv);
    ctx->DrawInstanced(6, (UINT)(end - start), 0, (UINT)start);
    start = end;
  }
}

void mb_render_present(const double *inst, int32_t count, double r, double g, double b) {
  if (!rtv) return;
  size_t need = (size_t)(count > 0 ? count : 1) * 24 * sizeof(float);
  if (vbuf_cap < need) {
    if (vbuf) vbuf->Release();
    vbuf_cap = need * 2;
    D3D11_BUFFER_DESC bd = {(UINT)vbuf_cap, D3D11_USAGE_DYNAMIC, D3D11_BIND_VERTEX_BUFFER,
                            D3D11_CPU_ACCESS_WRITE, 0, 0};
    dev->CreateBuffer(&bd, NULL, &vbuf);
  }
  D3D11_MAPPED_SUBRESOURCE m;
  if (FAILED(ctx->Map(vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, &m))) return;
  float *f = (float *)m.pData;
  int32_t n = count * 24;
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
  // a hidden or minimized window does not wait for vsync; pace it as if it did
  if (chain->Present(1, 0) == DXGI_STATUS_OCCLUDED) Sleep(16);
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
    ok = write_png(path, (const uint8_t *)m.pData, w, h, (int)m.RowPitch);
    ctx->Unmap(staging, 0);
  }
  staging->Release();
  view->Release();
  tex->Release();
  if (rtv) ctx->OMSetRenderTargets(1, &rtv, NULL);
  return ok;
}
