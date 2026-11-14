// The Tester's fake host as mbui/hostapi's `Host` (Tester::new sets it): every answer a test's host gives, to the
// framework (hostcall.mbt, hostread.mbt, ctx.mbt…: each asks @hostapi, whoever the host is) and to the app asking its
// host directly (@hostapi.log, @hostapi.decode_charset…) alike. What it does not answer, as a host with nothing for it
// answers (hostapi's defaults). A test's program has no other host: it links no host's code.

///|
/// A package handed to the system's installer: kept by its name (Tester::installs).
impl @hostapi.Host for FakeHost with install_package(self, name, _) {
  self.installs.push(name)
}

///|
impl @hostapi.Host for FakeHost with window_show(self) {
  self.window_shows = self.window_shows + 1
}

///|
/// The person's setting for motion (Tester::set_reduce_motion).
impl @hostapi.Host for FakeHost with reduce_motion(self) {
  self.reduce_motion
}

///|
/// A scripted run's step given to it to send as its own (drive.mbt): the window resized (8: "<w>x<h>", the Tester's
/// next frames that size); none of the others (the script sends them to the app itself).
impl @hostapi.Host for FakeHost with drive(_, kind, text) {
  if kind != 8 {
    return false
  }
  let wh = text.split("x").map(fn(v) { number(v.to_owned()) }).to_array()
  if wh.length() < 2 {
    return false
  }
  tester_size.val = Some((wh[0], wh[1]))
  true
}

///|
/// The app ended (a scripted run's verdict): noted on its log ("EXIT <code>").
impl @hostapi.Host for FakeHost with exit(self, code) {
  self.logs.push("EXIT \{code}")
}

///|
/// An update asked for: kept as asked (Tester::update_asked), with the delta it was given where there was one.
impl @hostapi.Host for FakeHost with update_fetch(_, _, _, _, name, now, delta) {
  update_asked.push(if delta == "" { "fetch \{name} \{now}" } else { "fetch \{name} \{now} delta \{delta}" })
}

///|
impl @hostapi.Host for FakeHost with update_apply(_, _) {
  update_asked.push("apply")
}

///|
/// How an update goes: as the test told it (Tester::tells_update).
impl @hostapi.Host for FakeHost with update_state(_) {
  update_told.untracked()
}

// The system's pickers and the files kept on the device (@hostapi pick.mbt, keep.mbt) as a test has them: its pickers
// give what the test said (Tester::picks) at the moment each is asked, told as a host's event tells it (FakeHost::due:
// after the event that asked, before the clock moves on); what the app keeps is kept by the test (Tester::kept), from
// the frame after it was finished.

///|
priv struct FakePick {
  kind : @hostapi.PickKind
  /// its answer told (the host's event said): what the pickers give is there to take from then
  mut said : Bool
  mut taken : Bool
}

///|
priv struct FakeKeep {
  name : String
  mime : String
  way : @hostapi.KeepWay
  data : Array[Byte]
  /// the frame it was finished in (-1: not yet): kept from the next on; let go of
  mut finished : Int
  mut ended : Bool
}

///|
/// An ask of its pickers (its id, from 1: the ask's place; Tester::drop_files's too).
impl @hostapi.Host for FakeHost with pk_start(self, kind) {
  let kind : @hostapi.PickKind = match kind & 15 {
    1 => Photos
    3 => Camera
    _ => Files
  }
  self.pick_asks.push({ kind, said: false, taken: false })
  let id = self.pick_asks.length()
  // (answered at the moment it is asked, the host's event after the one that asked; where the test answers its pickers
  // itself, as it says: Tester::pick_answer)
  if !self.picks_by_hand {
    self.due(self.time, "a pick answered", fn() { fake_pick_said(self, id) })
  }
  id
}

///|
impl @hostapi.Host for FakeHost with pk_photo(self, _) {
  @hostapi.Host::pk_start(self, 1)
}

///|
/// Ask `id` answered with what the pickers give: told as a host's event tells it (on_outside, MB_OUTSIDE_PICK).
fn fake_pick_said(f : FakeHost, id : Int) -> Unit {
  guard f.pick_asks.get(id - 1) is Some(a) && !a.said else { return }
  a.said = true
  on_outside(outside_pick, id, 1)
}

///|
/// How ask `id` goes: 0 asking (till its answer is told: fake_pick_said), 1 answered, -1 let go of or none.
impl @hostapi.Host for FakeHost with pk_state(self, id) {
  match self.pick_asks.get(id - 1) {
    Some(a) if !a.taken => if a.said { 1 } else { 0 }
    _ => -1
  }
}

///|
impl @hostapi.Host for FakeHost with pk_count(self, _) {
  self.picks.length()
}

///|
impl @hostapi.Host for FakeHost with pk_name(self, _, i) {
  match self.picks.get(i) {
    Some(p) => p.name
    None => ""
  }
}

///|
impl @hostapi.Host for FakeHost with pk_bytes(self, _, i) {
  match self.picks.get(i) {
    Some(p) => p.bytes
    None => b""
  }
}

///|
impl @hostapi.Host for FakeHost with pk_info(self, _, i) {
  match self.picks.get(i) {
    Some(p) => "\{p.held}\t\{p.size.to_int64()}\t\{p.src}"
    None => ""
  }
}

///|
/// An ask let go of (answered, or a drop nothing took): taken.
impl @hostapi.Host for FakeHost with pk_end(self, id) {
  match self.pick_asks.get(id - 1) {
    Some(a) => a.taken = true
    None => ()
  }
}

///|
/// A file to keep (its id, from 1).
impl @hostapi.Host for FakeHost with kp_begin(self, name, mime, way) {
  let way : @hostapi.KeepWay = match way {
    2 => Choose
    3 => Photos
    _ => Downloads
  }
  self.keeps.push({ name, mime, way, data: [], finished: -1, ended: false })
  self.keeps.length()
}

///|
impl @hostapi.Host for FakeHost with kp_append(self, id, data) {
  match self.keeps.get(id - 1) {
    Some(k) if k.finished < 0 && !k.ended => {
      for b in data {
        k.data.push(b)
      }
      1
    }
    _ => 0
  }
}

///|
impl @hostapi.Host for FakeHost with kp_finish(self, id) {
  match self.keeps.get(id - 1) {
    Some(k) if k.finished < 0 => {
      k.finished = g().frame_no
      self.wants = true
    }
    _ => ()
  }
}

///|
/// How a keep stands: kept from the frame after it was finished (1), called off (2), keeping (0), none (-1).
impl @hostapi.Host for FakeHost with kp_state(self, id) {
  match self.keeps.get(id - 1) {
    Some(k) if k.ended && k.finished < 0 => 2
    Some(k) if k.finished >= 0 && g().frame_no > k.finished => 1
    Some(_) => 0
    None => -1
  }
}

///|
/// Where it was kept: where the system keeps downloads ("Download/" and its name; in MBUI_DOWNLOADS_DIR, as a
/// scripted run's host keeps there, its path).
impl @hostapi.Host for FakeHost with kp_where(self, id) {
  match self.keeps.get(id - 1) {
    Some(k) =>
      match self.env.get("MBUI_DOWNLOADS_DIR").unwrap_or("") {
        "" => "Download/" + k.name
        dir => dir + "/" + k.name
      }
    None => ""
  }
}

///|
impl @hostapi.Host for FakeHost with kp_end(self, id) {
  match self.keeps.get(id - 1) {
    Some(k) => k.ended = true
    None => ()
  }
}

///|
/// Its clock: the frames' (Tester::run_for…).
impl @hostapi.Host for FakeHost with now(self) {
  self.time
}

///|
/// Its day: Tester::set_wall's at its clock's 0, on with its clock.
impl @hostapi.Host for FakeHost with wall_ms(self) {
  self.wall + self.time
}

///|
/// Its day at its clock's 0 taken from `ms`, as it is (both whole ms where the test says them; its local time is
/// UTC's: utc_offset_min's default 0).
impl @hostapi.Host for FakeHost with clock_at_wall(self, ms) {
  ms - self.wall
}

///|
/// When the input event being handled happened where the test says it apart from its clock (a test's event taken
/// late: Tester::touch_at); -1, as the clock has it.
impl @hostapi.Host for FakeHost with event_time(self) {
  self.event_at
}

///|
/// What it says the pointer's events come from (Tester::host_says_finger): 1 a finger, 0 a mouse, -1 not said.
impl @hostapi.Host for FakeHost with event_finger(self) {
  self.event_finger
}

///|
/// How late the frame before this one reached the screen: as said for this frame (Tester::frame_late, a run's LATE
/// line), else on time.
impl @hostapi.Host for FakeHost with frame_late(self) {
  let c = g()
  if self.late_after < 0.0 || c.clock <= self.late_after {
    return 0.0
  }
  if self.late_frame < 0 {
    self.late_frame = c.frame_no
  }
  if self.late_frame == c.frame_no {
    self.late
  } else {
    self.late_after = -1.0
    0.0
  }
}

///|
/// The system it plays (Tester::new's `platform`).
impl @hostapi.Host for FakeHost with platform(self) {
  self.platform
}

///|
/// The system whose keys are typed (Tester::new's `keys`: by default the system it plays).
impl @hostapi.Host for FakeHost with keys_platform(self) {
  self.keys
}

///|
impl @hostapi.Host for FakeHost with request_frame(self) {
  self.wants = true
  self.paced = 0.0
}

///|
/// A frame for what moves on by the clock: owed none at this moment (its time goes by run_for), counted
/// (Tester::frames_on).
impl @hostapi.Host for FakeHost with request_frame_on(self) {
  self.frames_on = self.frames_on + 1
  self.paced = 0.0
}

///|
/// A frame for what moves on by the clock that needs only `hz` frames a second: counted as request_frame_on's, its rate
/// told (Tester::frames_paced); its own frames are run_for's, whatever it is told.
impl @hostapi.Host for FakeHost with frames_paced(self, hz) {
  self.frames_on = self.frames_on + 1
  self.paced = hz
}

///|
impl @hostapi.Host for FakeHost with wake_after(self, ms) {
  if self.wake < 0.0 || self.time + ms < self.wake {
    self.wake = self.time + ms
  }
}

