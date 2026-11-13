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
  /// how far apart the frames run_for draws on its way are (ms; MBUI_TEST_FPS's), or 0: none, straight to its end;
  /// drawn while the app asks for frames (not at rest), as a host draws them.
  /// Only on run_for's way: what the test draws itself (an input's frames, `frame()`, a moment it says) is on the
  /// display's frames as ever, so a run at another rate walks the same moments, only more or fewer frames between
  between : Double
  /// whether the frame being drawn is one of those (or what it left owed): how a motion goes frame to frame is not
  /// judged on it (Tester::judges_motion), so a run at a rate judges the frames the default run does, no more
  mut on_way : Bool
  /// whether how what moves goes is judged on those frames too (MBUI_TEST_MOTION: test_motion_judged)
  mut motion : MotionJudged
  /// a host's frames as its run had them (set_frame_times, set_frame_period): every frame on them, as the host drew
  /// it (an input's, a draw's, run_for's), not at the moments the test says
  mut host_frames : Bool
  /// when the next input comes, as a run's script gave it (Tester::inputs_next; +inf: none said): a host's frames after
  /// it not drawn ahead of it, what is owed then left to be drawn on the way to it and after
  mut inputs_next : Double
  /// what the test looks at after each frame it draws, as it is drawn (Tester::each_frame): a frame an input's draw
  /// passes over on its way (the one that takes it, before the ones after) seen too
  mut each : (() -> Unit)?
  /// A real renderer's setup immediately before the next frame, for a Tester that draws its frames offscreen.
  before : (() -> Unit)?
}

///|
/// A display's frame period, the Tester's own unless told another (Tester::set_frame_period): a 60 Hz display's.
pub let frame_period_default : Double = 1000.0 / 60.0

///|
/// The run before let go of, before the next one's inputs are said: the window's tree disposed (what it made, what its
/// bindings followed, what was due on its timeline), what is made once forgotten. Said where a run is begun before
/// its Tester is made (what the app is given before it, its made-up core opening a page, then reaches no tree of the
/// run before), and as a Tester starts.
pub fn run_let_go() -> Unit {
  made_forget()
  view_forget()
  frame_watches_let_go()
}

///|
/// End this test run and restore the host that was current before it began. Release its window tree, bindings and the
/// faces the run gave to its live host, so a later run starts with its own fonts. An older tester cannot close a newer
/// one. A live host used here must be dedicated to the test: a face the run replaced on it cannot be restored.
pub fn Tester::end_run(self : Tester, restore : &@hostapi.Host) -> Unit {
  match fake.val {
    Some(f) if physical_equal(f, self.fake) => {
      run_let_go()
      let mut had_faces = false
      for face in 1..<faces_given.length() {
        if faces_given[face] {
          h_face_clear(face)
          faces_given[face] = false
          had_faces = true
        }
      }
      if had_faces {
        words_forgotten()
      }
      fake.val = None
      shot_watch.val = None
      pass_look.val = None
      corners_look.val = None
      wait_look.val = None
      frame_look.val = None
      @hostapi.set_host(restore)
    }
    _ => ()
  }
}

///|
/// What a test leaves behind forgotten before the next starts: the window's context made anew (every field of it as a
/// window's first frame has it, by construction), and the state kept outside it (the package's own tables, those of
/// the packages over it: on_reset) emptied; then checked (leaked_state), so that what is added later and not
/// forgotten here fails the next Tester at once rather than a test somewhere else.
fn reset_globals() -> Unit {
  window_zoom_reset()
  journal_reset()
  tree_frames_reset()
  run_let_go()
  // A run can end with a frame's resource handover still queued. Finish it before resetting the next run.
  frame_afters_run()
  frame_afters.val = []
  the_ctx.val.let_go()
  the_ctx.val = Ctx::new()
  looks_reset()
  pace_none()
  notices_reset()
  hand_reset()
  corners_hold.val = true
  corners_known_now.val = []
  presses_hold.val = true
  placed_presented.val = None
  kept_presented.val = None
  text_runs.on = false
  inst_owners.on = false
  inst_owners.track = false
  host_record_forget()
  inst_owners_clear()
  text_runs.runs.clear()
  desk_reset()
  tester_size.val = None
  env_kept.val = ""
  app_state.val = 3
  app_shown_said.set(true)
  app_front_said.set(true)
  app_on_said.set(true)
  driver.val = None
  track_x.reset()
  track_y.reset()
  reset_glass()
  reveal_reset()
  clear_shapes()
  text_cache.fonts.clear()
  text_cache.metrics.clear()
  glyphs_forget()
  text_cache.generation = -1
  text_cache.frame = 0
  text_cache.thinned = -1
  web_lines.val = false
  faces_reset()
  text_table.val = None
  inputs_since.val = false
  inputs_taken.val = false
  secret_copies.val = 0
  in_frame.val = false
  building.val = false
  messages_reset()
  drop_reset()
  fake_op.val = None
  fake_op_runs.clear()
  fake_op_pending.val = false
  fake_autofill.val = false
  fake_autofill_asks.clear()
  fake_autofill_picked.val = ""
  fake_passkey.val = None
  fake_passkey_asks.clear()
  image_cache.clear()
  image_by_id.clear()
  image_bytes.val = 0.0
  images_said.clear()
  views_told_text.clear()
  views_told_info.clear()
  sites_told_state.clear()
  outside_tickets.clear()
  update_told.set("")
  update_asked.clear()
  answers_waiting.clear()
  outside_takers.clear()
  @hostapi.autofill_forget()
  views_told.clear()
  views_told_changed()
  code_fields.clear()
  code_clears.clear()
  bars_hand.clear()
  perf_bytes_said.set(-1.0)
  image_data.clear()
  image_vector_drawers.clear()
  moving_images.clear()
  pixels_read.clear()
  open_views.clear()
  stacked_views.clear()
  views_stirred.clear()
  streams_reset()
  native_nodes.clear()
  picture_at.clear()
  wheels.clear()
  wheels_x.clear()
  wheel_mods.clear()
  captures.clear()
  drags.clear()
  press_follow_reset()
  sideways.clear()
  shows_asked.clear()
  app_said.clear()
  words_kept.clear()
  words_sel.clear()
  list_counts.clear()
  list_keys_seen.clear()
  second_ptr[2] = 0.0
  bench.mode = 0
  g_view.val = fn(_c) { () }
  app_change.val = None
  reduce_env.val = -1
  groups_host.val = -1
  rows_on_pixels_said.val = -1
  lines_on_pixels_said.val = -1
  draw_log.val = -1
  draw_frames.val = 0
  fx_reset(None)
  // (whether its fake host tells what it does as events, as a run asks its host's: run)
  outside_told.val = @hostapi.set_outside(fn(k, id, st) { on_outside(k, id, st) })
  // (the hand as its fake host says it first: @ui.pointing)
  host_pointing.val = None
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
    @halt.saying("state kept from an earlier test: " + left.join(", "))
  }
}

