// The folder picker (选择文件夹) for the files page's 添加到收藏 and a preset's 浏览文件夹 (sfbase folder_pick_asked): a
// panel of nodes a share of the window tall, the same height from folder to folder. Over its list where it is, in one
// line: the station (its mark and name; where there are others, a press opens a menu of them) and the way from its home,
// each step a way back; under it a quiet filter. Then the folders there, the panel's own list, a row each pressed
// whole to go in (a repository by its letter's tile, a folder, a disk by theirs); at the station's home its disks after
// them. At its foot 新建文件夹 and the button that takes the folder shown. A favorite belongs to the person using this
// device; choosing one does not change the station's configured folders.

///|
/// The picker's state (the one open): the station it shows, the folder asked (None: the home), what it holds (and what
/// it held last: its way stays while the next is read), why it could not be read, whether the station may not read it,
/// the ask on its way (`asking`; `serial`: a later ask supersedes one on its way), the filter's line; and the station
/// its choice names (`picked`: the one pressed from the press, the one shown once it is answered).
priv struct Picker {
  station : @signals.Signal[String]
  picked : @signals.Signal[String]
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
  station: @signals.signal("", same=fn(a, b) { a == b }),
  picked: @signals.signal("", same=fn(a, b) { a == b }),
  at: @signals.signal(None, same=fn(a, b) { a == b }),
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
/// Let go of: what was under way for it told by the serial.
fn picker_close() -> Unit {
  @signals.start_batch()
  if @signals.untracked(fn() { dialogs.station.get() != "" || dialogs.asking.get() }) {
    dialogs.serial.set(dialogs.serial.untracked() + 1)
  }
  dialogs.station.set("")
  dialogs.picked.set("")
  dialogs.at.set(None)
  dialogs.value.set(None)
  dialogs.last.set(None)
  dialogs.error.set("")
  dialogs.denied.set(false)
  dialogs.asking.set(false)
  dialogs.filter.set("")
  @signals.end_batch()
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
    [s] => picker_open(src, ws, s, picked)
    [] => ()
    _ =>
      @sf.panel_nodes(
        @sf.t("web-pages.files.addFavorite"),
        fn(v, close) { which_station(v, src, ws, stations, picked, close) },
        from=Unanchored,
        description=@sf.t("web-pages.files.whichFavoriteStation"),
      )
  }
}

///|
/// Which of `stations` the folder is to be chosen on, in node `v` (the panel's body's): a row each, its mark (a server's
/// where it has none), its name, 离线 after it while it is; pressed, the panel closed and the picker opened on it. The
/// stations are those it was opened with (a panel asked again is another).
fn which_station(
  v : @view.View,
  src : Source,
  ws : String,
  stations : Array[DvStation],
  picked : (Favorite) -> Unit,
  close : () -> Unit,
) -> Unit {
  // (in a dialog, round rows out to its corners, the last concentric with them: @sf.dialog_rows_node)
  let (list, row) = @sf.dialog_rows_node(v, pick_row_h)
  v.box(fn(l) {
    @sf.style_node(l, fn() { roots_list.then(list) })
    for s in stations {
      l.box(fn(r) {
        @sf.style_node(r, fn() { pick_row.then(row) })
        // (the list's ground under the hand: pick_row's hovered)
        r
        .ground(By(fn() { if @sf.lit_node(r) { @sf.theme().p.hover } else { 0L } }))
        .says(Is(Some(@view.said(Button, label=s.name))))
        |> ignore
        @sf.presses_node(r, fn() {
          close()
          picker_open(src, ws, s, picked)
        })
        if @sf.has_station_mark(s.emoji, s.icon) {
          // (a panel's pictures asked for on no page's time on top)
          @sf.station_mark_node(r, fn() { s.emoji }, fn() { s.icon }, pick_icon, fn() { @sf.theme().p.muted }, fn() { 0 })
        } else {
          @sf.icon_node(r, "server", pick_icon, By(fn() { @sf.theme().p.muted })) |> ignore
        }
        @sf.words_node(r, fn() { s.name }, fn() { pick_name }) |> ignore
        if !s.online {
          @sf.words_node(r, fn() { @sf.t("web-pages.stations.offline") }, fn() { pick_meta }) |> ignore
        }
      })
      |> ignore
    }
  })
  |> ignore
}


