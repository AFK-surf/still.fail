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
  self.handle = false
  // a key (the menu's own included) puts the menu away; what is picked loses its handles, but for all of it picked
  // by a finger's menu, which keeps both (Compose's TextFieldSelectionManager.selectAll)
  let picked = self.sel_handles
  let menu_was = self.menu
  self.menu = false
  self.sel_handles = false
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
    // (from the floating menu, over words picked or the caret: picked, both handles and the menu over all of it)
    if picked || menu_was {
      self.sel_handles = t.length() > 0
      self.menu = t.length() > 0
    }
  } else if code == key_copy || code == key_cut {
    let (a, b) = self.sel()
    // (a secret is not copied or cut out)
    if a != b && !self.secret {
      h_clipboard_set(sub(t, a, b))
      if code == key_cut {
        self.delete_selection() |> ignore
      } else if picked {
        // copied from a finger's menu: let go of, the caret at its end (Compose's copy(cancelSelection))
        self.anchor = b
        self.caret = b
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
  // what is typed lets the handle go (Compose: shown again by the next tap), and the menu and a pick's handles
  if kind != text_composing {
    self.handle = false
    self.menu = false
    self.sel_handles = false
  }
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
  } else if kind == text_composing {
    self.comp_a = a
    self.comp_b = b
  } else if kind == text_state {
    self.text_set(s, a, b)
  }
}

///|
/// The field as the input method left it (Android's: its edits made on the host's copy of the words, MBView.MBInput):
/// words `s` with the composing region last said (text_composing) in them, the selection from `a` to `b`. A
/// composition holding the caret is kept apart, at the caret, as the field keeps one; one that does not is let be as
/// words. As much put in at once as the field's limit or more is a paste, not put in (`pasted`), as kind 0's.
fn EditorState::text_set(self : EditorState, s : String, a : Int, b : Int) -> Unit {
  let n = s.length()
  let ca = self.comp_a
  let cb = self.comp_b
  self.comp_a = -1
  self.comp_b = -1
  let sa = imin(imax(a, 0), n)
  let sb = imin(imax(b, 0), n)
  let grown = n - self.display().length()
  if self.limit > 0 && grown >= self.limit && sa == sb && sa >= grown {
    self.pasted = Some(sub(s, sa - grown, sa))
    return
  }
  if ca >= 0 && cb > ca && cb <= n && sa == sb && sa >= ca && sa <= cb {
    self.text = sub(s, 0, ca) + sub(s, cb, n)
    self.caret = ca
    self.anchor = ca
    self.marked = sub(s, ca, cb)
    self.msel_a = sa - ca
    self.msel_b = sa - ca
  } else {
    self.text = s
    self.anchor = sa
    self.caret = sb
    self.marked = ""
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
  trim? : Bool = false,
  color? : Int64 = 0x1D1D1FFFL,
  placeholder_color? : Int64 = 0x8E8E93FFL,
  caret_color? : Int64 = 0x0A84FFFFL,
  enter_sends? : Bool = true,
  ime_action? : Int = 0,
  paste_limit? : Int = 0,
  secret? : Bool = false,
  words? : Bool = false,
  look? : (String) -> (String, Array[(Int, Int, Int64)]),
  field? : Field,
  pictures? : Bool = false,
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
  st.ime_action = ime_action
  st.secret = secret
  st.words = words
  st.look = look
  // (what the look makes of the words worked out again, once, for this build: it may say other colours now)
  st.looked = None
  // one Field, one editor: two editors over one Field would lay each other's lines and scroll over each other
  // (by id: the same key in two scopes, a list's rows, is two editors)
  if field is Some(_) && st.built_frame == self.build_no && st.built_id != id {
    abort(
      "Ctx::editor: one Field given to two editors in one build (\{st.built_key} id \{st.built_id} and \{key} id \{id}): a Field is one editor's",
    )
  }
  st.built_frame = self.build_no
  st.built_key = key
  st.built_id = id
  // ⌘V with a picture on the clipboard, read for it: the picture where it takes pictures (Ctx::field_picture), else
  // the words with it put in as a paste's
  match desk.pasting {
    Some((pid, r)) if pid == id =>
      match r.got() {
        Some(got) => {
          desk.pasting = None
          match got.picture {
            Png(png) if pictures => {
              desk.pictures[id] = png
              self.read_changed("a picture pasted")
            }
            _ => if got.text != "" { st.text_input(0, got.text, 0, 0, self.now) }
          }
        }
        None => ()
      }
    _ => ()
  }
  // Android's long press on it (the finger still, held long_press_ms: one that moves past the slop is no tap, app.mbt): the word there picked, its handles and the
  // floating menu, felt (Compose's text field); the finger sliding on from there widens it by words (`editor_tap`
  // is Android's alone: elsewhere a press on a field puts the caret at once)
  if self.editor_tap == id &&
    self.down &&
    !self.dragging &&
    self.held_told != self.press_at {
    let held = self.now - self.press_at
    if held >= long_press_ms {
      self.held_told = self.press_at
      self.take_press()
      self.editor_tap = 0
      self.focus = id
      if st.pick_word(self.press_x, self.press_y, self.now) {
        self.word_drag = id
      }
      haptic(LongPress)
    } else {
      self.wake_in(long_press_ms - held)
    }
  }
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
  // (the system's size of words: as Ctx::text's)
  let font_size = self.sp(font_size)
  let line = if line > 0.0 { self.sp(line) } else { self.theme.text_line * font_size }
  let (_, _, own_lh) = font_metrics(font_size, 400)
  let lh = if line > 0.0 { line } else { own_lh }
  n.id = id
  n.hit = true
  n.w = w
  n.font_size = font_size
  n.line_h = line
  n.line_trim = trim
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
/// Android's: Compose's text field's, shown the first 500 ms of each second (TextFieldCursor.kt cursorAnimationSpec).
pub let caret_blink_android_ms : Double = 500.0

///|
/// How long the caret is shown, and then hidden, here.
fn caret_blink() -> Double {
  if h_feel() == 2 {
    caret_blink_android_ms
  } else {
    caret_blink_ms
  }
}

///|
/// The caret's handle's radius (Compose's cursor handle: 25 dp across, HandleWidth).
let handle_r : Double = 12.5

///|
/// Whether (`x`, `y`) is on the caret's handle of `st` (its circle, and a little round it: a finger's).
fn EditorState::on_handle(self : EditorState, x : Double, y : Double) -> Bool {
  if !self.handle_on {
    return false
  }
  // the circle's middle: its radius √2 under the tip, straight down
  let mx = self.handle_x
  let my = self.handle_y + handle_r * 1.4142135623730951
  let dx = x - mx
  let dy = y - my
  (dx * dx + dy * dy).sqrt() <= handle_r + 8.0
}

///|
/// The caret's width (Compose's DefaultCursorThickness, 2 dp; 2 elsewhere too).
let caret_w : Double = 2.0

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
    let ph = layout_text(n.text, n.font_size, 400, 1.0e9, false, line=st.line, trim=n.line_trim)
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
    let blink = caret_blink()
    let phase = (since / blink).to_int()
    self.wake_at_time(st.blink0 + (phase + 1).to_double() * blink, later=true)
    let coff = if ml > 0 { st.caret + st.msel_a } else { st.caret }
    if phase % 2 == 0 {
      let (cx, cl) = tl.caret(coff)
      let top = st.oy + cl.to_double() * tl.line_h
      // Android's as Compose's text field draws it (TextFieldCursor.kt): from the caret rightwards (kept in the
      // field), its line's whole height, square; elsewhere about the caret, 2 short of each end, round
      let (x, y, h, r) = if h_feel() == 2 {
        (dmin(st.ox + cx, n.x + n.fw - caret_w), top, tl.line_h, 0.0)
      } else {
        (st.ox + cx - caret_w / 2.0, top + 2.0, tl.line_h - 4.0, 1.0)
      }
      self.emit_rect(
        x,
        y,
        caret_w,
        h,
        r,
        st.caret_color,
        0.0,
        0L,
        alpha,
      )
    }
  }
  pop_clip()
  // Android's handle under the caret (Compose's cursor handle, TextFieldSelectionManager): a drop in the caret's colour
  // hanging from it, a circle 25 across under a corner turned to point up, over everything (a popup's: no box cuts it)
  if focused && st.handle && h_feel() == 2 && a == b && ml == 0 && st.text.length() > 0 {
    let (cx, cl) = tl.caret(st.caret)
    let x = st.ox + cx
    let y = st.oy + (cl + 1).to_double() * tl.line_h
    st.handle_on = true
    st.handle_x = x
    st.handle_y = y
    let r = handle_r
    push_clip(-1.0e9, -1.0e9, 1.0e9, 1.0e9)
    let (outer, _, _) = clip_at(clip_top())
    let i0 = self.ninst
    self.emit_rect(x, y, 2.0 * r, 2.0 * r, r, st.caret_color, 0.0, 0L, alpha)
    self.emit_rect(x, y, r, r, 0.0, st.caret_color, 0.0, 0L, alpha)
    turn_insts(self.inst, i0, self.ninst, 3.141592653589793 / 4.0, x, y, outer)
    pop_clip()
  } else {
    st.handle_on = false
    if !focused {
      st.handle = false
    }
  }
  // Android's handles of words a finger picked (Compose's SelectionHandle, as large as the caret's): a drop hanging
  // from each end's foot, the start's corner up and to its right, the end's up and to its left, over everything
  if focused && st.sel_handles && h_feel() == 2 && a != b && ml == 0 {
    let r = handle_r
    let (ax, al) = tl.caret(a)
    let (bx, bl) = tl.caret(b)
    st.sel_ax = st.ox + ax
    st.sel_ay = st.oy + (al + 1).to_double() * tl.line_h
    st.sel_bx = st.ox + bx
    st.sel_by = st.oy + (bl + 1).to_double() * tl.line_h
    st.sel_on = true
    push_clip(-1.0e9, -1.0e9, 1.0e9, 1.0e9)
    // the start's: the circle to the tip's left, its square corner at the tip
    self.emit_rect(st.sel_ax - 2.0 * r, st.sel_ay, 2.0 * r, 2.0 * r, r, st.caret_color, 0.0, 0L, alpha)
    self.emit_rect(st.sel_ax - r, st.sel_ay, r, r, 0.0, st.caret_color, 0.0, 0L, alpha)
    // the end's: to its right
    self.emit_rect(st.sel_bx, st.sel_by, 2.0 * r, 2.0 * r, r, st.caret_color, 0.0, 0L, alpha)
    self.emit_rect(st.sel_bx, st.sel_by, r, r, 0.0, st.caret_color, 0.0, 0L, alpha)
    pop_clip()
  } else {
    st.sel_on = false
    if !focused || a == b {
      st.sel_handles = false
    }
  }
  if !focused {
    st.menu = false
  }
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
          // its input method's action said before the field takes it (the host starts the input method anew)
          if st.ime_action != self.ime_action_told {
            self.ime_action_told = st.ime_action
            h_ime_action(st.ime_action)
          }
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
    handle: false,
    handle_on: false,
    handle_x: 0.0,
    handle_y: 0.0,
    sel_handles: false,
    sel_on: false,
    sel_ax: 0.0,
    sel_ay: 0.0,
    sel_bx: 0.0,
    sel_by: 0.0,
    word_a: 0,
    word_b: 0,
    menu: false,
    comp_a: -1,
    comp_b: -1,
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
    ime_action: 0,
    line: 0.0,
    color: 0L,
    ph_color: 0L,
    caret_color: 0L,
    sel_color: 0L,
    secret: false,
    words: false,
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
/// Pastes what the clipboard holds into the field `id` (an edit menu's 粘贴), as ⌘V (Ctrl+V) with a picture on it
/// does: read first, then the picture where the field takes pictures (Ctx::field_picture), else its words.
pub fn Ctx::field_paste(self : Ctx, id : Int) -> Unit {
  match clipboard_read() {
    Some(r) => {
      desk.pasting = Some((id, r))
      self.focus_on(id)
    }
    None => ()
  }
}

///|
/// A picture pasted into the field `key` (one that takes pictures: Ctx::editor `pictures`) with ⌘V (Ctrl+V), as PNG:
/// taken once, for the app to put in as a file (a page's paste takes a picture as one).
pub fn Ctx::field_picture(self : Ctx, key : String) -> Bytes? {
  let id = self.id(key)
  let got = desk.pictures.get(id)
  desk.pictures.remove(id)
  got
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

// ── words picked by a finger (Android's: Compose's text field selection) ──────────────────────────────────────

///|
/// How soon a second tap on a field picks the word there (ViewConfiguration's double tap timeout).
pub let double_tap_ms : Double = 300.0

///|
/// The word at (`x`, `y`) in the field picked (a long press's, a double tap's): its two handles, the floating menu
/// over it. False when there is none there (nothing under the finger but spaces: the caret put there instead).
fn EditorState::pick_word(self : EditorState, x : Double, y : Double, now : Double) -> Bool {
  let tl = match self.tl {
    Some(t) => t
    None => return false
  }
  if self.marked.length() > 0 {
    self.text_input(2, "", 0, 0, now)
  }
  let off = imin(tl.offset_at(x - self.ox, y - self.oy), self.text.length())
  let (a, b) = word_at(self.text, off)
  self.blink0 = now
  self.handle = false
  if b <= a || self.secret {
    self.caret = off
    self.anchor = off
    self.sel_handles = false
    self.menu = self.text.length() > 0
    return false
  }
  self.anchor = a
  self.caret = b
  self.word_a = a
  self.word_b = b
  self.sel_handles = true
  self.menu = true
  true
}

///|
/// A finger sliding on from a long press's word: the selection widened by words to where it is (Compose's word
/// granularity), from the word first picked.
fn EditorState::widen_to(self : EditorState, x : Double, y : Double) -> Unit {
  let tl = match self.tl {
    Some(t) => t
    None => return
  }
  let off = imin(tl.offset_at(x - self.ox, y - self.oy), self.text.length())
  let (a, b) = word_at(self.text, off)
  if off >= self.word_a {
    self.anchor = self.word_a
    self.caret = if b > off { b } else { imax(off, self.word_b) }
  } else {
    self.anchor = self.word_b
    self.caret = if b > a { a } else { off }
  }
}

///|
/// Which of the selection's handles (`x`, `y`) is on: 2 its start's, 3 its end's, 0 neither (a finger's reach round
/// each circle, which hangs from its tip on the outside of the words).
fn EditorState::on_sel_handle(self : EditorState, x : Double, y : Double) -> Int {
  if !self.sel_on {
    return 0
  }
  let near = fn(cx : Double, cy : Double) {
    let dx = x - cx
    let dy = y - cy
    (dx * dx + dy * dy).sqrt() <= handle_r + 8.0
  }
  if near(self.sel_bx + handle_r, self.sel_by + handle_r) {
    3
  } else if near(self.sel_ax - handle_r, self.sel_ay + handle_r) {
    2
  } else {
    0
  }
}

///|
/// A selection's handle dragged to (`x`, `y`) (its tip `dy` over the finger): that end where the tip comes, in the
/// middle of the line over it, never past the other end.
fn EditorState::sel_handle_to(self : EditorState, which : Int, x : Double, y : Double, dy : Double) -> Unit {
  let tl = match self.tl {
    Some(t) => t
    None => return
  }
  let tip = y - dy
  let off = imin(tl.offset_at(x - self.ox, tip - tl.line_h / 2.0 - self.oy), self.text.length())
  let (a, b) = self.sel()
  if which == 2 {
    self.anchor = b
    self.caret = imin(off, imax(b - 1, 0))
  } else {
    self.anchor = a
    self.caret = imax(off, imin(a + 1, self.text.length()))
  }
}

///|
/// What can be done to the field's words now (hostapi text_menu_*): cut and copy what is picked (not a secret's),
/// paste always, select all unless all is picked.
fn EditorState::can(self : EditorState) -> Int {
  let (a, b) = self.sel()
  let n = self.text.length()
  (if a != b && !self.secret { @hostapi.text_menu_cut | @hostapi.text_menu_copy } else { 0 }) |
  @hostapi.text_menu_paste |
  (if n > 0 && !(a == 0 && b == n) { @hostapi.text_menu_select_all } else { 0 })
}

///|
/// A field right clicked since the last frame (a desktop's secondary button): its id and where, the focus given it (the
/// edit menu the app puts up there acts on it: field_can, field_edit). None when none was.
pub fn Ctx::field_right_clicked(self : Ctx) -> (Int, Double, Double)? {
  for m in desk.menus {
    for id in m.0 {
      if self.editors.contains(id) {
        if self.focus != id {
          self.focus_on(id)
        }
        return Some((id, m.1, m.2))
      }
    }
  }
  None
}

///|
/// What can be done to field `id`'s words now (hostapi text_menu_*: cut, copy, paste, select all); 0 for no field.
pub fn Ctx::field_can(self : Ctx, id : Int) -> Int {
  match self.editors.get(id) {
    Some(st) => st.can()
    None => 0
  }
}

///|
/// Field `id`'s words cut, copied or all picked (text_menu_cut, _copy, _select_all: as ⌘X, ⌘C, ⌘A do them), or
/// `paste` put in for what is picked (text_menu_paste: as ⌘V puts the clipboard's in); the focus its again (an edit
/// menu's choice, the menu having had it).
pub fn Ctx::field_edit(self : Ctx, id : Int, what : Int, paste? : String = "") -> Unit {
  match self.editors.get(id) {
    Some(st) => {
      if what == @hostapi.text_menu_paste {
        if paste != "" {
          st.text_input(0, paste, 0, 0, self.now)
        }
      } else if what == @hostapi.text_menu_cut {
        st.key(key_cut, 0, self.now)
      } else if what == @hostapi.text_menu_copy {
        st.key(key_copy, 0, self.now)
      } else if what == @hostapi.text_menu_select_all {
        st.key(key_select_all, 0, self.now)
      }
      self.focus_on(id)
      self.read_changed("a field edited")
    }
    None => ()
  }
}

///|
/// Tells the host whether the floating text menu is up and over what (Android's: a field's picked words, or its caret
/// when its handle was tapped): offering cut and copy over words picked (not a secret's), paste always, select all
/// unless all is picked; each frame, said again only when it changed.
fn Ctx::sync_text_menu(self : Ctx) -> Unit {
  let want = match self.editors.get(self.focus) {
    Some(st) if st.menu && st.marked.length() == 0 =>
      match st.tl {
        Some(tl) => {
          let (a, b) = st.sel()
          let (x0, l0) = tl.caret(a)
          let (x1, l1) = tl.caret(b)
          let top = st.oy + l0.to_double() * tl.line_h
          let bottom = st.oy + (l1 + 1).to_double() * tl.line_h
          let (x, w) = if l0 == l1 {
            (st.ox + dmin(x0, x1), dmax((x1 - x0).abs(), caret_w))
          } else {
            (st.ox, tl.w)
          }
          Some((x, top, w, bottom - top, st.can()))
        }
        None => None
      }
    _ => None
  }
  let sig = match want {
    Some((x, y, w, h, can)) => "\{x.to_int()},\{y.to_int()},\{w.to_int()},\{h.to_int()},\{can}"
    None => ""
  }
  if sig == self.menu_sig {
    return
  }
  self.menu_sig = sig
  match want {
    Some((x, y, w, h, can)) => h_text_menu(true, x, y, w, h, can)
    None => h_text_menu(false, 0.0, 0.0, 0.0, 0.0, 0)
  }
}
