// Streams on Windows (src/hostapi/stream.mbt, @ui's Stream): a stream's work on the thread pool, one piece after another
// in the order it came: JPEG frames decoded by WIC; H.264 (and H.265, where Windows has its decoder and the GPU decodes
// it) by the system's decoder (Media Foundation's: its config an avcC or an hvcC, its access units in AVCC, each made
// Annex B for it, a key frame after its parameter sets), low latency (a frame out as it goes in).
//
// On the GPU where it can (the renderer's device, made with video support: win_render.cpp): the decoder given a DXGI
// device manager decodes in hardware into Direct3D surfaces, each frame copied off its surface into an NV12 texture of
// the stream's own (a few kept for reuse), its colours made BGRA there by the video processor only when something
// shows it: the stream's system video layer (below), or the app's renderer drawing it (mb_stream_srv). Elsewhere (no
// video device, a decoder that will not decode on the GPU) as before: in software, its NV12 made BGRA on the CPU as its
// colours say (BT.709 or BT.601, video or full range) into a texture.
//
// Each frame is kept until the app shows it ("f TS W H", then mb_host_stream_show) or a later one; one that does not
// decode, or that the decoder passed over, is let go ("d TS"); the decoder failing says "b" and starts anew from the next
// key frame. Each event asks for a frame (mb_app_wake), or, while the stream shows itself on its layer, tells the app
// between frames (mb_app_streamed: ui's streams_said takes what changes nothing drawn without a frame).
//
// Routed (mb_stream_route_take, @hostapi.stream_direct): where the app's engine reads a remote screen itself (its
// shell), the frames of the view the app routed to a stream come here from the engine's thread, not through the app's
// queue: fed to the decoder in order, each decoded one shown at once (on the window's thread between frames, nothing of
// the app's run) and acknowledged to its sender, one let go acknowledged too. The app is told what came so in one event
// when it next reads the stream's ("D TS N BYTES": the last shown, how many frames came and their bytes since it was
// last told). A config stops the route until the app has taken it and routes it again. Its sound too: each packet
// played as it comes (below), nothing of the app's queue.
//
// A stream's sound (@hostapi.stream_audio, 48 kHz stereo PCM16 in 20 ms packets, the app's and a route's alike): a
// source voice of XAudio2's of its own (one engine for all), as apple_stream.m's player: started once 60 ms are
// queued, emptied past 300 ms queued (after a stall in the transport) and as it runs dry (an underrun refills the same
// reserve first); stopped by an empty packet (muted, the stream's sound gone) or as the stream closes.
//
// A stream's system video layer (@hostapi.stream_layers, a native view of kind 4: win_views.cpp hands its content's
// visual here, mb_stream_attach): a composition swap chain the size of the frame, in a visual of the views'
// DirectComposition tree under the canvas, stretched to the view's rect by its transform; each frame shown put there
// by the GPU (the video processor, or a copy of a BGRA frame) and presented, composed by the system with nothing of the
// app built or drawn. The remote pointer (@hostapi.stream_pointer) is a surface in a visual over it, placed in the
// picture's coordinates. A layer that shows the frame as sRGB (stream_layers 2: no Display P3 asked of the station).
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <d3d11.h>
#include <d3d10.h>
#include <dxgi1_2.h>
#include <dcomp.h>
#include <wincodec.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mftransform.h>
#include <mferror.h>
#include <wmcodecdsp.h>
#include <xaudio2.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "win.h"

#pragma comment(lib, "windowscodecs.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "wmcodecdspuuid.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "dxguid.lib")
#pragma comment(lib, "xaudio2.lib")

// A frame of NV12 on the GPU (the stream's own texture, the decoder's surface copied into it), as the video processor
// takes it: its size (even), its colours, its view for the processor (made as it is first shown, for the processor of
// its size)
struct Gpu {
  ID3D11Texture2D *tex;
  ID3D11VideoProcessorInputView *in;
  int w, h;
  int bt601, full;
};

struct StreamFrame {
  double ts;
  int w, h;
  ID3D11ShaderResourceView *srv;  // BGRA (JPEG, a frame decoded in software), or
  Gpu gpu;                        // NV12 on the GPU (gpu.tex NULL: none)
};

// A piece of a stream's work: a JPEG frame, a config (an avcC or an hvcC, the picture's size) or an access unit
enum { JOB_JPEG, JOB_CONFIG, JOB_FRAME };
struct StreamJob {
  int kind;
  double ts;
  uint8_t *data;
  size_t len;
  int key, w, h;
  int hevc;       // a config's: an hvcC (H.265)
  uint64_t route;  // a frame's: the route it came by (mb_stream_route_take), 0 the app's
};

// What was fed the decoder and is not out of it yet: its sample time there (a count) and its time
struct Fed {
  LONGLONG n;
  double ts;
  uint64_t route;  // the route it came by, 0 the app's: its fate acknowledged to its sender, not said
};

// A stream's decoder (its config's, started anew with each and as it fails; the stream's work's alone): the system's
// H.264 or H.265; the config's parameter sets in Annex B, put before each key frame; its NAL lengths' size; whether it
// waits for a key frame; the next frame's count; what was fed it, oldest first; the config's size; the picture it gives
// (NV12: its size as shown, its rows' count, its colours: BT.709, video range unless it says); whether it decodes on
// the GPU (given the device manager: its frames Direct3D surfaces)
struct H264 {
  IMFTransform *dec;
  uint8_t *head;
  size_t nhead;
  int nal_len;
  int need_key;
  LONGLONG next;
  Fed *fed;
  int nfed, cap_fed;
  UINT32 cw, ch, w, h, rows;
  int bt601, full;
  int hevc, gpu;
};

// a few of a stream's NV12 textures kept to be decoded into again
#define POOL 4

struct Stream {
  int id;
  int closed;
  // what it says, oldest first; frames decoded, not shown yet; JPEGs waiting; whether one is being decoded; its
  // textures free to be copied into (all under lock); what it is drawn with now (the UI thread's)
  char **events;
  int nevents, cap_events;
  StreamFrame *decoded;
  int ndecoded, cap_decoded;
  StreamJob *jobs;
  int njobs, cap_jobs;
  int busy;
  Gpu pool[POOL];
  int npool;
  StreamFrame cur;
  H264 *h264;
  // shown by its layer (attached: its events tell the app between frames); read by the decoder's thread
  volatile LONG layered;
  // its frames on the GPU not made BGRA there (vp_failed): its decoder in software from the next key frame
  volatile LONG no_gpu;
  // frames that came by a route: how many and their bytes (under lock); the last of them shown and what the app was
  // told of them ("D": the UI thread's)
  long direct_frames, direct_bytes, direct_told_frames, direct_told_bytes;
  double direct_at, direct_told_at;
  // the UI thread's: the video processor for frames of its size, and its BGRA picture for the app's renderer (made of
  // the frame shown when it is first drawn: `drawn_ts` of which)
  ID3D11VideoProcessorEnumerator *vpe;
  ID3D11VideoProcessor *vp;
  int vpw, vph, vp_said;
  ID3D11Texture2D *bgra;
  ID3D11ShaderResourceView *bgra_srv;
  ID3D11VideoProcessorOutputView *bgra_out;
  int bgra_w, bgra_h;
  double drawn_ts;
  int drawn;
  // its layer (the UI thread's): the view's content visual it is in, its picture's visual and swap chain (the frame's
  // size), the processor's view of its buffer; the view's rect (device pixels) and the window's scale
  IDCompositionVisual *content, *pic, *ptr;
  IDXGISwapChain1 *chain;
  ID3D11VideoProcessorOutputView *chain_out;
  int chain_w, chain_h, presented_w, presented_h;
  double place_w, place_h, place_scale;
  // its pointer: its picture (premultiplied BGRA, its size in pixels), its size and hot spot (points), where it points
  // (0..1 of the view's rect) and whether it shows; its surface, made again as its picture changes
  uint8_t *ptr_px;
  int ptr_pw, ptr_ph;
  double ptr_w, ptr_h, ptr_hx, ptr_hy, ptr_x, ptr_y;
  int ptr_shown, ptr_new;
  IDCompositionSurface *ptr_surface;
  // its sound (under sound_lock): its voice, whether it plays, its packets' memory (the voice reads each till played)
  IXAudio2SourceVoice *voice;
  int sound_playing, sound_gone;
  uint8_t *sound_ring;
  unsigned sound_next;
};

static Stream **streams;  // by id (ids are not reused)
static int nstreams, cap_streams;
static SRWLOCK streams_lock = SRWLOCK_INIT;  // the array as it grows (the engine's thread looks a stream up in it)
static CRITICAL_SECTION lock;
static int ready;

static void setup(void) {
  if (ready) return;
  ready = 1;
  InitializeCriticalSection(&lock);
}

static Stream *stream_of(int id) { return id > 0 && id < nstreams ? streams[id] : NULL; }

// ---- routes: a remote screen's frames straight from the app's engine ----

// A route (the app's call a view is) and the stream its frames go to (0: the app's to take), with the number of the
// last record offered by it (the app routes it only as it has taken that one: nothing of it left in its queue).
struct Route {
  uint64_t route, seq, used;
  int32_t video, audio;
};
#define ROUTES 8
static Route routes[ROUTES];
static uint64_t routes_used;
static SRWLOCK routes_lock = SRWLOCK_INIT;
static int (*route_ack)(double route, double ts);

// (under routes_lock) route's entry; made where `make` (in a free one, else one routing nothing used least lately)
static Route *route_at(uint64_t route, int make) {
  Route *empty = NULL, *old = NULL;
  for (int i = 0; i < ROUTES; i++) {
    Route *r = &routes[i];
    if (route && r->route == route) {
      r->used = ++routes_used;
      return r;
    }
    if (!r->route) {
      if (!empty) empty = r;
    } else if (!r->video && !r->audio && (!old || r->used < old->used)) {
      old = r;
    }
  }
  if (!make || !route) return NULL;
  Route *r = empty ? empty : old;
  if (r) *r = {route, 0, ++routes_used, 0, 0};
  return r;
}

