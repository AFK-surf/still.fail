// A Tester drawing a page's lists with nothing kept from one frame to the next (Tester::keep_no_rows): each row and
// what holds others drawn anew in every frame, as were it never drawn, so that a test can give the same inputs to two
// Testers, one keeping rows as a device does and one keeping none, and compare what each frame draws. Nothing of the
// app's asks it: the Tester lets go of what was kept after each frame it draws.

///|
/// Whether what the paint kept of a page's lists' rows and of what holds others is let go after each frame.
// kept across runs: set by the Tester that asks it (Tester::keep_no_rows), off as each Tester is made (reset_globals)
let rows_kept_none : Ref[Bool] = Ref(false)

///|
/// From the next frame on, nothing of a page's lists' rows nor of what holds others kept from one frame to the next
/// (`on`), each drawn anew in every frame; or kept as a device keeps them. The groups the host was told are left as
/// they are, the frame drawn out of them yet: only what the next paint would draw as kept is let go.
pub fn Tester::keep_no_rows(self : Tester, on : Bool) -> Unit {
  ignore(self)
  rows_kept_none.val = on
}

///|
/// A frame drawn: where the Tester keeps no rows, what was kept let go for the next.
fn rows_kept_none_after_frame() -> Unit {
  if rows_kept_none.val {
    ride_kept.clear()
    ride_walked.clear()
  }
}

///|
/// Which numbers of an instance are a place, a size or a clip (0-3, 16-19, 40-43, and where it fades towards a cut,
/// 52-59): compared on the device's pixels within a millionth of one (Tester::drawn_compared). (The numbers: scene.mbt's
/// head.)
fn compared_in_pixels(i : Int) -> Bool {
  (i >= 0 && i < 4) || (i >= 16 && i < 20) || (i >= 40 && i < 44) || (i >= 52 && i < 60)
}

///|
/// Whether instance number `i` of an instance of kind `kind` is a glyph's place in the atlas (12-15 of kinds 1, 3 and 7:
/// glyph, colour glyph, glyph in liquid glass): which of the atlas' cells holds its picture, by the order glyphs were
/// first made in, not what is drawn: left out of every comparison of two ways of drawing a frame.
fn atlas_number(kind : Double, i : Int) -> Bool {
  (kind == 1.0 || kind == 3.0 || kind == 7.0) && i >= 12 && i < 16
}

///|
/// The frame drawn last as its instances, for comparing two ways of drawing one frame (instances_apart): each place,
/// size and clip (compared_in_pixels) in the device's pixels (`sc` of them a point), every other number as it is, but a
/// glyph's place in the atlas, put at 0 (atlas_number).
pub fn Tester::drawn_compared(self : Tester, sc : Double) -> Array[Array[Double]] {
  self
  .drawn_instances()
  .map(fn(a) {
    let kind = a[5]
    a.mapi(fn(i, v) { if atlas_number(kind, i) { 0.0 } else if compared_in_pixels(i) { v * sc } else { v } })
  })
}

///|
/// Where two frames as Tester::drawn_compared gives them part (none: the same): each place, size and clip within a
/// millionth of a device pixel (rounded onto whole pixels, a layout's whole and half pixels go to either side by a
/// float's last bit: a clip's edge at 386.5 pixels kept against 386.49999999999994 drawn anew, both the same float
/// as a host draws it), every other number the same.
pub fn instances_apart(a : Array[Array[Double]], b : Array[Array[Double]]) -> String? {
  if a.length() != b.length() {
    return Some("\{a.length()} instances against \{b.length()}")
  }
  for k in 0..<a.length() {
    let (x, y) = (a[k], b[k])
    if x.length() != y.length() {
      return Some("instance \{k}: \{x.length()} numbers against \{y.length()}")
    }
    for i in 0..<x.length() {
      let same = if compared_in_pixels(i) { (x[i] - y[i]).abs() <= 1.0e-6 } else { x[i] == y[i] }
      if !same {
        return Some("instance \{k} (kind \{x[5]}), number \{i}: \{x[i]} against \{y[i]}")
      }
    }
  }
  None
}

///|
/// Where a place, a size or a clip is put on a fine grid for the two runs' judged hash (frame_kept_said): a 1024th of
/// a device pixel, its edges moved off every whole, half and other small fraction of one by the golden ratio's part, so
/// that two numbers a float's last bits apart fall in one cell (a layout's places sit on whole and half pixels, where an
/// edge at 0 would part them by that last bit) but where one lies within those bits of an edge, which the same run
/// does the same way each time: a 1024th of a pixel or more apart always shows.
let kept_grid_off : Double = 0.6180339887

