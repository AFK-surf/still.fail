// Laid out Medium with a sidebar to show (or beside the system's bars: rail_native.mbt), the wide frame's tape as nodes
// of the window's tree (mbui's view package; docs/retained.md, the way there's 4: from the outside in), made once:
//
//   - a row as wide as the tape, drawn moved as far as the tape has got (its offset, worked out as it is drawn from the
//     tape's move, committed once at its cause: tape_goes), holding the panels side by side as the tree lays them out:
//     the rail and the sidebar's column, the page's panel, a chat's side panel while it is open or closes (a node of its
//     own, `show`), each as wide as its binding says (tape_room: the window, the sidebar's width, the side panel's);
//   - in each panel, what it holds an old view (an island), built for the room the tree gives it; over each panel not in
//     use, a cover of the tree's: a tap or a secondary press brings it over, a drag across pulls it with the finger and,
//     let go, over or back, each at its event's moment (tape_cover);
//   - over the panels, an old view taking presses where it draws them alone: the edges dragged (tape_edge), and what a
//     screen reader says of the covers.
//
// The tape's move is a trajectory committed at its cause (tape_moves_from): where everything was at that moment,
// worked out of the trajectory before it alone (never of a state already changed), and where it all goes, as the
// change has it. What brings a panel over: a cover pressed, back, what is shown in the page (show_page, bring_page:
// wide.tape_ask), a chat's side panel opened or closed, another chat come, another place's sidebar (tape_settle, one
// change at its moment); the page waited for till the core has given what it shows or its wait is over (a moment of
// the tree's timeline: tape_goes.waited). What the window, an edge dragged or the keyboard does to where things go is no
// move: there at once. Its end is a moment of the timeline: the panel closed while in use let go there (side_left).
//
// Still the old frame's (the way there): what the panels hold (their islands); which page the page's panel draws while
// one put on top is waited for (Nav::shows_when, read as its island builds); the edges (their drags read as their island
// builds); what a screen reader says of the covers (an old view's, its press read as it builds); a passage picked
// bringing the page over (read as the page's island builds); back (said by the islands as they are built: the frame's in
// the island under all of it, tape_under).

///|
/// The tape's move, committed at its cause: its way (from 0 as it set out to 1), and of each thing it moves where it was
/// then and where it goes: how far the tape is moved (the one in use: not a finger's pull, added as it is drawn), how wide
/// the page's panel is, where the sidebar's column ends (where the page's panel starts on the tape), how far behind each
/// panel is (Side, Page, Panel: 0 in use, 1 its ground a step darker). Whether the tape is at rest (its way's end come),
/// what is due at that end; the side panel last open (closed while in use: shown, as it was, while the tape moves off it);
/// the page on top's stay there (each page come on top a stay of its own, by its number: a page come back to waits
/// anew) and the stay whose wait for what it shows is over (`most` past the moment it began), what is due then; the
/// finger pulling a panel over (where it went down across, the window's; where and when it was last, how fast it went
/// there, px/s).
priv struct TapeGoes {
  way : @motion.Way
  x : FixedArray[Double]
  page : FixedArray[Double]
  col : FixedArray[Double]
  behind : FixedArray[Double]
  rest : @signals.Signal[Bool]
  mut end_due : () -> Unit
  last_side : @signals.Signal[SideOf?]
  stay : @signals.Signal[(Int, Page?)]
  mut stays : Int
  waited : @signals.Signal[Int]
  mut wait_due : () -> Unit
  /// told as a move is committed or where things go is put (what works out where they are from it reads it)
  said : @signals.Signal[Int]
  mut pull_x0 : Double
  mut pull_last : (Double, Double)
  mut pull_v : Double
  /// the window's tree's node holding the tape, while it does (what its moves and its room are worked out of), and the
  /// side panel open on the page on top
  mut node : @view.View?
  /// its row, the sidebar's column, the page's panel's column, as made (for what is asked of them: tape_seen)
  parts : Array[@view.View]
  mut panel_of : () -> SideOf?
  /// whether the core has given what the page shows of a page (sfapp's pane_ready), waited for that long at most
  mut ready : (Page) -> Bool
  mut most : Double
}

///|
// kept across runs: put back as a run begins (tape_goes_reset)
let tape_goes : TapeGoes = {
  way: @motion.Way::new(1.0),
  x: FixedArray::make(2, 0.0),
  page: FixedArray::make(2, 0.0),
  col: FixedArray::make(2, 0.0),
  behind: FixedArray::make(6, 0.0),
  rest: @signals.signal(true, same=fn(a, b) { a == b }),
  end_due: fn() {  },
  last_side: @signals.signal(None, same=fn(a, b) { a == b }),
  stay: @signals.signal((-1, None), same=fn(a, b) { a == b }),
  stays: 0,
  waited: @signals.signal(-1, same=fn(a, b) { a == b }),
  wait_due: fn() {  },
  said: @signals.signal(0),
  pull_x0: 0.0,
  pull_last: (0.0, 0.0),
  pull_v: 0.0,
  node: None,
  parts: [],
  panel_of: fn() { None },
  ready: fn(_) { true },
  most: 0.0,
}

///|
fn tape_goes_reset() -> Unit {
  (tape_goes.end_due)()
  tape_goes.end_due = fn() {  }
  (tape_goes.wait_due)()
  tape_goes.wait_due = fn() {  }
  tape_goes.way.put(1.0)
  for a in [tape_goes.x, tape_goes.page, tape_goes.col, tape_goes.behind] {
    for i in 0..<a.length() {
      a[i] = 0.0
    }
  }
  tape_goes.rest.set(true)
  tape_goes.last_side.set(None)
  tape_goes.stay.set((-1, None))
  tape_goes.waited.set(-1)
  tape_goes.pull_x0 = 0.0
  tape_goes.pull_last = (0.0, 0.0)
  tape_goes.pull_v = 0.0
  tape_goes.node = None
  tape_goes.parts.clear()
  tape_goes.panel_of = fn() { None }
}

///|
/// Off the tape (the frame's, frame.mbt): nothing asked of it, no finger on it, its move over.
fn tape_off() -> Unit {
  wide.tape_ask.set(None)
  wide.tape_chat.set("")
  wide.tape_panel.set("")
  wide.tape_pull.set(None)
  wide.tape_drag.set(0.0)
  wide.tape_backing = false
  wide.tape_last_side = None
}

