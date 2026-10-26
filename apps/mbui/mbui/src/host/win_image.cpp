// Images on Windows: WIC decodes on a small thread pool straight to the size
// asked for (a scaler over the frame, which the JPEG decoder serves by
// decoding at a reduced size), turned by the EXIF orientation, converted to
// premultiplied BGRA, into a Direct3D 11 texture made right there (device
// methods are free-threaded). http(s) goes through URLDownloadToCacheFile.
// PDFs' pages too (below): drawn by Windows' own (Windows.Data.Pdf) into a PNG
// in memory, which WIC decodes the same way.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <d3d11.h>
#include <wincodec.h>
#include <urlmon.h>
#include <shlwapi.h>
#include <shcore.h>
#include <roapi.h>
#include <wrl.h>
#include <wrl/wrappers/corewrappers.h>
#include <windows.data.pdf.h>
#include <windows.storage.streams.h>
#include <windows.ui.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "win.h"

#pragma comment(lib, "windowscodecs.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "urlmon.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "shcore.lib")
#pragma comment(lib, "runtimeobject.lib")

struct Pdf;

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
  Pdf *pdf;  // or a PDF's page (held while it is drawn)
  int page;
};

static ID3D11ShaderResourceView *pdf_draw(IWICImagingFactory *wic, Pdf *p, int page, int max_px, int *w, int *h,
                                          int *ow, int *oh);
