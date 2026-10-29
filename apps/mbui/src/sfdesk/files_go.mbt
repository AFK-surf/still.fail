// Going somewhere on the files' page (ember web/src/pages/FilesGo.tsx, FilesGo.css.ts): another station from a
// folder's trail (the station's button at its start: the same folder there when it has one, else its home; ⌥ in a new
// tab), and a folder by its path (⌘⇧G, as Finder's 前往文件夹): `mba:~/Projects` names the station before the colon, `~`
// its home, a path without a slash in front is under the folder shown; Tab completes a folder's name, as a terminal
// does. What is typed is worked out by the core (`files.go`).

///|
/// A folder typed by its path, worked out (`files.go`'s Typed): the station, the folder it names, the folder it is in
/// and what is typed of its last part.
priv struct Typed {
  station : String
  abs : String
  parent : String
  partial : String
}

///|
/// ⌘⇧G's dialog (open, what is typed, the line chosen; what the core worked out for what was typed, by what; the
/// folders read where the last part is typed, which were asked) and the station's button whose menu is open.
priv struct Go {
  open : @signals.Signal[Bool]
  field : @ui.Field
  typed : @signals.Signal[String]
  at : @signals.Signal[Int]
  resolved : @signals.Signal[(String, Typed?)?]
  asking : @signals.Signal[String?]
  folders : @signals.Signal[(String, String, Array[String])?]
  asked : @signals.Signal[String]
  switching : @signals.Signal[Int]
  /// its dialog as presented (@sf.last_presented; 0 none)
  mut shown : Int
}

///|
// kept across runs: the dialog's state (go_reset puts it back)
let go : Go = {
  open: @signals.signal(false, same=fn(a, b) { a == b }),
  field: @ui.Field::new(),
  typed: @signals.signal("", same=fn(a, b) { a == b }),
  at: @signals.signal(0, same=fn(a, b) { a == b }),
  resolved: @signals.signal(None),
  asking: @signals.signal(None),
  folders: @signals.signal(None),
  asked: @signals.signal("", same=fn(a, b) { a == b }),
  switching: @signals.signal(0, same=fn(a, b) { a == b }),
  shown: 0,
}

///|
fn go_reset() -> Unit {
  go.open.set(false)
  go.field.set("")
  go.typed.set("")
  go.at.set(0)
  go.resolved.set(None)
  go.asking.set(None)
  go.folders.set(None)
  go.asked.set("")
  go.switching.set(0)
  go.shown = 0
}

///|
/// ⌘⇧G's dialog opened, empty.
pub fn go_to_open() -> Unit {
  go_reset()
  go.open.set(true)
}

///|
fn typed_of(v : Json?) -> Typed? {
  match v {
    Some(Object(_)) => Some({ station: text(v, "station"), abs: text(v, "abs"), parent: text(v, "parent"), partial: text(v, "partial") })
    _ => None
  }
}

///|
/// What is typed worked out by the core, from the folder `from` (`files.go`), answered.
fn go_resolve(src : Source, ws : String, typed : String, from : DriveAt, done : (Typed?) -> Unit) -> Unit {
  (src.call)(
    "files.go",
    {
      "workspace": Json::string(ws),
      "typed": Json::string(typed),
      "station": Json::string(from.station),
      "abs": Json::string(dv_absolute(from.root.unwrap_or(""), from.path)),
    },
    fn(r) {
      match r {
        Ok(v) => done(typed_of(Some(v)))
        Err(_) => ()
      }
    },
  )
}

///|
/// A child of a folder on a station (its own separator: Windows' backslash, else a slash).
fn child_of(folder : String, name : String) -> String {
  let sep = if folder.contains("\\") && !folder.contains("/") { "\\" } else { "/" }
  if folder.has_suffix(sep) {
    folder + name
  } else {
    folder + sep + name
  }
}

///|
/// The folder `abs` of `station` as a place to go: a root for one who browses everywhere, else under the folder it pins
/// that holds it (none: it cannot be gone to).
fn place_of(stations : Array[DvStation], station : String, abs : String) -> DriveAt? {
  match stations.iter().find_first(fn(s) { s.station == station }) {
    Some(s) if s.anywhere => Some({ station, root: Some(abs), path: "" })
    Some(s) =>
      match s.roots.iter().find_first(fn(r) { abs == r.path || abs.has_prefix(r.path + "/") }) {
        Some(r) =>
          Some({
            station,
            root: Some(r.path),
            path: if abs == r.path { "" } else { abs.view(start_offset=r.path.length() + 1).to_string() },
          })
        None => None
      }
    None => None
  }
}

