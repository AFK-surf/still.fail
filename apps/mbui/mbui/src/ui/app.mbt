// The window's loop: the host calls these functions for frames and input.

///|
/// The window's context: one for the window's life; a Tester makes a fresh one each (nothing a test left in it is
/// seen by the next).
let the_ctx : Ref[Ctx] = Ref(Ctx::new())


///|
/// The builds made so far, over every Ctx the program has had (a Tester's each its own): a build's number is never
/// another's, so what is kept of one outside its Ctx (an app's own Field, given to an editor in a Tester before; a
/// native view, a sideways box) is never taken for this build's.
// kept across runs: a build's number is never one a run before had
let builds_made : Ref[Int] = Ref(0)

///|
/// The number of the build beginning now (builds_made).
fn next_build() -> Int {
  builds_made.val = builds_made.val + 1
  builds_made.val
}
///|
fn g() -> Ctx {
  the_ctx.val
}

///|
let g_view : Ref[(Ctx) -> Unit] = { val: fn(_c) { () } }

///|
let bench : Bench = {
  mode: 0,
  frames: 0,
  cpu: [],
  present: [],
  gpu: [],
  start: 0.0,
  speed: 0.0,
  phases: [0.0, 0.0, 0.0],
  host: 0,
  held: false,
}

///|
struct Bench {
  mut mode : Int
  mut frames : Int
  cpu : Array[Double]
  present : Array[Double]
  // the GPU's time per frame (the last frame it finished), where the host knows it
  gpu : Array[Double]
  mut start : Double
  mut speed : Double
  // build, layout and paint time summed over the measured frames
  phases : Array[Double]
  // the host's bench mode as the window opened (MBUI_BENCH), kept as it was (`mode` the framework's own bench's)
  mut host : Int
  // a bench of the app's own asked this frame to draw the next one (Ctx::bench_frames)
  mut held : Bool
}

///|
/// Opens the window and runs `view` for every frame until it closes: the window a tree made once, `tree` (`view` the
/// old frame around the old views it holds, put where `view` says: old_views_here), else `view` its one old view
/// (view_host.mbt).
pub fn run(title : String, view : (Ctx) -> Unit, tree? : (@view.View) -> Unit) -> Unit {
  match tree {
    Some(make) => set_view_app(make, around=view)
    None => set_view_app(fn(root) { old(root, view).grow(Is(1.0)) |> ignore })
  }
  bench.host = @hostapi.bench_mode()
  // (the app's own bench, bench_app: the framework's does not run beside it)
  bench.mode = if bench.host == bench_app { 0 } else { bench.host }
  drive_init()
  @hostapi.set_back(fn(k, x, p, e) { on_back(k, x, p, e) })
  @hostapi.set_app_state(fn(s) { on_app_state(s) })
  outside_told.val = @hostapi.set_outside(fn(k, id, st) { on_outside(k, id, st) })
  @hostapi.run(
    title,
    fn(w, h, s, t) { on_frame(w, h, s, t) },
    fn(k, x, y, b) { on_pointer(k, x, y, b) },
    fn(x, y, dx, dy, ph) { on_wheel(x, y, dx, dy, ph) },
    fn(k, m) { on_key(k, m) },
    fn(k, s, a, b) { on_text(k, s, a, b) },
  )
}

///|
fn on_frame(w : Double, h : Double, scale : Double, t : Double) -> Unit {
  let c = g()
  let fed = inputs_since.val
  inputs_since.val = false
  let taken = inputs_taken.val
  inputs_taken.val = false
  in_frame.val = true
  frame_running.val = true
  paint_phase.val = 0
  // (the soft keyboard's height as the frame begins: device.mbt; the system's settings it is drawn by, kept with the
  // run's input: envrec.mbt)
  c.device_frame_start()
  env_at_frame()
  // (built whole where what it read changed, painted alone where only what its paint read did, or of its looks by the
  // clock alone: frame_watch.mbt)
  // what is made once laid out, placed and drawn as its frame does; the old view in the room its node is given
  // (view_host.mbt)
  view_frame(w, h, t)
  let t0 = frame_drawn(c, w, h, scale, t)
  in_frame.val = false
  // inputs came before this frame: one more, for what they changed late in it (inputrec.mbt `took_input`), built where
  // what is built took them (inputs_taken), else as what it read changed (frame_watch.mbt)
  c.took_input = fed
  if taken {
    c.wants_frame = true
  }
  let t3 = work_now()
  h_present(c.inst, c.ninst)
  // what the shots being taken drew read back (shot.mbt)
  c.shots_after_present()
  log_drawn(w, h, scale, t)
  // (a frame of the looks alone drew no picture of its own: none is let go for it)
  if !looks_drawn.val {
    c.trim_images()
  }
  let t4 = work_now()
  c.t_present = t4 - t3
  if bench.mode > 0 {
    bench_step(c, t3 - t0, t4 - t3)
  }
  slow_probe(c, t, t3 - t0, t4 - t3)
  perf_log(c, t, t3 - t0, t4 - t3)
  drive_frame(c)
  // a motion said, not at its end; one read going (built or painted from where it is now: Ctx::shows_motion); a cycle
  // shown (motion_data.mbt)
  c.motion_left = c.motion_owed() || c.motion_read
  c.motion_read = false
  // (what the window's tree has going: drawn as the clock goes; what ends at a moment, woken then: view_host.mbt)
  view_frame_end(c)
  // (a layout read back that moved: what was placed from it, placed again)
  if c.read_back_moved {
    c.wants_frame = true
  }
  // whether the frame left nothing that ends to come (Ctx::at_rest): said of a run, asserted (Tester::at_rest), never
  // waited on
  c.frame_rest = c.at_rest()
  let held = bench.held
  bench.held = false
  looks_left(c, held)
  if c.wants_frame || c.took_input || bench.mode > 0 || held || paint_left() || layout_left() {
    h_request_frame()
  } else if c.motion_left || c.cycling || c.fiber_frame {
    // what moves on (a motion, a fiber stepping a frame at a time) is drawn as the clock goes, on the host's next
    // frame: no frame is owed at this moment (a Tester's draw draws none for it; its run_for does, as its time goes)
    c.wants_frame = true
    h_request_frame_on()
  } else if c.wake_at > 0.0 {
    h_wake_after(dmax(c.wake_at - t, 1.0))
  }
  // what is still awaited from the host (an image decoding, a view loading): a run to a declared moment keeps its
  // clock still while any is (mac_app.m, MBView, web/host.js), so its picture does not hang on how fast the machine is
  if outside_told.val {
    let rt = runtime()
    let what = rt.awaited().map(fn(a) { a.0 }).join(", ")
    @hostapi.frame_awaiting(rt.awaiting(), what)
  }
  frame_running.val = false
  frame_built.val = false
}

///|
/// One frame without a window, for benchmarks (src/bench): `view` built,
/// laid out and painted at time `t` (ms) as a window's frame is, into
/// `c.inst` (`c.ninst` instances of 28 numbers); nothing is presented and
/// no frame is asked for. `c.t_build`, `t_layout` and `t_paint` time it.
pub fn frame_offscreen(
  view : (Ctx) -> Unit,
  w : Double,
  h : Double,
  scale : Double,
  t : Double,
) -> Ctx {
  g_view.val = view
  frame_body(g(), w, h, scale, t) |> ignore
  g()
}

///|
/// Called at the end of every frame (tests).
// kept across runs: a test sets it around the Testers it makes, and puts it back (layout_wbtest's same_both_ways)
let frame_hook : Ref[(() -> Unit)?] = Ref::new(None)