// Whether route's frames go to stream sid now.
static int routed(uint64_t route, int sid) {
  AcquireSRWLockShared(&routes_lock);
  int on = 0;
  for (int i = 0; i < ROUTES; i++)
    if (route && routes[i].route == route) on = routes[i].video == sid;
  ReleaseSRWLockShared(&routes_lock);
  return on;
}

// Stream sid no longer where a route's frames (`what` 1) or sound (2) go.
static void unroute(int sid, int what) {
  AcquireSRWLockExclusive(&routes_lock);
  for (int i = 0; i < ROUTES; i++) {
    if ((what & 1) && routes[i].video == sid) routes[i].video = 0;
    if ((what & 2) && routes[i].audio == sid) routes[i].audio = 0;
  }
  ReleaseSRWLockExclusive(&routes_lock);
}

// Frame ts of route taken, as far as its sender is concerned (the engine's ack: any thread).
static void route_acked(uint64_t route, double ts) {
  if (route_ack) route_ack((double)route, ts);
}

// ---- the GPU's video side ----

// The renderer's device's (made with video support where it can be: win_render.cpp), its context made safe for the
// decoders' threads to use beside the UI thread's, and Media Foundation's manager of it for the decoders: 1 here, -1
// none (0 not looked for yet). Looked for on the UI thread (as a stream opens, as the app asks what it has), before any
// decoder's thread reads it.
static int video_state;
static ID3D11VideoDevice *vdev;
static ID3D11VideoContext *vctx;
static IMFDXGIDeviceManager *dxgi_manager;
static int mf_started;

static int video_here(void) {
  if (video_state) return video_state > 0;
  ID3D11Device *dev = (ID3D11Device *)mb_render_device();
  ID3D11DeviceContext *ctx = (ID3D11DeviceContext *)mb_render_context();
  // (no device yet: asked again later)
  if (!dev || !ctx) return 0;
  video_state = -1;
  const char *no = getenv("MBUI_NO_VIDEO_GPU");
  if (no && *no && *no != '0') return 0;
  ID3D10Multithread *mt = NULL;
  UINT token = 0;
  if (FAILED(dev->QueryInterface(IID_PPV_ARGS(&vdev))) || FAILED(ctx->QueryInterface(IID_PPV_ARGS(&vctx))) ||
      FAILED(dev->QueryInterface(IID_PPV_ARGS(&mt)))) {
    if (vdev) vdev->Release();
    if (vctx) vctx->Release();
    vdev = NULL;
    vctx = NULL;
    fprintf(stdout, "win: streams: no video device (frames made on the CPU, drawn by the app)\n");
    fflush(stdout);
    return 0;
  }
  // (the decoders' threads use the immediate context too: each call under its lock)
  mt->SetMultithreadProtected(TRUE);
  mt->Release();
  if (!mf_started && SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_LITE))) mf_started = 1;
  if (FAILED(MFCreateDXGIDeviceManager(&token, &dxgi_manager)) || FAILED(dxgi_manager->ResetDevice(dev, token))) {
    if (dxgi_manager) dxgi_manager->Release();
    dxgi_manager = NULL;
  }
  video_state = 1;
  fprintf(stdout, "win: streams: on the GPU (its decoders %s)\n", dxgi_manager ? "too" : "not: no device manager");
  fflush(stdout);
  return 1;
}

// whether the GPU decodes `profile` into NV12 (D3D11_DECODER_PROFILE_*)
static int gpu_decodes(const GUID &profile) {
  if (!vdev) return 0;
  UINT n = vdev->GetVideoDecoderProfileCount();
  for (UINT i = 0; i < n; i++) {
    GUID g;
    BOOL ok = FALSE;
    if (SUCCEEDED(vdev->GetVideoDecoderProfile(i, &g)) && g == profile &&
        SUCCEEDED(vdev->CheckVideoDecoderFormat(&profile, DXGI_FORMAT_NV12, &ok)) && ok)
      return 1;
  }
  return 0;
}

// The system's H.265 decoder (Windows' HEVC Video Extensions, where installed: a decoder found by what it takes, not by
// a class of its own), NULL none.
static IMFTransform *hevc_decoder(void) {
  MFT_REGISTER_TYPE_INFO in = {MFMediaType_Video, MFVideoFormat_HEVC};
  IMFActivate **found = NULL;
  UINT32 n = 0;
  IMFTransform *t = NULL;
  if (FAILED(MFTEnumEx(MFT_CATEGORY_VIDEO_DECODER, MFT_ENUM_FLAG_SYNCMFT | MFT_ENUM_FLAG_LOCALMFT | MFT_ENUM_FLAG_SORTANDFILTER,
                       &in, NULL, &found, &n)))
    return NULL;
  for (UINT32 i = 0; i < n; i++) {
    if (!t && FAILED(found[i]->ActivateObject(IID_PPV_ARGS(&t)))) t = NULL;
    found[i]->Release();
  }
  CoTaskMemFree(found);
  return t;
}

// ---- its NV12 textures (any thread: the pool under lock) ----

static void gpu_drop(Gpu *g) {
  if (g->in) g->in->Release();
  if (g->tex) g->tex->Release();
  memset(g, 0, sizeof *g);
}

// One of its textures w × h to copy a frame into (one kept, else made): tex NULL none.
static Gpu gpu_take(Stream *s, int w, int h) {
  Gpu g = {};
  EnterCriticalSection(&lock);
  while (s->npool > 0) {
    Gpu k = s->pool[--s->npool];
    if (k.w == w && k.h == h) {
      g = k;
      break;
    }
    gpu_drop(&k);  // (another size's: the picture's changed)
  }
  LeaveCriticalSection(&lock);
  if (g.tex) return g;
  D3D11_TEXTURE2D_DESC td = {};
  td.Width = (UINT)w;
  td.Height = (UINT)h;
  td.MipLevels = td.ArraySize = 1;
  td.Format = DXGI_FORMAT_NV12;
  td.SampleDesc.Count = 1;
  td.Usage = D3D11_USAGE_DEFAULT;
  // (as a decoder's surface: what the video processor takes in, which one bound for shaders alone is not, NVIDIA's)
  td.BindFlags = D3D11_BIND_DECODER;
  ID3D11Device *dev = (ID3D11Device *)mb_render_device();
  if (FAILED(dev->CreateTexture2D(&td, NULL, &g.tex))) {
    td.BindFlags = 0;
    if (FAILED(dev->CreateTexture2D(&td, NULL, &g.tex))) g.tex = NULL;
  }
  g.w = w;
  g.h = h;
  return g;
}

// A texture it no longer shows, kept to be copied into again (a few), else let go.
static void gpu_give(Stream *s, Gpu *g) {
  if (!g->tex) return;
  EnterCriticalSection(&lock);
  int kept = !s->closed && s->npool < POOL;
  if (kept) s->pool[s->npool++] = *g;
  LeaveCriticalSection(&lock);
  if (kept) memset(g, 0, sizeof *g);
  else gpu_drop(g);
}

static void frame_free(Stream *s, StreamFrame *f) {
  if (f->srv) f->srv->Release();
  f->srv = NULL;
  gpu_give(s, &f->gpu);
}

// ---- what it says ----

// The app told: while the stream shows itself on its layer, between frames (what changes nothing drawn taken without
// one), else by a frame.
static void tell_app(Stream *s) {
  if (InterlockedCompareExchange(&s->layered, 0, 0)) mb_app_streamed(s->id);
  else mb_app_wake();
}

// under lock
static void say_locked(Stream *s, const char *e) {
  if (s->closed) return;
  if (s->nevents >= s->cap_events) {
    s->cap_events = s->cap_events ? s->cap_events * 2 : 16;
    s->events = (char **)realloc(s->events, (size_t)s->cap_events * sizeof *s->events);
  }
  s->events[s->nevents++] = _strdup(e);
}

static void num(char *out, size_t n, double v) {
  if (v == floor(v) && fabs(v) < 1e15) snprintf(out, n, "%lld", (long long)v);
  else snprintf(out, n, "%.17g", v);
}

static void say(Stream *s, const char *e) {
  EnterCriticalSection(&lock);
  say_locked(s, e);
  LeaveCriticalSection(&lock);
  tell_app(s);
}

static void say_dropped(Stream *s, double ts) {
  char t[40], e[48];
  num(t, sizeof t, ts);
  snprintf(e, sizeof e, "d %s", t);
  say(s, e);
}

// Frame ts let go: one that came by a route acknowledged to its sender, else said.
static void let_go(Stream *s, double ts, uint64_t route) {
  if (route) route_acked(route, ts);
  else say_dropped(s, ts);
}

// A frame decoded (srv or gpu its picture: neither, one that was not) kept till it is shown, and said: "f TS W H", or
// "d TS".
static void say_decoded(Stream *s, double ts, int w, int h, ID3D11ShaderResourceView *srv, Gpu *gpu) {
  char tt[40], e[96];
  num(tt, sizeof tt, ts);
  int has = srv || (gpu && gpu->tex);
  EnterCriticalSection(&lock);
  if (has && !s->closed) {
    if (s->ndecoded >= s->cap_decoded) {
      s->cap_decoded = s->cap_decoded ? s->cap_decoded * 2 : 8;
      s->decoded = (StreamFrame *)realloc(s->decoded, (size_t)s->cap_decoded * sizeof *s->decoded);
    }
    StreamFrame f = {};
    f.ts = ts;
    f.w = w;
    f.h = h;
    f.srv = srv;
    if (gpu) f.gpu = *gpu;
    s->decoded[s->ndecoded++] = f;
    snprintf(e, sizeof e, "f %s %d %d", tt, w, h);
    srv = NULL;
    if (gpu) memset(gpu, 0, sizeof *gpu);
  } else {
    snprintf(e, sizeof e, "d %s", tt);
  }
  say_locked(s, e);
  LeaveCriticalSection(&lock);
  if (srv) srv->Release();
  if (gpu) gpu_give(s, gpu);
  tell_app(s);
}

