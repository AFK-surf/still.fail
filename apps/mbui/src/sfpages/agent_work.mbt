// What an agent has going in the background past its turns, and its checklist (AgentCard.tsx WorkLine, WorkFold,
// AgentWork, WorkMark), as the core's `agentCard` view says them (views/brief.ts workOf): one line in its card (to its
// execution history), and a mark at the start of its history's tools that opens all of it in a panel.

///|
/// What it has going in the background past its turns and its checklist in one line (the core's `workLine`: 后台 4 ·
/// 清单 2/6：<the item under way>), `card` its `agentCard` view, cut at its end, never wrapped: pressed by `id`, in the
/// text's colour under the pointer; `inset` in from its start as its card's latest lines are. Nothing when it has
/// neither.
pub fn agent_work_line(c : @ui.Ctx, card : Json?, id : Int, inset? : Bool = false) -> Unit {
  let words = text(card, "workLine")
  if words == "" {
    return
  }
  let hot = c.lit(id)
  let b = c.box(style=if inset { work_line_inset } else { work_line }, id~, fn() {
    c.text(words, style=if hot { work_line_hot } else { work_line_words }) |> ignore
  })
  c.semantics(b, Button, id~, label=words)
}

///|
/// The mark of agent `key`'s work past its turns (on `station`), at the end of its execution history's details' line
/// of its turns (8 轮 · 共干了 1 小时 12 分 · 后台 4 · 2/6), in its words (`words`), after `lead` (its separator, 「 · 」),
/// what can be pressed in `hot` (a link's ink) under the pointer. It gives way first, a step at a time, before the line's own words
/// are cut (Ctx::text `keep` on them): 后台 4 · 2/6 (the core's `workMark`), then its counts alone (`workMarkShort`:
/// 4 · 2/6), then a mark with how many (`workMarkCount`: 4, or the checklist's 2/6), then nothing. Its words said a
/// shorter way (Ctx::text `shorter`), and each form a part its row leaves out (Ctx::box `drop`), the one with the mark
/// drawn only while the words are left out (while something runs in the background, at work's spokes before what it
/// says: work_spokes); `smallest`, that one alone, where its row is laid out without asking what it
/// left out (a phone's details, a list's row: Ctx::left_out reads nothing there). Pressed, whichever is shown, all of
/// it in a panel under it (from the foot on Small: the presenters'). Nothing when it has neither.
pub fn work_mark(
  c : @ui.Ctx,
  src : Source,
  station : String,
  key : String,
  words : @ui.TextStyle,
  hot : @ui.TextStyle,
  lead? : String = "",
  smallest? : Bool = false,
) -> Unit {
  let params : Map[String, Json] = { "station": Json::string(station), "key": Json::string(key) }
  let card = src.topic("agentCard", params).get().value
  let mark = text(card, "workMark")
  if mark == "" {
    return
  }
  let label = match text(card, "workLine") {
    "" => mark
    line => line
  }
  let (whole, least) = (c.id("history/work-mark"), c.id("history/work-mark/least"))
  for id in [whole, least] {
    c.on_press(id, fn() {
      open_work(src, params, Of(id))
    })
  }
  let counts = text(card, "workMarkShort")
  let count = text(card, "workMarkCount")
  let running = items(card, "tasks").length() > 0
  // (each form its separator and what is pressed, a part its row leaves out whole: the separator goes with it)
  let form = fn(id : Int, body : () -> Unit) {
    c.box(style=work_mark_form, drop=work_mark_drop, fn() {
      if lead != "" {
        c.text(lead, style=words) |> ignore
      }
      let b = c.box(style=work_mark_press, id~, body)
      c.semantics(b, Button, id~, label~)
    })
    |> ignore
  }
  // (its forms a row of their own, which its row leaves out of as it would its own parts; words said a shorter way
  // need no more than the shortest)
  c.box(style=work_mark_row, fn() {
    if count != "" && (smallest || c.left_out(whole)) {
      form(least, fn() {
        if running {
          work_spokes(c)
        } else {
          @sf.icon(c, "wait", size=12.0, color=if c.lit(least) { @sf.theme().p.accent } else { @sf.theme().p.muted }) |> ignore
        }
        c.text(count, style=if c.lit(least) { hot } else { words }) |> ignore
      })
    }
    if smallest && count != "" {
      return
    }
    form(whole, fn() {
      if running {
        work_spokes(c)
      }
      c.text(mark, style=if c.lit(whole) { hot } else { words }, shorter=if counts != "" && counts != mark {
        [counts]
      } else {
        []
      })
      |> ignore
    })
  })
  |> ignore
}