///|
/// The picker on station `s` of workspace `ws`, at its home: the folder shown kept as a favorite (已收藏 where it is).
fn picker_open(src : Source, ws : String, s : DvStation, picked : (Favorite) -> Unit) -> Unit {
  folder_pick(src, {
    title: @sf.t("web-pages.files.addFavorite"),
    note: @sf.t("web-pages.files.pickFavoriteNote"),
    stations: [{ station: s.station, name: s.name, emoji: s.emoji, icon: s.icon }],
    station: s.station,
    at: "",
    action: fn(_) { @sf.t("web-pages.files.pickFavorite") },
    taken: fn(station, path) { favorite_has(favorites(src, ws), station, path, "") },
    taken_words: @sf.t("web-pages.files.alreadyFavorite"),
    pick: fn(station, path, _, close) {
      let f : Favorite = { station, root: path, path: "", name: dv_root_label([], path) }
      close()
      favorite_add(src, ws, f)
      picked(f)
    },
  })
}

///|
/// The folders at `path` (the home where None) of `station` asked of it (`drive.folders`), a later ask superseding one
/// on its way. Where the picker shows a folder already (a station picked, a step of the way, a folder's row, one just
/// made), it stays as it is till the answer comes, the station's choice naming the one pressed; then the station, its
/// way, its rows and the foot switch to it in one change, told as what the answer tells (nothing sets out by it), at the
/// end of what is running (a frame being drawn shows it wholly as it was: sfbase's switch_answered), the filter
/// emptied with it; what it held kept as the last (its way stays where the folder could not be read). As it opens it
/// shows that it reads.
fn picker_go(src : Source, station : String, path : String?) -> Unit {
  @signals.start_batch()
  // (opening: nothing shown to keep)
  if dialogs.station.untracked() == "" {
    dialogs.station.set(station)
    dialogs.at.set(path)
  }
  dialogs.picked.set(station)
  dialogs.serial.set(dialogs.serial.untracked() + 1)
  dialogs.asking.set(true)
  @signals.end_batch()
  let serial = dialogs.serial.untracked()
  let params : Map[String, Json] = { "station": Json::string(station) }
  match path {
    Some(p) => params["path"] = Json::string(p)
    None => ()
  }
  (src.call)("drive.folders", Json::object(params), fn(r) {
    if serial != dialogs.serial.untracked() {
      return
    }
    @ui.after_frame(fn() {
      // (superseded, or the picker closed, meanwhile)
      guard serial == dialogs.serial.untracked() else { return }
      @view.answering(fn() {
        @signals.start_batch()
        dialogs.station.set(station)
        dialogs.at.set(path)
        dialogs.asking.set(false)
        dialogs.filter.set("")
        match r {
          Ok(v) => {
            dialogs.value.set(Some(v))
            dialogs.last.set(Some(v))
            dialogs.error.set("")
            dialogs.denied.set(flag(Some(v), "unreadable"))
          }
          Err(e) => {
            match dialogs.value.untracked() {
              Some(v) => dialogs.last.set(Some(v))
              None => ()
            }
            dialogs.value.set(None)
            if text(Some(e), "code") == "permission" {
              dialogs.error.set("")
              dialogs.denied.set(true)
            } else {
              dialogs.denied.set(false)
              dialogs.error.set(dv_error(e))
            }
          }
        }
        @signals.end_batch()
      })
    })
  })
}

///|
/// The folder picker `p` put up, at its station's folder `p.at` (its home where ""): what the panel holds and its foot
/// nodes of the window's tree, made once as it opens (@sf.panel_nodes); a step further in from the panel that asked for
/// it, where that one closed for it (the presenters'). sfbase's folder_pick_asked.
pub fn folder_pick(src : Source, p : @sfbase.FolderPick) -> Unit {
  picker_close()
  picker_go(src, p.station, if p.at == "" { None } else { Some(p.at) })
  @sf.panel_nodes(
    p.title,
    fn(v, _) { picker_body(v, src, p) },
    from=Unanchored,
    description=p.note,
    tall=station_pick_tall,
    foot=fn(v, close) { picker_foot(v, src, p, close) },
  )
}