static void pdf_let_go(Pdf *p);

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
    if (j->pdf) {
      srv = pdf_draw(wic, j->pdf, j->page, j->max_px, &w, &h, &ow, &oh);
      hr = E_ABORT;  // (drawn: nothing more to decode)
    } else if (j->data) {
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
  if (j->pdf) pdf_let_go(j->pdf);
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
    if (j->pdf) pdf_let_go(j->pdf);
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

// A ready image's pixels read back from its texture through a staging copy (premultiplied BGRA there: RGBA here),
// rows from the top.
int32_t mb_host_image_pixels(int32_t id, moonbit_bytes_t out) {
  if (id <= 0 || id >= nimgs) return 0;
  EnterCriticalSection(&lock);
  Image im = imgs[id];
  if (im.srv) im.srv->AddRef();
  LeaveCriticalSection(&lock);
  if (im.state != 1 || !im.srv) {
    if (im.srv) im.srv->Release();
    return 0;
  }
  int ok = 0;
  ID3D11Resource *res = NULL;
  ID3D11Texture2D *staging = NULL;
  ID3D11DeviceContext *dc = (ID3D11DeviceContext *)mb_render_context();
  ID3D11Device *dev = (ID3D11Device *)mb_render_device();
  im.srv->GetResource(&res);
  if ((size_t)Moonbit_array_length(out) >= (size_t)im.w * im.h * 4 && res && dc && dev) {
    D3D11_TEXTURE2D_DESC td = {};
    td.Width = im.w;
    td.Height = im.h;
    td.MipLevels = td.ArraySize = 1;
    td.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    td.SampleDesc.Count = 1;
    td.Usage = D3D11_USAGE_STAGING;
    td.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    D3D11_MAPPED_SUBRESOURCE m;
    if (SUCCEEDED(dev->CreateTexture2D(&td, NULL, &staging))) {
      dc->CopyResource(staging, res);
      if (SUCCEEDED(dc->Map(staging, 0, D3D11_MAP_READ, 0, &m))) {
        for (int y = 0; y < im.h; y++) {
          const uint8_t *row = (const uint8_t *)m.pData + (size_t)y * m.RowPitch;
          uint8_t *o = out + (size_t)y * im.w * 4;
          for (int x = 0; x < im.w; x++) {
            o[x * 4] = row[x * 4 + 2];
            o[x * 4 + 1] = row[x * 4 + 1];
            o[x * 4 + 2] = row[x * 4];
            o[x * 4 + 3] = row[x * 4 + 3];
          }
        }
        dc->Unmap(staging, 0);
        ok = 1;
      }
      staging->Release();
    }
  }
  if (res) res->Release();
  im.srv->Release();
  return ok;
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

// A bitmap the clipboard holds (CF_DIB, CF_DIBV5: its header, its colours, its pixels) as a PNG's bytes (malloc'd, into
// *png and *len): 1 when made. Read as a .bmp file is by WIC (the file's own header put before it), then written as
// a PNG. On any thread with COM (win_device.h's clipboard reads, on one of their own).
int mb_png_of_dib(const void *dib, size_t n, unsigned char **png, size_t *len) {
  *png = NULL;
  *len = 0;
  if (n < sizeof(BITMAPINFOHEADER)) return 0;
  const BITMAPINFOHEADER *h = (const BITMAPINFOHEADER *)dib;
  // where the pixels start: after the header, the three masks of a BITMAPINFOHEADER's BI_BITFIELDS, and its colours
  size_t colours = h->biClrUsed ? h->biClrUsed : (h->biBitCount <= 8 ? (1u << h->biBitCount) : 0);
  size_t masks = h->biSize == sizeof(BITMAPINFOHEADER) && h->biCompression == BI_BITFIELDS ? 12 : 0;
  size_t at = h->biSize + masks + colours * 4;
  if (at > n) return 0;
  size_t file = 14 + n;
  uint8_t *bmp = (uint8_t *)malloc(file);
  if (!bmp) return 0;
  bmp[0] = 'B';
  bmp[1] = 'M';
  uint32_t size = (uint32_t)file, zero = 0, off = (uint32_t)(14 + at);
  memcpy(bmp + 2, &size, 4);
  memcpy(bmp + 6, &zero, 4);
  memcpy(bmp + 10, &off, 4);
  memcpy(bmp + 14, dib, n);
  IWICImagingFactory *wic = NULL;
  IWICStream *in = NULL;
  IWICBitmapDecoder *dec = NULL;
  IWICBitmapFrameDecode *frame = NULL;
  IStream *out = NULL;
  IWICBitmapEncoder *enc = NULL;
  IWICBitmapFrameEncode *put = NULL;
  int ok = 0;
  if (SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&wic))) &&
      SUCCEEDED(wic->CreateStream(&in)) && SUCCEEDED(in->InitializeFromMemory(bmp, (DWORD)file)) &&
      SUCCEEDED(wic->CreateDecoderFromStream(in, NULL, WICDecodeMetadataCacheOnDemand, &dec)) &&
      SUCCEEDED(dec->GetFrame(0, &frame)) && SUCCEEDED(CreateStreamOnHGlobal(NULL, TRUE, &out)) &&
      SUCCEEDED(wic->CreateEncoder(GUID_ContainerFormatPng, NULL, &enc)) &&
      SUCCEEDED(enc->Initialize(out, WICBitmapEncoderNoCache)) && SUCCEEDED(enc->CreateNewFrame(&put, NULL)) &&
      SUCCEEDED(put->Initialize(NULL)) && SUCCEEDED(put->WriteSource(frame, NULL)) && SUCCEEDED(put->Commit()) &&
      SUCCEEDED(enc->Commit())) {
    HGLOBAL g = NULL;
    STATSTG st;
    if (SUCCEEDED(GetHGlobalFromStream(out, &g)) && SUCCEEDED(out->Stat(&st, STATFLAG_NONAME))) {
      size_t m = (size_t)st.cbSize.QuadPart;
      const void *p = GlobalLock(g);
      *png = (unsigned char *)malloc(m ? m : 1);
      if (p && *png) {
        memcpy(*png, p, m);
        *len = m;
        ok = 1;
      }
      if (p) GlobalUnlock(g);
    }
  }
  if (put) put->Release();
  if (enc) enc->Release();
  if (out) out->Release();
  if (frame) frame->Release();
  if (dec) dec->Release();
  if (in) in->Release();
  if (wic) wic->Release();
  free(bmp);
  if (!ok) {
    free(*png);
    *png = NULL;
    *len = 0;
  }
  return ok;
}

}  // extern "C"

// ---------------------------------------------------------------------------
// PDFs (host_native.mbt's pdf_*): Windows' own (Windows.Data.Pdf). A document is opened from its bytes on a thread of
// its own in the multithreaded apartment, where its asynchronous calls are waited on (never the UI thread's, whose
// apartment they would call back into), its pages' sizes read there too; a page is drawn on the pool's thread at the
// size asked, on white, as a PNG into memory (RenderToStreamAsync), which WIC decodes into an image of the table
// above (image_info, image_free and the renderer's textures take it as any other). One page at a time of a document.

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Wrappers::HStringReference;
namespace wf = ABI::Windows::Foundation;
namespace wpdf = ABI::Windows::Data::Pdf;
namespace wss = ABI::Windows::Storage::Streams;

struct Pdf {
  LONG refs;                     // the table's (till closed) and each job's drawing it
  wpdf::IPdfDocument *doc;       // NULL: the bytes were no PDF it could open
  int pages;
  double *sizes;                 // each page's width and height in points (its size in DIPs, 96 an inch, as 72)
  SRWLOCK draw;
  const uint8_t *data;           // (while it is opened)
  size_t len;
};

static Pdf **pdfs;
static int npdfs, pdf_cap;
static SRWLOCK pdfs_lock = SRWLOCK_INIT;

