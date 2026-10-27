// The device beyond the window on Windows (src/hostapi/device.mbt): a key catcher's keys, the clipboard read (words, a
// picture, files: below) and written (words; a picture under the registered "PNG" format, as browsers and Office put
// it there), the display kept on. No soft keyboard's height (0), no haptics. Included by win_app.c before its keys
// (its hwnd, ime_active, marked_len, mods_now, outside_cb above), after win_files.h (files read whole).

void mb_host_clipboard_set(moonbit_string_t s);

// ---- a key catcher (@hostapi.key_catch) ----

static int key_catching;

void mb_host_key_catch(int32_t on) { key_catching = on != 0; }

// A key down with the focus a key catcher's: the named keys (as the framework's codes, src/ui/desktop.mbt), a
// character with Ctrl, Alt or the Windows key held as its key (1000 + it, lower case; Ctrl with Alt is AltGr, a
// character typed). 0: not the catcher's as a key (a character comes as WM_CHAR, Space too).
static int catch_vk(WPARAM vk) {
  int mods = mods_now(), code = 0;
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
    case VK_PRIOR: code = 15; break;
    case VK_NEXT: code = 16; break;
    case VK_ESCAPE: code = 17; break;
    case VK_TAB: code = 18; break;
    default: break;
  }
  if (!code && (mods & (2 | 4 | 8)) && (mods & (2 | 4)) != (2 | 4)) {
    UINT ch = MapVirtualKeyW((UINT)vk, MAPVK_VK_TO_CHAR) & 0x7FFF;
    if (ch >= 'A' && ch <= 'Z') ch += 'a' - 'A';
    if (ch >= 32) code = 1000 + (int)ch;
  }
  if (code) mb_cb.key(code, mods);
  return code;
}

// ---- the soft keyboard: none told here ----

double mb_host_ime_inset(void) { return 0; }

int32_t mb_host_copy_shown(void) { return 0; }

// ---- the clipboard read ----

// Its words, a picture (a PNG under "PNG", as browsers and Office put it there; else a bitmap, CF_DIB, made a PNG) and
// its files (Explorer's copied ones, CF_HDROP: each read whole, a folder left out, over 1 GB too): what is the
// clipboard's taken as it is read (it is the window thread's to open), then the bitmap made a PNG and the files read on
// a thread of their own, told as the next frame after begins (device_tell).
enum { CLIP_NONE = 0, CLIP_PNG = 1, CLIP_TOO_LARGE = 2, CLIP_UNREADABLE = 3 };
#define CLIP_READS 8
#define CLIP_PNG_MOST (8u * 1024 * 1024)
typedef struct {
  int32_t id;
  volatile LONG done;    // all of it read
  volatile LONG owners;  // who holds it (the window's slot, its thread): the last to let go frees it
  int told;
  int picture;
  WCHAR *text;
  int text_len;
  unsigned char *png;
  size_t png_len;
  unsigned char *dib;  // a bitmap's, to be made a PNG
  size_t dib_len;
  WCHAR **paths;  // its files', to be read
  int npaths;
  file_list files;
} clip_read;
static clip_read *clip_reads[CLIP_READS];
static int32_t clip_next = 1;

static void clip_let_go(clip_read *r) {
  if (InterlockedDecrement(&r->owners) != 0) return;
  free(r->text);
  free(r->png);
  free(r->dib);
  for (int i = 0; i < r->npaths; i++) free(r->paths[i]);
  free(r->paths);
  files_free(&r->files);
  free(r);
}

static clip_read *clip_of(int32_t id) {
  for (int i = 0; i < CLIP_READS; i++)
    if (clip_reads[i] && clip_reads[i]->id == id && id) return clip_reads[i];
  return NULL;
}

void mb_host_clip_end(int32_t id) {
  for (int i = 0; i < CLIP_READS; i++)
    if (clip_reads[i] && clip_reads[i]->id == id && id) {
      clip_read *r = clip_reads[i];
      clip_reads[i] = NULL;
      clip_let_go(r);
    }
}

