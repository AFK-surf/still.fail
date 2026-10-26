// This machine's station on Windows (@hostapi.local_station, local_station_act), as mac_app.m has it on the Mac and
// still.fail's desktop app managed it on Windows (apps/desktop/src/installed.ts, station.ts): its data
// (%USERPROFILE%\.stillfail), whether it runs (run\station.json's pid alive) and by what (the scheduled task the
// installer made, "still.fail station": cloud/src/install-windows.ts; or a process started by hand), its release, whether
// the installer put one there (<data>\app: the desktop app's carried station had none), the workspace its data is in
// (mesh\cloud.json); what is being done to it and what went wrong last. "" where there is neither data nor a task. Its
// acts, on a thread of their own: start, stop, restart (the task's, schtasks; one started by hand only stopped), the
// log or the folder opened, and the station's installer (install.ps1 in PowerShell, as the person would run it: with a
// token a workspace joined, without one the station here brought up to date and run as the task, the desktop app's
// carried one among them). Included by win_app.c after win_life.h (its jparse, json_put, hwnd, want_frame).
#include <shellapi.h>
#include <taskschd.h>
#include <oleauto.h>
#include <wctype.h>

#pragma comment(lib, "taskschd.lib")
#pragma comment(lib, "oleaut32.lib")

#define STATION_TASK L"still.fail station"

static SRWLOCK local_lock = SRWLOCK_INIT;
static char local_doing[16];     // what is being done ("": nothing), under local_lock
static WCHAR *local_failed;      // what went wrong last (NULL: nothing), under local_lock
static WCHAR *local_said;        // the last the installer said, under local_lock

static void local_set(WCHAR **at, const WCHAR *s) {
  free(*at);
  *at = s ? _wcsdup(s) : NULL;
}

// %USERPROFILE%\.stillfail
static void local_data(WCHAR *out, size_t cap) {
  const WCHAR *home = _wgetenv(L"USERPROFILE");
  _snwprintf(out, cap, L"%ls\\.stillfail", home ? home : L"");
  out[cap - 1] = 0;
}

// whether the installer's task is there (the Task Scheduler's own word, asked on the window's thread)
static ITaskService *task_service;
static int local_task(void) {
  if (!task_service) {
    if (FAILED(CoCreateInstance(&CLSID_TaskScheduler, NULL, CLSCTX_INPROC_SERVER, &IID_ITaskService, (void **)&task_service)))
      return 0;
    VARIANT none;
    VariantInit(&none);
    if (FAILED(task_service->lpVtbl->Connect(task_service, none, none, none, none))) {
      task_service->lpVtbl->Release(task_service);
      task_service = NULL;
      return 0;
    }
  }
  ITaskFolder *root = NULL;
  IRegisteredTask *t = NULL;
  BSTR at = SysAllocString(L"\\"), name = SysAllocString(STATION_TASK);
  int there = SUCCEEDED(task_service->lpVtbl->GetFolder(task_service, at, &root)) && root &&
              SUCCEEDED(root->lpVtbl->GetTask(root, name, &t)) && t;
  if (t) t->lpVtbl->Release(t);
  if (root) root->lpVtbl->Release(root);
  SysFreeString(at);
  SysFreeString(name);
  return there;
}

// a JSON file of the data's, read: its value (jv_free it), kind 0 where there is none
static jv local_json(const WCHAR *path) {
  jv v;
  memset(&v, 0, sizeof v);
  HANDLE f = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, 0, NULL);
  if (f == INVALID_HANDLE_VALUE) return v;
  char b[16384];
  DWORD n = 0;
  BOOL ok = ReadFile(f, b, sizeof b - 1, &n, NULL);
  CloseHandle(f);
  if (!ok) return v;
  b[n] = 0;
  const char *p = b;
  if (!jparse(&p, &v, 0)) {
    jv_free(&v);
    memset(&v, 0, sizeof v);
  }
  return v;
}

