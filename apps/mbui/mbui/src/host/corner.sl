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
// wide or a shadow that blurred says of it.
float mb_sd_corner(float2 p, float2 hs, float r, float s, float band) {
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
// A box's own corners: r at most its shorter half, as smooth as its size has room for (band: mb_sd_corner's).
float mb_sd_box(float2 p, float2 hs, float r, float band) {
  float room = min(hs.x, hs.y);
  float rr = min(r, room);
  return mb_sd_corner(p, hs, rr, mb_smoothness(rr, room), band);
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
