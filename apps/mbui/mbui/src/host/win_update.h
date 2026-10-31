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
// Included by win_app.c after win_life.h (its app_id).
#include <stdarg.h>
#include <shlobj.h>
#include <knownfolders.h>
#include <winhttp.h>
#include <bcrypt.h>

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

// the files in `dir` other than `name` and its part taken away
static void update_leave_only(const WCHAR *dir, const WCHAR *name) {
  WCHAR pattern[MAX_PATH * 2], part[MAX_PATH], path[MAX_PATH * 2];
  _snwprintf(pattern, MAX_PATH * 2, L"%ls\\*", dir);
  _snwprintf(part, MAX_PATH, L"%ls.part", name);
  WIN32_FIND_DATAW f;
  HANDLE h = FindFirstFileW(pattern, &f);
  if (h == INVALID_HANDLE_VALUE) return;
  do {
    if (f.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
    if (!_wcsicmp(f.cFileName, name) || !_wcsicmp(f.cFileName, part)) continue;
    _snwprintf(path, MAX_PATH * 2, L"%ls\\%ls", dir, f.cFileName);
    DeleteFileW(path);
  } while (FindNextFileW(h, &f));
  FindClose(h);
}

// One try: the rest of the file (from what `part` holds) appended to it. 1 whole, 0 to try again (a cut connection,
// the server's trouble), -1 given up (why in `why`).
static int update_try(update_job *j, const WCHAR *part, WCHAR *why) {
  URL_COMPONENTS u;
  memset(&u, 0, sizeof u);
  u.dwStructSize = sizeof u;
  WCHAR host[256], path[2048];
  u.lpszHostName = host;
  u.dwHostNameLength = 256;
  u.lpszUrlPath = path;
  u.dwUrlPathLength = 2048;
  if (!WinHttpCrackUrl(j->url, 0, 0, &u)) {
    lstrcpynW(why, L"not a URL", 300);
    return -1;
  }
  ULONGLONG have = file_size(part);
  if (have > j->size) DeleteFileW(part), have = 0;
  if (have == j->size) return 1;
  HINTERNET s = WinHttpOpen(L"still.fail", WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
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
          int percent = j->size ? (int)(have * 100 / j->size) : -1;
          if (percent != last) update_say("downloading", percent, NULL), last = percent;
        }
        CloseHandle(f);
        result = have == j->size ? 1 : 0;
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

static DWORD WINAPI update_thread(void *arg) {
  update_job *j = (update_job *)arg;
  WCHAR part[MAX_PATH * 2], file[MAX_PATH * 2], why[300] = L"";
  SHCreateDirectoryExW(NULL, j->dir, NULL);
  _snwprintf(file, MAX_PATH * 2, L"%ls\\%ls", j->dir, j->name);
  _snwprintf(part, MAX_PATH * 2, L"%ls.part", file);
  update_log(L"%ls: %llu bytes to %ls", j->url, j->size, file);
  // what an earlier update left (another build's installer, its part) gone; this one's, downloaded before, taken
  update_leave_only(j->dir, j->name);
  char sum[65];
  file_sha256(file, sum);
  int got = 0;
  if (sum[0] && !_stricmp(sum, j->sha256)) {
    MoveFileExW(file, part, MOVEFILE_REPLACE_EXISTING);
    got = 1;
  }
  // how far from the first: what an earlier try kept (0 none), not "not known" till the first bytes come
  if (!got && j->size) update_say("downloading", (int)(file_size(part) * 100 / j->size), NULL);
  for (int failures = 0; got == 0;) {
    ULONGLONG before = file_size(part);
    got = update_try(j, part, why);
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
    if (_stricmp(sum, j->sha256) != 0) {
      DeleteFileW(part);
      lstrcpynW(why, L"not the signed one (SHA-256)", 300);
      got = -1;
    }
  }
  if (got != 1) {
    if (!why[0]) lstrcpynW(why, L"not downloaded", 300);
    update_log(L"failed: %ls", why);
    update_say("failed", -1, why);
  } else {
    DeleteFileW(file);
    MoveFileW(part, file);
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

void mb_host_update_fetch(moonbit_string_t url, moonbit_string_t sha256, double size, moonbit_string_t name, int32_t now) {
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
