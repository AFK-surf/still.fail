// Native views over the canvas (host_native.mbt's view_*) on Windows: web pages in WebView2, the system's own Edge
// runtime (nothing of Chromium shipped; the SDK's loader is linked in statically). Each is hosted as visuals of the
// DirectComposition tree under the canvas's swap chain (win_render.cpp): the app paints a hole (kind 9: transparent,
// unblended) where one shows and what it paints after the hole draws over it, as apple_views.m and NativeViews.java
// have it. Kind 2, a page of HTML, and kind 3, a site whose every request the app answers (view_site_*); no video
// player yet (kind 1 opens none: 0). Where WebView2's runtime is not installed (or DirectComposition could not be
// had), view_open answers 0 and the app says it cannot show it. MBUI_WEBVIEW2_DIR: a fixed-version runtime's folder
// instead of the installed runtime (one that is not there: as on a machine without it).
//
// Both kinds load from a host of their own that never reaches the network (https://*.stillfail.invalid, its requests
// taken by WebResourceRequested), as Android's WebView does: a page's HTML from here, a site's from the app.
//
// Threads: everything here runs on the UI thread, WebView2's events among them (they come through its message loop).
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <windowsx.h>
#include <objbase.h>
#include <shlwapi.h>
#include <dcomp.h>
#include <wincodec.h>
#include <wrl.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <deque>
#include <map>
#include <string>
#include <vector>
#include "WebView2.h"
#include "win.h"

#pragma comment(lib, "WebView2LoaderStatic.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "oleaut32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "version.lib")
#pragma comment(lib, "windowscodecs.lib")

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

extern "C" void mb_host_request_frame(void);

static const wchar_t kSite[] = L"https://preview.stillfail.invalid";  // a site's own host (Android's Site.HOST)
static const wchar_t kPage[] = L"https://page.stillfail.invalid";     // a page's

// "view N: …" lines on stdout, as the other hosts log theirs
static void vlog(const char *fmt, ...) {
  va_list a;
  va_start(a, fmt);
  vfprintf(stdout, fmt, a);
  va_end(a);
  fputc('\n', stdout);
  fflush(stdout);
}

static std::string utf8(const wchar_t *s, int n = -1) {
  if (!s) return std::string();
  int k = WideCharToMultiByte(CP_UTF8, 0, s, n, NULL, 0, NULL, NULL);
  std::string out(k > 0 ? (size_t)k : 0, '\0');
  if (k > 0) WideCharToMultiByte(CP_UTF8, 0, s, n, &out[0], k, NULL, NULL);
  if (n < 0 && !out.empty()) out.pop_back();  // its terminator
  return out;
}

static std::wstring wstr(moonbit_string_t s) {
  return std::wstring((const wchar_t *)s, (size_t)Moonbit_array_length(s));
}

static moonbit_string_t mstr(const std::wstring &s) {
  moonbit_string_t out = moonbit_make_string_raw((int32_t)s.size());
  if (!s.empty()) memcpy(out, s.data(), s.size() * sizeof(wchar_t));
  return out;
}

// a JSON string's text, quoted
static void jstr(std::wstring &o, const wchar_t *s) {
  o += L'"';
  for (; s && *s; s++) {
    wchar_t c = *s;
    if (c == L'"' || c == L'\\') {
      o += L'\\';
      o += c;
    } else if (c < 0x20) {
      wchar_t b[8];
      swprintf(b, 8, L"\\u%04x", (unsigned)c);
      o += b;
    } else {
      o += c;
    }
  }
  o += L'"';
}

// [[k,v]…] as JSON text (the app's head): its pairs. Only that shape is read.
static bool jread_str(const wchar_t *&p, std::wstring &out) {
  while (*p == L' ') p++;
  if (*p != L'"') return false;
  p++;
  out.clear();
  while (*p && *p != L'"') {
    if (*p != L'\\') {
      out += *p++;
      continue;
    }
    p++;
    switch (*p) {
      case L'n': out += L'\n'; break;
      case L't': out += L'\t'; break;
      case L'r': out += L'\r'; break;
      case L'b': out += L'\b'; break;
      case L'f': out += L'\f'; break;
      case L'u': {
        unsigned v = 0;
        for (int i = 1; i <= 4 && p[i]; i++) {
          wchar_t h = p[i];
          v = v * 16 + (h >= L'0' && h <= L'9' ? h - L'0' : (h | 0x20) - L'a' + 10);
        }
        out += (wchar_t)v;
        p += 4;
        break;
      }
      default: out += *p;
    }
    if (*p) p++;
  }
  if (*p != L'"') return false;
  p++;
  return true;
}

static std::vector<std::pair<std::wstring, std::wstring>> jpairs(const std::wstring &text) {
  std::vector<std::pair<std::wstring, std::wstring>> out;
  const wchar_t *p = text.c_str();
  while (*p && *p != L'[') p++;
  if (*p) p++;
  for (;;) {
    while (*p == L' ' || *p == L',') p++;
    if (*p != L'[') break;
    p++;
    std::wstring k, v;
    if (!jread_str(p, k)) break;
    while (*p == L' ' || *p == L',') p++;
    if (!jread_str(p, v)) break;
    while (*p && *p != L']') p++;
    if (*p) p++;
    out.push_back({k, v});
  }
  return out;
}

// ---------------------------------------------------------------------------

// One request of a site's page: what it asked, its deferral until the app answers it whole.
struct Req {
  int rid;
  ComPtr<ICoreWebView2WebResourceRequestedEventArgs> args;
  ComPtr<ICoreWebView2Deferral> deferral;
  std::vector<uint8_t> body;  // the request's
  bool headed = false;
  int status = 200;
  std::wstring headers;       // "K: V\r\n"…
  std::vector<uint8_t> data;  // the answer's body so far
};

struct View {
  int vid, kind;
  double x = 0, y = 0, w = 0, h = 0, cx0 = 0, cy0 = 0, cx1 = 0, cy1 = 0, radius = 0;
  ComPtr<IDCompositionRectangleClip> round;  // its content cut to its rect, rounded (radius > 0)
  bool shown = false, placed = false;
  bool loaded = false, failed = false, closed = false, told = false, loading = true;
  std::string html;    // a page's
  std::wstring start;  // a site's first path
  int html_len = 0;
  ComPtr<ICoreWebView2CompositionController> comp;
  ComPtr<ICoreWebView2Controller> ctl;
  ComPtr<ICoreWebView2> web;
  ComPtr<IDCompositionVisual> box;      // clips: at the clip rect
  ComPtr<IDCompositionVisual> content;  // in it: at the view's rect, the web view's root
  // a site's
  std::deque<std::wstring> said;
  std::map<int, Req *> reqs;
  int next_req = 0;
  double zoom = 1;
  // its picture for snapshots (premultiplied BGRA), being taken
  std::vector<uint8_t> snap;
  int snap_w = 0, snap_h = 0;
  bool snapping = false;
  HCURSOR cursor = NULL;
  // a page's and a site's: the scripts the app sent (view_tell 1), waiting for the page there (loaded, or said
  // something since it started); who takes the mouse on it (view_tell 2); a page grabbed (PNG; still_state 1 grabbing,
  // 2 here, -1 failed)
  std::vector<std::wstring> scripts;
  bool there = false;
  std::string touch = "all";
  std::vector<uint8_t> still;
  int still_state = 0;
};

