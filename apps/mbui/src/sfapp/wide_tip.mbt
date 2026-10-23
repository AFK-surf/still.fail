// Tips in the wide frame: the library's (@sf.tip, web/ui parts.tsx Tip), none on a phone. The keys an action has are
// the core's prefs' keymap (@sf.set_shortcuts, said as the app builds: app.mbt view).

///|
/// `id`'s tip, saying `text` (nothing when empty); with `action`, the keys set for it after (settings' keymap).
fn wide_tip(c : @ui.Ctx, key : String, id : Int, text : String, action? : String = "") -> Unit {
  if wide_on.val {
    @sf.tip(c, key, id, text, shortcut=action)
  }
}

///|
/// An action's keys, as the core's prefs set them (the settings' keymap), "" none.
fn tip_keys_of(action : String) -> String {
  match link_src.val {
    Some(src) => @settings.keys_text((src.topic)("prefs", {}).value, action)
    None => ""
  }
}
