// Metal renderer: one pipeline, one instanced quad per scene instance.
#import "apple.h"
#include "corner_sl.h"
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>

int mb_atlas_size = 2048;
// the numbers of an instance (src/ui/scene.mbt)
#define MB_INST 32

static id<MTLDevice> dev;
static id<MTLCommandQueue> queue;
static id<MTLRenderPipelineState> mpipe;
static id<MTLRenderPipelineState> rpipe_off;
// holes for native views (kind 9): written, not blended
static id<MTLRenderPipelineState> hpipe;
static id<MTLTexture> atlas;
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
// glass (src/ui/glass.mbt): the passes that blur what is under it, the copies they work in (level j is 1/2^j of the
// target, each as big as the target's at that level; tmp for a Gaussian's first half), the GPU's time of the last
// frame done
static id<MTLRenderPipelineState> ppipe;
static id<MTLTexture> lv[4], ltmp;
static int lv_w, lv_h;
static double last_gpu = -1;

static NSString *shader_src = @
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"// scene.mbt's 32 numbers: clip, rc and rs the rounded rect it is cut to (its rect x0 y0 x1 y1, its corners' radii,\n"
"// how smooth they are)\n"
"struct Inst { float4 rect; float4 p; float4 color; float4 c2; float4 clip; float4 pad; float4 rc; float4 rs; };\n"
"struct U { float2 vp; float scale; float pad; };\n"
"// glass: where a point's backdrop is in the blurred copy (uv = p * map.xy + map.zw, kept in uvc), a liquid group's\n"
"// bounds, shapes and corners, how many\n"
"struct G { float4 map; float4 uvc; float4 gb; float4 shape[8]; float4 rad[2]; float4 misc; };\n"
"struct VOut { float4 pos [[position]]; float2 p; uint iid [[flat]]; };\n"
"vertex VOut vmain(uint vid [[vertex_id]], uint iid [[instance_id]],\n"
"    const device Inst* inst [[buffer(0)]], constant U& u [[buffer(1)]], constant G& g [[buffer(2)]]) {\n"
"  Inst I = inst[iid];\n"
"  float2 corner = float2((vid == 1 || vid == 4 || vid == 5) ? 1.0 : 0.0,\n"
"                         (vid == 2 || vid == 3 || vid == 5) ? 1.0 : 0.0);\n"
"  int kind = int(I.p.y + 0.5);\n"
"  float grow = kind == 2 ? I.p.w * 2.0 + 2.0 : ((kind == 0 || kind == 4 || kind == 5) ? 1.0 : 0.0);\n"
"  float2 pos = I.rect.xy - grow + corner * (I.rect.zw + 2.0 * grow);\n"
"  if (kind == 6) pos = mix(g.gb.xy, g.gb.zw, corner);\n"
"  VOut o;\n"
"  o.pos = float4(pos.x / u.vp.x * 2.0 - 1.0, 1.0 - pos.y / u.vp.y * 2.0, 0.0, 1.0);\n"
"  o.p = pos; o.iid = iid;\n"
"  return o;\n"
"}\n"
MB_CORNER_SL
"static float sd_rr(float2 p, float4 r, float rad) {\n"
"  float2 hs = r.zw * 0.5;\n"
"  return mb_sd_box(p - r.xy - hs, hs, rad, 1e9);\n"
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
"    d = smin_k(d, sd_rr(p, g.shape[i], g.rad[i / 4][i % 4]), k);\n"
"  }\n"
"  return d;\n"
"}\n"
"static float3 backdrop(texture2d<float> bd, constant G& g, float2 p) {\n"
"  constexpr sampler s(filter::linear, address::clamp_to_edge);\n"
"  float2 uv = clamp(p * g.map.xy + g.map.zw, g.uvc.xy, g.uvc.zw);\n"
"  return bd.sample(s, uv).rgb;\n"
"}\n"
"static float luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }\n"
"// how much of the pixel at p its rounded clip keeps (r: the corners' radii, top left, then clockwise; s: how smooth\n"
"// each is), its edge covered as a box's own (0.5 - d * scale), so what it cuts meets the ground of the box that cuts it\n"
"static float clip_cover(float2 p, float4 c, float4 r, float4 s, float scale) {\n"
"  float2 hs = (c.zw - c.xy) * 0.5;\n"
"  float2 m = c.xy + hs;\n"
"  float rr = p.x < m.x ? (p.y < m.y ? r.x : r.w) : (p.y < m.y ? r.y : r.z);\n"
"  float ss = p.x < m.x ? (p.y < m.y ? s.x : s.w) : (p.y < m.y ? s.y : s.z);\n"
"  float d = mb_sd_corner(p - m, hs, min(rr, min(hs.x, hs.y)), ss, 1.0 + 2.0 / scale);\n"
"  return clamp(0.5 - d * scale, 0.0, 1.0);\n"
"}\n"
"fragment float4 fmain(VOut in [[stage_in]], const device Inst* inst [[buffer(0)]],\n"
"    constant U& u [[buffer(1)]], constant G& g [[buffer(2)]], texture2d<float> atlas [[texture(0)]],\n"
"    texture2d<float> img [[texture(1)]], texture2d<float> bd [[texture(2)]]) {\n"
"  Inst I = inst[in.iid];\n"
"  float2 p = in.p;\n"
"  // cut to its clip: a rect's, hard; a rounded one's, covered as edges are\n"
"  float cover = 1.0;\n"
"  if (max(max(I.rc.x, I.rc.y), max(I.rc.z, I.rc.w)) > 0.0) {\n"
"    cover = clip_cover(p, I.clip, I.rc, I.rs, u.scale);\n"
"    if (cover <= 0.0) discard_fragment();\n"
"  } else if (p.x < I.clip.x || p.y < I.clip.y || p.x > I.clip.z || p.y > I.clip.w) discard_fragment();\n"
"  int kind = int(I.p.y + 0.5);\n"
"  float4 col = I.color;\n"
"  if (kind == 1 || kind == 3 || kind == 7) {\n"
"    constexpr sampler s(filter::linear, coord::pixel);\n"
"    float2 uv = I.c2.xy + (p - I.rect.xy) / I.rect.zw * I.c2.zw;\n"
"    float4 t = atlas.sample(s, uv);\n"
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
"    return (float4(c, 1.0) * (a * I.c2.w)) * cover;\n"
"  }\n"
"  float2 hs = I.rect.zw * 0.5;\n"
"  float2 c = I.rect.xy + hs;\n"
"  // worked out as near the curve as its cover, its edge or its blur reaches\n"
"  float band = 1.0 + 2.0 / u.scale + (kind == 2 ? max(I.p.w, 0.5) : max(I.p.z, 0.0));\n"
"  float d = mb_sd_box(p - c, hs, I.p.x, band);\n"
"  if (kind == 0 || kind == 5) d = notch_cut(d, p, I.rect, I.pad);\n"
"  if (kind == 9) { if (d > 0.0) discard_fragment(); return (float4(0.0)) * cover; }\n"
"  if (kind == 4) {\n"
"    constexpr sampler si(filter::linear, address::clamp_to_edge);\n"
"    float2 uv = I.c2.xy + clamp((p - I.rect.xy) / I.rect.zw, 0.0, 1.0) * I.c2.zw;\n"
"    return (img.sample(si, uv) * (col.a * clamp(0.5 - d * u.scale, 0.0, 1.0))) * cover;\n"
"  }\n"
"  if (kind == 2) {\n"
"    float b = max(I.p.w, 0.5);\n"
"    float a = 1.0 - smoothstep(-b, b, d);\n"
"    // glass's: only outside its box (c2.y above it)\n"
"    if (I.c2.x > 0.5) {\n"
"      float db = mb_sd_box(p - c + float2(0.0, I.c2.y), hs, I.p.x, band);\n"
"      a *= clamp(0.5 + db * u.scale, 0.0, 1.0);\n"
"    }\n"
"    return (float4(col.rgb, 1.0) * col.a * a) * cover;\n"
"  }\n"
"  float a = clamp(0.5 - d * u.scale, 0.0, 1.0);\n"
"  if (kind == 5) {\n"
"    // frosted: the blurred copy, saturated, the tint over it; the rim (a hairline inside the edge, the top left lit,\n"
"    // the foot and right less), 0.5 wide\n"
"    float3 g3 = backdrop(bd, g, p);\n"
"    g3 = max(mix(float3(luma(g3)), g3, I.p.z), 0.0);\n"
"    g3 = g3 * (1.0 - col.a) + col.rgb * col.a;\n"
"    if (I.c2.x + I.c2.y + I.c2.z > 0.0) {\n"
"      float edge = clamp(0.5 + (d + 0.5) * u.scale, 0.0, 1.0);\n"
"      float lit = clamp(0.5 + notch_cut(sd_rr(p - 0.5, I.rect, I.p.x), p - 0.5, I.rect, I.pad) * u.scale, 0.0, 1.0);\n"
"      float back = clamp(0.5 + notch_cut(sd_rr(p + 0.5, I.rect, I.p.x), p + 0.5, I.rect, I.pad) * u.scale, 0.0, 1.0);\n"
"      g3 = mix(g3, float3(1.0), I.c2.x * edge);\n"
"      g3 = mix(g3, float3(1.0), I.c2.y * lit);\n"
"      g3 = mix(g3, float3(1.0), I.c2.z * back);\n"
"    }\n"
"    return (float4(g3, 1.0) * (a * I.c2.w)) * cover;\n"
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
"struct PU { float4 a; float4 b; };\n"
"vertex float4 vpost(uint vid [[vertex_id]]) {\n"
"  float2 c = float2(vid == 1 ? 3.0 : -1.0, vid == 2 ? 3.0 : -1.0);\n"
"  return float4(c, 0.0, 1.0);\n"
"}\n"
"fragment float4 fpost(float4 pos [[position]], texture2d<float> src [[texture(0)]], constant PU& u [[buffer(0)]]) {\n"
"  constexpr sampler s(filter::linear, address::clamp_to_edge);\n"
"  float2 ts = u.a.xy;\n"
"  float2 lo = ts * 0.5, hi = u.b.xy;\n"
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