static int local_alive(double pid) {
  if (pid <= 0) return 0;
  HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD)pid);
  if (!h) return GetLastError() == ERROR_ACCESS_DENIED;
  DWORD code = 0;
  int alive = GetExitCodeProcess(h, &code) && code == STILL_ACTIVE;
  CloseHandle(h);
  return alive;
}

// a number of a JSON object's ("pid"), -1 none
static double jnumber(const jv *o, const char *key) {
  const jv *v = jget(o, key);
  return v && v->kind == 'n' && v->s ? atof(v->s) : -1;
}

// (UTF-8 to JSON's string, put: json_put takes UTF-16)
static size_t json_put8(char *out, size_t o, size_t cap, const char *s) {
  int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
  WCHAR *w = (WCHAR *)calloc((size_t)n + 1, sizeof(WCHAR));
  if (!w) return o;
  MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
  o = json_put(out, o, cap, w, (int)wcslen(w));
  free(w);
  return o;
}

moonbit_string_t mb_host_local_station(void) {
  WCHAR data[MAX_PATH], path[MAX_PATH * 2];
  local_data(data, MAX_PATH);
  int there = GetFileAttributesW(data) != INVALID_FILE_ATTRIBUTES;
  int task = local_task();
  AcquireSRWLockShared(&local_lock);
  int doing = local_doing[0] != 0, failed = local_failed != NULL;
  ReleaseSRWLockShared(&local_lock);
  // none here, and nothing being done or gone wrong about it: ""; one being installed is said before it is there
  if (!there && !task && !doing && !failed) return moonbit_make_string_raw(0);
  size_t cap = 8192, o = 0;
  char *b = (char *)malloc(cap);
  if (!b) return moonbit_make_string_raw(0);
  o += (size_t)snprintf(b + o, cap - o, "{");
  if (there || task) {
    o += (size_t)snprintf(b + o, cap - o, "\"data\":\"");
    o = json_put(b, o, cap - 8, data, (int)wcslen(data));
    o += (size_t)snprintf(b + o, cap - o, "\",");
  }
  _snwprintf(path, MAX_PATH * 2, L"%ls\\run\\station.json", data);
  jv run = local_json(path);
  int alive = local_alive(jnumber(&run, "pid"));
  o += (size_t)snprintf(b + o, cap - o, "\"runner\":\"%s\"", !alive ? "none" : task ? "service" : "other");
  const char *version = alive ? jtext(&run, "version") : "";
  char build[32] = "";
  if (!*version && task) {
    _snwprintf(path, MAX_PATH * 2, L"%ls\\app\\BUILD", data);
    HANDLE f = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    DWORD n = 0;
    char num[16] = "";
    if (f != INVALID_HANDLE_VALUE) ReadFile(f, num, sizeof num - 1, &n, NULL), CloseHandle(f);
    num[n] = 0;
    for (DWORD i = 0; i < n; i++)
      if (num[i] < '0' || num[i] > '9') num[i] = 0;
    if (num[0]) snprintf(build, sizeof build, "0.1.%s", num), version = build;
  }
  if (*version) {
    o += (size_t)snprintf(b + o, cap - o, ",\"version\":\"");
    o = json_put8(b, o, cap - 8, version);
    o += (size_t)snprintf(b + o, cap - o, "\"");
  }
  jv_free(&run);
  // a release of its own (<data>\app: the installer's); a station still.fail's desktop app ran from its own has none
  _snwprintf(path, MAX_PATH * 2, L"%ls\\app", data);
  if (GetFileAttributesW(path) != INVALID_FILE_ATTRIBUTES) o += (size_t)snprintf(b + o, cap - o, ",\"installed\":true");
  if (task) o += (size_t)snprintf(b + o, cap - o, ",\"service\":{\"kind\":\"task\",\"name\":\"still.fail station\"}");
  _snwprintf(path, MAX_PATH * 2, L"%ls\\mesh\\cloud.json", data);
  jv cloud = local_json(path);
  const char *ws = jtext(&cloud, "workspace");
  if (*ws) {
    o += (size_t)snprintf(b + o, cap - o, ",\"workspace\":{\"id\":\"");
    o = json_put8(b, o, cap - 8, ws);
    o += (size_t)snprintf(b + o, cap - o, "\"");
    static const char *const keys[][2] = {{"workspace_name", "name"}, {"station", "station"}, {"name", "stationName"}};
    for (int i = 0; i < 3; i++) {
      const char *v = jtext(&cloud, keys[i][0]);
      if (!*v) continue;
      o += (size_t)snprintf(b + o, cap - o, ",\"%s\":\"", keys[i][1]);
      o = json_put8(b, o, cap - 8, v);
      o += (size_t)snprintf(b + o, cap - o, "\"");
    }
    const jv *removed = jget(&cloud, "removed_at");
    o += (size_t)snprintf(b + o, cap - o, ",\"removed\":%s}", removed && removed->kind != 'z' ? "true" : "false");
  }
  jv_free(&cloud);
  AcquireSRWLockShared(&local_lock);
  if (local_doing[0]) {
    o += (size_t)snprintf(b + o, cap - o, ",\"doing\":\"%s\"", local_doing);
    if (local_said) {
      o += (size_t)snprintf(b + o, cap - o, ",\"said\":\"");
      o = json_put(b, o, cap - 8, local_said, (int)wcslen(local_said));
      o += (size_t)snprintf(b + o, cap - o, "\"");
    }
  }
  if (local_failed) {
    o += (size_t)snprintf(b + o, cap - o, ",\"failed\":\"");
    o = json_put(b, o, cap - 8, local_failed, (int)wcslen(local_failed));
    o += (size_t)snprintf(b + o, cap - o, "\"");
  }
  ReleaseSRWLockShared(&local_lock);
  o += (size_t)snprintf(b + o, cap - o, "}");
  int wn = MultiByteToWideChar(CP_UTF8, 0, b, (int)o, NULL, 0);
  moonbit_string_t s = moonbit_make_string_raw(wn);
  MultiByteToWideChar(CP_UTF8, 0, b, (int)o, (WCHAR *)s, wn);
  free(b);
  return s;
}

