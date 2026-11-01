// mbui's corners (src/ui/smooth.mbt: these are its smoothness, sd_corner and sd_box, number for number), the one copy
// every renderer draws by: Metal's, Direct3D's and both GLs' shaders take it in as it is (corner_sl.h; web/host.js
// between its "corner.sl" lines), written in what the four have in common (float2: GLSL's vec2, defined so before it).
// Made into those by scripts/chk corner-sl, which CI runs with --check.
//
// How smooth a corner of radius r is where room is half its box's shorter side: 0 a circle's or a capsule's end, 1
// superellipse(1.5) over r a quarter longer; between, as far as the room goes.
float mb_smoothness(float r, float room) {
  return r <= 0.0 ? 0.0 : clamp((room - r) / (0.25 * r), 0.0, 1.0);
}
// The signed distance of p (from a box's middle) from that box, hs its half sides, its corners r (at most the shorter
// half) s smooth: |x|^n + |y|^n = R^n about each corner's centre, n from 2 to 2^1.5 and R from r to 1.25 r as s goes
// from 0 to 1. 0 on the curve; off it, the curve's value over how fast it grows there (along its normal, to first
// order). At s = 0 a round corner's, as before. Only within band of the curve is it worked out (two powers a pixel):
// the curve lies between the circle of R and that of R 2^(1/2 - 1/n) (under 1.107 R), and further than band inside
// the one or outside the other the round distance has its sign and is as far, which is all a cover, an edge band
// wide or a shadow that blurred says of it. (mb_sd_corner below: this and a capsule's end easing into its edges.)
float mb_corner_shape(float2 p, float2 hs, float r, float s, float band) {
  float R = min(r * (1.0 + 0.25 * s), min(hs.x, hs.y));
  float2 q = abs(p) - hs + R;
  float2 m = max(q, 0.0);
  float l = length(m);
  if (s <= 0.0 || min(m.x, m.y) <= 0.0 || l <= R - band || l >= 1.107 * R + band) return l + min(max(q.x, q.y), 0.0) - R;
  float hi = max(m.x, m.y);
  float t = min(m.x, m.y) / hi;
  if (s >= 1.0) {
    // wholly smooth (nearly every corner): the two factors below as polynomials in t, no power (smooth.mbt
    // smooth_a, smooth_b: within 2e-5 of them, a hundredth of a pixel over a radius of 200)
    float A = 1.0000098 + t * (-0.00106380035 + t * (0.0390446602 + t * (1.21491043 + t * (-1.49650831 + t * (1.90947795 + t * (-2.77580972 + t * (2.11536546 + t * -0.591224537)))))));
    float B = 1.00001404 + t * (-0.00136262193 + t * (0.039570688 + t * (0.648050719 + t * (-0.725922772 + t * (0.327888394 + t * (-0.914717465 + t * (1.13728689 + t * -0.403984265)))))));
    return hi * A - R * B;
  }
  float n = 2.0 + 0.8284271247461903 * s;
  float tn1 = pow(t, n - 1.0);
  float tn = tn1 * t;
  float u = pow(1.0 + tn, 1.0 / n);
  return (hi * u - R) * (1.0 + tn) / (u * sqrt(1.0 + tn1 * tn1));
}
// A capsule's end as Apple draws one (smooth.mbt capsule_ease): how much further in than the circle it lies, in r, u r
// from the tip, k the share of the room it needs along the edge the box has; a quintic from the circle's height, slope
// and bend at 0.3 r to the edge's at (1 + k) r.
float mb_capsule_ease(float u, float k) {
  float e = 1.0 + k;
  if (k <= 0.0 || u <= 0.3 || u >= e) return 0.0;
  float h = e - 0.3;
  float t = (u - 0.3) / h;
  float t2 = t * t;
  float t3 = t2 * t;
  float w0 = 1.0 - t3 * (10.0 - 15.0 * t + 6.0 * t2);
  float w1 = t - t3 * (6.0 - 8.0 * t + 3.0 * t2);
  float w2 = t2 * (0.5 - t * (1.5 - t * (1.5 - 0.5 * t)));
  float eased = 0.285857157145715 * w0 - 0.9801960588196068 * h * w1 + 2.7456472235843328 * h * h * w2;
  float circ = u < 1.0 ? 1.0 - sqrt(u * (2.0 - u)) : 0.0;
  return eased - circ;
}
// How much further out than the round corner's (rr) a point is once the corner eases into one of its box's edges:
// along the point's coordinate that way and ha that half side, across and hc the other's (from the box's middle,
// positive); as far as the corner has no room across and room along, moved along the round corner's normal
// (smooth.mbt capsule_tail).
float mb_capsule_tail(float along, float across, float ha, float hc, float rr) {
  float k = min((ha - rr) / rr, 1.0);
  float tight = 1.0 - mb_smoothness(rr, hc);
  if (k <= 0.0 || tight <= 0.0) return 0.0;
  float e = mb_capsule_ease((ha - along) / rr, k);
  if (e == 0.0) return 0.0;
  float qa = along - ha + rr;
  float qc = across - hc + rr;
  float ma = max(qa, 0.0);
  float mc = max(qc, 0.0);
  float l = sqrt(ma * ma + mc * mc);
  float n = l > 0.0 ? mc / l : (qc >= qa ? 1.0 : 0.0);
  return tight * k * e * rr * n;
}
// The signed distance of p (from a box's middle) from that box (mb_corner_shape's), a capsule's end easing into its
// long edges.
float mb_sd_corner(float2 p, float2 hs, float r, float s, float band) {
  float d = mb_corner_shape(p, hs, r, s, band);
  float rr = min(r * (1.0 + 0.25 * s), min(hs.x, hs.y));
  if (s >= 1.0 || rr <= 0.0) return d;
  float2 a = abs(p);
  return d + (1.0 - s) * (mb_capsule_tail(a.x, a.y, hs.x, hs.y, rr) + mb_capsule_tail(a.y, a.x, hs.y, hs.x, rr));
}
// Which of a box's corners' radii r (top left, top right, bottom right, bottom left: scene.mbt 36-39) p (from its
// middle) is drawn by: the one of its quarter's corner.
float mb_corner_of(float2 p, float4 r) {
  return p.x < 0.0 ? (p.y < 0.0 ? r.x : r.w) : (p.y < 0.0 ? r.y : r.z);
}
// The signed distance of p from a clip (scene.mbt 16-19 and 24-31, or its outer's 40-51): c its rect (x0 y0 x1 y1), r
// its corners (top left, then clockwise; 0 square), s how smooth each is. A corner is the curve of the box whose corner
// it is, where that box has it (its radius as that box drew it): drawn there whatever the clip's own size, so a band a
// few points high sharing a frame's corner is cut by the frame's very curve, not by one flattened to its half height.
// Each corner against its own corner point; the rect's edges straight.
float mb_clip_corner(float2 p, float2 k, float2 inward, float2 hs, float r, float s, float band) {
  float R = r * (1.0 + 0.25 * s);
  float2 hv = max(hs, float2(R, R));
  return mb_sd_corner(max(hv - (p - k) * inward, float2(0.0, 0.0)), hv, r, s, band);
}
float mb_sd_clip(float2 p, float4 c, float4 r, float4 s, float band) {
  float2 hs = max((c.zw - c.xy) * 0.5, float2(0.0, 0.0));
  float2 q = abs(p - (c.xy + hs)) - hs;
  float d = length(max(q, float2(0.0, 0.0))) + min(max(q.x, q.y), 0.0);
  if (r.x > 0.0) d = max(d, mb_clip_corner(p, c.xy, float2(1.0, 1.0), hs, r.x, s.x, band));
  if (r.y > 0.0) d = max(d, mb_clip_corner(p, c.zy, float2(-1.0, 1.0), hs, r.y, s.y, band));
  if (r.z > 0.0) d = max(d, mb_clip_corner(p, c.zw, float2(-1.0, -1.0), hs, r.z, s.z, band));
  if (r.w > 0.0) d = max(d, mb_clip_corner(p, c.xw, float2(1.0, -1.0), hs, r.w, s.w, band));
  return d;
}
// A box's own corners: r at most its shorter half, as smooth as its size has room for (band: mb_sd_corner's).
float mb_sd_box(float2 p, float2 hs, float r, float band) {
  float room = min(hs.x, hs.y);
  float rr = min(r, room);
  return mb_sd_corner(p, hs, rr, mb_smoothness(rr, room), band);
}
// A contained blur extends the picture at its actual curved boundary, rather than cropping all four straight edges
// to a corner's inset. Points already in the picture stay where they are. Near a curve, keep a little inside its
// antialiased edge so the bilinear sample itself cannot bring in the background outside the clip.
#ifndef MB_CONTAINED_LOOP
#define MB_CONTAINED_LOOP
#endif
float mb_max4(float4 v) { return max(max(v.x, v.y), max(v.z, v.w)); }
float mb_contained_rect_dist(float2 p, float4 c) {
  float2 hs = (c.zw - c.xy) * 0.5;
  float2 q = abs(p - c.xy - hs) - hs;
  return length(max(q, float2(0.0, 0.0))) + min(max(q.x, q.y), 0.0);
}
// The same clip as mb_sd_clip, traversed so a runtime shader compiler need only compile one corner's calculation.
float mb_contained_clip_dist(float2 p, float4 c, float4 r, float4 s) {
  float2 hs = max((c.zw - c.xy) * 0.5, float2(0.0, 0.0));
  float2 q = abs(p - (c.xy + hs)) - hs;
  float d = length(max(q, float2(0.0, 0.0))) + min(max(q.x, q.y), 0.0);
  MB_CONTAINED_LOOP for (int i = 0; i < 4; i++) {
    if (r[i] > 0.0) {
      float2 inward = float2(i == 0 || i == 3 ? 1.0 : -1.0, i < 2 ? 1.0 : -1.0);
      float2 corner = float2(inward.x > 0.0 ? c.x : c.z, inward.y > 0.0 ? c.y : c.w);
      d = max(d, mb_clip_corner(p, corner, inward, hs, r[i], s[i], 1e9));
    }
  }
  return d;
}
float mb_contained_dist(float2 p, float4 box, float4 rr, float4 clip, float4 rc, float4 rs,
                        float4 outer, float4 orc, float4 ors) {
  float2 hs = (box.zw - box.xy) * 0.5;
  float2 q = p - box.xy - hs;
  float d = max(mb_sd_box(q, hs, mb_corner_of(q, rr), 1e9), mb_contained_clip_dist(p, clip, rc, rs));
  if (mb_max4(orc) > 0.0) d = max(d, mb_contained_clip_dist(p, outer, orc, ors));
  return d;
}
// Skip the distance and search entirely along the straight parts of the edges and in the middle of the picture.
bool mb_contained_corner(float2 p, float4 c, float4 r, float pad) {
  // A capsule's easing can reach two radii along its long edge.
  float4 R = r * 2.5 + float4(pad, pad, pad, pad);
  return (r.x > 0.0 && p.x < c.x + R.x && p.y < c.y + R.x) ||
         (r.y > 0.0 && p.x > c.z - R.y && p.y < c.y + R.y) ||
         (r.z > 0.0 && p.x > c.z - R.z && p.y > c.w - R.z) ||
         (r.w > 0.0 && p.x < c.x + R.w && p.y > c.w - R.w);
}
float2 mb_contained_point(float2 p, float4 box, float4 rr, float4 clip, float4 rc, float4 rs,
                          float4 outer, float4 orc, float4 ors, float pixel) {
  float pad = 1.5 * pixel;
  if (!mb_contained_corner(p, box, rr, pad) && !mb_contained_corner(p, clip, rc, pad) &&
      !mb_contained_corner(p, outer, orc, pad)) return p;
  float2 lo = max(box.xy, clip.xy), hi = min(box.zw, clip.zw);
  if (mb_max4(orc) > 0.0) { lo = max(lo, outer.xy); hi = min(hi, outer.zw); }
  float2 inside = (lo + hi) * 0.5;
  float2 outside = p;
  float id = 0.0, inset = 0.0;
  // One distance evaluation in the shader: check p, find an interior point, then bisect towards the edge twelve times.
  // A clip can leave only a corner of the box visible, so try each shape's centre clamped to the intersection too.
  MB_CONTAINED_LOOP for (int i = 0; i < 17; i++) {
    float2 probe = p;
    if (i == 1) probe = (lo + hi) * 0.5;
    else if (i == 2) probe = clamp((clip.xy + clip.zw) * 0.5, lo, hi);
    else if (i == 3) probe = clamp((box.xy + box.zw) * 0.5, lo, hi);
    else if (i == 4) probe = mb_max4(orc) > 0.0 ? clamp((outer.xy + outer.zw) * 0.5, lo, hi) : inside;
    else if (i > 4) probe = (outside + inside) * 0.5;
    float d = mb_contained_dist(probe, box, rr, clip, rc, rs, outer, orc, ors);
    if (i == 0) {
      if (d <= -pad) return p;
      // Near a straight edge, the original pixel is already picture even in the antialiasing band.
      float straight = max(mb_contained_rect_dist(p, box), mb_contained_rect_dist(p, clip));
      if (mb_max4(orc) > 0.0) straight = max(straight, mb_contained_rect_dist(p, outer));
      if (d <= straight + 0.001 * pixel) return p;
    } else if (i <= 4) {
      if (i == 1 || d < id) { inside = probe; id = d; }
      if (i == 4) {
        if (id >= 0.0) return p;
        inset = min(pad, -id * 0.5);
      }
    } else if (d > -inset) outside = probe;
    else inside = probe;
  }
  return inside;
}
// A shadow as Core Animation draws one (CALayer shadowRadius: a Gaussian blur of the shape, sigma its radius): the box
// of half sides hs about p, its corners r, blurred by sigma; how much of it covers p, 0 … 1. The blur across worked
// out whole (erf); along, four samples of the Gaussian over where it is not nothing (Evan Wallace's rounded box shadow).
float mb_erf(float x) {
  float s = sign(x);
  float a = abs(x);
  float t = 1.0 + (0.278393 + (0.230389 + 0.078108 * (a * a)) * a) * a;
  t = t * t;
  return s - s / (t * t);
}
float mb_shadow_row(float x, float y, float sigma, float r, float2 hs) {
  float delta = min(hs.y - r - abs(y), 0.0);
  float curved = hs.x - r + sqrt(max(0.0, r * r - delta * delta));
  float k = 0.7071067811865476 / sigma;
  return 0.5 * (mb_erf((x + curved) * k) - mb_erf((x - curved) * k));
}
float mb_shadow(float2 p, float2 hs, float r, float sigma) {
  float rr = min(r, min(hs.x, hs.y));
  float lo = clamp(-3.0 * sigma, p.y - hs.y, p.y + hs.y);
  float hi = clamp(3.0 * sigma, p.y - hs.y, p.y + hs.y);
  float st = (hi - lo) / 4.0;
  float y = lo + st * 0.5;
  float v = 0.0;
  for (int i = 0; i < 4; i++) {
    float g = exp(-(y * y) / (2.0 * sigma * sigma)) / (2.5066282746310002 * sigma);
    v += mb_shadow_row(p.x, p.y - y, sigma, rr, hs) * g * st;
    y += st;
  }
  return v;
}
// A shape (src/ui/shape.mbt, scene.mbt's kind 11): its pieces s (x0 y0 x1 y1 as shares of its band's rect r) worked
// into the pixel about p, scale its pixels a point. A fill's: each piece's crossings of 4 rows across the pixel, each
// counted by how much of the row lies left of it (+ going down, - going up); their sums over every piece, the rows'
// winding numbers across the pixel, make its cover (even_odd 1: by the even-odd rule, else the nonzero one).
// (mb4: v in all four; Direct3D's float4 takes no single number)
float4 mb4(float v) {
  return float4(v, v, v, v);
}
float4 mb_path_rows(float4 s, float4 r, float2 p, float scale) {
  float2 a = r.xy + s.xy * r.zw;
  float2 b = r.xy + s.zw * r.zw;
  if (a.y == b.y) return mb4(0.0);
  float dir = b.y > a.y ? 1.0 : -1.0;
  float4 ys = mb4(p.y) + float4(-0.375, -0.125, 0.125, 0.375) / scale;
  float4 in_ = step(mb4(min(a.y, b.y)), ys) * (mb4(1.0) - step(mb4(max(a.y, b.y)), ys));
  float4 xs = mb4(a.x) + (ys - mb4(a.y)) * ((b.x - a.x) / (b.y - a.y));
  return in_ * dir * clamp((xs - mb4(p.x)) * scale + mb4(0.5), mb4(0.0), mb4(1.0));
}
float mb_path_cover(float4 w, float even_odd) {
  float4 a = abs(w);
  float4 f = a - floor(a * 0.5) * 2.0;
  float4 c = even_odd > 0.5 ? mb4(1.0) - abs(mb4(1.0) - f) : min(a, mb4(1.0));
  return dot(c, mb4(0.25));
}
// A stroke's: how far p is from a piece (its ends round).
float mb_seg_dist(float4 s, float4 r, float2 p) {
  float2 a = r.xy + s.xy * r.zw;
  float2 ab = r.xy + s.zw * r.zw - a;
  float h = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-8), 0.0, 1.0);
  return length(p - a - ab * h);
}
// Which of a data instance's (kind 12) fours piece i is in: 0, 2, 3, 4, 6, 7 (shape.mbt seg_slots), six to an instance.
int mb_seg_slot(int i) {
  int s = i - (i / 6) * 6;
  return s + (s >= 1 ? 1 : 0) + (s >= 4 ? 1 : 0);
}
// How far to move a smooth ground (glass's frost) at the pixel px (in pixels) before it is written to 8 bits a
// channel, in steps of 1/255: Skia's ordered dither (GrDitherEffect, an 8x8 Bayer matrix by the pixel's place), never
// half a step either way. Without it a slope of a few steps across a wide frost is written as flat bands, an edge where
// each step is (contour lines); with it each pixel is the step above or below as often as the slope is near it, and
// a value already on a step stays it.
float mb_dither(float2 px) {
  int x = int(floor(px.x)) & 7;
  int y = (int(floor(px.y)) & 7) ^ x;
  int m = ((y & 1) << 5) | ((x & 1) << 4) | ((y & 2) << 2) | ((x & 2) << 1) | ((y & 4) >> 1) | ((x & 4) >> 2);
  return float(m) / 64.0 - 63.0 / 128.0;
}
