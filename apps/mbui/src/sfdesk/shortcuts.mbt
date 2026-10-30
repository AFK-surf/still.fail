// ⌘/ (ember web/src/Shortcuts.tsx ShortcutsDialog, Shortcuts.css.ts): every shortcut, by where it works, the way to
// change them (快捷键, sfpages shortcuts.mbt) at its foot.

///|
/// ⌘/ (Shortcuts.tsx ShortcutsDialog): every shortcut, by where it works (the core's keymap, then those of one place,
/// not changed here), quiet words beside each; the way to change them at its foot (the desktop app's).
pub fn keys_dialog(c : @ui.Ctx, src : Source) -> Unit {
  let prefs = (src.topic)("prefs", {}).value
  let change = Ref(false)
  let footer : (() -> Unit)? = if @settings.keys_changeable(prefs) {
    Some(fn() {
      if @sf.button(c, @sf.t("web-main.shortcuts.change"), key="keys-dialog/change", tone=Ghost) {
        change.val = true
      }
    })
  } else {
    None
  }
  let d = @sf.dialog(
    c,
    "keys-dialog",
    wide.keys_open.get(),
    @sf.t("web-main.shortcuts.title"),
    close_label=@sf.t("common.close"),
    footer?,
    fn() {
      c.box(style=keys_sheet, fn() {
        for g in key_lines(prefs) {
          c.box(style=keys_group, fn() {
            c.box(style=keys_group_head, fn() { c.text(g.0, style=keys_group_title) |> ignore }) |> ignore
            for k in g.1 {
              c.box(style=keys_line, fn() {
                c.text(k.0, style=keys_line_words) |> ignore
                c.text(k.1, style=keys_line_keys) |> ignore
              })
              |> ignore
            }
          })
          |> ignore
        }
      })
      |> ignore
    },
  )
  wide.keys_open.set(d && !change.val)
  if change.val {
    open_settings_at(@settings.Route::Shortcuts)
  }
}

///|
/// What ⌘/ lists, each place's shortcuts with their keys in words: worked out as it is drawn, not while it is closed.
fn key_lines(prefs : Json?) -> Array[(String, Array[(String, String)])] {
  let (first_ws, last_ws) = @settings.workspace_keys(prefs)
  let groups = @settings.key_groups(prefs)
  groups.push((@sf.t("web-main.shortcuts.group.workspace"), [(@sf.t("web-main.shortcuts.switchWorkspace"), first_ws + " … " + last_ws)]))
  groups.push(
    (
      @sf.t("web-main.shortcuts.group.composer"),
      [
        (@sf.t("web-main.shortcuts.send"), "↩"),
        (@sf.t("web-main.shortcuts.newline"), "⇧↩"),
        (@sf.t("web-main.shortcuts.prevNextChat"), "↑ / ↓"),
      ],
    ),
  )
  groups.push(
    (
      @sf.t("web-main.shortcuts.group.preview"),
      [
        (@sf.t("web-main.shortcuts.prevNextImage"), "← / →"),
        (@sf.t("web-main.shortcuts.zoom"), "+ / -"),
        (@sf.t("web-main.shortcuts.fitActual"), "0 / 1"),
        (@sf.t("common.close"), "Esc"),
      ],
    ),
  )
  groups
}

///|
/// (Shortcuts.css.ts sheet: the groups 18 apart; group: its lines 2 apart, its title 4 over them)
// kept across runs: a value (no field of it changes)
let keys_sheet : @ui.Style = @ui.css("w=Full gap=S4_5")

///|
// kept across runs: a value (no field of it changes)
let keys_group : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let keys_group_head : @ui.Style = @ui.css("w=Full pb=S1")

///|
/// (groupTitle: 12, 500, muted)
// kept across runs: a value (no field of it changes)
let keys_group_title : @ui.TextStyle = @ui.text_style(size=Meta, leading=L4_75, weight=Medium, color=Muted, wrap=false)

///|
/// (line: what it does and its keys at the two ends, 16 apart, 4 over and under, the list's words)
// kept across runs: a value (no field of it changes)
let keys_line : @ui.Style = @ui.css("row w=Full py=S1 gap=S4 align=AEnd justify=JBetween")

///|
// kept across runs: a value (no field of it changes)
let keys_line_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5, color=Fg, wrap=false)

///|
/// (keys: muted, their digits as wide as each other)
// kept across runs: a value (no field of it changes)
let keys_line_keys : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)
