// The ways a folder of a station's drive is shown (ember web/src/pages/DriveViews.tsx: the files' page, a chat's 文件
// tab), switched over its list and kept for each place on this device (prefs `driveViews`: `page`, `tab`): columns (a
// column a folder, from where it is to the one open, as Finder's), a tree (folders opened in place, several
// at once), or a list (one folder). Each row is the same (DriveRow, drive.mbt): chosen by a press, opened by a double
// click, dragged, its menu on a right click; the place says what a row does (`RowProps`) and in what order a folder's
// entries go (the core's, through the place: Browse). How far each folder was scrolled is its list's own (kept by
// where it is shown and how: kept.ts), a tree's folders open and a column's width the core's.

///|
/// What a row of a folder does, as its place says (RowProps): its menu (a right click, its ⋯: about what is chosen
/// when it is among it), opened (a double click), pressed (chosen; in columns a folder opened beside), right clicked
/// (chosen, if it is not among what is), chosen, its name being changed in place and that done (None: as it was), and
/// a folder's: where what is dropped on it goes.
pub(all) struct RowProps {
  items : () -> Array[@sf.MenuItem?]
  open : () -> Unit
  press : () -> Unit
  menu : () -> Unit
  chosen : Bool
  renaming : Bool
  rename : (String?) -> Unit
  drop : DriveAt?
}

///|
/// The ways a place shows a folder's rows, the same for each view (Shown): with what the core says of the place (its
/// Browse), what each row does, what is dropped on where a folder's rows are (not on one of them), a press where there
/// is no row (nothing chosen); whether the station takes what is written there and copies from others.
pub(all) struct Shown {
  b : Browse
  row_of : (DriveAt, DvEntry) -> RowProps
  drop_on : (DriveAt) -> DriveAt?
  clear : () -> Unit
  write : Bool
  transfers : Bool
}

///|
/// A folder's rows to come while it is read the first time (the library's Waiting, in its bones): `count` rows as
/// rows_view draws them (drive_row, each a row of the group's card) as `s` shows them at `at`, of made-up names, a
/// couple of folders first.
pub fn rows_sample(c : @ui.Ctx, at : DriveAt, s : Shown, count : Int, compact? : Bool = false) -> Unit {
  @sf.rows_room(c, fn() {
    for i in 0..<count {
      let (dir, name) = rows_sample_names[i % rows_sample_names.length()]
      let e = @sfbase.dv_entry({
        "name": Json::string(@sf.sample_words(name) + (if dir { "" } else { ".md" })),
        "dir": Json::boolean(dir),
        "sizeText": Json::string(if dir { "" } else { @sf.sample_words(3) }),
        "timeText": Json::string(@sf.sample_words(4)),
      })
      @sf.group_row(c, i == 0, i == count - 1, fn() {
        drive_row(c, @sfbase.sample_source, at, e, rows_sample_props, s, compact~)
      })
    }
  })
}

///|
/// What a made-up row does: nothing.
// kept across runs: a value (nothing in it changes)
let rows_sample_props : RowProps = {
  items: fn() { [] },
  open: fn() {  },
  press: fn() {  },
  menu: fn() {  },
  chosen: false,
  renaming: false,
  rename: fn(_) {  },
  drop: None,
}

///|
/// Whether each made-up row is a folder, and how long its name is (letters).
// kept across runs: a table, never written
let rows_sample_names : Array[(Bool, Int)] = [(true, 4), (true, 6), (false, 9), (false, 5), (false, 12), (false, 7), (false, 8), (false, 6)]

///|
/// A row pressed: what it would carry (drag.mbt), as the web's draggedOf has it.
fn drag_press(c : @ui.Ctx, src : Source, at : DriveAt, e : DvEntry) -> Unit {
  let root = at.root.unwrap_or("")
  let path = dv_join(at.path, e.name)
  fdrag_press(c, {
    station: at.station,
    station_name: station_name(src, at.station),
    root,
    path,
    abs: dv_absolute(root, path),
    name: e.name,
    size: e.size,
    dir: e.dir,
  })
}

