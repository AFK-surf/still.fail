// The one way a model is chosen (still.fail web/src/ModelTriple.tsx, ModelTriple.css.ts; NewChat.kt's run picker said the
// same): a control that says the model, the runtime (where it can still change and the model runs on more than one),
// how hard it thinks and who runs it, in one line; pressed, its panel through the presenters (beside it with keyboard and mouse,
// a sheet with touch): the configurations used most here nearest what opened it (a model with how it runs, the core's
// `combos`), then the starred models, each saying how it runs picked (as it last ran here), the rest past them (a
// filter over them when there are many); between them and it the runtime, the
// effort and the speed, every name whole; at its foot who runs it (the accounts in a panel of their own, from it).
// Its rows are the screen's (Theme::rows pick). Each pick is made what it runs on as it is picked (`pick.save`), a
// model closing the panel; a model another station has is drafted (`pick.set`) and borrowed first, asked in a dialog.
//
// Laid out by use, not by our controls (the user, 2026-10-30: 「不要被我们现在的控件束缚住了」): what is used more
// stands nearer the button (2026-11-01: 「那它就不应该跑到离按钮很远的最顶上去啊」).

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
  mut sidekick : Bool
  mut pick : Json?
  /// the level the model picked was last brought into view in (its first, all of them, a kind's; none yet), for each
  /// of a sheet's steps ("" its first, and all of one beside what opened it): once as each is come to, not each frame,
  /// so what the person scrolled stays where they left it
  shown : Map[String, String]
  /// how its borrowing is asked, where what opened it asks it itself (a control made once: model_triple_node), given
  /// what the pick says of it; None, its control's build's dialog (borrow_dialog)
  asks : ((Json?) -> Unit)?
  /// what its stops for how hard it thinks keep between builds (@sf.stops), those of each of a sheet's steps ("" its
  /// first)
  effort_stops : Map[String, @sf.Stops]
  /// the models of its first level after the configurations used most, as they stood when it opened and those come to
  /// it since: the one picked where it is not starred (where the rest are a level further) and those starred: one
  /// starred or not since stays where it was while the panel is open
  mut first : (Array[String], Array[String])?
  /// the configurations used most as its first level shows them (None till the core has said them): one taken out
  /// (`pick.forget`) stays among them while it leaves where it was (`combos_leaving`, by its key), the next of them come
  /// in its place only once it has gone; `combos_seen` those it has shown since it opened, the rest coming in by a
  /// motion of their own (the user, 2026-11-13: 「去掉后要有补位（如果有的话），还要有动效」)
  mut combos_shown : Array[Json]?
  combos_leaving : Map[String, Json]
  combos_seen : Map[String, Bool]
}

///|
fn TriplePanel::pick_now(self : TriplePanel, src : Source, station : String, of : String) -> Json? {
  if @sf.presented_open_of(self.serial) {
    // (its last as it leaves: what it shows stays while it goes)
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
  triple_ahead_stop()
  triple_ahead.of = ""
  // (a lease of a run before is that run's source's: let go with it)
  triple_ahead.lease = None
}

///|
/// A control drawn of its face (a new chat's: its `pick` as the page has it, NewChatPick) asks its panel's own `pick` as
/// the hand comes to it (a pointer resting over it, a finger or a pointer going down on it, a press) and opens that panel
/// once it is answered, whole: what it holds of it meanwhile (`lease`, of `of`: its station and pick), and the press
/// waiting for it to be answered (`wait`: sfbase's press_wait, which waits only while what it was pressed in stays as it
/// was, and lets go of what it asked when it stops). The panel holds it while it is open, and a borrowing asked from it
/// while that is asked.
priv struct TripleAhead {
  mut lease : @sfbase.TopicLease?
  mut of : String
  mut wait : @sfbase.PressWait?
}

///|
// kept across runs: put back by triple_reset
let triple_ahead : TripleAhead = { lease: None, of: "", wait: None }

///|
/// Whether a press waits for a panel's pick.
fn triple_waiting() -> Bool {
  triple_ahead.wait is Some(w) && w.waiting()
}

///|
/// What waits to open a panel ended, letting go of nothing (the same asked again, or the panel opened holds it).
fn triple_ahead_stop() -> Unit {
  match triple_ahead.wait {
    Some(w) => {
      triple_ahead.wait = None
      w.end()
    }
    None => ()
  }
}

///|
/// The pick `of` on `station` asked of the core ahead of its panel (held till triple_let_go), unless it is held already;
/// one held for another let go of.
fn triple_ask(src : Source, station : String, of : String) -> Unit {
  let me = station + "\u{1}" + of
  match triple_ahead.lease {
    Some(l) if triple_ahead.of == me && l.alive() => return
    Some(l) => l.cancel()
    None => ()
  }
  triple_ahead.of = me
  triple_ahead.lease = Some(src.lease_topic("pick", pick_params(station, of)))
}

///|
/// What was asked ahead of the panel of the pick `of` on `station` as it stands, read through what holds it (holding
/// nothing more: a page's own read of it would hold it while the page is there); None while it is not held.
fn triple_ahead_read(station : String, of : String) -> @sfbase.TopicState? {
  guard triple_ahead.of == station + "\u{1}" + of && triple_ahead.lease is Some(l) && l.alive() else { return None }
  @signals.untracked(fn() { l.read() })
}

///|
/// What was asked ahead of the panel of `me` let go of, where nothing reads it: its panel not open, nothing waiting to
/// open it, no borrowing of it asked, the hand not on its control (`hand`).
fn triple_let_go(me : String, hand? : Bool = false) -> Unit {
  guard triple_ahead.of == me && !hand && triple.open != me && !triple_waiting() && triple.borrow_asking != me else {
    return
  }
  match triple_ahead.lease {
    Some(l) => {
      triple_ahead.lease = None
      l.cancel()
    }
    None => ()
  }
}

///|
/// The panel of the pick `of` on `station` opened beside `from` once its own pick is answered (asked now where it is
/// not held already): at once where it is, else the moment it is, whole, never on what the control's face has nor in
/// its bones; a press that waits for it as sfbase's press_wait says (not at all once what it was pressed in is gone,
/// what it asked let go of then). Opened already, it closes (as open_triple_panel).
fn open_triple_whole(src : Source, station : String, of : String, from : @sf.Anchor, saved : String) -> Unit {
  let me = station + "\u{1}" + of
  if triple.open == me {
    @sf.close_presented_of(triple.shown)
    return
  }
  triple_ahead_stop()
  triple_ask(src, station, of)
  // (the pick read through what holds it, never through the page's source, which would hold it while the page is there)
  let w = @sfbase.press_wait(
    fn() {
      match triple_ahead.lease {
        Some(l) if triple_ahead.of == me => l.follow() is Some(st) && @sfbase.opens_answered(st)
        _ => false
      }
    },
    fn() {
      guard triple.open != me else { return }
      // (gone: what it held let go of where nothing else holds it)
      open_triple_panel(src, station, of, from, saved~, gone=fn() { triple_let_go(me) })
    },
    let_go=fn() { triple_let_go(me) },
  )
  triple_ahead.wait = if w.waiting() { Some(w) } else { None }
}

///|
/// What is at a row's end (its check, what goes with it): the rest of the row after its words, at its end.
// kept across runs: a value (no field of it changes)
let triple_end : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S1_5, align=ACenter, justify=JEnd)