///|
/// Builds, lays out and paints a frame; returns when it started.
fn frame_body(c : Ctx, w : Double, h : Double, scale : Double, t : Double) -> Double {
  c.width = w
  c.height = h
  c.window_w = w
  c.window_h = h
  // the theme set for this width (a phone's when narrower than its bound: Ctx::set_theme)
  c.pick_theme()
  if scale != c.scale {
    // images are as large as their pixels at this scale
    c.epoch = c.epoch + 1
  }
  c.scale = scale
  // (lengths laid out on whole pixels or not: every layout made anew when that changes)
  let whole = whole_px_layout()
  if whole != c.whole_px {
    c.whole_px = whole
    c.epoch = c.epoch + 1
  }
  // the system's size of words: every layout made anew when it changes
  let fs = font_scale()
  if fs != c.font_scale && fs > 0.0 {
    c.font_scale = fs
    c.epoch = c.epoch + 1
    view_words_rescaled()
  }
  c.clock = t
  c.dt = if c.last_now < 0.0 { 16.67 } else { dclamp(t - c.last_now, 0.0, 100.0) }
  c.last_now = t
  c.frame_no = c.frame_no + 1
  c.hand_moved = c.px != c.hand_was.0 || c.py != c.hand_was.1
  c.hand_was = (c.px, c.py)
  if !layout_reuse.val {
    c.epoch = c.epoch + 1
  }
  // (no wake but a look's asked yet: frame_watch.mbt)
  looks_frame_start()
  c.wants_frame = false
  c.wake_at = -1.0
  c.wake_waited = -1.0
  c.frame_by = None
  c.wake_by = None
  c.page_in_hand = false
  c.cycling = false
  c.reads_out = h_a11y_on()
  c.cycles.clear()
  c.periodic.clear()
  c.nav_rest = -1.0
  c.read_back_moved = false
  faces_from_env()
  text_frame()
  if bench.mode > 0 && c.bench_list != 0 && bench.frames >= 30 {
    c.scroll_list(c.bench_list, bench.speed)
  }
  // (what the frame does, for whoever measures it: perf.mbt; the rows it keeps and builds, kept_nodes.mbt)
  perf_frame_start()
  rows_frame_start()
  let t0 = work_now()
  // what was posted from outside since the last frame (a core's answers), all of it, handed to its handlers in the
  // order it came, before anything reads it (messages.mbt)
  take_messages()
  // (the probe's: how long the messages took, slow_probe)
  probe_msgs_ms.val = work_now() - t0
  // the runtime's fibers run up to this frame's time (fx.mbt): the view reads what they left
  fx_frame_start(c)
  // the parts kept (kept_part.mbt): another run's forgotten, what the runtime did since the last frame an event from outside
  parts_frame_start(c)
  // what came from outside and of the hand, taken: read, so that the next frame is built again as more comes
  // (frame_watch.mbt)
  frame_inputs_read()
  // what is said to move, handed this frame's time, before the view reads where it is (motion_data.mbt)
  c.movers_sample()
  // what the boxes moved by a move_state were shown as in the last frame: where a move set out now starts (move_state.mbt)
  c.moves_frame_start()
  desk_frame_start()
  // the keys and presses since the last frame that move the focus, press what has it, dismiss a layer (focus.mbt,
  // overlay.mbt), before the view builds
  c.focus_frame_start()
  // the press as this frame sees it (press.mbt): every build of it the same; followed by what reads it, not by this
  @signals.untracked(fn() { c.press() |> ignore })
  // each stream's events since the last frame (a frame decoded, let go, a decoder broken), the frame it shows from now
  streams_frame_start()
  // built and laid out; built again, at once, while what the view read in it changed as it was built or laid out
  // (Ctx::read_changed: the focus given, a layer dismissed, a list scrolled, words laid out elsewhere): what is drawn
  // is what the view builds from the state as it is, never a frame of it as it was (frame_passes_most at most)
  let mut root = 0
  let mut t1 = t0
  let mut pass = 0
  c.layers_opened.clear()
  while true {
    pass = pass + 1
    // (built again in the frame, from what changed as it was built or laid out: what built its lists' rows may build
    // them otherwise, none kept, kept_nodes.mbt; a row that shows only what it read too, as what it read of the layout
    // is no signal of its own: its words measured, a row that cuts them so built again)
    if pass > 1 {
      nodes_run.fresh = true
      nodes_run.whole = true
    }
    let kept0 = nodes_run.kept
    layout_coming.val = true
    c.read_back_moved = false
    old_built.val = false
    building.val = true
    c.build_no = next_build()
    // (a hold handed an old view: the frame it comes to, as its build begins; gone once that frame is)
    view_handed_comes(c)
    root = frame_build(c, w, h)
    perf_at[3] = perf_at[3] + 1
    let built_layers = c.layers.length()
    t1 = work_now()
    // laid out under a watch of its own: what only its layout reads (a list's place, its motions by the clock) lays
    // the next frame out again, its lists' rows kept where nothing they show changed (frame_watch.mbt, kept_nodes.mbt)
    laying.val = true
    layout_clock_at.val = ""
    layout_watch_of().read(fn() {
      // lists build their rows while laid out, and those see clicks too
      c.layout(root, 0.0, 0.0, w, h) |> ignore
      // a layer opened by what was built as it was laid out (a list's row: a hover card over what it holds) came
      // after the page's layout: laid out over the window now, as one opened before it is; one opened in it, after it
      let mut late = built_layers
      while late < c.layers.length() {
        c.layout(c.layers[late].node, 0.0, 0.0, w, h) |> ignore
        late = late + 1
      }
      // what floats over what scrolls, all of it made now (a list's rows as it was laid out: scroll_bar.mbt)
      c.floating_found()
      c.sideways_found()
      // what the nodes hold of the frame, all of them made now (a list's rows as it was laid out): what Tab goes among
      // (focus.mbt), the corners worked out once laid out (corners.mbt)
      c.focusables_found()
      c.corners_found()
      c.sems_found()
      // what rows left out where they had not the room, drawn nowhere (readback.mbt)
      c.left_out_after_layout()
      // what covers an item, over it as laid out now (cover.mbt)
      c.covers_after_layout()
      // the corners said `Inner`, from where they lie in their parents as laid out, the covers moved (corners.mbt)
      c.corners_after_layout()
      // how things are drawn this frame, from where they are laid out (draw.mbt: the motion package's looks)
      c.drawing_after_layout()
      // what words marked as selectable hold, as laid out (words.mbt)
      c.words_after_layout()
      // what the view read of the layout as it built (a box's laid rect, a list's place), looked at again
      // (readback.mbt)
      c.reads_after_layout()
      // how far what scrolls sideways can (sideways.mbt)
      c.sideways_after_layout()
    })
    laying.val = false
    layout_coming.val = false
    // the focus into the layers that opened, back from those that went (overlay.mbt)
    c.layers_focus()
    hand_focus_said(c)
    // (what this pass took of the inputs is taken: one built again sees none of them, the clicks, keys, menus and
    // actions since the last frame)
    c.clicked.clear()
    c.double_clicked.clear()
    c.click_at = None
    c.tapped = None
    desk.keys.clear()
    desk.menus.clear()
    c.actions.clear()
    building.val = false
    // (built again keeping no row, for a Tester: compared with the pass that kept them, and built once more where they
    // part, kept_nodes.mbt)
    if c.rows_check_end() {
      continue
    }
    if c.read_back_moved && pass < frame_passes_most {
      continue
    }
    if c.rows_check_begin(kept0) {
      continue
    }
    break
  }
  // the parts kept that this frame did not show let go (kept_part.mbt)
  parts_frame_end(c)
  // what was let go on the window from outside that no build took: files' paths into the field there, the drops
  // let go (drop.mbt)
  drops_frame_end(c)
  // words picked with the pointer held: to what is under it as laid out now (desktop.mbt), drawn so
  c.select_after_layout()
  // what the builds said, where a Tester asks (said.mbt)
  c.said_built_logged()
  // what the last build said to tell outside, told now, once by its key: the last said of it, where the first was
  // (Ctx::after_build)
  let tell_ids = c.tells.map(fn(t) { t.0 })
  let tells = tells_once(c.tells)
  c.tells.clear()
  // (what is told changes what the next frame builds, though nothing came from outside: built again, frame_watch.mbt)
  looks_told(tell_ids, c.told.map(fn(t) { t.0 }))
  for f in tells {
    f()
  }
  // what any of its builds said to tell, once each (Ctx::tell)
  let told = c.told.copy()
  c.told.clear()
  for t in told {
    (t.1)()
  }
  // (what is told may answer at once (a cache, a test's core): what the answer changes is shown by the frame after,
  // owed now, at this moment, not by whatever frame comes next)
  if !told.is_empty() {
    c.owe_next()
  }
  if scroll_logging() {
    c.log_scroll()
  }
  // (what it laid out, said as one number: whether the next frame may paint it again alone, frame_watch.mbt)
  laid_kept(c, root)
  let t2 = work_now()
  // painted under a watch of its own: what only its paint reads (a look worked out as it is painted) paints the next
  // frame again, nothing built (frame_watch.mbt)
  match paint_watch.val {
    Some(p) => p.read(fn() { frame_paint(c, root) })
    None => frame_paint(c, root)
  }
  // the runtime's fibers as the frame ends: what is ready runs at the next frame, a timer's wakes it (fx.mbt)
  fx_frame_end(c)
  let t3 = work_now()
  c.t_build = t1 - t0
  c.t_layout = t2 - t1
  c.t_paint = t3 - t2
  t0
}

///|
/// The frame's tree from `root`, as it is laid out, painted: its instances, what is tapped and scrolled where, what is
/// read out, the native views placed, what the host is told of the field with the keys. `alone`: painted again, its
/// build the last one's (frame_watch.mbt): what that build made for the frames after it (its layers, what takes the
/// focus) is as it left it.
fn frame_paint(c : Ctx, root : Int, alone? : Bool = false) -> Unit {
  paint_phase.val = 1
  paint_base.wake = -1.0
  paint_clock_at.val = ""
  // what is placed by the clock placed where it is now (Ctx::moved_by: a page sliding), read as it is painted
  c.moved_place()
  c.ninst = 0
  cycle_looks_begin()
  dr.tops.clear()
  c.segs.clear()
  text_runs.runs.clear()
  words_alpha.val = 1.0
  c.next_hit_ids.clear()
  c.next_hit_rects.clear()
  c.next_hit_clips.clear()
  c.next_hit_ends.clear()
  c.next_hit_marks.clear()
  c.next_points.clear()
  c.next_passes.clear()
  c.passing = 0
  c.next_point_hits.clear()
  c.next_scroll_ids.clear()
  c.next_scroll_rects.clear()
  c.next_bars.clear()
  c.across_seen.clear()
  c.glass_frame()
  // (the window's tree in its order, the old frame or its old views in their places in it: view_host.mbt)
  c.view_paint(root)
  // what flies that no stratum over it took (strata.mbt), then what is over everything of the page wherever it was
  // painted (an editor's handles), after the rest of it (a layer's after the rest of the layer: Ctx::paint)
  c.land_flying()
  c.raise_tops()
  // (what is over a scrim or a cover none painted after it took: over everything)
  c.paint_raised()
  c.paint_over_cover()
  c.raise_tops()
  // (what is over everything, the layers over the page too)
  c.paint_over_layers()
  // what was shaped and not drawn, for the host to draw ahead while it presents this frame (text.mbt)
  glyphs_ahead()
  c.emit_segs()
  // what is drawn by the clock, as its cycle is now (cycle_look.mbt), what it is drawn over kept for a frame of it alone
  // (frame_watch.mbt)
  looks_keep(c)
  looks_apply(c)
  // the shots being taken, each into instances of its own (shot.mbt)
  c.paint_shots()
  c.sync_views()
  // what the widgets are, for a screen reader reading them (a11y.mbt)
  c.a11y_after_paint()
  // what the paint said, where a Tester asks (said.mbt)
  c.said_logged()
  // the streams' frames taken in this frame said shown (stream.mbt)
  streams_after_paint()
  // back goes where the stack drawn now says (Ctx::nav, while building)
  c.back = c.back_next
  c.back_node = c.back_node_next
  c.back_island = c.back_island_next
  c.back_edge = c.back_edge_next
  c.back_chain = c.back_chain_next
  // (a layer's that took back already, said again as it was kept: what it was said over, in its place)
  c.back_layer_spent()
  // (the host told whether the app takes back, as what the old views said now has it: Ctx::back_told_host)
  c.back_told_host()
  let hi = c.hit_ids
  // (the targets as this frame drew them: what a layer dismissed since the last drew is out of them as it was let go)
  layer_retired_ids.clear()
  c.hit_ids = c.next_hit_ids
  c.next_hit_ids = hi
  let hr = c.hit_rects
  c.hit_rects = c.next_hit_rects
  c.next_hit_rects = hr
  let hc = c.hit_clips
  c.hit_clips = c.next_hit_clips
  c.next_hit_clips = hc
  let he = c.hit_ends
  c.hit_ends = c.next_hit_ends
  c.next_hit_ends = he
  let hm = c.hit_marks
  c.hit_marks = c.next_hit_marks
  c.next_hit_marks = hm
  let ps = c.points
  c.points = c.next_points
  c.next_points = ps
  let pa = c.passes
  c.passes = c.next_passes
  c.next_passes = pa
  // (the old views' kept as painted, each where it is: view_host.mbt)
  old_hits_framed(c)
  // (what said its presses are another's, under a Tester: that one takes them there)
  c.check_press_owners()
  let si = c.scroll_ids
  c.scroll_ids = c.next_scroll_ids
  c.next_scroll_ids = si
  let sr = c.scroll_rects
  c.scroll_rects = c.next_scroll_rects
  c.next_scroll_rects = sr
  let bs = c.bars
  c.bars = c.next_bars
  c.next_bars = bs
  // (its targets published whole: what nodes yield to of them told, view_host.mbt)
  yields_published(c)
  // (what the build made for the next frames, the layers it opened and what takes the focus, said by it: painted again
  // alone, it stands)
  if !alone {
    c.layers_frame_end()
    c.focus_frame_end()
  }
  c.desk_frame_end()
  // (the hand as this frame left it, what it drew published, at its clock: hand_turns.mbt)
  turns_said(c, c.clock, frame=true)
  // (what takes a field's keys the frame no longer said so of, let go: Ctx::on_key)
  keys_taken_built()
  c.bars_frame_end()
  c.sync_ime()
  c.sync_text_menu()
  c.sync_edit_can()
  match frame_hook.val {
    Some(f) if !looks_rebuilt.val => f()
    _ => ()
  }
  paint_phase.val = 2
}

