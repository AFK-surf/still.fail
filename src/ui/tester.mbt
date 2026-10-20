// Tests drive a view without a window: a fake host with fixed text metrics,
// a clock the test advances, input sent the way a host sends it, and a text
// dump of the laid-out tree to compare against.

///|
pub struct Tester {
  fake : FakeHost
  mut w : Double
  mut h : Double
  mut frames : Int
  /// the seed it was made with (Tester::finish_all's order)
  seed : Int?
  /// its display's frames: one only ever at `origin` and a whole number of `period`s after it, as a host draws only
  /// at its display's vsync (Tester::set_frame_period)
  mut origin : Double
  mut period : Double
  /// the display's frames to come, as a run's tape had them (Tester::set_frame_times): after the last, on its period
  mut times : Array[Double]
}

///|
/// A display's frame period, the Tester's own unless told another (Tester::set_frame_period): a 60 Hz display's.
pub let frame_period_default : Double = 1000.0 / 60.0

///|
/// What a test leaves behind forgotten before the next starts: the window's context made anew (every field of it as a
/// window's first frame has it, by construction), and the state kept outside it (the package's own tables, those of
/// the packages over it: on_reset) emptied; then checked (leaked_state), so that what is added later and not
/// forgotten here fails the next Tester at once rather than a test somewhere else.
fn reset_globals() -> Unit {
  the_ctx.val = Ctx::new()
  desk_reset()
  tester_size.val = None
  env_kept.val = ""
  app_state.val = 3
  driver.val = None
  track_x.reset()
  track_y.reset()
  reset_glass()
  clear_shapes()
  text_cache.fonts.clear()
  text_cache.metrics.clear()
  text_cache.glyphs.clear()
  text_cache.generation = -1
  text_table.val = None
  inputs_since.val = false
  in_frame.val = false
  building.val = false
  messages_reset()
  image_cache.clear()
  views_told_text.clear()
  views_told_info.clear()
  sites_told_state.clear()
  outside_tickets.clear()
  views_told.clear()
  pagers.clear()
  code_fields.clear()
  code_clears.clear()
  image_data.clear()
  open_views.clear()
  streams_reset()
  native_nodes.clear()
  picture_at.clear()
  wheels.clear()
  captures.clear()
  drags.clear()
  sideways.clear()
  words_marks.clear()
  words_kept.clear()
  words_sel.clear()
  list_counts.clear()
  second_ptr[2] = 0.0
  bench.mode = 0
  g_view.val = fn(_c) { () }
  app_change.val = None
  reduce_env.val = -1
  draw_log.val = -1
  draw_frames.val = 0
  fx_reset(None)
  outside_told.val = false
  commit_counts[0] = 0
  commit_counts[1] = 0
  commit_counts[2] = 0
  scroll_log.val = -1
  last_logged.val = -1.0e9
  sideways_log.val = -1
  text_rec.val = -1
  text_said.clear()
  timers_reset()
  reset_drawing()
  let left = leaked_state()
  if left.length() > 0 {
    abort("state kept from an earlier test: " + left.join(", "))
  }
}

///|
/// The tables kept outside the context that still hold something (a Tester starts with all of them empty).
fn leaked_state() -> Array[String] {
  let out = []
  let check = fn(name : String, n : Int) { if n > 0 { out.push(name) } }
  check("desk.menus", desk.menus.length() + desk.mutable_menus.length())
  check("desk.keys", desk.keys.length() + desk.mutable_keys.length())
  check("desk.cursors", desk.cursors.length() + desk.next_cursors.length())
  check("desk.sels", desk.sels.length() + desk.next_sels.length())
  check("picked", picked.base)
  check("image_cache", image_cache.length())
  check("image_data", image_data.length())
  check("pagers", pagers.length())
  check("code_fields", code_fields.length() + code_clears.length())
  check("open_views", open_views.length())
  check("streams", open_streams.length() + stream_nodes.length())
  check("native_nodes", native_nodes.length())
  check("picture_at", picture_at.length())
  check("wheels", wheels.length())
  check("captures", captures.length())
  check("drags", drags.length())
  check("sideways", sideways.length())
  check("words", words_marks.length() + words_kept.length() + words_sel.length())
  check("list_counts", list_counts.length())
  check("timers", helds.length() + marks_at.length())
  check("drawing", dr.entries.length() + dr.overlay.length() + dr.carry.length())
  check("messages", fake_posted.length())
  out
}

