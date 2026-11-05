// A card of options (parts.mbt's options_card) as nodes of the window's tree, made once: each a row to be pressed, its
// number in a disc (the one recommended in the accent), its label and what it leads to; half there when not enabled,
// a spinner on the one being answered, a check in the disc of the one picked; under a pointer its row's ground. Each
// change eased over dur_ms from its cause, as a control answers.

///|
/// The options card in `parent`: `options` (each its label, its detail, whether recommended), as they are now;
/// `enabled` whether they are to be pressed, `busy` the one being answered, `chosen` the one picked; `wide` as wide as
/// what it says (under a post, on the text at 5%), `history` read only with a check beside the one picked; `waits` the
/// ones not to be pressed yet, saying `waits_why` under them. `pick` told the one pressed (its place).
pub fn options_card_node(
  parent : @view.View,
  options : () -> Array[(String, String, Bool)],
  enabled : () -> Bool,
  busy : () -> Int?,
  pick : (Int) -> Unit,
  chosen? : () -> Int? = fn() { None },
  wide? : Bool = false,
  history? : Bool = false,
  waits? : () -> Array[Bool] = fn() { [] },
  waits_why? : () -> String = fn() { "" },
) -> @view.View {
  parent.box(fn(room) {
    // (as wide as where it is, the wide frame's at most as wide as what it says and 460 at least, at its start:
    // options_card's AStart and w=Full max_w)
    room.lines_up(Is(None)) |> ignore
    room.box(fn(card) {
      card
      .max_width(By(fn() {
        let why = if waits().contains(true) { waits_why() } else { "" }
        Some(options_most(options(), option_type(), wide, why))
      }))
      .radius(Is(options_card_radius))
      .padding(Is(if history { (0.0, 0.0, 0.0, 0.0) } else { (options_card_pad, options_card_pad, options_card_pad, options_card_pad) }))
      .ground(By(fn() {
        if history {
          0L
        } else if wide {
          alpha(theme().p.text, 0.05)
        } else {
          theme().p.chip
        }
      }))
      |> ignore
      card.each(fn() { options().mapi(fn(i, _) { i }) }, fn(i) { i }, fn(row, i) {
        let i = @signals.untracked(fn() { i.get() })
        option_row_node(row, i, options, enabled, busy, chosen, history, waits, waits_why, pick)
      })
    })
    |> ignore
  })
}

