// src/host/win_logs.h's tests, the system's side of the log files, on Windows (log_files_test.c tests what is plain C):
//   cl -nologo -W3 -Isrc/host scripts/win_logs_test.c -Feout/win_logs_test.exe && out/win_logs_test.exe 2>out/win_logs_stderr.txt
// (mbui-host-windows.yml; its stderr then read for what it gave on.) What it waits for it waits for by its state; a
// watcher fails the run where a state does not come, or a writer to stderr hangs: that is the failure looked for.
#include "win_logs.h"
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "advapi32.lib")

static int failed;
#define CHECK(c)                                                        \
  do {                                                                  \
    if (!(c)) {                                                         \
      printf("%s:%d: failed: %s\n", __FILE__, __LINE__, #c);            \
      fflush(stdout);                                                   \
      failed = 1;                                                       \
    }                                                                   \
  } while (0)

static WCHAR dir[MAX_PATH];

static const char *volatile stage = "start";
static DWORD watch_ms = 110000;
static ULONGLONG began;
static void at(const char *what) {
  stage = what;
  printf("win_logs: %.1f s: %s\n", (double)(GetTickCount64() - began) / 1000.0, what);
  fflush(stdout);
}

// What a hang was in: where the test had got to, and how the threads stand.
static DWORD WINAPI watcher(LPVOID unused) {
  (void)unused;
  Sleep(watch_ms);
  printf("win_logs_test: hung at \"%s\": queued=%zu dropped=%llu writing=%ld held=%ld marks=%ld/%ld\n", stage, logs_q.used,
         (unsigned long long)logs_q.dropped, logs_writing, logs_writer_held, logs_marks_passed, logs_marks_said);
  fflush(stdout);
  ExitProcess(2);
}

// Everything said so far is on the disk.
static void all_written(void) {
  while (!logs_settled(5000)) {}
}

// All the stream's files' text, in order of their names; how many files; the largest.
static char *read_stream(const char *prefix, int *count, unsigned long long *largest) {
  lf_file files[LF_FILES_MOST];
  *count = 0;
  *largest = 0;
  int n = logs_list(prefix, files);
  size_t cap = 1 << 16, used = 0;
  char *all = malloc(cap);
  all[0] = 0;
  for (;;) {
    int next = -1;
    for (int i = 0; i < n; i++)
      if (files[i].name[0] && (next < 0 || strcmp(files[i].name, files[next].name) < 0)) next = i;
    if (next < 0) break;
    (*count)++;
    if (files[next].bytes > *largest) *largest = files[next].bytes;
    WCHAR path[MAX_PATH * 2];
    logs_path(path, MAX_PATH * 2, files[next].name);
    HANDLE f = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, 0, NULL);
    CHECK(f != INVALID_HANDLE_VALUE);
    for (;;) {
      if (cap - used < 4097) all = realloc(all, cap *= 2);
      DWORD got = 0;
      if (!ReadFile(f, all + used, 4096, &got, NULL) || !got) break;
      used += got;
    }
    all[used] = 0;
    CloseHandle(f);
    files[next].name[0] = 0;
  }
  return all;
}

static void written_until(const char *prefix, const char *text) {
  for (;;) {
    all_written();
    int count;
    unsigned long long largest;
    char *all = read_stream(prefix, &count, &largest);
    int there = strstr(all, text) != NULL;
    free(all);
    if (there) return;
    Sleep(2);
  }
}

static volatile LONG told;
static void on_written(void) { InterlockedIncrement(&told); }

// As the app is run from the Start menu: no console, no stderr at all to take over; the record on from the run before.
static int no_stderr_run(const WCHAR *given) {
  if (_fileno(stderr) >= 0) return 3;  // (not the case this is for)
  // (its own hang ended before its parent's watcher, its exit said there)
  logs_begin(given, NULL, NULL);
  CHECK(logs_perf_state() == 1);
  fprintf(stderr, "no console line\n");
  const char *sys = "no console handle line\n";
  DWORD wrote;
  WriteFile(GetStdHandle(STD_ERROR_HANDLE), sys, (DWORD)strlen(sys), &wrote, NULL);
  written_until("log", "no console line");
  written_until("log", "no console handle line");
  written_until("perf", "perf: on (started)");
  return failed;
}

static void no_stderr_child(void) {
  WCHAR child[MAX_PATH], exe[MAX_PATH], marker[MAX_PATH], line[MAX_PATH * 3];
  _snwprintf(child, MAX_PATH, L"%ls-child", dir);
  CHECK(SHCreateDirectoryExW(NULL, child, NULL) == ERROR_SUCCESS);
  _snwprintf(marker, MAX_PATH, L"%ls\\perf-on", child);
  CloseHandle(CreateFileW(marker, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, 0, NULL));
  GetModuleFileNameW(NULL, exe, MAX_PATH);
  _snwprintf(line, MAX_PATH * 3, L"\"%ls\" \"%ls\"", exe, child);
  STARTUPINFOW si = {sizeof si};
  si.dwFlags = STARTF_USESTDHANDLES;
  PROCESS_INFORMATION pi;
  CHECK(CreateProcessW(exe, line, NULL, NULL, FALSE, DETACHED_PROCESS, NULL, NULL, &si, &pi));
  WaitForSingleObject(pi.hProcess, INFINITE);
  DWORD code = 99;
  GetExitCodeProcess(pi.hProcess, &code);
  printf("win_logs: with no stderr: exit %lu\n", code);
  CHECK(code == 0);
}

