// This device's password manager for the Windows host (host_native.mbt `pw_*`, hostapi/passwords.mbt): 1Password's
// command-line tool `op.exe`, run without a window with the arguments the app gives, its output kept until the app
// takes it: apple_passwords.m's way. `op` signed in through 1Password's desktop app asks the person itself (Windows
// Hello, in its own window). Found where winget and 1Password's installer put it, else on PATH.
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "win.h"

void mb_host_request_frame(void);

typedef struct run {
  int id;
  HANDLE process;
  // How it ended, once it has: "<code>\x1f<out>\x1f<err>\x1f" (UTF-8).
  char *done;
  struct run *next;
} run;

static SRWLOCK lock = SRWLOCK_INIT;
static run *runs;
static int run_next;

static run *find(int id) {
  for (run *r = runs; r; r = r->next)
    if (r->id == id) return r;
  return NULL;
}

/// Where op.exe is: winget's links, 1Password's installer's, else the first on PATH; FALSE when it is nowhere.
static BOOL op_path(WCHAR *out, DWORD cap) {
  WCHAR place[MAX_PATH];
  const WCHAR *vars[] = {L"%LOCALAPPDATA%\\Microsoft\\WinGet\\Links\\op.exe", L"%ProgramFiles%\\1Password CLI\\op.exe", L"%LOCALAPPDATA%\\1Password\\cli\\op.exe"};
  for (int i = 0; i < 3; i++) {
    if (ExpandEnvironmentStringsW(vars[i], place, MAX_PATH) && GetFileAttributesW(place) != INVALID_FILE_ATTRIBUTES) {
      wcsncpy(out, place, cap - 1);
      out[cap - 1] = 0;
      return TRUE;
    }
  }
  return SearchPathW(NULL, L"op.exe", NULL, cap, out, NULL) > 0;
}

/// `arg` put on a command line as one argument, as the C runtime reads it back (quotes, and the backslashes before them).
static void quote(WCHAR *line, size_t cap, size_t *at, const WCHAR *arg) {
#define PUT(c) do { if (*at + 1 < cap) line[(*at)++] = (c); } while (0)
  PUT(L' ');
  PUT(L'"');
  for (const WCHAR *p = arg;; p++) {
    size_t slashes = 0;
    while (*p == L'\\') {
      slashes++;
      p++;
    }
    if (*p == 0) {
      for (size_t i = 0; i < slashes * 2; i++) PUT(L'\\');
      break;
    }
    if (*p == L'"') {
      for (size_t i = 0; i < slashes * 2 + 1; i++) PUT(L'\\');
    } else {
      for (size_t i = 0; i < slashes; i++) PUT(L'\\');
    }
    PUT(*p);
  }
  PUT(L'"');
  line[*at] = 0;
#undef PUT
}

/// All a pipe gives until it ends, NUL-ended.
static char *drain(HANDLE h) {
  size_t n = 0, cap = 4096;
  char *buf = malloc(cap);
  for (;;) {
    DWORD got = 0;
    if (n + 4096 > cap) buf = realloc(buf, cap *= 2);
    if (!ReadFile(h, buf + n, 4096, &got, NULL) || got == 0) break;
    n += got;
  }
  buf[n] = 0;
  return buf;
}

typedef struct waiting {
  int id;
  HANDLE process, out, err;
  // Its error output, read on a thread of its own.
  char *errs;
} waiting;

static DWORD WINAPI err_reader(LPVOID p) {
  waiting *w = p;
  w->errs = drain(w->err);
  return 0;
}

/// Reads what it says, waits for it to end, and keeps how it ended for the app (a frame asked for).
static DWORD WINAPI wait_run(LPVOID p) {
  waiting *w = p;
  // Its error output read beside its output: a pipe that fills up holds the process.
  HANDLE t = CreateThread(NULL, 0, err_reader, w, 0, NULL);
  char *said = drain(w->out);
  if (t) {
    WaitForSingleObject(t, INFINITE);
    CloseHandle(t);
  } else {
    w->errs = drain(w->err);
  }
  WaitForSingleObject(w->process, INFINITE);
  DWORD code = 1;
  GetExitCodeProcess(w->process, &code);
  size_t len = strlen(said) + strlen(w->errs) + 32;
  char *done = malloc(len);
  snprintf(done, len, "%ld\x1f%s\x1f%s\x1f", (long)code, said, w->errs);
  free(said);
  free(w->errs);
  CloseHandle(w->out);
  CloseHandle(w->err);
  CloseHandle(w->process);
  AcquireSRWLockExclusive(&lock);
  run *r = find(w->id);
  if (r) {
    r->done = done;
    if (r->process) CloseHandle(r->process);
    r->process = NULL;
  } else {
    free(done);
  }
  ReleaseSRWLockExclusive(&lock);
  free(w);
  mb_host_request_frame();
  return 0;
}

