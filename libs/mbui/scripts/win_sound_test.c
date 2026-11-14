// src/host/win_sound.h's tests: Windows' stream sound player's rule over a voice of the test's own, on the test's clock
// (a millisecond a step: what plays, what the app gives, what the player's moment asks, each at its own):
//   cl -nologo -W4 -WX -Isrc/host scripts/win_sound_test.c -Foout/sound/ -Feout/sound/win_sound_test.exe
// (mbui-host-windows.yml). Plain C: any compiler of C runs it the same (clang -Wall -Werror -Isrc/host ...).
#include <stdio.h>
#include <string.h>
#include "win_sound.h"

static int failed;
#define CHECK(c, ...)                                         \
  do {                                                        \
    if (!(c)) {                                               \
      printf("%s:%d: failed: %s: ", __FILE__, __LINE__, #c);  \
      printf(__VA_ARGS__);                                    \
      printf("\n");                                           \
      failed = 1;                                             \
    }                                                         \
  } while (0)

// The voice: its packets queued, whether it runs (started: it plays what is queued, a ms at a time, and goes on
// running dry), how far into the one playing it is, what it played (ms), how often it ran dry while it ran.
typedef struct Voice {
  int queued, running, into, dry;
  double played;
} Voice;

static int v_queued(void *it) { return ((Voice *)it)->queued; }
static int v_submit(void *it, const uint8_t *packet) {
  (void)packet;
  ((Voice *)it)->queued++;
  return 1;
}
static int v_start(void *it) {
  ((Voice *)it)->running = 1;
  return 1;
}
static void v_flush(void *it) {
  Voice *v = (Voice *)it;
  v->running = 0;
  v->queued = 0;
  v->into = 0;
}

// a ms of it played
static void v_step(Voice *v) {
  if (!v->running) return;
  if (!v->queued) {
    v->dry++;
    return;
  }
  v->played++;
  if (++v->into == 20) {
    v->into = 0;
    v->queued--;
  }
}

static const uint8_t packet[3840] = {0};

// A run: the player, its voice, the clock, the moment the player asked for (0: none).
typedef struct Run {
  SoundPlayer p;
  Voice v;
  SoundVoice sv;
  double now, held;
} Run;

static void run_init(Run *r) {
  memset(r, 0, sizeof *r);
  r->sv.it = &r->v;
  r->sv.queued = v_queued;
  r->sv.submit = v_submit;
  r->sv.start = v_start;
  r->sv.flush = v_flush;
  r->now = 1000;  // (the clock's 0 is none)
}

static void give(Run *r) {
  double at = sound_packet(&r->p, &r->sv, packet, r->now);
  if (at > 0) r->held = at;
}

// a ms gone by: what plays, the moment asked for
static void step(Run *r) {
  r->now++;
  v_step(&r->v);
  if (r->held > 0 && r->now >= r->held) {
    r->held = 0;
    sound_held(&r->p, &r->sv, r->now);
  }
}

// The sound stopped (an empty packet: win_stream.cpp lets its voice go, the next packet makes it anew).
static void stop(Run *r) {
  v_flush(&r->v);
  sound_stopped(&r->p);
  r->held = 0;
}

// An app that keeps `ahead` ms queued past what has played and gives more only as it plays (a replay's: 160), told
// every 40 ms: for `ms` of the clock, or none given for it (`frozen`: its window's thread held). Returns what played.
typedef struct App {
  double sent, zero;
} App;

static void app_begin(Run *r, App *a) {
  a->sent = 0;
  a->zero = r->v.played;
}

static double app_for(Run *r, App *a, int ms, double ahead, int frozen) {
  double from = r->v.played;
  for (int i = 0; i < ms; i++) {
    if (!frozen && (int)r->now % 40 == 0) {
      int n = 0;
      while (a->sent - (r->v.played - a->zero) < ahead && n++ < 16) {
        give(r);
        a->sent += 20;
      }
    }
    step(r);
  }
  return r->v.played - from;
}

int main(void) {
  // A replay's: 160 ms ahead. A second of it, its window frozen 400 ms (the voice runs dry), a second again: its sound
  // plays again; stopped, and a second again 200 ms after: so too.
  {
    Run r;
    App a;
    run_init(&r);
    app_begin(&r, &a);
    double before = app_for(&r, &a, 1000, 160, 0);
    app_for(&r, &a, 400, 160, 1);
    app_begin(&r, &a);
    double after_gap = app_for(&r, &a, 1000, 160, 0);
    int reserve_after_gap = r.p.reserve;
    stop(&r);
    app_for(&r, &a, 200, 160, 1);
    app_begin(&r, &a);
    double after_stop = app_for(&r, &a, 1000, 160, 0);
    printf("win_sound: 160 ms ahead: played %.0f ms before the gap, %.0f after it, %.0f after a stop (the reserve %d ms after the gap, %d ms now)\n",
           before, after_gap, after_stop, reserve_after_gap * 20, r.p.reserve * 20);
    CHECK(before >= 900, "%.0f ms played before the gap", before);
    CHECK(after_gap >= 800, "%.0f ms of the second after the gap played", after_gap);
    CHECK(after_stop >= 800, "%.0f ms of the second after the stop played", after_stop);
    // ... and its reserve comes back: 40 s more of it, steady, and the gap is forgotten
    app_for(&r, &a, 40000, 160, 0);
    printf("win_sound: 160 ms ahead: the reserve %d ms after 40 s steady\n", r.p.reserve * 20);
    CHECK(r.p.reserve == 5, "the reserve %d ms after 40 s steady", r.p.reserve * 20);
  }

  // A remote screen's sound: a packet every 20 ms as it is made, but now and then 260 ms late (a busy Mac's): the first
  // late one runs it dry and raises the reserve; those after it are covered, nothing runs dry again.
  {
    Run r;
    run_init(&r);
    int dry_after_first = -1;
    for (int k = 0; k < 6; k++) {
      // 3 s on time, then 260 ms of nothing and the 13 packets made meanwhile at once
      for (int i = 0; i < 3000; i++) {
        if (i % 20 == 0) give(&r);
        step(&r);
      }
      for (int i = 0; i < 260; i++) step(&r);
      for (int i = 0; i < 13; i++) give(&r);
      if (k == 0) {
        for (int i = 0; i < 40; i++) {
          if (i % 20 == 0) give(&r);
          step(&r);
        }
        dry_after_first = r.v.dry;
      }
    }
    printf("win_sound: a stream 260 ms late each 3 s: the reserve %d ms, ran dry %d ms in all (%d by the first late)\n",
           r.p.reserve * 20, r.v.dry, dry_after_first);
    CHECK(r.p.reserve >= 14, "the reserve %d ms", r.p.reserve * 20);
    CHECK(r.v.dry == dry_after_first, "ran dry %d ms after the first late one", r.v.dry - dry_after_first);
  }

  // A gap of a second or more (the sound paused) raises nothing.
  {
    Run r;
    run_init(&r);
    for (int i = 0; i < 1000; i++) {
      if (i % 20 == 0) give(&r);
      step(&r);
    }
    for (int i = 0; i < 1500; i++) step(&r);
    give(&r);
    CHECK(r.p.reserve == 5, "the reserve %d ms after a pause", r.p.reserve * 20);
  }

  printf(failed ? "win_sound: FAILED\n" : "win_sound: ok\n");
  return failed;
}
