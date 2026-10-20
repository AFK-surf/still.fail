// The drive's sheets (ember apps/android drive/DriveScreen.kt openViewSheet, openEntrySheet, openChosenSheet,
// newFolder, removeAll, openRoots, openFolderPicker; Files.kt lend; screens/PageParts.kt ask, confirm): over the page
// that opened them, one at a time.

///|
/// The sheet open (or the one closing), over the page.
fn dv_sheets(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let (s, closing) = match dv.sheet {
    NoSheet =>
      match dv.closing {
        NoSheet => return
        x =>
          if c.now() - dv.closed_at < dv_sheet_close_ms && !c.stable() {

            c.request_frame()
            (x, true)
          } else {
            dv.closing = NoSheet
            return
          }
      }
    x => (x, false)
  }
  let (list, _) = dv_stations(src, w.id)
  let station_of = fn(id : String) -> DvStation? {
    match list {
      Some(l) => l.iter().find_first(fn(x) { x.station == id })
      None => None
    }
  }
  match s {
    NoSheet => ()
    Add(at, name, manage) =>
      dv_sheet_frame(c, name, dv_fit(if manage { 3 } else { 2 }), closing~, fn() {
        if dv_pick_row(c, "add/upload", tr("android-misc.drive.upload"), icon="upload") {
          dv_close(c)
          dv_upload(c, at)
        }
        if dv_pick_row(c, "add/mkdir", tr("android-misc.drive.mkdir"), icon="folder-plus") {
          dv_new_folder(c, src, at)
        }
        if manage &&
          dv_pick_row(c, "add/roots", tr("android-misc.drive.roots.manage"), icon="folder") {
          dv_open(c, Roots(at.station))
        }
      })
    View(at, manage) => {
      let (sort, hidden) = dv_views(src)
      let by = match sort.find("-") {
        Some(i) => sort.view(end_offset=i).to_owned()
        None => sort
      }
      dv_sheet_frame(
        c,
        tr("android-misc.drive.view"),
        dmin(c.height * 0.5, dv_fit(5 + (if manage { 1 } else { 0 }))),
        closing~,
        fn() {
          for k in ["name", "time", "size", "kind"] {
            if dv_pick_row(c, "view/" + k, tr("web-pages.drive.sortBy." + k), checked=by == k) {
              dv_set_view(src, "sort", if k == "name" { None } else { Some(k) })
            }
          }
          if dv_pick_row(c, "view/hidden", tr("web-pages.drive.showHidden"), checked=hidden) {
            dv_set_view(src, "hidden", if hidden { None } else { Some("shown") })
          }
          if manage &&
            dv_pick_row(c, "view/roots", tr("android-misc.drive.roots.manage"), icon="folder") {
            dv_open(c, Roots(at.station))
          }
        },
      )
    }
    Entry(at, e, names) => {
      let can = dv_rights(src, w.id, station_of(at.station))
      entry_sheet(c, src, at, e, names, can, closing)
    }
    Chosen(at, picked) => {
      let can = dv_rights(src, w.id, station_of(at.station))
      chosen_sheet(c, src, at, picked, can, closing)
    }
    Ask(title, value, placeholder, action, run) =>
      dv_sheet_frame(c, title, c.height * 0.42, closing~, fn() {
        let key = "dv-ask"
        let asked = title + "\u{1}" + value
        if dv.asked != asked {
          dv.asked = asked
          c.set_editor_text(key, value)
        }
        c.box(w=Fill(1.0), padx=20.0, gap=10.0, fn() {
          let words = dv_field(c, key, placeholder)
          let line = words.trim(chars=" \t\n").to_owned()
          c.box(dir=Row, w=Fill(1.0), pt=6.0, pb=24.0, gap=8.0, justify=JEnd, fn() {
            if dv_button(c, "ask/cancel", tr("common.cancel"), primary=false) {
              dv_close(c)
            }
            if dv_button(c, "ask/go", action, primary=true, enabled=line != "" && line != value) {
              dv_close(c)
              dv.asked = ""
              run(line)
            }
          })
          |> ignore
        })
        |> ignore
      })
    Confirm(title, words, action, danger, run) =>
      dv_sheet_frame(c, title, c.height * 0.36, closing~, fn() {
        let t = @sf.theme()
        c.box(w=Fill(1.0), padx=20.0, gap=10.0, fn() {
          c.text(words, size=14.0, color=t.p.muted, w=Fill(1.0), line=20.0) |> ignore
          c.box(dir=Row, w=Fill(1.0), pt=6.0, pb=24.0, gap=8.0, justify=JEnd, fn() {
            if dv_button(c, "confirm/cancel", tr("common.cancel"), primary=false) {
              dv_close(c)
            }
            if dv_button(c, "confirm/go", action, primary=true, danger~) {
              dv_close(c)
              run()
            }
          })
          |> ignore
        })
        |> ignore
      })
    Roots(station) => roots_sheet(c, src, station, station_of(station), closing)
    RootHeld(station, r) =>
      dv_sheet_frame(c, r.name, dv_fit(1), closing~, fn() {
        let t = @sf.theme()
        if dv_pick_row(c, "held/stop", tr("android-misc.drive.roots.stop"), icon="close", color=t.p.accent) {
          dv_unshare(c, src, station, station_of(station), r)
        }
      })
    LendOn(on) =>
      dv_sheet_frame(c, tr("android-misc.files.lendOn"), (96 + on.length() * 48 + 24).to_double(), closing~, fn() {
        for s in on {
          if dv_pick_row(c, "lend/" + s.station, s.name) {
            dv_open_picker(c, s.station, s.roots.map(fn(r) { r.path }))
          }
        }
      })
    Picker(station, lent) => picker_sheet(c, src, station, lent, closing)
  }
}

