// What an app asks of the device beyond its window (as @hostapi's device.mbt has it), through the framework, so that under
// a Tester the device is the test's: a key catcher (an unseen focus that takes the keyboard, the soft one or one
// plugged in, and keeps no text: what is typed comes to the app as keys and text, as still.fail's Android KeyCatcher
// sends a remote screen), the soft keyboard's height, the clipboard read (an outside ticket, answered at a frame's
// boundary; a real host's answer kept on the run's tape, CLIPSAID, and given again to a Tester replaying it) and
// written, the screen kept awake, a haptic.
//
// A key catcher's input comes as any input does (app.mbt's on_key and on_text, kept on the tape as INPUT lines), and
// is worked into what the app reads as its frame builds (Ctx::key_catcher's `keys`):
//   text committed            Text of each line, an Enter tapped between lines
//   text composed             nothing yet: sent once committed, or as the composition is finished
//   delete around the caret   while composing, the composition shortened; else that many Backspace, then Delete taps
//   a named key               its tap (down, up): Enter, Backspace, Delete, Tab, Escape, the arrows, Home, End,
//                             Page Up, Page Down, Space
//   a character with Ctrl, Alt or ⌘ held   its key's tap (a shortcut: Ctrl+C is "c", KeyC, ctrl)
// Keys and codes are named as the DOM's KeyboardEvent names them (`key`, `code`); `mods` are a remote screen's bits
// (key_in_alt, key_in_ctrl, key_in_meta, key_in_shift). The framework's keys are presses: a key comes as its tap.
//
//   CLIPSAID {"text":T,"picture":"none"|"png"|"too_large"|"unreadable","png":HEX}   the clipboard as the app took it

///|
/// A haptic (@ui.haptic), as still.fail's Android app has them: Android's constant for each (Compose's
/// HapticFeedbackType.LongPress is LONG_PRESS, TextHandleMove TEXT_HANDLE_MOVE), the nearest elsewhere.
pub(all) enum Haptic {
  /// a long press took something (a row's menu, words picked)
  LongPress
  /// a context click (two fingers' tap as a right click)
  ContextClick
  /// a step passed while dragging (a handle moved, a swipe past its line)
  TextHandleMove
  /// something done
  Confirm
  /// something refused
  Reject
  /// a key tapped
  KeyboardTap
} derive(Eq, Show, Debug)

///|
fn Haptic::code(self : Haptic) -> Int {
  match self {
    LongPress => @hostapi.haptic_long_press
    ContextClick => @hostapi.haptic_context_click
    TextHandleMove => @hostapi.haptic_text_handle_move
    Confirm => @hostapi.haptic_confirm
    Reject => @hostapi.haptic_reject
    KeyboardTap => @hostapi.haptic_keyboard_tap
  }
}

///|
/// A haptic of `kind` (@hostapi.haptic); a Tester's host keeps it (Tester::haptics).
pub fn haptic(kind : Haptic) -> Unit {
  match fake.val {
    Some(f) => f.dev.haptics.push(kind)
    None => @hostapi.haptic(kind.code())
  }
}

///|
/// The screen kept on while the app is in front (`on`), or let sleep again (@hostapi.keep_awake); a Tester's host keeps
/// what it was last told (Tester::awake).
pub fn keep_awake(on : Bool) -> Unit {
  match fake.val {
    Some(f) => f.dev.awake = on
    None => @hostapi.keep_awake(on)
  }
}

///|
/// Words put on the clipboard, `label` what the system shows of where they came from (a screen's title); a Tester's
/// host holds them (Tester::clipboard, clipboard_label).
pub fn clipboard_set(text : String, label? : String = "") -> Unit {
  match fake.val {
    Some(f) => {
      f.clipboard = text
      f.dev.clip_png = None
      f.dev.clip_label = label
    }
    None => @hostapi.clip_set_text(text, label)
  }
}

///|
/// A picture (PNG's bytes) put on the clipboard (@hostapi.clip_set_png), in place of what it held; a Tester's host holds
/// it (Tester::clipboard_png).
pub fn clipboard_set_png(png : Bytes, label? : String = "") -> Unit {
  match fake.val {
    Some(f) => {
      f.clipboard = ""
      f.dev.clip_png = Some(png)
      f.dev.clip_label = label
    }
    None => @hostapi.clip_set_png(png, label)
  }
}

