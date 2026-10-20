// A multi-line text field. The system input method composes into `marked`
// (shown underlined at the caret) until it commits; the host is told the
// caret's rectangle and the text around it every frame the field is focused.

///|
pub struct EditorResult {
  submitted : String?
  focused : Bool
  /// the words in it now (what the input method composes not yet among them)
  text : String
  /// words put in at once, `paste_limit` characters or more: not put in, for the app to take (a long paste)
  pasted : String?
}

///|
fn sub(s : String, a : Int, b : Int) -> String {
  if a >= b {
    ""
  } else {
    s.unsafe_substring(start=a, end=b)
  }
}

///|
fn EditorState::display(self : EditorState) -> String {
  if self.marked.length() == 0 {
    self.text
  } else {
    sub(self.text, 0, self.caret) +
    self.marked +
    sub(self.text, self.caret, self.text.length())
  }
}

///|
/// What its look makes of words `d` (`d` itself, no colours, with none): what shows (`d` where it would not keep
/// their length) and the colours of its ranges; worked out once a build, kept for the same words.
fn EditorState::look_of(self : EditorState, d : String) -> (String, Array[(Int, Int, Int64)]) {
  match self.look {
    None => (d, [])
    Some(f) =>
      match self.looked {
        Some((w, o, spans)) if w == d => (o, spans)
        _ => {
          let (o, spans) = f(d)
          let shown = if o.length() == d.length() { o } else { d }
          self.looked = Some((d, shown, spans))
          (shown, spans)
        }
      }
  }
}

///|
/// What it shows: its words (with what is being composed), each a dot where they are a secret (as many UTF-16 units,
/// so the caret's and the selection's places are the same).
fn EditorState::shown(self : EditorState) -> String {
  let d = self.display()
  if !self.secret {
    return self.look_of(d).0
  }
  let b = StringBuilder()
  for _ in 0..<d.length() {
    b.write_char('\u{2022}')
  }
  b.to_string()
}

///|
fn EditorState::sel(self : EditorState) -> (Int, Int) {
  if self.anchor < self.caret {
    (self.anchor, self.caret)
  } else {
    (self.caret, self.anchor)
  }
}

///|
fn EditorState::delete_selection(self : EditorState) -> Bool {
  let (a, b) = self.sel()
  if a == b {
    return false
  }
  self.text = sub(self.text, 0, a) + sub(self.text, b, self.text.length())
  self.caret = a
  self.anchor = a
  true
}

///|
fn EditorState::insert(self : EditorState, s : String) -> Unit {
  self.delete_selection() |> ignore
  self.text = sub(self.text, 0, self.caret) +
    s +
    sub(self.text, self.caret, self.text.length())
  self.caret = self.caret + s.length()
  self.anchor = self.caret
  self.marked = ""
}

///|
/// The grapheme cluster boundary before `off` (UAX #29).
fn prev_boundary(t : String, off : Int) -> Int {
  @text.prev_grapheme(t, off)
}

///|
/// The grapheme cluster boundary after `off`, which may lie inside a cluster
/// (an input method can put the caret anywhere).
fn next_boundary(t : String, off : Int) -> Int {
  if off >= t.length() {
    return t.length()
  }
  @text.next_grapheme(t, @text.prev_grapheme(t, off + 1))
}

///|
let key_backspace = 1

///|
let key_delete = 2

///|
let key_left = 3

///|
let key_right = 4

///|
let key_up = 5

///|
let key_down = 6

///|
let key_enter = 7

///|
let key_home = 8

///|
let key_end = 9

///|
let key_page_up = 15

///|
let key_page_down = 16

///|
let key_select_all = 12

///|
let key_copy = 13

///|
let key_cut = 14

///|
let mod_shift = 1

///|
fn EditorState::move_to(self : EditorState, off : Int, ext : Bool) -> Unit {
  self.caret = off
  if !ext {
    self.anchor = off
  }
}

