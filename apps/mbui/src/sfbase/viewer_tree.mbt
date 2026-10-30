// The image viewer as nodes of the window's tree (the narrow shell's: sfapp's narrow_shell.mbt; docs/retained.md), made
// as it opens and let go as it has gone, over the pages:
//
//   - its layer: the whole window, taking every finger that comes to it (what is under it, the pages, takes none);
//   - its ground: the canvas's colour, as far in as the viewer has come (its flight, its fade), sampled as each frame
//     draws it;
//   - its canvas: what a finger does on the picture is this node's, each event at its own moment (one finger drags,
//     two pinch, a tap shows or hides the bars, two zoom, a hold opens the picture's menu, marking draws), the zoom
//     told the stage's size and the picture's as either changes, at that moment;
//   - in it, what draws the picture (an old view taking no finger: the picture where its zoom has it as the frame
//     draws it, its flight, the pictures beside it), and over it the bars (an old view taking a finger only where they
//     have something to press).
//
// It sets out as the node is made (that moment its cause's: the thumbnail tapped), and is done at its way's declared
// end (a moment on the node's timeline): landed, the thumbnail shows again; gone, it is let go.
//
// Still the old view's here (the way there): what the bars do (their own presses, Esc and back), the wheel (the tree
// has none of its own yet: the drawing view's stage takes it), the strip of pictures beside it (an old view's motion,
// read at the frame's moment), the lift over the keyboard while marking.

///|
/// How many times what draws the picture and the bars over it have been built, each (what a change built again).
pub(all) struct ViewerBuilt {
  mut drawing : Int
  mut bars : Int
}

///|
// kept across runs: counts, only ever read as how many more
pub let viewer_built : ViewerBuilt = { drawing: 0, bars: 0 }

///|
/// The viewer the window's tree draws: the one open, else the one going, when what it shows is an image it shows (not
/// one too big to show).
fn tree_viewer() -> Viewer? {
  let v = match viewer.get() {
    Some(v) => Some(v)
    None => pv_leaving.get()
  }
  match v {
    Some(v) if v.shown_kind() == Some(KImage) && v.file.size <= big_file => Some(v)
    _ => None
  }
}

///|
/// The image viewer in node `v` of the window's tree (laid out over the pages: narrow_shell), made as one opens and let
/// go as it has gone; another opened (a step to the one beside it) another node.
/// `stage`: how big the room it is laid out in is (the window's, less what the shell keeps clear of the system's bars),
/// what its picture is fitted to, as it changes.
pub fn viewer_node(v : @view.View, src : Source, stage : () -> (Double, Double)) -> Unit {
  v.pick(
    fn() {
      match tree_viewer() {
        Some(vw) => vw.serial
        None => 0
      }
    },
    fn(n, serial) {
      match tree_viewer() {
        // (over the pages, the whole of the room it is given: not one more of what is laid out after them)
        Some(vw) if serial > 0 && vw.serial == serial => {
          n.over(Is(true)) |> ignore
          n.box(fn(layer) { image_layer(layer, src, vw, stage) }) |> ignore
        }
        _ => ()
      }
    },
  )
}

