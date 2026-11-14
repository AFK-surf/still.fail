// The desktop app's newer build ready, offered over the sidebar's top (brand.tsx UpdateButton, brand.css.ts
// sidebarUpdate): how an update stands is both frames' (sfbase updates.mbt).

///|
/// Whether the sidebar offers the update key: from a newer build known (有新版本, its first stage, 2026-11-03 the user:
/// 「所有能看到更新的地方，一定要有三个阶段：提示更新、下载更新中、点击更新」) while it comes, failed, or wants the person,
/// and while a check they asked for is under way.
fn update_shown() -> Bool {
  match update_now() {
    Offered(_, ..) | Coming(_, _) | Checking | Failed(_, _) => true
    _ => update_wants_you()
  }
}

///|
/// The desktop app's newer build, the library's update key (one look on every screen), the size of the
/// filter beside it (32, its mark 16): in the sidebar's first row before the filter (update_in_row); with the sidebar
/// closed, where the bar's start leaves room for it, past the rail (and the window's buttons). `top`: the system's
/// bars over the window (a phone's status bar), which take what is pressed under them: it goes below them.
fn update_button(c : @ui.Ctx, src : Source, inset : Bool, top : Double) -> Unit {
  let left = if inset { update_closed_inset } else { update_closed_in }
  c.layer(fn() {
    c.box(style=update_at, left~, top=top + update_top, fn() { update_in_row(c, src) }) |> ignore
  })
  |> ignore
}

///|
/// The update in a row of keys, in its three stages: 有新版本 (a download mark), progress while it comes, then 重启更新.
/// Pressing the progress opens its details; pressing one offered, ready or failed does what it says (update_go).
fn update_in_row(c : @ui.Ctx, src : Source) -> Unit {
  let now = update_now()
  let coming = match now {
    Coming(_, part) => Some(part)
    _ => None
  }
  let (label, tip, busy) = update_said()
  let offered = now is Offered(_, ..)
  let restart = now is Ready(_, ..)
  @sf.update_key(c, "side/update", update_key_side, update_key_mark, label, tip, busy, coming~, offered~, restart~, on_press=fn() {
    if coming is Some(_) {
      @sfbase.update_dialog(src)
    } else {
      update_go(src)
    }
  })
}

///|
/// The update key beside another sidebar's action, if one is shown.
fn update_trailing(c : @ui.Ctx, src : Source) -> (() -> Unit)? {
  if update_shown() { Some(fn() { update_in_row(c, src) }) } else { None }
}

///|
/// A sidebar's action band with the update at its end: on the tape or in the floating pane, the same line and corner
/// as the chats' filter. With no update, the other sidebars keep their ordinary band.
fn update_band(at? : BandAt = band_at_old()) -> @ui.Style {
  if !update_shown() {
    @sf.nav_new()
  } else if at.tape {
    band_new_tape(at~)
  } else {
    band_new_pane(at~)
  }
}

///|
/// The settings' old back row has the list's 4 above it and at least row_least in height; the action band has 6 above
/// it and band_row_h in height. Make up the difference below so the groups do not jump when the update appears.
fn update_back_band(at? : BandAt = band_at_old()) -> @ui.Style {
  let band = update_band(at~).then(settings_back_band)
  if at.in_bar || at.tape {
    band
  } else {
    let bottom = @sf.room_of(update_back_room + @sf.row_least() - @sf.band_row_h())
    band.then(@ui.style(pb=bottom))
  }
}

///|
/// The back band's 10 below, plus the old list's 4 above, less the action band's 6 above.
let update_back_room : Double = 8.0

///|
/// The key's side and its mark's: the filter's beside it (filter_box: 32; side_icon: 16).
let update_key_side : Double = 32.0

///|
let update_key_mark : Double = 16.0

///|
/// What the key says, its tip (the key is a mark alone: what it does or what is under way is said there, in every
/// state it shows in), and whether it is under way.
fn update_said() -> (String, String, Bool) {
  match update_now() {
    Allow(_) =>
      (@sf.t("android-misc.updates.allow"), @sf.t("android-misc.updates.allowWhy", args=[("app", "still.fail")]), false)
    Checking => {
      let checking = @sf.t("android-misc.updates.checking")
      (checking, checking, true)
    }
    Offered(_, ..) | Coming(_, _) | Failed(_, _) => {
      let stands = @sfbase.update_stands()
      (stands.label, stands.label + (if stands.note == "" { "" } else { " · " + stands.note }), false)
    }
    Installing(v) =>
      (
        @sf.t("web-main.appUpdate.restarting"),
        @sf.t("android-misc.updates.installingVersion", args=[("version", text(Some(v), "versionName"))]),
        true,
      )
    // (that it is downloaded said too: 重启以更新到 alone read as one still to come, 2026-11-03)
    Ready(_, ..) => {
      let stands = @sfbase.update_stands()
      (@sf.t("desktop.update.restart"), stands.label + " · " + stands.note, false)
    }
    _ => (@sf.t("desktop.update.restart"), "", false)
  }
}

///|
/// Where 更新 is (brand.css.ts sidebarUpdate): 11 down in the desktop app; closed, 68 from the window's edge (80 with
/// the window's buttons in the app's top row); the page bars' start clear of it then (frame.mbt bar_update_in).
pub let update_top : Double = 11.0

///|
pub let update_closed_in : Double = 68.0

///|
let update_closed_inset : Double = 80.0

///|
/// 更新's box with the sidebar closed: its key's size.
// kept across runs: a value (no field of it changes)
let update_at : @ui.Style = @ui.css("row")
