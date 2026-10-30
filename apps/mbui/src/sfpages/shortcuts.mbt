// 快捷键 (ember web/src/Shortcuts.tsx ShortcutsPage, Shortcuts.css.ts), one page in every frame: each action of the
// core's keymap (the prefs' `keymap`) gets new keys by pressing them (`keys.set`). ⌘/'s list of them is the shell's
// (sfdesk shortcuts.mbt keys_dialog).

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
/// 快捷键 (Shortcuts.tsx ShortcutsPage): each group's actions, their keys; pressed, the next key press is its new keys
/// (Esc leaves them, ⌫ clears them; keys another action had are moved here, said so); 恢复默认 an action's own again,
/// 全部恢复默认 every one's. Kept on this device.
pub fn shortcuts_page(c : @ui.Ctx, core : Core, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let prefs = (core.topic)("prefs", Map::new()).value
  let keymap = field(prefs, "keymap")
  // recording: the next key press
  let recording = keys_recording.get()
  if recording != "" {
    for k in c.keys() {
      let (code, mods, _) = k
      if code == @ui.key_escape && mods == 0 {
        keys_recording.set("")
        break
      }
      if code == 1 && mods == 0 {
        // ⌫: none
        c.after_build("keys-clear", fn() { set_keys(core, Some(recording), Json::array([])) })
        keys_recording.set("")
        break
      }
      match binding_of(code, mods) {
        Some(b) => {
          c.after_build("keys-set", fn() { set_keys(core, Some(recording), Json::array([Json::string(b)])) })
          keys_recording.set("")
          break
        }
        None => ()
      }
    }
  }
  let listed = key_actions(prefs).filter(fn(a) { flag(Some(a), "listed") })
  let any = listed.iter().any(fn(a) { flag(Some(a), "changed") })
  let blocks : Array[() -> Unit] = []
  for i, g in items(keymap, "groups") {
    let group = text(Some(g), "group")
    blocks.push(fn() {
      let rows = fn() {
        c.box(style=if look is Narrow { keys_rows_carded } else { keys_rows }, fn() {
          for a in listed {
            if text(Some(a), "group") == group {
              shortcut_row(c, core, a)
            }
          }
        })
        |> ignore
      }
      let reset_all = fn() {
        if keys_toggle(c, "keys-reset-all", @sf.t("web-main.shortcuts.resetAll")) {
          c.tell("keys-reset-all", fn() { set_keys(core, None, Json::null()) })
        }
      }
      match look {
        Wide =>
          @sf.section(
            c,
            text(Some(g), "name"),
            note=if i == 0 { @sf.t("web-main.shortcuts.hint") } else { "" },
            actions?=if i == 0 && any { Some(reset_all) } else { None },
            rows,
          )
        // narrow: its heading, its rows on a card, what the keys do under the first
        Narrow => {
          @sf.heading(c, text(Some(g), "name"))
          @sf.page_card(c, rows)
          if i == 0 {
            @sf.page_note(c, @sf.t("web-main.shortcuts.hint"))
            if any {
              c.box(style=narrow_note_box, reset_all) |> ignore
            }
          }
        }
      }
    })
  }
  @sf.page(c, on_back=core.pop, frame~, "shortcuts", @sf.t("web-main.shortcuts.title"), blocks)
}