// the bitmap made a PNG, the files read
static DWORD WINAPI clip_thread(void *arg) {
  clip_read *r = (clip_read *)arg;
  CoInitializeEx(NULL, COINIT_MULTITHREADED);
  if (r->dib) {
    unsigned char *png = NULL;
    size_t n = 0;
    if (!mb_png_of_dib(r->dib, r->dib_len, &png, &n)) {
      r->picture = CLIP_UNREADABLE;
    } else if (n > CLIP_PNG_MOST) {
      free(png);
      r->picture = CLIP_TOO_LARGE;
    } else {
      r->png = png;
      r->png_len = n;
      r->picture = CLIP_PNG;
    }
  }
  for (int i = 0; i < r->npaths; i++) {
    DWORD at = GetFileAttributesW(r->paths[i]);
    if (at != INVALID_FILE_ATTRIBUTES && !(at & FILE_ATTRIBUTE_DIRECTORY)) files_read(&r->files, r->paths[i], path_last(r->paths[i]));
  }
  CoUninitialize();
  InterlockedExchange(&r->done, 1);
  mb_app_wake();
  clip_let_go(r);
  return 0;
}

int32_t mb_host_clip_read(void) {
  int i = -1;
  for (int k = 0; k < CLIP_READS; k++)
    if (!clip_reads[k]) {
      i = k;
      break;
    }
  if (i < 0) return 0;
  clip_read *r = (clip_read *)calloc(1, sizeof *r);
  if (!r) return 0;
  r->id = clip_next++;
  r->owners = 1;
  clip_reads[i] = r;
  if (OpenClipboard(hwnd)) {
    HANDLE h = GetClipboardData(CF_UNICODETEXT);
    const WCHAR *w = h ? (const WCHAR *)GlobalLock(h) : NULL;
    if (w) {
      int n = (int)wcslen(w), k = 0;
      r->text = (WCHAR *)malloc(((size_t)n + 1) * sizeof(WCHAR));
      // CR LF as the app's LF
      for (int j = 0; r->text && j < n; j++)
        if (!(w[j] == '\r' && w[j + 1] == '\n')) r->text[k++] = w[j];
      r->text_len = r->text ? k : 0;
      GlobalUnlock(h);
    }
    // its files: their paths, read after (a folder left out there)
    HANDLE hd = GetClipboardData(CF_HDROP);
    HDROP drop = hd ? (HDROP)GlobalLock(hd) : NULL;
    if (drop) {
      UINT n = DragQueryFileW(drop, 0xFFFFFFFF, NULL, 0);
      r->paths = (WCHAR **)calloc(n ? n : 1, sizeof(WCHAR *));
      for (UINT k = 0; r->paths && k < n; k++) {
        UINT len = DragQueryFileW(drop, k, NULL, 0);
        WCHAR *p = (WCHAR *)calloc((size_t)len + 1, sizeof(WCHAR));
        if (p && DragQueryFileW(drop, k, p, len + 1)) r->paths[r->npaths++] = p;
        else free(p);
      }
      GlobalUnlock(hd);
    }
    // a picture, where there are no files (Explorer's copied picture files are the files, not their icon)
    UINT png_format = RegisterClipboardFormatW(L"PNG");
    HANDLE p = r->npaths ? NULL : GetClipboardData(png_format);
    const unsigned char *b = p ? (const unsigned char *)GlobalLock(p) : NULL;
    if (b) {
      size_t n = GlobalSize(p);
      static const unsigned char sig[8] = {0x89, 'P', 'N', 'G', 13, 10, 26, 10};
      if (n < 8 || memcmp(b, sig, 8) != 0) {
        r->picture = CLIP_UNREADABLE;
      } else if (n > CLIP_PNG_MOST) {
        r->picture = CLIP_TOO_LARGE;
      } else if ((r->png = (unsigned char *)malloc(n)) != NULL) {
        memcpy(r->png, b, n);
        r->png_len = n;
        r->picture = CLIP_PNG;
      }
      GlobalUnlock(p);
    } else if (!r->npaths) {
      // a bitmap (a screenshot's, Paint's): CF_DIB, which Windows makes of CF_DIBV5 and CF_BITMAP too
      HANDLE d = GetClipboardData(CF_DIB);
      const void *bits = d ? GlobalLock(d) : NULL;
      if (bits) {
        size_t n = GlobalSize(d);
        if ((r->dib = (unsigned char *)malloc(n ? n : 1)) != NULL) {
          memcpy(r->dib, bits, n);
          r->dib_len = n;
        }
        GlobalUnlock(d);
      }
    }
    CloseClipboard();
  }
  if (r->dib || r->npaths) {
    InterlockedIncrement(&r->owners);
    HANDLE t = CreateThread(NULL, 0, clip_thread, r, 0, NULL);
    if (t) {
      CloseHandle(t);
    } else {
      r->owners--;
      r->done = 1;
    }
  } else {
    r->done = 1;
  }
  want_frame = 1;
  return r->id;
}

