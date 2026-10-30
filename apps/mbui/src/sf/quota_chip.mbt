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
/// An allowance's windows (components.tsx QuotaBars compact, QuotaChip each, ProfilesNav.tsx Windows): a chip per
/// window, what is left in it, filled as far as that, its mark before it where `marked` (the web's default; a chat's
/// agents only with more than one), or `worded`, what is left said in words (每周剩余 78%: a profile's row, which has the
/// room); `small`, a lower line; `gap` apart; nothing while the core cannot say (`state` not ok) or there is no window.
/// Each says over it while it is pointed at what is left of it and when it fills again; `key` names them where the same
/// allowance shows more than once in a place (a list's rows: each its profile's).
pub fn quota_chips(
  c : @ui.Ctx,
  q : Json?,
  small? : Bool = false,
  marked? : Bool = true,
  worded? : Bool = false,
  gap? : Double = 8.0,
  key? : String = "quota",
) -> Unit {
  guard has_quota(q) else { return }
  let windows = match chip_field(q, "windows") {
    Some(Array(a)) => a
    _ => []
  }
  c.box(style=quota_chips_row.then(@ui.style(gap=room(gap))), fn() {
    for w in windows {
      quota_chip(c, Some(w), small~, marked~, worded~, key~)
    }
  })
  |> ignore
}

///|
/// One window of an allowance (components.tsx QuotaChip), or the one an agent is short of: what is left in it, filled
/// as far as that, its mark before it where `marked`, or with its name in words where `worded`; over it while it is
/// pointed at, `said` (what is left of it and when it fills again: quota_said), the chip `key`'s.
pub fn quota_chip(
  c : @ui.Ctx,
  w : Json?,
  small? : Bool = false,
  marked? : Bool = true,
  worded? : Bool = false,
  key? : String = "quota",
  said? : String,
) -> Unit {
  let left = chip_left(w)
  fill_chip(
    c,
    left,
    chip_str(w, "level"),
    if marked && !worded { chip_str(w, "mark") } else { "" },
    if worded { quota_left(w) } else { left.to_string() + "%" },
    small~,
    key=key + "/" + chip_str(w, "mark"),
    said=said.unwrap_or(quota_said(w)),
  )
}

///|
/// What is left of an allowance's window, in words (components.tsx quotaLeft: with its name where it has one), and
/// when it fills again on a line of its own (QuotaBars' tip).
pub fn quota_said(w : Json?) -> String {
  let said = quota_left(w)
  match chip_str(w, "refills") {
    "" => said
    refills => said + "\n" + refills
  }
}

///|
/// What is left of an allowance's window, in words: 每周剩余 78% (剩余 78% where it has no name).
fn quota_left(w : Json?) -> String {
  let label = chip_str(w, "label")
  let left = chip_left(w).to_string()
  if label != "" {
    t("web-main.quota.left", args=[("label", label), ("left", left)])
  } else {
    t("web-main.quota.leftAlone", args=[("left", left)])
  }
}

///|
/// A machine's CPU, memory or disk (components.tsx MeterChip): its mark and what is left, filled as far as is used;
/// `brief`, the figure alone with its unit's first letter, small (a station's row); `drop`, the turn it is left out of
/// a line short of room in (Ctx::box's), `keep` never squeezed there.
pub fn meter_chip(
  c : @ui.Ctx,
  m : Json?,
  brief? : Bool = false,
  drop? : Int = 0,
  keep? : Bool = false,
  key? : String = "meter",
) -> Unit {
  let unit = chip_str(m, "unit")
  let words = if brief && chip_str(m, "big") != "" {
    chip_str(m, "big") + (if unit == "%" || unit == "" { unit } else { unit.view(end_offset=1).to_string() })
  } else {
    chip_str(m, "remaining")
  }
  // what it is over it while pointed at (MeterChips' tip: its name, how much of how much, a note)
  let note = chip_str(m, "note")
  let said = match chip_str(m, "label") {
    "" => ""
    label => label + " " + chip_str(m, "value") + (if note != "" { " · " + note } else { "" })
  }
  fill_chip(
    c,
    100 - chip_left(m),
    chip_str(m, "level"),
    chip_str(m, "short"),
    words,
    small=brief,
    drop~,
    keep~,
    key=key + "/" + chip_str(m, "short"),
    said~,
  )
}

///|
/// A machine's CPU, memory and disk (components.tsx MeterChips), each a meter_chip, in one line that never goes on to
/// another, so what holds it is as high however narrow (a station's row in a narrow sidebar). Where it is short of
/// room, only what is still plenty is left out (level ok, grey: the last of them first); one running low (amber, red)
/// always stays, being what the line is there to show (MeterChips `alerts`: those running low).
pub fn meter_chips(c : @ui.Ctx, meters : Array[Json], brief? : Bool = false, key? : String = "meter") -> Unit {
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
      meter_chip(c, Some(m), brief~, drop=if ok { plenty - k + 1 } else { 0 }, keep=true, key~)
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
