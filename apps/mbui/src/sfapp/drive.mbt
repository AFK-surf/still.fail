// A station's drive (ember apps/android drive/Files.kt, DriveScreen.kt; docs/drive.md): 文件, every station's folders
// lent (its home first for a member who browses every folder), each opening its folder's page; a folder's page lists
// what is in it (its order and whether hidden files show are the device's, prefs `driveViews`), a folder goes in (a
// page pushed, so going in and coming back is the stack's slide and the edge swipe), a text or Markdown file is read
// (drive_reader.mbt), anything else goes to the file's preview (open_file); held, a row is chosen (others then by a
// tap) and what is chosen is renamed, deleted (to the machine's trash where the station has one), its path copied.
// ＋ uploads files (`drive.upload.part`, a part at a time, each a row of the folder until it is there) and makes
// folders; the workspace's owners and admins choose the folders lent (`drive.setRoots`, the folder picker).

///|
/// 文件 (Files.kt FilesScreen): pushed, a page with back and its ＋ in its bar; `place`, the top of a place of the
/// bottom bar (its top bar as Home's, the ＋ the bar's: files_lend).
pub fn files_page(c : @ui.Ctx, src : Source, w : Workspace, place? : Bool = false) -> Unit {
  let t = @sf.theme()
  let (list, error) = dv_stations(src, w.id)
  let lenders = files_lenders(src, w, list)
  dv.building = dv_page_of(None)
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
    if !place {
      let back = match under_page() {
        Some(Home) => tr("android-misc.bar.place.chats")
        _ => tr("android-settings.title")
      }
      if dv_nav_bar(c, back, tr("android-misc.bar.place.files"), fn() {
          if lenders.length() > 0 &&
            dv_nav_button(c, "files-lend", "plus", size=20.0, said=tr("android-misc.bar.action.files")) {
            files_lend_on(c, lenders)
          }
        }) {
        app.nav.pop() |> ignore
      }
    }
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      // under the top bar (and the status bar); at the foot 30 over the navigation bar, and the bottom bar's room at a
      // place's top (Files.kt foot)
      let foot = nav_foot() + 30.0 + (if place && has_bar() { bar_room } else { 0.0 })
      files_body(c, src, list, error, lenders, if place { status_top() + bar_h + 8.0 } else { 4.0 }, foot)
      if place {
        c.layer(fn() { files_top_bar(c) }) |> ignore
      }
    })
    |> ignore
    dv_sheets(c, src, w, dv_page_of(None))
  })
  |> ignore
}

///|
/// Whether 文件 offers ＋ (another folder lent: an owner or admin, a station up with a drive), for the bottom bar's
/// notch.
pub fn files_can_lend(src : Source, w : Workspace) -> Bool {
  let (list, _) = dv_stations(src, w.id)
  files_lenders(src, w, list).length() > 0
}

///|
/// ＋ of 文件 (the bottom bar's notch): another folder lent, on the one station there is or one chosen first.
pub fn files_lend(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let (list, _) = dv_stations(src, w.id)
  files_lend_on(c, files_lenders(src, w, list))
}

///|
fn files_lenders(src : Source, w : Workspace, list : Array[DvStation]?) -> Array[DvStation] {
  let manager = dv_manager((src.topic)("workspace", { "workspace": Json::string(w.id) }).value)
  if !manager {
    return []
  }
  list.unwrap_or([]).filter(fn(s) { s.online && s.drive })
}

///|
fn files_lend_on(c : @ui.Ctx, on : Array[DvStation]) -> Unit {
  match on {
    [] => ()
    [s] => dv_open_picker(c, s.station, s.roots.map(fn(r) { r.path }))
    _ => dv_open(c, LendOn(on))
  }
}

///|
/// The page under the top one, if any.
fn under_page() -> Page? {
  let pages = app.nav.pages()
  if pages.length() >= 2 {
    Some(pages[pages.length() - 2])
  } else {
    None
  }
}

