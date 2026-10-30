// How a station's files are worked with on a wide screen, as a local file browser does (ember web/src/drive/browse.ts
// useBrowse): a press chooses (⌘ adds or takes one away, ⇧ the ones between), a double click opens, the keys move and
// act on what is chosen; names are changed where they are. The files' page and a chat's 文件 tab go through it, each
// saying what may be done there. What is chosen, the order, a tree's folders open, the columns' widths and where a
// press or a key goes are the core's (its `driveBrowse` topic and `drive.browse`, client/core-ts/src/views/browse.ts):
// here they are drawn, and what the core answers is done (another folder shown, an entry opened, a name changed in
// place, a row brought into view).

///|
/// What a place does with what the core answers, as its page says (BrowseOptions): an entry opened by its kind (a
/// folder gone into, a file read, played, previewed or saved), another folder shown under the root (by its path;
/// `replace`: as the keys go, not a step back each), what is chosen previewed (space), the chosen asked to be deleted.
pub(all) struct BrowseDoes {
  open : (DriveAt, DvEntry) -> Unit
  go : (String, Bool) -> Unit
  preview : (DriveAt, DvEntry) -> Unit
  remove : (Array[(DriveAt, DvEntry)]) -> Unit
}

///|
/// A place as it is held here: its own name to the core (what is chosen is each place's: two sides of the files' page
/// are two), where it last told the core it is, what the core last said of it (kept while another folder is read, as
/// columns keep the choice that opened it), the row whose name is being changed (`folder\nname`) and its field, the row
/// to bring into view.
priv struct BrowsePlace {
  name : String
  told : @signals.Signal[String]
  last : @signals.Signal[BrowseView?]
  renaming : @signals.Signal[String?]
  field : @signals.Signal[@ui.Field]
  show : @signals.Signal[String?]
}

///|
/// The places by the page's key for each (the files' page's sides, a chat's tab), named p1, p2… as they come (the
/// same steps give the same names).
let browse_places : Map[String, BrowsePlace] = {}

///|
fn browse_reset() -> Unit {
  browse_places.clear()
}

///|
/// A place's folder, at a moment: by its page's key, the folder it shows and how, what may be done there.
pub(all) struct Browse {
  key : String
  owner : String
  view : String
  at : DriveAt
  root : String
  write : Bool
  does : BrowseDoes
  /// what the core says of it now (or last, while it is read)
  shown : BrowseView?
}

///|
/// A row's key among those shown: its folder's path under the root, and its name.
pub fn row_key(folder : String, name : String) -> String {
  folder + "\n" + name
}

///|
fn browse_place(key : String) -> BrowsePlace {
  match browse_places.get(key) {
    Some(p) => p
    None => {
      let p : BrowsePlace = {
        name: "p\{browse_places.length() + 1}",
        told: @signals.signal("", same=fn(a, b) { a == b }),
        last: @signals.signal(None),
        renaming: @signals.signal(None, same=fn(a, b) { a == b }),
        field: @signals.signal(@ui.Field::new()),
        show: @signals.signal(None, same=fn(a, b) { a == b }),
      }
      browse_places[key] = p
      p
    }
  }
}

///|
/// The core's name for the place `key` (a fixture's mode tells it what is chosen there before the first frame).
pub fn place_name(key : String) -> String {
  browse_place(key).name
}

///|
fn Browse::where_(self : Browse) -> Map[String, Json] {
  browse_where(
    self.owner,
    browse_place(self.key).name,
    self.view,
    self.at.station,
    self.root,
    self.at.path,
    write=self.write,
  )
}

