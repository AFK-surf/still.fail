// The files' page in the wide frame, as the web's (ember web/src/pages/Files.tsx, FilesNav.tsx, Drive.tsx FolderView,
// DriveViews.tsx; drive/favorites.ts): the sidebar as Finder's (Pin 文件夹 in its band; 个人收藏, the person's own
// folders of any station, kept among the prefs; each station with a drive, opened to its places, how full its disk is;
// 团队共享, the folders the stations pin for everyone); the folder beside it under a bar of what can be done to it (its
// three ways: columns, a tree, a list; upload, a new folder, refresh, 收藏, pin; its view's menu), its station and where
// in it over its name and what it holds. A row is chosen by a click and opened by a double click; in columns a folder
// pressed opens beside its column.

///|
/// How the page shows a folder (prefs `driveViews.page`, as chosen here until the prefs say): columns where never chosen.
fn files_view(src : Source) -> String {
  match wide.files_view {
    Some(v) => v
    None =>
      match text(field((src.topic)("prefs", {}).value, "driveViews"), "page") {
        "tree" => "tree"
        "list" => "list"
        _ => "columns"
      }
  }
}

///|
/// Another way chosen (`prefs.set {driveViews: {page}}`).
fn files_set_view(src : Source, v : String) -> Unit {
  wide.files_view = Some(v)
  (src.call)("prefs.set", { "driveViews": { "page": if v == "columns" { Json::null() } else { Json::string(v) } } }, fn(
    _,
  ) {
    ()
  })
}

///|
/// A folder kept at hand (Favorite): its station, its root, where in it, its name.
priv struct Fav {
  station : String
  root : String
  path : String
  name : String
}

///|
/// The workspace's 个人收藏 (prefs `driveFavorites[workspace]`, a JSON list), as chosen here until the prefs say.
fn files_favs(src : Source, ws : String) -> Array[Fav] {
  let raw = match wide.favs_set.get(ws) {
    Some(r) => r
    None => text(field(field((src.topic)("prefs", {}).value, "driveFavorites"), ws), "")
  }
  let out : Array[Fav] = []
  let parsed = @json.parse(raw) catch { _ => Json::null() }
  match parsed {
    Array(list) =>
      for f in list {
        let f = Some(f)
        if text(f, "station") != "" && text(f, "root") != "" {
          out.push({ station: text(f, "station"), root: text(f, "root"), path: text(f, "path"), name: text(f, "name") })
        }
      }
    _ => ()
  }
  out
}

///|
/// The 个人收藏 kept (40 at most).
fn files_keep_favs(src : Source, ws : String, list : Array[Fav]) -> Unit {
  let kept = (if list.length() > 40 { list[:40].to_owned() } else { list }).map(fn(f) {
    Json::object({
      "station": Json::string(f.station),
      "root": Json::string(f.root),
      "path": Json::string(f.path),
      "name": Json::string(f.name),
    })
  })
  let raw = Json::array(kept).stringify()
  wide.favs_set[ws] = raw
  (src.call)("prefs.set", { "driveFavorites": Json::object(Map::from_array([(ws, Json::string(raw))])) }, fn(_) {  })
}