///|
/// Its text: a live host's (Tester::new's `live`); else a host's kept text where it has it (text_table); else its own
/// deterministic metrics.
impl @hostapi.Host for FakeHost with font_metrics(self, size, weight, style, out) {
  if self.live is Some(l) {
    l.host.font_metrics(size, weight, style, out)
    return
  }
  if kept_metrics(size, weight, style, out) {
    return
  }
  out[0] = size * 0.8
  out[1] = size * 0.2
  out[2] = (size * 1.42).round()
}

///|
/// Fake shaping: one cluster per extended grapheme cluster, as real hosts
/// make them; Latin half an em wide (0.6 in the code face; ASCII as a real face where the test says:
/// Tester::latin_advances), everything else a full em.
impl @hostapi.Host for FakeHost with shape(self, text, size, weight, style, out) {
  if self.live is Some(l) {
    return l.host.shape(text, size, weight, style, out)
  }
  if kept_shape(text, size, weight, style, out) is Some(k) {
    return k
  }
  let n = text.length()
  let cap = out.length() / 4
  let mut i = 0
  let mut k = 0
  while i < n && k < cap {
    let c = text.at(i).to_int()
    let len = @text.next_grapheme(text, i) - i
    let mono = (style & @hostapi.style_mono) != 0
    // (a letter measured as a real face measures it: latin_advances)
    let real = match self.latin {
      Some((regular, bold)) if !mono && c >= 32 && c <= 126 =>
        Some(size * (if weight >= 600 { bold[c - 32] } else { regular[c - 32] }))
      _ => None
    }
    let adv = if c == 10 {
      0.0
    } else if real is Some(a) {
      a
    } else if c < 0x2E80 {
      if mono {
        size * 0.6
      } else {
        size * 0.5
      }
    } else {
      size
    }
    let adv = if weight >= 600 && c != 10 && real is None { adv + size * self.bold } else { adv }
    let adv = if self.ui_face != 0.0 && c != 10 && in_ui_face(style) { adv + size * self.ui_face } else { adv }
    let adv = if self.tabular != 0.0 && c >= 48 && c <= 57 && (style & @hostapi.style_tabular) != 0 {
      adv + size * self.tabular
    } else {
      adv
    }
    let adv = match self.faces_wider.get(@hostapi.face_of_style(style)) {
      Some(em) if c != 10 => adv + size * em
      _ => adv
    }
    out[k * 4] = i.to_double()
    out[k * 4 + 1] = len.to_double()
    out[k * 4 + 2] = adv
    // U+E000 plays a ligature's second letter: drawn as part of the cluster before it (unless shaped with no
    // ligatures)
    out[k * 4 + 3] = if c == 32 || c == 10 {
      -1.0
    } else if c == 0xE000 && k > 0 && (style & @hostapi.style_no_ligatures) == 0 {
      -2.0
    } else {
      c.to_double()
    }
    i = i + len
    k = k + 1
  }
  k
}

///|
/// Whether words in `style` are set in the app's words' face (face_ui) as a host sets them: one is given and the style
/// names no other (code's, the serif one, what people wrote's, one by its number).
fn in_ui_face(style : Int) -> Bool {
  face_given(@hostapi.face_ui) &&
  @hostapi.face_of_style(style) == 0 &&
  (style & (@hostapi.style_mono | @hostapi.style_serif | @hostapi.style_words)) == 0
}

///|
impl @hostapi.Host for FakeHost with text_key(self, text, size, weight, style) {
  if self.live is Some(l) {
    return l.host.text_key(text, size, weight, style)
  }
  match kept_key(text, size, weight, style) {
    Some(k) => k
    None => text.at(0).to_int()
  }
}

///|
impl @hostapi.Host for FakeHost with glyph(self, key, out) {
  if self.live is Some(l) {
    l.host.glyph(key, out)
    return
  }
  if kept_glyph(key, out) {
    return
  }
  // a glyph box per cluster, so painting is exercised
  out[0] = 0.0
  out[1] = 0.0
  out[2] = self.glyph_box.0
  out[3] = self.glyph_box.1
  out[4] = 0.0
  out[5] = -10.0
  out[6] = if key >= 0x1F000 { 1.0 } else { 0.0 }
}

///|
/// A glyph's picture put in the atlas: a live host's; the fake has no pictures.
impl @hostapi.Host for FakeHost with glyph_put(self, key, x, y) {
  if self.live is Some(l) {
    l.host.glyph_put(key, x, y)
  }
}

///|
/// The side of a fake host's atlas: the web's (its glyphs placed in it as a host's are), colour glyphs in it with the
/// others.
let fake_atlas_size : Int = 2048

///|
impl @hostapi.Host for FakeHost with atlas_size(self, colour) {
  match self.live {
    Some(l) => l.host.atlas_size(colour)
    None => if colour { 0 } else { fake_atlas_size }
  }
}

///|
/// A face's file: a live host's; the fake takes any (its words measured as ever), but one the test made unreadable
/// (Tester::set_unreadable_font).
impl @hostapi.Host for FakeHost with face_add(self, face, path, weight) {
  match self.live {
    Some(l) => l.host.face_add(face, path, weight)
    None => {
      let ok = !self.unreadable_fonts.contains(path)
      if ok && self.generation_on_face_add.val {
        self.generation += 1
      }
      ok
    }
  }
}

///|
impl @hostapi.Host for FakeHost with face_add_bytes(self, face, data, weight) {
  match self.live {
    Some(l) => l.host.face_add_bytes(face, data, weight)
    None => data.length() > 0
  }
}

///|
impl @hostapi.Host for FakeHost with face_clear(self, face) {
  if self.live is Some(l) {
    l.host.face_clear(face)
  }
}

///|
impl @hostapi.Host for FakeHost with face_add_family(self, face, family) {
  match self.live {
    Some(l) => l.host.face_add_family(face, family)
    None => {
      self.families_given[face] = family
      true
    }
  }
}

///|
/// The font families installed as it says them (Tester::set_local_fonts).
impl @hostapi.Host for FakeHost with local_font_families(self) {
  self.local_fonts
}

///|
/// Its glyphs' generation (each ask counted: Tester's): a live host's, else its own.
impl @hostapi.Host for FakeHost with atlas_generation(self) {
  self.generation_asks += 1
  match self.live {
    Some(l) => l.host.atlas_generation()
    None => self.generation
  }
}

///|
/// The system asks for less transparency (Tester::set_reduce_transparency).
impl @hostapi.Host for FakeHost with reduce_transparency(self) {
  self.reduce_transparency
}

///|
/// Its performance record (Tester::set_perf): -1 none kept here, 0 off, 1 on.
impl @hostapi.Host for FakeHost with perf_state(self) {
  self.perf
}

///|
impl @hostapi.Host for FakeHost with set_perf(self, on) {
  if self.perf >= 0 {
    self.perf_sets.push(on)
    self.perf = if on { 1 } else { 0 }
  }
}

///|
impl @hostapi.Host for FakeHost with perf_line(self, line) {
  if self.perf == 1 {
    self.perf_lines.push(line)
  }
}

///|
impl @hostapi.Host for FakeHost with perf_where(self) {
  if self.perf >= 0 {
    "Documents/perf"
  } else {
    ""
  }
}

///|
impl @hostapi.Host for FakeHost with perf_open(self, go) {
  if !self.perf_opens {
    return false
  }
  if go {
    self.perf_opened += 1
  }
  true
}

///|
impl @hostapi.Host for FakeHost with perf_size(self) {
  // (what the lines weigh is the real host's, whose times are not a test's: as the test says, Tester::set_perf_size)
  self.perf_bytes
}

///|
/// The field as it was told (its input method's), counted.
impl @hostapi.Host for FakeHost with set_ime(self, active, x, y, w, h, text, a, b) {
  self.ime_active = active
  self.ime_text = text
  self.ime_sel = (a, b)
  self.ime_rect = (x, y, w, h)
  self.ime_told = self.ime_told + 1
}

///|
impl @hostapi.Host for FakeHost with text_menu(self, shown, x, y, w, h, can) {
  self.text_menu = (shown, x, y, w, h, can)
}

///|
impl @hostapi.Host for FakeHost with text_menu_own(self, words) {
  self.text_menu_own = words
}

///|
impl @hostapi.Host for FakeHost with edit_can(self, can) {
  self.edit_can = can
}

///|
impl @hostapi.Host for FakeHost with clipboard_set(self, s) {
  self.clipboard = s
  self.clipboard_secret = -1.0
}

///|
/// A word's bounds: a live host's; under a host's kept text, the host's word as it said it (a word it did not say: the
/// test is told, Tester::text_missing, and gets none of its own made up in its place); with no kept text, none.
impl @hostapi.Host for FakeHost with word_at(self, text, off) {
  if self.live is Some(l) {
    return l.host.word_at(text, off)
  }
  match text_table.val {
    Some(_) => {
      let head : Json = [Json::string(text), Json::number(off.to_double())]
      match kept_answer("wa", head) {
        Some(Array([Number(s, ..), Number(e, ..), ..])) => (s.to_int(), e.to_int())
        _ => (-1, -1)
      }
    }
    None => (-1, -1)
  }
}

///|
/// A URL handed to the system: kept (Tester::opened).
impl @hostapi.Host for FakeHost with open_url(self, url) {
  self.opened.push(url)
  true
}

///|
/// A page in a browser's tab: kept as one handed to the system (Tester::opened).
impl @hostapi.Host for FakeHost with open_tab(self, url) {
  self.opened.push(url)
  true
}

///|
impl @hostapi.Host for FakeHost with back_enabled(self, on) {
  self.back_on = on
}

///|
impl @hostapi.Host for FakeHost with wheel_kept(self, kept) {
  self.wheel_kept = kept
}

///|
/// Something reading the widgets out (Tester's a11y_on).
impl @hostapi.Host for FakeHost with a11y_on(self) {
  self.a11y
}

///|
impl @hostapi.Host for FakeHost with a11y_tree(self, tree) {
  self.a11y_said = tree
  // (kept as a host keeps it: A11yMirror::apply)
  match a11y_update_read(tree) {
    Some((full, focus, told)) => self.a11y_told.apply(full, focus, told) |> ignore
    None => ()
  }
}