// `command` run with no window, what it says read as it comes (the installer's steps: its last line, local_said);
// NULL when it ended well, else what it said last (malloc'd)
static WCHAR *local_run(WCHAR *command, const WCHAR *channel) {
  SECURITY_ATTRIBUTES sa = {sizeof sa, NULL, TRUE};
  HANDLE r = NULL, w = NULL;
  if (!CreatePipe(&r, &w, &sa, 0)) return _wcsdup(L"pipe");
  SetHandleInformation(r, HANDLE_FLAG_INHERIT, 0);
  STARTUPINFOW si = {sizeof si};
  si.dwFlags = STARTF_USESTDHANDLES;
  si.hStdOutput = w;
  si.hStdError = w;
  si.hStdInput = NULL;
  PROCESS_INFORMATION pi;
  // (the beta's channel for the installer: STILLFAIL_CHANNEL, in what it is started with)
  if (channel) SetEnvironmentVariableW(L"STILLFAIL_CHANNEL", channel);
  BOOL started = CreateProcessW(NULL, command, NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi);
  if (channel) SetEnvironmentVariableW(L"STILLFAIL_CHANNEL", NULL);
  CloseHandle(w);
  if (!started) {
    CloseHandle(r);
    return _wcsdup(L"not started");
  }
  char buf[4096], line[1024];
  size_t ln = 0;
  WCHAR last[1024] = L"";
  DWORD n = 0;
  while (ReadFile(r, buf, sizeof buf, &n, NULL) && n > 0) {
    for (DWORD i = 0; i < n; i++) {
      char c = buf[i];
      if (c != '\r' && c != '\n' && ln + 1 < sizeof line) {
        line[ln++] = c;
        continue;
      }
      if (ln == 0) continue;
      line[ln] = 0;
      ln = 0;
      WCHAR said[1024];
      if (MultiByteToWideChar(CP_UTF8, 0, line, -1, said, 1024) <= 1) continue;
      lstrcpynW(last, said, 1024);
      AcquireSRWLockExclusive(&local_lock);
      local_set(&local_said, said);
      ReleaseSRWLockExclusive(&local_lock);
      mb_app_wake();
    }
  }
  CloseHandle(r);
  WaitForSingleObject(pi.hProcess, INFINITE);
  DWORD code = 1;
  GetExitCodeProcess(pi.hProcess, &code);
  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);
  fprintf(stdout, "win: %ls exited %lu\n", command, (unsigned long)code);
  fflush(stdout);
  if (code == 0) return NULL;
  if (last[0]) return _wcsdup(last);
  WCHAR why[32];
  _snwprintf(why, 32, L"exit %lu", (unsigned long)code);
  return _wcsdup(why);
}

