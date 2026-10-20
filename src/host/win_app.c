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
#include <shellapi.h>
#include <objbase.h>
#include <imm.h>
#include <psapi.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "win.h"
#include "post.h"
#include "done_watch.h"

#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "imm32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "shell32.lib")

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
// The window as the app asks for it (@host.window_setup), the pointer's shape (@host.set_cursor), whether the
// pointer's leaving is asked to be told (TrackMouseEvent), whether the right button is down
static double setup_w, setup_h, setup_min_w, setup_min_h;
static int cursor_kind, tracking_leave, right_down;
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


static mb_outside_fn outside_cb;  // who is told as what the host does for the app is done (mb_host_set_outside)
static void device_tell(mb_outside_fn tell);  // win_device.h: the clipboard's reads done

static void draw_frame(void) {
  RECT rc;
  GetClientRect(hwnd, &rc);
  want_frame = 0;
  mb_images_tell(outside_cb);
  mb_views_tell(outside_cb);
  device_tell(outside_cb);
  if (rc.right <= 0 || rc.bottom <= 0) return;  // minimized; WM_SIZE asks again
  double was = scale;
  scale = GetDpiForWindow(hwnd) / 96.0;
  if (scale != was) {
    ime_place();  // the candidate window is placed in pixels
    mb_views_rescale();
  }
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

// the device beyond the window (device.mbt): a key catcher's keys, the clipboard, awake
#include "win_device.h"

static void key_down(WPARAM vk) {
  // a key catcher's focus (win_device.h): its keys (a composition under way keeps them)
  if (key_catching && ime_active && marked_len == 0 && catch_vk(vk)) return;
  int mods = mods_now(), code = 0;
  if (mods & 2) {
    switch (vk) {
      case 'A': code = 12; break;
      case 'C': code = 13; break;
      case 'X': code = 14; break;
      case 'V': paste(); return;
    }
    // any other Ctrl key with a character: the app's shortcut (1000 + the character, lower case)
    if (!code) {
      UINT ch = MapVirtualKeyW((UINT)vk, MAPVK_VK_TO_CHAR) & 0x7FFF;
      if (ch >= 'A' && ch <= 'Z') ch += 'a' - 'A';
      if (ch >= 32) {
        mb_cb.key(1000 + (int)ch, mods);
        return;
      }
    }
  }
  switch (vk) {
    case VK_ESCAPE: code = 17; break;
    case VK_TAB: code = 18; break;
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
  if (code) {
    mb_cb.key(code, mods);
    return;
  }
  // a character with no field to take it (Space, a letter): the app's, as 1000 + it
  if (!ime_active) {
    UINT ch = MapVirtualKeyW((UINT)vk, MAPVK_VK_TO_CHAR) & 0x7FFF;
    if (ch >= 'A' && ch <= 'Z') ch += 'a' - 'A';
    if (ch >= 32) mb_cb.key(1000 + (int)ch, mods);
  }
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
  // control characters arrive as keys (Enter, Backspace) or shortcuts; with no field, characters are keys (key_down)
  if (c < 0x20 || c == 0x7F || !ime_active) return;
  send_text(0, &c, 1, 0, 0);
}

// ---- the window ----

static void pointer(int kind, LPARAM lp) {
  mb_cb.pointer(kind, GET_X_LPARAM(lp) / scale, GET_Y_LPARAM(lp) / scale, 0);
}

static void pointer_button(int kind, LPARAM lp, int button) {
  mb_cb.pointer(kind, GET_X_LPARAM(lp) / scale, GET_Y_LPARAM(lp) / scale, button);
}

static LPCWSTR cursor_name(int kind) {
  switch (kind) {
    case 1: return IDC_HAND;
    case 2: return IDC_IBEAM;
    case 3: return IDC_SIZEWE;
    case 4: return IDC_SIZENS;
    case 5: return IDC_SIZEALL;
    default: return IDC_ARROW;
  }
}

static void wheel(WPARAM wp, LPARAM lp, int horizontal) {
  POINT p = {GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
  ScreenToClient(hwnd, &p);
  UINT lines = 3;
  SystemParametersInfoW(SPI_GETWHEELSCROLLLINES, 0, &lines, 0);
  if (lines == WHEEL_PAGESCROLL) lines = 20;
  // a notch is WHEEL_DELTA; a line 100/3 points, as a browser scrolls (100 a notch of three lines), eased in by the
  // app (phase 4)
  double d = GET_WHEEL_DELTA_WPARAM(wp) / (double)WHEEL_DELTA * lines * (100.0 / 3.0);
  if (horizontal) mb_cb.wheel(p.x / scale, p.y / scale, d, 0, 4);
  else mb_cb.wheel(p.x / scale, p.y / scale, 0, -d, 4);
}

static LRESULT CALLBACK wndproc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
  // the mouse over a web view (win_views.cpp) is its page's
  if (((msg >= WM_MOUSEFIRST && msg <= WM_MOUSELAST) || msg == WM_MOUSELEAVE) && mb_views_input(msg, wp, lp)) {
    if (msg == WM_MOUSEMOVE && !tracking_leave) {
      TRACKMOUSEEVENT t = {sizeof t, TME_LEAVE, h, 0};
      tracking_leave = TrackMouseEvent(&t) ? 1 : 0;
    }
    return 0;
  }
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
    case WM_MOUSEMOVE:
      if (!tracking_leave) {
        TRACKMOUSEEVENT t = {sizeof t, TME_LEAVE, h, 0};
        tracking_leave = TrackMouseEvent(&t) ? 1 : 0;
      }
      pointer(1, lp);
      return 0;
    case WM_MOUSELEAVE:
      tracking_leave = 0;
      mb_cb.pointer(7, -1, -1, 0);
      return 0;
    case WM_RBUTTONDOWN: SetFocus(h); right_down = 1; pointer_button(0, lp, 2); return 0;
    case WM_RBUTTONUP:
      if (right_down) pointer_button(2, lp, 2);
      right_down = 0;
      return 0;
    case WM_CONTEXTMENU: return 0;
    case WM_SETCURSOR:
      if (LOWORD(lp) == HTCLIENT) {
        POINT p;
        GetCursorPos(&p);
        ScreenToClient(h, &p);
        HCURSOR page = (HCURSOR)mb_views_cursor(p.x / scale, p.y / scale);
        SetCursor(page ? page : LoadCursor(NULL, cursor_name(cursor_kind)));
        return TRUE;
      }
      break;
    case WM_GETMINMAXINFO: {
      // the least the app asked for (@host.window_setup), as a client area at the window's scale
      if (setup_min_w > 0 || setup_min_h > 0) {
        UINT dpi = GetDpiForWindow(h);
        double k = (dpi ? dpi : 96) / 96.0;
        RECT r = {0, 0, (LONG)lround(setup_min_w * k), (LONG)lround(setup_min_h * k)};
        AdjustWindowRectExForDpi(&r, WS_OVERLAPPEDWINDOW, FALSE, 0, dpi ? dpi : 96);
        MINMAXINFO *mm = (MINMAXINFO *)lp;
        mm->ptMinTrackSize.x = r.right - r.left;
        mm->ptMinTrackSize.y = r.bottom - r.top;
      }
      return 0;
    }
    case WM_LBUTTONUP: ReleaseCapture(); pointer(2, lp); return 0;
    case WM_MOUSEWHEEL: wheel(wp, lp, 0); return 0;
    case WM_MOUSEHWHEEL: wheel(wp, lp, 1); return 0;
    case WM_KEYDOWN: key_down(wp); return 0;
    case WM_SYSKEYDOWN:
      // Alt with a key: a key catcher's shortcut (win_device.h)
      if (key_catching && ime_active && catch_vk(wp)) return 0;
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
  // MBUI_SHOT_SCREEN=1: also what the screen shows (<name>-screen.png)
  const char *sc = getenv("MBUI_SHOT_SCREEN");
  if (sc && *sc == '1') {
    _snwprintf(p, 1024, L"%ls\\%hs-screen.png", shot_dir, name);
    p[1023] = 0;
    fprintf(stdout, "SHOT screen %s\n", mb_screen_snapshot(hwnd, p) ? "ok" : "failed");
  }
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
    // from the 30th frame, once the native views have opened (loaded or failed) and their pictures are taken anew;
    // 30 s at most
    static int snapped, done;
    static double since;
    if (step >= 30 && !done) {
      if (!since) since = mb_now_ms();
      int late = mb_now_ms() - since > 30000;
      if (late || !mb_views_busy()) {
        if (!snapped && mb_views_count() > 0 && !late) {
          mb_views_snap_all();
          snapped = 1;
        } else {
          if (late) fprintf(stdout, "shot: native views still busy after 30 s\n");
          shot(getenv("MBUI_SHOT_NAME") ? getenv("MBUI_SHOT_NAME") : "main");
          done = step;
        }
      }
    } else if (done && step > done) {
      exit(0);
    }
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
  // MBUI_WIN=<w>x<h>: the client area's size in points (a phone's, for the narrow layouts); else the app's own
  // (@host.window_setup); 900 x 720 by default
  double ww = setup_w > 0 ? setup_w : 900, wh = setup_h > 0 ? setup_h : 720;
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

// The time of day (host_native.mbt's wall_ms): FILETIME's 100 ns since 1601, from 1970 in ms.
double mb_host_wall_ms(void) {
  FILETIME ft;
  GetSystemTimeAsFileTime(&ft);
  ULARGE_INTEGER u;
  u.LowPart = ft.dwLowDateTime;
  u.HighPart = ft.dwHighDateTime;
  return (double)(u.QuadPart - 116444736000000000ULL) / 10000.0;
}

double mb_host_event_time(void) { return -1; }

int32_t mb_host_platform(void) { return 3; }

void mb_host_request_frame(void) { want_frame = 1; }

void mb_app_wake(void) { PostMessageW(hwnd, WM_APP, 0, 0); }

// A message posted from outside the frames (post.h), on whatever thread: the window's loop asked for a frame.
static void mb_post_wake(void) { mb_app_wake(); }

void *mb_app_hwnd(void) { return hwnd; }

double mb_app_scale(void) { return scale; }

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

// A secret on the clipboard (@host.clipboard_set_secret): as any words here (no sensitive mark, nothing cleared yet).
void mb_host_clipboard_secret(moonbit_string_t s, double clear_ms) {
  (void)clear_ms;
  mb_host_clipboard_set(s);
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

// The app over another app done (@host.over_done): it never is here.
void mb_host_over_done(int32_t open_app) { (void)open_app; }

// A page in a browser's tab over the app (@host.open_tab): the default browser, as open_url.
int32_t mb_host_open_url(moonbit_string_t s);
int32_t mb_host_open_tab(moonbit_string_t s) { return mb_host_open_url(s); }

// What holds the app up while it listens for a browser (@host.hold_words): nothing here, the app runs on.
void mb_host_hold_words(moonbit_string_t channel, moonbit_string_t title, moonbit_string_t body) {
  (void)channel;
  (void)title;
  (void)body;
}

// A URL handed to the system (@host.open_url): ShellExecute, the default browser or the app that takes it; only
// http, https and mailto (nothing ShellExecute would run as a program).
int32_t mb_host_open_url(moonbit_string_t s) {
  int n = Moonbit_array_length(s);
  WCHAR *w = (WCHAR *)malloc(((size_t)n + 1) * sizeof(WCHAR));
  memcpy(w, s, (size_t)n * sizeof(WCHAR));
  w[n] = 0;
  int ok = 0;
  if (_wcsnicmp(w, L"http://", 7) == 0 || _wcsnicmp(w, L"https://", 8) == 0 || _wcsnicmp(w, L"mailto:", 7) == 0) {
    mb_host_log(s);
    ok = (INT_PTR)ShellExecuteW(NULL, L"open", w, NULL, NULL, SW_SHOWNORMAL) > 32;
  }
  free(w);
  return ok;
}

// The word around an offset (@host.word_at): none from the host here yet (the app's own rule, words.mbt).
double mb_host_word_at(moonbit_string_t text, int32_t off) {
  (void)text; (void)off;
  return -1;
}

// Whether the run is on its own clock (host_native.mbt's own_clock): no run here is yet.
int32_t mb_host_own_clock(void) { return 0; }

int32_t mb_host_reduce_motion(void) {
  // the system's "show animations in Windows" off
  BOOL on = TRUE;
  SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &on, 0);
  return on ? 0 : 1;
}

// What the host did for the app is done (host_native.mbt's set_outside): kind 1 an image decoded (win_image.cpp), 2 a
// native view ready, failed, or waiting on the app (win_views.cpp); told as each frame begins: on this thread, between
// frames. No PDFs yet (pdf_page_load answers 0: nothing the app awaits).
int32_t mb_host_set_outside(mb_outside_fn f) {
  outside_cb = f;
  return 1;
}
// How many of the app's asks are not answered yet, and what they are, as the frame just built left it
// (host_native.mbt's frame_awaiting): nothing here waits on it yet.
void mb_host_frame_awaiting(int32_t awaiting, moonbit_string_t what) {
  (void)awaiting;
  (void)what;
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

// Sharing (@host.share, @host.shared_in): no share sheet here yet; nothing comes in.
int32_t mb_host_share(moonbit_string_t text, moonbit_string_t name, moonbit_string_t mime, moonbit_bytes_t data) {
  (void)text; (void)name; (void)mime; (void)data;
  return 0;
}
moonbit_string_t mb_host_shared_in(void) { return moonbit_make_string_raw(0); }
moonbit_bytes_t mb_host_shared_in_file(int32_t i) { (void)i; return moonbit_make_bytes(0, 0); }

// Updates (@host.app_version, update_install, update_state): this app does not update itself here.
int32_t mb_host_app_version(void) { return 0; }
// A package for the system's installer (@host.install_package): none here, said on the system channel (system.mbt):
// its name as UTF-8, escaped for JSON.
void mb_host_install_package(moonbit_string_t name, moonbit_bytes_t data) {
  (void)data;
  int n = Moonbit_array_length(name);
  int u = WideCharToMultiByte(CP_UTF8, 0, (LPCWCH)name, n, NULL, 0, NULL, NULL);
  char *utf8 = (char *)malloc((size_t)u + 1);
  WideCharToMultiByte(CP_UTF8, 0, (LPCWCH)name, n, utf8, u, NULL, NULL);
  char *out = (char *)malloc((size_t)u * 6 + 64);
  size_t o = (size_t)sprintf(out, "{\"install\":{\"name\":\"");
  for (int i = 0; i < u; i++) {
    unsigned char ch = (unsigned char)utf8[i];
    if (ch == '"' || ch == '\\') out[o++] = '\\', out[o++] = (char)ch;
    else if (ch < 0x20) o += (size_t)sprintf(out + o, "\\u%04x", ch);
    else out[o++] = (char)ch;
  }
  o += (size_t)sprintf(out + o, "\",\"error\":\"unsupported\"}}");
  mb_post("system", out, o, NULL, 0);
  free(out);
  free(utf8);
}

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

// Scripted runs' input given to the host (src/ui/drive.mbt): the window's picture saved (4), the window resized to
// "<w>x<h>" points (8), the runner's directory watched (9); the rest is sent to the app itself.
int32_t mb_host_drive(int32_t kind, moonbit_string_t text) {
  // the directory the run's runner says what it has done in, watched (done_watch.h)
  if (kind == 9) return mb_done_watch(text);
  int n = Moonbit_array_length(text);
  wchar_t w[1024];
  if (n > 1023) n = 1023;
  memcpy(w, text, (size_t)n * sizeof(wchar_t));
  w[n] = 0;
  if (kind == 4) {
    int ok = mb_render_snapshot(w);
    char u[2048];
    WideCharToMultiByte(CP_UTF8, 0, w, -1, u, sizeof u, NULL, NULL);
    fprintf(stdout, "SHOT %s %s\n", u, ok ? "ok" : "failed");
    fflush(stdout);
    return 1;
  }
  if (kind == 8) {
    double cw = 0, ch = 0;
    if (swscanf(w, L"%lfx%lf", &cw, &ch) != 2 || cw <= 0 || ch <= 0) return 0;
    UINT dpi = GetDpiForWindow(hwnd);
    RECT r = {0, 0, (LONG)lround(cw * scale), (LONG)lround(ch * scale)};
    AdjustWindowRectExForDpi(&r, WS_OVERLAPPEDWINDOW, FALSE, 0, dpi);
    SetWindowPos(hwnd, NULL, 0, 0, r.right - r.left, r.bottom - r.top, SWP_NOMOVE | SWP_NOZORDER);
    fprintf(stdout, "RESIZED %.0fx%.0f\n", cw, ch);
    fflush(stdout);
    want_frame = 1;
    return 1;
  }
  return 0;
}

// The window as the app wants it, asked before `run` (@host.window_setup). Windows keeps its own title bar here.
void mb_host_window_setup(double min_w, double min_h, double w, double h, int32_t inset) {
  (void)inset;
  setup_min_w = min_w;
  setup_min_h = min_h;
  setup_w = w;
  setup_h = h;
}

// The system's title bar holds the window's buttons: none in the app's top row.
int32_t mb_host_window_inset(void) { return 0; }

// The press under way moves the window (the app's top row), as the title bar's would.
void mb_host_window_drag(void) {
  ReleaseCapture();
  SendMessageW(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
}

// The pointer's shape (@host.set_cursor), shown at once where it is over the window.
void mb_host_set_cursor(int32_t kind) {
  cursor_kind = kind;
  POINT p;
  if (GetCursorPos(&p) && WindowFromPoint(p) == hwnd) SetCursor(LoadCursor(NULL, cursor_name(kind)));
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


// A sign-in in the browser that comes back here (host_native.mbt `browser_login`): win_browser_login.c.

// Files picked (pick.mbt): not on this host yet.
int32_t mb_host_pick_start(int32_t kind) { return 0; }
int32_t mb_host_pick_state(int32_t pid) { return -1; }
int32_t mb_host_pick_count(int32_t pid) { return 0; }
moonbit_string_t mb_host_pick_name(int32_t pid, int32_t i) { return moonbit_make_string_raw(0); }
moonbit_bytes_t mb_host_pick_bytes(int32_t pid, int32_t i) { return moonbit_make_bytes(0, 0); }
void mb_host_pick_end(int32_t pid) {}

// The gallery (gallery.mbt): none on this host; no photo of it picked.
int32_t mb_host_gallery_access(void) { return -1; }
void mb_host_gallery_ask(void) {}
int32_t mb_host_gallery_answers(void) { return 0; }
int32_t mb_host_gallery_read(void) { return 0; }
int32_t mb_host_gallery_read_state(int32_t id) { (void)id; return -1; }
moonbit_string_t mb_host_gallery_read_rows(int32_t id) { (void)id; return moonbit_make_string_raw(0); }
void mb_host_gallery_read_end(int32_t id) { (void)id; }
int32_t mb_host_pick_photo(moonbit_string_t src) { (void)src; return 0; }

// Native views over the canvas: win_views.cpp. PDFs (host_native.mbt): not on Windows yet; no PDF is drawn (pages -1),
// the app says it cannot show it. (Saving a file: at the end, with keep.mbt's.)
int32_t mb_host_pdf_open(moonbit_bytes_t data) { (void)data; return 0; }
int32_t mb_host_pdf_pages(int32_t doc) { (void)doc; return -1; }
void mb_host_pdf_page_size(int32_t doc, int32_t page, double *out) { (void)doc; (void)page; out[0] = out[1] = 0; }
int32_t mb_host_pdf_page_load(int32_t doc, int32_t page, int32_t max_px) { (void)doc; (void)page; (void)max_px; return 0; }
void mb_host_pdf_close(int32_t doc) { (void)doc; }
int32_t mb_host_save_file(moonbit_string_t name, moonbit_bytes_t data);  // below, with keep.mbt's

// ---------------------------------------------------------------------------
// Files kept (keep.mbt) and saved (save_file): into the Downloads known folder (MBUI_DOWNLOADS_DIR instead, for
// scripted runs), either way (no save dialog yet); a name taken gets " (2)", " (3)"… before its extension. Written at
// once, so each keep is answered as it starts.
#include <shlobj.h>
#include <knownfolders.h>
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "uuid.lib")

// where downloads go: MBUI_DOWNLOADS_DIR, else the Downloads known folder; made if it is not there
static int keep_dir(wchar_t *dir) {
  const wchar_t *over = _wgetenv(L"MBUI_DOWNLOADS_DIR");
  if (over && *over) {
    lstrcpynW(dir, over, MAX_PATH);
  } else {
    PWSTR p = NULL;
    if (FAILED(SHGetKnownFolderPath(&FOLDERID_Downloads, 0, NULL, &p))) return 0;
    lstrcpynW(dir, p, MAX_PATH);
    CoTaskMemFree(p);
  }
  CreateDirectoryW(dir, NULL);
  return 1;
}

// the app's name for a file made safe for a folder (no separators or reserved characters, never empty)
static void keep_safe(moonbit_string_t name, wchar_t *n) {
  int len = Moonbit_array_length(name), k = 0;
  for (int i = 0; i < len && k < 200; i++) {
    wchar_t ch = (wchar_t)name[i];
    n[k++] = (ch < 32 || wcschr(L"\\/:*?\"<>|", ch)) ? L'_' : ch;
  }
  n[k] = 0;
  if (k == 0 || !wcscmp(n, L".") || !wcscmp(n, L"..")) lstrcpynW(n, L"file", MAX_PATH);
}

// the i-th name tried in `dir` for `n`: n, then "base (2).ext"…
static void keep_name(const wchar_t *dir, const wchar_t *n, int i, wchar_t *out) {
  wchar_t base[MAX_PATH], ext[MAX_PATH] = {0};
  lstrcpynW(base, n, MAX_PATH);
  wchar_t *dot = wcsrchr(base, L'.');
  if (dot && dot != base) {
    lstrcpynW(ext, dot, MAX_PATH);
    *dot = 0;
  }
  if (i == 1) _snwprintf(out, MAX_PATH, L"%ls\\%ls", dir, n);
  else _snwprintf(out, MAX_PATH, L"%ls\\%ls (%d)%ls", dir, base, i, ext);
  out[MAX_PATH - 1] = 0;
}

static int keep_put(HANDLE f, const char *b, DWORD left) {
  DWORD put = 0;
  while (left > 0) {
    if (!WriteFile(f, b, left, &put, NULL)) return 0;
    b += put;
    left -= put;
  }
  return 1;
}

int32_t mb_host_save_file(moonbit_string_t name, moonbit_bytes_t data) {
  wchar_t dir[MAX_PATH], n[MAX_PATH], path[MAX_PATH];
  if (!keep_dir(dir)) return 0;
  keep_safe(name, n);
  for (int i = 1; i < 10000; i++) {
    keep_name(dir, n, i, path);
    HANDLE f = CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    if (f == INVALID_HANDLE_VALUE) {
      if (GetLastError() == ERROR_FILE_EXISTS) continue;
      return 0;
    }
    int ok = keep_put(f, (const char *)data, (DWORD)Moonbit_array_length(data));
    CloseHandle(f);
    if (!ok) DeleteFileW(path);
    return ok;
  }
  return 0;
}

// each keep: its state (0 keeping, 1 kept, -1 failed), its name, its part file in the temporary directory while its
// bytes come, where it went
typedef struct {
  int state;
  HANDLE part;
  wchar_t name[MAX_PATH], tmp[MAX_PATH], where[MAX_PATH];
} win_keep;
static win_keep *keeps;
static int nkeeps = 1;  // ids from 1

static win_keep *keep_of(int32_t id) { return id > 0 && id < nkeeps ? &keeps[id] : NULL; }

static void keep_fail(win_keep *k) {
  if (k->part != INVALID_HANDLE_VALUE) CloseHandle(k->part);
  k->part = INVALID_HANDLE_VALUE;
  DeleteFileW(k->tmp);
  k->state = -1;
}

int32_t mb_host_keep_begin(moonbit_string_t name, moonbit_string_t mime, int32_t way) {
  (void)mime;
  (void)way;
  win_keep *grown = realloc(keeps, sizeof(win_keep) * (nkeeps + 1));
  if (!grown) return 0;
  keeps = grown;
  int id = nkeeps++;
  win_keep *k = &keeps[id];
  memset(k, 0, sizeof *k);
  keep_safe(name, k->name);
  wchar_t t[MAX_PATH];
  GetTempPathW(MAX_PATH, t);
  _snwprintf(k->tmp, MAX_PATH, L"%lsmbui-keep-%lu-%d.part", t, (unsigned long)GetCurrentProcessId(), id);
  k->tmp[MAX_PATH - 1] = 0;
  k->part = CreateFileW(k->tmp, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_TEMPORARY, NULL);
  k->state = k->part == INVALID_HANDLE_VALUE ? -1 : 0;
  return id;
}

int32_t mb_host_keep_append(int32_t id, moonbit_bytes_t data) {
  win_keep *k = keep_of(id);
  if (!k || k->state != 0 || k->part == INVALID_HANDLE_VALUE) return 0;
  if (keep_put(k->part, (const char *)data, (DWORD)Moonbit_array_length(data))) return 1;
  keep_fail(k);
  return 0;
}

// finished: the part file moved into Downloads under a name not taken (a copy across volumes)
void mb_host_keep_finish(int32_t id) {
  win_keep *k = keep_of(id);
  if (!k || k->state != 0 || k->part == INVALID_HANDLE_VALUE) return;
  CloseHandle(k->part);
  k->part = INVALID_HANDLE_VALUE;
  wchar_t dir[MAX_PATH];
  if (keep_dir(dir)) {
    for (int i = 1; i < 10000; i++) {
      keep_name(dir, k->name, i, k->where);
      if (GetFileAttributesW(k->where) != INVALID_FILE_ATTRIBUTES) continue;
      if (MoveFileExW(k->tmp, k->where, MOVEFILE_COPY_ALLOWED)) {
        k->state = 1;
        want_frame = 1;
        return;
      }
      if (GetLastError() != ERROR_ALREADY_EXISTS && GetLastError() != ERROR_FILE_EXISTS) break;
    }
  }
  k->where[0] = 0;
  keep_fail(k);
  want_frame = 1;
}

int32_t mb_host_keep_state(int32_t id) {
  win_keep *k = keep_of(id);
  return k ? k->state : -1;
}

moonbit_string_t mb_host_keep_where(int32_t id) {
  win_keep *k = keep_of(id);
  if (!k || k->state != 1) return moonbit_make_string_raw(0);
  int n = (int)wcslen(k->where);
  moonbit_string_t s = moonbit_make_string_raw(n);
  memcpy(s, k->where, n * sizeof(uint16_t));
  return s;
}

void mb_host_keep_end(int32_t id) {
  win_keep *k = keep_of(id);
  if (k && k->state == 0) keep_fail(k);
  if (k) k->state = -1;
}

// Text in a legacy encoding (charset.mbt): Windows' code pages by IANA's names (those a reader meets), decoded by
// MultiByteToWideChar (a byte with no mapping: U+FFFD).
#include <wctype.h>
static UINT cs_page(moonbit_string_t charset) {
  static const struct { const wchar_t *name; UINT page; } pages[] = {
    {L"gb18030", 54936}, {L"gbk", 936}, {L"gb2312", 936}, {L"big5", 950}, {L"shift_jis", 932},
    {L"euc-kr", 949}, {L"windows-1252", 1252}, {L"iso-8859-1", 28591}, {L"utf-8", 65001},
  };
  int n = Moonbit_array_length(charset);
  wchar_t name[32];
  if (n <= 0 || n >= 32) return 0;
  for (int i = 0; i < n; i++) name[i] = (wchar_t)towlower((wint_t)charset[i]);
  name[n] = 0;
  for (size_t i = 0; i < sizeof pages / sizeof pages[0]; i++)
    if (!wcscmp(name, pages[i].name)) return pages[i].page;
  return 0;
}

int32_t mb_host_charset_known(moonbit_string_t charset) {
  UINT p = cs_page(charset);
  return p && IsValidCodePage(p) ? 1 : 0;
}

moonbit_string_t mb_host_charset_decode(moonbit_bytes_t data, moonbit_string_t charset) {
  UINT p = cs_page(charset);
  int len = Moonbit_array_length(data);
  if (!p || len == 0) return moonbit_make_string_raw(0);
  int n = MultiByteToWideChar(p, 0, (const char *)data, len, NULL, 0);
  if (n <= 0) return moonbit_make_string_raw(0);
  moonbit_string_t s = moonbit_make_string_raw(n);
  MultiByteToWideChar(p, 0, (const char *)data, len, (wchar_t *)s, n);
  return s;
}

// Marks drawn onto an image (marks.mbt): none on this host yet.
int32_t mb_host_marks_start(moonbit_bytes_t image, moonbit_string_t marks) { (void)image; (void)marks; return 0; }
int32_t mb_host_marks_state(int32_t id) { (void)id; return -1; }
moonbit_bytes_t mb_host_marks_png(int32_t id) { (void)id; return moonbit_make_bytes(0, 0); }
