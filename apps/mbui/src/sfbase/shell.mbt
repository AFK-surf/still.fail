// What the app's own doings (links opened, notifications, the dock, the system's say) ask of the pages drawn: what is
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
  /// a detail of a chat opened where the layout has it (an agent's history by its key, jobs, letters, files, a
  /// service: the side panel's tabs on the wide frame, toggled): what a page asks of its chat (open_detail)
  detail : (Source, ChatRef, String) -> Unit
  /// what back does where the layout has it (docs/architecture.md, the tiers' table), none where back is the
  /// system's: what the keys, the frames and the pages' back call (back_step, go_back), never the stack themselves
  back : () -> (() -> Unit)?
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
    detail: fn(_, _, _) {  },
    back: stack_back,
  }
}

///|
/// Back on the stack alone: its top page popped, none at its root.
fn stack_back() -> (() -> Unit)? {
  if app.nav.depth() > 1 {
    Some(fn() { app.nav.pop() |> ignore })
  } else {
    None
  }
}

///|
/// What back does here, in every tier (Shell's `back`); none where it is the system's (a phone's list: the app left).
pub fn back_step() -> (() -> Unit)? {
  (shell.val.back)()
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
