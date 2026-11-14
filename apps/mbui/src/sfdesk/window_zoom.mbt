// The size of the whole window, kept on this device. The same actions are available from the menu bar and the keys.

///|
fn zoom_at(src : Source) -> Int {
  let kept = @settings.pref_from(src.topic("prefs", {}).get().value, "windowZoom")
  @sfbase.window_zoom_levels.search_by(fn(z) { z.0 == kept }).unwrap_or(5)
}

///|
fn zoom_do(src : Source, action : String) -> Unit {
  let window_zoom_levels = @sfbase.window_zoom_levels
  let at = zoom_at(src)
  let next = if action == "zoom.reset" {
    5
  } else if action == "zoom.in" {
    if at < window_zoom_levels.length() - 1 { at + 1 } else { at }
  } else if action == "zoom.out" {
    if at > 0 { at - 1 } else { at }
  } else {
    at
  }
  let (value, zoom) = window_zoom_levels[next]
  @ui.set_window_zoom(zoom)
  if next != at {
    @settings.set_pref_with(src.call, fn(words) { toast_later(words) }, "windowZoom", value)
  }
}

///|
pub fn window_zoom_keys(c : @ui.Ctx, src : Source) -> Unit {
  if !@ui.window_zoom_supported() {
    return
  }
  let prefs = src.topic("prefs", {}).get().value
  @ui.set_window_key_handler(fn(code, mods) {
    if @signals.untracked(fn() { @settings.keys_recording.get() }) != "" {
      return false
    }
    guard @settings.binding_of(code, mods) is Some(binding) else { return false }
    for action in ["zoom.in", "zoom.out", "zoom.reset"] {
      if @settings.keys_of(prefs, action).contains(binding) {
        zoom_do(src, action)
        return true
      }
    }
    false
  })
  let zoom = @sfbase.window_zoom_levels[zoom_at(src)].1
  if @ui.window_zoom() != zoom {
    c.after_build("window-zoom", fn() { @ui.set_window_zoom(zoom) })
  }
}

///|
/// The window's size as actions of node `v` (the window's root): chosen from the menu bar (its keys are the window's
/// own, taken before anything else: window_zoom_keys), done at that moment.
pub fn zoom_actions(v : @view.View, src : Source) -> Unit {
  for action in ["zoom.in", "zoom.out", "zoom.reset"] {
    v.on_action(action, fn(_) {
      guard @ui.window_zoom_supported() else { return false }
      zoom_do(src, action)
      true
    })
    |> ignore
  }
}
