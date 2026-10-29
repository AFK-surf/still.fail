// src/host/corner.sl as a C string (scripts/chk corner-sl makes it: edit corner.sl, then run it). The shaders
// write float2; GLSL's take it with `#define float2 vec2` and `#define float4 vec4` before it.
#define MB_CORNER_SL \
  "// mbui's corners (src/ui/smooth.mbt: these are its smoothness, sd_corner and sd_box, number for number), the one copy\n" \
  "// every renderer draws by: Metal's, Direct3D's and both GLs' shaders take it in as it is (corner_sl.h; web/host.js\n" \
  "// between its \"corner.sl\" lines), written in what the four have in common (float2: GLSL's vec2, defined so before it).\n" \
  "// Made into those by scripts/chk corner-sl, which CI runs with --check.\n" \
  "//\n" \
  "// How smooth a corner of radius r is where room is half its box's shorter side: 0 a circle's or a capsule's end, 1\n" \
  "// superellipse(1.5) over r a quarter longer; between, as far as the room goes.\n" \
  "float mb_smoothness(float r, float room) {\n" \
  "  return r <= 0.0 ? 0.0 : clamp((room - r) / (0.25 * r), 0.0, 1.0);\n" \
  "}\n" \
  "// The signed distance of p (from a box's middle) from that box, hs its half sides, its corners r (at most the shorter\n" \
  "// half) s smooth: |x|^n + |y|^n = R^n about each corner's centre, n from 2 to 2^1.5 and R from r to 1.25 r as s goes\n" \
  "// from 0 to 1. 0 on the curve; off it, the curve's value over how fast it grows there (along its normal, to first\n" \
  "// order). At s = 0 a round corner's, as before. Only within band of the curve is it worked out (two powers a pixel):\n" \
  "// the curve lies between the circle of R and that of R 2^(1/2 - 1/n) (under 1.107 R), and further than band inside\n" \
  "// the one or outside the other the round distance has its sign and is as far, which is all a cover, an edge band\n" \
  "// wide or a shadow that blurred says of it.\n" \
  "float mb_sd_corner(float2 p, float2 hs, float r, float s, float band) {\n" \
  "  float R = min(r * (1.0 + 0.25 * s), min(hs.x, hs.y));\n" \
  "  float2 q = abs(p) - hs + R;\n" \
  "  float2 m = max(q, 0.0);\n" \
  "  float l = length(m);\n" \
  "  if (s <= 0.0 || min(m.x, m.y) <= 0.0 || l <= R - band || l >= 1.107 * R + band) return l + min(max(q.x, q.y), 0.0) - R;\n" \
  "  float hi = max(m.x, m.y);\n" \
  "  float t = min(m.x, m.y) / hi;\n" \
  "  if (s >= 1.0) {\n" \
  "    // wholly smooth (nearly every corner): the two factors below as polynomials in t, no power (smooth.mbt\n" \
  "    // smooth_a, smooth_b: within 2e-5 of them, a hundredth of a pixel over a radius of 200)\n" \
  "    float A = 1.0000098 + t * (-0.00106380035 + t * (0.0390446602 + t * (1.21491043 + t * (-1.49650831 + t * (1.90947795 + t * (-2.77580972 + t * (2.11536546 + t * -0.591224537)))))));\n" \
  "    float B = 1.00001404 + t * (-0.00136262193 + t * (0.039570688 + t * (0.648050719 + t * (-0.725922772 + t * (0.327888394 + t * (-0.914717465 + t * (1.13728689 + t * -0.403984265)))))));\n" \
  "    return hi * A - R * B;\n" \
  "  }\n" \
  "  float n = 2.0 + 0.8284271247461903 * s;\n" \
  "  float tn1 = pow(t, n - 1.0);\n" \
  "  float tn = tn1 * t;\n" \
  "  float u = pow(1.0 + tn, 1.0 / n);\n" \
  "  return (hi * u - R) * (1.0 + tn) / (u * sqrt(1.0 + tn1 * tn1));\n" \
  "}\n" \
  "// Which of a box's corners' radii r (top left, top right, bottom right, bottom left: scene.mbt 36-39) p (from its\n" \
  "// middle) is drawn by: the one of its quarter's corner.\n" \
  "float mb_corner_of(float2 p, float4 r) {\n" \
  "  return p.x < 0.0 ? (p.y < 0.0 ? r.x : r.w) : (p.y < 0.0 ? r.y : r.z);\n" \
  "}\n" \
  "// The signed distance of p from a clip (scene.mbt 16-19 and 24-31, or its outer's 40-51): c its rect (x0 y0 x1 y1), r\n" \
  "// its corners (top left, then clockwise; 0 square), s how smooth each is. A corner is the curve of the box whose corner\n" \
  "// it is, where that box has it (its radius as that box drew it): drawn there whatever the clip's own size, so a band a\n" \
  "// few points high sharing a frame's corner is cut by the frame's very curve, not by one flattened to its half height.\n" \
  "// Each corner against its own corner point; the rect's edges straight.\n" \
  "float mb_clip_corner(float2 p, float2 k, float2 inward, float2 hs, float r, float s, float band) {\n" \
  "  float R = r * (1.0 + 0.25 * s);\n" \
  "  float2 hv = max(hs, float2(R, R));\n" \
  "  return mb_sd_corner(max(hv - (p - k) * inward, float2(0.0, 0.0)), hv, r, s, band);\n" \
  "}\n" \
  "float mb_sd_clip(float2 p, float4 c, float4 r, float4 s, float band) {\n" \
  "  float2 hs = max((c.zw - c.xy) * 0.5, float2(0.0, 0.0));\n" \
  "  float2 q = abs(p - (c.xy + hs)) - hs;\n" \
  "  float d = length(max(q, float2(0.0, 0.0))) + min(max(q.x, q.y), 0.0);\n" \
  "  if (r.x > 0.0) d = max(d, mb_clip_corner(p, c.xy, float2(1.0, 1.0), hs, r.x, s.x, band));\n" \
  "  if (r.y > 0.0) d = max(d, mb_clip_corner(p, c.zy, float2(-1.0, 1.0), hs, r.y, s.y, band));\n" \
  "  if (r.z > 0.0) d = max(d, mb_clip_corner(p, c.zw, float2(-1.0, -1.0), hs, r.z, s.z, band));\n" \
  "  if (r.w > 0.0) d = max(d, mb_clip_corner(p, c.xw, float2(1.0, -1.0), hs, r.w, s.w, band));\n" \
  "  return d;\n" \
  "}\n" \
  "// A box's own corners: r at most its shorter half, as smooth as its size has room for (band: mb_sd_corner's).\n" \
  "float mb_sd_box(float2 p, float2 hs, float r, float band) {\n" \
  "  float room = min(hs.x, hs.y);\n" \
  "  float rr = min(r, room);\n" \
  "  return mb_sd_corner(p, hs, rr, mb_smoothness(rr, room), band);\n" \
  "}\n" \
  "// A shadow as Core Animation draws one (CALayer shadowRadius: a Gaussian blur of the shape, sigma its radius): the box\n" \
  "// of half sides hs about p, its corners r, blurred by sigma; how much of it covers p, 0 … 1. The blur across worked\n" \
  "// out whole (erf); along, four samples of the Gaussian over where it is not nothing (Evan Wallace's rounded box shadow).\n" \
  "float mb_erf(float x) {\n" \
  "  float s = sign(x);\n" \
  "  float a = abs(x);\n" \
  "  float t = 1.0 + (0.278393 + (0.230389 + 0.078108 * (a * a)) * a) * a;\n" \
  "  t = t * t;\n" \
  "  return s - s / (t * t);\n" \
  "}\n" \
  "float mb_shadow_row(float x, float y, float sigma, float r, float2 hs) {\n" \
  "  float delta = min(hs.y - r - abs(y), 0.0);\n" \
  "  float curved = hs.x - r + sqrt(max(0.0, r * r - delta * delta));\n" \
  "  float k = 0.7071067811865476 / sigma;\n" \
  "  return 0.5 * (mb_erf((x + curved) * k) - mb_erf((x - curved) * k));\n" \
  "}\n" \
  "float mb_shadow(float2 p, float2 hs, float r, float sigma) {\n" \
  "  float rr = min(r, min(hs.x, hs.y));\n" \
  "  float lo = clamp(-3.0 * sigma, p.y - hs.y, p.y + hs.y);\n" \
  "  float hi = clamp(3.0 * sigma, p.y - hs.y, p.y + hs.y);\n" \
  "  float st = (hi - lo) / 4.0;\n" \
  "  float y = lo + st * 0.5;\n" \
  "  float v = 0.0;\n" \
  "  for (int i = 0; i < 4; i++) {\n" \
  "    float g = exp(-(y * y) / (2.0 * sigma * sigma)) / (2.5066282746310002 * sigma);\n" \
  "    v += mb_shadow_row(p.x, p.y - y, sigma, rr, hs) * g * st;\n" \
  "    y += st;\n" \
  "  }\n" \
  "  return v;\n" \
  "}\n" \
  "// A shape (src/ui/shape.mbt, scene.mbt's kind 11): its pieces s (x0 y0 x1 y1 as shares of its band's rect r) worked\n" \
  "// into the pixel about p, scale its pixels a point. A fill's: each piece's crossings of 4 rows across the pixel, each\n" \
  "// counted by how much of the row lies left of it (+ going down, - going up); their sums over every piece, the rows'\n" \
  "// winding numbers across the pixel, make its cover (even_odd 1: by the even-odd rule, else the nonzero one).\n" \
  "// (mb4: v in all four; Direct3D's float4 takes no single number)\n" \
  "float4 mb4(float v) {\n" \
  "  return float4(v, v, v, v);\n" \
  "}\n" \
  "float4 mb_path_rows(float4 s, float4 r, float2 p, float scale) {\n" \
  "  float2 a = r.xy + s.xy * r.zw;\n" \
  "  float2 b = r.xy + s.zw * r.zw;\n" \
  "  if (a.y == b.y) return mb4(0.0);\n" \
  "  float dir = b.y > a.y ? 1.0 : -1.0;\n" \
  "  float4 ys = mb4(p.y) + float4(-0.375, -0.125, 0.125, 0.375) / scale;\n" \
  "  float4 in_ = step(mb4(min(a.y, b.y)), ys) * (mb4(1.0) - step(mb4(max(a.y, b.y)), ys));\n" \
  "  float4 xs = mb4(a.x) + (ys - mb4(a.y)) * ((b.x - a.x) / (b.y - a.y));\n" \
  "  return in_ * dir * clamp((xs - mb4(p.x)) * scale + mb4(0.5), mb4(0.0), mb4(1.0));\n" \
  "}\n" \
  "float mb_path_cover(float4 w, float even_odd) {\n" \
  "  float4 a = abs(w);\n" \
  "  float4 f = a - floor(a * 0.5) * 2.0;\n" \
  "  float4 c = even_odd > 0.5 ? mb4(1.0) - abs(mb4(1.0) - f) : min(a, mb4(1.0));\n" \
  "  return dot(c, mb4(0.25));\n" \
  "}\n" \
  "// A stroke's: how far p is from a piece (its ends round).\n" \
  "float mb_seg_dist(float4 s, float4 r, float2 p) {\n" \
  "  float2 a = r.xy + s.xy * r.zw;\n" \
  "  float2 ab = r.xy + s.zw * r.zw - a;\n" \
  "  float h = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-8), 0.0, 1.0);\n" \
  "  return length(p - a - ab * h);\n" \
  "}\n" \
  "// Which of a data instance's (kind 12) fours piece i is in: 0, 2, 3, 4, 6, 7 (shape.mbt seg_slots), six to an instance.\n" \
  "int mb_seg_slot(int i) {\n" \
  "  int s = i - (i / 6) * 6;\n" \
  "  return s + (s >= 1 ? 1 : 0) + (s >= 4 ? 1 : 0);\n" \
  "}\n" \
  "// How far to move a smooth ground (glass's frost) at the pixel px (in pixels) before it is written to 8 bits a\n" \
  "// channel, in steps of 1/255: Skia's ordered dither (GrDitherEffect, an 8x8 Bayer matrix by the pixel's place), never\n" \
  "// half a step either way. Without it a slope of a few steps across a wide frost is written as flat bands, an edge where\n" \
  "// each step is (contour lines); with it each pixel is the step above or below as often as the slope is near it, and\n" \
  "// a value already on a step stays it.\n" \
  "float mb_dither(float2 px) {\n" \
  "  int x = int(floor(px.x)) & 7;\n" \
  "  int y = (int(floor(px.y)) & 7) ^ x;\n" \
  "  int m = ((y & 1) << 5) | ((x & 1) << 4) | ((y & 2) << 2) | ((x & 2) << 1) | ((y & 4) >> 1) | ((x & 4) >> 2);\n" \
  "  return float(m) / 64.0 - 63.0 / 128.0;\n" \
  "}\n" \
  ""
