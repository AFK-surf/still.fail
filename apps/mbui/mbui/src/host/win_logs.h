// The app's log files on Windows: what it says on stderr and its log (a window's program started from the Start menu
// has neither anywhere to go: win_life.h life_console) and its performance record (@hostapi.perf_state, as iOS's:
// ios_app.m) kept in %LOCALAPPDATA%\<its id>\logs: log-<day>-<n>.log and perf-<day>-<n>.log, each to 5 MB, the 3 newest
// of each kept (log_files.h says what a line may hold, and the names). Nothing leaves the device. Included by win_app.c,
// and by scripts/win_logs_test.c, which runs it on Windows.
//
// Who waits for what: stderr (this program's C runtime's and, through the system's handle, what its engine and shell
// write) is a pipe. logs_pump reads it, gives it on as it was given to whoever had stderr before, and puts the line in
// a queue. logs_writer alone touches the disk. Whoever says a line (the window's thread) writes to the pipe, which
// logs_pump empties whatever the disk does, or copies into the queue: a disk that stalls loses the lines the queue has
// no room for (said once it comes back) and holds nobody up. What is said after the writer's last write, as the process
// ends, gets a moment (logs_end); a crash loses only what the queue held.
//
// Written in the lines' own order and form: `2026-11-04 21:12:33.123 <text>`, in a file opened to append, several
// processes (a window of its own) adding to one file a whole line at a time.
#include <windows.h>
#include <fcntl.h>
#include <io.h>
#include <objbase.h>
#include <shellapi.h>
#include <shlobj.h>
#include <knownfolders.h>
#include <stdio.h>
#include <stdlib.h>
#include "log_files.h"

enum { LOGS_LOG = 0, LOGS_PERF = 1, LOGS_STREAMS = 2 };
static const char *const logs_prefix[LOGS_STREAMS] = {"log", "perf"};
#define LOGS_KEPT 3
#define LOGS_QUEUE_BYTES (1u << 20)
#define LOGS_TICK_MS 5000

// (a test's smaller: scripts/win_logs_test.c)
static volatile unsigned long long logs_file_most = 5ull << 20;

typedef struct {
  HANDLE file;
  char name[LF_NAME_MOST];
  int counts_perf;
} logs_stream;

static WCHAR logs_dir[MAX_PATH * 2];
static volatile LONG logs_running;
static SRWLOCK logs_lock = SRWLOCK_INIT;
static CONDITION_VARIABLE logs_wake = CONDITION_VARIABLE_INIT;
static unsigned char logs_ring[LOGS_QUEUE_BYTES];
static lf_queue logs_q = {logs_ring, LOGS_QUEUE_BYTES, 0, 0, 0};
static volatile LONG logs_writing;      // the writer has a line out of the queue
static volatile LONG logs_writer_held;  // a test's stalled disk
static HANDLE logs_pipe_r, logs_pipe_w;
// A byte said through the pipe to learn that all before it has come out (logs_settled). Nothing else can tell: the
// pipe's read end is the pump's, and on a handle a ReadFile is waiting on, PeekNamedPipe waits too, however empty.
#define LOGS_MARK '\x01'
static volatile LONG logs_marks_said, logs_marks_passed;
static HANDLE logs_before = INVALID_HANDLE_VALUE;  // whoever had stderr before: given it all as it comes

// each tick (the writer's thread): what the host has to say of itself; and that perf's bytes changed
static void (*logs_on_tick)(void);
static void (*logs_on_written)(void);

static volatile LONG logs_perf_on;
static volatile LONG logs_marker_to;  // the switch's file to be made to match: 1 on, 2 off (the writer's to do)
static volatile LONG logs_perf_opening;  // "perf: on" still to be said
static const char *volatile logs_perf_why = "started";
static volatile double logs_perf_bytes;

// A line said (any thread), its time now: into the queue, at no cost of the disk's.
static void logs_line(int stream, const char *text, size_t n) {
  if (!InterlockedCompareExchange(&logs_running, 1, 1)) return;
  FILETIME now;
  GetSystemTimeAsFileTime(&now);
  uint64_t when = ((uint64_t)now.dwHighDateTime << 32) | now.dwLowDateTime;
  AcquireSRWLockExclusive(&logs_lock);
  lf_push(&logs_q, stream, when, text, n);
  ReleaseSRWLockExclusive(&logs_lock);
  WakeConditionVariable(&logs_wake);
}