///|
/// Whether the signed-in frame with workspace `w` in view, a window `width` wide, is the tape (tape_view): laid out Medium
/// (or beside the system's bars: an iPhone Duo's, rail_native.mbt), with a sidebar to show (not a device waiting to be
/// confirmed in the workspace's safe mode, nor 连接 or 用量, a page across the pane).
pub fn tape_holds(src : Source, w : Workspace, width : Double) -> Bool {
  let gated = lit_place() != "settings" && @settings.lock_waiting(settings_core(src, w), w.id)
  let bare = place_bare(lit_place())
  !gated && !bare && (@sf.layout(width) is Medium || @sf.native_on() || @sf.native_able())
}

///|
/// What the tape is laid out by, a window `ww` by `wh`: what the window leaves beside the column of the system's glass
/// at its right (`tw`: @sf.side_clear) and that column (`under`: the last panel's ground goes on under it); the sidebar's
/// width and the column it is in (the rail's, the sidebar's, 6 from the window, 8 from the page: where the page's panel
/// starts), as tape_side_w has it now; the bars' room at the top and the foot; the panels' top and height (6 in from the
/// bars); the page's panel's width with the side panel open (`open`) or not, and the side panel's while it shows
/// (`shown`: open, or closing).
priv struct TapeRoom {
  tw : Double
  under : Double
  s : Double
  col : Double
  top : Double
  foot : Double
  panel_top : Double
  panel_h : Double
  main_to : Double
  panel_w : Double
}

///|
fn tape_room(ww : Double, wh : Double, open : Bool, shown : Bool) -> TapeRoom {
  let under = @sf.native_clear()
  let tw = ww - under
  let s = tape_side_w(tw, wide.side_w.get())
  // (on the tape apart from the page: its panel 6 in from the window's edge, 8 from the page's: tape_apart; as much
  // wider as its rail shows more there, its places in the panel's corners concentric with it: rail_open_tape)
  let col = rail_left() + s + bar_in_now() + bar_gap_now() + rail_more()
  let bars = @ui.system_bars()
  let top = bars.top
  // (down the side, the cards to the column's own foot, the home indicator's line under their ground: cards_foot; the
  // soft keyboard up, the window ends where it starts: the cards end on it from its first point on. A touch device's
  // navigation bar over the app, edge to edge, the cards' ground under it to the window's foot, what is in them clear
  // of it; not a window's on a computer, whose foot is its own; nor an iPhone Duo's upright, the system's tabs across
  // its foot in that room: the user, 2026-10-28)
  let edge = @sf.native_side() || (@sf.native_input() is Finger && !@sf.native_on())
  let foot = if @sf.native_side() {
    cards_foot
  } else if edge {
    dmin(bars.bottom, cards_foot + @ui.current().ime_inset())
  } else {
    bars.bottom
  }
  let page_h = dmax(0.0, wh - top - foot)
  let panel_top = top + bar_in_now()
  let panel_h = dmax(0.0, page_h - 2.0 * bar_in_now())
  let main_to = if open && !@sf.native_side() {
    dmax(0.0, tw - tape_shows_left() - tape_shows_right() - 2.0 * bar_gap_now())
  } else {
    // The system's trailing column already separates the active pane from what
    // peeks beside it. Do not reserve a second strip of chat width for details.
    tape_one_beside(tw, tape_shows_left())
  }
  let panel_w = if shown { tape_panel_w(tw) } else { 0.0 }
  { tw, under, s, col, top, foot, panel_top, panel_h, main_to, panel_w }
}

///|
/// The side panel shown on the tape: the one open on the page on top, else the one last open while it closes (what it
/// showed kept as it goes: side_leaving).
fn tape_shown_side() -> SideOf? {
  match (tape_goes.panel_of)() {
    Some(s) => Some(s)
    None =>
      match tape_goes.last_side.get() {
        Some(s) if side_leaving(s.key()) is Some(_) => Some(s)
        _ => None
      }
  }
}

///|
/// The tape's room now (tape_room), its window as the tree's frames give it.
fn tape_room_now() -> TapeRoom {
  let (ww, wh) = match tape_goes.node {
    Some(v) => v.window()
    None => (0.0, 0.0)
  }
  tape_room(ww, wh, (tape_goes.panel_of)() is Some(_), tape_shown_side() is Some(_))
}

///|
/// Where what the tape moves goes, as the state is now (`r`, the one in use): how far the tape is moved (no finger's
/// pull), how wide the page's panel is, where the sidebar's column ends, how far behind each panel is.
priv struct TapeTo {
  x : Double
  page : Double
  col : Double
  behind : FixedArray[Double]
} derive(Eq)

///|
fn tape_to_of(r : TapeRoom) -> TapeTo {
  let at = tape_at(r.tw, r.col, r.main_to, r.panel_w)
  let p = wide.tape_at.get()
  {
    x: tape_x_of(at, p),
    page: r.main_to,
    col: r.col,
    behind: [Side, Page, Panel].map(fn(q) { if q == p { 0.0 } else { 1.0 } }) |> FixedArray::from_array,
  }
}

///|
/// `a`'s value (from, to) as far as the tape's move has got at `t`.
fn tape_along(a : FixedArray[Double], i : Int, t : Double) -> Double {
  let from = a[2 * i]
  from + (a[2 * i + 1] - from) * tape_goes.way.value_at(t)
}

///|
/// Where the sidebar's column ends at `t`, how wide the page's panel is, how far behind panel `p` is, how far the tape
/// is moved (its move's alone: tape_x_at adds a finger's pull), as the move committed has them.
fn tape_col_at(t : Double) -> Double {
  tape_along(tape_goes.col, 0, t)
}

///|
fn tape_page_at(t : Double) -> Double {
  tape_along(tape_goes.page, 0, t)
}

///|
fn tape_behind_at(p : TapePane, t : Double) -> Double {
  tape_along(tape_goes.behind, tape_index(p), t)
}

///|
fn tape_index(p : TapePane) -> Int {
  match p {
    Side => 0
    Page => 1
    Panel => 2
  }
}

///|
/// Where the tape has each of its panels in use, as the state is now (tape_at): what a finger's pull is held within.
fn tape_ends(r : TapeRoom) -> (Double, Double, Double) {
  tape_at(r.tw, r.col, r.main_to, r.panel_w)
}

///|
/// How far the tape is moved at `t`: where its move committed has got, and as far as a finger pulls another over
/// (no further than where that has it in use).
fn tape_x_at(r : TapeRoom, t : Double) -> Double {
  let pulled = match wide.tape_pull.get() {
    Some(p) => tape_pull_clamp(tape_ends(r), p, wide.tape_drag.get())
    None => 0.0
  }
  tape_along(tape_goes.x, 0, t) + pulled
}