///|
/// `f`, what the view tells outside of what it builds (a call to its core: the chat shown and its end seen), done once
/// the frame's builds are over, as the last of them says it: a frame is built again while what the view read changes
/// (frame_body), and what an earlier build said, from what it read then, is let go. By `key` in the scope it is said
/// in: said twice in a build, the later, where the first was said (said in order: what is kept says it again as it is
/// drawn again, said.mbt). Said outside a frame's build, at once.
pub fn Ctx::after_build(self : Ctx, key : String, f : () -> Unit) -> Unit {
  if !building.val {
    f()
    return
  }
  self.tells.push((self.id("\u{2}after-build/" + key), f))
}

///|
/// What the frame's builds said to tell (Ctx::after_build, in the order said), once by its id: the last said of it,
/// where the first was.
fn tells_once(tells : Array[(Int, () -> Unit)]) -> Array[() -> Unit] {
  let at : Map[Int, Int] = {}
  let out : Array[() -> Unit] = []
  for t in tells {
    match at.get(t.0) {
      Some(k) => out[k] = t.1
      None => {
        at[t.0] = out.length()
        out.push(t.1)
      }
    }
  }
  out
}

///|
/// The most times a frame is built (frame_body): what the view read still changing after them is built again at the
/// next frame (a frame asked for), and a Tester's draw says whose it is (Ctx::read_back_key).
let frame_passes_most = 3

///|
/// Whether a frame is being built or laid out now (frame_body), before it is drawn: what the view read changing now
/// is built again in this frame (Ctx::read_changed).
let building : Ref[Bool] = Ref::new(false)

///|
/// The view built (a pass of frame_body): what each build collects begins from nothing; the root, the window's size.
fn frame_build(c : Ctx, w : Double, h : Double) -> Int {
  // (who each node the last pass made is, where it is, before the rows' are taken out of the frame's: Ctx::node_known)
  c.nodes_known()
  // (the rows kept as their nodes out of the frame's, for this build to make its own: kept_nodes.mbt)
  c.rows_detach()
  // (what is made once out of the frame's nodes likewise: made.mbt)
  c.made_detach()
  c.moves_build_start()
  c.corner_ladder = c.theme.corner_ladder
  c.corner_fit = c.theme.corner_fit
  c.lit_asked.clear()
  c.hand_chooses.clear()
  c.lit_apart = c.theme.lit_apart
  c.lit_reach = c.theme.lit_reach
  c.window_corner = window_corner()
  for k in 0..<4 {
    c.window_corners[k] = window_corner_at(k)
  }
  // (what an earlier build of this frame said to tell outside is let go: this one says it again, or not)
  c.tells.clear()
  drawing_begin()
  desk_build_start()
  c.built_ids.clear()
  c.marks_ahead.clear()
  c.focus_ahead.clear()
  // (where the build says streams, native views and pictures at a rect of their own are drawn, by node: kept till the
  // next build, a frame painted again alone drawing them where its build said: frame_watch.mbt)
  stream_nodes.clear()
  native_nodes.clear()
  picture_at.clear()
  c.layers.clear()
  c.focusables.clear()
  c.sem_hide = 0
  c.layer_cur = 0
  c.group_cur = 0
  c.count = 0
  c.cur = -1
  c.back_next = None
  c.back_node_next = -1
  c.back_island_next = None
  c.back_chain_next = Unsaid
  let root = c.alloc(kind_box)
  c.nodes[root].w = Px(w)
  c.nodes[root].h = Px(h)
  // (under a change of theme spreading from where it was asked, while it does: reveal.mbt)
  c.with_parent(root, fn() { c.revealed(w, h, fn() { (g_view.val)(c) }) })
  // what lies over the page over everything else (overlay.mbt)
  c.raise_layers()
  root
}

///|
fn bench_step(c : Ctx, cpu : Double, present : Double) -> Unit {
  bench.frames = bench.frames + 1
  if bench.frames == 30 {
    bench.start = c.clock
    bench.speed = -23.0
  }
  if bench.frames > 30 {
    bench.phases[0] = bench.phases[0] + c.t_build
    bench.phases[1] = bench.phases[1] + c.t_layout
    bench.phases[2] = bench.phases[2] + c.t_paint
    bench.cpu.push(cpu)
    bench.present.push(present)
    let gms = h_gpu_ms()
    if gms >= 0.0 {
      bench.gpu.push(gms)
    }
  }
  if bench.frames == 630 {
    let wall = c.clock - bench.start
    let cs = bench.cpu.copy()
    cs.sort_by(fn(a, b) { a.compare(b) })
    let ps = bench.present.copy()
    ps.sort_by(fn(a, b) { a.compare(b) })
    let n = cs.length()
    let mut sum = 0.0
    for x in cs {
      sum = sum + x
    }
    let mut psum = 0.0
    for x in ps {
      psum = psum + x
    }
    let p = fn(a : Array[Double], q : Double) -> Double {
      a[imin(n - 1, (q * n.to_double()).to_int())]
    }
    let mut slow = 0
    for x in bench.cpu {
      if x > 8.0 {
        slow = slow + 1
      }
    }
    let mut first_slow = -1
    for i, x in bench.cpu {
      if x > 8.0 && first_slow < 0 {
        first_slow = i
      }
    }
    h_log("BENCH slow_frames(>8ms)=\{slow} first_slow_at=\{first_slow}")
    let nd = n.to_double()
    h_log(
      "BENCH build_avg=\{bench.phases[0] / nd} layout_avg=\{bench.phases[1] / nd} paint_avg=\{bench.phases[2] / nd} " +
      "flex_sized=\{@flex.counters[0].to_double() / 630.0} flex_cached=\{@flex.counters[1].to_double() / 630.0} flex_measured=\{@flex.counters[2].to_double() / 630.0}",
    )
    h_log(
      "BENCH frames=\{n} wall_ms=\{wall} fps=\{n.to_double() * 1000.0 / wall} " +
      "cpu_avg=\{sum / n.to_double()} cpu_p50=\{p(cs, 0.5)} cpu_p99=\{p(cs, 0.99)} cpu_max=\{cs[n - 1]} " +
      "present_avg=\{psum / n.to_double()} present_p99=\{p(ps, 0.99)} present_max=\{ps[n - 1]} " +
      "nodes=\{c.count} instances=\{c.ninst} rss_mb=\{@hostapi.mem_bytes() / 1048576.0}",
    )
    if bench.gpu.length() > 0 {
      let gs = bench.gpu.copy()
      gs.sort_by(fn(a, b) { a.compare(b) })
      let mut gsum = 0.0
      for x in gs {
        gsum = gsum + x
      }
      let gn = gs.length()
      h_log(
        "BENCH gpu_avg=\{gsum / gn.to_double()} gpu_p50=\{gs[gn / 2]} gpu_p99=\{gs[imin(gn - 1, gn * 99 / 100)]} gpu_max=\{gs[gn - 1]} glass_captures=\{glass_paint.run}",
      )
    }
    if bench.mode == 1 {
      @hostapi.exit(0)
    } else {
      bench.mode = 0
    }
  }
}

///|
/// The pointer's track, for its velocity when let go (scroll.mbt).
let track_x : Tracker = Tracker::new()

///|
let track_y : Tracker = Tracker::new()

///|
/// What an editor holds was written by the app (Field::set, take): an event, as an input is, wherever it came from
/// (an answer between frames, a fiber, a timer); the frame that draws it the framework's to draw.
fn field_written() -> Unit {
  h_request_frame()
}

///|
/// An input came between two frames (the host's, a test's, an action asked by the accessibility): the next frame and
/// the one after it are the framework's to draw (inputrec.mbt `inputs_since`).
fn input_came() -> Unit {
  inputs_since.val = true
  // (a frame owed: what it changed of the hand, what reads it reads, hand.mbt; no event from outside for what is kept,
  // kept_part.mbt)
  h_frame_owed()
}

///|
fn on_pointer(kind : Int, x : Double, y : Double, button : Int) -> Unit {
  // a touch screen's finger as the host has it, by the system's id for it (touches.mbt)
  if kind >= 10 && kind <= 13 {
    touch_in(kind - 10, button, x, y)
    return
  }
  // the keys held as it goes down, read once and kept with it (a replay hands the same on); what the host says it
  // came from, a finger or a mouse, likewise
  pointer_in(kind, x, y, button, if kind == 0 { mods_held() } else { 0 }, by=h_event_finger())
}

///|
/// A pointer's event, with the keys held as it went down (0 for an event other than a press), and what it came from
/// where the host says (`by`: 1 a finger, 0 a mouse or a pen; the hand of the moment from it on: pointing).
fn pointer_in(kind : Int, x : Double, y : Double, button : Int, mods : Int, by? : Int = -1) -> Unit {
  // (one event, at its own moment, the hand it came by so as of then: what was due before it sees the one before, what
  // takes it (the tree's nodes, what they take presses by bound to it, or the old view) this one: view_host.mbt)
  view_event_said(fn() { pointing_said_by_host(by) }, fn() {
    pointer_in_now(kind, x, y, button, mods, by~)
  })
}

///|
fn pointer_in_now(kind : Int, x : Double, y : Double, button : Int, mods : Int, by? : Int = -1) -> Unit {
  let args = [kind.to_double(), x, y, button.to_double(), mods.to_double()]
  if by >= 0 {
    args.push(by.to_double())
  }
  // (where a mouse points, said before the event is taken; what it is over told once it is: view_host.mbt)
  view_point_said(kind, x, y)
  // (what the tree made once routes elsewhere than to the old view (a press on a node of its own, one outside the old
  // view's island) is no input of the old view's: taped alone, view_host.mbt)
  if (kind <= 3 || view_holds()) && view_pointer(kind, x, y, button) {
    view_pointed()
    input_taped("pointer", h_event_time(), args)
    // (a press the window's tree took is outside every layer of the old frame's: what it dismisses so, at its moment,
    // as one the old frame takes is: overlay.mbt)
    if kind == 0 {
      let c = g()
      c.press_down = Some((x, y))
      c.press_down_tree = true
      c.layer_keys_now()
    }
  } else {
    took_input("pointer", h_event_time(), args)
    view_pointed()
    old_pointer_now(kind, x, y, button, mods, h_event_time())
  }
  // (a finger or button down, wherever it went (a node of the tree's, the old view): a press of its own from here, a
  // hold handed before it none's, view_handed)
  if kind == 0 || kind == 4 {
    downs_made.val = downs_made.val + 1
  }
}

