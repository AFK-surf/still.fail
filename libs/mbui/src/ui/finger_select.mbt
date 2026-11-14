// Words picked with a finger, by the same selection as a mouse's (desktop.mbt: Ctx::selectable's paragraphs), as a
// phone's text is picked (Android's TextView, iOS's UITextView): a finger held still on words that are picked with the
// pointer a long press's time picks the word under it (nothing else having taken the press: a row's menu, a link's, a
// view's own picking), felt; sliding on, widened by words from that word, the list scrolled toward the finger past its
// edge; lifted, a handle at each end (taken and moved, the end following the finger from where it was taken) and the
// system's floating text menu over it (Ctx::sync_text_menu: copy, select all), as a field's words a finger picked
// have. A press elsewhere does not let it go (the list scrolled under it keeps it); a tap does. Copied, it is let go.

///|
/// The press a finger's hold last picked words for (its moment, Ctx's `press_at`): once a press.
// kept across runs: let go as a run begins (finger_reset)
let finger_held : Ref[Double] = Ref(-1.0)

///|
/// The handles of what a finger picked, as the frame painting them placed them (the start's, the end's): where a finger
/// takes each (x, y, w, h) and the end it moves (x, y: the middle of its line), and as the last frame painted them.
priv struct FingerEnd {
  x : Double
  y : Double
  w : Double
  h : Double
  ex : Double
  ey : Double
}

///|
// kept across runs: painted each frame, let go as a run begins (finger_reset)
let next_finger_ends : Array[FingerEnd?] = [None, None]

///|
// kept across runs: as the last frame painted them, let go as a run begins (finger_reset)
let finger_ends : Array[FingerEnd?] = [None, None]

///|
/// As a run begins (a Tester's start): nothing held, no handles.
fn finger_reset() -> Unit {
  finger_held.val = -1.0
  for k in 0..<2 {
    next_finger_ends[k] = None
    finger_ends[k] = None
  }
}

///|
/// What a finger picked let go: no word widened from, no handle held.
fn finger_let_go() -> Unit {
  picked.word = None
  picked.handle = 0
  picked.grab_x = 0.0
  picked.grab_y = 0.0
}

///|
/// As a frame ends: the handles it painted are where a finger takes them.
fn finger_frame_end() -> Unit {
  finger_ends[0] = next_finger_ends[0]
  finger_ends[1] = next_finger_ends[1]
}

///|
/// The paragraph that can be picked under (x, y) for a finger's hold: the topmost an old view painted there, in the
/// layer a press there goes to, its old view open to presses (Ctx::sel_at's, whether lists are dragged by a mouse or
/// not).
fn Ctx::sel_finger_at(self : Ctx, x : Double, y : Double) -> SelTarget? {
  if self.selection_blocked(x, y) {
    return None
  }
  let layer = self.layer_at(x, y)
  let mut k = desk.sels.length() - 1
  while k >= 0 {
    let t = desk.sels[k]
    if t.layer == OldLayer(layer) &&
      x >= t.x0 &&
      x < t.x1 &&
      y >= t.y0 &&
      y < t.y1 &&
      old_owner_open(t.island) {
      return Some(t)
    }
    k = k - 1
  }
  None
}

///|
/// As a frame is painted, its builds over (what takes a hold of its own has taken it by then: Ctx::take_press): a finger
/// held still on words that are picked with the pointer a long press's time picks the word under where it went down,
/// the press the pick's from then (no tap, nothing under it dragged); a frame asked for when it will have been held so.
fn Ctx::finger_hold(self : Ctx) -> Unit {
  guard pointing() is Finger else { return }
  // (a hold the window's tree handed here, held long already, that nothing built has taken: a cover's over words
  // still held to pick them, Ctx::holds_through)
  match view_handed.val {
    Some(h) if !h.taken && h.down == downs_made.val && old_owner_open(h.owner) && finger_held.val != self.press_at =>
      match self.sel_finger_at(h.x, h.y) {
        Some(t) => {
          h.taken = true
          self.finger_pick(t, h.x, h.y)
          return
        }
        None => ()
      }
    _ => ()
  }
  if !self.down ||
    self.dragging ||
    self.press_strayed ||
    self.press_at < 0.0 ||
    self.taken_at == self.press_at ||
    finger_held.val == self.press_at ||
    picked.handle != 0 ||
    self.edge == 2 ||
    self.editors.contains(self.active) {
    return
  }
  let (x, y) = (self.press_x, self.press_y)
  guard self.sel_finger_at(x, y) is Some(t) else { return }
  let held = self.clock - self.press_at
  if held < long_press_ms {
    self.wake_in(long_press_ms - held)
    return
  }
  self.finger_pick(t, x, y)
}

