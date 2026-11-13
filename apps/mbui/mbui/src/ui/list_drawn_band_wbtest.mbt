// A page's list scrolled (View::scrolls_window, its blocks reused), the same input given at the same moments at 60,
// 120 and 24 frames a second (Tester::input_at): in each frame as the host is given it, no band of where the list
// shows is drawn by no row (the row come to meet it drawn in the frame it came, never a frame late); and at each moment
// two rates both draw, what is drawn where the list shows is the same to the bit. Which block takes which key, and
// which key a block is made for, may differ by rate (a block shows nothing of its last key: answering.mbt); that is
// printed, not held.

///|
/// How tall key `k`'s row is: 64 for every fifth, else 40 (all counted 40 before they are laid out).
fn band_tall(k : Int) -> Double {
  if k % 5 == 0 {
    64.0
  } else {
    40.0
  }
}

///|
/// Key `k`'s row's ground, its own: found again by it in the draw list.
fn band_ground(k : Int) -> Int64 {
  0x40000000L + (k + 10).to_int64() * 0x100L + 0xFFL
}

///|
/// One frame as drawn: its number, the input it fell in, its moment, the tallest band of where the list shows drawn by
/// no row and where it starts, and the rows drawn there (key, top, foot), top down.
priv struct BandFrame {
  n : Int
  phase : String
  at : Double
  gap : Double
  gap_at : Double
  rows : Array[(Int, Double, Double)]
}

///|
/// A list 300 tall at the top of a window 300 by 400, of 300 keys, each a block of one kind reused, a row of words on
/// a ground of its own; drawn at `period` ms a frame. What its blocks did, in order (`log`); each frame as drawn
/// (`frames`); what each frame drew where the list shows (its plain rectangles and its words meeting the list's 300 by
/// 300, each number by its bits), by its moment in microseconds (`shots`).
priv struct BandCase {
  t : Tester
  log : Array[String]
  frames : Array[BandFrame]
  phase : Ref[String]
  shots : Map[Int64, Array[String]]
}

///|
fn band_case(
  period : Double,
  scale? : Double = 2.0,
  on_pixels? : Bool = false,
  scroll? : @view.Scroll = @view.Scroll::list(),
) -> BandCase {
  let log : Array[String] = []
  let t = Tester::new(fn(_c) {  }, w=300.0, h=400.0, platform=0, scale~)
  t.set_rows_on_pixels(on_pixels)
  t.check_looks(false)
  t.set_frame_period(period)
  let blocks = Ref(0)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
      col.scrolls_window(
        scroll,
        fn() { Array::makei(300, fn(i) { i }) },
        est=40.0,
        fn(_, _) { @halt.saying("every block is of a kind another may take") },
        reused=fn(_) { Some(0) },
        make_reused=fn(b, key) {
          blocks.val = blocks.val + 1
          let n = blocks.val
          log.push("made #\{n} \{@signals.untracked(key)}")
          b.owns(fn() { log.push("gone #\{n}") }) |> ignore
          let shown = Ref(-1)
          b.box(fn(row) {
            row
            .height(By(fn() { Some(band_tall(key())) }))
            .ground(By(fn() { band_ground(key()) }))
            .words(By(fn() {
              let k = key()
              if shown.val != k {
                shown.val = k
                log.push("#\{n} shows \{k}")
              }
              "row \{k}"
            }))
            |> ignore
          })
          |> ignore
        },
      )
      |> ignore
    })
    |> ignore
  })
  let c = { t, log, frames: [], phase: Ref("made"), shots: Map([]) }
  t.each_frame(Some(fn() { band_frame(c) }))
  t.draw()
  c
}

///|
/// Each frame as drawn: the rows' grounds where the list shows (by their keys), their bands put together, the tallest
/// band between 0 and 300 none of them covers; and what it drew there, by its moment.
fn band_frame(c : BandCase) -> Unit {
  let rows : Array[(Int, Double, Double)] = []
  let bits = fn(v : Double) { v.reinterpret_as_int64().to_string() }
  let shot : Array[String] = []
  let meets = fn(x : Double, y : Double, w : Double, h : Double) { x < 300.0 && x + w > 0.0 && y < 300.0 && y + h > 0.0 }
  for r in c.t.drawn_rects() {
    if meets(r.0, r.1, r.2, r.3) {
      shot.push("rect \{bits(r.0)} \{bits(r.1)} \{bits(r.2)} \{bits(r.3)} \{r.4}")
    }
    let g = r.4 - 0x40000000L - 0xFFL
    if r.0 < 1.0 && r.2 > 250.0 && g >= 0L && g % 0x100L == 0L && g / 0x100L < 1000L && meets(r.0, r.1, r.2, r.3) {
      rows.push(((g / 0x100L).to_int() - 10, r.1, r.1 + r.3))
    }
  }
  for w in c.t.words() {
    if meets(w.1, w.2, w.3, w.4) {
      shot.push("words \{w.0} \{bits(w.1)} \{bits(w.2)} \{bits(w.3)} \{bits(w.4)} \{bits(w.5)}")
    }
  }
  rows.sort_by(fn(a, b) { a.1.compare(b.1) })
  let mut at = 0.0
  let mut gap = 0.0
  let mut gap_at = 0.0
  for b in rows {
    if b.1 > at + 1.0e-9 && b.1 - at > gap {
      gap = b.1 - at
      gap_at = at
    }
    at = dmax(at, b.2)
  }
  if rows.is_empty() {
    gap = 300.0
  } else if at < 300.0 - 1.0e-9 && 300.0 - at > gap {
    gap = 300.0 - at
    gap_at = at
  }
  c.frames.push({ n: c.frames.length() + 1, phase: c.phase.val, at: c.t.time(), gap, gap_at, rows })
  c.shots[(c.t.time() * 1000.0).round().to_int64()] = shot
}

