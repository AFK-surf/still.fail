// What a mouse, a trackpad and a keyboard bring beyond a finger, for an app in a desktop's window (macOS, Windows, a
// browser): a secondary click (a context menu's), the pointer's shape over what is under it, keys as shortcuts, the
// window dragged by the app's own top row (a window with no title bar of its own), a wheel's notches eased. Hosts
// with no pointer (iOS, Android) never send what these read.

///|
/// The pointer's shape over something: the arrow, a hand (what takes presses), the text's I-beam, a resizing edge's
/// (sideways, up and down), an open hand (what is dragged), and what another machine's pointer may be drawn as besides
/// (a remote screen's: a closed hand dragging, a crosshair, what cannot be done). What it is over says it
/// (Ctx::show_cursor): a field the I-beam, what takes presses the hand, words picked with the pointer the I-beam; what
/// is none of those as it is (an edge, what a press on goes to a field, a remote screen's pointer) is said so
/// (Ctx::cursor).
pub(all) enum Cursor {
  Arrow
  Hand
  IBeam
  ResizeX
  ResizeY
  Grab
  Grabbing
  Crosshair
  NotAllowed
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
    Grabbing => 6
    Crosshair => 7
    NotAllowed => 8
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
pub let key_code_backspace : Int = 1

///|
pub let key_code_delete : Int = 2

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
/// A field's moves and deletions as a Mac's text system names what a key does (NSResponder's moveWordLeft:,
/// moveToLeftEndOfLine:, deleteToBeginningOfLine:…, its host's doCommandBySelector), each a key of its own, Shift
/// (mod_shift_key) widening what is picked; elsewhere they come as the keys themselves with what is held, which a field
/// reads as that system's fields do (editor.mbt edit_of). By words, back and on:
pub let key_code_word_back : Int = 20

///|
pub let key_code_word_on : Int = 21

///|
/// To the start and the end of the line the caret shows on.
pub let key_code_line_start : Int = 22

///|
pub let key_code_line_end : Int = 23

///|
/// To the start and the end of its paragraph (what lies between line breaks).
pub let key_code_paragraph_start : Int = 24

///|
pub let key_code_paragraph_end : Int = 25

///|
/// To the start and the end of all of it.
pub let key_code_text_start : Int = 26

///|
pub let key_code_text_end : Int = 27

///|
/// To the paragraph's start or end, or the one before's or after's when there already (moveParagraphBackward:).
pub let key_code_paragraph_back : Int = 28

///|
pub let key_code_paragraph_on : Int = 29

///|
/// Deleting a word back and on, to the line's start and end, to the paragraph's start and end.
pub let key_code_delete_word_back : Int = 30

///|
pub let key_code_delete_word_on : Int = 31

///|
pub let key_code_delete_line_back : Int = 32

///|
pub let key_code_delete_line_on : Int = 33

///|
pub let key_code_delete_paragraph_back : Int = 34

///|
pub let key_code_delete_paragraph_on : Int = 35

///|
/// Forward, as hosts send it: a mouse's forward button (its fifth), and Alt+→ on Windows (as Alt+← is its back: the
/// system's back, set_back). What goes forward is the app's to read (Ctx::key_pressed), as a browser's forward.
pub let key_forward : Int = 40

///|
/// Whether a focused field takes key `code` as its own (its moves and deletions, Enter, select all, copy, cut), not
/// Escape, Tab or a character's key.
fn field_key(code : Int) -> Bool {
  code < key_escape || (code >= key_code_word_back && code <= key_code_delete_paragraph_on)
}

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
  /// what was clicked with the secondary button since the last frame: the target under it and what holds it
  /// (innermost first: Ctx::secondary_press), where
  mutable_menus : Array[(Array[Int], Double, Double)]
  /// what this frame reads of them (moved over from `mutable_menus` as a frame starts)
  menus : Array[(Array[Int], Double, Double)]
  /// keys since the last frame: code, modifiers, whether a field took it
  mutable_keys : Array[(Int, Int, Bool)]
  keys : Array[(Int, Int, Bool)]
  /// the shape the host shows
  mut shown : Int
  /// ⌘V (Ctrl+V) with files or a picture on the clipboard, the host's app key: the read under way and the field it is
  /// for; the files read (the picture as one) for a field that takes files (Ctx::editor `files`), by its id, until the
  /// app takes them
  mut pasting : (Int, ClipboardRead)?
  pasted : Map[Int, Array[(String, Bytes)]]
  /// lists dragged by the mouse as a finger drags them (true unless the app says not), as this frame's build says (in
  /// the order said: the last said holds) and as the last one's said
  next_mouse_drags : Array[Bool]
  mut mouse_drags : Bool
  /// rich text built now is picked with the pointer (Ctx::selectable), and in what colour picked words are grounded
  mut selecting : Bool
  mut sel_color : Int64
  /// the paragraphs that can be picked, as this frame paints them and as the last one did (in the order they are
  /// painted): their id, the layer they are in (Ctx::layer_of), where they stand in the page (Ctx::page_order), layout, words, where their text starts, the
  /// part of them shown (x0, y0, x1, y1)
  next_sels : Array[SelTarget]
  mut sels : Array[SelTarget]
}

