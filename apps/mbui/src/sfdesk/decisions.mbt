// 奏 as one of the sidebar's lists (ember web/src/DecisionDesk.tsx DecisionRows, DecisionDesk.css.ts item, group, row,
// question, meta): the decisions waiting for the viewer as the core lists them (the core's `decisions` view: `items`,
// those set aside last under 待定), each its question in two lines at most, its chat, its station and when it was asked
// under it; the one the 奏 page shows lit while it is open (the core's `shown`); pressed, it is the one shown
// (`decision.show`), the 奏 page opened for it.

///|
/// One of the list's lines.
priv enum ZouLine {
  Top
  /// 待定, over the first set aside
  Aside
  Row(Int, Json)
  /// none waiting, or the list still read
  Empty
  Reading
  Foot
}

///|
/// 奏's list, under the band (新建对话 and the filter stay over it, as over the chats').
fn decisions_pane(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let topic = (src.topic)("decisions", { "workspace": Json::string(w.id) })
  let shown = items(topic.value, "items")
  // (lit only on the 奏 page: aria-current while it is the page in view)
  let here = lit_place() == "decisions"
  let front = decision_front(topic.value, shown)
  let lines : Array[ZouLine] = [Top]
  let mut aside = false
  for i, d in shown {
    if flag(Some(d), "deferred") && !aside {
      aside = true
      lines.push(Aside)
    }
    lines.push(Row(i, d))
  }
  if topic.value is None {
    lines.push(Reading)
  } else if shown.length() == 0 {
    lines.push(Empty)
  }
  lines.push(Foot)
  let key = "side/zou/" + w.id
  let keys = lines.map(fn(l) {
    match l {
      Row(_, d) => "r/" + decision_key(d)
      Aside => "h/aside"
      _ => ""
    }
  })
  let lid = @motion.list_keys(c, key, keys.filter(fn(k) { k != "" }).map(fn(k) { key + "\u{1}" + k }), liftable=fn(k) {
    !k.contains("\u{1}h/")
  })
  // (read now: the rows are made as the list is laid out)
  let band = band_h(src, w)
  c.box(style=lists_fill, fn() {
    c.list(key, lines.length(), zou_row_h, fn(i) {
      let n = c.box(style=@sf.list_line(Side), fn() {
        match lines[i] {
          Top => side_space(c, band + @sfpages.lists_top_in)
          Aside => c.box(style=zou_group, fn() { c.text(@sf.t("web-main.decisions.defer"), style=zou_group_words) |> ignore }) |> ignore
          Row(k, d) => zou_row(c, src, w, d, here && k == front, i + 1 < lines.length() && lines[i + 1] is Row(_, _))
          Empty => c.box(style=zou_empty, fn() { c.text(@sf.t("web-main.decisions.empty"), style=zou_empty_words) |> ignore }) |> ignore
          Reading => @sf.waiting(c, fn() { zou_rows_sample(c, w) })
          Foot => side_space(c, @sf.list_foot_in(Side))
        }
      })
      if keys[i] != "" {
        @sfpages.row_moving(c, lid, key, keys[i], n)
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// Which of the decisions the 奏 page shows (the core's `shown`: the one picked, else the one now in its place).
fn decision_front(view : Json?, shown : Array[Json]) -> Int {
  let at = number(view, "shown").to_int()
  if at >= 0 && at < shown.length() {
    at
  } else {
    0
  }
}

///|
/// One decision (DecisionDesk.css.ts row): its question (13 on 20, 500, two lines at most: the core's `question`,
/// uncut, else its title), its chat, its station and when under it (12 on 18, subtle); set aside, faded; pressed, the
/// one the 奏 page shows, the page opened.
fn zou_row(c : @ui.Ctx, src : Source, w : Workspace, d : Json, on : Bool, more : Bool) -> Unit {
  let t = @sf.theme()
  let v = Some(d)
  let key = "zou-nav/" + decision_key(d)
  let id = c.id(key)
  if c.clicked(id) {
    // the one pressed shown from now on (the list as it is), on the 奏 page, on the tape brought over
    decision_show(src, w, d)
    if lit_place() != "decisions" {
      go_zou()
    }
    @sfbase.show_chosen()
  }
  let question = match text(v, "question") {
    "" => text(v, "title")
    q => q
  }
  let ground = nav_ground(c, key, c.lit(id) || c.pressed(id), on)
  let look = if flag(v, "deferred") { zou_row_look.then(zou_aside) } else { zou_row_look }
  c.box(style=if more { @sfpages.row_more } else { @sfpages.row_last }, fn() {
    c.box(style=look.then(@ui.style(bg=Data(ground))), id~, fn() {
      c.text(question, style=zou_question) |> ignore
      c.box(style=zou_meta, fn() {
        c.box(style=zou_where, fn() {
          // (its chat's title cut where the room runs out, the station it is on whole after it)
          c.text(text(v, "title"), style=zou_meta_cut) |> ignore
          c.text(" · ", style=zou_meta_hug) |> ignore
          if @sf.has_station_mark(text(v, "stationEmoji"), text(v, "stationIcon")) {
            @sf.station_mark(c, text(v, "stationEmoji"), text(v, "stationIcon"), @sfpages.kind_mark, t.p.subtle)
          }
          c.text(text(v, "stationName"), style=zou_meta_hug) |> ignore
        })
        |> ignore
        match stamp_of(field(v, "message"), "createdAt") {
          Some(s) => c.text(s.ago, style=zou_time) |> ignore
          None => ()
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The decisions to come while the list is read the first time (the library's Waiting, in its bones): rows as zou_row
/// draws them, of made-up words (a question, its chat, its station and when).
fn zou_rows_sample(c : @ui.Ctx, w : Workspace) -> Unit {
  for i in 0..<zou_sample.length() {
    let (question, title) = zou_sample[i]
    let d : Json = {
      "station": Json::string("sample"),
      "seq": Json::number(i.to_double()),
      "question": Json::string(@sf.sample_words(question)),
      "title": Json::string(@sf.sample_words(title)),
      "stationName": Json::string(@sf.sample_words(4)),
      "message": { "time": { "createdAt": { "ago": Json::string(@sf.sample_words(3)), "full": "" } } },
    }
    zou_row(c, @sfbase.sample_source, w, d, false, i + 1 < zou_sample.length())
  }
}

///|
/// How long the made-up decisions' questions and their chats' titles are (letters).
// kept across runs: a table, never written
let zou_sample : Array[(Int, Int)] = [(16, 7), (11, 9), (22, 6), (14, 10), (9, 8), (18, 7)]

///|
/// The 奏 page at the stack's root, as the rail's 奏 goes to it.
fn go_zou() -> Unit {
  @sfbase.history_push()
  while app.nav.depth() > 1 {
    if !app.nav.pop() {
      break
    }
  }
  app.nav.replace(Decisions)
}

///|
/// A row at its least (8, a question's line, 4, its meta's, 8): what the list measures rows by before they are drawn.
let zou_row_h : Double = 58.0

///|
// kept across runs: a value (no field of it changes)
let zou_row_look : @ui.Style = @ui.css("w=Full px=S2_5 py=S2 gap=S1 radius=Xl")

///|
// kept across runs: a value (no field of it changes)
let zou_aside : @ui.Style = @ui.css("opacity=O55")

///|
// kept across runs: a value (no field of it changes)
let zou_question : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, leading=L6, max_lines=2, w=Full)

///|
// kept across runs: a value (no field of it changes)
let zou_meta : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let zou_where : @ui.Style = @ui.css("row w=Full align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let zou_meta_hug : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, leading=L5, wrap=false, w=Hug)

///|
// kept across runs: a value (no field of it changes)
let zou_meta_cut : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, leading=L5, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let zou_time : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, leading=L5, wrap=false)

///|
/// 待定 over the ones set aside (DecisionDesk.css.ts group: 14 10 4, 12 on 18, subtle).
// kept across runs: a value (no field of it changes)
let zou_group : @ui.Style = @ui.css("w=Full px=S2_5 pt=S3_5 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let zou_group_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, leading=L5, wrap=false)

///|
/// None waiting (emptyList: 20 by 10 in, 12 on 20, subtle).
// kept across runs: a value (no field of it changes)
let zou_empty : @ui.Style = @ui.css("w=Full px=S2_5 py=S5")

///|
// kept across runs: a value (no field of it changes)
let zou_empty_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, leading=L6)