int wmain(int argc, WCHAR **argv) {
  began = GetTickCount64();
  if (argc > 1) watch_ms = 50000;
  CloseHandle(CreateThread(NULL, 0, watcher, NULL, 0, NULL));
  if (argc > 1) return no_stderr_run(argv[1]);
  WCHAR tmp[MAX_PATH];
  GetTempPathW(MAX_PATH, tmp);
  _snwprintf(dir, MAX_PATH, L"%lsmbui-logs-%lu\\logs", tmp, GetCurrentProcessId());
  logs_begin(dir, NULL, on_written);
  CHECK(logs_perf_state() == 0);
  at("begun");

  // the C runtime's, and the system's handle as Rust's asks for it; what must not be kept is not; nor the whole of a
  // developer's trace; and what had stderr before has it all as it was (the workflow reads that file)
  fprintf(stderr, "crt line password=hunter2\n");
  DWORD wrote;
  const char *sys = "handle line https://a.example/p?token=hunter3\n";
  WriteFile(GetStdHandle(STD_ERROR_HANDLE), sys, (DWORD)strlen(sys), &wrote, NULL);
  fprintf(stderr, "[core trace] says hunter4\n");
  logs_line(LOGS_LOG, "said ana@example.org", 20);
  fprintf(stderr, "the last of these\n");
  written_until("log", "the last of these");
  int count;
  unsigned long long largest;
  char *all = read_stream("log", &count, &largest);
  CHECK(strstr(all, "logs: begun") != NULL);
  CHECK(strstr(all, "crt line password=<cut>") != NULL);
  CHECK(strstr(all, "handle line https://a.example/<cut>") != NULL);
  CHECK(strstr(all, "said <email>") != NULL);
  CHECK(strstr(all, "hunter") == NULL);
  CHECK(strstr(all, "example.org") == NULL);
  // each line with the time before it, on one line of its own
  CHECK(strstr(all, ".") != NULL && all[4] == '-' && all[10] == ' ');
  CHECK(strstr(all, "\r") == NULL);
  free(all);

  at("lines read back");
  // kept in a stream of its own, remembered, its bytes told to the app
  logs_set_perf(1);
  at("perf on");
  CHECK(logs_perf_state() == 1);
  logs_line(LOGS_PERF, "frames: fps=60", 14);
  written_until("perf", "frames: fps=60");
  WCHAR marker[MAX_PATH * 2];
  logs_path(marker, MAX_PATH * 2, "perf-on");
  while (GetFileAttributesW(marker) == INVALID_FILE_ATTRIBUTES) Sleep(1);
  CHECK(logs_perf_bytes > 0);
  CHECK(InterlockedCompareExchange(&told, 0, 0) > 0);
  logs_set_perf(0);
  CHECK(logs_perf_state() == 0);
  while (GetFileAttributesW(marker) != INVALID_FILE_ATTRIBUTES) Sleep(1);
  written_until("perf", "perf: off");

  at("perf off");
  // to any length: the newest few, each at most its most, the newest lines the last's
  logs_file_most = 4000;
  char line[100];
  memset(line, 'x', sizeof line);
  for (int i = 0; i < 3000; i++) {
    int n = snprintf(line, sizeof line, "rotate %05d ", i);
    line[n] = 'x';
    line[80] = '\n';
    fwrite(line, 1, 81, stderr);
  }
  fprintf(stderr, "rotated all\n");
  at("rotating said");
  written_until("log", "rotated all");
  at("rotated");
  all = read_stream("log", &count, &largest);
  CHECK(count == LOGS_KEPT);
  CHECK(largest <= 4000);
  CHECK(strstr(all, "rotate 02999") != NULL);
  CHECK(strstr(all, "rotate 00000") == NULL);
  free(all);
  logs_file_most = 5ull << 20;

  // a disk that stalls holds up nobody: while the writer writes nothing, more than the pipe and the queue hold goes to
  // stderr without a wait (or the watcher ends this), and lines are lost and said to be, once it writes again
  InterlockedExchange(&logs_writer_held, 1);
  WakeConditionVariable(&logs_wake);
  static char block[4000];
  memset(block, 'y', sizeof block);
  block[sizeof block - 1] = '\n';
  for (int i = 0; i < (int)((LOGS_QUEUE_BYTES / sizeof block) * 3); i++) fwrite(block, 1, sizeof block, stderr);
  for (;;) {
    AcquireSRWLockShared(&logs_lock);
    uint64_t dropped = logs_q.dropped;
    ReleaseSRWLockShared(&logs_lock);
    if (dropped) break;
    Sleep(1);
  }
  at("stalled, lines dropped, nobody held up");
  InterlockedExchange(&logs_writer_held, 0);
  WakeConditionVariable(&logs_wake);
  fprintf(stderr, "after the stall\n");
  written_until("log", "after the stall");
  all = read_stream("log", &count, &largest);
  CHECK(strstr(all, "lines lost: the disk was behind") != NULL);
  CHECK(count <= LOGS_KEPT);
  free(all);

  at("after the stall");
  no_stderr_child();
  if (failed) return 1;
  printf("win_logs: ok\n");
  fflush(stdout);
  return 0;
}
