// A stack of pages drawn flat (Ctx::nav_flat's, a pane's beside a sidebar) held by the window's tree: the stack a node
// of its own, each page in it a node made as it is put on the stack and let go as it leaves it (what the page made for
// it forgotten then: Nav's on_leave), the page itself built in it while it shows. What shows is the page on top, in
// place, nothing sliding — or, where its owner keeps one shown while the one on top waits for what it shows
// (Nav::flat_owned, Nav::flat_keep: page_wait.mbt's, at its causes), that one, kept till it is let go; a page put in
// place moving is put where it was going. A page put in place waits for nothing here: what waits is its owner's (no
// owner, it shows at once). What is pushed over the page in place (Nav::push_over: a pane on a tape, a phone's screen)
// slides in over it as nav_view's pages do, once `over_ready` says it has what it shows (`most` ms at most:
// Nav::held_by), and back takes it off sliding, following the system's gesture, down to the page in place (the stack's
// floor), where `takes_back` says back is the stack's now.
//
// Which pages it holds and which show is where a change left things as a whole (@signals.after_flush): the stack told
// anew and what its owner says of it as that comes (the page before kept as the one in its place waits) seen as one,
// never the half between them, whichever of them is told first — so a page kept is never let go and made again.

///|
/// Where a flat stack stands as a change left it (nav_flat_view): the entries it holds a node for, those that show,
/// whether what shows is pushed over the page in place, and what kind of page made once each is (by `keys`' order).
#derive(Eq)
priv struct FlatSeen {
  keys : Array[Int]
  shown : Array[Int]
  stacked : Bool
  /// what kind of page made once each holds (nav_flat_view's `made`; "" its old view), as what each is then
  kinds : Array[String]
}

///|
/// The page drawn in place now (the one kept shown where its owner keeps one, else the one on top), read as it changes.
fn[P] Nav::flat_drawn(self : Nav[P]) -> NavPage[P] {
  self.said.get() |> ignore
  self.shown.get() |> ignore
  match self.flat_kept_entry() {
    Some(e) => e
    None => self.pages[self.pages.length() - 1]
  }
}

///|
/// Entry `serial` of a flat stack: on it, going back off it, or kept shown in place though it left it (Nav::flat_keep).
fn[P] Nav::flat_entry(self : Nav[P], serial : Int) -> NavPage[P]? {
  match self.entry(serial) {
    Some(e) => Some(e)
    None => self.flat_kept_entry().filter(fn(e) { e.serial == serial })
  }
}

///|
/// What page entry `serial` is (as it is now: what it became in place) and the page under it as it was put on: one on
/// the stack, going back off it, or kept shown in place though it left it (Nav::flat_keep); read as it changes. What
/// the frame puts over a page asks of it (nav_flat_view's `head`).
pub fn[P] Nav::page_of(self : Nav[P], serial : Int) -> (P, P?)? {
  self.said.get() |> ignore
  self.shown.get() |> ignore
  self.flat_entry(serial).map(fn(e) { (e.page, e.under) })
}

///|
/// The entries a flat stack holds a node for: those on it, the one going back off it, and the one kept shown in place
/// though it left it (Nav::flat_keep), read as they change.
fn[P] Nav::flat_entries(self : Nav[P]) -> Array[Int] {
  self.said.get() |> ignore
  self.shown.get() |> ignore
  let all = self.pages.map(fn(e) { e.serial })
  match self.leaving {
    Some(e) => all.push(e.serial)
    None => ()
  }
  match self.flat_kept_entry() {
    Some(e) if !all.contains(e.serial) => all.push(e.serial)
    _ => ()
  }
  all
}

