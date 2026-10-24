// The files' page's dialogs about the folders a station pins (ember web/src/pages/Drive.tsx useAddFolder, useManage,
// RootsDialog, PickerDialog; Drive.css.ts rootsList, picker): Pin 文件夹 (the station first, where there are several),
// the folders pinned (each taken back after asking), and the picker of a folder on a station (its places beside its
// folders, the way back as a trail, a filter; entered by a click, the one shown pinned).

///|
/// What is open: which station to pin on (choosing), the folders pinned on a station (`roots`: "" none), one asked to be
/// taken back, the picker on a station (`picking`: "" none); the picker's place asked (None: the home), what it holds
/// (and what it held last: its places stay while the next is read), why it could not be read, the ask on its way.
priv struct Dialogs {
  mut choosing : Bool
  mut roots : String
  mut unpin : DvRoot?
  mut picking : String
  mut at : String?
  mut value : Json?
  mut last : Json?
  mut error : String
  mut denied : Bool
  mut serial : Int
  filter : @ui.Field
}

///|
// kept across runs: the dialogs' state (dialogs_reset puts it back)
let dialogs : Dialogs = {
  choosing: false,
  roots: "",
  unpin: None,
  picking: "",
  at: None,
  value: None,
  last: None,
  error: "",
  denied: false,
  serial: 0,
  filter: @ui.Field::new(),
}

