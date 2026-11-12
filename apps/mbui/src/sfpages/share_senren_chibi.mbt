// 千恋＊万花's looks (share_senren.mbt): the chibi ones (Ciallo's salute, 芳乃's dog ears, 丛雨's parfait, 小春's capsule
// toys, all six) and the heroines together (the festival's photo, the sweets party, after school). Each is its mockup
// (senren/cards/<mockup>.html) in boxes, words, pictures and a few shapes: what the mockups turned a few degrees
// (stickers, notes, a stamp) stands straight; a text's edge (-webkit-text-stroke) is its words drawn round them; a
// gradient is its middle colour.

// ── what this file's looks share ─────────────────────────────────────────

///|
/// A hard shadow under a sticker or a bubble, as the mockups' `0 3px 0`: this far down, not blurred.
let sb_lift : Double = 3.0

///|
let sb_sharp : Double = 0.0

///|
/// The eight ways round words their edge is drawn (sb_outlined), each as far out.
// kept across runs: a table, never written
let sb_round : Array[(Double, Double)] = [
  (1.0, 0.0),
  (0.71, 0.71),
  (0.0, 1.0),
  (-0.71, 0.71),
  (-1.0, 0.0),
  (-0.71, -0.71),
  (0.0, -1.0),
  (0.71, -0.71),
]

///|
/// Words with an edge round them, as the mockups' -webkit-text-stroke (which words have not): the words in `edge`'s
/// colour eight times `r` out round them, under that the same `drop` lower in `shade`'s (their text-shadow), the words
/// over it all in `ink`'s; `scale` their size over the styles'.
fn sb_outlined(
  c : @ui.Ctx,
  words : String,
  ink : @ui.TextStyle,
  edge : @ui.TextStyle,
  shade : @ui.TextStyle,
  r : Double,
  drop : Double,
  scale : Double,
) -> Unit {
  c.box(fn() {
    sr_rich(c, [@ui.span(words, scale~)], edge)
    for d in sb_round {
      c.box(left=d.0 * r, top=d.1 * r + drop, fn() { sr_rich(c, [@ui.span(words, scale~)], shade) }) |> ignore
    }
    for d in sb_round {
      c.box(left=d.0 * r, top=d.1 * r, fn() { sr_rich(c, [@ui.span(words, scale~)], edge) }) |> ignore
    }
    c.box(left=0.0, top=0.0, fn() { sr_rich(c, [@ui.span(words, scale~)], ink) }) |> ignore
  })
  |> ignore
}

///|
/// The words of `key` with its `{name}`s put in from `args`, as sr_said's: each figure in `hi`, `scale` its size, bold
/// (`bold` false: in the words' weight), but those named in `plain`, put in as the words are.
fn sb_said(
  key : String,
  args : Array[(String, String)],
  hi : Int64,
  scale? : Double = 1.0,
  bold? : Bool = true,
  plain? : Array[String] = [],
) -> Array[@ui.Run] {
  let runs : Array[@ui.Run] = []
  let mut rest = @sf.t(key)
  while true {
    match rest.find("{") {
      None => break
      Some(i) => {
        let after = rest.exact_view(start=i + 1).to_owned()
        match after.find("}") {
          None => break
          Some(j) => {
            let name = after.exact_view(end=j).to_owned()
            if i > 0 {
              runs.push(@ui.span(rest.exact_view(end=i).to_owned()))
            }
            let value = sr_arg(args, name)
            if plain.contains(name) {
              runs.push(@ui.span(value))
            } else {
              runs.push(@ui.span(value, color=hi, weight=if bold { 700 } else { 0 }, scale~))
            }
            rest = after.exact_view(start=j + 1).to_owned()
          }
        }
      }
    }
  }
  if rest != "" {
    runs.push(@ui.span(rest))
  }
  runs
}

///|
/// A figure of the view as it is said (2.1 亿, 57 个, $1,911) and what it counts after its last space (亿, 个: none
/// where that has a digit, $1,911).
fn sb_split(value : String) -> (String, String) {
  let mut last = -1
  let mut i = 0
  for ch in value {
    if ch == ' ' {
      last = i
    }
    i = i + 1
  }
  if last < 0 {
    return (value, "")
  }
  let head = StringBuilder()
  let tail = StringBuilder()
  let mut k = 0
  let mut digit = false
  for ch in value {
    if k < last {
      head.write_char(ch)
    } else if k > last {
      tail.write_char(ch)
      if ch >= '0' && ch <= '9' {
        digit = true
      }
    }
    k = k + 1
  }
  if digit {
    (value, "")
  } else {
    (head.to_string(), tail.to_string())
  }
}

///|
/// A figure as runs: its number in `hi`, bold, `scale` its size, what it counts after it in the words' size (`whole`:
/// all of it the number's).
fn sb_figure(value : String, hi : Int64, scale : Double, whole? : Bool = false) -> Array[@ui.Run] {
  let (n, unit) = sb_split(value)
  if whole || unit == "" {
    [@ui.span(value, color=hi, weight=700, scale~)]
  } else {
    [@ui.span(n, color=hi, weight=700, scale~), @ui.span(unit, color=hi, weight=700)]
  }
}

///|
/// The day of when the view was had (10月26日 of 10月26日 04:12).
fn sb_date(at : String) -> String {
  let buf = StringBuilder()
  for ch in at {
    if ch == ' ' {
      break
    }
    buf.write_char(ch)
  }
  buf.to_string()
}

///|
/// Dots of light over a look's ground, each where `dots` says (left, top, across) in `ink`: drawn first, under all.
fn sb_sparks(c : @ui.Ctx, dots : Array[(Double, Double, Double)], ink : Int64) -> Unit {
  for d in dots {
    let (x, y, across) = d
    c.box(style=@ui.style(w=Fixed(across), h=Fixed(across), radius=Full, bg=Data(ink)), left=x, top=y, fn() {  })
    |> ignore
  }
}

///|
/// A speech bubble's tail over its top edge, `left` in from its left, in `ink` (the bubble's own).
fn sb_tail(c : @ui.Ctx, left : Double, ink : Int64) -> Unit {
  let h = sb_tail_h
  c.box(left~, top=-h, fn() {
    c.shapes([@ui.shape_of([([0.0, h, h, 0.0, 2.0 * h, h], true)], fill=ink)], w=Px(2.0 * h), h=Px(h)) |> ignore
  })
  |> ignore
}

///|
let sb_tail_h : Double = 9.0

///|
/// A heroine's name (the catalog's), as all of this file's looks say them.
fn sb_name(who : String) -> String {
  @sf.t("web-main.stations.shareSenren.chibi." + who)
}

///|
/// Words that may say more in one language than the room beside them: wrapped, two lines at most.
let sb_two_lines : Int = 2

///|
/// The heroines, in the order the group pictures and the routes have them.
// kept across runs: a table, never written
let sb_six : Array[String] = ["murasame", "yoshino", "mako", "lena", "koharu", "roka"]

///|
/// Every model with its tokens (as a number, to rank by) and as said, its cost and its name: the most tokens first.
fn sb_ranked(fleet : Json?) -> Array[(String, Double, String, String)] {
  let out : Array[(String, Double, String, String)] = []
  for q in items(fleet, "spent") {
    for m in items(Some(q), "models") {
      let m = Some(m)
      out.push((text(m, "name"), number(m, "tokens"), text(m, "tokensText"), text(m, "costText")))
    }
  }
  out.sort_by(fn(a, b) { b.1.compare(a.1) })
  out
}

///|
/// The outlines of SVG path data `d`, every point `k` times as far out, then moved by (`dx`, `dy`): a shape's.
fn sb_path(d : String, k : Double, dx : Double, dy : Double) -> Array[(Array[Double], Bool)] {
  @pixels.svg_path(d, k * sb_fine).map(fn(o) {
    let pts = o.0
    let out : Array[Double] = []
    let mut j = 0
    while j + 1 < pts.length() {
      out.push(pts[j] * k + dx)
      out.push(pts[j + 1] * k + dy)
      j += 2
    }
    (out, o.1)
  })
}

///|
/// How finely curves are cut: for a picture drawn at 4 pixels a point.
let sb_fine : Double = 4.0

///|
/// A round of 1 about the origin, and its upper half (SVG path data, for sb_path).
let sb_disc : String = "M-1 0 A1 1 0 1 0 1 0 A1 1 0 1 0 -1 0 Z"

///|
let sb_upper_half : String = "M-1 0 A1 1 0 0 1 1 0 Z"

///|
/// An oval about (`cx`, `cy`), `rx` across and `ry` down, turned by `turn` (its cos and sin).
fn sb_oval(cx : Double, cy : Double, rx : Double, ry : Double, turn : (Double, Double)) -> (Array[Double], Bool) {
  let pts : Array[Double] = []
  let k = if rx > ry { rx } else { ry }
  for o in @pixels.svg_path(sb_disc, k * sb_fine) {
    let p = o.0
    let mut j = 0
    while j + 1 < p.length() {
      let x = p[j] * rx
      let y = p[j + 1] * ry
      pts.push(cx + x * turn.0 - y * turn.1)
      pts.push(cy + x * turn.1 + y * turn.0)
      j += 2
    }
  }
  (pts, true)
}

///|
/// Not turned.
// kept across runs: a value (no field of it changes)
let sb_straight : (Double, Double) = (1.0, 0.0)

///|
/// Outlines turned about (`cx`, `cy`) by `turn` (its cos and sin), as an SVG's rotate(…) does.
fn sb_turned(o : Array[(Array[Double], Bool)], cx : Double, cy : Double, turn : (Double, Double)) -> Array[(Array[Double], Bool)] {
  o.map(fn(x) {
    let p = x.0
    let out : Array[Double] = []
    let mut j = 0
    while j + 1 < p.length() {
      let dx = p[j] - cx
      let dy = p[j + 1] - cy
      out.push(cx + dx * turn.0 - dy * turn.1)
      out.push(cy + dx * turn.1 + dy * turn.0)
      j += 2
    }
    (out, x.1)
  })
}

///|
/// What of outline `subject` is inside outline `clip` (which bulges nowhere in: a glass), as an SVG's clip-path:
/// Sutherland and Hodgman's, an edge of `clip` at a time.
fn sb_clip(subject : Array[Double], clip : Array[Double]) -> Array[Double] {
  let n = clip.length() / 2
  let mut area = 0.0
  for i in 0..<n {
    let j = (i + 1) % n
    area = area + clip[2 * i] * clip[2 * j + 1] - clip[2 * j] * clip[2 * i + 1]
  }
  let way = if area >= 0.0 { 1.0 } else { -1.0 }
  let mut out = subject
  for i in 0..<n {
    let j = (i + 1) % n
    let ax = clip[2 * i]
    let ay = clip[2 * i + 1]
    let bx = clip[2 * j]
    let by = clip[2 * j + 1]
    if ax == bx && ay == by {
      continue
    }
    let side = fn(x : Double, y : Double) { way * ((bx - ax) * (y - ay) - (by - ay) * (x - ax)) }
    let input = out
    let m = input.length() / 2
    if m == 0 {
      break
    }
    out = []
    for p in 0..<m {
      let q = (p + m - 1) % m
      let px = input[2 * p]
      let py = input[2 * p + 1]
      let qx = input[2 * q]
      let qy = input[2 * q + 1]
      let sp = side(px, py)
      let sq = side(qx, qy)
      if (sp >= 0.0) != (sq >= 0.0) {
        let t = sq / (sq - sp)
        out.push(qx + t * (px - qx))
        out.push(qy + t * (py - qy))
      }
      if sp >= 0.0 {
        out.push(px)
        out.push(py)
      }
    }
  }
  out
}

///|
/// Where outline `pts` crosses the line `y` down: its rightmost crossing (`right`) or its leftmost; where it does not,
/// its rightmost or leftmost point.
fn sb_x_at(pts : Array[Double], y : Double, right : Bool) -> Double {
  let n = pts.length() / 2
  let mut best = 0.0
  let mut found = false
  for i in 0..<n {
    let j = (i + 1) % n
    let x0 = pts[2 * i]
    let y0 = pts[2 * i + 1]
    let x1 = pts[2 * j]
    let y1 = pts[2 * j + 1]
    if ((y0 <= y && y <= y1) || (y1 <= y && y <= y0)) && y0 != y1 {
      let x = x0 + (y - y0) / (y1 - y0) * (x1 - x0)
      if !found || (right && x > best) || (!right && x < best) {
        best = x
      }
      found = true
    }
  }
  if found {
    return best
  }
  for i in 0..<n {
    let x = pts[2 * i]
    if i == 0 || (right && x > best) || (!right && x < best) {
      best = x
    }
  }
  best
}

///|
/// Line `pts` (x y …) dotted: a piece `on` long each `on` + `off` along it, each a line of its own.
fn sb_dashed(pts : Array[Double], on : Double, off : Double) -> Array[(Array[Double], Bool)] {
  let out : Array[(Array[Double], Bool)] = []
  let mut left = on
  let mut drawing = true
  let mut j = 0
  while j + 3 < pts.length() {
    let x0 = pts[j]
    let y0 = pts[j + 1]
    let x1 = pts[j + 2]
    let y1 = pts[j + 3]
    let len = ((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)).sqrt()
    let mut at = 0.0
    while at < len {
      let step = if left < len - at { left } else { len - at }
      if drawing && step > 0.0 {
        let a = at / len
        let b = (at + step) / len
        out.push(([x0 + (x1 - x0) * a, y0 + (y1 - y0) * a, x0 + (x1 - x0) * b, y0 + (y1 - y0) * b], false))
      }
      at = at + step
      left = left - step
      if left <= 0.0 {
        drawing = !drawing
        left = if drawing { on } else { off }
      }
    }
    j += 2
  }
  out
}

