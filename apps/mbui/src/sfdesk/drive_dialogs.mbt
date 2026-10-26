// The files' page's dialogs about the folders a station pins (ember web/src/pages/Drive.tsx useAddFolder, useManage,
// RootsDialog, PickerDialog; Drive.css.ts rootsList, picker): Pin 文件夹 (the station first, where there are several),
// the folders pinned (each taken back after asking), and the picker of a folder on a station (its places beside its
// folders, the way back as a trail, a filter; entered by a click, the one shown pinned). Each is the library's panel
// (@sf.panel, opened by nothing): a dialog in the middle of a wide window, a sheet on a narrow one.

///|
/// The picker's state (it is the one open: presented, its body drawn each frame): the station it shows (`picking`: ""
/// none), the place asked (None: the home), what it holds (and what it held last: its places stay while the next is
/// read), why it could not be read, the ask on its way (`asking`: one asked, not answered yet).
priv struct Picker {
  mut picking : String
  mut at : String?
  mut value : Json?
  mut last : Json?
  mut error : String
  mut denied : Bool
  mut serial : Int
  mut asking : Bool
  filter : @ui.Field
}

///|
// kept across runs: the picker's state (dialogs_reset puts it back)
let dialogs : Picker = {
  picking: "",
  at: None,
  value: None,
  last: None,
  error: "",
  denied: false,
  serial: 0,
  asking: false,
  filter: @ui.Field::new(),
}

///|
fn dialogs_reset() -> Unit {
  picker_close()
}

///|
fn picker_close() -> Unit {
  dialogs.picking = ""
  dialogs.at = None
  dialogs.value = None
  dialogs.last = None
  dialogs.error = ""
  dialogs.denied = false
  dialogs.serial += 1
  dialogs.asking = false
  dialogs.filter.set("")
}

///|
/// The stations the viewer may pin a folder on (useAddFolder): those with a drive, for a manager of the workspace any,
/// else those it browses everywhere on.
pub fn pin_stations(src : Source, ws : String) -> Array[DvStation] {
  let manager = dv_rights(src, ws, None).manage
  drive_stations(src, ws).0.unwrap_or([]).filter(fn(s) { s.drive && (manager || s.anywhere) })
}

///|
/// Pin 文件夹 of workspace `ws` where no one station is in view (the files' sidebar): the picker of the one station,
/// else which first (useAddFolder's dialog: the stations, one chosen opening its picker).
pub fn add_folder(src : Source, ws : String, stations : Array[DvStation]) -> Unit {
  match stations {
    [s] => picker_open(src, ws, s.station)
    [] => ()
    _ =>
      @sf.panel(
        @sf.t("web-pages.drive.addRoot"),
        fn(c, close) {
          let t = @sf.theme()
          // (in a dialog, round rows out to its corners, the last concentric with them: @sf.dialog_rows)
          let (list, row) = @sf.dialog_rows(pick_row_h)
          c.box(style=roots_list.then(list), fn() {
            for s in stations {
              let id = c.id("drive/which/" + s.station)
              if c.clicked(id) {
                close()
                picker_open(src, ws, s.station)
              }
              let b = c.box(style=pick_row.then(row), id~, fn() {
                @sf.station_icon(c, s.emoji, s.icon, pick_icon, t.p.muted)
                c.text(s.name, style=pick_name) |> ignore
                if !s.online {
                  c.text(@sf.t("web-pages.stations.offline"), style=pick_meta) |> ignore
                }
              })
              c.semantics(b, Button, id~, label=s.name)
            }
          })
          |> ignore
        },
        from=Unanchored,
        description=@sf.t("web-pages.drive.whichStation"),
      )
  }
}

///|
/// The folders `station` of workspace `ws` pins (useManage's RootsDialog): each to be taken back (asked first), another
/// to be pinned.
pub fn manage_roots(src : Source, ws : String, station : String) -> Unit {
  @sf.panel(
    @sf.t("web-pages.drive.manage"),
    fn(c, _) {
      let t = @sf.theme()
      let st = drive_station_of(src, ws, station)
      let roots = match st {
        Some(s) => s.roots
        None => []
      }
      c.box(style=roots_list, fn() {
        if roots.length() == 0 {
          c.text(@sf.t("web-pages.drive.noneYet"), style=pick_meta) |> ignore
        }
        for r in roots {
          c.box(style=root_line, fn() {
            @sf.icon(c, "folder", size=root_icon, color=t.p.muted) |> ignore
            c.box(style=root_text, fn() {
              c.text(r.name, style=pick_name) |> ignore
              c.text(r.path, style=pick_meta) |> ignore
              match dv_trouble(r.state) {
                Some((what, hint)) => c.text(what + " · " + hint, style=root_trouble_words) |> ignore
                None => ()
              }
            })
            |> ignore
            match st {
              Some(s) if @sf.icon_button(c, "close", key="drive/roots/unpin/" + r.path, label=@sf.t("web-pages.drive.unshare")) =>
                ask_unpin(c, src, s, r)
              _ => ()
            }
          })
          |> ignore
        }
      })
      |> ignore
    },
    from=Unanchored,
    description=@sf.t("web-pages.drive.manageNote"),
    foot=fn(c, close) {
      if @sf.button(c, @sf.t("common.done"), key="drive/roots/done", tone=Ghost) {
        close()
      }
      if @sf.button(c, @sf.t("web-pages.drive.addRoot"), key="drive/roots/add", tone=Primary, icon="plus") {
        close()
        picker_open(src, ws, station)
      }
    },
  )
}