///|
/// A tester showing `view` in a window of w × h logical pixels; it has
/// already drawn the first frame, and the frames it owes at that moment
/// (Tester::draw's). `images`: sources views may load, with
/// their size in pixels (others fail to load).
/// `dark`, `window_inset`, `env`, `app_version`: what the app reads of where
/// it runs (hostread.mbt): the system dark, the window's buttons in its top
/// row, environment variables, the build's version code.
/// `platform`: the system it plays, as @host.platform has them (0 macOS,
/// 1 iOS, 2 Android: how lists scroll). `seed`: the order the runtime's ready
/// fibers run in is drawn from it (fx.mbt; without, the order they became ready).
/// `text`: a real host's text as it kept it (MBUI_TEXT_RECORD's lines, textrec.mbt): its metrics, shaping and glyphs
/// in place of the fake host's. `scale`: device pixels a point. `time`: the clock before the first frame (drawn 16 ms
/// later). `stable`: output the same on every run, as a host asked by MBUI_BENCH=-1 makes it (Ctx::stable).
/// `run`: a real host's run this Tester replays (Tester::replay_frames): the system's settings it began with (its ENV
/// lines before its first frame) are set before the first frame is drawn, so that frame is the run's first (and only
/// it: the run's next frames are its own).
/// `finish`: what the host does for the app (an image decoding, a native view
/// loading) is done by itself at the next frame, in the order asked; false: it
/// stays undone until the test says (Tester::finish, finish_all), so the test
/// decides when and in what order it comes in.
/// `h264`: whether its host decodes H.264 (@ui.h264_here: a stream's frames, stream.mbt).
pub fn Tester::new(
  view : (Ctx) -> Unit,
  w? : Double = 390.0,
  h? : Double = 844.0,
  dark? : Bool = false,
  window_inset? : Bool = false,
  env? : Array[(String, String)] = [],
  app_version? : Int = 0,
  images? : Array[(String, Int, Int)] = [],
  platform? : Int = 0,
  seed? : Int,
  text? : String,
  scale? : Double = 2.0,
  time? : Double = 1000.0,
  stable? : Bool = false,
  finish? : Bool = true,
  run? : String,
  h264? : Bool = false,
) -> Tester {
  let f = {
    time,
    wall: tester_wall - time,
    scale,
    wants: false,
    wake: -1.0,
    instances: 0,
    ime_active: false,
    ime_text: "",
    ime_sel: (0, 0),
    ime_rect: (0.0, 0.0, 0.0, 0.0),
    clipboard: "",
    clipboard_secret: -1.0,
    back_on: false,
    platform,
    reduce_transparency: false,
    reduce_motion: false,
    logs: [],
    image_sizes: {},
    image_loads: [],
    images: {},
    bold: 0.0,
    views: [],
    view_ids: 0,
    view_ready: {},
    auto_finish: finish,
    finished: [],
    site: [],
    cursor: 0,
    window_drags: 0,
    opened: [],
    dark,
    inset: window_inset,
    env: Map::from_array(env),
    app_version,
    notices: [],
    notice_opened: "",
    installs: [],
    hold_words: None,
    overs_done: [],
    notice_perm: "granted",
    notice_reply: Some(true),
    notice_asks: 0,
    notice_due: None,
    pdfs: {},
    picks: [],
    pick_asks: [],
    keeps: [],
    reads: [],
    read_ids: 0,
    read_answers: [],
    players: {},
    share: None,
    share_files: [],
    marks: [],
    marks_out: [],
    marks_next: None,
    shares: [],
    view_texts: {},
    view_stills: {},
    view_infos: {},
    site_states: {},
    site_bodies: {},
    site_of: {},
    view_kinds: {},
    view_at: {},
    view_touch: {},
    touch_view: 0,
    touch_down: (0.0, 0.0),
    touch_at: (0.0, 0.0),
    touch_sideways: false,
    scripts_waiting: {},
    scripts_run: {},
    page_there: {},
    scripts_sent: [],
    h264,
    stream_ids: 0,
    streams_fed: {},
    stream_said: {},
  }
  for im in images {
    f.image_sizes[im.0] = (im.1, im.2)
  }
  if run is Some(r) {
    env_before_frames(f, r)
  }
  fake.val = Some(f)
  reset_globals()
  match text {
    Some(lines) => text_table.val = Some(text_table_of(lines))
    None => ()
  }
  if stable {
    bench.mode = -1
  }
  fx_reset(seed)
  g_view.val = view
  let t = { fake: f, w, h, frames: 0, seed, origin: time, period: frame_period_default, times: [] }
  // a host's run replayed: its first frame where the host drew it (its first DRAWHASH), the display's frames from
  // there; else the display's first frame after `time`
  match run.bind(run_first_frame) {
    Some(at) => {
      t.origin = at
      t.frame_at(at)
    }
    None => t.frame()
  }
  // (what the first frame left owed, drawn at its moment, as Tester::draw draws an input's; a host's run replayed has
  // only the frames it drew: Tester::replay_frames draws the next where it did)
  if run is None {
    t.draw_owed(1)
  }
  t
}

///|
/// What the app awaits from the fake host, oldest first: (1, an image's id) decoding, (2, a native view's id) not
/// ready yet.
pub fn Tester::pending(self : Tester) -> Array[(Int, Int)] {
  let out : Array[(Int, Int)] = []
  let ids = self.fake.images.keys().collect()
  ids.sort()
  for id in ids {
    if self.fake.images.get(id) is Some(im) && im.state == 0 {
      out.push((1, id))
    }
  }
  for id in 1..=self.fake.view_ids {
    if !self.fake.view_ready.contains(id) {
      out.push((2, id))
    }
  }
  out
}

///|
/// What the app asked the host for is done, now (the host's event): `kind` 1 an image decoded (`ok` false: it could
/// not be), 2 a native view ready (or failed). Seen from the next frame on. Nothing if it is not pending.
pub fn Tester::finish(self : Tester, kind : Int, id : Int, ok? : Bool = true) -> Unit {
  let state = if ok { 1 } else { -1 }
  match kind {
    1 =>
      match self.fake.images.get(id) {
        Some(im) if im.state == 0 => im.state = state
        _ => return
      }
    2 => {
      if id < 1 || id > self.fake.view_ids || self.fake.view_ready.contains(id) {
        return
      }
      self.fake.view_ready[id] = state
    }
    _ => return
  }
  self.fake.wants = true
  self.fake.finished.push((kind, id))
  on_outside(kind, id, state)
}

///|
/// What the fake host finished, in the order it did ((kind, id): Tester::finish).
pub fn Tester::finished_order(self : Tester) -> Array[(Int, Int)] {
  self.fake.finished.copy()
}

///|
/// What the app awaits from the host, as effect.mb's outside says it (what it is), oldest first.
pub fn Tester::awaited(self : Tester) -> Array[String] {
  ignore(self)
  runtime().awaited().map(a => a.0)
}

