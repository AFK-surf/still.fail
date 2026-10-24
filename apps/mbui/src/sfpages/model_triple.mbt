// The one way a model is chosen in the wide frame (ember web/src/ModelTriple.tsx, ModelTriple.css.ts): a control that
// says the model, the runtime (where it can still change and the model runs on more than one), how hard it thinks and
// who runs it, in one line; pressed, a panel under it: the models by series (a filter over them when there are many),
// the runtimes, the efforts and the speed, side by side; at its foot who runs it (a panel of the accounts beside it),
// 取消 and 确定. Picks there are the core's draft (`pick.set`) until 确定 (`pick.save`); a model another station has is
// borrowed first, asked in a dialog.


///|
/// What the control keeps of its own (the pick is the core's): the one whose panel is open (its station and pick, ""
/// none), its accounts' panel beside it, its filter's field and words; the borrowing it asks to confirm ("" none).
priv struct Triple {
  mut open : String
  mut accounts : Bool
  field : @ui.Field
  mut query : String
  mut borrow_asking : String
}

///|
let triple : Triple = { open: "", accounts: false, field: @ui.Field::new(), query: "", borrow_asking: "" }

///|
fn triple_reset() -> Unit {
  triple.open = ""
  triple.accounts = false
  triple.field.set("")
  triple.query = ""
  triple.borrow_asking = ""
}

