// Images on Windows: WIC decodes on a small thread pool straight to the size
// asked for (a scaler over the frame, which the JPEG decoder serves by
// decoding at a reduced size), turned by the EXIF orientation, converted to
// premultiplied BGRA, into a Direct3D 11 texture made right there (device
// methods are free-threaded). http(s) goes through URLDownloadToCacheFile.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <d3d11.h>
#include <wincodec.h>
#include <urlmon.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "win.h"

#pragma comment(lib, "windowscodecs.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "urlmon.lib")

struct Image {
  int state;  // 0 decoding, 1 ready, -1 failed or freed
  int w, h, ow, oh;
  ID3D11ShaderResourceView *srv;
  int untold;  // decoded (or failed), not yet told to the app (mb_images_tell)
};

struct Job {
  int id, max_px;
  wchar_t *src;  // or
  uint8_t *data;
  size_t len;
};

// by id (ids are not reused); the UI thread grows it, workers fill entries in
static Image *imgs;
static int nimgs, img_cap;
// the ids of those finished and not told yet (mb_images_tell), under lock
static int *done_ids;
static int ndone, done_cap;
static CRITICAL_SECTION lock;
static PTP_POOL pool;
static TP_CALLBACK_ENVIRON pool_env;
static int log_times;

static void setup(void) {
  if (pool) return;
  InitializeCriticalSection(&lock);
  pool = CreateThreadpool(NULL);
  // a few at a time, so a grid scrolled fast doesn't keep every core busy
  // with pictures already off screen
  SetThreadpoolThreadMaximum(pool, 3);
  SetThreadpoolThreadMinimum(pool, 1);
  InitializeThreadpoolEnvironment(&pool_env);
  SetThreadpoolCallbackPool(&pool_env, pool);
  const char *b = getenv("MBUI_BENCH");
  log_times = b && atoi(b) != 0;
}

static void finish(int id, int state, int w, int h, int ow, int oh, ID3D11ShaderResourceView *srv) {
  EnterCriticalSection(&lock);
  Image *im = &imgs[id];
  if (im->state == 0) {
    *im = {state, w, h, ow, oh, srv, 1};
    srv = NULL;
    if (ndone >= done_cap) {
      done_cap = done_cap ? done_cap * 2 : 64;
      done_ids = (int *)realloc(done_ids, (size_t)done_cap * sizeof *done_ids);
    }
    done_ids[ndone++] = id;
  }
  LeaveCriticalSection(&lock);
  if (srv) srv->Release();  // freed meanwhile
  mb_app_wake();
}

static UINT16 orientation(IWICBitmapFrameDecode *frame) {
  IWICMetadataQueryReader *q = NULL;
  UINT16 o = 1;
  if (FAILED(frame->GetMetadataQueryReader(&q))) return 1;
  // the policy name covers JPEG, TIFF and HEIF; the path, JPEG without it
  const wchar_t *names[] = {L"System.Photo.Orientation", L"/app1/ifd/{ushort=274}"};
  for (const wchar_t *n : names) {
    PROPVARIANT v;
    PropVariantInit(&v);
    HRESULT hr = q->GetMetadataByName(n, &v);
    if (SUCCEEDED(hr) && v.vt == VT_UI2) o = v.uiVal;
    PropVariantClear(&v);
    if (SUCCEEDED(hr)) break;
  }
  q->Release();
  return o >= 1 && o <= 8 ? o : 1;
}

// EXIF orientation to what turns the stored picture upright (WIC flips
// before it rotates)
static WICBitmapTransformOptions upright(UINT16 o) {
  switch (o) {
    case 2: return WICBitmapTransformFlipHorizontal;
    case 3: return WICBitmapTransformRotate180;
    case 4: return WICBitmapTransformFlipVertical;
    case 5: return (WICBitmapTransformOptions)(WICBitmapTransformRotate270 | WICBitmapTransformFlipHorizontal);
    case 6: return WICBitmapTransformRotate90;
    case 7: return (WICBitmapTransformOptions)(WICBitmapTransformRotate90 | WICBitmapTransformFlipHorizontal);
    case 8: return WICBitmapTransformRotate270;
    default: return WICBitmapTransformRotate0;
  }
}