///|
/// Stack `nav` drawn flat as a node of `v`'s, filling the room it is given (above): each page built by `page` (its old
/// view, built again as `page_key` of it changes besides what it reads), on a ground of `bg`; a page put in place shown
/// as its owner says (Nav::flat_owned, Nav::flat_keep), else at once; what is pushed over the page in place sliding in
/// once `over_ready` says it has what it shows (`most` ms at most), taken off by back (within `edge` of its left side)
/// while `takes_back` says back is the stack's; where `stacks` says not (a pane beside a sidebar off a tape), shown in
/// place as any other. Over each page's own view what `head` makes of its entry (by its number, and whether the page
/// is made once there: `made`), nodes of the tree's
/// laid over it (a panel's bar: the page leaving its room), the stack's back over the whole of both (Nav::backs_over);
/// what was kept for it let go by `gone` as its entry is (not as it stops showing: shown again, as it was). `made`: a
/// page made once as nodes of the tree's in the place of its old view, as nav_view's (Nav::made: what `head` makes in
/// its flow over it, the page in the room left under it). `shown`: told the entries that show (by their numbers) as
/// the stack stands whole after a change (never the half between a change and its owner's keeping), and as it is made.
pub fn[P] nav_flat_view(
  v : @view.View,
  nav : Nav[P],
  page : (Ctx, P) -> Unit,
  over_ready : (P) -> Bool,
  most : Double,
  bg? : () -> Int64 = fn() { 0L },
  edge? : Double = 20.0,
  takes_back? : () -> Bool = fn() { true },
  stacks? : () -> Bool = fn() { true },
  page_key? : (P) -> String = fn(_) { "" },
  page_for? : (@view.View, Int) -> (@view.View) -> (Ctx, P) -> Unit,
  head? : (@view.View, Int, Bool) -> Unit,
  gone? : (Int) -> Unit = fn(_) {  },
  made? : (P) -> (String, (@view.View, () -> P, P?, () -> Int, Int) -> Unit)? = fn(_) { None },
  shown? : (Array[Int]) -> Unit = fn(_) {  },
) -> @view.View {
  // (what shows pushed over the page in place, where what is pushed over is so here)
  let stacked = fn() { stacks() && nav.stacked() }
  v.box(fn(s) {
    s.grow(Is(1.0)).clips(Is(true)) |> ignore
    // (what a frame says of a stack, as nav_view's: when it rests, a page held by a finger)
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
    // (the entries a node of it holds now: what left the stack with none, let go of as it stands, Nav::flat_gone)
    let held : Map[Int, Bool] = Map([])
    // (what is pushed over the page in place slides as a phone's, its wait and its slide at their causes)
    nav.held_by(s, fn() { s.laid_size() }, Some(fn(p) { !nav.top_over() || over_ready(p) }), most)
    // (where it stands as a change left it, as a whole: told once each change is told whole, while it is held)
    // (what kind of page made once each of `keys` is, as what it is and what `made` reads to say so are now)
    let kinds_of = fn(keys : Array[Int]) {
      keys.map(fn(k) {
        match nav.flat_entry(k) {
          Some(e) =>
            match made(e.page) {
              Some((kind, _)) => kind
              None => ""
            }
          None => ""
        }
      })
    }
    let seen_now = fn() -> FlatSeen {
      @signals.untracked(fn() {
        let st = stacked()
        let shown = if st {
          let (top, beside) = nav.top_beside()
          match beside {
            Some(b) => [top.serial, b.serial]
            None => [top.serial]
          }
        } else {
          [nav.flat_drawn().serial]
        }
        let keys = nav.flat_entries()
        { keys, shown, stacked: st, kinds: kinds_of(keys) }
      })
    }
    let seen = @signals.signal(seen_now(), same=fn(a, b) { a == b })
    // (which entries show, told the frame as the stack stands whole: what is kept for one shown is that one's)
    s.reacts(fn() { seen.get().shown }, shown)
    // (what left the stack held by no node of it, not kept shown: let go of now, as the stack stands whole, once —
    // left while no node held it: the stack not shown, or before it was)
    let gone_free = fn() {
      let free = nav.gone.filter(fn(e) {
        !held.contains(e.serial) && !(nav.flat_kept_entry() is Some(kept) && kept.serial == e.serial)
      })
      for e in free {
        match nav.gone.search_by(fn(g) { g.serial == e.serial }) {
          Some(i) => nav.gone.remove(i) |> ignore
          None => ()
        }
        g().forget(e.serial)
        gone(e.serial)
        nav.entry_left(e)
      }
    }
    // (as it is first held: once that change is told whole, its owner's keeping told with it)
    @signals.after_flush(fn() { if s.alive() { @signals.untracked(gone_free) } })
    s.reacts(
      // (what makes it stand anew: the stack told, what may push over it, and what decides which way each is drawn, as
      // `made` reads it: a page's width there, the stack itself told nothing)
      fn() { (nav.said.get(), nav.shown.get(), stacks(), kinds_of(nav.flat_entries())) },
      fn(_) {
        @signals.after_flush(fn() {
          if s.alive() {
            seen.set(seen_now())
            @signals.untracked(gone_free)
          }
        })
      },
    )
    // (a page put in place, or gone back to one in place, moving: put where it was going, at once, as Ctx::nav_flat)
    s.reacts(
      fn() {
        nav.said.get() |> ignore
        nav.shown.get() |> ignore
        !stacked() && (nav.mode != 0 || nav.leaving is Some(_))
      },
      fn(moving) { if moving { nav.settle() } },
    )
    s.each(at_once=true, fn() { seen.get().keys }, fn(k) { k }, fn(pv, serial) {
      let k = serial.untracked()
      held[k] = true
      let entry = match nav.entry(k) {
        Some(e) => Some(e)
        None => @signals.untracked(fn() { nav.flat_kept_entry() })
      }
      let shows = fn() { seen.get().shown.contains(k) }
      pv
        .over(Is(true))
        .shift(By(fn() { if seen.get().stacked { nav.shift_of(k, fn() { pv.drawn_at() }) } else { (0.0, 0.0) } }))
        .presses(By(fn() { if seen.get().stacked { nav.takes(k) } else { shows() } }))
        |> ignore
      // (let go as it leaves the stack, not kept shown: what it made forgotten, the app told)
      pv.owns(fn() {
        held.remove(k)
        let here = nav.pages.iter().any(fn(e) { e.serial == k }) ||
          (nav.leaving is Some(e) && e.serial == k) ||
          (nav.flat_kept_entry() is Some(e) && e.serial == k)
        if !here {
          match nav.gone.search_by(fn(e) { e.serial == k }) {
            Some(i) => nav.gone.remove(i) |> ignore
            None => ()
          }
          g().forget(k)
          gone(k)
          match entry {
            Some(e) => nav.entry_left(e)
            None => ()
          }
        }
      })
      |> ignore
      let draw_for = match page_for { Some(make) => make(pv, k); None => fn(_) { page } }
      // (its old view while it shows; or, where `made` says so of what it is as the stack stood whole (FlatSeen's
      // `kinds`, never the half between a change and its owner's keeping), its nodes made once, as it first shows, and
      // kept while it is held, laid out nowhere while it does not show: as nav_view's)
      pv.pick(
        at_once=true,
        fn() {
          let st = seen.get()
          match st.keys.search(k) {
            Some(i) => st.kinds[i]
            None => ""
          }
        },
        fn(pb, kind) {
          // (as tall as the stack's room, never as what it holds: what is in it scrolls in that, or is cut to it)
          pb.grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
          match @signals.untracked(fn() { nav.flat_entry(k).map(fn(e) { (e, made(e.page)) }) }) {
            Some((e, Some((_, f)))) if kind != "" => {
              let shown = Ref(false)
              pb.show(
                at_once=true,
                fn() {
                  if shows() {
                    shown.val = true
                  }
                  shown.val
                },
                fn(m) {
                  m.basis(Is(Some(0.0))).min_height(Is(Some(0.0))).laid_nowhere(By(fn() { !shows() })) |> ignore
                  // (back the stack's while it is pushed over the page in place and on the stack, down to that page)
                  let floor = fn() { if takes_back() && stacks() { nav.over_floor() } else { nav.pages.length() } }
                  let when = fn() { seen.get().stacked && nav.entry(k) is Some(_) }
                  match head {
                    Some(h) => nav.made(m, k, e, f, bg, edge, floor~, when~, head=fn(o) { h(o, k, true) })
                    None => nav.made(m, k, e, f, bg, edge, floor~, when~)
                  }
                },
              )
            }
            _ =>
              pb.show(at_once=true, shows, fn(b) {
                b.grow(Is(1.0)) |> ignore
                let draw_page = draw_for(b)
                let key = fn() {
                  match entry {
                    Some(e) => {
                      let said = Ref("")
                      nav.built_by(e, fn() { said.val = page_key(e.page) })
                      said.val
                    }
                    None => ""
                  }
                }
                let island = fn() {
                  old(
                    b,
                    fn(c) {
                      // (back the stack's down to the page in place, where it is the stack's now)
                      nav.floor = if takes_back() && stacks() { nav.over_floor() } else { nav.pages.length() }
                      if seen.get().stacked && nav.entry(k) is Some(_) {
                        // (under what the frame puts over it, the stack's back that node's: below)
                        nav.page_built(c, k, draw_page, if head is Some(_) { 0L } else { bg() }, edge, stack=head is None)
                      } else {
                        // (in place: built as Ctx::nav_flat builds it, all of its room, cut to it, no back of the stack's; on the
                        // stack, or kept shown though it left it)
                        nav.said.get() |> ignore
                        let e = match nav.entry(k) {
                          Some(e) => Some(e)
                          None => nav.flat_kept_entry().filter(fn(e) { e.serial == k })
                        }
                        match e {
                          Some(e) =>
                            c.box(style=if head is Some(_) { flat_in_place } else { flat_in_place.then(style(bg=Data(bg()))) }, fn() {
                              let (owner, stint) = (c.owner, c.stint)
                              c.owner = e.serial
                              c.stint = e.stint
                              nav.built_by(e, fn() { c.scope(e.serial, fn() { draw_page(c, e.page) }) })
                              c.owner = owner
                              c.stint = stint
                            })
                            |> ignore
                          _ => ()
                        }
                      }
                    },
                    key~,
                  )
                  .grow(Is(1.0))
                  |> ignore
                }
                match head {
                  // (what the frame puts over the page's own, its nodes the tree's, laid over it (a panel's bar: its room the
                  // page's own to leave as it is built, so nothing of it moves as the bar is told what it shows); the page's
                  // ground under both, as the page's own was under what it held; the stack's back over the whole of both, as a
                  // page made once has it, where it is the stack's: Nav::backs_over)
                  Some(h) => {
                    b.ground(By(bg)) |> ignore
                    let floor = fn() { if takes_back() && stacks() { nav.over_floor() } else { nav.pages.length() } }
                    nav.backs_over(b, k, edge, floor~, when=fn() { seen.get().stacked && nav.entry(k) is Some(_) }, fn() {
                      island()
                      b.box(fn(o) {
                        o.over(Is(true)) |> ignore
                        h(o, k, false)
                      })
                      |> ignore
                    })
                  }
                  None => island()
                }
              })
          }
        },
      )
    })
  })
}

///|
/// A page put in place in a flat stack (nav_flat_view): the whole of its room, cut to it, as Ctx::nav_flat builds one.
// kept across runs: a value (no field of it changes)
let flat_in_place : Style = css("w=Full h=Full clip")
