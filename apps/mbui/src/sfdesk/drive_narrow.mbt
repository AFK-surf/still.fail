// A station's drive laid out narrow, as the web's narrow app has it (ember web/src/mobile/Drive.tsx RootsPage,
// RootRow, FolderPage, Crumbs, EntryRow, UploadRow, Empty; Drive.css.ts m*): the files' page and a folder's in a box
// narrower than @sf.page_narrow_most, in whichever frame (the phone's stack, a tablet's pane), with either hand.
// The bar: back where the frame has somewhere to go back to, the folder's name, read again, ＋ (put files up, a new
// folder) and ⋯ (the order, hidden files, its path, 收藏, pin, 管理). Under it the way down from its root, what it holds
// in a line, the files going up, its entries on a card: pressed, one opens as its entry says (a folder gone into, a
// text read, a video played, a picture or code previewed, the rest saved); a long press or a right click gives what
// can be done to it (the files' page's own: drive.mbt row_items). What is chosen, the order and the names a change
// gives are the core's, as the wide page's are (browse.mbt).

///|
/// What a narrow page is given of its frame and what it opens: the frame's (back's words, the room over and under),
/// back (the frame's own way), and a folder shown in place of this one (the frame's: pushed on a stack, the side in
/// front of the files' page).
pub(all) struct NarrowOf {
  frame : PageFrame
  back : () -> Unit
}

///|
/// The narrow app's frame where nothing is said of it (a pane beside a list: no back, no room over or under).
pub fn narrow_bare() -> NarrowOf {
  { frame: { back: None, top: 0.0, foot: 0.0, named: false }, back: fn() {  } }
}

///|
/// What a narrow folder's list holds, in order.
priv enum NarrowItem {
  NCrumbs
  NFailed(String)
  NStale(String)
  NReading
  NCount(String)
  NUp(DvUpload, Bool, Bool)
  NEmpty
  NRow(DvEntry, Bool, Bool)
  NFoot
}