///|
/// The real host's word on whether it says a copy itself, asked once (a Tester never reads it: its own is
/// Tester::new's `copy_shown`).
// kept across runs: the real host's (asked once); a Tester answers from its fake host
let host_copy_shown : Ref[Int] = { val: -1 }

///|
/// Whether the system says itself that something was put on the clipboard (Android 13 and later show it, with a
/// preview): then the app does not say it again. Kept on the run's tape (ENV's `copy`); a Tester's is its `copy_shown`.
pub fn copy_shown() -> Bool {
  match fake.val {
    Some(f) => f.dev.copy_shown
    None => {
      if host_copy_shown.val < 0 {
        host_copy_shown.val = if @hostapi.copy_shown() { 1 } else { 0 }
      }
      host_copy_shown.val == 1
    }
  }
}

///|
/// A picture on the clipboard, as the app takes it.
pub(all) enum ClipPicture {
  /// none
  NoPicture
  /// one, as PNG (another kind made one), at most @hostapi.clip_png_max bytes
  Png(Bytes)
  /// one past the bounds (@hostapi.clip_too_large)
  TooLarge
  /// one that could not be read
  Unreadable
} derive(Eq, Show, Debug)

///|
/// What the clipboard held: its words ("" none), its picture, its files (copied in macOS's Finder, or by an app that
/// copies a picture as its file: each its name and bytes, @hostapi.ClipGot's).
pub(all) struct Clipboard {
  text : String
  picture : ClipPicture
  files : Array[(String, Bytes)]
} derive(Eq, Show, Debug)

///|
/// A read of the clipboard under way (clipboard_read), waited on (an outside ticket) until it is taken.
pub struct ClipboardRead {
  priv host : @hostapi.ClipRead?
  priv fake : Int
  priv taken : Ref[Bool]
}

///|
priv struct FakeClipRead {
  /// the frame it was asked in, and its answer with the frame it was given in: taken from the frame after both
  frame : Int
  mut answer : (Clipboard, Int)?
}

///|
/// What a Tester's host has of the device: the screen kept awake, the haptics fired, the picture on the clipboard and
/// the label of what was put there, whether the system says a copy itself, the soft keyboard's height, whether the
/// focus is a key catcher's, the clipboard's reads asked and the answers given before an ask.
priv struct FakeDevice {
  mut awake : Bool
  haptics : Array[Haptic]
  mut clip_png : Bytes?
  mut clip_label : String
  mut copy_shown : Bool
  mut ime_inset : Double
  mut key_catch : Bool
  /// the input method's action the app last said (@hostapi.ime_action)
  mut ime_action : Int
  reads : Array[FakeClipRead]
  held : Array[Clipboard]
  /// the app's native calls (native.mbt), their answers given before a call (by its name), and the answers given by
  /// themselves (Tester::native_answers)
  natives : Array[FakeNative]
  native_held : Array[(String, Result[Json, String])]
  native_auto : Map[String, (Json) -> Result[Json, String]]
}

///|
fn FakeDevice::new(copy_shown : Bool) -> FakeDevice {
  {
    awake: false,
    haptics: [],
    clip_png: None,
    clip_label: "",
    copy_shown,
    ime_inset: 0.0,
    key_catch: false,
    ime_action: 0,
    reads: [],
    held: [],
    natives: [],
    native_held: [],
    native_auto: {},
  }
}

///|
/// The clipboard read (@hostapi.clip_read): its words and its picture, from the frame after the host has read it
/// (ClipboardRead::got). None where the host cannot. Under a Tester, what the test gives (Tester::clipboard_gives…):
/// until it does, the read is waited on (the app is not at rest).
pub fn clipboard_read() -> ClipboardRead? {
  match fake.val {
    Some(f) => {
      let ask = { frame: g().frame_no, answer: None }
      if f.dev.held.length() > 0 {
        ask.answer = Some((f.dev.held.remove(0), g().frame_no))
        f.wants = true
      }
      f.dev.reads.push(ask)
      let r : ClipboardRead = { host: None, fake: f.dev.reads.length() - 1, taken: Ref::new(false) }
      outside_start(outside_clip, r.outside_id(), "the clipboard read \{r.outside_id()}")
      Some(r)
    }
    None =>
      match @hostapi.clip_read() {
        Some(h) => {
          let r : ClipboardRead = { host: Some(h), fake: -1, taken: Ref::new(false) }
          outside_start(outside_clip, r.outside_id(), "the clipboard read \{r.outside_id()}")
          Some(r)
        }
        None => None
      }
  }
}

