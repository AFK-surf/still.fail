// What a mouse, a trackpad and a keyboard bring beyond a finger, for an app in a desktop's window (macOS, Windows, a
// browser): a secondary click (a context menu's), the pointer's shape over what is under it, keys as shortcuts, the
// window dragged by the app's own top row (a window with no title bar of its own), a wheel's notches eased. Hosts
// with no pointer (iOS, Android) never send what these read.

///|
/// The pointer's shape over something (Ctx::cursor): the arrow, a hand (what is pressed), the text's I-beam, a
/// resizing edge's (sideways, up and down), an open hand (what is dragged).
pub(all) enum Cursor {
  Arrow
  Hand
  IBeam
  ResizeX
  ResizeY
  Grab
} derive(Eq, Show, Debug)

///|
fn Cursor::code(self : Cursor) -> Int {
  match self {
    Arrow => 0
    Hand => 1
    IBeam => 2
    ResizeX => 3
    ResizeY => 4
    Grab => 5
  }
}

///|
/// A key's code as hosts send it, beyond the editor's (editor.mbt: 1 Backspace … 16 Page Down): Escape, Tab, and a
/// character typed with ⌘ (macOS) or Ctrl (elsewhere) held: 1000 + the character (lower case).
pub let key_escape : Int = 17

///|
pub let key_tab : Int = 18

///|
pub fn key_of_char(ch : Char) -> Int {
  1000 + ch.to_int()
}

///|
/// The editor's codes, for an app reading keys (Ctx::key_pressed).
pub let key_code_enter : Int = 7

///|
pub let key_code_up : Int = 5

///|
pub let key_code_down : Int = 6

///|
pub let key_code_left : Int = 3

///|
pub let key_code_right : Int = 4

///|
pub let key_code_home : Int = 8

///|
pub let key_code_end : Int = 9

///|
pub let key_code_page_up : Int = 15

///|
pub let key_code_page_down : Int = 16

///|
/// Select all, copy, cut: the keys a field takes for them (a shortcut's, the floating text menu's: @hostapi.text_menu).
pub let key_code_select_all : Int = 12

///|
pub let key_code_copy : Int = 13

///|
pub let key_code_cut : Int = 14

///|
/// Modifiers in a key's `mods`: Shift, Ctrl, Alt (Option), ⌘ (the Windows key, Meta).
pub let mod_shift_key : Int = 1

///|
pub let mod_ctrl : Int = 2

///|
pub let mod_alt : Int = 4

///|
pub let mod_cmd : Int = 8

///|
priv struct Desk {
  /// what was clicked with the secondary button since the last frame: the targets under it (topmost first), where
  mutable_menus : Array[(Array[Int], Double, Double)]
  /// what this frame reads of them (moved over from `mutable_menus` as a frame starts)
  menus : Array[(Array[Int], Double, Double)]
  /// what asked for a menu (Ctx::menu_asked) as the frame those targets are of was built, and as this one is
  askers : Array[Int]
  next_askers : Array[Int]
  /// keys since the last frame: code, modifiers, whether a field took it
  mutable_keys : Array[(Int, Int, Bool)]
  keys : Array[(Int, Int, Bool)]
  /// the pointer's shape by target, as this frame's build says, and as the last one's said
  next_cursors : Map[Int, Int]
  mut cursors : Map[Int, Int]
  /// the shape the host shows
  mut shown : Int
  /// targets that drag the window (Ctx::window_drag), this frame's and the last one's
  next_drags : Array[Int]
  mut drags : Array[Int]
  /// targets a press on keeps what is picked with the pointer (Ctx::keeps_selection), this frame's and the last one's
  next_keeps : Array[Int]
  mut keeps : Array[Int]
  /// ⌘V (Ctrl+V) with a picture on the clipboard, the host's app key: the read under way and the field it is for; a
  /// picture read for a field that takes pictures (Ctx::editor `pictures`), by its id, until the app takes it
  mut pasting : (Int, ClipboardRead)?
  pictures : Map[Int, Bytes]
  /// lists dragged by the mouse as a finger drags them (true unless the app says not), as this frame's build says and
  /// as the last one's said
  mut next_mouse_drags : Bool
  mut mouse_drags : Bool
  /// rich text built now is picked with the pointer (Ctx::selectable), and in what colour picked words are grounded
  mut selecting : Bool
  mut sel_color : Int64
  /// the paragraphs that can be picked, as this frame paints them and as the last one did: their id, layout, words,
  /// where their text starts, the part of them shown (x0, y0, x1, y1)
  next_sels : Array[SelTarget]
  mut sels : Array[SelTarget]
}