static void pdf_let_go(Pdf *p) {
  if (InterlockedDecrement(&p->refs) != 0) return;
  if (p->doc) p->doc->Release();
  free(p->sizes);
  free(p);
}

// an asynchronous call's end waited for (on a thread of the multithreaded apartment)
template <typename Op, typename Done>
static HRESULT pdf_wait(Op *op) {
  HANDLE ended = CreateEventW(NULL, TRUE, FALSE, NULL);
  if (!ended) return E_FAIL;
  HRESULT hr = op->put_Completed(Callback<Done>([ended](Op *, wf::AsyncStatus) -> HRESULT {
                                   SetEvent(ended);
                                   return S_OK;
                                 }).Get());
  if (SUCCEEDED(hr)) WaitForSingleObject(ended, INFINITE);
  CloseHandle(ended);
  return hr;
}

static DWORD WINAPI pdf_open_thread(void *arg) {
  Pdf *p = (Pdf *)arg;
  if (FAILED(RoInitialize(RO_INIT_MULTITHREADED))) return 0;
  {
    ComPtr<IStream> mem;
    mem.Attach(SHCreateMemStream(p->data, (UINT)p->len));
    ComPtr<wss::IRandomAccessStream> in;
    ComPtr<wpdf::IPdfDocumentStatics> statics;
    ComPtr<wf::IAsyncOperation<wpdf::PdfDocument *>> op;
    ComPtr<wpdf::IPdfDocument> doc;
    UINT32 n = 0;
    if (mem && SUCCEEDED(CreateRandomAccessStreamOverStream(mem.Get(), BSOS_DEFAULT, IID_PPV_ARGS(&in))) &&
        SUCCEEDED(wf::GetActivationFactory(HStringReference(RuntimeClass_Windows_Data_Pdf_PdfDocument).Get(), &statics)) &&
        SUCCEEDED(statics->LoadFromStreamAsync(in.Get(), &op)) &&
        SUCCEEDED((pdf_wait<wf::IAsyncOperation<wpdf::PdfDocument *>, wf::IAsyncOperationCompletedHandler<wpdf::PdfDocument *>>(op.Get()))) &&
        SUCCEEDED(op->GetResults(&doc)) && doc && SUCCEEDED(doc->get_PageCount(&n))) {
      p->sizes = (double *)calloc((size_t)(n ? n : 1) * 2, sizeof(double));
      for (UINT32 i = 0; p->sizes && i < n; i++) {
        ComPtr<wpdf::IPdfPage> page;
        wf::Size size = {};
        // (as the page is shown: its crop box, turned as it says)
        if (SUCCEEDED(doc->GetPage(i, &page)) && SUCCEEDED(page->get_Size(&size))) {
          p->sizes[2 * i] = size.Width * 72.0 / 96.0;
          p->sizes[2 * i + 1] = size.Height * 72.0 / 96.0;
        }
      }
      if (p->sizes) {
        p->doc = doc.Detach();
        p->pages = (int)n;
      }
    }
  }
  RoUninitialize();
  return 0;
}

// a page drawn at most `max_px` on its longer side (8192 at most, 1024 unsaid), on white (on the pool's thread)
static ID3D11ShaderResourceView *pdf_draw(IWICImagingFactory *wic, Pdf *p, int page, int max_px, int *w, int *h,
                                          int *ow, int *oh) {
  if (!p->doc || page < 0 || page >= p->pages) return NULL;
  double pw = p->sizes[2 * page], ph = p->sizes[2 * page + 1];
  if (pw <= 0 || ph <= 0) return NULL;
  int lim = max_px > 0 ? (max_px < 8192 ? max_px : 8192) : 1024;
  double k = lim / fmax(pw, ph);
  UINT32 dw = (UINT32)fmax(1, lround(pw * k)), dh = (UINT32)fmax(1, lround(ph * k));
  ID3D11ShaderResourceView *srv = NULL;
  if (FAILED(RoInitialize(RO_INIT_MULTITHREADED))) return NULL;
  AcquireSRWLockExclusive(&p->draw);
  {
    ComPtr<wpdf::IPdfPage> pg;
    ComPtr<IInspectable> made;
    ComPtr<wpdf::IPdfPageRenderOptions> opts;
    ComPtr<IStream> out;
    ComPtr<wss::IRandomAccessStream> to;
    ComPtr<wf::IAsyncAction> act;
    IWICBitmapDecoder *dec = NULL;
    ABI::Windows::UI::Color white = {255, 255, 255, 255};
    LARGE_INTEGER start = {};
    if (SUCCEEDED(p->doc->GetPage((UINT32)page, &pg)) &&
        SUCCEEDED(RoActivateInstance(HStringReference(RuntimeClass_Windows_Data_Pdf_PdfPageRenderOptions).Get(), &made)) &&
        SUCCEEDED(made.As(&opts)) && SUCCEEDED(opts->put_DestinationWidth(dw)) &&
        SUCCEEDED(opts->put_DestinationHeight(dh)) && SUCCEEDED(opts->put_BackgroundColor(white)) &&
        SUCCEEDED(CreateStreamOnHGlobal(NULL, TRUE, &out)) &&
        SUCCEEDED(CreateRandomAccessStreamOverStream(out.Get(), BSOS_DEFAULT, IID_PPV_ARGS(&to))) &&
        SUCCEEDED(pg->RenderWithOptionsToStreamAsync(to.Get(), opts.Get(), &act)) &&
        SUCCEEDED((pdf_wait<wf::IAsyncAction, wf::IAsyncActionCompletedHandler>(act.Get()))) &&
        SUCCEEDED(act->GetResults()) && SUCCEEDED(out->Seek(start, STREAM_SEEK_SET, NULL)) &&
        SUCCEEDED(wic->CreateDecoderFromStream(out.Get(), NULL, WICDecodeMetadataCacheOnDemand, &dec))) {
      srv = decode(wic, dec, lim, w, h, ow, oh);
    }
    if (dec) dec->Release();
  }
  ReleaseSRWLockExclusive(&p->draw);
  RoUninitialize();
  // (its size the page's, in points, as an image's own is)
  *ow = (int)lround(pw);
  *oh = (int)lround(ph);
  return srv;
}

