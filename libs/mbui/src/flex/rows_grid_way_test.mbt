// A size on its way down a page's list's rows on a host's pixels (Style's rows_grid: 2, 2.75, 3 and 3.5 a point) is
// put on the grid toward where it goes and never past where it rests: growing, up, no more than its rest as laid;
// shrinking, down, no less than its rest as laid. So a row closing to a rest on the grid or off it steps one way in
// whole pixels, never under its rest, there at its last look; and a row growing as another closes by as much (two ways
// mirrored, as a key coming into what a part closing gives back) sum to the same stretch at every look, nothing under
// them moving. Looked at every 10 ms from the way's moment.

///|
/// The grids looked on.
let rw_grids : Array[Double] = [2.0, 2.75, 3.0, 3.5]

///|
/// `v` on grid `g`, up (as a row at rest is laid).
fn rw_up(v : Double, g : Double) -> Double {
  (v * g - 0.000001).ceil() / g
}

///|
/// An item on its way in a column: from `from` tall to `to` (1: as tall as it is said, `natural`; 0: nothing), set out
/// at 0, still.
fn rw_way(natural : Double, from : Double, to : Double) -> @flex.Node {
  let n = @flex.Node::new()
  let s = n.style
  s.set_height(Pt(natural))
  s.shrink = 0.0
  s.come_from = from
  s.come_to = to
  s.come_v = 0.0
  s.come_at = 0.0
  s.come_now = 0.0
  s.come_goal = if to <= 0.0 { 0.0 } else { 0.0 / 0.0 }
  s.come_ends = if to <= 0.0 { @flex.come_way_ms(from, 0.0, 0.0) } else { 0.0 / 0.0 }
  s.come_plan = s.come_goal
  s.come_fill = to <= 0.0 || from <= 0.0
  n
}

///|
/// A page's list's column on grid `g` holding `items`, a row of 30 under them; laid out at `t` ms on their ways.
fn rw_column(g : Double, items : Array[@flex.Node]) -> (@flex.Node, @flex.Node) {
  let col = @flex.Node::new()
  col.style.position = Absolute
  col.style.set_width(Pt(300.0))
  col.style.rows_grid = g
  for n in items {
    col.add(n)
  }
  let under = @flex.Node::new()
  under.style.set_height(Pt(30.0))
  under.style.shrink = 0.0
  col.add(under)
  (col, under)
}

///|
/// Laid out at `t` ms on the ways of `items`.
fn rw_at(col : @flex.Node, items : Array[@flex.Node], t : Double, g : Double) -> Unit {
  for n in items {
    n.style.come_now = t
  }
  @flex.compute(col, round=false, reuse=false, grid=g)
}

///|
/// (On main this holds: put up, a closing row lands on its rest from above. It is what holds "never under its rest" once
/// closing rounds down: a floor alone takes a rest off the grid, 20.3, under its 20.5 as laid on a grid of 2.)
test "a row closing to a rest on and off a host's grid: down in whole pixels one way, never under its rest as laid, at it at its last look" {
  for g in rw_grids {
    for rest in [20.0, 20.3] {
      let item = rw_way(rest, 60.7, 1.0)
      let (col, _) = rw_column(g, [item])
      let seen = []
      let mut t = 0.0
      while t <= 600.0 {
        rw_at(col, [item], t, g)
        seen.push(item.height)
        t = t + 10.0
      }
      let floor = rw_up(rest, g)
      for i, h in seen {
        let px = h * g
        assert_true((px - px.round()).abs() < 0.001, msg="grid \{g}, rest \{rest}, look \{i}: \{h} not on the grid")
        assert_true(h >= floor - 0.001, msg="grid \{g}, rest \{rest}, look \{i}: \{h} under its rest \{floor}")
        if i > 0 {
          assert_true(h <= seen[i - 1] + 0.001, msg="grid \{g}, rest \{rest}, look \{i}: up from \{seen[i - 1]} to \{h}")
        }
      }
      let n = seen.length()
      assert_true((seen[n - 1] - floor).abs() < 0.001, msg="grid \{g}, rest \{rest}: \{seen[n - 1]} at its last look")
      assert_true(seen[n - 2] - floor < 1.0 / g + 0.001, msg="grid \{g}, rest \{rest}: \{seen[n - 2]} the look before")
    }
  }
}

