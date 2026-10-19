// A one-line field (still.fail's: not one of Radix's, what its forms put a label to): a pill, a line round it that
// darkens pointed at and written in, its words the editor's (`key`'s), what it holds the view's to read. A password
// field (password.mbt) is one with a button in it.

///|
/// What a field gives back: its words now, and whether Enter was pressed in it (handed on).
pub(all) struct Field {
  text : String
  submitted : Bool
}

///|
/// A one-line field (see the file's head), its editor `key`'s, `placeholder` while empty, `w` wide.
pub fn text_field(
  c : @ui.Ctx,
  key : String,
  placeholder? : String = "",
  w? : @ui.Size = Fill(1.0),
  disabled? : Bool = false,
) -> Field {
  let mut out = { text: "", submitted: false }
  pill_field(c, key, w, disabled, false, placeholder, fn(e) { out = { text: e.text, submitted: e.submitted is Some(_) } }, fn() {  })
  out
}

///|
/// The pill of field `key` round its editor (`secret`: drawn as dots), then what `after` builds in it (a button);
/// `got` is given what the editor reports; `invalid`: edged in the danger colour.
fn pill_field(
  c : @ui.Ctx,
  key : String,
  w : @ui.Size,
  disabled : Bool,
  secret : Bool,
  placeholder : String,
  got : (@ui.EditorResult) -> Unit,
  after : () -> Unit,
  invalid? : Bool = false,
) -> Unit {
  let t = c.theme()
  let fid = c.id(key + "/field")
  let edge = if invalid {
    t.danger
  } else if c.editor_focused(key) || c.hovered(fid) {
    t.field_hover
  } else {
    t.border
  }
  c.box(
    id=fid,
    dir=Row,
    w~,
    h=Px(t.control_h),
    radius=t.control_h / 2.0,
    border=1.0,
    border_color=edge,
    bg=t.bg,
    pl=16.0,
    pr=8.0,
    gap=8.0,
    align=ACenter,
    opacity=if disabled { 0.45 } else { 1.0 },
    fn() {
      got(
        c.editor(
          key,
          placeholder~,
          w=Fill(1.0),
          max_lines=1,
          plain=true,
          secret~,
          enter_sends=true,
          font_size=t.font + 1.0,
          color=t.fg,
          placeholder_color=t.subtle,
          caret_color=t.accent,
        ),
      )
      after()
    },
  )
  |> ignore
}