static HWND hwnd_main;
static std::map<int, View *> views;  // by id: as they are stacked
static int next_vid;
static ComPtr<ICoreWebView2Environment> env;
static int env_state;  // 0 not asked, 1 being made, 2 here, -1 failed
static int runtime;    // 0 not looked for, 1 installed, -1 not
static std::deque<std::pair<int, int>> told;  // (id, state) for the app (mb_views_tell)
static std::deque<std::pair<int, int>> grabs;  // (id, state) of pages grabbed, for the app (mb_views_tell)
static int captured;   // the view a button went down on, until it is up
static int hovered;    // the view the pointer was last in

static View *find(int vid) {
  auto it = views.find(vid);
  return it == views.end() ? NULL : it->second;
}

// Its state for the app (host_native.mbt's set_outside, kind 2): 1 ready (a page loaded), -1 failed, 0 waiting on the
// app now (a site's request): told between frames (mb_views_tell).
static void outside(View *v, int state) {
  told.push_back({v->vid, state});
  vlog("view %d: told %d", v->vid, state);
  mb_host_request_frame();
}

static void tell(View *v, int state) {
  if (v->told && state > 0) return;
  v->told = state > 0;
  outside(v, state);
}

static void fail(View *v, const char *why, HRESULT hr) {
  if (v->loaded || v->closed || v->failed) return;
  v->failed = true;
  vlog("view %d: failed: %s (0x%08lx)", v->vid, why, (unsigned long)hr);
  tell(v, -1);
}

static double scale_now(void) { return mb_app_scale(); }

// Placed as it was last told: its box at the clip, the web view at its rect within it, hidden by an empty clip.
static void apply_place(View *v) {
  if (!v->box || !v->ctl) return;
  double s = scale_now();
  double bx = round(v->cx0 * s), by = round(v->cy0 * s);
  v->box->SetOffsetX((float)bx);
  v->box->SetOffsetY((float)by);
  D2D_RECT_F clip = {0, 0, 0, 0};
  if (v->shown) clip = {0, 0, (float)fmax(0, round(v->cx1 * s) - bx), (float)fmax(0, round(v->cy1 * s) - by)};
  v->box->SetClip(clip);
  // its content's edges each on the device pixel nearest it (right minus left, not its width rounded: that can land a
  // pixel off the hole's edge)
  double px0 = round(v->x * s), py0 = round(v->y * s);
  double pw = fmax(0, round((v->x + fmax(0, v->w)) * s) - px0), ph = fmax(0, round((v->y + fmax(0, v->h)) * s) - py0);
  v->content->SetOffsetX((float)(px0 - bx));
  v->content->SetOffsetY((float)(py0 - by));
  RECT r = {0, 0, (LONG)pw, (LONG)ph};
  v->ctl->put_Bounds(r);
  // its corners round (as the hole the app paints for it): its content's visual cut to its rect, rounded
  if (v->radius > 0) {
    IDCompositionDevice *dc = (IDCompositionDevice *)mb_render_dcomp();
    if (!v->round && dc) dc->CreateRectangleClip(&v->round);
    if (v->round) {
      float rr = (float)(v->radius * s);
      v->round->SetLeft(0.0f);
      v->round->SetTop(0.0f);
      v->round->SetRight((float)pw);
      v->round->SetBottom((float)ph);
      v->round->SetTopLeftRadiusX(rr);
      v->round->SetTopLeftRadiusY(rr);
      v->round->SetTopRightRadiusX(rr);
      v->round->SetTopRightRadiusY(rr);
      v->round->SetBottomLeftRadiusX(rr);
      v->round->SetBottomLeftRadiusY(rr);
      v->round->SetBottomRightRadiusX(rr);
      v->round->SetBottomRightRadiusY(rr);
      v->content->SetClip(v->round.Get());
    }
  } else if (v->round) {
    v->content->SetClip((IDCompositionClip *)NULL);
    v->round.Reset();
  }
  v->ctl->put_IsVisible(v->shown ? TRUE : FALSE);
  mb_render_commit();
  // where it is now, in device pixels (scripts/host_contract.sh HOST views compares it with VIEWTOLD)
  if (v->shown)
    vlog("VIEWAT %d %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f", v->vid, px0, py0, pw, ph, bx, by, bx + clip.right,
         by + clip.bottom, v->round ? v->radius * s : 0.0);
}

// ---- its picture for snapshots ----

static void decode_snap(View *v, IStream *st) {
  LARGE_INTEGER zero = {};
  st->Seek(zero, STREAM_SEEK_SET, NULL);
  ComPtr<IWICImagingFactory> wic;
  ComPtr<IWICBitmapDecoder> dec;
  ComPtr<IWICBitmapFrameDecode> frame;
  ComPtr<IWICBitmapSource> conv;
  UINT w = 0, h = 0;
  if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&wic))) ||
      FAILED(wic->CreateDecoderFromStream(st, NULL, WICDecodeMetadataCacheOnDemand, &dec)) ||
      FAILED(dec->GetFrame(0, &frame)) ||
      FAILED(WICConvertBitmapSource(GUID_WICPixelFormat32bppPBGRA, frame.Get(), &conv)) ||
      FAILED(conv->GetSize(&w, &h)) || !w || !h) {
    vlog("view %d: its picture could not be read", v->vid);
    return;
  }
  std::vector<uint8_t> px((size_t)w * h * 4);
  if (FAILED(conv->CopyPixels(NULL, w * 4, (UINT)px.size(), px.data()))) return;
  v->snap.swap(px);
  v->snap_w = (int)w;
  v->snap_h = (int)h;
}