///|
priv struct SelTarget {
  base : Int
  lay : RichLayout
  text : String
  ox : Double
  oy : Double
  x0 : Double
  y0 : Double
  x1 : Double
  y1 : Double
}

///|
/// What is picked with the pointer: in which paragraph (0: nothing), from its anchor to where the pointer took it, and
/// whether the pointer is still taking it.
priv struct Picked {
  mut base : Int
  mut a : Int
  mut b : Int
  mut dragging : Bool
  mut text : String
  mut target : SelTarget?
}

///|
let picked : Picked = { base: 0, a: 0, b: 0, dragging: false, text: "", target: None }

///|
let desk : Desk = {
  mutable_menus: [],
  menus: [],
  askers: [],
  next_askers: [],
  mutable_keys: [],
  keys: [],
  next_cursors: {},
  cursors: {},
  shown: 0,
  next_drags: [],
  drags: [],
  next_keeps: [],
  keeps: [],
  pasting: None,
  pictures: {},
  next_mouse_drags: true,
  mouse_drags: true,
  selecting: false,
  sel_color: 0x3B82F64DL,
  next_sels: [],
  sels: [],
}

///|
fn desk_reset() -> Unit {
  desk.mutable_menus.clear()
  desk.menus.clear()
  desk.askers.clear()
  desk.next_askers.clear()
  desk.mutable_keys.clear()
  desk.keys.clear()
  desk.next_cursors.clear()
  desk.cursors.clear()
  desk.shown = 0
  desk.next_drags.clear()
  desk.drags.clear()
  desk.next_keeps.clear()
  desk.keeps.clear()
  desk.pasting = None
  desk.pictures.clear()
  desk.next_mouse_drags = true
  desk.mouse_drags = true
  desk.selecting = false
  desk.next_sels.clear()
  desk.sels = []
  picked.base = 0
  picked.dragging = false
  picked.target = None
  select_last.val = (-1.0e9, 0.0, 0.0)
}

///|
/// As a frame starts: what came since the last one is what this one reads.
fn desk_frame_start() -> Unit {
  desk.menus.clear()
  for m in desk.mutable_menus {
    desk.menus.push(m)
  }
  desk.mutable_menus.clear()
  // (what asked in the frame before: what was under a right click since was laid out by it)
  desk.askers.clear()
  for a in desk.next_askers {
    desk.askers.push(a)
  }
  desk.next_askers.clear()
  desk.keys.clear()
  for k in desk.mutable_keys {
    desk.keys.push(k)
  }
  desk.mutable_keys.clear()
}

///|
/// As the view is built (each time a frame builds it: frame_body): the shapes, drag areas and selections it says
/// begin from none.
fn desk_build_start() -> Unit {
  desk.next_cursors.clear()
  desk.next_drags.clear()
  desk.next_keeps.clear()
  desk.next_mouse_drags = true
  desk.next_sels.clear()
  desk.selecting = false
}

///|
/// As a frame ends (its targets in place): the shapes and drag areas it said are the ones in force, the pointer's
/// target found again where it rests (what moved under it), its shape shown.
fn Ctx::desk_frame_end(self : Ctx) -> Unit {
  let cs = desk.cursors
  desk.cursors = desk.next_cursors.copy()
  cs.clear()
  desk.drags = desk.next_drags.copy()
  desk.keeps = desk.next_keeps.copy()
  desk.mouse_drags = desk.next_mouse_drags
  desk.sels = desk.next_sels.copy()
  if !self.down && self.px >= 0.0 {
    if pointing() is Finger {
      // a finger lifted is nowhere: what it last touched is not hovered, and the pointer is not over it (this frame,
      // the one after it was lifted, still read where it was, for what a tap there opens)
      self.px = -1.0
      self.py = -1.0
      self.hover = 0
    } else {
      self.hover = hit_in(self.hit_ids, self.hit_rects, self.px, self.py)
    }
  }
  self.show_cursor()
}

///|
/// The shape for what is under the pointer (or held: what is dragged keeps its shape), told the host when it changes.
fn Ctx::show_cursor(self : Ctx) -> Unit {
  let target = if self.down && self.active != 0 { self.active } else { self.hover }
  let kind = match desk.cursors.get(target) {
    Some(k) => k
    None =>
      if target != 0 && self.editors.contains(target) {
        Cursor::IBeam.code()
      } else if sel_at(self.px, self.py) is Some(_) {
        // words that are picked with the pointer
        Cursor::IBeam.code()
      } else {
        0
      }
  }
  if kind != desk.shown {
    desk.shown = kind
    h_set_cursor(kind)
  }
}