///|
/// Station `id` of workspace `ws`, as the files' pages know it.
fn drive_station_of(src : Source, ws : String, id : String) -> DvStation? {
  dv_stations(src, ws).0.unwrap_or([]).iter().find_first(fn(s) { s.station == id })
}

///|
/// The picker's folders at `path` (its home when None) asked of the station (`drive.folders`), a later ask superseding
/// one on its way; what it held kept (its places stay while the next is read).
fn picker_go(c : @ui.Ctx, src : Source, station : String, path : String?) -> Unit {
  dialogs.at = path
  match dialogs.value {
    Some(v) => dialogs.last = Some(v)
    None => ()
  }
  dialogs.value = None
  dialogs.error = ""
  dialogs.denied = false
  dialogs.serial += 1
  dialogs.filter.set("")
  let serial = dialogs.serial
  dialogs.asking = true
  let params : Map[String, Json] = { "station": Json::string(station) }
  match path {
    Some(p) => params["path"] = Json::string(p)
    None => ()
  }
  c.tell("drive.folders/picker", fn() {
    (src.call)("drive.folders", Json::object(params), fn(r) {
      if serial != dialogs.serial {
        return
      }
      dialogs.asking = false
      match r {
        Ok(v) => {
          dialogs.value = Some(v)
          dialogs.last = Some(v)
          dialogs.denied = flag(Some(v), "unreadable")
        }
        Err(e) => if text(Some(e), "code") == "permission" { dialogs.denied = true } else { dialogs.error = dv_error(e) }
      }
    })
  })
}

///|
/// The station's folders pinned set to `roots` (`drive.setRoots`), said when done.
fn set_roots(c : @ui.Ctx, src : Source, station : String, roots : Array[String], done? : String = "") -> Unit {
  // (told once the frame's builds are over: a press asks it)
  c.tell("drive.setRoots", fn() {
    (src.call)(
      "drive.setRoots",
      { "station": Json::string(station), "roots": Json::array(roots.map(fn(r) { Json::string(r) })) },
      act_done(c, @sf.t("web-pages.drive.rootsWhat"), done~),
    )
  })
}

///|
/// The picker on `station` of workspace `ws`, at its home (PickerDialog): the way to where it is, a filter; the
/// station's places beside the folders where it is (over them, narrow); entered by a click; 选这个文件夹 pins the one
/// shown (one pinned already, or one the station may not read, is not).
fn picker_open(src : Source, ws : String, station : String) -> Unit {
  picker_close()
  dialogs.picking = station
  let lent = fn() {
    match drive_station_of(src, ws, station) {
      Some(s) => s.roots.map(fn(r) { r.path })
      None => []
    }
  }
  @sf.panel(
    @sf.t("web-pages.drive.pick"),
    fn(c, _) { picker(c, src, station) },
    from=Unanchored,
    description=@sf.t("web-pages.drive.pickNote"),
    wide=true,
    foot=fn(c, close) {
      let v = dialogs.value
      let path = text(v, "path")
      let lent = lent()
      let taken = v is Some(_) && lent.contains(path)
      if @sf.button(c, @sf.t("common.cancel"), key="drive/picker/cancel", tone=Ghost) {
        close()
        picker_close()
      }
      if @sf.button(
          c,
          @sf.t(if taken { "web-pages.drive.already" } else { "web-pages.drive.pickThis" }),
          key="drive/picker/pick",
          tone=Primary,
          disabled=v is None || taken || dialogs.denied,
        ) {
        let name = match dv_name(path.trim_end(chars="/\\").to_owned()) {
          "" => path
          n => n
        }
        close()
        picker_close()
        set_roots(c, src, station, lent + [path], done=@sf.t("web-pages.drive.shared", args=[("name", name)]))
      }
    },
    gone=picker_close,
  )
}