///|
fn dialogs_reset() -> Unit {
  dialogs.choosing = false
  dialogs.roots = ""
  dialogs.unpin = None
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
/// Pin 文件夹 where no one station is in view (the files' sidebar): the picker of the one station, else which first.
pub fn add_folder(stations : Array[DvStation]) -> Unit {
  match stations {
    [s] => picker_open(s.station)
    [] => ()
    _ => dialogs.choosing = true
  }
}

///|
/// The folders a station pins, to take one back or pin another (useManage's RootsDialog).
pub fn manage_roots(station : String) -> Unit {
  dialogs.roots = station
}

///|
/// The picker on `station`, at its home.
fn picker_open(station : String) -> Unit {
  picker_close()
  dialogs.picking = station
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
/// What is wrong with a folder pinned (rootTrouble): what, and what to do; None where nothing is.
fn root_trouble(state : String) -> (String, String)? {
  match state {
    "ok" | "" => None
    "missing" => Some((@sf.t("web-pages.drive.root.missing"), @sf.t("web-pages.drive.root.missingHint")))
    "not_a_directory" => Some((@sf.t("web-pages.drive.root.notFolder"), @sf.t("web-pages.drive.root.notFolderHint")))
    _ => Some((@sf.t("web-pages.drive.root.unreadable"), @sf.t("web-pages.drive.root.unreadableHint")))
  }
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
/// The dialogs of workspace `ws`, whichever is open (drawn over the page).
pub fn drive_dialogs(c : @ui.Ctx, src : Source, ws : String) -> Unit {
  let t = @sf.theme()
  let stations = dv_stations(src, ws).0.unwrap_or([])
  let station_of = fn(id : String) { stations.iter().find_first(fn(s) { s.station == id }) }
  let roots_of = fn(id : String) -> Array[DvRoot] {
    match station_of(id) {
      Some(s) => s.roots
      None => []
    }
  }
  // which station (Pin 文件夹 with several)
  if dialogs.choosing {
    let shown = @sf.dialog(
      c,
      "drive/which",
      true,
      @sf.t("web-pages.drive.addRoot"),
      description=@sf.t("web-pages.drive.whichStation"),
      close_label=@sf.t("common.close"),
      fn() {
        c.box(style=roots_list, fn() {
          for s in pin_stations(src, ws) {
            let id = c.id("drive/which/" + s.station)
            c.cursor(id, Hand)
            if c.clicked(id) {
              dialogs.choosing = false
              picker_open(s.station)
            }
            let b = c.box(style=pick_row, id~, fn() {
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
    )
    if !shown {
      dialogs.choosing = false
    }
  }
  // the folders pinned (RootsDialog)
  if dialogs.roots != "" {
    let station = dialogs.roots
    let roots = roots_of(station)
    let shown = @sf.dialog(
      c,
      "drive/roots",
      true,
      @sf.t("web-pages.drive.manage"),
      description=@sf.t("web-pages.drive.manageNote"),
      close_label=@sf.t("common.close"),
      footer=fn() {
        if @sf.button(c, @sf.t("common.done"), key="drive/roots/done", tone=Ghost) {
          dialogs.roots = ""
        }
        if @sf.button(c, @sf.t("web-pages.drive.addRoot"), key="drive/roots/add", tone=Primary, icon="plus") {
          dialogs.roots = ""
          picker_open(station)
        }
      },
      fn() {
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
                match root_trouble(r.state) {
                  Some((what, hint)) => c.text(what + " · " + hint, style=root_trouble_words) |> ignore
                  None => ()
                }
              })
              |> ignore
              if @sf.icon_button(c, "close", key="drive/roots/unpin/" + r.path, label=@sf.t("web-pages.drive.unshare")) {
                dialogs.unpin = Some(r)
              }
            })
            |> ignore
          }
        })
        |> ignore
      },
    )
    if !shown {
      dialogs.roots = ""
    }
    // a folder taken back, asked first
    let asked = @sf.confirm(
      c,
      "drive/roots/unpin",
      dialogs.unpin is Some(_),
      @sf.t("web-pages.drive.unshareAsk", args=[("name", match dialogs.unpin { Some(r) => r.name; None => "" })]),
      @sf.t("web-pages.drive.unshareText"),
      @sf.t("web-pages.drive.unshare"),
      cancel=@sf.t("common.cancel"),
    )
    match dialogs.unpin {
      Some(r) if asked.confirmed => {
        dialogs.unpin = None
        set_roots(c, src, station, roots.filter(fn(x) { x.path != r.path }).map(fn(x) { x.path }))
      }
      Some(_) if !asked.open => dialogs.unpin = None
      _ => ()
    }
  }
  if dialogs.picking != "" {
    picker(c, src, dialogs.picking, roots_of(dialogs.picking).map(fn(r) { r.path }))
  }
}

///|
/// The picker (PickerDialog): the way to where it is, a filter at its end; the station's places beside the folders
/// where it is (its home's own and its disks, while at the home nothing typed not listed again under their names);
/// entered by a click; 选这个文件夹 pins the one shown (one pinned already, or one the station may not read, is not).
fn picker(c : @ui.Ctx, src : Source, station : String, lent : Array[String]) -> Unit {
  let t = @sf.theme()
  if dialogs.value is None && dialogs.error == "" && !dialogs.denied && dialogs.last is None {
    picker_go(c, src, station, dialogs.at)
  }
  let v = dialogs.value
  let near = dialogs.last
  let path = text(v, "path")
  let taken = v is Some(_) && lent.contains(path)
  let shown = @sf.dialog(
    c,
    "drive/picker",
    true,
    @sf.t("web-pages.drive.pick"),
    description=@sf.t("web-pages.drive.pickNote"),
    wide=true,
    close_label=@sf.t("common.close"),
    footer=fn() {
      if @sf.button(c, @sf.t("common.cancel"), key="drive/picker/cancel", tone=Ghost) {
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
        picker_close()
        set_roots(c, src, station, lent + [path], done=@sf.t("web-pages.drive.shared", args=[("name", name)]))
      }
    },
    fn() {
      // the way here, the filter at its end
      let way = match near {
        Some(h) => way_of(h)
        None => []
      }
      c.box(style=picker_path, fn() {
        c.box(style=picker_crumbs, fn() {
          for i, step in way {
            let (name, p) = step
            if i > 0 {
              @sf.icon(c, "chevron-right", size=crumb_icon, color=t.p.muted) |> ignore
            }
            let last = i == way.length() - 1
            let id = c.id("drive/picker/way/\{i}")
            if !last && c.clicked(id) {
              picker_go(c, src, station, Some(p))
            }
            c.box(style=crumb_box, id=if last { 0 } else { id }, fn() {
              c.text(name, style=if last { crumb_last } else { crumb_words }) |> ignore
            })
            |> ignore
          }
        })
        |> ignore
        if !dialogs.denied && dialogs.error == "" {
          c.box(style=picker_filter, fn() {
            @sf.input(c, "drive/picker/filter", placeholder=@sf.t("web-pages.drive.pickFilter"), field=dialogs.filter) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      let wanted = dialogs.filter.text().trim(chars=" ").to_owned()
      let row = fn(name : String, p : String, unreadable : Bool, disk : Bool, here : Bool) {
        let id = c.id("drive/picker/row/" + p)
        c.cursor(id, Hand)
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
      c.box(style=picker_box, fn() {
        // its places, where it was last (they stay while the next folder is read)
        let places = folders_of(near, "places")
        if places.length() > 0 {
          c.box(style=picker_places, fn() {
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
    },
  )
  if !shown {
    picker_close()
  }
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
let root_trouble_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Warn, wrap=false)

///|
/// A row to pick (pickRow): 40 high at least, 6 by 10 in, 10 between, the field's corner; the list's ground under the
/// pointer, and where the picker is (600).
// kept across runs: a value (no field of it changes)
let pick_row : @ui.Style = @ui.css(
  #|row w=Full min_h=S10 px=S2_5 py=S1_5 gap=S2_5 align=ACenter radius=Lg hovered{bg=ListGround}
)

///|
// kept across runs: a value (no field of it changes)
let pick_row_here : @ui.Style = pick_row.then(@ui.css("bg=ListGround"))

///|
// kept across runs: a value (no field of it changes)
let pick_name : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pick_name_here : @ui.TextStyle = @ui.text_style(size=Sm, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pick_meta : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// The way (pickerPath): the trail, then the filter 200 wide, 12 apart, 10 over the folders, 36 high at least.
// kept across runs: a value (no field of it changes)
let picker_path : @ui.Style = @ui.css("row w=Full min_h=S9 pb=S2_5 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let picker_crumbs : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=SPx, align=ACenter, clip=true)

///|
// kept across runs: a value (no field of it changes)
let crumb_box : @ui.Style = @ui.css("px=S1 py=S0_5 radius=Md")

///|
// kept across runs: a value (no field of it changes)
let crumb_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let crumb_last : @ui.TextStyle = @ui.text_style(size=Xs, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let picker_filter : @ui.Style = @ui.css("w=S48")

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
let picker_head : @ui.TextStyle = @ui.text_style(size=Xs2, color=Muted, wrap=false)

///|
/// A folder the station cannot read (pickerShut): its mark over what to do, in the middle.
// kept across runs: a value (no field of it changes)
let picker_shut : @ui.Style = @ui.css("w=Full h=Full px=S6 gap=S3 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let shut_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, center=true, w=Full)
