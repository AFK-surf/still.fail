// Updates on Windows (@hostapi.app_version, update_fetch, update_apply, update_state), as mac_app.m's "Updates": the app keeping
// itself current, as still.fail's desktop app did (electron-updater's NsisUpdater). A newer build the core found
// (`app.update`, its signature checked there: the release's installer, its sha256 and size the signed ones) downloaded
// into the app's own folder (%LOCALAPPDATA%\<its id>\updates), picking up where a cut connection left off (the bytes so
// far kept in `<name>.part`, the rest asked for as a range, a few times over with a growing pause while each try gets
// further), checked against its size and SHA-256, then run as the desktop app's updater ran its installer (`--updated
// /S --force-run`: still.fail's windows/setup.c, which ends this app, puts the new one in its place and opens it) as
// this one quits. How it goes the app reads (`update_state`: the phase, how far, what went wrong), told each time it
// changes (MB_OUTSIDE_UPDATE, id 1: 0 while the host works at it, -1 failed). Only a program with a version of its own
// (its resources' FILEVERSION 0.1.<n>: an app's, still.fail's scripts/win.sh) updates; a bare one (0) never asks.
// Where the core says a delta from this build (update_fetch's `delta`), that is tried first: downloaded as the installer
// would be (`<name>.delta`), applied to the installed folder's files (update_delta.h) into the release's raw installer
// (`<name less .exe>.raw.exe`: the same program, what it carries stored, not LZMS's), checked against the size and
// SHA-256 the signed words say for it, and run in the installer's place. Anything wrong with it is said on the log and
// the installer downloaded whole as ever. The made installer, kept until another build is asked for, is taken again by
// a later start; the delta goes once it is applied.
// Included by win_app.c after win_life.h (its app_id, and mini_json.h's jparse).
#include <stdarg.h>
#include <shlobj.h>
#include <knownfolders.h>
#include <winhttp.h>
#include <bcrypt.h>
#include "update_delta.h"

#pragma comment(lib, "winhttp.lib")
#pragma comment(lib, "bcrypt.lib")
#pragma comment(lib, "version.lib")

enum { MB_OUTSIDE_UPDATE = 7 };

int32_t mb_host_app_version(void) {
  static int version = -1;
  if (version >= 0) return version;
  version = 0;
  if (!*app_id()) return 0;
  WCHAR self[MAX_PATH * 2];
  GetModuleFileNameW(NULL, self, MAX_PATH * 2);
  DWORD ignored = 0, n = GetFileVersionInfoSizeW(self, &ignored);
  void *info = n ? malloc(n) : NULL;
  VS_FIXEDFILEINFO *fixed = NULL;
  UINT fn = 0;
  if (info && GetFileVersionInfoW(self, 0, n, info) && VerQueryValueW(info, L"\\", (void **)&fixed, &fn) && fixed)
    version = (int)HIWORD(fixed->dwFileVersionLS);  // (0,1,<n>,0)
  free(info);
  return version;
}

static SRWLOCK update_lock = SRWLOCK_INIT;
static char update_phase[16] = "idle";  // idle | downloading | retrying | ready | installing | failed
static int update_percent = -1;
static WCHAR update_error[300];
// the build asked for (its file's name), and once ready, where its installer is and the folder it runs in
static WCHAR update_file[MAX_PATH], update_ready[MAX_PATH * 2], update_ready_dir[MAX_PATH];
static void update_at_quit(void);
static volatile LONG update_working, update_untold;

static void update_say(const char *phase, int percent, const WCHAR *error) {
  AcquireSRWLockExclusive(&update_lock);
  int changed = strcmp(phase, update_phase) != 0 || percent != update_percent;
  lstrcpynA(update_phase, phase, sizeof update_phase);
  update_percent = percent;
  lstrcpynW(update_error, error ? error : L"", 300);
  ReleaseSRWLockExclusive(&update_lock);
  if (!strcmp(phase, "failed") || !strcmp(phase, "ready")) InterlockedExchange(&update_working, 0);
  if (changed) {
    InterlockedExchange(&update_untold, 1);
    mb_app_wake();
  }
}