static ID3D11ShaderResourceView *decode(IWICImagingFactory *wic, IWICBitmapDecoder *dec, int max_px,
                                        int *w, int *h, int *ow, int *oh) {
  IWICBitmapFrameDecode *frame = NULL;
  IWICBitmapScaler *scaler = NULL;
  IWICFormatConverter *conv = NULL;
  IWICBitmapFlipRotator *turn = NULL;
  ID3D11Texture2D *tex = NULL;
  ID3D11ShaderResourceView *srv = NULL;
  uint8_t *px = NULL;
  UINT sw = 0, sh = 0;
  if (FAILED(dec->GetFrame(0, &frame)) || FAILED(frame->GetSize(&sw, &sh)) || !sw || !sh) goto done;
  {
    UINT16 o = orientation(frame);
    int turned = o >= 5;
    *ow = (int)(turned ? sh : sw);
    *oh = (int)(turned ? sw : sh);
    double k = fmin(1.0, max_px / (double)(sw > sh ? sw : sh));
    UINT tw = (UINT)lround(sw * k), th = (UINT)lround(sh * k);
    if (!tw) tw = 1;
    if (!th) th = 1;
    IWICBitmapSource *src = frame;
    if (k < 1) {
      if (FAILED(wic->CreateBitmapScaler(&scaler)) ||
          FAILED(scaler->Initialize(frame, tw, th, WICBitmapInterpolationModeFant)))
        goto done;
      src = scaler;
    }
    if (FAILED(wic->CreateFormatConverter(&conv)) ||
        FAILED(conv->Initialize(src, GUID_WICPixelFormat32bppPBGRA, WICBitmapDitherTypeNone, NULL, 0,
                                WICBitmapPaletteTypeCustom)))
      goto done;
    src = conv;
    if (o != 1) {
      if (FAILED(wic->CreateBitmapFlipRotator(&turn)) || FAILED(turn->Initialize(conv, upright(o))))
        goto done;
      src = turn;
    }
    UINT dw = 0, dh = 0;
    src->GetSize(&dw, &dh);
    UINT stride = dw * 4;
    px = (uint8_t *)malloc((size_t)stride * dh);
    if (!px || FAILED(src->CopyPixels(NULL, stride, stride * dh, px))) goto done;
    D3D11_TEXTURE2D_DESC td = {};
    td.Width = dw;
    td.Height = dh;
    td.MipLevels = td.ArraySize = 1;
    td.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    td.SampleDesc.Count = 1;
    td.Usage = D3D11_USAGE_IMMUTABLE;
    td.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    D3D11_SUBRESOURCE_DATA init = {px, stride, 0};
    ID3D11Device *dev = (ID3D11Device *)mb_render_device();
    if (FAILED(dev->CreateTexture2D(&td, &init, &tex)) ||
        FAILED(dev->CreateShaderResourceView(tex, NULL, &srv)))
      srv = NULL;
    *w = (int)dw;
    *h = (int)dh;
  }
done:
  free(px);
  if (tex) tex->Release();
  if (turn) turn->Release();
  if (conv) conv->Release();
  if (scaler) scaler->Release();
  if (frame) frame->Release();
  return srv;
}

static void CALLBACK work(PTP_CALLBACK_INSTANCE inst, void *arg) {
  Job *j = (Job *)arg;
  LARGE_INTEGER t0, t1, f;
  QueryPerformanceCounter(&t0);
  CoInitializeEx(NULL, COINIT_MULTITHREADED);
  IWICImagingFactory *wic = NULL;
  IWICStream *stream = NULL;
  IWICBitmapDecoder *dec = NULL;
  ID3D11ShaderResourceView *srv = NULL;
  int w = 0, h = 0, ow = 0, oh = 0;
  wchar_t cached[MAX_PATH];
  const wchar_t *path = j->src;
  if (path && (!wcsncmp(path, L"http://", 7) || !wcsncmp(path, L"https://", 8))) {
    path = SUCCEEDED(URLDownloadToCacheFileW(NULL, path, cached, MAX_PATH, 0, NULL)) ? cached : NULL;
  } else if (path && !wcsncmp(path, L"file://", 7)) {
    path += 7;
  }
  if (SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER,
                                 __uuidof(IWICImagingFactory), (void **)&wic))) {
    HRESULT hr = E_FAIL;
    if (j->data) {
      if (SUCCEEDED(wic->CreateStream(&stream)) &&
          SUCCEEDED(stream->InitializeFromMemory(j->data, (DWORD)j->len)))
        hr = wic->CreateDecoderFromStream(stream, NULL, WICDecodeMetadataCacheOnDemand, &dec);
    } else if (path) {
      hr = wic->CreateDecoderFromFilename(path, NULL, GENERIC_READ, WICDecodeMetadataCacheOnDemand, &dec);
    }
    if (SUCCEEDED(hr)) srv = decode(wic, dec, j->max_px, &w, &h, &ow, &oh);
  }
  if (dec) dec->Release();
  if (stream) stream->Release();
  if (wic) wic->Release();
  CoUninitialize();
  if (log_times) {
    QueryPerformanceCounter(&t1);
    QueryPerformanceFrequency(&f);
    fprintf(stdout, "image %dx%d -> %dx%d in %.1f ms: %ls\n", ow, oh, w, h,
            (t1.QuadPart - t0.QuadPart) * 1000.0 / f.QuadPart, j->src ? j->src : L"(bytes)");
    fflush(stdout);
  }
  finish(j->id, srv ? 1 : -1, w, h, ow, oh, srv);
  free(j->src);
  free(j->data);
  free(j);
}

