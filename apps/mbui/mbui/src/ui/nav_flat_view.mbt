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
/// Where a flat stack stands as a change left it (nav_flat_view): the entries it holds a node for, those that show, and
/// whether what shows is pushed over the page in place.
priv struct FlatSeen {
  keys : Array[Int]
  shown : Array[Int]
  stacked : Bool
} derive(Eq)

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
/// place as any other.
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
) -> @view.View {
  // (what shows pushed over the page in place, where what is pushed over is so here)
  let stacked = fn() { stacks() && nav.stacked() }
  v.box(fn(s) {
    s.grow(Is(1.0)).clips(Is(true)) |> ignore
    // (what is pushed over the page in place slides as a phone's, its wait and its slide at their causes)
    nav.held_by(s, fn() { s.laid_size() }, Some(fn(p) { !nav.top_over() || over_ready(p) }), most)
    // (where it stands as a change left it, as a whole: told once each change is told whole, while it is held)
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
        { keys: nav.flat_entries(), shown, stacked: st }
      })
    }
    let seen = @signals.signal(seen_now(), same=fn(a, b) { a == b })
    s.reacts(
      fn() { (nav.said.get(), nav.shown.get(), stacks()) },
      fn(_) { @signals.after_flush(fn() { if s.alive() { seen.set(seen_now()) } }) },
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
    s.each(fn() { seen.get().keys }, fn(k) { k }, fn(pv, serial) {
      let k = @signals.untracked(fn() { serial.get() })
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
        let here = nav.pages.iter().any(fn(e) { e.serial == k }) ||
          (nav.leaving is Some(e) && e.serial == k) ||
          (nav.flat_kept_entry() is Some(e) && e.serial == k)
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
      pv.show(shows, fn(b) {
        b.grow(Is(1.0)) |> ignore
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
        old(
          b,
          fn(c) {
            // (back the stack's down to the page in place, where it is the stack's now)
            nav.floor = if takes_back() && stacks() { nav.over_floor() } else { nav.pages.length() }
            if nav.entry(k) is Some(_) {
              nav.page_built(c, k, page, bg(), edge)
            } else {
              // (kept shown in place though it left the stack: built as it was, no back of the stack's)
              nav.said.get() |> ignore
              match nav.flat_kept_entry() {
                Some(e) if e.serial == k =>
                  c.box(style=nav_page_whole.then(style(bg=Data(bg()))), fn() {
                    let (owner, stint) = (c.owner, c.stint)
                    c.owner = e.serial
                    c.stint = e.stint
                    nav.built_by(e, fn() { c.scope(e.serial, fn() { page(c, e.page) }) })
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
      })
    })
  })
}
