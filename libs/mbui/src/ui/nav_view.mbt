// A stack of pages (Nav) held by the window's tree (src/view, the way there's 4): the stack a node of
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
  /// whether what the old frame's focus names (an old widget's, a node's: Ctx::focus) is in the stack (Nav::focus_follows)
  holds : (Int) -> Bool
  /// whether what it names may take the focus still (a node of the tree's not let go of; an old widget's, built as its
  /// page is again)
  still : (Int) -> Bool
}

///|
/// What shows of the stack changed (which pages, how they move): what reads it told.
fn[P] Nav::shown_told(self : Nav[P]) -> Unit {
  self.shown.set(self.shown.untracked() + 1)
}

///|
/// Where the top page is at `now`, in its widths off to its side, as its slide has it (from where it set out, by when
/// and how), or where it is held (by a finger, waiting, at rest).
fn[P] Nav::p_at(self : Nav[P], now : Double) -> Double {
  if (self.mode == 1 || self.mode == 2 || self.mode == 4) && self.t0 >= 0.0 {
    self.slid_at(now)
  } else {
    self.p
  }
}

///|
/// The page `serial` (on the stack, leaving it, or on its shelf: Nav::replace_kept).
fn[P] Nav::entry(self : Nav[P], serial : Int) -> NavPage[P]? {
  match self.leaving {
    Some(e) if e.serial == serial => return Some(e)
    _ => ()
  }
  match self.pages.iter().find_first(fn(e) { e.serial == serial }) {
    Some(e) => Some(e)
    None => self.shelf.iter().find_first(fn(e) { e.serial == serial })
  }
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
pub fn[P] Nav::shows(self : Nav[P], serial : Int) -> Bool {
  self.said.get() |> ignore
  self.shown.get() |> ignore
  let (top, beside) = self.top_beside()
  top.serial == serial || (beside is Some(b) && b.serial == serial)
}

///|
/// Whether the stack's root page shows: the top, or the one beside it as one moves over it or off it (read: told as it
/// changes, at its slide's end on the tree's timeline).
pub fn[P] Nav::root_shows(self : Nav[P]) -> Bool {
  self.said.get() |> ignore
  self.shown.get() |> ignore
  let root = self.pages[0].serial
  let (top, beside) = self.top_beside()
  top.serial == root || (beside is Some(b) && b.serial == root)
}

///|
/// Whether page `serial` takes presses: not as it goes back off the stack, nor under a page coming in over it, nor on
/// the shelf (read: told as that changes).
fn[P] Nav::takes(self : Nav[P], serial : Int) -> Bool {
  self.said.get() |> ignore
  self.shown.get() |> ignore
  let n = self.pages.length()
  let leaving = self.leaving is Some(l) && l.serial == serial
  let top = !leaving && self.pages[n - 1].serial == serial
  let shelved = self.shelf.iter().any(fn(e) { e.serial == serial })
  !(leaving || shelved || (self.mode == 1 && !top))
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
  let way = if (self.from_left)(top.page, top.under) { -1.0 } else { 1.0 }
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
/// The stacks the window's tree holds, each told as every frame ends (nav_views_framed): by a number of
/// its own.
// kept across runs: put back as a run begins (view_forget)
let nav_views : Array[(Int, (Ctx) -> Unit)] = []

///|
// kept across runs: a count
let nav_views_made : Ref[Int] = Ref(0)

///|
/// As every frame ends (built whole, painted alone or of its looks alone): each stack the tree holds says what a
/// frame says of a stack (Ctx::nav: when it rests, a page held by a finger), for what reads it of the frame (a test's
/// nav_rest, the corners' checks).
fn nav_views_framed(c : Ctx) -> Unit {
  for e in nav_views {
    (e.1)(c)
  }
}

///|
/// Stack `nav` as a node of `v`'s, filling the room it is given (nav_view.mbt above): each page built by `page` (its
/// old view, built again as `page_key` of it changes besides what it reads), on a ground of `bg`; back taken within
/// `edge` of its left side. A page pushed slides in once `ready` says it has what it shows, `most` ms after it was
/// pushed at the latest (none: at once). `made`: a page made once as nodes of the tree's in the place of its old view
/// (Nav::made): what kind of page it is (one become another of the same kind, in place, the same nodes following what
/// it is now) and what makes its nodes, in the node given, given what it is as that changes, the page under it (its
/// own, whatever is on top when what they bind is read: not Nav::under), its time on top (its entry's, as it is put
/// there again: Ctx::page_stint's) and its entry's number (what the frame keeps of the page by, as long as the entry
/// is: nav_flat_view's `head`, `gone`); none, its old view. `keeps_made`: a root page made as nodes that another takes
/// the place of (Nav::replace_kept) put on the shelf, its nodes put by at rest (View::each's `keeps`) and taken in again
/// as it is put back; the shelf emptied, each on it left for good, as this node is let go.
pub fn[P] nav_view(
  v : @view.View,
  nav : Nav[P],
  page : (Ctx, P) -> Unit,
  bg? : () -> Int64 = fn() { 0L },
  edge? : Double = 20.0,
  ready? : (P) -> Bool,
  most? : Double = 0.0,
  page_key? : (P) -> String = fn(_) { "" },
  page_for? : (@view.View, Int) -> (@view.View) -> (Ctx, P) -> Unit,
  made? : (P) -> (String, (@view.View, () -> P, P?, () -> Int, Int) -> Unit)? = fn(_) { None },
  keeps_made? : Bool = false,
) -> @view.View {
  v.box(fn(s) {
    s.grow(Is(1.0)) |> ignore
    nav.floor = 0
    if keeps_made {
      nav.shelves = Some(fn(p) { made(p) is Some(_) })
      // (its shelf this node's: let go with it, what it put by let go by the each below, each left for good)
      s.owns(fn() {
        nav.shelves = None
        nav.shelf.clear()
      })
      |> ignore
    }
    nav.held_by(s, fn() { s.laid_size() }, ready, most)
    let k = nav_views_made.val
    nav_views_made.val = k + 1
    nav_views.push((k, fn(c) {
      if nav.mode == 3 {
        c.page_in_hand = true
      }
      let r = nav.rested_at(c.frame_no)
      if r > c.nav_rest {
        c.nav_rest = r
      }
    }))
    s.owns(fn() {
      match nav_views.search_by(fn(e) { e.0 == k }) {
        Some(i) => nav_views.remove(i) |> ignore
        None => ()
      }
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
        let k = serial.untracked()
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
              Some(e) => nav.entry_left(e)
              None => ()
            }
          }
        })
        |> ignore
        let draw_for = match page_for { Some(make) => make(pv, k); None => fn(_) { page } }
        // (its old view while it shows, built again as `page_key` of it changes; or, where `made` says so, its nodes made
        // once, as it first shows, and kept as long as it is on the stack, laid out nowhere while it does not show (what they hold, their
        // fields' words, how far they scroll, as they were), its data what it becomes in place followed by them; another
        // kind of page come in its place (Nav::become) the one handed to the other)
        pv.pick(
          at_once=true,
          fn() {
            nav.said.get() |> ignore
            match nav.entry(k).map(fn(e) { made(e.page) }) {
              Some(Some((kind, _))) => kind
              _ => ""
            }
          },
          fn(b, kind) {
            b.grow(Is(1.0)) |> ignore
            match @signals.untracked(fn() { nav.entry(k).map(fn(e) { (e, made(e.page)) }) }) {
              Some((e, Some((_, f)))) if kind != "" => {
                // (made the first time it shows, as its old view would first be built: a page put on under another before
                // a frame shows it makes nothing; kept from then)
                let shown = Ref(false)
                b.show(
                  at_once=true,
                  fn() {
                    if nav.shows(k) {
                      shown.val = true
                    }
                    shown.val
                  },
                  fn(m) {
                    // (laid out nowhere while it does not show, but on the shelf: there it is held by no node, put
                    // by as it was laid out, and taken back so, laid out again nowhere and then whole for nothing)
                    m
                    .grow(Is(1.0))
                    .laid_nowhere(By(fn() { !nav.shows(k) && !nav.shelf.iter().any(fn(e) { e.serial == k }) }))
                    |> ignore
                    nav.made(m, k, e, f, bg, edge)
                  },
                )
              }
              _ =>
                b.show(at_once=true, fn() { nav.shows(k) }, fn(o) {
                  o.grow(Is(1.0)) |> ignore
                  let draw_page = draw_for(o)
                  let key = fn() {
                    match nav.entry(k) {
                      // (as the page is built: what it asks of where it stands, Nav::under, its own)
                      Some(e) => {
                        let said = Ref("")
                        nav.built_by(e, fn() { said.val = page_key(e.page) })
                        said.val
                      }
                      None => ""
                    }
                  }
                  old(o, fn(c) { nav.page_built(c, k, draw_page, bg(), edge) }, key~).grow(Is(1.0)) |> ignore
                })
            }
          },
        )
      },
      // (those on the shelf kept, put by at rest: Nav::replace_kept)
      keeps?=if keeps_made {
        Some(fn() {
          nav.said.get() |> ignore
          nav.shelf.map(fn(e) { e.serial })
        })
      } else {
        None
      },
    )
  })
}