///|
fn EditorState::key(self : EditorState, code : Int, mods : Int, now : Double) -> Unit {
  let shift = (mods & mod_shift) != 0
  self.blink0 = now
  let t = self.text
  if code == key_backspace {
    if !self.delete_selection() && self.caret > 0 {
      let p = prev_boundary(t, self.caret)
      self.text = sub(t, 0, p) + sub(t, self.caret, t.length())
      self.caret = p
      self.anchor = p
    }
  } else if code == key_delete {
    if !self.delete_selection() && self.caret < t.length() {
      let q = next_boundary(t, self.caret)
      self.text = sub(t, 0, self.caret) + sub(t, q, t.length())
    }
  } else if code == key_left {
    let (a, b) = self.sel()
    if a != b && !shift {
      self.move_to(a, false)
    } else {
      self.move_to(prev_boundary(t, self.caret), shift)
    }
    self.pref_x = -1.0
  } else if code == key_right {
    let (a, b) = self.sel()
    if a != b && !shift {
      self.move_to(b, false)
    } else {
      self.move_to(next_boundary(t, self.caret), shift)
    }
    self.pref_x = -1.0
  } else if code == key_up || code == key_down {
    match self.tl {
      Some(tl) => {
        let (x, line) = tl.caret(self.caret)
        if self.pref_x < 0.0 {
          self.pref_x = x
        }
        let target = if code == key_up { line - 1 } else { line + 1 }
        if target < 0 {
          self.move_to(0, shift)
        } else if target >= tl.line_start.length() {
          self.move_to(t.length(), shift)
        } else {
          let off = tl.offset_at(self.pref_x, (target.to_double() + 0.5) * tl.line_h)
          self.move_to(off, shift)
        }
      }
      None => ()
    }
  } else if code == key_home {
    self.move_to(0, shift)
  } else if code == key_end {
    self.move_to(t.length(), shift)
  } else if code == key_select_all {
    self.anchor = 0
    self.caret = t.length()
  } else if code == key_copy || code == key_cut {
    let (a, b) = self.sel()
    // (a secret is not copied or cut out)
    if a != b && !self.secret {
      h_clipboard_set(sub(t, a, b))
      if code == key_cut {
        self.delete_selection() |> ignore
      }
    }
  } else if code == key_enter {
    if shift || !self.enter_sends {
      if self.marked.length() > 0 {
        self.text_input(2, "", 0, 0, now)
      }
      self.insert("\n")
    } else if self.text.length() > 0 {
      self.submitted = Some(self.text)
      self.text = ""
      self.caret = 0
      self.anchor = 0
    }
  }
}

///|
/// kind 0 commits text, 1 sets the composition (with its selection),
/// 2 commits the composition as it is.
fn EditorState::text_input(
  self : EditorState,
  kind : Int,
  s : String,
  a : Int,
  b : Int,
  now : Double,
) -> Unit {
  self.blink0 = now
  self.pref_x = -1.0
  if kind == 0 {
    if self.limit > 0 && s.length() >= self.limit {
      self.pasted = Some(s)
    } else {
      self.insert(s)
    }
  } else if kind == 1 {
    self.delete_selection() |> ignore
    self.marked = s
    self.msel_a = a
    self.msel_b = b
  } else if kind == 2 {
    let m = self.marked
    self.marked = ""
    self.insert(m)
  } else if kind == 3 {
    // the input method moves the selection (iOS)
    let n = self.text.length()
    self.anchor = imin(imax(a, 0), n)
    self.caret = imin(imax(b, 0), n)
  }
}

