// A chat's 文件 tab (ember web/src/pages/DriveTab.tsx, DriveTab.css.ts; mobile/StationFiles.tsx): the files of the
// workspace's stations beside a chat, to put into what is being written. That is what it is for, on every screen: a
// few files picked (a press picks a file, goes into a folder; the folder shown picked as a whole from the top of its
// list), then 添加 n at its foot puts them into the message; what a file is, seen by its row's menu (打开) or the
// preview under the list; the files themselves kept on the files' page. It starts at the chat's station's home for one who browses every folder,
// else at its one folder pinned, else at the places (each station's home and the folders it pins); the way up is a
// trail of folders over the list, the first of them the places. A list of names and sizes, the folder as a whole at
// its top: picking needs no other way of showing (the files' page has its columns and its tree); its preview under the
// list (`driveViews.tabPreview`). A row's menu
// (a right click): 添加到消息, 复制路径, 下载, pin; a row dragged onto the chat is put into the message (the composer
// takes it: tab_take_drop). A folder is gone into; what reads, plays or previews opens over the chat. Where it
// is is kept by workspace while the app runs, as the web's tab is.

///|
/// The tab: whether it is being built, where it is by workspace (None: the places; none kept: where it starts), what
/// was asked put into a chat's message (the chat, what), and a row let go off it (what, where, the frame).
priv struct FChatTab {
  mut building : Bool
  places : Map[String, DriveAt?]
  mut scope : String
  mut let_go : (Dragged, Double, Double, Int)?
  mut chat : String
  /// what is picked to go into the chat's message, in the order picked
  picked : Array[Dragged]
}

///|
// kept across runs: the tab's state (tab_reset puts it back)
let ftab : FChatTab = {
  building: false,
  places: {},
  scope: "",
  let_go: None,
  chat: "",
  picked: [],
}

///|
fn tab_reset() -> Unit {
  panel_screens.clear()
  panel_screen_pages.clear()
  ftab.building = false
  ftab.places.clear()
  ftab.scope = ""
  ftab.let_go = None
  ftab.chat = ""
  ftab.picked.clear()
}

///|
/// Whether `d` is picked.
fn ftab_picked(d : Dragged) -> Bool {
  ftab.picked.iter().any(fn(x) { x.station == d.station && x.abs == d.abs })
}

///|
/// `d` picked, or no longer.
fn ftab_pick(d : Dragged) -> Unit {
  if ftab_picked(d) {
    ftab.picked.retain(fn(x) { !(x.station == d.station && x.abs == d.abs) })
  } else {
    ftab.picked.push(d)
  }
}

///|
/// What is picked, at the tab's foot (StationFiles.tsx's 添加; 添加 n once something is): pressed, it goes into chat
/// `key`'s message (files_into: the composer takes it, by its path or as a file as the chat says), the picks let go.
fn ftab_add(c : @ui.Ctx, key : String) -> Unit {
  let n = ftab.picked.length()
  let label = if n == 0 {
    @sf.t("web-mobile.files.add")
  } else {
    @sf.t("web-mobile.files.addCount", args=[("n", n.to_string())])
  }
  if @sf.button(c, label, key="files-tab/add", tone=Primary, disabled=n == 0) {
    for d in ftab.picked {
      files_into(key, d)
    }
    ftab.picked.clear()
  }
}

///|
/// The tab into a folder of a station (its root, the path under it).
fn ftab_go(station : String, root : String, path : String) -> Unit {
  ftab.places[ftab.scope] = Some({ station, root: Some(root), path })
}

///|
/// Whether the tab is being built now (a folder gone to from what it draws goes there, not to the files' page).
pub fn tab_building() -> Bool {
  ftab.building
}

///|
/// The tab of the workspace `ws` at `at` (None: the places), as going there in it does.
pub fn tab_place_set(ws : String, at : DriveAt?) -> Unit {
  ftab.places[ws] = at
}

///|
/// Where the tab of `ws` is: None while nothing was chosen there (it starts where the chat's station does), Some(None)
/// at the places.
pub fn tab_place(ws : String) -> DriveAt?? {
  ftab.places.get(ws)
}

