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
  let card = (src.topic)("agentCard", params).value
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
    if c.clicked(id) {
      open_work(src, params, id)
    }
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
/// All of it in a panel beside what opened it (`from`): its card's tasks and checklist as they are now.
fn open_work(src : Source, params : Map[String, Json], from : Int) -> Unit {
  @sf.panel("", fn(c, _) { agent_work(c, src, (src.topic)("agentCard", params).value) }, from=Of(from), w=work_panel_w, along=End)
}

///|
/// Its panel: as wide as an agent's card is (agent_card_w).
let work_panel_w : Double = 288.0

///|
/// What it has going in the background (后台进行中, how many) and its checklist as it wrote it last (清单, how much of
/// it is done), all of them, `card` its `agentCard` view, as a small panel's groups (the library's panel_group: each
/// under its small head, a line between them, menu_rule): a task a row, its kind's chip in a column of its own, what
/// it is cut at its end, for how long it has run at the row's end; the checklist drawn as a plan call is in its
/// history (plan_list), on the same line. In the panel its history's mark opens (work_mark). Nothing when it has
/// neither.
pub fn agent_work(c : @ui.Ctx, src : Source, card : Json?) -> Unit {
  let tasks = items(card, "tasks")
  let plan = items(card, "plan")
  if tasks.is_empty() && plan.is_empty() {
    return
  }
  let now = (src.now)()
  c.box(style=work_box, fn() {
    if tasks.length() > 0 {
      @sf.panel_group(
        c,
        fn() {
          for task in tasks {
            let tv = Some(task)
            let ran = now - number(tv, "since")
            each_second(c, ran)
            c.box(style=@sf.panel_words_in().then(work_task), fn() {
              c.box(style=work_kind_column, fn() {
                c.box(style=work_kind_chip, fn() { c.text(text(tv, "kindText"), style=work_kind) |> ignore }) |> ignore
              })
              |> ignore
              c.text(text(tv, "text"), style=work_task_words) |> ignore
              c.text(elapsed(ran), style=work_elapsed) |> ignore
            })
            |> ignore
          }
        },
        label=tasks.length().to_string(),
        lead=fn(c) { c.text(@sf.t("web-main.chat.agentCard.background"), style=work_head_words) |> ignore },
      )
    }
    if tasks.length() > 0 && plan.length() > 0 {
      @sf.menu_rule(c)
    }
    if plan.length() > 0 {
      @sf.panel_group(
        c,
        fn() { c.box(style=@sf.panel_words_in().then(work_plan), fn() { plan_list(c, plan) }) |> ignore },
        label=text(card, "planText"),
        lead=fn(c) { c.text(@sf.t("web-main.chat.agentCard.plan"), style=work_head_words) |> ignore },
      )
    }
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
// kept across runs: a value (no field of it changes)
let work_kind_column : @ui.Style = @ui.css("w=S12 row align=ACenter")

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
