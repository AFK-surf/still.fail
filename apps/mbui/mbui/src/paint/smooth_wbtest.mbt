// smooth.mbt's corners against still.fail's (its apps/android/shared/src/test/kotlin/fail/still/android/ui/
// CornersTest.kt, the same assertions where they are of the curve rather than of Android's cubics): on the
// superellipse, a circle with no smoothing, as smooth as there is room for, never a jump as a box grows.

///|
/// A box 600 by 400 about the origin, its corner `r` drawn `s` smooth: the point of its top right corner's curve at
/// `a` (radians from the right edge's way round to the top's, about the corner's centre), and the curve's outward
/// normal there.
fn on_curve(r : Double, s : Double, a : Double) -> (Double, Double, Double, Double) {
  let n = 2.0 + (smooth_exponent - 2.0) * s
  let big = r * (1.0 + (smooth_scale - 1.0) * s)
  let c = @dmath.cos(a)
  let sn = @dmath.sin(a)
  let rho = @dmath.pow(@dmath.pow(c, n) + @dmath.pow(sn, n), -1.0 / n)
  let x = big * rho * c
  let y = big * rho * sn
  // the gradient of |x|^n + |y|^n
  let gx = @dmath.pow(x, n - 1.0)
  let gy = @dmath.pow(y, n - 1.0)
  let gl = (gx * gx + gy * gy).sqrt()
  (300.0 - big + x, 200.0 - big + y, gx / gl, gy / gl)
}

///|
test "a smooth corner is the web's superellipse: |x|^n + |y|^n = 1 over the radius a quarter longer" {
  assert_true((smooth_exponent * smooth_exponent - 8.0).abs() < 1.0e-12)
  // within a hundredth of a pixel of it over a radius of 200 (more than any the apps have at 4×: the wholly smooth
  // corner by its polynomials), and half way to it (a box with half the room, by its powers) within a millionth, of the
  // exponent half way (the curve itself: half smooth, this corner has little room across, and so eases a little into
  // its long edges as a capsule's end does, capsule_ease)
  for s in [(1.0, 0.01), (0.5, 1.0e-6)] {
    for j in 0..=40 {
      let (x, y, _, _) = on_curve(160.0, s.0, 1.5707963267948966 * j.to_double() / 40.0)
      let d = corner_shape(x, y, 300.0, 200.0, 160.0, s.0, 1.0e30)
      assert_true(d.abs() < s.1, msg="\{s.0} at \{j}: \{d} off the curve")
    }
  }
}

///|
test "with no smoothing it is a circle's arc: a round corner's distance, to the last place, as before" {
  for j in 0..=40 {
    let a = 1.5707963267948966 * j.to_double() / 40.0
    for off in [-3.0, -0.5, 0.0, 0.25, 2.0] {
      let x = 300.0 - 20.0 + (20.0 + off) * @dmath.cos(a)
      let y = 200.0 - 20.0 + (20.0 + off) * @dmath.sin(a)
      let qx = x - 300.0 + 20.0
      let qy = y - 200.0 + 20.0
      let round = (dmax(qx, 0.0) * dmax(qx, 0.0) + dmax(qy, 0.0) * dmax(qy, 0.0)).sqrt() +
        dmin(dmax(qx, qy), 0.0) -
        20.0
      assert_eq(sd_corner(x, y, 300.0, 200.0, 20.0, 0.0), round)
      assert_eq(sd_box(x, y, 300.0, 200.0, 20.0), sd_corner(x, y, 300.0, 200.0, 20.0, smoothness(20.0, 200.0)))
    }
  }
  // a capsule, its radius half its height: round
  assert_eq(smoothness(200.0, 200.0), 0.0)
}

///|
test "off the curve it is the distance along its normal: within a hundredth and a half of a pixel for an edge's cover" {
  // a corner of 160 (200 drawn) and one of 12 (15 drawn), a pixel either way of it (the cover is the half pixel)
  for r in [160.0, 12.0] {
    for j in 0..=40 {
      let (x, y, nx, ny) = on_curve(r, 1.0, 1.5707963267948966 * j.to_double() / 40.0)
      for off in [-1.0, -0.5, 0.5, 1.0] {
        let d = sd_corner(x + off * nx, y + off * ny, 300.0, 200.0, r, 1.0)
        assert_true((d - off).abs() < 0.015, msg="corner \{r} at \{j}, \{off} out: \{d}")
      }
    }
  }
}