// The reads done since the last frame, told before it is drawn (draw_frame).
static void device_tell(mb_outside_fn tell) {
  for (int i = 0; i < CLIP_READS; i++) {
    clip_read *r = clip_reads[i];
    if (r && !r->told && InterlockedCompareExchange(&r->done, 1, 1)) {
      r->told = 1;
      if (tell) tell(MB_OUTSIDE_CLIP, r->id, 1);
    }
  }
}

int32_t mb_host_clip_state(int32_t id) {
  clip_read *r = clip_of(id);
  return !r ? -1 : r->told ? 1 : 0;
}

int32_t mb_host_clip_picture(int32_t id) {
  clip_read *r = clip_of(id);
  return r && r->told ? r->picture : CLIP_NONE;
}

moonbit_string_t mb_host_clip_text(int32_t id) {
  clip_read *r = clip_of(id);
  int n = r && r->told ? r->text_len : 0;
  moonbit_string_t s = moonbit_make_string_raw(n);
  if (n) memcpy(s, r->text, (size_t)n * sizeof(WCHAR));
  return s;
}

moonbit_bytes_t mb_host_clip_png(int32_t id) {
  clip_read *r = clip_of(id);
  size_t n = r && r->told ? r->png_len : 0;
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)n, 0);
  if (n) memcpy(b, r->png, n);
  return b;
}

int32_t mb_host_clip_files(int32_t id) {
  clip_read *r = clip_of(id);
  return r && r->told ? r->files.n : 0;
}

moonbit_string_t mb_host_clip_file_name(int32_t id, int32_t i) {
  clip_read *r = clip_of(id);
  const WCHAR *s = r && r->told && i >= 0 && i < r->files.n ? r->files.names[i] : L"";
  int n = (int)wcslen(s);
  moonbit_string_t out = moonbit_make_string_raw(n);
  if (n) memcpy(out, s, (size_t)n * sizeof(WCHAR));
  return out;
}

moonbit_bytes_t mb_host_clip_file(int32_t id, int32_t i) {
  clip_read *r = clip_of(id);
  size_t n = r && r->told && i >= 0 && i < r->files.n ? r->files.lens[i] : 0;
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)n, 0);
  if (n) memcpy(b, r->files.datas[i], n);
  return b;
}

// ---- the clipboard written: words (as @hostapi.clipboard_set), or a picture (no label on Windows) ----

// A PNG on the clipboard, in place of what it held: under "PNG" (browsers, Office read it, its pixels as they are) and
// as a bitmap, CF_DIB (Windows makes CF_BITMAP and CF_DIBV5 of it): what Paint, chat apps and the clipboard's history
// (Win+V) take, none of which reads "PNG" (2026-10-27: 分享图片's 复制图片 put nothing they could paste). Either alone
// when the other cannot be made.
static void clipboard_png(const unsigned char *png, size_t n) {
  UINT f = RegisterClipboardFormatW(L"PNG");
  HGLOBAL h = f ? GlobalAlloc(GMEM_MOVEABLE, n) : NULL;
  if (h) {
    memcpy(GlobalLock(h), png, n);
    GlobalUnlock(h);
  }
  HGLOBAL dib = mb_dib_of_png(png, n);
  if (!h && !dib) return;
  if (!OpenClipboard(hwnd)) {
    if (h) GlobalFree(h);
    if (dib) GlobalFree(dib);
    return;
  }
  EmptyClipboard();
  if (h && !SetClipboardData(f, h)) GlobalFree(h);
  if (dib && !SetClipboardData(CF_DIB, dib)) GlobalFree(dib);
  CloseClipboard();
}

void mb_host_clip_set(moonbit_string_t text, moonbit_bytes_t png, moonbit_string_t label) {
  (void)label;
  size_t n = (size_t)Moonbit_array_length(png);
  if (!n) {
    mb_host_clipboard_set(text);
    return;
  }
  clipboard_png(png, n);
}

// ---- the display kept on; no haptics ----

void mb_host_keep_awake(int32_t on) {
  SetThreadExecutionState(on ? (ES_CONTINUOUS | ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED) : ES_CONTINUOUS);
}

void mb_host_haptic(int32_t kind) { (void)kind; }
void mb_host_ime_action(int32_t kind) { (void)kind; }

// An app's own native calls (src/hostapi/native.mbt): none on this host yet.
int32_t mb_host_native_call(moonbit_string_t name, moonbit_string_t params) { return 0; }
int32_t mb_host_native_state(int32_t id) { return -1; }
moonbit_string_t mb_host_native_result(int32_t id) { return moonbit_make_string_raw(0); }
void mb_host_native_end(int32_t id) {}
