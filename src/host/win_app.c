// Windows host: a per-monitor DPI-aware Win32 window drawn with Direct3D 11,
// frames from a message loop that blocks while there is nothing to draw,
// input from window messages, and the input method through IMM32 (TSF input
// methods reach it through their IMM32 compatibility layer).
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00  // per-monitor DPI v2 (Windows 10 1703)
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <windowsx.h>
#include <objbase.h>
#include <imm.h>
#include <psapi.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "win.h"

#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "imm32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "advapi32.lib")

mb_callbacks mb_cb;

// Back (host_native.mbt `set_back`): a mouse's back button and Alt+Left, while the app takes it.
typedef void (*mb_back_fn)(int32_t, double, double, int32_t);
static mb_back_fn back_cb;
static int back_on;
static int go_back(void) {
  if (!back_cb || !back_on) return 0;
  back_cb(2, 0, 1, 0);
  return 1;
}

static HWND hwnd;
static int want_frame;
static double wake_at = -1;  // mb_now_ms() of the earliest wake_after, or -1
static double scale = 1;
static double frame_w, frame_h;  // the last frame's size in points
static int ime_active;
static double caret[4];  // x, y, w, h in points, from set_ime
static int marked_len;
static WCHAR high_surrogate;
static const char *script;
static const wchar_t *shot_dir;
static int frames_drawn;
static int sizing;  // inside the modal move/size loop, where our loop does not run

static double mb_now_ms(void) {
  static LARGE_INTEGER freq;
  LARGE_INTEGER t;
  if (!freq.QuadPart) QueryPerformanceFrequency(&freq);
  QueryPerformanceCounter(&t);
  return (double)t.QuadPart * 1000.0 / (double)freq.QuadPart;
}

static void send_text(int kind, const WCHAR *s, int n, int a, int b) {
  moonbit_string_t out = moonbit_make_string_raw(n);
  if (n) memcpy(out, s, (size_t)n * sizeof(WCHAR));
  mb_cb.text(kind, out, a, b);
}

static void run_script_step(int step);
static void ime_place(void);
double mb_host_mem_bytes(void);

static void draw_frame(void) {
  RECT rc;
  GetClientRect(hwnd, &rc);
  want_frame = 0;
  if (rc.right <= 0 || rc.bottom <= 0) return;  // minimized; WM_SIZE asks again
  double was = scale;
  scale = GetDpiForWindow(hwnd) / 96.0;
  if (scale != was) ime_place();  // the candidate window is placed in pixels
  frame_w = rc.right / scale;
  frame_h = rc.bottom / scale;
  mb_text_set_scale(scale);
  mb_render_set_size(rc.right, rc.bottom, frame_w, frame_h, scale);
  mb_cb.frame(frame_w, frame_h, scale, mb_now_ms());
  frames_drawn++;
  if (script) run_script_step(frames_drawn);
}

// ---- input method ----

static void ime_place(void) {
  if (!ime_active) return;
  int x = (int)lround(caret[0] * scale), y = (int)lround(caret[1] * scale);
  int b = (int)lround((caret[1] + caret[3]) * scale);
  SetCaretPos(x, y);  // some input methods follow the system caret
  HIMC imc = ImmGetContext(hwnd);
  if (!imc) return;
  COMPOSITIONFORM cf = {CFS_POINT, {x, y}, {0, 0, 0, 0}};
  ImmSetCompositionWindow(imc, &cf);
  CANDIDATEFORM cand = {0, CFS_EXCLUDE, {x, b}, {x, y, x + 1, b}};
  ImmSetCandidateWindow(imc, &cand);
  ImmReleaseContext(hwnd, imc);
}

static void ime_compose(const WCHAR *s, int n, int cursor) {
  marked_len = n;
  if (n == 0) send_text(1, L"", 0, 0, 0);
  else send_text(1, s, n, cursor, 0);
}

static void ime_commit(const WCHAR *s, int n) {
  marked_len = 0;
  send_text(0, s, n, 0, 0);
}

