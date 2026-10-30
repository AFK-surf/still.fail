// The files' page on a wide screen (ember web/src/pages/Files.tsx FilesShell, Files.css.ts), as Finder's window: a row
// of tabs, each a folder of a station of the workspace (tabs.mbt: the core keeps them), the one shown below; a tab split
// in two shows two folders side by side, of one station or two, to drag from one to the other. The side in front (its
// top lined in the accent) is what the page's address says and what the keys work on; a press in the other one puts it
// in front. Each side is a folder's page (its head, then FolderView) under its own station.

///|
/// A folder opened in the side in front (the stack's page above the files' place, in place of what was open); in the
/// chat's 文件 tab while it is built, there. On the tape opened from the page in use (a folder in it, its path): over
/// it, as a phone's is, back coming to the folder it was opened from (page_goes_on).
pub fn files_go(at : DriveAt) -> Unit {
  if tab_building() {
    tab_go(at)
    return
  }
  @sfbase.history_push()
  if page_goes_on() {
    if !(app.nav.top() is Drive(here) && here == at) {
      app.nav.push_over(Drive(at))
    }
    return
  }
  while app.nav.depth() > 1 {
    if !app.nav.pop() {
      break
    }
  }
  app.nav.push(Drive(at))
}

///|
/// What the shell holds: where it last told the tabs the address moved to.
priv struct Shell {
  mut arrived : String
}

///|
// kept across runs: the shell's state (shell_reset puts it back)
let shell : Shell = { arrived: "" }

///|
fn shell_reset() -> Unit {
  shell.arrived = ""
}

///|
/// A pane's folder (its last part; a root pinned by its name, the home as 主目录) and its station's name (paneParts).
pub fn pane_parts(p : DriveAt, stations : Array[DvStation]) -> (String, String) {
  let root = p.root.unwrap_or("")
  match stations.iter().find_first(fn(s) { s.station == p.station }) {
    Some(s) => {
      let folder = if p.path != "" {
        dv_name(p.path)
      } else if root == s.home && !s.roots.iter().any(fn(r) { r.path == root }) {
        @sf.t("web-pages.drive.home")
      } else {
        dv_root_label(s.roots, root)
      }
      (folder, s.name)
    }
    None => (if p.path != "" { dv_name(p.path) } else { dv_name(root) }, "")
  }
}