///|
/// An effort as it is said (low → 低); one the words do not know, as it is spelled, its first letter up.
pub fn effort_text(effort : String) -> String {
  let key = "web-main.model.effortLevel." + effort
  let said = @sf.t(key)
  if said != key {
    said
  } else if effort == "" {
    effort
  } else {
    effort.clamped_view(end=1).to_upper().to_owned() + effort.clamped_view(start=1).to_owned()
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
fn pick_save(
  src : Source,
  station : String,
  of : String,
  patch : Map[String, Json],
  done? : String = "",
  ok? : (Json) -> Unit = fn(_) {  },
  failed? : () -> Unit = fn() {  },
) -> Unit {
  let p = pick_params(station, of)
  for k, v in patch {
    p[k] = v
  }
  act(src, @sf.t("common.confirm"), "pick.save/" + station + "/" + of, "pick.save", Json::object(p), done~, ok~, failed~)
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
  gone? : () -> Unit = fn() {  },
  asks? : (Json?) -> Unit,
  accounts? : Bool = false,
) -> Unit {
  let me = station + "\u{1}" + of
  if triple.open == me {
    @sf.close_presented_of(triple.shown)
    return
  }
  triple.open = me
  // (its accounts over it as it opens: asked for by who runs it, an agent's card's 账号)
  if accounts {
    triple.accounts_asked = true
  }
  let contents : TriplePanel = { serial: 0, field: @ui.Field::new(), query: "", kind: triple_no_kind, all: false, sidekick: false, pick: None, shown: {}, asks, effort_stops: {}, first: None, combos_shown: None, combos_leaving: {}, combos_seen: {} }
  pick_draft(src, station, of, { "open": Json::boolean(true) })
  // (as wide as its models and how hard it thinks beside them; wider where they are many, their makers a column
  // before them)
  let now = src.topic("pick", pick_params(station, of)).get().value
  let many = items(now, "makers").length() > 1 && items(now, "options").length() > triple_flat_most
  @sf.panel(
    @sf.t("android-chat.new.model"),
    fn(c, close) { triple_panel(c, src, station, of, contents, saved, close) },
    from~,
    w=if many { triple_panel_w_many } else { triple_panel_w },
    // (as wide as its columns' words, no wider: 2026-10-26 用户「没啥内容也这么宽感觉会很奇怪」)
    fits=true,
    foot=fn(c, close) { triple_foot(c, src, station, of, contents, close, saved~) },
    // (beside what opened it, its title over its models' column, its search beside it, how hard it thinks titled over
    // its own: triple_body's; 2026-11-02 用户「搜索在左边区域，思考深度和模型在同一个层级」)
    heads_itself=true,
    gone=fn() {
      triple.open = ""
      let cur = src.topic("pick", pick_params(station, of)).get().value
      if triple_selected_accounts(field(cur, "draft")) is Some([]) {
        pick_draft(src, station, of, { "open": Json::boolean(false) })
      }
      gone()
    },
    focus=false,
    // (the models scroll by themselves, what goes with the one picked beside them in view)
    lists=true,
    fade_out_together=true,
    // (a line over its foot out to its sides: 2026-11-02 用户「下面整体一根通的分割线」, in place of 2026-10-30's none)
    ruled=true,
    // (a sheet of it goes in steps, as the app's other panels of levels do: all the models a step in, a maker's a step
    // further, each sliding in with its back key, the sheet as tall as each on its way there; 2026-11-10 用户「动效呢」,
    // of levels one in another's place at once, the sheet another height in the same frame)
    steps=true,
    side~,
  )
  contents.serial = @sf.last_presented()
  triple.shown = contents.serial
}

///|
/// The control of the pick `of` on `station` (ModelTriple): its line, and its panel under it while open (above it
/// where the presenters flip it up). `face`: the control as a page draws it closed with itself (a new chat's: its
/// `pick`, NewChatPick, only where it runs on a model), not read on its own: its panel's own pick is asked as the hand
/// comes to it and the panel opens once that is answered (open_triple_whole); `small`: in a composer's row (its words
/// 12). `saved`: what is said once a model picked
/// (onConfirm's toast: a chat's, from its next turn; a connect's, its model bound; nothing where nothing runs on it yet,
/// a new chat's or a new connect's). `floating`: over a page rather than in a row (a new chat's over its
/// composer, narrow): a capsule of the composer's glass.
pub fn model_triple(
  c : @ui.Ctx,
  src : Source,
  station : String,
  of : String,
  face? : Json? = None,
  small? : Bool = false,
  floating? : Bool = false,
  saved? : String = "",
  bound? : Bool = false,
) -> Unit {
  let t = @sf.theme()
  let v = match face {
    Some(_) => face
    None => src.topic("pick", pick_params(station, of)).get().value
  }
  guard v is Some(Object(_)) else { return }
  let value = field(v, "value")
  // (a face is drawn only of a control that runs on a model: there are models to pick)
  let offers = face is Some(_) || items(v, "options").length() > 0
  let vo = field(v, "valueOption")
  let account = field(v, "account")
  let me = station + "\u{1}" + of
  let dkey = "pick.save/" + station + "/" + of
  let saving = doing(dkey)
  let id = c.id("triple/" + me)
  // (`bound`: what it runs is another's to say, a preset's: shown, not opened, no chevron)
  let can = offers && !saving && !bound
  let open = triple.open == me
  let go = fn() {
    triple.asked = ""
    match face {
      Some(_) => open_triple_whole(src, station, of, Of(id), saved)
      None => open_triple_panel(src, station, of, Of(id), saved~)
    }
  }
  // (drawn of its face: its panel's pick asked as the hand comes to it, ahead of the press it opens at: a pointer come
  // to rest over it, a finger or a pointer gone down on it; let go as it leaves, where nothing else holds it)
  if face is Some(_) && !src.read_only && !c.in_bones() {
    let hand = can && (c.hovered(id) || (c.press().down && c.press_within(id)))
    if hand {
      triple_ask(src, station, of)
    } else {
      triple_let_go(me)
    }
    // (pressed before it was answered: looked at again once the frame's builds are over, where opening it tells
    // outside)
    match triple_ahead.wait {
      Some(w) => c.after_build("triple-open/" + me, fn() { w.check() })
      None => ()
    }
  }
  if can && !open {
    c.on_press(id, fn() {
      go()
    })
  }
  // (asked from elsewhere: opened as it is seen)
  if can && !open && triple.asked == me {
    go()
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
    if !offers {
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
      if !flag(v, "runtimeFixed") && (flag(v, "showRuntime") || items(vo, "runtimes").length() > 1) {
        c.box(style=triple_part, drop=triple_drop_runtime, fn() {
          c.text("·", style=muted) |> ignore
          c.text(@settings.runtime_short(runtime), style=words) |> ignore
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
      match text(v, "subagentText") {
        "" => ()
        sub =>
          c.box(style=triple_part, fn() {
            c.text(sub, style=words) |> ignore
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
    } else if !bound {
      @sf.icon(c, "chevron-down", size=12.0, color=t.p.muted) |> ignore
    }
    },
  )
  |> ignore
  // (a borrowing asked from its panel: what its own pick says of it, as what the panel asked holds it while it is
  // asked: triple_let_go)
  let asking = match face {
    Some(_) if triple.borrow_asking == me => triple_ahead_read(station, of).bind(fn(s) { s.value })
    Some(_) => None
    None => v
  }
  borrow_dialog(c, src, station, of, asking)
}

///|
/// The control of the pick `of` on `station` (model_triple's, as nodes, made once) in `parent`, its words as the core's
/// pick says them now: the model's mark and name, then (each left out where the line has not the room, what matters
/// least first) its runtime, how hard it thinks, how fast, who runs it (its mark, its name, its allowance's chips); a
/// ring in place of its chevron while what was picked is on its way; on its hover's ground while the hand is on it and
/// while its panel is open. Pressed, its panel opens beside it (open_triple_panel); borrowing a model from there is
/// asked in the presenters' confirm. `saved`: as model_triple's. Nothing while the pick is not read.
pub fn model_triple_node(parent : @view.View, src : Source, station : String, of : String, saved? : String = "") -> Unit {
  let me = station + "\u{1}" + of
  let dkey = "pick.save/" + station + "/" + of
  let v = fn() { src.topic("pick", pick_params(station, of)).get().value }
  let value = fn() { field(v(), "value") }
  let vo = fn() { field(v(), "valueOption") }
  let account = fn() { field(v(), "account") }
  let runtime = fn() { text(value(), "runtime") }
  let opened = @signals.signal(false, same=fn(a, b) { a == b })
  // borrowing a model of another station's, asked first (borrow_dialog's, put up by the presenters)
  let asks = fn(borrow : Json?) { borrow_ask(src, station, of, borrow) }
  parent.show(fn() { v() is Some(Object(_)) }, fn(o) {
    o.box(fn(b) {
      @sf.style_node(b, fn() { triple_style }, in_row=true)
      // (no wider than its row leaves it: what it says given way within it, its parts left out, its name cut last)
      b
      .shrink(Is(1.0))
      .min_width(Is(Some(0.0)))
      .ground(By(fn() { if @sf.lit_node(b) || opened.get() { @ui.tree_theme().color(Hover) } else { 0L } }))
      |> ignore
      let can = fn() { items(v(), "options").length() > 0 && !doing(dkey) }
      @sf.presses_node(b, fn() {
        guard @signals.untracked(can) && triple.open != me else { return }
        triple.asked = ""
        let (x, y, w, h) = b.placed_window_now()
        opened.set(true)
        open_triple_panel(src, station, of, At(x, y, w, h), saved~, gone=fn() { opened.set(false) }, asks~)
      }, on=can)
      // (each part what its row holds itself, so the row leaves it out where it has not the room: View::drops)
      let part = fn(r : @view.View, drop : Int, shown : () -> Bool, body : (@view.View) -> Unit) {
        r.show(shown, fn(x) {
          @sf.style_node(x, fn() { triple_part }, in_row=true)
          x.drops(Is(drop)) |> ignore
          body(x)
        })
      }
      let dot = fn(x : @view.View) { @sf.words_node(x, fn() { "·" }, fn() { triple_muted }) |> ignore }
      b.pick(fn() { items(v(), "options").length() == 0 }, fn(r, none) {
        // (its parts in a row, as the capsule's: what has not the room left out of it, View::drops)
        r
        .row(Is(true))
        .gap(Is(triple_gap))
        .lines_up(Is(Some(Middle)))
        .fits(Is(true))
        .shrink(Is(1.0))
        .min_width(Is(Some(0.0)))
        |> ignore
        if none {
          @sf.words_node(r, fn() { @sf.t("web-main.model.none") }, fn() { triple_muted }) |> ignore
          return
        }
        r.pick(fn() { (text(field(vo(), "maker"), "id"), runtime()) }, fn(m, k) { @sf.maker_mark_node(m, k.0, k.1, 14.0) |> ignore })
        // (within the room it has, the most it can say: model_triple's; the model never, its name cut short last)
        @sf.words_node(r, fn() {
          let model = text(value(), "model")
          if model == "" {
            @sf.t("web-main.model.pick")
          } else {
            match text(vo(), "name") {
              "" => model
              n => n
            }
          }
        }, fn() { triple_name })
        .shrink(Is(1.0))
        .min_width(Is(Some(0.0)))
        .cuts(Is(true))
        .allow_ellipsis(Is(true))
        // (what may be left out leaving for it first, its name cut short only then: View::fit_whole)
        .fit_whole(Is(true))
        |> ignore
        part(r, triple_drop_runtime, fn() { !flag(v(), "runtimeFixed") && (flag(v(), "showRuntime") || items(vo(), "runtimes").length() > 1) }, fn(x) {
          dot(x)
          @sf.words_node(x, fn() { @settings.runtime_short(runtime()) }, fn() { triple_words }) |> ignore
        })
        part(r, triple_drop_effort, fn() { text(value(), "effort") != "" || items(v(), "efforts").length() > 0 }, fn(x) {
          dot(x)
          @sf.words_node(x, fn() {
            let effort = text(value(), "effort")
            if effort == "" {
              @sf.t("web-main.model.defaultEffort")
            } else {
              effort_text(effort)
            }
          }, fn() { triple_words })
          |> ignore
        })
        part(r, triple_drop_effort, fn() { text(v(), "fastText") != "" }, fn(x) {
          dot(x)
          @sf.words_node(x, fn() { text(v(), "fastText") }, fn() { triple_words }) |> ignore
        })
        // (who runs it: its mark where it has one, then its name, then its allowance's chips: model_triple's)
        let profile = fn() { field(account(), "profile") }
        let marked = fn() { profile() is Some(Object(_)) }
        part(r, triple_drop_account, fn() { account() is Some(Object(_)) && marked() }, fn(x) {
          dot(x)
          x.pick(fn() { (text(profile(), "mark"), runtime()) }, fn(m, k) { @sf.maker_mark_node(m, k.0, k.1, 14.0) |> ignore })
        })
        r.show(fn() { account() is Some(Object(_)) }, fn(x) {
          @sf.style_node(x, fn() { if marked() { triple_alone } else { triple_part } }, in_row=true)
          x.drops(Is(triple_drop_name)) |> ignore
          x.show(fn() { !marked() }, dot)
          @sf.words_node(x, fn() { text(account(), "text") }, fn() {
            match text(account(), "level") {
              "amber" => triple_amber
              "red" => triple_red
              _ => triple_words
            }
          })
          |> ignore
        })
        part(r, triple_drop_account, fn() { account() is Some(Object(_)) && marked() }, fn(x) {
          @sf.quota_chips_node(x, fn() { field(profile(), "quota") }, small=true)
        })
      })
      // what was picked on its way: a ring in place of the chevron
      b.pick(fn() { doing(dkey) }, fn(e, saving) {
        if saving {
          @sf.spinner_node(e, size=12.0) |> ignore
        } else {
          @sf.icon_node(e, "chevron-down", 12.0, By(fn() { @sf.theme().p.muted })) |> ignore
        }
      })
    })
    |> ignore
  })
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
fn triple_panel(
  c : @ui.Ctx,
  src : Source,
  station : String,
  of : String,
  contents : TriplePanel,
  saved : String,
  close : () -> Unit,
  at? : String = "",
) -> Unit {
  let v = contents.pick_now(src, station, of)
  if v is None {
    // (read the first time: the panel of made-up models, in its bones; the model picked brought into view once its own
    // are read)
    let (shown, first, combos_shown) = (contents.shown.copy(), contents.first, contents.combos_shown)
    @sf.waiting(c, fn() { triple_body(c, @sfbase.sample_source, station, of, contents, Some(triple_sample()), saved, close, at) })
    contents.shown.clear()
    for k, v in shown {
      contents.shown[k] = v
    }
    contents.first = first
    contents.combos_shown = combos_shown
    return
  }
  triple_body(c, src, station, of, contents, v, saved, close, at)
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
  at : String,
) -> Unit {
  let options = items(v, "options")
  let draft = field(v, "draft")
  // (a sheet: the makers, a maker's models a step further, each a step of the sheet's, `at` the one drawn ("" its
  // first, "all" all of them by their makers, "kind:" and a maker's id its models); beside what opened it all in the
  // one panel, the makers and a maker's models side by side)
  let sheet = !@sf.in_small_panel()
  // (typed in its first step, where its search is)
  let words = if sheet && at != "" { "" } else { contents.query.trim(chars=" ").to_owned().to_lower() }
  // (the search, where the panel's head has none: a sheet's, its head its own)
  if sheet && at == "" && options.length() > 8 {
    c.box(style=triple_search, fn() { triple_find_field(c, contents, v) }) |> ignore
  }
  let listed = options.filter(fn(o) {
    let o = Some(o)
    words == "" ||
    text(o, "name").to_lower().contains(words) ||
    text(o, "model").to_lower().contains(words) ||
    items(o, "ids").iter().any(fn(i) { i is String(s) && s.to_lower().contains(words) })
  })
  // two levels (2026-11-02 用户「两级优化」): first the configurations used most here (the core's `combos`), nearest
  // what opened the panel, then the models starred (`liked`), then the way to all of them; there, every model of a maker (the core's
  // `makers`, 「分组应该是模型厂商，而不是供应商」; 「我 20 个 provider 你怎么排」: a list of them, not a row), each starred
  // there by the box before it (「星标改成前面的选择框」). Typed, every one that matches, whatever its kind. None used nor starred: all of them at
  // once.
  let searching = words != ""
  let model_of = fn(id : Json) -> Json? {
    guard id is String(id) else { return None }
    match options.search_by(fn(o) { text(Some(o), "model") == id }) {
      Some(i) => Some(options[i])
      None =>
        if id.has_prefix("fusion-") {
          match id.find("-sidekick-") {
            Some(at) if at > 7 => {
              let lead = id.exact_view(start=7, end=at).to_owned()
              options.search_by(fn(o) { text(Some(o), "model") == lead }).map(fn(i) { options[i] })
            }
            _ => None
          }
        } else {
          None
        }
    }
  }
  // (as the core says them now: one taken out (`pick.forget`) leaves the panel as it is taken out, not as the panel
  // opens again, the user, 2026-11-13: 「删掉常用模型，只有 x 会消失，然后关掉重新打开才能刷新」)
  let combos_now : Array[Json] = items(v, "combos").filter_map(fn(x) {
    if x is Object(_) && model_of(Json::string(text(Some(x), "model"))) is Some(_) {
      Some(x)
    } else {
      None
    }
  })
  // (what the first level shows of them: each drawn with how it comes or goes (triple_combos_drawn))
  let combos_drawn = triple_combos_drawn(c, contents, combos_now, v is Some(_) && !c.in_bones())
  let combos : Array[Json] = combos_drawn.filter(fn(d) { !d.2 }).map(fn(d) { d.0 })
  let liked : Array[Json] = items(v, "liked").filter_map(model_of)
  let kinds = items(v, "makers")
  let kind_of = fn(o : Json) -> String { text(field(Some(o), "maker"), "id") }
  // all of them in one list while they are few, no level past it (2026-11-10: a station of six models went through
  // 全部模型 and its makers to reach one); more, those used most and starred first and the rest a level further, by
  // their makers, a maker's models a step past them (2026-11-02 用户「我 20 个 provider 你怎么排」)
  let flat = kinds.length() < 2 || options.length() <= triple_flat_most
  let has_first = !combos_drawn.is_empty() || !liked.is_empty()
  let all = searching || (!flat && ((if sheet { at != "" } else { contents.all }) || !has_first))
  // (the kind asked for: a sheet's step's, else the one chosen in the panel)
  // (none asked for is no maker's id: the makers with none known, 其他, have the id "", and a step into them was
  // taken for no step, the makers listed again under 其他's name, 2026-11-10 用户「怎么其它厂商里又有个 anthropic」)
  let kind_asked = if !sheet {
    contents.kind
  } else if at.has_prefix("kind:") {
    at.exact_view(start=5).to_owned()
  } else {
    triple_no_kind
  }
  // (the kind browsed: as asked, else the picked model's, else the first)
  let kind = if kinds.iter().any(fn(k) { text(Some(k), "id") == kind_asked }) {
    kind_asked
  } else {
    match model_of(Json::string(text(v, "option"))) {
      Some(o) if kinds.iter().any(fn(k) { text(Some(k), "id") == kind_of(o) }) => kind_of(o)
      _ => kinds.get(0).map(fn(k) { text(Some(k), "id") }).unwrap_or("")
    }
  }
  let kind_open = !sheet || kind_asked != triple_no_kind
  // a step in, in a sheet: what `to` names of the models, its foot as every step's (each step's ids its own: two of
  // them are drawn while one slides over the other)
  let step = fn(title : String, to : String, n : Int) {
    @sf.panel_go(
      title,
      fn(c, close) { c.scope(n, fn() { triple_panel(c, src, station, of, contents, saved, close, at=to) }) },
      foot=fn(c, close) { c.scope(n, fn() { triple_foot(c, src, station, of, contents, close, saved~, at=to) }) },
    )
  }
  let rest = listed.filter(fn(o) { searching || kind_of(o) == kind })
  // a maker's models by their series (2026-11-02 用户「要保留模型分组，opus 系列之类的」) where a series has more than
  // one: a name over each of two series of one model each said every name twice (2026-11-10)
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
  let by_series = !searching && series.length() > 1 && series.iter().any(fn(s) { s.1.length() > 1 })
  let efforts = items(v, "efforts")
  let all_efforts : Array[(String, String)] = []
  // (no level for the model's own: 2026-11-02 用户「思考深度不再提供默认」)
  if efforts.length() > 0 {
    for e in efforts {
      if e is String(e) {
        all_efforts.push((e, effort_text(e)))
      }
    }
  }
  // (each made what it runs on at once, the panel staying open: kept for the model too, as it runs next time it is
  // picked; and by the core while the panel is open, for a model never run here picked in it next: the pick's
  // options' `usual`)
  let pick_effort = fn(e : String) {
    // (not taken: its stops back on what it runs on)
    let back = fn() {
      for _, st in contents.effort_stops {
        st.reset()
      }
    }
    pick_save(
      src,
      station,
      of,
      { "effort": if e == "" { Json::null() } else { Json::string(e) } },
      // (the core kept none of it, its `saved: false`: nothing picked yet that would think that hard, a session
      // still on its station's own model; nothing else tells the level back, so its stops would stay on what was
      // pressed)
      ok=fn(res) {
        if field(Some(res), "saved") is Some(False) {
          back()
        }
      },
      failed=back,
    )
  }

  // what each says of how it runs right after its name, on its line (2026-11-02 用户「常用模型的信息分两边很难读」,
  // 「移动端…跟在模型后面」; under it, two lines, rejected: 「到底为什么要两行」)
  let picked = text(v, "option")
  // (one that says nothing of how it runs has never run here: it says how hard it thinks once that is set by hand in
  // the panel, so the room for the widest level is its from the start, the panel as wide whatever is set in it)
  let level_w = all_efforts.fold(init=0.0, fn(m, e) { dmax(m, c.words_across(e.1, triple_note)) })
  let usual_w = options.fold(init=0.0, fn(m, o) {
    let said = text(Some(o), "usualText")
    // (and one that says how hard it thinks, the one picked as it is set now: as wide as with the widest level)
    let own = match text(field(Some(o), "usual"), "effort") {
      "" => 0.0
      e => c.words_across(effort_text(e), triple_note)
    }
    let w = if said == "" {
      level_w
    } else if own > 0.0 {
      c.words_across(said, triple_note) - own + dmax(level_w, own)
    } else {
      c.words_across(said, triple_note)
    }
    dmax(m, w)
  })
  // each column's words as wide as the widest of them picked (the models' of all of them, whatever the filter leaves):
  // the panel, as wide as what it holds, as wide whichever is picked and whatever is typed (as a segmented choice's)
  let names_w = options.fold(init=0.0, fn(m, o) {
    let o = Some(o)
    let name = c.words_across(text(o, "name"), triple_row_picked)
    let name = if usual_w > 0.0 { name + @ui.Space::px(S1_5) + usual_w } else { name }
    dmax(dmax(m, name), c.words_across(text(field(o, "spent"), "text"), triple_note))
  })
  // (and the configurations used most: a name, how it runs in a capsule after it, the capsule's sides with it)
  let names_w = combos_drawn
    .map(fn(d) { d.0 })
    .fold(init=names_w, fn(m, x) {
      let x = Some(x)
      dmax(
        m,
        c.words_across(text(x, "name"), triple_row_picked) +
        @ui.Space::px(S1_5) +
        c.words_across(text(x, "text"), triple_combo_words) +
        2.0 * @ui.Space::px(S2),
      )
    })
    .ceil()
  // (the panel at least as wide as a row with the widest name and the widest of how it runs, and its star, where it
  // has the room)
  let row_least = names_w + 14.0 + @sf.icon_button_side + 4.0 * @ui.Space::px(S1_5) + 2.0 * @ui.Space::px(S2_5) +
    @ui.Space::px(S3_5)
  c.box(style=@ui.style(min_w=Within(row_least)), fn() {  }) |> ignore
  let up = @sf.panel_opens_up()
  // the first level, two things told apart (the user, 2026-11-10: 「感觉常用模型配置需要跟普通的收藏模型从 ui 上区分
  // 开」; and then 「我常用只有一个 sonnet 是什么逻辑」「收藏跟常用不一样」「常用包括了思考深度和速度还有上下文长度」
  // 「是一种配置」): those used most, each a configuration (the core's `combos`: a model with its runtime, how hard it
  // thinks, how fast and how much context; one model run two ways two rows), under their name (常用搭配), how each
  // runs in a capsule after its name, no star (a configuration is not starred) but what takes it out of them where a
  // star is (「常用模型应该是一种特定配置，并且可以删掉，跟模型没有关系」), the most used nearest what opened the
  // panel (2026-11-01 用户「那它就不应该跑到离按钮很远的最顶上去啊」); and every starred model, plain models told by
  // their stars, past them with room between, one of them there whether or not a configuration of it is used most.
  // Each model its star at its end (lit while starred; pressed, starred or not where it stands); the one picked, where
  // it is not starred, after them where the rest are a level further (in the one list of a few, among the rest), so it
  // is always in sight as a model. Each model stays where it was while the panel is open, starred or not since.
  let now_used : Array[String] = []
  match model_of(Json::string(picked)) {
    Some(o) if !flat && !liked.contains(o) => now_used.push(picked)
    _ => ()
  }
  let now_liked : Array[String] = liked.map(fn(o) { text(Some(o), "model") })
  let (used_ids, liked_ids) = match contents.first {
    Some(was) => {
      // (one starred a level further is with them once come back; in the one list of a few it stays where it is)
      if !flat {
        for id in now_used {
          if !was.0.contains(id) && !was.1.contains(id) {
            was.0.push(id)
          }
        }
        for id in now_liked {
          if !was.0.contains(id) && !was.1.contains(id) {
            was.1.push(id)
          }
        }
      }
      was
    }
    None => {
      if !c.in_bones() {
        contents.first = Some((now_used, now_liked))
      }
      (now_used, now_liked)
    }
  }
  // (the starred, then the one picked where it is not)
  let starred : Array[Json] = (liked_ids + used_ids).filter_map(fn(id) { model_of(Json::string(id)) })
  // (the rest of a few, past them in the same list, in the core's order)
  let others : Array[Json] = if flat {
    options.filter(fn(o) { !used_ids.contains(text(Some(o), "model")) && !liked_ids.contains(text(Some(o), "model")) })
  } else {
    []
  }
  // the models' room as tall as what it holds at each level, up to a most, scrolling in itself past that (the user,
  // 2026-11-10: 「感觉不用固定高度吧，不能做到撑开吗？定个最大高度」, of a room as tall at every level, what a short
  // level did not need left empty over it): beside what opened it the web's 360; in a sheet eight rows and a half
  // (the half row says there is more), less where the sheet at its most has less for it
  let t = @sf.theme()
  let row_h = t.rows.pick + 1.0
  let list_most = if sheet {
    dmax(3.0 * row_h, dmin(triple_sheet_rows * row_h, @sf.sheet_window_h(c) * @sf.sheet_most - triple_sheet_rest))
  } else {
    triple_list_h
  }
  let scroll = fn(key : String, most : Double, body : () -> Unit) {
    c.capped(key, most, shrinks=true, fn() { c.box(style=triple_rows, body) |> ignore }) |> ignore
  }
  // beside what opened it, where the models go by level, their room is its most at every level, whichever maker's are
  // shown and whatever is typed: the panel one size all the while it is open. As tall as each level holds, it was
  // another height at once as a level was come to (2026-11-10: 461 to 323 in a frame for a station's 全部模型, its
  // ground, the line between its columns and all under it with it), and there the levels are not steps that slide,
  // as a sheet's are. The way to all of them then at the room's foot, the models from its top (2026-11-02 用户「全部
  // 模型的位置需要讲究一下」: level with the last of the levels beside them, as a list's 「查看全部」 is).
  let level_h : @ui.Size? = if !sheet && !flat { Some(Px(triple_list_h)) } else { None }
  let level_ends : @ui.Justify? = if level_h is Some(_) { Some(JBetween) } else { None }
  // a level's models (all that match what is typed), scrolling by themselves
  let model_rows = fn(most : Double) {
    scroll("triple/models/" + (if searching { "" } else { kind }), most, fn() {
      for s in series {
        if by_series {
          triple_column_head(c, s.0)
        }
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
  // the makers, a row each: its mark, its name, how many of the models it makes; the one browsed lit
  let kind_rows = fn(most : Double) {
    scroll("triple/kinds", most, fn() {
      for k in kinds {
        let kv = Some(k)
        let id = text(kv, "id")
        let on = kind_open && id == kind
        let count = match field(kv, "count") {
          Some(Number(n, ..)) => n.to_int().to_string()
          _ => ""
        }
        triple_option(
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
          on_press=fn() {
            if sheet {
              step(text(kv, "title"), "kind:" + id, 2 + kinds.search_by(fn(x) { text(Some(x), "id") == id }).unwrap_or(0))
            } else {
              contents.kind = id
            }
          },
        )
      }
    })
  }
  // the way to all of them, at the foot of the first level's models (2026-11-02 用户「全部模型的位置需要讲究一下」: as
  // a list's 「查看全部」 is)
  let to_all = fn() {
    triple_option(
      c,
      "triple/all",
      @sf.t("web-main.model.allModels"),
      false,
      // (its chevron right after its words: 「全部模型的箭头跟在文字后面」)
      fn() {
        c.text(@sf.t("web-main.model.allModels"), style=triple_words) |> ignore
        @sf.icon(c, "chevron-right", size=14.0, color=t.p.muted) |> ignore
      },
      checks=false,
      on_press=fn() {
        if sheet {
          step(@sf.t("web-main.model.allModels"), "all", 1)
        } else {
          contents.all = true
        }
      },
    )
  }
  // the models' room: the first level (those used most and starred, the way to all of them under them), or all of
  // them (typed, those that match; few, at once; else the makers and a maker's models: side by side beside what opened
  // the panel, a maker's a step past the makers in a sheet), the way back over them where there is one
  let models = fn() {
    if !all {
      // (the way to all of them under them)
      let room = c.box(style=triple_room, h?=level_h, justify?=level_ends, fn() {
        // (each row of the first level by its key, as the library's group draws them (@sf.group_rows): one taken out of
        // those used most leaves where it was (triple_combos_drawn), then its room closes as the next of them opens its
        // own where it comes, what is over and under them going with their rooms, the panel's edge too: the user,
        // 2026-11-13, 「去掉后要有补位，还要有动效」. Its room given back at once as it had left, a panel opened up from its
        // control was that much shorter at its top in one frame, what was over it drawn from where it had been, past
        // that top, on its way down)
        let first_rows : Array[(String, () -> Unit)] = []
        let rows = fn(of_them : Array[Json]) {
          for o in of_them {
            first_rows.push(
              ("model/" + text(Some(o), "model"), fn() { triple_model_row(c, src, station, of, v, Some(o), names_w, saved, close) }),
            )
          }
        }
        // (its groups one after another, room between two that both hold something)
        let groups : Array[(String, Bool, () -> Unit)] = [
          (
            "combos",
            !combos_drawn.is_empty(),
            fn() {
              first_rows.push(("combos", fn() { triple_column_head(c, @sf.t("web-main.combos.label")) }))
              for d in (if up { combos_drawn.rev() } else { combos_drawn }) {
                let (x, look, leaving) = d
                first_rows.push(
                  (
                    triple_combo_key(Some(x)),
                    fn() {
                      let b = c.box(style=triple_moving, fn() {
                        triple_combo_row(c, src, station, of, v, Some(x), model_of(Json::string(text(Some(x), "model"))), names_w, saved, close)
                      })
                      // (coming or going by its own motion; going, only drawn: what is pressed there is what is under it)
                      match look {
                        Some(l) => c.look(b, l)
                        None => ()
                      }
                      @motion.leaving(c, b, !leaving)
                    },
                  ),
                )
              }
            },
          ),
          ("starred", !starred.is_empty(), fn() { rows(starred) }),
          ("others", !others.is_empty(), fn() { rows(others) }),
        ]
        let shown = groups.filter(fn(g) { g.1 })
        // (the configurations used most nearest what opened the panel, the starred past them, the rest of a few past
        // those; the room between two by the two it is between, whichever way the panel opened)
        let shown_turned = if up { shown.rev() } else { shown }
        for i, g in shown_turned {
          if i > 0 {
            let (a, b) = if up { (g.0, shown_turned[i - 1].0) } else { (shown_turned[i - 1].0, g.0) }
            first_rows.push(("apart/" + a + "/" + b, fn() { c.box(style=triple_apart, fn() {  }) |> ignore }))
          }
          (g.2)()
        }
        scroll("triple/first", if flat { list_most } else { list_most - row_h }, fn() {
          // (each with the room between it and the next in its own, so that room opens and closes with it: on its side
          // towards the panel's far end from what opened it, the row there, a model's, none past it; the panel's own rows
          // by the panel, its bones as they are)
          c.box(style=triple_first_rows, fn() {
            let far = if up { 0 } else { first_rows.length() - 1 }
            let each = first_rows.mapi(fn(i, r) {
              let style = if i == far {
                triple_first_rows
              } else if up {
                triple_first_row_up
              } else {
                triple_first_row
              }
              (r.0, fn() { c.box(style~, r.1) |> ignore })
            })
            if v is Some(_) && !c.in_bones() {
              @sf.group_rows(c, triple_first_group(contents), each)
            } else {
              for r in each {
                (r.1)()
              }
            }
          })
          |> ignore
        })
        if !flat {
          to_all()
        }
      })
      // (shorter where the sheet, at its most, has less room left for it: what goes with the models under them, on
      // more lines on a narrow screen, never pushed out of it)
      c.gives_way(room)
      return
    }
    // (the way back: beside what opened it a row over them; a sheet's step's head has its back key)
    let back_to = if searching || sheet {
      ""
    } else if has_first {
      @sf.t("web-main.model.allModels")
    } else {
      ""
    }
    let room = c.box(style=triple_room, h?=level_h, fn() {
      if back_to != "" {
        triple_option(c, "triple/back", back_to, false, fn() {
          @sf.icon(c, "chevron-left", size=14.0, color=t.p.muted) |> ignore
          c.text(back_to, style=triple_picked) |> ignore
        },
          checks=false,
          on_press=fn() {
            contents.all = false
          },
        )
      }
      let most = if back_to != "" { list_most - row_h } else { list_most }
      if searching {
        model_rows(most)
      } else if sheet {
        if kind_asked == triple_no_kind { kind_rows(most) } else { model_rows(most) }
      } else {
        c.box(style=triple_browse, fn() {
          c.box(style=triple_kinds_column, fn() { kind_rows(most) }) |> ignore
          c.box(style=triple_rule_v, fn() {  }) |> ignore
          c.box(style=triple_models_column, fn() { model_rows(most) }) |> ignore
        })
        |> ignore
      }
    })
    c.gives_way(room)
  }
  // how hard it thinks, in view at every level (2026-11-10: gone with the level of all the models, and in a sheet a
  // sheet of its own over this one for four levels): beside what opened the panel its own column at the panel's right
  // (2026-11-02 用户「思考深度放在整个面板的右边」「模型跟思考深度的并排的」); in a sheet a segmented choice under the
  // models, its name before it
  let h_effort = @sf.t("web-main.model.effort")
  // (none picked, the model's own where its runtime says it: 2026-11-02 用户「能拿到默认档就勾上它」)
  let effort_now = match text(draft, "effort") {
    "" => text(v, "effortDefault")
    e => e
  }
  // beside what opened it, its title (and its search) over the models (heads_itself)
  let models_head = fn() {
    if options.length() > 8 {
      @sf.panel_head(c, @sf.t("android-chat.new.model"), end=fn(c) { triple_find_field(c, contents, v) })
    } else {
      @sf.panel_head(c, @sf.t("android-chat.new.model"))
    }
  }
  // (beside what opened it no wider than its first level needs, 2026-10-26 用户「没啥内容也这么宽感觉会很奇怪」; wider
  // only at the level of all of many, their makers a column before a maker's models, and as wide from then on)
  let beside_w = (if all && !searching { triple_panel_w_many } else { triple_panel_w }) - 2.0 * @sf.panel_pad
  if (sheet && at == "sidekick") || (!sheet && contents.sidekick) {
    triple_sidekick_step(c, src, station, of, contents, v, sheet, beside_w, level_h)
    return
  }
  if sheet {
    models()
    if all_efforts.length() > 0 {
      // its name, and under it a stop for each level across the sheet, the one it is at said in the thumb (@sf.stops):
      // as many levels as a model has on one line in any language, nothing opened over the sheet to pick one
      c.box(style=triple_effort_block, fn() {
        c.box(style=triple_effort_name, fn() { c.text(h_effort, style=triple_head) |> ignore }) |> ignore
        let stops = match contents.effort_stops.get(at) {
          Some(st) => st
          None => {
            let st = @sf.Stops::new()
            contents.effort_stops[at] = st
            st
          }
        }
        @sf.stops(
          c,
          "triple/effort/" + at,
          all_efforts.map(fn(e) { e.1 }),
          all_efforts.search_by(fn(e) { e.0 == effort_now }).unwrap_or(-1),
          stops,
          said=h_effort,
          on_pick=fn(i) { pick_effort(all_efforts[i].0) },
        )
        |> ignore
      })
      |> ignore
    }
  } else if all_efforts.length() == 0 {
    c.box(style=@ui.style(max_w=Fixed(beside_w)), fn() {
      models_head()
      models()
    })
    |> ignore
  } else {
    // (the models and how hard it thinks side by side, each titled alike over it, the line between them up to the
    // panel's top: 「上面的分割线试试到顶」)
    c.box(style=triple_side_by_side.then(@ui.style(max_w=Fixed(beside_w))), fn() {
      c.box(style=triple_models_column, fn() {
        models_head()
        models()
      })
      |> ignore
      c.box(style=triple_effort_column, fn() {
        // (the line between them out of their flow, in the middle of the room between them, from the panel's top
        // down to the line over its foot, meeting it: 「竖的那根怎么没跟横的接起来呢」)
        c.box(style=triple_rule_v, left=-triple_between_rule, top=-@sf.panel_pad, bottom=-@sf.panel_rule_over(), fn() {  })
        |> ignore
        @sf.panel_head(c, h_effort)
        triple_choices(c, "triple/effort", "", all_efforts, effort_now, pick_effort)
      })
      |> ignore
    })
    |> ignore
  }
  // the model picked in view as the panel opens and as each level is come to (2026-11-05 用户「模型选择面板打开不会自动
  // 滚动到能看见已选择模型的地方」), not while what is typed filters them; and again once the panel is found to stand
  // above what opened it (its side is the presenters' once it is laid out: a panel flipped up for want of room below
  // is first built as one going down, its rows in the other order and the one to bring into view another; shown for
  // that alone, the row nearest the hand was left a row past the scroller's foot, under the panel's, 2026-11-10)
  let level = (if !all { "first" } else if kind_open { "all/" + kind } else { "all" }) + (if up { "/up" } else { "" })
  let shown_was = contents.shown.get(at).unwrap_or("")
  if !searching && shown_was != level {
    // (a first level opening up from what opened it starts at its foot, nearest the hand, where the one picked shows
    // from there; else at the one picked. One of the two, said once: brought to the foot and then to the one picked,
    // each as the other had been laid out, a sheet's step did not come to rest, 2026-11-10)
    // (each by its row's key: a configuration's, a model's)
    let model_key = fn(o : Json) { "triple/model/" + text(Some(o), "model") }
    let nearest = match (combos.get(0), starred.last(), others.last()) {
      (Some(x), _, _) => triple_combo_key(Some(x))
      (None, Some(o), _) | (None, None, Some(o)) => model_key(o)
      _ => ""
    }
    let is_picked = fn(o : Json) { text(Some(o), "model") == picked }
    // (at the first level the configuration it runs on exactly, where one is, else its model)
    let combo_on = if all { None } else { combos.search_by(fn(x) { flag(Some(x), "selected") }) }
    let (picked_key, from_foot) = match combo_on {
      Some(i) => (triple_combo_key(Some(combos[i])), i)
      None =>
        (
          "triple/model/" + picked,
          // (the configurations' title a row under it too)
          (if combos.is_empty() { 0 } else { 1 }) +
          (match (starred.search_by(is_picked), others.search_by(is_picked)) {
            (Some(j), _) => combos.length() + starred.length() - 1 - j
            (None, Some(k)) => combos.length() + starred.length() + others.length() - 1 - k
            _ => 0
          }),
        )
    }
    let rows_in_view = ((if flat { list_most } else { list_most - row_h }) / row_h).to_int()
    let to = if !all && up && nearest != "" && from_foot < rows_in_view - 1 { nearest } else { picked_key }
    contents.shown[at] = level
    c.show(c.id(to))
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
/// One of what goes with the model, at the panel's foot (who runs it, what on, which sidekick, how fast, how much
/// context): a capsule on the words' tint, its name, what is picked now (`mark`: a runtime's mark before it; `maker`:
/// a model maker's mark before it), a chevron. All of them one part in one place (2026-11-10: two of them rows with a
/// chevron under the models, three of them words at the foot with none, read as what it says rather than what is
/// pressed).
fn triple_chip(
  c : @ui.Ctx,
  id : Int,
  head : String,
  words : String,
  mark? : String = "",
  maker? : String = "",
  look? : @ui.TextStyle = triple_who_name,
) -> Unit {
  let b = c.box(style=triple_who(), id~, fn() {
    c.text(head, style=triple_who_lead) |> ignore
    if mark != "" || maker != "" {
      @sf.maker_mark(c, maker, mark, triple_pick_mark) |> ignore
    }
    c.text(words, style=look) |> ignore
    @sf.icon(c, "chevron-down", size=triple_pick_chevron, color=@sf.theme().p.muted) |> ignore
  })
  c.semantics(b, Button, id~, label=words)
}

///|
/// Who runs it, at the foot's start (the web's panel's foot, the phone's sheet's): the accounts in a panel of their
/// own, from it (on 中屏/大屏 flush with the model panel `panel_serial`).
fn triple_runs_who(
  c : @ui.Ctx,
  src : Source,
  station : String,
  of : String,
  v : Json?,
  panel_serial : Int,
) -> Unit {
  let who = c.id("triple/who")
  let revert_none = fn() {
    let cur = src.topic("pick", pick_params(station, of)).get().value
    if triple_selected_accounts(field(cur, "draft")) is Some([]) {
      pick_draft(src, station, of, { "open": Json::boolean(false) })
    }
  }
  let go = fn() {
    triple.accounts_asked = false
    @sf.panel_nodes(
      @sf.t("web-main.model.account"),
      fn(n, close) { triple_accounts_node(n, src, station, of, close) },
      from=Of(who),
      w=triple_accounts_w,
      gone=revert_none,
      focus=false,
      match_panel=panel_serial,
    )
  }
  c.on_press(who, go)
  // (asked from elsewhere: opened as it is seen)
  if triple.accounts_asked {
    go()
  }
  let level = text(v, "whoLevel")
  let words = match text(v, "who") {
    "" => @sf.t("web-main.model.selectAll")
    w => w
  }
  triple_chip(
    c,
    who,
    @sf.t("web-main.model.account"),
    words,
    look=if level == "amber" {
      triple_who_amber
    } else if level == "red" {
      triple_who_red
    } else {
      triple_who_name
    },
  )
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
  c.on_press(id, fn() {
    @sf.pick(
      head,
      choices,
      now,
      fn(r) {
        pick_save(src, station, of, { "runtime": Json::string(r) })
      },
      from=Of(id),
      search=false,
    )
  })
  triple_chip(c, id, head, @settings.runtime_label(now), mark=now)
}

///|
/// Which sidekick runs with the model on Devin Fusion, at the foot beside who runs it: its name and the one picked;
/// pressed, a secondary panel of `副模型 × 思考深度` (`triple_sidekick_node`).
fn triple_sidekick(
  c : @ui.Ctx,
  src : Source,
  station : String,
  of : String,
  contents : TriplePanel,
  v : Json?,
  saved : String,
  at : String,
) -> Unit {
  let head = @sf.t("web-main.model.sidekick")
  let now = text(v, "sidekickNow")
  let sidekicks = items(v, "sidekicks")
  let picked = sidekicks.search_by(fn(sk) { text(Some(sk), "id") == now }).map(fn(i) { sidekicks[i] })
  let words = match picked {
    Some(sk) => text(Some(sk), "text")
    None => @sf.t("web-main.model.sidekickNone")
  }
  let maker = match picked {
    Some(sk) => text(field(Some(sk), "maker"), "id")
    None => ""
  }
  let sheet = !@sf.in_small_panel()
  let id = c.id("triple/sidekick")
  c.on_press(id, fn() {
    if sheet {
      if at == "sidekick" {
        @sf.panel_back() |> ignore
      } else {
        @sf.panel_go(
          head,
          fn(c, close) { c.scope(99, fn() { triple_panel(c, src, station, of, contents, saved, close, at="sidekick") }) },
          foot=fn(c, close) { c.scope(99, fn() { triple_foot(c, src, station, of, contents, close, saved~, at="sidekick") }) },
        )
      }
    } else {
      contents.sidekick = !contents.sidekick
    }
  })
  triple_chip(c, id, head, words, maker~, mark=if now != "" { "devin" } else { "" })
}

///|
fn triple_sidekick_step(
  c : @ui.Ctx,
  src : Source,
  station : String,
  of : String,
  contents : TriplePanel,
  v : Json?,
  sheet : Bool,
  beside_w : Double,
  level_h : @ui.Size?,
) -> Unit {
  let t = @sf.theme()
  let groups = triple_sidekick_groups(v)
  let now = text(v, "sidekickNow")
  let active_idx = groups.search_by(fn(g) { g.efforts.iter().any(fn(w) { w.0 == now }) }).unwrap_or(0)
  let active_group = groups.get(active_idx).unwrap_or({ id: "", name: "", maker: "", efforts: [] })
  let active_eff_lbl = active_group.efforts.search_by(fn(w) { w.0 == now }).map(fn(i) { active_group.efforts[i].1 }).unwrap_or("")
  let h_sidekick = @sf.t("web-main.model.sidekick")
  let h_effort = @sf.t("web-main.model.effort")
  let efforts : Array[(String, String)] = if active_group.id == "" || active_group.efforts.is_empty() {
    [("", "—")]
  } else {
    active_group.efforts.map(fn(w) { (w.0, w.1) })
  }
  let pick_eff = fn(sid : String) {
    match active_group.efforts.search_by(fn(w) { w.0 == sid && sid != "" }) {
      Some(i) => {
        let chosen = active_group.efforts[i]
        if chosen.0 != now && chosen.2 != "" {
          pick_save(src, station, of, { "model": Json::string(chosen.2), "runtime": Json::string("devin") })
        }
      }
      None => ()
    }
  }
  let left_rows = fn() {
    c.box(style=triple_room, h?=level_h, fn() {
      c.box(style=triple_rows, fn() {
        for g in groups {
          let on = active_group.id == g.id
          triple_option(
            c,
            "triple/sidekick/model/" + g.name,
            g.name,
            on,
            fn() {
              if g.maker != "" {
                @sf.maker_mark(c, g.maker, "devin", 14.0) |> ignore
              } else {
                c.box(style=triple_kind_mark, fn() {  }) |> ignore
              }
              c.text(g.name, style=if on { triple_row_picked } else { triple_row_name }) |> ignore
            },
            on_press=fn() {
              if g.id == "" {
                let target = g.efforts.get(0).map(fn(w) { w.2 }).unwrap_or("")
                if now != "" && target != "" {
                  pick_save(src, station, of, { "model": Json::string(target), "runtime": Json::string("devin") })
                }
                if sheet {
                  @sf.panel_back() |> ignore
                } else {
                  contents.sidekick = false
                }
              } else {
                let chosen = match g.efforts.search_by(fn(w) { w.1 == active_eff_lbl && active_eff_lbl != "" }) {
                  Some(i) => g.efforts[i]
                  None => g.efforts[0]
                }
                if chosen.0 != now && chosen.2 != "" {
                  pick_save(src, station, of, { "model": Json::string(chosen.2), "runtime": Json::string("devin") })
                }
              }
            },
          )
        }
      })
      |> ignore
    })
    |> ignore
  }
  c.box(style=if sheet { triple_side_by_side } else { triple_side_by_side.then(@ui.style(max_w=Fixed(beside_w))) }, fn() {
    c.box(style=triple_models_column, fn() {
      if sheet {
        triple_column_head(c, @sf.t("android-chat.new.model"))
      } else {
        triple_option(
          c,
          "triple/sidekick/back",
          h_sidekick,
          false,
          fn() {
            @sf.icon(c, "chevron-left", size=14.0, color=t.p.muted) |> ignore
            c.text(h_sidekick, style=triple_picked) |> ignore
          },
          checks=false,
          on_press=fn() { contents.sidekick = false },
        )
      }
      left_rows()
    })
    |> ignore
    if sheet {
      c.box(style=triple_effort_column, fn() {
        c.box(style=triple_rule_v, left=-triple_between_rule, top=0.0, bottom=-@sf.panel_rule_over(), fn() {  })
        |> ignore
        triple_column_head(c, h_effort)
        triple_choices(c, "triple/sidekick/effort", "", efforts, if active_group.id == "" { "" } else { now }, pick_eff)
      })
      |> ignore
    } else {
      c.box(style=triple_effort_column, fn() {
        c.box(style=triple_rule_v, left=-triple_between_rule, top=-@sf.panel_pad, bottom=-@sf.panel_rule_over(), fn() {  })
        |> ignore
        @sf.panel_head(c, h_effort)
        triple_choices(c, "triple/sidekick/effort", "", efforts, if active_group.id == "" { "" } else { now }, pick_eff)
      })
      |> ignore
    }
  })
  |> ignore
}

///|
priv struct SidekickGroup {
  id : String
  name : String
  maker : String
  efforts : Array[(String, String, String)]
}

///|
fn triple_sidekick_groups(v : Json?) -> Array[SidekickGroup] {
  let sidekicks = items(v, "sidekicks")
  let default_eff = @sf.t("web-main.model.defaultEffort")
  let groups : Array[SidekickGroup] = []
  for sk in sidekicks {
    let sv = Some(sk)
    let sid = text(sv, "id")
    let label = text(sv, "text")
    let target = text(sv, "model")
    let maker = text(field(sv, "maker"), "id")
    let (name_part, eff_part) = if sid == "" {
      (label, "")
    } else {
      match label.find(" · ") {
        Some(idx) => (label.exact_view(start=0, end=idx).to_owned(), label.exact_view(start=idx + 3).to_owned())
        None => (label, default_eff)
      }
    }
    match groups.search_by(fn(g) { g.name == name_part && (sid == "" || g.id != "") }) {
      Some(i) => groups[i].efforts.push((sid, eff_part, target))
      None => groups.push({ id: sid, name: name_part, maker, efforts: [(sid, eff_part, target)] })
    }
  }
  groups
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
    // (Fast its bolt)
    @sf.choice("fast", "Fast", note=@sf.t("web-main.model.fastNote"), icon="zap"),
  ]
  let id = c.id("triple/fast")
  c.on_press(id, fn() {
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
  })
  let words = choices.search_by(fn(ch) { ch.key == now }).map(fn(i) { choices[i].label }).unwrap_or("")
  triple_chip(c, id, head, words)
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
  c.on_press(id, fn() {
    @sf.pick(
      head,
      choices,
      now,
      fn(k) {
        let set = if k == "" { Json::null() } else { Json::string(k) }
        pick_save(src, station, of, { "context": set })
      },
      from=Of(id),
      search=false,
    )
  })
  let words = choices.search_by(fn(ch) { ch.key == now }).map(fn(i) { choices[i].label }).unwrap_or("")
  triple_chip(c, id, head, words)
}

///|
/// Its foot (the presenter's, where every panel's foot stands): what goes with the model, each a capsule (who runs it,
/// what on where its model runs on more than one, how fast, how much context: on a second line where one is short),
/// and where the model picked is another station's, borrowing it (asked first). Nothing to confirm: each pick is made
/// what it runs on as it is picked (2026-11-01 用户「从第一性原理出发重新思考这个组件的使用场景」).
fn triple_foot(
  c : @ui.Ctx,
  src : Source,
  station : String,
  of : String,
  contents : TriplePanel,
  close : () -> Unit,
  saved? : String = "",
  at? : String = "",
) -> Unit {
  let v = contents.pick_now(src, station, of)
  if v is None {
    return
  }
  let borrow = field(v, "borrow")
  let panel_serial = if contents.serial > 0 { contents.serial } else { @sf.last_presented() }
  c.box(style=triple_who_room, keep=true, flow=true, line_gap=@ui.Space::px(S2), fn() {
    triple_runs_who(c, src, station, of, v, panel_serial)
    if !flag(v, "runtimeFixed") && items(v, "runtimes").length() > 1 {
      triple_runtime(c, src, station, of, v)
    }
    if !items(v, "sidekicks").is_empty() {
      triple_sidekick(c, src, station, of, contents, v, saved, at)
    }
    if flag(v, "fastAvailable") {
      triple_speed(c, src, station, of, v)
    }
    if !items(v, "contexts").is_empty() {
      triple_context(c, src, station, of, v)
    }
  })
  |> ignore
  if borrow is Some(Object(_)) {
    @sf.button(c, text(borrow, "action"), key="triple/borrow", tone=Primary, disabled=!flag(borrow, "allowed"), on_press=fn() {
      triple.open = ""
      // (the panel shut first: shutting it shuts what is over it, the ask put up after it is not; asked of the
      // control's build, said before it shuts, so what the panel held of the pick is held on for it)
      if contents.asks is None {
        triple.borrow_asking = station + "\u{1}" + of
      }
      close()
      match contents.asks {
        Some(ask) => ask(borrow)
        None => ()
      }
    }) |> ignore
  }
}

///|
/// A model's row: its maker's mark, its name (what it has spent under it) `names_w` wide (the widest of the models'),
/// how it runs picked right after its name (cut short first where the row is short), at its end the station it comes
/// from; beside it at its end its star, lit
/// while it is starred: pressed, starred or not (`pick.like`). Pressed,
/// picked as the core says it runs picked (its `usual`): as it last ran here; one that never ran here, with what was
/// set by hand in the panel since it opened, where it takes it.
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
  // (its ids, a line each)
  let ids = items(o, "ids").filter_map(fn(i) { if i is String(s) { Some(s) } else { None } }).join("\n")
  // how it would run picked, after its name (the core's: as it last ran here; one never run here, how it was set by
  // hand in the panel since it opened; the user, 2026-11-10: 「常用模型按理说是包括思考深度的，这样随便切会让常用模型的
  // 配置失效」, of every model picked taking what was set by hand; what is used most is a configuration of its own
  // now, triple_combo_row, the user, 2026-11-10: 「常用包括了思考深度和速度还有上下文长度」「是一种配置」); nothing
  // after the one picked, whose own is what the panel shows under the models
  let usual = if picked { "" } else { text(o, "usualText") }
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
  }
  let liked = flag(o, "liked")
  // (its star beside the row, not in it: a press of its own)
  let like_star = fn() {
    @sf.icon_button(
      c,
      if liked { "star-fill" } else { "star" },
      key="triple/like/" + model,
      round=true,
      ink=if liked { t.p.text } else { t.p.muted },
      label=@sf.t("web-main.model.likeModel", args=[("model", text(o, "name"))]),
      on_press=fn() {
        (src.call)(
          "pick.like",
          { "station": Json::string(station), "of": Json::string(of), "model": Json::string(model), "liked": Json::boolean(!liked) },
          fn(res) {
            match res {
              Ok(_) => ()
              Err(e) => toast_later(@sf.t("web-main.pick.failed", args=[("error", error_words(e))]))
            }
          },
        )
      },
    )
  }
  // pressed: picked
  let go = fn() {
    if text(o, "availability") == "borrowable" {
      // (another station's: borrowed first, from the foot)
      pick_draft(src, station, of, { "model": Json::string(model) })
    } else {
      // made what it runs on at once, as it last ran here, and the panel closed: nothing of it left to confirm
      triple.open = ""
      close()
      if !picked || text(field(v, "value"), "model") != text(field(v, "draft"), "model") {
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
  c.box(style=triple_liking, fn() {
    c.box(style=triple_models_column, fn() {
      triple_option(c, "triple/model/" + model, text(o, "name"), picked, trail~, tip=ids, fn() {
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
              c.box(style=triple_usual_room, fn() { c.text(usual, style=triple_usual) |> ignore })
              |> ignore
            })
            |> ignore
          }
          match text(field(o, "spent"), "text") {
            "" => ()
            sp => c.text(sp, style=triple_note) |> ignore
          }
        })
        |> ignore
      }, on_press=go)
    })
    |> ignore
    like_star()
  })
  |> ignore
}

///|
/// A configuration's row's key: its model, runtime, how hard it thinks, how fast and how much context, so two of one
/// model are two.
fn triple_combo_key(x : Json?) -> String {
  let fast = match field(x, "fast") {
    Some(True) => "fast"
    Some(False) => "standard"
    _ => ""
  }
  let context = match field(x, "context") {
    Some(Number(n, ..)) => n.to_int64().to_string()
    _ => ""
  }
  "triple/combo/" + text(x, "model") + "/" + text(x, "runtime") + "/" + text(x, "effort") + "/" + fast + "/" + context
}

///|
/// The key of the group the first level of `contents` draws its rows by (@sf.group_rows): its panel's own, never one
/// still closing as another opens.
fn triple_first_group(contents : TriplePanel) -> String {
  "triple/first/" + contents.serial.to_string()
}

///|
/// The configurations used most as the first level of `contents` draws them, of those the core says now (`now`), each
/// with how it comes or goes (its look; None, still) and whether it is leaving. One taken out stays where it was while
/// it leaves (@sf.leave), only drawn; the core's next of them comes in its place once it has gone, as what was over
/// it moves down into its room (as its room closes: @sf.group_rows), coming in after them (triple_combo_in) so as never to
/// be drawn over one still on its way. `keep`: what it draws is the core's (not a page's bones), kept for what follows.
fn triple_combos_drawn(c : @ui.Ctx, contents : TriplePanel, now : Array[Json], keep : Bool) -> Array[(Json, @ui.Look?, Bool)] {
  if !keep {
    return now.map(fn(x) { (x, None, false) })
  }
  let key_of = fn(x : Json) { triple_combo_key(Some(x)) }
  let now_of = fn(k : String) { now.search_by(fn(y) { key_of(y) == k }).map(fn(i) { now[i] }) }
  let was = match contents.combos_shown {
    Some(was) => was
    None => {
      // (those there as it opens: there, no motion)
      for x in now {
        contents.combos_seen[key_of(x)] = true
      }
      now
    }
  }
  // (each it showed that the core no longer says: leaving)
  for x in was {
    let k = key_of(x)
    if now_of(k) is None && !contents.combos_leaving.contains(k) {
      contents.combos_leaving[k] = x
    }
  }
  // (how each leaving goes; once gone, gone from what is shown)
  let gone_looks : Map[String, @ui.Look] = Map([])
  for k, _ in contents.combos_leaving.copy() {
    match @motion.presence(c, "triple/combo/in/" + k, false, exit=@sf.leave) {
      Some(l) => gone_looks[k] = l
      None => contents.combos_leaving.remove(k)
    }
  }
  // (none leaving: as the core says them, the next come in; else as shown, its rows as the core says them now)
  let shown = if contents.combos_leaving.is_empty() {
    now
  } else {
    was.filter_map(fn(x) {
      let k = key_of(x)
      match now_of(k) {
        Some(y) => Some(y)
        None => if contents.combos_leaving.contains(k) { Some(x) } else { None }
      }
    })
  }
  contents.combos_shown = Some(shown)
  shown.map(fn(x) {
    let k = key_of(x)
    match gone_looks.get(k) {
      Some(l) => (x, Some(l), true)
      None => {
        let new = !contents.combos_seen.contains(k)
        contents.combos_seen[k] = true
        (x, @motion.presence(c, "triple/combo/in/" + k, true, initial=new, enter=triple_combo_in), false)
      }
    }
  })
}

///|
/// How the next of the configurations used most comes into the room of one taken out: faded in as what was over that
/// one has come most of its way down into its room (a Move as long as the room is tall: @sf.group_rows), so never drawn
/// over it.
// kept across runs: a value (no field of it changes)
let triple_combo_in : @motion.Trans = @motion.trans(fade=0.0, spec=@motion.tween(@sf.enter_ms, ease=Out, delay=triple_combo_in_after))

///|
/// How long after one taken out has gone the next comes in (triple_combo_in).
let triple_combo_in_after : Double = 250.0

///|
/// A configuration used most (`x`, one of the pick's `combos`; `o` its model): its maker's mark, its model's name, how
/// it runs (the core's `text`) in a capsule after it, part of what the row is; drawn picked while it is exactly what
/// is drafted (`selected`). No star, a configuration is not starred: where a model's star is, what takes it out of
/// those used most (`pick.forget`, the user, 2026-11-10: 「常用模型应该是一种特定配置，并且可以删掉，跟模型没有关系」),
/// a press of its own beside the row, the panel open; taken out, the row leaves the panel at once (the user, 2026-11-13).
/// Pressed, the panel closes and all of it is
/// made what it runs on at once (`pick.save`): nothing sent where it already runs on it.
fn triple_combo_row(
  c : @ui.Ctx,
  src : Source,
  station : String,
  of : String,
  v : Json?,
  x : Json?,
  o : Json?,
  names_w : Double,
  saved : String,
  close : () -> Unit,
) -> Unit {
  let on = flag(x, "selected")
  let name = text(x, "name")
  let how = text(x, "text")
  let go = fn() {
    triple.open = ""
    close()
    if !on || flag(v, "changed") {
      let p : Map[String, Json] = { "model": Json::string(text(x, "model")) }
      for k in ["runtime", "effort", "fast", "context"] {
        p[k] = field(x, k).unwrap_or(Json::null())
      }
      pick_save(src, station, of, p, done=saved)
    }
  }
  // (what the row shows: its maker's mark, its name, how it runs)
  let body = fn() {
        @sf.maker_mark(c, text(field(o, "maker"), "id"), text(x, "runtime"), 14.0) |> ignore
        c.box(style=triple_name_column.then(@ui.style(w=Fixed(names_w))), fn() {
          c.box(style=triple_name_line, fn() {
            c.box(keep=true, fn() {
              c.text(name, style=if on { triple_row_picked } else { triple_row_name })
              |> ignore
            })
            |> ignore
            // (giving way to the name where the row is short: cut short, all of it where the name leaves no room;
            // its capsule's sides too, which would else stand over what is at the row's end: said_at_its_longest)
            if how != "" {
              c.box(style=triple_combo_room, fn() {
                c.box(style=triple_combo, fn() { c.text(how, style=triple_combo_words) |> ignore })
                |> ignore
              })
              |> ignore
            }
          })
          |> ignore
        })
        |> ignore
  }
  c.box(style=triple_liking, fn() {
    c.box(style=triple_models_column, fn() {
        triple_option(c, triple_combo_key(x), if how == "" { name } else { name + " · " + how }, on, body, on_press=go)
    })
    |> ignore
    // (beside it, where a model's star is: taken out of those used most)
    let t = @sf.theme()
    let p = pick_params(station, of)
    p["model"] = Json::string(text(x, "model"))
    for k in ["runtime", "effort", "fast", "context"] {
      p[k] = field(x, k).unwrap_or(Json::null())
    }
    @sf.icon_button(
      c,
      "close",
      key=triple_combo_key(x) + "/forget",
      round=true,
      ink=t.p.muted,
      label=@sf.t("web-main.model.forgetCombo", args=[("name", if how == "" { name } else { name + " · " + how })]),
      on_press=fn() {
        (src.call)("pick.forget", Json::object(p), fn(res) {
          match res {
            Ok(_) => ()
            Err(e) => toast_later(@sf.t("web-main.pick.failed", args=[("error", error_words(e))]))
          }
        })
      },
    )
  })
  |> ignore
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
    c.on_press(id, fn() {
      pick(value)
    })
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
  on_press? : () -> Unit,
) -> Unit {
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
      } else if @sf.in_small_panel() {
        // (its room kept beside what opened the panel, which is as wide as its rows; a sheet's rows are the sheet's
        // width, and the room goes to their words)
        c.box(style=triple_check_room, fn() {  }) |> ignore
      }
    })
    |> ignore
  })
  c.semantics(b, Button, id~, label~)
  @sf.tip(c, key + "/tip", id, tip)
  match on_press {
    Some(f) => c.on_press(id, f)
    None => ()
  }
}

///|
/// The explicit subset of accounts drafted (`None`: 全选, every eligible account; `Some([])`: 全不选, waiting for one
/// account to be tapped; `Some(ids)`: only those accounts).
fn triple_selected_accounts(draft : Json?) -> Array[String]? {
  match field(draft, "profiles") {
    Some(Array(xs)) => {
      let out : Array[String] = []
      for x in xs {
        if x is String(s) && s != "" && !out.contains(s) {
          out.push(s)
        }
      }
      return Some(out)
    }
    _ => ()
  }
  match text(draft, "profile") {
    "" => None
    id => Some([id])
  }
}

///|
/// The accounts (runPickerAccounts), in a panel of their own from who runs it: 全选 (tapping while all are checked
/// clears to 全不选 so tapping one account pins it directly; closing on 全不选 reverts to the saved selection), a quiet
/// rule, then each account on two crisp non-wrapping lines with 当前 at the active row's end.
fn triple_accounts_node(n : @view.View, src : Source, station : String, of : String, _close : () -> Unit) -> Unit {
  let v = fn() { src.topic("pick", pick_params(station, of)).get().value }
  let draft = fn() { field(v(), "draft") }
  let accounts = fn() { items(v(), "accounts") }
  let single_only = fn() { accounts().length() <= 1 }
  let all_on = fn() { triple_selected_accounts(draft()) is None }
  let none_on = fn() { triple_selected_accounts(draft()) is Some([]) }
  let repicking = "pick.repick/" + station + "/" + of
  n.show(fn() { text(v(), "dropped") != "" }, fn(w) {
    @sf.style_node(w, fn() { @sf.panel_words_in_node(w).then(triple_dropped_box) })
    @sf.words_node(w, fn() { text(v(), "dropped") }, fn() { triple_amber_sm }) |> ignore
  })
  @sf.choice_row_node(
    n,
    fn() { @sf.t("web-main.model.selectAll") },
    fn() { false },
    compact=true,
    disabled=single_only,
    lead=fn(l) {
      @sf.check_mark_node(l, all_on, mixed=fn() { !all_on() && !none_on() }, dimmed=single_only)
    },
    note=fn() { text(v(), "autoNote") },
    note_ink=fn() { if none_on() { @sf.theme().p.warn_ink } else { @sf.theme().p.muted } },
    trail?=if of.has_prefix("session:") {
      Some(fn(e) {
        e.show(fn() { text(v(), "repick") != "" }, fn(r) {
          r.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Middle))) |> ignore
          r.show(fn() { doing(repicking) }, fn(s) { @sf.spinner_node(s, size=14.0) |> ignore })
          @sf.panel_button_node(r, fn() { text(v(), "repick") }, fn() {
            if !doing(repicking) {
              let label = text(@signals.untracked(v), "repick")
              act(src, label, repicking, "pick.repick", Json::object(pick_params(station, of)), ok=fn(res) {
                match text(Some(res), "said") {
                  "" => ()
                  said => toast_later(said)
                }
              })
            }
          })
          |> ignore
        })
      })
    } else {
      None
    },
    press=fn() {
      if !@signals.untracked(single_only) {
        if @signals.untracked(all_on) {
          pick_draft(src, station, of, { "profiles": Json::array([]) })
        } else {
          pick_save(src, station, of, { "profiles": Json::null(), "profile": Json::null() })
        }
      }
    },
  )
  n.show(fn() { !accounts().is_empty() }, fn(d) {
    @sf.style_node(d, fn() { triple_accounts_rule })
    d.box(fn(l) { @sf.style_node(l, fn() { triple_rule_h }) }) |> ignore
  })
  n.each(accounts, fn(a) { text(Some(a), "id") }, fn(row, a) {
    let id = text(Some(a.untracked()), "id")
    let av = fn() { Some(a.get()) }
    let checked = fn() {
      match triple_selected_accounts(draft()) {
        None => true
        Some(sel) => sel.contains(id)
      }
    }
    @sf.choice_row_node(
      row,
      fn() { text(av(), "name") },
      fn() { false },
      compact=true,
      disabled=single_only,
      lead=fn(l) { @sf.check_mark_node(l, checked, dimmed=single_only) },
      note=fn() { text(field(av(), "quotaLine"), "text") },
      note_ink=fn() {
        match text(field(av(), "quotaLine"), "level") {
          "amber" => @sf.theme().p.warn_ink
          "red" => @sf.theme().p.red
          _ => @sf.theme().p.muted
        }
      },
      trail=fn(e) {
        e.show(fn() { flag(av(), "current") && accounts().length() > 1 }, fn(t) {
          @sf.words_node(t, fn() { @sf.t("web-main.model.current") }, fn() { triple_muted }) |> ignore
        })
      },
      press=fn() {
        if @signals.untracked(single_only) {
          return
        }
        let all_ids = @signals.untracked(accounts).map(fn(x) { text(Some(x), "id") }).filter(fn(x) { x != "" })
        let cur_ids = match triple_selected_accounts(@signals.untracked(draft)) {
          None => all_ids
          Some(xs) => xs
        }
        if cur_ids.contains(id) {
          let next = cur_ids.filter(fn(x) { x != id })
          if next.is_empty() {
            pick_draft(src, station, of, { "profiles": Json::array([]) })
          } else {
            pick_save(src, station, of, { "profiles": Json::array(next.map(fn(s) { Json::string(s) })) })
          }
        } else {
          let next = all_ids.filter(fn(x) { x == id || cur_ids.contains(x) })
          if next.length() >= all_ids.length() {
            pick_save(src, station, of, { "profiles": Json::null(), "profile": Json::null() })
          } else {
            pick_save(src, station, of, { "profiles": Json::array(next.map(fn(s) { Json::string(s) })) })
          }
        }
      },
    )
  })
}

///|
/// Borrowing the picked model's account from another station, asked first: what it does,
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
  wide_confirm(c, "borrow/" + me, open, text(borrow, "title"), lines, text(borrow, "action"), doing(dkey), flag(borrow, "allowed"), fn(
    yes,
  ) {
    if yes {
      act(src, text(borrow, "action"), dkey, "pick.borrow", Json::object(pick_params(station, of)), done=@sf.t("web-main.model.borrowed"), ok=fn(_) {
        triple.borrow_asking = ""
        triple_let_go(me)
      })
    } else {
      triple.borrow_asking = ""
      triple_let_go(me)
    }
  })
}

