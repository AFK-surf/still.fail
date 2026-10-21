// Streams on Windows (src/host/stream.mbt, @ui's Stream): JPEG frames decoded by WIC on the thread pool, a stream's
// one after another in the order they came, each into a Direct3D 11 texture kept until the app shows it ("f TS W H",
// then mb_host_stream_show: what the renderer draws the stream's instances with, win_render.cpp) or a later one; one
// that does not decode is let go ("d TS"). No H.264 here (h264_here is false: the sender is asked for JPEG only); an
// H.264 frame handed over anyway is let go. Each event asks for a frame (mb_app_wake).
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <d3d11.h>
#include <wincodec.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "win.h"

#pragma comment(lib, "windowscodecs.lib")
#pragma comment(lib, "ole32.lib")

struct StreamFrame {
  double ts;
  int w, h;
  ID3D11ShaderResourceView *srv;
};

struct StreamJob {
  double ts;
  uint8_t *data;
  size_t len;
};

struct Stream {
  int id;
  int closed;
  // what it says, oldest first; frames decoded, not shown yet; JPEGs waiting; whether one is being decoded (all under
  // lock); what it is drawn with now (the UI thread's)
  char **events;
  int nevents, cap_events;
  StreamFrame *decoded;
  int ndecoded, cap_decoded;
  StreamJob *jobs;
  int njobs, cap_jobs;
  int busy;
  ID3D11ShaderResourceView *srv;
};

static Stream **streams;  // by id (ids are not reused)
static int nstreams, cap_streams;
static CRITICAL_SECTION lock;
static int ready;

static void setup(void) {
  if (ready) return;
  ready = 1;
  InitializeCriticalSection(&lock);
}

static Stream *stream_of(int id) { return id > 0 && id < nstreams ? streams[id] : NULL; }

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

static void say_dropped(Stream *s, double ts) {
  char t[40], e[48];
  num(t, sizeof t, ts);
  snprintf(e, sizeof e, "d %s", t);
  EnterCriticalSection(&lock);
  say_locked(s, e);
  LeaveCriticalSection(&lock);
  mb_app_wake();
}

// A JPEG's pixels as premultiplied BGRA in a texture: its view, NULL when it does not decode.
static ID3D11ShaderResourceView *decode_jpeg(const uint8_t *data, size_t len, int *w, int *h) {
  IWICImagingFactory *wic = NULL;
  IWICStream *stream = NULL;
  IWICBitmapDecoder *dec = NULL;
  IWICBitmapFrameDecode *frame = NULL;
  IWICFormatConverter *conv = NULL;
  ID3D11Texture2D *tex = NULL;
  ID3D11ShaderResourceView *srv = NULL;
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
    if (!px || FAILED(conv->CopyPixels(NULL, stride, stride * sh, px))) goto done;
    D3D11_TEXTURE2D_DESC td = {};
    td.Width = sw;
    td.Height = sh;
    td.MipLevels = td.ArraySize = 1;
    td.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    td.SampleDesc.Count = 1;
    td.Usage = D3D11_USAGE_IMMUTABLE;
    td.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    D3D11_SUBRESOURCE_DATA init = {px, stride, 0};
    ID3D11Device *dev = (ID3D11Device *)mb_render_device();
    if (FAILED(dev->CreateTexture2D(&td, &init, &tex)) || FAILED(dev->CreateShaderResourceView(tex, NULL, &srv)))
      srv = NULL;
    *w = (int)sw;
    *h = (int)sh;
  }
done:
  free(px);
  if (tex) tex->Release();
  if (conv) conv->Release();
  if (frame) frame->Release();
  if (dec) dec->Release();
  if (stream) stream->Release();
  if (wic) wic->Release();
  return srv;
}

