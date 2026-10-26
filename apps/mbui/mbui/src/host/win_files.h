// Files from outside the app on Windows, as mac_app.m has them: picked through the system's own dialog (pick.mbt:
// IFileOpenDialog over the window, on a thread of its own, so the window goes on drawing behind it), and let go on the
// window from outside (ui/drop.mbt: the window an OLE drop target, Explorer's files as it holds them over it), each
// read whole on a thread of its own and told as the next frame begins (MB_OUTSIDE_PICK). A file over 1 GB, or one
// that cannot be read, is left out (as still.fail's composer refuses one so big). Folders let go come with their files,
// named by their way down from where they were dropped ("照片/2026/a.jpg"), each folder itself named with a "/" at its
// end and no bytes (so an empty one is made too); the system's hidden files of a folder (Thumbs.db, desktop.ini) left
// out, as the Mac leaves out .DS_Store. MBUI_PICK_FILES="<path>|<path>…" answers every ask with those files at once,
// no dialog (scripted runs). Included by win_app.c before win_device.h, whose clipboard reads read files with it (its
// hwnd, scale above).
#include <ole2.h>
#include <shobjidl.h>

#pragma comment(lib, "uuid.lib")

#define FILE_MOST (1ull << 30)

// ---- files read ----

typedef struct {
  int n, cap;
  WCHAR **names;
  unsigned char **datas;
  size_t *lens;
} file_list;

static void files_free(file_list *f) {
  for (int i = 0; i < f->n; i++) free(f->names[i]), free(f->datas[i]);
  free(f->names);
  free(f->datas);
  free(f->lens);
  memset(f, 0, sizeof *f);
}

static int files_push(file_list *f, const WCHAR *name, unsigned char *data, size_t len) {
  if (f->n == f->cap) {
    int cap = f->cap ? f->cap * 2 : 8;
    WCHAR **names = (WCHAR **)realloc(f->names, sizeof(WCHAR *) * (size_t)cap);
    if (names) f->names = names;
    unsigned char **datas = (unsigned char **)realloc(f->datas, sizeof(unsigned char *) * (size_t)cap);
    if (datas) f->datas = datas;
    size_t *lens = (size_t *)realloc(f->lens, sizeof(size_t) * (size_t)cap);
    if (lens) f->lens = lens;
    if (!names || !datas || !lens) return 0;
    f->cap = cap;
  }
  f->names[f->n] = _wcsdup(name);
  f->datas[f->n] = data;
  f->lens[f->n] = len;
  f->n++;
  return 1;
}

// the file at `path` read whole, as `name`: 0 where it cannot be (gone, unreadable, over FILE_MOST)
static int files_read(file_list *f, const WCHAR *path, const WCHAR *name) {
  HANDLE h = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING,
                         FILE_FLAG_SEQUENTIAL_SCAN, NULL);
  if (h == INVALID_HANDLE_VALUE) return 0;
  LARGE_INTEGER size;
  if (!GetFileSizeEx(h, &size) || (unsigned long long)size.QuadPart > FILE_MOST) {
    CloseHandle(h);
    return 0;
  }
  size_t n = (size_t)size.QuadPart, got = 0;
  unsigned char *b = (unsigned char *)malloc(n ? n : 1);
  while (b && got < n) {
    DWORD k = 0, ask = (DWORD)(n - got > (1u << 30) ? (1u << 30) : n - got);
    if (!ReadFile(h, b + got, ask, &k, NULL) || k == 0) break;
    got += k;
  }
  CloseHandle(h);
  if (!b || got != n) {
    free(b);
    return 0;
  }
  if (!files_push(f, name, b, n)) {
    free(b);
    return 0;
  }
  return 1;
}

// the last part of a path (its file's or folder's own name)
static const WCHAR *path_last(const WCHAR *path) {
  const WCHAR *a = wcsrchr(path, L'\\'), *b = wcsrchr(path, L'/');
  const WCHAR *at = a > b ? a : b;
  return at ? at + 1 : path;
}