///|
/// One entry (DriveScreen.kt openEntrySheet): renamed and deleted by those who may change the drive; a file
/// downloaded and shared, a folder downloaded as a zip; its path copied.
fn entry_sheet(
  c : @ui.Ctx,
  src : Source,
  at : DriveAt,
  e : DvEntry,
  names : Array[String],
  can : DvRights,
  closing : Bool,
) -> Unit {
  let t = @sf.theme()
  let root = at.root.unwrap_or("")
  let path = dv_join(at.path, e.name)
  let zip = e.dir && can.zip
  let rows = (if can.write { 2 } else { 0 }) +
    (if e.dir {
      if zip {
        1
      } else {
        0
      }
    } else {
      2
    }) +
    1
  let done = fn() { dv.chosen.remove(folder_key(at.station, root, at.path)) }
  dv_sheet_frame(c, e.name, dmin(c.height * 0.5, dv_fit(rows)), closing~, fn() {
    if can.write && dv_pick_row(c, "entry/rename", tr("android-misc.drive.rename"), icon="edit") {
      done()
      dv_open(
        c,
        Ask(tr("android-misc.drive.rename"), e.name, e.name, tr("common.save"), fn(name) {
          let what = tr("android-misc.drive.rename.what")
          match dv_name_problem(name) {
            Some(p) => say(c, fill("android-misc.act.failed", [("what", what), ("error", p)]))
            None =>
              if name != e.name && names.contains(name) {
                say(
                  c,
                  fill("android-misc.act.failed", [("what", what), ("error", tr("station.drive.exists"))]),
                )
              } else {
                dv_doing(
                  c,
                  src,
                  dv_key("entry", at.station, root, path),
                  what,
                  "drive.rename",
                  Json::object({
                    "station": Json::string(at.station),
                    "root": Json::string(root),
                    "from": Json::string(path),
                    "to": Json::string(dv_join(at.path, name)),
                  }),
                )
              }
          }
        }),
      )
    }
    if !e.dir {
      if dv_pick_row(c, "entry/download", tr("android-misc.drive.download"), icon="download") {
        dv_close(c)
        done()
        say(c, fill("android-misc.drive.downloading", [("name", e.name)]))
        download_drive_file(c, src, at.station, root, path, e.name, e.mime)
      }
      if dv_pick_row(c, "entry/share", tr("android-misc.drive.share"), icon="external") {
        dv_close(c)
        done()
        // read whole through the core, then the system's share sheet (share.mbt)
        share_drive_file(c, src, at, e)
      }
    } else if zip &&
      dv_pick_row(c, "entry/zip", tr("web-pages.drive.downloadZip"), icon="download") {
      dv_close(c)
      done()
      say(c, fill("android-misc.drive.downloading", [("name", e.name + ".zip")]))
      download_drive_zip(c, src, at.station, root, path)
    }
    if dv_pick_row(c, "entry/copy", tr("web-pages.drive.copyPath"), icon="copy") {
      dv_close(c)
      done()
      c.copy_text(dv_absolute(root, path))
      say(c, tr("web-pages.drive.pathCopied"))
    }
    if can.write &&
      dv_pick_row(
        c,
        "entry/remove",
        tr(if can.trash { "web-pages.drive.toTrash" } else { "android-misc.drive.remove" }),
        icon="trash",
        color=t.p.accent,
      ) {
      done()
      dv_close(c)
      dv_remove_all(c, src, at, [e], can.trash)
    }
  })
}