///|
/// Viewer `vw`'s layer, node `n` (viewer_node's).
fn image_layer(n : @view.View, src : Source, vw : Viewer, stage : () -> (Double, Double)) -> Unit {
  n.over(Is(true)) |> ignore
  vw.in_tree = true
  n.owns(fn() {
    vw.in_tree = false
    (vw.hold_off)()
    vw.fingers.clear()
  })
  |> ignore
  // set out as it is made: the moment of what opened it
  vw.set_out(@ui.current(), src, n.cause_at())
  image_ends(n, vw)
  // what it reads asked of the core as what it needs comes (its kind sniffed, its bytes, a read failed)
  n.reacts(fn() { (vw.sniffed.get(), vw.bytes.get() is Some(_), vw.error.get() is Some(_), vw.fetching.get()) }, fn(_) {
    vw.fetch(@ui.current(), src)
  })
  // the images beside it read ahead as what is beside it is said (the core's imageNear, its folder), at that change:
  // what draws it reads only what came of them
  n.reacts(fn() { vw.near_ids(src) }, fn(_) {
    let (before, after) = vw.near(src)
    vw.read_near(src, before, after)
  })
  // the stage: the room it is laid out in (the keyboard over it, not the stage made shorter for it: FilePreview.kt),
  // and the picture's size (as sent, else as decoded, else its stand-in's: followed by its own decodes), told the zoom
  // at the moment either changes
  n.reacts(
    fn() {
      let (w, h) = stage()
      ((w, h + @ui.current().ime_inset()), vw.natural_size(src))
    },
    fn(told) {
      let ((bw, bh), (nw, nh)) = told
      let at = n.cause_at()
      vw.zoom.boxed(bw, bh, at~)
      vw.zoom.natural(nw, nh, at~)
    },
  )
  // lifted over the keyboard while marking, as far as keeps what is being written (or the open note's pin, its box
  // under it) 24 clear of it: its way said as the keyboard comes or goes or what is written moves, at that moment
  // (the same lift a finger on the picture is placed by: Viewer::marks_rect)
  n.reacts(
    fn() {
      // (followed: marking, the keyboard, what the zoom is told; worked out where the picture is at the cause's
      // moment, the one the lift sets out at)
      marks_said()
      vw.zoom.told()
      let ime = @ui.current().ime_inset()
      let below = match marks_writing_bottom_in(vw.zoom, vw.zoom.rect_at(n.cause_at())) {
        Some(b) => b + marks_keyboard_gap - stage().1
        None => 0.0
      }
      if ime > 0.0 && below > 0.0 {
        below
      } else {
        0.0
      }
    },
    fn(to) {
      if to != vw.lift.target() {
        vw.lift.go(to, @motion.animate_spring, at=n.cause_at())
      }
    },
  )
  // its ground, as far in as it has come (its flight's share, its fade): sampled as each frame draws it while either
  // goes, at their ends once neither does (the clock read no more)
  n.box(fn(g) {
    g
    .over(Is(true))
    .ground(By(fn() {
      vw.fly.said()
      vw.fade.said()
      let now = g.logic_at()
      let t = if vw.fly.goes_at(now) || vw.fade.goes_at(now) { g.drawn_at() } else { @double.infinity }
      @sf.alpha(vw.ground_ink(), vw.flight_share_at(t) * vw.fade.value_at(t))
    }))
    |> ignore
  })
  |> ignore
  // the canvas: what a finger does on it, the picture drawn in it
  n.box(fn(canvas) {
    canvas
    .over(Is(true))
    // (closed: what is on it the viewer's going alone, a finger on it called off then)
    .presses(By(fn() {
      match pv_leaving.get() {
        Some(l) => !physical_equal(l, vw)
        None => true
      }
    }))
    .on_drag(fn(d) { vw.finger_on(canvas, src, d) }, fingers=2)
    // (the pointer's secondary button on the picture: its menu, as a finger held still on it opens it)
    .on_menu(fn(m) { vw.menu_on(m) })
    |> ignore
    // (what it draws takes a finger only where it has something of its own to press: a mark's pin, the words being
    // written; the stage under it only pointed at, for the wheel)
    @ui.old(canvas, fn(c) {
      viewer_built.drawing += 1
      // (whether it marks, and what: what it draws decided by it, followed here where that is decided)
      marks_said()
      let stage = c.id("preview/stage")
      c.box(style=viewer_under, id=stage, taps=false, points=true, fn() { vw.image_view(c, src, stage, false) })
      |> ignore
      vw.wheel(c, stage, vw.zoom)
    })
    .over(Is(true))
    |> @ui.old_takes_own
    |> ignore
  })
  |> ignore
  // the bars over it: theirs where they have something to press, the rest the canvas's
  @ui.old(n, fn(c) {
    viewer_built.bars += 1
    image_bars(c, src, vw)
  })
  .over(Is(true))
  |> @ui.old_takes_own
  |> ignore
}