///|
/// A pointer's event the old frame takes (pointer_in_now's, or a hold the window's tree handed it: view_through_old),
/// at `t` (the host's event's moment; a hold handed on, when the finger went down).
fn old_pointer_now(kind : Int, x : Double, y : Double, button : Int, mods : Int, t : Double) -> Unit {
  // (a press down, up or called off, a second finger, the pointer gone: what reads what came is built again; a pointer
  // moved is the hand's place, read by what reads it: hand.mbt)
  if kind != 1 {
    hand_pressed()
  }
  // (a move that changed nothing but where a list stands, said by its signal: no input taken by what is built,
  // inputrec.mbt)
  let mut quiet = false
  let c = g()
  // a second finger (4 down, 5 moved, 6 up: hosts with touch screens; 8 the first let go, the second the first from
  // here), for a pinch (native.mbt `second_pointer`)
  if (kind >= 4 && kind <= 6) || kind == 8 {
    on_second(if kind == 8 { 6 } else { kind }, x, y)
    // one of two lifted: the moves from here may be the other's, its own track
    if kind == 6 || kind == 8 {
      track_x.reset()
      track_y.reset()
    }
    return
  }
  // the pointer gone out of the window (7); a secondary button (a right click: its menu's, nothing pressed)
  if kind == 7 {
    c.pointer_left()
    c.bar_pointer(-1.0, -1.0)
    return
  }
  if button == 2 {
    if kind == 0 {
      c.secondary_press(x, y)
    }
    return
  }
  c.px = x
  c.py = y
  // the event's own time (`t`): events handled together happened apart
  c.pointer_t = t
  if scroll_logging() {
    h_log("TOUCH \{kind} \{t} \{x} \{y} \{h_now()}")
  }
  if kind == 0 {
    let target = hit_in(c.hit_ids, c.hit_rects, x, y)
    // a scroll bar's thumb (a mouse's, scroll_bar.mbt): held from here, the press nothing else's (no tap, no words
    // picked, the focus where it is)
    if c.bar_press(target) {
      c.press_down = Some((x, y))
      c.layer_keys_now()
      c.down = true
      c.active = 0
      c.press_x = x
      c.press_y = y
      c.press_at = t
      c.taken_at = t
      c.last_x = x
      c.last_y = y
      c.last_t = t
      c.press_chain.clear()
      c.drag_scroll = 0
      c.claimed = true
      c.dragging = false
      c.edge = 0
      h_request_frame()
      return
    }
    // the app's own top row: the window is the host's to move from here (it takes the rest of the press)
    if desk_drags(target) {
      h_window_drag()
      return
    }
    // how many presses in a row this one is (NSEvent's clickCount: a double click's second 2, a triple's third 3):
    // one soon after the last (double_click_ms) and near it (double_click_slop) counts on from it
    let (n, at, ax, ay) = c.press_run
    c.clicks = if t - at <= double_click_ms &&
      (x - ax).abs() <= double_click_slop &&
      (y - ay).abs() <= double_click_slop {
      n + 1
    } else {
      1
    }
    c.press_run = (c.clicks, t, x, y)
    // words picked with the pointer (desktop.mbt), not in a field, nor on what keeps them (Ctx::keeps_selection);
    // picking them lets go of what the focused field had picked, the focus staying its (focus.mbt): one thing picked
    // in the window, as in a browser, and it is what ⌘C copies
    if !c.editors.contains(target) && !keeps_selection_on(target) {
      c.select_press(x, y, c.clicks)
      match c.editors.get(c.focus_allowed()) {
        Some(st) if picked.from.base != 0 => st.anchor = st.caret
        _ => ()
      }
    }
    // what lies over the page sees it (overlay.mbt); the focus goes as a press moves it (focus.mbt)
    c.press_down = Some((x, y))
    // (the layers it is outside of dismissed at its moment: overlay.mbt)
    c.layer_keys_now()
    c.focus_on_press(target)
    c.press_mods = mods
    c.down = true
    c.active = target
    c.press_on_at(target, x, y)
    c.press_x = x
    c.press_y = y
    c.press_at = t
    c.press_strayed = false
    // (not taken yet: one taken before at the same moment is not this one)
    c.taken_at = -1.0
    c.last_y = y
    c.last_x = x
    c.vel_x = 0.0
    c.last_t = t
    c.vel = 0.0
    c.dragging = false
    track_x.reset()
    track_y.reset()
    track_x.add(t, x)
    track_y.add(t, y)
    // what lies under it waits for the finger's way (claim.mbt); the innermost meanwhile
    claim_down(c, x, y)
    for id in c.press_chain {
      sideways_down(c, id, x, y)
    }
    c.editor_drag = false
    c.handle_drag = 0
    c.word_drag = 0
    // a selection's handle under the finger (Android's): the finger moves that end, the menu away meanwhile
    match c.editors.get(c.focus_allowed()) {
      Some(st) if st.on_sel_handle(x, y) != 0 => {
        c.handle_which = st.on_sel_handle(x, y)
        c.handle_drag = c.focus
        c.handle_dy = y - (if c.handle_which == 2 { st.sel_ay } else { st.sel_by })
        st.menu = false
        c.claimed = true
        for other in c.press_chain {
          drag_cancel(other)
        }
        c.active = 0
        c.edge = 0
        h_request_frame()
        return
      }
      _ => ()
    }
    // the caret's handle under the finger (Android's): the finger moves the caret, nothing under it pressed or scrolled
    match c.editors.get(c.focus_allowed()) {
      Some(st) if st.on_handle(x, y) => {
        c.handle_which = 1
        c.handle_drag = c.focus
        c.handle_dy = y - st.handle_y
        c.claimed = true
        for other in c.press_chain {
          drag_cancel(other)
        }
        c.active = 0
        c.edge = 0
        h_request_frame()
        return
      }
      _ => ()
    }
    c.edge = if c.on_edge(x, y) { 1 } else { 0 }
    // a drag area under it (a sheet's top, the bottom bar, a row or a card swiped across): no edge swipe under it
    for id in c.press_chain {
      if drag_down(id, x, y) {
        c.edge = 0
      }
    }
    // a desktop's page: the mouse drags no list and swipes no page back (the wheel scrolls; Ctx::mouse_drags_lists)
    if !desk.mouse_drags {
      c.edge = 0
      if c.lists.contains(c.drag_scroll) {
        c.drag_scroll = 0
      }
    }
    c.press_late = h_feel() == 2 && c.drag_scroll != 0
    // a list moving on its own (flung, springing back from an end) is caught wherever on it the finger lands, and the
    // press presses nothing in it: the finger drags it from there at once; on what scrolls or drags its own way in it
    // (a table or a code block that scrolls sideways, a row swiped across), stopped, the press goes the finger's way
    // as ever (claim.mbt)
    let mut caught = 0
    if desk.mouse_drags {
      for id in c.press_chain {
        if caught == 0 && c.lists.get(id) is Some(st) && st.moving() {
          caught = id
        }
      }
    }
    match c.lists.get(caught) {
      Some(st) => {
        st.catch_up()
        if caught == c.drag_scroll {
          c.claimed = true
          for other in c.press_chain {
            if other != c.drag_scroll {
              drag_cancel(other)
            }
          }
          st.held = true
          c.dragging = true
        }
        // (no tap of anything, of a row's drag area or anywhere, once lifted)
        c.active = 0
        c.taken_at = c.press_at
        c.edge = 0
        h_request_frame()
        return
      }
      None =>
        match c.lists.get(c.drag_scroll) {
          Some(st) => st.stop()
          None => ()
        }
    }
    c.editor_tap = 0
    match c.editors.get(target) {
      // Android's: a field takes the focus and the caret where it is tapped, the finger lifted where it came down
      // (Compose's tap); a finger that moves on drags what is under it (the list), the field untouched
      Some(_) if h_feel() == 2 => c.editor_tap = target
      Some(st) => {
        c.focus_moved(target)
        c.editor_drag = true
        // a press with Shift: what is picked widened to it; a double click's second the word there, a triple's the
        // paragraph, the drag on from it going by them (a Mac's fields, a browser's)
        if (mods & mod_shift_key) != 0 {
          st.widen_by_pointer(x, y, t)
        } else {
          place_caret(st, x, y, t)
          if c.clicks > 1 {
            st.pick_at(if c.clicks == 2 { Words } else { Paragraphs })
          }
        }
      }
      // (on nothing: the focus let go, where it may take input now; one a modal layer of the window's tree keeps from
      // input, kept as it is, view_host.mbt)
      None => if target == 0 && c.focus_allowed() != 0 { c.focus_moved(0) }
    }
  } else if kind == 1 {
    // a bar's thumb held: what it is for follows the pointer, nothing else sees it move
    if c.bar_drag != 0 {
      c.bar_drag_move(x, y)
      c.last_x = x
      c.last_y = y
      c.last_t = t
      h_request_frame()
      return
    }
    // (a finger hovers over nothing: Pointing)
    if pointing() is Mouse {
      c.point_at(x, y)
    }
    c.bar_pointer(x, y)
    if c.down {
      track_x.add(t, x)
      track_y.add(t, y)
      // moved past the slop: no long press of it (Android's), and on a field no tap either
      if (x - c.press_x).abs() > touch_slop() || (y - c.press_y).abs() > touch_slop() {
        c.press_strayed = true
        c.editor_tap = 0
      }
      // (a page already following the finger back, from the edge: its moves are where it is, Nav's `finger`)
      let edge_following = c.edge == 2
      if c.handle_drag != 0 {
        handle_move(c, x, y, t)
      } else if c.word_drag != 0 {
        // sliding on from a long press's word: widened by words (the menu away meanwhile)
        match c.editors.get(c.word_drag) {
          Some(st) => {
            st.widen_to(x, y)
            st.menu = false
            h_request_frame()
          }
          None => ()
        }
      } else if c.edge > 0 && c.edge_move(x, y, t) {
        quiet = edge_following
      } else if c.select_move(x, y) {
        // picking words: the press is no tap
        c.active = 0
      } else if c.editor_drag {
        match c.editors.get(c.active) {
          Some(st) if c.clicks > 1 && (c.press_mods & mod_shift_key) == 0 =>
            st.widen_to(x, y, by=if c.clicks == 2 { Words } else { Paragraphs })
          Some(st) =>
            match st.tl {
              Some(tl) => st.caret_to_point(tl, x, y)
              None => ()
            }
          None => ()
        }
      } else if !claim_move(c, x, y) {
        // no one's yet: nothing moves
        quiet = true
      } else if sideways.contains(c.drag_scroll) &&
        !sideways_move(c, c.drag_scroll, x, y) {
        // dragged sideways (or not yet past the slop); moved up or down first, the list takes it below
        ()
      } else if drags.contains(c.drag_scroll) {
        if drag_move(c.drag_scroll, x, y) && !c.dragging {
          c.dragging = true
          c.active = 0
        }
      } else if c.drag_scroll != 0 && !captures.contains(c.drag_scroll) {
        // a pager follows the finger sideways, a list up and down
        let pager = pagers.contains(c.drag_scroll)
        if !c.dragging {
          let moved = if pager { x - c.press_x } else { y - c.press_y }
          let slop = touch_slop()
          if moved.abs() > slop {
            c.dragging = true
            c.active = 0
            if !pager {
              c.scroll_lets_go(c.drag_scroll)
            }
            // from where the slop ends, as Compose starts a drag: nothing
            // jumps, and what moved past the slop is not lost
            let past = if moved > 0.0 { moved - slop } else { moved + slop }
            if pager {
              c.pager_drag(c.drag_scroll, past) |> ignore
            } else {
              c.list_drag(c.drag_scroll, -past)
            }
          } else {
            // (within the slop: nothing moves)
            quiet = true
          }
        } else if pager {
          c.pager_drag(c.drag_scroll, x - c.last_x) |> ignore
        } else {
          // (the list follows the finger: where it stands is its signal's, ListState::hand_moved)
          c.list_drag(c.drag_scroll, -(y - c.last_y))
          quiet = true
        }
      }
      c.last_y = y
      c.last_x = x
      c.last_t = t
    }
  } else if kind == 2 {
    // a bar's thumb let go: its bar shows a while more
    if c.bar_press_off() {
      return
    }
    if c.down {
      track_x.add(t, x)
      track_y.add(t, y)
    }
    if c.edge == 2 {
      c.back_gesture(2, x, t) |> ignore
    }
    c.edge = 0
    let target = hit_in(c.hit_ids, c.hit_rects, x, y)
    if c.active != 0 && target == c.active && !c.dragging {
      c.clicked.push(c.active)
      c.click_at = Some((x, y))
      // the second of two (Ctx::double_clicked): on the same, soon enough and near enough; then none is first
      let (was, at, ax, ay) = c.last_click
      if was == c.active && t - at <= double_click_ms && (x - ax).abs() <= double_click_slop &&
        (y - ay).abs() <= double_click_slop {
        c.double_clicked.push(c.active)
        c.last_click = (0, 0.0, 0.0, 0.0)
      } else {
        c.last_click = (c.active, t, x, y)
      }
      // (what was said a press on it does, done as it is let go, where it was let go: Ctx::on_press, made.mbt)
      made_pressed(c.active)
    }
    // a tap wherever it lands (Ctx::tapped_anywhere), not a drag, not a press the app took
    if !c.dragging && c.taken_at != c.press_at {
      c.tapped = Some((x, y))
    }
    // taken by none: the innermost's tap (as a press on it alone); the others let it go
    for other in c.press_chain {
      if other != c.drag_scroll {
        drag_cancel(other)
      }
    }
    if drags.contains(c.drag_scroll) {
      drag_up(
        c.drag_scroll,
        x,
        y,
        dclamp(track_x.velocity(), -max_fling, max_fling),
        dclamp(track_y.velocity(), -max_fling, max_fling),
        c.taken_at == c.press_at,
      )
    }
    if c.dragging {
      match c.lists.get(c.drag_scroll) {
        Some(st) =>
          c.release(st, dclamp(-track_y.velocity(), -max_fling, max_fling), t)
        None => ()
      }
      sideways_up(
        c,
        c.drag_scroll,
        dclamp(track_x.velocity(), -max_fling, max_fling),
        dclamp(track_y.velocity(), -max_fling, max_fling),
      )
      if pagers.contains(c.drag_scroll) {
        c.pager_release(
          c.drag_scroll,
          dclamp(track_x.velocity(), -max_fling, max_fling),
        )
      }
    }
    // a tap on a field (Android's): the focus and the caret where it was tapped, its handle under the caret
    if c.editor_tap != 0 &&
      !c.dragging &&
      (x - c.press_x).abs() <= touch_slop() &&
      (y - c.press_y).abs() <= touch_slop() {
      match c.editors.get(c.editor_tap) {
        Some(st) => {
          // (tapped again: said to the host anew, which asks for its keyboard again if none is up)
          if c.focus == c.editor_tap {
            c.ime_sig = "tap"
          }
          c.focus_moved(c.editor_tap)
          let (was, at, lx, ly) = c.last_tap
          if was == c.editor_tap &&
            t - at <= double_tap_ms &&
            (c.press_x - lx).abs() <= 2.0 * touch_slop() &&
            (c.press_y - ly).abs() <= 2.0 * touch_slop() {
            // a second tap soon after the first, near it: the word there picked (Compose's double tap)
            st.pick_word(c.press_x, c.press_y, t) |> ignore
            c.last_tap = (0, -1.0e9, 0.0, 0.0)
          } else {
            place_caret(st, c.press_x, c.press_y, t)
            st.handle = st.text.length() > 0
            c.last_tap = (c.editor_tap, t, c.press_x, c.press_y)
          }
          h_request_frame()
        }
        None => ()
      }
    }
    // a handle let go: the menu back over what is picked; the caret's handle tapped (not moved): its menu (粘贴) shown
    // or put away
    if c.handle_drag != 0 {
      match c.editors.get(c.handle_drag) {
        Some(st) =>
          if c.handle_which == 1 {
            if (x - c.press_x).abs() <= touch_slop() && (y - c.press_y).abs() <= touch_slop() {
              st.menu = !st.menu
            }
          } else {
            st.menu = true
          }
        None => ()
      }
      h_request_frame()
    }
    // a long press's word slid on from, let go: the menu over it
    if c.word_drag != 0 {
      match c.editors.get(c.word_drag) {
        Some(st) => st.menu = true
        None => ()
      }
      h_request_frame()
    }
    c.word_drag = 0
    c.editor_tap = 0
    c.down = false
    c.dragging = false
    c.active = 0
    c.editor_drag = false
    c.handle_drag = 0
    picked.dragging = false
    select_edge_stop()
    second_ptr[2] = 0.0
  } else {
    c.press_called_off(x, y, t)
  }
  // (moved, nothing held down, or but a list moved by it: a frame owed, what it changed of the hand read by what reads
  // it, hand.mbt, and of the list by what lays it out; else what the press did, come from outside what is a signal yet)
  if kind == 1 && (!c.down || quiet) {
    h_frame_owed()
  } else {
    // (a drag: taken by what is built, inputrec.mbt)
    inputs_taken.val = true
    h_request_frame()
  }
}

