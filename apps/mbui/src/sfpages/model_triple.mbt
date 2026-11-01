// The one way a model is chosen (ember web/src/ModelTriple.tsx, ModelTriple.css.ts; NewChat.kt's run picker said the
// same): a control that says the model, the runtime (where it can still change and the model runs on more than one),
// how hard it thinks and who runs it, in one line; pressed, its panel through the presenters (beside it with keyboard and mouse,
// a sheet with touch): the models, each saying how it runs picked (as it last ran here), the ones used most nearest
// what opened it, the rest past them (a filter over them when there are many); between them and it the runtime, the
// effort and the speed, every name whole; at its foot who runs it (the accounts in a panel of their own, from it).
// Its rows are the screen's (Theme::rows pick). Each pick is made what it runs on as it is picked (`pick.save`), a
// model closing the panel; a model another station has is drafted (`pick.set`) and borrowed first, asked in a dialog.


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
    fn(c, close) { triple_panel(c, src, station, of, saved, close) },
    from~,
    w=triple_panel_w,
    // (as wide as its columns' words, no wider: 2026-10-26 用户「没啥内容也这么宽感觉会很奇怪」)
    fits=true,
    foot=fn(c, close) { triple_foot(c, src, station, of, close) },
    // (its search beside its title, not a line of its own)
    head_end=fn(c) { triple_find_field(c, (src.topic)("pick", pick_params(station, of)).value) },
    gone=fn() { triple.open = "" },
    focus=false,
    // (the models scroll by themselves, what goes with the one picked beside them in view)
    lists=true,
    // (no line over its foot: 2026-10-30 用户「分割线也去掉呗」, in place of 2026-10-25's line out to its edges)
    ruled=false,
    side~,
  )
  triple.shown = @sf.last_presented()
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
/// The panel: the filter across its top (more than 8 models), the models (one picked, `saved` said and the panel
/// closed: triple_model_row), and between them and what opened it the runtimes (where there are
/// more than one), how hard it thinks and how fast, each a segmented choice: the models scrolling by themselves, what
/// goes with them in view. What borrowing would do under them. Beside what opened it the models scroll past 360 (the
/// web's); in a sheet the sheet is as tall as all of it up to its most, the models scrolling in what is left then
/// (@sf.panel_column).
fn triple_panel(c : @ui.Ctx, src : Source, station : String, of : String, saved : String, close : () -> Unit) -> Unit {
  let v = (src.topic)("pick", pick_params(station, of)).value
  if v is None {
    // (read the first time: the panel of made-up models, in its bones)
    @sf.waiting(c, fn() { triple_body(c, @sfbase.sample_source, station, of, Some(triple_sample()), saved, close) })
    return
  }
  triple_body(c, src, station, of, v, saved, close)
}