///|
pub fn Ctx::editor(
  self : Ctx,
  key : String,
  placeholder? : String = "",
  w? : Size = Fill(1.0),
  font_size? : Double = 15.0,
  max_lines? : Int = 5,
  plain? : Bool = false,
  line? : Double = 0.0,
  color? : Int64 = 0x1D1D1FFFL,
  placeholder_color? : Int64 = 0x8E8E93FFL,
  caret_color? : Int64 = 0x0A84FFFFL,
  enter_sends? : Bool = true,
  paste_limit? : Int = 0,
  secret? : Bool = false,
  look? : (String) -> (String, Array[(Int, Int, Int64)]),
  field? : Field,
) -> EditorResult {
  let id = self.id(key)
  let st = match (self.editors.get(id), field) {
    // what the app keeps (Field): this editor shows it from now on
    (Some(s), Some(f)) if physical_equal(s, f.st) => s
    (had, Some(f)) => {
      self.editors[id] = f.st
      if had is None {
        self.own(id)
      }
      f.st
    }
    (Some(s), None) => s
    (None, None) => {
      let s = EditorState::fresh("", self.now)
      self.editors[id] = s
      self.own(id)
      s
    }
  }
  st.limit = paste_limit
  st.enter_sends = enter_sends
  st.secret = secret
  st.look = look
  // (what the look makes of the words worked out again, once, for this build: it may say other colours now)
  st.looked = None
  // one Field, one editor: two editors over one Field would lay each other's lines and scroll over each other
  // (by id: the same key in two scopes, a list's rows, is two editors)
  if field is Some(_) && st.built_frame == self.frame_no && st.built_id != id {
    abort(
      "Ctx::editor: one Field given to two editors in one frame (\{st.built_key} id \{st.built_id} and \{key} id \{id}): a Field is one editor's",
    )
  }
  st.built_frame = self.frame_no
  st.built_key = key
  st.built_id = id
  if st.blink_again {
    st.blink_again = false
    st.blink0 = self.now
  }
  st.line = line
  st.color = color
  st.ph_color = placeholder_color
  st.caret_color = caret_color
  st.sel_color = (caret_color & 0xFFFFFF00L) | 0x40L
  let focused = self.focus == id
  let i = self.alloc(kind_editor)
  // in Tab's order (focus.mbt); its keys are its own
  self.focusable(id, node=i, keys=0, on_press=true)
  self.semantics(i, TextField, id~, label=placeholder, value=if secret { "" } else { st.text })
  let n = self.nodes[i]
  let line = if line > 0.0 { line } else { self.theme.text_line * font_size }
  let (_, _, own_lh) = font_metrics(font_size, 400)
  let lh = if line > 0.0 { line } else { own_lh }
  n.id = id
  n.hit = true
  n.w = w
  n.font_size = font_size
  n.line_h = line
  n.clip = true
  n.text = placeholder
  if plain {
    // no frame of its own: what holds it draws one
    n.min_h = lh
    n.max_h = lh * max_lines.to_double()
  } else {
    n.pad_l = 12.0
    n.pad_r = 12.0
    n.pad_t = 9.0
    n.pad_b = 9.0
    n.min_h = lh + 18.0
    n.max_h = lh * max_lines.to_double() + 18.0
    n.bg = 0xFFFFFFFFL
    n.radius = 12.0
    n.border_w = if focused { 2.0 } else { 1.0 }
    n.border_c = if focused { 0x0A84FFFFL } else { 0xD2D2D7FFL }
  }
  let res = { submitted: st.submitted, focused, text: st.text, pasted: st.pasted }
  st.submitted = None
  st.pasted = None
  res
}

///|
/// How long a focused field's caret is shown, and then hidden, as it blinks (ms).
pub let caret_blink_ms : Double = 530.0

