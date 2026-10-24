// exit() while the core's thread is in a task (src/host/apple_core.mm's stop_at_exit), with core/exit-test.js in the
// core's place: the script's task tells this program it runs, and the program holds it there, on the core's thread,
// until exit() has begun. Built and run by `scripts/core.sh exit`.
//   exit_test <data dir>        (MB_CORE_BUNDLE: core/exit-test.js)
// Exit 0 when the core's thread had ended before what atexit was given before the core started ran: the destructors
// of the core's statics (its mutex, its queues), registered as the program loaded, come after that. Exit 1 when it
// was still going then (it went on into a destroyed mutex: abort, or freed memory: SIGSEGV, and macOS said the app
// had crashed); 3 when the script's task never came.
#import <Foundation/Foundation.h>
#include <pthread.h>
#include <stdatomic.h>
#include <unistd.h>
#include "core_api.h"

static dispatch_semaphore_t in_task, go_on;
static pthread_key_t core_thread;
static atomic_int ended, failed;

// the core's thread's end (its thread-specific value's destructor)
static void thread_ended(void *v) { atomic_store(&ended, 1); }

static void on_message(const char *json, size_t len, const uint8_t *bytes, size_t blen, void *ctx) {
  printf("<- %.*s\n", (int)len, json);
  fflush(stdout);
  NSDictionary *m = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:json length:len] options:0 error:nil];
  if (m[@"running"]) {
    pthread_setspecific(core_thread, (void *)1);
    dispatch_semaphore_signal(in_task);
    dispatch_semaphore_wait(go_on, DISPATCH_TIME_FOREVER);
  } else if (m[@"fatal"]) {
    atomic_store(&failed, 1);
    dispatch_semaphore_signal(in_task);
  }
}

// atexit's, the first to run: the task the core is held in goes on as exit() does
static void release(void) { dispatch_semaphore_signal(go_on); }

// atexit's, given before the core started: after the core's own, before anything is destroyed
static void check(void) {
  int ok = atomic_load(&ended);
  printf("%s the core's thread had ended before exit() went on to destroy anything\n", ok ? "ok  " : "FAIL");
  printf("result %s\n", ok ? "OK" : "FAILED");
  fflush(stdout);
  _exit(ok ? 0 : 1);
}

int main(int argc, char **argv) {
  @autoreleasepool {
    if (argc < 2) {
      fprintf(stderr, "usage: exit_test <data dir>\n");
      return 2;
    }
    in_task = dispatch_semaphore_create(0);
    go_on = dispatch_semaphore_create(0);
    pthread_key_create(&core_thread, thread_ended);
    atexit(check);
    mb_core_start(argv[1], "https://example.invalid", 0, on_message, NULL);
    const char *say = "{\"n\":1}";
    mb_core_send(say, strlen(say), NULL, 0);
    if (dispatch_semaphore_wait(in_task, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC)) || atomic_load(&failed)) {
      printf("FAIL the script's task came (in 20 s, the core not failed)\nresult FAILED\n");
      fflush(stdout);
      _exit(3);
    }
    printf("ok   the core's thread is in a task; exit()\n");
    fflush(stdout);
    atexit(release);
    exit(0);
  }
}