///|
/// How much of the ground its flight has brought at `t` (Viewer::flying's, at a moment of its own: its way alone, at
/// the stage (1) where it flies no more).
fn Viewer::flight_share_at(self : Viewer, t : Double) -> Double {
  let e = self.fly.value_at(t)
  if e >= 1.0 {
    1.0
  } else if e <= self.fly_lift {
    0.0
  } else {
    (e - self.fly_lift) / (1.0 - self.fly_lift)
  }
}

///|
/// The canvas's colour under what it shows (viewer_layer's ground).
fn Viewer::ground_ink(self : Viewer) -> Int64 {
  if self.dark() {
    0x000000FFL
  } else if self.shown_kind() == Some(KPdf) {
    let t = @sf.theme()
    @sf.mix(t.p.text, 0.05, t.p.bg)
  } else {
    @sf.theme().p.canvas
  }
}

///|
/// What is done at the ends of `vw`'s ways, on node `n`'s timeline: landed from its thumbnail, the thumbnail shown
/// again (one picture on the screen, never two); gone (back into its thumbnail, or faded out), let go of.
fn image_ends(n : @view.View, vw : Viewer) -> Unit {
  if vw.flies && !vw.fly_back {
    n.at_moment(vw.fly.end(), fn() {
      if vw.flies && !vw.fly_back {
        vw.flies = false
        pv_hidden.val = ""
      }
    })
    |> ignore
  }
  // (closed: done at the end of the way it is said to go then)
  let ends : Ref[() -> Unit] = Ref(fn() {  })
  n.reacts(
    fn() {
      match pv_leaving.get() {
        Some(l) => physical_equal(l, vw)
        None => false
      }
    },
    fn(going) {
      (ends.val)()
      if going {
        let end = if vw.flies { vw.fly.end() } else { vw.fade.end() }
        ends.val = n.at_moment(end, fn() {
          match pv_leaving.get() {
            Some(l) if physical_equal(l, vw) => {
              pv_hidden.val = ""
              leaving_done()
            }
            _ => ()
          }
        })
      }
    },
  )
}

///|
/// The bars over the picture and what is said with them (viewer_layer's, for a viewer the window's tree draws): the
/// steps to the pictures beside it, its bar (or marking's foot), what it was asked to save once its bytes came, the
/// download told, back.
fn image_bars(c : @ui.Ctx, src : Source, v : Viewer) -> Unit {
  // (marking as it is: the bars follow what a finger on the picture did to it)
  marks_said()
  src_now.val = src.now
  v.marks_frame(c)
  let shown = if v.flies { v.flying() } else { v.fade.get() }
  if v.save_after && v.bytes.get() is Some(_) {
    v.save_after = false
    v.ask_save(c)
  }
  c.box(style=viewer_under, fn() {
    if !marking.on {
      c.layer(fn() { vf_steps(v, c, src, shown) }) |> ignore
    } else {
      c.layer(fn() {
        c.spacer()
        marks_foot(c)
        let nav = (@sf.viewer_host().room)().1
        if nav > 0.0 {
          c.box(style=@ui.style(w=Full, h=Fixed(nav)), fn() {  }) |> ignore
        }
      })
      |> ignore
    }
    c.layer(fn() { vf_bar(v, c, src, shown) }) |> ignore
  })
  |> ignore
  if v.download_asked {
    v.download_asked = false
    let (station, key, name, size, from) = (v.station, v.key, v.name, v.file.size, v.opened_from())
    c.tell("download/" + name, fn() { download_start(src, station, key, name, size, from~) })
  }
  if !v.closing {
    c.take_back(fn() { if marking.on { marks_back(c) } else { v.shut(c) } })
  }
}