///|
/// The tab gone to `at` (what a folder opened from it does).
pub fn tab_go(at : DriveAt) -> Unit {
  ftab_go(at.station, at.root.unwrap_or(""), at.path)
}

///|
/// A row let go off the tab, where (x, y in the window), taken once, in the frame it was let go or the next: for the
/// chat's composer, when let go over it, to put it into the message.
pub fn tab_take_drop(c : @ui.Ctx) -> (Dragged, Double, Double)? {
  match ftab.let_go {
    Some((item, x, y, frame)) if c.frame_number() - frame <= 1 => {
      ftab.let_go = None
      Some((item, x, y))
    }
    _ => None
  }
}

///|
/// The tab for the chat `chat` (its key: what 添加 puts things into), whose station is `station`, filling the box it is
/// drawn in, one on every screen: the places or a folder (its way, its rows picked by a press, its ways of showing as
/// wide as its list leaves, its preview), 添加 at its foot; with a pointer its rows dragged onto the chat too.
pub fn files_tab(c : @ui.Ctx, src : Source, ws : String, chat : String, station : String, only_station? : Bool = false, scope? : String = ws) -> Unit {
  ftab.scope = scope
  // (what is picked is for this chat's message)
  if ftab.chat != chat {
    ftab.picked.clear()
  }
  ftab.chat = chat
  // a row let go off the tab (the desk's drag_frame lets the carried go where nothing here takes it)
  let carried = dragged()
  drag_frame(c, src, ws, outside=false)
  match carried {
    Some(i) if dragged() is None => {
      let (px, py, _) = c.pointer()
      ftab.let_go = Some((i, px, py, c.frame_number()))
    }
    _ => ()
  }
  let (list, _) = dv_stations(src, ws)
  let stations = list.unwrap_or([]).filter(fn(s) { s.drive && (!only_station || s.station == station) })
  let start : DriveAt? = match stations.iter().find_first(fn(s) { s.station == station }) {
    Some(s) if s.anywhere && s.home != "" => Some({ station, root: Some(s.home), path: "" })
    Some(s) if s.roots.length() == 1 => Some({ station, root: Some(s.roots[0].path), path: "" })
    _ => None
  }
  let place = match ftab.places.get(scope) {
    Some(p) => p
    None => start
  }
  ftab.building = true
  c.box(style=ftab_box, fn() {
    c.box(style=ftab_body, fn() {
      match place {
        None => ftab_places(c, stations)
        Some(at) if at.root is None => ftab_places(c, stations)
        Some(at) =>
          match stations.iter().find_first(fn(s) { s.station == at.station }) {
            Some(st) => ftab_folder(c, src, ws, st, at)
            None => ftab_places(c, stations)
          }
      }
    })
    |> ignore
    // (in a panel of its own, 添加 in its foot corner concentric with it: @sf.foot_corner)
    c.box(style=ftab_foot.then(@sf.foot_corner(@sf.button_height(), ftab_side, ftab_under)), fn() { ftab_add(c, chat) })
    |> ignore
  })
  |> ignore
  ftab.building = false
}

