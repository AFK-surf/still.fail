// 千恋＊万花's looks (share_senren.mbt): each heroine's own thing — 丛雨's ADV box, 芳乃's fortune slip, 茉子's mission
// report, 蕾娜's inn bill, 小春's menu, 芦花's ledger, and 芦花's shop at night. Each as its mockup is drawn (the
// senren cards), in what boxes, words and pictures do: a CSS gradient a fall in bands (hero_fade), a solid shadow
// under a box a ground of its colour a little lower, a stamp upright where the mockup turned it.

// ── what these looks share ───────────────────────────────────────────────

///|
/// The words of `key` (under the looks' own: web-main.stations.shareSenren.) with `args` put in.
fn hero_t(key : String, args? : Array[(String, String)] = []) -> String {
  @sf.t("web-main.stations.shareSenren." + key, args~)
}

///|
/// `whole`'s words as runs: each `{name}` of `marks` its own run (a figure in the look's colour, bolder, larger), the
/// rest as written (a name not among them too), `scale` their size.
fn hero_marked(whole : String, marks : Array[(String, @ui.Run)], scale? : Double = 1.0) -> Array[@ui.Run] {
  let runs : Array[@ui.Run] = []
  let mut rest = whole
  while true {
    match rest.find("{") {
      None => break
      Some(i) => {
        let after = rest.exact_view(start=i + 1).to_owned()
        match after.find("}") {
          None => break
          Some(j) => {
            let name = after.exact_view(end=j).to_owned()
            match marks.iter().find_first(fn(m) { m.0 == name }) {
              Some(m) => {
                if i > 0 {
                  runs.push(@ui.span(rest.exact_view(end=i).to_owned(), scale~))
                }
                runs.push(m.1)
              }
              None => runs.push(@ui.span(rest.exact_view(end=i + j + 2).to_owned(), scale~))
            }
            rest = after.exact_view(start=j + 1).to_owned()
          }
        }
      }
    }
  }
  if rest != "" {
    runs.push(@ui.span(rest, scale~))
  }
  runs
}

///|
/// The words of `key` with `plain` put in as they are and `marks`' runs in their places.
fn hero_said(
  key : String,
  plain : Array[(String, String)],
  marks : Array[(String, @ui.Run)],
  scale? : Double = 1.0,
) -> Array[@ui.Run] {
  hero_marked(hero_t(key, args=plain), marks, scale~)
}

///|
/// A figure among words: in `color`, bold, `scale` the words' size.
fn hero_hi(v : String, color : Int64, scale? : Double = 1.0) -> @ui.Run {
  @ui.span(v, color~, bold=true, scale~)
}

///|
/// From clear into `ground`, `h` tall: as solid at each height as `stops` say there ((how far down, how solid), each 0
/// to 1), in bands about `hero_band` tall (a ground is of one colour: a gradient said in steps).
fn hero_fade(c : @ui.Ctx, ground : Int64, h : Double, stops : Array[(Double, Double)]) -> Unit {
  let n = if h > hero_band { (h / hero_band).to_int() } else { 1 }
  let bh = h / n.to_double()
  for i in 0..<n {
    let a = hero_stop(stops, (i.to_double() + 0.5) / n.to_double())
    let ink = (ground & hero_rgb) | (a * hero_solid + 0.5).to_int64()
    c.box(style=@ui.style(w=Full, h=Fixed(bh), bg=Data(ink)), fn() {  }) |> ignore
  }
}

///|
/// How solid `stops` say it is at `x` (straight between two).
fn hero_stop(stops : Array[(Double, Double)], x : Double) -> Double {
  let mut prev = stops[0]
  for s in stops {
    if x <= s.0 {
      if s.0 <= prev.0 {
        return s.1
      }
      return prev.1 + (s.1 - prev.1) * (x - prev.0) / (s.0 - prev.0)
    }
    prev = s
  }
  prev.1
}

///|
let hero_rgb : Int64 = 0xFFFFFF00L

///|
let hero_solid : Double = 255.0

///|
let hero_band : Double = 3.0

///|
/// Clear at its top, solid at its foot, evenly.
// kept across runs: a table, never written
let hero_even : Array[(Double, Double)] = [(0.0, 0.0), (1.0, 1.0)]

///|
/// The look's picture across the card's top, `h` tall (its crop at `at`), its last `fade` falling into `ground`: laid at
/// the card's top out of its flow, under what is laid after it (a look's paper rises over its foot).
fn hero_top(c : @ui.Ctx, art : String, h : Double, at : Double, ground : Int64, fade : Double) -> Unit {
  c.box(left=hero_zero, top=hero_zero, fn() { sr_art(c, art, @sf.share_w_most, h, at~) |> ignore }) |> ignore
  c.box(left=hero_zero, right=hero_zero, top=h - fade, fn() { hero_fade(c, ground, fade, hero_even) }) |> ignore
}

///|
/// Room down the card, `h` tall (what the picture over it shows through).
fn hero_gap(c : @ui.Ctx, h : Double) -> Unit {
  c.box(style=@ui.style(w=Full, h=Fixed(h)), fn() {  }) |> ignore
}

///|
/// A line of dashes across what holds it, in `ink`.
fn hero_dashes(c : @ui.Ctx, ink : Int64) -> Unit {
  c.box(style=hero_dash_row, fn() {
    for _ in 0..<hero_dash_count {
      c.box(style=hero_dash.then(@ui.style(bg=Data(ink))), fn() {  }) |> ignore
    }
  })
  |> ignore
}

///|
/// A rule across what holds it, `h` thick, in `ink`.
fn hero_rule(c : @ui.Ctx, ink : Int64, h : Double) -> Unit {
  c.box(style=@ui.style(w=Full, h=Fixed(h), bg=Data(ink)), fn() {  }) |> ignore
}

///|
/// `words`' characters one by one (a seal's, a noren's: one in each place).
fn hero_chars(words : String) -> Array[String] {
  let out = []
  for ch in words {
    out.push(ch.to_string())
  }
  out
}

///|
/// still.fail's line and when, at either end of a line.
fn hero_foot(c : @ui.Ctx, fleet : Json?, style : @ui.Style, words : @ui.TextStyle) -> Unit {
  c.box(style~, fn() {
    c.box(style=hero_grow, fn() { sr_words(c, @sf.t("web-main.stations.shareTagline"), words) }) |> ignore
    sr_words(c, text(fleet, "at"), words)
  })
  |> ignore
}

///|
/// `words` but the last, a space between (a model kind's name without 订阅: Claude 订阅's Claude; when without its clock).
fn hero_but_last(words : Array[String]) -> String {
  let buf = StringBuilder()
  for i in 0..<(words.length() - 1) {
    if i > 0 {
      buf.write_string(" ")
    }
    buf.write_string(words[i])
  }
  buf.to_string()
}

///|
let hero_zero : Double = 0.0

///|
/// A line of dashes: as many as fit, 3 apart, a hairline thick.
// kept across runs: a value (no field of it changes)
let hero_dash_row : @ui.Style = @ui.css("row w=Full gap=S1 h=SPx clip")

///|
let hero_dash_count : Int = 48

///|
// kept across runs: a value (no field of it changes)
let hero_dash : @ui.Style = @ui.style(w=@sf.grow, h=Full)

///|
// kept across runs: a value (no field of it changes)
let hero_grow : @ui.Style = @ui.style(w=@sf.grow)

// ── 丛雨 · ADV ──────────────────────────────────────────────────────────────

///|
/// 丛雨's: the game's own screen as she talks. Her picture (night sakura, pointing at you), falling into the night at its
/// foot; the seventh day, when and where in a chip, still.fail across from it; two choices, the chats at work the one
/// chosen; her name on its tab over the box she says the week in (the top model's tokens and cost, that no one calls
/// her a blunt blade now); the game's menu, still.fail's line.
fn sr_adv(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = sr_args(fleet)
  let hi = fn(name : String) -> (String, @ui.Run) { (name, hero_hi(sr_arg(args, name), adv_gold, scale=adv_hi_scale)) }
  sr_box(c, id, flat, adv_ground, fn() {
    sr_art(c, "a1-murasame-adv", @sf.share_w_most, adv_art_h, at=0.0) |> ignore
    hero_gap(c, adv_rest_h)
    c.box(left=hero_zero, right=hero_zero, top=adv_shade_top, fn() { hero_fade(c, adv_ground, adv_shade_h, adv_shade) })
    |> ignore
    c.box(style=adv_chip, left=adv_edge, top=adv_edge, fn() {
      sr_words(c, hero_t("adv.day"), adv_chip_day)
      sr_words(c, sr_arg(args, "at"), adv_chip_words)
      sr_words(c, hero_t("adv.place"), adv_chip_words)
    })
    |> ignore
    c.box(right=adv_brand_r, top=adv_brand_t, fn() { sr_brand(c, adv_brand) }) |> ignore
    c.box(style=adv_choices, left=adv_choices_x, right=adv_choices_x, top=adv_choices_t, fn() {
      adv_choice(c, hero_t("adv.pat"), false)
      adv_choice(c, hero_t("adv.go", args=[("chats", sr_arg(args, "chats"))]), true)
    })
    |> ignore
    c.box(style=adv_box, left=adv_box_x, right=adv_box_x, top=adv_box_t, fn() {
      c.box(style=adv_hair, left=adv_hair_x, right=adv_hair_x, top=adv_hair_t, fn() {  }) |> ignore
      let plain = [("accounts", sr_arg(args, "accounts")), ("kind", sr_arg(args, "kind")), ("model", sr_arg(args, "model"))]
      sr_rich(c, hero_said("adv.line", plain, [hi("tokens"), hi("cost")]), adv_line)
      sr_rich(c, hero_said("adv.line2", [], [("blunt", @ui.span(hero_t("adv.blunt"), color=adv_pink))]), adv_line)
      c.box(right=adv_next_r, bottom=adv_next_b, fn() { sr_words(c, "▼", adv_next) }) |> ignore
    })
    |> ignore
    c.box(style=adv_name, left=adv_name_x, top=adv_name_t, fn() { sr_words(c, hero_t("adv.name"), adv_name_words) })
    |> ignore
    c.box(style=adv_menu, left=hero_zero, right=hero_zero, top=adv_menu_t, fn() {
      for k, w in hero_t("adv.menu").split(" ").to_array() {
        sr_words(c, w.to_owned(), if k == adv_menu_on_at { adv_menu_on } else { adv_menu_words })
      }
    })
    |> ignore
    c.box(style=adv_foot_row, left=hero_zero, right=hero_zero, top=adv_foot_t, fn() {
      sr_words(c, @sf.t("web-main.stations.shareTagline"), adv_foot)
    })
    |> ignore
  })
}