typedef struct {
  char verb[16];
  WCHAR *command;  // what is run (NULL: the act needs none here)
  WCHAR *channel;
} local_job;

static DWORD WINAPI local_thread(void *arg) {
  local_job *j = (local_job *)arg;
  WCHAR *failed = j->command ? local_run(j->command, j->channel) : NULL;
  AcquireSRWLockExclusive(&local_lock);
  local_doing[0] = 0;
  local_set(&local_failed, failed);
  local_set(&local_said, NULL);
  ReleaseSRWLockExclusive(&local_lock);
  free(failed);
  free(j->command);
  free(j->channel);
  free(j);
  mb_app_wake();
  return 0;
}

// `verb` begun with `command` on a thread of its own, unless something is being done already ("busy")
static void local_begin(const char *verb, WCHAR *command, const WCHAR *channel) {
  AcquireSRWLockExclusive(&local_lock);
  if (local_doing[0]) {
    local_set(&local_failed, L"busy");
    ReleaseSRWLockExclusive(&local_lock);
    free(command);
    want_frame = 1;
    return;
  }
  lstrcpynA(local_doing, verb, sizeof local_doing);
  local_set(&local_failed, NULL);
  local_set(&local_said, NULL);
  ReleaseSRWLockExclusive(&local_lock);
  local_job *j = (local_job *)calloc(1, sizeof *j);
  if (!j) return;
  lstrcpynA(j->verb, verb, sizeof j->verb);
  j->command = command;
  j->channel = channel ? _wcsdup(channel) : NULL;
  HANDLE t = CreateThread(NULL, 0, local_thread, j, 0, NULL);
  if (t) CloseHandle(t);
  else local_thread(j);
  want_frame = 1;
}

// an ask's string field, as UTF-16 (malloc'd), "" none
static WCHAR *ask_text(const jv *ask, const char *key) {
  const char *s = jtext(ask, key);
  int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
  WCHAR *w = (WCHAR *)calloc((size_t)n + 1, sizeof(WCHAR));
  if (w) MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
  return w;
}

// what may go in a PowerShell's single-quoted string: no quote, nothing but what a URL or a token is made of
static int ps_plain(const WCHAR *s) {
  for (; *s; s++)
    if (!(iswalnum(*s) || wcschr(L":/.-_~?&=%+", *s))) return 0;
  return 1;
}