///|
priv struct SelTarget {
  base : Int
  layer : Int
  /// the old view it was built in (Node's `island`): whether a press may pick it now, view_host.mbt's old_owner_open
  island : @view.NodeId?
  at : Array[Int]
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
/// A place in the words picked with the pointer: its paragraph (its id), the offset in its text, and where the
/// paragraph stands in the page (Ctx::page_order) as last laid out.
priv struct SelSpot {
  base : Int
  off : Int
  at : Array[Int]
}

///|
/// What of a paragraph is picked: from `a` until `b` of its words (`text`, as last laid out), and where it stands in the
/// page.
priv struct SelSpan {
  a : Int
  b : Int
  text : String
  at : Array[Int]
}

///|
/// What is picked with the pointer, as a browser's selection: from where the press went down (`from`; its paragraph 0:
/// nothing picked) to where the pointer took it (`to`), the paragraphs between them in the page's order whole; what
/// is picked of each paragraph, by its id (those scrolled out of view kept as they were); whether the pointer is
/// still taking it; the list the press went down in (0 none), scrolled toward the pointer held past its edge; and the
/// layer it went down in (overlay.mbt; 0 the page), the only one whose words it picks, as a browser's selection
/// started in a dialog stays in it.
priv struct Picked {
  mut from : SelSpot
  mut to : SelSpot
  mut spans : Map[Int, SelSpan]
  mut dragging : Bool
  mut list : Int
  mut layer : Int
}

///|
let picked : Picked = { from: no_spot, to: no_spot, spans: {}, dragging: false, list: 0, layer: 0 }

///|
// kept across runs: a value (no field of it changes)
let no_spot : SelSpot = { base: 0, off: 0, at: [] }

///|
let desk : Desk = {
  mutable_menus: [],
  menus: [],
  mutable_keys: [],
  keys: [],
  shown: 0,
  pasting: None,
  pasted: {},
  next_mouse_drags: [],
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
  desk.mutable_keys.clear()
  desk.keys.clear()
  desk.shown = 0
  desk.pasting = None
  desk.pasted.clear()
  desk.next_mouse_drags.clear()
  desk.mouse_drags = true
  desk.selecting = false
  desk.next_sels.clear()
  desk.sels = []
  select_none()
}

///|
/// As a frame starts: what came since the last one is what this one reads.
fn desk_frame_start() -> Unit {
  desk.menus.clear()
  for m in desk.mutable_menus {
    desk.menus.push(m)
  }
  desk.mutable_menus.clear()
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
  desk.next_mouse_drags.clear()
  desk.next_sels.clear()
  desk.selecting = false
}

///|
/// As a frame ends (its targets in place): the shapes and drag areas it said are the ones in force, the pointer's
/// target found again where it rests (what moved under it), its shape shown.
fn Ctx::desk_frame_end(self : Ctx) -> Unit {
  desk.mouse_drags = match desk.next_mouse_drags.last() {
    Some(on) => on
    None => true
  }
  desk.sels = desk.next_sels.copy()
  if !self.down && self.px >= 0.0 {
    if pointing() is Finger {
      // a finger lifted is nowhere: what it last touched is not hovered, and the pointer is not over it (this frame,
      // the one after it was lifted, still read where it was, for what a tap there opens)
      self.px = -1.0
      self.py = -1.0
      self.point_nowhere()
    } else {
      self.point_at(self.px, self.py)
    }
  }
  self.show_cursor()
}

///|
/// The shape for what is under the pointer, told the host when it changes: the one said for it (Ctx::cursor); else a
/// field's I-beam; the hand over what takes presses (a button, a row, a link in words: Ctx::takes_presses), unless
/// said to be the arrow (a ground: a stage, the room round a list's rows); the I-beam over words picked with the
/// pointer; else the arrow. Held, the shape it was pressed with stays (a slider's thumb dragged off its line, words
/// picked across a link: what reads its click while it is not held reads none then), a drag area's its own once the
/// press is its drag, pressed no more.
fn Ctx::show_cursor(self : Ctx) -> Unit {
  let area = self.down && self.dragging && drags.contains(self.drag_scroll)
  if self.down && !area {
    return
  }
  let target = if area { self.drag_scroll } else { self.hover }
  // (over what is only pointed at: what holds it, as a press there is its)
  let target = if self.points.contains(target) {
    let mut held = 0
    let mut k = self.hover_in.length() - 1
    while k >= 0 {
      if !self.points.contains(self.hover_in[k]) {
        held = self.hover_in[k]
        break
      }
      k = k - 1
    }
    held
  } else {
    target
  }
  let said = marked_cursor(hit_marks(target))
  let kind = match said {
    Some(k) if k != Cursor::Arrow.code() => k
    _ =>
      if target != 0 && self.editors.contains(target) {
        Cursor::IBeam.code()
      } else if said is None && (hit_marks(target) & mark_takes) != 0 {
        Cursor::Hand.code()
      } else if self.sel_at(self.px, self.py) is Some(_) {
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
/// A node's marks (Node's `marks`): it takes presses (Ctx::takes_presses, and what reads its click), a press on it drags
/// the window (Ctx::window_drag), keeps what is picked (Ctx::keeps_selection), is what lies under it's when held
/// (Ctx::holds_through), asks for a menu (Ctx::menu_asked); above them, the pointer's shape over it and one
/// (Ctx::cursor), 0 where none is said.
let mark_takes : Int = 1

///|
let mark_drags : Int = 2

///|
let mark_keeps : Int = 4

///|
let mark_holds : Int = 8

///|
let mark_asks : Int = 16

///|
let mark_cursor_at : Int = 5

///|
/// What is said of the target `id` as it is built, marked on its node (docs/retained.md, the way there's 1: what a frame
/// says is what its nodes hold, kept with them). Said of an id whose node is not made yet, it is marked on it as it is
/// (Ctx::id_built). The shape said last is the one.
fn Ctx::mark_id(self : Ctx, id : Int, m : Int, cursor? : Int = -1) -> Unit {
  if id == 0 {
    return
  }
  match self.built_ids.get(id) {
    Some(i) if i < self.count && self.nodes[i].id == id => {
      let n = self.nodes[i]
      n.marks = with_marks(n.marks, m, cursor)
    }
    _ => self.marks_ahead[id] = with_marks(self.marks_ahead.get(id).unwrap_or(0), m, cursor)
  }
}

///|
fn with_marks(old : Int, m : Int, cursor : Int) -> Int {
  if cursor >= 0 {
    (old & ((1 << mark_cursor_at) - 1)) | m | ((cursor + 1) << mark_cursor_at)
  } else {
    old | m
  }
}

///|
/// Node `i` made with its id by this build: what was said of the id before it is marked on it (Ctx::mark_id).
fn Ctx::id_built(self : Ctx, i : Int) -> Unit {
  let n = self.nodes[i]
  self.built_ids[n.id] = i
  match self.focus_ahead.get(n.id) {
    Some(f) => {
      self.focus_ahead.remove(n.id)
      n.focus = Some(f)
    }
    None => ()
  }
  match self.marks_ahead.get(n.id) {
    Some(m) => {
      self.marks_ahead.remove(n.id)
      n.marks = with_marks(n.marks, m & ((1 << mark_cursor_at) - 1), (m >> mark_cursor_at) - 1)
    }
    None => ()
  }
}

///|
/// The pointer's shape marked (Ctx::cursor), if one is.
fn marked_cursor(marks : Int) -> Int? {
  let c = marks >> mark_cursor_at
  if c > 0 {
    Some(c - 1)
  } else {
    None
  }
}

///|
/// What the last frame's target `id` was marked with as it was built (its last drawn).
fn hit_marks(id : Int) -> Int {
  if id == 0 {
    return 0
  }
  let c = g()
  let mut k = c.hit_ids.length() - 1
  while k >= 0 && c.hit_ids[k] != id {
    k = k - 1
  }
  if k >= 0 && k < c.hit_marks.length() {
    c.hit_marks[k]
  } else {
    0
  }
}

///|
/// The pointer is `cursor` over `id` (a target: a box with an id), said each frame it is drawn, where what it is does
/// not say it (Ctx::show_cursor): a resizing edge's, the I-beam over what a press on gives a field the focus (a
/// composer's capsule round its field). `Arrow`: what takes presses there is a ground, not a control (a stage a click
/// shows the bars on, the room round a list's rows a click there chooses none in): no hand over it, words picked with
/// the pointer in it the I-beam still. A field shows the I-beam, what takes presses the hand, without being told.
pub fn Ctx::cursor(self : Ctx, id : Int, cursor : Cursor) -> Unit {
  self.mark_id(id, 0, cursor=cursor.code())
}

///|
/// `id` takes presses, said as it is built: the pointer's hand over it (Ctx::show_cursor). What reads its click
/// (Ctx::clicked, a part's Response) says so by that; what takes its press without its click (a slider set where it
/// is pressed, Ctx::pressed alone) says it here.
pub fn Ctx::takes_presses(self : Ctx, id : Int) -> Unit {
  self.mark_id(id, mark_takes)
}

///|
/// Where `id` was clicked with the secondary button (a right click; Ctrl-click on macOS) since the last frame, in the
/// window's terms: for its context menu. It counts for what is under the pointer and what holds it.
pub fn Ctx::right_clicked(self : Ctx, id : Int) -> (Double, Double)? {
  ignore(self)
  hand_events_read()
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
  hand_events_read()
  self.mark_id(id, mark_asks)
  let mut at : (Double, Double)? = None
  for m in desk.menus {
    if m.0.contains(id) {
      // (the first under it, topmost first, that asked for a menu as the frame it was laid out in was built: what
      // asks for the first time this frame goes by itself)
      let innermost = match m.0.iter().find_first(fn(u) { (hit_marks(u) & mark_asks) != 0 }) {
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
  hand_events_read()
  desk.menus.length() > 0
}

///|
/// A press on `id` drags the window (and a double click on it zooms it, as the system's title bar does): the app's
/// own top row, in a window with none of the system's (@hostapi.window_setup `inset`). Said each frame it is drawn.
pub fn Ctx::window_drag(self : Ctx, id : Int) -> Unit {
  self.mark_id(id, mark_drags)
}

///|
/// Whether a mouse's drag moves a list as a finger does (a phone's page in a window: true, as before); false on a
/// desktop's page, where the wheel and the trackpad scroll and a drag is the pointer's own. Said each frame: a frame
/// that does not say it drags them (a wide window made narrow).
pub fn Ctx::mouse_drags_lists(self : Ctx, on : Bool) -> Unit {
  ignore(self)
  desk.next_mouse_drags.push(on)
}

///|
/// Whether key `code` came since the last frame with exactly `mods` held (with `in_field`, also one a focused field
/// took: an Enter it sent, an arrow it moved by).
pub fn Ctx::key_pressed(self : Ctx, code : Int, mods? : Int = 0, in_field? : Bool = false) -> Bool {
  hand_events_read()
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
/// Whether any key came since the last frame: what looks for keys of its own (an app's shortcuts, each a binding to
/// read) has none to look for when none came, as on every frame of a phone without a keyboard.
pub fn Ctx::keys_came(self : Ctx) -> Bool {
  ignore(self)
  hand_events_read()
  !desk.keys.is_empty()
}

///|
/// Key `code` with exactly `mods` held, if it came since the last frame and nothing took it yet: taken now (what reads
/// keys after this does not see it). For a widget's own keys while it has the focus (a slider's arrows).
pub fn Ctx::take_key(self : Ctx, code : Int, mods? : Int = 0) -> Bool {
  hand_events_read()
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
  hand_events_read()
  if !self.keys_here() {
    return []
  }
  desk.keys
}

///|
/// The focused field let go of (the keyboard's words go nowhere until another is pressed).
pub fn Ctx::unfocus(self : Ctx) -> Unit {
  self.focus_moved(0)
}

///|
/// Whether a field has the keyboard.
pub fn Ctx::field_focused(self : Ctx) -> Bool {
  hand.focus_id.get() |> ignore
  self.focus != 0 && self.editors.contains(self.focus)
}

///|
/// A secondary press at (x, y) (on_pointer's button 2): recorded for Ctx::right_clicked, nothing pressed. It is on
/// what a press there would be: the topmost target under it and what holds that one (Ctx::hovered's), innermost
/// first; never on what only lies under them (the page under a menu, a dialog or a file open over the window, a
/// list's image under the composer floating over it), as a press is not.
fn Ctx::secondary_press(self : Ctx, x : Double, y : Double) -> Unit {
  let under : Array[Int] = []
  let k = hit_at(self.hit_ids, self.hit_rects, self.hit_clips, x, y, pressed=true)
  // (and what is drawn smaller than its room, reached from round it as a press is: press_reach)
  let k = press_reach(self.hit_ids, self.hit_rects, self.hit_clips, k, x, y)
  if k >= 0 {
    self.holders(k, under)
    under.push(self.hit_ids[k])
    under.rev_in_place()
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
  self.point_nowhere()
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
  (hit_marks(id) & mark_drags) != 0
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
/// The words picked with the pointer, each paragraph's on a line of its own in the page's order ("" none).
fn selected_words() -> String {
  let spans : Array[SelSpan] = picked.spans.values().filter(fn(s) { s.a < s.b }).collect()
  spans.sort_by(fn(p, q) { order_cmp(p.at, q.at) })
  spans.map(fn(s) { s.text.view(start_offset=s.a, end_offset=s.b).to_string() }).join("\n")
}

///|
/// Nothing picked with the pointer.
fn select_none() -> Unit {
  picked.from = no_spot
  picked.to = no_spot
  picked.spans.clear()
  picked.dragging = false
  picked.layer = 0
  select_edge_stop()
}

///|
/// Where node `i` stands in the page: from the root down, each node's place among its parent's children (node_place).
/// Paragraphs come in the page's order as their places do (order_cmp): the order the page holds them in, whatever is
/// drawn over what; kept with what is drawn of them (a list's row drawn again keeps its paragraphs' places).
fn Ctx::page_order(self : Ctx, i : Int) -> Array[Int] {
  let up : Array[Int] = []
  let mut k = i
  while k >= 0 && self.nodes[k].parent >= 0 {
    up.push(self.node_place(k))
    k = self.nodes[k].parent
  }
  up.rev()
}

///|
/// The layer node `i` is in (overlay.mbt: its id; 0 the page).
fn Ctx::layer_of(self : Ctx, i : Int) -> Int {
  let mut k = i
  while k >= 0 {
    let n = self.nodes[k]
    if n.portal {
      return n.portal_id
    }
    k = n.parent
  }
  0
}

///|
/// The layer whose words a press at (x, y) picks, as last laid out (0 the page): the topmost that shows something
/// there (Ctx::shows_at: a card's panel, not the room a toast's layer is laid out in), or a modal one, whose ground
/// takes it.
fn Ctx::layer_at(self : Ctx, x : Double, y : Double) -> Int {
  let mut k = self.last_layers.length() - 1
  while k >= 0 {
    let l = self.last_layers[k]
    k = k - 1
    if l.inert || l.node >= self.count {
      continue
    }
    if l.modal || self.shows_at(l.node, x, y) {
      return l.id
    }
  }
  0
}

///|
/// Whether what node `i` holds shows something at (x, y) or takes a press there: a node with a ground, a border, glass
/// or an id, or one that is not a box (words, a picture), under it; a modal layer's ground left out.
fn Ctx::shows_at(self : Ctx, i : Int, x : Double, y : Double) -> Bool {
  let mut ch = self.nodes[i].first
  while ch >= 0 {
    let n = self.nodes[ch]
    if !n.blocks && n.opacity > 0.002 {
      let inside = x >= n.x && x < n.x + n.fw && y >= n.y && y < n.y + n.fh
      if inside &&
        (n.kind != kind_box || n.id != 0 || n.bg != 0L || n.border_w > 0.0 || n.glass is Some(_)) {
        return true
      }
      // (what is placed out of its parent's box is looked for there too)
      if self.shows_at(ch, x, y) {
        return true
      }
    }
    ch = n.next
  }
  false
}

///|
/// Node `i`'s place among its parent's children: a list's row, its item (so that the place holds as the list scrolls
/// and builds other rows); else how many come before it.
fn Ctx::node_place(self : Ctx, i : Int) -> Int {
  let n = self.nodes[i]
  if n.item >= 0 {
    return n.item
  }
  let mut r = 0
  let mut s = self.nodes[n.parent].first
  while s >= 0 && s != i {
    r = r + 1
    s = self.nodes[s].next
  }
  r
}

///|
/// The paragraphs that can be picked as the view is laid out now (a frame's layout, before it is drawn; between
/// frames, the last one's), in the order the page holds them, each where it stands in the page (Ctx::page_order) and
/// with the part of it shown (cut by what clips it); one drawn too faint to see (a row left out), none of them.
fn Ctx::sel_laid(self : Ctx) -> Array[SelTarget] {
  let out = []
  if self.count > 0 {
    self.sel_walk(0, [], 0, -1.0e9, -1.0e9, 1.0e9, 1.0e9, 1.0, out)
  }
  out
}

///|
fn Ctx::sel_walk(
  self : Ctx,
  i : Int,
  at : Array[Int],
  layer : Int,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  alpha : Double,
  out : Array[SelTarget],
) -> Unit {
  let n = self.nodes[i]
  // (as painted: Ctx::paint_node)
  let alpha = alpha * n.opacity
  if alpha <= 0.002 {
    return
  }
  let layer = if n.portal { n.portal_id } else { layer }
  if n.kind == kind_rich {
    match (n.rcut, n.rich) {
      (Some(r), _) | (None, Some(r)) if r.select =>
        match n.rich_layout(dmax(n.fw - n.pad_l - n.pad_r, 0.0)) {
          Some(lay) =>
            out.push({
              base: r.base,
              layer,
              island: n.island,
              at: at.copy(),
              lay,
              text: n.text,
              ox: n.x + n.pad_l,
              oy: n.y + n.pad_t,
              x0: dmax(n.x, x0),
              y0: dmax(n.y, y0),
              x1: dmin(n.x + n.fw, x1),
              y1: dmin(n.y + n.fh, y1),
            })
          None => ()
        }
      _ => ()
    }
    return
  }
  let (x0, y0, x1, y1) = if n.clip {
    (dmax(x0, n.x), dmax(y0, n.y), dmin(x1, n.x + n.fw), dmin(y1, n.y + n.fh))
  } else {
    (x0, y0, x1, y1)
  }
  let mut k = n.first
  while k >= 0 {
    at.push(self.node_place(k))
    self.sel_walk(k, at, layer, x0, y0, x1, y1, alpha, out)
    at.pop() |> ignore
    k = self.nodes[k].next
  }
}

///|
/// -1, 0 or 1 as place `a` comes before, at or after `b` in the page (Ctx::page_order).
fn order_cmp(a : Array[Int], b : Array[Int]) -> Int {
  let n = imin(a.length(), b.length())
  for k in 0..<n {
    if a[k] != b[k] {
      return if a[k] < b[k] { -1 } else { 1 }
    }
  }
  a.length().compare(b.length())
}

///|
/// -1, 0 or 1 as spot `p` comes before, at or after `q` in the words of the page.
fn spot_cmp(p : SelSpot, q : SelSpot) -> Int {
  if p.base == q.base {
    p.off.compare(q.off)
  } else {
    order_cmp(p.at, q.at)
  }
}

///|
/// Whether the focused field has words of its own picked (copied before those picked with the pointer).
fn field_picks(c : Ctx) -> Bool {
  match c.editors.get(c.focus_allowed()) {
    Some(st) => {
      let (a, b) = st.sel()
      a != b
    }
    None => false
  }
}

///|
/// A paragraph that can be picked, as painted (rich.mbt paint_rich).
fn selectable_painted(
  base : Int,
  layer : Int,
  island : @view.NodeId?,
  at : Array[Int],
  lay : RichLayout,
  text : String,
  ox : Double,
  oy : Double,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
) -> Unit {
  desk.next_sels.push({ base, layer, island, at, lay, text, ox, oy, x0, y0, x1, y1 })
}

///|
/// What of paragraph `base` is picked: a rectangle a line, in its text's terms.
fn selected_rects(base : Int, lay : RichLayout) -> Array[(Double, Double, Double, Double)] {
  match picked.spans.get(base) {
    Some(s) if s.a < s.b => lay.rects(s.a, s.b)
    _ => []
  }
}

///|
/// Where the pointer at (x, y) takes what is picked, among the paragraphs laid out (`laid`, Words::offset_at's way): in
/// the one whose part shown holds its height (the nearest across: beside a table's cell); else at the start of the
/// nearest one under it; under them all, at the end of the lowest. None with none shown.
fn sel_spot_at(laid : Array[SelTarget], x : Double, y : Double) -> (SelTarget, Int)? {
  let mut hit : SelTarget? = None
  let mut best = 1.0e18
  let mut under : SelTarget? = None
  let mut lowest : SelTarget? = None
  for t in laid {
    if t.x1 <= t.x0 || t.y1 <= t.y0 {
      continue
    }
    if y >= t.y0 && y < t.y1 {
      let d = if x < t.x0 {
        t.x0 - x
      } else if x > t.x1 {
        x - t.x1
      } else {
        0.0
      }
      if d < best {
        best = d
        hit = Some(t)
      }
    }
    match under {
      Some(u) if u.y0 <= t.y0 => ()
      _ => if t.y0 > y { under = Some(t) }
    }
    match lowest {
      Some(l) if l.y1 > t.y1 => ()
      _ => lowest = Some(t)
    }
  }
  match (hit, under, lowest) {
    (Some(t), _, _) => {
      let off = t.lay.offset_at(x - t.ox, y - t.oy)
      Some((t, imax(0, imin(off, t.text.length()))))
    }
    (None, Some(t), _) => Some((t, 0))
    (None, None, Some(t)) => Some((t, t.text.length()))
    _ => None
  }
}

///|
/// What is picked with the pointer taken to (x, y) (sel_spot_at) from where the press went down, as the view is laid
/// out now, in the layer it went down in: the paragraphs between them in the page's order whole, the two ends' paragraphs from and to their spots;
/// those not laid out now (scrolled out of view) kept as they were while they lie between, let go once they do not
/// (the one the press went down in kept, empty).
fn Ctx::select_to(self : Ctx, x : Double, y : Double) -> Unit {
  // the paragraphs laid out: their words and where they stand in the page, now
  let laid = self.sel_laid().filter(fn(t) { t.layer == picked.layer })
  let drawn : Map[Int, SelSpan] = {}
  for t in laid {
    if !drawn.contains(t.base) {
      drawn[t.base] = { a: 0, b: 0, text: t.text, at: t.at }
    }
  }
  let now = fn(s : SelSpot) {
    match drawn.get(s.base) {
      Some(d) => { ..s, at: d.at }
      None => s
    }
  }
  picked.from = now(picked.from)
  picked.to = match sel_spot_at(laid, x, y) {
    Some((t, off)) => now({ base: t.base, off, at: [] })
    None => now(picked.to)
  }
  let (lo, hi) = if spot_cmp(picked.from, picked.to) <= 0 {
    (picked.from, picked.to)
  } else {
    (picked.to, picked.from)
  }
  let known : Map[Int, SelSpan] = {}
  picked.spans.each(fn(k, s) { if !drawn.contains(k) { known[k] = s } })
  drawn.each(fn(k, d) { known[k] = d })
  let spans : Map[Int, SelSpan] = {}
  known.each(fn(k, s) {
    let n = s.text.length()
    let a = if k == lo.base {
      lo.off
    } else if order_cmp(s.at, lo.at) > 0 {
      0
    } else {
      n
    }
    let b = if k == hi.base {
      hi.off
    } else if order_cmp(s.at, hi.at) < 0 {
      n
    } else {
      0
    }
    let a = imax(0, imin(a, n))
    let b = imax(a, imin(b, n))
    if a < b || k == picked.from.base {
      spans[k] = { ..s, a, b }
    }
  })
  picked.spans = spans
}

///|
/// As a frame is laid out, before it is drawn: words being picked with the pointer held go to what is under it as
/// this frame lays the page out (a list scrolled under it by the wheel, words come), drawn so in this frame.
fn Ctx::select_after_layout(self : Ctx) -> Unit {
  // (read so: hand.mbt)
  hand.down.get() |> ignore
  if picked.dragging && self.down {
    hand.pointer.get() |> ignore
    self.select_to(self.px, self.py)
  }
  self.select_edge()
}

///|
/// How fast the list words are picked in scrolls toward the pointer held past its shown edge (px a ms for each px it
/// is past it, from select_edge_least px), as a browser scrolls what a selection is dragged out of: further out,
/// faster.
let select_edge_rate : Double = 0.02

///|
/// How far past the edge the pointer counts as from the edge itself (px): just past it, the list already scrolls at a
/// pace one sees (200 px a second), not a crawl.
let select_edge_least : Double = 10.0

///|
/// Words being picked with the pointer held past the top or the foot of the list the press went down in, as it shows
/// (what floats over it, a page's bar, a composer, is not where it shows: Ctx::floated): the list scrolls toward the
/// pointer, faster the further past it is, words coming as it does (select_after_layout), until the pointer comes
/// back in or lets go. Its edges as the last frame drew it (its scroll bar's: none where it does not scroll).
fn Ctx::select_edge(self : Ctx) -> Unit {
  let id = picked.list
  if id == 0 {
    return
  }
  let v = match self.bar_drawn(id) {
    Some(b) if picked.dragging && self.down && !b.foot => {
      let top = b.y0 + b.top_in
      let foot = b.y1 - b.foot_in
      if foot <= top {
        0.0
      } else if self.py < top {
        -(top - self.py + select_edge_least) * select_edge_rate
      } else if self.py > foot {
        (self.py - foot + select_edge_least) * select_edge_rate
      } else {
        0.0
      }
    }
    _ => 0.0
  }
  self.edge_scroll(id, v)
}

///|
/// The list words were picked in scrolls no more toward the pointer (it let go, or they did).
fn select_edge_stop() -> Unit {
  if picked.list != 0 {
    g().edge_scroll(picked.list, 0.0)
    picked.list = 0
  }
}

///|
/// The paragraph that can be picked under (x, y), the topmost, in the layer a press there goes to (Ctx::layer_at):
/// none of the page's under a popover's panel or a dialog's ground.
fn Ctx::sel_at(self : Ctx, x : Double, y : Double) -> SelTarget? {
  if desk.mouse_drags || x < 0.0 {
    return None
  }
  let layer = self.layer_at(x, y)
  let mut k = desk.sels.length() - 1
  while k >= 0 {
    let t = desk.sels[k]
    if t.layer == layer && x >= t.x0 && x < t.x1 && y >= t.y0 && y < t.y1 && old_owner_open(t.island) {
      return Some(t)
    }
    k = k - 1
  }
  None
}

///|
/// A primary press at (x, y), the `clicks`th in a row (Ctx's `clicks`): on words that are picked with the pointer,
/// picking starts there (a double click's second picks the word under it, a triple's the paragraph, as a browser's
/// do); elsewhere what was picked is let go.
fn Ctx::select_press(self : Ctx, x : Double, y : Double, clicks : Int) -> Unit {
  select_none()
  match self.sel_at(x, y) {
    Some(target) => {
      let text = target.text
      let off = imax(0, imin(target.lay.offset_at(x - target.ox, y - target.oy), text.length()))
      let (s, e) = if clicks <= 1 {
        (off, off)
      } else if clicks == 2 {
        word_at(text, off)
      } else {
        (paragraph_end(text, off, -1), paragraph_end(text, off, 1))
      }
      let at = target.at
      picked.from = { base: target.base, off: s, at }
      picked.to = { base: target.base, off: e, at }
      picked.spans[target.base] = { a: s, b: e, text, at }
      picked.dragging = clicks <= 1
      picked.layer = target.layer
      // (the list it lies in: sideways boxes in it scroll it no way the pointer goes up or down)
      picked.list = if picked.dragging { outer_scroll(self, x, y) } else { 0 }
    }
    None => ()
  }
}

///|
/// A press on `id` keeps what is picked with the pointer (a button that does something with it, as a page's control
/// whose press is not the words' with mousedown's preventDefault: a quote of what is picked). Said each frame it is
/// drawn.
pub fn Ctx::keeps_selection(self : Ctx, id : Int) -> Unit {
  self.mark_id(id, mark_keeps)
}

///|
/// A press on `id` is its own (a tap, a click, a drag), but a finger held still on it is what lies under it's: what
/// holds the target under it counts the press as within it (Ctx::press_within). A cover over what is shown and not in
/// use (a pane beside the one in use), whose words are still held to pick them. Said each frame it is drawn.
pub fn Ctx::holds_through(self : Ctx, id : Int) -> Unit {
  self.mark_id(id, mark_holds)
}

///|
/// Whether a press on `target` keeps what is picked (Ctx::keeps_selection).
fn keeps_selection_on(target : Int) -> Bool {
  (hit_marks(target) & mark_keeps) != 0
}

///|
/// Where what is picked with the pointer lies in the window, once the pointer has let it go (the box round its
/// lines), or None: none picked, or still being dragged.
pub fn Ctx::selection_box(self : Ctx) -> (Double, Double, Double, Double)? {
  ignore(self)
  if picked.dragging {
    return None
  }
  let mut x0 = 1.0e9
  let mut y0 = 1.0e9
  let mut x1 = -1.0e9
  let mut y1 = -1.0e9
  // (of the paragraphs drawn, where they are drawn: those scrolled out of view are nowhere)
  for t in desk.sels {
    for r in selected_rects(t.base, t.lay) {
      x0 = dmin(x0, t.ox + r.0)
      y0 = dmin(y0, t.oy + r.1)
      x1 = dmax(x1, t.ox + r.0 + r.2)
      y1 = dmax(y1, t.oy + r.1 + r.3)
    }
  }
  if x1 < x0 {
    None
  } else {
    Some((x0, y0, x1 - x0, y1 - y0))
  }
}

///|
/// Where the pointer let what is picked go, in the window: the end of it the pointer took (Picked's `to`: dragged
/// down, the last of its lines' right end; dragged up, the first's left end), x and its line's top and height; None
/// as selection_box. What it holds is what was dragged over, so this is where the pointer let go, not past the words.
pub fn Ctx::selection_end(self : Ctx) -> (Double, Double, Double)? {
  ignore(self)
  if picked.dragging {
    return None
  }
  let down = spot_cmp(picked.from, picked.to) <= 0
  let mut end : (Array[Int], Double, Double, Double)? = None
  // (of the paragraphs drawn, where they are drawn: those scrolled out of view are nowhere)
  for t in desk.sels {
    for r in selected_rects(t.base, t.lay) {
      let (x, y) = (t.ox + r.0, t.oy + r.1)
      let here = (t.at, if down { x + r.2 } else { x }, y, r.3)
      end = match end {
        None => Some(here)
        Some((at, _, ey, _) as e) => {
          let k = order_cmp(t.at, at)
          let k = if k == 0 { y.compare(ey) } else { k }
          if (down && k > 0) || (!down && k < 0) {
            Some(here)
          } else {
            Some(e)
          }
        }
      }
    }
  }
  end.map(fn(e) { (e.1, e.2, e.3) })
}

///|
/// What is picked with the pointer let go (a quote taken from it).
pub fn Ctx::selection_clear(self : Ctx) -> Unit {
  ignore(self)
  select_none()
}

///|
/// The pointer moved while picking: the picked words go to it. True once some are (the press is no tap then).
fn Ctx::select_move(self : Ctx, x : Double, y : Double) -> Bool {
  if !picked.dragging {
    return false
  }
  self.select_to(x, y)
  picked.spans.values().any(fn(s) { s.a < s.b })
}