int32_t mb_host_passwords_able(void) { return 1; }

static int ended(int id, const char *why) {
  size_t len = strlen(why) + 16;
  char *done = malloc(len);
  snprintf(done, len, "-1\x1f\x1f%s\x1f", why);
  AcquireSRWLockExclusive(&lock);
  run *r = find(id);
  if (r) r->done = done;
  else free(done);
  ReleaseSRWLockExclusive(&lock);
  mb_host_request_frame();
  return id;
}

int32_t mb_host_passwords_run(moonbit_string_t args) {
  run *r = calloc(1, sizeof *r);
  AcquireSRWLockExclusive(&lock);
  r->id = ++run_next;
  r->next = runs;
  runs = r;
  int id = r->id;
  ReleaseSRWLockExclusive(&lock);
  WCHAR op[MAX_PATH];
  if (!op_path(op, MAX_PATH)) return ended(id, "op not found");
  // The command line: the program, then each argument (each ended by a unit separator, U+001F, as the app gives them).
  int n = Moonbit_array_length(args);
  size_t cap = (size_t)n * 2 + MAX_PATH + 64;
  WCHAR *line = malloc(cap * sizeof(WCHAR));
  size_t at = 0;
  line[0] = 0;
  quote(line, cap, &at, op);
  WCHAR *arg = malloc(((size_t)n + 1) * sizeof(WCHAR));
  int k = 0;
  for (int i = 0; i < n; i++) {
    WCHAR c = ((const WCHAR *)args)[i];
    if (c == 0x1f) {
      arg[k] = 0;
      quote(line, cap, &at, arg);
      k = 0;
    } else {
      arg[k++] = c;
    }
  }
  free(arg);
  SECURITY_ATTRIBUTES sa = {sizeof sa, NULL, TRUE};
  HANDLE out_r, out_w, err_r, err_w;
  if (!CreatePipe(&out_r, &out_w, &sa, 0) || !CreatePipe(&err_r, &err_w, &sa, 0)) {
    free(line);
    return ended(id, "no pipe");
  }
  SetHandleInformation(out_r, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(err_r, HANDLE_FLAG_INHERIT, 0);
  STARTUPINFOW si = {sizeof si};
  si.dwFlags = STARTF_USESTDHANDLES;
  si.hStdInput = NULL;
  si.hStdOutput = out_w;
  si.hStdError = err_w;
  PROCESS_INFORMATION pi;
  // (the line without the space `quote` puts first)
  BOOL started = CreateProcessW(op, line + 1, NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi);
  free(line);
  CloseHandle(out_w);
  CloseHandle(err_w);
  if (!started) {
    CloseHandle(out_r);
    CloseHandle(err_r);
    return ended(id, "op did not start");
  }
  CloseHandle(pi.hThread);
  AcquireSRWLockExclusive(&lock);
  run *still = find(id);
  HANDLE mine = NULL;
  if (still) {
    still->process = pi.hProcess;
    DuplicateHandle(GetCurrentProcess(), pi.hProcess, GetCurrentProcess(), &mine, 0, FALSE, DUPLICATE_SAME_ACCESS);
  }
  ReleaseSRWLockExclusive(&lock);
  // The waiting thread's own handle of the process (the run's is closed by whichever of it and `end` comes first).
  waiting *w = malloc(sizeof *w);
  *w = (waiting){id, mine, out_r, err_r, NULL};
  if (!mine) {
    if (still) still->process = NULL;
    w->process = pi.hProcess;
  }
  HANDLE t = CreateThread(NULL, 0, wait_run, w, 0, NULL);
  if (t) CloseHandle(t);
  return id;
}

moonbit_string_t mb_host_passwords_out(int32_t id) {
  AcquireSRWLockShared(&lock);
  run *r = find(id);
  WCHAR *w = NULL;
  int n = 0;
  if (r && r->done) {
    n = MultiByteToWideChar(CP_UTF8, 0, r->done, -1, NULL, 0) - 1;
    w = malloc(((size_t)n + 1) * sizeof(WCHAR));
    MultiByteToWideChar(CP_UTF8, 0, r->done, -1, w, n + 1);
  }
  ReleaseSRWLockShared(&lock);
  moonbit_string_t out = moonbit_make_string_raw(n > 0 ? n : 0);
  if (n > 0) memcpy(out, w, (size_t)n * sizeof(WCHAR));
  free(w);
  return out;
}

void mb_host_passwords_end(int32_t id) {
  AcquireSRWLockExclusive(&lock);
  for (run **p = &runs; *p; p = &(*p)->next) {
    if ((*p)->id != id) continue;
    run *r = *p;
    *p = r->next;
    if (r->process) {
      TerminateProcess(r->process, 1);
      CloseHandle(r->process);
    }
    free(r->done);
    free(r);
    break;
  }
  ReleaseSRWLockExclusive(&lock);
}