static int start(Job *j) {
  setup();
  EnterCriticalSection(&lock);
  if (nimgs == 0) nimgs = 1;  // 0 is no image
  if (nimgs >= img_cap) {
    img_cap = img_cap ? img_cap * 2 : 256;
    imgs = (Image *)realloc(imgs, (size_t)img_cap * sizeof *imgs);
  }
  j->id = nimgs++;
  imgs[j->id] = {};
  LeaveCriticalSection(&lock);
  if (!TrySubmitThreadpoolCallback(work, j, &pool_env)) {
    finish(j->id, -1, 0, 0, 0, 0, NULL);
    int id = j->id;
    free(j->src);
    free(j->data);
    free(j);
    return id;
  }
  return j->id;
}

extern "C" {

int32_t mb_host_image_load(moonbit_string_t s, int32_t max_px) {
  int n = Moonbit_array_length(s);
  Job *j = (Job *)calloc(1, sizeof(Job));
  j->max_px = max_px;
  j->src = (wchar_t *)calloc((size_t)n + 1, sizeof(wchar_t));
  memcpy(j->src, s, (size_t)n * sizeof(wchar_t));
  return start(j);
}

int32_t mb_host_image_load_bytes(moonbit_bytes_t data, int32_t max_px) {
  Job *j = (Job *)calloc(1, sizeof(Job));
  j->max_px = max_px;
  j->len = Moonbit_array_length(data);
  j->data = (uint8_t *)malloc(j->len ? j->len : 1);
  memcpy(j->data, data, j->len);
  return start(j);
}

int32_t mb_host_image_info(int32_t id, double *out) {
  if (id <= 0 || id >= nimgs) return -1;
  EnterCriticalSection(&lock);
  Image im = imgs[id];
  LeaveCriticalSection(&lock);
  if (im.state == 1) {
    out[0] = im.w; out[1] = im.h; out[2] = im.ow; out[3] = im.oh;
  }
  return im.state;
}

void mb_host_image_free(int32_t id) {
  if (id <= 0 || id >= nimgs) return;
  EnterCriticalSection(&lock);
  ID3D11ShaderResourceView *srv = imgs[id].srv;
  imgs[id] = {-1};
  LeaveCriticalSection(&lock);
  if (srv) srv->Release();
}

void mb_images_tell(mb_outside_fn f) {
  if (!pool) return;  // no image asked for yet
  for (;;) {
    int id = 0, state = 0;
    EnterCriticalSection(&lock);
    while (ndone > 0 && !id) {
      int i = done_ids[--ndone];
      if (imgs[i].untold) {  // not freed meanwhile
        imgs[i].untold = 0;
        id = i;
        state = imgs[i].state;
      }
    }
    LeaveCriticalSection(&lock);
    if (!id) return;
    if (f) f(MB_OUTSIDE_IMAGE, id, state);
  }
}

void *mb_image_srv(int id) {
  if (id <= 0 || id >= nimgs) return NULL;
  EnterCriticalSection(&lock);
  ID3D11ShaderResourceView *srv = imgs[id].state == 1 ? imgs[id].srv : NULL;
  LeaveCriticalSection(&lock);
  return srv;
}

}  // extern "C"