///|
test "it leaves along the edges and only ever turns one way" {
  for s in [0.0, 0.3, 1.0] {
    let big = 20.0 * (1.0 + (smooth_scale - 1.0) * s)
    // where the curve meets the right edge, and the top: the edges' own distance on either side of the meeting
    for e in [-0.001, 0.001] {
      for off in [-0.5, 0.5] {
        assert_true((sd_corner(300.0 + off, 200.0 - big + e, 300.0, 200.0, 20.0, s) - off).abs() < 1.0e-3)
        assert_true((sd_corner(300.0 - big + e, 200.0 + off, 300.0, 200.0, 20.0, s) - off).abs() < 1.0e-3)
      }
    }
    // convex: between any two of its points, inside it
    for j in 0..<20 {
      for k in (j + 1)..=20 {
        let (x0, y0, _, _) = on_curve(20.0, s, 1.5707963267948966 * j.to_double() / 20.0)
        let (x1, y1, _, _) = on_curve(20.0, s, 1.5707963267948966 * k.to_double() / 20.0)
        assert_true(sd_corner((x0 + x1) / 2.0, (y0 + y1) / 2.0, 300.0, 200.0, 20.0, s) <= 1.0e-3)
      }
    }
  }
}

///|
test "a corner is as smooth as it has room for" {
  // a capsule's end and a circle (the radius half the side) are not smoothed; a quarter more room, wholly
  assert_eq(smoothness(26.0, 26.0), 0.0)
  assert_eq(smoothness(999.0, 26.0), 0.0)
  assert_eq(smoothness(26.0, 32.5), 1.0)
  assert_eq(smoothness(12.0, 200.0), 1.0)
  assert_true((smoothness(16.0, 18.0) - 0.5).abs() < 1.0e-12)
  assert_eq(smoothness(0.0, 20.0), 0.0)
  // growing, the radius drawn is never more than the room there is, and never jumps
  let mut last = 26.0
  for i in 0..=100 {
    let room = 26.0 + i.to_double() * 0.1
    let r = 26.0 * (1.0 + (smooth_scale - 1.0) * smoothness(26.0, room))
    assert_true(r <= room + 1.0e-9)
    assert_true(r - last >= 0.0 && r - last <= 0.11)
    last = r
  }
}

///|
test "concentric: a curve moved in is drawn as much smaller, a corner drawn a quarter larger than it is given" {
  assert_eq(concentric(26.0, 10.0), 18.0)
  assert_eq(concentric_out(18.0, 10.0), 26.0)
  assert_eq(concentric(6.0, 10.0), 0.0)
  // the middle of a corner of 20 (wholly smooth): on the curve, as far in from both edges
  let m = smooth_middle(20.0)
  assert_true(sd_corner(300.0 - m, 200.0 - m, 300.0, 200.0, 20.0, 1.0).abs() < 1.0e-3)
  // the inner box's corner drawn about the outer's corner's own centre: the same curve, as much smaller as it is in
  assert_eq(10.0 + concentric(26.0, 10.0) * smooth_scale, 26.0 * smooth_scale)
}

///|
/// The most a circle `r` round, centred `centre` in from both edges of a wholly smooth corner of 28 (a 300 by 200 box's
/// top right), is off an even gap from it (its distance from its edges, centre less r) anywhere along its quarter.
fn circle_off_even(centre : Double, r : Double) -> Double {
  let d = centre - r
  let mut most = 0.0
  for i in 0..=90 {
    let a = i.to_double() * 1.5707963267948966 / 90.0
    let x = centre - r * @dmath.cos(a)
    let y = centre - r * @dmath.sin(a)
    let gap = -sd_corner(300.0 - x, 200.0 - y, 300.0, 200.0, 28.0, 1.0)
    most = dmax(most, (gap - d).abs())
  }
  most
}