///|
/// The pointer is `cursor` over `id` (a target: a box with an id). Said each frame it is drawn; a field shows the
/// I-beam without being told.
pub fn Ctx::cursor(self : Ctx, id : Int, cursor : Cursor) -> Unit {
  ignore(self)
  if id != 0 {
    desk.next_cursors[id] = cursor.code()
  }
}

///|
/// Where `id` was clicked with the secondary button (a right click; Ctrl-click on macOS) since the last frame, in the
/// window's terms: for its context menu. It counts for what is under the pointer and what holds it.
pub fn Ctx::right_clicked(self : Ctx, id : Int) -> (Double, Double)? {
  ignore(self)
  for m in desk.menus {
    if m.0.contains(id) {
      return Some((m.1, m.2))
    }
  }
  None
}

///|
/// Where a menu of `id` was asked for since the last frame, in the window's terms: by a mouse, its secondary button
/// clicked on it (Ctx::right_clicked); by a finger, held on it (long_press_ms, still: the press is then no click).
/// For a menu the web's `contextmenu` opens (a row's, a place's), on either hand. One press, one menu: a right click is
/// the innermost asker's under it (a row's, not the list's it sits in, though the list is asked first: its rows are
/// built after it), as a press goes to one target; a hold is already the target's held.
pub fn Ctx::menu_asked(self : Ctx, id : Int) -> (Double, Double)? {
  if id != 0 {
    desk.next_askers.push(id)
  }
  let mut at : (Double, Double)? = None
  for m in desk.menus {
    if m.0.contains(id) {
      // (the first under it, topmost first, that asked for a menu as the frame it was laid out in was built: what
      // asks for the first time this frame goes by itself)
      let innermost = match m.0.iter().find_first(fn(u) { desk.askers.contains(u) }) {
        Some(u) => u
        None => id
      }
      if innermost == id {
        at = Some((m.1, m.2))
      }
    }
  }
  match at {
    Some(at) => Some(at)
    None =>
      if pointing() is Finger && self.held_long(id) {
        Some((self.px, self.py))
      } else {
        None
      }
  }
}

///|
/// Whether anything was clicked with the secondary button since the last frame (what closes a menu as another opens).
pub fn Ctx::any_right_click(self : Ctx) -> Bool {
  ignore(self)
  desk.menus.length() > 0
}

///|
/// A press on `id` drags the window (and a double click on it zooms it, as the system's title bar does): the app's
/// own top row, in a window with none of the system's (@hostapi.window_setup `inset`). Said each frame it is drawn.
pub fn Ctx::window_drag(self : Ctx, id : Int) -> Unit {
  ignore(self)
  if id != 0 {
    desk.next_drags.push(id)
  }
}

///|
/// Whether a mouse's drag moves a list as a finger does (a phone's page in a window: true, as before); false on a
/// desktop's page, where the wheel and the trackpad scroll and a drag is the pointer's own. Said each frame: a frame
/// that does not say it drags them (a wide window made narrow).
pub fn Ctx::mouse_drags_lists(self : Ctx, on : Bool) -> Unit {
  ignore(self)
  desk.next_mouse_drags = on
}

///|
/// Whether key `code` came since the last frame with exactly `mods` held (with `in_field`, also one a focused field
/// took: an Enter it sent, an arrow it moved by).
pub fn Ctx::key_pressed(self : Ctx, code : Int, mods? : Int = 0, in_field? : Bool = false) -> Bool {
  // (under an open menu or dialog, none: they are its)
  if !self.keys_here() {
    return false
  }
  for k in desk.keys {
    if k.0 == code && k.1 == mods && (in_field || !k.2) {
      return true
    }
  }
  false
}

///|
/// Key `code` with exactly `mods` held, if it came since the last frame and nothing took it yet: taken now (what reads
/// keys after this does not see it). For a widget's own keys while it has the focus (a slider's arrows).
pub fn Ctx::take_key(self : Ctx, code : Int, mods? : Int = 0) -> Bool {
  if !self.keys_here() {
    return false
  }
  for k in 0..<desk.keys.length() {
    let (kc, km, taken) = desk.keys[k]
    if kc == code && km == mods && !taken {
      desk.keys[k] = (kc, km, true)
      return true
    }
  }
  false
}