///|
/// How many Testers were made at each place in the test program so far (frame_kept_said's key: the nth made there).
// kept across runs: counts of the program's whole run, the same in the two runs of it that are compared
let kept_made : Map[String, Int] = Map([])

///|
/// What the Tester made last is called in frame_kept_said's key: where it was made and the how-manieth made there.
// kept across runs: set as each Tester is made (Tester::new, kept_made_now)
let kept_made_as : Ref[String] = Ref("")

///|
/// A Tester made at `loc`: its name for frame_kept_said.
fn kept_made_now(loc : String) -> Unit {
  let n = kept_made.get(loc).unwrap_or(0) + 1
  kept_made[loc] = n
  kept_made_as.val = "\{loc}#\{n}"
}

///|
/// A hash of numbers, each folded in (FNV-1a's way over a number's 64 bits).
fn kept_fold(h : UInt64, v : Int64) -> UInt64 {
  let mut h = h
  let mut x = v.reinterpret_as_uint64()
  for _ in 0..<8 {
    h = (h ^ (x & 0xFFUL)) * 0x100000001B3UL
    x = x >> 8
  }
  h
}

///|
/// Where the two runs that compare kept rows with rows drawn anew ask it (MBUI_TEST_FRAMES `1`; the second with
/// MBUI_TEST_KEEP_NONE `1`: test_keeps_none), the frame just drawn said: `KEPT <made> <moment> <nth> <judged> <raw>
/// <asked>`, <made> where its Tester was made and the how-manieth made there, <moment> the frame's on the Tester's clock,
/// <nth> the how-manieth said at it. Judged:
/// each place, size and clip (compared_in_pixels) on the device's pixels put on kept_grid_off's grid, every other
/// number as it is, a glyph's place in the atlas left out (atlas_number). Raw, not judged: every number's bits, the
/// atlas left out the same. Asked: what the app asked of its host for the next frame (wanted, and woken when), which the
/// two runs must say alike for their pictures to be compared.
fn Tester::frame_kept_said(self : Tester, at : Double) -> Unit {
  guard kept_frames_said() else { return }
  let sc = self.fake.scale
  let mut judged = kept_hash_none
  let mut raw = kept_hash_none
  for a in self.drawn_instances() {
    let kind = a[5]
    for i, v in a {
      if atlas_number(kind, i) {
        continue
      }
      raw = kept_fold(raw, v.reinterpret_as_int64())
      judged = kept_fold(
        judged,
        if compared_in_pixels(i) {
          (v * sc * 1024.0 + kept_grid_off).floor().to_int64()
        } else {
          v.reinterpret_as_int64()
        },
      )
    }
  }
  // what the app asked of its host: the next frame (asked between frames, by the frame, woken when), the clipboard,
  // what it opened; and what it sent its core since the frame before (kept_core_told)
  let c = g()
  let mut asked = kept_core.val
  kept_core.val = kept_hash_none
  asked = kept_fold(asked, self.wanted_next().reinterpret_as_int64())
  asked = kept_fold(asked, if self.fake.wants || c.wants_frame { 1L } else { 0L })
  asked = kept_fold_words(asked, self.fake.clipboard)
  for u in self.fake.opened {
    asked = kept_fold_words(asked, u)
  }
  // (the how-manieth frame of this Tester at this moment: a test may draw a moment again)
  let nth = if kept_at_last.val == (kept_made_as.val, at) { kept_at_nth.val + 1 } else { 1 }
  kept_at_last.val = (kept_made_as.val, at)
  kept_at_nth.val = nth
  println("KEPT \{kept_made_as.val} \{at} \{nth} \{judged} \{raw} \{asked}")
  let key = "\{kept_made_as.val} \{at} \{nth}"
  if kept_dump_all.val || kept_dump_keys().contains(key) {
    self.frame_kept_dumped(key, sc)
  }
  kept_core_lines.clear()
}

///|
/// The frames whose instances and asks are said whole as well (MBUI_TEST_FRAME_DUMP: `<made> <moment> <nth>` keys as
/// KEPT lines say them, `;` between; `*` every frame), for reading what two runs' differing frames hold.
fn kept_dump_keys() -> Array[String] {
  if kept_dump_read.val is None {
    let d = test_frame_dump()
    kept_dump_all.val = d == "*"
    kept_dump_read.val = Some(d.split(";").map(fn(v) { v.trim().to_owned() }).filter(fn(v) { v != "" }).collect())
  }
  kept_dump_read.val.unwrap_or([])
}

