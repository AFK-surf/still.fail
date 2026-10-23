// A chat's 文件 tab (ember web/src/pages/DriveTab.tsx, DriveTab.css.ts): the files of the workspace's stations beside
// a chat, to put into what is being written. It starts at the chat's station's home for one who browses every folder,
// else at its one folder pinned, else at the places (each station's home and the folders it pins); the way up is a
// trail of folders over the list, the first of them the places. Its three ways (prefs `driveViews.tab`: columns two
// at a time, a tree, a list of names and sizes) and its preview under the list (`driveViews.tabPreview`). A row's menu
// (a right click): 添加到消息, 复制路径, 下载, pin; a row dragged onto the chat is put into the message (the composer
// takes it: files_tab_take_drop). A folder is gone into; what reads, plays or previews opens over the chat. Where it
// is is kept by workspace while the app runs, as the web's tab is.

///|
/// The tab: whether it is being built (rows choose and go here, not on the files' page), where it is by workspace
/// (None: the places; none kept: where it starts), the row chosen in it, its row's menu (what, where), what was asked
/// put into a chat's message (the chat, what), and a row let go off it (what, where, the frame).
priv struct FChatTab {
  mut building : Bool
  places : Map[String, DriveAt?]
  mut scope : String
  mut chosen : String
  mut menu : (FDragged, DvEntry, Double, Double)?
  sent : Array[(String, FDragged)]
  mut let_go : (FDragged, Double, Double, Int)?
  mut chat : String
}

///|
let ftab : FChatTab = {
  building: false,
  places: {},
  scope: "",
  chosen: "",
  menu: None,
  sent: [],
  let_go: None,
  chat: "",
}

///|
fn ftab_reset() -> Unit {
  ftab.building = false
  ftab.places.clear()
  ftab.scope = ""
  ftab.chosen = ""
  ftab.menu = None
  ftab.sent.clear()
  ftab.let_go = None
  ftab.chat = ""
}

///|
/// Whose keys the rows being built use: a chat's 文件 tab's, else the files' page's ("").
fn files_owner() -> String {
  if ftab.building {
    "tab\u{2}"
  } else {
    ""
  }
}

///|
/// The row chosen where rows are being built (the tab's or the page's).
fn files_chosen_now() -> String {
  if ftab.building {
    ftab.chosen
  } else {
    wide.files_chosen
  }
}

///|
fn files_choose(key : String) -> Unit {
  if ftab.building {
    ftab.chosen = key
  } else {
    wide.files_chosen = key
  }
}

///|
/// The tab into a folder of a station (its root, the path under it).
fn ftab_go(station : String, root : String, path : String) -> Unit {
  ftab.places[ftab.scope] = Some({ station, root: Some(root), path })
  // (its columns open to it, from its root)
  wide.files_cols["tab\u{2}" + station + "\u{1}" + root + "\u{1}"] = path
  ftab.chosen = ""
}

///|
/// A row's menu, opened where it was right clicked.
fn ftab_menu_at(station : String, root : String, path : String, e : DvEntry, x : Double, y : Double) -> Unit {
  ftab.menu = Some(
    (
      { station, station_name: "", root, path, abs: dv_absolute(root, path), name: e.name, size: e.size, dir: e.dir },
      e,
      x,
      y,
    ),
  )
}

///|
/// What is carried off the tab now (a row dragged out of it), for the chat's composer to show it would take it.
fn files_tab_dragging() -> FDragged? {
  fdrag.item
}

///|
/// A row let go off the tab, where (x, y in the window), taken once, in the frame it was let go or the next: for the
/// chat's composer, when let go over it, to put it into the message.
fn files_tab_take_drop(c : @ui.Ctx) -> (FDragged, Double, Double)? {
  match ftab.let_go {
    Some((item, x, y, frame)) if c.frame_number() - frame <= 1 => {
      ftab.let_go = None
      Some((item, x, y))
    }
    _ => None
  }
}

