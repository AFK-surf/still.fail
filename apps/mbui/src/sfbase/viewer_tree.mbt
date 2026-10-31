// The image viewer as nodes of the window's tree (every shell's: sfapp's narrow_shell.mbt, tape_shell.mbt;
// docs/retained.md), made as it opens and let go as it has gone, over the pages:
//
//   - its layer: the whole window, a modal layer while it is the one open (View::modal: what is under it, the pages
//     and what the shell draws round them, takes no press, key, wheel or stop of Tab, and is read out none, as the old
//     frame's modal overlay made it; closing, theirs again as it begins to go);
//   - its ground: the canvas's colour, as far in as the viewer has come (its flight, its fade), sampled as each frame
//     draws it while either goes;
//   - its canvas: what a finger does on the picture is this node's, each event at its own moment (one finger drags,
//     two pinch, a tap shows or hides the bars, two zoom, a hold opens the picture's menu, marking draws), and so the
//     secondary button (the picture's menu) and the wheel; the zoom told the stage's size and the picture's as either
//     changes, at that moment; what is beside it read ahead as that is said;
//   - in it, what draws the picture (an old view taking a press only on what it has to press: a mark's pin, the words
//     written; the picture where its zoom has it as the frame draws it, its flight, the pictures beside it), and over
//     it the bars: the floating bar on a small screen, its picture coming or whole and not marked, nodes of its own
//     (image_head, head_as_nodes: how much of it has come, its tools, their tips); the bar across the top of a wider
//     screen, its picture coming or whole and not marked, nodes too (image_bar, bar_as_nodes); the ways to the
//     pictures beside it while it is not marked (image_steps); the rest an old view taking a press only where it has
//     something to press (marking's bars).
//
// It sets out as the node is made (that moment its cause's: the thumbnail tapped), and is done at its ways' declared
// ends (moments on the node's timeline): landed, the thumbnail shows again; gone, it is let go.
//
// What a download, a save or marking's picture asks is done by the layer at its cause (image_layer), whichever bar
// asked.
//
// Still the old view's here (the way there): what those old bars do (their own presses, Esc and back: a press on one
// taken as the bars' view builds, so what draws the picture follows it at the next frame), the flight in and out
// (where it flies from, recorded as it is drawn; the thumbnail's place read of the old layout).

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
/// The image viewer in node `v` of the window's tree (laid out over the pages: narrow_shell, tape_shell), made as one opens and let
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
  // (over the pages, a modal layer: what is under it (the pages, the bar, what the shell draws round them) takes no key,
  // no wheel, no stop of Tab, and is read out none, as the old frame's modal overlay made it; what opens over all of it,
  // a menu, a sheet, its own)
  n
  .over(Is(true))
  // (while it is the one open: closing, the pages' input theirs again as it begins to go, whatever is still drawn)
  .modal(By(fn() {
    match viewer.get() {
      Some(v) => physical_equal(v, vw)
      None => false
    }
  }))
  // (its keys, at their moment, where nothing over it (a menu, a field being written in) takes them first)
  .on_key(fn(k) { vw.key_on(src, k) })
  // (back: leaving marking first, else closing it; a sheet, a menu over it, theirs first: Ctx::back_taker)
  .takes_back(fn() {
    if !vw.closing {
      if marking.on {
        marks_back(@ui.current())
      } else {
        vw.shut(@ui.current())
      }
    }
  })
  |> ignore
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
  // what marking made, taken as the host says it is drawn (MarkedImage::ready, its answers' signal): kept, or into the
  // chat's draft, once (Viewer::marks_frame takes it), by this viewer while it is the one open and its layer here; a
  // drawing another by its id, whatever it drew
  n.reacts(
    fn() {
      marks_said()
      match marking.job {
        Some(j) => Some((j.id(), j.ready()))
        None => None
      }
    },
    fn(job) {
      match (job, viewer.get()) {
        (Some((_, true)), Some(v)) if physical_equal(v, vw) && !vw.closing => vw.marks_frame(@ui.current())
        _ => ()
      }
    },
  )
  // what was asked to be saved: a chat's file's download said to the core at the moment it was asked; what was asked
  // for before it was here saved as its whole comes; each once (Viewer::ask_save)
  n.reacts(fn() { (vw.asked_told.get(), vw.bytes.get() is Some(_)) }, fn(_) {
    download_told(src, vw)
    if vw.save_after && @signals.untracked(fn() { vw.bytes.get() }) is Some(_) {
      vw.save_after = false
      vw.ask_save(@ui.current())
    }
  })
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
  // the canvas: what a finger does on it, the picture drawn in it, as far in as its fade has come (as its ground is; a
  // flight's fade is put in whole, its picture the flight's own), sampled as its ground is
  n.box(fn(canvas) {
    canvas
    .over(Is(true))
    .alpha(By(fn() {
      vw.fade.said()
      let now = canvas.logic_at()
      vw.fade.value_at(if vw.fade.goes_at(now) { canvas.drawn_at() } else { @double.infinity })
    }))
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
    // (a wheel over it, at its moment, where it is on the stage then)
    .on_wheel(fn(w) { vw.wheeled(vw.zoom, w.x, w.y, w.dx, w.dy, w.mods, w.at) })
    |> ignore
    // (what it draws takes a finger only where it has something of its own to press: a mark's pin, the words being
    // written)
    @ui.old(canvas, fn(c) {
      viewer_built.drawing += 1
      // (whether it marks, and what: what it draws decided by it, followed here where that is decided)
      marks_said()
      let stage = c.id("preview/stage")
      c.box(style=viewer_under, fn() { vw.image_view(c, src, stage, false) }) |> ignore
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
  // (the floating bar over it on a small screen, its nodes: where the old bars draw it not, head_as_nodes)
  n.show(fn() { head_as_nodes(vw, stage().0) }, fn(h) { image_head(h, src, vw, stage) })
  // (the bar across the top of a wider window, its picture whole, its nodes: where the old bars draw it not,
  // bar_as_nodes)
  n.show(fn() { bar_as_nodes(vw, stage().0) }, fn(h) { image_bar(h, src, vw, stage) })
  // (marking's foot while it marks: its tools nodes, its notes the old view's, one column)
  n.show(
    fn() {
      marks_said()
      marking.on
    },
    fn(h) { marks_foot_node(h, fn() { (@sf.viewer_host().room)().1 }) },
  )
  // (the ways to the pictures beside it, its nodes, while it is not marked)
  n.show(
    fn() {
      marks_said()
      !marking.on
    },
    fn(h) { image_steps(h, src, vw, stage) },
  )
  // (a mouse's pointer along the top where the bar across it is: the bar shown while it is there, whatever is over it
  // then, the bar itself as it shows; as the pointer comes in or goes out (vf_bar's near, as the old frame read it of
  // its pointer each frame))
  n.box(fn(top) {
    top.over(Is(true)).height(Is(Some(@sf.viewer_bar_h))) |> ignore
    top.reacts(fn() { top.pointer_within() && @sf.pointer_rests() }, fn(near) {
      if vw.near_bar != near {
        vw.near_bar = near
        vw.awake_said()
      }
    })
  })
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
/// The bars over the picture and what is said with them (viewer_layer's, for a viewer the window's tree draws): its bar,
/// what marking made said (back, what was asked to be saved, a download asked: its layer's,
/// image_layer); the ways to the pictures beside it are nodes (image_steps).
fn image_bars(c : @ui.Ctx, src : Source, v : Viewer) -> Unit {
  // (marking as it is: the bars follow what a finger on the picture did to it)
  marks_said()
  src_now.val = src.now
  let shown = if v.flies { v.flying() } else { v.fade.get() }
  c.box(style=viewer_under, fn() {
    // (the ways to the pictures beside it its nodes: image_steps; marking's foot too: marks_foot_node)
    // (its keys its node's: Viewer::key_on)
    c.layer(fn() { vf_bar(v, c, src, shown, keys=false) }) |> ignore
  })
  |> ignore
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

///|
/// A key to viewer `vw` (its layer's: View::on_key), at its moment: Escape leaves marking (the marks it was making) or
/// else closes it; ← and → step to the picture before and after; the zoom's keys zoom (viewer_zoom_key). True where it
/// took the key; closing, it takes none.
fn Viewer::key_on(self : Viewer, src : Source, k : @view.Key) -> Bool {
  let v = self
  if v.closing {
    return false
  }
  let c = @ui.current()
  if k.code == @ui.key_escape && k.mods == 0 {
    if marking.on {
      marks_back(c)
    } else {
      v.shut(c)
    }
    return true
  }
  if marking.on || v.shown_kind() != Some(KImage) || (k.mods & (@ui.mod_cmd | @ui.mod_ctrl | @ui.mod_alt)) != 0 {
    return false
  }
  if k.code == @ui.key_code_left || k.code == @ui.key_code_right {
    v.go(c, src, if k.code == @ui.key_code_left { -1 } else { 1 }, 0.0)
    return true
  }
  @sf.viewer_zoom_key(v.zoom, k.code, k.mods, k.at)
}

///|
/// Whether viewer `v`'s floating bar is its nodes (image_head), `w` wide, the old bars' (vf_bar's) not: a picture here
/// coming or whole (not read, played or marked), on a small screen (a phone's; a fold half open wider than one, its
/// kind and size with it), its own bar (not the system's beside it: an iPhone Duo's). As each is told.
pub fn head_as_nodes(v : Viewer, w : Double) -> Bool {
  marks_said()
  v.in_tree &&
  v.shown_kind() == Some(KImage) &&
  !marking.on &&
  @sf.viewer_bar_floats(w) &&
  !@sf.native_on()
}

///|
/// Whether viewer `vw`'s bar across the top is its nodes (image_bar), `w` wide, the old bar's (vf_bar's) not: a picture
/// here, coming or whole or marked (not read or played), not on a small screen (whose bar floats: head_as_nodes), its own bar
/// (not the system's beside it). As each is told.
pub fn bar_as_nodes(v : Viewer, w : Double) -> Bool {
  marks_said()
  v.in_tree &&
  v.shown_kind() == Some(KImage) &&
  !@sf.viewer_bar_floats(w) &&
  !@sf.native_on()
}

///|
/// How far in viewer `vw` is as node `node` is drawn (its flight's share, else its fade, sampled as it is drawn while
/// either goes; where neither goes, as it is).
fn Viewer::shown_on(self : Viewer, node : @view.View) -> Double {
  let vw = self
  vw.fly.said()
  vw.fade.said()
  let now = node.logic_at()
  let t = if vw.fly.goes_at(now) || vw.fade.goes_at(now) { node.drawn_at() } else { @double.infinity }
  if vw.flies {
    vw.flight_share_at(t)
  } else {
    vw.fade.value_at(t)
  }
}

///|
/// Viewer `vw`'s floating bar as nodes in `h` (viewer_head_node, as vf_bar has it there): its file's name (its kind and
/// size after it, wider than a phone), there while its bars are (Viewer::bars_shown), as far in as the viewer is
/// (Viewer::shown_on); while its picture comes, how much of it has once the core has said (file_progress_node); its
/// tools (image_tools), ×. Each press done at its moment. Their tips in a layer of its own over all of it.
fn image_head(h : @view.View, src : Source, vw : Viewer, stage : () -> (Double, Double)) -> Unit {
  h.over(Is(true)) |> ignore
  let ink = fn() { @sf.page_viewer_ink() }
  let tips_at : Ref[@view.View?] = Ref(None)
  let tips = @sf.TipLayer::new(fn() { tips_at.val })
  let whole = fn() { vw.bytes.get() is Some(_) }
  let dl = fn() { vw.download(src) }
  @sf.viewer_head_node(
    h,
    fn() { vw.file.name },
    // (its kind and size after its name where the bar has room: wider than a phone, viewer_head_node)
    fn() { vf_meta(vw, src) },
    fn() { vw.bars_shown() },
    fn(node) { vw.shown_on(node) },
    fn() { (@sf.viewer_host().room)().0 },
    fn() { stage().0 },
    ink,
    fn() { @sf.viewer_page_glass() },
    fn(row) {
      // while it comes, how much of it has, once the core has said (FilePreview.tsx: FileComing in the floating head)
      row.show(fn() { vw.coming() && vw.got.get() is Some(_) }, fn(r) {
        file_progress_node(r, fn() { vw.got.get().unwrap_or((0.0, None)) }, fn() { vw.file.size }) |> ignore
      })
      image_tools(row, src, vw, ink, Is(@sf.tool_side / 2.0), tips)
    },
    fn() { "\{whole()} \{downloading(dl())} \{vw.coming()} \{vw.got.get() is Some(_)}" },
    fn() {
      if !vw.closing {
        vw.shut(@ui.current())
      }
    },
    tips=tips,
  )
  |> ignore
  // (its tips over all of it)
  tips_at.val = Some(h.box(fn(l) { l.over(Is(true)) |> ignore }))
}

///|
/// Viewer `vw`'s bar across the top as nodes in `h` (viewer_bar_node, as vf_bar has it there): back to where it was
/// opened from by name, its file's name and the line about it (which of how many, its size, its kind, its size in
/// pixels), where the file is its tip (none for a draft's, kept on this device alone); gone up while its bars are not
/// shown (Viewer::bars_shown), as far in as the viewer is (Viewer::shown_on); while its picture comes, how much of it
/// has (viewer_coming_node); its tools once it no longer does (image_tools), each round as a page's bar's buttons are at
/// the window's corner. Its way back closes it, at the press's moment. Their tips in a layer
/// of its own over all of it.
fn image_bar(h : @view.View, src : Source, vw : Viewer, stage : () -> (Double, Double)) -> Unit {
  h.over(Is(true)) |> ignore
  let ink = fn() { @sf.page_viewer_ink() }
  let tips_at : Ref[@view.View?] = Ref(None)
  let tips = @sf.TipLayer::new(fn() { tips_at.val })
  @sf.viewer_bar_node(
    h,
    fn() { vw.desk_back(src) },
    fn() { vw.file.name },
    fn() { vf_meta(vw, src) },
    fn() { if vw.file.path.has_prefix("draft:") { "" } else { vw.file.path } },
    fn() {
      // (marking, there: Viewer::bars_shown)
      marks_said()
      !vw.bars_shown()
    },
    fn(node) { vw.shown_on(node) },
    fn() { (@sf.viewer_host().room)().0 },
    fn() { stage().0 },
    ink,
    fn(row, corner) {
      // (while it comes, how much of it has: FilePreview.tsx FileComing in the bar, from the start)
      row.show(fn() { vw.coming() }, fn(r) {
        @sf.viewer_coming_node(r, fn() { vw.got.get() }, fn() { vw.file.size }, ink) |> ignore
      })
      // (its tools; marking, marking's actions in their place: vf_tools's)
      let marked = fn() {
        marks_said()
        marking.on
      }
      row.show(fn() { !marked() }, fn(r) {
        r.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(@sf.keys_apart())) |> ignore
        image_tools(r, src, vw, ink, corner, tips)
      })
      row.show(marked, fn(r) { marks_actions_node_of(r, vw, ink, tips) })
    },
    fn() {
      if !vw.closing {
        vw.shut(@ui.current())
      }
    },
    tips,
  )
  |> ignore
  tips_at.val = Some(h.box(fn(l) { l.over(Is(true)) |> ignore }))
}

///|
/// The ways to the pictures before and after viewer `vw`'s as nodes in `h` (viewer_steps_node, as vf_steps has them):
/// each while what is beside it says there is one (imageNear's, its folder's), there while its bars are
/// (Viewer::bars_shown), as far in as the viewer is (Viewer::shown_on), a phone's sizes under 640; pressed, a step to
/// that one at the press's moment (Viewer::go). Their tips in a layer of their own over all of it.
fn image_steps(h : @view.View, src : Source, vw : Viewer, stage : () -> (Double, Double)) -> Unit {
  h.over(Is(true)) |> ignore
  let tips_at : Ref[@view.View?] = Ref(None)
  let tips = @sf.TipLayer::new(fn() { tips_at.val })
  @sf.viewer_steps_node(
    h,
    fn() { vw.near_ids(src).0 is Some(_) },
    fn() { vw.near_ids(src).1 is Some(_) },
    fn() { vw.bars_shown() },
    fn(node) { vw.shown_on(node) },
    fn() { stage().0 <= @sf.viewer_small_w },
    fn(dir) {
      if !vw.closing {
        vw.go(@ui.current(), src, dir, 0.0)
      }
    },
    tips,
  )
  |> ignore
  tips_at.val = Some(h.box(fn(l) { l.over(Is(true)) |> ignore }))
}

///|
/// A picture's tools in a bar's row `row` (vf_tools's, as nodes): mark and copy once its picture is all here (copied:
/// a check for copied_ms, from the press's moment); download (unable while there is nothing to save; a ring while the
/// core downloads it; none while it comes). Each `corner` round, in `ink`, its tip in `tips`; each press done at its
/// moment, what a download asks for told once, as it is asked.
fn image_tools(
  row : @view.View,
  src : Source,
  vw : Viewer,
  ink : () -> @sf.ViewerInk,
  corner : @view.Live[Double],
  tips : @sf.TipLayer,
) -> Unit {
  let whole = fn() { vw.bytes.get() is Some(_) }
  let dl = fn() { vw.download(src) }
  // (copied: a check from the press, its end its own, another press another end)
  let copied : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })
  let copied_end : Ref[() -> Unit] = Ref(fn() {  })
  // 标注图片: once its whole picture is here (annotate/ImageMarks.tsx)
  row.show(whole, fn(r) {
    @sf.tool_node(
      r,
      fn() { { icon: "edit", label: @sf.t("web-main.annotate.image"), on: false, disabled: false } },
      ink,
      corner,
      fn() { marks_start() },
      tip=tips,
    )
    |> ignore
  })
  // 复制: the whole picture on the clipboard, a check a moment after (FilePreview.tsx CopyImage)
  row.show(whole, fn(r) {
    let t = @sf.tool_node(
      r,
      fn() {
        if copied.get() {
          { icon: "check", label: @sf.t("common.copied"), on: false, disabled: false }
        } else {
          { icon: "copy", label: @sf.t("common.copy"), on: false, disabled: false }
        }
      },
      ink,
      corner,
      fn() {
        match @signals.untracked(fn() { vw.bytes.get() }) {
          Some(b) => {
            @ui.current().copy_image(b)
            vw.copied += 1
            (copied_end.val)()
            copied.set(true)
            copied_end.val = r.at_moment(r.cause_at() + @sf.copied_ms, fn() { copied.set(false) })
          }
          None => ()
        }
      },
      tip=tips,
    )
    ignore(t)
    r.owns(fn() { (copied_end.val)() }) |> ignore
  })
  // download: what is here saved at once; one told of, read whole first; a ring while the core downloads it
  row.show(fn() { !vw.coming() && !downloading(dl()) }, fn(r) {
    @sf.tool_node(
      r,
      fn() {
        let saving = vw.bytes.get() is Some(_) || (vw.told_of() && !vw.asked)
        { icon: "download", label: @sf.t("web-main.preview.download"), on: false, disabled: !saving }
      },
      ink,
      corner,
      fn() { vw.ask_save(@ui.current()) },
      tip=tips,
    )
    |> ignore
  })
  row.show(fn() { !vw.coming() && downloading(dl()) }, fn(r) {
    @sf.tool_ring_node(r, fn() { number(dl(), "progress") }, fn() { @sf.t("web-main.preview.download") }, ink, corner)
    |> ignore
  })
}

///|
/// What viewer `vw` asked the core to download (Viewer::ask_save), told it once, at the moment it was asked
/// (image_layer's).
fn download_told(src : Source, vw : Viewer) -> Unit {
  if vw.download_asked {
    vw.download_asked = false
    let (station, key, name, size, from) = (vw.station, vw.key, vw.name, vw.file.size, vw.opened_from())
    @ui.current().tell("download/" + name, fn() { download_start(src, station, key, name, size, from~) })
  }
}

///|
/// How much of a file has come (file_progress's, FilePreview.kt FileProgress) as nodes in `parent`: "正在读取 **4 MB** /
/// 12 MB" (the size so far in bold, in the words' ink) over a bar, on the surface (surface2 dark), 14 round, 14 and 12
/// in, 220 wide; its size not known (neither the station's, `got`'s, nor the one it was sent with, `sent`), 正在读取 over
/// a bar that sweeps. Each as it changes: what has come, the words' language, the theme. The card's node.
pub fn file_progress_node(parent : @view.View, got : () -> (Double, Double?), sent : () -> Double) -> @view.View {
  let total = fn() -> Double? {
    match got().1 {
      Some(n) => Some(n)
      None => if sent() > 0.0 { Some(sent()) } else { None }
    }
  }
  let wide = match @sf.file_progress_w {
    Fixed(w) => w
    _ => 220.0
  }
  parent.box(fn(card) {
    card
    .width(Is(Some(wide)))
    .padding(Is((@ui.Space::px(S3_5), @ui.Space::px(S3), @ui.Space::px(S3_5), @ui.Space::px(S3))))
    .gap(Is(@ui.Space::px(S2)))
    .lines_up(Is(Some(Middle)))
    .radius(Is(file_progress_corner))
    .ground(By(fn() {
      let t = @sf.theme()
      if t.dark {
        surface2_dark
      } else {
        t.p.card
      }
    }))
    |> ignore
    card.box(fn(w) {
      w
      .words_runs(By(fn() {
        match total() {
          Some(n) => {
            // the size so far in bold, where the sentence has it
            let words = pv("android-chat.file.loading.size")
            let (before, after) = match words.find("{size}") {
              Some(i) => (words.view(end_offset=i).to_owned(), words.view(start_offset=i + 6).to_owned())
              None => (words, "")
            }
            [
              @view.words_run(before),
              @view.words_run(@sf.file_size(got().0), weight=600, ink=@sf.theme().p.text),
              @view.words_run(" / " + @sf.file_size(n) + after),
            ]
          }
          None => [@view.words_run(pv("common.reading"))]
        }
      }))
      .words_look(By(fn() {
        let (size, line) = @ui.tree_theme().text_size(Body)
        { size, weight: 400, line, wrap: true }
      }))
      .ink(By(fn() { @ui.tree_theme().color(Muted) }))
      |> ignore
    })
    |> ignore
    // (as wide as the card has room)
    @sf.progress_node(
      card,
      fn() {
        match total() {
          Some(n) if n > 0.0 => Some(dmin(1.0, got().0 / n))
          _ => None
        }
      },
      fn() { @ui.tree_theme().line },
      fn() { @sf.theme().p.accent },
    )
    .width_share(Is(1.0))
    |> ignore
  })
}
