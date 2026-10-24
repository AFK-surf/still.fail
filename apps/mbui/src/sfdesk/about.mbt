// 关于 and 更新日志 on the desktop (ember web/src/pages/About.tsx; Changelog.tsx, Changelog.css.ts). 关于: whether this
// device sends usage statistics and error reports, on a card (not where nothing is sent), and still.fail's terms and
// privacy policy on its site. 更新日志: the core's `changelog`, a tab a part, by day, each change's lines with their
// kind before them and its version at the end of the first, what is not out yet under them; opened, what the last
// update brought is read (`changelog.seen`).

///|
/// 关于 (AboutPage).
fn about_page(c : @ui.Ctx, core : Core) -> Unit {
  let t = @sf.theme()
  let blocks : Array[() -> Unit] = []
  // a build that sends nothing has nothing to turn off
  match (core.reporting)() {
    Some(on) =>
      blocks.push(fn() {
        @sf.section(c, @sf.t("web-pages.about.privacy"), fn() {
          c.box(style=desk_card, fn() {
            let now = @sf.switch_row(
              c,
              "about/reporting",
              @sf.t("common.telemetry.title"),
              on,
              note=@sf.t("common.telemetry.note", args=[("name", "still.fail")]),
            )
            if now != on {
              (core.set_reporting)(now)
            }
          })
          |> ignore
        })
      })
    None => ()
  }
  // on still.fail's site, in the browser
  blocks.push(fn() {
    @sf.section(c, @sf.t("web-pages.about.legal"), fn() {
      c.box(style=desk_list, fn() {
        for l in [("terms", "common.legal.terms"), ("privacy", "common.legal.privacy")] {
          let id = c.id("about/" + l.0)
          c.cursor(id, Hand)
          if c.clicked(id) {
            (core.open_link)(@settings.legal_url(l.0))
          }
          let b = c.box(style=desk_list_link, id~, fn() {
            c.box(style=desk_list_text, fn() { c.text(@sf.t(l.1), style=desk_list_title) |> ignore }) |> ignore
            @sf.icon(c, "arrow-up-right", size=desk_chevron, color=t.p.muted) |> ignore
          })
          c.semantics(b, Link, id~, label=@sf.t(l.1))
        }
      })
      |> ignore
    })
  })
  desk_page(c, core, "about", @sf.t("web-pages.settings.nav.about"), blocks)
}

///|
/// The changelog's part in view ("" the first) and whether its news was told read while it is open.
// kept across runs: said by its tabs and as it opens; changelog_reset puts them back
let changelog_part : Ref[String] = Ref("")

///|
// kept across runs: said as the page opens; changelog_reset puts it back
let changelog_seen : Ref[Bool] = Ref(false)

///|
fn changelog_reset() -> Unit {
  changelog_part.val = ""
  changelog_seen.val = false
}

///|
/// 更新日志 (ChangelogPage).
fn changelog_page(c : @ui.Ctx, core : Core) -> Unit {
  let topic = (core.topic)("changelog", Map([]))
  let v = topic.value
  // opened: what the update brought is read
  if has(v, "news") && !changelog_seen.val {
    changelog_seen.val = true
    c.tell("changelog.seen", fn() { (core.call)("changelog.seen", obj([]), fn(_) {  }) })
  }
  let tabs = items(v, "tabs")
  let at = match tabs.search_by(fn(x) { text(Some(x), "part") == changelog_part.val }) {
    Some(i) => i
    None => 0
  }
  let blocks : Array[() -> Unit] = []
  if tabs.length() > 0 {
    blocks.push(fn() {
      c.box(style=cl_tabs_row, fn() {
        let i = @sf.segmented(c, "changelog/tabs", tabs.map(fn(x) { text(Some(x), "label") }), at, item_w=cl_tab_w)
        if i != at {
          changelog_part.val = text(Some(tabs[i]), "part")
        }
      })
      |> ignore
    })
  }
  if v is None || flag(v, "loading") {
    blocks.push(fn() {
      @sf.waiting(
        c,
        count=5,
        error=match topic.error {
          Some(e) => @settings.error_text(e)
          None => ""
        },
      )
    })
  } else if has(v, "error") {
    blocks.push(fn() { c.text(text(v, "error"), style=desk_note_bad) |> ignore })
  } else {
    let days = match tabs.get(at) {
      Some(x) => items(Some(x), "days")
      None => []
    }
    if days.length() == 0 {
      blocks.push(fn() { c.text(@sf.t("web-pages.changelog.empty"), style=desk_muted) |> ignore })
    }
    for day in days {
      blocks.push(fn() {
        c.box(style=cl_day, fn() {
          c.box(style=cl_heading_room, fn() { c.text(text(Some(day), "label"), style=cl_heading) |> ignore }) |> ignore
          for e in items(Some(day), "entries") {
            change_item(c, Some(e))
          }
        })
        |> ignore
      })
    }
  }
  desk_page(
    c,
    core,
    "changelog/" + at.to_string(),
    @sf.t("web-pages.settings.nav.changelog"),
    lead=if has(v, "build") && !(field(v, "build") is Some(Null)) {
      @sf.t("web-pages.changelog.build", args=[("build", count(v, "build").to_string())])
    } else {
      ""
    },
    blocks,
  )
}