///|
/// Borrowing a model of another station's asked first (borrow_dialog's), put up by the presenters as its panel's 借用 is
/// pressed (open_triple_panel's `asks`), what it holds nodes: its title, its lines, 取消 and its action at its foot (a
/// ring before them while it borrows), closed once it has borrowed it.
fn borrow_ask(src : Source, station : String, of : String, borrow : Json?) -> Unit {
  let dkey = "pick.borrow/" + station + "/" + of
  let lines = items(borrow, "lines").map(fn(l) {
    match l {
      String(s) => s
      _ => ""
    }
  })
  let action = text(borrow, "action")
  let allowed = flag(borrow, "allowed")
  @sf.panel_nodes(
    text(borrow, "title"),
    from=Unanchored,
    w=confirm_w,
    fn(b, _) {
      for l in lines {
        @sf.words_node(b, fn() { l }, fn() { confirm_line }) |> ignore
      }
    },
    foot=fn(f, shut) {
      f.box(fn(r) {
        @sf.style_node(r, fn() { confirm_foot })
        @sf.button_node(r, fn() { @sf.t("common.cancel") }, shut, tone=Ghost) |> ignore
        r.show(fn() { doing(dkey) }, fn(s) { @sf.spinner_node(s, size=14.0) |> ignore })
        @sf.button_node(
          r,
          fn() { action },
          fn() {
            act(src, action, dkey, "pick.borrow", Json::object(pick_params(station, of)), done=@sf.t("web-main.model.borrowed"), ok=fn(_) {
              shut()
            })
          },
          tone=Primary,
          busy=fn() { doing(dkey) },
          disabled=fn() { !allowed },
        )
        |> ignore
      })
      |> ignore
    },
  )
}