///|
/// A place a row or a column can be let go this frame (drag.mbt fdrag_target), as its folder is shown.
fn drag_target(c : @ui.Ctx, id : Int, key : String, into : DriveAt, name : String, s : Shown, depth : Int) -> String? {
  fdrag_target(c, id, key, Some(into), name, s.write, s.transfers, depth)
}

///|
/// Whether the row `name` of the folder `at` is what is being dragged.
fn drag_carried(at : DriveAt, name : String) -> Bool {
  fdrag_carried(at.station, at.root.unwrap_or(""), dv_join(at.path, name))
}

///|
/// How `place` (page or tab) shows a folder, as last chosen there. The files page starts with the detailed list; a
/// chat's narrower files tab starts with columns where they fit.
pub fn drive_view(src : Source, place : String) -> String {
  match text(field((src.topic)("prefs", {}).value, "driveViews"), place) {
    "columns" => "columns"
    "tree" => "tree"
    "list" => "list"
    _ => if place == "page" { "list" } else { "columns" }
  }
}

///|
/// The ways a folder can be shown in a list's room `room` across: columns where two fit side by side (where one
/// alone does, they are a list that says it is columns), a tree and a list wherever (a tree opens folders in place, a
/// list does not: as narrow as a phone they differ still).
pub fn views_for(room : Double) -> Array[String] {
  if room >= 2.0 * (column_w + column_gap) {
    ["columns", "tree", "list"]
  } else {
    ["tree", "list"]
  }
}

///|
/// How `place` shows a folder in a list's room `room` across: the way last chosen there where that room can have it,
/// else a list (what was chosen kept: wider, it is back).
pub fn view_in(src : Source, place : String, room : Double) -> String {
  let v = drive_view(src, place)
  if views_for(room).contains(v) {
    v
  } else {
    "list"
  }
}

///|
/// Another way chosen for `place` (`prefs.set {driveViews: {place}}`).
pub fn set_drive_view(src : Source, place : String, v : String) -> Unit {
  let o : Map[String, Json] = {}
  o[place] = if place != "page" && v == "columns" { Json::null() } else { Json::string(v) }
  (src.call)("prefs.set", { "driveViews": Json::object(o) }, fn(_) {  })
}

///|
/// The ways the room has (`ways`: views_for's), side by side (ViewSwitch): a segmented choice of their icons among the
/// bar's buttons, each its tip.
pub fn view_switch(c : @ui.Ctx, key : String, value : String, on_change : (String) -> Unit, ways? : Array[String] = views_all) -> Unit {
  let shown = view_icons.filter(fn(w) { ways.contains(w.0) })
  let at = shown.search_by(fn(w) { w.0 == value }).unwrap_or(0)
  let k = @sf.segmented(
    c,
    key,
    shown.map(fn(w) { @sf.t("web-pages.drive.view." + w.0) }),
    at,
    icons=shown.map(fn(w) { w.1 }),
    bar=true,
    said=@sf.t("web-pages.drive.view.label"),
  )
  // (the one shown chosen again is kept as chosen: shown where the room has not what was chosen before)
  if k != at || c.clicked(@kit.part_id(c.id(key), at)) {
    match shown.get(k) {
      Some((v, _)) => on_change(v)
      None => ()
    }
  }
}

///|
/// Every way, and each one's icon.
// kept across runs: a value (no field of it changes)
let views_all : Array[String] = ["columns", "tree", "list"]

///|
// kept across runs: a value (no field of it changes)
pub let view_icons : Array[(String, String)] = [("columns", "view-columns"), ("tree", "view-tree"), ("list", "list")]

// ── a list, a tree ──

///|
/// A row of a list or a tree as drawn: an entry (its folder, its depth in a tree, whether it is a folder opened there),
/// or a line about a folder not listed (being read, empty, refused) at its depth.
priv enum Line {
  Row(DriveAt, DvEntry, Int, Bool?)
  Note(String, Bool, Int)
  Reading(Int)
}