void mb_render_init(CAMetalLayer *layer) {
  dev = MTLCreateSystemDefaultDevice();
  queue = [dev newCommandQueue];
  mlayer = layer;
  layer.device = dev;
  layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
  // glass copies what is drawn so far out of the drawable
  layer.framebufferOnly = NO;
  // native views show under it through holes (mb_views_*); a frame clears opaque
  layer.opaque = NO;
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
  MTLTextureDescriptor *td = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                   width:mb_atlas_size
                                  height:mb_atlas_size
                               mipmapped:NO];
  td.usage = MTLTextureUsageShaderRead;
  atlas = [dev newTextureWithDescriptor:td];
  inflight = dispatch_semaphore_create(3);
}

id<MTLDevice> mb_render_device(void) { return dev; }

void mb_render_set_size(double w, double h, double scale) {
  vw = w;
  vh = h;
  vscale = scale;
  CGSize want = CGSizeMake(round(w * scale), round(h * scale));
  if (!CGSizeEqualToSize(mlayer.drawableSize, want)) mlayer.drawableSize = want;
}

void mb_atlas_upload(int x, int y, int w, int h, const void *rgba) {
  [atlas replaceRegion:MTLRegionMake2D(x, y, w, h) mipmapLevel:0 withBytes:rgba bytesPerRow:w * 4];
}