///|
/// A dialog that asks before something is done (the web's Confirm, Dialog): its title, its lines, 取消 and `action`
/// (`danger`: in red). `said` told true as the action is pressed, false as 取消 is, or as Esc or a press outside closes
/// it.
fn wide_confirm(
  c : @ui.Ctx,
  key : String,
  open : Bool,
  title : String,
  lines : Array[String],
  action : String,
  busy : Bool,
  allowed : Bool,
  said : (Bool) -> Unit,
) -> Unit {
  let d = @sf.dialog(
    c,
    key,
    open,
    title,
    w=dmin(confirm_w, c.width - 32.0),
    close_label=@sf.t("common.close"),
    on_close=fn() { said(false) },
    fn() {
      for l in lines {
        c.text(l, style=confirm_line) |> ignore
      }
      c.box(style=confirm_foot, fn() {
        small_button(c, key + "/cancel", @sf.t("common.cancel"), false, true, on_press=fn() { said(false) })
        if busy {
          @sf.spinner(c, size=14.0) |> ignore
        }
        small_button(c, key + "/ok", action, true, allowed && !busy, on_press=fn() { said(true) })
      })
      |> ignore
    },
  )
  // (closed by Esc or a press outside: what the dialog says as it is built)
  if open && !d {
    said(false)
  }
}