///|
/// Stack `self` held by node `s` of the window's tree, its slides on the tree's timeline (nav_view's, and a stack an
/// old view draws whose pages pushed over it the node over that view sets out: Nav::held_over): each told at its
/// cause's moment (Nav::go: the tree's now), as long as its way across `room` is (as laid out as of then), its end a
/// moment there (the page that went let go); a page pushed waiting for what it shows (`ready`) set out as it has it
/// (a reaction, at that answer's moment) or `most` ms after it was pushed (a moment), whichever comes first, whatever
/// frames are drawn. What is due of a slide or a wait is called off as the stack is told anew (pushed, popped, back
/// let go or called off: Nav::go) and as the node is let go (the stack no longer this node's then: another's, or the
/// frames' again).
fn[P] Nav::held_by(
  self : Nav[P],
  s : @view.View,
  room : () -> (Double, Double),
  ready : ((P) -> Bool)?,
  most : Double,
) -> Unit {
  let nav : Nav[P] = self
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
      nav.t0 = s.logic_at()
      sets_out()
      g().moving(nav.mover, nav as &Moving, what="a stack's slide")
      nav.shown_told()
    }
  }
  let hosted : NavHosted = {
    now: fn() { s.logic_at() },
    room,
    holds: fn(id) {
      match (view_app.val, focus_node_of(id)) {
        (Some(t), Some(n)) => t.holds(s.id(), n)
        _ => false
      }
    },
    still: fn(id) {
      match tree_said_ids.get(id) {
        Some(n) =>
          match view_app.val {
            Some(t) => t.holds(n, n)
            None => false
          }
        None => true
      }
    },
    went: fn() {
      (due.val)()
      due.val = fn() {  }
      // (no frame has given the window yet: how far it goes and so how long, not known; set out once it is)
      if @signals.untracked(fn() { s.window() }).0 <= 0.0 {
        nav.t0 = -1.0
        return
      }
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
  }
  nav.hosted = Some(hosted)
  // a page told to come or go before the tree held the stack (pushed as the app began, before any frame; or as the old
  // view held it, the window laid out otherwise): its slide set out now, at this moment, where it had not; one under
  // way goes on to its end, said on the timeline
  if nav.mode == 1 || nav.mode == 2 || nav.mode == 4 {
    if nav.t0 == -1.0 {
      nav.go(nav.mode, nav.p1, v=nav.v0)
    } else if nav.t0 >= 0.0 {
      sets_out()
    } else if nav.t0 == nav_held {
      due.val = s.at_moment(nav.wait_from + nav.held_most, goes)
    }
  }
  // (one told before the window was known sets out as the first frame gives it, at that moment)
  s.reacts(fn() { s.window().0 > 0.0 }, fn(laid) {
    if laid && nav.t0 == -1.0 && (nav.mode == 1 || nav.mode == 2 || nav.mode == 4) {
      nav.go(nav.mode, nav.p1, v=nav.v0)
    }
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
  s.owns(fn() {
    (due.val)()
    due.val = fn() {  }
    // (held by another node since, made before this one was let go: that one's still)
    match nav.hosted {
      Some(h) if physical_equal(h, hosted) => nav.hosted = None
      _ => ()
    }
  })
  |> ignore
}

///|
/// Stack `self`, drawn by an old view in node `s` (Ctx::nav_flat's `stacks`: a pane's stack, the pages pushed over the
/// one in place sliding in as on a phone), held by it (Nav::held_by): its slides told at their causes' moments, as
/// long as its way across the room the view drew it in last (Ctx::nav's, as laid out then); a page pushed over (Nav::
/// push_over) sliding in once `ready` says it has what it shows, `most` ms after it was pushed at the latest, a page put
/// in place not waited for here (what shows in place, the view's owner's: Nav::flat_keep).
pub fn[P] Nav::held_over(self : Nav[P], s : @view.View, ready : (P) -> Bool, most : Double) -> Unit {
  self.held_by(s, fn() { (self.room_w, self.room_h) }, Some(fn(p) { !self.top_over() || ready(p) }), most)
}

///|
/// Page `serial` of the stack built (its old view): over its whole room, on the stack's back (its gesture, from within
/// `edge` of its left side) where it is the top and a page is under it or moving, the page's own back taken before it;
/// one leaving, or under a page coming in, its back none (its presses none: its node's, Nav::takes, as the tree says
/// where an input finds what: old_hits_place). Not `stack`: the stack's back none of the old view's (a node of the
/// tree's over the whole page has it: Nav::backs_over), the page's own as above.
fn[P] Nav::page_built(
  self : Nav[P],
  c : Ctx,
  serial : Int,
  page : (Ctx, P) -> Unit,
  bg : Int64,
  edge : Double,
  stack? : Bool = true,
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
  let takes = stack && top && (n > self.floor + 1 || self.mode >= 3 || (self.floor == 0 && self.mode != 0))
  let before = c.back_next
  let before_node = c.back_node_next
  let before_edge = c.back_edge_next
  let before_island = c.back_island_next
  let before_chain = c.back_chain_next
  let _ = c.box(style=nav_page_whole.then(style(bg=Data(bg))), fn() {
    let stack_back = fn() {
      c.back_next = Some(fn(kind, x, w, t, progress) { self.gesture(kind, x, w, t, progress~) })
      c.back_node_next = c.cur
      c.back_edge_next = edge
      c.back_island_next = c.island_said()
      c.back_says()
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
    c.back_island_next = before_island
    c.back_chain_next = before_chain
  }
}

///|
/// The old view of page `serial` in node `v` of a page made once (nav_view's and nav_flat_view's `made`), while what it
/// holds is not nodes yet: built as the stack builds a page's old view (Nav::page_built's: what it keeps its own and
/// forgotten with it, its time on top, the page it was put on from, its widgets' ids its own), as what the page is now
/// (what it became in place) and as `key` changes (asked as it is built: Nav::under its own); none of the stack's back
/// (the made page's node has it: Nav::backs_over). One left the stack but kept shown in place (Nav::flat_keep) built
/// as before. `natural`, `gives`, `over`, `reshaped`: as tall as what it holds, giving way where it is short of room,
/// drawing past it, told as what it holds comes to another height (old's: the rest of the page under it nodes).
pub fn[P] Nav::page_island(
  self : Nav[P],
  v : @view.View,
  serial : Int,
  build : (Ctx, P) -> Unit,
  key? : () -> String = fn() { "" },
  natural? : Bool = false,
  gives? : Bool = false,
  over? : Bool = false,
  reshaped? : (Double) -> Unit,
) -> @view.View {
  let nav = self
  old(
    v,
    natural~,
    gives~,
    over~,
    reshaped?,
    fn(c) {
      nav.said.get() |> ignore
      nav.shown.get() |> ignore
      match nav.flat_entry(serial) {
        Some(e) => {
          let (owner, stint) = (c.owner, c.stint)
          c.owner = e.serial
          c.stint = e.stint
          nav.built_by(e, fn() { c.scope(e.serial, fn() { build(c, e.page) }) })
          c.owner = owner
          c.stint = stint
        }
        None => ()
      }
    },
    // (as the page is built: what it asks of where it stands, Nav::under, its own)
    key=fn() {
      match nav.flat_entry(serial) {
        Some(e) => {
          let said = Ref("")
          nav.built_by(e, fn() { said.val = key() })
          said.val
        }
        None => ""
      }
    },
  )
}

///|
/// A page of the stack: the whole of its room, on its ground.
// kept across runs: a value (no field of it changes)
let nav_page_whole : Style = css("w=Full h=Full")

///|
/// Page `serial` of the stack (`e`) made once as nodes of the tree's in node `m` (nav_view's `made`): on a ground of
/// `bg`, its nodes `f` makes in it, once (as it is put on, the stack's `under` as of it: Nav::under), given what the
/// page is as that changes; back the stack's as Nav::backs_over has it (from `floor`, where `when` says), the whole of
/// `m`. With `head`: what the frame puts over it made first in its flow, the page in the room left under it, cut to it.
fn[P] Nav::made(
  self : Nav[P],
  m : @view.View,
  serial : Int,
  e : NavPage[P],
  f : (@view.View, () -> P, P?, () -> Int, Int) -> Unit,
  bg : () -> Int64,
  edge : Double,
  floor? : () -> Int,
  when? : () -> Bool = fn() { true },
  head? : (@view.View) -> Unit,
) -> Unit {
  let nav = self
  m
  .grow(Is(1.0))
  // (cut to its room, its ground and all it holds, as the old view of a page is by the island it is built in)
  .clips(Is(true))
  |> ignore
  // (its ground, under all it holds)
  m.box(fn(g) { g.over(Is(true)).ground(By(bg)) |> ignore }) |> ignore
  // (what it is: as it was put on, then what it becomes in place, Nav::become)
  let page = fn() {
    nav.said.get() |> ignore
    e.page
  }
  // (its time on top, as it is put there again: what is put up anew then, a picture that could not be had asked for
  // again, Ctx::page_stint's)
  let stint = fn() {
    nav.said.get() |> ignore
    e.stint
  }
  nav.backs_over(m, serial, edge, floor?, when~, fn() {
    match head {
      None => nav.built_by(e, fn() { f(m, page, e.under, stint, serial) })
      // (what the frame puts over the page first (a panel's bar), in its flow; the page in what is left under it, cut
      // to it: what it scrolls never under the bar)
      Some(h) => {
        m.box(h) |> ignore
        m.box(fn(rest) {
          rest.grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))).clips(Is(true)) |> ignore
          nav.built_by(e, fn() { f(rest, page, e.under, stint, serial) })
        })
        |> ignore
      }
    }
  })
}

///|
/// Back the stack's over the whole of node `m`, page `serial`'s (what `build` makes in it its own, the page and what is
/// over it), while it takes it as the old view says it (Nav::page_built's `takes`, from the stack's `floor`; and where
/// `when` says so): a node of the tree's following it, before what `build` makes (the page's own back said in it takes
/// it first), after it while the one over it goes back off (it takes none of its own then); the swipe from its left
/// edge (within `edge`, a finger's on a platform with none of the system's, a mouse's where it drags) taken over from
/// whatever of `m` it went down on once it goes across more than up or down, past the old view's slop, as wide as `m`.
fn[P] Nav::backs_over(
  self : Nav[P],
  m : @view.View,
  serial : Int,
  edge : Double,
  build : () -> Unit,
  floor? : () -> Int,
  when? : () -> Bool = fn() { true },
) -> Unit {
  let nav = self
  let floor = match floor {
    Some(f) => f
    None => fn() { nav.floor }
  }
  // (whether back is the stack's, and before or after what the page says takes it: Nav::page_built's `takes`)
  let backs = fn(leaving : Bool) {
    nav.said.get() |> ignore
    nav.shown.get() |> ignore
    let n = nav.pages.length()
    let gone = nav.leaving is Some(l) && l.serial == serial
    let top = !gone && n > 0 && nav.pages[n - 1].serial == serial
    let fl = floor()
    when() &&
    top &&
    (n > fl + 1 || nav.mode >= 3 || (fl == 0 && nav.mode != 0)) &&
    (nav.leaving is Some(_)) == leaving
  }
  // (each step to the stack as one of the old frame's (Ctx::back_gesture's kinds), x from the page's left, as wide as it
  // is laid out)
  let step = fn(s : @view.BackStep) {
    let w = @signals.untracked(fn() { m.laid_size() }).0
    let p = back_progress.val
    match s {
      Began(x, t) => nav.gesture(0, x, w, t, progress=p, floor=floor())
      Moved(x, t) => nav.gesture(1, x, w, t, progress=p, floor=floor())
      LetGo(x, t) => nav.gesture(2, x, w, t, progress=p, floor=floor())
      CalledOff => nav.gesture(3, 0.0, w, m.cause_at(), progress=p, floor=floor())
      Back => nav.gesture(4, 0.0, w, m.cause_at(), progress=p, floor=floor())
    }
  }
  let back_node = fn(b : @view.View) { b.over(Is(true)).follows_back(step) |> ignore }
  // (back not the stack's but another's of the tree's, outside the page (a tape's panel's: what the frame takes it by,
  // View::follows_back): the swipe from the page's edge is its, as the old frame's edge gives a page's swipe to what
  // takes back then (Ctx::back_gesture: Tree::back_taker))
  let elsewhere = fn() -> @view.NodeId? {
    if backs(false) {
      return None
    }
    match m.tree.back_taker() {
      Some(id) if !m.tree.holds(m.id(), id) => Some(id)
      _ => None
    }
  }
  // (where a swipe from its edge went down, as it went down: from there it sets out, as the old frame's from press_x;
  // and, where it is another's, which, and where that is drawn from: x from its left, as it is told by the old frame's)
  let down_x = Ref(0.0)
  let down_wx = Ref(0.0)
  // (where `m` was in the window as it went down, and how big it was drawn: what the stack's steps are told x from,
  // as the old frame's are from where the page was as the gesture began, whatever `m` is moved by as it goes)
  let down_left = Ref(0.0)
  let down_scale = Ref(1.0)
  let from_down = fn(d : @view.Drag) { (d.wx - down_left.val) / down_scale.val }
  let swiped = Ref(false)
  let other : Ref[(@view.NodeId, Double)?] = Ref(None)
  let to_other = fn(id : @view.NodeId, step : @view.BackStep, at : Double) { m.tree.back_step(id, step, at) |> ignore }
  m
  .claims(
    fn(dx, dy) {
      swiped.val = dx > 6.0 && dx.abs() > dy.abs()
      swiped.val
    },
    from=fn(x, _) {
      down_x.val = x
      // (where it went down in the window, as `m` is drawn as it goes down: what it sets out from, whatever moves `m`
      // before it is taken over)
      match m.tree.drawn_of(m.id()) {
        Some(o) => {
          let lw = @signals.untracked(fn() { m.laid_size() }).0
          down_left.val = o.x
          down_scale.val = if lw > 0.0 { o.w / lw } else { 1.0 }
        }
        None => {
          down_left.val = 0.0
          down_scale.val = 1.0
        }
      }
      down_wx.val = down_left.val + x * down_scale.val
      h_platform() != 2 && desk.mouse_drags && x < edge && (backs(false) || elsewhere() is Some(_))
    },
  )
  .on_drag(fn(d) {
    if swiped.val {
      let w = d.w
      match d.kind {
        Down => {
          other.val = match elsewhere() {
            Some(id) => Some((id, m.tree.drawn_of(id).map(fn(o) { o.x }).unwrap_or(0.0)))
            None => None
          }
          match other.val {
            Some((id, left)) => {
              to_other(id, Began(down_wx.val - left, d.at), d.at)
              to_other(id, Moved(d.wx - left, d.at), d.at)
            }
            None => {
              nav.gesture(0, down_x.val, w, d.at, floor=floor())
              nav.gesture(1, from_down(d), w, d.at, floor=floor())
            }
          }
        }
        Moved =>
          match other.val {
            Some((id, left)) => to_other(id, Moved(d.wx - left, d.at), d.at)
            None => nav.gesture(1, from_down(d), w, d.at, floor=floor())
          }
        Up => {
          match other.val {
            Some((id, left)) => to_other(id, LetGo(d.wx - left, d.at), d.at)
            None => nav.gesture(2, from_down(d), w, d.at, floor=floor())
          }
          swiped.val = false
          other.val = None
        }
        Off => {
          match other.val {
            Some((id, _)) => to_other(id, CalledOff, d.at)
            None => nav.gesture(3, from_down(d), w, d.at, floor=floor())
          }
          swiped.val = false
          other.val = None
        }
      }
    }
  })
  |> ignore
  m.show(at_once=true, fn() { backs(false) }, back_node)
  build()
  m.show(at_once=true, fn() { backs(true) }, back_node)
}
