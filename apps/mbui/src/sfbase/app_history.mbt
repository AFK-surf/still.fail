// The app's history, as a browser's Navigation API has it (navigation.entries, navigate with history "push" or
// "replace", traverseTo): a list of entries, each the workspace in view and the stack of pages then. What a person does
// to go somewhere (a row chosen, a link, a place, a workspace switched, a page opened) says so before it moves the
// stack (history_push): the entry it leaves kept, what forward had forgotten. Everything else that moves the stack (the
// wide frame landing on a chat, a page stepping on in place, the core's answers) replaces the entry now, as a browser
// lets no page add entries a person did not ask for (Chromium's history manipulation intervention). Back and forward
// traverse the entries, the workspace switched back with the pages where they differ.

///|
/// Where the app was: the workspace in view, the pages on the stack.
priv struct Spot {
  ws : String
  pages : Array[Page]
}

///|
/// The entries before the one now (the last nearest), the entries back came from (the last nearest), and the one now
/// (None until the app was first somewhere: history_note).
let history_back : Array[Spot] = []

///|
let history_forward : Array[Spot] = []

///|
/// Told as the entries before the one now change (pushed, taken back, forgotten): what reads whether there is one
/// (history_back_step) follows it, at that change.
// kept across runs: only a count
let history_said : @signals.Signal[Int] = @signals.signal(0)

///|
fn history_changed() -> Unit {
  history_said.set(@signals.untracked(fn() { history_said.get() }) + 1)
}

///|
let history_now : Ref[Spot?] = Ref(None)

///|
/// Where a person's act left from (history_push), till it has gone somewhere (history_note): one entry for all it moves,
/// however many steps it takes the stack through.
let history_from : Ref[Spot?] = Ref(None)

///|
/// A person's act under way (history_push, till history_settled: its change done): one origin for all of it, whatever
/// it noted on its way (a workspace switched first, then its pages).
let history_acting : Ref[Bool] = Ref(false)

///|
/// Told as a person's act is done (history_settled): what notes where the app is (sfapp's app_state_tree) reads it, so it
/// notes once the change the act is in is committed whole, whether the act moved anything or not.
// kept across runs: only a count
let history_ended : @signals.Signal[Int] = @signals.signal(0)

///|
/// What notes where the app is reads, to note once an act is done (history_ended).
pub fn history_acts_ended() -> Int {
  history_ended.get()
}

///|
/// At most so many entries back, the oldest let go (a browser keeps its own).
let history_most = 100

///|
/// The entries forgotten (the app's reset).
fn history_reset() -> Unit {
  history_back.clear()
  history_forward.clear()
  history_now.val = None
  history_from.val = None
  history_acting.val = false
  history_changed()
}

///|
/// A page as history compares it: a chat by its station and session (a chat landed on by the core's mark has no
/// title; chosen in a list it has the row's).
fn spot_page(p : Page) -> Page {
  match p {
    Chat(r) => Chat({ ..r, title: "", station_name: "" })
    History(r, key, entry) => History({ ..r, title: "", station_name: "" }, key, entry)
    _ => p
  }
}

///|
fn same_spot(a : Spot, b : Spot) -> Bool {
  if a.ws != b.ws || a.pages.length() != b.pages.length() {
    return false
  }
  for k, p in a.pages {
    if spot_page(p) != spot_page(b.pages[k]) {
      return false
    }
  }
  true
}

///|
/// Where the app is now: the stack as it is, the workspace the entry now has (one switched since is a person's act,
/// which pushed first).
fn spot_here() -> Spot {
  let ws = match history_now.val {
    Some(n) => n.ws
    None => ""
  }
  { ws, pages: app.nav.pages() }
}

///|
/// A person's act goes somewhere (navigate with history "push"): said before it moves the stack or the workspace, where
/// it leaves from kept, an entry for back once the act has gone somewhere else (history_note: as a browser's entry is
/// made once its navigation commits, what forward had forgotten then). Once for the act, the first of its steps; an act
/// that leaves the app where it was (a page opened again) adds none.
pub fn history_push() -> Unit {
  if history_acting.val || history_now.val is None {
    return
  }
  history_acting.val = true
  history_from.val = Some(spot_here())
}

///|
/// A person's act `f` as one change (a composite of opening: a workspace switched, the stack put down, a page opened):
/// pushed first (history_push), where the app is noted once, as `f` is done, an entry for where it left from where it
/// went somewhere else.
pub fn history_act(f : () -> Unit) -> Unit {
  let outer = history_acting.val
  history_push()
  @signals.start_batch()
  f()
  @signals.end_batch()
  if !outer {
    history_settled()
  }
}

///|
/// A person's act done (history_act, as its change ends; an old view's build its act was taken in: sfapp's
/// signed_in_frame): where it went noted once that change is committed (history_note), an entry for where it left from
/// where it went somewhere else, none where it went nowhere (a page opened again).
pub fn history_settled() -> Unit {
  if !history_acting.val {
    return
  }
  history_acting.val = false
  // (where it went is noted as the change it is in is committed: history_note, an entry there or none)
  history_ended.set(@signals.untracked(fn() { history_ended.get() }) + 1)
}