///|
/// The places (Places): each station a section (its name, 离线 by it while away), its home for one who browses every
/// folder, then its folders pinned, a row each going there (where it is under its name; what is wrong with one in red):
/// the library's parts, so its headings and rows stand in one line as a page's do.
fn ftab_places(c : @ui.Ctx, stations : Array[DvStation]) -> Unit {
  let t = @sf.theme()
  c.box(style=ftab_list, fn() {
    if stations.length() == 0 {
      @sf.page_note(c, @sf.t("web-main.rail.filesNone"))
    }
    for s in stations {
      @sf.section(c, s.name, note=if s.online { "" } else { @sf.t("web-pages.stations.offline") }, fn() {
        @sf.group(c, fn() {
          let row = fn(key : String, icon : String, name : String, where_ : String, trouble : String, root : String) {
            if @sf.link_row(c, "files-tab/place/" + s.station + "/" + key, name, note=where_, trouble~, lead=fn() {
                @sf.icon(c, icon, size=tab_icon, color=t.p.muted) |> ignore
              }) {
              ftab_go(s.station, root, "")
            }
          }
          if s.anywhere && s.home != "" {
            row("home", "server", @sf.t("web-pages.drive.home"), s.home, "", s.home)
          }
          for r in s.roots {
            let trouble = match r.state {
              "ok" => ""
              "missing" => @sf.t("web-pages.drive.root.missing")
              "not_a_directory" => @sf.t("web-pages.drive.root.notFolder")
              _ => @sf.t("web-pages.drive.root.unreadable")
            }
            row("root/" + r.path, "folder", r.name, r.path, trouble, r.path)
          }
        })
      })
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
    out.push((@sf.t("web-pages.drive.home"), h))
    at.view(start_offset=h.length()).to_string()
  } else {
    out.push(("/", "/"))
    at
  }
  for part in rest.split("/") {
    if part != "" {
      let (_, last) = out[out.length() - 1]
      out.push((part.to_string(), ftab_child(last, part.to_string())))
    }
  }
  out
}

///|
/// A folder (FolderList): the trail over it, what is done to it at the trail's end, its list as the tab shows it, the
/// preview under it.
fn ftab_folder(c : @ui.Ctx, src : Source, ws : String, st : DvStation, at : DriveAt) -> Unit {
  let t = @sf.theme()
  let root = at.root.unwrap_or("")
  let here = dv_absolute(root, at.path)
  let favs = favorites_in(src, ws, [st])
  let kept = favorite_has(favs, at.station, root, at.path)
  // (a list, whatever the files' page shows: picking from it needs no columns nor tree)
  let view = "list"
  let previewing = preview_shown(src, "tab")
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
      if c.clicked(sid) {
        ftab.places[ftab.scope] = None
      }
      let sb = c.box(style=ftab_step, id=sid, fn() { c.text(st.name, style=ftab_step_words) |> ignore })
      c.semantics(sb, Button, id=sid, label=st.name)
      for i, step in way {
        let (name, abs) = step
        @sf.icon(c, "chevron-right", size=ftab_chevron, color=t.p.muted) |> ignore
        let id = c.id("files-tab/step/" + abs)
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
      if lit_button(c, "files-tab/favorite", "star", @sf.t(if kept { "web-pages.files.unfavorite" } else { "web-pages.files.favorite" }, args=[("name", folder_name(st, at))]), kept) {
        if kept {
          favorite_remove(src, ws, at.station, root, at.path)
        } else {
          favorite_add(src, ws, { station: at.station, root, path: at.path, name: folder_name(st, at) })
        }
      }
      if lit_button(
          c,
          "files-tab/preview",
          if previewing { "panel-close" } else { "panel-open" },
          @sf.t(if previewing { "web-pages.files.hidePreview" } else { "web-pages.files.showPreview" }),
          previewing,
        ) {
        set_preview_shown(src, "tab", !previewing)
      }
      if @sf.icon_button(c, "copy", key="files-tab/copy", label=@sf.t("web-pages.drive.copyPath")) {
        copy_path(c, here)
      }
      if @sf.icon_button(c, "refresh", key="files-tab/refresh", label=@sf.t("web-pages.drive.refresh")) {
        refresh_folder(c, src, at)
      }
    })
    |> ignore
  })
  |> ignore
  // as on the files' page, but nothing here changes the files: ⏎ opens what is chosen rather than renaming it
  let b_ref : Ref[Browse?] = Ref(None)
  let held = fn(folder : String) {
    @sfbase.dv_entries(src, at.station, root, folder).unwrap_or([])
  }
  // a folder's entries as shown (for a preview to step through the pictures beside it): the one shown's
  let folder_of = fn(in_ : DriveAt) -> Array[DvEntry] {
    match b_ref.val {
      Some(b) if in_.path == at.path => b.arranged(in_.path, held(in_.path)).unwrap_or([])
      _ => []
    }
  }
  let open = fn(in_ : DriveAt, e : DvEntry) {
    open_entry(c, src, "tab", in_, e, folder_of(in_), fn(to) { ftab_go(to.station, to.root.unwrap_or(""), to.path) })
  }
  let b = browse(c, src, "tab/" + ftab.chat, "tab", view, at, false, {
    open,
    preview: open,
    go: fn(p, _) { ftab_go(at.station, root, p) },
    remove: fn(_) {  },
  })
  b_ref.val = Some(b)
  let dragged = fn(in_ : DriveAt, e : DvEntry) -> Dragged {
    let path = dv_join(in_.path, e.name)
    { station: in_.station, station_name: st.name, root, path, abs: dv_absolute(root, path), name: e.name, size: e.size, dir: e.dir }
  }
  // a press: a folder gone into, a file picked (or no longer)
  let pressed = fn(in_ : DriveAt, e : DvEntry) {
    if e.dir {
      ftab_go(at.station, root, dv_join(in_.path, e.name))
    } else {
      ftab_pick(dragged(in_, e))
    }
  }
  let row_of = fn(in_ : DriveAt, e : DvEntry) -> RowProps {
    {
      items: fn() {
        let abs = dv_absolute(root, dv_join(in_.path, e.name))
        let out : Array[@sf.MenuItem?] = []
        // (a file is opened from here: a press picks it)
        if !e.dir {
          out.push(Some(@sf.menu_item_of(@sf.t("web-pages.drive.open"), icon="external", fn() { open(in_, e) })))
        }
        out.push(Some(@sf.menu_item_of(@sf.t("web-pages.drive.sendToChat"), icon="send", fn() { files_into(ftab.chat, dragged(in_, e)) })))
        out.push(Some(@sf.menu_item_of(@sf.t("web-pages.drive.copyPath"), icon="copy", fn() { copy_path(c, abs) })))
        if !e.dir {
          out.push(Some(@sf.menu_item_of(@sf.t("web-pages.drive.download"), icon="download", fn() { save_entry(c, src, in_, e) })))
        }
        if e.dir {
          let path = dv_join(in_.path, e.name)
          let saved = favorite_has(favs, at.station, root, path)
          out.push(Some(@sf.menu_item_of(@sf.t(if saved { "web-pages.files.unfavorite" } else { "web-pages.files.favorite" }, args=[("name", e.name)]), icon="star", fn() {
            if saved {
              favorite_remove(src, ws, at.station, root, path)
            } else {
              favorite_add(src, ws, { station: at.station, root, path, name: e.name })
            }
          })))
        }
        out
      },
      open: fn() { pressed(in_, e) },
      press: fn() { pressed(in_, e) },
      menu: fn() {  },
      chosen: !e.dir && ftab_picked(dragged(in_, e)),
      renaming: false,
      rename: fn(_) {  },
      drop: None,
    }
  }
  let shown : Shown = {
    b,
    row_of,
    drop_on: fn(_) { None },
    clear: fn() { b.clear(c, src) },
    write: false,
    transfers: false,
  }
  let lid = c.id("files-tab/list")
  // (a ground round its rows: a press there chooses none)
  c.cursor(lid, Arrow)
  c.box(style=ftab_list, id=lid, fn() {
    {
      let (value, error) = drive_folder(src, at.station, root, at.path)
        match (value, error) {
          (None, Some(e)) =>
            c.box(style=ftab_problem, fn() {
              c.text(e, style=tab_trouble) |> ignore
              if @sf.button(c, @sf.t("web-pages.drive.retry"), key="files-tab/retry", tone=Ghost, icon="retry") {
                refresh_folder(c, src, at)
              }
            })
            |> ignore
          (None, None) => @sf.waiting(c, fn() { rows_sample(c, at, shown, 5, compact=true) })
          _ =>
            match b.arranged(at.path, held(at.path)) {
              None => @sf.waiting(c, fn() { rows_sample(c, at, shown, 5, compact=true) })
              Some([]) => c.text(@sf.t("web-pages.drive.emptyFolder"), style=ftab_note) |> ignore
              Some(_) =>
                rows_view(c, src, "files-tab/rows/" + at.station + "/" + root + "/" + at.path, at, shown, false, compact=true, head=fn() {
                  // the folder shown, picked as a whole
                  let whole : Dragged = {
                    station: at.station,
                    station_name: st.name,
                    root,
                    path: at.path,
                    abs: here,
                    name: if at.path == "" { way[way.length() - 1].0 } else { dv_name(at.path) },
                    size: 0.0,
                    dir: true,
                  }
                  // (the folder as a whole, where it is under it: the library's row of choices, as the places' rows)
                  if @sf.choice_row(c, "files-tab/whole", ftab_picked(whole), @sf.t("web-mobile.files.wholeFolder"), note=here, lead=fn() {
                      @sf.icon(c, "folder", size=tab_icon, color=t.p.muted) |> ignore
                    }) {
                    ftab_pick(whole)
                  }
                })
            }
        }
    }
    // a press where there is no row: nothing chosen
    if c.clicked(lid) && !row_took(c) {
      b.clear(c, src)
    }
  })
  |> ignore
  if previewing {
    // (what was picked last in the folder shown: what a pick is, seen before it goes into the message)
    let here_picked = ftab.picked.filter(fn(d) { d.station == at.station && !d.dir && dv_parent(d.path) == at.path })
    let p : Previewed = match here_picked.last() {
      Some(d) =>
        match held(at.path).iter().find_first(fn(e) { e.name == d.name }) {
          Some(e) => One(at, e)
          None => Nothing
        }
      None => Nothing
    }
    drive_pane(
      c,
      src,
      p,
      st.name,
      fn() {
        match p {
          One(pat, e) => open(pat, e)
          _ => ()
        }
      },
      fn() {
        match p {
          One(pat, e) => save_entry(c, src, pat, e)
          _ => ()
        }
      },
      fn(abs) { copy_path(c, abs) },
      below=true,
    )
  }
}

