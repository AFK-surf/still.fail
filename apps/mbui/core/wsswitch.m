// The core in Hermes (src/host/apple_core.mm, the engine Android's is) on two workspaces of real size
// (client/core-ts/bench/ws-switch-seed.ts seeds the data directory), asked what the app asks as it starts on one and is
// switched to the other (src/sfbase/workspace_switch.mbt). At the press the app keeps the screen as it was and only
// holds what the new workspace's first screen opens on (小屏: sfapp's home_opens; 大屏: sfdesk's frame_opens, the page
// its pane lands on asked at the press, as the workspaces' marks held since the start say it); once all of that is answered (or switch_wait_ms passed) it
// commits: prefs.set, what the new screen asks besides, the old screen's topics let go of. The messages and their order
// are the app's own client's, captured in the Tester (2026-11-11); what it keeps of a topic it lets go of (a chat, the
// lists a place opens on: kept_name) let go of with `keep` and asked again with `have`, as the app's client is told to
// as it starts (src/stillfail's main: sfbase's topic_kept), a Tester's not. For each switch: when each value comes,
// how long the person waits (`waited`: press to all it waits for answered) and when the new screen is whole (`quiet`:
// press to the last first value of what the commit asked).
//   wsswitch <data dir>   MB_CORE_BUNDLE: the core's script; SCREEN=small|wide (small); LIMIT: the list's first
//                         window (30, sfbase first_window on both screens); CHAT_ROWS: a chat's (30, chat_first_window;
//                         0: none told, its untold page); AWAY_MS: how long away before the last switch;
//                         STATIONS=up: the stations up (the seed's `link` records, as a device last found them) and the
//                         network never answering (still.fail cloud at 192.0.2.1, TEST-NET-1, which nothing routes),
//                         so each link stays as a device's is as the app starts, on its way and taken for up (link.ts),
//                         until it gives up some seconds on (mesh.ts's dial): the switches within seconds of the start
//                         find them up, the last one, after AWAY_MS, down; else (down) refused at once, every station
//                         down and a new chat's page saying so
#import <Foundation/Foundation.h>
#include <math.h>
#include <os/lock.h>
#include <time.h>
#include "core_api.h"

#define MOST 8192
static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
// (each message as the core hands it over, its text kept for what an answer leads to: workspaceMarks' chat)
static struct { double at; int id; size_t len; int value, delta, error, waiting, same; char *text; } got[MOST];
static int got_n;
static dispatch_semaphore_t told;

static double now_ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (double)t.tv_sec * 1000.0 + (double)t.tv_nsec / 1e6;
}

// What the app's client keeps of a topic as it lets it go (sfbase's topic_kept, @core.Client::keep): a chat however it
// is asked, and the lists a place opens on (sfbase's `lasting`) asked with no `q`. Let go of with `keep`, the core
// answers `{id, v}`, the version of what it sent; asked again, the topic says it (`have`) and is answered `same` where
// it is that still, what changed from it where it is not (client/core-ts store.ts #first). Each kept by the topic as
// asked, the version the core said.
static int kept_name(const char *name) {
  static const char *names[] = {"chat", "workspace", "stations", "stationNet", "profiles", "connects", "vaults", "usage", "archive", NULL};
  for (int i = 0; names[i]; i++)
    if (strcmp(names[i], name) == 0) return 1;
  return 0;
}
#define KEPT 64
static struct { int id; char topic[512]; char v[128]; } kept[KEPT];
static int kept_n;

// (`{"id":N,"v":"…"}`: the version of what a subscription let go of with `keep` holds, put by its topic)
static void kept_said(const char *json, size_t len, int id) {
  const char *v = memmem(json, len < 64 ? len : 64, "\"v\":\"", 5);
  if (!v) return;
  v += 5;
  const char *end = memchr(v, '"', len - (size_t)(v - json));
  if (!end) return;
  for (int i = 0; i < kept_n; i++) {
    if (kept[i].id != id) continue;
    snprintf(kept[i].v, sizeof kept[i].v, "%.*s", (int)(end - v), v);
    kept[i].id = -1;
  }
}