///|
/// The folder `f.at` laid out narrow (FolderPage).
pub fn folder_narrow(c : @ui.Ctx, src : Source, f : FolderOf, n : NarrowOf) -> Unit {
  let t = @sf.theme()
  let at = f.at
  let root = at.root.unwrap_or("")
  let st = f.st
  let write = f.rights.write
  let (value, error) = drive_folder(src, at.station, root, at.path)
  let entries = items(value, "entries").map(dv_entry)
  if f.front {
    keep_files_page(f.ws, at)
  }
  // the files picked to go up
  dv_take_picked(src, at, entries)
  let b_ref : Ref[Browse?] = Ref(None)
  let open_row = fn(in_ : DriveAt, e : DvEntry) {
    let near = match b_ref.val {
      Some(b) => b.arranged(in_.path, entries).unwrap_or([e])
      None => [e]
    }
    open_entry(c, src, "page", in_, e, near, fn(to) { (f.go)(to, false) })
  }
  let b = browse(c, src, f.key, "page", "list", at, write, {
    open: open_row,
    preview: open_row,
    go: fn(p, replace) { (f.go)({ ..at, path: p }, replace) },
    remove: fn(items) { remove_entries(c, src, st, items) },
  })
  b_ref.val = Some(b)
  let name = folder_name(st, at)
  let shown = b.arranged(at.path, entries)
  let ups_here = ups.uploads.filter(fn(u) { u.station == at.station && u.root == root && u.dir == at.path })
  let list : Array[NarrowItem] = []
  if at.path != "" {
    list.push(NCrumbs)
  }
  match (error, value) {
    (Some(e), Some(_)) => list.push(NStale(e))
    (Some(e), None) => list.push(NFailed(e))
    (None, None) => list.push(NReading)
    _ => ()
  }
  match (value, shown) {
    (Some(_), Some(rows)) => {
      let count = text(value, "countText") +
        (if flag(value, "truncated") { " · " + @sf.t("web-pages.drive.truncated") } else { "" })
      list.push(NCount(count))
      for i, u in ups_here {
        list.push(NUp(u, i == 0, i == ups_here.length() - 1))
      }
      if rows.length() == 0 && ups_here.length() == 0 {
        list.push(NEmpty)
      }
      for i, e in rows {
        list.push(NRow(e, i == 0, i == rows.length() - 1))
      }
    }
    (Some(_), None) => list.push(NReading)
    _ => ()
  }
  list.push(NFoot)
  c.box(style=narrow_page, fn() {
    if narrow_bar(c, n, name, fn() { narrow_folder_actions(c, src, f, b) }) {
      (n.back)()
    }
    c.list("files/narrow/" + f.key + "/" + at.station + "/" + root + "/" + at.path, list.length(), narrow_row_est, fn(i) {
      match list[i] {
        NCrumbs => narrow_crumbs(c, f)
        NStale(e) =>
          narrow_retry(c, @sf.t("android-misc.drive.stale", args=[("error", e)]), narrow_stale_words, fn() {
            refresh_folder(c, src, at)
          })
        NFailed(e) => narrow_retry(c, e, narrow_failed_words, fn() { refresh_folder(c, src, at) })
        NReading => @sf.waiting(c, count=7)
        NCount(s) => c.box(style=narrow_count_box, fn() { c.text(s, style=narrow_count_words) |> ignore }) |> ignore
        NUp(u, first, last) => card_row(c, first, last, 0, fn() { narrow_upload_row(c, src, u) })
        NEmpty =>
          narrow_empty(c, @sf.t("web-pages.drive.emptyFolder"), if write {
            Some((@sf.t("web-pages.drive.upload"), fn() { dv_upload(c, at) }))
          } else {
            None
          })
        NRow(e, first, last) => narrow_entry_row(c, src, f, b, e, first, last)
        NFoot => c.box(style=@ui.style(w=Full, h=Fixed(narrow_list_foot + n.frame.foot)), fn() {  }) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
  ignore(t)
}

///|
/// The narrow bar (NavBar): back where the frame says (its words), the title in the middle, what it does at its end;
/// true on the frame back was pressed.
fn narrow_bar(c : @ui.Ctx, n : NarrowOf, title : String, trailing : () -> Unit) -> Bool {
  @sf.nav_bar(
    c,
    "files/narrow/back",
    n.frame.back.unwrap_or(""),
    title,
    trailing~,
    back_max=if c.width / 2.0 - narrow_back_room > narrow_back_least {
      c.width / 2.0 - narrow_back_room
    } else {
      narrow_back_least
    },
    bg=@sf.theme().p.bg,
    top=n.frame.top,
  )
}

///|
/// A round button of the bar (NavButton): 34 across, its icon 18 (`size`), what it is said to be.
fn narrow_bar_button(c : @ui.Ctx, key : String, icon : String, label : String, size? : Double = narrow_bar_icon) -> Bool {
  @sf.icon_button(c, icon, key~, size=narrow_bar_button_w, icon_size=size, round=true, label~)
}

///|
/// What the folder's bar does (FolderPage's trailing): read again (the spinner in its place while it is read), ＋ for
/// one who may write (put files up, a new folder), ⋯ (the order and hidden files, as the wide list's own menu; its
/// path; 收藏; pin, for one who browses every folder; 管理).
fn narrow_folder_actions(c : @ui.Ctx, src : Source, f : FolderOf, b : Browse) -> Unit {
  let at = f.at
  let root = at.root.unwrap_or("")
  let st = f.st
  c.box(style=narrow_actions_row, fn() {
    if refreshing(at) {
      c.box(style=narrow_bar_spin, fn() { @sf.spinner(c) |> ignore }) |> ignore
    } else if narrow_bar_button(c, "files/narrow/refresh", "refresh", @sf.t("web-pages.drive.refresh")) {
      refresh_folder(c, src, at)
    }
    if f.rights.write &&
      narrow_bar_button(c, "files/narrow/add", "plus", @sf.t("web-pages.drive.add"), size=narrow_bar_plus) {
      @sf.menu(
        [
          Some(@sf.menu_item_of(@sf.t("web-pages.drive.upload"), icon="upload", fn() { dv_upload(c, at) })),
          Some(@sf.menu_item_of(@sf.t("web-pages.drive.mkdir"), icon="folder-plus", fn() { ask_new_folder(c, src, at) })),
        ],
        from=Of(c.id("files/narrow/add")),
        title=folder_name(st, at),
        along=End,
      )
    }
    if narrow_bar_button(c, "files/narrow/more", "more", @sf.t("web-main.menu.more")) {
      let a = b.arrangement()
      let here = dv_absolute(root, at.path)
      let name = folder_name(st, at)
      let kept = favorite_has(favorites(src, f.ws), at.station, root, at.path)
      let pinned = st.roots.iter().any(fn(r) { r.path == here })
      let items : Array[@sf.MenuItem?] = []
      for by in ["name", "time", "size", "kind"] {
        items.push(Some(@sf.menu_item_of(@sf.t("web-pages.drive.sortBy." + by), icon=if a.by == by { "check" } else { "" }, fn() {
          b.arrange_as(c, src, by~, down=false)
        })))
      }
      items.push(Some(@sf.menu_item_of(@sf.t(if a.hidden { "web-pages.drive.hideHidden" } else { "web-pages.drive.showHidden" }), fn() {
        b.arrange_as(c, src, hidden=!a.hidden)
      })))
      items.push(None)
      items.push(Some(@sf.menu_item_of(@sf.t("web-pages.drive.copyPath"), icon="copy", fn() { copy_path(c, here) })))
      items.push(Some(@sf.menu_item_of(@sf.t(if kept { "web-pages.files.unfavorite" } else { "web-pages.files.favorite" }, args=[("name", name)]), icon="star", fn() {
        if kept {
          favorite_remove(src, f.ws, at.station, root, at.path)
        } else {
          favorite_add(src, f.ws, { station: at.station, root, path: at.path, name })
        }
      })))
      if st.anywhere {
        items.push(Some(@sf.menu_item_of(@sf.t(if pinned { "web-pages.drive.unpin" } else { "web-pages.drive.pin" }), icon="pin", fn() {
          pin_folder(c, src, st, here, !pinned)
        })))
      }
      match f.manage {
        Some(m) if f.rights.manage || st.anywhere =>
          items.push(Some(@sf.menu_item_of(@sf.t("web-pages.drive.manage"), icon="folder", m)))
        _ => ()
      }
      @sf.menu(items, from=Of(c.id("files/narrow/more")), along=End)
    }
  })
  |> ignore
}

///|
/// A new folder in `at`, named as it is asked (newFolder: 新建文件夹, its name typed; refused in the core's words where
/// it may not have it).
pub fn ask_new_folder(c : @ui.Ctx, src : Source, at : DriveAt) -> Unit {
  let what = @sf.t("web-pages.drive.mkdirWhat")
  @sf.ask(
    @sf.t("web-pages.drive.mkdir"),
    @sf.t("web-pages.drive.make"),
    fn(name) {
      dv_check_name(src, name, fn(problem) {
        match problem {
          Some(p) => say(c, @sf.t("web-main.act.failed", args=[("what", what), ("error", p)]))
          None =>
            (src.call)(
              "drive.mkdir",
              {
                "station": Json::string(at.station),
                "root": Json::string(at.root.unwrap_or("")),
                "path": Json::string(dv_join(at.path, name)),
              },
              act_done(c, what),
            )
        }
      })
    },
    placeholder=@sf.t("web-pages.drive.mkdirPlaceholder"),
  )
}

///|
/// A name changed as it is asked (EntrySheet's 重命名: its name in the field), the folder's row chosen under it once
/// the station has it.
pub fn ask_rename(c : @ui.Ctx, src : Source, b : Browse, in_ : DriveAt, e : DvEntry) -> Unit {
  @sf.ask(
    @sf.t("web-pages.drive.renameTitle"),
    @sf.t("common.save"),
    fn(name) { b.rename(c, src, in_.path, e, Some(name)) },
    value=e.name,
    placeholder=e.name,
  )
}

///|
/// Where the folder is under its root (Crumbs): the root, then each folder down to this one, each but the last a way
/// to it; scrolled across when long, its end in view.
fn narrow_crumbs(c : @ui.Ctx, f : FolderOf) -> Unit {
  let t = @sf.theme()
  let at = f.at
  let root = at.root.unwrap_or("")
  let parts = at.path.split("/").filter(fn(p) { p != "" }).map(fn(p) { p.to_owned() }).to_array()
  let levels : Array[(String, String)] = [(folder_name(f.st, { ..at, path: "" }), "")]
  let mut so_far = ""
  for p in parts {
    so_far = dv_join(so_far, p)
    levels.push((p, so_far))
  }
  c.sideways("files/narrow/crumbs/" + at.station + "/" + root, to_end="/" + at.path, fn() {
    c.box(style=narrow_crumbs_row, fn() {
      for i, l in levels {
        let (label, to) = l
        if i > 0 {
          @sf.icon(c, "chevron-right", size=narrow_crumb_chevron, color=t.p.subtle) |> ignore
        }
        let last = i == levels.length() - 1
        let id = c.id("files/narrow/crumb/\{i}")
        if !last && c.clicked(id) {
          (f.go)({ ..at, path: to }, false)
        }
        c.box(style=narrow_crumb, id=if last { 0 } else { id }, fn() {
          c.text(label, style=if last { narrow_crumb_here } else { narrow_crumb_words }) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// What could not be read, and 重试.
fn narrow_retry(c : @ui.Ctx, words : String, look : @ui.TextStyle, retry : () -> Unit) -> Unit {
  c.box(style=narrow_problem, fn() {
    c.box(style=narrow_problem_words, fn() { c.text(words, style=look) |> ignore }) |> ignore
    let id = c.id("files/narrow/retry")
    if c.clicked(id) {
      retry()
    }
    c.box(style=narrow_link, id~, fn() { c.text(@sf.t("web-pages.drive.retry"), style=narrow_link_words) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// Nothing here (Empty): a folder's mark (40), why, and what can be done about it (`action`: its words, what it does).
fn narrow_empty(c : @ui.Ctx, words : String, action : (String, () -> Unit)?) -> Unit {
  let t = @sf.theme()
  c.box(style=narrow_empty_box, fn() {
    @sf.icon(c, "folder", size=narrow_empty_icon, color=t.p.subtle) |> ignore
    c.text(words, style=narrow_empty_words) |> ignore
    match action {
      Some((label, go)) => if @sf.button(c, label, key="files/narrow/empty", tone=Ghost) { go() }
      None => ()
    }
  })
  |> ignore
}

///|
/// An entry (EntryRow): its kind's mark, its name, its size and time (a folder's time); a spinner while something is
/// under way on it, a folder's chevron. Pressed, it opens; held (a finger) or right clicked (a mouse), what can be done
/// to it, at the press.
fn narrow_entry_row(c : @ui.Ctx, src : Source, f : FolderOf, b : Browse, e : DvEntry, first : Bool, last : Bool) -> Unit {
  let t = @sf.theme()
  let at = f.at
  let path = dv_join(at.path, e.name)
  let busy = entry_busy(src, at, e.name)
  let id = c.id("files/narrow/row/" + at.station + "/" + at.root.unwrap_or("") + "/" + path)
  if !busy {
    c.cursor(id, Hand)
    match c.menu_asked(id) {
      Some((x, y)) => {
        b.choose(c, src, at.path, e.name)
        @sf.menu(row_items(c, src, f, b, at, e, favorites(src, f.ws), narrow=true), from=@sf.at_point(x, y), title=e.name)
      }
      None =>
        if c.clicked(id) {
          let near = b.arranged(at.path, items(drive_folder(src, at.station, at.root.unwrap_or(""), at.path).0, "entries").map(dv_entry)).unwrap_or([e])
          open_entry(c, src, "page", at, e, near, fn(to) { (f.go)(to, false) })
        }
    }
  }
  card_row(c, first, last, if busy { 0 } else { id }, fn() {
    let row = c.box(style=narrow_entry, fn() {
      @sf.icon(c, dv_kind_icon(if e.dir { "folder" } else { e.kind }), size=narrow_kind_icon, color=t.p.muted) |> ignore
      c.box(style=narrow_entry_words, fn() {
        c.text(e.name, style=narrow_entry_name) |> ignore
        let line = if e.dir { e.time_text } else { dv_words([e.size_text, e.time_text], " · ") }
        if line != "" {
          c.text(line, style=narrow_entry_meta) |> ignore
        }
      })
      |> ignore
      // how far it has come while the core downloads it (a folder's: its zip's, 0 while the station zips it)
      let fetching = match download_of_drive(src, at.station, at.root.unwrap_or(""), path) {
        Some(d) if flag(Some(d), "active") => Some((number(Some(d), "progress") * 100.0).floor().to_int())
        _ => None
      }
      if busy {
        @sf.spinner(c, size=narrow_spin) |> ignore
      } else if fetching is Some(p) {
        download_chip(c, at.station + "/" + path, p)
      } else if e.kind == "text" || e.kind == "markdown" {
        read_share(c, src, at.station, at.root.unwrap_or(""), path)
      } else if e.dir {
        @sf.icon(c, "chevron-right", size=narrow_chevron_icon, color=t.p.subtle) |> ignore
      }
    })
    c.semantics(row, Button, id~, label=e.name)
  })
}

///|
/// How far a text has been read on this device, once opened (the core's `drivePlace`): its share, 读完 at its end.
fn read_share(c : @ui.Ctx, src : Source, station : String, root : String, path : String) -> Unit {
  let place = (src.topic)("drivePlace", { "station": Json::string(station), "root": Json::string(root), "path": Json::string(path) }).value
  let of = number(place, "of")
  if of <= 0.0 {
    return
  }
  let at = number(place, "at") / of
  let share = if at < 0.0 { 0.0 } else if at > 1.0 { 1.0 } else { at }
  if share < read_least {
    return
  }
  c.text(if share >= read_whole { @sf.t("android-misc.drive.read.done") } else { "\{(share * 100.0).to_int()}%" }, style=narrow_entry_meta)
  |> ignore
}

///|
/// Read so little it says nothing (1%), read to its end (99.5%).
let read_least : Double = 0.01

///|
let read_whole : Double = 0.995

///|
/// How far a file of the drive has come while it is downloaded (FillChip's `progress`): a rounded box, its ground filled
/// in the accent from the left as it comes (moving to each new share over 500 ms), n% on it.
fn download_chip(c : @ui.Ctx, key : String, percent : Int) -> Unit {
  let p = if percent < 0 { 0 } else if percent > 100 { 100 } else { percent }
  let drawn = @motion.animate(c, "files/narrow/fetch/" + key, p.to_double(), spec=chip_fill)
  c.box(style=chip_box, fn() {
    if drawn > 0.0 {
      c.layer(fn() {
        c.box(style=chip_track, fn() {
          c.box(style=chip_done.then(@ui.style(w=Grow(drawn))), fn() {  }) |> ignore
          let rest = chip_whole - drawn
          if rest > 0.0 {
            c.box(style=@ui.style(h=Full, w=Grow(rest)), fn() {  }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    }
    c.box(style=chip_words_box, fn() { c.text("\{p}%", style=chip_words) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// How the chip fills (500 ms).
// kept across runs: a value (no field of it changes)
let chip_fill : @motion.Spec = @motion.tween(chip_fill_ms)

///|
let chip_fill_ms : Double = 500.0

///|
/// The whole of the chip, in its percent.
let chip_whole : Double = 100.0

///|
/// The chip: 20 high, on the neutral ground, its fill the accent at 20%, its words 11 bold.
// kept across runs: a value (no field of it changes)
let chip_box : @ui.Style = @ui.css("h=S5 radius=Lg bg=Neutral clip justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let chip_track : @ui.Style = @ui.css("row w=Full h=Full")

///|
// kept across runs: a value (no field of it changes)
let chip_done : @ui.Style = @ui.css("h=Full bg=A(Accent,O20)")

///|
// kept across runs: a value (no field of it changes)
let chip_words_box : @ui.Style = @ui.css("row px=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let chip_words : @ui.TextStyle = @ui.text_style(size=Xs2, weight=Semibold, color=Fg, wrap=false)

///|
/// A file going up (UploadRow): its name, how far it has got (a thin bar, sent of its size); its name taken there
/// (替换, 保留两者), or why it failed (重试); × lets it go.
fn narrow_upload_row(c : @ui.Ctx, src : Source, u : DvUpload) -> Unit {
  let t = @sf.theme()
  let k = "files/narrow/up/\{u.serial}"
  c.box(style=narrow_upload, fn() {
    @sf.icon(c, "upload", size=narrow_kind_icon, color=t.p.muted) |> ignore
    c.box(style=narrow_entry_words, fn() {
      c.text(u.name, style=narrow_entry_name) |> ignore
      match u.state {
        "taken" =>
          c.box(style=narrow_upload_ask, fn() {
            c.text(@sf.t("web-pages.drive.taken"), style=narrow_entry_meta.then(@ui.text_style(w=Cut))) |> ignore
            let rid = c.id(k + "/replace")
            let bid = c.id(k + "/both")
            if c.clicked(rid) {
              u.replace = true
              u.state = "waiting"
              dv_pump(src)
            }
            if c.clicked(bid) {
              dv_keep_both(src, u)
            }
            c.box(style=narrow_answer, id=rid, fn() { c.text(@sf.t("web-pages.drive.replace"), style=narrow_answer_words) |> ignore })
            |> ignore
            c.box(style=narrow_answer, id=bid, fn() { c.text(@sf.t("web-pages.drive.keepBoth"), style=narrow_answer_words) |> ignore })
            |> ignore
          })
          |> ignore
        "failed" =>
          c.text(@sf.t("web-pages.drive.uploadFailed", args=[("error", u.error)]), style=narrow_upload_failed) |> ignore
        _ => {
          let size = u.bytes.length()
          c.text(
            @sf.t("web-pages.drive.uploading", args=[("sent", @sf.file_size(u.sent.to_double())), ("size", @sf.file_size(size.to_double()))]),
            style=narrow_entry_meta,
          )
          |> ignore
          c.box(style=narrow_progress, fn() {
            @sf.progress(c, if size > 0 { Some(u.sent.to_double() / size.to_double()) } else { None })
          })
          |> ignore
        }
      }
    })
    |> ignore
    if u.state == "failed" &&
      @sf.icon_button(c, "retry", key=k + "/retry", size=narrow_row_key, round=true, label=@sf.t("web-pages.drive.retry")) {
      u.state = "waiting"
      u.error = ""
      u.sent = 0
      dv_pump(src)
    }
    if @sf.icon_button(c, "close", key=k + "/cancel", size=narrow_row_key, round=true, label=@sf.t("common.cancel")) {
      ups.uploads.retain(fn(x) { x.serial != u.serial })
      if u.state == "going" {
        ups.pumping = false
        dv_pump(src)
      }
    }
  })
  |> ignore
}

///|
/// A station's drive with no folder to show (RootsPage): its folders pinned, each a row (what is wrong with one under
/// its name, in red; held or right clicked, for one who may: no longer pinned, asked first); none, says so (选择文件夹
/// for one who may); from before drives, says so. Its bar: the station's name back, 文件, ⋯ 管理 for one who may.
pub fn roots_narrow(
  c : @ui.Ctx,
  src : Source,
  ws : String,
  st : DvStation?,
  reading : Bool,
  error : String?,
  manage : Bool,
  n : NarrowOf,
  go : (DriveAt) -> Unit,
) -> Unit {
  let t = @sf.theme()
  c.box(style=narrow_page, fn() {
    let back = match (n.frame.back, st) {
      (Some(_), Some(s)) => { ..n, frame: { ..n.frame, back: Some(s.name) } }
      _ => n
    }
    if narrow_bar(c, back, @sf.t("web-pages.drive.title"), fn() {
        match st {
          Some(s) if manage && s.drive && s.roots.length() > 0 =>
            if narrow_bar_button(c, "files/narrow/roots-more", "more", @sf.t("web-pages.drive.manage")) {
              manage_roots(src, ws, s.station)
            }
          _ => ()
        }
      }) {
      (n.back)()
    }
    match st {
      _ if reading => @sf.waiting(c, count=7, error=error.unwrap_or(""))
      None => narrow_empty(c, @sf.t("web-pages.workspace.noSuchStation"), None)
      Some(s) if !s.overview => @sf.waiting(c, count=7)
      Some(s) if !s.drive => narrow_empty(c, @sf.t("web-pages.drive.oldStation"), None)
      Some(s) if s.roots.length() == 0 =>
        narrow_empty(c, @sf.t(if manage { "web-pages.drive.noneManage" } else { "web-pages.drive.noneMember" }), if manage {
          Some((@sf.t("web-pages.drive.pick"), fn() { add_folder(src, ws, [s]) }))
        } else {
          None
        })
      Some(s) => {
        let rs = s.roots
        c.list("files/narrow/roots/" + s.station, rs.length() + 2, narrow_row_est, fn(i) {
          if i == 0 {
            c.box(style=narrow_count_box, fn() {
              c.text(@sf.t("web-pages.drive.rootsCount", args=[("n", rs.length().to_string())]), style=narrow_count_words) |> ignore
            })
            |> ignore
          } else if i == rs.length() + 1 {
            c.box(style=@ui.style(w=Full, h=Fixed(narrow_list_foot + n.frame.foot)), fn() {  }) |> ignore
          } else {
            narrow_root_row(c, src, s, rs[i - 1], i == 1, i == rs.length(), manage, go)
          }
        })
        |> ignore
      }
    }
  })
  |> ignore
  ignore(t)
}

///|
/// A folder pinned (RootRow): its name, where it is; one that cannot be browsed now with why in red and what to do.
fn narrow_root_row(
  c : @ui.Ctx,
  src : Source,
  s : DvStation,
  r : DvRoot,
  first : Bool,
  last : Bool,
  manage : Bool,
  go : (DriveAt) -> Unit,
) -> Unit {
  let t = @sf.theme()
  let id = c.id("files/narrow/root/" + s.station + "/" + r.path)
  c.cursor(id, Hand)
  match c.menu_asked(id) {
    Some((x, y)) if manage =>
      @sf.menu(
        [Some(@sf.menu_item_of(@sf.t("web-pages.drive.unshare"), icon="close", danger=true, fn() { ask_unpin(c, src, s, r) }))],
        from=@sf.at_point(x, y),
        title=r.name,
      )
    Some(_) => ()
    None => if c.clicked(id) { go({ station: s.station, root: Some(r.path), path: "" }) }
  }
  card_row(c, first, last, id, fn() {
    let b = c.box(style=narrow_entry, fn() {
      @sf.icon(c, "folder", size=narrow_kind_icon, color=t.p.muted) |> ignore
      c.box(style=narrow_entry_words, fn() {
        c.text(r.name, style=narrow_entry_name) |> ignore
        c.text(r.path, style=narrow_entry_meta) |> ignore
        match dv_trouble(r.state) {
          Some((what, hint)) => {
            c.text(what, style=narrow_trouble) |> ignore
            c.text(hint, style=narrow_trouble_hint) |> ignore
          }
          None => ()
        }
      })
      |> ignore
      @sf.icon(c, "chevron-right", size=narrow_chevron_icon, color=t.p.subtle) |> ignore
    })
    c.semantics(b, Button, id~, label=r.name)
  })
}

///|
/// A folder pinned no longer, asked first (unshare: 取消共享…).
pub fn ask_unpin(c : @ui.Ctx, src : Source, s : DvStation, r : DvRoot) -> Unit {
  @sf.confirm(
    @sf.t("web-pages.drive.unshareAsk", args=[("name", r.name)]),
    @sf.t("web-pages.drive.unshareText"),
    @sf.t("web-pages.drive.unshare"),
    fn() { set_roots(c, src, s.station, s.roots.filter(fn(x) { x.path != r.path }).map(fn(x) { x.path })) },
    danger=true,
  )
}

///|
/// The rows of a card (ListCard, ListRow): 12 in from the box's sides, the first and last carrying its corners, 10
/// under the last; each row 8 in from the card's sides (and from its top on the first, its bottom on the last), its
/// ground concentric with the card's, lit under the pointer or a finger's press (`id`; 0: none), rippling under a
/// finger.
fn card_row(c : @ui.Ctx, first : Bool, last : Bool, id : Int, body : () -> Unit) -> Unit {
  let ground = if id != 0 && c.lit(id) { Some(@sf.theme().p.hover) } else { None }
  c.box(style=if last { card_room_last } else { card_room }, fn() {
    c.box(style=card_inner, fn() {
      // the card's ground: rounded where it ends (its first row's top, its last's bottom), square between rows
      c.layer(fn() {
        c.box(style=card_whole, fn() {
          if !first {
            c.box(style=card_corner_room, fn() {  }) |> ignore
          }
          c.box(style=if first || last { card_ground_end } else { card_ground }, fn() {  }) |> ignore
          if !last {
            c.box(style=card_corner_room, fn() {  }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
      if !first {
        c.layer(fn() { c.box(style=card_square, fn() {  }) |> ignore }) |> ignore
      }
      if !last {
        c.layer(fn() {
          c.spacer()
          c.box(style=card_square, fn() {  }) |> ignore
        })
        |> ignore
      }
      let room = match (first, last) {
        (true, true) => card_row_only
        (true, false) => card_row_first
        (false, true) => card_row_last
        (false, false) => card_row_mid
      }
      c.box(style=room, fn() {
        c.box(style=if first || last { card_row_ground_end } else { card_row_ground }, bg?=ground, id~, fn() {
          body()
          if id != 0 {
            @sf.press_ripple(c, id, if first || last { @sf.inner_corner(@sf.drive_card_corner, @sf.list_pad) } else { @sf.row_corner })
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
/// How tall a row is taken to be before it is laid out.
let narrow_row_est : Double = 62.0

///|
/// Under the list, 30 over the frame's foot (contentPadding).
let narrow_list_foot : Double = 30.0

///|
/// Back's words at least 80 wide, at most what the bar has beside the title (half less 120).
let narrow_back_least : Double = 80.0

///|
let narrow_back_room : Double = 120.0

///|
/// The bar's buttons (NavButton: 34, its icon 18; ＋'s 20).
let narrow_bar_button_w : Double = 34.0

///|
let narrow_bar_icon : Double = 18.0

///|
let narrow_bar_plus : Double = 20.0

///|
/// The rows' marks (22), a folder's chevron (14), a crumb's (12), the empty folder's mark (40), a row's spinner (12), a
/// row's key (34).
let narrow_kind_icon : Double = 22.0

///|
let narrow_chevron_icon : Double = 14.0

///|
let narrow_crumb_chevron : Double = 12.0

///|
let narrow_empty_icon : Double = 40.0

///|
let narrow_spin : Double = 12.0

///|
let narrow_row_key : Double = 34.0

///|
// kept across runs: a value (no field of it changes)
let narrow_page : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

///|
// kept across runs: a value (no field of it changes)
let narrow_actions_row : @ui.Style = @ui.css("row align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let narrow_bar_spin : @ui.Style = @ui.css("w=S8 h=S8 align=ACenter justify=JCenter")

///|
/// What it holds in a line (mCount): 28 in, 2 over, 8 under, the meta's words, muted.
// kept across runs: a value (no field of it changes)
let narrow_count_box : @ui.Style = @ui.css("w=Full px=S7 pt=S0_5 pb=S2")

///|
// kept across runs: a value (no field of it changes)
let narrow_count_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false)

///|
/// The crumbs (mCrumbs): 20 in, a crumb 4 round, the way's muted, where it is in the words' colour.
// kept across runs: a value (no field of it changes)
let narrow_crumbs_row : @ui.Style = @ui.css("row pl=S5 pr=S5 pt=S0_5 pb=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let narrow_crumb : @ui.Style = @ui.css("px=S1 py=S1 radius=Lg")

///|
// kept across runs: a value (no field of it changes)
let narrow_crumb_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let narrow_crumb_here : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, wrap=false)

///|
/// Why it could not be read (mProblem): 20 in, 12 over and under, its 重试 in the link's ink.
// kept across runs: a value (no field of it changes)
let narrow_problem : @ui.Style = @ui.css("row w=Full px=S5 py=S3 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let narrow_problem_words : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let narrow_failed_words : @ui.TextStyle = @ui.text_style(size=Base, color=Danger, w=Full)

///|
// kept across runs: a value (no field of it changes)
let narrow_stale_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let narrow_link : @ui.Style = @ui.css("p=S1 radius=Lg")

///|
// kept across runs: a value (no field of it changes)
let narrow_link_words : @ui.TextStyle = @ui.text_style(size=Base, color=Link, wrap=false)

///|
/// Nothing here (mEmpty): in the middle, 56 by 32 in, 12 apart.
// kept across runs: a value (no field of it changes)
let narrow_empty_box : @ui.Style = @ui.css("w=Full px=S8 py=S14 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let narrow_empty_words : @ui.TextStyle = @ui.text_style(size=Base, color=Muted, center=true, w=Full)

///|
/// A row (mRow): 12 by 11 in (the card's 8 and its own), its mark, its words, what is at its end 12 apart.
// kept across runs: a value (no field of it changes)
let narrow_entry : @ui.Style = @ui.css("row w=Full px=S2 py=S2_5 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let narrow_entry_words : @ui.Style = @ui.style(w=@sf.grow)

///|
/// Its name (mName: the body's 15 on 20), what it is under it (mMeta: 12 on 16, muted).
// kept across runs: a value (no field of it changes)
let narrow_entry_name : @ui.TextStyle = @ui.text_style(size=Lg, leading=L6, color=Fg, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let narrow_entry_meta : @ui.TextStyle = @ui.text_style(size=Xs, leading=L4, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let narrow_trouble : @ui.TextStyle = @ui.text_style(size=Xs, leading=L4, weight=Semibold, color=Danger, w=Full)

///|
// kept across runs: a value (no field of it changes)
let narrow_trouble_hint : @ui.TextStyle = @ui.text_style(size=Xs, leading=L4, color=Muted, w=Full)

///|
/// A file going up (mRow, data-upload): its keys at its end (34 round).
// kept across runs: a value (no field of it changes)
let narrow_upload : @ui.Style = @ui.css("row w=Full pl=S2 py=S2_5 gap=S3 align=ACenter")

///|
/// Its name taken there (mUploadAsk): what is asked cut short, its two answers whole, 12 apart.
// kept across runs: a value (no field of it changes)
let narrow_upload_ask : @ui.Style = @ui.css("row gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let narrow_answer : @ui.Style = @ui.css("row")

///|
// kept across runs: a value (no field of it changes)
let narrow_answer_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L4, weight=Semibold, color=Link, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let narrow_upload_failed : @ui.TextStyle = @ui.text_style(size=Xs, leading=L4, color=Danger, w=Full)

///|
/// How far it has got (mProgress): 5 under the words.
// kept across runs: a value (no field of it changes)
let narrow_progress : @ui.Style = @ui.css("w=Full pt=S1_25")

///|
/// A card's room in its box (ListCard: 12 from the box's sides, 10 under the last row).
// kept across runs: a value (no field of it changes)
let card_room : @ui.Style = @ui.css("w=Full px=S3")

///|
// kept across runs: a value (no field of it changes)
let card_room_last : @ui.Style = @ui.css("w=Full px=S3 pb=S2_5")

///|
// kept across runs: a value (no field of it changes)
let card_whole : @ui.Style = @ui.css("w=Full h=Full")

///|
/// A card's row as tall as what it holds, the card's ground layered under it.
// kept across runs: a value (no field of it changes)
let card_inner : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let card_corner_room : @ui.Style = @ui.style(w=Full, h=Fixed(@sf.drive_card_corner))

///|
// kept across runs: a value (no field of it changes)
let card_ground : @ui.Style = @ui.css("w=Full h=Full bg=Card")

///|
// kept across runs: a value (no field of it changes)
let card_ground_end : @ui.Style = @ui.css("w=Full h=Full radius=Xl2 bg=Card")

///|
/// Between rows the card goes on square to the row's edge (its corner's room twice).
// kept across runs: a value (no field of it changes)
let card_square : @ui.Style = @ui.style(w=Full, h=Fixed(card_square_h), bg=Card)

///|
let card_square_h : Double = @sf.drive_card_corner * 2.0

///|
/// A row's room on its card: 8 in from its sides, and from its top on the first, its bottom on the last.
// kept across runs: a value (no field of it changes)
let card_row_mid : @ui.Style = @ui.css("w=Full px=S2")

///|
// kept across runs: a value (no field of it changes)
let card_row_first : @ui.Style = @ui.css("w=Full px=S2 pt=S2")

///|
// kept across runs: a value (no field of it changes)
let card_row_last : @ui.Style = @ui.css("w=Full px=S2 pb=S2")

///|
// kept across runs: a value (no field of it changes)
let card_row_only : @ui.Style = @ui.css("w=Full p=S2")

///|
/// A row's own ground (lit): its corner the row's, concentric with the card's at its ends.
// kept across runs: a value (no field of it changes)
let card_row_ground : @ui.Style = @ui.css("w=Full radius=Xl2")

///|
// kept across runs: a value (no field of it changes)
let card_row_ground_end : @ui.Style = @ui.style(w=Full, radius=@sf.drive_row_end_radius)
