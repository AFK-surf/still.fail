// What the core's answers do sets nothing moving (the owner, 2026-11-13: 「动效要有理由」「想办法根除」, recordings of a
// wide screen where switching a page's tab or a chat set panels folding block by block, a hover card drawn longer, a page
// sliding down whole; the coordinator of the migration: a way sets out only for a person's act, the core telling
// something new of what it had answered, or a moment said). On each screen of daily_paths_wbtest, over a core answering
// each call and every subscription 0, 16, 120, 250, 400 and 700 ms after it is asked (core_pace_wbtest's way of sweeping
// it; a subscription asked again answered late again, as a device's core does: round_trip_again), each step walked from
// where the one before left it: another chat opened and back, a picture opened, stepped and closed (its bytes a call,
// late too), each place of the shell one after another and back. A way that sets out after the step's own moment (what
// it set out at once is the act's) is a cell of `answers_still_known`, which only falls: a cell not in it fails, as
// does one in it that sets out none now (its line comes off). Each says which of two it is: `B`, a way set out only as
// an answer came late (none at 0 ms: the framework's to hold, an answer first come no cause), or `C`, the page's own
// (set out at 0 ms too: a page's to mend, the coordinator's to give out).

///|
/// The cells that set out a way after their step's moment now, `screen mode step`, which of the two they are (`B`: only
/// as an answer comes late; `C`: the page's own) and how many ways they set out at all the paces together. What and where is printed as each test runs
/// (ANSWERS_STILL).
let answers_still_known : Array[(String, String, Int)] = [
  // (usage_node.mbt:1003, 用量's days as its answer comes: one at each late pace)
  ("小屏 home to usage", "B", 5),
  ("小屏 chat-preview-named to usage", "B", 5),
  ("中屏 home to usage", "B", 5),
  ("中屏 chat-preview-named to usage", "B", 5),
  ("大屏 home to usage", "B", 5),
  ("大屏 chat-preview-named to usage", "B", 5),
  // (chat_bar_wide_node.mbt:225, the chat's bar as the chat's answer comes)
  ("中屏 chat-preview-named another chat", "B", 6),
  ("中屏 chat-preview-named back to its chat", "B", 4),
  ("大屏 chat-preview-named another chat", "B", 6),
  ("大屏 chat-preview-named back to its chat", "B", 5),
]

///|
/// The core's answers in each cell (ms after they are asked).
let answers_ms : Array[Double] = [0.0, 16.0, 120.0, 250.0, 400.0, 700.0]

///|
/// A step: its name, and what it does (a person's act: true where it could be done on this screen).
priv struct AnswerStep {
  name : String
  act : (@ui.Tester) -> Bool
}

///|
/// The steps walked on a page of `mode`.
fn answer_steps(mode : String) -> Array[AnswerStep] {
  let steps : Array[AnswerStep] = []
  if mode.has_prefix("chat") {
    steps.push({
      name: "another chat",
      act: fn(_) {
        open_chat({ station: "ws1/st1", session: "s-c2", title: "首页的列表改成按天分组", station_name: "Willow" })
        true
      },
    })
    steps.push({
      name: "back to its chat",
      act: fn(_) {
        open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
        true
      },
    })
    steps.push({
      name: "a picture opened",
      act: fn(t) {
        // (the chat walked up a row at a time till its picture shows, a step of its own before the press)
        walk_to_image(t, "compare.png")
        t.run_for(@ui.move_most_ms)
        t.ways_set_out() |> ignore
        match t.locate("img:compare.png") {
          [(x, y), ..] => {
            t.tap(x, y)
            true
          }
          _ => false
        }
      },
    })
    steps.push({
      name: "the picture stepped",
      act: fn(t) {
        if viewer.get() is None {
          return false
        }
        t.key(@ui.key_code_right)
        true
      },
    })
    steps.push({
      name: "the picture closed",
      act: fn(t) {
        if viewer.get() is None {
          return false
        }
        t.back()
        true
      },
    })
  }
  for place in ["files", "profiles", "archive", "usage", "chats"] {
    steps.push({ name: "to " + place, act: fn(_) { @sfbase.go_place(place) } })
  }
  steps
}

///|
/// A cell's ways set out after its step: the cell (`screen mode step`), how late the core answered, and each way's kind,
/// moment after the step and where it was made.
priv struct LateWays {
  cell : String
  ms : Double
  ways : Array[String]
}

