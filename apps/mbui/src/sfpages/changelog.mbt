// What the last update brought, at the top of the chats' lists until it is seen (ember web/src/mobile/Changelog.tsx
// ChangelogNews; the `changelog` topic's `news`), where the frame puts it (the phone's Home: beside the wide frame's
// rail the web says it in a bubble of its own, cloud/workspace.tsx): the build it is now and its first three changes,
// a press opens the changelog; its × lets it go at once and tells the core (`changelog.seen`).

///|
/// The news let go here (before the core has it): none shows while the core's is this one.
let news_gone : Ref[Json?] = Ref(None)

///|
/// As at the start (tests).
fn news_reset() -> Unit {
  news_gone.val = None
}

///|
/// The news as the core has it, unless let go here.
pub fn news_of(src : Source) -> Json? {
  match field((src.topic)("changelog", Map::new()).value, "news") {
    Some(Object(_)) as n if news_gone.val != n => n
    _ => None
  }
}

///|
/// Its room in the list: 12 from the sides, 4 over it, 10 under.
// kept across runs: a value (no field of it changes)
let news_room : @ui.Style = @ui.css("w=Full px=S3 pt=S1 pb=S2_5")

///|
/// The card (22 round: its × 6 in, and its half, on the surface).
// kept across runs: a value (no field of it changes)
let news_card : @ui.Style = @ui.css("w=Full radius=Xl3 bg=Surface clip")

///|
/// What it says, 16 in (44 on the right, for the ×), 12 over and under, its lines 2 apart; rippled where it is pressed.
// kept across runs: a value (no field of it changes)
let news_words : @ui.Style = @ui.css("w=Full pl=S4 pr=S11 pt=S3 pb=S3 gap=S0_5")

///|
/// Its head: the sparks and the build, 6 apart, 2 over the lines.
// kept across runs: a value (no field of it changes)
let news_head : @ui.Style = @ui.css("row pb=S0_5 gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let news_title : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Fg, wrap=false)

///|
/// A change (13 on 18, muted, one line).
// kept across runs: a value (no field of it changes)
let news_line : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, leading=L5, wrap=false, w=Full)

///|
/// Its ×: 32, round, 6 from the card's top and right.
// kept across runs: a value (no field of it changes)
let news_close_place : @ui.Style = @ui.css("w=Full p=S1_5 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let news_close : @ui.Style = @ui.css("w=S8 h=S8 radius=Full align=ACenter justify=JCenter")

///|
/// How many of its changes it says before "还有 n 项".
let news_lines_most : Int = 3

///|
/// The news card at a chats' list's top, while there is news.
pub fn changelog_news(c : @ui.Ctx, src : Source) -> Unit {
  let news = match news_of(src) {
    Some(n) => Some(n)
    None => return
  }
  let t = @sf.theme()
  let lines : Array[String] = []
  for e in items(news, "entries") {
    for l in items(Some(e), "text") {
      match l {
        String(s) => lines.push(s)
        _ => ()
      }
    }
  }
  c.box(style=news_room, fn() {
    c.box(style=news_card, fn() {
      let open = c.id("changelog-news")
      if c.clicked(open) {
        open_page(Setting(@settings.Route::Changelog))
      }
      c.box(style=news_words, id=open, fn() {
        c.box(style=news_head, fn() {
          @sf.icon(c, "sparks", size=16.0, color=t.p.text) |> ignore
          c.text(
            match @sfbase.opt_text(news, "build") {
              Some(b) => @sf.t("android-settings.changelog.updatedTo", args=[("build", b)])
              None => @sf.t("android-settings.changelog.updated")
            },
            style=news_title,
          )
          |> ignore
        })
        |> ignore
        for i, l in lines {
          if i >= news_lines_most {
            break
          }
          c.text(l, style=news_line) |> ignore
        }
        if lines.length() > news_lines_most {
          c.text(@sf.t("android-settings.changelog.more", args=[("n", (lines.length() - news_lines_most).to_string())]), style=news_line)
          |> ignore
        }
        // PageParts.kt ChangelogNews: clickable, cut to the card's corners
        @motion.ripple(c, open, 0.0)
      })
      |> ignore
      // let go: gone at once, the core told
      c.layer(fn() {
        c.box(style=news_close_place, fn() {
          let close = c.id("changelog-news/close")
          if c.clicked(close) {
            news_gone.val = news
            (src.call)("changelog.seen", Json::object({}), fn(_) {  })
          }
          c.box(style=news_close, id=close, label=@sf.t("android-settings.changelog.dismiss"), fn() {
            @sf.icon(c, "close", size=16.0, color=t.p.muted) |> ignore
            @motion.ripple(c, close, 16.0)
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
}
