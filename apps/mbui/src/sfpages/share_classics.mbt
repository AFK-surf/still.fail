// The card to share's classic paper looks (2026-10-27 用户：「整一点经典的东西进去」「搞十个不同类型的」): a newspaper's
// front page, an almanac's day, a boarding pass, a certificate of merit. Each says of the `fleet` view what that paper
// would, in its own words (share_games.mbt said_of).

// ── 报纸 ───────────────────────────────────────────────────────────────────

///|
/// 报纸: a newspaper's front page in the serif face: its masthead between rules, the day and still.fail's line under it;
/// the headline the first kind's share whole; under it what is at work and where as its deck; two columns, today and
/// the last 7 days, a rule between them; the tasks across devices as the story at its foot.
fn paper_look(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let s = said_of(fleet)
  look_box(c, id, flat, @sf.share_paper_ground, fn() {
    c.box(style=paper_rule_thick, fn() {  }) |> ignore
    serif_centred(c, @sf.t("web-main.stations.shareDaily"), paper_masthead)
    c.box(style=pic_head, fn() {
      c.box(style=pic_grow, fn() { serif(c, s.at, paper_small) }) |> ignore
      serif(c, @sf.t("web-main.stations.shareTagline"), paper_small)
    })
    |> ignore
    c.box(style=paper_double, fn() {
      c.box(style=paper_rule, fn() {  }) |> ignore
      c.box(style=paper_rule, fn() {  }) |> ignore
    })
    |> ignore
    serif(c, if s.lead != "" { s.lead + " " + s.number + " " + s.of } else { s.number + " " + s.of }, paper_headline)
    serif(c, s.chats_text + "，" + s.where_, paper_deck)
    c.box(style=paper_rule, fn() {  }) |> ignore
    c.box(style=paper_columns, fn() {
      paper_column(c, s.today_title, s.today)
      c.box(style=paper_column_rule, fn() {  }) |> ignore
      paper_column(c, s.week_title, s.week)
    })
    |> ignore
    if s.tasks != "" {
      c.box(style=paper_rule, fn() {  }) |> ignore
      serif(c, s.tasks + "，" + s.tasks_per + "。", paper_story)
    }
    c.box(style=paper_rule_thick, fn() {  }) |> ignore
  })
}

///|
/// Words in the serif face.
fn serif(c : @ui.Ctx, words : String, style : @ui.TextStyle) -> Unit {
  c.rich([@ui.span(words, serif=true)], style~) |> ignore
}

