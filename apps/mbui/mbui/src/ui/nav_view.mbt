// A stack of pages (Nav) held by the window's tree (src/view; docs/retained.md, the way there's 4): the stack a node of
// its own, each page in it a node made as the page is put on the stack and let go as it leaves it (what the page made
// for it forgotten then: Nav's on_leave), and in it, while the page shows (the top; the one beside it as one moves),
// the page itself, an old view (`old`) built the old way. Which pages show and where they are drawn are bindings of
// those nodes: what shows changes as the stack is told to (its moment the cause's: Nav::go); where a page is drawn is
// worked out from the time it is drawn at (its slide said once as it sets out: where from, where to, from when, how
// long), followed by a finger as it holds one. Its slide's end is a moment of the tree's timeline (View::at_moment),
// whatever frames are drawn: the page that slid away let go there, and the one under a page come to rest no longer
// shown. A page pushed to show what the core has for it (`ready`) sets out as it has it (the moment that answer came),
// `most` ms after it was pushed at the latest (Nav::comes_when's wait, said once).
//
// What is the old frame's still (the way there): back. The page on top takes it first, then the stack (its swipe from
// the edge, the system's gesture, as Ctx::nav does); said as the page's old view is built, in the tree's order, by the
// view itself (NavPage's island, nav_page_built).

///|
/// What the window's tree gives a stack it holds: its moment now (a change's cause's), how big it is laid out then, and what it is told as a page
/// sets out (Nav::go: its slide's end, or its wait, said on the tree's timeline).
priv struct NavHosted {
  now : () -> Double
  room : () -> (Double, Double)
  went : () -> Unit
}

///|
/// What shows of the stack changed (which pages, how they move): what reads it told.
fn[P] Nav::shown_told(self : Nav[P]) -> Unit {
  self.shown.set(@signals.untracked(fn() { self.shown.get() }) + 1)
}

///|
/// Where the top page is at `now`, in its widths off to its side, as its slide has it (from where it set out, by when
/// and how), or where it is held (by a finger, waiting, at rest).
fn[P] Nav::p_at(self : Nav[P], now : Double) -> Double {
  if (self.mode == 1 || self.mode == 2 || self.mode == 4) && self.t0 >= 0.0 {
    let t = if self.dur <= 0.0 || now >= self.t0 + self.dur {
      1.0
    } else {
      dmax((now - self.t0) / self.dur, 0.0)
    }
    let (x, _) = move_path(self.p0 - self.p1, self.v0, t * self.dur, self.dur)
    self.p1 + x
  } else {
    self.p
  }
}

///|
/// The page `serial` (on the stack, or leaving it).
fn[P] Nav::entry(self : Nav[P], serial : Int) -> NavPage[P]? {
  match self.leaving {
    Some(e) if e.serial == serial => return Some(e)
    _ => ()
  }
  self.pages.iter().find_first(fn(e) { e.serial == serial })
}

///|
/// The top page and the one beside it as one moves (the one under it: the page under one pushed, the page left on top
/// as one goes back), if one does.
fn[P] Nav::top_beside(self : Nav[P]) -> (NavPage[P], NavPage[P]?) {
  let n = self.pages.length()
  match self.leaving {
    Some(e) => (e, Some(self.pages[n - 1]))
    None => (self.pages[n - 1], if self.mode != 0 && n > 1 { Some(self.pages[n - 2]) } else { None })
  }
}

///|
/// Whether page `serial` shows: the top, or the one beside it as one moves (read: told as it changes).
fn[P] Nav::shows(self : Nav[P], serial : Int) -> Bool {
  self.said.get() |> ignore
  self.shown.get() |> ignore
  let (top, beside) = self.top_beside()
  top.serial == serial || (beside is Some(b) && b.serial == serial)
}

///|
/// Whether page `serial` takes presses: not as it goes back off the stack, nor under a page coming in over it (read:
/// told as that changes).
fn[P] Nav::takes(self : Nav[P], serial : Int) -> Bool {
  self.said.get() |> ignore
  self.shown.get() |> ignore
  let n = self.pages.length()
  let leaving = self.leaving is Some(l) && l.serial == serial
  let top = !leaving && self.pages[n - 1].serial == serial
  !(leaving || (self.mode == 1 && !top))
}

