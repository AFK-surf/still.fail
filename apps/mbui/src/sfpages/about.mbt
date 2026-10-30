// 关于 and 更新日志, one page each in every frame (ember web/src/pages/About.tsx, Changelog.tsx, Changelog.css.ts; the
// narrow app's mobile/Settings.tsx AboutScreen, mobile/Changelog.tsx). 关于: this build, the way to a newer one,
// what changed; whether this device sends usage statistics and error reports (not where nothing is sent); still.fail's
// terms and privacy policy on its site; last, where the device keeps one, its performance record (性能记录: what
// warms it, kept on the device alone, @hostapi.perf_state). 更新日志: the core's `changelog`, a tab a part, by day,
// each change's lines with their kind before them, its version, what is not out yet; opened, what the last update
// brought is read (`changelog.seen`). Laid out by the page's width (page_look.mbt).

///|
/// 关于 (AboutPage; the narrow app's AboutScreen, Android's SettingsHome.kt AboutScreen): this build and the way to a
/// newer one, what changed; whether this device sends usage statistics and error reports (not where nothing is sent);
/// still.fail's terms and privacy policy on its site.
pub fn about_page(c : @ui.Ctx, core : Core, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let blocks : Array[() -> Unit] = []
  // this build, and what changed
  blocks.push(fn() {
    @sf.section(c, heads=false, @sf.t("web-pages.settings.nav.version"), fn() {
      @sf.group(c, fn() {
        version_rows(c, core)
        if @sf.link_row(c, "about/changelog", @sf.t("web-pages.settings.nav.changelog")) {
          (core.push)(Changelog)
        }
      })
    })
  })
  // a build that sends nothing has nothing to turn off
  match (core.reporting)() {
    Some(on) =>
      blocks.push(fn() {
        @sf.section(c, heads=false, @sf.t("web-pages.about.privacy"), fn() {
          @sf.group(c, card=true, fn() {
            let now = @sf.switch_row(c, "about/reporting",
              @sf.t("common.telemetry.title"),
              on,
              note=@sf.t("common.telemetry.note", args=[("name", "still.fail")]),
            )
            if now != on {
              (core.set_reporting)(now)
            }
          })
        })
      })
    None => ()
  }
  // on still.fail's site, in the browser
  blocks.push(fn() {
    @sf.section(c, heads=false, @sf.t("web-pages.about.legal"), fn() {
      @sf.group(c, fn() {
        for l in [("terms", "common.legal.terms"), ("privacy", "common.legal.privacy")] {
          if @sf.link_row(c, "about/" + l.0, @sf.t(l.1), out=true) {
            (core.open_link)(@settings.legal_url(l.0))
          }
        }
      })
    })
  })
  // this device's performance record, last and out of the way (where the device keeps one: iOS)
  let perf = @hostapi.perf_state()
  if perf >= 0 {
    blocks.push(fn() {
      @sf.section(c, heads=false, @sf.t("web-pages.about.diagnostics"), fn() {
        @sf.group(c, card=true, fn() {
          let on = perf == 1
          let now = @sf.switch_row(c, "about/perf",
            @sf.t("web-pages.about.perf.title"),
            on,
            note=@sf.t("web-pages.about.perf.note", args=[("where", @hostapi.perf_where()), ("size", @sf.file_size(@hostapi.perf_size()))]),
          )
          if now != on {
            @hostapi.set_perf(now)
          }
          // (handed on through the system's share sheet: a release build's files are nowhere a person can take them from,
          // the Files app shows none of the app's and only a build signed for development can be copied off with Xcode)
          if @hostapi.perf_size() > 0.0 &&
            @sf.link_row(c, "about/perf/share", @sf.t("web-pages.about.perf.share"), acts=true) {
            @hostapi.share("", "still.fail-perf.log", "text/plain", @hostapi.perf_read()) |> ignore
          }
        })
      })
    })
  }
  @sf.page(c, on_back=core.pop, frame~, "about", @sf.t("web-pages.settings.nav.about"), blocks)
}