static Pdf *pdf_of(int doc) {
  AcquireSRWLockShared(&pdfs_lock);
  Pdf *p = doc > 0 && doc < npdfs ? pdfs[doc] : NULL;
  ReleaseSRWLockShared(&pdfs_lock);
  return p;
}

extern "C" {

int32_t mb_host_pdf_open(moonbit_bytes_t data) {
  Pdf *p = (Pdf *)calloc(1, sizeof(Pdf));
  if (!p) return 0;
  p->refs = 1;
  InitializeSRWLock(&p->draw);
  p->data = (const uint8_t *)data;
  p->len = (size_t)Moonbit_array_length(data);
  // (opened on a thread of its own, waited for: the bytes are the app's till it returns)
  HANDLE t = CreateThread(NULL, 0, pdf_open_thread, p, 0, NULL);
  if (t) {
    WaitForSingleObject(t, INFINITE);
    CloseHandle(t);
  }
  p->data = NULL;
  AcquireSRWLockExclusive(&pdfs_lock);
  if (npdfs == 0) npdfs = 1;  // 0 is no PDF
  if (npdfs >= pdf_cap) {
    pdf_cap = pdf_cap ? pdf_cap * 2 : 16;
    pdfs = (Pdf **)realloc(pdfs, (size_t)pdf_cap * sizeof *pdfs);
  }
  int id = npdfs++;
  pdfs[id] = p;
  ReleaseSRWLockExclusive(&pdfs_lock);
  return id;
}

int32_t mb_host_pdf_pages(int32_t doc) {
  Pdf *p = pdf_of(doc);
  return p && p->doc ? p->pages : -1;
}

void mb_host_pdf_page_size(int32_t doc, int32_t page, double *out) {
  out[0] = out[1] = 0;
  Pdf *p = pdf_of(doc);
  if (!p || !p->doc || page < 0 || page >= p->pages) return;
  out[0] = p->sizes[2 * page];
  out[1] = p->sizes[2 * page + 1];
}

int32_t mb_host_pdf_page_load(int32_t doc, int32_t page, int32_t max_px) {
  Pdf *p = pdf_of(doc);
  Job *j = (Job *)calloc(1, sizeof(Job));
  j->max_px = max_px;
  j->page = page;
  if (p) {
    InterlockedIncrement(&p->refs);
    j->pdf = p;
  }
  // (none: a job that fails, its image failed as a bad one's)
  if (!p) j->data = (uint8_t *)malloc(1), j->len = 0;
  return start(j);
}

void mb_host_pdf_close(int32_t doc) {
  AcquireSRWLockExclusive(&pdfs_lock);
  Pdf *p = doc > 0 && doc < npdfs ? pdfs[doc] : NULL;
  if (p) pdfs[doc] = NULL;
  ReleaseSRWLockExclusive(&pdfs_lock);
  if (p) pdf_let_go(p);
}

void *mb_image_srv(int id) {
  if (id <= 0 || id >= nimgs) return NULL;
  EnterCriticalSection(&lock);
  ID3D11ShaderResourceView *srv = imgs[id].state == 1 ? imgs[id].srv : NULL;
  LeaveCriticalSection(&lock);
  return srv;
}

}  // extern "C"