///|
/// A finger's event on the canvas of viewer `v` (node `canvas`), at its own moment: what the old view's stage worked
/// out from the frames (Viewer::gestures), from the events themselves. One finger moves the picture where it is larger
/// than the stage, else the strip to the one beside it (let go: on to it, or back); two pinch round the point between
/// them; let go moving, it flings on; a tap shows or hides the bars, two zoom in or back; held still, its menu;
/// marking, one finger draws. Everything it decides is decided as things are at the event's moment (the picture's
/// place, zoomed or not, its edges, the strip: by their ways, read there), whatever frames were drawn meanwhile; where
/// on the stage, in the canvas's own terms; how far a finger went, in the window's.
fn Viewer::finger_on(self : Viewer, canvas : @view.View, src : Source, d : @view.Drag) -> Unit {
  let v = self
  let c = @ui.current()
  let z = v.zoom
  let at = d.at
  let (x, y) = (d.wx, d.wy)
  // (the canvas's own terms for a point of the window's, as it is drawn at this moment)
  let (ox, oy) = (d.x - d.wx, d.y - d.wy)
  let strip = pv_strip.way
  let (before, after) = v.near(src)
  let (has_before, has_after) = (before is Some(_), after is Some(_))
  match d.kind {
    Down => {
      v.fingers[d.finger] = (x, y)
      if v.fingers.length() == 1 {
        v.held = true
        v.down_x = x
        v.down_y = y
        v.down_lx = d.x
        v.down_ly = d.y
        v.last_x = x
        v.last_y = y
        v.speed.reset()
        v.speed.add(at, x, y)
        if !v.pinched {
          v.moved = 0.0
          // flinging, or sliding to the one beside it: it stops where it is, and the press taps nothing
          v.caught = z.stop_fling(at~)
          let s = strip.value_at(at)
          if strip.goes_at(at) {
            strip.put(s)
            v.caught = true
          }
          v.strip_down = s
        }
        let (rx, _, rw, _) = z.rect_at(at).unwrap_or((0.0, 0.0, 0.0, 0.0))
        v.at_left = rx >= -0.5
        v.at_right = rx + rw <= z.bw + 0.5
        if marking.on {
          match v.marks_rect(at) {
            Some(r) => marks_finger(c, 0, d.x, d.y, r, z.nw)
            None => ()
          }
        } else if !@sf.pointer_rests() {
          // a finger held still: the picture's menu, once its whole is here, where the finger is on it (as it is then;
          // a mouse's button held asks for none: its menu is the secondary button's, Viewer::menu_on)
          let due = at + @ui.long_press_ms
          v.hold_off = canvas.at_moment(due, fn() {
            match (z.rect_at(due), v.bytes.get()) {
              (Some((rx, ry, rw, rh)), Some(b)) if v.held && v.moved <= tap_slop && !v.pinched &&
                v.fingers.length() == 1 &&
                v.down_lx >= rx &&
                v.down_lx < rx + rw &&
                v.down_ly >= ry &&
                v.down_ly < ry + rh => {
                v.caught = true
                @ui.haptic(LongPress)
                v.picture_menu_at(@ui.current(), v.down_x, v.down_y, b)
              }
              _ => ()
            }
          })
        }
      } else {
        // a second finger: a pinch round the point between them; a swipe going goes back, not left between two; a mark
        // being drawn or moved, called off
        (v.hold_off)()
        marks_finger_off()
        let (cx, cy, dist) = v.pinch_now()
        v.pinch_d = dist
        v.pinch_x = cx
        v.pinch_y = cy
        v.pinched = true
        if v.swiping {
          v.swiping = false
          strip.go(0.0, @motion.sheet_spring, at~)
        }
        v.held = false
      }
    }
    Moved => {
      v.fingers[d.finger] = (x, y)
      if v.fingers.length() >= 2 && z.nw > 0.0 {
        // round the point between them on the stage, moved as far as it went
        let (cx, cy, dist) = v.pinch_now()
        if v.pinch_d > 0.0 && dist > 0.0 {
          z.transform(cx + ox, cy + oy, dist / v.pinch_d, cx - v.pinch_x, cy - v.pinch_y, at~)
        }
        v.pinch_d = dist
        v.pinch_x = cx
        v.pinch_y = cy
      } else {
        v.one_finger_at(d, has_before, has_after)
      }
    }
    Up | Off => {
      v.fingers.remove(d.finger)
      if !v.fingers.is_empty() {
        // one of two let go: the pinch over, the one left followed from where it is next
        v.pinch_d = 0.0
        v.held = false
        return
      }
      (v.hold_off)()
      v.hold_off = fn() {  }
      let pinched = v.pinched
      if d.kind == Off {
        // called off: nothing it would have come to (a mark being drawn dropped, one moved back)
        v.pinched = false
        marks_finger_off()
        if v.swiping {
          strip.go(0.0, @motion.sheet_spring, at~)
        }
        v.swiping = false
        v.held = false
        return
      }
      // where it was let go, and when, the last of its way: as a move of its own first (however far from the last
      // move, or with none: a down and an up alone; how fast it went as of then, a pause before it slowing it to none);
      // the last of a pinch let go, nothing of its own
      if v.held {
        v.one_finger_at(d, has_before, has_after)
      }
      v.pinched = false
      if marking.on && !pinched {
        match v.marks_rect(at) {
          Some(r) => marks_finger(c, 2, d.x, d.y, r, z.nw)
          None => ()
        }
        v.held = false
        return
      }
      v.image_let_go(c, src, d, pinched, has_before, has_after)
    }
  }
}