static void on_message(const char *json, size_t len, const uint8_t *bytes, size_t blen, void *ctx) {
  double at = now_ms();
  // {"id":N,… without parsing the whole: the id is first
  int id = -1;
  if (len > 6 && strncmp(json, "{\"id\":", 6) == 0) id = atoi(json + 6);
  size_t head = len < 64 ? len : 64;
  os_unfair_lock_lock(&lock);
  kept_said(json, len, id);
  os_unfair_lock_unlock(&lock);
  char *text = NULL;
  if (len < 256 * 1024) {
    text = malloc(len + 1);
    memcpy(text, json, len);
    text[len] = 0;
  }
  os_unfair_lock_lock(&lock);
  if (got_n < MOST) {
    got[got_n].at = at;
    got[got_n].id = id;
    got[got_n].len = len;
    got[got_n].value = memmem(json, head, "\"value\"", 7) != NULL;
    got[got_n].delta = memmem(json, head, "\"delta\"", 7) != NULL;
    got[got_n].error = memmem(json, head, "\"error\"", 7) != NULL;
    got[got_n].waiting = memmem(json, head, "\"waiting\"", 9) != NULL;
    got[got_n].same = memmem(json, head, "\"same\"", 6) != NULL;
    got[got_n].text = text;
    got_n++;
    text = NULL;
  }
  os_unfair_lock_unlock(&lock);
  free(text);
  dispatch_semaphore_signal(told);
}

static void tell(NSString *json) {
  NSData *d = [json dataUsingEncoding:NSUTF8StringEncoding];
  mb_core_send(d.bytes, d.length, NULL, 0);
}

static int wide_screen;
static int limit;
static int next = 100;

// What a screen holds: each subscription by its topic's name, why it was asked (at the press and waited for, asked as
// an answer led to it and waited for, the commit's, the start's) and when its first value came.
enum { HELD, FOLLOW, COMMIT, START };
static const char *roles[] = {"held", "follow", "commit", "start"};
typedef struct {
  int id, role;
  char name[24];
  char topic[512];
  double asked, first;
  size_t len;
  int same;
} Sub;
#define SUBS 64
static Sub subs[SUBS], prev[SUBS];
static int subs_n, prev_n;
static double t0;

static void sub(const char *name, int role, NSString *topic) {
  Sub *s = &subs[subs_n++];
  s->id = next++;
  s->role = role;
  snprintf(s->name, sizeof s->name, "%s", name);
  snprintf(s->topic, sizeof s->topic, "%s", topic.UTF8String);
  s->asked = now_ms() - t0;
  s->first = -1;
  // (kept as it was let go of: asked again with its version)
  char have[160] = "";
  os_unfair_lock_lock(&lock);
  for (int i = 0; i < kept_n; i++)
    if (kept[i].id < 0 && kept[i].v[0] && strcmp(kept[i].topic, s->topic) == 0) snprintf(have, sizeof have, ",\"have\":\"%s\"", kept[i].v);
  os_unfair_lock_unlock(&lock);
  tell([NSString stringWithFormat:@"{\"id\":%d,\"subscribe\":%@,\"keyed\":true%s}", s->id, topic, have]);
}

static void call(NSString *name, NSString *params) {
  tell([NSString stringWithFormat:@"{\"id\":%d,\"call\":\"%@\",\"params\":%@}", next++, name, params]);
}

static void call_ws(const char *topic, int role, NSString *ws, const char *key) {
  sub(topic, role, [NSString stringWithFormat:@"{\"topic\":\"%s\",\"%s\":\"%@\"}", topic, key, ws]);
}

// The list (its window told before it, as the app's client tells it: sfbase's chats_told_before).
static void list_of(NSString *ws, int role) {
  call(@"chats.window", [NSString stringWithFormat:@"{\"scope\":\"%@\",\"mine\":false,\"rows\":%d}", ws, limit]);
  sub("chats", role, [NSString stringWithFormat:@"{\"topic\":\"chats\",\"scope\":\"%@\",\"mine\":false}", ws]);
}

// The page the wide frame's pane lands on (sfdesk's land_page): the chat workspaceMarks says was open last there, else
// a new chat. The seed's chat (ws-switch-seed.ts: openChat of ws2) is the real-size fixture's CHAT, thread 1001, its
// last page held (entries 251 to 300): what the app reads of its view to say its thread and the last seen (`seen`).
static char land_station[64], land_key[64];
static const int land_thread = 1001, land_seen = 300;
static int left_chat;
static char left_station[64], left_key[64];

// The workspaces' marks as the app asks them (sfbase's marks_asked: one topic whichever workspace is shown), asked as
// the app starts and held across every switch; their value as it first came, what a switch's pane lands by.
#define MARKS @"{\"topic\":\"workspaceMarks\"}"
static char *marks_text;

