// A six-digit code as nodes of the window's tree. The Field owns its editor so an answer arriving between frames can
// clear it; the node owns its focus, drawing and the once-per-complete-code notification.

///|
/// A code's editor and the value already handed on. The same instance is kept while its node is on screen.
pub struct CodeField {
  priv field : Field
  priv accepted : Ref[String]
  priv handed : Ref[String?]
}

///|
pub fn CodeField::new() -> CodeField {
  { field: Field::new(), accepted: Ref(""), handed: Ref(None) }
}

///|
/// Empty a refused code, including while it is disabled, so the same code can be entered again.
pub fn CodeField::clear(self : CodeField) -> Unit {
  self.accepted.val = ""
  self.handed.val = None
  self.field.set("")
}

///|
pub fn CodeField::text(self : CodeField) -> String {
  self.field.text()
}

///|
/// Six boxes in groups of three, editing `code`. Only digits are kept; `complete` is called once for each completed
/// value, again after it was made incomplete or cleared. While disabled the previous value is retained. It takes the
/// focus on opening and releases it with its node. Its boxes scale to their room and then wrap into two groups.
pub fn code_field_node(
  parent : @view.View,
  code : CodeField,
  complete : (String) -> Unit,
  wrong? : () -> Bool = fn() { false },
  enabled? : () -> Bool = fn() { true },
  color? : () -> Int64 = fn() { 0x1D1D1FFFL },
  disabled_color? : () -> Int64 = fn() { 0x8E8E93FFL },
  edge? : () -> Int64 = fn() { 0x1D1D1F2EL },
  next_edge? : () -> Int64 = fn() { 0x1D1D1FFFL },
  wrong_edge? : () -> Int64 = fn() { 0xFF3B30FFL },
) -> @view.View {
  let input_field = code.field
  let accepted = code.accepted
  let handed = code.handed
  parent.box(fn(room) {
    room.width_share(Is(1.0)).lines_up(Is(Some(Middle))) |> ignore
    let fits = fn(w : Double) { w <= 0.0 || w >= 308.0 * 0.8 }
    let scale = fn(w : Double) {
      if w <= 0.0 { return 1.0 }
      let s = w / (if fits(w) { 308.0 } else { 142.0 })
      if s < 1.0 { s } else { 1.0 }
    }
    let focused = @signals.signal(false)
    room.box(fn(groups) {
      groups
      .row(Roomed(room, fn(w, _) { fits(w) }))
      .gap(Roomed(room, fn(w, _) { (if fits(w) { 24.0 } else { 8.0 }) * scale(w) }))
      .lines_up(Is(Some(Middle)))
      |> ignore
      for group in 0..<2 {
        groups.box(fn(held) {
          held
          .width(Roomed(room, fn(w, _) { Some(142.0 * scale(w)) }))
          .height(Roomed(room, fn(w, _) { Some(52.0 * scale(w)) }))
          |> ignore
          held.box(fn(row) {
            row
            .width(Is(Some(142.0)))
            .height(Is(Some(52.0)))
            .row(Is(true))
            .gap(Is(8.0))
            .scale(Painted(fn(laid) {
              match laid.size(room) {
                Some((w, _)) => scale(w)
                None => 1.0
              }
            }), about=At(0.0, 0.0))
            |> ignore
            for j in 0..<3 {
              let index = group * 3 + j
              row.box(fn(box) {
                box
                .width(Is(Some(42.0)))
                .height(Is(Some(52.0)))
                .radius(Is(12.0))
                .lines_up(Is(Some(Middle)))
                .lies_along(Is(Middle))
                .edge(By(fn() {
                  let digits = input_field.text().to_array()
                  let next = if digits.length() < 5 { digits.length() } else { 5 }
                  let ink = if wrong() && digits.length() == 0 {
                    wrong_edge()
                  } else if enabled() && focused.get() && index == next {
                    next_edge()
                  } else {
                    edge()
                  }
                  (1.0, ink)
                }))
                |> ignore
                box.box(fn(digit) {
                  digit
                  .words_runs(By(fn() {
                    let digits = input_field.text().to_array()
                    if index < digits.length() { [span(digits[index].to_string(), mono=true)] } else { [] }
                  }))
                  .words_look(Is({ ..@view.words_plain, size: 24.0, weight: 600, wrap: false }))
                  .ink(By(fn() { if enabled() { color() } else { disabled_color() } }))
                  |> ignore
                })
                |> ignore
              })
              |> ignore
            }
          })
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
    let input = field(
      room,
      input_field,
      font_size=24.0,
      line=52.0,
      max_lines=1,
      color=0L,
      placeholder_color=0L,
      caret_color=0L,
      enter_sends=true,
      ime_action=@hostapi.ime_action_number,
    )
    input.over(Is(true)) |> ignore
    input.reacts(fn() { input.focused() }, fn(on) { focused.set(on) })
    room.reacts(fn() { input_field.text() }, fn(typed) {
      if !@signals.untracked(enabled) {
        if typed != accepted.val { input_field.set(accepted.val) }
      } else {
        let b = StringBuilder()
        let mut n = 0
        for ch in typed {
          if ch >= '0' && ch <= '9' && n < 6 {
            b.write_char(ch)
            n += 1
          }
        }
        let digits = b.to_string()
        accepted.val = digits
        if n < 6 { handed.val = None }
        let ready = n == 6 && handed.val != Some(digits)
        if ready { handed.val = Some(digits) }
        if typed != digits { input_field.set(digits) }
        if ready { complete(digits) }
      }
    })
    // The tree may still be being made, before it is installed in the window. Ask its focus manager to give the
    // editor the focus when this node opens, including on the first frame of a new tree.
    room.focus_opens(input) |> ignore
  })
}
