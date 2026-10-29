// What the app's own doings (links opened, notifications, the system's say) ask of the pages drawn: what is
// over them (sheets, menus) and how an invitation shows are theirs, said as they are drawn (src/sfapp pages_shell).

///|
pub(all) struct Shell {
  /// back to the stack's root (Home), what is over the pages put down
  home : () -> Unit
  /// what is over the pages put down as a page opens from a link (a sheet, a menu)
  close_overlays : () -> Unit
  /// an invitation's link opened: what it leads to shown, before it is accepted (its token)
  open_invite : (String) -> Unit
  /// the app gone behind, between frames (what lives only while it is shown let go)
  behind : (Source) -> Unit
  /// a page opened where the layout has it (docs/architecture.md, the pane table): what pages, links and the app's
  /// own doings call (open), never the stack themselves
  open : (Page) -> Unit
  /// a page opened from the page in view (a chat's link in a message): over it where the layout keeps pages, back
  /// coming to it again (open_over)
  open_over : (Page) -> Unit
  /// a detail of a chat opened where the layout has it (an agent's history by its key, jobs, letters, files, a
  /// service: the side panel's tabs on the wide frame, toggled): what a page asks of its chat (open_detail)
  detail : (Source, ChatRef, String) -> Unit
  /// what back does where the layout has it (docs/architecture.md, the tiers' table), none where back is the
  /// system's: what the keys, the frames and the pages' back call (back_step, go_back), never the stack themselves
  back : () -> (() -> Unit)?
  /// what was chosen in a list (a row of a place's list, a pick) shown where the layout has the page: on the tape the
  /// page beside the sidebar in use, brought over from the side panel (show_chosen)
  show : () -> Unit
  /// the rail changed where it is (自定义侧边条, Rail.tsx editing), where the layout has a rail beside the pages; none
  /// where it has none
  edit_rail : () -> Unit
}

///|
/// The stack's own, until the pages say theirs (as they are first drawn): a page pushed, a new chat risen from the
/// foot; a detail nowhere.
pub fn bare_shell() -> Shell {
  {
    home: nav_home,
    close_overlays: fn() { app.menu = false },
    open_invite: fn(_) {  },
    behind: fn(_) {  },
    open: stack_open,
    open_over: stack_open,
    detail: fn(_, _, _) {  },
    back: stack_back,
    show: fn() {  },
    edit_rail: fn() {  },
  }
}

///|
/// Back on the stack alone: its top page popped, none at its root.
fn stack_back() -> (() -> Unit)? {
  if app.nav.depth() > 1 {
    Some(back_pop)
  } else {
    None
  }
}

///|
/// What back took off the stack, last on top, for forward to put back (⌘], a mouse's forward button; the web's
/// history.forward): each the stack as back left it, the page taken off, how it was put there (over the one under it,
/// risen from the foot), and whether the wide frame landed on a new chat since (frame.mbt land: the chats' place is
/// never empty).
let forward_steps : Array[ForwardStep] = []

///|
priv struct ForwardStep {
  pages : Array[Page]
  page : Page
  over : Bool
  risen : Bool
  mut landed : Bool
  // a chat back went from to the chat before it (chat_back): the chat put back in its place
  swap : Bool
}

///|
/// Page `p` taken off the stack by back (the shells' back_pop, the stack's own: new_nav's `went_back`), kept for forward.
fn went_back(p : Page, over : Bool, risen : Bool, pages : Array[Page]) -> Unit {
  forward_steps.push({ pages, page: p, over, risen, landed: false, swap: false })
}

///|
/// Back's step off the stack (what the shells' back does to it): its top page popped, kept for forward.
pub fn back_pop() -> Unit {
  let top = app.nav.top()
  let over = app.nav.top_over()
  let risen = app.nav.risen()
  if app.nav.pop() {
    went_back(top, over, risen, app.nav.pages())
  }
}

///|
/// The wide frame's chats' place landed on a new chat over the stack back left at its root (frame.mbt land): forward
/// still puts back what back took, in the new chat's place.
pub fn forward_landed() -> Unit {
  match forward_steps.last() {
    Some(s) if s.pages == app.nav.pages() => s.landed = true
    _ => ()
  }
}

///|
/// What forward does here: the page back last took off put back, while the stack is as that back left it; none when
/// back took nothing or the stack changed since (a page opened, a place chosen: what it took is forgotten, as a
/// browser's forward is after a link followed).
pub fn forward_step() -> (() -> Unit)? {
  guard forward_steps.last() is Some(s) else { return None }
  let pages = app.nav.pages()
  if pages == s.pages {
    Some(fn() {
      forward_steps.pop() |> ignore
      if s.swap {
        match app.nav.top() {
          Chat(r) => chat_trail.push(r)
          _ => ()
        }
        app.nav.replace(s.page)
      } else if s.risen {
        app.nav.rise(s.page)
      } else if s.over {
        app.nav.push_over(s.page)
      } else {
        app.nav.push(s.page)
      }
    })
  } else if s.landed && pages == [..s.pages, NewChat] {
    Some(fn() {
      forward_steps.pop() |> ignore
      app.nav.replace(s.page)
    })
  } else {
    forward_steps.clear()
    None
  }
}

///|
/// The chats shown before the one in the pane, the last on top, on the wide frame with the page beside the sidebar
/// (the web's history of a chat chosen after another): another chat chosen there in its place leaves the one it took
/// the place of here (chat_left), back goes to them one by one (chat_back), at most `chat_trail_most`.
let chat_trail : Array[ChatRef] = []

///|
let chat_trail_most = 50

