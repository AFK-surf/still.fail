// What is dragged on the files' page (ember web/src/drive/drag.ts, browse.ts takes / effectOf / dropInto, transfer.ts,
// order.ts movesOf, FilesNav.tsx useFolderDrop): a row pressed and moved past a few points carries its file or folder
// under the pointer; let go on a folder (a folder's row, a column, the folder shown, a folder of the sidebar) it goes
// there: within its station moved (⌥: copied), to another station copied (⌘: moved), as Finder does across disks; a
// folder let go on 个人收藏 is kept there. A move within a station by a root both places are under is a rename there,
// anything else the core's `drive.transfer` (the stations copy between them; the bar's 传输 follows it); a name
// already there is asked about first (替换, 保留两者, 跳过). Files from the computer (Finder) let go on a folder go up
// into it, a folder of them made there and filled.

///|
/// What is dragged (drag.ts Dragged): its station and that station's name, its root and its path under it, its absolute
/// path, its name, its size, whether it is a folder.
priv struct FDragged {
  station : String
  station_name : String
  root : String
  path : String
  abs : String
  name : String
  size : Double
  dir : Bool
}

///|
/// Where something dragged can be let go this frame: its id (where it was drawn), its key, the folder it is (None: 个人
/// 收藏), its name, whether its station takes files written there and copies from others, and how deep it lies (a
/// folder's row over the folder shown it is in).
priv struct FTarget {
  id : Int
  key : String
  into : DriveAt?
  name : String
  write : Bool
  transfers : Bool
  depth : Int
  /// whether it takes the computer's files (a folder of the sidebar does not)
  outside : Bool
}

///|
/// A name already where files go, asked about (transfer.ts Clash): what comes (its size, its station's name) and what
/// is there.
priv struct FClash {
  name : String
  dir : Bool
  size : Double
  station : String
  there : DvEntry
}

///|
/// What is asked now (transfer.ts Asking): where they go, its name, how many go, the names there, the answers so far,
/// whether the next is said for all the rest, and what is done with the answers.
priv struct FAsking {
  into : DriveAt
  into_name : String
  total : Int
  clashes : Array[FClash]
  answers : Map[String, String]
  mut all : Bool
  done : (Map[String, String]) -> Unit
}

///|
/// The drag: a row pressed (what, where), what is carried once it moved, the targets drawn last frame and this one,
/// the one under the pointer, files dropped from outside still being read (their pick, where they go), what is asked.
priv struct FDrag {
  mut press : (FDragged, Double, Double)?
  mut item : FDragged?
  mut targets : Array[FTarget]
  mut drawn : Array[FTarget]
  mut over : String
  mut dropped : Array[(@ui.Pick, DriveAt)]
  mut asking : FAsking?
  /// drops waiting for the folder they go into to be read (what is there by their names asked about first): each done
  /// once it is (true)
  mut later : Array[() -> Bool]
  /// the frame this was last moved on in (the sidebar and the folder both ask; the first does it)
  mut frame : Int
  /// the station this machine is (its address; "" none), read once
  mut here : String?
}

///|
let fdrag : FDrag = {
  press: None,
  item: None,
  targets: [],
  drawn: [],
  over: "",
  dropped: [],
  asking: None,
  later: [],
  frame: -1,
  here: None,
}

///|
fn fdrag_reset() -> Unit {
  fdrag.press = None
  fdrag.item = None
  fdrag.targets = []
  fdrag.drawn = []
  fdrag.over = ""
  fdrag.dropped = []
  fdrag.asking = None
  fdrag.later = []
  fdrag.frame = -1
  fdrag.here = None
}

///|
/// The station this machine is (thisMachine.ts: "<workspace>/<station>"), as its host says (its station's cloud.json),
/// read once; "" where it is none.
fn files_this_machine() -> String {
  match fdrag.here {
    Some(h) => h
    None => {
      let v = @json.parse(@ui.local_station()) catch { _ => Json::null() }
      let ws = field(Some(v), "workspace")
      let h = if text(ws, "id") != "" && text(ws, "station") != "" {
        text(ws, "id") + "/" + text(ws, "station")
      } else {
        ""
      }
      fdrag.here = Some(h)
      h
    }
  }
}

///|
/// Whether the viewer writes to `s`'s drive (a read-only member does not).
fn files_writes(src : Source, w : Workspace, s : DvStation) -> Bool {
  dv_rights(src, w.id, Some(s)).write
}

///|
/// How far a press moves before it is a drag (a click's slop).
let fdrag_slop : Double = 4.0

///|
/// A row pressed: what it would carry, where the pointer went down.
fn fdrag_press(c : @ui.Ctx, item : FDragged) -> Unit {
  if fdrag.press is None && fdrag.item is None {
    // (where it went down: the frame that sees the press may see it moved already)
    fdrag.press = Some((item, c.press_x, c.press_y))
  }
}

///|
/// Whether a row is what is being dragged.
fn fdrag_carried(station : String, root : String, path : String) -> Bool {
  match fdrag.item {
    Some(i) => i.station == station && i.root == root && i.path == path
    None => false
  }
}