///|
/// What 添加到消息 put in for the chat `chat` since it was last asked, taken.
fn files_tab_take_sent(chat : String) -> Array[FDragged] {
  let out = ftab.sent.filter(fn(x) { x.0 == chat }).map(fn(x) { x.1 })
  ftab.sent.retain(fn(x) { x.0 != chat })
  out
}

///|
/// The tab for the chat `chat` (its key: what 添加到消息 puts things into), whose station is `station`, filling the box
/// it is drawn in.
fn files_tab(c : @ui.Ctx, src : Source, w : Workspace, chat : String, station : String) -> Unit {
  ftab.scope = w.id
  ftab.chat = chat
  // a row let go off the tab (fdrag_frame lets the carried go where nothing here takes it)
  let carried = fdrag.item
  fdrag_frame(c, src, w, outside=false)
  match carried {
    Some(i) if fdrag.item is None => {
      let (px, py, _) = c.pointer()
      ftab.let_go = Some((i, px, py, c.frame_number()))
    }
    _ => ()
  }
  let (list, _) = dv_stations(src, w.id)
  let stations = list.unwrap_or([]).filter(fn(s) { s.drive })
  let start : DriveAt? = match stations.iter().find_first(fn(s) { s.station == station }) {
    Some(s) if s.anywhere && s.home != "" => Some({ station, root: Some(s.home), path: "" })
    Some(s) if s.roots.length() == 1 => Some({ station, root: Some(s.roots[0].path), path: "" })
    _ => None
  }
  let place = match ftab.places.get(w.id) {
    Some(p) => p
    None => start
  }
  ftab.building = true
  c.box(style=ftab_box, fn() {
    match place {
      None => ftab_places(c, stations)
      Some(at) =>
        match stations.iter().find_first(fn(s) { s.station == at.station }) {
          Some(st) => ftab_folder(c, src, w, st, at)
          None => ftab_places(c, stations)
        }
    }
  })
  |> ignore
  ftab.building = false
  ftab_menu(c, src, w, chat)
}

///|
/// The places (Places): under each station's name (and whether it is away), its home for one who browses every
/// folder, then its folders pinned (what is wrong with one said under its name).
fn ftab_places(c : @ui.Ctx, stations : Array[DvStation]) -> Unit {
  let t = @sf.theme()
  c.box(style=ftab_list, fn() {
    if stations.length() == 0 {
      c.text(tr("web-main.rail.filesNone"), style=ftab_note) |> ignore
    }
    for s in stations {
      c.box(style=ftab_group, fn() {
        c.text(s.name, style=ftab_group_words) |> ignore
        if !s.online {
          c.text(tr("web-pages.stations.offline"), style=ftab_group_words) |> ignore
        }
      })
      |> ignore
      let row = fn(key : String, icon : String, name : String, trouble : String, root : String) {
        let id = c.id("files-tab/place/" + s.station + "/" + key)
        c.cursor(id, Hand)
        if c.clicked(id) {
          ftab_go(s.station, root, "")
        }
        let b = c.box(style=files_row_style, id~, fn() {
          @sf.icon(c, icon, size=files_icon, color=t.p.muted) |> ignore
          c.box(style=ftab_place_words, fn() {
            c.text(name, style=place_name) |> ignore
            if trouble != "" {
              c.text(trouble, style=place_trouble) |> ignore
            }
          })
          |> ignore
          @sf.icon(c, "chevron-right", size=files_icon, color=t.p.subtle) |> ignore
        })
        c.semantics(b, Button, id~, label=name)
      }
      if s.anywhere && s.home != "" {
        row("home", "server", tr("web-pages.drive.home"), "", s.home)
      }
      for r in s.roots {
        let trouble = match r.state {
          "ok" => ""
          "missing" => tr("web-pages.drive.root.missing")
          "not_a_directory" => tr("web-pages.drive.root.notFolder")
          _ => tr("web-pages.drive.root.unreadable")
        }
        row("root/" + r.path, "folder", r.name, trouble, r.path)
      }
    }
  })
  |> ignore
}