///|
/// Its id as the host's event names it (outside_clip), a Tester's its ask's place, from 1.
fn ClipboardRead::outside_id(self : ClipboardRead) -> Int {
  match self.host {
    Some(h) => h.id()
    None => self.fake + 1
  }
}

///|
/// What the clipboard held, once read: None while it is read, and once taken (taken once: keep it).
pub fn ClipboardRead::got(self : ClipboardRead) -> Clipboard? {
  if self.taken.val || !answer_here(outside_clip, self.outside_id()) {
    return None
  }
  let got = match self.host {
    Some(h) => h.got().map(clipboard_of)
    None =>
      match fake.val {
        Some(f) if self.fake >= 0 && self.fake < f.dev.reads.length() =>
          match f.dev.reads[self.fake].answer {
            Some((c, at)) if g().frame_no > at => Some(c)
            _ => None
          }
        _ => None
      }
  }
  if got is Some(c) {
    self.taken.val = true
    answer_taken(outside_clip, self.outside_id())
    outside_end(outside_clip, self.outside_id())
    clip_said(c)
  }
  got
}

///|
fn clipboard_of(h : @hostapi.ClipGot) -> Clipboard {
  let picture = if h.picture == @hostapi.clip_png {
    Png(h.png)
  } else if h.picture == @hostapi.clip_too_large {
    TooLarge
  } else if h.picture == @hostapi.clip_unreadable {
    Unreadable
  } else {
    NoPicture
  }
  { text: h.text, picture, files: h.files }
}

///|
/// The clipboard as the app took it, on the run's tape (CLIPSAID), for a Tester replaying it to give again.
fn clip_said(c : Clipboard) -> Unit {
  if !taping() {
    return
  }
  let (kind, png) = match c.picture {
    NoPicture => ("none", "")
    Png(b) => ("png", @codec.hex(b))
    TooLarge => ("too_large", "")
    Unreadable => ("unreadable", "")
  }
  let m : Map[String, Json] = {
    "text": Json::string(c.text),
    "picture": Json::string(kind),
    "png": Json::string(png),
  }
  if c.files.length() > 0 {
    m["files"] = Json::array(
      c.files.map(fn(f) { Json::object({ "name": Json::string(f.0), "bytes": Json::string(@codec.hex(f.1)) }) }),
    )
  }
  tape_line("CLIPSAID " + Json::object(m).stringify())
}

///|
/// A CLIPSAID line's clipboard (None: not one).
fn clip_of_line(line : String) -> Clipboard? {
  guard line.find("CLIPSAID ") is Some(i) else { return None }
  let j = @json.parse(line.view(start_offset=i + 9).to_owned()) catch { _ => return None }
  guard j is Object(m) else { return None }
  let str = fn(k : String) -> String {
    match m.get(k) {
      Some(String(s)) => s
      _ => ""
    }
  }
  let picture = match str("picture") {
    "png" => Png(@codec.from_hex(str("png")))
    "too_large" => TooLarge
    "unreadable" => Unreadable
    _ => NoPicture
  }
  let files = match m.get("files") {
    Some(Array(fs)) =>
      fs.filter_map(fn(f) {
        guard f is Object(fm) else { return None }
        match (fm.get("name"), fm.get("bytes")) {
          (Some(String(name)), Some(String(hex))) => Some((name, @codec.from_hex(hex)))
          _ => None
        }
      })
    _ => []
  }
  Some({ text: str("text"), picture, files })
}