// what changed told as the next frame begins (draw_frame)
static void update_tell(mb_outside_fn tell) {
  if (!InterlockedExchange(&update_untold, 0)) return;
  AcquireSRWLockShared(&update_lock);
  int failed = !strcmp(update_phase, "failed"), ready = !strcmp(update_phase, "ready");
  ReleaseSRWLockShared(&update_lock);
  if (tell) tell(MB_OUTSIDE_UPDATE, 1, failed ? -1 : ready ? 1 : 0);
}

moonbit_string_t mb_host_update_state(void) {
  if (mb_host_app_version() <= 0) return moonbit_make_string_raw(0);
  char b[900];
  AcquireSRWLockShared(&update_lock);
  size_t o = (size_t)snprintf(b, sizeof b, "{\"phase\":\"%s\",\"percent\":%d,\"error\":\"", update_phase, update_percent);
  o = json_put(b, o, sizeof b - 4, update_error, (int)wcslen(update_error));
  o += (size_t)snprintf(b + o, sizeof b - o, "\",\"file\":\"");
  o = json_put(b, o, sizeof b - 4, update_file, (int)wcslen(update_file));
  ReleaseSRWLockShared(&update_lock);
  o += (size_t)snprintf(b + o, sizeof b - o, "\"}");
  moonbit_string_t s = moonbit_make_string_raw((int32_t)o);
  for (size_t i = 0; i < o; i++) s[i] = (uint16_t)(unsigned char)b[i];
  return s;
}

static void update_log(const WCHAR *fmt, ...) {
  WCHAR line[600];
  va_list a;
  va_start(a, fmt);
  _vsnwprintf(line, 600, fmt, a);
  va_end(a);
  line[599] = 0;
  fprintf(stdout, "update: %ls\n", line);
  fflush(stdout);
}

typedef struct {
  WCHAR *url, *name;
  char sha256[65];
  ULONGLONG size;
  WCHAR dir[MAX_PATH];
  char *delta;  // the JSON the core gave for a delta, "" none
} update_job;

// the file's SHA-256 as hex, "" where it cannot be read
static void file_sha256(const WCHAR *path, char out[65]) {
  out[0] = 0;
  HANDLE f = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, NULL);
  if (f == INVALID_HANDLE_VALUE) return;
  BCRYPT_ALG_HANDLE alg = NULL;
  BCRYPT_HASH_HANDLE h = NULL;
  UCHAR digest[32];
  int ok = BCRYPT_SUCCESS(BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, NULL, 0)) &&
           BCRYPT_SUCCESS(BCryptCreateHash(alg, &h, NULL, 0, NULL, 0, 0));
  static unsigned char buf[1 << 16];
  DWORD n = 0;
  while (ok && ReadFile(f, buf, sizeof buf, &n, NULL) && n > 0) ok = BCRYPT_SUCCESS(BCryptHashData(h, buf, n, 0));
  ok = ok && BCRYPT_SUCCESS(BCryptFinishHash(h, digest, 32, 0));
  if (h) BCryptDestroyHash(h);
  if (alg) BCryptCloseAlgorithmProvider(alg, 0);
  CloseHandle(f);
  if (!ok) return;
  for (int i = 0; i < 32; i++) snprintf(out + 2 * i, 3, "%02x", digest[i]);
}

static ULONGLONG file_size(const WCHAR *path) {
  WIN32_FILE_ATTRIBUTE_DATA fa;
  return GetFileAttributesExW(path, GetFileExInfoStandard, &fa) ? ((ULONGLONG)fa.nFileSizeHigh << 32 | fa.nFileSizeLow) : 0;
}