///|
/// The word of paragraph `t` under (x, y) picked by a finger's hold, the press the pick's from then (no tap, nothing
/// under it dragged), felt; widened by words as the finger slides on.
fn Ctx::finger_pick(self : Ctx, t : SelTarget, x : Double, y : Double) -> Unit {
  finger_held.val = self.press_at
  let text = t.text
  let off = imax(0, imin(t.offset_at(x, y), text.length()))
  let (s, e) = finger_word_at(text, off)
  if e <= s {
    return
  }
  select_none()
  picked.made = picked.made + 1
  let ws = { base: t.base, off: s, at: t.at }
  let we = { base: t.base, off: e, at: t.at }
  picked.from = ws
  picked.to = we
  picked.spans[t.base] = { a: s, b: e, text, at: t.at }
  picked.dragging = true
  picked.finger = true
  picked.layer = t.layer
  picked.island = t.island
  picked.word = Some((ws, we))
  picked.list = outer_scroll(self, x, y)
  self.take_press()
  haptic(LongPress)
  picked_told()
}

///|
/// The word a finger held at offset `off` of `text` picks (word_at): held on spaces between words, the word next to
/// them, the one before first, else the one after, as iOS's and Android's text pick it (a space alone is of no use to
/// anyone); none where there is only space.
fn finger_word_at(text : String, off : Int) -> (Int, Int) {
  let n = text.length()
  if n == 0 {
    return (0, 0)
  }
  // (spaces, in the text's units as its offsets are: the ideographic one too)
  let blank = fn(k : Int) {
    let c = text.at(k).to_int()
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x3000
  }
  // (a word as the system finds it, without the spaces it may hold at its ends: a word with its space after it)
  let word = fn(k : Int) {
    let (s, e) = word_at(text, k)
    let mut s = s
    let mut e = e
    while s < e && blank(s) {
      s = s + 1
    }
    while e > s && blank(e - 1) {
      e = e - 1
    }
    (s, e)
  }
  let i = imax(0, imin(off, n - 1))
  if !blank(i) {
    return word(i)
  }
  let mut l = i - 1
  while l >= 0 && blank(l) {
    l = l - 1
  }
  if l >= 0 {
    return word(l)
  }
  let mut r = i + 1
  while r < n && blank(r) {
    r = r + 1
  }
  if r < n {
    word(r)
  } else {
    (0, 0)
  }
}

///|
/// A finger's press going down at (x, y) on a handle of what a finger picked: the press the handle's (the view's lists
/// let go of it), that end following the finger from where it was taken, the other where it is. True when it was one.
fn Ctx::finger_handle_down(self : Ctx, x : Double, y : Double) -> Bool {
  guard pointing() is Finger && picked.finger else { return false }
  for k in 0..<2 {
    match finger_ends[k] {
      Some(h) if x >= h.x && x < h.x + h.w && y >= h.y && y < h.y + h.h => {
        let (lo, hi) = if spot_cmp(picked.from, picked.to) <= 0 {
          (picked.from, picked.to)
        } else {
          (picked.to, picked.from)
        }
        picked.from = if k == 0 { hi } else { lo }
        picked.to = if k == 0 { lo } else { hi }
        picked.word = None
        picked.handle = k + 1
        picked.grab_x = h.ex - x
        picked.grab_y = h.ey - y
        picked.dragging = true
        picked.list = outer_scroll(self, x, y)
        picked_told()
        return true
      }
      _ => ()
    }
  }
  false
}

///|
/// A finger's tap lifted at (x, y), on nothing that keeps what is picked (Ctx::keeps_selection): what a finger picked
/// let go.
fn Ctx::finger_tapped(_self : Ctx, target : Int) -> Unit {
  if pointing() is Finger && picked.finger && !picked.dragging && !keeps_selection_on(target) {
    select_none()
  }
}

///|
/// Where the system's floating text menu goes over what a finger picked (the box round its lines as drawn, in the
/// window) and what it offers (copy; select all), once the finger has let it go; None else.
fn finger_menu() -> (Double, Double, Double, Double, Int)? {
  if !picked.finger || picked.dragging || selected_words() == "" {
    return None
  }
  // (and the app's own items where what holds the words it ends in offers some: picked_menu)
  let own = if picked_menu_own().is_empty() { 0 } else { @hostapi.text_menu_own_item }
  match g().selection_box() {
    Some((x, y, w, h)) => Some((x, y, w, h, @hostapi.text_menu_copy | @hostapi.text_menu_select_all | own))
    None => None
  }
}