///|
/// A line of words over the ground: what is said at its start, the time (or still.fail) at its end.
// kept across runs: a value (no field of it changes)
let sb_foot : @ui.Style = @ui.css("row w=Full align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let sb_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let sb_middle : @ui.Style = @ui.css("w=Full align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sb_middle_below : @ui.Style = sb_middle.then(@ui.css("pt=S1_5"))

// ── Ciallo ───────────────────────────────────────────────────────────────

///|
/// Ciallo: 丛雨's chibi saluting on her sticker's pink, the salute's words large under her (as 巡 of the house's other
/// game says it, which she says she learned next door); her bubble, the week's tokens and cost; six stickers, the
/// week's tokens, cost and chats archived, the chats at work, the tasks across devices, the devices; still.fail's line
/// and when.
fn sr_ciallo(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = sr_args(fleet)
  let key = "web-main.stations.shareSenren.ciallo."
  sr_box(c, id, flat, ciallo_ground, fn() {
    sb_sparks(c, ciallo_sparks, ciallo_spark)
    c.box(style=ciallo_hero, fn() {
      sr_art(c, "b1-chibi-ciallo", @sf.share_w_most, ciallo_art_h, at=ciallo_art_at) |> ignore
      c.box(left=ciallo_in, top=ciallo_top, fn() { sr_brand(c, ciallo_brand) }) |> ignore
    })
    |> ignore
    c.box(style=sb_middle, fn() {
      sb_outlined(
        c,
        @sf.t(key + "salute"),
        ciallo_salute,
        ciallo_salute_edge,
        ciallo_salute_shade,
        ciallo_edge_r,
        sb_lift,
        ciallo_salute_scale,
      )
    })
    |> ignore
    c.box(style=sb_middle_below, fn() { sr_words(c, @sf.t(key + "from"), ciallo_from) }) |> ignore
    c.box(style=ciallo_bubble, fn() {
      sr_words(c, sb_name("murasame"), ciallo_who)
      sr_rich(c, sb_said(key + "say", args, ciallo_hot, scale=ciallo_hot_scale, plain=["model"]), ciallo_say)
      sb_tail(c, ciallo_tail_left, ciallo_paper)
    })
    |> ignore
    let archived = sr_arg(args, "archived")
    let stickers : Array[(Array[@ui.Run], String)] = [
      (sb_figure(sr_arg(args, "weekTokens"), ciallo_sticker_ink, ciallo_v_scale, whole=true), "weekTokens"),
      (sb_figure(sr_arg(args, "weekCost"), ciallo_sticker_ink, ciallo_v_scale), "weekCost"),
      (sb_figure(archived, ciallo_sticker_ink, ciallo_v_scale), "archived"),
      (sb_said(key + "chatsV", args, ciallo_sticker_ink, scale=ciallo_v_scale), "chats"),
      (sb_said(key + "tasksV", args, ciallo_sticker_ink, scale=ciallo_v_scale), "tasks"),
      (sb_said(key + "devicesV", args, ciallo_sticker_ink, scale=ciallo_v_scale), "devices"),
    ]
    c.box(style=ciallo_stickers, fn() {
      for row in 0..<3 {
        c.box(style=ciallo_sticker_row, fn() {
          for k in 0..<2 {
            let i = row * 2 + k
            let s = stickers[i]
            c.box(style=ciallo_sticker.then(@ui.style(bg=Data(ciallo_sticker_grounds[i]))), fn() {
              sr_rich(c, s.0, ciallo_v)
              sr_words(c, @sf.t(key + s.1), ciallo_k)
            })
            |> ignore
          }
        })
        |> ignore
      }
    })
    |> ignore
    c.box(style=ciallo_foot, fn() {
      sr_words(c, @sf.t("web-main.stations.shareTagline"), ciallo_small)
      c.box(style=sb_grow, fn() {  }) |> ignore
      sr_words(c, sr_arg(args, "at"), ciallo_small)
    })
    |> ignore
  })
}

///|
/// Ciallo's pink (the sticker's own ground) and its wine-dark ink.
let ciallo_ground : Int64 = 0xFDC1D6FFL

///|
let ciallo_ink : Int64 = 0x5A2340FFL

///|
let ciallo_dim : Int64 = 0xA04D74FFL

///|
let ciallo_hot : Int64 = 0xFF3D7FFFL

///|
let ciallo_paper : Int64 = 0xFFFFFFFFL

///|
let ciallo_spark : Int64 = 0xFFFFFF99L

///|
/// The sparkles over the pink (left, top, across), as the sticker's ground has them.
// kept across runs: a table, never written
let ciallo_sparks : Array[(Double, Double, Double)] = [
  (41.0, 496.0, 5.0),
  (314.0, 560.0, 6.0),
  (70.0, 706.0, 5.0),
  (279.0, 738.0, 4.0),
  (178.0, 610.0, 4.0),
]

///|
/// Her picture 330 high, its crop 42% down; the salute's words over its last 14.
let ciallo_art_h : Double = 330.0

///|
let ciallo_art_at : Double = 0.42

///|
// kept across runs: a value (no field of it changes)
let ciallo_hero : @ui.Style = @ui.style(w=Full, h=Fixed(ciallo_hero_h))

///|
let ciallo_hero_h : Double = 316.0

///|
let ciallo_in : Double = 18.0

///|
let ciallo_top : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let ciallo_brand : @ui.TextStyle = @ui.text_style(size=Lg, weight=Bold, color=Data(ciallo_ink), wrap=false)

///|
/// The salute: its pink (#ff4f8b) over a white edge 3.5 out, a pink shade 3 under that; 33 high.
// kept across runs: a value (no field of it changes)
let ciallo_salute : @ui.TextStyle = @ui.text_style(size=Xl4, weight=Bold, color=Data(ciallo_salute_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ciallo_salute_edge : @ui.TextStyle = ciallo_salute.then(@ui.text_style(color=Data(ciallo_paper)))

///|
// kept across runs: a value (no field of it changes)
let ciallo_salute_shade : @ui.TextStyle = ciallo_salute.then(@ui.text_style(color=Data(ciallo_salute_shade_ink)))

///|
let ciallo_salute_ink : Int64 = 0xFF4F8BFFL

///|
let ciallo_salute_shade_ink : Int64 = 0xF59AB9FFL

///|
let ciallo_edge_r : Double = 3.5

///|
let ciallo_salute_scale : Double = 1.0

///|
// kept across runs: a value (no field of it changes)
let ciallo_from : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(ciallo_dim), wrap=false)

///|
/// 丛雨's bubble: the paper, 18 in from the card's sides, 14 under the line over it, its tail 46 in.
// kept across runs: a value (no field of it changes)
let ciallo_bubble : @ui.Style = @ui.css("mx=S4_5 mt=S3_5 px=S4 pt=S3 pb=S3 radius=Xl2 gap=S0_5").then(
  @ui.style(bg=Data(ciallo_paper), shadow=Cast(sb_sharp, sb_lift, ciallo_bubble_edge)),
)

///|
let ciallo_bubble_edge : Int64 = 0xF2A3C0FFL

///|
let ciallo_tail_left : Double = 46.0

///|
// kept across runs: a value (no field of it changes)
let ciallo_who : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(ciallo_who_ink), w=Full)

///|
let ciallo_who_ink : Int64 = 0xC0628DFFL

///|
// kept across runs: a value (no field of it changes)
let ciallo_say : @ui.TextStyle = @ui.text_style(size=Lg, leading=L6, color=Data(ciallo_say_ink), w=Full)

///|
let ciallo_say_ink : Int64 = 0x4A1D36FFL

///|
/// The figures she says, 19 to her 15.5.
let ciallo_hot_scale : Double = 1.2

///|
/// The stickers: two across, 10 apart, 18 in, 16 under the bubble.
// kept across runs: a value (no field of it changes)
let ciallo_stickers : @ui.Style = @ui.css("mx=S4_5 mt=S4 gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let ciallo_sticker_row : @ui.Style = @ui.css("row w=Full gap=S2_5")

///|
/// A sticker: its own pale ground in a white edge, round, a hard shadow under it.
// kept across runs: a value (no field of it changes)
let ciallo_sticker : @ui.Style = @ui.css("px=S3 pt=S2 pb=S2_5 radius=Xl2 border=B2 gap=S0_5").then(
  @ui.style(w=@sf.grow, border_color=Data(ciallo_paper), shadow=Cast(sb_sharp, sb_lift, ciallo_sticker_edge)),
)

///|
let ciallo_sticker_edge : Int64 = 0x0000001AL

///|
// kept across runs: a table, never written
let ciallo_sticker_grounds : Array[Int64] = [
  0xFFF0F6FFL, 0xFFF8E6FFL, 0xEEFAF3FFL, 0xF1EFFFFFL, 0xEAF6FFFFL, 0xFFF1ECFFL,
]

///|
let ciallo_sticker_ink : Int64 = 0x4A1D36FFL

///|
/// A sticker's figure 21 high, what it counts 13.
// kept across runs: a value (no field of it changes)
let ciallo_v : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(ciallo_sticker_ink), wrap=false)

///|
let ciallo_v_scale : Double = 1.6

///|
// kept across runs: a value (no field of it changes)
let ciallo_k : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(ciallo_k_ink), w=Full)

///|
let ciallo_k_ink : Int64 = 0x9A5578FFL

///|
// kept across runs: a value (no field of it changes)
let ciallo_foot : @ui.Style = sb_foot.then(@ui.css("px=S5 pt=S4_5 pb=S4_5"))

///|
// kept across runs: a value (no field of it changes)
let ciallo_small : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(ciallo_dim), wrap=false)

// ── 犬耳 ─────────────────────────────────────────────────────────────────