static WCHAR *ime_string(HIMC imc, DWORD which, int *n) {
  LONG bytes = ImmGetCompositionStringW(imc, which, NULL, 0);
  if (bytes <= 0) {
    *n = 0;
    return NULL;
  }
  WCHAR *s = (WCHAR *)malloc((size_t)bytes);
  ImmGetCompositionStringW(imc, which, s, (DWORD)bytes);
  *n = (int)(bytes / sizeof(WCHAR));
  return s;
}

static void ime_composition(LPARAM lp) {
  HIMC imc = ImmGetContext(hwnd);
  if (!imc) return;
  int n;
  if (lp & GCS_RESULTSTR) {
    WCHAR *s = ime_string(imc, GCS_RESULTSTR, &n);
    ime_commit(s, n);
    free(s);
  }
  if (lp & GCS_COMPSTR) {
    WCHAR *s = ime_string(imc, GCS_COMPSTR, &n);
    int cursor = (lp & GCS_CURSORPOS) ? (int)ImmGetCompositionStringW(imc, GCS_CURSORPOS, NULL, 0) : n;
    ime_compose(s, n, cursor < 0 || cursor > n ? n : cursor);
    free(s);
  } else if (!(lp & GCS_RESULTSTR) && marked_len) {
    ime_compose(NULL, 0, 0);  // composition cancelled
  }
  ImmReleaseContext(hwnd, imc);
  ime_place();
}

// ---- clipboard ----

static void paste(void) {
  if (!OpenClipboard(hwnd)) return;
  HANDLE h = GetClipboardData(CF_UNICODETEXT);
  const WCHAR *p = h ? (const WCHAR *)GlobalLock(h) : NULL;
  if (p) {
    size_t n = wcslen(p), k = 0;
    WCHAR *s = (WCHAR *)malloc((n + 1) * sizeof(WCHAR));
    for (size_t i = 0; i < n; i++)
      if (!(p[i] == '\r' && p[i + 1] == '\n')) s[k++] = p[i];
    GlobalUnlock(h);
    CloseClipboard();
    if (k) send_text(0, s, (int)k, 0, 0);
    free(s);
    return;
  }
  CloseClipboard();
}

// ---- keys ----

static int mods_now(void) {
  return (GetKeyState(VK_SHIFT) < 0 ? 1 : 0) | (GetKeyState(VK_CONTROL) < 0 ? 2 : 0) |
         (GetKeyState(VK_MENU) < 0 ? 4 : 0) |
         ((GetKeyState(VK_LWIN) < 0 || GetKeyState(VK_RWIN) < 0) ? 8 : 0);
}

static void key_down(WPARAM vk) {
  int mods = mods_now(), code = 0;
  if (mods & 2) {
    switch (vk) {
      case 'A': code = 12; break;
      case 'C': code = 13; break;
      case 'X': code = 14; break;
      case 'V': paste(); return;
    }
  }
  switch (vk) {
    case VK_BACK: code = 1; break;
    case VK_DELETE: code = 2; break;
    case VK_LEFT: code = 3; break;
    case VK_RIGHT: code = 4; break;
    case VK_UP: code = 5; break;
    case VK_DOWN: code = 6; break;
    case VK_RETURN: code = 7; break;
    case VK_HOME: code = 8; break;
    case VK_END: code = 9; break;
    // without a field to type in, these scroll the list under the pointer
    case VK_PRIOR: code = ime_active ? 0 : 15; break;
    case VK_NEXT: code = ime_active ? 0 : 16; break;
  }
  if (code) mb_cb.key(code, mods);
}

static void char_in(WCHAR c) {
  if (IS_HIGH_SURROGATE(c)) {
    high_surrogate = c;
    return;
  }
  if (IS_LOW_SURROGATE(c)) {
    WCHAR pair[2] = {high_surrogate, c};
    if (high_surrogate) send_text(0, pair, 2, 0, 0);
    high_surrogate = 0;
    return;
  }
  high_surrogate = 0;
  // control characters arrive as keys (Enter, Backspace) or shortcuts
  if (c < 0x20 || c == 0x7F) return;
  send_text(0, &c, 1, 0, 0);
}

// ---- the window ----

static void pointer(int kind, LPARAM lp) {
  mb_cb.pointer(kind, GET_X_LPARAM(lp) / scale, GET_Y_LPARAM(lp) / scale, 0);
}

