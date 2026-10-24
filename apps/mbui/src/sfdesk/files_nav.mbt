// The files' sidebar (ember web/src/pages/FilesNav.tsx, FilesNav.css.ts), as Finder's: the person's own folders kept at
// hand (个人收藏, of any station: favorites.mbt), then every station of the workspace with a drive, a row each (online or
// not, whether it is this machine, how full its disk is), opened to its places (its home, the home's own folders, its
// disks), then the folders the stations pin for everyone (团队共享). A row opens its folder in the side in front;
// something dragged onto one goes into it, and a folder dragged onto 个人收藏 is kept there (drag.mbt).

///|
/// What the sidebar holds: the stations opened (to their places), each station's places as read (asked once).
priv struct Nav {
  open : Map[String, Bool]
  places : Map[String, Array[(String, String, Bool)]]
  asked : Map[String, Bool]
  mut here : String?
}

///|
// kept across runs: the sidebar's state (nav_reset puts it back)
let nav : Nav = { open: {}, places: {}, asked: {}, here: None }

///|
fn nav_reset() -> Unit {
  nav.open.clear()
  nav.places.clear()
  nav.asked.clear()
  nav.here = None
}

///|
/// The station this machine is (thisMachine.ts: "<workspace>/<station>"), as its host says (its station's cloud.json),
/// read once; "" where it is none.
pub fn this_machine() -> String {
  match nav.here {
    Some(h) => h
    None => {
      let v = @json.parse(@ui.local_station()) catch { _ => Json::null() }
      let ws = field(Some(v), "workspace")
      let h = if text(ws, "id") != "" && text(ws, "station") != "" {
        text(ws, "id") + "/" + text(ws, "station")
      } else {
        ""
      }
      nav.here = Some(h)
      h
    }
  }
}