///|
/// Words in the serif face, in the middle of their line.
fn serif_centred(c : @ui.Ctx, words : String, style : @ui.TextStyle) -> Unit {
  c.box(style=centred_line, fn() { serif(c, words, style) }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let centred_line : @ui.Style = @ui.css("w=Full align=ACenter")

///|
/// A column: its title, each figure a line (what, then how much).
fn paper_column(c : @ui.Ctx, title : String, stats : Array[(String, String)]) -> Unit {
  c.box(style=paper_column_box, fn() {
    serif(c, title, paper_column_title)
    for x in stats {
      c.box(style=pic_other, fn() {
        serif(c, x.0, paper_line)
        c.box(style=pic_grow, fn() {  }) |> ignore
        serif(c, x.1, paper_value)
      })
      |> ignore
    }
  })
  |> ignore
}

// ── 黄历 ───────────────────────────────────────────────────────────────────

///|
/// 黄历: an almanac's day: its paper and its vermilion; the day large; 宜 (what the agents did: the chats at work, the
/// tasks across devices, today's chats archived) and 忌 (what a person need not do now) each its mark in a square and
/// its lines; the share at its foot, still.fail's line.
fn almanac_look(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let s = said_of(fleet)
  look_box(c, id, flat, @sf.share_almanac_ground, fn() {
    c.box(style=almanac_band, fn() {
      c.box(style=pic_grow, fn() { serif(c, "still.fail", almanac_band_words) }) |> ignore
      serif(c, s.at, almanac_band_words)
    })
    |> ignore
    c.box(style=almanac_day, fn() {
      serif_centred(c, day_of(s.at), almanac_big)
      serif_centred(c, s.where_, almanac_small_line)
    })
    |> ignore
    let good : Array[String] = [s.chats_text]
    if s.tasks != "" {
      good.push(s.tasks)
    }
    if s.today.length() > 0 {
      good.push(s.today[0].0 + " " + s.today[0].1)
    }
    almanac_row(c, @sf.t("web-main.stations.shareGood"), good, almanac_mark_good)
    almanac_row(
      c,
      @sf.t("web-main.stations.shareAvoid"),
      [@sf.t("web-main.stations.shareAvoidCode"), @sf.t("web-main.stations.shareAvoidWatch")],
      almanac_mark_avoid,
    )
    if s.lead != "" {
      serif(c, s.lead + " " + s.number + " " + s.of, almanac_small)
    }
    serif(c, @sf.t("web-main.stations.shareTagline"), almanac_small)
  })
}

///|
/// The day of `at` (10月26日 04:12: 10月26日; Oct 26, 04:12: Oct 26): what is before its time.
fn day_of(at : String) -> String {
  // (up to its last space, a comma before it left out)
  let chars : Array[Char] = []
  for ch in at {
    chars.push(ch)
  }
  let mut end = chars.length()
  for i in 0..<chars.length() {
    if chars[i] == ' ' {
      end = i
    }
  }
  if end == chars.length() {
    return at
  }
  if end > 0 && chars[end - 1] == ',' {
    end = end - 1
  }
  String::from_array(chars[:end].to_array())
}

///|
/// A row of the almanac: its mark in a square, its lines beside it.
fn almanac_row(c : @ui.Ctx, mark : String, lines : Array[String], mark_style : @ui.Style) -> Unit {
  c.box(style=almanac_row_box, fn() {
    c.box(style=mark_style, fn() { serif(c, mark, almanac_mark_words) }) |> ignore
    c.box(style=almanac_lines, fn() {
      for l in lines {
        serif(c, l, almanac_line)
      }
    })
    |> ignore
  })
  |> ignore
}

// ── 登机牌 ─────────────────────────────────────────────────────────────────

///|
/// 登机牌: a boarding pass from the person's devices to still.fail: its airline's band; from and to large; the flight
/// (SF and the share's figures), the day, the seat (the chats at work), the gate (the first kind's accounts); a torn
/// line to its stub, the stub's barcode and the week's spend as its fare.
fn boarding_look(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let s = said_of(fleet)
  let flight = "SF" + digits_of(s.number).to_string()
  let gate = match s.first {
    Some(_) => "S" + count(s.first, "accounts").to_string()
    None => "S1"
  }
  look_box(c, id, flat, @sf.share_boarding_ground, fn() {
    c.box(style=boarding_band, fn() {
      c.box(style=pic_grow, fn() { c.text("still.fail ✈", style=boarding_band_words) |> ignore }) |> ignore
      c.text(@sf.t("web-main.stations.shareBoarding"), style=boarding_band_words) |> ignore
    })
    |> ignore
    c.box(style=boarding_route, fn() {
      boarding_end(c, @sf.t("web-main.stations.shareFrom"), "DEV", @sf.t("web-main.stations.shareYourDevices"))
      c.box(style=pic_grow, fn() { c.text("- - - ✈ - - -", style=boarding_plane) |> ignore }) |> ignore
      boarding_end(c, @sf.t("web-main.stations.shareTo"), "SFL", "still.fail")
    })
    |> ignore
    c.box(style=boarding_fields, fn() {
      boarding_field(c, @sf.t("web-main.stations.shareFlight"), flight)
      boarding_field(c, @sf.t("web-main.stations.shareSeat"), s.chats.to_string() + "A")
      boarding_field(c, @sf.t("web-main.stations.shareGate"), gate)
    })
    |> ignore
    c.box(style=boarding_fields, fn() {
      boarding_field(c, @sf.t("web-main.stations.sharePassenger"), "AGENTS")
      boarding_field(c, @sf.t("web-main.stations.shareDate"), day_of(s.at))
    })
    |> ignore
    if s.lead != "" {
      c.text(s.lead + " " + s.number + " " + s.of, style=boarding_note) |> ignore
    }
    dashes(c)
    c.box(style=boarding_stub, fn() {
      barcode(c, flight + s.at + s.chats_text)
      c.box(style=boarding_fare, fn() {
        c.text(if s.week.length() > 0 { s.week[s.week.length() - 1].0 } else { "" }, style=boarding_key) |> ignore
        code_words(c, week_value(s, 2), boarding_fare_value)
      })
      |> ignore
    })
    |> ignore
    c.text(@sf.t("web-main.stations.shareTagline"), style=boarding_key) |> ignore
  })
}

///|
/// An end of the route: what it is, its code large, its name.
fn boarding_end(c : @ui.Ctx, what : String, code : String, name : String) -> Unit {
  c.box(style=boarding_end_box, fn() {
    c.text(what, style=boarding_key) |> ignore
    code_words(c, code, boarding_code)
    c.text(name, style=boarding_name) |> ignore
  })
  |> ignore
}

///|
/// A field: what it is over its value.
fn boarding_field(c : @ui.Ctx, key : String, value : String) -> Unit {
  c.box(style=boarding_field_box, fn() {
    c.text(key, style=boarding_key) |> ignore
    code_words(c, value, boarding_value)
  })
  |> ignore
}

// ── 奖状 ───────────────────────────────────────────────────────────────────

///|
/// 奖状: a certificate of merit: its red, its gold rims and stars; 奖状 large; presented to the agents of still.fail for
/// what they did (the first kind's share, the tasks across devices, the chats at work), its closing words; the day and
/// a round seal of still.fail.
fn award_look(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let s = said_of(fleet)
  look_box(c, id, flat, @sf.share_award_red, fn() {
    serif_centred(c, "★  ★  ★", award_stars)
    c.box(style=award_rim, fn() {
      c.box(style=award_paper, fn() {
        serif_centred(c, @sf.t("web-main.stations.shareAward"), award_title)
        serif(c, @sf.t("web-main.stations.shareAwardTo"), award_words)
        let deeds = StringBuilder()
        if s.lead != "" {
          deeds.write_string(s.lead + " " + s.number + " " + s.of + "；")
        }
        if s.tasks != "" {
          deeds.write_string(s.tasks + "；")
        }
        deeds.write_string(s.chats_text + "。")
        serif(c, deeds.to_string(), award_body)
        serif(c, @sf.t("web-main.stations.shareAwardEnd"), award_body)
        c.box(style=award_foot, fn() {
          c.box(style=pic_grow, fn() {  }) |> ignore
          c.box(style=award_sign, fn() {
            serif(c, "still.fail", award_words)
            serif(c, day_of(s.at), award_words)
          })
          |> ignore
          c.box(style=award_seal, fn() { serif(c, "s.", award_seal_words) }) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    serif_centred(c, @sf.t("web-main.stations.shareTagline"), award_stars)
  })
}

// ── 报纸's ─────────────────────────────────────────────────────────────────

///|
// kept across runs: a value (no field of it changes)
let paper_masthead : @ui.TextStyle = @ui.text_style(size=Xl4, weight=Bold, color=Data(@sf.share_paper_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let paper_small : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(@sf.share_paper_dim), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let paper_headline : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Bold, tracking=Tight, color=Data(@sf.share_paper_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let paper_deck : @ui.TextStyle = @ui.text_style(size=Base, color=Data(@sf.share_paper_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let paper_story : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_paper_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let paper_column_title : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_paper_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let paper_line : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(@sf.share_paper_dim), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let paper_value : @ui.TextStyle = @ui.text_style(size=Xs, weight=Bold, color=Data(@sf.share_paper_ink), wrap=false)

///|
/// Its rules: a hairline of its ink, a heavy one at its head and foot, two together under the masthead.
// kept across runs: a value (no field of it changes)
let paper_rule : @ui.Style = @ui.css("w=Full h=SPx").then(@ui.style(bg=Data(@sf.share_paper_ink)))

///|
// kept across runs: a value (no field of it changes)
let paper_rule_thick : @ui.Style = @ui.css("w=Full h=S1").then(@ui.style(bg=Data(@sf.share_paper_ink)))

///|
// kept across runs: a value (no field of it changes)
let paper_double : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
/// The columns side by side, a rule between them, 12 apart.
// kept across runs: a value (no field of it changes)
let paper_columns : @ui.Style = @ui.css("row w=Full gap=S3 align=AStretch")

///|
// kept across runs: a value (no field of it changes)
let paper_column_box : @ui.Style = @ui.css("gap=S1").then(@ui.style(w=@sf.grow))

///|
// kept across runs: a value (no field of it changes)
let paper_column_rule : @ui.Style = @ui.css("w=SPx").then(@ui.style(bg=Data(@sf.share_paper_ink)))

// ── 黄历's ─────────────────────────────────────────────────────────────────

///|
/// Its band: the vermilion, its words the paper, 12 and 8 in.
// kept across runs: a value (no field of it changes)
let almanac_band : @ui.Style = @ui.css("row w=Full px=S3 py=S2 align=ACenter").then(
  @ui.style(bg=Data(@sf.share_almanac_red), radius=@sf.small_radius),
)

///|
// kept across runs: a value (no field of it changes)
let almanac_band_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_almanac_ground), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let almanac_day : @ui.Style = @ui.css("w=Full gap=S1 align=ACenter py=S3")

///|
// kept across runs: a value (no field of it changes)
let almanac_big : @ui.TextStyle = @ui.text_style(size=Xl5, weight=Bold, color=Data(@sf.share_almanac_red), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let almanac_small : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_almanac_dim), center=true, w=Full)

///|
// kept across runs: a value (no field of it changes)
let almanac_small_line : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_almanac_dim), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let almanac_row_box : @ui.Style = @ui.css("row w=Full gap=S4 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let almanac_mark_good : @ui.Style = @ui.css("w=S14 h=S14 align=ACenter justify=JCenter").then(
  @ui.style(bg=Data(@sf.share_almanac_red)),
)

///|
// kept across runs: a value (no field of it changes)
let almanac_mark_avoid : @ui.Style = @ui.css("w=S14 h=S14 align=ACenter justify=JCenter").then(
  @ui.style(bg=Data(@sf.share_almanac_ink)),
)

///|
// kept across runs: a value (no field of it changes)
let almanac_mark_words : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Bold, color=Data(@sf.share_almanac_ground), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let almanac_lines : @ui.Style = @ui.css("gap=S1 pt=S0_5").then(@ui.style(w=@sf.grow))

///|
// kept across runs: a value (no field of it changes)
let almanac_line : @ui.TextStyle = @ui.text_style(size=Base, weight=Medium, color=Data(@sf.share_almanac_ink), w=Full)

// ── 登机牌's ───────────────────────────────────────────────────────────────

///|
// kept across runs: a value (no field of it changes)
let boarding_band : @ui.Style = @ui.css("row w=Full px=S3 py=S2_5 align=ACenter").then(
  @ui.style(bg=Data(@sf.share_boarding_blue), radius=@sf.small_radius),
)

///|
// kept across runs: a value (no field of it changes)
let boarding_band_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let boarding_route : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter py=S2")

///|
// kept across runs: a value (no field of it changes)
let boarding_end_box : @ui.Style = @ui.css("gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let boarding_code : @ui.TextStyle = @ui.text_style(size=Xl4, weight=Bold, color=Data(@sf.share_boarding_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let boarding_name : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(@sf.share_boarding_dim), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let boarding_plane : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_boarding_blue), center=true, w=Full)

///|
// kept across runs: a value (no field of it changes)
let boarding_fields : @ui.Style = @ui.css("row w=Full gap=S3")

///|
// kept across runs: a value (no field of it changes)
let boarding_field_box : @ui.Style = @ui.css("gap=S0_5").then(@ui.style(w=@sf.grow))

///|
// kept across runs: a value (no field of it changes)
let boarding_key : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(@sf.share_boarding_dim), w=Full)

///|
// kept across runs: a value (no field of it changes)
let boarding_value : @ui.TextStyle = @ui.text_style(size=Lg, weight=Bold, color=Data(@sf.share_boarding_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let boarding_note : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Data(@sf.share_boarding_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let boarding_stub : @ui.Style = @ui.css("row w=Full gap=S4 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let boarding_fare : @ui.Style = @ui.css("gap=S0_5 align=AEnd").then(@ui.style(w=@sf.grow))

///|
// kept across runs: a value (no field of it changes)
let boarding_fare_value : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, color=Data(@sf.share_boarding_ink), wrap=false)

// ── 奖状's ─────────────────────────────────────────────────────────────────

///|
// kept across runs: a value (no field of it changes)
let award_stars : @ui.TextStyle = @ui.text_style(size=Xl, weight=Bold, color=Data(@sf.share_award_gold), wrap=false)

///|
/// Its gold rim round its paper, 3 thick, the paper's own rim a hairline of the gold 4 in.
// kept across runs: a value (no field of it changes)
let award_rim : @ui.Style = @ui.css("w=Full p=S1").then(@ui.style(bg=Data(@sf.share_award_gold)))

///|
// kept across runs: a value (no field of it changes)
let award_paper : @ui.Style = @ui.css("w=Full p=S5 gap=S3 border=B1").then(
  @ui.style(bg=Data(@sf.share_award_paper), border_color=Data(@sf.share_award_red)),
)

///|
// kept across runs: a value (no field of it changes)
let award_title : @ui.TextStyle = @ui.text_style(size=Xl5, weight=Bold, tracking=Widest, color=Data(@sf.share_award_red), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let award_words : @ui.TextStyle = @ui.text_style(size=Base, weight=Bold, color=Data(@sf.share_award_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let award_body : @ui.TextStyle = @ui.text_style(size=Base, color=Data(@sf.share_award_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let award_foot : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter pt=S2")

///|
// kept across runs: a value (no field of it changes)
let award_sign : @ui.Style = @ui.css("gap=S0_5 align=AEnd")

///|
/// The seal: a round of the red, its words in it.
// kept across runs: a value (no field of it changes)
let award_seal : @ui.Style = @ui.css("w=S16 h=S16 radius=Full border=B2 align=ACenter justify=JCenter").then(
  @ui.style(border_color=Data(@sf.share_award_red)),
)

///|
// kept across runs: a value (no field of it changes)
let award_seal_words : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Bold, color=Data(@sf.share_award_red), center=true, wrap=false)
