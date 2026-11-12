// A machine's CPU, memory and disk in brief, in one line that never goes on to another (meter_chips' `brief`, a
// station's row's) as nodes of the window's tree: what each says followed as it changes.

///|
/// A machine's CPU, memory and disk (`meters`, as they are now) in `parent`, each in brief (meter_chip's `brief`: the
/// figure alone with its unit's first letter, a small chip), 4 apart in a line as wide as what holds it that never goes
/// on to another: short of room, only what is still plenty is left out (level ok: the last of them first), one running
/// low (amber, red) staying while there is the room for it at its narrowest, each whole or not there; where even those
/// left have not the room, they give way to it, their figures cut short (meter_chip's `keep`), never to fewer than two
/// of its characters (meter_brief_wide); short even of that, the last of those running low left out as well, and
/// so on to none: nothing cut past knowing. What each is over it while it is pointed at (its name, how much of how
/// much, a note), in the layer of tips the panel it is in is lent (panel_tips_lent; none outside a panel).
#callsite(autofill(loc))
pub fn meter_chips_brief_node(parent : @view.View, meters : () -> Array[Json], loc~ : SourceLoc) -> Unit {
  let tips = parent.lent(panel_tips_lent)
  let low = fn(m : Json?) { chip_str(m, "level") is ("amber" | "red") }
  // (by the room it is given, those running low it has not the room for even at their narrowest left out, the last
  // first: what it shows of them is made by that room, View::by_room)
  let line = parent.by_room(loc~, fn(held, room) {
    let apart = @ui.Space::S1.px()
    // (short of the room for those running low whole, 4 apart: only then is any of them measured cut short, words
    // shaped only as the line comes to need them)
    let short = fn() {
      let mut used = 0.0
      let mut each = 0
      for m in meters() {
        if low(Some(m)) {
          used = used + (if each > 0 { apart } else { 0.0 }) + meter_brief_wide(held, m, cut=false)
          each += 1
        }
      }
      used > room.width() + 0.01
    }
    // (how many of those running low, from the first, it has the room for at their narrowest, 4 apart)
    let lows_held = fn() {
      let all = meters()
      let lows = all.filter(fn(x) { low(Some(x)) }).length()
      if !short() {
        return lows
      }
      let mut used = 0.0
      let mut n = 0
      for m in all {
        if low(Some(m)) {
          used = used + (if n > 0 { apart } else { 0.0 }) + meter_brief_wide(held, m, cut=true)
          if used <= room.width() + 0.01 {
            n += 1
          } else {
            break
          }
        }
      }
      n
    }
    held.box(fn(r) {
      style_node(r, fn() { meter_chips_line })
      // (its chips left out of it where it has not the room for all, as the old line's `drop`s)
      r.fits(Is(true)) |> ignore
      r.each(
        fn() {
          let all = meters()
          let lows = all.filter(fn(x) { low(Some(x)) }).length()
          let held_n = lows_held()
          if held_n >= lows {
            Array::makei(all.length(), fn(i) { i })
          } else {
            // (short even of those running low at their narrowest: the first of them it has the room for, alone)
            let kept : Array[Int] = []
            for i, m in all {
              if low(Some(m)) && kept.length() < held_n {
                kept.push(i)
              }
            }
            kept
          }
        },
        fn(i) { i },
        fn(c, i) {
          let k = i.untracked()
          let m = fn() { meters().get(k) }
          // (the k-th of those still plenty, from the first: the last to go first; one running low never)
          // (kept whole while what may be left out is (View::fit_whole, the old chip's `keep`); once nothing more may,
          // each gives way, its figure cut short (squeezes), never narrower than with two of its characters left)
          c
          .fit_whole(Is(true))
          .shrink(Is(1.0))
          .min_width(By(fn() {
            match m() {
              Some(x) if short() => Some(meter_brief_wide(c, x, cut=true))
              _ => Some(0.0)
            }
          }))
          |> ignore
          c.drops(By(fn() {
            let all = meters()
            if low(all.get(k)) {
              0
            } else {
              let plenty = all.filter(fn(x) { !low(Some(x)) }).length()
              let mut nth = 0
              for j in 0..=k {
                if j < all.length() && !low(all.get(j)) {
                  nth += 1
                }
              }
              plenty - nth + 1
            }
          }))
          |> ignore
          fill_chip_node(
            c,
            fn() { 100 - chip_left(m()) },
            fn() { chip_str(m(), "level") },
            fn() { chip_str(m(), "short") },
            fn() { meter_brief_figure(m()) },
            small=true,
            squeezes=true,
            said=fn() {
              let note = chip_str(m(), "note")
              match chip_str(m(), "label") {
                "" => ""
                label => label + " " + chip_str(m(), "value") + (if note != "" { " · " + note } else { "" })
              }
            },
            tips?,
          )
          |> ignore
        },
      )
    })
    |> ignore
  })
  style_node(line, fn() { meter_brief_room }, in_row=true)
}

///|
/// A meter's figure in brief (meter_chip's `brief`): its figure with its unit's first letter, else what is left.
fn meter_brief_figure(m : Json?) -> String {
  let unit = chip_str(m, "unit")
  if chip_str(m, "big") != "" {
    chip_str(m, "big") + (if unit == "%" || unit == "" { unit } else { unit.clamped_view(end=1).to_owned() })
  } else {
    chip_str(m, "remaining")
  }
}

///|
/// How wide meter `m`'s chip in brief is in node `v`'s tree (fill_chip_node `small`, squeezes), its words as they are
/// set (chip_text, the system's size of words applied), with what is round and between them (fill_chip_wide's): whole,
/// or (`cut`) as narrow as it may be, its mark whole and its figure whole or cut to its first meter_brief_kept
/// characters and an ellipsis, whichever is narrower.
fn meter_brief_wide(v : @view.View, m : Json, cut~ : Bool) -> Double {
  let mark = chip_str(Some(m), "short")
  let words = meter_brief_figure(Some(m))
  let look = @ui.style_words(chip_text)
  let size = node_sp(v, look.size)
  let wide = fn(s : String) { if s == "" { 0.0 } else { node_words_w(s, size, weight=look.weight) } }
  let chars = words.to_array()
  let figure = if cut && chars.length() > meter_brief_kept {
    dmin(wide(words), wide(String::from_array(chars[:meter_brief_kept].to_owned()) + "…"))
  } else {
    wide(words)
  }
  let side = @ui.Space::S1_25.px()
  let between = if mark == "" || chip_joined(mark, words) { 0.0 } else { @ui.Space::S1_25.px() }
  2.0 * side + wide(mark) + between + figure
}

///|
/// The line's room: as wide as what holds it.
// kept across runs: a value (no field of it changes)
let meter_brief_room : @ui.Style = @ui.css("w=Full")

///|
/// How many characters of a figure cut short must still show: as many as mbui's squeeze holds words cut short with an
/// ellipsis to (ui's squeeze_kept_chars, not mbui's to give), fewer read as squeezed out.
let meter_brief_kept : Int = 2
