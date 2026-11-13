// The station's MoonBit programs' host: one queue of what comes from outside (the parent's lines on stdin, the shell's
// answers from its threads), waited on by the program's one thread (sfh_wait), and the shell (client/shell) it asks.
// Nothing here calls into MoonBit: the program takes each event from the queue in its own loop (host.mbt).
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "moonbit.h"

#ifdef _WIN32
#include <windows.h>
#include <shellapi.h>
typedef SRWLOCK lock_t;
typedef CONDITION_VARIABLE cond_t;
#define LOCK_INIT SRWLOCK_INIT
#define COND_INIT CONDITION_VARIABLE_INIT
static void lock(lock_t *l) { AcquireSRWLockExclusive(l); }
static void unlock(lock_t *l) { ReleaseSRWLockExclusive(l); }
static void signal_one(cond_t *c) { WakeConditionVariable(c); }
#else
#include <pthread.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#ifdef __APPLE__
#include <crt_externs.h>
#endif
typedef pthread_mutex_t lock_t;
typedef pthread_cond_t cond_t;
#define LOCK_INIT PTHREAD_MUTEX_INITIALIZER
#define COND_INIT PTHREAD_COND_INITIALIZER
static void lock(lock_t *l) { pthread_mutex_lock(l); }
static void unlock(lock_t *l) { pthread_mutex_unlock(l); }
static void signal_one(cond_t *c) { pthread_cond_signal(c); }
#endif

// client/shell's C ABI (client/shell/src/lib.rs).
typedef void (*sf_complete)(void *, uint64_t, const uint8_t *, size_t, const uint8_t *, size_t, const uint8_t *, size_t, uint8_t);
void *sf_shell_start(const char *data_dir, sf_complete complete, void *ctx);
void sf_shell_call(const void *shell, uint64_t id, const char *op, const uint8_t *json, size_t json_len, const uint8_t *bytes, size_t bytes_len, uint8_t has_bytes);
uint8_t *sf_shell_call_sync(const void *shell, const char *op, const uint8_t *json, size_t json_len, size_t *out_len);
void sf_free(uint8_t *ptr, size_t len);

/// What came: kind 1 a piece of stdin, 2 stdin's end, 3 the shell's answer to call `id` (its JSON, then its error).
typedef struct event {
  struct event *next;
  uint8_t kind;
  uint64_t id;
  uint8_t *data;
  size_t len;
} event_t;

static lock_t queue_lock = LOCK_INIT;
static cond_t queue_cond = COND_INIT;
static event_t *head = NULL, *tail = NULL;
static void *shell = NULL;

static void push(uint8_t kind, uint64_t id, const uint8_t *a, size_t al, const uint8_t *b, size_t bl) {
  event_t *e = malloc(sizeof *e);
  e->next = NULL;
  e->kind = kind;
  e->id = id;
  e->len = al + bl;
  e->data = malloc(e->len ? e->len : 1);
  if (al) memcpy(e->data, a, al);
  if (bl) memcpy(e->data + al, b, bl);
  lock(&queue_lock);
  if (tail) tail->next = e; else head = e;
  tail = e;
  signal_one(&queue_cond);
  unlock(&queue_lock);
}

// The shell's answer, from any of its threads: its error and its JSON, each after its length (8 bytes), then whether it
// carries bytes (1 byte) and the bytes.
static void put_len(uint8_t *at, size_t n) {
  for (int i = 0; i < 8; i++) at[i] = (uint8_t)((uint64_t)n >> (8 * i));
}

static void completed(void *ctx, uint64_t id, const uint8_t *json, size_t jl, const uint8_t *error, size_t el, const uint8_t *bytes, size_t bl, uint8_t has) {
  (void)ctx;
  size_t carried = has ? bl : 0;
  size_t len = 8 + el + 8 + jl + 1 + carried;
  uint8_t *all = malloc(len), *at = all;
  put_len(at, el);
  at += 8;
  if (el) memcpy(at, error, el);
  at += el;
  put_len(at, jl);
  at += 8;
  if (jl) memcpy(at, json, jl);
  at += jl;
  *at++ = has ? 1 : 0;
  if (carried) memcpy(at, bytes, carried);
  push(3, id, all, len, NULL, 0);
  free(all);
}