///|
test "a circle in a smooth corner follows it as round_like's round corner: an even gap within 1.25% of its radius" {
  // (the user, 2026-10-27: 中型屏的单行 composer 跟圆角还是对不上: a capsule 48 high 4 in from a corner of 28)
  let k = round_like(28.0)
  assert_true((k - 28.0 * smooth_round).abs() < 1.0e-12)
  for r in [8.0, 16.0, 22.0] {
    assert_true(circle_off_even(k, r) < 0.0125 * 28.0, msg="a circle \{r} round: \{circle_off_even(k, r)}")
    // centred the corner's whole radius in, as in a round one: off by over twice as much at the curve's middle
    assert_true(circle_off_even(28.0, r) > 0.025 * 28.0)
  }
  // a capsule's end (no room to be smooth) is round: itself; between, as smooth as its box has room for
  assert_eq(round_like(20.0, room=20.0), 20.0)
  assert_true(round_like(20.0, room=22.5) > round_like(20.0) && round_like(20.0, room=22.5) < 20.0)
  // and back
  for c in [(28.0, 1.0e30), (20.0, 20.0), (20.0, 22.5), (34.0, 1.0e30)] {
    let (r, room) = c
    assert_true((round_like_out(round_like(r, room~), room~) - r).abs() < 1.0e-9)
  }
}

///|
test "the middle of a corner as smooth as its box has room for: on the curve, as far in from both edges" {
  // a square 30 across: a circle, a corner a little too round to be wholly smooth, one wholly smooth
  for c in [(15.0, 15.0), (13.0, 15.0), (7.0, 15.0)] {
    let (r, room) = c
    let m = corner_middle(r, room)
    assert_true(sd_box(room - m, room - m, room, room, r).abs() < 1.0e-3)
  }
  assert_true((corner_middle(15.0, 15.0) - 15.0 * (1.0 - (0.5).sqrt())).abs() < 1.0e-9)
  // with room enough, smooth_middle's
  assert_true((corner_middle(20.0, 1.0e6) - smooth_middle(20.0)).abs() < 1.0e-12)
}

///|
test "det_pow: the power by + - × ÷ alone, as @dmath.pow's within a few units in the last place" {
  for x in [1.0e-30, 1.0e-6, 0.001, 0.1, 0.25, 0.5, 0.7071, 0.9, 0.999999, 1.0, 1.3, 1.9999, 2.0] {
    for e in [0.353553, 0.5, 1.0, 1.4, 1.8284271247461903, 2.0, 2.8284271247461903] {
      let want = @dmath.pow(x, e)
      let got = det_pow(x, e)
      assert_true((got - want).abs() <= want * 4.0e-14, msg="\{x}^\{e}: \{got}, not \{want}")
    }
  }
  assert_eq(det_pow(0.0, 2.0), 0.0)
}

///|
test "worked out within a band of the curve only: the same there; beyond it, of the same sign and at least as far" {
  for r in [20.0, 6.0] {
    for j in 0..=40 {
      let (x, y, nx, ny) = on_curve(r, 1.0, 1.5707963267948966 * j.to_double() / 40.0)
      for k in -40..=40 {
        let off = k.to_double() / 4.0
        let px = x + off * nx
        let py = y + off * ny
        let exact = sd_corner(px, py, 300.0, 200.0, r, 1.0)
        let banded = sd_corner(px, py, 300.0, 200.0, r, 1.0, band=2.0)
        if exact.abs() < 2.0 {
          assert_eq(banded, exact)
        } else {
          assert_true(banded * exact > 0.0 && banded.abs() >= 2.0, msg="\{r} \{j} \{off}: \{banded}, \{exact}")
        }
      }
    }
  }
}

///|
test "the wholly smooth corner's polynomials are its factors within 2e-5" {
  let n = smooth_exponent
  for i in 0..=1000 {
    let t = i.to_double() / 1000.0
    let tn1 = if t == 0.0 { 0.0 } else { @dmath.pow(t, n - 1.0) }
    let tn = tn1 * t
    let u = @dmath.pow(1.0 + tn, 1.0 / n)
    let g = (1.0 + tn1 * tn1).sqrt()
    assert_true((smooth_a(t) - (1.0 + tn) / g).abs() < 2.0e-5, msg="a at \{t}")
    assert_true((smooth_b(t) - (1.0 + tn) / (u * g)).abs() < 2.0e-5, msg="b at \{t}")
  }
}

///|
/// How far below the top edge a capsule 300 by 80 (its corners 40) has its top edge `u` r from its right tip, in r: the
/// point on that column where sd_box is 0, by halving.
fn capsule_drop(hx : Double, u : Double) -> Double {
  let x = hx - 40.0 * u
  let mut lo = 0.0
  let mut hi = 40.0
  for _ in 0..<60 {
    let mid = (lo + hi) / 2.0
    if sd_box(x, mid, hx, 40.0, 40.0) <= 0.0 {
      lo = mid
    } else {
      hi = mid
    }
  }
  (40.0 - lo) / 40.0
}

