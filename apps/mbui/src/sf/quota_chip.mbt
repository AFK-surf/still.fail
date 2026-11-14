// What the core says of an allowance and of a machine, as fill chips (MeterChip): one part
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
/// An allowance's windows (QuotaChip each): a chip per
/// window, what is left in it, filled as far as that, its mark before it where `marked` (the web's default; a chat's
/// agents only with more than one), or `worded`, its name and what is left in words, as a machine's chips say theirs
/// (每周剩 78%, as 内存剩 12.3 G: a profile's row, where a touch has no tip to say what W is); `small`, a lower line;
/// `gap` apart; nothing while the core cannot say (`state` not ok) or there is no window.
/// Worded, the line said one way for all its chips, the longest that fits the room it is given whole (Ctx::box one_of): a
/// phone's row has not the room for 5 小时剩 62%, 每周剩 95% and 每月剩 97%, so they say 5 小时 62%, 每周 95%…, then
/// 5H 62%, W 95%…, never one chip a way of its own nor one cut short. Where no line holds them (an account's windows
/// and its models' own weeks, five: each was cut to …), the account's a line by their names and its models' own a line
/// under it, each by its model, either going on in lines where it must (quota_chips_lines).
/// `lines` (not worded): on a line of its own, as wide as what holds it (under a row's words: a station's account),
/// where the line has not the room for its chips they go on so too, by their marks.
/// Each says over it while it is pointed at what is left of it and when it fills again; `key` names them where the same
/// allowance shows more than once in a place (a list's rows: each its profile's).
pub fn quota_chips(
  c : @ui.Ctx,
  q : Json?,
  small? : Bool = false,
  marked? : Bool = true,
  worded? : Bool = false,
  lines? : Bool = false,
  gap? : Double = 8.0,
  key? : String = "quota",
) -> Unit {
  guard has_quota(q) else { return }
  let windows = match chip_field(q, "windows") {
    Some(Array(a)) => a
    _ => []
  }
  let grouped = quota_parts(windows).iter().any(fn(p) { p.0 != "" })
  if !worded {
    if lines && grouped {
      quota_chips_lines(c, windows, small, gap, key, 2)
      return
    }
    let row = fn() {
      c.box(style=quota_chips_row.then(@ui.style(gap=room(gap))), fn() {
        for w in windows {
          quota_chip(c, Some(w), small~, marked~, key~)
        }
      })
      |> ignore
    }
    if lines {
      c.box(style=quota_chips_line, one_of=true, fn() {
        row()
        quota_chips_lines(c, windows, small, gap, key, 2)
      })
      |> ignore
    } else {
      row()
    }
    return
  }
  // (its ways, each shorter than the one before, the first that fits the line's room shown: Ctx::box one_of)
  c.box(style=quota_chips_line, one_of=true, fn() {
    for form in 0..<3 {
      c.box(style=quota_chips_row.then(@ui.style(gap=room(gap))), fn() {
        for w in windows {
          let (mark, words) = quota_worded(Some(w), form)
          fill_chip(
            c,
            chip_left(Some(w)),
            chip_str(Some(w), "level"),
            mark,
            words,
            small~,
            key=key + "/" + chip_str(Some(w), "mark") + "/" + form.to_string(),
            said=quota_said(Some(w)),
          )
        }
      })
      |> ignore
    }
    quota_chips_lines(c, windows, small, gap, key, 1)
  })
  |> ignore
}

///|
/// The group display name of a window when its label has a `" · "` suffix (such as `"5 小时 · Gemini"` or
/// `"每周 · Claude / GPT"`), or its `scope` otherwise.
fn quota_group_name(w : Json) -> String {
  let label = chip_str(Some(w), "label")
  match label.find(" · ") {
    Some(i) => label.clamped_view(start=i + 3).to_owned()
    None => chip_str(Some(w), "scope")
  }
}