///|
/// ⌘⇧G (GoTo) of workspace `ws` from `here` (the side in front), while it is asked for (go_to_open): the library's
/// dialog (@sf.panel, opened by nothing); closed (Esc, ✕, a press outside), not asked for any more. `to`: a folder
/// gone to.
pub fn go_to(c : @ui.Ctx, src : Source, ws : String, here : DriveAt, to : (DriveAt) -> Unit) -> Unit {
  ignore(c)
  if go.open.get() && go.shown == 0 {
    @sf.panel(
      @sf.t("web-pages.files.goTo"),
      fn(c, _) { go_body(c, src, ws, here, to) },
      from=Unanchored,
      description=@sf.t("web-pages.files.goToNote"),
      gone=fn() {
        go.open.set(false)
        go.shown = 0
      },
    )
    go.shown = @sf.last_presented()
  } else if !go.open.get() && go.shown > 0 {
    // (a folder gone to: down)
    @sf.close_presented_of(go.shown)
    go.shown = 0
  }
}

///|
/// What the dialog holds: a field, where it goes under it; the stations while their name is typed, then the folders
/// whose name starts with what is typed of the last part (Tab completes the one chosen, ↑ / ↓ choose, Enter goes).
fn go_body(c : @ui.Ctx, src : Source, ws : String, here : DriveAt, to : (DriveAt) -> Unit) -> Unit {
  let t = @sf.theme()
  let stations = drive_stations(src, ws).0.unwrap_or([])
  let typed = go.typed.get()
  // what is typed, worked out by the core as it changes (the last answer for what is typed now)
  let asked_for = typed + "\n" + here.station + "\n" + dv_absolute(here.root.unwrap_or(""), here.path)
  if go.asking.get() != Some(asked_for) {
    c.after_build("files-goto/resolve", fn() {
      if go.asking.get() != Some(asked_for) {
        go.asking.set(Some(asked_for))
        go_resolve(src, ws, typed, here, fn(r) { if go.asking.get() == Some(asked_for) { go.resolved.set(Some((typed, r)))} })
      }
    })
  }
  let resolved = match go.resolved.get() {
    Some((_, r)) => r
    None => None
  }
  let named = match resolved {
    Some(r) => stations.iter().find_first(fn(s) { s.station == r.station })
    None => None
  }
  // the folders where the last part is typed, read as the way to it changes
  match (resolved, named) {
    (Some(r), Some(n)) if n.anywhere => {
      let key = r.station + "\n" + r.parent
      if go.asked.get() != key {
        c.after_build("files-goto/folders", fn() {
          if go.asked.get() != key {
            go.asked.set(key)
            (src.call)("drive.folders", { "station": Json::string(r.station), "path": Json::string(r.parent) }, fn(a) {
              if go.asked.get() == key {
                go.folders.set(Some((r.station, r.parent, match a {
                  Ok(v) => items(Some(v), "entries").map(fn(e) { text(Some(e), "name") })
                  Err(_) => []
                })))
              }
            })
          }
        })
      }
    }
    _ => ()
  }
  // the lines: what each says, what Tab puts in, where it goes; the stations while their name is typed (nothing before
  // a colon yet), then folders whose name starts with what is typed
  let rows : Array[(String, String, (String, String)?)] = []
  if typed != "" && !typed.contains(":") && !typed.has_prefix("/") && !typed.has_prefix("~") {
    for s in stations {
      if @sf.lower(s.name).has_prefix(@sf.lower(typed)) {
        rows.push((s.name, @sf.lower(s.name) + ":~/", if s.home != "" { Some((s.station, s.home)) } else { None }))
      }
    }
  }
  match (resolved, named, go.folders.get()) {
    (Some(r), Some(n), Some((fs, fp, names))) if fs == r.station && fp == r.parent => {
      let prefix = if r.station == here.station && !typed.contains(":") { "" } else { @sf.lower(n.name) + ":" }
      let found = names.filter(fn(name) { !name.has_prefix(".") && @sf.lower(name).has_prefix(@sf.lower(r.partial)) })
      for name in found[:if found.length() > go_most { go_most } else { found.length() }] {
        let abs = child_of(r.parent, name)
        rows.push((n.name + " › " + abs, prefix + abs + "/", Some((r.station, abs))))
      }
    }
    _ => ()
  }
  if go.at.get() >= rows.length() {
    go.at.set(if rows.length() > 0 { rows.length() - 1 } else { 0 })
  }
  let open = fn(target : (String, String)?) {
    match target {
      Some((st, abs)) =>
        match place_of(stations, st, abs) {
          Some(p) => {
            go.open.set(false)
            c.blur()
            to(p)
          }
          None => ()
        }
      None => ()
    }
  }
  // Enter: as typed now, whatever came back for what was typed before
  let enter = fn(r : Typed?) {
    let chosen = rows.get(go.at.get())
    match (r, chosen) {
      (Some(r), Some((_, _, target))) if r.partial != "" => open(target)
      (Some(r), _) => open(Some((r.station, r.abs)))
      (None, Some((_, _, target))) => open(target)
      _ => ()
    }
  }
  // ↓ ↑ move what is chosen, Tab completes it (read in the dialog: its keys while it is open)
  let mut keyed = false
  if c.key_pressed(@ui.key_code_down, in_field=true) && go.at.get() < rows.length() - 1 {
    go.at.set(go.at.get() + 1)
    keyed = true
  }
  if c.key_pressed(@ui.key_code_up, in_field=true) && go.at.get() > 0 {
    go.at.set(go.at.get() - 1)
    keyed = true
  }
  if c.key_pressed(@ui.key_tab, in_field=true) {
    match rows.get(go.at.get()) {
      Some((_, complete, _)) => {
        go.field.set(complete)
        go.typed.set(complete)
        go.at.set(0)
      }
      None => ()
    }
  }
  c.box(style=go_field_box, fn() {
    let res = c.editor(
      "files-goto/field",
      placeholder=@sf.t("web-pages.files.goToPlaceholder"),
      font_size=go_font,
      line=go_line,
      max_lines=1,
      plain=true,
      color=t.p.text,
      placeholder_color=t.p.subtle,
      caret_color=t.p.accent,
      enter_sends=true,
      field=go.field,
    )
    // (a dialog's only field: it has the keys while it is open, a composer's given up as it opens)
    if !res.focused {
      c.focus_editor("files-goto/field")
    }
    if res.text != go.typed.get() {
      go.typed.set(res.text)
      go.at.set(0)
    }
    match res.submitted {
      Some(words) =>
        match go.resolved.get() {
          Some((was, r)) if was == words => enter(r)
          _ => c.tell("files-goto/enter", fn() { go_resolve(src, ws, words, here, enter) })
        }
      None => ()
    }
  })
  |> ignore
  match (resolved, named) {
    (Some(r), Some(n)) => c.box(style=go_where_box, fn() { c.text(n.name + " › " + r.abs, style=go_where) |> ignore }) |> ignore
    _ => ()
  }
  if rows.length() > 0 {
    let list = c.box(style=go_list, fn() {
      for i, r in rows {
        let (label, _, target) = r
        let id = c.id("files-goto/row/" + label)
        if c.clicked(id) {
          open(target)
        }
        if c.lit(id) {
          go.at.set(i)
        }
        // (moved to by the keys: in view where the dialog scrolls)
        if keyed && i == go.at.get() {
          c.show(id)
        }
        let row = c.box(style=if i == go.at.get() { go_row_on } else { go_row }, id~, fn() {
          @sf.icon(c, "folder", size=go_icon, color=t.p.muted) |> ignore
          c.text(label, style=go_row_words) |> ignore
          if i == go.at.get() {
            c.box(style=go_key_box, fn() { c.text("Tab", style=go_key) |> ignore }) |> ignore
          }
        })
        c.semantics(row, Option, id~, label~, selected=i == go.at.get())
      }
    })
    c.semantics(list, Listbox)
  }
  c.box(style=go_keys_box, fn() { c.text(@sf.t("web-pages.files.goToKeys"), style=go_keys) |> ignore }) |> ignore
}

