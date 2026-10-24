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
/// What is asked about before it goes for good (no trash takes it), by the place's key; the name being changed in place
/// and whether its field had the focus (it is done once it leaves).
priv struct DriveHeld {
  removing : Map[String, Array[(DriveAt, DvEntry)]]
  mut naming : String
  mut naming_had : Bool
  refreshing : Map[String, Bool]
  mut row_frame : Int
}

///|
let held : DriveHeld = { removing: {}, naming: "", naming_had: false, refreshing: {}, row_frame: -1 }

///|
fn drive_reset() -> Unit {
  held.removing.clear()
  held.naming = ""
  held.naming_had = false
  held.refreshing.clear()
  held.row_frame = -1
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
    "read" => app.nav.push(DriveRead({ station: in_.station, root: Some(root), path: full }))
    "play" => app.nav.push(DrivePlay({ station: in_.station, root: Some(root), path: full }))
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
/// them, asked first (`key`: the place asking), then for good.
pub fn remove_entries(c : @ui.Ctx, src : Source, key : String, st : DvStation, items : Array[(DriveAt, DvEntry)]) -> Unit {
  if items.is_empty() {
    return
  }
  if !st.trash {
    held.removing[key] = items
    return
  }
  let what = @sf.t("web-pages.drive.deleteWhat")
  let left : Array[(DriveAt, DvEntry)] = []
  let answered = Ref(0)
  c.tell("remove/" + key, fn() {
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
              held.removing[key] = left
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
fn remove_confirm(c : @ui.Ctx, src : Source, key : String) -> Unit {
  let asking = held.removing.get(key).unwrap_or([])
  let title = match asking {
    [] => ""
    [(_, e)] =>
      @sf.t(if e.dir { "web-pages.drive.deleteFolderAsk" } else { "web-pages.drive.deleteAsk" }, args=[("name", e.name)])
    many => @sf.t("web-pages.drive.deleteManyAsk", args=[("n", many.length().to_string())])
  }
  let words = if asking.iter().any(fn(x) { x.1.dir }) {
    @sf.t("web-pages.drive.deleteFolderText")
  } else {
    @sf.t("web-pages.drive.deleteText")
  }
  let r = @sf.confirm_dialog(
    c,
    "files/remove/" + key,
    !asking.is_empty(),
    title,
    words,
    @sf.t("web-pages.drive.delete"),
    cancel=@sf.t("common.cancel"),
  )
  if r.confirmed {
    held.removing.remove(key)
    let what = @sf.t("web-pages.drive.deleteWhat")
    c.tell("remove-for-good/" + key, fn() {
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
    })
  } else if !r.open {
    held.removing.remove(key)
  }
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
/// The folder's own (FolderView): a folder of a station in the way the page shows it, the files going up into it over
/// its rows, its preview beside it (⌘⇧P); what is dropped where no folder of it takes it goes into it. Its keys
/// while it is in front: the rows' (the core's), ⌘U puts files up, ⌘⇧N a new folder, ⌘⇧P the preview.
pub fn folder_view(c : @ui.Ctx, src : Source, f : FolderOf) -> Unit {
  let at = f.at
  let root = at.root.unwrap_or("")
  let st = f.st
  let write = f.rights.write
  let view = drive_view(src, "page")
  let (value, error) = drive_folder(src, at.station, root, at.path)
  let entries = items(value, "entries").map(dv_entry)
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
    remove: fn(items) { remove_entries(c, src, f.key, st, items) },
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
  let previewing = preview_shown(src, "page")
  if f.front && !c.field_focused() {
    b.keys(c, src)
    if write && c.shortcut('u') {
      dv_upload(c, at)
    }
    if write && c.shortcut('n', shift=true) {
      b.new_folder(c, src, at.path)
    }
    if c.shortcut('p', shift=true) {
      set_preview_shown(src, "page", !previewing)
    }
  }
  let ups_here = ups.uploads.filter(fn(u) { u.station == at.station && u.root == root && u.dir == at.path })
  let empty = fn() {
    folder_empty(c, @sf.t("web-pages.drive.emptyFolder"), if write { Some(fn() { dv_upload(c, at) }) } else { None })
  }
  let list_menu = "files/list-menu/" + f.key
  // (short of room for the list beside the preview, the preview gives way: the list keeps a few names' width)
  let pane_slot = c.id("files/pane-slot/" + f.key)
  let pane_shown = previewing && !c.left_out(pane_slot)
  c.box(style=with_pane, fn() {
    let lid = c.id("files/list/" + f.key)
    let lit = drag_target(c, lid, "pane/" + f.key + "/" + at.station + "/" + root + "/" + at.path, at, name, shown, 0)
    c.box(style=list_box, id=lid, fn() {
      if view == "columns" {
        // (columns stay while the folder opened is read: each column says its own reading or trouble)
        for u in ups_here {
          upload_row(c, src, u, entries)
        }
        columns_view(
          c,
          src,
          { ..at, path: "" },
          at.path,
          shown,
          f.room - (if pane_shown { pane_w + 1.0 } else { 0.0 }),
          empty?=if ups_here.is_empty() { Some(empty) } else { Some(fn() {  }) },
        )
      } else {
        match (value, error) {
          (None, Some(e)) =>
            c.box(style=problem_box, fn() {
              c.text(e, style=problem_words) |> ignore
              if @sf.button(c, @sf.t("web-pages.drive.retry"), key="files/retry/" + f.key, tone=Ghost, icon="retry") {
                refresh_folder(c, src, at)
              }
            })
            |> ignore
          (None, None) => @sf.waiting(c, count=8)
          (Some(_), _) =>
            match b.arranged(at.path, entries) {
              None => @sf.waiting(c, count=8)
              Some(list) =>
                rows_view(
                  c,
                  src,
                  "files/rows/" + f.key + "/" + view + "/" + at.station + "/" + root + "/" + at.path,
                  at,
                  shown,
                  view == "tree",
                  head=fn() {
                    for u in ups_here {
                      upload_row(c, src, u, entries)
                    }
                    if view == "list" && list.length() > 0 {
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
          Some((x, y)) => @sf.menu_open_here(list_menu, x, y)
          None => ()
        }
      }
    })
    |> ignore
    // a right click where there is no row: what can be done to the folder
    let a = b.arrangement()
    let menu : Array[@sf.MenuItem?] = []
    if write {
      menu.push(Some(@sf.menu_item_of(@sf.t("web-pages.drive.mkdir"), icon="folder-plus", fn() { b.new_folder(c, src, at.path) })))
      menu.push(Some(@sf.menu_item_of(@sf.t("web-pages.drive.upload"), icon="upload", fn() { dv_upload(c, at) })))
    }
    for by in ["name", "time", "size", "kind"] {
      menu.push(Some(@sf.menu_item_of(@sf.t("web-pages.drive.sortBy." + by), icon=if a.by == by { "check" } else { "" }, fn() {
        b.arrange_as(c, src, by~, down=false)
      })))
    }
    menu.push(Some(@sf.menu_item_of(@sf.t(if a.hidden { "web-pages.drive.hideHidden" } else { "web-pages.drive.showHidden" }), fn() {
      b.arrange_as(c, src, hidden=!a.hidden)
    })))
    menu.push(Some(@sf.menu_item_of(@sf.t("web-pages.drive.refresh"), icon="refresh", fn() { refresh_folder(c, src, at) })))
    @sf.context_items(c, list_menu, menu) |> ignore
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
  remove_confirm(c, src, f.key)
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
            fn() { remove_entries(c, src, f.key, st, all) },
          ),
        ),
      )
    }
    return out
  }
  let full = dv_join(in_.path, e.name)
  let abs = dv_absolute(root, full)
  item(@sf.t("web-pages.drive.open"), "", fn() {
    open_entry(c, src, "page", in_, e, [e], fn(to) { (f.go)(to, false) })
  })
  if !e.dir {
    item(@sf.t("web-pages.drive.download"), "download", fn() { save_entry(c, src, in_, e) })
  } else if f.rights.zip {
    item(@sf.t("web-pages.drive.downloadZip"), "download", fn() { save_entry(c, src, in_, e) })
  }
  item(@sf.t("web-pages.drive.copyPath"), "copy", fn() { copy_path(c, abs) })
  match f.open_in {
    Some(open) if e.dir => {
      item(@sf.t("web-pages.files.openInTab"), "", fn() { open({ ..in_, path: full }, false) })
      item(@sf.t("web-pages.files.openBeside"), "", fn() { open({ ..in_, path: full }, true) })
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
    item(@sf.t("web-pages.drive.rename"), "edit", fn() { b.start_rename(c, src, in_.path, e) })
    out.push(
      Some(
        @sf.menu_item_of(
          @sf.t(if st.trash { "web-pages.drive.toTrash" } else { "web-pages.drive.delete" }),
          icon="trash",
          danger=true,
          fn() { remove_entries(c, src, f.key, st, [(in_, e)]) },
        ),
      ),
    )
  }
  out
}

///|
/// What can be done to the folder (FolderView's actions), for the files' page's bar while it is in front: its three
/// ways, the preview, put up and a new folder (who may write), read again (turning while it is read), 收藏 (lit while
/// it is kept), pin (for one who browses every folder: lit while pinned), its ⋯ (复制路径, 前往文件夹, 管理).
pub fn folder_actions(c : @ui.Ctx, src : Source, f : FolderOf) -> Unit {
  let at = f.at
  let root = at.root.unwrap_or("")
  let st = f.st
  let view = drive_view(src, "page")
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
    // a new folder, uploading; the way it is shown last, the other two ways offered there)
    @sf.tool_of(
      "view",
      fn() { view_switch(c, "files/view", view, fn(v) { set_drive_view(src, "page", v) }) },
      drop=folder_drop_view,
      instead=[("columns", "view-columns"), ("tree", "view-tree"), ("list", "list")]
        .filter(fn(w) { w.0 != view })
        .map(fn(w) { @sf.menu_item_of(@sf.t("web-pages.drive.view." + w.0), fn() { set_drive_view(src, "page", w.0) }, icon=w.1) }),
    ),
    @sf.tool_button(
      c,
      "files/preview",
      if previewing { "panel-close" } else { "panel-open" },
      @sf.t(if previewing { "web-pages.files.hidePreview" } else { "web-pages.files.showPreview" }),
      on_press=fn() { set_preview_shown(src, "page", !previewing) },
      drop=folder_drop_preview,
      lit?=on(previewing),
    ),
  ]
  if f.rights.write {
    tools.push(@sf.tool_button(c, "files/upload", "upload", @sf.t("web-pages.drive.upload"), on_press=fn() { dv_upload(c, at) }, drop=folder_drop_upload))
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
  let more : Array[@sf.MenuItem?] = [Some(@sf.menu_item_of(@sf.t("web-pages.drive.copyPath"), icon="copy", fn() { copy_path(c, here) }))]
  match f.go_to {
    Some(g) => more.push(Some(@sf.menu_item_of(@sf.t("web-pages.files.goTo"), icon="search", g)))
    None => ()
  }
  match f.manage {
    Some(m) if f.rights.manage || st.anywhere =>
      more.push(Some(@sf.menu_item_of(@sf.t("web-pages.drive.manage"), icon="folder", m)))
    _ => ()
  }
  @sf.tools_row(c, "files/more", tools, more~, label=@sf.t("web-main.menu.more"), style=actions_row)
}

///|
/// The order a folder's actions go into its ⋯ in, short of room (refreshing first, the way it is shown last).
let folder_drop_refresh : Int = 1

///|
let folder_drop_pin : Int = 2

///|
let folder_drop_favorite : Int = 3

///|
let folder_drop_preview : Int = 4

///|
let folder_drop_mkdir : Int = 5

///|
let folder_drop_upload : Int = 6

///|
let folder_drop_view : Int = 7

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
  let menu_key = key + "/menu"
  let busy = entry_busy(src, at, e.name)
  let live = !busy && !row.renaming
  if live {
    c.cursor(id, Hand)
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
  let finger = @ui.pointing() is Finger
  if live {
    let asked = c.menu_asked(id)
    match asked {
      Some((x, y)) => {
        held.row_frame = c.frame_number()
        (row.menu)()
        @sf.menu_open_here(menu_key + "/at", x, y)
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
  let (px, py, _) = c.pointer()
  let over = match c.rect_of(id) {
    Some((x, y, w, h)) => px >= x && px < x + w && py >= y && py < y + h
    None => false
  }
  let open = @sf.menu_is_open(menu_key) || @sf.menu_is_open(menu_key + "/at")
  let ground = if lit is Some(_) {
    entry_drop
  } else if row.chosen {
    entry_chosen
  } else if along || open || over {
    entry_along
  } else {
    entry_plain
  }
  let tree = depth is Some(_)
  let indent = match depth {
    Some(d) => tree_step * d.to_double()
    None => tree_none
  }
  let inner = if compact && tree {
    row_tree_compact
  } else if tree {
    row_tree
  } else if compact {
    row_compact
  } else {
    row_style
  }
  c.box(style=entry_room, fn() {
    let box = c.box(style=if busy { ground.then(entry_busy_look) } else { ground }, id~, fn() {
      c.box(style=inner, fn() {
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
        @sf.icon(c, dv_kind_icon(if e.dir { "folder" } else { e.kind }), size=if compact { kind_compact } else { kind_icon }, color=t.p.muted)
        |> ignore
        if row.renaming {
          name_field(c, key + "/name", s.b, e, row)
        } else if compact {
          c.text(e.name, style=row_name) |> ignore
        } else {
          // (short of room, the name keeps a few words: the size goes first, then the time, as the heads do)
          c.box(style=name_cell, fn() { c.text(e.name, style=row_name) |> ignore }) |> ignore
        }
        let size = if e.dir || column { "" } else { e.size_text }
        if compact {
          if size != "" {
            c.text(size, style=row_meta) |> ignore
          }
          c.box(style=end_compact, fn() {  }) |> ignore
        } else {
          c.box(style=size_cell, drop=list_drop_size, fn() { c.text(size, style=row_meta) |> ignore }) |> ignore
          c.box(style=time_cell, drop=list_drop_time, fn() { c.text(e.time_text, style=row_meta) |> ignore }) |> ignore
          c.box(style=end_cell, fn() {  }) |> ignore
        }
      })
      |> ignore
      // at its end: › on the folder open beside (columns), the ⋯ on hover, always to a finger (Drive.css.ts more,
      // next: `hover: none`; a spinner while something is under way)
      c.layer(fn() {
        c.box(style=more_place, fn() {
          if busy {
            @sf.spinner(c) |> ignore
          } else if over || open || finger {
            @sf.menu_of(
              c,
              menu_key,
              if open { (row.items)() } else { [] },
              label=@sf.t("web-main.menu.more"),
              size=if compact { more_compact } else { more_size },
            )
            |> ignore
          } else if column && e.dir && along {
            c.box(style=next_box, fn() {
              @sf.icon(c, "chevron-right", size=disclosure_icon, color=t.p.muted) |> ignore
            })
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    })
    c.semantics(box, Button, id~, label=e.name, selected=row.chosen, expanded?=if tree && e.dir { Some(expanded == Some(true)) } else { None })
  })
  |> ignore
  // its menu on a right click, at the pointer
  if @sf.menu_is_open(menu_key + "/at") {
    @sf.context_items(c, menu_key + "/at", (row.items)()) |> ignore
  }
}

///|
/// A name changed in place (NameField): the name but its extension picked; ⏎ or leaving it keeps it, esc leaves it as
/// it was.
fn name_field(c : @ui.Ctx, key : String, b : Browse, e : DvEntry, row : RowProps) -> Unit {
  let t = @sf.theme()
  if held.naming != key {
    held.naming = key
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
      held.naming = ""
      (row.rename)(None)
    } else {
      match r.submitted {
        Some(words) => {
          held.naming = ""
          (row.rename)(Some(words))
        }
        None =>
          if r.focused {
            held.naming_had = true
          } else if held.naming_had {
            // left: kept
            held.naming = ""
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
    c.cursor(id, Hand)
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
/// name taken there (替换, 保留两者), or why it failed (重试); × lets it go.
pub fn upload_row(c : @ui.Ctx, src : Source, u : DvUpload, entries : Array[DvEntry]) -> Unit {
  let t = @sf.theme()
  let k = "files/up/\{u.serial}"
  c.box(style=entry_room, fn() {
    c.box(style=entry_plain, fn() {
      c.box(style=row_style, fn() {
        @sf.icon(c, "upload", size=kind_icon, color=t.p.muted) |> ignore
        // (its name, and beside it how far, what is asked or why it failed: under the name where the row has not the room
        // for both, as the phone's row has it; its name keeps a few words, what is asked its two answers alone)
        c.box(style=upload_words, flow=true, line_gap=0.0, fn() {
          c.box(style=upload_name, fn() { c.text(u.name, style=row_name) |> ignore }) |> ignore
          match u.state {
            "taken" =>
              c.box(style=upload_ask, fn() {
                c.box(drop=upload_drop_note, fn() { c.text(@sf.t("web-pages.drive.taken"), style=row_meta) |> ignore })
                |> ignore
                if @sf.button(c, @sf.t("web-pages.drive.replace"), key=k + "/replace", tone=Ghost) {
                  u.replace = true
                  u.state = "waiting"
                  dv_pump(src)
                }
                if @sf.button(c, @sf.t("web-pages.drive.keepBoth"), key=k + "/both", tone=Ghost) {
                  let others = ups.uploads.filter(fn(x) { x.serial != u.serial && x.dir == u.dir })
                  u.name = dv_free_name(u.name, entries.map(fn(e) { e.name }) + others.map(fn(x) { x.name }))
                  u.state = "waiting"
                  dv_pump(src)
                }
              })
              |> ignore
            "failed" =>
              c.box(style=upload_why, fn() {
                c.text(@sf.t("web-pages.drive.uploadFailed", args=[("error", u.error)]), style=upload_failed) |> ignore
              })
              |> ignore
            _ => {
              let size = u.bytes.length()
              let part = if size > 0 { dmin(u.sent.to_double() / size.to_double(), all) } else { none }
              let rest = all - part
              c.box(style=progress_cell, keep=true, fn() {
                c.box(style=progress_track, fn() {
                  c.box(style=progress_done.then(@ui.style(w=Grow(part))), fn() {  }) |> ignore
                  c.box(style=@ui.style(w=Grow(rest)), fn() {  }) |> ignore
                })
                |> ignore
                // (short of room, how much has gone up leaves whole, its bar kept)
                c.box(drop=upload_drop_sent, fn() {
                  c.text(
                    @sf.t("web-pages.drive.uploading", args=[("sent", @sf.file_size(u.sent.to_double())), ("size", @sf.file_size(size.to_double()))]),
                    style=row_meta,
                  )
                  |> ignore
                })
                |> ignore
              })
              |> ignore
            }
          }
        })
        |> ignore
        c.box(style=end_cell, fn() {  }) |> ignore
      })
      |> ignore
      c.layer(fn() {
        c.box(style=more_place, fn() {
          if u.state == "failed" && @sf.icon_button(c, "retry", key=k + "/retry", label=@sf.t("web-pages.drive.retry")) {
            u.state = "waiting"
            u.error = ""
            u.sent = 0
            dv_pump(src)
          }
          if @sf.icon_button(c, "close", key=k + "/cancel", label=@sf.t("common.cancel")) {
            ups.uploads.retain(fn(x) { x.serial != u.serial })
            if u.state == "going" {
              ups.pumping = false
              dv_pump(src)
            }
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
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
}

///|
/// The preview's width beside the list (DrivePane.css.ts pane).
pub let pane_w : Double = 300.0

///|
/// A row's marks (KindIcon 20; compact 18), a tree's disclosure's chevron (12), the ⋯ (32; compact 24), the empty
/// folder's mark (36), what is dropped's (22), the heads' chevron (10).
let kind_icon : Double = 20.0

///|
let kind_compact : Double = 18.0

///|
let disclosure_icon : Double = 12.0

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
/// The entries (list): rows 2 apart, its corner the card's.
// kept across runs: a value (no field of it changes)
let list_box : @ui.Style = @ui.style(w=@sf.grow, min_w=S56, h=Full, radius=Xl2, clip=true)

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
/// A row's ground (entry): the field's corner; the list's under the pointer, the selected's chosen, the accent's
/// ringed where a drop goes in; faded while something is under way on it.
// kept across runs: a value (no field of it changes)
let entry_plain : @ui.Style = @ui.css("w=Full radius=Xl")

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
/// A row (row): 44 high at least, 8 by 12 in, its parts 12 apart: its mark (20), its name, its size (96) and time
/// (104) at their end, room for its ⋯ (36).
// kept across runs: a value (no field of it changes)
let row_style : @ui.Style = @ui.css("row w=Full min_h=S11 px=S3 py=S2 gap=S3 align=ACenter")

///|
/// A chat's 文件 tab's and a column's (compact): 36 high, 6 by 10 in, 10 apart, the size alone, room for its ⋯ (28).
// kept across runs: a value (no field of it changes)
let row_compact : @ui.Style = @ui.css("row w=Full min_h=S9 px=S2_5 py=S1_5 gap=S2_5 align=ACenter")

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
// kept across runs: a value (no field of it changes)
let row_name : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let row_meta : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

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
let head_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let head_words_on : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

///|
/// Going up: how far it has got (a 2 high bar on the words at 10%, filled in the accent), its size.
// kept across runs: a value (no field of it changes)
let progress_cell : @ui.Style = @ui.style(row=true, w=@sf.grow, max_w=Fixed(progress_w), gap=S2_5, align=ACenter)

///|
/// The size and time columns' (96 and 104 and their gap).
let progress_w : Double = 212.0

///|
// kept across runs: a value (no field of it changes)
let progress_track : @ui.Style = @ui.style(row=true, w=@sf.grow, min_w=S12, h=S0_5, radius=Sm, bg=A(Fg, O10), clip=true)

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
let upload_failed : @ui.TextStyle = @ui.text_style(size=Xs, color=Danger, wrap=false, w=Cut)

///|
/// Why the folder could not be read, and 重试 (problem: 12 in, 10 apart).
// kept across runs: a value (no field of it changes)
let problem_box : @ui.Style = @ui.css("w=Full p=S3 gap=S2_5 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let problem_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Danger, w=Full)

///|
/// Nothing in it (empty): in the middle, 56 by 24 in, 12 apart, muted.
// kept across runs: a value (no field of it changes)
let empty_box : @ui.Style = @ui.css("w=Full pt=S14 pb=S14 px=S6 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let empty_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, center=true)

///|
/// What is held over the list (drop): over all of it, its words and mark in the middle, the page's ground at 82%
/// under them, ringed in the accent.
// kept across runs: a value (no field of it changes)
let drop_box : @ui.Style = @ui.css(
  #|w=Full h=Full gap=S2 align=ACenter justify=JCenter radius=Xl2 bg=A(Bg,O80) border=B2 border_color=A(Accent,O60)
)

///|
// kept across runs: a value (no field of it changes)
let drop_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false)

///|
/// What is done to the folder (actions): 6 apart.
// kept across runs: a value (no field of it changes)
let actions_row : @ui.Style = @ui.css("row gap=S1_5 align=ACenter justify=JEnd")

///|
/// A folder's page's head (Drive.tsx FolderView's pageHead): its trail (its station's button, then the way down to it:
/// its root, then each folder above it), its name (h1), its station and what it holds. `split`: a side of a split tab,
/// in less; `front_it`: what is pressed in a side puts it in front first.
pub fn folder_head(c : @ui.Ctx, src : Source, f : FolderOf, split : Bool, front_it : () -> Unit) -> Unit {
  let t = @sf.theme()
  let at = f.at
  let root = at.root.unwrap_or("")
  let stations = dv_stations(src, f.ws).0.unwrap_or([])
  let topic = (src.topic)("drive", { "station": Json::string(at.station), "root": Json::string(root), "path": Json::string(at.path) })
  let (name, _) = pane_parts(at, stations)
  c.box(style=if split { head_half } else { head_one }, fn() {
    c.box(style=head_trail, fn() {
      station_switch(c, src, f, front_it)
      let parts : Array[String] = if at.path == "" { [] } else { at.path.split("/").map(fn(p) { p.to_string() }).collect() }
      let (root_name, _) = pane_parts({ ..at, path: "" }, stations)
      let crumbs : Array[(String, String)] = if at.path == "" { [] } else { [(root_name, "")] }
      let mut so_far = ""
      for i in 0..<(parts.length() - 1) {
        so_far = dv_join(so_far, parts[i])
        crumbs.push((parts[i], so_far))
      }
      for x in crumbs {
        let (word, path) = x
        @sf.icon(c, "chevron-right", size=trail_chevron, color=t.p.subtle) |> ignore
        let cid = c.id("files/crumb/" + at.station + "/" + root + "/" + path)
        c.cursor(cid, Hand)
        if c.clicked(cid) {
          front_it()
          (f.go)({ station: at.station, root: Some(root), path }, false)
        }
        c.box(style=head_crumb, id=cid, fn() { c.text(word, style=head_meta) |> ignore }) |> ignore
      }
    })
    |> ignore
    c.text(name, style=head_title) |> ignore
    match text(topic.value, "countText") {
      "" => ()
      count => c.text(f.st.name + " · " + count, style=head_meta) |> ignore
    }
  })
  |> ignore
}

///|
/// The trail's chevrons (16).
let trail_chevron : Double = 16.0

///|
/// The head (pageHead): 12 over and under, 6 between its lines; in from its side as the page is (40; split, 24).
// kept across runs: a value (no field of it changes)
let head_one : @ui.Style = @ui.css("w=Full px=S10 pt=S3 pb=S3 gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let head_half : @ui.Style = @ui.css("w=Full px=S6 pt=S3 pb=S3 gap=S1_5")

///|
/// Its trail (crumbs): 4 between.
// kept across runs: a value (no field of it changes)
let head_trail : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let head_crumb : @ui.Style = @ui.css("px=S0_5 radius=Sm hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let head_meta : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// Its name (h1): 22, 600.
// kept across runs: a value (no field of it changes)
let head_title : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Semibold, color=Fg, wrap=false)