///|
/// The way to `abs` (useDrive.ts trailOf): from the home (主目录) when it is under it, else from the top of the disk.
fn ftab_trail(abs : String, home : String) -> Array[(String, String)] {
  let trim = fn(p : String) { if p.length() > 1 && p.has_suffix("/") { p.view(end_offset=p.length() - 1).to_string() } else { p } }
  let at = trim(abs)
  let h = trim(home)
  let out : Array[(String, String)] = []
  let rest = if h != "" && (at == h || at.has_prefix(h + "/")) {
    out.push((tr("web-pages.drive.home"), h))
    at.view(start_offset=h.length()).to_string()
  } else {
    out.push(("/", "/"))
    at
  }
  for part in rest.split("/") {
    if part != "" {
      let (_, last) = out[out.length() - 1]
      out.push((part.to_string(), fdrag_child(last, part.to_string())))
    }
  }
  out
}

///|
/// A folder (FolderList): the trail over it, what is done to it at the trail's end, its list as the tab shows it, the
/// preview under it.
fn ftab_folder(c : @ui.Ctx, src : Source, w : Workspace, st : DvStation, at : DriveAt) -> Unit {
  let t = @sf.theme()
  let root = at.root.unwrap_or("")
  let here = dv_absolute(root, at.path)
  let pinned = st.roots.iter().any(fn(r) { r.path == here })
  let view = match text(field((src.topic)("prefs", {}).value, "driveViews"), "tab") {
    "tree" => "tree"
    "list" => "list"
    _ => "columns"
  }
  let previewing = text(field((src.topic)("prefs", {}).value, "driveViews"), "tabPreview") == "shown"
  // the way here: from the home (or the disk's top) for one who browses everywhere, else from the folder pinned
  let way : Array[(String, String)] = if st.anywhere {
    ftab_trail(here, st.home)
  } else {
    let first = match st.roots.iter().find_first(fn(r) { r.path == root }) {
      Some(r) => r.name
      None => dv_name(root)
    }
    let out = [(first, root)]
    let mut so_far = ""
    for part in at.path.split("/") {
      if part != "" {
        so_far = dv_join(so_far, part.to_string())
        out.push((part.to_string(), dv_absolute(root, so_far)))
      }
    }
    out
  }
  let go_to = fn(abs : String) {
    let prefix = if root.has_suffix("/") { root } else { root + "/" }
    if abs == root {
      ftab_go(at.station, root, "")
    } else if abs.has_prefix(prefix) {
      ftab_go(at.station, root, abs.view(start_offset=prefix.length()).to_string())
    } else {
      ftab_go(at.station, abs, "")
    }
  }
  c.box(style=ftab_head, fn() {
    c.box(style=ftab_trail_box, fn() {
      let sid = c.id("files-tab/places")
      c.cursor(sid, Hand)
      if c.clicked(sid) {
        ftab.places[w.id] = None
      }
      let sb = c.box(style=ftab_step, id=sid, fn() { c.text(st.name, style=ftab_step_words) |> ignore })
      c.semantics(sb, Button, id=sid, label=st.name)
      for i, step in way {
        let (name, abs) = step
        @sf.icon(c, "chevron-right", size=ftab_chevron, color=t.p.muted) |> ignore
        let id = c.id("files-tab/step/" + abs)
        c.cursor(id, Hand)
        if c.clicked(id) {
          go_to(abs)
        }
        let last = i == way.length() - 1
        let b = c.box(style=ftab_step, id~, fn() {
          c.text(name, style=if last { ftab_step_last } else { ftab_step_words }) |> ignore
        })
        c.semantics(b, Button, id~, label=name)
      }
    })
    |> ignore
    c.box(style=ftab_actions, fn() {
      if st.anywhere &&
        files_lit_button(c, "files-tab/pin", "pin", tr(if pinned { "web-pages.drive.unpin" } else { "web-pages.drive.pin" }), pinned) {
        ftab_pin(c, src, st, here, !pinned)
      }
      c.box(style=files_views, fn() {
        for v in [("columns", "view-columns"), ("tree", "view-tree"), ("list", "list")] {
          let (way, icon) = v
          let on = view == way
          let vid = c.id("files-tab/view/" + way)
          c.cursor(vid, Hand)
          if c.clicked(vid) && !on {
            (src.call)("prefs.set", { "driveViews": { "tab": if way == "columns" { Json::null() } else { Json::string(way) } } }, fn(_) {  })
          }
          let b = c.box(style=if on { files_view_on } else { files_view_off }, id=vid, fn() {
            @sf.icon(c, icon, size=files_icon, color=if on { t.p.text } else { t.p.muted }) |> ignore
          })
          c.semantics(b, Button, id=vid, label=tr("web-pages.drive.view." + way))
        }
      })
      |> ignore
      if files_lit_button(
          c,
          "files-tab/preview",
          if previewing { "panel-close" } else { "panel-open" },
          tr(if previewing { "web-pages.files.hidePreview" } else { "web-pages.files.showPreview" }),
          previewing,
        ) {
        (src.call)("prefs.set", { "driveViews": { "tabPreview": if previewing { Json::null() } else { Json::string("shown") } } }, fn(_) {  })
      }
      if icon_button(c, "files-tab/copy", "copy", label=tr("web-pages.drive.copyPath")) {
        c.copy_text(here)
        say(c, tr("web-pages.drive.pathCopied"))
      }
      if icon_button(c, "files-tab/refresh", "refresh", label=tr("web-pages.drive.refresh")) {
        (src.call)(
          "drive.refresh",
          { "station": Json::string(at.station), "root": Json::string(root), "path": Json::string(at.path) },
          dv_act(c, tr("web-pages.drive.refreshWhat")),
        )
      }
    })
    |> ignore
  })
  |> ignore
  c.box(style=ftab_list, id=c.id("files-tab/list"), fn() {
    match view {
      "list" => files_list(c, src, at, root, at.path, 0, false, fn() {  }, compact=true)
      "tree" => files_list(c, src, at, root, at.path, 0, true, fn() {  }, compact=true)
      _ => {
        // (from the folder pinned or the home: the way down to the one open in its columns)
        let top : DriveAt = { ..at, path: "" }
        let ckey = files_owner() + at.station + "\u{1}" + root + "\u{1}"
        if !wide.files_cols.contains(ckey) {
          wide.files_cols[ckey] = at.path
        }
        let room = match c.laid_size(c.id("files-tab/list")) {
          Some((w, _)) => w
          None => c.width * ftab_share
        }
        files_columns(c, src, top, root, room, fn() {  }, halves=true)
        // a folder pressed in a column: the tab there
        match wide.files_cols.get(ckey) {
          Some(p) if p != at.path => ftab.places[w.id] = Some({ ..at, path: p })
          _ => ()
        }
      }
    }
  })
  |> ignore
  if previewing {
    files_preview_pane(c, src, st, at, root, below=true)
  }
}