///|
/// The station's button before a folder's trail (StationSwitch), the folder `f` shows: the workspace's stations with a
/// drive (the one shown checked; one away not to be picked; this machine and the one shown said); picked, the same
/// folder there when it has one, else its home (said so); ⌥ held, in a new tab. `front_it`: what is pressed in a side
/// puts it in front first.
fn station_switch(c : @ui.Ctx, src : Source, f : FolderOf, front_it : () -> Unit) -> Unit {
  let t = @sf.theme()
  let at = f.at
  let here = this_machine()
  let chip = c.id("files/station-switch/" + at.station + "/" + at.root.unwrap_or("") + "/" + at.path)
  let stations = drive_stations(src, f.ws).0.unwrap_or([])
  // picked: the same folder there when it has one, else its home (said so); ⌥ held as it is picked, in a new tab
  let picked = fn(st : String) {
    match stations.iter().find_first(fn(s) { s.station == st }) {
      Some(s) if st != at.station && s.online => {
        let tab = (@ui.mods_held() & @ui.mod_alt) != 0
        let open_at = fn(root : String, same : Bool) {
          if !same {
            say(c, @sf.t("web-pages.files.notThere", args=[("name", s.name)]))
          }
          let pane : DriveAt = { station: st, root: Some(root), path: "" }
          match f.open_in {
            Some(o) if tab => o(pane, false)
            _ => (f.go)(pane, false)
          }
        }
        let abs = dv_absolute(at.root.unwrap_or(""), at.path)
        if s.anywhere && s.home != "" {
          (src.call)("drive.folders", { "station": Json::string(st), "path": Json::string(abs) }, fn(r) {
            match r {
              Ok(v) if !flag(Some(v), "unreadable") => open_at(abs, true)
              _ => open_at(s.home, false)
            }
          })
        } else {
          match s.roots.get(0) {
            Some(r) => open_at(r.path, false)
            None => ()
          }
        }
      }
      _ => ()
    }
  }
  if c.clicked(chip) {
    front_it()
    // the stations with a drive (this machine, the one shown, one away said beside each), the one shown chosen: the
    // library's pick under it
    let choices = stations.map(fn(s) {
      let meta : Array[String] = []
      if s.station == here {
        meta.push(@sf.t("web-pages.files.thisMachine"))
      }
      if s.station == at.station {
        meta.push(@sf.t("web-pages.files.current"))
      }
      if !s.online {
        meta.push(@sf.t("web-pages.stations.offline"))
      }
      // (each by its mark, as the chip names the one shown)
      @sf.choice(s.station, s.name, value=meta.join(" · "), mark=fn(c, size) {
        @sf.station_icon(c, s.emoji, s.icon, size, @sf.theme().p.muted, here=s.station == here)
      })
    })
    @sf.pick(@sf.t("web-pages.files.switchNote"), choices, at.station, picked, from=Of(chip))
    go.switching.set(@sf.last_presented())
  }
  let b = c.box(style=switch_button, id=chip, fn() {
    @sf.station_icon(c, f.st.emoji, f.st.icon, switch_icon, t.p.muted, here=f.st.station == here)
    c.text(f.st.name, style=switch_words) |> ignore
    @sf.icon(c, "chevron-down", size=switch_chevron, color=t.p.muted) |> ignore
  })
  let open = go.switching.get() != 0 && @sf.presented_drawn_of(go.switching.get())
  c.semantics(b, Button, id=chip, label=@sf.t("web-pages.files.switchStation"), expanded=open)
}