///|
/// The moment the tape is drawn at by what reads it in node `n`: the frame's while its move goes, else after it (at
/// rest: the clock read no more).
fn tape_drawn_at(n : @view.View) -> Double {
  tape_goes.said.get() |> ignore
  tape_goes.way.said()
  if tape_goes.way.goes_at(n.logic_at()) {
    n.drawn_at()
  } else {
    @double.infinity
  }
}

///|
/// The tape's move committed at `at` (its cause's moment) as `change` says (another brought over, a pull let go back,
/// another place's sidebar): each thing it moves from where the move before had it then (and the tape where a finger
/// had pulled it), to where the state `change` leaves has it; one way, as long as the furthest goes (a Move: @ui.move_ms),
/// its end a moment of the tree's timeline.
fn tape_moves_from(at : Double, change : () -> Unit) -> Unit {
  @signals.untracked(fn() {
    let x = tape_x_at(tape_room_now(), at)
    let page = tape_page_at(at)
    let col = tape_col_at(at)
    let behind = [tape_behind_at(Side, at), tape_behind_at(Page, at), tape_behind_at(Panel, at)]
    change()
    let to = tape_to_of(tape_room_now())
    tape_goes.x[0] = x
    tape_goes.x[1] = to.x
    tape_goes.page[0] = page
    tape_goes.page[1] = to.page
    tape_goes.col[0] = col
    tape_goes.col[1] = to.col
    for i in 0..<3 {
      tape_goes.behind[2 * i] = behind[i]
      tape_goes.behind[2 * i + 1] = to.behind[i]
    }
    let far = dmax(dmax((to.x - x).abs(), (to.page - page).abs()), (to.col - col).abs())
    tape_goes.way.put(0.0)
    tape_goes.way.go(1.0, @motion.move(over=far), at~)
    tape_said()
    tape_rest_at(tape_goes.way.ends_at())
  })
}

///|
/// Where what the tape moves goes changed with no cause of a move (the window, an edge dragged, the keyboard, a side
/// panel shown as its chat's view came): there at once, the move going on (if one goes) for the rest of it.
fn tape_put(to : TapeTo) -> Unit {
  let put = fn(a : FixedArray[Double], i : Int, v : Double) {
    if a[2 * i + 1] != v {
      a[2 * i] = v
      a[2 * i + 1] = v
    }
  }
  put(tape_goes.x, 0, to.x)
  put(tape_goes.page, 0, to.page)
  put(tape_goes.col, 0, to.col)
  for i in 0..<3 {
    put(tape_goes.behind, i, to.behind[i])
  }
  tape_said()
}

///|
/// What is committed of the tape's move told (tape_moves_from, tape_put).
fn tape_said() -> Unit {
  tape_goes.said.set(@signals.untracked(fn() { tape_goes.said.get() }) + 1)
}

///|
/// Where what the tape moves goes, as committed (tape_moves_from, tape_put).
fn tape_committed() -> TapeTo {
  {
    x: tape_goes.x[1],
    page: tape_goes.page[1],
    col: tape_goes.col[1],
    behind: [tape_goes.behind[1], tape_goes.behind[3], tape_goes.behind[5]] |> FixedArray::from_array,
  }
}

///|
/// The tape at rest from `end` (-1: at once, its move none: motion reduced), what is due then done then: the side panel
/// closed while in use let go once the tape is at the page (tape_left).
fn tape_rest_at(end : Double) -> Unit {
  (tape_goes.end_due)()
  tape_goes.end_due = fn() {  }
  match tape_goes.node {
    Some(n) if end >= 0.0 => {
      tape_goes.rest.set(false)
      tape_goes.end_due = n.at_moment(end, fn() {
        tape_goes.rest.set(true)
        tape_left()
      })
    }
    _ => {
      tape_goes.rest.set(true)
      tape_left()
    }
  }
}

///|
/// The side panel closed while in use, shown as it was while the tape moved off it, let go once the tape rests at the
/// page (panel.mbt side_left).
fn tape_left() -> Unit {
  @signals.untracked(fn() {
    if (tape_goes.panel_of)() is None && tape_goes.rest.get() && wide.tape_at.get() == Page {
      match tape_goes.last_side.get() {
        Some(s) => side_left(s.key())
        None => ()
      }
    }
  })
}

///|
/// `p` brought over at `at`, from where the tape is drawn then: no longer what a finger pulled (if it was), the field of
/// the page no more in use letting go of the keyboard (what shows of it takes nothing).
fn tape_to(p : TapePane, at : Double) -> Unit {
  tape_moves_from(at, fn() {
    wide.tape_at.set(p)
    if wide.tape_pull.get() == Some(p) {
      wide.tape_pull.set(None)
      wide.tape_drag.set(0.0)
      wide.tape_backing = false
    }
  })
  if p != Page {
    @ui.current().blur()
  }
}

///|
/// Whether the page on top shows what it is for: the core has given it (sfapp's pane_ready), or its stay's wait is over
/// (its moment on the tree's timeline: tape_goes.waited; a stay said for the page on top now, not one before it).
fn tape_page_ready() -> Bool {
  let top = app.nav.top()
  let (stay, on) = tape_goes.stay.get()
  (tape_goes.ready)(top) || (on == Some(top) && tape_goes.waited.get() == stay)
}

///|
/// What was asked of the tape (wide.tape_ask: a cover pressed, back, what is shown in the page), as of `at`: the page
/// once it has what was put on it (as a phone's page slides in once it has what it shows, not sliding over with the page
/// before on it), asked still till then; the side panel only while one is open. True where the tape set out.
fn tape_take_ask(at : Double) -> Bool {
  @signals.untracked(fn() {
    match wide.tape_ask.get() {
      Some(Page) if wide.tape_at.get() != Page && !tape_page_ready() => false
      Some(p) => {
        wide.tape_ask.set(None)
        if p != wide.tape_at.get() && !(p == Panel && (tape_goes.panel_of)() is None) {
          tape_to(p, at)
          true
        } else {
          false
        }
      }
      None => false
    }
  })
}

///|
/// The one pulled over let go at `at` (`v`: the finger's speed across as it left, px/s): brought over when pulled a
/// third of the way or flung toward it, else back to the one in use; on from where the finger left the tape.
fn tape_let_go(p : TapePane, v : Double, at : Double) -> Unit {
  @signals.untracked(fn() {
    let ends = tape_ends(tape_room_now())
    let span = tape_x_of(ends, p) - tape_x_of(ends, wide.tape_at.get())
    let k = if span == 0.0 { 0.0 } else { tape_pull_clamp(ends, p, wide.tape_drag.get()) / span }
    let fling = v.abs() > tape_fling
    let toward = fling && (v > 0.0) == (span > 0.0)
    let away = fling && !toward
    if toward || (k > tape_pull_over && !away) {
      tape_to(p, at)
    } else {
      tape_moves_from(at, fn() {
        wide.tape_pull.set(None)
        wide.tape_drag.set(0.0)
        wide.tape_backing = false
      })
    }
  })
}