///|
/// Everything pending is done (Tester::finish each): in the order asked, or, made with a seed, in an order drawn
/// from it (another seed, another order; the same seed, the same).
pub fn Tester::finish_all(self : Tester) -> Unit {
  let ps = self.pending()
  match self.seed {
    Some(s) => {
      // Fisher-Yates over a small LCG from the seed
      let mut x = s.to_int64() * 6364136223846793005L + 1442695040888963407L
      for i = ps.length() - 1; i > 0; i = i - 1 {
        x = x * 6364136223846793005L + 1442695040888963407L
        let j = ((x >> 33) % (i + 1).to_int64()).to_int()
        let j = if j < 0 { -j } else { j }
        let t = ps[i]
        ps[i] = ps[j]
        ps[j] = t
      }
    }
    None => ()
  }
  for p in ps {
    self.finish(p.0, p.1)
  }
}

///|
/// Draws one frame, at the display's first frame `ms` or more on (by default, and at the least, the next one): frames
/// come only at the display's vsync (Tester::set_frame_period, set_frame_times), as on a host.
pub fn Tester::frame(self : Tester, ms? : Double = 0.0) -> Unit {
  let next = self.tick_after(self.fake.time)
  let want = self.fake.time + ms
  self.frame_at(if want > next { self.tick_at(want) } else { next })
}

///|
/// The display's first frame after `t` (Tester::frame): of its frames' times (set_frame_times) while they last, else on
/// its period.
fn Tester::tick_after(self : Tester, t : Double) -> Double {
  match self.times.search_by(fn(f) { f > t }) {
    Some(i) => self.times[i]
    None => {
      let k = ((t - self.origin) / self.period + 1.0e-9).floor() + 1.0
      self.origin + k * self.period
    }
  }
}

///|
/// The display's first frame at or after `t`.
fn Tester::tick_at(self : Tester, t : Double) -> Double {
  match self.times.search_by(fn(f) { f >= t }) {
    Some(i) => self.times[i]
    None => {
      let k = ((t - self.origin) / self.period - 1.0e-9).ceil()
      self.origin + k * self.period
    }
  }
}

///|
/// The display's frame period (ms): its frames this far apart.
pub fn Tester::frame_period(self : Tester) -> Double {
  self.period
}

///|
/// When the display's next frame is: where the next input is taken, the next change the test makes is shown.
pub fn Tester::next_frame_time(self : Tester) -> Double {
  self.tick_after(self.fake.time)
}

///|
/// The display's first frame at or after `t` on the clock: where a test sees what is so at `t` (a deadline, a motion's
/// end), as a host shows it.
pub fn Tester::display_frame(self : Tester, t : Double) -> Double {
  self.tick_at(t)
}

///|
/// The display's frame period from now on (ms; a run's own, as its tape says it), its frames counted from now (frames'
/// times set before let go).
pub fn Tester::set_frame_period(self : Tester, ms : Double) -> Unit {
  self.origin = self.fake.time
  self.period = ms
  self.times = []
}

///|
/// The display's frames from now on at `times` (ms on the frames' clock, each later than the one before and than now):
/// a run's own, as its tape had them, where every frame the Tester draws comes (an input's, run_for's, draw's); after
/// the last, on the frame period from it. Grid and tape are one: the period's frames a table of times evenly apart.
pub fn Tester::set_frame_times(self : Tester, times : Array[Double]) -> Unit {
  let mut before = self.fake.time
  for i, at in times {
    if !(at > before) {
      let s = "Tester::set_frame_times: time \{i} (\{at}) is not later than " +
        (if i == 0 { "now (\{before})" } else { "the one before it (\{before})" })
      println(s)
      abort(s)
    }
    before = at
  }
  self.times = times.copy()
  if times.length() > 0 {
    self.origin = times[times.length() - 1]
  }
}

///|
/// Draws one frame at `at` on the clock, whatever the display's frames (a host's run replayed: where it drew).
pub fn Tester::frame_at(self : Tester, at : Double) -> Unit {
  self.fake.time = at
  // decodes started last frame are done, the views opened are ready: the host's events for them (unless the test
  // says when: Tester::finish)
  if self.fake.auto_finish {
    for p in self.pending() {
      self.finish(p.0, p.1)
    }
  }
  self.fake.wants = false
  // a scripted run's `resize`
  match tester_size.val {
    Some((w, h)) => {
      self.w = w
      self.h = h
      tester_size.val = None
    }
    None => ()
  }
  on_frame(self.w, self.h, self.fake.scale, self.fake.time)
  self.frames = self.frames + 1
  // what the outside the test stands for has said meanwhile, posted for the next frame (messages.mbt)
  frame_ended_outside()
}

///|
pub fn Tester::resize(self : Tester, w : Double, h : Double) -> Unit {
  self.w = w
  self.h = h
  self.draw()
}

///|
pub fn Tester::tap(self : Tester, x : Double, y : Double) -> Unit {
  finger(0, x, y)
  finger(2, x, y)
  self.draw()
}

///|
/// A finger or mouse drag from one point to another in `steps` moves, one
/// frame apart, then released.
pub fn Tester::drag(
  self : Tester,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  steps? : Int = 10,
) -> Unit {
  finger(0, x0, y0)
  for i in 1..=steps {
    let t = i.to_double() / steps.to_double()
    // (a finger's moves come a display's frame apart: the drag takes steps × drag_step_ms)
    // (each move in the display's next frame, as a finger's come)
    let at = self.tick_after(self.fake.time)
    self.fake.time = at
    finger(1, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)
    self.frame_at(at)
  }
  finger(2, x1, y1)
  self.draw()
}

///|
/// How far apart a drag's moves come (ms), about: a 60 Hz display's frame, as a finger's moves reach an app. A drag's
/// moves come each in the display's next frame (Tester::frame_period_default apart, or the period told).
pub let drag_step_ms : Double = 16.0