///|
/// The files' page of workspace `ws` at `here` (the page's address: the side in front of the tab shown), `room` across:
/// the bar (the tabs, when more than one; what can be done to the folder in front; 传输, split, a new tab), then the
/// tab shown.
pub fn files_shell(
  c : @ui.Ctx,
  src : Source,
  ws : String,
  stations : Array[DvStation],
  here : DriveAt,
  room : Double,
) -> Unit {
  // what is dragged moved on or let go, before what it goes over is drawn
  drag_frame(c, src, ws)
  // the address moved (a link, the sidebar, history): the side in front follows it
  let arrive = ws + "\n" + here.station + "\n" + here.root.unwrap_or("") + "\n" + here.path
  if shell.arrived != arrive {
    c.after_build("files-arrive", fn() {
      if shell.arrived != arrive {
        shell.arrived = arrive
        files_tabs_act(src, ws, "arrive", pane=here, fn(_) {  })
      }
    })
  }
  // until the core has them, the one tab where the address is
  let tabs : FilesTabs = match files_tabs(src, ws) {
    Some(Some(t)) if t.tabs.length() > 0 => t
    _ => { tabs: [{ id: "", panes: [here], front: 0 }], current: "", front: here }
  }
  let tab = match tabs.tabs.iter().find_first(fn(x) { x.id == tabs.current }) {
    Some(t) => t
    None => tabs.tabs[0]
  }
  // another tab or side brought in front: the address says it
  let show = fn(act : String, pane : DriveAt?, id : String?, side : Int?) {
    c.tell("files-tabs/" + act, fn() {
      files_tabs_act(src, ws, act, pane?, id?, side?, fn(next) {
        match next {
          Some(n) => if !same_pane(n.front, here) { files_go(n.front) }
          None => ()
        }
      })
    })
  }
  // the side in front is where the address is: drawn from it, not from what is kept (which follows it)
  let pane_at = fn(x : FilesTab, i : Int) -> DriveAt {
    if x.id == tab.id && i == tab.front {
      here
    } else {
      x.panes.get(i).unwrap_or(here)
    }
  }
  let split_on = tab.panes.length() == 2
  // ⌘T a new tab where the front is, ⌃Tab / ⌘⇧] and ⌘⇧[ go along them, ⌘⌥D splits, ⌘⇧G a folder by its path (as
  // Finder's 前往文件夹)
  let at = tabs.tabs.search_by(fn(x) { x.id == tabs.current }).unwrap_or(0)
  let along = fn(step : Int) {
    let n = tabs.tabs.length()
    show("show", None, Some(tabs.tabs[(at + step + n) % n].id), None)
  }
  if c.shortcut('t') {
    show("open", Some(here), None, None)
  } else if c.key_pressed(@ui.key_tab, mods=@ui.mod_ctrl) || c.shortcut(']', shift=true) {
    along(1)
  } else if c.key_pressed(@ui.key_tab, mods=@ui.mod_ctrl + @ui.mod_shift_key) || c.shortcut('[', shift=true) {
    along(-1)
  } else if c.key_pressed(@ui.key_of_char('d'), mods=@ui.mod_cmd + @ui.mod_alt) {
    show("split", None, None, None)
  } else if c.key_pressed(@ui.key_of_char('g'), mods=@ui.mod_cmd + @ui.mod_shift_key) {
    go_to_open()
  }
  // a side's folder, as the folder's own parts take it (drive.mbt), in its side's room; a folder opened in a new tab
  // or on the other side
  let side_room = if split_on { room / 2.0 - body_in_half } else { room - body_in }
  let folder_of = fn(i : Int, p : DriveAt) -> FolderOf? {
    match stations.iter().find_first(fn(x) { x.station == p.station }) {
      Some(st) =>
        Some({
          key: "page/\{i}",
          ws,
          st,
          rights: dv_rights(src, ws, Some(st)),
          at: p,
          front: i == tab.front,
          room: side_room,
          go: fn(to, _) { files_go(to) },
          open_in: Some(fn(to, beside) { show(if beside { "besides" } else { "open" }, Some(to), None, None) }),
          go_to: Some(go_to_open),
          manage: Some(fn() { manage_roots(src, ws, p.station) }),
        })
      None => None
    }
  }
  let page = c.id("files-page")
  c.box(style=page_box, id=page, fn() {
    let bar = c.id("files-bar")
    if @ui.window_inset() {
      c.window_drag(bar)
    }
    c.box(style=if @sf.in_pane() { bar_box_tape() } else { bar_box_wide() }, id=bar, fn() {
      // the tabs as Safari's compact ones; one tab alone has none (as Finder's window): only the bar's buttons
      if tabs.tabs.length() > 1 {
        tab_row(c, stations, tabs, pane_at, fn(act, id) { show(act, None, Some(id), None) })
      } else {
        c.box(style=tabs_none, fn() {  }) |> ignore
      }
      // what can be done to the folder in front, then the tabs' own, a little apart
      match folder_of(tab.front, here) {
        Some(f) => folder_actions(c, src, f)
        None => ()
      }
      c.box(style=bar_apart, fn() {  }) |> ignore
      let lit = @sf.theme().p.accent
      // (as a bar's buttons are: round on the tape, the last in the panel's corner concentric with it; at the window's
      // corner the corner they share, following it: @sf.bar_keys_link)
      if @sf.icon_button(
          c,
          "view-columns",
          key="files/split",
          on=split_on,
          round=true,
          linked?=@sf.bar_keys_link(),
          ink?=if split_on { Some(lit) } else { None },
          label=@sf.t(if split_on { "web-pages.files.unsplit" } else { "web-pages.files.split" }),
        ) {
        show("split", None, None, None)
      }
      if @sf.icon_button(c, "plus", key="files/new-tab", round=true, linked?=@sf.bar_keys_link(), label=@sf.t("web-pages.files.newTab")) {
        show("open", Some(here), None, None)
      }
    })
    |> ignore
    // the tab shown: a side each, split the one in front lined at its top
    c.box(style=panes_row, fn() {
      for i in 0..<tab.panes.length() {
        let front = i == tab.front
        // (each side's ids its own: the same folder can be on both)
        c.scope(i, fn() {
          pane_frame(c, src, folder_of(i, pane_at(tab, i)), "page/\{i}", split_on, front, fn() {
            if !front {
              show("front", None, None, Some(i))
            }
          })
        })
      }
    })
    |> ignore
    go_to(c, src, ws, here, files_go)
    clash_dialog(c)
    drag_ghost(c, page)
  })
  |> ignore
}