static void wheel(WPARAM wp, LPARAM lp, int horizontal) {
  POINT p = {GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
  ScreenToClient(hwnd, &p);
  UINT lines = 3;
  SystemParametersInfoW(SPI_GETWHEELSCROLLLINES, 0, &lines, 0);
  if (lines == WHEEL_PAGESCROLL) lines = 20;
  // a notch is WHEEL_DELTA; a line is about 16 points
  double d = GET_WHEEL_DELTA_WPARAM(wp) / (double)WHEEL_DELTA * lines * 16.0;
  if (horizontal) mb_cb.wheel(p.x / scale, p.y / scale, d, 0, 0);
  else mb_cb.wheel(p.x / scale, p.y / scale, 0, -d, 0);
}

static LRESULT CALLBACK wndproc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
  switch (msg) {
    case WM_PAINT: {
      PAINTSTRUCT ps;
      BeginPaint(h, &ps);
      EndPaint(h, &ps);
      want_frame = 1;
      return 0;
    }
    case WM_ERASEBKGND: return 1;
    case WM_APP: want_frame = 1; return 0;  // mb_app_wake
    case WM_SIZE:
      want_frame = 1;
      if (sizing) draw_frame();
      return 0;
    case WM_ENTERSIZEMOVE: sizing = 1; SetTimer(h, 1, 16, NULL); return 0;
    case WM_EXITSIZEMOVE: sizing = 0; KillTimer(h, 1); return 0;
    case WM_TIMER:
      if (wake_at >= 0 && mb_now_ms() >= wake_at) {
        wake_at = -1;
        want_frame = 1;
      }
      if (want_frame) draw_frame();
      return 0;
    case WM_DPICHANGED: {
      RECT *r = (RECT *)lp;
      SetWindowPos(h, NULL, r->left, r->top, r->right - r->left, r->bottom - r->top,
                   SWP_NOZORDER | SWP_NOACTIVATE);
      want_frame = 1;
      return 0;
    }
    case WM_LBUTTONDOWN: SetCapture(h); SetFocus(h); pointer(0, lp); return 0;
    case WM_MOUSEMOVE: pointer(1, lp); return 0;
    case WM_LBUTTONUP: ReleaseCapture(); pointer(2, lp); return 0;
    case WM_MOUSEWHEEL: wheel(wp, lp, 0); return 0;
    case WM_MOUSEHWHEEL: wheel(wp, lp, 1); return 0;
    case WM_KEYDOWN: key_down(wp); return 0;
    case WM_SYSKEYDOWN:
      if (wp == VK_LEFT && go_back()) return 0;
      break;
    case WM_XBUTTONUP:
      if (GET_XBUTTON_WPARAM(wp) == XBUTTON1) go_back();
      return TRUE;
    case WM_CHAR: char_in((WCHAR)wp); return 0;
    case WM_SETFOCUS:
      if (ime_active) {
        CreateCaret(h, NULL, 1, (int)lround(caret[3] * scale));
        ime_place();
      }
      return 0;
    case WM_KILLFOCUS: DestroyCaret(); return 0;
    case WM_IME_SETCONTEXT:
      // we draw the composition ourselves; the system draws the candidates
      lp &= ~(LPARAM)ISC_SHOWUICOMPOSITIONWINDOW;
      break;
    case WM_IME_STARTCOMPOSITION: ime_place(); return 0;
    case WM_IME_COMPOSITION: ime_composition(lp); return 0;
    case WM_IME_ENDCOMPOSITION:
      if (marked_len) ime_compose(NULL, 0, 0);
      return 0;
    case WM_DESTROY: exit(0);
  }
  return DefWindowProcW(h, msg, wp, lp);
}

// ---------------------------------------------------------------------------
// Scripted runs (MBUI_SCRIPT=ime|shot): drive the same paths an input method
// takes and save snapshots, as the macOS host does.

static void shot(const char *name) {
  if (!shot_dir) return;
  wchar_t p[1024];
  _snwprintf(p, 1024, L"%ls\\%hs.png", shot_dir, name);
  p[1023] = 0;
  int ok = mb_render_snapshot(p);
  char u[2048];
  WideCharToMultiByte(CP_UTF8, 0, p, -1, u, sizeof u, NULL, NULL);
  fprintf(stdout, "SHOT %s %s\n", u, ok ? "ok" : "failed");
  fflush(stdout);
}

