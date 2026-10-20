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
/// What it shows: its words (with what is being composed), each a dot where they are a secret (as many UTF-16 units,
/// so the caret's and the selection's places are the same).
fn EditorState::shown(self : EditorState) -> String {
  let d = self.display()
  if !self.secret {
    return d
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
) -> EditorResult {
  let id = self.id(key)
  let st = match self.editors.get(id) {
    Some(s) => s
    None => {
      let s = {
        text: "",
        caret: 0,
        anchor: 0,
        marked: "",
        msel_a: 0,
        msel_b: 0,
        blink0: self.now,
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
      }
      self.editors[id] = s
      self.own(id)
      s
    }
  }
  st.limit = paste_limit
  st.enter_sends = enter_sends
  st.secret = secret
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
    self.emit_text(tl, st.ox, st.oy, st.color, alpha)
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
/// Takes the text out of an editor (a send button does this).
pub fn Ctx::take_editor_text(self : Ctx, key : String) -> String {
  match self.editors.get(self.id(key)) {
    Some(st) => {
      if st.marked.length() > 0 {
        st.text_input(2, "", 0, 0, self.now)
      }
      let t = st.text
      st.text = ""
      st.caret = 0
      st.anchor = 0
      st.scroll = 0.0
      t
    }
    None => ""
  }
}

///|
/// Puts `text` in an editor in place of what it has, the caret at its end (a draft kept, words put back). An editor
/// not drawn yet takes it when it is.
pub fn Ctx::set_editor_text(self : Ctx, key : String, text : String) -> Unit {
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
      let st = {
        text,
        caret: text.length(),
        anchor: text.length(),
        marked: "",
        msel_a: 0,
        msel_b: 0,
        blink0: self.now,
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
      }
      self.editors[id] = st
      self.own(id)
    }
  }
}

///|
/// The words in editor `key` now ("" none such): what a view checks before the editor is built this frame.
pub fn Ctx::editor_text(self : Ctx, key : String) -> String {
  match self.editors.get(self.id(key)) {
    Some(st) => st.text
    None => ""
  }
}

///|
/// Whether the editor `key` is kept on this page (drawn before, and its page not left since).
pub fn Ctx::has_editor(self : Ctx, key : String) -> Bool {
  self.editors.contains(self.id(key))
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