///|
/// A bar's thumb held by the press let go (as the press ends or is called off), nothing else of the press's done: false
/// where it held none.
fn Ctx::bar_press_off(self : Ctx) -> Bool {
  if self.bar_drag == 0 {
    return false
  }
  self.bar_let_go()
  self.down = false
  self.dragging = false
  self.active = 0
  h_request_frame()
  true
}

///|
/// The press held called off at (x, y) at `t` (the host's word, or a modal layer of the window's tree come over the old
/// view it was on: view_host.mbt): no tap, no handle dragged, what it dragged let go where it is.
fn Ctx::press_called_off(self : Ctx, x : Double, y : Double, t : Double) -> Unit {
  let c = self
  // (a bar's thumb held: let go, its bar shows a while more)
  if c.bar_press_off() {
    return
  }
  c.editor_tap = 0
  c.handle_drag = 0
  c.word_drag = 0
  // (a hold handed here and not taken yet: called off with the press)
  view_handed.val = None
  if c.edge == 2 {
    c.back_gesture(3, x, t) |> ignore
  }
  c.edge = 0
  for id in c.press_chain {
    drag_cancel(id)
  }
  if drags.contains(c.drag_scroll) {
    drag_up(c.drag_scroll, x, y, 0.0, 0.0, true)
  }
  if c.dragging {
    match c.lists.get(c.drag_scroll) {
      Some(st) => c.release(st, 0.0, t)
      None => ()
    }
    sideways_up(c, c.drag_scroll, 0.0, 0.0)
    if pagers.contains(c.drag_scroll) {
      c.pager_release(c.drag_scroll, 0.0)
    }
  }
  // (words being picked by it: picked as far as they are, no more, nothing scrolled on at an edge for it)
  picked.dragging = false
  select_edge_stop()
  c.down = false
  c.dragging = false
  c.active = 0
  second_ptr[2] = 0.0
}

///|
/// A finger dragging list `id` by `d` (positive down the list).
fn Ctx::list_drag(self : Ctx, id : Int, d : Double) -> Unit {
  match self.lists.get(id) {
    Some(st) => {
      st.held = true
      self.feed(st, d, 1)
      st.hand_moved()
    }
    None => ()
  }
}

///|
/// Whether a press at (x, y) is on the left edge of the stack that takes
/// back (Ctx::nav), where a swipe back starts. None on Android: there the
/// swipe from the edge is the system's back gesture (on_back), as still.fail's
/// Android app has no other. One of these started beside it too, and the
/// system taking the finger from the app once it had decided (a cancel here)
/// called the page back to its place mid-swipe, deaf to the system's steps
/// after it.
fn Ctx::on_edge(self : Ctx, x : Double, y : Double) -> Bool {
  if h_platform() == 2 {
    return false
  }
  // (whose back it is may take presses now: no modal layer of the window's tree over it, view_host.mbt)
  if !old_owner_open(self.back_owner()) {
    return false
  }
  match self.back {
    Some(_) if self.back_node >= 0 && self.back_node < self.count => {
      let n = self.nodes[self.back_node]
      x >= n.x && x < n.x + self.back_edge && y >= n.y && y < n.y + n.fh
    }
    _ => false
  }
}

///|
/// The back gesture's step to the stack that takes back: x in its own terms (from its left), its width; the system's
/// progress where it is the system's (on_back). A gesture is held from its start (0) by what takes back then, where it
/// was then and the old view it is of (BackHeld): each step after goes to that one alone, whatever takes back by then; as
/// that old view may take input no more (gone, a modal layer of the window's tree over it), it is called off for it once
/// and the rest of the gesture is nobody's (false). Done (2, 4) or called off (3), let go. A step with none held (a back
/// said with no gesture) goes to what takes back now.
fn Ctx::back_gesture(self : Ctx, kind : Int, x : Double, t : Double, progress? : Double = -1.0) -> Bool {
  match (kind, self.back_held) {
    (0, _) | (_, None) => {
      if kind != 0 && self.back_off {
        // (the rest of one called off: nobody's)
        if kind >= 2 {
          self.back_off = false
        }
        return false
      }
      // (what takes back now: a node of the window's tree's, else what the old views said: Ctx::back_taker)
      guard self.back_taker() is Some(h) else { return false }
      if kind == 0 {
        self.back_off = false
        self.back_held = Some(h)
      }
      (h.f)(kind, x - h.left, h.w, t, progress)
      true
    }
    (_, Some(h)) => {
      if kind >= 2 {
        self.back_held = None
      }
      if kind != 3 && !old_owner_open(h.owner) {
        // (its old view taking input no more: called off for it, once, the rest of the gesture nobody's)
        self.back_held = None
        self.back_off = kind < 2
        (h.f)(3, x - h.left, h.w, t, -1.0)
        return false
      }
      // (done as the system decided: the end of the gesture held, not a back with no gesture)
      if kind == 4 {
        (h.done)(x - h.left, t, progress)
      } else {
        (h.f)(kind, x - h.left, h.w, t, progress)
      }
      true
    }
  }
}

///|
/// A back gesture held from its start (Ctx::back_gesture): what takes it, where that was then (its left, its width), and
/// the old view it is of (none: what the old frame put over all of it at its root).
struct BackHeld {
  f : (Int, Double, Double, Double, Double) -> Unit
  left : Double
  w : Double
  owner : @view.NodeId?
  /// whether it is a node of the window's tree's (what back does there is no input of the old views')
  tree : Bool
  /// the gesture it holds done as the system decided (x from its left, the moment, the system's progress): told so
  /// as that gesture's end, not as a back with no gesture (a node's: Tree::back_done)
  done : (Double, Double, Double) -> Unit
}