static void run_script_step(int step) {
  double h = frame_h;
  if (strcmp(script, "ime") == 0) {
    switch (step) {
      case 20: shot("01-start"); break;
      case 21:  // click the composer
        mb_cb.pointer(0, 120, h - 30, 0);
        mb_cb.pointer(2, 120, h - 30, 0);
        break;
      case 30: ime_compose(L"ni'hao", 6, 6); break;
      case 40: shot("02-composing"); break;
      case 41: ime_commit(L"\x4f60\x597d", 2); break;  // 你好
      case 42: ime_commit(L"\xff0cMoonBit ", 9); break;  // ，MoonBit
      case 43: ime_compose(L"shi'jie", 7, 3); break;
      case 50: shot("03-composing-2"); break;
      case 51: ime_commit(L"\x4e16\x754c \xd83d\xdc4b", 5); break;  // 世界 👋
      case 60: shot("04-typed"); break;
      case 61: mb_cb.key(7, 0); break;
      case 100: shot("05-sent"); break;
      case 101:
        for (int i = 0; i < 40; i++) mb_cb.wheel(300, 300, 0, -120, 0);
        break;
      case 140: shot("06-scrolled"); break;
      case 141: exit(0);
    }
    want_frame = 1;
  } else if (strcmp(script, "photos") == 0) {
    // decodes take a while: a shot once they have had some, then the keys
    // that scroll the list under the pointer, as a keyboard sends them
    static int phase;
    static double at;
    double now = mb_now_ms();
    if (!at) at = now;
    if (now - at > 4000) {
      at = now;
      char name[16];
      snprintf(name, sizeof name, "photos-%d", phase + 1);
      shot(name);
      fprintf(stdout, "memory at %s: %.1f MB\n", name, mb_host_mem_bytes() / 1048576.0);
      fflush(stdout);
      mb_cb.pointer(1, 300, 300, 0);
      if (phase == 0) for (int i = 0; i < 3; i++) SendMessageW(hwnd, WM_KEYDOWN, VK_NEXT, 0);
      if (phase == 1) SendMessageW(hwnd, WM_KEYDOWN, VK_END, 0);
      if (phase == 2) exit(0);
      phase++;
    }
    want_frame = 1;
  } else if (strcmp(script, "shot") == 0) {
    if (step == 30) shot(getenv("MBUI_SHOT_NAME") ? getenv("MBUI_SHOT_NAME") : "main");
    if (step == 31) exit(0);
    want_frame = 1;
  }
}

// ---------------------------------------------------------------------------
// The host API MoonBit calls