// The page's picture taken anew (asynchronous: the latest kept).
static void refresh_snap(View *v) {
  if (!v->loaded || !v->web || v->w <= 0 || v->h <= 0 || v->snapping) return;
  ComPtr<IStream> st;
  if (FAILED(CreateStreamOnHGlobal(NULL, TRUE, &st))) return;
  int vid = v->vid;
  v->snapping = true;
  HRESULT hr = v->web->CapturePreview(
      COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_PNG, st.Get(),
      Callback<ICoreWebView2CapturePreviewCompletedHandler>([vid, st](HRESULT r) -> HRESULT {
        View *v = find(vid);
        if (!v) return S_OK;
        v->snapping = false;
        if (SUCCEEDED(r)) decode_snap(v, st.Get());
        else vlog("view %d: its picture not taken (0x%08lx)", vid, (unsigned long)r);
        mb_host_request_frame();
        return S_OK;
      }).Get());
  if (FAILED(hr)) v->snapping = false;
}

// ---- requests of its own host ----

static IStream *mem_stream(const void *data, size_t n) {
  return SHCreateMemStream((const BYTE *)data, (UINT)n);
}

static const wchar_t *reason(int status) {
  return status >= 200 && status < 300 ? L"OK" : status == 404 ? L"Not Found" : status >= 500 ? L"Error" : L"Status";
}

static void respond(ICoreWebView2WebResourceRequestedEventArgs *args, int status, const std::wstring &headers,
                    const void *data, size_t n) {
  if (!env) return;
  ComPtr<IStream> st;
  st.Attach(mem_stream(data, n));
  ComPtr<ICoreWebView2WebResourceResponse> r;
  if (SUCCEEDED(env->CreateWebResourceResponse(st.Get(), status, reason(status), headers.c_str(), &r)))
    args->put_Response(r.Get());
}

// the path (with its query) of a URI of `host`; empty when it is not one of its
static std::wstring path_of(const wchar_t *uri, const wchar_t *host) {
  size_t n = wcslen(host);
  if (!uri || _wcsnicmp(uri, host, n) != 0) return std::wstring();
  const wchar_t *p = uri + n;
  if (*p == 0) return L"/";
  if (*p != L'/' && *p != L'?') return std::wstring();
  std::wstring out = p;
  size_t hash = out.find(L'#');
  if (hash != std::wstring::npos) out.resize(hash);
  if (out.empty() || out[0] == L'?') out = L"/" + out;
  return out;
}

static void on_request(View *v, ICoreWebView2WebResourceRequestedEventArgs *args) {
  ComPtr<ICoreWebView2WebResourceRequest> rq;
  if (FAILED(args->get_Request(&rq))) return;
  LPWSTR uri = NULL, method = NULL;
  rq->get_Uri(&uri);
  rq->get_Method(&method);
  if (v->kind == 2) {
    // the page given, and nothing else of its host
    std::wstring p = path_of(uri, kPage);
    if (p == L"/") respond(args, 200, L"Content-Type: text/html; charset=utf-8", v->html.data(), v->html.size());
    else respond(args, 404, L"Content-Type: text/plain", "", 0);
    CoTaskMemFree(uri);
    CoTaskMemFree(method);
    return;
  }
  Req *q = new Req;
  q->rid = ++v->next_req;
  q->args = args;
  args->GetDeferral(&q->deferral);
  ComPtr<IStream> body;
  if (SUCCEEDED(rq->get_Content(&body)) && body) {
    uint8_t buf[16384];
    ULONG n = 0;
    while (SUCCEEDED(body->Read(buf, sizeof buf, &n)) && n > 0) q->body.insert(q->body.end(), buf, buf + n);
  }
  COREWEBVIEW2_WEB_RESOURCE_CONTEXT rc = COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL;
  args->get_ResourceContext(&rc);
  bool page = rc == COREWEBVIEW2_WEB_RESOURCE_CONTEXT_DOCUMENT;
  std::wstring e = L"{\"req\":" + std::to_wstring(q->rid) + L",\"method\":";
  jstr(e, method ? method : L"GET");
  e += L",\"path\":";
  std::wstring path = path_of(uri, kSite);
  jstr(e, path.empty() ? L"/" : path.c_str());
  e += L",\"headers\":[";
  ComPtr<ICoreWebView2HttpRequestHeaders> hs;
  ComPtr<ICoreWebView2HttpHeadersCollectionIterator> it;
  bool first = true;
  if (SUCCEEDED(rq->get_Headers(&hs)) && SUCCEEDED(hs->GetIterator(&it))) {
    BOOL has = FALSE;
    while (SUCCEEDED(it->get_HasCurrentHeader(&has)) && has) {
      LPWSTR k = NULL, val = NULL;
      if (SUCCEEDED(it->GetCurrentHeader(&k, &val))) {
        if (!first) e += L',';
        first = false;
        e += L'[';
        jstr(e, k);
        e += L',';
        jstr(e, val);
        e += L']';
        if (k && _wcsicmp(k, L"Accept") == 0 && val && _wcsnicmp(val, L"text/html", 9) == 0) page = true;
        CoTaskMemFree(k);
        CoTaskMemFree(val);
      }
      BOOL more = FALSE;
      if (FAILED(it->MoveNext(&more)) || !more) break;
    }
  }
  e += L"],\"page\":";
  e += page ? L"true}" : L"false}";
  v->reqs[q->rid] = q;
  v->said.push_back(e);
  CoTaskMemFree(uri);
  CoTaskMemFree(method);
  // the site waits on the app's answer now
  outside(v, 0);
}

// The request answered as it stands (whole, or a page saying why there was none), or let go to fail (`broke`: its
// deferral ends with no answer: the host is not on the network, so the page sees a network error).
static void finish(View *v, Req *q, const std::wstring &error) {
  if (!q->headed) {
    std::string msg = error.empty() ? std::string("no answer") : utf8(error.c_str());
    respond(q->args.Get(), 502, L"Content-Type: text/plain; charset=utf-8", msg.data(), msg.size());
  } else if (error.empty()) {
    respond(q->args.Get(), q->status, q->headers, q->data.data(), q->data.size());
  } else {
    vlog("view %d: request %d broke off: %s", v->vid, q->rid, utf8(error.c_str()).c_str());
  }
  if (q->deferral) q->deferral->Complete();
  delete q;
}

// ---- making it ----

// What waits for the page runs, once it is there.
static void run_scripts(View *v) {
  if (!v->there || !v->web || v->closed) return;
  for (auto &js : v->scripts) v->web->ExecuteScript(js.c_str(), NULL);
  v->scripts.clear();
}