///|
impl @hostapi.Host for FakeHost with log(self, s) {
  self.logs.push(s)
}

///|
/// A picture by its source: a live host's decode (its sizes as that host has them); else as the host decoded it, when
/// kept with the text; else as the test made it up (Tester::new's images), one it does not know failed at once.
impl @hostapi.Host for FakeHost with image_load(self, src, max_px) {
  self.image_loads.push((src, max_px))
  let head : Json = [Json::string(src), Json::number(max_px.to_double())]
  let id = match self.live {
    Some(l) => live_image(self, l, l.host.image_load(src, max_px), { "is": head })
    None => {
      let id = match (self.image_sizes.get(src), text_table.val) {
        (None, Some(_)) =>
          match kept_sizes(kept_answer("is", head)) {
            Some((w, h, ow, oh)) => fake_image_sized(self, w, h, ow, oh)
            None => fake_image(self, 0, 0, max_px)
          }
        (sized, _) => {
          let (w, h) = sized.unwrap_or((0, 0))
          fake_image(self, w, h, max_px)
        }
      }
      match self.pixels_of_src.get(src) {
        Some(px) => self.pixels_of[id] = px
        None => ()
      }
      id
    }
  }
  // (its source kept, a failed one's too: Tester::image_src describes the same id as a live host's)
  self.image_srcs[id] = src
  // (said to take a while: done that long after it is asked for, Tester::decode_after)
  match self.decode_after.get(src) {
    Some(ms) => self.decode_due[id] = self.time + ms
    None => ()
  }
  id
}

///|
/// Bytes decoded: a live host's decode; else as the host decoded these bytes, when kept with the text; else a made-up
/// 400 × 300.
impl @hostapi.Host for FakeHost with image_load_bytes(self, data, max_px) {
  self.image_loads.push(("bytes:\{data.length()}", max_px))
  let head = image_bytes_head(data, max_px)
  let id = match self.live {
    Some(l) => live_image(self, l, l.host.image_load_bytes(data, max_px), { "ib": head })
    None =>
      match (text_table.val, kept_sizes(kept_answer("ib", head))) {
        (Some(_), Some((w, h, ow, oh))) => fake_image_sized(self, w, h, ow, oh)
        _ => fake_image(self, 400, 300, max_px)
      }
  }
  self.image_bytes[id] = data.length()
  self.image_bytes_now += data.length()
  if self.image_bytes_now > self.image_bytes_most {
    self.image_bytes_most = self.image_bytes_now
    host_image_bytes_held(self)
  }
  id
}

// What the host holds of the bytes handed over for decodes, at once (FakeHost.image_bytes): a phone's Java side kept a
// GIF's every frame's, 140 MB of a 256 MB heap, and the app was killed (#5301); the tests' every image was small and
// nothing counted what they came to. Held a file at a time, as gaps_steady.mbt's faults: the most a Tester made in a
// file has its host hold at once is at most its file's bar (`host_image_bytes_known`, given by a test package as it
// starts) and a tenth, or `host_image_bytes_free` where the file has none. The bars are what each file's Testers held
// at most when they were set (the user, 2026-11-11: 三条都加), and only fall: one brought down by a change to what is
// handed over is written down in the same change.

///|
/// What a Tester made in a file with no bar may have its host hold at once: an icon's, a few small pictures'.
let host_image_bytes_free : Int = 4096

///|
/// Each file's bar: the most bytes handed over for decodes a Tester made there may have its host hold at once.
// kept across runs: said once as a test program starts (its packages' `init`)
let host_image_bytes_bars : Map[String, Int] = Map([])

///|
/// The most bytes each file's Testers had their hosts hold so far in this run, said as it grows (motion_runs).
// kept across runs: the most of all the program's Testers, each file's said once as it grows
let host_image_bytes_most : Map[String, Int] = Map([])

///|
/// The bars of the files `bars` names, each the most bytes handed over for decodes (image_load_bytes) a Tester made
/// there may have its host hold at once, a tenth over it let by. Said by a test package as it starts (`fn init`);
/// only falls.
pub fn host_image_bytes_known(bars : Array[(String, Int)]) -> Unit {
  motion_bars_said("host_image_bytes", bars)
  for b in bars {
    host_image_bytes_bars.set(b.0, b.1)
  }
}

///|
/// Stops the test where what the host holds of the bytes handed over goes over its file's bar by more than a tenth.
fn host_image_bytes_held(f : FakeHost) -> Unit {
  let file = match f.made_at.find(":") {
    Some(i) => f.made_at.unsafe_substring(start=0, end=i)
    None => f.made_at
  }
  let bar = host_image_bytes_bars.get(file).unwrap_or(host_image_bytes_free)
  // (the most each file's Testers held, said as it grows: motion_runs, `MOTION held host_image_bytes <file> <bytes>`)
  if motion_runs() && f.image_bytes_now > host_image_bytes_most.get(file).unwrap_or(0) {
    host_image_bytes_most.set(file, f.image_bytes_now)
    println("MOTION held host_image_bytes \{file} \{f.image_bytes_now}")
  }
  if f.image_bytes_now * 10 > bar * 11 {
    @halt.saying(
      "the host holds \{f.image_bytes_now} bytes handed over for decodes at once (fake_host.mbt: host_image_bytes_known), " +
      "the Tester made at \{f.made_at}; \{file}'s bar is \{bar}" +
      (if host_image_bytes_bars.contains(file) { "" } else { " (none said: host_image_bytes_free)" }),
    )
  }
}

///|
impl @hostapi.Host for FakeHost with image_info(self, id, out) {
  match self.images.get(id) {
    Some(im) => {
      if im.state == 1 {
        out[0] = im.w
        out[1] = im.h
        out[2] = im.ow
        out[3] = im.oh
      }
      im.state
    }
    None => -1
  }
}

///|
/// A ready image's pixels: a live host's; else as the test made them (Tester::add_pixels), else every pixel a mid
/// grey, opaque.
impl @hostapi.Host for FakeHost with image_pixels(self, id, out) {
  match (self.live, self.live_images.get(id)) {
    (Some(l), Some(mine)) => return l.host.image_pixels(mine, out)
    _ => ()
  }
  match self.images.get(id) {
    Some(im) if im.state == 1 => {
      let n = im.w.to_int() * im.h.to_int() * 4
      match self.pixels_of.get(id) {
        Some(px) if px.length() == n => px.blit_to(out, len=n)
        _ =>
          for i in 0..<n {
            out[i] = if i % 4 == 3 { b'\xFF' } else { b'\x80' }
          }
      }
      true
    }
    _ => false
  }
}

///|
/// The last frame's pixels: a live host's as it drew the frame (a film's), the fake's every pixel a mid grey, opaque.
impl @hostapi.Host for FakeHost with drawn_pixels(self, x, y, w, h, out) {
  match self.live {
    Some(l) => l.host.drawn_pixels(x, y, w, h, out)
    None => {
      for i in 0..<(w * h * 4) {
        out[i] = if i % 4 == 3 { b'\xFF' } else { b'\x80' }
      }
      true
    }
  }
}

///|
/// Instances never presented drawn: a live host's, its pictures that host's own as a film draws a frame (film.mbt
/// draw_frame: one it has not, nothing); the fake's every pixel a mid grey, opaque.
impl @hostapi.Host for FakeHost with drawn_pixels_of(self, inst, count, r, gg, b, scale, w, h, out) {
  match self.live {
    Some(l) => {
      let len = count * inst_size
      let mine = FixedArray::make(if len > 0 { len } else { 1 }, 0.0)
      inst.blit_to(mine, len~)
      for k in 0..<count {
        let at = k * inst_size
        if mine[at + 5] == 4.0 {
          match self.live_images.get(mine[at + 20].to_int()) {
            Some(id) => mine[at + 20] = id.to_double()
            None => {
              // nothing drawn: a rect of no colour, no border, no blur
              mine[at + 5] = 0.0
              for j in 6..<12 {
                mine[at + j] = 0.0
              }
            }
          }
        }
      }
      l.host.drawn_pixels_of(mine, count, r, gg, b, scale, w, h, out)
    }
    None => {
      for i in 0..<(w * h * 4) {
        out[i] = if i % 4 == 3 { b'\xFF' } else { b'\x80' }
      }
      true
    }
  }
}

///|
impl @hostapi.Host for FakeHost with image_free(self, id) {
  self.images.remove(id)
  match self.image_bytes.get(id) {
    Some(n) => {
      self.image_bytes.remove(id)
      self.image_bytes_now -= n
    }
    None => ()
  }
  match (self.live, self.live_images.get(id)) {
    (Some(l), Some(mine)) => {
      self.live_images.remove(id)
      l.host.image_free(mine)
    }
    _ => ()
  }
}

// Native views (native.mbt): the fake host has views of every kind, ready at once, 10 s long and 640 × 360, that
// never ask to read; it notes what is asked of them (FakeHost.views).

///|
impl @hostapi.Host for FakeHost with view_open(self, kind, arg) {
  self.view_ids += 1
  self.views.push("open \{self.view_ids} \{kind} \{arg.length()}")
  self.view_kinds[self.view_ids] = kind
  self.view_ids
}

///|
/// A view placed (device pixels, as a host is told): noted, and where it shows kept in points (what a finger on it
/// is by).
impl @hostapi.Host for FakeHost with view_place(self, id, px, py, pw, ph, pcx0, pcy0, pcx1, pcy1, pr0, pr1, pr2, pr3, shown) {
  self.views.push(
    "place \{id} \{px} \{py} \{pw} \{ph} in \{pcx0} \{pcy0} \{pcx1} \{pcy1}" +
    (if pr0 == pr1 && pr1 == pr2 && pr2 == pr3 {
      if pr0 > 0.0 {
        " round \{pr0}"
      } else {
        ""
      }
    } else {
      " round \{pr0} \{pr1} \{pr2} \{pr3}"
    }) +
    (if shown { "" } else { " hidden" }),
  )
  let z = window_zoom_drawn.val
  let (x, y, w, h) = (px / z, py / z, pw / z, ph / z)
  let (cx0, cy0, cx1, cy1) = (pcx0 / z, pcy0 / z, pcx1 / z, pcy1 / z)
  self.view_at[id] = (dmax(x, cx0), dmax(y, cy0), dmin(x + w, cx1), dmin(y + h, cy1), shown)
}