///|
/// 犬耳: 芳乃's chibi, her dog ears out (a tatari is near, the game's sign of it), a red alarm over her: the tatari
/// detected is the week's tokens, large, each kind's share a stretch of a meter; each day's chats archived a bar, today
/// red; her line (有地さん, don't stare); a note in small print; still.fail's line and still.fail.
fn sr_inumimi(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = sr_args(fleet)
  let key = "web-main.stations.shareSenren.inumimi."
  let spent = items(fleet, "spent")
  sr_box(c, id, flat, inu_ground, fn() {
    c.box(style=inu_hero, fn() {
      sr_art(c, "b2-chibi-yoshino-ears", @sf.share_w_most, inu_art_h, at=inu_art_at) |> ignore
      c.box(style=inu_alert, left=inu_alert_in, top=inu_alert_in, fn() {
        c.box(style=inu_ring, fn() { c.box(style=inu_dot, fn() {  }) |> ignore }) |> ignore
        sr_words(c, @sf.t(key + "alert"), inu_alert_words)
      })
      |> ignore
      c.box(right=inu_where_right, top=inu_where_top, fn() {
        sr_rich(c, sb_said(key + "where", args, inu_dim, bold=false), inu_where)
      })
      |> ignore
    })
    |> ignore
    c.box(style=inu_panel, fn() {
      c.box(style=inu_title_row, fn() {
        c.box(style=inu_title_lead, fn() { sr_words(c, @sf.t(key + "title"), inu_title_wrap) }) |> ignore
        sr_rich(c, sb_said(key + "most", args, inu_title_ink, bold=false), inu_title)
      })
      |> ignore
      c.box(style=inu_big_row, fn() {
        sr_words(c, sr_arg(args, "weekTokens"), inu_big)
        sr_words(c, @sf.t(key + "unit"), inu_unit)
      })
      |> ignore
      c.box(style=inu_meter, fn() {
        for i, q in spent {
          let ink = inu_kinds[i % inu_kinds.length()]
          c.box(style=@ui.style(w=Grow(number(Some(q), "share")), h=Full, bg=Data(ink)), fn() {  }) |> ignore
        }
      })
      |> ignore
      c.box(style=inu_keys, flow=true, line_gap=inu_keys_line_gap, fn() {
        for i, q in spent {
          let q = Some(q)
          let ink = inu_kinds[i % inu_kinds.length()]
          let share = (number(q, "share") * 100.0).round().to_int().to_string() + "%"
          let kargs = [("kind", text(q, "name")), ("accounts", count(q, "accounts").to_string()), ("share", share)]
          c.box(style=inu_key, fn() {
            c.box(style=@ui.style(w=Fixed(inu_key_dot), h=Fixed(inu_key_dot), radius=Full, bg=Data(ink)), fn() {  })
            |> ignore
            sr_rich(c, sb_said(key + "key", kargs, inu_key_ink, bold=false), inu_key_words)
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
    c.box(style=inu_obs, fn() {
      c.box(style=inu_title_row, fn() {
        c.box(style=inu_title_lead, fn() { sr_words(c, @sf.t(key + "daily"), inu_title_wrap) }) |> ignore
        sr_rich(c, sb_said(key + "week", args, inu_title_ink, bold=false), inu_title)
      })
      |> ignore
      let days = sr_days(fleet)
      c.box(style=inu_bars, fn() {
        for d in days {
          let h = if d.3 * inu_bars_h > inu_bar_least { d.3 * inu_bars_h } else { inu_bar_least }
          c.box(style=inu_bar_slot, fn() {
            let ink = if d.4 { inu_red } else { inu_bar }
            c.box(style=@ui.style(w=Full, h=Fixed(h), radius=Md, bg=Data(ink)), fn() {  })
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      c.box(style=inu_labels, fn() {
        for d in days {
          c.box(style=inu_label_slot, fn() {
            if d.4 {
              sr_words(c, @sf.t(key + "today"), inu_today)
            } else {
              sr_words(c, d.0, inu_label)
            }
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
    c.box(style=inu_say_box, fn() {
      sr_words(c, sb_name("yoshino"), inu_who)
      sr_words(c, @sf.t(key + "say"), inu_say)
    })
    |> ignore
    c.box(style=inu_note_box, fn() { sr_words(c, @sf.t(key + "note"), inu_note) }) |> ignore
    c.box(style=inu_foot, fn() {
      sr_words(c, @sf.t("web-main.stations.shareTagline"), inu_small)
      c.box(style=sb_grow, fn() {  }) |> ignore
      sr_brand(c, inu_brand)
    })
    |> ignore
  })
}

///|
/// 犬耳's lavender (her sticker's ground) and its ink.
let inu_ground : Int64 = 0xDFC8FDFFL

///|
let inu_ink : Int64 = 0x2F2150FFL

///|
let inu_dim : Int64 = 0x6B56A0FFL

///|
let inu_red : Int64 = 0xE8384FFFL

///|
let inu_paper : Int64 = 0xFFFFFFFFL

///|
let inu_edge : Int64 = 0xC3A8F0FFL

///|
let inu_art_h : Double = 318.0

///|
let inu_art_at : Double = 0.38

///|
/// Her picture, the panel over its last 6.
// kept across runs: a value (no field of it changes)
let inu_hero : @ui.Style = @ui.style(w=Full, h=Fixed(inu_hero_h))

///|
let inu_hero_h : Double = 312.0

///|
let inu_alert_in : Double = 16.0

///|
/// The alarm: a red pill, a white dot in its ring, the words; a hard red shadow under it.
// kept across runs: a value (no field of it changes)
let inu_alert : @ui.Style = @ui.css("row gap=S1_5 align=ACenter pl=S2 pr=S3 py=S1 radius=Full").then(
  @ui.style(bg=Data(inu_red), shadow=Cast(sb_sharp, sb_lift, inu_alert_edge)),
)

///|
let inu_alert_edge : Int64 = 0xB3203AFFL

///|
// kept across runs: a value (no field of it changes)
let inu_ring : @ui.Style = @ui.css("radius=Full align=ACenter justify=JCenter").then(
  @ui.style(w=Fixed(inu_ring_w), h=Fixed(inu_ring_w), bg=Data(inu_ring_ink)),
)

///|
let inu_ring_w : Double = 15.0

///|
let inu_ring_ink : Int64 = 0xFFFFFF55L

///|
// kept across runs: a value (no field of it changes)
let inu_dot : @ui.Style = @ui.css("radius=Full").then(
  @ui.style(w=Fixed(inu_dot_w), h=Fixed(inu_dot_w), bg=Data(inu_paper)),
)

///|
let inu_dot_w : Double = 9.0

///|
// kept across runs: a value (no field of it changes)
let inu_alert_words : @ui.TextStyle = @ui.text_style(size=Base, weight=Bold, color=Data(inu_paper), wrap=false)

///|
let inu_where_right : Double = 18.0

///|
let inu_where_top : Double = 20.0

///|
// kept across runs: a value (no field of it changes)
let inu_where : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(inu_dim), wrap=false)

///|
/// The panel of the tatari detected: the paper, 16 in, round, its shadow the lavender deeper.
// kept across runs: a value (no field of it changes)
let inu_panel : @ui.Style = @ui.css("mx=S4 px=S4 pt=S3_5 pb=S4 radius=Xl2").then(
  @ui.style(bg=Data(inu_paper), shadow=Cast(sb_sharp, inu_panel_lift, inu_edge)),
)

///|
let inu_panel_lift : Double = 4.0

///|
// kept across runs: a value (no field of it changes)
let inu_title_row : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let inu_title : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(inu_title_ink), wrap=false)

///|
let inu_title_ink : Int64 = 0x7A63B0FFL

///|
/// A title row's words: what is left beside its figure, on two lines where a language says more.
// kept across runs: a value (no field of it changes)
let inu_title_lead : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let inu_title_wrap : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(inu_title_ink), w=Full, max_lines=sb_two_lines)

///|
// kept across runs: a value (no field of it changes)
let inu_big_row : @ui.Style = @ui.css("row gap=S2 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let inu_big : @ui.TextStyle = @ui.text_style(size=Xl5, weight=Bold, tracking=Tight, color=Data(inu_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let inu_unit : @ui.TextStyle = @ui.text_style(size=Lg, color=Data(inu_unit_ink), wrap=false)

///|
let inu_unit_ink : Int64 = 0x4B3A78FFL

///|
/// The meter: each kind's share a stretch of it, a pill 14 high on the lavender barely.
// kept across runs: a value (no field of it changes)
let inu_meter : @ui.Style = @ui.css("row w=Full radius=Full clip mt=S3 mb=S2").then(
  @ui.style(h=Fixed(inu_meter_h), bg=Data(inu_meter_ground)),
)

///|
let inu_meter_h : Double = 14.0

///|
let inu_meter_ground : Int64 = 0xEFE6FFFFL

///|
/// The kinds' colours in their order: the alarm's red, a violet, a gold.
// kept across runs: a table, never written
let inu_kinds : Array[Int64] = [0xE8384FFFL, 0x8B6FE0FFL, 0xF2B33DFFL]

///|
// kept across runs: a value (no field of it changes)
let inu_keys : @ui.Style = @ui.css("row w=Full gap=S3")

///|
let inu_keys_line_gap : Double = 4.0

///|
// kept across runs: a value (no field of it changes)
let inu_key : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
let inu_key_dot : Double = 8.0

///|
let inu_key_ink : Int64 = 0x4B3A78FFL

///|
// kept across runs: a value (no field of it changes)
let inu_key_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(inu_key_ink), wrap=false)

///|
/// The days watched: the paper thinned, 12 under the panel.
// kept across runs: a value (no field of it changes)
let inu_obs : @ui.Style = @ui.css("mx=S4 mt=S3 px=S3_5 pt=S3 pb=S2_5 radius=Xl2").then(@ui.style(bg=Data(inu_obs_ground)))

///|
let inu_obs_ground : Int64 = 0xFFFFFFB3L

///|
// kept across runs: a value (no field of it changes)
let inu_bars : @ui.Style = @ui.css("row w=Full gap=S2 mt=S2 align=AEnd").then(@ui.style(h=Fixed(inu_bars_h)))

///|
let inu_bars_h : Double = 62.0

///|
let inu_bar_least : Double = 6.0

///|
let inu_bar : Int64 = 0xB79CF0FFL

///|
// kept across runs: a value (no field of it changes)
let inu_bar_slot : @ui.Style = @ui.css("h=Full justify=JEnd").then(@ui.style(w=@sf.grow))

///|
// kept across runs: a value (no field of it changes)
let inu_labels : @ui.Style = @ui.css("row w=Full gap=S2 mt=S2")

///|
// kept across runs: a value (no field of it changes)
let inu_label_slot : @ui.Style = @ui.css("align=ACenter").then(@ui.style(w=@sf.grow))

///|
// kept across runs: a value (no field of it changes)
let inu_label : @ui.TextStyle = @ui.text_style(size=Xs3, color=Data(inu_title_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let inu_today : @ui.TextStyle = @ui.text_style(size=Xs3, weight=Bold, color=Data(inu_red), wrap=false)

///|
/// Her line: on the paper, round, its shadow the lavender deeper.
// kept across runs: a value (no field of it changes)
let inu_say_box : @ui.Style = @ui.css("mx=S4 mt=S3_5 px=S3_5 pt=S3 pb=S3 radius=Xl2").then(
  @ui.style(bg=Data(inu_paper), shadow=Cast(sb_sharp, sb_lift, inu_edge)),
)

///|
// kept across runs: a value (no field of it changes)
let inu_who : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(inu_who_ink), w=Full)

///|
let inu_who_ink : Int64 = 0x8A70C8FFL

///|
// kept across runs: a value (no field of it changes)
let inu_say : @ui.TextStyle = @ui.text_style(size=Lg, leading=L6, color=Data(inu_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let inu_note_box : @ui.Style = @ui.css("mx=S5 mt=S2")

///|
// kept across runs: a value (no field of it changes)
let inu_note : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(inu_dim), w=Full)

///|
// kept across runs: a value (no field of it changes)
let inu_foot : @ui.Style = sb_foot.then(@ui.css("px=S5 pt=S3_5 pb=S4_5"))

///|
// kept across runs: a value (no field of it changes)
let inu_small : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(inu_dim), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let inu_brand : @ui.TextStyle = @ui.text_style(size=Base, weight=Bold, color=Data(inu_ink), wrap=false)

// ── 丛雨's parfait ──────────────────────────────────────────────────────

///|
/// 丛雨's parfait: her chibi with a spoon on mint, at her side a tall glass drawn (shapes): a layer each kind of
/// account from its foot, as thick as its share of the tokens (matcha, strawberry, custard), cream, a wafer and a cherry
/// on top; beside each layer its kind and its models' tokens, a dotted lead to it. Her line (all 3.1 亿 tokens of it
/// hers!); the biggest spoon (the top model), today's chats archived and cost; still.fail, when, its line.
fn sr_parfait(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = sr_args(fleet)
  let key = "web-main.stations.shareSenren.parfait."
  let spent = items(fleet, "spent")
  let bands = parfait_bands(spent.map(fn(q) { number(Some(q), "share") }))
  // where each kind's label stands (its middle down the card), pushed up where thin layers would have them overlap
  let spots : Array[(Double, Double, Double)] = []
  let mut prev = parfait_card_h * 2.0
  for i, q in spent {
    let (foot, top) = bands[i]
    let at = parfait_glass_top + (foot + top) / 2.0 * parfait_k
    let h = parfait_label_base + parfait_label_line * items(Some(q), "models").length().to_double()
    let most = prev - h / 2.0 - parfait_label_apart
    let y = if at < most { at } else { most }
    prev = y - h / 2.0
    spots.push((at, y, h))
  }
  sr_box(c, id, flat, parfait_ground, fn() {
    c.box(style=parfait_card, fn() {
      sb_sparks(c, parfait_sparks, parfait_spark)
      c.box(left=parfait_art_left, top=parfait_art_top, fn() {
        sr_art(c, "b3-chibi-murasame-spoon", parfait_art_w, parfait_art_w) |> ignore
      })
      |> ignore
      c.box(left=parfait_glass_left, top=parfait_glass_top, fn() {
        c.shapes(parfait_glass(bands), w=Px(parfait_glass_w * parfait_k), h=Px(parfait_glass_h * parfait_k)) |> ignore
      })
      |> ignore
      c.box(left=0.0, top=0.0, fn() {
        c.shapes(parfait_leads(spots), w=Px(@sf.share_w_most), h=Px(parfait_card_h)) |> ignore
      })
      |> ignore
      for i, q in spent {
        let q = Some(q)
        let s = spots[i]
        let ink = parfait_sweets[i % parfait_sweets.length()].0
        c.box(style=parfait_label, left=parfait_label_left, right=parfait_label_right, top=s.1 - s.2 / 2.0, fn() {
          c.box(style=parfait_label_bar.then(@ui.style(bg=Data(ink))), fn() {  }) |> ignore
          c.box(style=parfait_label_words, fn() {
            sr_words(c, parfait_kind(text(q, "name"), key), parfait_kind_words)
            for m in items(q, "models") {
              let m = Some(m)
              sr_rich(
                c,
                [@ui.span(parfait_short(text(m, "name")) + " "), @ui.span(text(m, "tokensText"), weight=700, color=parfait_ink)],
                parfait_model_words,
              )
            }
          })
          |> ignore
        })
        |> ignore
      }
      c.box(style=sb_foot, left=parfait_top_in, right=parfait_top_in, top=parfait_top_y, fn() {
        sr_brand(c, parfait_brand)
        c.box(style=sb_grow, fn() {  }) |> ignore
        sr_words(c, sr_arg(args, "at"), parfait_small)
      })
      |> ignore
      c.box(left=parfait_title_left, top=parfait_title_top, fn() {
        sb_outlined(
          c,
          @sf.t(key + "title"),
          parfait_title,
          parfait_title_edge,
          parfait_title_shade,
          parfait_title_r,
          sb_lift,
          parfait_title_scale,
        )
      })
      |> ignore
      c.box(style=parfait_say, left=parfait_in, right=parfait_in, top=parfait_say_top, fn() {
        sr_words(c, sb_name("murasame"), parfait_who)
        sr_rich(c, sb_said(key + "say", args, parfait_hot, scale=parfait_hot_scale), parfait_say_words)
        sb_tail(c, parfait_tail_left, parfait_paper)
      })
      |> ignore
      c.box(style=parfait_chips, left=parfait_in, right=parfait_in, top=parfait_chips_top, fn() {
        let chips : Array[(Array[@ui.Run], String)] = [
          (
            sb_said(key + "spoonV", args, parfait_ink, plain=["tokens", "cost"]),
            @sf.t(key + "spoon", args=[("model", sr_arg(args, "model"))]),
          ),
          (sb_figure(sr_arg(args, "todayArchived"), parfait_ink, parfait_v_scale), @sf.t(key + "todayArchived")),
          (sb_figure(sr_arg(args, "todayCost"), parfait_ink, parfait_v_scale), @sf.t(key + "todayCost")),
        ]
        for i, chip in chips {
          c.box(style=parfait_chip.then(@ui.style(w=Grow(parfait_chip_grow[i]))), fn() {
            sr_rich(c, chip.0, if i == 0 { parfait_v_first } else { parfait_v })
            sr_words(c, chip.1, parfait_k_words)
          })
          |> ignore
        }
      })
      |> ignore
      c.box(style=sb_foot, left=parfait_top_in, right=parfait_top_in, bottom=parfait_foot_y, fn() {
        sr_words(c, @sf.t("web-main.stations.shareTagline"), parfait_small)
        c.box(style=sb_grow, fn() {  }) |> ignore
        sr_words(c, @sf.t(key + "limited"), parfait_small)
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// Each kind's layer in the glass (in its drawing's units, 130 by 430), from its foot up: its foot and its top, as
/// thick as its share of what the layers fill (10 at least).
fn parfait_bands(shares : Array[Double]) -> Array[(Double, Double)] {
  let out : Array[(Double, Double)] = []
  let mut y = parfait_layers_foot
  for share in shares {
    let full = parfait_layers_foot - parfait_layers_top
    let h = if full * share > parfait_layer_least { full * share } else { parfait_layer_least }
    out.push((y, y - h))
    y = y - h
  }
  out
}

///|
/// A kind's name as its label says it: without what every kind's name ends in (订阅), where it does.
fn parfait_kind(name : String, key : String) -> String {
  for e in @sf.t(key + "kindEnd").split("|") {
    let end = e.to_owned()
    if end != "" && name.has_suffix(end) && name.length() > end.length() {
      return name.exact_view(end=name.length() - end.length()).to_owned()
    }
  }
  name
}

///|
/// A model's name short (Opus 5.5: Opus; GPT-5.5 Codex: Codex; GLM-4.6: GLM): its first word with no figure in it,
/// or what is before its dash.
fn parfait_short(name : String) -> String {
  let words : Array[String] = []
  let buf = StringBuilder()
  let mut figure = false
  let flush = fn(buf : StringBuilder, figure : Bool) {
    let w = buf.to_string()
    if w != "" && !figure {
      words.push(w)
    }
  }
  for ch in name {
    if ch == ' ' {
      flush(buf, figure)
      buf.reset()
      figure = false
    } else {
      if ch >= '0' && ch <= '9' {
        figure = true
      }
      buf.write_char(ch)
    }
  }
  flush(buf, figure)
  if words.length() > 0 {
    return words[0]
  }
  let head = StringBuilder()
  for ch in name {
    if ch == '-' || ch == ' ' {
      break
    }
    head.write_char(ch)
  }
  head.to_string()
}

///|
/// The parfait glass (its drawing's units, then all of it 0.82 as large): the glass, each kind's layer cut to it with
/// its wavy top, matcha's beans and strawberry's seeds, the glass's sheen, its rim, its stem and foot, the wafer, the
/// cream, the cherry and a leaf.
fn parfait_glass(bands : Array[(Double, Double)]) -> Array[@ui.Shape] {
  let k = parfait_k
  let inner = match sb_path(parfait_inner, 1.0, 0.0, 0.0) {
    [o, ..] => o.0
    [] => []
  }
  let out : Array[@ui.Shape] = []
  let add = fn(o : Array[(Array[Double], Bool)], fill : Int64, stroke : Int64, width : Double) {
    out.push(@ui.shape_of(o.map(fn(x) { (x.0.map(fn(v) { v * k }), x.1) }), fill~, stroke~, width=width * k))
  }
  add([(inner, true)], parfait_glass_ink, 0L, 0.0)
  for i, b in bands {
    let (foot, top) = b
    let (ink, edge) = parfait_sweets[i % parfait_sweets.length()]
    let band = [0.0, foot + 2.0, parfait_glass_w, foot + 2.0, parfait_glass_w, top]
    parfait_wave(band, top)
    add([(sb_clip(band, inner), true)], ink, 0L, 0.0)
    let line : Array[Double] = []
    parfait_wave(line, top + 3.0)
    let lo = sb_x_at(inner, top + 3.0, false) + 1.0
    let hi = sb_x_at(inner, top + 3.0, true) - 1.0
    let kept : Array[Double] = [hi, top + 3.0]
    let mut j = 0
    while j + 1 < line.length() {
      if line[j] > lo && line[j] < hi {
        kept.push(line[j])
        kept.push(line[j + 1])
      }
      j += 2
    }
    add([(kept, false)], 0L, edge, parfait_wave_w)
    let h = foot - top
    if i == 0 {
      // matcha's beans
      let m = if h - 30.0 > 20.0 { h - 30.0 } else { 20.0 }
      for n in 0..<9 {
        let x = 30.0 + (n * 37 % 72).to_double()
        let v = (n * 53).to_double()
        let y = foot - 18.0 - (v - (v / m).floor() * m)
        add([sb_oval(x, y, parfait_bean_r, parfait_bean_r, sb_straight)], parfait_bean, 0L, 0.0)
      }
    } else if i == 1 {
      // strawberry's seeds
      for n in 0..<4 {
        let x = 36.0 + (n * 19).to_double()
        add([sb_oval(x, foot - h / 2.0, parfait_seed_r, parfait_seed_r, sb_straight)], parfait_seed, 0L, 0.0)
      }
    }
  }
  // the glass's sheen: lighter at its sides
  add([(inner, true)], parfait_sheen, 0L, 0.0)
  add([(sb_clip([0.0, 0.0, 30.0, 0.0, 30.0, parfait_glass_h, 0.0, parfait_glass_h], inner), true)], parfait_sheen_side, 0L, 0.0)
  add(
    [(sb_clip([104.0, 0.0, parfait_glass_w, 0.0, parfait_glass_w, parfait_glass_h, 104.0, parfait_glass_h], inner), true)],
    parfait_sheen_side,
    0L,
    0.0,
  )
  add(sb_path(parfait_rim, 1.0, 0.0, 0.0), 0L, parfait_paper, 3.5)
  add(sb_path(parfait_gleam, 1.0, 0.0, 0.0), 0L, parfait_gleam_ink, 4.0)
  add(sb_path(parfait_stem, 1.0, 0.0, 0.0), parfait_frost, parfait_paper, 2.0)
  add([sb_oval(65.0, 400.0, 42.0, 9.0, sb_straight)], parfait_frost, parfait_paper, 2.5)
  add([sb_oval(65.0, 70.0, 55.0, 7.0, sb_straight)], 0L, parfait_paper, 3.0)
  // the wafer, leaning back
  add(sb_turned(sb_path(parfait_wafer, 1.0, 0.0, 0.0), 40.0, 80.0, parfait_wafer_turn), parfait_wafer_ink, parfait_wafer_edge, 1.5)
  add(sb_turned(sb_path(parfait_wafer_lines, 1.0, 0.0, 0.0), 40.0, 80.0, parfait_wafer_turn), 0L, parfait_wafer_line, 1.0)
  for cr in parfait_cream {
    add([sb_oval(cr.0, cr.1, cr.2, cr.2, sb_straight)], parfait_paper, parfait_cream_edge, 1.5)
  }
  add(sb_path(parfait_cherry_stem, 1.0, 0.0, 0.0), 0L, parfait_stem_ink, 2.5)
  add([sb_oval(66.0, 37.0, 11.0, 11.0, sb_straight)], parfait_cherry, 0L, 0.0)
  add([sb_oval(62.0, 33.0, 3.2, 3.2, sb_straight)], parfait_cherry_shine, 0L, 0.0)
  add([sb_oval(94.0, 58.0, 9.0, 5.0, parfait_leaf_turn)], parfait_leaf, 0L, 0.0)
  out
}

///|
/// A wave across the glass from its right to its left at `y`: a scallop each 13 across, 2.5 up at its middle.
fn parfait_wave(pts : Array[Double], y : Double) -> Unit {
  let mut x = parfait_glass_w
  while x > 0.0 {
    for t in [0.25, 0.5, 0.75, 1.0] {
      let u = 1.0 - t
      pts.push(u * u * x + 2.0 * u * t * (x - 6.5) + t * t * (x - 13.0))
      pts.push(u * u * y + 2.0 * u * t * (y - 5.0) + t * t * y)
    }
    x = x - 13.0
  }
}

///|
/// The dotted leads from the glass's edge (by its rim) to each kind's label: across a little, then to the label's middle.
fn parfait_leads(spots : Array[(Double, Double, Double)]) -> Array[@ui.Shape] {
  let rim = match sb_path(parfait_rim, 1.0, 0.0, 0.0) {
    [o, ..] => o.0
    [] => []
  }
  let out : Array[@ui.Shape] = []
  for s in spots {
    let e = parfait_glass_left + parfait_k * sb_x_at(rim, (s.0 - parfait_glass_top) / parfait_k, true)
    let pts = [e + 2.0, s.0, e + 9.0, s.0, parfait_label_left - 4.0, s.1]
    out.push(@ui.shape_of(sb_dashed(pts, parfait_dash, parfait_dash_gap), stroke=parfait_lead, width=parfait_lead_w))
  }
  out
}

///|
/// 丛雨's mint and its ink.
let parfait_ground : Int64 = 0xD1F9E3FFL

///|
let parfait_ink : Int64 = 0x1F4A3AFFL

///|
let parfait_dim : Int64 = 0x3D7A62FFL

///|
let parfait_paper : Int64 = 0xFFFFFFFFL

///|
let parfait_hot : Int64 = 0xE0447DFFL

///|
let parfait_spark : Int64 = 0xFFFFFF99L

///|
// kept across runs: a table, never written
let parfait_sparks : Array[(Double, Double, Double)] = [(308.0, 76.0, 4.0), (251.0, 24.0, 3.0), (344.0, 348.0, 4.0)]

///|
/// The card 648 high: all of it placed where the mockup has it.
// kept across runs: a value (no field of it changes)
let parfait_card : @ui.Style = @ui.style(w=Full, h=Fixed(parfait_card_h))

///|
let parfait_card_h : Double = 648.0

///|
/// Her picture: 316 square, 14 out past the card's left, 84 down.
let parfait_art_left : Double = -14.0

///|
let parfait_art_top : Double = 84.0

///|
let parfait_art_w : Double = 316.0

///|
/// The glass: its drawing 130 by 430 drawn 0.82 as large, 160 in and 70 down; its layers fill it from 342 up to 104.
let parfait_glass_left : Double = 160.0

///|
let parfait_glass_top : Double = 70.0

///|
let parfait_k : Double = 0.82

///|
let parfait_glass_w : Double = 130.0

///|
let parfait_glass_h : Double = 430.0

///|
let parfait_layers_foot : Double = 342.0

///|
let parfait_layers_top : Double = 104.0

///|
let parfait_layer_least : Double = 10.0

///|
/// Inside the glass, its rim, its gleam, its stem, the wafer and its lines, the cherry's stem (SVG path data in the
/// drawing's units).
let parfait_inner : String = "M14 72 C16 180 24 286 36 328 Q65 356 94 328 C106 286 114 180 116 72 Z"

///|
let parfait_rim : String = "M10 70 C12 180 20 290 33 331 Q65 362 97 331 C110 290 118 180 120 70"

///|
let parfait_gleam : String = "M24 92 C25 170 30 250 38 300"

///|
let parfait_stem : String = "M63 350 H67 Q71 350 71 354 V390 Q71 394 67 394 H63 Q59 394 59 390 V354 Q59 350 63 350 Z"

///|
let parfait_wafer : String = "M33 8 H43 Q46 8 46 11 V89 Q46 92 43 92 H33 Q30 92 30 89 V11 Q30 8 33 8 Z"

///|
let parfait_wafer_lines : String = "M30 22h16M30 36h16M30 50h16M30 64h16M38 8v84"

///|
let parfait_cherry_stem : String = "M68 34 C70 22 76 12 86 6"

///|
/// Each layer's sweet, from the foot: matcha, strawberry, custard (each its colour, and its wave's deeper).
// kept across runs: a table, never written
let parfait_sweets : Array[(Int64, Int64)] = [
  (0x8CC66BFFL, 0x6FAE528CL),
  (0xF59AB8FFL, 0xE5799C8CL),
  (0xF8D76EFFL, 0xECBD458CL),
]

///|
let parfait_wave_w : Double = 2.0

///|
let parfait_bean : Int64 = 0x5C3A2E8CL

///|
let parfait_bean_r : Double = 2.6

///|
let parfait_seed : Int64 = 0xD9485FB3L

///|
let parfait_seed_r : Double = 3.4

///|
let parfait_glass_ink : Int64 = 0xFFFFFF55L

///|
let parfait_sheen : Int64 = 0xFFFFFF1AL

///|
let parfait_sheen_side : Int64 = 0xFFFFFF59L

///|
let parfait_gleam_ink : Int64 = 0xFFFFFFBFL

///|
let parfait_frost : Int64 = 0xFFFFFFCCL

///|
let parfait_wafer_ink : Int64 = 0xECC27AFFL

///|
let parfait_wafer_edge : Int64 = 0xC99545FFL

///|
let parfait_wafer_line : Int64 = 0xC99545CCL

///|
/// The wafer turned back 24°, the leaf 30° (each its cos and sin).
// kept across runs: a value (no field of it changes)
let parfait_wafer_turn : (Double, Double) = (0.9135, -0.4067)

///|
// kept across runs: a value (no field of it changes)
let parfait_leaf_turn : (Double, Double) = (0.866, -0.5)

///|
/// The cream (each its middle and its round).
// kept across runs: a table, never written
let parfait_cream : Array[(Double, Double, Double)] = [
  (30.0, 92.0, 17.0),
  (100.0, 92.0, 17.0),
  (52.0, 88.0, 20.0),
  (78.0, 88.0, 20.0),
  (45.0, 70.0, 16.0),
  (84.0, 70.0, 16.0),
  (65.0, 62.0, 18.0),
  (65.0, 44.0, 12.0),
]

///|
let parfait_cream_edge : Int64 = 0xE8F4EEFFL

///|
let parfait_stem_ink : Int64 = 0x5F8A3AFFL

///|
let parfait_cherry : Int64 = 0xE8384FFFL

///|
let parfait_cherry_shine : Int64 = 0xFFFFFFCCL

///|
let parfait_leaf : Int64 = 0x7FC98FFFL

///|
/// The labels: 266 in, each 18 high and 15 a model, 8 apart at least; a bar of its layer's colour at its left.
let parfait_label_left : Double = 262.0

///|
let parfait_label_right : Double = 0.0

///|
let parfait_label_base : Double = 18.0

///|
let parfait_label_line : Double = 15.0

///|
let parfait_label_apart : Double = 8.0

///|
// kept across runs: a value (no field of it changes)
let parfait_label : @ui.Style = @ui.css("row gap=S1 align=AStretch")

///|
// kept across runs: a value (no field of it changes)
let parfait_label_bar : @ui.Style = @ui.style(w=Fixed(parfait_bar_w))

///|
let parfait_bar_w : Double = 3.0

///|
// kept across runs: a value (no field of it changes)
let parfait_label_words : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let parfait_kind_words : @ui.TextStyle = @ui.text_style(size=Xs, weight=Bold, color=Data(parfait_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let parfait_model_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(parfait_dim), wrap=false)

///|
/// The leads: dots 2 long 2.5 apart, the green deeper at three quarters.
let parfait_dash : Double = 2.0

///|
let parfait_dash_gap : Double = 2.5

///|
let parfait_lead : Int64 = 0x2F7A5CBFL

///|
let parfait_lead_w : Double = 1.2

///|
/// Its top: still.fail and when, 18 in, 14 down; the title under it, 16 in, 40 down.
let parfait_top_in : Double = 18.0

///|
let parfait_top_y : Double = 14.0

///|
let parfait_foot_y : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let parfait_brand : @ui.TextStyle = @ui.text_style(size=Lg, weight=Bold, color=Data(parfait_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let parfait_small : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(parfait_dim), wrap=false)

///|
let parfait_title_left : Double = 16.0

///|
let parfait_title_top : Double = 40.0

///|
/// The title: the mint deeper, a white edge 3 out, a shade the mint paler 3 under it; 27 high.
// kept across runs: a value (no field of it changes)
let parfait_title : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Bold, tracking=@sf.share_letters_apart, color=Data(parfait_title_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let parfait_title_edge : @ui.TextStyle = parfait_title.then(@ui.text_style(color=Data(parfait_paper)))

///|
// kept across runs: a value (no field of it changes)
let parfait_title_shade : @ui.TextStyle = parfait_title.then(@ui.text_style(color=Data(parfait_edge)))

///|
let parfait_title_ink : Int64 = 0x2F9E74FFL

///|
let parfait_edge : Int64 = 0x9FD8C0FFL

///|
let parfait_title_r : Double = 3.0

///|
let parfait_title_scale : Double = 1.22

///|
let parfait_in : Double = 16.0

///|
/// Her bubble, 438 down, its tail 70 in.
let parfait_say_top : Double = 438.0

///|
let parfait_tail_left : Double = 70.0

///|
// kept across runs: a value (no field of it changes)
let parfait_say : @ui.Style = @ui.css("px=S4 pt=S3 pb=S3 radius=Xl2 gap=S0_5").then(
  @ui.style(bg=Data(parfait_paper), shadow=Cast(sb_sharp, sb_lift, parfait_edge)),
)

///|
// kept across runs: a value (no field of it changes)
let parfait_who : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(parfait_title_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let parfait_say_words : @ui.TextStyle = @ui.text_style(size=Lg, leading=L6, color=Data(parfait_say_ink), w=Full)

///|
let parfait_say_ink : Int64 = 0x1F3D32FFL

///|
let parfait_hot_scale : Double = 1.15

///|
/// The chips, 548 down: the biggest spoon three quarters again as wide as today's two (the mockup's half again cuts
/// its 2.1 亿 · $1,420 in the app's face).
let parfait_chips_top : Double = 548.0

///|
// kept across runs: a value (no field of it changes)
let parfait_chips : @ui.Style = @ui.css("row gap=S2 align=AStretch")

///|
// kept across runs: a table, never written
let parfait_chip_grow : Array[Double] = [1.75, 1.0, 1.0]

///|
// kept across runs: a value (no field of it changes)
let parfait_chip : @ui.Style = @ui.css("px=S2_5 py=S2 radius=Xl1_5 border=B1_5").then(
  @ui.style(bg=Data(parfait_chip_ground), border_color=Data(parfait_paper)),
)

///|
let parfait_chip_ground : Int64 = 0xFFFFFFB8L

///|
// kept across runs: a value (no field of it changes)
let parfait_v : @ui.TextStyle = @ui.text_style(size=Xs, weight=Bold, color=Data(parfait_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let parfait_v_first : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, color=Data(parfait_ink), w=Full, max_lines=sb_two_lines)

///|
let parfait_v_scale : Double = 1.42

///|
// kept across runs: a value (no field of it changes)
let parfait_k_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(parfait_dim), w=Full, max_lines=sb_two_lines)

// ── 小春's capsule toys ─────────────────────────────────────────────────

///|
/// 小春's capsule toys: her chibi at a capsule machine on peach; a ribbon, this week's pulls; a capsule each model,
/// the most tokens first, its rarity by them (SSR from 1 亿, gold and shining; SR from 1000 万; R the rest), its
/// tokens and cost; her line (an SSR! the parfait's on her, but not her brother's); what the pulls cost (the week's),
/// the chats still pulling; still.fail, its line and when.
fn sr_gacha(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = sr_args(fleet)
  let key = "web-main.stations.shareSenren.gacha."
  let ranked = sb_ranked(fleet)
  sr_box(c, id, flat, gacha_ground, fn() {
    sb_sparks(c, gacha_sparks, gacha_spark)
    c.box(style=gacha_hero, fn() {
      sr_art(c, "b4-chibi-koharu-gacha", @sf.share_w_most, gacha_art_h, at=gacha_art_at) |> ignore
    })
    |> ignore
    c.box(style=sb_middle, fn() {
      c.box(style=gacha_banner, fn() {
        c.box(left=0.0, top=0.0, fn() {
          c.shapes(gacha_ribbon(), w=Px(gacha_banner_w), h=Px(gacha_banner_h + sb_lift)) |> ignore
        })
        |> ignore
        sr_rich(
          c,
          [
            @ui.span("✦", color=gacha_star, scale=gacha_star_scale),
            @ui.span(" " + @sf.t(key + "title") + " ", scale=gacha_banner_scale),
            @ui.span("✦", color=gacha_star, scale=gacha_star_scale),
          ],
          gacha_banner_words,
        )
      })
      |> ignore
    })
    |> ignore
    c.box(style=gacha_grid, fn() {
      for row in 0..<2 {
        c.box(style=gacha_row, fn() {
          for k in 0..<3 {
            let i = row * 3 + k
            if i < ranked.length() {
              gacha_capsule(c, ranked[i], i, key)
            } else {
              c.box(style=sb_grow, fn() {  }) |> ignore
            }
          }
        })
        |> ignore
      }
    })
    |> ignore
    c.box(style=gacha_say, fn() {
      sr_words(c, sb_name("koharu"), gacha_who)
      let sargs = [("ssr", @sf.t(key + "ssr"))]
      sr_rich(c, sb_said(key + "say", sargs, gacha_pink), gacha_say_words)
    })
    |> ignore
    c.box(style=gacha_bill, fn() {
      sr_words(c, @sf.t(key + "spent"), gacha_bill_words)
      sr_words(c, sr_arg(args, "weekCost"), gacha_bill_cost)
      c.box(style=sb_grow, fn() {  }) |> ignore
      c.box(style=gacha_button, fn() {
        sr_rich(c, sb_said(key + "pulling", args, gacha_paper, bold=false), gacha_button_words)
      })
      |> ignore
    })
    |> ignore
    c.box(style=gacha_foot, fn() {
      sr_brand(c, gacha_brand)
      sr_words(c, @sf.t("web-main.stations.shareTagline"), gacha_small)
      c.box(style=sb_grow, fn() {  }) |> ignore
      sr_words(c, sr_arg(args, "at"), gacha_small)
    })
    |> ignore
  })
}

///|
/// A model's capsule, the `i`th by tokens: its rarity's badge, the ball in its colour over white, its name, tokens and
/// cost; an SSR's gold, shining, its ball ringed, sparkles round it.
fn gacha_capsule(c : @ui.Ctx, m : (String, Double, String, String), i : Int, key : String) -> Unit {
  let rare = if m.1 >= gacha_ssr_from { 2 } else if m.1 >= gacha_sr_from { 1 } else { 0 }
  c.box(style=gacha_slot, fn() {
    if rare == 2 {
      // its shine: the gold thinned, twice, round it
      c.box(style=gacha_glow_far, left=-gacha_glow_far_w, right=-gacha_glow_far_w, top=-gacha_glow_far_w, bottom=-gacha_glow_far_w, fn() {  })
      |> ignore
      c.box(style=gacha_glow_near, left=-gacha_glow_near_w, right=-gacha_glow_near_w, top=-gacha_glow_near_w, bottom=-gacha_glow_near_w, fn() {  })
      |> ignore
    }
    c.box(style=if rare == 2 { gacha_cap_ssr } else { gacha_cap }, fn() {
      c.shapes(gacha_ball(gacha_tops[i % gacha_tops.length()], rare == 2), w=Px(gacha_ball_box), h=Px(gacha_ball_box)) |> ignore
      sr_rich(c, [@ui.span(m.0, scale=gacha_name_scale)], gacha_name)
      sr_words(c, m.2, if rare == 2 { gacha_tokens_ssr } else { gacha_tokens })
      sr_words(c, m.3, gacha_cost)
      c.box(style=gacha_rare.then(@ui.style(bg=Data(gacha_rare_grounds[rare]))), left=gacha_rare_in, top=gacha_rare_in, fn() {
        sr_words(c, @sf.t(key + gacha_rare_keys[rare]), gacha_rare_words)
      })
      |> ignore
      if rare == 2 {
        for s in gacha_sparkles {
          c.box(left=s.0, top=s.1, fn() { sr_rich(c, [@ui.span("✦", scale=s.2)], gacha_sparkle) }) |> ignore
        }
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The ribbon under the banner's words, its ends notched in, its hard shadow under it.
fn gacha_ribbon() -> Array[@ui.Shape] {
  let w = gacha_banner_w
  let h = gacha_banner_h
  let n = w * gacha_notch
  let at = fn(dy : Double) { [0.0, dy, w, dy, w - n, dy + h / 2.0, w, dy + h, 0.0, dy + h, n, dy + h / 2.0] }
  [
    @ui.shape_of([(at(sb_lift), true)], fill=gacha_ribbon_edge),
    @ui.shape_of([(at(0.0), true)], fill=gacha_ribbon_ink),
  ]
}

///|
/// A capsule's ball, in a box gacha_ball_box square, its middle the box's: its top half `top`, its foot white, a line
/// across, its shine, its edge; an SSR's ringed in pale gold, shining round.
fn gacha_ball(top : Int64, ssr : Bool) -> Array[@ui.Shape] {
  let o = gacha_ball_box / 2.0
  let r = gacha_ball_r
  let out : Array[@ui.Shape] = []
  if ssr {
    out.push(@ui.shape_of(sb_path(sb_disc, r + gacha_ring_w + gacha_glow_w, o, o), fill=gacha_glow_ink))
    out.push(@ui.shape_of(sb_path(sb_disc, r + gacha_ring_w, o, o), fill=gacha_ring_ink))
  }
  out.push(@ui.shape_of(sb_path(sb_disc, r, o, o), fill=gacha_paper))
  out.push(@ui.shape_of(sb_path(sb_upper_half, r, o, o), fill=top))
  out.push(@ui.shape_of([([o - r, o - gacha_line_h / 2.0, o + r, o - gacha_line_h / 2.0, o + r, o + gacha_line_h / 2.0, o - r, o + gacha_line_h / 2.0], true)], fill=gacha_ink))
  out.push(@ui.shape_of([sb_oval(o - gacha_shine_x, o - gacha_shine_y, gacha_shine_rx, gacha_shine_ry, gacha_shine_turn)], fill=gacha_shine))
  out.push(@ui.shape_of(sb_path(sb_disc, r - gacha_edge_w / 2.0, o, o), stroke=gacha_ink, width=gacha_edge_w))
  out
}

///|
/// 小春's peach and its ink.
let gacha_ground : Int64 = 0xFDD1C2FFL

///|
let gacha_ink : Int64 = 0x5A2A1EFFL

///|
let gacha_paper : Int64 = 0xFFFFFFFFL

///|
let gacha_pink : Int64 = 0xE0567CFFL

///|
let gacha_spark : Int64 = 0xFFFFFF99L

///|
// kept across runs: a table, never written
let gacha_sparks : Array[(Double, Double, Double)] = [
  (27.0, 468.0, 4.0),
  (336.0, 501.0, 5.0),
  (20.0, 736.0, 3.0),
  (329.0, 786.0, 4.0),
]

///|
let gacha_art_h : Double = 328.0

///|
let gacha_art_at : Double = 0.3

///|
/// Her picture, the ribbon over its last 22.
// kept across runs: a value (no field of it changes)
let gacha_hero : @ui.Style = @ui.style(w=Full, h=Fixed(gacha_hero_h))

///|
let gacha_hero_h : Double = 306.0

///|
/// The ribbon: 236 across, 36 high, its ends notched 6% in; its words white, spaced, a gold star either side.
// kept across runs: a value (no field of it changes)
let gacha_banner : @ui.Style = @ui.css("row align=ACenter justify=JCenter").then(
  @ui.style(w=Fixed(gacha_banner_w), h=Fixed(gacha_banner_h)),
)

///|
let gacha_banner_w : Double = 236.0

///|
let gacha_banner_h : Double = 36.0

///|
let gacha_notch : Double = 0.06

///|
let gacha_ribbon_ink : Int64 = 0xF77A5EFFL

///|
let gacha_ribbon_edge : Int64 = 0xC9472FFFL

///|
let gacha_star : Int64 = 0xFFE08AFFL

///|
let gacha_banner_scale : Double = 1.1

///|
let gacha_star_scale : Double = 0.7

///|
// kept across runs: a value (no field of it changes)
let gacha_banner_words : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, tracking=Widest, color=Data(gacha_paper), wrap=false)

///|
/// The capsules: three across, 8 apart, 14 in, 16 under the ribbon.
// kept across runs: a value (no field of it changes)
let gacha_grid : @ui.Style = @ui.css("mx=S3_5 mt=S4 gap=S2")

///|
// kept across runs: a value (no field of it changes)
let gacha_row : @ui.Style = @ui.css("row w=Full gap=S2 align=AStretch")

///|
// kept across runs: a value (no field of it changes)
let gacha_slot : @ui.Style = @ui.style(w=@sf.grow)

///|
/// A capsule's card: the paper warmed, round, a hard shadow the peach deeper; an SSR's in gold.
// kept across runs: a value (no field of it changes)
let gacha_cap : @ui.Style = @ui.css("w=Full h=Full pt=S1 pb=S2 px=S1_5 radius=Xl2 align=ACenter").then(
  @ui.style(bg=Data(gacha_cap_ground), shadow=Cast(sb_sharp, sb_lift, gacha_cap_edge)),
)

///|
// kept across runs: a value (no field of it changes)
let gacha_cap_ssr : @ui.Style = gacha_cap.then(
  @ui.css("border=B2").then(
    @ui.style(bg=Data(gacha_ssr_ground), border_color=Data(gacha_ssr_ring), shadow=Cast(sb_sharp, sb_lift, gacha_ssr_edge)),
  ),
)

///|
let gacha_cap_ground : Int64 = 0xFFFAF6FFL

///|
let gacha_cap_edge : Int64 = 0xF2B79FFFL

///|
let gacha_ssr_ground : Int64 = 0xFFF9E9FFL

///|
let gacha_ssr_ring : Int64 = 0xF5C542FFL

///|
let gacha_ssr_edge : Int64 = 0xE0A43AFFL

///|
/// The SSR's shine round its card: the gold at a fifth 4 out, at a tenth 9 out.
// kept across runs: a value (no field of it changes)
let gacha_glow_near : @ui.Style = @ui.css("radius=Xl3").then(@ui.style(bg=Data(gacha_glow_near_ink)))

///|
// kept across runs: a value (no field of it changes)
let gacha_glow_far : @ui.Style = @ui.css("radius=Xl3").then(@ui.style(bg=Data(gacha_glow_far_ink)))

///|
let gacha_glow_near_w : Double = 4.0

///|
let gacha_glow_far_w : Double = 9.0

///|
let gacha_glow_near_ink : Int64 = 0xFFD45E4DL

///|
let gacha_glow_far_ink : Int64 = 0xFFD45E26L

///|
/// Rarity by tokens: SSR from 1 亿, SR from 1000 万.
let gacha_ssr_from : Double = 100000000.0

///|
let gacha_sr_from : Double = 10000000.0

///|
// kept across runs: a table, never written
let gacha_rare_keys : Array[String] = ["r", "sr", "ssr"]

///|
/// R's sky, SR's violet, SSR's gold (their gradients' middles).
// kept across runs: a table, never written
let gacha_rare_grounds : Array[Int64] = [0x6FB6E6FFL, 0x9F76E5FFL, 0xF5A63BFFL]

///|
let gacha_rare_in : Double = 7.0

///|
// kept across runs: a value (no field of it changes)
let gacha_rare : @ui.Style = @ui.css("px=S1_5 pt=S0_5 radius=Md")

///|
// kept across runs: a value (no field of it changes)
let gacha_rare_words : @ui.TextStyle = @ui.text_style(size=Xs, weight=Bold, tracking=@sf.share_letters_apart, color=Data(gacha_paper), wrap=false)

///|
/// The SSR's sparkles (left, top, size), the gold.
// kept across runs: a table, never written
let gacha_sparkles : Array[(Double, Double, Double)] = [(76.0, 6.0, 1.0), (66.0, 38.0, 0.7), (12.0, 44.0, 0.8)]

///|
// kept across runs: a value (no field of it changes)
let gacha_sparkle : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(gacha_sparkle_ink), wrap=false)

///|
let gacha_sparkle_ink : Int64 = 0xF5B82EFFL

///|
/// The balls' tops, in the capsules' order.
// kept across runs: a table, never written
let gacha_tops : Array[Int64] = [0xF6C544FFL, 0xB88AF0FFL, 0x7EC8F2FFL, 0x8FDCB0FFL, 0xF7A1BFFFL, 0xF5DF6EFFL]

///|
/// A ball 46 across in a box 62 (its SSR's ring 4 and shine 4 round it), its edge 2.5, its line 3, its shine an oval
/// up and left of its middle, turned 25°.
let gacha_ball_box : Double = 62.0

///|
let gacha_ball_r : Double = 23.0

///|
let gacha_edge_w : Double = 2.5

///|
let gacha_line_h : Double = 3.0

///|
let gacha_ring_w : Double = 4.0

///|
let gacha_glow_w : Double = 4.0

///|
let gacha_ring_ink : Int64 = 0xFFF3C4FFL

///|
let gacha_glow_ink : Int64 = 0xFFD45E66L

///|
let gacha_shine : Int64 = 0xFFFFFFCCL

///|
let gacha_shine_x : Double = 5.5

///|
let gacha_shine_y : Double = 10.0

///|
let gacha_shine_rx : Double = 6.0

///|
let gacha_shine_ry : Double = 3.5

///|
// kept across runs: a value (no field of it changes)
let gacha_shine_turn : (Double, Double) = (0.906, -0.423)

///|
let gacha_name_scale : Double = 1.0

///|
// kept across runs: a value (no field of it changes)
let gacha_name : @ui.TextStyle = @ui.text_style(size=Xs, weight=Bold, color=Data(gacha_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let gacha_tokens : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, color=Data(gacha_tokens_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let gacha_tokens_ssr : @ui.TextStyle = gacha_tokens.then(@ui.text_style(color=Data(gacha_tokens_gold)))

///|
let gacha_tokens_ink : Int64 = 0xD2452FFFL

///|
let gacha_tokens_gold : Int64 = 0xC76A00FFL

///|
// kept across runs: a value (no field of it changes)
let gacha_cost : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(gacha_cost_ink), wrap=false)

///|
let gacha_cost_ink : Int64 = 0xA0675AFFL

///|
/// Her line: the paper, round, 16 in, 14 under the capsules, its tail 46 in.
// kept across runs: a value (no field of it changes)
let gacha_say : @ui.Style = @ui.css("mx=S4 mt=S3_5 px=S4 pt=S3 pb=S3 radius=Xl2 gap=S0_5").then(
  @ui.style(bg=Data(gacha_paper), shadow=Cast(sb_sharp, sb_lift, gacha_cap_edge)),
)

///|
// kept across runs: a value (no field of it changes)
let gacha_who : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(gacha_pink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let gacha_say_words : @ui.TextStyle = @ui.text_style(size=Lg, leading=L6, color=Data(gacha_say_ink), w=Full)

///|
let gacha_say_ink : Int64 = 0x4A2418FFL

///|
/// What the pulls cost: a pill of the paper thinned, in a white edge; the chats still pulling a button at its end.
// kept across runs: a value (no field of it changes)
let gacha_bill : @ui.Style = @ui.css("row mx=S4 mt=S3 pl=S4 pr=S2 py=S2 gap=S2_5 radius=Full border=B1_5 align=ACenter").then(
  @ui.style(bg=Data(gacha_bill_ground), border_color=Data(gacha_paper)),
)

///|
let gacha_bill_ground : Int64 = 0xFFFFFFB3L

///|
// kept across runs: a value (no field of it changes)
let gacha_bill_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(gacha_bill_ink), wrap=false)

///|
let gacha_bill_ink : Int64 = 0x8A4A36FFL

///|
// kept across runs: a value (no field of it changes)
let gacha_bill_cost : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Bold, color=Data(gacha_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let gacha_button : @ui.Style = @ui.css("px=S3_5 py=S1_5 radius=Full").then(
  @ui.style(bg=Data(gacha_ribbon_ink), shadow=Cast(sb_sharp, gacha_button_lift, gacha_ribbon_edge)),
)

///|
let gacha_button_lift : Double = 2.0

///|
// kept across runs: a value (no field of it changes)
let gacha_button_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(gacha_paper), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let gacha_foot : @ui.Style = sb_foot.then(@ui.css("gap=S2_5 px=S5 pt=S3 pb=S4"))

///|
// kept across runs: a value (no field of it changes)
let gacha_brand : @ui.TextStyle = @ui.text_style(size=Base, weight=Bold, color=Data(gacha_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let gacha_small : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(gacha_small_ink), wrap=false)

///|
let gacha_small_ink : Int64 = 0xA0523AFFL

// ── 穗织全员 Q 版 ────────────────────────────────────────────────────────

///|
/// All six in chibi, in a row (丛雨 芳乃 茉子 蕾娜 小春 芦花), each her name on a tag under her; a banner (all of Hoori,
/// here this week) over the week's tokens and the days of it worked; under it a card each, her name in her colours
/// and one figure in her voice: 丛雨 the top model's tokens and cost, 芳乃 the chats archived, 茉子 the tasks across
/// devices, 蕾娜 the devices, 小春 the chats at work, 芦花 the week's cost. still.fail's line and when.
fn sr_chibi(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = sr_args(fleet)
  let key = "web-main.stations.shareSenren.chibi."
  sr_box(c, id, flat, chibi_ground, fn() {
    c.box(style=chibi_hero, fn() {
      sr_art(c, "b5-chibi-group", @sf.share_w_most, chibi_art_h, at=chibi_art_at) |> ignore
      c.box(style=chibi_brand_chip, left=chibi_brand_left, top=chibi_brand_top, fn() { sr_brand(c, chibi_brand) })
      |> ignore
      for i, who in sb_six {
        let (tag_bg, tag_ink, tag_edge, _, _, _) = chibi_colors[i]
        c.box(style=chibi_tag_slot, left=chibi_tag_x[i] - chibi_tag_w / 2.0, top=chibi_tag_top, fn() {
          c.box(style=chibi_tag.then(@ui.style(bg=Data(tag_bg), border_color=Data(tag_edge))), fn() {
            sr_words(c, sb_name(who), chibi_tag_words.then(@ui.text_style(color=Data(tag_ink))))
          })
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
    c.box(style=sb_middle, fn() {
      c.box(style=chibi_banner, fn() {
        sr_rich(
          c,
          [
            @ui.span(@sf.t(key + "banner1")),
            @ui.span("·", color=chibi_banner_dot),
            @ui.span(@sf.t(key + "banner2")),
          ],
          chibi_banner_words,
        )
      })
      |> ignore
    })
    |> ignore
    c.box(style=sb_middle_below, fn() { sr_rich(c, sb_said(key + "sub", args, chibi_dim, bold=false), chibi_sub) }) |> ignore
    let cost = sr_arg(args, "cost")
    c.box(style=chibi_grid, fn() {
      for row in 0..<2 {
        c.box(style=chibi_row, fn() {
          for k in 0..<3 {
            let i = row * 3 + k
            let p = chibi_colors[i]
            let ink = p.5
            let figure = match i {
              0 => sb_figure(sr_arg(args, "tokens"), ink, chibi_v_scale)
              1 => sb_figure(sr_arg(args, "archived"), ink, chibi_v_scale)
              2 => sb_said(key + "makoV", args, ink, scale=chibi_v_scale)
              3 => sb_said(key + "lenaV", args, ink, scale=chibi_v_scale)
              4 => sb_said(key + "koharuV", args, ink, scale=chibi_v_scale)
              _ => sb_figure(sr_arg(args, "weekCost"), ink, chibi_v_scale)
            }
            let (name_bg, name_ink, name_edge, card_edge, card_cast, _) = p
            c.box(style=chibi_card.then(@ui.style(border_color=Data(card_edge), shadow=Cast(sb_sharp, sb_lift, card_cast))), fn() {
              c.box(style=chibi_name.then(@ui.style(bg=Data(name_bg), border_color=Data(name_edge))), fn() {
                sr_words(c, sb_name(sb_six[i]), chibi_name_words.then(@ui.text_style(color=Data(name_ink))))
              })
              |> ignore
              sr_rich(c, figure, chibi_v.then(@ui.text_style(color=Data(ink))))
              sr_words(c, @sf.t(key + sb_six[i] + "Line"), chibi_line)
              if i == 0 {
                sr_words(c, @sf.t(key + "murasameMore", args=[("cost", cost)]), chibi_more)
              }
            })
            |> ignore
          }
        })
        |> ignore
      }
    })
    |> ignore
    c.box(style=chibi_foot, fn() {
      sr_words(c, @sf.t("web-main.stations.shareTagline"), chibi_small)
      c.box(style=sb_grow, fn() {  }) |> ignore
      sr_words(c, sr_arg(args, "at"), chibi_small)
    })
    |> ignore
  })
}

///|
/// The cream under the six and its ink.
let chibi_ground : Int64 = 0xFCF1E9FFL

///|
let chibi_ink : Int64 = 0x4A3328FFL

///|
let chibi_dim : Int64 = 0xA07A5EFFL

///|
let chibi_art_h : Double = 232.0

///|
let chibi_art_at : Double = 0.35

///|
/// The picture, the banner over its last 10.
// kept across runs: a value (no field of it changes)
let chibi_hero : @ui.Style = @ui.style(w=Full, h=Fixed(chibi_hero_h))

///|
let chibi_hero_h : Double = 222.0

///|
let chibi_brand_left : Double = 14.0

///|
let chibi_brand_top : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let chibi_brand_chip : @ui.Style = @ui.css("px=S3 py=S1 radius=Full").then(@ui.style(bg=Data(chibi_brand_ground)))

///|
let chibi_brand_ground : Int64 = 0xFFFFFFCCL

///|
// kept across runs: a value (no field of it changes)
let chibi_brand : @ui.TextStyle = @ui.text_style(size=Base, weight=Bold, color=Data(chibi_ink), wrap=false)

///|
/// Each heroine's colours: her tag's ground, its words, its ring; her card's edge, its shadow; her figure's.
// kept across runs: a table, never written
let chibi_colors : Array[(Int64, Int64, Int64, Int64, Int64, Int64)] = [
  (0xC8F0DCFFL, 0x1F7A58FFL, 0x7FD9B3FFL, 0xD9F5E8FFL, 0xA8E2C9FFL, 0x1F7A58FFL),
  (0xD8364FFFL, 0xFFFFFFFFL, 0xFFFFFFFFL, 0xFBE1E5FFL, 0xF2B2BDFFL, 0xB52A40FFL),
  (0x2C3D78FFL, 0xFFFFFFFFL, 0x2C3D78FFL, 0xE1E5F3FFL, 0xB4BEDEFFL, 0x2C3D78FFL),
  (0x8352C4FFL, 0xFFFFFFFFL, 0xE2B33CFFL, 0xEFE5FAFFL, 0xD2BDF0FFL, 0x6C3FAEFFL),
  (0xFFD0E1FFL, 0xD23F78FFL, 0xF58FB5FFL, 0xFFE6EFFFL, 0xF7BCD2FFL, 0xD23F78FFL),
  (0x9B2747FFL, 0xFFFFFFFFL, 0x9B2747FFL, 0xF6E0E6FFL, 0xE1B0BDFFL, 0x8A1F3DFFL),
]

///|
/// Where each stands in the picture (her middle, from its left) and her tag under her, 190 down.
// kept across runs: a table, never written
let chibi_tag_x : Array[Double] = [36.0, 91.8, 147.6, 207.0, 264.6, 324.0]

///|
let chibi_tag_top : Double = 190.0

///|
let chibi_tag_w : Double = 56.0

///|
// kept across runs: a value (no field of it changes)
let chibi_tag_slot : @ui.Style = @ui.css("align=ACenter").then(@ui.style(w=Fixed(chibi_tag_w)))

///|
// kept across runs: a value (no field of it changes)
let chibi_tag : @ui.Style = @ui.css("px=S2 radius=Full border=B1")

///|
// kept across runs: a value (no field of it changes)
let chibi_tag_words : @ui.TextStyle = @ui.text_style(size=Xs2, weight=Bold, color=Data(chibi_ink), wrap=false)

///|
/// The banner: a white pill, a hard shadow the cream deeper.
// kept across runs: a value (no field of it changes)
let chibi_banner : @ui.Style = @ui.css("px=S5 pt=S1_5 pb=S2 radius=Full").then(
  @ui.style(bg=Data(chibi_paper), shadow=Cast(sb_sharp, sb_lift, chibi_banner_edge)),
)

///|
let chibi_paper : Int64 = 0xFFFFFFFFL

///|
let chibi_banner_edge : Int64 = 0xF0CFA8FFL

///|
let chibi_banner_dot : Int64 = 0xE0567CFFL

///|
// kept across runs: a value (no field of it changes)
let chibi_banner_words : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, tracking=Widest, color=Data(chibi_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let chibi_sub : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(chibi_dim), wrap=false)

///|
/// The cards: three across, 9 apart (8), 13 in (12), 13 under the line over them.
// kept across runs: a value (no field of it changes)
let chibi_grid : @ui.Style = @ui.css("mx=S3 mt=S3 gap=S2")

///|
// kept across runs: a value (no field of it changes)
let chibi_row : @ui.Style = @ui.css("row w=Full gap=S2 align=AStretch")

///|
/// A card: white, round, its edge and shadow her colours.
// kept across runs: a value (no field of it changes)
let chibi_card : @ui.Style = @ui.css("p=S2_5 radius=Xl2 border=B2 align=AStart").then(
  @ui.style(w=@sf.grow, bg=Data(chibi_paper)),
)

///|
// kept across runs: a value (no field of it changes)
let chibi_name : @ui.Style = @ui.css("px=S2 radius=Md border=B1")

///|
// kept across runs: a value (no field of it changes)
let chibi_name_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, tracking=Wider, color=Data(chibi_ink), wrap=false)

///|
/// Her figure 23 high, what it counts 13.
// kept across runs: a value (no field of it changes)
let chibi_v : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(chibi_ink), wrap=false)

///|
let chibi_v_scale : Double = 1.75

///|
// kept across runs: a value (no field of it changes)
let chibi_line : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(chibi_line_ink), w=Full)

///|
let chibi_line_ink : Int64 = 0x5E4638FFL

///|
// kept across runs: a value (no field of it changes)
let chibi_more : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(chibi_more_ink), w=Full)

///|
let chibi_more_ink : Int64 = 0x8C7364FFL

///|
// kept across runs: a value (no field of it changes)
let chibi_foot : @ui.Style = sb_foot.then(@ui.css("px=S4_5 pt=S4 pb=S4"))

///|
// kept across runs: a value (no field of it changes)
let chibi_small : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(chibi_dim), wrap=false)

// ── the festival's photo ─────────────────────────────────────────────────

///|
/// The summer festival's photo: on the night, all six in yukata under the fireworks in a polaroid, taped up, its
/// caption the day and the week's tokens; on its back each one's note in her colour and voice (丛雨 the top model's
/// tokens, 芳乃 the chats archived, 茉子 the tasks across devices, 蕾娜 the devices, 小春 the chats at work, 芦花 the
/// week's cost); still.fail and its line.
fn sr_photo(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = sr_args(fleet)
  let key = "web-main.stations.shareSenren.photo."
  sr_box(c, id, flat, photo_ground, fn() {
    for d in photo_sparks {
      let (x, y, across, ink) = d
      c.box(style=@ui.style(w=Fixed(across), h=Fixed(across), radius=Full, bg=Data(ink)), left=x, top=y, fn() {  }) |> ignore
    }
    c.box(style=photo_head, fn() {
      sr_rich(c, [@ui.span(@sf.t(key + "title"), scale=photo_title_scale)], photo_title)
      c.box(style=photo_lead, fn() { sr_words(c, @sf.t(key + "back"), photo_back) }) |> ignore
    })
    |> ignore
    c.box(style=photo_middle, fn() {
      c.box(style=photo_polaroid, fn() {
        sr_art(c, "h1-group-festival", photo_art_w, photo_art_h, at=photo_art_at) |> ignore
        c.box(style=photo_cap, fn() {
          c.box(style=photo_lead, fn() {
            sr_rich(c, sb_said(key + "date", [("date", sb_date(sr_arg(args, "at")))], photo_cap_ink, bold=false), photo_date)
          })
          |> ignore
          sr_rich(c, sb_said(key + "week", args, photo_pink, scale=photo_week_scale), photo_week)
        })
        |> ignore
        // the tapes over its top corners
        for t in photo_tapes {
          c.box(left=t.0 - photo_tape_box_w / 2.0, top=t.1 - photo_tape_box_h / 2.0, fn() {
            c.shapes(photo_tape(t.2, t.3), w=Px(photo_tape_box_w), h=Px(photo_tape_box_h)) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
    c.box(style=photo_notes, fn() {
      for row in 0..<3 {
        c.box(style=photo_row, fn() {
          for k in 0..<2 {
            let i = row * 2 + k
            let (ground, ink) = photo_inks[i]
            c.box(style=photo_note.then(@ui.style(bg=Data(ground))), fn() {
              sr_words(c, sb_name(sb_six[i]), photo_who.then(@ui.text_style(color=Data(ink))))
              sr_rich(c, sb_said(key + sb_six[i], args, ink, scale=photo_note_scale), photo_note_words)
            })
            |> ignore
          }
        })
        |> ignore
      }
    })
    |> ignore
    c.box(style=photo_foot, fn() {
      sr_brand(c, photo_brand)
      c.box(style=sb_grow, fn() {  }) |> ignore
      sr_words(c, @sf.t("web-main.stations.shareTagline"), photo_small)
    })
    |> ignore
  })
}

///|
/// A strip of tape `turn`ed (its cos and sin) about the middle of its box, in `ink`.
fn photo_tape(turn : (Double, Double), ink : Int64) -> Array[@ui.Shape] {
  let cx = photo_tape_box_w / 2.0
  let cy = photo_tape_box_h / 2.0
  let w = photo_tape_w / 2.0
  let h = photo_tape_h / 2.0
  let strip = [cx - w, cy - h, cx + w, cy - h, cx + w, cy + h, cx - w, cy + h]
  [@ui.shape_of(sb_turned([(strip, true)], cx, cy, turn), fill=ink)]
}

///|
/// The festival's night and the words on it.
let photo_ground : Int64 = 0x1D1630FFL

///|
let photo_ink : Int64 = 0xFFFFFFFFL

///|
/// The festival's lights in the night (left, top, across, colour).
// kept across runs: a table, never written
let photo_sparks : Array[(Double, Double, Double, Int64)] = [
  (53.0, 68.0, 3.0, 0xFFD36B55L),
  (293.0, 103.0, 4.0, 0xFF9EC455L),
  (251.0, 34.0, 3.0, 0xA8F0CF55L),
  (330.0, 260.0, 3.0, 0xFFD36B44L),
]

///|
// kept across runs: a value (no field of it changes)
let photo_head : @ui.Style = @ui.css("row w=Full gap=S2 align=AEnd px=S5 pt=S5")

///|
// kept across runs: a value (no field of it changes)
let photo_title : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, tracking=Wider, color=Data(photo_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let photo_back : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(photo_back_ink), w=Full, max_lines=sb_two_lines)

///|
/// What is left beside the title (its second words) or beside the week (the caption's date): wrapped there if need be.
// kept across runs: a value (no field of it changes)
let photo_lead : @ui.Style = @ui.style(w=@sf.grow)

///|
let photo_back_ink : Int64 = 0xC9B8F0FFL

///|
let photo_title_scale : Double = 1.18

///|
// kept across runs: a value (no field of it changes)
let photo_middle : @ui.Style = @ui.css("w=Full align=ACenter pt=S6")

///|
/// The polaroid: 322 across, its white warmed, 11 in round the picture, deep in the night's shadow.
// kept across runs: a value (no field of it changes)
let photo_polaroid : @ui.Style = @ui.css("pt=S3 px=S3 radius=Sm").then(
  @ui.style(w=Fixed(photo_polaroid_w), bg=Data(photo_paper), shadow=Cast(photo_shadow_blur, photo_shadow_y, photo_shadow)),
)

///|
let photo_polaroid_w : Double = 322.0

///|
let photo_paper : Int64 = 0xFFFDF7FFL

///|
let photo_shadow_blur : Double = 15.0

///|
let photo_shadow_y : Double = 14.0

///|
let photo_shadow : Int64 = 0x00000099L

///|
let photo_art_w : Double = 298.0

///|
let photo_art_h : Double = 200.0

///|
let photo_art_at : Double = 0.3

///|
// kept across runs: a value (no field of it changes)
let photo_cap : @ui.Style = @ui.css("row w=Full align=AEnd px=S1 pt=S2 pb=S3")

///|
let photo_cap_ink : Int64 = 0x3A2F4AFFL

///|
let photo_pink : Int64 = 0xE0508AFFL

///|
// kept across runs: a value (no field of it changes)
let photo_date : @ui.TextStyle = @ui.text_style(size=Lg, color=Data(photo_cap_ink), w=Full, max_lines=sb_two_lines)

///|
// kept across runs: a value (no field of it changes)
let photo_week : @ui.TextStyle = @ui.text_style(size=Base, color=Data(photo_pink), wrap=false)

///|
let photo_week_scale : Double = 1.3

///|
/// The tapes: 74 by 22 each, the left one's middle 23 in and 1 down turned back 28°, the right one's 24° on.
// kept across runs: a table, never written
let photo_tapes : Array[(Double, Double, (Double, Double), Int64)] = [
  (23.0, 1.0, (0.883, -0.469), 0xFFE7A8C9L),
  (299.0, 1.0, (0.914, 0.407), 0xB9F0DCC9L),
]

///|
let photo_tape_w : Double = 74.0

///|
let photo_tape_h : Double = 22.0

///|
let photo_tape_box_w : Double = 80.0

///|
let photo_tape_box_h : Double = 60.0

///|
/// The notes on its back: two across, 10 apart, 18 in, 22 under it.
// kept across runs: a value (no field of it changes)
let photo_notes : @ui.Style = @ui.css("mx=S4_5 mt=S5 gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let photo_row : @ui.Style = @ui.css("row w=Full gap=S2_5 align=AStretch")

///|
// kept across runs: a value (no field of it changes)
let photo_note : @ui.Style = @ui.css("px=S2_5 pt=S2 pb=S2_5 radius=Base gap=S0_5").then(
  @ui.style(w=@sf.grow, shadow=Cast(photo_note_blur, photo_note_y, photo_note_shadow)),
)

///|
let photo_note_blur : Double = 5.0

///|
let photo_note_y : Double = 4.0

///|
let photo_note_shadow : Int64 = 0x00000066L

///|
/// Each one's note: its paper, her ink.
// kept across runs: a table, never written
let photo_inks : Array[(Int64, Int64)] = [
  (0xD9F7E8FFL, 0x2F8A5FFFL),
  (0xFDE4E8FFL, 0xC8283AFFL),
  (0xE3E8FBFFL, 0x2B3A78FFL),
  (0xF0E6FFFFL, 0x7A4FC0FFL),
  (0xFFE3EFFFL, 0xE0508AFFL),
  (0xFBE3E6FFL, 0x8F2440FFL),
]

///|
// kept across runs: a value (no field of it changes)
let photo_who : @ui.TextStyle = @ui.text_style(size=Xs2, weight=Bold, color=Data(photo_note_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let photo_note_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L4_75, color=Data(photo_note_ink), w=Full)

///|
let photo_note_ink : Int64 = 0x2E2438FFL

///|
let photo_note_scale : Double = 1.15

///|
// kept across runs: a value (no field of it changes)
let photo_foot : @ui.Style = sb_foot.then(@ui.css("px=S5 pt=S4_5 pb=S4"))

///|
// kept across runs: a value (no field of it changes)
let photo_brand : @ui.TextStyle = @ui.text_style(size=Base, weight=Bold, color=Data(photo_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let photo_small : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(photo_small_ink), wrap=false)

///|
let photo_small_ink : Int64 = 0xA898C8FFL

// ── the sweets party ─────────────────────────────────────────────────────

///|
/// The sweets party at the 甘味处: all six round a table of sweets; under it the bill (御会计), a line each, the models
/// by tokens each a heroine's order (丛雨 the matcha parfait …), its model and tokens under it, its cost at its end; the
/// week's total large, a stamp asking who pays; 芦花's line (she treats today… wait, how much?!); still.fail's line and
/// when.
fn sr_party(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = sr_args(fleet)
  let key = "web-main.stations.shareSenren.party."
  let ranked = sb_ranked(fleet)
  sr_box(c, id, flat, party_ground, fn() {
    // the wood's grain, a faint line every 46
    for i in 0..<party_grains {
      c.box(style=party_grain, left=i.to_double() * party_grain_apart, top=0.0, bottom=0.0, fn() {  }) |> ignore
    }
    c.box(style=party_hero, fn() {
      sr_art(c, "h2-group-sweets", @sf.share_w_most, party_art_h, at=party_art_at) |> ignore
      c.box(style=party_brand_chip, left=party_chip_in, top=party_chip_in, fn() { sr_brand(c, party_brand) }) |> ignore
      c.box(style=party_title_chip, right=party_title_right, top=party_chip_in, fn() {
        sr_words(c, @sf.t(key + "title"), party_title)
      })
      |> ignore
    })
    |> ignore
    c.box(style=party_slip, fn() {
      c.box(style=party_slip_top, fn() {  }) |> ignore
      c.box(style=party_slip_in, fn() {
        sr_words(c, @sf.t(key + "bill"), party_bill)
        for i, m in ranked {
          c.box(style=party_line, fn() {
            c.box(style=party_who_box, fn() { sr_words(c, sb_name(sb_six[i % sb_six.length()]), party_who) }) |> ignore
            c.box(style=sb_grow, fn() {
              sr_words(c, @sf.t(key + "sweet" + (i % sb_six.length() + 1).to_string()), party_what)
              sr_words(c, @sf.t(key + "order", args=[("model", m.0), ("tokens", m.2)]), party_order)
            })
            |> ignore
            sr_words(c, m.3, party_price)
          })
          |> ignore
          c.box(style=party_dashes, fn() {
            for _ in 0..<party_dash_count {
              c.box(style=party_dash, fn() {  }) |> ignore
            }
          })
          |> ignore
        }
        c.box(style=party_total, fn() {
          sr_words(c, @sf.t(key + "total"), party_total_words)
          c.box(style=sb_grow, fn() {  }) |> ignore
          sr_words(c, sr_arg(args, "weekCost"), party_total_cost)
        })
        |> ignore
      })
      |> ignore
      c.box(style=party_hanko, left=party_hanko_left, bottom=party_hanko_bottom, fn() {
        sr_words(c, @sf.t(key + "hanko1"), party_hanko_words)
        sr_words(c, @sf.t(key + "hanko2"), party_hanko_words)
      })
      |> ignore
    })
    |> ignore
    c.box(style=party_say, fn() {
      c.box(style=party_say_chip, fn() { sr_words(c, sb_name("roka"), party_say_who) }) |> ignore
      c.box(style=sb_grow, fn() { sr_rich(c, sb_said(key + "say", args, party_ink), party_say_words) }) |> ignore
    })
    |> ignore
    c.box(style=party_foot, fn() {
      sr_words(c, @sf.t("web-main.stations.shareTagline"), party_small)
      c.box(style=sb_grow, fn() {  }) |> ignore
      sr_words(c, sr_arg(args, "at"), party_small)
    })
    |> ignore
  })
}

///|
/// The shop's wood and the ink on it.
let party_ground : Int64 = 0xE9D4B6FFL

///|
let party_ink : Int64 = 0x3A2A1EFFL

///|
let party_dim : Int64 = 0x8A6A52FFL

///|
let party_grains : Int = 8

///|
let party_grain_apart : Double = 46.0

///|
// kept across runs: a value (no field of it changes)
let party_grain : @ui.Style = @ui.style(w=Fixed(party_grain_w), bg=Data(party_grain_ink))

///|
let party_grain_w : Double = 2.0

///|
let party_grain_ink : Int64 = 0x0000000AL

///|
let party_art_h : Double = 240.0

///|
let party_art_at : Double = 0.35

///|
/// The picture, the bill over its last 26.
// kept across runs: a value (no field of it changes)
let party_hero : @ui.Style = @ui.style(w=Full, h=Fixed(party_hero_h))

///|
let party_hero_h : Double = 214.0

///|
let party_chip_in : Double = 12.0

///|
let party_title_right : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let party_brand_chip : @ui.Style = @ui.css("px=S2_5 py=S1 radius=Full").then(@ui.style(bg=Data(party_brand_ground)))

///|
let party_brand_ground : Int64 = 0x3A2A1ECCL

///|
// kept across runs: a value (no field of it changes)
let party_brand : @ui.TextStyle = @ui.text_style(size=Base, weight=Bold, color=Data(party_paper), wrap=false)

///|
let party_paper : Int64 = 0xFFFFFFFFL

///|
// kept across runs: a value (no field of it changes)
let party_title_chip : @ui.Style = @ui.css("px=S2_5 py=S1 radius=Full").then(
  @ui.style(bg=Data(party_title_ground), shadow=Cast(party_chip_blur, party_chip_y, party_chip_shadow)),
)

///|
let party_title_ground : Int64 = 0xB8452EE6L

///|
let party_chip_blur : Double = 4.0

///|
let party_chip_y : Double = 2.0

///|
let party_chip_shadow : Int64 = 0x00000055L

///|
// kept across runs: a value (no field of it changes)
let party_title : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(party_paper), wrap=false)

///|
/// The bill: a slip of paper 22 in, its top edge the shop's red, in its shadow.
// kept across runs: a value (no field of it changes)
let party_slip : @ui.Style = @ui.css("mx=S5").then(
  @ui.style(bg=Data(party_slip_paper), shadow=Cast(party_slip_blur, party_slip_y, party_slip_shadow)),
)

///|
let party_slip_paper : Int64 = 0xFFFDF6FFL

///|
let party_slip_blur : Double = 10.0

///|
let party_slip_y : Double = 8.0

///|
let party_slip_shadow : Int64 = 0x5A3A1A40L

///|
// kept across runs: a value (no field of it changes)
let party_slip_top : @ui.Style = @ui.style(w=Full, h=Fixed(party_slip_edge), bg=Data(party_red))

///|
let party_slip_edge : Double = 4.0

///|
let party_red : Int64 = 0xB8452EFFL

///|
// kept across runs: a value (no field of it changes)
let party_slip_in : @ui.Style = @ui.css("w=Full px=S4 pt=S3_5 pb=S3")

///|
// kept across runs: a value (no field of it changes)
let party_bill : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, tracking=Widest, color=Data(party_ink), wrap=false)

///|
/// A line of the bill: who, what (its model and tokens under it), the price at its end.
// kept across runs: a value (no field of it changes)
let party_line : @ui.Style = @ui.css("row w=Full gap=S2 py=S2 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let party_who_box : @ui.Style = @ui.style(min_w=Fixed(party_who_w))

///|
let party_who_w : Double = 34.0

///|
// kept across runs: a value (no field of it changes)
let party_who : @ui.TextStyle = @ui.text_style(size=Base, weight=Bold, color=Data(party_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let party_what : @ui.TextStyle = @ui.text_style(size=Base, color=Data(party_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let party_order : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(party_dim), w=Full)

///|
// kept across runs: a value (no field of it changes)
let party_price : @ui.TextStyle = @ui.text_style(size=Xl, weight=Bold, color=Data(party_ink), wrap=false)

///|
/// The dashes under a line, the wood paler.
// kept across runs: a value (no field of it changes)
let party_dashes : @ui.Style = @ui.css("row w=Full gap=S1")

///|
let party_dash_count : Int = 40

///|
// kept across runs: a value (no field of it changes)
let party_dash : @ui.Style = @ui.style(w=@sf.grow, h=Fixed(party_dash_h), bg=Data(party_dash_ink))

///|
let party_dash_h : Double = 1.0

///|
let party_dash_ink : Int64 = 0xD9C6AEFFL

///|
// kept across runs: a value (no field of it changes)
let party_total : @ui.Style = @ui.css("row w=Full pt=S2_5 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let party_total_words : @ui.TextStyle = @ui.text_style(size=Base, color=Data(party_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let party_total_cost : @ui.TextStyle = @ui.text_style(size=Xl4, weight=Bold, color=Data(party_red), wrap=false)

///|
/// The stamp: a red ring 44 across, 132 in, 6 over the slip's foot, asking who pays.
let party_hanko_left : Double = 132.0

///|
let party_hanko_bottom : Double = 6.0

///|
// kept across runs: a value (no field of it changes)
let party_hanko : @ui.Style = @ui.css("radius=Full border=B2 align=ACenter justify=JCenter").then(
  @ui.style(w=Fixed(party_hanko_w), h=Fixed(party_hanko_w), border_color=Data(party_hanko_ink)),
)

///|
let party_hanko_w : Double = 44.0

///|
let party_hanko_ink : Int64 = 0xC8283AD9L

///|
// kept across runs: a value (no field of it changes)
let party_hanko_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, leading=L4, color=Data(party_hanko_ink), wrap=false)

///|
/// 芦花's line: her name on her wine red, what she says beside it.
// kept across runs: a value (no field of it changes)
let party_say : @ui.Style = @ui.css("row mx=S5 mt=S4 gap=S2_5 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let party_say_chip : @ui.Style = @ui.css("px=S2 py=S0_5 radius=Full mt=S0_5").then(@ui.style(bg=Data(party_wine)))

///|
let party_wine : Int64 = 0x8F2440FFL

///|
// kept across runs: a value (no field of it changes)
let party_say_who : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(party_paper), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let party_say_words : @ui.TextStyle = @ui.text_style(size=Lg, leading=L6, color=Data(party_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let party_foot : @ui.Style = sb_foot.then(@ui.css("px=S5 pt=S3_5 pb=S4"))

///|
// kept across runs: a value (no field of it changes)
let party_small : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(party_dim), wrap=false)

// ── after school ─────────────────────────────────────────────────────────

///|
/// After school at 鵜茅学院: the girls in the classroom at dusk; under it the blackboard in chalk: the day and who is on
/// duty (the top model), this week's homework (the chats archived), attendance (the days used of the week), make-up
/// class (the chats at work), the class fund (the week's cost, the top model's share of it), errands between rooms
/// (the tasks across devices); 丛雨's doodle in its corner (only Master sees her); the chalk tray; 芳乃's line (fewer
/// tokens next week, 有地さん); still.fail's line and when.
fn sr_class(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = sr_args(fleet)
  let key = "web-main.stations.shareSenren.class."
  let all = sr_days(fleet).length().to_string()
  let said = [("n", sr_num(sr_arg(args, "archived"))), ("all", all), ("date", sb_date(sr_arg(args, "at")))]
  for a in args {
    said.push(a)
  }
  sr_box(c, id, flat, class_ground, fn() {
    c.box(style=class_hero, fn() {
      sr_art(c, "h3-group-classroom", @sf.share_w_most, class_art_h, at=class_art_at) |> ignore
      c.box(style=class_chip, left=class_chip_left, top=class_chip_top, fn() {
        sr_words(c, @sf.t(key + "where"), class_chip_words)
      })
      |> ignore
      c.box(style=class_brand_chip, right=class_brand_right, top=class_brand_top, fn() { sr_brand(c, class_brand) })
      |> ignore
    })
    |> ignore
    c.box(style=class_board, fn() {
      c.box(style=class_date_row, fn() {
        sr_words(c, sr_arg(said, "date"), class_date)
        c.box(style=sb_grow, fn() {  }) |> ignore
        sr_rich(c, sb_said(key + "duty", said, class_gold, scale=class_duty_scale), class_date)
      })
      |> ignore
      sr_rich(c, sb_said(key + "homework", said, class_pink, scale=class_big_scale), class_big)
      c.box(style=class_list, fn() {
        let attend = [@ui.span("✓ ", color=class_mint)]
        for r in sb_said(key + "attend", said, class_gold, scale=class_list_scale) {
          attend.push(r)
        }
        sr_rich(c, attend, class_line)
        for name in ["makeup", "fund", "errands"] {
          sr_rich(c, sb_said(key + name, said, class_gold, scale=class_list_scale, plain=["model"]), class_line)
        }
      })
      |> ignore
      c.box(style=class_doodle, right=class_doodle_right, bottom=class_doodle_bottom, fn() {
        sr_words(c, @sf.t(key + "doodle1"), class_doodle_words)
        sr_words(c, @sf.t(key + "doodle2"), class_doodle_words)
      })
      |> ignore
    })
    |> ignore
    c.box(style=class_tray_row, fn() {
      c.box(style=class_tray, fn() {
        c.box(style=class_chalk_white, fn() {  }) |> ignore
        c.box(style=class_chalk_pink, fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
    c.box(style=class_say, fn() {
      sr_rich(c, [@ui.span(sb_name("yoshino") + "  ", color=class_pink), @ui.span(@sf.t(key + "say"))], class_say_words)
    })
    |> ignore
    c.box(style=class_foot, fn() {
      sr_words(c, @sf.t("web-main.stations.shareTagline"), class_small)
      c.box(style=sb_grow, fn() {  }) |> ignore
      sr_words(c, sr_arg(args, "at"), class_small)
    })
    |> ignore
  })
}

///|
/// The classroom's wood, dusk-dark, and the chalk.
let class_ground : Int64 = 0x48352AFFL

///|
let class_chalk : Int64 = 0xF4F1E8FFL

///|
let class_gold : Int64 = 0xFFE08AFFL

///|
let class_pink : Int64 = 0xFFB3C9FFL

///|
let class_mint : Int64 = 0xA8F0CFFFL

///|
let class_art_h : Double = 240.0

///|
let class_art_at : Double = 0.4

///|
/// The picture, the blackboard over its last 20.
// kept across runs: a value (no field of it changes)
let class_hero : @ui.Style = @ui.style(w=Full, h=Fixed(class_hero_h))

///|
let class_hero_h : Double = 220.0

///|
let class_chip_left : Double = 14.0

///|
let class_chip_top : Double = 13.0

///|
let class_brand_right : Double = 12.0

///|
let class_brand_top : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let class_chip : @ui.Style = @ui.css("px=S2_5 py=S1 radius=Full").then(@ui.style(bg=Data(class_chip_ground)))

///|
// kept across runs: a value (no field of it changes)
let class_brand_chip : @ui.Style = @ui.css("px=S2_5 py=S1 radius=Full").then(@ui.style(bg=Data(class_chip_ground)))

///|
let class_chip_ground : Int64 = 0x1F3B2CCCL

///|
// kept across runs: a value (no field of it changes)
let class_chip_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(class_white), wrap=false)

///|
let class_white : Int64 = 0xFFFFFFFFL

///|
// kept across runs: a value (no field of it changes)
let class_brand : @ui.TextStyle = @ui.text_style(size=Base, weight=Bold, color=Data(class_white), wrap=false)

///|
/// The blackboard: green in a wooden frame 8 thick, 12 in, room at its foot for the doodle; deep in its shadow.
// kept across runs: a value (no field of it changes)
let class_board : @ui.Style = @ui.css("mx=S3 px=S4 pt=S3_5 pb=S11 radius=Md border=B8 gap=S3").then(
  @ui.style(bg=Data(class_board_green), border_color=Data(class_frame), shadow=Cast(class_board_blur, class_board_y, class_board_shadow)),
)

///|
let class_board_green : Int64 = 0x26503EFFL

///|
let class_frame : Int64 = 0x8A5A32FFL

///|
let class_board_blur : Double = 12.0

///|
let class_board_y : Double = 10.0

///|
let class_board_shadow : Int64 = 0x00000088L

///|
// kept across runs: a value (no field of it changes)
let class_date_row : @ui.Style = @ui.css("row w=Full align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let class_date : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(class_date_ink), wrap=false)

///|
let class_date_ink : Int64 = 0xE8F0D8FFL

///|
let class_duty_scale : Double = 1.15

///|
// kept across runs: a value (no field of it changes)
let class_big : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Bold, tracking=@sf.share_letters_apart, color=Data(class_chalk), w=Full)

///|
let class_big_scale : Double = 1.3

///|
// kept across runs: a value (no field of it changes)
let class_list : @ui.Style = @ui.css("w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let class_line : @ui.TextStyle = @ui.text_style(size=Base, color=Data(class_chalk), w=Full)

///|
let class_list_scale : Double = 1.15

///|
let class_doodle_right : Double = 14.0

///|
let class_doodle_bottom : Double = 10.0

///|
// kept across runs: a value (no field of it changes)
let class_doodle : @ui.Style = @ui.css("align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let class_doodle_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(class_doodle_ink), wrap=false)

///|
let class_doodle_ink : Int64 = 0xF4F1E8CCL

///|
/// The chalk tray under the board: two sticks of chalk on it, white and pink.
// kept across runs: a value (no field of it changes)
let class_tray : @ui.Style = @ui.css("row w=Full pt=S0_5 radius=Sm").then(@ui.style(h=Fixed(class_tray_h), bg=Data(class_tray_ink)))

///|
/// The tray's own box: the card's width, the tray as far in from its edges as the board over it.
// kept across runs: a value (no field of it changes)
let class_tray_row : @ui.Style = @ui.css("w=Full px=S3")

///|
let class_tray_h : Double = 7.0

///|
let class_tray_ink : Int64 = 0x6A4428FFL

///|
// kept across runs: a value (no field of it changes)
let class_chalk_white : @ui.Style = @ui.css("ml=S4_5 radius=Sm").then(
  @ui.style(w=Fixed(class_chalk_long), h=Fixed(class_chalk_h), bg=Data(class_chalk)),
)

///|
// kept across runs: a value (no field of it changes)
let class_chalk_pink : @ui.Style = @ui.css("ml=S1_5 radius=Sm").then(
  @ui.style(w=Fixed(class_chalk_short), h=Fixed(class_chalk_h), bg=Data(class_pink)),
)

///|
let class_chalk_long : Double = 22.0

///|
let class_chalk_short : Double = 16.0

///|
let class_chalk_h : Double = 5.0

///|
// kept across runs: a value (no field of it changes)
let class_say : @ui.Style = @ui.css("mx=S5 mt=S3_5")

///|
// kept across runs: a value (no field of it changes)
let class_say_words : @ui.TextStyle = @ui.text_style(size=Base, color=Data(class_say_ink), w=Full)

///|
let class_say_ink : Int64 = 0xF3E6D8FFL

///|
// kept across runs: a value (no field of it changes)
let class_foot : @ui.Style = sb_foot.then(@ui.css("px=S5 pt=S3 pb=S3_5"))

///|
// kept across runs: a value (no field of it changes)
let class_small : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(class_small_ink), wrap=false)

///|
let class_small_ink : Int64 = 0xC8B39EFFL