// ---------------------------------------------------------------------------
// Glass: when the instances reach a run of glass (slot 20 negative: the capture it shares), what is drawn so far
// under it (its rects with room for the blur round them) is copied out, halved down to where the blur is a few texels
// wide (dual Kawase's downsample, at most 1/8), blurred there by a Gaussian of what deviation is left, and drawn
// through.

typedef struct { float map[4]; float uvc[4]; float gb[4]; float shape[8][4]; float rad[2][4]; float misc[4]; } GU;
static GU gu;
static id<MTLTexture> gtex;  // the blurred copy the glass in view shows

static id<MTLTexture> level_tex(int w, int h) {
  MTLTextureDescriptor *td = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:(NSUInteger)(w > 0 ? w : 1)
                                  height:(NSUInteger)(h > 0 ? h : 1) mipmapped:NO];
  td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
  td.storageMode = MTLStorageModePrivate;
  return [dev newTextureWithDescriptor:td];
}

static void ensure_levels(int w, int h) {
  if (lv_w >= w && lv_h >= h && lv[0]) return;
  lv_w = w > lv_w ? w : lv_w;
  lv_h = h > lv_h ? h : lv_h;
  for (int j = 0; j < 4; j++) lv[j] = level_tex((lv_w + (1 << j) - 1) >> j, (lv_h + (1 << j) - 1) >> j);
  ltmp = level_tex(lv_w, lv_h);
}

