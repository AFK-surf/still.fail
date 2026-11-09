// A panel whose body and foot are nodes (panel_nodes) as a sheet from the foot of the window (小屏's: @kit.sheet's, the
// host's present_sheet), as nodes of the window's tree: a modal layer over the window, what is under it dimmed by the
// sheet's scrim (black at 28%, in and out over @kit.sheet_scrim_ms, CSS's ease), the sheet in the window's foot as
// tall as what it holds (sheet_most of the window at most, what it holds scrolling in it past that; one a share of the
// window tall, `tall`, that share, what it holds filling the room it leaves and laid out in it), its top corners
// the pane's, on the frosted glass of a sheet; its grabber over its title (none where what it holds heads itself,
// `heads_itself`), what it says, what it holds and its foot,
// laid out as the host's sheet lays a panel out (sheet_step). It rises from below on a Move as long as its own height
// makes it (SheetRise, placed as it is drawn by how tall it is laid out: View::moved_by) and sinks away on one as
// it closes. Its top (sheet_drag_h: the grabber and the head) drags it down with the finger: let go more than
// sheet_drag_close down it closes, from where it is, else it goes back on a Move as fast as it was let go. Escape, the
// back and a press on what is above it close it (its gone told); what it holds closes it with what it was given.

///|
/// How far down a sheet's top is dragged before it closes as it is let go (@kit.sheet's, one without detents).
let sheet_drag_close : Double = 80.0

///|
/// How tall a sheet's top stands, that drags it (@kit.sheet's `drag_h`: the grabber and the head).
let sheet_drag_h : Double = 64.0

