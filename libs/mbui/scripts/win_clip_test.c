// The real clipboard reader, with the clipboard and worker's delivery supplied by this test. No user's clipboard
// opened and no clock or worker race: the test delivers the bitmap conversion before asking for its result.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <objbase.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(c) do { if (!(c)) { printf("failed at line %d: %s", __LINE__, #c); exit(1); } } while (0)
#define FILE_MOST (1ull << 30)
#define WM_MB_CAUGHT_KEY (WM_APP + 2)
typedef WCHAR *moonbit_string_t;
typedef unsigned char *moonbit_bytes_t;
typedef void (*mb_outside_fn)(int32_t, int32_t, int32_t);
enum { MB_OUTSIDE_CLIP = 9 };
static moonbit_string_t moonbit_make_string_raw(int n) { return (WCHAR *)calloc((size_t)n + 1, sizeof(WCHAR)); }
static moonbit_bytes_t moonbit_make_bytes(int32_t n, int v) { (void)v; return (unsigned char *)calloc(n ? n : 1, 1); }
#define Moonbit_array_length(b) 0
static HWND hwnd = (HWND)1;
static int ime_active, marked_len, want_frame;
static struct { void (*key)(int32_t, int32_t); } mb_cb;
typedef struct { int n; WCHAR **names; unsigned char **datas; size_t *lens; } file_list;
static void files_free(file_list *f) { (void)f; }
static int files_read(file_list *f, const WCHAR *p, const WCHAR *n) { (void)f; (void)p; (void)n; return 0; }
static const WCHAR *path_last(const WCHAR *p) { return p; }
static void mb_host_clipboard_set(moonbit_string_t s) { (void)s; }
static HGLOBAL mb_dib_of_png(const void *p, size_t n) { (void)p; (void)n; return NULL; }

static HGLOBAL input;
static UINT input_format;
static size_t input_size, encoded_size;
static LPTHREAD_START_ROUTINE worker;
static void *worker_arg;
static int opened, closed, wakes, told;
static int32_t told_id;
static BOOL test_open(HWND w) { CHECK(w == hwnd); opened++; return TRUE; }
static BOOL test_close(void) { closed++; return TRUE; }
static UINT test_format(LPCWSTR name) { CHECK(wcscmp(name, L"PNG") == 0); return 0xc001; }
static HANDLE test_data(UINT f) { return f == input_format ? input : NULL; }
static SIZE_T test_size(HGLOBAL h) { CHECK(h == input); return input_size; }
static HANDLE test_thread(LPSECURITY_ATTRIBUTES a, SIZE_T n, LPTHREAD_START_ROUTINE fn, LPVOID arg, DWORD flags, LPDWORD id) {
  (void)a; (void)n; (void)id; CHECK(!flags && !worker); worker = fn; worker_arg = arg; return (HANDLE)1;
}
static BOOL test_close_handle(HANDLE h) { CHECK(h == (HANDLE)1); return TRUE; }
static void mb_app_wake(void) { wakes++; }
// Conversion supplied at a named step: the reader must accept a screenshot's PNG past the old screen-sync bound.
static int mb_png_of_dib(const void *p, size_t n, unsigned char **png, size_t *len) {
  CHECK(p && n == input_size);
  *len = encoded_size;
  *png = (unsigned char *)calloc(encoded_size > FILE_MOST ? 1 : encoded_size, 1);
  CHECK(*png);
  return 1;
}
#define OpenClipboard test_open
#define CloseClipboard test_close
#define RegisterClipboardFormatW test_format
#define GetClipboardData test_data
#define GlobalSize test_size
#define CreateThread test_thread
#define CloseHandle test_close_handle
#include "win_device.h"

static void said(int32_t kind, int32_t id, int32_t state) {
  CHECK(kind == MB_OUTSIDE_CLIP && state == 1); told++; told_id = id;
}

static void read_picture(UINT format, size_t n, size_t converted, int expected) {
  input_format = format; input_size = n; encoded_size = converted;
  // An over-limit PNG is rejected from its size; it needs only the signature, not a gigabyte allocation.
  input = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, n > FILE_MOST ? 8 : n);
  CHECK(input);
  unsigned char sig[8] = {137, 'P', 'N', 'G', 13, 10, 26, 10};
  memcpy(GlobalLock(input), sig, sizeof sig); GlobalUnlock(input);
  opened = closed = wakes = told = 0; want_frame = 0;
  int32_t id = mb_host_clip_read();
  CHECK(id && opened == 1 && closed == 1 && want_frame && mb_host_clip_state(id) == 0);
  if (worker) {
    LPTHREAD_START_ROUTINE fn = worker; worker = NULL;
    CHECK(fn(worker_arg) == 0 && wakes == 1);
  }
  device_tell(said);
  CHECK(told == 1 && told_id == id && mb_host_clip_state(id) == 1 && mb_host_clip_picture(id) == expected);
  CHECK(clip_of(id)->png_len == (expected == CLIP_PNG ? (format == 0xc001 ? n : converted) : 0));
  device_tell(said); CHECK(told == 1);
  mb_host_clip_end(id); CHECK(!clip_of(id));
  GlobalFree(input);
}

int main(void) {
  read_picture(0xc001, 9u << 20, 0, CLIP_PNG);  // a PNG already encoded by the copying app
  read_picture(CF_DIB, 40, 11266689, CLIP_PNG);  // the reported 4K PixPin screenshot's converted size
  read_picture(0xc001, FILE_MOST + 1, 0, CLIP_TOO_LARGE);
  read_picture(CF_DIB, 40, FILE_MOST + 1, CLIP_TOO_LARGE);
  puts("clipboard: PNG and bitmap pictures over 8 MiB accepted; attachment bound retained");
  return 0;
}
