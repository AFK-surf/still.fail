// The files' page in the wide frame, as the web's (ember web/src/pages/Files.tsx, FilesNav.tsx, Drive.tsx FolderView,
// DriveViews.tsx; drive/favorites.ts): the sidebar as Finder's (Pin 文件夹 in its band; 个人收藏, the person's own
// folders of any station, kept among the prefs; each station with a drive, opened to its places, how full its disk is;
// 团队共享, the folders the stations pin for everyone); the folder beside it under a bar of what can be done to it (its
// three ways: columns, a tree, a list; upload, a new folder, refresh, 收藏, pin; its view's menu), its station and where
// in it over its name and what it holds. A row is chosen by a click and opened by a double click; in columns a folder
// pressed opens beside its column.

///|
/// Where a station's drive starts for its viewer: its home for one who browses everywhere, else the first folder it
/// pins.
fn files_start(s : DvStation) -> String? {
  if s.anywhere && s.home != "" {
    Some(s.home)
  } else {
    match s.roots.get(0) {
      Some(r) => Some(r.path)
      None => None
    }
  }
}

///|
/// A folder opened in the pane (the stack's page above the place, in place of what was open).
fn files_go(at : DriveAt) -> Unit {
  if ftab.building {
    ftab_go(at.station, at.root.unwrap_or(""), at.path)
    return
  }
  while app.nav.depth() > 1 {
    if !app.nav.pop() {
      break
    }
  }
  app.nav.push(Drive(at))
}

// ── the sidebar (FilesNav) ──────────────────────────────────────────────

