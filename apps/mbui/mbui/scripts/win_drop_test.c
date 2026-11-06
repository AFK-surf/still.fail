// Exercise the Windows host's actual OLE drop and clipboard readers with movable CF_HDROP memory. This drives the
// drop target directly; it is not an Explorer drag. The clipboard owner is simulated so this test leaves the runner's
// clipboard alone and can release its data immediately when the host closes it.
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <ole2.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include "win.h"

static HWND hwnd;
static double scale = 1;
static int want_frame;
static HANDLE wake_event;
mb_callbacks mb_cb;
static int mods_now(void) { return 0; }
void mb_app_wake(void) { assert(SetEvent(wake_event)); }

// These MoonBit allocations are used only by the result getters in this native test.
moonbit_string_t moonbit_make_string_raw(int32_t n) { return (moonbit_string_t)calloc((size_t)n + 1, sizeof(uint16_t)); }
moonbit_bytes_t moonbit_make_bytes(int32_t n, int value) {
  moonbit_bytes_t b = (moonbit_bytes_t)malloc((size_t)n + 1);
  assert(b);
  memset(b, value, (size_t)n + 1);
  return b;
}
int mb_png_of_dib(const void *dib, size_t n, unsigned char **png, size_t *len) {
  (void)dib; (void)n; (void)png; (void)len;
  return 0;
}
HGLOBAL mb_dib_of_png(const void *png, size_t n) { (void)png; (void)n; return NULL; }
void mb_host_clipboard_set(moonbit_string_t text) { (void)text; }

static int overs, drops, leaves, drop_id;
void mb_post(const char *channel, const char *json, size_t len, const uint8_t *bytes, size_t blen) {
  assert(!strcmp(channel, "mbui.drop") && len == strlen(json) && !bytes && !blen);
  if (strstr(json, "\"type\":\"over\"")) overs++;
  if (strstr(json, "\"type\":\"left\"")) leaves++;
  if (strstr(json, "\"type\":\"drop\"")) {
    const char *p = strstr(json, "\"pick\":");
    assert(p);
    drop_id = atoi(p + strlen("\"pick\":"));
    drops++;
  }
}

// The handle and the address obtained by locking it are different for this fixture. In addition to calling Windows'
// DragQueryFileW, check its argument: some Windows versions happen to accept the locked address, masking this error.
static HGLOBAL expected_drop;
static int queried, released;
static UINT checked_drag_query(HDROP h, UINT index, LPWSTR out, UINT length) {
  assert(expected_drop && (HGLOBAL)h == expected_drop);
  queried++;
  return DragQueryFileW(h, index, out, length);
}
static void checked_release(STGMEDIUM *medium) {
  assert(medium->tymed == TYMED_HGLOBAL && medium->hGlobal == expected_drop && queried);
  expected_drop = NULL;
  ReleaseStgMedium(medium);
  released++;
}
#define DragQueryFileW checked_drag_query
#define ReleaseStgMedium checked_release
#include "win_files.h"
#undef ReleaseStgMedium

static HGLOBAL clipboard_drop;
static int clipboard_open, clipboard_closed;
static BOOL test_open_clipboard(HWND window) {
  assert(window == hwnd && !clipboard_open && clipboard_drop);
  clipboard_open = 1;
  expected_drop = clipboard_drop;
  return TRUE;
}
static HANDLE test_get_clipboard_data(UINT format) {
  assert(clipboard_open);
  return format == CF_HDROP ? clipboard_drop : NULL;
}
static BOOL test_close_clipboard(void) {
  assert(clipboard_open && clipboard_drop == expected_drop && queried);
  clipboard_open = 0;
  expected_drop = NULL;
  assert(GlobalFree(clipboard_drop) == NULL);
  clipboard_drop = NULL;
  clipboard_closed++;
  return TRUE;
}
#define OpenClipboard test_open_clipboard
#define GetClipboardData test_get_clipboard_data
#define CloseClipboard test_close_clipboard
#include "win_device.h"
#undef OpenClipboard
#undef GetClipboardData
#undef CloseClipboard
#undef DragQueryFileW

static WCHAR paths[2][MAX_PATH];
static const WCHAR *names[] = {L"file-\x6587\x4ef6.txt", L"\x03b1-\x00e9.txt"};
static const char *contents[] = {"first file", "second file"};

// Return a real movable HGLOBAL containing a wide DROPFILES list with both paths and its extra final NUL.
static HGLOBAL make_drop(void) {
  size_t chars = 1;
  for (int i = 0; i < 2; i++) chars += wcslen(paths[i]) + 1;
  HGLOBAL h = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, sizeof(DROPFILES) + chars * sizeof(WCHAR));
  assert(h);
  DROPFILES *d = (DROPFILES *)GlobalLock(h);
  assert(d && (HGLOBAL)d != h);
  d->pFiles = sizeof(DROPFILES);
  d->fWide = TRUE;
  WCHAR *p = (WCHAR *)((unsigned char *)d + d->pFiles);
  for (int i = 0; i < 2; i++) {
    size_t n = wcslen(paths[i]) + 1;
    memcpy(p, paths[i], n * sizeof(WCHAR));
    p += n;
  }
  assert(*p == 0);
  GlobalUnlock(h);
  return h;
}

