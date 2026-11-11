// 千恋＊万花's looks (share_senren.mbt): the game's own screens (the title, the CG gallery, the routes' affection, the
// girls' group chat, the staff roll) and 穂織's things (the sword's appraisal, the festival's lanterns, the map, the ema).
// Each as its mockup draws it (senren/cards/<mockup>.html), in what boxes, words, pictures and shapes do: a gradient is
// bands of a colour going from one to the other, a letter's white edge its words drawn again round them, a face a
// picture cut by where it is in it; nothing turned (no rotation here), nothing blended.

// ── what this file's looks share ─────────────────────────────────────────

///|
/// The figures the looks say (sr_args), and the week's chats archived as a number alone (57).
fn gc_args(fleet : Json?) -> Array[(String, String)] {
  let args = sr_args(fleet)
  args.push(("archivedN", sr_num(sr_arg(args, "archived"))))
  args
}

///|
/// What follows a figure in what is said of it (「57 个」: 个), its space left out; "" for none.
fn gc_unit(value : String) -> String {
  let b = StringBuilder()
  let mut seen = false
  let mut started = false
  for ch in value {
    if !started {
      if (ch >= '0' && ch <= '9') || ch == '.' || ch == ',' {
        seen = true
        continue
      }
      if !seen || ch == ' ' {
        continue
      }
      started = true
    }
    b.write_char(ch)
  }
  b.to_string()
}

///|
/// `rgb` at the opacity `a` (0 to 1): its own alpha replaced.
fn gc_alpha(rgb : Int64, a : Double) -> Int64 {
  let a = gc_clamp(a, 0.0, 1.0)
  (rgb & 0xFFFFFF00L) | (a * 255.0).round().to_int64()
}

///|
/// The colour `t` of the way from `a` to `b`, each of its four (red, green, blue, alpha) on its own.
fn gc_mix(a : Int64, b : Int64, t : Double) -> Int64 {
  let mut out = 0L
  for s in [24, 16, 8, 0] {
    let x = ((a >> s) & 0xFFL).to_double()
    let y = ((b >> s) & 0xFFL).to_double()
    out = out | ((x + (y - x) * t).round().to_int64() << s)
  }
  out
}

///|
fn gc_clamp(x : Double, lo : Double, hi : Double) -> Double {
  if x < lo {
    lo
  } else if x > hi {
    hi
  } else {
    x
  }
}

///|
/// The colour `stops` say at `t` (each stop a place from 0 to 1 and its colour, in order), as a gradient has it.
fn gc_stop(stops : Array[(Double, Int64)], t : Double) -> Int64 {
  for j, s in stops {
    if s.0 >= t {
      if j == 0 {
        return s.1
      }
      let p = stops[j - 1]
      return gc_mix(p.1, s.1, (t - p.0) / (s.0 - p.0))
    }
  }
  stops[stops.length() - 1].1
}

///|
/// A gradient down the box it is in: `n` bands, each the colour `stops` say at its middle.
fn gc_grad(c : @ui.Ctx, stops : Array[(Double, Int64)], n : Int) -> Unit {
  for i in 0..<n {
    let t = (i.to_double() + 0.5) / n.to_double()
    c.box(style=gc_band.then(@ui.style(bg=Data(gc_stop(stops, t)))), fn() {  }) |> ignore
  }
}

///|
/// The same across the box it is in.
fn gc_grad_across(c : @ui.Ctx, stops : Array[(Double, Int64)], n : Int) -> Unit {
  c.box(style=gc_row_full, fn() {
    for i in 0..<n {
      let t = (i.to_double() + 0.5) / n.to_double()
      c.box(style=gc_band_across.then(@ui.style(bg=Data(gc_stop(stops, t)))), fn() {  }) |> ignore
    }
  })
  |> ignore
}

///|
/// A gradient over the whole of the box it is laid in, from `top` to `bottom`.
fn gc_ground(c : @ui.Ctx, stops : Array[(Double, Int64)]) -> Unit {
  c.layer(fn() { gc_grad(c, stops, gc_ground_bands) }) |> ignore
}

///|
/// Words with an edge round them in `edge`, `o` out each way (a title's white edge, a glow over a picture): the words
/// drawn in it eight ways round, under them.
fn gc_edged(c : @ui.Ctx, runs : Array[@ui.Run], style : @ui.TextStyle, edge : Int64, o : Double) -> Unit {
  let edged = runs.map(fn(r) { @ui.span(r.text, weight=r.weight, italic=r.italic, scale=r.scale, color=edge) })
  let edge_style = style.then(@ui.text_style(color=Data(edge)))
  c.box(fn() {
    for d in gc_edge_ways {
      c.layer(fn() { c.box(tx=d.0 * o, ty=d.1 * o, fn() { sr_rich(c, edged, edge_style) }) |> ignore }) |> ignore
    }
    sr_rich(c, runs, style)
  })
  |> ignore
}

///|
/// The eight ways round, as far out each.
// kept across runs: a table, never written
let gc_edge_ways : Array[(Double, Double)] = [
  (1.0, 0.0),
  (-1.0, 0.0),
  (0.0, 1.0),
  (0.0, -1.0),
  (0.71, 0.71),
  (-0.71, 0.71),
  (0.71, -0.71),
  (-0.71, -0.71),
]

///|
/// Words spread out, a space between each two of their letters (a title's letters set wide, as CSS's letter-spacing).
fn gc_spread(words : String) -> String {
  let b = StringBuilder()
  let mut first = true
  for ch in words {
    if !first {
      b.write_char(' ')
    }
    b.write_char(ch)
    first = false
  }
  b.to_string()
}

///|
/// Words spread out where they are Chinese: a space between two letters only when both are past ASCII (「种 别」, while
/// 「Length」 stays as it is: Latin letters set apart do not fit a label's column).
fn gc_spread_han(words : String) -> String {
  let b = StringBuilder()
  let mut last = ' '
  let mut first = true
  for ch in words {
    if !first && last.to_int() > 0x7F && ch.to_int() > 0x7F {
      b.write_char(' ')
    }
    b.write_char(ch)
    last = ch
    first = false
  }
  b.to_string()
}

///|
/// Words in small capitals: each word's first letter as it is, the rest `small` its size (the words said in capitals),
/// spread out when `spread`.
fn gc_caps(words : String, small : Double, spread : Bool) -> Array[@ui.Run] {
  let runs : Array[@ui.Run] = []
  let mut start = true
  for ch in words {
    if spread && runs.length() > 0 {
      runs.push(@ui.span(" "))
    }
    if ch == ' ' {
      start = true
      runs.push(@ui.span(" "))
      continue
    }
    runs.push(if start { @ui.span(ch.to_string()) } else { @ui.span(ch.to_string(), scale=small) })
    start = false
  }
  runs
}

