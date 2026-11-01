// The files' sidebar (ember web/src/pages/FilesNav.tsx, FilesNav.css.ts), as Finder's: the person's own folders kept at
// hand (个人收藏, of any station: favorites.mbt, including old pins), then every station of the workspace with a drive,
// opened to its places. A row opens its folder in the side in front; something dragged onto one goes into it, and a
// folder dragged onto 个人收藏 is kept there (drag.mbt).

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
  places_rows.clear()
  places_keys.clear()
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
/// The files' sidebar of workspace `ws`: its add-favorite action, then the places.
pub fn files_nav(c : @ui.Ctx, src : Source, ws : String) -> Unit {
  // what is dragged over it moved on or let go
  drag_frame(c, src, ws)
  c.box(style=nav_side, fn() {
    side_top(c)
    let stations = favorite_stations(src, ws)
    if stations.length() > 0 {
      nav_action(c, "files/pin", @sf.t("web-pages.files.addFavorite"), Some(fn(_) { add_favorite_folder(src, ws, stations) }))
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
  PFavoriteHead
  PFavoriteHint
  PFavorite(Favorite, DvStation, Bool)
  PHeading(String)
  PStation(DvStation)
  PFoot(Double)
}

///|
/// Each places list keeps its own rows and their identities, so favorites enter and leave where they are.
// kept across runs: put back by nav_reset
let places_rows : Map[String, @ui.ListRows[PlaceItem]] = {}

///|
// kept across runs: put back by nav_reset
let places_keys : Map[String, Array[String]] = {}

///|
fn places_rows_of(ws : String) -> @ui.ListRows[PlaceItem] {
  match places_rows.get(ws) {
    Some(rows) => rows
    None => {
      let rows = @ui.ListRows::new()
      places_rows[ws] = rows
      rows
    }
  }
}

///|
/// The files' places of workspace `ws` (FilesNav's list; the phone's 文件, Files.tsx, is the same list), in the box it
/// is given, scrolling: the person's folders kept at hand, then every station with a drive. Its rows a sidebar list's on this screen (the
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
  let favs = favorites_in(src, ws, stations)
  let visible : Array[(Favorite, DvStation)] = []
  for f in favs {
    match stations.iter().find_first(fn(s) { s.station == f.station }) {
      Some(s) => visible.push((f, s))
      None => ()
    }
  }
  let rows : Array[PlaceItem] = [PTop(top)]
  match (known, error) {
    (None, Some(e)) => rows.push(PTrouble(e))
    _ => ()
  }
  if known is Some(_) && stations.length() == 0 {
    rows.push(PNone)
  }
  rows.push(PFavoriteHead)
  if favs.is_empty() {
    rows.push(PFavoriteHint)
  }
  for i, (f, s) in visible {
    rows.push(PFavorite(f, s, i + 1 < visible.length()))
  }
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
  rows.push(PFoot(foot))
  // The same workspace's places can be shown in different panes; each list owns its motion.
  let list_id = c.id("files/places/" + ws).to_string()
  let keys = rows.map(fn(row) {
    match row {
      PTop(_) => "top"
      PTrouble(_) => "trouble"
      PReading => "reading"
      PNone => "none"
      PFavoriteHead => "favorite-head"
      PFavoriteHint => "favorite-hint"
      PFavorite(f, _, _) => "favorite/" + f.station + "\u{1}" + favorite_path(f.root, f.path)
      PHeading(h) => "heading/" + h
      PStation(s) => "station/" + s.station
      PFoot(_) => "foot"
    }
  })
  let content = keys.filter(fn(k) { k.has_prefix("favorite/") || k.has_prefix("station/") })
  let before = places_keys.get(list_id).unwrap_or([])
  places_keys[list_id] = content
  let lr = places_rows_of(list_id)
  let (rows, shown_keys) = lr.rows(
    c,
    keys,
    rows,
    fn(row) {
      match row {
        PFavorite(_, _, more) => if more { "more" } else { "last" }
        _ => ""
      }
    },
    watched=content.iter().any(fn(k) { before.contains(k) }),
  )
  c.box(style=@sf.theme().chat_list.side_list, fn() {
    c.list("files/places/" + ws, rows.length(), place_est, fn(i) {
      let box = c.box(style=@sf.full_width, fn() {
        match rows[i] {
          PTop(h) | PFoot(h) => c.box(style=@ui.style(h=Fixed(h)), fn() {  }) |> ignore
          PTrouble(e) => c.text(e, style=nav_trouble) |> ignore
          PReading => @sf.waiting(c, fn() { places_sample(c) })
          PNone =>
            c.box(style=nav_note, fn() { c.text(@sf.t("web-main.rail.filesNone"), style=nav_meta()) |> ignore }) |> ignore
          PFavoriteHead => favorite_drop(c, "head", fn() { @sf.list_heading(c, @sf.t("web-pages.files.favorites"), Side) })
          PFavoriteHint => favorite_drop(c, "hint", fn() {
            c.box(style=@sf.theme().chat_list.side_hint, fn() {
              @sf.icon(c, "star", size=nav_icon, color=@sf.theme().p.subtle) |> ignore
              c.text(@sf.t("web-pages.files.favoritesHint"), style=nav_meta()) |> ignore
            })
            |> ignore
          })
          PFavorite(f, s, more) => favorite_row(c, src, ws, f, s, more, go)
          PHeading(h) => @sf.list_heading(c, h, Side)
          PStation(s) => {
            let more = i + 1 < rows.length() && rows[i + 1] is PStation(_)
            station_row(c, src, s, s.station == here, dv_rights(src, ws, Some(s)).write, more, go)
          }
        }
      })
      lr.enter(c, box, shown_keys[i])
      lr.leave(c, box, shown_keys[i])
    }, sized=lr.sized())
    |> ignore
  })
  |> ignore
}

///|
/// Whether the folder is the one shown (the side in front: the stack's top), its row lit.
fn place_lit(station : String, root : String, path : String) -> Bool {
  match app.nav.top() {
    Drive(h) =>
      if h.station != station {
        false
      } else {
        match h.root {
          Some(r) => favorite_same_path(r, h.path, root, path)
          None => false
        }
      }
    _ => false
  }
}

///|
/// A part of 个人收藏 takes a folder dragged onto it; a favorite's own drop target takes precedence.
fn favorite_drop(c : @ui.Ctx, key : String, body : () -> Unit) -> Unit {
  let kid = c.id("files/keep/" + key)
  let keeping = fdrag_target(c, kid, "keep/" + key, None, "", true, true, 0, outside=false) is Some(_)
  c.box(style=if keeping { keep_on } else { keep_off }, id=kid, body) |> ignore
}

///|
/// One favorite: its row opens the folder; a hold or right click offers to remove it. A pointer also gets a remove key.
fn favorite_row(
  c : @ui.Ctx,
  src : Source,
  ws : String,
  f : Favorite,
  st : DvStation,
  more : Bool,
  go : (DriveAt) -> Unit,
) -> Unit {
  let t = @sf.theme()
  let place = f.station + "/" + f.root + "/" + f.path
  let rid = c.id("files/unfav/" + place)
  let old_root = st.roots.iter().find_first(fn(r) { favorite_same_path(f.root, f.path, r.path, "") })
  // Preserve the root used by older station integrations that can only read configured roots.
  let into : DriveAt = match old_root {
    Some(r) => { station: f.station, root: Some(r.path), path: "" }
    None => { station: f.station, root: Some(f.root), path: f.path }
  }
  favorite_drop(c, "favorite/" + place, fn() {
    fdrag_side_row(c, "fav/" + place, into, f.name, dv_rights(src, ws, Some(st)).write, st.transfers, fn() {
      let key = "files/fav/" + place
      let id = c.id(key)
      let label = @sf.t("web-pages.files.unfavorite", args=[("name", f.name)])
      match c.menu_asked(id) {
        Some((x, y)) => {
          let held = @sf.menu_held(c, "files/favorite/" + place)
          @sf.menu(
            [Some(@sf.menu_item_of(label, icon="star", fn() { favorite_remove(src, ws, f.station, f.root, f.path) }))],
            from=if held { Of(id) } else { @sf.at_point(x, y) },
            title=f.name,
          )
        }
        None => ()
      }
      let removed = c.clicked(rid)
      let opened = nav_row(
          c,
          key,
          place_lit(f.station, into.root.unwrap_or(""), into.path),
          fn() {
            @sf.icon(c, "folder", size=nav_icon, color=t.p.muted) |> ignore
            nav_words(c, f.name, color?=if st.online { None } else { Some(t.p.muted) })
            c.text(st.name, style=nav_meta(), allow_ellipsis=true) |> ignore
            if !@sf.more_held() {
              c.hand_shown(c.lit(id) || c.lit(rid), fn() {
                let ub = c.box(style=favorite_remove_key(), id=rid, fn() {
                  @sf.icon(c, "close", size=nav_icon, color=t.p.subtle) |> ignore
                })
                c.semantics(ub, Button, id=rid, label~)
                @sf.tip(c, "files/favorite-tip/" + place, rid, label)
              })
            }
          },
          more~,
        )
      if removed {
        favorite_remove(src, ws, f.station, f.root, f.path)
      } else if opened {
        go(into)
      }
    })
  })
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
/// A row key concentric with the side row's rounded end, without increasing the row's height.
fn favorite_remove_key() -> @ui.Style {
  let corner = @sf.row_least() / 2.0
  let inset = @sf.capsule_in(corner, @sf.row_keys_room(1), room=corner)
  @sf.row_key_box.then(@ui.style(mr=@sf.room_of(inset - @sf.theme().chat_list.band_pad)))
}

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