///|
/// The clipboard holds `clip` for the app's read asked first and not answered yet (else for its next read): taken
/// from the next frame.
fn fake_clip_give(f : FakeHost, clip : Clipboard) -> Unit {
  for a in f.dev.reads {
    if a.answer is None {
      a.answer = Some((clip, g().frame_no))
      f.wants = true
      return
    }
  }
  f.dev.held.push(clip)
}

///|
/// The app's read of the clipboard answered with `text` (its read asked first and not yet answered; else its next):
/// taken from the next frame, as a host's answer comes at a frame's boundary. Until a read is answered, the app is not
/// at rest.
pub fn Tester::clipboard_gives(self : Tester, text : String) -> Unit {
  fake_clip_give(self.fake, { text, picture: NoPicture, files: [] })
}

///|
/// The same, the clipboard holding a picture (`png`, as the host gives it: PNG's bytes), and `text` beside it.
pub fn Tester::clipboard_gives_png(self : Tester, png : Bytes, text? : String = "") -> Unit {
  fake_clip_give(self.fake, { text, picture: Png(png), files: [] })
}

///|
/// The same, the clipboard holding files (their names and bytes, as Finder copies them), and `text` beside them (what
/// Finder puts there too: their names).
pub fn Tester::clipboard_gives_files(self : Tester, files : Array[(String, Bytes)], text? : String = "") -> Unit {
  fake_clip_give(self.fake, { text, picture: NoPicture, files })
}

///|
/// The same, with all that the host may say of it (an empty clipboard, a picture too large or unreadable).
pub fn Tester::clipboard_gives_clip(self : Tester, clip : Clipboard) -> Unit {
  fake_clip_give(self.fake, clip)
}

///|
/// How many times the app asked to read the clipboard.
pub fn Tester::clipboard_reads(self : Tester) -> Int {
  self.fake.dev.reads.length()
}

///|
/// The picture the app last put on the clipboard (None: it holds none, words put there after it).
pub fn Tester::clipboard_png(self : Tester) -> Bytes? {
  self.fake.dev.clip_png
}

///|
/// The label of what the app last put on the clipboard.
pub fn Tester::clipboard_label(self : Tester) -> String {
  self.fake.dev.clip_label
}

///|
/// Whether the app last asked for the screen to be kept awake.
pub fn Tester::awake(self : Tester) -> Bool {
  self.fake.dev.awake
}

///|
/// The haptics the app fired, oldest first.
pub fn Tester::haptics(self : Tester) -> Array[Haptic] {
  self.fake.dev.haptics.copy()
}

///|
/// The soft keyboard reaching `h` points over the window's foot (0: down), from the next frame on, as a host says it
/// while it moves (the window's own size is the test's: a host lays the app out above the keyboard).
pub fn Tester::set_ime_inset(self : Tester, h : Double) -> Unit {
  self.fake.dev.ime_inset = h
  self.fake.wants = true
}

///|
/// Whether the host was last told the focus is a key catcher's (its keyboard the app's, keys and all).
pub fn Tester::key_catching(self : Tester) -> Bool {
  self.fake.dev.key_catch
}

///|
/// The field as Android's input method left it (its edits made on the host's copy of the words): words `s`, the
/// selection from `a` to `b`, the composing region from `ca` to `cb` (-1: none); the frames it causes drawn.
pub fn Tester::ime_state(self : Tester, s : String, a : Int, b : Int, ca? : Int = -1, cb? : Int = -1) -> Unit {
  on_text(text_composing, "", ca, cb)
  on_text(text_state, s, a, b)
  self.draw()
}

///|
/// The soft keyboard put away by the person (its own key, Back); the frames it causes drawn.
pub fn Tester::keyboard_gone(self : Tester) -> Unit {
  on_text(text_keyboard_gone, "", 0, 0)
  self.draw()
}

///|
/// The keyboard's trackpad (iOS's floating cursor) begins at (`x`, `y`), moves to (`x1`, `y1`) and is let go; the
/// frames it causes drawn.
pub fn Tester::ime_trackpad(self : Tester, x : Int, y : Int, x1 : Int, y1 : Int) -> Unit {
  on_text(text_float_begin, "", x, y)
  self.draw()
  on_text(text_float_move, "", x1, y1)
  self.draw()
}