///|
/// The folder shown (its answer), "" while it is read or one the station may not read.
fn picker_here() -> String {
  match dialogs.value.get() {
    Some(v) if !dialogs.denied.get() && dialogs.error.get() == "" => text(Some(v), "path")
    _ => ""
  }
}

///|
/// The folder shown's name: the home's 主目录, else its own (its way's last step).
fn picker_here_name() -> String {
  let v = dialogs.value.get()
  let path = text(v, "path")
  if path != "" && path == text(v, "home") {
    return @sf.t("web-pages.drive.home")
  }
  match v {
    Some(h) =>
      match way_of(h).last() {
        Some((name, _)) => name
        None => path
      }
    None => ""
  }
}

///|
/// What the picker holds, in node `v` (the panel's body's): where it is, the filter, then what is there.
fn picker_body(v : @view.View, src : Source, p : @sfbase.FolderPick) -> Unit {
  picker_where(v, src, p)
  picker_filter_node(v)
  v.box(fn(main) {
    main.grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
    main.pick(picker_shows, fn(b, shows) {
      b.grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
      match shows {
        PickerReading => @sf.wait_line_node(b, fn() { @sf.t("common.reading") }) |> ignore
        PickerShut => picker_shut_node(b)
        PickerNone =>
          @sf.panel_note_node(b, fn() {
            @sf.t(if picker_wanted() != "" { "web-pages.drive.pickNoMatch" } else { "web-pages.drive.noSubfolders" })
          })
        PickerListed => picker_list_node(b, src)
      }
    })
  })
  |> ignore
}

///|
/// What the picker shows under its filter: the folder read, one it cannot read (or failed to), nothing there (or
/// nothing found), or its rows.
#derive(Eq)
priv enum PickerShows {
  PickerReading
  PickerShut
  PickerNone
  PickerListed
}

///|
fn picker_shows() -> PickerShows {
  if dialogs.denied.get() || dialogs.error.get() != "" {
    PickerShut
  } else if dialogs.value.get() is None {
    PickerReading
  } else if picker_rows().length() == 0 {
    PickerNone
  } else {
    PickerListed
  }
}

///|
/// The filter's words, trimmed and lowered.
fn picker_wanted() -> String {
  dialogs.filter.text().trim(chars=" ").to_owned().to_lower()
}

///|
/// A folder the picker lists: its name, its path, whether the station may not read it, a repository, a disk.
priv struct PickerEntry {
  name : String
  path : String
  unreadable : Bool
  git : Bool
  disk : Bool
}

///|
fn picker_entries(v : Json?, key : String) -> Array[PickerEntry] {
  items(v, key).map(fn(x) {
    let x = Some(x)
    { name: text(x, "name"), path: text(x, "path"), unreadable: flag(x, "unreadable"), git: flag(x, "git"), disk: flag(x, "disk") }
  })
}

///|
/// The rows by their keys: each folder here whose name has what is filtered (`e` and its path), and at the station's
/// home its disks after them under their heading (`h`, `d` and its path).
fn picker_rows() -> Array[String] {
  let v = dialogs.value.get()
  let wanted = picker_wanted()
  let has = fn(e : PickerEntry) { wanted == "" || e.name.to_lower().contains(wanted) }
  let rows = picker_entries(v, "entries").filter(has).map(fn(e) { "e\n" + e.path })
  let path = text(v, "path")
  if path != "" && path == text(v, "home") {
    let disks = picker_entries(v, "places").filter(fn(e) { e.disk && has(e) })
    if disks.length() > 0 {
      rows.push("h")
      for d in disks {
        rows.push("d\n" + d.path)
      }
    }
  }
  rows
}

///|
/// The folder or disk a row's key names, as the folder shown has it.
fn picker_entry_of(key : String) -> PickerEntry? {
  let v = dialogs.value.get()
  let (list, path) = if key.has_prefix("d\n") {
    (picker_entries(v, "places"), key.exact_view(start=2).to_owned())
  } else {
    (picker_entries(v, "entries"), key.exact_view(start=2).to_owned())
  }
  list.iter().find_first(fn(e) { e.path == path })
}

