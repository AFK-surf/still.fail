// The folder picker for the files page and other panels. A favorite belongs to the person using this device;
// choosing one does not change the station's configured folders.

///|
/// The picker's state (it is the one open: presented, its body drawn each frame): the station it shows (`picking`: ""
/// none), the place asked (None: the home), what it holds (and what it held last: its places stay while the next is
/// read), why it could not be read, the ask on its way (`asking`: one asked, not answered yet).
priv struct Picker {
  picking : @signals.Signal[String]
  at : @signals.Signal[String?]
  value : @signals.Signal[Json?]
  last : @signals.Signal[Json?]
  error : @signals.Signal[String]
  denied : @signals.Signal[Bool]
  serial : @signals.Signal[Int]
  asking : @signals.Signal[Bool]
  filter : @ui.Field
}

///|
// kept across runs: the picker's state (dialogs_reset puts it back)
let dialogs : Picker = {
  picking: @signals.signal("", same=fn(a, b) { a == b }),
  at: @signals.signal(None, same=fn(a, b) { physical_equal(a, b) || (a is None && b is None) }),
  value: @signals.signal(None, same=fn(a, b) { physical_equal(a, b) || (a is None && b is None) }),
  last: @signals.signal(None, same=fn(a, b) { physical_equal(a, b) || (a is None && b is None) }),
  error: @signals.signal("", same=fn(a, b) { a == b }),
  denied: @signals.signal(false, same=fn(a, b) { a == b }),
  serial: @signals.signal(0, same=fn(a, b) { a == b }),
  asking: @signals.signal(false, same=fn(a, b) { a == b }),
  filter: @ui.Field::new(),
}

///|
fn dialogs_reset() -> Unit {
  picker_close()
}

///|
fn picker_close() -> Unit {
  // (one open, or one asked, let go: what was under way for it told by the serial; none, nothing changed)
  if @signals.untracked(fn() { dialogs.picking.get() != "" || dialogs.asking.get() }) {
    dialogs.serial.set(dialogs.serial.get() + 1)
  }
  dialogs.picking.set("")
  dialogs.at.set(None)
  dialogs.value.set(None)
  dialogs.last.set(None)
  dialogs.error.set("")
  dialogs.denied.set(false)
  dialogs.asking.set(false)
  dialogs.filter.set("")
}

///|
/// Stations whose folder picker is available. Older station integrations can restrict that picker.
pub fn favorite_stations(src : Source, ws : String) -> Array[DvStation] {
  let manager = dv_rights(src, ws, None).manage
  drive_stations(src, ws).0.unwrap_or([]).filter(fn(s) { s.drive && (manager || s.anywhere) })
}