///|
/// A folder's entries as its station said them, and why it could not be read.
pub fn drive_folder(src : Source, station : String, root : String, path : String) -> (Json?, String?) {
  let t = @sfbase.hold(src, @sfbase.drive_scope, "drive", {
    "station": Json::string(station),
    "root": Json::string(root),
    "path": Json::string(path),
  })
  (
    t.value,
    match t.error {
      Some(e) => Some(dv_error(e))
      None => None
    },
  )
}

///|
/// A folder and, under each of its folders opened, that one's, in by a step each (TreeView, TreeFolder): its lines.
fn tree_lines(src : Source, s : Shown, at : DriveAt, depth : Int, out : Array[Line], empty : Bool) -> Unit {
  let root = at.root.unwrap_or("")
  let (value, error) = drive_folder(src, at.station, root, at.path)
  match error {
    Some(e) => {
      out.push(Note(e, true, depth))
      return
    }
    None => ()
  }
  let entries = match value {
    Some(_) => s.b.arranged(at.path, @sfbase.dv_entries(src, at.station, root, at.path).unwrap_or([]))
    None => None
  }
  match entries {
    None => out.push(Reading(depth))
    Some([]) => if !(depth == 0 && empty) { out.push(Note(@sf.t("web-pages.drive.emptyFolder"), false, depth)) }
    Some(list) =>
      for e in list {
        let full = dv_join(at.path, e.name)
        let open = e.dir && s.b.is_open(full)
        out.push(Row(at, e, depth, if e.dir { Some(open) } else { None }))
        if open {
          tree_lines(src, s, { ..at, path: full }, depth + 1, out, false)
        }
      }
  }
}