///|
pub fn Tester::wheel(self : Tester, x : Double, y : Double, dy : Double) -> Unit {
  finger_wheel(x, y, 0.0, dy, 0)
  self.draw()
}

///|
/// Text committed by the input method (or typed on a hardware keyboard).
pub fn Tester::type_text(self : Tester, s : String) -> Unit {
  on_text(0, s, 0, 0)
  self.draw()
}

///|
/// The input method's composition, with the caret at its end.
pub fn Tester::compose(self : Tester, s : String) -> Unit {
  on_text(1, s, s.length(), 0)
  self.draw()
}

///|
pub fn Tester::key(self : Tester, code : Int, mods? : Int = 0) -> Unit {
  on_key(code, mods)
  self.draw()
}

///|
pub fn Tester::enter(self : Tester) -> Unit {
  self.key(key_enter)
}

///|
pub fn Tester::backspace(self : Tester) -> Unit {
  self.key(key_backspace)
}

///|
/// The centre of the first text node (or editor placeholder) containing `s`.
pub fn Tester::find(self : Tester, s : String) -> (Double, Double)? {
  let c = g()
  for i in 0..<c.count {
    let n = c.nodes[i]
    if (n.kind == kind_text || n.kind == kind_editor || n.kind == kind_rich) &&
      n.text.contains(s) {
      return Some((n.x + n.fw / 2.0, n.y + n.fh / 2.0))
    }
  }
  None
}

///|
/// The centre of the last text node containing `s` (drawn last: what lies over the others, a sheet's).
pub fn Tester::find_last(self : Tester, s : String) -> (Double, Double)? {
  ignore(self)
  let c = g()
  let mut found = None
  for i in 0..<c.count {
    let n = c.nodes[i]
    if (n.kind == kind_text || n.kind == kind_editor || n.kind == kind_rich) &&
      n.text.contains(s) {
      found = Some((n.x + n.fw / 2.0, n.y + n.fh / 2.0))
    }
  }
  found
}

///|
pub fn Tester::tap_text(self : Tester, s : String) -> Unit {
  match self.find(s) {
    Some((x, y)) => self.tap(x, y)
    None => abort("no text \"\{s}\" on screen")
  }
}

///|
/// What the host was last told about the focused field: active, text,
/// selection start and end.
pub fn Tester::ime(self : Tester) -> (Bool, String, Int, Int) {
  let (a, b) = self.fake.ime_sel
  (self.fake.ime_active, self.fake.ime_text, a, b)
}

///|
/// Where the host was last told the caret is (x, y, w, h).
pub fn Tester::ime_rect(self : Tester) -> (Double, Double, Double, Double) {
  self.fake.ime_rect
}

///|
pub fn Tester::clipboard(self : Tester) -> String {
  self.fake.clipboard
}

///|
/// How the app over another app was ended (@ui.over_done), oldest first: whether on into the app.
pub fn Tester::overs_done(self : Tester) -> Array[Bool] {
  self.fake.overs_done.copy()
}

///|
/// What the app last said the notice holding it up says (@ui.hold_words): its channel, title and line.
pub fn Tester::hold_words(self : Tester) -> (String, String, String)? {
  self.fake.hold_words
}

///|
/// The packages the app handed to the system's installer (@ui.install_package), oldest first.
pub fn Tester::installs(self : Tester) -> Array[String] {
  self.fake.installs.copy()
}

///|
/// Whether the clipboard's words were put there as a secret (Ctx::copy_secret): how long after they are taken off,
/// None when they were not.
pub fn Tester::clipboard_secret(self : Tester) -> Double? {
  if self.fake.clipboard_secret < 0.0 {
    None
  } else {
    Some(self.fake.clipboard_secret)
  }
}

///|
pub fn Tester::instances(self : Tester) -> Int {
  self.fake.instances
}

///|
/// What the fake host was asked of its native views and PDFs, a line each ("open 1 1 9", "place 1 0 0 390 220 in 0 0
/// 390 844", "control 1 1 0", "close 1", "pdf 2400"…), in order.
pub fn Tester::views(self : Tester) -> Array[String] {
  self.fake.views
}

///|
/// A site view's host says `event` (its JSON text, as view_site_next gives it: a request, one let go, a link left by),
/// taken on the next frame.
pub fn Tester::site_says(self : Tester, event : String) -> Unit {
  self.fake.site.push(event)
  g().wants_frame = true
}

///|
/// The holes (kind 9: where a native view shows) in the last frame, as (x, y, w, h).
pub fn Tester::holes(self : Tester) -> Array[(Double, Double, Double, Double)] {
  ignore(self)
  let out = []
  for i in 0..<g().ninst {
    let b = i * inst_size
    if g().inst[b + 5] == 9.0 {
      out.push((g().inst[b], g().inst[b + 1], g().inst[b + 2], g().inst[b + 3]))
    }
  }
  out
}

///|
fn r(x : Double) -> Int {
  x.round().to_int()
}

///|
/// The laid-out tree as text: one node per line, indented by depth, with its
/// rectangle; text nodes with their text and line count.
pub fn Tester::dump(self : Tester) -> String {
  let sb = StringBuilder()
  dump_node(sb, 0, 0)
  sb.to_string()
}