///|
/// A choice: a capsule of white (the chosen one's pink), a flower at its start, its words in its middle.
fn adv_choice(c : @ui.Ctx, words : String, on : Bool) -> Unit {
  c.box(style=if on { adv_pill_on } else { adv_pill }, fn() {
    c.box(style=if on { adv_ring_on } else { adv_ring }, fn() {
      c.box(style=adv_side, fn() { sr_words(c, "❀", if on { adv_flower_on } else { adv_flower }) }) |> ignore
      c.box(style=adv_choice_mid, fn() { sr_words(c, words, if on { adv_choice_on } else { adv_choice_words }) })
      |> ignore
      c.box(style=adv_side, fn() {  }) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
let adv_ground : Int64 = 0x1B1430FFL

///|
let adv_art_h : Double = 540.0

///|
/// The card under the picture: 652 in all.
let adv_rest_h : Double = 112.0

///|
let adv_shade_top : Double = 330.0

///|
let adv_shade_h : Double = 322.0

///|
/// The night over the picture's foot: clear, mostly by 38% down it, whole by 62%.
// kept across runs: a table, never written
let adv_shade : Array[(Double, Double)] = [(0.0, 0.0), (0.38, 0.8), (0.62, 1.0), (1.0, 1.0)]

///|
let adv_edge : Double = 14.0

///|
let adv_brand_r : Double = 16.0

///|
let adv_brand_t : Double = 15.0

///|
let adv_choices_x : Double = 44.0

///|
let adv_choices_t : Double = 338.0

///|
let adv_box_x : Double = 12.0

///|
let adv_box_t : Double = 448.0

///|
let adv_box_h : Double = 152.0

///|
let adv_hair_x : Double = 14.0

///|
let adv_hair_t : Double = 8.0

///|
let adv_next_r : Double = 16.0

///|
let adv_next_b : Double = 10.0

///|
let adv_name_x : Double = 22.0

///|
let adv_name_t : Double = 434.0

///|
let adv_menu_t : Double = 608.0

///|
let adv_foot_t : Double = 630.0

///|
/// AUTO, lit as the game's is while it reads on by itself.
let adv_menu_on_at : Int = 4

///|
let adv_hi_scale : Double = 1.08

///|
let adv_side_w : Double = 14.0

///|
let adv_white : Int64 = 0xFFFFFFFFL

///|
let adv_gold : Int64 = 0xFFD36BFFL

///|
let adv_pink : Int64 = 0xFFB3D1FFL

///|
let adv_chip_bg : Int64 = 0x120C22A6L

///|
let adv_chip_ink : Int64 = 0xF3E8FFFFL

///|
let adv_chip_hi : Int64 = 0xFFD2E6FFL

///|
let adv_choice_bg : Int64 = 0xFFFAFCE6L

///|
let adv_choice_ink : Int64 = 0x3B2457FFL

///|
let adv_choice_ring : Int64 = 0xF3B6D3FFL

///|
let adv_flower_ink : Int64 = 0xF08BB5FFL

///|
let adv_on_bg : Int64 = 0xF28DB9F0L

///|
let adv_on_ring : Int64 = 0xFFD2E6FFL

///|
let adv_box_bg : Int64 = 0x251940ECL

///|
let adv_box_edge : Int64 = 0xFFFFFF38L

///|
let adv_hair_ink : Int64 = 0xF3B6D366L

///|
let adv_name_bg : Int64 = 0x77C8A1FFL

///|
let adv_name_ink : Int64 = 0x10301FFFL

///|
let adv_line_ink : Int64 = 0xFBF6FFFFL

///|
let adv_menu_ink : Int64 = 0xCBBFE6FFL

///|
let adv_foot_ink : Int64 = 0x8E80B0FFL

///|
// kept across runs: a value (no field of it changes)
let adv_chip : @ui.Style = @ui.css("row px=S3 py=S1_25 radius=Full gap=S2 align=ACenter").then(
  @ui.style(bg=Data(adv_chip_bg)),
)

///|
// kept across runs: a value (no field of it changes)
let adv_chip_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(adv_chip_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let adv_chip_day : @ui.TextStyle = @ui.text_style(size=Xs, weight=Bold, color=Data(adv_chip_hi), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let adv_brand : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Data(adv_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let adv_choices : @ui.Style = @ui.css("gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let adv_pill : @ui.Style = @ui.css("w=Full radius=Full border=B1_5").then(
  @ui.style(bg=Data(adv_choice_bg), border_color=Data(adv_white)),
)

///|
// kept across runs: a value (no field of it changes)
let adv_pill_on : @ui.Style = adv_pill.then(@ui.style(bg=Data(adv_on_bg)))

///|
// kept across runs: a value (no field of it changes)
let adv_ring : @ui.Style = @ui.css("row w=Full radius=Full border=B1 px=S3_5 py=S2 align=ACenter").then(
  @ui.style(border_color=Data(adv_choice_ring)),
)

///|
// kept across runs: a value (no field of it changes)
let adv_ring_on : @ui.Style = adv_ring.then(@ui.style(border_color=Data(adv_on_ring)))

///|
// kept across runs: a value (no field of it changes)
let adv_side : @ui.Style = @ui.style(w=Fixed(adv_side_w))

///|
// kept across runs: a value (no field of it changes)
let adv_choice_mid : @ui.Style = @ui.css("align=ACenter").then(@ui.style(w=@sf.grow))

///|
// kept across runs: a value (no field of it changes)
let adv_flower : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(adv_flower_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let adv_flower_on : @ui.TextStyle = adv_flower.then(@ui.text_style(color=Data(adv_white)))

///|
// kept across runs: a value (no field of it changes)
let adv_choice_words : @ui.TextStyle = @ui.text_style(size=Lg, leading=L5, color=Data(adv_choice_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let adv_choice_on : @ui.TextStyle = adv_choice_words.then(@ui.text_style(color=Data(adv_white)))

///|
/// The box she talks in: 152 tall at least, its night a little clear, a hairline round it.
// kept across runs: a value (no field of it changes)
let adv_box : @ui.Style = @ui.css("radius=Xl2 border=B1 pt=S5 px=S4 pb=S3").then(
  @ui.style(min_h=Fixed(adv_box_h), bg=Data(adv_box_bg), border_color=Data(adv_box_edge)),
)

///|
// kept across runs: a value (no field of it changes)
let adv_hair : @ui.Style = @ui.css("h=SPx").then(@ui.style(bg=Data(adv_hair_ink)))

///|
// kept across runs: a value (no field of it changes)
let adv_line : @ui.TextStyle = @ui.text_style(size=Xl, leading=L6, color=Data(adv_line_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let adv_next : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(adv_pink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let adv_name : @ui.Style = @ui.css("px=S4_5 pt=S1 pb=S1_25 radius=Lg").then(@ui.style(bg=Data(adv_name_bg)))

///|
// kept across runs: a value (no field of it changes)
let adv_name_words : @ui.TextStyle = @ui.text_style(
  size=Lg,
  weight=Bold,
  tracking=Widest,
  color=Data(adv_name_ink),
  wrap=false,
)

///|
// kept across runs: a value (no field of it changes)
let adv_menu : @ui.Style = @ui.css("row w=Full gap=S3 justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let adv_menu_words : @ui.TextStyle = @ui.text_style(size=Xs3, tracking=@sf.share_letters_apart, color=Data(adv_menu_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let adv_menu_on : @ui.TextStyle = adv_menu_words.then(@ui.text_style(color=Data(adv_gold)))

///|
// kept across runs: a value (no field of it changes)
let adv_foot : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(adv_foot_ink), wrap=false)

///|
/// still.fail's line in the card's middle.
// kept across runs: a value (no field of it changes)
let adv_foot_row : @ui.Style = @ui.css("w=Full align=ACenter")

// ── 芳乃 · 御神签 ────────────────────────────────────────────────────────────

///|
/// 芳乃's: a fortune slip drawn at 建实神社. Her picture (holding out the box), falling into the paper's cream; on the
/// slip in its red frame the shrine and the slip's number (the week's chats archived, in Chinese figures), the fortune
/// by how many of the seven days had work (all seven 大吉), seven lines of what it says (wish, visitor, study, trade,
/// travel, love, quarrels: the week's figures), the shrine's seal; what she says under it, still.fail's line and when.
fn sr_omikuji(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = sr_args(fleet)
  let days = sr_days(fleet).filter(fn(d) { d.3 > 0.0 }).length()
  let grade = if days >= 7 {
    "7"
  } else if days >= 5 {
    "5"
  } else if days >= 3 {
    "3"
  } else if days >= 1 {
    "1"
  } else {
    "0"
  }
  let luck = hero_t("omikuji.luck" + grade)
  let archived = sr_num(sr_arg(args, "archived"))
  let n = @string.parse_int(archived) catch { _ => 0 }
  // (the slip's number as each language numbers it: 第五十七番, No. 57)
  let no = hero_t("omikuji.no", args=[("no", if @sf.language() == "zh" { omi_cn(n) } else { archived })])
  let first = items(fleet, "spent").get(0)
  let share = (number(first, "share") * omi_percent + 0.5).to_int().to_string() + "%"
  let kind_words : Array[String] = text(first, "name").split(" ").map(fn(w) { w.to_owned() }).collect()
  let kind = if kind_words.length() > 1 { hero_but_last(kind_words) } else { text(first, "name") }
  let hi = fn(name : String) -> (String, @ui.Run) { (name, hero_hi(sr_arg(args, name), omi_figure, scale=omi_hi_scale)) }
  let lines = [
    ("omikuji.wishK", hero_said("omikuji.wish", [], [hi("archived")])),
    ("omikuji.waitK", hero_said("omikuji.wait", [("model", sr_arg(args, "model"))], [hi("tokens")])),
    ("omikuji.studyK", hero_said("omikuji.study", [], [hi("weekTokens")])),
    ("omikuji.tradeK", hero_said("omikuji.trade", [], [hi("weekCost")])),
    ("omikuji.travelK", hero_said("omikuji.travel", [], [hi("tasks")])),
    ("omikuji.loveK", hero_said("omikuji.love", [("kind", kind)], [("share", hero_hi(share, omi_figure, scale=omi_hi_scale))])),
    ("omikuji.fightK", hero_said("omikuji.fight", [], [hi("chats")])),
  ]
  sr_box(c, id, flat, omi_ground, fn() {
    hero_top(c, "a2-yoshino-omikuji", omi_art_h, omi_art_at, omi_ground, omi_fade)
    c.box(left=omi_brand_x, top=omi_brand_y, fn() { sr_brand(c, omi_brand) }) |> ignore
    hero_gap(c, omi_lift)
    c.box(style=omi_slip, fn() {
      c.box(style=omi_frame, fn() {
        c.box(style=omi_head, fn() {
          sr_words(c, hero_t("omikuji.shrine"), omi_shrine)
          c.box(style=hero_grow, fn() {  }) |> ignore
          sr_words(c, no, omi_no)
        })
        |> ignore
        c.box(style=omi_mid, fn() {
          sr_words(c, hero_t("omikuji.title"), omi_title)
          // (a fortune of a word or two as large as the slip holds; said longer, as a line)
          if luck.length() <= omi_luck_short {
            sr_rich(c, [@ui.span(luck, scale=omi_luck_scale)], omi_luck)
          } else {
            sr_words(c, luck, omi_luck_long)
          }
          sr_words(c, hero_t("omikuji.why" + grade, args=[("days", days.to_string())]), omi_why)
        })
        |> ignore
        c.box(style=omi_rule, fn() {  }) |> ignore
        c.box(style=omi_lines, fn() {
          for x in lines {
            c.box(style=omi_line, fn() {
              c.box(style=omi_key, fn() { sr_words(c, hero_t(x.0), omi_key_words) }) |> ignore
              c.box(style=hero_grow, fn() { sr_rich(c, x.1, omi_words) }) |> ignore
            })
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
      // the shrine's seal, in its four characters two by two
      c.box(style=omi_seal, right=omi_seal_r, top=omi_seal_t, fn() { hero_seal(c, hero_t("omikuji.seal"), omi_seal_words) })
      |> ignore
    })
    |> ignore
    c.box(style=omi_say, fn() {
      c.box(style=omi_who, fn() { sr_words(c, hero_t("omikuji.who"), omi_who_words) }) |> ignore
      c.box(style=hero_grow, fn() { sr_words(c, hero_t("omikuji.say", args=[("luck", luck)]), omi_say_words) }) |> ignore
    })
    |> ignore
    hero_foot(c, fleet, omi_foot, omi_foot_words)
  })
}

///|
/// A seal's characters two to a line (建实 over 神社; 常 over 陆), in its middle.
fn hero_seal(c : @ui.Ctx, words : String, style : @ui.TextStyle) -> Unit {
  let chars = hero_chars(words)
  let per = if chars.length() > 3 { 2 } else { 1 }
  let mut i = 0
  while i < chars.length() {
    let line = StringBuilder()
    let end = if i + per < chars.length() { i + per } else { chars.length() }
    for k in i..<end {
      line.write_string(chars[k])
    }
    sr_words(c, line.to_string(), style)
    i = i + per
  }
}

///|
/// `x` in Chinese figures (57: 五十七), from the figures the catalog says (〇 to 九, 十, 百); in the digits where it says
/// fewer.
fn omi_cn(x : Int) -> String {
  let ds = hero_chars(hero_t("omikuji.digits"))
  if ds.length() < 12 || x < 0 || x >= 1000 {
    return x.to_string()
  }
  if x < 10 {
    return ds[x]
  }
  let t = x / 10 % 10
  let u = x % 10
  let buf = StringBuilder()
  if x >= 100 {
    buf.write_string(ds[x / 100])
    buf.write_string(ds[11])
  }
  if t != 0 {
    if !(t == 1 && x < 100) {
      buf.write_string(ds[t])
    }
    buf.write_string(ds[10])
  } else if x >= 100 && u != 0 {
    buf.write_string(ds[0])
  }
  if u != 0 {
    buf.write_string(ds[u])
  }
  buf.to_string()
}

///|
let omi_ground : Int64 = 0xF6EFE0FFL

///|
let omi_art_h : Double = 236.0

///|
let omi_art_at : Double = 0.3

///|
let omi_fade : Double = 62.0

///|
/// The slip rises 34 over the picture's foot.
let omi_lift : Double = 202.0

///|
let omi_brand_x : Double = 16.0

///|
let omi_brand_y : Double = 14.0

///|
let omi_seal_r : Double = 20.0

///|
let omi_seal_t : Double = 90.0

///|
let omi_seal_side : Double = 46.0

///|
let omi_key_w : Double = 34.0

///|
let omi_percent : Double = 100.0

///|
let omi_hi_scale : Double = 1.06

///|
/// 大吉 78 high: Xl7's 72, a little more.
let omi_luck_scale : Double = 1.08

///|
/// A fortune this long or shorter is said large.
let omi_luck_short : Int = 3

///|
let omi_red : Int64 = 0xC8283AFFL

///|
let omi_figure : Int64 = 0xA3121FFFL

///|
let omi_paper : Int64 = 0xFFFAF0FFL

///|
let omi_ink : Int64 = 0x2B2320FFL

///|
let omi_brown : Int64 = 0x8A5A4AFFL

///|
let omi_why_ink : Int64 = 0x6B4A3AFFL

///|
let omi_rule_ink : Int64 = 0xC8283A66L

///|
let omi_seal_ink : Int64 = 0xC8283AE0L

///|
let omi_say_ink : Int64 = 0x3A2C28FFL

///|
let omi_who_bg : Int64 = 0x4A5AA8FFL

///|
let omi_foot_ink : Int64 = 0x8A6A5AFFL

///|
let omi_white : Int64 = 0xFFFFFFFFL

///|
// kept across runs: a value (no field of it changes)
let omi_brand : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Data(omi_white), wrap=false)

///|
/// The slip: its paper in a red edge, 16 in from the card's sides.
// kept across runs: a value (no field of it changes)
let omi_slip : @ui.Style = @ui.css("mx=S4 border=B1_5 p=S1").then(
  @ui.style(bg=Data(omi_paper), border_color=Data(omi_red)),
)

///|
/// A thinner red line 6 in from its edge, what it says inside it.
// kept across runs: a value (no field of it changes)
let omi_frame : @ui.Style = @ui.css("w=Full border=B1 px=S2_5 pt=S2_5 pb=S2").then(@ui.style(border_color=Data(omi_red)))

///|
// kept across runs: a value (no field of it changes)
let omi_head : @ui.Style = @ui.css("row w=Full px=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let omi_shrine : @ui.TextStyle = @ui.text_style(size=Sm, tracking=Widest, color=Data(omi_red), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let omi_no : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(omi_red), wrap=false)

///|
/// The title, the fortune, why: in the slip's middle.
// kept across runs: a value (no field of it changes)
let omi_mid : @ui.Style = @ui.css("w=Full align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let omi_title : @ui.TextStyle = @ui.text_style(size=Sm, tracking=Widest, color=Data(omi_brown), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let omi_luck : @ui.TextStyle = @ui.text_style(size=Xl7, weight=Bold, tracking=@sf.share_letters_apart, color=Data(omi_red), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let omi_luck_long : @ui.TextStyle = @ui.text_style(size=Xl4, weight=Bold, color=Data(omi_red))

///|
// kept across runs: a value (no field of it changes)
let omi_why : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(omi_why_ink))

///|
// kept across runs: a value (no field of it changes)
let omi_rule : @ui.Style = @ui.css("w=Full h=SPx mt=S2_5 mb=S2_5").then(@ui.style(bg=Data(omi_rule_ink)))

///|
// kept across runs: a value (no field of it changes)
let omi_lines : @ui.Style = @ui.css("w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let omi_line : @ui.Style = @ui.css("row w=Full gap=S2_5 align=AStart")

///|
/// What a line is of: white on the red, 34 wide at least.
// kept across runs: a value (no field of it changes)
let omi_key : @ui.Style = @ui.css("radius=Sm px=S0_5 py=S0_5 mt=SPx align=ACenter").then(
  @ui.style(min_w=Fixed(omi_key_w), bg=Data(omi_red)),
)

///|
// kept across runs: a value (no field of it changes)
let omi_key_words : @ui.TextStyle = @ui.text_style(size=Xs, tracking=@sf.share_letters_apart, color=Data(omi_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let omi_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5, color=Data(omi_ink), w=Full)

///|
/// The seal: 46 square, its red edge, a little faint.
// kept across runs: a value (no field of it changes)
let omi_seal : @ui.Style = @ui.css("border=B2 radius=Base align=ACenter justify=JCenter").then(
  @ui.style(w=Fixed(omi_seal_side), h=Fixed(omi_seal_side), border_color=Data(omi_seal_ink)),
)

///|
// kept across runs: a value (no field of it changes)
let omi_seal_words : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, leading=L5, color=Data(omi_seal_ink), wrap=false)

///|
/// What she says, 18 in, her name on its capsule before it.
// kept across runs: a value (no field of it changes)
let omi_say : @ui.Style = @ui.css("row w=Full px=S4_5 pt=S3_5 gap=S2_5 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let omi_who : @ui.Style = @ui.css("px=S2 py=S0_5 radius=Full mt=S0_5").then(@ui.style(bg=Data(omi_who_bg)))

///|
// kept across runs: a value (no field of it changes)
let omi_who_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(omi_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let omi_say_words : @ui.TextStyle = @ui.text_style(size=Base, leading=L6, color=Data(omi_say_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let omi_foot : @ui.Style = @ui.css("row w=Full px=S5 pt=S3_5 pb=S4 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let omi_foot_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(omi_foot_ink), wrap=false)

// ── 茉子 · 忍务报告书 ────────────────────────────────────────────────────────

///|
/// 茉子's: a ninja's mission report on a scroll. Her picture (on a roof at night, scared of the height), still.fail on
/// its moon; the scroll's rods over and under its paper, a band of navy and gold at its top; to 有地さん, its title, the
/// red 极秘 stamp; five missions (the chats at work, the tasks across devices, the top model's tokens, the week's
/// spend, the chats archived) each with its state; what she writes after, her name and seal; still.fail's line.
fn sr_ninja(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = sr_args(fleet)
  let on = hero_t("ninja.on")
  let ok = hero_t("ninja.ok")
  let missions = [
    ("chats", sr_arg(args, "chats"), hero_t("ninja.chatsN", args=[("devices", sr_arg(args, "devices"))]), on, true),
    ("tasks", sr_arg(args, "tasks"), hero_t("ninja.tasksN", args=[("per", sr_arg(args, "tasksPer"))]), ok, false),
    (
      "intel",
      sr_arg(args, "tokens"),
      hero_t("ninja.intelN", args=[("model", sr_arg(args, "model")), ("cost", sr_arg(args, "cost"))]),
      ok,
      false,
    ),
    ("funds", sr_arg(args, "weekCost"), hero_t("ninja.fundsN"), hero_t("ninja.claim"), true),
    ("done", sr_num(sr_arg(args, "archived")), hero_t("ninja.doneN"), ok, false),
  ]
  sr_box(c, id, flat, nin_ground, fn() {
    hero_top(c, "a3-mako-roof", nin_art_h, nin_art_at, nin_ground, nin_fade)
    for s in nin_stars {
      c.box(style=nin_star, left=s.0, top=s.1, fn() {  }) |> ignore
    }
    c.box(left=nin_brand_x, top=nin_brand_y, fn() { sr_brand(c, nin_brand) }) |> ignore
    hero_gap(c, nin_lift)
    nin_rod(c)
    c.box(style=nin_paper, fn() {
      // a band of navy and gold across its top
      c.box(style=nin_band, left=hero_zero, right=hero_zero, top=nin_band_t, fn() {
        for _ in 0..<nin_band_count {
          c.box(style=nin_band_navy, fn() {  }) |> ignore
          c.box(style=nin_band_gold, fn() {  }) |> ignore
        }
      })
      |> ignore
      sr_rich(c, hero_said("ninja.to", [], [("arichi", @ui.span(hero_t("ninja.arichi"), color=nin_navy, bold=true))]), nin_to)
      sr_words(c, hero_t("ninja.title"), nin_title)
      sr_words(c, hero_t("ninja.sub"), nin_sub)
      c.box(style=nin_rows, fn() {
        hero_rule(c, nin_navy, nin_rule_h)
        for m in missions {
          c.box(style=nin_row, fn() {
            sr_words(c, "✦", nin_mark)
            c.box(style=nin_key, fn() { sr_words(c, hero_t("ninja." + m.0 + "K"), nin_key_words) }) |> ignore
            c.box(style=hero_grow, fn() {
              sr_rich(c, hero_said("ninja." + m.0, [], [("count", hero_hi(m.1, nin_red, scale=nin_big_scale))]), nin_value)
              sr_words(c, m.2, nin_note)
            })
            |> ignore
            c.box(style=if m.4 { nin_state_on } else { nin_state_ok }, fn() {
              sr_words(c, m.3, if m.4 { nin_state_on_words } else { nin_state_ok_words })
            })
            |> ignore
          })
          |> ignore
          hero_dashes(c, nin_dash)
        }
      })
      |> ignore
      c.box(style=nin_ps_room, fn() {
        sr_rich(c, [@ui.span(hero_t("ninja.who"), color=nin_red, bold=true), @ui.span(hero_t("ninja.ps"))], nin_ps)
      })
      |> ignore
      c.box(style=nin_sig, fn() {
        sr_words(c, hero_t("ninja.sig"), nin_sig_words)
        c.box(style=nin_seal, fn() { hero_seal(c, hero_t("ninja.seal"), nin_seal_words) }) |> ignore
      })
      |> ignore
      // 极秘, stamped over its corner
      c.box(style=nin_secret, right=nin_secret_r, top=nin_secret_t, fn() {
        c.box(style=nin_secret_in, fn() { sr_words(c, hero_t("ninja.secret"), nin_secret_words) }) |> ignore
      })
      |> ignore
    })
    |> ignore
    nin_rod(c)
    hero_foot(c, fleet, nin_foot, nin_foot_words)
  })
}

///|
/// A rod of the scroll: navy, round, a gold cap at either end.
fn nin_rod(c : @ui.Ctx) -> Unit {
  c.box(style=nin_rod_room, fn() {
    c.box(style=nin_rod_bar, left=nin_rod_x, right=nin_rod_x, top=hero_zero, fn() {  }) |> ignore
    c.box(style=nin_cap, left=nin_cap_x, top=nin_cap_t, fn() {  }) |> ignore
    c.box(style=nin_cap, right=nin_cap_x, top=nin_cap_t, fn() {  }) |> ignore
  })
  |> ignore
}

///|
let nin_ground : Int64 = 0x121A31FFL

///|
let nin_art_h : Double = 240.0

///|
let nin_art_at : Double = 0.4

///|
let nin_fade : Double = 74.0

///|
/// The scroll rises 24 over the picture's foot.
let nin_lift : Double = 216.0

///|
/// still.fail on the moon.
let nin_brand_x : Double = 47.0

///|
let nin_brand_y : Double = 45.0

///|
/// The sky's few stars beside the scroll: where, from the card's top left.
// kept across runs: a table, never written
let nin_stars : Array[(Double, Double)] = [(21.0, 410.0), (341.0, 490.0), (10.0, 649.0), (348.0, 728.0)]

///|
let nin_rod_h : Double = 18.0

///|
let nin_rod_x : Double = 10.0

///|
let nin_cap_x : Double = 4.0

///|
let nin_cap_t : Double = 2.0

///|
let nin_cap_w : Double = 12.0

///|
let nin_cap_h : Double = 14.0

///|
let nin_band_t : Double = 6.0

///|
let nin_band_count : Int = 42

///|
let nin_band_navy_w : Double = 6.0

///|
let nin_band_gold_w : Double = 2.0

///|
let nin_rule_h : Double = 1.5

///|
let nin_key_w : Double = 70.0

///|
let nin_big_scale : Double = 1.5

///|
let nin_secret_r : Double = 16.0

///|
let nin_secret_t : Double = 26.0

///|
let nin_seal_side : Double = 36.0

///|
let nin_navy : Int64 = 0x1B2440FFL

///|
let nin_red : Int64 = 0xB0202CFFL

///|
let nin_stamp : Int64 = 0xC4232FE0L

///|
let nin_rod_ink : Int64 = 0x1F2950FFL

///|
let nin_gold : Int64 = 0xC99A3EFFL

///|
let nin_band_navy_ink : Int64 = 0x1F2950D9L

///|
let nin_band_gold_ink : Int64 = 0xC9A24AD9L

///|
let nin_paper_ink : Int64 = 0xF5EFE1FFL

///|
let nin_paper_edge : Int64 = 0xD8CDB3FFL

///|
let nin_dim : Int64 = 0x4A5070FFL

///|
let nin_grey : Int64 = 0x6A6F88FFL

///|
let nin_title_ink : Int64 = 0x18213FFFL

///|
let nin_value_ink : Int64 = 0x2B3150FFL

///|
let nin_dash : Int64 = 0x1B244055L

///|
let nin_ps_ink : Int64 = 0x1F2747FFL

///|
let nin_star_ink : Int64 = 0xFFFFFF66L

///|
let nin_foot_ink : Int64 = 0x8C96C0FFL

///|
let nin_white : Int64 = 0xFFFFFFFFL

///|
let nin_moon_ink : Int64 = 0x1A2140E6L

///|
// kept across runs: a value (no field of it changes)
let nin_star : @ui.Style = @ui.css("w=S0_5 h=S0_5 radius=Full").then(@ui.style(bg=Data(nin_star_ink)))

///|
// kept across runs: a value (no field of it changes)
let nin_brand : @ui.TextStyle = @ui.text_style(size=Xl, weight=Semibold, color=Data(nin_moon_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let nin_rod_room : @ui.Style = @ui.style(w=Full, h=Fixed(nin_rod_h))

///|
// kept across runs: a value (no field of it changes)
let nin_rod_bar : @ui.Style = @ui.css("radius=Full").then(@ui.style(h=Fixed(nin_rod_h), bg=Data(nin_rod_ink)))

///|
// kept across runs: a value (no field of it changes)
let nin_cap : @ui.Style = @ui.css("radius=Base").then(
  @ui.style(w=Fixed(nin_cap_w), h=Fixed(nin_cap_h), bg=Data(nin_gold)),
)

///|
/// The paper between the rods: 20 in from the card's sides.
// kept across runs: a value (no field of it changes)
let nin_paper : @ui.Style = @ui.css("mx=S5 pt=S6 px=S4_5 pb=S4_5 border=B1").then(
  @ui.style(bg=Data(nin_paper_ink), border_color=Data(nin_paper_edge)),
)

///|
// kept across runs: a value (no field of it changes)
let nin_band : @ui.Style = @ui.css("row h=S1 clip")

///|
// kept across runs: a value (no field of it changes)
let nin_band_navy : @ui.Style = @ui.style(w=Fixed(nin_band_navy_w), h=Full, bg=Data(nin_band_navy_ink))

///|
// kept across runs: a value (no field of it changes)
let nin_band_gold : @ui.Style = @ui.style(w=Fixed(nin_band_gold_w), h=Full, bg=Data(nin_band_gold_ink))

///|
// kept across runs: a value (no field of it changes)
let nin_to : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(nin_dim), w=Full)

///|
// kept across runs: a value (no field of it changes)
let nin_title : @ui.TextStyle = @ui.text_style(size=Xl4, weight=Bold, tracking=Widest, color=Data(nin_title_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let nin_sub : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(nin_grey), w=Full)

///|
// kept across runs: a value (no field of it changes)
let nin_rows : @ui.Style = @ui.css("w=Full pt=S3")

///|
/// A mission: its mark, what it is, its figure over its note, its state; 6 over and under.
// kept across runs: a value (no field of it changes)
let nin_row : @ui.Style = @ui.css("row w=Full gap=S2 pt=S1_25 pb=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let nin_mark : @ui.TextStyle = @ui.text_style(size=Lg, color=Data(nin_navy), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let nin_key : @ui.Style = @ui.style(w=Fixed(nin_key_w))

///|
// kept across runs: a value (no field of it changes)
let nin_key_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(nin_navy), w=Full)

///|
// kept across runs: a value (no field of it changes)
let nin_value : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(nin_value_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let nin_note : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(nin_grey), w=Full)

///|
/// A mission's state: under way white on the navy, done in a red edge.
// kept across runs: a value (no field of it changes)
let nin_state_on : @ui.Style = @ui.css("px=S1_5 py=SPx radius=Sm").then(@ui.style(bg=Data(nin_navy)))

///|
// kept across runs: a value (no field of it changes)
let nin_state_ok : @ui.Style = @ui.css("px=S1_5 py=SPx radius=Sm border=B1").then(@ui.style(border_color=Data(nin_red)))

///|
// kept across runs: a value (no field of it changes)
let nin_state_on_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(nin_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let nin_state_ok_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(nin_red), wrap=false)

///|
/// What she writes after, a little in from the paper's right (as the mockup wraps it).
// kept across runs: a value (no field of it changes)
let nin_ps_room : @ui.Style = @ui.css("w=Full pr=S2_5")

///|
// kept across runs: a value (no field of it changes)
let nin_ps : @ui.TextStyle = @ui.text_style(size=Base, leading=L6, color=Data(nin_ps_ink), w=Full)

///|
/// Her name and seal at the paper's end.
// kept across runs: a value (no field of it changes)
let nin_sig : @ui.Style = @ui.css("row w=Full gap=S2 pt=S2 justify=JEnd align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let nin_sig_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(nin_navy), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let nin_seal : @ui.Style = @ui.css("radius=Full border=B2 align=ACenter justify=JCenter").then(
  @ui.style(w=Fixed(nin_seal_side), h=Fixed(nin_seal_side), border_color=Data(nin_stamp)),
)

///|
// kept across runs: a value (no field of it changes)
let nin_seal_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, leading=L3, color=Data(nin_stamp), wrap=false)

///|
/// 极秘: a thin red line 2 out from a thick one.
// kept across runs: a value (no field of it changes)
let nin_secret : @ui.Style = @ui.css("border=B1 p=S0_5").then(@ui.style(border_color=Data(nin_stamp)))

///|
// kept across runs: a value (no field of it changes)
let nin_secret_in : @ui.Style = @ui.css("border=B2 px=S2 py=S1").then(@ui.style(border_color=Data(nin_stamp)))

///|
// kept across runs: a value (no field of it changes)
let nin_secret_words : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Bold, tracking=@sf.share_letters_apart, color=Data(nin_stamp), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let nin_foot : @ui.Style = @ui.css("row w=Full px=S5 pt=S4 pb=S3_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let nin_foot_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(nin_foot_ink), wrap=false)

// ── 蕾娜 · 志那都庄的账单 ─────────────────────────────────────────────────────

///|
/// 蕾娜's: the inn's bill (御会计) from 志那都庄. Her picture (waving at the inn's door at dusk), falling into the bill's
/// lavender; the noren's rod and its four indigo panels, one character of the inn's name each; on the paper under it
/// the title, the stay (the week's days, so many nights), the inn's stamp, every model a guest (様) with its tokens and
/// its room (cost), the total, who checked out (archived), who is in tonight (at work), the rooms (devices); what she
/// says in her English, the corridor's notice, still.fail's line.
fn sr_ryokan(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = sr_args(fleet)
  let days = sr_days(fleet)
  let nights = days.length().to_string()
  let stay = match days {
    [first, .., last] => hero_t("ryokan.stay", args=[("from", first.0), ("to", last.0), ("nights", nights)])
    _ => hero_t("ryokan.nights", args=[("nights", nights)])
  }
  let count = fn(key : String, v : String) {
    hero_said(key, [], [("count", hero_hi(v, ryo_indigo, scale=ryo_out_scale))])
  }
  let em = fn(key : String) { @ui.span(hero_t(key), color=ryo_purple, bold=true) }
  sr_box(c, id, flat, ryo_ground, fn() {
    hero_top(c, "a4-lena-ryokan", ryo_art_h, ryo_art_at, ryo_ground, ryo_fade)
    c.box(left=ryo_brand_x, top=ryo_brand_y, fn() { sr_brand(c, ryo_brand) }) |> ignore
    hero_gap(c, ryo_lift)
    c.box(style=ryo_rod_room, fn() { c.box(style=ryo_rod, fn() {  }) |> ignore }) |> ignore
    c.box(style=ryo_bill, fn() {
      hero_gap(c, ryo_under_noren)
      c.box(style=ryo_paper_under, fn() {
        c.box(style=ryo_paper, fn() {
          sr_rich(c, [@ui.span(hero_t("ryokan.title"), scale=ryo_title_scale)], ryo_title)
          sr_words(c, stay, ryo_stay)
          c.box(style=ryo_head, fn() {
            c.box(style=hero_grow, fn() { sr_words(c, hero_t("ryokan.guest"), ryo_head_words) }) |> ignore
            c.box(style=ryo_tk_col, fn() { sr_words(c, hero_t("ryokan.tokens"), ryo_head_words) }) |> ignore
            c.box(style=ryo_ct_col, fn() { sr_words(c, hero_t("ryokan.room"), ryo_head_words) }) |> ignore
          })
          |> ignore
          hero_rule(c, ryo_indigo, ryo_rule_h)
          for k, m in sr_models(fleet) {
            let vip = k == 0
            c.box(style=ryo_guest, fn() {
              c.box(style=hero_grow, fn() {
                sr_rich(
                  c,
                  [@ui.span(m.0 + " "), @ui.span(hero_t("ryokan.sama"), color=ryo_purple, scale=ryo_sama_scale)],
                  if vip { ryo_name_vip } else { ryo_name },
                )
              })
              |> ignore
              c.box(style=ryo_tk_col, fn() { sr_words(c, m.1, ryo_tokens) }) |> ignore
              c.box(style=ryo_ct_col, fn() { sr_words(c, m.2, if vip { ryo_cost_vip } else { ryo_cost }) }) |> ignore
            })
            |> ignore
            hero_dashes(c, ryo_dots)
          }
          c.box(style=ryo_double, fn() {
            hero_rule(c, ryo_indigo, ryo_rule_thin)
            hero_rule(c, ryo_indigo, ryo_rule_thin)
          })
          |> ignore
          c.box(style=ryo_sum, fn() {
            sr_words(c, hero_t("ryokan.total"), ryo_sum_words)
            c.box(style=hero_grow, fn() { sr_words(c, hero_t("ryokan.nights", args=[("nights", nights)]), ryo_stay) })
            |> ignore
            sr_words(c, sr_arg(args, "weekCost"), ryo_total)
          })
          |> ignore
          c.box(style=ryo_outs, fn() {
            c.box(style=ryo_out, fn() { sr_rich(c, count("ryokan.out", sr_num(sr_arg(args, "archived"))), ryo_out_words) })
            |> ignore
            c.box(style=ryo_out, fn() { sr_rich(c, count("ryokan.in", sr_arg(args, "chats")), ryo_out_words) }) |> ignore
            c.box(style=ryo_out, fn() { sr_rich(c, count("ryokan.rooms", sr_arg(args, "devices")), ryo_out_words) })
            |> ignore
          })
          |> ignore
          // the inn's stamp
          c.box(style=ryo_stamp, right=ryo_stamp_r, top=ryo_stamp_t, fn() {
            c.box(style=ryo_stamp_in, fn() { hero_seal(c, hero_t("ryokan.stamp"), ryo_stamp_words) }) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
      // the noren over the paper's top, one character of the inn on each panel
      c.box(style=ryo_noren, left=hero_zero, right=hero_zero, top=hero_zero, fn() {
        for ch in hero_chars(hero_t("ryokan.noren")) {
          c.box(style=ryo_panel, fn() {
            c.box(style=ryo_panel_top, left=hero_zero, right=hero_zero, top=hero_zero, fn() {  }) |> ignore
            sr_words(c, ch, ryo_panel_words)
            c.box(style=ryo_panel_line, left=ryo_panel_in, right=ryo_panel_in, bottom=ryo_panel_in, fn() {  }) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
    c.box(style=ryo_say_under, fn() {
      c.box(style=ryo_say, fn() {
        let marks = [
          ("ciallo", @ui.span(hero_t("ryokan.ciallo"), color=ryo_pink, bold=true)),
          ("welcome", em("ryokan.welcome")),
          ("total", em("ryokan.totalSaid")),
          ("very", em("ryokan.very")),
          ("cost", hero_hi(sr_arg(args, "weekCost"), ryo_red, scale=ryo_say_scale)),
        ]
        let who = @ui.span(" " + hero_t("ryokan.who") + " ", color=ryo_white, bg=ryo_who_bg, scale=ryo_who_scale)
        sr_rich(c, [who, @ui.span(" "), ..hero_said("ryokan.say", [], marks)], ryo_say_words)
      })
      |> ignore
    })
    |> ignore
    c.box(style=ryo_note, fn() { sr_words(c, hero_t("ryokan.note"), ryo_note_words) }) |> ignore
    hero_foot(c, fleet, ryo_foot, ryo_foot_words)
  })
}

///|
let ryo_ground : Int64 = 0xE7DEF6FFL

///|
let ryo_art_h : Double = 240.0

///|
let ryo_art_at : Double = 0.4

///|
let ryo_fade : Double = 66.0

///|
/// The noren's rod 54 up over the picture's foot.
let ryo_lift : Double = 186.0

///|
let ryo_brand_x : Double = 16.0

///|
let ryo_brand_y : Double = 14.0

///|
let ryo_rod_h : Double = 8.0

///|
let ryo_noren_h : Double = 48.0

///|
/// The paper's top under the noren's foot.
let ryo_under_noren : Double = 38.0

///|
let ryo_panel_top_h : Double = 8.0

///|
let ryo_panel_in : Double = 6.0

///|
let ryo_rule_h : Double = 1.5

///|
let ryo_rule_thin : Double = 1.0

///|
let ryo_tk_w : Double = 74.0

///|
let ryo_ct_w : Double = 66.0

///|
let ryo_stamp_r : Double = 14.0

///|
let ryo_stamp_t : Double = 16.0

///|
let ryo_stamp_side : Double = 52.0

///|
/// 御会计 27 high: Xl3's 22, larger.
let ryo_title_scale : Double = 1.22

///|
let ryo_sama_scale : Double = 0.8

///|
let ryo_out_scale : Double = 1.25

///|
let ryo_say_scale : Double = 1.08

///|
let ryo_who_scale : Double = 0.8

///|
let ryo_indigo : Int64 = 0x2B2566FFL

///|
let ryo_ink : Int64 = 0x2A2357FFL

///|
let ryo_purple : Int64 = 0x6B4FA0FFL

///|
let ryo_red : Int64 = 0xB0234AFFL

///|
let ryo_pink : Int64 = 0xE0457BFFL

///|
let ryo_white : Int64 = 0xFFFFFFFFL

///|
let ryo_wood : Int64 = 0x8A6240FFL

///|
let ryo_panel_ink : Int64 = 0x332C75FFL

///|
let ryo_panel_dark : Int64 = 0x242060FFL

///|
let ryo_panel_rule : Int64 = 0xFFFFFF40L

///|
let ryo_paper_ink : Int64 = 0xFDFBFFFFL

///|
let ryo_paper_shadow : Int64 = 0xCBBDE8FFL

///|
let ryo_soft : Int64 = 0x7A6AA8FFL

///|
let ryo_head_ink : Int64 = 0x8D80B8FFL

///|
let ryo_tk_ink : Int64 = 0x4A4080FFL

///|
let ryo_dots : Int64 = 0xB6A8DCFFL

///|
let ryo_out_bg : Int64 = 0xF1ECFBFFL

///|
let ryo_stamp_ink : Int64 = 0xC4304AD9L

///|
let ryo_say_shadow : Int64 = 0xC9B8EFFFL

///|
let ryo_who_bg : Int64 = 0x7C5CB8FFL

///|
let ryo_note_ink : Int64 = 0x6A5A98FFL

///|
// kept across runs: a value (no field of it changes)
let ryo_brand : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Data(ryo_white), wrap=false)

///|
/// The noren's rod: a little wider than the bill, its wood round at its ends.
// kept across runs: a value (no field of it changes)
let ryo_rod : @ui.Style = @ui.css("w=Full radius=Full").then(@ui.style(h=Fixed(ryo_rod_h), bg=Data(ryo_wood)))

///|
/// The rod 8 wider than the bill each side: in a room as wide as the card, 10 in from its sides.
// kept across runs: a value (no field of it changes)
let ryo_rod_room : @ui.Style = @ui.css("w=Full px=S4_5")

///|
// kept across runs: a value (no field of it changes)
let ryo_bill : @ui.Style = @ui.css("mx=S4_5")

///|
// kept across runs: a value (no field of it changes)
let ryo_noren : @ui.Style = @ui.css("row gap=S1").then(@ui.style(h=Fixed(ryo_noren_h)))

///|
/// A panel: indigo, its top a shade darker, its character in its middle.
// kept across runs: a value (no field of it changes)
let ryo_panel : @ui.Style = @ui.css("h=Full radius=Sm align=ACenter justify=JCenter pt=S0_5").then(
  @ui.style(w=@sf.grow, bg=Data(ryo_panel_ink)),
)

///|
// kept across runs: a value (no field of it changes)
let ryo_panel_top : @ui.Style = @ui.style(h=Fixed(ryo_panel_top_h), bg=Data(ryo_panel_dark))

///|
// kept across runs: a value (no field of it changes)
let ryo_panel_line : @ui.Style = @ui.css("h=SPx").then(@ui.style(bg=Data(ryo_panel_rule)))

///|
// kept across runs: a value (no field of it changes)
let ryo_panel_words : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Bold, color=Data(ryo_white), wrap=false)

///|
/// The paper on its lavender shadow, 4 lower.
// kept across runs: a value (no field of it changes)
let ryo_paper_under : @ui.Style = @ui.css("w=Full pb=S1 radius=Md").then(@ui.style(bg=Data(ryo_paper_shadow)))

///|
// kept across runs: a value (no field of it changes)
let ryo_paper : @ui.Style = @ui.css("w=Full pt=S4_5 px=S4 pb=S3_5 radius=Md").then(@ui.style(bg=Data(ryo_paper_ink)))

///|
// kept across runs: a value (no field of it changes)
let ryo_title : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Bold, tracking=Widest, color=Data(ryo_indigo), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ryo_stay : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(ryo_soft), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ryo_head : @ui.Style = @ui.css("row w=Full pt=S3 px=S0_5 pb=S1 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let ryo_head_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(ryo_head_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ryo_tk_col : @ui.Style = @ui.css("align=AEnd").then(@ui.style(w=Fixed(ryo_tk_w)))

///|
// kept across runs: a value (no field of it changes)
let ryo_ct_col : @ui.Style = @ui.css("align=AEnd").then(@ui.style(w=Fixed(ryo_ct_w)))

///|
/// A guest's line: its name, tokens, room; 6 over, 5 under.
// kept across runs: a value (no field of it changes)
let ryo_guest : @ui.Style = @ui.css("row w=Full px=S0_5 py=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ryo_name : @ui.TextStyle = @ui.text_style(size=Lg, color=Data(ryo_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let ryo_name_vip : @ui.TextStyle = ryo_name.then(@ui.text_style(color=Data(ryo_red)))

///|
// kept across runs: a value (no field of it changes)
let ryo_tokens : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(ryo_tk_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ryo_cost : @ui.TextStyle = @ui.text_style(size=Lg, weight=Bold, color=Data(ryo_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ryo_cost_vip : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, color=Data(ryo_red), wrap=false)

///|
/// The total's double rule.
// kept across runs: a value (no field of it changes)
let ryo_double : @ui.Style = @ui.css("w=Full gap=SPx pt=S0_5")

///|
// kept across runs: a value (no field of it changes)
let ryo_sum : @ui.Style = @ui.css("row w=Full gap=S1_5 px=S0_5 pt=S1_5 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let ryo_sum_words : @ui.TextStyle = @ui.text_style(size=Base, tracking=@sf.share_letters_apart, color=Data(ryo_indigo), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ryo_total : @ui.TextStyle = @ui.text_style(
  size=Xl4,
  weight=Bold,
  leading=L9,
  color=Data(ryo_red),
  wrap=false,
)

///|
// kept across runs: a value (no field of it changes)
let ryo_outs : @ui.Style = @ui.css("row w=Full gap=S1_5 pt=S2")

///|
// kept across runs: a value (no field of it changes)
let ryo_out : @ui.Style = @ui.css("radius=Md pt=S1_25 pb=S1_5 align=ACenter").then(
  @ui.style(w=@sf.grow, bg=Data(ryo_out_bg)),
)

///|
// kept across runs: a value (no field of it changes)
let ryo_out_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(ryo_tk_ink), wrap=false)

///|
/// The inn's stamp: a red ring in a ring, its name two by two.
// kept across runs: a value (no field of it changes)
let ryo_stamp : @ui.Style = @ui.css("radius=Full border=B2 p=S0_5").then(
  @ui.style(w=Fixed(ryo_stamp_side), h=Fixed(ryo_stamp_side), border_color=Data(ryo_stamp_ink)),
)

///|
// kept across runs: a value (no field of it changes)
let ryo_stamp_in : @ui.Style = @ui.css("w=Full h=Full radius=Full border=B1 align=ACenter justify=JCenter").then(
  @ui.style(border_color=Data(ryo_stamp_ink)),
)

///|
// kept across runs: a value (no field of it changes)
let ryo_stamp_words : @ui.TextStyle = @ui.text_style(size=Base, weight=Bold, leading=L4, color=Data(ryo_stamp_ink), wrap=false)

///|
/// What she says: on white, round, its lavender shadow 4 lower; 18 in from the card's sides.
// kept across runs: a value (no field of it changes)
let ryo_say_under : @ui.Style = @ui.css("mx=S4_5 mt=S4 pb=S1 radius=Xl2").then(@ui.style(bg=Data(ryo_say_shadow)))

///|
// kept across runs: a value (no field of it changes)
let ryo_say : @ui.Style = @ui.css("w=Full px=S3_5 py=S3 radius=Xl2").then(@ui.style(bg=Data(ryo_white)))

///|
// kept across runs: a value (no field of it changes)
let ryo_say_words : @ui.TextStyle = @ui.text_style(size=Lg, leading=L6, color=Data(ryo_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let ryo_note : @ui.Style = @ui.css("w=Full px=S5 pt=S2")

///|
// kept across runs: a value (no field of it changes)
let ryo_note_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(ryo_note_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let ryo_foot : @ui.Style = @ui.css("row w=Full px=S5 pt=S3 pb=S4 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ryo_foot_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(ryo_soft), wrap=false)

// ── 小春 · 甘味处菜单 ────────────────────────────────────────────────────────

///|
/// 小春's: the sweets shop's menu board (お品書き). Her picture (with a tray of parfait and dango), falling into the
/// board's cream; on the washi in its wooden frame, hung on two hooks, the title, 营业中, every model a sweet (the first
/// the 招牌 matcha parfait) drawn small, its cost the price and its tokens under it; 本日售出 stamped with today's chats
/// archived and cost, the week's takings, the guests still waiting (at work); what she says, that 廉太郎 gets no
/// discount, still.fail's line.
fn sr_menu(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = sr_args(fleet)
  let model_words : Array[String] = sr_arg(args, "model").split(" ").map(fn(w) { w.to_owned() }).collect()
  let model = if model_words.length() > 0 { model_words[0] } else { "" }
  sr_box(c, id, flat, menu_ground, fn() {
    hero_top(c, "a5-koharu-sweets", menu_art_h, menu_art_at, menu_ground, menu_fade)
    c.box(left=menu_brand_x, top=menu_brand_y, fn() { sr_brand(c, menu_brand) }) |> ignore
    hero_gap(c, menu_lift)
    c.box(style=menu_board, fn() {
      c.box(style=menu_washi, fn() {
        c.box(style=menu_title_row, fn() {
          sr_rich(c, [@ui.span(hero_t("menu.title"), scale=menu_title_scale)], menu_title)
          sr_words(c, hero_t("menu.sub"), menu_sub)
        })
        |> ignore
        c.box(style=menu_items, fn() {
          hero_rule(c, menu_ink, menu_rule_h)
          for k, m in sr_models(fleet) {
            let top = k == 0
            c.box(style=menu_item, fn() {
              menu_icon(c, k % menu_icons.length())
              c.box(style=menu_name_col, fn() {
                c.box(style=menu_name_row, fn() {
                  sr_words(c, hero_t("menu.sweet" + (k % menu_icons.length()).to_string()), menu_name)
                  if top {
                    c.box(style=menu_hot, fn() { sr_words(c, hero_t("menu.hot"), menu_hot_words) }) |> ignore
                  }
                })
                |> ignore
                sr_words(c, m.0, menu_model)
              })
              |> ignore
              menu_leader(c)
              c.box(style=menu_price, fn() {
                sr_words(c, m.2, if top { menu_cost_top } else { menu_cost })
                sr_words(c, hero_t("menu.tokens", args=[("count", m.1)]), menu_tokens)
              })
              |> ignore
            })
            |> ignore
            hero_dashes(c, menu_dash)
          }
        })
        |> ignore
        c.box(style=menu_tally, fn() {
          c.box(style=menu_sold, fn() {
            c.box(style=menu_sold_in, fn() {
              sr_words(c, hero_t("menu.sold"), menu_sold_words)
              sr_rich(
                c,
                hero_said(
                  "menu.soldN",
                  [],
                  [("count", hero_hi(sr_num(sr_arg(args, "todayArchived")), menu_red, scale=menu_sold_scale))],
                  scale=menu_unit_scale,
                ),
                menu_sold_count,
              )
              sr_words(c, sr_arg(args, "todayCost"), menu_sold_words)
            })
            |> ignore
          })
          |> ignore
          c.box(style=menu_rev, fn() {
            sr_words(c, hero_t("menu.rev"), menu_rev_label)
            sr_words(c, sr_arg(args, "weekCost"), menu_rev_value)
            sr_words(c, hero_t("menu.waiting", args=[("chats", sr_arg(args, "chats"))]), menu_rev_label)
          })
          |> ignore
        })
        |> ignore
        // 营业中, on its red tag
        c.box(style=menu_open_under, right=menu_open_r, top=menu_open_t, fn() {
          c.box(style=menu_open, fn() { sr_words(c, hero_t("menu.open"), menu_open_words) }) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    // the board's two hooks over its top
    c.box(style=menu_hook, left=menu_hook_x, top=menu_hook_t, fn() {  }) |> ignore
    c.box(style=menu_hook, right=menu_hook_x, top=menu_hook_t, fn() {  }) |> ignore
    c.box(style=menu_say_under, fn() {
      c.box(style=menu_say, fn() {
        sr_words(c, hero_t("menu.who"), menu_who)
        sr_rich(c, hero_said("menu.say", [], [("model", hero_hi(model, menu_green))]), menu_say_words)
      })
      |> ignore
    })
    |> ignore
    c.box(style=menu_note, fn() { sr_words(c, hero_t("menu.note"), menu_note_words) }) |> ignore
    hero_foot(c, fleet, menu_foot, menu_foot_words)
  })
}

///|
/// Sweet `k` drawn small, 30 square: its pieces each a box where the table says (left, top, width, height, colour, and
/// whether it is round).
fn menu_icon(c : @ui.Ctx, k : Int) -> Unit {
  c.box(style=menu_icon_box, fn() {
    for p in menu_icons[k] {
      let (x, y, wide, high, ink, round) = p
      c.box(style=@ui.style(w=Fixed(wide), h=Fixed(high), bg=Data(ink), radius=if round { Full } else { Sm }), left=x, top=y, fn() {  })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The dots from a sweet's name to its price.
fn menu_leader(c : @ui.Ctx) -> Unit {
  c.box(style=menu_dots, fn() {
    for _ in 0..<menu_dot_count {
      c.box(style=menu_dot, fn() {  }) |> ignore
    }
  })
  |> ignore
}

///|
/// The sweets, in the models' order: matcha parfait (its glass, layers, two scoops, a cherry, a wafer), sakura mochi
/// on its leaf, three-coloured dango on a skewer, warabi mochi, yōkan, dorayaki.
// kept across runs: a table, never written
let menu_icons : Array[Array[(Double, Double, Double, Double, Int64, Bool)]] = [
  [
    (19.5, 1.0, 2.0, 8.0, 0xE2B56EFFL, false),
    (9.0, 3.5, 7.0, 7.0, 0x86B95CFFL, true),
    (14.5, 4.0, 6.5, 6.5, 0xFFF3D9FFL, true),
    (14.0, 1.5, 4.0, 4.0, 0xD8303AFFL, true),
    (8.0, 9.5, 14.0, 2.6, 0x9CC96BFFL, false),
    (8.0, 12.0, 14.0, 3.0, 0xFFF1CFFFL, false),
    (8.5, 15.0, 13.0, 4.0, 0x6FA64FFFL, false),
    (10.0, 18.5, 10.0, 2.5, 0x6FA64FFFL, true),
    (14.0, 21.0, 2.0, 4.0, 0xC9B18EFFL, false),
    (10.0, 24.6, 10.0, 2.8, 0xC9B18EFFL, true),
  ],
  [
    (5.0, 14.0, 20.0, 11.0, 0x7FAE5AFFL, true),
    (5.0, 6.5, 20.0, 15.0, 0xF7B8C9FFL, true),
    (9.5, 9.5, 3.2, 3.2, 0xFFFFFF99L, true),
  ],
  [
    (4.0, 25.0, 3.0, 3.0, 0xC9A06AFFL, true),
    (23.5, 2.0, 3.0, 3.0, 0xC9A06AFFL, true),
    (5.4, 16.4, 9.2, 9.2, 0x8CC06AFFL, true),
    (10.4, 10.4, 9.2, 9.2, 0xF3EBD9FFL, true),
    (15.4, 4.4, 9.2, 9.2, 0xF6A8BFFFL, true),
  ],
  [
    (3.0, 24.5, 24.0, 1.2, 0xC9A86AFFL, true),
    (4.0, 13.0, 9.0, 9.0, 0xEAD7A6FFL, false),
    (15.0, 12.0, 10.0, 10.0, 0xEAD7A6FFL, false),
    (9.0, 5.0, 9.0, 9.0, 0xF0E0B6FFL, false),
    (7.5, 15.5, 1.2, 1.2, 0xB8894AFFL, true),
    (18.5, 14.5, 1.2, 1.2, 0xB8894AFFL, true),
    (12.5, 7.5, 1.2, 1.2, 0xB8894AFFL, true),
  ],
  [
    (5.0, 9.0, 21.0, 4.0, 0x7A2F2FFFL, false),
    (12.0, 12.0, 14.0, 10.0, 0x6B2628FFL, false),
    (5.0, 12.0, 7.0, 9.0, 0x5A1F22FFL, false),
  ],
  [
    (4.0, 14.0, 22.0, 10.0, 0xB8742EFFL, true),
    (4.5, 13.0, 21.0, 7.0, 0x6B2A2AFFL, true),
    (4.0, 8.0, 22.0, 9.5, 0xC9843AFFL, true),
    (6.0, 9.0, 18.0, 6.0, 0xA8622AFFL, true),
  ],
]

///|
let menu_ground : Int64 = 0xF3E6CFFFL

///|
let menu_art_h : Double = 240.0

///|
let menu_art_at : Double = 0.4

///|
let menu_fade : Double = 62.0

///|
/// The board rises 38 over the picture's foot.
let menu_lift : Double = 202.0

///|
let menu_brand_x : Double = 16.0

///|
let menu_brand_y : Double = 14.0

///|
let menu_hook_x : Double = 74.0

///|
let menu_hook_t : Double = 193.0

///|
let menu_hook_w : Double = 7.0

///|
let menu_hook_h : Double = 12.0

///|
let menu_open_r : Double = 12.0

///|
let menu_open_t : Double = 14.0

///|
let menu_rule_h : Double = 1.5

///|
let menu_icon_side : Double = 30.0

///|
let menu_dot_count : Int = 40

///|
let menu_sold_side : Double = 88.0

///|
/// お品書き 28 high: Xl3's 22, larger.
let menu_title_scale : Double = 1.27

///|
/// Today's sold 28 high on its 12's unit.
let menu_sold_scale : Double = 2.3

///|
let menu_unit_scale : Double = 1.0

///|
let menu_ink : Int64 = 0x3A2414FFL

///|
let menu_dark : Int64 = 0x2E1A0EFFL

///|
let menu_brown : Int64 = 0x9A6A44FFL

///|
let menu_label_ink : Int64 = 0x8A5A32FFL

///|
let menu_red : Int64 = 0xC8402EFFL

///|
let menu_price_ink : Int64 = 0xA8321FFFL

///|
let menu_tk_ink : Int64 = 0x7A5636FFL

///|
let menu_green : Int64 = 0x3F8A3AFFL

///|
let menu_pink : Int64 = 0xE0608AFFL

///|
let menu_white : Int64 = 0xFFFFFFFFL

///|
let menu_wood : Int64 = 0x9A6838FFL

///|
let menu_wood_edge : Int64 = 0x5E3A1CFFL

///|
let menu_paper : Int64 = 0xFFFAF0FFL

///|
let menu_paper_edge : Int64 = 0xE8D6B4FFL

///|
let menu_dash : Int64 = 0xC9A87EFFL

///|
let menu_stamp : Int64 = 0xC8402EE6L

///|
let menu_tag_shadow : Int64 = 0x8E2A1EFFL

///|
let menu_say_shadow : Int64 = 0xE6C8A8FFL

///|
// kept across runs: a value (no field of it changes)
let menu_brand : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Data(menu_white), wrap=false)

///|
/// The board: wood round the washi, 14 in from the card's sides.
// kept across runs: a value (no field of it changes)
let menu_board : @ui.Style = @ui.css("mx=S3_5 p=S2 radius=Lg border=B1").then(
  @ui.style(bg=Data(menu_wood), border_color=Data(menu_wood_edge)),
)

///|
// kept across runs: a value (no field of it changes)
let menu_washi : @ui.Style = @ui.css("w=Full pt=S3_5 px=S3_5 pb=S3 radius=Sm border=B1").then(
  @ui.style(bg=Data(menu_paper), border_color=Data(menu_paper_edge)),
)

///|
// kept across runs: a value (no field of it changes)
let menu_hook : @ui.Style = @ui.css("radius=Sm").then(
  @ui.style(w=Fixed(menu_hook_w), h=Fixed(menu_hook_h), bg=Data(menu_wood_edge)),
)

///|
// kept across runs: a value (no field of it changes)
let menu_title_row : @ui.Style = @ui.css("row w=Full gap=S2_5 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let menu_title : @ui.TextStyle = @ui.text_style(
  size=Xl3,
  weight=Bold,
  tracking=Wider,
  leading=L7,
  color=Data(menu_dark),
  wrap=false,
)

///|
// kept across runs: a value (no field of it changes)
let menu_sub : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(menu_brown), wrap=false)

///|
/// 营业中: white on its red tag, the tag's shadow 2 lower.
// kept across runs: a value (no field of it changes)
let menu_open_under : @ui.Style = @ui.css("pb=S0_5 radius=Sm").then(@ui.style(bg=Data(menu_tag_shadow)))

///|
// kept across runs: a value (no field of it changes)
let menu_open : @ui.Style = @ui.css("px=S2 pt=S0_5 pb=S1 radius=Sm").then(@ui.style(bg=Data(menu_red)))

///|
// kept across runs: a value (no field of it changes)
let menu_open_words : @ui.TextStyle = @ui.text_style(size=Xs, weight=Bold, tracking=@sf.share_letters_apart, color=Data(menu_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let menu_items : @ui.Style = @ui.css("w=Full mt=S2")

///|
/// A sweet: its drawing, its name over its model, the dots, its price over its tokens; 6 over and under.
// kept across runs: a value (no field of it changes)
let menu_item : @ui.Style = @ui.css("row w=Full gap=S2 py=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let menu_icon_box : @ui.Style = @ui.style(w=Fixed(menu_icon_side), h=Fixed(menu_icon_side))

///|
// kept across runs: a value (no field of it changes)
let menu_name_col : @ui.Style = @ui.css("gap=SPx")

///|
// kept across runs: a value (no field of it changes)
let menu_name_row : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let menu_name : @ui.TextStyle = @ui.text_style(
  size=Xl,
  weight=Bold,
  leading=L6,
  color=Data(menu_dark),
  wrap=false,
)

///|
// kept across runs: a value (no field of it changes)
let menu_hot : @ui.Style = @ui.css("px=S1 radius=Sm").then(@ui.style(bg=Data(menu_red)))

///|
// kept across runs: a value (no field of it changes)
let menu_hot_words : @ui.TextStyle = @ui.text_style(size=Xs3, weight=Bold, color=Data(menu_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let menu_model : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(menu_brown), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let menu_dots : @ui.Style = @ui.css("row gap=S0_5 mx=S0_5 mt=S2 clip").then(@ui.style(w=@sf.grow))

///|
// kept across runs: a value (no field of it changes)
let menu_dot : @ui.Style = @ui.css("w=S0_5 h=S0_5 radius=Full").then(@ui.style(bg=Data(menu_dash)))

///|
// kept across runs: a value (no field of it changes)
let menu_price : @ui.Style = @ui.css("align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let menu_cost : @ui.TextStyle = @ui.text_style(
  size=Xl,
  weight=Bold,
  leading=L6,
  color=Data(menu_price_ink),
  wrap=false,
)

///|
// kept across runs: a value (no field of it changes)
let menu_cost_top : @ui.TextStyle = @ui.text_style(
  size=Xl3,
  weight=Bold,
  leading=L6,
  color=Data(menu_price_ink),
  wrap=false,
)

///|
// kept across runs: a value (no field of it changes)
let menu_tokens : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(menu_tk_ink))

///|
/// 本日售出's stamp beside the week's takings.
// kept across runs: a value (no field of it changes)
let menu_tally : @ui.Style = @ui.css("row w=Full gap=S3 mt=S2 pt=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let menu_sold : @ui.Style = @ui.css("radius=Full border=B2 p=S0_5").then(
  @ui.style(w=Fixed(menu_sold_side), h=Fixed(menu_sold_side), border_color=Data(menu_stamp)),
)

///|
// kept across runs: a value (no field of it changes)
let menu_sold_in : @ui.Style = @ui.css("w=Full h=Full radius=Full border=B1 align=ACenter justify=JCenter").then(
  @ui.style(border_color=Data(menu_stamp)),
)

///|
// kept across runs: a value (no field of it changes)
let menu_sold_words : @ui.TextStyle = @ui.text_style(size=Xs2, tracking=@sf.share_letters_apart, color=Data(menu_stamp), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let menu_sold_count : @ui.TextStyle = @ui.text_style(size=Xs, leading=L7, color=Data(menu_stamp), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let menu_rev : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let menu_rev_label : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(menu_label_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let menu_rev_value : @ui.TextStyle = @ui.text_style(size=Xl4, weight=Bold, color=Data(menu_dark), wrap=false)

///|
/// What she says: on white, round, its shadow 4 lower; 16 in from the card's sides.
// kept across runs: a value (no field of it changes)
let menu_say_under : @ui.Style = @ui.css("mx=S3_5 mt=S4 pb=S1 radius=Xl2").then(@ui.style(bg=Data(menu_say_shadow)))

///|
// kept across runs: a value (no field of it changes)
let menu_say : @ui.Style = @ui.css("w=Full px=S3_5 pt=S3 pb=S3 radius=Xl2").then(@ui.style(bg=Data(menu_white)))

///|
// kept across runs: a value (no field of it changes)
let menu_who : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(menu_pink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let menu_say_words : @ui.TextStyle = @ui.text_style(size=Lg, leading=L6, color=Data(menu_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let menu_note : @ui.Style = @ui.css("w=Full px=S5 pt=S2")

///|
// kept across runs: a value (no field of it changes)
let menu_note_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(menu_label_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let menu_foot : @ui.Style = @ui.css("row w=Full px=S5 pt=S3 pb=S4 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let menu_foot_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(menu_brown), wrap=false)

// ── 芦花 · 大福帐 ────────────────────────────────────────────────────────────

///|
/// 芦花's: the shop owner's account book (大福帐). Her picture (at the counter with abacus and ledger), falling into the
/// shop's wine; on the cream paper bound along its top, the title and the week, a line a day of the chats archived
/// counted in 正 (five strokes a five) and in figures (today in red), the week's takings with a soroban set to them,
/// the top regular (the top model), today's and the guests in the shop (at work); what she says, still.fail's line.
fn sr_ledger(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = sr_args(fleet)
  let days = sr_days(fleet)
  let range = match days {
    [first, .., last] => first.0 + " – " + last.0
    _ => ""
  }
  let figure = fn(v : String, scale : Double) { hero_hi(v, led_ink, scale~) }
  sr_box(c, id, flat, led_ground, fn() {
    hero_top(c, "a6-roka-ledger", led_art_h, led_art_at, led_ground, led_fade)
    c.box(left=led_brand_x, top=led_brand_y, fn() { sr_brand(c, led_brand) }) |> ignore
    hero_gap(c, led_lift)
    c.box(style=led_book, fn() {
      c.box(style=led_bind, left=hero_zero, right=hero_zero, top=hero_zero, fn() {  }) |> ignore
      c.box(style=led_head, fn() {
        sr_words(c, hero_t("ledger.title"), led_title)
        c.box(style=hero_grow, fn() {  }) |> ignore
        c.box(style=led_side, fn() {
          sr_words(c, hero_t("ledger.sub"), led_sub)
          sr_words(c, range, led_range)
        })
        |> ignore
      })
      |> ignore
      // the table: its heads, a line a day
      c.box(style=led_table, fn() {
        c.box(style=led_heads, fn() {
          c.box(style=led_date, fn() { sr_words(c, hero_t("ledger.date"), led_head_words) }) |> ignore
          c.box(style=led_vline, fn() {  }) |> ignore
          c.box(style=led_marks, fn() { sr_words(c, hero_t("ledger.chats"), led_head_words) }) |> ignore
          c.box(style=led_vline, fn() {  }) |> ignore
          c.box(style=led_count, fn() { sr_words(c, hero_t("ledger.sum"), led_head_words) }) |> ignore
        })
        |> ignore
        hero_rule(c, led_red_rule, led_rule_h)
        for d in days {
          let today = d.4
          c.box(style=if today { led_day_today } else { led_day }, fn() {
            c.box(style=led_date, fn() {
              sr_words(c, if today { hero_t("ledger.today") } else { d.0 }, if today { led_date_today } else { led_date_words })
            })
            |> ignore
            c.box(style=led_vline, fn() {  }) |> ignore
            c.box(style=led_marks, fn() {
              c.box(style=led_tally, fn() {
                let n = @string.parse_int(d.2) catch { _ => 0 }
                let mut left = if n > led_tally_most * led_five { led_tally_most * led_five } else { n }
                while left > 0 {
                  led_glyph(c, if left > led_five { led_five } else { left })
                  left = left - led_five
                }
              })
              |> ignore
            })
            |> ignore
            c.box(style=led_vline, fn() {  }) |> ignore
            c.box(style=led_count, fn() {
              sr_rich(
                c,
                hero_said("ledger.count", [], [("count", hero_hi(d.2, if today { led_red } else { led_ink }))], scale=led_unit_scale),
                if today { led_count_today } else { led_count_words },
              )
            })
            |> ignore
          })
          |> ignore
          hero_rule(c, led_row_rule, led_hair)
        }
      })
      |> ignore
      c.box(style=led_sum, fn() {
        c.box(style=led_big, fn() {
          sr_words(c, hero_t("ledger.rev"), led_label)
          c.box(style=led_under, fn() {
            sr_words(c, sr_arg(args, "weekCost"), led_total)
            hero_rule(c, led_red_rule, led_hair)
            hero_rule(c, led_red_rule, led_hair)
          })
          |> ignore
        })
        |> ignore
        led_soroban(c, sr_arg(args, "weekCost"))
      })
      |> ignore
      c.box(style=led_vip, fn() {
        c.box(style=led_vip_tag, fn() { sr_words(c, hero_t("ledger.vip"), led_vip_tag_words) }) |> ignore
        sr_words(c, sr_arg(args, "model"), led_vip_words)
        c.box(style=hero_grow, fn() {  }) |> ignore
        sr_rich(
          c,
          hero_said("ledger.vipLine", [], [
            ("tokens", figure(sr_arg(args, "tokens"), led_vip_scale)),
            ("cost", figure(sr_arg(args, "cost"), led_vip_scale)),
          ]),
          led_vip_words,
        )
      })
      |> ignore
      hero_rule(c, led_row_rule, led_hair)
      c.box(style=led_minis, fn() {
        c.box(style=led_mini, fn() {
          sr_rich(c, hero_said("ledger.todayCost", [], [("cost", figure(sr_arg(args, "todayCost"), led_mini_scale))]), led_mini_words)
        })
        |> ignore
        c.box(style=led_mini, fn() {
          sr_rich(c, hero_said("ledger.guests", [], [("chats", figure(sr_arg(args, "chats"), led_mini_scale))]), led_mini_words)
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    // the binding's thread over the book's top
    for x in led_threads {
      c.box(style=led_thread, left=x, top=led_thread_t, fn() {  }) |> ignore
    }
    c.box(style=led_say_under, fn() {
      c.box(style=led_say, fn() {
        let who = @ui.span(" " + hero_t("ledger.who") + " ", color=led_white, bg=led_who_bg, scale=led_who_scale)
        sr_rich(c, [who, @ui.span(" " + hero_t("ledger.say"))], led_say_words)
        sr_rich(c, hero_said("ledger.say2", [], [("love", @ui.span(hero_t("ledger.love"), color=led_red))]), led_say_words)
      })
      |> ignore
    })
    |> ignore
    hero_foot(c, fleet, led_foot, led_foot_words)
  })
}

///|
/// 正 written to its `k`th stroke (一, 丅, 下, 止, 正), 18 square.
fn led_glyph(c : @ui.Ctx, k : Int) -> Unit {
  c.box(style=led_glyph_box, fn() {
    for i in 0..<k {
      let (x, y, wide, high) = led_strokes[i]
      c.box(style=@ui.style(w=Fixed(wide), h=Fixed(high), bg=Data(led_stroke_ink), radius=Sm), left=x, top=y, fn() {  })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A small soroban with `cost`'s figures set on its six rods (the last six: a bead over the bar five, each under it
/// one), its frame round it.
fn led_soroban(c : @ui.Ctx, cost : String) -> Unit {
  let digits : Array[Int] = []
  for ch in cost {
    if ch >= '0' && ch <= '9' {
      digits.push(ch.to_int() - '0'.to_int())
    }
  }
  while digits.length() < led_rods {
    digits.insert(0, 0)
  }
  let set = digits[digits.length() - led_rods:].to_owned()
  c.box(style=led_soro, fn() {
    c.box(style=led_soro_in, left=led_soro_edge, top=led_soro_edge, fn() {  }) |> ignore
    for i, v in set {
      let x = led_rod_x + i.to_double() * led_rod_gap
      c.box(style=led_rod, left=x - led_hair / 2.0, top=led_soro_edge, fn() {  }) |> ignore
      let five = v >= led_five
      led_bead(c, x, if five { led_heaven_on } else { led_heaven_off }, five)
      let ones = v % led_five
      for j in 0..<4 {
        if j < ones {
          led_bead(c, x, led_earth_on + j.to_double() * led_bead_step, true)
        } else {
          led_bead(c, x, led_earth_off - (3 - j).to_double() * led_bead_step, false)
        }
      }
    }
    c.box(style=led_bar, left=led_soro_edge, top=led_bar_t, fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// A bead at (`x`, `y`), its middle: dark where it counts.
fn led_bead(c : @ui.Ctx, x : Double, y : Double, on : Bool) -> Unit {
  c.box(style=if on { led_bead_on } else { led_bead_off }, left=x - led_bead_w / 2.0, top=y - led_bead_h / 2.0, fn() {  })
  |> ignore
}

///|
/// 正's strokes in the order written: the top, the middle down, its short right, the short left down, the foot (left,
/// top, width, height in an 18 square).
// kept across runs: a table, never written
let led_strokes : Array[(Double, Double, Double, Double)] = [
  (3.0, 2.2, 12.0, 2.1),
  (8.1, 3.0, 2.1, 12.4),
  (9.2, 8.1, 4.8, 2.1),
  (3.7, 9.6, 2.1, 5.8),
  (2.2, 14.5, 13.6, 2.1),
]

///|
/// The binding's thread: where, from the card's left (at 18%, 39%, 61%, 82% of the book).
// kept across runs: a table, never written
let led_threads : Array[Double] = [73.0, 142.0, 214.0, 283.0]

///|
let led_ground : Int64 = 0x3A1E22FFL

///|
let led_art_h : Double = 240.0

///|
let led_art_at : Double = 0.4

///|
let led_fade : Double = 66.0

///|
/// The book rises 40 over the picture's foot.
let led_lift : Double = 200.0

///|
let led_brand_x : Double = 16.0

///|
let led_brand_y : Double = 14.0

///|
let led_thread_t : Double = 197.0

///|
let led_thread_w : Double = 3.0

///|
let led_thread_h : Double = 13.0

///|
let led_bind_h : Double = 12.0

///|
let led_rule_h : Double = 1.5

///|
let led_hair : Double = 1.0

///|
let led_row_h : Double = 28.0

///|
let led_col_w : Double = 54.0

///|
let led_glyph_side : Double = 18.0

///|
let led_five : Int = 5

///|
/// The most 正 a day's row holds (its marks 178 across, a 正 20 with the gap after it): a day of more fills the row and
/// stops there, its count beside it saying how many (a real week had 64 in one day, 2026-11-03, past the row's end).
let led_tally_most : Int = 8

///|
let led_unit_scale : Double = 0.75

///|
let led_vip_scale : Double = 1.15

///|
let led_mini_scale : Double = 1.4

///|
let led_who_scale : Double = 0.86

///|
let led_soro_w : Double = 104.0

///|
let led_soro_h : Double = 60.0

///|
let led_soro_edge : Double = 4.0

///|
let led_rods : Int = 6

///|
let led_rod_x : Double = 13.0

///|
let led_rod_gap : Double = 15.6

///|
let led_rod_h : Double = 52.0

///|
let led_bar_t : Double = 16.0

///|
let led_bar_h : Double = 2.6

///|
let led_bar_w : Double = 96.0

///|
let led_bead_w : Double = 12.0

///|
let led_bead_h : Double = 6.0

///|
let led_bead_step : Double = 6.2

///|
let led_heaven_on : Double = 12.6

///|
let led_heaven_off : Double = 7.4

///|
let led_earth_on : Double = 21.8

///|
let led_earth_off : Double = 52.8

///|
let led_ink : Int64 = 0x1F1410FFL

///|
let led_red : Int64 = 0xB0303AFFL

///|
let led_paper : Int64 = 0xF8F0DCFFL

///|
let led_paper_edge : Int64 = 0xE2D2AEFFL

///|
let led_bind_ink : Int64 = 0xEEE2C4FFL

///|
let led_bind_edge : Int64 = 0xD9C49AFFL

///|
let led_thread_ink : Int64 = 0x7A2A32FFL

///|
let led_brown : Int64 = 0x8A5A4AFFL

///|
let led_range_ink : Int64 = 0xA3343CFFL

///|
let led_red_rule : Int64 = 0xC0404AFFL

///|
let led_row_rule : Int64 = 0xD0606A66L

///|
let led_col_rule : Int64 = 0xD0606A88L

///|
let led_today_bg : Int64 = 0xF6D9D633L

///|
let led_date_ink : Int64 = 0x4A2E24FFL

///|
let led_unit_ink : Int64 = 0x7A5A4AFFL

///|
let led_stroke_ink : Int64 = 0x241712FFL

///|
let led_frame : Int64 = 0x5E3A22FFL

///|
let led_frame_in : Int64 = 0xEFE2C4FFL

///|
let led_rod_ink : Int64 = 0x7A5A3AFFL

///|
let led_bead_on_ink : Int64 = 0x7A2A32FFL

///|
let led_bead_off_ink : Int64 = 0xA07A5AFFL

///|
let led_say_bg : Int64 = 0xFBF4F2FFL

///|
let led_say_shadow : Int64 = 0x7A3A42FFL

///|
let led_who_bg : Int64 = 0x8A2A3AFFL

///|
let led_say_ink : Int64 = 0x2A1A14FFL

///|
let led_foot_ink : Int64 = 0xC9A0A4FFL

///|
let led_white : Int64 = 0xFFFFFFFFL

///|
// kept across runs: a value (no field of it changes)
let led_brand : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Data(led_white), wrap=false)

///|
/// The book: cream paper, 16 in from the card's sides, its binding along its top.
// kept across runs: a value (no field of it changes)
let led_book : @ui.Style = @ui.css("mx=S4 pt=S5 px=S3_5 pb=S3_5 radius=Sm border=B1").then(
  @ui.style(bg=Data(led_paper), border_color=Data(led_paper_edge)),
)

///|
// kept across runs: a value (no field of it changes)
let led_bind : @ui.Style = @ui.css("border=B1").then(
  @ui.style(h=Fixed(led_bind_h), bg=Data(led_bind_ink), border_color=Data(led_bind_edge)),
)

///|
// kept across runs: a value (no field of it changes)
let led_thread : @ui.Style = @ui.css("radius=Sm").then(
  @ui.style(w=Fixed(led_thread_w), h=Fixed(led_thread_h), bg=Data(led_thread_ink)),
)

///|
// kept across runs: a value (no field of it changes)
let led_head : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let led_title : @ui.TextStyle = @ui.text_style(
  size=Xl4,
  weight=Bold,
  tracking=Wider,
  leading=L9,
  color=Data(led_ink),
  wrap=false,
)

///|
// kept across runs: a value (no field of it changes)
let led_side : @ui.Style = @ui.css("align=AEnd gap=SPx")

///|
// kept across runs: a value (no field of it changes)
let led_sub : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(led_brown), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let led_range : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(led_range_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let led_table : @ui.Style = @ui.css("w=Full mt=S2")

///|
// kept across runs: a value (no field of it changes)
let led_heads : @ui.Style = @ui.css("row w=Full pb=S0_5 align=AStretch")

///|
// kept across runs: a value (no field of it changes)
let led_head_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(led_red), wrap=false)

///|
/// A day's line: its date, its 正s, its count, ruled apart.
// kept across runs: a value (no field of it changes)
let led_day : @ui.Style = @ui.css("row w=Full align=AStretch").then(@ui.style(h=Fixed(led_row_h)))

///|
// kept across runs: a value (no field of it changes)
let led_day_today : @ui.Style = led_day.then(@ui.style(bg=Data(led_today_bg)))

///|
// kept across runs: a value (no field of it changes)
let led_date : @ui.Style = @ui.css("px=S1_5 justify=JCenter").then(@ui.style(w=Fixed(led_col_w)))

///|
// kept across runs: a value (no field of it changes)
let led_marks : @ui.Style = @ui.css("px=S1_5 justify=JCenter").then(@ui.style(w=@sf.grow))

///|
// kept across runs: a value (no field of it changes)
let led_count : @ui.Style = @ui.css("px=S1_5 justify=JCenter align=AEnd").then(@ui.style(w=Fixed(led_col_w)))

///|
// kept across runs: a value (no field of it changes)
let led_vline : @ui.Style = @ui.css("w=SPx").then(@ui.style(bg=Data(led_col_rule)))

///|
// kept across runs: a value (no field of it changes)
let led_date_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(led_date_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let led_date_today : @ui.TextStyle = led_date_words.then(@ui.text_style(color=Data(led_red)))

///|
// kept across runs: a value (no field of it changes)
let led_tally : @ui.Style = @ui.css("row gap=S0_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let led_glyph_box : @ui.Style = @ui.style(w=Fixed(led_glyph_side), h=Fixed(led_glyph_side))

///|
// kept across runs: a value (no field of it changes)
let led_count_words : @ui.TextStyle = @ui.text_style(size=Lg, weight=Bold, color=Data(led_unit_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let led_count_today : @ui.TextStyle = led_count_words.then(@ui.text_style(color=Data(led_red)))

///|
/// The week's takings beside the soroban, at their feet.
// kept across runs: a value (no field of it changes)
let led_sum : @ui.Style = @ui.css("row w=Full gap=S2_5 mt=S2 pt=S1 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let led_big : @ui.Style = @ui.css("align=AStart").then(@ui.style(w=@sf.grow))

///|
// kept across runs: a value (no field of it changes)
let led_label : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(led_brown), wrap=false)

///|
/// The takings over their double red rule, as wide as they are.
// kept across runs: a value (no field of it changes)
let led_under : @ui.Style = @ui.css("gap=SPx pb=S0_5")

///|
// kept across runs: a value (no field of it changes)
let led_total : @ui.TextStyle = @ui.text_style(size=Xl4, weight=Bold, color=Data(led_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let led_soro : @ui.Style = @ui.css("radius=Base").then(
  @ui.style(w=Fixed(led_soro_w), h=Fixed(led_soro_h), bg=Data(led_frame)),
)

///|
// kept across runs: a value (no field of it changes)
let led_soro_in : @ui.Style = @ui.css("radius=Sm").then(
  @ui.style(w=Fixed(led_bar_w), h=Fixed(led_rod_h), bg=Data(led_frame_in)),
)

///|
// kept across runs: a value (no field of it changes)
let led_rod : @ui.Style = @ui.style(w=Fixed(led_hair), h=Fixed(led_rod_h), bg=Data(led_rod_ink))

///|
// kept across runs: a value (no field of it changes)
let led_bar : @ui.Style = @ui.style(w=Fixed(led_bar_w), h=Fixed(led_bar_h), bg=Data(led_frame))

///|
// kept across runs: a value (no field of it changes)
let led_bead_on : @ui.Style = @ui.css("radius=Full").then(
  @ui.style(w=Fixed(led_bead_w), h=Fixed(led_bead_h), bg=Data(led_bead_on_ink)),
)

///|
// kept across runs: a value (no field of it changes)
let led_bead_off : @ui.Style = led_bead_on.then(@ui.style(bg=Data(led_bead_off_ink)))

///|
/// The top regular: its tag, the model, its tokens and cost at the line's end.
// kept across runs: a value (no field of it changes)
let led_vip : @ui.Style = @ui.css("row w=Full gap=S1_5 mt=S2 pt=S0_5 px=S0_5 pb=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let led_vip_tag : @ui.Style = @ui.css("px=S1_25 radius=Sm").then(@ui.style(bg=Data(led_range_ink)))

///|
// kept across runs: a value (no field of it changes)
let led_vip_tag_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(led_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let led_vip_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(led_date_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let led_minis : @ui.Style = @ui.css("row w=Full gap=S1_5 mt=S2")

///|
// kept across runs: a value (no field of it changes)
let led_mini : @ui.Style = @ui.css("px=S2 pt=S1_5 pb=S2 radius=Base border=B1").then(
  @ui.style(w=@sf.grow, border_color=Data(led_col_rule)),
)

///|
// kept across runs: a value (no field of it changes)
let led_mini_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(led_brown), wrap=false)

///|
/// What she says: on blush paper, round, its wine shadow 4 lower; 16 in from the card's sides.
// kept across runs: a value (no field of it changes)
let led_say_under : @ui.Style = @ui.css("mx=S4 mt=S4 pb=S1 radius=Xl2").then(@ui.style(bg=Data(led_say_shadow)))

///|
// kept across runs: a value (no field of it changes)
let led_say : @ui.Style = @ui.css("w=Full px=S3_5 pt=S3 pb=S3 radius=Xl2").then(@ui.style(bg=Data(led_say_bg)))

///|
// kept across runs: a value (no field of it changes)
let led_say_words : @ui.TextStyle = @ui.text_style(size=Base, leading=L6, color=Data(led_say_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let led_foot : @ui.Style = @ui.css("row w=Full px=S5 pt=S3_5 pb=S3_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let led_foot_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(led_foot_ink), wrap=false)

// ── 芦花 · 夜樱 (her shop at night) ─────────────────────────────────────────

///|
/// 芦花's shop at night: her picture at the counter, falling into the night at its foot; the shop's sign (open late),
/// still.fail across from it; under her, when as the shop says it (深夜, 夜里), the guests still in (the chats at work)
/// large, the week's takings and today's, what was ordered most (the top model), and what she says; still.fail's line
/// and 大人の時間 at the foot.
fn sr_night(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = sr_args(fleet)
  let at = sr_arg(args, "at")
  // (when: its last word the clock, before it the day; the hour the clock's first figure)
  let parts : Array[String] = at.split(" ").map(fn(w) { w.to_owned() }).collect()
  let clock = if parts.length() > 0 { parts[parts.length() - 1] } else { "" }
  let day = hero_but_last(parts)
  let hour = @string.parse_int(sr_num(clock)) catch { _ => -1 }
  let night = hour >= nite_evening || (hour >= 0 && hour < nite_dawn)
  let when = if hour >= nite_late || (hour >= 0 && hour < nite_dawn) {
    hero_t("night.late")
  } else if night {
    hero_t("night.eve")
  } else {
    hero_t("night.day")
  }
  let hi = fn(name : String) -> (String, @ui.Run) { (name, hero_hi(sr_arg(args, name), nite_white, scale=nite_hi_scale)) }
  sr_box(c, id, flat, nite_ground, fn() {
    sr_art(c, "f1-roka-night", @sf.share_w_most, nite_art_h, at=nite_art_at) |> ignore
    hero_gap(c, nite_rest_h)
    c.box(left=hero_zero, right=hero_zero, top=nite_shade_top, fn() { hero_fade(c, nite_ground, nite_shade_h, nite_shade) })
    |> ignore
    c.box(style=nite_sign, left=nite_edge, top=nite_edge, fn() {
      c.box(style=nite_dot, fn() {  }) |> ignore
      sr_words(c, hero_t("night.sign"), nite_sign_words)
      sr_words(c, hero_t("night.open"), nite_sign_open)
    })
    |> ignore
    c.box(right=nite_brand_r, top=nite_brand_t, fn() { sr_brand(c, nite_brand) }) |> ignore
    c.box(style=nite_panel, left=nite_x, right=nite_panel_r, top=nite_panel_t, fn() {
      sr_words(c, when + " " + clock + (if day != "" { " · " + day } else { "" }), nite_kick)
      let big = if night { "night.big" } else { "night.bigDay" }
      sr_rich(
        c,
        hero_said(big, [], [("chats", hero_hi(sr_arg(args, "chats"), nite_amber, scale=nite_big_scale))], scale=nite_big_words),
        nite_big,
      )
      c.box(style=nite_rows, fn() {
        sr_rich(c, hero_said("night.rev", [], [hi("weekCost"), hi("todayCost")]), nite_row)
        sr_rich(c, hero_said("night.top", [("model", sr_arg(args, "model"))], [hi("tokens"), hi("cost")]), nite_row)
      })
      |> ignore
      c.box(style=nite_say, fn() {
        c.box(style=nite_bar, fn() {  }) |> ignore
        c.box(style=nite_say_words, fn() {
          sr_words(c, hero_t("night.who"), nite_who)
          sr_words(c, hero_t("night.say", args=[("chats", sr_arg(args, "chats"))]), nite_line)
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    c.box(style=nite_foot, left=nite_x, right=nite_x, bottom=nite_foot_b, fn() {
      c.box(style=hero_grow, fn() { sr_words(c, @sf.t("web-main.stations.shareTagline"), nite_small) }) |> ignore
      sr_words(c, hero_t("night.adult"), nite_small)
    })
    |> ignore
  })
}

///|
let nite_ground : Int64 = 0x1B0F12FFL

///|
let nite_art_h : Double = 540.0

///|
let nite_art_at : Double = 0.08

///|
/// The card under the picture: 704 in all.
let nite_rest_h : Double = 164.0

///|
let nite_shade_top : Double = 360.0

///|
let nite_shade_h : Double = 344.0

///|
// kept across runs: a table, never written
let nite_shade : Array[(Double, Double)] = [(0.0, 0.0), (0.34, 0.85), (0.56, 1.0), (1.0, 1.0)]

///|
/// From 18 the shop says 夜里 (今晚: tonight), from 22 深夜, till 5.
let nite_evening : Int = 18

///|
let nite_late : Int = 22

///|
let nite_dawn : Int = 5

///|
let nite_edge : Double = 14.0

///|
let nite_brand_r : Double = 16.0

///|
let nite_brand_t : Double = 18.0

///|
let nite_x : Double = 20.0

///|
/// The words a little nearer the card's right edge than its left (the top model's line, its cost too, on one line).
let nite_panel_r : Double = 16.0

///|
let nite_panel_t : Double = 458.0

///|
let nite_foot_b : Double = 14.0

///|
let nite_hi_scale : Double = 1.1

///|
let nite_big_scale : Double = 1.28

///|
/// The guests' line a little over Xl3 (27 to its 22), its number larger again (34).
let nite_big_words : Double = 1.2

///|
let nite_white : Int64 = 0xFFFFFFFFL

///|
let nite_amber : Int64 = 0xFFB35AFFL

///|
let nite_sign_bg : Int64 = 0x32190FF2L

///|
let nite_sign_edge : Int64 = 0xC98B4F88L

///|
let nite_sign_ink : Int64 = 0xFFE2B8FFL

///|
let nite_kick_ink : Int64 = 0xE8A882FFL

///|
let nite_row_ink : Int64 = 0xF1DCCFFFL

///|
let nite_foot_ink : Int64 = 0xA88A7EFFL

///|
// kept across runs: a value (no field of it changes)
let nite_sign : @ui.Style = @ui.css("row px=S3 pt=S1_5 pb=S2 radius=Md border=B1 gap=S1_5 align=ACenter").then(
  @ui.style(bg=Data(nite_sign_bg), border_color=Data(nite_sign_edge)),
)

///|
// kept across runs: a value (no field of it changes)
let nite_dot : @ui.Style = @ui.css("w=S2 h=S2 radius=Full").then(@ui.style(bg=Data(nite_amber)))

///|
// kept across runs: a value (no field of it changes)
let nite_sign_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(nite_sign_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let nite_sign_open : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(nite_amber), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let nite_brand : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Data(nite_white), wrap=false)

///|
/// Under her: when, the guests, the figures, what she says.
// kept across runs: a value (no field of it changes)
let nite_panel : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let nite_kick : @ui.TextStyle = @ui.text_style(size=Xs, tracking=Widest, color=Data(nite_kick_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let nite_big : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Bold, tracking=@sf.share_letters_apart, color=Data(nite_white), w=Full)

///|
// kept across runs: a value (no field of it changes)
let nite_rows : @ui.Style = @ui.css("w=Full gap=S1_25 pt=S2")

///|
// kept across runs: a value (no field of it changes)
let nite_row : @ui.TextStyle = @ui.text_style(size=Base, color=Data(nite_row_ink), w=Full)

///|
/// What she says: an amber bar down its start, 12 from her words.
// kept across runs: a value (no field of it changes)
let nite_say : @ui.Style = @ui.css("row w=Full gap=S3 pt=S3 pr=S1 align=AStretch")

///|
// kept across runs: a value (no field of it changes)
let nite_bar : @ui.Style = @ui.css("w=S0_5").then(@ui.style(bg=Data(nite_amber)))

///|
// kept across runs: a value (no field of it changes)
let nite_say_words : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let nite_who : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(nite_kick_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let nite_line : @ui.TextStyle = @ui.text_style(size=Lg, leading=L6, color=Data(nite_white), w=Full)

///|
// kept across runs: a value (no field of it changes)
let nite_foot : @ui.Style = @ui.css("row w=Full align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let nite_small : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(nite_foot_ink), wrap=false)