///|
/// The rows of a list or a tree (`tree`: folders opened in place), in a list of their own (`key`: by where it is shown
/// and how, so each folder keeps how far it was scrolled): `head` over them, `empty` where the folder has nothing,
/// `foot` the room under the last. The row whose name is being changed is kept in view (the soft keyboard up, the
/// list shorter: it comes up over it).
pub fn rows_view(
  c : @ui.Ctx,
  src : Source,
  key : String,
  at : DriveAt,
  s : Shown,
  tree : Bool,
  compact? : Bool = false,
  head? : () -> Unit,
  empty? : () -> Unit,
  foot? : Double = 0.0,
) -> Unit {
  let lines : Array[Line] = []
  if tree {
    tree_lines(src, s, at, 0, lines, empty is Some(_))
  } else {
    let root = at.root.unwrap_or("")
    let (value, _) = drive_folder(src, at.station, root, at.path)
    match value {
      Some(_) =>
        match s.b.arranged(at.path, @sfbase.dv_entries(src, at.station, root, at.path).unwrap_or([])) {
          Some(list) =>
            for e in list {
              lines.push(Row(at, e, 0, None))
            }
          None => ()
        }
      None => ()
    }
  }
  let extra = if head is Some(_) { 1 } else { 0 }
  let empty_n = if lines.is_empty() && empty is Some(_) { 1 } else { 0 }
  // the list's rows by what each is (a file by its folder and name; its head, an empty folder's words and its foot
  // too): one made, taken out or moved comes and goes where it is, as a chat's rows do (ListRows, docs/list-motion.md);
  // a folder's rows all others now (another folder, its first read) as they are
  let lr = drive_rows_of(key)
  let all : Array[ListLine] = []
  if extra == 1 {
    all.push(Head)
  }
  for l in lines {
    all.push(At(l))
  }
  if empty_n == 1 {
    all.push(Empty)
  }
  all.push(Foot)
  let all_keys = all.mapi(fn(i, l) {
    match l {
      Head => "head"
      At(Row(a, e, _, _)) => "r/" + row_key(a.path, e.name)
      At(Note(w, _, d)) => "n/" + d.to_string() + "/" + w
      At(Reading(d)) => "w/" + d.to_string() + "/" + i.to_string()
      Empty => "empty"
      Foot => "foot"
    }
  })
  let was = drive_keys.get(key).unwrap_or([])
  drive_keys[key] = all_keys
  let (all, shown_keys) = lr.rows(c, all_keys, all, fn(_) { "" }, comes=fn(l) { l is At(_) }, watched=all_keys.iter().any(fn(k) { k.has_prefix("r/") && was.contains(k) }))
  // (the lines among them, with those going: where each is, its first and last of the group's)
  let line_of : Array[Int] = []
  let mut lines_n = 0
  for l in all {
    line_of.push(if l is At(_) { lines_n } else { -1 })
    if l is At(_) {
      lines_n += 1
    }
  }
  // a row asked into view (a key moved to it), or the one being named: as near as it needs to come
  let want = match s.b.take_show() {
    Some(w) => Some(w)
    None => s.b.renaming()
  }
  match want {
    Some(want) =>
      for i, l in all {
        match l {
          At(Row(a, e, _, _)) if row_key(a.path, e.name) == want => {
            // (read back by the rows in view alone)
            match c.list_info_as(key, fn(i) { i.map(fn(i) { (i.first, i.last) }) }) {
              Some(info) if i >= info.first && i < info.last => ()
              Some(info) if i >= info.last =>
                c.list_scroll_to(key, dmax_int(0, i - (info.last - info.first) + 2))
              _ => c.list_scroll_to(key, i)
            }
          }
          _ => ()
        }
      }
    None => ()
  }
  // a line as drawn (an entry, a note about a folder, one being read) on its ground (the group's), what it holds coming
  // and going where it is by its key: its room opening and closing, the ground not faded nor moved with what it holds
  let line_at = fn(i : Int, line : Line) {
    let first = line_of[i] == 0
    let last = line_of[i] == lines_n - 1
    let held = fn(body : () -> Unit) {
      let b = c.box(style=@sf.full_width, body)
      lr.enter(c, b, shown_keys[i])
      lr.leave(c, b, shown_keys[i])
    }
    @sf.group_row(c, first, last, fn() {
      held(fn() {
        match line {
          Row(a, e, depth, open) =>
            drive_row(c, src, a, e, (s.row_of)(a, e), s, compact~, depth?=if tree { Some(depth) } else { None }, expanded?=open, on_toggle=fn() {
              s.b.toggle(c, src, dv_join(a.path, e.name))
            })
          Note(words, error, depth) =>
            c.box(style=tree_note, fn() {
              c.box(style=@ui.style(w=Fixed(tree_note_in + tree_step * depth.to_double())), fn() {  }) |> ignore
              c.text(words, style=if error { tree_error } else { tree_words }) |> ignore
            })
            |> ignore
          Reading(depth) =>
            c.box(style=tree_note, fn() {
              c.box(style=@ui.style(w=Fixed(tree_note_in + tree_step * depth.to_double())), fn() {  }) |> ignore
              @sf.wait_line(c, "")
            })
            |> ignore
        }
      })
    })
  }
  @sf.rows_list(c, key, all.length(), if compact { row_compact_est } else { row_est }, sized=lr.sized(), fn(i) {
    match all[i] {
      Head =>
        match head {
          Some(h) => h()
          None => ()
        }
      At(l) => line_at(i, l)
      Empty =>
        match empty {
          Some(f) => f()
          None => ()
        }
      Foot => c.box(style=@ui.style(w=Full, h=Fixed(rows_foot + foot)), fn() {  }) |> ignore
    }
  })
  |> ignore
}

///|
/// A row of a folder's list (rows_view): its head, a line, an empty folder's words, the room under the last.
priv enum ListLine {
  Head
  At(Line)
  Empty
  Foot
}

///|
/// Each list's lines as given and as its list made of them (rows_view), by the list's key.
// kept across runs: forgot by drive_rows_reset (the app's reset)
let drive_rows : Map[String, @ui.ListRows[ListLine]] = {}

///|
/// Each list's lines' keys as last given.
// kept across runs: forgot by drive_rows_reset (the app's reset)
let drive_keys : Map[String, Array[String]] = {}