///|
fn dump_node(sb : StringBuilder, i : Int, depth : Int) -> Unit {
  let c = g()
  if i >= c.count {
    return
  }
  let n = c.nodes[i]
  for _ in 0..<depth {
    sb.write_string("  ")
  }
  let kind = if n.kind == kind_text {
    "text"
  } else if n.kind == kind_rich {
    "rich"
  } else if n.kind == kind_list {
    "list"
  } else if n.kind == kind_editor {
    "editor"
  } else if n.dir == Row {
    "row"
  } else {
    "col"
  }
  sb.write_string("\{kind} \{r(n.x)},\{r(n.y)} \{r(n.fw)}x\{r(n.fh)}")
  if n.kind == kind_text {
    let lines = match n.tl {
      Some(tl) => tl.line_start.length()
      None => 0
    }
    sb.write_string(" \{n.text.escape()} lines=\{lines}")
  }
  if n.kind == kind_rich {
    let lines = match n.rl {
      Some(rl) => rl.line_start.length()
      None => 0
    }
    sb.write_string(" \{n.text.escape()} lines=\{lines}")
  }
  if n.kind == kind_editor {
    match c.editors.get(n.id) {
      Some(st) => sb.write_string(" \{st.shown().escape()} caret=\{st.caret}")
      None => ()
    }
  }
  if n.item >= 0 {
    sb.write_string(" item=\{n.item}")
  }
  sb.write_char('\n')
  let mut ch = n.first
  while ch >= 0 {
    dump_node(sb, ch, depth + 1)
    ch = c.nodes[ch].next
  }
}

///|
/// The rectangle of the first node whose text contains `s` (x, y, w, h).
pub fn Tester::rect_of(self : Tester, s : String) -> (Double, Double, Double, Double)? {
  let c = g()
  for i in 0..<c.count {
    let n = c.nodes[i]
    if (n.kind == kind_text || n.kind == kind_rich || n.kind == kind_editor) &&
      n.text.contains(s) {
      return Some((n.x, n.y, n.fw, n.fh))
    }
  }
  None
}

///|
/// Visible list rows: (item, y, height), top to bottom.
pub fn Tester::rows(self : Tester) -> Array[(Int, Double, Double)] {
  let c = g()
  let out = []
  for i in 0..<c.count {
    if c.nodes[i].kind == kind_list {
      let mut r = c.nodes[i].first
      while r >= 0 {
        let n = c.nodes[r]
        out.push((n.item, n.y, n.fh))
        r = n.next
      }
    }
  }
  out
}

///|
/// The lines of the first text node whose text contains `s`, as laid out.
pub fn Tester::lines_of(self : Tester, s : String) -> Array[String] {
  let c = g()
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.kind == kind_text && n.text.contains(s) {
      match n.tl {
        Some(tl) =>
          return Array::makei(tl.line_start.length(), fn(l) {
            let (a, b) = tl.line_range(l)
            tl.text.unsafe_substring(start=a, end=b)
          })
        None => ()
      }
    }
    if n.kind == kind_rich && n.text.contains(s) {
      match n.rl {
        Some(rl) =>
          return Array::makei(rl.line_count(), fn(l) {
            let (a, b) = rl.line_range(l)
            rl.text.unsafe_substring(start=a, end=b)
          })
        None => ()
      }
    }
  }
  []
}

///|
/// The pointer moved to (x, y), no button down.
pub fn Tester::move(self : Tester, x : Double, y : Double) -> Unit {
  finger(1, x, y)
  self.draw()
}

///|
fn Tester::list_state(self : Tester) -> ListState {
  ignore(self)
  let c = g()
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.kind == kind_list {
      match c.lists.get(n.id) {
        Some(st) => return st
        None => ()
      }
    }
  }
  abort("no list on screen")
}

///|
/// The context the view is built in (between frames: for what a view would
/// call on it while building, as Ctx::list_moved).
pub fn Tester::ctx(self : Tester) -> Ctx {
  ignore(self)
  g()
}

///|
/// Scrolls the (first) list so that row `item` starts at its top, from the
/// next frame on.
pub fn Tester::scroll_to(self : Tester, item : Int) -> Unit {
  self.list_state().scroll_to(item)
}

///|
pub fn Tester::scroll_to_end(self : Tester) -> Unit {
  self.list_state().scroll_to_end()
}

///|
/// The first and last rows of the list in view (-1, -1 when none).
pub fn Tester::visible(self : Tester) -> (Int, Int) {
  let st = self.list_state()
  (st.vis_first, st.vis_last)
}

///|
pub fn Tester::at_end(self : Tester) -> Bool {
  self.list_state().at_end
}

///|
/// Where row `item` of the list is (x, y, w, h), if built.
pub fn Tester::row(self : Tester, item : Int) -> (Double, Double, Double, Double)? {
  ignore(self)
  let c = g()
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.item == item && n.parent >= 0 && c.nodes[n.parent].kind == kind_list {
      // only rows the list kept (it may build some it doesn't show)
      let mut ch = c.nodes[n.parent].first
      while ch >= 0 {
        if ch == i {
          return Some((n.x, n.y, n.fw, n.fh))
        }
        ch = c.nodes[ch].next
      }
    }
  }
  None
}

///|
/// Checks the list's rows in view follow each other without gaps or
/// overlaps and fill the view from `top` to `bottom` (unless they run
/// out), as mygo's checkRows does.
pub fn Tester::check_rows(self : Tester, top : Double, bottom : Double) -> Unit raise {
  let (first, last) = self.visible()
  if last < first || first < 0 {
    fail("no row in view")
  }
  let (_, y0, _, h0) = self.row(first).unwrap()
  if y0 > top + 0.01 {
    fail("row \{first}, the first in view, starts at \{y0}, below the top \{top}")
  }
  let mut end = y0 + h0
  for i in (first + 1)..=last {
    match self.row(i) {
      Some((_, y, _, h)) => {
        if (y - end).abs() > 0.01 {
          fail("row \{i} starts \{y - end} from where row \{i - 1} ends")
        }
        end = y + h
      }
      None => fail("row \{i} in view was not built")
    }
  }
  if last < self.list_state().count - 1 && end < bottom - 0.01 {
    fail("row \{last}, the last in view, ends at \{end}, above the bottom \{bottom}")
  }
}