#ifdef _WIN32
static DWORD WINAPI read_input(LPVOID arg) {
  (void)arg;
  HANDLE in = GetStdHandle(STD_INPUT_HANDLE);
  uint8_t buf[65536];
  DWORD n;
  while (ReadFile(in, buf, sizeof buf, &n, NULL) && n > 0) push(1, 0, buf, n, NULL, 0);
  push(2, 0, NULL, 0, NULL, 0);
  return 0;
}
#else
static void *read_input(void *arg) {
  (void)arg;
  uint8_t buf[65536];
  for (;;) {
    ssize_t n = read(0, buf, sizeof buf);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) break;
    push(1, 0, buf, (size_t)n, NULL, 0);
  }
  push(2, 0, NULL, 0, NULL, 0);
  return NULL;
}
#endif

#ifndef _WIN32
// Raises the soft open-file limit from macOS launchd's 256 (even if started by an older launcher before renew).
static void raise_nofile(void) {
  struct rlimit limit;
  if (getrlimit(RLIMIT_NOFILE, &limit) != 0) return;
  rlim_t most = 65536;
  rlim_t cap = (limit.rlim_max == RLIM_INFINITY || limit.rlim_max > most) ? most : limit.rlim_max;
  rlim_t targets[3] = { cap, cap < 10240 ? cap : 10240, cap < 4096 ? cap : 4096 };
  for (int i = 0; i < 3; i++) {
    if (targets[i] <= limit.rlim_cur) return;
    struct rlimit next = { targets[i], limit.rlim_max };
    if (setrlimit(RLIMIT_NOFILE, &next) == 0) return;
  }
}
#endif

/// Starts reading stdin, and the shell keeping its own files in `dir` (none when `dir` is empty). False: the shell did not
/// start.
int32_t sfh_start(moonbit_bytes_t dir) {
#ifndef _WIN32
  raise_nofile();
#endif
  if (Moonbit_array_length(dir) > 1) {
    shell = sf_shell_start((const char *)dir, completed, NULL);
    if (shell == NULL) return 0;
  }
#ifdef _WIN32
  HANDLE t = CreateThread(NULL, 0, read_input, NULL, 0, NULL);
  if (t) CloseHandle(t);
#else
  pthread_t t;
  pthread_create(&t, NULL, read_input, NULL);
  pthread_detach(t);
#endif
  return 1;
}

/// The next event (kind, id as 8 bytes, then what it carries), waiting at most `ms` (negative: until there is one).
/// Empty: none came in time.
moonbit_bytes_t sfh_wait(int64_t ms) {
  lock(&queue_lock);
  if (head == NULL && ms != 0) {
#ifdef _WIN32
    SleepConditionVariableSRW(&queue_cond, &queue_lock, ms < 0 ? INFINITE : (DWORD)ms, 0);
#else
    if (ms < 0) {
      while (head == NULL) pthread_cond_wait(&queue_cond, &queue_lock);
    } else {
      struct timespec at;
      clock_gettime(CLOCK_REALTIME, &at);
      at.tv_sec += ms / 1000;
      at.tv_nsec += (ms % 1000) * 1000000;
      if (at.tv_nsec >= 1000000000) { at.tv_sec += 1; at.tv_nsec -= 1000000000; }
      while (head == NULL && pthread_cond_timedwait(&queue_cond, &queue_lock, &at) != ETIMEDOUT) {}
    }
#endif
  }
  event_t *e = head;
  if (e) {
    head = e->next;
    if (head == NULL) tail = NULL;
  }
  unlock(&queue_lock);
  if (e == NULL) return moonbit_make_bytes(0, 0);
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)(9 + e->len), 0);
  out[0] = e->kind;
  for (int i = 0; i < 8; i++) out[1 + i] = (uint8_t)(e->id >> (8 * i));
  if (e->len) memcpy(out + 9, e->data, e->len);
  free(e->data);
  free(e);
  return out;
}