///|
/// A frame as words: its number, input, moment, band, and its rows.
fn band_said(f : BandFrame) -> String {
  let rows = f.rows.map(fn(r) { "\{r.0}@\{r.1}-\{r.2}" })
  "f\{f.n} \{f.phase} t=\{f.at} band \{f.gap} from \{f.gap_at}: \{Repr(rows)}"
}

///|
/// The same string of input, each at its own moment from the Tester's start whatever the frames (Tester::input_at): a
/// slow drag down 200 (5 a move), wheel turns of 120 one after another, one wheel turn of 260 (over a whole row and
/// more in one frame), a quick drag let go (a fling), coasting to rest; then back up by the wheel.
fn band_walk(c : BandCase) -> Unit {
  let t = c.t
  let t0 = t.origin
  let at = fn(ms : Double) { t.input_at(t0 + ms) }
  at(500.0)
  c.phase.val = "slow drag"
  t.drag(150.0, 280.0, 150.0, 80.0, steps=40)
  c.phase.val = "wheel 120s"
  for i in 0..<8 {
    at(1500.0 + 50.0 * i.to_double())
    t.wheel(150.0, 150.0, 120.0)
  }
  at(2200.0)
  c.phase.val = "wheel 260"
  t.wheel(150.0, 150.0, 260.0)
  at(2700.0)
  c.phase.val = "fling"
  t.drag(150.0, 280.0, 150.0, 30.0, steps=3)
  c.phase.val = "wheel back"
  for i in 0..<6 {
    at(5500.0 + 50.0 * i.to_double())
    t.wheel(150.0, 150.0, -200.0)
  }
  at(6800.0)
}

///|
test "a page's list scrolled slowly, by the wheel, by over a row at once and by a fling, at 60, 120 and 24 a second, on 1, 2, 2.75, 3 and 3.5 pixels a point: in each frame drawn, where it shows is drawn by its rows, no band left" {
  let faults = []
  let runs = [(2.0, false), (1.0, true), (2.0, true), (2.75, true), (3.0, true), (3.5, true)]
  for run in runs {
    let (scale, on_pixels) = run
    for p in [1000.0 / 60.0, 1000.0 / 120.0, 1000.0 / 24.0] {
      let c = band_case(p, scale~, on_pixels~)
      band_walk(c)
      let banded = c.frames.filter(fn(f) { f.gap > 0.0 })
      if banded.length() > 0 {
        let first = banded[0]
        let next = match c.frames.get(first.n) {
          Some(g) => band_said(g)
          None => "none"
        }
        faults.push(
          "\{scale} a point\{if on_pixels { " on its pixels" } else { "" }} at \{1000.0 / p} a second: \{banded.length()} of \{c.frames.length()} frames, the first \{band_said(first)}; next \{next}",
        )
      }
    }
  }
  assert_eq(faults, [])
}

///|
/// On 2 pixels a point and on a host's pixels of 2.75, 3 and 3.5 a point, what is drawn at a moment two rates share is
/// the same to the bit: a frame's moment is one double at every rate that draws it (the Tester's grid, its frames worked
/// out at once: tester_time.mbt's grid_moment), a fling's place there one double, and a row's place where it is drawn
/// one. Till 2026-11-12 the grid's moments were k periods of 1000/24 against 5k of 1000/120, a few last bits apart, and
/// 2.75 was held only to a millionth of a point (the coordinator of the migration, 2026-11-12: held to the bit once the
/// Tester's moments were worked out once each).
test "a page's list given the same input at the same moments at 60, 120 and 24 frames a second: at each moment two of them draw, what is drawn where it shows is the same to the bit, on 2 pixels a point and on 2.75, 3 and 3.5" {
  let faults = []
  for run in [(2.0, false), (2.75, true), (3.0, true), (3.5, true)] {
    let (scale, on_pixels) = run
    let cases = []
    for p in [1000.0 / 60.0, 1000.0 / 120.0, 1000.0 / 24.0] {
      let c = band_case(p, scale~, on_pixels~)
      band_walk(c)
      cases.push((1000.0 / p, c))
    }
    // (each of the 60 run's and the 24 run's moments is one of the 120 run's)
    let (_, c120) = cases[1]
    for i in [0, 2] {
      let (rate, c) = cases[i]
      let (mine, theirs) = (c.shots, c120.shots)
      let moments = mine.keys().filter(fn(k) { theirs.contains(k) }).collect()
      moments.sort()
      let differ = moments.filter(fn(k) { mine[k] != theirs[k] })
      match differ.get(0) {
        Some(k) => {
          let a = mine[k]
          let b = theirs[k]
          faults.push(
            "\{scale} a point, \{rate} against 120: \{differ.length()} of \{moments.length()} moments, the first t=\{k.to_double() / 1000.0}: only at \{rate} \{Repr(a.filter(fn(e) { !b.contains(e) }))}; only at 120 \{Repr(b.filter(fn(e) { !a.contains(e) }))}",
          )
        }
        None => ()
      }
      // (which block takes which key, and which key a block is made for: printed, not held)
      if c.log != c120.log {
        println("list_drawn_band: on \{scale}, at \{rate} the blocks take their keys otherwise than at 120 (\{c.log.length()} events against \{c120.log.length()})")
      }
      if moments.length() < mine.length() * 9 / 10 {
        faults.push("\{scale} a point, \{rate} against 120: only \{moments.length()} of \{mine.length()} moments shared")
      }
    }
  }
  assert_eq(faults, [])
}