///|
/// A finger that went down on the left edge: once it has moved sideways
/// more than up or down, it moves the page back (and nothing under it sees
/// it); up or down first, it is the list's. True while it is the page's.
fn Ctx::edge_move(self : Ctx, x : Double, y : Double, t : Double) -> Bool {
  if self.edge == 1 {
    let dx = x - self.press_x
    let dy = y - self.press_y
    if dx > 6.0 && dx.abs() > dy.abs() {
      self.edge = 2
      self.active = 0
      self.dragging = true
      self.drag_scroll = 0
      self.editor_drag = false
      self.back_gesture(0, self.press_x, self.last_t) |> ignore
    } else if dy.abs() > 6.0 || dx < -6.0 {
      self.edge = 0
    }
  }
  if self.edge == 2 {
    self.back_gesture(1, x, t) |> ignore
    self.last_x = x
    self.last_y = y
    self.last_t = t
    return true
  }
  false
}

///|
/// The system's back (host_native.mbt set_back): its gesture followed (x
/// from the edge it came from), let go to go back, called off; or a back
/// with no gesture. Its steps are the hand's events but where it is as it goes: that is where what follows it reads it
/// (Nav's `finger`), as a pointer moved is (inputrec.mbt).
fn on_back(kind : Int, x : Double, progress : Double, edge : Int) -> Unit {
  // (one event, at its own moment: view_host.mbt)
  view_event(fn() { on_back_now(kind, x, progress, edge) })
}

///|
fn on_back_now(kind : Int, x : Double, progress : Double, edge : Int) -> Unit {
  let c = g()
  // (what takes it as it goes (held from its start), or what will as it begins: a node of the window's tree's, or the
  // rest of one called off, nobody's: no input of the old views', taped alone; else theirs)
  let theirs = match (kind, c.back_held) {
    (0, _) | (_, None) =>
      if kind != 0 && c.back_off {
        false
      } else {
        match c.back_taker() {
          Some(h) => !h.tree
          None => true
        }
      }
    (_, Some(h)) => !h.tree
  }
  let args = [kind.to_double(), x, progress, edge.to_double()]
  if theirs {
    took_input("back", h_now(), args)
    if kind != 1 {
      hand_event()
    }
  } else {
    input_taped("back", h_now(), args)
  }
  // (the event's own moment, taken once as it began: view_host.mbt)
  let t = view_moment()
  // from the right edge, the finger's way is mirrored
  let from_left = if edge == 1 { c.width - x } else { x }
  match kind {
    // (begun where what takes back may take input now (view_host.mbt's old_owner_open): held by it from here,
    // Ctx::back_gesture; else the whole of it nobody's)
    0 =>
      if c.back_open() {
        c.back_gesture(0, from_left, t, progress~) |> ignore
      } else {
        c.back_held = None
        c.back_off = true
      }
    1 => c.back_gesture(1, from_left, t, progress~) |> ignore
    // (back said with no gesture: what takes back now, where it may take input)
    2 if c.back_held is None && !c.back_off =>
      if c.back_open() {
        c.back_gesture(4, 0.0, t) |> ignore
      }
    2 => c.back_gesture(4, 0.0, t) |> ignore
    _ => c.back_gesture(3, 0.0, t) |> ignore
  }
  // (a step on: a frame owed, where the finger has it read by what reads it, as a pointer moved is; one a node of the
  // tree's took: a frame owed, what it changed told by its signals; else what began, ended or was called off, come from
  // outside what is a signal yet)
  if kind == 1 || !theirs {
    h_frame_owed()
  } else {
    h_request_frame()
  }
}

///|
fn on_wheel(x : Double, y : Double, dx : Double, dy : Double, phase : Int) -> Unit {
  // (one event, at its own moment: view_host.mbt)
  view_event(fn() { on_wheel_now(x, y, dx, dy, phase) })
}

///|
fn on_wheel_now(x : Double, y : Double, dx : Double, dy : Double, phase : Int) -> Unit {
  // what was held with it, above its phase (wheel_mod_*: ⇧ ⌃ ⌥ ⌘, and a trackpad's pinch as a wheel with ⌃ held)
  let mods = phase / 16
  // (over a node of the window's tree's that takes the wheel: its, at the wheel's own moment, where it is then; no input
  // of the old view's: taped alone)
  if view_wheel(x, y, dx, dy, mods) {
    input_taped("wheel", h_event_time(), [x, y, dx, dy, phase.to_double()])
    return
  }
  took_input("wheel", h_event_time(), [x, y, dx, dy, phase.to_double()])
  let phase = phase % 16
  let c = g()
  let mut target = hit_in(c.scroll_ids, c.scroll_rects, x, y)
  // (what scrolls there in an old view a modal layer of the window's tree keeps from input: nothing scrolls, the wheel
  // taken: island_allows)
  if target != 0 && !island_allows(c.island_of_id(target)) {
    wheel_taken()
    return
  }
  // over what scrolls sideways: its sideways part moves it, the rest goes to the list it lies in
  if sideways.contains(target) {
    if sideways_wheel(target, dx, dy) {
      wheel_taken()
      h_request_frame()
      return
    }
    target = outer_scroll(c, x, y)
  }
  if captures.contains(target) {
    // a box that takes the pointer keeps the wheel (native.mbt `wheel`, `wheel_of`)
    wheels[target] = wheels.get(target).unwrap_or(0.0) + dy
    wheels_x[target] = wheels_x.get(target).unwrap_or(0.0) + dx
    wheel_mods[target] = mods
    wheel_taken()
    h_request_frame()
    return
  }
  // a pinch is what holds a page's own (a picture's zoom): no list scrolls by it
  if (mods & wheel_mod_pinch) != 0 {
    wheel_taken()
    return
  }
  match c.lists.get(target) {
    Some(st) => {
      st.stop()
      // a wheel's notch (phase 4): eased over a few frames, as a browser does; a trackpad's (and its momentum's)
      // follows the fingers as it comes
      if phase == 4 {
        c.ease_list(target, dy, h_event_time())
      } else {
        c.scroll_list(target, dy)
      }
      // (where it stands its signal's: what lays it out lays it out again, nothing taken by what is built; where parts
      // are kept as drawn, kept_part.mbt, an event from outside for the part or the row it turns in)
      st.hand_moved()
      h_request_frame()
    }
    None => wheel_taken()
  }
}

///|
/// A wheel turned over what is no list (what scrolls sideways, what takes the pointer, a pinch, nothing that scrolls):
/// what it changed is no signal yet, taken by what is built (inputrec.mbt: an input taken, come from outside).
fn wheel_taken() -> Unit {
  inputs_taken.val = true
  outside_came()
}

///|
fn on_key(code : Int, mods : Int) -> Unit {
  // (one event, at its own moment: view_host.mbt)
  view_event(fn() { on_key_now(code, mods) })
}

///|
fn on_key_now(code : Int, mods : Int) -> Unit {
  // what the part over the field with the focus said it takes of its keys, at their moment, before the field, the
  // tree's Tab or the frame (Ctx::on_key): the one place a key is handed it or not
  if keys_taken_now(g().focus_allowed(), code, mods) {
    took_input("key", h_now(), [code.to_double(), mods.to_double()])
    hand_event()
    h_request_frame()
    return
  }
  // (taken by a node of the window's tree, at its moment: no input of the old views', taped alone: view_host.mbt)
  if view_key(code, mods) {
    input_taped("key", h_now(), [code.to_double(), mods.to_double()])
    return
  }
  took_input("key", h_now(), [code.to_double(), mods.to_double()])
  hand_event()
  key_in(code, mods)
  // (Escape to the topmost layer it dismisses, at its moment: overlay.mbt)
  if code == key_escape {
    g().layer_keys_now()
  }
}

///|
/// A key, taken as it came (on_key) or as the input method's deleting stands for it (on_text).
fn key_in(code : Int, mods : Int) -> Unit {
  let c = g()
  // (the focus where a modal layer of the window's tree lets it take input; else none's, for this key: island_allows)
  let focus = c.focus_allowed()
  // a key catcher's while it has the focus: all of it (device.mbt)
  if catcher_key(c, code, mods) {
    return
  }
  // (a field with the focus under a layer the keys go to, modal, a menu with the focus in it, Ctx::keys_reach: its keys
  // not its; that layer's to read as the frame takes them, Ctx::key_pressed)
  let under = c.editors.contains(focus) && !c.keys_reach(focus)
  let focus = if under { 0 } else { focus }
  // ⌘Z, ⇧⌘Z (Ctrl+Z, Ctrl+Y elsewhere) with a field focused: its edits undone and done again (editor_undo.mbt)
  let step = if c.editors.contains(focus) { step_of(code, mods, h_keys()) } else { None }
  // every key the app may read (Ctx::key_pressed), and whether the focused field takes it (the editor's own keys)
  desk_key(code, mods, c.editors.contains(focus) && (field_key(code) || step is Some(_)))
  if under {
    h_request_frame()
    return
  }
  // ⌘V (Ctrl+V) as the app's key: the host saw files or a picture on the clipboard (mac_app.m, win_app.c), read for
  // the field focused (Ctx::editor: them where it takes files, its words where it does not)
  if code == key_of_char('v') && (mods & (mod_cmd | mod_ctrl)) != 0 && c.editors.contains(focus) {
    match clipboard_read() {
      Some(r) => desk.pasting = Some((focus, r))
      None => ()
    }
  }
  // ⌘C: the words picked with the pointer, unless the focused field has words of its own picked (a field keeps the
  // focus through a press on the page's words, which lets go of what it had picked: the press above)
  if code == key_copy && selected_words() != "" && !field_picks(c) {
    h_clipboard_set(selected_words())
    return
  }
  match (c.editors.get(focus), step) {
    (Some(st), Some(s)) => {
      st.step(s, h_now())
      h_request_frame()
      return
    }
    _ => ()
  }
  if !field_key(code) {
    h_request_frame()
    return
  }
  match c.editors.get(focus) {
    Some(st) => {
      st.key(code, mods, h_now())
      h_request_frame()
    }
    None => {
      let target = hit_in(c.scroll_ids, c.scroll_rects, c.px, c.py)
      // a key the focused widget takes (focus.mbt) scrolls nothing under the pointer; nor one in an old view a modal
      // layer of the window's tree keeps from input (island_allows)
      if target != 0 &&
        island_allows(c.island_of_id(target)) &&
        !c.focus_takes(code) &&
        (c.list_key(target, code) || c.pager_key(target, code)) {
        h_request_frame()
      }
    }
  }
}

///|
fn on_text(kind : Int, s : String, a : Int, b : Int) -> Unit {
  // (one event, at its own moment: view_host.mbt)
  view_event(fn() { on_text_now(kind, s, a, b) })
}