///|
/// What is chosen, several (DriveScreen.kt openChosenSheet): downloaded, their paths copied, deleted.
fn chosen_sheet(
  c : @ui.Ctx,
  src : Source,
  at : DriveAt,
  picked : Array[DvEntry],
  can : DvRights,
  closing : Bool,
) -> Unit {
  let t = @sf.theme()
  let root = at.root.unwrap_or("")
  let files = picked.filter(fn(e) { !e.dir })
  let rows = (if files.length() > 0 { 1 } else { 0 }) + 1 + (if can.write { 1 } else { 0 })
  let done = fn() { dv.chosen.remove(folder_key(at.station, root, at.path)) }
  dv_sheet_frame(c, dv_count("android-misc.drive.chosen", picked.length()), dv_fit(rows), closing~, fn() {
    if files.length() > 0 &&
      dv_pick_row(c, "chosen/download", dv_count("web-pages.drive.downloadMany", files.length()), icon="download") {
      dv_close(c)
      done()
      download_drive_files(c, src, at.station, root, at.path, files)
    }
    if dv_pick_row(c, "chosen/copy", tr("web-pages.drive.copyPaths"), icon="copy") {
      dv_close(c)
      done()
      let out = StringBuilder()
      for i, e in picked {
        if i > 0 {
          out.write_char('\n')
        }
        out.write_string(dv_absolute(root, dv_join(at.path, e.name)))
      }
      c.copy_text(out.to_string())
      say(c, tr("web-pages.drive.pathCopied"))
    }
    if can.write &&
      dv_pick_row(
        c,
        "chosen/remove",
        dv_count(
          if can.trash {
            "web-pages.drive.toTrashMany"
          } else {
            "web-pages.drive.deleteMany"
          },
          picked.length(),
        ),
        icon="trash",
        color=t.p.accent,
      ) {
      dv_close(c)
      done()
      dv_remove_all(c, src, at, picked, can.trash)
    }
  })
}

///|
/// A new folder in `at`, named here (DriveScreen.kt newFolder).
fn dv_new_folder(c : @ui.Ctx, src : Source, at : DriveAt) -> Unit {
  let root = at.root.unwrap_or("")
  dv_open(
    c,
    Ask(tr("android-misc.drive.mkdir"), "", tr("android-misc.drive.mkdir.placeholder"), tr("android-misc.drive.mkdir.make"), fn(name) {
      let what = tr("android-misc.drive.mkdir.what")
      match dv_name_problem(name) {
        Some(p) => say(c, fill("android-misc.act.failed", [("what", what), ("error", p)]))
        None =>
          (src.call)(
            "drive.mkdir",
            Json::object({
              "station": Json::string(at.station),
              "root": Json::string(root),
              "path": Json::string(dv_join(at.path, name)),
            }),
            dv_act(c, what),
          )
      }
    }),
  )
}

