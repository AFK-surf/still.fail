// A card over what the pointer rests on (sfpages' hover, kit's hover_card, the web's Peeks.tsx Hover) as nodes of the
// window's tree: opened once a mouse's pointer has rested on what it is of hover_card_open_ms (carrying no press: one
// let go there rests from then), kept while the pointer is on that or on the card, closed hover_card_close_ms after it
// has left both; a finger, which rests on nothing, holds what it is of (its press's long press) to open it, and it stays
// till a press outside it and what it is of, or Escape. Closed at once by Escape, by a press outside both, and as what
// it is of takes input no more (said to take no press, leaving, under a modal layer: View::takes_input) or goes; kept
// open by the app (`held`), by none of these. Each
// of these at its cause's moment: a rest's end and a leave's a moment of the timeline said from the cause, the hand's
// state as it is then; nothing read of the hand or the clock as anything is made. Drawn in its layer (over all of the
// window) beside what it is of (View::beside: under it, at its start, 6 off), a small panel 320 wide (a tile: as wide as
// what it holds, 220 to 420), what it holds 10 in from its padding (or at it); grown out of that edge from .96 and
// clear over 160 ms as it comes, to .97 and clear over 90 ms as it goes, its ground first.

///|
/// How long a mouse's pointer rests on what a card is of before it opens, and how long after it has left both that
/// and the card it closes (Radix's HoverCard as Peeks.tsx sets it: sfpages' hover_open_ms, hover_close_ms).
pub let hover_card_open_ms : Double = 320.0

///|
pub let hover_card_close_ms : Double = 120.0

///|
/// How far a card is from what it is of.
let hover_card_offset : Double = 6.0

///|
/// How a card comes (faded in, grown from .96, eased out over 160 ms) and goes (to .97, eased to leave over 90 ms),
/// its ground first, then what it holds.
// kept across runs: a value (no field of it changes)
let hover_card_in : @motion.Trans = @motion.trans(fade=0.0, scale=0.96, spec=@motion.tween(hover_card_in_ms, ease=Out), ground_first=true)

///|
// kept across runs: a value (no field of it changes)
let hover_card_out : @motion.Trans = @motion.trans(fade=0.0, scale=0.97, spec=@motion.tween(hover_card_out_ms, ease=Leave), ground_first=true)

///|
let hover_card_in_ms : Double = 160.0

///|
pub let hover_card_out_ms : Double = 90.0

///|
/// What is done with a card (hover_card_node's) by what it is of or by what is in it: opened as a finger's hold opens
/// it (`hold`: till a press outside it and what it is of, or Escape), closed (`close`), whether it is open now
/// (`open`, followed), and the card while it is made (`card`, followed: what is opened from what it holds stands beside
/// it, `Node(card)`).
pub struct HoverHand {
  hold : () -> Unit
  close : () -> Unit
  open : () -> Bool
  card : () -> @view.View?
}