///|
/// Option `i` of an options card (options_card_node's) in `row`.
fn option_row_node(
  row : @view.View,
  i : Int,
  options : () -> Array[(String, String, Bool)],
  enabled : () -> Bool,
  busy : () -> Int?,
  chosen : () -> Int?,
  history : Bool,
  waits : () -> Array[Bool],
  waits_why : () -> String,
  pick : (Int) -> Unit,
) -> Unit {
  let o = fn() { options().get(i).unwrap_or(("", "", false)) }
  let waiting = fn() { waits().get(i) == Some(true) }
  let free = fn() { enabled() && busy() is None && !history && !waiting() }
  let ot = fn() { option_type() }
  // (each eased over dur_ms from what changes it: half there not enabled, the check in the one picked, the one being
  // sent turning, one that waits faded)
  let there = EdgeWay::new(1.0)
  let ticked = EdgeWay::new(0.0)
  let turning = EdgeWay::new(0.0)
  let woken = EdgeWay::new(1.0)
  row.reacts(fn() { history || enabled() || chosen() == Some(i) }, fn(on) { there.go(row, if on { 1.0 } else { 0.5 }, dur_ms) })
  row.reacts(fn() { !history && chosen() == Some(i) }, fn(on) { ticked.go(row, if on { 1.0 } else { 0.0 }, dur_ms) })
  row.reacts(fn() { busy() == Some(i) }, fn(on) { turning.go(row, if on { 1.0 } else { 0.0 }, dur_ms) })
  row.reacts(waiting, fn(on) { woken.go(row, if on { 0.5 } else { 1.0 }, dur_ms) })
  row
  .row(Is(true))
  .gap(Is(12.0))
  .lines_up(Is(Some(Start)))
  .padding(By(fn() {
    let t = ot()
    (t.pad_in, t.pad_in, option_row_end, t.pad_in)
  }))
  .radius(Is(option_row_corner))
  .ground(By(fn() { if @ui.pointing() is Mouse && free() && row.pointed() { theme().p.hover } else { 0L } }))
  .alpha(By(fn() { there.shown(row) }))
  // (read out by the words in it, in order, as main's options_card's button is: its number where it is words, past
  // the sixth; its name; its line under it; why it waits, where it does)
  .says(By(fn() {
    let (label, detail, _) = o()
    let words = if i < 6 { [] } else { ["\{i + 1}"] }
    words.push(label)
    if detail != "" { words.push(detail) }
    if waiting() { words.push(waits_why()) }
    Some(@view.said(Button, label=words.join(" ")))
  }))
  |> ignore
  presses_node(row, fn() { if free() { pick(i) } }, on=free)
  // (its number in a disc, the one recommended in the accent; picked, a check in its place)
  row.box(fn(disc) {
    disc
    .width(By(fn() { Some(ot().disc) }))
    .height(By(fn() { Some(ot().disc) }))
    .radius(By(fn() { ot().disc / 2.0 }))
    .lies_along(Is(Middle))
    .lines_up(Is(Some(Middle)))
    .ground(By(fn() {
      let t = theme()
      if o().2 { t.p.accent } else { mix_seen(t.p.accent, ticked.shown(disc), alpha(t.p.text, 0.09)) }
    }))
    .alpha(By(fn() { woken.shown(disc) }))
    |> ignore
    let ink : @view.Live[Int64] = By(fn() { if o().2 { 0xFFFFFFFFL } else { theme().p.muted } })
    disc.box(fn(n) {
      n.alpha(By(fn() { 1.0 - ticked.shown(n) })) |> ignore
      if i < 6 {
        icon_node(n, "option-\{i + 1}", @signals.untracked(fn() { ot().disc }), ink) |> ignore
      } else {
        n
        .words(Is("\{i + 1}"))
        .words_look(By(fn() { { ..@view.words_plain, size: theme().t.caption, weight: 600, wrap: false } }))
        .ink(ink)
        |> ignore
      }
    })
    |> ignore
    disc.box(fn(check) {
      check
      .over(Is(true))
      .lies_along(Is(Middle))
      .lines_up(Is(Some(Middle)))
      .alpha(By(fn() { ticked.shown(check) }))
      |> ignore
      icon_node(check, "check", @signals.untracked(fn() { ot().disc * option_check_share }), Is(0xFFFFFFFFL)) |> ignore
    })
    |> ignore
  })
  |> ignore
  // (its label and what it leads to; one that waits, why under them)
  row.box(fn(words) {
    words.grow(Is(1.0)).basis(Is(Some(0.0))).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    words.box(fn(w) {
      w.alpha(By(fn() { woken.shown(w) })) |> ignore
      w.box(fn(l) {
        l
        .words(By(fn() { o().0 }))
        .words_look(By(fn() { { ..@view.words_plain, size: ot().label, weight: 500, line: ot().label_line } }))
        .ink(By(fn() { theme().p.text }))
        |> ignore
      })
      |> ignore
      w.show(fn() { o().1 != "" }, fn(d) {
        d
        .words(By(fn() { o().1 }))
        .words_look(By(fn() { { ..@view.words_plain, size: ot().detail, weight: 400, line: ot().detail_line } }))
        .ink(By(fn() { theme().p.muted }))
        |> ignore
      })
    })
    |> ignore
    words.show(waiting, fn(why) {
      why
      .words(By(waits_why))
      .words_look(By(fn() { @ui.style_words(option_waits) }))
      .ink(By(fn() { @ui.style_ink(option_waits) }))
      |> ignore
    })
  })
  |> ignore
  // (the one being sent turning at its end, over what the words leave there)
  row.show(fn() { busy() == Some(i) || turning.shown(row) > 0.0 }, fn(s) {
    s
    .over(Is(true))
    .lines_up(Is(Some(End)))
    .padding(By(fn() { (0.0, ot().pad_in, option_row_end, 0.0) }))
    .alpha(By(fn() { turning.shown(s) }))
    |> ignore
    s.box(fn(at) {
      at.height(By(fn() { Some(ot().label_line) })).lies_along(Is(Middle)) |> ignore
      spinner_node(at, size=12.0) |> ignore
    })
    |> ignore
  })
  // (read only: a check beside the one picked)
  if history {
    row.show(fn() { chosen() == Some(i) }, fn(c) {
      c.height(By(fn() { Some(ot().label_line) })).lies_along(Is(Middle)) |> ignore
      icon_node(c, "check", 14.0, By(fn() { theme().p.accent })) |> ignore
    })
  }
}
