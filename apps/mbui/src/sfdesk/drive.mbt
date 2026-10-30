// A folder of a station's drive on a wide screen (ember web/src/pages/Drive.tsx FolderView, DriveRow, NameField,
// ListHead, UploadRow, Empty; Drive.css.ts): its entries in one of three ways (DriveViews: columns, a tree, a list),
// each row chosen by a press, opened by a double click (a folder gone into, a text read, a video played, a picture or
// code previewed, the rest downloaded), its name changed in place, its ⋯ (on hover) or a right click giving what can be
// done to it (what is chosen, when it is among it); a right click where there is no row: a new folder, files put up,
// the order, hidden files, read again. The keys are the rows' wherever on the page they are pressed but a field (the
// core says which act: browse.mbt). Deleted to the machine's trash, as Finder does, nothing asked; where none takes it,
// asked first, then for good. The preview beside it (⌘⇧P: drive_pane.mbt). What a folder's bar holds (its ways, put
// up, a new folder, read again, 收藏, pin, its ⋯) is `folder_actions`, put in the files' page's bar by it.

///|
/// What opens an entry, by its kind (drive/model.ts openerOf): a folder gone into, read, played, previewed, saved.
pub fn opener_of(kind : String) -> String {
  match kind {
    "folder" => "folder"
    "text" | "markdown" => "read"
    "video" | "audio" => "play"
    "image" | "pdf" | "code" | "csv" | "html" | "subtitle" => "preview"
    _ => "save"
  }
}

///|
/// A folder as its page gives it (FolderView's props, and what the files' page around it does): the place's key (its
/// side), the workspace, the station (with what the viewer may do there), the folder (its root said), whether it is the
/// side in front (where the keys go), the room its list has across; another folder of the station shown (`replace`:
/// as the keys go), a folder opened in a tab or beside (None: no files' page around it), 前往文件夹 (⌘⇧G).
pub(all) struct FolderOf {
  key : String
  ws : String
  st : DvStation
  rights : DvRights
  at : DriveAt
  front : Bool
  room : Double
  go : (DriveAt, Bool) -> Unit
  open_in : ((DriveAt, Bool) -> Unit)?
  go_to : (() -> Unit)?
  manage : (() -> Unit)?
}

///|
/// The name being changed in place and whether its field had the focus (it is done once it leaves); the row whose menu
/// is presented (its key, the presenter's serial: @sf.last_presented), marked while it is drawn.
priv struct DriveHeld {
  naming : @signals.Signal[String]
  mut naming_had : Bool
  refreshing : @sf.LiveMap[String, Bool]
  mut row_frame : Int
  mut menu_row : String
  mut menu_serial : Int
  menu_items : Array[@sf.MenuItem?]
}

///|
let held : DriveHeld = {
  naming: @signals.signal("", same=fn(a, b) { a == b }),
  naming_had: false,
  refreshing: @sf.LiveMap::new(),
  row_frame: -1,
  menu_row: "",
  menu_serial: 0,
  menu_items: [],
}

///|
fn drive_reset() -> Unit {
  held.naming.set("")
  held.naming_had = false
  held.refreshing.clear()
  held.row_frame = -1
  held.menu_row = ""
  held.menu_serial = 0
}

///|
/// `items` presented as row `key`'s menu (@sf.menu `from`), the row marked while it is drawn; what it offers kept as
/// the row's are each frame it is built (drive_row_menu_now: what is chosen, as the core says it, may come after it
/// opened, as the web's menu renders its items from what is chosen).
fn drive_row_menu(
  key : String,
  items : Array[@sf.MenuItem?],
  from : @sf.Beside,
  along? : @ui.Along = Start,
  title? : String = "",
) -> Unit {
  held.menu_items.clear()
  held.menu_items.push_iter(items.iter())
  @sf.menu(held.menu_items, from~, along~, title~)
  held.menu_row = key
  held.menu_serial = @sf.last_presented()
}

///|
/// Row `key`'s menu, while it is drawn, offering `items` as they are now.
fn drive_row_menu_now(key : String, items : Array[@sf.MenuItem?]) -> Unit {
  if drive_row_menu_drawn(key) {
    // (what it shows told where it changed: the presenters draw it from what it holds)
    let said = fn(a : Array[@sf.MenuItem?]) {
      a.map(fn(x) { x.map(fn(m) { (m.label, m.icon, m.danger, m.disabled, m.chosen, m.heading) }) })
    }
    if said(held.menu_items) != said(items) {
      @sf.presented_changed()
    }
    held.menu_items.clear()
    held.menu_items.push_iter(items.iter())
  }
}

///|
/// Whether row `key`'s menu is drawn (drive_row_menu).
fn drive_row_menu_drawn(key : String) -> Bool {
  held.menu_row == key && @sf.presented_drawn_of(held.menu_serial)
}

///|
/// Whether a row took this frame's press or right click (what holds the rows leaves it to them: a click on a row is
/// not one where there is no row).
pub fn row_took(c : @ui.Ctx) -> Bool {
  held.row_frame == c.frame_number()
}

///|
/// A station's name, as the workspace's stations list has it (its address while not known).
pub fn station_name(src : Source, station : String) -> String {
  let ws = match station.find("/") {
    Some(i) => station.view(end_offset=i).to_owned()
    None => station
  }
  match dv_stations(src, ws).0 {
    Some(list) =>
      match list.iter().find_first(fn(s) { s.station == station }) {
        Some(s) => s.name
        None => station
      }
    None => station
  }
}

///|
/// What a change set going said should it fail (useAct): 没能{what}：{error}; `done` once done, if said.
pub fn act_done(c : @ui.Ctx, what : String, done? : String = "") -> (Result[Json, Json]) -> Unit {
  fn(r) {
    match r {
      Ok(_) => if done != "" { say(c, done) }
      Err(e) => say(c, @sf.t("web-main.act.failed", args=[("what", what), ("error", dv_error(e))]))
    }
  }
}

///|
/// A path copied, said so.
pub fn copy_path(c : @ui.Ctx, abs : String) -> Unit {
  c.copy_text(abs)
  say(c, @sf.t("web-pages.drive.pathCopied"))
}

///|
/// The folder read again (drive.refresh), once at a time.
pub fn refresh_folder(c : @ui.Ctx, src : Source, at : DriveAt) -> Unit {
  let root = at.root.unwrap_or("")
  let key = at.station + "\n" + root + "\n" + at.path
  if held.refreshing.contains(key) {
    return
  }
  held.refreshing[key] = true
  c.tell("refresh/" + key, fn() {
    (src.call)(
      "drive.refresh",
      { "station": Json::string(at.station), "root": Json::string(root), "path": Json::string(at.path) },
      fn(r) {
        held.refreshing.remove(key)
        (act_done(c, @sf.t("web-pages.drive.refreshWhat")))(r)
      },
    )
  })
}

///|
/// Whether the folder is being read again.
pub fn refreshing(at : DriveAt) -> Bool {
  held.refreshing.contains(at.station + "\n" + at.root.unwrap_or("") + "\n" + at.path)
}

///|
/// A folder pinned for everyone or not (drive.setRoots: the station's folders lent, with it or without it).
pub fn pin_folder(c : @ui.Ctx, src : Source, st : DvStation, abs : String, on : Bool) -> Unit {
  let roots = st.roots.map(fn(r) { r.path }).filter(fn(p) { p != abs })
  if on {
    roots.push(abs)
  }
  let name = dv_name(abs.trim_end(chars="/\\").to_string())
  c.tell("pin/" + st.station + "/" + abs, fn() {
    (src.call)(
      "drive.setRoots",
      { "station": Json::string(st.station), "roots": Json::array(roots.map(fn(p) { Json::string(p) })) },
      act_done(
        c,
        @sf.t("web-pages.drive.rootsWhat"),
        done=@sf.t(if on { "web-pages.drive.shared" } else { "web-pages.drive.unpinned" }, args=[("name", name)]),
      ),
    )
  })
}

///|
/// A file of the drive downloaded (a folder zipped first).
pub fn save_entry(c : @ui.Ctx, src : Source, at : DriveAt, e : DvEntry) -> Unit {
  let root = at.root.unwrap_or("")
  let path = dv_join(at.path, e.name)
  c.tell("save/" + at.station + "/" + root + "/" + path, fn() {
    if e.dir {
      download_drive_zip(c, src, at.station, root, path)
    } else {
      say(c, @sf.t("android-misc.drive.downloading", args=[("name", e.name)]))
      download_drive_file(c, src, at.station, root, path, e.name, listed=Some((e.mtime, e.size)))
    }
  })
}