///|
/// Back on the tape bringing `p` over (the one before the one in use: tape_back_to), step by step as the system's back
/// gesture goes (Ctx::follow_back): the tape in its hand from where it began, as a finger pulling `p` over has it,
/// moved as far as the gesture has come from the edge it came from; gone through, `p` brought over from there; let go,
/// over or back as a finger's is; called off, back where it was. Each at its step's moment. A back with no gesture (a
/// back key, ⌘[) brings `p` over at once.
fn tape_back(p : TapePane, step : @ui.BackStep) -> Unit {
  let now = @ui.tree_cause().unwrap_or(@ui.current().moment())
  match step {
    Began(x, t) =>
      if wide.tape_pull.get() is None {
        wide.tape_pull.set(Some(p))
        wide.tape_drag.set(0.0)
        wide.tape_backing = true
        wide.tape_back_x0 = x
        wide.tape_back_last = (x, t)
        wide.tape_back_v = 0.0
      }
    Moved(x, t) | LetGo(x, t) =>
      if wide.tape_backing {
        let (x1, t1) = wide.tape_back_last
        if t > t1 {
          wide.tape_back_v = (x - x1) / (t - t1) * 1000.0
        }
        wide.tape_back_last = (x, t)
        wide.tape_drag.set(x - wide.tape_back_x0)
        if step is LetGo(_, _) {
          wide.tape_backing = false
          match wide.tape_pull.get() {
            Some(q) => tape_let_go(q, wide.tape_back_v, t)
            None => ()
          }
        }
      }
    CalledOff =>
      if wide.tape_backing {
        tape_moves_from(now, fn() {
          wide.tape_pull.set(None)
          wide.tape_drag.set(0.0)
          wide.tape_backing = false
        })
      }
    Back =>
      if wide.tape_backing {
        match wide.tape_pull.get() {
          Some(q) => tape_to(q, now)
          None => ()
        }
      } else {
        wide.tape_ask.set(Some(p))
        tape_take_ask(now) |> ignore
      }
  }
}

///|
/// The tape as of `at`, one change at its moment (tape_view's reaction): what the shown chat's side panel and its chat
/// ask of it (the panel opened beside the same chat as before, its view come: the panel comes over; closed while in use,
/// the page; another chat shown while a panel was in use: its page, not the panel open in it: pengxiao, 2026-10-25, the
/// chat in the middle is what one comes to; a panel shown as its view comes is not one opened), then what was asked
/// taken (tape_take_ask); with no move set out, where things go changed by what is no cause of a move put there at once.
fn tape_settle(chat : String, open : String, known : Bool, at : Double) -> Unit {
  @signals.untracked(fn() {
    if wide.tape_ask.get() is None {
      if chat != wide.tape_chat.get() {
        if wide.tape_at.get() == Panel {
          wide.tape_ask.set(Some(Page))
        }
      } else if open != "" && open != wide.tape_panel.get() && wide.tape_panel.get() != tape_unknown && known {
        wide.tape_ask.set(Some(Panel))
      } else if open == "" && known && wide.tape_at.get() == Panel {
        wide.tape_ask.set(Some(Page))
      }
    }
    wide.tape_chat.set(chat)
    wide.tape_panel.set(if known { open } else { tape_unknown })
    if !tape_take_ask(at) {
      let to = tape_to_of(tape_room_now())
      if to != tape_committed() {
        tape_put(to)
      }
    }
  })
}