///|
/// What a drop of `item` into a folder of `station` does (browse.ts effectOf): across stations a copy (⌘: a move),
/// within one a move (⌥: a copy).
fn fdrag_effect(item : FDragged, station : String, mods : Int) -> String {
  if item.station != station {
    if (mods & @ui.mod_cmd) != 0 {
      "move"
    } else {
      "copy"
    }
  } else if (mods & @ui.mod_alt) != 0 {
    "copy"
  } else {
    "move"
  }
}

///|
/// Whether `t` takes what is held over the window now (browse.ts takes): a folder written to, the station's own or one
/// that copies from others (not into what is carried itself); 个人收藏 a folder; the computer's files any folder
/// written to.
fn fdrag_takes(t : FTarget) -> Bool {
  match (fdrag.item, t.into) {
    (Some(i), None) => i.dir
    (Some(i), Some(into)) => {
      let root = into.root.unwrap_or("")
      let inside = i.station == into.station &&
        root == i.root &&
        (into.path == i.path || into.path.has_prefix(i.path + "/"))
      t.write && !inside && (i.station == into.station || t.transfers)
    }
    (None, Some(_)) => t.write && t.outside
    (None, None) => false
  }
}

///|
/// The target under (x, y) of those drawn last frame that takes what is held: the deepest, the last drawn of those.
fn fdrag_at(c : @ui.Ctx, x : Double, y : Double) -> FTarget? {
  let mut best : FTarget? = None
  for t in fdrag.drawn {
    if !fdrag_takes(t) {
      continue
    }
    match c.rect_of(t.id) {
      Some((rx, ry, rw, rh)) if x >= rx && x < rx + rw && y >= ry && y < ry + rh =>
        match best {
          Some(b) if b.depth > t.depth => ()
          _ => best = Some(t)
        }
      _ => ()
    }
  }
  best
}

///|
/// `key` a place something can be let go this frame (`id` where it is drawn): what a drop there would do, while what is
/// held is over it ("move", "copy", "upload", "keep"), else None.
fn fdrag_target(
  c : @ui.Ctx,
  id : Int,
  key : String,
  into : DriveAt?,
  name : String,
  write : Bool,
  transfers : Bool,
  depth : Int,
  outside? : Bool = true,
) -> String? {
  ignore(c)
  fdrag.targets.push({ id, key, into, name, write, transfers, depth, outside })
  if fdrag.over != key {
    return None
  }
  match (fdrag.item, into) {
    (Some(_), None) => Some("keep")
    (Some(i), Some(at)) => Some(fdrag_effect(i, at.station, @ui.mods_held()))
    (None, Some(_)) => Some("upload")
    (None, None) => None
  }
}

///|
/// Each frame of the files' page, before it is built: the drag moved on or let go, files from outside held or let go,
/// those read going up, the target under the pointer.
fn fdrag_frame(c : @ui.Ctx, src : Source, w : Workspace, outside? : Bool = true) -> Unit {
  if fdrag.frame == c.frame_number() {
    return
  }
  fdrag.frame = c.frame_number()
  let (px, py, down) = c.pointer()
  // the targets drawn last frame are where a drop lands now
  fdrag.drawn = fdrag.targets
  fdrag.targets = []
  match (fdrag.press, fdrag.item) {
    (Some((item, x0, y0)), None) if down =>
      if (px - x0).abs() > fdrag_slop || (py - y0).abs() > fdrag_slop {
        fdrag.item = Some(item)
        fdrag.press = None
        wide.files_chosen = item.station + "\u{1}" + item.root + "\u{1}" + item.path
      }
    (_, Some(item)) if !down => {
      match fdrag_at(c, px, py) {
        Some(t) => fdrag_drop(c, src, w, item, t, @ui.mods_held())
        None => ()
      }
      fdrag.item = None
      fdrag.press = None
    }
    _ => if !down { fdrag.press = None }
  }
  // files from the computer let go: read as a pick's, then up into the folder they were let go on (on the files' page)
  while outside {
    match @ui.take_drop() {
      Some((x, y, pick)) =>
        match fdrag_at(c, x, y) {
          Some({ into: Some(into), .. }) => fdrag.dropped.push((pick, into))
          _ => pick.files() |> ignore
        }
      None => break
    }
  }
  let still : Array[(@ui.Pick, DriveAt)] = []
  for d in fdrag.dropped {
    let (pick, into) = d
    match pick.files() {
      // (up once the frame's builds are over)
      Some(files) => c.after_build("files-put-up", fn() { fdrag_put_up(src, into, files) })
      None => still.push(d)
    }
  }
  fdrag.dropped = still
  // drops whose folder has been read since
  let waiting = fdrag.later
  fdrag.later = []
  for f in waiting {
    if !f() {
      fdrag.later.push(f)
    }
  }
  fdrag.over = match (fdrag.item, @ui.files_held()) {
    (Some(_), _) =>
      match fdrag_at(c, px, py) {
        Some(t) => t.key
        None => ""
      }
    (None, Some((x, y))) =>
      match fdrag_at(c, x, y) {
        Some(t) => t.key
        None => ""
      }
    _ => ""
  }
}