///|
/// ⌘⇧G's: at most this many folders listed; its field's
/// words 14 on 20; a row's mark 16; the button's mark 14, its chevron 12.
let go_most : Int = 8

///|
let go_font : Double = 14.0

///|
let go_line : Double = 20.0

///|
let go_icon : Double = 16.0

///|
let switch_icon : Double = 14.0

///|
let switch_chevron : Double = 12.0

///|
/// Its field (goInput): the controls' input, in the mono face's place.
// kept across runs: a value (no field of it changes)
let go_field_box : @ui.Style = @ui.css("row w=Full h=S9 px=S3 align=ACenter radius=Lg bg=Tint")

///|
/// Where it goes (goWhere): 8 under the field, muted, small.
// kept across runs: a value (no field of it changes)
let go_where : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let go_where_box : @ui.Style = @ui.css("w=Full pt=S2")

///|
/// Its lines (goList: 2 apart, 10 under), each (goRow) 7 by 10 in, 8 between its parts, the one chosen on the selected
/// ground.
// kept across runs: a value (no field of it changes)
let go_list : @ui.Style = @ui.css("w=Full gap=S0_5 pt=S2_5")

///|
// kept across runs: a value (no field of it changes)
let go_row : @ui.Style = @ui.css("row w=Full h=S8 px=S2_5 gap=S2 align=ACenter radius=Lg")

///|
// kept across runs: a value (no field of it changes)
let go_row_on : @ui.Style = go_row.then(@ui.css("bg=Selected"))

///|
// kept across runs: a value (no field of it changes)
let go_row_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false, w=@sf.grow)

///|
/// The key (kbd): 5 in at its sides, a hairline round it, its corner 4.
// kept across runs: a value (no field of it changes)
let go_key_box : @ui.Style = @ui.css("px=S1_25 radius=Base border=B1 border_color=Line")

///|
// kept across runs: a value (no field of it changes)
let go_key : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
/// Under the list, its keys (goKeys): 10 under it, faint.
// kept across runs: a value (no field of it changes)
let go_keys : @ui.TextStyle = @ui.text_style(size=Caption, color=Subtle, w=Full)

///|
// kept across runs: a value (no field of it changes)
let go_keys_box : @ui.Style = @ui.css("w=Full pt=S2_5")

///|
/// The station's button (switchButton): 22 high, 7 in, 5 between, a hairline round it on the raised ground, its corner
/// the options'.
// kept across runs: a value (no field of it changes)
let switch_button : @ui.Style = @ui.css(
  #|row h=S6 px=S2 gap=S1_25 align=ACenter radius=Lg bg=Raised border=B1 border_color=Line hovered{bg=Hover}
)

///|
// kept across runs: a value (no field of it changes)
let switch_words : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Fg, wrap=false, w=Cut)

