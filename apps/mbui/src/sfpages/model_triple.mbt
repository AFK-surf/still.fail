// The one way a model is chosen (ember web/src/ModelTriple.tsx, ModelTriple.css.ts; NewChat.kt's run picker said the
// same): a control that says the model, the runtime (where it can still change and the model runs on more than one),
// how hard it thinks and who runs it, in one line; pressed, its panel through the presenters (beside it with keyboard and mouse,
// a sheet with touch): the models by series (a filter over them when there are many), under them the runtime, the
// effort and the speed as selects, every name whole; at its foot who runs it (the accounts in a
// panel of their own, from it), 取消 and 确定. Its rows are the screen's (Theme::rows pick). Picks there are the
// core's draft (`pick.set`) until 确定 (`pick.save`); a model another station has is borrowed first, asked in a dialog.


///|
/// What the control keeps of its own (the pick is the core's): the one whose panel is open (its station and pick, ""
/// none) and that panel (@sf.last_presented), the one asked open (a screen's fixture, a page's), its filter's field
/// and words; the borrowing it asks to confirm ("" none).
priv struct Triple {
  mut open : String
  mut shown : Int
  mut asked : String
  field : @ui.Field
  mut query : String
  mut borrow_asking : String
}

///|
let triple : Triple = { open: "", shown: 0, asked: "", field: @ui.Field::new(), query: "", borrow_asking: "" }

///|
fn triple_reset() -> Unit {
  triple.open = ""
  triple.shown = 0
  triple.asked = ""
  triple.field.set("")
  triple.query = ""
  triple.borrow_asking = ""
}

///|
/// What is at a row's end (its check, what goes with it): the rest of the row after its words, at its end.
// kept across runs: a value (no field of it changes)
let triple_end : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S1_5, align=ACenter, justify=JEnd)

///|
/// An effort as it is said (low → 低); one the words do not know, as it is spelled, its first letter up.
fn effort_text(effort : String) -> String {
  let key = "web-main.model.effortLevel." + effort
  let said = @sf.t(key)
  if said != key {
    said
  } else if effort == "" {
    effort
  } else {
    effort.view(end_offset=1).to_upper().to_string() + effort.view(start_offset=1).to_string()
  }
}

///|
/// The pick's topic's params.
fn pick_params(station : String, of : String) -> Map[String, Json] {
  { "station": Json::string(station), "of": Json::string(of) }
}

///|
/// What the panel picked changed (`pick.set`): only what is given.
fn pick_draft(src : Source, station : String, of : String, patch : Map[String, Json]) -> Unit {
  let p = pick_params(station, of)
  for k, v in patch {
    p[k] = v
  }
  (src.call)("pick.set", Json::object(p), fn(res) {
    match res {
      Ok(_) => ()
      Err(e) => toast_later(@sf.t("web-main.pick.failed", args=[("error", error_words(e))]))
    }
  })
}

///|
/// The panel of the pick `of` on `station` (the control's: see model_triple) opened beside `from`: from the control,
/// or from elsewhere that says what runs (an agent's card's account: `side` Right, beside the card). Opened already,
/// it closes (a trigger toggles it: one the panel does not cover, the card's, stays pressable while it is open).
pub fn open_triple_panel(
  src : Source,
  station : String,
  of : String,
  from : @sf.Anchor,
  saved? : String = "",
  side? : @ui.Side = Bottom,
) -> Unit {
  let me = station + "\u{1}" + of
  if triple.open == me {
    @sf.close_presented_of(triple.shown)
    return
  }
  triple.open = me
  triple.field.set("")
  triple.query = ""
  pick_draft(src, station, of, { "open": Json::boolean(true) })
  @sf.panel(
    @sf.t("android-chat.new.model"),
    fn(c, _) { triple_panel(c, src, station, of) },
    from~,
    w=triple_panel_w,
    // (as wide as its columns' words, no wider: 2026-10-26 用户「没啥内容也这么宽感觉会很奇怪」)
    fits=true,
    foot=fn(c, close) { triple_foot(c, src, station, of, saved, close) },
    gone=fn() { triple.open = "" },
    focus=false,
    // (the models scroll by themselves, what goes with the one picked beside them in view)
    lists=true,
    // (the line over its foot across the whole panel, out past its padding to its edges, over the foot where what it
    // holds scrolls: 2026-10-25 用户「分割线边上不要留空」)
    ruled=true,
    side~,
  )
  triple.shown = @sf.last_presented()
}