///|
/// How far page `serial` is drawn off its place at `now`, as the stack moves (the top off to its side, the one beside
/// it edge to edge with it; one that rose up and down over the one under it, which stays): read as
/// it is drawn (told as the stack changes; with the clock while it slides, the finger while it is held by one), in its
/// own widths and heights: as big as the frame drawing it lays it out (View::shift).
fn[P] Nav::shift_of(self : Nav[P], serial : Int, now : () -> Double) -> (Double, Double) {
  self.said.get() |> ignore
  self.shown.get() |> ignore
  if self.mode == 0 {
    return (0.0, 0.0)
  }
  let p = if self.mode == 3 {
    self.finger.get() |> ignore
    self.p
  } else if self.t0 >= 0.0 {
    self.p_at(now())
  } else {
    self.p
  }
  let (top, beside) = self.top_beside()
  let rising = top.rise
  let way = if (self.from_left)(top.page) { -1.0 } else { 1.0 }
  if top.serial == serial {
    if rising {
      (0.0, p)
    } else {
      (way * p, 0.0)
    }
  } else if beside is Some(b) && b.serial == serial && !rising {
    (way * (p - 1.0), 0.0)
  } else {
    (0.0, 0.0)
  }
}

///|
/// The stacks the window's tree holds, each told as a frame of the old view begins (nav_views_framed): by a number of
/// its own.
// kept across runs: put back as a run begins (view_forget)
let nav_views : Array[(Int, (Ctx) -> Unit)] = []

///|
// kept across runs: a count
let nav_views_made : Ref[Int] = Ref(0)

///|
/// As a frame of the old view begins: each stack the tree holds says what a frame says of a stack (Ctx::nav: when it
/// rests, a page held by a finger), for what reads it of the frame (a test's nav_rest, the corners' checks).
fn nav_views_framed(c : Ctx) -> Unit {
  for e in nav_views {
    (e.1)(c)
  }
}

///|
/// Stack `nav` as a node of `v`'s, filling the room it is given (nav_view.mbt above): each page built by `page` (its
/// old view), on a ground of `bg`; back taken within `edge` of its left side. A page pushed slides in once `ready`
/// says it has what it shows, `most` ms after it was pushed at the latest (none: at once).
pub fn[P] nav_view(
  v : @view.View,
  nav : Nav[P],
  page : (Ctx, P) -> Unit,
  bg? : () -> Int64 = fn() { 0L },
  edge? : Double = 20.0,
  ready? : (P) -> Bool,
  most? : Double = 0.0,
) -> @view.View {
  v.box(fn(s) {
    s.grow(Is(1.0)) |> ignore
    nav.floor = 0
    // (what is due of it on the tree's timeline: its slide's end, or the end of its wait)
    let due : Ref[() -> Unit] = Ref(fn() {  })
    // a slide set out (at its start, said once): over at its end, the page that went let go
    let sets_out = fn() {
      (due.val)()
      let t0 = nav.t0
      due.val = s.at_moment(nav.t0 + nav.dur, fn() {
        if nav.t0 == t0 && (nav.mode == 1 || nav.mode == 2 || nav.mode == 4) {
          nav.settle()
        }
      })
    }
    // the page waited for goes now (it has what it shows, or its wait is over): its slide from now
    let goes = fn() {
      if nav.t0 == nav_held {
        nav.waited = true
        nav.t0 = s.now()
        sets_out()
        nav.shown_told()
      }
    }
    nav.hosted = Some({
      now: fn() { s.now() },
      room: fn() { s.laid_size() },
      went: fn() {
        (due.val)()
        due.val = fn() {  }
        match ready {
          Some(r) if nav.mode == 1 && nav.p0 == 1.0 => {
            nav.wait_from = nav.t0
            nav.held_most = most
            if !r(nav.pages[nav.pages.length() - 1].page) {
              nav.t0 = nav_held
              due.val = s.at_moment(nav.wait_from + most, goes)
              return
            }
            nav.waited = true
          }
          _ => ()
        }
        if nav.mode == 1 || nav.mode == 2 || nav.mode == 4 {
          sets_out()
        }
      },
    })
    // (waiting: it goes as what it shows comes, at that answer's moment)
    match ready {
      Some(r) =>
        s.reacts(
          fn() {
            nav.shown.get() |> ignore
            nav.said.get() |> ignore
            nav.t0 == nav_held && r(nav.pages[nav.pages.length() - 1].page)
          },
          fn(now) { if now { goes() } },
        )
      None => ()
    }
    let k = nav_views_made.val
    nav_views_made.val = k + 1
    nav_views.push((k, fn(c) {
      if nav.mode == 3 {
        c.page_in_hand = true
      }
      let r = nav.rest_at(c.clock, c.frame_no)
      if r > c.nav_rest {
        c.nav_rest = r
      }
    }))
    s.owns(fn() {
      match nav_views.search_by(fn(e) { e.0 == k }) {
        Some(i) => nav_views.remove(i) |> ignore
        None => ()
      }
      (due.val)()
      nav.hosted = None
    })
    |> ignore
    s.each(
      fn() {
        nav.said.get() |> ignore
        nav.shown.get() |> ignore
        let all = nav.pages.map(fn(e) { e.serial })
        match nav.leaving {
          Some(e) => all.push(e.serial)
          None => ()
        }
        all
      },
      fn(k) { k },
      fn(pv, serial) {
        let k = @signals.untracked(fn() { serial.get() })
        let entry = nav.entry(k)
        pv
          .over(Is(true))
          .shift(By(fn() { nav.shift_of(k, fn() { pv.drawn_at() }) }))
          // (going back off the stack, or covered as a page comes in over it: drawn only, from that moment)
          .presses(By(fn() { nav.takes(k) }))
          |> ignore
        // (let go as it leaves the stack: what it made forgotten, the app told; let go with the stack's node, kept)
        pv.owns(fn() {
          let here = nav.pages.iter().any(fn(e) { e.serial == k }) ||
            (nav.leaving is Some(e) && e.serial == k)
          if !here {
            match nav.gone.search_by(fn(e) { e.serial == k }) {
              Some(i) => nav.gone.remove(i) |> ignore
              None => ()
            }
            g().forget(k)
            match entry {
              Some(e) => (nav.on_leave)(e.page)
              None => ()
            }
          }
        })
        |> ignore
        pv.show(fn() { nav.shows(k) }, fn(b) {
          b.grow(Is(1.0)) |> ignore
          old(b, fn(c) { nav.page_built(c, k, page, bg(), edge) }).grow(Is(1.0)) |> ignore
        })
      },
    )
  })
}