// Premultiplied BGRA pixels, w × h, in a texture: its view (NULL: none made)
static ID3D11ShaderResourceView *texture_of(const uint8_t *px, UINT w, UINT h) {
  D3D11_TEXTURE2D_DESC td = {};
  td.Width = w;
  td.Height = h;
  td.MipLevels = td.ArraySize = 1;
  td.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  td.SampleDesc.Count = 1;
  td.Usage = D3D11_USAGE_IMMUTABLE;
  td.BindFlags = D3D11_BIND_SHADER_RESOURCE;
  D3D11_SUBRESOURCE_DATA init = {px, w * 4, 0};
  ID3D11Device *dev = (ID3D11Device *)mb_render_device();
  ID3D11Texture2D *tex = NULL;
  ID3D11ShaderResourceView *srv = NULL;
  if (FAILED(dev->CreateTexture2D(&td, &init, &tex)) || FAILED(dev->CreateShaderResourceView(tex, NULL, &srv))) srv = NULL;
  if (tex) tex->Release();
  return srv;
}

// An image's (a JPEG's, a PNG's) pixels as premultiplied BGRA (malloc'd, w × h), NULL when it does not decode.
static uint8_t *bgra_of_image(const uint8_t *data, size_t len, int *w, int *h) {
  IWICImagingFactory *wic = NULL;
  IWICStream *stream = NULL;
  IWICBitmapDecoder *dec = NULL;
  IWICBitmapFrameDecode *frame = NULL;
  IWICFormatConverter *conv = NULL;
  uint8_t *px = NULL;
  UINT sw = 0, sh = 0;
  if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER, __uuidof(IWICImagingFactory),
                              (void **)&wic)) ||
      FAILED(wic->CreateStream(&stream)) || FAILED(stream->InitializeFromMemory((BYTE *)data, (DWORD)len)) ||
      FAILED(wic->CreateDecoderFromStream(stream, NULL, WICDecodeMetadataCacheOnDemand, &dec)) ||
      FAILED(dec->GetFrame(0, &frame)) || FAILED(frame->GetSize(&sw, &sh)) || !sw || !sh ||
      FAILED(wic->CreateFormatConverter(&conv)) ||
      FAILED(conv->Initialize(frame, GUID_WICPixelFormat32bppPBGRA, WICBitmapDitherTypeNone, NULL, 0,
                              WICBitmapPaletteTypeCustom)))
    goto done;
  {
    UINT stride = sw * 4;
    px = (uint8_t *)malloc((size_t)stride * sh);
    if (px && FAILED(conv->CopyPixels(NULL, stride, stride * sh, px))) {
      free(px);
      px = NULL;
    }
    *w = (int)sw;
    *h = (int)sh;
  }
done:
  if (conv) conv->Release();
  if (frame) frame->Release();
  if (dec) dec->Release();
  if (stream) stream->Release();
  if (wic) wic->Release();
  return px;
}

// A JPEG's pixels as premultiplied BGRA in a texture: its view, NULL when it does not decode.
static ID3D11ShaderResourceView *decode_jpeg(const uint8_t *data, size_t len, int *w, int *h) {
  uint8_t *px = bgra_of_image(data, len, w, h);
  ID3D11ShaderResourceView *srv = px ? texture_of(px, (UINT)*w, (UINT)*h) : NULL;
  free(px);
  return srv;
}

// ---- a routed frame decoded: shown on the window's thread ----

static void layer_present(Stream *s);

struct Direct {
  int sid;
  uint64_t route;
  StreamFrame f;
};

// (the window's thread) a frame that came by a route, decoded: shown and acknowledged here while the route still goes
// to its stream, nothing of the app's run; else kept and said, as the app's are.
static void direct_shown(void *arg) {
  Direct *x = (Direct *)arg;
  Stream *s = stream_of(x->sid);
  StreamFrame f = x->f;
  uint64_t route = x->route;
  free(x);
  if (!s || s->closed) {
    if (s) frame_free(s, &f);
    else if (f.srv) f.srv->Release(), gpu_drop(&f.gpu);
    else gpu_drop(&f.gpu);
    route_acked(route, f.ts);
    return;
  }
  if (!routed(route, s->id)) {
    say_decoded(s, f.ts, f.w, f.h, f.srv, f.gpu.tex ? &f.gpu : NULL);
    return;
  }
  // (what the app said decoded before it and has not shown yet: passed over)
  EnterCriticalSection(&lock);
  int k = 0;
  for (int i = 0; i < s->ndecoded; i++) {
    if (s->decoded[i].ts > f.ts) s->decoded[k++] = s->decoded[i];
    else frame_free(s, &s->decoded[i]);
  }
  s->ndecoded = k;
  LeaveCriticalSection(&lock);
  frame_free(s, &s->cur);
  s->cur = f;
  s->drawn = 0;
  s->direct_at = f.ts;
  layer_present(s);
  route_acked(route, f.ts);
}

// (the stream's work) a frame of route decoded: to the window's thread, to be shown there
static void direct_decoded(Stream *s, double ts, int w, int h, ID3D11ShaderResourceView *srv, Gpu *gpu, uint64_t route) {
  if (!srv && !(gpu && gpu->tex)) return route_acked(route, ts);
  Direct *x = (Direct *)calloc(1, sizeof(Direct));
  x->sid = s->id;
  x->route = route;
  x->f.ts = ts;
  x->f.w = w;
  x->f.h = h;
  x->f.srv = srv;
  if (gpu) x->f.gpu = *gpu;
  mb_app_call(direct_shown, x);
}

// ---- H.264 and H.265 (the stream's work's alone: on the pool, one piece at a time) ----

// what was fed the decoder and is not out of it, let go: "d" of the last's time
static void fed_dropped(Stream *s) {
  H264 *d = s->h264;
  if (!d || !d->nfed) return;
  // (the app's said let go up to the newest of them; a route's acknowledged up to its newest)
  double app = -1, direct = -1;
  uint64_t route = 0;
  for (int i = 0; i < d->nfed; i++) {
    if (d->fed[i].route) direct = d->fed[i].ts, route = d->fed[i].route;
    else app = d->fed[i].ts;
  }
  d->nfed = 0;
  if (app >= 0) say_dropped(s, app);
  if (direct >= 0) route_acked(route, direct);
}

static void h264_stop(H264 *d) {
  if (d->dec) d->dec->Release();
  d->dec = NULL;
  d->gpu = 0;
}

static void h264_free(Stream *s) {
  H264 *d = s->h264;
  if (!d) return;
  h264_stop(d);
  free(d->head);
  free(d->fed);
  free(d);
  s->h264 = NULL;
}

// a NAL after a start code, at the end of the config's head
static void head_put(H264 *d, const uint8_t *nal, size_t len) {
  uint8_t *p = d->head + d->nhead;
  p[0] = p[1] = p[2] = 0, p[3] = 1;
  memcpy(p + 4, nal, len);
  d->nhead += 4 + len;
}

// the avcC's NAL lengths' size, and its SPS and PPS in Annex B: 0 not an avcC
static int avcc_read(H264 *d, const uint8_t *a, size_t n) {
  if (n < 7 || a[0] != 1) return 0;
  d->nal_len = (a[4] & 3) + 1;
  free(d->head);
  d->head = (uint8_t *)malloc(n * 2 + 16);
  d->nhead = 0;
  size_t at = 5;
  for (int set = 0; set < 2 && at < n; set++) {
    int count = set == 0 ? (a[at] & 31) : a[at];
    at++;
    for (int i = 0; i < count && at + 2 <= n; i++) {
      size_t len = ((size_t)a[at] << 8) | a[at + 1];
      at += 2;
      if (len > n - at) break;
      head_put(d, a + at, len);
      at += len;
    }
  }
  return d->nhead > 0;
}

// the hvcC's (ISO/IEC 14496-15 8.3.3) NAL lengths' size, and its VPS, SPS and PPS (and whatever else it carries) in
// Annex B: 0 not an hvcC
static int hvcc_read(H264 *d, const uint8_t *a, size_t n) {
  if (n < 23 || a[0] != 1) return 0;
  d->nal_len = (a[21] & 3) + 1;
  if (d->nal_len == 3) return 0;
  free(d->head);
  d->head = (uint8_t *)malloc(n * 2 + 16);
  d->nhead = 0;
  int arrays = a[22], sets = 0;
  size_t at = 23;
  for (int k = 0; k < arrays && at + 3 <= n; k++) {
    int type = a[at] & 0x3f, units = (a[at + 1] << 8) | a[at + 2];
    at += 3;
    for (int i = 0; i < units && at + 2 <= n; i++) {
      size_t len = ((size_t)a[at] << 8) | a[at + 1];
      at += 2;
      if (len > n - at) return 0;
      head_put(d, a + at, len);
      if (type >= 32 && type <= 34) sets++;
      at += len;
    }
  }
  return sets >= 3;
}

// the decoder's output NV12, and what it says of it (its size as shown, its rows as given, its colours): 1 set
static int h264_output(H264 *d) {
  for (DWORD i = 0;; i++) {
    IMFMediaType *mt = NULL;
    if (FAILED(d->dec->GetOutputAvailableType(0, i, &mt))) return 0;
    GUID sub = GUID_NULL;
    mt->GetGUID(MF_MT_SUBTYPE, &sub);
    if (sub == MFVideoFormat_NV12 && SUCCEEDED(d->dec->SetOutputType(0, mt, 0))) {
      UINT32 w = 0, h = 0;
      if (SUCCEEDED(MFGetAttributeSize(mt, MF_MT_FRAME_SIZE, &w, &h)) && w && h) d->w = w, d->h = h, d->rows = h;
      MFVideoArea area;
      UINT32 got = 0;
      if (SUCCEEDED(mt->GetBlob(MF_MT_MINIMUM_DISPLAY_APERTURE, (UINT8 *)&area, sizeof area, &got)) &&
          got == sizeof area && area.Area.cx > 0 && area.Area.cy > 0 && (UINT32)area.Area.cy <= d->rows)
        d->w = (UINT32)area.Area.cx, d->h = (UINT32)area.Area.cy;
      UINT32 m = 0, r = 0;
      d->bt601 = SUCCEEDED(mt->GetUINT32(MF_MT_YUV_MATRIX, &m)) && m == MFVideoTransferMatrix_BT601;
      d->full = SUCCEEDED(mt->GetUINT32(MF_MT_VIDEO_NOMINAL_RANGE, &r)) && r == MFNominalRange_0_255;
      mt->Release();
      return 1;
    }
    mt->Release();
  }
}

