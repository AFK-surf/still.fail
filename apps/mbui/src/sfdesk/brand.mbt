// The desktop app's newer build, offered over the sidebar's top (brand.tsx UpdateButton, brand.css.ts
// sidebarUpdate): how an update stands is both frames' (sfbase updates.mbt).

///|
/// Whether the desktop app has a newer build to offer, or one on its way in (brand.tsx UpdateButton: the app's update
/// state, none while there is none).
fn update_shown() -> Bool {
  update.available is Some(_) || update_busy() || update.phase == "failed"
}

///|
/// The desktop app's newer build (brand.tsx UpdateButton, brand.css.ts sidebarUpdate): 更新 at the open sidebar's top
/// right, 12 in from its edge, or past the rail (and the window's buttons) when it is closed, moved with it; how far it
/// has downloaded, 正在重启 while it is put in place, 更新失败，重试 when it failed (why, its tip). Pressed, the build is
/// downloaded and the app restarts as it. `top`: the system's bars over the window (a phone's status bar), which take
/// what is pressed under them: it goes below them. `x`: how far the tape is moved (laid out Medium).
fn update_button(
  c : @ui.Ctx,
  src : Source,
  bar : Bool,
  s : Double,
  inset : Bool,
  top : Double,
  x : Double,
) -> Unit {
  let (label, tip, busy) = update_said()
  let id = c.id("side/update")
  // open, its end 12 in from the sidebar's (translateX(-100%)); closed, its start past the rail and the window's buttons
  let width = match c.laid_size(id) {
    Some((w, _)) => w
    None => 0.0
  }
  // (on the tape, moved with it: x)
  let (left, tx) = if bar {
    (if inset { update_closed_inset } else { update_closed_in }, 0.0)
  } else {
    (rail_w + s - bar_in, x - width)
  }
  c.cursor(id, Hand)
  c.layer(fn() {
    let b = c.box(style=update_at, moves="side-update", left~, top=top + update_top, tx~, id~, fn() {
      @sf.pill(c, label, tone=Accented)
    })
    c.semantics(b, Button, id~, label~)
  })
  |> ignore
  @sf.tip(c, "side/update-tip", id, tip, side=Bottom)
  if c.clicked(id) && !busy {
    update_install(src)
  }
}

///|
/// 更新 in the tape's sidebar's first row (新建对话's, before the filter): as large as the filter beside it, its words in
/// it, the row where it is whether there is one or not (pengxiao, 2026-10-25: its own row over the sidebar pushed the
/// sidebar down, and its pill was small for a finger).
fn update_in_row(c : @ui.Ctx, src : Source) -> Unit {
  let t = @sf.theme()
  let (label, tip, busy) = update_said()
  let id = c.id("side/update")
  c.cursor(id, Hand)
  let b = c.box(style=update_in_row_box.then(@ui.style(bg=Data(t.p.accent_bg))), id~, fn() {
    c.text(label, style=update_in_row_words.then(@ui.text_style(color=Data(t.p.accent_text)))) |> ignore
  })
  c.semantics(b, Button, id~, label~)
  @sf.tip(c, "side/update-tip", id, tip, side=Bottom)
  if c.clicked(id) && !busy {
    update_install(src)
  }
}

///|
/// 更新 in the first row: a capsule as high as the filter (32), its words 12 in.
// kept across runs: a value (no field of it changes)
let update_in_row_box : @ui.Style = @ui.css("row h=S8 px=S3 radius=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let update_in_row_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Semibold, wrap=false)

///|
/// What 更新 says, its tip, and whether it is under way.
fn update_said() -> (String, String, Bool) {
  // (its phase as the host says it, what went wrong said once: updates.mbt)
  update_progress() |> ignore
  let v = try Some(@json.parse(@ui.update_state())) catch { _ => None }
  let busy = update_busy()
  let label = match update.phase {
    "downloading" | "retrying" =>
      @sf.t("web-main.appUpdate.downloading", args=[("percent", dmax(0.0, number(v, "percent")).to_int().to_string())])
    "installing" => @sf.t("web-main.appUpdate.restarting")
    "failed" => @sf.t("web-main.appUpdate.failed")
    _ => @sf.t("web-main.versions.update")
  }
  let tip = if update.phase == "failed" {
    update_error(text(v, "error"))
  } else {
    @sf.t("web-main.appUpdate.title", args=[("version", text(update.available, "versionName")), ("app", "still.fail")])
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
/// 更新's box: its pill's size.
// kept across runs: a value (no field of it changes)
let update_at : @ui.Style = @ui.css("row")