// `path` let go: a file read whole; a folder as "name/" and everything in it by its way down ("name/sub/a.jpg")
static void files_dropped(file_list *f, const WCHAR *path, const WCHAR *name, int depth) {
  DWORD at = GetFileAttributesW(path);
  if (at == INVALID_FILE_ATTRIBUTES) return;
  if (!(at & FILE_ATTRIBUTE_DIRECTORY)) {
    files_read(f, path, name);
    return;
  }
  size_t nn = wcslen(name);
  WCHAR *dir = (WCHAR *)calloc(nn + 2, sizeof(WCHAR));
  if (!dir) return;
  wcscpy_s(dir, nn + 2, name);
  dir[nn] = L'/';
  files_push(f, dir, NULL, 0);
  free(dir);
  if (depth > 64) return;
  size_t pn = wcslen(path);
  WCHAR *glob = (WCHAR *)calloc(pn + 3, sizeof(WCHAR));
  if (!glob) return;
  _snwprintf(glob, pn + 3, L"%ls\\*", path);
  WIN32_FIND_DATAW e;
  HANDLE h = FindFirstFileExW(glob, FindExInfoBasic, &e, FindExSearchNameMatch, NULL, FIND_FIRST_EX_LARGE_FETCH);
  free(glob);
  if (h == INVALID_HANDLE_VALUE) return;
  do {
    if (!wcscmp(e.cFileName, L".") || !wcscmp(e.cFileName, L"..")) continue;
    // (the system's own, hidden: Thumbs.db, desktop.ini)
    if ((e.dwFileAttributes & FILE_ATTRIBUTE_HIDDEN) && (e.dwFileAttributes & FILE_ATTRIBUTE_SYSTEM)) continue;
    if (e.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) continue;  // (a link elsewhere: not walked into)
    size_t cn = wcslen(e.cFileName);
    WCHAR *child = (WCHAR *)calloc(pn + cn + 2, sizeof(WCHAR));
    WCHAR *child_name = (WCHAR *)calloc(nn + cn + 2, sizeof(WCHAR));
    if (child && child_name) {
      _snwprintf(child, pn + cn + 2, L"%ls\\%ls", path, e.cFileName);
      _snwprintf(child_name, nn + cn + 2, L"%ls/%ls", name, e.cFileName);
      files_dropped(f, child, child_name, depth + 1);
    }
    free(child);
    free(child_name);
  } while (FindNextFileW(h, &e));
  FindClose(h);
}

// ---- picks: the dialog's, the canned ones, and what was let go ----

#define PICK_MOST 32
typedef struct {
  int32_t id;
  volatile LONG done;  // 1 once read (by its thread)
  int told;            // told to the app (pick_tell)
  int state;           // 0 asking, 1 files, -1 none (called off, nothing readable)
  file_list files;
  // what its thread is to do: the dialog of `kind` (1 photos, 2 any files), or these paths (`folders`: walked into)
  int kind, folders;
  WCHAR **paths;
  int npaths;
} win_pick;
static win_pick picks[PICK_MOST];
static SRWLOCK picks_lock = SRWLOCK_INIT;
static int32_t pick_next = 1;

static win_pick *pick_of(int32_t id) {
  for (int i = 0; i < PICK_MOST; i++)
    if (picks[i].id == id && id) return &picks[i];
  return NULL;
}

// a slot for a new ask (the oldest one told and never taken let go first, as none is open past its answer): NULL
// where every one is under way
static win_pick *pick_new(void) {
  AcquireSRWLockExclusive(&picks_lock);
  win_pick *p = NULL;
  for (int i = 0; i < PICK_MOST && !p; i++)
    if (!picks[i].id) p = &picks[i];
  for (int i = 0; i < PICK_MOST && !p; i++)
    if (picks[i].told) {
      files_free(&picks[i].files);
      p = &picks[i];
    }
  if (p) {
    memset(p, 0, sizeof *p);
    p->id = pick_next++;
  }
  ReleaseSRWLockExclusive(&picks_lock);
  return p;
}

// its paths read (walked into where they were let go), then said done
static void pick_read(win_pick *p) {
  file_list f = {0};
  for (int i = 0; i < p->npaths; i++) {
    if (p->folders) files_dropped(&f, p->paths[i], path_last(p->paths[i]), 0);
    else files_read(&f, p->paths[i], path_last(p->paths[i]));
    free(p->paths[i]);
  }
  free(p->paths);
  p->paths = NULL;
  AcquireSRWLockExclusive(&picks_lock);
  p->files = f;
  p->state = f.n > 0 ? 1 : -1;
  ReleaseSRWLockExclusive(&picks_lock);
  InterlockedExchange(&p->done, 1);
  mb_app_wake();
}

static void pick_paths_add(win_pick *p, const WCHAR *path) {
  WCHAR **g = (WCHAR **)realloc(p->paths, sizeof(WCHAR *) * (size_t)(p->npaths + 1));
  if (!g) return;
  p->paths = g;
  p->paths[p->npaths++] = _wcsdup(path);
}