// The decoder for the config's picture, w × h, from the next key frame (H.264's, or H.265's: d->hevc), decoding on the
// GPU where it will (given the device manager before its types: d->gpu), else in software: 1 started.
static int h264_start(Stream *s, UINT32 w, UINT32 h) {
  H264 *d = s->h264;
  d->need_key = 1;
  d->gpu = 0;
  d->cw = w, d->ch = h;
  d->w = w, d->h = h, d->rows = h;
  if (!mf_started) {
    if (FAILED(MFStartup(MF_VERSION, MFSTARTUP_LITE))) return 0;
    mf_started = 1;
  }
  IMFMediaType *in = NULL;
  IMFAttributes *at = NULL;
  HRESULT hr = S_OK;
  if (d->hevc) {
    d->dec = hevc_decoder();
    if (!d->dec) hr = MF_E_TOPO_CODEC_NOT_FOUND;
  } else {
    hr = CoCreateInstance(CLSID_CMSH264DecoderMFT, NULL, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&d->dec));
  }
  if (SUCCEEDED(hr) && SUCCEEDED(d->dec->GetAttributes(&at))) {
    // (a frame out as it goes in, none held back for the order of frames a screen's never has)
    at->SetUINT32(MF_LOW_LATENCY, TRUE);
    // on the GPU: its frames Direct3D surfaces, copied off by the GPU (h264_drain)
    UINT32 aware = 0;
    if (video_state > 0 && dxgi_manager && !InterlockedCompareExchange(&s->no_gpu, 0, 0) &&
        SUCCEEDED(at->GetUINT32(MF_SA_D3D11_AWARE, &aware)) && aware &&
        SUCCEEDED(d->dec->ProcessMessage(MFT_MESSAGE_SET_D3D_MANAGER, (ULONG_PTR)dxgi_manager)))
      d->gpu = 1;
    at->Release();
  }
  if (SUCCEEDED(hr)) hr = MFCreateMediaType(&in);
  if (SUCCEEDED(hr)) hr = in->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  if (SUCCEEDED(hr)) hr = in->SetGUID(MF_MT_SUBTYPE, d->hevc ? MFVideoFormat_HEVC : MFVideoFormat_H264);
  if (SUCCEEDED(hr)) hr = MFSetAttributeSize(in, MF_MT_FRAME_SIZE, w, h);
  if (SUCCEEDED(hr)) hr = in->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  if (SUCCEEDED(hr)) hr = d->dec->SetInputType(0, in, 0);
  if (FAILED(hr) && d->gpu && d->dec) {
    // (not this picture on the GPU: in software)
    d->dec->ProcessMessage(MFT_MESSAGE_SET_D3D_MANAGER, 0);
    d->gpu = 0;
    hr = d->dec->SetInputType(0, in, 0);
  }
  if (in) in->Release();
  if (SUCCEEDED(hr) && !h264_output(d)) hr = E_FAIL;
  if (SUCCEEDED(hr)) hr = d->dec->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
  if (SUCCEEDED(hr)) hr = d->dec->ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);
  if (FAILED(hr)) {
    fprintf(stdout, "win: stream %d: no %s decoder (%08lx)\n", s->id, d->hevc ? "H.265" : "H.264", (unsigned long)hr);
    fflush(stdout);
    h264_stop(d);
    return 0;
  }
  fprintf(stdout, "win: stream %d: %s %ux%u decoded %s\n", s->id, d->hevc ? "H.265" : "H.264", w, h,
          d->gpu ? "on the GPU" : "in software");
  fflush(stdout);
  return 1;
}

// the decoder failed: what was in it let go, said ("b"), and anew from the next key frame
static void h264_broken(Stream *s, HRESULT hr) {
  H264 *d = s->h264;
  fprintf(stdout, "win: stream %d: its decoder failed (%08lx)\n", s->id, (unsigned long)hr);
  fflush(stdout);
  fed_dropped(s);
  say(s, "b");
  h264_stop(d);
  h264_start(s, d->cw, d->ch);
}

// NV12 (its rows `stride` bytes apart, `rows` of them before the chroma's) into BGRA as its colours say: BT.709 or
// BT.601, video range (16-235, 16-240) or full; a texture's view (NULL: none made)
static ID3D11ShaderResourceView *bgra_of_nv12(H264 *d, const uint8_t *nv12, size_t len) {
  UINT32 w = d->w, h = d->h, rows = d->rows;
  if (!rows || len < (size_t)rows * 3 / 2) return NULL;
  size_t stride = len * 2 / ((size_t)rows * 3);
  if (stride < w || h > rows) return NULL;
  const uint8_t *Y = nv12, *UV = nv12 + stride * rows;
  // (×1024: R = Y + kr·Cr, G = Y − kgb·Cb − kgr·Cr, B = Y + kb·Cb)
  int kr = d->bt601 ? 1436 : 1613, kgb = d->bt601 ? 352 : 192, kgr = d->bt601 ? 731 : 479, kb = d->bt601 ? 1815 : 1900;
  uint8_t *px = (uint8_t *)malloc((size_t)w * h * 4);
  if (!px) return NULL;
  for (UINT32 y = 0; y < h; y++) {
    const uint8_t *yr = Y + stride * y, *cr = UV + stride * (y / 2);
    uint8_t *o = px + (size_t)w * 4 * y;
    for (UINT32 x = 0; x < w; x++) {
      int l = yr[x], u = cr[x & ~1u] - 128, v = cr[(x & ~1u) + 1] - 128;
      if (!d->full) l = ((l - 16) * 1192) >> 10, u = (u * 1166) >> 10, v = (v * 1166) >> 10;
      int r = l + ((kr * v) >> 10), g = l - ((kgb * u + kgr * v) >> 10), b = l + ((kb * u) >> 10);
      o[0] = (uint8_t)(b < 0 ? 0 : b > 255 ? 255 : b);
      o[1] = (uint8_t)(g < 0 ? 0 : g > 255 ? 255 : g);
      o[2] = (uint8_t)(r < 0 ? 0 : r > 255 ? 255 : r);
      o[3] = 255;
      o += 4;
    }
  }
  ID3D11ShaderResourceView *srv = texture_of(px, w, h);
  free(px);
  return srv;
}

// A frame the GPU decoded (its sample's Direct3D surface, a slice of the decoder's) copied by the GPU into a texture
// of the stream's own, its size even (NV12's halves), so the decoder has its surface back at once: tex NULL failed.
static Gpu gpu_copy_off(Stream *s, H264 *d, IMFSample *smp) {
  Gpu g = {};
  IMFMediaBuffer *b = NULL;
  IMFDXGIBuffer *xb = NULL;
  ID3D11Texture2D *src = NULL;
  UINT sub = 0;
  int w = (int)(d->w & ~1u), h = (int)(d->h & ~1u);
  if (w > 0 && h > 0 && SUCCEEDED(smp->GetBufferByIndex(0, &b)) && SUCCEEDED(b->QueryInterface(IID_PPV_ARGS(&xb))) &&
      SUCCEEDED(xb->GetResource(IID_PPV_ARGS(&src))) && SUCCEEDED(xb->GetSubresourceIndex(&sub))) {
    g = gpu_take(s, w, h);
    if (g.tex) {
      D3D11_BOX box = {0, 0, 0, (UINT)w, (UINT)h, 1};
      ((ID3D11DeviceContext *)mb_render_context())->CopySubresourceRegion(g.tex, 0, 0, 0, 0, src, sub, &box);
      g.bt601 = d->bt601;
      g.full = d->full;
    }
  }
  if (src) src->Release();
  if (xb) xb->Release();
  if (b) b->Release();
  return g;
}

// what the decoder has out, each frame as fed (those it passed over before one let go: "d"), till it wants more
static void h264_drain(Stream *s) {
  H264 *d = s->h264;
  while (d->dec) {
    MFT_OUTPUT_STREAM_INFO info = {};
    d->dec->GetOutputStreamInfo(0, &info);
    IMFSample *mine = NULL;
    if (!(info.dwFlags & (MFT_OUTPUT_STREAM_PROVIDES_SAMPLES | MFT_OUTPUT_STREAM_CAN_PROVIDE_SAMPLES))) {
      IMFMediaBuffer *b = NULL;
      if (FAILED(MFCreateSample(&mine)) || FAILED(MFCreateMemoryBuffer(info.cbSize, &b))) {
        if (mine) mine->Release();
        return;
      }
      mine->AddBuffer(b);
      b->Release();
    }
    MFT_OUTPUT_DATA_BUFFER o = {0, mine, 0, NULL};
    DWORD status = 0;
    HRESULT hr = d->dec->ProcessOutput(0, 1, &o, &status);
    if (o.pEvents) o.pEvents->Release();
    if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT) {
      if (o.pSample) o.pSample->Release();
      return;
    }
    if (hr == MF_E_TRANSFORM_STREAM_CHANGE) {
      if (o.pSample) o.pSample->Release();
      if (!h264_output(d)) return h264_broken(s, hr);
      continue;
    }
    if (FAILED(hr) || !o.pSample) {
      if (o.pSample) o.pSample->Release();
      return h264_broken(s, hr);
    }
    LONGLONG t = 0;
    o.pSample->GetSampleTime(&t);
    LONGLONG n = (t + 5000) / 10000;
    double ts = -1, passed = -1, passed_direct = -1;
    uint64_t route = 0, passed_route = 0;
    int k = 0;
    while (k < d->nfed && d->fed[k].n <= n) {
      if (d->fed[k].n == n) ts = d->fed[k].ts, route = d->fed[k].route;
      else if (d->fed[k].route) passed_direct = d->fed[k].ts, passed_route = d->fed[k].route;
      else passed = d->fed[k].ts;
      k++;
    }
    memmove(d->fed, d->fed + k, (size_t)(d->nfed - k) * sizeof *d->fed);
    d->nfed -= k;
    if (passed >= 0) say_dropped(s, passed);
    if (passed_direct >= 0) route_acked(passed_route, passed_direct);
    ID3D11ShaderResourceView *srv = NULL;
    Gpu gpu = {};
    if (ts >= 0 && d->gpu) {
      gpu = gpu_copy_off(s, d, o.pSample);
    } else if (ts >= 0) {
      IMFMediaBuffer *cb = NULL;
      BYTE *px = NULL;
      DWORD len = 0;
      if (SUCCEEDED(o.pSample->ConvertToContiguousBuffer(&cb)) && SUCCEEDED(cb->Lock(&px, NULL, &len))) {
        srv = bgra_of_nv12(d, px, len);
        cb->Unlock();
      }
      if (cb) cb->Release();
    }
    o.pSample->Release();
    if (ts < 0) continue;
    if (route) {
      direct_decoded(s, ts, (int)d->w, (int)d->h, srv, gpu.tex ? &gpu : NULL, route);
      continue;
    }
    say_decoded(s, ts, (int)d->w, (int)d->h, srv, gpu.tex ? &gpu : NULL);
  }
}