///|
/// A file of the drive handed to another app (分享): read through the core a part at a time, how far on its row
/// meanwhile (drive_fetch), then the system's share sheet; said when nothing takes it.
pub fn share_entry(c : @ui.Ctx, src : Source, at : DriveAt, e : DvEntry) -> Unit {
  let root = at.root.unwrap_or("")
  let all = Buffer(size_hint=if e.size > 0.0 { e.size.to_int() } else { 0 })
  c.tell("share/" + at.station + "/" + root + "/" + dv_join(at.path, e.name), fn() {
    drive_fetch(
      src,
      at.station,
      root,
      dv_join(at.path, e.name),
      fn(b) {
        all.write_bytes(b)
        true
      },
      fn(err) {
        match err {
          None =>
            if !@ui.share("", e.name, e.mime, all.to_bytes()) {
              say(c, @sf.t("android-misc.drive.noApp"))
            }
          Some(err) =>
            say(c, @sf.t("android-misc.drive.fetchFailed", args=[("name", e.name), ("error", dv_error(err))]))
        }
      },
      listed=Some((e.mtime, e.size)),
    )
  })
}

///|
/// An entry of the folder `in_` opened as its kind wants (FolderView openIn): a folder gone into, a text read, a video
/// played, a picture or code previewed (with the pictures beside it, `near`), the rest downloaded; kept as what was
/// last opened there.
pub fn open_entry(
  c : @ui.Ctx,
  src : Source,
  owner : String,
  in_ : DriveAt,
  e : DvEntry,
  near : Array[DvEntry],
  go : (DriveAt) -> Unit,
) -> Unit {
  let root = in_.root.unwrap_or("")
  let full = dv_join(in_.path, e.name)
  keep_opened(c, src, owner, in_, e.name)
  match opener_of(if e.dir { "folder" } else { e.kind }) {
    "folder" => go({ ..in_, path: full })
    "read" => open_page(DriveRead({ station: in_.station, root: Some(root), path: full }))
    "play" => open_page(DrivePlay({ station: in_.station, root: Some(root), path: full }))
    "preview" => {
      let pictures = if e.kind == "image" {
        near.filter(fn(x) { x.kind == "image" }).map(fn(x) { dv_file(in_.station, root, in_.path, x) })
      } else {
        []
      }
      open_drive_file(dv_file(in_.station, root, in_.path, e), pictures)
    }
    _ => save_entry(c, src, in_, e)
  }
}

///|
/// Deleted (FolderView remove): to the machine's trash, as Finder does, nothing asked (said once done); where none takes
/// them, asked first (the library's confirm), then for good.
pub fn remove_entries(c : @ui.Ctx, src : Source, st : DvStation, items : Array[(DriveAt, DvEntry)]) -> Unit {
  if items.is_empty() {
    return
  }
  if !st.trash {
    ask_remove(c, src, items)
    return
  }
  let what = @sf.t("web-pages.drive.deleteWhat")
  let left : Array[(DriveAt, DvEntry)] = []
  let answered = Ref(0)
  c.tell("remove/" + st.station, fn() {
    for x in items {
      let (at, e) = x
      (src.call)(
        "drive.remove",
        {
          "station": Json::string(at.station),
          "root": Json::string(at.root.unwrap_or("")),
          "path": Json::string(dv_join(at.path, e.name)),
        },
        fn(r) {
          answered.val += 1
          match r {
            Ok(_) => ()
            Err(err) if text(Some(err), "code") == "no_trash" => left.push(x)
            Err(err) => say(c, @sf.t("web-main.act.failed", args=[("what", what), ("error", dv_error(err))]))
          }
          if answered.val == items.length() {
            if left.length() > 0 {
              ask_remove(c, src, left)
            } else {
              say(c, @sf.t("web-pages.drive.trashed", args=[("n", items.length().to_string())]))
            }
          }
        },
      )
    }
  })
}

///|
/// What is asked before something goes for good (Confirm): the one, the folder, or how many; 删除 does it.
fn ask_remove(c : @ui.Ctx, src : Source, asking : Array[(DriveAt, DvEntry)]) -> Unit {
  let title = match asking {
    [(_, e)] =>
      @sf.t(if e.dir { "web-pages.drive.deleteFolderAsk" } else { "web-pages.drive.deleteAsk" }, args=[("name", e.name)])
    many => @sf.t("web-pages.drive.deleteManyAsk", args=[("n", many.length().to_string())])
  }
  let words = if asking.iter().any(fn(x) { x.1.dir }) {
    @sf.t("web-pages.drive.deleteFolderText")
  } else {
    @sf.t("web-pages.drive.deleteText")
  }
  let what = @sf.t("web-pages.drive.deleteWhat")
  @sf.confirm(title, words, @sf.t("web-pages.drive.delete"), fn() {
    for x in asking {
      let (at, e) = x
      (src.call)(
        "drive.remove",
        {
          "station": Json::string(at.station),
          "root": Json::string(at.root.unwrap_or("")),
          "path": Json::string(dv_join(at.path, e.name)),
          "permanent": Json::boolean(true),
        },
        act_done(c, what),
      )
    }
  }, danger=true)
}

///|
/// What the core says is under way on an entry (`doing`: removed, renamed).
fn entry_busy(src : Source, at : DriveAt, name : String) -> Bool {
  let root = at.root.unwrap_or("")
  let full = dv_join(at.path, name)
  for d in items((src.topic)("doing", {}).value, "doing") {
    let call = text(Some(d), "call")
    let p = field(Some(d), "params")
    if text(Some(d), "stage") == "failed" || text(p, "station") != at.station || text(p, "root") != root {
      continue
    }
    if (call == "drive.remove" && text(p, "path") == full) || (call == "drive.rename" && text(p, "from") == full) {
      return true
    }
  }
  false
}