///|
/// The input method deletes `before` UTF-16 units before the caret and `after` after it (Android's
/// deleteSurroundingText); the frames it causes drawn.
pub fn Tester::ime_delete(self : Tester, before : Int, after : Int) -> Unit {
  on_text(text_delete_around, "", before, after)
  self.draw()
}

///|
/// The input method finishes its composition: what it composed is committed as it is (Android's
/// finishComposingText); the frames it causes drawn.
pub fn Tester::ime_finish(self : Tester) -> Unit {
  on_text(2, "", 0, 0)
  self.draw()
}

///|
/// The input method's text event deleting around the caret (`a` before it, `b` after: on_text's kind).
let text_delete_around = 4

///|
/// The input method's text event saying the composing region (`a` to `b`, -1 none) of the state it sends next.
let text_composing = 6

///|
/// The input method's text event giving the field's whole state: its words, the selection from `a` to `b`.
let text_state = 5

///|
/// The host's event saying the soft keyboard was put away by the person: the field lets go of the focus.
let text_keyboard_gone = 7

///|
/// The host's text event putting in the clipboard's words (a paste: ⌘V, the edit menu's): as kind 0 puts in what is
/// typed, but a step of its own to undo, not one with the typing about it (editor_undo.mbt).
let text_paste = 8

///|
/// The host's text event saying the keyboard's trackpad (iOS's floating cursor: a long press on the space bar) begins,
/// at (`a`, `b`) in the window, in points.
let text_float_begin = 9

///|
/// The host's text event saying the keyboard's trackpad moved to (`a`, `b`) in the window, in points: the caret goes as
/// far from where it was when it began as that is from where it began.
let text_float_move = 10

///|
fn h_ime_action(kind : Int) -> Unit {
  match fake.val {
    Some(f) => f.dev.ime_action = kind
    None => @hostapi.ime_action(kind)
  }
}

///|
fn h_key_catch(on : Bool) -> Unit {
  match fake.val {
    Some(f) => f.dev.key_catch = on
    None => @hostapi.key_catch(on)
  }
}

///|
fn h_ime_inset() -> Double {
  match fake.val {
    Some(f) => f.dev.ime_inset
    None => @hostapi.ime_inset()
  }
}

///|
/// What a key catcher has typed into it, as the app reads it (see the file's head).
pub(all) enum KeyIn {
  /// words, committed by the input method (or typed on a keyboard)
  Text(String)
  /// a key going down or up: the DOM's `key` and `code`, the modifiers held (key_in_*)
  Key(down~ : Bool, key~ : String, code~ : String, mods~ : Int)
} derive(Eq, Show, Debug)

///|
/// A KeyIn's modifiers: Alt (Option), Ctrl, Meta (⌘, the Windows key), Shift.
pub let key_in_alt : Int = 1

///|
pub let key_in_ctrl : Int = 2

///|
pub let key_in_meta : Int = 4

///|
pub let key_in_shift : Int = 8

///|
/// A key catcher as this frame builds it: its id (what Ctx::focus_on gives the keyboard to), whether it has the focus
/// (the keyboard is the app's), and what was typed into it since the last frame.
pub struct KeyCatch {
  id : Int
  focused : Bool
  keys : Array[KeyIn]
}

///|
/// The device's state a window keeps: its key catchers by id, the soft keyboard's height as this frame began.
struct DeviceState {
  catchers : Map[Int, Catcher]
  mut ime_inset : Double
}

///|
fn DeviceState::new() -> DeviceState {
  { catchers: {}, ime_inset: 0.0 }
}

///|
/// A key catcher's state: what the input method composes (not sent until committed), what came since the frame that
/// last read it, what this frame reads, and which frame that is.
struct Catcher {
  mut composing : String
  came : Array[KeyIn]
  mut keys : Array[KeyIn]
  mut frame : Int
  /// the old view it was last built in (view_host.mbt's island_allows), none in a layer of its own: whether its focus
  /// may take input now (Ctx::focus_allowed)
  mut island : @view.NodeId?
}

///|
fn Ctx::catcher_of(self : Ctx, id : Int) -> Catcher {
  match self.dev.catchers.get(id) {
    Some(st) => st
    None => {
      let st = { composing: "", came: [], keys: [], frame: -1, island: None }
      self.dev.catchers[id] = st
      st
    }
  }
}