static void on_nav_start(View *v, ICoreWebView2NavigationStartingEventArgs *a) {
  LPWSTR uri = NULL;
  a->get_Uri(&uri);
  std::wstring u = uri ? uri : L"";
  CoTaskMemFree(uri);
  bool about = _wcsnicmp(u.c_str(), L"about:", 6) == 0;
  bool ok;
  if (v->kind == 3) {
    ok = about || !path_of(u.c_str(), kSite).empty();
    bool quiet = _wcsnicmp(u.c_str(), L"data:", 5) == 0 || _wcsnicmp(u.c_str(), L"blob:", 5) == 0 ||
                 _wcsnicmp(u.c_str(), L"javascript:", 11) == 0;
    if (!ok && !quiet) {
      // a link elsewhere: said to the app, not followed
      std::wstring e = L"{\"leave\":";
      jstr(e, u.c_str());
      e += L'}';
      v->said.push_back(e);
    }
  } else {
    // only the page given: no link followed, nothing else loaded
    ok = about || !path_of(u.c_str(), kPage).empty();
    if (!ok) vlog("view %d: navigation to %s cancelled", v->vid, utf8(u.c_str()).c_str());
  }
  if (!ok) a->put_Cancel(TRUE);
  else {
    v->loading = true;
    v->there = false;
  }
  mb_host_request_frame();
}

static void on_nav_done(View *v, ICoreWebView2NavigationCompletedEventArgs *a) {
  BOOL ok = FALSE;
  a->get_IsSuccess(&ok);
  COREWEBVIEW2_WEB_ERROR_STATUS st = COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN;
  a->get_WebErrorStatus(&st);
  // a page that came with an HTTP error status (the app's 404, a 502 saying why) is a page shown
  ComPtr<ICoreWebView2NavigationCompletedEventArgs2> a2;
  int code = 0;
  if (!ok && SUCCEEDED(a->QueryInterface(IID_PPV_ARGS(&a2)))) a2->get_HttpStatusCode(&code);
  v->loading = false;
  mb_host_request_frame();
  if (v->closed) return;
  if (ok || code > 0) {
    v->there = true;
    run_scripts(v);
    if (v->kind == 3) {
      refresh_snap(v);
      tell(v, 1);
    }
    if (v->loaded) return;
    v->loaded = true;
    vlog("view %d: %s loaded", v->vid, v->kind == 3 ? "site page" : "page");
    tell(v, 1);
    refresh_snap(v);
    return;
  }
  // one it went from (a link cancelled, a new one begun) is not a failure
  if (st == COREWEBVIEW2_WEB_ERROR_STATUS_OPERATION_CANCELED) return;
  fail(v, "the page could not be loaded", (HRESULT)st);
}