///|
/// What the picker on `station` holds, each frame while it is open.
fn picker(c : @ui.Ctx, src : Source, station : String) -> Unit {
  // (closed: what it held last stays drawn as it goes, nothing asked)
  if dialogs.picking != station {
    return
  }
  let t = @sf.theme()
  // (asked once: not again each frame while the answer is on its way)
  if dialogs.value is None && dialogs.error == "" && !dialogs.denied && dialogs.last is None && !dialogs.asking {
    picker_go(c, src, station, dialogs.at)
  }
  let narrow = look_of(c) is Narrow
  let v = dialogs.value
  let near = dialogs.last
  let path = text(v, "path")
  // the way here, the filter at its end (under it, narrow)
  let way = match near {
    Some(h) => way_of(h)
    None => []
  }
  c.box(style=if narrow { picker_path_narrow } else { picker_path }, fn() {
    @sf.way_line(c, "drive/picker/way", way.map(fn(w) { w.0 }), picker_way(), fn(i) {
      picker_go(c, src, station, Some(way[i].1))
    })
    if !dialogs.denied && dialogs.error == "" {
      c.box(style=if narrow { picker_filter_narrow } else { picker_filter }, fn() {
        @sf.input(c, "drive/picker/filter", placeholder=@sf.t("web-pages.drive.pickFilter"), field=dialogs.filter) |> ignore
      })
      |> ignore
    }
  })
  |> ignore
  let wanted = dialogs.filter.text().trim(chars=" ").to_owned()
  let row = fn(name : String, p : String, unreadable : Bool, disk : Bool, here : Bool) {
    let id = c.id("drive/picker/row/" + p)
    if c.clicked(id) {
      picker_go(c, src, station, Some(p))
    }
    let b = c.box(style=if here { pick_row_here } else { pick_row }, id~, fn() {
      @sf.icon(c, if disk { "disk" } else { "folder" }, size=pick_icon, color=t.p.muted) |> ignore
      c.box(style=root_text, fn() {
        c.text(name, style=if here { pick_name_here } else { pick_name }) |> ignore
        if unreadable {
          c.text(@sf.t("web-pages.drive.pickUnreadable"), style=pick_meta) |> ignore
        }
      })
      |> ignore
    })
    c.semantics(b, Button, id~, label=name)
  }
  let folders_of = fn(h : Json?, key : String) {
    items(h, key).map(fn(x) {
      let x = Some(x)
      (text(x, "name"), text(x, "path"), flag(x, "unreadable"), flag(x, "disk"))
    })
  }
  c.box(style=if narrow { picker_box_narrow } else { picker_box }, fn() {
    // its places, where it was last (they stay while the next folder is read)
    let places = folders_of(near, "places")
    if places.length() > 0 {
      c.box(style=if narrow { picker_places_narrow } else { picker_places }, fn() {
        c.text(@sf.t("web-pages.drive.places"), style=picker_head) |> ignore
        let here_at = match v {
          Some(_) => path
          None => match way.last() { Some((_, p)) => p; None => "" }
        }
        for p in places {
          row(p.0, p.1, p.2, p.3, p.1 == here_at)
        }
      })
      |> ignore
    }
    c.box(style=picker_list, fn() {
      if dialogs.denied || dialogs.error != "" {
        c.box(style=picker_shut, fn() {
          @sf.icon(c, "folder", size=shut_icon, color=t.p.muted) |> ignore
          c.text(if dialogs.denied { @sf.t("web-pages.drive.pickNeedsAccess") } else { dialogs.error }, style=shut_words) |> ignore
        })
        |> ignore
      } else {
        match v {
          None => @sf.wait_line(c, @sf.t("common.reading"), key="drive/picker")
          Some(_) => {
            let home = text(v, "home")
            let entries = folders_of(v, "entries")
            // at the home with nothing typed, the usual places (on the left) not listed again
            let shown = entries.filter(fn(e) {
              (wanted == "" || e.0.to_lower().contains(wanted.to_lower())) &&
              !(path == home && wanted == "" && places.iter().any(fn(p) { p.1 == e.1 }))
            })
            if shown.length() == 0 {
              c.text(@sf.t(if wanted != "" { "web-pages.drive.pickNoMatch" } else { "web-pages.drive.noSubfolders" }), style=picker_head) |> ignore
            } else {
              c.text(@sf.t("web-pages.drive.foldersHere"), style=picker_head) |> ignore
              c.list("drive/picker/" + path, shown.length(), pick_row_h, fn(i) {
                let e = shown[i]
                row(e.0, e.1, e.2, e.3, false)
              })
              |> ignore
            }
          }
        }
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The way to the folder a picker shows: as the station says it (its crumbs), else from the home when it is under it,
/// else from the top.
fn way_of(here : Json) -> Array[(String, String)] {
  let h = Some(here)
  let crumbs = items(h, "crumbs")
  if crumbs.length() > 0 {
    return crumbs.map(fn(x) { (text(Some(x), "name"), text(Some(x), "path")) })
  }
  let path = text(h, "path")
  let home_path = text(h, "home")
  let home = home_path.trim_end(chars="/\\").to_owned()
  let under = home != "" && (path == home_path || path.has_prefix(home + "/"))
  let way : Array[(String, String)] = [if under { (@sf.t("web-pages.drive.home"), home_path) } else { ("/", "/") }]
  let mut at = if under { home } else { "" }
  let rest = if under { path.view(start_offset=home.length()).to_owned() } else { path }
  for part in rest.split("/") {
    if part != "" {
      at = at + "/" + part.to_owned()
      way.push((part.to_owned(), at))
    }
  }
  way
}

///|
/// A pick row's mark (18), a folder pinned's (16), the trail's chevrons (12), the shut picker's folder (32), a row's
/// height as the list guesses it (40).
let pick_icon : Double = 18.0

///|
let root_icon : Double = 16.0

///|
let crumb_icon : Double = 12.0

///|
let shut_icon : Double = 32.0

///|
let pick_row_h : Double = 40.0

///|
/// The folders pinned (rootsList: 4 apart), each (rootLine) 8 by 4 in, 12 between its mark, its words and its ×.
// kept across runs: a value (no field of it changes)
let roots_list : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let root_line : @ui.Style = @ui.css("row w=Full px=S1 py=S2 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let root_text : @ui.Style = @ui.style(w=@sf.grow, gap=SPx, clip=true)

///|
// kept across runs: a value (no field of it changes)
let root_trouble_words : @ui.TextStyle = @ui.text_style(size=Meta, color=WarnInk, wrap=false)

///|
/// A row to pick (pickRow): 40 high at least, 6 by 10 in, 10 between, the field's corner; the list's ground under the
/// pointer, and where the picker is (600).
// kept across runs: a value (no field of it changes)
let pick_row : @ui.Style = @ui.css(
  #|row w=Full min_h=S10 px=S2_5 py=S1_5 gap=S2_5 align=ACenter radius=Lg hovered{bg=Hover}
)

///|
// kept across runs: a value (no field of it changes)
let pick_row_here : @ui.Style = pick_row.then(@ui.css("bg=ListGround"))

///|
// kept across runs: a value (no field of it changes)
let pick_name : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pick_name_here : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pick_meta : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// The way (pickerPath): the trail, then the filter 200 wide, 12 apart, 10 over the folders, 36 high at least.
// kept across runs: a value (no field of it changes)
let picker_path : @ui.Style = @ui.css("row w=Full min_h=S9 pb=S2_5 gap=S3 align=ACenter")

///|
/// Its trail (pickerCrumbs): 1 apart, a crumb 4 by 2 in, the way's muted, where it is bold in the words' colour, the
/// chevrons muted (way_line: those between in its … where the line is short).
fn picker_way() -> @sf.WayLook {
  {
    line: picker_trail,
    step: crumb_box,
    words: crumb_words,
    here: crumb_last,
    chevron: crumb_icon,
    chevron_ink: @sf.theme().p.muted,
  }
}

///|
// kept across runs: a value (no field of it changes)
let picker_trail : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=SPx, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let crumb_box : @ui.Style = @ui.css("px=S1 py=S0_5 radius=Md")

///|
// kept across runs: a value (no field of it changes)
let crumb_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let crumb_last : @ui.TextStyle = @ui.text_style(size=Meta, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let picker_filter : @ui.Style = @ui.css("w=S48")

///|
/// Narrow: the filter under the trail, as wide as it; the places over the folders.
// kept across runs: a value (no field of it changes)
let picker_path_narrow : @ui.Style = @ui.css("w=Full pb=S2_5 gap=S2")

///|
// kept across runs: a value (no field of it changes)
let picker_filter_narrow : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let picker_box_narrow : @ui.Style = @ui.css("w=Full h=S96 gap=S3")

///|
// kept across runs: a value (no field of it changes)
let picker_places_narrow : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
/// Its places (180) beside its folders, 12 apart, as high as 420 at most.
// kept across runs: a value (no field of it changes)
let picker_box : @ui.Style = @ui.css("row w=Full h=S96 gap=S3")

///|
// kept across runs: a value (no field of it changes)
let picker_places : @ui.Style = @ui.css("w=S44 h=Full gap=S0_5 clip")

///|
// kept across runs: a value (no field of it changes)
let picker_list : @ui.Style = @ui.style(w=@sf.grow, h=Full, gap=S0_5, clip=true)

///|
/// A part's heading (pickerHead): 4 by 8 in, small, muted.
// kept across runs: a value (no field of it changes)
let picker_head : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
/// A folder the station cannot read (pickerShut): its mark over what to do, in the middle.
// kept across runs: a value (no field of it changes)
let picker_shut : @ui.Style = @ui.css("w=Full h=Full px=S6 gap=S3 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let shut_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, center=true, w=Full)