///|
/// A key catcher (see the file's head): unseen, it takes the keyboard while it has the focus (Ctx::catch_keys raises
/// the soft keyboard, or puts it away) and keeps no text of its own; what was typed since the last frame is `keys`,
/// the same in every build of this frame. A press elsewhere leaves it the focus, as a field's.
pub fn Ctx::key_catcher(self : Ctx, key : String) -> KeyCatch {
  let id = self.id(key)
  let st = self.catcher_of(id)
  st.island = if self.layer_cur == 0 { island_building.val } else { None }
  if st.frame != self.frame_no {
    st.frame = self.frame_no
    st.keys = st.came.copy()
    st.came.clear()
  }
  { id, focused: self.has_focus(id), keys: st.keys }
}

///|
/// The key catcher `key` given the focus (`on`: the soft keyboard raised, the keyboard the app's), or, if it has it,
/// none (the soft keyboard put away).
pub fn Ctx::catch_keys(self : Ctx, key : String, on : Bool) -> Unit {
  let id = self.id(key)
  if on {
    ignore(self.catcher_of(id))
    if self.focus != id {
      self.focus_on(id)
    }
  } else if self.focus == id {
    self.focus_on(0)
  }
}

///|
/// How far the soft keyboard reaches over the window's foot as this frame began, in points (0: down); the window is
/// laid out above it.
pub fn Ctx::ime_inset(self : Ctx) -> Double {
  ignore(self)
  ime_said.get()
}

///|
/// Whether the soft keyboard is up as this frame began: what reads it changes as it comes up or goes down, not as it
/// moves.
pub fn Ctx::keyboard_up(self : Ctx) -> Bool {
  ignore(self)
  ime_up.get()
}

///|
/// The soft keyboard's height as this frame began, and whether it is up: signals of their own, read where they are
/// read (what reads neither is not built again as it moves), not among the host's settings the whole frame reads.
// kept across runs: set as each frame begins
let ime_said : @signals.Signal[Double] = @signals.signal(0.0, same=fn(a, b) { a == b })

///|
// kept across runs: worked out of ime_said as it changes
let ime_up : @signals.Computed[Bool] = @signals.computed(fn(_) { ime_said.get() > 0.0 }, same=fn(a, b) { a == b })

///|
/// As a frame begins: the soft keyboard's height, as the host has it now (kept on the tape: envrec.mbt).
fn Ctx::device_frame_start(self : Ctx) -> Unit {
  self.dev.ime_inset = h_ime_inset()
  ime_said.set(self.dev.ime_inset)
}

///|
/// The modifiers of a key (mod_shift_key, mod_ctrl, mod_alt, mod_cmd) as a KeyIn's.
fn key_in_mods(mods : Int) -> Int {
  (if (mods & mod_alt) != 0 { key_in_alt } else { 0 }) |
  (if (mods & mod_ctrl) != 0 { key_in_ctrl } else { 0 }) |
  (if (mods & mod_cmd) != 0 { key_in_meta } else { 0 }) |
  (if (mods & mod_shift_key) != 0 { key_in_shift } else { 0 })
}

///|
/// The keys that are not text, by the framework's code: the DOM's `key` and `code`.
fn named_key(code : Int) -> (String, String)? {
  match code {
    1 => Some(("Backspace", "Backspace"))
    2 => Some(("Delete", "Delete"))
    3 => Some(("ArrowLeft", "ArrowLeft"))
    4 => Some(("ArrowRight", "ArrowRight"))
    5 => Some(("ArrowUp", "ArrowUp"))
    6 => Some(("ArrowDown", "ArrowDown"))
    7 => Some(("Enter", "Enter"))
    8 => Some(("Home", "Home"))
    9 => Some(("End", "End"))
    15 => Some(("PageUp", "PageUp"))
    16 => Some(("PageDown", "PageDown"))
    17 => Some(("Escape", "Escape"))
    18 => Some(("Tab", "Tab"))
    1032 => Some((" ", "Space"))
    _ => None
  }
}