///|
/// A window's mark within a group `group`: when `group` is already shown as the line's group heading, strip the
/// repeated `group + " "` prefix from the window's mark (`"Claude / GPT 5H"` -> `"5H"`).
fn quota_part_mark(group : String, w : Json?) -> String {
  let mark = chip_str(w, "mark")
  let prefix = group + " "
  if group != "" && mark.has_prefix(prefix) {
    mark.clamped_view(start=prefix.length()).to_owned()
  } else {
    mark
  }
}

///|
/// The lines an allowance's windows divide into when one line cannot hold them all: two windows stay together (and
/// wrap only if the line is narrower than a pair); more than two put the account's own windows on the first line (four
/// unscoped windows balanced two and two), each multi-window model pool (`scope` shared by more than one window, such as
/// Gemini 5H / Gemini W and Claude / GPT 5H / Claude / GPT W) on its own line with its group heading, and single-window
/// model caps (`Fable`, `Opus`, `Sonnet`) together on theirs.
fn quota_parts(windows : Array[Json]) -> Array[(String, Array[Json])] {
  if windows.length() <= 1 {
    return if windows.length() == 0 { [] } else { [("", windows)] }
  }
  let base : Array[Json] = []
  let counts : Map[String, Int] = Map([])
  let order : Array[String] = []
  for w in windows {
    let s = chip_str(Some(w), "scope")
    if s == "" {
      base.push(w)
    } else {
      let c = counts.get(s).unwrap_or(0)
      if c == 0 {
        order.push(s)
      }
      counts[s] = c + 1
    }
  }
  let parts : Array[(String, Array[Json])] = []
  if base.length() >= 2 && order.length() == 0 {
    let half = (base.length() + 1) / 2
    parts.push(("", base[:half].to_owned()))
    parts.push(("", base[half:].to_owned()))
  } else if base.length() > 0 {
    parts.push(("", base))
  }
  let single : Array[Json] = []
  for s in order {
    if counts.get(s).unwrap_or(0) > 1 {
      let group_wins = windows.filter(fn(w) { chip_str(Some(w), "scope") == s })
      parts.push((quota_group_name(group_wins[0]), group_wins))
    } else {
      for w in windows {
        if chip_str(Some(w), "scope") == s {
          single.push(w)
        }
      }
    }
  }
  if single.length() > 0 {
    parts.push(("", single))
  }
  parts
}