void mb_host_run(moonbit_string_t title, mb_frame_fn frame, mb_pointer_fn pointer_fn,
                 mb_wheel_fn wheel_fn, mb_key_fn key, mb_text_fn text) {
  mb_cb = (mb_callbacks){frame, pointer_fn, wheel_fn, key, text};
  script = getenv("MBUI_SCRIPT");
  shot_dir = _wgetenv(L"MBUI_SHOT_DIR");
  SetConsoleOutputCP(CP_UTF8);
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);

  WNDCLASSEXW wc = {sizeof wc};
  wc.lpfnWndProc = wndproc;
  wc.hInstance = GetModuleHandleW(NULL);
  wc.hCursor = LoadCursor(NULL, IDC_ARROW);
  wc.hIcon = LoadIcon(NULL, IDI_APPLICATION);
  wc.lpszClassName = L"mbui";
  RegisterClassExW(&wc);
  int n = Moonbit_array_length(title);
  WCHAR *t = (WCHAR *)calloc((size_t)n + 1, sizeof(WCHAR));
  memcpy(t, title, (size_t)n * sizeof(WCHAR));
  DWORD style = WS_OVERLAPPEDWINDOW;
  // MBUI_WIN=<w>x<h>: the client area's size in points (a phone's, for the narrow layouts); 900 x 720 by default
  double ww = 900, wh = 720;
  const char *win = getenv("MBUI_WIN");
  if (win) sscanf(win, "%lfx%lf", &ww, &wh);
  hwnd = CreateWindowExW(0, L"mbui", t, style, CW_USEDEFAULT, CW_USEDEFAULT, (int)ww, (int)wh, NULL, NULL,
                         wc.hInstance, NULL);
  free(t);
  // that client area at the monitor's scale
  UINT dpi = GetDpiForWindow(hwnd);
  scale = dpi / 96.0;
  RECT r = {0, 0, (LONG)lround(ww * scale), (LONG)lround(wh * scale)};
  AdjustWindowRectExForDpi(&r, style, FALSE, 0, dpi);
  SetWindowPos(hwnd, NULL, 0, 0, r.right - r.left, r.bottom - r.top, SWP_NOMOVE | SWP_NOZORDER);
  ImmAssociateContextEx(hwnd, NULL, 0);  // no input method until an editor has focus
  if (!mb_render_init(hwnd)) exit(1);
  ShowWindow(hwnd, SW_SHOW);
  want_frame = 1;

  for (;;) {
    MSG m;
    while (PeekMessageW(&m, NULL, 0, 0, PM_REMOVE)) {
      if (m.message == WM_QUIT) exit(0);
      TranslateMessage(&m);
      DispatchMessageW(&m);
    }
    double now = mb_now_ms();
    if (wake_at >= 0 && now >= wake_at) {
      wake_at = -1;
      want_frame = 1;
    }
    if (want_frame) {
      draw_frame();  // Present waits for vsync
      continue;
    }
    DWORD timeout = wake_at < 0 ? INFINITE : (DWORD)ceil(wake_at - now);
    MsgWaitForMultipleObjectsEx(0, NULL, timeout, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
  }
}

double mb_host_now(void) { return mb_now_ms(); }

double mb_host_event_time(void) { return -1; }

int32_t mb_host_platform(void) { return 3; }

void mb_host_request_frame(void) { want_frame = 1; }

void mb_app_wake(void) { PostMessageW(hwnd, WM_APP, 0, 0); }

void mb_host_wake_after(double ms) {
  double t = mb_now_ms() + ms;
  if (wake_at < 0 || t < wake_at) wake_at = t;
}

void mb_host_present(double *buf, int32_t count, double r, double g, double b) {
  mb_render_present(buf, count, r, g, b);
}

void mb_host_set_ime(int32_t active, double x, double y, double w, double h, moonbit_string_t text,
                     int32_t a, int32_t b) {
  int was = ime_active;
  ime_active = active != 0;
  caret[0] = x;
  caret[1] = y;
  caret[2] = w;
  caret[3] = h;
  if (ime_active && !was) {
    ImmAssociateContextEx(hwnd, NULL, IACE_DEFAULT);
    if (GetFocus() == hwnd) CreateCaret(hwnd, NULL, 1, (int)lround(h * scale));
  } else if (!ime_active && was) {
    HIMC imc = ImmGetContext(hwnd);
    if (imc) {
      ImmNotifyIME(imc, NI_COMPOSITIONSTR, CPS_CANCEL, 0);
      ImmReleaseContext(hwnd, imc);
    }
    ImmAssociateContextEx(hwnd, NULL, 0);
    DestroyCaret();
    marked_len = 0;
  }
  ime_place();
}

void mb_host_clipboard_set(moonbit_string_t s) {
  int n = Moonbit_array_length(s), k = 0;
  // other Windows programs expect CR LF
  HGLOBAL h = GlobalAlloc(GMEM_MOVEABLE, ((size_t)n * 2 + 1) * sizeof(WCHAR));
  if (!h) return;
  WCHAR *p = (WCHAR *)GlobalLock(h);
  for (int i = 0; i < n; i++) {
    if (s[i] == '\n' && (i == 0 || s[i - 1] != '\r')) p[k++] = '\r';
    p[k++] = s[i];
  }
  p[k] = 0;
  GlobalUnlock(h);
  if (!OpenClipboard(hwnd)) {
    GlobalFree(h);
    return;
  }
  EmptyClipboard();
  if (!SetClipboardData(CF_UNICODETEXT, h)) GlobalFree(h);
  CloseClipboard();
}

