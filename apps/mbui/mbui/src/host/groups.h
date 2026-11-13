// The groups of instances the host keeps (@hostapi.group_set): a list's row kept as it was drawn, which the app then
// says among a frame's instances by a header alone (kind 13, mbui/src/ui/scene.mbt), moved, instead of writing every
// instance of it again each frame. Each host's mb_host_present draws the headers out here before its renderer takes the
// frame, as mbui/src/ui/view_ride.mbt's ride_put writes them: so a renderer, its shaders, what compares a frame with the
// last (apple_render.m's same_as_shown) and what draws the last frame again all take the instances as before.
//
// A header's numbers: 0, 1 how far its group's instances are moved; 5 13; 12 the group; 13 the first of its instances,
// 14 how many (the header and the room after it the frame gives them, unwritten), 15 how far on its shapes' pieces
// (a band's 12, kind 11) are among the frame's; 16-19 a clip they are all cut to (x0, y0, x1, y1; all 0: none), a list's
// column's whole (mbui/src/ui/view_ride.mbt's ListRiding). Each of the group's instances moved: its rect (0, 1) always;
// its clip (16-19), its outer (40-43) and its turn's point (33, 34) as its `moves` bits say; then cut to the header's
// clip: its own where that is square (no corner's radius, 24-27) or it has no outer, a corner the cut moves square;
// else its outer. A group may hold headers of others (a list's rows kept, in the list's group kept whole), each in one
// place of it: a header of such a group stands for all of it, its 14 how many it draws out to (each header in it as
// many as that one says), each header in it drawn out where it comes, moved with it and cut to its clip as well.
//
// Included once, by the file that defines mb_host_present.
#ifndef MB_GROUPS_H
#define MB_GROUPS_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define MB_GROUP_INST 60
#define MB_GROUP_HEAD 13.0

typedef struct {
  // 0: none here; -1: one let go here (looked past)
  int32_t id;
  int32_t n;
  double *inst;
  int32_t *moves;
  // whether it holds headers of others (a list's, its rows kept)
  int32_t heads;
} mb_group;

static mb_group *mb_groups;
static size_t mb_groups_cap;
// (those here and those let go, what a look goes past)
static size_t mb_groups_taken;
static double *mb_groups_out;
static size_t mb_groups_out_cap;

static size_t mb_group_slot(int32_t id) { return ((uint32_t)id * 2654435761u) & (mb_groups_cap - 1); }

// Where group `id` is, or NULL.
static mb_group *mb_group_find(int32_t id) {
  if (!mb_groups_cap) return NULL;
  for (size_t i = mb_group_slot(id), k = 0; k < mb_groups_cap; i = (i + 1) & (mb_groups_cap - 1), k++) {
    if (mb_groups[i].id == id) return &mb_groups[i];
    if (mb_groups[i].id == 0) return NULL;
  }
  return NULL;
}

static void mb_group_put(mb_group g);

// Room for more, those here put again (those let go left behind).
static void mb_groups_grow(void) {
  mb_group *old = mb_groups;
  size_t cap = mb_groups_cap;
  mb_groups_cap = cap ? cap * 2 : 256;
  mb_groups = calloc(mb_groups_cap, sizeof(mb_group));
  mb_groups_taken = 0;
  for (size_t i = 0; i < cap; i++)
    if (old[i].id > 0) mb_group_put(old[i]);
  free(old);
}

static void mb_group_put(mb_group g) {
  if ((mb_groups_taken + 1) * 2 > mb_groups_cap) mb_groups_grow();
  size_t i = mb_group_slot(g.id);
  while (mb_groups[i].id > 0) i = (i + 1) & (mb_groups_cap - 1);
  if (mb_groups[i].id == 0) mb_groups_taken++;
  mb_groups[i] = g;
}

int32_t mb_host_groups_here(void) { return 1; }

void mb_host_group_drop(int32_t id) {
  mb_group *g = mb_group_find(id);
  if (!g) return;
  free(g->inst);
  free(g->moves);
  g->inst = NULL;
  g->moves = NULL;
  g->n = 0;
  g->id = -1;
}

