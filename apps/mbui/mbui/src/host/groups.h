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
// clip: its own where that is square (no corner's radius, 24-27), else its outer, the header's its outer where it has
// none.
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
                malloc(sizeof(int32_t) * (size_t)(n > 0 ? n : 1))};
  memcpy(g.inst, inst, sizeof(double) * MB_GROUP_INST * (size_t)n);
  for (int32_t i = 0; i < n; i++) g.moves[i] = (int32_t)moves[i];
  mb_group_put(g);
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
    int32_t first = (int32_t)h[13], n = (int32_t)h[14];
    double dx = h[0], dy = h[1], seg_by = h[15];
    // (its clip, 16-19, where it says one: each of its instances cut to it as well, mbui/src/ui/view_ride.mbt's
    // inst_cut_to)
    double h0 = h[16], h1 = h[17], h2 = h[18], h3 = h[19];
    int cut = !(h0 == 0.0 && h1 == 0.0 && h2 == 0.0 && h3 == 0.0);
    if (n < 1) n = 1;
    if (k + n > count) n = count - k;
    mb_group *g = mb_group_find((int32_t)h[12]);
    double *d = s + (size_t)k * MB_GROUP_INST;
    if (!g || first < 0 || first + n > g->n) {
      // (one not kept, never so: nothing drawn there)
      memset(d, 0, sizeof(double) * MB_GROUP_INST * (size_t)n);
      k += n;
      continue;
    }
    memcpy(d, g->inst + (size_t)first * MB_GROUP_INST, sizeof(double) * MB_GROUP_INST * (size_t)n);
    for (int32_t i = 0; i < n; i++, d += MB_GROUP_INST) {
      d[0] += dx;
      d[1] += dy;
      if (d[5] == 11.0) d[12] += seg_by;
      int32_t m = g->moves[first + i];
      if (m) {
        for (int j = 0; j < 4; j++) {
          double by = j % 2 == 0 ? dx : dy;
          if (m & (1 << j)) d[16 + j] += by;
          if (m & (1 << (4 + j))) d[40 + j] += by;
        }
        if (m & 256) {
          d[33] += dx;
          d[34] += dy;
        }
      }
      if (!cut) continue;
      if (d[24] == 0.0 && d[25] == 0.0 && d[26] == 0.0 && d[27] == 0.0) {
        // (a square clip: cut to it)
        if (d[16] < h0) d[16] = h0;
        if (d[17] < h1) d[17] = h1;
        if (d[18] > h2) d[18] = h2;
        if (d[19] > h3) d[19] = h3;
      } else if (d[40] == 0.0 && d[41] == 0.0 && d[42] == 0.0 && d[43] == 0.0) {
        // (a round one with no outer: it its outer)
        d[40] = h0;
        d[41] = h1;
        d[42] = h2;
        d[43] = h3;
        for (int j = 44; j < 52; j++) d[j] = 0.0;
      } else {
        if (d[40] < h0) d[40] = h0;
        if (d[41] < h1) d[41] = h1;
        if (d[42] > h2) d[42] = h2;
        if (d[43] > h3) d[43] = h3;
      }
    }
    k += n;
  }
  return s;
}

#endif