///|
/// A folder pinned or let go (`drive.setRoots`), said so.
fn ftab_pin(c : @ui.Ctx, src : Source, st : DvStation, abs : String, on : Bool) -> Unit {
  let roots = st.roots.map(fn(r) { r.path }).filter(fn(p) { p != abs })
  if on {
    roots.push(abs)
  }
  (src.call)(
    "drive.setRoots",
    { "station": Json::string(st.station), "roots": Json::array(roots.map(fn(p) { Json::string(p) })) },
    fn(r) {
      match r {
        Ok(_) => say(c, fill(if on { "web-pages.drive.shared" } else { "web-pages.drive.unpinned" }, [("name", dv_name(abs))]))
        Err(_) => (dv_act(c, tr("web-pages.drive.rootsWhat")))(r)
      }
    },
  )
}

///|
/// A row's menu (DriveTab.tsx items): 添加到消息, 复制路径, 下载 (a file), pin (a folder, for one who browses everywhere).
fn ftab_menu(c : @ui.Ctx, src : Source, w : Workspace, chat : String) -> Unit {
  let (item, e, x, y) = match ftab.menu {
    Some(m) => m
    None => {
      wide_menu(c, "files-tab/menu", false, 0, [], {}, ftab_menu_w) |> ignore
      return
    }
  }
  let st = dv_stations(src, w.id).0.unwrap_or([]).iter().find_first(fn(s) { s.station == item.station })
  let anywhere = match st {
    Some(s) => s.anywhere
    None => false
  }
  let pinned = match st {
    Some(s) => s.roots.iter().any(fn(r) { r.path == item.abs })
    None => false
  }
  let entries = [
    @kit.menu_item("send", label=tr("web-pages.drive.sendToChat")),
    @kit.menu_item("copy", label=tr("web-pages.drive.copyPath")),
  ]
  if !item.dir {
    entries.push(@kit.menu_item("download", label=tr("web-pages.drive.download")))
  }
  if item.dir && anywhere {
    entries.push(@kit.menu_item("pin", label=tr(if pinned { "web-pages.drive.unpin" } else { "web-pages.drive.pin" })))
  }
  let m = wide_menu(
    c,
    "files-tab/menu",
    true,
    0,
    entries,
    { "send": "send", "copy": "copy", "download": "download", "pin": "pin" },
    ftab_menu_w,
    at=(x, y, 0.0, 0.0),
  )
  match m.chosen {
    Some("send") => ftab.sent.push((chat, item))
    Some("copy") => {
      c.copy_text(item.abs)
      say(c, tr("web-pages.drive.pathCopied"))
    }
    Some("download") => {
      say(c, fill("android-misc.drive.downloading", [("name", e.name)]))
      download_drive_file(c, src, item.station, item.root, item.path, e.name, e.mime, listed=Some((e.mtime, e.size)))
    }
    Some("pin") =>
      match st {
        Some(s) => ftab_pin(c, src, s, item.abs, !pinned)
        None => ()
      }
    _ => ()
  }
  if m.chosen is Some(_) || !m.open {
    ftab.menu = None
  }
}

