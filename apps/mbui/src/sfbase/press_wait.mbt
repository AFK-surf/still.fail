// A press that waits for the core to open something: a row's menu, its swipe's question and its 归档 key waiting for
// its chat's whole row (`chatRow`, whole_row.mbt), the chat page's "…" (sfpages' open_chat_menu), a new chat's model
// panel waiting for its `pick` (sfpages' model_triple), an account's page waiting for what it shows
// (account_open.mbt), the add page's choice of station waiting for that station's flow (sfpages new_profile.mbt).
// The rule held here, once for all of them: such a press waits
// only while what it was pressed in stays as it was (the page on top's stay, Nav::top_stay: the page not left, the
// workspace not switched; and nothing else put up by the presenters since, last_presented), and lets go of what it
// asked when it stops waiting without opening anything. Once answered while it is so, it does what it waited for, in
// the frame the answer comes, or at once where it is answered already.

///|
/// A press waiting for the core (press_wait): whether it still waits, and what ends it.
pub struct PressWait {
  priv mut waiting : Bool
  priv mut stop : (() -> Unit)?
  priv ready : () -> Bool
  priv go : () -> Unit
  priv let_go : () -> Unit
  priv stay : (Int, Int)
  priv shown : Int
}

///|
/// Whether what a press was pressed in is as it was then (`stay`, `shown`): read where it is read.
fn press_still(stay : (Int, Int), shown : Int) -> Bool {
  app.nav.top_stay() == stay && @sf.last_presented() == shown
}

///|
/// A press that does `go` once `ready` (read where it is read: what it waits for of the core, through what holds it)
/// says it can: at once where it does already, else the moment it comes to, while what the press was pressed in stays
/// as it was; once that is no longer so (the page left, the workspace switched, something else put up), it waits no
/// more, does nothing and lets go of what it asked (`let_go`). Made in a press's handler (a system bar's choice is told
/// once the frame's builds are over: sfdesk rail_native.mbt) or before any frame (a fixture's ask), never as a view
/// builds, since `go` may run at once (a build asks through Ctx::after_build, as model_triple.mbt's does); what waits
/// is owned by nothing and read outside what reads now.
pub fn press_wait(ready : () -> Bool, go : () -> Unit, let_go? : () -> Unit = fn() {  }) -> PressWait {
  let w : PressWait = {
    waiting: true,
    stop: None,
    ready,
    go,
    let_go,
    stay: @signals.untracked(fn() { app.nav.top_stay() }),
    shown: @sf.last_presented(),
  }
  if @signals.untracked(ready) {
    w.waiting = false
    go()
    return w
  }
  let owner = @signals.set_owner(None)
  let stop = @signals.untracked(fn() {
    @signals.effect(fn() {
      guard w.waiting else { return }
      // (what it was pressed in first: once that is gone, what it waits for is not read again)
      if !press_still(w.stay, w.shown) {
        @signals.untracked(fn() { w.give_up() })
      } else if ready() {
        @signals.untracked(fn() {
          w.end()
          go()
        })
      }
    })
  })
  @signals.set_owner(owner) |> ignore
  if w.waiting {
    w.stop = Some(stop)
  } else {
    stop()
  }
  w
}

///|
/// Whether it still waits.
pub fn PressWait::waiting(self : PressWait) -> Bool {
  self.waiting
}

///|
/// It waits no more, doing nothing and letting go of nothing: what it waited for is another's now (the same asked
/// again, what it opened holding it), or it was done.
pub fn PressWait::end(self : PressWait) -> Unit {
  self.waiting = false
  match self.stop {
    Some(stop) => {
      self.stop = None
      // (stopped once the change under way is told: it may be what stops it)
      @signals.after_flush(stop)
    }
    None => ()
  }
}

///|
/// It waits no more and lets go of what it asked (what it was pressed in is gone, or what holds it is): nothing opens.
pub fn PressWait::give_up(self : PressWait) -> Unit {
  guard self.waiting else { return }
  self.end()
  (self.let_go)()
}

///|
/// Looked at again now (a build that finds what it waits for answered by a source that tells nothing as it changes):
/// gives up where what it was pressed in is gone, else does what it waited for where `ready` says it can. Nothing
/// where it waits no more.
pub fn PressWait::check(self : PressWait) -> Unit {
  guard self.waiting else { return }
  if !@signals.untracked(fn() { press_still(self.stay, self.shown) }) {
    self.give_up()
  } else if @signals.untracked(self.ready) {
    self.end()
    (self.go)()
  }
}
