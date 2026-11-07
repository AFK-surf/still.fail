// Dirty rectangles in app points, shared by Metal, Direct3D and GLES. Each renderer owns one copy.
#ifndef MB_RENDER_DIRTY_H
#define MB_RENDER_DIRTY_H
#include <math.h>
#define MB_PARTS 8
static double dirty[MB_PARTS][4];
static int dirty_n, dirty_whole, dirty_told;

#ifdef __cplusplus
extern "C"
#endif
void mb_host_render_dirty(double x, double y, double w, double h) {
  dirty_told = 1;
  if (w < 0 || h < 0) {
    dirty_whole = 1;
  } else if (w > 0 && h > 0) {
    // More than the buffer holds: grow the last rectangle around the new one.
    if (dirty_n == MB_PARTS) {
      double *d = dirty[MB_PARTS - 1];
      double x1 = fmax(d[0] + d[2], x + w), y1 = fmax(d[1] + d[3], y + h);
      d[0] = fmin(d[0], x);
      d[1] = fmin(d[1], y);
      d[2] = x1 - d[0];
      d[3] = y1 - d[1];
    } else {
      double *d = dirty[dirty_n++];
      d[0] = x; d[1] = y; d[2] = w; d[3] = h;
    }
  }
}

// Consume the next frame's damage: -1 draws all, 0 draws nothing. Pixel bounds are top-left x0,y0,x1,y1.
// Expand by one pixel for antialiasing before clipping to the target; hosts convert only the rectangle format.
static int take_dirty(int tw, int th, int kept, int missing, double scale, int r[MB_PARTS][4]) {
  int told = dirty_told, whole = dirty_whole, n = dirty_n;
  dirty_told = dirty_whole = dirty_n = 0;
  if (!told || whole || !kept || missing) return -1;
  int k = 0;
  for (int i = 0; i < n; i++) {
    int x0 = (int)floor(dirty[i][0] * scale) - 1, y0 = (int)floor(dirty[i][1] * scale) - 1;
    int x1 = (int)ceil((dirty[i][0] + dirty[i][2]) * scale) + 1;
    int y1 = (int)ceil((dirty[i][1] + dirty[i][3]) * scale) + 1;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > tw) x1 = tw;
    if (y1 > th) y1 = th;
    if (x1 <= x0 || y1 <= y0) continue;
    r[k][0] = x0; r[k][1] = y0; r[k][2] = x1; r[k][3] = y1;
    k++;
  }
  return k;
}
#endif