///|
/// This build and the way to a newer one, a row each on every screen. Its name and version, words of a length known,
/// the row's alone. Then, where newer builds are asked for here (not on iOS, nor run from the sources), what can be
/// done, said by the row's own words: 更新到 <version> where a newer build is known (installed), else 检查更新 (still.fail
/// cloud asked now); pressed, the update dialog opens and says how it goes (updates.mbt update_dialog), and pressed
/// while it goes, opens again. What is under way under its words (正在检查, 下载中 40%, 正在安装: words of no length
/// known, on a line of their own) and under them the bar, from asking to installing (Progress: how far while it
/// downloads, else a piece sweeping across), as the dialog has it: the row as tall all the way. (A spinner at its end
/// while how far was not known, the bar only while it was, made the row taller and shorter again as it went: 正在检查,
/// 下载中, 正在安装, 2026-10-28. A button at the row's end took what its words left: the name cut to 「still.fail…」 and
/// 下载中 40% broken in two beside 更新到 0.1.5283 on a phone, 2026-10-26.)
fn version_rows(c : @ui.Ctx, core : Core) -> Unit {
  let v = (core.version_now)()
  @sf.link_row(c, "", "still.fail mbui " + build_version(), goes=false) |> ignore
  if !v.asks {
    return
  }
  let busy = v.doing != ""
  let label = if v.newer != "" {
    @sf.t("android-settings.version.update", args=[("version", v.newer)])
  } else {
    @sf.t("android-settings.version.check")
  }
  let pressed = @sf.link_row(
    c,
    "about/version",
    label,
    note=v.doing,
    chevron=false,
    below?=if busy { Some(fn() { @sf.progress(c, "about/version/part", v.part) }) } else { None },
  )
  if pressed {
    (core.version_tap)()
  }
}

///|
/// The changelog's part in view ("" the first), and the news last told read (as the core says it: told once, not again
/// each frame until the core has it, and news an update brings later told again).
// kept across runs: said by its tabs and as it opens; changelog_reset puts them back
let changelog_part : Ref[String] = Ref("")

///|
// kept across runs: said as the page opens; changelog_reset puts it back
let changelog_seen : Ref[String] = Ref("")

///|
fn changelog_reset() -> Unit {
  changelog_part.val = ""
  changelog_seen.val = ""
}