///|
/// A key by name: Home, End, PageUp, PageDown, Up, Down, Left, Right,
/// Enter, Backspace, Delete, Escape, Tab, Space, or a character ("a").
pub fn Tester::press(self : Tester, name : String) -> Unit {
  let code = match name {
    "Home" => key_home
    "End" => key_end
    "PageUp" => key_page_up
    "PageDown" => key_page_down
    "Up" => key_up
    "Down" => key_down
    "Left" => key_left
    "Right" => key_right
    "Enter" => key_enter
    "Backspace" => key_backspace
    "Delete" => key_delete
    "Escape" => key_escape
    "Tab" => key_tab
    "Space" => key_space
    _ =>
      if name.length() == 1 {
        key_of_char(name.iter().next().unwrap())
      } else {
        abort("no key \{name}")
      }
  }
  self.key(code)
}

///|
/// Back, as a back button (or the system's back with no gesture) asks.
pub fn Tester::back(self : Tester) -> Unit {
  on_back(2, 0.0, 1.0, 0)
  self.draw()
}

///|
/// The system's back gesture (Android's predictive back) from the left
/// edge to `x`, in `steps` moves a frame apart; then gone back (`commit`)
/// or called off. Not settled: the page is where it was let go.
pub fn Tester::back_gesture(
  self : Tester,
  x : Double,
  commit : Bool,
  steps? : Int = 10,
) -> Unit {
  on_back(0, 0.0, 0.0, 0)
  for i in 1..=steps {
    let at = self.tick_after(self.fake.time)
    self.fake.time = at
    on_back(1, x * i.to_double() / steps.to_double(), 0.0, 0)
    self.frame_at(at)
  }
  on_back(if commit { 2 } else { 3 }, x, 1.0, 0)
  self.draw()
}

///|
/// A finger event now on the tester's clock (kind 0 down, 1 moved, 2 up, 3
/// called off), handled at once, no frame drawn: for touches between
/// frames, at the times a host gives them.
pub fn Tester::touch(self : Tester, kind : Int, x : Double, y : Double) -> Unit {
  ignore(self)
  finger(kind, x, y)
}

///|
/// The URLs the app handed to the system (Ctx::open_url), oldest first.
pub fn Tester::opened(self : Tester) -> Array[String] {
  self.fake.opened
}

///|
/// The clock moves on `ms`, no frame drawn.
pub fn Tester::advance(self : Tester, ms : Double) -> Unit {
  self.fake.time = self.fake.time + ms
}

///|
/// The tester's clock (ms).
pub fn Tester::time(self : Tester) -> Double {
  self.fake.time
}

///|
/// The (first) list's scroll position: how far its top is from its first
/// row's.
pub fn Tester::list_offset(self : Tester) -> Double {
  self.list_state().offset()
}

///|
/// How far the (first) list is pulled past an end: positive at the top,
/// negative at the bottom (Android: in the list's heights; iOS: points).
pub fn Tester::list_overscroll(self : Tester) -> Double {
  let st = self.list_state()
  st.over * st.over_edge.to_double()
}

///|
/// Whether the (first) list moves on its own (a fling, an overscroll going
/// back).
pub fn Tester::list_moving(self : Tester) -> Bool {
  self.list_state().moving()
}

///|
/// Whether the host was told the app takes back.
pub fn Tester::takes_back(self : Tester) -> Bool {
  self.fake.back_on
}

///|
/// A finger down at (x, y) and moved to (x1, y1) in `steps` moves, a frame
/// apart, not let go (a page followed: see where it is).
pub fn Tester::hold_drag(
  self : Tester,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  steps? : Int = 10,
) -> Unit {
  finger(0, x0, y0)
  for i in 1..=steps {
    let t = i.to_double() / steps.to_double()
    // (each move in the display's next frame, as a finger's come)
    let at = self.tick_after(self.fake.time)
    self.fake.time = at
    finger(1, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)
    self.frame_at(at)
  }
}

///|
/// The finger let go at (x, y).
pub fn Tester::release(self : Tester, x : Double, y : Double) -> Unit {
  finger(2, x, y)
  self.draw()
}

///|
/// The finger down at (x, y), held (a frame drawn so).
pub fn Tester::press_at(self : Tester, x : Double, y : Double) -> Unit {
  finger(0, x, y)
  self.draw()
}

///|
/// The system asks for less transparency from now on, or no longer.
pub fn Tester::set_reduce_transparency(self : Tester, on : Bool) -> Unit {
  self.fake.reduce_transparency = on
  glass_paint.checked_at = -1000
}

///|
/// The glass drawn in the last frame: (x, y, w, h, kind (5 frosted, 6
/// liquid), the capture it shares (1, 2, …)).
pub fn Tester::drawn_glass(self : Tester) -> Array[(Double, Double, Double, Double, Int, Int)] {
  ignore(self)
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    let kind = c.inst[b + 5].to_int()
    if kind == 5 || kind == 6 {
      out.push(
        (
          c.inst[b],
          c.inst[b + 1],
          c.inst[b + 2],
          c.inst[b + 3],
          kind,
          (-c.inst[b + 20]).to_int(),
        ),
      )
    }
  }
  out
}

///|
/// The notches cut into the last frame's rectangles and frosted glass (Ctx::box `notch_r`): (kind (0 a rectangle, 5
/// glass), its top, its circle's middle below the top, its radius, its fillets').
pub fn Tester::drawn_notches(self : Tester) -> Array[(Int, Double, Double, Double, Double)] {
  ignore(self)
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    let kind = c.inst[b + 5].to_int()
    if (kind == 0 || kind == 5) && c.inst[b + 22] > 0.0 {
      out.push((kind, c.inst[b + 1], c.inst[b + 21], c.inst[b + 22], c.inst[b + 23]))
    }
  }
  out
}

