// The core in Hermes (src/host/apple_core.mm, the engine Android's is) on two workspaces of real size
// (client/core-ts/bench/ws-switch-seed.ts seeds the data directory): Home of one shown, then the other switched to as
// the app does it (what it sends, in its order). For each switch: how long after it each of Home's topics is first
// answered, what follows of them, and how long something cheap asked 10, 30, 60 and 90 ms after it waits (what the
// core is busy with then keeps every later ask waiting so).
//   wsswitch <data dir>        (MB_CORE_BUNDLE: the core's script; AWAY_MS: how long away before the last switch)
#import <Foundation/Foundation.h>
#include <os/lock.h>
#include <time.h>
#include "core_api.h"

#define MOST 4096
#define ASKS 4
static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
static struct { double at; int id; size_t len; int value, delta; } got[MOST];
static int got_n;
static double t0;
static const double ask_at[ASKS] = {10, 30, 60, 90};
static double asked[ASKS];

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
  size_t head = len < 64 ? len : 64;
  os_unfair_lock_lock(&lock);
  if (got_n < MOST) {
    got[got_n].at = at;
    got[got_n].id = id;
    got[got_n].len = len;
    got[got_n].value = memmem(json, head, "\"value\"", 7) != NULL;
    got[got_n].delta = memmem(json, head, "\"delta\"", 7) != NULL;
    got_n++;
  }
  os_unfair_lock_unlock(&lock);
}

static void tell(NSString *json) {
  NSData *d = [json dataUsingEncoding:NSUTF8StringEncoding];
  mb_core_send(d.bytes, d.length, NULL, 0);
}

static void pause_ms(double ms) {
  dispatch_semaphore_wait(dispatch_semaphore_create(0), dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ms * NSEC_PER_MSEC)));
}

// What Home holds of a workspace (src/sfapp: its list, the bar's marks, the stations and profiles its places open on).
static const char *names[] = {"lock", "longJobs", "chats", "workspaceMarks", "workspace", "stations", "profiles", "driveTransfers", "status", "notify"};
#define TOPICS 10
static NSArray<NSString *> *home(NSString *ws) {
  return @[
    [NSString stringWithFormat:@"{\"topic\":\"lock\",\"workspace\":\"%@\"}", ws],
    [NSString stringWithFormat:@"{\"topic\":\"longJobs\",\"scope\":\"%@\"}", ws],
    [NSString stringWithFormat:@"{\"topic\":\"chats\",\"scope\":\"%@\",\"mine\":false,\"limit\":50}", ws],
    [NSString stringWithFormat:@"{\"topic\":\"workspaceMarks\",\"workspace\":\"%@\"}", ws],
    [NSString stringWithFormat:@"{\"topic\":\"workspace\",\"workspace\":\"%@\"}", ws],
    [NSString stringWithFormat:@"{\"topic\":\"stations\",\"scope\":\"%@\"}", ws],
    [NSString stringWithFormat:@"{\"topic\":\"profiles\",\"scope\":\"%@\"}", ws],
    [NSString stringWithFormat:@"{\"topic\":\"driveTransfers\",\"workspace\":\"%@\"}", ws],
    [NSString stringWithFormat:@"{\"topic\":\"status\",\"workspace\":\"%@\"}", ws],
    [NSString stringWithFormat:@"{\"topic\":\"notify\",\"workspace\":\"%@\"}", ws],
  ];
}

static int next = 100;
static int held_from = -1;

static void show(const char *label, NSString *ws, int first) {
  int from = next;
  next += 100;
  os_unfair_lock_lock(&lock);
  got_n = 0;
  os_unfair_lock_unlock(&lock);
  t0 = now_ms();
  if (!first) tell([NSString stringWithFormat:@"{\"id\":%d,\"call\":\"prefs.set\",\"params\":{\"workspace\":\"%@\"}}", from + 90, ws]);
  NSArray<NSString *> *topics = home(ws);
  for (int i = 0; i < TOPICS; i++) tell([NSString stringWithFormat:@"{\"id\":%d,\"subscribe\":%@,\"keyed\":true}", from + i, topics[i]]);
  if (held_from >= 0) for (int i = 0; i < TOPICS; i++) tell([NSString stringWithFormat:@"{\"id\":%d,\"unsubscribe\":true}", held_from + i]);
  tell([NSString stringWithFormat:@"{\"id\":%d,\"call\":\"client.focus\",\"params\":{\"visible\":true,\"focused\":true,\"workspace\":\"%@\"}}", from + 91, ws]);
  // Something cheap asked later (`doing`, held since the start: answered from what the core holds). Spun to its
  // moment, not slept to: a sleep ends when the system likes, tens of ms late where the program is in no window.
  for (int k = 0; k < ASKS; k++) {
    while (now_ms() - t0 < ask_at[k]) {}
    asked[k] = now_ms();
    tell([NSString stringWithFormat:@"{\"id\":%d,\"subscribe\":{\"topic\":\"doing\"},\"keyed\":true}", from + 70 + k]);
  }
  pause_ms(1500);
  for (int k = 0; k < ASKS; k++) tell([NSString stringWithFormat:@"{\"id\":%d,\"unsubscribe\":true}", from + 70 + k]);
  printf("== %s: %s\n", label, ws.UTF8String);
  os_unfair_lock_lock(&lock);
  double waited[ASKS] = {-1, -1, -1, -1};
  for (int i = 0; i < got_n; i++) {
    int k = got[i].id - from;
    // (what is said each second after, a station's waits: not the switch's)
    if (got[i].at - t0 > 1000) continue;
    if (k >= 70 && k < 70 + ASKS) {
      if (waited[k - 70] < 0) waited[k - 70] = got[i].at - asked[k - 70];
      continue;
    }
    if (k < 0 || k >= TOPICS || !(got[i].value || got[i].delta)) continue;
    printf("  +%7.1f ms  %-5s %-16s %7zu B\n", got[i].at - t0, got[i].value ? "value" : "delta", names[k], got[i].len);
  }
  os_unfair_lock_unlock(&lock);
  for (int k = 0; k < ASKS; k++) printf("  asked at +%2.0f ms: waited %5.1f ms\n", ask_at[k], waited[k]);
  fflush(stdout);
  held_from = from;
}

int main(int argc, char **argv) {
  @autoreleasepool {
    if (argc < 2) {
      fprintf(stderr, "usage: wsswitch <data dir>\n");
      return 2;
    }
    double away = getenv("AWAY_MS") ? atof(getenv("AWAY_MS")) : 70000;
    mb_core_start(argv[1], "http://127.0.0.1:9", 0, on_message, NULL);
    tell(@"{\"id\":1,\"subscribe\":{\"topic\":\"doing\"},\"keyed\":true}");
    tell(@"{\"id\":2,\"subscribe\":{\"topic\":\"prefs\"},\"keyed\":true}");
    show("as the app starts", @"ws", 1);
    // (long enough for what the start set going to be over: the links' first tries, the rows read behind the list)
    pause_ms(6000);
    show("the other workspace, the first time this run", @"ws2", 0);
    pause_ms(3000);
    show("back within seconds", @"ws", 0);
    if (away > 0) {
      pause_ms(away);
      show("the other again, after the core let it go", @"ws2", 0);
    }
    mb_core_stop();
    return 0;
  }
}
