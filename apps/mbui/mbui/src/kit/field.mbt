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
/// How a field stands, for its look: the id its frame takes (what the pointer is over), how wide it is asked to be,
/// written in (its editor has the keys), pointed at, disabled, said to be wrong.
pub(all) struct FieldState {
  id : Int
  w : @ui.Size
  focused : Bool
  hovered : Bool
  disabled : Bool
  invalid : Bool
}

///|
/// A one-line field (see the file's head), its editor `key`'s, `placeholder` while empty, `w` wide; `field`: what it
/// holds, the view's own to read and write (mbui's Field), else the editor's. `secret`: drawn as dots; `enter_sends`:
/// Enter is handed on (else a new line is not taken either: one line); `size` and `line` the words' size and line
/// (0: the theme's); `look` draws its frame round the editor (`editor`, built where the look says), by default the pill.
pub fn text_field(
  c : @ui.Ctx,
  key : String,
  placeholder? : String = "",
  w? : @ui.Size = Fill(1.0),
  disabled? : Bool = false,
  secret? : Bool = false,
  enter_sends? : Bool = true,
  size? : Double = 0.0,
  line? : Double = 0.0,
  look? : (@ui.Ctx, FieldState, () -> Unit) -> Unit = pill_look,
  field? : @ui.Field,
) -> Field {
  let mut out = { text: "", submitted: false }
  pill_field(
    c,
    key,
    w,
    disabled,
    secret,
    placeholder,
    fn(e) { out = { text: e.text, submitted: e.submitted is Some(_) } },
    fn() {  },
    enter_sends~,
    size~,
    line~,
    look~,
    field?,
  )
  out
}

///|
/// The field `key`'s frame round its editor (`secret`: drawn as dots), then what `after` builds in it (a button), as
/// `look` draws it; `got` is given what the editor reports; `invalid`: edged in the danger colour.
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
  enter_sends? : Bool = true,
  size? : Double = 0.0,
  line? : Double = 0.0,
  look? : (@ui.Ctx, FieldState, () -> Unit) -> Unit = pill_look,
  field? : @ui.Field,
) -> Unit {
  let t = c.theme()
  let fid = c.id(key + "/field")
  let st = { id: fid, w, focused: c.editor_focused(key), hovered: c.lit(fid), disabled, invalid }
  look(c, st, fn() {
    got(
      c.editor(
        key,
        placeholder~,
        w=Fill(1.0),
        max_lines=1,
        plain=true,
        secret~,
        enter_sends~,
        font_size=if size > 0.0 { size } else { t.font + 1.0 },
        line~,
        color=t.fg,
        placeholder_color=t.subtle,
        caret_color=t.accent,
        field?,
      ),
    )
    after()
  })
}

///|
/// The default look (still.fail's): a pill `control_h` high, a line round it that darkens pointed at and written in
/// (the danger colour while wrong), its words 16 in, a button at its end 6 in.
pub fn pill_look(c : @ui.Ctx, s : FieldState, editor : () -> Unit) -> Unit {
  let t = c.theme()
  let edge = if s.invalid {
    t.danger
  } else if s.focused || s.hovered {
    t.field_hover
  } else {
    t.border
  }
  c.box(
    id=s.id,
    dir=Row,
    w=s.w,
    h=Px(t.control_h),
    radius=t.control_h / 2.0,
    border=1.0,
    border_color=edge,
    bg=t.bg,
    pl=16.0,
    // a button at its end stands 6 in, as from its top and bottom (password.mbt)
    pr=6.0,
    gap=8.0,
    align=ACenter,
    opacity=if s.disabled { 0.45 } else { 1.0 },
    editor,
  )
  |> ignore
}