///|
/// The tabs (Files.tsx): one groove, each tab an equal share of it, the one shown raised; its folder first, its station
/// after it, small, a dot of its station's colour before; its close at its left while pointed at. `show`: a tab shown
/// or closed.
fn tab_row(
  c : @ui.Ctx,
  stations : Array[DvStation],
  tabs : FilesTabs,
  pane_at : (FilesTab, Int) -> DriveAt,
  show : (String, String) -> Unit,
) -> Unit {
  let t = @sf.theme()
  let g = c.box(style=tabs_groove, fn() {
    for x in tabs.tabs {
      let on = x.id == tabs.current
      let id = c.id("files/tab/" + x.id)
      let cid = c.id("files/tab-close/" + x.id)
      if c.clicked(cid) {
        show("close", x.id)
      } else if !on && c.clicked(id) {
        show("show", x.id)
      }
      // (its ✕ always to a finger, which hovers over nothing)
      let hot = @sf.pointed_or_finger(c, c.lit(id) || c.lit(cid))
      let panes = Array::makei(x.panes.length(), fn(i) { pane_at(x, i) })
      let words = panes
        .map(fn(p) {
          let (folder, station) = pane_parts(p, stations)
          station + " › " + folder
        })
        .join(" | ")
      let b = c.box(style=if on { tab_on } else { tab_off }, id~, fn() {
        // (drawn clear when not shown: the hand changes no box)
        let close = c.box(style=tab_close, id=cid, fn() {
          @sf.icon(c, "close", size=close_icon, color=if hot { t.p.muted } else { 0L }) |> ignore
        })
        c.semantics(close, Button, id=cid, label=@sf.t("web-pages.files.closeTab"))
        c.box(style=tab_parts, fn() {
          for i, p in panes {
            let tone = stations.search_by(fn(s) { s.station == p.station }).unwrap_or(0) % station_dots.length()
            c.box(style=station_dots[tone], fn() {  }) |> ignore
            let (folder, station) = pane_parts(p, stations)
            c.text(folder, style=if on { tab_folder_on } else { tab_folder }) |> ignore
            c.text(station, style=tab_station) |> ignore
          }
        })
        |> ignore
        // (as wide as its close, so its words are in its middle)
        c.box(style=tab_close, fn() {  }) |> ignore
      })
      c.semantics(b, Tab, id~, label=words, selected=on)
    }
  })
  c.semantics(g, TabList, label=@sf.t("web-pages.files.tabs"))
}

