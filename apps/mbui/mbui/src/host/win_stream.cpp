// Streams on Windows (src/hostapi/stream.mbt, @ui's Stream): a stream's work on the thread pool, one piece after another
// in the order it came: JPEG frames decoded by WIC; H.264 by the system's decoder (Media Foundation's, in software:
// its config an avcC, its access units in AVCC, each made Annex B for it, a key frame after its SPS and PPS), low
// latency (a frame out as it goes in), its NV12 made BGRA as its colours say (BT.709 or BT.601, video or full range).
// Each frame into a Direct3D 11 texture kept until the app shows it ("f TS W H", then mb_host_stream_show: what the
// renderer draws the stream's instances with, win_render.cpp) or a later one; one that does not decode, or that the
// decoder passed over, is let go ("d TS"); the decoder failing says "b" and starts anew from the next key frame. Each
// event asks for a frame (mb_app_wake).
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <d3d11.h>
#include <wincodec.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mftransform.h>
#include <mferror.h>
#include <wmcodecdsp.h>
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

struct StreamFrame {
  double ts;
  int w, h;
  ID3D11ShaderResourceView *srv;
};

// A piece of a stream's work: a JPEG frame, an H.264 config (its avcC, the picture's size) or access unit
enum { JOB_JPEG, JOB_CONFIG, JOB_FRAME };
struct StreamJob {
  int kind;
  double ts;
  uint8_t *data;
  size_t len;
  int key, w, h;
};

// What was fed the H.264 decoder and is not out of it yet: its sample time there (a count) and its time
struct Fed {
  LONGLONG n;
  double ts;
};

// A stream's H.264 decoder (its config's, started anew with each and as it fails; the stream's work's alone): the
// system's; the avcC's SPS and PPS in Annex B, put before each key frame; its NAL lengths' size; whether it waits for a
// key frame; the next frame's count; what was fed it, oldest first; the config's size; the picture it gives (NV12: its
// size as shown, its rows' count, its colours: BT.709, video range unless it says)
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
  H264 *h264;
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

// A JPEG's pixels as premultiplied BGRA in a texture: its view, NULL when it does not decode.
static ID3D11ShaderResourceView *decode_jpeg(const uint8_t *data, size_t len, int *w, int *h) {
  IWICImagingFactory *wic = NULL;
  IWICStream *stream = NULL;
  IWICBitmapDecoder *dec = NULL;
  IWICBitmapFrameDecode *frame = NULL;
  IWICFormatConverter *conv = NULL;
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
    srv = texture_of(px, sw, sh);
    *w = (int)sw;
    *h = (int)sh;
  }
done:
  free(px);
  if (conv) conv->Release();
  if (frame) frame->Release();
  if (dec) dec->Release();
  if (stream) stream->Release();
  if (wic) wic->Release();
  return srv;
}

// ---- H.264 (the stream's work's alone: on the pool, one piece at a time) ----

static int mf_started;

static void say(Stream *s, const char *e) {
  EnterCriticalSection(&lock);
  say_locked(s, e);
  LeaveCriticalSection(&lock);
  mb_app_wake();
}

// what was fed the decoder and is not out of it, let go: "d" of the last's time
static void fed_dropped(Stream *s) {
  H264 *d = s->h264;
  if (!d || !d->nfed) return;
  double last = d->fed[d->nfed - 1].ts;
  d->nfed = 0;
  say_dropped(s, last);
}

static void h264_stop(H264 *d) {
  if (d->dec) d->dec->Release();
  d->dec = NULL;
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
      uint8_t *p = d->head + d->nhead;
      p[0] = p[1] = p[2] = 0, p[3] = 1;
      memcpy(p + 4, a + at, len);
      d->nhead += 4 + len;
      at += len;
    }
  }
  return d->nhead > 0;
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

