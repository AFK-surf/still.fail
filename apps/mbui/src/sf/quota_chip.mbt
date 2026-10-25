// What the core says of an allowance and of a machine, as fill chips (components.tsx QuotaChip, MeterChip): one part
// each, for every page that shows one (a profile's row and page, a station's row and peek, a chat's agents, the model
// control), drawn by fill_chip.

///|
/// An allowance's windows (components.tsx QuotaChip each, ProfilesNav.tsx Windows): a chip per window, what is left in
/// it, filled as far as that, its mark before it where `marked` (the web's default; a chat's agents only with more
/// than one); `small`, a lower line; `gap` apart; nothing while the core cannot say (`state` not ok) or there is no
/// window. `tip`: told each one's box (its id) and window, for words over it while it is pointed at.
pub fn quota_chips(
  c : @ui.Ctx,
  q : Json?,
  small? : Bool = false,
  marked? : Bool = true,
  gap? : Double = 8.0,
  tip? : (Int, Json) -> Unit,
) -> Unit {
  if chip_str(q, "state") != "ok" {
    return
  }
  let windows = match chip_field(q, "windows") {
    Some(Array(a)) => a
    _ => []
  }
  if windows.length() == 0 {
    return
  }
  c.box(style=quota_chips_row.then(@ui.style(gap=room(gap))), fn() {
    for w in windows {
      let wv = Some(w)
      let left = chip_left(wv)
      let chip = fn() {
        fill_chip(c, left, chip_str(wv, "level"), if marked { chip_str(wv, "mark") } else { "" }, left.to_string() + "%", small~)
      }
      match tip {
        Some(f) => {
          let id = c.id("quota-chip/" + chip_str(wv, "mark"))
          c.box(id~, taps=false, chip) |> ignore
          f(id, w)
        }
        None => chip()
      }
    }
  })
  |> ignore
}

///|
/// A machine's CPU, memory or disk (components.tsx MeterChip): its mark and what is left, filled as far as is used;
/// `brief`, the figure alone with its unit's first letter, small (a station's row).
pub fn meter_chip(c : @ui.Ctx, m : Json?, brief? : Bool = false) -> Unit {
  let unit = chip_str(m, "unit")
  let words = if brief && chip_str(m, "big") != "" {
    chip_str(m, "big") + (if unit == "%" || unit == "" { unit } else { unit.view(end_offset=1).to_string() })
  } else {
    chip_str(m, "remaining")
  }
  fill_chip(c, 100 - chip_left(m), chip_str(m, "level"), chip_str(m, "short"), words, small=brief)
}

///|
fn chip_field(v : Json?, key : String) -> Json? {
  match v {
    Some(Object(o)) => o.get(key)
    _ => None
  }
}

///|
fn chip_str(v : Json?, key : String) -> String {
  match chip_field(v, key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
/// What is left (0–100) of a window or a meter (`left`).
fn chip_left(v : Json?) -> Int {
  let n = match chip_field(v, "left") {
    Some(Number(x, ..)) => x.to_int()
    _ => 0
  }
  if n < 0 {
    0
  } else if n > 100 {
    100
  } else {
    n
  }
}

///|
/// The chips in a line, in its middle.
// kept across runs: a value (no field of it changes)
let quota_chips_row : @ui.Style = @ui.css("row align=ACenter")