///|
/// Picture `art` (`ratio` its width over its height) in a box `w` by `h` that `style` cuts round, covering it `zoom`
/// times over, its point (`fx`, `fy`: shares of its width and height) as near the box's middle as it can be: a part of a
/// picture as a CSS background's size and place cut it (a face, the side of a picture a girl is on).
fn gc_pic(
  c : @ui.Ctx,
  style : @ui.Style,
  art : String,
  ratio : Double,
  w : Double,
  h : Double,
  zoom : Double,
  fx : Double,
  fy : Double,
) -> Unit {
  let (cw, ch) = if w / h > ratio { (w, w / ratio) } else { (h * ratio, h) }
  let pw = cw * zoom
  let ph = ch * zoom
  let x = gc_clamp(w / 2.0 - fx * pw, w - pw, 0.0)
  let y = gc_clamp(h / 2.0 - fy * ph, h - ph, 0.0)
  c.box(style=style.then(@ui.style(w=Fixed(w), h=Fixed(h))), fn() {
    c.box(left=x, top=y, fn() { sr_art(c, art, pw, ph, at=0.0) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// A round face `d` across from picture `art`: its face's middle at (`fx`, `fy`), the face `fw` of the picture's width,
/// drawn `k` of the circle's.
fn gc_face(c : @ui.Ctx, art : String, ratio : Double, d : Double, fx : Double, fy : Double, fw : Double, k : Double) -> Unit {
  let cover = if ratio > 1.0 { d * ratio } else { d }
  gc_pic(c, gc_round_cut, art, ratio, d, d, k * d / fw / cover, fx, fy)
}

///|
/// sin, as a short sum (no clock nor host in it: the same everywhere).
fn gc_sin(x : Double) -> Double {
  let pi = 3.141592653589793
  let mut a = x - (x / (2.0 * pi)).floor() * 2.0 * pi
  if a > pi {
    a = a - 2.0 * pi
  }
  let a2 = a * a
  let mut term = a
  let mut sum = a
  for k in 1..=10 {
    term = -term * a2 / ((2 * k) * (2 * k + 1)).to_double()
    sum = sum + term
  }
  sum
}

///|
fn gc_cos(x : Double) -> Double {
  gc_sin(x + 1.5707963267948966)
}

///|
/// log10, as a short sum.
fn gc_log10(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  let mut m = x
  let mut e = 0.0
  while m >= 10.0 {
    m = m / 10.0
    e = e + 1.0
  }
  while m < 1.0 {
    m = m * 10.0
    e = e - 1.0
  }
  let y = (m - 1.0) / (m + 1.0)
  let y2 = y * y
  let mut term = y
  let mut sum = 0.0
  for k in 0..<80 {
    sum = sum + term / (2 * k + 1).to_double()
    term = term * y2
  }
  e + 2.0 * sum / 2.302585092994046
}

///|
/// Points as a shape's outline has them (x0 y0 x1 y1 …), each moved by (`dx`, `dy`) and grown `k` times.
fn gc_flat(pts : Array[(Double, Double)], dx? : Double = 0.0, dy? : Double = 0.0, k? : Double = 1.0) -> Array[Double] {
  let out = []
  for p in pts {
    out.push(dx + p.0 * k)
    out.push(dy + p.1 * k)
  }
  out
}

///|
/// The points of a cubic Bézier from `a` through `b`, `c2` to `d`, `n` of them after `a`.
fn gc_cubic(out : Array[(Double, Double)], a : (Double, Double), b : (Double, Double), c2 : (Double, Double), d : (Double, Double), n : Int) -> Unit {
  for i in 1..=n {
    let t = i.to_double() / n.to_double()
    let u = 1.0 - t
    let k0 = u * u * u
    let k1 = 3.0 * u * u * t
    let k2 = 3.0 * u * t * t
    let k3 = t * t * t
    out.push((k0 * a.0 + k1 * b.0 + k2 * c2.0 + k3 * d.0, k0 * a.1 + k1 * b.1 + k2 * c2.1 + k3 * d.1))
  }
}

///|
/// The points of a quadratic Bézier from `a` through `b` to `d`, `n` of them after `a`.
fn gc_quad(out : Array[(Double, Double)], a : (Double, Double), b : (Double, Double), d : (Double, Double), n : Int) -> Unit {
  for i in 1..=n {
    let t = i.to_double() / n.to_double()
    let u = 1.0 - t
    out.push((u * u * a.0 + 2.0 * u * t * b.0 + t * t * d.0, u * u * a.1 + 2.0 * u * t * b.1 + t * t * d.1))
  }
}

///|
/// An ellipse about (`cx`, `cy`), `rx` by `ry`, turned `turn` radians about (`ox`, `oy`): its points round.
fn gc_ellipse(cx : Double, cy : Double, rx : Double, ry : Double, turn? : Double = 0.0, ox? : Double = 0.0, oy? : Double = 0.0) -> Array[(Double, Double)] {
  let out = []
  let cs = gc_cos(turn)
  let sn = gc_sin(turn)
  for i in 0..<gc_round_points {
    let a = 2.0 * 3.141592653589793 * i.to_double() / gc_round_points.to_double()
    let x = cx + rx * gc_cos(a) - ox
    let y = cy + ry * gc_sin(a) - oy
    out.push((ox + x * cs - y * sn, oy + x * sn + y * cs))
  }
  out
}

///|
/// A line through `pts` cut into dashes `on` long, `off` apart: each dash its points.
fn gc_dashes(pts : Array[(Double, Double)], on : Double, off : Double) -> Array[Array[(Double, Double)]] {
  let out : Array[Array[(Double, Double)]] = []
  let mut cur : Array[(Double, Double)] = [pts[0]]
  let mut drawing = true
  let mut left = on
  for k in 1..<pts.length() {
    let mut a = pts[k - 1]
    let b = pts[k]
    let mut seg = ((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1)).sqrt()
    while seg > left {
      let t = left / seg
      let p = (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t)
      if drawing {
        cur.push(p)
        out.push(cur)
      }
      cur = [p]
      drawing = !drawing
      seg = seg - left
      a = p
      left = if drawing { on } else { off }
    }
    left = left - seg
    if drawing {
      cur.push(b)
    }
  }
  if drawing && cur.length() > 1 {
    out.push(cur)
  }
  out
}

///|
/// A heart (the routes' screen's) `w` by `h` from (`x`, `y`): whole, or its left half alone (`half`).
fn gc_heart(x : Double, y : Double, w : Double, h : Double, half : Bool) -> Array[Double] {
  let p : Array[(Double, Double)] = [(12.0, 21.0)]
  gc_cubic(p, (12.0, 21.0), (5.0, 15.8), (0.8, 11.6), (0.8, 6.9), 8)
  gc_cubic(p, (0.8, 6.9), (0.8, 3.4), (3.4, 0.9), (6.6, 0.9), 8)
  gc_cubic(p, (6.6, 0.9), (8.8, 0.9), (10.8, 2.1), (12.0, 4.0), 8)
  if !half {
    gc_cubic(p, (12.0, 4.0), (13.2, 2.1), (15.2, 0.9), (17.4, 0.9), 8)
    gc_cubic(p, (17.4, 0.9), (20.6, 0.9), (23.2, 3.4), (23.2, 6.9), 8)
    gc_cubic(p, (23.2, 6.9), (23.2, 11.6), (19.0, 15.8), (12.0, 21.0), 8)
  }
  let out = []
  for q in p {
    out.push(x + q.0 * w / 24.0)
    out.push(y + q.1 * h / 22.0)
  }
  out
}

///|
/// How many points a round thing's outline has.
let gc_round_points : Int = 40

///|
/// How many bands a ground's gradient has, top to foot.
let gc_ground_bands : Int = 48

///|
// kept across runs: a value (no field of it changes)
let gc_band : @ui.Style = @ui.style(w=Full, h=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let gc_band_across : @ui.Style = @ui.style(w=@sf.grow, h=Full)

///|
// kept across runs: a value (no field of it changes)
let gc_row_full : @ui.Style = @ui.css("row w=Full h=Full")

///|
// kept across runs: a value (no field of it changes)
let gc_round_cut : @ui.Style = @ui.css("radius=Full clip")

///|
// kept across runs: a value (no field of it changes)
let gc_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
let gc_white : Int64 = 0xFFFFFFFFL

// ── 标题画面 ────────────────────────────────────────────────────────────────

///|
/// 标题画面: the game's title screen, the six under the sakura (c1-title-kv) the whole card. In its open sky the logo
/// 千恋✿万Token (pink, its letters edged white) still.fail's edition, who stars and what she burned; on the dusk at its
/// foot the menu, 继续游戏 lit (the chats at work), 回想模式 the week's archived; Click to Start, a copyright of the week.
fn sr_title(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = gc_args(fleet)
  sr_box(c, id, flat, tt_ground, fn() {
    sr_art(c, "c1-title-kv", @sf.share_w_most, tt_h, at=0.0) |> ignore
    // the dusk deepening under the menu
    c.box(style=tt_shade, left=0.0, top=tt_h - tt_shade_h, fn() { gc_grad(c, tt_shade_stops, tt_shade_bands) }) |> ignore
    // the logo in the open sky: 千恋✿ over 万Token, white-edged
    c.box(style=tt_logo, left=tt_logo_left, top=tt_logo_top, fn() {
      c.box(style=tt_logo_row, fn() {
        gc_edged(
          c,
          [@ui.span(@sf.t("web-main.stations.shareSenren.title.logoA"), scale=tt_logo_scale)],
          tt_logo_words,
          gc_white,
          tt_edge,
        )
        c.shapes(tt_flower(), w=Px(tt_flower_side), h=Px(tt_flower_side)) |> ignore
      })
      |> ignore
    })
    |> ignore
    c.box(style=tt_logo, left=tt_logo_left, top=tt_logo_top2, fn() {
      c.box(style=tt_logo_row2, fn() {
        gc_edged(
          c,
          [
            @ui.span(@sf.t("web-main.stations.shareSenren.title.logoB"), scale=tt_logo_scale),
            @ui.span(@sf.t("web-main.stations.shareSenren.title.logoToken"), italic=true, scale=tt_token_scale),
          ],
          tt_logo_words,
          gc_white,
          tt_edge,
        )
      })
      |> ignore
    })
    |> ignore
    c.box(style=tt_under, left=tt_logo_left, top=tt_edition_top, fn() {
      gc_edged(
        c,
        [
          @ui.span("still", color=tt_brand_ink, weight=700, italic=false),
          @ui.span(".", color=@sf.share_orange, weight=700),
          @ui.span("fail", color=tt_brand_ink, weight=700),
          @ui.span(" " + @sf.t("web-main.stations.shareSenren.title.edition"), italic=true),
        ],
        tt_edition,
        gc_white,
        tt_glow,
      )
      c.box(style=tt_star, fn() {
        gc_edged(c, gc_plain(sr_said("web-main.stations.shareSenren.title.star1", args, tt_rose), sr_arg(args, "model")), tt_star_words, gc_white, tt_glow)
        gc_edged(c, sr_said("web-main.stations.shareSenren.title.star2", args, tt_rose), tt_star_words, gc_white, tt_glow)
      })
      |> ignore
    })
    |> ignore
    // the menu, translucent on the dusk; 继续游戏 lit
    c.box(style=tt_menu, left=tt_menu_left, top=tt_menu_top, fn() {
      tt_item(c, [@ui.span(@sf.t("web-main.stations.shareSenren.title.new"))], false)
      tt_item(
        c,
        [@ui.span(@sf.t("web-main.stations.shareSenren.title.continue"))] +
        sr_said("web-main.stations.shareSenren.title.continueMore", args, gc_white).map(fn(r) {
          @ui.span(r.text, scale=tt_small_scale, color=gc_white)
        }),
        true,
      )
      tt_item(
        c,
        [@ui.span(@sf.t("web-main.stations.shareSenren.title.recall"))] +
        sr_said("web-main.stations.shareSenren.title.recallMore", args, tt_small_ink).map(fn(r) {
          @ui.span(r.text, scale=tt_small_scale, color=tt_small_ink)
        }),
        false,
      )
      c.box(style=tt_menu_pair, fn() {
        c.box(style=gc_grow, fn() { tt_item(c, [@ui.span(@sf.t("web-main.stations.shareSenren.title.config"))], false) }) |> ignore
        c.box(style=gc_grow, fn() { tt_item(c, [@ui.span(@sf.t("web-main.stations.shareSenren.title.quit"))], false) }) |> ignore
      })
      |> ignore
    })
    |> ignore
    c.box(style=tt_line, left=0.0, top=tt_click_top, fn() {
      gc_edged(
        c,
        [@ui.span("—  " + gc_spread(@sf.t("web-main.stations.shareSenren.title.click")) + "  —")],
        tt_click,
        tt_click_glow,
        tt_glow,
      )
    })
    |> ignore
    c.box(style=tt_line, left=0.0, top=tt_h - tt_copy_up, fn() {
      sr_words(c, @sf.t("web-main.stations.shareSenren.title.copy", args~), tt_copy)
    })
    |> ignore
  })
}

///|
/// An item of the title's menu: its words in the middle of a band of white fading at its ends (the lit one pink, a ✿
/// at either end).
fn tt_item(c : @ui.Ctx, runs : Array[@ui.Run], lit : Bool) -> Unit {
  c.box(style=tt_item_box, fn() {
    c.layer(fn() { gc_grad_across(c, if lit { tt_lit_stops } else { tt_item_stops }, tt_item_bands) }) |> ignore
    if lit {
      c.layer(fn() {
        c.box(style=tt_item_marks, fn() {
          sr_words(c, "✿", tt_mark)
          c.box(style=gc_grow, fn() {  }) |> ignore
          sr_words(c, "✿", tt_mark)
        })
        |> ignore
      })
      |> ignore
    }
    sr_rich(c, runs, tt_item_words)
  })
  |> ignore
}

///|
/// The logo's ＊: a five-petal flower, pink edged white, its middle yellow (the mockup's svg, 24 grown to its side).
fn tt_flower() -> Array[@ui.Shape] {
  let k = tt_flower_side / 24.0
  let out : Array[@ui.Shape] = []
  for i in 0..<5 {
    let turn = i.to_double() * 2.0 * 3.141592653589793 / 5.0
    let petal = gc_ellipse(12.0, 6.2, 3.6, 5.6, turn~, ox=12.0, oy=12.0)
    out.push(@ui.shape_of([(gc_flat(petal, k~), true)], fill=tt_petal, stroke=gc_white, width=1.6 * k))
  }
  out.push(@ui.shape_of([(gc_flat(gc_ellipse(12.0, 12.0, 2.6, 2.6), k~), true)], fill=tt_pistil))
  out
}

///|
let tt_h : Double = 680.0

///|
let tt_ground : Int64 = 0x2A1830FFL

///|
let tt_shade_h : Double = 250.0

///|
let tt_shade_bands : Int = 25

///|
/// The dusk under the menu: clear at its top, the ground's at its foot.
// kept across runs: a table, never written
let tt_shade_stops : Array[(Double, Int64)] = [
  (0.0, 0x2A183000L),
  (0.34, 0x2A183099L),
  (0.62, 0x2A1830DDL),
  (1.0, 0x2A1830F2L),
]

///|
// kept across runs: a value (no field of it changes)
let tt_shade : @ui.Style = @ui.style(w=Fixed(@sf.share_w_most), h=Fixed(tt_shade_h))

///|
let tt_logo_left : Double = 150.0

///|
let tt_logo_top : Double = 19.0

///|
/// The logo's second line (万Token), where it starts: close under the first, as the mockup's 52-point lines.
let tt_logo_top2 : Double = 73.0

///|
let tt_logo_w : Double = 206.0

///|
// kept across runs: a value (no field of it changes)
let tt_logo : @ui.Style = @ui.css("align=ACenter").then(@ui.style(w=Fixed(tt_logo_w)))

///|
// kept across runs: a value (no field of it changes)
let tt_logo_row : @ui.Style = @ui.css("row align=ACenter gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let tt_logo_row2 : @ui.Style = @ui.css("row align=ACenter pl=S4_5")

///|
let tt_logo_scale : Double = 1.4

///|
let tt_token_scale : Double = 1.25

///|
let tt_edge : Double = 4.0

///|
let tt_glow : Double = 1.2

///|
let tt_pink : Int64 = 0xE4508AFFL

///|
let tt_petal : Int64 = 0xFF9CC2FFL

///|
let tt_pistil : Int64 = 0xFFE28AFFL

///|
let tt_flower_side : Double = 36.0

///|
// kept across runs: a value (no field of it changes)
let tt_logo_words : @ui.TextStyle = @ui.text_style(size=Xl4, weight=Bold, color=Data(tt_pink), wrap=false)

///|
let tt_edition_top : Double = 136.0

///|
let tt_brand_ink : Int64 = 0x4A1430FFL

///|
let tt_rose : Int64 = 0xB8306EFFL

///|
// kept across runs: a value (no field of it changes)
let tt_under : @ui.Style = @ui.css("align=ACenter gap=S1").then(@ui.style(w=Fixed(tt_logo_w)))

///|
let tt_edition_ink : Int64 = 0x8A2A5AFFL

///|
// kept across runs: a value (no field of it changes)
let tt_edition : @ui.TextStyle = @ui.text_style(size=Base, tracking=Wider, color=Data(tt_edition_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tt_star : @ui.Style = @ui.css("align=ACenter")

///|
let tt_star_words_ink : Int64 = 0x5A1E3CFFL

///|
// kept across runs: a value (no field of it changes)
let tt_star_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(tt_star_words_ink), wrap=false)

///|
let tt_menu_left : Double = 50.0

///|
let tt_menu_top : Double = 480.0

///|
let tt_menu_w : Double = @sf.share_w_most - 2.0 * tt_menu_left

///|
// kept across runs: a value (no field of it changes)
let tt_menu : @ui.Style = @ui.css("gap=S1").then(@ui.style(w=Fixed(tt_menu_w)))

///|
// kept across runs: a value (no field of it changes)
let tt_menu_pair : @ui.Style = @ui.css("row w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let tt_item_box : @ui.Style = @ui.css("w=Full align=ACenter justify=JCenter").then(@ui.style(h=Fixed(tt_item_h)))

///|
let tt_item_h : Double = 29.0

///|
let tt_item_bands : Int = 26

///|
// kept across runs: a table, never written
let tt_item_stops : Array[(Double, Int64)] = [(0.0, 0xFFFFFF00L), (0.22, 0xFFFFFF30L), (0.78, 0xFFFFFF30L), (1.0, 0xFFFFFF00L)]

///|
// kept across runs: a table, never written
let tt_lit_stops : Array[(Double, Int64)] = [(0.0, 0xF07FB000L), (0.22, 0xF07FB0C0L), (0.78, 0xF07FB0C0L), (1.0, 0xF07FB000L)]

///|
// kept across runs: a value (no field of it changes)
let tt_item_marks : @ui.Style = @ui.css("row w=Full h=Full align=ACenter px=S1_5")

///|
// kept across runs: a value (no field of it changes)
let tt_mark : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(gc_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tt_item_words : @ui.TextStyle = @ui.text_style(size=Base, tracking=Widest, color=Data(gc_white), wrap=false)

///|
let tt_small_scale : Double = 0.83

///|
let tt_small_ink : Int64 = 0xFFD2E6FFL

///|
let tt_click_top : Double = 624.0

///|
let tt_click_glow : Int64 = 0xFF8FB866L

///|
// kept across runs: a value (no field of it changes)
let tt_line : @ui.Style = @ui.css("align=ACenter").then(@ui.style(w=Fixed(@sf.share_w_most)))

///|
let tt_click_ink : Int64 = 0xFFE3EFFFL

///|
// kept across runs: a value (no field of it changes)
let tt_click : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(tt_click_ink), wrap=false)

///|
let tt_copy_up : Double = 27.0

///|
let tt_copy_ink : Int64 = 0xCBB3CFFFL

///|
// kept across runs: a value (no field of it changes)
let tt_copy : @ui.TextStyle = @ui.text_style(size=Xs3, color=Data(tt_copy_ink), wrap=false)

// ── CG 鉴赏 ───────────────────────────────────────────────────────────────

///|
/// CG 鉴赏: the game's extras screen in the night with pink. A CG a day, cut from the heroines' pictures, its date and
/// its chats archived (a day with none locked, ？？？), today's NEW; the eighth the week's 回收率. Under them the best
/// CG of the week (the day with the most), large, who starred in it (the top model) and the week's three figures; the
/// theme song playing, and when.
fn sr_cg(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = gc_args(fleet)
  let days = sr_days(fleet)
  let got = days.filter(fn(d) { d.2 != "0" }).length()
  let mut best = 0
  for i, d in days {
    if d.3 > days[best].3 {
      best = i
    }
  }
  let best_i = best
  sr_box(c, id, flat, cg_ground, fn() {
    c.box(style=cg_inner, fn() {
      c.box(style=cg_head, fn() {
        c.box(style=gc_grow, fn() {
          sr_words(c, gc_spread(@sf.t("web-main.stations.shareSenren.cg.extra")), cg_extra)
          sr_rich(c, [@ui.span(@sf.t("web-main.stations.shareSenren.cg.title"), scale=cg_title_scale)], cg_title)
        })
        |> ignore
        sr_brand(c, cg_brand)
      })
      |> ignore
      // the tabs: CG 鉴赏 on, underlined in pink
      c.box(style=cg_tabs, fn() {
        c.box(style=cg_tab_on, fn() {
          sr_words(c, @sf.t("web-main.stations.shareSenren.cg.title"), cg_tab_lit)
          c.box(style=cg_tab_bar, fn() {  }) |> ignore
        })
        |> ignore
        sr_words(c, @sf.t("web-main.stations.shareSenren.cg.tabRecall"), cg_tab)
        sr_words(c, @sf.t("web-main.stations.shareSenren.cg.tabBgm"), cg_tab)
        c.box(style=gc_grow, fn() {  }) |> ignore
        sr_words(c, @sf.t("web-main.stations.shareSenren.cg.page"), cg_page)
      })
      |> ignore
      c.box(style=cg_rule, fn() {  }) |> ignore
      // the grid: a CG a day, the 回收率 last
      c.box(style=cg_grid, fn() {
        for r in 0..<2 {
          c.box(style=cg_grid_row, fn() {
            for k in 0..<4 {
              let i = r * 4 + k
              if i < days.length() {
                cg_tile(c, days[i], i)
              } else if i == days.length() {
                cg_sum(c, got, days.length())
              }
            }
          })
          |> ignore
        }
      })
      |> ignore
      // the best CG of the week
      c.box(style=cg_best, fn() {
        c.box(style=cg_best_head, fn() {
          sr_rich(c, [@ui.span("✿  ", color=cg_pink), @ui.span(@sf.t("web-main.stations.shareSenren.cg.best"))], cg_best_label)
          c.box(style=gc_grow, fn() {  }) |> ignore
          sr_words(
            c,
            @sf.t("web-main.stations.shareSenren.cg.bestOf", args=[
              ("i", (best_i + 1).to_string()),
              ("n", days.length().to_string()),
            ]),
            cg_best_of,
          )
        })
        |> ignore
        if days.length() > 0 {
          let d = days[best_i]
          let shot = cg_shots[best_i % cg_shots.length()]
          c.box(style=cg_pic_ring, fn() {
            c.box(style=cg_pic, fn() {
              sr_art(c, shot.0, cg_pic_w, cg_pic_h, at=cg_best_at) |> ignore
              c.layer(fn() {
                c.spacer()
                c.box(style=cg_pic_cap, fn() {
                  c.layer(fn() { gc_grad(c, cg_cap_stops, cg_cap_bands) }) |> ignore
                  c.box(style=cg_pic_cap_row, fn() {
                    sr_words(
                      c,
                      if d.4 {
                        d.0 + " · " + @sf.t("web-main.stations.shareSenren.cg.today")
                      } else {
                        d.0
                      },
                      cg_pic_date,
                    )
                    sr_rich(
                      c,
                      sr_said("web-main.stations.shareSenren.cg.archivedN", [("n", d.2)], gc_white, scale=cg_best_n_scale),
                      cg_pic_n,
                    )
                    c.box(style=gc_grow, fn() {  }) |> ignore
                    sr_words(c, @sf.t("web-main.stations.shareSenren.cg.most"), cg_pic_most)
                  })
                  |> ignore
                })
                |> ignore
              })
              |> ignore
              c.layer(fn() { c.box(style=cg_pic_edge, fn() {  }) |> ignore }) |> ignore
            })
            |> ignore
          })
          |> ignore
        }
        c.box(style=cg_cast, fn() {
          c.box(style=cg_cast_tag, fn() { sr_words(c, @sf.t("web-main.stations.shareSenren.cg.cast"), cg_cast_tag_words) })
          |> ignore
          // the model said plain, its tokens and cost lit (as the mockup)
          let model = sr_arg(args, "model")
          sr_rich(
            c,
            sr_said("web-main.stations.shareSenren.cg.castLine", args, gc_white, scale=cg_cast_scale).map(fn(r) {
              if r.text == model {
                @ui.span(r.text)
              } else {
                r
              }
            }),
            cg_cast_words,
          )
        })
        |> ignore
      })
      |> ignore
      // the week's three figures
      c.box(style=cg_week, fn() {
        for x in [
          (sr_arg(args, "archived"), "web-main.stations.shareSenren.cg.weekArchived"),
          (sr_arg(args, "weekTokens"), "web-main.stations.shareSenren.cg.weekTokens"),
          (sr_arg(args, "weekCost"), "web-main.stations.shareSenren.cg.weekCost"),
        ] {
          c.box(style=cg_week_box, fn() {
            sr_rich(c, [@ui.span(x.0, scale=cg_week_scale)], cg_week_value)
            sr_words(c, @sf.t(x.1), cg_week_label)
          })
          |> ignore
        }
      })
      |> ignore
      c.box(style=cg_foot, fn() {
        c.box(style=cg_eq, fn() {
          for h in cg_eq_heights {
            c.box(style=cg_eq_bar.then(@ui.style(h=Fixed(h))), fn() {  }) |> ignore
          }
        })
        |> ignore
        sr_rich(c, [@ui.span("♪ ", color=cg_pink), @ui.span(@sf.t("web-main.stations.shareSenren.cg.song"))], cg_song)
        c.box(style=gc_grow, fn() {  }) |> ignore
        sr_words(c, sr_arg(args, "at"), cg_at)
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// A day's CG: its picture, its date and chats archived over a dark fading up at its foot (today's ringed pink, NEW); a
/// day with none locked, ？？？.
fn cg_tile(c : @ui.Ctx, d : (String, String, String, Double, Bool), i : Int) -> Unit {
  let shot = cg_shots[i % cg_shots.length()]
  let locked = d.2 == "0"
  c.box(style=if locked { cg_tile_locked } else { cg_tile_box }, fn() {
    if locked {
      c.box(style=cg_lock, fn() { sr_words(c, @sf.t("web-main.stations.shareSenren.cg.locked"), cg_lock_words) }) |> ignore
    } else {
      gc_pic(c, cg_cut, shot.0, shot.1, cg_tile_w, cg_tile_h, shot.2, shot.3, shot.4)
    }
    c.layer(fn() {
      c.spacer()
      c.box(style=cg_cap, fn() {
        c.layer(fn() { gc_grad(c, cg_cap_stops, cg_cap_bands) }) |> ignore
        sr_rich(
          c,
          if locked {
            [@ui.span(d.0)]
          } else {
            [@ui.span(d.0 + " · "), @ui.span(d.1, weight=700, color=cg_pink_light)]
          },
          cg_cap_words,
        )
      })
      |> ignore
    })
    |> ignore
    if d.4 && !locked {
      c.box(style=cg_new, left=cg_new_at, top=cg_new_at, fn() {
        sr_words(c, @sf.t("web-main.stations.shareSenren.cg.new"), cg_new_words)
      })
      |> ignore
    }
    c.layer(fn() { c.box(style=if d.4 { cg_tile_edge_today } else { cg_tile_edge }, fn() {  }) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// The eighth tile: how many of the days have their CG, of how many, and as a percentage.
fn cg_sum(c : @ui.Ctx, got : Int, all : Int) -> Unit {
  c.box(style=cg_sum_box, fn() {
    sr_words(c, @sf.t("web-main.stations.shareSenren.cg.rate"), cg_sum_k)
    sr_rich(c, [@ui.span(got.to_string() + "/" + all.to_string(), scale=cg_sum_scale)], cg_sum_v)
    sr_words(c, (if all > 0 { got * 100 / all } else { 0 }).to_string() + "%", cg_sum_p)
  })
  |> ignore
}

///|
/// Each day's CG (by the day's place in the week): its picture, its width over its height, how much it is grown, and
/// where in it the tile's middle is (the face, the girl's side of a landscape).
// kept across runs: a table, never written
let cg_shots : Array[(String, Double, Double, Double, Double)] = [
  ("a2-yoshino-omikuji", 1.5, 1.0, 1.0, 0.5),
  ("a3-mako-roof", 1.5, 1.12, 0.66, 0.35),
  ("a4-lena-ryokan", 1.5, 1.0, 1.0, 0.5),
  ("a5-koharu-sweets", 1.5, 1.0, 1.0, 0.5),
  ("a6-roka-ledger", 1.5, 1.0, 1.0, 0.5),
  ("d2-yoshino-kagura", 0.6667, 1.75, 0.47, 0.17),
  ("e1-murasame-beauty", 0.6667, 1.7, 0.46, 0.19),
]

///|
let cg_ground : Int64 = 0x16111FFFL

///|
let cg_pink : Int64 = 0xF39BC1FFL

///|
let cg_pink_light : Int64 = 0xFFC2DCFFL

///|
// kept across runs: a value (no field of it changes)
let cg_inner : @ui.Style = @ui.css("w=Full px=S4 pt=S4_5 pb=S4")

///|
// kept across runs: a value (no field of it changes)
let cg_head : @ui.Style = @ui.css("row w=Full align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let cg_extra : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(cg_pink), wrap=false)

///|
let cg_title_scale : Double = 1.14

///|
let cg_title_ink : Int64 = 0xF6EEF9FFL

///|
// kept across runs: a value (no field of it changes)
let cg_title : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Bold, tracking=Wider, color=Data(cg_title_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cg_brand : @ui.TextStyle = @ui.text_style(size=Lg, weight=Bold, color=Data(gc_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cg_tabs : @ui.Style = @ui.css("row w=Full gap=S4_5 align=AStart pt=S2")

///|
// kept across runs: a value (no field of it changes)
let cg_tab_on : @ui.Style = @ui.css("gap=S1_5 align=AStretch")

///|
// kept across runs: a value (no field of it changes)
let cg_tab_bar : @ui.Style = @ui.css("w=Full h=S0_5 radius=Full").then(@ui.style(bg=Data(cg_pink)))

///|
// kept across runs: a value (no field of it changes)
let cg_tab_lit : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(gc_white), wrap=false)

///|
let cg_tab_ink : Int64 = 0x8F82A6FFL

///|
// kept across runs: a value (no field of it changes)
let cg_tab : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(cg_tab_ink), wrap=false)

///|
let cg_page_ink : Int64 = 0xB9ABD0FFL

///|
// kept across runs: a value (no field of it changes)
let cg_page : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(cg_page_ink), wrap=false)

///|
let cg_rule_bg : Int64 = 0xFFFFFF1FL

///|
// kept across runs: a value (no field of it changes)
let cg_rule : @ui.Style = @ui.css("w=Full h=SPx").then(@ui.style(bg=Data(cg_rule_bg)))

///|
// kept across runs: a value (no field of it changes)
let cg_grid : @ui.Style = @ui.css("w=Full gap=S2 pt=S3_5")

///|
// kept across runs: a value (no field of it changes)
let cg_grid_row : @ui.Style = @ui.css("row w=Full gap=S2")

///|
let cg_tile_w : Double = 76.0

///|
let cg_tile_h : Double = 106.0

///|
let cg_tile_box_bg : Int64 = 0x2A2236FFL

///|
// kept across runs: a value (no field of it changes)
let cg_tile_box : @ui.Style = @ui.css("radius=Lg clip").then(@ui.style(w=Fixed(cg_tile_w), h=Fixed(cg_tile_h), bg=Data(cg_tile_box_bg)))

///|
let cg_tile_locked_bg : Int64 = 0x241D30FFL

///|
// kept across runs: a value (no field of it changes)
let cg_tile_locked : @ui.Style = cg_tile_box.then(@ui.style(bg=Data(cg_tile_locked_bg)))

///|
// kept across runs: a value (no field of it changes)
let cg_cut : @ui.Style = @ui.css("clip")

///|
// kept across runs: a value (no field of it changes)
let cg_lock : @ui.Style = @ui.css("w=Full align=ACenter pt=S8")

///|
let cg_lock_words_ink : Int64 = 0x6F6386FFL

///|
// kept across runs: a value (no field of it changes)
let cg_lock_words : @ui.TextStyle = @ui.text_style(size=Xl, color=Data(cg_lock_words_ink), wrap=false)

///|
let cg_tile_edge_edge : Int64 = 0xFFFFFF2EL

///|
// kept across runs: a value (no field of it changes)
let cg_tile_edge : @ui.Style = @ui.css("w=Full h=Full radius=Lg border=B1").then(@ui.style(border_color=Data(cg_tile_edge_edge)))

///|
// kept across runs: a value (no field of it changes)
let cg_tile_edge_today : @ui.Style = @ui.css("w=Full h=Full radius=Lg border=B2").then(@ui.style(border_color=Data(cg_pink)))

///|
/// A caption's dark fading up behind its words: clear at its top, the ground's at its foot.
// kept across runs: a table, never written
let cg_cap_stops : Array[(Double, Int64)] = [(0.0, 0x16111F00L), (0.55, 0x16111FD9L), (1.0, 0x16111FE6L)]

///|
let cg_cap_bands : Int = 12

///|
// kept across runs: a value (no field of it changes)
let cg_cap : @ui.Style = @ui.css("w=Full align=ACenter pt=S3_5 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let cg_cap_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(gc_white), wrap=false)

///|
let cg_new_at : Double = 4.0

///|
let cg_new_bg : Int64 = 0xF0609AFFL

///|
// kept across runs: a value (no field of it changes)
let cg_new : @ui.Style = @ui.css("px=S1_5 radius=Full").then(@ui.style(bg=Data(cg_new_bg)))

///|
// kept across runs: a value (no field of it changes)
let cg_new_words : @ui.TextStyle = @ui.text_style(size=Xs3, weight=Bold, tracking=@sf.share_letters_apart, color=Data(gc_white), wrap=false)

///|
let cg_sum_box_bg : Int64 = 0x3E2545FFL

///|
let cg_sum_box_edge : Int64 = 0xF39BC188L

///|
// kept across runs: a value (no field of it changes)
let cg_sum_box : @ui.Style = @ui.css("radius=Lg align=ACenter justify=JCenter border=B1").then(
  @ui.style(w=Fixed(cg_tile_w), h=Fixed(cg_tile_h), bg=Data(cg_sum_box_bg), border_color=Data(cg_sum_box_edge)),
)

///|
let cg_sum_k_ink : Int64 = 0xF7C6DCFFL

///|
// kept across runs: a value (no field of it changes)
let cg_sum_k : @ui.TextStyle = @ui.text_style(size=Xs2, tracking=@sf.share_letters_apart, color=Data(cg_sum_k_ink), wrap=false)

///|
let cg_sum_scale : Double = 1.36

///|
// kept across runs: a value (no field of it changes)
let cg_sum_v : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Bold, color=Data(gc_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cg_sum_p : @ui.TextStyle = @ui.text_style(size=Xs2, tracking=Wider, color=Data(cg_pink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cg_best : @ui.Style = @ui.css("w=Full pt=S4_5 gap=S2")

///|
// kept across runs: a value (no field of it changes)
let cg_best_head : @ui.Style = @ui.css("row w=Full align=AEnd")

///|
let cg_best_label_ink : Int64 = 0xF7C6DCFFL

///|
// kept across runs: a value (no field of it changes)
let cg_best_label : @ui.TextStyle = @ui.text_style(size=Sm, tracking=Widest, color=Data(cg_best_label_ink), wrap=false)

///|
let cg_best_of_ink : Int64 = 0xA99CBFFFL

///|
// kept across runs: a value (no field of it changes)
let cg_best_of : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(cg_best_of_ink), wrap=false)

///|
let cg_pic_w : Double = 320.0

///|
let cg_pic_h : Double = 180.0

///|
let cg_best_at : Double = 0.1

///|
let cg_pic_ring_edge : Int64 = 0xF39BC166L

///|
// kept across runs: a value (no field of it changes)
let cg_pic_ring : @ui.Style = @ui.css("w=Full p=S1 radius=Xl2 border=B1").then(@ui.style(border_color=Data(cg_pic_ring_edge)))

///|
// kept across runs: a value (no field of it changes)
let cg_pic : @ui.Style = @ui.css("radius=Xl clip").then(@ui.style(w=Fixed(cg_pic_w), h=Fixed(cg_pic_h)))

///|
let cg_pic_edge_edge : Int64 = 0xFFFFFF40L

///|
// kept across runs: a value (no field of it changes)
let cg_pic_edge : @ui.Style = @ui.css("w=Full h=Full radius=Xl border=B1").then(@ui.style(border_color=Data(cg_pic_edge_edge)))

///|
// kept across runs: a value (no field of it changes)
let cg_pic_cap : @ui.Style = @ui.css("w=Full pt=S6 pb=S2 px=S3")

///|
// kept across runs: a value (no field of it changes)
let cg_pic_cap_row : @ui.Style = @ui.css("row w=Full gap=S2 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let cg_pic_date : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(cg_pink_light), wrap=false)

///|
let cg_best_n_scale : Double = 1.5

///|
// kept across runs: a value (no field of it changes)
let cg_pic_n : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(gc_white), wrap=false)

///|
let cg_pic_most_ink : Int64 = 0xE4D8F0FFL

///|
// kept across runs: a value (no field of it changes)
let cg_pic_most : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(cg_pic_most_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cg_cast : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter pt=S1")

///|
// kept across runs: a value (no field of it changes)
let cg_cast_tag : @ui.Style = @ui.css("px=S1_5 radius=Base").then(@ui.style(bg=Data(cg_pink)))

///|
// kept across runs: a value (no field of it changes)
let cg_cast_tag_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(cg_ground), wrap=false)

///|
let cg_cast_scale : Double = 1.15

///|
let cg_cast_words_ink : Int64 = 0xD8CCE8FFL

///|
// kept across runs: a value (no field of it changes)
let cg_cast_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(cg_cast_words_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cg_week : @ui.Style = @ui.css("row w=Full gap=S2 pt=S3_5")

///|
let cg_week_box_bg : Int64 = 0xFFFFFF0DL

///|
let cg_week_box_edge : Int64 = 0xFFFFFF17L

///|
// kept across runs: a value (no field of it changes)
let cg_week_box : @ui.Style = @ui.css("py=S2 radius=Lg align=ACenter border=B1").then(
  @ui.style(w=@sf.grow, bg=Data(cg_week_box_bg), border_color=Data(cg_week_box_edge)),
)

///|
let cg_week_scale : Double = 1.06

///|
// kept across runs: a value (no field of it changes)
let cg_week_value : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, color=Data(gc_white), wrap=false)

///|
let cg_week_label_ink : Int64 = 0xA99CBFFFL

///|
// kept across runs: a value (no field of it changes)
let cg_week_label : @ui.TextStyle = @ui.text_style(size=Xs3, color=Data(cg_week_label_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cg_foot : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter pt=S3_5")

///|
// kept across runs: a value (no field of it changes)
let cg_eq : @ui.Style = @ui.css("row gap=SPx align=AEnd")

///|
/// The equaliser's bars beside the song: how tall each is.
// kept across runs: a table, never written
let cg_eq_heights : Array[Double] = [6.0, 10.0, 4.0, 8.0]

///|
let cg_eq_w : Double = 2.0

///|
// kept across runs: a value (no field of it changes)
let cg_eq_bar : @ui.Style = @ui.css("radius=Sm").then(@ui.style(w=Fixed(cg_eq_w), bg=Data(cg_pink)))

///|
let cg_song_ink : Int64 = 0xD8CCE8FFL

///|
// kept across runs: a value (no field of it changes)
let cg_song : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(cg_song_ink), wrap=false)

///|
let cg_at_ink : Int64 = 0x8F82A6FFL

///|
// kept across runs: a value (no field of it changes)
let cg_at : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(cg_at_ink), wrap=false)

// ── 好感度 ────────────────────────────────────────────────────────────────

///|
/// 好感度 · 攻略进度: the routes screen, pink. The models, the most tokens first, are the six routes in their order
/// (丛雨线 the most): each its heroine's face, her route and the model, its hearts (five, by its tokens on a log scale:
/// the most MAX) and its tokens and cost. Over them the route now played; under them the endings reached (the week's
/// archived) and the routes being played (the chats at work).
fn sr_affection(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = gc_args(fleet)
  let ranked = gc_ranked(fleet)
  let most = if ranked.length() > 0 { gc_log10(ranked[0].3) } else { 0.0 }
  sr_box(c, id, flat, af_ground, fn() {
    gc_ground(c, af_ground_stops)
    c.box(style=af_inner, fn() {
      c.box(style=af_top, fn() {
        sr_brand(c, af_brand)
        c.box(style=gc_grow, fn() {  }) |> ignore
        sr_words(c, sr_arg(args, "at"), af_at)
      })
      |> ignore
      c.box(style=af_title_row, fn() {
        c.box(fn() {
          // its shadow, then its white edge, then it
          c.layer(fn() {
            c.box(ty=af_title_drop, fn() {
              gc_edged(c, [@ui.span(@sf.t("web-main.stations.shareSenren.aff.title"))], af_title_drop_words, af_title_drop_ink, af_title_edge)
            })
            |> ignore
          })
          |> ignore
          gc_edged(c, [@ui.span(@sf.t("web-main.stations.shareSenren.aff.title"))], af_title, gc_white, af_title_edge)
        })
        |> ignore
        c.box(style=af_tag_ledge, fn() {
          c.box(style=af_tag, fn() { sr_words(c, @sf.t("web-main.stations.shareSenren.aff.tag"), af_tag_words) }) |> ignore
        })
        |> ignore
      })
      |> ignore
      // the route now played
      c.box(style=af_now_ledge, fn() {
        c.box(style=af_now, fn() {
          let route = @sf.t("web-main.stations.shareSenren.aff.route", args=[("name", @sf.t(af_girls[0].0))])
          sr_rich(c, sr_said("web-main.stations.shareSenren.aff.now", [("route", route)], af_girls[0].1), af_now_words)
          c.box(style=af_max, fn() { sr_words(c, @sf.t("web-main.stations.shareSenren.aff.max"), af_max_words) }) |> ignore
        })
        |> ignore
      })
      |> ignore
      c.box(style=af_list, fn() {
        for i, m in ranked {
          if i >= af_girls.length() {
            break
          }
          let girl = af_girls[i]
          let hearts = if most > 6.0 {
            let h = ((gc_log10(m.3) - 6.0) / (most - 6.0) * 10.0).round() / 2.0
            if h < 0.5 {
              0.5
            } else {
              h
            }
          } else {
            5.0
          }
          af_row(c, girl, m, hearts, i == 0)
        }
      })
      |> ignore
      c.box(style=af_stats, fn() {
        af_stat(
          c,
          @sf.t("web-main.stations.shareSenren.aff.ended"),
          sr_num(sr_arg(args, "archived")),
          gc_unit(sr_arg(args, "archived")),
          @sf.t("web-main.stations.shareSenren.aff.endedSub"),
        )
        af_stat(
          c,
          @sf.t("web-main.stations.shareSenren.aff.playing"),
          sr_arg(args, "chats"),
          @sf.t("web-main.stations.shareSenren.aff.playingUnit"),
          @sf.t("web-main.stations.shareSenren.aff.playingSub"),
        )
      })
      |> ignore
      c.box(style=af_foot, fn() { sr_words(c, @sf.t("web-main.stations.shareTagline"), af_tagline) }) |> ignore
    })
    |> ignore
  })
}

///|
/// Every model, the most tokens first: its name, tokens and cost as said, and its tokens.
fn gc_ranked(fleet : Json?) -> Array[(String, String, String, Double)] {
  let out : Array[(String, String, String, Double)] = []
  for q in items(fleet, "spent") {
    for m in items(Some(q), "models") {
      let m = Some(m)
      out.push((text(m, "name"), text(m, "tokensText"), text(m, "costText"), number(m, "tokens")))
    }
  }
  for i in 1..<out.length() {
    let mut j = i
    while j > 0 && out[j - 1].3 < out[j].3 {
      let x = out[j - 1]
      out[j - 1] = out[j]
      out[j] = x
      j = j - 1
    }
  }
  out
}

///|
/// A route: its heroine's face ringed in her colour, her route and the model, its hearts (MAX at five), its tokens and
/// cost; the lead's ringed mint.
fn af_row(
  c : @ui.Ctx,
  girl : (String, Int64, String, Double, Double, Double, Double),
  m : (String, String, String, Double),
  hearts : Double,
  lead : Bool,
) -> Unit {
  let (name, ink, art, ratio, fx, fy, fw) = girl
  c.box(style=if lead { af_row_ledge_lead } else { af_row_ledge }, fn() {
    c.box(style=if lead { af_card_lead } else { af_card }, fn() {
      c.box(style=af_av_ring.then(@ui.style(bg=Data(ink))), fn() {
        c.box(style=af_av_white, fn() { gc_face(c, art, ratio, af_av_d, fx, fy, fw, af_face_k) }) |> ignore
      })
      |> ignore
      c.box(style=af_mid, fn() {
        c.box(style=af_name_row, fn() {
          sr_rich(
            c,
            [@ui.span(@sf.t("web-main.stations.shareSenren.aff.route", args=[("name", @sf.t(name))]), color=ink, scale=af_route_scale)],
            af_route,
          )
          sr_words(c, m.0, af_model)
        })
        |> ignore
        c.box(style=af_hearts_row, fn() {
          c.shapes(af_hearts(hearts), w=Px(af_hearts_w), h=Px(af_heart_h)) |> ignore
          if hearts >= 5.0 {
            c.box(style=af_max_small, fn() { sr_words(c, @sf.t("web-main.stations.shareSenren.aff.max"), af_max_small_words) })
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
      c.box(style=af_num, fn() {
        sr_words(c, m.1, af_tokens)
        sr_words(c, m.2, af_cost)
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// Five hearts, `n` of them filled (by halves).
fn af_hearts(n : Double) -> Array[@ui.Shape] {
  let out : Array[@ui.Shape] = []
  for k in 0..<5 {
    let x = k.to_double() * (af_heart_w + af_heart_gap)
    out.push(@ui.shape_of([(gc_heart(x, 0.0, af_heart_w, af_heart_h, false), true)], fill=af_heart_pale))
    let left = n - k.to_double()
    if left >= 1.0 {
      out.push(@ui.shape_of([(gc_heart(x, 0.0, af_heart_w, af_heart_h, false), true)], fill=af_heart_full))
    } else if left >= 0.5 {
      out.push(@ui.shape_of([(gc_heart(x, 0.0, af_heart_w, af_heart_h, true), true)], fill=af_heart_full))
    }
  }
  out
}

///|
/// A figure's card under the routes: a heart and what it is, the figure large (its unit small after it), a line.
fn af_stat(c : @ui.Ctx, what : String, value : String, unit : String, sub : String) -> Unit {
  c.box(style=af_stat_ledge, fn() {
    c.box(style=af_stat_card, fn() {
      c.box(style=af_stat_k, fn() {
        c.shapes([@ui.shape_of([(gc_heart(0.0, 0.0, af_stat_heart_w, af_stat_heart_h, false), true)], fill=af_heart_full)], w=Px(af_stat_heart_w), h=Px(af_stat_heart_h))
        |> ignore
        sr_words(c, what, af_stat_k_words)
      })
      |> ignore
      sr_rich(c, [@ui.span(value, scale=af_stat_scale), @ui.span(" " + unit, weight=700)], af_stat_v)
      sr_words(c, sub, af_stat_sub)
    })
    |> ignore
  })
  |> ignore
}

///|
/// The heroines in their routes' order: her name's words, her colour, her picture (its width over its height) and
/// where her face is in it (its middle, its width: shares of the picture's).
// kept across runs: a table, never written
let af_girls : Array[(String, Int64, String, Double, Double, Double, Double)] = [
  ("web-main.stations.shareSenren.chat.murasame", 0x2F9E74FFL, "a1-murasame-adv", 0.6667, 0.5, 0.215, 0.2),
  ("web-main.stations.shareSenren.chat.yoshino", 0xD8364FFFL, "a2-yoshino-omikuji", 1.5, 0.775, 0.27, 0.16),
  ("web-main.stations.shareSenren.chat.mako", 0x2C3D78FFL, "a3-mako-roof", 1.5, 0.642, 0.275, 0.15),
  ("web-main.stations.shareSenren.chat.lena", 0x8352C4FFL, "a4-lena-ryokan", 1.5, 0.775, 0.275, 0.158),
  ("web-main.stations.shareSenren.chat.koharu", 0xEC5A92FFL, "a5-koharu-sweets", 1.5, 0.79, 0.265, 0.142),
  ("web-main.stations.shareSenren.chat.roka", 0x9B2747FFL, "a6-roka-ledger", 1.5, 0.772, 0.265, 0.135),
]

///|
let af_ground : Int64 = 0xFFDAE8FFL

///|
// kept across runs: a table, never written
let af_ground_stops : Array[(Double, Int64)] = [(0.0, 0xFFE9F2FFL), (0.55, 0xFFD9E8FFL), (1.0, 0xFFCFE1FFL)]

///|
let af_ink : Int64 = 0x5B2240FFL

///|
let af_rose : Int64 = 0xB0517CFFL

///|
let af_hot : Int64 = 0xEC4F8AFFL

///|
let af_heart_full : Int64 = 0xEF4F88FFL

///|
let af_heart_pale : Int64 = 0xF9D0DEFFL

///|
// kept across runs: a value (no field of it changes)
let af_inner : @ui.Style = @ui.css("w=Full pb=S4")

///|
// kept across runs: a value (no field of it changes)
let af_top : @ui.Style = @ui.css("row w=Full align=AEnd px=S4_5 pt=S4")

///|
// kept across runs: a value (no field of it changes)
let af_brand : @ui.TextStyle = @ui.text_style(size=Lg, weight=Bold, color=Data(af_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let af_at : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(af_rose), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let af_title_row : @ui.Style = @ui.css("row w=Full justify=JCenter align=ACenter gap=S1_5 pt=S1")

///|
let af_title_edge : Double = 3.0

///|
let af_title_drop : Double = 3.0

///|
let af_title_drop_ink : Int64 = 0xF5A3C3FFL

///|
// kept across runs: a value (no field of it changes)
let af_title : @ui.TextStyle = @ui.text_style(size=Xl4, weight=Bold, tracking=Wider, color=Data(af_hot), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let af_title_drop_words : @ui.TextStyle = af_title.then(@ui.text_style(color=Data(af_title_drop_ink)))

///|
let af_tag_ledge_bg : Int64 = 0xC2457AFFL

///|
// kept across runs: a value (no field of it changes)
let af_tag_ledge : @ui.Style = @ui.css("pb=S0_5 radius=Md").then(@ui.style(bg=Data(af_tag_ledge_bg)))

///|
// kept across runs: a value (no field of it changes)
let af_tag : @ui.Style = @ui.css("px=S2 py=S0_5 radius=Md").then(@ui.style(bg=Data(af_hot)))

///|
// kept across runs: a value (no field of it changes)
let af_tag_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, tracking=Widest, color=Data(gc_white), wrap=false)

///|
let af_now_ledge_bg : Int64 = 0xF2A9C6FFL

///|
// kept across runs: a value (no field of it changes)
let af_now_ledge : @ui.Style = @ui.css("mx=S3_5 mt=S2 pb=S1 radius=Full").then(@ui.style(bg=Data(af_now_ledge_bg)))

///|
// kept across runs: a value (no field of it changes)
let af_now : @ui.Style = @ui.css("row w=Full justify=JCenter align=ACenter gap=S2 py=S1_5 radius=Full").then(
  @ui.style(bg=Data(gc_white)),
)

///|
// kept across runs: a value (no field of it changes)
let af_now_words : @ui.TextStyle = @ui.text_style(size=Base, color=Data(af_ink), wrap=false)

///|
let af_max_bg : Int64 = 0xF0558FFFL

///|
// kept across runs: a value (no field of it changes)
let af_max : @ui.Style = @ui.css("px=S1_5 radius=Md").then(@ui.style(bg=Data(af_max_bg)))

///|
// kept across runs: a value (no field of it changes)
let af_max_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, tracking=@sf.share_letters_apart, color=Data(gc_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let af_list : @ui.Style = @ui.css("w=Full gap=S2 px=S3_5 pt=S3_5")

///|
let af_row_ledge_bg : Int64 = 0xF1B3CBFFL

///|
// kept across runs: a value (no field of it changes)
let af_row_ledge : @ui.Style = @ui.css("w=Full pb=S1 radius=Xl2").then(@ui.style(bg=Data(af_row_ledge_bg)))

///|
let af_row_ledge_lead_bg : Int64 = 0x9FD8C0FFL

///|
// kept across runs: a value (no field of it changes)
let af_row_ledge_lead : @ui.Style = @ui.css("w=Full pb=S1 radius=Xl2").then(@ui.style(bg=Data(af_row_ledge_lead_bg)))

///|
let af_row_bg : Int64 = 0xFFF7FAFFL

///|
// kept across runs: a value (no field of it changes)
let af_card : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter pl=S2_5 pr=S3 py=S1_5 radius=Xl2").then(
  @ui.style(bg=Data(af_row_bg)),
)

///|
let af_row_lead_edge : Int64 = 0x7FD9B3FFL

///|
// kept across runs: a value (no field of it changes)
let af_card_lead : @ui.Style = af_card.then(@ui.style(bg=Data(gc_white), border=B2, border_color=Data(af_row_lead_edge)))

///|
// kept across runs: a value (no field of it changes)
let af_av_ring : @ui.Style = @ui.css("p=S0_5 radius=Full")

///|
// kept across runs: a value (no field of it changes)
let af_av_white : @ui.Style = @ui.css("p=S0_5 radius=Full").then(@ui.style(bg=Data(gc_white)))

///|
let af_av_d : Double = 48.0

///|
let af_face_k : Double = 0.66

///|
// kept across runs: a value (no field of it changes)
let af_mid : @ui.Style = @ui.css("gap=S1").then(@ui.style(w=@sf.grow))

///|
// kept across runs: a value (no field of it changes)
let af_name_row : @ui.Style = @ui.css("row gap=S2 align=AEnd")

///|
let af_route_scale : Double = 1.1

///|
// kept across runs: a value (no field of it changes)
let af_route : @ui.TextStyle = @ui.text_style(size=Lg, weight=Bold, tracking=@sf.share_letters_apart, color=Data(af_ink), wrap=false)

///|
let af_model_ink : Int64 = 0x8E5574FFL

///|
// kept across runs: a value (no field of it changes)
let af_model : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(af_model_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let af_hearts_row : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
let af_heart_w : Double = 17.0

///|
let af_heart_h : Double = 16.0

///|
let af_heart_gap : Double = 2.0

///|
let af_hearts_w : Double = 93.0

///|
let af_max_small_bg : Int64 = 0xF0558FFFL

///|
// kept across runs: a value (no field of it changes)
let af_max_small : @ui.Style = @ui.css("px=S1 radius=Base").then(@ui.style(bg=Data(af_max_small_bg)))

///|
// kept across runs: a value (no field of it changes)
let af_max_small_words : @ui.TextStyle = @ui.text_style(size=Xs2, weight=Bold, tracking=@sf.share_letters_apart, color=Data(gc_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let af_num : @ui.Style = @ui.css("align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let af_tokens : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, color=Data(af_ink), wrap=false)

///|
let af_cost_ink : Int64 = 0xA0607EFFL

///|
// kept across runs: a value (no field of it changes)
let af_cost : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(af_cost_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let af_stats : @ui.Style = @ui.css("row w=Full gap=S2_5 px=S3_5 pt=S3_5")

///|
let af_stat_ledge_bg : Int64 = 0xF1B3CBFFL

///|
// kept across runs: a value (no field of it changes)
let af_stat_ledge : @ui.Style = @ui.css("pb=S1 radius=Xl2").then(@ui.style(w=@sf.grow, bg=Data(af_stat_ledge_bg)))

///|
// kept across runs: a value (no field of it changes)
let af_stat_card : @ui.Style = @ui.css("w=Full px=S3 py=S1_5 radius=Xl2 gap=S0_5").then(@ui.style(bg=Data(gc_white)))

///|
// kept across runs: a value (no field of it changes)
let af_stat_k : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
let af_stat_heart_w : Double = 13.0

///|
let af_stat_heart_h : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let af_stat_k_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(af_rose), wrap=false)

///|
let af_stat_scale : Double = 1.7

///|
// kept across runs: a value (no field of it changes)
let af_stat_v : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(af_ink), wrap=false)

///|
let af_stat_sub_ink : Int64 = 0xA0607EFFL

///|
// kept across runs: a value (no field of it changes)
let af_stat_sub : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(af_stat_sub_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let af_foot : @ui.Style = @ui.css("w=Full align=ACenter pt=S3")

///|
// kept across runs: a value (no field of it changes)
let af_tagline : @ui.TextStyle = @ui.text_style(size=Xs, tracking=Widest, color=Data(af_rose), wrap=false)

// ── 穗织女子会 ─────────────────────────────────────────────────────────────

///|
/// 「穗织女子会」: the girls' group chat on a phone. Its status bar at the time of the card, the group's bar; each says a
/// figure in her voice (丛雨 the top model's tokens, 芳乃 its cost, 茉子 the tasks across devices, 蕾娜 the devices, 小春
/// the chats at work), 因幡巡 joins with her Ciallo, 茉子 asks if she is in the wrong game, 芳乃 sends her dog-ear
/// sticker, 芦花 the week's archived; each a minute or so before the card's time. The field to write in, still.fail.
fn sr_chat(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = gc_args(fleet)
  let now = ch_minutes(sr_arg(args, "at"))
  sr_box(c, id, flat, ch_ground, fn() {
    // the phone's status bar
    c.box(style=ch_status, fn() {
      sr_words(c, ch_clock(now, 0), ch_status_words)
      c.box(style=gc_grow, fn() {  }) |> ignore
      c.box(style=ch_bars, fn() {
        for h in ch_signal {
          c.box(style=ch_signal_bar.then(@ui.style(h=Fixed(h))), fn() {  }) |> ignore
        }
      })
      |> ignore
      c.box(style=ch_battery_row, fn() {
        c.box(style=ch_battery, fn() { c.box(style=ch_battery_fill, fn() {  }) |> ignore }) |> ignore
        c.box(style=ch_battery_nub, fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
    // the group's bar
    c.box(style=ch_bar, fn() {
      sr_words(c, "‹", ch_back)
      c.box(style=gc_grow, fn() {
        sr_rich(
          c,
          [@ui.span(@sf.t("web-main.stations.shareSenren.chat.group")), @ui.span(@sf.t("web-main.stations.shareSenren.chat.count"), weight=500, color=ch_count_ink)],
          ch_group,
        )
      })
      |> ignore
      c.shapes(ch_search(), w=Px(ch_icon), h=Px(ch_icon)) |> ignore
      c.shapes(ch_menu(), w=Px(ch_icon), h=Px(ch_icon)) |> ignore
    })
    |> ignore
    c.box(style=ch_rule, fn() {  }) |> ignore
    c.box(style=ch_log, fn() {
      c.box(style=ch_pill_row, fn() {
        c.box(style=ch_day, fn() { sr_words(c, @sf.t("web-main.stations.shareSenren.chat.today"), ch_pill_words) }) |> ignore
      })
      |> ignore
      ch_said(c, 0, sr_said("web-main.stations.shareSenren.chat.m1", args, ch_hi), ch_clock(now, 9), false)
      ch_said(c, 1, sr_said("web-main.stations.shareSenren.chat.m2", args, ch_hi), ch_clock(now, 8), false)
      ch_said(c, 2, sr_said("web-main.stations.shareSenren.chat.m3", args, ch_hi), ch_clock(now, 7), false)
      ch_said(c, 3, sr_said("web-main.stations.shareSenren.chat.m4", args, ch_hi), ch_clock(now, 6), false)
      ch_said(c, 4, sr_said("web-main.stations.shareSenren.chat.m5", args, ch_hi), ch_clock(now, 5), false)
      c.box(style=ch_pill_row, fn() {
        c.box(style=ch_sys, fn() { sr_words(c, @sf.t("web-main.stations.shareSenren.chat.join"), ch_pill_words) }) |> ignore
      })
      |> ignore
      ch_said(c, 6, [@ui.span(@sf.t("web-main.stations.shareSenren.chat.ciallo"), weight=700, color=ch_ciallo)], ch_clock(now, 3), false)
      ch_said(c, 2, [@ui.span(@sf.t("web-main.stations.shareSenren.chat.m7"))], ch_clock(now, 2), false)
      ch_said(c, 1, [], ch_clock(now, 1), true)
      ch_said(c, 5, sr_said("web-main.stations.shareSenren.chat.m9", args, ch_hi), ch_clock(now, 0), false)
    })
    |> ignore
    // the field to write in
    c.box(style=ch_rule, fn() {  }) |> ignore
    c.box(style=ch_input, fn() {
      sr_words(c, "+", ch_plus)
      c.box(style=ch_field, fn() { sr_words(c, @sf.t("web-main.stations.shareSenren.chat.input"), ch_field_words) }) |> ignore
      c.shapes(ch_mic(), w=Px(ch_icon), h=Px(ch_icon)) |> ignore
    })
    |> ignore
    c.box(style=ch_foot, fn() {
      sr_brand(c, ch_brand)
      sr_words(c, @sf.t("web-main.stations.shareTagline"), ch_foot_words)
      c.box(style=gc_grow, fn() {  }) |> ignore
      sr_words(c, sr_arg(args, "at"), ch_foot_words)
    })
    |> ignore
  })
}

///|
/// One of the group says `runs` at `time` (`who` her place in ch_who): her face and name, the bubble (or 芳乃's dog-ear
/// sticker), the time after it.
fn ch_said(c : @ui.Ctx, who : Int, runs : Array[@ui.Run], time : String, sticker : Bool) -> Unit {
  let w = ch_who[who]
  c.box(style=ch_msg, fn() {
    c.box(style=ch_av_ring, fn() {
      if w.2 == "" {
        c.box(style=ch_av_letter, fn() { sr_words(c, @sf.t(w.1), ch_av_letter_words) }) |> ignore
      } else {
        gc_face(c, w.2, w.3, ch_av_d, w.4, w.5, w.6, ch_face_k)
      }
    })
    |> ignore
    c.box(style=ch_msg_body, fn() {
      sr_words(c, @sf.t(w.0), ch_name)
      c.box(style=ch_line, fn() {
        if sticker {
          c.box(style=ch_sticker, fn() {
            gc_pic(c, ch_sticker_cut, "b2-chibi-yoshino-ears", 1.0, ch_sticker_d, ch_sticker_d, 1.0, 0.5, 0.3)
          })
          |> ignore
        } else {
          c.box(style=ch_bubble, fn() {
            c.box(left=ch_tail_x, top=ch_tail_y, fn() { c.shapes(ch_tail(), w=Px(ch_tail_w), h=Px(ch_tail_h)) |> ignore }) |> ignore
            sr_rich(c, runs, ch_words)
          })
          |> ignore
        }
        sr_words(c, time, ch_time)
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The minutes into its day of the time at the end of `at` (「10月26日 04:12」: 252), -1 for none.
fn ch_minutes(at : String) -> Int {
  let mut h = 0
  let mut m = 0
  let mut colon = false
  let mut any = false
  for ch in at {
    if ch == ' ' {
      h = 0
      m = 0
      colon = false
      any = false
    } else if ch == ':' {
      colon = true
    } else if ch >= '0' && ch <= '9' {
      any = true
      if colon {
        m = m * 10 + (ch.to_int() - '0'.to_int())
      } else {
        h = h * 10 + (ch.to_int() - '0'.to_int())
      }
    }
  }
  if any && colon {
    h * 60 + m
  } else {
    -1
  }
}

///|
/// The time `back` minutes before `now` (as a phone says it: 4:03), "" when there is none.
fn ch_clock(now : Int, back : Int) -> String {
  if now < 0 {
    return ""
  }
  let t = (now - back + 24 * 60) % (24 * 60)
  let m = t % 60
  (t / 60).to_string() + ":" + (if m < 10 { "0" } else { "" }) + m.to_string()
}

///|
/// The bubble's tail: a small white point out of its left, near its top.
fn ch_tail() -> Array[@ui.Shape] {
  [@ui.shape_of([([ch_tail_w, 0.0, 0.0, ch_tail_h / 2.0, ch_tail_w, ch_tail_h], true)], fill=gc_white)]
}

///|
/// The search icon: a ring and its handle.
fn ch_search() -> Array[@ui.Shape] {
  let k = ch_icon / 24.0
  [
    @ui.shape_of([(gc_flat(gc_ellipse(10.5, 10.5, 6.5, 6.5), k~), true)], stroke=ch_icon_ink, width=2.0 * k),
    @ui.shape_of([(gc_flat([(15.5, 15.5), (20.0, 20.0)], k~), false)], stroke=ch_icon_ink, width=2.0 * k),
  ]
}

///|
/// The menu icon: three lines.
fn ch_menu() -> Array[@ui.Shape] {
  let k = ch_icon / 24.0
  [6.0, 12.0, 18.0].map(fn(y) { @ui.shape_of([(gc_flat([(4.0, y), (20.0, y)], k~), false)], stroke=ch_icon_ink, width=2.0 * k) })
}

///|
/// The microphone icon: its head, its cup, its stem.
fn ch_mic() -> Array[@ui.Shape] {
  let k = ch_icon / 24.0
  let head : Array[(Double, Double)] = [(9.0, 6.0)]
  gc_quad(head, (9.0, 6.0), (9.0, 3.0), (12.0, 3.0), 6)
  gc_quad(head, (12.0, 3.0), (15.0, 3.0), (15.0, 6.0), 6)
  head.push((15.0, 11.0))
  gc_quad(head, (15.0, 11.0), (15.0, 14.0), (12.0, 14.0), 6)
  gc_quad(head, (12.0, 14.0), (9.0, 14.0), (9.0, 11.0), 6)
  let cup : Array[(Double, Double)] = [(5.5, 11.0)]
  gc_quad(cup, (5.5, 11.0), (5.5, 17.5), (12.0, 17.5), 8)
  gc_quad(cup, (12.0, 17.5), (18.5, 17.5), (18.5, 11.0), 8)
  [
    @ui.shape_of([(gc_flat(head, k~), true)], stroke=ch_mic_ink, width=2.0 * k),
    @ui.shape_of([(gc_flat(cup, k~), false)], stroke=ch_mic_ink, width=2.0 * k),
    @ui.shape_of([(gc_flat([(12.0, 17.5), (12.0, 21.0)], k~), false)], stroke=ch_mic_ink, width=2.0 * k),
  ]
}

///|
/// Who is in the group: her name's words, a letter's words for a face (因幡巡, who has no picture here), her picture
/// (its width over its height) and where her face is in it.
// kept across runs: a table, never written
let ch_who : Array[(String, String, String, Double, Double, Double, Double)] = [
  ("web-main.stations.shareSenren.chat.murasame", "", "a1-murasame-adv", 0.6667, 0.5, 0.215, 0.2),
  ("web-main.stations.shareSenren.chat.yoshino", "", "a2-yoshino-omikuji", 1.5, 0.775, 0.27, 0.16),
  ("web-main.stations.shareSenren.chat.mako", "", "a3-mako-roof", 1.5, 0.642, 0.275, 0.15),
  ("web-main.stations.shareSenren.chat.lena", "", "a4-lena-ryokan", 1.5, 0.775, 0.275, 0.158),
  ("web-main.stations.shareSenren.chat.koharu", "", "a5-koharu-sweets", 1.5, 0.79, 0.265, 0.142),
  ("web-main.stations.shareSenren.chat.roka", "", "a6-roka-ledger", 1.5, 0.772, 0.265, 0.135),
  ("web-main.stations.shareSenren.chat.meguru", "web-main.stations.shareSenren.chat.meguruFace", "", 1.0, 0.5, 0.5, 1.0),
]

///|
let ch_ground : Int64 = 0xA9BEDDFFL

///|
let ch_hi : Int64 = 0xD23F6EFFL

///|
let ch_ciallo : Int64 = 0xE0447DFFL

///|
let ch_ink : Int64 = 0x1F2633FFL

///|
let ch_dark : Int64 = 0x222222FFL

///|
// kept across runs: a value (no field of it changes)
let ch_status : @ui.Style = @ui.css("row w=Full align=ACenter px=S4 gap=S1_5").then(@ui.style(h=Fixed(ch_status_h), bg=Data(gc_white)))

///|
let ch_status_h : Double = 24.0

///|
// kept across runs: a value (no field of it changes)
let ch_status_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(ch_dark), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ch_bars : @ui.Style = @ui.css("row gap=SPx align=AEnd")

///|
/// The signal's bars, how tall each is.
// kept across runs: a table, never written
let ch_signal : Array[Double] = [4.0, 6.0, 8.0, 10.0]

///|
let ch_signal_w : Double = 3.0

///|
// kept across runs: a value (no field of it changes)
let ch_signal_bar : @ui.Style = @ui.css("radius=Sm").then(@ui.style(w=Fixed(ch_signal_w), bg=Data(ch_dark)))

///|
// kept across runs: a value (no field of it changes)
let ch_battery_row : @ui.Style = @ui.css("row align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ch_battery : @ui.Style = @ui.css("p=SPx radius=Base border=B1_5").then(
  @ui.style(w=Fixed(ch_battery_w), h=Fixed(ch_battery_h), border_color=Data(ch_dark)),
)

///|
let ch_battery_w : Double = 22.0

///|
let ch_battery_h : Double = 11.0

///|
// kept across runs: a value (no field of it changes)
let ch_battery_fill : @ui.Style = @ui.css("h=Full radius=Sm").then(@ui.style(w=Pct(ch_battery_pct), bg=Data(ch_dark)))

///|
let ch_battery_pct : Double = 72.0

///|
// kept across runs: a value (no field of it changes)
let ch_battery_nub : @ui.Style = @ui.css("w=S0_5 h=S1 radius=Sm").then(@ui.style(bg=Data(ch_dark)))

///|
// kept across runs: a value (no field of it changes)
let ch_bar : @ui.Style = @ui.css("row w=Full align=ACenter gap=S4 pl=S2_5 pr=S3_5").then(@ui.style(h=Fixed(ch_bar_h), bg=Data(gc_white)))

///|
let ch_bar_h : Double = 46.0

///|
// kept across runs: a value (no field of it changes)
let ch_back : @ui.TextStyle = @ui.text_style(size=Xl4, color=Data(ch_dark), wrap=false)

///|
let ch_count_ink : Int64 = 0x555555FFL

///|
let ch_group_ink : Int64 = 0x111111FFL

///|
// kept across runs: a value (no field of it changes)
let ch_group : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, color=Data(ch_group_ink), wrap=false)

///|
let ch_icon : Double = 20.0

///|
let ch_icon_ink : Int64 = 0x222222FFL

///|
let ch_mic_ink : Int64 = 0x444444FFL

///|
let ch_rule_bg : Int64 = 0x0000001AL

///|
// kept across runs: a value (no field of it changes)
let ch_rule : @ui.Style = @ui.css("w=Full h=SPx").then(@ui.style(bg=Data(ch_rule_bg)))

///|
// kept across runs: a value (no field of it changes)
let ch_log : @ui.Style = @ui.css("w=Full gap=S1_5 pt=S2 pb=S3 px=S2_5")

///|
// kept across runs: a value (no field of it changes)
let ch_pill_row : @ui.Style = @ui.css("w=Full align=ACenter")

///|
let ch_day_bg : Int64 = 0x0000002EL

///|
// kept across runs: a value (no field of it changes)
let ch_day : @ui.Style = @ui.css("px=S3 radius=Full").then(@ui.style(bg=Data(ch_day_bg)))

///|
let ch_sys_bg : Int64 = 0x00000033L

///|
// kept across runs: a value (no field of it changes)
let ch_sys : @ui.Style = @ui.css("px=S3 py=S0_5 radius=Full").then(@ui.style(bg=Data(ch_sys_bg)))

///|
// kept across runs: a value (no field of it changes)
let ch_pill_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(gc_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ch_msg : @ui.Style = @ui.css("row w=Full gap=S1_5 align=AStart").then(@ui.style(bg=Data(ch_ground)))

///|
let ch_av_ring_bg : Int64 = 0xFFFFFFCCL

///|
// kept across runs: a value (no field of it changes)
let ch_av_ring : @ui.Style = @ui.css("p=S0_5 radius=Full").then(@ui.style(bg=Data(ch_av_ring_bg)))

///|
let ch_av_d : Double = 34.0

///|
let ch_face_k : Double = 0.7

///|
let ch_av_letter_bg : Int64 = 0xB9BEC8FFL

///|
// kept across runs: a value (no field of it changes)
let ch_av_letter : @ui.Style = @ui.css("radius=Full align=ACenter justify=JCenter").then(
  @ui.style(w=Fixed(ch_av_d), h=Fixed(ch_av_d), bg=Data(ch_av_letter_bg)),
)

///|
let ch_av_letter_words_ink : Int64 = 0xF4F5F7FFL

///|
// kept across runs: a value (no field of it changes)
let ch_av_letter_words : @ui.TextStyle = @ui.text_style(size=Lg, weight=Bold, color=Data(ch_av_letter_words_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ch_msg_body : @ui.Style = @ui.css("gap=S1").then(@ui.style(w=@sf.grow))

///|
let ch_name_ink : Int64 = 0x3B4A63FFL

///|
// kept across runs: a value (no field of it changes)
let ch_name : @ui.TextStyle = @ui.text_style(size=Xs2, leading=L3, color=Data(ch_name_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ch_line : @ui.Style = @ui.css("row gap=S1 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let ch_bubble : @ui.Style = @ui.css("px=S2_5 pt=S1_5 pb=S1_5 radius=Xl2").then(@ui.style(max_w=Fixed(ch_bubble_most), bg=Data(gc_white)))

///|
let ch_bubble_most : Double = 268.0

///|
let ch_tail_x : Double = -5.0

///|
let ch_tail_y : Double = 9.0

///|
let ch_tail_w : Double = 6.0

///|
let ch_tail_h : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let ch_words : @ui.TextStyle = @ui.text_style(size=Base, leading=L4_75, color=Data(ch_ink))

///|
let ch_time_ink : Int64 = 0x4D5D78FFL

///|
// kept across runs: a value (no field of it changes)
let ch_time : @ui.TextStyle = @ui.text_style(size=Xs3, color=Data(ch_time_ink), wrap=false)

///|
let ch_sticker_d : Double = 92.0

///|
// kept across runs: a value (no field of it changes)
let ch_sticker : @ui.Style = @ui.css("p=S1 radius=Xl3").then(@ui.style(bg=Data(gc_white)))

///|
// kept across runs: a value (no field of it changes)
let ch_sticker_cut : @ui.Style = @ui.css("radius=Xl2 clip")

///|
// kept across runs: a value (no field of it changes)
let ch_input : @ui.Style = @ui.css("row w=Full align=ACenter gap=S2_5 px=S3").then(@ui.style(h=Fixed(ch_bar_h), bg=Data(gc_white)))

///|
let ch_plus_ink : Int64 = 0x444444FFL

///|
// kept across runs: a value (no field of it changes)
let ch_plus : @ui.TextStyle = @ui.text_style(size=Xl3, color=Data(ch_plus_ink), wrap=false)

///|
let ch_field_bg : Int64 = 0xF1F2F5FFL

///|
// kept across runs: a value (no field of it changes)
let ch_field : @ui.Style = @ui.css("h=S7 px=S3 radius=Full justify=JCenter").then(@ui.style(w=@sf.grow, bg=Data(ch_field_bg)))

///|
let ch_field_words_ink : Int64 = 0x8A909BFFL

///|
// kept across runs: a value (no field of it changes)
let ch_field_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(ch_field_words_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ch_foot : @ui.Style = @ui.css("row w=Full align=AEnd gap=S2_5 px=S4 pt=S2 pb=S3").then(@ui.style(bg=Data(gc_white)))

///|
// kept across runs: a value (no field of it changes)
let ch_brand : @ui.TextStyle = @ui.text_style(size=Base, weight=Bold, color=Data(ch_dark), wrap=false)

///|
let ch_foot_words_ink : Int64 = 0x8A909BFFL

///|
// kept across runs: a value (no field of it changes)
let ch_foot_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(ch_foot_words_ink), wrap=false)

// ── 片尾 · STAFF ───────────────────────────────────────────────────────────

///|
/// 片尾 · STAFF: the ending's credits over dusk on the hot-spring town from the shrine's steps (c5-staffroll-bg), sky and
/// town darkened under them, the two on the steps left in the clear and THE END under them. Starring the top model (its
/// tokens and cost), co-starring the others (the most tokens first), funded by each kind of account, the devices on
/// location, the tasks across devices its stunts, the theme song, the week's archived its episodes; still.fail and when.
fn sr_staff(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = gc_args(fleet)
  let co : Array[String] = []
  for i, m in gc_ranked(fleet) {
    if i > 0 {
      co.push(m.0)
    }
  }
  let funds : Array[String] = []
  for q in items(fleet, "spent") {
    let q = Some(q)
    funds.push(
      @sf.t("web-main.stations.shareSenren.staff.fund", args=[
        ("n", count(q, "accounts").to_string()),
        ("kind", text(q, "name")),
      ]),
    )
  }
  sr_box(c, id, flat, sfr_ground, fn() {
    sr_art(c, "c5-staffroll-bg", @sf.share_w_most, sfr_h, at=0.5) |> ignore
    c.layer(fn() { gc_grad(c, sfr_dim_stops, sfr_dim_bands) }) |> ignore
    c.box(style=sfr_roll, left=sfr_side, top=sfr_roll_top, fn() {
      sr_rich(c, gc_caps(@sf.t("web-main.stations.shareSenren.staff.staff"), sfr_caps_small, true), sfr_staff)
      c.box(style=sfr_orn, fn() {
        c.box(style=sfr_orn_line, fn() {  }) |> ignore
        sr_words(c, "✿", sfr_orn_mark)
        c.box(style=sfr_orn_line, fn() {  }) |> ignore
      })
      |> ignore
      sfr_section(c, "web-main.stations.shareSenren.staff.lead", fn() {
        sr_words(c, sr_arg(args, "model"), sfr_who_big)
        sr_rich(c, sr_said("web-main.stations.shareSenren.staff.leadLine", args, sfr_gold), sfr_sub)
      })
      sfr_section(c, "web-main.stations.shareSenren.staff.co", fn() { sfr_rows(c, co, 3) })
      sfr_section(c, "web-main.stations.shareSenren.staff.funds", fn() { sfr_rows(c, funds, 2) })
      sfr_section(c, "web-main.stations.shareSenren.staff.location", fn() {
        sr_words(c, @sf.t("web-main.stations.shareSenren.staff.devices", args~), sfr_who)
      })
      sfr_section(c, "web-main.stations.shareSenren.staff.stunts", fn() {
        sr_words(c, @sf.t("web-main.stations.shareSenren.staff.tasks", args~), sfr_who)
      })
      sfr_section(c, "web-main.stations.shareSenren.staff.song", fn() {
        sr_words(c, @sf.t("web-main.stations.shareSenren.staff.songName"), sfr_who)
        sr_words(c, @sf.t("web-main.stations.shareSenren.staff.singer"), sfr_sub)
      })
      sfr_section(c, "web-main.stations.shareSenren.staff.done", fn() {
        sr_words(c, @sf.t("web-main.stations.shareSenren.staff.episodes", args~), sfr_who)
        sr_words(c, @sf.t("web-main.stations.shareTagline"), sfr_sub)
      })
    })
    |> ignore
    c.box(style=sfr_end, left=0.0, top=sfr_end_top, fn() {
      sr_rich(c, gc_caps(@sf.t("web-main.stations.shareSenren.staff.end"), sfr_caps_small, true), sfr_end_words)
      sr_rich(c, [@ui.span(@sf.t("web-main.stations.shareSenren.staff.thanks"), italic=true)], sfr_thanks)
    })
    |> ignore
    c.box(style=sfr_foot, left=sfr_side, top=sfr_h - sfr_foot_up, fn() {
      sr_brand(c, sfr_brand)
      c.box(style=gc_grow, fn() {  }) |> ignore
      sr_words(c, sr_arg(args, "at"), sfr_at)
    })
    |> ignore
  })
}

///|
/// A credit: its role spread small in the gold, who under it.
fn sfr_section(c : @ui.Ctx, role : String, body : () -> Unit) -> Unit {
  c.box(style=sfr_sec, fn() {
    sr_words(c, gc_spread(@sf.t(role)), sfr_role)
    body()
  })
  |> ignore
}

///|
/// Names `per` to a line, a gold dot between each two.
fn sfr_rows(c : @ui.Ctx, names : Array[String], per : Int) -> Unit {
  let mut i = 0
  while i < names.length() {
    let runs : Array[@ui.Run] = []
    let upto = if i + per < names.length() { i + per } else { names.length() }
    for j in i..<upto {
      if j > i {
        runs.push(@ui.span("  ·  ", color=sfr_dot))
      }
      runs.push(@ui.span(names[j]))
    }
    sr_rich(c, runs, sfr_who)
    i = upto
  }
}

///|
let sfr_h : Double = 820.0

///|
let sfr_ground : Int64 = 0x1C1238FFL

///|
/// The dark the credits roll over: deep over the sky and town, all but gone over the two on the steps, deep again
/// at the foot.
// kept across runs: a table, never written
let sfr_dim_stops : Array[(Double, Int64)] = [
  (0.0, 0x120C1E66L),
  (0.06, 0x120C1EB0L),
  (0.14, 0x120C1ECCL),
  (0.6, 0x120C1ED2L),
  (0.665, 0x120C1EC4L),
  (0.715, 0x120C1E2EL),
  (0.82, 0x120C1E24L),
  (0.875, 0x120C1EA8L),
  (1.0, 0x120C1EE0L),
]

///|
let sfr_dim_bands : Int = 82

///|
let sfr_side : Double = 20.0

///|
let sfr_roll_top : Double = 30.0

///|
let sfr_gold : Int64 = 0xF2D58AFFL

///|
let sfr_dot : Int64 = 0xE8C97AFFL

///|
let sfr_roll_w : Double = @sf.share_w_most - 2.0 * sfr_side

///|
// kept across runs: a value (no field of it changes)
let sfr_roll : @ui.Style = @ui.css("align=ACenter").then(@ui.style(w=Fixed(sfr_roll_w)))

///|
let sfr_caps_small : Double = 0.78

///|
// kept across runs: a value (no field of it changes)
let sfr_staff : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Medium, tracking=Widest, color=Data(sfr_gold), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sfr_orn : @ui.Style = @ui.css("row gap=S2_5 align=ACenter pt=S1 pb=S0_5")

///|
let sfr_orn_w : Double = 54.0

///|
let sfr_orn_line_bg : Int64 = 0xF2D58AAAL

///|
// kept across runs: a value (no field of it changes)
let sfr_orn_line : @ui.Style = @ui.css("h=SPx").then(@ui.style(w=Fixed(sfr_orn_w), bg=Data(sfr_orn_line_bg)))

///|
// kept across runs: a value (no field of it changes)
let sfr_orn_mark : @ui.TextStyle = @ui.text_style(size=Xs3, color=Data(sfr_gold), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sfr_sec : @ui.Style = @ui.css("w=Full align=ACenter gap=S0_5 pt=S3")

///|
// kept across runs: a value (no field of it changes)
let sfr_role : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(sfr_dot), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sfr_who : @ui.TextStyle = @ui.text_style(size=Xl, color=Data(gc_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sfr_who_big : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Bold, color=Data(gc_white), wrap=false)

///|
let sfr_sub_ink : Int64 = 0xE9DEF0FFL

///|
// kept across runs: a value (no field of it changes)
let sfr_sub : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(sfr_sub_ink), wrap=false)

///|
let sfr_end_top : Double = 690.0

///|
// kept across runs: a value (no field of it changes)
let sfr_end : @ui.Style = @ui.css("align=ACenter gap=S0_5").then(@ui.style(w=Fixed(@sf.share_w_most)))

///|
// kept across runs: a value (no field of it changes)
let sfr_end_words : @ui.TextStyle = @ui.text_style(size=Xl4, weight=Bold, tracking=Widest, color=Data(gc_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sfr_thanks : @ui.TextStyle = @ui.text_style(size=Lg, tracking=@sf.share_letters_apart, color=Data(sfr_gold), wrap=false)

///|
let sfr_foot_up : Double = 38.0

///|
let sfr_foot_w : Double = @sf.share_w_most - 2.0 * sfr_side

///|
// kept across runs: a value (no field of it changes)
let sfr_foot : @ui.Style = @ui.css("row align=AEnd").then(@ui.style(w=Fixed(sfr_foot_w)))

///|
// kept across runs: a value (no field of it changes)
let sfr_brand : @ui.TextStyle = @ui.text_style(size=Lg, weight=Bold, color=Data(gc_white), wrap=false)

///|
let sfr_at_ink : Int64 = 0xE9DEF0FFL

///|
// kept across runs: a value (no field of it changes)
let sfr_at : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(sfr_at_ink), wrap=false)

// ── 刀剑鉴定书 ─────────────────────────────────────────────────────────────

///|
/// 丛雨丸 · 刀剑鉴定书: a sword's appraisal on washi in a red double frame, 特别保存刀剑 鉴定书 and 建实神社's seal. Its
/// oshigata (the blade's ink rubbing, drawn) has the week in its temper line: the hamon runs through the seven days'
/// shares of their chats archived, each a red dot with its count and date under it. Its fields: 丛雨丸 of 建实神社, its
/// length the top model's tokens, its price their cost, 锋利无比 (no blunt blade), once snapped by 有地将臣. Signed by
/// still.fail with its seal, when; 丛雨 pouting in a taped photo, 「吾辈才不是钝刀！」.
fn sr_sword(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = gc_args(fleet)
  let days = sr_days(fleet)
  let small = fn(runs : Array[@ui.Run]) {
    runs.map(fn(r) { @ui.span(r.text, scale=swd_small_scale, color=swd_note) })
  }
  sr_box(c, id, flat, swd_ground, fn() {
    c.box(style=swd_pad, fn() {
      c.box(style=swd_frame, fn() {
        c.box(style=swd_inner, fn() {
          c.box(style=swd_corner, left=swd_corner_in, top=swd_corner_top, fn() { sr_words(c, "❖", swd_corner_mark) }) |> ignore
          c.box(style=swd_corner, right=swd_corner_in, top=swd_corner_top, fn() { sr_words(c, "❖", swd_corner_mark) }) |> ignore
          c.box(style=swd_heads, fn() {
            sr_words(c, gc_spread_han(@sf.t("web-main.stations.shareSenren.sword.kick")), swd_kick)
            sr_rich(c, [@ui.span(gc_spread_han(@sf.t("web-main.stations.shareSenren.sword.title")), scale=swd_title_scale)], swd_title)
          })
          |> ignore
          c.box(style=swd_seal_big, right=swd_seal_right, top=swd_seal_top, fn() {
            swd_seal_words(c, @sf.t("web-main.stations.shareSenren.sword.seal1"), swd_seal_big_words)
          })
          |> ignore
          // the oshigata
          c.box(style=swd_blade_row, fn() {
            c.box(style=swd_blade_box, fn() {
              c.shapes(swd_blade(days), w=Px(swd_blade_w), h=Px(swd_blade_h)) |> ignore
              let mid = (swd_back(0.0) + 1.8 + swd_edge(0.0) - 4.5) / 2.0
              c.box(style=swd_tang_box, left=swd_tang_x - swd_tang_w / 2.0, top=mid - swd_tang_up, fn() {
                sr_rich(c, [@ui.span(@sf.t("web-main.stations.shareSenren.sword.tang"), scale=swd_tang_scale)], swd_tang_words)
              })
              |> ignore
              for i, d in days {
                let x = swd_x(swd_knot_t(i, days.length()))
                c.box(style=swd_label_box, left=x - swd_label_w / 2.0, top=swd_n_top, fn() { sr_words(c, d.2, swd_n) }) |> ignore
                c.box(style=swd_label_box, left=x - swd_label_w / 2.0, top=swd_date_top, fn() {
                  sr_rich(
                    c,
                    [@ui.span(if d.4 { @sf.t("web-main.stations.shareSenren.sword.today") } else { d.0 }, scale=swd_date_scale)],
                    if d.4 {
                      swd_date_today
                    } else {
                      swd_date
                    },
                  )
                })
                |> ignore
              }
            })
            |> ignore
          })
          |> ignore
          c.box(style=swd_rule, fn() {  }) |> ignore
          c.box(style=swd_fields, fn() {
            swd_field(c, "web-main.stations.shareSenren.sword.kind", [@ui.span(@sf.t("web-main.stations.shareSenren.sword.kindV"))], true)
            swd_field(
              c,
              "web-main.stations.shareSenren.sword.mei",
              [@ui.span(@sf.t("web-main.stations.shareSenren.sword.meiV"))] +
              small([@ui.span(@sf.t("web-main.stations.shareSenren.sword.meiNote"))]),
              false,
            )
            swd_field(
              c,
              "web-main.stations.shareSenren.sword.length",
              sr_said("web-main.stations.shareSenren.sword.lengthV", args, swd_ink, scale=swd_big_scale) +
              small(sr_said("web-main.stations.shareSenren.sword.lengthNote", args, swd_note)),
              false,
            )
            swd_field(
              c,
              "web-main.stations.shareSenren.sword.hamon",
              [@ui.span(@sf.t("web-main.stations.shareSenren.sword.hamonV"))] +
              small(sr_said("web-main.stations.shareSenren.sword.hamonNote", args, swd_note)),
              false,
            )
            swd_field(
              c,
              "web-main.stations.shareSenren.sword.price",
              sr_said("web-main.stations.shareSenren.sword.priceV", args, swd_ink, scale=swd_big_scale),
              false,
            )
            swd_field(
              c,
              "web-main.stations.shareSenren.sword.verdict",
              [@ui.span(@sf.t("web-main.stations.shareSenren.sword.verdictV"), weight=700, color=swd_say)],
              false,
            )
            swd_field(c, "web-main.stations.shareSenren.sword.note", [@ui.span(@sf.t("web-main.stations.shareSenren.sword.noteV"))], false)
          })
          |> ignore
          // the signature, and 丛雨 pouting
          c.box(style=swd_bottom, fn() {
            c.box(style=swd_sign, fn() {
              sr_words(c, @sf.t("web-main.stations.shareSenren.sword.cert"), swd_cert)
              sr_words(c, sr_arg(args, "at"), swd_date_line)
              c.box(style=swd_by, fn() {
                sr_words(c, @sf.t("web-main.stations.shareSenren.sword.by"), swd_by_words)
                sr_brand(c, swd_brand)
                c.box(style=swd_seal_small, fn() {
                  swd_seal_words(c, @sf.t("web-main.stations.shareSenren.sword.seal2"), swd_seal_small_words)
                })
                |> ignore
              })
              |> ignore
              sr_words(c, @sf.t("web-main.stations.shareTagline"), swd_tag)
            })
            |> ignore
            c.box(style=swd_pout, fn() {
              c.box(style=swd_photo, fn() {
                gc_pic(c, swd_photo_cut, "b6-chibi-murasame-pout", 1.0, swd_photo_d, swd_photo_d, swd_photo_zoom, 0.5, swd_photo_fy)
              })
              |> ignore
              c.box(style=swd_tape, left=swd_tape_x, top=swd_tape_y, fn() {  }) |> ignore
            })
            |> ignore
            c.box(style=swd_bubble, right=swd_bubble_right, bottom=swd_bubble_bottom, fn() {
              sr_words(c, @sf.t("web-main.stations.shareSenren.sword.pout"), swd_bubble_words)
              c.box(right=swd_tail_right, bottom=-swd_tail_h + swd_tail_over, fn() {
                c.shapes(swd_tail(), w=Px(swd_tail_w), h=Px(swd_tail_h)) |> ignore
              })
              |> ignore
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// A field of the certificate: its name spread in the red, what it is after it; a hairline over it but the first's.
fn swd_field(c : @ui.Ctx, key : String, runs : Array[@ui.Run], first : Bool) -> Unit {
  if !first {
    c.box(style=swd_field_rule, fn() {  }) |> ignore
  }
  c.box(style=swd_field_row, fn() {
    c.box(style=swd_k_box, fn() { sr_words(c, gc_spread_han(@sf.t(key)), swd_k) }) |> ignore
    c.box(style=gc_grow, fn() { sr_rich(c, runs, swd_v) }) |> ignore
  })
  |> ignore
}

///|
/// A seal's four characters, two over two.
fn swd_seal_words(c : @ui.Ctx, words : String, style : @ui.TextStyle) -> Unit {
  let chars : Array[String] = []
  for ch in words {
    chars.push(ch.to_string())
  }
  for r in 0..<2 {
    let a = if r * 2 < chars.length() { chars[r * 2] } else { "" }
    let b = if r * 2 + 1 < chars.length() { chars[r * 2 + 1] } else { "" }
    sr_words(c, a + b, style)
  }
}

///|
/// Where along the blade day `i` of `n` is (a share of its length).
fn swd_knot_t(i : Int, n : Int) -> Double {
  swd_yk * (i + 1).to_double() / (n + 1).to_double()
}

///|
fn swd_x(t : Double) -> Double {
  swd_x0 + (swd_x1 - swd_x0) * t
}

///|
/// The blade's middle at `t`: it rises to the tip (its curve, sori).
fn swd_mid(t : Double) -> Double {
  swd_y - 17.0 * @dmath.pow(t, 1.7)
}

///|
fn swd_wid(t : Double) -> Double {
  28.0 - 9.0 * t
}

///|
fn swd_back(t : Double) -> Double {
  swd_mid(t) - swd_wid(t) / 2.0
}

///|
fn swd_edge(t : Double) -> Double {
  swd_mid(t) + swd_wid(t) / 2.0
}

///|
fn swd_shin(t : Double) -> Double {
  swd_back(t) + swd_wid(t) * 0.24
}

///|
/// The temper line's height at `t` (a share of the blade's width over its edge), through the days' shares: a smooth
/// curve (Catmull-Rom) through `knots`.
fn swd_frac(knots : Array[Double], t : Double) -> Double {
  let n = knots.length()
  let s0 = t / swd_yk * (n - 1).to_double()
  let s = if s0 > (n - 1).to_double() - 0.0001 { (n - 1).to_double() - 0.0001 } else { s0 }
  let i = s.floor().to_int()
  let u = s - i.to_double()
  let p = fn(j : Int) { knots[if j < 0 { 0 } else if j > n - 1 { n - 1 } else { j }] }
  let a = p(i - 1)
  let b = p(i)
  let c2 = p(i + 1)
  let d = p(i + 2)
  0.5 *
  (
    2.0 * b +
    (-a + c2) * u +
    (2.0 * a - 5.0 * b + 4.0 * c2 - d) * u * u +
    (-a + 3.0 * b - 3.0 * c2 + d) * u * u * u
  )
}

///|
/// Points along the blade from `a` to `b` (shares of it) of the line `f` says the height of.
fn swd_line(f : (Double) -> Double, a : Double, b : Double) -> Array[(Double, Double)] {
  let out = []
  for i in 0..=swd_steps {
    let t = a + (b - a) * i.to_double() / swd_steps.to_double()
    out.push((swd_x(t), f(t)))
  }
  out
}

///|
/// The oshigata of 丛雨丸 (the mockup's svg): tang on the left, tip on the right, edge down; its hamon through the week's
/// days, a red dot on it at each, a dashed line down to its count.
fn swd_blade(days : Array[(String, String, String, Double, Bool)]) -> Array[@ui.Shape] {
  let knots = [0.24]
  for d in days {
    knots.push(0.12 + 0.56 * d.3)
  }
  knots.push(0.34)
  let ham = fn(t : Double) { swd_edge(t) - swd_frac(knots, t) * swd_wid(t) }
  let yk = swd_x(swd_yk)
  let tip = (swd_x1, swd_back(1.0) + 1.5)
  let bosh = (swd_x1 - 9.0, swd_back(1.0) + 3.6)
  let turn = (swd_x1 - 12.0, ham(swd_yk) + 0.5)
  // the outline: back to the tip, the edge's curve into it, the edge back
  let outline = swd_line(swd_back, 0.0, 1.0)
  outline.push(tip)
  gc_quad(outline, tip, (swd_x1 - 3.0, swd_edge(swd_yk) - 0.5), (yk, swd_edge(swd_yk)), 8)
  for p in swd_line(swd_edge, swd_yk, 0.0) {
    outline.push(p)
  }
  // the body over the temper line (ji), its grey
  let ji = swd_line(swd_back, 0.0, 1.0)
  ji.push(tip)
  ji.push(bosh)
  gc_quad(ji, bosh, turn, (yk, ham(swd_yk)), 8)
  for p in swd_line(ham, swd_yk, 0.0) {
    ji.push(p)
  }
  let hamon = swd_line(ham, 0.0, swd_yk)
  gc_quad(hamon, (yk, ham(swd_yk)), turn, bosh, 8)
  let shinogi = swd_line(swd_shin, 0.0, swd_yk)
  shinogi.push((swd_x1 - 1.0, swd_back(1.0) + 1.6))
  // the tang: rounded at its end, a peg hole, file marks
  let tt = swd_back(0.0) + 1.8
  let tb = swd_edge(0.0) - 4.5
  let tang : Array[(Double, Double)] = [(swd_x0, tt), (12.0, tt + 1.6)]
  gc_quad(tang, (12.0, tt + 1.6), (4.0, (tt + tb) / 2.0 - 1.0), (13.0, tb - 4.5), 10)
  tang.push((swd_x0, tb))
  let out = [
    @ui.shape_of([(gc_flat(outline), true)], fill=swd_paper),
    @ui.shape_of([(gc_flat(ji), true)], fill=swd_rub),
    @ui.shape_of([(gc_flat(hamon), false)], stroke=swd_hamon_glow, width=3.2),
    @ui.shape_of([(gc_flat(hamon), false)], stroke=swd_hamon_ink, width=1.1),
    @ui.shape_of([(gc_flat(shinogi), false)], stroke=swd_line_ink, width=0.6),
    @ui.shape_of([(gc_flat([(yk, swd_shin(swd_yk)), (yk + 0.6, swd_edge(swd_yk))]), false)], stroke=swd_line_ink, width=0.6),
    @ui.shape_of([(gc_flat(outline), true)], stroke=swd_ink, width=1.1),
    @ui.shape_of([(gc_flat(tang), true)], fill=swd_tang_ink),
  ]
  for i in 0..<3 {
    let x = i.to_double() * 4.2
    out.push(@ui.shape_of([(gc_flat([(15.0 + x, tt + 1.0), (10.0 + x, tb - 1.0)]), false)], stroke=swd_file_ink, width=1.1))
  }
  out.push(@ui.shape_of([(gc_flat(tang), true)], stroke=swd_ink, width=1.0))
  out.push(@ui.shape_of([(gc_flat(gc_ellipse(29.0, (tt + tb) / 2.0, 2.6, 2.6)), true)], fill=swd_ground, stroke=swd_ink, width=0.7))
  for i, d in days {
    let t = swd_knot_t(i, days.length())
    let x = swd_x(t)
    for dash in gc_dashes([(x, swd_edge(t) + 3.0), (x, swd_n_top - 1.0)], 1.5, 1.5) {
      out.push(@ui.shape_of([(gc_flat(dash), false)], stroke=swd_lead_ink, width=0.6))
    }
    let r = if d.4 { 2.2 } else { 1.6 }
    out.push(@ui.shape_of([(gc_flat(gc_ellipse(x, ham(t), r, r)), true)], fill=swd_seal_ink))
  }
  out
}

///|
/// The bubble's tail: a point down out of its foot, edged on its two sides.
fn swd_tail() -> Array[@ui.Shape] {
  [
    @ui.shape_of([([0.0, 0.0, swd_tail_w, 0.0, swd_tail_w * 0.4, swd_tail_h], true)], fill=gc_white),
    @ui.shape_of([([0.0, swd_tail_over, swd_tail_w * 0.4, swd_tail_h, swd_tail_w, swd_tail_over], false)], stroke=swd_ink, width=1.5),
  ]
}

///|
let swd_ground : Int64 = 0xF4ECD9FFL

///|
let swd_red : Int64 = 0xB3222CFFL

///|
let swd_seal_ink : Int64 = 0xC0262FFFL

///|
let swd_ink : Int64 = 0x231A15FFL

///|
let swd_note : Int64 = 0x7A6656FFL

///|
let swd_say : Int64 = 0xA3121FFFL

///|
let swd_paper : Int64 = 0xFBF7EEFFL

///|
let swd_rub : Int64 = 0xBDB5A7E6L

///|
let swd_hamon_glow : Int64 = 0xFFFDF6D9L

///|
let swd_hamon_ink : Int64 = 0x3E342CFFL

///|
let swd_line_ink : Int64 = 0x5A4E44CCL

///|
let swd_tang_ink : Int64 = 0x4A423BFFL

///|
let swd_file_ink : Int64 = 0x2A241FFFL

///|
let swd_lead_ink : Int64 = 0xC0262F66L

///|
let swd_x0 : Double = 66.0

///|
let swd_x1 : Double = 304.0

///|
let swd_y : Double = 54.0

///|
/// Where the tip begins (a share of the blade's length): the days' dots before it.
let swd_yk : Double = 0.9

///|
let swd_steps : Int = 70

///|
let swd_blade_w : Double = 308.0

///|
let swd_blade_h : Double = 112.0

///|
// kept across runs: a value (no field of it changes)
let swd_pad : @ui.Style = @ui.css("w=Full p=S2_5")

///|
// kept across runs: a value (no field of it changes)
let swd_frame : @ui.Style = @ui.css("w=Full p=S1 border=B2").then(@ui.style(border_color=Data(swd_red)))

///|
// kept across runs: a value (no field of it changes)
let swd_inner : @ui.Style = @ui.css("w=Full pt=S4 px=S2 pb=S3 border=B1").then(@ui.style(border_color=Data(swd_red)))

///|
let swd_corner_in : Double = 5.0

///|
let swd_corner_top : Double = 2.0

///|
// kept across runs: a value (no field of it changes)
let swd_corner : @ui.Style = @ui.css("w=Hug")

///|
// kept across runs: a value (no field of it changes)
let swd_corner_mark : @ui.TextStyle = @ui.text_style(size=Xs3, color=Data(swd_red), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let swd_heads : @ui.Style = @ui.css("w=Full align=ACenter")

///|
let swd_kick_ink : Int64 = 0x6B5444FFL

///|
// kept across runs: a value (no field of it changes)
let swd_kick : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(swd_kick_ink), wrap=false)

///|
let swd_title_scale : Double = 1.12

///|
// kept across runs: a value (no field of it changes)
let swd_title : @ui.TextStyle = @ui.text_style(size=Xl4, weight=Bold, color=Data(swd_ink), wrap=false)

///|
let swd_seal_right : Double = 14.0

///|
let swd_seal_top : Double = 20.0

///|
let swd_seal_big_d : Double = 44.0

///|
let swd_seal_big_edge : Int64 = 0xC0262FDBL

///|
// kept across runs: a value (no field of it changes)
let swd_seal_big : @ui.Style = @ui.css("radius=Base border=B2 align=ACenter justify=JCenter").then(
  @ui.style(w=Fixed(swd_seal_big_d), h=Fixed(swd_seal_big_d), border_color=Data(swd_seal_big_edge)),
)

///|
let swd_seal_big_words_ink : Int64 = 0xC0262FDBL

///|
// kept across runs: a value (no field of it changes)
let swd_seal_big_words : @ui.TextStyle = @ui.text_style(size=Xl, weight=Bold, leading=L4_75, color=Data(swd_seal_big_words_ink), wrap=false)

///|
let swd_seal_small_d : Double = 34.0

///|
let swd_seal_small_edge : Int64 = 0xC0262FDBL

///|
// kept across runs: a value (no field of it changes)
let swd_seal_small : @ui.Style = @ui.css("radius=Base border=B2 align=ACenter justify=JCenter ml=S1").then(
  @ui.style(w=Fixed(swd_seal_small_d), h=Fixed(swd_seal_small_d), border_color=Data(swd_seal_small_edge)),
)

///|
let swd_seal_small_words_ink : Int64 = 0xC0262FDBL

///|
// kept across runs: a value (no field of it changes)
let swd_seal_small_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, leading=L4, color=Data(swd_seal_small_words_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let swd_blade_row : @ui.Style = @ui.css("w=Full align=ACenter pt=S2")

///|
// kept across runs: a value (no field of it changes)
let swd_blade_box : @ui.Style = @ui.style(w=Fixed(swd_blade_w), h=Fixed(swd_blade_h))

///|
let swd_tang_x : Double = 49.0

///|
let swd_tang_w : Double = 40.0

///|
let swd_tang_up : Double = 7.0

///|
let swd_tang_scale : Double = 0.8

///|
// kept across runs: a value (no field of it changes)
let swd_tang_box : @ui.Style = @ui.css("align=ACenter").then(@ui.style(w=Fixed(swd_tang_w)))

///|
let swd_tang_words_ink : Int64 = 0xEFE6D4FFL

///|
// kept across runs: a value (no field of it changes)
let swd_tang_words : @ui.TextStyle = @ui.text_style(size=Xs3, weight=Bold, color=Data(swd_tang_words_ink), wrap=false)

///|
let swd_label_w : Double = 36.0

///|
let swd_n_top : Double = 82.0

///|
let swd_date_top : Double = 97.0

///|
let swd_date_scale : Double = 0.85

///|
// kept across runs: a value (no field of it changes)
let swd_label_box : @ui.Style = @ui.css("align=ACenter").then(@ui.style(w=Fixed(swd_label_w)))

///|
// kept across runs: a value (no field of it changes)
let swd_n : @ui.TextStyle = @ui.text_style(size=Xs2, weight=Bold, color=Data(swd_say), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let swd_date : @ui.TextStyle = @ui.text_style(size=Xs3, color=Data(swd_note), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let swd_date_today : @ui.TextStyle = @ui.text_style(size=Xs3, color=Data(swd_say), wrap=false)

///|
let swd_rule_bg : Int64 = 0xB3222C66L

///|
// kept across runs: a value (no field of it changes)
let swd_rule : @ui.Style = @ui.css("w=Full h=SPx mt=S1").then(@ui.style(bg=Data(swd_rule_bg)))

///|
// kept across runs: a value (no field of it changes)
let swd_fields : @ui.Style = @ui.css("w=Full")

///|
let swd_field_rule_bg : Int64 = 0xB3222C40L

///|
// kept across runs: a value (no field of it changes)
let swd_field_rule : @ui.Style = @ui.css("w=Full h=SPx").then(@ui.style(bg=Data(swd_field_rule_bg)))

///|
// kept across runs: a value (no field of it changes)
let swd_field_row : @ui.Style = @ui.css("row w=Full align=ACenter py=S1_5 px=S0_5")

///|
let swd_k_w : Double = 58.0

///|
// kept across runs: a value (no field of it changes)
let swd_k_box : @ui.Style = @ui.style(w=Fixed(swd_k_w))

///|
// kept across runs: a value (no field of it changes)
let swd_k : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(swd_red), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let swd_v : @ui.TextStyle = @ui.text_style(size=Base, color=Data(swd_ink), w=Full)

///|
let swd_small_scale : Double = 0.84

///|
let swd_big_scale : Double = 1.1

///|
// kept across runs: a value (no field of it changes)
let swd_bottom : @ui.Style = @ui.css("row w=Full align=AEnd pt=S2_5").then(@ui.style(min_h=Fixed(swd_bottom_h)))

///|
let swd_bottom_h : Double = 150.0

///|
// kept across runs: a value (no field of it changes)
let swd_sign : @ui.Style = @ui.css("gap=S2 pb=S0_5").then(@ui.style(w=@sf.grow))

///|
let swd_cert_ink : Int64 = 0x3A2C24FFL

///|
// kept across runs: a value (no field of it changes)
let swd_cert : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Data(swd_cert_ink), w=Full)

///|
let swd_date_line_ink : Int64 = 0x3A2C24FFL

///|
// kept across runs: a value (no field of it changes)
let swd_date_line : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(swd_date_line_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let swd_by : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
let swd_by_words_ink : Int64 = 0x6B5444FFL

///|
// kept across runs: a value (no field of it changes)
let swd_by_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(swd_by_words_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let swd_brand : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, color=Data(swd_ink), wrap=false)

///|
let swd_tag_ink : Int64 = 0x8A7262FFL

///|
// kept across runs: a value (no field of it changes)
let swd_tag : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(swd_tag_ink), wrap=false)

///|
let swd_photo_d : Double = 108.0

///|
let swd_photo_zoom : Double = 1.4

///|
let swd_photo_fy : Double = 0.393

///|
// kept across runs: a value (no field of it changes)
let swd_pout : @ui.Style = @ui.css("mr=S0_5")

///|
// kept across runs: a value (no field of it changes)
let swd_photo : @ui.Style = @ui.css("p=S1 radius=Xl1_5").then(@ui.style(bg=Data(gc_white)))

///|
let swd_photo_cut_bg : Int64 = 0xA9D4F5FFL

///|
// kept across runs: a value (no field of it changes)
let swd_photo_cut : @ui.Style = @ui.css("radius=Xl clip").then(@ui.style(bg=Data(swd_photo_cut_bg)))

///|
let swd_tape_x : Double = 34.0

///|
let swd_tape_y : Double = -8.0

///|
let swd_tape_w : Double = 52.0

///|
let swd_tape_h : Double = 16.0

///|
let swd_tape_bg : Int64 = 0xF2B8C4C4L

///|
// kept across runs: a value (no field of it changes)
let swd_tape : @ui.Style = @ui.style(w=Fixed(swd_tape_w), h=Fixed(swd_tape_h), bg=Data(swd_tape_bg))

///|
let swd_bubble_right : Double = 66.0

///|
let swd_bubble_bottom : Double = 124.0

///|
// kept across runs: a value (no field of it changes)
let swd_bubble : @ui.Style = @ui.css("px=S3 pt=S1 pb=S1_5 radius=Xl2 border=B1_5").then(
  @ui.style(bg=Data(gc_white), border_color=Data(swd_ink)),
)

///|
// kept across runs: a value (no field of it changes)
let swd_bubble_words : @ui.TextStyle = @ui.text_style(size=Lg, weight=Bold, color=Data(swd_seal_ink), wrap=false)

///|
let swd_tail_w : Double = 14.0

///|
let swd_tail_h : Double = 10.0

///|
/// How far up into the bubble its tail starts (over the bubble's edge).
let swd_tail_over : Double = 2.0

///|
let swd_tail_right : Double = 18.0

// ── 春祭 · 奉纳神乐 ────────────────────────────────────────────────────────

///|
/// 春祭 · 奉纳神乐: 芳乃's kagura at the spring festival (d2-yoshino-kagura), a cord of seven lanterns across its top, a
/// lantern a day, each its chats archived, as bright as its share of the most (today's pink). Under her: 七夜点亮 the
/// week's archived 盏灯笼, the tokens offered and what the incense cost, the chats still dancing and on how many devices,
/// and that the shrine princess dances it only at the spring festival.
fn sr_kagura(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = gc_args(fleet)
  let days = sr_days(fleet)
  sr_box(c, id, flat, kg_ground, fn() {
    sr_art(c, "d2-yoshino-kagura", @sf.share_w_most, kg_art_h, at=kg_art_at) |> ignore
    c.box(style=kg_rest, fn() {  }) |> ignore
    c.box(style=kg_top_shade, left=0.0, top=0.0, fn() { gc_grad(c, kg_top_stops, kg_top_bands) }) |> ignore
    c.box(style=kg_shade, left=0.0, top=kg_shade_top, fn() { gc_grad(c, kg_shade_stops, kg_shade_bands) }) |> ignore
    c.box(left=0.0, top=0.0, fn() { c.shapes(kg_cord(), w=Px(@sf.share_w_most), h=Px(kg_cord_h)) |> ignore }) |> ignore
    c.box(style=kg_lanterns, left=kg_lanterns_x, top=kg_lanterns_y, fn() {
      for d in days {
        kg_lantern(c, d)
      }
    })
    |> ignore
    c.box(style=kg_panel, left=kg_side, top=kg_panel_top, fn() {
      sr_words(c, gc_spread_han(@sf.t("web-main.stations.shareSenren.kagura.kick")), kg_kick)
      sr_rich(
        c,
        sr_said("web-main.stations.shareSenren.kagura.title", args, kg_gold_bright, scale=kg_title_n_scale).map(fn(r) {
          @ui.span(r.text, weight=r.weight, scale=r.scale * kg_title_scale, color=r.color)
        }),
        kg_title,
      )
      c.box(style=kg_lines, fn() {
        for line in [
          ("web-main.stations.shareSenren.kagura.l1", sr_arg(args, "model")),
          ("web-main.stations.shareSenren.kagura.l2", sr_arg(args, "devices")),
          ("web-main.stations.shareSenren.kagura.l3", ""),
        ] {
          c.box(style=kg_line, fn() {
            c.box(style=kg_dot, fn() {  }) |> ignore
            sr_rich(c, gc_plain(sr_said(line.0, args, gc_white, scale=kg_line_n_scale), line.1), kg_line_words)
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
    c.box(style=kg_foot, left=kg_side, top=kg_h - kg_foot_up, fn() {
      sr_brand(c, kg_brand)
      c.box(style=gc_grow, fn() {  }) |> ignore
      sr_words(c, sr_arg(args, "at"), kg_at)
    })
    |> ignore
  })
}

///|
/// `runs` with the last run that is just `plain` (a figure sr_said lit) said plain, as the line's other words.
fn gc_plain(runs : Array[@ui.Run], plain : String) -> Array[@ui.Run] {
  let out = runs.copy()
  if plain == "" {
    return out
  }
  for i = out.length() - 1; i >= 0; i = i - 1 {
    if out[i].text == plain {
      out[i] = @ui.span(plain)
      break
    }
  }
  out
}

///|
/// A day's lantern on its string: its cap, its body as bright as the day's share of the most (today's pink), its
/// count on it, its tail; the date under it.
fn kg_lantern(c : @ui.Ctx, d : (String, String, String, Double, Bool)) -> Unit {
  let (label, _, n, share, today) = d
  let lit = gc_clamp(kg_dim_least + (1.0 - kg_dim_least) * share, 0.0, 1.0)
  let o = kg_opacities[(lit * 20.0).round().to_int()]
  let halo_a = kg_halo_most * share
  let halo = gc_alpha(if today { kg_halo_today } else { kg_halo_ink }, halo_a)
  let outer = if today { kg_today_outer } else { kg_outer }
  let mid = if today { kg_today_mid } else { kg_mid }
  let core = if today { kg_today_core } else { kg_core_ink }
  c.box(style=kg_lantern_box, fn() {
    c.box(style=kg_halo.then(@ui.style(bg=Data(halo))), left=kg_halo_x, top=kg_halo_y, fn() {  }) |> ignore
    c.box(style=kg_string, fn() {  }) |> ignore
    c.box(style=kg_cap, fn() {  }) |> ignore
    c.box(style=kg_body.then(@ui.style(opacity=o, bg=Data(outer))), fn() {
      c.box(style=kg_glow.then(@ui.style(bg=Data(mid))), fn() {
        c.box(style=kg_core.then(@ui.style(bg=Data(core))), fn() {  }) |> ignore
      })
      |> ignore
      c.layer(fn() {
        c.box(style=kg_ribs, fn() {
          c.box(style=kg_rib, fn() {  }) |> ignore
          c.box(style=gc_grow, fn() {  }) |> ignore
          c.box(style=kg_rib, fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
      c.layer(fn() { c.box(style=kg_n_box, fn() { sr_words(c, n, kg_n) }) |> ignore }) |> ignore
    })
    |> ignore
    c.box(style=kg_tail, fn() {  }) |> ignore
    sr_words(c, if today { @sf.t("web-main.stations.shareSenren.kagura.today") } else { label }, if today { kg_date_today } else { kg_date })
  })
  |> ignore
}

///|
/// The lanterns' cord: a curve sagging across the card's top.
fn kg_cord() -> Array[@ui.Shape] {
  let pts = []
  for i in 0..=gc_round_points {
    let a = 3.141592653589793 * i.to_double() / gc_round_points.to_double()
    pts.push((@sf.share_w_most / 2.0 - kg_cord_rx * gc_cos(a), kg_cord_y + kg_cord_sag * gc_sin(a)))
  }
  [@ui.shape_of([(gc_flat(pts), false)], stroke=kg_string_ink, width=1.5)]
}

///|
/// The opacities a lantern may be drawn at, by twentieths.
// kept across runs: a table, never written
let kg_opacities : Array[@ui.Opacity] = [
  O0, O5, O10, O15, O20, O25, O30, O35, O40, O45, O50, O55, O60, O65, O70, O75, O80, O85, O90, O95, O100,
]

///|
let kg_h : Double = 660.0

///|
let kg_art_h : Double = 540.0

///|
let kg_art_at : Double = 0.2

///|
let kg_ground : Int64 = 0x140D22FFL

///|
let kg_rest_h : Double = kg_h - kg_art_h

///|
// kept across runs: a value (no field of it changes)
let kg_rest : @ui.Style = @ui.style(w=Full, h=Fixed(kg_rest_h))

///|
// kept across runs: a value (no field of it changes)
let kg_top_shade : @ui.Style = @ui.style(w=Fixed(@sf.share_w_most), h=Fixed(kg_top_shade_h))

///|
let kg_top_shade_h : Double = 150.0

///|
let kg_top_bands : Int = 15

///|
// kept across runs: a table, never written
let kg_top_stops : Array[(Double, Int64)] = [(0.0, 0x0C0718CCL), (1.0, 0x0C071800L)]

///|
let kg_shade_top : Double = 380.0

///|
let kg_shade_h : Double = kg_h - kg_shade_top

///|
// kept across runs: a value (no field of it changes)
let kg_shade : @ui.Style = @ui.style(w=Fixed(@sf.share_w_most), h=Fixed(kg_shade_h))

///|
let kg_shade_bands : Int = 28

///|
// kept across runs: a table, never written
let kg_shade_stops : Array[(Double, Int64)] = [(0.0, 0x140D2200L), (0.3, 0x140D22E6L), (0.52, 0x140D22FFL), (1.0, 0x140D22FFL)]

///|
let kg_cord_h : Double = 60.0

///|
let kg_cord_rx : Double = 190.0

///|
let kg_cord_y : Double = 6.0

///|
let kg_cord_sag : Double = 40.0

///|
let kg_string_ink : Int64 = 0xE9D9B8AAL

///|
let kg_lanterns_x : Double = 10.0

///|
let kg_lanterns_y : Double = 18.0

///|
let kg_lanterns_w : Double = @sf.share_w_most - 2.0 * kg_lanterns_x

///|
// kept across runs: a value (no field of it changes)
let kg_lanterns : @ui.Style = @ui.css("row justify=JBetween").then(@ui.style(w=Fixed(kg_lanterns_w)))

///|
let kg_lantern_w : Double = 40.0

///|
// kept across runs: a value (no field of it changes)
let kg_lantern_box : @ui.Style = @ui.css("align=ACenter").then(@ui.style(w=Fixed(kg_lantern_w)))

///|
let kg_halo_x : Double = -3.0

///|
let kg_halo_y : Double = 8.0

///|
let kg_halo_w : Double = 46.0

///|
let kg_halo_h : Double = 54.0

///|
let kg_halo_most : Double = 0.24

///|
let kg_halo_ink : Int64 = 0xFFB24AFFL

///|
let kg_halo_today : Int64 = 0xFF7FB4FFL

///|
// kept across runs: a value (no field of it changes)
let kg_halo : @ui.Style = @ui.css("radius=Full").then(@ui.style(w=Fixed(kg_halo_w), h=Fixed(kg_halo_h)))

///|
let kg_string_w : Double = 1.5

///|
let kg_string_h : Double = 10.0

///|
// kept across runs: a value (no field of it changes)
let kg_string : @ui.Style = @ui.style(w=Fixed(kg_string_w), h=Fixed(kg_string_h), bg=Data(kg_string_ink))

///|
let kg_wood : Int64 = 0x2A1A12FFL

///|
// kept across runs: a value (no field of it changes)
let kg_cap : @ui.Style = @ui.css("w=S4 h=S1 radius=Sm").then(@ui.style(bg=Data(kg_wood)))

///|
let kg_body_w : Double = 32.0

///|
let kg_body_h : Double = 40.0

///|
/// The least a lantern is lit (a day with none archived), its brightness growing from it with the day's share.
let kg_dim_least : Double = 0.45

///|
// kept across runs: a value (no field of it changes)
let kg_body : @ui.Style = @ui.css("radius=Xl2 align=ACenter justify=JCenter clip").then(
  @ui.style(w=Fixed(kg_body_w), h=Fixed(kg_body_h)),
)

///|
let kg_outer : Int64 = 0xE0542AFFL

///|
let kg_mid : Int64 = 0xFFB24AFFL

///|
let kg_core_ink : Int64 = 0xFFF3C4FFL

///|
let kg_today_outer : Int64 = 0xF0508AFFL

///|
let kg_today_mid : Int64 = 0xFFD2E6FFL

///|
let kg_today_core : Int64 = 0xFFFFFFFFL

///|
let kg_glow_w : Double = 27.0

///|
let kg_glow_h : Double = 33.0

///|
// kept across runs: a value (no field of it changes)
let kg_glow : @ui.Style = @ui.css("radius=Xl align=ACenter justify=JCenter").then(@ui.style(w=Fixed(kg_glow_w), h=Fixed(kg_glow_h)))

///|
let kg_core_w : Double = 16.0

///|
let kg_core_h : Double = 20.0

///|
// kept across runs: a value (no field of it changes)
let kg_core : @ui.Style = @ui.css("radius=Lg").then(@ui.style(w=Fixed(kg_core_w), h=Fixed(kg_core_h)))

///|
// kept across runs: a value (no field of it changes)
let kg_ribs : @ui.Style = @ui.css("w=Full h=Full py=S1")

///|
let kg_rib_bg : Int64 = 0xA8401C55L

///|
// kept across runs: a value (no field of it changes)
let kg_rib : @ui.Style = @ui.css("w=Full h=SPx").then(@ui.style(bg=Data(kg_rib_bg)))

///|
// kept across runs: a value (no field of it changes)
let kg_n_box : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
let kg_n_ink : Int64 = 0x5A1A08FFL

///|
// kept across runs: a value (no field of it changes)
let kg_n : @ui.TextStyle = @ui.text_style(size=Base, weight=Bold, color=Data(kg_n_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let kg_tail : @ui.Style = @ui.css("w=S2_5 h=S1_5 radius=Sm").then(@ui.style(bg=Data(kg_wood)))

///|
let kg_date_ink : Int64 = 0xF6EAD0FFL

///|
// kept across runs: a value (no field of it changes)
let kg_date : @ui.TextStyle = @ui.text_style(size=Xs3, color=Data(kg_date_ink), wrap=false)

///|
let kg_date_today_ink : Int64 = 0xFFC2DCFFL

///|
// kept across runs: a value (no field of it changes)
let kg_date_today : @ui.TextStyle = @ui.text_style(size=Xs3, weight=Bold, color=Data(kg_date_today_ink), wrap=false)

///|
let kg_side : Double = 20.0

///|
let kg_panel_top : Double = 466.0

///|
let kg_panel_w : Double = @sf.share_w_most - 2.0 * kg_side

///|
// kept across runs: a value (no field of it changes)
let kg_panel : @ui.Style = @ui.css("gap=S0_5").then(@ui.style(w=Fixed(kg_panel_w)))

///|
let kg_kick_ink : Int64 = 0xF2CF7AFFL

///|
// kept across runs: a value (no field of it changes)
let kg_kick : @ui.TextStyle = @ui.text_style(size=Sm, tracking=Widest, color=Data(kg_kick_ink), wrap=false)

///|
let kg_gold_bright : Int64 = 0xFFD36BFFL

///|
let kg_title_scale : Double = 1.14

///|
let kg_title_n_scale : Double = 1.2

///|
// kept across runs: a value (no field of it changes)
let kg_title : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Bold, tracking=@sf.share_letters_apart, color=Data(gc_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let kg_lines : @ui.Style = @ui.css("w=Full gap=S1_5 pt=S2")

///|
// kept across runs: a value (no field of it changes)
let kg_line : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
let kg_dot_bg : Int64 = 0xF2CF7AFFL

///|
// kept across runs: a value (no field of it changes)
let kg_dot : @ui.Style = @ui.css("w=S1_5 h=S1_5 radius=Full").then(@ui.style(bg=Data(kg_dot_bg)))

///|
let kg_line_n_scale : Double = 1.1

///|
let kg_line_words_ink : Int64 = 0xE9DEF8FFL

///|
// kept across runs: a value (no field of it changes)
let kg_line_words : @ui.TextStyle = @ui.text_style(size=Base, color=Data(kg_line_words_ink), w=Full)

///|
let kg_foot_up : Double = 34.0

///|
let kg_foot_w : Double = @sf.share_w_most - 2.0 * kg_side

///|
// kept across runs: a value (no field of it changes)
let kg_foot : @ui.Style = @ui.css("row align=AEnd").then(@ui.style(w=Fixed(kg_foot_w)))

///|
// kept across runs: a value (no field of it changes)
let kg_brand : @ui.TextStyle = @ui.text_style(size=Base, weight=Bold, color=Data(gc_white), wrap=false)

///|
let kg_at_ink : Int64 = 0xA898C8FFL

///|
// kept across runs: a value (no field of it changes)
let kg_at : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(kg_at_ink), wrap=false)