///|
/// 文件's top bar as a place's (PlacePage.kt TopGlassBar): settings, its name.
fn files_top_bar(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), glass=@sf.glass_bar(), fn() {
    // under the status bar (TopGlassBar: windowInsetsPadding(statusBars), then TopBarHeight)
    c.box(dir=Row, w=Fill(1.0), pl=16.0, pr=16.0, pt=status_top(), min_h=top_bar_h(), gap=10.0, align=ACenter, fn() {
      if nav_button(c, "settings", 22.0, key="files-settings") {
        app.nav.push(Settings)
      }
      c.box(w=Fill(1.0), h=Px(34.0), justify=JCenter, fn() {
        top_bar_title(c, tr("android-misc.bar.place.files")) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A folder lent and the station it is on; `home`: the station's home.
priv struct Lent {
  s : DvStation
  root : DvRoot
  home : Bool
}

///|
priv enum FilesItem {
  FTop(Double)
  FHead(DvStation)
  FRow(Lent)
  FFoot
}

///|
fn files_body(
  c : @ui.Ctx,
  src : Source,
  list : Array[DvStation]?,
  error : String?,
  lenders : Array[DvStation],
  top : Double,
  foot : Double,
) -> Unit {
  ignore(src)
  let t = @sf.theme()
  let lent : Array[Lent] = []
  for s in list.unwrap_or([]) {
    if s.drive && s.anywhere && s.home != "" {
      lent.push({ s, root: { path: s.home, name: tr("web-pages.drive.home"), state: "ok" }, home: true })
    }
    for r in s.roots {
      lent.push({ s, root: r, home: false })
    }
  }
  match list {
    None => {
      c.box(h=Px(top), fn() {  }) |> ignore
      waiting(c, 7, None, error)
      return
    }
    Some(l) if lent.length() == 0 && l.iter().any(fn(s) { s.online && !s.overview }) => {
      c.box(h=Px(top), fn() {  }) |> ignore
      waiting(c, 7, None, error)
      return
    }
    _ => ()
  }
  if lent.length() == 0 {
    c.box(w=Fill(1.0), pt=top + 56.0, pb=56.0, padx=32.0, gap=12.0, align=ACenter, fn() {
      @sf.icon(c, "folder", size=40.0, color=t.p.subtle) |> ignore
      c.text(
        if lenders.length() > 0 {
          tr("android-misc.files.none.manager")
        } else {
          tr("android-misc.files.none.member")
        },
        size=14.0,
        color=t.p.muted,
        center=true,
        w=Fill(1.0),
        line=20.0,
      )
      |> ignore
    })
    |> ignore
    return
  }
  let rows : Array[FilesItem] = [FTop(top)]
  let mut last = ""
  for l in lent {
    if l.s.station != last {
      last = l.s.station
      rows.push(FHead(l.s))
    }
    rows.push(FRow(l))
  }
  rows.push(FFoot)
  c.list("files", rows.length(), 42.0, fn(i) {
    match rows[i] {
      FTop(h) => c.box(h=Px(h), fn() {  }) |> ignore
      FHead(s) =>
        dv_section(
          c,
          if s.online {
            s.name
          } else {
            fill("web-pages.drive.stationAway", [("name", s.name)])
          },
        )
      FRow(l) => files_row(c, l)
      FFoot => c.box(h=Px(foot), fn() {  }) |> ignore
    }
  })
  |> ignore
}

///|
/// A folder, as the desktop sidebar's (PlaceRows.kt PlaceRow): its mark (a station's home the server's), its name
/// (faint while the station is away).
fn files_row(c : @ui.Ctx, l : Lent) -> Unit {
  let t = @sf.theme()
  let id = c.id("files/" + l.s.station + "|" + l.root.path)
  if c.clicked(id) {
    app.nav.push(Drive({ station: l.s.station, root: Some(l.root.path), path: "" }))
  }
  c.box(
    dir=Row,
    w=Fill(1.0),
    pl=22.0,
    pr=16.0,
    pt=10.0,
    pb=10.0,
    gap=8.0,
    align=ACenter,
    bg=if c.pressed(id) { @sf.alpha(t.p.text, 0.05) } else { 0L },
    id~,
    fn() {
      c.box(w=Px(16.0), h=Px(22.0), align=ACenter, justify=JCenter, fn() {
        @sf.icon(c, if l.home { "server" } else { "folder" }, size=16.0, color=t.p.muted)
        |> ignore
      })
      |> ignore
      c.box(w=Fill(1.0), opacity=if l.s.online { 1.0 } else { 0.5 }, fn() {
        c.text(l.root.name, size=16.0, color=t.p.text, wrap=false, line=22.0) |> ignore
      })
      |> ignore
    },
  )
  |> ignore
}

// ── a drive's page ───────────────────────────────────────────────────────

///|
/// A page of a station's drive (DriveScreen.kt DriveScreen): `root` None is the drive itself (its one root's contents,
/// or its roots as folders); else the folder `path` under `root`.
pub fn drive_page(c : @ui.Ctx, src : Source, w : Workspace, at : DriveAt) -> Unit {
  let t = @sf.theme()
  let (list, error) = dv_stations(src, w.id)
  let s = match list {
    Some(l) => l.iter().find_first(fn(x) { x.station == at.station })
    None => None
  }
  let can = dv_rights(src, w.id, s)
  dv.building = dv_page_of(Some(at))
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
    match s {
      Some(st) if st.drive => {
        let only = match st.roots {
          [r] if r.state == "ok" => Some(r.path)
          _ => None
        }
        match (match at.root { Some(r) => Some(r); None => only }) {
          Some(root) => folder_page(c, src, st, root, at, at.root is None, can)
          None => roots_page(c, src, at.station, s, error, can)
        }
      }
      _ => roots_page(c, src, at.station, s, error, can)
    }
    dv_sheets(c, src, w, dv_page_of(Some(at)))
  })
  |> ignore
}

///|
/// The drive itself with its roots (DriveScreen.kt RootsPage): each a row, one that cannot be browsed with why in red.
fn roots_page(
  c : @ui.Ctx,
  src : Source,
  station : String,
  s : DvStation?,
  error : String?,
  can : DvRights,
) -> Unit {
  ignore(src)
  let t = @sf.theme()
  let name = match s {
    Some(x) => x.name
    None => ""
  }
  let roots = match s {
    Some(x) if x.drive => Some(x.roots)
    _ => None
  }
  if dv_nav_bar(c, name, tr("android-misc.drive.title"), fn() {
      match roots {
        Some(r) if can.manage && r.length() > 0 =>
          if dv_nav_button(c, "drive-roots", "more") {
            dv_open(c, Roots(station))
          }
        _ => ()
      }
    }) {
    app.nav.pop() |> ignore
  }
  match roots {
    None =>
      if error is Some(_) || (match s { Some(x) => !x.overview; None => true }) {
        waiting(c, 7, None, error)
      } else {
        dv_note(c, tr("android-misc.drive.oldStation"))
      }
    Some([]) =>
      dv_empty(
        c,
        if can.manage {
          tr("android-misc.drive.none.manager")
        } else {
          tr("android-misc.drive.none.member")
        },
        if can.manage { tr("android-misc.drive.choose") } else { "" },
        true,
        fn() { dv_open_picker(c, station, []) },
      )
    Some(rs) =>
      c.list("drive-roots/" + station, rs.length() + 2, 64.0, fn(i) {
        if i == 0 {
          dv_count_line(c, dv_count("android-misc.drive.roots.count", rs.length()))
        } else if i == rs.length() + 1 {
          // 30 over the navigation bar (DriveScreen.kt contentPadding)
          c.box(h=Px(30.0 + nav_foot()), fn() {  }) |> ignore
        } else {
          root_row(c, station, rs[i - 1], i == 1, i == rs.length(), can.manage)
        }
      })
      |> ignore
  }
  ignore(t)
}

///|
/// A folder lent (DriveScreen.kt RootRow): its name, where it is; one that cannot be browsed now with why in red and
/// what to do about it. Held (owners and admins): stop lending it.
fn root_row(c : @ui.Ctx, station : String, r : DvRoot, first : Bool, last : Bool, manage : Bool) -> Unit {
  let t = @sf.theme()
  let id = c.id("root/" + r.path)
  if manage && dv_held(c, id) {
    dv_open(c, RootHeld(station, r))
  }
  if dv_tapped(c, id) {
    app.nav.push(Drive({ station, root: Some(r.path), path: "" }))
  }
  let trouble = dv_trouble(r.state)
  dv_card_row(c, first, last, None, id, fn() {
    c.box(dir=Row, w=Fill(1.0), padx=@sf.card_pad - @sf.list_pad, pady=12.0, gap=12.0, align=ACenter, fn() {
      @sf.icon(c, "folder", size=22.0, color=t.p.muted) |> ignore
      c.box(w=Fill(1.0), fn() {
        c.text(r.name, size=15.0, color=t.p.text, wrap=false, line=20.0) |> ignore
        c.text(r.path, size=12.0, color=t.p.muted, wrap=false, line=16.0) |> ignore
        match trouble {
          Some((what, hint)) => {
            c.box(pt=3.0, fn() {
              c.text(what, size=12.0, weight=600, color=t.p.red, line=16.0, w=Fill(1.0))
              |> ignore
            })
            |> ignore
            c.text(hint, size=12.0, color=t.p.muted, line=16.0, w=Fill(1.0)) |> ignore
          }
          None => ()
        }
      })
      |> ignore
      @sf.icon(c, "chevron-right", size=14.0, color=t.p.subtle) |> ignore
    })
    |> ignore
  })
}

///|
/// A folder's page's items, in order.
priv enum FolderItem {
  Crumbs
  Stale(String)
  Failed(String)
  Reading
  CountLine(String)
  Up(DvUpload, Bool, Bool)
  EmptyFolder
  Row(DvEntry, Bool, Bool)
  Foot
}

///|
/// The key of a folder's page (what is chosen in it).
fn folder_key(station : String, root : String, path : String) -> String {
  station + "\n" + root + "\n" + path
}

///|
/// The folder `at.path` under `root` (DriveScreen.kt FolderPage): back to where it was opened from, its name; where
/// it is under its root (each step a tap away), what it holds in a line, the files going up into it, its entries.
fn folder_page(
  c : @ui.Ctx,
  src : Source,
  s : DvStation,
  root : String,
  at : DriveAt,
  top : Bool,
  can : DvRights,
) -> Unit {
  let t = @sf.theme()
  let station = s.station
  let path = at.path
  let topic = (src.topic)("drive", {
    "station": Json::string(station),
    "root": Json::string(root),
    "path": Json::string(path),
  })
  let value = topic.value
  let error = match topic.error {
    Some(e) => Some(dv_error(e))
    None => None
  }
  let entries = items(value, "entries").map(dv_entry)
  let roots = s.roots
  let name = if path != "" {
    dv_name(path)
  } else if root == s.home && !roots.iter().any(fn(r) { r.path == root }) {
    tr("web-pages.drive.home")
  } else {
    dv_root_label(roots, root)
  }
  let back = if top {
    s.name
  } else if path == "" {
    tr("android-misc.drive.title")
  } else if dv_parent(path) == "" {
    dv_root_label(roots, root)
  } else {
    dv_name(dv_parent(path))
  }
  let here : DriveAt = { station, root: Some(root), path }
  let key = folder_key(station, root, path)
  let refreshing = dv.refreshing.contains(key)
  let reload = fn() {
    if !dv.refreshing.contains(key) {
      dv.refreshing[key] = true
      (src.call)(
        "drive.refresh",
        Json::object({
          "station": Json::string(station),
          "root": Json::string(root),
          "path": Json::string(path),
        }),
        fn(r) {
          dv.refreshing.remove(key)
          (dv_act(c, tr("android-misc.drive.refreshWhat")))(r)
        },
      )
    }
  }
  // the files picked to go up
  dv_take_picked(src, here, entries)
  let shown = dv_shown(src, station, root, path, entries).unwrap_or([])
  let chosen = dv.chosen.get(key).unwrap_or([])
  let choosing = chosen.length() > 0
  let ups = ups.uploads.filter(fn(u) { u.station == station && u.root == root && u.dir == path })
  if choosing {
    let all = chosen.length() == shown.length()
    if dv_nav_bar(c, tr("common.cancel"), dv_count("android-misc.drive.chosen", chosen.length()), fn() {
        c.box(dir=Row, align=ACenter, fn() {
          let id = c.id("drive-choose-all")
          if c.clicked(id) {
            if all {
              dv.chosen.remove(key)
            } else {
              dv.chosen[key] = shown.map(fn(e) { e.name })
            }
          }
          c.box(padx=8.0, pady=6.0, radius=6.0, id~, fn() {
            c.text(
              tr(if all { "android-misc.drive.chooseNone" } else { "android-misc.drive.chooseAll" }),
              size=15.0,
              color=@sf.link_ink(),
              wrap=false,
            )
            |> ignore
            // DriveScreen.kt: clip(Smooth(6)).clickable
            @motion.ripple(c, id, 6.0)
          })
          |> ignore
          if dv_nav_button(c, "drive-chosen-more", "more", said=tr("android-misc.drive.chosenActions")) {
            let picked = entries.filter(fn(e) { chosen.contains(e.name) })
            match picked {
              [] => ()
              [e] => dv_open(c, Entry(here, e, entries.map(fn(x) { x.name })))
              _ => dv_open(c, Chosen(here, picked))
            }
          }
        })
        |> ignore
      }) {
      dv.chosen.remove(key)
    }
  } else if dv_nav_bar(c, back, name, fn() {
      c.box(dir=Row, align=ACenter, fn() {
        let rid = c.id("drive-refresh")
        if c.clicked(rid) {
          reload()
        }
        let rb = c.box(
          w=Px(34.0),
          h=Px(34.0),
          radius=17.0,
          align=ACenter,
          justify=JCenter,
          id=rid,
          fn() {
            if refreshing {
              @sf.spinner(c) |> ignore
            } else {
              @sf.icon(c, "refresh", size=18.0, color=t.p.text) |> ignore
            }
            // DriveScreen.kt: clip(CircleShape).clickable
            @motion.ripple(c, rid, 17.0)
          },
        )
        c.semantics(rb, Button, id=rid, label=tr("android-misc.drive.refresh"))
        if can.write && dv_nav_button(c, "drive-add", "plus", size=20.0, said=tr("android-misc.drive.add")) {
          dv_open(c, Add(here, name, can.manage && top))
        }
        if dv_nav_button(c, "drive-view", "more", said=tr("android-misc.drive.view")) {
          dv_open(c, View(here, can.manage && top))
        }
      })
      |> ignore
    }) {
    app.nav.pop() |> ignore
  }
  let list : Array[FolderItem] = []
  if path != "" {
    list.push(Crumbs)
  }
  match (error, value) {
    (Some(e), Some(_)) => list.push(Stale(e))
    (Some(e), None) => list.push(Failed(e))
    (None, None) => list.push(Reading)
    _ => ()
  }
  if value is Some(_) {
    let count = text(value, "countText") +
      (if flag(value, "truncated") {
        " · " + tr("android-misc.drive.truncated")
      } else {
        ""
      })
    list.push(CountLine(count))
    for i, u in ups {
      list.push(Up(u, i == 0, i == ups.length() - 1))
    }
    if shown.length() == 0 && ups.length() == 0 {
      list.push(EmptyFolder)
    }
    for i, e in shown {
      list.push(Row(e, i == 0, i == shown.length() - 1))
    }
  }
  list.push(Foot)
  c.list("drive/" + key, list.length(), 62.0, fn(i) {
    match list[i] {
      Crumbs => drive_crumbs(c, station, root, dv_root_label(roots, root), path)
      Stale(e) =>
        dv_retry_line(c, fill("android-misc.drive.stale", [("error", e)]), 13.0, t.p.muted, 6.0, reload)
      Failed(e) => dv_retry_line(c, e, 14.0, t.p.red, 12.0, reload)
      Reading => waiting(c, 7, None, None)
      CountLine(s) => dv_count_line(c, s)
      Up(u, first, last) => upload_row(c, src, u, first, last, entries)
      EmptyFolder =>
        dv_empty(
          c,
          tr("android-misc.drive.empty"),
          if can.write { tr("android-misc.drive.upload") } else { "" },
          false,
          fn() { dv_upload(c, here) },
        )
      Row(e, first, last) =>
        entry_row(c, src, here, root, e, first, last, choosing, chosen.contains(e.name), fn() {
          let now = dv.chosen.get(key).unwrap_or([])
          if now.contains(e.name) {
            let left = now.filter(fn(n) { n != e.name })
            if left.length() == 0 {
              dv.chosen.remove(key)
            } else {
              dv.chosen[key] = left
            }
          } else {
            dv.chosen[key] = now + [e.name]
          }
        }, shown)
      // 30 over the navigation bar (DriveScreen.kt contentPadding)
      Foot => c.box(h=Px(30.0 + nav_foot()), fn() {  }) |> ignore
    }
  })
  |> ignore
}

///|
/// The line over a list: what it holds.
fn dv_count_line(c : @ui.Ctx, words : String) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), pl=24.0, pr=20.0, pt=2.0, pb=6.0, fn() {
    c.text(words, size=13.0, color=t.p.muted, wrap=false, line=18.0) |> ignore
  })
  |> ignore
}