///|
/// Deleted (DriveScreen.kt removeAll): to the machine's trash where the station has one, nothing asked (said once
/// done); where none takes them, asked first, then for good.
fn dv_remove_all(c : @ui.Ctx, src : Source, at : DriveAt, picked : Array[DvEntry], trash : Bool) -> Unit {
  let root = at.root.unwrap_or("")
  let what = tr("android-misc.drive.remove.what")
  let params = fn(e : DvEntry, permanent : Bool) {
    let p : Map[String, Json] = {
      "station": Json::string(at.station),
      "root": Json::string(root),
      "path": Json::string(dv_join(at.path, e.name)),
    }
    if permanent {
      p["permanent"] = Json::boolean(true)
    }
    Json::object(p)
  }
  let for_good = fn(list : Array[DvEntry]) {
    let title = match list {
      [one] =>
        fill(
          if one.dir {
            "android-misc.drive.remove.folderTitle"
          } else {
            "android-misc.drive.remove.fileTitle"
          },
          [("name", one.name)],
        )
      _ => dv_count("web-pages.drive.deleteManyAsk", list.length())
    }
    let words = tr(
      if list.iter().any(fn(e) { e.dir }) {
        "android-misc.drive.remove.folderText"
      } else {
        "android-misc.drive.remove.fileText"
      },
    )
    dv_open(
      c,
      Confirm(title, words, tr("android-misc.drive.remove"), true, fn() {
        for e in list {
          dv_doing(
            c,
            src,
            dv_key("entry", at.station, root, dv_join(at.path, e.name)),
            what,
            "drive.remove",
            params(e, true),
          )
        }
      }),
    )
  }
  if !trash {
    for_good(picked)
    return
  }
  // each to the trash; those it would not take asked about, once all have answered
  let left : Array[DvEntry] = []
  let mut answered = 0
  let mut failed = false
  for e in picked {
    let key = dv_key("entry", at.station, root, dv_join(at.path, e.name))
    dv.busy[key] = true
    (src.call)("drive.remove", params(e, false), fn(r) {
      dv.busy.remove(key)
      answered += 1
      match r {
        Ok(_) => ()
        Err(x) =>
          if text(Some(x), "code") == "no_trash" {
            left.push(e)
          } else if !failed {
            failed = true
            (dv_act(c, what))(r)
          }
      }
      if answered == picked.length() && !failed {
        if left.length() > 0 {
          for_good(left)
        } else {
          say(
            c,
            if picked.length() == 1 {
              tr("web-pages.drive.trashed.one")
            } else {
              dv_count("web-pages.drive.trashed", picked.length())
            },
          )
        }
      }
    })
  }
}

// ── the folders lent ─────────────────────────────────────────────────────

///|
/// The folders the station lends (DriveScreen.kt openRoots, owners and admins): each tapped to stop lending it;
/// another one added.
fn roots_sheet(c : @ui.Ctx, src : Source, station : String, s : DvStation?, closing : Bool) -> Unit {
  let t = @sf.theme()
  let roots = match s {
    Some(x) => x.roots
    None => []
  }
  dv_sheet_frame(c, tr("android-misc.drive.roots.manage"), c.height * 0.7, closing~, fn() {
    c.box(w=Fill(1.0), pl=20.0, pr=20.0, pb=6.0, fn() {
      c.text(tr("android-misc.drive.roots.note"), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0)
      |> ignore
    })
    |> ignore
    for r in roots {
      let mark = match dv_trouble(r.state) {
        Some((what, _)) => what
        None => ""
      }
      if dv_pick_row(c, "roots/" + r.path, r.name, sub=r.path, icon="folder", mark~) {
        dv_unshare(c, src, station, s, r)
      }
    }
    if dv_pick_row(c, "roots/add", tr("android-misc.drive.roots.add"), icon="plus", color=t.p.accent) {
      dv_open_picker(c, station, roots.map(fn(r) { r.path }))
    }
  })
}