///|
/// Whether `at` (its root said) is among the 个人收藏.
fn files_is_fav(favs : Array[Fav], station : String, root : String, path : String) -> Bool {
  favs.iter().any(fn(f) { f.station == station && f.root == root && f.path == path })
}

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
  wide.files_chosen = ""
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
    side_top(c)
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
        (None, None) => side_breathing(c)
        _ => ()
      }
      if list is Some(_) && stations.length() == 0 {
        c.box(style=files_note_box, fn() { c.text(tr("web-main.rail.filesNone"), style=place_meta) |> ignore })
        |> ignore
      }
      // 个人收藏
      let favs = files_favs(src, w.id)
      nav_heading(c, tr("web-pages.files.favorites"))
      if favs.length() == 0 {
        c.box(style=files_hint, fn() {
          @sf.icon(c, "star", size=files_icon, color=t.p.subtle) |> ignore
          c.text(tr("android-misc.files.favoritesHint"), style=place_meta) |> ignore
        })
        |> ignore
      }
      for f in favs {
        let s = stations.iter().find_first(fn(x) { x.station == f.station })
        match s {
          Some(st) => {
            let rid = c.id("files/unfav/" + f.station + "/" + f.root + "/" + f.path)
            if c.clicked(rid) {
              files_keep_favs(src, w.id, favs.filter(fn(x) { !(x.station == f.station && x.root == f.root && x.path == f.path) }))
            } else if nav_row(c, "files/fav/" + f.station + "/" + f.root + "/" + f.path, lit(f.station, f.root, f.path), fn() {
                @sf.icon(c, "folder", size=files_icon, color=t.p.muted) |> ignore
                c.text(f.name, style=place_name) |> ignore
                c.text(st.name, style=place_meta) |> ignore
                c.box(style=files_unfav, id=rid, fn() {
                  @sf.icon(c, "close", size=files_icon, color=t.p.subtle) |> ignore
                })
                |> ignore
              }) {
              files_go({ station: f.station, root: Some(f.root), path: f.path })
            }
          }
          None => ()
        }
      }
      // Station: each, opened to its places
      if stations.length() > 0 {
        nav_heading(c, "Station")
      }
      for s in stations {
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
        } else if nav_row(
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
              if nav_row(c, "files/place/" + s.station + "/" + path, lit(s.station, path, ""), fn() {
                  @sf.icon(c, if disk { "disk" } else { "folder" }, size=files_icon, color=t.p.muted) |> ignore
                  c.text(name, style=place_name) |> ignore
                }) {
                files_go({ station: s.station, root: Some(path), path: "" })
              }
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
        nav_heading(c, tr("web-pages.files.shared"))
      }
      for x in pinned {
        let (s, r) = x
        if nav_row(c, "files/shared/" + s.station + "/" + r.path, lit(s.station, r.path, ""), fn() {
            @sf.icon(c, "pin", size=files_icon, color=t.p.muted) |> ignore
            c.text(if r.name != "" { r.name } else { dv_name(r.path) }, style=place_name) |> ignore
            c.text(s.name, style=place_meta) |> ignore
          }) {
          files_go({ station: s.station, root: Some(r.path), path: "" })
        }
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A station's places (its home, the home's own folders, its disks: `drive.folders` with no path), read as its row
/// opens, once.
fn files_places(src : Source, s : DvStation) -> Unit {
  (src.call)("drive.folders", { "station": Json::string(s.station), "path": Json::null() }, fn(r) {
    match r {
      Ok(v) => {
        let all : Array[Json] = []
        if s.home != "" {
          all.push({ "name": Json::string(tr("web-pages.drive.home")), "path": Json::string(s.home) })
        }
        for e in items(Some(v), "entries") {
          all.push(e)
        }
        for p in items(Some(v), "places") {
          all.push(p)
        }
        wide.files_places[s.station] = all
      }
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
  let used = 1.0 - number(disk, "freeBytes") / total
  let fill = (if used >= files_disk_full { files_disk_warn } else { files_disk_used }).then(
    @ui.style(w=Fixed(files_disk_w * used)),
  )
  c.box(style=files_disk_bar, fn() {
    c.box(style=fill, fn() {
      ()
    })
    |> ignore
  })
  |> ignore
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

// ── the tabs (Files.tsx FilesShell, drive/tabsModel.ts) ─────────────────

///|
/// One of the files' page's tabs (tabsModel.ts FilesTab): a folder, or two side by side, one of them in front.
priv struct FTab {
  id : String
  panes : Array[DriveAt]
  front : Int
}

///|
/// The page's tabs and the one shown.
priv struct FTabs {
  tabs : Array[FTab]
  current : String
}

///|
/// At most this many tabs (the oldest let go past it).
let files_most_tabs : Int = 12

///|
fn pane_same(a : DriveAt, b : DriveAt) -> Bool {
  a.station == b.station && a.root == b.root && a.path == b.path
}

///|
/// The workspace's tabs as kept (prefs `filesTabs[workspace]`, as kept here until the prefs say); what does not hold
/// together let go.
fn files_tabs_read(src : Source, ws : String) -> FTabs? {
  let raw = match wide.tabs_set.get(ws) {
    Some(r) => r
    None => text(field(field((src.topic)("prefs", {}).value, "filesTabs"), ws), "")
  }
  let parsed = @json.parse(raw) catch { _ => Json::null() }
  let v = Some(parsed)
  let tabs : Array[FTab] = []
  for x in items(v, "tabs") {
    let x = Some(x)
    let panes : Array[DriveAt] = []
    for p in items(x, "panes") {
      let p = Some(p)
      if text(p, "station") != "" && text(p, "root") != "" {
        panes.push({ station: text(p, "station"), root: Some(text(p, "root")), path: text(p, "path") })
      }
    }
    if text(x, "id") != "" && panes.length() >= 1 && panes.length() <= 2 {
      tabs.push({ id: text(x, "id"), panes, front: if number(x, "front") == 1.0 && panes.length() == 2 { 1 } else { 0 } })
    }
  }
  if tabs.length() == 0 {
    return None
  }
  let current = text(v, "current")
  Some({ tabs, current: if tabs.iter().any(fn(t) { t.id == current }) { current } else { tabs[0].id } })
}

///|
/// The tabs kept (`prefs.set {filesTabs: {workspace: …}}`, the web's shape).
fn files_tabs_keep(src : Source, ws : String, s : FTabs) -> Unit {
  let pane = fn(p : DriveAt) -> Json {
    { "station": Json::string(p.station), "root": Json::string(p.root.unwrap_or("")), "path": Json::string(p.path) }
  }
  let tabs = s.tabs.map(fn(t) -> Json {
    { "id": Json::string(t.id), "panes": Json::array(t.panes.map(pane)), "front": Json::number(t.front.to_double()) }
  })
  let raw = ({ "tabs": Json::array(tabs), "current": Json::string(s.current) } : Json).stringify()
  wide.tabs_set[ws] = raw
  (src.call)("prefs.set", { "filesTabs": Json::object(Map::from_array([(ws, Json::string(raw))])) }, fn(_) {  })
}

///|
/// A new tab's id: the first `t<n>` none has (by count, so the same steps give the same ids).
fn files_tab_id(tabs : Array[FTab]) -> String {
  let mut n = tabs.length()
  while tabs.iter().any(fn(t) { t.id == "t\{n}" }) {
    n = n + 1
  }
  "t\{n}"
}

///|
/// The tab shown.
fn files_tab_of(s : FTabs) -> FTab {
  match s.tabs.iter().find_first(fn(t) { t.id == s.current }) {
    Some(t) => t
    None => s.tabs[0]
  }
}

///|
/// The pane in front of the tab shown.
fn files_front_of(s : FTabs) -> DriveAt {
  let t = files_tab_of(s)
  t.panes.get(t.front).unwrap_or(t.panes[0])
}

///|
/// The address moved (the sidebar, a folder opened): the pane in front shows it; with no tabs yet, the first.
fn files_arrive(s : FTabs?, p : DriveAt) -> FTabs {
  match s {
    None => { tabs: [{ id: "t0", panes: [p], front: 0 }], current: "t0" }
    Some(s) => {
      let tabs = s.tabs.map(fn(t) {
        if t.id != s.current || pane_same(t.panes[t.front], p) {
          t
        } else {
          { ..t, panes: t.panes.mapi(fn(i, x) { if i == t.front { p } else { x } }) }
        }
      })
      { ..s, tabs, }
    }
  }
}

///|
/// A new tab showing `p`, after the one shown, shown.
fn files_opened(s : FTabs, p : DriveAt) -> FTabs {
  let tab : FTab = { id: files_tab_id(s.tabs), panes: [p], front: 0 }
  let at = s.tabs.search_by(fn(t) { t.id == s.current }).unwrap_or(0)
  let tabs : Array[FTab] = []
  for i, t in s.tabs {
    tabs.push(t)
    if i == at {
      tabs.push(tab)
    }
  }
  let first = s.tabs[0].id
  { tabs: if tabs.length() > files_most_tabs { tabs.filter(fn(t) { t.id != first }) } else { tabs }, current: tab.id }
}

///|
/// A tab closed (the last one is not: it stays, as Finder keeps a window); the one beside it shown.
fn files_closed(s : FTabs, id : String) -> FTabs {
  if s.tabs.length() <= 1 {
    return s
  }
  let at = s.tabs.search_by(fn(t) { t.id == id }).unwrap_or(0)
  let tabs = s.tabs.filter(fn(t) { t.id != id })
  let next = if at < tabs.length() { at } else { tabs.length() - 1 }
  { tabs, current: if s.current == id { tabs[next].id } else { s.current } }
}

///|
/// The tab shown split in two (the other side opening where the front is), or one again (the side in front kept).
fn files_split(s : FTabs) -> FTabs {
  let tabs = s.tabs.map(fn(t) {
    if t.id != s.current {
      t
    } else if t.panes.length() == 2 {
      { ..t, panes: [t.panes[t.front]], front: 0 }
    } else {
      { ..t, panes: [t.panes[0], t.panes[0]], front: 1 }
    }
  })
  { ..s, tabs, }
}

///|
/// The side `front` of the tab shown put in front.
fn files_fronted(s : FTabs, front : Int) -> FTabs {
  let tabs = s.tabs.map(fn(t) { if t.id == s.current && front < t.panes.length() { { ..t, front, } } else { t } })
  { ..s, tabs, }
}

///|
/// A pane's folder (its last part; a root pinned by its name, the home as 主目录) and its station's name.
fn files_pane_parts(p : DriveAt, stations : Array[DvStation]) -> (String, String) {
  let root = p.root.unwrap_or("")
  match stations.iter().find_first(fn(s) { s.station == p.station }) {
    Some(s) => {
      let folder = if p.path != "" {
        dv_name(p.path)
      } else if root == s.home && !s.roots.iter().any(fn(r) { r.path == root }) {
        tr("web-pages.drive.home")
      } else {
        dv_root_label(s.roots, root)
      }
      (folder, s.name)
    }
    None => (if p.path != "" { dv_name(p.path) } else { dv_name(root) }, "")
  }
}

// ── a folder (FolderView) ───────────────────────────────────────────────

///|
/// The files' page at a folder: the bar (the tabs, when more than one; what can be done to the folder in front; split
/// and a new tab), then the tab shown, a folder or two side by side. The folder in front is the stack's top (what the
/// sidebar and opening a folder move); a press in the other side puts it in front.
fn wide_folder(c : @ui.Ctx, src : Source, w : Workspace, at : DriveAt) -> Unit {
  let t = @sf.theme()
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
  let can = dv_rights(src, w.id, s)
  let here : DriveAt = { station: at.station, root: Some(root), path: at.path }
  dv.building = dv_page_of(Some(here))
  let tabs = files_arrive(files_tabs_read(src, w.id), here)
  let tab = files_tab_of(tabs)
  let split_on = tab.panes.length() == 2
  // other tabs or sides brought in front: kept, the stack's top the folder in front
  let show = fn(next : FTabs) {
    files_tabs_keep(src, w.id, next)
    let f = files_front_of(next)
    if !pane_same(f, here) {
      files_go(f)
    }
  }
  // ⌘T a new tab where the front is, ⌘⌥D split
  if c.shortcut('t') {
    show(files_opened(tabs, here))
  }
  if c.key_pressed(@ui.key_of_char('d'), mods=@ui.mod_cmd + @ui.mod_alt) {
    show(files_split(tabs))
  }
  // ⌘⇧G: a folder by its path (FilesGo.tsx GoTo), as Finder's 前往文件夹
  if c.key_pressed(@ui.key_of_char('g'), mods=@ui.mod_cmd + @ui.mod_shift_key) {
    fgo_open()
  }
  let (name, _) = files_pane_parts(here, stations)
  let favs = files_favs(src, w.id)
  let faved = files_is_fav(favs, at.station, root, at.path)
  let abs = if at.path == "" { root } else { root + "/" + at.path }
  let pinned = st.roots.iter().any(fn(r) { r.path == abs })
  let key = folder_key(at.station, root, at.path)
  c.box(style=files_page_box, fn() {
    // the bar (Files.tsx's): the tabs, the folder's ways and what can be done to it, then the tabs' own
    let bar = c.id("files-bar")
    if @ui.window_inset() {
      c.window_drag(bar)
    }
    c.box(style=files_bar, id=bar, fn() {
      if tabs.tabs.length() > 1 {
        files_tab_row(c, stations, tabs, show)
      } else {
        c.box(style=files_tabs_none, fn() {  }) |> ignore
      }
      files_transfers(c)
      c.box(style=files_views, fn() {
        for v in [("columns", "view-columns"), ("tree", "view-tree"), ("list", "list")] {
          let (way, icon) = v
          let on = files_view(src) == way
          let vid = c.id("files/view/" + way)
          c.cursor(vid, Hand)
          if c.clicked(vid) && !on {
            files_set_view(src, way)
          }
          let b = c.box(style=if on { files_view_on } else { files_view_off }, id=vid, fn() {
            @sf.icon(c, icon, size=files_icon, color=if on { t.p.text } else { t.p.muted }) |> ignore
          })
          c.semantics(b, Button, id=vid, label=tr("web-pages.drive.view." + way))
        }
      })
      |> ignore
      if can.write && icon_button(c, "files/upload", "upload", label=tr("web-pages.drive.upload")) {
        dv_upload(c, here)
      }
      if can.write && icon_button(c, "files/mkdir", "folder-plus", label=tr("web-pages.drive.mkdir")) {
        dv_new_folder(c, src, here)
      }
      if icon_button(c, "files/refresh", "refresh", label=tr("web-pages.drive.refresh")) && !dv.refreshing.contains(key) {
        dv.refreshing[key] = true
        (src.call)(
          "drive.refresh",
          { "station": Json::string(at.station), "root": Json::string(root), "path": Json::string(at.path) },
          fn(r) {
            dv.refreshing.remove(key)
            (dv_act(c, tr("web-pages.drive.refreshWhat")))(r)
          },
        )
      }
      let fav_label = fill(if faved { "web-pages.files.unfavorite" } else { "web-pages.files.favorite" }, [("name", name)])
      if files_lit_button(c, "files/fav", "star", fav_label, faved) {
        if faved {
          files_keep_favs(src, w.id, favs.filter(fn(f) { !(f.station == at.station && f.root == root && f.path == at.path) }))
        } else {
          let kept : Array[Fav] = [{ station: at.station, root, path: at.path, name }]
          for f in favs {
            kept.push(f)
          }
          files_keep_favs(src, w.id, kept)
        }
      }
      if st.anywhere && can.manage &&
        files_lit_button(c, "files/pin", "pin", tr(if pinned { "web-pages.drive.unpin" } else { "web-pages.drive.pin" }), pinned) {
        let roots = st.roots.map(fn(r) { r.path }).filter(fn(p) { p != abs })
        if !pinned {
          roots.push(abs)
        }
        (src.call)(
          "drive.setRoots",
          { "station": Json::string(at.station), "roots": Json::array(roots.map(fn(p) { Json::string(p) })) },
          dv_act(c, tr("android-misc.drive.roots.what")),
        )
      }
      if icon_button(c, "files/more", "more", label=tr("android-misc.drive.view")) {
        dv_open(c, View(here, can.manage && at.path == ""))
      }
      c.box(style=files_bar_sep, fn() {  }) |> ignore
      if files_lit_button(c, "files/split", "view-columns", tr(if split_on { "web-pages.files.unsplit" } else { "web-pages.files.split" }), split_on) {
        show(files_split(tabs))
      }
      if icon_button(c, "files/new-tab", "plus", label=tr("web-pages.files.newTab")) {
        show(files_opened(tabs, here))
      }
    })
    |> ignore
    c.box(style=files_bar_rule, fn() {  }) |> ignore
    // the tab shown: a side each, split the one in front lined at its top
    c.box(style=files_panes, fn() {
      for i, p in tab.panes {
        let front = i == tab.front
        let pane = if front { here } else { p }
        if i > 0 {
          c.box(style=files_column_rule, fn() {  }) |> ignore
        }
        c.box(style=if split_on { files_side_half } else { files_side_one }, fn() {
          if split_on {
            c.box(style=if front { files_front_line } else { files_back_line }, fn() {  }) |> ignore
          }
          // (each side's ids its own: the same folder can be on both)
          c.scope(i, fn() {
            folder_pane(c, src, w, stations, pane, split_on, fn() {
              if !front {
                show(files_fronted(tabs, i))
              }
            })
          })
        })
        |> ignore
      }
    })
    |> ignore
    dv_sheets(c, src, w, dv_page_of(Some(here)))
    files_goto(c, src, stations, here)
  })
  |> ignore
}

// ── the transfers (Transfers.tsx TransfersButton) ───────────────────────

///|
/// What is going up or down while the app runs: each its name and how far (of 100).
fn files_going() -> Array[(String, Int)] {
  let out : Array[(String, Int)] = []
  for u in dv.uploads {
    if u.state == "waiting" || u.state == "going" {
      let total = u.bytes.length()
      out.push((u.name, if total > 0 { u.sent * 100 / total } else { 0 }))
    }
  }
  dv_fetches.each(fn(key, at) {
    let name = match key.rev_find("\n") {
      Some(i) => dv_name(key.view(start_offset=i + 1).to_string())
      None => key
    }
    out.push((name, at))
  })
  out
}

///|
/// The bar's chip while something goes up or down (N 个传输 · P%: how far all of it is); pressed, each with how far.
fn files_transfers(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  let going = files_going()
  let id = c.id("files/transfers")
  if going.length() == 0 {
    wide_menu(c, "files/transfers-menu", false, id, [], {}, fgo_menu_w) |> ignore
    fgo.transfers = false
    return
  }
  let percent = going.fold(init=0, fn(a, g) { a + g.1 }) / going.length()
  c.cursor(id, Hand)
  if c.clicked(id) {
    fgo.transfers = !fgo.transfers
  }
  let words = fill("web-pages.files.transfersGoing", [("n", going.length().to_string()), ("percent", percent.to_string())])
  let b = c.box(style=files_transfers_chip, id~, fn() {
    @sf.icon(c, "upload", size=files_close_icon, color=t.p.muted) |> ignore
    c.text(words, style=files_chip_words) |> ignore
  })
  c.semantics(b, Button, id~, label=tr("web-pages.files.transfers"))
  let entries = going.map(fn(g) { @kit.menu_item(g.0, label=g.0 + " · " + g.1.to_string() + "%", disabled=true) })
  let m = wide_menu(c, "files/transfers-menu", fgo.transfers, id, entries, {}, fgo_menu_w)
  if fgo.transfers && !m.open {
    fgo.transfers = false
  }
}

///|
/// The transfers' chip: a capsule 28 high on the chips' ground.
// kept across runs: a value (no field of it changes)
let files_transfers_chip : @ui.Style = @ui.style(row=true, h=S7, px=S2_5, gap=S1_5, align=ACenter, radius=Full, bg=Hover)

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
  let d = @kit.dialog(
    c,
    "files-goto",
    fgo.open,
    tr("web-pages.files.goTo"),
    description=tr("web-pages.files.goToNote"),
    w=dmin(fgo_w, c.width - fgo_margin),
    close_label="",
    look=fn(c, s, body) {
      c.box(style=fgo_panel.then(@ui.style(w=Fixed(s.w))), fn() {
        c.text(s.title, style=fgo_title) |> ignore
        c.text(s.description, style=fgo_note) |> ignore
        body()
      })
      |> ignore
    },
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
  if !d.value {
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
  let m = wide_menu(c, "files/switch/" + chip.to_string(), open, chip, entries, {}, fgo_menu_w)
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
let fgo_panel : @ui.Style = @ui.style(p=S5, gap=S2, radius=Xl3, bg=Raised, border=B1, border_color=Line, shadow=Lg)

///|
// kept across runs: a value (no field of it changes)
let fgo_title : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Fg, wrap=false)

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
/// The tabs as Safari's compact ones (Files.css.ts tabs): one groove, each tab an equal share of it, the one shown
/// raised; its folder first, its station after it, small, a dot of its station's colour before; its close at its left
/// while pointed at.
fn files_tab_row(c : @ui.Ctx, stations : Array[DvStation], tabs : FTabs, show : (FTabs) -> Unit) -> Unit {
  let t = @sf.theme()
  c.box(style=files_tabs_groove, fn() {
    for x in tabs.tabs {
      let on = x.id == tabs.current
      let id = c.id("files/tab/" + x.id)
      let cid = c.id("files/tab-close/" + x.id)
      c.cursor(id, Hand)
      c.cursor(cid, Hand)
      if c.clicked(cid) {
        show(files_closed(tabs, x.id))
      } else if c.clicked(id) && !on {
        show({ ..tabs, current: x.id })
      }
      let hot = c.hovered(id) || c.hovered(cid)
      let words = x.panes.map(fn(p) { files_pane_parts(p, stations).0 }).join(" | ")
      let b = c.box(style=if on { files_tab_on } else { files_tab_off }, id~, fn() {
        let close = c.box(style=files_tab_close, id=cid, fn() {
          if hot {
            @sf.icon(c, "close", size=files_close_icon, color=t.p.muted) |> ignore
          }
        })
        c.semantics(close, Button, id=cid, label=tr("web-pages.files.closeTab"))
        c.box(style=files_tab_parts, fn() {
          for i, p in x.panes {
            if i > 0 {
              c.box(style=files_tab_split, fn() {  }) |> ignore
            }
            let tone = stations.search_by(fn(s) { s.station == p.station }).unwrap_or(0) % files_dots.length()
            c.box(style=files_dots[tone], fn() {  }) |> ignore
            let (folder, station) = files_pane_parts(p, stations)
            c.text(folder, style=if on { files_tab_folder_on } else { files_tab_folder }) |> ignore
            c.text(station, style=files_tab_station) |> ignore
          }
        })
        |> ignore
        // (as wide as its close, so its words are in its middle)
        c.box(style=files_tab_close, fn() {  }) |> ignore
      })
      c.semantics(b, Button, id~, label=words)
    }
  })
  |> ignore
}

///|
/// One side: its station and where in it, its name and what it holds, then its way of showing. `front_it` puts it in
/// front, said first by whatever is pressed in it.
fn folder_pane(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  stations : Array[DvStation],
  at : DriveAt,
  split_on : Bool,
  front_it : () -> Unit,
) -> Unit {
  let t = @sf.theme()
  let st = match stations.iter().find_first(fn(x) { x.station == at.station }) {
    Some(v) => v
    None => {
      c.box(style=files_head, fn() { c.text(tr("web-pages.workspace.noSuchStation"), style=place_meta) |> ignore })
      |> ignore
      return
    }
  }
  let root = at.root.unwrap_or("")
  let topic = (src.topic)("drive", {
    "station": Json::string(at.station),
    "root": Json::string(root),
    "path": Json::string(at.path),
  })
  let (name, _) = files_pane_parts(at, stations)
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
      let (root_name, _) = files_pane_parts({ ..at, path: "" }, stations)
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
  let total = c.width - rail_w - (if wide.folded { 0.0 } else { wide.side_w })
  let room = if split_on { total / 2.0 - files_body_in_half } else { total - files_body_in }
  c.box(style=if split_on { files_pane_half } else { files_pane }, fn() {
    match files_view(src) {
      "list" => files_list(c, src, at, root, at.path, 0, false, front_it)
      "tree" => files_list(c, src, at, root, at.path, 0, true, front_it)
      _ => files_columns(c, src, at, root, room, front_it)
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
/// A folder's entries in the order shown (the device's order, hidden ones as it says).
fn files_entries(src : Source, station : String, root : String, path : String) -> (Array[DvEntry]?, String?) {
  let topic = (src.topic)("drive", {
    "station": Json::string(station),
    "root": Json::string(root),
    "path": Json::string(path),
  })
  let (sort, hidden) = dv_views(src)
  match topic.value {
    Some(v) => (Some(dv_arranged(items(Some(v), "entries").map(dv_entry), sort, hidden)), None)
    None =>
      (
        None,
        match topic.error {
          Some(e) => Some(dv_error(e))
          None => None
        },
      )
  }
}

///|
/// A folder's rows (a list), or with its folders opened in place under them (`tree`), in by a step a depth.
fn files_list(
  c : @ui.Ctx,
  src : Source,
  at : DriveAt,
  root : String,
  path : String,
  depth : Int,
  tree : Bool,
  front_it : () -> Unit,
) -> Unit {
  let (entries, error) = files_entries(src, at.station, root, path)
  match (entries, error) {
    (None, Some(e)) => c.text(e, style=place_trouble) |> ignore
    (None, None) => c.box(style=files_note_box, fn() { c.text(tr("web-pages.files.reading"), style=place_meta) |> ignore }) |> ignore
    (Some([]), _) =>
      c.box(style=files_note_box, fn() { c.text(tr("web-pages.drive.emptyFolder"), style=place_meta) |> ignore }) |> ignore
    (Some(list), _) => {
      // a list's heads (ListView): its order by a press on one, the one it is in marked
      if !tree && depth == 0 {
        files_heads(c, src)
      }
      for e in list {
        let full = dv_join(path, e.name)
        let okey = "tree/" + at.station + "/" + root + "/" + full
        let open = tree && e.dir && wide.files_open.contains(okey)
        wide_row(c, src, at, root, path, e, list, depth, if tree && e.dir { Some(open) } else { None }, front_it, fn() {
          if open {
            wide.files_open.remove(okey)
          } else {
            wide.files_open[okey] = true
          }
        })
        if open {
          files_list(c, src, at, root, full, depth + 1, true, front_it)
        }
      }
    }
  }
}

///|
/// A list's heads (DriveViews.tsx ListView): 名称, 大小, 修改时间 over their columns; a press orders the folder by it
/// (`driveViews.sort`), the order it is in marked.
fn files_heads(c : @ui.Ctx, src : Source) -> Unit {
  let t = @sf.theme()
  let (sort, _) = dv_views(src)
  let head = fn(key : String, words : String, style : @ui.Style) {
    let id = c.id("files/head/" + key)
    c.cursor(id, Hand)
    if c.clicked(id) && sort != key {
      dv_set_view(src, "sort", if key == "name" { None } else { Some(key) })
    }
    let b = c.box(style~, id~, fn() {
      c.text(words, style=files_head_words) |> ignore
      if sort == key {
        @sf.icon(c, "chevron-down", size=files_close_icon, color=t.p.muted) |> ignore
      }
    })
    c.semantics(b, Button, id~, label=words)
  }
  c.box(style=files_heads_row, fn() {
    c.box(style=files_head_mark, fn() {  }) |> ignore
    head("name", tr("web-pages.drive.sortBy.nameHead"), files_head_name)
    head("size", tr("web-pages.drive.sortBy.sizeHead"), files_head_size)
    head("time", tr("web-pages.drive.sortBy.timeHead"), files_head_time)
    c.box(style=files_row_end, fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// The folder in columns (ColumnsView): a column a folder, from the one open to the one opened in it (and so on), as
/// many as the pane holds, the last ones; a folder pressed opens beside its column, the columns after it let go.
fn files_columns(c : @ui.Ctx, src : Source, at : DriveAt, root : String, pane : Double, front_it : () -> Unit) -> Unit {
  let ckey = at.station + "\u{1}" + root + "\u{1}" + at.path
  let open = wide.files_cols.get(ckey).unwrap_or("")
  let parts = if open == "" { [] } else { open.split("/").map(fn(p) { p.to_string() }).collect() }
  let paths = [at.path]
  let mut so_far = at.path
  for p in parts {
    so_far = dv_join(so_far, p)
    paths.push(so_far)
  }
  let room = dmax(1.0, (pane / files_column_w).floor())
  let from = dmax(0.0, paths.length().to_double() - room).to_int()
  c.box(style=files_columns_row, fn() {
    for i in from..<paths.length() {
      let path = paths[i]
      let next = parts.get(i)
      c.box(style=files_column, fn() {
        let (entries, error) = files_entries(src, at.station, root, path)
        match (entries, error) {
          (None, Some(e)) => c.text(e, style=place_trouble) |> ignore
          (None, None) =>
            c.box(style=files_note_box, fn() { c.text(tr("web-pages.files.reading"), style=place_meta) |> ignore })
            |> ignore
          (Some([]), _) =>
            c.box(style=files_note_box, fn() { c.text(tr("web-pages.drive.emptyFolder"), style=place_meta) |> ignore })
            |> ignore
          (Some(list), _) =>
            for e in list {
              let along = next == Some(e.name)
              wide_row(c, src, at, root, path, e, list, 0, None, front_it, fn() {  }, along~, column=true, open_beside=fn() {
                // (what is opened under the column's folder: its way down from where the columns start)
                let below = if at.path == "" {
                  dv_join(path, e.name)
                } else {
                  dv_join(path, e.name).view(start_offset=at.path.length() + 1).to_string()
                }
                wide.files_cols[ckey] = below
              })
            }
        }
      })
      |> ignore
      c.box(style=files_column_rule, fn() {  }) |> ignore
    }
  })
  |> ignore
}

///|
/// A row (DriveRow): its kind's mark (a folder's disclosure before it in a tree), its name; chosen by a click, opened by
/// a double click (a folder gone into; in columns, a folder pressed opens beside); `along` the folder open beside.
fn wide_row(
  c : @ui.Ctx,
  src : Source,
  at : DriveAt,
  root : String,
  dir : String,
  e : DvEntry,
  shown : Array[DvEntry],
  depth : Int,
  disclosure : Bool?,
  front_it : () -> Unit,
  toggle : () -> Unit,
  along? : Bool = false,
  column? : Bool = false,
  open_beside? : () -> Unit = fn() {  },
) -> Unit {
  let t = @sf.theme()
  let rkey = at.station + "\u{1}" + root + "\u{1}" + dv_join(dir, e.name)
  let id = c.id("files/row/" + rkey)
  let did = c.id("files/row-open/" + rkey)
  c.cursor(id, Hand)
  let chosen = wide.files_chosen == rkey
  let in_place : DriveAt = { station: at.station, root: Some(root), path: dir }
  // (a press in the side not in front puts it in front first)
  if c.clicked(did) || c.double_clicked(id) || c.clicked(id) || c.right_clicked(id) is Some(_) {
    front_it()
  }
  // its menu (the drive's sheet of an entry: open, share, rename, move, delete…) from a right click, chosen
  if c.right_clicked(id) is Some(_) {
    wide.files_chosen = rkey
    dv_open(c, Entry(in_place, e, shown.map(fn(x) { x.name })))
  }
  if c.clicked(did) {
    toggle()
  } else if c.double_clicked(id) {
    drive_open(c, src, in_place, root, e, shown)
  } else if c.clicked(id) {
    wide.files_chosen = rkey
    if column && e.dir {
      open_beside()
    }
  }
  c.box(style=if chosen || along { files_row_on } else { files_row_style }, id~, fn() {
    if depth > 0 {
      c.box(style=@ui.style(w=Fixed(files_indent * depth.to_double())), fn() {  }) |> ignore
    }
    match disclosure {
      Some(open) =>
        c.box(style=files_disclosure, id=did, fn() {
          @sf.icon(c, if open { "chevron-down" } else { "chevron-right" }, size=files_icon, color=t.p.subtle) |> ignore
        })
        |> ignore
      None => ()
    }
    @sf.icon(c, dv_kind_icon(if e.dir { "folder" } else { e.kind }), size=files_icon, color=t.p.muted) |> ignore
    c.text(e.name, style=place_name) |> ignore
    if column && e.dir {
      @sf.icon(c, "chevron-right", size=files_icon, color=t.p.subtle) |> ignore
    }
    // a list's and a tree's: its size and when it changed, in their columns
    if !column {
      c.box(style=files_size_cell, fn() { c.text(e.size_text, style=files_cell_words) |> ignore }) |> ignore
      c.box(style=files_time_cell, fn() { c.text(e.time_text, style=files_cell_words) |> ignore }) |> ignore
      c.box(style=files_row_end, fn() {  }) |> ignore
    }
  })
  |> ignore
}

///|
/// A column (Drive.css.ts column: 240 wide), a tree's step in (16), a disk's bar (24).
let files_column_w : Double = 240.0

///|
let files_indent : Double = 16.0

///|
/// A row's mark (16, as the web's rows) and the folder's room in from the pane's sides (32 each).
let files_icon : Double = 16.0

///|
let files_body_in : Double = 64.0

///|
let files_disk_w : Double = 24.0

///|
/// Past this the disk's bar is amber (FilesNav DiskBar).
let files_disk_full : Double = 0.9

///|
// kept across runs: a value (no field of it changes)
let files_disk_used : @ui.Style = @ui.style(h=Full, radius=Full, bg=Muted)

///|
// kept across runs: a value (no field of it changes)
let files_disk_warn : @ui.Style = @ui.style(h=Full, radius=Full, bg=Warn)

///|
// kept across runs: a value (no field of it changes)
let files_page_box : @ui.Style = @ui.style(w=Full, h=Full, bg=Bg)

///|
/// The bar: 45 high, what is on it at its end, 12 in, a line under it.
// kept across runs: a value (no field of it changes)
let files_bar : @ui.Style = @ui.style(row=true, w=Full, h=S11, px=S3, gap=S1, align=ACenter, justify=JEnd)

///|
/// The three ways side by side on a ground of their own (Drive.css.ts views), the one shown raised.
// kept across runs: a value (no field of it changes)
let files_views : @ui.Style = @ui.style(row=true, p=S0_5, gap=SPx, radius=Xl, bg=Hover)

///|
// kept across runs: a value (no field of it changes)
let files_view_off : @ui.Style = @ui.style(w=S7, h=S7, radius=Lg, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let files_view_on : @ui.Style = files_view_off.then(@ui.style(bg=Bg))

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
// kept across runs: a value (no field of it changes)
let files_pane : @ui.Style = @ui.style(w=Full, h=Full, px=S8, clip=true)

///|
/// Split, a side's room in from its sides (24 each and its rows' 16).
let files_body_in_half : Double = 80.0

///|
/// A tab's close (10).
let files_close_icon : Double = 10.0

///|
/// Room for what the bar starts with when there is one tab (none shown).
// kept across runs: a value (no field of it changes)
let files_tabs_none : @ui.Style = @ui.style(w=@sf.grow)

///|
/// Between what is done to the folder and the tabs' own buttons: a short line, 16 high (Files.css.ts barFolder).
// kept across runs: a value (no field of it changes)
let files_bar_sep : @ui.Style = @ui.style(w=SPx, h=S4, bg=Line)

///|
/// The tabs' groove (Files.css.ts tabs): capsules in a capsule, 2 apart, on the words' colour at 6%.
// kept across runs: a value (no field of it changes)
let files_tabs_groove : @ui.Style = @ui.style(row=true, w=@sf.grow, p=S0_5, gap=S0_5, radius=Full, bg=Tint)

///|
/// A tab: an equal share of the groove, at most 280, 28 high; the one shown on the page's ground.
// kept across runs: a value (no field of it changes)
let files_tab_off : @ui.Style = @ui.style(
  row=true,
  w=@sf.grow,
  max_w=Fixed(files_tab_most),
  h=S7,
  px=S1_5,
  align=ACenter,
  radius=Full,
  hovered=@ui.patch(bg=Hover),
)

///|
// kept across runs: a value (no field of it changes)
let files_tab_on : @ui.Style = files_tab_off.then(@ui.style(bg=Bg, shadow=Sm))

///|
let files_tab_most : Double = 280.0

///|
/// Its close: a circle 16 across, 6 in from its end.
// kept across runs: a value (no field of it changes)
let files_tab_close : @ui.Style = @ui.style(
  w=S4,
  h=S4,
  radius=Full,
  align=ACenter,
  justify=JCenter,
  hovered=@ui.patch(bg=Hover),
)

///|
// kept across runs: a value (no field of it changes)
let files_tab_parts : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S1_5, align=ACenter, justify=JCenter, clip=true)

///|
// kept across runs: a value (no field of it changes)
let files_tab_split : @ui.Style = @ui.style(w=SPx, h=S2_5, bg=Line)

///|
// kept across runs: a value (no field of it changes)
let files_tab_folder : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let files_tab_folder_on : @ui.TextStyle = @ui.text_style(size=Xs, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let files_tab_station : @ui.TextStyle = @ui.text_style(size=Xs, color=Subtle, wrap=false)

///|
/// A station's colour on the tabs: one of six, by its place among the workspace's (Files.css.ts dot: 7 across).
// kept across runs: a table, never written
let files_dots : Array[@ui.Style] = ([Accent, Link, Positive, Warn, Danger, Muted] : Array[@ui.Color]).map(fn(k) {
  @ui.style(w=S1_5, h=S1_5, radius=Full, bg=k)
})

///|
/// The tab's sides, side by side.
// kept across runs: a value (no field of it changes)
let files_panes : @ui.Style = @ui.style(row=true, w=Full, h=Full)

///|
// kept across runs: a value (no field of it changes)
let files_side_one : @ui.Style = @ui.style(w=Full, h=Full)

///|
// kept across runs: a value (no field of it changes)
let files_side_half : @ui.Style = @ui.style(w=@sf.grow, h=Full, clip=true)

///|
/// Split, the side in front lined at its top in the accent (2), the other not.
// kept across runs: a value (no field of it changes)
let files_front_line : @ui.Style = @ui.style(w=Full, h=S0_5, bg=Accent)

///|
// kept across runs: a value (no field of it changes)
let files_back_line : @ui.Style = @ui.style(w=Full, h=S0_5)

///|
// kept across runs: a value (no field of it changes)
let files_head_half : @ui.Style = @ui.style(w=Full, px=S6, pt=S3, pb=S3, gap=S1_5)

///|
// kept across runs: a value (no field of it changes)
let files_pane_half : @ui.Style = @ui.style(w=Full, h=Full, px=S4, clip=true)

///|
/// A list's columns (ListView): its size's (96) and its time's (116), right-aligned, and the room after them for its
/// row's menu (64).
// kept across runs: a value (no field of it changes)
let files_size_cell : @ui.Style = @ui.style(row=true, w=S24, justify=JEnd)

///|
// kept across runs: a value (no field of it changes)
let files_time_cell : @ui.Style = @ui.style(row=true, w=S28, justify=JEnd)

///|
// kept across runs: a value (no field of it changes)
let files_row_end : @ui.Style = @ui.style(w=S16)

///|
// kept across runs: a value (no field of it changes)
let files_cell_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// The heads: a row 32 high, their words small and muted, each over its column.
// kept across runs: a value (no field of it changes)
let files_heads_row : @ui.Style = @ui.style(row=true, w=Full, h=S8, px=S2, gap=S2, align=ACenter)

///|
/// (over a row's mark: as wide as it)
// kept across runs: a value (no field of it changes)
let files_head_mark : @ui.Style = @ui.style(w=S4)

///|
// kept across runs: a value (no field of it changes)
let files_head_name : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S1, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let files_head_size : @ui.Style = @ui.style(row=true, w=S24, gap=S1, align=ACenter, justify=JEnd)

///|
// kept across runs: a value (no field of it changes)
let files_head_time : @ui.Style = @ui.style(row=true, w=S28, gap=S1, align=ACenter, justify=JEnd)

///|
// kept across runs: a value (no field of it changes)
let files_head_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// The line under the bar (Files.css.ts: the pane's line across it).
// kept across runs: a value (no field of it changes)
let files_bar_rule : @ui.Style = @ui.style(w=Full, h=SPx, bg=Line)

///|
// kept across runs: a value (no field of it changes)
let files_columns_row : @ui.Style = @ui.style(row=true, w=Full, h=Full)

///|
// kept across runs: a value (no field of it changes)
let files_column : @ui.Style = @ui.style(w=Fixed(files_column_w), h=Full, px=S1, clip=true)

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
let files_row_on : @ui.Style = files_row_style.then(@ui.style(bg=Selected))

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
let files_disk_bar : @ui.Style = @ui.style(w=Fixed(files_disk_w), h=S1, radius=Full, bg=Line, clip=true)