///|
fn Ctx::paint_editor(self : Ctx, n : Node, alpha : Double) -> Unit {
  let st = match self.editors.get(n.id) {
    Some(s) => s
    None => return
  }
  let tl = match st.tl {
    Some(t) => t
    None => return
  }
  push_clip(n.x, n.y, n.x + n.fw, n.y + n.fh)
  let focused = self.focus == n.id
  let ml = st.marked.length()
  // selection
  let (a, b) = st.sel()
  if focused && a != b && ml == 0 {
    let (x0, l0) = tl.caret(a)
    let (x1, l1) = tl.caret(b)
    for l in l0..=l1 {
      let sx = if l == l0 { x0 } else { 0.0 }
      let ex = if l == l1 { x1 } else { tl.line_w[l] + 4.0 }
      self.emit_rect(
        st.ox + sx,
        st.oy + l.to_double() * tl.line_h,
        dmax(ex - sx, 2.0),
        tl.line_h,
        2.0,
        st.sel_color,
        0.0,
        0L,
        alpha,
      )
    }
  }
  if st.text.length() == 0 && ml == 0 && n.text.length() > 0 {
    // on one line, as a text that does not wrap
    let ph = layout_text(n.text, n.font_size, 400, 1.0e9, false, line=st.line)
    self.emit_text(ph, st.ox, st.oy, st.ph_color, alpha)
  } else {
    let spans = if st.secret { [] } else { st.look_of(st.display()).1 }
    self.emit_text(tl, st.ox, st.oy, st.color, alpha, spans~)
  }
  // composition underline
  if ml > 0 {
    let (x0, l0) = tl.caret(st.caret)
    let (x1, l1) = tl.caret(st.caret + ml)
    for l in l0..=l1 {
      let sx = if l == l0 { x0 } else { 0.0 }
      let ex = if l == l1 { x1 } else { tl.line_w[l] }
      self.emit_rect(
        st.ox + sx,
        st.oy + (l + 1).to_double() * tl.line_h - 3.0,
        dmax(ex - sx, 1.0),
        1.5,
        0.0,
        st.color,
        0.0,
        0L,
        alpha,
      )
    }
  }
  // caret
  if focused {
    let since = self.now - st.blink0
    let phase = (since / caret_blink_ms).to_int()
    self.wake_at_time(st.blink0 + (phase + 1).to_double() * caret_blink_ms, later=true)
    let coff = if ml > 0 { st.caret + st.msel_a } else { st.caret }
    if phase % 2 == 0 {
      let (cx, cl) = tl.caret(coff)
      self.emit_rect(
        st.ox + cx - 1.0,
        st.oy + cl.to_double() * tl.line_h + 2.0,
        2.0,
        tl.line_h - 4.0,
        1.0,
        st.caret_color,
        0.0,
        0L,
        alpha,
      )
    }
  }
  pop_clip()
}

///|
/// Tells the host where the caret is, so the input method's candidate
/// window follows it, and what text surrounds it.
fn Ctx::sync_ime(self : Ctx) -> Unit {
  // a key catcher's focus (device.mbt): the host told so before its input method is, with no text
  let catching = self.dev.catchers.contains(self.focus)
  if catching != self.ime_sig.has_prefix("catch ") {
    h_key_catch(catching)
    if !catching {
      self.ime_sig = "-"
    }
  }
  if catching {
    let sig = "catch \{self.focus}"
    if sig != self.ime_sig {
      self.ime_sig = sig
      h_set_ime(true, 0.0, self.height, 1.0, 1.0, "", 0, 0)
    }
    return
  }
  match self.editors.get(self.focus) {
    Some(st) =>
      match st.tl {
        Some(tl) => {
          let coff = st.caret + st.marked.length()
          let (cx, cl) = tl.caret(coff)
          let x = st.ox + cx
          let y = st.oy + cl.to_double() * tl.line_h
          let (a, b) = st.sel()
          let sig = "\{x.to_int()},\{y.to_int()},\{a},\{b},\{st.text.length()},\{stable_hash(st.text)}"
          if sig != self.ime_sig {
            self.ime_sig = sig
            h_set_ime(true, x, y, 2.0, tl.line_h, st.text, a, b)
          }
        }
        None => ()
      }
    None =>
      if self.ime_sig != "" {
        self.ime_sig = ""
        h_set_ime(false, 0.0, 0.0, 0.0, 0.0, "", 0, 0)
      }
  }
}

