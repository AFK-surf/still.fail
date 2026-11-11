// What is dragged on the files' page (still.fail web/src/drive/drag.ts, browse.ts takes / effectOf / dropInto, transfer.ts,
// FilesNav.tsx useFolderDrop): a row pressed and moved past a few points carries its file or folder under the pointer;
// let go on a folder (a folder's row, a column, the folder shown, a folder of the sidebar) it goes there: within its
// station moved (⌥: copied), to another station copied (⌘: moved), as Finder does across disks; a folder let go on 个人
// 收藏 is kept there. A move within a station by a root both places are under (the core's `drive.moves`) is a rename
// there (a copy kept beside one of the same name named by `drive.name`), anything else the core's `drive.transfer`
// (the stations copy between them; the bar's 传输 follows it); a name already there is asked about first (替换, 保留两者,
// 跳过). Files from the computer (Finder) let go on a folder go up into it, a folder of them made there and filled.

///|
/// Where something dragged can be let go: its id (the box it is drawn as), its key, the folder it is (None: 个人收藏),
/// its name, whether its station takes files written there and copies from others, and how deep it lies (a folder's
/// row over the folder shown it is in); what it was built with (the core it asks, the workspace whose 个人收藏 it is).
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
  src : Source
  ws : String
}

///|
/// A name already where files go, asked about: what comes (its size, its station's name) and what
/// is there.
pub(all) struct Clash {
  name : String
  dir : Bool
  size : Double
  station : String
  there : DvEntry
}

///|
/// What is asked now: where they go, its name, how many go, the names there, the answers so far,
/// whether the next is said for all the rest, and what is done with the answers.
pub(all) struct Asking {
  into : DriveAt
  into_name : String
  total : Int
  clashes : Array[Clash]
  answers : Map[String, String]
  mut all : Bool
  done : (Map[String, String]) -> Unit
}

///|
/// The drag: a row pressed (what it would carry, where the press went down, whether it is a chat's 文件 tab's), what is
/// carried once the press moved past the slop and whether it came off the tab, the places it can be let go (by the id
/// of the box each is drawn as), the one what is held is over, what is asked, and what waits on something read.
/// Changed only as the hand, the host or the core says (a press's steps: fdrag_follow; files from outside held or let
/// go: fdrag_files; a folder or a pick read: fdrag_when), never as a frame is built.
priv struct FDrag {
  mut press : (Dragged, Double, Double, Bool)?
  /// (told as it changes: what shows it carried, built before what takes it in the frame, built again for it)
  item : @signals.Signal[Dragged?]
  mut off_tab : Bool
  /// (said where each is built, kept with what keeps it unbuilt, let go with its page: what a drop is let go on is
  /// what of these is drawn where it is let go)
  targets : Map[Int, FTarget]
  /// the key of the target what is held is over ("" none): told as it changes, what reads it built again
  over : @signals.Signal[String]
  mut asking : Asking?
  /// what waits on a folder to be read (a drop into it: what is there by their names asked about first) or a pick's
  /// files (dropped from outside): each stopped once done, or with the drag (drag_reset)
  later : Array[(Ref[Bool], () -> Unit)]
}

///|
// kept across runs: the drag's state (drag_reset puts it back)
let fdrag : FDrag = {
  press: None,
  item: @signals.signal(None),
  off_tab: false,
  targets: {},
  over: @signals.signal(""),
  asking: None,
  later: [],
}

///|
fn drag_reset() -> Unit {
  fdrag.press = None
  fdrag.item.set(None)
  fdrag.off_tab = false
  fdrag.targets.clear()
  fdrag.over.set("")
  fdrag.asking = None
  for w in fdrag.later {
    (w.1)()
  }
  fdrag.later.clear()
  fclash_shown.val = 0
  clash_changed()
}

///|
/// How far a press moves before it is a drag (a click's slop).
let fdrag_slop : Double = 4.0

///|
/// Row `id`, which would carry `item` (`tab`: a chat's 文件 tab's), followed as it is pressed (Ctx::follow_press):
/// pressed, moved past the slop it carries it, let go it drops it where it is let go. Not while `live` is not (the row
/// busy, its name being changed).
fn fdrag_source(c : @ui.Ctx, id : Int, item : Dragged, tab : Bool, live : Bool) -> Unit {
  c.follow_press(id, fn(step) {
    if live {
      fdrag_follow(c, item, tab, step)
    }
  })
}