// A stream's JPEGs decoded one after another, until none waits (a thread of the pool).
static void CALLBACK work(PTP_CALLBACK_INSTANCE inst, void *arg) {
  Stream *s = (Stream *)arg;
  CoInitializeEx(NULL, COINIT_MULTITHREADED);
  for (;;) {
    EnterCriticalSection(&lock);
    if (s->njobs == 0 || s->closed) {
      s->busy = 0;
      LeaveCriticalSection(&lock);
      break;
    }
    StreamJob j = s->jobs[0];
    memmove(s->jobs, s->jobs + 1, (size_t)(s->njobs - 1) * sizeof *s->jobs);
    s->njobs--;
    LeaveCriticalSection(&lock);
    int w = 0, h = 0;
    ID3D11ShaderResourceView *srv = decode_jpeg(j.data, j.len, &w, &h);
    free(j.data);
    char t[40], e[96];
    num(t, sizeof t, j.ts);
    EnterCriticalSection(&lock);
    if (srv && !s->closed) {
      if (s->ndecoded >= s->cap_decoded) {
        s->cap_decoded = s->cap_decoded ? s->cap_decoded * 2 : 8;
        s->decoded = (StreamFrame *)realloc(s->decoded, (size_t)s->cap_decoded * sizeof *s->decoded);
      }
      s->decoded[s->ndecoded++] = {j.ts, w, h, srv};
      snprintf(e, sizeof e, "f %s %d %d", t, w, h);
      srv = NULL;
    } else {
      snprintf(e, sizeof e, "d %s", t);
    }
    say_locked(s, e);
    LeaveCriticalSection(&lock);
    if (srv) srv->Release();
    mb_app_wake();
  }
  CoUninitialize();
}

extern "C" {

int32_t mb_host_stream_open(void) {
  setup();
  if (nstreams == 0) nstreams = 1;  // 0 is none
  if (nstreams >= cap_streams) {
    cap_streams = cap_streams ? cap_streams * 2 : 16;
    streams = (Stream **)realloc(streams, (size_t)cap_streams * sizeof *streams);
  }
  Stream *s = (Stream *)calloc(1, sizeof(Stream));
  s->id = nstreams;
  streams[nstreams] = s;
  return nstreams++;
}

void mb_host_stream_h264(int32_t id, moonbit_bytes_t avcc, int32_t w, int32_t h) {
  (void)id; (void)avcc; (void)w; (void)h;
}

void mb_host_stream_frame(int32_t id, moonbit_bytes_t data, int32_t key, double ts) {
  (void)data; (void)key;
  Stream *s = stream_of(id);
  if (s) say_dropped(s, ts);
}

void mb_host_stream_jpeg(int32_t id, moonbit_bytes_t data, double ts) {
  Stream *s = stream_of(id);
  if (!s) return;
  size_t len = (size_t)Moonbit_array_length(data);
  StreamJob j = {ts, (uint8_t *)malloc(len ? len : 1), len};
  memcpy(j.data, data, len);
  EnterCriticalSection(&lock);
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
    say_dropped(s, ts);
  }
}

moonbit_string_t mb_host_stream_next(int32_t id) {
  Stream *s = stream_of(id);
  char *e = NULL;
  if (s) {
    EnterCriticalSection(&lock);
    if (s->nevents > 0) {
      e = s->events[0];
      memmove(s->events, s->events + 1, (size_t)(s->nevents - 1) * sizeof *s->events);
      s->nevents--;
    }
    LeaveCriticalSection(&lock);
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
  ID3D11ShaderResourceView *srv = NULL;
  EnterCriticalSection(&lock);
  int at = -1;
  for (int i = 0; i < s->ndecoded; i++) {
    if (s->decoded[i].ts == ts) at = i;
  }
  if (at >= 0) {
    srv = s->decoded[at].srv;
    // it, and those decoded before it passed over
    int k = 0;
    for (int i = 0; i < s->ndecoded; i++) {
      if (s->decoded[i].ts > ts) s->decoded[k++] = s->decoded[i];
      else if (i != at) s->decoded[i].srv->Release();
    }
    s->ndecoded = k;
  }
  LeaveCriticalSection(&lock);
  if (!srv) return;
  if (s->srv) s->srv->Release();
  s->srv = srv;
}

void mb_host_stream_close(int32_t id) {
  Stream *s = stream_of(id);
  if (!s) return;
  EnterCriticalSection(&lock);
  s->closed = 1;
  for (int i = 0; i < s->nevents; i++) free(s->events[i]);
  s->nevents = 0;
  for (int i = 0; i < s->ndecoded; i++) s->decoded[i].srv->Release();
  s->ndecoded = 0;
  for (int i = 0; i < s->njobs; i++) free(s->jobs[i].data);
  s->njobs = 0;
  LeaveCriticalSection(&lock);
  if (s->srv) s->srv->Release();
  s->srv = NULL;
  // (the stream itself kept: a decode under way still holds it; it does nothing more)
}

int32_t mb_host_h264_here(void) { return 0; }

void *mb_stream_srv(int id) {
  Stream *s = stream_of(id);
  return s ? s->srv : NULL;
}

}  // extern "C"