///|
/// 更新日志 (ChangelogPage; the narrow app's ChangelogScreen): the core's `changelog`, a tab a part (the choice only where
/// there is more than one), by day (narrow: each day's changes on a card); opened, what the last update brought is read
/// (`changelog.seen`).
pub fn changelog_page(c : @ui.Ctx, core : Core, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let topic = (core.topic)("changelog", Map([]))
  let v = topic.value
  // opened: what the update brought is read
  let news = match field(v, "news") {
    Some(Null) | None => ""
    Some(n) => n.stringify()
  }
  if news != "" && news != changelog_seen.val {
    changelog_seen.val = news
    c.tell("changelog.seen", fn() { (core.call)("changelog.seen", obj([]), fn(_) {  }) })
  }
  let tabs = items(v, "tabs")
  let at = match tabs.search_by(fn(x) { text(Some(x), "part") == changelog_part.val }) {
    Some(i) => i
    None => 0
  }
  let blocks : Array[() -> Unit] = []
  if tabs.length() > 1 {
    blocks.push(fn() {
      let labels = tabs.map(fn(x) { text(Some(x), "label") })
      // (each part 120 wide at least, a wide page's)
      let chosen = @sf.page_choice(c, "changelog/tabs", labels, at, item_w=cl_tab_w)
      if chosen != at {
        changelog_part.val = text(Some(tabs[chosen]), "part")
      }
    })
  }
  if v is None || flag(v, "loading") {
    blocks.push(fn() {
      let error = match topic.error {
        Some(e) => @settings.error_text(e)
        None => ""
      }
      @sf.waiting(c, fn() { changelog_sample(c, look) }, error~)
    })
  } else if has(v, "error") {
    blocks.push(fn() { cl_said(c, look, text(v, "error"), bad=true) })
  } else {
    let days = match tabs.get(at) {
      Some(x) => items(Some(x), "days")
      None => []
    }
    if days.length() == 0 {
      blocks.push(fn() { cl_said(c, look, @sf.t("web-pages.changelog.empty")) })
    }
    for day in days {
      blocks.append(day_blocks(c, look, day))
    }
  }
  @sf.page(c, on_back=core.pop, frame~, "changelog/" + at.to_string(),
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
/// A day of the changelog: its heading, its changes under it (narrow: on a card under it, the heading a block of its
/// own).
fn day_blocks(c : @ui.Ctx, look : Look, day : Json) -> Array[() -> Unit] {
  match look {
    Narrow =>
      [
        fn() { @sf.heading(c, text(Some(day), "label")) },
        fn() {
          @sf.group(c, fn() {
            for e in items(Some(day), "entries") {
              change_narrow(c, Some(e))
            }
          })
        },
      ]
    Wide =>
      [
        fn() {
          c.box(style=cl_day, fn() {
            c.box(style=cl_heading_room, fn() { c.text(text(Some(day), "label"), style=cl_heading) |> ignore })
            |> ignore
            for e in items(Some(day), "entries") {
              change_item(c, Some(e))
            }
          })
          |> ignore
        },
      ]
  }
}

///|
/// The changes to come while they are read (the library's Waiting, in its bones): two days of made-up ones, as
/// day_blocks draws them.
fn changelog_sample(c : @ui.Ctx, look : Look) -> Unit {
  for d, lines in changelog_sample_lines {
    let entries = lines.map(fn(n) {
      Json::object({
        "lines": [{ "label": Json::string(@sf.sample_words(2)), "text": Json::string(@sf.sample_words(n)) }],
        "versionName": Json::string(@sf.sample_words(5)),
      })
    })
    let day : Json = { "label": Json::string(@sf.sample_words(if d == 0 { 2 } else { 5 })), "entries": Json::array(entries) }
    for b in day_blocks(c, look, day) {
      b()
    }
  }
}

///|
/// How long each made-up change is (letters), day by day.
// kept across runs: a table, never written
let changelog_sample_lines : Array[Array[Int]] = [[18, 26, 12], [22, 15]]

///|
/// What the page says in place of the changes (none yet, or why they could not be read: red).
fn cl_said(c : @ui.Ctx, look : Look, words : String, bad? : Bool = false) -> Unit {
  match look {
    Narrow =>
      c.box(style=cl_narrow_said, fn() { c.text(words, style=if bad { cl_narrow_bad } else { cl_narrow_note }) |> ignore })
      |> ignore
    Wide => c.text(words, style=if bad { desk_note_bad } else { desk_muted }) |> ignore
  }
}

///|
/// One change on a narrow page (mChange): each line led by its kind on a small tinted label (the accent's for something
/// new), its words wrapping under it; then its version and what is not out yet (in the accent: an update would bring
/// it).
fn change_narrow(c : @ui.Ctx, e : Json?) -> Unit {
  let t = @sf.theme()
  c.box(style=cl_narrow_change, fn() {
    for l in items(e, "lines") {
      let lv = Some(l)
      let label = text(lv, "label")
      if label == "" {
        c.text(text(lv, "text"), style=cl_narrow_line) |> ignore
      } else {
        // the label inline before the words (Changelog.css.ts mKind, in ems of its 13: 6 either side, 19 high, 6
        // round, 6 before the words)
        let fresh = text(lv, "kind") == "new"
        let ground : @ui.Ground = { room: 6.0 / 13.0, height: 19.0 / 13.0, corner: 6.0 / 13.0, after: 6.0 / 13.0 }
        let kind = @ui.span(
          label,
          scale=13.0 / 15.0,
          color=if fresh { t.p.accent_text } else { t.p.muted },
          bg=if fresh { t.p.accent_bg } else { t.p.chip },
          ground=Some(ground),
        )
        c.rich([kind, @ui.plain(text(lv, "text"))], style=cl_narrow_line) |> ignore
      }
    }
    c.box(style=cl_narrow_meta, fn() {
      c.text(text(e, "versionName"), style=cl_narrow_version) |> ignore
      if text(e, "note") != "" {
        c.text(text(e, "note"), style=if field(e, "has") is Some(False) { cl_narrow_coming } else { cl_narrow_version })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
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
let cl_tab_w : Double = 120.0

///|
/// A day (heading: 20 over it, 10 in, 2 under; meta, medium, muted), its changes under it.
// kept across runs: a value (no field of it changes)
let cl_day : @ui.Style = @ui.css("w=Full pt=S5 gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let cl_heading : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=Muted, w=@sf.grow)

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
let cl_kind_words : @ui.TextStyle = @ui.text_style(size=Caption, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cl_kind_new_words : @ui.TextStyle = @ui.text_style(size=Caption, leading=L5, color=AccentText, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cl_line : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5, color=Fg, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let cl_version : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, wrap=false)

///|
/// What is not out yet (note: meta, muted; the accent's where an update would bring it).
// kept across runs: a value (no field of it changes)
let cl_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let cl_note_new : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=AccentText, w=@sf.grow)

// ── the narrow page's (mobile/Changelog.css.ts) ─────────────────────────

///|
/// What is said in place of the changes (mNote: 24 from the page's sides, 12 in its room; 8 over and under).
// kept across runs: a value (no field of it changes)
let cl_narrow_said : @ui.Style = @ui.css("w=Full px=S3 py=S2")

///|
// kept across runs: a value (no field of it changes)
let cl_narrow_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let cl_narrow_bad : @ui.TextStyle = cl_narrow_note.then(@ui.text_style(color=Danger))

///|
/// A change (mChange: 16 by 10 in, its lines 2 apart).
// kept across runs: a value (no field of it changes)
let cl_narrow_change : @ui.Style = @ui.css("w=Full px=S4 py=S2_5 gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let cl_narrow_line : @ui.TextStyle = @sf.body.then(@sf.full_words)

///|
/// Its version and what is not out yet (mMeta: in a line, 10 apart).
// kept across runs: a value (no field of it changes)
let cl_narrow_meta : @ui.Style = @ui.css("row w=Full gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let cl_narrow_version : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cl_narrow_coming : @ui.TextStyle = cl_narrow_version.then(@ui.text_style(color=AccentText))