///|
impl @hostapi.Host for FakeHost with view_close(self, id) {
  self.views.push("close \{id}")
  self.view_at.remove(id)
  self.scripts_waiting.remove(id)
  if self.touch_view == id {
    self.touch_view = 0
  }
}

///|
impl @hostapi.Host for FakeHost with view_control(self, id, op, value) {
  self.views.push("control \{id} \{op} \{value}")
}

///|
/// How a view stands (each read counted: Tester's); a page there now runs what was sent to it.
impl @hostapi.Host for FakeHost with view_info(self, id, out) {
  self.view_reads += 1
  let state = fake_view_info(self, id, out)
  fake_scripts_flush(self, id)
  state
}

///|
fn fake_view_info(f : FakeHost, id : Int, out : FixedArray[Double]) -> Int {
  match f.view_infos.get(id) {
    // as the run recorded the host's saying it (Tester::view_said)
    Some((state, at)) => {
      for i in 0..<10 {
        out[i] = at[i]
      }
      return state
    }
    None => ()
  }
  // a test that says when views are ready: not yet, until it does
  if !f.auto_finish && f.view_ready.get(id).unwrap_or(0) != 1 {
    for i in 0..<10 {
      out[i] = 0.0
    }
    return f.view_ready.get(id).unwrap_or(0)
  }
  match f.players.get(id) {
    Some(p) => {
      for i in 0..<10 {
        out[i] = p[i]
      }
      1
    }
    None => {
      out[0] = 10000.0
      out[1] = 0.0
      out[2] = 0.0
      out[3] = 640.0
      out[4] = 360.0
      out[5] = 0.0
      out[6] = 1.0
      out[7] = 0.0
      out[8] = 0.0
      out[9] = 0.0
      1
    }
  }
}

///|
/// What its sites say, the view's own first (Tester::view_says…), then the views' common queue (Tester::site_says).
impl @hostapi.Host for FakeHost with view_site_next(self, id) {
  let e = match self.site_of.get(id) {
    Some(q) if q.length() > 0 => q.remove(0)
    _ => if self.site.length() > 0 { self.site.remove(0) } else { "" }
  }
  // (a page that said something is there: what was sent to it runs)
  if e.has_prefix("{\"said\"") {
    self.page_there[id] = true
    fake_scripts_flush(self, id)
  }
  e
}

///|
/// What the app tells a view's host beyond its controls: each noted ("script 1 42 9a0b…", "touch 1 vertical 8",
/// "settings 1 …"), a page's scripts run as a host does: once its page is there (ready and not loading, or said
/// something since it started), in the order sent.
impl @hostapi.Host for FakeHost with view_tell(self, id, what, text) {
  if what == 1 {
    self.scripts_sent.push("\{id} \{text.length()} \{script_hash(text)}")
    match self.scripts_waiting.get(id) {
      Some(q) => q.push(text)
      None => self.scripts_waiting[id] = [text]
    }
    fake_scripts_flush(self, id)
  } else if what == 2 {
    let parts = text.split(" ").map(fn(p) { p.to_owned() }).to_array()
    let slop = match (try Some(@json.parse(parts.get(1).unwrap_or("0"))) catch { _ => None }) {
      Some(Number(n, ..)) => n
      _ => 0.0
    }
    self.view_touch[id] = (parts.get(0).unwrap_or("all"), slop)
    self.views.push("touch \{id} \{text}")
  } else if what == 4 {
    let rects : Array[Double] = []
    for p in text.split(" ") {
      match (try Some(@json.parse(p.to_owned())) catch { _ => None }) {
        Some(Number(n, ..)) => rects.push(n)
        _ => ()
      }
    }
    self.view_covers[id] = rects
  } else if what == 5 {
    self.views.push("raise \{id}")
  } else {
    self.views.push("settings \{id} \{text}")
  }
}

///|
/// Whether a fake page is there for scripts: said something since it started, or ready and not loading.
fn fake_page_there(f : FakeHost, id : Int) -> Bool {
  if f.page_there.get(id) is Some(true) {
    return true
  }
  let ready = match f.view_infos.get(id) {
    Some((state, _)) => state == 1
    None => f.auto_finish || f.view_ready.get(id).unwrap_or(0) == 1
  }
  let loading = match f.site_states.get(id) {
    Some(st) =>
      match (try Some(@json.parse(st)) catch { _ => None }) {
        Some(Object(m)) => m.get("loading") is Some(True)
        _ => false
      }
    None => false
  }
  ready && !loading
}

///|
/// A fake page's scripts that wait run, in the order sent, once it is there.
fn fake_scripts_flush(f : FakeHost, id : Int) -> Unit {
  match f.scripts_waiting.get(id) {
    Some(q) if q.length() > 0 && fake_page_there(f, id) => {
      let run = match f.scripts_run.get(id) {
        Some(r) => r
        None => {
          let r = []
          f.scripts_run[id] = r
          r
        }
      }
      for js in q {
        run.push(js)
        f.views.push("script \{id} \{js.length()} \{script_hash(js)}")
      }
      q.clear()
    }
    _ => ()
  }
}

///|
/// A request's body: as the run recorded it (Tester::view_said); else none.
impl @hostapi.Host for FakeHost with view_site_body(self, id, req) {
  self.site_bodies.get((id, req)).unwrap_or(Bytes::new(0))
}

///|
impl @hostapi.Host for FakeHost with view_site_head(self, id, req, status, headers) {
  self.views.push("site head \{id} \{req} \{status} \{headers}")
}

///|
impl @hostapi.Host for FakeHost with view_site_chunk(self, id, req, data) {
  self.views.push("site chunk \{id} \{req} \{data.length()}")
}

///|
impl @hostapi.Host for FakeHost with view_site_end(self, id, req, error) {
  self.views.push("site end \{id} \{req} \{error}")
}

///|
/// A site's page: as the run recorded the host's saying it (Tester::view_said); not said: at its start, loaded,
/// untitled.
impl @hostapi.Host for FakeHost with view_site_state(self, id) {
  let st = self.site_states.get(id).unwrap_or(
    "{\"path\":\"/\",\"back\":false,\"forward\":false,\"loading\":false,\"title\":\"\"}",
  )
  fake_scripts_flush(self, id)
  st
}

///|
/// What a view says: as the run recorded the host's saying it (Tester::view_said); not said yet: not known (a grab:
/// none asked). A grab said ready before its frame is said ("2", then the `still` line: a host says both in one frame,
/// a replay may give them a frame apart): still grabbing until the frame is here, not ready with none.
impl @hostapi.Host for FakeHost with view_text(self, id, what) {
  match self.view_texts.get((id, what)) {
    Some("2") if what == 2 && !(self.view_stills.get(id) is Some(q) && q.length() > 0) => Some("1")
    Some(t) => Some(t)
    None => if what == 2 { Some("0") } else { None }
  }
}

///|
/// The oldest frame grabbed, taken (the grab's state back to none asked, as a host's).
impl @hostapi.Host for FakeHost with view_still(self, id) {
  let b = match self.view_stills.get(id) {
    Some(q) if q.length() > 0 => q.remove(0)
    _ => b""
  }
  if self.view_texts.get((id, 2)) == Some("2") {
    self.view_texts[(id, 2)] = "0"
  }
  b
}

///|
impl @hostapi.Host for FakeHost with view_site_load(self, id, path) {
  self.views.push("site load \{id} \{path}")
}

///|
impl @hostapi.Host for FakeHost with view_read_next(self, id, out) {
  fake_read_next(self, id, out)
}

///|
impl @hostapi.Host for FakeHost with view_read_answer(self, id, req, data, total, more) {
  self.read_answers.push((id, req, data.length(), total, more))
}

// PDFs (native.mbt Pdf): the fake host's every PDF has 3 pages of 612 × 792 points; a page drawn is an image of that
// shape. Under a host's kept text (text_table), its answers as the host gave them.

///|
impl @hostapi.Host for FakeHost with pdf_open(self, data) {
  self.views.push("pdf \{data.length()}")
  let doc = 7 + self.pdfs.length()
  self.pdfs[doc] = (bytes_name(data), data.length())
  doc
}

///|
impl @hostapi.Host for FakeHost with pdf_pages(self, doc) {
  match self.pdfs.get(doc) {
    // as the host counted them, when kept with the text; else the fake's 3
    Some(named) if text_table.val is Some(_) =>
      match kept_answer("pn", pdf_head(named, [])) {
        Some(Number(n, ..)) => n.to_int()
        _ => 3
      }
    Some(_) => 3
    None => -1
  }
}

///|
impl @hostapi.Host for FakeHost with pdf_page_size(self, doc, page, out) {
  out[0] = 612.0
  out[1] = 792.0
  match self.pdfs.get(doc) {
    Some(named) if text_table.val is Some(_) =>
      match kept_answer("ps", pdf_head(named, [page])) {
        Some(Array([Number(w, ..), Number(h, ..), ..])) => {
          out[0] = w
          out[1] = h
        }
        _ => ()
      }
    _ => ()
  }
}

///|
impl @hostapi.Host for FakeHost with pdf_page_load(self, doc, page, max_px) {
  self.image_loads.push(("pdf:\{doc}/\{page}", max_px))
  match self.pdfs.get(doc) {
    Some(named) if text_table.val is Some(_) =>
      match kept_sizes(kept_answer("pi", pdf_head(named, [page, max_px]))) {
        Some((w, h, ow, oh)) => fake_image_sized(self, w, h, ow, oh)
        None => fake_image(self, 1224, 1584, max_px)
      }
    _ => fake_image(self, 1224, 1584, max_px)
  }
}

///|
impl @hostapi.Host for FakeHost with pdf_close(self, doc) {
  self.views.push("pdf close \{doc}")
}

///|
/// The pointer's shape as last told (desktop.mbt).
impl @hostapi.Host for FakeHost with set_cursor(self, kind) {
  self.cursor = kind
  self.cursors_told = self.cursors_told + 1
}