///|
/// Where a station's drive starts for its viewer: its home for one who browses everywhere, else the first folder it
/// pins.
pub fn drive_start(s : DvStation) -> String? {
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
/// The files' sidebar of workspace `ws` (FilesNav).
pub fn files_nav(c : @ui.Ctx, src : Source, ws : String) -> Unit {
  // what is dragged over it moved on or let go
  drag_frame(c, src, ws)
  let t = @sf.theme()
  let here = this_machine()
  // those with a drive, this machine's first, then as the workspace lists them
  let (known, error) = drive_stations(src, ws)
  let stations = known.unwrap_or([])
  let views = dv_stations(src, ws).0.unwrap_or([])
  // the folder shown (the side in front), its row lit
  let shown = match app.nav.top() {
    Drive(at) => Some(at)
    _ => None
  }
  let lit = fn(station : String, root : String, path : String) {
    match shown {
      Some(h) => h.station == station && h.root == Some(root) && h.path == path
      None => false
    }
  }
  let writes = fn(s : DvStation) { dv_rights(src, ws, Some(s)).write }
  c.box(style=nav_side, fn() {
    side_top(c)
    c.box(style=nav_list, fn() {
      // Pin 文件夹 (useAddFolder): the folders of the one station it can be done on, else which first
      let pins = pin_stations(src, ws)
      if pins.length() > 0 {
        nav_action(c, "files/pin", @sf.t("web-pages.drive.addRoot"), Some(fn() { add_folder(pins) }))
      }
      match (known, error) {
        (None, Some(e)) => c.text(e, style=nav_trouble) |> ignore
        (None, None) => side_breathing(c)
        _ => ()
      }
      if known is Some(_) && stations.length() == 0 {
        c.box(style=nav_note, fn() { c.text(@sf.t("web-main.rail.filesNone"), style=nav_meta) |> ignore }) |> ignore
      }
      // 个人收藏: a folder dragged onto it kept there
      let favs = favorites(src, ws)
      let kid = c.id("files/keep")
      let keeping = fdrag_target(c, kid, "keep", None, "", true, true, 0, outside=false) is Some(_)
      c.box(style=if keeping { keep_on } else { keep_off }, id=kid, fn() {
        nav_heading(c, @sf.t("web-pages.files.favorites"))
        if favs.length() == 0 {
          c.box(style=nav_hint, fn() {
            @sf.icon(c, "star", size=nav_icon, color=t.p.subtle) |> ignore
            c.text(@sf.t("web-pages.files.favoritesHint"), style=nav_meta) |> ignore
          })
          |> ignore
        }
        for f in favs {
          match views.iter().find_first(fn(x) { x.station == f.station }) {
            Some(st) => {
              let place = f.station + "/" + f.root + "/" + f.path
              let rid = c.id("files/unfav/" + place)
              let into : DriveAt = { station: f.station, root: Some(f.root), path: f.path }
              fdrag_side_row(c, "fav/" + place, into, f.name, writes(st), st.transfers, fn() {
                if c.clicked(rid) {
                  favorite_remove(src, ws, f.station, f.root, f.path)
                } else if nav_row(c, "files/fav/" + place, lit(f.station, f.root, f.path), fn() {
                    @sf.icon(c, "folder", size=nav_icon, color=t.p.muted) |> ignore
                    nav_words(c, f.name, color?=if st.online { None } else { Some(t.p.muted) })
                    c.text(st.name, style=nav_meta) |> ignore
                    let ub = c.box(style=unkeep, id=rid, fn() {
                      @sf.icon(c, "close", size=nav_icon, color=t.p.subtle) |> ignore
                    })
                    c.semantics(ub, Button, id=rid, label=@sf.t("web-pages.files.unfavorite", args=[("name", f.name)]))
                  }) {
                  files_go(into)
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
        nav_heading(c, "Station")
      }
      for s in stations {
        station_row(c, src, s, s.station == here, writes(s), lit)
      }
      // 团队共享: the folders each station pins
      let pinned : Array[(DvStation, DvRoot)] = []
      for s in views {
        for r in s.roots {
          pinned.push((s, r))
        }
      }
      if pinned.length() > 0 {
        nav_heading(c, @sf.t("web-pages.files.shared"))
      }
      for x in pinned {
        let (s, r) = x
        let name = if r.name != "" { r.name } else { dv_name(r.path) }
        let into : DriveAt = { station: s.station, root: Some(r.path), path: "" }
        fdrag_side_row(c, "shared/" + s.station + "/" + r.path, into, name, writes(s), s.transfers, fn() {
          if nav_row(c, "files/shared/" + s.station + "/" + r.path, lit(s.station, r.path, ""), fn() {
              @sf.icon(c, "pin", size=nav_icon, color=t.p.muted) |> ignore
              nav_words(c, name, color?=if s.online { None } else { Some(t.p.muted) })
              c.text(s.name, style=nav_meta) |> ignore
            }) {
            files_go(into)
          }
        })
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A station's row (StationRow): its disclosure, then its home (or the folder it pins, for a read-only member), this
/// machine said, how full its disk is or that it is away; its places under it while opened.
fn station_row(
  c : @ui.Ctx,
  src : Source,
  s : DvStation,
  here : Bool,
  write : Bool,
  lit : (String, String, String) -> Bool,
) -> Unit {
  let t = @sf.theme()
  let open = nav.open.contains(s.station)
  let start = drive_start(s)
  let did = c.id("files/station-open/" + s.station)
  if c.clicked(did) {
    if open {
      nav.open.remove(s.station)
    } else {
      nav.open[s.station] = true
    }
  } else {
    let row = fn() {
      if nav_row(
          c,
          "files/station/" + s.station,
          match start {
            Some(r) => lit(s.station, r, "")
            None => false
          },
          fn() {
            let d = c.box(style=disclosure, id=did, fn() {
              @sf.icon(c, if open { "chevron-down" } else { "chevron-right" }, size=nav_icon, color=t.p.subtle) |> ignore
            })
            c.semantics(
              d,
              Button,
              id=did,
              label=@sf.t(if open { "web-pages.files.collapse" } else { "web-pages.files.expand" }, args=[("name", s.name)]),
              expanded=open,
            )
            @sf.station_icon(c, s.emoji, s.icon, @sf.row_icon, t.p.muted, here~)
            nav_words(c, s.name, color?=if s.online { None } else { Some(t.p.muted) })
            if here {
              c.box(style=here_chip, fn() { c.text(@sf.t("web-pages.files.thisMachine"), style=here_words) |> ignore })
              |> ignore
            }
            if s.online {
              disk_bar(c, s)
            } else {
              c.text(@sf.t("web-pages.stations.offline"), style=nav_meta) |> ignore
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
      Some(r) => fdrag_side_row(c, "station/" + s.station, { station: s.station, root: Some(r), path: "" }, s.name, write, s.transfers, row)
      None => row()
    }
  }
  if !open {
    return
  }
  // its places as its drive offers them to one who browses everywhere, read as its row opens; else what it pins
  if s.anywhere && !nav.asked.contains(s.station) {
    c.after_build("files-places/" + s.station, fn() {
      if !nav.asked.contains(s.station) {
        nav.asked[s.station] = true
        (src.call)("drive.folders", { "station": Json::string(s.station), "path": Json::null() }, fn(r) {
          nav.places[s.station] = match r {
            Ok(v) =>
              items(Some(v), "places").map(fn(p) {
                let p = Some(p)
                (text(p, "name"), text(p, "path"), flag(p, "disk"))
              })
            Err(_) => []
          }
        })
      }
    })
  }
  let places = if s.anywhere {
    nav.places.get(s.station).unwrap_or([])
  } else {
    s.roots.map(fn(r) { (r.name, r.path, false) })
  }
  if s.anywhere && nav.places.get(s.station) is None {
    c.box(style=nav_note, fn() { c.text(@sf.t("web-pages.files.reading"), style=nav_meta) |> ignore }) |> ignore
  }
  c.box(style=places_in, fn() {
    for p in places {
      let (name, path, disk) = p
      let into : DriveAt = { station: s.station, root: Some(path), path: "" }
      fdrag_side_row(c, "place/" + s.station + "/" + path, into, name, write, s.transfers, fn() {
        if nav_row(c, "files/place/" + s.station + "/" + path, lit(s.station, path, ""), fn() {
            @sf.icon(c, if disk { "disk" } else { "folder" }, size=nav_icon, color=t.p.muted) |> ignore
            nav_words(c, name, color?=if s.online { None } else { Some(t.p.muted) })
          }) {
          files_go(into)
        }
      })
    }
  })
  |> ignore
}

///|
/// How full a station's disk is (DiskBar): a short bar, amber past 90%; what it says what is left, in GB, and how much
/// is used.
fn disk_bar(c : @ui.Ctx, s : DvStation) -> Unit {
  if s.disk_total <= 0.0 {
    return
  }
  let used = 1.0 - s.disk_free / s.disk_total
  let part = (if used >= disk_full { disk_warn } else { disk_used }).then(@ui.style(w=Fixed(disk_w * used)))
  let bar = c.box(style=disk_track, fn() { c.box(style=part, fn() {  }) |> ignore })
  let gb = s.disk_free / 1.0e9
  let left = if s.disk_free >= 1.0e11 { gb.round().to_int().to_string() } else { @sf.to_fixed(gb, 1) }
  c.semantics(
    bar,
    Image,
    label=@sf.t("web-pages.files.diskLeft", args=[("free", left + " GB"), ("percent", (used * 100.0).round().to_int().to_string())]),
  )
}

///|
/// A row's mark (16), the disk's bar (28 by 3), past what it is amber (90%).
let nav_icon : Double = 16.0

///|
let disk_w : Double = 28.0

///|
let disk_h : Double = 3.0

///|
let disk_full : Double = 0.9

///|
/// The sidebar (its band's row over its list), the list 8 in at its sides, 4 under the band (Sidebar.css.ts navList).
// kept across runs: a value (no field of it changes)
let nav_side : @ui.Style = @ui.css("w=Full h=Full")

///|
// kept across runs: a value (no field of it changes)
let nav_list : @ui.Style = @ui.css("w=Full h=Full px=S2 pt=S1")

///|
// kept across runs: a value (no field of it changes)
let nav_meta : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let nav_trouble : @ui.TextStyle = @ui.text_style(size=Xs, color=Danger, wrap=false)

///|
/// The list's words in place of rows (empty, reading), 8 by 10 in.
// kept across runs: a value (no field of it changes)
let nav_note : @ui.Style = @ui.css("w=Full px=S2_5 py=S2")

///|
/// Where favourites go while there are none (hint): a row of the list, its mark then its words, faint.
// kept across runs: a value (no field of it changes)
let nav_hint : @ui.Style = @ui.css("row w=Full px=S2_5 py=S1_5 gap=S2 align=ACenter")

///|
/// 个人收藏 (keep): ringed while a folder dragged over it would be kept there.
// kept across runs: a value (no field of it changes)
let keep_off : @ui.Style = @ui.css("w=Full radius=Xl")

///|
// kept across runs: a value (no field of it changes)
let keep_on : @ui.Style = keep_off.then(@ui.css("border=B1 border_color=Accent"))

///|
/// A favourite's remove (unkeep): 20 across.
// kept across runs: a value (no field of it changes)
let unkeep : @ui.Style = @ui.css("w=S5 h=S5 align=ACenter justify=JCenter radius=Base hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let disclosure : @ui.Style = @ui.css("w=S4 h=S4 align=ACenter justify=JCenter")

///|
/// This machine (here): a pill on the accent's ground, its words small.
// kept across runs: a value (no field of it changes)
let here_chip : @ui.Style = @ui.css("px=S1_25 radius=Full bg=AccentBg")

///|
// kept across runs: a value (no field of it changes)
let here_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=AccentText, wrap=false)

///|
/// A station's places, in under it (places: 14; and a row's own 6).
// kept across runs: a value (no field of it changes)
let places_in : @ui.Style = @ui.css("w=Full pl=S5")

///|
// kept across runs: a value (no field of it changes)
let disk_track : @ui.Style = @ui.style(w=Fixed(disk_w), h=Fixed(disk_h), radius=Sm, bg=Line, clip=true)

///|
// kept across runs: a value (no field of it changes)
let disk_used : @ui.Style = @ui.css("h=Full bg=Muted")

///|
// kept across runs: a value (no field of it changes)
let disk_warn : @ui.Style = @ui.css("h=Full bg=Warn")

///|
/// A station's row opened to its places (as a press on its disclosure does).
pub fn nav_open(station : String) -> Unit {
  nav.open[station] = true
}

///|
/// The workspace's stations with a drive as the files' page lists them everywhere (the sidebar, ⌘⇧G, a station's
/// button): this machine's first (`stations {scope, drive: true, here}`, the one topic each of them reads).
pub fn drive_stations(src : Source, ws : String) -> (Array[DvStation]?, String?) {
  dv_drive_stations(src, ws, here=this_machine())
}