static void land_from(const char *text, NSString *ws) {
  land_station[0] = land_key[0] = 0;
  if (!text) return;
  NSDictionary *m = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:text length:strlen(text)] options:0 error:nil];
  NSDictionary *chat = m[@"value"][@"workspaces"][ws][@"chat"];
  if (![chat isKindOfClass:[NSDictionary class]] || ![chat[@"station"] isKindOfClass:[NSString class]] || ![chat[@"key"] isKindOfClass:[NSString class]]) return;
  snprintf(land_station, sizeof land_station, "%s", [chat[@"station"] UTF8String]);
  snprintf(land_key, sizeof land_key, "%s", [chat[@"key"] UTF8String]);
}

// What the pane's page asks once workspaceMarks named it: a chat's view (how many of its last messages it opens on told
// before it, as the app's client tells it: sfbase's chat_first_window, CHAT_ROWS, 30 on 大屏), or the workspace's new
// chat.
static int chat_rows;
static void land(NSString *ws, int role, int start) {
  if (land_station[0]) {
    if (chat_rows > 0) call(@"chat.window", [NSString stringWithFormat:@"{\"station\":\"%s\",\"session\":\"%s\",\"rows\":%d}", land_station, land_key, chat_rows]);
    sub("chat", role, [NSString stringWithFormat:@"{\"topic\":\"chat\",\"station\":\"%s\",\"session\":\"%s\",\"compact\":true}", land_station, land_key]);
  } else {
    call_ws("newChat", role, ws, "scope");
    // (as the app starts, the new chat's page says so as it is pushed)
    if (start) call(@"client.focus", [NSString stringWithFormat:@"{\"visible\":true,\"focused\":true,\"workspace\":\"%@\",\"newChat\":\"%@\"}", ws, ws]);
  }
}

// What the old screen held, let go of in the order the app's client lets go of it.
// (the workspaces' marks, one topic whichever is shown, held all along: never let go of at a switch)
static const char *small_order[] = {"notify", "driveTransfers", "longJobs", "workspace", "stations", "profiles", "chats", "status", "lock", NULL};
static const char *wide_order[] = {"lock", "notify", "chatJobs", "stations", "composer", "chatFeedback", "chatOutline", "newChat", "chat", "chatRow", "driveTransfers", "status", "longJobs", "chats", NULL};
static int rank(const char *name) {
  const char **order = wide_screen ? wide_order : small_order;
  for (int i = 0; order[i]; i++)
    if (strcmp(order[i], name) == 0) return i;
  return 99;
}
// (one the app keeps let go of with `keep`, its version taken as the core says it: kept_said)
static void let_go(Sub *s) {
  int keep = kept_name(s->name) && !strstr(s->topic, "\"q\":");
  if (keep) {
    os_unfair_lock_lock(&lock);
    int at = -1;
    for (int i = 0; i < kept_n; i++)
      if (strcmp(kept[i].topic, s->topic) == 0) at = i;
    if (at < 0 && kept_n < KEPT) at = kept_n++;
    if (at >= 0) {
      kept[at].id = s->id;
      kept[at].v[0] = 0;
      snprintf(kept[at].topic, sizeof kept[at].topic, "%s", s->topic);
    }
    os_unfair_lock_unlock(&lock);
  }
  tell([NSString stringWithFormat:@"{\"id\":%d,\"unsubscribe\":true%s}", s->id, keep ? ",\"keep\":true" : ""]);
}

// (the device's own, changelog among them, are not the screen's: kept)
static void let_go_prev(void) {
  for (int r = 0; r < 99; r++)
    for (int i = 0; i < prev_n; i++)
      if (rank(prev[i].name) == r) let_go(&prev[i]);
  prev_n = 0;
}