///|
/// What is left of a row after its words (a check at its end).
// kept across runs: a value (no field of it changes)
let triple_grow : @ui.Style = @ui.style(w=@sf.grow)

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
/// The control of the pick `of` on `station` (ModelTriple): its line, and its panel under it while open (above it with
/// `up`). `page`: the control as a page has it with itself (a new chat's: its `pick`), not read on its own; `small`: in
/// a composer's row (ModelTriple.css.ts in newChat: 28 high, its words 12). `saved`: what is said once 确定 kept it
/// (onConfirm's toast: a connect's, its model bound).
pub fn model_triple(
  c : @ui.Ctx,
  src : Source,
  station : String,
  of : String,
  up? : Bool = false,
  page? : Json? = None,
  small? : Bool = false,
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
  if can {
    c.cursor(id, Hand)
  }
  let open = triple.open == me
  if can && c.clicked(id) {
    if open {
      triple.open = ""
    } else {
      triple.open = me
      triple.accounts = false
      triple.field.set("")
      triple.query = ""
      pick_draft(src, station, of, { "open": Json::boolean(true) })
    }
  }
  let runtime = text(value, "runtime")
  let (words, muted) = if small { (triple_words_xs, triple_muted_xs) } else { (triple_words, triple_muted) }
  c.box(
    style=match (open, small) {
      (true, false) => triple_on
      (false, false) => triple_style
      (true, true) => triple_small_on
      (false, true) => triple_small
    },
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
      // runs it by name, then who runs it, then the runtime, then how hard it thinks; the model never)
      c.text(name, style=words) |> ignore
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
            @settings.quota_chips(c, field(profile, "quota"), small=true)
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
  let pop = @kit.popover(
    c,
    "triple-pop/" + me,
    open,
    id,
    side=if up { Top } else { Bottom },
    along=Start,
    look=fn(c, _, body) { @sf.small_panel(c, body) |> ignore },
    fn() { triple_panel(c, src, station, of, v, saved) },
  )
  if open && !pop.value {
    triple.open = ""
  }
  triple_accounts_pop(c, src, station, of, v, open)
  borrow_dialog(c, src, station, of, v)
}

///|
/// The panel: the filter across its top (more than 8 models), the columns side by side under it with a line between,
/// what borrowing would do, the foot.
fn triple_panel(c : @ui.Ctx, src : Source, station : String, of : String, v : Json?, saved : String) -> Unit {
  let t = @sf.theme()
  let options = items(v, "options")
  let draft = field(v, "draft")
  let picked = text(v, "option")
  let words = triple.query.trim(chars=" ").to_string().to_lower()
  if options.length() > 8 {
    c.box(style=triple_search, fn() {
      @sf.icon(c, "search", size=14.0, color=t.p.subtle) |> ignore
      let res = c.editor(
        "triple/filter",
        placeholder=@sf.t("web-main.model.search"),
        font_size=13.0,
        line=20.0,
        max_lines=1,
        plain=true,
        color=t.p.text,
        placeholder_color=t.p.subtle,
        caret_color=t.p.accent,
        field=triple.field,
      )
      triple.query = res.text
    })
    |> ignore
    c.box(style=triple_rule_h, fn() {  }) |> ignore
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
  c.box(style=triple_columns, fn() {
    // the models: only their column scrolls (360 high at most), a row each for a series' name and for a model
    let rows : Array[() -> Unit] = []
    if options.length() <= 8 {
      rows.push(fn() { triple_column_head(c, @sf.t("web-main.model.models")) })
    }
    for s in series {
      if series.length() > 1 {
        let who = s.0
        rows.push(fn() { triple_column_head(c, who) })
      }
      for o in s.1 {
        let o = Some(o)
        rows.push(fn() { triple_model_row(c, src, station, of, v, o) })
      }
    }
    if listed.length() == 0 {
      rows.push(fn() {
        c.box(style=triple_empty, fn() { c.text(@sf.t("web-main.model.noMatch"), style=triple_muted) |> ignore })
        |> ignore
      })
    }
    let tall = dmin(triple_list_h, rows.length().to_double() * triple_row_h)
    c.box(style=@ui.style(w=Fixed(triple_models_w), h=Fixed(tall)), fn() {
      c.list("triple/models", rows.length(), triple_row_h, fn(i) { (rows[i])() }) |> ignore
    })
    |> ignore
    if runtimes.length() > 0 {
      c.box(style=triple_rule_v, fn() {  }) |> ignore
      c.box(style=triple_column, fn() {
        triple_column_head(c, @sf.t("web-main.model.runtime"))
        for r in runtimes {
          if r is String(r) {
            let on = text(draft, "runtime") == r
            if triple_option(c, "triple/runtime/" + r, @settings.runtime_label(r), on, fn() {
                @sf.maker_mark(c, "", r, 14.0) |> ignore
                c.text(@settings.runtime_label(r), style=if on { triple_picked } else { triple_words }) |> ignore
              }) {
              pick_draft(src, station, of, { "runtime": Json::string(r) })
            }
          }
        }
      })
      |> ignore
    }
    if efforts.length() > 0 || fast {
      c.box(style=triple_rule_v, fn() {  }) |> ignore
      c.box(style=triple_efforts, fn() {
        if efforts.length() > 0 {
          triple_column_head(c, @sf.t("web-main.model.effort"))
          let now = text(draft, "effort")
          let all : Array[String] = [""]
          for e in efforts {
            if e is String(e) {
              all.push(e)
            }
          }
          for e in all {
            let on = now == e
            let words = if e == "" { @sf.t("web-main.model.default") } else { effort_text(e) }
            if triple_option(c, "triple/effort/" + e, words, on, fn() {
                c.text(words, style=if on { triple_picked } else { triple_words }) |> ignore
              }) {
              pick_draft(src, station, of, { "effort": if e == "" { Json::null() } else { Json::string(e) } })
            }
          }
        }
        if fast {
          triple_column_head(c, @sf.t("web-main.model.speed"))
          let now = match field(draft, "fast") {
            Some(True) => "fast"
            Some(False) => "standard"
            _ => ""
          }
          for f in ["", "standard", "fast"] {
            let on = now == f
            let words = match f {
              "" => @sf.t("web-main.model.fastSubscription")
              "fast" => "Fast"
              _ => @sf.t("web-main.model.standard")
            }
            if triple_option(c, "triple/fast/" + f, words, on, fn() {
                c.text(words, style=if on { triple_picked } else { triple_words }) |> ignore
              }) {
              let fv : Json = match f {
                "" => Json::null()
                "fast" => Json::boolean(true)
                _ => Json::boolean(false)
              }
              pick_draft(src, station, of, { "fast": fv })
            }
          }
        }
      })
      |> ignore
    }
  })
  |> ignore
  // the model picked is another station's: said over the foot, which borrows it rather than confirming
  let borrow = field(v, "borrow")
  if borrow is Some(Object(_)) {
    c.box(style=triple_borrow, fn() {
      c.text(if flag(borrow, "allowed") { text(borrow, "note") } else { text(borrow, "why") }, style=triple_note)
      |> ignore
    })
    |> ignore
  }
  c.box(style=triple_rule_h, fn() {  }) |> ignore
  c.box(style=triple_foot.then(@sf.panel_foot_ends), fn() {
    // who runs it: the accounts in a panel beside this one
    let who = c.id("triple/who")
    c.cursor(who, Hand)
    if c.clicked(who) {
      triple.accounts = !triple.accounts
    }
    c.box(style=triple_who_room, fn() {
      c.box(style=if triple.accounts { triple_who_on } else { triple_who }, id=who, fn() {
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
    if small_button(c, "triple/cancel", @sf.t("common.cancel"), false, true) {
      triple.open = ""
    }
    if borrow is Some(Object(_)) {
      if small_button(c, "triple/borrow", text(borrow, "action"), true, flag(borrow, "allowed")) {
        triple.open = ""
        triple.borrow_asking = station + "\u{1}" + of
      }
    } else if small_button(c, "triple/confirm", @sf.t("common.confirm"), true, picked != "" && flag(v, "changed")) {
      triple.open = ""
      act(
        src,
        @sf.t("common.confirm"),
        "pick.save/" + station + "/" + of,
        "pick.save",
        Json::object(pick_params(station, of)),
        done=if saved == "" { @sf.t("web-pages.chat.pickSaved") } else { saved },
      )
    }
  })
  |> ignore
}

///|
/// A model's row: its maker's mark, its name (what it has spent under it), the station it comes from.
fn triple_model_row(c : @ui.Ctx, src : Source, station : String, of : String, v : Json?, o : Json?) -> Unit {
  let t = @sf.theme()
  let model = text(o, "model")
  let picked = text(v, "option") == model
  let runs = match items(o, "runtimes").get(0) {
    Some(String(r)) => r
    _ => text(field(v, "value"), "runtime")
  }
  if triple_option(c, "triple/model/" + model, text(o, "name"), picked, fn() {
      @sf.maker_mark(c, text(field(o, "maker"), "id"), runs, 14.0) |> ignore
      c.box(style=triple_option_text, fn() {
        c.text(text(o, "name"), style=if picked { triple_picked } else { triple_words }) |> ignore
        match text(field(o, "spent"), "text") {
          "" => ()
          sp => c.text(sp, style=triple_note) |> ignore
        }
      })
      |> ignore
      match field(o, "fromStation") {
        Some(Object(_)) as fs =>
          if text(fs, "icon") != "" || text(fs, "emoji") != "" {
            @sf.station_mark(c, text(fs, "emoji"), text(fs, "icon"), 14.0, t.p.muted)
          } else {
            c.text(text(fs, "name"), style=triple_note) |> ignore
          }
        _ => ()
      }
    }) {
    pick_draft(src, station, of, { "model": Json::string(model) })
  }
}

///|
/// A column's head (runPicker h4): 4 over it, 6 under, as far in as the rows' words.
fn triple_column_head(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=triple_head_box, fn() { c.text(words, style=triple_head) |> ignore }) |> ignore
}

///|
/// A row of a column (runPickerOption): 30 high at least, 4 by 10 in, its ground under the pointer and while picked,
/// a check at its end while picked. True on the frame after a press.
fn triple_option(c : @ui.Ctx, key : String, label : String, on : Bool, body : () -> Unit) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.cursor(id, Hand)
  let b = c.box(style=if on { triple_option_on } else { triple_option_style }, id~, fn() {
    body()
    c.box(style=triple_grow, fn() {  }) |> ignore
    if on {
      @sf.icon(c, "check", size=14.0, color=t.p.accent) |> ignore
    }
  })
  c.semantics(b, Button, id~, label~)
  c.clicked(id)
}

///|
/// The accounts (runPickerAccounts): a panel beside the control's, its foot on that one's foot: 自动 with what the
/// station's pick is on now, then each account with what is left of it.
fn triple_accounts_pop(c : @ui.Ctx, src : Source, station : String, of : String, v : Json?, open : Bool) -> Unit {
  let draft = field(v, "draft")
  let pop = @kit.popover(
    c,
    "triple-accounts/" + station + "/" + of,
    open && triple.accounts,
    c.id("triple/who"),
    side=Right,
    along=End,
    offset=14.0,
    look=fn(c, _, body) { @sf.small_panel(c, body) |> ignore },
    fn() {
      c.box(style=triple_accounts, fn() {
        triple_column_head(c, @sf.t("web-main.model.account"))
        match text(v, "dropped") {
          "" => ()
          d => c.text(d, style=triple_amber_sm) |> ignore
        }
        let mine = text(draft, "profile")
        if triple_option(c, "triple/account/", @sf.t("web-main.model.auto"), mine == "", fn() {
            c.box(style=triple_option_text, fn() {
              c.text(@sf.t("web-main.model.auto"), style=if mine == "" { triple_picked } else { triple_words }) |> ignore
              c.text(text(v, "autoNote"), style=triple_note) |> ignore
            })
            |> ignore
          }) {
          pick_draft(src, station, of, { "profile": Json::null() })
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
          }
        }
      })
      |> ignore
    },
  )
  if open && triple.accounts && !pop.value {
    triple.accounts = false
  }
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
  if on {
    c.cursor(id, Hand)
  }
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
// kept across runs: a value (no field of it changes)
let triple_style : @ui.Style = @ui.css("row h=S7 px=S2_5 gap=S1_5 align=ACenter radius=Lg clip hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let triple_on : @ui.Style = @ui.css("row h=S7 px=S2_5 gap=S1_5 align=ACenter radius=Lg clip bg=Hover")

///|
// kept across runs: a value (no field of it changes)
let triple_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let triple_picked : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let triple_muted : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let triple_amber : @ui.TextStyle = @ui.text_style(size=Sm, color=Warn, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let triple_red : @ui.TextStyle = @ui.text_style(size=Sm, color=Danger, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let triple_amber_sm : @ui.TextStyle = @ui.text_style(size=Xs, color=Warn)

///|
// kept across runs: a value (no field of it changes)
let triple_red_sm : @ui.TextStyle = @ui.text_style(size=Xs, color=Danger)

///|
// kept across runs: a value (no field of it changes)
let triple_note : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// A column's head (runPicker h4): 12, muted, medium; 4 over it, 6 under, as far in as the rows' words.
// kept across runs: a value (no field of it changes)
let triple_head : @ui.TextStyle = @ui.text_style(size=Xs, weight=Medium, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let triple_search : @ui.Style = @ui.css("row w=Full px=S2_5 py=S2_5 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
pub let triple_rule_h : @ui.Style = @ui.css("w=Full h=SPx bg=Line")

///|
// kept across runs: a value (no field of it changes)
let triple_rule_v : @ui.Style = @ui.css("w=SPx h=Full bg=Line")

///|
// kept across runs: a value (no field of it changes)
let triple_columns : @ui.Style = @ui.css("row max_h=S80 gap=S1")

///|
// kept across runs: a value (no field of it changes)
let triple_column : @ui.Style = @ui.css("min_w=S28 gap=SPx")

///|
// kept across runs: a value (no field of it changes)
// kept across runs: a value (no field of it changes)
let triple_efforts : @ui.Style = @ui.css("min_w=S32 gap=SPx")

///|
// kept across runs: a value (no field of it changes)
let triple_option_style : @ui.Style = @ui.css(
  #|row w=Full min_h=S7 px=S2_5 py=S1 gap=S1_5 align=ACenter radius=Xl hovered{bg=Hover}
)

///|
// kept across runs: a value (no field of it changes)
let triple_option_on : @ui.Style = @ui.css(
  #|row w=Full min_h=S7 px=S2_5 py=S1 gap=S1_5 align=ACenter radius=Xl bg=Hover
)

///|
// kept across runs: a value (no field of it changes)
let triple_option_text : @ui.Style = @ui.css("gap=SPx")

///|
// kept across runs: a value (no field of it changes)
let triple_empty : @ui.Style = @ui.css("px=S2_5 py=S2")

///|
// kept across runs: a value (no field of it changes)
let triple_borrow : @ui.Style = @ui.css("w=Full px=S2_5 py=S1_5")

///|
// kept across runs: a value (no field of it changes)
let triple_foot : @ui.Style = @ui.css("row w=Full pt=S1_5 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let triple_who_room : @ui.Style = @ui.style(row=true, w=@sf.grow, clip=true)

///|
// kept across runs: a value (no field of it changes)
let triple_who : @ui.Style = @ui.css("row h=S6 px=S2_5 gap=S1 align=ACenter radius=Full hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let triple_who_on : @ui.Style = @ui.css("row h=S6 px=S2_5 gap=S1 align=ACenter radius=Full bg=Hover")

///|
// kept across runs: a value (no field of it changes)
let triple_who_lead : @ui.TextStyle = @ui.text_style(size=Xs, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let triple_who_name : @ui.TextStyle = @ui.text_style(size=Xs, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let triple_accounts : @ui.Style = @ui.css("min_w=S56 max_w=S80 gap=SPx")

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
let small_primary_words : @ui.TextStyle = @ui.text_style(size=Xs, weight=Medium, color=OnPrimary, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let small_quiet_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let confirm_line : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let confirm_foot : @ui.Style = @ui.css("row w=Full pt=S3 gap=S2 align=ACenter justify=JEnd")

///|
/// The models' column: 360 high at most (runPicker), a row about 31 (30 at least, 1 apart), 200 wide.
let triple_list_h : Double = 360.0

///|
let triple_row_h : Double = 31.0

///|
let triple_models_w : Double = 200.0

///|
// kept across runs: a value (no field of it changes)
let triple_head_box : @ui.Style = @ui.css("px=S2_5 pt=S1 pb=S1_5")

///|
/// In a composer's row (newChat's): 28 high, 8 in, its words 12.
// kept across runs: a value (no field of it changes)
let triple_small : @ui.Style = @ui.css("row h=S7 px=S2 gap=S1_5 align=ACenter radius=Lg clip hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let triple_small_on : @ui.Style = @ui.css("row h=S7 px=S2 gap=S1_5 align=ACenter radius=Lg clip bg=Hover")

///|
// kept across runs: a value (no field of it changes)
pub let triple_words_xs : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
pub let triple_muted_xs : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// The control of the pick `of` on `station` with its panel open (a screen's fixture).
pub fn open_triple(station : String, of : String) -> Unit {
  triple.open = station + "\u{1}" + of
}