///|
/// The rows in node `v`: the panel's list (its share of the window, whatever a folder holds), each folder or disk a row
/// to go into, the disks' heading over them.
fn picker_list_node(v : @view.View, src : Source) -> Unit {
  @sf.panel_list_node(
    v,
    picker_rows,
    fn(r, k) {
      if k == "h" {
        @sf.panel_heading_node(r, fn() { @sf.t("web-pages.drive.disks") })
        return
      }
      guard @signals.untracked(fn() { picker_entry_of(k) }) is Some(was) else { return }
      let e = fn() { picker_entry_of(k).unwrap_or(was) }
      picker_row_node(
        r,
        was,
        fn() { e().name },
        fn() { if e().unreadable { @sf.t("web-pages.drive.pickUnreadable") } else { "" } },
        fn() { picker_go(src, dialogs.station.untracked(), Some(was.path)) },
      )
    },
    est=picker_row_est,
    fills=true,
  )
  |> ignore
}

///|
/// A folder's (or a disk's) row in node `v`, pressed whole to go into it: its mark, its `name` over its `note` ("" none),
/// a chevron right at its end; as high as a press at least, its words on the panel's words' line (panel_row_in_node),
/// its ground under the hand out to the panel's sides as the panel's rows' are.
fn picker_row_node(v : @view.View, e : PickerEntry, name : () -> String, note : () -> String, press : () -> Unit) -> Unit {
  v.box(fn(r) {
    @sf.style_node(r, fn() { picker_row_at.then(@sf.panel_row_in_node(r)) })
    r
    .ground(By(fn() { if @sf.lit_node(r) { @sf.theme().p.hover } else { 0L } }))
    .says(By(fn() { Some(@view.said(Button, label=name())) }))
    |> ignore
    @sf.presses_node(r, press)
    r.box(fn(l) {
      l.shrink(Is(0.0)) |> ignore
      picker_mark_node(l, e)
    })
    |> ignore
    r.box(fn(w) {
      w.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
      @sf.words_node(w, name, fn() { picker_row_name }) |> ignore
      w.show(fn() { note() != "" }, fn(n) { @sf.words_node(n, note, fn() { pick_meta }) |> ignore })
    })
    |> ignore
    @sf.icon_node(r, "chevron-right", crumb_icon, By(fn() { @sf.theme().p.subtle })).shrink(Is(0.0)) |> ignore
  })
  |> ignore
}

///|
/// A row's mark in node `v`: a repository its letter's tile (its colour by its path), as high as a press's row less a
/// corner's inset over and under it so it stands concentric in the row's round ground (panel_row_in_node); a disk the
/// disk's, a folder the folder's, in the middle of as much room.
fn picker_mark_node(v : @view.View, e : PickerEntry) -> Unit {
  if e.git {
    @sf.tile_avatar_node(v, fn() { e.path }, fn() { e.name }, fn() { "" }, picker_tile, corner=@sf.small_corner)
  } else {
    v.box(fn(b) {
      b.width(Is(Some(picker_tile))).height(Is(Some(picker_tile))).row(Is(true)).lines_up(Is(Some(Middle))).lies_along(Is(Middle))
      |> ignore
      @sf.icon_node(b, if e.disk { "disk" } else { "folder" }, picker_mark, By(fn() { @sf.theme().p.muted })) |> ignore
    })
    |> ignore
  }
}

///|
/// One the station may not read (or failed to): its folder over what to do (or why), in the middle.
fn picker_shut_node(v : @view.View) -> Unit {
  v.box(fn(b) {
    @sf.style_node(b, fn() { picker_shut })
    @sf.icon_node(b, "folder", shut_icon, By(fn() { @sf.theme().p.muted })) |> ignore
    @sf.words_node(b, fn() { if dialogs.denied.get() { @sf.t("web-pages.drive.pickNeedsAccess") } else { dialogs.error.get() } }, fn() {
      shut_words
    })
    |> ignore
  })
  |> ignore
}

