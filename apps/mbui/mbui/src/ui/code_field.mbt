// A one-time code typed into boxes (a sign-in's, a device paired's): one digit a box, the boxes in groups (3 and 3),
// a field over them, its words unseen, taking the typing (digits only, as many as there are boxes; a code pasted
// whole, its dashes and spaces left out). The box the next digit goes in is edged while the field has the keys; all
// are edged red while the code is said to be wrong and nothing is typed. The code is handed to the view once, on the
// frame it is complete, and again only once it has changed (a digit taken back and typed again counts): a view that
// sends it on as it is handed cannot send one code twice. A code refused is emptied (Ctx::clear_code_field) for the
// next try.

///|
priv struct CodeState {
  /// the digits typed
  mut value : String
  /// the complete code last handed to the view (None since it was not complete)
  mut handed : String?
}

///|
/// The code fields drawn, by id.
let code_fields : Map[Int, CodeState] = Map([])

///|
/// The code fields to empty as they are next built, by key (asked from anywhere: Ctx::clear_code_field).
let code_clears : Array[String] = []

///|
/// A code field (see the file's head): `length` boxes, `box_w` by `box_h`, `gap` apart, `group_gap` more between the
/// `groups` (their sizes in order; what they leave out is one more group). Its digits in `font_size` and `weight`, the
/// code face unless not `mono`, in `color` (`disabled_color` while not `enabled`, when typing changes nothing); its
/// boxes edged in `edge`, the next one's in `next_edge` while it has the keys, all in `wrong_edge` while `wrong` and
/// empty. It takes the keys as it first shows unless not `autofocus`. Some(code) on the frame a code is complete (once
/// a code: see the file's head); its editor is `key`'s (Ctx::editor_focused, Ctx::focus_editor).
pub fn Ctx::code_field(
  self : Ctx,
  key : String,
  length? : Int = 6,
  groups? : Array[Int] = [3, 3],
  wrong? : Bool = false,
  enabled? : Bool = true,
  autofocus? : Bool = true,
  box_w? : Double = 42.0,
  box_h? : Double = 52.0,
  radius? : Double = 12.0,
  gap? : Double = 8.0,
  group_gap? : Double = 8.0,
  font_size? : Double = 24.0,
  weight? : Int = 600,
  mono? : Bool = true,
  color? : Int64 = 0x1D1D1FFFL,
  disabled_color? : Int64 = 0x8E8E93FFL,
  edge? : Int64 = 0x1D1D1F2EL,
  next_edge? : Int64 = 0x1D1D1FFFL,
  wrong_edge? : Int64 = 0xFF3B30FFL,
) -> String? {
  let id = self.id(key)
  let st = match code_fields.get(id) {
    Some(s) => s
    None => {
      let s = { value: "", handed: None }
      code_fields[id] = s
      self.own(id)
      if autofocus {
        self.focus = id
      }
      s
    }
  }
  // emptied as asked (a code refused): the next try starts from nothing
  let mut cleared = false
  for k = code_clears.length() - 1; k >= 0; k = k - 1 {
    if code_clears[k] == key {
      code_clears.remove(k) |> ignore
      cleared = true
    }
  }
  if cleared {
    st.value = ""
    st.handed = None
    self.put_editor_text(key, "")
  }
  // what was typed, as the field holds it now: digits only, `length` at most (what else came is taken out of the
  // field); while it may not change, the field put back as it was
  let typed = match self.editors.get(id) {
    Some(e) => e.text
    None => st.value
  }
  let mut out : String? = None
  if !enabled {
    if typed != st.value {
      self.put_editor_text(key, st.value)
    }
  } else {
    let b = StringBuilder()
    let mut n = 0
    for ch in typed {
      if ch >= '0' && ch <= '9' && n < length {
        b.write_char(ch)
        n = n + 1
      }
    }
    let d = b.to_string()
    if d != typed {
      self.put_editor_text(key, d)
    }
    st.value = d
    if n < length {
      st.handed = None
    } else if st.handed != Some(d) {
      st.handed = Some(d)
      out = Some(d)
    }
  }
  // where a group ends (the room between groups before the box after it)
  let ends : Array[Int] = []
  let mut at = 0
  for n in groups {
    at = at + n
    if at < length {
      ends.push(at)
    }
  }
  let digits = st.value.to_array()
  let focused = self.focus == id
  let next = if digits.length() < length - 1 { digits.length() } else { length - 1 }
  self.box(align=ACenter, fn() {
    self.box(dir=Row, gap~, align=ACenter, fn() {
      for i in 0..<length {
        if ends.contains(i) {
          self.box(w=Px(group_gap), fn() {  }) |> ignore
        }
        let edge_c = if wrong && st.value == "" {
          wrong_edge
        } else if enabled && focused && i == next {
          next_edge
        } else {
          edge
        }
        self.box(
          w=Px(box_w),
          h=Px(box_h),
          radius~,
          border=1.0,
          border_color=edge_c,
          align=ACenter,
          justify=JCenter,
          fn() {
            if i < digits.length() {
              self.rich(
                [span(digits[i].to_string(), mono~)],
                size=font_size,
                weight~,
                color=if enabled { color } else { disabled_color },
                wrap=false,
              )
              |> ignore
            }
          },
        )
        |> ignore
      }
    })
    |> ignore
    // the field itself over the boxes, its words unseen: a tap there gives it the keys
    self.layer(fn() {
      self.editor(
        key,
        font_size~,
        max_lines=1,
        plain=true,
        line=box_h,
        color=0x00000000L,
        placeholder_color=0x00000000L,
        caret_color=0x00000000L,
        enter_sends=true,
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
  out
}

///|
/// Empties the code field `key` as it is next built, the code it handed forgotten (a code refused: typed again, it is
/// handed again). From anywhere: an answer that comes between frames, a field not shown now.
pub fn Ctx::clear_code_field(self : Ctx, key : String) -> Unit {
  if !code_clears.contains(key) {
    code_clears.push(key)
  }
  self.read_changed("clear_code_field \"\{key}\"")
}
