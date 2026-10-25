// The workspace's stations at a glance and the card to share of them (2026-10-26 用户：「需要有一个地方可以显示当前多少个
// chat 正在工作，有利于 app 传播」「hover 这个出一个卡片」「有个复制图片应该就行」). Over the rail's Station place, a
// card: how many agents are at work on them all, each station and what it is doing (the chats' view: its glyph's `now`,
// each station's `doing`, as the core says them), and while any agent is at work, 分享卡片. The card to share: a
// picture of the agents at work on the person's stations, copied whole to paste where others see it (a chat, a post):
// a poster of them (the `fleet` view): how many, where, each station at work, the models, the last 7 days, a QR code of
// still.fail's site beside its line; 复制图片 under it puts what is drawn of it on the clipboard.

///|
/// The stations of workspace `w` at a glance (the rail's Station place's hover card): how many agents are at work on
/// them all, a line each with what it is doing (red where it cannot be reached), and 分享卡片 while any is at work.
pub fn stations_now(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let chats = (src.topic)("chats", { "scope": Json::string(w.id), "mine": Json::boolean(false) }).value
  let glyph = field(chats, "glyph")
  c.box(style=now_box, fn() {
    c.text(stations_now_line(glyph), style=now_head) |> ignore
    c.box(style=now_rows, fn() {
      for s in items(chats, "stations") {
        let s = Some(s)
        c.box(style=now_row, fn() {
          c.box(style=now_name_room, fn() { c.text(text(s, "name"), style=now_name) |> ignore }) |> ignore
          c.text(text(s, "doing"), style=if text(s, "state") == "error" { now_doing_red } else { now_doing })
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
    if count(glyph, "running") > 0 {
      let id = c.id("stations-now/share")
      c.cursor(id, Hand)
      if c.clicked(id) {
        share_card_open(src, w)
      }
      c.box(style=now_share, id~, label=@sf.t("web-main.stations.shareCard"), fn() {
        @sf.icon(c, "photo", size=16.0, color=@sf.theme().p.text) |> ignore
        c.text(@sf.t("web-main.stations.shareCard"), style=now_share_words) |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// How many agents are at work, in a line (the glyph's `now`; from a core before it, its stations in words).
pub fn stations_now_line(glyph : Json?) -> String {
  match text(glyph, "now") {
    "" => text(glyph, "label")
    now => now
  }
}

///|
/// The card's parts 10 apart; the stations 6 apart.
// kept across runs: a value (no field of it changes)
let now_box : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let now_head : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let now_rows : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
/// A station's line: its name, what it is doing at its end.
// kept across runs: a value (no field of it changes)
let now_row : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
/// Its name's room: what what it is doing leaves of the line.
// kept across runs: a value (no field of it changes)
let now_name_room : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let now_name : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let now_doing : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let now_doing_red : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, wrap=false)

///|
/// 分享卡片: a block across the card at its foot, round as its corners (login_card's lc_open).
// kept across runs: a value (no field of it changes)
let now_share : @ui.Style = @ui.css(
  "row w=Full h=S8 mt=S1 px=S3 gap=S1_5 radius=Inner bg=A(Fg,O5) align=ACenter justify=JCenter hovered{bg=Hover}",
)

///|
// kept across runs: a value (no field of it changes)
let now_share_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false)

// ── the card to share ────────────────────────────────────────────────────

///|
/// The card to share of workspace `w`'s agents at work, opened by nothing (a dialog; a sheet to a finger): the picture
/// (share_picture), 复制图片 under it.
pub fn share_card_open(src : Source, w : Workspace) -> Unit {
  @sf.panel(
    @sf.t("web-main.stations.shareCard"),
    fn(c, _) { share_picture(c, src, w) },
    from=Unanchored,
    // (a dialog as wide as one of two columns wants: the poster lies its stations three a line in it)
    wide=true,
    // (its title said as it is drawn, in the language then)
    live=fn() { (@sf.t("web-main.stations.shareCard"), "", "") },
    foot=fn(c, _) {
      if @sf.button(c, @sf.t("desktop.contextMenu.copyImage"), key="share-card/copy", tone=Primary, icon="copy") {
        let picture = c.id(share_picture_key)
        // (once the frame's builds are over: the picture as the last frame drew it, read back by the host's renderer)
        c.tell("share-card/copy", fn() {
          match c.drawn_pixels(picture, inset=pic_copy_in) {
            @ui.PixelsRead(pw, ph, rgba) => {
              @ui.clipboard_set_png(@pixels.png(pw, ph, unpremultiplied(rgba)), label="still.fail")
              if !@ui.copy_shown() {
                say(c, @sf.t("common.copied"))
              }
            }
            _ => say(c, @sf.t("web-main.stations.shareFailed"))
          }
        })
      }
    },
  )
}

///|
/// The picture's key: what is copied is what was drawn of it.
let share_picture_key : String = "share-card/picture"

///|
/// The picture shared, a poster of the agents at work (the `fleet` view; 2026-10-26 用户：「来点花哨的设计和更多信息」):
/// on a night's ground with still.fail's orange and a violet glowing on it, the same in either theme: still.fail's
/// name; how many agents are at work, the number large, where they are under it; each station at work a tile, its name
/// and how many, its machine, a dot for each agent; the models at work; the last 7 days, their calls, tokens and cost
/// and each day's calls a bar, today's orange; still.fail's site as a QR code beside its line.
fn share_picture(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let fleet = (src.topic)("fleet", { "scope": Json::string(w.id) }).value
  let stations = items(fleet, "stations")
  let models = items(fleet, "models")
  let picture = c.id(share_picture_key)
  c.box(style=pic_box, id=picture, fn() {
    c.box(left=0.0, top=0.0, right=0.0, bottom=0.0, fn() {
      @sf.glow_ground(c, @sf.share_ground, pic_lights, pic_aspect, radius=pic_corner)
    })
    |> ignore
    c.rich([@ui.span("still"), @ui.span(".fail", color=@sf.share_orange)], style=pic_brand) |> ignore
    // the number, what follows it and where they are beside it, on its foot
    c.box(style=pic_hero, fn() {
      c.text(count(fleet, "running").to_string(), style=pic_number) |> ignore
      c.box(style=pic_hero_words, fn() {
        c.text(text(fleet, "unit"), style=pic_unit) |> ignore
        c.text(text(fleet, "where"), style=pic_where) |> ignore
      })
      |> ignore
    })
    |> ignore
    // the stations at work, three a line where the picture is wide enough, else two (the last line's room left kept:
    // each as wide), by the picture's own width
    let per = match c.laid_size(picture) {
      Some((pw, _)) if pw >= pic_three_from => 3
      _ => 2
    }
    c.box(style=pic_tiles, fn() {
      let mut k = 0
      while k < stations.length() {
        let end = if k + per < stations.length() { k + per } else { stations.length() }
        let line = stations[k:end].to_array()
        c.box(style=pic_tiles_line, fn() {
          for s in line {
            pic_tile(c, Some(s))
          }
          if stations.length() > line.length() {
            for _ in line.length()..<per {
              c.box(style=pic_tile_room, fn() {  }) |> ignore
            }
          }
        })
        |> ignore
        k += per
      }
    })
    |> ignore
    if models.length() > 0 {
      c.box(style=pic_chips, flow=true, line_gap=pic_chips_gap, fn() {
        for m in models {
          let m = Some(m)
          c.box(style=pic_chip, fn() {
            c.rich([@ui.span(text(m, "name")), @ui.span(" " + text(m, "text"), color=@sf.share_dim)], style=pic_chip_words)
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    }
    match field(fleet, "week") {
      Some(Object(_)) as week => pic_week(c, week)
      _ => ()
    }
    c.box(style=pic_foot, fn() {
      @sf.qr_code(c, Some(site_qr), pic_qr, @sf.t("web-main.stations.shareQr"))
      c.box(style=pic_line, fn() {
        c.text(@sf.t("web-main.stations.shareTagline"), style=pic_tagline) |> ignore
        c.text(@sf.t("web-main.stations.shareQr"), style=pic_scan) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A station at work as a tile: its name and how many at the line's ends, its machine under them, a dot for each agent
/// (so many, then +N).
fn pic_tile(c : @ui.Ctx, s : Json?) -> Unit {
  let n = count(s, "running")
  let _ = c.box(style=pic_tile_room, fn() {
    c.box(style=pic_tile_box, fn() {
      c.box(style=pic_tile_head, fn() {
        c.box(style=pic_grow, fn() { c.text(text(s, "name"), style=pic_tile_name) |> ignore }) |> ignore
        c.text(n.to_string(), style=pic_tile_n) |> ignore
      })
      |> ignore
      match text(s, "machine") {
        "" => ()
        machine => c.text(machine, style=pic_tile_machine) |> ignore
      }
      c.box(style=pic_dots, fn() {
        for _ in 0..<(if n < pic_dots_most { n } else { pic_dots_most }) {
          c.box(style=pic_dot, fn() {  }) |> ignore
        }
        if n > pic_dots_most {
          c.text("+" + (n - pic_dots_most).to_string(), style=pic_more) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// The last 7 days: their title, their calls, tokens and cost side by side, each day's calls a bar (today's orange).
fn pic_week(c : @ui.Ctx, week : Json?) -> Unit {
  c.box(style=pic_week_box, fn() {
    c.text(text(week, "title"), style=pic_where) |> ignore
    c.box(style=pic_stats, fn() {
      for x in items(week, "stats") {
        let x = Some(x)
        c.box(style=pic_stat, fn() {
          c.text(text(x, "value"), style=pic_stat_value) |> ignore
          c.text(text(x, "label"), style=pic_stat_label) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
    c.box(style=pic_bars, fn() {
      for d in items(week, "days") {
        let d = Some(d)
        let h = dmax(pic_bar_least, number(d, "share") * pic_bars_h)
        let ground = if flag(d, "today") { @sf.share_orange } else { @sf.share_bar }
        c.box(style=pic_bar.then(@ui.style(h=Fixed(h), bg=Data(ground))), fn() {  }) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The picture: 28 in (past its corner: what is at its edges stands clear of it), its parts 12 apart, round as a card,
/// on the night's ground (what is drawn on it seen against that), its glow over it clipped to it.
// kept across runs: a value (no field of it changes)
let pic_box : @ui.Style = @ui.css("w=Full p=S7 gap=S3 radius=Xl3 clip").then(@ui.style(bg=Data(@sf.share_ground)))

///|
/// How wide the picture is where its stations go three a line (a dialog's), else two (a phone's sheet).
let pic_three_from : Double = 480.0

///|
/// Its corner (Xl3's), its glow's picture's.
let pic_corner : Double = 24.0

///|
/// What is copied of the picture: its rectangle this far in from each side, its round corners (24) left out of it, so
/// the picture copied is its ground to its edges.
let pic_copy_in : Double = 8.0

///|
/// The glow's picture made in a poster's proportion (4 by 5), stretched over the picture whatever it holds.
let pic_aspect : Double = 0.8

///|
/// still.fail's orange at its top left, a violet at its right, the orange again faint at its foot.
// kept across runs: a table, never written
let pic_lights : Array[@sf.Glow] = [
  { x: 0.08, y: 0.02, r: 0.95, color: @sf.share_glow_orange },
  { x: 1.05, y: 0.42, r: 0.8, color: @sf.share_glow_violet },
  { x: 0.25, y: 1.02, r: 0.7, color: @sf.share_glow_orange },
]

///|
// kept across runs: a value (no field of it changes)
let pic_brand : @ui.TextStyle = @ui.text_style(size=Title, weight=Bold, color=Data(@sf.share_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pic_hero : @ui.Style = @ui.css("row w=Full gap=S3 align=AEnd")

///|
/// What follows the number and where they are, on the number's foot.
// kept across runs: a value (no field of it changes)
let pic_hero_words : @ui.Style = @ui.css("gap=S1 pb=S2").then(@ui.style(w=@sf.grow))

///|
/// The number, as large as a picture's one number is (the scale's past its words', Xl7 72), drawn tight.
// kept across runs: a value (no field of it changes)
let pic_number : @ui.TextStyle = @ui.text_style(size=Xl7, weight=Bold, tracking=Tight, color=Data(@sf.share_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pic_unit : @ui.TextStyle = @ui.text_style(size=Heading, weight=Semibold, color=Data(@sf.share_ink), wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let pic_where : @ui.TextStyle = @ui.text_style(size=Ui, color=Data(@sf.share_dim), wrap=false, w=Cut)

///|
/// The stations' tiles, 10 apart each way.
// kept across runs: a value (no field of it changes)
let pic_tiles : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let pic_tiles_line : @ui.Style = @ui.css("row w=Full gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let pic_tile_room : @ui.Style = @ui.style(w=@sf.grow)

///|
/// A tile: on white thinned over the ground, 12 in, round, its lines 4 apart.
// kept across runs: a value (no field of it changes)
let pic_tile_box : @ui.Style = @ui.css("w=Full p=S3 gap=S1 radius=Xl").then(@ui.style(bg=Data(@sf.share_tile)))

///|
// kept across runs: a value (no field of it changes)
let pic_tile_head : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pic_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let pic_tile_name : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Data(@sf.share_ink), wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let pic_tile_n : @ui.TextStyle = @ui.text_style(size=Title, weight=Bold, color=Data(@sf.share_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pic_tile_machine : @ui.TextStyle = @ui.text_style(size=Meta, color=Data(@sf.share_dim), wrap=false, w=Cut)

///|
/// A dot for each agent at work: 6, 4 apart, still.fail's orange.
// kept across runs: a value (no field of it changes)
let pic_dots : @ui.Style = @ui.css("row gap=S1 align=ACenter pt=S1")

///|
// kept across runs: a value (no field of it changes)
let pic_dot : @ui.Style = @ui.css("w=S1_5 h=S1_5 radius=Full").then(@ui.style(bg=Data(@sf.share_orange)))

///|
let pic_dots_most : Int = 12

///|
// kept across runs: a value (no field of it changes)
let pic_more : @ui.TextStyle = @ui.text_style(size=Caption, color=Data(@sf.share_dim), wrap=false)

///|
/// The models at work as chips, 6 apart each way.
// kept across runs: a value (no field of it changes)
let pic_chips : @ui.Style = @ui.css("row w=Full gap=S1_5")

///|
let pic_chips_gap : Double = 6.0

///|
// kept across runs: a value (no field of it changes)
let pic_chip : @ui.Style = @ui.css("px=S2_5 py=S1 radius=Full").then(@ui.style(bg=Data(@sf.share_tile)))

///|
// kept across runs: a value (no field of it changes)
let pic_chip_words : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Data(@sf.share_ink), wrap=false)

///|
/// The last 7 days: their title, their figures, their bars, 8 apart.
// kept across runs: a value (no field of it changes)
let pic_week_box : @ui.Style = @ui.css("w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let pic_stats : @ui.Style = @ui.css("row w=Full gap=S3")

///|
// kept across runs: a value (no field of it changes)
let pic_stat : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let pic_stat_value : @ui.TextStyle = @ui.text_style(size=Title, weight=Bold, color=Data(@sf.share_ink), wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let pic_stat_label : @ui.TextStyle = @ui.text_style(size=Caption, color=Data(@sf.share_dim), wrap=false, w=Cut)

///|
/// Each day's bar, side by side 6 apart, standing on the row's foot as tall as its calls' share of the busiest's 28
/// (4 at least: a day with none still seen).
// kept across runs: a value (no field of it changes)
let pic_bars : @ui.Style = @ui.css("row w=Full gap=S1_5 align=AEnd").then(@ui.style(h=Fixed(pic_bars_h)))

///|
let pic_bars_h : Double = 28.0

///|
let pic_bar_least : Double = 4.0

///|
// kept across runs: a value (no field of it changes)
let pic_bar : @ui.Style = @ui.css("radius=Sm").then(@ui.style(w=@sf.grow))

///|
/// Its foot: the QR code, still.fail's line beside it, 14 apart.
// kept across runs: a value (no field of it changes)
let pic_foot : @ui.Style = @ui.css("row w=Full gap=S3_5 align=ACenter")

///|
/// The QR code's side: 33 modules (25 and the quiet zone's 4 round them) of 2 each.
let pic_qr : Double = 66.0

///|
// kept across runs: a value (no field of it changes)
let pic_line : @ui.Style = @ui.css("gap=S1")

///|
// kept across runs: a value (no field of it changes)
let pic_tagline : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Data(@sf.share_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pic_scan : @ui.TextStyle = @ui.text_style(size=Meta, color=Data(@sf.share_dim), wrap=false)

///|
/// still.fail's site as a QR code, as the core makes one (qr.ts `qr("https://still.fail")`: 25 modules a side, `1`
/// dark): what the picture's QR code opens.
// kept across runs: a value (no field of it changes)
let site_qr : Json = {
  "size": 25,
  "rows": [
    "1111111000000100101111111", "1000001000010011101000001", "1011101010010001001011101", "1011101011100000001011101",
    "1011101010100100101011101", "1000001011000111101000001", "1111111010101010101111111", "0000000011111101000000000",
    "1011111001010011001111100", "1010110110001000110100010", "1101101100101001011111011", "0011100110111010101000001",
    "1110101011010001011110111", "1001110000001110100101010", "1000101111000111000111011", "1000100101001100111110001",
    "1011011001101010111110100", "0000000010100001100011000", "1111111001011000101010111", "1000001010110011100011000",
    "1011101011110001111110101", "1011101010001111011011111", "1011101011000110100001101", "1000001000001101110111001",
    "1111111010101010001111111",
  ],
}