///|
/// An editor's state as it starts: `text` in it, the caret at its end.
fn EditorState::fresh(text : String, now : Double) -> EditorState {
  {
    text,
    caret: text.length(),
    anchor: text.length(),
    marked: "",
    msel_a: 0,
    msel_b: 0,
    blink0: now,
    tl: None,
    ox: 0.0,
    oy: 0.0,
    submitted: None,
    pref_x: -1.0,
    scroll: 0.0,
    pasted: None,
    limit: 0,
    enter_sends: true,
    line: 0.0,
    color: 0L,
    ph_color: 0L,
    caret_color: 0L,
    sel_color: 0L,
    secret: false,
    look: None,
    looked: None,
    blink_again: false,
    built_frame: -1,
    built_key: "",
    built_id: 0,
  }
}

///|
/// What an editor holds (its words, its selection), the app's own (Compose's TextFieldState): kept where the app keeps
/// what it is about (a draft), given to the editor that shows it (Ctx::editor's `field`), read and written by the app
/// from anywhere (a core's answer between frames included), the editor drawing what it holds when it is next built.
/// Typing changes it as it changes the editor: they are one. A Field is one editor's: given to two in one frame, the
/// app is stopped there (both named); it may move from one editor to another between frames.
struct Field {
  st : EditorState
}

///|
/// A field holding `text`, the caret at its end.
pub fn Field::new(text? : String = "") -> Field {
  let st = EditorState::fresh(text, 0.0)
  // (its caret blinks from when its editor is first built, not from the app's start)
  st.blink_again = true
  { st, }
}

///|
/// Its words as written (what the input method composes not counted).
pub fn Field::text(self : Field) -> String {
  self.st.text
}

///|
/// Its selection: its anchor and its caret (UTF-16, in its words; the same when nothing is selected).
pub fn Field::selection(self : Field) -> (Int, Int) {
  (self.st.anchor, self.st.caret)
}

///|
/// `text` in place of what it holds, the caret at `caret` (its end when not said), nothing selected: an app's own edit
/// (words kept put back, a mark put in, a word taken out whole). What the input method was composing is let go.
pub fn Field::set(self : Field, text : String, caret? : Int) -> Unit {
  let st = self.st
  let at = match caret {
    Some(k) => imin(imax(k, 0), text.length())
    None => text.length()
  }
  if st.text == text && st.marked == "" && st.caret == at && st.anchor == at {
    return
  }
  st.marked = ""
  st.text = text
  st.caret = at
  st.anchor = at
  st.pref_x = -1.0
  if text == "" {
    st.scroll = 0.0
  }
  // the caret shown at once where it is put; and a frame to draw it, written from wherever it was (an answer between
  // frames, a fiber, a timer), as the input's own changes have
  st.blink_again = true
  field_written()
}

///|
/// Its words given up (sent): what the input method was composing put in first, then none left in it.
pub fn Field::take(self : Field) -> String {
  let st = self.st
  if st.marked.length() > 0 {
    // (when: its blinking starts again as it is next built)
    st.text_input(2, "", 0, 0, 0.0)
    st.blink_again = true
  }
  let t = st.text
  self.set("")
  t
}

///|
/// The framework's own fields (Ctx::code_field): `text` in its editor `key` in place of what it has, the caret at its
/// end. An app writes a field it keeps (Field::set), never an editor by its key.
fn Ctx::put_editor_text(self : Ctx, key : String, text : String) -> Unit {
  let id = self.id(key)
  match self.editors.get(id) {
    Some(st) => {
      st.marked = ""
      st.text = text
      st.caret = text.length()
      st.anchor = st.caret
      st.blink0 = self.now
    }
    None => {
      let st = EditorState::fresh(text, self.now)
      self.editors[id] = st
      self.own(id)
    }
  }
}

///|
/// Whether the editor `key` has the focus (the keyboard is its).
pub fn Ctx::editor_focused(self : Ctx, key : String) -> Bool {
  self.focus != 0 && self.focus == self.id(key)
}

///|
/// Lets go of the focus: no field takes keys, the keyboard goes.
pub fn Ctx::blur(self : Ctx) -> Unit {
  self.focus = 0
}