///|
/// Page `serial` of the stack built (its old view): over its whole room, on the stack's back (its gesture, from within
/// `edge` of its left side) where it is the top and a page is under it or moving, the page's own back taken before it;
/// one leaving, or under a page coming in, its back none (its presses none: its node's, Nav::takes, as the tree says
/// where an input finds what: old_hits_place).
fn[P] Nav::page_built(
  self : Nav[P],
  c : Ctx,
  serial : Int,
  page : (Ctx, P) -> Unit,
  bg : Int64,
  edge : Double,
) -> Unit {
  self.said.get() |> ignore
  self.shown.get() |> ignore
  let e = match self.entry(serial) {
    Some(e) => e
    None => return
  }
  let n = self.pages.length()
  let leaving = self.leaving is Some(l) && l.serial == serial
  let top = !leaving && self.pages[n - 1].serial == serial
  let takes = top && (n > self.floor + 1 || self.mode >= 3 || (self.floor == 0 && self.mode != 0))
  let before = c.back_next
  let before_node = c.back_node_next
  let before_edge = c.back_edge_next
  let i = c.box(w=Fill(1.0), h=Fill(1.0), bg~, fn() {
    let stack_back = fn() {
      c.back_next = Some(fn(kind, x, w, t, progress) { self.gesture(kind, x, w, t, progress~) })
      c.back_node_next = c.cur
      c.back_edge_next = edge
    }
    // (the page's own back first, then the stack's: a page going back off it takes none of its own)
    if takes && self.leaving is None {
      stack_back()
    }
    let saved = c.owner
    let saved_stint = c.stint
    c.owner = e.serial
    c.stint = e.stint
    self.built_by(e, fn() { c.scope(e.serial, fn() { page(c, e.page) }) })
    c.owner = saved
    c.stint = saved_stint
    if takes && self.leaving is Some(_) {
      stack_back()
    }
  })
  // (not the top: back as it was before it)
  if !top {
    c.back_next = before
    c.back_node_next = before_node
    c.back_edge_next = before_edge
  }
}