void mb_host_log(moonbit_string_t s) {
  int n = Moonbit_array_length(s);
  int bytes = WideCharToMultiByte(CP_UTF8, 0, (const WCHAR *)s, n, NULL, 0, NULL, NULL);
  char *u = (char *)malloc((size_t)bytes + 1);
  WideCharToMultiByte(CP_UTF8, 0, (const WCHAR *)s, n, u, bytes, NULL, NULL);
  u[bytes] = 0;
  fprintf(stdout, "%s\n", u);
  fflush(stdout);
  free(u);
}

int32_t mb_host_reduce_motion(void) {
  // the system's "show animations in Windows" off
  BOOL on = TRUE;
  SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &on, 0);
  return on ? 0 : 1;
}

int32_t mb_host_bench_mode(void) {
  const char *b = getenv("MBUI_BENCH");
  return b ? atoi(b) : 0;
}

void mb_host_exit(int32_t code) { exit(code); }

void mb_host_set_back(mb_back_fn f) { back_cb = f; }
void mb_host_back_enabled(int32_t on) { back_on = on; }

// The app in front or not (@host.set_app_state): not told here yet (the app counts itself shown and in front).
void mb_host_set_app_state(void (*f)(int32_t)) { (void)f; }

// Whether the system is set to dark (@host.system_dark): not read here yet (light).
int32_t mb_host_system_dark(void) { return 0; }

// Updates (@host.app_version, update_install, update_state): this app does not update itself here.
int32_t mb_host_app_version(void) { return 0; }
void mb_host_update_install(moonbit_string_t url, moonbit_string_t sha256, double size, moonbit_string_t name) {
  (void)url; (void)sha256; (void)size; (void)name;
}
moonbit_string_t mb_host_update_state(void) { return moonbit_make_string_raw(0); }

// Turned sideways for a film (@host.set_sideways): a window does not turn.
void mb_host_set_sideways(int32_t on) { (void)on; }

// The app drawn dark (@host.set_dark): nothing of the host's own follows it here yet.
void mb_host_set_dark(int32_t dark) { (void)dark; }

// Notifications (notify.mbt): none shown here yet (the toast notifications and WNS are a later slice's): nothing kept, nothing tapped, no push; what the
// system allows unknown.
void mb_host_notice_show(moonbit_string_t channel, moonbit_string_t tag, moonbit_string_t title, moonbit_string_t body,
                         moonbit_string_t opens) {
  (void)channel;
  (void)tag;
  (void)title;
  (void)body;
  (void)opens;
}

void mb_host_notice_cancel(moonbit_string_t tag) { (void)tag; }

int32_t mb_host_notice_state(int32_t what) { return what == 2 ? -1 : 0; }

moonbit_string_t mb_host_notice_text(int32_t what) {
  (void)what;
  return moonbit_make_string_raw(0);
}

// Scripted runs' input given to the host (src/ui/drive.mbt): none of its paths here yet (the app is sent it itself).
int32_t mb_host_drive(int32_t kind, moonbit_string_t text) {
  (void)kind;
  (void)text;
  return 0;
}

moonbit_string_t mb_host_env(moonbit_string_t name) {
  int n = Moonbit_array_length(name);
  WCHAR *k = (WCHAR *)calloc((size_t)n + 1, sizeof(WCHAR));
  memcpy(k, name, (size_t)n * sizeof(WCHAR));
  const WCHAR *v = _wgetenv(k);
  free(k);
  int len = v ? (int)wcslen(v) : 0;
  moonbit_string_t out = moonbit_make_string_raw(len);
  if (len) memcpy(out, v, (size_t)len * sizeof(WCHAR));
  return out;
}

// Windows' transparency effects (Settings > Personalization > Colors) turned off: glass drawn solid.
int32_t mb_host_reduce_transparency(void) {
  DWORD v = 1, n = sizeof v;
  if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                   L"EnableTransparency", RRF_RT_REG_DWORD, NULL, &v, &n) != ERROR_SUCCESS)
    return 0;
  return v == 0;
}