///|
/// All the words of the old view and layer a finger picked in, as laid out (those scrolled away kept as they were); of
/// the window's tree's, where what holds the words picked says they are whole of what they are of (picked_of's
/// `whole`: a message's), all of that alone (those paragraphs said of what such words picked are of), not all the
/// page's.
fn Ctx::finger_select_all(self : Ctx) -> Unit {
  let sels = self.sel_laid() + tree_sels()
  // (what the words picked now are of, where what showed them said them whole of it: tree_sels has said each found)
  let ofs : Array[String] = []
  match view_app.val {
    Some(tree) =>
      picked.spans.each(fn(k, s) {
        match picked_shown.get(k) {
          Some((id, Some(o))) if s.a < s.b && !ofs.contains(o) =>
            match tree.view_of(id) {
              Some(v) if v.lent(picked_wholes) == Some(true) => ofs.push(o)
              _ => ()
            }
          _ => ()
        }
      })
    None => ()
  }
  let laid = sels.filter(fn(t) {
    t.layer == picked.layer &&
    t.island == picked.island &&
    (ofs.is_empty() ||
    (match picked_shown.get(t.base) {
      Some((_, Some(o))) => ofs.contains(o)
      _ => false
    }))
  })
  if laid.is_empty() {
    return
  }
  let mut first = laid[0]
  let mut last = laid[0]
  for t in laid {
    picked.spans[t.base] = { a: 0, b: t.text.length(), text: t.text, at: t.at }
    if order_cmp(t.at, first.at) < 0 {
      first = t
    }
    if order_cmp(t.at, last.at) > 0 {
      last = t
    }
  }
  picked.from = { base: first.base, off: 0, at: first.at }
  picked.to = { base: last.base, off: last.text.length(), at: last.at }
  finger_let_go()
  picked_told()
}

///|
/// The handles of what a finger picked, over everything as a field's are (painted last, cut by nothing): at each end
/// of it where the paragraph holding that end shows it (an old view's as this frame painted it, the window's tree's as
/// it is laid out now), a line down the end's side with a knob in the colour it is picked in (over the start's line,
/// under the end's: iOS's), on Android a drop hanging from the end's foot (a field's: Compose's SelectionHandle); each
/// where a finger takes it (finger_ends).
fn Ctx::paint_finger_ends(self : Ctx) -> Unit {
  next_finger_ends[0] = None
  next_finger_ends[1] = None
  if !picked.finger {
    return
  }
  let (lo, hi) = if spot_cmp(picked.from, picked.to) <= 0 {
    (picked.from, picked.to)
  } else {
    (picked.to, picked.from)
  }
  let shown = (desk.next_sels + tree_sels()).filter(fn(t) { t.layer == picked.layer && t.island == picked.island })
  let ink = desk.sel_color | 0xFFL
  push_unclipped()
  for k in 0..<2 {
    let spot = if k == 0 { lo } else { hi }
    // (the topmost showing that paragraph)
    let mut on : SelTarget? = None
    for t in shown {
      if t.base == spot.base {
        on = Some(t)
      }
    }
    guard on is Some(t) else { continue }
    let rects = t.picked_rects()
    if rects.is_empty() {
      continue
    }
    let r = if k == 0 { rects[0] } else { rects[rects.length() - 1] }
    let x = t.ox + (if k == 0 { r.0 } else { r.0 + r.2 }) * t.sc
    let top = t.oy + r.1 * t.sc
    let h = r.3 * t.sc
    // (its line out of the part of the paragraph shown, scrolled under what cuts it: no handle)
    if top + h <= t.y0 || top >= t.y1 || x < t.x0 - 1.0 || x > t.x1 + 1.0 {
      continue
    }
    if h_feel() == 2 {
      let rr = handle_r
      if k == 0 {
        self.emit_rect(x - 2.0 * rr, top + h, 2.0 * rr, 2.0 * rr, rr, ink, 0.0, 0L, 1.0)
        self.emit_rect(x - rr, top + h, rr, rr, 0.0, ink, 0.0, 0L, 1.0)
      } else {
        self.emit_rect(x, top + h, 2.0 * rr, 2.0 * rr, rr, ink, 0.0, 0L, 1.0)
        self.emit_rect(x, top + h, rr, rr, 0.0, ink, 0.0, 0L, 1.0)
      }
    } else {
      self.emit_rect(x - 1.0, top, 2.0, h, 0.0, ink, 0.0, 0L, 1.0)
      let ky = if k == 0 { top - 11.0 } else { top + h - 1.0 }
      self.emit_rect(x - 6.0, ky, 12.0, 12.0, 6.0, ink, 0.0, 0L, 1.0)
    }
    // (a finger's room round it: 36 across, the line and 28 more where its knob is)
    let half = finger_end_half
    next_finger_ends[k] = Some({
      x: x - half,
      y: if k == 0 { top - finger_knob_room } else { top },
      w: 2.0 * half,
      h: h + finger_knob_room,
      ex: x,
      ey: top + h / 2.0,
    })
  }
  pop_clip()
}

///|
/// Half the room a finger takes a handle in across.
let finger_end_half : Double = 18.0

///|
/// The room a finger takes a handle in past its line, where its knob is (over the start's, under the end's).
let finger_knob_room : Double = 28.0

///|
/// Whether what is picked with the pointer was picked by a finger (held on its words), followed as that changes.
pub fn Ctx::selection_by_finger(self : Ctx) -> Bool {
  ignore(self)
  picked_finger_said.get()
}

///|
/// Whether (x, y) is on a handle of what a finger picked, as the last frame painted them.
fn finger_end_at(x : Double, y : Double) -> Bool {
  picked.finger &&
  finger_ends.iter().any(fn(e) {
    match e {
      Some(h) => x >= h.x && x < h.x + h.w && y >= h.y && y < h.y + h.h
      None => false
    }
  })
}