void mb_host_group_set(int32_t id, double *inst, double *moves, int32_t n) {
  mb_host_group_drop(id);
  if (id <= 0 || n < 0) return;
  mb_group g = {id, n, malloc(sizeof(double) * MB_GROUP_INST * (size_t)(n > 0 ? n : 1)),
                malloc(sizeof(int32_t) * (size_t)(n > 0 ? n : 1)), 0};
  memcpy(g.inst, inst, sizeof(double) * MB_GROUP_INST * (size_t)n);
  for (int32_t i = 0; i < n; i++) {
    g.moves[i] = (int32_t)moves[i];
    if (inst[(size_t)i * MB_GROUP_INST + 5] == MB_GROUP_HEAD) g.heads = 1;
  }
  mb_group_put(g);
}

// Instance `e` of a group moved by (dx, dy) as its `moves` bits `m` say, its shapes' pieces `seg_by` on, cut to
// (h0, h1, h2, h3) where `cut`.
static void mb_group_inst_moved(double *e, int32_t m, double dx, double dy, double seg_by, int cut, double h0,
                                double h1, double h2, double h3) {
  e[0] += dx;
  e[1] += dy;
  if (e[5] == 11.0) e[12] += seg_by;
  if (m) {
    for (int j = 0; j < 4; j++) {
      double by = j % 2 == 0 ? dx : dy;
      if (m & (1 << j)) e[16 + j] += by;
      if (m & (1 << (4 + j))) e[40 + j] += by;
    }
    if (m & 256) {
      e[33] += dx;
      e[34] += dy;
    }
    // (where it fades out towards a cut, 52, 54 down and 56, 58 across: what holds it inside the group said, moved
    // with it: view_ride.mbt's ride_moves, bits 9-12)
    for (int j = 0; j < 4; j++)
      if (m & (512 << j)) e[52 + 2 * j] += j < 2 ? dy : dx;
  }
  if (!cut) return;
  if ((e[24] == 0.0 && e[25] == 0.0 && e[26] == 0.0 && e[27] == 0.0) ||
      (e[40] == 0.0 && e[41] == 0.0 && e[42] == 0.0 && e[43] == 0.0)) {
    // (a square clip, or a round one with no outer: it cut to it, a corner the cut moves square, as
    // mbui/src/ui/scene.mbt's clamp_inst_clip; never it as its outer, which with no corner's radius is none)
    double m0 = e[16], m1 = e[17], m2 = e[18], m3 = e[19];
    if (e[16] < h0) e[16] = h0;
    if (e[17] < h1) e[17] = h1;
    if (e[18] > h2) e[18] = h2;
    if (e[19] > h3) e[19] = h3;
    if (e[16] != m0 || e[17] != m1) e[24] = e[28] = 0.0;
    if (e[18] != m2 || e[17] != m1) e[25] = e[29] = 0.0;
    if (e[18] != m2 || e[19] != m3) e[26] = e[30] = 0.0;
    if (e[16] != m0 || e[19] != m3) e[27] = e[31] = 0.0;
  } else {
    if (e[40] < h0) e[40] = h0;
    if (e[41] < h1) e[41] = h1;
    if (e[42] > h2) e[42] = h2;
    if (e[43] > h3) e[43] = h3;
  }
}