///|
/// What could not be read and 重试.
fn dv_retry_line(
  c : @ui.Ctx,
  words : String,
  size : Double,
  color : Int64,
  pady : Double,
  retry : () -> Unit,
) -> Unit {
  let t = @sf.theme()
  c.box(dir=Row, w=Fill(1.0), padx=20.0, pady~, gap=12.0, align=ACenter, fn() {
    c.box(w=Fill(1.0), fn() {
      c.text(words, size~, color~, w=Fill(1.0), line=size + 5.0) |> ignore
    })
    |> ignore
    let id = c.id("drive-retry")
    if c.clicked(id) {
      retry()
    }
    c.box(pad=4.0, radius=6.0, id~, fn() {
      c.text(tr("android-misc.drive.retry"), size~, color=@sf.link_ink(), wrap=false) |> ignore
      // DriveScreen.kt: clip(Smooth(6)).clickable
      @motion.ripple(c, id, 6.0)
    })
    |> ignore
  })
  |> ignore
}

///|
fn dv_note(c : @ui.Ctx, words : String) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), pad=32.0, align=ACenter, fn() {
    c.text(words, size=14.0, color=t.p.muted, center=true, w=Fill(1.0), line=20.0) |> ignore
  })
  |> ignore
}

///|
/// Nothing here (DriveScreen.kt Empty): a folder's mark, why, and what can be done about it.
fn dv_empty(c : @ui.Ctx, words : String, action : String, primary : Bool, act : () -> Unit) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), padx=32.0, pady=56.0, gap=12.0, align=ACenter, fn() {
    @sf.icon(c, "folder", size=40.0, color=t.p.subtle) |> ignore
    c.text(words, size=14.0, color=t.p.muted, center=true, w=Fill(1.0), line=20.0) |> ignore
    if action != "" && dv_button(c, "drive-empty-action", action, primary~) {
      act()
    }
  })
  |> ignore
}

