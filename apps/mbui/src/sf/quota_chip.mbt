// What the core says of an allowance and of a machine, as fill chips (components.tsx QuotaChip, MeterChip): one part
// each, for every page that shows one (a profile's row and page, a station's row and peek, a chat's agents, the model
// control), drawn by fill_chip.

///|
/// Whether an allowance shows as chips (quota_chips draws any): the core can say it (`state` ok) and it has a window.
pub fn has_quota(q : Json?) -> Bool {
  chip_str(q, "state") == "ok" &&
  (match chip_field(q, "windows") {
    Some(Array(a)) => a.length() > 0
    _ => false
  })
}

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
  guard has_quota(q) else { return }
  let windows = match chip_field(q, "windows") {
    Some(Array(a)) => a
    _ => []
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
/// `brief`, the figure alone with its unit's first letter, small (a station's row); `drop`, the turn it is left out of
/// a line short of room in (Ctx::box's), `keep` never squeezed there.
pub fn meter_chip(c : @ui.Ctx, m : Json?, brief? : Bool = false, drop? : Int = 0, keep? : Bool = false) -> Unit {
  let unit = chip_str(m, "unit")
  let words = if brief && chip_str(m, "big") != "" {
    chip_str(m, "big") + (if unit == "%" || unit == "" { unit } else { unit.view(end_offset=1).to_string() })
  } else {
    chip_str(m, "remaining")
  }
  fill_chip(c, 100 - chip_left(m), chip_str(m, "level"), chip_str(m, "short"), words, small=brief, drop~, keep~)
}

///|
/// A machine's CPU, memory and disk (components.tsx MeterChips), each a meter_chip, in one line that never goes on to
/// another, so what holds it is as high however narrow (a station's row in a narrow sidebar). Where it is short of
/// room, only what is still plenty is left out (level ok, grey: the last of them first); one running low (amber, red)
/// always stays, being what the line is there to show (MeterChips `alerts`: those running low).
pub fn meter_chips(c : @ui.Ctx, meters : Array[Json], brief? : Bool = false) -> Unit {
  c.box(style=meter_chips_line, fn() {
    let low = fn(m : Json) { chip_str(Some(m), "level") is ("amber" | "red") }
    let plenty = meters.filter(fn(m) { !low(m) }).length()
    let mut k = 0
    for m in meters {
      let ok = !low(m)
      if ok {
        k += 1
      }
      // (the k-th of those still plenty, from the first: the last to go first; each whole or not there, never
      // squeezed with its figure cut)
      meter_chip(c, Some(m), brief~, drop=if ok { plenty - k + 1 } else { 0 }, keep=true)
    }
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let meter_chips_line : @ui.Style = @ui.css("row w=Full gap=S1 align=ACenter")

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