///|
fn on_text_now(kind : Int, s : String, a : Int, b : Int) -> Unit {
  took_input("text", h_now(), [kind.to_double(), a.to_double(), b.to_double()], text=s)
  hand_event()
  let c = g()
  // (words for a focus a modal layer of the window's tree keeps from input: none's, island_allows)
  if c.focus != 0 && c.focus_allowed() == 0 {
    return
  }
  // the keyboard put away by the person: what has the focus lets go of it (what is composed stays, as words)
  if kind == text_keyboard_gone {
    match c.editors.get(c.focus) {
      Some(st) if st.marked.length() > 0 => st.text_input(2, "", 0, 0, h_now())
      _ => ()
    }
    if c.editors.contains(c.focus) || c.dev.catchers.contains(c.focus) {
      c.focus_moved(0)
      h_request_frame()
    }
    return
  }
  // a key catcher's while it has the focus (device.mbt)
  if catcher_text(c, kind, s, a, b) {
    return
  }
  // the input method deleting around the caret (`a` before, `b` after: Android's deleteSurroundingText): a field's
  // Backspace, its Delete
  if kind == text_delete_around {
    if a > 0 {
      key_in(key_backspace, 0)
    }
    if b > 0 {
      key_in(key_delete, 0)
    }
    return
  }
  match c.editors.get(c.focus) {
    Some(st) if kind == text_float_begin || kind == text_float_move => {
      float_caret(st, kind, a.to_double(), b.to_double(), h_now())
      h_request_frame()
    }
    Some(st) => {
      st.text_input(kind, s, a, b, h_now())
      h_request_frame()
    }
    None => ()
  }
}

///|
/// The keyboard's trackpad in field `st` (on_text's text_float_begin, text_float_move, at (`x`, `y`) in the window):
/// the caret put as a pointer would put it as far from where the caret was when it began as (`x`, `y`) is from where it
/// began, as iOS's own fields move theirs (the host's point is the finger's way, not a place in the words); counted in
/// the field's words, as the field scrolls under it to follow the caret.
fn float_caret(st : EditorState, kind : Int, x : Double, y : Double, t : Double) -> Unit {
  guard st.tl is Some(tl) else { return }
  if kind == text_float_begin {
    let (cx, line) = st.place_of(tl, st.caret + st.marked.length())
    st.floating = Some((x, y, cx, (line.to_double() + 0.5) * tl.line_h))
    return
  }
  guard st.floating is Some((fx, fy, cx, cy)) else { return }
  place_caret(st, st.ox + cx + x - fx, st.oy + cy + y - fy, t)
}

///|
/// The caret put where (`x`, `y`) is in the field `st` (what is composed committed first), its blinking from `t`.
fn place_caret(st : EditorState, x : Double, y : Double, t : Double) -> Unit {
  st.blink0 = t
  st.menu = false
  st.sel_handles = false
  match st.tl {
    Some(tl) => {
      if st.marked.length() > 0 {
        st.text_input(2, "", 0, 0, t)
      }
      st.caret_to_point(tl, x, y)
      st.anchor = st.caret
    }
    None => ()
  }
}

///|
/// The caret's handle dragged to (`x`, `y`): the caret where the handle's tip comes, in the middle of the line over it.
fn handle_move(c : Ctx, x : Double, y : Double, t : Double) -> Unit {
  match c.editors.get(c.handle_drag) {
    Some(st) if c.handle_which >= 2 => {
      st.sel_handle_to(c.handle_which, x, y, c.handle_dy)
      st.blink0 = t
      h_request_frame()
    }
    Some(st) =>
      match st.tl {
        Some(tl) => {
          let tip = y - c.handle_dy
          st.caret_to_point(tl, x, tip - tl.line_h / 2.0)
          st.anchor = st.caret
          st.blink0 = t
          h_request_frame()
        }
        None => ()
      }
    None => ()
  }
}

///|
/// Moves focus to an editor (used by tests and the bench).
pub fn Ctx::focus_editor(self : Ctx, key : String) -> Unit {
  self.focus_moved(self.id(key))
}

///|
/// Whether the app is shown (1) and in front (2), as the host last said (shown and in front until it says).
let app_state : Ref[Int] = Ref::new(3)

///|
/// Who is told when that changes (the app's one: `on_app_change`).
let app_change : Ref[((Bool, Bool) -> Unit)?] = Ref::new(None)

///|
fn on_app_state(s : Int) -> Unit {
  // (one event, at its own moment: view_host.mbt)
  view_event(fn() { on_app_state_now(s) })
}

///|
fn on_app_state_now(s : Int) -> Unit {
  took_input("app", h_now(), [s.to_double()])
  // (what the host says of the app: come from outside, frame_watch.mbt)
  outside_counted()
  // a scripted run stands for someone looking at the app: what the host says meanwhile (a locked screen's window
  // is covered, a task's app not active) is let be
  if driver.val is Some(d) {
    if !d.takes_state {
      h_log("DRIVE the host says the app is \{s} (1 shown, 2 in front): kept in front for the run")
    }
    // (shown again after it was not: what a run's `shown` waits for)
    if (s & 1) != 0 && (d.said_state & 1) == 0 {
      d.shown += 1
    }
    d.said_state = s
    if !d.takes_state {
      return
    }
  }
  app_state_taken(s)
}

///|
/// The app's state as `s` says it (1 shown, 2 in front, 4 going on not shown): who is told of it told, a frame asked.
fn app_state_taken(s : Int) -> Unit {
  if s == app_state.val {
    return
  }
  app_state.val = s
  // (no longer in front: the fingers down called off, all of it (touches.mbt); a finger held on the window's tree let
  // go of now)
  if (s & 2) == 0 {
    touches_off()
    view_hold_lost()
    // (and what the old views hold of their own that is no finger: a back gesture, a press of the pointer's)
    view_captures_off(view_moment(), fn(_) { true })
  }
  match app_change.val {
    Some(f) => f((s & 1) != 0, (s & 2) != 0)
    None => ()
  }
  h_request_frame()
}

///|
/// Whether the app's window is shown (not hidden, minimized, covered; Android: the activity resumed).
pub fn app_visible() -> Bool {
  (app_state.val & 1) != 0
}

///|
/// Whether it is also in front (the key window of the active app; Android: with the window's focus).
pub fn app_focused() -> Bool {
  (app_state.val & 2) != 0
}

///|
/// Whether the app goes on: shown, or not shown where its host still runs it for what comes from outside (a
/// desktop's app put away to the notification area or minimized: Windows'). Not an Android app behind another, whose
/// frames stop.
pub fn app_awake() -> Bool {
  (app_state.val & (1 | 4)) != 0
}

///|
/// `f` is told (shown, in front) as soon as that changes, even when no frame comes after (Android tells it as the
/// activity pauses, its GL thread about to stop); one at a time, the last given.
pub fn on_app_change(f : (Bool, Bool) -> Unit) -> Unit {
  app_change.val = Some(f)
}

///|
/// MBUI_BENCH's value for a bench of the app's own: the framework's bench (its list scrolled, its 630 frames timed)
/// does not run, and the app's draws every frame it asks for (Ctx::bench_frames).
pub let bench_app : Int = 3

///|
/// A bench of the app's own (a page's, as still.fail's chat bench scrolls its list) draws every frame while it asks
/// (`on`, asked each frame): only where the host was opened for it (MBUI_BENCH=3, bench_app), with the app as it
/// ships, no other path. Anywhere else (a run of the app, the framework's own bench, a scripted run's stable output,
/// a Tester) it does nothing: no frame is asked for by it.
pub fn Ctx::bench_frames(self : Ctx, on : Bool) -> Unit {
  ignore(self)
  if on && bench.host == bench_app && fake.val is None {
    bench.held = true
  }
}

///|
/// What an input or an event a build took (a tap, the host's answer, a view just made) tells outside of it (a call to
/// a core, a player told to play, bytes kept): told once the frame's builds are over, once by its `key` (the last said
/// under it this frame), whichever of its builds said it. A frame built again (a layout read back) sees no input its
/// first build took and says it no more: kept here, it is neither lost nor told twice. What every build of the frame
/// works out alike (asked while it is not yet: a page's next part, a page left) is Ctx::after_build's, the last
/// build's alone: tell is for what one build alone sees, once. Outside a build (an event's handler), told at once.
pub fn Ctx::tell(self : Ctx, key : String, f : () -> Unit) -> Unit {
  if building.val {
    let id = stable_hash(key).to_int()
    match self.told.search_by(fn(t) { t.0 == id }) {
      Some(k) => self.told[k] = (id, f)
      None => self.told.push((id, f))
    }
  } else {
    f()
  }
}

///|
/// The probe of frames slower than the display's (MBUI_PROBE=1, or always on a device build that sets it): a line on
/// the log for each frame whose work took longer than `probe_slow_ms`, or that came later than that after the one
/// before (the main thread held between them), with where its time went.
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_msgs_ms : Ref[Double] = { val: 0.0 }

///|
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_last_t : Ref[Double] = { val: -1.0 }

///|
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_on : Ref[Int] = { val: -1 }

///|
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_frames : Ref[Int] = { val: 0 }

///|
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_work : Ref[Double] = { val: 0.0 }

///|
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_phase : FixedArray[Double] = FixedArray::make(5, 0.0)

///|
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_since : Ref[Double] = { val: -1.0 }

///|
/// The probe's frames drawn whole, in part and not at all; the share of the window they drew; the GPU's times summed.
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_parts : FixedArray[Int] = FixedArray::make(3, 0)

///|
/// Why the frames drawn whole were (@damage.Damage::why), each its count.
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_why : FixedArray[Int] = FixedArray::make(6, 0)

///|
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_share : Ref[Double] = { val: 0.0 }

///|
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_damage : Ref[Double] = { val: 0.0 }

///|
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_gpu : Ref[Double] = { val: 0.0 }

///|
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_gpu_n : Ref[Int] = { val: 0 }

///|
/// The process's CPU time (every thread's: the core's too, @hostapi.cpu_ms) as the probe's 2 s began.
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_cpu : Ref[Double] = { val: -1.0 }

///|
/// The frames of the looks alone (frame_watch.mbt) as the probe's 2 s began.
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_steps : Ref[Int] = { val: 0 }

///|
/// The frames painted alone (frame_watch.mbt) as the probe's 2 s began.
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_paints : Ref[Int] = { val: 0 }

///|
/// Whether the probe ran the frame before (MBUI_PROBE=1, or the device's performance record kept): as it starts again
/// (the record turned on), what it summed before is dropped.
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_live : Ref[Bool] = { val: false }

///|
/// The frames slower than the display's since the last summary (the record's: one count, not a line each).
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_slow : Ref[Int] = { val: 0 }

///|
/// The second of the summary's span the last frame was in, its frames, the most of any second (fps_peak).
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_sec : Ref[Int] = { val: 0 }

///|
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_sec_n : Ref[Int] = { val: 0 }

///|
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_peak : Ref[Int] = { val: 0 }

///|
/// What the last frame was for (the summary's `last`).
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_last_why : Ref[String] = { val: "" }

///|
/// Whether the frame probe counts (MBUI_PROBE=1, or the device's performance record kept): what else is counted for
/// its summary (perf_also) is counted only then.
pub fn perf_counting() -> Bool {
  probe_live.val
}

///|
/// What the frames since the last summary were for, each its count and work (ms), by why (`built: <built_why>`,
/// `painted: <painted_why>`, `looks`: frame_watch.mbt's, with where it was asked or read); the heaviest one's work and
/// why; the messages posted to the app, by channel, each its count and bytes (messages_take).
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_whys : Map[String, (Int, Double)] = {}

///|
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_worst : Ref[(Double, String)] = { val: (0.0, "") }

