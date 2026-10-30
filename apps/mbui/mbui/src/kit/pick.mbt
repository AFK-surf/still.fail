// Picking a passage of words where they are (Android's text selection; still.fail's MessagePick.kt and Pick.kt, the
// web's mobile/pick.tsx), over the words @ui keeps of a box (Ctx::words, words_of): a finger held still on them a long
// press's time picks the word under it and, sliding on, widens it by words from that word; lifted, the passage has a
// handle at each end, which a finger takes and moves (the end following it from where it was taken, not jumping to
// under it), never past the other end; a tap anywhere else lets go of it. What the passage is for (a bar over it:
// quote, copy, all of it) and how it and its handles look are the view's; this is how a finger picks.

///|
/// A passage picked: the words' key ("" none), from `a` until `b` of their text (UTF-16), the word first held
/// (`from_a`, `from_b`), whether a finger is widening it, which handle a finger has (1 the start's, 2 the end's, 0
/// none) and the end's place off the finger, and the press that picked it.
pub(all) struct Pick {
  mut key : String
  mut a : Int
  mut b : Int
  mut from_a : Int
  mut from_b : Int
  mut widening : Bool
  mut handle : Int
  mut grab_x : Double
  mut grab_y : Double
  mut press : Int
}

///|
/// Nothing picked.
pub fn Pick::new() -> Pick {
  { key: "", a: 0, b: 0, from_a: 0, from_b: 0, widening: false, handle: 0, grab_x: 0.0, grab_y: 0.0, press: -1 }
}

///|
/// Let go of what is picked.
pub fn Pick::clear(self : Pick) -> Unit {
  self.key = ""
  self.widening = false
  self.handle = 0
}

///|
/// As new (a Tester's start).
pub fn Pick::reset(self : Pick) -> Unit {
  self.clear()
  self.a = 0
  self.b = 0
  self.from_a = 0
  self.from_b = 0
  self.grab_x = 0.0
  self.grab_y = 0.0
  self.press = -1
}

///|
/// Whether a passage of `key`'s words is picked.
pub fn Pick::of(self : Pick, key : String) -> Bool {
  self.key != "" && self.key == key
}

///|
/// A finger held on `key`'s words in box `id`, a long press's time from when it went down, picks the word under where
/// it went down (Ctx::press), widened from it as the finger slides on; it picks once a press. Held: the press went
/// down in the box as drawn (Ctx::press_within: not under what lies over it, a layer over the page) and is still there,
/// and the view lets it (`may`: no handle of its held, say). True on the frame it picks: the press is the pick's from
/// then (the view takes it, Ctx::take_press, and says so to the hand).
pub fn Pick::hold(self : Pick, c : @ui.Ctx, key : String, id : Int, may? : Bool = true) -> Bool {
  let press = c.press()
  let holding = may && press.down && !press.moved && c.press_within(id)
  // (asked each frame, so that a press let go starts again from nothing; a frame asked for when it will have)
  let held = after(c, key + "/hold", holding && self.press != press.frame, @ui.long_press_ms)
  if !held {
    return false
  }
  match c.words_of(key) {
    Some(w) if w.text != "" => {
      let (s, e) = w.word_at(w.offset_at(press.x, press.y))
      self.key = key
      self.a = s
      self.b = e
      self.from_a = s
      self.from_b = e
      self.widening = true
      self.handle = 0
      self.press = press.frame
      // (picked as the view is built, after what draws it read it: built again in this frame, as it is)
      c.built_from_changed("a passage picked")
      true
    }
    _ => false
  }
}

///|
/// The finger that picked it: still down and slid past the slop, the passage from the word first held to the word under
/// it, by words; lifted, no longer widened.
pub fn Pick::slide(self : Pick, c : @ui.Ctx) -> Unit {
  if self.key == "" || !self.widening {
    return
  }
  let (x, y, down) = c.pointer()
  if !down {
    self.widening = false
    return
  }
  // (widened as the finger slides on, not as the words move under a finger still where it went down: a row going
  // under them, the list putting them elsewhere, is no slide)
  if !c.press().moved {
    return
  }
  match c.words_of(self.key) {
    Some(w) => {
      let (s, e) = w.word_at(w.offset_at(x, y))
      if s >= self.from_a {
        self.picked(c, self.from_a, if e > self.from_b { e } else { self.from_b })
      } else {
        self.picked(c, s, self.from_b)
      }
    }
    None => ()
  }
}

///|
/// From `a` until `b` picked now, as the view is built: where that is not what was, what drew it read it before, and
/// the frame is built again, as it is (Ctx::built_from_changed).
fn Pick::picked(self : Pick, c : @ui.Ctx, a : Int, b : Int) -> Unit {
  if a == self.a && b == self.b {
    return
  }
  self.a = a
  self.b = b
  c.built_from_changed("a passage picked widened")
}

///|
/// Whether (x, y) is in what `id` was laid out as.
fn pick_in(c : @ui.Ctx, id : Int, x : Double, y : Double) -> Bool {
  match c.rect_of(id) {
    Some((rx, ry, rw, rh)) => x >= rx && x < rx + rw && y >= ry && y < ry + rh
    None => false
  }
}

///|
/// The handles, `ends` (the start's and the end's: what takes a finger round each): a press that went down this frame
/// (Ctx::press) on one is its (the view takes it, Ctx::take_press: lifted wherever the end and its handle have gone,
/// it taps nothing), the end's place off the finger kept; while the finger is down the end follows it, never past the
/// other end; lifted, let go. `words` as laid out.
pub fn Pick::handles(self : Pick, c : @ui.Ctx, words : @ui.Words, ends : Array[Int]) -> Unit {
  let press = c.press()
  let (x, y, down) = c.pointer()
  let (pressed_now, down_x, down_y) = (press.fresh, press.x, press.y)
  let lines = words.rects(self.a, self.b)
  if lines.length() == 0 {
    return
  }
  let first = lines[0]
  let last = lines[lines.length() - 1]
  if pressed_now && self.handle == 0 {
    for k, id in ends {
      if pick_in(c, id, down_x, down_y) {
        self.handle = k + 1
        let (ex, ey) = if k == 0 {
          (first.0, first.1 + first.3 / 2.0)
        } else {
          (last.0 + last.2, last.1 + last.3 / 2.0)
        }
        self.grab_x = ex - down_x
        self.grab_y = ey - down_y
      }
    }
    if self.handle != 0 {
      c.take_press()
    }
  }
  if self.handle != 0 {
    if !down {
      self.handle = 0
    } else {
      let at = words.offset_at(x + self.grab_x, y + self.grab_y)
      if self.handle == 1 {
        self.picked(c, if at < self.b - 1 { at } else { self.b - 1 }, self.b)
      } else {
        self.picked(c, self.a, if at > self.a + 1 { at } else { self.a + 1 })
      }
    }
  }
}

///|
/// A tap anywhere but on `keep` (the passage's bar, its handles) lets go of it (not the lifting of a press the pick
/// took: the one that picked it, one a handle moved). True when it did.
pub fn Pick::tapped_away(self : Pick, c : @ui.Ctx, keep : Array[Int]) -> Bool {
  if self.key == "" {
    return false
  }
  match c.tapped_anywhere() {
    Some((tx, ty)) if !keep.iter().any(fn(id) { pick_in(c, id, tx, ty) }) => {
      self.clear()
      c.built_from_changed("a passage let go")
      true
    }
    _ => false
  }
}

///|
/// All of `words` picked.
pub fn Pick::all(self : Pick, words : @ui.Words) -> Unit {
  self.a = 0
  self.b = words.text.length()
}
