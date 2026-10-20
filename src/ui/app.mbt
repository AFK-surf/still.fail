// The window's loop: the host calls these functions for frames and input.

///|
/// The window's context: one for the window's life; a Tester makes a fresh one each (nothing a test left in it is
/// seen by the next).
let the_ctx : Ref[Ctx] = Ref(Ctx::new())

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
/// Opens the window and runs `view` for every frame until it closes.
pub fn run(title : String, view : (Ctx) -> Unit) -> Unit {
  g_view.val = view
  bench.host = @host.bench_mode()
  // (the app's own bench, bench_app: the framework's does not run beside it)
  bench.mode = if bench.host == bench_app { 0 } else { bench.host }
  drive_init()
  @host.set_back(fn(k, x, p, e) { on_back(k, x, p, e) })
  @host.set_app_state(fn(s) { on_app_state(s) })
  outside_told.val = @host.set_outside(fn(k, id, st) { on_outside(k, id, st) })
  @host.run(
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
  in_frame.val = true
  // (the system's settings it is drawn by, kept with the run's input: envrec.mbt)
  env_at_frame()
  let t0 = frame_body(c, w, h, scale, t)
  in_frame.val = false
  // inputs came before this frame: one more, for what they changed late in it (inputrec.mbt `took_input`)
  c.took_input = fed
  if fed {
    c.wants_frame = true
  }
  let t3 = h_now()
  h_present(c.inst, c.ninst)
  log_drawn(w, h, scale, t)
  c.trim_images()
  let t4 = h_now()
  c.t_present = t4 - t3
  if bench.mode > 0 {
    bench_step(c, t3 - t0, t4 - t3)
  }
  drive_frame(c)
  // a motion said, not at its end; a cycle shown (motion_data.mbt)
  c.motion_left = c.motion_owed()
  // (a layout read back that moved: what was placed from it, placed again)
  if c.read_back_moved {
    c.wants_frame = true
  }
  let held = bench.held
  bench.held = false
  if c.wants_frame || bench.mode > 0 || held {
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
    @host.frame_awaiting(rt.awaiting(), what)
  }
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
  // the theme set for this width (a phone's when narrower than its bound: Ctx::set_theme)
  c.pick_theme()
  if scale != c.scale {
    // images are as large as their pixels at this scale
    c.epoch = c.epoch + 1
  }
  c.scale = scale
  c.now = t
  c.dt = if c.last_now < 0.0 { 16.67 } else { dclamp(t - c.last_now, 0.0, 100.0) }
  c.last_now = t
  c.frame_no = c.frame_no + 1
  if !layout_reuse.val {
    c.epoch = c.epoch + 1
  }
  c.wants_frame = false
  c.wake_at = -1.0
  c.wake_waited = -1.0
  c.frame_by = None
  c.wake_by = None
  c.cycling = false
  c.cycles.clear()
  c.periodic.clear()
  c.nav_rest = -1.0
  c.read_back_moved = false
  check_atlas()
  if bench.mode > 0 && c.bench_list != 0 && bench.frames >= 30 {
    c.scroll_list(c.bench_list, bench.speed)
  }
  let t0 = h_now()
  // what was posted from outside since the last frame (a core's answers), all of it, handed to its handlers in the
  // order it came, before anything reads it (messages.mbt)
  take_messages()
  // the runtime's fibers run up to this frame's time (fx.mbt): the view reads what they left
  fx_frame_start(c)
  // what is said to move, handed this frame's time, before the view reads where it is (motion_data.mbt)
  c.movers_sample()
  desk_frame_start()
  // the keys and presses since the last frame that move the focus, press what has it, dismiss a layer (focus.mbt,
  // overlay.mbt), before the view builds
  c.focus_frame_start()
  // how each native view stands, read before the view builds what it shows of it (a player's time, its first frame)
  views_frame_start()
  // built and laid out; built again, at once, while what the view read in it changed as it was built or laid out
  // (Ctx::read_changed: the focus given, a layer dismissed, a list scrolled, words laid out elsewhere): what is drawn
  // is what the view builds from the state as it is, never a frame of it as it was (frame_passes_most at most)
  let mut root = 0
  let mut t1 = t0
  let mut pass = 0
  c.layers_opened.clear()
  while true {
    pass = pass + 1
    c.read_back_moved = false
    building.val = true
    root = frame_build(c, w, h)
    t1 = h_now()
    // lists build their rows while laid out, and those see clicks too
    c.layout(root, 0.0, 0.0, w, h) |> ignore
    // what covers an item, over it as laid out now (cover.mbt)
    c.covers_after_layout()
    // the corners said `Inner`, from where they lie in their parents as laid out, the covers moved (corners.mbt)
    c.corners_after_layout()
    // how things are drawn this frame, from where they are laid out (draw.mbt: the motion package's looks)
    c.drawing_after_layout()
    // what words marked as selectable hold, as laid out (words.mbt)
    c.words_after_layout()
    // what the view read of the layout as it built (a box's laid rect, a list's place), looked at again (readback.mbt)
    c.reads_after_layout()
    // how far what scrolls sideways can (sideways.mbt)
    c.sideways_after_layout()
    // the focus into the layers that opened, back from those that went (overlay.mbt)
    c.layers_focus()
    // (what this pass took of the inputs is taken: one built again sees none of them, the clicks, keys, menus and
    // actions since the last frame)
    c.clicked.clear()
    c.tapped = None
    desk.keys.clear()
    desk.menus.clear()
    c.actions.clear()
    building.val = false
    if !c.read_back_moved || pass >= frame_passes_most {
      break
    }
  }
  // what the last build said to tell outside, told now, once (Ctx::after_build)
  let tells = c.tells.copy()
  c.tells.clear()
  for t in tells {
    (t.1)()
  }
  if scroll_logging() {
    c.log_scroll()
  }
  let t2 = h_now()
  c.ninst = 0
  c.next_hit_ids.clear()
  c.next_hit_rects.clear()
  c.next_hit_clips.clear()
  c.next_scroll_ids.clear()
  c.next_scroll_rects.clear()
  c.glass_frame()
  c.paint(root, 1.0)
  c.paint_overlays()
  c.sync_views()
  // back goes where the stack drawn now says (Ctx::nav, while building)
  c.back = c.back_next
  c.back_node = c.back_node_next
  c.back_edge = c.back_edge_next
  let takes = match c.back {
    Some(_) => true
    None => false
  }
  if takes != c.back_told {
    c.back_told = takes
    h_back_enabled(takes)
  }
  let hi = c.hit_ids
  c.hit_ids = c.next_hit_ids
  c.next_hit_ids = hi
  let hr = c.hit_rects
  c.hit_rects = c.next_hit_rects
  c.next_hit_rects = hr
  let hc = c.hit_clips
  c.hit_clips = c.next_hit_clips
  c.next_hit_clips = hc
  // (what said its presses are another's, under a Tester: that one takes them there)
  c.check_press_owners()
  let si = c.scroll_ids
  c.scroll_ids = c.next_scroll_ids
  c.next_scroll_ids = si
  let sr = c.scroll_rects
  c.scroll_rects = c.next_scroll_rects
  c.next_scroll_rects = sr
  c.layers_frame_end()
  c.focus_frame_end()
  c.desk_frame_end()
  c.sync_ime()
  fx_frame_end(c)
  match frame_hook.val {
    Some(f) => f()
    None => ()
  }
  let t3 = h_now()
  c.t_build = t1 - t0
  c.t_layout = t2 - t1
  c.t_paint = t3 - t2
  t0
}

///|
/// `f`, what the view tells outside of what it builds (a call to its core: the chat shown and its end seen), done once
/// the frame's builds are over, as the last of them says it: a frame is built again while what the view read changes
/// (frame_body), and what an earlier build said, from what it read then, is let go. By `key` in the scope it is said
/// in: said twice in a build, the later. Said outside a frame's build, at once.
pub fn Ctx::after_build(self : Ctx, key : String, f : () -> Unit) -> Unit {
  if !building.val {
    f()
    return
  }
  let id = self.id("\u{2}after-build/" + key)
  match self.tells.search_by(fn(t) { t.0 == id }) {
    Some(k) => self.tells[k] = (id, f)
    None => self.tells.push((id, f))
  }
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
  c.inners.clear()
  // (what an earlier build of this frame said to tell outside is let go: this one says it again, or not)
  c.tells.clear()
  drawing_begin()
  desk_build_start()
  c.layers.clear()
  c.focusables.clear()
  c.sems.clear()
  c.sem_hide = 0
  c.sem_hidden.clear()
  c.layer_cur = 0
  c.group_cur = 0
  c.count = 0
  c.cur = -1
  c.press_owners.clear()
  c.back_next = None
  c.back_node_next = -1
  let root = c.alloc(kind_box)
  c.nodes[root].w = Px(w)
  c.nodes[root].h = Px(h)
  c.with_parent(root, fn() { (g_view.val)(c) })
  // what lies over the page over everything else (overlay.mbt)
  c.raise_layers()
  root
}

///|
fn bench_step(c : Ctx, cpu : Double, present : Double) -> Unit {
  bench.frames = bench.frames + 1
  if bench.frames == 30 {
    bench.start = c.now
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
    let wall = c.now - bench.start
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
      "nodes=\{c.count} instances=\{c.ninst} rss_mb=\{@host.mem_bytes() / 1048576.0}",
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
      @host.exit(0)
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
/// An input came between two frames (the host's, a test's, an action asked by the accessibility): the next frame and
/// the one after it are the framework's to draw (inputrec.mbt `inputs_since`).
fn input_came() -> Unit {
  inputs_since.val = true
  h_request_frame()
}

///|
fn on_pointer(kind : Int, x : Double, y : Double, button : Int) -> Unit {
  took_input("pointer", h_event_time(), [kind.to_double(), x, y, button.to_double()])
  let c = g()
  // a second finger (4 down, 5 moved, 6 up: hosts with touch screens), for a pinch (native.mbt `second_pointer`)
  if kind >= 4 && kind <= 6 {
    on_second(kind, x, y)
    return
  }
  // the pointer gone out of the window (7); a secondary button (a right click: its menu's, nothing pressed)
  if kind == 7 {
    c.pointer_left()
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
  // the event's own time: events handled together happened apart
  let t = h_event_time()
  c.pointer_t = t
  if scroll_logging() {
    h_log("TOUCH \{kind} \{t} \{x} \{y} \{h_now()}")
  }
  if kind == 0 {
    let target = hit_in(c.hit_ids, c.hit_rects, x, y)
    // the app's own top row: the window is the host's to move from here (it takes the rest of the press)
    if desk_drags(target) {
      h_window_drag()
      return
    }
    // words picked with the pointer (desktop.mbt), not in a field
    if !c.editors.contains(target) {
      select_press(x, y)
    }
    // what lies over the page sees it (overlay.mbt); the focus goes as a press moves it (focus.mbt)
    c.press_down = Some((x, y))
    c.focus_on_press(target)
    c.down = true
    c.active = target
    c.press_x = x
    c.press_y = y
    c.press_at = t
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
    match c.lists.get(c.drag_scroll) {
      // a list moving on its own (flung, springing back from an end) is
      // caught: the finger drags it from there, and presses nothing in it
      Some(st) if st.moving() => {
        c.claimed = true
        for other in c.press_chain {
          if other != c.drag_scroll {
            drag_cancel(other)
          }
        }
        st.catch_up()
        st.held = true
        c.dragging = true
        c.active = 0
        c.edge = 0
        h_request_frame()
        return
      }
      Some(st) => st.stop()
      None => ()
    }
    match c.editors.get(target) {
      Some(st) => {
        c.focus = target
        c.editor_drag = true
        st.blink0 = t
        match st.tl {
          Some(tl) => {
            if st.marked.length() > 0 {
              st.text_input(2, "", 0, 0, t)
            }
            let off = tl.offset_at(x - st.ox, y - st.oy)
            st.caret = imin(off, st.text.length())
            st.anchor = st.caret
          }
          None => ()
        }
      }
      None => if target == 0 { c.focus = 0 }
    }
  } else if kind == 1 {
    c.hover = hit_in(c.hit_ids, c.hit_rects, x, y)
    if c.down {
      track_x.add(t, x)
      track_y.add(t, y)
      if c.edge > 0 && c.edge_move(x, y, t) {
        ()
      } else if select_move(x, y) {
        // picking words: the press is no tap
        c.active = 0
      } else if c.editor_drag {
        match c.editors.get(c.active) {
          Some(st) =>
            match st.tl {
              Some(tl) =>
                st.caret = imin(tl.offset_at(x - st.ox, y - st.oy), st.text.length())
              None => ()
            }
          None => ()
        }
      } else if !claim_move(c, x, y) {
        // no one's yet: nothing moves
        ()
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
            // from where the slop ends, as Compose starts a drag: nothing
            // jumps, and what moved past the slop is not lost
            let past = if moved > 0.0 { moved - slop } else { moved + slop }
            if pager {
              c.pager_drag(c.drag_scroll, past) |> ignore
            } else {
              c.list_drag(c.drag_scroll, -past)
            }
          }
        } else if pager {
          c.pager_drag(c.drag_scroll, x - c.last_x) |> ignore
        } else {
          c.list_drag(c.drag_scroll, -(y - c.last_y))
        }
      }
      c.last_y = y
      c.last_x = x
      c.last_t = t
    }
  } else if kind == 2 {
    if c.down {
      track_x.add(t, x)
      track_y.add(t, y)
    }
    if c.edge == 2 {
      c.back_gesture(2, x, t)
    }
    c.edge = 0
    let target = hit_in(c.hit_ids, c.hit_rects, x, y)
    if c.active != 0 && target == c.active && !c.dragging {
      c.clicked.push(c.active)
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
        false,
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
    c.down = false
    c.dragging = false
    c.active = 0
    c.editor_drag = false
    picked.dragging = false
    second_ptr[2] = 0.0
  } else {
    if c.edge == 2 {
      c.back_gesture(3, x, t)
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
    c.down = false
    c.dragging = false
    c.active = 0
    second_ptr[2] = 0.0
  }
  h_request_frame()
}

///|
/// A finger dragging list `id` by `d` (positive down the list).
fn Ctx::list_drag(self : Ctx, id : Int, d : Double) -> Unit {
  match self.lists.get(id) {
    Some(st) => {
      st.held = true
      self.feed(st, d, 1)
    }
    None => ()
  }
}

///|
/// Whether a press at (x, y) is on the left edge of the stack that takes
/// back (Ctx::nav), where a swipe back starts.
fn Ctx::on_edge(self : Ctx, x : Double, y : Double) -> Bool {
  match self.back {
    Some(_) if self.back_node >= 0 && self.back_node < self.count => {
      let n = self.nodes[self.back_node]
      x >= n.x && x < n.x + self.back_edge && y >= n.y && y < n.y + n.fh
    }
    _ => false
  }
}

///|
/// The back gesture's step to the stack that takes back: x in its own
/// terms (from its left), its width.
fn Ctx::back_gesture(self : Ctx, kind : Int, x : Double, t : Double) -> Unit {
  match self.back {
    Some(f) => {
      let (left, w) = if self.back_node >= 0 && self.back_node < self.count {
        let n = self.nodes[self.back_node]
        (n.x, n.fw)
      } else {
        (0.0, self.width)
      }
      f(kind, x - left, w, t)
    }
    None => ()
  }
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
      self.back_gesture(0, self.press_x, self.last_t)
    } else if dy.abs() > 6.0 || dx < -6.0 {
      self.edge = 0
    }
  }
  if self.edge == 2 {
    self.back_gesture(1, x, t)
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
/// with no gesture.
fn on_back(kind : Int, x : Double, _progress : Double, edge : Int) -> Unit {
  took_input("back", h_now(), [kind.to_double(), x, _progress, edge.to_double()])
  let c = g()
  let t = h_now()
  // from the right edge, the finger's way is mirrored
  let from_left = if edge == 1 { c.width - x } else { x }
  match kind {
    0 => c.back_gesture(0, from_left, t)
    1 => c.back_gesture(1, from_left, t)
    2 => c.back_gesture(4, 0.0, t)
    _ => c.back_gesture(3, 0.0, t)
  }
  h_request_frame()
}

///|
fn on_wheel(x : Double, y : Double, dx : Double, dy : Double, phase : Int) -> Unit {
  took_input("wheel", h_event_time(), [x, y, dx, dy, phase.to_double()])
  let c = g()
  let mut target = hit_in(c.scroll_ids, c.scroll_rects, x, y)
  // over what scrolls sideways: its sideways part moves it, the rest goes to the list it lies in
  if sideways.contains(target) {
    if sideways_wheel(target, dx, dy) {
      h_request_frame()
      return
    }
    target = outer_scroll(c, x, y)
  }
  if captures.contains(target) {
    // a box that takes the pointer keeps the wheel (native.mbt `wheel`)
    wheels[target] = wheels.get(target).unwrap_or(0.0) + dy
    h_request_frame()
    return
  }
  if target != 0 {
    match c.lists.get(target) {
      Some(st) => st.stop()
      None => ()
    }
    // a wheel's notch (phase 4): eased over a few frames, as a browser does; a trackpad's (and its momentum's)
    // follows the fingers as it comes
    if phase == 4 {
      c.ease_list(target, dy)
    } else {
      c.scroll_list(target, dy)
    }
    h_request_frame()
  }
}

///|
fn on_key(code : Int, mods : Int) -> Unit {
  took_input("key", h_now(), [code.to_double(), mods.to_double()])
  let c = g()
  // every key the app may read (Ctx::key_pressed), and whether the focused field takes it (the editor's own keys)
  desk_key(code, mods, c.editors.contains(c.focus) && code < key_escape)
  // ⌘C with no field focused: the words picked with the pointer
  if code == key_copy && !c.editors.contains(c.focus) && selected_words() != "" {
    h_clipboard_set(selected_words())
    return
  }
  if code >= key_escape {
    h_request_frame()
    return
  }
  match c.editors.get(c.focus) {
    Some(st) => {
      st.key(code, mods, h_now())
      h_request_frame()
    }
    None => {
      let target = hit_in(c.scroll_ids, c.scroll_rects, c.px, c.py)
      // a key the focused widget takes (focus.mbt) scrolls nothing under the pointer
      if target != 0 &&
        !c.focus_takes(code) &&
        (c.list_key(target, code) || c.pager_key(target, code)) {
        h_request_frame()
      }
    }
  }
}

///|
fn on_text(kind : Int, s : String, a : Int, b : Int) -> Unit {
  took_input("text", h_now(), [kind.to_double(), a.to_double(), b.to_double()], text=s)
  let c = g()
  match c.editors.get(c.focus) {
    Some(st) => {
      st.text_input(kind, s, a, b, h_now())
      h_request_frame()
    }
    None => ()
  }
}

///|
/// Moves focus to an editor (used by tests and the bench).
pub fn Ctx::focus_editor(self : Ctx, key : String) -> Unit {
  self.focus = self.id(key)
}

///|
/// Whether the app is shown (1) and in front (2), as the host last said (shown and in front until it says).
let app_state : Ref[Int] = Ref::new(3)

///|
/// Who is told when that changes (the app's one: `on_app_change`).
let app_change : Ref[((Bool, Bool) -> Unit)?] = Ref::new(None)

///|
fn on_app_state(s : Int) -> Unit {
  took_input("app", h_now(), [s.to_double()])
  // a scripted run stands for someone looking at the app: what the host says meanwhile (a locked screen's window
  // is covered, a task's app not active) is let be
  if driver.val is Some(_) {
    h_log("DRIVE the host says the app is \{s} (1 shown, 2 in front): kept in front for the run")
    return
  }
  if s == app_state.val {
    return
  }
  app_state.val = s
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