///|
/// What runs in the background, at work: the spokes every mark of work at work has (@sf.spokes: the chats' marks, an
/// agent's badge), 10 in a 12 room, on a line of 12. They step on the resident clock, a frame a step (10 a second,
/// each of the looks alone: nothing built, laid out or painted for them), and stand still while motion is reduced.
fn work_spokes(c : @ui.Ctx) -> Unit {
  @sf.spokes(c, 10.0, @sf.mark_yellow, box=12.0) |> ignore
}

///|
/// How readily its mark leaves its row (Ctx::box `drop`): the first of what may.
let work_mark_drop : Int = 1

///|
/// Its forms' row: as wide as the one it shows.
// kept across runs: a value (no field of it changes)
let work_mark_row : @ui.Style = @ui.css("row align=ACenter")

///|
/// A form: its separator, then what is pressed (its mark 4 before how many).
// kept across runs: a value (no field of it changes)
let work_mark_form : @ui.Style = @ui.css("row align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let work_mark_press : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
/// All of it in a panel beside what opened it (`from`): its card's tasks and checklist as they are now
/// (agent_work_node).
fn open_work(src : Source, params : Map[String, Json], from : @sf.Anchor) -> Unit {
  @sf.panel_nodes("", fn(v, close) { agent_work_node(v, src, params, close) }, from~, w=work_panel_w, along=End)
}

///|
/// Its panel: as wide as an agent's card is (agent_card_w).
let work_panel_w : Double = 288.0

///|
/// Whether agent card `card` says something in the background or a checklist.
fn work_has(card : Json?) -> Bool {
  items(card, "tasks").length() > 0 || items(card, "plan").length() > 0
}

///|
/// What it has going in the background (后台进行中, how many) and its checklist as it wrote it last (清单, how much of
/// it is done), all of them, as the agent's `agentCard` view (`params`) says them now, made once in node `v` (its
/// panel's body) as a small panel's groups (the library's panel_group_node: each under its small head, a line between
/// them, panel_rule_node): a task a row by its id, its kind's chip in a column of its own (as wide as the chip where the
/// words are larger than it holds), what it is cut at its end, for how long it has run at the row's end, a second at a
/// time; the checklist drawn as a plan call is in its history (plan_node), on the same line. A task or an item of the
/// checklist comes and goes as the card lists it; a group as it has any. The card read while the panel is up and let go
/// with it. Nothing while there is no card or it has said neither yet; once it had either and says neither any more, the
/// panel closes (`close`, as that is said), showing what it showed last till it is gone. In the panel its history's mark opens
/// (work_mark_node).
fn agent_work_node(v : @view.View, src : Source, params : Map[String, Json], close : () -> Unit) -> Unit {
  let src = src.owned_by(v)
  let now = fn() { src.topic("agentCard", params).get().value }
  // (none left: the panel closes, what it showed last kept as it goes, not closed group by group under it; while the
  // core has said no card (not yet, or none any more), nothing, as ever)
  let last : Ref[Json?] = Ref(None)
  let card = fn() {
    let now = now()
    match now {
      Some(_) if !work_has(now) && last.val is Some(_) => last.val
      _ => {
        if work_has(now) {
          last.val = now
        }
        now
      }
    }
  }
  // (closed as a card that had either comes to have neither: said once, as it does)
  let had = Ref(false)
  v.reacts(fn() {
    match now() {
      None => 0
      Some(_) as c if work_has(c) => 1
      Some(_) => 2
    }
  }, fn(says) {
    if says == 1 {
      had.val = true
    } else if says == 2 && had.val {
      close()
    }
  })
  let tasks = fn() { items(card(), "tasks") }
  let plan = fn() { items(card(), "plan") }
  v.show(fn() { work_has(card()) }, fn(b) {
    @sf.style_node(b, fn() { work_box })
    b.show(fn() { tasks().length() > 0 }, fn(g) {
      @sf.panel_group_node(
        g,
        fn() { tasks().length().to_string() },
        fn(rows) { rows.each(tasks, fn(t) { text(Some(t), "id") }, fn(row, task) { work_task_node(row, src, task) }) },
        lead=fn(l) { @sf.words_node(l, fn() { @sf.t("web-main.chat.agentCard.background") }, fn() { work_head_words }) |> ignore },
      )
    })
    b.show(fn() { tasks().length() > 0 && plan().length() > 0 }, fn(r) { @sf.panel_rule_node(r) })
    b.show(fn() { plan().length() > 0 }, fn(g) {
      @sf.panel_group_node(
        g,
        fn() { text(card(), "planText") },
        fn(p) {
          p.box(fn(l) {
            @sf.style_node(l, fn() { @sf.panel_words_in_node(l).then(work_plan) })
            plan_node(l, plan)
          })
          |> ignore
        },
        lead=fn(l) { @sf.words_node(l, fn() { @sf.t("web-main.chat.agentCard.plan") }, fn() { work_head_words }) |> ignore },
      )
    })
  })
}

///|
/// A task of the background's in `row` (each's: a box of no padding of its own, so its way in and out is all of it),
/// as `task` says it now: its kind's chip, what it is, for how long it has run, read again each whole second.
fn work_task_node(row : @view.View, src : Source, task : @signals.Signal[Json]) -> Unit {
  let tv = fn() { Some(task.get()) }
  row.box(fn(r) {
    @sf.style_node(r, fn() { @sf.panel_words_in_node(r).then(work_task) })
    let tick = steps_seconds(r, src, @signals.untracked(fn() { number(tv(), "since") }))
    r.box(fn(k) {
      @sf.style_node(k, fn() { work_kind_column }, in_row=true)
      k.shrink(Is(0.0)) |> ignore
      k.box(fn(chip) {
        @sf.style_node(chip, fn() { work_kind_chip }, in_row=true)
        @sf.words_node(chip, fn() { text(tv(), "kindText") }, fn() { work_kind }) |> ignore
      })
      |> ignore
    })
    |> ignore
    @sf.words_node(r, fn() { text(tv(), "text") }, fn() { work_task_words })
    .grow(Is(1.0))
    .shrink(Is(1.0))
    .min_width(Is(Some(0.0)))
    |> ignore
    @sf.words_node(r, fn() {
      tick() |> ignore
      elapsed((src.now)() - number(tv(), "since"))
    }, fn() { work_elapsed })
    .shrink(Is(0.0))
    |> ignore
  })
  |> ignore
}

///|
/// What it holds: as far under the panel's top and over its foot as a menu's first and last rows' words are.
// kept across runs: a value (no field of it changes)
let work_box : @ui.Style = @ui.css("w=Full pb=S1_5")

///|
/// Its heads: 12, medium, muted (what follows them, how many, the library's group label: 12, muted).
// kept across runs: a value (no field of it changes)
let work_head_words : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Muted, wrap=false)

