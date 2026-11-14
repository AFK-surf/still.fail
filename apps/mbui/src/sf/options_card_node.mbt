// A card of options (options_card's) as a node of the window's tree, made once: each option a row to be pressed, its
// number in a disc, its label and what it leads to; the one being sent turning at its row's end, the one picked a
// check in its disc, the rest half there once none may be pressed, each over dur_ms from the moment that changed
// (a control answering); read-only with a check beside the one chosen where it is a card's history. Its measures,
// grounds and corners options_card's (parts.mbt), the same on every screen as there.

///|
/// A card of options in `parent` (options_card's, as nodes): `options` each its label, its detail, whether recommended,
/// as they are said; pressed while `enabled` and none is `busy` (the one being answered: a spinner at its row's end),
/// `on_pick` told its place as it is; `chosen` a check in its disc where its number was (answered). `wide`: under a
/// post, as wide as what it says (460 at least) and no wider than where it is, on the text at 5%; else as wide as where
/// it is, on the chips' ground. `history`: the original choices read-only and whole, a check beside the one chosen,
/// no ground or padding of its own (its presenter's). The node.
#callsite(autofill(loc))
pub fn options_card_node(
  parent : @view.View,
  options : () -> Array[(String, String, Bool)],
  enabled : () -> Bool,
  busy : () -> Int?,
  chosen? : () -> Int? = fn() { None },
  wide? : Bool = false,
  history? : Bool = false,
  on_pick? : (Int) -> Unit,
  loc~ : SourceLoc,
) -> @view.View {
  let free = fn() { enabled() && busy() is None && !history }
  parent.box(made_for=loc, fn(v) {
    // (in the wide frame as wide as what it says and 460 at least)
    style_node(v, fn() { if wide { options_room_start } else { options_room_across } })
    v.box(fn(card) {
      style_node(card, fn() {
        let ot = option_type()
        @ui.style(
          max_w=Fixed(options_most(options(), ot, wide)),
          p=room(if history { options_history_pad } else { options_card_pad }),
        )
      })
      // (as wide as where it is, up to what it says: the old box's w=Full under a column that sets it at its start)
      card
      .width_share(Is(1.0))
      .radius(Is(options_card_radius))
      .ground(By(fn() {
        let t = theme()
        if history {
          0L
        } else if wide {
          alpha(t.p.text, 0.05)
        } else {
          t.p.chip
        }
      }))
      |> ignore
      card.each(fn() { options().mapi(fn(i, o) { (i, o) }) }, fn(p) { p.0 }, fn(r, item) {
        // (its place and what it says read through its item, never kept: View::each's rows are their keys' readings)
        option_row_node(loc~, r, fn() { item.get().0 }, fn() { item.get().1 }, enabled, busy, chosen, free, history, on_pick)
      })
    })
    |> ignore
  })
}