///|
/// A folder no longer lent, asked first (DriveScreen.kt unshare).
fn dv_unshare(c : @ui.Ctx, src : Source, station : String, s : DvStation?, r : DvRoot) -> Unit {
  let roots = match s {
    Some(x) => x.roots.filter(fn(x) { x.path != r.path }).map(fn(x) { Json::string(x.path) })
    None => []
  }
  dv_open(
    c,
    Confirm(
      fill("android-misc.drive.roots.stopTitle", [("name", r.name)]),
      tr("android-misc.drive.roots.stopText"),
      tr("android-misc.drive.roots.stop"),
      true,
      fn() {
        (src.call)(
          "drive.setRoots",
          Json::object({ "station": Json::string(station), "roots": Json::array(roots) }),
          dv_act(c, tr("android-misc.drive.roots.what")),
        )
      },
    ),
  )
}

///|
/// The folder picker opened at the station's home (DriveScreen.kt openFolderPicker); `lent`: the folders lent already.
fn dv_open_picker(c : @ui.Ctx, station : String, lent : Array[String]) -> Unit {
  dv.picker_at = None
  dv.picker = None
  dv.picker_error = ""
  dv.picker_denied = false
  // (an ask of an earlier opening still on its way is let go: its answer is not this one's)
  dv.picker_serial += 1
  dv.picker_asking = false
  c.set_editor_text("dv-picker-filter", "")
  dv_open(c, Picker(station, lent))
}

///|
/// The folders at `path` asked of the station (its home when None); a later ask supersedes one on its way. The one
/// place that asks: whoever wants another place (a step of the way, a folder tapped, the sheet opened) comes here, and
/// the ask is on its way until its answer (picker_asking), so nothing asks it again meanwhile.
fn dv_picker_go(c : @ui.Ctx, src : Source, station : String, path : String?) -> Unit {
  dv.picker_at = path
  dv.picker = None
  dv.picker_error = ""
  dv.picker_denied = false
  dv.picker_serial += 1
  dv.picker_asking = true
  let serial = dv.picker_serial
  c.set_editor_text("dv-picker-filter", "")
  let params : Map[String, Json] = { "station": Json::string(station) }
  match path {
    Some(p) => params["path"] = Json::string(p)
    None => ()
  }
  (src.call)("drive.folders", Json::object(params), fn(r) {
    if serial != dv.picker_serial {
      return
    }
    dv.picker_asking = false
    match r {
      Ok(v) => {
        dv.picker = Some(v)
        dv.picker_denied = flag(Some(v), "unreadable")
      }
      Err(e) =>
        if text(Some(e), "code") == "permission" {
          dv.picker_denied = true
        } else {
          dv.picker_error = dv_error(e)
        }
    }
  })
}

///|
/// The way to the folder shown (DriveScreen.kt wayTo): from the home when it is under it, else from the top.
fn dv_way(here : Json) -> Array[(String, String)] {
  let h = Some(here)
  let crumbs = items(h, "crumbs")
  if crumbs.length() > 0 {
    return crumbs.map(fn(x) { (text(Some(x), "name"), text(Some(x), "path")) })
  }
  let path = text(h, "path")
  let home_path = text(h, "home")
  let home = home_path.trim_end(chars="/\\").to_owned()
  let under = home != "" && (path == home_path || path.has_prefix(home + "/"))
  let way : Array[(String, String)] = [
    if under {
      (tr("web-pages.drive.home"), home_path)
    } else {
      ("/", "/")
    },
  ]
  let mut at = if under { home } else { "" }
  let rest = if under { path.view(start_offset=home.length()).to_owned() } else { path }
  for part in rest.split("/") {
    if part != "" {
      at = at + "/" + part.to_owned()
      way.push((part.to_owned(), at))
    }
  }
  way
}

