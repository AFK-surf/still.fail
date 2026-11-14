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
  /// a page opened where the layout has it (the pane table): what pages, links and the app's
  /// own doings call (open), never the stack themselves
  open : (Page) -> Unit
  /// a page opened from the page in view (a chat's link in a message): over it where the layout keeps pages, back
  /// coming to it again (open_over)
  open_over : (Page) -> Unit
  /// a detail of a chat opened where the layout has it (an agent's history by its key, jobs, letters, files, a
  /// service: the side panel's tabs on the wide frame, toggled): what a page asks of its chat (open_detail)
  detail : (Source, ChatRef, String) -> Unit
  /// a file asked to be opened beside the page (its `view:` tab: viewer_tab.mbt) put there where the layout has a side
  /// panel for the page in view (the wide frame's chat), in front: the tab it put there (that file's tab there
  /// already, by whatever key it was opened with), none where it has nowhere (what asked opens it over the whole
  /// window). What open_preview calls, never a page itself
  beside : (String) -> String?
  /// whether the layout has such a side panel for the page in view now: what offers to open a file there asks
  beside_room : () -> Bool
  /// what back does where the layout has it (the tiers' table), none where back is the
  /// system's: what the keys, the frames and the pages' back call (back_step, go_back), never the stack themselves
  back : () -> (() -> Unit)?
  /// what was chosen in a list (a row of a place's list, a pick) shown where the layout has the page: on the tape the
  /// page beside the sidebar in use, brought over from the side panel (show_chosen)
  show : () -> Unit
  /// what was opened from outside (a notification, an outside link) brought into view on the tape, even from the
  /// sidebar (bring_chosen)
  bring : () -> Unit
  /// the rail changed where it is (自定义侧边条), where the layout has a rail beside the pages; none
  /// where it has none
  edit_rail : () -> Unit
}

///|
/// The stack's own, until the pages say theirs (as they are first drawn): a page pushed, a new chat risen from the
/// foot; a detail nowhere, nothing beside.
pub fn bare_shell() -> Shell {
  {
    home: nav_home,
    close_overlays: fn() { app.menu = false },
    open_invite: fn(_) {  },
    behind: fn(_) {  },
    open: stack_open,
    open_over: stack_open,
    detail: fn(_, _, _) {  },
    beside: fn(_) { None },
    beside_room: fn() { false },
    back: stack_back,
    show: fn() {  },
    bring: fn() {  },
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
/// Back's step off the stack (what the shells' back does to it): its top page popped, as the stack's own back is
/// (app_history.mbt: the spot it comes to is back's).
pub fn back_pop() -> Unit {
  let top = app.nav.top()
  let over = app.nav.top_over()
  let risen = app.nav.risen()
  // (one change: what notes where the app is told once, the entry left for forward first)
  @signals.start_batch()
  if app.nav.pop() {
    went_back(top, over, risen, app.nav.pages())
  }
  @signals.end_batch()
}

///|
/// What was chosen in a list shown where the layout has the page (Shell's `show`): what a list's row calls once what it
/// chose is the page's (on the tape the page comes over to show it; beside the list or pushed, nothing more).
pub fn show_chosen() -> Unit {
  (shell.val.show)()
}

///|
/// What was opened from outside brought into view where the layout holds panels on a tape (Shell's `bring`): on a
/// foldable or tablet's tape, even when the sidebar was in use.
pub fn bring_chosen() -> Unit {
  (shell.val.bring)()
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
  history_closed()
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
  history_act(fn() { (shell.val.detail)(src, r, tab) })
}

///|
/// The pages' last drawn.
pub let shell : Ref[Shell] = Ref(bare_shell())

///|
/// Whether the layout has a side panel for the page in view (`beside_room` of the shell as it was last set:
/// shell_set), told only as that changes: what offers to open a file there follows it (beside_offered), a node made
/// once as well as an old view built each frame.
// kept across runs: put back by pages.mbt's reset, as the shell is
let beside_room_now : @signals.Signal[Bool] = @signals.signal(false)

///|
/// The pages' shell `s` said (each frame they are drawn, or as the app begins again): beside_room_now told where
/// what it says of the side panel changed.
pub fn shell_set(s : Shell) -> Unit {
  shell.val = s
  let room = @signals.untracked(s.beside_room)
  if room != beside_room_now.untracked() {
    beside_room_now.set(room)
  }
}

///|
/// A place's page at the stack's root: 对话 Home, 文件 Files, another its own.
pub fn place_page(place : String) -> Page {
  match place {
    "chats" => Home
    "files" => Files
    p => Place(p)
  }
}

///|
/// A place gone to (the bottom bar's, the rail's, back to the chats from another place's top), in every tier: what is
/// over the pages put down (Shell's `close_overlays`), the stack back to its root and the place's page that root, in
/// place; `way` the side it comes in from (the bar's order: -1 its left, 1 its right, 0 none). The same place again
/// changes nothing. Whether it went. `kept`: the page that leaves the root put on the stack's shelf and the place's taken
/// back from it (nav_root_kept: the bottom bar's on 小屏), not let go and made anew.
pub fn go_place(place : String, way? : Int = 0, kept? : Bool = false) -> Bool {
  let page = place_page(place)
  if app.nav.depth() == 1 && app.nav.top() == page {
    return false
  }
  history_act(fn() {
    (shell.val.close_overlays)()
    app.switch_way = way
    nav_home()
    if kept {
      nav_root_kept(page)
    } else {
      app.nav.replace(page)
    }
  })
  true
}