///|
/// One change (Change): each line with its kind before it (a small label, the accent's for something new; none: its
/// room kept), its version at the end of the first; under them what is not out yet (in the accent where an update
/// would bring it).
fn change_item(c : @ui.Ctx, e : Json?) -> Unit {
  c.box(style=cl_change, fn() {
    for i, l in items(e, "lines") {
      let lv = Some(l)
      c.box(style=cl_row, fn() {
        c.box(style=cl_kind_room, fn() {
          if text(lv, "label") != "" {
            let fresh = text(lv, "kind") == "new"
            c.box(style=if fresh { cl_kind_new } else { cl_kind }, fn() {
              c.text(text(lv, "label"), style=if fresh { cl_kind_new_words } else { cl_kind_words }) |> ignore
            })
            |> ignore
          }
        })
        |> ignore
        c.text(text(lv, "text"), style=cl_line) |> ignore
        if i == 0 {
          c.text(text(e, "versionName"), style=cl_version) |> ignore
        }
      })
      |> ignore
    }
    if text(e, "note") != "" {
      // under the words (62 in: the kind's room and the gap after it)
      c.box(style=cl_row, fn() {
        c.box(style=cl_kind_room, fn() {  }) |> ignore
        c.text(text(e, "note"), style=if field(e, "has") is Some(False) { cl_note_new } else { cl_note }) |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

// ── styles (Changelog.css.ts) ───────────────────────────────────────────

///|
/// A tab a part, under the title (tabsRow: 8 over what follows; tabs: 360 wide at least).
// kept across runs: a value (no field of it changes)
let cl_tabs_row : @ui.Style = @ui.css("row w=Full pb=S2")

///|
let cl_tab_w : Double = 120.0

///|
/// A day (heading: 20 over it, 10 in, 2 under; meta, medium, muted), its changes under it.
// kept across runs: a value (no field of it changes)
let cl_day : @ui.Style = @ui.css("w=Full pt=S5 gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let cl_heading : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, weight=Medium, color=Muted, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let cl_heading_room : @ui.Style = @ui.css("w=Full px=S2_5")

///|
/// A change (change: 8 by 10 in, its lines 4 apart).
// kept across runs: a value (no field of it changes)
let cl_change : @ui.Style = @ui.css("w=Full px=S2_5 py=S2 gap=S1")

///|
/// A line (row: its kind in 52, 10 apart, its words, the version at its end).
// kept across runs: a value (no field of it changes)
let cl_row : @ui.Style = @ui.css("row w=Full gap=S2_5 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let cl_kind_room : @ui.Style = @ui.style(w=Fixed(cl_kind_w), align=AStart)

///|
/// (row: its kind in 52)
let cl_kind_w : Double = 52.0

///|
/// Its kind (kind: 6 in, 18 high, round 6; muted on the neutral ground, the accent's for something new).
// kept across runs: a value (no field of it changes)
let cl_kind : @ui.Style = @ui.css("px=S1_5 radius=Base bg=Neutral")

///|
// kept across runs: a value (no field of it changes)
let cl_kind_new : @ui.Style = @ui.css("px=S1_5 radius=Base bg=AccentBg")

///|
// kept across runs: a value (no field of it changes)
let cl_kind_words : @ui.TextStyle = @ui.text_style(size=Xs2, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cl_kind_new_words : @ui.TextStyle = @ui.text_style(size=Xs2, leading=L5, color=AccentText, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cl_line : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5, color=Fg, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let cl_version : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Subtle, wrap=false)

///|
/// What is not out yet (note: meta, muted; the accent's where an update would bring it).
// kept across runs: a value (no field of it changes)
let cl_note : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let cl_note_new : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=AccentText, w=@sf.grow)