// The same of what a MoonBit string holds: as much as a line can.
static void logs_line_wide(int stream, const WCHAR *s, int n) {
  char u[LF_LINE_MOST];
  if (n > LF_LINE_MOST / 3) n = LF_LINE_MOST / 3;
  int bytes = WideCharToMultiByte(CP_UTF8, 0, s, n, u, sizeof u, NULL, NULL);
  if (bytes > 0) logs_line(stream, u, (size_t)bytes);
}

// ---- the writer's thread: the disk ----

// logs_dir\<what>, as the system's
static void logs_path(WCHAR *out, size_t cap, const char *what) {
  _snwprintf(out, cap, L"%ls\\%hs", logs_dir, what);
  out[cap - 1] = 0;
}

// What's in the folder of a stream's files, their sizes.
static int logs_list(const char *prefix, lf_file *files) {
  WCHAR pattern[MAX_PATH * 2];
  char wild[32];
  snprintf(wild, sizeof wild, "%s-*.log", prefix);
  logs_path(pattern, MAX_PATH * 2, wild);
  WIN32_FIND_DATAW d;
  HANDLE h = FindFirstFileW(pattern, &d);
  if (h == INVALID_HANDLE_VALUE) return 0;
  int count = 0;
  do {
    int u = WideCharToMultiByte(CP_UTF8, 0, d.cFileName, -1, files[count].name, LF_NAME_MOST, NULL, NULL);
    if (u <= 0) continue;
    files[count].bytes = ((unsigned long long)d.nFileSizeHigh << 32) | d.nFileSizeLow;
    count++;
  } while (count < LF_FILES_MOST && FindNextFileW(h, &d));
  FindClose(h);
  return count;
}

// The files beyond the newest few removed. (A file another process still has open goes when it lets it go: shared
// for deleting as it is opened.)
static void logs_prune(const char *prefix) {
  lf_file files[LF_FILES_MOST];
  int count = logs_list(prefix, files);
  for (int guard = 0; guard < LF_FILES_MOST; guard++) {
    int i = lf_oldest(files, count, prefix, LOGS_KEPT);
    if (i < 0) break;
    WCHAR path[MAX_PATH * 2];
    logs_path(path, MAX_PATH * 2, files[i].name);
    DeleteFileW(path);
    files[i] = files[--count];
  }
}

// The perf stream's files' bytes counted, for the app (mb_host_perf_size).
static void logs_count_perf(void) {
  lf_file files[LF_FILES_MOST];
  int count = logs_list(logs_prefix[LOGS_PERF], files);
  double total = 0;
  for (int i = 0; i < count; i++) {
    unsigned d, s;
    if (lf_parse(files[i].name, logs_prefix[LOGS_PERF], &d, &s)) total += (double)files[i].bytes;
  }
  logs_perf_bytes = total;
}

static int logs_folder_made(void) {
  int r = SHCreateDirectoryExW(NULL, logs_dir, NULL);
  return r == ERROR_SUCCESS || r == ERROR_ALREADY_EXISTS || r == ERROR_FILE_EXISTS;
}

// The handle `n` bytes of the stream go to on `day`: the one open while it holds them within a file's most (asked of
// the file, as another process may be adding to it), else the one lf_pick says, those beyond the newest removed.
static HANDLE logs_file_for(logs_stream *st, const char *prefix, unsigned day, size_t n) {
  if (st->file) {
    unsigned d, s;
    LARGE_INTEGER size;
    if (lf_parse(st->name, prefix, &d, &s) && d == day && GetFileSizeEx(st->file, &size) &&
        (unsigned long long)size.QuadPart + n <= logs_file_most)
      return st->file;
    CloseHandle(st->file);
    st->file = NULL;
  }
  if (!logs_folder_made()) return NULL;
  lf_file files[LF_FILES_MOST];
  int count = logs_list(prefix, files);
  char name[LF_NAME_MOST];
  int fresh = lf_pick(files, count, prefix, day, logs_file_most, n, name);
  WCHAR path[MAX_PATH * 2];
  logs_path(path, MAX_PATH * 2, name);
  HANDLE f = CreateFileW(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_ALWAYS,
                         FILE_ATTRIBUTE_NORMAL, NULL);
  if (f == INVALID_HANDLE_VALUE) return NULL;
  st->file = f;
  lstrcpynA(st->name, name, LF_NAME_MOST);
  if (fresh) {
    logs_prune(prefix);
    if (st->counts_perf) logs_count_perf();
  }
  return f;
}

