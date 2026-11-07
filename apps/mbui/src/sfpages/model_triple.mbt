// The one way a model is chosen (still.fail web/src/ModelTriple.tsx, ModelTriple.css.ts; NewChat.kt's run picker said the
// same): a control that says the model, the runtime (where it can still change and the model runs on more than one),
// how hard it thinks and who runs it, in one line; pressed, its panel through the presenters (beside it with keyboard and mouse,
// a sheet with touch): the models, each saying how it runs picked (as it last ran here), the ones used most nearest
// what opened it, the rest past them (a filter over them when there are many); between them and it the runtime, the
// effort and the speed, every name whole; at its foot who runs it (the accounts in a panel of their own, from it).
// Its rows are the screen's (Theme::rows pick). Each pick is made what it runs on as it is picked (`pick.save`), a
// model closing the panel; a model another station has is drafted (`pick.set`) and borrowed first, asked in a dialog.

///|
/// What the control keeps of its own (the pick is the core's): the one whose panel is open (its station and pick, ""
/// none) and that panel (@sf.last_presented), the one asked open (a screen's fixture, a page's) and whether its accounts
/// are asked open in it too (a screen's fixture), and the borrowing it asks to confirm ("" none). Each panel keeps its
/// own contents and filter while it is shown.
priv struct Triple {
  mut open : String
  mut shown : Int
  mut asked : String
  mut accounts_asked : Bool
  mut borrow_asking : String
}

///|
let triple : Triple = { open: "", shown: 0, asked: "", accounts_asked: false, borrow_asking: "" }

///|
/// One panel's filter, what it shows and its pick: whether all the models are shown (past those used most and
/// starred) and the maker whose models they are ("" the picked model's; in a sheet, none yet: the makers). Once
/// closed, its last pick stays with it while it leaves: saving a different model may change its options and height
/// immediately, but must not rearrange the panel that is already going away.
priv struct TriplePanel {
  mut serial : Int
  field : @ui.Field
  mut query : String
  mut kind : String
  mut all : Bool
  mut pick : Json?
  /// whether its body was drawn last as a sheet's (its foot then leaves the runtime to the body: triple_foot)
  mut sheet : Bool
  /// the level the model picked was last brought into view in (its first, all of them, a kind's; "" none yet): once
  /// as each is come to, not each frame, so what the person scrolled stays where they left it
  mut shown : String
}

///|
fn TriplePanel::pick_now(self : TriplePanel, src : Source, station : String, of : String) -> Json? {
  if @sf.presented_open_of(self.serial) {
    // (until its own is read, what the page that opened it has: the same pick, so it opens as it stays, not first
    // in its bones somewhere else)
    match src.topic("pick", pick_params(station, of)).get().value {
      Some(_) as v => self.pick = v
      None => ()
    }
  }
  self.pick
}