// The switch done (workspace_switch.mbt's switch_pick): the prefs said, the new screen's tree made and asking what it
// shows besides, the old screen's let go of. The held subscriptions are the new screen's from here (handed over, no
// message).
static void commit(NSString *ws) {
  call(@"prefs.set", [NSString stringWithFormat:@"{\"workspace\":\"%@\"}", ws]);
  if (!wide_screen) {
    call_ws("lock", COMMIT, ws, "workspace");
    call_ws("workspace", COMMIT, ws, "workspace");
    call_ws("stations", COMMIT, ws, "scope");
    call_ws("profiles", COMMIT, ws, "scope");
    call_ws("driveTransfers", COMMIT, ws, "workspace");
    call_ws("status", COMMIT, ws, "workspace");
    call(@"client.focus", [NSString stringWithFormat:@"{\"visible\":true,\"focused\":true,\"workspace\":\"%@\"}", ws]);
    call_ws("notify", COMMIT, ws, "workspace");
  } else {
    call_ws("driveTransfers", COMMIT, ws, "workspace");
    call_ws("status", COMMIT, ws, "workspace");
    call_ws("lock", COMMIT, ws, "workspace");
    if (land_station[0]) {
      NSString *st = @(land_station), *key = @(land_key);
      sub("chatOutline", COMMIT, [NSString stringWithFormat:@"{\"topic\":\"chatOutline\",\"station\":\"%@\",\"thread\":%d}", st, land_thread]);
      sub("chatFeedback", COMMIT, [NSString stringWithFormat:@"{\"topic\":\"chatFeedback\",\"station\":\"%@\",\"session\":\"%@\"}", st, key]);
      sub("composer", COMMIT, [NSString stringWithFormat:@"{\"topic\":\"composer\",\"key\":\"%@:%@\"}", st, key]);
      sub("chatRow", COMMIT, [NSString stringWithFormat:@"{\"topic\":\"chatRow\",\"station\":\"%@\",\"session\":\"%@\"}", st, key]);
      call_ws("stations", COMMIT, ws, "scope");
      sub("chatJobs", COMMIT, [NSString stringWithFormat:@"{\"topic\":\"chatJobs\",\"station\":\"%@\",\"session\":\"%@\",\"summary\":true,\"compact\":true}", st, key]);
      call(@"client.focus", [NSString stringWithFormat:@"{\"visible\":true,\"focused\":true,\"workspace\":\"%@\"}", ws]);
      call_ws("notify", COMMIT, ws, "workspace");
      call(@"chat.place", [NSString stringWithFormat:@"{\"station\":\"%@\",\"thread\":%d}", st, land_thread]);
      call(@"client.focus", [NSString stringWithFormat:@"{\"chat\":{\"station\":\"%@\",\"session\":\"%@\",\"thread\":%d,\"end\":true,\"seen\":%d}}", st, key, land_thread, land_seen]);
    } else {
      sub("composer", COMMIT, [NSString stringWithFormat:@"{\"topic\":\"composer\",\"key\":\"new:%@\"}", ws]);
      if (left_chat) call(@"client.focus", [NSString stringWithFormat:@"{\"left\":{\"station\":\"%s\",\"session\":\"%s\",\"thread\":%d}}", left_station, left_key, land_thread]);
      call(@"client.focus", [NSString stringWithFormat:@"{\"visible\":true,\"focused\":true,\"workspace\":\"%@\",\"newChat\":\"%@\"}", ws, ws]);
      call_ws("notify", COMMIT, ws, "workspace");
    }
  }
  let_go_prev();
}

// What the app asks as it starts on `ws` (src/stillfail's main, then the first screen: its shell's opens and the rest it
// shows), less its calls out of the device (notify.permission, push.unregister, paste.info, machineSessions.list).
// The device's own topics (prefs, accounts, workspaces, downloads, changelog on 小屏, doing, lockPrompts, notify) are
// held all along, as the app holds them.
static void start(NSString *ws) {
  tell(@"{\"id\":1,\"subscribe\":{\"topic\":\"prefs\"},\"keyed\":true}");
  tell(@"{\"id\":2,\"subscribe\":{\"topic\":\"accounts\"},\"keyed\":true}");
  tell(@"{\"id\":3,\"subscribe\":{\"topic\":\"workspaces\"},\"keyed\":true}");
  tell(@"{\"id\":4,\"subscribe\":{\"topic\":\"downloads\"},\"keyed\":true}");
  call_ws("lock", START, ws, "workspace");
  if (!wide_screen) {
    call_ws("longJobs", HELD, ws, "scope");
    list_of(ws, HELD);
    sub("changelog", HELD, @"{\"topic\":\"changelog\",\"news\":true}");
    sub("workspaceMarks", START, MARKS);
    call_ws("workspace", START, ws, "workspace");
    call_ws("stations", START, ws, "scope");
    call_ws("profiles", START, ws, "scope");
  } else {
    sub("workspaceMarks", HELD, MARKS);
    list_of(ws, HELD);
    call_ws("longJobs", HELD, ws, "scope");
    call_ws("status", START, ws, "workspace");
    call_ws("driveTransfers", START, ws, "workspace");
  }
  tell(@"{\"id\":5,\"subscribe\":{\"topic\":\"doing\"},\"keyed\":true}");
  if (!wide_screen) {
    call_ws("driveTransfers", START, ws, "workspace");
    call_ws("status", START, ws, "workspace");
  }
  tell(@"{\"id\":6,\"subscribe\":{\"topic\":\"lockPrompts\"},\"keyed\":true}");
  call(@"client.focus", [NSString stringWithFormat:@"{\"visible\":true,\"focused\":true,\"workspace\":\"%@\"}", ws]);
  tell(@"{\"id\":7,\"subscribe\":{\"topic\":\"notify\"},\"keyed\":true}");
  call_ws("notify", START, ws, "workspace");
}