// A line written: cleaned (log_clean), its time before it. Never on stderr, whatever goes wrong: that would come back.
static void logs_write(logs_stream *streams, int stream, uint64_t when, const char *text, size_t n) {
  static char clean[LF_LINE_MOST + 64];
  size_t c = log_clean(text, n, clean, LF_LINE_MOST);
  if (!c) return;
  FILETIME utc = {(DWORD)when, (DWORD)(when >> 32)}, local;
  SYSTEMTIME t;
  if (!FileTimeToLocalFileTime(&utc, &local) || !FileTimeToSystemTime(&local, &t)) return;
  char at[32];
  int a = snprintf(at, sizeof at, "%04d-%02d-%02d %02d:%02d:%02d.%03d ", t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond, t.wMilliseconds);
  // (one write, so that another process's lines do not come in within it)
  static char whole[LF_LINE_MOST + 96];
  memcpy(whole, at, (size_t)a);
  memcpy(whole + a, clean, c);
  whole[(size_t)a + c] = '\n';
  DWORD bytes = (DWORD)a + (DWORD)c + 1, wrote = 0;
  HANDLE f = logs_file_for(&streams[stream], logs_prefix[stream], (unsigned)t.wYear * 10000 + t.wMonth * 100 + t.wDay, bytes);
  if (!f || !WriteFile(f, whole, bytes, &wrote, NULL)) return;
  if (stream == LOGS_PERF) {
    logs_perf_bytes = logs_perf_bytes + wrote;
    if (logs_on_written) logs_on_written();
  }
}