///|
/// `mode`'s page on `s` over a core answering each call and every subscription `ms` late, walked through answer_steps:
/// each step's ways set out after its own moment.
fn answers_walk(s : Screen, mode : String, ms : Double) -> Array[LateWays] {
  new_run()
  if mode.has_prefix("chat") {
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  }
  let src = round_trip_again(@sffixture.round_trip(fixture_app(mode), ms), 0.0, late=fn(_, _) { ms })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=s.w, h=s.h, platform=s.platform)
  t.check_looks(false)
  t.draw()
  let settle = ms * 8.0 + @ui.move_most_ms + 1000.0
  t.run_for(settle)
  t.ways_set_out() |> ignore
  let out = []
  for step in answer_steps(mode) {
    let from = t.time()
    if !(step.act)(t) {
      continue
    }
    t.run_for(settle)
    let late = t.ways_set_out().filter(fn(w) { w.at > from + 0.5 })
    if late.length() > 0 {
      out.push({
        cell: "\{s.name} \{mode} \{step.name}",
        ms,
        ways: late.map(fn(w) { "\{w.kind} +\{(w.at - from).round()} ms \{w.made} \{w.part}" }),
      })
    }
  }
  out
}

///|
/// The cells walked under `prefix` hold `known`: each cell that set out a way is in it with its column (`C` where it
/// did at 0 ms, else `B`) and how many it set out at all its paces together, and each of it under `prefix` still does
/// as many. More fails (a new spot in a cell known), fewer fails too, till its count comes down. A line may say `C` of
/// a cell that set one out only late, where the same spot is the page's own on another screen. Every way printed
/// (`tag`), each cell's line too (`tag` + "_CELL").
fn late_ways_held(
  tag : String,
  found : Array[LateWays],
  known : Array[(String, String, Int)],
  prefix : String,
) -> Unit raise {
  let cells : Map[String, (String, Int)] = Map([])
  for f in found {
    for w in f.ways {
      println("\{tag} \{f.cell}, core \{f.ms} ms: \{w}")
    }
    let col = if f.ms <= 0.0 { "C" } else { "B" }
    let (was, n) = cells.get(f.cell).unwrap_or((col, 0))
    cells[f.cell] = (if was == "C" { "C" } else { col }, n + f.ways.length())
  }
  let said = []
  for cell, cn in cells {
    let (col, n) = cn
    println("\{tag}_CELL (\"\{cell}\", \"\{col}\", \{n}),")
    match known.iter().find_first(fn(k) { k.0 == cell }) {
      // (one set out at 0 ms is the page's whatever its line says; one only late may be said the page's, where the same
      // spot is so on another screen)
      Some((_, c, _)) if c != col && c != "C" => said.push("\{cell} is \{col} now, not \{c}: its line says so")
      Some((_, _, k)) if n > k => said.push("\{cell} sets out \{n} ways after its step, not \{k}: see \{tag} above")
      Some((_, _, k)) if n < k => said.push("\{cell} sets out \{n} ways after its step now, not \{k}: bring its count down")
      Some(_) => ()
      None => said.push("\{cell} sets out \{n} ways after its step (\{col}): see \{tag} above")
    }
  }
  for k in known {
    if k.0.has_prefix(prefix) && !cells.contains(k.0) {
      said.push("\{k.0} sets out no way after its step now: take it off")
    }
  }
  if said.length() > 0 {
    fail(said.join("\n"))
  }
}

///|
/// `mode`'s page on `s` walked at each pace, held to answers_still_known.
fn answers_held(s : Screen, mode : String) -> Unit raise {
  let found = []
  for ms in answers_ms {
    found.push_iter(answers_walk(s, mode, ms).iter())
  }
  late_ways_held("ANSWERS_STILL", found, answers_still_known, "\{s.name} \{mode} ")
}

///|
test "answers still: Home, 小屏" {
  answers_held(daily_small, "home")
}

///|
test "answers still: a chat, 小屏" {
  answers_held(daily_small, "chat-preview-named")
}

///|
test "answers still: Home, 中屏" {
  answers_held(daily_medium, "home")
}

///|
test "answers still: a chat, 中屏" {
  answers_held(daily_medium, "chat-preview-named")
}

///|
test "answers still: Home, 大屏" {
  answers_held(daily_large, "home")
}

///|
test "answers still: a chat, 大屏" {
  answers_held(daily_large, "chat-preview-named")
}