///|
/// Whether `ch` came with the platform's command key held (⌘ on macOS, Ctrl elsewhere), and Shift if `shift`:
/// a shortcut (⌘K).
pub fn Ctx::shortcut(self : Ctx, ch : Char, shift? : Bool = false) -> Bool {
  let cmd = if h_platform() == 0 { mod_cmd } else { mod_ctrl }
  self.key_pressed(key_of_char(ch), mods=cmd | (if shift { mod_shift_key } else { 0 }))
}

///|
/// The keys since the last frame (code, modifiers, whether a field took it); none under an open menu or dialog (they
/// are its).
pub fn Ctx::keys(self : Ctx) -> Array[(Int, Int, Bool)] {
  if !self.keys_here() {
    return []
  }
  desk.keys
}

///|
/// The focused field let go of (the keyboard's words go nowhere until another is pressed).
pub fn Ctx::unfocus(self : Ctx) -> Unit {
  self.focus = 0
}

///|
/// Whether a field has the keyboard.
pub fn Ctx::field_focused(self : Ctx) -> Bool {
  self.focus != 0 && self.editors.contains(self.focus)
}

///|
/// A secondary press at (x, y) (on_pointer's button 2): recorded for Ctx::right_clicked, nothing pressed.
fn Ctx::secondary_press(self : Ctx, x : Double, y : Double) -> Unit {
  let under : Array[Int] = []
  let mut k = self.hit_ids.length() - 1
  while k >= 0 {
    let r = k * 4
    if x >= self.hit_rects[r] &&
      x < self.hit_rects[r + 2] &&
      y >= self.hit_rects[r + 1] &&
      y < self.hit_rects[r + 3] &&
      in_round_clip(self.hit_clips, k, x, y) &&
      !under.contains(self.hit_ids[k]) {
      under.push(self.hit_ids[k])
    }
    k = k - 1
  }
  desk.mutable_menus.push((under, x, y))
  // a press all the same for what lies over the page (overlay.mbt)
  self.press_down = Some((x, y))
  self.px = x
  self.py = y
}

///|
/// The pointer left the window: nothing is under it.
fn Ctx::pointer_left(self : Ctx) -> Unit {
  if self.down {
    return
  }
  self.px = -1.0
  self.py = -1.0
  self.hover = 0
  self.show_cursor()
}

///|
/// A key, recorded for the app to read (Ctx::key_pressed) whether a field takes it or not.
fn desk_key(code : Int, mods : Int, taken : Bool) -> Unit {
  desk.mutable_keys.push((code, mods, taken))
}

///|
/// Whether a press at the target `id` drags the window (and so is the host's from here).
fn desk_drags(id : Int) -> Bool {
  id != 0 && desk.drags.contains(id)
}

///|
/// `body` built for a part of the window `w` by `h` (a pane beside a sidebar): what it reads of the Ctx's size
/// (`width`, `height`), and its lists' rows built later as they are laid out, are that part's, not the window's.
pub fn Ctx::sized(self : Ctx, w : Double, h : Double, body : () -> Unit) -> Unit {
  let (sw, sh) = (self.width, self.height)
  self.width = w
  self.height = h
  body()
  self.width = sw
  self.height = sh
}

///|
/// The rich text `body` builds (and its lists' rows) is picked with the pointer: pressed and dragged over, its words
/// are selected (in `color`), ⌘C (Ctrl+C) copies them; a press elsewhere lets them go. A desktop's page, where the
/// mouse drags no list (Ctx::mouse_drags_lists false).
pub fn Ctx::selectable(self : Ctx, body : () -> Unit, color? : Int64 = 0x3B82F64DL) -> Unit {
  ignore(self)
  let saved = desk.selecting
  desk.selecting = true
  desk.sel_color = color
  body()
  desk.selecting = saved
}

///|
/// The words picked with the pointer ("" none).
pub fn Ctx::selected_text(self : Ctx) -> String {
  ignore(self)
  selected_words()
}

///|
fn selected_words() -> String {
  if picked.base == 0 || picked.a == picked.b {
    return ""
  }
  let (a, b) = if picked.a < picked.b { (picked.a, picked.b) } else { (picked.b, picked.a) }
  let n = picked.text.length()
  let a = if a > n { n } else { a }
  let b = if b > n { n } else { b }
  picked.text.unsafe_substring(start=a, end=b)
}

///|
/// A paragraph that can be picked, as painted (rich.mbt paint_rich).
fn selectable_painted(
  base : Int,
  lay : RichLayout,
  text : String,
  ox : Double,
  oy : Double,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
) -> Unit {
  let t = { base, lay, text, ox, oy, x0, y0, x1, y1 }
  desk.next_sels.push(t)
  // the paragraph picked from moves with what moves it (the list scrolled): its place is this frame's
  if picked.base == base {
    picked.target = Some(t)
    picked.text = text
  }
}