///|
/// The tape in node `v` (the signed-in shell's, filling the window: sfapp's taped_shell), in the workspace in view (its
/// file's head): the page brought over once `ready` says the core has given what it shows of the page put on it, `most`
/// ms after it was put there at the latest.
pub fn tape_view(v : @view.View, src : Source, ready~ : (Page) -> Bool, most~ : Double) -> Unit {
  wide.tape = true
  tape_goes.node = Some(v)
  tape_goes.ready = ready
  tape_goes.most = most
  tape_goes.panel_of = fn() {
    match @sfbase.workspace_in_view(src).0 {
      Some(w) => side_open_for(src, w, app.nav.top())
      None => None
    }
  }
  // (where the system lays out the app's tabs, its bars handed what the tape's frame has for them each frame it shows:
  // rail_native.mbt nav_frame)
  nav_held.val = fn() {
    if !@sf.native_able() {
      return None
    }
    match @sfbase.workspace_in_view(src) {
      (Some(w), all, _, _) => Some((src, w, all))
      _ => None
    }
  }
  // (at rest where it is in use as it is made: no move from wherever another frame left it)
  tape_goes.way.put(1.0)
  tape_goes.rest.set(true)
  tape_put(tape_to_of(tape_room_now()))
  v.owns(fn() {
    // (left for the frame off the tape, at this change's moment: the block closes from where the tape had it then, its
    // column and how far the tape was moved (with a finger's pull), pane_view)
    let at = v.cause_at()
    let r = tape_room_now()
    fold_goes.left_tape = Some(fold_look_tape(r.s, tape_col_at(at), r.top, r.foot, x=tape_x_at(r, at)))
    (tape_goes.end_due)()
    tape_goes.end_due = fn() {  }
    (tape_goes.wait_due)()
    tape_goes.wait_due = fn() {  }
    tape_goes.node = None
    tape_goes.parts.clear()
    tape_goes.panel_of = fn() { None }
    nav_held.val = fn() { None }
    wide.tape = false
  })
  |> ignore
  // each page come on top a stay of its own, waited for `most` ms at most from the moment it came: its wait over a
  // moment of the tree's timeline
  v.reacts(fn() { app.nav.top() }, fn(top) {
    (tape_goes.wait_due)()
    tape_goes.stays = tape_goes.stays + 1
    let stay = tape_goes.stays
    tape_goes.stay.set((stay, Some(top)))
    tape_goes.wait_due = v.at_moment(v.cause_at() + tape_goes.most, fn() { tape_goes.waited.set(stay) })
  })
  // the side panel last open, kept while it closes (tape_shown_side); let go once the tape rests at the page
  v.reacts(fn() { (tape_goes.panel_of)() }, fn(side) {
    match side {
      Some(_) => tape_goes.last_side.set(side)
      None => ()
    }
  })
  v.reacts(fn() { (panel_own.leaving.get(), (tape_goes.panel_of)() is None) }, fn(_) { tape_left() })
  // another place's sidebar at its own width (side_take: as it was left): the tape moved to it from where it is then, as
  // the sidebar is (brand.tsx moveSidebar, 380 ms); not the width the edge drags, which is followed at once
  let side_took = Ref(false)
  v.reacts(
    fn() {
      match @sfbase.workspace_in_view(src).0 {
        Some(w) if (src.topic)("prefs", {}).value is Some(_) => w.id + "\n" + side_group(src, w.id)
        _ => ""
      }
    },
    fn(key) {
      if key == "" {
        return
      }
      let take = fn() {
        match @sfbase.workspace_in_view(src).0 {
          Some(w) => side_take(src, w.id) |> ignore
          None => ()
        }
      }
      if side_took.val && !wide.edge_held.get() {
        tape_moves_from(v.cause_at(), take)
      } else {
        take()
      }
      side_took.val = true
    },
  )
  // the tape as each change has it, at its moment (tape_settle): what is asked of it, what the shown chat and its side
  // panel ask, the page waited for come or its wait over, where things go
  v.reacts(
    fn() {
      let chat = match app.nav.top() {
        Chat(r) | History(r, _, _) => chat_key(r)
        // a chat's detail asked as a page, on its way to its chat's side panel (main_page): still that chat, not another
        // come (its panel, opening, comes over)
        p if laid_beside(p) => @signals.untracked(fn() { wide.tape_chat.get() })
        _ => ""
      }
      let open = match (tape_goes.panel_of)() {
        Some(side) => side.key()
        None => ""
      }
      // (the chat shown has its view: what its side panel shows is known)
      let known = match app.nav.top() {
        Chat(r) | History(r, _, _) => (src.topic)("chat", chat_params(r)).value is Some(_)
        _ => true
      }
      (chat, open, known, wide.tape_ask.get(), tape_page_ready(), tape_to_of(tape_room_now()))
    },
    fn(said) {
      let (chat, open, known, _, _, _) = said
      tape_settle(chat, open, known, v.cause_at())
    },
  )
  v.box(fn(row) {
    tape_goes.parts.clear()
    tape_goes.parts.push(row)
    row
    .row(Is(true))
    .grow(Is(1.0))
    // (as wide as the tape: its panels side by side, the last on to the window's edge under the system's column)
    .width(By(fn() {
      let r = tape_room_now()
      let t = tape_drawn_at(row)
      Some(
        tape_col_at(t) +
        tape_page_at(t) +
        (if tape_shown_side() is Some(_) { bar_gap_now() + r.panel_w } else { 0.0 }) +
        r.under,
      )
    }))
    // moved as a whole, as far as the tape has got: nothing in it laid out again as it moves
    .offset(By(fn() {
      let r = tape_room_now()
      (tape_x_at(r, tape_drawn_at(row)), 0.0)
    }))
    |> ignore
    // the rail and the sidebar's column (its panel 6 in from the window's edge and the bars, 8 from the page's)
    row.box(fn(side) {
      tape_goes.parts.push(side)
      side.width(By(fn() { Some(tape_col_at(tape_drawn_at(side))) })) |> ignore
      @ui.old(side, fn(c) { tape_side_built(c, src) }, key=tape_island_key).over(Is(true)) |> ignore
      tape_cover(side, Side, fn() {
        let r = tape_room_now()
        let (_, wh) = side.window()
        (bar_in_now(), r.panel_top, bar_gap_now(), dmax(0.0, wh - r.panel_top - r.panel_h))
      })
    })
    |> ignore
    // the page's panel, 6 in from the bars
    row.box(fn(page) {
      tape_goes.parts.push(page)
      page
      .width(By(fn() {
        let r = tape_room_now()
        let w = tape_page_at(tape_drawn_at(page))
        Some(if tape_shown_side() is None { w + r.under } else { w })
      }))
      |> ignore
      tape_panel_box(page, 0.0, fn(pane) {
        @ui.old(pane, fn(c) { tape_page_built(c, src) }, key=tape_island_key).over(Is(true)) |> ignore
      })
      tape_cover(page, Page, fn() { tape_panel_room(page) })
    })
    |> ignore
    // a chat's side panel, 8 from the page's, while it is open or closes
    row.show(fn() { tape_shown_side() is Some(_) }, fn(panel) {
      panel
      .width(By(fn() {
        let r = tape_room_now()
        Some(bar_gap_now() + r.panel_w + r.under)
      }))
      |> ignore
      tape_panel_box(panel, bar_gap_now(), fn(pane) {
        @ui.old(pane, fn(c) { tape_panel_built(c, src) }, key=tape_island_key).over(Is(true)) |> ignore
      })
      tape_cover(panel, Panel, fn() {
        let (_, t, _, b) = tape_panel_room(panel)
        (bar_gap_now(), t, 0.0, b)
      })
    })
    // the edges dragged, and what a screen reader says of the covers: over the panels, taking presses where it draws
    // them alone
    @ui.old(row, fn(c) { tape_hand_built(c, src) }, key=tape_island_key).over(Is(true)) |> @ui.old_takes_own |> ignore
  })
  |> ignore
}

///|
/// What the window's tree has of the tape, for a test: who its shell, its row, the sidebar's column and the page's panel
/// are (made once: the same while the tape is shown), where the row is drawn across (how far the tape is moved, as the
/// tree has drawn it) and how wide the page's panel's column is laid out. None off the tape.
pub fn tape_seen() -> (Array[@view.NodeId], Double, Double)? {
  match tape_goes.node {
    Some(v) if tape_goes.parts.length() == 3 => {
      let ids = [v.id()] + tape_goes.parts.map(fn(p) { p.id() })
      let (x, _, _, _) = tape_goes.parts[0].rect()
      let (_, _, w, _) = tape_goes.parts[2].rect()
      Some((ids, x, w))
    }
    _ => None
  }
}

///|
/// Where the tape's move committed has the sidebar's column end at `t` (where the page's panel starts on the tape), for a
/// test.
pub fn tape_col_now(t : Double) -> Double {
  tape_col_at(t)
}

///|
/// Where the tape's move committed has the tape at `t` (its own: no finger's pull) and how wide it has the page's panel,
/// worked out of the move alone, for a test.
pub fn tape_along_at(t : Double) -> (Double, Double) {
  (tape_along(tape_goes.x, 0, t), tape_page_at(t))
}

///|
/// What the tape's panels' islands are built from besides what they read: the theme, whether a finger has the pointer.
fn tape_island_key() -> String {
  let t = @sf.theme()
  "\{t.p.bg} \{t.dark} \{pane_finger()} \{@ui.window_inset()}"
}

