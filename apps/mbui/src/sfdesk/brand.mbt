// The desktop app's newer build ready, offered over the sidebar's top (brand.tsx UpdateButton, brand.css.ts
// sidebarUpdate): how an update stands is both frames' (sfbase updates.mbt).

///|
/// Whether the sidebar offers the update key: only while the update wants the person (sfbase updates.mbt
/// update_wants_you: a build ready that is not put in place by itself, the leave to install apps, one being put in
/// place at their word); while one comes it is the host's, said in 关于 alone.
fn update_shown() -> Bool {
  update_wants_you()
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
/// 重启更新 in a row of keys (the sidebar's first, before the filter): the library's update key, the filter's size, its
/// tip the version it goes to. Pressed, the build ready is put in place and the app starts again as it (update_go);
/// turning while it is.
fn update_in_row(c : @ui.Ctx, src : Source) -> Unit {
  let (label, tip, busy) = update_said()
  if @sf.update_key(c, "side/update", update_key_side, update_key_mark, label, tip, busy) {
    update_go(src)
  }
}

///|
/// The key's side and its mark's: the filter's beside it (filter_box: 32; side_icon: 16).
let update_key_side : Double = 32.0

///|
let update_key_mark : Double = 16.0

///|
/// What the key says, its tip, and whether it is under way.
fn update_said() -> (String, String, Bool) {
  match update_now() {
    Allow(_) =>
      (@sf.t("android-misc.updates.allow"), @sf.t("android-misc.updates.allowWhy", args=[("app", "still.fail")]), false)
    Installing(_) => (@sf.t("web-main.appUpdate.restarting"), "", true)
    Ready(v, ..) =>
      (
        @sf.t("desktop.update.restart"),
        @sf.t("android-misc.updates.ready", args=[("version", text(Some(v), "versionName"))]),
        false,
      )
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