///|
/// A step of a press on a row that would carry `item` (fdrag_source), as the hand takes it.
fn fdrag_follow(c : @ui.Ctx, item : Dragged, tab : Bool, step : @ui.PressStep) -> Unit {
  match step {
    // (a mouse's: a finger moving on a row moves the list, as the web's rows, which a touch drags nothing of; a file is
    // moved there by its menu)
    Down(x, y, _) =>
      if @sf.pointer_rests() && fdrag.item.get() is None {
        fdrag.press = Some((item, x, y, tab))
      }
    Moving(x, y) => {
      match (fdrag.press, fdrag.item.get()) {
        (Some((i, x0, y0, t)), None) if (x - x0).abs() > fdrag_slop || (y - y0).abs() > fdrag_slop => {
          fdrag.press = None
          fdrag.off_tab = t
          // (another carried: what was let go before and not taken is not for it)
          ftab.let_go = None
          fdrag.item.set(Some(i))
        }
        _ => ()
      }
      if fdrag.item.get() is Some(_) {
        fdrag_over(c, x, y)
      }
    }
    Up(x, y) => {
      fdrag.press = None
      match fdrag.item.get() {
        Some(i) => {
          match fdrag_at(c, x, y) {
            Some(t) => fdrag_drop(c, i, t, @ui.mods_held())
            None => ()
          }
          // a row let go off the tab, where: for the chat's composer to take (tab_take_drop)
          if fdrag.off_tab {
            ftab.let_go = Some((i, x, y))
          }
          fdrag.off_tab = false
          fdrag.over.set("")
          fdrag.item.set(None)
        }
        None => ()
      }
    }
    Off => {
      fdrag.press = None
      fdrag.off_tab = false
      fdrag.over.set("")
      fdrag.item.set(None)
    }
  }
}