static void made(View *v, ICoreWebView2CompositionController *cc) {
  IDCompositionDevice *dc = (IDCompositionDevice *)mb_render_dcomp();
  IDCompositionVisual *under = (IDCompositionVisual *)mb_render_views_visual();
  v->comp = cc;
  if (FAILED(cc->QueryInterface(IID_PPV_ARGS(&v->ctl))) || FAILED(v->ctl->get_CoreWebView2(&v->web)) || !dc ||
      !under || FAILED(dc->CreateVisual(&v->box)) || FAILED(dc->CreateVisual(&v->content))) {
    fail(v, "its web view could not be made", E_FAIL);
    return;
  }
  v->box->AddVisual(v->content.Get(), FALSE, NULL);
  under->AddVisual(v->box.Get(), TRUE, NULL);  // over the views opened before it
  v->box->SetClip(D2D_RECT_F{0, 0, 0, 0});
  cc->put_RootVisualTarget(v->content.Get());
  ComPtr<ICoreWebView2Controller2> c2;
  if (SUCCEEDED(v->ctl.As(&c2))) c2->put_DefaultBackgroundColor(COREWEBVIEW2_COLOR{255, 255, 255, 255});
  ComPtr<ICoreWebView2Controller3> c3;
  if (SUCCEEDED(v->ctl.As(&c3))) {
    c3->put_ShouldDetectMonitorScaleChanges(FALSE);
    c3->put_RasterizationScale(scale_now());
  }
  if (v->zoom != 1) v->ctl->put_ZoomFactor(v->zoom);
  ComPtr<ICoreWebView2Settings> s;
  if (SUCCEEDED(v->web->get_Settings(&s))) {
    s->put_IsScriptEnabled(TRUE);
    s->put_AreDevToolsEnabled(FALSE);
    s->put_IsStatusBarEnabled(FALSE);
    s->put_IsZoomControlEnabled(FALSE);
    s->put_AreHostObjectsAllowed(FALSE);
    // the page's way to the app (mbuiHost.post), its own messages, nothing else of the app's
    s->put_IsWebMessageEnabled(TRUE);
  }
  int vid = v->vid;
  EventRegistrationToken tok;
  v->web->AddScriptToExecuteOnDocumentCreated(
      L"window.mbuiHost={post:function(t){window.chrome.webview.postMessage(String(t))}};", NULL);
  v->web->add_WebMessageReceived(
      Callback<ICoreWebView2WebMessageReceivedEventHandler>(
          [vid](ICoreWebView2 *, ICoreWebView2WebMessageReceivedEventArgs *a) -> HRESULT {
            View *v = find(vid);
            LPWSTR text = NULL;
            if (v && !v->closed && SUCCEEDED(a->TryGetWebMessageAsString(&text)) && text) {
              std::wstring e = L"{\"said\":";
              jstr(e, text);
              e += L'}';
              v->said.push_back(e);
              v->there = true;
              run_scripts(v);
              mb_host_request_frame();
            }
            CoTaskMemFree(text);
            return S_OK;
          }).Get(),
      &tok);
  std::wstring filter = std::wstring(v->kind == 3 ? kSite : kPage) + L"/*";
  v->web->AddWebResourceRequestedFilter(filter.c_str(), COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
  v->web->add_WebResourceRequested(
      Callback<ICoreWebView2WebResourceRequestedEventHandler>(
          [vid](ICoreWebView2 *, ICoreWebView2WebResourceRequestedEventArgs *a) -> HRESULT {
            View *v = find(vid);
            if (v) on_request(v, a);
            return S_OK;
          }).Get(),
      &tok);
  v->web->add_NavigationStarting(
      Callback<ICoreWebView2NavigationStartingEventHandler>(
          [vid](ICoreWebView2 *, ICoreWebView2NavigationStartingEventArgs *a) -> HRESULT {
            View *v = find(vid);
            if (v) on_nav_start(v, a);
            return S_OK;
          }).Get(),
      &tok);
  v->web->add_NavigationCompleted(
      Callback<ICoreWebView2NavigationCompletedEventHandler>(
          [vid](ICoreWebView2 *, ICoreWebView2NavigationCompletedEventArgs *a) -> HRESULT {
            View *v = find(vid);
            if (v) on_nav_done(v, a);
            return S_OK;
          }).Get(),
      &tok);
  // a new window asked for (target=_blank, window.open): none opens; a site's is said as a link left by
  v->web->add_NewWindowRequested(
      Callback<ICoreWebView2NewWindowRequestedEventHandler>(
          [vid](ICoreWebView2 *, ICoreWebView2NewWindowRequestedEventArgs *a) -> HRESULT {
            a->put_Handled(TRUE);
            View *v = find(vid);
            LPWSTR uri = NULL;
            a->get_Uri(&uri);
            if (v && v->kind == 3 && uri) {
              std::wstring e = L"{\"leave\":";
              jstr(e, uri);
              e += L'}';
              v->said.push_back(e);
              mb_host_request_frame();
            }
            CoTaskMemFree(uri);
            return S_OK;
          }).Get(),
      &tok);
  v->web->add_HistoryChanged(Callback<ICoreWebView2HistoryChangedEventHandler>([](ICoreWebView2 *, IUnknown *) -> HRESULT {
                               mb_host_request_frame();
                               return S_OK;
                             }).Get(),
                             &tok);
  v->web->add_DocumentTitleChanged(
      Callback<ICoreWebView2DocumentTitleChangedEventHandler>([](ICoreWebView2 *, IUnknown *) -> HRESULT {
        mb_host_request_frame();
        return S_OK;
      }).Get(),
      &tok);
  cc->add_CursorChanged(Callback<ICoreWebView2CursorChangedEventHandler>(
                            [vid](ICoreWebView2CompositionController *c, IUnknown *) -> HRESULT {
                              View *v = find(vid);
                              if (v) c->get_Cursor(&v->cursor);
                              return S_OK;
                            }).Get(),
                        &tok);
  if (v->placed) apply_place(v);
  else mb_render_commit();
  std::wstring url = v->kind == 3 ? std::wstring(kSite) + (v->start.empty() ? L"/" : v->start) : std::wstring(kPage) + L"/";
  HRESULT hr = v->web->Navigate(url.c_str());
  if (FAILED(hr)) fail(v, "its page could not be asked for", hr);
  vlog("view %d: web view made", vid);
}

static void make_web(View *v) {
  ComPtr<ICoreWebView2Environment3> e3;
  if (FAILED(env.As(&e3))) {
    fail(v, "this WebView2 runtime hosts no visuals", E_NOINTERFACE);
    return;
  }
  int vid = v->vid;
  auto done = Callback<ICoreWebView2CreateCoreWebView2CompositionControllerCompletedHandler>(
      [vid](HRESULT r, ICoreWebView2CompositionController *cc) -> HRESULT {
        View *v = find(vid);
        if (!v) {
          // closed meanwhile
          ComPtr<ICoreWebView2Controller> c;
          if (cc && SUCCEEDED(cc->QueryInterface(IID_PPV_ARGS(&c)))) c->Close();
          return S_OK;
        }
        if (FAILED(r) || !cc) fail(v, "its web view could not be made", r);
        else made(v, cc);
        return S_OK;
      });
  HRESULT hr;
  // InPrivate where the runtime has it: nothing of it kept (as Apple's non-persistent data store)
  ComPtr<ICoreWebView2Environment10> e10;
  ComPtr<ICoreWebView2ControllerOptions> opts;
  if (SUCCEEDED(env.As(&e10)) && SUCCEEDED(e10->CreateCoreWebView2ControllerOptions(&opts))) {
    opts->put_IsInPrivateModeEnabled(TRUE);
    hr = e10->CreateCoreWebView2CompositionControllerWithOptions(hwnd_main, opts.Get(), done.Get());
  } else {
    hr = e3->CreateCoreWebView2CompositionController(hwnd_main, done.Get());
  }
  if (FAILED(hr)) fail(v, "its web view could not be asked for", hr);
}

// MBUI_WEBVIEW2_DIR: a fixed-version runtime's folder to use instead of the installed one (NULL: the installed one)
static const wchar_t *runtime_dir(void) {
  const wchar_t *d = _wgetenv(L"MBUI_WEBVIEW2_DIR");
  return d && *d ? d : NULL;
}

static void make_env(void) {
  env_state = 1;
  wchar_t dir[MAX_PATH + 32];
  DWORD n = GetTempPathW(MAX_PATH, dir);
  wcscpy_s(dir + n, 32, L"mbui-webview2");
  HRESULT hr = CreateCoreWebView2EnvironmentWithOptions(
      runtime_dir(), dir, NULL,
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [](HRESULT r, ICoreWebView2Environment *e) -> HRESULT {
            if (FAILED(r) || !e) {
              env_state = -1;
              vlog("view: no WebView2 environment (0x%08lx)", (unsigned long)r);
              for (auto &kv : views) fail(kv.second, "no WebView2 environment", r);
              return S_OK;
            }
            env = e;
            env_state = 2;
            for (auto &kv : views)
              if (!kv.second->comp && !kv.second->failed) make_web(kv.second);
            return S_OK;
          }).Get());
  if (FAILED(hr)) {
    env_state = -1;
    vlog("view: no WebView2 environment (0x%08lx)", (unsigned long)hr);
    for (auto &kv : views) fail(kv.second, "no WebView2 environment", hr);
  }
}

// Whether WebView2's runtime is installed (looked for once).
static bool runtime_here(void) {
  if (runtime) return runtime > 0;
  LPWSTR ver = NULL;
  HRESULT hr = GetAvailableCoreWebView2BrowserVersionString(runtime_dir(), &ver);
  runtime = SUCCEEDED(hr) && ver ? 1 : -1;
  if (runtime > 0) vlog("view: WebView2 runtime %s", utf8(ver).c_str());
  else vlog("view: no WebView2 runtime (0x%08lx): web views cannot be shown", (unsigned long)hr);
  CoTaskMemFree(ver);
  return runtime > 0;
}

// ---------------------------------------------------------------------------
// The host API MoonBit calls

extern "C" int32_t mb_host_view_open(int32_t kind, moonbit_string_t arg) {
  if (kind == 1) vlog("view: no video player on Windows yet");
  if (kind != 2 && kind != 3) return 0;
  if (!mb_render_dcomp() || !runtime_here()) return 0;
  if (!hwnd_main) hwnd_main = (HWND)mb_app_hwnd();
  View *v = new View;
  v->vid = ++next_vid;
  v->kind = kind;
  if (kind == 2) {
    std::wstring h = wstr(arg);
    v->html = utf8(h.c_str(), (int)h.size());
    v->html_len = (int)v->html.size();
    vlog("view %d: open web page (%d bytes)", v->vid, v->html_len);
  } else {
    v->start = wstr(arg);
    if (v->start.empty()) v->start = L"/";
    vlog("view %d: open site at %s", v->vid, utf8(v->start.c_str()).c_str());
  }
  views[v->vid] = v;
  if (env_state == 2) make_web(v);
  else if (env_state == 0) make_env();
  else if (env_state < 0) fail(v, "no WebView2 environment", E_FAIL);
  return v->vid;
}

