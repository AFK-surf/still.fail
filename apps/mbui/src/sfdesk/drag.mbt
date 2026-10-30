// What is dragged on the files' page (ember web/src/drive/drag.ts, browse.ts takes / effectOf / dropInto, transfer.ts,
// FilesNav.tsx useFolderDrop): a row pressed and moved past a few points carries its file or folder under the pointer;
// let go on a folder (a folder's row, a column, the folder shown, a folder of the sidebar) it goes there: within its
// station moved (⌥: copied), to another station copied (⌘: moved), as Finder does across disks; a folder let go on 个人
// 收藏 is kept there. A move within a station by a root both places are under (the core's `drive.moves`) is a rename
// there (a copy kept beside one of the same name named by `drive.name`), anything else the core's `drive.transfer`
// (the stations copy between them; the bar's 传输 follows it); a name already there is asked about first (替换, 保留两者,
// 跳过). Files from the computer (Finder) let go on a folder go up into it, a folder of them made there and filled.

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
pub(all) struct Clash {
  name : String
  dir : Bool
  size : Double
  station : String
  there : DvEntry
}

///|
/// What is asked now (transfer.ts Asking): where they go, its name, how many go, the names there, the answers so far,
/// whether the next is said for all the rest, and what is done with the answers.
pub(all) struct Asking {
  into : DriveAt
  into_name : String
  total : Int
  clashes : Array[Clash]
  answers : Map[String, String]
  all : @signals.Signal[Bool]
  done : (Map[String, String]) -> Unit
}

///|
/// The drag: a row pressed (what, where), what is carried once it moved, the targets drawn last frame and this one,
/// the one under the pointer, files dropped from outside still being read (their pick, where they go), what is asked.
priv struct FDrag {
  press : @signals.Signal[(Dragged, Double, Double)?]
  /// (told as it changes: what shows it carried, built before what takes it in the frame, built again for it)
  item : @signals.Signal[Dragged?]
  // (targets, drawn, dropped, later plain: the frame's own work (where it may drop, as laid out; drops and asks to
  // take up), read by the frame that does it, not shown)
  mut targets : Array[FTarget]
  mut drawn : Array[FTarget]
  over : @signals.Signal[String]
  mut dropped : Array[(@ui.Pick, DriveAt)]
  asking : @signals.Signal[Asking?]
  /// drops waiting for the folder they go into to be read (what is there by their names asked about first): each done
  /// once it is (true)
  mut later : Array[() -> Bool]
  /// the frame this was last moved on in (the sidebar and the folder both ask; the first does it)
  mut frame : Int
}

///|
// kept across runs: the drag's state (drag_reset puts it back)
let fdrag : FDrag = {
  press: @signals.signal(None),
  item: @signals.signal(None),
  targets: [],
  drawn: [],
  over: @signals.signal("", same=fn(a, b) { a == b }),
  dropped: [],
  asking: @signals.signal(None),
  later: [],
  frame: -1,
}

///|
fn drag_reset() -> Unit {
  fdrag.press.set(None)
  fdrag.item.set(None)
  fdrag.targets = []
  fdrag.drawn = []
  fdrag.over.set("")
  fdrag.dropped = []
  fdrag.asking.set(None)
  fdrag.later = []
  fdrag.frame = -1
  fclash_shown.val = 0
}

///|
/// How far a press moves before it is a drag (a click's slop).
let fdrag_slop : Double = 4.0

///|
/// A row pressed: what it would carry, where the pointer went down.
fn fdrag_press(c : @ui.Ctx, item : Dragged) -> Unit {
  // (a mouse's: a finger moving on a row moves the list, as the web's rows, which a touch drags nothing of; a file is
  // moved there by its menu)
  if !@sf.pointer_rests() {
    return
  }
  if fdrag.press.get() is None && fdrag.item.get() is None {
    // (where it went down: the frame that sees the press may see it moved already)
    fdrag.press.set(Some((item, c.press_x, c.press_y)))
  }
}

///|
/// Whether a row is what is being dragged.
fn fdrag_carried(station : String, root : String, path : String) -> Bool {
  match fdrag.item.get() {
    Some(i) => i.station == station && i.root == root && i.path == path
    None => false
  }
}

