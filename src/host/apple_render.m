// Metal renderer: one pipeline, one instanced quad per scene instance.
#import "apple.h"
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>

int mb_atlas_size = 2048;

static id<MTLDevice> dev;
static id<MTLCommandQueue> queue;
static id<MTLRenderPipelineState> mpipe;
static id<MTLRenderPipelineState> rpipe_off;
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

static NSString *shader_src = @
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"struct Inst { float4 rect; float4 p; float4 color; float4 c2; float4 clip; float4 pad; };\n"
"struct U { float2 vp; float scale; float pad; };\n"
"struct VOut { float4 pos [[position]]; float2 p; uint iid [[flat]]; };\n"
"vertex VOut vmain(uint vid [[vertex_id]], uint iid [[instance_id]],\n"
"    const device Inst* inst [[buffer(0)]], constant U& u [[buffer(1)]]) {\n"
"  Inst I = inst[iid];\n"
"  float2 corner = float2((vid == 1 || vid == 4 || vid == 5) ? 1.0 : 0.0,\n"
"                         (vid == 2 || vid == 3 || vid == 5) ? 1.0 : 0.0);\n"
"  int kind = int(I.p.y + 0.5);\n"
"  float grow = kind == 2 ? I.p.w * 2.0 + 2.0 : ((kind == 0 || kind == 4) ? 1.0 : 0.0);\n"
"  float2 pos = I.rect.xy - grow + corner * (I.rect.zw + 2.0 * grow);\n"
"  VOut o;\n"
"  o.pos = float4(pos.x / u.vp.x * 2.0 - 1.0, 1.0 - pos.y / u.vp.y * 2.0, 0.0, 1.0);\n"
"  o.p = pos; o.iid = iid;\n"
"  return o;\n"
"}\n"
"fragment float4 fmain(VOut in [[stage_in]], const device Inst* inst [[buffer(0)]],\n"
"    constant U& u [[buffer(1)]], texture2d<float> atlas [[texture(0)]],\n"
"    texture2d<float> img [[texture(1)]]) {\n"
"  Inst I = inst[in.iid];\n"
"  float2 p = in.p;\n"
"  if (p.x < I.clip.x || p.y < I.clip.y || p.x > I.clip.z || p.y > I.clip.w) discard_fragment();\n"
"  int kind = int(I.p.y + 0.5);\n"
"  float4 col = I.color;\n"
"  if (kind == 1 || kind == 3) {\n"
"    constexpr sampler s(filter::linear, coord::pixel);\n"
"    float2 uv = I.c2.xy + (p - I.rect.xy) / I.rect.zw * I.c2.zw;\n"
"    float4 t = atlas.sample(s, uv);\n"
"    if (kind == 1) return float4(col.rgb, 1.0) * (t.a * col.a);\n"
"    return t * col.a;\n"
"  }\n"
"  float2 hs = I.rect.zw * 0.5;\n"
"  float2 c = I.rect.xy + hs;\n"
"  float r = min(I.p.x, min(hs.x, hs.y));\n"
"  float2 q = abs(p - c) - hs + r;\n"
"  float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;\n"
"  if (kind == 4) {\n"
"    constexpr sampler si(filter::linear, address::clamp_to_edge);\n"
"    float2 uv = I.c2.xy + clamp((p - I.rect.xy) / I.rect.zw, 0.0, 1.0) * I.c2.zw;\n"
"    return img.sample(si, uv) * (col.a * clamp(0.5 - d * u.scale, 0.0, 1.0));\n"
"  }\n"
"  if (kind == 2) {\n"
"    float b = max(I.p.w, 0.5);\n"
"    float a = 1.0 - smoothstep(-b, b, d);\n"
"    return float4(col.rgb, 1.0) * col.a * a;\n"
"  }\n"
"  float a = clamp(0.5 - d * u.scale, 0.0, 1.0);\n"
"  float4 fill = float4(col.rgb, 1.0) * col.a;\n"
"  float bw = I.p.z;\n"
"  if (bw > 0.0) {\n"
"    float inner = clamp(0.5 - (d + bw) * u.scale, 0.0, 1.0);\n"
"    float4 bc = float4(I.c2.rgb, 1.0) * I.c2.a;\n"
"    fill = mix(bc, fill, inner);\n"
"  }\n"
"  return fill * a;\n"
"}\n";