///|
/// The trail's chevrons (12).
let ftab_chevron : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let ftab_box : @ui.Style = @ui.css("w=Full h=Full")

///|
/// What it shows, over its foot.
// kept across runs: a value (no field of it changes)
let ftab_body : @ui.Style = @ui.style(w=Full, h=@sf.grow)

///|
/// Its trail and what is done to the folder (head: 4 over, 8 at its end, 6 under, 12 before).
// kept across runs: a value (no field of it changes)
let ftab_head : @ui.Style = @ui.css("row w=Full pt=S1 pr=S2 pb=S1_5 pl=S3 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ftab_trail_box : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=SPx, align=ACenter, clip=true)

///|
/// A step of it (3 by 4 in, the option's corner); the folder shown bold in the words' ink.
// kept across runs: a value (no field of it changes)
let ftab_step : @ui.Style = @ui.css("px=S1 py=SPx radius=Md hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let ftab_step_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ftab_step_last : @ui.TextStyle = @ui.text_style(size=Meta, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ftab_actions : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
/// The rows, from edge to edge but for a little room (list: 0 by 8, 8 under).
// kept across runs: a value (no field of it changes)
let ftab_list : @ui.Style = @ui.style(w=Full, h=@sf.grow, px=S2, pb=S2, clip=true)

///|
// kept across runs: a value (no field of it changes)
let ftab_note : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
/// Why the folder could not be read, and 重试.
// kept across runs: a value (no field of it changes)
let ftab_problem : @ui.Style = @ui.css("w=Full p=S3 gap=S2_5 align=AStart")

///|
/// Where `name` goes in the folder `folder`, as an absolute path (useDrive.ts childOf).
fn ftab_child(folder : String, name : String) -> String {
  if folder.has_suffix("/") {
    folder + name
  } else {
    folder + "/" + name
  }
}

///|
/// A button of the tab's head lit while what it says is so (pin, the preview): the accent's ink then.
fn lit_button(c : @ui.Ctx, key : String, icon : String, label : String, on : Bool) -> Bool {
  let lit = @sf.theme().p.accent
  @sf.icon_button(c, icon, key~, on~, ink?=if on { Some(lit) } else { None }, label~)
}

///|
/// A row's mark (16).
let tab_icon : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let tab_trouble : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, wrap=false)

///|
/// 添加 at its foot's end.
// kept across runs: a value (no field of it changes)
let ftab_foot : @ui.Style = @ui.css("row w=Full px=S5 pt=S2 justify=JEnd")

///|
/// 添加's room at its sides and under it, standing alone.
let ftab_side : Double = 20.0

///|
let ftab_under : Double = 16.0