///|
/// The DOM's `code` of a character typed with a modifier held (c: KeyC); "" for one with no key of its own.
fn code_of_char(ch : Int) -> String {
  if ch >= 'a'.to_int() && ch <= 'z'.to_int() {
    "Key" + (ch - 32).unsafe_to_char().to_string()
  } else if ch >= 'A'.to_int() && ch <= 'Z'.to_int() {
    "Key" + ch.unsafe_to_char().to_string()
  } else if ch >= '0'.to_int() && ch <= '9'.to_int() {
    "Digit" + ch.unsafe_to_char().to_string()
  } else {
    match ch.unsafe_to_char() {
      ' ' => "Space"
      '-' => "Minus"
      '=' => "Equal"
      '[' => "BracketLeft"
      ']' => "BracketRight"
      '\\' => "Backslash"
      ';' => "Semicolon"
      '\'' => "Quote"
      ',' => "Comma"
      '.' => "Period"
      '/' => "Slash"
      '`' => "Backquote"
      _ => ""
    }
  }
}

///|
/// A key pressed and let go.
fn Catcher::tap(self : Catcher, key : String, code : String, mods : Int) -> Unit {
  self.came.push(Key(down=true, key~, code~, mods~))
  self.came.push(Key(down=false, key~, code~, mods~))
}

///|
/// Words typed: each line as text, Enter tapped between them.
fn Catcher::type_words(self : Catcher, s : String) -> Unit {
  let mut first = true
  for line in s.split("\n") {
    if !first {
      self.tap("Enter", "Enter", 0)
    }
    first = false
    let l = line.to_owned()
    if l != "" {
      self.came.push(Text(l))
    }
  }
}

///|
/// A key with the focus a key catcher's: the catcher's (and seen by Ctx::key_pressed's `in_field` only). False when
/// the focus is not one's, or is where a modal layer of the window's tree keeps it from input (Ctx::focus_allowed).
fn catcher_key(c : Ctx, code : Int, mods : Int) -> Bool {
  guard c.dev.catchers.get(c.focus_allowed()) is Some(st) else { return false }
  desk_key(code, mods, true)
  let m = key_in_mods(mods)
  match named_key(code) {
    Some((k, kc)) => st.tap(k, kc, m)
    None =>
      if code > 1000 {
        let ch = code - 1000
        if (mods & (mod_ctrl | mod_alt | mod_cmd)) != 0 {
          // a shortcut: a letter as its key (upper case with Shift), a digit, another character by itself
          let lower = if ch >= 'A'.to_int() && ch <= 'Z'.to_int() { ch + 32 } else { ch }
          let key = if lower >= 'a'.to_int() && lower <= 'z'.to_int() && (mods & mod_shift_key) != 0 {
            (lower - 32).unsafe_to_char().to_string()
          } else {
            lower.unsafe_to_char().to_string()
          }
          st.tap(key, code_of_char(lower), m)
        } else {
          st.came.push(Text(ch.unsafe_to_char().to_string()))
        }
      }
  }
  true
}

///|
/// The input method's text with the focus a key catcher's (see the file's head). False when the focus is not one's
/// (or is kept from input: Ctx::focus_allowed).
fn catcher_text(c : Ctx, kind : Int, s : String, a : Int, b : Int) -> Bool {
  guard c.dev.catchers.get(c.focus_allowed()) is Some(st) else { return false }
  match kind {
    0 => {
      st.composing = ""
      st.type_words(s)
    }
    1 => st.composing = s
    2 => {
      if st.composing != "" {
        st.type_words(st.composing)
      }
      st.composing = ""
    }
    4 =>
      if st.composing != "" {
        let n = st.composing.length() - a
        st.composing = if n <= 0 {
          ""
        } else {
          st.composing.unsafe_substring(start=0, end=n)
        }
      } else {
        for _ in 0..<a {
          st.tap("Backspace", "Backspace", 0)
        }
        for _ in 0..<b {
          st.tap("Delete", "Delete", 0)
        }
      }
    _ => ()
  }
  true
}

///|
/// The input method's action the app last told its host (@hostapi.ime_action_*: a search field's, when one has the
/// focus).
pub fn Tester::ime_action(self : Tester) -> Int {
  self.fake.dev.ime_action
}