///|
/// Files from the computer into `into` (browse.ts dropInto, putFolder): each folder made there first (one there already
/// filled, as Finder merges), then each file up into its folder.
fn fdrag_put_up(src : Source, into : DriveAt, files : Array[@hostapi.Picked]) -> Unit {
  let root = into.root.unwrap_or("")
  let folders = files.filter(fn(f) { f.name.has_suffix("/") }).map(fn(f) { f.name.view(end_offset=f.name.length() - 1).to_string() })
  let up = files.filter(fn(f) { !f.name.has_suffix("/") })
  let send = fn() {
    for f in up {
      let dir = dv_join(into.path, dv_parent(f.name))
      dv.serial += 1
      dv.uploads.push({
        serial: dv.serial,
        station: into.station,
        root,
        dir,
        name: dv_name(f.name),
        bytes: f.bytes,
        sent: 0,
        state: "waiting",
        error: "",
        replace: false,
        id: "",
      })
    }
    dv_pump(src)
  }
  // (one after another: a folder's parent made before it)
  fn make(i : Int) {
    if i >= folders.length() {
      send()
      return
    }
    (src.call)(
      "drive.mkdir",
      { "station": Json::string(into.station), "root": Json::string(root), "path": Json::string(dv_join(into.path, folders[i])) },
      fn(_) { make(i + 1) },
    )
  }
  make(0)
}

///|
/// What is carried let go on `t`: kept in 个人收藏 (a folder), or moved or copied into its folder.
fn fdrag_drop(c : @ui.Ctx, src : Source, w : Workspace, item : FDragged, t : FTarget, mods : Int) -> Unit {
  match t.into {
    None => {
      let favs = files_favs(src, w.id)
      if !favs.iter().any(fn(f) { f.station == item.station && f.root == item.abs && f.path == "" }) {
        let kept : Array[Fav] = [{ station: item.station, root: item.abs, path: "", name: item.name }]
        for f in favs {
          kept.push(f)
        }
        files_keep_favs(src, w.id, kept)
      }
    }
    Some(into) => {
      let move = fdrag_effect(item, into.station, mods) == "move"
      let anywhere = match dv_stations(src, w.id).0 {
        Some(l) =>
          match l.iter().find_first(fn(s) { s.station == into.station }) {
            Some(s) => s.anywhere
            None => false
          }
        None => false
      }
      let go = fn() { fdrag_transfer(c, src, item, into, move, t.name, anywhere) }
      if !go() {
        fdrag.later.push(go)
      }
    }
  }
}

///|
/// Where `name` goes in the folder `folder`, as an absolute path (useDrive.ts childOf).
fn fdrag_child(folder : String, name : String) -> String {
  if folder.has_suffix("/") {
    folder + name
  } else {
    folder + "/" + name
  }
}

///|
/// Whether `path` is `top` or under it.
fn fdrag_under(path : String, top : String) -> Bool {
  path == top || path.has_prefix(if top.has_suffix("/") { top } else { top + "/" })
}

///|
/// The rename a move of `item` into `into` within its station is (order.ts movesOf): by a root both places are under
/// (the one it was dragged from, or the folder's), else, for one who browses every folder, by the top of the disk;
/// None where there is none (another station's, or no root holds both).
fn fdrag_rename(item : FDragged, into : DriveAt, anywhere : Bool) -> (String, String, String)? {
  if item.station != into.station {
    return None
  }
  let into_root = into.root.unwrap_or("")
  let dest = dv_absolute(into_root, into.path)
  let target = fdrag_child(dest, item.name)
  if target == item.abs || fdrag_under(dest, item.abs) {
    return None
  }
  let root = if fdrag_under(item.abs, item.root) && fdrag_under(target, item.root) {
    Some(item.root)
  } else if fdrag_under(item.abs, into_root) && fdrag_under(target, into_root) {
    Some(into_root)
  } else if anywhere {
    Some("/")
  } else {
    None
  }
  match root {
    Some(r) => {
      let rel = fn(abs : String) {
        if abs == r {
          ""
        } else {
          let s = abs.view(start_offset=r.length()).to_string()
          if s.has_prefix("/") {
            s.view(start_offset=1).to_string()
          } else {
            s
          }
        }
      }
      Some((r, rel(item.abs), rel(target)))
    }
    None => None
  }
}

///|
/// The name Finder gives a copy kept beside one of the same name (order.ts keptName): 名字 2.txt, 名字 3.txt…
fn fdrag_kept_name(taken : Array[String], name : String, dir : Bool) -> String {
  let names = taken.map(fn(n) { n.to_lower() })
  let dot = if dir {
    -1
  } else {
    match name.rev_find(".") {
      Some(i) => i
      None => -1
    }
  }
  let (stem, ext) = if dot > 0 {
    (name.view(end_offset=dot).to_string(), name.view(start_offset=dot).to_string())
  } else {
    (name, "")
  }
  let mut n = 2
  while names.contains((stem + " " + n.to_string() + ext).to_lower()) {
    n += 1
  }
  stem + " " + n.to_string() + ext
}

