// The core in Hermes (src/host/apple_core.mm, the engine Android's is) opening chats from what the device holds
// (client/core-ts/bench/chat-open.ts seeds the data directory): from `subscribe` to the chat's first value, the first
// time (cold), again a moment after it was let go (warm), and after the core let its view go (evicted).
//   chatopen <data dir>        (MB_CORE_BUNDLE: the core's script)
#import <Foundation/Foundation.h>
#include <time.h>
#include "core_api.h"

static double t0;
static dispatch_semaphore_t got;
static volatile int want = -1;
static double sent_at, got_ms;
static size_t got_bytes;
static int got_error;
static int list_rows;
static dispatch_semaphore_t list_got;

static double now_ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (double)t.tv_sec * 1000.0 + (double)t.tv_nsec / 1e6;
}

static void on_message(const char *json, size_t len, const uint8_t *bytes, size_t blen, void *ctx) {
  double at = now_ms();
  // {"id":N,… without parsing the whole: the id is first
  int id = -1;
  if (len > 6 && strncmp(json, "{\"id\":", 6) == 0) id = atoi(json + 6);
  if (id == 1 && list_rows == 0 && strstr(json, "\"value\"")) {
    list_rows = 1;
    dispatch_semaphore_signal(list_got);
  }
  if (id >= 0 && id == want && (strstr(json, "\"value\"") || strstr(json, "\"error\""))) {
    want = -1;
    got_ms = at - sent_at;
    got_bytes = len;
    char head[32];
    int n = snprintf(head, sizeof head, "{\"id\":%d,\"error\"", id);
    got_error = len >= (size_t)n && strncmp(json, head, (size_t)n) == 0;
    if (got_error) printf("error: %.*s\n", (int)(len > 400 ? 400 : len), json);
    dispatch_semaphore_signal(got);
  }
}

static void tell(NSString *json) {
  NSData *d = [json dataUsingEncoding:NSUTF8StringEncoding];
  mb_core_send(d.bytes, d.length, NULL, 0);
}

static void pause_ms(double ms) {
  dispatch_semaphore_wait(dispatch_semaphore_create(0), dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ms * NSEC_PER_MSEC)));
}

static int next_id = 100;

static void round_of(const char *name) {
  printf("%s:", name);
  for (int i = 0; i < 10; i++) {
    int id = next_id++;
    want = id;
    sent_at = now_ms();
    tell([NSString stringWithFormat:@"{\"id\":%d,\"subscribe\":{\"topic\":\"chat\",\"station\":\"w/s00\",\"session\":\"k%d\"},\"keyed\":true}", id, i]);
    long late = dispatch_semaphore_wait(got, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    if (late) printf(" k%d:LATE", i);
    else printf(" k%d:%.1fms/%zuKB%s", i, got_ms, got_bytes / 1024, got_error ? "!" : "");
    fflush(stdout);
    tell([NSString stringWithFormat:@"{\"id\":%d,\"unsubscribe\":true}", id]);
    pause_ms(300);
  }
  printf("\n");
}

int main(int argc, char **argv) {
  @autoreleasepool {
    if (argc < 2) {
      fprintf(stderr, "usage: chatopen <data dir>\n");
      return 2;
    }
    got = dispatch_semaphore_create(0);
    list_got = dispatch_semaphore_create(0);
    t0 = now_ms();
    mb_core_start(argv[1], "http://127.0.0.1:9", 0, on_message, NULL);
    tell(@"{\"id\":1,\"subscribe\":{\"topic\":\"chats\",\"scope\":\"w\",\"mine\":false},\"keyed\":true}");
    dispatch_semaphore_wait(list_got, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC));
    printf("chat list's first value %.0f ms after start\n", now_ms() - t0);
    pause_ms(8000);
    round_of("cold");
    round_of("warm");
    pause_ms(62000);
    round_of("evicted");
    mb_core_stop();
    return 0;
  }
}