// a config: the decoder anew (what was in it let go), from the next key frame
static void h264_config(Stream *s, StreamJob *j) {
  if (!s->h264) s->h264 = (H264 *)calloc(1, sizeof(H264));
  H264 *d = s->h264;
  fed_dropped(s);
  h264_stop(d);
  d->hevc = j->hevc;
  if (!(j->hevc ? hvcc_read(d, j->data, j->len) : avcc_read(d, j->data, j->len))) {
    fprintf(stdout, "win: stream %d: its config is no %s\n", s->id, j->hevc ? "hvcC" : "avcC");
    fflush(stdout);
    return;
  }
  h264_start(s, (UINT32)j->w, (UINT32)j->h);
}

// an access unit: made Annex B (a key frame after the config's parameter sets), fed, and what comes of it said
static void h264_frame(Stream *s, StreamJob *j) {
  H264 *d = s->h264;
  if (d && d->dec && d->gpu && InterlockedCompareExchange(&s->no_gpu, 0, 0)) {
    // (its frames on the GPU cannot be shown: anew in software, from the next key frame, which "b" asks for)
    fed_dropped(s);
    say(s, "b");
    h264_stop(d);
    h264_start(s, d->cw, d->ch);
  }
  if (!d || !d->dec || (d->need_key && !j->key)) return let_go(s, j->ts, j->route);
  d->need_key = 0;
  size_t cap = j->len * 3 + (j->key ? d->nhead : 0) + 16;
  IMFMediaBuffer *buf = NULL;
  IMFSample *smp = NULL;
  BYTE *p = NULL;
  if (FAILED(MFCreateMemoryBuffer((DWORD)cap, &buf)) || FAILED(buf->Lock(&p, NULL, NULL))) {
    if (buf) buf->Release();
    return let_go(s, j->ts, j->route);
  }
  size_t k = 0;
  if (j->key) memcpy(p, d->head, d->nhead), k = d->nhead;
  for (size_t at = 0; at + d->nal_len <= j->len;) {
    size_t n = 0;
    for (int i = 0; i < d->nal_len; i++) n = (n << 8) | j->data[at + i];
    at += d->nal_len;
    if (n > j->len - at) break;
    p[k] = p[k + 1] = p[k + 2] = 0, p[k + 3] = 1;
    memcpy(p + k + 4, j->data + at, n);
    k += 4 + n;
    at += n;
  }
  buf->Unlock();
  buf->SetCurrentLength((DWORD)k);
  if (FAILED(MFCreateSample(&smp))) {
    buf->Release();
    return let_go(s, j->ts, j->route);
  }
  smp->AddBuffer(buf);
  buf->Release();
  // (its time in the decoder a count: what comes out is matched to what went in by it, 1 ms in the 100 ns MF's go by)
  LONGLONG n = ++d->next;
  smp->SetSampleTime(n * 10000);
  smp->SetSampleDuration(10000);
  if (j->key) smp->SetUINT32(MFSampleExtension_CleanPoint, TRUE);
  if (d->nfed >= d->cap_fed) {
    d->cap_fed = d->cap_fed ? d->cap_fed * 2 : 16;
    d->fed = (Fed *)realloc(d->fed, (size_t)d->cap_fed * sizeof *d->fed);
  }
  d->fed[d->nfed++] = {n, j->ts, j->route};
  HRESULT hr = d->dec->ProcessInput(0, smp, 0);
  if (hr == MF_E_NOTACCEPTING) {
    h264_drain(s);
    hr = d->dec ? d->dec->ProcessInput(0, smp, 0) : E_FAIL;
  }
  smp->Release();
  if (FAILED(hr)) return h264_broken(s, hr);
  h264_drain(s);
}

// Whether this machine has the system's H.264 decoder (not Windows' N editions without their media pack): asked once
static int h264_decoder_here(void) {
  static int here = -1;
  if (here >= 0) return here;
  HRESULT ci = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
  IMFTransform *t = NULL;
  here = SUCCEEDED(CoCreateInstance(CLSID_CMSH264DecoderMFT, NULL, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&t)));
  if (t) t->Release();
  if (SUCCEEDED(ci)) CoUninitialize();
  return here;
}

// Whether H.265 is decoded here: by the GPU (its HEVC Main profile into NV12) through the system's decoder (Windows'
// HEVC Video Extensions): asked once there is a device. Not in software alone (a screen's 4K, 60 times a second).
static int h265_decoder_here(void) {
  static int here = -1;
  if (here >= 0) return here;
  if (!video_here() || !dxgi_manager) return 0;
  here = 0;
  if (!gpu_decodes(D3D11_DECODER_PROFILE_HEVC_VLD_MAIN)) return 0;
  HRESULT ci = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
  IMFTransform *t = hevc_decoder();
  if (t) {
    IMFAttributes *at = NULL;
    UINT32 aware = 0;
    here = SUCCEEDED(t->GetAttributes(&at)) && SUCCEEDED(at->GetUINT32(MF_SA_D3D11_AWARE, &aware)) && aware;
    if (at) at->Release();
    t->Release();
  }
  if (SUCCEEDED(ci)) CoUninitialize();
  fprintf(stdout, "win: streams: H.265 %s\n", here ? "decoded on the GPU" : "not decoded here");
  fflush(stdout);
  return here;
}

// A stream's work done one piece after another, until none waits (a thread of the pool); the stream gone, its decoder
// with it.
static void CALLBACK work(PTP_CALLBACK_INSTANCE inst, void *arg) {
  Stream *s = (Stream *)arg;
  CoInitializeEx(NULL, COINIT_MULTITHREADED);
  for (;;) {
    EnterCriticalSection(&lock);
    if (s->njobs == 0 || s->closed) {
      int gone = s->closed;
      s->busy = 0;
      LeaveCriticalSection(&lock);
      if (gone) h264_free(s);
      break;
    }
    StreamJob j = s->jobs[0];
    memmove(s->jobs, s->jobs + 1, (size_t)(s->njobs - 1) * sizeof *s->jobs);
    s->njobs--;
    LeaveCriticalSection(&lock);
    if (j.kind != JOB_JPEG) {
      if (j.kind == JOB_CONFIG) h264_config(s, &j);
      else h264_frame(s, &j);
      free(j.data);
      continue;
    }
    int w = 0, h = 0;
    ID3D11ShaderResourceView *srv = decode_jpeg(j.data, j.len, &w, &h);
    free(j.data);
    say_decoded(s, j.ts, w, h, srv, NULL);
  }
  CoUninitialize();
}

// ---- its picture made BGRA by the video processor (the UI thread's) ----

// The processor for frames w × h (as large out), made again as their size changes (the views made for the one
// before let go with it): 1 here.
static int vp_ready(Stream *s, int w, int h) {
  if (s->vp && s->vpw == w && s->vph == h) return 1;
  if (!vdev || !vctx) return 0;
  if (s->vp) s->vp->Release();
  if (s->vpe) s->vpe->Release();
  s->vp = NULL;
  s->vpe = NULL;
  if (s->cur.gpu.in) s->cur.gpu.in->Release();
  s->cur.gpu.in = NULL;
  EnterCriticalSection(&lock);
  for (int i = 0; i < s->npool; i++)
    if (s->pool[i].in) s->pool[i].in->Release(), s->pool[i].in = NULL;
  LeaveCriticalSection(&lock);
  if (s->bgra_out) s->bgra_out->Release();
  s->bgra_out = NULL;
  D3D11_VIDEO_PROCESSOR_CONTENT_DESC cd = {};
  cd.InputFrameFormat = D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE;
  cd.InputFrameRate = {60, 1};
  cd.InputWidth = (UINT)w;
  cd.InputHeight = (UINT)h;
  cd.OutputFrameRate = {60, 1};
  cd.OutputWidth = (UINT)w;
  cd.OutputHeight = (UINT)h;
  cd.Usage = D3D11_VIDEO_USAGE_PLAYBACK_NORMAL;
  UINT in_ok = 0, out_ok = 0;
  if (FAILED(vdev->CreateVideoProcessorEnumerator(&cd, &s->vpe)) ||
      FAILED(s->vpe->CheckVideoProcessorFormat(DXGI_FORMAT_NV12, &in_ok)) ||
      !(in_ok & D3D11_VIDEO_PROCESSOR_FORMAT_SUPPORT_INPUT) ||
      FAILED(s->vpe->CheckVideoProcessorFormat(DXGI_FORMAT_B8G8R8A8_UNORM, &out_ok)) ||
      !(out_ok & D3D11_VIDEO_PROCESSOR_FORMAT_SUPPORT_OUTPUT) || FAILED(vdev->CreateVideoProcessor(s->vpe, 0, &s->vp))) {
    if (s->vpe) s->vpe->Release();
    s->vpe = NULL;
    s->vp = NULL;
    fprintf(stdout, "win: stream %d: no video processor for %dx%d\n", s->id, w, h);
    fflush(stdout);
    return 0;
  }
  s->vpw = w;
  s->vph = h;
  vctx->VideoProcessorSetStreamFrameFormat(s->vp, 0, D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE);
  vctx->VideoProcessorSetStreamAutoProcessingMode(s->vp, 0, FALSE);
  // (out: RGB's full range)
  D3D11_VIDEO_PROCESSOR_COLOR_SPACE out = {};
  out.RGB_Range = 0;
  vctx->VideoProcessorSetOutputColorSpace(s->vp, &out);
  return 1;
}