///|
// kept across runs: the test program's own environment, read once
let kept_dump_read : Ref[Array[String]?] = Ref(None)

///|
// kept across runs: as kept_dump_read
let kept_dump_all : Ref[Bool] = Ref(false)

///|
/// What the app sent its core since the frame said last, whole, where frames are dumped (kept_dump_keys).
// kept across runs: emptied by each frame said
let kept_core_lines : Array[String] = []

///|
/// The frame `key` said whole: each instance's judged numbers (places on the 1024ths grid, the atlas left out) with
/// what drew it, and what the app asked of its host and sent its core.
fn Tester::frame_kept_dumped(self : Tester, key : String, sc : Double) -> Unit {
  let c = g()
  println(
    "KDUMP \{key} built=\{self.built_why()} painted=\{self.painted_why()} looks_alone=\{self.looks_alone()} asks next=\{self.wanted_next()} fake.wants=\{self.fake.wants} wants_frame=\{c.wants_frame} wake_at=\{c.wake_at} why=\{self.wanted_why()} clipboard=\{self.fake.clipboard} opened=\{self.fake.opened.length()}",
  )
  for m in kept_core_lines {
    println("KDUMP \{key} core \{m}")
  }
  for i, a in self.drawn_instances() {
    let kind = a[5]
    let vals = a.mapi(fn(j, v) {
      if atlas_number(kind, j) {
        "-"
      } else if compared_in_pixels(j) {
        (v * sc * 1024.0 + kept_grid_off).floor().to_int64().to_string()
      } else {
        v.to_string()
      }
    })
    println("KDUMP \{key} i\{i} \{vals.join(",")} @ \{self.sources_at(a[0] + a[2] / 2.0, a[1] + a[3] / 2.0).replace_all(old="\n", new=" / ")}")
  }
}

///|
/// The Tester and moment of the frame said last, and how many were said at it (frame_kept_said).
// kept across runs: the program's whole run, the same in both runs compared
let kept_at_last : Ref[(String, Double)] = Ref(("", -1.0))

///|
// kept across runs: as kept_at_last
let kept_at_nth : Ref[Int] = Ref(0)

///|
/// What frame_kept_said's hashes begin with (FNV-1a's offset).
let kept_hash_none : UInt64 = 0xCBF29CE484222325UL

///|
/// What the app sent its core since the frame said last, folded (frame_kept_said takes it).
// kept across runs: taken by each frame said, the next Tester's first frame taking what came before it as well (the
// same in both runs)
let kept_core : Ref[UInt64] = Ref(kept_hash_none)

///|
/// A message the app sent its core, kept for the frame to say (frame_kept_said): told by the app's test rig, which
/// keeps the core's trace to it as each Tester starts where frames are said (frames_said; stillfail's sffixture), no
/// line of the app's running path its own.
pub fn kept_core_told(s : String) -> Unit {
  if kept_frames_said() {
    kept_core.val = kept_fold_words(kept_core.val, s)
    if kept_dump_all.val || kept_dump_keys().length() > 0 {
      kept_core_lines.push(s)
    }
  }
}

///|
/// Whether every frame a Tester draws is said, for the two runs comparing kept rows with rows drawn anew
/// (MBUI_TEST_FRAMES `1`: frame_kept_said): what a test's rig asks before keeping what it would say of them.
pub fn frames_said() -> Bool {
  kept_frames_said()
}

///|
/// Words folded into a frame_kept_said hash, each of their code units, then their length.
fn kept_fold_words(h : UInt64, s : String) -> UInt64 {
  let mut h = h
  for i in 0..<s.length() {
    h = kept_fold(h, s.code_unit_at(i).to_int().to_int64())
  }
  kept_fold(h, s.length().to_int64())
}

///|
/// Whether every frame is said (test_frames_said), asked once.
fn kept_frames_said() -> Bool {
  if kept_said_now.val < 0 {
    kept_said_now.val = if test_frames_said() { 1 } else { 0 }
  }
  kept_said_now.val == 1
}

///|
// kept across runs: the test program's own environment, asked once (-1 not yet)
let kept_said_now : Ref[Int] = Ref(-1)