extern "C" void mb_host_view_place(int32_t vid, double x, double y, double w, double h, double cx0, double cy0,
                                   double cx1, double cy1, double radius, int32_t shown) {
  View *v = find(vid);
  if (!v) return;
  bool s = shown != 0;
  if (v->placed && v->shown == s && v->x == x && v->y == y && v->w == w && v->h == h && v->cx0 == cx0 &&
      v->cy0 == cy0 && v->cx1 == cx1 && v->cy1 == cy1 && v->radius == radius)
    return;
  bool resized = !v->placed || v->w != w || v->h != h;
  v->placed = true;
  v->shown = s;
  v->x = x; v->y = y; v->w = w; v->h = h;
  v->cx0 = cx0; v->cy0 = cy0; v->cx1 = cx1; v->cy1 = cy1;
  v->radius = radius;
  apply_place(v);
  if (resized) refresh_snap(v);
}

extern "C" void mb_host_view_close(int32_t vid) {
  View *v = find(vid);
  if (!v) return;
  views.erase(vid);
  v->closed = true;
  for (auto &kv : v->reqs) {
    if (kv.second->deferral) kv.second->deferral->Complete();
    delete kv.second;
  }
  v->reqs.clear();
  if (v->ctl) v->ctl->Close();
  IDCompositionVisual *under = (IDCompositionVisual *)mb_render_views_visual();
  if (under && v->box) under->RemoveVisual(v->box.Get());
  mb_render_commit();
  if (captured == vid) {
    captured = 0;
    ReleaseCapture();
  }
  if (hovered == vid) hovered = 0;
  vlog("view %d: closed", vid);
  delete v;
}

// What its page shows now, as a PNG (CapturePreview): `still` once it is here, told as a grab.
static void grab_page(View *v) {
  v->still_state = 1;
  v->still.clear();
  int vid = v->vid;
  ComPtr<IStream> st;
  if (!v->web || FAILED(CreateStreamOnHGlobal(NULL, TRUE, &st))) {
    v->still_state = -1;
    grabs.push_back({vid, -1});
    mb_host_request_frame();
    return;
  }
  v->web->CapturePreview(COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_PNG, st.Get(),
                         Callback<ICoreWebView2CapturePreviewCompletedHandler>([vid, st](HRESULT hr) -> HRESULT {
                           View *v = find(vid);
                           if (!v) return S_OK;
                           STATSTG info = {};
                           if (SUCCEEDED(hr) && SUCCEEDED(st->Stat(&info, STATFLAG_NONAME)) && info.cbSize.QuadPart > 0) {
                             v->still.resize((size_t)info.cbSize.QuadPart);
                             LARGE_INTEGER zero = {};
                             st->Seek(zero, STREAM_SEEK_SET, NULL);
                             ULONG got = 0;
                             st->Read(v->still.data(), (ULONG)v->still.size(), &got);
                             v->still.resize(got);
                           }
                           v->still_state = v->still.empty() ? -1 : 2;
                           vlog("view %d: page %s", vid, v->still_state == 2 ? "grabbed" : "not grabbed");
                           grabs.push_back({vid, v->still_state == 2 ? 1 : -1});
                           mb_host_request_frame();
                           return S_OK;
                         }).Get());
}

extern "C" void mb_host_view_control(int32_t vid, int32_t op, double value) {
  View *v = find(vid);
  if (v && op == 21) {
    grab_page(v);
    return;
  }
  if (!v || v->kind != 3) return;
  if (op == 8) {
    // laid out at its rect over the scale, drawn at the scale
    if (value > 0) {
      v->zoom = value;
      if (v->ctl) v->ctl->put_ZoomFactor(value);
    }
    return;
  }
  if (!v->web) return;
  BOOL can = FALSE;
  switch (op) {
    case 5: if (SUCCEEDED(v->web->get_CanGoBack(&can)) && can) v->web->GoBack(); break;
    case 6: if (SUCCEEDED(v->web->get_CanGoForward(&can)) && can) v->web->GoForward(); break;
    case 7: v->web->Reload(); break;
  }
}

extern "C" int32_t mb_host_view_info(int32_t vid, double *out) {
  for (int i = 0; i < 10; i++) out[i] = 0;
  out[0] = -1;
  View *v = find(vid);
  if (!v) return -1;
  if (v->kind == 2) out[5] = v->html_len;
  out[6] = v->loaded ? 1 : 0;
  return v->failed ? -1 : v->loaded ? 1 : 0;
}

// a player's: none here
extern "C" int32_t mb_host_view_read_next(int32_t vid, double *out) { (void)vid; (void)out; return 0; }
extern "C" void mb_host_view_read_answer(int32_t vid, int32_t req, moonbit_bytes_t data, double total) {
  (void)vid; (void)req; (void)data; (void)total;
}
// a page's grab: how it stands (what 2), the PNG
extern "C" moonbit_string_t mb_host_view_text(int32_t vid, int32_t what) {
  View *v = find(vid);
  if (!v || what != 2) return moonbit_make_string_raw(0);
  return mstr(std::to_wstring(v->still_state));
}
extern "C" int32_t mb_host_view_text_known(int32_t vid, int32_t what) { return find(vid) && what == 2 ? 1 : 0; }
extern "C" moonbit_bytes_t mb_host_view_still(int32_t vid) {
  View *v = find(vid);
  size_t n = v ? v->still.size() : 0;
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)n, 0);
  if (n) memcpy(out, v->still.data(), n);
  if (v) {
    v->still.clear();
    if (v->still_state == 2) v->still_state = 0;
  }
  return out;
}

// What the app tells a view beyond its controls (host_native.mbt view_tell): a script for its page, who takes the
// mouse on it ("through": the canvas, "vertical": the canvas its wheel's upright scroll), a site's settings (WebView2
// waits on a request's deferral as long as the app takes: no head wait here).
extern "C" void mb_host_view_tell(int32_t vid, int32_t what, moonbit_string_t text) {
  View *v = find(vid);
  if (!v || v->kind < 2) return;
  std::wstring t = wstr(text);
  if (what == 1) {
    v->scripts.push_back(t);
    run_scripts(v);
  } else if (what == 2) {
    std::string m = utf8(t.c_str());
    v->touch = m.substr(0, m.find(' '));
  }
}