// The press: the screen as it was, only what the new one opens on held (its order the app's client's).
static void press(NSString *ws) {
  if (!wide_screen) {
    list_of(ws, HELD);
    call_ws("longJobs", HELD, ws, "scope");
  } else {
    list_of(ws, HELD);
    call_ws("longJobs", HELD, ws, "scope");
  }
}

static Sub *sub_of(int id) {
  for (int i = 0; i < subs_n; i++)
    if (subs[i].id == id) return &subs[i];
  return NULL;
}

// Whether all that is waited for is answered (and on the wide frame its page asked).
static int all_answered(int asked_land) {
  if (wide_screen && !asked_land) return 0;
  for (int i = 0; i < subs_n; i++)
    if ((subs[i].role == HELD || subs[i].role == FOLLOW) && subs[i].first < 0) return 0;
  return 1;
}

// How long the app waits at most (workspace_switch.mbt switch_wait_ms).
#define SWITCH_WAIT_MS 300.0
#define WATCH_MS 1500.0

static int taken;

static void show(const char *label, NSString *ws, int first) {
  subs_n = 0;
  os_unfair_lock_lock(&lock);
  for (int i = 0; i < got_n; i++) free(got[i].text);
  got_n = 0;
  os_unfair_lock_unlock(&lock);
  taken = 0;
  land_station[0] = land_key[0] = 0;
  int asked_land = 0, done = first && !wide_screen;
  double commit_at = -1;
  t0 = now_ms();
  if (first) start(ws);
  else press(ws);
  printf("== %s: %s (%s)\n", label, ws.UTF8String, wide_screen ? "大屏" : "小屏");
  // (the pane lands by the marks held: what it asks, asked at the press)
  if (!first && wide_screen) {
    land_from(marks_text, ws);
    land(ws, FOLLOW, 0);
    asked_land = 1;
    printf("  +%7.1f ms  asked %s (of the marks held)\n", now_ms() - t0, land_station[0] ? "chat" : "newChat");
  }
  // Each message as it comes: a follow-up asked as its cause is answered, the commit as the last waited is.
  while (now_ms() - t0 < WATCH_MS) {
    dispatch_semaphore_wait(told, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_MSEC)));
    for (;;) {
      os_unfair_lock_lock(&lock);
      int have = got_n;
      os_unfair_lock_unlock(&lock);
      if (taken >= have) break;
      int k = taken++;
      Sub *s = sub_of(got[k].id);
      if (!s) continue;
      double at = got[k].at - t0;
      // (the core saying a topic waits on its station for what it shows: a chat's page opens on it, its messages to
      // come, as sfbase's chat_opens has it; anything else still waits for its value)
      if (got[k].waiting && s->first < 0) {
        printf("  +%7.1f ms  waits on its station: %s [%s]\n", at, s->name, roles[s->role]);
        if (strcmp(s->name, "chat") == 0) s->first = at;
        continue;
      }
      if (!(got[k].value || got[k].delta || got[k].error || got[k].same)) continue;
      if (s->first >= 0) {
        printf("  +%7.1f ms  %-5s %-16s %7zu B\n", at, got[k].delta ? "delta" : "value", s->name, got[k].len);
        continue;
      }
      s->first = at;
      s->len = got[k].len;
      printf("  +%7.1f ms  %-5s %-16s %7zu B  [%s, asked +%.1f]\n", at, got[k].error ? "error" : got[k].same ? "same" : got[k].delta ? "delta" : "value", s->name, got[k].len, roles[s->role], s->asked);
      if (strcmp(s->name, "workspaceMarks") == 0 && got[k].value && got[k].text && !marks_text) marks_text = strdup(got[k].text);
      if (wide_screen && !asked_land && strcmp(s->name, "workspaceMarks") == 0 && s->role == HELD) {
        land_from(got[k].text, ws);
        land(ws, FOLLOW, first);
        asked_land = 1;
        printf("  +%7.1f ms  asked %s\n", now_ms() - t0, land_station[0] ? "chat" : "newChat");
      }
    }
    if (!done && (all_answered(asked_land) || (!first && now_ms() - t0 >= SWITCH_WAIT_MS))) {
      done = 1;
      commit_at = now_ms() - t0;
      if (first) {
        // (as the app starts, the page pushed once answered asks its composer)
        if (land_station[0]) commit(ws);
        else sub("composer", COMMIT, [NSString stringWithFormat:@"{\"topic\":\"composer\",\"key\":\"new:%@\"}", ws]);
      } else commit(ws);
      printf("  +%7.1f ms  committed%s\n", commit_at, all_answered(asked_land) ? "" : " (switch_wait_ms passed)");
    }
  }
  double waited = 0, quiet = 0;
  const char *last_waited = "", *last_quiet = "";
  for (int i = 0; i < subs_n; i++) {
    Sub *s = &subs[i];
    if (s->first < 0) {
      printf("  (none within %.0f ms: %s [%s])\n", WATCH_MS, s->name, roles[s->role]);
      continue;
    }
    if ((s->role == HELD || s->role == FOLLOW) && s->first > waited) waited = s->first, last_waited = s->name;
    if ((s->role == COMMIT || s->role == START) && s->first > quiet) quiet = s->first, last_quiet = s->name;
  }
  printf("  waited: %.1f ms (last: %s)\n", waited, last_waited);
  printf("  quiet: %.1f ms (last: %s)\n", quiet, last_quiet);
  // (the commit goes as the last waited value is handed to the app; the new screen is drawn by the display's next frame,
  // the press's own frame at 0)
  if (commit_at >= 0)
    printf("  committed +%.1f ms: drawn by the frame at +%.1f ms at 60 Hz, +%.1f ms at 120 Hz\n", commit_at,
           ceil(commit_at / (1000.0 / 60)) * (1000.0 / 60), ceil(commit_at / (1000.0 / 120)) * (1000.0 / 120));
  fflush(stdout);
  // (what this screen holds: let go of as the next commits)
  memcpy(prev, subs, sizeof subs);
  prev_n = subs_n;
  left_chat = wide_screen && land_station[0];
  if (left_chat) {
    snprintf(left_station, sizeof left_station, "%s", land_station);
    snprintf(left_key, sizeof left_key, "%s", land_key);
  }
}