double mb_host_mem_bytes(void) {
  PROCESS_MEMORY_COUNTERS_EX pmc = {sizeof pmc};
  if (!K32GetProcessMemoryInfo(GetCurrentProcess(), (PROCESS_MEMORY_COUNTERS *)&pmc, sizeof pmc)) return 0;
  return (double)pmc.PrivateUsage;
}


// A sign-in in the browser that comes back here (host_native.mbt `browser_login`): not on this host yet.
int32_t mb_host_browser_login_start(moonbit_string_t path) { return 0; }
int32_t mb_host_browser_login_port(int32_t id) { return 0; }
int32_t mb_host_browser_login_open(int32_t id, moonbit_string_t url) { return 0; }
moonbit_string_t mb_host_browser_login_back(int32_t id) { return moonbit_make_string_raw(0); }
void mb_host_browser_login_end(int32_t id) {}

// Files picked (pick.mbt): not on this host yet.
int32_t mb_host_pick_start(int32_t kind) { return 0; }
int32_t mb_host_pick_state(int32_t pid) { return -1; }
int32_t mb_host_pick_count(int32_t pid) { return 0; }
moonbit_string_t mb_host_pick_name(int32_t pid, int32_t i) { return moonbit_make_string_raw(0); }
moonbit_bytes_t mb_host_pick_bytes(int32_t pid, int32_t i) { return moonbit_make_bytes(0, 0); }
void mb_host_pick_end(int32_t pid) {}

// Native views over the canvas, PDFs, saving a file (host_native.mbt): not on Windows yet. No view opens (0), no PDF
// is drawn (pages -1), nothing is saved; the app says it cannot show those here.
int32_t mb_host_view_open(int32_t kind, moonbit_string_t arg) { (void)kind; (void)arg; return 0; }
void mb_host_view_place(int32_t id, double x, double y, double w, double h, double cx0, double cy0, double cx1,
                        double cy1, int32_t shown) {
  (void)id; (void)x; (void)y; (void)w; (void)h; (void)cx0; (void)cy0; (void)cx1; (void)cy1; (void)shown;
}
void mb_host_view_close(int32_t id) { (void)id; }
void mb_host_view_control(int32_t id, int32_t op, double value) { (void)id; (void)op; (void)value; }
int32_t mb_host_view_info(int32_t id, double *out) {
  (void)id;
  for (int i = 0; i < 10; i++) out[i] = 0;
  return -1;
}
int32_t mb_host_view_read_next(int32_t id, double *out) { (void)id; (void)out; return 0; }
moonbit_string_t mb_host_view_site_next(int32_t id) { (void)id; return moonbit_make_string_raw(0); }
moonbit_bytes_t mb_host_view_site_body(int32_t id, int32_t req) { (void)id; (void)req; return moonbit_make_bytes(0, 0); }
void mb_host_view_site_head(int32_t id, int32_t req, int32_t status, moonbit_string_t headers) {
  (void)id; (void)req; (void)status; (void)headers;
}
void mb_host_view_site_chunk(int32_t id, int32_t req, moonbit_bytes_t data) { (void)id; (void)req; (void)data; }
void mb_host_view_site_end(int32_t id, int32_t req, moonbit_string_t error) { (void)id; (void)req; (void)error; }
moonbit_string_t mb_host_view_site_state(int32_t id) { (void)id; return moonbit_make_string_raw(0); }
void mb_host_view_site_load(int32_t id, moonbit_string_t path) { (void)id; (void)path; }
void mb_host_view_read_answer(int32_t id, int32_t req, moonbit_bytes_t data, double total) {
  (void)id; (void)req; (void)data; (void)total;
}
int32_t mb_host_pdf_open(moonbit_bytes_t data) { (void)data; return 0; }
int32_t mb_host_pdf_pages(int32_t doc) { (void)doc; return -1; }
void mb_host_pdf_page_size(int32_t doc, int32_t page, double *out) { (void)doc; (void)page; out[0] = out[1] = 0; }
int32_t mb_host_pdf_page_load(int32_t doc, int32_t page, int32_t max_px) { (void)doc; (void)page; (void)max_px; return 0; }
void mb_host_pdf_close(int32_t doc) { (void)doc; }
int32_t mb_host_save_file(moonbit_string_t name, moonbit_bytes_t data) { (void)name; (void)data; return 0; }
