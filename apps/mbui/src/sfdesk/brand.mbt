// The desktop app's newer build, offered over the sidebar's top (brand.tsx UpdateButton, brand.css.ts
// sidebarUpdate): how an update stands is both frames' (sfbase updates.mbt).

///|
/// Whether the desktop app has a newer build to offer, or one on its way in (brand.tsx UpdateButton: the app's update
/// state, none while there is none).
fn update_shown() -> Bool {
  update.available.get() is Some(_) || update_under_way() || update_phase() == "failed"
}

///|
/// The desktop app's newer build, the library's update key (Home.kt's, one look on every screen), the size of the
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
/// 更新 in a row of keys (the sidebar's first, before the filter): the library's update key, the filter's size; how far
/// it has come under its mark, a red dot where it failed (why, its tip). Pressed, the build is downloaded and the app
/// restarts as it.
fn update_in_row(c : @ui.Ctx, src : Source) -> Unit {
  let (label, why, busy) = update_said()
  if @sf.update_key(c, "side/update", update_key_side, update_key_mark, label, why, update_part(), update_phase() == "failed", busy) {
    update_install(src)
  }
}

///|
/// The key's side and its mark's: the filter's beside it (filter_box: 32; side_icon: 16).
let update_key_side : Double = 32.0

///|
let update_key_mark : Double = 16.0

///|
/// What 更新 says, its tip, and whether it is under way.
fn update_said() -> (String, String, Bool) {
  let busy = update_under_way()
  let percent = update_percent()
  let label = match update_phase() {
    "downloading" | "retrying" =>
      @sf.t("web-main.appUpdate.downloading", args=[("percent", (if percent < 0 { 0 } else { percent }).to_string())])
    "installing" => @sf.t("web-main.appUpdate.restarting")
    "failed" => @sf.t("web-main.appUpdate.failed")
    _ => @sf.t("web-main.versions.update")
  }
  let tip = if update_phase() == "failed" {
    update_why()
  } else {
    @sf.t("web-main.appUpdate.title", args=[("version", text(update.available.get(), "versionName")), ("app", "still.fail")])
  }
  (label, tip, busy)
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