///|
/// A small panel's small pill: 24 high, 10 in, its words in 12; `primary` dark with light
/// words, else quiet with the ground on hover; not pressed while `on` is false. `on_press` as it is pressed.
fn small_button(c : @ui.Ctx, key : String, words : String, primary : Bool, on : Bool, on_press? : () -> Unit) -> Unit {
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
  match on_press {
    Some(f) if on => c.on_press(id, f)
    _ => ()
  }
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
/// The order the control's line leaves its parts out in, short of room: who runs it by name
/// (in its part), who runs it, how hard it thinks and how fast, then the runtime.
let triple_drop_name : Int = 1

///|
let triple_drop_account : Int = 2

///|
let triple_drop_effort : Int = 3

///|
let triple_drop_runtime : Int = 4

///|
/// The triple as a row's value (28 high at its end, in its middle): a capsule, as the round controls beside it are, its
/// shape its height's wherever the row's corners are (a row's corner with it at its end 10 in would be 10 here, 8.4 in
/// a finger's taller row, its own 8 in neither).
// kept across runs: a value (no field of it changes)
let triple_style : @ui.Style = @ui.css("row h=S7 px=S2_5 gap=S1_5 align=ACenter radius=Full hovered{bg=Hover}")

///|
/// The room between a model control's parts (triple_style's gap=S1_5), as nodes: the row of them in the capsule.
let triple_gap : Double = 6.0

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
/// A column's rows, 1 apart.
// kept across runs: a value (no field of it changes)
let triple_rows : @ui.Style = @ui.css("w=Full gap=SPx")

///|
/// A configuration used most in the first level, coming or going by its own motion (triple_body's): as wide as the rows.
// kept across runs: a value (no field of it changes)
let triple_moving : @ui.Style = @ui.css("w=Full")

///|
/// The first level's rows (triple_body's), one after another, the room between them each one's own (triple_first_row).
// kept across runs: a value (no field of it changes)
let triple_first_rows : @ui.Style = @ui.css("w=Full")

///|
/// A row of the first level with the room under it (as far as triple_rows' rows are apart), its room opening and
/// closing with it (@sf.group_rows).
// kept across runs: a value (no field of it changes)
let triple_first_row : @ui.Style = @ui.css("w=Full pb=SPx")

///|
/// A row of the first level of a panel opened up from what opened it, with that room over it (triple_first_row).
// kept across runs: a value (no field of it changes)
let triple_first_row_up : @ui.Style = @ui.css("w=Full pt=SPx")

///|
/// A row's ground, concentric with its small panel as a menu's row is (panel_in): a capsule 34 high, a taller row (an
/// account with what is left of it under its name) the ladder's 18, not a capsule as round as half its height.
// kept across runs: a value (no field of it changes)
let triple_option_style : @ui.Style = @ui.css((
  #|row w=Full px=S2_5 py=S1 gap=S1_5 align=ACenter hovered{bg=Hover}
)).then(@ui.style(radius=@sf.panel_in))


///|
// kept across runs: a value (no field of it changes)
let triple_option_on : @ui.Style = @ui.css((
  #|row w=Full px=S2_5 py=S1 gap=S1_5 align=ACenter bg=Hover
)).then(@ui.style(radius=@sf.panel_in))

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
let triple_liking : @ui.Style = @ui.css("row w=Full gap=SPx align=ACenter")

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
/// Where the line between them starts, from how hard it thinks' start: in the middle of the 8 between them.
let triple_between_rule : Double = 4.5

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
/// How one of those used most runs, after its name: a capsule on the words' tint, its words the rows' own colour.
// kept across runs: a value (no field of it changes)
let triple_combo : @ui.Style = @ui.css("row h=S5 px=S2 align=ACenter radius=Full bg=Tint")

///|
// kept across runs: a value (no field of it changes)
let triple_combo_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false, w=Cut)