///|
/// An action's row (Shortcuts.css.ts row): its name, 恢复默认 once changed, its keys on a button that, pressed, records
/// new ones.
fn shortcut_row(c : @ui.Ctx, core : Core, a : Json) -> Unit {
  let av = Some(a)
  let action = text(av, "action")
  let on = keys_recording.get() == action
  c.box(style=shortcut_row_box, fn() {
    c.box(style=keys_row_label, fn() { c.text(text(av, "name"), style=keys_row_words) |> ignore }) |> ignore
    if flag(av, "changed") && keys_toggle(c, "keys-reset/" + action, @sf.t("web-main.shortcuts.reset")) {
      c.tell("keys-reset/" + action, fn() { set_keys(core, Some(action), Json::null()) })
    }
    let id = c.id("keys/" + action)
    c.focusable(id)
    let none = strings(av, "keys").length() == 0
    c.box(
      id~,
      style=if on { keys_record_on } else { keys_record },
      fn() {
        c.text(if on { @sf.t("web-main.shortcuts.recording") } else { text(av, "text") }, style=if on {
          keys_record_on_words
        } else if none {
          keys_record_none
        } else {
          keys_record_words
        })
        |> ignore
      },
    )
    |> ignore
    if hit(c, id) {
      keys_recording.set(if on { "" } else { action })
    }
  })
  |> ignore
}

///|
/// A quiet word to press (controls.css.ts textToggle): 12 muted, the words' colour pointed at. Whether it was pressed.
fn keys_toggle(c : @ui.Ctx, key : String, words : String) -> Bool {
  let id = c.id(key)
  c.focusable(id)
  c.box(id~, style=keys_toggle_box, fn() {
    c.text(words, style=if c.lit(id) { keys_toggle_hot } else { keys_toggle_words }) |> ignore
  })
  |> ignore
  hit(c, id)
}

///|
// kept across runs: a value (no field of it changes)
let keys_rows : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
/// The rows on a card (narrow): the first's and the last's keys in its corners as far from both its edges.
// kept across runs: a value (no field of it changes)
let keys_rows_carded : @ui.Style = keys_rows.then(@sf.card_rows_reach(keys_row_h, keys_record_h))

///|
/// (Shortcuts.css.ts row: 40 high at least, 8 apart, the list's words)
// kept across runs: a value (no field of it changes)
let shortcut_row_box : @ui.Style = @ui.style(row=true, w=Full, min_h=Fixed(keys_row_h), gap=S2, align=ACenter)

///|
let keys_row_h : Double = 40.0

///|
// kept across runs: a value (no field of it changes)
let keys_row_label : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let keys_row_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5, color=Fg, w=Full)

///|
/// Its keys (Shortcuts.css.ts record): 120 wide at least, 30 high, 12 in, the ladder's small block's corner (the first's
/// and the last's in the card's corners on its words' inset, concentric there: every one alike), the hover ground (and
/// the pointer's over it, pointed at: docs/ui-panels.md 悬停), in the middle; none, subtle; recording, the accent's
/// ground and words.
// kept across runs: a value (no field of it changes)
let keys_record : @ui.Style = @ui.style(
  row=true,
  min_w=Fixed(keys_record_w),
  h=Fixed(keys_record_h),
  px=S3,
  radius=@sf.small_radius,
  bg=Hover,
  align=ACenter,
  justify=JCenter,
  hovered=@ui.patch(bg=Hover),
)

///|
let keys_record_w : Double = 120.0

///|
let keys_record_h : Double = 30.0


///|
// kept across runs: a value (no field of it changes)
let keys_record_on : @ui.Style = keys_record.then(@ui.css("bg=AccentBg"))

///|
// kept across runs: a value (no field of it changes)
let keys_record_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let keys_record_none : @ui.TextStyle = keys_record_words.then(@ui.text_style(color=Subtle))

///|
// kept across runs: a value (no field of it changes)
let keys_record_on_words : @ui.TextStyle = keys_record_words.then(@ui.text_style(color=AccentText))

///|
/// (controls.css.ts textToggle: 2 by 4 in)
// kept across runs: a value (no field of it changes)
let keys_toggle_box : @ui.Style = @ui.css("px=S1 py=S0_5")

///|
// kept across runs: a value (no field of it changes)
let keys_toggle_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L4_75, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let keys_toggle_hot : @ui.TextStyle = keys_toggle_words.then(@ui.text_style(color=Fg))

///|
// kept across runs: a value (no field of it changes)
let keys_reset_box : @ui.Style = @ui.css("px=S2 py=S1 radius=Base hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let keys_reset_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)