///|
test "a capsule's end is Apple's: the circle's at its middle, easing into the long edges until 2 r from the tip" {
  // (the user, 2026-10-31: 苹果的那个按钮就看不出直线和半圆的接点) measured off iOS 26's alert button 144 high, top and
  // bottom of both ends: how far below the edge its outline lies, in r, u r from the tip
  let apple = [
    (0.325, 0.2628),
    (0.525, 0.1225),
    (0.725, 0.0507),
    (0.825, 0.0328),
    (0.925, 0.0183),
    (1.025, 0.0134),
    (1.125, 0.0097),
    (1.225, 0.0046),
    (1.325, 0.0035),
    (1.525, 0.0004),
  ]
  for p in apple {
    let (u, want) = p
    let got = capsule_drop(150.0, u)
    assert_true((got - want).abs() < 0.005, msg="at \{u} r: \{got}, Apple's \{want}")
  }
  // the circle's at its middle, the edge's from 2 r in; a circle met the edge at r with nothing left
  for u in [0.1, 0.2, 0.3] {
    let circle = 1.0 - (u * (2.0 - u)).sqrt()
    assert_true((capsule_drop(150.0, u) - circle).abs() < 1.0e-9, msg="at \{u}: \{capsule_drop(150.0, u)}, the circle \{circle}")
  }
  assert_true(capsule_drop(150.0, 1.0) > 0.01)
  assert_true(capsule_drop(150.0, 2.0) < 1.0e-9)
  // it only ever comes nearer the edge, and bends less and less into it: no bump, no second turn
  let mut last = capsule_drop(150.0, 0.0)
  let mut last_slope = -1.0e9
  for i in 1..=200 {
    let u = i.to_double() * 0.01
    let d = capsule_drop(150.0, u)
    assert_true(d <= last + 1.0e-9, msg="back out at \{u}")
    if u > 1.2 {
      let slope = (d - last) / 0.01
      assert_true(slope >= last_slope - 1.0e-6, msg="bends back at \{u}")
      last_slope = slope
    }
    last = d
  }
  // along the straight edge and round the tip the distance is the edge's and the circle's
  for off in [-0.5, 0.5] {
    assert_true((sd_box(0.0, 40.0 + off, 150.0, 40.0, 40.0) - off).abs() < 1.0e-12)
    assert_true((sd_box(150.0 + off, 0.0, 150.0, 40.0, 40.0) - off).abs() < 1.0e-12)
  }
}

///|
test "how far a capsule's end eases in goes with the room it has: a circle round, none at once as it grows" {
  // a circle 80 across: a circle's distance
  for j in 0..=40 {
    let a = 1.5707963267948966 * j.to_double() / 40.0
    for off in [-1.0, 0.0, 1.0] {
      let x = (40.0 + off) * @dmath.cos(a)
      let y = (40.0 + off) * @dmath.sin(a)
      let l = (x * x + y * y).sqrt()
      assert_true((sd_box(x, y, 40.0, 40.0, 40.0) - (l - 40.0)).abs() < 1.0e-12)
    }
  }
  // standing up, the same as lying down
  for u in [0.5, 0.9, 1.3] {
    let x = 150.0 - 40.0 * u
    for y in [37.0, 39.5, 40.5] {
      assert_eq(sd_box(y, x, 40.0, 150.0, 40.0), sd_box(x, y, 150.0, 40.0, 40.0))
    }
  }
  // a capsule growing from a circle: its outline at r from the tip never jumps
  let mut last = capsule_drop(40.0, 1.0)
  for i in 1..=120 {
    let d = capsule_drop(40.0 + i.to_double() * 0.5, 1.0)
    assert_true((d - last).abs() < 0.001, msg="jumps at \{40.0 + i.to_double() * 0.5}")
    last = d
  }
  // a corner with room across (wholly smooth), and a round one given in a big box (a window's): not eased
  assert_eq(capsule_ease(1.0, 0.0), 0.0)
  assert_eq(sd_box(140.0, 30.0, 150.0, 40.0, 12.0), sd_corner(140.0, 30.0, 150.0, 40.0, 12.0, 1.0))
}
