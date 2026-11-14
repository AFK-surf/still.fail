// The C side of this package: the shell's C interface (client/shell, a static library the program is linked
// to) as MoonBit calls it. The shell answers a call from one of its own threads; each answer is put on one queue here,
// and the program's one thread takes them from it between the turns of its runtime (shell.mbt `Shell::pump`). Nothing
// here calls into MoonBit.
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include "moonbit.h"

// The shell's C interface (client/shell/src/lib.rs).
typedef void (*sf_complete)(void *, uint64_t, const uint8_t *, size_t, const uint8_t *, size_t, const uint8_t *, size_t, uint8_t);
void *sf_shell_start(const char *data_dir, sf_complete complete, void *ctx);
void sf_shell_call(const void *shell, uint64_t id, const char *op, const uint8_t *json, size_t json_len, const uint8_t *bytes, size_t bytes_len, uint8_t has_bytes);
uint8_t *sf_shell_call_sync(const void *shell, const char *op, const uint8_t *json, size_t json_len, size_t *out_len);
void sf_free(uint8_t *ptr, size_t len);

/// One answer as MoonBit reads it (shell.mbt `Shell::answered`): the call's id (8 bytes, the low first), its kind (0 its
/// JSON alone, 1 its JSON and bytes, 2 its error), the length of the JSON or the error (4 bytes, the low first), that
/// text, then the bytes.
typedef struct answer {
  struct answer *next;
  size_t len;
  uint8_t data[];
} answer_t;

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t came = PTHREAD_COND_INITIALIZER;
static answer_t *first = NULL, *last = NULL;
static void *shell = NULL;

static void completed(void *ctx, uint64_t id, const uint8_t *json, size_t json_len, const uint8_t *error, size_t error_len, const uint8_t *bytes, size_t bytes_len, uint8_t has_bytes) {
  (void)ctx;
  const uint8_t *text = error_len > 0 ? error : json;
  size_t text_len = error_len > 0 ? error_len : json_len;
  size_t carried = error_len == 0 && has_bytes ? bytes_len : 0;
  answer_t *a = malloc(sizeof *a + 13 + text_len + carried);
  a->next = NULL;
  a->len = 13 + text_len + carried;
  for (int i = 0; i < 8; i++) a->data[i] = (uint8_t)(id >> (8 * i));
  a->data[8] = error_len > 0 ? 2 : has_bytes ? 1 : 0;
  for (int i = 0; i < 4; i++) a->data[9 + i] = (uint8_t)((uint32_t)text_len >> (8 * i));
  if (text_len) memcpy(a->data + 13, text, text_len);
  if (carried) memcpy(a->data + 13 + text_len, bytes, carried);
  pthread_mutex_lock(&lock);
  if (last) last->next = a; else first = a;
  last = a;
  pthread_cond_signal(&came);
  pthread_mutex_unlock(&lock);
}

/// Starts the shell, keeping what it keeps in `dir` (NUL-terminated): 1, or 0 where it did not start. What it keeps
/// there is this device's alone (its key): the shell writes each value it keeps as a file of its user's only, whatever
/// the process's umask, which is the program's and is not touched here. The directory is its user's only where it
/// was not there and the shell made it (what the shell made over it is as the umask has it: nothing is kept there);
/// one that was there is left as it is.
int32_t bsh_start(moonbit_bytes_t dir) {
  if (shell != NULL) return 1;
  struct stat was;
  int made = stat((const char *)dir, &was) != 0;
  shell = sf_shell_start((const char *)dir, completed, NULL);
  if (shell != NULL && made) (void)chmod((const char *)dir, 0700);
  return shell != NULL;
}

/// The next answer, waited for at most `ms` (negative: until one comes); empty where none came in time.
moonbit_bytes_t bsh_wait(int64_t ms) {
  pthread_mutex_lock(&lock);
  if (first == NULL && ms != 0) {
    if (ms < 0) {
      while (first == NULL) pthread_cond_wait(&came, &lock);
    } else {
      struct timespec until;
      clock_gettime(CLOCK_REALTIME, &until);
      until.tv_sec += ms / 1000;
      until.tv_nsec += (ms % 1000) * 1000000;
      if (until.tv_nsec >= 1000000000) {
        until.tv_sec += 1;
        until.tv_nsec -= 1000000000;
      }
      while (first == NULL && pthread_cond_timedwait(&came, &lock, &until) != ETIMEDOUT) {}
    }
  }
  answer_t *a = first;
  if (a) {
    first = a->next;
    if (first == NULL) last = NULL;
  }
  pthread_mutex_unlock(&lock);
  if (a == NULL) return moonbit_make_bytes(0, 0);
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)a->len, 0);
  memcpy(out, a->data, a->len);
  free(a);
  return out;
}

/// Asks the shell `op` (NUL-terminated) with `json` and, where `has` says so, `bytes`: answered later, as `id`.
void bsh_call(int64_t id, moonbit_bytes_t op, moonbit_bytes_t json, moonbit_bytes_t bytes, int32_t has) {
  if (shell == NULL) {
    static const char none[] = "the shell is not started";
    completed(NULL, (uint64_t)id, NULL, 0, (const uint8_t *)none, sizeof none - 1, NULL, 0, 0);
    return;
  }
  sf_shell_call(shell, (uint64_t)id, (const char *)op, json, (size_t)Moonbit_array_length(json), bytes, (size_t)Moonbit_array_length(bytes), has ? 1 : 0);
}

/// The shell's answer at once to `op` (NUL-terminated) with `json`: `{"value": …}` or `{"error": …}`.
moonbit_bytes_t bsh_ask(moonbit_bytes_t op, moonbit_bytes_t json) {
  if (shell == NULL) {
    static const char none[] = "{\"error\":\"the shell is not started\"}";
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

/// A clock that never goes back, in ms.
int64_t bsh_now(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (int64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

/// `n` bytes of the system's randomness.
moonbit_bytes_t bsh_random(int32_t n) {
  moonbit_bytes_t out = moonbit_make_bytes(n, 0);
  arc4random_buf(out, (size_t)n);
  return out;
}