///|
/// The number on the app's icon, kept (Tester::badge).
impl @hostapi.Host for FakeHost with set_badge(self, n) {
  self.badge = n
}

///|
/// What the app's own native call `name` says, as the test set it (Tester::set_app_said); "" unset.
impl @hostapi.Host for FakeHost with app_said(self, name) {
  self.app_said.get(name).unwrap_or("")
}

///|
/// What the app told its own native calls, kept (Tester::app_told).
impl @hostapi.Host for FakeHost with app_tell(self, name, arg) {
  self.app_told.push((name, arg))
}

///|
/// The keys held down as the test says (Tester::hold_mods).
impl @hostapi.Host for FakeHost with mods_held(self) {
  self.mods
}

///|
/// The window dragged: counted.
impl @hostapi.Host for FakeHost with window_drag(self) {
  self.window_drags = self.window_drags + 1
}

///|
/// What the app asked of the window's own buttons, oldest first (Tester's).
impl @hostapi.Host for FakeHost with window_act(self, what) {
  self.window_acts.push(what)
}

///|
/// Whether the window is maximized (Tester::set_window_zoomed).
impl @hostapi.Host for FakeHost with window_zoomed(self) {
  self.zoomed
}

///|
/// Where the app last said its maximize button is (device pixels).
impl @hostapi.Host for FakeHost with window_snap(self, x, y, w, h) {
  self.snap = (x, y, w, h)
}

///|
/// How the pointer stands on the maximize button (Tester::set_window_snap).
impl @hostapi.Host for FakeHost with window_snap_state(self) {
  self.snap_state
}

///|
impl @hostapi.Host for FakeHost with window_opens(self) {
  self.window_opens
}

///|
/// Another window opened where it can (Tester::set_window_opens), kept.
impl @hostapi.Host for FakeHost with window_open(self, what) {
  if self.window_opens {
    self.windows_opened.push(what)
  }
  self.window_opens
}

///|
/// A window brought to the front where one opened for `what` is open still (Tester::close_window), kept.
impl @hostapi.Host for FakeHost with window_front(self, what) {
  let open = self.windows_opened.iter().filter(fn(w) { w == what }).count() >
    self.windows_closed.iter().filter(fn(w) { w == what }).count()
  if open {
    self.windows_fronted.push(what)
  }
  open
}

///|
/// What another app shared in (Tester::share_in), from the frame after it was told; taken once.
impl @hostapi.Host for FakeHost with shared_in(self) {
  match self.share {
    Some((said, frame)) if g().frame_no > frame => {
      self.share = None
      said
    }
    _ => ""
  }
}

///|
/// The i-th of the files shared in, taken once.
impl @hostapi.Host for FakeHost with shared_in_file(self, i) {
  if i >= 0 && i < self.share_files.length() {
    let b = self.share_files[i]
    self.share_files[i] = b""
    b
  } else {
    b""
  }
}

///|
/// What the app hands the share sheet: taken, kept for the test (Tester::shared_out).
impl @hostapi.Host for FakeHost with share(self, text, name, mime, data) {
  self.shares.push((text, name, mime, data))
  true
}

///|
/// Marks drawn onto an image: kept (Tester::marks_drawn), drawn by the frame after (or as the test says,
/// Tester::marks_by_hand); its PNG the test's (Tester::marks_make) or one clear pixel (its id, from 1: its place).
impl @hostapi.Host for FakeHost with mk_start(self, _, marks) {
  self.marks.push((marks, g().frame_no))
  self.marks_out.push(self.marks_next.unwrap_or(marked_png))
  self.marks_next = None
  self.wants = true
  self.marks.length()
}

///|
/// How drawing `id` goes: 0 drawing (until the frame after it was asked, or by hand: at once, the test's word told
/// as a host's event), 1 drawn, -1 none.
impl @hostapi.Host for FakeHost with mk_state(self, id) {
  match self.marks.get(id - 1) {
    Some((_, frame)) => if self.marks_by_hand || g().frame_no > frame { 1 } else { 0 }
    None => -1
  }
}

///|
impl @hostapi.Host for FakeHost with mk_png(self, id) {
  self.marks_out.get(id - 1).unwrap_or(b"")
}

///|
/// Its clock is its own (its frames').
impl @hostapi.Host for FakeHost with own_clock(_) {
  true
}

///|
impl @hostapi.Host for FakeHost with system_dark(self) {
  self.dark
}

///|
/// The system's size of words (Tester::set_font_scale).
impl @hostapi.Host for FakeHost with font_scale(self) {
  self.font_scale
}

///|
/// How far its local time is ahead of UTC (Tester::set_utc_offset), whatever the moment.
impl @hostapi.Host for FakeHost with utc_offset_min(self, _) {
  self.utc_offset
}

///|
/// What the person points with as it starts (Tester::new's `pointing`): 1 a finger, 0 a mouse; each event's word
/// after (@ui.pointing).
impl @hostapi.Host for FakeHost with pointing(self) {
  match self.pointing {
    Finger => 1
    Mouse => 0
  }
}

///|
/// What the app was started to be used with (Tester::new's `native`): 1 a finger, 2 a mouse.
impl @hostapi.Host for FakeHost with native_pointing(self) {
  match self.native {
    Finger => 1
    Mouse => 2
  }
}

///|
/// A keyboard at hand (Tester::new's `keyboard`, Tester::set_keyboard).
impl @hostapi.Host for FakeHost with keyboard(self) {
  if self.keyboard {
    1
  } else {
    0
  }
}

///|
impl @hostapi.Host for FakeHost with window_inset(self) {
  self.inset
}

///|
impl @hostapi.Host for FakeHost with full_screen(self) {
  self.full
}

///|
/// The window made to fill the screen or back: kept (@ui.full_screen).
impl @hostapi.Host for FakeHost with set_full_screen(self, on) {
  self.full = on
}

///|
/// The window's buttons moved lower: kept (Tester::window_buttons_down).
impl @hostapi.Host for FakeHost with window_buttons_down(self, by, ms) {
  self.buttons_down = (by, ms)
}

///|
/// How round the window's corners are (Tester::new's `window_corner`, the roundest of its `window_corners`): none
/// while it fills the screen.
impl @hostapi.Host for FakeHost with window_corner(self) {
  if self.full {
    0.0
  } else {
    match self.window_corners {
      Some(k) => k.fold(init=0.0, fn(m, r) { dmax(m, r) })
      None => self.window_corner
    }
  }
}

///|
/// Corner `k` (0 top left, then round it: Tester::new's `window_corners`, else its `window_corner`).
impl @hostapi.Host for FakeHost with window_corner_at(self, k) {
  if self.full {
    0.0
  } else {
    match self.window_corners {
      Some(c) => c[k & 3]
      None => self.window_corner
    }
  }
}

///|
/// Whether it lays out the app's tabs itself (Tester::set_nav_able).
impl @hostapi.Host for FakeHost with nv_able(self) {
  self.nav_able
}

///|
/// The bars handed it, kept (Tester::nav_said): shown where it lays them out.
impl @hostapi.Host for FakeHost with nv_bar(self, spec) {
  self.nav_said = spec
  if self.nav_able {
    1
  } else {
    0
  }
}

///|
/// Its environment (Tester::new's `env`, Tester::set_env).
impl @hostapi.Host for FakeHost with env(self, name) {
  self.env.get(name).unwrap_or("")
}

///|
impl @hostapi.Host for FakeHost with app_version(self) {
  self.app_version
}
///|
/// A secret on the clipboard: kept as any words (Tester::clipboard), said to be a secret (Tester::clipboard_secret).
impl @hostapi.Host for FakeHost with clipboard_set_secret(self, s, clear_ms) {
  self.clipboard = s
  self.clipboard_secret = clear_ms
}

///|
/// The last secret taken off while it is there still (Tester::clipboard empty again, Tester::clipboard_secret None).
impl @hostapi.Host for FakeHost with clipboard_secret_off(self) {
  if self.clipboard_secret >= 0.0 {
    self.clipboard = ""
    self.clipboard_secret = -1.0
  }
}

///|
/// A picture on the clipboard: how long it was kept (Tester::clipboard_image).
impl @hostapi.Host for FakeHost with clipboard_set_image(self, data) {
  self.clipboard_image = data.length()
}

///|
/// A frame presented: its instances counted, what a host that keeps its picture is handed kept for a test that
/// records it (tester_host.mbt).
/// Drawn out where a header stands for a group it keeps, as a host draws them (Ctx::flat_from): what a test reads of
/// the frame reads the instances drawn. Those are the frame's, every one: what a host is handed leaves out what
/// cannot be seen (h_present, @damage's Damage::occlude), which draws the same.
impl @hostapi.Host for FakeHost with present(self, _, _, _, _, _) {
  let c = g()
  c.flat_from(0)
  self.instances = c.ninst
  host_presented_now(c.inst, c.ninst)
  // (what of it was drawn not as laid out, as it is presented: held at the frame's end, tester_placed.mbt)
  placed_at_present()
  // (what the window's tree keeps against what working it out whole gives, as it is presented: held at the frame's
  // end, tester.mbt)
  kept_at_present()
}

///|
/// The app over another app done, kept (Tester::overs_done).
impl @hostapi.Host for FakeHost with over_done(self, open_app) {
  self.overs_done.push(open_app)
}

///|
/// What the notice holding the app up says, kept (Tester::hold_words).
impl @hostapi.Host for FakeHost with hold_words(self, channel, title, body) {
  self.hold_words = Some((channel, title, body))
}

///|
/// The legacy encodings it decodes (@hostapi.decode_charset): GB18030 and the two it holds (fake_gb18030.mbt); the
/// system's others are a host's own (its contract's).
fn fake_charset(charset : String) -> Bool {
  let c = charset.to_upper()
  c == "GB18030" || c == "GBK" || c == "GB2312"
}

///|
impl @hostapi.Host for FakeHost with cs_known(_, charset) {
  if fake_charset(charset) {
    1
  } else {
    0
  }
}

///|
impl @hostapi.Host for FakeHost with cs_decode(_, data, charset) {
  if fake_charset(charset) {
    gb18030_decode(data)
  } else {
    ""
  }
}