///|
/// A configuration's capsule's room: as its words', down to nothing, the capsule cut where the name leaves less.
// kept across runs: a value (no field of it changes)
let triple_combo_room : @ui.Style = triple_usual_room.then(@ui.css("min_w=S0 clip"))

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
let triple_who_room : @ui.Style = @ui.style(row=true, w=@sf.grow, align=ACenter, gap=S2)

///|
/// Who runs it, a capsule at the foot's start as tall as the foot's buttons (@sf.button_height), so standing in the
/// panel's foot corner where they stand in the other, concentric with it, as far from its foot as from its side.
fn triple_who() -> @ui.Style {
  triple_who_look.then(@ui.style(h=Fixed(@sf.button_height())))
}

///|
// kept across runs: a value (no field of it changes)
let triple_who_look : @ui.Style = @ui.css("row px=S3 gap=S1 align=ACenter radius=Full bg=Tint hovered{bg=TintStrong}")

///|
// kept across runs: a value (no field of it changes)
let triple_who_lead : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let triple_who_name : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let triple_who_amber : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=WarnInk, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let triple_who_red : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Danger, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let triple_dropped_box : @ui.Style = @ui.css("w=Full pb=S1_5")

///|
// kept across runs: a value (no field of it changes)
let small_primary : @ui.Style = @ui.css("h=S6 px=S2_5 align=ACenter justify=JCenter radius=Full bg=Primary")