///|
/// The folder's own (FolderView): a folder of a station in the way its room has it shown (views_for), `head` over its
/// rows (in their list, scrolled with them; over the columns, which scroll each their own), the files going up into
/// it, its preview beside it (⌘⇧P) where the room has it; `foot` the frame's room under the last row. What is dropped
/// where no folder of it takes it goes into it. Its keys while it is in front: the rows' (the core's), ⌘U puts files
/// up, ⌘⇧N a new folder, ⌘⇧P the preview.
fn folder_view(c : @ui.Ctx, src : Source, f : FolderOf, head~ : () -> Unit, foot~ : Double) -> Unit {
  let at = f.at
  let root = at.root.unwrap_or("")
  let st = f.st
  let write = f.rights.write
  let view = view_in(src, "page", list_room(src, f.room))
  let (value, error) = drive_folder(src, at.station, root, at.path)
  let entries = @sfbase.dv_entries(src, at.station, root, at.path).unwrap_or([])
  let sname = st.name
  if f.front {
    keep_files_page(f.ws, at)
  }
  // the files picked to go up
  dv_take_picked(src, at, entries)
  let b_ref : Ref[Browse?] = Ref(None)
  let open_row = fn(in_ : DriveAt, e : DvEntry) {
    let near = match b_ref.val {
      Some(b) if in_.path == at.path => b.arranged(in_.path, entries).unwrap_or([e])
      _ => [e]
    }
    open_entry(c, src, "page", in_, e, near, fn(to) { (f.go)(to, false) })
  }
  let b = browse(c, src, f.key, "page", view, at, write, {
    open: open_row,
    preview: open_row,
    go: fn(p, replace) { (f.go)({ ..at, path: p }, replace) },
    remove: fn(items) { remove_entries(c, src, st, items) },
  })
  b_ref.val = Some(b)
  let name = folder_name(st, at)
  // what goes into a folder dropped on it, where the viewer may write there
  let into = fn(folder : DriveAt) -> DriveAt? { if write { Some(folder) } else { None } }
  let favs = favorites(src, f.ws)
  let row_of = fn(in_ : DriveAt, e : DvEntry) -> RowProps {
    {
      items: fn() { row_items(c, src, f, b, in_, e, favs) },
      open: fn() { open_row(in_, e) },
      press: fn() { b.press(c, src, in_.path, e.name) },
      menu: fn() { b.choose(c, src, in_.path, e.name) },
      chosen: b.is_chosen(in_.path, e.name),
      renaming: b.renaming() == Some(row_key(in_.path, e.name)),
      rename: fn(to) { b.rename(c, src, in_.path, e, to) },
      drop: if e.dir { into({ ..in_, path: dv_join(in_.path, e.name) }) } else { None },
    }
  }
  let shown : Shown = {
    b,
    row_of,
    drop_on: into,
    clear: fn() { b.clear(c, src) },
    write,
    transfers: st.transfers,
  }
  // (the preview beside the list where its room has both)
  let previewing = preview_shown(src, "page") && pane_fits(f.room)
  if f.front && !c.field_focused() {
    b.keys(c, src)
    if write && c.shortcut('u') {
      dv_upload(c, at)
    }
    if write && c.shortcut('n', shift=true) {
      b.new_folder(c, src, at.path)
    }
    // (the keymap's files.preview: ⌘⇧P, as Finder's preview pane, or as changed)
    if @settings.action_pressed(c, (src.topic)("prefs", {}).value, "files.preview") {
      set_preview_shown(src, "page", !previewing)
    }
  }
  let ups_here = ups.uploads.filter(fn(u) { u.station == at.station && u.root == root && u.dir == at.path })
  let empty = fn() {
    folder_empty(c, @sf.t("web-pages.drive.emptyFolder"), if write { Some(fn() { dv_upload(c, at) }) } else { None })
  }
  // a right click where there is no row: what can be done to the folder
  let folder_menu = fn() -> Array[@sf.MenuItem?] {
    let a = b.arrangement()
    let menu : Array[@sf.MenuItem?] = []
    if write {
      menu.push(Some(@sf.menu_item_of(@sf.t("web-pages.drive.mkdir"), icon="folder-plus", fn() { b.new_folder(c, src, at.path) })))
      menu.push(Some(@sf.menu_item_of(@sf.t("web-pages.drive.upload"), icon="upload", fn() { dv_upload(c, at) })))
    }
    for by in ["name", "time", "size", "kind"] {
      menu.push(Some(@sf.menu_item_of(@sf.t("web-pages.drive.sortBy." + by), chosen=a.by == by, fn() {
        b.arrange_as(c, src, by~, down=false)
      })))
    }
    menu.push(Some(@sf.menu_item_of(@sf.t(if a.hidden { "web-pages.drive.hideHidden" } else { "web-pages.drive.showHidden" }), fn() {
      b.arrange_as(c, src, hidden=!a.hidden)
    })))
    menu.push(Some(@sf.menu_item_of(@sf.t("web-pages.drive.refresh"), icon="refresh", fn() { refresh_folder(c, src, at) })))
    menu
  }
  // (short of room for the list beside the preview, the preview gives way: the list keeps a few names' width)
  let pane_slot = c.id("files/pane-slot/" + f.key)
  c.box(style=with_pane, fn() {
    let lid = c.id("files/list/" + f.key)
    // (a ground round its rows: a press there chooses none)
    c.cursor(lid, Arrow)
    let lit = drag_target(c, lid, "pane/" + f.key + "/" + at.station + "/" + root + "/" + at.path, at, name, shown, 0)
    c.box(style=list_box, id=lid, fn() {
      if view == "columns" {
        // (columns stay while the folder opened is read: each column says its own reading or trouble)
        head()
        uploads_here(c, src, ups_here)
        columns_view(
          c,
          src,
          { ..at, path: "" },
          at.path,
          shown,
          list_room(src, f.room),
          empty?=if ups_here.is_empty() { Some(empty) } else { Some(fn() {  }) },
        )
      } else {
        match (value, error) {
          // (why it was not read: the head's, with its 重试)
          // (its head where its rows' list stands it: @sf.rows_list)
          (None, Some(_)) => @sf.rows_room(c, head)
          (None, None) => {
            @sf.rows_room(c, head)
            @sf.waiting(c, fn() { rows_sample(c, at, shown, 8) })
          }
          (Some(_), _) =>
            match b.arranged(at.path, entries) {
              None => {
                @sf.rows_room(c, head)
                @sf.waiting(c, fn() { rows_sample(c, at, shown, 8) })
              }
              Some(list) =>
                rows_view(
                  c,
                  src,
                  "files/rows/" + f.key + "/" + view + "/" + at.station + "/" + root + "/" + at.path,
                  at,
                  shown,
                  view == "tree",
                  foot~,
                  head=fn() {
                    head()
                    uploads_here(c, src, ups_here)
                    // (its columns' heads where its rows have their columns: not where they say it under the name)
                    if view == "list" && list.length() > 0 && f.room >= row_stack_below {
                      list_head(c, b.arrangement(), fn(by) {
                        let a = b.arrangement()
                        if by == a.by {
                          b.arrange_as(c, src, down=!a.down)
                        } else {
                          b.arrange_as(c, src, by~, down=false)
                        }
                      })
                    }
                  },
                  empty?=if ups_here.is_empty() { Some(empty) } else { None },
                )
            }
        }
      }
      match lit {
        Some(l) => drop_over(c, l, name)
        None => ()
      }
      // a press where there is no row (a row's own is the row's): nothing chosen; a right click there, the folder's
      // menu
      if !row_took(c) {
        if c.clicked(lid) {
          b.clear(c, src)
        }
        match c.menu_asked(lid) {
          Some((x, y)) => @sf.menu(folder_menu(), from=@sf.at_point(x, y))
          None => ()
        }
      }
    })
    |> ignore
    if previewing {
      let ch = b.chosen()
      let p : Previewed = if ch.names.length() > 1 {
        Many(ch.names.length())
      } else {
        match ch.names.get(0) {
          Some(n) =>
            match b.held(src, ch.folder).iter().find_first(fn(e) { e.name == n }) {
              Some(e) => One({ ..at, path: ch.folder }, e)
              None => Nothing
            }
          None => Nothing
        }
      }
      c.box(style=pane_slot_row, id=pane_slot, taps=false, drop=pane_drop, fn() {
        drive_pane(
          c,
          src,
          p,
          sname,
          fn() {
            match p {
              One(pat, e) => open_entry(c, src, "page", pat, e, [e], fn(to) { (f.go)(to, false) })
              _ => ()
            }
          },
          fn() {
            match p {
              One(pat, e) => save_entry(c, src, pat, e)
              _ => ()
            }
          },
          fn(abs) { copy_path(c, abs) },
        )
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The folder's name: its last part; the root by its name as the station lends it, the home as 主目录 for one who
/// browses every folder.
pub fn folder_name(st : DvStation, at : DriveAt) -> String {
  let root = at.root.unwrap_or("")
  if at.path != "" {
    dv_name(at.path)
  } else if st.anywhere && !st.roots.iter().any(fn(r) { r.path == root }) {
    if root == st.home {
      @sf.t("web-pages.drive.home")
    } else {
      let n = dv_name(root.trim_end(chars="/\\").to_string())
      if n == "" {
        root
      } else {
        n
      }
    }
  } else {
    dv_root_label(st.roots, root)
  }
}

///|
/// A row's menu (FolderView itemsIn): about what is chosen when it is among it and more than it, else about it alone.
fn row_items(
  c : @ui.Ctx,
  src : Source,
  f : FolderOf,
  b : Browse,
  in_ : DriveAt,
  e : DvEntry,
  favs : Array[Favorite],
) -> Array[@sf.MenuItem?] {
  let all = b.chosen_with(src, in_.path, e)
  let root = in_.root.unwrap_or("")
  let st = f.st
  let write = f.rights.write
  // (each with its icon: the words of every item on one line)
  let out : Array[@sf.MenuItem?] = []
  let item = fn(label : String, icon : String, act : () -> Unit) { out.push(Some(@sf.menu_item_of(label, icon~, act))) }
  if all.length() > 1 {
    // what is chosen, several at once
    let files = all.filter(fn(x) { !x.1.dir })
    if files.length() > 0 {
      item(@sf.t("web-pages.drive.downloadMany", args=[("n", files.length().to_string())]), "download", fn() {
        for x in files {
          save_entry(c, src, x.0, x.1)
        }
      })
    }
    item(@sf.t("web-pages.drive.copyPaths"), "copy", fn() {
      copy_path(c, all.map(fn(x) { dv_absolute(root, dv_join(x.0.path, x.1.name)) }).join("\n"))
    })
    if write {
      out.push(
        Some(
          @sf.menu_item_of(
            @sf.t(if st.trash { "web-pages.drive.toTrashMany" } else { "web-pages.drive.deleteMany" }, args=[("n", all.length().to_string())]),
            icon="trash",
            danger=true,
            fn() { remove_entries(c, src, st, all) },
          ),
        ),
      )
    }
    return out
  }
  let full = dv_join(in_.path, e.name)
  let abs = dv_absolute(root, full)
  item(@sf.t("web-pages.drive.open"), "eye", fn() {
    open_entry(c, src, "page", in_, e, [e], fn(to) { (f.go)(to, false) })
  })
  if !e.dir {
    item(@sf.t("web-pages.drive.download"), "download", fn() { save_entry(c, src, in_, e) })
    item(@sf.t("android-misc.drive.share"), "external", fn() { share_entry(c, src, in_, e) })
  } else if f.rights.zip {
    item(@sf.t("web-pages.drive.downloadZip"), "download", fn() { save_entry(c, src, in_, e) })
  }
  item(@sf.t("web-pages.drive.copyPath"), "copy", fn() { copy_path(c, abs) })
  match f.open_in {
    Some(open) if e.dir => {
      item(@sf.t("web-pages.files.openInTab"), "plus", fn() { open({ ..in_, path: full }, false) })
      item(@sf.t("web-pages.files.openBeside"), "view-columns", fn() { open({ ..in_, path: full }, true) })
    }
    _ => ()
  }
  if e.dir && !favorite_has(favs, in_.station, root, full) {
    item(@sf.t("web-pages.files.favoriteIt"), "star", fn() {
      favorite_add(src, f.ws, { station: in_.station, root, path: full, name: e.name })
    })
  }
  if e.dir && st.anywhere {
    let on = st.roots.iter().any(fn(r) { r.path == abs })
    item(@sf.t(if on { "web-pages.drive.unpin" } else { "web-pages.drive.pin" }), "pin", fn() {
      pin_folder(c, src, st, abs, !on)
    })
  }
  if write {
    // (changed in place, wherever: the row kept in view over the soft keyboard: rows_view)
    item(@sf.t("web-pages.drive.rename"), "edit", fn() { b.start_rename(c, src, in_.path, e) })
    out.push(
      Some(
        @sf.menu_item_of(
          @sf.t(if st.trash { "web-pages.drive.toTrash" } else { "web-pages.drive.delete" }),
          icon="trash",
          danger=true,
          fn() { remove_entries(c, src, st, [(in_, e)]) },
        ),
      ),
    )
  }
  out
}

///|
/// What can be done to the folder (FolderView's actions), for the bar it is shown under (the files' page's while it
/// is in front, or its own): the ways its room has, the preview, put up and a new folder (who may write), read again
/// (turning while it is read), 收藏 (lit while it is kept), pin (for one who browses every folder: lit while pinned),
/// its ⋯ (复制路径, 前往文件夹, 管理). Short of room they go into the ⋯, what is needed least first.
pub fn folder_actions(c : @ui.Ctx, src : Source, f : FolderOf, style? : @ui.Style = actions_row()) -> Unit {
  let at = f.at
  let root = at.root.unwrap_or("")
  let st = f.st
  let ways = views_for(list_room(src, f.room))
  let view = view_in(src, "page", list_room(src, f.room))
  let previewing = preview_shown(src, "page")
  let here = dv_absolute(root, at.path)
  let name = folder_name(st, at)
  let pinned = st.roots.iter().any(fn(r) { r.path == here })
  let kept = favorite_has(favorites(src, f.ws), at.station, root, at.path)
  let b = browse(c, src, f.key, "page", view, at, f.rights.write, {
    open: fn(_, _) {  },
    preview: fn(_, _) {  },
    go: fn(_, _) {  },
    remove: fn(_) {  },
  })
  let lit = @sf.theme().p.accent
  let on = fn(yes : Bool) -> Int64? { if yes { Some(lit) } else { None } }
  let tools : Array[@sf.Tool] = [
    // (short of room, what is needed least goes into the ⋯ first: reading it again, pinning it, 收藏, the preview,
    // the way it is shown (the others offered there), a new folder; putting files up last)
    @sf.tool_of(
      "view",
      fn() { view_switch(c, "files/view", view, fn(v) { set_drive_view(src, "page", v) }, ways~) },
      drop=folder_drop_view,
      instead=view_icons
        .filter(fn(w) { w.0 != view && ways.contains(w.0) })
        .map(fn(w) { @sf.menu_item_of(@sf.t("web-pages.drive.view." + w.0), fn() { set_drive_view(src, "page", w.0) }, icon=w.1) }),
    ),
  ]
  if pane_fits(f.room) {
    tools.push(
      @sf.tool_button(
        c,
        "files/preview",
        if previewing { "panel-close" } else { "panel-open" },
        @sf.t(if previewing { "web-pages.files.hidePreview" } else { "web-pages.files.showPreview" }),
        on_press=fn() { set_preview_shown(src, "page", !previewing) },
        shortcut="files.preview",
        drop=folder_drop_preview,
        lit?=on(previewing),
      ),
    )
  }
  // (putting files up and a new folder in the system's column where it has the rail's places, the rest here:
  // rail_native.mbt bar_action)
  if f.rights.write &&
    !bar_action("files/upload", @sf.t("web-pages.drive.upload"), "upload", fn() { dv_upload(c, at) }) {
    tools.push(@sf.tool_button(c, "files/upload", "upload", @sf.t("web-pages.drive.upload"), on_press=fn() { dv_upload(c, at) }, drop=folder_drop_upload))
  }
  if f.rights.write &&
    !bar_action("files/mkdir", @sf.t("web-pages.drive.mkdir"), "folder-plus", fn() { b.new_folder(c, src, at.path) }) {
    tools.push(
      @sf.tool_button(c, "files/mkdir", "folder-plus", @sf.t("web-pages.drive.mkdir"), on_press=fn() { b.new_folder(c, src, at.path) }, drop=folder_drop_mkdir),
    )
  }
  tools.push(
    @sf.tool_button(
      c,
      "files/refresh",
      "refresh",
      @sf.t("web-pages.drive.refresh"),
      on_press=fn() { refresh_folder(c, src, at) },
      drop=folder_drop_refresh,
      disabled=refreshing(at),
    ),
  )
  tools.push(
    @sf.tool_button(
      c,
      "files/fav",
      "star",
      @sf.t(if kept { "web-pages.files.unfavorite" } else { "web-pages.files.favorite" }, args=[("name", name)]),
      on_press=fn() {
        if kept {
          favorite_remove(src, f.ws, at.station, root, at.path)
        } else {
          favorite_add(src, f.ws, { station: at.station, root, path: at.path, name })
        }
      },
      drop=folder_drop_favorite,
      lit?=on(kept),
    ),
  )
  if st.anywhere {
    tools.push(
      @sf.tool_button(
        c,
        "files/pin",
        "pin",
        @sf.t(if pinned { "web-pages.drive.unpin" } else { "web-pages.drive.pin" }),
        on_press=fn() { pin_folder(c, src, st, here, !pinned) },
        drop=folder_drop_pin,
        lit?=on(pinned),
      ),
    )
  }
  // its ⋯: the order and hidden files (where its rows have no heads to sort by, and no right click: a finger's), then
  // its path, a folder by its path, 管理
  let a = b.arrangement()
  let more : Array[@sf.MenuItem?] = []
  for by in ["name", "time", "size", "kind"] {
    more.push(Some(@sf.menu_item_of(@sf.t("web-pages.drive.sortBy." + by), chosen=a.by == by, fn() {
      b.arrange_as(c, src, by~, down=false)
    })))
  }
  more.push(Some(@sf.menu_item_of(@sf.t(if a.hidden { "web-pages.drive.hideHidden" } else { "web-pages.drive.showHidden" }), fn() {
    b.arrange_as(c, src, hidden=!a.hidden)
  })))
  more.push(None)
  more.push(Some(@sf.menu_item_of(@sf.t("web-pages.drive.copyPath"), icon="copy", fn() { copy_path(c, here) })))
  match f.go_to {
    Some(g) => more.push(Some(@sf.menu_item_of(@sf.t("web-pages.files.goTo"), icon="search", g)))
    None => ()
  }
  match f.manage {
    Some(m) if f.rights.manage || st.anywhere =>
      more.push(Some(@sf.menu_item_of(@sf.t("web-pages.drive.manage"), icon="folder", m)))
    _ => ()
  }
  @sf.tools_row(c, "files/more", tools, more~, label=@sf.t("web-main.menu.more"), style~)
}

///|
/// The order a folder's actions go into its ⋯ in, short of room (refreshing first, putting files up last).
let folder_drop_refresh : Int = 1

///|
let folder_drop_pin : Int = 2

///|
let folder_drop_favorite : Int = 3

///|
let folder_drop_preview : Int = 4

///|
let folder_drop_view : Int = 5

///|
let folder_drop_mkdir : Int = 6

///|
let folder_drop_upload : Int = 7

///|
/// A row of a folder's list, as the files' page and a chat's 文件 tab draw it (DriveRow): its mark, name, size and time
/// (`compact`: the size alone), the ⋯ on hover and the same on a right click. Pressed it is chosen, a double click opens
/// it, its name is changed in place; pressed and moved it is dragged (what is chosen with it), and a folder takes what
/// is dropped on it. In a tree (`depth`), in by its depth, a folder with its disclosure (`expanded`, `on_toggle`); in
/// columns (`column`), the folder open (`along`) marked as the way to the next column, with › at its end.
pub fn drive_row(
  c : @ui.Ctx,
  src : Source,
  at : DriveAt,
  e : DvEntry,
  row : RowProps,
  s : Shown,
  compact? : Bool = false,
  depth? : Int,
  expanded? : Bool,
  on_toggle? : () -> Unit = fn() {  },
  column? : Bool = false,
  along? : Bool = false,
) -> Unit {
  let t = @sf.theme()
  let root = at.root.unwrap_or("")
  let full = dv_join(at.path, e.name)
  let key = "files/row/" + s.b.key + "/" + at.station + "/" + root + "/" + full
  let id = c.id(key)
  let did = c.id(key + "/open")
  let more = c.id(key + "/menu/more")
  let busy = entry_busy(src, at, e.name)
  let live = !busy && !row.renaming
  // (touch: no ⋯, a hold its menu, a folder's › saying a press goes in; a computer: its ⋯ under the pointer)
  let held_more = @sf.more_held()
  if live {
    if c.pressed(id) {
      drag_press(c, src, at, e)
    }
  }
  // a folder takes what is dropped on it
  let lit = match row.drop {
    Some(into) => drag_target(c, id, "row/" + key, into, e.name, s, 2)
    None => None
  }
  // (a finger: its ⋯ always there, as nothing is hovered; a tap opens it, as a double click does with a mouse)
  let finger = !@sf.pointer_rests()
  if live {
    let asked = c.menu_asked(id)
    match asked {
      Some((x, y)) => {
        held.row_frame = c.frame_number()
        (row.menu)()
        // (had by holding it, its menu says what it is of: a sheet over the row it was held on)
        drive_row_menu(key, (row.items)(), @sf.at_point(x, y), title=if held_more { e.name } else { "" })
      }
      None => ()
    }
    if c.clicked(id) || c.clicked(did) {
      held.row_frame = c.frame_number()
    }
    if asked is Some(_) {
      ()
    } else if depth is Some(_) && e.dir && c.clicked(did) {
      on_toggle()
    } else if c.double_clicked(id) || (finger && c.clicked(id)) {
      (row.open)()
    } else if c.clicked(id) {
      (row.press)()
    }
  }
  let over = c.hovered(id)
  let open = drive_row_menu_drawn(key)
  if open {
    drive_row_menu_now(key, (row.items)())
  }
  let ground = (if lit is Some(_) {
    entry_drop
  } else if row.chosen {
    entry_chosen
  } else if along || open || over {
    entry_along
  } else {
    entry_plain
  }).then(if held_more { entry_held } else { entry_capsule })
  let tree = depth is Some(_)
  let indent = match depth {
    Some(d) => tree_step * d.to_double()
    None => tree_none
  }
  // its sizes the screen's (Theme.items); short of room for its size's and time's columns, what it is goes under its
  // name (a phone's mMeta), by the row's own width
  let items = t.items
  let stacked = !compact && !column && c.width < row_stack_below
  let inner = (if compact && tree {
    row_tree_compact
  } else if tree {
    row_tree
  } else if compact {
    row_compact
  } else {
    row_style
  }).then(@ui.style(min_h=Fixed(if compact { items.least - compact_less } else { items.least })))
  let fetching = match download_of_drive(src, at.station, root, full) {
    Some(d) if flag(Some(d), "active") => Some((number(Some(d), "progress") * 100.0).floor().to_int())
    _ => None
  }
  c.box(style=entry_room, fn() {
    let box = c.box(style=if busy { ground.then(entry_busy_look) } else { ground }, id~, fn() {
      c.box(style=inner.then(@sf.row_least_h()), fn() {
        if tree {
          // (in by its depth: 18 a step, past the 6 every tree row is in by)
          c.box(style=@ui.style(w=Fixed(indent)), fn() {  }) |> ignore
          c.box(style=disclosure_box, id=if e.dir { did } else { 0 }, fn() {
            if e.dir {
              @sf.icon(c, if expanded == Some(true) { "chevron-down" } else { "chevron-right" }, size=disclosure_icon, color=t.p.muted)
              |> ignore
            }
          })
          |> ignore
        }
        @sf.icon(c, dv_kind_icon(if e.dir { "folder" } else { e.kind }), size=if compact { items.mark - compact_less_mark } else { items.mark }, color=t.p.muted)
        |> ignore
        // (a name: cut short where what follows it leaves it less)
        let name_words = items.name.then(file_name_cut)
        let size = if e.dir || column { "" } else { e.size_text }
        if row.renaming {
          name_field(c, key + "/name", s.b, e, row)
        } else if compact {
          @sf.name_words(c, e.name, items.name) |> ignore
        } else if stacked {
          // its name, what it is under it (a folder's time; a file's size · time)
          c.box(style=name_stack, fn() {
            c.text(e.name, style=name_words) |> ignore
            let line = if e.dir { e.time_text } else { dv_words([size, e.time_text], " · ") }
            if line != "" {
              c.text(line, style=items.meta) |> ignore
            }
          })
          |> ignore
        } else {
          // (short of room, the name keeps a few words: the size goes first, then the time, as the heads do)
          c.box(style=name_cell, fn() { c.text(e.name, style=name_words) |> ignore }) |> ignore
        }
        if compact {
          // (how far it has come down, in words: a compact row has no room for the chip in its corner)
          match fetching {
            Some(p) => c.text("\{p}%", style=items.meta) |> ignore
            None => if size != "" { c.text(size, style=items.meta) |> ignore }
          }
          c.box(style=end_compact, fn() {  }) |> ignore
        } else if !stacked {
          c.box(style=size_cell, drop=list_drop_size, fn() { c.text(size, style=items.meta) |> ignore }) |> ignore
          c.box(style=time_cell, drop=list_drop_time, fn() { c.text(e.time_text, style=items.meta) |> ignore }) |> ignore
        }
        if stacked || held_more {
          // what is at its end in the flow: something under way, how far it has come down, how far it was read, a
          // folder's ›
          c.box(style=end_flow, fn() {
            if busy {
              @sf.spinner(c) |> ignore
            } else if fetching is Some(p) && !compact {
              download_chip(c, at.station + "/" + full, p)
            } else if e.kind == "text" || e.kind == "markdown" {
              read_share(c, src, at.station, root, full)
            } else if e.dir && held_more {
              @sf.icon(c, "chevron-right", size=finger_chevron, color=t.p.subtle) |> ignore
            }
          })
          |> ignore
        }
        if !held_more && !compact {
          c.box(style=end_cell, fn() {  }) |> ignore
        }
      })
      |> ignore
      // at its end, a mouse's: › on the folder open beside (columns), the ⋯ on hover (Drive.css.ts more, next; a
      // spinner while something is under way)
      c.layer(fn() {
        if held_more {
          return
        }
        // (a row stacked is as high as its two lines: as it is laid out, read back)
        let least_h = dmax(@sf.row_least(), if compact { items.least - compact_less } else { items.least })
        let row_h = match c.laid_size(id) {
          Some((_, h)) if stacked && h > least_h => h
          _ => least_h
        }
        c.box(style=more_place_at(row_h, if compact { more_compact } else { more_size }), fn() {
          let shown = over || open
          if busy && !stacked {
            @sf.spinner(c) |> ignore
          } else if busy {
            ()
          } else if shown || !(column && e.dir && along) {
            // (there whether shown or not, clear while not: the hand changes no box)
            c.box(style=if shown { more_shown } else { more_clear }, fn() {
              // (round, in the middle of the row's capsule end, concentric with it)
              if @sf.icon_button(
                  c,
                  "more",
                  key=key + "/menu/more",
                  size=if compact { more_compact } else { more_size },
                  on=open,
                  round=true,
                  label=@sf.t("web-main.menu.more"),
                ) {
                drive_row_menu(key, (row.items)(), Of(more), along=End)
              }
            })
            |> ignore
          } else {
            c.box(style=next_box, fn() {
              @sf.icon(c, "chevron-right", size=disclosure_icon, color=t.p.muted) |> ignore
            })
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
      // (a finger's press ripples)
      if live {
        @sf.press_ripple(c, id, if held_more { @sf.row_corner } else { row_round })
      }
    })
    c.semantics(box, Button, id~, label=e.name, selected=row.chosen, expanded?=if tree && e.dir { Some(expanded == Some(true)) } else { None })
  })
  |> ignore
}

///|
/// A name changed in place (NameField): the name but its extension picked; ⏎ or leaving it keeps it, esc leaves it as
/// it was.
fn name_field(c : @ui.Ctx, key : String, b : Browse, e : DvEntry, row : RowProps) -> Unit {
  let t = @sf.theme()
  if held.naming.get() != key {
    held.naming.set(key)
    held.naming_had = false
  }
  c.box(style=name_field_box, fn() {
    let r = c.editor(
      key,
      font_size=t.t.ui,
      line=t.t.ui_line,
      max_lines=1,
      plain=true,
      color=t.p.text,
      caret_color=t.p.accent,
      enter_sends=true,
      field=b.rename_field(),
    )
    if !r.focused && !held.naming_had {
      c.focus_editor(key)
    }
    if c.key_pressed(@ui.key_escape, in_field=true) {
      held.naming.set("")
      (row.rename)(None)
    } else {
      match r.submitted {
        Some(words) => {
          held.naming.set("")
          (row.rename)(Some(words))
        }
        None =>
          if r.focused {
            held.naming_had = true
          } else if held.naming_had {
            // left: kept
            held.naming.set("")
            (row.rename)(Some(r.text))
          }
      }
    }
  })
  |> ignore
  ignore(e)
}

///|
/// Over a list, what its columns are (ListHead), each ordering it (again: the other way): the one it is in marked, its
/// chevron down or up.
pub fn list_head(c : @ui.Ctx, a : Arrangement, on_sort : (String) -> Unit) -> Unit {
  let t = @sf.theme()
  let head = fn(by : String, words : String, style : @ui.Style) {
    let id = c.id("files/head/" + by)
    if c.clicked(id) {
      on_sort(by)
    }
    let on = a.by == by
    let b = c.box(style~, id~, fn() {
      c.text(words, style=if on || c.lit(id) { head_words_on } else { head_words }) |> ignore
      if on {
        @sf.icon(c, if a.down { "chevron-up" } else { "chevron-down" }, size=head_chevron, color=t.p.text) |> ignore
      }
    })
    c.semantics(b, Button, id~, label=words, pressed=on)
  }
  c.box(style=list_head_row, fn() {
    c.box(style=head_mark, fn() {  }) |> ignore
    head("name", @sf.t("web-pages.drive.sortBy.nameHead"), head_name)
    c.box(drop=list_drop_size, fn() { head("size", @sf.t("web-pages.drive.sortBy.sizeHead"), head_size) }) |> ignore
    c.box(drop=list_drop_time, fn() { head("time", @sf.t("web-pages.drive.sortBy.timeHead"), head_time) }) |> ignore
    c.box(style=end_cell, fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// A file going up into the folder shown (UploadRow): its mark, its name, how far (a thin bar, sent of its size); its
/// name taken there (替换, 保留两者), or why it failed (重试); × lets it go. Wide, how far beside its name; narrower than
/// its columns need (row_stack_below), under it, as a list's row says what it is.
pub fn upload_row(c : @ui.Ctx, src : Source, u : DvUpload) -> Unit {
  let t = @sf.theme()
  let items = t.items
  let k = "files/up/\{u.serial}"
  let stacked = c.width < row_stack_below
  let size = u.bytes.length()
  let part = if size > 0 { dmin(u.sent.get().to_double() / size.to_double(), all) } else { none }
  let how_far = @sf.t("web-pages.drive.uploading", args=[("sent", @sf.file_size(u.sent.get().to_double())), ("size", @sf.file_size(size.to_double()))])
  let replace = fn() {
    u.replace = true
    u.state.set("waiting")
    dv_pump(src)
  }
  let keys = fn() {
    if u.state.get() == "failed" && @sf.icon_button(c, "retry", key=k + "/retry", label=@sf.t("web-pages.drive.retry")) {
      u.state.set("waiting")
      u.error.set("")
      u.sent.set(0)
      dv_pump(src)
    }
    if @sf.icon_button(c, "close", key=k + "/cancel", label=@sf.t("common.cancel")) {
      ups.uploads.retain(fn(x) { x.serial != u.serial })
      if u.state.get() == "going" {
        ups.pumping.set(false)
        dv_pump(src)
      }
    }
  }
  c.box(style=entry_room, fn() {
    c.box(style=entry_plain, fn() {
      c.box(style=(if stacked { upload_stacked } else { row_style }).then(@ui.style(min_h=Fixed(items.least))), fn() {
        if stacked {
          // its mark, its name and its keys on its first line; under it, as far in as its name and on lines of their
          // own, how far, what is asked (its answers after it, under it where the line has not the room) or why it
          // failed
          c.box(style=upload_first, fn() {
            @sf.icon(c, "upload", size=items.mark, color=t.p.muted) |> ignore
            c.box(style=name_stack, fn() { c.text(u.name.get(), style=items.name.then(file_name_cut)) |> ignore }) |> ignore
            c.box(style=upload_keys, fn() { keys() }) |> ignore
          })
          |> ignore
          c.box(style=upload_under.then(@ui.style(pl=@sf.room_of(upload_under_in + items.mark))), fn() {
            match u.state.get() {
              "taken" =>
                c.box(style=upload_ask_line, flow=true, line_gap=0.0, fn() {
                  c.text(@sf.t("web-pages.drive.taken"), style=items.meta.then(@sf.one_line)) |> ignore
                  c.box(style=upload_answers, fn() {
                    upload_answer(c, k + "/replace", @sf.t("web-pages.drive.replace"), replace)
                    upload_answer(c, k + "/both", @sf.t("web-pages.drive.keepBoth"), fn() { dv_keep_both(src, u) })
                  })
                  |> ignore
                })
                |> ignore
              "failed" =>
                c.text(@sf.t("web-pages.drive.uploadFailed", args=[("error", u.error.get())]), style=items.meta.then(upload_failed_under))
                |> ignore
              _ => {
                c.text(how_far, style=items.meta) |> ignore
                c.box(style=upload_bar_under, fn() { @sf.progress(c, k, if size > 0 { Some(part) } else { None }) }) |> ignore
              }
            }
          })
          |> ignore
        } else {
          @sf.icon(c, "upload", size=items.mark, color=t.p.muted) |> ignore
          // (its name, and beside it how far, what is asked or why it failed: its name keeps a few words, what is
          // asked its two answers alone)
          c.box(style=upload_words, flow=true, line_gap=0.0, fn() {
            c.box(style=upload_name, fn() { c.text(u.name.get(), style=items.name.then(file_name_cut)) |> ignore }) |> ignore
            match u.state.get() {
              "taken" =>
                c.box(style=upload_ask, fn() {
                  c.box(drop=upload_drop_note, fn() { c.text(@sf.t("web-pages.drive.taken"), style=items.meta) |> ignore })
                  |> ignore
                  if @sf.button(c, @sf.t("web-pages.drive.replace"), key=k + "/replace", tone=Ghost) {
                    replace()
                  }
                  if @sf.button(c, @sf.t("web-pages.drive.keepBoth"), key=k + "/both", tone=Ghost) {
                    dv_keep_both(src, u)
                  }
                })
                |> ignore
              "failed" =>
                c.box(style=upload_why, fn() {
                  c.text(@sf.t("web-pages.drive.uploadFailed", args=[("error", u.error.get())]), style=upload_failed) |> ignore
                })
                |> ignore
              _ => {
                let rest = all - part
                c.box(style=progress_cell, keep=true, fn() {
                  c.box(style=progress_track, fn() {
                    c.box(style=progress_done.then(@ui.style(w=Grow(part))), fn() {  }) |> ignore
                    c.box(style=@ui.style(w=Grow(rest)), fn() {  }) |> ignore
                  })
                  |> ignore
                  // (short of room, how much has gone up leaves whole, its bar kept)
                  c.box(drop=upload_drop_sent, fn() { c.text(how_far, style=items.meta) |> ignore }) |> ignore
                })
                |> ignore
              }
            }
          })
          |> ignore
          c.box(style=end_cell, fn() {  }) |> ignore
        }
      })
      |> ignore
      if !stacked {
        c.layer(fn() { c.box(style=more_place, fn() { keys() }) |> ignore }) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// An answer to what is asked of a file going up, under its name: its words in the link's ink, 600.
fn upload_answer(c : @ui.Ctx, key : String, words : String, act : () -> Unit) -> Unit {
  let id = c.id(key)
  if c.clicked(id) {
    act()
  }
  let b = c.box(style=upload_answer_box, id~, fn() { c.text(words, style=@sf.theme().items.meta.then(upload_answer_words)) |> ignore })
  c.semantics(b, Button, id~, label=words)
}

///|
/// Stacked: its first line (its mark, its name cut short, its keys), the lines under it in from the row's start as
/// far as its name (its mark and the 12 after it), to the row's end (12 in), 8 under the last.
// kept across runs: a value (no field of it changes)
let upload_stacked : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let upload_first : @ui.Style = @ui.css("row w=Full px=S3 pt=S2 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let upload_under : @ui.Style = @ui.css("w=Full pr=S3 pb=S2")

///|
/// How far in from a row's start its name is past its mark (row_style's 12 in, 12 after the mark).
let upload_under_in : Double = 24.0

///|
/// A file's name on one line, cut short where what follows it on its row leaves it less (a name).
// kept across runs: a value (no field of it changes)
let file_name_cut : @ui.TextStyle = @ui.text_style(wrap=false, w=Cut)

///|
/// Under its name (mUploadAsk, mProgress): what is asked, its answers after it (under it where the line has not the
/// room), 12 apart; the bar 5 under the words; why it failed in red, as long as it needs.
// kept across runs: a value (no field of it changes)
let upload_ask_line : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let upload_answers : @ui.Style = @ui.css("row gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let upload_answer_box : @ui.Style = @ui.css("row py=S1")

///|
// kept across runs: a value (no field of it changes)
let upload_answer_words : @ui.TextStyle = @ui.text_style(weight=Semibold, color=Link, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let upload_bar_under : @ui.Style = @ui.css("w=Full pt=S1_25")

///|
// kept across runs: a value (no field of it changes)
let upload_failed_under : @ui.TextStyle = @ui.text_style(color=Danger, wrap=true, w=Full)

///|
// kept across runs: a value (no field of it changes)
let upload_keys : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
/// The files going up into the folder shown, together as its rows are (@sf.group_row).
fn uploads_here(c : @ui.Ctx, src : Source, ups_here : Array[DvUpload]) -> Unit {
  for i, u in ups_here {
    @sf.group_row(c, i == 0, i == ups_here.length() - 1, fn() { upload_row(c, src, u) })
  }
}

///|
/// Nothing in the folder (Empty): a folder's mark (36), what it says, what can be done (put files up).
pub fn folder_empty(c : @ui.Ctx, words : String, upload : (() -> Unit)?) -> Unit {
  let t = @sf.theme()
  c.box(style=empty_box, fn() {
    @sf.icon(c, "folder", size=empty_icon, color=t.p.muted) |> ignore
    c.text(words, style=empty_words) |> ignore
    match upload {
      Some(up) => if @sf.button(c, @sf.t("web-pages.drive.upload"), key="files/empty/upload", icon="upload") { up() }
      None => ()
    }
  })
  |> ignore
}

///|
/// What is held over the folder shown (drop): over the list, where it goes, in words.
fn drop_over(c : @ui.Ctx, lit : String, name : String) -> Unit {
  let t = @sf.theme()
  c.layer(fn() {
    // (10 in from the list's edges, the ladder's inset: what it holds goes on round it, square)
    c.box(style=drop_room, fn() {
      c.box(style=drop_box, fn() {
        @sf.icon(c, if lit == "upload" { "upload" } else { "move" }, size=drop_icon, color=t.p.text) |> ignore
        let key = match lit {
          "copy" => "web-pages.files.copyHere"
          "move" => "web-pages.files.moveHere"
          _ => "web-pages.drive.dropHere"
        }
        c.text(@sf.t(key, args=[("name", name)]), style=drop_words) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The preview's width beside the list (DrivePane.css.ts pane).
pub let pane_w : Double = 300.0

///|
/// Whether a folder's room `room` across has the preview beside its list: where the page is laid out wide, the list
/// keeping what is left (a narrow page's whole width is its list's).
fn pane_fits(room : Double) -> Bool {
  room >= @sf.page_narrow_most
}

///|
/// What a folder's list has across in its room `room`: what the preview beside it leaves, where it is shown.
fn list_room(src : Source, room : Double) -> Double {
  if preview_shown(src, "page") && pane_fits(room) {
    room - pane_w - 1.0
  } else {
    room
  }
}

///|
/// A compact row (a column's, a chat's 文件 tab's) 8 less high than the screen's, its mark 2 less (KindIcon 20, compact
/// 18); a tree's disclosure's chevron (12), the ⋯ (32; compact 24), the empty folder's mark (36), what is dropped's
/// (22), the heads' chevron (10); a folder's › to a finger (14).
let compact_less : Double = 8.0

///|
let compact_less_mark : Double = 2.0

///|
let finger_chevron : Double = 14.0

///|
/// Narrower than this, a row says what it is under its name (its size's and time's columns would leave its name too
/// little).
let row_stack_below : Double = 440.0


///|
let disclosure_icon : Double = 12.0

///|
/// A ripple's corner on a row (entry_plain, a capsule): past any row's half, so as round as the row.
let row_round : Double = 1000.0

///|
let more_size : Double = 32.0

///|
let more_compact : Double = 24.0

///|
let empty_icon : Double = 36.0

///|
let drop_icon : Double = 22.0

///|
let head_chevron : Double = 10.0

///|
/// A tree's row in by 6 (its padding) and a step (18: drive_views.mbt tree_step) a depth; a list's by none.
let tree_none : Double = 0.0

///|
/// The time's column (104).
let time_w : Double = 104.0

///|
/// What a bar is filled by at most and at least.
let all : Double = 1.0

///|
let none : Double = 0.0

///|
/// The list and the preview beside it (withPane).
// kept across runs: a value (no field of it changes)
let with_pane : @ui.Style = @ui.css("row w=Full h=Full")

///|
/// The entries (list): rows 2 apart, on the page's ground (no corner of its own: its head's station button and its rows
/// stand in none; what is held over it is rounded itself).
// kept across runs: a value (no field of it changes)
let list_box : @ui.Style = @ui.style(w=@sf.grow, min_w=S56, h=Full, clip=true)

///|
/// The preview beside the list goes first, short of room (the list keeps its least, 224).
let pane_drop : Int = 1

///|
/// The preview and its rule, as tall as the list.
// kept across runs: a value (no field of it changes)
let pane_slot_row : @ui.Style = @ui.css("row h=Full")

///|
/// A row's room in the list (its 2 to the next: list's gap).
// kept across runs: a value (no field of it changes)
let entry_room : @ui.Style = @ui.css("w=Full pb=S0_5")

///|
/// A row's ground (entry): with its ⋯ at its end (a pointer's), a capsule, as round as it is high (the round ⋯ in the
/// middle of its end concentric with it, whatever its height: 外圆角 = 距离 + 半高); its ⋯ had by holding it (a
/// finger's), a row's corner of the ladder's (what is in the middle of its end in none of its corners); as its press
/// ripples; the list's under the pointer, the selected's chosen, the accent's ringed where a drop goes in; faded while
/// something is under way on it.
// kept across runs: a value (no field of it changes)
let entry_plain : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let entry_capsule : @ui.Style = @ui.css("radius=Full")

///|
// kept across runs: a value (no field of it changes)
let entry_held : @ui.Style = @ui.style(radius=@sf.row_radius)

///|
// kept across runs: a value (no field of it changes)
let entry_along : @ui.Style = entry_plain.then(@ui.css("bg=ListGround"))

///|
// kept across runs: a value (no field of it changes)
let entry_chosen : @ui.Style = entry_plain.then(@ui.css("bg=Selected"))

///|
// kept across runs: a value (no field of it changes)
let entry_drop : @ui.Style = entry_plain.then(@ui.css("bg=AccentBg border=B1 border_color=Accent"))

///|
// kept across runs: a value (no field of it changes)
let entry_busy_look : @ui.Style = @ui.css("opacity=O60")

///|
/// A row (row): as high as the screen's items at least, 8 by 12 in, its parts 12 apart: its mark, its name, its size
/// (96) and time (104) at their end, room for its ⋯ (36).
// kept across runs: a value (no field of it changes)
let row_style : @ui.Style = @ui.css("row w=Full px=S3 py=S2 gap=S3 align=ACenter")

///|
/// A chat's 文件 tab's and a column's (compact): 8 less high, 6 by 10 in, 10 apart, the size alone, room for its ⋯ (28).
// kept across runs: a value (no field of it changes)
let row_compact : @ui.Style = @ui.css("row w=Full px=S2_5 py=S1_5 gap=S2_5 align=ACenter")

///|
/// In a tree: 8 apart, its disclosure (12) before its mark, in by its depth.
// kept across runs: a value (no field of it changes)
let row_tree : @ui.Style = row_style.then(@ui.css("gap=S2 pl=S1_5"))

///|
// kept across runs: a value (no field of it changes)
let row_tree_compact : @ui.Style = row_compact.then(@ui.css("gap=S2 pl=S1_5"))

///|
// kept across runs: a value (no field of it changes)
let disclosure_box : @ui.Style = @ui.css("w=S3 h=S3 align=ACenter justify=JCenter")


///|
/// Its name with what it is under it, in what is left of its row.
// kept across runs: a value (no field of it changes)
let name_stack : @ui.Style = @ui.style(w=@sf.grow, min_w=S16)

///|
/// What is at its end in its flow (a finger's, or under the name): 8 before it.
// kept across runs: a value (no field of it changes)
let end_flow : @ui.Style = @ui.css("row pl=S2 align=ACenter")


///|
// kept across runs: a value (no field of it changes)
let size_cell : @ui.Style = @ui.css("row w=S24 justify=JEnd")

///|
/// A list's name in what is left of its row, never less than a few words (32: 128); its head the same.
// kept across runs: a value (no field of it changes)
let name_cell : @ui.Style = @ui.style(w=@sf.grow, min_w=S32)

///|
/// The order a list's columns leave its rows and heads in, short of room: the size, then the time.
let list_drop_size : Int = 1

///|
let list_drop_time : Int = 2

///|
// kept across runs: a value (no field of it changes)
let time_cell : @ui.Style = @ui.style(row=true, w=Fixed(time_w), justify=JEnd)

///|
// kept across runs: a value (no field of it changes)
let end_cell : @ui.Style = @ui.css("w=S9")

///|
// kept across runs: a value (no field of it changes)
let end_compact : @ui.Style = @ui.css("w=S7")

///|
/// Its ⋯ (more), and › in columns (next: 24), 6 in from its end, in its middle.
// kept across runs: a value (no field of it changes)
let more_place : @ui.Style = @ui.css("row w=Full h=Full pr=S1_5 gap=SPx align=ACenter justify=JEnd")

///|
/// The same at a row `row` high, its ⋯ `side` across: as far from the row's end as from its top and foot, in the middle
/// of the row's capsule end concentric with it (entry_capsule).
fn more_place_at(row : Double, side : Double) -> @ui.Style {
  let end = dmax(0.0, (row - side) / 2.0)
  more_place.then(@ui.style(pr=@sf.room_of(end)))
}

///|
/// The ⋯ shown (pointed at, or a finger's), or there and clear.
// kept across runs: a value (no field of it changes)
let more_shown : @ui.Style = @ui.css("row")

///|
// kept across runs: a value (no field of it changes)
let more_clear : @ui.Style = @ui.css("row opacity=O0")

///|
// kept across runs: a value (no field of it changes)
let next_box : @ui.Style = @ui.css("w=S6 h=S6 align=ACenter justify=JCenter")

///|
/// A name changed in place (nameField): a line of the accent round it, the option's corner, on the page's ground.
// kept across runs: a value (no field of it changes)
let name_field_box : @ui.Style = @ui.style(w=@sf.grow, px=S1_5, py=S0_5, radius=Xl, border=B1, border_color=Accent, bg=Bg)

///|
/// The heads (listHead): 12 in and 4 under, over the row's columns, 12 apart, their words the meta's.
// kept across runs: a value (no field of it changes)
let list_head_row : @ui.Style = @ui.css("row w=Full px=S3 pb=S1 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let head_mark : @ui.Style = @ui.css("w=S5")

///|
// kept across runs: a value (no field of it changes)
let head_name : @ui.Style = @ui.style(row=true, w=@sf.grow, min_w=S32, gap=S1, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let head_size : @ui.Style = @ui.css("row w=S24 gap=S1 align=ACenter justify=JEnd")

///|
// kept across runs: a value (no field of it changes)
let head_time : @ui.Style = @ui.style(row=true, w=Fixed(time_w), gap=S1, align=ACenter, justify=JEnd)

///|
// kept across runs: a value (no field of it changes)
let head_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let head_words_on : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
/// Going up: how far it has got (a 2 high bar on the words at 10%, filled in the accent), its size.
// kept across runs: a value (no field of it changes)
let progress_cell : @ui.Style = @ui.style(row=true, w=@sf.grow, max_w=Fixed(progress_w), gap=S2_5, align=ACenter)

///|
/// The size and time columns' (96 and 104 and their gap).
let progress_w : Double = 212.0

///|
// kept across runs: a value (no field of it changes)
let progress_track : @ui.Style = @ui.style(row=true, w=@sf.grow, min_w=S12, h=S0_5, radius=Sm, bg=TintStrong, clip=true)

///|
// kept across runs: a value (no field of it changes)
let progress_done : @ui.Style = @ui.css("h=Full bg=Accent")

///|
/// Its name taken there, or why it failed: at its end, 64 short of it (ask, failed).
// kept across runs: a value (no field of it changes)
let upload_ask : @ui.Style = @ui.css("row gap=S1 pr=S9 align=ACenter justify=JEnd")

///|
/// Why it failed: what is left beside its name, cut short, clear of its two buttons (重试, ×: 64).
// kept across runs: a value (no field of it changes)
let upload_why : @ui.Style = @ui.style(row=true, w=@sf.grow, pr=S16, align=ACenter, justify=JEnd)

///|
/// Its name, never less than a few words (16: 64).
// kept across runs: a value (no field of it changes)
let upload_name : @ui.Style = @ui.style(w=@sf.grow, min_w=S16)

///|
/// What leaves an upload's row first, short of room: what its answers are about (已有同名文件).
let upload_drop_note : Int = 1

///|
/// What leaves an upload's bar, short of room: how much has gone up of its size, the bar kept (never less than 48).
let upload_drop_sent : Int = 1

///|
/// An upload's name and what is beside it (how far, what is asked, why it failed), in what is left of its row.
// kept across runs: a value (no field of it changes)
let upload_words : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S3, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let upload_failed : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, wrap=false, w=Cut)



///|
/// Nothing in it (empty): in the middle, 56 by 24 in, 12 apart, muted.
// kept across runs: a value (no field of it changes)
let empty_box : @ui.Style = @ui.css("w=Full pt=S14 pb=S14 px=S6 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let empty_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, center=true)

///|
/// What is held over the list (drop): over all of it, its words and mark in the middle, the page's ground at 82%
/// under them, ringed in the accent.
// kept across runs: a value (no field of it changes)
let drop_box : @ui.Style = @ui.css(
  #|w=Full h=Full gap=S2 align=ACenter justify=JCenter radius=Xl2 bg=A(Bg,O80) border=B2 border_color=A(Accent,O60)
)

///|
// kept across runs: a value (no field of it changes)
let drop_room : @ui.Style = @ui.style(w=Full, h=Full, p=@sf.inset_room)

///|
// kept across runs: a value (no field of it changes)
let drop_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false)

///|
/// What is done to the folder (actions): 6 apart, more where a press's room needs it (@sf.keys_gap).
fn actions_row() -> @ui.Style {
  actions_row_look.then(@ui.style(gap=@sf.keys_gap(least=@sf.tools_apart)))
}

///|
// kept across runs: a value (no field of it changes)
let actions_row_look : @ui.Style = @ui.css("row align=ACenter justify=JEnd")