// ---- a site's API ----

extern "C" moonbit_string_t mb_host_view_site_next(int32_t vid) {
  View *v = find(vid);
  if (!v || v->kind < 2 || v->said.empty()) return moonbit_make_string_raw(0);
  std::wstring e = v->said.front();
  v->said.pop_front();
  return mstr(e);
}

extern "C" moonbit_bytes_t mb_host_view_site_body(int32_t vid, int32_t req) {
  View *v = find(vid);
  Req *q = NULL;
  if (v) {
    auto it = v->reqs.find(req);
    if (it != v->reqs.end()) q = it->second;
  }
  size_t n = q ? q->body.size() : 0;
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)n, 0);
  if (n) memcpy(out, q->body.data(), n);
  return out;
}

static Req *req_of(int32_t vid, int32_t req) {
  View *v = find(vid);
  if (!v) return NULL;
  auto it = v->reqs.find(req);
  return it == v->reqs.end() ? NULL : it->second;
}

extern "C" void mb_host_view_site_head(int32_t vid, int32_t req, int32_t status, moonbit_string_t headers) {
  Req *q = req_of(vid, req);
  if (!q || q->headed) return;
  q->headed = true;
  // a redirect or a status WebView2 does not take: as Android's, 200
  q->status = status >= 200 && status <= 599 && (status < 300 || status > 399) ? status : 200;
  q->headers.clear();
  for (auto &h : jpairs(wstr(headers))) {
    if (!q->headers.empty()) q->headers += L"\r\n";
    q->headers += h.first + L": " + h.second;
  }
}

extern "C" void mb_host_view_site_chunk(int32_t vid, int32_t req, moonbit_bytes_t data) {
  Req *q = req_of(vid, req);
  if (!q || !q->headed) return;
  int32_t n = Moonbit_array_length(data);
  q->data.insert(q->data.end(), data, data + n);
}

extern "C" void mb_host_view_site_end(int32_t vid, int32_t req, moonbit_string_t error) {
  View *v = find(vid);
  Req *q = req_of(vid, req);
  if (!v || !q) return;
  v->reqs.erase(req);
  finish(v, q, wstr(error));
}

extern "C" moonbit_string_t mb_host_view_site_state(int32_t vid) {
  View *v = find(vid);
  if (!v || v->kind != 3) return moonbit_make_string_raw(0);
  std::wstring path = v->start, title;
  BOOL back = FALSE, fwd = FALSE;
  if (v->web) {
    LPWSTR uri = NULL, t = NULL;
    if (SUCCEEDED(v->web->get_Source(&uri)) && uri && *uri) {
      std::wstring p = path_of(uri, kSite);
      path = p.empty() ? std::wstring(uri) : p;
    }
    if (SUCCEEDED(v->web->get_DocumentTitle(&t)) && t) title = t;
    CoTaskMemFree(uri);
    CoTaskMemFree(t);
    v->web->get_CanGoBack(&back);
    v->web->get_CanGoForward(&fwd);
  }
  std::wstring e = L"{\"path\":";
  jstr(e, path.c_str());
  e += L",\"back\":";
  e += back ? L"true" : L"false";
  e += L",\"forward\":";
  e += fwd ? L"true" : L"false";
  e += L",\"loading\":";
  e += v->loading ? L"true" : L"false";
  e += L",\"title\":";
  jstr(e, title.c_str());
  e += L'}';
  return mstr(e);
}

extern "C" void mb_host_view_site_load(int32_t vid, moonbit_string_t path) {
  View *v = find(vid);
  if (!v || v->kind != 3) return;
  std::wstring p = wstr(path);
  if (p.empty()) p = L"/";
  if (!v->web) {
    v->start = p;
    return;
  }
  std::wstring url = std::wstring(kSite) + p;
  v->web->Navigate(url.c_str());
}

// ---------------------------------------------------------------------------
// For the window (win_app.c) and the renderer (win_render.cpp)

extern "C" int mb_views_count(void) { return (int)views.size(); }

// the view shown at (x, y), points from the client area's top left, the last stacked first
static View *view_at(double x, double y) {
  for (auto it = views.rbegin(); it != views.rend(); ++it) {
    View *v = it->second;
    if (!v->shown || !v->placed || !v->comp || v->touch == "through") continue;
    double x0 = fmax(v->cx0, v->x), y0 = fmax(v->cy0, v->y);
    double x1 = fmin(v->cx1, v->x + v->w), y1 = fmin(v->cy1, v->y + v->h);
    if (x >= x0 && x < x1 && y >= y0 && y < y1) return v;
  }
  return NULL;
}

extern "C" int mb_views_pass_through(double x, double y) { return view_at(x, y) != NULL; }