///|
// kept across runs: the probe's (MBUI_PROBE, a host's run), read by nothing else
let probe_channels : Map[String, (Int, Int)] = {}

///|
/// What else is said with each summary into the record (perf_also), by name: an app's (its core's calls and topics,
/// its page, a remote screen's frames).
// kept across runs: said once as an app starts
let probe_also : Map[String, (Double) -> String] = {}

///|
/// `f`'s line said with each summary of the frames into the device's performance record (@hostapi.perf_line) while it
/// is kept, as `<name>: <its line>` ("" says nothing): what an app knows of where its time goes that mbui does not (the
/// calls and topics of its core, the page it shows, a remote screen's frames). Asked after the frame is drawn, outside
/// any build, with the summary's span (ms); it says what it counted since it was last asked.
pub fn perf_also(name : String, f : (Double) -> String) -> Unit {
  probe_also[name] = f
}

///|
/// A message posted to the app, counted for the probe while it runs (messages_take): its channel, its bytes.
fn probe_message(channel : String, json : String, bytes : Bytes?) -> Unit {
  if !probe_live.val {
    return
  }
  let n = json.length() +
    (match bytes {
      Some(b) => b.length()
      None => 0
    })
  let (k, b) = probe_channels.get(channel).unwrap_or((0, 0))
  probe_channels[channel] = (k + 1, b + n)
}

///|
/// The `n` heaviest of `m` (by its second number, then its first), as ` <second><unit>/<first> <key>` each, `sep`
/// between.
fn[N : Compare + Show] probe_top(m : Map[String, (Int, N)], n : Int, unit : String, sep? : String = " ") -> String {
  let all = m.to_array()
  all.sort_by(fn(a, b) {
    let c = b.1.1.compare(a.1.1)
    if c != 0 { c } else { b.1.0.compare(a.1.0) }
  })
  let out = StringBuilder::new()
  for i, e in all {
    if i >= n {
      break
    }
    out.write_string((if i == 0 { " " } else { sep }) + "\{e.1.1}\{unit}/\{e.1.0} \{e.0}")
  }
  out.to_string()
}

///|
let probe_slow_ms : Double = 24.0

///|
/// How often the probe sums up: on the log (MBUI_PROBE=1), into the performance record.
let probe_log_ms : Double = 2000.0

///|
let probe_record_ms : Double = 5000.0

///|
/// The probe (above): on the log every 2 s with MBUI_PROBE=1, a line for each slow frame too; into the device's
/// performance record (@hostapi.perf_line, the person's 性能记录) every 5 s while it is kept, its slow frames counted
/// only. Neither: nothing summed.
fn slow_probe(c : Ctx, t : Double, work : Double, present : Double) -> Unit {
  if probe_on.val < 0 {
    probe_on.val = if @hostapi.env("MBUI_PROBE") == "1" { 1 } else { 0 }
    presented.tell(@hostapi.env("MBUI_PROBE_DAMAGE") == "1")
  }
  let recording = @hostapi.perf_recording()
  if probe_on.val == 0 && !recording {
    probe_live.val = false
    return
  }
  if !probe_live.val {
    probe_live.val = true
    probe_reset(-1.0)
    probe_last_t.val = -1.0
  }
  let gap = if probe_last_t.val < 0.0 { 0.0 } else { t - probe_last_t.val }
  probe_last_t.val = t
  // (what it was for: the record's attribution, its heaviest; said of the last frame with each summary)
  let why = if built_why.val != "" {
    "built: " + built_why.val
  } else if painted_why.val != "" {
    "painted: " + painted_why.val
  } else {
    looks_why()
  }
  // (a summary is of its span's frames, said as the first frame after it comes: a span with none drawn after it, a
  // burst of frames at its start, is said whole, its seconds' busiest beside its average, not with the frames that
  // come after a pause)
  let every = if probe_on.val == 1 { probe_log_ms } else { probe_record_ms }
  if probe_since.val >= 0.0 && t - probe_since.val >= every && probe_frames.val > 0 {
    probe_said(c, t, recording)
    probe_reset(t)
  }
  // (how many frames a second, said every 2 s it draws: 5 s into the record alone)
  probe_frames.val = probe_frames.val + 1
  probe_work.val = probe_work.val + work + present
  probe_phase[0] = probe_phase[0] + probe_msgs_ms.val
  probe_phase[1] = probe_phase[1] + c.t_build - probe_msgs_ms.val
  probe_phase[2] = probe_phase[2] + c.t_layout
  probe_phase[3] = probe_phase[3] + c.t_paint
  probe_phase[4] = probe_phase[4] + present
  probe_last_why.val = why
  if recording {
    let (k, ms) = probe_whys.get(why).unwrap_or((0, 0.0))
    probe_whys[why] = (k + 1, ms + work + present)
    if probe_worst.val.1 == "" || work + present > probe_worst.val.0 {
      probe_worst.val = (work + present, why)
    }
  }
  // (how much of the window each drew again, docs/partial-redraw.md; the GPU's time of the last done)
  let share = presented_share.val
  probe_parts[if share >= 1.0 { 0 } else if share > 0.0 { 1 } else { 2 }] += 1
  probe_why[presented.why()] += 1
  probe_share.val = probe_share.val + share
  probe_damage.val = probe_damage.val + presented_ms.val
  let gms = h_gpu_ms()
  if gms >= 0.0 {
    probe_gpu.val = probe_gpu.val + gms
    probe_gpu_n.val = probe_gpu_n.val + 1
  }
  if probe_since.val < 0.0 {
    probe_since.val = t
    probe_cpu.val = h_cpu_ms()
    probe_steps.val = looks_frames.val
    probe_paints.val = paints_alone.val
  }
  // (the frames of each second of the span, its busiest: a burst not averaged away)
  let sec = ((t - probe_since.val) / 1000.0).to_int()
  if sec != probe_sec.val {
    probe_sec.val = sec
    probe_sec_n.val = 0
  }
  probe_sec_n.val = probe_sec_n.val + 1
  if probe_sec_n.val > probe_peak.val {
    probe_peak.val = probe_sec_n.val
  }
  // (slow: its own work longer than the display's frame allows, not a pause before it with nothing asked of it)
  if work + present > probe_slow_ms {
    probe_slow.val = probe_slow.val + 1
  }
  if probe_on.val == 1 && (work > probe_slow_ms || gap > 3.0 * probe_slow_ms) {
    h_log(
      "PROBE slow frame: work=\{work.round()}ms (messages=\{probe_msgs_ms.val.round()} build=\{c.t_build.round()} " +
      "layout=\{c.t_layout.round()} paint=\{c.t_paint.round()} present=\{present.round()}) since_last=\{gap.round()}ms " +
      "handed=\{messages_handed.val} nodes=\{c.count}",
    )
  }
}

///|
/// The probe's summary of the frames since `probe_since`, as the frame at `t` comes after its span: on the log
/// (MBUI_PROBE=1), into the record (`recording`). Its CPU and fps are of the span to `t`, whatever was drawn in it;
/// `fps_peak` the most frames of one second of it; `last` what its last frame was for.
fn probe_said(c : Ctx, t : Double, recording : Bool) -> Unit {
  let span = t - probe_since.val
  // (the whole process's share of one CPU since, whatever drew: 100% one core busy throughout)
  let cpu_now = h_cpu_ms()
  let cpu = if cpu_now >= 0.0 && probe_cpu.val >= 0.0 { ((cpu_now - probe_cpu.val) * 100.0 / span).round() } else { -1.0 }
  probe_cpu.val = cpu_now
  let stepped = looks_frames.val - probe_steps.val
  probe_steps.val = looks_frames.val
  let painted = paints_alone.val - probe_paints.val
  probe_paints.val = paints_alone.val
  let n = probe_frames.val.to_double()
  let said = "fps=\{(n * 1000.0 / span).round()} fps_peak=\{probe_peak.val} span=\{(span / 100.0).round() / 10.0}s cpu=\{cpu}% looks_alone=\{stepped} painted_alone=\{painted} (last: \{probe_last_why.val}) main_busy=\{(probe_work.val * 100.0 / span).round()}% " +
    "work_avg=\{(probe_work.val / n * 10.0).round() / 10.0}ms " +
    "avg msgs/build/layout/paint/present=\{probe_phase.map(fn(x) { (x / n * 10.0).round() / 10.0 })} nodes=\{c.count} " +
    "drawn whole/part/none=\{probe_parts[0]}/\{probe_parts[1]}/\{probe_parts[2]} whole_why=\{probe_why} damage_avg=\{(probe_damage.val / n * 100.0).round() / 100.0}ms share_avg=\{(probe_share.val * 100.0 / n).round()}% " +
    "gpu_avg=\{if probe_gpu_n.val > 0 { (probe_gpu.val / probe_gpu_n.val.to_double() * 100.0).round() / 100.0 } else { -1.0 }}ms slow=\{probe_slow.val}"
  if probe_on.val == 1 {
    h_log("PROBE " + said)
  }
  if recording {
    @hostapi.perf_line("frames: " + said)
    let r = (fn(x : Double) { (x * 10.0).round() / 10.0 })
    let whys = probe_whys.map(fn(_, v) { (v.0, r(v.1)) })
    @hostapi.perf_line("frames why (the 5 heaviest, ms/frames):" + probe_top(whys, 5, "ms", sep=" | "))
    if probe_worst.val.1 != "" {
      @hostapi.perf_line("frames heaviest: \{r(probe_worst.val.0)}ms \{probe_worst.val.1}")
    }
    if probe_channels.length() > 0 {
      @hostapi.perf_line("messages (bytes/count, by channel):" + probe_top(probe_channels, 6, "B", sep=" | "))
    }
    for name, f in probe_also {
      let line = @signals.untracked(fn() { f(span) })
      if line != "" {
        @hostapi.perf_line(name + ": " + line)
      }
    }
  }
}

///|
/// What a frame of the looks alone was for: the cycles it drew (Ctx::cycle_look, where each was said), else the
/// motions' looks.
fn looks_why() -> String {
  if cycle_frame.is_empty() {
    return "looks"
  }
  let at : Array[String] = []
  cycle_frame.each(fn(_, cy) {
    let l = cy.loc.to_string()
    if !at.contains(l) {
      at.push(l)
    }
  })
  at.sort()
  "looks: cycles at " + at.join(", ")
}

///|
/// The probe's sums begun again from `t` (-1: from its next frame, its CPU's time asked then).
fn probe_reset(t : Double) -> Unit {
  for i in 0..<3 {
    probe_parts[i] = 0
  }
  for i in 0..<6 {
    probe_why[i] = 0
  }
  probe_share.val = 0.0
  probe_damage.val = 0.0
  probe_gpu.val = 0.0
  probe_gpu_n.val = 0
  for i in 0..<5 {
    probe_phase[i] = 0.0
  }
  probe_frames.val = 0
  probe_work.val = 0.0
  probe_slow.val = 0
  probe_sec.val = 0
  probe_sec_n.val = 0
  probe_peak.val = 0
  probe_whys.clear()
  probe_worst.val = (0.0, "")
  probe_channels.clear()
  probe_since.val = t
}