///|
/// An allowance's chips where no one line holds them (quota_chips' last way): the account's windows a line, each said
/// `account`'s way (quota_worded's: 1 its name and what is left, 5 小时 62%; 2 by its mark, where the line before was),
/// each multi-window model pool a line of its own with its group column on the left and short `[5H %] [W %]` capsules
/// on the right, and what single models have to themselves (`scope`) a line under it, each by its model (Fable 46%: a
/// model's name says whose it is, where W says little without a tip); a line going on in lines where even it has not
/// the room, every chip whole.
fn quota_chips_lines(c : @ui.Ctx, windows : Array[Json], small : Bool, gap : Double, key : String, account : Int) -> Unit {
  let parts = quota_parts(windows)
  let label_w = parts.fold(init=0.0, fn(m, p) {
    if p.0 == "" { m } else { dmax(m, c.words_across(p.0, nav_quota_group).ceil()) }
  })
  c.box(style=quota_chips_parts, fn() {
    for part in parts {
      c.box(style=quota_chips_part.then(@ui.style(gap=room(gap))), flow=part.0 == "", line_gap=quota_chips_part_lines, fn() {
        if part.0 != "" {
          c.box(style=@ui.style(w=Fixed(label_w)), fn() {
            c.text(part.0, style=nav_quota_group) |> ignore
          })
          |> ignore
        }
        let draw_chips = fn() {
          for w in part.1 {
            let form = if chip_str(Some(w), "scope") != "" { 2 } else { account }
            let (mark0, words) = quota_worded(Some(w), form)
            let mark = if part.0 != "" { quota_part_mark(part.0, Some(w)) } else { mark0 }
            fill_chip(
              c,
              chip_left(Some(w)),
              chip_str(Some(w), "level"),
              mark,
              words,
              small~,
              key=key + "/" + chip_str(Some(w), "mark") + "/lines",
              said=quota_said(Some(w)),
            )
          }
        }
        if part.0 != "" {
          c.box(style=quota_chips_part.then(@ui.style(gap=room(gap))), flow=true, line_gap=quota_chips_part_lines, draw_chips)
          |> ignore
        } else {
          draw_chips()
        }
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The lines of an allowance no one line holds: as wide as what holds them, a line under another as far as the lines
/// a line goes on in.
// kept across runs: a value (no field of it changes)
let quota_chips_parts : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let quota_chips_part : @ui.Style = @ui.css("row w=Full align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let quota_chips_part_lines : Double = 6.0

///|
// kept across runs: a value (no field of it changes)
let nav_quota_group : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, leading=L4, wrap=false)

///|
/// A sidebar row's allowance starts under the mark, in every row of every list (the user, 2026-11-10: 「全跟 logo
/// 对齐」, after rows of one list started some at the mark and some at the text). It keeps every window as a standard
/// marked capsule (`[mark %]`): all in one line when the provider's widest row fits, or wrapped into logical lines
/// (`quota_parts`) when a provider's windows are too wide or numerous for one line; multi-window model pools (`Gemini`,
/// `Claude / GPT`) align their pool name in a left column and their short `[5H %] [W %]` capsules on the right (the
/// user, 2026-11-13: 「按账号类型来搞，不要所有全用同一种」「相同供应商的账号用同一种就行」「感觉极端情况就应该多行」「感觉这
/// 里还是要分组」「方案 A：左组名列 + 右短胶囊对齐」). Every way stands from the start, its chips the same gap apart, never
/// spread to the row's ends (the user, 2026-11-10: 「怎么一会儿左对齐一会儿两端对齐」). Its nav_item gives it the whole
/// row as `foot` and says foot_capsule=fill_chip_small_h so the capsules are at the same inset from the row's foot.
/// `at`: where its row's list stands (its words' room: band_pad_in).
pub fn nav_quota_chips(
  c : @ui.Ctx,
  q : Json?,
  key? : String = "quota",
  at? : ListAt = Side,
  widest? : Double = 0.0,
) -> Unit {
  guard has_quota(q) else { return }
  let windows = match chip_field(q, "windows") {
    Some(Array(a)) => a
    _ => []
  }
  let inset = @ui.capsule_in(row_corner, fill_chip_small_h)
  let side = band_pad_in(at)
  // A capsule reaches the corner until it is past the outer corner's circle-equivalent radius.
  let clear = dmax(0.0, inset + fill_chip_small_h / 2.0 - side)
  let parts = quota_parts(windows)
  let label_w = parts.fold(init=0.0, fn(m, p) {
    if p.0 == "" { m } else { dmax(m, c.words_across(p.0, nav_quota_group).ceil()) }
  })
  let pad_y = dmax(0.0, (theme().chat_list.meta_h - fill_chip_small_h) / 2.0)
  let part_chip = fn(group : String, w : Json, chip_key : String) {
    let left = chip_left(Some(w))
    fill_chip(
      c,
      left,
      chip_str(Some(w), "level"),
      quota_part_mark(group, Some(w)),
      left.to_string() + "%",
      small=true,
      key=chip_key + "/" + chip_str(Some(w), "mark"),
      said=quota_said(Some(w)),
    )
  }
  c.box(style=quota_chips_line, one_of=true, fn() {
    // (as wide as its provider's widest needs, so a provider's rows take one way, not each its own)
    let line = dmax(widest, nav_quota_line(c, q)) + clear
    if label_w > 0.0 {
      c.box(
        style=@ui.style(w=Full, min_w=Fixed(line), ml=room(inset - side), pr=room(clear), my=room(pad_y), gap=S1),
        keep=true,
        fn() {
          for p, part in parts {
            c.box(style=quota_chips_part.then(@ui.style(gap=S1_5)), keep=true, fn() {
              if part.0 != "" {
                c.box(style=@ui.style(w=Fixed(label_w)), keep=true, fn() {
                  c.text(part.0, style=nav_quota_group) |> ignore
                }) |> ignore
              }
              c.box(style=quota_chips_row.then(@ui.style(gap=S1)), keep=true, fn() {
                for i, w in part.1 {
                  c.box(keep=true, fn() {
                    part_chip(part.0, w, key + "/grouped/" + p.to_string() + "/" + i.to_string())
                  }) |> ignore
                }
              }) |> ignore
            }) |> ignore
          }
        },
      ) |> ignore
    } else {
      c.box(style=@ui.style(row=true, min_w=Fixed(line), ml=room(inset - side), pr=room(clear), gap=S1), keep=true, fn() {
        for i in 0..<windows.length() {
          c.box(keep=true, fn() {
            quota_chip(c, Some(windows[i]), small=true, key=key + "/under/" + i.to_string())
          }) |> ignore
        }
      }) |> ignore
    }
    c.box(
      // (where one line cannot hold the provider's widest, wrap into logical lines of full marked chips, its first and
      // last lines at the same inset from the row's edges as a single line; grouped pools stack their group label above
      // their short capsules when the sidebar is too narrow for the side-by-side column)
      style=@ui.style(w=Full, ml=room(inset - side), mr=room(clear), my=room(pad_y), gap=S1),
      fn() {
        for p, part in parts {
          if part.0 != "" {
            c.box(style=@ui.style(w=Full, gap=S0_5), fn() {
              c.text(part.0, style=nav_quota_group) |> ignore
              c.box(style=quota_chips_part.then(@ui.style(gap=S1)), flow=true, line_gap=@ui.Space::S1.px(), fn() {
                for i, w in part.1 {
                  part_chip(part.0, w, key + "/lines/" + p.to_string() + "/" + i.to_string())
                }
              })
              |> ignore
            })
            |> ignore
          } else {
            c.box(style=quota_chips_part.then(@ui.style(gap=S1)), flow=true, line_gap=@ui.Space::S1.px(), fn() {
              for i, w in part.1 {
                quota_chip(c, Some(w), small=true, key=key + "/lines/" + p.to_string() + "/" + i.to_string())
              }
            })
            |> ignore
          }
        }
      },
    ) |> ignore
  }) |> ignore
}

///|
/// The room an allowance's full chips need in one line of a sidebar's row, as quota_chip says them (or for a
/// multi-window grouped allowance, the room its widest `[group_column + short_chips]` row needs): what a list
/// gives its rows as `widest` (nav_quota_chips), the most of them; 0 where it shows none.
pub fn nav_quota_line(c : @ui.Ctx, q : Json?) -> Double {
  guard has_quota(q) else { return 0.0 }
  let windows = match chip_field(q, "windows") {
    Some(Array(a)) => a
    _ => []
  }
  let parts = quota_parts(windows)
  let label_w = parts.fold(init=0.0, fn(m, p) {
    if p.0 == "" { m } else { dmax(m, c.words_across(p.0, nav_quota_group).ceil()) }
  })
  if label_w > 0.0 {
    return parts.fold(init=0.0, fn(most, p) {
      let mut sum = if p.0 == "" { 0.0 } else { label_w + @ui.Space::S1_5.px() }
      for i, w in p.1 {
        sum += fill_chip_wide(c, quota_part_mark(p.0, Some(w)), chip_left(Some(w)).to_string() + "%", small=true) +
          (if i > 0 { @ui.Space::S1.px() } else { 0.0 })
      }
      dmax(most, sum)
    })
  }
  let mut sum = 0.0
  for i, w in windows {
    sum += fill_chip_wide(c, chip_str(Some(w), "mark"), chip_left(Some(w)).to_string() + "%", small=true) +
      (if i > 0 { @ui.Space::S1.px() } else { 0.0 })
  }
  sum
}

///|
/// The ways a worded window says itself, each shorter than the one before: its name and what is left (每周剩 95%), its
/// name and the figure (每周 95%), its mark and the figure (W 95%).
fn quota_worded(w : Json?, form : Int) -> (String, String) {
  let left = chip_left(w).to_string()
  let name = match chip_str(w, "label") {
    "" => chip_str(w, "mark")
    label => label
  }
  match form {
    0 => (name, t("web-main.quota.figure", args=[("left", left)]))
    1 => (name, left + "%")
    _ => (chip_str(w, "mark"), left + "%")
  }
}

///|
/// One window of an allowance, or the one an agent is short of: what is left in it, filled
/// as far as that, its mark before it where `marked`; `compact` gives a small, unmarked figure less padding when the
/// mark is above it; over it while pointed at, `said` (what is left and when it fills again: quota_said), the chip
/// `key`'s.
pub fn quota_chip(
  c : @ui.Ctx,
  w : Json?,
  small? : Bool = false,
  compact? : Bool = false,
  marked? : Bool = true,
  key? : String = "quota",
  said? : String,
) -> Unit {
  let left = chip_left(w)
  fill_chip(
    c,
    left,
    chip_str(w, "level"),
    if marked { chip_str(w, "mark") } else { "" },
    left.to_string() + "%",
    small~,
    compact~,
    key=key + "/" + chip_str(w, "mark"),
    said=said.unwrap_or(quota_said(w)),
  )
}

///|
/// What is left of an allowance's window, in words, and
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
/// A machine's CPU, memory or disk: its mark and what is left, filled as far as is used;
/// `brief`, the figure alone with its unit's first letter, small (a station's row); `figure`, the same words at the
/// chip's own size (meter_line's shorter way); `drop`, the turn it is left out of a line short of room in (Ctx::box's),
/// `keep` never squeezed there.
pub fn meter_chip(
  c : @ui.Ctx,
  m : Json?,
  brief? : Bool = false,
  figure? : Bool = false,
  drop? : Int = 0,
  keep? : Bool = false,
  key? : String = "meter",
) -> Unit {
  let unit = chip_str(m, "unit")
  let words = if (brief || figure) && chip_str(m, "big") != "" {
    chip_str(m, "big") + (if unit == "%" || unit == "" { unit } else { unit.clamped_view(end=1).to_owned() })
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
/// A machine's CPU, memory and disk, each a meter_chip, in one line that never goes on to
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
/// A machine's chips in a line as wide as what holds it (a station's card, its peek), 8 apart, each whole: in words
/// where the line has the room for all of them (内存剩 9.2 G), else all by their figures (内存 9.2G), one way for all
/// of them (Ctx::box one_of), never one cut short with an ellipsis.
pub fn meter_line(c : @ui.Ctx, meters : Array[Json], key? : String = "meter") -> Unit {
  c.box(style=quota_chips_line, one_of=true, fn() {
    for figure in [false, true] {
      c.box(style=meter_line_way, fn() {
        for m in meters {
          meter_chip(c, Some(m), figure~, key=key + (if figure { "/figure" } else { "" }))
        }
      })
      |> ignore
    }
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let meter_line_way : @ui.Style = @ui.css("row gap=S2 align=ACenter")

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

///|
/// A worded line of them: as wide as what holds it, the room its ways are fitted to (Ctx::box one_of).
// kept across runs: a value (no field of it changes)
let quota_chips_line : @ui.Style = @ui.css("row w=Full align=ACenter")