///|
/// `item` into the folder `into` (transfer.ts transfer): not into itself, nor where it is already; a name there asked
/// about first. A move within its station by a root both places are under is a rename there (the one there to the
/// trash first, or this one beside it named as a copy kept); anything else the stations' transfer (`drive.transfer`).
/// False while the folder it goes into is not read yet (asked again as it is).
fn fdrag_transfer(
  c : @ui.Ctx,
  src : Source,
  item : FDragged,
  into : DriveAt,
  move : Bool,
  into_name : String,
  anywhere : Bool,
) -> Bool {
  let into_root = into.root.unwrap_or("")
  if item.station == into.station && item.root == into_root &&
    (dv_parent(item.path) == into.path || into.path == item.path || into.path.has_prefix(item.path + "/")) {
    return true
  }
  let entries = match files_entries(src, into.station, into_root, into.path) {
    (Some(list), _) => list
    // (one that cannot be read: no names there to ask about)
    (None, Some(_)) => []
    (None, None) => return false
  }
  let clash = entries.iter().find_first(fn(e) { e.name.to_lower() == item.name.to_lower() })
  let go = fn(answers : Map[String, String]) {
    let answer = answers.get(item.name)
    if answer == Some("skip") {
      return
    }
    let what = tr(if move { "web-pages.drive.moveWhat" } else { "web-pages.files.copyWhat" })
    match (move, fdrag_rename(item, into, anywhere)) {
      (true, Some((root, from, to))) => {
        let rename = fn(to : String) {
          (src.call)(
            "drive.rename",
            { "station": Json::string(into.station), "root": Json::string(root), "from": Json::string(from), "to": Json::string(to) },
            dv_act(c, what),
          )
        }
        match answer {
          Some("replace") =>
            (src.call)(
              "drive.remove",
              { "station": Json::string(into.station), "root": Json::string(into_root), "path": Json::string(dv_join(into.path, item.name)) },
              fn(_) { rename(to) },
            )
          Some("keep") => {
            let kept = fdrag_kept_name(entries.map(fn(e) { e.name }), item.name, item.dir)
            rename(dv_join(dv_parent(to), kept))
          }
          _ => rename(to)
        }
      }
      _ => {
        let conflicts : Map[String, Json] = {}
        match answer {
          Some(a) => conflicts[item.name] = Json::string(a)
          None => ()
        }
        (src.call)(
          "drive.transfer",
          {
            "from": {
              "station": Json::string(item.station),
              "root": Json::string(item.root),
              "path": Json::string(dv_parent(item.path)),
              "names": [Json::string(item.name)],
            },
            "to": { "station": Json::string(into.station), "root": Json::string(into_root), "path": Json::string(into.path) },
            "move": Json::boolean(move),
            "conflicts": Json::object(conflicts),
          },
          dv_act(c, what),
        )
      }
    }
  }
  match clash {
    Some(e) =>
      fdrag.asking = Some({
        into,
        into_name,
        total: 1,
        clashes: [{ name: item.name, dir: item.dir, size: item.size, station: item.station_name, there: e }],
        answers: {},
        all: false,
        done: go,
      })
    None => go({})
  }
  true
}

///|
/// What is asked about a name already where files go (Transfers.tsx TransferAsk): each name in turn (or all the rest
/// the same way): 跳过, 保留两者, 替换; let go, nothing goes.
fn files_clash_dialog(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  let (asking, now) = match fdrag.asking {
    Some(a) =>
      match a.clashes.iter().find_first(fn(x) { !a.answers.contains(x.name) }) {
        Some(n) => (Some(a), Some(n))
        None => (Some(a), None)
      }
    None => (None, None)
  }
  let title = match (asking, now) {
    (Some(a), Some(n)) =>
      fill(if n.dir { "web-pages.files.clashFolder" } else { "web-pages.files.clash" }, [("folder", a.into_name), ("name", n.name)])
    _ => ""
  }
  let answer = fn(a : FAsking, n : FClash, said : String) {
    let left = a.clashes.filter(fn(x) { !a.answers.contains(x.name) })
    if a.all {
      for x in left {
        a.answers[x.name] = said
      }
    } else {
      a.answers[n.name] = said
    }
    if a.clashes.iter().all(fn(x) { a.answers.contains(x.name) }) {
      fdrag.asking = None
      (a.done)(a.answers)
    }
  }
  let d = @sf.dialog(
    c,
    "files-clash",
    now is Some(_),
    title,
    description=match asking {
      Some(a) if a.clashes.length() > 1 =>
        fill("web-pages.files.clashCount", [("n", a.total.to_string()), ("clashes", a.clashes.length().to_string())])
      _ => ""
    },
    w=dmin(fclash_w, c.width - fgo_margin),
    close_label=tr("common.close"),
    fn() {
      match (asking, now) {
        (Some(a), Some(n)) => {
          c.box(style=fclash_facts, fn() {
            c.box(style=fpane_facts_column, fn() {
              c.text(tr("web-pages.files.coming"), style=fpane_fact_said) |> ignore
              c.text(tr("web-pages.files.there"), style=fpane_fact_said) |> ignore
            })
            |> ignore
            c.box(style=fpane_values_column, fn() {
              let coming = if n.dir { tr("web-pages.files.folder") } else { @sf.file_size(n.size) }
              c.text(coming + " · " + n.station, style=fpane_fact_value) |> ignore
              let there = if n.there.dir { tr("web-pages.files.folder") } else { n.there.size_text }
              c.text(there + " · " + n.there.time_text, style=fpane_fact_value) |> ignore
            })
            |> ignore
          })
          |> ignore
          c.text(tr("web-pages.files.replaceNote"), style=fgo_note) |> ignore
          let left = a.clashes.filter(fn(x) { !a.answers.contains(x.name) })
          if left.length() > 1 {
            let id = c.id("files-clash/all")
            c.cursor(id, Hand)
            if c.clicked(id) {
              a.all = !a.all
            }
            c.box(style=fclash_all, id~, fn() {
              @sf.icon(c, if a.all { "check-circle" } else { "square" }, size=files_icon, color=if a.all { t.p.accent } else { t.p.muted })
              |> ignore
              c.text(fill("web-pages.files.applyAll", [("n", (left.length() - 1).to_string())]), style=fgo_note) |> ignore
            })
            |> ignore
          }
          c.box(style=fclash_foot, fn() {
            if @sf.button(c, tr("web-pages.files.skip"), key="files-clash/skip", tone=Ghost) {
              answer(a, n, "skip")
            }
            if @sf.button(c, tr("web-pages.drive.keepBoth"), key="files-clash/keep") {
              answer(a, n, "keep")
            }
            if @sf.button(c, tr("web-pages.drive.replace"), key="files-clash/replace", tone=Primary, icon="trash") {
              answer(a, n, "replace")
            }
          })
          |> ignore
        }
        _ => ()
      }
    },
  )
  if !d && now is Some(_) {
    // let go (Escape, a press outside): nothing goes
    fdrag.asking = None
  }
}