///|
/// The control of the pick `of` on `station` (ModelTriple): its line, and its panel under it while open (above it with
/// `up`). `page`: the control as a page has it with itself (a new chat's: its `pick`), not read on its own; `small`: in
/// a composer's row (ModelTriple.css.ts in newChat: 28 high, its words 12). `saved`: what is said once 确定 kept it
/// (onConfirm's toast: a chat's, from its next turn; a connect's, its model bound; nothing where nothing runs on it yet,
/// a new chat's or a new connect's). `floating`: over a page rather than in a row (a new chat's over its
/// composer, narrow): a capsule of the composer's glass.
pub fn model_triple(
  c : @ui.Ctx,
  src : Source,
  station : String,
  of : String,
  up? : Bool = false,
  page? : Json? = None,
  small? : Bool = false,
  floating? : Bool = false,
  saved? : String = "",
) -> Unit {
  let t = @sf.theme()
  let v = match page {
    Some(_) => page
    None => (src.topic)("pick", pick_params(station, of)).value
  }
  guard v is Some(Object(_)) else { return }
  let value = field(v, "value")
  let options = items(v, "options")
  let vo = field(v, "valueOption")
  let account = field(v, "account")
  let me = station + "\u{1}" + of
  let dkey = "pick.save/" + station + "/" + of
  let saving = doing(dkey)
  let id = c.id("triple/" + me)
  let can = options.length() > 0 && !saving
  let open = triple.open == me
  if can && !open && (c.clicked(id) || triple.asked == me) {
    triple.asked = ""
    open_triple_panel(src, station, of, Of(id), saved~)
  }
  let runtime = text(value, "runtime")
  let (words, muted) = if small { (triple_words_xs, triple_muted_xs) } else { (triple_words, triple_muted) }
  c.box(
    style=match (floating, open, small) {
      // (over the page, not in a row: on the composer's glass, as the page's other choice)
      (true, _, _) => glass_chooser_box
      (false, true, false) => triple_on
      (false, false, false) => triple_style
      (false, true, true) => triple_small_on
      (false, false, true) => triple_small
    },
    glass?=if floating { Some(@sf.glass_floating()) } else { None },
    id~,
    fn() {
    if options.length() == 0 {
      c.text(@sf.t("web-main.model.none"), style=muted) |> ignore
    } else {
      let model = text(value, "model")
      @sf.maker_mark(c, text(field(vo, "maker"), "id"), runtime, 14.0) |> ignore
      let name = if model == "" {
        @sf.t("web-main.model.pick")
      } else {
        match text(vo, "name") {
          "" => model
          n => n
        }
      }
      // (within the room it has, the most it can say: what matters least left out first, as the web's DROPS: who
      // runs it by name, then who runs it, then the runtime, then how hard it thinks; the model never: its name cut
      // short once all of them have gone)
      c.text(name, style=if small { triple_name_xs } else { triple_name }, keep=true) |> ignore
      if !flag(v, "runtimeFixed") && items(vo, "runtimes").length() > 1 {
        c.box(style=triple_part, drop=triple_drop_runtime, fn() {
          c.text("·", style=muted) |> ignore
          c.text(@settings.runtime_label(runtime), style=words) |> ignore
        })
        |> ignore
      }
      let effort = text(value, "effort")
      if effort != "" || items(v, "efforts").length() > 0 {
        c.box(style=triple_part, drop=triple_drop_effort, fn() {
          c.text("·", style=muted) |> ignore
          c.text(if effort == "" { @sf.t("web-main.model.defaultEffort") } else { effort_text(effort) }, style=words)
          |> ignore
        })
        |> ignore
      }
      match text(v, "fastText") {
        "" => ()
        f =>
          c.box(style=triple_part, drop=triple_drop_effort, fn() {
            c.text("·", style=muted) |> ignore
            c.text(f, style=words) |> ignore
          })
          |> ignore
      }
      if account is Some(Object(_)) {
        // (each of its pieces in the control's row: its name the first to go, then the rest of it)
        let profile = field(account, "profile")
        c.box(style=triple_part, drop=triple_drop_account, fn() {
          c.text("·", style=muted) |> ignore
          if profile is Some(Object(_)) {
            @sf.maker_mark(c, text(profile, "mark"), runtime, 14.0) |> ignore
          }
        })
        |> ignore
        let level = text(account, "level")
        c.box(drop=triple_drop_name, fn() {
          c.text(
            text(account, "text"),
            style=if level == "amber" {
              triple_amber
            } else if level == "red" {
              triple_red
            } else {
              words
            },
          )
          |> ignore
        })
        |> ignore
        if profile is Some(Object(_)) {
          c.box(style=triple_part, drop=triple_drop_account, fn() {
            @sf.quota_chips(c, field(profile, "quota"), small=true)
          })
          |> ignore
        }
      }
    }
    // what was picked on its way: a ring in place of the chevron
    if saving {
      @sf.spinner(c, size=12.0) |> ignore
    } else {
      @sf.icon(c, "chevron-down", size=12.0, color=t.p.muted) |> ignore
    }
    },
  )
  |> ignore
  borrow_dialog(c, src, station, of, v)
}

///|
/// What a model is picked from, made up, for what the panel shows while it is read (triple_body in its bones): a few
/// models of two series, two runtimes, how hard it thinks.
fn triple_sample() -> Json {
  let model = fn(i : Int, family : Int, n : Int) -> Json {
    {
      "model": Json::string("sample" + i.to_string()),
      "name": Json::string(@sf.sample_words(n)),
      "family": Json::string(@sf.sample_words(family)),
    }
  }
  {
    "options": [model(0, 3, 6), model(1, 3, 8), model(2, 3, 5), model(3, 4, 7), model(4, 4, 6)],
    "runtimes": ["claude", "codex"],
    "efforts": ["low", "medium", "high"],
  }
}

///|
/// The panel: the filter across its top (more than 8 models), the models by series, and beside them the runtimes, how
/// hard it thinks and how fast as columns where all their words fit, else under them as selects side by side: the
/// models scrolling by themselves, what goes with them in view. What borrowing would do under them. Beside what opened it the models scroll past 360 (the web's); in a sheet the
/// sheet is as tall as all of it up to its most, the models scrolling in what is left then (@sf.panel_column).
fn triple_panel(c : @ui.Ctx, src : Source, station : String, of : String) -> Unit {
  let v = (src.topic)("pick", pick_params(station, of)).value
  if v is None {
    // (read the first time: the panel of made-up models, in its bones)
    @sf.waiting(c, fn() { triple_body(c, @sfbase.sample_source, station, of, Some(triple_sample())) })
    return
  }
  triple_body(c, src, station, of, v)
}