static HRESULT STDMETHODCALLTYPE data_query(IDataObject *data, REFIID iid, void **out) {
  (void)data; (void)iid;
  *out = NULL;
  return E_NOINTERFACE;
}
static ULONG STDMETHODCALLTYPE data_ref(IDataObject *data) { (void)data; return 1; }
static HRESULT STDMETHODCALLTYPE data_get(IDataObject *data, FORMATETC *format, STGMEDIUM *medium) {
  (void)data;
  assert(format->cfFormat == CF_HDROP && (format->tymed & TYMED_HGLOBAL));
  memset(medium, 0, sizeof *medium);
  medium->tymed = TYMED_HGLOBAL;
  expected_drop = medium->hGlobal = make_drop();
  return S_OK;
}
static HRESULT STDMETHODCALLTYPE data_can_get(IDataObject *data, FORMATETC *format) {
  (void)data;
  return format->cfFormat == CF_HDROP && (format->tymed & TYMED_HGLOBAL) ? S_OK : DV_E_FORMATETC;
}
static IDataObjectVtbl data_vtbl = {data_query, data_ref, data_ref, data_get, NULL, data_can_get,
                                   NULL, NULL, NULL, NULL, NULL, NULL};
static IDataObject data_object = {&data_vtbl};

static int told_pick, told_clip;
static void told(int32_t kind, int32_t id, int32_t state) {
  assert(state == 1);
  if (kind == MB_OUTSIDE_PICK) { assert(id == drop_id); told_pick++; }
  else if (kind == MB_OUTSIDE_CLIP) { assert(id > 0); told_clip++; }
  else assert(0);
}
static void await_read(void) { assert(WaitForSingleObject(wake_event, 30000) == WAIT_OBJECT_0); }

static void check_files(int32_t id, int clipboard) {
  assert((clipboard ? mb_host_clip_files(id) : mb_host_pick_count(id)) == 2);
  for (int i = 0; i < 2; i++) {
    moonbit_string_t name = clipboard ? mb_host_clip_file_name(id, i) : mb_host_pick_name(id, i);
    moonbit_bytes_t bytes = clipboard ? mb_host_clip_file(id, i) : mb_host_pick_bytes(id, i);
    assert(name && bytes && !wcscmp((WCHAR *)name, names[i]));
    size_t actual = clipboard ? clip_of(id)->files.lens[i] : pick_of(id)->files.lens[i];
    assert(actual == strlen(contents[i]));
    assert(!memcmp(bytes, contents[i], actual));
    free(name);
    free(bytes);
  }
}

int main(void) {
  WCHAR temp[MAX_PATH], dir[MAX_PATH];
  assert(GetTempPathW(MAX_PATH, temp));
  assert(GetTempFileNameW(temp, L"mbd", 0, dir));
  assert(DeleteFileW(dir) && CreateDirectoryW(dir, NULL));
  for (int i = 0; i < 2; i++) {
    assert(_snwprintf(paths[i], MAX_PATH, L"%ls\\%ls", dir, names[i]) > 0);
    HANDLE file = CreateFileW(paths[i], GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    assert(file != INVALID_HANDLE_VALUE);
    DWORD written = 0, n = (DWORD)strlen(contents[i]);
    assert(WriteFile(file, contents[i], n, &written, NULL) && written == n && CloseHandle(file));
  }
  wake_event = CreateEventW(NULL, FALSE, FALSE, NULL);
  assert(wake_event && SUCCEEDED(OleInitialize(NULL)));
  WNDCLASSW cls = {0};
  cls.lpfnWndProc = DefWindowProcW;
  cls.hInstance = GetModuleHandleW(NULL);
  cls.lpszClassName = L"mbui-drop-test";
  assert(RegisterClassW(&cls));
  hwnd = CreateWindowW(cls.lpszClassName, L"", 0, 0, 0, 1, 1, NULL, NULL, cls.hInstance, NULL);
  assert(hwnd);
  files_start();
  assert(SUCCEEDED(RevokeDragDrop(hwnd)));

  // A complete drop uses the same methods OLE calls; all paths outlive ReleaseStgMedium and are read asynchronously.
  POINTL point = {0, 0};
  DWORD effect = DROPEFFECT_COPY;
  assert(dt_enter(&drop_target, &data_object, 0, point, &effect) == S_OK && effect == DROPEFFECT_COPY);
  assert(dt_drop(&drop_target, &data_object, 0, point, &effect) == S_OK && effect == DROPEFFECT_COPY);
  assert(overs == 1 && drops == 1 && leaves == 0 && drop_id > 0 && released == 1 && !expected_drop);
  await_read();
  pick_tell(told);
  pick_tell(told);
  assert(told_pick == 1 && mb_host_pick_state(drop_id) == 1);
  check_files(drop_id, 0);
  mb_host_pick_end(drop_id);

  // The clipboard owner frees its HGLOBAL on CloseClipboard, before the background reader opens the files.
  queried = 0;
  clipboard_drop = make_drop();
  int32_t clip_id = mb_host_clip_read();
  assert(clip_id > 0 && clipboard_closed == 1 && !clipboard_open && !clipboard_drop && !expected_drop);
  await_read();
  device_tell(told);
  device_tell(told);
  assert(told_clip == 1 && mb_host_clip_state(clip_id) == 1);
  check_files(clip_id, 1);
  mb_host_clip_end(clip_id);

  assert(DestroyWindow(hwnd));
  OleUninitialize();
  assert(CloseHandle(wake_event));
  for (int i = 0; i < 2; i++) assert(DeleteFileW(paths[i]));
  assert(RemoveDirectoryW(dir));
  puts("Windows movable CF_HDROP: drop and clipboard paths copied and read once");
  return 0;
}