// The switch's file made to match it (asked of the window's thread, where a disk is not to be waited for).
static void logs_marker(void) {
  LONG to = InterlockedExchange(&logs_marker_to, 0);
  if (!to) return;
  WCHAR path[MAX_PATH * 2];
  logs_path(path, MAX_PATH * 2, "perf-on");
  if (to == 1) {
    if (!logs_folder_made()) return;
    HANDLE f = CreateFileW(path, GENERIC_WRITE, 0, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (f != INVALID_HANDLE_VALUE) CloseHandle(f);
  } else {
    DeleteFileW(path);
  }
}

static DWORD WINAPI logs_writer(LPVOID unused) {
  (void)unused;
  static logs_stream streams[LOGS_STREAMS];
  static char line[LF_LINE_MOST];
  streams[LOGS_PERF].counts_perf = 1;
  logs_count_perf();
  if (logs_on_written) logs_on_written();
  ULONGLONG next_tick = GetTickCount64() + LOGS_TICK_MS;
  uint64_t told_dropped = 0;
  for (;;) {
    while (InterlockedCompareExchange(&logs_writer_held, 1, 1)) Sleep(1);
    int kind = 0, got;
    uint64_t when = 0, dropped;
    AcquireSRWLockExclusive(&logs_lock);
    got = lf_pop(&logs_q, &kind, &when, line);
    dropped = logs_q.dropped;
    if (got < 0 && dropped == told_dropped && !logs_marker_to && !logs_perf_opening) {
      ULONGLONG now = GetTickCount64();
      if (now < next_tick) {
        InterlockedExchange(&logs_writing, 0);
        SleepConditionVariableSRW(&logs_wake, &logs_lock, (DWORD)(next_tick - now), 0);
      }
    }
    InterlockedExchange(&logs_writing, got >= 0);
    ReleaseSRWLockExclusive(&logs_lock);
    logs_marker();
    if (dropped != told_dropped) {
      char lost[96];
      FILETIME now;
      GetSystemTimeAsFileTime(&now);
      int n = snprintf(lost, sizeof lost, "logs: %llu lines lost: the disk was behind", (unsigned long long)(dropped - told_dropped));
      logs_write(streams, LOGS_LOG, ((uint64_t)now.dwHighDateTime << 32) | now.dwLowDateTime, lost, (size_t)n);
      told_dropped = dropped;
    }
    if (got >= 0) logs_write(streams, kind, when, line, (size_t)got);
    InterlockedExchange(&logs_writing, 0);
    if (InterlockedExchange(&logs_perf_opening, 0)) {
      char said[128];
      int n = snprintf(said, sizeof said, "perf: on (%s) pid=%lu", logs_perf_why, GetCurrentProcessId());
      logs_line(LOGS_PERF, said, (size_t)n);
    }
    ULONGLONG now = GetTickCount64();
    if (now >= next_tick) {
      next_tick = now + LOGS_TICK_MS;
      if (logs_on_tick) logs_on_tick();
    }
  }
}

// ---- the pump's thread: stderr ----

// Whole lines of what was read go in the queue; what is left of one stays at the start of `held` (its length back). A
// line past a line's most goes in as it is, the rest of it another line.
static size_t logs_lines_out(char *held, size_t n) {
  size_t from = 0;
  for (size_t i = 0; i < n; i++) {
    if (held[i] != '\n') continue;
    size_t e = i;
    if (e > from && held[e - 1] == '\r') e--;  // (the C runtime's text mode's)
    if (e > from) logs_line(LOGS_LOG, held + from, e - from);
    from = i + 1;
  }
  memmove(held, held + from, n - from);
  n -= from;
  if (n == LF_LINE_MOST) {
    logs_line(LOGS_LOG, held, n);
    n = 0;
  }
  return n;
}

static DWORD WINAPI logs_pump(LPVOID unused) {
  (void)unused;
  static char held[LF_LINE_MOST];
  size_t n = 0;
  for (;;) {
    DWORD got = 0;
    if (!ReadFile(logs_pipe_r, held + n, (DWORD)(LF_LINE_MOST - n), &got, NULL) || !got) return 0;
    // (the marks taken out: nobody said them)
    LONG marks = 0;
    DWORD kept = 0;
    for (DWORD i = 0; i < got; i++) {
      if (held[n + i] == LOGS_MARK) marks++;
      else held[n + kept++] = held[n + i];
    }
    // (whoever gave this program its stderr reads it as it did, and if it stops reading, this waits as a writer did;
    // the queue holds what the writer has yet to do)
    if (kept && logs_before != INVALID_HANDLE_VALUE) {
      DWORD wrote;
      WriteFile(logs_before, held + n, kept, &wrote, NULL);
    }
    n = logs_lines_out(held, n + kept);
    if (marks) InterlockedExchangeAdd(&logs_marks_passed, marks);
  }
}

// stderr a pipe, both ways of writing to it (the C runtime's, stderr's own stream and descriptor; the system's handle,
// as the engine's and shell's Rust ask for it each time): 1 where it now is. A GUI program's stderr may be nothing: it
// is given a descriptor first. What had it before kept to give it on, none of the handles handed to children.
static int logs_stderr_piped(void) {
  HANDLE r, w;
  if (!CreatePipe(&r, &w, NULL, 64 * 1024)) return 0;
  int fd = _open_osfhandle((intptr_t)w, _O_WRONLY | _O_TEXT);
  if (fd < 0) {
    CloseHandle(r);
    CloseHandle(w);
    return 0;
  }
  fflush(stderr);
  int now = _fileno(stderr);
  if (now >= 0) {
    int was = _dup(now);
    if (was >= 0) {
      HANDLE before = (HANDLE)_get_osfhandle(was);
      if (before != INVALID_HANDLE_VALUE && GetFileType(before) != FILE_TYPE_UNKNOWN) {
        logs_before = before;
        SetHandleInformation(before, HANDLE_FLAG_INHERIT, 0);
      } else {
        _close(was);
      }
    }
  } else {
    FILE *f;
    if (freopen_s(&f, "NUL", "w", stderr) != 0) {
      _close(fd);
      CloseHandle(r);
      return 0;
    }
    now = _fileno(stderr);
  }
  if (now < 0 || _dup2(fd, now) != 0) {
    CloseHandle(r);
    _close(fd);
    logs_before = INVALID_HANDLE_VALUE;
    return 0;
  }
  SetHandleInformation((HANDLE)_get_osfhandle(now), HANDLE_FLAG_INHERIT, 0);
  setvbuf(stderr, NULL, _IONBF, 0);
  SetStdHandle(STD_ERROR_HANDLE, w);
  logs_pipe_r = r;
  logs_pipe_w = w;
  return 1;  // (fd and w stay open as long as the program runs)
}

// (a thread of its own: writing to stderr may wait on whoever reads what it gives on, and nobody here is to wait for that)
static DWORD WINAPI logs_mark_thread(LPVOID unused) {
  (void)unused;
  fflush(stderr);
  char mark = LOGS_MARK;
  DWORD wrote;
  WriteFile(logs_pipe_w, &mark, 1, &wrote, NULL);
  return 0;
}

// Whether everything said before this is on the disk, within `most_ms`.
static int logs_settled(DWORD most_ms) {
  LONG want = 0;
  if (logs_pipe_w) {
    want = InterlockedIncrement(&logs_marks_said);
    HANDLE t = CreateThread(NULL, 0, logs_mark_thread, NULL, 0, NULL);
    if (t) CloseHandle(t);
    else want = 0;
  }
  ULONGLONG until = GetTickCount64() + most_ms;
  for (;;) {
    AcquireSRWLockShared(&logs_lock);
    size_t used = logs_q.used;
    ReleaseSRWLockShared(&logs_lock);
    if (InterlockedCompareExchange(&logs_marks_passed, 0, 0) >= want && !used && !InterlockedCompareExchange(&logs_writing, 0, 0)) return 1;
    if (GetTickCount64() >= until) return 0;
    Sleep(1);
  }
}

// As the process ends: a moment for what was said just before it, then on, however far that got.
static void __cdecl logs_end(void) { logs_settled(300); }

// Begun (once, as the process starts), the files in `dir`; on_tick called each few seconds by the writer's thread;
// on_written as the record has grown, on the same (it tells the window's thread). Nothing kept where the threads do
// not start.
static void logs_begin(const WCHAR *dir, void (*on_tick)(void), void (*on_written)(void)) {
  lstrcpynW(logs_dir, dir, MAX_PATH * 2);
  logs_on_tick = on_tick;
  logs_on_written = on_written;
  WCHAR marker[MAX_PATH * 2];
  logs_path(marker, MAX_PATH * 2, "perf-on");
  if (GetFileAttributesW(marker) != INVALID_FILE_ATTRIBUTES) {
    logs_perf_on = 1;
    logs_perf_opening = 1;
  }
  InterlockedExchange(&logs_running, 1);
  HANDLE writer = CreateThread(NULL, 0, logs_writer, NULL, 0, NULL);
  if (!writer) {
    InterlockedExchange(&logs_running, 0);
    return;
  }
  CloseHandle(writer);
  if (logs_stderr_piped()) {
    HANDLE pump = CreateThread(NULL, 0, logs_pump, NULL, 0, NULL);
    if (pump) CloseHandle(pump);
  }
  char said[64];
  int n = snprintf(said, sizeof said, "logs: begun, pid=%lu", GetCurrentProcessId());
  logs_line(LOGS_LOG, said, (size_t)n);
  atexit(logs_end);
}

// ---- the performance record's switch ----

static int32_t logs_perf_state(void) {
  return !InterlockedCompareExchange(&logs_running, 1, 1) ? -1 : logs_perf_on ? 1 : 0;
}

// Kept from now on, or no longer, and from the next launch so: remembered by a file (made by the writer's thread).
static void logs_set_perf(int on) {
  if (!InterlockedCompareExchange(&logs_running, 1, 1) || (on != 0) == (logs_perf_on != 0)) return;
  if (on) {
    logs_perf_why = "turned on";
    logs_perf_on = 1;
    logs_perf_opening = 1;
  } else {
    logs_line(LOGS_PERF, "perf: off", 9);
    logs_perf_on = 0;
  }
  InterlockedExchange(&logs_marker_to, on ? 1 : 2);
  WakeConditionVariable(&logs_wake);
}

// ---- the folder opened ----

static DWORD WINAPI logs_open_thread(LPVOID unused) {
  (void)unused;
  HRESULT co = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  if (logs_folder_made()) ShellExecuteW(NULL, L"open", logs_dir, NULL, NULL, SW_SHOWNORMAL);
  if (SUCCEEDED(co)) CoUninitialize();
  return 0;
}

// The folder in Explorer, off the window's thread (making it and starting Explorer may each take a while).
static int logs_open(void) {
  if (!InterlockedCompareExchange(&logs_running, 1, 1)) return 0;
  HANDLE t = CreateThread(NULL, 0, logs_open_thread, NULL, 0, NULL);
  if (!t) return 0;
  CloseHandle(t);
  return 1;
}