///|
/// (a Tester's gallery, Tester::gallery: all of it; none given, as a host the app may read none of: 0)
impl @hostapi.Host for FakeHost with ga_access(self) {
  if self.gallery is Some(_) {
    1
  } else {
    0
  }
}

///|
impl @hostapi.Host for FakeHost with ga_read(self) {
  self.gallery_read()
}

///|
impl @hostapi.Host for FakeHost with ga_read_state(self, a0) {
  self.gallery_read_state(a0)
}

///|
impl @hostapi.Host for FakeHost with ga_read_rows(self, a0) {
  self.gallery_read_rows(a0)
}

///|
impl @hostapi.Host for FakeHost with ga_read_end(self, a0) {
  self.gallery_read_end(a0)
}

// This device's password manager (@hostapi passwords.mbt) as a test has it: none, unless it says how `op` answers
// (`fake_op`: its exit code, output and error output for the arguments given), each run ended at once.

///|
/// How `op` answers a test, given its arguments: None, no password manager here.
pub let fake_op : Ref[((Array[String]) -> (Int, String, String))?] = Ref(None)

///|
/// The runs of `op` asked for in a test, by their id (from 1): their arguments.
pub let fake_op_runs : Array[Array[String]] = []

///|
impl @hostapi.Host for FakeHost with pw_able(_) {
  fake_op.val is Some(_)
}

///|
impl @hostapi.Host for FakeHost with pw_run(_, args) {
  guard fake_op.val is Some(_) else { return 0 }
  let given = args.split("\u{1f}").map(fn(a) { a.to_owned() }).to_array()
  // (each argument ended by the separator: the last piece is none)
  ignore(given.pop())
  fake_op_runs.push(given)
  fake_op_runs.length()
}

///|
/// Whether the runs of `op` are still under way in a test (none has ended: 1Password slow to answer).
pub let fake_op_pending : Ref[Bool] = Ref(false)

///|
impl @hostapi.Host for FakeHost with pw_out(_, id) {
  guard fake_op.val is Some(answer) && id >= 1 && id <= fake_op_runs.length() && !fake_op_pending.val else { return "" }
  let (code, out, err) = answer(fake_op_runs[id - 1])
  "\{code}\u{1f}\{out}\u{1f}\{err}\u{1f}"
}

///|
impl @hostapi.Host for FakeHost with pw_end(_, _) {
  ()
}

// The system's autofill (@hostapi autofill.mbt) as a test has it: none, unless it says there is a service
// (`fake_autofill`); the sites asked for kept, the login the person picked there given by `fake_autofill_picks`.

///|
/// Whether a test's host has an autofill service.
pub let fake_autofill : Ref[Bool] = Ref(false)

///|
/// The sites the autofill service was asked for in a test, in order; "" where the ask was let go of.
pub let fake_autofill_asks : Array[String] = []

///|
let fake_autofill_picked : Ref[String] = Ref("")

///|
/// The person picks a login in the autofill service's offer: its site's host, account and password, taken once.
pub fn fake_autofill_picks(host : String, username : String, password : String) -> Unit {
  fake_autofill_picked.val = "\{host}\u{1f}\{username}\u{1f}\{password}\u{1f}"
}

///|
impl @hostapi.Host for FakeHost with af_able(_) {
  fake_autofill.val
}

///|
impl @hostapi.Host for FakeHost with af_ask(_, host) {
  guard fake_autofill.val else { return 0 }
  fake_autofill_asks.push(host)
  1
}

///|
impl @hostapi.Host for FakeHost with af_take(_) {
  let p = fake_autofill_picked.val
  fake_autofill_picked.val = ""
  p
}

///|
impl @hostapi.Host for FakeHost with af_end(_) {
  fake_autofill_picked.val = ""
  fake_autofill_asks.push("")
}

// This device's passkeys (@hostapi passkeys.mbt) as a test has them: none, unless it says how the device answers
// (`fake_passkey`: given the relying party, the client data, the verification and the ids asked, the host's answer as
// it gives it), each ask ended at once.

///|
/// How the device answers a test's ask for a passkey: None, no passkeys here.
pub let fake_passkey : Ref[((String, String, String, String) -> String)?] = Ref(None)

///|
/// The asks for a passkey in a test, by their id (from 1): the relying party, the client data, the verification, the
/// ids asked (hex, joined by commas).
pub let fake_passkey_asks : Array[(String, String, String, String)] = []

///|
impl @hostapi.Host for FakeHost with wa_able(_) {
  fake_passkey.val is Some(_)
}

///|
impl @hostapi.Host for FakeHost with wa_get(_, ask) {
  guard fake_passkey.val is Some(_) else { return 0 }
  let p = ask.split("\u{1f}").map(fn(a) { a.to_owned() }).to_array()
  fake_passkey_asks.push((p.get(0).unwrap_or(""), p.get(1).unwrap_or(""), p.get(2).unwrap_or(""), p.get(3).unwrap_or("")))
  fake_passkey_asks.length()
}

///|
impl @hostapi.Host for FakeHost with wa_out(_, id) {
  guard fake_passkey.val is Some(answer) && id >= 1 && id <= fake_passkey_asks.length() else { return "" }
  let (rp, client, uv, ids) = fake_passkey_asks[id - 1]
  answer(rp, client, uv, ids)
}

///|
impl @hostapi.Host for FakeHost with wa_end(_, _) {
  ()
}

// The device beyond the window (@hostapi device.mbt; @ui's device.mbt) as a test has it (FakeDevice): what it was told
// kept, the clipboard read as the test gives it (Tester::clipboard_gives…), from the frame after.

///|
/// A haptic fired, kept (Tester::haptics).
impl @hostapi.Host for FakeHost with dv_haptic(self, kind) {
  let all : Array[Haptic] = [LongPress, ContextClick, TextHandleMove, Confirm, Reject, KeyboardTap]
  for h in all {
    if h.code() == kind {
      self.dev.haptics.push(h)
      return
    }
  }
}

///|
/// The screen kept awake as last told (Tester::awake).
impl @hostapi.Host for FakeHost with dv_keep_awake(self, on) {
  self.dev.awake = on != 0
}

///|
/// Whether the system says a copy itself (Tester::new's `copy_shown`).
impl @hostapi.Host for FakeHost with dv_copy_shown(self) {
  if self.dev.copy_shown {
    1
  } else {
    0
  }
}

///|
impl @hostapi.Host for FakeHost with dv_key_catch(self, on) {
  self.dev.key_catch = on != 0
}

///|
/// The soft keyboard's height as the test says it.
impl @hostapi.Host for FakeHost with dv_ime_inset(self) {
  self.dev.ime_inset
}

///|
impl @hostapi.Host for FakeHost with dv_ime_action(self, kind) {
  self.dev.ime_action = kind
}

///|
/// Words or a picture put on the clipboard (@hostapi.clip_set_text, clip_set_png), held with their label
/// (Tester::clipboard, clipboard_png, clipboard_label).
impl @hostapi.Host for FakeHost with cl_set(self, text, png, label) {
  if png.length() > 0 {
    self.clipboard = ""
    self.dev.clip_png = Some(png)
  } else {
    self.clipboard = text
    self.dev.clip_png = None
  }
  self.dev.clip_label = label
}

///|
/// A read of the clipboard asked (its id, from 1: the ask's place): answered by what the test gave before it, if it
/// did, else by what it gives next.
impl @hostapi.Host for FakeHost with cl_read(self) {
  let ask : FakeClipRead = { answer: None }
  if self.dev.held.length() > 0 {
    ask.answer = Some((self.dev.held.remove(0), g().frame_no))
    self.wants = true
  }
  self.dev.reads.push(ask)
  self.dev.reads.length()
}

///|
/// What read `id` was answered with, from the frame after it was given.
fn FakeHost::clip_given(self : FakeHost, id : Int) -> Clipboard? {
  guard self.dev.reads.get(id - 1) is Some(r) else { return None }
  match r.answer {
    Some((c, at)) if g().frame_no > at => Some(c)
    _ => None
  }
}

///|
/// How read `id` goes: 0 reading (until the test's answer is a frame old), 1 read.
impl @hostapi.Host for FakeHost with cl_state(self, id) {
  if self.clip_given(id) is Some(_) {
    1
  } else {
    0
  }
}

///|
impl @hostapi.Host for FakeHost with cl_text(self, id) {
  match self.clip_given(id) {
    Some(c) => c.text
    None => ""
  }
}

///|
impl @hostapi.Host for FakeHost with cl_picture(self, id) {
  match self.clip_given(id) {
    Some({ picture: Png(_), .. }) => @hostapi.clip_png
    Some({ picture: TooLarge, .. }) => @hostapi.clip_too_large
    Some({ picture: Unreadable, .. }) => @hostapi.clip_unreadable
    _ => @hostapi.clip_none
  }
}

///|
impl @hostapi.Host for FakeHost with cl_png(self, id) {
  match self.clip_given(id) {
    Some({ picture: Png(b), .. }) => b
    _ => Bytes::new(0)
  }
}

///|
impl @hostapi.Host for FakeHost with cl_files(self, id) {
  match self.clip_given(id) {
    Some(c) => c.files.length()
    None => 0
  }
}

///|
impl @hostapi.Host for FakeHost with cl_file_name(self, id, i) {
  match self.clip_given(id) {
    Some(c) if i >= 0 && i < c.files.length() => c.files[i].0
    _ => ""
  }
}

///|
impl @hostapi.Host for FakeHost with cl_file(self, id, i) {
  match self.clip_given(id) {
    Some(c) if i >= 0 && i < c.files.length() => c.files[i].1
    _ => Bytes::new(0)
  }
}

// The system's notifications (@hostapi notify.mbt) as a test has them: those shown kept (Tester::notices), one tapped
// as the test says (Tester::tap_notice), what the system lets the app show and what the person answers when asked
// (Tester::set_notice_permission, set_notice_reply).

///|
/// A notification shown: kept, one of the same tag replaced.
impl @hostapi.Host for FakeHost with nt_show(self, channel, tag, title, body, opens) {
  let kept = self.notices.filter(fn(n) { tag == "" || n.tag != tag })
  self.notices.clear()
  self.notices.append(kept)
  self.notices.push({ channel, tag, title, body, opens })
}