///|
/// The place `key` (its owner, `page` or `tab`) showing `at` as `view`: what the core says of it, the core told where
/// it is as that changes (what is chosen there is then as coming to it chooses, or as columns carry it).
pub fn browse(
  c : @ui.Ctx,
  src : Source,
  key : String,
  owner : String,
  view : String,
  at : DriveAt,
  write : Bool,
  does : BrowseDoes,
) -> Browse {
  let p = browse_place(key)
  let root = at.root.unwrap_or("")
  let b0 : Browse = { key, owner, view, at, root, write, does, shown: None }
  let got = browse_topic(src, b0.where_())
  match got {
    Some(v) => p.last.set(Some(v))
    None => ()
  }
  let b = { ..b0, shown: match got { Some(v) => Some(v); None => p.last.get() } }
  let here = view + "\n" + at.station + "\n" + root + "\n" + at.path
  if p.told.get() != here {
    // (a name being changed lets go as another folder is shown)
    if p.told.get() != "" {
      p.renaming.set(None)
    }
    c.after_build("browse-at/" + key, fn() {
      if p.told.get() != here {
        p.told.set(here)
        browse_send(c, src, b, { "act": "at" })
      }
    })
  }
  b
}

///|
/// What is chosen in the place now.
pub fn Browse::chosen(self : Browse) -> Chosen {
  match self.shown {
    Some(v) => v.chosen
    None => chosen_none()
  }
}

///|
/// How the device orders a folder's entries (by name where the core has not said).
pub fn Browse::arrangement(self : Browse) -> Arrangement {
  match self.shown {
    Some(v) => v.arrangement
    None => arrangement_none()
  }
}

///|
/// The folder `folder`'s entries in the order shown, as the core says them; None while it has not.
pub fn Browse::arranged(self : Browse, folder : String, entries : Array[DvEntry]) -> Array[DvEntry]? {
  match self.shown {
    Some(v) => dv_in_order(v.folders.get(folder), entries)
    None => None
  }
}

///|
/// Whether a tree's folder is open.
pub fn Browse::is_open(self : Browse, path : String) -> Bool {
  match self.shown {
    Some(v) => v.open.contains(path)
    None => false
  }
}

///|
/// A column's width dragged (None: as every column is).
pub fn Browse::width_of(self : Browse, path : String) -> Double? {
  match self.shown {
    Some(v) => v.widths.get(path)
    None => None
  }
}

///|
pub fn Browse::is_chosen(self : Browse, folder : String, name : String) -> Bool {
  let ch = self.chosen()
  ch.folder == folder && ch.names.contains(name)
}

///|
/// The row whose name is being changed (`folder\nname`).
pub fn Browse::renaming(self : Browse) -> String? {
  browse_place(self.key).renaming.get()
}

///|
/// A folder's entries as its station said them (held), by its path under the root.
fn Browse::held(self : Browse, src : Source, folder : String) -> Array[DvEntry] {
  @sfbase.dv_entries(src, self.at.station, self.root, folder).unwrap_or([])
}

///|
fn Browse::entry_of(self : Browse, src : Source, folder : String, name : String) -> DvEntry? {
  self.held(src, folder).iter().find_first(fn(e) { e.name == name })
}

///|
fn Browse::at_of(self : Browse, folder : String) -> DriveAt {
  { station: self.at.station, root: Some(self.root), path: folder }
}

///|
/// What the core answers done (Done): another folder shown, an entry opened, previewed, renamed or deleted, a row in
/// view.
fn browse_after(src : Source, b : Browse, done : Json) -> Unit {
  let d = Some(done)
  let p = browse_place(b.key)
  match field(d, "go") {
    Some(Object(_)) as g => (b.does.go)(text(g, "path"), flag(g, "replace"))
    _ => ()
  }
  let entry = fn(s : Json?) -> Array[(DriveAt, DvEntry)] {
    match b.entry_of(src, text(s, "folder"), text(s, "name")) {
      Some(e) => [(b.at_of(text(s, "folder")), e)]
      None => []
    }
  }
  match field(d, "open") {
    Some(Object(_)) as s => for x in entry(s) { (b.does.open)(x.0, x.1) }
    _ => ()
  }
  match field(d, "preview") {
    Some(Object(_)) as s => for x in entry(s) { (b.does.preview)(x.0, x.1) }
    _ => ()
  }
  match field(d, "rename") {
    Some(Object(_)) as s => browse_rename_start(b, text(s, "folder"), text(s, "name"), flag(s, "dir"))
    _ => ()
  }
  match field(d, "remove") {
    Some(Array(list)) => {
      let all : Array[(DriveAt, DvEntry)] = []
      for s in list {
        all.push_iter(entry(Some(s)).iter())
      }
      (b.does.remove)(all)
    }
    _ => ()
  }
  match field(d, "show") {
    Some(Object(_)) as s => p.show.set(Some(row_key(text(s, "folder"), text(s, "name"))))
    _ => ()
  }
}

