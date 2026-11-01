// A contained capture's coordinates and rounded boundaries, passed to the shared corner shader. The mapping takes
// capture-local pixel coordinates to the scene's points; GL's y step is negative, Metal and D3D's positive.
typedef struct {
  float map[4], box[4], rr[4], clip[4], rc[4], rs[4], outer[4], orc[4], ors[4];
} MBContained;

static int mb_contained_make(MBContained *c, const float *a, float x, float y, float dx, float dy) {
  int rounded = a[4] > 0;
  for (int i = 0; i < 4; i++) rounded |= a[24 + i] > 0 || a[44 + i] > 0;
  if (a[7] >= 0 || !rounded) return 0;
  c->map[0] = x; c->map[1] = y; c->map[2] = dx; c->map[3] = dy;
  c->box[0] = a[0]; c->box[1] = a[1]; c->box[2] = a[0] + a[2]; c->box[3] = a[1] + a[3];
  for (int i = 0; i < 4; i++) {
    c->rr[i] = a[36 + i]; c->clip[i] = a[16 + i]; c->rc[i] = a[24 + i]; c->rs[i] = a[28 + i];
    c->outer[i] = a[40 + i]; c->orc[i] = a[44 + i]; c->ors[i] = a[48 + i];
  }
  return 1;
}