///|
/// How many glyphs of the last frame are inked by the glass under them.
pub fn Tester::adaptive_glyphs(self : Tester) -> Int {
  ignore(self)
  let c = g()
  let mut n = 0
  for k in 0..<c.ninst {
    if c.inst[k * inst_size + 5] == 7.0 {
      n = n + 1
    }
  }
  n
}

///|
/// The plain rectangles drawn in the last frame, as (x, y, w, h, colour
/// RRGGBBAA with its opacity applied).
pub fn Tester::drawn_rects(self : Tester) -> Array[(Double, Double, Double, Double, Int64)] {
  ignore(self)
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 0.0 {
      let ch = fn(v : Double) { (v * 255.0).round().to_int64() }
      let color = (ch(c.inst[b + 8]) << 24) |
        (ch(c.inst[b + 9]) << 16) |
        (ch(c.inst[b + 10]) << 8) |
        ch(c.inst[b + 11])
      out.push((c.inst[b], c.inst[b + 1], c.inst[b + 2], c.inst[b + 3], color))
    }
  }
  out
}

///|
/// The glyphs drawn in the last frame: (x, y, colour).
pub fn Tester::drawn_glyphs(self : Tester) -> Array[(Double, Double, Int64)] {
  ignore(self)
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 1.0 {
      let ch = fn(v : Double) { (v * 255.0).round().to_int64() }
      let color = (ch(c.inst[b + 8]) << 24) |
        (ch(c.inst[b + 9]) << 16) |
        (ch(c.inst[b + 10]) << 8) |
        ch(c.inst[b + 11])
      out.push((c.inst[b], c.inst[b + 1], color))
    }
  }
  out
}

///|
/// The rich paragraph whose text contains `s`, as laid out, and where it
/// is (its content's top left).
pub fn Tester::rich_of(self : Tester, s : String) -> (RichLayout, Double, Double)? {
  ignore(self)
  let c = g()
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.kind == kind_rich && n.text.contains(s) {
      match n.rl {
        Some(rl) => return Some((rl, n.x + n.pad_l, n.y + n.pad_t))
        None => ()
      }
    }
  }
  None
}

///|
/// Where the words `s` of a rich paragraph are drawn: one rectangle a line
/// (x, y, w, h).
pub fn Tester::run_rects(self : Tester, s : String) -> Array[(Double, Double, Double, Double)] {
  match self.rich_of(s) {
    Some((rl, x, y)) =>
      match rl.text.find(s) {
        Some(a) =>
          rl
          .rects(a, a + s.length())
          .map(fn(r) { (r.0 + x, r.1 + y, r.2, r.3) })
        None => []
      }
    None => []
  }
}

///|
/// A tap on the middle of the first piece of the words `s` of a rich
/// paragraph (a link).
pub fn Tester::tap_run(self : Tester, s : String) -> Unit {
  let rs = self.run_rects(s)
  if rs.length() == 0 {
    abort("no rich text \"\{s}\" on screen")
  }
  let (x, y, w, h) = rs[0]
  self.tap(x + w / 2.0, y + h / 2.0)
}

///|
/// Makes up an image at `src`, `w` × `h` pixels, for views to load.
pub fn Tester::add_image(self : Tester, src : String, w : Int, h : Int) -> Unit {
  self.fake.image_sizes[src] = (w, h)
}

///|
/// The images loaded so far: source and the size asked for.
pub fn Tester::image_loads(self : Tester) -> Array[(String, Int)] {
  self.fake.image_loads
}

///|
/// How many decoded images are kept.
pub fn Tester::images_kept(self : Tester) -> Int {
  self.fake.images.length()
}

///|
/// The image instances drawn in the last frame: (x, y, w, h, u0, v0, du,
/// dv, opacity).
pub fn Tester::drawn_images(self : Tester) -> Array[Array[Double]] {
  ignore(self)
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 4.0 {
      out.push([
        c.inst[b],
        c.inst[b + 1],
        c.inst[b + 2],
        c.inst[b + 3],
        c.inst[b + 12],
        c.inst[b + 13],
        c.inst[b + 14],
        c.inst[b + 15],
        c.inst[b + 11],
      ])
    }
  }
  out
}

///|
/// The host says the app is shown or not, in front or not (as a window's or an activity's changes are told).
pub fn Tester::app_state(self : Tester, visible : Bool, focused : Bool) -> Unit {
  on_app_state((if visible { 1 } else { 0 }) | (if focused { 2 } else { 0 }))
  self.draw()
}

///|
/// Bold text `em` ems wider a character than regular from now on (the fake
/// host's shapes ignore weight otherwise).
pub fn Tester::bold_wider(self : Tester, em : Double) -> Unit {
  self.fake.bold = em
}

///|
/// Where the first text node containing `s` is drawn (its top left), moved as it and what holds it move
/// (draw.mbt).
pub fn Tester::drawn_of(self : Tester, s : String) -> (Double, Double)? {
  ignore(self)
  let c = g()
  for i in 0..<c.count {
    let n = c.nodes[i]
    if (n.kind == kind_text || n.kind == kind_rich) && n.text.contains(s) {
      return Some(c.drawn_at(i))
    }
  }
  None
}

