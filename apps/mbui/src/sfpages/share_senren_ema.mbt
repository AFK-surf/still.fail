// 千恋＊万花's looks (share_senren.mbt): 建实神社's votive plaques, the ema look (the senren card ema.html). Under the
// shrine's sacred rope and its zigzag paper streamers, a red rack of two posts and two beams holds four plaques, each a
// heroine's wish written on it: 丛雨's crossed out halfway, 芳乃's, 茉子's and 小春's. The plaques are pictures made
// for this look (senren/tools/ema_plaques.py: d4-ema cut to its pentagon, its white ground gone, its shadow under it,
// turned as the mockup turns each); the words on them stay upright (the app turns nothing), each set where its turned
// plaque carries it. The rope's twist and the card's warm gradient are drawn in bands.

///|
/// 建实神社's ema rack: the week's offerings, the top model, four heroines' wishes on four plaques, the chats at work.
fn sr_ema(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = sr_args(fleet)
  args.push(("n", sr_num(sr_arg(args, "archived"))))
  sr_box(c, id, flat, ema_ground, fn() {
    ema_wall(c)
    ema_petals(c)
    ema_streamers(c)
    ema_rope(c)
    c.box(style=ema_head, fn() {
      sr_words(c, ema_t("shrine"), ema_kick)
      c.box(style=ema_title_box, fn() { sr_words(c, ema_t("title"), ema_title) }) |> ignore
      c.box(style=ema_koh_under, fn() {
        c.box(style=ema_koh, fn() {
          sr_words(c, ema_t("offerings"), ema_koh_words)
          sr_words(c, sr_arg(args, "weekCost"), ema_koh_cost)
        })
        |> ignore
      })
      |> ignore
      c.box(style=ema_top_box, fn() {
        sr_rich(c, ema_runs(ema_t("top"), args, ema_title_ink, 1.0, plain=["model"]), ema_top)
      })
      |> ignore
    })
    |> ignore
    ema_rack(c, args)
    c.box(style=ema_end, fn() {
      c.box(style=ema_now_box, fn() {
        sr_rich(c, ema_runs(ema_t("now"), args, ema_red, ema_now_hi), ema_now)
      })
      |> ignore
      c.box(style=ema_foot, fn() {
        sr_brand(c, ema_brand)
        c.spacer()
        sr_words(c, @sf.t("web-main.stations.shareTagline"), ema_foot_words)
        c.box(style=ema_foot_gap, fn() {  }) |> ignore
        sr_words(c, sr_arg(args, "at"), ema_foot_words)
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// The words of the look's `key` (under web-main.stations.shareSenren.ema.).
fn ema_t(key : String) -> String {
  @sf.t("web-main.stations.shareSenren.ema." + key)
}

///|
/// `words` as runs: each `{name}` its figure from `args` in `hi`, bold, `scale` the words' size (a name in `plain` as
/// the words are), what is between `[` and `]` crossed out (丛雨's first wish).
fn ema_runs(
  words : String,
  args : Array[(String, String)],
  hi : Int64,
  scale : Double,
  plain? : Array[String] = [],
) -> Array[@ui.Run] {
  let runs : Array[@ui.Run] = []
  let mut said = ""
  let mut name = ""
  let mut naming = false
  let mut struck = false
  for ch in words {
    if naming {
      if ch == '}' {
        naming = false
        let v = sr_arg(args, name)
        if plain.contains(name) {
          runs.push(@ui.span(v, strike=struck))
        } else {
          runs.push(@ui.span(v, color=hi, weight=700, scale~, strike=struck))
        }
        name = ""
      } else {
        name = name + ch.to_string()
      }
    } else if ch == '{' || ch == '[' || ch == ']' {
      if said != "" {
        runs.push(@ui.span(said, strike=struck))
        said = ""
      }
      if ch == '{' {
        naming = true
      } else {
        struck = ch == '['
      }
    } else {
      said = said + ch.to_string()
    }
  }
  if said != "" {
    runs.push(@ui.span(said, strike=struck))
  }
  runs
}

///|
/// `a` to `b` by `t` (0 to 1), each of red, green, blue and alpha.
fn ema_mix(a : Int64, b : Int64, t : Double) -> Int64 {
  let mut out = 0L
  for shift in [24, 16, 8, 0] {
    let x = ((a >> shift) & 0xFFL).to_double()
    let y = ((b >> shift) & 0xFFL).to_double()
    out = out | ((x + (y - x) * t + 0.5).to_int64() << shift)
  }
  out
}

///|
/// The warm wall: from its top colour into the card's ground at ema_wall_mid of the way down, and into its foot's
/// colour at the bottom (the mockup's gradient, in bands).
fn ema_wall(c : @ui.Ctx) -> Unit {
  let top_h = ema_card_h * ema_wall_mid
  let foot_h = ema_card_h - top_h
  c.box(left=ema_zero, right=ema_zero, top=ema_zero, fn() { ema_bands(c, ema_wall_top, ema_ground, top_h) }) |> ignore
  c.box(left=ema_zero, right=ema_zero, bottom=ema_zero, fn() { ema_bands(c, ema_ground, ema_wall_foot, foot_h) })
  |> ignore
}

///|
/// From `a` down into `b` over `h`, in bands about ema_band tall.
fn ema_bands(c : @ui.Ctx, a : Int64, b : Int64, h : Double) -> Unit {
  let n = (h / ema_band).to_int()
  let bh = h / n.to_double()
  for i in 0..<n {
    let ink = ema_mix(a, b, (i.to_double() + 0.5) / n.to_double())
    c.box(style=@ui.style(w=Full, h=Fixed(bh), bg=Data(ink)), fn() {  }) |> ignore
  }
}

///|
/// The cherry petals fallen on the wall, behind everything else.
fn ema_petals(c : @ui.Ctx) -> Unit {
  for p in ema_petal_spots {
    let (x, y, rx, ry, ink) = p
    let w = rx * ema_petal_solid * 2.0
    let h = ry * ema_petal_solid * 2.0
    let left = x * @sf.share_w_most - w / 2.0
    let top = y * ema_card_h - h / 2.0
    c.box(style=ema_petal.then(@ui.style(w=Fixed(w), h=Fixed(h), bg=Data(ink))), left~, top~, fn() {  }) |> ignore
  }
}

///|
/// How far down the sacred rope's middle is at `x` across the card (it sags in the middle).
fn ema_rope_y(x : Double) -> Double {
  let t = (x + ema_rope_reach) / (@sf.share_w_most + ema_rope_reach * 2.0)
  ema_rope_end + ema_rope_sag * t * (1.0 - t)
}

///|
/// The zigzag paper streamers (shide) hanging from the rope, drawn before it (it covers their tops): each its pieces
/// in their outline's colour a little larger, then in white over them.
fn ema_streamers(c : @ui.Ctx) -> Unit {
  for s in ema_shide_spots {
    let (x, k) = s
    let left = x - ema_shide_half
    let top = ema_rope_y(x) + ema_shide_drop
    for pass in 0..<2 {
      let grow = if pass == 0 { ema_shide_line } else { 0.0 }
      let ink = if pass == 0 { ema_shide_edge } else { ema_white }
      for r in ema_shide_pieces {
        let (x0, y0, x1, y1) = r
        let (across, high) = ((x1 - x0) * k + grow * 2.0, (y1 - y0) * k + grow * 2.0)
        let st = @ui.style(w=Fixed(across), h=Fixed(high), bg=Data(ink))
        c.box(style=st, left=left + x0 * k - grow, top=top + y0 * k - grow, fn() {  }) |> ignore
      }
    }
  }
}

///|
/// The sacred rope across the top, sagging: its straw in slabs along it with its shadow under it, its twist's dark and
/// light bands leaning down to the right (the mockup's pattern turned -38°) laid row by row across it, its light line
/// along its top.
fn ema_rope(c : @ui.Ctx) -> Unit {
  let mut x = 0.0
  while x < @sf.share_w_most {
    let mid = ema_rope_y(x + ema_rope_step / 2.0)
    c.box(left=x, top=mid - ema_rope_thick / 2.0, fn() {
      c.box(style=ema_rope_straw, fn() {  }) |> ignore
      c.box(style=ema_rope_shade, fn() {  }) |> ignore
    })
    |> ignore
    x = x + ema_rope_step
  }
  let row_h = ema_rope_thick / ema_rope_rows.to_double()
  let mut at = -ema_twist_period * 2.0
  while at < @sf.share_w_most {
    for r in 0..<ema_rope_rows {
      let left = at + (r.to_double() + 0.5) * row_h * ema_twist_lean
      let top = ema_rope_y(left + ema_twist_dark_w / 2.0) - ema_rope_thick / 2.0 + r.to_double() * row_h
      let dark = @ui.style(w=Fixed(ema_twist_dark_w), h=Fixed(row_h), bg=Data(ema_twist_dark))
      let light = @ui.style(w=Fixed(ema_twist_light_w), h=Fixed(row_h), bg=Data(ema_twist_light))
      c.box(style=dark, left~, top~, fn() {  }) |> ignore
      c.box(style=light, left=left + ema_twist_dark_w, top~, fn() {  }) |> ignore
    }
    at = at + ema_twist_period
  }
  x = 0.0
  while x < @sf.share_w_most {
    let mid = ema_rope_y(x + ema_rope_step / 2.0)
    c.box(style=ema_rope_shine, left=x, top=mid - ema_rope_shine_up, fn() {  }) |> ignore
    x = x + ema_rope_step
  }
}

///|
/// The rack: two red posts, two beams with their black caps, and on each beam two plaques hung on red-and-white cords,
/// each with its heroine's wish and her name.
fn ema_rack(c : @ui.Ctx, args : Array[(String, String)]) -> Unit {
  c.box(style=ema_rack_box, fn() {
    c.box(style=ema_post, left=ema_post_at, top=ema_zero, fn() { ema_post_bands(c) }) |> ignore
    c.box(style=ema_post, right=ema_post_at, top=ema_zero, fn() { ema_post_bands(c) }) |> ignore
    for top in ema_beams {
      c.box(style=ema_beam_shade, left=ema_post_at, right=ema_post_at, top=top + ema_beam_h, fn() {  }) |> ignore
      c.box(style=ema_beam, left=ema_post_at, right=ema_post_at, top~, fn() {
        for b in ema_beam_bands {
          c.box(style=@ui.style(w=Full, h=Fixed(ema_beam_band_h), bg=Data(b)), fn() {  }) |> ignore
        }
      })
      |> ignore
      c.box(style=ema_cap, left=ema_cap_at, top=top - ema_cap_up, fn() {  }) |> ignore
      c.box(style=ema_cap, right=ema_cap_at, top=top - ema_cap_up, fn() {  }) |> ignore
    }
    for i, p in ema_plaques {
      ema_plaque(c, args, i, p)
    }
  })
  |> ignore
}

///|
/// A post's red, darker at its sides (the mockup's gradient across it, in bands).
fn ema_post_bands(c : @ui.Ctx) -> Unit {
  for b in ema_post_inks {
    c.box(style=@ui.style(w=Fixed(ema_post_band_w), h=Fixed(ema_rack_h), bg=Data(b)), fn() {  }) |> ignore
  }
}

///|
/// Plaque `i` (of ema_plaques): its cord from the beam, its picture (turned, its shadow in it), its wish's lines in the
/// middle of its wood and its heroine's name at its lower right, both upright where the turn carries them.
fn ema_plaque(
  c : @ui.Ctx,
  args : Array[(String, String)],
  i : Int,
  p : (Double, Double, Double, Double, Double, Double, Double, String, Int, Int64),
) -> Unit {
  let (x, y, beam, wdx, wdy, ndx, ndy, who, lines, ink) = p
  let cord_h = y - beam + ema_pl * ema_pl_pivot - ema_cord_from
  let cord_x = x + ema_pl / 2.0 - ema_cord_w / 2.0
  c.box(style=ema_cord.then(@ui.style(h=Fixed(cord_h))), left=cord_x, top=beam + ema_cord_from, fn() {
    let mut at = 0.0
    while at < cord_h {
      c.box(style=ema_cord_red, fn() {  }) |> ignore
      c.box(style=ema_cord_white, fn() {  }) |> ignore
      at = at + ema_cord_red_h + ema_cord_white_h
    }
  })
  |> ignore
  c.box(left=x - ema_pl_pad, top=y - ema_pl_pad, fn() {
    sr_art(c, "d4-ema-" + (i + 1).to_string(), ema_pl + ema_pl_pad * 2.0, ema_pl + ema_pl_pad * 2.0) |> ignore
  })
  |> ignore
  c.box(style=ema_wish, left=x + ema_wish_left + wdx, top=y + ema_wish_top + wdy, fn() {
    for n in 1..=lines {
      sr_rich(c, ema_runs(ema_t(who + n.to_string()), args, ema_wish_ink, ema_wish_hi), ema_wish_words)
    }
  })
  |> ignore
  c.box(style=ema_pl_box, left=x, top=y, fn() {
    c.box(right=ema_who_right - ndx, bottom=ema_who_bottom - ndy, fn() {
      sr_rich(
        c,
        [@ui.span(ema_dash, color=(ink & ema_rgb) | ema_dash_alpha), @ui.span(ema_t(who), color=ink, weight=600)],
        ema_who_words,
      )
    })
    |> ignore
  })
  |> ignore
}

// ── the look's measures and inks ─────────────────────────────────────────

///|
let ema_zero : Double = 0.0

///|
let ema_ground : Int64 = 0xF3DCC0FFL

///|
let ema_wall_top : Int64 = 0xF7E8CFFFL

///|
let ema_wall_foot : Int64 = 0xEFD2B3FFL

///|
/// Where the wall's gradient is the card's ground (of its height).
let ema_wall_mid : Double = 0.55

///|
/// The card's height as laid out (the wall's gradient and the petals are placed by it).
let ema_card_h : Double = 628.0

///|
let ema_band : Double = 4.0

///|
let ema_white : Int64 = 0xFFFFFFFFL

///|
let ema_rgb : Int64 = 0xFFFFFF00L

///|
let ema_kick_ink : Int64 = 0xA8402EFFL

///|
let ema_title_ink : Int64 = 0x3A1A10FFL

///|
let ema_red : Int64 = 0xB8382AFFL

///|
let ema_red_dark : Int64 = 0x8A2418FFL

///|
let ema_gold : Int64 = 0xFFE7A8FFL

///|
let ema_dim : Int64 = 0x8A5A3AFFL

///|
let ema_now_ink : Int64 = 0x8A4A30FFL

///|
let ema_wish_ink : Int64 = 0x2E1A10FFL

///|
/// The petals: each where it lies (across, down: shares of the card), how wide and tall (radii), its pink.
// kept across runs: a table, never written
let ema_petal_spots : Array[(Double, Double, Double, Double, Int64)] = [
  (0.09, 0.30, 5.0, 3.5, 0xF6B9C8FFL),
  (0.91, 0.24, 4.0, 3.0, 0xF6B9C8FFL),
  (0.06, 0.64, 4.5, 3.0, 0xF4AEC0FFL),
  (0.95, 0.58, 5.0, 3.5, 0xF6B9C8FFL),
  (0.50, 0.97, 4.0, 3.0, 0xF4AEC0FFL),
  (0.72, 0.96, 3.5, 2.5, 0xF6B9C8FFL),
]

///|
/// How much of a petal's radius is solid (the mockup's radial gradient: solid to 60%, gone by 70%).
let ema_petal_solid : Double = 0.65

///|
// kept across runs: a value (no field of it changes)
let ema_petal : @ui.Style = @ui.css("radius=Full")

///|
/// The rope's ends' height, how much it sags, how far past the card's sides it reaches, how thick it is.
let ema_rope_end : Double = 10.0

///|
let ema_rope_sag : Double = 80.0

///|
let ema_rope_reach : Double = 10.0

///|
let ema_rope_thick : Double = 19.0

///|
/// The rope's slabs' width, its twist's rows down it, how far a band leans across for each point down (tan 38°), the
/// bands' period across and their widths (the mockup's 9, 2.6 and 1.4, turned).
let ema_rope_step : Double = 4.0

///|
let ema_rope_rows : Int = 5

///|
let ema_twist_lean : Double = 0.78

///|
let ema_twist_period : Double = 11.42

///|
let ema_twist_dark_w : Double = 3.3

///|
let ema_twist_light_w : Double = 1.78

///|
let ema_twist_dark : Int64 = 0xB08640FFL

///|
let ema_twist_light : Int64 = 0xECD391FFL

///|
let ema_rope_straw_ink : Int64 = 0xDFBF72FFL

///|
// kept across runs: a value (no field of it changes)
let ema_rope_straw : @ui.Style = @ui.style(w=Fixed(ema_rope_step), h=Fixed(ema_rope_thick), bg=Data(ema_rope_straw_ink))

///|
/// The light line: its middle 4 over the rope's, 3 thick.
let ema_rope_shine_up : Double = 5.5

///|
let ema_rope_shine_h : Double = 3.0

///|
let ema_rope_shine_ink : Int64 = 0xF3E0A8CCL

///|
// kept across runs: a value (no field of it changes)
let ema_rope_shine : @ui.Style = @ui.style(
  w=Fixed(ema_rope_step),
  h=Fixed(ema_rope_shine_h),
  bg=Data(ema_rope_shine_ink),
)

///|
let ema_rope_shade_h : Double = 3.0

///|
let ema_rope_shade_ink : Int64 = 0x8A6A3259L

///|
// kept across runs: a value (no field of it changes)
let ema_rope_shade : @ui.Style = @ui.style(
  w=Fixed(ema_rope_step),
  h=Fixed(ema_rope_shade_h),
  bg=Data(ema_rope_shade_ink),
)

///|
/// The streamers: each its middle across the card and its size (of the mockup's 22 by 40).
// kept across runs: a table, never written
let ema_shide_spots : Array[(Double, Double)] = [(30.0, 1.0), (96.0, 0.9), (264.0, 0.9), (330.0, 1.0)]

///|
/// A streamer's pieces (left, top, right, bottom in its 22 by 40): the paper's zigzag down.
// kept across runs: a table, never written
let ema_shide_pieces : Array[(Double, Double, Double, Double)] = [
  (9.0, 0.0, 13.0, 8.0),
  (9.0, 8.0, 20.0, 11.0),
  (14.0, 11.0, 20.0, 18.0),
  (6.0, 18.0, 14.0, 21.0),
  (2.0, 21.0, 6.0, 28.0),
  (2.0, 28.0, 17.0, 31.0),
  (11.0, 31.0, 17.0, 40.0),
]

///|
let ema_shide_half : Double = 11.0

///|
let ema_shide_drop : Double = 6.0

///|
let ema_shide_line : Double = 0.6

///|
let ema_shide_edge : Int64 = 0xC9B9A0FFL

///|
// kept across runs: a value (no field of it changes)
let ema_head : @ui.Style = @ui.css("w=Full align=ACenter pt=S16")

///|
// kept across runs: a value (no field of it changes)
let ema_kick : @ui.TextStyle = @ui.text_style(
  size=Xs,
  leading=L4_75,
  tracking=Widest,
  color=Data(ema_kick_ink),
  wrap=false,
)

///|
// kept across runs: a value (no field of it changes)
let ema_title_box : @ui.Style = @ui.css("mt=S0_5")

///|
// kept across runs: a value (no field of it changes)
let ema_title : @ui.TextStyle = @ui.text_style(
  size=Xl4,
  leading=L8,
  weight=Semibold,
  tracking=Wider,
  color=Data(ema_title_ink),
  wrap=false,
)

///|
/// The offerings' pill's solid shadow: a ground of its darker red under it, a little lower.
// kept across runs: a value (no field of it changes)
let ema_koh_under : @ui.Style = @ui.css("mt=S1_5 pb=S0_5 radius=Full").then(@ui.style(bg=Data(ema_red_dark)))

///|
// kept across runs: a value (no field of it changes)
let ema_koh : @ui.Style = @ui.css("row align=ACenter gap=S2 px=S3_5 pt=S1 pb=S1_25 radius=Full").then(
  @ui.style(bg=Data(ema_red)),
)

///|
// kept across runs: a value (no field of it changes)
let ema_koh_words : @ui.TextStyle = @ui.text_style(
  size=Sm,
  color=Data(ema_white),
  wrap=false,
)

///|
// kept across runs: a value (no field of it changes)
let ema_koh_cost : @ui.TextStyle = @ui.text_style(
  size=Xl2,
  weight=Bold,
  color=Data(ema_gold),
  wrap=false,
)

///|
// kept across runs: a value (no field of it changes)
let ema_top_box : @ui.Style = @ui.css("mt=S2")

///|
// kept across runs: a value (no field of it changes)
let ema_top : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(ema_dim), wrap=false)

///|
/// The rack's height: to under the lower plaques' shadows (the mockup's 366, less the 8 the words under it go down by
/// to be as far under it as it is under the head).
let ema_rack_h : Double = 358.0

///|
// kept across runs: a value (no field of it changes)
let ema_rack_box : @ui.Style = @ui.css("w=Full mt=S3").then(@ui.style(h=Fixed(ema_rack_h)))

///|
let ema_post_at : Double = 4.0

///|
let ema_post_band_w : Double = 2.0

///|
/// A post's red across it (the mockup's gradient: dark, bright at 45%, dark).
// kept across runs: a table, never written
let ema_post_inks : Array[Int64] = [0xA52A1EFFL, 0xBA3A28FFL, 0xCF4A33FFL, 0xB53420FFL, 0x9A2418FFL]

///|
// kept across runs: a value (no field of it changes)
let ema_post : @ui.Style = @ui.css("row").then(@ui.style(h=Fixed(ema_rack_h)))

///|
/// The beams' tops in the rack.
// kept across runs: a table, never written
let ema_beams : Array[Double] = [4.0, 192.0]

///|
let ema_beam_h : Double = 12.0

///|
let ema_beam_band_h : Double = 3.0

///|
/// A beam's red down it (the mockup's gradient, in bands).
// kept across runs: a table, never written
let ema_beam_bands : Array[Int64] = [0xCD4B35FFL, 0xC03C29FFL, 0xB02F1FFFL, 0x962719FFL]

///|
// kept across runs: a value (no field of it changes)
let ema_beam : @ui.Style = @ui.css("radius=Sm clip").then(@ui.style(h=Fixed(ema_beam_h)))

///|
let ema_beam_shade_h : Double = 4.0

///|
let ema_beam_shade_ink : Int64 = 0x5A1A1026L

///|
// kept across runs: a value (no field of it changes)
let ema_beam_shade : @ui.Style = @ui.style(h=Fixed(ema_beam_shade_h), bg=Data(ema_beam_shade_ink))

///|
let ema_cap_at : Double = 6.0

///|
let ema_cap_up : Double = 2.0

///|
let ema_cap_w : Double = 20.0

///|
let ema_cap_h : Double = 16.0

///|
let ema_cap_ink : Int64 = 0x2E1A14FFL

///|
// kept across runs: a value (no field of it changes)
let ema_cap : @ui.Style = @ui.css("radius=Sm").then(
  @ui.style(w=Fixed(ema_cap_w), h=Fixed(ema_cap_h), bg=Data(ema_cap_ink)),
)

///|
/// A plaque's box in the mockup, the room its picture has around it (its turned corners, its shadow), where it turns.
let ema_pl : Double = 164.0

///|
let ema_pl_pad : Double = 14.0

///|
let ema_pl_pivot : Double = 0.12

///|
// kept across runs: a value (no field of it changes)
let ema_pl_box : @ui.Style = @ui.style(w=Fixed(ema_pl), h=Fixed(ema_pl))

///|
/// The plaques: each its box's left and top in the rack, its beam's top, how far its turn carries its wish's middle and
/// its name (across, down), its heroine (her name's key, her wish's lines' keys' stem), how many lines her wish has
/// and her colour.
// kept across runs: a table, never written
let ema_plaques : Array[(Double, Double, Double, Double, Double, Double, Double, String, Int, Int64)] = [
  (14.0, 10.0, 4.0, 5.2, -0.8, 9.0, -5.0, "murasame", 3, 0x3F9A6EFFL),
  (182.0, 14.0, 4.0, -4.0, 0.4, -7.0, 3.3, "yoshino", 2, 0xC0303AFFL),
  (16.0, 198.0, 192.0, -3.3, 0.3, -5.8, 2.8, "mako", 3, 0x27306AFFL),
  (180.0, 196.0, 192.0, 4.6, -0.7, 7.9, -4.3, "koharu", 2, 0xE0558AFFL),
]

///|
let ema_cord_from : Double = 6.0

///|
let ema_cord_w : Double = 2.0

///|
let ema_cord_red_h : Double = 4.0

///|
let ema_cord_white_h : Double = 3.0

///|
let ema_cord_red_ink : Int64 = 0xD0342AFFL

///|
// kept across runs: a value (no field of it changes)
let ema_cord : @ui.Style = @ui.css("clip").then(@ui.style(w=Fixed(ema_cord_w)))

///|
// kept across runs: a value (no field of it changes)
let ema_cord_red : @ui.Style = @ui.style(w=Full, h=Fixed(ema_cord_red_h), bg=Data(ema_cord_red_ink))

///|
// kept across runs: a value (no field of it changes)
let ema_cord_white : @ui.Style = @ui.style(w=Full, h=Fixed(ema_cord_white_h), bg=Data(ema_white))

///|
/// The wish's room on the wood (the mockup's 17% from the left, 6% from the right, 41% down, 34% tall).
let ema_wish_left : Double = 27.88

///|
let ema_wish_top : Double = 66.6

///|
let ema_wish_w : Double = 126.28

///|
let ema_wish_h : Double = 57.0

///|
// kept across runs: a value (no field of it changes)
let ema_wish : @ui.Style = @ui.css("align=ACenter justify=JCenter").then(
  @ui.style(w=Fixed(ema_wish_w), h=Fixed(ema_wish_h)),
)

///|
/// A figure in a wish (as large as its words).
let ema_wish_hi : Double = 1.0

///|
// kept across runs: a value (no field of it changes)
let ema_wish_words : @ui.TextStyle = @ui.text_style(
  size=Base,
  leading=L4_75,
  color=Data(ema_wish_ink),
  wrap=false,
)

///|
/// The name's room from the plaque's box's right and foot (9%, 8%).
let ema_who_right : Double = 14.76

///|
let ema_who_bottom : Double = 13.12

///|
let ema_dash : String = "—— "

///|
let ema_dash_alpha : Int64 = 0x99L

///|
// kept across runs: a value (no field of it changes)
let ema_who_words : @ui.TextStyle = @ui.text_style(size=Xs2, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ema_now_box : @ui.Style = @ui.css("w=Full align=ACenter")

///|
/// The card's foot under the rack, as far under it as the rack is under the head: the chats at work, still.fail's line.
// kept across runs: a value (no field of it changes)
let ema_end : @ui.Style = @ui.css("w=Full mt=S3 gap=S2 pb=S4")

///|
/// The chats' figure (bolder, as large).
let ema_now_hi : Double = 1.0

///|
// kept across runs: a value (no field of it changes)
let ema_now : @ui.TextStyle = @ui.text_style(
  size=Sm,
  leading=L5,
  color=Data(ema_now_ink),
  wrap=false,
)

///|
// kept across runs: a value (no field of it changes)
let ema_foot : @ui.Style = @ui.css("row w=Full align=ACenter px=S5")

///|
// kept across runs: a value (no field of it changes)
let ema_foot_gap : @ui.Style = @ui.css("w=S3")

///|
// kept across runs: a value (no field of it changes)
let ema_brand : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(ema_title_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ema_foot_words : @ui.TextStyle = @ui.text_style(
  size=Xs,
  color=Data(ema_dim),
  wrap=false,
)