///|
/// What is held is over (x, y) now: the target there that takes it, lit.
fn fdrag_over(c : @ui.Ctx, x : Double, y : Double) -> Unit {
  fdrag.over.set(
    match fdrag_at(c, x, y) {
      Some(t) => t.key
      None => ""
    },
  )
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
/// The target under (x, y), of those drawn where the hand is now, that takes what is held: the deepest, the smaller of
/// two as deep (what is drawn in the other).
fn fdrag_at(c : @ui.Ctx, x : Double, y : Double) -> FTarget? {
  let mut best : (FTarget, Double)? = None
  for _, t in fdrag.targets {
    if !fdrag_takes(t) {
      continue
    }
    match c.rect_of(t.id) {
      Some((rx, ry, rw, rh)) if x >= rx && x < rx + rw && y >= ry && y < ry + rh =>
        match best {
          Some((b, _)) if b.depth > t.depth => ()
          Some((b, area)) if b.depth == t.depth && area <= rw * rh => ()
          _ => best = Some((t, rw * rh))
        }
      _ => ()
    }
  }
  best.map(fn(b) { b.0 })
}

///|
/// `key` a place something can be let go (`id` the box it is drawn as; `src` the core it asks, `ws` the workspace
/// whose 个人收藏 it is, where it is that): what a drop there would do, while what is held is over it ("move", "copy",
/// "upload", "keep"), else None. Said where it is built: kept with what keeps it unbuilt, let go with its page.
fn fdrag_target(
  c : @ui.Ctx,
  src : Source,
  id : Int,
  key : String,
  into : DriveAt?,
  name : String,
  write : Bool,
  transfers : Bool,
  depth : Int,
  outside? : Bool = true,
  ws? : String,
) -> String? {
  let ws = match (ws, into) {
    (Some(w), _) => w
    (None, Some(at)) => @sfbase.workspace_of(at.station)
    (None, None) => ""
  }
  fdrag.targets[id] = { id, key, into, name, write, transfers, depth, outside, src, ws }
  c.on_page_release("files/drop-target/" + key, fn() { fdrag.targets.remove(id) })
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
/// Box `page` takes files from the computer let go on a folder drawn in it (Finder's, Explorer's: Ctx::on_files): held
/// over one, it says where they go; let go there, read as a pick's, then up into it. Let go elsewhere they are not
/// taken here (what is there may take them otherwise: a field, by their paths).
fn fdrag_files(c : @ui.Ctx, page : Int) -> Unit {
  c.on_files(
    page,
    held=fn(at) {
      if fdrag.item.get() is None {
        match at {
          Some((x, y)) => fdrag_over(c, x, y)
          None => fdrag.over.set("")
        }
      }
    },
    take=fn(x, y) {
      match fdrag_at(c, x, y) {
        Some({ into: Some(into), src, .. }) =>
          Some(fn(pick : @ui.Pick) {
            // (up once their reading is done: its answer)
            let files : Ref[Array[@hostapi.Picked]?] = Ref(None)
            fdrag_when(
              fn() {
                if files.val is None {
                  files.val = pick.files()
                }
                files.val is Some(_)
              },
              fn() { fdrag_put_up(src, into, files.val.unwrap_or([])) },
            )
          })
        _ => None
      }
    },
  )
}

///|
/// `go` done once `ready` says so: now, or as what it read changes (a folder's listing come from the core, a pick's
/// files read by the host), outside any build. What waits is let go with the drag (drag_reset).
fn fdrag_when(ready : () -> Bool, go : () -> Unit) -> Unit {
  // (those done before: let go of what they read)
  let gone = fdrag.later.filter(fn(w) { w.0.val })
  for w in gone {
    (w.1)()
  }
  fdrag.later.retain(fn(w) { !w.0.val })
  let done = Ref(false)
  // (owned by nothing: what waits is no part of what reads now, let go only by `stop`. Made so as it is made where
  // nothing reads and no owner is set: a drop from outside is handed on as the frame begins, outside its reading (ui's
  // take_messages), a row let go in the press's handler. One made as a frame is read would be that frame's, and is a
  // fault: @signals.effect_in_watch)
  let stop = @signals.effect(fn() {
    if !done.val && ready() {
      done.val = true
      @signals.untracked(go)
    }
  })
  if done.val {
    stop()
  } else {
    fdrag.later.push((done, stop))
  }
}

///|
/// Files from the computer into `into` (browse.ts dropInto, putFolder): each folder made there first (one there already
/// filled, as Finder merges), then each file up into its folder.
fn fdrag_put_up(src : Source, into : DriveAt, files : Array[@hostapi.Picked]) -> Unit {
  let root = into.root.unwrap_or("")
  let folders = files.filter(fn(f) { f.name.has_suffix("/") }).map(fn(f) { f.name.exact_view(end=f.name.length() - 1).to_owned() })
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
fn fdrag_drop(c : @ui.Ctx, item : Dragged, t : FTarget, mods : Int) -> Unit {
  let src = t.src
  match t.into {
    None => {
      favorite_add(src, t.ws, { station: item.station, root: item.abs, path: "", name: item.name })
    }
    Some(into) => {
      let moves = fdrag_effect(item, into.station, mods) == "move"
      let anywhere = match dv_stations(src, t.ws).0 {
        Some(l) =>
          match l.iter().find_first(fn(s) { s.station == into.station }) {
            Some(s) => s.anywhere
            None => false
          }
        None => false
      }
      fdrag_transfer(c, src, item, into, moves, t.name, anywhere)
    }
  }
}

///|
/// `item` into the folder `into`: not into itself, nor where it is already; a name there asked
/// about first, once the folder is read (now, or as it is: fdrag_when). Moved within its station by a root both places
/// are under (the core's `drive.moves`), it is a rename there (the one there to the trash first, or this one beside it
/// named as Finder names a copy kept: `drive.name`); anything else the stations' transfer (`drive.transfer`).
fn fdrag_transfer(
  c : @ui.Ctx,
  src : Source,
  item : Dragged,
  into : DriveAt,
  moves : Bool,
  into_name : String,
  anywhere : Bool,
) -> Unit {
  let into_root = into.root.unwrap_or("")
  if item.station == into.station &&
    item.root == into_root &&
    (dv_parent(item.path) == into.path || into.path == item.path || into.path.has_prefix(item.path + "/")) {
    return
  }
  fdrag_when(fn() { !(drive_folder(src, into.station, into_root, into.path) is (None, None)) }, fn() {
    fdrag_send(c, src, item, into, moves, into_name, anywhere)
  })
}

///|
/// `item` into the folder `into`, read (fdrag_transfer): a name there asked about first.
fn fdrag_send(
  c : @ui.Ctx,
  src : Source,
  item : Dragged,
  into : DriveAt,
  moves : Bool,
  into_name : String,
  anywhere : Bool,
) -> Unit {
  let into_root = into.root.unwrap_or("")
  let entries = match drive_folder(src, into.station, into_root, into.path) {
    (Some(_), _) => @sfbase.dv_entries(src, into.station, into_root, into.path).unwrap_or([])
    // (one that cannot be read: no names there to ask about)
    _ => []
  }
  let what = @sf.t(if moves { "web-pages.drive.moveWhat" } else { "web-pages.files.copyWhat" })
  let into_json : Json = { "station": Json::string(into.station), "root": Json::string(into_root), "path": Json::string(into.path) }
  // the stations' copy (or move), the answer about a name there said
  let transfer = fn(answer : String?) {
    let conflicts : Map[String, Json] = Map([])
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
        "move": Json::boolean(moves),
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
    if moves && item.station == into.station {
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
    Some(e) => {
      fdrag.asking = Some({
        into,
        into_name,
        total: 1,
        clashes: [{ name: item.name, dir: item.dir, size: item.size, station: item.station_name, there: e }],
        answers: {},
        all: false,
        done: go,
      })
      clash_changed()
    }
    None => go({})
  }
}

///|
/// What is asked about a name already where files go: each name in turn (or all the rest
/// the same way): 跳过, 保留两者, 替换; let go, nothing goes. The library's dialog (@sf.panel, opened by nothing), up
/// while something is asked: its title and what it is about as the name asked about now says them.
fn clash_dialog(c : @ui.Ctx) -> Unit {
  ignore(c)
  // (read as told: what builds it, a part kept as its nodes too, built again as something is asked or all answered)
  clash_told.get() |> ignore
  match fdrag.asking {
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
          fdrag.asking = None
          fclash_shown.val = 0
          clash_changed()
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
/// What is asked, as it was last told (fdrag.asking set or let go, a name answered, all the rest chosen the same way):
/// the asking itself, how many names it has answered, whether all the rest go one way. What reads it (clash_now: the
/// dialog's title and what it says, what it holds, its foot) follows it, as that changes.
// kept across runs: said again as it changes (drag_reset among them)
let clash_told : @signals.Signal[(Asking?, Int, Bool)] = @signals.signal((None, 0, false), same=fn(a, b) {
  let same_asking = match (a.0, b.0) {
    (Some(x), Some(y)) => physical_equal(x, y)
    (None, None) => true
    _ => false
  }
  same_asking && a.1 == b.1 && a.2 == b.2
})

///|
/// What is asked changed: told (clash_told).
fn clash_changed() -> Unit {
  clash_told.set(
    match fdrag.asking {
      Some(a) => (Some(a), a.answers.length(), a.all)
      None => (None, 0, false)
    },
  )
}

///|
/// The asking's dialog as presented (@sf.last_presented; 0 none).
// kept across runs: put back by drag_reset
let fclash_shown : Ref[Int] = Ref(0)

///|
/// What is asked now, and the name asked about (the first not answered).
fn clash_now() -> (Asking?, Clash?) {
  clash_told.get() |> ignore
  match fdrag.asking {
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
  if a.all {
    for x in left {
      a.answers[x.name] = said
    }
  } else {
    a.answers[n.name] = said
  }
  clash_changed()
  if a.clashes.iter().all(fn(x) { a.answers.contains(x.name) }) {
    fdrag.asking = None
    clash_changed()
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
        c.on_press(id, fn() {
          a.all = !a.all
          clash_changed()
        })
        c.box(style=fclash_all, id~, fn() {
          @sf.icon(c, if a.all { "check-circle" } else { "square" }, size=drag_icon, color=if a.all { t.p.accent } else { t.p.muted })
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
      @sf.button(c, @sf.t("web-pages.files.skip"), key="files-clash/skip", tone=Ghost, on_press=fn() {
        clash_answer(a, n, "skip")
      }) |> ignore
      @sf.button(c, @sf.t("web-pages.drive.keepBoth"), key="files-clash/keep", on_press=fn() {
        clash_answer(a, n, "keep")
      }) |> ignore
      @sf.button(c, @sf.t("web-pages.drive.replace"), key="files-clash/replace", tone=Primary, icon="trash", on_press=fn() {
        clash_answer(a, n, "replace")
      }) |> ignore
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
/// A folder of the sidebar that takes a drop: its row, ringed while what it takes is over it,
/// saying what a drop does; its corner the row's (the theme's chats' list's `side_drop`: a row's, as the row it rings,
/// flush in it, is round).
fn fdrag_side_row(
  c : @ui.Ctx,
  src : Source,
  key : String,
  into : DriveAt,
  name : String,
  write : Bool,
  transfers : Bool,
  row : () -> Unit,
) -> Unit {
  let id = c.id("files/drop/" + key)
  let lit = fdrag_target(c, src, id, "side/" + key, Some(into), name, write, transfers, 1, outside=false)
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
let fdrag_ghost_chip : @ui.Style = @ui.css((
  #|row h=S8 px=S3 gap=S2 align=ACenter radius=Lg bg=Raised shadow=Lg opacity=O90
))

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
/// What is carried now (a row dragged), for what it goes over to show it (a chat's composer).
pub fn dragged() -> Dragged? {
  fdrag.item.get()
}

///|
/// A name already where files go asked about, as a drop does (a page shown at that moment: the fixture's).
pub fn drag_ask(a : Asking) -> Unit {
  fdrag.asking = Some(a)
  clash_changed()
}
///|
/// The clash's facts (4 by 12 between; what is said muted).
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