///|
/// Where the folder is under its root (DriveScreen.kt Crumbs): the root, then each folder down to this one, each but
/// the last a way back to it (back where it is in the stack, else opened there).
fn drive_crumbs(c : @ui.Ctx, station : String, root : String, root_name : String, path : String) -> Unit {
  let t = @sf.theme()
  let parts = path.split("/").filter(fn(p) { p != "" }).map(fn(p) { p.to_owned() }).to_array()
  let levels : Array[(String, String)] = [(root_name, "")]
  let mut so_far = ""
  for p in parts {
    so_far = dv_join(so_far, p)
    levels.push((p, so_far))
  }
  // scrolled across when long, its end in view (DriveScreen.kt Crumbs: horizontalScroll, scrollTo(maxValue))
  c.sideways("crumbs/" + station + "/" + root, to_end="/" + path, fn() {
    c.box(dir=Row, pl=21.0, pr=20.0, pt=2.0, pb=4.0, align=ACenter, fn() {
      for i, l in levels {
        let (label, to) = l
        if i > 0 {
          @sf.icon(c, "chevron-right", size=12.0, color=t.p.subtle) |> ignore
        }
        let last = i == levels.length() - 1
        let id = c.id("crumb/\{i}")
        if !last && c.clicked(id) {
          drive_go_back_to(station, root, to)
        }
        c.box(padx=3.0, pady=2.0, radius=6.0, id=if last { 0 } else { id }, fn() {
          c.text(
            label,
            size=13.0,
            weight=if last { 600 } else { 400 },
            color=if last { t.p.text } else { t.p.muted },
            wrap=false,
          )
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// Back to a folder where it is in the stack (the root as the drive's own page with one root has it is the same page);
/// else it opened there.
fn drive_go_back_to(station : String, root : String, path : String) -> Unit {
  let pages = app.nav.pages()
  let mut at = -1
  for i, p in pages {
    match p {
      Drive(d) if d.station == station &&
        d.path == path &&
        (d.root == Some(root) || (d.root is None && path == "")) => at = i
      _ => ()
    }
  }
  if at >= 0 {
    for _ in 0..<(pages.length() - 1 - at) {
      app.nav.pop() |> ignore
    }
  } else {
    app.nav.push(Drive({ station, root: Some(root), path }))
  }
}

///|
/// An entry opened as its kind wants (DriveScreen.kt open): a folder goes in, text and Markdown are read, videos and songs
/// played, anything else goes to the preview (pictures there step to the folder's others).
fn drive_open(c : @ui.Ctx, src : Source, at : DriveAt, root : String, e : DvEntry, shown : Array[DvEntry]) -> Unit {
  let path = dv_join(at.path, e.name)
  match e.kind {
    "folder" => app.nav.push(Drive({ station: at.station, root: Some(root), path }))
    "text" | "markdown" =>
      app.nav.push(DriveRead({ station: at.station, root: Some(root), path }))
    "video" | "audio" =>
      app.nav.push(DrivePlay({ station: at.station, root: Some(root), path }))
    _ => {
      let near = if e.kind == "image" {
        shown.filter(fn(x) { x.kind == "image" }).map(fn(x) { dv_file(at.station, root, at.path, x) })
      } else {
        []
      }
      open_file(c, src, dv_file(at.station, root, at.path, e), near)
    }
  }
}

///|
/// An entry (DriveScreen.kt EntryRow): its kind's mark (choosing: whether it is chosen), its name, its size and time;
/// at its end what is under way on it, how far a text has been read, a folder's chevron.
fn entry_row(
  c : @ui.Ctx,
  src : Source,
  at : DriveAt,
  root : String,
  e : DvEntry,
  first : Bool,
  last : Bool,
  choosing : Bool,
  chosen : Bool,
  toggle : () -> Unit,
  shown : Array[DvEntry],
) -> Unit {
  let t = @sf.theme()
  let path = dv_join(at.path, e.name)
  let busy_key = dv_key("entry", at.station, root, path)
  let busy = dv.busy.contains(busy_key)
  let why = dv.failed.get(busy_key)
  // said for a while from when it is first shown (`after` asks for the frame it goes on)
  let failed = if @kit.after(c, "failed/" + busy_key, why is Some(_), dv_failed_ms) { None } else { why }

  let id = c.id("entry/" + path)
  if !busy {
    if dv_held(c, id) {
      toggle()
    }
    if dv_tapped(c, id) {
      if choosing {
        toggle()
      } else {
        drive_open(c, src, at, root, e, shown)
      }
    }
  }
  let ground = if chosen { Some(@sf.over(dv_surface(), @sf.alpha(t.p.accent, 0.12))) } else { None }
  dv_card_row(c, first, last, ground, if busy { 0 } else { id }, fn() {
    c.box(dir=Row, w=Fill(1.0), padx=@sf.card_pad - @sf.list_pad, pady=11.0, gap=12.0, align=ACenter, fn() {
      if choosing {
        c.box(
          w=Px(22.0),
          h=Px(22.0),
          radius=11.0,
          bg=if chosen { t.p.accent } else { @sf.alpha(t.p.text, 0.08) },
          align=ACenter,
          justify=JCenter,
          fn() {
            if chosen {
              @sf.icon(c, "check", size=14.0, color=t.p.card) |> ignore
            }
          },
        )
        |> ignore
      } else {
        @sf.icon(c, dv_kind_icon(e.kind), size=22.0, color=t.p.muted) |> ignore
      }
      c.box(w=Fill(1.0), fn() {
        c.text(e.name, size=15.0, color=t.p.text, wrap=false, line=20.0) |> ignore
        let line = if e.dir {
          e.time_text
        } else {
          dv_words([e.size_text, e.time_text], " · ")
        }
        if line != "" {
          c.text(line, size=12.0, color=t.p.muted, wrap=false, line=16.0) |> ignore
        }
      })
      |> ignore
      // how far it has come: the core's download of it (a folder's: its zip's, 0 while the station zips it), else a
      // fetch of it to hand to another app
      let fetching = match download_of_drive(src, at.station, root, path) {
        Some(d) if flag(Some(d), "active") => Some((number(Some(d), "progress") * 100.0).floor().to_int())
        _ => dv_fetches.get(dv_fetch_key(at.station, root, path))
      }
      if busy {
        @sf.spinner(c, size=12.0) |> ignore
      } else if failed is Some(_) {
        @sf.icon(c, "info", size=12.0, color=t.p.red) |> ignore
      } else if fetching is Some(n) {
        download_chip(c, dv_fetch_key(at.station, root, path), n)
      } else if e.kind == "text" || e.kind == "markdown" {
        read_share(c, src, at.station, root, path)
      } else if e.dir {
        @sf.icon(c, "chevron-right", size=14.0, color=t.p.subtle) |> ignore
      }
    })
    |> ignore
  })
}

///|
/// How far a text has been read on this device, once opened (DriveScreen.kt ReadShare): grey; 读完 at its end.
fn read_share(c : @ui.Ctx, src : Source, station : String, root : String, path : String) -> Unit {
  let t = @sf.theme()
  let place = (src.topic)("drivePlace", {
    "station": Json::string(station),
    "root": Json::string(root),
    "path": Json::string(path),
  }).value
  let of = number(place, "of")
  if of <= 0.0 {
    return
  }
  let share = dmin(1.0, dmax(0.0, number(place, "at") / of))
  if share < 0.01 {
    return
  }
  c.text(
    if share >= 0.995 {
      tr("android-misc.drive.read.done")
    } else {
      "\{(share * 100.0).to_int()}%"
    },
    size=12.0,
    color=t.p.muted,
    wrap=false,
  )
  |> ignore
}

// ── uploads ──────────────────────────────────────────────────────────────

///|
/// A file going up (DriveScreen.kt UploadRow): its name, how far it has got (a thin bar); its name taken there
/// (替换 or 保留两者), or why it failed (重试); × lets it go.
fn upload_row(
  c : @ui.Ctx,
  src : Source,
  u : DvUpload,
  first : Bool,
  last : Bool,
  entries : Array[DvEntry],
) -> Unit {
  let t = @sf.theme()
  let k = "up/\{u.serial}"
  dv_card_row(c, first, last, None, 0, fn() {
    c.box(dir=Row, w=Fill(1.0), pl=@sf.card_pad - @sf.list_pad, pt=11.0, pb=11.0, gap=12.0, align=ACenter, fn() {
      @sf.icon(c, "upload", size=22.0, color=t.p.muted) |> ignore
      c.box(w=Fill(1.0), fn() {
        c.text(u.name, size=15.0, color=t.p.text, wrap=false, line=20.0) |> ignore
        match u.state {
          "taken" =>
            c.box(dir=Row, gap=12.0, align=ACenter, fn() {
              // (short of room, what is asked is cut short, its two answers kept whole)
              c.text(tr("android-misc.drive.exists.title"), size=12.0, color=t.p.muted, wrap=false, line=16.0, w=Cut)
              |> ignore
              let rid = c.id(k + "/replace")
              let bid = c.id(k + "/both")
              if c.clicked(rid) {
                u.replace = true
                u.state = "waiting"
                dv_pump(src)
              }
              if c.clicked(bid) {
                let others = ups.uploads.filter(fn(x) { x.serial != u.serial && x.dir == u.dir })
                let taken = entries.map(fn(e) { e.name }) + others.map(fn(x) { x.name })
                u.name = dv_free_name(u.name, taken)
                u.state = "waiting"
                dv_pump(src)
              }
              c.box(style=drive_answer, id=rid, fn() {
                c.text(tr("android-misc.drive.exists.replace"), size=12.0, weight=600, color=@sf.link_ink(), wrap=false, line=16.0)
                |> ignore
              })
              |> ignore
              c.box(style=drive_answer, id=bid, fn() {
                c.text(tr("android-misc.drive.exists.both"), size=12.0, weight=600, color=@sf.link_ink(), wrap=false, line=16.0)
                |> ignore
              })
              |> ignore
            })
            |> ignore
          "failed" =>
            c.text(
              fill("android-misc.drive.upload.failed", [("error", u.error)]),
              size=12.0,
              color=t.p.red,
              w=Fill(1.0),
              line=16.0,
            )
            |> ignore
          _ => {
            let size = u.bytes.length()
            c.text(
              fill("android-misc.drive.upload.going", [
                ("sent", @sf.file_size(u.sent.to_double())),
                ("size", @sf.file_size(size.to_double())),
              ]),
              size=12.0,
              color=t.p.muted,
              wrap=false,
              line=16.0,
            )
            |> ignore
            c.box(w=Fill(1.0), pt=5.0, fn() {
              @sf.progress(
                c,
                if size > 0 {
                  Some(u.sent.to_double() / size.to_double())
                } else {
                  None
                },
              )
            })
            |> ignore
          }
        }
      })
      |> ignore
      if u.state == "failed" && dv_row_key(c, k + "/retry", "retry", tr("android-misc.drive.retry")) {
        u.state = "waiting"
        u.error = ""
        u.sent = 0
        dv_pump(src)
      }
      if dv_row_key(c, k + "/cancel", "close", tr("common.cancel")) {
        ups.uploads.retain(fn(x) { x.serial != u.serial })
        if u.state == "going" {
          ups.pumping = false
          dv_pump(src)
        }
      }
    })
    |> ignore
  })
}

///|
/// A key at a row's end (DriveScreen.kt RowKey): 34 round, a 16 icon in grey.
fn dv_row_key(c : @ui.Ctx, key : String, icon : String, said : String) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  // (`said`: what it is to a screen reader, RowKey's contentDescription)
  c.box(
    w=Px(34.0),
    h=Px(34.0),
    radius=17.0,
    align=ACenter,
    justify=JCenter,
    label=said,
    id~,
    fn() {
      @sf.icon(c, icon, size=16.0, color=t.p.muted) |> ignore
      // DriveScreen.kt RowKey: clip(CircleShape).clickable
      @motion.ripple(c, id, 17.0)
    },
  )
  |> ignore
  c.clicked(id)
}

///|
/// An answer to what is asked of an upload (替换, 保留两者): its words whole on their line.
// kept across runs: a value (no field of it changes)
let drive_answer : @ui.Style = @ui.css("row")