///|
/// The panel's models, runtimes, how hard it thinks and how fast, as the core's `pick` (`v`) offers them.
fn triple_body(
  c : @ui.Ctx,
  src : Source,
  station : String,
  of : String,
  v : Json?,
  saved : String,
  close : () -> Unit,
) -> Unit {
  let options = items(v, "options")
  let draft = field(v, "draft")
  let words = triple.query.trim(chars=" ").to_string().to_lower()
  // (the search, where the panel's head has none: a sheet's, its head its own)
  if !@sf.in_small_panel() && options.length() > 8 {
    c.box(style=triple_search, fn() { triple_find_field(c, v) }) |> ignore
  }
  let listed = options.filter(fn(o) {
    let o = Some(o)
    words == "" ||
    text(o, "name").to_lower().contains(words) ||
    text(o, "model").to_lower().contains(words) ||
    items(o, "ids").iter().any(fn(i) { i is String(s) && s.to_lower().contains(words) })
  })
  // the models used most here (the core's `near`), nearest what opened the panel, out of the list while nothing is typed;
  // the rest by series, in the core's order
  let searching = words != ""
  let near : Array[Json] = []
  if !searching {
    for id in items(v, "near") {
      if id is String(id) {
        match options.search_by(fn(o) { text(Some(o), "model") == id }) {
          Some(i) => near.push(options[i])
          None => ()
        }
      }
    }
  }
  let rest = listed.filter(fn(o) { !near.iter().any(fn(n) { text(Some(n), "model") == text(Some(o), "model") }) })
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
  // (each made what it runs on at once, the panel staying open: kept for the model too, as it runs next time it is
  // picked)
  let pick_runtime = fn(r : String) { pick_save(src, station, of, { "runtime": Json::string(r) }) }
  let pick_effort = fn(e : String) {
    pick_save(src, station, of, { "effort": if e == "" { Json::null() } else { Json::string(e) } })
  }
  let pick_speed = fn(f : String) {
    let fv : Json = match f {
      "" => Json::null()
      "fast" => Json::boolean(true)
      _ => Json::boolean(false)
    }
    pick_save(src, station, of, { "fast": fv })
  }
  // each column's words as wide as the widest of them picked (the models' of all of them, whatever the filter leaves):
  // the panel, as wide as what it holds, as wide whichever is picked and whatever is typed (as a segmented choice's)
  let names_w = options.fold(init=0.0, fn(m, o) {
    let o = Some(o)
    dmax(dmax(m, c.words_across(text(o, "name"), triple_row_picked)), c.words_across(text(field(o, "spent"), "text"), triple_note))
  }).ceil()
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
  let up = @sf.panel_opens_up()
  let models = fn() {
    if rest.length() == 0 && !searching {
      return
    }
    @sf.panel_column(c, "triple/models", triple_list_h, triple_rows, fn() {
      // (no head of its own: the panel's title says what they are; nor each series one, its models' names and marks
      // saying it again, most of them a series of one (2026-10-30 用户「有点丑」): a series' models together)
      for s in series {
        for o in s.1 {
          triple_model_row(c, src, station, of, v, Some(o), names_w, saved, close)
        }
      }
      if listed.length() == 0 {
        c.box(style=triple_empty, fn() { c.text(@sf.t("web-main.model.noMatch"), style=triple_muted) |> ignore })
        |> ignore
      }
    })
  }
  let used = fn() {
    if near.length() == 0 {
      return
    }
    c.box(style=if up { triple_near_up } else { triple_near_down }, fn() {
      // (named, as what they are: 2026-11-01 用户「感觉还是得标注一下常用」)
      triple_column_head(c, @sf.t("web-main.combos.short"))
      for o in if up { near.rev() } else { near } {
        triple_model_row(c, src, station, of, v, Some(o), names_w, saved, close)
      }
    })
    |> ignore
  }
  let how = fn() {
    // how it runs, on a ground of its own under the models, each as it is used (2026-10-30 用户「这个地方可以有专属设计」
    // 「不一定每个都要平铺吧」): how hard it thinks, tuned to the work at hand, laid out whole as a level (its stops from
    // the model's own to the most side by side in one capsule, its track filled up to the one picked, lifted out of it);
    // the runtime and how fast, set once and seldom changed, each a pill saying what it
    // is now, the rest a pick away, the two side by side on one line
    if runs_on.length() > 1 || all_efforts.length() > 0 || fast {
      let (h_runtime, h_effort, h_speed) = (
        @sf.t("web-main.model.runtime"),
        @sf.t("web-main.model.effort"),
        @sf.t("web-main.model.speed"),
      )
      // (each line's name at its start, as wide as the widest of them: what it holds starting alike)
      let head_w = [h_runtime, h_effort, h_speed].fold(init=0.0, fn(m, h) { dmax(m, c.words_across(h, triple_head)) }).ceil()
      c.box(style=if up { triple_tray } else { triple_tray_first }, fn() {
        if all_efforts.length() > 0 {
          triple_tray_part(c, h_effort, head_w, fn() { triple_meter(c, all_efforts, text(draft, "effort"), pick_effort) })
        }
        if runs_on.length() > 1 {
          triple_pick_row(
            c,
            "triple/runtime",
            h_runtime,
            head_w,
            runs_on.map(fn(o) { @sf.choice(o.0, o.1, icon="runtime:" + o.0) }),
            text(draft, "runtime"),
            pick_runtime,
          )
        }
        if fast {
          triple_pick_row(
            c,
            "triple/fast",
            h_speed,
            head_w,
            speeds.map(fn(o) {
              if o.0 == "fast" {
                // (Fast its bolt, and what it costs: ModelTriple.tsx's fastNote)
                @sf.choice(o.0, o.1, note=@sf.t("web-main.model.fastNote"), icon="zap")
              } else {
                @sf.choice(o.0, o.1)
              }
            }),
            speed_now,
            pick_speed,
          )
        }
      })
      |> ignore
    }
  }
  if up {
    models()
    used()
    how()
  } else {
    how()
    used()
    models()
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
fn triple_find_field(c : @ui.Ctx, v : Json?) -> Unit {
  guard items(v, "options").length() > 8 else { return }
  let t = @sf.theme()
  // (in the panel's top corner, the head standing it where it is concentric with it: panel_head's `end`)
  triple_find_input(c, t)
}

///|
/// The search's field itself (triple_find_field).
fn triple_find_input(c : @ui.Ctx, t : @sf.Theme) -> Unit {
  let res = @kit.text_field(
    c,
    "triple/filter",
    placeholder=@sf.t("web-main.model.search"),
    size=t.t.ui,
    line=t.t.ui_line,
    field=triple.field,
    look=fn(c, s, editor) {
      c.box(id=s.id, style=(if s.hovered || s.focused { triple_find_hot } else { triple_find }).then(@ui.style(h=Fixed(@sf.menu_row_min))), fn() {
        @sf.icon(c, "search", size=triple_find_icon, color=t.p.muted) |> ignore
        c.box(style=triple_find_words, editor) |> ignore
      })
      |> ignore
    },
  )
  triple.query = res.text
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
/// Its foot (the presenter's, where every panel's foot stands): who runs it, and where the model picked is another
/// station's, borrowing it (asked first). Nothing to confirm: each pick is made what it runs on as it is picked
/// (2026-11-01 用户「从第一性原理出发重新思考这个组件的使用场景」).
fn triple_foot(c : @ui.Ctx, src : Source, station : String, of : String, close : () -> Unit) -> Unit {
  let v = (src.topic)("pick", pick_params(station, of)).value
  if v is None {
    return
  }
  let borrow = field(v, "borrow")
  triple_runs_who(c, src, station, of, v)
  if borrow is Some(Object(_)) &&
    @sf.button(c, text(borrow, "action"), key="triple/borrow", tone=Primary, disabled=!flag(borrow, "allowed")) {
    triple.open = ""
    triple.borrow_asking = station + "\u{1}" + of
    close()
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
  saved : String,
  close : () -> Unit,
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
  // (at its end how it runs picked: as it last ran here, the one picked as it runs now; then where it comes from)
  let trail = if usual == "" && from_station is None {
    None
  } else {
    Some(fn() {
      if usual != "" {
        c.text(usual, style=triple_usual) |> ignore
      }
      match from_station {
        Some(f) => f()
        None => ()
      }
    })
  }
  if triple_option(c, "triple/model/" + model, text(o, "name"), picked, trail?, tip=ids, fn() {
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
            for k in ["runtime", "effort", "fast"] {
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
/// A line of the tray under the models: its name `head` at its start, `head_w` wide (the widest of the tray's names),
/// what `body` draws the rest of it.
fn triple_tray_part(c : @ui.Ctx, head : String, head_w : Double, body : () -> Unit) -> Unit {
  c.box(style=triple_tray_part_box, fn() {
    c.box(style=@ui.style(w=Fixed(head_w)), fn() { c.text(head, style=triple_head) |> ignore }) |> ignore
    c.box(style=triple_tray_room, body) |> ignore
  })
  |> ignore
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
/// How hard it thinks as a level (`efforts`: the model's own first, "" its value, then its levels from the least to
/// the most; `now` the one picked): one capsule of the stops' names side by side, each an equal share, its track
/// filled from its start up to the one picked, the picked one lifted out of it (a segmented choice's thumb), the names
/// up to it in the ink, past it muted. All of it is one place along the stops, moving there as one thing as another is
/// picked: the thumb slides there, the fill's end under it, each name inked as the thumb reaches it.
/// `pick` given the value pressed.
fn triple_meter(c : @ui.Ctx, efforts : Array[(String, String)], now : String, pick : (String) -> Unit) -> Unit {
  let t = @sf.theme()
  let at = efforts.search_by(fn(o) { o.0 == now }).unwrap_or(0)
  // (each stop as wide as the widest name and its sides at least: where the panel may be as wide as that, it is, no
  // name cut short)
  let n = efforts.length().to_double()
  let stop_least = efforts.fold(init=0.0, fn(m, o) { dmax(m, c.words_across(o.1, triple_meter_words)) }).ceil() +
    2.0 * @ui.Space::px(S2_5)
  // (as tall as a panel's rows and its search: a small panel's 34)
  let high = @sf.menu_row_min
  // where along the stops it is (0 the first's place, 1 the next's …): going to the picked one's as a thing moved (a
  // stop's way a stop wide: the further the longer), on from where it was as fast as it went when another is picked
  let pos = @motion.animate(c, "triple/effort-at", at.to_double(), spec=@motion.move(points=stop_least))
  // (each as a share of the stops' width: the fill to the thumb's far end, the room before the thumb, a stop's)
  let fill_to = (pos + 1.0) / n * 100.0
  let before = pos / n * 100.0
  let share = 100.0 / n
  c.box(style=triple_meter_box.then(@ui.style(min_w=Within(stop_least * n), h=Fixed(high))), fn() {
    // (behind the stops, in from the capsule as they are: the track filled from its start to the thumb's far end, its
    // end under the thumb, all of it under the thumb at the model's own; then the thumb, a stop's share wide, that far
    // along)
    c.box(style=triple_meter_under, left=triple_meter_in, top=triple_meter_in, right=triple_meter_in, bottom=triple_meter_in, taps=false, fn() {
      c.box(style=triple_meter_fill.then(@ui.style(w=Pct(fill_to))), fn() {  }) |> ignore
    })
    |> ignore
    c.box(style=triple_meter_under, left=triple_meter_in, top=triple_meter_in, right=triple_meter_in, bottom=triple_meter_in, taps=false, fn() {
      c.box(style=triple_meter_before.then(@ui.style(w=Pct(before))), fn() {  }) |> ignore
      c.box(style=triple_meter_thumb.then(@ui.style(w=Pct(share))), fn() {  }) |> ignore
    })
    |> ignore
    for i, o in efforts {
      let (e, words) = o
      let id = c.id("triple/effort/" + e)
      let b = c.box(style=triple_meter_column, id~, fn() {
        // (in the ink once the thumb is on it or past it, muted ahead of it: the way between as it nears)
        let inked = @motion.clamp(0.0, 1.0, pos - i.to_double() + 1.0)
        // det-ok(box-loose): its ink between the theme's muted and its ink as far as the thumb has come, no style's
        c.text(words, style=triple_meter_words, color=@sf.mix(t.p.text, inked, t.p.muted)) |> ignore
      })
      c.semantics(b, Radio, id~, label=words, check=if i == at { On } else { Off })
      if c.clicked(id) {
        pick(e)
      }
    }
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
      pick_save(src, station, of, { "profile": Json::null() })
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
// kept across runs: a value (no field of it changes)
let triple_tray_part_box : @ui.Style = @ui.css("row w=Full pl=S2_5 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let triple_tray_room : @ui.Style = @ui.style(w=@sf.grow)

///|
/// What a pick row says is picked: its icon 6 before its words, the rest of the row.
// kept across runs: a value (no field of it changes)
let triple_pick_value : @ui.Style = @ui.style(w=@sf.grow).then(@ui.css("row gap=S1_5 align=ACenter"))

///|
/// The level: across the tray, a capsule as tall as the panel's rows on the words' tint, cut to its round, its stops 2
/// in, side by side, each an equal share.
// kept across runs: a value (no field of it changes)
let triple_meter_box : @ui.Style = @ui.css("row w=Full p=S0_5 radius=Full bg=Tint clip=true")

///|
/// A stop: an equal share of the level, its name in its middle; the pointer's ground under it.
// kept across runs: a value (no field of it changes)
let triple_meter_column : @ui.Style = @ui.css("h=Full align=ACenter justify=JCenter radius=Inner hovered{bg=Hover}")
  .then(@ui.style(w=@sf.grow))

///|
/// The track filled: the words' stronger tint, a capsule as the track is (concentric in it, 2 in), wherever it ends.
// kept across runs: a value (no field of it changes)
let triple_meter_fill : @ui.Style = @ui.css("h=Full radius=Full bg=TintStrong")

///|
let triple_meter_in : Double = 2.0

///|
/// What is behind the stops (the fill, the thumb): a row as far in as they are.
// kept across runs: a value (no field of it changes)
let triple_meter_under : @ui.Style = @ui.css("row")

///|
/// The room before the thumb: the stops it is past.
// kept across runs: a value (no field of it changes)
let triple_meter_before : @ui.Style = @ui.css("h=Full")

///|
/// The picked stop: lifted out of the track (the theme's raised, a hairline round it, a shadow), a capsule as the track
/// is (concentric in it at either end, 2 in), wherever it is on its way.
// kept across runs: a value (no field of it changes)
let triple_meter_thumb : @ui.Style = @ui.css("h=Full radius=Full bg=Raised border=B0_5 border_color=Line shadow=Sm")

///|
/// A stop's name (its ink as far as the thumb has come to it: triple_meter), one weight whatever is picked: the thumb
/// says which.
// kept across runs: a value (no field of it changes)
let triple_meter_words : @ui.TextStyle = @ui.text_style(size=Meta, wrap=false)

///|
/// A select's share of their line: its name over it.
// kept across runs: a value (no field of it changes)
let triple_select_box : @ui.Style = @ui.style(w=@sf.grow, gap=SPx)

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
/// The models used most: their rows 1 apart, as far from the rest as the tray is from them, on the side the rest is
/// (over them opening up, under them opening down).
// kept across runs: a value (no field of it changes)
let triple_near_up : @ui.Style = @ui.css("w=Full mt=S2 gap=SPx")

///|
// kept across runs: a value (no field of it changes)
let triple_near_down : @ui.Style = @ui.css("w=Full mb=S2 gap=SPx")

///|
/// How a model runs picked, at its row's end: Meta, muted, on one line.
// kept across runs: a value (no field of it changes)
let triple_usual : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

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
