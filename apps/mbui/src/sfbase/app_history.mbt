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
/// (None until a frame ended on one).
let history_back : Array[Spot] = []

///|
let history_forward : Array[Spot] = []

///|
let history_now : Ref[Spot?] = Ref(None)

///|
/// A new entry asked since the frame before ended (history_push): one for all a person's act moves, however many steps
/// it takes the stack through.
let history_pushed : Ref[Bool] = Ref(false)

///|
/// At most so many entries back, the oldest let go (a browser keeps its own).
let history_most = 100

///|
/// The entries forgotten (the app's reset).
fn history_reset() -> Unit {
  history_back.clear()
  history_forward.clear()
  history_now.val = None
  history_pushed.val = false
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
/// A person's act goes somewhere (navigate with history "push"): said before it moves the stack or the workspace, the
/// entry it leaves kept for back and what forward had (as a browser forgets it after a link followed). Once for the
/// act, its steps the frame through; an act that leaves the app where it was adds none (history_note).
pub fn history_push() -> Unit {
  if history_pushed.val || history_now.val is None {
    return
  }
  history_pushed.val = true
  history_back.push(spot_here())
  if history_back.length() > history_most {
    history_back.remove(0) |> ignore
  }
  history_forward.clear()
}

///|
/// Back by the stack's own (a page's back, the system's gesture, the shell's back_pop; Nav's went_back): the entry
/// before traversed to as the stack takes its page off, the one now kept for forward.
fn went_back(_p : Page, _over : Bool, _risen : Bool, _pages : Array[Page]) -> Unit {
  guard history_now.val is Some(now) && history_back.length() > 0 else { return }
  history_back.pop() |> ignore
  history_forward.push(now)
  // (the stack decides where it lands: history_note puts it in the entry now)
}

///|
/// The entry now as a frame ends (workspace `ws` in view): where the app is put in it (navigate with history
/// "replace": what moved the stack without a person's act changes the entry, adds none); an act that came back to
/// where it left, its entry taken back. `passing`: the stack is Home alone where it is never shown so (the wide frame
/// lands on a chat over it the frame after: frame.mbt land), no entry's.
pub fn history_note(ws : String, passing : Bool) -> Unit {
  if ws == "" || passing {
    return
  }
  let here : Spot = { ws, pages: app.nav.pages() }
  if history_pushed.val {
    history_pushed.val = false
    match history_back.last() {
      Some(b) if same_spot(b, here) => history_back.pop() |> ignore
      _ => ()
    }
  }
  history_now.val = Some(here)
}

///|
/// Back along the history, where there is an entry before this one: it brought again (history_go).
pub fn history_back_step(src : Source) -> (() -> Unit)? {
  guard history_back.last() is Some(_) else { return None }
  Some(fn() {
    guard history_back.pop() is Some(spot) else { return }
    match history_now.val {
      Some(now) => history_forward.push(now)
      None => ()
    }
    history_go(src, spot)
  })
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
    history_go(src, spot)
  })
}

///|
/// Entry `spot` traversed to (traverseTo): its workspace in view (switched as the rail switches it: the prefs'
/// `workspace`), the stack as it was there. The pages it shares with the stack now stay; of the rest the first takes
/// the place of the first that goes, in place (nothing slides: a chat in place of a chat, as the web's history shows
/// one), the others pushed; the stack only shorter, its pages popped as back pops them.
fn history_go(src : Source, spot : Spot) -> Unit {
  let ws = match history_now.val {
    Some(n) => n.ws
    None => ""
  }
  if spot.ws != ws {
    app.picked.set(spot.ws)
    (src.call)("prefs.set", { "workspace": Json::string(spot.ws) }, fn(_) {  })
  }
  history_now.val = Some(spot)
  app.menu.set(false)
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
    Some(b) if same_spot(b, spot_here()) => history_back.pop() |> ignore
    _ => ()
  }
}
