// The device beyond the window on Windows (src/host/device.mbt): a key catcher's keys, the clipboard read and written
// (words; a picture under the registered "PNG" format, as browsers and Office put it there: a bitmap alone is said
// unreadable, not converted), the display kept on. No soft keyboard's height (0), no haptics. Included by win_app.c
// before its keys (its hwnd, ime_active, marked_len, mods_now, outside_cb above).

void mb_host_clipboard_set(moonbit_string_t s);

// ---- a key catcher (@host.key_catch) ----

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

enum { CLIP_NONE = 0, CLIP_PNG = 1, CLIP_TOO_LARGE = 2, CLIP_UNREADABLE = 3 };
#define CLIP_READS 8
static struct {
  int32_t id;
  int told;
  int picture;
  WCHAR *text;
  int text_len;
  unsigned char *png;
  size_t png_len;
} clip_reads[CLIP_READS];
static int32_t clip_next = 1;

static int clip_slot(int32_t id) {
  for (int i = 0; i < CLIP_READS; i++)
    if (clip_reads[i].id == id && id) return i;
  return -1;
}

void mb_host_clip_end(int32_t id) {
  int i = clip_slot(id);
  if (i < 0) return;
  free(clip_reads[i].text);
  free(clip_reads[i].png);
  memset(&clip_reads[i], 0, sizeof clip_reads[i]);
}

// Read at once (the clipboard is the window thread's to open), told as the next frame begins (device_tell).
int32_t mb_host_clip_read(void) {
  int i = -1;
  for (int k = 0; k < CLIP_READS; k++)
    if (!clip_reads[k].id) { i = k; break; }
  if (i < 0) return 0;
  int32_t id = clip_next++;
  clip_reads[i].id = id;
  if (OpenClipboard(hwnd)) {
    HANDLE h = GetClipboardData(CF_UNICODETEXT);
    const WCHAR *w = h ? (const WCHAR *)GlobalLock(h) : NULL;
    if (w) {
      int n = (int)wcslen(w), k = 0;
      clip_reads[i].text = (WCHAR *)malloc(((size_t)n + 1) * sizeof(WCHAR));
      // CR LF as the app's LF
      for (int j = 0; j < n; j++)
        if (!(w[j] == '\r' && w[j + 1] == '\n')) clip_reads[i].text[k++] = w[j];
      clip_reads[i].text_len = k;
      GlobalUnlock(h);
    }
    UINT png_format = RegisterClipboardFormatW(L"PNG");
    HANDLE p = GetClipboardData(png_format);
    const unsigned char *b = p ? (const unsigned char *)GlobalLock(p) : NULL;
    if (b) {
      size_t n = GlobalSize(p);
      static const unsigned char sig[8] = {0x89, 'P', 'N', 'G', 13, 10, 26, 10};
      if (n < 8 || memcmp(b, sig, 8) != 0) {
        clip_reads[i].picture = CLIP_UNREADABLE;
      } else if (n > 8u * 1024 * 1024) {
        clip_reads[i].picture = CLIP_TOO_LARGE;
      } else {
        clip_reads[i].png = (unsigned char *)malloc(n);
        memcpy(clip_reads[i].png, b, n);
        clip_reads[i].png_len = n;
        clip_reads[i].picture = CLIP_PNG;
      }
      GlobalUnlock(p);
    } else if (IsClipboardFormatAvailable(CF_DIB) || IsClipboardFormatAvailable(CF_BITMAP)) {
      clip_reads[i].picture = CLIP_UNREADABLE;
    }
    CloseClipboard();
  }
  want_frame = 1;
  return id;
}

// The reads done since the last frame, told before it is drawn (draw_frame).
static void device_tell(mb_outside_fn tell) {
  for (int i = 0; i < CLIP_READS; i++) {
    if (clip_reads[i].id && !clip_reads[i].told) {
      clip_reads[i].told = 1;
      if (tell) tell(MB_OUTSIDE_CLIP, clip_reads[i].id, 1);
    }
  }
}

int32_t mb_host_clip_state(int32_t id) {
  int i = clip_slot(id);
  return i < 0 ? -1 : clip_reads[i].told ? 1 : 0;
}

int32_t mb_host_clip_picture(int32_t id) {
  int i = clip_slot(id);
  return i < 0 ? CLIP_NONE : clip_reads[i].picture;
}

moonbit_string_t mb_host_clip_text(int32_t id) {
  int i = clip_slot(id);
  int n = i < 0 ? 0 : clip_reads[i].text_len;
  moonbit_string_t s = moonbit_make_string_raw(n);
  if (n) memcpy(s, clip_reads[i].text, (size_t)n * sizeof(WCHAR));
  return s;
}

moonbit_bytes_t mb_host_clip_png(int32_t id) {
  int i = clip_slot(id);
  size_t n = i < 0 ? 0 : clip_reads[i].png_len;
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)n, 0);
  if (n) memcpy(b, clip_reads[i].png, n);
  return b;
}

// ---- the clipboard written: words (as @host.clipboard_set), or a PNG under "PNG" (no label on Windows) ----

void mb_host_clip_set(moonbit_string_t text, moonbit_bytes_t png, moonbit_string_t label) {
  (void)label;
  size_t n = (size_t)Moonbit_array_length(png);
  if (!n) {
    mb_host_clipboard_set(text);
    return;
  }
  HGLOBAL h = GlobalAlloc(GMEM_MOVEABLE, n);
  if (!h) return;
  memcpy(GlobalLock(h), png, n);
  GlobalUnlock(h);
  if (!OpenClipboard(hwnd)) {
    GlobalFree(h);
    return;
  }
  EmptyClipboard();
  if (!SetClipboardData(RegisterClipboardFormatW(L"PNG"), h)) GlobalFree(h);
  CloseClipboard();
}

// ---- the display kept on; no haptics ----

void mb_host_keep_awake(int32_t on) {
  SetThreadExecutionState(on ? (ES_CONTINUOUS | ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED) : ES_CONTINUOUS);
}

void mb_host_haptic(int32_t kind) { (void)kind; }

// An app's own native calls (src/host/native.mbt): none on this host yet.
int32_t mb_host_native_call(moonbit_string_t name, moonbit_string_t params) { return 0; }
int32_t mb_host_native_state(int32_t id) { return -1; }
moonbit_string_t mb_host_native_result(int32_t id) { return moonbit_make_string_raw(0); }
void mb_host_native_end(int32_t id) {}