static id<MTLRenderPipelineState> make_pipe(id<MTLLibrary> lib, MTLPixelFormat fmt) {
  MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new];
  d.vertexFunction = [lib newFunctionWithName:@"vmain"];
  d.fragmentFunction = [lib newFunctionWithName:@"fmain"];
  d.colorAttachments[0].pixelFormat = fmt;
  d.colorAttachments[0].blendingEnabled = YES;
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
  layer.framebufferOnly = YES;
  NSError *err = nil;
  id<MTLLibrary> lib = [dev newLibraryWithSource:shader_src options:nil error:&err];
  if (!lib) NSLog(@"shader: %@", err);
  mpipe = make_pipe(lib, MTLPixelFormatBGRA8Unorm);
  rpipe_off = mpipe;
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

static void encode(id<MTLCommandBuffer> cb, id<MTLTexture> target, id<MTLRenderPipelineState> p,
                   id<MTLBuffer> buf, int32_t count, double r, double g, double b) {
  MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
  rp.colorAttachments[0].texture = target;
  rp.colorAttachments[0].loadAction = MTLLoadActionClear;
  rp.colorAttachments[0].storeAction = MTLStoreActionStore;
  rp.colorAttachments[0].clearColor = MTLClearColorMake(r, g, b, 1);
  id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
  if (count > 0) {
    struct { float vp[2]; float scale; float pad; } u = {{(float)vw, (float)vh}, (float)vscale, 0};
    [enc setRenderPipelineState:p];
    [enc setVertexBuffer:buf offset:0 atIndex:0];
    [enc setVertexBytes:&u length:sizeof(u) atIndex:1];
    [enc setFragmentBuffer:buf offset:0 atIndex:0];
    [enc setFragmentBytes:&u length:sizeof(u) atIndex:1];
    [enc setFragmentTexture:atlas atIndex:0];
    // one draw per run of instances showing the same image (slot 20; 0:
    // none, the atlas stands in)
    const float *f = (const float *)buf.contents;
    int32_t start = 0;
    while (start < count) {
      int tid = (int)f[start * 24 + 20];
      int32_t end = start + 1;
      while (end < count && (int)f[end * 24 + 20] == tid) end++;
      id<MTLTexture> t = tid ? mb_image_texture(tid) : nil;
      [enc setFragmentTexture:(t ?: atlas) atIndex:1];
      [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6
              instanceCount:end - start baseInstance:start];
      start = end;
    }
  }
  [enc endEncoding];
}

void mb_render_present(const double *inst, int32_t count, double r, double g, double b) {
  dispatch_semaphore_wait(inflight, DISPATCH_TIME_FOREVER);
  buf_i = (buf_i + 1) % 3;
  size_t need = (size_t)(count > 0 ? count : 1) * 24 * sizeof(float);
  if (buf_cap[buf_i] < need) {
    size_t cap = need * 2;
    bufs[buf_i] = [dev newBufferWithLength:cap options:MTLResourceStorageModeShared];
    buf_cap[buf_i] = cap;
  }
  float *f = (float *)bufs[buf_i].contents;
  int32_t n = count * 24;
  for (int32_t i = 0; i < n; i++) f[i] = (float)inst[i];
  // keep a copy for snapshots
  if (last_cap < need) {
    last_inst = realloc(last_inst, need);
    last_cap = need;
  }
  memcpy(last_inst, f, (size_t)n * sizeof(float));
  last_count = count;
  last_bg[0] = r; last_bg[1] = g; last_bg[2] = b;

  id<CAMetalDrawable> drawable = [mlayer nextDrawable];
  id<MTLCommandBuffer> cb = [queue commandBuffer];
  if (drawable) encode(cb, drawable.texture, mpipe, bufs[buf_i], count, r, g, b);
  __block dispatch_semaphore_t sem = inflight;
  [cb addCompletedHandler:^(id<MTLCommandBuffer> _) { dispatch_semaphore_signal(sem); }];
  if (drawable) [cb presentDrawable:drawable];
  [cb commit];
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
  id<MTLBuffer> buf = [dev newBufferWithBytes:last_inst length:(last_count > 0 ? last_count : 1) * 24 * sizeof(float) options:MTLResourceStorageModeShared];
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