///|
fn drive_rows_of(key : String) -> @ui.ListRows[ListLine] {
  match drive_rows.get(key) {
    Some(l) => l
    None => {
      let l = @ui.ListRows::new()
      drive_rows[key] = l
      l
    }
  }
}

///|
/// What each list's lines were forgets (a run anew).
pub fn drive_rows_reset() -> Unit {
  drive_rows.clear()
  drive_keys.clear()
}

///|
/// Under the last row (the phone's contentPadding: 30), over the frame's room.
let rows_foot : Double = 30.0

///|
fn dmax_int(a : Int, b : Int) -> Int {
  if a > b {
    a
  } else {
    b
  }
}

// ── columns ──

///|
/// A column's width: as wide as every column is until one is dragged (240 until all are, kept on this device), 160 to
/// 640.
pub let column_w : Double = 240.0

///|
let column_least : Double = 160.0

///|
let column_most : Double = 640.0

///|
fn clamp_column(px : Double) -> Double {
  let w = px.round()
  if w < column_least {
    column_least
  } else if w > column_most {
    column_most
  } else {
    w
  }
}

///|
/// A column being dragged wider or narrower (its place's key, the folder's path or None with ⌥ held: every one; the
/// width), and every column's width as just dragged until the kept one comes back (what the prefs said then, and it).
priv struct Cols {
  mut drag : (String, String?, Double)?
  mut every : (String, Double)?
}

///|
let cols : Cols = { drag: None, every: None }

///|
fn cols_reset() -> Unit {
  cols.drag = None
  cols.every = None
}

///|
/// Every column's width: as kept on this device (prefs `driveViews.column`), or as just dragged until the kept one
/// comes back.
fn every_column(src : Source) -> Double {
  let kept = text(field((src.topic)("prefs", {}).value, "driveViews"), "column")
  match cols.every {
    Some((was, w)) if was == kept => return w
    Some(_) => cols.every = None
    None => ()
  }
  match (@json.parse(kept) catch { _ => Json::null() }) {
    Number(w, ..) if w > 0.0 => w
    _ => column_w
  }
}

///|
/// A column a folder (ColumnsView), from the one it starts at (`at.path` "" under its root) to the one open (`open`,
/// under it), each with the next open marked; a folder pressed opens next to its column, the columns after it let go.
/// As many as `room` holds, the last ones (as the web's strip keeps the last in view). Each column takes what is
/// dropped on it into its folder. Its edge, dragged, makes it wider or narrower (with ⌥ held every column; a double
/// click as wide as its longest name). `halves`: a chat's 文件 tab's, two at a time, halves of it.
pub fn columns_view(
  c : @ui.Ctx,
  src : Source,
  at : DriveAt,
  open : String,
  s : Shown,
  room : Double,
  halves? : Bool = false,
  empty? : () -> Unit,
) -> Unit {
  let parts = if open == "" { [] } else { open.split("/").map(fn(p) { p.to_string() }).collect() }
  let paths = [at.path]
  let mut so_far = at.path
  for p in parts {
    so_far = dv_join(so_far, p)
    paths.push(so_far)
  }
  let every = every_column(src)
  let widths = paths.map(fn(p) {
    if halves {
      room / 2.0 - column_gap
    } else {
      match cols.drag {
        Some((k, whose, px)) if k == s.b.key && (whose is None || whose == Some(p)) => px
        _ => s.b.width_of(p).unwrap_or(every)
      }
    }
  })
  let mut from = paths.length() - 1
  let mut used = widths[from] + column_gap
  while from > 0 && used + widths[from - 1] + column_gap <= room {
    from -= 1
    used += widths[from] + column_gap
  }
  c.box(style=columns_strip, fn() {
    for i in from..<paths.length() {
      column(c, src, { ..at, path: paths[i] }, parts.get(i), s, widths[i], halves, if i == paths.length() - 1 { empty } else { None })
    }
  })
  |> ignore
}