///|
/// `drive.browse` asked of the place (its where, and `params`), what it answers done.
fn browse_send(c : @ui.Ctx, src : Source, b : Browse, params : Map[String, Json]) -> Unit {
  ignore(c)
  let o = b.where_()
  for k, v in params {
    o[k] = v
  }
  (src.call)("drive.browse", Json::object(o), fn(r) {
    match r {
      Ok(Object(_) as done) => browse_after(src, b, done)
      _ => ()
    }
  })
}

///|
/// A press on a row (a click: ⌘ and ⇧ as Finder has them).
pub fn Browse::press(self : Browse, c : @ui.Ctx, src : Source, folder : String, name : String) -> Unit {
  let held = @ui.mods_held()
  let b = self
  c.tell("browse-press/" + self.key, fn() {
    browse_send(c, src, b, {
      "act": "press",
      "folder": Json::string(folder),
      "name": Json::string(name),
      "mod": Json::boolean((held & (@ui.mod_cmd | @ui.mod_ctrl)) != 0),
      "shift": Json::boolean((held & @ui.mod_shift_key) != 0),
    })
  })
}

///|
/// Chosen and nothing else, unless it is among what is (a right click on a row).
pub fn Browse::choose(self : Browse, c : @ui.Ctx, src : Source, folder : String, name : String) -> Unit {
  let b = self
  c.tell("browse-menu/" + self.key, fn() {
    browse_send(c, src, b, { "act": "menu", "folder": Json::string(folder), "name": Json::string(name) })
  })
}

///|
/// What is chosen, if `entry` is among it; else `entry` alone (what a menu or a drag of that row is about).
pub fn Browse::chosen_with(self : Browse, src : Source, folder : String, e : DvEntry) -> Array[(DriveAt, DvEntry)] {
  let ch = self.chosen()
  if ch.folder == folder && ch.names.contains(e.name) && ch.names.length() > 1 {
    let out : Array[(DriveAt, DvEntry)] = []
    for n in ch.names {
      match self.entry_of(src, folder, n) {
        Some(x) => out.push((self.at_of(folder), x))
        None => ()
      }
    }
    return out
  }
  [(self.at_of(folder), e)]
}

///|
/// Nothing chosen (a press where there is no row).
pub fn Browse::clear(self : Browse, c : @ui.Ctx, src : Source) -> Unit {
  if self.chosen().names.length() > 0 {
    let b = self
    c.tell("browse-clear/" + self.key, fn() { browse_send(c, src, b, { "act": "clear" }) })
  }
}

///|
/// A folder of the tree opened or closed (its disclosure).
pub fn Browse::toggle(self : Browse, c : @ui.Ctx, src : Source, path : String) -> Unit {
  let b = self
  c.tell("browse-tree/" + self.key + "/" + path, fn() {
    browse_send(c, src, b, { "act": "tree", "folder": Json::string(path) })
  })
}

///|
/// A column's width dragged, kept (`path` its folder's).
pub fn Browse::keep_width(self : Browse, c : @ui.Ctx, src : Source, path : String, px : Double) -> Unit {
  let b = { ..self, at: { ..self.at, path, } }
  c.tell("browse-width/" + self.key + "/" + path, fn() {
    browse_send(c, src, b, { "act": "width", "path": Json::string(path), "width": Json::number(px) })
  })
}