///|
/// The station's folders, from its home (DriveScreen.kt openFolderPicker): the way there on top (each step a way
/// back), a filter for the names, at the home the usual places over its folders; a folder the station may not read
/// says so. 选择此文件夹 lends the one shown.
fn picker_sheet(c : @ui.Ctx, src : Source, station : String, lent : Array[String], closing : Bool) -> Unit {
  let t = @sf.theme()
  // opened, nothing shown and nothing on its way: its place asked (a step or a folder tapped asked already, as it was
  // tapped: dv_picker_go)
  if !closing && dv.picker is None && dv.picker_error == "" && !dv.picker_denied && !dv.picker_asking {
    dv_picker_go(c, src, station, dv.picker_at)
  }
  dv_sheet_frame(c, tr("android-misc.drive.pick.title"), c.height * 0.85, closing~, fn() {
    let here = dv.picker
    let way = match here {
      Some(h) => dv_way(h)
      None => []
    }
    // the way
    c.box(dir=Row, w=Fill(1.0), min_h=28.0, pl=17.0, pr=20.0, pb=8.0, align=ACenter, clip=true, fn() {
      for i, step in way {
        let (name, path) = step
        if i > 0 {
          @sf.icon(c, "chevron-right", size=12.0, color=t.p.subtle) |> ignore
        }
        let last = i == way.length() - 1
        let id = c.id("pick-way/\{i}")
        if !last && c.clicked(id) {
          dv_picker_go(c, src, station, Some(path))
        }
        c.box(padx=3.0, pady=3.0, radius=6.0, id=if last { 0 } else { id }, fn() {
          c.text(name, size=14.0, weight=if last { 600 } else { 400 }, color=if last { t.p.text } else { t.p.muted }, wrap=false)
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
    // the filter
    let mut wanted = ""
    c.box(w=Fill(1.0), padx=20.0, pb=6.0, fn() {
      c.box(dir=Row, w=Fill(1.0), h=Px(38.0), radius=19.0, bg=@sf.alpha(t.p.text, 0.06), pl=12.0, pr=6.0, gap=8.0, align=ACenter, fn() {
        @sf.icon(c, "search", size=16.0, color=t.p.muted) |> ignore
        c.box(w=Fill(1.0), fn() {
          let res = c.editor(
            "dv-picker-filter",
            placeholder=tr("android-misc.drive.pick.filter"),
            font_size=15.0,
            line=21.0,
            max_lines=1,
            plain=true,
            color=t.p.text,
            placeholder_color=t.p.muted,
            caret_color=t.p.accent,
          )
          wanted = res.text.trim(chars=" ").to_owned()
        })
        |> ignore
        if wanted != "" && dv_row_key(c, "pick-filter-clear", "close") {
          c.set_editor_text("dv-picker-filter", "")
        }
      })
      |> ignore
    })
    |> ignore
    // the folders
    c.box(w=Fill(1.0), h=Fill(1.0), clip=true, fn() {
      match here {
        _ if dv.picker_error != "" =>
          c.box(padx=20.0, pady=8.0, fn() {
            c.text(dv.picker_error, size=13.0, color=t.p.red, w=Fill(1.0)) |> ignore
          })
          |> ignore
        _ if dv.picker_denied => dv_note(c, tr("android-misc.drive.pick.unreadable"))
        None =>
          c.box(padx=20.0, pady=12.0, fn() {
            @sf.wait_line(c, tr("common.reading"), key="picker")
          })
          |> ignore
        Some(h) => {
          let hp = Some(h)
          let path = text(hp, "path")
          let home = text(hp, "home")
          let entries = match field(hp, "entries") {
            Some(Array(a)) => a.map(fn(x) { (text(Some(x), "name"), text(Some(x), "path"), flag(Some(x), "unreadable"), flag(Some(x), "disk")) })
            _ =>
              items(hp, "folders").map(fn(x) {
                let n = match x {
                  String(s) => s
                  _ => ""
                }
                (n, path.trim_end(chars="/").to_owned() + "/" + n, false, false)
              })
          }
          let places = if path == home && wanted == "" {
            let all = items(hp, "places").map(fn(x) { (text(Some(x), "name"), text(Some(x), "path"), flag(Some(x), "unreadable"), flag(Some(x), "disk")) })
            all.filter(fn(p) { p.1 != home })
          } else {
            []
          }
          let listed = if wanted == "" {
            entries.filter(fn(e) { !places.iter().any(fn(p) { p.1 == e.1 }) })
          } else {
            entries.filter(fn(e) { e.0.to_lower().contains(wanted.to_lower()) })
          }
          let rows : Array[(String, String, Bool, Bool)?] = []
          if places.length() > 0 {
            rows.push(Some(("\u{1}places", "", false, false)))
            for p in places {
              rows.push(Some(p))
            }
            rows.push(Some(("\u{1}folders", "", false, false)))
          }
          if listed.length() == 0 {
            rows.push(None)
          }
          for e in listed {
            rows.push(Some(e))
          }
          c.list("picker/" + path, rows.length(), 48.0, fn(i) {
            match rows[i] {
              None =>
                c.box(padx=20.0, pady=12.0, fn() {
                  c.text(
                    if wanted == "" {
                      tr("android-misc.drive.pick.empty")
                    } else {
                      fill("android-misc.drive.pick.noMatch", [("q", wanted)])
                    },
                    size=13.0,
                    color=t.p.muted,
                    w=Fill(1.0),
                  )
                  |> ignore
                })
                |> ignore
              Some(("\u{1}places", _, _, _)) => dv_section(c, tr("android-misc.drive.pick.places"))
              Some(("\u{1}folders", _, _, _)) => dv_section(c, tr("android-misc.drive.pick.folders"))
              Some((name, p, unreadable, disk)) =>
                if dv_pick_row(
                    c,
                    "pick/" + p,
                    name,
                    sub=if unreadable { tr("android-misc.drive.pick.unreadable") } else { "" },
                    icon=if disk { "disk" } else { "folder" },
                  ) {
                  dv_picker_go(c, src, station, Some(p))
                }
            }
          })
          |> ignore
        }
      }
    })
    |> ignore
    if dv.picker_denied {
      c.box(w=Fill(1.0), pl=20.0, pr=20.0, pt=8.0, fn() {
        c.text(tr("android-misc.drive.pick.unreadableNote"), size=13.0, color=t.p.muted, w=Fill(1.0))
        |> ignore
      })
      |> ignore
    }
    let shown_path = match here {
      Some(h) => text(Some(h), "path")
      None => ""
    }
    let taken = here is Some(_) && lent.contains(shown_path)
    c.box(dir=Row, w=Fill(1.0), pl=20.0, pr=20.0, pt=8.0, pb=16.0, gap=8.0, justify=JEnd, fn() {
      if dv_button(c, "pick/cancel", tr("common.cancel"), primary=false) {
        dv_close(c)
      }
      if dv_button(
          c,
          "pick/choose",
          if taken {
            tr("android-misc.drive.pick.already")
          } else {
            tr("android-misc.drive.pick.choose")
          },
          primary=true,
          enabled=here is Some(_) && !taken && !dv.picker_denied,
        ) {
        dv_close(c)
        let p = shown_path
        let label = match dv_name(p.trim_end(chars="/").to_owned()) {
          "" => p
          n => n
        }
        let roots = lent.map(fn(x) { Json::string(x) })
        roots.push(Json::string(p))
        (src.call)(
          "drive.setRoots",
          Json::object({ "station": Json::string(station), "roots": Json::array(roots) }),
          dv_act(
            c,
            tr("android-misc.drive.roots.what"),
            done=fill("android-misc.drive.roots.added", [("name", label)]),
          ),
        )
      }
    })
    |> ignore
  })
}