// the files in `dir` other than those named (a NULL-ended list) taken away
static void update_leave_only(const WCHAR *dir, const WCHAR *const *keep) {
  WCHAR pattern[MAX_PATH * 2], path[MAX_PATH * 2];
  _snwprintf(pattern, MAX_PATH * 2, L"%ls\\*", dir);
  WIN32_FIND_DATAW f;
  HANDLE h = FindFirstFileW(pattern, &f);
  if (h == INVALID_HANDLE_VALUE) return;
  do {
    int kept = 0;
    if (f.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
    for (const WCHAR *const *k = keep; *k && !kept; k++) kept = !_wcsicmp(f.cFileName, *k);
    if (kept) continue;
    _snwprintf(path, MAX_PATH * 2, L"%ls\\%ls", dir, f.cFileName);
    DeleteFileW(path);
  } while (FindNextFileW(h, &f));
  FindClose(h);
}

// One try: the rest of the file (from what `part` holds) appended to it. 1 whole, 0 to try again (a cut connection,
// the server's trouble), -1 given up (why in `why`).
static int update_try(const WCHAR *url, ULONGLONG size, const WCHAR *part, WCHAR *why) {
  URL_COMPONENTS u;
  memset(&u, 0, sizeof u);
  u.dwStructSize = sizeof u;
  WCHAR host[256], path[2048];
  u.lpszHostName = host;
  u.dwHostNameLength = 256;
  u.lpszUrlPath = path;
  u.dwUrlPathLength = 2048;
  if (!WinHttpCrackUrl(url, 0, 0, &u)) {
    lstrcpynW(why, L"not a URL", 300);
    return -1;
  }
  ULONGLONG have = file_size(part);
  if (have > size) DeleteFileW(part), have = 0;
  if (have == size) return 1;
  HINTERNET s = WinHttpOpen(app_name(L"mbui"), WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
  HINTERNET c = s ? WinHttpConnect(s, host, u.nPort, 0) : NULL;
  HINTERNET r = c ? WinHttpOpenRequest(c, L"GET", path, NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
                                       u.nScheme == INTERNET_SCHEME_HTTPS ? WINHTTP_FLAG_SECURE : 0)
                  : NULL;
  int result = 0;
  WCHAR range[64] = L"";
  if (have) _snwprintf(range, 64, L"Range: bytes=%llu-", have);
  DWORD status = 0, sn = sizeof status;
  if (r && WinHttpSendRequest(r, have ? range : WINHTTP_NO_ADDITIONAL_HEADERS, have ? (DWORD)-1 : 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0) &&
      WinHttpReceiveResponse(r, NULL) &&
      WinHttpQueryHeaders(r, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_HEADER_NAME_BY_INDEX, &status, &sn,
                          WINHTTP_NO_HEADER_INDEX)) {
    if (status == 200 && have) DeleteFileW(part), have = 0;  // (the whole of it again: no range there)
    if (status == 200 || status == 206) {
      HANDLE f = CreateFileW(part, FILE_APPEND_DATA, 0, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
      if (f != INVALID_HANDLE_VALUE) {
        static unsigned char buf[1 << 16];
        DWORD n = 0;
        int last = -1;
        while (WinHttpReadData(r, buf, sizeof buf, &n) && n > 0) {
          DWORD put = 0;
          if (!WriteFile(f, buf, n, &put, NULL) || put != n) break;
          have += n;
          int percent = size ? (int)(have * 100 / size) : -1;
          if (percent != last) update_say("downloading", percent, NULL), last = percent;
        }
        CloseHandle(f);
        result = have == size ? 1 : 0;
      }
    } else if (status >= 400 && status < 500 && status != 408 && status != 429) {
      _snwprintf(why, 300, L"HTTP %lu", status);
      result = -1;
    }
  }
  if (r) WinHttpCloseHandle(r);
  if (c) WinHttpCloseHandle(c);
  if (s) WinHttpCloseHandle(s);
  return result;
}

// `file` downloaded (its bytes so far in `<file>.part`; the file there already taken where its SHA-256 is the one asked
// for) and checked against `sha256`: 1, or 0 and why not.
static int update_get(const WCHAR *url, ULONGLONG size, const char *sha256, const WCHAR *file, WCHAR *why) {
  WCHAR part[MAX_PATH * 2];
  _snwprintf(part, MAX_PATH * 2, L"%ls.part", file);
  char sum[65];
  file_sha256(file, sum);
  if (sum[0] && !_stricmp(sum, sha256)) return 1;
  // how far from the first: what an earlier try kept (0 none), not "not known" till the first bytes come
  if (size) update_say("downloading", (int)(file_size(part) * 100 / size), NULL);
  int got = 0;
  for (int failures = 0; got == 0;) {
    ULONGLONG before = file_size(part);
    got = update_try(url, size, part, why);
    if (got != 0) break;
    if (file_size(part) > before) failures = 0;
    if (++failures >= 5) break;
    update_say("retrying", update_percent, NULL);
    // (a cut download tried again a while after, a longer one each time it gets no further, as Android's Updates.java:
    // on this thread of its own)
    Sleep(1000u << (failures - 1));
  }
  if (got == 1) {
    file_sha256(part, sum);
    if (_stricmp(sum, sha256) != 0) {
      DeleteFileW(part);
      lstrcpynW(why, L"not the signed one (SHA-256)", 300);
      got = -1;
    } else if (!MoveFileExW(part, file, MOVEFILE_REPLACE_EXISTING)) {
      _snwprintf(why, 300, L"not kept (%lu)", GetLastError());
      got = -1;
    }
  }
  if (got != 1 && !why[0]) lstrcpynW(why, L"not downloaded", 300);
  return got == 1;
}

// One of the installed folder's files for the delta (update_delta.h's ud_read_fn; `root` the folder, wide): its bytes
// (malloc's), or NULL.
static unsigned char *update_old_file(void *root, const char *rel, size_t *size) {
  WCHAR wrel[MAX_PATH], path[MAX_PATH * 2];
  int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, rel, -1, wrel, MAX_PATH);
  if (n <= 0) return NULL;
  for (WCHAR *c = wrel; *c; c++)
    if (*c == L'/') *c = L'\\';
  _snwprintf(path, MAX_PATH * 2, L"%ls\\%ls", (const WCHAR *)root, wrel);
  path[MAX_PATH * 2 - 1] = 0;
  // (the program running among them: read beside its loader, whatever else holds it)
  HANDLE f = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING,
                         FILE_FLAG_SEQUENTIAL_SCAN, NULL);
  if (f == INVALID_HANDLE_VALUE) return NULL;
  LARGE_INTEGER total;
  unsigned char *b = NULL;
  size_t have = 0;
  if (GetFileSizeEx(f, &total) && total.QuadPart >= 0 && (ULONGLONG)total.QuadPart < ((ULONGLONG)1 << 40))
    b = (unsigned char *)malloc(total.QuadPart ? (size_t)total.QuadPart : 1);
  while (b && have < (size_t)total.QuadPart) {
    DWORD k = 0, ask = (DWORD)((size_t)total.QuadPart - have > (1u << 30) ? (1u << 30) : (size_t)total.QuadPart - have);
    if (!ReadFile(f, b + have, ask, &k, NULL) || k == 0) break;
    have += k;
  }
  CloseHandle(f);
  if (b && have != (size_t)total.QuadPart) {
    free(b);
    return NULL;
  }
  if (b) *size = have;
  return b;
}

static int update_made_bytes(void *out, const unsigned char *b, size_t n) {
  while (n > 0) {
    DWORD k = 0, ask = (DWORD)(n > (1u << 30) ? (1u << 30) : n);
    if (!WriteFile((HANDLE)out, b, ask, &k, NULL) || k == 0) return 0;
    b += k, n -= k;
  }
  return 1;
}

// The release's raw installer made from the delta the core says (`json`: url, sha256, size, makes_sha256, makes_size)
// and the installed folder, in the updates' folder beside what the installer's download keeps, into `made`: 1, or 0
// and why not (0 and no why: the installer is here already, the delta not wanted).
static int update_by_delta(update_job *j, WCHAR *made, WCHAR *why) {
  const char *p = j->delta;
  jv d;
  int ok = 0;
  if (!jparse(&p, &d, 0) || d.kind != 'o') {
    jv_free(&d);
    lstrcpynW(why, L"not a delta this host takes (JSON)", 300);
    return 0;
  }
  const char *url8 = jtext(&d, "url"), *sha256 = jtext(&d, "sha256"), *makes = jtext(&d, "makes_sha256");
  double size = jnum(&d, "size", 0), made_size = jnum(&d, "makes_size", 0);
  WCHAR url[2048], delta[MAX_PATH], delta_part[MAX_PATH], raw[MAX_PATH], part[MAX_PATH], file[MAX_PATH * 2];
  WCHAR dfile[MAX_PATH * 2], mpart[MAX_PATH * 2], root[MAX_PATH * 2];
  if (!MultiByteToWideChar(CP_UTF8, 0, url8, -1, url, 2048) || !url[0] || strlen(sha256) != 64 || strlen(makes) != 64 ||
      size <= 0 || made_size <= 0) {
    lstrcpynW(why, L"not a delta this host takes", 300);
    jv_free(&d);
    return 0;
  }
  // names: <name>.delta, and the installer it makes <name less .exe>.raw.exe (it is run: an .exe)
  size_t nn = wcslen(j->name);
  int exe = nn > 4 && !_wcsicmp(j->name + nn - 4, L".exe");
  _snwprintf(delta, MAX_PATH, L"%ls.delta", j->name);
  _snwprintf(delta_part, MAX_PATH, L"%ls.delta.part", j->name);
  _snwprintf(raw, MAX_PATH, L"%.*ls.raw.exe", (int)(exe ? nn - 4 : nn), j->name);
  _snwprintf(part, MAX_PATH, L"%ls.part", j->name);
  delta[MAX_PATH - 1] = delta_part[MAX_PATH - 1] = raw[MAX_PATH - 1] = part[MAX_PATH - 1] = 0;
  const WCHAR *keep[] = {j->name, part, delta, delta_part, raw, NULL};
  update_leave_only(j->dir, keep);
  _snwprintf(file, MAX_PATH * 2, L"%ls\\%ls", j->dir, j->name);
  _snwprintf(made, MAX_PATH * 2, L"%ls\\%ls", j->dir, raw);
  _snwprintf(dfile, MAX_PATH * 2, L"%ls\\%ls", j->dir, delta);
  _snwprintf(mpart, MAX_PATH * 2, L"%ls.part", made);
  if (GetFileAttributesW(file) != INVALID_FILE_ATTRIBUTES) {
    jv_free(&d);
    return 0;
  }
  char sum[65];
  file_sha256(made, sum);
  if (sum[0] && !_stricmp(sum, makes)) {
    update_log(L"%ls made before, sha256 %hs as the signed words say", raw, makes);
    jv_free(&d);
    return 1;
  }
  DeleteFileW(made);
  if (!update_get(url, (ULONGLONG)size, sha256, dfile, why)) {
    WCHAR w[300];
    lstrcpynW(w, why, 300);
    _snwprintf(why, 300, L"not downloaded (%ls)", w);
    why[299] = 0;
    _snwprintf(mpart, MAX_PATH * 2, L"%ls.part", dfile);
    DeleteFileW(mpart);
    jv_free(&d);
    return 0;
  }
  // the old files: the folder this program runs from
  GetModuleFileNameW(NULL, root, MAX_PATH * 2);
  if (wcsrchr(root, L'\\')) *wcsrchr(root, L'\\') = 0;
  const char *e = NULL;
  size_t dn = 0;
  unsigned char *bytes = NULL;
  {
    HANDLE f = CreateFileW(dfile, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, NULL);
    LARGE_INTEGER n;
    if (f != INVALID_HANDLE_VALUE && GetFileSizeEx(f, &n) && n.QuadPart > 0 && n.QuadPart < (1 << 30) &&
        (bytes = (unsigned char *)malloc((size_t)n.QuadPart)) != NULL) {
      DWORD k = 0;
      if (ReadFile(f, bytes, (DWORD)n.QuadPart, &k, NULL) && k == (DWORD)n.QuadPart) dn = k;
      else free(bytes), bytes = NULL;
    }
    if (f != INVALID_HANDLE_VALUE) CloseHandle(f);
  }
  HANDLE out = bytes ? CreateFileW(mpart, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL) : INVALID_HANDLE_VALUE;
  if (!bytes) e = "not read";
  else if (out == INVALID_HANDLE_VALUE) e = "can't write the made installer";
  else e = ud_apply(bytes, dn, update_old_file, root, update_made_bytes, out, (uint64_t)made_size);
  if (out != INVALID_HANDLE_VALUE) CloseHandle(out);
  free(bytes);
  DeleteFileW(dfile);
  if (!e) {
    file_sha256(mpart, sum);
    if (file_size(mpart) != (ULONGLONG)made_size) e = "the made installer is not the size the signed words say";
    else if (_stricmp(sum, makes) != 0) e = "the made installer is not the signed one (SHA-256)";
    else if (!MoveFileExW(mpart, made, MOVEFILE_REPLACE_EXISTING)) e = "the made installer not kept";
  }
  if (e) {
    DeleteFileW(mpart);
    _snwprintf(why, 300, L"%hs", e);
    why[299] = 0;
  } else {
    update_log(L"%ls made from a delta of %.0f bytes, sha256 %hs as the signed words say", raw, size, sum);
    ok = 1;
  }
  jv_free(&d);
  return ok;
}

static DWORD WINAPI update_thread(void *arg) {
  update_job *j = (update_job *)arg;
  WCHAR part[MAX_PATH], file[MAX_PATH * 2], why[300] = L"";
  SHCreateDirectoryExW(NULL, j->dir, NULL);
  _snwprintf(file, MAX_PATH * 2, L"%ls\\%ls", j->dir, j->name);
  _snwprintf(part, MAX_PATH, L"%ls.part", j->name);
  update_log(L"%ls: %llu bytes to %ls", j->url, j->size, file);
  int got = 0;
  // the delta first, where there is one: on any trouble, said and left for the installer downloaded whole
  if (j->delta && j->delta[0]) {
    got = update_by_delta(j, file, why);
    if (!got && why[0]) update_log(L"delta not used: %ls", why);
    why[0] = 0;
    if (!got) _snwprintf(file, MAX_PATH * 2, L"%ls\\%ls", j->dir, j->name);
  }
  if (!got) {
    // what an earlier update left (another build's installer, its part, a delta's) gone; this one's, downloaded
    // before, taken
    const WCHAR *keep[] = {j->name, part, NULL};
    update_leave_only(j->dir, keep);
    got = update_get(j->url, j->size, j->sha256, file, why);
  }
  if (!got) {
    update_log(L"failed: %ls", why);
    update_say("failed", -1, why);
  } else {
    AcquireSRWLockExclusive(&update_lock);
    lstrcpynW(update_ready, file, MAX_PATH * 2);
    lstrcpynW(update_ready_dir, j->dir, MAX_PATH);
    ReleaseSRWLockExclusive(&update_lock);
    update_log(L"%ls ready", file);
    static volatile LONG at_quit;
    if (!InterlockedExchange(&at_quit, 1)) atexit(update_at_quit);
    update_say("ready", -1, NULL);
  }
  free(j->url);
  free(j->name);
  free(j->delta);
  free(j);
  return 0;
}

// The app quitting with a build ready (the person never said 重启更新): its installer run as it goes, without opening
// the app after (no --force-run: the next time the person opens it, it is the newer build).
static void update_at_quit(void) {
  WCHAR file[MAX_PATH * 2], dir[MAX_PATH], command[MAX_PATH * 3];
  AcquireSRWLockExclusive(&update_lock);
  int ready = !strcmp(update_phase, "ready") && update_ready[0];
  lstrcpynW(file, update_ready, MAX_PATH * 2);
  lstrcpynW(dir, update_ready_dir, MAX_PATH);
  update_ready[0] = 0;
  ReleaseSRWLockExclusive(&update_lock);
  if (!ready) return;
  _snwprintf(command, MAX_PATH * 3, L"\"%ls\" --updated /S", file);
  STARTUPINFOW si = {sizeof si};
  PROCESS_INFORMATION pi;
  if (CreateProcessW(file, command, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, dir, &si, &pi)) {
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    update_log(L"%ls run as this one quits", file);
  }
}

void mb_host_update_fetch(moonbit_string_t url, moonbit_string_t sha256, double size, moonbit_string_t name, int32_t now,
                          moonbit_string_t delta) {
  (void)now;  // (no network here is told apart as costing more)
  if (mb_host_app_version() <= 0 || InterlockedCompareExchange(&update_working, 1, 0) != 0) return;
  update_job *j = (update_job *)calloc(1, sizeof *j);
  if (!j) return;
  int un = Moonbit_array_length(url), nn = Moonbit_array_length(name), sn = Moonbit_array_length(sha256);
  j->url = (WCHAR *)calloc((size_t)un + 1, sizeof(WCHAR));
  j->name = (WCHAR *)calloc((size_t)nn + 1, sizeof(WCHAR));
  if (!j->url || !j->name || sn != 64) {
    free(j->url), free(j->name), free(j);
    InterlockedExchange(&update_working, 0);
    return;
  }
  memcpy(j->url, url, (size_t)un * sizeof(WCHAR));
  // (its last part: a name, nothing of a path)
  for (int i = 0; i < nn; i++) j->name[i] = (WCHAR)name[i];
  WCHAR *slash = wcspbrk(j->name, L"/\\:");
  for (WCHAR *at = slash; at; at = wcspbrk(at + 1, L"/\\:")) slash = at;
  if (slash) memmove(j->name, slash + 1, (wcslen(slash + 1) + 1) * sizeof(WCHAR));
  if (!j->name[0] || !wcscmp(j->name, L"..")) {
    free(j->url), free(j->name), free(j);
    InterlockedExchange(&update_working, 0);
    return;
  }
  // (ready already, or being put in place)
  AcquireSRWLockShared(&update_lock);
  int same = !wcscmp(j->name, update_file) && (!strcmp(update_phase, "ready") || !strcmp(update_phase, "installing"));
  ReleaseSRWLockShared(&update_lock);
  if (same) {
    free(j->url), free(j->name), free(j);
    InterlockedExchange(&update_working, 0);
    return;
  }
  AcquireSRWLockExclusive(&update_lock);
  lstrcpynW(update_file, j->name, MAX_PATH);
  update_ready[0] = 0;
  ReleaseSRWLockExclusive(&update_lock);
  for (int i = 0; i < 64; i++) j->sha256[i] = (char)sha256[i];
  j->size = (ULONGLONG)size;
  // the delta's JSON as UTF-8 ("" none)
  int dn = Moonbit_array_length(delta);
  int du = dn ? WideCharToMultiByte(CP_UTF8, 0, (LPCWCH)delta, dn, NULL, 0, NULL, NULL) : 0;
  j->delta = (char *)malloc((size_t)du + 1);
  if (j->delta) {
    if (du) WideCharToMultiByte(CP_UTF8, 0, (LPCWCH)delta, dn, j->delta, du, NULL, NULL);
    j->delta[du] = 0;
  }
  PWSTR local = NULL;
  if (SUCCEEDED(SHGetKnownFolderPath(&FOLDERID_LocalAppData, 0, NULL, &local))) {
    _snwprintf(j->dir, MAX_PATH, L"%ls\\%ls\\updates", local, app_id());
    CoTaskMemFree(local);
  }
  update_say("downloading", -1, NULL);
  HANDLE t = CreateThread(NULL, 0, update_thread, j, 0, NULL);
  if (t) CloseHandle(t);
  else update_say("failed", -1, L"no thread");
}

void mb_host_update_apply(moonbit_string_t said) {
  (void)said;  // (opened again here: nothing to say)
  WCHAR file[MAX_PATH * 2], dir[MAX_PATH];
  AcquireSRWLockExclusive(&update_lock);
  int ready = !strcmp(update_phase, "ready") && update_ready[0];
  lstrcpynW(file, update_ready, MAX_PATH * 2);
  lstrcpynW(dir, update_ready_dir, MAX_PATH);
  if (ready) update_ready[0] = 0;
  ReleaseSRWLockExclusive(&update_lock);
  if (!ready) return;
  update_say("installing", -1, NULL);
  // the installer, run as the desktop app's updater ran it: it ends this app, puts the new one in its place, opens it
  WCHAR command[MAX_PATH * 3], why[300];
  _snwprintf(command, MAX_PATH * 3, L"\"%ls\" --updated /S --force-run", file);
  STARTUPINFOW si = {sizeof si};
  PROCESS_INFORMATION pi;
  if (CreateProcessW(file, command, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, dir, &si, &pi)) {
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    update_log(L"%ls run: this one quits", file);
    fflush(stdout);
    PostMessageW(hwnd, WM_MB_QUIT, 0, 0);
  } else {
    _snwprintf(why, 300, L"the installer did not start (%lu)", GetLastError());
    update_say("failed", -1, why);
  }
}
