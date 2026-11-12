// 千恋＊万花's looks (share_senren.mbt): 穗织画报's covers, each heroine whole, a magazine's masthead over her. One
// drawing, its heroine's picture, colours and words from her line of a table (gh_covers), as the mockups draw each
// cover from a heroine's config (senren/cards/gahou.js).

// ── 穗织画报 ──────────────────────────────────────────────────────────────

///|
/// A cover's heroine: her picture; her colours (`ink` the masthead's and the figures', `deep` the shades'); how far her
/// picture is moved down (`drop`: her face out from under the masthead) and the sky over it then (`sky`: the ground the
/// picture's top fades into); where the cover lines start (`lines_top`); her words' keys under shareSenren.: her name
/// and title's (`who`), her line's and her issue's (`own`), and the cover lines between the feature and the live one
/// (what each is, what it says).
priv struct SrCover {
  look : String
  art : String
  ink : Int64
  deep : Int64
  sky : Int64
  drop : Double
  lines_top : Double
  who : String
  own : String
  lines : Array[(String, String)]
}

///|
/// The covers, each heroine's (the mockups' gahou-<who>.html).
// kept across runs: a table, never written
let gh_covers : Array[SrCover] = [
  {
    look: "senren-gahou-murasame",
    art: "e1-murasame-beauty",
    ink: 0xA8F0CFFFL,
    deep: 0x0D1428FFL,
    sky: 0x0D1428FFL,
    drop: 0.0,
    lines_top: gh_lines_top,
    who: "gahou-murasame",
    own: "gahou-murasame",
    lines: [("gahou-murasame.k1", "gahou-murasame.v1"), ("gahou.data", "gahou-murasame.v2")],
  },
  {
    look: "senren-gahou-mako",
    art: "e4-mako-beauty",
    ink: 0xFF8F8FFFL,
    deep: 0x0B1022FFL,
    sky: 0x141634FFL,
    drop: 44.0,
    lines_top: gh_lines_top,
    who: "gahou-mako",
    own: "gahou-mako",
    lines: [("gahou-mako.k1", "gahou-mako.v1"), ("gahou.data", "gahou-mako.v2")],
  },
  {
    look: "senren-gahou-lena",
    art: "e3-lena-beauty",
    ink: 0xFFD36BFFL,
    deep: 0x140B26FFL,
    sky: 0x140B26FFL,
    drop: 0.0,
    lines_top: gh_lines_top,
    who: "gahou-lena",
    own: "gahou-lena",
    lines: [("gahou-lena.k1", "gahou-lena.v1"), ("gahou-lena.k2", "gahou-lena.v2")],
  },
  {
    look: "senren-gahou-roka",
    art: "e2-roka-beauty",
    ink: 0xFFB0C8FFL,
    deep: 0x120A1AFFL,
    sky: 0x1A1630FFL,
    drop: 96.0,
    lines_top: gh_lines_top,
    who: "gahou-roka",
    own: "gahou-roka",
    lines: [("gahou-roka.k1", "gahou-roka.v1"), ("gahou.data", "gahou-roka.v2")],
  },
  {
    look: "senren-gahou-koharu",
    art: "e5-koharu-beauty",
    ink: 0xFFB3D9FFL,
    deep: 0x1A0D1CFFL,
    sky: 0x241A33FFL,
    drop: 64.0,
    lines_top: gh_lines_top,
    who: "gahou-koharu",
    own: "gahou-koharu",
    lines: [("gahou-koharu.k1", "gahou-koharu.v1"), ("gahou.data", "gahou-koharu.v2")],
  },
  {
    look: "senren-gahou-roka2",
    art: "f2-roka-cover",
    ink: 0xFFC58FFFL,
    deep: 0x1A0E14FFL,
    sky: 0x2B1D1CFFL,
    drop: 70.0,
    lines_top: gh_lines_top,
    who: "gahou-roka",
    own: "gahou-roka2",
    lines: [("gahou-roka2.k1", "gahou-roka2.v1"), ("gahou.data", "gahou-roka.v2")],
  },
]