// the system's dialog over the window (its owner, which it keeps from taking input meanwhile), then what was chosen
static DWORD WINAPI pick_thread(void *arg) {
  win_pick *p = (win_pick *)arg;
  if (p->kind) {
    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    IFileOpenDialog *d = NULL;
    if (SUCCEEDED(CoCreateInstance(&CLSID_FileOpenDialog, NULL, CLSCTX_INPROC_SERVER, &IID_IFileOpenDialog, (void **)&d))) {
      FILEOPENDIALOGOPTIONS o = 0;
      d->lpVtbl->GetOptions(d, &o);
      d->lpVtbl->SetOptions(d, o | FOS_ALLOWMULTISELECT | FOS_FILEMUSTEXIST | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST);
      if (p->kind == 1) {
        // (the pictures' own kinds, said as their patterns: no words of the app's here)
        static const WCHAR kinds[] = L"*.png;*.jpg;*.jpeg;*.gif;*.webp;*.bmp;*.heic;*.heif;*.tif;*.tiff;*.avif";
        COMDLG_FILTERSPEC spec = {kinds, kinds};
        d->lpVtbl->SetFileTypes(d, 1, &spec);
      }
      if (SUCCEEDED(d->lpVtbl->Show(d, hwnd))) {
        IShellItemArray *items = NULL;
        DWORD n = 0;
        if (SUCCEEDED(d->lpVtbl->GetResults(d, &items)) && SUCCEEDED(items->lpVtbl->GetCount(items, &n))) {
          for (DWORD i = 0; i < n; i++) {
            IShellItem *it = NULL;
            PWSTR path = NULL;
            if (SUCCEEDED(items->lpVtbl->GetItemAt(items, i, &it)) &&
                SUCCEEDED(it->lpVtbl->GetDisplayName(it, SIGDN_FILESYSPATH, &path))) {
              pick_paths_add(p, path);
              CoTaskMemFree(path);
            }
            if (it) it->lpVtbl->Release(it);
          }
        }
        if (items) items->lpVtbl->Release(items);
      }
      d->lpVtbl->Release(d);
    }
    CoUninitialize();
  }
  pick_read(p);
  return 0;
}

static int32_t pick_begin(win_pick *p) {
  HANDLE t = CreateThread(NULL, 0, pick_thread, p, 0, NULL);
  if (!t) {
    pick_read(p);
    return p->id;
  }
  CloseHandle(t);
  return p->id;
}

int32_t mb_host_pick_start(int32_t kind) {
  kind &= 15;  // (16: a big file may be held: none is here, each read whole)
  if (kind != 1 && kind != 2) return 0;  // (no camera here)
  win_pick *p = pick_new();
  if (!p) return 0;
  const WCHAR *canned = _wgetenv(L"MBUI_PICK_FILES");
  if (canned && *canned) {
    WCHAR *all = _wcsdup(canned), *next = NULL;
    for (WCHAR *t = wcstok_s(all, L"|", &next); t; t = wcstok_s(NULL, L"|", &next)) pick_paths_add(p, t);
    free(all);
  } else {
    p->kind = kind;
  }
  return pick_begin(p);
}

// Files let go on the window: read as a pick's, folders walked into (the drop's message names it)
static int32_t drop_pick(WCHAR **paths, int n) {
  win_pick *p = pick_new();
  if (!p) return 0;
  p->folders = 1;
  for (int i = 0; i < n; i++) pick_paths_add(p, paths[i]);
  return pick_begin(p);
}

// the picks read since the last frame, told before it is drawn (draw_frame)
static void pick_tell(mb_outside_fn tell) {
  for (int i = 0; i < PICK_MOST; i++) {
    win_pick *p = &picks[i];
    if (!p->id || p->told || !InterlockedCompareExchange(&p->done, 1, 1)) continue;
    p->told = 1;
    if (tell) tell(MB_OUTSIDE_PICK, p->id, p->state);
  }
}

int32_t mb_host_pick_state(int32_t pid) {
  win_pick *p = pick_of(pid);
  return !p ? -1 : !p->told ? 0 : p->state;
}

int32_t mb_host_pick_count(int32_t pid) {
  win_pick *p = pick_of(pid);
  return p && p->told ? p->files.n : 0;
}

moonbit_string_t mb_host_pick_name(int32_t pid, int32_t i) {
  win_pick *p = pick_of(pid);
  const WCHAR *s = p && p->told && i >= 0 && i < p->files.n ? p->files.names[i] : L"";
  int n = (int)wcslen(s);
  moonbit_string_t out = moonbit_make_string_raw(n);
  if (n) memcpy(out, s, (size_t)n * sizeof(WCHAR));
  return out;
}

// every file read whole here (none held: pick.mbt's Picked.held)
moonbit_string_t mb_host_pick_info(int32_t pid, int32_t i) {
  (void)pid, (void)i;
  return moonbit_make_string_raw(0);
}

moonbit_bytes_t mb_host_pick_bytes(int32_t pid, int32_t i) {
  win_pick *p = pick_of(pid);
  size_t n = p && p->told && i >= 0 && i < p->files.n ? p->files.lens[i] : 0;
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)n, 0);
  if (n) memcpy(b, p->files.datas[i], n);
  return b;
}