///|
/// One finger alone on the canvas at `d` (moved, or let go there): marking, the mark it draws or moves; else the way
/// from where it was last, how fast as of then, and what that does (the zoomed picture with it, the strip sideways, the
/// fitted one panned); after a pinch, followed from here.
fn Viewer::one_finger_at(self : Viewer, d : @view.Drag, has_before : Bool, has_after : Bool) -> Unit {
  let v = self
  let z = v.zoom
  let strip = pv_strip.way
  let at = d.at
  let (x, y) = (d.wx, d.wy)
  if marking.on && !v.pinched {
    match v.marks_rect(at) {
      Some(r) => marks_finger(@ui.current(), 1, d.x, d.y, r, z.nw)
      None => ()
    }
  } else if !v.held {
    // one finger again after a pinch: followed from where it is now
    v.held = true
    v.last_x = x
    v.last_y = y
    v.speed.reset()
    v.speed.add(at, x, y)
  } else {
    let dx = x - v.last_x
    let dy = y - v.last_y
    v.moved = v.moved + dx.abs() + dy.abs()
    v.speed.add(at, x, y)
    if v.moved > tap_slop {
      (v.hold_off)()
    }
    if z.zoomed_at(at) {
      // zoomed in: it goes with the finger (at once after a pinch)
      if (v.moved > tap_slop || v.pinched) && (dx != 0.0 || dy != 0.0) {
        v.drag_zoomed(z, strip, dx, dy, has_before, has_after, at)
      }
    } else {
      // fitted, one finger sideways moves the strip, under the finger from where it went down; past the first or
      // the last a third as far
      let mut dx = dx
      if !v.swiping &&
        v.moved > tap_slop &&
        (x - v.down_x).abs() > (y - v.down_y).abs() &&
        (has_before || has_after) &&
        !v.pinched {
        v.swiping = true
        pv_strip.leaving = None
        dx = x - v.down_x
      }
      if v.swiping {
        let s = strip.value_at(at)
        let next = s + dx
        let none = if next > 0.0 { !has_before } else { !has_after }
        strip.put(if none { s + dx / 3.0 } else { next })
      } else if v.moved > tap_slop && (dx != 0.0 || dy != 0.0) {
        z.pan(dx, dy, at~)
      }
    }
    v.last_x = x
    v.last_y = y
  }
}

///|
/// The pointer's secondary button pressed on the canvas (`m`, at its moment): the picture's menu where it is on the
/// picture as it is then, once its whole is here; off it, or marking, none.
fn Viewer::menu_on(self : Viewer, m : @view.Menu) -> Unit {
  if marking.on {
    return
  }
  match (self.zoom.rect_at(m.at), self.bytes.get()) {
    (Some((rx, ry, rw, rh)), Some(b)) if m.x >= rx && m.x < rx + rw && m.y >= ry && m.y < ry + rh =>
      self.picture_menu_at(@ui.current(), m.wx, m.wy, b)
    _ => ()
  }
}