///|
/// A card holding what `body` makes, of node `anchor`, drawn in `layer` (the window's layer over all of it, a tip's:
/// its node as the card is first opened), opened and closed as the file's head says. `tile`: as wide as what it holds
/// (220 to 420), not 320; `padded`: what it holds 10 in from its padding, else at it (for rows to lie there); `side`,
/// `along`: where it stands of `anchor`; `along_offset`: that much further along its side (a card of words, its own
/// words starting where they start: sfpages' hover's `words_along`); `piece`: beside that piece of `anchor`, not all of
/// it (a link in its words: View::beside's). `held`: kept open meanwhile, whatever the pointer does, through a press
/// outside, Escape and its anchor taking no input (what was pressed in it opened something beside it the pointer goes
/// on to, a modal panel over its anchor, pressed in), as kit's hover_card's `held`; let go, as the pointer is then. A
/// row of it opening a menu beside it (submenu_row_node) holds it so while that is open, without being said.
/// `press`: what a press on `anchor` does, every input's (a tap, a click, Enter), `anchor` then taking presses;
/// `tapped`: what a finger's tap on `anchor` does in place of `press` (a station's card from the presenters, a finger
/// resting on nothing); said alone, `anchor` takes presses from a finger only, a mouse's press there what holds it's (a
/// bar dragging the window). A finger's long press on `anchor` opens the card whether it is pressed or not (kit's
/// hover_card: held_long of any trigger); one said neither answers a hold and nothing else (View::gesture's
/// hold alone): a tap, a click or a drag on it is what holds it's as ever (a row pressed to open, a bar dragged), the
/// finger its once held still that long; held by a finger, it is held to the room a press takes as anything pressed is
/// (t.audit()'s `room`): what it is put in gives it that room (a bar as high as a press's), not this part. Closed with the focus in
/// it, the focus goes back to `anchor` (where that takes it). `pointed`: a mouse's pointer on what it is of as that
/// says (a piece of `anchor`: a link of its words, @ui.runs_links' `pointed`), in place of on `anchor`, a press as it
/// goes down there not one outside; and nothing of the hand put on `anchor` (`press`, `tapped` and a finger's hold
/// none of its: what holds it says them, a finger's hold opening it by the hand's `hold`). `yields_to`: a mouse's pointer
/// on that or on what it holds (View::pointed_in) not on `anchor`, wherever it is within it: what beside `anchor`
/// reaches over it (a key's room over a tag, a press there that key's) answers there alone, its card the one that
/// opens (lit_within_node's). `owner`: what it is made
/// and let go with (a card of a piece of `anchor`, as that piece comes and goes), `anchor` where not said. The hand
/// the card is opened and closed by.
#callsite(autofill(loc))
pub fn hover_card_node(
  layer : TipLayer,
  anchor : @view.View,
  body : (@view.View) -> Unit,
  tile? : Bool = false,
  padded? : Bool = true,
  side? : @view.Side = Bottom,
  along? : @view.Along = Start,
  along_offset? : Double = 0.0,
  piece? : (Double, Double) -> (Double, Double, Double, Double)?,
  held? : () -> Bool = fn() { false },
  press? : () -> Unit,
  tapped? : () -> Unit,
  pointed? : () -> Bool,
  yields_to? : @view.View,
  owner? : @view.View,
  loc~ : SourceLoc,
) -> HoverHand {
  let owner = owner.unwrap_or(anchor)
  // (a row of it opening a menu beside it (submenu_row_node): its menu open, the card kept open as by `held`, the pointer
  // gone on to the menu, outside the card; as kit's hover_card was held by what opened from it)
  let row_open : @signals.Signal[@view.View?] = @signals.signal(None, same=same_view)
  let held = fn() { held() || row_open.get() is Some(_) }
  let open : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })
  // (opened by a finger's hold: stays till a press outside, Escape, or its anchor takes no input)
  let by_hand = Ref(false)
  // (the card's panel while it is made: what the pointer may be on)
  let card : @signals.Signal[@view.View?] = @signals.signal(None, same=fn(a, b) {
    match (a, b) {
      (None, None) => true
      (Some(x), Some(y)) => x.id() == y.id()
      _ => false
    }
  })
  // (how far it is in, and which way it goes: in as hover_card_in, out as hover_card_out)
  let way = EdgeWay::new(0.0)
  // (the moment pending: its rest's end while closed, its leave's while open)
  let due : Ref[(() -> Unit)?] = Ref(None)
  let stop_due = fn() {
    match due.val {
      Some(s) => s()
      None => ()
    }
    due.val = None
  }
  let made = Ref(false)
  let set_open : Ref[(Bool) -> Unit] = Ref(fn(_) {  })
  let make = fn() -> Bool {
    guard (layer.layer)() is Some(l) else { return false }
    let holder = l.box(made_for=loc, fn(h) { h.over(Is(true)) |> ignore }).lives_with(owner)
    holder.on_key(fn(k) {
      if k.code == @ui.key_escape && open.untracked() && !@signals.untracked(held) {
        (set_open.val)(false)
        true
      } else {
        false
      }
    })
    |> ignore
    // (a press anywhere in the window but on the card or on what it is of: closed as it goes down, the press what it
    // lands on's as ever)
    holder.reacts(fn() { holder.window_downs() }, at_start=false, fn(_) {
      // (kept open by the app: what the press lands on is what was opened from it)
      guard open.untracked() && !@signals.untracked(held) else { return }
      let (x, y) = holder.window_down_point()
      let on = fn(v : @view.View?) {
        match v {
          Some(p) =>
            match p.tree.target_at(x, y) {
              Pressed(id) | Dragged(id) => p.tree.holds(p.id(), id)
              _ => false
            }
          None => false
        }
      }
      let on_anchor = match pointed {
        Some(p) => @signals.untracked(p)
        None => on(Some(anchor))
      }
      if !(on(card.untracked()) || on_anchor) {
        (set_open.val)(false)
      }
    })
    holder.show(fn() { open.get() }, leave=hover_card_out_ms, fn(t) {
      card.set(Some(t))
      t.owns(fn() {
        match card.untracked() {
          Some(c) if c.id() == t.id() => card.set(None)
          _ => ()
        }
      })
      |> ignore
      let look = fn() {
        let p = way.shown(t)
        (if way.target() > 0.5 { hover_card_in } else { hover_card_out }).at(p, p)
      }
      small_panel_node(t)
      .beside(anchor.id(), side~, along~, offset=hover_card_offset, padding=8.0, piece?, along_offset~)
      .width(Is(if tile { None } else { Some(hover_card_px) }))
      .min_width(Is(if tile { Some(hover_tile_least_px) } else { None }))
      .max_width(By(fn() { Some(if tile { dmin(hover_tile_most_px, over_room(t).0 - 16.0) } else { over_room(t).0 - 16.0 }) }))
      .max_height(By(fn() { Some(dmax(0.0, over_room(t).1 - 16.0)) }))
      .alpha(By(fn() { look().alpha }))
      .scale(By(fn() { look().sx }), about=FromBeside)
      .says(Is(Some(@view.said(Group))))
      // (closed with the focus in it: back to what it is of, not to what had it as it opened)
      .focus_returns()
      .opened_by(@view.ByNode(anchor.id()))
      // (a press on it its own, the pointer on it on it, a press there nothing outside it: a ground, the library's panels'
      // (ground_node), the arrow over it; what it holds that is pressed, the hand as ever)
      |> ground_node
      |> ignore
      // (its submenu rows' one open: row_open; their menus made in the card's own layer over the window, not in what
      // it scrolls, which would cut them and what takes their presses)
      t.lends(panel_submenus_lent, row_open) |> ignore
      t.lends(submenu_layer_lent, holder) |> ignore
      t.box(fn(b) {
        b.alpha(By(fn() { look().words })) |> ignore
        b.scrolls(@view.Scroll::new(), slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(s) {
          s.box(fn(inner) {
            inner.fills_across(Is(true)) |> ignore
            if padded {
              let p = @ui.Space::px(S2_5)
              inner.padding(Is((p, p, p, p))).gap(Is(@ui.Space::px(S2))) |> ignore
            }
            body(inner)
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    true
  }
  set_open.val = fn(on : Bool) {
    stop_due()
    if !on {
      by_hand.val = false
    }
    if on == open.untracked() {
      return
    }
    if on && !made.val {
      made.val = make()
      guard made.val else { return }
    }
    if on {
      way.go(anchor, 1.0, hover_card_in_ms, ease=Out)
    } else {
      way.go(anchor, 0.0, hover_card_out_ms, ease=Leave)
    }
    open.set(on)
  }
  // (what decides it, as of each cause: a mouse's pointer on what it is of or on the card, a press held anywhere in
  // the window (View::window_held: one carried onto it from elsewhere, or one on it that is not its, a bar's dragging
  // the window, rests on nothing till it is let go, as kit's hover_card's `c.press().down`), whether it takes input, whether it is held open; one a mouse does not press (no `press`), by where the pointer is
  // within it, what a press there is for being another's)
  let takes = fn() { anchor.takes_input() }
  let state = fn() {
    let mouse = @ui.pointing() is Mouse
    let on_anchor = mouse &&
      (
        match pointed {
          Some(p) => p()
          None => anchor.pointed_in()
        }
      ) &&
      !yielded(yields_to)
    let on_card = mouse &&
      (
        match card.get() {
          Some(c) => c.pointed_in()
          None => false
        }
      )
    (on_anchor, on_card, anchor.window_held(), takes(), held())
  }
  let rests_was = Ref(false)
  owner.reacts(state, fn(s) {
    let (on_anchor, on_card, pressed, takes, keep) = s
    let at = owner.cause_at()
    let rests = on_anchor && !pressed
    let rests_now = rests && !rests_was.val
    rests_was.val = rests
    // (taking no input: closed, unless kept open by the app (what it opened, a modal panel beside it, over its anchor))
    if !takes && !keep {
      (set_open.val)(false)
      return
    }
    if open.untracked() {
      // (opened by a finger, or kept open: none of the pointer's to close it)
      if by_hand.val || keep || on_anchor || on_card {
        stop_due()
      } else if due.val is None {
        // (left both: closed a while from now, the pointer as it is then)
        due.val = Some(
          owner.at_moment(at + hover_card_close_ms, fn() {
            due.val = None
            let (a, c, _, _, k) = @signals.untracked(state)
            if !(a || c || k || by_hand.val) {
              (set_open.val)(false)
            }
          }),
        )
      }
    } else if rests_now {
      // (rested on a while from now: opened then, the pointer as it is then)
      stop_due()
      due.val = Some(
        owner.at_moment(at + hover_card_open_ms, fn() {
          due.val = None
          let (a, _, p, t, _) = @signals.untracked(state)
          if a && !p && t {
            (set_open.val)(true)
          }
        }),
      )
    } else if !rests {
      stop_due()
    }
  })
  let hold = fn() {
    (set_open.val)(true)
    by_hand.val = true
  }
  // (a finger held on it long_press_ms opens the card, on any anchor, as kit's hover_card's held_long)
  let on_held = fn(_d : @view.Drag) {
    if @ui.pointing() is Finger {
      hold()
    }
  }
  match (press, tapped) {
    // (its pointer said: nothing of the hand put on it, what holds it says that)
    _ if pointed is Some(_) => ()
    // (said neither: a hold and nothing else (View::gesture's hold alone): a press or a drag on it what holds it's as
    // ever (a row pressed to open, a bar dragged), the finger its once held still that long)
    (None, None) => anchor.points(Is(true)).gesture(@ui.touch_slop(), hold=(@ui.long_press_ms, on_held)) |> ignore
    _ => {
      // (pressed: a tap, a click or Enter does `press` (a finger's tap `tapped` where it is said); a mouse's long press
      // is still a click as it is let go on it, as an icon button's)
      let pressed = fn() {
        match press {
          Some(f) => f()
          None => ()
        }
      }
      let tap = fn() {
        match (tapped, @ui.pointing()) {
          (Some(f), Finger) => f()
          _ => pressed()
        }
      }
      let held_now = Ref(false)
      let on_it = fn(d : @view.Drag) { anchor.finger_target(d.wx, d.wy) }
      // (said `press`, every input's; said `tapped` alone, a finger's only: a mouse's press there what holds it's as
      // ever, a bar's dragging the window, as the current input changes)
      if press is Some(_) {
        anchor.presses(Is(true)).on_press(pressed) |> ignore
      } else {
        anchor.presses(Is(true)).points(By(fn() { @ui.pointing() is Mouse })).on_press(pressed) |> ignore
      }
      anchor.gesture(
        @ui.touch_slop(),
        tap=fn(d) { if on_it(d) { tap() } },
        hold=(
          @ui.long_press_ms,
          fn(d) {
            held_now.val = true
            on_held(d)
          },
        ),
        drag=fn(d) {
          if !held_now.val {
            if d.kind == Up && @ui.pointing() is Mouse && on_it(d) {
              pressed()
            }
          } else if d.kind == Up || d.kind == Off {
            held_now.val = false
            if d.kind == Up && @ui.pointing() is Mouse && on_it(d) {
              pressed()
            }
          }
        },
      )
      |> ignore
    }
  }
  // (let go: nothing of it left pending)
  owner.owns(fn() {
    stop_due()
    way.put(0.0)
  })
  |> ignore
  { hold, close: fn() { (set_open.val)(false) }, open: fn() { open.get() }, card: fn() { card.get() } }
}

///|
/// A card's width (sf's hover_card_w), and a tile's least and most (hover_tile_least, hover_tile_most), in points.
let hover_card_px : Double = match hover_card_w {
  Fixed(v) => v
  _ => 320.0
}

///|
let hover_tile_least_px : Double = match hover_tile_least {
  Fixed(v) => v
  _ => 220.0
}

///|
let hover_tile_most_px : Double = match hover_tile_most {
  Fixed(v) => v
  _ => 420.0
}