///|
/// Choose a folder for the person's shortcuts, leaving the station's old pinned folders alone.
pub fn add_favorite_folder(src : Source, ws : String, stations : Array[DvStation], picked? : (Favorite) -> Unit = fn(_) {  }) -> Unit {
  match stations {
    [s] => picker_open(src, ws, s.station, picked)
    [] => ()
    _ =>
      @sf.panel(
        @sf.t("web-pages.files.addFavorite"),
        fn(c, close) {
          let t = @sf.theme()
          // (in a dialog, round rows out to its corners, the last concentric with them: @sf.dialog_rows)
          let (list, row) = @sf.dialog_rows(pick_row_h)
          c.box(style=roots_list.then(list), fn() {
            for s in stations {
              let id = c.id("drive/which/" + s.station)
              if c.clicked(id) {
                close()
                picker_open(src, ws, s.station, picked)
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
        description=@sf.t("web-pages.files.whichFavoriteStation"),
      )
  }
}

///|
/// The picker's folders at `path` (its home when None) asked of the station (`drive.folders`), a later ask superseding
/// one on its way; what it held kept (its places stay while the next is read).
fn picker_go(c : @ui.Ctx, src : Source, station : String, path : String?) -> Unit {
  dialogs.at.set(path)
  match dialogs.value.get() {
    Some(v) => dialogs.last.set(Some(v))
    None => ()
  }
  dialogs.value.set(None)
  dialogs.error.set("")
  dialogs.denied.set(false)
  dialogs.serial.set(dialogs.serial.get() + 1)
  dialogs.filter.set("")
  let serial = dialogs.serial.get()
  dialogs.asking.set(true)
  let params : Map[String, Json] = { "station": Json::string(station) }
  match path {
    Some(p) => params["path"] = Json::string(p)
    None => ()
  }
  c.tell("drive.folders/picker", fn() {
    (src.call)("drive.folders", Json::object(params), fn(r) {
      if serial != dialogs.serial.get() {
        return
      }
      dialogs.asking.set(false)
      match r {
        Ok(v) => {
          dialogs.value.set(Some(v))
          dialogs.last.set(Some(v))
          dialogs.denied.set(flag(Some(v), "unreadable"))
        }
        Err(e) => if text(Some(e), "code") == "permission" { dialogs.denied.set(true)} else { dialogs.error.set(dv_error(e))}
      }
    })
  })
}

///|
/// The picker on `station` of workspace `ws`, at its home (PickerDialog): the way to where it is, a filter; the
/// station's places beside the folders where it is (over them, narrow); the folder shown can be kept as a favorite.
fn picker_open(src : Source, ws : String, station : String, picked : (Favorite) -> Unit) -> Unit {
  picker_close()
  dialogs.picking.set(station)
  @sf.panel(
    @sf.t("web-pages.files.addFavorite"),
    fn(c, _) { picker(c, src, station) },
    from=Unanchored,
    description=@sf.t("web-pages.files.pickFavoriteNote"),
    wide=true,
    foot=fn(c, close) {
      let v = dialogs.value.get()
      let path = text(v, "path")
      let taken = v is Some(_) && favorite_has(favorites(src, ws), station, path, "")
      if @sf.button(c, @sf.t("common.cancel"), key="drive/picker/cancel", tone=Ghost) {
        close()
        picker_close()
      }
      if @sf.button(
          c,
          @sf.t(if taken { "web-pages.files.alreadyFavorite" } else { "web-pages.files.pickFavorite" }),
          key="drive/picker/pick",
          tone=Primary,
          disabled=v is None || taken || dialogs.denied.get(),
        ) {
        let name = dv_root_label([], path)
        close()
        picker_close()
        let f : Favorite = { station, root: path, path: "", name }
        favorite_add(src, ws, f)
        picked(f)
      }
    },
    gone=picker_close,
  )
}

///|
/// The picker put inside something else (a preset's dialog: sfbase folder_browse_*): at `station`'s home.
pub fn folder_browse_open(station : String) -> Unit {
  picker_close()
  dialogs.picking.set(station)
}

///|
/// What it holds, drawn where it is shown, each frame.
pub fn folder_browse_body(c : @ui.Ctx, src : Source, station : String) -> Unit {
  picker(c, src, station)
}

///|
/// The folder it shows: "" while it is read, or one the station may not read.
pub fn folder_browse_here() -> String {
  match dialogs.value.get() {
    Some(v) if !dialogs.denied.get() => text(Some(v), "path")
    _ => ""
  }
}

///|
/// Let go (as it closes).
pub fn folder_browse_close() -> Unit {
  picker_close()
}

///|
/// What the picker on `station` holds, each frame while it is open.
fn picker(c : @ui.Ctx, src : Source, station : String) -> Unit {
  // (closed: what it held last stays drawn as it goes, nothing asked)
  if dialogs.picking.get() != station {
    return
  }
  let t = @sf.theme()
  // (asked once: not again each frame while the answer is on its way)
  if dialogs.value.get() is None && dialogs.error.get() == "" && !dialogs.denied.get() && dialogs.last.get() is None && !dialogs.asking.get() {
    picker_go(c, src, station, dialogs.at.get())
  }
  let narrow = look_of(c) is Narrow
  let v = dialogs.value.get()
  let near = dialogs.last.get()
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
    if !dialogs.denied.get() && dialogs.error.get() == "" {
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
      if dialogs.denied.get() || dialogs.error.get() != "" {
        c.box(style=picker_shut, fn() {
          @sf.icon(c, "folder", size=shut_icon, color=t.p.muted) |> ignore
          c.text(if dialogs.denied.get() { @sf.t("web-pages.drive.pickNeedsAccess") } else { dialogs.error.get() }, style=shut_words) |> ignore
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
  let home = @sfbase.dv_trim_root(home_path)
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
let root_text : @ui.Style = @ui.style(w=@sf.grow, gap=SPx, clip=true)

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