///|
test "a row growing as another closes by as much on a host's grid: the two sum to the same stretch at every look, nothing under them moving" {
  for g in rw_grids {
    for h in [40.0, 40.3, 61.37] {
      let grows = rw_way(h, 0.0, 1.0)
      let closes = rw_way(h, h, 0.0)
      let items = [grows, closes]
      let (col, under) = rw_column(g, items)
      let mut first : Double? = None
      let mut t = 0.0
      while t <= 600.0 {
        rw_at(col, items, t, g)
        match first {
          None => first = Some(under.top)
          Some(was) =>
            assert_true(
              (under.top - was).abs() < 0.001,
              msg="grid \{g}, \{h}: at \{t} ms the row under them at \{under.top} (\{grows.height} + \{closes.height}), \{was} at first",
            )
        }
        t = t + 10.0
      }
    }
  }
}

///|
/// Item `n` set off again at `t` ms toward `to` (1: as tall as it is said; 0: nothing) from where its way has it then
/// and as fast, as a structure turns one back (the view's View::comes).
fn rw_turn(n : @flex.Node, to : Double, t : Double) -> Unit {
  let s = n.style
  let (from, v) = @flex.come_state(s, t).unwrap()
  s.come_from = from
  s.come_v = v
  s.come_to = to
  s.come_goal = if to <= 0.0 { 0.0 } else { 0.0 / 0.0 }
  s.come_at = t
  s.come_now = t
  s.come_ends = if to <= 0.0 { t + @flex.come_way_ms(from, v, 0.0) } else { 0.0 / 0.0 }
  s.come_plan = s.come_goal
  s.come_fill = true
}

///|
test "a row turned back on its way on a host's grid: at the turn a step of a device pixel at most, the way it then goes; on the grid, never past its rests, at its rest at its last look" {
  for g in rw_grids {
    for h in [40.0, 40.3, 61.37] {
      // (coming from nothing turned to go, and going turned to come, each at a few moments of its way)
      for case in [(0.0, 1.0, 0.0), (h, 0.0, 1.0)] {
        let (from, to, back) = case
        for turn_at in [30.0, 90.0, 170.0] {
          let item = rw_way(h, from, to)
          let (col, _) = rw_column(g, [item])
          let mut t = 0.0
          while t < turn_at {
            rw_at(col, [item], t, g)
            t = t + 10.0
          }
          rw_at(col, [item], turn_at, g)
          let was = item.height
          rw_turn(item, back, turn_at)
          rw_at(col, [item], turn_at, g)
          let step = item.height - was
          let goes = if back > 0.0 { 1.0 } else { -1.0 }
          let at = "grid \{g}, \{h}, to \{back} at \{turn_at} ms"
          assert_true(step.abs() <= 1.0 / g + 0.001, msg="\{at}: a step of \{step} at the turn (\{was} to \{item.height})")
          assert_true(step * goes >= -0.001, msg="\{at}: a step of \{step} at the turn, against the way it then goes")
          let rest = if back > 0.0 { rw_up(h, g) } else { 0.0 }
          let mut last = item.height
          t = turn_at + 10.0
          while t <= turn_at + 900.0 {
            rw_at(col, [item], t, g)
            last = item.height
            let px = last * g
            assert_true((px - px.round()).abs() < 0.001, msg="\{at}: \{last} at \{t} ms not on the grid")
            assert_true(last >= -0.001 && last <= rw_up(h, g) + 0.001, msg="\{at}: \{last} at \{t} ms past its rests")
            t = t + 10.0
          }
          assert_true((last - rest).abs() < 0.001, msg="\{at}: \{last} at its last look, its rest \{rest}")
        }
      }
    }
  }
}