///|
/// What is carried, under the pointer (the drag's picture): its mark and its name on a raised chip, and what a drop
/// where it is would do.
fn fdrag_ghost(c : @ui.Ctx, page : Int) -> Unit {
  let t = @sf.theme()
  match (fdrag.item, c.rect_of(page)) {
    (Some(i), Some((x0, y0, _, _))) => {
      let (px, py, _) = c.pointer()
      c.layer(fn() {
        c.box(style=fdrag_ghost_place, tx=px - x0 + fdrag_ghost_off, ty=py - y0 + fdrag_ghost_off, fn() {
          c.box(style=fdrag_ghost_chip, fn() {
            @sf.icon(c, dv_kind_icon(if i.dir { "folder" } else { dv_kind_of(i.name) }), size=files_icon, color=t.p.muted)
            |> ignore
            c.text(i.name, style=files_chip_words) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    _ => ()
  }
}

///|
/// A file's kind by its name, for its mark while it is carried (the folder's listing said it; this is only the picture).
fn dv_kind_of(name : String) -> String {
  match dv_ext(name) {
    "md" | "markdown" => "markdown"
    "txt" | "log" => "text"
    "png" | "jpg" | "jpeg" | "gif" | "webp" | "heic" => "image"
    "mp4" | "mov" | "mkv" | "webm" => "video"
    "mp3" | "m4a" | "wav" | "flac" => "audio"
    "pdf" => "pdf"
    "csv" => "csv"
    _ => "other"
  }
}

///|
/// What is held over the folder shown (Drive.css.ts drop): over the list, where it goes, in words.
fn fdrag_over_pane(c : @ui.Ctx, lit : String, name : String) -> Unit {
  let t = @sf.theme()
  c.layer(fn() {
    c.box(style=fdrag_pane_drop, fn() {
      @sf.icon(c, if lit == "upload" { "upload" } else { "move" }, size=fdrag_drop_icon, color=t.p.text) |> ignore
      let key = match lit {
        "copy" => "web-pages.files.copyHere"
        "move" => "web-pages.files.moveHere"
        _ => "web-pages.drive.dropHere"
      }
      c.text(fill(key, [("name", name)]), style=fdrag_drop_words) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A folder of the sidebar that takes a drop (FilesNav.tsx FolderDrop): its row, ringed while what it takes is over it,
/// saying what a drop does.
fn fdrag_side_row(
  c : @ui.Ctx,
  key : String,
  into : DriveAt,
  name : String,
  write : Bool,
  transfers : Bool,
  row : () -> Unit,
) -> Unit {
  let id = c.id("files/drop/" + key)
  let lit = fdrag_target(c, id, "side/" + key, Some(into), name, write, transfers, 1, outside=false)
  c.box(style=if lit is Some(_) { fdrag_side_on } else { fdrag_side }, id~, fn() {
    row()
    match lit {
      Some(l) =>
        c.layer(fn() {
          c.box(style=fdrag_says_place, fn() {
            c.box(style=fdrag_says, fn() {
              c.text(tr(if l == "copy" { "web-pages.files.copyHereShort" } else { "web-pages.files.moveHereShort" }), style=fdrag_says_words)
              |> ignore
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      None => ()
    }
  })
  |> ignore
}

///|
/// The clash dialog (Dialog: 420 wide).
let fclash_w : Double = 420.0

///|
/// The drag's picture this far from the pointer (down and right of it).
let fdrag_ghost_off : Double = 12.0

///|
/// The drop's mark over the list (22).
let fdrag_drop_icon : Double = 22.0

///|
// kept across runs: a value (no field of it changes)
let fclash_foot : @ui.Style = @ui.style(row=true, w=Full, pt=S2, gap=S2, justify=JEnd)

///|
/// What comes and what is there (clash: 10 by 12 in, the field's corner, the neutral ground).
// kept across runs: a value (no field of it changes)
let fclash_facts : @ui.Style = @ui.style(row=true, w=Full, px=S3, py=S2_5, gap=S3, radius=Xl, bg=Neutral)

///|
// kept across runs: a value (no field of it changes)
let fclash_all : @ui.Style = @ui.style(row=true, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let fdrag_ghost_place : @ui.Style = @ui.style(w=Full, h=Full, align=AStart)

///|
/// The picture carried: a chip on the raised ground, its shadow under it.
// kept across runs: a value (no field of it changes)
let fdrag_ghost_chip : @ui.Style = @ui.style(row=true, h=S8, px=S3, gap=S2, align=ACenter, radius=Lg, bg=Raised, shadow=Lg, opacity=O90)

///|
/// Over the list (drop: the canvas at 82% over it, ringed 2 in the accent at 60%, its words in the middle, 8 apart).
// kept across runs: a value (no field of it changes)
let fdrag_pane_drop : @ui.Style = @ui.style(
  w=Full,
  h=Full,
  gap=S2,
  align=ACenter,
  justify=JCenter,
  radius=Xl3,
  bg=A(Bg, O80),
  border=B2,
  border_color=A(Accent, O60),
)

///|
// kept across runs: a value (no field of it changes)
let fdrag_drop_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false)

///|
/// A folder's row of the sidebar (drop: the nav row's corner), ringed in the accent on its ground while over it.
// kept across runs: a value (no field of it changes)
let fdrag_side : @ui.Style = @ui.style(w=Full, radius=Xl)

///|
// kept across runs: a value (no field of it changes)
let fdrag_side_on : @ui.Style = fdrag_side.then(@ui.style(bg=AccentBg, border=B1, border_color=Accent))

///|
// kept across runs: a value (no field of it changes)
let fdrag_says_place : @ui.Style = @ui.style(row=true, w=Full, h=Full, pr=S2, align=ACenter, justify=JEnd)

///|
/// What a drop there does (dropSays: a capsule in the accent, 7 in, its words 11 bold on it).
// kept across runs: a value (no field of it changes)
let fdrag_says : @ui.Style = @ui.style(px=S1_5, py=SPx, radius=Full, bg=Accent)

///|
// kept across runs: a value (no field of it changes)
let fdrag_says_words : @ui.TextStyle = @ui.text_style(size=Xs2, weight=Semibold, color=OnPrimary, wrap=false)

///|
/// 个人收藏 while a folder dragged over it would be kept there (keep: ringed in the accent).
// kept across runs: a value (no field of it changes)
let fdrag_keep : @ui.Style = @ui.style(w=Full, radius=Xl)

///|
// kept across runs: a value (no field of it changes)
let fdrag_keep_on : @ui.Style = fdrag_keep.then(@ui.style(border=B1, border_color=Accent))

///|
/// A folder's row (entry's data-drop: the accent's ground, ringed 1 in it), a column (its ground).
// kept across runs: a value (no field of it changes)
let files_row_drop : @ui.Style = files_row_style.then(@ui.style(bg=AccentBg, border=B1, border_color=Accent))

///|
// kept across runs: a value (no field of it changes)
let files_column_drop : @ui.Style = @ui.style(bg=AccentBg)

// ── the transfers (Transfers.tsx TransfersButton, TransferRow) ─────────

///|
/// The person's transfers into the workspace's stations (the `driveTransfers` topic), newest first.
fn files_transfer_list(src : Source, ws : String) -> Array[Json] {
  items((src.topic)("driveTransfers", { "workspace": Json::string(ws) }).value, "transfers")
}

///|
/// On the bar: the transfers, how many go and how far they are (in the accent while they go, red when one failed);
/// pressed, their list. Nothing while there has been none.
fn files_transfers(c : @ui.Ctx, src : Source, ws : String) -> Unit {
  let t = @sf.theme()
  let all = files_transfer_list(src, ws)
  let id = c.id("files/transfers")
  if all.length() == 0 {
    fgo.transfers = false
    return
  }
  let going = all.filter(fn(x) { flag(Some(x), "active") })
  let failed = all.iter().any(fn(x) { text(Some(x), "state") == "failed" })
  let total = going.fold(init=0.0, fn(a, x) { a + number(Some(x), "total") })
  let copied = going.fold(init=0.0, fn(a, x) { a + number(Some(x), "copied") })
  let label = if going.length() > 0 {
    let percent = if total > 0.0 { (copied / total * 100.0).floor().to_int() } else { 0 }
    fill("web-pages.files.transfersGoing", [("n", going.length().to_string()), ("percent", percent.to_string())])
  } else {
    tr("web-pages.files.transfers")
  }
  c.cursor(id, Hand)
  if c.clicked(id) {
    fgo.transfers = !fgo.transfers
  }
  let (style, words, ink) = if failed {
    (ftransfers_chip_failed, ftransfers_chip_failed_words, t.p.red)
  } else if going.length() > 0 {
    (ftransfers_chip_going, ftransfers_chip_going_words, t.p.accent_text)
  } else {
    (ftransfers_chip, ftransfers_chip_words, t.p.muted)
  }
  let b = c.box(style~, id~, fn() {
    @sf.icon(c, "move", size=files_close_icon, color=ink) |> ignore
    c.text(label, style=words) |> ignore
  })
  c.semantics(b, Button, id~, label~)
  let p = @kit.popover(
    c,
    "files/transfers-pop",
    fgo.transfers,
    id,
    side=Bottom,
    along=End,
    look=fn(c, _, body) { @sf.panel(c, w=Px(ftransfers_w), body) |> ignore },
    fn() {
      c.box(style=ftransfers_head, fn() { c.text(tr("web-pages.files.transfers"), style=ftransfers_head_words) |> ignore })
      |> ignore
      for x in all {
        files_transfer_row(c, src, x)
      }
    },
  )
  fgo.transfers = fgo.transfers && p.value
}

///|
/// A transfer (TransferRow): its mark, what goes and where, how far (a bar while it copies), how it stands; stopped
/// while it goes, tried again once failed, its folder shown once done.
fn files_transfer_row(c : @ui.Ctx, src : Source, x : Json) -> Unit {
  let t = @sf.theme()
  let j = Some(x)
  let state = text(j, "state")
  let station = text(j, "station")
  let tid = text(j, "id")
  let way = if text(j, "fromStation") == station {
    fill("web-pages.files.into", [("to", text(j, "toText"))])
  } else {
    fill("web-pages.files.fromInto", [("from", text(j, "fromStationName")), ("to", text(j, "toText"))])
  }
  let call = fn(name : String) {
    (src.call)(name, { "station": Json::string(station), "id": Json::string(tid) }, dv_act(c, tr("web-pages.files.transferWhat")))
  }
  c.box(style=files_bar_rule, fn() {  }) |> ignore
  c.box(style=ftransfer_row, fn() {
    let (mark, ink) = match state {
      "done" => ("check", t.p.green)
      "failed" => ("retry", t.p.red)
      "cancelled" => ("close", t.p.muted)
      _ => ("move", t.p.muted)
    }
    c.box(style=ftransfer_mark, fn() { @sf.icon(c, mark, size=files_close_icon, color=ink) |> ignore }) |> ignore
    c.box(style=ftransfer_text, fn() {
      c.box(style=ftransfer_title, fn() {
        c.text(text(j, "title"), style=ftransfer_title_words) |> ignore
        c.text(if flag(j, "move") { fill("web-pages.files.moving", [("way", way)]) } else { way }, style=ftransfer_way) |> ignore
      })
      |> ignore
      if state == "copying" {
        fdrag_bar(c, ftransfer_bar, ftransfer_bar_done, number(j, "progress"))
      }
      let files = number(j, "files").to_int()
      let status = text(j, "statusText") +
        (if (state == "copying" || state == "done") && files > 1 {
          " · " + fill("web-pages.files.filesCount", [("n", files.to_string())])
        } else {
          ""
        })
      c.text(status, style=if state == "failed" { ftransfer_failed } else { ftransfer_status }) |> ignore
    })
    |> ignore
    c.box(style=ftransfer_actions, fn() {
      if flag(j, "active") && icon_button(c, "files/transfer/cancel/" + tid, "close", label=tr("web-pages.files.cancelTransfer")) {
        call("drive.transfer.cancel")
      }
      if state == "failed" && icon_button(c, "files/transfer/retry/" + tid, "retry", label=tr("web-pages.drive.retry")) {
        call("drive.transfer.retry")
      }
      if state == "done" && @sf.button(c, tr("web-pages.files.show"), key="files/transfer/show/" + tid, tone=Ghost) {
        fgo.transfers = false
        files_go({ station, root: Some(text(j, "toRoot")), path: text(j, "toPath") })
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A file going up into the folder shown (Drive.tsx UploadRow): its mark, its name, how far (a thin bar, sent of its
/// size); its name taken there (替换, 保留两者), or why it failed (重试); × lets it go.
fn files_upload_row(c : @ui.Ctx, src : Source, u : DvUpload, entries : Array[DvEntry]) -> Unit {
  let t = @sf.theme()
  let k = "files/up/\{u.serial}"
  c.box(style=files_row_style, fn() {
    @sf.icon(c, "upload", size=files_icon, color=t.p.muted) |> ignore
    c.text(u.name, style=place_name) |> ignore
    match u.state {
      "taken" =>
        c.box(style=fupload_ask, fn() {
          c.text(tr("web-pages.drive.taken"), style=files_cell_words) |> ignore
          if @sf.button(c, tr("web-pages.drive.replace"), key=k + "/replace", tone=Ghost) {
            u.replace = true
            u.state = "waiting"
            dv_pump(src)
          }
          if @sf.button(c, tr("web-pages.drive.keepBoth"), key=k + "/both", tone=Ghost) {
            let others = dv.uploads.filter(fn(x) { x.serial != u.serial && x.dir == u.dir })
            u.name = dv_free_name(u.name, entries.map(fn(e) { e.name }) + others.map(fn(x) { x.name }))
            u.state = "waiting"
            dv_pump(src)
          }
        })
        |> ignore
      "failed" => c.text(fill("web-pages.drive.uploadFailed", [("error", u.error)]), style=fupload_failed) |> ignore
      _ => {
        let size = u.bytes.length()
        c.box(style=fupload_cell, fn() {
          fdrag_bar(c, fupload_bar, fupload_bar_done, if size > 0 { u.sent.to_double() / size.to_double() } else { 0.0 })
          c.text(
            fill("web-pages.drive.uploading", [("sent", @sf.file_size(u.sent.to_double())), ("size", @sf.file_size(size.to_double()))]),
            style=files_cell_words,
          )
          |> ignore
        })
        |> ignore
      }
    }
    if u.state == "failed" && icon_button(c, k + "/retry", "retry", label=tr("web-pages.drive.retry")) {
      u.state = "waiting"
      u.error = ""
      u.sent = 0
      dv_pump(src)
    }
    if icon_button(c, k + "/cancel", "close", label=tr("common.cancel")) {
      dv.uploads.retain(fn(x) { x.serial != u.serial })
      if u.state == "going" {
        dv.pumping = false
        dv_pump(src)
      }
    }
  })
  |> ignore
}

///|
/// How far something has got, a bar `bar` filled from its start by `done` (0 … 1).
fn fdrag_bar(c : @ui.Ctx, bar : @ui.Style, done : @ui.Style, part : Double) -> Unit {
  let p = dmax(0.0, dmin(1.0, part))
  let rest = 1.0 - p
  c.box(style=bar, fn() {
    c.box(style=done.then(@ui.style(w=Grow(p))), fn() {  }) |> ignore
    c.box(style=@ui.style(w=Grow(rest)), fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// The transfers' list (transfers: 360 wide).
let ftransfers_w : Double = 360.0

///|
/// A file's bar going up (progress: 2 high, as wide as the size's and the time's columns less the words).
let fupload_bar_w : Double = 96.0

///|
/// The chip (transfersChip: 28 high, 10 in, the neutral ground, its words muted; going: the accent's; failed: red's).
// kept across runs: a value (no field of it changes)
let ftransfers_chip : @ui.Style = @ui.style(row=true, h=S7, px=S2_5, gap=S1_5, align=ACenter, radius=Full, bg=Neutral)

///|
// kept across runs: a value (no field of it changes)
let ftransfers_chip_going : @ui.Style = ftransfers_chip.then(@ui.style(bg=AccentBg))

///|
// kept across runs: a value (no field of it changes)
let ftransfers_chip_failed : @ui.Style = ftransfers_chip.then(@ui.style(bg=DangerBg))

///|
// kept across runs: a value (no field of it changes)
let ftransfers_chip_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ftransfers_chip_going_words : @ui.TextStyle = @ui.text_style(size=Xs, color=AccentText, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ftransfers_chip_failed_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Danger, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ftransfers_head : @ui.Style = @ui.style(w=Full, px=S2, pt=S1, pb=S2)

///|
// kept across runs: a value (no field of it changes)
let ftransfers_head_words : @ui.TextStyle = @ui.text_style(size=Xs, weight=Semibold, color=Fg, wrap=false)

///|
/// A transfer (transfer: its mark 18, its words, its keys; 8 in, 8 apart, a line over it).
// kept across runs: a value (no field of it changes)
let ftransfer_row : @ui.Style = @ui.style(row=true, w=Full, p=S2, gap=S2, align=AStart)

///|
// kept across runs: a value (no field of it changes)
let ftransfer_mark : @ui.Style = @ui.style(w=S4_5, h=S4_5, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let ftransfer_text : @ui.Style = @ui.style(w=@sf.grow, gap=S1, clip=true)

///|
// kept across runs: a value (no field of it changes)
let ftransfer_title : @ui.Style = @ui.style(row=true, gap=S1, clip=true)

///|
// kept across runs: a value (no field of it changes)
let ftransfer_title_words : @ui.TextStyle = @ui.text_style(size=Xs, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ftransfer_way : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// Its bar (transferBar: 4 high, its corner 2, the line's ground, the accent's done).
// kept across runs: a value (no field of it changes)
let ftransfer_bar : @ui.Style = @ui.style(row=true, w=Full, h=S1, radius=Sm, bg=Line, clip=true)

///|
// kept across runs: a value (no field of it changes)
let ftransfer_bar_done : @ui.Style = @ui.style(h=Full, bg=Accent)

///|
// kept across runs: a value (no field of it changes)
let ftransfer_status : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ftransfer_failed : @ui.TextStyle = @ui.text_style(size=Xs, color=Danger, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ftransfer_actions : @ui.Style = @ui.style(row=true, gap=SPx, align=ACenter)

///|
/// A file going up: its bar and how far (progressCell: 10 apart), what to do with a name taken (ask), why it failed.
// kept across runs: a value (no field of it changes)
let fupload_cell : @ui.Style = @ui.style(row=true, gap=S2_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let fupload_bar : @ui.Style = @ui.style(row=true, w=Fixed(fupload_bar_w), h=SPx, radius=Sm, bg=A(Fg, O10), clip=true)

///|
// kept across runs: a value (no field of it changes)
let fupload_bar_done : @ui.Style = @ui.style(h=Full, bg=Accent)

///|
// kept across runs: a value (no field of it changes)
let fupload_ask : @ui.Style = @ui.style(row=true, gap=S1, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let fupload_failed : @ui.TextStyle = @ui.text_style(size=Xs, color=Danger, wrap=false)

///|
/// 本机 by this machine's station (here: a capsule on the accent's ground, its words 11 in the accent's ink).
// kept across runs: a value (no field of it changes)
let files_here_chip : @ui.Style = @ui.style(px=S1_25, radius=Full, bg=AccentBg)

///|
// kept across runs: a value (no field of it changes)
let files_here_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=AccentText, wrap=false)