///|
/// What a drop of `item` into a folder of `station` does (browse.ts effectOf): across stations a copy (⌘: a move),
/// within one a move (⌥: a copy).
fn fdrag_effect(item : Dragged, station : String, mods : Int) -> String {
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
  match (fdrag.item.get(), t.into) {
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
  if fdrag.over.get() != key {
    return None
  }
  match (fdrag.item.get(), into) {
    (Some(_), None) => Some("keep")
    (Some(i), Some(at)) => Some(fdrag_effect(i, at.station, @ui.mods_held()))
    (None, Some(_)) => Some("upload")
    (None, None) => None
  }
}

///|
/// Each frame of the files' page, before it is built: the drag moved on or let go, files from outside held or let go,
/// those read going up, the target under the pointer.
pub fn drag_frame(c : @ui.Ctx, src : Source, ws : String, outside? : Bool = true) -> Unit {
  if fdrag.frame == c.frame_number() {
    return
  }
  fdrag.frame = c.frame_number()
  let (px, py, down) = c.pointer()
  // the targets drawn last frame are where a drop lands now
  fdrag.drawn = fdrag.targets
  fdrag.targets = []
  match (fdrag.press.get(), fdrag.item.get()) {
    (Some((item, x0, y0)), None) if down =>
      if (px - x0).abs() > fdrag_slop || (py - y0).abs() > fdrag_slop {
        fdrag.item.set(Some(item))
        fdrag.press.set(None)
      }
    (_, Some(item)) if !down => {
      match fdrag_at(c, px, py) {
        Some(t) => fdrag_drop(c, src, ws, item, t, @ui.mods_held())
        None => ()
      }
      fdrag.item.set(None)
      fdrag.press.set(None)
    }
    _ => if !down { fdrag.press.set(None) }
  }
  // files from the computer let go on a folder (on the files' page): read as a pick's, then up into it; let go elsewhere
  // they are not taken here (what is there may take them otherwise: a field, by their paths)
  let folder_at = fn(x, y) { fdrag_at(c, x, y) is Some({ into: Some(_), .. }) }
  while outside {
    match @ui.take_drop(over=folder_at) {
      Some((x, y, pick)) =>
        match fdrag_at(c, x, y) {
          Some({ into: Some(into), .. }) => fdrag.dropped.push((pick, into))
          _ => ()
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
  fdrag.over.set(match (fdrag.item.get(), @ui.files_held()) {
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
  })
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
      ups.serial += 1
      ups.uploads.push({
        serial: ups.serial,
        station: into.station,
        root,
        dir,
        name: @signals.signal(dv_name(f.name)),
        bytes: f.bytes,
        sent: @signals.signal(0),
        state: @signals.signal("waiting"),
        error: @signals.signal(""),
        replace: @signals.signal(false, same=fn(a, b) { a == b }),
        id: @signals.signal("", same=fn(a, b) { a == b }),
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
fn fdrag_drop(c : @ui.Ctx, src : Source, ws : String, item : Dragged, t : FTarget, mods : Int) -> Unit {
  match t.into {
    None => {
      favorite_add(src, ws, { station: item.station, root: item.abs, path: "", name: item.name })
    }
    Some(into) => {
      let move = fdrag_effect(item, into.station, mods) == "move"
      let anywhere = match dv_stations(src, ws).0 {
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
/// `item` into the folder `into` (transfer.ts transfer): not into itself, nor where it is already; a name there asked
/// about first. Moved within its station by a root both places are under (the core's `drive.moves`), it is a rename
/// there (the one there to the trash first, or this one beside it named as Finder names a copy kept: `drive.name`);
/// anything else the stations' transfer (`drive.transfer`). False while the folder it goes into is not read yet
/// (asked again as it is).
fn fdrag_transfer(
  c : @ui.Ctx,
  src : Source,
  item : Dragged,
  into : DriveAt,
  move : Bool,
  into_name : String,
  anywhere : Bool,
) -> Bool {
  let into_root = into.root.unwrap_or("")
  if item.station == into.station &&
    item.root == into_root &&
    (dv_parent(item.path) == into.path || into.path == item.path || into.path.has_prefix(item.path + "/")) {
    return true
  }
  let entries = match drive_folder(src, into.station, into_root, into.path) {
    (Some(_), _) => @sfbase.dv_entries(src, into.station, into_root, into.path).unwrap_or([])
    // (one that cannot be read: no names there to ask about)
    (None, Some(_)) => []
    (None, None) => return false
  }
  let what = @sf.t(if move { "web-pages.drive.moveWhat" } else { "web-pages.files.copyWhat" })
  let into_json : Json = { "station": Json::string(into.station), "root": Json::string(into_root), "path": Json::string(into.path) }
  // the stations' copy (or move), the answer about a name there said
  let transfer = fn(answer : String?) {
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
        "to": into_json,
        "move": Json::boolean(move),
        "conflicts": Json::object(conflicts),
      },
      act_done(c, what),
    )
  }
  // renamed within its station: the one there to the trash first, or this one kept beside it under a name of its own
  let rename = fn(m : Json?, answer : String?) {
    let root = text(m, "root")
    let from = text(m, "from")
    let to = text(m, "to")
    let named = fn(to : String) {
      (src.call)(
        "drive.rename",
        { "station": Json::string(into.station), "root": Json::string(root), "from": Json::string(from), "to": Json::string(to) },
        act_done(c, what),
      )
    }
    match answer {
      Some("replace") =>
        (src.call)(
          "drive.remove",
          { "station": Json::string(into.station), "root": Json::string(into_root), "path": Json::string(dv_join(into.path, item.name)) },
          fn(_) { named(to) },
        )
      Some("keep") =>
        (src.call)(
          "drive.name",
          {
            "name": Json::string(item.name),
            "taken": Json::array(entries.map(fn(e) { Json::string(e.name) })),
            "beside": Json::boolean(true),
            "dir": Json::boolean(item.dir),
          },
          fn(r) {
            match r {
              Ok(v) => named(dv_join(dv_parent(to), text(Some(v), "name")))
              Err(_) => ()
            }
          },
        )
      _ => named(to)
    }
  }
  let go = fn(answers : Map[String, String]) {
    let answer = answers.get(item.name)
    if answer == Some("skip") {
      return
    }
    if move && item.station == into.station {
      (src.call)(
        "drive.moves",
        {
          "items": [
            {
              "station": Json::string(item.station),
              "root": Json::string(item.root),
              "abs": Json::string(item.abs),
              "name": Json::string(item.name),
            },
          ],
          "into": into_json,
          "anywhere": Json::boolean(anywhere),
        },
        fn(r) {
          match r {
            Ok(v) =>
              match items(Some(v), "moves") {
                [m] => rename(Some(m), answer)
                _ => transfer(answer)
              }
            Err(e) => act_done(c, what)(Err(e))
          }
        },
      )
    } else {
      transfer(answer)
    }
  }
  match entries.iter().find_first(fn(e) { e.name.to_lower() == item.name.to_lower() }) {
    Some(e) =>
      fdrag.asking.set(Some({
        into,
        into_name,
        total: 1,
        clashes: [{ name: item.name, dir: item.dir, size: item.size, station: item.station_name, there: e }],
        answers: {},
        all: @signals.signal(false, same=fn(a, b) { a == b }),
        done: go,
      }))
    None => go({})
  }
  true
}

///|
/// What is asked about a name already where files go (Transfers.tsx TransferAsk): each name in turn (or all the rest
/// the same way): 跳过, 保留两者, 替换; let go, nothing goes. The library's dialog (@sf.panel, opened by nothing), up
/// while something is asked: its title and what it is about as the name asked about now says them.
fn clash_dialog(c : @ui.Ctx) -> Unit {
  ignore(c)
  match fdrag.asking.get() {
    Some(_) if fclash_shown.val == 0 => {
      @sf.panel(
        "",
        fn(c, _) { clash_body(c) },
        from=Unanchored,
        foot=fn(c, _) { clash_foot(c) },
        live=fn() {
          match clash_now() {
            (Some(a), Some(n)) =>
              (
                @sf.t(if n.dir { "web-pages.files.clashFolder" } else { "web-pages.files.clash" }, args=[
                  ("folder", a.into_name),
                  ("name", n.name),
                ]),
                "",
                if a.clashes.length() > 1 {
                  @sf.t("web-pages.files.clashCount", args=[
                    ("n", a.total.to_string()),
                    ("clashes", a.clashes.length().to_string()),
                  ])
                } else {
                  ""
                },
              )
            _ => ("", "", "")
          }
        },
        // let go (Escape, ✕, a press outside): nothing goes
        gone=fn() {
          fdrag.asking.set(None)
          fclash_shown.val = 0
        },
      )
      fclash_shown.val = @sf.last_presented()
    }
    None if fclash_shown.val > 0 => {
      // (all answered: down)
      @sf.close_presented_of(fclash_shown.val)
      fclash_shown.val = 0
    }
    _ => ()
  }
}

///|
/// The asking's dialog as presented (@sf.last_presented; 0 none).
// kept across runs: put back by drag_reset
let fclash_shown : Ref[Int] = Ref(0)

///|
/// What is asked now, and the name asked about (the first not answered).
fn clash_now() -> (Asking?, Clash?) {
  match fdrag.asking.get() {
    Some(a) =>
      match a.clashes.iter().find_first(fn(x) { !a.answers.contains(x.name) }) {
        Some(n) => (Some(a), Some(n))
        None => (Some(a), None)
      }
    None => (None, None)
  }
}

///|
/// `said` (skip, keep, replace) for the name asked about, or all the rest; all answered, what goes goes.
fn clash_answer(a : Asking, n : Clash, said : String) -> Unit {
  let left = a.clashes.filter(fn(x) { !a.answers.contains(x.name) })
  if a.all.get() {
    for x in left {
      a.answers[x.name] = said
    }
  } else {
    a.answers[n.name] = said
  }
  if a.clashes.iter().all(fn(x) { a.answers.contains(x.name) }) {
    fdrag.asking.set(None)
    (a.done)(a.answers)
  }
}

///|
/// What the dialog holds: what comes and what is there (size or folder, where from, when), what replacing does, the
/// rest the same way.
fn clash_body(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  match clash_now() {
    (Some(a), Some(n)) => {
      c.box(style=fclash_facts, fn() {
        c.box(style=fclash_said_column, fn() {
          c.text(@sf.t("web-pages.files.coming"), style=fclash_said) |> ignore
          c.text(@sf.t("web-pages.files.there"), style=fclash_said) |> ignore
        })
        |> ignore
        c.box(style=fclash_values_column, fn() {
          let coming = if n.dir { @sf.t("web-pages.files.folder") } else { @sf.file_size(n.size) }
          c.text(coming + " · " + n.station, style=fclash_value) |> ignore
          let there = if n.there.dir { @sf.t("web-pages.files.folder") } else { n.there.size_text }
          c.text(there + " · " + n.there.time_text, style=fclash_value) |> ignore
        })
        |> ignore
      })
      |> ignore
      c.text(@sf.t("web-pages.files.replaceNote"), style=clash_note) |> ignore
      let left = a.clashes.filter(fn(x) { !a.answers.contains(x.name) })
      if left.length() > 1 {
        let id = c.id("files-clash/all")
        if c.clicked(id) {
          a.all.set(!a.all.get())
        }
        c.box(style=fclash_all, id~, fn() {
          @sf.icon(c, if a.all.get() { "check-circle" } else { "square" }, size=drag_icon, color=if a.all.get() { t.p.accent } else { t.p.muted })
          |> ignore
          c.text(@sf.t("web-pages.files.applyAll", args=[("n", (left.length() - 1).to_string())]), style=clash_note) |> ignore
        })
        |> ignore
      }
    }
    _ => ()
  }
}

///|
/// 跳过, 保留两者, 替换.
fn clash_foot(c : @ui.Ctx) -> Unit {
  match clash_now() {
    (Some(a), Some(n)) => {
      if @sf.button(c, @sf.t("web-pages.files.skip"), key="files-clash/skip", tone=Ghost) {
        clash_answer(a, n, "skip")
      }
      if @sf.button(c, @sf.t("web-pages.drive.keepBoth"), key="files-clash/keep") {
        clash_answer(a, n, "keep")
      }
      if @sf.button(c, @sf.t("web-pages.drive.replace"), key="files-clash/replace", tone=Primary, icon="trash") {
        clash_answer(a, n, "replace")
      }
    }
    _ => ()
  }
}

///|
/// What is carried, under the pointer (the drag's picture): its mark and its name on a raised chip, and what a drop
/// where it is would do.
fn drag_ghost(c : @ui.Ctx, page : Int) -> Unit {
  let t = @sf.theme()
  match (fdrag.item.get(), c.rect_of(page)) {
    (Some(i), Some((x0, y0, _, _))) => {
      let (px, py, _) = c.pointer()
      c.layer(fn() {
        c.box(style=fdrag_ghost_place, tx=px - x0 + fdrag_ghost_off, ty=py - y0 + fdrag_ghost_off, fn() {
          c.box(style=fdrag_ghost_chip, fn() {
            @sf.icon(c, dv_kind_icon(if i.dir { "folder" } else { dv_kind_of(i.name) }), size=drag_icon, color=t.p.muted)
            |> ignore
            c.text(i.name, style=drag_chip_words) |> ignore
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
  match @sf.extension_of(name) {
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
/// A folder of the sidebar that takes a drop (FilesNav.tsx FolderDrop): its row, ringed while what it takes is over it,
/// saying what a drop does; its corner the row's (the theme's chats' list's `side_drop`: a row's, as the row it rings,
/// flush in it, is round).
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
  let drop = @sf.theme().chat_list.side_drop
  let look = if lit is Some(_) { drop.then(fdrag_side_on) } else { drop }
  c.box(style=look, id~, fn() {
    row()
    match lit {
      Some(l) =>
        c.layer(fn() {
          c.box(style=fdrag_says_place, fn() {
            c.box(style=fdrag_says, fn() {
              c.text(@sf.t(if l == "copy" { "web-pages.files.copyHereShort" } else { "web-pages.files.moveHereShort" }), style=fdrag_says_words)
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
/// The drag's picture this far from the pointer (down and right of it).
let fdrag_ghost_off : Double = 12.0

///|
/// What comes and what is there (clash: 10 by 12 in, the field's corner, the neutral ground).
// kept across runs: a value (no field of it changes)
let fclash_facts : @ui.Style = @ui.css("row w=Full px=S3 py=S2_5 gap=S3 radius=Xl bg=Neutral")

///|
// kept across runs: a value (no field of it changes)
let fclash_all : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let fdrag_ghost_place : @ui.Style = @ui.css("w=Full h=Full align=AStart")

///|
/// The picture carried: a chip on the raised ground, its shadow under it.
// kept across runs: a value (no field of it changes)
let fdrag_ghost_chip : @ui.Style = @ui.css(
  #|row h=S8 px=S3 gap=S2 align=ACenter radius=Lg bg=Raised shadow=Lg opacity=O90
)

///|
/// What a drop over it would land in: ringed in the accent on its wash.
// kept across runs: a value (no field of it changes)
let fdrag_side_on : @ui.Style = @ui.css("bg=AccentBg border=B1 border_color=Accent")

///|
// kept across runs: a value (no field of it changes)
let fdrag_says_place : @ui.Style = @ui.css("row w=Full h=Full pr=S2 align=ACenter justify=JEnd")

///|
/// What a drop there does (dropSays: a capsule in the accent, 7 in, its words 11 bold on it).
// kept across runs: a value (no field of it changes)
let fdrag_says : @ui.Style = @ui.css("px=S1_5 py=SPx radius=Full bg=Accent")

///|
// kept across runs: a value (no field of it changes)
let fdrag_says_words : @ui.TextStyle = @ui.text_style(size=Caption, weight=Semibold, color=OnPrimary, wrap=false)

///|
/// 个人收藏 while a folder dragged over it would be kept there (keep: ringed in the accent).
// kept across runs: a value (no field of it changes)
let fdrag_keep : @ui.Style = @ui.css("w=Full radius=Xl")

///|
// kept across runs: a value (no field of it changes)
let fdrag_keep_on : @ui.Style = fdrag_keep.then(@ui.css("border=B1 border_color=Accent"))


///|
/// What is carried now (a row dragged), for what it goes over to show it (a chat's composer).
pub fn dragged() -> Dragged? {
  fdrag.item.get()
}

///|
/// A name already where files go asked about, as a drop does (a page shown at that moment: the fixture's).
pub fn drag_ask(a : Asking) -> Unit {
  fdrag.asking.set(Some(a))
}
///|
/// The clash's facts (DrivePane.css.ts facts: two columns, 4 by 12 between; what is said muted).
// kept across runs: a value (no field of it changes)
let fclash_said_column : @ui.Style = @ui.css("gap=S1")

///|
// kept across runs: a value (no field of it changes)
let fclash_values_column : @ui.Style = @ui.style(w=@sf.grow, gap=S1, clip=true)

///|
// kept across runs: a value (no field of it changes)
let fclash_said : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let fclash_value : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)


///|
/// What is carried's mark (16).
let drag_icon : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let drag_chip_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
/// What the clash dialog says under its facts (a note, muted).
// kept across runs: a value (no field of it changes)
let clash_note : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)