///|
/// A task a row, 28 high: its kind's chip (its column 48, the chips' start on the words' line), what it is (the room
/// left, cut at its end), for how long at its end; 8 apart.
// kept across runs: a value (no field of it changes)
let work_task : @ui.Style = @ui.css("row w=Full h=S7 gap=S2 align=ACenter")

///|
/// Its kind's column: 48, or as wide as its chip where the words are larger than that holds (never the chip cut).
// kept across runs: a value (no field of it changes)
let work_kind_column : @ui.Style = @ui.css("min_w=S12 row align=ACenter")

///|
/// Its kind: on the hover ground, round, 6 in.
// kept across runs: a value (no field of it changes)
let work_kind_chip : @ui.Style = @ui.css("px=S1_5 py=SPx radius=Full bg=Hover")

///|
// kept across runs: a value (no field of it changes)
let work_kind : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let work_task_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, w=@sf.grow, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let work_elapsed : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// The checklist on the tasks' line, 4 under its head.
// kept across runs: a value (no field of it changes)
let work_plan : @ui.Style = @ui.css("w=Full pt=S1")

///|
/// Its line: a row as wide as it is given, its words (12, muted; the text's under the pointer) cut at their end; in its
/// card 14 in, as its latest lines are.
// kept across runs: a value (no field of it changes)
let work_line : @ui.Style = @ui.css("row w=Full gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let work_line_inset : @ui.Style = @ui.css("row w=Full pl=S3_5 gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let work_line_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let work_line_hot : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false, w=Cut)