void mb_host_local_station_act(moonbit_string_t action) {
  int n = Moonbit_array_length(action);
  WCHAR *a = (WCHAR *)calloc((size_t)n + 1, sizeof(WCHAR));
  if (!a) return;
  memcpy(a, action, (size_t)n * sizeof(WCHAR));
  WCHAR data[MAX_PATH], path[MAX_PATH * 2];
  local_data(data, MAX_PATH);
  // `install {…}`, `update {…}`: the station's installer, install.ps1 of the cloud (`origin`), a token or none, the
  // channel the app is on
  if (!wcsncmp(a, L"install ", 8) || !wcsncmp(a, L"update ", 7)) {
    int install = a[0] == L'i';
    const WCHAR *json = a + (install ? 8 : 7);
    int u = WideCharToMultiByte(CP_UTF8, 0, json, -1, NULL, 0, NULL, NULL);
    char *j8 = (char *)malloc((size_t)u + 1);
    if (j8) WideCharToMultiByte(CP_UTF8, 0, json, -1, j8, u, NULL, NULL);
    jv ask;
    const char *p = j8;
    int ok = j8 && jparse(&p, &ask, 0) && ask.kind == 'o';
    WCHAR *origin = ok ? ask_text(&ask, "origin") : NULL, *token = ok ? ask_text(&ask, "token") : NULL;
    int beta = ok && !strcmp(jtext(&ask, "channel"), "beta");
    if (ok) jv_free(&ask);
    free(j8);
    if (origin && token && (!wcsncmp(origin, L"https://", 8) || !wcsncmp(origin, L"http://", 7)) && ps_plain(origin) &&
        ps_plain(token)) {
      size_t cap = wcslen(origin) + wcslen(token) + 200;
      WCHAR *command = (WCHAR *)calloc(cap, sizeof(WCHAR));
      if (command)
        _snwprintf(command, cap,
                   L"powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"& ([scriptblock]::Create((irm '%ls/install.ps1'))) %ls\"",
                   origin, token);
      if (command) local_begin(install ? "install" : "update", command, beta ? L"beta" : NULL);
    } else {
      AcquireSRWLockExclusive(&local_lock);
      local_set(&local_failed, L"origin");
      ReleaseSRWLockExclusive(&local_lock);
    }
    free(origin);
    free(token);
    free(a);
    return;
  }
  if (!wcscmp(a, L"log") || !wcscmp(a, L"folder")) {
    if (!wcscmp(a, L"log")) _snwprintf(path, MAX_PATH * 2, L"%ls\\stillfail.log", data);
    else lstrcpynW(path, data, MAX_PATH * 2);
    ShellExecuteW(NULL, L"open", path, NULL, NULL, SW_SHOWNORMAL);
    free(a);
    return;
  }
  int start = !wcscmp(a, L"start"), stop = !wcscmp(a, L"stop"), restart = !wcscmp(a, L"restart");
  if (!start && !stop && !restart) {
    free(a);
    return;
  }
  WCHAR *command = NULL;
  if (local_task()) {
    // (the task ended, then run again: a restart; schtasks's own, with nothing of a shell)
    command = (WCHAR *)calloc(256, sizeof(WCHAR));
    if (command) {
      if (stop) _snwprintf(command, 256, L"schtasks.exe /End /TN \"%ls\"", STATION_TASK);
      else if (start) _snwprintf(command, 256, L"schtasks.exe /Run /TN \"%ls\"", STATION_TASK);
      else _snwprintf(command, 256, L"cmd.exe /c schtasks.exe /End /TN \"%ls\" & schtasks.exe /Run /TN \"%ls\"", STATION_TASK, STATION_TASK);
    }
  } else {
    _snwprintf(path, MAX_PATH * 2, L"%ls\\run\\station.json", data);
    jv run = local_json(path);
    double pid = jnumber(&run, "pid");
    jv_free(&run);
    // started by hand: only stopped from here, it has nothing to start it again
    if (stop && local_alive(pid)) {
      command = (WCHAR *)calloc(64, sizeof(WCHAR));
      if (command) _snwprintf(command, 64, L"taskkill.exe /PID %lu /T /F", (unsigned long)pid);
    } else {
      AcquireSRWLockExclusive(&local_lock);
      local_set(&local_failed, local_alive(pid) ? L"byHand" : L"noService");
      ReleaseSRWLockExclusive(&local_lock);
      want_frame = 1;
      free(a);
      return;
    }
  }
  char verb[16];
  WideCharToMultiByte(CP_UTF8, 0, a, -1, verb, sizeof verb, NULL, NULL);
  if (command) local_begin(verb, command, NULL);
  free(a);
}