// Frame g into `target` (BGRA, g's size) as its colours say (BT.709 or BT.601, video range or full), through the
// output view kept in *view (made here, for this processor): 1 done.
// (what failed said once a stream; its decoder told to go on in software, its frames made BGRA on the CPU: h264_frame)
static int vp_failed(Stream *s, const char *what, HRESULT hr) {
  if (!s->vp_said) {
    s->vp_said = 1;
    fprintf(stdout, "win: stream %d: its frame not made BGRA: %s (%08lx); decoded in software from the next key frame\n",
            s->id, what, (unsigned long)hr);
    fflush(stdout);
  }
  InterlockedExchange(&s->no_gpu, 1);
  return 0;
}

static int vp_blt(Stream *s, Gpu *g, ID3D11Resource *target, ID3D11VideoProcessorOutputView **view) {
  if (!g->tex || !vp_ready(s, g->w, g->h)) return 0;
  HRESULT hr;
  if (!g->in) {
    D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC d = {};
    d.ViewDimension = D3D11_VPIV_DIMENSION_TEXTURE2D;
    if (FAILED(hr = vdev->CreateVideoProcessorInputView(g->tex, s->vpe, &d, &g->in))) {
      g->in = NULL;
      return vp_failed(s, "its input view", hr);
    }
  }
  if (!*view) {
    D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC d = {};
    d.ViewDimension = D3D11_VPOV_DIMENSION_TEXTURE2D;
    if (FAILED(hr = vdev->CreateVideoProcessorOutputView(target, s->vpe, &d, view))) {
      *view = NULL;
      return vp_failed(s, "its output view", hr);
    }
  }
  D3D11_VIDEO_PROCESSOR_COLOR_SPACE in = {};
  in.YCbCr_Matrix = g->bt601 ? 0 : 1;
  in.Nominal_Range = g->full ? D3D11_VIDEO_PROCESSOR_NOMINAL_RANGE_0_255 : D3D11_VIDEO_PROCESSOR_NOMINAL_RANGE_16_235;
  vctx->VideoProcessorSetStreamColorSpace(s->vp, 0, &in);
  D3D11_VIDEO_PROCESSOR_STREAM st = {};
  st.Enable = TRUE;
  st.pInputSurface = g->in;
  if (FAILED(hr = vctx->VideoProcessorBlt(s->vp, *view, 0, 1, &st))) return vp_failed(s, "the processor", hr);
  return 1;
}

// ---- its system video layer (the UI thread's) ----

static void layer_transform(Stream *s) {
  if (!s->pic || s->chain_w <= 0 || s->chain_h <= 0 || s->place_w <= 0 || s->place_h <= 0) return;
  D2D_MATRIX_3X2_F m = {};
  m._11 = (FLOAT)(s->place_w / s->chain_w);
  m._22 = (FLOAT)(s->place_h / s->chain_h);
  s->pic->SetTransform(m);
}

// Its swap chain w × h (made, or its buffers made again at a new size): 1 here.
static int chain_ready(Stream *s, int w, int h) {
  if (s->chain && s->chain_w == w && s->chain_h == h) return 1;
  if (s->chain && FAILED(s->chain->ResizeBuffers(2, (UINT)w, (UINT)h, DXGI_FORMAT_B8G8R8A8_UNORM, 0))) {
    s->pic->SetContent(NULL);
    s->chain->Release();
    s->chain = NULL;
  }
  if (!s->chain) {
    ID3D11Device *dev = (ID3D11Device *)mb_render_device();
    IDXGIDevice *xdev = NULL;
    IDXGIAdapter *adapter = NULL;
    IDXGIFactory2 *factory = NULL;
    DXGI_SWAP_CHAIN_DESC1 sd = {};
    sd.Width = (UINT)w;
    sd.Height = (UINT)h;
    sd.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    sd.SampleDesc.Count = 1;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.BufferCount = 2;
    sd.Scaling = DXGI_SCALING_STRETCH;
    // (a frame presented over one not shown yet takes its place: the newest shown, none queued behind)
    sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    sd.AlphaMode = DXGI_ALPHA_MODE_IGNORE;
    HRESULT hr = dev->QueryInterface(IID_PPV_ARGS(&xdev));
    if (SUCCEEDED(hr)) hr = xdev->GetAdapter(&adapter);
    if (SUCCEEDED(hr)) hr = adapter->GetParent(IID_PPV_ARGS(&factory));
    if (SUCCEEDED(hr)) hr = factory->CreateSwapChainForComposition(dev, &sd, NULL, &s->chain);
    if (FAILED(hr) && factory) {
      sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
      hr = factory->CreateSwapChainForComposition(dev, &sd, NULL, &s->chain);
    }
    if (SUCCEEDED(hr)) hr = s->pic->SetContent(s->chain);
    if (factory) factory->Release();
    if (adapter) adapter->Release();
    if (xdev) xdev->Release();
    if (FAILED(hr)) {
      if (s->chain) s->chain->Release();
      s->chain = NULL;
      fprintf(stdout, "win: stream %d: no swap chain for its layer (%08lx)\n", s->id, (unsigned long)hr);
      fflush(stdout);
      return 0;
    }
  }
  s->chain_w = w;
  s->chain_h = h;
  layer_transform(s);
  // (its new size's stretch shown with the picture: now, or with the frame whose placing is under way)
  mb_render_commit_soon();
  return 1;
}

// The frame it shows now put on its layer and presented, composed by the system: nothing of the app's drawn.
static void layer_present(Stream *s) {
  StreamFrame *f = &s->cur;
  if (!s->pic || (!f->gpu.tex && !f->srv)) return;
  int w = f->gpu.tex ? f->gpu.w : f->w, h = f->gpu.tex ? f->gpu.h : f->h;
  if (w <= 0 || h <= 0 || !chain_ready(s, w, h)) return;
  ID3D11Texture2D *back = NULL;
  if (FAILED(s->chain->GetBuffer(0, IID_PPV_ARGS(&back)))) return;
  int put = 0;
  if (f->gpu.tex) {
    // (a view of the buffer drawn into now: the chain's buffers take turns)
    ID3D11VideoProcessorOutputView *view = NULL;
    put = vp_blt(s, &f->gpu, back, &view);
    if (view) view->Release();
  } else {
    ID3D11Resource *src = NULL;
    f->srv->GetResource(&src);
    if (src) {
      ((ID3D11DeviceContext *)mb_render_context())->CopyResource(back, src);
      src->Release();
      put = 1;
    }
  }
  back->Release();
  if (!put) return;
  HRESULT hr = s->chain->Present(0, 0);
  // (said once a size: what the layer shows, for the log)
  if (s->presented_w != w || s->presented_h != h || FAILED(hr)) {
    s->presented_w = w;
    s->presented_h = h;
    fprintf(stdout, "win: stream %d: on its layer %dx%d (%s, %08lx)\n", s->id, w, h, f->gpu.tex ? "the GPU's" : "a copy",
            (unsigned long)hr);
    fflush(stdout);
  }
}

// Its pointer's surface (made again as its picture changes) at its place over the picture, or none; committed
// (`commit`: now, unless a frame is placing the views) or with what commits next.
static void pointer_put(Stream *s, int commit) {
  if (!s->ptr) return;
  if (s->ptr_new) {
    s->ptr_new = 0;
    if (s->ptr_surface) s->ptr_surface->Release();
    s->ptr_surface = NULL;
    IDCompositionDevice *dc = (IDCompositionDevice *)mb_render_dcomp();
    if (dc && s->ptr_px &&
        SUCCEEDED(dc->CreateSurface((UINT)s->ptr_pw, (UINT)s->ptr_ph, DXGI_FORMAT_B8G8R8A8_UNORM,
                                    DXGI_ALPHA_MODE_PREMULTIPLIED, &s->ptr_surface))) {
      ID3D11Texture2D *t = NULL;
      POINT off = {};
      if (SUCCEEDED(s->ptr_surface->BeginDraw(NULL, IID_PPV_ARGS(&t), &off))) {
        D3D11_BOX box = {(UINT)off.x, (UINT)off.y, 0, (UINT)(off.x + s->ptr_pw), (UINT)(off.y + s->ptr_ph), 1};
        ((ID3D11DeviceContext *)mb_render_context())->UpdateSubresource(t, 0, &box, s->ptr_px, (UINT)s->ptr_pw * 4, 0);
        t->Release();
        s->ptr_surface->EndDraw();
      } else {
        s->ptr_surface->Release();
        s->ptr_surface = NULL;
      }
    }
  }
  int shown = s->ptr_surface && s->ptr_shown && s->place_w > 0 && s->place_h > 0;
  s->ptr->SetContent(shown ? s->ptr_surface : NULL);
  if (shown) {
    // its picture at its own size whatever its pixels, its hot spot where it points (in the view's rect)
    double k = s->place_scale > 0 ? s->place_scale : 1;
    D2D_MATRIX_3X2_F m = {};
    m._11 = (FLOAT)(s->ptr_w * k / s->ptr_pw);
    m._22 = (FLOAT)(s->ptr_h * k / s->ptr_ph);
    m._31 = (FLOAT)(s->ptr_x * s->place_w - s->ptr_hx * k);
    m._32 = (FLOAT)(s->ptr_y * s->place_h - s->ptr_hy * k);
    s->ptr->SetTransform(m);
  }
  if (commit) mb_render_commit_soon();
}

// Its layer taken off its view's visual, and let go.
static void layer_drop(Stream *s) {
  InterlockedExchange(&s->layered, 0);
  if (s->content) {
    if (s->pic) s->content->RemoveVisual(s->pic);
    if (s->ptr) s->content->RemoveVisual(s->ptr);
    s->content->Release();
  }
  if (s->pic) s->pic->Release();
  if (s->ptr) s->ptr->Release();
  if (s->chain) s->chain->Release();
  if (s->ptr_surface) s->ptr_surface->Release();
  s->content = s->pic = s->ptr = NULL;
  s->chain = NULL;
  s->ptr_surface = NULL;
  s->chain_w = s->chain_h = 0;
  s->presented_w = s->presented_h = 0;
  s->ptr_new = s->ptr_px != NULL;
}

