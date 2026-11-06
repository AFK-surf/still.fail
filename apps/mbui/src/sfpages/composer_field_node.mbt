// The composer's one editor, held while its box opens, closes or its content changes. It uses the same Writing and
// reference processing as the old composer's field; only its input causes do work, never a frame's build.

///|
/// The composer's field in `parent`: its existing draft, where its files go, current restrictions and hint, and what
/// gives its words up. `changed` is told only a local edit (the core's own revision has already updated Writing), so
/// typing may warm the agent without warming it when its draft is read back. `room`: what its lines are given room by
/// (a node that holds it) and how tall that room is by how big that is laid out (its share of it: text_window_share,
/// text_most at most), worked out as it is laid out. The field node is kept by the caller's keyed part as the composer
/// changes arrangement.
fn composer_field_node(
  parent : @view.View,
  src : Source,
  w : Writing,
  station : () -> String,
  locked : () -> Bool,
  offline : () -> Bool,
  hint : () -> String,
  submit : () -> Unit,
  changed : () -> Unit,
  room : (@view.View, (Double, Double) -> Double),
  hint_alpha? : () -> Double = fn() { 1.0 },
  caret_alpha? : () -> Double = fn() { 1.0 },
  keys? : (Int, Int) -> Bool,
) -> @view.View {
  let live = fn() { !locked() }
  let files = fn() { !locked() && !offline() }
  let words = fn() { @ui.style_words(@sf.theme().t.words) }
  let line = fn() {
    let l = words()
    if l.line > 0.0 { l.line } else { l.size * @ui.tree_theme().text_line }
  }
  let field = @ui.field(
    parent,
    w.field,
    words=true,
    trim=true,
    size_by=fn() { words().size },
    line_by=line,
    max_lines_in=(room.0, fn(w, h) { (dmin(text_most, (room.1)(w, h) * text_window_share) / line()).to_int() }),
    enter_by=fn() { @sf.enter_sends() },
    paste_limit_by=fn() { if files() && !w.starting.get() { @sfbase.paste_threshold_read() } else { 0 } },
    files_when=files,
    placeholder_by=hint,
    keys?=keys,
    colors_by=fn() {
      let p = @sf.theme().p
      (p.text, @sf.alpha(p.subtle, hint_alpha()), @sf.alpha(p.accent, caret_alpha()))
    },
    look=fn(s) { (@sfbase.refs_look(w.key, @sf.theme().p.accent))(s) },
    submitted=fn(s) {
      if live() {
        writing_text(src, w, s)
        submit()
      }
    },
    pasted=fn(s) {
      if files() && !w.starting.get() {
        @sfbase.writing_paste(src, w, station(), s)
      }
    },
    files=fn(fs) {
      if files() {
        for (name, bytes) in fs {
          writing_add(src, w, station(), name, bytes)
        }
      }
    },
  )
  field.presses(By(live)).focusable(By(live), keys=0) |> ignore
  field.reacts(fn() { true }, fn(_) { @sfbase.paste_threshold_now(src) |> ignore })
  field.reacts(fn() { (w.field.text(), w.field.selection(), w.starting.get(), locked(), station()) }, fn(_) {
    @sfbase.refs_edits_now(src, w.key, w.field, station(), locked())
    let said = w.field.text()
    if live() && !w.starting.get() && said != w.text.get() {
      writing_text(src, w, said)
      changed()
    }
  })
  field
}