///|
/// Its menu's width; the share of the window the tab is taken to have before it is laid out.
let ftab_menu_w : Double = 200.0

///|
let ftab_share : Double = 0.38

///|
/// The trail's chevrons (12).
let ftab_chevron : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let ftab_box : @ui.Style = @ui.style(w=Full, h=Full)

///|
/// Its trail and what is done to the folder (head: 4 over, 8 at its end, 6 under, 12 before).
// kept across runs: a value (no field of it changes)
let ftab_head : @ui.Style = @ui.style(row=true, w=Full, pt=S1, pr=S2, pb=S1_5, pl=S3, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let ftab_trail_box : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=SPx, align=ACenter, clip=true)

///|
/// A step of it (3 by 4 in, the option's corner); the folder shown bold in the words' ink.
// kept across runs: a value (no field of it changes)
let ftab_step : @ui.Style = @ui.style(px=S1, py=SPx, radius=Md, hovered=@ui.patch(bg=Hover))

///|
// kept across runs: a value (no field of it changes)
let ftab_step_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ftab_step_last : @ui.TextStyle = @ui.text_style(size=Xs, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ftab_actions : @ui.Style = @ui.style(row=true, gap=S1, align=ACenter)

///|
/// The rows, from edge to edge but for a little room (list: 0 by 8, 8 under).
// kept across runs: a value (no field of it changes)
let ftab_list : @ui.Style = @ui.style(w=Full, h=@sf.grow, px=S2, pb=S2, clip=true)

///|
// kept across runs: a value (no field of it changes)
let ftab_note : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, w=Full)

///|
/// A station's name over its places (group: 8 over, 10 in, 4 under, muted, medium).
// kept across runs: a value (no field of it changes)
let ftab_group : @ui.Style = @ui.style(row=true, w=Full, pt=S2, px=S2_5, pb=S1, gap=S1_5)

///|
// kept across runs: a value (no field of it changes)
let ftab_group_words : @ui.TextStyle = @ui.text_style(size=Xs, weight=Medium, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ftab_place_words : @ui.Style = @ui.style(w=@sf.grow, clip=true)