///|
/// The tables kept outside the context that still hold something (a Tester starts with all of them empty).
fn leaked_state() -> Array[String] {
  let out = []
  let check = fn(name : String, n : Int) { if n > 0 { out.push(name) } }
  // (the signals' graph in the middle of a change or a read: what ran before stopped inside one, and every set after it
  // tells nothing (view's 185 of 435 on wasm-gc, 2026-11-11))
  check("signals' change begun and never ended (batch)", @signals.batch_depth())
  check("signals' reader left reading", if @signals.active_sub() is Some(_) { 1 } else { 0 })
  check("desk.menus", desk.menus.length() + desk.mutable_menus.length())
  check("desk.keys", desk.keys.length() + desk.mutable_keys.length())
  check("desk.sels", desk.sels.length() + desk.next_sels.length())
  check("picked", (if picked.from.base != NoSel { 1 } else { 0 }) + picked.spans.length())
  check("image_cache", image_cache.length())
  check("image_data", image_data.length())
  check("image_vector_drawers", image_vector_drawers.length())
  // (a GIF that moves, its decoder with it: GifCycle)
  check("moving_images", moving_images.length())
  check("code_fields", code_fields.length() + code_clears.length())
  check("open_views", open_views.length() + stacked_views.length())
  check("streams", open_streams.length() + stream_nodes.length())
  check("native_nodes", native_nodes.length())
  check("picture_at", picture_at.length())
  check("wheels", wheels.length())
  check("captures", captures.length())
  check("drags", drags.length())
  check("sideways", sideways.length())
  check("words", words_kept.length() + words_sel.length())
  check("list_counts", list_counts.length() + list_keys_seen.length())
  check("timers", helds.length() + marks_at.length())
  check("drawing", dr.entries.length() + dr.overlay.length() + dr.raised.length() + dr.carry.length())
  check("messages", fake_posted.length())
  check("inst_owners", inst_owners.owner.length())
  check("key_taken", if @view.key_marks_left() { 1 } else { 0 })
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
/// `platform`: the system it plays, as @hostapi.platform has them (0 macOS,
/// 1 iOS, 2 Android: how lists scroll). `keys`: the system whose keys are typed (@ui.keys_system), by default
/// `platform`; a browser's (4) the one under it. `pointing`: what the person points with (@ui.pointing), by default the
/// system's (a finger on iOS and Android): a run told on one system and replayed as it was (its core told that
/// system) by the hand it was made with. `native`: what the app was started to be used with (@ui.native_pointing), by
/// default its system's (the hand of the moment, `pointing`, changes none of it). `keyboard`: a keyboard at hand
/// (@ui.keyboard), by default its system's (a desktop's yes, a phone's or a tablet's no). `seed`: the order the runtime's ready
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
/// `copy_shown`: the system says itself that something was put on the clipboard (Android 13 and later: @ui.copy_shown).
/// `live`: a real host asked in place of the fake for what is drawn by, its text and its pictures (Live: a film's,
/// mbui/src/film; never a test's), recorded as a host's are (MBUI_TEXT_RECORD=1 in `env`); `text` is then not read.
/// `corners_held`: whether every frame it draws with nothing moving is held to the corner rule where the theme says
/// its ladder (Tester::hold_corners); false for a test that draws a fault on purpose, to find it.
/// `presses_held`: whether a frame it draws with presses said to be an area's that takes none there (Ctx::presses_to)
/// stops the test; false for a test that says one wrong on purpose, to find it (Tester::presses_unheld).
/// `window_corner`: how round the system draws the window's corners (@hostapi.window_corner: a Mac's 16, Windows 11's
/// 8; 0 square), the outermost container what lies in them is held concentric with (corners.mbt); `window_corners`
/// each of them where they differ (top left, then round it: an iPhone Duo's outer screen, 8 along its hinge).
/// `words_over_held`: whether every frame it draws while something moves is held to showing no words over others
/// (Tester::hold_words_over); false for a test that draws them on purpose, to find them.
/// `nav_able`: whether the system lays out the app's tabs itself (an iPhone Duo's: @hostapi.nav_bar_able), as a host
/// says it from the app's first frame on; Tester::set_nav_able changes it later.
/// `before`: a live renderer's frame setup, called before every frame including the first (a film's offscreen target).
/// `begun`: what the test sets for this run that its first frame is to show (a library's state, a film pinned), said
/// once the run has begun (the globals put back, every on_reset hook run) and before the first frame is drawn, which
/// is drawn here: what is set before the Tester is made is the run before's, put back as this one begins.
/// `keeps_sources`: whether the window's tree keeps where in the source each node was made (Tester::sources_at); off
/// for a run measured as a device runs it.
/// `loc`: where it is made, said where a check of its frames fails (frame_watch.mbt, words_over.mbt).
#callsite(autofill(loc))
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
  keys? : Int,
  pointing? : Pointing,
  native? : Pointing,
  keyboard? : Bool,
  seed? : Int,
  text? : String,
  scale? : Double = 2.0,
  time? : Double = 1000.0,
  stable? : Bool = false,
  finish? : Bool = true,
  run? : String,
  h264? : Bool = false,
  copy_shown? : Bool = false,
  live? : Live,
  corners_held? : Bool = true,
  presses_held? : Bool = true,
  window_corner? : Double = 0.0,
  window_corners? : FixedArray[Double],
  words_over_held? : Bool = true,
  nav_able? : Bool = false,
  tree? : (@view.View) -> Unit,
  before? : () -> Unit,
  begun? : () -> Unit,
  keeps_sources? : Bool = true,
  loc~ : SourceLoc,
) -> Tester {
  host_settings_given.val = ""
  fake_dues.clear()
  frames_by_clock_on.val = false
  let f = {
    time,
    late: 0.0,
    late_after: -1.0,
    late_frame: -1,
    wall: tester_wall - time,
    scale,
    wants: false,
    frames_on: 0,
    paced: 0.0,
    wake: -1.0,
    instances: 0,
    ime_active: false,
    ime_text: "",
    ime_sel: (0, 0),
    ime_told: 0,
    text_menu: (false, 0.0, 0.0, 0.0, 0.0, 0),
    text_menu_own: "",
    edit_can: -1,
    ime_rect: (0.0, 0.0, 0.0, 0.0),
    clipboard: "",
    badge: 0,
    local_station: "",
    local_acts: [],
    local_fonts: "",
    families_given: {},
    unreadable_fonts: [],
    mods: 0,
    clipboard_secret: -1.0,
    clipboard_image: -1,
    back_on: false,
    wheel_kept: false,
    window_shows: 0,
    platform,
    keys: keys.unwrap_or(platform),
    pointing: match pointing {
      Some(p) => p
      None => platform_pointing(platform)
    },
    event_finger: -1,
    event_at: -1.0,
    native: native.unwrap_or(platform_pointing(platform)),
    keyboard: keyboard.unwrap_or(platform_keyboard(platform)),
    reduce_transparency: false,
    reduce_motion: false,
    logs: [],
    image_sizes: {},
    image_loads: [],
    image_srcs: {},
    images: {},
    image_ids: 0,
    decode_after: {},
    decode_due: {},
    image_bytes: {},
    image_bytes_now: 0,
    image_bytes_most: 0,
    made_at: loc.to_string(),
    bold: 0.0,
    ui_face: 0.0,
    generation: 0,
    generation_asks: 0,
    generation_on_face_add: Ref(false),
    tabular: 0.0,
    glyph_box: (6.0, 10.0),
    faces_wider: {},
    views: [],
    view_ids: 0,
    view_ready: {},
    view_reads: 0,
    auto_finish: finish,
    finished: [],
    site: [],
    cursor: 0,
    cursors_told: 0,
    window_drags: 0,
    window_acts: [],
    zoomed: false,
    snap: (0.0, 0.0, 0.0, 0.0),
    snap_state: 0,
    window_opens: false,
    windows_opened: [],
    windows_closed: [],
    windows_fronted: [],
    opened: [],
    dark,
    inset: window_inset,
    full: false,
    buttons_down: (0.0, 0.0),
    window_corner,
    window_corners,
    font_scale: 1.0,
    utc_offset: 0,
    nav_able,
    nav_said: "",
    a11y: false,
    a11y_said: "",
    a11y_told: A11yMirror::new(),
    a11y_held: 0,
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
    notice_settings: 0,
    notice_due: None,
    pdfs: {},
    picks: [],
    pick_asks: [],
    keeps: [],
    gallery: None,
    gallery_reads: [],
    reads: [],
    read_ids: 0,
    read_answers: [],
    read_from: {},
    players: {},
    share: None,
    share_files: [],
    marks: [],
    marks_out: [],
    marks_next: None,
    marks_by_hand: false,
    picks_by_hand: false,
    rows_on_pixels: false,
    groups: true,
    keeps_sources,
    shares: [],
    perf: -1,
    perf_sets: [],
    perf_lines: [],
    perf_opens: false,
    perf_opened: 0,
    perf_bytes: 0.0,
    view_texts: {},
    view_stills: {},
    view_infos: {},
    site_states: {},
    site_bodies: {},
    site_of: {},
    view_kinds: {},
    view_at: {},
    view_touch: {},
    view_covers: {},
    touch_view: 0,
    touch_down: (0.0, 0.0),
    touch_at: (0.0, 0.0),
    touch_sideways: false,
    scripts_waiting: {},
    scripts_run: {},
    page_there: {},
    scripts_sent: [],
    h264,
    audio_here: false,
    h265_here: false,
    stream_feeds: false,
    stream_layers: false,
    stream_layers_srgb: false,
    stream_ids: 0,
    streams_fed: {},
    stream_said: {},
    dev: FakeDevice::new(copy_shown),
    pixels_of_src: {},
    pixels_of: {},
    live,
    live_images: {},
    shots: [],
    shot_sizes: [],
    shot_drawn: [],
  }
  for im in images {
    f.image_sizes[im.0] = (im.1, im.2)
  }
  fake.val = Some(f)
  wall_ahead.set(f.wall)
  // (what the app asks of its host directly, the fake's too: fake_host.mbt)
  @hostapi.set_host(f)
  reset_globals()
  // (each pass of a frame's build that kept rows built again keeping none and compared: tester_rows.mbt)
  pass_look.val = Some(rows_pass_looked)
  // (each frame's corners worked out with what is kept worked out anew as well and the two compared: tester_corners.mbt)
  corners_look.val = if test_corners_looked() { Some(corners_looked) } else { None }
  wait_look.val = Some(wait_looked)
  // (each frame painted alone or of its looks alone built whole after it and the two compared: tester_looks.mbt)
  frame_look.val = Some(looks_looked)
  // (each shot taken kept, what it says, how big a picture it makes and what it drew: Tester::shot_drawn)
  shot_watch.val = Some(fn(words, s) {
    let (x, y, w, h) = s.rect
    f.shots.push(words)
    let sc = if s.scale > 0.0 { s.scale } else { g().scale }
    f.shot_sizes.push(((w * sc).round().to_int(), (h * sc).round().to_int()))
    f.shot_drawn.push(shot_drawn_of(s.inst, s.ninst, x, y))
  })
  corners_hold.val = corners_held
  corners_known_now.val = []
  presses_hold.val = presses_held
  // (each frame of the looks by the clock alone drawn whole after it as well, and the two compared: frame_watch.mbt)
  looks_check.val = true
  looks_made_at.val = loc.to_string()
  focus_off_begun()
  // (the file each bar of its is held by: motion_runs)
  if motion_runs() {
    let at = loc.to_string()
    let file = match at.find(":") {
      Some(i) => at.unsafe_substring(start=0, end=i)
      None => at
    }
    println("MOTION made \{file}")
    // (and counted here, a run at a rate counting its file (motion_counted): what may say it leaves the list, a file
    // never run so, a sweep of the default rate's alone, says nothing of it)
    if test_motion_judged(at) == Count {
      println("MOTION counting \{file}")
    }
  }
  looks_unjudged.val = false
  motion_unjudged.val = false
  words_over_begin(loc.to_string(), words_over_held)
  rows_steady_begin(loc.to_string(), words_over_held)
  sizes_steady_begin(loc.to_string(), words_over_held)
  gaps_steady_begin(loc.to_string(), words_over_held)
  seen_whole.val = ""
  said_log.on = false
  frame_said.val = None
  said_log.built.reset()
  said_log.sb.reset()
  said_log.ids.clear()
  // (after the globals are put back: what came from outside before the run's first frame, posted here, would be lost
  // with them, and the first frame drawn without it: the system's bars round an edge-to-edge window)
  if run is Some(r) {
    env_before_frames(f, r)
  }
  // (the words drawn kept a line at a time, for Tester::text_runs)
  text_runs.on = true
  match text {
    Some(lines) => text_table.val = Some(text_table_of(lines))
    None => ()
  }
  if stable {
    bench.mode = -1
  }
  fx_reset(seed)
  // (the run begun: what the test sets for it, before its first frame is made or drawn)
  if begun is Some(set) {
    set()
  }
  // (the window a tree made once: `tree`, the view under test the old frame around its old views; else the view its
  // one old view: view_host.mbt)
  match tree {
    Some(make) => set_view_app(make, around=view)
    None => set_view_app(fn(root) { old(root, view).grow(Is(1.0)) |> ignore })
  }
  let between = test_frames_between()
  tester_rested.clear()
  frames_at_one.val = (-1.0, 0)
  let t = { fake: f, w, h, frames: 0, seed, origin: time, period: frame_period_default, times: [], between, on_way: false, motion: test_motion_judged(loc.to_string()), host_frames: false, inputs_next: @double.infinity, each: None, before }
  // a host's run replayed: its first frame where the host drew it (its first DRAWHASH), the display's frames from
  // there; else the display's first frame after `time`
  match run.bind(run_first_frame) {
    Some(at) => {
      t.origin = at
      t.frame_at(at)
    }
    None => t.frame_at(time + first_frame_ms)
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
/// Images the host could not decode, by the id it gave them. `image_src` says each one's source. Unlike `pending`,
/// these will not become ready; a picture exporter can refuse to write an incomplete image.
pub fn Tester::failed_images(self : Tester) -> Array[Int] {
  let ids = self.fake.images.keys().collect()
  ids.sort()
  ids.filter(fn(id) {
    match self.fake.images.get(id) {
      Some(im) => im.state < 0
      None => false
    }
  })
}

///|
/// Failed decodes needed to draw the last painted frame, by the host's image id. A failure kept in the cache for a
/// picture no longer in the frame is not one of these. `image_src` gives the source of each id.
pub fn Tester::failed_images_drawn(self : Tester) -> Array[Int] {
  self.reads_own()
  ignore(self)
  frame_failed_images.copy()
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
  // (a view's: how it stands changed with it, as a host tells it)
  if kind == 2 {
    on_outside(outside_stood, id, 0)
  }
}

///|
/// What the fake host finished, in the order it did ((kind, id): Tester::finish).
pub fn Tester::finished_order(self : Tester) -> Array[(Int, Int)] {
  self.fake.finished.copy()
}

///|
/// What the app awaits from the host, as effect.mb's outside says it (what it is), oldest first.
pub fn Tester::awaited(self : Tester) -> Array[String] {
  self.reads_own()
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
/// Whether how what moves goes from frame to frame is judged on the frame being drawn (words_over.mbt, rows_steady.mbt,
/// sizes_steady.mbt: a step, a dead stop, words over words): on a display's own, 60 a second or more, and not on a
/// frame of a run at a rate (MBUI_TEST_FPS, scripts/fps_check.sh), whose frames are not the default run's. Such a run holds only that what a
/// test asserts at its moments is the same however many frames came between; its judging is the default run's, on the
/// same frames (the user, 2026-11-09: 7/24 帧只比结果；fps 跑法只比结果，平滑度另开一条线).
/// A run that judges motion (MBUI_TEST_MOTION, test_motion_judged) judges those too, at a display's rate (60 a second
/// or more): every frame a host at that rate draws while something moves.
pub fn Tester::judges_motion(self : Tester) -> Bool {
  // (a run whose frames are not judged: Tester::frames_unjudged; nor how what moves goes: Tester::motion_unjudged)
  if looks_unjudged.val || motion_unjudged.val {
    return false
  }
  if self.between > 0.0 {
    // (a run at a rate: none of its frames where it holds results only, its other frames (an input's, what is due)
    // not the default run's either; every one where it judges motion)
    self.motion != Results && self.between <= frame_period_default + 1.0e-9 && self.period <= frame_period_default + 1.0e-9
  } else {
    self.period <= frame_period_default + 1.0e-9
  }
}

///|
/// Whether this test program runs at a rate (MBUI_TEST_FPS, scripts/fps_check.sh): frames drawn on run_for's way. A
/// test that walks its frames itself (`frame()`, the display's at any rate) to judge how what moves goes from frame to
/// frame (send_steady_wbtest.mbt) is the default run's alone: at a rate it draws the very same frames and would only
/// repeat itself (the user, 2026-11-09: 逐帧平滑度测试只在默认帧率跑).
pub fn test_at_a_rate() -> Bool {
  test_frames_between() > 0.0
}

///|
/// How far apart the frames motion is judged on are (ms): the display's, or a run's that judges motion on its frames
/// on run_for's way, closer (Tester::judges_motion).
fn Tester::motion_period(self : Tester) -> Double {
  if self.motion != Results && self.between > 0.0 && self.between < self.period {
    self.between
  } else {
    self.period
  }
}

///|
/// What a run at a frame rate holds of a motion (test_motion_judged): only results, the default's; how it goes frame to
/// frame on run_for's way too, a fault failing its test; or that, each fault said and none failing.
// Judge is made by tester_fps.mbt, a file of every target but wasm
#warnings("-unused_constructor")
#derive(Eq)
pub enum MotionJudged {
  Results
  Judge
  Count
}

///|
/// The files whose Testers a run that counts motion only counts (test_motion_judged), not judges.
// kept across runs: said once as a test program starts (its packages' `init`)
let motion_counted_files : Set[String] = Set([])

///|
/// The files whose Testers still show faults of how what moves goes at 60 or 120 a second (MBUI_TEST_MOTION `count`,
/// what CI's runs counted): only counted there, every other file judged. Said by a test package as it starts
/// (`fn init`); only shrinks: a file mended to none leaves the list.
pub fn motion_counted(files : Array[String]) -> Unit {
  if motion_runs() {
    for f in files {
      println("MOTION counted \{f}")
    }
  }
  for f in files {
    motion_counted_files.add(f)
  }
}

///|
/// When a Tester's first frame is drawn, after its `time`: the app's first frame, as a 60 Hz display's first would be,
/// whatever the display's period (Tester::set_frame_period): what happens at the app's start happens at the same
/// moment at any frame rate.
pub let first_frame_ms : Double = 1000.0 / 60.0

///|
/// Draws one frame, at the display's first frame `ms` or more on (by default, and at the least, the next one): frames
/// come only at the display's vsync (Tester::set_frame_period, set_frame_times), as on a host.
/// A frame as a host's: what the clock and what was said (an input, a signal set, a host's or the core's word) bring,
/// drawn as the host draws it (parts kept, the scene's layers copied), nothing else taken as changed. A test that
/// changed what is no signal (a made-up core's state, a page opened by hand) says so first (Tester::stepped).
pub fn Tester::frame(self : Tester, ms? : Double = 0.0) -> Unit {
  self.clock_frame(ms~)
}

///|
/// What the test changed of what is no signal (a made-up core's state, a page opened by hand), said: taken at the next
/// frame as an event from outside is, built whole (frame_watch.mbt). Said by the step that changed it, not by every
/// frame: a frame by itself is a host's (Tester::frame).
pub fn Tester::stepped(self : Tester) -> Unit {
  ignore(self)
  test_stepped()
}

///|
/// The display's next frame (Tester::frame), nothing said changed: what the time alone does.
fn Tester::clock_frame(self : Tester, ms? : Double = 0.0) -> Unit {
  let next = self.tick_after(self.fake.time)
  let want = self.fake.time + ms
  if ms > 0.0 && !self.host_frames {
    // a moment the test says: drawn there, whatever the display's frames
    self.frame_at(self.on_grid(want))
  } else {
    self.frame_at(self.at_due(if want > next { self.tick_at(want) } else { next }))
  }
}

///|
/// A display's frame at `t`, or the moment something is due at (Tester::next_due: a wake, a motion's end) where that
/// is a hair after it (within `due_hair`): the same moment summed one way or another, drawn at what is due, not a hair
/// before it, where what ends then has not (a fade's end 5e-13 ms after the frame a grid of 7 a second put there: the
/// frame drawn of its looks alone kept what the whole build let go). What is due a hair before the frame is past at it:
/// the frame stays on the grid, the same double whatever is due (an old view's list and the window's tree's, each its
/// own ease's end summed from its own moments: list_scroll_same_wbtest). run_for's on_grid holds the same the other way.
fn Tester::at_due(self : Tester, t : Double) -> Double {
  let due = self.next_due()
  if due > self.fake.time && due > t && due - t < due_hair {
    due
  } else {
    t
  }
}

///|
/// How near (ms) a frame and what is due are the same moment (Tester::at_due, run_for's frames on the way): a moment
/// summed one way or another.
let due_hair : Double = 1.0e-6

///|
/// The display's first frame after `t` (Tester::frame): of its frames' times (set_frame_times) while they last, else on
/// its period (a moment a hair short of one of its frames, grid_hair, that frame's own).
fn Tester::tick_after(self : Tester, t : Double) -> Double {
  match self.times.search_by(fn(f) { f > t }) {
    Some(i) => self.times[i]
    None => {
      if t == @double.infinity {
        return t
      }
      // (counted on the frames' times as they are summed, not by dividing a moment back into periods: on a clock of days,
      // as a device's frames' is from its start, a frame's own time divided comes out short of its count by more than
      // the hair, and the frame after it would be that frame again: frames after it never drawn)
      let hair = grid_hair * self.period
      let mut k = ((t - self.origin) / self.period).floor() - 1.0
      while grid_moment(self.origin, k, self.period) <= t + hair {
        k = k + 1.0
      }
      grid_moment(self.origin, k, self.period)
    }
  }
}

///|
/// How far short of one of the display's frames a moment may be and be that frame's (a share of its period): a moment
/// summed one way or another.
let grid_hair : Double = 1.0e-9

///|
/// How many of the display's frames fall after `from` and at or before `to`, on its frames' times (Tester::tick_after):
/// what was drawn between two moments (a replay's first screen, Flow::until_at).
pub fn Tester::frames_between(self : Tester, from : Double, to : Double) -> Int {
  let mut n = 0
  let mut t = self.tick_after(from)
  while t <= to + grid_hair * self.period {
    n = n + 1
    t = self.tick_after(t)
  }
  n
}

///|
///|
/// The display's first frame at or after `t`.
fn Tester::tick_at(self : Tester, t : Double) -> Double {
  match self.times.search_by(fn(f) { f >= t }) {
    Some(i) => self.times[i]
    None => {
      if t == @double.infinity {
        return t
      }
      // (counted on the frames' times, as tick_after)
      let hair = grid_hair * self.period
      let mut k = ((t - self.origin) / self.period).floor() + 2.0
      while grid_moment(self.origin, k - 1.0, self.period) >= t - hair {
        k = k - 1.0
      }
      grid_moment(self.origin, k, self.period)
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
/// When what is posted now is taken: the frame drawn for it, at this moment (Tester::draw, run_for: what comes at a
/// time is drawn at it); a host's run's frames (set_frame_times, set_frame_period): its next.
pub fn Tester::taken_at(self : Tester) -> Double {
  if self.host_frames {
    self.tick_after(self.fake.time)
  } else {
    self.fake.time
  }
}

///|
/// The display's first frame at or after `t` on the clock: where a test sees what is so at `t` (a deadline, a motion's
/// end), as a host shows it. Never a moment before `t`: where the display's frame is a hair short of it (tick_at's
/// grid_hair, a moment summed one way or another), `t` itself, as at_due draws what is due a hair after a frame. Drawn
/// at that frame, what comes at `t` has not come (a clock's next second worked out as a few last bits past the frame:
/// emit_kept_wbtest), the app asks for `t` again, and a host's frames put where it asks never go on
/// (tester_display_frame_wbtest).
pub fn Tester::display_frame(self : Tester, t : Double) -> Double {
  let tick = self.tick_at(t)
  if tick < t {
    t
  } else {
    tick
  }
}

///|
/// The display's frame period from now on (ms; a run's own, as its tape says it), its frames counted from now (frames'
/// times set before let go).
pub fn Tester::set_frame_period(self : Tester, ms : Double) -> Unit {
  self.origin = self.fake.time
  self.period = ms
  self.times = []
  self.host_frames = true
}

///|
/// What is wrong with `times` as the frames' times set_frame_times is given (a time not later than now, or than the one
/// before it), said; None where nothing is. The words set_frame_times stops with: the two are one asking.
pub fn Tester::frame_times_wrong(self : Tester, times : Array[Double]) -> String? {
  let mut before = self.fake.time
  for i, at in times {
    if !(at > before) {
      return Some(
        "Tester::set_frame_times: time \{i} (\{at}) is not later than " +
        (if i == 0 { "now (\{before})" } else { "the one before it (\{before})" }),
      )
    }
    before = at
  }
  None
}

///|
/// The display's frames from now on at `times` (ms on the frames' clock, each later than the one before and than now):
/// a run's own, as its tape had them, where every frame the Tester draws comes (an input's, run_for's, draw's); after
/// the last, on the frame period from it. Grid and tape are one: the period's frames a table of times evenly apart.
pub fn Tester::set_frame_times(self : Tester, times : Array[Double]) -> Unit {
  match self.frame_times_wrong(times) {
    Some(s) => @halt.saying(s)
    None => ()
  }
  self.times = times.copy()
  self.host_frames = true
  if times.length() > 0 {
    self.origin = times[times.length() - 1]
  }
}

///|
/// The waits asked without their own `since` that count from no cause, from the frame's moment as it began, or from
/// the latest of several (Ctx::held, wait_look): said as MOTION lines, each a place to give its `since` or to make a node.
fn wait_looked(kind : String, loc : SourceLoc, causes : Array[(Double, String)]) -> Unit {
  println("MOTION \{kind} \{sizes_steady.file}: \{loc} [\{causes.map(fn(c) { "(\{c.0}, \{c.1})" }).join(", ")}]")
}

///|
/// Draws one frame at `at` on the clock, whatever the display's frames (a host's run replayed: where it drew). Stops,
/// saying so, on frames_at_one_most of them one after another at one moment while the app waits for a later one
/// (Tester::frame_at_said).
pub fn Tester::frame_at(self : Tester, at : Double) -> Unit {
  match self.frame_at_said(at) {
    Some(s) => @halt.saying(s)
    None => ()
  }
  self.frame_shown_at(at, at)
}

///|
/// The moment of the last frames frame_at drew one after another at one moment while the app waited for a later one,
/// and how many.
// kept across runs: put back by each Tester (Tester::new)
let frames_at_one : Ref[(Double, Int)] = Ref((-1.0, 0))

///|
/// How many frames one after another at one moment, the app waiting for a later one, are frames that do not go on
/// (Tester::frame_at_said): a test draws such a frame a few times (to look at it again), never so many.
let frames_at_one_most = 1000

///|
/// What is wrong with a frame at `at` after those frame_at drew before it, said (frame_at stops on it; None where
/// nothing is): frames_at_one_most one after another at one moment, the app asking for none there but a wake at a later
/// moment (Tester::wanted_after; an input, a change or a frame asked for counts afresh). Frames put where the app asks
/// (wanted_after, display_frame) that never come to what it waits for: a test walking them would go on for ever, the
/// moment it waits for never there.
fn Tester::frame_at_said(self : Tester, at : Double) -> String? {
  let w = self.wanted_next()
  let (was, n) = frames_at_one.val
  let n = if at == was && w > at && w < @double.infinity { n + 1 } else { 1 }
  frames_at_one.val = (at, n)
  if n < frames_at_one_most {
    return None
  }
  Some(
    "Tester::frame_at: \{n} frames one after another at \{at}, the clock moved on by none: the app asks for its next " +
    "at \{w} (\{self.wanted_why()})" +
    (if w > at && w < @double.infinity { ", the display's frame for it \{self.display_frame(w)}" } else { "" }),
  )
}

///|
/// Draws one frame the host times for when it is shown, ahead of where it is: the host at `now` (the logic brought
/// there, nothing later: no step or end taken past it), what is drawn sampled at `shown` (a moment later, as a host's
/// frame is drawn for its vsync). The next events may come at any moment from `now`.
pub fn Tester::frame_shown_at(self : Tester, now : Double, shown : Double) -> Unit {
  let at = now
  // (what was posted told at its moment, and what the fake host does at its own moments up to this frame's, before the
  // clock comes there: posted_tell, FakeHost::due)
  posted_tell()
  fake_dues_to(self.fake, at)
  self.fake.time = at
  // decodes started last frame are done, the views opened are ready: the host's events for them (unless the test
  // says when: Tester::finish)
  if self.fake.auto_finish {
    for p in self.pending() {
      // (one said to take a while: done at its own moment, not before; a frame is drawn there: next_due)
      match self.fake.decode_due.get(p.1) {
        Some(due) if p.0 == 1 && due > at + 1.0e-9 => continue
        _ => ()
      }
      self.finish(p.0, p.1)
    }
  }
  // what was posted since the frame before, told as a device's host tells it, between frames, before this one begins
  // (messages.mbt: messages_between takes what changes only signals now, what is left this frame's)
  if fake_posted.length() > 0 {
    on_outside(outside_posted, 0, 0)
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
  match self.before {
    Some(f) => f()
    None => ()
  }
  self.fake_pages_run()
  // (what was said to move since the frame before, between frames (an input's handler): seen before this frame lets
  // go of what is over by its moment, tester_time.mbt)
  tester_rests_seen()
  on_frame(self.w, self.h, self.fake.scale, if shown > at { shown } else { at })
  // (a bench's measured frame ends here: what follows is the Tester's own checks of it, which a device runs not)
  bench_frame_ends()
  self.hold_a11y_whole()
  self.frames = self.frames + 1
  // (what the window's tree did in it, where a test asked: tester_tree_work.mbt)
  tree_frame_kept()
  // (each box's presses said to be another's that one's to take, where the box is: presses.mbt)
  g().check_press_owners()
  // (how what moves goes from frame to frame, judged on a display's own frames: Tester::judges_motion)
  if self.judges_motion() {
    self.hold_words_over()
    self.hold_rows_steady()
    self.hold_sizes_steady()
    self.hold_gaps_steady()
  } else if !words_over.held && !self.on_way && self.period <= frame_period_default + 1.0e-9 {
    // (where a test does not hold the rule but reads which frames show words over words: kept on a run at a rate's
    // frames as on the default's, but for those on run_for's way)
    self.hold_words_over()
  }
  self.hold_seen_whole_now()
  self.hold_corners()
  // (where the focus a key moved along comes to rest, once what moved as it did is at rest: tester_focus_off.mbt)
  self.focus_off_at_rest()
  // (what it drew was placed by the layout it drew by: tester_placed.mbt)
  self.hold_placed()
  match self.each {
    Some(f) => f()
    None => ()
  }
  // what the outside the test stands for has said meanwhile, posted for the next frame (messages.mbt)
  frame_ended_outside()
  // (what is said to move, its end as it says it, kept by the Tester for rest_of once it is over: tester_time.mbt)
  tester_rests_seen()
  // (as its host got it, where a test records it: tester_host.mbt)
  host_frame_drawn(at)
  // (what the fake host does at a moment of its own that this frame asked for at its moment (a pick, a native call
  // answered as it is asked: FakeHost::due) told as it ends, between frames, as a device's host answers after the
  // frame that asked: fake_dues_after_frame)
  fake_dues_after_frame(self.fake)
  // (a block's key's marks put back by the change that set them: left set, every structure after them at once, unsaid)
  if @view.key_marks_left() {
    @halt.saying("a list's block's key mark (key_taking, key_taken) left set after a frame at \{at}")
  }
  // (what the window's tree keeps held to what working it out whole gives, where the frame changed it: the drawing
  // order and the boxes each node lays out as the frame was presented, kept_at_present; whether each takes input as
  // the frame's own work is done, here, what the next input meets: the old frame's modal layer is told the tree as its
  // frame closes, view_frame_end, after it was presented; a scripted run's step after that, as an input between frames
  // (drive_frame), what it changes still due here, told by the frame after. Not where a bench measures its frames, as
  // kept_at_present)
  match kept_presented.val {
    Some(why) => {
      kept_presented.val = None
      @halt.saying("after the frame at \{at}, as it was presented: \{why}")
    }
    None => ()
  }
  match view_app.val {
    Some(tree) if !bench_measuring.val =>
      match tree.kept_inputs_said() {
        Some(why) => @halt.saying("after the frame at \{at}: \{why}")
        None => ()
      }
    _ => ()
  }
}

///|
/// What the window's tree keeps that working it out whole does not give, as the frame being drawn was presented
/// (kept_at_present), for the Tester's frame end to stop on: None where nothing differed.
let kept_presented : Ref[String?] = Ref(None)

///|
/// The frame presented now (FakeHost::present): what the window's tree draws by, as it keeps it, held to what working it
/// out whole gives (the drawing order and each node's boxes: view's kept_checks.mbt, Tree::kept_drawn_said), as the
/// frame stood the moment it was presented, as tester_placed.mbt holds its rule. What
/// comes after that in the same frame (a scripted run's step, drive_frame: a finger's move scrolling a list, a row put
/// in) is put in order for the frame after it, which lays it out: looked at as the frame ends, every frame of a drag
/// ended with the next one's change already committed, the order due, and two in a row stopped the run as never held
/// (#5620's bench, its list scenes: still.fail's instrbench, paged, list30, list1500). Not where a bench measures its
/// frames (Tester::bench past its `log measure`): as the bench's other checks of a frame, no work of the app's.
fn kept_at_present() -> Unit {
  if bench_measuring.val || kept_presented.val is Some(_) {
    return
  }
  match view_app.val {
    Some(tree) => kept_presented.val = tree.kept_drawn_said()
    None => ()
  }
}

///|
/// `f` run after each frame the Tester draws from now on (None: no more), the frame just drawn its draw list (what
/// drawn_order and the like read): what holds of every frame, those an input's draw goes through on its way too.
pub fn Tester::each_frame(self : Tester, f : (() -> Unit)?) -> Unit {
  self.each = f
}

///|
/// The window `w` by `h` from the next frame on, as a host lays the app out anew (above its keyboard as it comes up,
/// Tester::set_ime_inset): no frame drawn for it here.
pub fn Tester::resize_next(self : Tester, w : Double, h : Double) -> Unit {
  tester_size.val = Some((w, h))
  self.fake.wants = true
}

///|
pub fn Tester::resize(self : Tester, w : Double, h : Double) -> Unit {
  self.w = w
  self.h = h
  self.draw()
}

///|
/// What the fake host says the pointer's events come from from here on, as a machine with a touch screen beside a
/// mouse does (Windows': @hostapi.event_finger): Some(true) a finger, Some(false) a mouse; None not said (its
/// system's hand). The hand of the moment (@ui.pointing) is what the last event said.
pub fn Tester::host_says_finger(self : Tester, finger : Bool?) -> Unit {
  self.fake.event_finger = match finger {
    Some(true) => 1
    Some(false) => 0
    None => -1
  }
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
    // (a finger's moves come input_step_ms apart, whatever the display's period: each drawn as it comes)
    let at = self.fake.time + input_step_ms
    self.fake.time = at
    finger(1, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)
    self.frame_at(at)
  }
  finger(2, x1, y1)
  self.draw()
}

///|
/// How far apart a drag's moves come (ms), about: a 60 Hz display's frame, as a finger's moves reach an app.
pub let drag_step_ms : Double = 16.0

///|
/// How far apart a gesture's moves come (a drag's, a held drag's, a back gesture's): a finger's rate, as a 60 Hz
/// screen samples it, whatever the display's frame period; each move drawn as it comes.
pub let input_step_ms : Double = 1000.0 / 60.0

///|
pub fn Tester::wheel(self : Tester, x : Double, y : Double, dy : Double) -> Unit {
  finger_wheel(x, y, 0.0, dy, 0)
  self.drawn_now()
}

///|
/// What the hand does through what a press runs, done here by the test straight (`f`: a panel closed by the call its ×
/// makes): taken as the hand's at this moment, as a press is (rows_steady.mbt: what the rows do after it is its answer).
pub fn Tester::by_hand(self : Tester, f : () -> Unit) -> Unit {
  ignore(self)
  rows_steady_hand()
  f()
}

///|
/// Text committed by the input method (or typed on a hardware keyboard).
pub fn Tester::type_text(self : Tester, s : String) -> Unit {
  posted_tell()
  on_text(0, s, 0, 0)
  self.draw()
}

///|
/// The input method's composition, with the caret at its end.
pub fn Tester::compose(self : Tester, s : String) -> Unit {
  posted_tell()
  on_text(1, s, s.length(), 0)
  self.draw()
}

///|
pub fn Tester::key(self : Tester, code : Int, mods? : Int = 0) -> Unit {
  posted_tell()
  let was = g().focus
  on_key(code, mods)
  self.draw()
  self.focus_moved_held(code, mods, was)
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
/// The centre of the first text node (or editor placeholder) containing `s`. Here and in what else finds words, none
/// of a page's bones: no words are drawn there (bones.mbt).
pub fn Tester::find(self : Tester, s : String) -> (Double, Double)? {
  self.reads_own()
  let c = g()
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.bones == 0L && (n.kind == kind_text || n.kind == kind_editor || n.kind == kind_rich) &&
      n.text.contains(s) {
      return Some((n.x + n.fw / 2.0, n.y + n.fh / 2.0))
    }
  }
  // (or the words of a node of the window's tree, where it is drawn: as it is made, however faded this frame, as an
  // old view's text is found; none once let go of. What is seen is the glyphs' to say: Tester::glyphs_seen)
  match view_tree() {
    Some(tree) =>
      for d in tree.drawn() {
        // (none of a page's bones: View::bones)
        if d.bones == 0L && view_words_found(d).contains(s) {
          return Some((d.x + d.w / 2.0, d.y + d.h / 2.0))
        }
      }
    None => ()
  }
  None
}

///|
/// The centre of the last text node containing `s` (drawn last: what lies over the others, a sheet's). In the order
/// they are painted (Ctx::paint: a node, then its children; what flies over everything after all the rest), not the
/// order they were made: a list's rows are made as it is laid out, after what was built over it.
pub fn Tester::find_last(self : Tester, s : String) -> (Double, Double)? {
  self.reads_own()
  ignore(self)
  let c = g()
  let found : Ref[(Double, Double)?] = Ref(None)
  let over : Array[Int] = []
  fn walk(i : Int, overlay : Bool) -> Unit {
    if !overlay && c.drawn_entry(i) is Some(e) && e.z == z_flying {
      over.push(i)
      return
    }
    let n = c.nodes[i]
    if n.bones == 0L && (n.kind == kind_text || n.kind == kind_editor || n.kind == kind_rich) &&
      n.text.contains(s) {
      found.val = Some((n.x + n.fw / 2.0, n.y + n.fh / 2.0))
    }
    let mut k = n.first
    while k >= 0 {
      walk(k, false)
      k = c.nodes[k].next
    }
  }
  for i in 0..<c.count {
    if c.nodes[i].parent < 0 {
      walk(i, false)
    }
  }
  // (one over everything may hold another: painted after it)
  let mut j = 0
  while j < over.length() {
    walk(over[j], true)
    j += 1
  }
  match view_tree() {
    Some(tree) => for d in tree.drawn() {
      if d.bones == 0L && view_words_found(d).contains(s) {
        found.val = Some((d.x + d.w / 2.0, d.y + d.h / 2.0))
      }
    }
    None => ()
  }
  found.val
}

///|
pub fn Tester::tap_text(self : Tester, s : String) -> Unit {
  match self.find(s) {
    Some((x, y)) => self.tap(x, y)
    None => @halt.saying("no text \"\{s}\" on screen")
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
/// The floating text menu as the host was last told it (@hostapi.text_menu): shown, over (x, y, w, h), offering
/// what `can` says (@hostapi.text_menu_*).
pub fn Tester::text_menu(self : Tester) -> (Bool, Double, Double, Double, Double, Int) {
  self.fake.text_menu
}

///|
/// The words of the app's own items of the floating text menu as the host was last told them, in their order
/// (@hostapi.text_menu_own; none: none told).
pub fn Tester::text_menu_own(self : Tester) -> Array[String] {
  if self.fake.text_menu_own == "" {
    []
  } else {
    self.fake.text_menu_own.split("\n").map(fn(s) { s.to_owned() }).collect()
  }
}

///|
/// What the menu bar's editing items can do as the host was last told it (@hostapi.edit_can: text_menu_*; -1 not told).
pub fn Tester::edit_can(self : Tester) -> Int {
  self.fake.edit_can
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
/// The number on the app's icon as the app last told it (@ui.set_badge).
pub fn Tester::badge(self : Tester) -> Int {
  self.fake.badge
}

///|
/// This machine's station as its host says it from now on (@ui.local_station), "" none.
pub fn Tester::set_local_station(self : Tester, json : String) -> Unit {
  self.fake.local_station = json
}

///|
/// The font families installed here from now on, as a JSON array of their names (@ui.local_font_families); "" none.
pub fn Tester::set_local_fonts(self : Tester, json : String) -> Unit {
  self.fake.local_fonts = json
}

///|
/// A font file (by where it is) its host cannot read as a font from now on (@ui.face_add says false): one damaged, or
/// not a font.
pub fn Tester::set_unreadable_font(self : Tester, path : String) -> Unit {
  self.fake.unreadable_fonts.push(path)
}

///|
/// The family of this machine's given to face `face` last (@ui.face_add_family), "" none.
pub fn Tester::family_given(self : Tester, face : Int) -> String {
  self.fake.families_given.get(face).unwrap_or("")
}

///|
/// What was done to this machine's station (@ui.local_station_act), oldest first.
pub fn Tester::local_acts(self : Tester) -> Array[String] {
  self.fake.local_acts
}

///|
/// The keys held down from now on (@ui.mods_held: @ui.mod_alt, mod_cmd…; 0 none).
pub fn Tester::hold_mods(self : Tester, mods : Int) -> Unit {
  self.fake.mods = mods
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
/// The picture last put on the clipboard (Ctx::copy_image): its bytes' length, None when none was.
pub fn Tester::clipboard_image(self : Tester) -> Int? {
  if self.fake.clipboard_image < 0 {
    None
  } else {
    Some(self.fake.clipboard_image)
  }
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
/// Where the fake host has native view `view` now, as it was last told (view_place): the part of it seen, in the
/// window's points (x0, y0, x1, y1: its rect cut by its clip), and whether it is shown; None where it was never placed
/// or is closed.
pub fn Tester::view_stands(self : Tester, view : NativeView) -> (Double, Double, Double, Double, Bool)? {
  self.fake.view_at.get(view.id())
}

///|
/// The holes (kind 9: where a native view shows) in the last frame, as (x, y, w, h).
pub fn Tester::holes(self : Tester) -> Array[(Double, Double, Double, Double)] {
  self.reads_own()
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
/// The holes' corners in the last frame (kind 9, in the order of holes): 0 square, else their radius.
pub fn Tester::hole_radii(self : Tester) -> Array[Double] {
  self.reads_own()
  ignore(self)
  let out = []
  for i in 0..<g().ninst {
    let b = i * inst_size
    if g().inst[b + 5] == 9.0 {
      out.push(g().inst[b + 4])
    }
  }
  out
}

///|
/// The same, each corner its own (top left, then round it: an instance's 36-39).
pub fn Tester::hole_corners(self : Tester) -> Array[(Double, Double, Double, Double)] {
  self.reads_own()
  ignore(self)
  let out = []
  for i in 0..<g().ninst {
    let b = i * inst_size
    if g().inst[b + 5] == 9.0 {
      out.push((g().inst[b + 36], g().inst[b + 37], g().inst[b + 38], g().inst[b + 39]))
    }
  }
  out
}

///|
/// What each hole in the last frame shows of its view (kind 9, in the order of holes): the view's id (its image less
/// @hostapi.view_tex_base) and the part of its content there (u0, v0, du, dv: shares of the content's rect), as a host
/// that draws the view's picture draws it.
pub fn Tester::hole_parts(self : Tester) -> Array[(Int, Double, Double, Double, Double)] {
  self.reads_own()
  ignore(self)
  let out = []
  for i in 0..<g().ninst {
    let b = i * inst_size
    let a = g().inst
    if a[b + 5] == 9.0 {
      out.push(
        (
          a[b + 20].to_int() - @hostapi.view_tex_base,
          a[b + 12],
          a[b + 13],
          a[b + 14],
          a[b + 15],
        ),
      )
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
pub fn Tester::dump(_self : Tester) -> String {
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
/// The images the old views built in the last frame (Ctx::image), each its source and its size as laid out, drawn or
/// not (none decoded yet, faded out): what an old view asked to be shown.
pub fn Tester::image_nodes(self : Tester) -> Array[(String, Double, Double)] {
  self.reads_own()
  ignore(self)
  let c = g()
  let out = []
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.kind == kind_image {
      out.push((n.text, n.fw, n.fh))
    }
  }
  out
}

///|
/// The words drawn now, as another app's frame is compared with this one's (still.fail's apps/mbui tape.mbt): each
/// text node's words, where its top left is drawn (moved by its own look and its ancestors': Ctx::drawn_at), its size
/// as laid out, and how opaque it is drawn (its and its ancestors' opacities and looks' alphas, multiplied).
pub fn Tester::words(self : Tester) -> Array[(String, Double, Double, Double, Double, Double)] {
  self.reads_own()
  self.words_marked().map(fn(w) { w.0 })
}

///|
/// Tester::words' words, each with whether nothing of it is read out (an old view's made where nothing is,
/// Ctx::hidden_from_semantics; a node of the window's tree under a modal layer it is not in, or kept from what is read
/// out: Tree::reads_out): one list, so the two never part.
fn Tester::words_marked(self : Tester) -> Array[((String, Double, Double, Double, Double, Double), Bool)] {
  ignore(self)
  let c = g()
  let out = []
  // (in the box of an old view let go since the old frame was built: not drawn, though its nodes are there till the old
  // frame is built again (a frame drawn by the window's tree alone, or painted alone, builds none))
  let let_go = fn(i : Int) {
    let mut p = i
    let mut gone = false
    while p >= 0 && !gone {
      if old_box_owners.get(p) is Some((_, id)) {
        gone = !old_islands.iter().any(fn(o) { o.id == id })
      }
      p = c.nodes[p].parent
    }
    gone
  }
  for i in 0..<c.count {
    let n = c.nodes[i]
    // (a field's placeholder too, as Android's hint is words of their own)
    if n.bones == 0L &&
      (n.kind == kind_text || n.kind == kind_rich || n.kind == kind_editor) &&
      n.text != "" &&
      !let_go(i) {
      let (x, y) = c.drawn_at(i)
      let mut alpha = 1.0
      let mut p = i
      while p >= 0 {
        alpha = alpha * c.nodes[p].opacity
        match c.drawn_entry(p) {
          Some(e) => alpha = alpha * e.look_now().alpha
          None => ()
        }
        p = c.nodes[p].parent
      }
      out.push(((n.text, x, y, n.fw, n.fh, alpha), n.sem_hid))
    }
  }
  // (and the words of the window's tree's nodes, where and as faded as they are drawn, as Tester::find finds them)
  match view_tree() {
    Some(tree) =>
      for d in tree.drawn() {
        // (a field's placeholder too, its hint: view_words_found)
        let words = view_words_found(d)
        if words != "" && d.bones == 0L {
          out.push(((words, d.x, d.y, d.w, d.h, d.alpha), !tree.reads_out(d.id)))
        }
      }
    None => ()
  }
  out
}

///|
/// The words Tester::words has of the app's own nodes, but those made where nothing is read out (Ctx::hidden_from_semantics:
/// a picture drawn small to stand for itself, say), as a person reading the screen out would have them.
pub fn Tester::words_said(self : Tester) -> Array[(String, Double, Double, Double, Double, Double)] {
  self.reads_own()
  self.words_marked().filter(fn(w) { !w.1 }).map(fn(w) { w.0 })
}

///|
/// The rectangle of the first node whose text contains `s` (x, y, w, h).
pub fn Tester::rect_of(self : Tester, s : String) -> (Double, Double, Double, Double)? {
  self.reads_own()
  let c = g()
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.bones == 0L && (n.kind == kind_text || n.kind == kind_rich || n.kind == kind_editor) &&
      n.text.contains(s) {
      return Some((n.x, n.y, n.fw, n.fh))
    }
  }
  // (or the words of a node of the window's tree, where it is drawn, as Tester::find finds them)
  match view_tree() {
    Some(tree) =>
      for d in tree.drawn() {
        if d.bones == 0L && view_words_found(d).contains(s) && d.alpha > 0.0 {
          return Some((d.x, d.y, d.w, d.h))
        }
      }
    None => ()
  }
  None
}

///|
/// Visible list rows: (item, y, height), top to bottom.
pub fn Tester::rows(self : Tester) -> Array[(Int, Double, Double)] {
  self.reads_own()
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
/// Each list's visible rows' boxes (x, y, width, height), top to bottom, list by list as they were built.
pub fn Tester::list_row_boxes(self : Tester) -> Array[Array[(Double, Double, Double, Double)]] {
  self.reads_own()
  ignore(self)
  let c = g()
  let out = []
  for i in 0..<c.count {
    if c.nodes[i].kind == kind_list {
      let rows = []
      let mut r = c.nodes[i].first
      while r >= 0 {
        let n = c.nodes[r]
        rows.push((n.x, n.y, n.fw, n.fh))
        r = n.next
      }
      out.push(rows)
    }
  }
  out
}

///|
/// The lines of the first text node whose text contains `s`, as laid out (an old view's, else a node's of the window's tree).
pub fn Tester::lines_of(self : Tester, s : String) -> Array[String] {
  self.reads_own()
  let c = g()
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.bones == 0L && n.kind == kind_text && n.text.contains(s) {
      match n.tl {
        Some(tl) =>
          return Array::makei(tl.line_start.length(), fn(l) {
            let (a, b) = tl.line_range(l)
            tl.text.unsafe_substring(start=a, end=b)
          })
        None => ()
      }
    }
    if n.bones == 0L && n.kind == kind_rich && n.text.contains(s) {
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
  // (or the words of a node of the window's tree, as it draws them (shorter ones in their place where it says them:
  // View::shorter, none of them where they are none): laid out as the tree lays them out at its width,
  // view_words_measure's; on one line too long for it, or on more than it says it is drawn on, cut with an ellipsis as it
  // is drawn)
  match view_tree() {
    Some(tree) => {
      let found : Ref[Array[String]?] = Ref(None)
      tree.each_drawn(fn(d, _, _, alpha) {
        guard found.val is None && d.bones == 0L && alpha > 0.0 && d.words.contains(s) else { return }
        let shown = d.words_drawn.unwrap_or(d.words)
        if shown == "" {
          found.val = Some([])
          return
        }
        let look = d.words_look
        let scale = tree.words_scale_of(d.id)
        let tl = layout_words(
          view_words_set(shown, look, d.words_breaks),
          view_sp(scale, look.size),
          look.weight,
          if look.wrap { d.w } else { 1.0e9 },
          look.wrap,
          balance=look.balance,
          line=view_line(scale, look),
          spacing=view_spacing(scale, look),
          style=view_words_style(),
          max_lines=look.max_lines,
        )
        let lines = Array::makei(tl.line_start.length(), fn(l) {
          let (a, b) = tl.line_range(l)
          tl.text.unsafe_substring(start=a, end=b)
        })
        if !look.wrap && tl.w > d.w + 0.5 && lines.length() > 0 {
          lines[lines.length() - 1] = lines[lines.length() - 1] + "…"
        }
        found.val = Some(lines)
      })
      if found.val is Some(lines) {
        return lines
      }
    }
    None => ()
  }
  []
}

///|
/// The pointer moved to (x, y), no button down.
pub fn Tester::move_to(self : Tester, x : Double, y : Double) -> Unit {
  finger(1, x, y)
  self.drawn_now()
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
  @halt.saying("no list on screen")
}

///|
/// The context the view is built in (between frames: for what a view would
/// call on it while building, as Ctx::list_moved).
pub fn Tester::ctx(self : Tester) -> Ctx {
  self.reads_own()
  ignore(self)
  g()
}

///|
/// Scrolls the (first) list so that row `item` starts at its top, from the
/// next frame on.
pub fn Tester::scroll_to(self : Tester, item : Int) -> Unit {
  self.list_state().scroll_to(item)
  // (the list put there by the test, no hand on it: taken at the next frame as a step of the test's, built whole)
  test_stepped()
}

///|
pub fn Tester::scroll_to_end(self : Tester) -> Unit {
  self.list_state().scroll_to_end()
  test_stepped()
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
  self.reads_own()
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
        @halt.saying("no key \{name}")
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
/// The system's back as a host hands it on (host_native.mbt set_back) at `at`, its own time said with it, no frame drawn:
/// `kind` 0 its gesture begun, 1 moved to `x` (from the edge it came from), 2 gone back (a back with no gesture where none
/// began), 3 called off.
pub fn Tester::back_raw(self : Tester, kind : Int, x : Double, at : Double) -> Unit {
  self.fake.event_at = at
  on_back(kind, x, if kind == 2 { 1.0 } else { 0.0 }, 0)
  self.fake.event_at = -1.0
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
    let at = self.fake.time + input_step_ms
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
/// A touch screen's finger as a host hands it on (touches.mbt): `phase` 0 down, 1 moved, 2 up, 3 called off, `id` the
/// system's for that finger, at `at` (its own time, said with it: @hostapi.event_time).
pub fn Tester::touch_raw(self : Tester, phase : Int, id : Int, x : Double, y : Double, at : Double) -> Unit {
  self.fake.event_at = at
  on_pointer(10 + phase, x, y, id)
  self.fake.event_at = -1.0
}

///|
/// A finger's event (Tester::touch's) that happened at `at`, taken now, later (the host's clock past it): as a host hands
/// on an event it got a while before, its own time said with it (@hostapi.event_time).
pub fn Tester::touch_at(self : Tester, kind : Int, x : Double, y : Double, at : Double) -> Unit {
  self.fake.event_at = at
  finger(kind, x, y)
  self.fake.event_at = -1.0
}

///|
/// The URLs the app handed to the system (Ctx::open_url), oldest first.
pub fn Tester::opened(self : Tester) -> Array[String] {
  self.fake.opened
}

///|
/// The clock moves on `ms`, no frame drawn.
pub fn Tester::advance(self : Tester, ms : Double) -> Unit {
  posted_tell()
  fake_dues_to(self.fake, self.fake.time + ms)
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
/// Whether the host was told the last wheel zoomed something of the app's (@hostapi.wheel_kept): a browser's page
/// zooms by one that did not.
pub fn Tester::wheel_kept(self : Tester) -> Bool {
  self.fake.wheel_kept
}

///|
/// How many times the app asked its host to show the window it held (@hostapi.window_show).
pub fn Tester::window_shows(self : Tester) -> Int {
  self.fake.window_shows
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
    // (a finger's moves come input_step_ms apart, whatever the display's period: each drawn as it comes)
    let at = self.fake.time + input_step_ms
    self.fake.time = at
    finger(1, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)
    self.frame_at(at)
  }
}

///|
/// The finger held down (Tester::hold_drag) moved on to (x, y), a gesture's move later (input_step_ms), drawn as it
/// comes: one frame.
pub fn Tester::hold_move(self : Tester, x : Double, y : Double) -> Unit {
  let at = self.fake.time + input_step_ms
  self.fake.time = at
  finger(1, x, y)
  self.frame_at(at)
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
/// A keyboard plugged in from now on, or taken away (@ui.keyboard).
pub fn Tester::set_keyboard(self : Tester, on : Bool) -> Unit {
  self.fake.keyboard = on
}

///|
/// The device's performance record from now on (@hostapi.perf_state): -1 none kept here (as a Tester starts), 0 one
/// kept but off, 1 on.
pub fn Tester::set_perf(self : Tester, state : Int) -> Unit {
  self.fake.perf = state
}

///|
/// Whether the performance record's folder can be opened from now on (@hostapi.perf_opens: a host with no share sheet).
pub fn Tester::set_perf_opens(self : Tester, opens : Bool) -> Unit {
  self.fake.perf_opens = opens
}

///|
/// How many times the app opened the performance record's folder (@hostapi.perf_open).
pub fn Tester::perf_opened(self : Tester) -> Int {
  self.fake.perf_opened
}

///|
/// How many bytes the performance record's files have from now on (@hostapi.perf_size), told as a host tells it wrote
/// them (its event: hostcall.mbt's on_outside, outside_perf).
pub fn Tester::set_perf_size(self : Tester, bytes : Double) -> Unit {
  self.fake.perf_bytes = bytes
  on_outside(outside_perf, 0, 1)
}

///|
/// What the app said of the device's performance record: each @hostapi.set_perf (on or off), oldest first; and the
/// lines it wrote into it while it was on (@hostapi.perf_line).
pub fn Tester::perf_said(self : Tester) -> (Array[Bool], Array[String]) {
  (self.fake.perf_sets, self.fake.perf_lines)
}

///|
/// The system asks for less transparency from now on, or no longer.
pub fn Tester::set_reduce_transparency(self : Tester, on : Bool) -> Unit {
  host_setting_set("set_reduce_transparency")
  self.fake.reduce_transparency = on
}

///|
/// The glass drawn in the last frame: (x, y, w, h, kind (5 frosted, 6
/// liquid), the capture it shares (1, 2, …)).
pub fn Tester::drawn_glass(self : Tester) -> Array[(Double, Double, Double, Double, Int, Int)] {
  self.reads_own()
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
/// The same glass as far as it is drawn: its rect cut to its clip (a box over it that cuts it off, a sheet's foot),
/// (x, y, w, h); none where nothing of it is left.
pub fn Tester::drawn_glass_cut(self : Tester) -> Array[(Double, Double, Double, Double)] {
  self.reads_own()
  ignore(self)
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    let kind = c.inst[b + 5].to_int()
    if kind == 5 || kind == 6 {
      let (x, y, w, h) = (c.inst[b], c.inst[b + 1], c.inst[b + 2], c.inst[b + 3])
      let (cx0, cy0, cx1, cy1) = (c.inst[b + 16], c.inst[b + 17], c.inst[b + 18], c.inst[b + 19])
      let x0 = if cx1 > cx0 { dmax(x, cx0) } else { x }
      let y0 = if cy1 > cy0 { dmax(y, cy0) } else { y }
      let x1 = if cx1 > cx0 { dmin(x + w, cx1) } else { x + w }
      let y1 = if cy1 > cy0 { dmin(y + h, cy1) } else { y + h }
      if x1 > x0 && y1 > y0 {
        out.push((x0, y0, x1 - x0, y1 - y0))
      }
    }
  }
  out
}

///|
/// The same glass with its corner, the roundest of its four: (x, y, w, h, corner).
pub fn Tester::drawn_glass_corners(self : Tester) -> Array[(Double, Double, Double, Double, Double)] {
  self.reads_own()
  ignore(self)
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    let kind = c.inst[b + 5].to_int()
    if kind == 5 || kind == 6 {
      out.push((c.inst[b], c.inst[b + 1], c.inst[b + 2], c.inst[b + 3], c.inst[b + 4]))
    }
  }
  out
}

///|
/// Whether each glass of the last frame (drawn_glass's order) frosts only what is under its own box (Glass's
/// `contained`: its blur said below 0).
pub fn Tester::drawn_glass_contained(self : Tester) -> Array[Bool] {
  self.reads_own()
  ignore(self)
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    let kind = c.inst[b + 5].to_int()
    if kind == 5 || kind == 6 {
      out.push(c.inst[b + 7] < 0.0)
    }
  }
  out
}

///|
/// The notches cut into the last frame's rectangles and frosted glass (Ctx::box `notch_r`): (kind (0 a rectangle, 5
/// glass), its top, its circle's middle below the top, its radius, its fillets').
pub fn Tester::drawn_notches(self : Tester) -> Array[(Int, Double, Double, Double, Double)] {
  self.reads_own()
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
  self.reads_own()
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
  self.reads_own()
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
/// The same rectangles with their corners, each its own (top left, then round it: an instance's 36-39).
pub fn Tester::drawn_rect_corners(
  self : Tester,
) -> Array[(Double, Double, Double, Double, Int64, (Double, Double, Double, Double))] {
  self.reads_own()
  let rs = self.drawn_rects()
  let out = []
  let c = g()
  let mut j = 0
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 0.0 {
      let r = rs[j]
      out.push((r.0, r.1, r.2, r.3, r.4, (c.inst[b + 36], c.inst[b + 37], c.inst[b + 38], c.inst[b + 39])))
      j += 1
    }
  }
  out
}

///|
/// The shadows drawn in the last frame (a blurred shape, kind 2): (x, y, w, h, its corner, its blur, colour
/// RRGGBBAA with its opacity applied). One of no opacity left (under half a step of 255) draws nothing and is none: a
/// shadow's last frame as what casts it goes, the frame its card was gone in.
pub fn Tester::drawn_shadows(self : Tester) -> Array[(Double, Double, Double, Double, Double, Double, Int64)] {
  self.reads_own()
  ignore(self)
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 2.0 {
      let ch = fn(v : Double) { (v * 255.0).round().to_int64() }
      let color = (ch(c.inst[b + 8]) << 24) |
        (ch(c.inst[b + 9]) << 16) |
        (ch(c.inst[b + 10]) << 8) |
        ch(c.inst[b + 11])
      if (color & 0xFFL) != 0L {
        out.push((c.inst[b], c.inst[b + 1], c.inst[b + 2], c.inst[b + 3], c.inst[b + 4], c.inst[b + 7], color))
      }
    }
  }
  out
}

///|
/// The glyphs drawn in the last frame: (x, y, colour).
pub fn Tester::drawn_glyphs(self : Tester) -> Array[(Double, Double, Int64)] {
  self.reads_own()
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
/// What shows of each glyph drawn in the last frame (seen at all: not wholly cut by its clip): its picture's box (x0,
/// y0, x1, y1) cut by its clip.
pub fn Tester::glyphs_shown(self : Tester) -> Array[(Double, Double, Double, Double)] {
  self.reads_own()
  ignore(self)
  let c = g()
  let a = c.inst
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if a[b + 5] == 1.0 && a[b + 11] > 0.0 {
      let x0 = dmax(a[b], a[b + 16])
      let y0 = dmax(a[b + 1], a[b + 17])
      let x1 = dmin(a[b] + a[b + 2], a[b + 18])
      let y1 = dmin(a[b + 1] + a[b + 3], a[b + 19])
      if x1 > x0 && y1 > y0 {
        out.push((x0, y0, x1, y1))
      }
    }
  }
  out
}

///|
/// Each glyph drawn in the last frame (seen at all) as it is drawn: its picture's box and the clip it is cut by (x0, y0,
/// x1, y1 each), for what asks where words show within what cuts them (a column that scrolls).
pub fn Tester::glyph_clips(self : Tester) -> Array[((Double, Double, Double, Double), (Double, Double, Double, Double))] {
  self.reads_own()
  ignore(self)
  let c = g()
  let a = c.inst
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if a[b + 5] == 1.0 && a[b + 11] > 0.0 {
      out.push(((a[b], a[b + 1], a[b] + a[b + 2], a[b + 1] + a[b + 3]), (a[b + 16], a[b + 17], a[b + 18], a[b + 19])))
    }
  }
  out
}

///|
/// What of each glyph drawn in the last frame is seen (glyphs_shown's), but for those whose middle something drawn
/// after them hides (a fill nearly whole, a picture, glass: words_over_hides): what a person can read.
pub fn Tester::glyphs_seen(self : Tester) -> Array[(Double, Double, Double, Double)] {
  self.reads_own()
  ignore(self)
  let c = g()
  let a = c.inst
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if a[b + 5] == 1.0 && a[b + 11] > 0.0 {
      let x0 = dmax(a[b], a[b + 16])
      let y0 = dmax(a[b + 1], a[b + 17])
      let x1 = dmin(a[b] + a[b + 2], a[b + 18])
      let y1 = dmin(a[b + 1] + a[b + 3], a[b + 19])
      if x1 > x0 && y1 > y0 {
        let px = (x0 + x1) / 2.0
        let py = (y0 + y1) / 2.0
        let mut hidden = false
        for j in (k + 1)..<c.ninst {
          if words_over_hides(a, j, px, py) {
            hidden = true
            break
          }
        }
        if !hidden {
          out.push((x0, y0, x1, y1))
        }
      }
    }
  }
  out
}

///|
/// The rich paragraph whose text contains `s`, as laid out, and where it
/// is (its content's top left).
pub fn Tester::rich_of(self : Tester, s : String) -> (RichLayout, Double, Double)? {
  self.reads_own()
  ignore(self)
  let c = g()
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.bones == 0L && n.kind == kind_rich && n.text.contains(s) {
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
/// (x, y, w, h). An old view's paragraph, else a node of the window's tree's words in pieces (View::words_runs: laid
/// out as it draws them, view_runs_laid; as big as it is drawn), the first that holds them.
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
    None => tree_run_rects(s)
  }
}

///|
/// Where the words `s` of a node of the window's tree's words in pieces are drawn, as it lays them out now: one
/// rectangle a line, in the window (its line in its middle where it says so: its start's room before it).
fn tree_run_rects(s : String) -> Array[(Double, Double, Double, Double)] {
  let out : Array[(Double, Double, Double, Double)] = []
  guard view_app.val is Some(tree) else { return out }
  tree.laid_as_now()
  tree.each_drawn_scaled(fn(c, x, y, a, sc) {
    if out.length() > 0 || c.runs.is_empty() || a <= 0.0 {
      return
    }
    let (_, lay, _) = view_runs_laid(c.runs, c.words_look, c.runs_look, c.w, tree.words_scale_of(c.id), kept=c.words_breaks)
    match lay.text.find(s) {
      Some(i) =>
        for r in lay.rects(i, i + s.length()) {
          // (each line where it is drawn: in the middle of the node where it says so, view_host's picked rects')
          let dx = rich_shift_at(lay, r.1 + r.3 / 2.0, if c.words_center { c.w } else { -1.0 })
          out.push((x + (r.0 + dx) * sc, y + r.1 * sc, r.2 * sc, r.3 * sc))
        }
      None => ()
    }
  })
  out
}

///|
/// A tap on the middle of the first piece of the words `s` of a rich
/// paragraph (a link).
pub fn Tester::tap_run(self : Tester, s : String) -> Unit {
  let rs = self.run_rects(s)
  if rs.length() == 0 {
    @halt.saying("no rich text \"\{s}\" on screen")
  }
  let (x, y, w, h) = rs[0]
  self.tap(x + w / 2.0, y + h / 2.0)
}

///|
/// The picture at `src` takes `ms` to decode: asked for at a moment, its host says it is decoded at that moment and
/// `ms` after it, on the timeline (a frame drawn there), not at the frame after it is asked for, as every other one
/// is. Where the test says when itself (Tester::finish), that.
pub fn Tester::decode_after(self : Tester, src : String, ms : Double) -> Unit {
  self.fake.decode_after[src] = ms
}

///|
/// Makes up an image at `src`, `w` × `h` pixels, for views to load.
pub fn Tester::add_image(self : Tester, src : String, w : Int, h : Int) -> Unit {
  self.fake.image_sizes[src] = (w, h)
}

///|
/// Makes up a picture at `src`, `w` × `h` pixels of `rgba` (premultiplied, rows from the top), for views to load and
/// read back (Ctx::image_pixels): loaded no larger than asked, as it is.
pub fn Tester::add_pixels(self : Tester, src : String, w : Int, h : Int, rgba : FixedArray[Byte]) -> Unit {
  self.fake.image_sizes[src] = (w, h)
  self.fake.pixels_of_src[src] = rgba
}

///|
/// The source decode `id` the host was asked for is of ("" none): the picture's it was asked for (bytes handed over:
/// the source they were handed for), while the app keeps it; else the source its host was asked for.
pub fn Tester::image_src(self : Tester, id : Int) -> String {
  match image_by_id.get(id) {
    Some((src, _)) => src
    None => self.fake.image_srcs.get(id).unwrap_or("")
  }
}

///|
/// The images loaded so far: source and the size asked for.
pub fn Tester::image_loads(self : Tester) -> Array[(String, Int)] {
  self.fake.image_loads
}

///|
/// The most bytes handed over for decodes (image_load_bytes) the host held at once in this run: what a host keeps of
/// them till they are let go of (image_free), as a phone's Java side kept a GIF's every frame's (#5301).
pub fn Tester::host_image_bytes_most(self : Tester) -> Int {
  self.fake.image_bytes_most
}

///|
/// How many decoded images are kept.
pub fn Tester::images_kept(self : Tester) -> Int {
  self.fake.images.length()
}

///|
/// Every instance drawn in the last frame in the order drawn, each its numbers whole (scene.mbt's layout: its rect 0-3,
/// its kind 5, its clip 16-19 and 24-31, its outer 40-51…): what is cut where, read as the renderers read it.
pub fn Tester::drawn_instances(self : Tester) -> Array[Array[Double]] {
  self.reads_own()
  ignore(self)
  let c = g()
  Array::makei(c.ninst, fn(k) { Array::makei(inst_size, fn(j) { c.inst[k * inst_size + j] }) })
}

///|
/// Every instance drawn in the last frame in the order drawn (later over earlier): its kind (0 a rect, 4 an image…),
/// x, y, w, h and opacity.
pub fn Tester::drawn_order(self : Tester) -> Array[(Int, Double, Double, Double, Double, Double)] {
  self.reads_own()
  ignore(self)
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    out.push((c.inst[b + 5].to_int(), c.inst[b], c.inst[b + 1], c.inst[b + 2], c.inst[b + 3], c.inst[b + 11]))
  }
  out
}

///|
/// Every instance drawn in the last frame in the order drawn, with what cuts it: its kind, x, y, w, h, and the rect it
/// is cut to (x0, y0, x1, y1: scene.mbt 16-19); what of it lies outside that is not seen.
pub fn Tester::drawn_cut(self : Tester) -> Array[(Int, Double, Double, Double, Double, (Double, Double, Double, Double))] {
  self.reads_own()
  ignore(self)
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    let a = c.inst
    out.push((a[b + 5].to_int(), a[b], a[b + 1], a[b + 2], a[b + 3], (a[b + 16], a[b + 17], a[b + 18], a[b + 19])))
  }
  out
}

///|
/// How each instance drawn in the last frame fades out towards a cut (scene.mbt 52-55), in drawing order: its kind, its
/// rect's top and height, then from its top where it is 0 and how far below that it is whole, from its foot where it is
/// 0 and how far above that it is whole (a soft of 0: none that way).
pub fn Tester::drawn_fades(self : Tester) -> Array[(Int, Double, Double, Double, Double, Double, Double)] {
  self.reads_own()
  ignore(self)
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    let a = c.inst
    out.push((a[b + 5].to_int(), a[b + 1], a[b + 3], a[b + 52], a[b + 53], a[b + 54], a[b + 55]))
  }
  out
}

///|
/// How each instance drawn in the last frame fades out towards a cut across (scene.mbt 56-59), in drawing order: its
/// kind, its rect's top and height, then from its left how far it is whole past where it is 0, and from its right (0:
/// none that way), with where each is 0.
pub fn Tester::drawn_fades_across(self : Tester) -> Array[(Int, Double, Double, Double, Double, Double, Double)] {
  self.reads_own()
  ignore(self)
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    let a = c.inst
    out.push((a[b + 5].to_int(), a[b + 1], a[b + 3], a[b + 57], a[b + 56], a[b + 59], a[b + 58]))
  }
  out
}

///|
/// The image instances drawn in the last frame: (x, y, w, h, u0, v0, du,
/// dv, opacity).
pub fn Tester::drawn_images(self : Tester) -> Array[Array[Double]] {
  self.reads_own()
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
/// What cuts each image instance of the last frame, in drawn_images' order: its clip (left, top, right, bottom) and that
/// clip's corners (top left, then round it; 0 square).
pub fn Tester::drawn_image_clips(
  self : Tester,
) -> Array[((Double, Double, Double, Double), (Double, Double, Double, Double))] {
  self.reads_own()
  ignore(self)
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 4.0 {
      out.push(
        (
          (c.inst[b + 16], c.inst[b + 17], c.inst[b + 18], c.inst[b + 19]),
          (c.inst[b + 24], c.inst[b + 25], c.inst[b + 26], c.inst[b + 27]),
        ),
      )
    }
  }
  out
}

///|
/// The host says the app is shown or not, in front or not (as a window's or an activity's changes are told); `awake`:
/// it goes on while not shown (a desktop's app put away: @ui.app_awake).
pub fn Tester::app_state(self : Tester, visible : Bool, focused : Bool, awake? : Bool = false) -> Unit {
  on_app_state((if visible { 1 } else { 0 }) | (if focused { 2 } else { 0 }) | (if awake { 4 } else { 0 }))
  self.draw()
}

///|
/// Bold text `em` ems wider a character than regular from now on (the fake
/// host's shapes ignore weight otherwise).
pub fn Tester::bold_wider(self : Tester, em : Double) -> Unit {
  self.fake.bold = em
}

///|
/// What is set in the app's words' face `em` ems wider a character once one is given (face_add @hostapi.face_ui) than
/// in the system's, from now on (the fake host's shapes ignore faces otherwise).
pub fn Tester::ui_face_wider(self : Tester, em : Double) -> Unit {
  self.fake.ui_face = em
}

///|
/// The host's glyphs moved on (@hostapi.atlas_generation), as a host's do once a face it was given is in (a page's,
/// loaded after it was asked for), its scale changes or its atlas is lost: seen as the next frame begins.
pub fn Tester::glyphs_moved_on(self : Tester) -> Unit {
  self.fake.generation = self.fake.generation + 1
}

///|
/// Digits set all one width (@hostapi.style_tabular) `em` ems wider than set otherwise, from now on (the fake host's
/// shapes ignore it otherwise).
pub fn Tester::tabular_wider(self : Tester, em : Double) -> Unit {
  self.fake.tabular = em
}

///|
/// Each glyph's picture `w` by `h` points from now on (6 by 10 till said: the fake host's), so few fill the atlas.
pub fn Tester::glyph_box(self : Tester, w : Double, h : Double) -> Unit {
  self.fake.glyph_box = (w, h)
}

///|
/// What is set in host face `face` (a face given by its number, as a face's preview is) `em` ems wider a character than
/// in the system's, from now on.
pub fn Tester::face_wider(self : Tester, face : Int, em : Double) -> Unit {
  self.fake.faces_wider[face] = em
}

///|
/// Where the first text node containing `s` is drawn (its top left), moved as it and what holds it move
/// (draw.mbt).
pub fn Tester::drawn_of(self : Tester, s : String) -> (Double, Double)? {
  self.reads_own()
  ignore(self)
  let c = g()
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.bones == 0L && (n.kind == kind_text || n.kind == kind_rich) && n.text.contains(s) {
      return Some(c.drawn_at(i))
    }
  }
  // (or the words of a node of the window's tree, where it is drawn, as Tester::rect_of finds them)
  match view_tree() {
    Some(tree) =>
      for d in tree.drawn() {
        if d.bones == 0L && view_words_set(d.words, d.words_look, d.words_breaks).contains(s) && d.alpha > 0.0 {
          return Some((d.x, d.y))
        }
      }
    None => ()
  }
  None
}

///|
/// What shows of the first text node containing `s` (x, y, w, h): where it is drawn (drawn_of), cut by each box
/// holding it that clips, where that box is drawn (a clip moves with its own look and its holders', not with what it
/// holds); nothing shows when w or h is 0.
pub fn Tester::shown_of(self : Tester, s : String) -> (Double, Double, Double, Double)? {
  self.reads_own()
  ignore(self)
  let c = g()
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.bones == 0L && (n.kind == kind_text || n.kind == kind_rich) && n.text.contains(s) {
      let (x, y) = c.drawn_at(i)
      let mut x0 = x
      let mut y0 = y
      let mut x1 = x + n.fw
      let mut y1 = y + n.fh
      let mut p = n.parent
      while p >= 0 {
        let a = c.nodes[p]
        if a.clip {
          let (ax, ay) = c.drawn_at(p)
          x0 = dmax(x0, ax)
          y0 = dmax(y0, ay)
          x1 = dmin(x1, ax + a.fw)
          y1 = dmin(y1, ay + a.fh)
        }
        p = a.parent
      }
      return Some((x0, y0, dmax(x1 - x0, 0.0), dmax(y1 - y0, 0.0)))
    }
  }
  // (or the words of a node of the window's tree, as much of them as is drawn: cut by what holds them that cuts what
  // it holds (View::clips), as drawn)
  match view_tree() {
    Some(tree) => {
      let drawn = tree.drawn_held()
      for e in drawn {
        let (d, holder, _) = e
        if d.bones == 0L && view_words_set(d.words, d.words_look, d.words_breaks).contains(s) && d.alpha > 0.0 {
          let mut x0 = d.x
          let mut y0 = d.y
          let mut x1 = d.x + d.w
          let mut y1 = d.y + d.h
          let mut h = holder
          while h >= 0 {
            let (a, up, _) = drawn[h]
            if a.clips {
              x0 = dmax(x0, a.x)
              y0 = dmax(y0, a.y)
              x1 = dmin(x1, a.x + a.w)
              y1 = dmin(y1, a.y + a.h)
            }
            h = up
          }
          return Some((x0, y0, dmax(x1 - x0, 0.0), dmax(y1 - y0, 0.0)))
        }
      }
    }
    None => ()
  }
  None
}

///|
/// How the node keyed `what` (its id's key, as built: c.id(what)), else the first text node containing `what` (`=WORDS`:
/// whose words are WORDS exactly, as Tester::locate takes it), was drawn in the last frame over how it is laid out: its
/// scale across and down and its opacity, its own look's and all its ancestors' together (a card shrunk to 90% as it
/// goes: (0.9, 0.9, 1.0)); words, as they are drawn, by their looks' `words` too (a panel's words after its ground).
/// None when there is no such node.
pub fn Tester::look_of(self : Tester, what : String) -> (Double, Double, Double)? {
  self.reads_own()
  let c = g()
  let found = self.node_named(what)
  guard found >= 0 else { return None }
  let k = c.nodes[found].kind
  let words = k == kind_text || k == kind_rich || k == kind_editor
  let mut sx = 1.0
  let mut sy = 1.0
  let mut alpha = 1.0
  let mut p = found
  while p >= 0 {
    match c.drawn_entry(p) {
      Some(e) => {
        let l = e.look_now()
        sx = sx * l.sx
        sy = sy * l.sy
        alpha = alpha * l.alpha * (if words { l.words } else { 1.0 })
      }
      None => ()
    }
    p = c.nodes[p].parent
  }
  Some((sx, sy, alpha))
}

///|
/// How far the node `what` (as look_of finds it) was turned in the last frame, in radians clockwise: its own look's
/// and all its ancestors' together. None when there is no such node.
pub fn Tester::turn_of(self : Tester, what : String) -> Double? {
  self.reads_own()
  let c = g()
  let found = self.node_named(what)
  guard found >= 0 else { return None }
  let mut rot = 0.0
  let mut p = found
  while p >= 0 {
    match c.drawn_entry(p) {
      Some(e) => rot = rot + e.look_now().rot
      None => ()
    }
    p = c.nodes[p].parent
  }
  Some(rot)
}

///|
/// The node keyed `what`, else the first text node containing `what` (`=WORDS`: exactly): its index, -1 when none.
fn Tester::node_named(self : Tester, what : String) -> Int {
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
      if n.bones == 0L && (n.kind == kind_text || n.kind == kind_rich) &&
        (match exact {
          Some(e) => n.text == e
          None => n.text.contains(what)
        }) {
        found = i
        break
      }
    }
  }
  found
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
  self.drawn_now()
}

///|
/// The wheel turned both ways (`dx`, `dy`) at (x, y) with `mods` held (wheel_mod_*: ⌘ to zoom a picture, a pinch).
pub fn Tester::wheel_with(self : Tester, x : Double, y : Double, dx : Double, dy : Double, mods : Int) -> Unit {
  finger_wheel(x, y, dx, dy, mods * 16)
  self.drawn_now()
}

///|
/// A key (`code`, `mods` held) the host says came at `at` (its own moment), told now, later: no frame drawn.
pub fn Tester::key_told(self : Tester, code : Int, mods : Int, at : Double) -> Unit {
  self.fake.event_at = at
  posted_tell()
  let was = g().focus
  on_key(code, mods)
  self.fake.event_at = -1.0
  self.focus_moved_held(code, mods, was)
}

///|
/// Text committed by the input method (Tester::type_text's) the host says came at `at`, told now, later: no frame
/// drawn.
pub fn Tester::text_told(self : Tester, s : String, at : Double) -> Unit {
  self.fake.event_at = at
  posted_tell()
  on_text(0, s, 0, 0)
  self.fake.event_at = -1.0
}

///|
/// The wheel turned (Tester::wheel_with's) at `at`, told now, later (the host's clock past it): as a host hands on an
/// event it got a while before, its own time said with it (@hostapi.event_time). No frame drawn.
pub fn Tester::wheel_told(
  self : Tester,
  x : Double,
  y : Double,
  dx : Double,
  dy : Double,
  mods : Int,
  at : Double,
) -> Unit {
  self.fake.event_at = at
  finger_wheel(x, y, dx, dy, mods * 16)
  self.fake.event_at = -1.0
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
    6 => Grabbing
    7 => Crosshair
    8 => NotAllowed
    _ => Arrow
  }
}

///|
/// How often a press asked the host to drag the window.
pub fn Tester::window_drags(self : Tester) -> Int {
  self.fake.window_drags
}

///|
/// What the app asked of the window's own buttons, oldest first (@hostapi.window_act: 1 minimize, 2 maximize or back,
/// 3 close).
pub fn Tester::window_acts(self : Tester) -> Array[Int] {
  self.fake.window_acts.copy()
}

///|
/// Whether the app can open a window of its own, from the next frame on (@hostapi.window_opens: a desktop's).
pub fn Tester::set_window_opens(self : Tester, can : Bool) -> Unit {
  self.fake.window_opens = can
  self.fake.wants = true
}

///|
/// What the app opened windows of its own for, oldest first (@hostapi.window_open).
pub fn Tester::windows_opened(self : Tester) -> Array[String] {
  self.fake.windows_opened.copy()
}

///|
/// A window the app opened for `what` closed, by the person (@hostapi.window_front finds it no more).
pub fn Tester::close_window(self : Tester, what : String) -> Unit {
  self.fake.windows_closed.push(what)
}

///|
/// What the app brought its windows to the front for, oldest first (@hostapi.window_front).
pub fn Tester::windows_fronted(self : Tester) -> Array[String] {
  self.fake.windows_fronted.copy()
}

///|
/// Where the app last said it draws the window's maximize button (@hostapi.window_snap): x, y, w, h (w 0: none).
pub fn Tester::window_snap_rect(self : Tester) -> (Double, Double, Double, Double) {
  self.fake.snap
}

///|
/// The window maximized or not, from the next frame on (@hostapi.window_zoomed).
pub fn Tester::set_window_zoomed(self : Tester, zoomed : Bool) -> Unit {
  host_setting_set("set_window_zoomed")
  self.fake.zoomed = zoomed
  self.fake.wants = true
}

///|
/// How the pointer stands on the window's maximize button the app draws, as its host would say it (0 not on it, 1 on it,
/// 2 pressing it), from the next frame on (@hostapi.window_snap_state).
pub fn Tester::set_window_snap(self : Tester, state : Int) -> Unit {
  self.fake.snap_state = state
  self.fake.wants = true
}

///|
/// Whether a press at (x, y) would drag the window (what it lands on is a target of Ctx::window_drag, or a node of the
/// window's tree's top row that moves it: View::moves_window), pressing nothing. Found as a press is (view_pointer):
/// what the old frame put over all of it at its root first; then the tree's, an old view's where the tree hosts one
/// there, or where nothing of the tree's is and the one old view is the whole window, taking input.
pub fn Tester::drags_window_at(self : Tester, x : Double, y : Double) -> Bool {
  self.reads_own()
  let c = self.ctx()
  let old = fn() { desk_drags(hit_in(c.hit_ids, c.hit_rects, x, y)) }
  match view_tree() {
    None => old()
    Some(tree) => {
      // (what the old views take presses at, where the tree has them now)
      old_hits_place(c, Some(tree))
      if old_root_hit(c, x, y) {
        return old()
      }
      match tree.target_at(x, y) {
        TopRow(id) => tree.moves_window(id)
        Pressed(_) | Dragged(_) => false
        Hosted(_) => old()
        Nothing => old_whole.val && island_allows(old_whole_island()) && old()
      }
    }
  }
}

///|
/// What a press at (x, y) would land on, pressing nothing, found as drags_window_at finds it (view_pointer's order):
/// "window" where it drags the window; "pressed" where what it lands on does something pressed (a node of the window's
/// tree with its press or its drag said, as Tree::target_at has it, the rule of a press's room measuring by the same;
/// an old view's target whose press is read, Ctx::takes_presses); "" where it lands on nothing that does (what is only
/// pointed at or named, a top row that moves no window, nothing).
pub fn Tester::press_lands_at(self : Tester, x : Double, y : Double) -> String {
  self.reads_own()
  let c = self.ctx()
  let old = fn() {
    let m = hit_marks(hit_in(c.hit_ids, c.hit_rects, x, y))
    if (m & mark_drags) != 0 {
      "window"
    } else if (m & mark_takes) != 0 {
      "pressed"
    } else {
      ""
    }
  }
  match view_tree() {
    None => old()
    Some(tree) => {
      old_hits_place(c, Some(tree))
      if old_root_hit(c, x, y) {
        return old()
      }
      match tree.target_at(x, y) {
        TopRow(id) => if tree.moves_window(id) { "window" } else { "" }
        Pressed(_) | Dragged(_) => "pressed"
        Hosted(_) => old()
        Nothing => if old_whole.val && island_allows(old_whole_island()) { old() } else { "" }
      }
    }
  }
}

///|
/// Tab (Shift+Tab when `back`): the focus to the next stop (focus.mbt).
pub fn Tester::tab(self : Tester, back? : Bool = false) -> Unit {
  self.key(key_tab, mods=if back { mod_shift_key } else { 0 })
}

///|
/// The semantics tree as it is read now (Ctx::semantics_tree): the old views' as the last frame built them, the window's
/// tree's nodes as they say they are now.
pub fn Tester::semantics(self : Tester) -> Array[SemNode] {
  self.reads_own()
  let tree = g().semantics_tree()
  self.hold_named(tree)
  tree
}

///|
/// The semantics tree as text, hidden nodes left out (Ctx::semantics_dump).
pub fn Tester::semantics_dump(self : Tester) -> String {
  self.reads_own()
  ignore(self)
  g().semantics_dump()
}

///|
/// What a test finds a node of the semantics tree by (Testing Library's queries by role and name, their options):
/// its role; its name exactly (`label`, "" any) or holding `has`; its state where one is given; in what `within` holds
/// (one of the tree's, Tester::all's: what it holds, not it).
pub(all) struct Find {
  role : Role
  label : String
  has : String
  checked : Check?
  selected : Bool?
  expanded : Bool?
  disabled : Bool?
  within : SemNode?
}

///|
/// Whether `s` is what `f` finds (its role, name and state; not where it is).
fn Find::takes(self : Find, s : SemNode) -> Bool {
  s.role == self.role &&
  !s.hidden &&
  (self.label == "" || s.label == self.label) &&
  (self.has == "" || s.label.contains(self.has)) &&
  (self.checked is None || s.check == self.checked) &&
  (self.selected is None || s.selected.unwrap_or(false) == self.selected.unwrap_or(false)) &&
  (self.expanded is None || s.expanded == self.expanded) &&
  (self.disabled is None || Some(s.disabled) == self.disabled)
}

///|
/// What `f` finds, said in a line (for what a test fails with).
fn Find::said(self : Find) -> String {
  let sb = StringBuilder()
  sb.write_string(self.role.to_string())
  if self.label != "" {
    sb.write_string(" \{self.label.escape()}")
  }
  if self.has != "" {
    sb.write_string(" holding \{self.has.escape()}")
  }
  match self.checked {
    Some(c) => sb.write_string(" checked=\{c}")
    None => ()
  }
  match self.selected {
    Some(v) => sb.write_string(" selected=\{v}")
    None => ()
  }
  match self.expanded {
    Some(v) => sb.write_string(" expanded=\{v}")
    None => ()
  }
  match self.disabled {
    Some(v) => sb.write_string(" disabled=\{v}")
    None => ()
  }
  match self.within {
    Some(w) => sb.write_string(" within \{w.describe()}")
    None => ()
  }
  sb.to_string()
}

///|
/// The nodes not hidden (under a modal, in a hidden part) that `f` finds, in the tree's order.
fn Tester::found(self : Tester, f : Find) -> Array[SemNode] {
  let tree = self.semantics()
  // (in what `within` holds: the nodes after it deeper than it, up to the next as deep or shallower)
  let (from, until) = match f.within {
    Some(w) => {
      let mut at = -1
      for k, s in tree {
        if s.id == w.id && s.role == w.role && s.label == w.label && s.rect == w.rect && s.depth == w.depth {
          at = k
          break
        }
      }
      if at < 0 {
        (0, 0)
      } else {
        let mut end = at + 1
        while end < tree.length() && tree[end].depth > tree[at].depth {
          end = end + 1
        }
        (at + 1, end)
      }
    }
    None => (0, tree.length())
  }
  let out = []
  for k in from..<until {
    if f.takes(tree[k]) {
      out.push(tree[k])
    }
  }
  out
}

///|
/// The nodes of `role` not hidden (under a modal, in a hidden part), named `label` exactly unless it is "", holding
/// `has` in their names, in the state each of `checked`, `selected`, `expanded`, `disabled` says where it is given, in
/// what `within` holds where it is (Find).
pub fn Tester::all(
  self : Tester,
  role : Role,
  label? : String = "",
  has? : String = "",
  checked? : Check,
  selected? : Bool,
  expanded? : Bool,
  disabled? : Bool,
  within? : SemNode,
) -> Array[SemNode] {
  self.reads_own()
  self.found({ role, label, has, checked, selected, expanded, disabled, within })
}

///|
/// The node of `role` named `label` (Testing Library's getByRole with its name, Compose's onNode; the rest of what
/// Tester::all takes too): the one not hidden; the test fails when there is none, or more than one.
pub fn Tester::get(
  self : Tester,
  role : Role,
  label? : String = "",
  has? : String = "",
  checked? : Check,
  selected? : Bool,
  expanded? : Bool,
  disabled? : Bool,
  within? : SemNode,
) -> SemNode raise {
  self.reads_own()
  let f : Find = { role, label, has, checked, selected, expanded, disabled, within }
  let found = self.found(f)
  if found.length() == 1 {
    return found[0]
  }
  if found.is_empty() {
    fail("no \{f.said()} in the semantics tree:\n\{self.semantics_dump()}")
  }
  fail("\{found.length()} of \{f.said()} in the semantics tree:\n\{self.semantics_dump()}")
}

///|
/// The node of `role` named `label` (and the rest of what Tester::all takes), if there is one not hidden (the first).
pub fn Tester::query(
  self : Tester,
  role : Role,
  label? : String = "",
  has? : String = "",
  checked? : Check,
  selected? : Bool,
  expanded? : Bool,
  disabled? : Bool,
  within? : SemNode,
) -> SemNode? {
  self.reads_own()
  let found = self.found({ role, label, has, checked, selected, expanded, disabled, within })
  if found.is_empty() {
    None
  } else {
    Some(found[0])
  }
}

///|
/// A tap on the middle of the node of `role` named `label` (Tester::get, what it takes), settled.
pub fn Tester::click(
  self : Tester,
  role : Role,
  label? : String = "",
  has? : String = "",
  checked? : Check,
  selected? : Bool,
  expanded? : Bool,
  disabled? : Bool,
  within? : SemNode,
) -> Unit raise {
  let s = self.get(role, label~, has~, checked?, selected?, expanded?, disabled?, within?)
  let (x, y, w, h) = s.rect
  self.tap(x + w / 2.0, y + h / 2.0)
}

///|
/// `action` asked of the node of `role` named `label` (Tester::get, what it takes) as a screen reader asks it, settled.
pub fn Tester::act(
  self : Tester,
  role : Role,
  action : Action,
  label? : String = "",
  has? : String = "",
  within? : SemNode,
) -> Unit raise {
  let s = self.get(role, label~, has~, within?)
  if s.id == 0 {
    fail("\{s.describe()} takes no action")
  }
  g().ask_action(s.id, action)
  self.draw()
}

///|
/// Asks `s` (one of what the semantics tree says, Tester::all's: of several alike, the one a test means) to do `action`,
/// as Tester::act asks the one of its role and label.
pub fn Tester::act_on(self : Tester, s : SemNode, action : Action) -> Unit raise {
  if s.id == 0 {
    fail("\{s.describe()} takes no action")
  }
  g().ask_action(s.id, action)
  self.draw()
}

///|
/// The node that has the keyboard's focus, if it says something.
pub fn Tester::focused(self : Tester) -> SemNode? {
  self.reads_own()
  for s in self.semantics() {
    if s.focused {
      return Some(s)
    }
  }
  None
}

///|
/// Whether every frame a test draws at rest is held to the corner rule (Tester::hold_corners): as the Tester was made
/// (its `corners_held`).
// kept across runs: set again by each Tester (Tester::new)
let corners_hold : Ref[Bool] = Ref(true)

///|
/// The corner rule (corners.mbt), held on the frame just drawn when nothing on it moves (a motion between its ends
/// stands anywhere): where the theme says its ladder (an app's: Theme::corner_ladder), any fault fails the test at
/// once, with what and where. So what a test reaches, every state of every screen it walks through, keeps to it, not
/// only the screens a test of corners looks at.
fn Tester::hold_corners(self : Tester) -> Unit {
  if !corners_hold.val {
    return
  }
  let c = g()
  let faults = corners_unknown(c.held_corner_faults())
  if faults.is_empty() {
    return
  }
  let said = "the corner rule broken on a frame drawn \{self.w}×\{self.h} at \{self.fake.time}, the Tester made at \{looks_made_at.val} (the theme's ladder \{Repr(c.corner_ladder)}; the rule: mbui's src/ui/corners.mbt):\n" +
    faults.join("\n")
  @halt.saying(said)
}

///|
/// The corner faults a test knows and keeps (Tester::corners_known), as corner_fault_unplaced says them: those
/// Tester::hold_corners passes over. None but where a test says them.
// kept across runs: set again by each Tester (Tester::new)
let corners_known_now : Ref[Array[String]] = Ref([])

///|
/// Faults of the corner rule this test knows and keeps (a design not yet decided, each with why where it is said):
/// Tester::hold_corners passes over each fault that is one of them where it stands (corner_fault_unplaced: what it
/// names by its words and size, its container the same, the rule's same words; where they stand on the window, and
/// which of the frame's nodes they are, not compared: the same part as a list scrolls). Any other fails as ever:
/// another part, another size, the rule's other words. Said once, after the Tester is made, for the rest of it.
pub fn Tester::corners_known(self : Tester, known : Array[String]) -> Unit {
  ignore(self)
  corners_known_now.val = known.map(corner_fault_unplaced)
}

///|
/// Of `faults`, those the test does not know (Tester::corners_known): what Tester::hold_corners fails on.
fn corners_unknown(faults : Array[String]) -> Array[String] {
  let known = corners_known_now.val
  faults.filter(fn(f) { !known.contains(corner_fault_unplaced(f)) })
}

///|
/// A fault of the corner rule said without where what it names stands: each `(at x,y ` of its as `(at * `, each
/// `node n` as `node *` (Tester::corners_known's way of comparing).
pub fn corner_fault_unplaced(fault : String) -> String {
  let sb = StringBuilder()
  let cs = fault.to_array()
  let n = cs.length()
  let starts = fn(i : Int, w : String) -> Bool {
    let ws = w.to_array()
    if i + ws.length() > n {
      return false
    }
    for j in 0..<ws.length() {
      if cs[i + j] != ws[j] {
        return false
      }
    }
    true
  }
  let mut i = 0
  while i < n {
    if starts(i, "(at ") {
      sb.write_string("(at *")
      i += 4
      while i < n && cs[i] != ' ' {
        i += 1
      }
    } else if starts(i, "node ") {
      sb.write_string("node *")
      i += 5
      while i < n && cs[i] >= '0' && cs[i] <= '9' {
        i += 1
      }
    } else {
      sb.write_char(cs[i])
      i += 1
    }
  }
  sb.to_string()
}

///|
/// What the corner rule finds on the frame just drawn as Tester::hold_corners holds it: where the theme says its ladder
/// and nothing on it moves (Ctx's `motion_left`, the window's tree's drawn as moving too: view_frame_end), the frame's
/// and the window's tree's nodes (Ctx::with_tree_nodes); none otherwise.
fn Ctx::held_corner_faults(self : Ctx) -> Array[String] {
  if self.corner_ladder.is_empty() || self.frame_by is Some(_) || self.motion_left || self.page_in_hand {
    return []
  }
  self.with_tree_nodes(fn() { self.corner_faults() })
}

///|
/// Every list and scroller the last frame drew (an old view's, a node of the window's tree's that scrolls: the page's
/// own, View::scrolls_window) scrolled to its end by a wheel over its middle, then a move's time run: what each screen
/// shows at its end, for the rules held at rest (a card last in a panel ending in its foot corners: corner_faults).
/// How many it scrolled.
pub fn Tester::scroll_all_to_end(self : Tester) -> Int {
  self.reads_own()
  let c = g()
  let at : Array[(Double, Double)] = c.with_tree_nodes(fn() {
    let out = []
    for i in 0..<c.count {
      let n = c.nodes[i]
      if (n.kind == kind_list || n.kind == kind_scroll || n.tree_scrolls) && n.fw > 0.0 && n.fh > 0.0 {
        let (x, y) = c.drawn_at(i)
        out.push((x + n.fw / 2.0, y + n.fh / 2.0))
      }
    }
    out
  })
  for p in at {
    self.wheel(p.0, p.1, 100000.0)
  }
  self.run_for(move_most_ms)
  at.length()
}

///|
/// How many things are drawn in their bones now (Ctx::bones, View::bones): what a page shows of what it still waits
/// for. None: nothing on screen waits.
pub fn Tester::bones_drawn(self : Tester) -> Int {
  self.reads_own()
  let _ = self
  let c = g()
  let mut n = 0
  for i in 0..<c.count {
    if c.nodes[i].bones != 0L {
      n += 1
    }
  }
  match view_tree() {
    Some(tree) =>
      for d in tree.drawn() {
        if d.bones != 0L && d.alpha > 0.0 {
          n += 1
        }
      }
    None => ()
  }
  n
}