///|
/// Between two columns (Drive.css.ts columns' gap), where an edge is.
pub let column_gap : Double = 6.0

///|
fn column(
  c : @ui.Ctx,
  src : Source,
  at : DriveAt,
  next : String?,
  s : Shown,
  width : Double,
  halves : Bool,
  empty : (() -> Unit)?,
) -> Unit {
  let root = at.root.unwrap_or("")
  let (value, error) = drive_folder(src, at.station, root, at.path)
  let entries = match value {
    Some(_) => s.b.arranged(at.path, @sfbase.dv_entries(src, at.station, root, at.path).unwrap_or([]))
    None => None
  }
  let ckey = "files/column/" + s.b.key + "/" + at.station + "/" + root + "/" + at.path
  let cid = c.id(ckey)
  // (a ground round its rows: a press there chooses none)
  c.cursor(cid, Arrow)
  let lit = match (s.drop_on)(at) {
    Some(into) => drag_target(c, cid, ckey, into, dv_name(dv_absolute(root, at.path)), s, 1)
    None => None
  }
  let sized = column_box.then(@ui.style(w=Fixed(width)))
  c.box(style=if lit is Some(_) { sized.then(column_drop) } else { sized }, id=cid, fn() {
    match (entries, error) {
      (_, Some(e)) => c.box(style=column_note, fn() { c.text(e, style=tree_error) |> ignore }) |> ignore
      (None, None) =>
        c.box(style=column_note, fn() { @sf.wait_line(c, "") }) |> ignore
      (Some([]), _) =>
        match empty {
          Some(f) => f()
          None =>
            c.box(style=column_note, fn() {
              c.text(@sf.t("web-pages.drive.emptyFolder"), style=tree_words) |> ignore
            })
            |> ignore
        }
      (Some(list), _) => {
        let lkey = ckey + "/rows"
        match s.b.take_show() {
          Some(want) =>
            for i, e in list {
              if row_key(at.path, e.name) == want {
                // (read back by the rows in view alone)
                match c.list_info_as(lkey, fn(i) { i.map(fn(i) { (i.first, i.last) }) }) {
                  Some(info) if i >= info.first && i < info.last => ()
                  Some(info) if i >= info.last => c.list_scroll_to(lkey, dmax_int(0, i - (info.last - info.first) + 2))
                  _ => c.list_scroll_to(lkey, i)
                }
              }
            }
          None => ()
        }
        @sf.rows_list(c, lkey, list.length(), row_compact_est, fn(i) {
          let e = list[i]
          drive_row(c, src, at, e, (s.row_of)(at, e), s, compact=true, column=true, along=next == Some(e.name))
        })
        |> ignore
      }
    }
    // a press in it where there is no row: nothing chosen
    if c.clicked(cid) && !row_took(c) {
      (s.clear)()
    }
  })
  |> ignore
  if halves {
    c.box(style=column_edge_room, fn() {  }) |> ignore
  } else {
    let names = match entries {
      Some(list) => list.map(fn(e) { e.name })
      None => []
    }
    column_edge(c, src, s, at.path, cid, width, names)
  }
}