// A mouse message of the window's, handed to the web view under it (or the one its button went down on): 1 when it
// took it (the app does not see it).
extern "C" int mb_views_input(unsigned msg, uintptr_t wp, intptr_t lp) {
  if (views.empty()) return 0;
  COREWEBVIEW2_MOUSE_EVENT_KIND kind;
  switch (msg) {
    case WM_MOUSEMOVE: kind = COREWEBVIEW2_MOUSE_EVENT_KIND_MOVE; break;
    case WM_LBUTTONDOWN: kind = COREWEBVIEW2_MOUSE_EVENT_KIND_LEFT_BUTTON_DOWN; break;
    case WM_LBUTTONUP: kind = COREWEBVIEW2_MOUSE_EVENT_KIND_LEFT_BUTTON_UP; break;
    case WM_LBUTTONDBLCLK: kind = COREWEBVIEW2_MOUSE_EVENT_KIND_LEFT_BUTTON_DOUBLE_CLICK; break;
    case WM_RBUTTONDOWN: kind = COREWEBVIEW2_MOUSE_EVENT_KIND_RIGHT_BUTTON_DOWN; break;
    case WM_RBUTTONUP: kind = COREWEBVIEW2_MOUSE_EVENT_KIND_RIGHT_BUTTON_UP; break;
    case WM_MBUTTONDOWN: kind = COREWEBVIEW2_MOUSE_EVENT_KIND_MIDDLE_BUTTON_DOWN; break;
    case WM_MBUTTONUP: kind = COREWEBVIEW2_MOUSE_EVENT_KIND_MIDDLE_BUTTON_UP; break;
    case WM_XBUTTONDOWN: kind = COREWEBVIEW2_MOUSE_EVENT_KIND_X_BUTTON_DOWN; break;
    case WM_XBUTTONUP: kind = COREWEBVIEW2_MOUSE_EVENT_KIND_X_BUTTON_UP; break;
    case WM_MOUSEWHEEL: kind = COREWEBVIEW2_MOUSE_EVENT_KIND_WHEEL; break;
    case WM_MOUSEHWHEEL: kind = COREWEBVIEW2_MOUSE_EVENT_KIND_HORIZONTAL_WHEEL; break;
    case WM_MOUSELEAVE: {
      View *h = find(hovered);
      hovered = 0;
      if (h && h->comp) h->comp->SendMouseInput(COREWEBVIEW2_MOUSE_EVENT_KIND_LEAVE, COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS_NONE, 0, POINT{0, 0});
      return 0;
    }
    default: return 0;
  }
  POINT p = {GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
  if (msg == WM_MOUSEWHEEL || msg == WM_MOUSEHWHEEL) ScreenToClient(hwnd_main, &p);
  double s = scale_now();
  View *v = captured ? find(captured) : view_at(p.x / s, p.y / s);
  if (hovered && (!v || v->vid != hovered)) {
    View *h = find(hovered);
    if (h && h->comp) h->comp->SendMouseInput(COREWEBVIEW2_MOUSE_EVENT_KIND_LEAVE, COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS_NONE, 0, POINT{0, 0});
    hovered = 0;
  }
  if (!v || !v->comp) return 0;
  // the wheel's upright scroll over a page that gives it to the canvas (a page in a list of messages)
  if (msg == WM_MOUSEWHEEL && v->touch == "vertical") return 0;
  hovered = v->vid;
  UINT32 data = 0;
  if (msg == WM_MOUSEWHEEL || msg == WM_MOUSEHWHEEL) data = (UINT32)(int32_t)GET_WHEEL_DELTA_WPARAM(wp);
  else if (msg == WM_XBUTTONDOWN || msg == WM_XBUTTONUP) data = GET_XBUTTON_WPARAM(wp);
  POINT q = {p.x - (LONG)lround(v->x * s), p.y - (LONG)lround(v->y * s)};
  v->comp->SendMouseInput(kind, (COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS)GET_KEYSTATE_WPARAM(wp), data, q);
  if (msg == WM_LBUTTONDOWN || msg == WM_RBUTTONDOWN || msg == WM_MBUTTONDOWN || msg == WM_XBUTTONDOWN) {
    // its keys: the page's until the canvas is clicked again
    if (!captured) SetCapture(hwnd_main);
    captured = v->vid;
    v->ctl->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
  } else if (captured && (msg == WM_LBUTTONUP || msg == WM_RBUTTONUP || msg == WM_MBUTTONUP || msg == WM_XBUTTONUP) &&
             !(GET_KEYSTATE_WPARAM(wp) & (MK_LBUTTON | MK_RBUTTON | MK_MBUTTON | MK_XBUTTON1 | MK_XBUTTON2))) {
    captured = 0;
    ReleaseCapture();
  }
  return 1;
}

// The pointer's shape over a web view (its page's), or NULL over the canvas.
extern "C" void *mb_views_cursor(double x, double y) {
  View *v = view_at(x, y);
  return v ? (void *)v->cursor : NULL;
}

// The window's scale changed: each web view drawn at it, placed again.
extern "C" void mb_views_rescale(void) {
  for (auto &kv : views) {
    View *v = kv.second;
    ComPtr<ICoreWebView2Controller3> c3;
    if (v->ctl && SUCCEEDED(v->ctl.As(&c3))) c3->put_RasterizationScale(scale_now());
    if (v->placed) apply_place(v);
  }
}

// What the app awaits of the views, told as it came (f: host_native.mbt's set_outside; NULL: dropped).
extern "C" void mb_views_tell(mb_outside_fn f) {
  while (!told.empty()) {
    std::pair<int, int> t = told.front();
    told.pop_front();
    if (f) f(MB_OUTSIDE_VIEW, t.first, t.second);
  }
  while (!grabs.empty()) {
    std::pair<int, int> t = grabs.front();
    grabs.pop_front();
    if (f) f(MB_OUTSIDE_GRAB, t.first, t.second);
  }
}

// Whether a view is still opening (neither loaded nor failed) or its picture is being taken: a scripted snapshot
// waits for it.
extern "C" int mb_views_busy(void) {
  for (auto &kv : views) {
    View *v = kv.second;
    if ((!v->loaded && !v->failed) || v->snapping) return 1;
  }
  return 0;
}

// A snapshot is about to be taken: every page loaded has its picture taken anew.
extern "C" void mb_views_snap_all(void) {
  for (auto &kv : views) refresh_snap(kv.second);
}

// The views' pictures (white where a page has none yet) into `out` (w × h premultiplied BGRA, zeroed), at their rects
// within their clips, as they are stacked.
extern "C" void mb_views_draw_under(uint8_t *out, int w, int h, double scale) {
  for (auto &kv : views) {
    View *v = kv.second;
    if (!v->shown || !v->placed || v->w <= 0 || v->h <= 0) continue;
    double rx = v->x * scale, ry = v->y * scale, rw = v->w * scale, rh = v->h * scale;
    int x0 = (int)lround(fmax(v->cx0, v->x) * scale), y0 = (int)lround(fmax(v->cy0, v->y) * scale);
    int x1 = (int)lround(fmin(v->cx1, v->x + v->w) * scale), y1 = (int)lround(fmin(v->cy1, v->y + v->h) * scale);
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > w) x1 = w;
    if (y1 > h) y1 = h;
    for (int y = y0; y < y1; y++) {
      uint8_t *d = out + ((size_t)y * w + x0) * 4;
      int sy = v->snap_h ? (int)((y + 0.5 - ry) / rh * v->snap_h) : 0;
      if (sy < 0) sy = 0;
      if (sy >= v->snap_h) sy = v->snap_h - 1;
      for (int x = x0; x < x1; x++, d += 4) {
        if (v->snap_w) {
          int sx = (int)((x + 0.5 - rx) / rw * v->snap_w);
          if (sx < 0) sx = 0;
          if (sx >= v->snap_w) sx = v->snap_w - 1;
          const uint8_t *s = &v->snap[((size_t)sy * v->snap_w + sx) * 4];
          // over white
          int k = 255 - s[3];
          d[0] = (uint8_t)(s[0] + k);
          d[1] = (uint8_t)(s[1] + k);
          d[2] = (uint8_t)(s[2] + k);
        } else {
          d[0] = d[1] = d[2] = 255;
        }
        d[3] = 255;
      }
    }
  }
}
