// The files' sidebar (ember web/src/pages/FilesNav.tsx, FilesNav.css.ts), as Finder's: the person's own folders kept at
// hand (个人收藏, of any station: favorites.mbt), then every station of the workspace with a drive, a row each (online or
// not, whether it is this machine, how full its disk is), opened to its places (its home, the home's own folders, its
// disks), then the folders the stations pin for everyone (团队共享). A row opens its folder in the side in front;
// something dragged onto one goes into it, and a folder dragged onto 个人收藏 is kept there (drag.mbt).

///|
/// What the sidebar holds: the stations opened (to their places), each station's places as read (asked once).
priv struct Nav {
  open : @sf.LiveMap[String, Bool]
  places : @sf.LiveMap[String, Array[(String, String, Bool)]]
  asked : @sf.LiveMap[String, Bool]
}

///|
// kept across runs: the sidebar's state (nav_reset puts it back)
let nav : Nav = { open: @sf.LiveMap::new(), places: @sf.LiveMap::new(), asked: @sf.LiveMap::new()}

///|
fn nav_reset() -> Unit {
  nav.open.clear()
  nav.places.clear()
  nav.asked.clear()
}

///|
/// The station this machine is said to be, in place of its host's (a made-up app's: the fixtures show no real
/// machine's).
pub fn set_this_machine(station : String) -> Unit {
  @sfbase.machine_here.val = Some(station)
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
/// The files' sidebar of workspace `ws` (FilesNav): its band (Pin 文件夹, the folders of the one station it can be done
/// on, else which first), then the places.
pub fn files_nav(c : @ui.Ctx, src : Source, ws : String) -> Unit {
  // what is dragged over it moved on or let go
  drag_frame(c, src, ws)
  c.box(style=nav_side, fn() {
    side_top(c)
    let pins = pin_stations(src, ws)
    if pins.length() > 0 {
      nav_action(c, "files/pin", @sf.t("web-pages.drive.addRoot"), Some(fn(_) { add_folder(src, ws, pins) }))
    }
    // (a folder chosen there in the page, on the tape brought over to show it)
    files_places(c, src, ws, top=nav_top, foot=@sf.list_foot_in(Side), go=fn(at) {
      files_go(at)
      @sfbase.show_chosen()
    })
  })
  |> ignore
}

///|
/// What the places' list holds, in order.
priv enum PlaceItem {
  PTop(Double)
  PTrouble(String)
  PReading
  PNone
  PFavorites
  PHeading(String)
  PStation(DvStation)
  PShared(DvStation, DvRoot)
  PFoot(Double)
}

///|
/// The files' places of workspace `ws` (FilesNav's list; the phone's 文件, Files.tsx, is the same list), in the box it
/// is given, scrolling: the person's own folders kept at hand (个人收藏), every station with a drive (its places under
/// it, opened), the folders the stations pin for everyone (团队共享). Its rows a sidebar list's on this screen (the
/// theme's: touch's a finger's list's, a size up, the box's width). `top`, `foot`: room kept at its ends for
/// what is over it;
/// `go`: a folder opened (the side in front, by default).
pub fn files_places(
  c : @ui.Ctx,
  src : Source,
  ws : String,
  top? : Double = 0.0,
  foot? : Double = 0.0,
  go? : (DriveAt) -> Unit = files_go,
) -> Unit {
  drag_frame(c, src, ws)
  let here = this_machine()
  // those with a drive, this machine's first, then as the workspace lists them
  let (known, error) = drive_stations(src, ws)
  let stations = known.unwrap_or([])
  // (what the stations pin and the favourites' stations are among those with a drive: the one list read)
  let views = stations
  let rows : Array[PlaceItem] = [PTop(top)]
  match (known, error) {
    (None, Some(e)) => rows.push(PTrouble(e))
    _ => ()
  }
  if known is Some(_) && stations.length() == 0 {
    rows.push(PNone)
  }
  rows.push(PFavorites)
  // (while they are read, the stations to come in their bones where they will be)
  if known is None && error is None {
    rows.push(PReading)
  }
  if stations.length() > 0 {
    rows.push(PHeading("Station"))
  }
  for s in stations {
    rows.push(PStation(s))
  }
  let pinned : Array[PlaceItem] = []
  for s in views {
    for r in s.roots {
      pinned.push(PShared(s, r))
    }
  }
  if pinned.length() > 0 {
    rows.push(PHeading(@sf.t("web-pages.files.shared")))
    rows.append(pinned)
  }
  rows.push(PFoot(foot))
  c.box(style=@sf.theme().chat_list.side_list, fn() {
    c.list("files/places/" + ws, rows.length(), place_est, fn(i) {
      match rows[i] {
        PTop(h) | PFoot(h) => c.box(style=@ui.style(h=Fixed(h)), fn() {  }) |> ignore
        PTrouble(e) => c.text(e, style=nav_trouble) |> ignore
        PReading => @sf.waiting(c, fn() { places_sample(c) })
        PNone =>
          c.box(style=nav_note, fn() { c.text(@sf.t("web-main.rail.filesNone"), style=nav_meta()) |> ignore }) |> ignore
        PFavorites => places_favorites(c, src, ws, views, go)
        PHeading(h) => @sf.list_heading(c, h, Side)
        PStation(s) => {
          let more = i + 1 < rows.length() && rows[i + 1] is PStation(_)
          station_row(c, src, s, s.station == here, dv_rights(src, ws, Some(s)).write, more, go)
        }
        PShared(s, r) => {
          let t = @sf.theme()
          let name = if r.name != "" { r.name } else { dv_name(r.path) }
          let into : DriveAt = { station: s.station, root: Some(r.path), path: "" }
          fdrag_side_row(c, "shared/" + s.station + "/" + r.path, into, name, dv_rights(src, ws, Some(s)).write, s.transfers, fn() {
            if nav_row(
                c,
                "files/shared/" + s.station + "/" + r.path,
                place_lit(s.station, r.path, ""),
                fn() {
                  @sf.icon(c, "pin", size=nav_icon, color=t.p.muted) |> ignore
                  nav_words(c, name, color?=if s.online { None } else { Some(t.p.muted) })
                  c.text(s.name, style=nav_meta(), allow_ellipsis=true) |> ignore
                },
                more=i + 1 < rows.length() && rows[i + 1] is PShared(_),
              ) {
              go(into)
            }
          })
        }
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// Whether the folder is the one shown (the side in front: the stack's top), its row lit.
fn place_lit(station : String, root : String, path : String) -> Bool {
  match app.nav.top() {
    Drive(h) => h.station == station && h.root == Some(root) && h.path == path
    _ => false
  }
}

///|
/// 个人收藏 (the person's own folders kept at hand, of any station): a folder dragged onto it kept there; none yet, where
/// they go.
fn places_favorites(
  c : @ui.Ctx,
  src : Source,
  ws : String,
  views : Array[DvStation],
  go : (DriveAt) -> Unit,
) -> Unit {
  let t = @sf.theme()
  let favs = favorites(src, ws)
  let kid = c.id("files/keep")
  let keeping = fdrag_target(c, kid, "keep", None, "", true, true, 0, outside=false) is Some(_)
  c.box(style=if keeping { keep_on } else { keep_off }, id=kid, fn() {
    @sf.list_heading(c, @sf.t("web-pages.files.favorites"), Side)
    if favs.length() == 0 {
      c.box(style=@sf.theme().chat_list.side_hint, fn() {
        @sf.icon(c, "star", size=nav_icon, color=t.p.subtle) |> ignore
        c.text(@sf.t("web-pages.files.favoritesHint"), style=nav_meta()) |> ignore
      })
      |> ignore
    }
    for k, f in favs {
      match views.iter().find_first(fn(x) { x.station == f.station }) {
        Some(st) => {
          let place = f.station + "/" + f.root + "/" + f.path
          let rid = c.id("files/unfav/" + place)
          let into : DriveAt = { station: f.station, root: Some(f.root), path: f.path }
          fdrag_side_row(c, "fav/" + place, into, f.name, dv_rights(src, ws, Some(st)).write, st.transfers, fn() {
            if c.clicked(rid) {
              favorite_remove(src, ws, f.station, f.root, f.path)
            } else if nav_row(
                c,
                "files/fav/" + place,
                place_lit(f.station, f.root, f.path),
                fn() {
                  @sf.icon(c, "folder", size=nav_icon, color=t.p.muted) |> ignore
                  nav_words(c, f.name, color?=if st.online { None } else { Some(t.p.muted) })
                  c.text(st.name, style=nav_meta(), allow_ellipsis=true) |> ignore
                  let ub = c.box(style=unkeep(), id=rid, fn() {
                    @sf.icon(c, "close", size=nav_icon, color=t.p.subtle) |> ignore
                  })
                  c.semantics(ub, Button, id=rid, label=@sf.t("web-pages.files.unfavorite", args=[("name", f.name)]))
                },
                more=k + 1 < favs.length(),
              ) {
              go(into)
            }
          })
        }
        None => ()
      }
    }
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
  more : Bool,
  go : (DriveAt) -> Unit,
) -> Unit {
  let t = @sf.theme()
  let did = c.id("files/station-open/" + s.station)
  if c.clicked(did) {
    if nav.open.contains(s.station) {
      nav.open.remove(s.station)
    } else {
      nav.open[s.station] = true
    }
  }
  let open = nav.open.contains(s.station)
  let start = drive_start(s)
  // (its places' rows under it while opened)
  let under = open &&
    (if s.anywhere { nav.places.get(s.station).unwrap_or([]).length() > 0 } else { s.roots.length() > 0 })
  let row = fn() {
    if nav_row(
        c,
        "files/station/" + s.station,
        match start {
          Some(r) => place_lit(s.station, r, "")
          None => false
        },
        fn() {
          let d = c.box(style=disclosure(), id=did, fn() {
            @sf.icon(c, if open { "chevron-down" } else { "chevron-right" }, size=nav_icon, color=t.p.subtle) |> ignore
          })
          c.semantics(
            d,
            Button,
            id=did,
            label=@sf.t(if open { "web-pages.files.collapse" } else { "web-pages.files.expand" }, args=[("name", s.name)]),
            expanded=open,
          )
          @sf.station_icon(c, s.emoji, s.icon, nav_icon, t.p.muted, here~)
          nav_words(c, s.name, color?=if s.online { None } else { Some(t.p.muted) })
          if here {
            c.box(style=here_chip, fn() { c.text(@sf.t("web-pages.files.thisMachine"), style=here_words) |> ignore })
            |> ignore
          }
          if s.online {
            disk_bar(c, s)
          } else {
            c.text(@sf.t("web-pages.stations.offline"), style=nav_meta()) |> ignore
          }
        },
        more=under,
      ) &&
      !c.clicked(did) {
      match start {
        Some(r) => go({ station: s.station, root: Some(r), path: "" })
        None => ()
      }
    }
  }
  nav_apart(c, more, fn() {
    c.box(style=station_item, fn() {
      match start {
        Some(r) => fdrag_side_row(c, "station/" + s.station, { station: s.station, root: Some(r), path: "" }, s.name, write, s.transfers, row)
        None => row()
      }
      if open {
        station_places(c, src, s, write, go)
      }
    })
    |> ignore
  })
}

///|
/// The stations to come while they are read (the library's Waiting, in its bones): their heading and two made-up
/// stations' rows, as station_row draws them.
fn places_sample(c : @ui.Ctx) -> Unit {
  @sf.list_heading(c, "Station", Side)
  for i, n in [5, 3] {
    let s = @sfbase.dv_station({
      "station": Json::string("sample/" + i.to_string()),
      "name": Json::string(@sf.sample_words(n)),
      "online": true,
      "overview": { "disk": { "totalBytes": 2.0, "freeBytes": 1.0 } },
    })
    station_row(c, @sfbase.sample_source, s, false, false, i == 0, fn(_) {  })
  }
}

///|
/// A station's places, under its row opened: as its drive offers them to one who browses everywhere (its home, the
/// home's own folders, its disks: read as its row opens), else the folders it pins.
fn station_places(
  c : @ui.Ctx,
  src : Source,
  s : DvStation,
  write : Bool,
  go : (DriveAt) -> Unit,
) -> Unit {
  let t = @sf.theme()
  let read = if s.anywhere { station_places_read(c, src, s) } else { None }
  let places = if s.anywhere {
    read.unwrap_or([])
  } else {
    s.roots.map(fn(r) { (r.name, r.path, false) })
  }
  if s.anywhere && read is None {
    c.box(style=nav_note, fn() { c.text(@sf.t("web-pages.files.reading"), style=nav_meta()) |> ignore }) |> ignore
  }
  c.box(style=places_in, fn() {
    for k, p in places {
      let (name, path, disk) = p
      let into : DriveAt = { station: s.station, root: Some(path), path: "" }
      fdrag_side_row(c, "place/" + s.station + "/" + path, into, name, write, s.transfers, fn() {
        if nav_row(
            c,
            "files/place/" + s.station + "/" + path,
            place_lit(s.station, path, ""),
            fn() {
              @sf.icon(c, if disk { "disk" } else { "folder" }, size=nav_icon, color=t.p.muted) |> ignore
              nav_words(c, name, color?=if s.online { None } else { Some(t.p.muted) })
            },
            more=k + 1 < places.length(),
          ) {
          go(into)
        }
      })
    }
  })
  |> ignore
}

///|
/// The places a station's drive offers one who browses everywhere (its home, the home's own folders, its disks: each
/// its name, path, whether a disk), asked once and kept; None while they are read.
fn station_places_read(c : @ui.Ctx, src : Source, s : DvStation) -> Array[(String, String, Bool)]? {
  if !nav.asked.contains(s.station) {
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
  nav.places.get(s.station)
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
  // (what is left of it in words, over it while it is pointed at: FilesNav.tsx DiskBar's tip)
  let id = c.id("files-disk/" + s.station)
  let bar = c.box(style=disk_track, id~, taps=false, points=true, fn() { c.box(style=part, fn() {  }) |> ignore })
  let gb = s.disk_free / 1.0e9
  let left = if s.disk_free >= 1.0e11 { gb.round().to_int().to_string() } else { @sf.to_fixed(gb, 1) }
  let said = @sf.t("web-pages.files.diskLeft", args=[("free", left + " GB"), ("percent", (used * 100.0).round().to_int().to_string())])
  c.semantics(bar, Image, label=said)
  @sf.tip(c, "files-disk/" + s.station + "/tip", id, said)
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
/// The list 4 under the band (Sidebar.css.ts navList).
let nav_top : Double = 4.0

///|
/// A station's row and its places under it, one item of the list.
// kept across runs: a value (no field of it changes)
let station_item : @ui.Style = @ui.css("w=Full")

///|
/// A row of the list as a guess at its height, before it is laid out.
let place_est : Double = 36.0

///|
// kept across runs: a value (no field of it changes)
let nav_trouble : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, wrap=false)

///|
/// The list's words in place of rows (empty, reading), 8 by 10 in.
// kept across runs: a value (no field of it changes)
let nav_note : @ui.Style = @ui.css("w=Full px=S2_5 py=S2")

///|
/// 个人收藏 (keep): ringed while a folder dragged over it would be kept there.
// kept across runs: a value (no field of it changes)
let keep_off : @ui.Style = @ui.css("w=Full radius=Xl")

///|
// kept across runs: a value (no field of it changes)
let keep_on : @ui.Style = keep_off.then(@ui.css("border=B1 border_color=Accent"))

///|
/// A favourite's remove (unkeep): 20 across, round, in the middle of its row's end (a sidebar's row as high as a row
/// at least, row_least: a capsule) as far in as makes it concentric with it (capsule_in: 8 in a row 36 high), past the
/// row's 10. (Its row was 32 high when this was said once: 6 in a row 36 high since rows' least height, its corner
/// none of the row's.)
fn unkeep() -> @ui.Style {
  let corner = @sf.row_least() / 2.0
  let off = @sf.capsule_in(corner, unkeep_side, room=corner) - unkeep_row_pad
  unkeep_look.then(@ui.style(mr=@sf.room_of(off)))
}

///|
// kept across runs: a value (no field of it changes)
let unkeep_look : @ui.Style = @ui.css("w=S5 h=S5 align=ACenter justify=JCenter radius=Full hovered{bg=Hover}")

///|
let unkeep_row_pad : Double = 10.0

///|
let unkeep_side : Double = 20.0

///|
/// A station's disclosure: its chevron 16 across, its box as wide as makes it a press's room inside its row (whose sides
/// are the band's pad in: 20 with touch), the chevron in its middle.
fn disclosure() -> @ui.Style {
  let w = dmax(disclosure_side, @ui.room_least() - 2.0 * @sf.theme().chat_list.band_pad)
  disclosure_look.then(@ui.style(w=Fixed(w)))
}

///|
let disclosure_side : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let disclosure_look : @ui.Style = @ui.css("h=S4 align=ACenter justify=JCenter")

///|
/// This machine (here): a pill on the accent's ground, its words small.
// kept across runs: a value (no field of it changes)
let here_chip : @ui.Style = @ui.css("px=S1_25 radius=Full bg=AccentBg")

///|
// kept across runs: a value (no field of it changes)
let here_words : @ui.TextStyle = @ui.text_style(size=Caption, color=AccentText, wrap=false)

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