///|
impl @hostapi.Host for FakeHost with nt_cancel(self, tag) {
  let kept = self.notices.filter(fn(n) { n.tag != tag })
  self.notices.clear()
  self.notices.append(kept)
}

///|
/// 0: what it lets the app show (1 granted, 2 denied, 3 ask, 0 unknown); 1: asked to let it (where it is not granted or
/// unknown: the person's answer due, as the test said); 2: the answer, as a frame begins (never between frames: the
/// person answers as the frame after the ask begins); 3: its settings opened, counted; 4: whether it shows the number on
/// the app's icon, as the system it plays does.
impl @hostapi.Host for FakeHost with nt_state(self, what) {
  match what {
    0 =>
      match self.notice_perm {
        "granted" => 1
        "denied" => 2
        "ask" => 3
        _ => 0
      }
    1 => {
      if self.notice_perm == "granted" || self.notice_perm == "unknown" {
        return 0
      }
      self.notice_asks += 1
      self.notice_due = match self.notice_reply {
        Some(yes) => Some((yes, g().frame_no))
        None => None
      }
      self.wants = true
      1
    }
    2 =>
      match self.notice_due {
        Some((yes, _)) if frame_running.val => {
          self.notice_due = None
          self.notice_perm = if yes { "granted" } else { "denied" }
          if yes {
            1
          } else {
            0
          }
        }
        _ => -1
      }
    3 => {
      self.notice_settings += 1
      1
    }
    4 => if platform_badge(self.platform) { 1 } else { 0 }
    _ => 0
  }
}

///|
/// 0: the notification tapped (what it opens), once.
impl @hostapi.Host for FakeHost with nt_text(self, what) {
  if what != 0 {
    return ""
  }
  let o = self.notice_opened
  self.notice_opened = ""
  o
}

// Streams (@hostapi stream.mbt; @ui's stream.mbt) as a test has them: what each was handed, a line each
// (Tester::stream_fed), and its events as the test or a run says them (Tester::stream_shows…, view_said).

///|
fn fake_fed(f : FakeHost, id : Int, line : String) -> Unit {
  match f.streams_fed.get(id) {
    Some(a) => a.push(line)
    None => f.streams_fed[id] = [line]
  }
}

///|
impl @hostapi.Host for FakeHost with st_open(self) {
  self.stream_ids += 1
  self.streams_fed[self.stream_ids] = []
  self.stream_said[self.stream_ids] = []
  self.stream_ids
}

///|
impl @hostapi.Host for FakeHost with st_h264(self, id, avcc, w, h) {
  fake_fed(self, id, "h264 \{w}x\{h} avcc=\{avcc.length()}")
}

///|
impl @hostapi.Host for FakeHost with st_hevc(self, id, hvcc, w, h) {
  fake_fed(self, id, "hevc \{w}x\{h} hvcc=\{hvcc.length()}")
}

///|
impl @hostapi.Host for FakeHost with st_av1(self, id, av1c, w, h) {
  fake_fed(self, id, "av1 \{w}x\{h} av1c=\{av1c.length()}")
}

///|
impl @hostapi.Host for FakeHost with st_frame(self, id, data, key, ts) {
  fake_fed(self, id, "frame key=\{key != 0} ts=\{ts} bytes=\{data.length()}")
}

///|
/// A frame not to be shown: "frame … hidden", taken (as Windows' host does), unless the test said its host has nothing
/// for one (Tester::set_stream_hides false: one shown as st_frame's, the other not taken).
impl @hostapi.Host for FakeHost with st_frame_shown(self, id, data, key, ts, show) {
  if show != 0 {
    fake_fed(self, id, "frame key=\{key != 0} ts=\{ts} bytes=\{data.length()}")
    1
  } else if self.stream_hides {
    fake_fed(self, id, "frame key=\{key != 0} ts=\{ts} bytes=\{data.length()} hidden")
    1
  } else {
    0
  }
}

///|
impl @hostapi.Host for FakeHost with st_flush(self, id, drain) {
  fake_fed(self, id, "flush drain=\{drain != 0}")
}

///|
impl @hostapi.Host for FakeHost with st_audio_played(self, id) {
  match self.stream_audio_clock.get(id) {
    Some((played, _)) => played
    None => 0.0
  }
}

///|
impl @hostapi.Host for FakeHost with st_audio_queued(self, id) {
  match self.stream_audio_clock.get(id) {
    Some((_, queued)) => queued
    None => 0.0
  }
}

///|
impl @hostapi.Host for FakeHost with st_audio_volume(self, id, v) {
  fake_fed(self, id, "volume \{v}")
}

///|
impl @hostapi.Host for FakeHost with st_jpeg(self, id, data, ts) {
  fake_fed(self, id, "jpeg ts=\{ts} bytes=\{data.length()}")
}

///|
impl @hostapi.Host for FakeHost with st_show(self, id, ts) {
  fake_fed(self, id, "show ts=\{ts}")
}

///|
impl @hostapi.Host for FakeHost with st_codec(self, id, cmd, data) {
  fake_fed(self, id, if data.length() > 0 { "do \{cmd} bytes=\{data.length()}" } else { "do \{cmd}" })
}

///|
impl @hostapi.Host for FakeHost with st_close(self, id) {
  fake_fed(self, id, "close")
}

///|
/// A route's frames (@hostapi.stream_direct: `flags` 1 video, 2 audio; none, the route let go of: 0).
impl @hostapi.Host for FakeHost with st_direct(self, id, route, after, flags) {
  let video = (flags & 1) != 0
  let audio = (flags & 2) != 0
  let r = if video || audio { route.to_int() } else { 0 }
  fake_fed(self, id, "route \{r} after=\{after} video=\{video} audio=\{audio}")
}

///|
impl @hostapi.Host for FakeHost with st_audio(self, id, data) {
  fake_fed(self, id, "audio bytes=\{data.length()}")
}

///|
/// The pointer's picture said by the name the app gives it, its size and hot spot in points.
impl @hostapi.Host for FakeHost with st_pointer_named(self, id, key, _, w, h, hx, hy) {
  let z = window_zoom_drawn.val
  fake_fed(self, id, "pointer \{key} \{w / z}x\{h / z} hot=\{hx / z},\{hy / z}")
}

///|
impl @hostapi.Host for FakeHost with st_pointer_at(self, id, x, y, shown) {
  fake_fed(self, id, if shown != 0 { "pointer at \{x} \{y}" } else { "pointer none" })
}

///|
/// Stream `id`'s next event, as the test or the run said it.
impl @hostapi.Host for FakeHost with st_next(self, id) {
  match self.stream_said.get(id) {
    Some(q) if q.length() > 0 => q.remove(0)
    _ => ""
  }
}

///|
/// Whether it decodes H.264 (Tester::new's `h264`).
impl @hostapi.Host for FakeHost with st_h264_here(self) {
  if self.h264 {
    1
  } else {
    0
  }
}

///|
/// Whether it decodes H.265 (Tester::set_h265).
impl @hostapi.Host for FakeHost with st_h265_here(self) {
  if self.h265_here {
    1
  } else {
    0
  }
}

///|
/// Whether it decodes AV1 (Tester::set_av1).
impl @hostapi.Host for FakeHost with st_av1_here(self) {
  if self.av1_here {
    1
  } else {
    0
  }
}

///|
/// Whether its H.264 decoder is driven from the app (Tester::set_stream_feeds).
impl @hostapi.Host for FakeHost with st_feeds(self) {
  if self.stream_feeds {
    1
  } else {
    0
  }
}

///|
/// Its streams' system video layers (Tester::set_stream_layers): 0 none, 1 in a stream's tagged colours, 2 in sRGB
/// (Tester::set_stream_layers_srgb).
impl @hostapi.Host for FakeHost with st_layers(self) {
  if !self.stream_layers {
    0
  } else if self.stream_layers_srgb {
    2
  } else {
    1
  }
}

///|
/// Whether it plays a remote screen's audio (Tester::set_stream_audio).
impl @hostapi.Host for FakeHost with st_audio_here(self) {
  if self.audio_here {
    1
  } else {
    0
  }
}

///|
/// As a frame begins: its pages run what was sent to them once they are there.
fn Tester::fake_pages_run(self : Tester) -> Unit {
  for v in open_views {
    fake_scripts_flush(self.fake, v.id)
  }
}

///|
/// What was posted to it (fake_post) since a frame took the last: how many, taken one by one (post_next).
impl @hostapi.Host for FakeHost with post_take(_) {
  fake_posted.length()
}

///|
impl @hostapi.Host for FakeHost with post_next(_) {
  if fake_posted.is_empty() {
    return None
  }
  let (channel, json, b) = fake_posted.remove(0)
  Some((channel, json, b.unwrap_or(Bytes::new(0))))
}

// The app's own calls of its host (@hostapi native.mbt; @ui's native_call.mbt) as a test has them: each waits until
// the test answers it (Tester::answer_native, refuse_native), or answered as it is asked (Tester::native_answers) or by
// an answer given before it (held: a replay's NATIVESAID), each told at that moment as a host's event tells it
// (FakeHost::due: after the event that asked or answered, before the clock moves on).

///|
/// A call asked (its id, from 1: its place).
impl @hostapi.Host for FakeHost with ncall_call(self, name, params) {
  let params = @json.parse(params) catch { _ => Json::string(params) }
  let ask : FakeNative = { name, params, answer: None, said: false }
  let mut held = -1
  for i, h in self.dev.native_held {
    if h.0 == name {
      held = i
      break
    }
  }
  if held >= 0 {
    ask.answer = Some(self.dev.native_held.remove(held).1)
  } else {
    match self.dev.native_auto.get(name) {
      Some(answer) => ask.answer = Some(answer(params))
      None => ()
    }
  }
  self.dev.natives.push(ask)
  let id = self.dev.natives.length()
  if ask.answer is Some(_) {
    fake_native_due(self, id)
  }
  id
}