///|
/// How the node keyed `what` (its id's key, as built: c.id(what)), else the first text node containing `what` (`=WORDS`:
/// whose words are WORDS exactly, as Tester::locate takes it), was drawn in the last frame over how it is laid out: its
/// scale across and down and its opacity, its own look's and all its ancestors' together (a card shrunk to 90% as it
/// goes: (0.9, 0.9, 1.0)). None when there is no such node.
pub fn Tester::look_of(self : Tester, what : String) -> (Double, Double, Double)? {
  ignore(self)
  let c = g()
  let id = c.id(what)
  let mut found = -1
  for i in 0..<c.count {
    if c.nodes[i].id == id {
      found = i
      break
    }
  }
  if found < 0 {
    let exact = if what.has_prefix("=") && what.length() > 1 {
      Some(what.unsafe_substring(start=1, end=what.length()))
    } else {
      None
    }
    for i in 0..<c.count {
      let n = c.nodes[i]
      if (n.kind == kind_text || n.kind == kind_rich) &&
        (match exact {
          Some(e) => n.text == e
          None => n.text.contains(what)
        }) {
        found = i
        break
      }
    }
  }
  guard found >= 0 else { return None }
  let mut sx = 1.0
  let mut sy = 1.0
  let mut alpha = 1.0
  let mut p = found
  while p >= 0 {
    match c.drawn_entry(p) {
      Some(e) => {
        sx = sx * e.look.sx
        sy = sy * e.look.sy
        alpha = alpha * e.look.alpha
      }
      None => ()
    }
    p = c.nodes[p].parent
  }
  Some((sx, sy, alpha))
}

///|
/// A tap and the one frame after it, nothing settled (what moves after it is the test's to step).
pub fn Tester::tap_once(self : Tester, x : Double, y : Double) -> Unit {
  finger(0, x, y)
  finger(2, x, y)
  self.draw()
}

///|
/// A secondary click (a right click) at (x, y): what a context menu opens on.
pub fn Tester::right_click(self : Tester, x : Double, y : Double) -> Unit {
  on_pointer(0, x, y, 2)
  on_pointer(2, x, y, 2)
  self.draw()
}

///|
/// The pointer gone out of the window.
pub fn Tester::leave(self : Tester) -> Unit {
  on_pointer(7, -1.0, -1.0, 0)
  self.draw()
}

///|
/// A wheel at (x, y) as the host sends it: `phase` 0 a trackpad's (or a host that does not say), 4 a mouse wheel's
/// notch (eased in over the next frames). One frame drawn, not settled.
pub fn Tester::wheel_phase(self : Tester, x : Double, y : Double, dy : Double, phase : Int) -> Unit {
  finger_wheel(x, y, 0.0, dy, phase)
  self.draw()
}

///|
/// The pointer's shape the host was last told (desktop.mbt Cursor).
pub fn Tester::cursor(self : Tester) -> Cursor {
  match self.fake.cursor {
    1 => Hand
    2 => IBeam
    3 => ResizeX
    4 => ResizeY
    5 => Grab
    _ => Arrow
  }
}

///|
/// How often a press asked the host to drag the window.
pub fn Tester::window_drags(self : Tester) -> Int {
  self.fake.window_drags
}

///|
/// Tab (Shift+Tab when `back`): the focus to the next stop (focus.mbt).
pub fn Tester::tab(self : Tester, back? : Bool = false) -> Unit {
  self.key(key_tab, mods=if back { mod_shift_key } else { 0 })
}

///|
/// The semantics tree of the last frame (Ctx::semantics_tree).
pub fn Tester::semantics(self : Tester) -> Array[SemNode] {
  ignore(self)
  g().semantics_tree()
}

///|
/// The semantics tree as text, hidden nodes left out (Ctx::semantics_dump).
pub fn Tester::semantics_dump(self : Tester) -> String {
  ignore(self)
  g().semantics_dump()
}

///|
/// The nodes of `role` not hidden (under a modal, in a hidden part), labelled `label` exactly unless it is "".
pub fn Tester::all(self : Tester, role : Role, label? : String = "") -> Array[SemNode] {
  self.semantics().filter(fn(s) { s.role == role && !s.hidden && (label == "" || s.label == label) })
}

///|
/// The node of `role` labelled `label` (Testing Library's getByRole with its name, Compose's onNode): the one not
/// hidden; the test fails when there is none, or more than one.
pub fn Tester::get(self : Tester, role : Role, label? : String = "") -> SemNode raise {
  let found = self.all(role, label~)
  if found.length() == 1 {
    return found[0]
  }
  let what = if label == "" { "\{role}" } else { "\{role} \{label.escape()}" }
  if found.is_empty() {
    fail("no \{what} in the semantics tree:\n\{self.semantics_dump()}")
  }
  fail("\{found.length()} of \{what} in the semantics tree:\n\{self.semantics_dump()}")
}

///|
/// The node of `role` labelled `label`, if there is one not hidden (the first).
pub fn Tester::query(self : Tester, role : Role, label? : String = "") -> SemNode? {
  let found = self.all(role, label~)
  if found.is_empty() {
    None
  } else {
    Some(found[0])
  }
}

///|
/// A tap on the middle of the node of `role` labelled `label` (Tester::get), settled.
pub fn Tester::click(self : Tester, role : Role, label? : String = "") -> Unit raise {
  let s = self.get(role, label~)
  let (x, y, w, h) = s.rect
  self.tap(x + w / 2.0, y + h / 2.0)
}

///|
/// `action` asked of the node of `role` labelled `label` (as a screen reader asks it), settled.
pub fn Tester::act(self : Tester, role : Role, action : Action, label? : String = "") -> Unit raise {
  let s = self.get(role, label~)
  if s.id == 0 {
    fail("\{s.describe()} takes no action")
  }
  g().ask_action(s.id, action)
  self.draw()
}

///|
/// The node that has the keyboard's focus, if it says something.
pub fn Tester::focused(self : Tester) -> SemNode? {
  for s in self.semantics() {
    if s.focused {
      return Some(s)
    }
  }
  None
}
