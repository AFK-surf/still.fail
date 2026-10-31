// What the page's pane shows while a page put on top waits for what it shows, said at its causes by the node holding
// the pane (the tape's on Medium: tape_view.mbt; the frame off the tape's, Large: pane_view.mbt), never found by the
// frames: the stay the pane shows (Nav::top_stay's: an entry of the stack and its time on top), the one before kept by
// the stack meanwhile (Nav::flat_keep), and what is due as the wait is over.

///|
priv struct PageWait {
  /// the stay the pane shows ((-1, -1): none yet, as its node is made)
  shown : @signals.Signal[(Int, Int)]
  /// the wait of the one on top over, as it is due (a moment of the tree's timeline): what calls it off
  mut due : () -> Unit
}

///|
fn page_wait() -> PageWait {
  { shown: @signals.signal((-1, -1), same=fn(a, b) { a == b }), due: fn() {  } }
}

///|
/// Its wait called off, nothing shown yet (a run begun, its node let go).
fn PageWait::reset(self : PageWait) -> Unit {
  (self.due)()
  self.due = fn() {  }
  self.shown.set((-1, -1))
}

///|
/// Whether the pane shows the page on top (read as either changes): once the core gave what it shows, or its wait is
/// over.
fn PageWait::shows_top(self : PageWait) -> Bool {
  self.shown.get() == app.nav.top_stay()
}

///|
/// The page on top shown (stay `stay`, still the one on top), at the moment of what said so: what was kept in its place
/// let go, its wait called off. Once.
fn PageWait::shows(self : PageWait, stay : (Int, Int)) -> Unit {
  if app.nav.top_stay() != stay || self.shown.get() == stay {
    return
  }
  (self.due)()
  self.due = fn() {  }
  self.shown.set(stay)
  app.nav.flat_keep(None)
}

///|
/// Node `v`'s, the pane's: what it shows as the page on top changes, each at its cause's moment, whatever frames are
/// drawn. A page come on top (a stay of its own: Nav::top_stay; the one on top as the node is made too) shows at once
/// where the core has given what it shows (`ready`); else the one shown before stays (kept by the stack:
/// Nav::flat_keep; none before, the one on top drawn as it comes) till the core gives it (a reaction, at that answer's
/// moment) or `most()` past the moment it came (a moment of the tree's timeline), whichever comes first, once. Another
/// come on top in the while calls this one's wait off; the node let go, its wait too, the stack drawn as the frames say
/// again.
fn PageWait::follow(self : PageWait, v : @view.View, ready : (Page) -> Bool, most : () -> Double) -> Unit {
  app.nav.flat_owned(true)
  self.reset()
  v.reacts(fn() { app.nav.top_stay() }, fn(stay) {
    (self.due)()
    self.due = fn() {  }
    let before = self.shown.get()
    if before == stay {
      return
    }
    if ready(app.nav.top()) {
      self.shown.set(stay)
      app.nav.flat_keep(None)
      return
    }
    app.nav.flat_keep(if before.0 >= 0 { Some(before) } else { None })
    self.due = v.at_moment(v.cause_at() + most(), fn() { self.shows(stay) })
  })
  // (what the core gives the page on top, at that answer's moment)
  v.reacts(fn() { (app.nav.top_stay(), ready(app.nav.top())) }, fn(told) {
    let (stay, now) = told
    if now {
      self.shows(stay)
    }
  })
  v.owns(fn() {
    (self.due)()
    self.due = fn() {  }
    app.nav.flat_owned(false)
  })
  |> ignore
}

///|
// kept across runs: its wait called off and nothing shown as a run begins (tape_goes_reset)
let tape_page_wait : PageWait = page_wait()

///|
// kept across runs: its wait called off and nothing shown as a run begins (fold_goes_reset)
let pane_page_wait : PageWait = page_wait()