///|
/// Where it is, in node `v`: the station (its menu of the others where it has others), then the way from its home,
/// each step a way back, the one shown last; short of room those between leave it for a … (way_line_node).
fn picker_where(v : @view.View, src : Source, p : @sfbase.FolderPick) -> Unit {
  let way = fn() {
    match dialogs.value.get() {
      Some(h) => way_of(h)
      None =>
        match dialogs.last.get() {
          Some(h) if text(Some(h), "path") != "" => way_of(h)
          _ => []
        }
    }
  }
  v.box(fn(line) {
    @sf.style_node(line, fn() { @sf.panel_words_out_by_node(v, pick_crumb_in).then(picker_where_row) })
    @sf.station_choice_node(
      line,
      fn() { p.stations },
      // (the one pressed from the press; what is under it the one shown till its home is answered)
      fn() { dialogs.picked.get() },
      // (another station: at its home)
      fn(at) { picker_go(src, at, None) },
      title=@sf.t("android-misc.files.lendOn"),
      label=fn(name) { @sf.t("android-misc.files.lendOn") + ": " + name },
    )
    |> ignore
    line.show(fn() { way().length() > 0 }, at_once=true, fn(c) {
      c.shrink(Is(0.0)) |> ignore
      @sf.icon_node(c, "chevron-right", crumb_icon, By(fn() { @sf.theme().p.subtle })) |> ignore
    })
    @sf.way_line_node(line, fn() { way().map(fn(w) { w.0 }) }, picker_way, fn(i) {
      let steps = @signals.untracked(way)
      if i < steps.length() {
        picker_go(src, dialogs.station.untracked(), Some(steps[i].1))
      }
    })
    .grow(Is(1.0))
    .basis(Is(Some(0.0)))
    .min_width(Is(Some(0.0)))
    |> ignore
  })
  |> ignore
}

///|
/// The filter in node `v`: the library's line, a search's mark before what is typed, × to empty it while it holds
/// something; on the panel's words' line, a row's room under it.
fn picker_filter_node(v : @view.View) -> Unit {
  v.box(fn(fb) {
    @sf.style_node(fb, fn() { picker_filter_at.then(@sf.panel_field_in_node(fb)) })
    @sf.input_node(
      fb,
      dialogs.filter,
      placeholder=@sf.t("web-pages.drive.pickFilter"),
      small=true,
      lead=fn(l) { @sf.icon_node(l, "search", picker_search_icon, By(fn() { @sf.theme().p.muted })) |> ignore },
      end=fn(e) {
        e.show(fn() { dialogs.filter.text() != "" }, at_once=true, fn(x) {
          @sf.icon_button_node(x, "close", fn() { @sf.t("web-pages.drive.pickClear") }, fn() { dialogs.filter.set("") }, size=picker_clear, icon_size=picker_clear_icon)
          |> ignore
        })
      },
    )
    // (a search over what the panel lists: the keys as it opens with keys and a mouse, never an input method raised
    // over the folders)
    |> @sf.panel_search_at_hand_node
  })
  |> ignore
}

///|
/// The picker's foot, in node `v`: 新建文件夹 at its start; at its end what takes the folder shown (its words given its
/// name; disabled while it is read or cannot be, or where it is taken already).
fn picker_foot(v : @view.View, src : Source, p : @sfbase.FolderPick, close : () -> Unit) -> Unit {
  @sf.button_node(v, fn() { @sf.t("web-pages.drive.mkdir") }, fn() { picker_mkdir(src) }, tone=Ghost, icon="folder-plus", disabled=fn() {
    picker_here() == ""
  })
  |> ignore
  @sf.foot_spacer_node(v)
  let taken = fn() {
    let here = picker_here()
    here != "" && (p.taken)(dialogs.station.get(), here)
  }
  @sf.button_node(
    v,
    fn() { if taken() { p.taken_words } else { (p.action)(picker_here_name()) } },
    fn() {
      let here = @signals.untracked(picker_here)
      if here != "" {
        (p.pick)(dialogs.station.untracked(), here, @signals.untracked(picker_here_name), close)
      }
    },
    tone=Primary,
    disabled=fn() { picker_here() == "" || taken() },
  )
  |> ignore
}