///|
fn triple_reset() -> Unit {
  triple.open = ""
  triple.shown = 0
  triple.asked = ""
  triple.accounts_asked = false
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
/// What the panel picked made what it runs on at once (`pick.save` given the picks `patch`), said once done with `done`
/// ("" nothing: a change in the panel, which stays open and shows it).
fn pick_save(src : Source, station : String, of : String, patch : Map[String, Json], done? : String = "") -> Unit {
  let p = pick_params(station, of)
  for k, v in patch {
    p[k] = v
  }
  act(src, @sf.t("common.confirm"), "pick.save/" + station + "/" + of, "pick.save", Json::object(p), done~)
}

///|
/// The panel of the pick `of` on `station` (the control's: see model_triple) opened beside `from`: from the control,
/// or from elsewhere that says what runs (an agent's card's account: `side` Right, beside the card). Opened already,
/// it closes (a trigger toggles it: one the panel does not cover, the card's, stays pressable while it is open).
/// `page`: the pick as the page that opened it has it (a new chat's), shown until the panel's own is read.
pub fn open_triple_panel(
  src : Source,
  station : String,
  of : String,
  from : @sf.Anchor,
  saved? : String = "",
  side? : @ui.Side = Bottom,
  page? : Json? = None,
) -> Unit {
  let me = station + "\u{1}" + of
  if triple.open == me {
    @sf.close_presented_of(triple.shown)
    return
  }
  triple.open = me
  let contents : TriplePanel = { serial: 0, field: @ui.Field::new(), query: "", kind: "", all: false, pick: page, sheet: false, shown: "" }
  pick_draft(src, station, of, { "open": Json::boolean(true) })
  @sf.panel(
    @sf.t("android-chat.new.model"),
    fn(c, close) { triple_panel(c, src, station, of, contents, saved, close) },
    from~,
    w=triple_panel_w,
    // (as wide as its columns' words, no wider: 2026-10-26 用户「没啥内容也这么宽感觉会很奇怪」)
    fits=true,
    foot=fn(c, close) { triple_foot(c, src, station, of, contents, close) },
    // (beside what opened it, its title over its models' column, its search beside it, how hard it thinks titled over
    // its own: triple_body's; 2026-11-02 用户「搜索在左边区域，思考深度和模型在同一个层级」)
    heads_itself=true,
    gone=fn() { triple.open = "" },
    focus=false,
    // (the models scroll by themselves, what goes with the one picked beside them in view)
    lists=true,
    fade_out_together=true,
    // (a line over its foot out to its sides: 2026-11-02 用户「下面整体一根通的分割线」, in place of 2026-10-30's none)
    ruled=true,
    side~,
  )
  contents.serial = @sf.last_presented()
  triple.shown = contents.serial
}

///|
/// The control of the pick `of` on `station` (ModelTriple): its line, and its panel under it while open (above it with
/// `up`). `page`: the control as a page has it with itself (a new chat's: its `pick`), not read on its own; `small`: in
/// a composer's row (ModelTriple.css.ts in newChat: 28 high, its words 12). `saved`: what is said once a model picked
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
    None => src.topic("pick", pick_params(station, of)).get().value
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
    open_triple_panel(src, station, of, Of(id), saved~, page~)
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
        let marked = profile is Some(Object(_))
        // (the dot before it goes with what follows it: its mark where it has one, else its name, never left alone)
        if marked {
          c.box(style=triple_part, drop=triple_drop_account, fn() {
            c.text("·", style=muted) |> ignore
            @sf.maker_mark(c, text(profile, "mark"), runtime, 14.0) |> ignore
          })
          |> ignore
        }
        let level = text(account, "level")
        c.box(style=if marked { triple_alone } else { triple_part }, drop=triple_drop_name, fn() {
          if !marked {
            c.text("·", style=muted) |> ignore
          }
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
/// The panel: the filter across its top (more than 8 models), the models (one picked, `saved` said and the panel
/// closed: triple_model_row), and between them and what opened it the runtimes (where there are
/// more than one), how hard it thinks and how fast, each a segmented choice: the models scrolling by themselves, what
/// goes with them in view. What borrowing would do under them. Beside what opened it the models scroll past 360 (the
/// web's); in a sheet the sheet is as tall as all of it up to its most, the models scrolling in what is left then
/// (@sf.panel_column).
fn triple_panel(c : @ui.Ctx, src : Source, station : String, of : String, contents : TriplePanel, saved : String, close : () -> Unit) -> Unit {
  let v = contents.pick_now(src, station, of)
  if v is None {
    // (read the first time: the panel of made-up models, in its bones; the model picked brought into view once its own
    // are read)
    let shown = contents.shown
    @sf.waiting(c, fn() { triple_body(c, @sfbase.sample_source, station, of, contents, Some(triple_sample()), saved, close) })
    contents.shown = shown
    return
  }
  triple_body(c, src, station, of, contents, v, saved, close)
}

///|
/// The panel's models, runtimes, how hard it thinks and how fast, as the core's `pick` (`v`) offers them.
fn triple_body(
  c : @ui.Ctx,
  src : Source,
  station : String,
  of : String,
  contents : TriplePanel,
  v : Json?,
  saved : String,
  close : () -> Unit,
) -> Unit {
  let options = items(v, "options")
  let draft = field(v, "draft")
  let words = contents.query.trim(chars=" ").to_string().to_lower()
  // (the search, where the panel's head has none: a sheet's, its head its own)
  if !@sf.in_small_panel() && options.length() > 8 {
    c.box(style=triple_search, fn() { triple_find_field(c, contents, v) }) |> ignore
  }
  let listed = options.filter(fn(o) {
    let o = Some(o)
    words == "" ||
    text(o, "name").to_lower().contains(words) ||
    text(o, "model").to_lower().contains(words) ||
    items(o, "ids").iter().any(fn(i) { i is String(s) && s.to_lower().contains(words) })
  })
  // two levels (2026-11-02 用户「两级优化」): first the models used most here (the core's `near`), nearest what opened
  // the panel, then those starred (`liked`), then the way to all of them; there, every model of a maker (the core's
  // `makers`, 「分组应该是模型厂商，而不是供应商」; 「我 20 个 provider 你怎么排」: a list of them, not a row), each starred
  // there by the box before it (「星标改成前面的选择框」). Typed, every one that matches, whatever its kind. None used nor starred: all of them at
  // once.
  let searching = words != ""
  let model_of = fn(id : Json) -> Json? {
    guard id is String(id) else { return None }
    options.search_by(fn(o) { text(Some(o), "model") == id }).map(fn(i) { options[i] })
  }
  let near : Array[Json] = items(v, "near").filter_map(model_of)
  let liked : Array[Json] = items(v, "liked").filter_map(model_of)
  let all = searching || contents.all || (near.is_empty() && liked.is_empty())
  let kinds = items(v, "makers")
  let kind_of = fn(o : Json) -> String { text(field(Some(o), "maker"), "id") }
  // (the kind browsed: as chosen, else the picked model's, else the first)
  let kind = if kinds.iter().any(fn(k) { text(Some(k), "id") == contents.kind }) {
    contents.kind
  } else {
    match model_of(Json::string(text(v, "option"))) {
      Some(o) if kinds.iter().any(fn(k) { text(Some(k), "id") == kind_of(o) }) => kind_of(o)
      _ => kinds.get(0).map(fn(k) { text(Some(k), "id") }).unwrap_or("")
    }
  }
  // (a sheet: the kinds, a kind's models a step further; beside what opened it, the two side by side)
  let sheet = !@sf.in_small_panel()
  contents.sheet = sheet
  let kind_open = !sheet || contents.kind != ""
  let rest = listed.filter(fn(o) {
    searching || kinds.length() < 2 || kind_of(o) == kind
  })
  let series : Array[(String, Array[Json])] = []
  for o in rest {
    let who = match text(Some(o), "family") {
      "" => @sf.t("web-main.model.otherSeries")
      f => f
    }
    match series.search_by(fn(s) { s.0 == who }) {
      Some(i) => series[i].1.push(o)
      None => series.push((who, [o]))
    }
  }
  let efforts = items(v, "efforts")
  let fast = flag(v, "fastAvailable")
  let all_efforts : Array[(String, String)] = []
  // (no level for the model's own: 2026-11-02 用户「思考深度不再提供默认」)
  if efforts.length() > 0 {
    for e in efforts {
      if e is String(e) {
        all_efforts.push((e, effort_text(e)))
      }
    }
  }
  let all_contexts : Array[(String, String)] = items(v, "contexts").map(fn(o) { (text(Some(o), "id"), text(Some(o), "text")) })
  // (each made what it runs on at once, the panel staying open: kept for the model too, as it runs next time it is
  // picked)
  let pick_effort = fn(e : String) {
    pick_save(src, station, of, { "effort": if e == "" { Json::null() } else { Json::string(e) } })
  }

  // what each says of how it runs right after its name, on its line (2026-11-02 用户「常用模型的信息分两边很难读」,
  // 「移动端…跟在模型后面」; under it, two lines, rejected: 「到底为什么要两行」); as wide as the widest of it, the one
  // picked's at whatever it is picked to: the panel as wide whatever is picked in it (its widest kept: a depth picked
  // wider, it would grow)
  let picked = text(v, "option")
  let many = options
    .search_by(fn(o) { text(Some(o), "model") == picked })
    .map(fn(i) { items(Some(options[i]), "runtimes").length() > 1 && !flag(v, "runtimeFixed") })
    .unwrap_or(false)
  // (the widest of the less context it can be kept to after them: 500K)
  let context_said = all_contexts.fold(init="", fn(m, o) {
    if o.0 != "" && o.1.length() > m.length() { o.1 } else { m }
  })
  let said_as = fn(e : String, fast_on : Bool) {
    let parts = []
    if many {
      parts.push(@settings.runtime_label(text(draft, "runtime")))
    }
    if e != "" {
      parts.push(effort_text(e))
    }
    if fast_on {
      parts.push("Fast")
    }
    if context_said != "" {
      parts.push(context_said)
    }
    parts.join(" · ")
  }
  let usual_w = options.fold(init=0.0, fn(m, o) { dmax(m, c.words_across(text(Some(o), "usualText"), triple_note)) })
  let usual_w = all_efforts.fold(init=usual_w, fn(m, e) {
    dmax(dmax(m, c.words_across(said_as(e.0, false), triple_note)), if fast { c.words_across(said_as(e.0, true), triple_note) } else { 0.0 })
  })
  let usual_w = if all_efforts.is_empty() { dmax(usual_w, c.words_across(said_as("", fast), triple_note)) } else { usual_w }
  // each column's words as wide as the widest of them picked (the models' of all of them, whatever the filter leaves):
  // the panel, as wide as what it holds, as wide whichever is picked and whatever is typed (as a segmented choice's)
  let names_w = options.fold(init=0.0, fn(m, o) {
    let o = Some(o)
    let name = c.words_across(text(o, "name"), triple_row_picked)
    let name = if usual_w > 0.0 { name + @ui.Space::px(S1_5) + usual_w } else { name }
    dmax(dmax(m, name), c.words_across(text(field(o, "spent"), "text"), triple_note))
  })
  let names_w = names_w.ceil()
  // each as what it is (2026-10-30 用户「思考这些选项各自的特点」): the models many, their names long, each its maker's
  // mark: a list, scrolling by itself, every name whole (「看不出是什么模型怎么办」). Beside it, in view whatever model
  // is picked (「用户选完模型根本看不到下面的 runtime 和思考深度」), the rest as the few they are, each a segmented
  // choice across the panel with its name over it: the runtimes the model runs on (none where it runs on one: nothing
  // to choose), how hard it thinks (an order, from the model's own to the most, read along its line), how fast (three
  // ways). Each gives way where its line is short as a segmented choice does (its words closer, smaller, else the one
  // chosen alone and the rest in a pick: a narrow sheet's)
  // nearest what opened the panel what is used most, farthest what is not (2026-11-01 用户「那它就不应该跑到离按钮很远
  // 的最顶上去啊」): opening up from it (a composer's, at the foot of its page) or a sheet risen from the screen's foot,
  // from the foot up how it runs, the models used most (the most used lowest), then the rest; opening down, the same
  // from the top down. What is used most stays put; the rest scrolls by itself.
  // (the panel at least as wide as a row with the widest name and the widest of how it runs, where it has the room:
  // as wide whatever depth is picked in it)
  // (and the box before it where all of them are listed)
  let row_least = names_w + 14.0 + triple_box_side + 4.0 * @ui.Space::px(S1_5) + 2.0 * @ui.Space::px(S2_5) +
    @ui.Space::px(S3_5)
  c.box(style=@ui.style(min_w=Within(row_least)), fn() {  }) |> ignore
  let up = @sf.panel_opens_up()
  // a kind's models (all that match what is typed), scrolling by themselves
  let model_rows = fn() {
    @sf.panel_column(c, "triple/models/" + (if searching { "" } else { kind }), triple_list_h, triple_rows, fn() {
      // (no head of its own: what is over it says what they are; each series under its name where there are more than
      // one (2026-11-02 用户「要保留模型分组，opus 系列之类的」), its models together)
      for s in series {
        if series.length() > 1 {
          triple_column_head(c, s.0)
        }
        for o in s.1 {
          triple_model_row(c, src, station, of, v, Some(o), names_w, saved, close, likes=true)
        }
      }
      if listed.length() == 0 {
        c.box(style=triple_empty, fn() { c.text(@sf.t("web-main.model.noMatch"), style=triple_muted) |> ignore })
        |> ignore
      }
    })
  }
  // the makers, a row each: its mark, its name, how many of the models it makes; the one browsed lit
  let kind_rows = fn() {
    @sf.panel_column(c, "triple/kinds", triple_list_h, triple_rows, fn() {
      for k in kinds {
        let kv = Some(k)
        let id = text(kv, "id")
        let on = kind_open && id == kind
        let count = match field(kv, "count") {
          Some(Number(n, ..)) => n.to_int().to_string()
          _ => ""
        }
        if triple_option(
            c,
            "triple/kind/" + id,
            text(kv, "title"),
            on,
            fn() {
              c.box(style=triple_kind_mark, fn() { @sf.maker_mark(c, id, "", 14.0) |> ignore }) |> ignore
              c.text(text(kv, "title"), style=if on { triple_picked } else { triple_words }) |> ignore
            },
            trail=fn() { c.text(count, style=triple_usual) |> ignore },
            // (a maker is browsed, not picked: lit, no check)
            checks=false,
          ) {
          contents.kind = id
        }
      }
    })
  }
  // all of them: typed, those that match; else the kinds and a kind's models (side by side beside what opened the
  // panel; in a sheet, a kind's a step past the kinds), the way back over them where there is one
  let models = fn() {
    let back_to = if searching {
      ""
    } else if sheet && contents.kind != "" && kinds.length() > 1 {
      text(kinds.iter().find_first(fn(k) { text(Some(k), "id") == kind }), "title")
    } else if !near.is_empty() || !liked.is_empty() {
      @sf.t("web-main.model.allModels")
    } else {
      ""
    }
    if back_to != "" {
      if triple_option(c, "triple/back", back_to, false, fn() {
          @sf.icon(c, "chevron-left", size=14.0, color=@sf.theme().p.muted) |> ignore
          c.text(back_to, style=triple_picked) |> ignore
        }) {
        if sheet && contents.kind != "" {
          contents.kind = ""
        } else {
          contents.all = false
        }
      }
    }
    if searching || kinds.length() < 2 {
      model_rows()
    } else if sheet {
      if contents.kind == "" { kind_rows() } else { model_rows() }
    } else {
      c.box(style=triple_browse, fn() {
        c.box(style=triple_kinds_column, fn() { kind_rows() }) |> ignore
        c.box(style=triple_rule_v, fn() {  }) |> ignore
        c.box(style=triple_models_column, fn() { model_rows() }) |> ignore
      })
      |> ignore
    }
  }
  // (each named, as what they are: 2026-11-01 用户「感觉还是得标注一下常用」; nearest what opened the panel the first of
  // them)
  let section = fn(head : String, rows : Array[Json], star : Bool) {
    if rows.length() == 0 {
      return
    }
    c.box(style=triple_rows, fn() {
      if head != "" {
        triple_column_head(c, head)
      }
      for o in if up { rows.rev() } else { rows } {
        triple_model_row(c, src, station, of, v, Some(o), names_w, saved, close, star~)
      }
    })
    |> ignore
  }
  // (neither with a head of its own: 2026-11-02 用户「去掉喜欢两个字」「去掉常用两个字吧」; told apart by the room
  // between them and the stars of those starred)
  let used = fn() { section("", near, false) }
  let starred = fn() { section("", liked, true) }
  // the way to all of them, farthest from what opened the panel
  let to_all = fn() {
    if triple_option(
        c,
        "triple/all",
        @sf.t("web-main.model.allModels"),
        false,
        // (its chevron right after its words: 「全部模型的箭头跟在文字后面」)
        fn() {
          c.text(@sf.t("web-main.model.allModels"), style=triple_words) |> ignore
          @sf.icon(c, "chevron-right", size=14.0, color=@sf.theme().p.muted) |> ignore
        },
        checks=false,
      ) {
      contents.all = true
    }
  }
  // how hard it thinks beside what opened the panel: its own column at the panel's right, beside the models, its
  // levels one under another (2026-11-02 用户「思考深度放在整个面板的右边」「模型跟思考深度的并排的」); in a sheet
  // (「手机上只有模型是平铺的」) a pick of its own under the models, as the runtime's, its levels in a sheet of their own
  // (「手机上思考深度变回一个 select，点了弹出来」「抽屉」). How fast is at the foot, by who runs it.
  let h_effort = @sf.t("web-main.model.effort")
  // (none picked, the model's own where its runtime says it: 2026-11-02 用户「能拿到默认档就勾上它」)
  let effort_now = match text(draft, "effort") {
    "" => text(v, "effortDefault")
    e => e
  }
  let effort_column = fn() {
    triple_choices(c, "triple/effort", "", all_efforts, effort_now, pick_effort)
  }
  // (in a sheet the runtime a pick under how hard it thinks, as it is, the foot only who runs it and how fast; beside
  // what opened it, at the foot)
  let runs_on = if flag(v, "runtimeFixed") { [] } else { items(v, "runtimes").filter_map(fn(r) { if r is String(r) { Some(r) } else { None } }) }
  let how = fn() {
    if sheet && (all_efforts.length() > 0 || runs_on.length() > 1) {
      let h_runtime = @sf.t("web-main.model.runtime")
      let head_w = [h_effort, h_runtime].fold(init=0.0, fn(m, h) { dmax(m, c.words_across(h, triple_head)) }).ceil()
      c.box(style=if up { triple_tray } else { triple_tray_first }, fn() {
        if all_efforts.length() > 0 {
          triple_pick_row(
            c,
            "triple/effort",
            h_effort,
            head_w,
            all_efforts.map(fn(o) { @sf.choice(o.0, o.1) }),
            effort_now,
            pick_effort,
          )
        }
        if runs_on.length() > 1 {
          triple_pick_row(
            c,
            "triple/runtime",
            h_runtime,
            head_w,
            runs_on.map(fn(r) { @sf.choice(r, @settings.runtime_label(r), icon="runtime:" + r) }),
            text(draft, "runtime"),
            fn(r) { pick_save(src, station, of, { "runtime": Json::string(r) }) },
          )
        }
      })
      |> ignore
    }
  }
  // beside what opened it, its title (and its search) over the models (heads_itself)
  let models_head = fn() {
    if !sheet {
      if options.length() > 8 {
        @sf.panel_head(c, @sf.t("android-chat.new.model"), end=fn(c) { triple_find_field(c, contents, v) })
      } else {
        @sf.panel_head(c, @sf.t("android-chat.new.model"))
      }
    }
  }
  if all {
    models_head()
    models()
  } else {
    // its parts told apart by the room between them and what marks them (2026-11-02 用户「感觉有点难以分辨各个部分」,
    // 「分割线太丑了」): the way to all of them, those starred (each its star), those used most (named); how it runs on a
    // ground of its own past them
    let parts : Array[() -> Unit] = [to_all]
    if !liked.is_empty() {
      parts.push(starred)
    }
    // (in a sheet the way to all of them and those starred scroll by themselves in what the rest leaves, those used
    // most staying put by how it runs, as a kind's models do: a sheet held to its most, a short window's or one the
    // keyboard has risen into, has no room for all of them; 2026-11-02 the person's phone, 账号 over 速度 and over a
    // model)
    let kept = sheet && !near.is_empty()
    if !near.is_empty() && !kept {
      parts.push(used)
    }
    let apart = fn() {
      if sheet {
        @sf.panel_column(c, "triple/first", triple_list_h, triple_parts, fn() { for part in parts { part() } })
      } else {
        c.box(style=triple_parts, fn() { for part in parts { part() } }) |> ignore
      }
    }
    let used_kept = fn() { c.box(style=if up { triple_part_under } else { triple_part_over }, used) |> ignore }
    let first = fn() {
      if up {
        apart()
        if kept {
          used_kept()
        }
        how()
      } else {
        how()
        if kept {
          used_kept()
        }
        parts.rev_in_place()
        apart()
      }
    }
    if sheet || all_efforts.length() == 0 {
      models_head()
      first()
    } else {
      // (the models and how hard it thinks side by side, each titled alike over it, the line between them up to the
      // panel's top: 「上面的分割线试试到顶」)
      // (the way to all of them at the foot of the models' column, under those starred and used most, level with the
      // last of the levels beside them, as a list's 「查看全部」 is: 2026-11-02 用户「全部模型的位置需要讲究一下」)
      // (those used most first, then those starred: what it runs on now in view whatever is starred)
      let near_parts : Array[() -> Unit] = []
      if !near.is_empty() {
        near_parts.push(used)
      }
      if !liked.is_empty() {
        near_parts.push(starred)
      }
      c.box(style=triple_side_by_side, fn() {
        // (the way to all of them at the column's foot, what is over it at its top: no room that grows, which would
        // have the panel ask for all the window's height)
        c.box(style=triple_models_column.then(triple_ends_apart), fn() {
          c.box(style=triple_models_top, fn() {
            models_head()
            // (those used most and starred scrolling by themselves past the most the models' list has, the way to all
            // of them staying in view under them: 「数量多的时候呢？」)
            c.capped("triple/near", triple_list_h, shrinks=true, fn() {
              c.box(style=triple_parts, fn() { for part in near_parts { part() } }) |> ignore
            })
            |> ignore
          })
          |> ignore
          c.box(style=triple_all_room, to_all) |> ignore
        })
        |> ignore
        c.box(style=triple_effort_column, fn() {
          // (the line between them out of their flow, in the middle of the room between them, from the panel's top
          // down to the line over its foot, meeting it: 「竖的那根怎么没跟横的接起来呢」)
          c.box(style=triple_rule_v, left=-triple_between_rule, top=-@sf.panel_pad, bottom=-@sf.panel_rule_over(), fn() {  })
          |> ignore
          @sf.panel_head(c, h_effort)
          effort_column()
        })
        |> ignore
      })
      |> ignore
    }
  }
  // the model picked in view as the panel opens and as each level is come to (2026-11-05 用户「模型选择面板打开不会自动
  // 滚动到能看见已选择模型的地方」), not while what is typed filters them
  let level = if !all { "first" } else if kind_open { "all/" + kind } else { "all" }
  if !searching && contents.shown != level {
    contents.shown = level
    c.show(c.id("triple/model/" + picked))
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
/// The models' search where there are more than 8 of them (the pick `v`'s): round, on the words' tint, no line round it,
/// its glass before its words, its ground deeper pointed at or typed in (2026-10-30 用户「搜索也优化一下」「感觉它不应该
/// 单独一行」: beside what opened it, at the end of the panel's head, beside its title).
fn triple_find_field(c : @ui.Ctx, contents : TriplePanel, v : Json?) -> Unit {
  guard items(v, "options").length() > 8 else { return }
  let t = @sf.theme()
  // (in the panel's top corner, the head standing it where it is concentric with it: panel_head's `end`)
  triple_find_input(c, t, contents)
}

///|
/// The search's field itself (triple_find_field).
fn triple_find_input(c : @ui.Ctx, t : @sf.Theme, contents : TriplePanel) -> Unit {
  let res = @kit.text_field(
    c,
    "triple/filter",
    placeholder=@sf.t("web-main.model.search"),
    size=t.t.ui,
    line=t.t.ui_line,
    field=contents.field,
    look=fn(c, s, editor) {
      c.box(id=s.id, style=(if s.hovered || s.focused { triple_find_hot } else { triple_find }).then(@ui.style(h=Fixed(@sf.menu_row_min))), fn() {
        @sf.icon(c, "search", size=triple_find_icon, color=t.p.muted) |> ignore
        c.box(style=triple_find_words, editor) |> ignore
      })
      |> ignore
    },
  )
  contents.query = res.text
}

///|
/// Who runs it, at the foot's start beside 取消 and 确定 (the web's panel's foot, the phone's sheet's): the accounts in a
/// panel of their own, from it.
fn triple_runs_who(c : @ui.Ctx, src : Source, station : String, of : String, v : Json?) -> Unit {
  let draft = field(v, "draft")
  let who = c.id("triple/who")
  if c.clicked(who) || triple.accounts_asked {
    triple.accounts_asked = false
    @sf.panel(
      @sf.t("web-main.model.account"),
      fn(c, close) { triple_accounts(c, src, station, of, close) },
      from=Of(who),
      focus=false,
    )
  }
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
  })
  |> ignore
}

///|
/// What it runs on where its model runs on more than one, at the foot beside who runs it (2026-11-02 用户「运行时不应该
/// 放那个位置吧」): its name and the one picked; pressed, the runtimes in a pick.
fn triple_runtime(c : @ui.Ctx, src : Source, station : String, of : String, v : Json?) -> Unit {
  let head = @sf.t("web-main.model.runtime")
  let now = text(field(v, "draft"), "runtime")
  let choices = items(v, "runtimes").filter_map(fn(r) {
    if r is String(r) { Some(@sf.choice(r, @settings.runtime_label(r), icon="runtime:" + r)) } else { None }
  })
  let id = c.id("triple/runtime")
  if c.clicked(id) {
    @sf.pick(head, choices, now, fn(r) { pick_save(src, station, of, { "runtime": Json::string(r) }) }, from=Of(id), search=false)
  }
  let b = c.box(style=triple_who(), id~, fn() {
    c.text(head, style=triple_who_lead) |> ignore
    @sf.maker_mark(c, "", now, triple_pick_mark) |> ignore
    c.text(@settings.runtime_label(now), style=triple_who_name) |> ignore
  })
  c.semantics(b, Button, id~, label=@settings.runtime_label(now))
}

///|
/// How fast it runs, at the foot beside who runs it (2026-11-02 用户「速度放在面板下面，跟账号差不多的位置」): its name
/// and how fast it runs; pressed, the two ways in a pick. None picked, how fast its account runs it, said as that
/// (`fastPlan`; 2026-11-02 用户「谁知道订阅是什么，应该直接显示具体值」).
fn triple_speed(c : @ui.Ctx, src : Source, station : String, of : String, v : Json?) -> Unit {
  let head = @sf.t("web-main.model.speed")
  let now = match field(field(v, "draft"), "fast") {
    Some(True) => "fast"
    Some(False) => "standard"
    _ => if flag(v, "fastPlan") { "fast" } else { "standard" }
  }
  let choices = [
    @sf.choice("standard", @sf.t("web-main.model.standard")),
    // (Fast its bolt, and what it costs: ModelTriple.tsx's fastNote)
    @sf.choice("fast", "Fast", note=@sf.t("web-main.model.fastNote"), icon="zap"),
  ]
  let id = c.id("triple/fast")
  if c.clicked(id) {
    @sf.pick(
      head,
      choices,
      now,
      fn(f) {
        pick_save(src, station, of, { "fast": Json::boolean(f == "fast") })
      },
      from=Of(id),
      search=false,
    )
  }
  let words = choices.search_by(fn(ch) { ch.key == now }).map(fn(i) { choices[i].label }).unwrap_or("")
  let b = c.box(style=triple_who(), id~, fn() {
    c.text(head, style=triple_who_lead) |> ignore
    c.text(words, style=triple_who_name) |> ignore
  })
  c.semantics(b, Button, id~, label=words)
}

///|
/// How much context it is kept to, at the foot after how fast (2026-11-03 用户「把 opus5.5 上下文长度限制在 500k 或者
/// 300k」「直接放最下面跟速度一样吧」): its name and the step picked; pressed, the steps in a pick, its whole window first,
/// as the core offers them (none where its runtime cannot).
fn triple_context(c : @ui.Ctx, src : Source, station : String, of : String, v : Json?) -> Unit {
  let head = @sf.t("web-main.model.context")
  let now = text(v, "contextNow")
  let choices = items(v, "contexts").map(fn(o) { @sf.choice(text(Some(o), "id"), text(Some(o), "text")) })
  let id = c.id("triple/context")
  if c.clicked(id) {
    @sf.pick(
      head,
      choices,
      now,
      fn(k) { pick_save(src, station, of, { "context": if k == "" { Json::null() } else { Json::string(k) } }) },
      from=Of(id),
      search=false,
    )
  }
  let words = choices.search_by(fn(ch) { ch.key == now }).map(fn(i) { choices[i].label }).unwrap_or("")
  let b = c.box(style=triple_who(), id~, fn() {
    c.text(head, style=triple_who_lead) |> ignore
    c.text(words, style=triple_who_name) |> ignore
  })
  c.semantics(b, Button, id~, label=words)
}

///|
/// Its foot (the presenter's, where every panel's foot stands): who runs it, and where the model picked is another
/// station's, borrowing it (asked first). Nothing to confirm: each pick is made what it runs on as it is picked
/// (2026-11-01 用户「从第一性原理出发重新思考这个组件的使用场景」).
fn triple_foot(c : @ui.Ctx, src : Source, station : String, of : String, contents : TriplePanel, close : () -> Unit) -> Unit {
  let v = contents.pick_now(src, station, of)
  if v is None {
    return
  }
  let borrow = field(v, "borrow")
  // (who runs it, what on and how fast, one after another at the foot's start, on a second line where one is short)
  c.box(style=triple_who_room, keep=true, flow=true, fn() {
    // (a short line between each and the next: 2026-11-02 用户「下面不是好几个东西么，之间用短分割线」)
    let apart = fn() { c.box(style=triple_foot_rule, fn() {  }) |> ignore }
    triple_runs_who(c, src, station, of, v)
    if !contents.sheet && !flag(v, "runtimeFixed") && items(v, "runtimes").length() > 1 {
      apart()
      triple_runtime(c, src, station, of, v)
    }
    if flag(v, "fastAvailable") {
      apart()
      triple_speed(c, src, station, of, v)
    }
    if !items(v, "contexts").is_empty() {
      apart()
      triple_context(c, src, station, of, v)
    }
  })
  |> ignore
  if borrow is Some(Object(_)) &&
    @sf.button(c, text(borrow, "action"), key="triple/borrow", tone=Primary, disabled=!flag(borrow, "allowed")) {
    triple.open = ""
    triple.borrow_asking = station + "\u{1}" + of
    close()
  }
}

///|
/// A model's row: its maker's mark, its name (what it has spent under it) `names_w` wide (the widest of the models'),
/// how it runs picked right after its name (cut short first where the row is short), at its end the station it comes
/// from; with `likes`,
/// a box before it, ticked while it is starred (`pick.like`); with `star`, a star at its end (one of those starred).
fn triple_model_row(
  c : @ui.Ctx,
  src : Source,
  station : String,
  of : String,
  v : Json?,
  o : Json?,
  names_w : Double,
  saved : String,
  close : () -> Unit,
  likes? : Bool = false,
  star? : Bool = false,
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
  let usual = text(o, "usualText")
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
  // (at its end where it comes from)
  let trail = fn() {
    match from_station {
      Some(f) => f()
      None => ()
    }
    if star {
      @sf.icon(c, "star-fill", size=triple_star_icon, color=t.p.muted) |> ignore
    }
  }
  let liked = flag(o, "liked")
  // (starred or not, its box before it where all of them are listed: beside the row, not in its corner)
  let like_box = fn() {
    let now = @kit.checkbox(
        c,
        "triple/like/" + model,
        if liked { On } else { Off },
        label=@sf.t("web-main.model.likeModel", args=[("model", text(o, "name"))]),
      ).value
    if (now == On) != liked {
      (src.call)(
        "pick.like",
        { "station": Json::string(station), "of": Json::string(of), "model": Json::string(model), "liked": Json::boolean(now == On) },
        fn(res) {
          match res {
            Ok(_) => ()
            Err(e) => toast_later(@sf.t("web-main.pick.failed", args=[("error", error_words(e))]))
          }
        },
      )
    }
  }
  let mut pressed = false
  let row = fn() {
    pressed = triple_option(c, "triple/model/" + model, text(o, "name"), picked, trail~, tip=ids, fn() {
      @sf.maker_mark(c, text(field(o, "maker"), "id"), runs, 14.0) |> ignore
      // (all of its name in the room its column leaves it, on a second line where one is not enough: what goes with
      // the model picked beside the models takes the room its words need first)
      c.box(style=triple_name_column.then(@ui.style(w=Fixed(names_w))), fn() {
        let name = fn() {
          c.text(text(o, "name"), style=if picked { triple_row_picked } else { triple_row_name }) |> ignore
        }
        // (how it runs picked: as it last ran here, the one picked as it runs now)
        if usual == "" {
          name()
        } else {
          c.box(style=triple_name_line, fn() {
            // (the name as wide as its words, how it runs right after it rather than at the row's end; kept, so what
            // is after it gives way first)
            c.box(keep=true, name) |> ignore
            // (giving way to the name where the row is short: what the name leaves of it, cut short)
            c.box(style=triple_usual_room, fn() { c.text(usual, style=triple_usual) |> ignore }) |> ignore
          })
          |> ignore
        }
        match text(field(o, "spent"), "text") {
          "" => ()
          sp => c.text(sp, style=triple_note) |> ignore
        }
      })
      |> ignore
    })
  }
  if likes {
    c.box(style=triple_liking, fn() {
      c.box(style=triple_like_room, like_box) |> ignore
      c.box(style=triple_models_column, row) |> ignore
    })
    |> ignore
  } else {
    row()
  }
  if pressed {
    if text(o, "availability") == "borrowable" {
      // (another station's: borrowed first, from the foot)
      pick_draft(src, station, of, { "model": Json::string(model) })
    } else {
      // made what it runs on at once, as it last ran here, and the panel closed: nothing of it left to confirm
      triple.open = ""
      close()
      if !picked || text(field(v, "value"), "model") != model {
        let p : Map[String, Json] = { "model": Json::string(model) }
        match field(o, "usual") {
          Some(Object(u)) =>
            for k in ["runtime", "effort", "fast", "context"] {
              p[k] = u.get(k).unwrap_or(Json::null())
            }
          _ => ()
        }
        pick_save(src, station, of, p, done=saved)
      }
    }
  }
}

///|
/// The runtime's and how fast's: a panel's row (as tall as its rows, its ground under the pointer, as the models' are),
/// its name `head` at its start `head_w` wide, what is picked now (its icon, its words) after it, a chevron at its end;
/// pressed, all of `choices` in a pick beside it, `pick` given the one chosen.
fn triple_pick_row(
  c : @ui.Ctx,
  key : String,
  head : String,
  head_w : Double,
  choices : Array[@sf.Choice],
  now : String,
  pick : (String) -> Unit,
) -> Unit {
  let t = @sf.theme()
  let id = c.id(key)
  let picked = choices.search_by(fn(ch) { ch.key == now }).map(fn(i) { choices[i] })
  let words = picked.map(fn(ch) { ch.label }).unwrap_or("")
  let icon = picked.map(fn(ch) { ch.icon }).unwrap_or("")
  let b = c.box(style=triple_option_style.then(@ui.style(min_h=Fixed(t.rows.pick), gap=S3)), id~, fn() {
    c.box(style=@ui.style(w=Fixed(head_w)), fn() { c.text(head, style=triple_head) |> ignore }) |> ignore
    c.box(style=triple_pick_value, fn() {
      if icon.has_prefix("runtime:") {
        @sf.maker_mark(c, "", icon.view(start_offset=8).to_string(), triple_pick_mark) |> ignore
      } else if icon != "" {
        @sf.icon(c, icon, size=triple_pick_mark, color=t.p.text) |> ignore
      }
      c.text(words, style=triple_words) |> ignore
    })
    |> ignore
    @sf.icon(c, "chevron-down", size=triple_pick_chevron, color=t.p.muted) |> ignore
  })
  c.semantics(b, Button, id~, label=words)
  if c.clicked(id) {
    @sf.pick(head, choices, now, pick, from=Of(id), search=false)
  }
}

///|
/// A pick row's icon (a maker's mark, Fast's bolt) and its chevron.
let triple_pick_mark : Double = 14.0

///|
let triple_pick_chevron : Double = 12.0

///|
/// How hard it thinks, at the panel's right (`choices`: its value and its words, the model's own first, then from the
/// least to the most; `now` the one picked): its name `head` over them, each a row of the panel's under the one before,
/// the one picked lit and checked (a pick's rows); `pick` given the value pressed.
fn triple_choices(
  c : @ui.Ctx,
  key : String,
  head : String,
  choices : Array[(String, String)],
  now : String,
  pick : (String) -> Unit,
) -> Unit {
  let t = @sf.theme()
  if head != "" {
    triple_column_head(c, head)
  }
  for ch in choices {
    let (value, words) = ch
    let on = value == now
    let id = c.id(key + "/" + value)
    let b = c.box(style=(if on { triple_option_on } else { triple_option_style }).then(@ui.style(min_h=Fixed(t.rows.pick))), id~, keep=true, fn() {
      c.text(words, style=if on { triple_picked } else { triple_words }) |> ignore
      c.box(style=triple_end, keep=true, fn() {
        if on {
          @sf.icon(c, "check", size=14.0, color=t.p.accent) |> ignore
        } else {
          c.box(style=triple_check_room, fn() {  }) |> ignore
        }
      })
      |> ignore
    })
    c.semantics(b, Radio, id~, label=words, check=if on { On } else { Off })
    if c.clicked(id) {
      pick(value)
    }
  }
}

///|
/// A column's head (runPicker h4): 4 over it, 6 under, as far in as the rows' words.
fn triple_column_head(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=triple_head_box, fn() { c.text(words, style=triple_head) |> ignore }) |> ignore
}

///|
/// A row of a column (runPickerOption): as high as the screen's picker rows at least (Theme::rows pick), 4 by 10 in, its ground under the pointer and while picked,
/// `trail` (a button of its own, the station a model comes from) at its end, a check after it while picked (its room
/// kept while not, as the web's hidden check; none at all with `checks` false); `tip` over it while it is pointed at.
/// `corner`: one line high in its panel's corners (the accounts' panel, not scrolled), a capsule standing concentric
/// with them as a menu's row does (pick_reach), past the padding at its sides and, the last (`at_foot`), its foot.
/// True on the frame after a press.
fn triple_option(
  c : @ui.Ctx,
  key : String,
  label : String,
  on : Bool,
  body : () -> Unit,
  trail? : () -> Unit,
  tip? : String = "",
  checks? : Bool = true,
  corner? : Bool = false,
  at_foot? : Bool = false,
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  let reach = if corner { @sf.menu_row_reach(t.rows.pick) } else { 0.0 }
  let (_, under_by) = @sf.ends_reach(reach, false, at_foot)
  // (across its column, as wide as its words need at least: what the column needs, the panel's columns laid out by it)
  let look = (if on { triple_option_on } else { triple_option_style }).then(@ui.style(min_h=Fixed(t.rows.pick)))
  let look = if reach > 0.0 { look.then(@sf.pick_reach()).then(@ui.style(mb=@sf.room_of(under_by))) } else { look }
  let b = c.box(style=look, id~, keep=true, fn() {
    body()
    // what is at its end, at the end: the room left (no spacer of its own, whose gap took a gap's room from the
    // words), never less than it needs; the check's room kept while it is not picked
    c.box(style=triple_end, keep=true, fn() {
      match trail {
        Some(f) => f()
        None => ()
      }
      if !checks {
        ()
      } else if on {
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
  let v = src.topic("pick", pick_params(station, of)).get().value
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
      pick_save(src, station, of, { "profile": Json::null() })
      close()
    }
    let accounts = items(v, "accounts")
    for i, a in accounts {
      let a = Some(a)
      let id = text(a, "id")
      // (one line where nothing is said of what is left of it: a capsule, standing so in the panel's foot corners)
      let one_line = text(field(a, "quotaLine"), "text") == ""
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
        }, corner=one_line, at_foot=i == accounts.length() - 1) {
        pick_save(src, station, of, { "profile": Json::string(id) })
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
/// Who runs it by name after its mark (in the mark's part, triple_part's gap before it).
// kept across runs: a value (no field of it changes)
let triple_alone : @ui.Style = @ui.css("row align=ACenter")

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
/// The search: as tall as the panel's rows (a small panel's search is 34), round, on the words' tint (deeper pointed at or typed in), its glass 12 in and 8 before its
/// words.
// kept across runs: a value (no field of it changes)
let triple_find : @ui.Style = @ui.css("row w=Full px=S3 gap=S2 align=ACenter radius=Full bg=Tint")

///|
// kept across runs: a value (no field of it changes)
let triple_find_hot : @ui.Style = @ui.css("row w=Full px=S3 gap=S2 align=ACenter radius=Full bg=TintStrong")

///|
// kept across runs: a value (no field of it changes)
let triple_find_words : @ui.Style = @ui.style(w=@sf.grow)

///|
/// The search's glass.
let triple_find_icon : Double = 14.0

///|
/// A line across (a history's under its figures; the panel's over its foot is the presenters', `ruled`: kept,
/// 2026-10-25 用户「这两个的分割线可以保留」).
// kept across runs: a value (no field of it changes)
pub let triple_rule_h : @ui.Style = @ui.css("w=Full h=SPx bg=Line")

///|
pub let triple_models_least : Double = 200.0

///|
/// What goes with the models under them: across the panel, 8 under them, on the panel's own ground (no ground nor
/// corner of its own: 2026-10-30 用户「下面阴影部分的圆角也不对吧」), its lines the panel's rows (as tall, as far in, 1
/// apart), each its name 12 before what it holds, its name on the rows' words' line.
// kept across runs: a value (no field of it changes)
let triple_tray : @ui.Style = @ui.css("w=Full mt=S2 gap=SPx")

///|
/// The tray nearest what opened the panel opening down: over the models, as far from them.
// kept across runs: a value (no field of it changes)
let triple_tray_first : @ui.Style = @ui.css("w=Full mb=S2 gap=SPx")

///|
/// What a pick row says is picked: its icon 6 before its words, the rest of the row.
// kept across runs: a value (no field of it changes)
let triple_pick_value : @ui.Style = @ui.style(w=@sf.grow).then(@ui.css("row gap=S1_5 align=ACenter"))

  .then(@ui.style(w=@sf.grow))

///|
/// A select's share of their line: its name over it.
// kept across runs: a value (no field of it changes)
let triple_select_box : @ui.Style = @ui.style(w=@sf.grow, gap=SPx)

///|
/// A column's rows, 1 apart.
// kept across runs: a value (no field of it changes)
let triple_rows : @ui.Style = @ui.css("w=Full gap=SPx")

///|
/// A row's ground, concentric with its small panel as a menu's row is (panel_in): a capsule 34 high, a taller row (an
/// account with what is left of it under its name) the ladder's 18, not a capsule as round as half its height.
// kept across runs: a value (no field of it changes)
let triple_option_style : @ui.Style = @ui.css(
  #|row w=Full px=S2_5 py=S1 gap=S1_5 align=ACenter hovered{bg=Hover}
).then(@ui.style(radius=@sf.panel_in))

///|
// kept across runs: a value (no field of it changes)
let triple_option_on : @ui.Style = @ui.css(
  #|row w=Full px=S2_5 py=S1 gap=S1_5 align=ACenter bg=Hover
).then(@ui.style(radius=@sf.panel_in))

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
/// The parts of the panel's first level, apart: those starred, those used most, the way to all of them.
// kept across runs: a value (no field of it changes)
let triple_parts : @ui.Style = @ui.css("w=Full gap=S3")

///|
/// Those used most kept out of what scrolls in a sheet, as far from it as triple_parts' parts are apart: under it
/// (opening up), over it (opening down).
// kept across runs: a value (no field of it changes)
let triple_part_under : @ui.Style = @ui.css("w=Full mt=S3")

///|
// kept across runs: a value (no field of it changes)
let triple_part_over : @ui.Style = @ui.css("w=Full mb=S3")

///|
/// The star at the end of one of those starred.
let triple_star_icon : Double = 12.0

///|
/// The box before a model where all of them are listed (the kit's checkbox: 18), beside its row, and its room.
let triple_box_side : Double = 18.0

///|
// kept across runs: a value (no field of it changes)
let triple_liking : @ui.Style = @ui.css("row w=Full gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let triple_like_room : @ui.Style = @ui.css("pl=S2_5 align=ACenter justify=JCenter")

///|
/// All the models beside what opened the panel: the makers, a line, a maker's models.
// kept across runs: a value (no field of it changes)
let triple_browse : @ui.Style = @ui.css("row w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let triple_kinds_column : @ui.Style = @ui.css("w=S48")

///|
// kept across runs: a value (no field of it changes)
let triple_models_column : @ui.Style = @ui.style(w=@sf.grow)

///|
/// The line between them (the panel's columns', 2026-10-25 用户 kept them).
// kept across runs: a value (no field of it changes)
let triple_rule_v : @ui.Style = @ui.css("w=SPx bg=Line")

///|
/// The models and how hard it thinks side by side, 8 apart, the line between them in the middle of that.
// kept across runs: a value (no field of it changes)
let triple_side_by_side : @ui.Style = @ui.css("row w=Full gap=S2")

///|
/// The models' column beside how hard it thinks: what is at its top there, the way to all of them at its foot.
// kept across runs: a value (no field of it changes)
let triple_ends_apart : @ui.Style = @ui.css("justify=JBetween")

///|
/// What is at its top: its title and search, those used most and starred.
// kept across runs: a value (no field of it changes)
let triple_models_top : @ui.Style = @ui.css("w=Full")

///|
/// The way to all of them: 12 under what is over it at least.
// kept across runs: a value (no field of it changes)
let triple_all_room : @ui.Style = @ui.css("w=Full pt=S3")

///|
/// Where the line between them starts, from how hard it thinks' start: in the middle of the 8 between them.
let triple_between_rule : Double = 4.5

///|
/// Between the foot's parts: a short line upright, as tall as their words.
// kept across runs: a value (no field of it changes)
let triple_foot_rule : @ui.Style = @ui.css("w=SPx h=S3 bg=Line")

///|
/// How hard it thinks beside the models: as wide as its words need.
// kept across runs: a value (no field of it changes)
let triple_effort_column : @ui.Style = @ui.css("gap=SPx")

///|
/// A kind's mark, as wide as a model's.
// kept across runs: a value (no field of it changes)
let triple_kind_mark : @ui.Style = @ui.css("w=S3_5 align=ACenter justify=JCenter")

///|
/// How a model runs picked, right after its name: Meta, muted, on one line.
// kept across runs: a value (no field of it changes)
let triple_usual : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=Cut)

///|
/// Its room: right after the name, what the name leaves of the row.
// kept across runs: a value (no field of it changes)
let triple_usual_room : @ui.Style = @ui.style(row=true, w=@sf.grow)

///|
/// A model's name with how it runs right after it, on its words' line.
// kept across runs: a value (no field of it changes)
let triple_name_line : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let triple_empty : @ui.Style = @ui.css("px=S2_5 py=S2")

///|
// kept across runs: a value (no field of it changes)
let triple_borrow : @ui.Style = @ui.css("w=Full px=S2_5 py=S1_5")

///|
// kept across runs: a value (no field of it changes)
let triple_who_room : @ui.Style = @ui.style(row=true, w=@sf.grow, align=ACenter, gap=S1)

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

///|
/// The same with its accounts open over it (a screen's fixture).
pub fn open_triple_accounts(station : String, of : String) -> Unit {
  open_triple(station, of)
  triple.accounts_asked = true
}
