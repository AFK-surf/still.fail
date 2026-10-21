// src/host/corner.sl as a C string (scripts/corner_sl.py makes it: edit corner.sl, then run it). The shaders
// write float2; GLSL's take it with `#define float2 vec2` before it.
#define MB_CORNER_SL \
  "// mbui's corners (src/ui/smooth.mbt: these are its smoothness, sd_corner and sd_box, number for number), the one copy\n" \
  "// every renderer draws by: Metal's, Direct3D's and both GLs' shaders take it in as it is (corner_sl.h; web/host.js\n" \
  "// between its \"corner.sl\" lines), written in what the four have in common (float2: GLSL's vec2, defined so before it).\n" \
  "// Made into those by scripts/corner_sl.py, which CI runs with --check.\n" \
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
  "// A box's own corners: r at most its shorter half, as smooth as its size has room for (band: mb_sd_corner's).\n" \
  "float mb_sd_box(float2 p, float2 hs, float r, float band) {\n" \
  "  float room = min(hs.x, hs.y);\n" \
  "  float rr = min(r, room);\n" \
  "  return mb_sd_corner(p, hs, rr, mb_smoothness(rr, room), band);\n" \
  "}\n" \
  ""