///|
/// work_mark as nodes in `parent`, a row that leaves it out (View::fits) before its own words are cut (they are kept
/// whole first: View::fit_whole), as agent `key`'s card on `station` says it now: 后台 4 · 2/6, said 4 · 2/6 where it
/// has not the room (View::shorter), then in place of it a mark with how many (there only while the whole is left out:
/// View::drops -1); `smallest`, that one alone. Pressed, all of it in a panel beside it. Nothing when it has neither.
pub fn work_mark_node(
  parent : @view.View,
  src : Source,
  station : String,
  key : String,
  words : @ui.TextStyle,
  hot : @ui.TextStyle,
  link? : @ui.TextStyle,
  lead? : String = "",
  smallest? : Bool = false,
) -> Unit {
  let params : Map[String, Json] = { "station": Json::string(station), "key": Json::string(key) }
  let card = fn() { src.topic("agentCard", params).get().value }
  let mark = fn() { text(card(), "workMark") }
  let count = fn() { text(card(), "workMarkCount") }
  let running = fn() { items(card(), "tasks").length() > 0 }
  let label = fn() {
    match text(card(), "workLine") {
      "" => mark()
      line => line
    }
  }
  let spokes = fn(x : @view.View) {
    x.show(running, fn(s) { @sf.spokes_node(s, 10.0, fn() { @sf.mark_yellow }, box=12.0) |> ignore })
  }
  // (each form its separator and what is pressed, left out of the row whole: the separator goes with it)
  let form = fn(r : @view.View, drop : Int, shown : () -> Bool, body : (@view.View) -> Unit) {
    r.show(shown, fn(f) {
      @sf.style_node(f, fn() { work_mark_form }, in_row=true)
      f.drops(Is(drop)).shrink(Is(0.0)) |> ignore
      if lead != "" {
        @sf.words_node(f, fn() { lead }, fn() { words }) |> ignore
      }
      f.box(fn(p) {
        @sf.style_node(p, fn() { work_mark_press }, in_row=true)
        @sf.presses_node(p, fn() { open_work(src, params, Node(p)) })
        p.says(By(fn() { Some(@view.said(Button, label=label())) })) |> ignore
        body(p)
      })
      |> ignore
    })
  }
  parent.show(fn() { mark() != "" }, fn(o) {
    // (its forms a row of their own that leaves them out as it would its own parts: work_mark's; the first in its
    // row to give way)
    o.row(Is(true)).fits(Is(true)).lines_up(Is(Some(Middle))).shrink(Is(work_mark_gives)).min_width(Is(Some(0.0))) |> ignore
    if smallest {
      let rest = link.unwrap_or(words)
      form(o, 0, fn() { count() != "" }, fn(p) {
        p.pick(running, fn(i, at_work) {
          if at_work {
            spokes(i)
          } else {
            @sf.icon_node(i, "wait", 12.0, By(fn() { if @sf.lit_node(p) { @sf.theme().p.accent } else if link is Some(_) { @sf.theme().p.blue } else { @sf.theme().p.muted } })) |> ignore
          }
        })
        @sf.words_node(p, count, fn() { if @sf.lit_node(p) { hot } else { rest } }) |> ignore
      })
      o.show(fn() { count() == "" }, fn(w) { work_mark_whole(w, form, spokes, mark, card, words, hot, link) })
      return
    }
    let rest = link.unwrap_or(words)
    work_mark_whole(o, form, spokes, mark, card, words, hot, link)
    form(o, -1, fn() { count() != "" }, fn(p) {
      p.pick(running, fn(i, at_work) {
        if at_work {
          spokes(i)
        } else {
          @sf.icon_node(i, "wait", 12.0, By(fn() { if @sf.lit_node(p) { @sf.theme().p.accent } else if link is Some(_) { @sf.theme().p.blue } else { @sf.theme().p.muted } })) |> ignore
        }
      })
      @sf.words_node(p, count, fn() { if @sf.lit_node(p) { hot } else { rest } }) |> ignore
    })
  })
}

///|
/// How much more readily work_mark_node's row gives way in its line than what is beside it (its line's own words).
let work_mark_gives : Double = 100.0

///|
/// work_mark_node's whole form: 后台 4 · 2/6, its counts alone where it has not the room; the first to leave its row.
fn work_mark_whole(
  o : @view.View,
  form : (@view.View, Int, () -> Bool, (@view.View) -> Unit) -> Unit,
  spokes : (@view.View) -> Unit,
  mark : () -> String,
  card : () -> Json?,
  words : @ui.TextStyle,
  hot : @ui.TextStyle,
  link : @ui.TextStyle?,
) -> Unit {
  let rest = link.unwrap_or(words)
  form(o, work_mark_drop, fn() { true }, fn(p) {
    spokes(p)
    @sf.words_node(p, mark, fn() { if @sf.lit_node(p) { hot } else { rest } })
    .shorter(By(fn() {
      let counts = text(card(), "workMarkShort")
      if counts != "" && counts != mark() {
        [counts]
      } else {
        []
      }
    }))
    |> ignore
  })
}