///|
// kept across runs: a value (no field of it changes)
let small_primary_off : @ui.Style = @ui.css((
  #|h=S6 px=S2_5 align=ACenter justify=JCenter radius=Full bg=Primary opacity=O50
))

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
/// No maker asked for (TriplePanel's `kind`, a sheet's step's): no maker's id, the makers not known having the id "".
let triple_no_kind : String = "\u{1}"

///|
/// How many models all of them are listed at once up to; more, by their makers.
let triple_flat_most : Int = 12

///|
/// How many rows the models' room shows in a sheet at most: eight and a half, the half saying there is more.
let triple_sheet_rows : Double = 8.5

///|
/// Between those used most and the rest of a few, in their one list.
// kept across runs: a value (no field of it changes)
let triple_apart : @ui.Style = @ui.css("w=Full h=S2")

///|
/// What a sheet of it holds besides its models' room, about: its grab and title, its search, how hard it thinks, its
/// foot on two lines. The models' room is the sheet's most less this at most, so the sheet is never taller than its
/// most and the room is as tall as it says (one that gave way after it was laid out was brought to its foot for a
/// taller one, its last row cut off, 2026-11-10).
let triple_sheet_rest : Double = 350.0

///|
/// The models' room (as tall as what it holds, to its most: triple_body's `list_most`; beside what opened it, where
/// the models go by level, its most at every level: `level_h`).
// kept across runs: a value (no field of it changes)
let triple_room : @ui.Style = @ui.css("w=Full gap=SPx")

///|
/// How hard it thinks in a sheet, under the models: its name, and under it its stops across the sheet.
// kept across runs: a value (no field of it changes)
let triple_effort_block : @ui.Style = @ui.css("w=Full pt=S3 gap=S1_5")

///|
/// Its name, as far in as the rows' words.
// kept across runs: a value (no field of it changes)
let triple_effort_name : @ui.Style = @ui.css("px=S2_5")

///|
/// The accounts' sub-panel width on 中屏/大屏, wide enough for multi-window quota summaries on one line.
let triple_accounts_w : Double = 340.0

///|
// kept across runs: a value (no field of it changes)
let triple_accounts_rule : @ui.Style = @ui.css("w=Full py=S1")

///|
/// The most the panel is wide beside its control, as wide as its columns' words within it (the web's: the models' 200
/// to 300, the runtimes' and the efforts' columns).
let triple_panel_w : Double = 520.0

///|
/// The same where its models are many: their makers a column before a maker's models.
let triple_panel_w_many : Double = 660.0

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
