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
/// How many times a code field was asked to be emptied (Ctx::clear_code_field), read by each as it is built: one kept
/// as it was drawn (a list's row, a part, kept_part.mbt) is built again to empty it.
// kept across runs: it only counts on
let code_clears_said : @signals.Signal[Int] = @signals.signal(0)

///|
/// A code field (see the file's head): `length` boxes, `box_w` by `box_h`, `gap` apart, `group_gap` more between the
/// `groups` (their sizes in order; what they leave out is one more group). Its digits in `font_size` and `weight`, the
/// code face unless not `mono`, in `color` (`disabled_color` while not `enabled`, when typing changes nothing); its
/// boxes edged in `edge`, the next one's in `next_edge` while it has the keys, all in `wrong_edge` while `wrong` and
/// empty. Narrower than one row of boxes, they are drawn smaller (`min_scale` of their size at the least), then a row
/// for each group. It takes the keys as it first shows unless not `autofocus`. Some(code) on the frame a code is complete (once
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
  min_scale? : Double = 0.8,
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
        self.focus_moved(id)
      }
      s
    }
  }
  // emptied as asked (a code refused): the next try starts from nothing
  code_clears_said.get() |> ignore
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
  let focused = self.has_focus(id)
  let next = if digits.length() < length - 1 { digits.length() } else { length - 1 }
  // As wide as the room it is given (read back): the boxes, the room between them and the digits drawn smaller where
  // one row of them is wider than that (an iPhone Duo's outer screen, a narrow pane), down to `min_scale`; narrower
  // still, a row for each group (3 over 3), as large as that room lets them be, never larger than asked.
  let room_id = self.id(key + "/room")
  let room = match self.laid_size(room_id) {
    Some((w, _)) => w
    None => 0.0
  }
  let one_row = length.to_double() * box_w +
    (length - 1 + ends.length()).to_double() * gap +
    ends.length().to_double() * group_gap
  let widest = {
    let mut most = 0
    let mut from = 0
    for e in ends {
      most = if e - from > most { e - from } else { most }
      from = e
    }
    if length - from > most {
      length - from
    } else {
      most
    }
  }
  let group_row = widest.to_double() * box_w + (widest - 1).to_double() * gap
  let fits = room <= 0.0 || one_row * min_scale <= room
  let scale = if room <= 0.0 {
    1.0
  } else {
    let s = room / (if fits { one_row } else { group_row })
    if s < 1.0 {
      s
    } else {
      1.0
    }
  }
  let bw = box_w * scale
  let bh = box_h * scale
  let g = gap * scale
  let digit = fn(i : Int) {
    let edge_c = if wrong && st.value == "" {
      wrong_edge
    } else if enabled && focused && i == next {
      next_edge
    } else {
      edge
    }
    self.box(
      w=Px(bw),
      h=Px(bh),
      radius=radius * scale,
      border=1.0,
      border_color=edge_c,
      align=ACenter,
      justify=JCenter,
      fn() {
        if i < digits.length() {
          self.rich(
            [span(digits[i].to_string(), mono~)],
            size=font_size * scale,
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
  // (one row, the groups apart; or a row a group, one over another)
  let rows : Array[(Int, Int)] = []
  if fits {
    rows.push((0, length))
  } else {
    let mut from = 0
    for e in ends {
      rows.push((from, e))
      from = e
    }
    rows.push((from, length))
  }
  self.box(style=code_room, id=room_id, fn() {
    self.box(gap=g, align=ACenter, fn() {
      for r in rows {
        let (a, b) = r
        self.box(dir=Row, gap=g, align=ACenter, fn() {
          for i in a..<b {
            if i > a && ends.contains(i) {
              self.box(w=Px(group_gap * scale), fn() {  }) |> ignore
            }
            digit(i)
          }
        })
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
        line=bh,
        color=0x00000000L,
        placeholder_color=0x00000000L,
        caret_color=0x00000000L,
        enter_sends=true,
        ime_action=@hostapi.ime_action_number,
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
  out
}

///|
/// The room a code field is given: as wide as what holds it (read back for its boxes' size), them in its middle.
// kept across runs: a value (no field of it changes)
let code_room : Style = css("w=Full align=ACenter")

///|
/// Empties the code field `key` as it is next built, the code it handed forgotten (a code refused: typed again, it is
/// handed again). From anywhere: an answer that comes between frames, a field not shown now.
pub fn Ctx::clear_code_field(self : Ctx, key : String) -> Unit {
  if !code_clears.contains(key) {
    code_clears.push(key)
  }
  code_clears_said.set(@signals.untracked(fn() { code_clears_said.get() }) + 1)
  self.read_changed("clear_code_field \"\{key}\"")
}