///|
/// The room round a panel in column `n` (the page's, the side panel's): from the bars, 6 in, and before it what is
/// between it and the one before (the side panel's 8 from the page's).
fn tape_panel_room(n : @view.View) -> (Double, Double, Double, Double) {
  let r = tape_room_now()
  let (_, wh) = n.window()
  (0.0, r.panel_top, 0.0, dmax(0.0, wh - r.panel_top - r.panel_h))
}

///|
/// The panel in column `n`, its room round it (tape_panel_room) and `before` it (the side panel's 8 from the page's),
/// what `held` puts in it.
fn tape_panel_box(n : @view.View, before : Double, held : (@view.View) -> Unit) -> Unit {
  n.box(fn(room) {
    room
    .over(Is(true))
    .padding(By(fn() {
      let (_, t, _, b) = tape_panel_room(n)
      (before, t, 0.0, b)
    }))
    |> ignore
    room.box(fn(pane) {
      pane.grow(Is(1.0)) |> ignore
      held(pane)
    })
    |> ignore
  })
  |> ignore
}

///|
/// Over panel `p` in column `n` (its room round it: `room`, at its left, top, right and bottom), while it is not in use
/// (or a finger pulls it over): a cover of the tree's drawing nothing, what is done on it its own, each at its event's
/// moment. A tap, or the pointer's secondary button (no menu of what it holds), brings it over; a drag across brings it
/// with the finger (the tape in the hand from there) and, let go, over or back. Drags on the one in use are its own.
fn tape_cover(n : @view.View, p : TapePane, room : () -> (Double, Double, Double, Double)) -> Unit {
  // (where and when the finger went down on it, the window's: where a pull begins from, however the cover moved since)
  let down : Ref[(Double, Double)?] = Ref(None)
  n.box(fn(holder) {
    holder.over(Is(true)).padding(By(room)) |> ignore
    holder.show(
      // (the one in use, at rest, takes what is done on it; moving to it, or pulled, still the cover's)
      fn() { tape_covered(p) },
      fn(cover) {
        cover
        .grow(Is(1.0))
        .on_menu(fn(m) {
          wide.tape_ask.set(Some(p))
          tape_take_ask(m.at) |> ignore
        })
        .gesture(
          @ui.press_slop,
          press=fn(d) { down.val = Some((d.wx, d.at)) },
          tap=fn(d) {
            down.val = None
            wide.tape_ask.set(Some(p))
            tape_take_ask(d.at) |> ignore
          },
          drag=fn(d) {
            tape_pulled(p, d, down.val.unwrap_or((d.wx, d.at)))
            if d.kind is (Up | Off) {
              down.val = None
            }
          },
        )
        |> ignore
      },
    )
  })
  |> ignore
}

///|
/// A finger dragging panel `p`'s cover across (tape_cover), gone down at `down` (where across the window, when): the tape
/// in its hand from where it went down (unless another is in its hand: back's), moved as far as it has come from there;
/// let go, over or back (tape_let_go), as fast as it went from where it was last told (from its down where none was);
/// called off, back.
fn tape_pulled(p : TapePane, d : @view.Drag, down : (Double, Double)) -> Unit {
  let begin = fn() {
    wide.tape_pull.set(Some(p))
    wide.tape_drag.set(0.0)
    tape_goes.pull_x0 = down.0
    tape_goes.pull_last = down
    tape_goes.pull_v = 0.0
  }
  let moved = fn() {
    let (x1, t1) = tape_goes.pull_last
    if d.at > t1 {
      tape_goes.pull_v = (d.wx - x1) / (d.at - t1) * 1000.0
    }
    tape_goes.pull_last = (d.wx, d.at)
    wide.tape_drag.set(tape_pull_clamp(tape_ends(tape_room_now()), p, d.wx - tape_goes.pull_x0))
  }
  let mine = wide.tape_pull.get() == Some(p) && !wide.tape_backing
  let free = p != wide.tape_at.get() && wide.tape_pull.get() is None
  match d.kind {
    Down =>
      if free {
        begin()
        moved()
      }
    Moved => if mine { moved() }
    Up =>
      // (let go past the slop with no move told before: its end alone, from where it went down)
      if mine || free {
        if free {
          begin()
        }
        moved()
        tape_let_go(p, tape_goes.pull_v, d.at)
      }
    Off =>
      if mine {
        tape_moves_from(d.at, fn() {
          wide.tape_pull.set(None)
          wide.tape_drag.set(0.0)
        })
      }
  }
}

///|
/// What panel `p`'s island draws (`body`, its answer): behind the one in use on the ground a step darker
/// (@sf.behind_ground), as far behind as the tape's move has got, what is on it as it is; in use, on its own, read out
/// (behind it, only drawn: what reads the widgets reads its cover).
fn tape_behind(c : @ui.Ctx, p : TapePane, body : () -> Unit) -> Unit {
  // (where the move has got as the island is built: built again each frame it goes, at rest no more)
  tape_goes.said.get() |> ignore
  tape_goes.way.said()
  let t = if tape_goes.way.goes_at(c.moment()) {
    tape_goes.way.get() |> ignore
    c.moment()
  } else {
    @double.infinity
  }
  let k = tape_behind_at(p, t)
  let shown = fn() {
    if wide.tape_at.get() == p {
      body()
    } else {
      c.hidden_from_semantics(body)
    }
  }
  if k <= 0.0 {
    shown()
  } else {
    @sf.with_ground(c, @sf.behind_ground(k~), shown)
  }
}

///|
/// Whether panel `p` has its cover over it (tape_cover): not in use, or on its way to be, or pulled over by a finger.
fn tape_covered(p : TapePane) -> Bool {
  wide.tape_at.get() != p || !tape_goes.rest.get() || wide.tape_pull.get() == Some(p)
}

///|
/// The rail and the sidebar's column on the tape (its island, as wide as the tree lays it out: the sidebar's width where
/// its move has got): the block apart from the page, in the workspace in view.
fn tape_side_built(c : @ui.Ctx, src : Source) -> Unit {
  let (now, all, _, _) = @sfbase.workspace_in_view(src)
  guard now is Some(w) else { return }
  let r = tape_room_now()
  let s = dmax(0.0, c.width - rail_left() - bar_in_now() - bar_gap_now() - rail_more())
  tape_behind(c, Side, fn() {
    dock(
      c,
      src,
      w,
      all,
      false,
      false,
      s,
      c.width,
      if side_full_height(false) {
        0.0
      } else {
        r.top
      },
      r.foot,
      0.0,
      held=true,
    )
  })
}