///|
/// Back by the stack's own (a page's back, the system's gesture, the shell's back_pop; Nav's went_back), told once page
/// `p` is taken off, the stack `pages` then: the entry before traversed to, the one it left (where it was, `p` on
/// those, whatever the entry now was told meanwhile) kept for forward.
fn went_back(p : Page, _over : Bool, _risen : Bool, pages : Array[Page]) -> Unit {
  guard history_now.val is Some(now) && history_back.length() > 0 else { return }
  history_back.pop() |> ignore
  history_forward.push({ ws: now.ws, pages: [..pages, p] })
  history_changed()
  // (the stack decides where it lands: history_note puts it in the entry now)
}

///|
/// The entry now as the stack or the workspace in view changes, at that change (workspace `ws` in view: sfapp's
/// app_state_tree): where the app is put in it (navigate with history "replace": what moved the stack without a
/// person's act changes the entry, adds none); a person's act gone somewhere else, where it left from an entry before
/// it (history_push). `passing`: the stack is Home alone where it is never shown so (the wide frame lands on a chat
/// over it: frame.mbt land), no entry's.
pub fn history_note(ws : String, passing : Bool) -> Unit {
  if ws == "" || passing {
    return
  }
  let here : Spot = { ws, pages: app.nav.pages() }
  match history_from.val {
    // (once the act is done: the first of its steps no entry of their own)
    Some(from) if !history_acting.val => {
      history_from.val = None
      if !same_spot(from, here) {
        history_back.push(from)
        if history_back.length() > history_most {
          history_back.remove(0) |> ignore
        }
        history_forward.clear()
        history_changed()
      }
    }
    _ => ()
  }
  history_now.val = Some(here)
}

///|
/// Back along the history, where there is an entry before this one: that entry, as it is now, brought again when what
/// it gives is done (history_go; later, as a gesture goes through, the same entry, whatever was pushed meanwhile: those
/// after it, and the one now, forward's, as traverseTo leaves them); the entry forgotten by then, nothing.
pub fn history_back_step(src : Source) -> (() -> Unit)? {
  history_said.get() |> ignore
  guard history_back.last() is Some(spot) else { return None }
  Some(fn() {
    let mut at = history_back.length() - 1
    while at >= 0 && !physical_equal(history_back[at], spot) {
      at = at - 1
    }
    guard at >= 0 else { return }
    match history_now.val {
      Some(now) => history_forward.push(now)
      None => ()
    }
    for k = history_back.length() - 1; k > at; k = k - 1 {
      history_forward.push(history_back[k])
    }
    while history_back.length() > at {
      history_back.pop() |> ignore
    }
    history_changed()
    history_go(src, spot)
  })
}

///|
/// The top page of each entry before the one now, the oldest first, and of the one now (what a test reads of the
/// history).
pub fn history_tops() -> (Array[Page], Page?) {
  (history_back.map(fn(s) { s.pages[s.pages.length() - 1] }), history_now.val.map(fn(s) { s.pages[s.pages.length() - 1] }))
}

///|
/// Forward along the history, where back came from an entry: it brought again (history_go).
pub fn history_forward_step(src : Source) -> (() -> Unit)? {
  guard history_forward.last() is Some(_) else { return None }
  Some(fn() {
    guard history_forward.pop() is Some(spot) else { return }
    match history_now.val {
      Some(now) => history_back.push(now)
      None => ()
    }
    history_changed()
    history_go(src, spot)
  })
}

///|
/// Entry `spot` traversed to (traverseTo): its workspace in view (switched as the rail switches it: the prefs'
/// `workspace`), the stack as it was there. The pages it shares with the stack now stay; of the rest the first takes
/// the place of the first that goes, in place (nothing slides: a chat in place of a chat, as the web's history shows
/// one), the others pushed; the stack only shorter, its pages popped as back pops them.
fn history_go(src : Source, spot : Spot) -> Unit {
  // (one change, all its steps: what notes where the app is told once, of where it lands)
  @signals.start_batch()
  let ws = match history_now.val {
    Some(n) => n.ws
    None => ""
  }
  if spot.ws != ws {
    app.picked.set(spot.ws)
    (src.call)("prefs.set", { "workspace": Json::string(spot.ws) }, fn(_) {  })
  }
  history_now.val = Some(spot)
  app.menu = false
  let pages = app.nav.pages()
  let mut k = 0
  while k < pages.length() && k < spot.pages.length() && spot_page(pages[k]) == spot_page(spot.pages[k]) {
    k = k + 1
  }
  if k == 0 {
    // (the root differs: another place's)
    while app.nav.depth() > 1 && app.nav.pop() {
      ()
    }
    app.nav.replace(spot.pages[0])
    k = 1
  } else if k < spot.pages.length() && app.nav.depth() > k {
    while app.nav.depth() > k + 1 && app.nav.pop() {
      ()
    }
    app.nav.replace(spot.pages[k])
    k = k + 1
  } else {
    while app.nav.depth() > k && app.nav.pop() {
      ()
    }
  }
  for p in spot.pages[k:] {
    app.nav.push(p)
  }
  @signals.end_batch()
}

///|
/// Forward, where there is one to go to (history_forward_step). Whether it went.
pub fn go_forward(src : Source) -> Bool {
  match history_forward_step(src) {
    Some(f) => {
      f()
      true
    }
    None => false
  }
}

///|
/// A page closed itself (its 关闭, 取消: close_page), as a browser's page goes history.back: where it came to the entry
/// before, that entry the one now; else the entry now changed (history_note).
fn history_closed() -> Unit {
  match history_back.last() {
    Some(b) if same_spot(b, spot_here()) => {
      history_back.pop() |> ignore
      history_changed()
    }
    _ => ()
  }
}