///|
/// Option `i` of options_card_node's (`i` its place and `o` what it says, as they are) in `r`: a row pressed while `free` (its ground under a mouse,
/// its ripple), its number's disc (the accent where recommended; a check over the number once it is `chosen`, the
/// disc going to the accent with it), its label and detail; turning at its end while it is `busy`; half there once
/// none may be pressed but it; read-only with its check after it in a history.
#callsite(autofill(loc))
fn option_row_node(
  r : @view.View,
  i : () -> Int,
  o : () -> (String, String, Bool),
  enabled : () -> Bool,
  busy : () -> Int?,
  chosen : () -> Int?,
  free : () -> Bool,
  history : Bool,
  on_pick : ((Int) -> Unit)?,
  loc~ : SourceLoc,
) -> Unit {
  let fill = fn(row : @view.View) {
    style_node(row, fn() {
      let ot = option_type()
      @ui.style(
        row=true,
        w=Full,
        pl=room(ot.pad_in),
        pr=room(option_row_end),
        pt=room(ot.pad_in),
        pb=room(ot.pad_in),
        gap=room(option_row_gap),
        align=AStart,
      )
    })
    // (under a mouse's pointer its row's ground, in any layout)
    let hot = fn() { @ui.pointing() is Mouse && free() && lit_node(row) }
    row.radius(Is(option_row_corner)).ground(By(fn() { if hot() { theme().p.hover } else { 0L } })) |> ignore
    // (the one picked, answered: a check in its disc where its number was, on the accent; the rest half there, the
    // one being sent turning at its end: each over dur_ms from the moment it changed, as a control answers)
    let picked_here = fn() { !history && chosen() == Some(i()) }
    let there_of = fn() { if history || enabled() || chosen() == Some(i()) { 1.0 } else { 0.5 } }
    let there = EdgeWay::new(@signals.untracked(there_of))
    let ticked = EdgeWay::new(if @signals.untracked(picked_here) { 1.0 } else { 0.0 })
    let turning = EdgeWay::new(if @signals.untracked(fn() { busy() == Some(i()) }) { 1.0 } else { 0.0 })
    row.reacts(there_of, fn(to) { there.go(row, to, dur_ms) })
    row.reacts(picked_here, fn(on) { ticked.go(row, if on { 1.0 } else { 0.0 }, dur_ms) })
    row.reacts(fn() { busy() == Some(i()) }, fn(on) { turning.go(row, if on { 1.0 } else { 0.0 }, dur_ms) })
    row.alpha(By(fn() { there.shown(row) })) |> ignore
    // its number's disc
    row.box(fn(disc) {
      style_node(disc, fn() {
        let d = option_type().disc
        @ui.style(w=Fixed(d), h=Fixed(d), align=ACenter, justify=JCenter)
      })
      disc
      .radius(By(fn() { option_type().disc / 2.0 }))
      .ground(By(fn() {
        let t = theme()
        if o().2 {
          t.p.accent
        } else {
          mix_seen(t.p.accent, ticked.shown(disc), alpha(t.p.text, 0.09))
        }
      }))
      |> ignore
      let color = fn() { if o().2 { 0xFFFFFFFFL } else { theme().p.muted } }
      // (its number: an icon's for the first six, its words after)
      let number = disc.box(fn(n) {
        n.pick(fn() { i() < 6 }, fn(k, drawn) {
          if drawn {
            icon_node(k, "option-1", option_type().disc, By(color), name_now=fn() { "option-\{i() + 1}" }) |> ignore
          } else {
            k.box(fn(w) {
              w
              .words(By(fn() { "\{i() + 1}" }))
              .words_look(By(fn() { { ..@view.words_plain, size: theme().t.caption, weight: 600, wrap: false } }))
              .ink(By(color))
              |> ignore
            })
            |> ignore
          }
        })
      })
      number.alpha(By(fn() { 1.0 - ticked.shown(disc) })) |> ignore
      // (the check over the number while it is picked, and as it fades out after)
      disc.show(fn() { picked_here() || ticked.shown(disc) > 0.0 }, fn(mark) {
        // (over the disc, taking none of its room)
        mark.over(Is(true)) |> ignore
        style_node(mark, fn() { option_check_room })
        icon_node(mark, "check", option_type().disc * option_check_share, Is(0xFFFFFFFFL)) |> ignore
        mark.alpha(By(fn() { ticked.shown(mark) })) |> ignore
      })
    })
    |> ignore
    // its label and what it leads to
    row.box(fn(col) {
      style_node(col, fn() { option_words_room }, in_row=true)
      col.box(fn(w) {
        w
        .words(By(fn() { o().0 }))
        .words_look(By(fn() {
          let ot = option_type()
          { ..@view.words_plain, size: ot.label, weight: 500, line: ot.label_line }
        }))
        .ink(By(fn() { theme().p.text }))
        |> ignore
      })
      |> ignore
      col.show(fn() { o().1 != "" }, fn(d) {
        d.box(fn(w) {
          w
          .words(By(fn() { o().1 }))
          .words_look(By(fn() {
            let ot = option_type()
            { ..@view.words_plain, size: ot.detail, line: ot.detail_line }
          }))
          .ink(By(fn() { theme().p.muted }))
          |> ignore
        })
        |> ignore
      })
    })
    |> ignore
    // (turning over the row's end, in what it leaves at the end of the words: never narrowing them; and as it fades
    // out after)
    row.show(fn() { busy() == Some(i()) || turning.shown(row) > 0.0 }, fn(s) {
      // (over the row, taking none of its room nor a gap of it)
      s.over(Is(true)) |> ignore
      style_node(s, fn() { @ui.style(w=Full, align=AEnd, pt=room(option_type().pad_in), pr=room(option_row_end)) })
      s.alpha(By(fn() { turning.shown(s) })) |> ignore
      s.box(fn(h) {
        style_node(h, fn() { @ui.style(h=Fixed(option_type().label_line), justify=JCenter) })
        spinner_node(h, size=12.0) |> ignore
      })
      |> ignore
    })
    // (read-only: the one chosen checked after its words)
    if history {
      row.show(fn() { chosen() == Some(i()) }, fn(c) {
        style_node(c, fn() { @ui.style(h=Fixed(option_type().label_line), justify=JCenter) })
        icon_node(c, "check", 14.0, By(fn() { theme().p.accent })) |> ignore
      })
    }
  }
  match on_pick {
    Some(f) if !history =>
      // pressed while free: its ripple in the ink (SettingParts.kt options: ripple(color = C.ink)), read out a button
      // named as it is
      @headless.button(
        made_for=loc,
        r,
        fn() { o().0 },
        fn(_) { f(i()) },
        disabled=fn() { !free() },
        fn(row, b) {
          fill(row)
          let rippled = press_look(row, Is(option_row_corner), fn() { false }, ink=fn() { alpha(theme().p.text, 0.1) })
          let on_it = fn(d : @view.Drag) { row.finger_target(d.wx, d.wy) }
          row.gesture(
            @ui.touch_slop(),
            press=fn(d) { if !b.disabled() { (rippled.down)(d) } },
            tap=fn(d) {
              (rippled.tapped)(d)
              if on_it(d) {
                b.press()
              }
            },
            drag=fn(d) {
              if d.kind == Up && @ui.pointing() is Mouse && on_it(d) {
                b.press()
              }
            },
          )
          |> ignore
        },
      )
      |> ignore
    _ => r.box(made_for=loc, fill) |> ignore
  }
}

///|
/// The card's room under a post: as wide as what it says, at the column's start (options_card `wide`).
// kept across runs: a value (no field of it changes)
let options_room_start : @ui.Style = @ui.css("w=Full align=AStart")

///|
/// The card's room elsewhere: as wide as where it is.
// kept across runs: a value (no field of it changes)
let options_room_across : @ui.Style = @ui.css("w=Full align=AStretch")

///|
/// An option's words: what its row leaves after its disc.
// kept across runs: a value (no field of it changes)
let option_words_room : @ui.Style = @ui.css("w=Full")

///|
/// Between an option's disc and its words: 12 (the web's gap: 12px).
let option_row_gap : Double = 12.0

///|
/// A history's card: no room of its own round its rows (its presenter's).
let options_history_pad : Double = 0.0