///|
/// The page's panel on the tape (its island, as the tree lays it out: as wide as the tape's move has got, 6 in from the
/// bars): the page's ground, its corners the tape's, a line round it; in it the stack's top drawn flat, a phone's
/// screen (page_in); what moves in it of its own (the composer) taking its place from its foot. A passage picked in it
/// while it is not in use brings it over.
fn tape_page_built(c : @ui.Ctx, src : Source) -> Unit {
  let (now, _, _, _) = @sfbase.workspace_in_view(src)
  guard now is Some(w) else { return }
  // (said by this build: image_item, video_item)
  @sfbase.held_pictures_waiting.val = false
  // a page opened in the pane shows once the core has given what it shows, the one before staying till then
  // (page_local_ms at most), as a page pushed on a phone slides in then (asked as its stack is drawn)
  app.nav.shows_when(fn() { (tape_goes.ready)(app.nav.top()) }, tape_goes.most)
  let r = tape_room_now()
  let side = tape_shown_side()
  let under = if side is None { r.under } else { 0.0 }
  let main_w = dmax(0.0, c.width - under)
  let page_id = c.id("main-page")
  let corners = tape_pane_corners(Page, side is Some(_))
  tape_behind(c, Page, fn() {
    // a right click in it: what is picked copied (context_menu.mbt)
    context_page(c, page_id)
    let pane = c.box(
      style=page_apart.then(@ui.style(w=Fixed(c.width), h=Fixed(c.height), radius=@sf.corners_radius(corners))),
      id=page_id,
      fn() {
        // (what is in it as wide as beside the system's column: `under` its ground alone, its right corners none of
        // what is in it, which ends where the column begins: beside_column)
        @sf.pane_round.val = Some(beside_column(corners, under))
        c.box(style=@ui.style(w=Fixed(main_w), h=Full), fn() {
          page_in(c, src, w, false, main_w, c.height, 0.0, pane_finger())
        })
        |> ignore
        @sf.pane_round.val = None
      },
    )
    // what moves in the page of its own (the composer) takes its place from the page's foot: the tape moving the page,
    // a keyboard making it shorter, move none of it (it goes with the page, at once)
    @motion.scope(c, pane, bottom=true)
  })
  // a passage of a message picked while the page is not in use (held where it shows beside the sidebar): the page comes
  // over with it, its bar there to be pressed (pengxiao, 2026-10-25: 引用 pressed there went to what showed of the page
  // and brought it over, quoting nothing). As it is picked, once: a passage left picked keeps nothing from being brought
  // over after (pengxiao, 2026-10-25: the sidebar pressed or pulled over went straight back)
  let pick = if @sfbase.pk.ts == "" { "" } else { "\{@sfbase.pk.ts}\u{1}\{@sfbase.pk.taken_at}" }
  if pick != "" &&
    pick != wide.tape_pick.get() &&
    wide.tape_at.get() != Page &&
    wide.tape_ask.get() is None &&
    wide.tape_pull.get() is None {
    wide.tape_ask.set(Some(Page))
  }
  wide.tape_pick.set(pick)
}

///|
/// A chat's side panel on the tape (its island, 6 in from the bars, 8 from the page's), closed while in use as it was
/// as the tape moves off it.
fn tape_panel_built(c : @ui.Ctx, src : Source) -> Unit {
  let (now, _, _, _) = @sfbase.workspace_in_view(src)
  guard now is Some(w) else { return }
  guard tape_shown_side() is Some(side) else { return }
  let leaving = (tape_goes.panel_of)() is None
  let r = tape_room_now()
  let panel_w = dmax(0.0, c.width - r.under)
  tape_behind(c, Panel, fn() {
    let corners = tape_pane_corners(Panel, true)
    c.box(style=page_apart.then(@ui.style(w=Fixed(c.width), h=Fixed(c.height), radius=@sf.corners_radius(corners))), fn() {
      @sf.pane_round.val = Some(beside_column(corners, r.under))
      c.box(style=@ui.style(w=Fixed(panel_w), h=Full), fn() {
        c.sized(panel_w, c.height, fn() { tape_side(c, src, w, side, leaving~) })
      })
      |> ignore
      @sf.pane_round.val = None
    })
    |> ignore
  })
}

///|
/// Over the tape's panels (its island, as wide as the tape, moved with it): the edge between the sidebar or the side
/// panel in use and the page beside it, dragged, its width (the sidebar's kept as the wide frame's is: side_follow),
/// the page beside it showing what it leaves; a press on it where it lies over what shows of the page, the page's. What a
/// screen reader says of the covers (what pressing one does), its press theirs.
fn tape_hand_built(c : @ui.Ctx, src : Source) -> Unit {
  let (now, _, _, _) = @sfbase.workspace_in_view(src)
  guard now is Some(w) else { return }
  let r = tape_room_now()
  tape_goes.said.get() |> ignore
  tape_goes.way.said()
  let t = if tape_goes.way.goes_at(c.moment()) {
    tape_goes.way.get() |> ignore
    c.moment()
  } else {
    @double.infinity
  }
  // (where it is on the tape: it is placed on the window's pixels, as an old view is (ui's old_frame), the tape moved
  // past them by what the rounding left; what it draws put back by that, where the tape has it)
  let x = tape_x_at(r, t)
  let o = x - (x * c.scale).round() / c.scale
  let col = tape_col_at(t)
  let main_w = tape_page_at(t)
  let side = tape_shown_side()
  // (what a screen reader says of each panel not in use: its cover's words, a press of it bringing it over)
  let panels = [(Side, bar_in_now(), col - bar_in_now() - bar_gap_now()), (Page, col, main_w)]
  if side is Some(_) {
    panels.push((Panel, col + main_w + bar_gap_now(), r.panel_w))
  }
  for panel in panels {
    let (p, left, width) = panel
    let left = left + o
    if width <= 0.0 || p == wide.tape_at.get() {
      continue
    }
    let id = c.id("tape/" + p.to_string())
    let b = c.box(style=@ui.style(w=Fixed(width), h=Fixed(r.panel_h)), left~, top=r.panel_top, fn() {  })
    c.semantics(b, Button, id~, label=tape_words(p))
    if c.clicked(id) {
      wide.tape_ask.set(Some(p))
    }
  }
  match wide.tape_at.get() {
    Side => {
      let id = c.id("tape/side-edge")
      let said = tape_edge(
        c,
        "tape/side-edge",
        @sf.t("web-pages.workspace.resizeSidebar"),
        col + o - bar_gap_now(),
        r.panel_top,
        r.panel_h,
        tape_side_w(r.tw, wide.side_w.get()),
        side_min,
        tape_side_most(r.tw),
        Right,
      )
      match said {
        Dragging(x) | Dropped(x) => wide.side_w.set(x)
        Twice => wide.side_w.set(side_default(side_group(src, w.id)))
        Pressed | Untouched => ()
      }
      wide.edge_held.set(c.pressed(id) || said is Dragging(_))
      // (a press on it where it lies over what shows of the page: the page's, as a press there would be without it)
      tape_edge_page(c, id, col, true)
    }
    Panel if side is Some(_) => {
      wide.edge_held.set(false)
      let id = c.id("tape/panel-edge")
      match
        tape_edge(
          c,
          "tape/panel-edge",
          @sf.t("web-pages.chat.resizePanel"),
          col + o + main_w,
          r.panel_top,
          r.panel_h,
          r.panel_w,
          dmin(panel_min, tape_one_beside(r.tw, tape_shows_left())),
          tape_one_beside(r.tw, tape_shows_left()),
          Left,
        ) {
        Dragging(x) | Dropped(x) => panel_own.width.set(Some(x))
        Twice => panel_own.width.set(None)
        Pressed | Untouched => ()
      }
      tape_edge_page(c, id, col + main_w, false)
    }
    _ => wide.edge_held.set(false)
  }
}