/// Writes all of `b` to stdout.
int32_t sfh_out(moonbit_bytes_t b) {
  size_t len = (size_t)Moonbit_array_length(b), done = 0;
  while (done < len) {
#ifdef _WIN32
    DWORD n;
    if (!WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), b + done, (DWORD)(len - done), &n, NULL)) return 0;
#else
    ssize_t n = write(1, b + done, len - done);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) return 0;
#endif
    done += (size_t)n;
  }
  return 1;
}

/// A clock that never goes back, in ms.
int64_t sfh_now(void) {
#ifdef _WIN32
  return (int64_t)GetTickCount64();
#else
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (int64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000;
#endif
}

/// The shell's answer at once to `op` (NUL-terminated) with `json`: {"value": …} or {"error": …}.
moonbit_bytes_t sfh_shell_sync(moonbit_bytes_t op, moonbit_bytes_t json) {
  if (shell == NULL) {
    static const char none[] = "{\"error\":\"no shell\"}";
    moonbit_bytes_t out = moonbit_make_bytes(sizeof none - 1, 0);
    memcpy(out, none, sizeof none - 1);
    return out;
  }
  size_t n = 0;
  uint8_t *answer = sf_shell_call_sync(shell, (const char *)op, json, (size_t)Moonbit_array_length(json), &n);
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)n, 0);
  if (n) memcpy(out, answer, n);
  sf_free(answer, n);
  return out;
}

/// Asks the shell `op` (NUL-terminated) with `json` and, where `has` says so, `bytes`; its answer comes as event `id`.
void sfh_shell_call(int64_t id, moonbit_bytes_t op, moonbit_bytes_t json, moonbit_bytes_t bytes, int32_t has) {
  if (shell == NULL) {
    static const char none[] = "no shell";
    completed(NULL, (uint64_t)id, NULL, 0, (const uint8_t *)none, sizeof none - 1, NULL, 0, 0);
    return;
  }
  sf_shell_call(shell, (uint64_t)id, (const char *)op, json, (size_t)Moonbit_array_length(json), bytes, (size_t)Moonbit_array_length(bytes), has ? 1 : 0);
}

/// The program's arguments in UTF-8, each ended by a NUL: as the system has them, not as the MoonBit runtime takes them
/// (its strings of the system are its platform's, fixed where the program's C was made: on the Mac for every target).
moonbit_bytes_t sfh_args(void) {
  size_t len = 0;
  char *all = NULL;
#if defined(_WIN32)
  int argc = 0;
  LPWSTR *argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  for (int i = 0; argv != NULL && i < argc; i++) {
    int n = WideCharToMultiByte(CP_UTF8, 0, argv[i], -1, NULL, 0, NULL, NULL);
    if (n <= 0) continue;
    all = realloc(all, len + (size_t)n);
    WideCharToMultiByte(CP_UTF8, 0, argv[i], -1, all + len, n, NULL, NULL);
    len += (size_t)n;
  }
  if (argv != NULL) LocalFree(argv);
#elif defined(__APPLE__)
  int argc = *_NSGetArgc();
  char **argv = *_NSGetArgv();
  for (int i = 0; i < argc; i++) {
    size_t n = strlen(argv[i]) + 1;
    all = realloc(all, len + n);
    memcpy(all + len, argv[i], n);
    len += n;
  }
#else
  FILE *f = fopen("/proc/self/cmdline", "rb");
  if (f != NULL) {
    char buf[4096];
    size_t n;
    while ((n = fread(buf, 1, sizeof buf, f)) > 0) {
      all = realloc(all, len + n);
      memcpy(all + len, buf, n);
      len += n;
    }
    fclose(f);
  }
#endif
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)len, 0);
  if (len) memcpy(out, all, len);
  free(all);
  return out;
}

/// This process's id.
int32_t sfh_pid(void) {
#ifdef _WIN32
  return (int32_t)GetCurrentProcessId();
#else
  return (int32_t)getpid();
#endif
}
