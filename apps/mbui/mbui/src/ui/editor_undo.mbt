// A field's edits undone and done again: ⌘Z and ⇧⌘Z on Apple's systems, Ctrl+Z and Ctrl+Y (Ctrl+Shift+Z) elsewhere,
// and the menu bar's 撤销 and 重做, which press them. Each of the person's edits is kept as the field was before it. A
// run of typing (what is typed and deleted at the caret, one after another, nothing else done between) is one step, as
// a Mac's and a browser's fields keep it (NSTextView's typing, Blink's TypingCommand while open); a paste and a cut are
// each a step of their own. What the app writes in it (Field::set) is not the person's edit: what was kept is let go
// of, as Compose's TextFieldState does after an edit of the program's.

///|
/// Which way a key goes through a field's edits: the last one undone, or the last undone done again.
priv enum Step {
  Undo
  Redo
}

///|
/// How many steps a field keeps to undo (Blink's UndoStack, kMaximumUndoStackDepth); past them the oldest is let go of.
let undo_depth = 1000

///|
/// What key `code` with `mods` held is to a field on system `platform` (@ui.platform), as that system's own fields
/// have it: ⌘Z and ⇧⌘Z on Apple's; Ctrl+Z, Ctrl+Y and Ctrl+Shift+Z elsewhere (Blink's EditingBehavior). None: neither.
fn step_of(code : Int, mods : Int, platform : Int) -> Step? {
  let cmd = match platform {
    0 | 1 => mod_cmd
    _ => mod_ctrl
  }
  let held = mods & (mod_shift | mod_ctrl | mod_alt | mod_cmd)
  if code == key_of_char('z') && held == cmd {
    Some(Undo)
  } else if code == key_of_char('z') && held == (cmd | mod_shift) {
    Some(Redo)
  } else if code == key_of_char('y') && held == mod_ctrl && cmd == mod_ctrl {
    Some(Redo)
  } else {
    None
  }
}

///|
/// An edit made, the field having been `text` with its anchor and caret there before it: kept to undo, what was undone
/// let go of. Typing (`typing`) from where the last typing left the field goes on in that step instead. Nothing when
/// its words are as they were.
fn EditorState::edited(self : EditorState, text : String, anchor : Int, caret : Int, typing : Bool) -> Unit {
  if self.text == text {
    return
  }
  let goes_on = typing && self.typed == Some((text, anchor, caret))
  if !goes_on {
    self.undos.push((text, anchor, caret))
    if self.undos.length() > undo_depth {
      self.undos.remove(0) |> ignore
    }
  }
  self.redos.clear()
  self.typed = if typing { Some((self.text, self.anchor, self.caret)) } else { None }
}

///|
/// What was kept to undo and to do again let go of: the app wrote its words.
fn EditorState::forget_edits(self : EditorState) -> Unit {
  self.undos.clear()
  self.redos.clear()
  self.typed = None
}

///|
/// The field's last edit undone, as it was before it, what was picked then picked again (Undo); or the last undone
/// done again (Redo). Nothing while the input method composes (its keys are its own then), nor when there is none.
fn EditorState::step(self : EditorState, s : Step, now : Double) -> Unit {
  self.step_edit(s, now)
  self.words_told()
}

///|
/// An undo or redo of it (EditorState::step's), done.
fn EditorState::step_edit(self : EditorState, s : Step, now : Double) -> Unit {
  if self.marked.length() > 0 {
    return
  }
  let (from, to) = match s {
    Undo => (self.undos, self.redos)
    Redo => (self.redos, self.undos)
  }
  guard from.pop() is Some((text, anchor, caret)) else { return }
  to.push((self.text, self.anchor, self.caret))
  self.put_words(text)
  self.anchor = anchor
  self.caret = caret
  self.typed = None
  self.pref_x = -1.0
  self.upstream = -1
  self.handle = false
  self.menu = false
  self.sel_handles = false
  self.blink0 = now
}
