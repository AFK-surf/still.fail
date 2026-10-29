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
/// What its look makes of its words and what is being composed: the look's of the words the app holds (`text`, the
/// only ones it knows of: a composer's marks), the composition put in at the caret as it is, in the field's own colour,
/// the ranges after it moved along (one it is within grown over it).
fn EditorState::look_shown(self : EditorState) -> (String, Array[(Int, Int, Int64)]) {
  let (o, spans) = self.look_of(self.text)
  let ml = self.marked.length()
  if ml == 0 {
    return (o, spans)
  }
  let at = self.caret
  let moved = spans.map(fn(r) {
    let (a, b, k) = r
    (if a >= at { a + ml } else { a }, if b > at { b + ml } else { b }, k)
  })
  (sub(o, 0, at) + self.marked + sub(o, at, o.length()), moved)
}

///|
/// What it shows: its words (with what is being composed), each a dot where they are a secret (as many UTF-16 units,
/// so the caret's and the selection's places are the same).
fn EditorState::shown(self : EditorState) -> String {
  let d = self.display()
  if !self.secret {
    return self.look_shown().0
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

// ── moving and deleting by keys ────────────────────────────────────────────────────────────────────────────────

///|
/// How far a key's move or deletion in a field goes from where it starts, back (-1) or on (1).
priv enum Reach {
  /// a character
  Grapheme(Int)
  /// a line up or down, as near the same x as there is
  Line(Int)
  /// back, to the start of the word it is in or of the one before; on, to the end of the word it is in or of the next
  Word(Int)
  /// on, to the start of the next word (Windows')
  NextWord
  /// to the start or the end of the line it shows on
  LineEnd(Int)
  /// to the start or the end of its paragraph (what lies between line breaks)
  Para(Int)
  /// the same, or of the paragraph before or after when it is there already (a Mac's ⌥↑ ⌥↓, Ctrl+↑ Ctrl+↓)
  ParaOver(Int)
  /// to the start or the end of all of it
  All(Int)
}

///|
fn Reach::dir(self : Reach) -> Int {
  match self {
    Grapheme(d) | Line(d) | Word(d) | LineEnd(d) | Para(d) | ParaOver(d) | All(d) => d
    NextWord => 1
  }
}

///|
/// What a key does in a field: the caret moved (with Shift, what is picked widened to where it goes), or what lies
/// between the caret and where it reaches deleted (what is picked instead, when anything is).
priv enum Edit {
  Move(Reach)
  Erase(Reach)
}

///|
/// The keys that move and delete in every system's fields, with nothing held but Shift.
// kept across runs: a table, never written
let plain_keys : Array[(Int, Int, Edit)] = [
  (key_backspace, 0, Erase(Grapheme(-1))),
  (key_delete, 0, Erase(Grapheme(1))),
  (key_left, 0, Move(Grapheme(-1))),
  (key_right, 0, Move(Grapheme(1))),
  (key_up, 0, Move(Line(-1))),
  (key_down, 0, Move(Line(1))),
]

///|
/// A Mac's (an iPad's, an iPhone's with a keyboard), as Cocoa's key bindings have them (StandardKeyBinding.dict). A
/// Mac's host sends what its text system makes of a key instead (edit_keys); these are for a key that came as it was.
// kept across runs: a table, never written
let apple_keys : Array[(Int, Int, Edit)] = [
  (key_home, 0, Move(All(-1))),
  (key_end, 0, Move(All(1))),
  (key_left, mod_alt, Move(Word(-1))),
  (key_right, mod_alt, Move(Word(1))),
  (key_up, mod_alt, Move(ParaOver(-1))),
  (key_down, mod_alt, Move(ParaOver(1))),
  (key_left, mod_cmd, Move(LineEnd(-1))),
  (key_right, mod_cmd, Move(LineEnd(1))),
  (key_up, mod_cmd, Move(All(-1))),
  (key_down, mod_cmd, Move(All(1))),
  (key_backspace, mod_alt, Erase(Word(-1))),
  (key_delete, mod_alt, Erase(Word(1))),
  (key_backspace, mod_cmd, Erase(LineEnd(-1))),
]

///|
/// Windows' (and a browser's), as Blink's EditingBehavior table has them: Ctrl+→ to the next word's start
/// (ShouldSkipSpaceWhenMovingRight).
// kept across runs: a table, never written
let windows_keys : Array[(Int, Int, Edit)] = [
  (key_home, 0, Move(LineEnd(-1))),
  (key_end, 0, Move(LineEnd(1))),
  (key_home, mod_ctrl, Move(All(-1))),
  (key_end, mod_ctrl, Move(All(1))),
  (key_left, mod_ctrl, Move(Word(-1))),
  (key_right, mod_ctrl, Move(NextWord)),
  (key_up, mod_ctrl, Move(ParaOver(-1))),
  (key_down, mod_ctrl, Move(ParaOver(1))),
  (key_backspace, mod_ctrl, Erase(Word(-1))),
  (key_delete, mod_ctrl, Erase(NextWord)),
]

///|
/// Android's, as Blink's EditingBehavior table has them there: Alt+← Alt+→ to the line's ends, Alt+Backspace deleting
/// to its start.
// kept across runs: a table, never written
let android_keys : Array[(Int, Int, Edit)] = [
  (key_home, 0, Move(LineEnd(-1))),
  (key_end, 0, Move(LineEnd(1))),
  (key_home, mod_ctrl, Move(All(-1))),
  (key_end, mod_ctrl, Move(All(1))),
  (key_left, mod_ctrl, Move(Word(-1))),
  (key_right, mod_ctrl, Move(Word(1))),
  (key_left, mod_alt, Move(LineEnd(-1))),
  (key_right, mod_alt, Move(LineEnd(1))),
  (key_up, mod_ctrl, Move(ParaOver(-1))),
  (key_down, mod_ctrl, Move(ParaOver(1))),
  (key_backspace, mod_ctrl, Erase(Word(-1))),
  (key_delete, mod_ctrl, Erase(Word(1))),
  (key_backspace, mod_alt, Erase(LineEnd(-1))),
]

///|
/// The edit keys (key_code_word_back… key_code_delete_paragraph_on), in their order: what a Mac's text system makes of
/// a key (NSResponder's moveWordLeft:, moveToLeftEndOfLine:, deleteToBeginningOfLine:…), the same on every system.
// kept across runs: a table, never written
let edit_keys : Array[Edit] = [
  Move(Word(-1)),
  Move(Word(1)),
  Move(LineEnd(-1)),
  Move(LineEnd(1)),
  Move(Para(-1)),
  Move(Para(1)),
  Move(All(-1)),
  Move(All(1)),
  Move(ParaOver(-1)),
  Move(ParaOver(1)),
  Erase(Word(-1)),
  Erase(Word(1)),
  Erase(LineEnd(-1)),
  Erase(LineEnd(1)),
  Erase(Para(-1)),
  Erase(Para(1)),
]

///|
/// What key `code` with `mods` held does in a field on system `platform` (@ui.platform), as that system's own fields
/// do; Shift aside (it widens a move). None: nothing of these (Enter, ⌘C…, or a key with other keys held).
fn edit_of(code : Int, mods : Int, platform : Int) -> Edit? {
  if code >= key_code_word_back && code <= key_code_delete_paragraph_on {
    return Some(edit_keys[code - key_code_word_back])
  }
  let held = mods & (mod_ctrl | mod_alt | mod_cmd)
  let own = match platform {
    0 | 1 => apple_keys
    2 => android_keys
    _ => windows_keys
  }
  for keys in [plain_keys, own] {
    for k in keys {
      if k.0 == code && k.1 == held {
        return Some(k.2)
      }
    }
  }
  None
}

///|
/// Whether code unit `c` lies between words: a space, a line break, a mark (punctuation, a symbol: ASCII's, Latin-1's,
/// the general punctuation, the CJK and full-width ones); what a move by words passes over to come to one.
fn between_words(c : Int) -> Bool {
  if c < 0x80 {
    !((c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F)
  } else {
    (c >= 0x80 && c <= 0xBF) ||
    c == 0xD7 ||
    c == 0xF7 ||
    (c >= 0x2000 && c <= 0x206F) ||
    (c >= 0x3000 && c <= 0x303F) ||
    (c >= 0xFE30 && c <= 0xFE6F) ||
    (c >= 0xFF00 && c <= 0xFF0F) ||
    (c >= 0xFF1A && c <= 0xFF20) ||
    (c >= 0xFF3B && c <= 0xFF40) ||
    (c >= 0xFF5B && c <= 0xFF65)
  }
}

///|
fn between_words_at(t : String, i : Int) -> Bool {
  between_words(t.code_unit_at(i).to_int())
}

///|
/// The start of the word before `off` in `t` (the one it is in, or the one before what lies between them), as the
/// host's word boundaries have it (word_at: a dictionary's words in Chinese).
fn word_start_before(t : String, off : Int) -> Int {
  let mut i = off
  while i > 0 && between_words_at(t, prev_boundary(t, i)) {
    i = prev_boundary(t, i)
  }
  if i == 0 {
    return 0
  }
  let p = prev_boundary(t, i)
  imin(word_at(t, p).0, p)
}

///|
/// The end of the word after `off` in `t` (the one it is in, or the one after what lies between them).
fn word_end_after(t : String, off : Int) -> Int {
  let n = t.length()
  let mut i = off
  while i < n && between_words_at(t, i) {
    i = next_boundary(t, i)
  }
  if i >= n {
    return n
  }
  imax(word_at(t, i).1, next_boundary(t, i))
}

///|
/// The start of the word after the one `off` is in (Windows' Ctrl+→): the rest of that word, and what lies after it,
/// passed over.
fn next_word_start(t : String, off : Int) -> Int {
  let n = t.length()
  let mut i = off
  if i < n && !between_words_at(t, i) {
    i = imax(word_at(t, i).1, next_boundary(t, i))
  }
  while i < n && between_words_at(t, i) {
    i = next_boundary(t, i)
  }
  i
}

///|
/// The start (`d` -1) or the end (1) of the paragraph of `t` that `off` is in: after the line break before it, before
/// the one after it.
fn paragraph_end(t : String, off : Int, d : Int) -> Int {
  let n = t.length()
  let mut i = off
  if d < 0 {
    while i > 0 && !is_nl(t.code_unit_at(i - 1).to_int()) {
      i = i - 1
    }
  } else {
    while i < n && !is_nl(t.code_unit_at(i).to_int()) {
      i = i + 1
    }
  }
  i
}

///|
/// Whether the caret shows at the end of the line before where a line wraps into the next at it (EditorState's
/// `upstream`): its own place, words being composed none.
fn EditorState::caret_up(self : EditorState) -> Bool {
  self.upstream == self.caret && self.marked == ""
}

///|
/// Where offset `off` shows in `tl` (x, line), as the caret there would: at the end of the line before, where it is
/// the caret's and the caret shows so (EditorState's `upstream`).
fn EditorState::place_of(self : EditorState, tl : TextLayout, off : Int) -> (Double, Int) {
  tl.caret_side(off, off == self.caret && self.caret_up())
}

///|
/// The caret put nearest to (`x`, `y`) in the window, laid out as `tl` (the anchor left where it is): shown on the line
/// the point is on, at its end where the point is past it and the line wraps into the next there.
fn EditorState::caret_to_point(self : EditorState, tl : TextLayout, x : Double, y : Double) -> Unit {
  let line = imin(imax(((y - self.oy) / tl.line_h).to_int(), 0), imax(tl.line_start.length() - 1, 0))
  let (off, up) = tl.offset_on(x - self.ox, line)
  self.caret = imin(off, self.text.length())
  self.upstream = if up { self.caret } else { -1 }
}

///|
/// Where `r` reaches from `off` (`up`: the caret is there, shown at the end of the line before), and whether the caret
/// there shows so too.
fn EditorState::reach(self : EditorState, off : Int, r : Reach, up : Bool) -> (Int, Bool) {
  let t = self.text
  let n = t.length()
  match r {
    Grapheme(d) => (if d < 0 { prev_boundary(t, off) } else { next_boundary(t, off) }, false)
    Line(d) =>
      match self.tl {
        Some(tl) => {
          let (x, line) = tl.caret_side(off, up)
          if self.pref_x < 0.0 {
            self.pref_x = x
          }
          let target = line + d
          if target < 0 {
            (0, false)
          } else if target >= tl.line_start.length() {
            (n, false)
          } else {
            tl.offset_on(self.pref_x, target)
          }
        }
        None => (off, false)
      }
    // (a secret's words are all one, as a password field's: where it has words is not given away)
    Word(_) | NextWord if self.secret => (if r.dir() < 0 { 0 } else { n }, false)
    Word(d) => (if d < 0 { word_start_before(t, off) } else { word_end_after(t, off) }, false)
    NextWord => (next_word_start(t, off), false)
    LineEnd(d) =>
      match self.tl {
        Some(tl) => tl.line_end_at(off, up, d)
        None => (paragraph_end(t, off, d), false)
      }
    Para(d) => (paragraph_end(t, off, d), false)
    ParaOver(d) => (paragraph_end(t, if d < 0 { prev_boundary(t, off) } else { next_boundary(t, off) }, d), false)
    All(d) => (if d < 0 { 0 } else { n }, false)
  }
}

///|
/// The caret moved by `r` (`widen`: what is picked widened to where it goes; `up`: it showed at a line's end, as
/// `upstream` said before the key). Not widening, a move goes from the end of what is picked it goes towards, a
/// character's only to there.
fn EditorState::move_by(self : EditorState, r : Reach, widen : Bool, up : Bool) -> Unit {
  let (a, b) = self.sel()
  let back = r.dir() < 0
  if !widen && a != b && r is Grapheme(_) {
    self.move_to(if back { a } else { b }, false)
  } else {
    let from = if widen || a == b {
      self.caret
    } else if back {
      a
    } else {
      b
    }
    let (to, to_up) = self.reach(from, r, up && from == self.caret)
    self.move_to(to, widen)
    if to_up {
      self.upstream = to
    }
  }
  if !(r is Line(_)) {
    self.pref_x = -1.0
  }
}

///|
/// What lies between the caret and where `r` reaches from it deleted (what is picked instead, when anything is); a
/// reach that comes to the caret itself (⌘⌫ at a line's start) takes the character that way, as a Mac's fields do.
fn EditorState::erase(self : EditorState, r : Reach, up : Bool) -> Unit {
  self.pref_x = -1.0
  if self.delete_selection() {
    return
  }
  let t = self.text
  let to = match self.reach(self.caret, r, up) {
    (to, _) if to != self.caret => to
    _ => self.reach(self.caret, Grapheme(r.dir()), false).0
  }
  let a = imin(to, self.caret)
  let b = imax(to, self.caret)
  if a < b {
    self.text = sub(t, 0, a) + sub(t, b, t.length())
    self.caret = a
    self.anchor = a
  }
}

///|
fn EditorState::key(self : EditorState, code : Int, mods : Int, now : Double) -> Unit {
  // (one the app takes for itself: not the field's)
  if mods == 0 && self.leaves.contains(code) {
    return
  }
  let shift = (mods & mod_shift) != 0
  self.blink0 = now
  self.handle = false
  // a key (the menu's own included) puts the menu away; what is picked loses its handles, but for all of it picked
  // by a finger's menu, which keeps both (Compose's TextFieldSelectionManager.selectAll)
  let picked = self.sel_handles
  let menu_was = self.menu
  self.menu = false
  self.sel_handles = false
  // the caret at a line's end shows there until a key moves it (a move to one says so again)
  let up = self.caret_up()
  self.upstream = -1
  let t = self.text
  let (anchor, caret) = (self.anchor, self.caret)
  match edit_of(code, mods, h_platform()) {
    Some(Move(r)) => self.move_by(r, shift, up)
    Some(Erase(r)) => self.erase(r, up)
    None =>
      if code == key_select_all {
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
            self.put_text(2, "", 0, 0, now)
          }
          self.insert("\n")
        } else {
          // (the words stay: what is done with them, a message sent and its field emptied, is the app's; empty too,
          // whether there is anything to send is the app's: a picture waiting with no words, the web's form submitted)
          self.submitted = Some(self.text)
        }
      }
  }
  // kept to undo (editor_undo.mbt): a cut a step of its own, a deletion or a new line typing
  self.edited(t, anchor, caret, code != key_cut)
}

///|
/// What the host's text event `kind` does to the field (put_text), kept to undo (editor_undo.mbt): a paste a step of
/// its own, all else typing.
fn EditorState::text_input(
  self : EditorState,
  kind : Int,
  s : String,
  a : Int,
  b : Int,
  now : Double,
) -> Unit {
  let (text, anchor, caret) = (self.text, self.anchor, self.caret)
  self.put_text(kind, s, a, b, now)
  self.edited(text, anchor, caret, kind != text_paste)
}

///|
/// kind 0 commits text (text_paste the same, what the clipboard held), 1 sets the composition (with its selection),
/// 2 commits the composition as it is.
fn EditorState::put_text(
  self : EditorState,
  kind : Int,
  s : String,
  a : Int,
  b : Int,
  now : Double,
) -> Unit {
  self.blink0 = now
  self.pref_x = -1.0
  // what is typed lets the handle go (Compose: shown again by the next tap), and the menu and a pick's handles, and
  // the caret's place at a line's end
  if kind != text_composing {
    self.handle = false
    self.menu = false
    self.sel_handles = false
    self.upstream = -1
  }
  if kind == 0 || kind == text_paste {
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
/// What Enter does in a field holding `max_lines` lines with the keyboard's action key `ime_action` (0 none), by the
/// way the words come in (pointing): with a keyboard it gives the words up; with a finger's keyboard it starts a new
/// line where there can be one and the keyboard has no key of its own for the field (a message's: Send is a button),
/// else it is that key (a search's, an address's go) or the one line's end, giving them up.
pub fn enter_sends_by(max_lines : Int, ime_action : Int) -> Bool {
  pointing() is Mouse || max_lines <= 1 || ime_action != 0
}

///|
/// A field of words. `enter_sends`: whether Enter gives the words up (`submitted`) rather than starting a new line;
/// unsaid, the way the words come in decides (enter_sends_by): a keyboard's Enter gives them up (Shift+Enter a new
/// line); a finger's keyboard's Enter is a new line where the field holds more than one and the keyboard has no key of
/// its own for it (`ime_action`), else that key, giving them up. `placeholder`: what it shows while nothing is typed in
/// it, on one line; `shorter`, other ways to say that where the field has less room, each shorter than the one before
/// (搜索全部内容, then 搜索): the longest of them all that fits is shown whole, the shortest cut with an ellipsis only
/// where none does, as Ctx::text's words (Node::hint_shown).
pub fn Ctx::editor(
  self : Ctx,
  key : String,
  placeholder? : String = "",
  shorter? : Array[String] = no_words,
  w? : Size = Fill(1.0),
  font_size? : Double = 15.0,
  max_lines? : Int = 5,
  plain? : Bool = false,
  line? : Double = 0.0,
  trim? : Bool = false,
  color? : Int64 = 0x1D1D1FFFL,
  placeholder_color? : Int64 = 0x8E8E93FFL,
  caret_color? : Int64 = 0x0A84FFFFL,
  enter_sends? : Bool,
  leaves? : Array[Int] = [],
  ime_action? : Int = 0,
  paste_limit? : Int = 0,
  secret? : Bool = false,
  words? : Bool = false,
  look? : (String) -> (String, Array[(Int, Int, Int64)]),
  field? : Field,
  files? : Bool = false,
) -> EditorResult {
  let id = self.id(key)
  // (what the hand does to it, read so: the keys and words typed, a press on it, the pointer while a press on it drags
  // its caret, what is picked in it or a handle of it: hand.mbt; not a press elsewhere)
  hand_events_read()
  hand.down.get() |> ignore
  if self.down && (self.active == id || self.word_drag == id || self.handle_drag == id) {
    hand.pointer.get() |> ignore
  }
  // (the focus in it: its caret and what the keys do, each frame; a part kept builds it each frame, kept_part.mbt)
  if self.has_focus(id) {
    part_live()
  }
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
      let s = EditorState::fresh("", self.clock)
      self.editors[id] = s
      self.own(id)
      s
    }
  }
  st.limit = paste_limit
  st.enter_sends = enter_sends.unwrap_or(enter_sends_by(max_lines, ime_action))
  st.leaves = leaves
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
  // ⌘V with files or a picture on the clipboard, read for it: where it takes files (Ctx::field_files) the files, else
  // the picture as one; else the words with them put in as a paste's
  match desk.pasting {
    Some((pid, r)) if pid == id =>
      match r.got() {
        Some(got) => {
          desk.pasting = None
          match (got.files, got.picture) {
            ([_, ..] as fs, _) if files => {
              desk.pasted[id] = fs
              self.read_changed("files pasted")
            }
            ([], Png(png)) if files => {
              desk.pasted[id] = [(pasted_picture_name, png)]
              self.read_changed("a picture pasted")
            }
            _ => if got.text != "" { st.text_input(text_paste, got.text, 0, 0, self.clock) }
          }
        }
        None => ()
      }
    _ => ()
  }
  // words a screen reader put in it (Action::SetText): in place of all it held, as though typed
  match self.text_asked(id) {
    Some(t) => {
      st.marked = ""
      st.anchor = 0
      st.caret = st.text.length()
      st.text_input(0, t, 0, 0, self.clock)
    }
    None => ()
  }
  // Android's long press on it (the finger still, held long_press_ms: one that moves past the slop is no tap, app.mbt): the word there picked, its handles and the
  // floating menu, felt (Compose's text field); the finger sliding on from there widens it by words (`editor_tap`
  // is Android's alone: elsewhere a press on a field puts the caret at once)
  if self.editor_tap == id &&
    self.down &&
    !self.dragging &&
    self.held_told != self.press_at {
    // (a moment: the frame at it woken, wake_in)
    let held = self.clock - self.press_at
    if held >= long_press_ms {
      self.held_told = self.press_at
      self.take_press()
      self.editor_tap = 0
      self.focus = id
      if st.pick_word(self.press_x, self.press_y, self.clock) {
        self.word_drag = id
      }
      haptic(LongPress)
    } else {
      self.wake_in(long_press_ms - held)
    }
  }
  if st.blink_again {
    st.blink_again = false
    st.blink0 = self.clock
  }
  st.line = line
  st.color = color
  st.ph_color = placeholder_color
  st.caret_color = caret_color
  st.sel_color = (caret_color & 0xFFFFFF00L) | 0x40L
  let focused = self.has_focus(id)
  let i = self.alloc(kind_editor)
  // in Tab's order (focus.mbt); its keys are its own
  self.focusable(id, node=i, keys=0, on_press=true)
  self.semantics(i, TextField, id~, label=placeholder, value=if secret { "" } else { st.text }, actions=[SetText("")])
  let n = self.nodes[i]
  // (the system's size of words: as Ctx::text's)
  let font_size = self.sp(font_size)
  let line = if line > 0.0 { self.sp(line) } else { self.theme.text_line * font_size }
  let (_, _, own_lh) = font_metrics(font_size, 400)
  let lh = if line > 0.0 { line } else { own_lh }
  n.id = id
  self.id_built(i)
  n.hit = true
  n.w = w
  n.font_size = font_size
  n.line_h = line
  n.line_trim = trim
  n.clip = true
  n.wrap = max_lines > 1
  n.text = placeholder
  n.shorter = shorter
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
  // more than a line: its words scroll in it as a box kept to a height does (sideways.mbt: the wheel, a finger, a fling,
  // its scroll bar), how far the layout's (layout.mbt)
  if max_lines > 1 {
    let sw = self.scroll_state(id, true)
    sw.field = true
    sw.theme = self.theme
    sw.built_frame = self.frame_no
    self.nodes[i].scroller = id
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
/// How long a caret blinks after it last moved (a word typed, the caret moved, the field focused): then it stays shown
/// and asks for no more frames, as GTK's stops after 10 s. A window left with a field focused draws nothing, and what
/// drawing holds goes back: on macOS the driver's own 30 to 50 MB a second or two after the last frame, and the
/// window's drawables (apple_render.m trim).
pub let caret_blinks_for_ms : Double = 30000.0

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
/// Where the caret at `off` is drawn in the field `n`, laid out as `tl` (x, y, w, h; round, its ends half circles):
/// about where it stands, kept in the field (where the words start at the field's edge, as a field with no frame of its
/// own has them, the field's clip would cut half of it at a line's start; Compose's TextFieldCursor.kt coerces it so
/// too); its line's whole height on Android (Compose's), elsewhere 2 short of each end. Android's handle hangs from its
/// foot's middle.
fn EditorState::caret_box(
  self : EditorState,
  tl : TextLayout,
  n : Node,
  off : Int,
) -> (Double, Double, Double, Double) {
  let (cx, cl) = self.place_of(tl, off)
  let top = self.oy + cl.to_double() * tl.line_h
  let x = dmax(n.x, dmin(self.ox + cx - caret_w / 2.0, n.x + n.fw - caret_w))
  if h_feel() == 2 {
    (x, top, caret_w, tl.line_h)
  } else {
    (x, top + 2.0, caret_w, tl.line_h - 4.0)
  }
}

///|
/// What the field `n` shows while nothing is typed in it, laid out in its `line` (EditorState's): its placeholder on one
/// line, as words that do not wrap, said the longest way that fits the room its words have (Ctx::editor `shorter`), the
/// shortest cut with an ellipsis where none does; never cut by the field's edge.
fn Node::hint_shown(self : Node, line : Double) -> TextLayout {
  let lay = self.hint_lay(line)
  said_in(self.text, lay(self.text), self.shorter, self.fw - self.pad_l - self.pad_r, lay)
}

///|
/// How the field `n` lays its placeholder out on one line, in its `line`.
fn Node::hint_lay(self : Node, line : Double) -> (String) -> TextLayout {
  fn(s) { layout_text(s, self.font_size, 400, 1.0e9, false, line~, trim=self.line_trim) }
}

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
  // (its rect within the clip it is in, as a box's (push_round_clip): its own alone let its words show past what cuts
  // it, a growing composer's new line under its foot over its send, 2026-10-30)
  let k = clip_top()
  push_clip(
    dmax(n.x, clip_stack[k]),
    dmax(n.y, clip_stack[k + 1]),
    dmin(n.x + n.fw, clip_stack[k + 2]),
    dmin(n.y + n.fh, clip_stack[k + 3]),
  )
  let i0 = self.ninst
  // its scroll bar, where its words scroll in it (scroll_bar.mbt)
  let bar = if sideways.contains(n.id) { self.bar_at(n) } else { None }
  let focused = self.has_focus(n.id)
  let ml = st.marked.length()
  // selection
  let (a, b) = st.sel()
  if focused && a != b && ml == 0 {
    let (x0, l0) = st.place_of(tl, a)
    let (x1, l1) = st.place_of(tl, b)
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
    // (a placeholder in no ink at all, hidden for now, is not drawn: nothing there to be seen or read)
    if (st.ph_color & 0xFFL) != 0L {
      self.emit_text(n.hint_shown(st.line), st.ox, st.oy, st.ph_color, alpha)
    }
  } else {
    let spans = if st.secret { [] } else { st.look_shown().1 }
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
    let since = self.clock - st.blink0
    let (phase, next) = periods_at(self.clock, st.blink0, caret_blink())
    // blinking till caret_blinks_for_ms, then shown at rest
    let resting = since >= caret_blinks_for_ms
    if !resting {
      self.wake_at_time(dmin(next, st.blink0 + caret_blinks_for_ms), later=true)
    }
    let coff = if ml > 0 { st.caret + st.msel_a } else { st.caret }
    if resting || phase % 2 == 0 {
      let (x, y, w, h) = st.caret_box(tl, n, coff)
      self.emit_rect(x, y, w, h, w / 2.0, st.caret_color, 0.0, 0L, alpha)
    }
  }
  // where its words go on past an edge (scrolled up, down, along), they fade out towards it, as far as they go on (a
  // line's worth at most): not cut off there (the user, 2026-10-30: 「现在有很多粗暴裁剪的」)
  let up = st.scroll
  let down = dmax(0.0, tl.h - (n.fh - n.pad_t - n.pad_b)) - st.scroll
  let back = st.scroll_x
  let on = dmax(0.0, tl.w - dmax(0.0, n.fw - n.pad_l - n.pad_r - caret_w)) - st.scroll_x
  if up > 0.0 || down > 0.0 || back > 0.0 || on > 0.0 {
    let a = self.inst
    for q in i0..<self.ninst {
      inst_fade(a, q * inst_size, n.y, cut_soft(up, up), n.y + n.fh, cut_soft(down, down))
      inst_fade_across(a, q * inst_size, n.x, cut_soft(back, back), n.x + n.fw, cut_soft(on, on))
    }
  }
  match bar {
    Some(b) => self.paint_bar(b, alpha)
    None => ()
  }
  pop_clip()
  // Android's handle under the caret (Compose's cursor handle, TextFieldSelectionManager): a drop in the caret's colour
  // hanging from the middle of its foot, a circle 25 across under a corner turned to point up, over everything (a
  // popup's, a window of its own over the app's on Android: no box cuts it and nothing painted after it covers it,
  // Ctx::paint_top)
  if focused && st.handle && h_feel() == 2 && a == b && ml == 0 && st.text.length() > 0 {
    let (cx, cy, cw, ch) = st.caret_box(tl, n, st.caret)
    let x = cx + cw / 2.0
    let y = cy + ch
    st.handle_on = true
    st.handle_x = x
    st.handle_y = y
    let r = handle_r
    push_unclipped()
    let (outer, _, _) = clip_at(clip_top())
    let i0 = self.ninst
    self.emit_rect(x, y, 2.0 * r, 2.0 * r, r, st.caret_color, 0.0, 0L, alpha)
    self.emit_rect(x, y, r, r, 0.0, st.caret_color, 0.0, 0L, alpha)
    turn_insts(self.inst, i0, self.ninst, 3.141592653589793 / 4.0, x, y, outer)
    pop_clip()
    self.paint_top(i0)
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
    let (ax, al) = st.place_of(tl, a)
    let (bx, bl) = st.place_of(tl, b)
    st.sel_ax = st.ox + ax
    st.sel_ay = st.oy + (al + 1).to_double() * tl.line_h
    st.sel_bx = st.ox + bx
    st.sel_by = st.oy + (bl + 1).to_double() * tl.line_h
    st.sel_on = true
    push_unclipped()
    let i0 = self.ninst
    // the start's: the circle to the tip's left, its square corner at the tip
    self.emit_rect(st.sel_ax - 2.0 * r, st.sel_ay, 2.0 * r, 2.0 * r, r, st.caret_color, 0.0, 0L, alpha)
    self.emit_rect(st.sel_ax - r, st.sel_ay, r, r, 0.0, st.caret_color, 0.0, 0L, alpha)
    // the end's: to its right
    self.emit_rect(st.sel_bx, st.sel_by, 2.0 * r, 2.0 * r, r, st.caret_color, 0.0, 0L, alpha)
    self.emit_rect(st.sel_bx, st.sel_by, r, r, 0.0, st.caret_color, 0.0, 0L, alpha)
    pop_clip()
    self.paint_top(i0)
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
          let (cx, cl) = st.place_of(tl, coff)
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
    upstream: -1,
    floating: None,
    scroll: 0.0,
    scroll_x: 0.0,
    followed: (-1, -1, -1),
    pasted: None,
    limit: 0,
    enter_sends: true,
    leaves: [],
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
    undos: [],
    redos: [],
    typed: None,
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
/// (words kept put back, a mark put in, a word taken out whole). What the input method was composing is let go; new
/// words let go of the person's edits kept to undo.
pub fn Field::set(self : Field, text : String, caret? : Int) -> Unit {
  let st = self.st
  let at = match caret {
    Some(k) => imin(imax(k, 0), text.length())
    None => text.length()
  }
  if st.text == text && st.marked == "" && st.caret == at && st.anchor == at {
    return
  }
  if st.text != text {
    st.forget_edits()
  }
  st.marked = ""
  st.text = text
  st.caret = at
  st.anchor = at
  st.pref_x = -1.0
  st.upstream = -1
  if text == "" {
    st.scroll = 0.0
    st.scroll_x = 0.0
  }
  // the caret shown at once where it is put; and a frame to draw it, written from wherever it was (an answer between
  // frames, a fiber, a timer), as the input's own changes have
  st.blink_again = true
  field_written()
}

///|
/// The colours of what it shows while nothing is in it and of its caret, said again after its editor was built this
/// frame (Ctx::editor's `placeholder_color`, `caret_color`): drawn as said here, as its words are as Field::set left
/// them. For what empties it in the same build after it (words sent from it: their hint and caret gone with them from
/// the frame they go, not shown once over them).
pub fn Field::colors(self : Field, placeholder~ : Int64, caret~ : Int64) -> Unit {
  self.st.ph_color = placeholder
  self.st.caret_color = caret
  self.st.sel_color = (caret & 0xFFFFFF00L) | 0x40L
}

///|
/// Its words from `from` to `to` picked (UTF-16, in its words: the anchor at `from`, the caret at `to`), as a name
/// changed in place picks it but its extension.
pub fn Field::pick(self : Field, from : Int, to : Int) -> Unit {
  let st = self.st
  st.anchor = imin(imax(from, 0), st.text.length())
  st.caret = imin(imax(to, 0), st.text.length())
  st.pref_x = -1.0
  st.upstream = -1
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
      if st.text != text {
        st.forget_edits()
      }
      st.marked = ""
      st.text = text
      st.caret = text.length()
      st.anchor = st.caret
      st.upstream = -1
      st.blink0 = self.clock
    }
    None => {
      let st = EditorState::fresh(text, self.clock)
      self.editors[id] = st
      self.own(id)
    }
  }
}

///|
/// Pastes what the clipboard holds into the field `id` (an edit menu's 粘贴), as ⌘V (Ctrl+V) with files or a picture
/// on it does: read first, then its files or its picture where the field takes files (Ctx::field_files), else its
/// words.
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
/// What a pasted picture is named as a file (as a browser names a page's pasted one).
pub let pasted_picture_name : String = "image.png"

///|
/// The files pasted into the field `key` (one that takes files: Ctx::editor `files`) with ⌘V (Ctrl+V) or its menu's
/// 粘贴, each its name and bytes: those on the clipboard (copied in Finder), else its picture as PNG
/// (`pasted_picture_name`), as a page's paste takes the clipboard's files. Taken once, for the app to put in.
pub fn Ctx::field_files(self : Ctx, key : String) -> Array[(String, Bytes)]? {
  let id = self.id(key)
  let got = desk.pasted.get(id)
  desk.pasted.remove(id)
  got
}

///|
/// Whether the editor `key` has the focus (the keyboard is its).
pub fn Ctx::editor_focused(self : Ctx, key : String) -> Bool {
  self.has_focus(self.id(key))
}

///|
/// Lets go of the focus: no field takes keys, the keyboard goes; no layer that closes later gives it back to what had
/// it as the layer opened (it was let go of, not taken by the layer: a tip, a toast, a menu over the field). What had it
/// is drawn let go of from the frame it was let go in, as the focus given is (Ctx::focus_on).
pub fn Ctx::blur(self : Ctx) -> Unit {
  let had = self.focus != 0
  self.focus = 0
  for k in self.layer_return.keys().collect() {
    self.layer_return[k] = 0
  }
  if had {
    self.read_changed("the focus let go")
  }
}

// ── words picked by a finger (Android's: Compose's text field selection) ──────────────────────────────────────

///|
/// How soon a second tap on a field picks the word there (ViewConfiguration's double tap timeout).
pub let double_tap_ms : Double = 300.0

///|
/// The word at (`x`, `y`) in the field picked (a long press's, a double tap's): its two handles, the floating menu
/// over it. False when there is none there (nothing under the finger but spaces, or no words at all: the caret put
/// there instead, the menu over it all the same, to paste: Android's EditText offers 粘贴 in an empty field too).
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
  self.upstream = -1
  if b <= a || self.secret {
    self.caret = off
    self.anchor = off
    self.sel_handles = false
    self.menu = true
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
/// What a double click picks in a field and a drag on from it goes by (Words), and a triple click's (Paragraphs).
priv enum PickBy {
  Words
  Paragraphs
}

///|
/// The word (a secret's words all one, as a move by words has them) or the paragraph `off` is in.
fn EditorState::unit_at(self : EditorState, off : Int, by : PickBy) -> (Int, Int) {
  match by {
    Words if self.secret => (0, self.text.length())
    Words => word_at(self.text, off)
    Paragraphs => (paragraph_end(self.text, off, -1), paragraph_end(self.text, off, 1))
  }
}

///|
/// A double click's (`by` Words) or a triple click's (Paragraphs), the caret put where it was pressed: the word or the
/// paragraph there picked, what a drag on from it widens from (`word_a`, `word_b`).
fn EditorState::pick_at(self : EditorState, by : PickBy) -> Unit {
  let (a, b) = self.unit_at(self.caret, by)
  if b > a {
    self.anchor = a
    self.caret = b
  }
  self.word_a = self.anchor
  self.word_b = self.caret
}

///|
/// A press with Shift at (`x`, `y`) (a mouse's): what is picked widened to there from its anchor, what was composed
/// committed first.
fn EditorState::widen_by_pointer(self : EditorState, x : Double, y : Double, t : Double) -> Unit {
  self.blink0 = t
  self.menu = false
  self.sel_handles = false
  match self.tl {
    Some(tl) => {
      if self.marked.length() > 0 {
        self.text_input(2, "", 0, 0, t)
      }
      self.caret_to_point(tl, x, y)
    }
    None => ()
  }
}

///|
/// A finger sliding on from a long press's word, or a mouse dragged on from a double click's (a triple click's: `by`
/// Paragraphs): the selection widened by them to where it is (Compose's word granularity), from the one first picked.
fn EditorState::widen_to(self : EditorState, x : Double, y : Double, by? : PickBy = Words) -> Unit {
  let tl = match self.tl {
    Some(t) => t
    None => return
  }
  let off = imin(tl.offset_at(x - self.ox, y - self.oy), self.text.length())
  let (a, b) = self.unit_at(off, by)
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
          st.text_input(text_paste, paste, 0, 0, self.clock)
        }
      } else if what == @hostapi.text_menu_cut {
        st.key(key_cut, 0, self.clock)
      } else if what == @hostapi.text_menu_copy {
        st.key(key_copy, 0, self.clock)
      } else if what == @hostapi.text_menu_select_all {
        st.key(key_select_all, 0, self.clock)
      }
      self.focus_on(id)
      self.read_changed("a field edited")
    }
    None => ()
  }
}

///|
/// Tells the host what the menu bar's editing items can do now (@hostapi.edit_can), said again only when it changes:
/// the focused field's (what its right-click menu offers, and its edits to undo and do again, none while the input
/// method composes), and copy where words are picked with the pointer (the field focused or not).
fn Ctx::sync_edit_can(self : Ctx) -> Unit {
  let pointer = if selected_words() != "" { @hostapi.text_menu_copy } else { 0 }
  let can = match self.editors.get(self.focus) {
    Some(st) =>
      st.can() |
      pointer |
      (if st.undos.length() > 0 && st.marked == "" { @hostapi.text_menu_undo } else { 0 }) |
      (if st.redos.length() > 0 && st.marked == "" { @hostapi.text_menu_redo } else { 0 })
    None => pointer
  }
  if can == self.edit_can_told {
    return
  }
  self.edit_can_told = can
  h_edit_can(can)
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
          let (x0, l0) = st.place_of(tl, a)
          let (x1, l1) = st.place_of(tl, b)
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