///|
/// 新建文件夹 in the folder shown: its name asked (the files page's words for it), made there (`drive.mkdir`), then gone
/// into; failing, said as the files page says it.
fn picker_mkdir(src : Source) -> Unit {
  let station = dialogs.station.untracked()
  let root = @signals.untracked(picker_here)
  guard root != "" else { return }
  @sf.ask(
    @sf.t("web-pages.drive.mkdir"),
    @sf.t("web-pages.drive.make"),
    fn(name) {
      (src.call)("drive.mkdir", { "station": Json::string(station), "root": Json::string(root), "path": Json::string(name) }, fn(r) {
        match r {
          Ok(_) =>
            // (still on that folder of that station: into the one made)
            if dialogs.station.untracked() == station && @signals.untracked(picker_here) == root {
              picker_go(src, station, Some(child_of(root, name)))
            }
          Err(err) =>
            @sfbase.toast_later(
              @sf.t("web-main.act.failed", args=[("what", @sf.t("web-pages.drive.mkdirWhat")), ("error", dv_error(err))]),
            )
        }
      })
    },
    placeholder=@sf.t("web-pages.drive.mkdirPlaceholder"),
  )
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
  let rest = if under { path.exact_view(start=home.length()).to_owned() } else { path }
  for part in rest.split("/") {
    if part != "" {
      at = at + "/" + part.to_owned()
      way.push((part.to_owned(), at))
    }
  }
  way
}

///|
/// A station's row's mark (18) and its height as a list guesses it (40), as 添加到收藏's stations are; the way's
/// chevron (12); the shut picker's folder (32); a row's mark (20, a repository's tile as large, its corner the ladder's
/// smallest step in from a tile's), a row's height before it is laid out (a name, a note under it); the filter's mark (16), its × (28, its
/// icon 14).
let pick_icon : Double = 18.0

///|
let pick_row_h : Double = 40.0

///|
let crumb_icon : Double = 12.0

///|
let shut_icon : Double = 32.0

///|
let picker_mark : Double = 20.0

///|
/// A repository's tile in the folder picker: a press's row (44) less a corner's inset (8) over and under it.
let picker_tile : Double = 28.0

///|
let picker_row_est : Double = 48.0

///|
let picker_search_icon : Double = 16.0

///|
let picker_clear : Double = 28.0

///|
let picker_clear_icon : Double = 14.0

///|
/// The stations' rows (rootsList: 4 apart).
// kept across runs: a value (no field of it changes)
let roots_list : @ui.Style = @ui.css("w=Full gap=S1")

///|
/// A station's row to pick (pickRow): 40 high at least, 6 by 10 in, 10 between, the field's corner; the list's ground
/// under the pointer.
// kept across runs: a value (no field of it changes)
let pick_row : @ui.Style = @ui.css((
  #|row w=Full min_h=S10 px=S2_5 py=S1_5 gap=S2_5 align=ACenter radius=Lg hovered{bg=Hover}
))

///|
// kept across runs: a value (no field of it changes)
let pick_name : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pick_meta : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// A folder's row (picker_row_node): 44 high at least, 6 over and under, 12 between its mark, its words, its chevron.
// kept across runs: a value (no field of it changes)
let picker_row_at : @ui.Style = @ui.css("row w=Full min_h=S11 py=S1_5 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let picker_row_name : @ui.TextStyle = @ui.text_style(size=Body, leading=L6, color=Fg, wrap=false, w=Cut)

///|
/// Where it is: one line, its own room over it, under it a finger's room for a press on a step (as the station files
/// picker's way: pick_crumbs_row) before the filter.
// kept across runs: a value (no field of it changes)
let picker_where_row : @ui.Style = @ui.css("row pt=S2 pb=S2 gap=SPx align=ACenter")

///|
/// The way's look: its steps muted, the one shown in the words' colour and semibold, the chevrons subtle (way_line:
/// those between in its … where the line is short).
fn picker_way() -> @sf.WayLook {
  { line: picker_trail, step: crumb_box, words: crumb_words, here: crumb_last, chevron: crumb_icon, chevron_ink: @sf.theme().p.subtle }
}

///|
// kept across runs: a value (no field of it changes)
let picker_trail : @ui.Style = @ui.css("row w=Full gap=SPx align=ACenter")

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
/// The filter over the rows: across the panel (where panel_field_in_node stands it), a row's room under it.
// kept across runs: a value (no field of it changes)
let picker_filter_at : @ui.Style = @ui.css("w=Full pb=S2")

///|
/// A folder the station cannot read (pickerShut): its mark over what to do, in the middle.
// kept across runs: a value (no field of it changes)
let picker_shut : @ui.Style = @ui.css("w=Full h=Full px=S6 gap=S3 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let shut_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, center=true, w=Full)
