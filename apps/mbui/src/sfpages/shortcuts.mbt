// 快捷键, one page made once on every screen: each action
// of the core's keymap (the prefs' `keymap`) gets new keys by pressing them (`keys.set`). ⌘/'s list of them is the
// shell's (sfdesk shortcuts.mbt keys_dialog).

///|
/// An action's keys changed (`keys.set`: none, its own again; no action, every one's), what the core says of it
/// (keys another action had, moved here) said.
fn set_keys(core : Core, action : String?, keys : Json) -> Unit {
  let params = match action {
    Some(a) => obj([("action", str(a)), ("keys", keys)])
    None => obj([])
  }
  (core.call)("keys.set", params, fn(r) {
    match r {
      Ok(v) =>
        match text(Some(v), "said") {
          "" => ()
          said => (core.say)(said)
        }
      Err(_) => ()
    }
  })
}

///|
/// 快捷键 made once as nodes of the window's tree (page_node, laid out by the `width` its
/// frame gives it, narrow where none is given): first how a message is sent (Enter, or ⌘Enter: the prefs' `sendKey`,
/// the keys of both said under it), then each group of the core's keymap a section, its actions' rows
/// (keys_rows_node), what the keys do said under the first, and 全部恢复默认 there once any was changed. An action's
/// keys pressed, the next key press is its new keys: Esc leaves them, ⌫ clears them, keys another action had are moved
/// here (the core says so); pressed again, or this page no longer the one on top of its stack (`active`: another put
/// over it, it gone back off), it records none. 恢复默认 an action's own again. Kept on this device. What it says of
/// itself told `said`.
pub fn shortcuts_node(
  v : @view.View,
  core : Core,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  active~ : () -> Bool,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
) -> Unit {
  // (what this page records, while it is the one that does: another made of the same page its own)
  keys_recorders.val += 1
  let me = keys_recorders.val
  let record = fn(action : String) {
    keys_recorder.val = me
    keys_recording.set(action)
  }
  let stop = fn() {
    if keys_recorder.val == me {
      keys_recording.set("")
    }
  }
  let prefs = fn() { (core.topic)("prefs", Map([])).get().value }
  let keymap = fn() { field(prefs(), "keymap") }
  let listed = fn() { key_actions(prefs()).filter(fn(a) { flag(Some(a), "listed") }) }
  let groups = fn() { items(keymap(), "groups") }
  let any = fn() { listed().iter().any(fn(a) { flag(Some(a), "changed") }) }
  // how the composer sends: one of two ways (`sendKey`), not keys of its own
  let send = fn() { field(keymap(), "send") }
  let sending = fn(v : @view.View) {
    @sf.setting_choice_node(
      v,
      fn() { @sf.t("web-main.shortcuts.sending") },
      fn() { items(send(), "choices").map(fn(c) { text(Some(c), "name") }) },
      fn() { items(send(), "choices").search_by(fn(c) { text(Some(c), "by") == text(send(), "by") }).unwrap_or(0) },
      fn(i) {
        let by = text(@signals.untracked(fn() { items(send(), "choices") }).get(i), "by")
        @settings.set_pref(core, "sendKey", if by == "mod" { "mod" } else { "" })
      },
      note=fn() { text(send(), "text") },
      alone=true,
    )
  }
  // (the next key press, while one records: none of it anything else's (pressed, window_zoom's stand aside))
  v.on_key(fn(k) {
    let recording = keys_recording.untracked()
    if recording == "" || keys_recorder.val != me {
      return false
    }
    if k.code == @ui.key_escape && k.mods == 0 {
      stop()
      return true
    }
    // ⌫: none
    if k.code == 1 && k.mods == 0 {
      stop()
      set_keys(core, Some(recording), Json::array([]))
      return true
    }
    match binding_of(k.code, k.mods) {
      Some(b) => {
        stop()
        set_keys(core, Some(recording), Json::array([Json::string(b)]))
        true
      }
      // (a modifier alone: the keys still to come)
      None => false
    }
  })
  |> ignore
  // (no longer on top of its stack, or let go: what it records, none; another's left as it is)
  v.reacts(active, fn(on) { if !on { stop() } })
  v.owns(stop) |> ignore
  @sf.page_node(
    v,
    fn() { @sf.t("web-main.shortcuts.title") },
    fn() {
      let keys = groups().mapi(fn(i, g) { "\{i}/" + text(Some(g), "group") })
      // (a core before the choice says none)
      if send() is Some(_) {
        keys.insert(0, "send")
      }
      keys
    },
    fn(b, key) {
      if key == "send" {
        sending(b)
        return
      }
      let i = @string.parse_int(key[:key.find("/").unwrap_or(0)]) catch { _ => 0 }
      let group = fn() { text(groups().get(i), "group") }
      let first = i == 0
      @sf.section_node(
        b,
        fn() { text(groups().get(i), "name") },
        fn(s) {
          @sf.keys_rows_node(s, fn(l) {
            l.each(fn() { listed().filter(fn(a) { text(Some(a), "group") == group() }) }, fn(a) { text(Some(a), "action") }, fn(
              r,
              a,
            ) {
              let action = text(Some(a.untracked()), "action")
              @sf.keys_row_node(
                r,
                fn() { text(Some(a.get()), "name") },
                fn() { text(Some(a.get()), "text") },
                fn() { strings(Some(a.get()), "keys").length() == 0 },
                fn() { keys_recording.get() == action && keys_recorder.val == me },
                fn() {
                  if keys_recording.untracked() == action && keys_recorder.val == me {
                    stop()
                  } else {
                    record(action)
                  }
                },
                fn() { flag(Some(a.get()), "changed") },
                fn() { set_keys(core, Some(action), Json::null()) },
                fn() { @sf.t("web-main.shortcuts.reset") },
                fn() { @sf.t("web-main.shortcuts.recording") },
              )
            })
          })
        },
        about=fn() { if first { @sf.t("web-main.shortcuts.hint") } else { "" } },
        actions?=if first {
          Some((any, fn(a) { @sf.text_toggle_node(a, fn() { @sf.t("web-main.shortcuts.resetAll") }, fn() { set_keys(core, None, Json::null()) }) }))
        } else {
          None
        },
      )
    },
    on_back~,
    frame~,
    said?,
    width?,
  )
}

///|
/// The page made once that records now (shortcuts_node's own count, what keys_recording says is its), and how many
/// were made.
// kept across runs: said as a page records; the count goes on
let keys_recorder : Ref[Int] = Ref(0)

///|
// kept across runs: it goes on counting
let keys_recorders : Ref[Int] = Ref(0)