///|
/// Where the picture is at `at` as marking draws it: lifted over the keyboard as far as its lift has come then.
pub fn Viewer::marks_rect(self : Viewer, at : Double) -> (Double, Double, Double, Double)? {
  let lift = self.lift.value_at(at)
  self.zoom.rect_at(at).map(fn(r) { (r.0, r.1 - lift, r.2, r.3) })
}

///|
/// How far a finger goes before what it does is a drag, not a tap (the old stage's).
let tap_slop : Double = 8.0

///|
/// The point between the first two fingers on it and how far apart they are.
fn Viewer::pinch_now(self : Viewer) -> (Double, Double, Double) {
  let ps = self.fingers.values().collect()
  if ps.length() < 2 {
    return (0.0, 0.0, 0.0)
  }
  let ((x1, y1), (x2, y2)) = (ps[0], ps[1])
  ((x1 + x2) / 2.0, (y1 + y2) / 2.0, ((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2)).sqrt())
}

///|
/// The last finger let go (`d`, at its moment): a swipe on to the one beside it or back, a fling, a tap or two.
fn Viewer::image_let_go(
  self : Viewer,
  c : @ui.Ctx,
  src : Source,
  d : @view.Drag,
  pinched : Bool,
  has_before : Bool,
  has_after : Bool,
) -> Unit {
  let v = self
  let z = v.zoom
  let strip = pv_strip.way
  let at = d.at
  let (x, y) = (d.wx, d.wy)
  let zoomed = z.zoomed_at(at)
  let (vx, vy) = v.speed.get()
  let s = strip.value_at(at)
  if v.held && (v.swiping || s != 0.0) && (!zoomed || s != 0.0) {
    // on to the one beside it (this press's way far enough, or flung that way), else back
    let width = z.bw + slide_gap
    let base = if v.strip_down > width / 2.0 { -1 } else if v.strip_down < -width / 2.0 { 1 } else { 0 }
    let dx = s - v.strip_down
    let far = dx.abs() > dmin(80.0, z.bw / 5.0)
    let from_edge = !zoomed || (if dx > 0.0 { v.at_left } else { v.at_right })
    let flung = from_edge && vx.abs() > 0.3 && (vx > 0.0) == (dx > 0.0) && dx.abs() > 10.0
    let step = if dx != 0.0 && (far || flung) { if dx > 0.0 { -1 } else { 1 } } else { 0 }
    let to = base + step
    if to < 0 {
      v.go(c, src, -1, vx * 1000.0)
    } else if to > 0 {
      v.go(c, src, 1, vx * 1000.0)
    } else {
      strip.go(0.0, @motion.sheet_spring, at~, velocity=vx * 1000.0)
    }
  } else if v.held && zoomed && (v.moved > tap_slop || pinched) {
    // zoomed in, let go moving: on at the finger's speed, slowing, to a stop or its edge
    z.fling(vx, vy, at~)
  }
  v.swiping = false
  let held = v.held
  v.held = false
  // pinched smaller than fitted and let go: back to fitted (as small as it is at the let go)
  if pinched && z.scale_at(at) < z.fit() {
    z.reset(at~)
  }
  // a tap (and a second: zoomed in, or back)
  if held && v.moved <= tap_slop && !pinched && !v.caught {
    let on_picture = match z.rect_at(at) {
      Some((rx, ry, rw, rh)) => d.x >= rx && d.x < rx + rw && d.y >= ry && d.y < ry + rh
      None => false
    }
    if (@sf.pointer_rests() || (!zoomed && @sf.native_able())) && !on_picture && !marking.on {
      v.shut(c)
    } else if at - v.tap_at < double_tap_ms && (x - v.tap_x).abs() < 40.0 && (y - v.tap_y).abs() < 40.0 {
      v.tap_at = -1.0e9
      v.toggle()
      z.double_tap(d.x, d.y, at~)
    } else {
      v.tap_at = at
      v.tap_x = x
      v.tap_y = y
      v.toggle()
    }
  }
}
