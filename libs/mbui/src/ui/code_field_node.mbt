// A code field (code_field.mbt's head) as a node of the window's tree, made once: its boxes nodes bound to the Field's
// words, the field of the tree's over them (its words unseen) taking the typing; how big the boxes are and whether they
// go in one row or a row a group made by the room it is given as it is laid out (View::by_room), nothing of its layout
// read back. What is typed is kept to digits, `length` at most, as it is typed (the edit's own moment); the code told
// once it is complete, and again only once it changed (a digit taken back and typed again counts). A code refused is
// emptied by what holds the Field (Field::set): the next one typed is told, the same or not.

///|
/// How a code field's digits and edges are drawn: its digits' ink (`off` while it takes no typing), its boxes' edges,
/// the next one's while it has the keys, all of them while the code is wrong and nothing is typed.
#derive(Eq)
pub(all) struct CodeInks {
  digits : Int64
  off : Int64
  edge : Int64
  next : Int64
  wrong : Int64
}

///|
/// What Ctx::code_field draws where nothing else is said.
// kept across runs: a value (no field of it changes)
pub let code_inks : CodeInks = {
  digits: 0x1D1D1FFFL,
  off: 0x8E8E93FFL,
  edge: 0x1D1D1F2EL,
  next: 0x1D1D1FFFL,
  wrong: 0xFF3B30FFL,
}

///|
/// The digits of `typed`, `length` at most.
fn code_digits(typed : String, length : Int) -> String {
  let b = StringBuilder()
  let mut n = 0
  for ch in typed {
    if ch >= '0' && ch <= '9' && n < length {
      b.write_char(ch)
      n = n + 1
    }
  }
  b.to_string()
}

///|
/// A code field in `parent` (the file's head; Ctx::code_field's look and sizes, each said the same way), editing
/// `input`: `typed` told the code at the moment it is complete (once a code). While `wrong()`, its boxes edged so while
/// nothing is typed; while not `enabled()`, its digits in `inks().off` and typing changes nothing. It takes the keys
/// as it is made unless not `autofocus`. `label`: what a screen reader calls it. The node (as wide as what holds it,
/// the boxes in its middle).
#callsite(autofill(loc))
pub fn code_field_node(
  parent : @view.View,
  input : Field,
  typed : (String) -> Unit,
  label? : String = "",
  length? : Int = 6,
  groups? : Array[Int] = [3, 3],
  wrong? : () -> Bool = fn() { false },
  enabled? : () -> Bool = fn() { true },
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
  inks? : () -> CodeInks = fn() { code_inks },
  loc~ : SourceLoc,
) -> @view.View {
  // (the groups as runs of boxes, [from, to); what they leave out one more)
  let rows : Array[(Int, Int)] = []
  let mut from = 0
  for n in groups {
    if from + n < length {
      rows.push((from, from + n))
      from = from + n
    }
  }
  rows.push((from, length))
  let widest = rows.fold(init=0, fn(m, r) { if r.1 - r.0 > m { r.1 - r.0 } else { m } })
  let one_row = length.to_double() * box_w +
    (length - 1 + rows.length() - 1).to_double() * gap +
    (rows.length() - 1).to_double() * group_gap
  let group_row = widest.to_double() * box_w + (widest - 1).to_double() * gap
  // (the complete code last told: none since it was not complete; the digits it holds as last typed)
  let told : Ref[String?] = Ref(None)
  let kept = Ref(@signals.untracked(fn() { code_digits(input.text(), length) }))
  parent.by_room(loc~, fn(held, room) {
    // As wide as its room: drawn smaller where one row is wider than that, down to `min_scale`; narrower still, a row
    // a group, as large as that room lets them be, never larger than asked.
    let fits = fn() { room.width() <= 0.0 || one_row * min_scale <= room.width() }
    let scale = fn() {
      let w = room.width()
      if w <= 0.0 {
        1.0
      } else {
        dmin(1.0, w / (if fits() { one_row } else { group_row }))
      }
    }
    let shown = fn() { code_digits(input.text(), length) }
    // the field itself over the boxes, its words unseen: a tap there gives it the keys (they take none of their own)
    let typing : Ref[@view.View?] = Ref(None)
    held.box(fn(over) {
      over.over(Is(true)) |> ignore
      let f = field(
        over,
        input,
        font_size~,
        max_lines=1,
        line=box_h,
        color=0x00000000L,
        placeholder_color=0x00000000L,
        caret_color=0x00000000L,
        enter_sends=true,
        ime_action=@hostapi.ime_action_number,
        label~,
        edited=fn(t) {
          // (while it takes no typing, put back as it was; else digits only, `length` at most)
          if !enabled() {
            input.set(kept.val)
            return
          }
          let d = code_digits(t, length)
          if d != t {
            input.set(d)
          }
          kept.val = d
          if d.length() == length && told.val != Some(d) {
            told.val = Some(d)
            typed(d)
          }
        },
      )
      f.grow(Is(1.0)) |> ignore
      typing.val = Some(f)
      if autofocus {
        input.focus()
      }
    })
    |> ignore
    held.lines_up(Is(Some(Middle))) |> ignore
    held.box(fn(boxes) {
      boxes
      .row(By(fits))
      .lines_up(Is(Some(Middle)))
      .gap(By(fn() { if fits() { gap * scale() * 2.0 + group_gap * scale() } else { gap * scale() } }))
      |> ignore
      for r in rows {
        boxes.box(fn(group) {
          group.row(Is(true)).gap(By(fn() { gap * scale() })) |> ignore
          for i in r.0..<r.1 {
            group.box(fn(b) {
              b
              .width(By(fn() { Some(box_w * scale()) }))
              .height(By(fn() { Some(box_h * scale()) }))
              .radius(By(fn() { radius * scale() }))
              .edge(
                By(fn() {
                  let k = inks()
                  let digits = shown()
                  let next = if digits.length() < length - 1 { digits.length() } else { length - 1 }
                  let ink = if wrong() && digits == "" {
                    k.wrong
                  } else if enabled() && i == next && typing.val.map_or(false, fn(f) { f.focused() }) {
                    k.next
                  } else {
                    k.edge
                  }
                  (1.0, ink)
                }),
              )
              .lines_up(Is(Some(Middle)))
              .lies_along(Is(Middle))
              |> ignore
              b.show(fn() { i < shown().length() }, fn(d) {
                d
                .words_runs(By(fn() { [span(shown().to_array()[i].to_string(), mono~)] }))
                .words_look(
                  By(fn() {
                    { ..@view.words_plain, size: font_size * scale(), weight, line: font_size * scale(), wrap: false }
                  }),
                )
                .ink(By(fn() { if enabled() { inks().digits } else { inks().off } }))
                |> ignore
              })
            })
            |> ignore
          }
        })
        |> ignore
      }
    })
    |> ignore
    // (what it holds followed, whoever writes it; the code told forgotten as it holds less than a code (emptied for the
    // next try): typed again, it is told again)
    held.reacts(shown, fn(d) {
      kept.val = d
      if d.length() < length {
        told.val = None
      }
    })
  })
}