///|
/// A sheet of panel `x` (its body and foot `n`) in `parent` while `open()`; `close`: what what it holds is given to
/// close it; `cancel` as it is closed by Escape, the back, a press over it or its top dragged down. `shown`, `gone`: as
/// dialog_layer_node's.
fn sheet_node(
  parent : @view.View,
  open : () -> Bool,
  x : PanelOf,
  n : PanelNodes,
  close : () -> Unit,
  cancel : () -> Unit,
  from : Anchor,
  shown? : () -> Unit = fn() {  },
  gone? : () -> Unit = fn() {  },
) -> Unit {
  parent.show(
    open,
    fn(layer) {
      shown()
      layer.owns(gone) |> ignore
      // (how far its scrim is in; how far below its place it is, in its own heights; how far a finger has its top down)
      let dim = EdgeWay::new(0.0)
      let below = SheetRise::new()
      let held : @signals.Signal[Double?] = @signals.signal(None)
      let back = EdgeWay::new(0.0)
      // (one that grows (`grows`): how tall it is where it was dragged or tapped to another height, or a finger has it;
      // as tall as what it holds till then)
      let sized = @signals.signal(false)
      let tall = EdgeWay::new(0.0)
      let tall_held : @signals.Signal[Double?] = @signals.signal(None)
      layer.reacts(fn() { layer.leaving() }, fn(going) {
        if going {
          dim.go(layer, 0.0, @kit.sheet_scrim_ms, ease=Out)
          below.go(layer, 1.0)
        } else {
          dim.go(layer, 1.0, @kit.sheet_scrim_ms, ease=Out)
          below.go(layer, 0.0)
        }
      })
      let live = fn() { !layer.leaving() }
      // (a share of the window tall (`tall`, not a form): that tall, what it holds filling the room left it and laid out
      // in it, as the host's sheet has a capped panel's (sheet_capped_room))
      let capped = x.tall > 0.0 && !x.form
      layer
      .over(Is(true))
      // (modal while open: closing, what is under it its own again as it begins to go)
      .modal(By(live))
      .hides(By(fn() { layer.leaving() }))
      .held_back_goes_on()
      .ground(By(fn() { @ui.alpha(sheet_scrim, dim.shown(layer)) }))
      // (a press on what is above it its own, nothing under it pressed: closing it as it goes down)
      .presses(Is(true))
      .on_drag(fn(d) {
        if d.kind == Down && @signals.untracked(live) {
          cancel()
        }
      })
      .on_key(fn(k) {
        if k.code == @ui.key_escape && @signals.untracked(live) {
          cancel()
          true
        } else {
          false
        }
      })
      .takes_back(fn() {
        if @signals.untracked(live) {
          cancel()
        }
      })
      |> ignore
      // (the room over it: what a press closes it on)
      layer.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
      layer.box(fn(sheet) {
        sheet
        // (its foot past the window's by its corner, as the host's: its round corners only at its top)
        .margin(Is((0.0, 0.0, 0.0, -sheet_under)))
        .padding(Is((0.0, 0.0, 0.0, sheet_under)))
        .max_height(By(fn() {
          // (one that grows: up to the window's top as a finger draws it past its most, giving way)
          Some(layer.window().1 * (if x.grows { 1.0 } else { sheet_most }) + sheet_under)
        }))
        .height(By(fn() {
          match tall_held.get() {
            Some(h) => Some(h + sheet_under)
            None =>
              if sized.get() {
                Some(tall.shown(sheet) + sheet_under)
              } else if capped {
                // (its share of the window, as the host's sheet is: present_sheet's)
                Some(x.tall * layer.window().1 + sheet_under)
              } else {
                None
              }
          }
        }))
        .radius(Is(pane_corner))
        .glass(By(fn() {
          let t = theme()
          Some({ ..glass_sheet(), solid: over(over(t.p.bg, alpha(0x000000FFL, 0.28 * dim.shown(layer))), alpha(t.p.card, 0.8)) })
        }))
        .shadow(Is((sheet_raised.sigma, sheet_raised.dy, sheet_raised.color)))
        .clips(Is(true))
        // (below its place by its own height as it comes and goes, over the time that height takes, as tall as it is
        // laid out in the frame drawing it; down where a finger has its top, or going back)
        // (what is leaving with it, its layer, kept till it has sunk away, however tall: as the host's is, gone once it
        // has sunk and its scrim faded)
        .moved_by(
          fn(_, h, t) { (0.0, below.shown(h - sheet_under, t)) },
          fn(_, h) { below.ends(h - sheet_under) },
          holds_leaving=true,
        )
        .offset(By(fn() {
          match held.get() {
            Some(y) => (0.0, y)
            None => (0.0, back.shown(layer))
          }
        }))
        .says(Is(Some(@view.said(Dialog, label=x.title))))
        // (a press on it its own: not over it)
        .presses(Is(true))
        .on_press(fn() {  })
        |> ignore
        // its top (sheet_drag_h: the grabber and the head) drags it: what a finger put down there does, as the host's
        // (@kit.sheet's): one that grows taller or shorter, settling at the detent it is let go nearer, closing let go
        // under sheet_close_below of the window, a tap on its grabber to the other end; one that does not only down,
        // closing past sheet_drag_close
        let from_y = Ref(-1.0)
        let from_h = Ref(0.0)
        sheet.on_drag(fn(d) {
          guard @signals.untracked(live) else { return }
          if d.kind == Down {
            // (its own height as laid out as of then, the drag's: its foot's room past the window taken off)
            from_y.val = if d.oy < sheet_drag_h { d.wy } else { -1.0 }
            from_h.val = d.h - sheet_under
          }
          guard from_y.val >= 0.0 else { return }
          let dy = d.wy - from_y.val
          let total = layer.window().1
          if x.grows {
            let top = total * sheet_most
            let to = dmax(from_h.val - dy, sheet_least_h)
            let now = sheet_stretched(to, top, total - top)
            match d.kind {
              Down => ()
              Moved => tall_held.set(Some(now))
              Up | Off => {
                tall_held.set(None)
                let at = if d.kind == Up && dy.abs() < @ui.touch_slop() { from_h.val } else { now }
                tall.put(at)
                sized.set(true)
                if d.kind == Up && dy.abs() < @ui.touch_slop() {
                  // (a tap on its grabber, its top 30: to the other end)
                  if d.oy < sheet_grab_tap {
                    let (lo, hi) = (sheet_grows_to[0], sheet_grows_to[1])
                    tall.go_by(sheet, if at > (lo + hi) / 2.0 * total { lo * total } else { hi * total }, @motion.move())
                  }
                } else if at / total < sheet_close_below {
                  cancel()
                } else {
                  let f = sheet_nearest(sheet_grows_to, at / total)
                  tall.go_by(sheet, f * total, @motion.move())
                }
              }
            }
          } else {
            let down = dmax(0.0, dy)
            match d.kind {
              Down => held.set(Some(0.0))
              Moved => held.set(Some(down))
              Up | Off => {
                held.set(None)
                back.put(down)
                if d.kind == Up && down > sheet_drag_close {
                  // (closed from where it is: it sinks away from there)
                  cancel()
                } else {
                  back.go_by(layer, 0.0, @motion.move())
                }
              }
            }
          }
          if d.kind == Up || d.kind == Off {
            from_y.val = -1.0
          }
        })
        |> ignore
        // (the grabber: 38 × 5 in the line's colour, 12 over it and 8 under)
        sheet.box(fn(g) {
          style_node(g, fn() { sheet_grab_outer })
          g.box(fn(i) {
            style_node(i, fn() { sheet_grab_inner })
            i.box(fn(b) { style_node(b, fn() { sheet_grabber.then(@ui.style(bg=Data(theme().p.line))) }) }) |> ignore
          })
          |> ignore
        })
        |> ignore
        // (its title; none where what it holds heads itself, `heads_itself`: its own title's row there)
        if x.title != "" && !x.heads_itself {
          sheet.box(fn(r) {
            style_node(r, fn() { sheet_title_row })
            words_node(r, fn() { x.title }, fn() { sheet_title_words }) |> ignore
          })
          |> ignore
        }
        // what it holds, scrolling where the sheet is short of room for it; a share of the window tall, filling the room
        // it leaves, laid out in it (sheet_capped_room)
        if capped {
          sheet.box(fn(b) {
            b.grow(Is(1.0)).shrink(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
            b.box(fn(col) {
              style_node(col, fn() { sheet_capped_room })
              col.min_height(Is(Some(0.0))) |> ignore
              // (laid out as the host's sheet lays out a capped panel's body: narrow, its words a sheet's own in, sheet_step's)
              panel_in_lend(col, Narrow, sheet_panel_sides)
              (n.body)(col, close)
            })
            |> ignore
          })
          |> ignore
        } else {
        sheet.box(fn(b) {
          let scroll = @view.Scroll::new()
          b.shrink(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
          b.scrolls(scroll, slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(s) {
            if x.description != "" {
              s.box(fn(w) {
                style_node(w, fn() { sheet_words_at })
                words_node(w, fn() { x.description }, fn() { sheet_lead }) |> ignore
              })
              |> ignore
            }
            // (in from its sides as the host's sheet has a panel's: opened by a press as far in as a pick's rows,
            // else as its words)
            let room = if from != Unanchored {
              if n.foot is None { sheet_held } else { sheet_held_sides }
            } else {
              sheet_panel
            }
            s.box(fn(col) {
              style_node(col, fn() { room })
              // (laid out as the host's sheet lays out a panel's body, sheet_step's: narrow; its words what a sheet's rows
              // leave of its words' in one a press opened, its rows out to its words' in one opened by nothing)
              let pressed = from != Unanchored
              panel_in_lend(
                col,
                Narrow,
                if pressed { sheet_panel_sides - sheet_row_sides } else { 0.0 },
                rows_out=dmax(0.0, (if pressed { sheet_row_sides } else { sheet_panel_sides }) - panel_card_in),
              )
              (n.body)(col, close)
            })
            |> ignore
          })
          .clips(By(fn() { scroll.goes() }))
          .bounds_input(By(fn() { scroll.goes() }))
          |> ignore
        })
        |> ignore
        }
        match n.foot {
          Some(f) => {
            if x.ruled {
              sheet.box(fn(r) { style_node(r, fn() { sheet_foot_rule }) }) |> ignore
            }
            sheet.box(fn(row) {
              style_node(row, fn() { sheet_foot_at })
              f(row, close)
            })
            |> ignore
          }
          None => ()
        }
        // (under it, the navigation bar's room: sheet_foot)
        sheet.box(fn(nav) { nav.height(By(fn() { Some(@ui.system_bars().bottom) })) |> ignore }) |> ignore
      })
      |> ignore
      layer.focus_returns() |> ignore
    },
    // (its scrim's fade; and its sinking away, which holds it: View::moved_by)
    leave=@kit.sheet_scrim_ms,
  )
}

///|
/// How short a sheet that grows is dragged at most (@kit.sheet's).
let sheet_least_h : Double = 120.0

///|
/// Under what share of the window a sheet that grows closes as it is let go (@kit.sheet's `close_below`).
let sheet_close_below : Double = 0.3

///|
/// How far down its top a press is on its grabber (@kit.sheet's: its top 30).
let sheet_grab_tap : Double = 30.0

///|
/// How tall a sheet is drawn `h` high under a finger, its top `top` and `room` above that (@kit.sheet's stretched): as
/// high as the finger has it up to its top, past it giving way more the further it is drawn, never past the room there
/// is.
fn sheet_stretched(h : Double, top : Double, room : Double) -> Double {
  if h <= top || room <= 0.0 {
    return dmin(h, top)
  }
  let x = h - top
  top + (1.0 - 1.0 / (x * sheet_give / room + 1.0)) * room
}

///|
/// How much a sheet drawn past its top gives way (@kit.sheet's: UIScrollView's rubber band's constant).
let sheet_give : Double = 0.55

///|
/// Which of `shares` `f` is nearest (@kit.sheet's).
fn sheet_nearest(shares : Array[Double], f : Double) -> Double {
  shares.fold(init=shares[0], fn(best, s) { if (s - f).abs() < (best - f).abs() { s } else { best } })
}

///|
/// How far a sheet is below its place, in its own heights (1: out of the window, 0: risen), as it rises and sinks: each
/// way a Move from where the one before had it at that way's cause's moment (as fast as it went then) to where it goes,
/// as long as its own height makes it (@kit.sheet's below, a SpringPath that moves: move_ms of how far it goes). Only
/// how far and when are said; where it is is worked out as it is drawn, by how tall it is laid out then
/// (View::moved_by), so a way under way follows the height it comes to.
struct SheetRise {
  /// where it was before its first way, and its ways (their cause's moment, where to)
  mut start : Double
  ways : Array[(Double, Double)]
  /// told as a way is said
  said : @signals.Signal[Int]
}

///|
fn SheetRise::new() -> SheetRise {
  { start: 1.0, ways: [], said: @signals.signal(0) }
}

///|
/// Off to `to` (in its heights) from `n`'s cause's moment, from where it is then.
fn SheetRise::go(self : SheetRise, n : @view.View, to : Double) -> Unit {
  let at = n.cause_at()
  // (the ways before over, however tall it is: from where the last of them went)
  match self.ways.last() {
    Some((_, last_to)) if last_to == to => return
    Some((last_at, last_to)) if at >= last_at + @ui.move_most_ms => {
      self.start = last_to
      self.ways.clear()
    }
    None if self.start == to => return
    _ => ()
  }
  self.ways.push((at, to))
  self.said.set(@signals.untracked(fn() { self.said.get() }) + 1)
}

///|
/// Where it is at moment `t` (in its heights), `d` points one of its heights, and when its last way ends (no way said:
/// none, -1).
fn SheetRise::at(self : SheetRise, d : Double, t : Double) -> (Double, Double) {
  let mut x = self.start
  // (its speed, its heights a millisecond)
  let mut v = 0.0
  let mut end = -1.0
  for i, w in self.ways {
    let (from_at, to) = w
    let last = i + 1 >= self.ways.length()
    let until = if last { t } else { self.ways[i + 1].0 }
    let dur = if (x == to && v == 0.0) || d <= 0.0 { 0.0 } else { @ui.move_ms((x - to).abs() * d) }
    if last {
      end = from_at + dur
    }
    if d <= 0.0 {
      x = to
      v = 0.0
    } else {
      let (dx, dv) = @ui.move_path((x - to) * d, v * d, until - from_at, dur)
      x = to + dx / d
      v = dv / d
    }
  }
  (x, end)
}

///|
/// How far below its place it is drawn at moment `t`, `h` points tall: in points (what is said of it followed).
fn SheetRise::shown(self : SheetRise, h : Double, t : Double) -> Double {
  self.said.get() |> ignore
  let d = dmax(h, 0.0)
  self.at(d, t).0 * d
}

///|
/// When its last way is over, `h` points tall (what is said of it followed): its move's end, View::moved_by's.
fn SheetRise::ends(self : SheetRise, h : Double) -> Double {
  self.said.get() |> ignore
  self.at(dmax(h, 0.0), 0.0).1
}
