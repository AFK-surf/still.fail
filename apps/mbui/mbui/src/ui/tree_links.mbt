// The links a node's words in pieces lead to (View::words_runs: runs with a `link`), pressed as an old view's
// paragraph's are (Ctx::rich): where the pieces of line their words are drawn on are (rich_link_pieces, as the node lays
// them out and draws them: view_runs_laid), the rest of the node passing a finger on to what is under it; a link's
// runs one after another one link (link_first). Pressed, that link's pressed ground under it alone; tapped (a finger's
// tap, a mouse's click let go on it), where it leads told; held a long press's time by a finger, or right clicked, told
// with the piece of line under it, and nothing tapped as it is let go. Each told at its event's moment.

///|
/// What a node's links are as it shows them: which one the pointer is on (by its link's first run; -1 none), as it
/// moves onto one and off it.
pub struct RunsLinks {
  pointed : @signals.Signal[Int]
}

///|
/// Node `v`'s links (its words in pieces, `runs` as they are now: what it is told by View::words_runs), pressed:
/// `tap` told where one leads as it is tapped; `hold` where it leads and the piece of line under the finger or the
/// pointer (in the window: x, y, w, h) as it is held a long press's time or right clicked; `shown` each link's way,
/// its words and its first run as they change (what shows over one while it is pointed at: RunsLinks' `pointed`).
pub fn runs_links(
  v : @view.View,
  runs : () -> Array[Run],
  tap : (String) -> Unit,
  hold? : (String, (Double, Double, Double, Double)) -> Unit,
  shown? : (Array[(String, String, Int)]) -> Unit,
) -> RunsLinks {
  let pointed = @signals.signal(-1)
  let held = @signals.signal(-1)
  v.runs_pressed(By(fn() { held.get() })) |> ignore
  // (where its links' pieces are as it is laid out now, in its own terms: its words and how they are set as it holds
  // them now (View::runs_set_now: what it is laid out and drawn from, not what the frame before drew), laid out as wide
  // as it is in them as of the moment (View::laid_size, laying out what was said before it), not as big as it is drawn)
  let pieces = fn() -> Array[(Int, Double, Double, Double, Double)] {
    let w = v.laid_size().0
    let (rs, look, set) = v.runs_set_now()
    guard !rs.is_empty() else { return [] }
    let (r, lay, _) = view_runs_laid(rs, look, set, w)
    rich_link_pieces(r, lay, 0.0, 0.0, center_in=if v.words_centered_now() { w } else { -1.0 })
  }
  let piece_at = fn(x : Double, y : Double) -> (Int, Double, Double, Double, Double)? {
    pieces().iter().find_first(fn(p) { x >= p.1 && x < p.3 && y >= p.2 && y < p.4 })
  }
  let href = fn(k : Int) {
    let rs = @signals.untracked(runs)
    if k >= 0 && k < rs.length() {
      rs[k].link
    } else {
      ""
    }
  }
  // (the piece in the window: where it is drawn, as big as it is drawn there)
  let in_window = fn(p : (Int, Double, Double, Double, Double)) {
    let (x, y, w, _) = v.rect()
    let lw = v.laid_size().0
    let s = if lw > 0.0 { w / lw } else { 1.0 }
    (x + p.1 * s, y + p.2 * s, (p.3 - p.1) * s, (p.4 - p.2) * s)
  }
  // (a finger taken where its links' pieces are alone)
  v.takes(fn(_, _, _) { pieces().map(fn(p) { (p.1, p.2, p.3, p.4) }) }) |> ignore
  // (held: no tap of it as it is let go)
  let was_held = Ref(false)
  let told = fn(d : @view.Drag, f : (Int, (Double, Double, Double, Double)) -> Unit) {
    match piece_at(d.x, d.y) {
      Some(p) => f(p.0, in_window(p))
      None => ()
    }
  }
  // (held a long press's time: where something is to be done of it alone; else a finger's long press let go on it a
  // tap, as an old view's paragraph's with no hold of its own)
  let hold_by = match hold {
    Some(f) =>
      Some(
        (
          long_press_ms,
          fn(d : @view.Drag) {
            if pointing() is Finger {
              was_held.val = true
              held.set(-1)
              told(d, fn(k, rect) { f(href(k), rect) })
            }
          },
        ),
      )
    None => None
  }
  v.gesture(
    touch_slop(),
    press=fn(d) {
      was_held.val = false
      match piece_at(d.x, d.y) {
        Some(p) => held.set(p.0)
        None => ()
      }
    },
    tap=fn(d) {
      held.set(-1)
      if !was_held.val {
        told(d, fn(k, _) { tap(href(k)) })
      }
    },
    hold?=hold_by,
    drag=fn(d) {
      match d.kind {
        Up => {
          // (a mouse's click let go on the link it went down on, however long held: as a tap)
          if pointing() is Mouse && !was_held.val {
            match piece_at(d.x, d.y) {
              Some(p) if p.0 == held.untracked() => tap(href(p.0))
              _ => ()
            }
          }
          held.set(-1)
        }
        Off => held.set(-1)
        _ => ()
      }
    },
  )
  |> ignore
  // (right clicked: as held)
  match hold {
    Some(f) =>
      v.on_menu(fn(m) {
        match piece_at(m.x, m.y) {
          Some(p) => f(href(p.0), in_window(p))
          None => ()
        }
      })
      |> ignore
    None => ()
  }
  // (the pointer onto a link and off it, as it moves)
  let point = fn() {
    let k = match v.pointer_here() {
      Some((x, y)) =>
        match piece_at(x, y) {
          Some(p) => p.0
          None => -1
        }
      None => -1
    }
    pointed.set(k)
  }
  v.on_pointer_moved(point) |> ignore
  // (what changes which piece is under a pointer that stays where it is: what lies over it come or gone (whether it is
  // pointed at), it or what holds it moved, grown or its words set again: which one the tree works out as it places
  // things, View::pointer_piece; told as that changes)
  v.reacts(
    fn() {
      // (only while it is pointed at: none of its links pointed at otherwise)
      if v.pointed() {
        v.pointer_piece(fn(x, y) {
          match piece_at(x, y) {
            Some(p) => p.0
            None => -1
          }
        })
      } else {
        -1
      }
    },
    fn(k) { pointed.set(k) },
  )
  // (each link told as the runs are: its way, its words, its first run)
  match shown {
    Some(f) =>
      v.reacts(
        fn() {
          let rs = runs()
          let out = []
          for k, r in rs {
            if link_starts(rs, k) {
              let words = StringBuilder()
              let mut j = k
              while j < rs.length() && rs[j].link == r.link {
                words.write_string(rs[j].text)
                j = j + 1
              }
              out.push((r.link, words.to_string(), k))
            }
          }
          out
        },
        f,
      )
    None => ()
  }
  { pointed, }
}