///|
/// One side (PaneFrame): a folder's page under its station, what is pressed in it putting it in front first (as the
/// web's side takes the pointer going down first); a station not among the workspace's, said so.
fn pane_frame(
  c : @ui.Ctx,
  src : Source,
  f : FolderOf?,
  key : String,
  split_on : Bool,
  front : Bool,
  front_it : () -> Unit,
) -> Unit {
  c.box(style=if split_on { side_half } else { side_one }, fn() {
    if split_on {
      c.box(style=if front { front_line } else { back_line }, fn() {  }) |> ignore
    }
    let f = match f {
      Some(f) => f
      None => {
        c.box(style=missing_box, fn() { c.text(@sf.t("web-pages.workspace.noSuchStation"), style=missing_words) |> ignore })
        |> ignore
        return
      }
    }
    c.box(style=if split_on { body_half } else { body_one }, fn() {
      let pid = c.id("files/side/" + key)
      // a press going down in it (a tap down and up between two frames too), before what it presses takes it
      let p = c.press()
      if p.fresh {
        match c.rect_of(pid) {
          Some((x, y, w, h)) if p.x >= x && p.x < x + w && p.y >= y && p.y < y + h => front_it()
          _ => ()
        }
      }
      c.box(style=side_one, id=pid, fn() { folder_page(c, src, f, None, front_it~) }) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A tab's close (10), and the folder's room in from a side's sides (one: 32 before it, 40 after; split, 24 each and
/// its rows' 16).
let close_icon : Double = 10.0

///|
let body_in : Double = 72.0

///|
let body_in_half : Double = 80.0

///|
// kept across runs: a value (no field of it changes)
let page_box : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

///|
/// The bar (bar): 44 high, what is on it at its end, 12 in, a line under it.
// kept across runs: a value (no field of it changes)
let bar_box : @ui.Style = @ui.css("row w=Full h=S11 px=S3 gap=S1 align=ACenter justify=JEnd")

///|
/// The same in a window's whole: its last button at the window's top right corner following it where the bar's buttons
/// do (@sf.window_end_in).
fn bar_box_wide() -> @ui.Style {
  bar_box.then(@ui.style(pr=@sf.room_of(@sf.window_end_in(bar_in)), gap=@sf.keys_gap()))
}

///|
/// The same in a panel of its own on the tape, as a page's bar there: on the tape's one line (@sf.tape_bar_over), its
/// last button in the panel's top right corner concentric with it where it can be, else clear of it (tape_bar_end);
/// what it starts with (where the room left puts it) clear of the top left one (tape_bar_clear_start).
fn bar_box_tape() -> @ui.Style {
  let over = @sf.tape_bar_over()
  bar_box.then(
    @ui.style(
      h=Fixed(bar_h + over),
      pt=@sf.room_of(over),
      pl=@sf.room_of(@sf.tape_bar_clear_start(bar_in)),
      pr=@sf.room_of(@sf.tape_bar_end(bar_in)),
      gap=@sf.keys_gap(),
    ),
  )
}

///|
/// The bar's height (bar_box: S11).
let bar_h : Double = 44.0

///|
/// Room for what the bar starts with when there is one tab (tabsNone).
// kept across runs: a value (no field of it changes)
let tabs_none : @ui.Style = @ui.style(w=@sf.grow)

///|
/// Between what is done to the folder and the tabs' own buttons: a little room more (no line: only a menu's parts are
/// set apart by one).
// kept across runs: a value (no field of it changes)
let bar_apart : @ui.Style = @ui.css("w=S2")

///|
/// The tabs' groove (tabs): capsules in a capsule, 2 apart, on the words' colour at 6%.
// kept across runs: a value (no field of it changes)
let tabs_groove : @ui.Style = @ui.style(row=true, w=@sf.grow, p=S0_5, gap=S0_5, radius=Full, bg=Tint)

///|
/// A tab: an equal share of the groove (as Safari's: the groove is its tabs', none of it left empty after them), 28
/// high; the one shown on the page's ground.
// kept across runs: a value (no field of it changes)
let tab_off : @ui.Style = @ui.style(
  row=true,
  w=@sf.grow,
  h=S7,
  px=S1_5,
  align=ACenter,
  radius=Full,
  hovered=@ui.patch(bg=Hover),
)

///|
// kept across runs: a value (no field of it changes)
let tab_on : @ui.Style = tab_off.then(@ui.css("bg=Bg shadow=Sm hovered{bg=Bg}"))

///|
/// Its close (tabClose): a circle 16 across, 6 in from its end.
// kept across runs: a value (no field of it changes)
let tab_close : @ui.Style = @ui.css("w=S4 h=S4 radius=Full align=ACenter justify=JCenter hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let tab_parts : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S1_5, align=ACenter, justify=JCenter, clip=true)

///|
// kept across runs: a value (no field of it changes)
let tab_folder : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tab_folder_on : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tab_station : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, wrap=false)

///|
/// A station's colour on the tabs: one of six, by its place among the workspace's (dot: 7 across).
// kept across runs: a table, never written
let station_dots : Array[@ui.Style] = ([Accent, Link, Positive, Warn, Danger, Muted] : Array[@ui.Color]).map(fn(k) {
  @ui.style(w=S1_5, h=S1_5, radius=Full, bg=k)
})

///|
/// The tab's sides, side by side, apart by their own padding (no line between).
// kept across runs: a value (no field of it changes)
let panes_row : @ui.Style = @ui.css("row w=Full h=Full")

///|
// kept across runs: a value (no field of it changes)
let side_one : @ui.Style = @ui.css("w=Full h=Full")

///|
// kept across runs: a value (no field of it changes)
let side_half : @ui.Style = @ui.style(w=@sf.grow, h=Full, clip=true)

///|
/// Split, the side in front lined at its top in the accent (2), the other not.
// kept across runs: a value (no field of it changes)
let front_line : @ui.Style = @ui.css("w=Full h=S0_5 bg=Accent")

///|
// kept across runs: a value (no field of it changes)
let back_line : @ui.Style = @ui.css("w=Full h=S0_5")

///|
/// What a side shows of its folder (FolderView), in from its sides.
// kept across runs: a value (no field of it changes)
let body_one : @ui.Style = @ui.css("row w=Full h=Full pl=S8 pr=S10 clip")

///|
// kept across runs: a value (no field of it changes)
let body_half : @ui.Style = @ui.css("row w=Full h=Full px=S4 clip")

///|
/// A side whose station is not among the workspace's (Missing).
// kept across runs: a value (no field of it changes)
let missing_box : @ui.Style = @ui.css("w=Full px=S10 pt=S3 pb=S3")

///|
// kept across runs: a value (no field of it changes)
let missing_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)
