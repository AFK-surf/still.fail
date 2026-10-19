// A password field with a button that shows it (Radix's Password Toggle Field): the words are the field's (a secret
// editor's: dots, never copied or cut out, while hidden), whether they show is the view's. The button, a tap, a
// click, or Enter or Space with its focus turn them; it is named for what it does (显示 or 隐藏 by default).

///|
/// What a password field gives back: its words, whether they show now (what the view keeps), and what happened to the
/// button.
pub(all) struct Password {
  text : String
  visible : Bool
  toggle : @ui.Response
}

///|
/// A password field (see the file's head), its editor `key`'s, showing its words if `visible`; `placeholder` while
/// empty; the button named `show_label` or `hide_label` for the semantics tree.
pub fn password_field(
  c : @ui.Ctx,
  key : String,
  visible : Bool,
  placeholder? : String = "",
  w? : @ui.Size = Fill(1.0),
  show_label? : String = "显示",
  hide_label? : String = "隐藏",
  disabled? : Bool = false,
) -> Password {
  let t = c.theme()
  let bid = c.id(key + "/toggle")
  let r = c.interact(bid, disabled~)
  let shows = if r.clicked { !visible } else { visible }
  let mut words = ""
  pill_field(c, key, w, disabled, !shows, placeholder, fn(e) { words = e.text }, fn() {
    let label = if shows { hide_label } else { show_label }
    let i = c.box(id=if disabled { 0 } else { bid }, padx=8.0, pady=4.0, radius=12.0, bg=pick(r.hovered, t.hover, 0L), fn() {
      c.text(label, size=t.font_sm, color=if r.hovered { t.fg } else { t.muted }, wrap=false) |> ignore
      focus_ring(c, r.focus_shown, r.rect, 12.0)
    })
    c.semantics(i, Button, id=bid, label~, pressed=shows, disabled~, actions=pick(disabled, [], [Activate]))
  })
  { text: words, visible: shows, toggle: r.changed_to(told(c, shows != visible)) }
}