///|
/// 穗织画报: a magazine's cover. The heroine's picture over all of it (moved down where her face would be under the
/// masthead, its top faded into the sky over it); shades of her deep colour at its top, its foot, and behind the cover
/// lines down its left; the masthead (its issue the week's chats archived); the cover lines (the feature: the top
/// model's tokens; two of hers; the chats at work now); her name, her title and her line; at the foot a barcode made of
/// what it says, still.fail and its line, and the week's spend its price.
fn sr_gahou(c : @ui.Ctx, look : String, fleet : Json?, id : Int, flat : Bool) -> Int {
  let g = match gh_covers.iter().find_first(fn(x) { x.look == look }) {
    Some(g) => g
    None => gh_covers[0]
  }
  let args = gh_args(fleet)
  let w = @sf.share_w_most
  let ink = @ui.text_style(color=Data(g.ink))
  let name = gh_t(g.who + ".name", [])
  sr_box(c, id, flat, g.sky, fn() {
    c.box(style=gh_frame, fn() {
      c.box(top=g.drop, left=0.0, fn() { sr_art(c, g.art, w, gh_h, at=0.0) |> ignore }) |> ignore
      if g.drop > 0.0 {
        gh_shade(c, "sky", g.sky, w, gh_sky_h, g.drop, 0.0, fn(_, y) { 1.0 - y })
      }
      gh_shade(c, "top", g.deep, w, gh_top_h, 0.0, 0.0, fn(_, y) { gh_top_most * (1.0 - y) })
      gh_shade(c, "foot", g.deep, w, gh_foot_h, gh_h - gh_foot_h, 0.0, fn(_, y) {
        if y < gh_foot_full {
          y / gh_foot_full
        } else {
          1.0
        }
      })
      gh_shade(c, "side", g.deep, gh_side_w, gh_side_h, g.lines_top - gh_side_over, 0.0, fn(x, y) {
        let fade = if y < gh_side_fade {
          y / gh_side_fade
        } else if y > 1.0 - gh_side_fade {
          (1.0 - y) / gh_side_fade
        } else {
          1.0
        }
        gh_side_most * (1.0 - x) * fade
      })
      // the masthead
      c.box(style=gh_mast, top=gh_mast_top, left=gh_edge, right=gh_edge, fn() {
        let small = gh_en.then(@ui.text_style(color=Data(gh_dim(g.ink))))
        c.box(style=gh_row, fn() {
          sr_words(c, gh_spaced(gh_t("gahou.en", [])), small)
          c.box(style=gh_grow, fn() {  }) |> ignore
          sr_words(c, gh_spaced(gh_t("gahou.en2", [])), small)
        })
        |> ignore
        // (as tall as its size, as the mockup's line: its face reaches past that, which a browser shares out above
        // and below and mbui leaves below, so it is lifted by half of it)
        c.box(style=gh_title_box, ty=-gh_title_lift, fn() { sr_words(c, gh_t("gahou.title", []), gh_title.then(ink)) })
        |> ignore
        c.box(style=gh_issue_row, fn() {
          if sr_arg(args, "month") != "" {
            sr_words(c, gh_t("gahou.month", args), gh_issue)
          }
          sr_rich(c, gh_said("gahou.issue", args, g.ink), gh_issue)
          c.box(style=gh_grow, fn() {  }) |> ignore
          sr_words(c, gh_t(g.own + ".note", []), gh_issue)
        })
        |> ignore
      })
      |> ignore
      // the cover lines
      c.box(style=gh_lines, top=g.lines_top, left=gh_edge, fn() {
        let lines = [("gahou.feature", "gahou.featureLine"), ..g.lines, ("gahou.live", "gahou.liveLine")]
        for line in lines {
          c.box(style=gh_line, fn() {
            sr_words(c, gh_t(line.0, []), gh_what.then(ink))
            sr_rich(c, gh_said(line.1, args, g.ink, hi_scale=gh_said_scale), gh_says)
          })
          |> ignore
        }
      })
      |> ignore
      // her name, her title, her line
      c.box(style=gh_hero, bottom=gh_hero_bottom, left=gh_edge, right=gh_edge, fn() {
        sr_rich(
          c,
          [
            @ui.span(name + " ", weight=600, scale=gh_name_scale),
            @ui.span(gh_t(g.who + ".title", []), color=g.ink, scale=gh_title_scale),
          ],
          gh_name,
        )
        sr_rich(c, gh_said(g.own + ".sub", args, g.ink, scale=gh_sub_scale, hi_scale=gh_sub_hi), gh_sub)
      })
      |> ignore
      // the barcode, still.fail, the price
      c.box(style=gh_foot, bottom=gh_foot_bottom, left=gh_edge, right=gh_edge, fn() {
        gh_barcode(c, sr_arg(args, "at") + sr_arg(args, "weekCost") + name, gh_figures(sr_arg(args, "at")))
        c.box(style=gh_meta, fn() {
          sr_brand(c, gh_brand)
          sr_words(c, @sf.t("web-main.stations.shareTagline"), gh_small)
        })
        |> ignore
        c.box(style=gh_grow, fn() {  }) |> ignore
        c.box(style=gh_price, fn() {
          sr_words(c, gh_t("gahou.price", []), gh_small)
          sr_words(c, sr_arg(args, "weekCost"), gh_price_figure.then(ink))
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// What the covers say, by name: sr_args', and the week's chats archived as a number alone (`archivedN`,
/// the issue's number too: `issue`), today's (`todayN`), and the month of the week's last day (`month`, the issue's).
fn gh_args(fleet : Json?) -> Array[(String, String)] {
  let args = sr_args(fleet)
  let month = match sr_days(fleet) {
    [.., last] =>
      match last.0.find("/") {
        Some(i) => last.0.exact_view(end=i).to_owned()
        None => ""
      }
    _ => ""
  }
  let archived = sr_num(sr_arg(args, "archived"))
  [..args, ("archivedN", archived), ("issue", archived), ("todayN", sr_num(sr_arg(args, "todayArchived"))), ("month", month)]
}

///|
/// The words of `key` under shareSenren., its `{name}`s put in from `args`.
fn gh_t(key : String, args : Array[(String, String)]) -> String {
  @sf.t("web-main.stations.shareSenren." + key, args~)
}

///|
/// The words of `key` under shareSenren. as runs, as sr_said makes them (each name's figure in `hi`, bolder,
/// `hi_scale` its size), but a name of gh_plain put in as the words round it are, and these `scale` their size: the
/// mockups make bold only the figures that are the news (用 6 个 Claude 订阅，一周烧掉 **2.1 亿** token).
fn gh_said(
  key : String,
  args : Array[(String, String)],
  hi : Int64,
  scale? : Double = 1.0,
  hi_scale? : Double = 1.0,
) -> Array[@ui.Run] {
  let runs : Array[@ui.Run] = []
  let mut rest = gh_t(key, [])
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
              runs.push(@ui.span(rest.exact_view(end=i).to_owned(), scale~))
            }
            let value = sr_arg(args, name)
            if gh_plain.contains(name) {
              runs.push(@ui.span(value, scale~))
            } else {
              runs.push(@ui.span(value, color=hi, weight=700, scale=hi_scale))
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
/// The names put in as the words round them: what the figures are of (the accounts and their kind, the model), an
/// average, the month.
// kept across runs: a table, never written
let gh_plain : Array[String] = ["accounts", "kind", "model", "tasksPer", "month"]

///|
/// A shade of `ink`, `w` by `h`, out of the flow `top` from the cover's top and `left` from its left, each point's
/// opacity `alpha(x, y)` (x and y from 0 to 1, across and down). mbui fills no gradient, nor masks one with another
/// (the side shade is a gradient across faded at its top and foot), so it is a small picture of its pixels, made once
/// (by `name` and `ink`: the same each time), laid stretched.
fn gh_shade(
  c : @ui.Ctx,
  name : String,
  ink : Int64,
  w : Double,
  h : Double,
  top : Double,
  left : Double,
  alpha : (Double, Double) -> Double,
) -> Unit {
  let key = "mem:senren-cover/\{name}/\{ink}"
  if !@ui.has_image(key) {
    let n = gh_shade_px
    let px = FixedArray::make(n * n * 4, b'\x00')
    for j in 0..<n {
      for i in 0..<n {
        let a = alpha((i.to_double() + 0.5) / n.to_double(), (j.to_double() + 0.5) / n.to_double())
        let a = if a < 0.0 { 0.0 } else if a > 1.0 { 1.0 } else { a }
        let o = (j * n + i) * 4
        px[o] = ((ink >> 24) & 0xFFL).to_int().to_byte()
        px[o + 1] = ((ink >> 16) & 0xFFL).to_int().to_byte()
        px[o + 2] = ((ink >> 8) & 0xFFL).to_int().to_byte()
        px[o + 3] = (a * 255.0).round().to_int().to_byte()
      }
    }
    @ui.add_image(key, @pixels.png(n, n, px))
  }
  c.box(top~, left~, fn() { c.image(key, w=Px(w), h=Px(h), fit=FitFill, bg=0L, fade=false) |> ignore }) |> ignore
}

///|
/// `ink` at the masthead's small line's opacity (90%).
fn gh_dim(ink : Int64) -> Int64 {
  (ink & 0xFFFFFF00L) | gh_dim_alpha
}

///|
/// `words` with a space between each two of its characters (three between its words): letters set far apart, as a
/// masthead's small line is (the mockups' letter spacing of 0.32 to 0.42 of an em, past the widest tracking).
fn gh_spaced(words : String) -> String {
  let buf = StringBuilder()
  let mut first = true
  for ch in words {
    if !first {
      buf.write_char(' ')
    }
    buf.write_char(ch)
    first = false
  }
  buf.to_string()
}

///|
/// The figures of `words` alone (the time's: 10月26日 04:12, 10260412).
fn gh_figures(words : String) -> String {
  let buf = StringBuilder()
  for ch in words {
    if ch >= '0' && ch <= '9' {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
/// The cover's barcode on its white: a bar for each character of `words` (its first gh_code_most), 1 to 3 wide and 1
/// or 2 from the next as its code says (the mockup's), `figures` under it.
fn gh_barcode(c : @ui.Ctx, words : String, figures : String) -> Unit {
  c.box(style=gh_code, fn() {
    c.box(style=gh_bars, fn() {
      let mut n = 0
      for ch in words {
        if n >= gh_code_most {
          break
        }
        let k = ch.to_int()
        let w = (k % 3 + 1).to_double()
        let gap = ((k >> 2) % 2 + 1).to_double()
        c.box(style=gh_bar.then(@ui.style(w=Fixed(w))), fn() {  }) |> ignore
        c.box(style=@ui.style(w=Fixed(gap)), fn() {  }) |> ignore
        n = n + 1
      }
    })
    |> ignore
    sr_rich(c, [@ui.span(figures, scale=gh_code_scale)], gh_code_words)
  })
  |> ignore
}

// ── 穗织画报's sizes and looks ─────────────────────────────────────────────

///|
/// The cover: as tall as a phone's picture (360 by 640), its picture as tall.
let gh_h : Double = 640.0

///|
/// Where the cover lines start, from the cover's top: under the masthead, beside the heroine's middle.
let gh_lines_top : Double = 236.0

///|
/// The sky's fade into a picture moved down: its top this tall.
let gh_sky_h : Double = 70.0

///|
/// The shade at the top, under the masthead: this tall, from 75% of the deep to none.
let gh_top_h : Double = 150.0

///|
let gh_top_most : Double = 0.75

///|
/// The shade at the foot, under her name and the barcode: this tall, the deep whole from 78% of it down.
let gh_foot_h : Double = 300.0

///|
let gh_foot_full : Double = 0.78

///|
/// The shade behind the cover lines: this wide and tall, from 30 over their top, 90% of the deep at the cover's edge
/// to none across, faded in and out over 22% of its height at its top and foot.
let gh_side_w : Double = 250.0

///|
let gh_side_h : Double = 250.0

///|
let gh_side_over : Double = 30.0

///|
let gh_side_most : Double = 0.9

///|
let gh_side_fade : Double = 0.22

///|
/// How many pixels a shade's picture is made of, across and down (it changes slowly: each stretched).
let gh_shade_px : Int = 64

///|
/// The masthead's place: this far from the cover's top, its sides as far in as everything's (gh_edge).
let gh_mast_top : Double = 12.0

///|
let gh_edge : Double = 16.0

///|
/// Her name's and line's place: their foot this far over the cover's; the barcode's foot this far.
let gh_hero_bottom : Double = 58.0

///|
let gh_foot_bottom : Double = 14.0

///|
/// The masthead's small line's opacity (90%).
let gh_dim_alpha : Int64 = 0xE6L

///|
/// The words over the picture: white, and white at 90%; the foot's grey.
let gh_white : Int64 = 0xFFFFFFFFL

///|
let gh_white_dim : Int64 = 0xFFFFFFE6L

///|
let gh_grey : Int64 = 0xDDDDDDFFL

///|
/// Her name 34 (on 30), her title 13 after it; her line 15, its figures 18 (on 14); a cover line's figures 17 (on 14).
let gh_name_scale : Double = 1.1333

///|
let gh_title_scale : Double = 0.4333

///|
let gh_sub_scale : Double = 1.0714

///|
let gh_sub_hi : Double = 1.2857

///|
let gh_said_scale : Double = 1.2143

///|
/// The barcode: at most this many bars, 22 high, black on white; its figures 7 (on 10).
let gh_code_most : Int = 26

///|
let gh_bars_h : Double = 22.0

///|
let gh_bar_ink : Int64 = 0x111111FFL

///|
let gh_code_scale : Double = 0.7

///|
/// The cover's whole: as wide as the card, gh_h tall, what is moved past its foot cut.
// kept across runs: a value (no field of it changes)
let gh_frame : @ui.Style = @ui.css("w=Full clip").then(@ui.style(h=Fixed(gh_h)))

///|
// kept across runs: a value (no field of it changes)
let gh_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let gh_row : @ui.Style = @ui.css("row w=Full align=ACenter")

///|
/// The masthead: its small line, its title 2 under it, its issue's line 4 under that.
// kept across runs: a value (no field of it changes)
let gh_mast : @ui.Style = @ui.css("gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let gh_issue_row : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter pt=S0_5")

///|
// kept across runs: a value (no field of it changes)
let gh_en : @ui.TextStyle = @ui.text_style(size=Xs3, tracking=Widest, wrap=false)

///|
/// The masthead's title: 60 high (its size, line-height 1), its face's 71 lifted by half the 11 past it.
let gh_title_h : Double = 60.0

///|
let gh_title_lift : Double = 5.5

///|
// kept across runs: a value (no field of it changes)
let gh_title_box : @ui.Style = @ui.css("w=Full").then(@ui.style(h=Fixed(gh_title_h)))

///|
// kept across runs: a value (no field of it changes)
let gh_title : @ui.TextStyle = @ui.text_style(size=Xl6, weight=Semibold, tracking=Wider, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let gh_issue : @ui.TextStyle = @ui.text_style(size=Xs2, leading=L3, color=Data(gh_white_dim), wrap=false)

///|
/// The cover lines: 196 wide, 8 apart; each what it is over what it says.
let gh_lines_w : Double = 196.0

///|
// kept across runs: a value (no field of it changes)
let gh_lines : @ui.Style = @ui.css("gap=S2").then(@ui.style(w=Fixed(gh_lines_w)))

///|
// kept across runs: a value (no field of it changes)
let gh_line : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let gh_what : @ui.TextStyle = @ui.text_style(size=Xs2, leading=L3, tracking=Widest, w=Full)

///|
// kept across runs: a value (no field of it changes)
let gh_says : @ui.TextStyle = @ui.text_style(size=Sm, leading=L4_75, color=Data(gh_white), w=Full)

///|
/// Her name and title over her line, 2 apart.
// kept across runs: a value (no field of it changes)
let gh_hero : @ui.Style = @ui.css("gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let gh_name : @ui.TextStyle = @ui.text_style(size=Xl3, tracking=Wider, color=Data(gh_white), w=Full)

///|
// kept across runs: a value (no field of it changes)
let gh_sub : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(gh_white), w=Full)

///|
/// The foot: the barcode, still.fail over its line, the price at the end, 10 apart, by their feet.
// kept across runs: a value (no field of it changes)
let gh_foot : @ui.Style = @ui.css("row gap=S2_5 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let gh_meta : @ui.Style = @ui.css("gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let gh_brand : @ui.TextStyle = @ui.text_style(size=Sm, weight=Semibold, color=Data(gh_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let gh_small : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(gh_grey), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let gh_price : @ui.Style = @ui.css("align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let gh_price_figure : @ui.TextStyle = @ui.text_style(size=Lg, weight=Bold, leading=L5, wrap=false)

///|
/// The barcode's white: 4 over its bars, 5 either side, 2 under its figures, its bars over its figures.
// kept across runs: a value (no field of it changes)
let gh_code : @ui.Style = @ui.css("align=ACenter pt=S1 px=S1_25 pb=S0_5 radius=Sm").then(@ui.style(bg=Data(gh_white)))

///|
// kept across runs: a value (no field of it changes)
let gh_bars : @ui.Style = @ui.css("row").then(@ui.style(h=Fixed(gh_bars_h)))

///|
// kept across runs: a value (no field of it changes)
let gh_bar : @ui.Style = @ui.css("h=Full").then(@ui.style(bg=Data(gh_bar_ink)))

///|
// kept across runs: a value (no field of it changes)
let gh_code_words : @ui.TextStyle = @ui.text_style(size=Xs3, tracking=Widest, color=Data(gh_bar_ink), wrap=false)

// ── 穗织 · 观光导览图 ────────────────────────────────────────────────────

///|
/// A place on the map: its spot on the picture (`x`, `y`: its red dot); its label card's top and its side's distance
/// (`side`: from the map's left, or from its right where `right`, so longer words grow away from the edge); where its
/// dashed leader ends (`ex`, `ey`: a little inside the card, which covers the rest, as the mockup's ends on its edge);
/// its symbol (map_icon_shapes' parts); its name's key and its lines' keys under shareSenren.
priv struct MapPlace {
  x : Double
  y : Double
  right : Bool
  side : Double
  top : Double
  ex : Double
  ey : Double
  icon : Array[(String, Int64, Int64, Double)]
  name : String
  lines : Array[String]
}

///|
/// The places, each where the mockup put it on the picture (senren/cards/hoori-map.html's P).
// kept across runs: a table, never written
let map_places : Array[MapPlace] = [
  {
    x: 150.0,
    y: 54.0,
    right: false,
    side: 6.0,
    top: 10.0,
    ex: 100.0,
    ey: 54.0,
    icon: map_icon_shrine,
    name: "map.shrine",
    lines: ["map.shrineIncense", "map.shrineWorth"],
  },
  {
    x: 120.0,
    y: 216.0,
    right: false,
    side: 6.0,
    top: 132.0,
    ex: 84.0,
    ey: 169.0,
    icon: map_icon_inn,
    name: "map.inn",
    lines: ["map.innGuests"],
  },
  {
    x: 305.0,
    y: 206.0,
    right: true,
    side: 12.0,
    top: 246.0,
    ex: 305.0,
    ey: 256.0,
    icon: map_icon_school,
    name: "map.school",
    lines: ["map.schoolWork"],
  },
  {
    x: 100.0,
    y: 328.0,
    right: false,
    side: 6.0,
    top: 398.0,
    ex: 100.0,
    ey: 408.0,
    icon: map_icon_sweets,
    name: "map.sweets",
    lines: ["map.sweetsTakings"],
  },
  {
    x: 183.0,
    y: 330.0,
    right: false,
    side: 124.0,
    top: 354.0,
    ex: 183.0,
    ey: 364.0,
    icon: map_icon_bridge,
    name: "map.bridge",
    lines: ["map.bridgeTrips"],
  },
  {
    x: 288.0,
    y: 408.0,
    right: true,
    side: 47.0,
    top: 482.0,
    ex: 288.0,
    ey: 492.0,
    icon: map_icon_onsen,
    name: "map.onsen",
    lines: ["map.onsenSoak"],
  },
]

///|
/// The places' symbols, 14 by 14, the mockup's SVGs: each part its path, its fill, its stroke and the stroke's width
/// (0 for none). The shrine's torii.
// kept across runs: a table, never written
let map_icon_shrine : Array[(String, Int64, Int64, Double)] = [
  ("M1 3.5 Q7 1.6 13 3.5", 0L, 0xC8322AFFL, 1.8),
  ("M2.6 6.2 H11.4", 0L, 0xC8322AFFL, 1.4),
  ("M4 3.6 V13 M10 3.6 V13", 0L, 0xC8322AFFL, 1.6),
]

///|
/// The inn: a roof over a lattice front.
// kept across runs: a table, never written
let map_icon_inn : Array[(String, Int64, Int64, Double)] = [
  ("M1 7 L7 2 L13 7 Z", 0x3A3283FFL, 0L, 0.0),
  ("M2.5 7 H11.5 V13 H2.5 Z", 0xEFE4CFFFL, 0x3A3283FFL, 1.0),
  ("M4 7.6 V10.4 M6 7.6 V10.4 M8 7.6 V10.4 M10 7.6 V10.4", 0L, 0x3A3283FFL, 1.2),
]

///|
/// The academy: a gabled hall, its door and its clock.
// kept across runs: a table, never written
let map_icon_school : Array[(String, Int64, Int64, Double)] = [
  ("M1 6 L7 2 L13 6", 0xA57A4EFFL, 0x6E4A2AFFL, 1.4),
  ("M2 6 H12 V13 H2 Z", 0xD9B98AFFL, 0x6E4A2AFFL, 1.0),
  ("M6 9 H8 V13 H6 Z", 0x6E4A2AFFL, 0L, 0.0),
  ("M6 4.6 A1 1 0 1 0 8 4.6 A1 1 0 1 0 6 4.6 Z", 0xFFFAF0FFL, 0L, 0.0),
]

///|
/// The sweets shop: a red parasol.
// kept across runs: a table, never written
let map_icon_sweets : Array[(String, Int64, Int64, Double)] = [
  ("M1.5 7 Q7 0 12.5 7 Z", 0xD23A2AFFL, 0L, 0.0),
  ("M7 3 V13", 0L, 0x6E4A2AFFL, 1.1),
  ("M4 6.6 Q7 3.2 10 6.6", 0L, 0xF6C9B8FFL, 0.7),
]

///|
/// The red bridge over its river.
// kept across runs: a table, never written
let map_icon_bridge : Array[(String, Int64, Int64, Double)] = [
  ("M1 11 Q7 3 13 11", 0L, 0xC8322AFFL, 1.8),
  ("M1 8.6 Q7 1.4 13 8.6", 0L, 0xC8322AFFL, 1.0),
  ("M4 6.3 V9.4 M7 4.6 V7.6 M10 6.3 V9.4", 0L, 0xC8322AFFL, 1.0),
  ("M0 12.5 H14", 0L, 0x5A9AD0FFL, 1.2),
]

///|
/// The hot spring: ♨.
// kept across runs: a table, never written
let map_icon_onsen : Array[(String, Int64, Int64, Double)] = [
  ("M2.5 9 Q7 14.5 11.5 9", 0L, 0xD23A2AFFL, 1.5),
  (
    "M4.6 8 Q3.6 6 4.6 4.5 Q5.6 3 4.6 1.5 M7 8 Q6 6 7 4.5 Q8 3 7 1.5 M9.4 8 Q8.4 6 9.4 4.5 Q10.4 3 9.4 1.5",
    0L,
    0xD23A2AFFL,
    1.2,
  ),
]

///|
/// The compass rose, 54 by 62 (the mockup's SVG): its paper disc and rim, the dashed ring inside it (27 dashes as
/// CSS's 1.5-on-2-off draws them round it, each 0.6 shorter for the round ends a stroke here has: worked out once,
/// so nothing is turned here), the needle with its red north half, the east-west bar.
// kept across runs: a table, never written
let map_compass : Array[(String, Int64, Int64, Double)] = [
  ("M8 35 A19 19 0 1 0 46 35 A19 19 0 1 0 8 35 Z", 0xFFFAF0D9L, 0x3A2A1AFFL, 1.2),
  (map_ring_dashes, 0L, 0x3A2A1AFFL, 0.6),
  ("M27 17 L31 35 L27 53 L23 35 Z", 0xFFFAF0FFL, 0x3A2A1AFFL, 1.0),
  ("M27 17 L31 35 L23 35 Z", 0xD23A2AFFL, 0L, 0.0),
  ("M9 35 L27 31.5 L45 35 L27 38.5 Z", 0x3A2A1ABFL, 0L, 0.0),
]

///|
let map_ring_dashes : String = "M42.00 35.30 L41.95 36.20 M41.52 38.76 L41.27 39.62 M40.26 42.02 L39.81 42.80 M38.28 44.89 L37.66 45.55 M35.68 47.23 L34.94 47.73 M32.62 48.91 L31.78 49.22 M29.25 49.83 L28.36 49.94 M25.76 49.95 L24.87 49.85 M22.34 49.26 L21.49 48.95 M19.17 47.79 L18.42 47.30 M16.42 45.64 L15.80 44.98 M14.25 42.90 L13.80 42.12 M12.77 39.74 L12.51 38.88 M12.06 36.32 L12.01 35.42 M12.16 32.83 L12.31 31.95 M13.06 29.46 L13.42 28.63 M14.72 26.39 L15.26 25.66 M17.04 23.78 L17.74 23.20 M19.91 21.78 L20.71 21.38 M23.16 20.50 L24.03 20.30 M26.61 20.00 L27.51 20.01 M30.09 20.32 L30.97 20.53 M33.40 21.43 L34.20 21.84 M36.36 23.28 L37.05 23.87 M38.82 25.77 L39.35 26.49 M40.64 28.75 L40.99 29.58 M41.71 32.07 L41.86 32.96"

///|
/// 穗织 · 观光导览图: the illustrated town fills the card, a hanging scroll's title at its top right, each place a pin
/// (a red dot on its spot, a dashed leader to a label card: the shrine the top model's tokens and cost, the inn the
/// chats running tonight, the academy the week's chats archived, the sweets shop the week's spend, the red bridge the
/// tasks across devices, the hot spring the devices), a compass at its foot; under it a legend: the week's chats
/// archived and their days as bars, still.fail, when and its line.
fn sr_map(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let args = gh_args(fleet)
  let w = @sf.share_w_most
  sr_box(c, id, flat, map_ground, fn() {
    c.box(style=map_frame, fn() {
      sr_art(c, "d3-hoori-map", w, map_h) |> ignore
      // the leaders, under the cards
      c.box(left=0.0, top=0.0, fn() { c.shapes(map_leaders(), w=Px(w), h=Px(map_h)) |> ignore }) |> ignore
      // the title: a little hanging scroll, a rod at either end
      c.box(style=map_cart, right=map_cart_side, top=map_cart_side, fn() {
        c.box(style=map_cart_inner, fn() {
          sr_rich(
            c,
            [
              @ui.span(gh_t("map.town", []) + " ", scale=map_title_k),
              @ui.span(gh_t("map.guide", []), color=map_red, scale=map_title_k),
            ],
            map_cart_title,
          )
          sr_words(c, gh_t("map.sub", []), map_cart_sub)
        })
        |> ignore
        c.box(style=map_rod, left=map_rod_out, top=map_rod_over, bottom=map_rod_over, fn() {
          c.box(style=map_rod_shine, fn() {  }) |> ignore
        })
        |> ignore
        c.box(style=map_rod, right=map_rod_out, top=map_rod_over, bottom=map_rod_over, fn() {
          c.box(style=map_rod_shine, fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
      // the places: each its card (on its shadow, laid that far right and down of it) and its dot
      for p in map_places {
        let card = fn() { map_card(c, p, args) }
        if p.right {
          c.box(style=map_card_shadow, right=p.side - map_card_drop, top=p.top + map_card_drop, card) |> ignore
        } else {
          c.box(style=map_card_shadow, left=p.side + map_card_drop, top=p.top + map_card_drop, card) |> ignore
        }
        c.box(style=map_dot, left=p.x - map_dot_r, top=p.y - map_dot_r, fn() {  }) |> ignore
      }
      // the compass
      c.box(left=map_compass_left, top=map_compass_top, fn() {
        c.shapes(map_shapes(map_compass), w=Px(map_compass_w), h=Px(map_compass_h)) |> ignore
        c.box(left=0.0, right=0.0, top=map_north_top, fn() { sr_words(c, gh_t("map.north", []), map_north) }) |> ignore
      })
      |> ignore
    })
    |> ignore
    // the legend: the week's visitors as bars, still.fail and when
    c.box(style=map_rule, fn() {  }) |> ignore
    c.box(style=map_legend, fn() {
      // (the label wraps where the room beside still.fail runs out: in English it is long)
      c.box(style=map_flow, fn() {
        sr_rich(c, [@ui.span(gh_t("map.flow", args), scale=map_small_k)], map_small_wrap)
        c.box(style=map_bars, fn() {
          for d in sr_days(fleet) {
            let (_, _, _, share, today) = d
            let h = if share * map_bars_h > map_bar_least { share * map_bars_h } else { map_bar_least }
            let bar = if today { map_bar_today } else { map_bar }
            c.box(style=bar.then(@ui.style(h=Fixed(h))), fn() {  }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
      // (as wide as its widest line, each a line of its own: nothing of it cut short in either language)
      c.box(style=map_info, fn() {
        sr_brand(c, map_brand)
        sr_rich(c, [@ui.span(sr_arg(args, "at"), scale=map_small_k)], map_small)
        sr_rich(c, [@ui.span(@sf.t("web-main.stations.shareTagline"), scale=map_small_k)], map_small)
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// A place's label card, moved up and left by its shadow's offset (it is laid in its shadow): its symbol and name in
/// red over its lines, their figures bolder and larger.
fn map_card(c : @ui.Ctx, p : MapPlace, args : Array[(String, String)]) -> Unit {
  c.box(style=map_card_box, tx=-map_card_drop, ty=-map_card_drop, fn() {
    c.box(style=map_card_head, fn() {
      c.shapes(map_shapes(p.icon), w=Px(map_icon), h=Px(map_icon)) |> ignore
      sr_rich(c, [@ui.span(gh_t(p.name, []), scale=map_k)], map_card_name)
    })
    |> ignore
    for line in p.lines {
      sr_rich(c, gh_said(line, args, map_ink_deep, scale=map_k, hi_scale=map_figure_k), map_card_line)
    }
  })
  |> ignore
}

///|
/// The shapes of `parts` (each a path, its fill, its stroke and the stroke's width), each filled, then stroked.
fn map_shapes(parts : Array[(String, Int64, Int64, Double)]) -> Array[@ui.Shape] {
  let out : Array[@ui.Shape] = []
  for part in parts {
    let (d, fill, stroke, width) = part
    let outlines = @pixels.svg_path(d, map_cut)
    if fill != 0L {
      out.push(@ui.shape_of(outlines, fill~))
    }
    if stroke != 0L {
      out.push(@ui.shape_of(outlines, stroke~, width~))
    }
  }
  out
}

///|
/// Each place's leader from its dot to its card: a pale line under a dark dashed one (CSS's 3-on-2.5-off, each dash
/// shorter by its round ends).
fn map_leaders() -> Array[@ui.Shape] {
  let out : Array[@ui.Shape] = []
  for p in map_places {
    out.push(@ui.shape_of([([p.x, p.y, p.ex, p.ey], false)], stroke=map_leader_under, width=map_leader_under_w))
    let dx = p.ex - p.x
    let dy = p.ey - p.y
    let len = (dx * dx + dy * dy).sqrt()
    let dashes : Array[(Array[Double], Bool)] = []
    let mut s = 0.0
    while s < len {
      let a = s + map_dash_cap
      let b = (if s + map_dash < len { s + map_dash } else { len }) - map_dash_cap
      if b > a {
        dashes.push(([p.x + dx * a / len, p.y + dy * a / len, p.x + dx * b / len, p.y + dy * b / len], false))
      }
      s = s + map_dash + map_dash_gap
    }
    out.push(@ui.shape_of(dashes, stroke=map_ink, width=map_leader_w))
  }
  out
}

///|
/// The map's colours: its paper, its ink, its red, its brown; the cards' grounds (the paper at 95% and 96%), the
/// title's inner line, the shadows, the scroll's rods, the bars.
let map_ground : Int64 = 0xF4EAD6FFL

///|
let map_ink : Int64 = 0x3A2A1AFFL

///|
let map_ink_deep : Int64 = 0x2A1A10FFL

///|
let map_title_ink : Int64 = 0x3A1A10FFL

///|
let map_red : Int64 = 0xB8382AFFL

///|
let map_dot_red : Int64 = 0xD23A2AFFL

///|
let map_brown : Int64 = 0x8A5A3AFFL

///|
let map_white : Int64 = 0xFFFFFFFFL

///|
let map_cart_ground : Int64 = 0xFFFAF0F2L

///|
let map_cart_line : Int64 = 0xB8382A66L

///|
let map_card_ground : Int64 = 0xFFFAF0F5L

///|
let map_shadow : Int64 = 0x3A2A1A40L

///|
let map_dot_shadow : Int64 = 0x00000066L

///|
let map_leader_under : Int64 = 0xFFFAF0D9L

///|
let map_rod_dark : Int64 = 0x6E4A2AFFL

///|
let map_rod_light : Int64 = 0xA57A4EFFL

///|
let map_bar_ink : Int64 = 0xC9A77AFFL

///|
/// The map 540 high (the picture, 2:3, whole).
let map_h : Double = 540.0

///|
/// The words' sizes off the scale, as runs' scales of the scale's (still.fail's): the cards' 12.5 (of Xs's 12), their
/// figures' 14, the title's 19 (of Xl2's 17), the legend's 11.5 (of Xs2's 11).
let map_k : Double = 1.0416667

///|
let map_figure_k : Double = 1.1666667

///|
let map_title_k : Double = 1.1176471

///|
let map_small_k : Double = 1.0454545

///|
/// The symbols 14 square; paths cut fine enough for 4 pixels a point.
let map_icon : Double = 14.0

///|
let map_cut : Double = 4.0

///|
/// The title 12 in from the map's top and right; its shadow 10 soft, 3 down; its rods 7 wide, 5 out past its sides
/// and 3 past its top and foot, a lighter 3 down their middles (the mockup's rounded gradient).
let map_cart_side : Double = 12.0

///|
let map_cart_blur : Double = 10.0

///|
let map_cart_drop : Double = 3.0

///|
let map_rod_w : Double = 7.0

///|
let map_rod_shine_w : Double = 3.0

///|
let map_rod_out : Double = -5.0

///|
let map_rod_over : Double = -3.0

///|
/// The cards' hard shadow 2 right and down; the dots 12 across, their shadow 4 soft, 1 down.
let map_card_drop : Double = 2.0

///|
let map_dot_size : Double = 12.0

///|
let map_dot_r : Double = 6.0

///|
let map_dot_blur : Double = 4.0

///|
let map_dot_y : Double = 1.0

///|
/// The leaders: the pale line 3.4 wide, the dashes 1.3 wide, 3 on and 2.5 off, their round ends half their width.
let map_leader_under_w : Double = 3.4

///|
let map_leader_w : Double = 1.3

///|
let map_dash : Double = 3.0

///|
let map_dash_gap : Double = 2.5

///|
let map_dash_cap : Double = 0.65

///|
/// The compass 54 by 62, 10 in from the map's left and 8 up from its foot; its N's line 2 above its box.
let map_compass_left : Double = 10.0

///|
let map_compass_top : Double = 470.0

///|
let map_compass_w : Double = 54.0

///|
let map_compass_h : Double = 62.0

///|
let map_north_top : Double = -2.0

///|
/// The legend's rule 2 high; its bars 30 high at most, 4 at least, 10 wide.
let map_rule_h : Double = 2.0

///|
let map_bars_h : Double = 30.0

///|
let map_bar_least : Double = 4.0

///|
let map_bar_w : Double = 10.0

///|
// kept across runs: a value (no field of it changes)
let map_frame : @ui.Style = @ui.css("w=Full clip").then(@ui.style(h=Fixed(map_h)))

///|
// kept across runs: a value (no field of it changes)
let map_cart : @ui.Style = @ui.css("p=S0_5 border=B1_5 radius=Base").then(
  @ui.style(
    bg=Data(map_cart_ground),
    border_color=Data(map_red),
    shadow=Cast(map_cart_blur, map_cart_drop, map_shadow),
  ),
)

///|
// kept across runs: a value (no field of it changes)
let map_cart_inner : @ui.Style = @ui.css("pt=S0_5 pb=S1 px=S3 border=B1 radius=Sm align=ACenter").then(
  @ui.style(border_color=Data(map_cart_line)),
)

///|
// kept across runs: a value (no field of it changes)
let map_rod : @ui.Style = @ui.css("row justify=JCenter radius=Base").then(
  @ui.style(w=Fixed(map_rod_w), bg=Data(map_rod_dark)),
)

///|
// kept across runs: a value (no field of it changes)
let map_rod_shine : @ui.Style = @ui.css("h=Full radius=Base").then(
  @ui.style(w=Fixed(map_rod_shine_w), bg=Data(map_rod_light)),
)

///|
// kept across runs: a value (no field of it changes)
let map_cart_title : @ui.TextStyle = @ui.text_style(
  size=Xl2,
  weight=Semibold,
  tracking=Wider,
  leading=L6,
  color=Data(map_title_ink),
  wrap=false,
)

///|
// kept across runs: a value (no field of it changes)
let map_cart_sub : @ui.TextStyle = @ui.text_style(size=Xs2, tracking=@sf.share_letters_apart, color=Data(map_brown), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let map_card_shadow : @ui.Style = @ui.css("radius=Md").then(@ui.style(bg=Data(map_shadow)))

///|
// kept across runs: a value (no field of it changes)
let map_card_box : @ui.Style = @ui.css("pt=S1 pb=S1_25 px=S2 radius=Md border=B1").then(
  @ui.style(bg=Data(map_card_ground), border_color=Data(map_ink)),
)

///|
// kept across runs: a value (no field of it changes)
let map_card_head : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let map_card_name : @ui.TextStyle = @ui.text_style(size=Xs, weight=Semibold, leading=L4, color=Data(map_red), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let map_card_line : @ui.TextStyle = @ui.text_style(size=Xs, leading=L4, color=Data(map_ink_deep), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let map_dot : @ui.Style = @ui.css("radius=Full border=B2").then(
  @ui.style(
    w=Fixed(map_dot_size),
    h=Fixed(map_dot_size),
    bg=Data(map_dot_red),
    border_color=Data(map_white),
    shadow=Cast(map_dot_blur, map_dot_y, map_dot_shadow),
  ),
)

///|
// kept across runs: a value (no field of it changes)
let map_north : @ui.TextStyle = @ui.text_style(size=Xs2, weight=Bold, color=Data(map_ink), center=true, w=Full)

///|
// kept across runs: a value (no field of it changes)
let map_rule : @ui.Style = @ui.css("w=Full").then(@ui.style(h=Fixed(map_rule_h), bg=Data(map_ink)))

///|
// kept across runs: a value (no field of it changes)
let map_legend : @ui.Style = @ui.css("row w=Full pt=S2_5 pb=S3 px=S4 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let map_flow : @ui.Style = @ui.style(w=@sf.grow).then(@ui.css("gap=S0_5"))

///|
// kept across runs: a value (no field of it changes)
let map_bars : @ui.Style = @ui.css("row gap=S1 align=AEnd").then(@ui.style(h=Fixed(map_bars_h)))

///|
// kept across runs: a value (no field of it changes)
let map_bar : @ui.Style = @ui.css("radius=Sm").then(@ui.style(w=Fixed(map_bar_w), bg=Data(map_bar_ink)))

///|
// kept across runs: a value (no field of it changes)
let map_bar_today : @ui.Style = map_bar.then(@ui.style(bg=Data(map_dot_red)))

///|
// kept across runs: a value (no field of it changes)
let map_info : @ui.Style = @ui.css("gap=S0_5 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let map_brand : @ui.TextStyle = @ui.text_style(size=Xl, weight=Semibold, color=Data(map_ink_deep), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let map_small : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(map_brown), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let map_small_wrap : @ui.TextStyle = @ui.text_style(size=Xs2, color=Data(map_brown), w=Full)