///|
/// The panel's models, runtimes, how hard it thinks and how fast, as the core's `pick` (`v`) offers them.
fn triple_body(c : @ui.Ctx, src : Source, station : String, of : String, v : Json?) -> Unit {
  let options = items(v, "options")
  let draft = field(v, "draft")
  let words = triple.query.trim(chars=" ").to_string().to_lower()
  if options.length() > 8 {
    // (a small panel's search, as a pick's: its ground sets it apart from the models, no line under it)
    c.box(style=triple_search, fn() {
      let res = @sf.input(c, "triple/filter", placeholder=@sf.t("web-main.model.search"), small=true, field=triple.field)
      triple.query = res.text
    })
    |> ignore
  }
  let listed = options.filter(fn(o) {
    let o = Some(o)
    words == "" ||
    text(o, "name").to_lower().contains(words) ||
    text(o, "model").to_lower().contains(words) ||
    items(o, "ids").iter().any(fn(i) { i is String(s) && s.to_lower().contains(words) })
  })
  // by series, in the core's order
  let series : Array[(String, Array[Json])] = []
  for o in listed {
    let who = match text(Some(o), "family") {
      "" => @sf.t("web-main.model.otherSeries")
      f => f
    }
    match series.search_by(fn(s) { s.0 == who }) {
      Some(i) => series[i].1.push(o)
      None => series.push((who, [o]))
    }
  }
  let runtimes = items(v, "runtimes")
  let efforts = items(v, "efforts")
  let fast = flag(v, "fastAvailable")
  let runs_on : Array[(String, String)] = []
  for r in runtimes {
    if r is String(r) {
      runs_on.push((r, @settings.runtime_label(r)))
    }
  }
  let all_efforts : Array[(String, String)] = []
  if efforts.length() > 0 {
    all_efforts.push(("", @sf.t("web-main.model.default")))
    for e in efforts {
      if e is String(e) {
        all_efforts.push((e, effort_text(e)))
      }
    }
  }
  let speed_now = match field(draft, "fast") {
    Some(True) => "fast"
    Some(False) => "standard"
    _ => ""
  }
  let speeds = [
    ("", @sf.t("web-main.model.fastSubscription")),
    ("standard", @sf.t("web-main.model.standard")),
    ("fast", "Fast"),
  ]
  let pick_runtime = fn(r : String) { pick_draft(src, station, of, { "runtime": Json::string(r) }) }
  let pick_effort = fn(e : String) {
    pick_draft(src, station, of, { "effort": if e == "" { Json::null() } else { Json::string(e) } })
  }
  let pick_speed = fn(f : String) {
    let fv : Json = match f {
      "" => Json::null()
      "fast" => Json::boolean(true)
      _ => Json::boolean(false)
    }
    pick_draft(src, station, of, { "fast": fv })
  }
  let has_rest = runs_on.length() > 0 || all_efforts.length() > 0 || fast
  // each column's words as wide as the widest of them picked (the models' of all of them, whatever the filter leaves):
  // the panel, as wide as what it holds, as wide whichever is picked and whatever is typed (as a segmented choice's)
  let names_w = options.fold(init=0.0, fn(m, o) {
    let o = Some(o)
    dmax(dmax(m, c.words_across(text(o, "name"), triple_row_picked)), c.words_across(text(field(o, "spent"), "text"), triple_note))
  }).ceil()
  let widest = fn(said : Array[(String, String)]) {
    said.fold(init=0.0, fn(m, s) { dmax(m, c.words_across(s.1, triple_picked)) }).ceil()
  }
  let (runs_w, efforts_w, speeds_w) = (widest(runs_on), widest(all_efforts), widest(speeds))
  // the models and, beside them, the runtimes and how hard it thinks (and how fast) as columns of their own, where the
  // panel has the room for all of their words (beside what opened it, as the web's: nothing is said of them twice);
  // where it has not (a phone's sheet), those columns leave the row whole (their own row's `drop`, read back) and are
  // selects under the models instead, side by side (2026-10-26 用户「你不如把运行时和思考深度缩成两个独立 select」):
  // either way in view whatever model is picked, the models scrolling by themselves (「用户选完模型根本看不到下面的
  // runtime 和思考深度」), every name whole (「看不出是什么模型怎么办」)
  let rest = c.id("triple/rest")
  let under = has_rest && c.left_out(rest)
  // the models as tall as the columns beside them where those are taller than the models' most (Codex's seven efforts
  // and its speeds): the row is as tall as its tallest column, and the models scroll in all of it, not in 360 of it
  // with the rest of their column empty under them (2026-10-30 用户「下面为啥这么大的遮挡」); each column as tall as
  // what it holds, read back
  let runs_id = c.id("triple/runs")
  let efforts_id = c.id("triple/efforts")
  let models_most = if under {
    triple_list_h
  } else {
    [runs_id, efforts_id].fold(init=triple_list_h, fn(m, id) {
      match c.laid_size(id) {
        Some((_, h)) => dmax(m, h)
        None => m
      }
    })
  }
  c.box(style=triple_columns, fn() {
    c.box(style=triple_models, keep=true, fn() {
      @sf.panel_column(c, "triple/models", models_most, triple_rows, fn() {
        // (no head of its own: the panel's title says what they are)
        for s in series {
          if series.length() > 1 {
            triple_column_head(c, s.0)
          }
          for o in s.1 {
            triple_model_row(c, src, station, of, v, Some(o), names_w)
          }
        }
        if listed.length() == 0 {
          c.box(style=triple_empty, fn() { c.text(@sf.t("web-main.model.noMatch"), style=triple_muted) |> ignore })
          |> ignore
        }
      })
    })
    |> ignore
    if has_rest {
      c.box(style=triple_rest, drop=1, id=rest, taps=false, fn() {
        // (the lines between columns out of their flow, in the middle of the 8 before each, as tall as the columns)
        triple_line_before(c)
        if runs_on.length() > 0 {
          c.box(style=triple_column, fn() {
            c.box(style=triple_column, id=runs_id, fn() {
            triple_column_head(c, @sf.t("web-main.model.runtime"))
            for o in runs_on {
              let (r, words) = o
              let on = text(draft, "runtime") == r
              if triple_option(c, "triple/runtime/" + r, words, on, fn() {
                  @sf.maker_mark(c, "", r, 14.0) |> ignore
                  triple_said(c, words, on, runs_w)
                }) {
                pick_runtime(r)
              }
            }
            })
            |> ignore
          })
          |> ignore
        }
        if all_efforts.length() > 0 || fast {
          c.box(style=triple_column, fn() {
            if runs_on.length() > 0 {
              triple_line_before(c)
            }
            c.box(style=triple_column, id=efforts_id, fn() {
            if all_efforts.length() > 0 {
              triple_column_head(c, @sf.t("web-main.model.effort"))
              for o in all_efforts {
                let (e, words) = o
                let on = text(draft, "effort") == e
                if triple_option(c, "triple/effort/" + e, words, on, fn() { triple_said(c, words, on, efforts_w) }) {
                  pick_effort(e)
                }
              }
            }
            if fast {
              triple_column_head(c, @sf.t("web-main.model.speed"))
              for o in speeds {
                let (f, words) = o
                let on = speed_now == f
                // (Fast says what it costs on hover: ModelTriple.tsx's fastNote)
                let tip = if f == "fast" { @sf.t("web-main.model.fastNote") } else { "" }
                if triple_option(c, "triple/fast/" + f, words, on, tip~, fn() { triple_said(c, words, on, speeds_w) }) {
                  pick_speed(f)
                }
              }
            }
            })
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    }
  })
  |> ignore
  if under {
    c.box(style=triple_selects, fn() {
      if runs_on.length() > 0 {
        let head = @sf.t("web-main.model.runtime")
        let icons : Map[String, String] = {}
        for o in runs_on {
          icons[o.0] = "runtime:" + o.0
        }
        triple_select_of(c, head, fn() {
          @sf.select(
            c,
            "triple/runtime",
            text(draft, "runtime"),
            runs_on,
            pick_runtime,
            label=head,
            disabled=runs_on.length() < 2,
            w=triple_select_most,
            whole=true,
            icons~,
          )
        })
      }
      if all_efforts.length() > 0 {
        let head = @sf.t("web-main.model.effort")
        triple_select_of(c, head, fn() {
          @sf.select(c, "triple/effort", text(draft, "effort"), all_efforts, pick_effort, label=head, w=triple_select_most, whole=true)
        })
      }
      if fast {
        let head = @sf.t("web-main.model.speed")
        triple_select_of(c, head, fn() {
          @sf.select(c, "triple/fast", speed_now, speeds, pick_speed, label=head, w=triple_select_most, whole=true)
        })
      }
    })
    |> ignore
  }
  // the model picked is another station's: said over the foot, which borrows it rather than confirming
  let borrow = field(v, "borrow")
  if borrow is Some(Object(_)) {
    c.box(style=triple_borrow, fn() {
      c.text(if flag(borrow, "allowed") { text(borrow, "note") } else { text(borrow, "why") }, style=triple_note)
      |> ignore
    })
    |> ignore
  }
}

///|
/// Who runs it, at the foot's start beside 取消 and 确定 (the web's panel's foot, the phone's sheet's): the accounts in a
/// panel of their own, from it.
fn triple_runs_who(c : @ui.Ctx, src : Source, station : String, of : String, v : Json?) -> Unit {
  let t = @sf.theme()
  let draft = field(v, "draft")
  let who = c.id("triple/who")
  if c.clicked(who) {
    @sf.panel(
      @sf.t("web-main.model.account"),
      fn(c, close) { triple_accounts(c, src, station, of, close) },
      from=Of(who),
      focus=false,
    )
  }
  c.box(style=triple_who_room, keep=true, fn() {
    c.box(style=triple_who(), id=who, fn() {
      c.text(@sf.t("web-main.model.account"), style=triple_who_lead) |> ignore
      let level = text(v, "whoLevel")
      c.text(
        if text(draft, "profile") != "" { text(v, "who") } else { @sf.t("web-main.model.auto") },
        style=if level == "amber" {
          triple_amber_sm
        } else if level == "red" {
          triple_red_sm
        } else {
          triple_who_name
        },
      )
      |> ignore
      @sf.icon(c, "chevron-right", size=12.0, color=t.p.muted) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// Its foot (the presenter's, where every panel's foot stands): who runs it, 取消, and 确定 (or borrowing it, asked first).
fn triple_foot(c : @ui.Ctx, src : Source, station : String, of : String, saved : String, close : () -> Unit) -> Unit {
  let v = (src.topic)("pick", pick_params(station, of)).value
  if v is None {
    return
  }
  let picked = text(v, "option")
  let borrow = field(v, "borrow")
  triple_runs_who(c, src, station, of, v)
  if @sf.button(c, @sf.t("common.cancel"), key="triple/cancel", tone=Ghost) {
    triple.open = ""
    close()
  }
  if borrow is Some(Object(_)) {
    if @sf.button(c, text(borrow, "action"), key="triple/borrow", tone=Primary, disabled=!flag(borrow, "allowed")) {
      triple.open = ""
      triple.borrow_asking = station + "\u{1}" + of
      close()
    }
  } else if @sf.button(
      c,
      @sf.t("common.confirm"),
      key="triple/confirm",
      tone=Primary,
      disabled=picked == "" || !flag(v, "changed"),
    ) {
    triple.open = ""
    close()
    act(
      src,
      @sf.t("common.confirm"),
      "pick.save/" + station + "/" + of,
      "pick.save",
      Json::object(pick_params(station, of)),
      done=saved,
    )
  }
}

///|
/// A model's row: its maker's mark, its name (what it has spent under it) `names_w` wide (the widest of the models'),
/// the station it comes from at its end.
fn triple_model_row(
  c : @ui.Ctx,
  src : Source,
  station : String,
  of : String,
  v : Json?,
  o : Json?,
  names_w : Double,
) -> Unit {
  let t = @sf.theme()
  let model = text(o, "model")
  let picked = text(v, "option") == model
  let runs = match items(o, "runtimes").get(0) {
    Some(String(r)) => r
    _ => text(field(v, "value"), "runtime")
  }
  // (its ids, a line each, over it while it is pointed at: ModelTriple.tsx's tip)
  let ids = items(o, "ids").filter_map(fn(i) { if i is String(s) { Some(s) } else { None } }).join("\n")
  let from_station = match field(o, "fromStation") {
    Some(Object(_)) as fs =>
      Some(fn() {
        if text(fs, "icon") != "" || text(fs, "emoji") != "" {
          // (where it comes from, or where it is, said over its mark on hover: runOptionFrom's title)
          let from = c.id("triple/from/" + model)
          c.box(id=from, taps=false, points=true, fn() { @sf.station_mark(c, text(fs, "emoji"), text(fs, "icon"), 14.0, t.p.muted) })
          |> ignore
          @sf.tip(c, "triple/from-tip/" + model, from, text(o, "fromText"))
        } else {
          c.text(text(fs, "name"), style=triple_note_cut) |> ignore
        }
      })
    _ => None
  }
  if triple_option(c, "triple/model/" + model, text(o, "name"), picked, trail?=from_station, tip=ids, fn() {
      @sf.maker_mark(c, text(field(o, "maker"), "id"), runs, 14.0) |> ignore
      // (all of its name in the room its column leaves it, on a second line where one is not enough: what goes with
      // the model picked beside the models takes the room its words need first)
      c.box(style=triple_name_column.then(@ui.style(w=Fixed(names_w))), fn() {
        c.text(text(o, "name"), style=if picked { triple_row_picked } else { triple_row_name }) |> ignore
        match text(field(o, "spent"), "text") {
          "" => ()
          sp => c.text(sp, style=triple_note) |> ignore
        }
      })
      |> ignore
    }) {
    pick_draft(src, station, of, { "model": Json::string(model) })
  }
}

///|
/// The line before a column beside another (the models, the runtimes), out of its flow, in the middle of the 8 between
/// them, from the top of the column down to the line over the panel's foot.
fn triple_line_before(c : @ui.Ctx) -> Unit {
  // (down to the line over the panel's foot, meeting it, past the room left under the columns)
  c.box(style=triple_rule_side, left=-triple_between_rule, top=0.0, bottom=-@sf.panel_rule_over(), fn() {  }) |> ignore
}

///|
/// An option's words (`on`: picked) `w` wide, the widest of its column's picked: the column as wide whichever is.
fn triple_said(c : @ui.Ctx, words : String, on : Bool, w : Double) -> Unit {
  c.box(style=@ui.style(w=Fixed(w)), fn() { c.text(words, style=if on { triple_picked } else { triple_words }) |> ignore })
  |> ignore
}

///|
/// A select under the models, its name `head` over it (as a column's head is over its rows): its share of their line,
/// never less than what it says needs (a long runtime's name whole, the others sharing what is left).
fn triple_select_of(c : @ui.Ctx, head : String, select : () -> Unit) -> Unit {
  c.box(style=triple_select_box, keep=true, fn() {
    triple_column_head(c, head)
    select()
  })
  |> ignore
}

///|
/// A column's head (runPicker h4): 4 over it, 6 under, as far in as the rows' words.
fn triple_column_head(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=triple_head_box, fn() { c.text(words, style=triple_head) |> ignore }) |> ignore
}

///|
/// A row of a column (runPickerOption): as high as the screen's picker rows at least (Theme::rows pick), 4 by 10 in, its ground under the pointer and while picked,
/// `trail` (a button of its own, the station a model comes from) at its end, a check after it while picked (its room
/// kept while not, as the web's hidden check); `tip` over it while it is pointed at. True on the frame after a press.
fn triple_option(
  c : @ui.Ctx,
  key : String,
  label : String,
  on : Bool,
  body : () -> Unit,
  trail? : () -> Unit,
  tip? : String = "",
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  // (across its column, as wide as its words need at least: what the column needs, the panel's columns laid out by it)
  let b = c.box(style=(if on { triple_option_on } else { triple_option_style }).then(@ui.style(min_h=Fixed(t.rows.pick))), id~, keep=true, fn() {
    body()
    // what is at its end, at the end: the room left (no spacer of its own, whose gap took a gap's room from the
    // words), never less than it needs; the check's room kept while it is not picked
    c.box(style=triple_end, keep=true, fn() {
      match trail {
        Some(f) => f()
        None => ()
      }
      if on {
        @sf.icon(c, "check", size=14.0, color=t.p.accent) |> ignore
      } else {
        c.box(style=triple_check_room, fn() {  }) |> ignore
      }
    })
    |> ignore
  })
  c.semantics(b, Button, id~, label~)
  @sf.tip(c, key + "/tip", id, tip)
  c.clicked(id)
}

///|
/// The accounts (runPickerAccounts), in a panel of their own from who runs it: 自动 with what the station's pick is on
/// now (and at its end, a chat's, what has the station pick again now: `pick.repick`, which account it took said in a
/// toast), then each account with what is left of it; picked, back to the pick's panel.
fn triple_accounts(c : @ui.Ctx, src : Source, station : String, of : String, close : () -> Unit) -> Unit {
  let v = (src.topic)("pick", pick_params(station, of)).value
  let draft = field(v, "draft")
  c.box(style=triple_accounts_box, fn() {
    match text(v, "dropped") {
      "" => ()
      d => c.text(d, style=triple_amber_sm) |> ignore
    }
    let mine = text(draft, "profile")
    let repick = text(v, "repick")
    let repicking = "pick.repick/" + station + "/" + of
    if triple_option(
        c,
        "triple/account/",
        @sf.t("web-main.model.auto"),
        mine == "",
        fn() {
          c.box(style=triple_option_text, fn() {
            c.text(@sf.t("web-main.model.auto"), style=if mine == "" { triple_picked } else { triple_words }) |> ignore
            c.text(text(v, "autoNote"), style=triple_note_cut) |> ignore
          })
          |> ignore
        },
        trail?=if repick == "" {
          None
        } else {
          Some(fn() {
            let busy = doing(repicking)
            if busy {
              @sf.spinner(c, size=14.0) |> ignore
            }
            if @sf.panel_button(c, "triple/repick", repick) && !busy {
              act(src, repick, repicking, "pick.repick", Json::object(pick_params(station, of)), ok=fn(r) {
                match text(Some(r), "said") {
                  "" => ()
                  said => toast_later(said)
                }
              })
            }
          })
        },
      ) {
      pick_draft(src, station, of, { "profile": Json::null() })
      close()
    }
    for a in items(v, "accounts") {
      let a = Some(a)
      let id = text(a, "id")
      if triple_option(c, "triple/account/" + id, text(a, "name"), mine == id, fn() {
          c.box(style=triple_option_text, fn() {
            c.text(text(a, "name"), style=if mine == id { triple_picked } else { triple_words }) |> ignore
            let line = field(a, "quotaLine")
            match text(line, "text") {
              "" => ()
              q =>
                c.text(
                  q,
                  style=match text(line, "level") {
                    "amber" => triple_amber_sm
                    "red" => triple_red_sm
                    _ => triple_note
                  },
                )
                |> ignore
            }
          })
          |> ignore
        }) {
        pick_draft(src, station, of, { "profile": Json::string(id) })
        close()
      }
    }
  })
  |> ignore
}

///|
/// Borrowing the picked model's account from another station, asked first (ModelTriple.tsx's Dialog): what it does,
/// 取消 and its action.
fn borrow_dialog(c : @ui.Ctx, src : Source, station : String, of : String, v : Json?) -> Unit {
  let me = station + "\u{1}" + of
  let borrow = field(v, "borrow")
  let dkey = "pick.borrow/" + station + "/" + of
  let open = triple.borrow_asking == me && borrow is Some(Object(_))
  let lines = items(borrow, "lines").map(fn(l) {
    match l {
      String(s) => s
      _ => ""
    }
  })
  match wide_confirm(c, "borrow/" + me, open, text(borrow, "title"), lines, text(borrow, "action"), doing(dkey), flag(borrow, "allowed")) {
    Some(true) =>
      act(src, text(borrow, "action"), dkey, "pick.borrow", Json::object(pick_params(station, of)), done=@sf.t("web-main.model.borrowed"), ok=fn(_) {
        triple.borrow_asking = ""
      })
    Some(false) => triple.borrow_asking = ""
    None => ()
  }
}

///|
/// A dialog that asks before something is done (the web's Confirm, Dialog): its title, its lines, 取消 and `action`
/// (`danger`: in red). Some(true) on the frame after the action was pressed, Some(false) after 取消, Esc or a press
/// outside; None meanwhile.
fn wide_confirm(
  c : @ui.Ctx,
  key : String,
  open : Bool,
  title : String,
  lines : Array[String],
  action : String,
  busy : Bool,
  allowed : Bool,
) -> Bool? {
  let mut said : Bool? = None
  let d = @sf.dialog(
    c,
    key,
    open,
    title,
    w=dmin(confirm_w, c.width - 32.0),
    close_label=@sf.t("common.close"),
    fn() {
      for l in lines {
        c.text(l, style=confirm_line) |> ignore
      }
      c.box(style=confirm_foot, fn() {
        if small_button(c, key + "/cancel", @sf.t("common.cancel"), false, true) {
          said = Some(false)
        }
        if busy {
          @sf.spinner(c, size=14.0) |> ignore
        }
        if small_button(c, key + "/ok", action, true, allowed && !busy) {
          said = Some(true)
        }
      })
      |> ignore
    },
  )
  if open && !d && said is None {
    said = Some(false)
  }
  said
}

///|
/// A small panel's small pill (ModelTriple.css.ts btnSm): 24 high, 10 in, its words in 12; `primary` dark with light
/// words, else quiet with the ground on hover; not pressed while `on` is false. True on the frame after a press.
fn small_button(c : @ui.Ctx, key : String, words : String, primary : Bool, on : Bool) -> Bool {
  let id = c.id(key)
  let b = c.box(
    style=match (primary, on) {
      (true, true) => small_primary
      (true, false) => small_primary_off
      (false, _) => small_quiet
    },
    id~,
    fn() { c.text(words, style=if primary { small_primary_words } else { small_quiet_words }) |> ignore },
  )
  c.semantics(b, Button, id~, label=words)
  on && c.clicked(id)
}

///|
/// How wide a dialog that asks is (Dialog: 420).
let confirm_w : Double = 420.0

///|
/// A part of the control's line after the model (triplePart): what it says and the dot before it, left out whole.
// kept across runs: a value (no field of it changes)
let triple_part : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
/// The order the control's line leaves its parts out in, short of room (ModelTriple.tsx DROPS): who runs it by name
/// (in its part), who runs it, the runtime, how hard it thinks and how fast.
let triple_drop_name : Int = 1

///|
let triple_drop_account : Int = 2

///|
let triple_drop_runtime : Int = 3

///|
let triple_drop_effort : Int = 4

///|
/// The triple as a row's value (28 high at its end, in its middle): a capsule, as the round controls beside it are, its
/// shape its height's wherever the row's corners are (a row's corner with it at its end 10 in would be 10 here, 8.4 in
/// a finger's taller row, its own 8 in neither).
// kept across runs: a value (no field of it changes)
let triple_style : @ui.Style = @ui.css("row h=S7 px=S2_5 gap=S1_5 align=ACenter radius=Full hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let triple_on : @ui.Style = @ui.css("row h=S7 px=S2_5 gap=S1_5 align=ACenter radius=Full bg=Hover")

///|
// kept across runs: a value (no field of it changes)
let triple_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let triple_picked : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let triple_muted : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let triple_amber : @ui.TextStyle = @ui.text_style(size=Ui, color=WarnInk, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let triple_red : @ui.TextStyle = @ui.text_style(size=Ui, color=Danger, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let triple_amber_sm : @ui.TextStyle = @ui.text_style(size=Meta, color=WarnInk)

///|
// kept across runs: a value (no field of it changes)
let triple_red_sm : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger)

///|
// kept across runs: a value (no field of it changes)
let triple_note : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// What the station's pick is on, under 自动: cut short where what picks again beside it needs the room.
// kept across runs: a value (no field of it changes)
let triple_note_cut : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=Cut)

///|
/// A column's head (runPicker h4): 12, muted, medium; 4 over it, 6 under, as far in as the rows' words.
// kept across runs: a value (no field of it changes)
let triple_head : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let triple_search : @ui.Style = @ui.css("w=Full pb=S2")

///|
/// A line across (a history's under its figures; the panel's over its foot is the presenters', `ruled`: kept,
/// 2026-10-25 用户「这两个的分割线可以保留」).
// kept across runs: a value (no field of it changes)
pub let triple_rule_h : @ui.Style = @ui.css("w=Full h=SPx bg=Line")


///|
/// The models and the rest beside them (a line between, in the middle of the 8 between them), or the models alone
/// across the panel where the rest left the row; as tall as the room a sheet held to its most leaves them (the models
/// scroll in it), else as tall as they are.
// kept across runs: a value (no field of it changes)
let triple_columns : @ui.Style = @ui.style(row=true, w=Full, h=@sf.grow, gap=S2)

///|
/// The models' column: what the rest leaves of the panel, 200 at least (the web's).
// kept across runs: a value (no field of it changes)
let triple_models : @ui.Style = @ui.style(w=@sf.grow, min_w=Within(triple_models_least))

///|
pub let triple_models_least : Double = 200.0

///|
/// The runtimes, how hard it thinks and how fast beside the models: columns as wide as their words, 8 apart, a line
/// between; there whole or not at all (a row's `drop`).
// kept across runs: a value (no field of it changes)
let triple_rest : @ui.Style = @ui.css("row gap=S2")

///|
// kept across runs: a value (no field of it changes)
let triple_column : @ui.Style = @ui.css("gap=SPx")

///|
/// Where the line before a column beside another starts, from its start: in the middle of the 8 between them.
let triple_between_rule : Double = 4.5

///|
/// The line before a column beside another: as tall as the column.
// kept across runs: a value (no field of it changes)
let triple_rule_side : @ui.Style = @ui.css("w=SPx bg=Line")

///|
/// The selects under the models (the runtime, how hard it thinks, how fast): side by side, each its share, 8 apart,
/// 8 under the models.
// kept across runs: a value (no field of it changes)
let triple_selects : @ui.Style = @ui.css("row w=Full pt=S2 gap=S2")

///|
/// A select's share of their line: its name over it.
// kept across runs: a value (no field of it changes)
let triple_select_box : @ui.Style = @ui.style(w=@sf.grow, gap=SPx)

///|
/// How wide a select is at most: all of its share.
let triple_select_most : Double = 1.0e9

///|
/// A column's rows, 1 apart.
// kept across runs: a value (no field of it changes)
let triple_rows : @ui.Style = @ui.css("w=Full gap=SPx")


///|
// kept across runs: a value (no field of it changes)
let triple_option_style : @ui.Style = @ui.css(
  #|row w=Full px=S2_5 py=S1 gap=S1_5 align=ACenter radius=Xl hovered{bg=Hover}
)

///|
// kept across runs: a value (no field of it changes)
let triple_option_on : @ui.Style = @ui.css(
  #|row w=Full px=S2_5 py=S1 gap=S1_5 align=ACenter radius=Xl bg=Hover
)

///|
// kept across runs: a value (no field of it changes)
let triple_option_text : @ui.Style = @ui.css("gap=SPx")

///|
/// A model's name in its row: across the room left in it, on two lines where it needs them (cut short past those, a
/// name longer than any).
// kept across runs: a value (no field of it changes)
let triple_row_name : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, w=Full, max_lines=2)

///|
// kept across runs: a value (no field of it changes)
let triple_row_picked : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, w=Full, max_lines=2)

///|
/// A model's name and what is under it: as wide as said, giving way to the room its row leaves where that is less.
// kept across runs: a value (no field of it changes)
let triple_name_column : @ui.Style = @ui.css("min_w=SPx gap=SPx")

///|
/// Where a row's check is while it is not picked: the row as wide picked or not (its column's words then as wide).
// kept across runs: a value (no field of it changes)
let triple_check_room : @ui.Style = @ui.css("w=S3_5")

///|
// kept across runs: a value (no field of it changes)
let triple_empty : @ui.Style = @ui.css("px=S2_5 py=S2")

///|
// kept across runs: a value (no field of it changes)
let triple_borrow : @ui.Style = @ui.css("w=Full px=S2_5 py=S1_5")


///|
// kept across runs: a value (no field of it changes)
let triple_who_room : @ui.Style = @ui.style(row=true, w=@sf.grow, h=Full, align=ACenter)

///|
/// Who runs it, a capsule at the foot's start as tall as the foot's buttons (@sf.button_height), so standing in the
/// panel's foot corner where they stand in the other, concentric with it, as far from its foot as from its side.
fn triple_who() -> @ui.Style {
  triple_who_look.then(@ui.style(h=Fixed(@sf.button_height())))
}

///|
// kept across runs: a value (no field of it changes)
let triple_who_look : @ui.Style = @ui.css("row px=S2_5 gap=S1 align=ACenter radius=Full hovered{bg=Hover}")


///|
// kept across runs: a value (no field of it changes)
let triple_who_lead : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let triple_who_name : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let triple_accounts_box : @ui.Style = @ui.css("w=Full min_w=S56 gap=SPx")

///|
// kept across runs: a value (no field of it changes)
let small_primary : @ui.Style = @ui.css("h=S6 px=S2_5 align=ACenter justify=JCenter radius=Full bg=Primary")

///|
// kept across runs: a value (no field of it changes)
let small_primary_off : @ui.Style = @ui.css(
  #|h=S6 px=S2_5 align=ACenter justify=JCenter radius=Full bg=Primary opacity=O50
)

///|
// kept across runs: a value (no field of it changes)
let small_quiet : @ui.Style = @ui.css("h=S6 px=S2_5 align=ACenter justify=JCenter radius=Full hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let small_primary_words : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=OnPrimary, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let small_quiet_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let confirm_line : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let confirm_foot : @ui.Style = @ui.css("row w=Full pt=S3 gap=S2 align=ACenter justify=JEnd")

///|
/// The models beside what opened it: 360 high at most (runPicker).
let triple_list_h : Double = 360.0

///|
/// The most the panel is wide beside its control, as wide as its columns' words within it (the web's: the models' 200
/// to 300, the runtimes' and the efforts' columns).
let triple_panel_w : Double = 520.0

///|
// kept across runs: a value (no field of it changes)
let triple_head_box : @ui.Style = @ui.css("px=S2_5 pt=S1 pb=S1_5")

///|
/// In a composer's row (newChat's): 28 high, 8 in, its words 12.
// kept across runs: a value (no field of it changes)
let triple_small : @ui.Style = @ui.css("row h=S7 px=S2 gap=S1_5 align=ACenter radius=Lg hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let triple_small_on : @ui.Style = @ui.css("row h=S7 px=S2 gap=S1_5 align=ACenter radius=Lg bg=Hover")

///|
// kept across runs: a value (no field of it changes)
pub let triple_words_xs : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
/// The model's name in the control: its words, cut short once all that may leave the control's row has left.
// kept across runs: a value (no field of it changes)
let triple_name : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let triple_name_xs : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
pub let triple_muted_xs : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// The control of the pick `of` on `station` with its panel open (a screen's fixture).
pub fn open_triple(station : String, of : String) -> Unit {
  triple.asked = station + "\u{1}" + of
}