int mb_stream_layers_here(void) { return mb_render_dcomp() && video_here(); }

void mb_stream_attach(int sid, void *content) {
  Stream *s = stream_of(sid);
  if (!s || (IDCompositionVisual *)content == s->content) return;
  layer_drop(s);
  IDCompositionDevice *dc = (IDCompositionDevice *)mb_render_dcomp();
  if (!content || s->closed || !dc) {
    mb_render_commit_soon();
    return;
  }
  if (FAILED(dc->CreateVisual(&s->pic)) || FAILED(dc->CreateVisual(&s->ptr))) {
    if (s->pic) s->pic->Release();
    s->pic = NULL;
    s->ptr = NULL;
    return;
  }
  s->content = (IDCompositionVisual *)content;
  s->content->AddRef();
  // the picture, its pointer over it
  s->content->AddVisual(s->pic, FALSE, NULL);
  s->content->AddVisual(s->ptr, TRUE, s->pic);
  InterlockedExchange(&s->layered, 1);
  // (what it shows already, at once: not black until the next frame)
  layer_present(s);
  pointer_put(s, 0);
  mb_render_commit_soon();
}

void mb_stream_placed(int sid, double w, double h, double scale) {
  Stream *s = stream_of(sid);
  if (!s) return;
  s->place_w = w;
  s->place_h = h;
  s->place_scale = scale;
  layer_transform(s);
  pointer_put(s, 0);
}

extern "C" {

int32_t mb_host_stream_open(void) {
  setup();
  // (the GPU's video side looked for here, on the UI thread, before any decoder's thread reads it)
  video_here();
  AcquireSRWLockExclusive(&streams_lock);
  if (nstreams == 0) nstreams = 1;  // 0 is none
  if (nstreams >= cap_streams) {
    cap_streams = cap_streams ? cap_streams * 2 : 16;
    streams = (Stream **)realloc(streams, (size_t)cap_streams * sizeof *streams);
  }
  Stream *s = (Stream *)calloc(1, sizeof(Stream));
  s->id = nstreams;
  s->direct_at = s->direct_told_at = -1;
  streams[nstreams] = s;
  int id = nstreams++;
  ReleaseSRWLockExclusive(&streams_lock);
  return id;
}

}  // extern "C"

// a piece of the stream's work queued, its bytes copied; the pool's thread started for it where none works on it
static void queue_bytes(Stream *s, StreamJob j, const uint8_t *data, size_t len) {
  j.data = (uint8_t *)malloc(len ? len : 1);
  j.len = len;
  memcpy(j.data, data, len);
  EnterCriticalSection(&lock);
  if (s->closed) {
    LeaveCriticalSection(&lock);
    free(j.data);
    return;
  }
  if (s->njobs >= s->cap_jobs) {
    s->cap_jobs = s->cap_jobs ? s->cap_jobs * 2 : 8;
    s->jobs = (StreamJob *)realloc(s->jobs, (size_t)s->cap_jobs * sizeof *s->jobs);
  }
  s->jobs[s->njobs++] = j;
  int start = !s->busy;
  s->busy = 1;
  LeaveCriticalSection(&lock);
  if (start && !TrySubmitThreadpoolCallback(work, s, NULL)) {
    EnterCriticalSection(&lock);
    s->busy = 0;
    s->njobs--;
    LeaveCriticalSection(&lock);
    free(j.data);
    if (j.kind != JOB_CONFIG) let_go(s, j.ts, j.route);
  }
}

static void queue_job(Stream *s, StreamJob j, moonbit_bytes_t data) {
  queue_bytes(s, j, data, (size_t)Moonbit_array_length(data));
}