///|
/// A press let go on edge `id` (tape_edge) where it lies over what shows of the page (past `line` on the tape: at its
/// right for the sidebar's edge, `after`, at its left for the side panel's): the page brought over, as a press there
/// without it would (the edge takes that much of it for a finger's drag); in the gap the edge's own.
fn tape_edge_page(c : @ui.Ctx, id : Int, line : Double, after : Bool) -> Unit {
  if !c.clicked(id) {
    return
  }
  match c.drag_of(id) {
    Some(d) => {
      // (where it was pressed on the tape: the window's less how far the tape is moved then)
      let x = d.x - tape_x_at(tape_room_now(), c.moment())
      if (after && x >= line) || (!after && x < line) {
        wide.tape_ask.set(Some(Page))
      }
    }
    None => ()
  }
}

///|
/// The edge between the sidebar or the side panel in use on the tape and the page beside it, in the gap between the two
/// (`gap`: the gap's left on the tape; `top`, `h`: the panels'), the library's (its bar and its line, @sf.edge_look, in
/// the gap's middle; always shown to touch, which points at nothing, else while the pointer is on it), over the gap and
/// as far into each panel as @sf.edge_reach says (over what shows of the page there: the drags across that land on it
/// are its own, @sf.handle_drag): dragged, the width of the one in use, from `width` between `least` and `most` (its
/// `edge`: the sidebar's right, the side panel's left), the page beside it showing what it leaves; what was done with it
/// said (the second of two presses: its own width again; a press on the page's part is the page's, tape_edge_page).
fn tape_edge(
  c : @ui.Ctx,
  key : String,
  label : String,
  gap : Double,
  top : Double,
  h : Double,
  width : Double,
  least : Double,
  most : Double,
  edge : @ui.Side,
) -> @sf.Resized {
  let id = c.id(key)
  c.cursor(id, ResizeX)
  let said = @sf.handle_drag(c, id, width, min=least, max=most, edge~)
  let held = c.pressed(id) || said is Dragging(_)
  // (the gap `before` from its left and `after` from its right, the look in its middle)
  let (into_in, into_page) = @sf.edge_reach(bar_gap_now())
  let (before, after) = if edge is Left { (into_page, into_in) } else { (into_in, into_page) }
  let strip = c.box(
    style=@ui.style(
      row=true,
      w=Fixed(before + bar_gap_now() + after),
      h=Fixed(h),
      pl=@sf.room_of(before),
      pr=@sf.room_of(after),
      justify=JCenter,
    ),
    left=gap - before,
    top~,
    id~,
    fn() {
      @sf.edge_look(
        c,
        key,
        over=@sf.pointed_or_finger(c, false),
        on=c.lit(id) || c.focus_shown(id) || held,
        active=held,
      )
    },
  )
  c.semantics(strip, Separator, id~, label~)
  @sf.edge_tip(c, key, id, label, side=if edge is Left { Left } else { Right })
  said
}

///|
/// The frame under the tape's panels with workspace `w` in view (an island under all of it: sfapp's taped_shell): how
/// the lists take the hand, the sidebar of this place and workspace as it was left, the system's tabs where it has its
/// own bars, what the page's bars and the sidebar's parts work out from (as open, apart: on the tape nothing of them
/// moves), the chat landed on, the window's buttons' row, back (the panels' own taken first, said after it), the web
/// services' pages let go.
pub fn tape_under(c : @ui.Ctx, src : Source, w : Workspace, all : Array[Workspace]) -> Unit {
  c.mouse_drags_lists(pane_finger())
  wide.side_place = side_place()
  side_follow(c, src, w.id)
  wide.tape = true
  wide.crowded = false
  side_crowded()
  wide.peeking.set(false)
  native_frame(c, src, w, all)
  wide.closed.set(false)
  // (what the page's bars and the sidebar's parts work out from: open, apart, nothing of them moving on the tape)
  let r = tape_room_now()
  wide.bar_pl = bar_in
  wide.bar_ml = 0.0
  wide.bar_mr = 0.0
  wide.brand_h = side_brand_h(false, r.top)
  wide.band = 1.0
  wide.mark = 0.0
  land(src, w)
  // (beside the system's action at the column's foot, the cards' foot corners the one the composer stands concentric in
  // on its line: said before any of them is built; another than the last frame's, what was kept of them drawn anew, as
  // for the screen's corner: rail_native.mbt native_frame)
  if @sf.native_foot_set(r.panel_top + r.panel_h) {
    c.forget_parts()
  }
  // (the window's buttons' row under all of the frame, where nothing of it is: title_row)
  if @ui.window_inset() {
    title_row(c, "window-title-row", closed_bar_top)
  }
  // back (⌘[, a mouse's back button), the shell's one way (sfbase's go_back: wide_back here), after what the panels
  // take it for; on the tape the panel back brings over follows the system's back gesture as it goes (tape_back)
  if !app.menu {
    match tape_back_to() {
      Some(p) => c.follow_back(fn(step) { tape_back(p, step) })
      None =>
        match @sfbase.back_step() {
          Some(f) => c.take_back(f)
          None => ()
        }
    }
  }
  // the pages of web services' and visualizations' tabs closed, no longer drawn, let go (service_tab.mbt)
  sv_sweep(c, src)
}