// Header `h`'s group drawn out into `d`, `room` instances at most (the header's own place and the room after it):
// each of its instances moved and cut as the header says. A group that holds headers (a list's, its rows kept:
// mbui/src/ui/view_ride.mbt's ListRiding) is drawn whole, each of those in one place of it drawn out where it comes
// in turn, moved with it and cut to its clip as well, as many as it says. How many it drew.
static int32_t mb_group_out(double *d, int32_t room, const double *h) {
  int32_t first = (int32_t)h[13], n = (int32_t)h[14];
  double dx = h[0], dy = h[1], seg_by = h[15];
  // (its clip, 16-19, where it says one: each of its instances cut to it as well, mbui/src/ui/view_ride.mbt's
  // inst_cut_to)
  double h0 = h[16], h1 = h[17], h2 = h[18], h3 = h[19];
  int cut = !(h0 == 0.0 && h1 == 0.0 && h2 == 0.0 && h3 == 0.0);
  if (n < 1) n = 1;
  if (n > room) n = room;
  mb_group *g = mb_group_find((int32_t)h[12]);
  if (g && g->heads) {
    int32_t w = 0;
    for (int32_t i = 0; i < g->n && w < n; i++) {
      const double *e = g->inst + (size_t)i * MB_GROUP_INST;
      if (e[5] == MB_GROUP_HEAD) {
        // (a header in it: moved with it, its pieces as far on again, its clip this one's where it says none, else as
        // much of both)
        double hv[20];
        memcpy(hv, e, sizeof hv);
        hv[0] += dx;
        hv[1] += dy;
        hv[15] += seg_by;
        if (cut) {
          if (hv[16] == 0.0 && hv[17] == 0.0 && hv[18] == 0.0 && hv[19] == 0.0) {
            hv[16] = h0;
            hv[17] = h1;
            hv[18] = h2;
            hv[19] = h3;
          } else {
            if (hv[16] < h0) hv[16] = h0;
            if (hv[17] < h1) hv[17] = h1;
            if (hv[18] > h2) hv[18] = h2;
            if (hv[19] > h3) hv[19] = h3;
          }
        }
        w += mb_group_out(d + (size_t)w * MB_GROUP_INST, n - w, hv);
        continue;
      }
      double *o = d + (size_t)w * MB_GROUP_INST;
      memcpy(o, e, sizeof(double) * MB_GROUP_INST);
      mb_group_inst_moved(o, g->moves[i], dx, dy, seg_by, cut, h0, h1, h2, h3);
      w++;
    }
    // (what it said it drew past what it holds: nothing there)
    if (w < n) memset(d + (size_t)w * MB_GROUP_INST, 0, sizeof(double) * MB_GROUP_INST * (size_t)(n - w));
    return n;
  }
  if (!g || first < 0 || first + n > g->n) {
    // (one not kept, never so: nothing drawn there)
    memset(d, 0, sizeof(double) * MB_GROUP_INST * (size_t)n);
    return n;
  }
  memcpy(d, g->inst + (size_t)first * MB_GROUP_INST, sizeof(double) * MB_GROUP_INST * (size_t)n);
  double *e = d;
  for (int32_t i = 0; i < n; i++, e += MB_GROUP_INST)
    mb_group_inst_moved(e, g->moves[first + i], dx, dy, seg_by, cut, h0, h1, h2, h3);
  return n;
}

// The frame `buf` (`count` instances) with each header drawn out, its group's instances in its place; `buf` itself
// where it has none.
static const double *mb_groups_draw_out(const double *buf, int32_t count) {
  int32_t k = 0;
  while (k < count && buf[(size_t)k * MB_GROUP_INST + 5] != MB_GROUP_HEAD) k++;
  if (k >= count) return buf;
  size_t len = (size_t)count * MB_GROUP_INST;
  if (mb_groups_out_cap < len) {
    mb_groups_out_cap = len * 2;
    mb_groups_out = realloc(mb_groups_out, sizeof(double) * mb_groups_out_cap);
  }
  double *s = mb_groups_out;
  // (what comes before the first header as it is)
  memcpy(s, buf, sizeof(double) * (size_t)k * MB_GROUP_INST);
  while (k < count) {
    const double *h = buf + (size_t)k * MB_GROUP_INST;
    if (h[5] != MB_GROUP_HEAD) {
      memcpy(s + (size_t)k * MB_GROUP_INST, h, sizeof(double) * MB_GROUP_INST);
      k++;
      continue;
    }
    k += mb_group_out(s + (size_t)k * MB_GROUP_INST, count - k, h);
  }
  return s;
}

#endif