extern "C" {

void mb_host_stream_h264(int32_t id, moonbit_bytes_t avcc, int32_t w, int32_t h) {
  Stream *s = stream_of(id);
  if (!s) return;
  // (the frames after it the app's to show, whatever their times)
  s->direct_at = -1;
  queue_job(s, {JOB_CONFIG, 0, NULL, 0, 0, w, h, 0, 0}, avcc);
}

void mb_host_stream_hevc(int32_t id, moonbit_bytes_t hvcc, int32_t w, int32_t h) {
  Stream *s = stream_of(id);
  if (!s) return;
  s->direct_at = -1;
  queue_job(s, {JOB_CONFIG, 0, NULL, 0, 0, w, h, 1, 0}, hvcc);
}

void mb_host_stream_frame(int32_t id, moonbit_bytes_t data, int32_t key, double ts) {
  Stream *s = stream_of(id);
  if (s) queue_job(s, {JOB_FRAME, ts, NULL, 0, key != 0, 0, 0, 0, 0}, data);
}

void mb_host_stream_jpeg(int32_t id, moonbit_bytes_t data, double ts) {
  Stream *s = stream_of(id);
  if (s) queue_job(s, {JOB_JPEG, ts, NULL, 0, 0, 0, 0, 0, 0}, data);
}

moonbit_string_t mb_host_stream_next(int32_t id) {
  Stream *s = stream_of(id);
  char *e = NULL;
  if (s) {
    long frames = 0, bytes = 0;
    EnterCriticalSection(&lock);
    if (s->nevents > 0) {
      e = s->events[0];
      memmove(s->events, s->events + 1, (size_t)(s->nevents - 1) * sizeof *s->events);
      s->nevents--;
    }
    frames = s->direct_frames;
    bytes = s->direct_bytes;
    LeaveCriticalSection(&lock);
    // what came by its route since it was last told, after all else it said
    if (!e && (s->direct_at != s->direct_told_at || frames != s->direct_told_frames)) {
      char t[40];
      num(t, sizeof t, s->direct_at);
      e = (char *)malloc(96);
      snprintf(e, 96, "D %s %ld %ld", t, frames - s->direct_told_frames, bytes - s->direct_told_bytes);
      s->direct_told_at = s->direct_at;
      s->direct_told_frames = frames;
      s->direct_told_bytes = bytes;
    }
  }
  int n = e ? (int)strlen(e) : 0;
  moonbit_string_t out = moonbit_make_string_raw(n);
  for (int i = 0; i < n; i++) out[i] = (uint16_t)(unsigned char)e[i];
  free(e);
  return out;
}

void mb_host_stream_show(int32_t id, double ts) {
  Stream *s = stream_of(id);
  if (!s) return;
  StreamFrame f = {};
  int found = 0;
  EnterCriticalSection(&lock);
  if (ts < s->direct_at) {
    // (older than a frame of its route shown since: passed over)
    int k = 0;
    for (int i = 0; i < s->ndecoded; i++) {
      if (s->decoded[i].ts > ts) s->decoded[k++] = s->decoded[i];
      else frame_free(s, &s->decoded[i]);
    }
    s->ndecoded = k;
    LeaveCriticalSection(&lock);
    return;
  }
  int at = -1;
  for (int i = 0; i < s->ndecoded; i++) {
    if (s->decoded[i].ts == ts) at = i;
  }
  if (at >= 0) {
    f = s->decoded[at];
    found = 1;
    // it, and those decoded before it passed over (their textures kept to be decoded into again: the same lock, taken
    // again)
    int k = 0;
    for (int i = 0; i < s->ndecoded; i++) {
      if (s->decoded[i].ts > ts) s->decoded[k++] = s->decoded[i];
      else if (i != at) frame_free(s, &s->decoded[i]);
    }
    s->ndecoded = k;
  }
  LeaveCriticalSection(&lock);
  if (!found) return;
  frame_free(s, &s->cur);
  s->cur = f;
  s->drawn = 0;
  // on its system video layer (if it has one) as well: what shows there
  layer_present(s);
}

// ---- a stream's sound (XAudio2) ----

#define SOUND_PACKET 3840  // 20 ms: 960 frames of 48 kHz stereo PCM16
#define SOUND_FRAMES 960
#define SOUND_RING 32      // packets' memory: the 15 queued at most, the one playing, and room

static SRWLOCK sound_lock = SRWLOCK_INIT;
static IXAudio2 *sound_engine;
static IXAudio2MasteringVoice *sound_master;
static int sound_state;  // 0 not tried, 1 here, -1 none (no audio device, XAudio2 refused)

// (under sound_lock) the engine and its output, made once
static int sound_ready(void) {
  if (sound_state) return sound_state > 0;
  sound_state = -1;
  if (FAILED(XAudio2Create(&sound_engine, 0, XAUDIO2_DEFAULT_PROCESSOR))) {
    fprintf(stderr, "win: streams: no sound (XAudio2)\n");
    return 0;
  }
  if (FAILED(sound_engine->CreateMasteringVoice(&sound_master))) {
    fprintf(stderr, "win: streams: no sound (no output device)\n");
    sound_engine->Release();
    sound_engine = NULL;
    return 0;
  }
  sound_state = 1;
  return 1;
}

// (under sound_lock) its voice let go, what is queued with it
static void sound_stop(Stream *s) {
  if (s->voice) s->voice->DestroyVoice();
  s->voice = NULL;
  s->sound_playing = 0;
}

// (under sound_lock) one 20 ms packet played after those queued
static void sound_play(Stream *s, const uint8_t *bytes) {
  if (!sound_ready()) return;
  if (!s->voice) {
    WAVEFORMATEX f = {};
    f.wFormatTag = WAVE_FORMAT_PCM;
    f.nChannels = 2;
    f.nSamplesPerSec = 48000;
    f.wBitsPerSample = 16;
    f.nBlockAlign = 4;
    f.nAvgBytesPerSec = 48000 * 4;
    if (FAILED(sound_engine->CreateSourceVoice(&s->voice, &f))) {
      s->voice = NULL;
      return;
    }
    if (!s->sound_ring) s->sound_ring = (uint8_t *)malloc((size_t)SOUND_RING * SOUND_PACKET);
    s->sound_playing = 0;
  }
  XAUDIO2_VOICE_STATE st;
  s->voice->GetState(&st, XAUDIO2_VOICE_NOSAMPLESPLAYED);
  // past 300 ms queued (a stall), or run dry while playing: emptied, the reserve filled again first
  if (st.BuffersQueued >= 15 || (s->sound_playing && st.BuffersQueued == 0)) {
    s->voice->Stop();
    s->voice->FlushSourceBuffers();
    s->sound_playing = 0;
    st.BuffersQueued = 0;
  }
  uint8_t *slot = s->sound_ring + (size_t)(s->sound_next++ % SOUND_RING) * SOUND_PACKET;
  memcpy(slot, bytes, SOUND_PACKET);
  XAUDIO2_BUFFER b = {};
  b.AudioBytes = SOUND_PACKET;
  b.pAudioData = slot;
  if (FAILED(s->voice->SubmitSourceBuffer(&b))) return;
  // started once 60 ms are queued
  if (!s->sound_playing && st.BuffersQueued + 1 >= 3 && SUCCEEDED(s->voice->Start())) s->sound_playing = 1;
}

// (any thread) stream s's packet played, or (empty) its sound stopped
static void sound_take(Stream *s, const uint8_t *bytes, size_t len) {
  AcquireSRWLockExclusive(&sound_lock);
  if (s->sound_gone || len == 0) sound_stop(s);
  else if (len == SOUND_PACKET) sound_play(s, bytes);
  ReleaseSRWLockExclusive(&sound_lock);
}

void mb_host_stream_close(int32_t id) {
  Stream *s = stream_of(id);
  if (!s) return;
  unroute(id, 3);
  AcquireSRWLockExclusive(&sound_lock);
  s->sound_gone = 1;
  sound_stop(s);
  ReleaseSRWLockExclusive(&sound_lock);
  layer_drop(s);
  if (s->ptr_px) free(s->ptr_px);
  s->ptr_px = NULL;
  s->ptr_new = 0;
  EnterCriticalSection(&lock);
  s->closed = 1;
  for (int i = 0; i < s->nevents; i++) free(s->events[i]);
  s->nevents = 0;
  StreamFrame *left = s->decoded;
  int nleft = s->ndecoded;
  s->decoded = NULL;
  s->ndecoded = s->cap_decoded = 0;
  for (int i = 0; i < s->njobs; i++) free(s->jobs[i].data);
  s->njobs = 0;
  Gpu pool[POOL];
  int npool = s->npool;
  memcpy(pool, s->pool, sizeof pool);
  s->npool = 0;
  int idle = !s->busy;
  LeaveCriticalSection(&lock);
  for (int i = 0; i < nleft; i++) frame_free(s, &left[i]);
  free(left);
  for (int i = 0; i < npool; i++) gpu_drop(&pool[i]);
  // (its decoder: here where no work goes on, else as that work ends)
  if (idle) h264_free(s);
  frame_free(s, &s->cur);
  if (s->bgra_out) s->bgra_out->Release();
  if (s->bgra_srv) s->bgra_srv->Release();
  if (s->bgra) s->bgra->Release();
  if (s->vp) s->vp->Release();
  if (s->vpe) s->vpe->Release();
  s->bgra_out = NULL;
  s->bgra_srv = NULL;
  s->bgra = NULL;
  s->vp = NULL;
  s->vpe = NULL;
  mb_render_commit_soon();
  // (the stream itself kept: a decode under way still holds it; it does nothing more)
}

int32_t mb_host_h264_here(void) { return h264_decoder_here(); }

// (the decoder the host's own, nothing for the framework to drive: @hostapi.stream_feeds)
int32_t mb_host_stream_feeds(void) { return 0; }
void mb_host_stream_codec(int32_t id, moonbit_string_t cmd, moonbit_bytes_t data) {}

// What the app's renderer draws stream id with: a frame's own BGRA texture, or the GPU's frame made BGRA by the
// video processor into a texture of the stream's (once for each frame drawn); NULL before a frame shows.
void *mb_stream_srv(int id) {
  Stream *s = stream_of(id);
  if (!s) return NULL;
  if (s->cur.srv || !s->cur.gpu.tex) return s->cur.srv;
  if (s->drawn && s->drawn_ts == s->cur.ts) return s->bgra_srv;
  Gpu *g = &s->cur.gpu;
  if (!s->bgra || s->bgra_w != g->w || s->bgra_h != g->h) {
    if (s->bgra_out) s->bgra_out->Release();
    if (s->bgra_srv) s->bgra_srv->Release();
    if (s->bgra) s->bgra->Release();
    s->bgra_out = NULL;
    s->bgra_srv = NULL;
    s->bgra = NULL;
    D3D11_TEXTURE2D_DESC td = {};
    td.Width = (UINT)g->w;
    td.Height = (UINT)g->h;
    td.MipLevels = td.ArraySize = 1;
    td.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    td.SampleDesc.Count = 1;
    td.Usage = D3D11_USAGE_DEFAULT;
    td.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    ID3D11Device *dev = (ID3D11Device *)mb_render_device();
    if (FAILED(dev->CreateTexture2D(&td, NULL, &s->bgra)) || FAILED(dev->CreateShaderResourceView(s->bgra, NULL, &s->bgra_srv))) {
      if (s->bgra) s->bgra->Release();
      s->bgra = NULL;
      s->bgra_srv = NULL;
      return NULL;
    }
    s->bgra_w = g->w;
    s->bgra_h = g->h;
  }
  if (!vp_blt(s, g, s->bgra, &s->bgra_out)) return NULL;
  s->drawn = 1;
  s->drawn_ts = s->cur.ts;
  return s->bgra_srv;
}

// Sound plays here unless a run says not to (MBUI_STREAM_AUDIO=0, to compare).
int32_t mb_host_stream_audio_here(void) {
  const char *v = getenv("MBUI_STREAM_AUDIO");
  return v && strcmp(v, "0") == 0 ? 0 : 1;
}

void mb_host_stream_audio(int32_t id, moonbit_bytes_t data) {
  Stream *s = stream_of(id);
  if (!s || s->closed) return;
  size_t len = (size_t)Moonbit_array_length(data);
  // (stopped: what its route plays stops with it, until the app routes it again)
  if (len == 0) unroute(id, 2);
  sound_take(s, (const uint8_t *)data, len);
}

// The app's (the window's thread): stream id takes route's frames (`what` 1) and sound (2) from now, where the last
// record offered by it is the `after`th (nothing of it left in the app's queue); those not asked no longer.
void mb_host_stream_direct(int32_t id, double route, double after, int32_t what) {
  unroute(id, ~what & 3);
  if (!(what & 3) || route < 1) return;
  AcquireSRWLockExclusive(&routes_lock);
  Route *r = route_at((uint64_t)route, 0);
  if (r && (double)r->seq == after) {
    if (what & 1) r->video = id;
    if (what & 2) r->audio = id;
  }
  ReleaseSRWLockExclusive(&routes_lock);
}

// A stream's record from the app's engine (its shell's thread, a route's in order): record `kind` of route `route` (2 a
// video frame; 1 its config, which stops the route until the app has taken it; 5, 6 sound's, the app's), the `seq`th
// of all offered: 1 when taken (fed to the stream the app routed it to), 0 when the app's to take.
int mb_stream_route_take(uint64_t route, int kind, int key, uint64_t seq, uint64_t ts, const uint8_t *bytes, size_t len) {
  int32_t sid = 0;
  AcquireSRWLockExclusive(&routes_lock);
  Route *r = route_at(route, 1);
  if (r) {
    r->seq = seq;
    if (kind == 1) r->video = 0;
    else if (kind == 5) r->audio = 0;
    else if (kind == 2) sid = r->video;
    else if (kind == 6 && len == SOUND_PACKET) sid = r->audio;
  }
  ReleaseSRWLockExclusive(&routes_lock);
  if (!sid) return 0;
  AcquireSRWLockShared(&streams_lock);
  Stream *s = stream_of(sid);
  ReleaseSRWLockShared(&streams_lock);
  if (!s || s->closed) return 0;
  if (kind == 6) {
    sound_take(s, bytes, len);
    return 1;
  }
  EnterCriticalSection(&lock);
  s->direct_frames += 1;
  s->direct_bytes += (long)len;
  LeaveCriticalSection(&lock);
  StreamJob j = {JOB_FRAME, (double)ts, NULL, 0, key != 0, 0, 0, 0, route};
  queue_bytes(s, j, bytes, len);
  return 1;
}

void mb_stream_route_acks(int (*ack)(double route, double ts)) { route_ack = ack; }

// A system video layer here (win_views.cpp's views of kind 4, where there is a composition and a video device): what a
// stream shows put there by the GPU, nothing drawn of it; shown as sRGB (2: its tagged colours not honoured, so none
// wider asked for).
int32_t mb_host_stream_layers(void) { return mb_stream_layers_here() ? 2 : 0; }

// Its pointer over its picture on its layer: its picture decoded (premultiplied BGRA), its size and hot spot (points).
void mb_host_stream_pointer(int32_t id, moonbit_bytes_t png, double w, double h, double hx, double hy) {
  Stream *s = stream_of(id);
  if (!s || s->closed) return;
  free(s->ptr_px);
  s->ptr_px = NULL;
  size_t n = (size_t)Moonbit_array_length(png);
  int pw = 0, ph = 0;
  if (n > 0) s->ptr_px = bgra_of_image((const uint8_t *)png, n, &pw, &ph);
  s->ptr_pw = pw;
  s->ptr_ph = ph;
  s->ptr_w = w;
  s->ptr_h = h;
  s->ptr_hx = hx;
  s->ptr_hy = hy;
  s->ptr_new = 1;
  pointer_put(s, 1);
}

void mb_host_stream_pointer_at(int32_t id, double x, double y, int32_t shown) {
  Stream *s = stream_of(id);
  if (!s || s->closed) return;
  s->ptr_x = x;
  s->ptr_y = y;
  s->ptr_shown = shown != 0;
  pointer_put(s, 1);
}

// H.265 where the GPU decodes it through the system's decoder (h265_decoder_here): the station asked for it first.
int32_t mb_host_h265_here(void) { return h265_decoder_here(); }

}  // extern "C"
