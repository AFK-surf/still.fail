// A station's drive on the phone's stack (docs/drive.md): 文件 (the files' places, the wide frame's sidebar's list) and a
// page of a station's drive (the files' page, laid out by its width: @sfdesk files_start.mbt, drive_narrow.mbt), each in
// the stack's frame; a folder gone into is a page pushed over it, so going in and coming back is the stack's slide and
// the edge swipe. ＋ pins another folder (the files' page's own: Pin 文件夹).

///|
/// 文件 on the phone's stack: its places (the files' places, the same list the wide frame's sidebar is:
/// @sfdesk.files_places) under the stack's bar; pushed, a page with back and its ＋ in its bar; `place`, the top of a
/// place of the bottom bar (its top bar as Home's, the ＋ the bar's: files_lend).
pub fn files_page(c : @ui.Ctx, src : Source, w : Workspace, place? : Bool = false) -> Unit {
  let t = @sf.theme()
  let lenders = @sfdesk.pin_stations(src, w.id)
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
    if !place {
      let back = match app.nav.under() {
        Some(Home) => tr("android-misc.bar.place.chats")
        _ => tr("android-settings.title")
      }
      if dv_nav_bar(c, back, tr("android-misc.bar.place.files"), fn() {
          if lenders.length() > 0 &&
            dv_nav_button(c, "files-lend", "plus", size=20.0, said=tr("android-misc.bar.action.files")) {
            @sfdesk.add_folder(src, w.id, lenders)
          }
        }) {
        @sfbase.go_back() |> ignore
      }
    }
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      // under the top bar (and the status bar); at the foot 30 over the navigation bar, and the bottom bar's room at a
      // place's top (Files.kt foot)
      let foot = nav_foot() + 30.0 + (if place && has_bar() { bar_room } else { 0.0 })
      @sfdesk.files_places(c, src, w.id, top=if place { status_top() + bar_h + 8.0 } else { 4.0 }, foot~, go=fn(at) {
        open_page(Drive(at))
      })
      if place {
        c.layer(fn() { files_top_bar(c) }) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// Whether 文件 offers ＋ (another folder pinned: one who may pin, on a station with a drive), for the bottom bar's
/// notch.
pub fn files_can_lend(src : Source, w : Workspace) -> Bool {
  @sfdesk.pin_stations(src, w.id).length() > 0
}

///|
/// ＋ of 文件 (the bottom bar's notch): Pin 文件夹, on the one station there is or one chosen first.
pub fn files_lend(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  ignore(c)
  @sfdesk.add_folder(src, w.id, @sfdesk.pin_stations(src, w.id))
}

///|
/// 文件's top bar as a place's (PlacePage.kt TopGlassBar): settings, its name.
fn files_top_bar(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  let glass_top = c.box(w=Fill(1.0), glass=@sf.glass_bar(), fn() {
    // under the status bar (TopGlassBar: windowInsetsPadding(statusBars), then TopBarHeight)
    c.box(dir=Row, w=Fill(1.0), pl=16.0, pr=16.0, pt=status_top(), min_h=top_bar_h(), gap=10.0, align=ACenter, fn() {
      if nav_button(c, "settings", 22.0, key="files-settings") {
        open_page(Settings)
      }
      c.box(w=Fill(1.0), h=Px(34.0), justify=JCenter, fn() {
        top_bar_title(c, tr("android-misc.bar.place.files")) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  // over what runs under it: the scroll bar there keeps clear of it
  c.floats_over(glass_top)
}

// ── a drive's page ───────────────────────────────────────────────────────

///|
/// A page of a station's drive on the stack: the files' page (@sfdesk.files_station: a folder, or the station's folders
/// pinned), in the stack's frame (back to the page under it, under the status bar, over the navigation bar), a folder
/// gone into pushed over it (or back to it where it is in the stack already).
pub fn drive_page(c : @ui.Ctx, src : Source, w : Workspace, at : DriveAt) -> Unit {
  let back = app.nav.under().map(fn(under) { drive_back_label(src, w, under) })
  @sfdesk.files_station(
    c,
    src,
    w,
    settings_core(src, w),
    at,
    c.width,
    narrow={ frame: { back, top: status_top(), foot: nav_foot(), named: false }, back: fn() { @sfbase.go_back() |> ignore } },
    go=fn(to) { drive_go_back_to(to.station, to.root.unwrap_or(""), to.path) },
  )
}

///|
/// What back over a page of the drive says: the folder under it by its name (its station's, at the drive's own page),
/// 文件, else as back says it elsewhere.
fn drive_back_label(src : Source, w : Workspace, under : Page) -> String {
  match under {
    Drive(d) => {
      let st = dv_stations(src, w.id).0.unwrap_or([]).iter().find_first(fn(s) { s.station == d.station })
      match (st, d.root) {
        (Some(s), Some(_)) => @sfdesk.folder_name(s, d)
        (Some(s), None) => s.name
        _ => @sf.t("common.back")
      }
    }
    Files => tr("android-misc.bar.place.files")
    p => @sfbase.back_label(p)
  }
}

///|
/// Back to a folder where it is in the stack (the root as the drive's own page with one root has it is the same page);
/// else it opened there.
fn drive_go_back_to(station : String, root : String, path : String) -> Unit {
  let pages = app.nav.pages()
  let mut at = -1
  for i, p in pages {
    match p {
      Drive(d) if d.station == station &&
        d.path == path &&
        (d.root == Some(root) || (d.root is None && path == "")) => at = i
      _ => ()
    }
  }
  if at >= 0 {
    @sfbase.history_push()
    for _ in 0..<(pages.length() - 1 - at) {
      app.nav.pop() |> ignore
    }
  } else {
    open_page(Drive({ station, root: Some(root), path }))
  }
}