// the decoder for the config's picture, w × h, from the next key frame: 1 started
static int h264_start(Stream *s, UINT32 w, UINT32 h) {
  H264 *d = s->h264;
  d->need_key = 1;
  d->cw = w, d->ch = h;
  d->w = w, d->h = h, d->rows = h;
  if (!mf_started) {
    if (FAILED(MFStartup(MF_VERSION, MFSTARTUP_LITE))) return 0;
    mf_started = 1;
  }
  IMFMediaType *in = NULL;
  IMFAttributes *at = NULL;
  HRESULT hr = CoCreateInstance(CLSID_CMSH264DecoderMFT, NULL, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&d->dec));
  // (a frame out as it goes in, none held back for the order of frames a screen's never has)
  if (SUCCEEDED(hr) && SUCCEEDED(d->dec->GetAttributes(&at))) at->SetUINT32(MF_LOW_LATENCY, TRUE), at->Release();
  if (SUCCEEDED(hr)) hr = MFCreateMediaType(&in);
  if (SUCCEEDED(hr)) hr = in->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  if (SUCCEEDED(hr)) hr = in->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
  if (SUCCEEDED(hr)) hr = MFSetAttributeSize(in, MF_MT_FRAME_SIZE, w, h);
  if (SUCCEEDED(hr)) hr = in->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  if (SUCCEEDED(hr)) hr = d->dec->SetInputType(0, in, 0);
  if (in) in->Release();
  if (SUCCEEDED(hr) && !h264_output(d)) hr = E_FAIL;
  if (SUCCEEDED(hr)) hr = d->dec->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
  if (SUCCEEDED(hr)) hr = d->dec->ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);
  if (FAILED(hr)) {
    fprintf(stdout, "win: stream %d: no H.264 decoder (%08lx)\n", s->id, (unsigned long)hr);
    fflush(stdout);
    h264_stop(d);
    return 0;
  }
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
    double ts = -1, passed = -1;
    int k = 0;
    while (k < d->nfed && d->fed[k].n <= n) {
      if (d->fed[k].n == n) ts = d->fed[k].ts;
      else passed = d->fed[k].ts;
      k++;
    }
    memmove(d->fed, d->fed + k, (size_t)(d->nfed - k) * sizeof *d->fed);
    d->nfed -= k;
    if (passed >= 0) say_dropped(s, passed);
    ID3D11ShaderResourceView *srv = NULL;
    IMFMediaBuffer *cb = NULL;
    BYTE *px = NULL;
    DWORD len = 0;
    if (ts >= 0 && SUCCEEDED(o.pSample->ConvertToContiguousBuffer(&cb)) && SUCCEEDED(cb->Lock(&px, NULL, &len))) {
      srv = bgra_of_nv12(d, px, len);
      cb->Unlock();
    }
    if (cb) cb->Release();
    o.pSample->Release();
    if (ts < 0) continue;
    char tt[40], e[96];
    num(tt, sizeof tt, ts);
    EnterCriticalSection(&lock);
    if (srv && !s->closed) {
      if (s->ndecoded >= s->cap_decoded) {
        s->cap_decoded = s->cap_decoded ? s->cap_decoded * 2 : 8;
        s->decoded = (StreamFrame *)realloc(s->decoded, (size_t)s->cap_decoded * sizeof *s->decoded);
      }
      s->decoded[s->ndecoded++] = {ts, (int)d->w, (int)d->h, srv};
      snprintf(e, sizeof e, "f %s %u %u", tt, d->w, d->h);
      srv = NULL;
    } else {
      snprintf(e, sizeof e, "d %s", tt);
    }
    say_locked(s, e);
    LeaveCriticalSection(&lock);
    if (srv) srv->Release();
    mb_app_wake();
  }
}

// a config: the decoder anew (what was in it let go), from the next key frame
static void h264_config(Stream *s, StreamJob *j) {
  if (!s->h264) s->h264 = (H264 *)calloc(1, sizeof(H264));
  H264 *d = s->h264;
  fed_dropped(s);
  h264_stop(d);
  if (!avcc_read(d, j->data, j->len)) {
    fprintf(stdout, "win: stream %d: its config is no avcC\n", s->id);
    fflush(stdout);
    return;
  }
  h264_start(s, (UINT32)j->w, (UINT32)j->h);
}

// an access unit: made Annex B (a key frame after the config's SPS and PPS), fed, and what comes of it said
static void h264_frame(Stream *s, StreamJob *j) {
  H264 *d = s->h264;
  if (!d || !d->dec || (d->need_key && !j->key)) return say_dropped(s, j->ts);
  d->need_key = 0;
  size_t cap = j->len * 3 + (j->key ? d->nhead : 0) + 16;
  IMFMediaBuffer *buf = NULL;
  IMFSample *smp = NULL;
  BYTE *p = NULL;
  if (FAILED(MFCreateMemoryBuffer((DWORD)cap, &buf)) || FAILED(buf->Lock(&p, NULL, NULL))) {
    if (buf) buf->Release();
    return say_dropped(s, j->ts);
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
    return say_dropped(s, j->ts);
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
  d->fed[d->nfed++] = {n, j->ts};
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

}  // extern "C"

// a piece of the stream's work queued, its bytes copied; the pool's thread started for it where none works on it
static void queue_job(Stream *s, StreamJob j, moonbit_bytes_t data) {
  size_t len = (size_t)Moonbit_array_length(data);
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
    if (j.kind != JOB_CONFIG) say_dropped(s, j.ts);
  }
}

extern "C" {

void mb_host_stream_h264(int32_t id, moonbit_bytes_t avcc, int32_t w, int32_t h) {
  Stream *s = stream_of(id);
  if (s) queue_job(s, {JOB_CONFIG, 0, NULL, 0, 0, w, h}, avcc);
}

void mb_host_stream_frame(int32_t id, moonbit_bytes_t data, int32_t key, double ts) {
  Stream *s = stream_of(id);
  if (s) queue_job(s, {JOB_FRAME, ts, NULL, 0, key != 0, 0, 0}, data);
}

void mb_host_stream_jpeg(int32_t id, moonbit_bytes_t data, double ts) {
  Stream *s = stream_of(id);
  if (s) queue_job(s, {JOB_JPEG, ts, NULL, 0, 0, 0, 0}, data);
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
  int idle = !s->busy;
  LeaveCriticalSection(&lock);
  // (its decoder: here where no work goes on, else as that work ends)
  if (idle) h264_free(s);
  if (s->srv) s->srv->Release();
  s->srv = NULL;
  // (the stream itself kept: a decode under way still holds it; it does nothing more)
}

int32_t mb_host_h264_here(void) { return h264_decoder_here(); }

// (the decoder the host's own, nothing for the framework to drive: @hostapi.stream_feeds)
int32_t mb_host_stream_feeds(void) { return 0; }
void mb_host_stream_codec(int32_t id, moonbit_string_t cmd, moonbit_bytes_t data) {}

void *mb_stream_srv(int id) {
  Stream *s = stream_of(id);
  return s ? s->srv : NULL;
}

}  // extern "C"