///|
/// Every column as wide as the rest again.
pub fn Browse::forget_widths(self : Browse, c : @ui.Ctx, src : Source) -> Unit {
  let b = self
  c.tell("browse-widths/" + self.key, fn() { browse_send(c, src, b, { "act": "widths" }) })
}

///|
/// The order and whether hidden files show, changed (`drive.arrange`).
pub fn Browse::arrange_as(self : Browse, c : @ui.Ctx, src : Source, by? : String, down? : Bool, hidden? : Bool) -> Unit {
  ignore(self)
  c.tell("browse-arrange", fn() { dv_arrange(src, by?, down?, hidden?) })
}

///|
/// (its field holding the name, picked but its extension: NameField's onFocus)
fn browse_rename_start(b : Browse, folder : String, name : String, dir : Bool) -> Unit {
  let p = browse_place(b.key)
  p.renaming.set(Some(row_key(folder, name)))
  p.field.set(@ui.Field::new())
  p.field.get().set(name)
  let dot = match name.rev_find(".") {
    Some(i) if i > 0 && !dir => i
    _ => name.length()
  }
  p.field.get().pick(0, dot)
}

///|
/// A row's name changed in place from here (its menu's 重命名): chosen, its field shown.
pub fn Browse::start_rename(self : Browse, c : @ui.Ctx, src : Source, folder : String, e : DvEntry) -> Unit {
  let b = self
  c.tell("browse-rename/" + self.key, fn() {
    browse_send(c, src, b, { "act": "choose", "folder": Json::string(folder), "name": Json::string(e.name) })
    browse_rename_start(b, folder, e.name, e.dir)
  })
}

///|
/// The field a name is changed in (the row's whose name it is).
pub fn Browse::rename_field(self : Browse) -> @ui.Field {
  browse_place(self.key).field.get()
}

///|
/// The name being changed done (None: left as it was): the station asked, chosen under its new name as soon as it
/// has it; what is wrong with the name said.
pub fn Browse::rename(self : Browse, c : @ui.Ctx, src : Source, folder : String, e : DvEntry, to : String?) -> Unit {
  let p = browse_place(self.key)
  p.renaming.set(None)
  let name = match to {
    Some(t) => t.trim(chars=" \t\n").to_string()
    None => return
  }
  if name == "" || name == e.name {
    return
  }
  let what = @sf.t("web-pages.drive.renameWhat")
  let b = self
  c.tell("browse-renamed/" + self.key, fn() {
    // (a name it may not have refused, in the core's words)
    dv_check_name(src, name, fn(problem) {
      match problem {
        Some(p) => say(c, @sf.t("web-main.act.failed", args=[("what", what), ("error", p)]))
        None =>
          (src.call)(
            "drive.rename",
            {
              "station": Json::string(b.at.station),
              "root": Json::string(b.root),
              "from": Json::string(dv_join(folder, e.name)),
              "to": Json::string(dv_join(folder, name)),
            },
            fn(r) {
              match r {
                Ok(_) => browse_send(c, src, b, { "act": "choose", "folder": Json::string(folder), "name": Json::string(name) })
                Err(err) => say(c, @sf.t("web-main.act.failed", args=[("what", what), ("error", dv_error(err))]))
              }
            },
          )
      }
    })
  })
}