///|
/// What of paragraph `base` is picked: a rectangle a line, in its text's terms.
fn selected_rects(base : Int, lay : RichLayout) -> Array[(Double, Double, Double, Double)] {
  if picked.base != base || picked.a == picked.b {
    return []
  }
  let (a, b) = if picked.a < picked.b { (picked.a, picked.b) } else { (picked.b, picked.a) }
  lay.rects(a, b)
}

///|
/// The paragraph that can be picked under (x, y), the topmost.
fn sel_at(x : Double, y : Double) -> SelTarget? {
  if desk.mouse_drags || x < 0.0 {
    return None
  }
  let mut k = desk.sels.length() - 1
  while k >= 0 {
    let t = desk.sels[k]
    if x >= t.x0 && x < t.x1 && y >= t.y0 && y < t.y1 {
      return Some(t)
    }
    k = k - 1
  }
  None
}

///|
/// A primary press at (x, y) at `t`: on words that are picked with the pointer, picking starts there (the second of
/// two quick presses there picks the word under it, as a browser's double click does); elsewhere what was picked is
/// let go.
fn select_press(x : Double, y : Double, t : Double) -> Unit {
  let (was, ax, ay) = select_last.val
  select_last.val = (t, x, y)
  match sel_at(x, y) {
    Some(target) => {
      let off = target.lay.offset_at(x - target.ox, y - target.oy)
      picked.base = target.base
      picked.a = off
      picked.b = off
      picked.dragging = true
      picked.text = target.text
      picked.target = Some(target)
      if t - was <= double_click_ms && (x - ax).abs() <= double_click_slop && (y - ay).abs() <= double_click_slop {
        let (s, e) = word_at(target.text, off)
        picked.a = s
        picked.b = e
        picked.dragging = false
        select_last.val = (-1.0e9, 0.0, 0.0)
      }
    }
    None => {
      picked.base = 0
      picked.dragging = false
      picked.target = None
    }
  }
}

///|
/// A press on `id` keeps what is picked with the pointer (a button that does something with it, as a page's control
/// whose press is not the words' with mousedown's preventDefault: a quote of what is picked). Said each frame it is
/// drawn.
pub fn Ctx::keeps_selection(self : Ctx, id : Int) -> Unit {
  ignore(self)
  desk.next_keeps.push(id)
}

///|
/// Whether a press on `target` keeps what is picked (Ctx::keeps_selection).
fn keeps_selection_on(target : Int) -> Bool {
  desk.keeps.contains(target)
}

///|
/// When and where the last press that could pick went down (a double click's first).
let select_last : Ref[(Double, Double, Double)] = Ref((-1.0e9, 0.0, 0.0))

///|
/// Where what is picked with the pointer lies in the window, once the pointer has let it go (the box round its
/// lines), or None: none picked, or still being dragged.
pub fn Ctx::selection_box(self : Ctx) -> (Double, Double, Double, Double)? {
  ignore(self)
  if picked.base == 0 || picked.a == picked.b || picked.dragging {
    return None
  }
  match picked.target {
    Some(t) => {
      let rects = selected_rects(t.base, t.lay)
      if rects.length() == 0 {
        return None
      }
      let mut x0 = 1.0e9
      let mut y0 = 1.0e9
      let mut x1 = -1.0e9
      let mut y1 = -1.0e9
      for r in rects {
        x0 = dmin(x0, r.0)
        y0 = dmin(y0, r.1)
        x1 = dmax(x1, r.0 + r.2)
        y1 = dmax(y1, r.1 + r.3)
      }
      Some((x0 + t.ox, y0 + t.oy, x1 - x0, y1 - y0))
    }
    None => None
  }
}

///|
/// What is picked with the pointer let go (a quote taken from it).
pub fn Ctx::selection_clear(self : Ctx) -> Unit {
  ignore(self)
  picked.base = 0
  picked.dragging = false
  picked.target = None
}

///|
/// The pointer moved while picking: the picked words go to it. True once some are (the press is no tap then).
fn select_move(x : Double, y : Double) -> Bool {
  if !picked.dragging {
    return false
  }
  match picked.target {
    Some(t) => {
      picked.b = t.lay.offset_at(x - t.ox, y - t.oy)
      picked.a != picked.b
    }
    None => false
  }
}