///|
/// Chat `r`, shown in the pane, given up for another chosen in its place (sfapp's open_chat_beside): kept for back.
pub fn chat_left(r : ChatRef) -> Unit {
  match chat_trail.last() {
    Some(l) if same_chat(l, r) => return
    _ => ()
  }
  chat_trail.push(r)
  if chat_trail.length() > chat_trail_most {
    chat_trail.remove(0) |> ignore
  }
}

///|
fn same_chat(a : ChatRef, b : ChatRef) -> Bool {
  a.station == b.station && a.session == b.session
}

///|
/// The workspace a chat is in: the first part of its station's key (`ws/station`).
fn chat_workspace(r : ChatRef) -> String {
  match r.station.split("/").next() {
    Some(w) => w.to_string()
    None => ""
  }
}

///|
/// Back to the chat shown before chat `open` (the wide frame's back with a chat alone beside the sidebar: wide_back), in
/// its place, kept for forward; none when no chat of its workspace was shown before it (those of another workspace,
/// and itself again, passed over and forgotten).
pub fn chat_back(open : ChatRef) -> (() -> Unit)? {
  while chat_trail.last() is Some(l) &&
        (same_chat(l, open) || chat_workspace(l) != chat_workspace(open)) {
    chat_trail.pop() |> ignore
  }
  guard chat_trail.last() is Some(prev) else { return None }
  Some(fn() {
    chat_trail.pop() |> ignore
    app.nav.replace(Chat(prev))
    forward_steps.push({
      pages: app.nav.pages(),
      page: Chat(open),
      over: false,
      risen: false,
      landed: false,
      swap: true,
    })
  })
}

///|
/// Forward, where there is one to go to (forward_step). Whether it went.
pub fn go_forward() -> Bool {
  match forward_step() {
    Some(f) => {
      f()
      true
    }
    None => false
  }
}

///|
/// What was chosen in a list shown where the layout has the page (Shell's `show`): what a list's row calls once what it
/// chose is the page's (on the tape the page comes over to show it; beside the list or pushed, nothing more).
pub fn show_chosen() -> Unit {
  (shell.val.show)()
}

///|
/// The rail changed where it is, as 外观's 自定义侧边条 asks (Shell's `edit_rail`): where the layout has no rail, nothing.
pub fn edit_rail() -> Unit {
  (shell.val.edit_rail)()
}

///|
/// What back does here, in every tier (Shell's `back`); none where it is the system's (a phone's list: the app left).
pub fn back_step() -> (() -> Unit)? {
  (shell.val.back)()
}

///|
/// Page `p` closed, as a page asks for itself (its 关闭, 取消, the player or the reader shut, a chat archived): taken
/// off the stack where it lies, the pages over it with it; not on the stack, nothing. Whether it was there. What a page
/// calls, never the stack itself; its bar's back is go_back.
pub fn close_page(p : Page) -> Bool {
  let pages = app.nav.pages()
  let mut at = -1
  for k = pages.length() - 1; k >= 1; k = k - 1 {
    if pages[k] == p {
      at = k
      break
    }
  }
  if at < 0 {
    return false
  }
  while app.nav.depth() > at {
    if !app.nav.pop() {
      break
    }
  }
  true
}

///|
/// Back, where there is one to go to (Shell's `back`). Whether it went.
pub fn go_back() -> Bool {
  match back_step() {
    Some(f) => {
      f()
      true
    }
    None => false
  }
}

///|
/// Page `p` shown in place of the one on top (a page's step on from it, leaving it: a profile added gone on to choosing
/// its models): that one taken off and `p` put where it was, over the one under it as it was (Nav::push_over: on the
/// tape, opened from the page, it slides in; chosen in the sidebar, it stays the one chosen), sliding in as a push does
/// where pushes slide. Not back: what back would do there (bring the sidebar over on the tape) is not asked.
pub fn open_in_place(p : Page) -> Unit {
  let over = app.nav.top_over()
  app.nav.pop() |> ignore
  if over {
    app.nav.push_over(p)
  } else {
    app.nav.push(p)
  }
}

///|
/// Page `p` opened on the stack (a phone's way): pushed, a new chat risen from the foot (App.kt: the new chat slides
/// up).
pub fn stack_open(p : Page) -> Unit {
  match p {
    NewChat => app.nav.rise(NewChat)
    _ => app.nav.push(p)
  }
}


///|
/// Chat `r`'s detail `tab` opened, where the layout has it (Shell's `detail`).
pub fn open_detail(src : Source, r : ChatRef, tab : String) -> Unit {
  (shell.val.detail)(src, r, tab)
}

///|
/// The pages' last drawn.
pub let shell : Ref[Shell] = Ref(bare_shell())

///|
/// A place's page at the stack's root: 对话 Home, 文件 Files, 奏 Decisions, another its own.
pub fn place_page(place : String) -> Page {
  match place {
    "chats" => Home
    "files" => Files
    "decisions" => Decisions
    p => Place(p)
  }
}

///|
/// A place gone to (the bottom bar's, the rail's, back to the chats from another place's top), in every tier: what is
/// over the pages put down (Shell's `close_overlays`), the stack back to its root and the place's page that root, in
/// place; `way` the side it comes in from (the bar's order: -1 its left, 1 its right, 0 none). The same place again
/// changes nothing. Whether it went.
pub fn go_place(place : String, way? : Int = 0) -> Bool {
  let page = place_page(place)
  if app.nav.depth() == 1 && app.nav.top() == page {
    return false
  }
  (shell.val.close_overlays)()
  app.switch_way = way
  nav_home()
  app.nav.replace(page)
  true
}