///|
/// A new folder in `folder`, named as Finder does (`drive.name`: 未命名文件夹, 未命名文件夹 2…), its name then changed
/// in place.
pub fn Browse::new_folder(self : Browse, c : @ui.Ctx, src : Source, folder : String) -> Unit {
  let b = self
  let what = @sf.t("web-pages.drive.mkdirWhat")
  let failed = fn(err : Json) { say(c, @sf.t("web-main.act.failed", args=[("what", what), ("error", dv_error(err))])) }
  c.tell("browse-mkdir/" + self.key, fn() {
    (src.call)(
      "drive.name",
      {
        "name": Json::string(@sf.t("web-pages.drive.untitledFolder")),
        "station": Json::string(b.at.station),
        "root": Json::string(b.root),
        "path": Json::string(folder),
      },
      fn(r) {
        match r {
          Ok(v) => {
            let name = text(Some(v), "name")
            (src.call)(
              "drive.mkdir",
              { "station": Json::string(b.at.station), "root": Json::string(b.root), "path": Json::string(dv_join(folder, name)) },
              fn(r) {
                match r {
                  Ok(_) => {
                    browse_send(c, src, b, { "act": "choose", "folder": Json::string(folder), "name": Json::string(name) })
                    browse_rename_start(b, folder, name, true)
                    browse_place(b.key).show.set(Some(row_key(folder, name)))
                  }
                  Err(err) => failed(err)
                }
              },
            )
          }
          Err(err) => failed(err)
        }
      },
    )
  })
}

///|
/// The row to bring into view, taken (a list draws it so once).
pub fn Browse::take_show(self : Browse) -> String? {
  let p = browse_place(self.key)
  let s = p.show.get()
  p.show.set(None)
  s
}

///|
/// A key as the core names it (its `keys`): `mod+` before it with ⌘ or Ctrl held, a letter in small; ⌘⇧. its own.
fn key_name(code : Int, mods : Int) -> String? {
  let m = (mods & (@ui.mod_cmd | @ui.mod_ctrl)) != 0
  let shift = (mods & @ui.mod_shift_key) != 0
  if m && shift && (code == @ui.key_of_char('.') || code == @ui.key_of_char('>')) {
    return Some("mod+shift+Period")
  }
  let k = if code == @ui.key_code_down {
    "ArrowDown"
  } else if code == @ui.key_code_up {
    "ArrowUp"
  } else if code == @ui.key_code_home {
    "Home"
  } else if code == @ui.key_code_end {
    "End"
  } else if code == @ui.key_code_right {
    "ArrowRight"
  } else if code == @ui.key_code_left {
    "ArrowLeft"
  } else if code == @ui.key_code_enter {
    "Enter"
  } else if code == @ui.key_escape {
    "Escape"
  } else if code == @ui.key_code_backspace {
    "Backspace"
  } else if code == @ui.key_code_delete {
    "Delete"
  } else if code >= 1000 {
    let ch = (code - 1000).unsafe_to_char()
    let lower = if ch >= 'A' && ch <= 'Z' { (ch.to_int() + 32).unsafe_to_char() } else { ch }
    lower.to_string()
  } else {
    return None
  }
  Some(if m { "mod+" + k } else { k })
}

///|
/// The keys pressed since the last frame where the rows are (the page's, anywhere on it but a field): one that does
/// something here now is the rows' (the core says which), taken; a letter goes to a name starting with it.
pub fn Browse::keys(self : Browse, c : @ui.Ctx, src : Source) -> Unit {
  let acts = match self.shown {
    Some(v) => v.keys
    None => []
  }
  if browse_place(self.key).renaming.get() is Some(_) || c.field_focused() {
    return
  }
  let b = self
  for i, k in c.keys() {
    let (code, mods, taken) = k
    if taken {
      continue
    }
    match key_name(code, mods) {
      Some(name) if acts.contains(name) => {
        c.take_key(code, mods~) |> ignore
        let shift = (mods & @ui.mod_shift_key) != 0
        c.tell("browse-key/" + self.key + "/\{i}", fn() {
          browse_send(c, src, b, { "act": "key", "key": Json::string(name), "shift": Json::boolean(shift) })
        })
      }
      Some(name) if (mods & (@ui.mod_cmd | @ui.mod_ctrl | @ui.mod_alt)) == 0 && code >= 1000 && code != @ui.key_space => {
        let letter = (code - 1000).unsafe_to_char().to_string()
        ignore(name)
        c.tell("browse-type/" + self.key + "/\{i}", fn() {
          browse_send(c, src, b, { "act": "type", "letter": Json::string(letter) })
        })
      }
      _ => ()
    }
  }
}
