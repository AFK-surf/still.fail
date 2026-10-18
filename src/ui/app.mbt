// The window's loop: the host calls these functions for frames and input.

///|
let g : Ctx = Ctx::new()

///|
let g_view : Ref[(Ctx) -> Unit] = { val: fn(_c) { () } }

///|
let bench : Bench = {
  mode: 0,
  frames: 0,
  cpu: [],
  present: [],
  start: 0.0,
  speed: 0.0,
  phases: [0.0, 0.0, 0.0],
}

///|
struct Bench {
  mut mode : Int
  mut frames : Int
  cpu : Array[Double]
  present : Array[Double]
  mut start : Double
  mut speed : Double
  // build, layout and paint time summed over the measured frames
  phases : Array[Double]
}

///|
/// Opens the window and runs `view` for every frame until it closes.
pub fn run(title : String, view : (Ctx) -> Unit) -> Unit {
  g_view.val = view
  bench.mode = @host.bench_mode()
  @host.set_back(fn(k, x, p, e) { on_back(k, x, p, e) })
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
  let c = g
  c.width = w
  c.height = h
  c.scale = scale
  c.now = t
  c.dt = if c.last_now < 0.0 { 16.67 } else { dclamp(t - c.last_now, 0.0, 100.0) }
  c.last_now = t
  c.frame_no = c.frame_no + 1
  c.wants_frame = false
  c.wake_at = -1.0
  check_atlas()
  if bench.mode > 0 && c.bench_list != 0 && bench.frames >= 30 {
    c.scroll_list(c.bench_list, bench.speed)
  }
  let t0 = h_now()
  c.count = 0
  c.cur = -1
  c.back_next = None
  c.back_node_next = -1
  let root = c.alloc(kind_box)
  c.nodes[root].w = Px(w)
  c.nodes[root].h = Px(h)
  c.with_parent(root, fn() { (g_view.val)(c) })
  let t1 = h_now()
  // lists build their rows while laid out, and those see clicks too
  c.layout(root, 0.0, 0.0, w, h) |> ignore
  c.clicked.clear()
  let t2 = h_now()
  c.ninst = 0
  c.next_hit_ids.clear()
  c.next_hit_rects.clear()
  c.next_scroll_ids.clear()
  c.next_scroll_rects.clear()
  c.paint(root, 1.0)
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
  let si = c.scroll_ids
  c.scroll_ids = c.next_scroll_ids
  c.next_scroll_ids = si
  let sr = c.scroll_rects
  c.scroll_rects = c.next_scroll_rects
  c.next_scroll_rects = sr
  c.sync_ime()
  let t3 = h_now()
  h_present(c.inst, c.ninst)
  c.trim_images()
  let t4 = h_now()
  c.t_build = t1 - t0
  c.t_layout = t2 - t1
  c.t_paint = t3 - t2
  c.t_present = t4 - t3
  if bench.mode > 0 {
    bench_step(c, t3 - t0, t4 - t3)
  }
  if c.wants_frame || bench.mode > 0 {
    h_request_frame()
  } else if c.wake_at > 0.0 {
    h_wake_after(dmax(c.wake_at - t, 1.0))
  }
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
    if bench.mode == 1 {
      @host.exit(0)
    } else {
      bench.mode = 0
    }
  }
}

///|
fn on_pointer(kind : Int, x : Double, y : Double, _button : Int) -> Unit {
  let c = g
  c.px = x
  c.py = y
  let t = h_now()
  if kind == 0 {
    c.down = true
    let target = hit_in(c.hit_ids, c.hit_rects, x, y)
    c.active = target
    c.press_x = x
    c.press_y = y
    c.last_y = y
    c.last_x = x
    c.vel_x = 0.0
    c.last_t = t
    c.vel = 0.0
    c.dragging = false
    c.drag_scroll = hit_in(c.scroll_ids, c.scroll_rects, x, y)
    match c.lists.get(c.drag_scroll) {
      Some(st) => st.vel = 0.0
      None => ()
    }
    c.editor_drag = false
    c.edge = if c.on_edge(x, y) { 1 } else { 0 }
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
      if c.edge > 0 && c.edge_move(x, y, t) {
        ()
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
      } else if c.drag_scroll != 0 {
        // a pager follows the finger sideways, a list up and down
        let pager = pagers.contains(c.drag_scroll)
        let moved = if pager { x - c.press_x } else { y - c.press_y }
        if !c.dragging && moved.abs() > 6.0 {
          c.dragging = true
          c.active = 0
        }
        if c.dragging {
          let dt = t - c.last_t
          if pager {
            let dx = x - c.last_x
            c.pager_drag(c.drag_scroll, dx) |> ignore
            if dt > 0.0 {
              c.vel_x = c.vel_x * 0.4 + dx / dt * 0.6
            }
          } else {
            let dy = y - c.last_y
            c.scroll_list(c.drag_scroll, -dy)
            if dt > 0.0 {
              let v = -dy / dt
              c.vel = c.vel * 0.4 + v * 0.6
            }
          }
        }
      }
      c.last_y = y
      c.last_x = x
      c.last_t = t
    }
  } else if kind == 2 {
    if c.edge == 2 {
      c.back_gesture(2, x, t)
    }
    c.edge = 0
    let target = hit_in(c.hit_ids, c.hit_rects, x, y)
    if c.active != 0 && target == c.active && !c.dragging {
      c.clicked.push(c.active)
    }
    if c.dragging {
      match c.lists.get(c.drag_scroll) {
        Some(st) => if t - c.last_t < 80.0 { st.vel = dclamp(c.vel, -8.0, 8.0) }
        None => ()
      }
      if pagers.contains(c.drag_scroll) {
        c.pager_release(
          c.drag_scroll,
          if t - c.last_t < 80.0 { c.vel_x } else { 0.0 },
        )
      }
    }
    c.down = false
    c.dragging = false
    c.active = 0
    c.editor_drag = false
  } else {
    if c.edge == 2 {
      c.back_gesture(3, x, t)
    }
    c.edge = 0
    c.down = false
    c.dragging = false
    c.active = 0
  }
  h_request_frame()
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
  let c = g
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
fn on_wheel(x : Double, y : Double, _dx : Double, dy : Double, _phase : Int) -> Unit {
  let c = g
  let target = hit_in(c.scroll_ids, c.scroll_rects, x, y)
  if target != 0 {
    match c.lists.get(target) {
      Some(st) => st.vel = 0.0
      None => ()
    }
    c.scroll_list(target, dy)
    h_request_frame()
  }
}

///|
fn on_key(code : Int, mods : Int) -> Unit {
  let c = g
  match c.editors.get(c.focus) {
    Some(st) => {
      st.key(code, mods, h_now())
      h_request_frame()
    }
    None => {
      let target = hit_in(c.scroll_ids, c.scroll_rects, c.px, c.py)
      if target != 0 && (c.list_key(target, code) || c.pager_key(target, code)) {
        h_request_frame()
      }
    }
  }
}

///|
fn on_text(kind : Int, s : String, a : Int, b : Int) -> Unit {
  let c = g
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