///|
/// Call `id`'s answer, once its host's event told it (fake_native_due).
fn FakeHost::native_given(self : FakeHost, id : Int) -> Result[Json, String]? {
  guard self.dev.natives.get(id - 1) is Some(a) && a.said else { return None }
  a.answer
}

///|
/// How call `id` goes: 0 waiting, 1 answered, 2 refused.
impl @hostapi.Host for FakeHost with ncall_state(self, id) {
  match self.native_given(id) {
    Some(Ok(_)) => 1
    Some(Err(_)) => 2
    None => 0
  }
}

///|
/// Its answer's JSON, or why it was refused.
impl @hostapi.Host for FakeHost with ncall_result(self, id) {
  match self.native_given(id) {
    Some(Ok(j)) => j.stringify()
    Some(Err(why)) => why
    None => ""
  }
}

///|
/// Its answers come by the frame after they were asked or given (Tester::finish where the test says when), told by
/// no event; but what was picked and a native call's answer, told at their moment as a host's event tells them
/// (fake_pick_said, fake_native_due), and the marks' drawings where the test answers them by hand
/// (Tester::marks_by_hand), told so (Tester::marks_answer).
impl @hostapi.Host for FakeHost with answers_by_frame(self, kind) {
  kind != outside_pick &&
  kind != outside_native &&
  !(kind == outside_marks && self.marks_by_hand)
}

///|
/// What it answers at a moment is told as a host's event (on_outside); the rest by the frame (answers_by_frame).
impl @hostapi.Host for FakeHost with set_outside(_, _) {
  true
}

///|
/// A test's finger (kinds as on_pointer's: 0 down, 1 moved, 2 up, 3 called off; 4, 5, 6 a second finger; 8 the first
/// let go, the second the first from here), taken as a host takes it where a page's view is.
fn finger(kind : Int, x : Double, y : Double) -> Unit {
  // (what was posted before this input told first, at its moment: posted_tell)
  posted_tell()
  let f = match fake.val {
    Some(f) => f
    None => return on_pointer(kind, x, y, 0)
  }
  if kind == 0 {
    let (id, mode, _) = fake_view_under(f, x, y)
    if id > 0 && mode != "through" {
      f.touch_view = id
      f.touch_down = (x, y)
      f.touch_at = (x, y)
      f.touch_sideways = false
      f.views.push("finger \{id} down \{x} \{y}")
      return
    }
    f.touch_view = 0
    return on_pointer(kind, x, y, 0)
  }
  let id = f.touch_view
  if id == 0 {
    return on_pointer(kind, x, y, 0)
  }
  let (mode, slop) = f.view_touch.get(id).unwrap_or(("all", 0.0))
  let (dx0, dy0) = f.touch_down
  let taken = match kind {
    1 =>
      mode == "vertical" &&
      !f.touch_sideways &&
      (y - dy0).abs() > slop &&
      (y - dy0).abs() > (x - dx0).abs()
    4 => mode == "pinch"
    _ => false
  }
  if taken {
    // the page's no more: called off there, the canvas's from where it went down (a pinch's first finger then where it
    // is now, before the second comes down)
    f.views.push("finger \{id} cancel")
    f.touch_view = 0
    on_pointer(0, dx0, dy0, 0)
    if kind == 4 {
      on_pointer(1, f.touch_at.0, f.touch_at.1, 0)
    }
    on_pointer(kind, x, y, 0)
    return
  }
  if kind == 1 {
    f.touch_at = (x, y)
    // sideways first: the page's to the end of the touch
    if mode == "vertical" && (x - dx0).abs() > slop {
      f.touch_sideways = true
    }
  }
  let name = match kind {
    1 => "move"
    2 => "up"
    3 => "cancel"
    4 => "second down"
    5 => "second move"
    _ => "second up"
  }
  f.views.push("finger \{id} \{name} \{x} \{y}")
  if kind == 2 || kind == 3 {
    f.touch_view = 0
  }
}

///|
/// A test's wheel, taken as a host takes it over a page's view: the page's (All, PinchOut), the canvas's (Through,
/// VerticalOut: its upright scroll).
fn finger_wheel(x : Double, y : Double, dx : Double, dy : Double, phase : Int) -> Unit {
  match fake.val {
    Some(f) => {
      let (id, mode, _) = fake_view_under(f, x, y)
      if id > 0 && (mode == "all" || mode == "pinch") {
        f.views.push("wheel \{id} \{dx} \{dy}")
        return
      }
    }
    None => ()
  }
  posted_tell()
  on_wheel(x, y, dx, dy, phase)
}

///|
/// What a script tells its system, its native views' host, its keyboard and its pickers, done as told (drive.mbt).
impl @hostapi.Host for FakeHost with script_step(self, step, arg) {
  match step {
    "system" => {
      fake_post(self, @hostapi.system_channel, arg, None)
      ""
    }
    "viewsaid" => {
      // (what the host says of its native views comes from outside: frame_watch.mbt)
      outside_counted()
      if fake_view_said(self, arg) {
        ""
      } else {
        "viewsaid: not a line of what a native view's host says: " + arg
      }
    }
    "ime" => {
      self.dev.ime_inset = number(arg)
      self.wants = true
      ""
    }
    "picks" => {
      self.picks.clear()
      for part in arg.split(" ") {
        match part.rev_find(":") {
          Some(i) => {
            let mut n = 0
            for ch in part[i + 1:] {
              n = n * 10 + (ch.to_int() - 48)
            }
            let bytes = Bytes::make(n, b'x')
            self.picks.push({ name: part[:i].to_owned(), bytes, held: 0, size: n.to_double(), src: "" })
          }
          None => ()
        }
      }
      ""
    }
    _ => "\{step}: the Tester's host takes no such step of a script"
  }
}

///|
/// It keeps groups of instances, as every platform's host does: drawn out as it is handed them (present); none where
/// the test says so (Tester::set_groups), as the web's host.
impl @hostapi.Host for FakeHost with groups_here(self) {
  self.groups
}

///|
/// A list's rows set on its pixels as every platform's host sets them, where the test says so
/// (Tester::set_rows_on_pixels).
impl @hostapi.Host for FakeHost with rows_on_pixels(self) {
  self.rows_on_pixels
}

///|
/// The window's tree keeps where in the source each node was made, for what a test finds to say where to change it
/// (view's source.mbt), unless the test runs it as a device does (Tester::new's `keeps_sources`).
impl @hostapi.Host for FakeHost with keeps_sources(self) {
  self.keeps_sources
}

///|
/// Over a host's kept text, as that host said of its fonts (any of them), asked of nothing new; else not.
impl @hostapi.Host for FakeHost with lines_on_pixels(_) {
  match text_table.val {
    Some(t) => t.metrics.values().any(fn(r) { r.length() > 5 && r[5] == 1.0 })
    None => false
  }
}

///|
/// What the fake host was posted and has not told yet, told now, between frames: before its clock moves on (a frame
/// drawn later, the clock advanced) and before an input it is given, so at the moment it was posted, as a device's host
/// tells it as it is posted (MB_OUTSIDE_POSTED), not as the next frame begins. What is posted at one moment is told as
/// one, in the order posted, as a device's host takes all that came by the time it is told (messages_between).
fn posted_tell() -> Unit {
  if in_frame.val || frame_running.val {
    return
  }
  if fake_posted.length() > 0 {
    on_outside(outside_posted, 0, 0)
  }
  // (and what the fake host does at a moment of its own come by now: FakeHost::due, each as one event, in its order)
  let now = match fake.val {
    Some(f) => f.time
    None => return
  }
  while fake_dues.length() > 0 && fake_dues[0].0 <= now + 1.0e-9 {
    let (_, _, _, f) = fake_dues.remove(0)
    f()
    if fake_posted.length() > 0 {
      on_outside(outside_posted, 0, 0)
    }
  }
}

///|
/// A frame of the fake host's ended: what it is to do by now (FakeHost::due: asked of it as the frame was made, at the
/// frame's moment) done now, between frames, before anything else comes, and what was posted with it (posted_tell),
/// as a device's host answers after the frame that asked. Nothing of the frame's posted else is told here: that waits,
/// as ever, for the clock to move or an input.
fn fake_dues_after_frame(f : FakeHost) -> Unit {
  if fake_dues.length() > 0 && fake_dues[0].0 <= f.time + 1.0e-9 {
    posted_tell()
  }
}

///|
/// What the fake host is to do at moments of its clock (FakeHost::due): when, in what order said, what (named for what
/// says it), done.
// kept across runs: emptied by each Tester (Tester::new)
let fake_dues : Array[(Double, Int, String, () -> Unit)] = []

///|
// kept across runs: only counted on
let fake_due_count : Ref[Int] = Ref(0)

///|
/// `f` done by the fake host at `at` on its clock, between frames, as an event from outside that comes then (a picked
/// file, a native call's answer, an operation done, as a device's host tells each at its moment): at the moment the
/// clock comes to it, however it is run on (run_for and come_to stop there at any rate of frames), after what is
/// going on now where `at` is now; several at one moment in the order said. `what` names it where it is said.
pub fn FakeHost::due(self : FakeHost, at : Double, what : String, f : () -> Unit) -> Unit {
  ignore(self)
  fake_due_count.val += 1
  let entry = (at, fake_due_count.val, what, f)
  let mut i = fake_dues.length()
  while i > 0 && (fake_dues[i - 1].0 > at || (fake_dues[i - 1].0 == at && fake_dues[i - 1].1 > entry.1)) {
    i -= 1
  }
  fake_dues.insert(i, entry)
}

///|
/// The fake host's next moment of its own (FakeHost::due) after `now`, +inf none.
fn fake_due_next(now : Double) -> Double {
  for d in fake_dues {
    if d.0 > now {
      return d.0
    }
  }
  @double.infinity
}

///|
/// The fake host's clock on to each of its moments (FakeHost::due) up to `t`, what is due at each done there, before the
/// clock goes on.
fn fake_dues_to(f : FakeHost, t : Double) -> Unit {
  while !in_frame.val && !frame_running.val && fake_dues.length() > 0 && fake_dues[0].0 <= t + 1.0e-9 {
    if fake_dues[0].0 > f.time {
      f.time = fake_dues[0].0
    }
    posted_tell()
  }
}