///|
/// The files' sidebar: Pin 文件夹; 个人收藏; each station with a drive, opened to its places; 团队共享.
fn files_side(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let (list, error) = dv_stations(src, w.id)
  let here = match app.nav.top() {
    Drive(at) => Some(at)
    _ => None
  }
  let lit = fn(station : String, root : String, path : String) {
    match here {
      Some(h) => h.station == station && h.root == Some(root) && h.path == path
      None => false
    }
  }
  let views = stations_listed(src, w)
  c.box(style=place_side, fn() {
    @sfdesk.side_top(c)
    c.box(style=place_list, fn() {
      let stations = match list {
        Some(l) => l.filter(fn(s) { s.drive })
        None => []
      }
      // Pin 文件夹: on a station whose viewer may pin (one who browses everywhere), its picker
      let pins = stations.filter(fn(s) { s.anywhere && s.online })
      if pins.length() > 0 {
        place_add(c, "files/pin", tr("web-pages.drive.addRoot"), Some(fn() {
          match pins {
            [s] => dv_open_picker(c, s.station, s.roots.map(fn(r) { r.path }))
            _ => dv_open(c, LendOn(pins))
          }
        }))
      }
      match (list, error) {
        (None, Some(e)) => c.text(e, style=place_trouble) |> ignore
        (None, None) => @sfdesk.side_breathing(c)
        _ => ()
      }
      if list is Some(_) && stations.length() == 0 {
        c.box(style=files_note_box, fn() { c.text(tr("web-main.rail.filesNone"), style=place_meta) |> ignore })
        |> ignore
      }
      // what is dragged moved on or let go (the sidebar's drops as the folder's)
      fdrag_frame(c, src, w)
      // 个人收藏 (a folder dragged onto it kept there)
      let favs = @sfdesk.favorites(src, w.id)
      let kid = c.id("files/keep")
      let keeping = fdrag_target(c, kid, "keep", None, "", true, true, 0, outside=false) is Some(_)
      c.box(style=if keeping { fdrag_keep_on } else { fdrag_keep }, id=kid, fn() {
      @sfdesk.nav_heading(c, tr("web-pages.files.favorites"))
      if favs.length() == 0 {
        c.box(style=files_hint, fn() {
          @sf.icon(c, "star", size=files_icon, color=t.p.subtle) |> ignore
          c.text(tr("web-pages.files.favoritesHint"), style=place_meta) |> ignore
        })
        |> ignore
      }
      for f in favs {
        let s = stations.iter().find_first(fn(x) { x.station == f.station })
        match s {
          Some(st) => {
            let rid = c.id("files/unfav/" + f.station + "/" + f.root + "/" + f.path)
            let into : DriveAt = { station: f.station, root: Some(f.root), path: f.path }
            fdrag_side_row(c, "fav/" + f.station + "/" + f.root + "/" + f.path, into, f.name, files_writes(src, w, st), st.transfers, fn() {
              if c.clicked(rid) {
                @sfdesk.favorite_remove(src, w.id, f.station, f.root, f.path)
              } else if @sfdesk.nav_row(c, "files/fav/" + f.station + "/" + f.root + "/" + f.path, lit(f.station, f.root, f.path), fn() {
                  @sf.icon(c, "folder", size=files_icon, color=t.p.muted) |> ignore
                  c.text(f.name, style=place_name) |> ignore
                  c.text(st.name, style=place_meta) |> ignore
                  let ub = c.box(style=files_unfav, id=rid, fn() {
                    @sf.icon(c, "close", size=files_icon, color=t.p.subtle) |> ignore
                  })
                  c.semantics(ub, Button, id=rid, label=fill("web-pages.files.unfavorite", [("name", f.name)]))
                }) {
                files_go({ station: f.station, root: Some(f.root), path: f.path })
              }
            })
          }
          None => ()
        }
      }
      })
      |> ignore
      // Station: each, opened to its places
      if stations.length() > 0 {
        @sfdesk.nav_heading(c, "Station")
      }
      // this machine's first (the station this Mac is), then as the workspace lists them
      let here_station = files_this_machine()
      let ordered = stations.filter(fn(s) { s.station == here_station }) + stations.filter(fn(s) { s.station != here_station })
      for s in ordered {
        let view = views.iter().find_first(fn(v) { text(Some(v), "station") == s.station })
        let open = wide.files_open.contains("station/" + s.station)
        let start = files_start(s)
        let did = c.id("files/station-open/" + s.station)
        if c.clicked(did) {
          if open {
            wide.files_open.remove("station/" + s.station)
          } else {
            wide.files_open["station/" + s.station] = true
          }
        } else {
          let row = fn() {
            if @sfdesk.nav_row(
                c,
                "files/station/" + s.station,
                match start {
                  Some(r) => lit(s.station, r, "")
                  None => false
                },
                fn() {
                  let d = c.box(style=files_disclosure, id=did, fn() {
                    @sf.icon(c, if open { "chevron-down" } else { "chevron-right" }, size=files_icon, color=t.p.subtle)
                    |> ignore
                  })
                  c.semantics(d, Button, id=did, label=fill(if open { "web-pages.files.collapse" } else { "web-pages.files.expand" }, [("name", s.name)]))
                  station_or_server(c, text(view, "emoji"), text(view, "icon"), @sf.row_icon, t.p.muted)
                  c.text(s.name, style=if s.online { place_name } else { place_name_away }) |> ignore
                  if s.station == here_station {
                    c.box(style=files_here_chip, fn() { c.text(tr("web-pages.files.thisMachine"), style=files_here_words) |> ignore })
                    |> ignore
                  }
                  if s.online {
                    files_disk(c, field(field(view, "overview"), "disk"))
                  } else {
                    c.text(tr("web-pages.stations.offline"), style=place_meta) |> ignore
                  }
                },
              ) {
              match start {
                Some(r) => files_go({ station: s.station, root: Some(r), path: "" })
                None => ()
              }
            }
          }
          match start {
            Some(r) =>
              fdrag_side_row(c, "station/" + s.station, { station: s.station, root: Some(r), path: "" }, s.name, files_writes(src, w, s), s.transfers, row)
            None => row()
          }
        }
        if open {
          if s.anywhere && !wide.files_places.contains(s.station) {
            c.after_build("files-places/" + s.station, fn() {
              if !wide.files_open.contains("asked/" + s.station) {
                wide.files_open["asked/" + s.station] = true
                files_places(src, s)
              }
            })
          }
          let places : Array[(String, String, Bool)] = if s.anywhere {
            match wide.files_places.get(s.station) {
              Some(ps) => ps.map(fn(p) { (text(Some(p), "name"), text(Some(p), "path"), flag(Some(p), "disk")) })
              None => []
            }
          } else {
            s.roots.map(fn(r) { (r.name, r.path, false) })
          }
          if s.anywhere && wide.files_places.get(s.station) is None {
            c.box(style=files_note_box, fn() { c.text(tr("web-pages.files.reading"), style=place_meta) |> ignore })
            |> ignore
          }
          for p in places {
            let (name, path, disk) = p
            c.box(style=files_place_in, fn() {
              fdrag_side_row(c, "place/" + s.station + "/" + path, { station: s.station, root: Some(path), path: "" }, name, files_writes(src, w, s), s.transfers, fn() {
                if @sfdesk.nav_row(c, "files/place/" + s.station + "/" + path, lit(s.station, path, ""), fn() {
                    @sf.icon(c, if disk { "disk" } else { "folder" }, size=files_icon, color=t.p.muted) |> ignore
                    c.text(name, style=place_name) |> ignore
                  }) {
                  files_go({ station: s.station, root: Some(path), path: "" })
                }
              })
            })
            |> ignore
          }
        }
      }
      // 团队共享: the folders each station pins
      let pinned : Array[(DvStation, DvRoot)] = []
      for s in stations {
        for r in s.roots {
          pinned.push((s, r))
        }
      }
      if pinned.length() > 0 {
        @sfdesk.nav_heading(c, tr("web-pages.files.shared"))
      }
      for x in pinned {
        let (s, r) = x
        let name = if r.name != "" { r.name } else { dv_name(r.path) }
        fdrag_side_row(c, "shared/" + s.station + "/" + r.path, { station: s.station, root: Some(r.path), path: "" }, name, files_writes(src, w, s), s.transfers, fn() {
          if @sfdesk.nav_row(c, "files/shared/" + s.station + "/" + r.path, lit(s.station, r.path, ""), fn() {
              @sf.icon(c, "pin", size=files_icon, color=t.p.muted) |> ignore
              c.text(name, style=place_name) |> ignore
              c.text(s.name, style=place_meta) |> ignore
            }) {
            files_go({ station: s.station, root: Some(r.path), path: "" })
          }
        })
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A station's places (`drive.folders` with no path: its home, the home's own folders, its disks, as its drive offers
/// them), read as its row opens, once.
fn files_places(src : Source, s : DvStation) -> Unit {
  (src.call)("drive.folders", { "station": Json::string(s.station), "path": Json::null() }, fn(r) {
    match r {
      Ok(v) => wide.files_places[s.station] = items(Some(v), "places")
      Err(_) => wide.files_places[s.station] = []
    }
  })
}

///|
/// How full a station's disk is (FilesNav DiskBar): a short bar, amber past 90%.
fn files_disk(c : @ui.Ctx, disk : Json?) -> Unit {
  let total = number(disk, "totalBytes")
  if total <= 0.0 {
    return
  }
  let free = number(disk, "freeBytes")
  let used = 1.0 - free / total
  let part = (if used >= files_disk_full { files_disk_warn } else { files_disk_used }).then(
    @ui.style(w=Fixed(files_disk_w * used)),
  )
  let bar = c.box(style=files_disk_bar, fn() {
    c.box(style=part, fn() {
      ()
    })
    |> ignore
  })
  // what it says (FilesNav.tsx DiskBar's label): what is left, in GB, and how much is used
  let gb = free / 1.0e9
  let left = if free >= 1.0e11 { gb.round().to_int().to_string() } else { @sf.to_fixed(gb, 1) }
  c.semantics(
    bar,
    Image,
    label=fill("web-pages.files.diskLeft", [("free", left + " GB"), ("percent", (used * 100.0).round().to_int().to_string())]),
  )
}

// ── a folder (FolderView) ───────────────────────────────────────────────

///|
/// The files' place with no folder open: the first station's start.
fn files_landing(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let (list, _) = dv_stations(src, w.id)
  let first = match list {
    Some(l) => l.iter().find_first(fn(s) { s.drive && files_start(s) is Some(_) })
    None => None
  }
  match first {
    Some(s) => wide_folder(c, src, w, { station: s.station, root: files_start(s), path: "" })
    None => files_page(c, src, w)
  }
}

// ── a folder (FolderView) ───────────────────────────────────────────────

///|
/// The files' page at a folder: the desk's shell (src/sfdesk/files.mbt: its tabs, the core's), what is the app's own
/// until it is the desk's given to it (the sidebar's way there, ⌘⇧G, 传输, a side's head, what is dragged). The folder
/// in front is the stack's top (what the sidebar and opening a folder move).
fn wide_folder(c : @ui.Ctx, src : Source, w : Workspace, at : DriveAt) -> Unit {
  let (list, _) = dv_stations(src, w.id)
  let stations = list.unwrap_or([])
  let s = stations.iter().find_first(fn(x) { x.station == at.station })
  let st = match s {
    Some(v) if v.drive => v
    _ => {
      drive_page(c, src, w, at)
      return
    }
  }
  let root = match at.root {
    Some(r) => r
    None =>
      match files_start(st) {
        Some(r) => r
        None => {
          drive_page(c, src, w, at)
          return
        }
      }
  }
  let here : DriveAt = { station: at.station, root: Some(root), path: at.path }
  dv.building = dv_page_of(Some(here))
  // what is dragged moved on or let go; the files picked to go up
  fdrag_frame(c, src, w)
  dv_take_picked(src, here, [])
  let room = c.width - @sfdesk.rail_w - (if @sfdesk.wide.folded { 0.0 } else { @sfdesk.wide.side_w })
  @sfdesk.files_shell(c, src, w.id, stations, here, room, {
    go: fn(to, _) { files_go(to) },
    head: fn(c, f, split_on, front_it) { files_side_head(c, src, w, stations, f, split_on, front_it) },
    go_to: fgo_open,
    transfers: fn(c) { files_transfers(c, src, w.id) },
    manage: fn(p) { dv_open(c, View(p, dv_rights(src, w.id, Some(st)).manage && p.path == "")) },
    over: fn(c, page) {
      dv_sheets(c, src, w, dv_page_of(Some(here)))
      files_goto(c, src, stations, here)
      files_clash_dialog(c)
      fdrag_ghost(c, page)
    },
  })
}

// ── going somewhere (FilesGo.tsx) ───────────────────────────────────────

///|
/// ⌘⇧G's dialog (open, what is typed, the line chosen, the folders read where the last part is typed, which were
/// asked) and the station's button whose menu is open.
priv struct FGo {
  mut open : Bool
  field : @ui.Field
  mut typed : String
  mut at : Int
  mut folders : (String, String, Array[String])?
  mut asked : String
  mut switching : Int
  mut transfers : Bool
}

///|
let fgo : FGo = {
  open: false,
  field: @ui.Field::new(),
  typed: "",
  at: 0,
  folders: None,
  asked: "",
  switching: 0,
  transfers: false,
}

///|
fn fgo_reset() -> Unit {
  fgo.open = false
  fgo.field.set("")
  fgo.typed = ""
  fgo.at = 0
  fgo.folders = None
  fgo.asked = ""
  fgo.switching = 0
  fgo.transfers = false
}

///|
fn fgo_open() -> Unit {
  fgo_reset()
  fgo.open = true
}

///|
/// A child of a folder on a station (its own separator: Windows' backslash, else a slash).
fn fgo_child(folder : String, name : String) -> String {
  let sep = if folder.contains("\\") && !folder.contains("/") { "\\" } else { "/" }
  if folder.has_suffix(sep) {
    folder + name
  } else {
    folder + sep + name
  }
}

///|
/// Whether `p` starts as a drive's letter does (`C:\`, `C:/`).
fn fgo_lettered(p : String) -> Bool {
  if p.length() < 3 {
    return false
  }
  let ch = p.at(0).to_int()
  let letter = (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122)
  letter && p.at(1).to_int() == 58 && (p.at(2).to_int() == 47 || p.at(2).to_int() == 92)
}

///|
/// What is typed, worked out (drive/goto.ts resolveTyped): the station (named before a colon, its name or its start;
/// else the one shown), the folder it names (`~` its home, no slash in front: under the folder shown, another
/// station's under its home), the folder its last part is in and what is typed of it.
fn fgo_resolve(typed : String, stations : Array[DvStation], from : DriveAt) -> (String, String, String, String)? {
  let colon = match typed.find(":") {
    Some(i) => i
    None => -1
  }
  let named = if colon > 0 && !fgo_lettered(typed) {
    Some(lower(typed.view(end_offset=colon).to_string().trim(chars=" ").to_string()))
  } else {
    None
  }
  let s = match named {
    None => stations.iter().find_first(fn(v) { v.station == from.station })
    Some(n) =>
      match stations.iter().find_first(fn(v) { lower(v.name) == n }) {
        Some(v) => Some(v)
        None => stations.iter().find_first(fn(v) { lower(v.name).has_prefix(n) })
      }
  }
  let s = match s {
    Some(v) => v
    None => return None
  }
  let rest = (if named is None { typed } else { typed.view(start_offset=colon + 1).to_string() }).trim(chars=" ").to_string()
  let home = s.home
  let from_abs = match from.root {
    Some(r) => if from.path == "" { r } else { r + "/" + from.path }
    None => ""
  }
  let base = if rest == "" || rest == "~" {
    home
  } else if rest.has_prefix("~/") {
    if home != "" { fgo_child(home, rest.view(start_offset=2).to_string()) } else { "" }
  } else if rest.has_prefix("/") || fgo_lettered(rest) {
    rest
  } else if s.station == from.station && from_abs != "" {
    fgo_child(from_abs, rest)
  } else if home != "" {
    fgo_child(home, rest)
  } else {
    ""
  }
  if base == "" {
    return None
  }
  let ends = rest == "" || rest == "~" || rest.has_suffix("/") || rest.has_suffix("\\")
  let mut abs = base
  if ends && abs.length() > 1 {
    while abs.length() > 1 && (abs.has_suffix("/") || abs.has_suffix("\\")) {
      abs = abs.view(end_offset=abs.length() - 1).to_string()
    }
  }
  let cut = {
    let mut k = -1
    for i in 0..<abs.length() {
      let ch = abs.at(i).to_int()
      if ch == 47 || ch == 92 {
        k = i
      }
    }
    k
  }
  let parent = if ends { abs } else if cut <= 0 { "/" } else { abs.view(end_offset=cut).to_string() }
  let partial = if ends { "" } else { abs.view(start_offset=cut + 1).to_string() }
  Some((s.station, abs, parent, partial))
}

///|
/// A folder opened by its absolute path on `station`: as a root for one who browses everywhere, else under the folder
/// it pins that holds it.
fn fgo_go(stations : Array[DvStation], station : String, abs : String) -> Unit {
  match stations.iter().find_first(fn(s) { s.station == station }) {
    Some(s) if s.anywhere => files_go({ station, root: Some(abs), path: "" })
    Some(s) =>
      match s.roots.iter().find_first(fn(r) { abs == r.path || abs.has_prefix(r.path + "/") }) {
        Some(r) =>
          files_go({
            station,
            root: Some(r.path),
            path: if abs == r.path { "" } else { abs.view(start_offset=r.path.length() + 1).to_string() },
          })
        None => ()
      }
    None => ()
  }
}

///|
/// ⌘⇧G (FilesGo.tsx GoTo): a field (`mba:~/Projects`), where it goes under it; the stations while their name is typed,
/// then the folders whose name starts with what is typed of the last part (Tab completes the one chosen, ↑ / ↓ choose,
/// Enter goes); Esc closes it.
fn files_goto(c : @ui.Ctx, src : Source, stations : Array[DvStation], here : DriveAt) -> Unit {
  let t = @sf.theme()
  let typed = fgo.typed
  let resolved = fgo_resolve(typed, stations, here)
  let named = match resolved {
    Some((st, _, _, _)) => stations.iter().find_first(fn(s) { s.station == st })
    None => None
  }
  // the folders where the last part is typed, read as the way to it changes (after the frame's build)
  match (resolved, named) {
    (Some((st, _, parent, _)), Some(n)) if fgo.open && n.anywhere => {
      let key = st + "\n" + parent
      if fgo.asked != key {
        c.after_build("files-goto/folders", fn() {
          if fgo.asked != key {
            fgo.asked = key
            (src.call)("drive.folders", { "station": Json::string(st), "path": Json::string(parent) }, fn(r) {
              if fgo.asked == key {
                fgo.folders = Some((st, parent, match r {
                  Ok(v) => items(Some(v), "entries").map(fn(e) { text(Some(e), "name") })
                  Err(_) => []
                }))
              }
            })
          }
        })
      }
    }
    _ => ()
  }
  // the lines: (what it says, what Tab puts in, where it goes)
  let rows : Array[(String, String, (String, String)?)] = []
  if typed != "" && !typed.contains(":") && !typed.has_prefix("/") && !typed.has_prefix("~") {
    for s in stations {
      if lower(s.name).has_prefix(lower(typed)) {
        rows.push((s.name, lower(s.name) + ":~/", if s.home != "" { Some((s.station, s.home)) } else { None }))
      }
    }
  }
  match (resolved, named, fgo.folders) {
    (Some((st, _, parent, partial)), Some(n), Some((fs, fp, names))) if fs == st && fp == parent => {
      let prefix = if st == here.station && !typed.contains(":") { "" } else { lower(n.name) + ":" }
      let mut k = 0
      for name in names {
        if k < fgo_most && !name.has_prefix(".") && lower(name).has_prefix(lower(partial)) {
          let abs = fgo_child(parent, name)
          rows.push((n.name + " › " + abs, prefix + abs + "/", Some((st, abs))))
          k += 1
        }
      }
    }
    _ => ()
  }
  if fgo.at >= rows.length() {
    fgo.at = dmax(0.0, (rows.length() - 1).to_double()).to_int()
  }
  if fgo.open {
    if c.key_pressed(@ui.key_code_down, in_field=true) && fgo.at < rows.length() - 1 {
      fgo.at += 1
    }
    if c.key_pressed(@ui.key_code_up, in_field=true) && fgo.at > 0 {
      fgo.at -= 1
    }
    if c.key_pressed(@ui.key_tab, in_field=true) {
      match rows.get(fgo.at) {
        Some((_, complete, _)) => {
          fgo.field.set(complete)
          fgo.typed = complete
          fgo.at = 0
        }
        None => ()
      }
    }
  }
  let go = fn(target : (String, String)?) {
    match target {
      Some((st, abs)) => {
        fgo.open = false
        c.blur()
        fgo_go(stations, st, abs)
      }
      None => ()
    }
  }
  let d = @sf.dialog(
    c,
    "files-goto",
    fgo.open,
    tr("web-pages.files.goTo"),
    description=tr("web-pages.files.goToNote"),
    w=dmin(fgo_w, c.width - fgo_margin),
    close_label=tr("common.close"),
    fn() {
      c.box(style=fgo_field_box, fn() {
        let res = c.editor(
          "files-goto/field",
          placeholder=tr("web-pages.files.goToPlaceholder"),
          font_size=fgo_font,
          line=fgo_line,
          max_lines=1,
          plain=true,
          color=t.p.text,
          placeholder_color=t.p.subtle,
          caret_color=t.p.accent,
          enter_sends=true,
          field=fgo.field,
        )
        if !res.focused && !c.field_focused() {
          c.focus_editor("files-goto/field")
        }
        if res.text != fgo.typed {
          fgo.typed = res.text
          fgo.at = 0
        }
        match res.submitted {
          Some(words) => {
            fgo.field.set(words)
            let chosen = rows.get(fgo.at)
            match (resolved, chosen) {
              (Some((_, _, _, partial)), Some((_, _, target))) if partial != "" => go(target)
              (Some((st, abs, _, _)), _) => go(Some((st, abs)))
              (None, Some((_, _, target))) => go(target)
              _ => ()
            }
          }
          None => ()
        }
      })
      |> ignore
      match (resolved, named) {
        (Some((_, abs, _, _)), Some(n)) => c.text(n.name + " › " + abs, style=fgo_where) |> ignore
        _ => ()
      }
      for i, r in rows {
        let (label, _, target) = r
        let id = c.id("files-goto/row/" + label)
        c.cursor(id, Hand)
        if c.clicked(id) {
          go(target)
        }
        if c.hovered(id) {
          fgo.at = i
        }
        c.box(style=if i == fgo.at { fgo_row_on } else { fgo_row }, id~, fn() {
          @sf.icon(c, "folder", size=files_icon, color=t.p.muted) |> ignore
          c.text(label, style=fgo_row_words) |> ignore
          if i == fgo.at {
            c.text("Tab", style=fgo_key) |> ignore
          }
        })
        |> ignore
      }
    },
  )
  if !d {
    fgo.open = false
  }
}

///|
/// A station's button's menu (StationSwitch): the workspace's stations with a drive (the one shown checked; one away
/// not to be picked); picked, the same folder there when it has one, else its home (said so).
fn files_switch_menu(c : @ui.Ctx, src : Source, stations : Array[DvStation], chip : Int, at : DriveAt) -> Unit {
  let open = fgo.switching == chip
  let entries = stations
    .filter(fn(s) { s.drive })
    .map(fn(s) { @kit.menu_radio(s.station, s.station == at.station, label=s.name, disabled=!s.online) })
  let m = @sf.menu(c, "files/switch/" + chip.to_string(), open, chip, entries, {}, fgo_menu_w)
  if open && !m.open {
    fgo.switching = 0
  }
  match m.chosen {
    Some(st) if st != at.station => {
      fgo.switching = 0
      match stations.iter().find_first(fn(s) { s.station == st }) {
        Some(s) => {
          let abs = match at.root {
            Some(r) => if at.path == "" { r } else { r + "/" + at.path }
            None => ""
          }
          if s.anywhere && s.home != "" {
            (src.call)("drive.folders", { "station": Json::string(st), "path": Json::string(abs) }, fn(r) {
              match r {
                Ok(v) if !flag(Some(v), "unreadable") => files_go({ station: st, root: Some(abs), path: "" })
                _ => {
                  say(c, fill("web-pages.files.notThere", [("name", s.name)]))
                  files_go({ station: st, root: Some(s.home), path: "" })
                }
              }
            })
          } else {
            match s.roots.get(0) {
              Some(r) => {
                say(c, fill("web-pages.files.notThere", [("name", s.name)]))
                files_go({ station: st, root: Some(r.path), path: "" })
              }
              None => ()
            }
          }
        }
        None => ()
      }
    }
    _ => ()
  }
}

///|
/// ⌘⇧G's: at most this many folders listed; its dialog 480 wide (16 in from the window's sides at least); its field's
/// words 14 on 20; the stations' menu 220.
let fgo_most : Int = 8

///|
let fgo_w : Double = 480.0

///|
let fgo_margin : Double = 32.0

///|
let fgo_font : Double = 14.0

///|
let fgo_line : Double = 20.0

///|
let fgo_menu_w : Double = 220.0

///|
// kept across runs: a value (no field of it changes)
let fgo_note : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let fgo_field_box : @ui.Style = @ui.style(row=true, w=Full, h=S9, px=S3, align=ACenter, radius=Lg, bg=Tint)

///|
// kept across runs: a value (no field of it changes)
let fgo_where : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let fgo_row : @ui.Style = @ui.style(row=true, w=Full, h=S8, px=S2, gap=S2, align=ACenter, radius=Lg)

///|
// kept across runs: a value (no field of it changes)
let fgo_row_on : @ui.Style = fgo_row.then(@ui.style(bg=Tint))

///|
// kept across runs: a value (no field of it changes)
let fgo_row_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let fgo_key : @ui.TextStyle = @ui.text_style(size=Xs, color=Subtle, wrap=false)

///|
/// A side's head: its station and where in it, its name and what it holds. `front_it` puts the side in front, said
/// first by whatever is pressed in it.
fn files_side_head(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  stations : Array[DvStation],
  f : @sfdesk.FolderOf,
  split_on : Bool,
  front_it : () -> Unit,
) -> Unit {
  let t = @sf.theme()
  let at = f.at
  let st = f.st
  let root = at.root.unwrap_or("")
  let topic = (src.topic)("drive", {
    "station": Json::string(at.station),
    "root": Json::string(root),
    "path": Json::string(at.path),
  })
  let (name, _) = @sfdesk.pane_parts(at, stations)
  // where it is: its station, then the way down to it (its root, then each folder above it)
  c.box(style=if split_on { files_head_half } else { files_head }, fn() {
    c.box(style=files_crumbs, fn() {
      // its station's button (FilesGo.tsx StationSwitch): the workspace's stations, the same folder there or its home
      let chip = c.id("files/station-switch/" + at.station + "/" + root + "/" + at.path)
      c.cursor(chip, Hand)
      if c.clicked(chip) {
        front_it()
        fgo.switching = if fgo.switching == chip { 0 } else { chip }
      }
      let b = c.box(style=files_station_chip, id=chip, fn() {
        let view = stations_listed(src, w).iter().find_first(fn(v) { text(Some(v), "station") == at.station })
        station_or_server(c, text(view, "emoji"), text(view, "icon"), files_icon, t.p.muted)
        c.text(st.name, style=files_chip_words) |> ignore
        @sf.icon(c, "chevron-down", size=files_close_icon, color=t.p.muted) |> ignore
      })
      c.semantics(b, Button, id=chip, label=tr("web-pages.files.switchStation"))
      files_switch_menu(c, src, stations, chip, at)
      let parts = if at.path == "" { [] } else { at.path.split("/").map(fn(p) { p.to_string() }).collect() }
      let (root_name, _) = @sfdesk.pane_parts({ ..at, path: "" }, stations)
      let crumbs : Array[(String, String)] = if at.path == "" { [] } else { [(root_name, "")] }
      let mut so_far = ""
      for p in parts[:dmax(0.0, (parts.length() - 1).to_double()).to_int()] {
        so_far = dv_join(so_far, p)
        crumbs.push((p, so_far))
      }
      for x in crumbs {
        let (word, path) = x
        @sf.icon(c, "chevron-right", size=files_icon, color=t.p.subtle) |> ignore
        let cid = c.id("files/crumb/" + at.station + "/" + root + "/" + path)
        c.cursor(cid, Hand)
        if c.clicked(cid) {
          front_it()
          files_go({ station: at.station, root: Some(root), path })
        }
        c.box(style=files_crumb, id=cid, fn() { c.text(word, style=place_meta) |> ignore }) |> ignore
      }
    })
    |> ignore
    c.text(name, style=files_title) |> ignore
    match text(topic.value, "countText") {
      "" => ()
      count => c.text(st.name + " · " + count, style=place_meta) |> ignore
    }
  })
  |> ignore
}

///|
/// A button of the bar that is lit while what it says is so (收藏, pin): the accent's ink then.
fn files_lit_button(c : @ui.Ctx, key : String, icon : String, label : String, on : Bool) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.cursor(id, Hand)
  let b = c.box(style=files_icon_button, id~, fn() {
    @sf.icon(c, icon, size=files_icon, color=if on { t.p.accent } else { t.p.muted }) |> ignore
  })
  c.semantics(b, Button, id~, label~)
  c.clicked(id)
}

///|
/// A row's mark (16, as the web's rows) and the folder's room in from the pane's sides (32 before it, 40 after: the
/// page's, as the preview beside it ends where the head does).
let files_icon : Double = 16.0

///|
/// A disk's bar (FilesNav.css.ts disk: 28 by 3, its corner 2, how much is used filled from its start).
let files_disk_w : Double = 28.0

///|
let files_disk_h : Double = 3.0

///|
/// Past this the disk's bar is amber (FilesNav DiskBar).
let files_disk_full : Double = 0.9

///|
// kept across runs: a value (no field of it changes)
let files_disk_used : @ui.Style = @ui.style(h=Full, bg=Muted)

///|
// kept across runs: a value (no field of it changes)
let files_disk_warn : @ui.Style = @ui.style(h=Full, bg=Warn)

///|
// kept across runs: a value (no field of it changes)
let files_icon_button : @ui.Style = @ui.style(
  w=S8,
  h=S8,
  radius=Xl,
  align=ACenter,
  justify=JCenter,
  hovered=@ui.patch(bg=Hover),
)

///|
/// Its station and where in it, its name (22 in 600), what it holds: 40 in from the pane's side.
// kept across runs: a value (no field of it changes)
let files_head : @ui.Style = @ui.style(w=Full, px=S10, pt=S3, pb=S3, gap=S1_5)

///|
// kept across runs: a value (no field of it changes)
let files_crumbs : @ui.Style = @ui.style(row=true, gap=S1, align=ACenter)

///|
/// Its station's chip (a pill on the chips' ground).
// kept across runs: a value (no field of it changes)
let files_station_chip : @ui.Style = @ui.style(row=true, h=S6, px=S2, gap=S1, align=ACenter, radius=Full, bg=Hover)

///|
// kept across runs: a value (no field of it changes)
let files_chip_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let files_crumb : @ui.Style = @ui.style(px=S0_5, radius=Sm, hovered=@ui.patch(bg=Hover))

///|
// kept across runs: a value (no field of it changes)
let files_title : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Semibold, color=Fg, wrap=false)

///|
/// A tab's close (10).
let files_close_icon : Double = 10.0

///|
// kept across runs: a value (no field of it changes)
let files_head_half : @ui.Style = @ui.style(w=Full, px=S6, pt=S3, pb=S3, gap=S1_5)

///|
/// The line under the bar (Files.css.ts: the pane's line across it).
// kept across runs: a value (no field of it changes)
let files_bar_rule : @ui.Style = @ui.style(w=Full, h=SPx, bg=Line)

///|
// kept across runs: a value (no field of it changes)
let files_column_rule : @ui.Style = @ui.style(w=SPx, h=Full, bg=Line)

///|
/// A row (Drive.css.ts row: 36 high, 8 in, the field's corner), chosen on the selected ground.
// kept across runs: a value (no field of it changes)
let files_row_style : @ui.Style = @ui.style(
  row=true,
  w=Full,
  h=S9,
  px=S2,
  gap=S2,
  align=ACenter,
  radius=Lg,
  hovered=@ui.patch(bg=Hover),
)

///|
// kept across runs: a value (no field of it changes)
let files_disclosure : @ui.Style = @ui.style(w=S4, h=S4, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let files_note_box : @ui.Style = @ui.style(w=Full, px=S2_5, py=S2)

///|
// kept across runs: a value (no field of it changes)
let files_hint : @ui.Style = @ui.style(row=true, w=Full, px=S2_5, py=S1_5, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let files_unfav : @ui.Style = @ui.style(w=S5, h=S5, align=ACenter, justify=JCenter, radius=Base, hovered=@ui.patch(bg=Hover))

///|
// kept across runs: a value (no field of it changes)
let files_place_in : @ui.Style = @ui.style(w=Full, pl=S5)

///|
// kept across runs: a value (no field of it changes)
let files_disk_bar : @ui.Style = @ui.style(w=Fixed(files_disk_w), h=Fixed(files_disk_h), radius=Sm, bg=Line, clip=true)