///|
/// A column's edge (ColumnEdge: the library's edge, @sf.handle_drag and @sf.edge_look, as the app's other columns'
/// edges look), `width` wide now, after it: dragged, its width, or with ⌥ held every column's (kept on this device as
/// it is let go); pressed twice, as wide as its longest name needs.
fn column_edge(c : @ui.Ctx, src : Source, s : Shown, path : String, column : Int, width : Double, names : Array[String]) -> Unit {
  let key = "files/column-edge/" + s.b.key + "/" + path
  let id = c.id(key)
  let (px, py, _) = c.pointer()
  c.cursor(id, ResizeX)
  let every = (@ui.mods_held() & @ui.mod_alt) != 0
  match @sf.handle_drag(c, id, width, min=column_least, max=column_most) {
    Dragging(w) => cols.drag = Some((s.b.key, if every { None } else { Some(path) }, w))
    Dropped(w) => {
      let was_every = match cols.drag {
        Some((_, whose, _)) => whose is None
        None => false
      }
      cols.drag = None
      if every || was_every {
        // every column as wide, kept on this device
        s.b.forget_widths(c, src)
        let kept = if w == column_w { Json::null() } else { Json::string(w.to_int().to_string()) }
        cols.every = Some((match kept { String(k) => k; _ => "" }, w))
        (src.call)("prefs.set", { "driveViews": { "column": kept } }, fn(_) {  })
      } else {
        s.b.keep_width(c, src, path, w)
      }
    }
    Twice => {
      let need = names.fold(init=0.0, fn(m, n) { dmax(m, @ui.text_advance(n, size=@sf.theme().t.ui)) })
      if need > 0.0 {
        s.b.keep_width(c, src, path, clamp_column(need + column_row_room))
      }
    }
    Untouched | Pressed => ()
  }
  // in hand: this edge, or with ⌥ every one, while one is dragged
  let dragged = match cols.drag {
    Some((k, whose, _)) => k == s.b.key && (whose == Some(path) || whose is None)
    None => false
  }
  let active = dragged || c.pressed(id)
  let over = match c.rect_of(column) {
    Some((x, y, w, h)) => px >= x && px < x + w + column_gap && py >= y && py < y + h
    None => false
  }
  let words = @sf.t("web-pages.drive.resizeColumn")
  let b = c.box(style=column_edge_room, id~, fn() {
    @sf.edge_look(c, key, over~, on=c.lit(id) || c.focus_shown(id) || active, active~)
  })
  c.semantics(b, Separator, id~, label=words)
  if !active {
    @sf.edge_tip(c, key, id, words)
  }
}

///|
/// A column's row about its name (a compact row: 10 in, its mark 18, 10, the name, 10, its size's room, 10, 28, 10 in;
/// and a point, as the web's fit adds one).
let column_row_room : Double = 97.0

///|
/// A list's rows, as tall as they mostly are (row 44 and the list's gap 2; compact 36 and 2), till they are laid out.
let row_est : Double = 46.0

///|
let row_compact_est : Double = 38.0

///|
/// A tree's line about a folder not listed (treeNote): 8 over and under, in by 46 and a step a depth (18), its words
/// the meta's; a column's, in by its rows' padding.
let tree_note_in : Double = 46.0

///|
let tree_step : Double = 18.0


///|
// kept across runs: a value (no field of it changes)
let tree_note : @ui.Style = @ui.css("row w=Full pt=S2 pb=S2 pr=S2_5")

///|
// kept across runs: a value (no field of it changes)
let column_note : @ui.Style = tree_note.then(@ui.css("pl=S2_5"))

///|
// kept across runs: a value (no field of it changes)
let tree_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let tree_error : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, w=Full)

///|
/// The columns side by side (Drive.css.ts columns), as tall as the list.
// kept across runs: a value (no field of it changes)
let columns_strip : @ui.Style = @ui.css("row w=Full h=Full")

///|
/// A column (column): as tall as the strip, its rows 2 apart, its top's corners the field's, its foot square (it goes on
/// past the page's foot, its rows scrolling under it: where it meets a panel's foot corner, the panel's cut is its
/// corner); lit while a drop goes into it.
// kept across runs: a value (no field of it changes)
// det-ok(corners-each): a column runs on to the page's foot, cut there by the panel; only its top is a corner of its own
let column_box : @ui.Style = @ui.style(h=Full, radius=Corners(column_top, column_top, column_foot, column_foot), clip=true)

///|
/// Its top's corners (the field's, Xl) and its foot's.
let column_top : Double = 12.0

///|
let column_foot : Double = 0.0

///|
// kept across runs: a value (no field of it changes)
let column_drop : @ui.Style = @ui.css("bg=AccentBg")

///|
/// An edge: as wide as the gap between two columns (6), the library's look from its left.
// kept across runs: a value (no field of it changes)
let column_edge_room : @ui.Style = @ui.style(w=Fixed(column_gap), h=Full)