// Messages taken as they come between the scenarios, not looked at.
static void idle(double ms) {
  double until = now_ms() + ms;
  while (now_ms() < until) {
    dispatch_semaphore_wait(told, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)));
    os_unfair_lock_lock(&lock);
    for (int i = 0; i < got_n; i++) free(got[i].text);
    got_n = 0;
    os_unfair_lock_unlock(&lock);
  }
}

int main(int argc, char **argv) {
  @autoreleasepool {
    if (argc < 2) {
      fprintf(stderr, "usage: wsswitch <data dir>\n");
      return 2;
    }
    double away = getenv("AWAY_MS") ? atof(getenv("AWAY_MS")) : 70000;
    wide_screen = getenv("SCREEN") && strcmp(getenv("SCREEN"), "wide") == 0;
    limit = getenv("LIMIT") ? atoi(getenv("LIMIT")) : 30;
    chat_rows = getenv("CHAT_ROWS") ? atoi(getenv("CHAT_ROWS")) : 30;
    told = dispatch_semaphore_create(0);
    int up = getenv("STATIONS") && strcmp(getenv("STATIONS"), "up") == 0;
    mb_core_start(argv[1], up ? "http://192.0.2.1:9" : "http://127.0.0.1:9", 0, on_message, NULL);
    show("as the app starts", @"ws", 1);
    // (long enough for what the start set going to be over: the links' first tries, the rows read behind the list)
    idle(6000);
    show("the other workspace, the first time this run", @"ws2", 0);
    idle(3000);
    show("back within seconds", @"ws", 0);
    if (away > 0) {
      idle(away);
      show("the other again, after the core let it go", @"ws2", 0);
    }
    mb_core_stop();
    return 0;
  }
}
