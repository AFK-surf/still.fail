// A stream's sound on Windows (win_stream.cpp's player) as a rule over its voice: when a packet is queued, when the
// voice starts, when what is queued is let go. Plain C of no system's: win_stream.cpp gives it XAudio2's source voice,
// the machine's clock and a timer, scripts/win_sound_test.c a voice of its own on its own clock.
//
// Its reserve, what is queued before it plays, starts at 100 ms (SOUND_BASE packets of 20 ms). A packet that comes
// late while the voice plays (since the last one, or since it started, longer than the reserve covers) makes it that
// long and a packet more, at most 300 ms (SOUND_MOST): packets of a busy Mac's sound came 50 to 270 ms apart now and
// then, and 60 ms ran dry, heard as a crackle each time. A gap while it does not play drains nothing and raises
// nothing; nor does one of a second or more (the sound paused, not late).
//
// It comes back, and it never asks more than the app gives (till 2026-11-15 it did neither: an app that keeps 160 ms
// ahead of what played and gives more only as that plays, a replay of a recording's, had no sound again for the
// window's life after the window froze once for more than 140 ms, every start waiting for 300 ms that never came):
// - each SOUND_CALM_MS with no packet late (more than SOUND_BASE covers) and nothing run dry halves what it is over
//   SOUND_BASE (300 ms back to 100 in 40 s);
// - not playing, once nothing more came for SOUND_HOLD_MS, it plays what is queued where that is SOUND_BASE or more:
//   all the app gives before it plays.
#ifndef MB_WIN_SOUND_H
#define MB_WIN_SOUND_H
#include <stdint.h>

#define SOUND_BASE 5           // the reserve at first and the least: 100 ms
#define SOUND_MOST 15          // the largest: 300 ms
#define SOUND_CALM_MS 10000.0  // each this long calm halves the reserve's excess over SOUND_BASE
#define SOUND_HOLD_MS 100.0    // not playing, and nothing more came for this long: what is queued plays

// What the player does to its voice.
typedef struct SoundVoice {
  void *it;
  int (*queued)(void *it);                         // buffers queued (the one playing among them)
  int (*submit)(void *it, const uint8_t *packet);  // one 20 ms packet after those queued (0: refused)
  int (*start)(void *it);                          // 0: refused
  void (*flush)(void *it);                         // stopped, what is queued let go
} SoundVoice;

typedef struct SoundPlayer {
  int reserve;      // packets queued before it plays (0: none came yet, SOUND_BASE then)
  int playing;
  double from;      // while it plays: when the last packet came or it started, the later (ms)
  double calm;      // since when no packet came late, nor did it run dry
  double gap;       // the last late packet's gap (ms: what win_stream.cpp's log says)
  unsigned count;   // packets come
  unsigned held;    // the count the moment asked for (sound_packet's answer) waits on
} SoundPlayer;

// Its voice let go (or made anew): it does not play.
static void sound_stopped(SoundPlayer *p) {
  p->playing = 0;
  p->from = 0;
}

// A packet came at `now` (ms) and is queued. Returns the moment to call sound_held at, where it does not play yet (0:
// none; a moment asked for before it is passed over).
static double sound_packet(SoundPlayer *p, const SoundVoice *v, const uint8_t *packet, double now) {
  if (!p->reserve) {
    p->reserve = SOUND_BASE;
    p->calm = now;
  }
  // (each calm stretch gone by halves the excess: a pause of a minute brings it back to SOUND_BASE at once)
  while (p->reserve > SOUND_BASE && now - p->calm >= SOUND_CALM_MS) {
    p->reserve = SOUND_BASE + (p->reserve - SOUND_BASE) / 2;
    p->calm += SOUND_CALM_MS;
  }
  if (p->playing && p->from > 0) {
    double gap = now - p->from;
    int need = (int)(gap / 20) + 2;
    if (gap < 1000 && need > SOUND_BASE) {
      // (late: no calm since; past what the reserve covers, it covers that now)
      p->calm = now;
      if (need > p->reserve) {
        p->reserve = need < SOUND_MOST ? need : SOUND_MOST;
        p->gap = gap;
      }
    }
  }
  int queued = v->queued(v->it);
  int dry = p->playing && queued == 0;
  // more than the reserve and 200 ms queued (a stall), or run dry while playing: emptied, the reserve filled again
  if (queued >= p->reserve + 10 || dry) {
    v->flush(v->it);
    p->playing = 0;
    p->from = 0;
    queued = 0;
    if (dry) p->calm = now;
  }
  p->count++;
  if (!v->submit(v->it, packet)) return 0;
  // started once its reserve is queued
  if (!p->playing && queued + 1 >= p->reserve && v->start(v->it)) p->playing = 1;
  if (p->playing) {
    p->from = now;
    return 0;
  }
  p->held = p->count;
  return now + SOUND_HOLD_MS;
}

// The moment sound_packet asked for, `now`: where nothing more came since and it does not play, what is queued plays
// if it is SOUND_BASE or more.
static void sound_held(SoundPlayer *p, const SoundVoice *v, double now) {
  if (p->playing || p->held != p->count || v->queued(v->it) < SOUND_BASE) return;
  if (v->start(v->it)) {
    p->playing = 1;
    p->from = now;
  }
}

#endif