void mb_host_pick_end(int32_t pid) {
  win_pick *p = pick_of(pid);
  if (!p || !p->told) return;
  AcquireSRWLockExclusive(&picks_lock);
  files_free(&p->files);
  memset(p, 0, sizeof *p);
  ReleaseSRWLockExclusive(&picks_lock);
}

// ---- let go on the window ----

// where it is held, posted on `mbui.drop` as it moves ({"type":"over","x","y"}, {"type":"left"}), then let go, its
// files read as a pick's ({"type":"drop","x","y","pick"})
static void drop_post(const char *json) { mb_post("mbui.drop", json, strlen(json), NULL, 0); }

static void drop_at(POINTL pt, double *x, double *y) {
  POINT p = {pt.x, pt.y};
  ScreenToClient(hwnd, &p);
  *x = p.x / scale;
  *y = p.y / scale;
}

static FORMATETC drop_files_format = {CF_HDROP, NULL, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
static int drop_has_files;

static HRESULT STDMETHODCALLTYPE dt_query(IDropTarget *t, REFIID riid, void **out) {
  if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IDropTarget)) {
    *out = t;
    return S_OK;
  }
  *out = NULL;
  return E_NOINTERFACE;
}
// (one for the window's life: nothing counted)
static ULONG STDMETHODCALLTYPE dt_ref(IDropTarget *t) {
  (void)t;
  return 1;
}

static void dt_over(POINTL pt, DWORD *effect) {
  *effect = drop_has_files ? DROPEFFECT_COPY : DROPEFFECT_NONE;
  if (!drop_has_files) return;
  double x, y;
  drop_at(pt, &x, &y);
  char b[96];
  snprintf(b, sizeof b, "{\"type\":\"over\",\"x\":%.1f,\"y\":%.1f}", x, y);
  drop_post(b);
}

static HRESULT STDMETHODCALLTYPE dt_enter(IDropTarget *t, IDataObject *data, DWORD keys, POINTL pt, DWORD *effect) {
  (void)t, (void)keys;
  drop_has_files = data && data->lpVtbl->QueryGetData(data, &drop_files_format) == S_OK;
  dt_over(pt, effect);
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE dt_move(IDropTarget *t, DWORD keys, POINTL pt, DWORD *effect) {
  (void)t, (void)keys;
  dt_over(pt, effect);
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE dt_leave(IDropTarget *t) {
  (void)t;
  if (drop_has_files) drop_post("{\"type\":\"left\"}");
  drop_has_files = 0;
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE dt_drop(IDropTarget *t, IDataObject *data, DWORD keys, POINTL pt, DWORD *effect) {
  (void)t, (void)keys;
  *effect = DROPEFFECT_NONE;
  STGMEDIUM m;
  int pid = 0;
  if (drop_has_files && data && data->lpVtbl->GetData(data, &drop_files_format, &m) == S_OK) {
    HDROP h = (HDROP)GlobalLock(m.hGlobal);
    UINT n = h ? DragQueryFileW(h, 0xFFFFFFFF, NULL, 0) : 0;
    WCHAR **paths = (WCHAR **)calloc(n ? n : 1, sizeof(WCHAR *));
    UINT got = 0;
    for (UINT i = 0; paths && i < n; i++) {
      UINT len = DragQueryFileW(h, i, NULL, 0);
      WCHAR *p = (WCHAR *)calloc((size_t)len + 1, sizeof(WCHAR));
      if (p && DragQueryFileW(h, i, p, len + 1)) paths[got++] = p;
      else free(p);
    }
    if (h) GlobalUnlock(m.hGlobal);
    ReleaseStgMedium(&m);
    if (got) pid = drop_pick(paths, (int)got);
    for (UINT i = 0; i < got; i++) free(paths[i]);
    free(paths);
  }
  drop_has_files = 0;
  if (!pid) {
    drop_post("{\"type\":\"left\"}");
    return S_OK;
  }
  double x, y;
  drop_at(pt, &x, &y);
  char b[128];
  snprintf(b, sizeof b, "{\"type\":\"drop\",\"x\":%.1f,\"y\":%.1f,\"pick\":%d}", x, y, pid);
  drop_post(b);
  *effect = DROPEFFECT_COPY;
  return S_OK;
}

static IDropTargetVtbl drop_vtbl = {dt_query, dt_ref, dt_ref, dt_enter, dt_move, dt_leave, dt_drop};
static IDropTarget drop_target = {&drop_vtbl};

// the window takes what is let go on it (OLE's: OleInitialize, before it)
static void files_start(void) { RegisterDragDrop(hwnd, &drop_target); }