// one pass of the blur: src into dst's top left (w × h); mode 1 halving, 2 a Gaussian of deviation sg along (dx, dy)
static void post_pass(id<MTLCommandBuffer> cb, id<MTLTexture> src, int sw, int sh, id<MTLTexture> dst, int w, int h,
                      int mode, float sg, float dx, float dy) {
  MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
  rp.colorAttachments[0].texture = dst;
  rp.colorAttachments[0].loadAction = MTLLoadActionDontCare;
  rp.colorAttachments[0].storeAction = MTLStoreActionStore;
  id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
  [e setRenderPipelineState:ppipe];
  [e setViewport:(MTLViewport){0, 0, (double)w, (double)h, 0, 1}];
  [e setScissorRect:(MTLScissorRect){0, 0, (NSUInteger)w, (NSUInteger)h}];
  float tw = 1.0f / (float)src.width, th = 1.0f / (float)src.height;
  struct { float a[4]; float b[4]; } u = {{tw, th, (float)mode, sg}, {((float)sw - 0.5f) * tw, ((float)sh - 0.5f) * th, dx, dy}};
  [e setFragmentBytes:&u length:sizeof u atIndex:0];
  [e setFragmentTexture:src atIndex:0];
  [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
  [e endEncoding];
}

// What the run [start, end) of glass sees, from target (tw × th pixels) into gtex and gu; 0 when none of it shows.
// Frosted glass of the same capture further on (glass.mbt shares_capture) is under it too.
static int capture(id<MTLCommandBuffer> cb, id<MTLTexture> target, const float *f, int32_t start, int32_t end,
                   int32_t count) {
  const float *a = f + start * MB_INST;
  float blur = a[7];
  int kind = (int)(a[5] + 0.5f);
  float margin = 3.0f * blur + (kind == 6 ? a[21] * (1.0f + a[22]) + a[23] : 0.0f) + 2.0f;
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
        for (int k = 0; k < 4; k++) gu.shape[n][k] = b[k];
        gu.rad[n / 4][n % 4] = b[4];
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
  gu.misc[0] = (float)n;
  gu.gb[0] = x0 - 2; gu.gb[1] = y0 - 2; gu.gb[2] = x1 + 2; gu.gb[3] = y1 + 2;
  int tw = (int)target.width, th = (int)target.height;
  float sc = (float)vscale;
  int px0 = (int)floorf((x0 - margin) * sc), py0 = (int)floorf((y0 - margin) * sc);
  int px1 = (int)ceilf((x1 + margin) * sc), py1 = (int)ceilf((y1 + margin) * sc);
  if (px0 < 0) px0 = 0;
  if (py0 < 0) py0 = 0;
  if (px1 > tw) px1 = tw;
  if (py1 > th) py1 = th;
  if (px1 <= px0 || py1 <= py0 || x1 <= x0 || y1 <= y0) return 0;
  int w = px1 - px0, h = py1 - py0;
  ensure_levels(tw, th);
  id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
  [bl copyFromTexture:target sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(px0, py0, 0)
           sourceSize:MTLSizeMake(w, h, 1) toTexture:lv[0] destinationSlice:0 destinationLevel:0
    destinationOrigin:MTLOriginMake(0, 0, 0)];
  [bl endEncoding];
  // down to where the deviation is 2 texels or more, at most 1/8
  float sp = blur * sc;
  int k = 0;
  while (k < 3 && sp / (float)(1 << (k + 1)) >= 2.0f) k++;
  int lw[4] = {w}, lh[4] = {h};
  for (int j = 1; j <= k; j++) {
    lw[j] = (lw[j - 1] + 1) / 2;
    lh[j] = (lh[j - 1] + 1) / 2;
    post_pass(cb, lv[j - 1], lw[j - 1], lh[j - 1], lv[j], lw[j], lh[j], 1, 0, 0, 0);
  }
  // what is left of the deviation once the halvings' and the last look's (bilinear) spread are taken out
  float sk = sp / (float)(1 << k);
  float pre = k > 0 ? 0.75f * (1.0f - powf(0.25f, (float)k)) / 3.0f + 1.0f / 6.0f : 0.0f;
  float sg = sqrtf(fmaxf(sk * sk - pre, 0.0f));
  if (sg > 0.3f) {
    post_pass(cb, lv[k], lw[k], lh[k], ltmp, lw[k], lh[k], 2, sg, 1, 0);
    post_pass(cb, ltmp, lw[k], lh[k], lv[k], lw[k], lh[k], 2, sg, 0, 1);
  }
  gtex = lv[k];
  float W = (float)gtex.width, H = (float)gtex.height, d = (float)(1 << k);
  gu.map[0] = sc / d / W; gu.map[1] = sc / d / H;
  gu.map[2] = -(float)px0 / d / W; gu.map[3] = -(float)py0 / d / H;
  gu.uvc[0] = 0.5f / W; gu.uvc[1] = 0.5f / H;
  gu.uvc[2] = ((float)lw[k] - 0.5f) / W; gu.uvc[3] = ((float)lh[k] - 0.5f) / H;
  return 1;
}

static id<MTLRenderCommandEncoder> begin_pass(id<MTLCommandBuffer> cb, id<MTLTexture> target, id<MTLRenderPipelineState> p,
                                              id<MTLBuffer> buf, int clear, double r, double g, double b) {
  MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
  rp.colorAttachments[0].texture = target;
  rp.colorAttachments[0].loadAction = clear ? MTLLoadActionClear : MTLLoadActionLoad;
  rp.colorAttachments[0].storeAction = MTLStoreActionStore;
  rp.colorAttachments[0].clearColor = MTLClearColorMake(r, g, b, 1);
  id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
  struct { float vp[2]; float scale; float pad; } u = {{(float)vw, (float)vh}, (float)vscale, 0};
  [enc setRenderPipelineState:p];
  [enc setVertexBuffer:buf offset:0 atIndex:0];
  [enc setVertexBytes:&u length:sizeof(u) atIndex:1];
  [enc setVertexBytes:&gu length:sizeof(gu) atIndex:2];
  [enc setFragmentBuffer:buf offset:0 atIndex:0];
  [enc setFragmentBytes:&u length:sizeof(u) atIndex:1];
  [enc setFragmentBytes:&gu length:sizeof(gu) atIndex:2];
  [enc setFragmentTexture:atlas atIndex:0];
  [enc setFragmentTexture:(gtex ?: atlas) atIndex:2];
  return enc;
}

static void encode(id<MTLCommandBuffer> cb, id<MTLTexture> target, id<MTLRenderPipelineState> p,
                   id<MTLBuffer> buf, int32_t count, double r, double g, double b) {
  gtex = nil;
  memset(&gu, 0, sizeof gu);
  id<MTLRenderCommandEncoder> enc = begin_pass(cb, target, p, buf, 1, r, g, b);
  // one draw per run of instances showing the same image (slot 20; 0:
  // none, the atlas stands in), or sharing one capture of glass (negative),
  // and holes for native views (kind 9) apart, unblended. Glass over a hole
  // sees the hole (the canvas only, not the view under it).
  const float *f = (const float *)buf.contents;
  int32_t start = 0;
  int bound = 0, shows = 0;
  while (start < count) {
    int tid = (int)f[start * MB_INST + 20];
    int hole = (int)(f[start * MB_INST + 5] + 0.5f) == 9;
    int32_t end = start + 1;
    while (end < count && (int)f[end * MB_INST + 20] == tid && ((int)(f[end * MB_INST + 5] + 0.5f) == 9) == hole) end++;
    if (tid < 0) {
      if (tid != bound) {
        [enc endEncoding];
        shows = capture(cb, target, f, start, end, count);
        bound = tid;
        enc = begin_pass(cb, target, p, buf, 0, r, g, b);
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
    id<MTLTexture> t = tid ? mb_image_texture(tid) : nil;
    [enc setFragmentTexture:(t ?: atlas) atIndex:1];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6
            instanceCount:end - start baseInstance:start];
    start = end;
  }
  [enc endEncoding];
}

// The instances into the next buffer of the ring (as floats), and a copy
// kept for snapshots.
static id<MTLBuffer> upload(const double *inst, int32_t count, double r, double g, double b) {
  buf_i = (buf_i + 1) % 3;
  size_t need = (size_t)(count > 0 ? count : 1) * MB_INST * sizeof(float);
  if (buf_cap[buf_i] < need) {
    size_t cap = need * 2;
    bufs[buf_i] = [dev newBufferWithLength:cap options:MTLResourceStorageModeShared];
    buf_cap[buf_i] = cap;
  }
  float *f = (float *)bufs[buf_i].contents;
  int32_t n = count * MB_INST;
  for (int32_t i = 0; i < n; i++) f[i] = (float)inst[i];
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

void mb_render_present(const double *inst, int32_t count, double r, double g, double b) {
  dispatch_semaphore_wait(inflight, DISPATCH_TIME_FOREVER);
  id<MTLBuffer> buf = upload(inst, count, r, g, b);
  id<CAMetalDrawable> drawable = [mlayer nextDrawable];
  id<MTLCommandBuffer> cb = [queue commandBuffer];
  if (drawable) encode(cb, drawable.texture, mpipe, buf, count, r, g, b);
  __block dispatch_semaphore_t sem = inflight;
  [cb addCompletedHandler:^(id<MTLCommandBuffer> done) {
    last_gpu = (done.GPUEndTime - done.GPUStartTime) * 1000.0;
    dispatch_semaphore_signal(sem);
  }];
  if (drawable) [cb presentDrawable:drawable];
  [cb commit];
}

// MBUI_SAFE's bands (mac_app.m), in points, and their ground
static double band_top, band_bottom;
static uint32_t band_ground;

void mb_render_set_bands(double top, double bottom, uint32_t ground) {
  band_top = top;
  band_bottom = bottom;
  band_ground = ground;
}

int mb_render_snapshot(const char *path) {
  int w = (int)round(vw * vscale), h = (int)round(vh * vscale);
  MTLTextureDescriptor *td = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:w height:h mipmapped:NO];
  td.usage = MTLTextureUsageRenderTarget;
#if TARGET_OS_OSX
  td.storageMode = MTLStorageModeManaged;
#else
  td.storageMode = MTLStorageModeShared;
#endif
  id<MTLTexture> tex = [dev newTextureWithDescriptor:td];
  id<MTLBuffer> buf = [dev newBufferWithBytes:last_inst length:(last_count > 0 ? last_count : 1) * MB_INST * sizeof(float) options:MTLResourceStorageModeShared];
  id<MTLCommandBuffer> cb = [queue commandBuffer];
  encode(cb, tex, rpipe_off, buf, last_count, last_bg[0], last_bg[1], last_bg[2]);
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
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGContextRef ctx = CGBitmapContextCreate(px, w, h, 8, bpr, cs,
      kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
  CGImageRef img = CGBitmapContextCreateImage(ctx);
  if (mb_views_count() > 0) {
    // the native views' content under the canvas, seen through its holes
    CGContextRef under = CGBitmapContextCreate(NULL, w, h, 8, bpr, cs,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    mb_views_draw_under(under, vscale);
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

// Without a window (the bench, src/bench): the renderer with no layer, and
// frames drawn into a texture kept across frames, the size a window's
// drawable would be, as nanoui's hill-climb draws its own.
static id<MTLTexture> off_target;

void mb_render_init_offscreen(double w, double h, double scale) {
  mb_render_init(nil);
  mb_render_set_size(w, h, scale);
  mb_text_scale = scale;
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
    encode(cb, off_target, mpipe, buf, count, r, g, b);
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
