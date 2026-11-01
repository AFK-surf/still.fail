// An agent's execution history's steps, in any pane (ember web/src/History.tsx, History.css.ts; ToolStep.tsx,
// ToolStep.css.ts): what the core put together (its `history` view) drawn turn by turn, each prompt that woke the agent
// beginning one under a rule saying when and what it did; each event a mark in the gutter on the turn's rail and what it
// is beside it. What people were sent leads, on a card; the agent's own words are a grey line; the calls and thoughts
// between fold into a group, a call opening to what it asked for and what came back (the core's reading of them:
// `history.tool`). Long words fold to a few lines. A call or thought in brief is read whole as it is opened
// (`history.detail`), the pages before as the reader nears the top (`history.older`). 只看收发 leaves out what the
// core calls `work`.

///|
/// What the steps keep of their own (the rest is the core's): what the reader opened (folds, lines, groups, calls), by
/// their keys; the entries read whole (by the step's key: when they came, -1 asked, -2 failed and why); what the core
/// said each opened call is (`history.tool`, by its key); the first item the pages before were last asked above. What
/// a row shows of them it reads, followed (a row is kept while nothing it read changed: history_steps).
priv struct StepsOwn {
  opened : @sf.LiveMap[String, Bool]
  detail : @sf.LiveMap[String, (Double, String)]
  tools : @sf.LiveMap[String, Json]
  older : @signals.Signal[String]
  /// an entry asked to be brought into view, by history (`<station>\u{1}<key>`); the item gone to, marked a moment
  /// (its history's list, its key), and the histories gone to an entry, not following their newest since
  focus : @sf.LiveMap[String, Int]
  marked : @signals.Signal[(String, String)]
  went : Map[String, Bool]
  /// each history's first item as its list was last built, by the list's key, and the frame the pages before last came
  /// in above it
  tops : Map[String, (String, Int)]
  /// 只看收发, for every history (as the web keeps it): a signal, what each history's rows are worked out by
  only_io : @signals.Signal[Bool]
}

///|
let steps_own : StepsOwn = {
  opened: @sf.LiveMap::new(),
  detail: @sf.LiveMap::new(),
  tools: @sf.LiveMap::new(),
  older: @signals.signal("", same=fn(a, b) { a == b }),
  focus: @sf.LiveMap::new(),
  marked: @signals.signal(("", ""), same=fn(a, b) { a == b }),
  went: {},
  tops: {},
  only_io: @signals.signal(false, same=fn(a, b) { a == b }),
}

///|
fn steps_reset() -> Unit {
  steps_own.opened.clear()
  steps_own.detail.clear()
  steps_own.tools.clear()
  steps_own.older.set("")
  steps_own.focus.clear()
  steps_own.marked.set(("", ""))
  steps_own.went.clear()
  steps_own.tops.clear()
  steps_own.only_io.set(false)
}

///|
/// Whether a history shows only what came in and went out (History.tsx onlyIo: what the core calls `work` left out).
pub fn history_only_io() -> Bool {
  steps_own.only_io.get()
}

///|
/// 只看收发 turned on or off.
pub fn history_only_io_flip() -> Unit {
  steps_own.only_io.set(!steps_own.only_io.get())
}

///|
/// Agent `key`'s history on `station` to bring transcript entry `entry` into view as it next shows (a link's
/// `?history=…&entry=…`, History.tsx focusEntry): the item that draws it in the pane's middle, marked a moment.
pub fn history_focus(station : String, key : String, entry : Int) -> Unit {
  steps_own.focus[station + "\u{1}" + key] = entry
}

///|
/// The transcript entries an item spans (HistoryItem.entries: its first and last), if it says.
fn entries_of(item : Json?) -> (Int, Int)? {
  match field(item, "entries") {
    Some(Array([Number(a, ..), Number(b, ..)])) => Some((a.to_int(), b.to_int()))
    _ => None
  }
}

///|
/// One of the history's rows: its top (where it begins, or the pages before on their way), an item (the rail running on
/// past it), the thinking and reply streaming in, the turn's state with the model.
priv enum StepsRow {
  Edge
  Item(Json, Bool)
  Live(Json, Bool)
  Phase(Json)
}

///|
/// Agent `key`'s history on `station`: its steps under its head (history.mbt agent_history). What builds them reads
/// only how they stand (steps_head_of); each row reads its own (steps_row_of) and shows nothing else, so the list keeps
/// its rows however the page is built again (Ctx::list's `rows_read`): what streams in as the agent works (its words
/// being written, the phase it is in, what it used) builds only the row that shows it.
pub fn history_steps(c : @ui.Ctx, src : Source, station : String, key : String) -> Unit {
  let params : Map[String, Json] = { "station": Json::string(station), "key": Json::string(key) }
  let lkey = "history-steps/" + station + "/" + key
  let head = steps_head_of(src, params, lkey)
  if head.waiting {
    c.box(style=steps_waiting, fn() {
      @sf.waiting(c, fn() { steps_sample(c, station, key) }, text=match head.edge {
        "" => @sf.t("web-main.history.reading")
        e => e
      })
    })
    |> ignore
    return
  }
  if head.empty {
    c.box(style=steps_box, fn() { c.text(head.edge, style=steps_edge) |> ignore }) |> ignore
    return
  }
  let more = head.more
  // opened at an entry: the item that draws it to the pane's middle, marked a moment; one before what is loaded, the
  // pages before first; one 只看收发 leaves out, all of it shown again first (what is loaded read only while one is asked)
  let fk = station + "\u{1}" + key
  let mut go_to = ""
  match steps_own.focus.get(fk) {
    Some(e) => {
      let loaded = items((src.topic)("history", params).value, "items")
      match loaded.search_by(fn(i) { entries_of(Some(i)).map(fn(x) { x.0 <= e && e <= x.1 }).unwrap_or(false) }) {
        Some(at) => {
          if steps_own.only_io.get() && flag(loaded.get(at), "work") {
            steps_own.only_io.set(false)
          }
          steps_own.focus.remove(fk)
          steps_own.went[lkey] = true
          go_to = text(loaded.get(at), "key")
          steps_own.marked.set((lkey, go_to))
        }
        None =>
          match loaded.get(0) {
            // (the pages before asked below, as near its top)
            Some(i) if more && e < entries_of(Some(i)).map(fn(x) { x.0 }).unwrap_or(0) => ()
            // not there: where it opens
            _ => steps_own.focus.remove(fk)
          }
      }
    }
    None => ()
  }
  let first = head.first
  // the page before come in above the first item: rows came before it (the edge's row the list's first), what is in
  // view stays where it is (sfbase chat_list's older_came); kept by its index, the reader is left at the top of the
  // page come in, near its top again, and the page before that is asked for, and so on to the history's start
  let (was, came_at) = steps_own.tops.get(lkey).unwrap_or(("", -1))
  let mut came_at = came_at
  if was != "" && was != first {
    let (all, _) = steps_rows_of_topic(src, params, lkey)
    match all.search_by(fn(i) { text(Some(i), "key") == was }) {
      Some(at) if at > 0 => {
        c.list_moved(lkey, 1, at)
        came_at = c.frame_number()
      }
      _ => ()
    }
  }
  steps_own.tops[lkey] = (first, came_at)
  let came = came_at == c.frame_number()
  // the pages before as it nears its top (useLoadNear), or for an entry before what is loaded, once each (read back
  // by that alone: not built again as it scrolls)
  // (where it stood as last laid out, not yet with the rows just come above: not near for them)
  let near = match c.list_info_as(lkey, fn(i) { i.map(fn(i) { i.first >= 0 && i.first <= 2 }) }) {
    Some(info) => !came && info.first >= 0 && info.first <= 2
    None => false
  }
  match (more && (near || steps_own.focus.contains(fk)), steps_own.older.get() != first) {
    (true, true) =>
      c.after_build("history-older/" + lkey, fn() {
        if steps_own.older.get() == first {
          return
        }
        steps_own.older.set(first)
        (src.call)("history.older", Json::object(params), fn(res) {
          if res is Err(_) {
            steps_own.older.set("")
            // (an entry asked for before what could be had: where it opens)
            steps_own.focus.remove(fk)
          }
        })
      })
    _ => ()
  }
  // gone to an entry: its item in the pane's middle (the edge's row before the items)
  if go_to != "" {
    let (all, _) = steps_rows_of_topic(src, params, lkey)
    match all.search_by(fn(i) { text(Some(i), "key") == go_to }) {
      Some(at) => {
        let half = match c.list_info_as(lkey, fn(i) { i.map(fn(i) { i.height }) }) {
          Some(info) => info.height / 2.0
          None => 0.0
        }
        c.list_scroll_to(lkey, at + 1, offset=steps_est / 2.0 - half)
      }
      None => ()
    }
  }
  c.box(style=steps_box, fn() {
    c.list(
      lkey,
      head.rows + 1,
      steps_est,
      fn(i) {
        guard steps_row_of(src, params, lkey, i) is Some(row) else {
          // the room under the last (historyBody: 40)
          c.box(style=steps_foot, fn() {  }) |> ignore
          return
        }
        c.box(style=if i == 0 { steps_row_first } else { steps_row }, fn() {
          match row {
            Edge => {
              let head = steps_head_of(src, params, lkey)
              if head.more {
                c.box(style=steps_edge_wait, fn() { @sf.wait_line(c, head.edge, key=lkey) }) |> ignore
              } else {
                c.text(head.edge, style=steps_edge) |> ignore
              }
            }
            Item(item, rail) => {
              let marked = steps_own.marked.get() == (lkey, text(Some(item), "key")) &&
                !@kit.after(c, "history-marked/" + lkey, true, steps_marked_ms)
              history_row(c, src, station, key, Some(item), rail, marked~)
            }
            Live(l, rail) =>
              steps_main(c, rail, fn() {
                ev(c, "think", "", "", rail_last=true, fn() { c.text(text(Some(l), "text"), style=live_words) |> ignore })
              })
            Phase(p) => phase_line(c, src, Some(p))
          }
        })
        |> ignore
      },
      // (followed at its newest; not once gone to an entry)
      stick_end=!steps_own.went.contains(lkey),
      rows_read=true,
    )
    |> ignore
  })
  |> ignore
}

///|
/// How an agent's history's steps stand (what builds them reads of it): read yet, none, what its top says, whether
/// there are pages before, how many rows and its first item's key.
priv struct StepsHead {
  waiting : Bool
  empty : Bool
  edge : String
  more : Bool
  rows : Int
  first : String
} derive(Eq)

///|
/// Each history's StepsHead, by its list's key: told only as it comes out otherwise.
// kept across runs: what it keeps is let go of by a run anew and by reset (sfbase derived.mbt)
let steps_head : @sfbase.Kept[StepsHead] = @sfbase.Kept::new()

///|
fn steps_head_of(src : Source, params : Map[String, Json], lkey : String) -> StepsHead {
  steps_head.read(
    lkey,
    fn(_) {
      let h = (src.topic)("history", params).value
      let empty = flag(h, "empty")
      let waiting = !(h is Some(Object(_))) || (empty && !flag(h, "loaded"))
      let (all, rows) = if waiting || empty { ([], []) } else { steps_rows_of_topic(src, params, lkey) }
      {
        waiting,
        empty,
        edge: text(h, "edge"),
        more: flag(h, "more"),
        rows: rows.length(),
        first: match all.get(0) {
          Some(i) => text(Some(i), "key")
          None => ""
        },
      }
    },
    same=fn(a, b) { a == b },
  )
}

///|
/// Agent `key`'s history's rows (steps_rows).
fn steps_rows_of_topic(src : Source, params : Map[String, Json], lkey : String) -> (Array[Json], Array[StepsRow]) {
  steps_rows.read(lkey, fn(_) {
    let h = (src.topic)("history", params).value
    steps_rows_of(h, items(h, "items"), steps_own.only_io.get())
  })
}

///|
/// Each history's rows one at a time, by its list's key and the row: None past them (the room under the last). Told only
/// as the row comes out otherwise (steps_row_same), not as another one does.
// kept across runs: what it keeps is let go of by a run anew and by reset (sfbase derived.mbt)
let steps_row_kept : @sfbase.Kept[StepsRow?] = @sfbase.Kept::new()

///|
fn steps_row_of(src : Source, params : Map[String, Json], lkey : String, i : Int) -> StepsRow? {
  steps_row_kept.read(
    lkey + "\u{1}" + i.to_string(),
    fn(_) { steps_rows_of_topic(src, params, lkey).1.get(i) },
    same=steps_row_same,
  )
}

///|
/// A row the same as before: the same of it, its item the same JSON (the core's deltas keep what they do not touch),
/// its rail running on as it did.
fn steps_row_same(a : StepsRow?, b : StepsRow?) -> Bool {
  match (a, b) {
    (None, None) | (Some(Edge), Some(Edge)) => true
    (Some(Item(x, r)), Some(Item(y, s))) => physical_equal(x, y) && r == s
    (Some(Live(x, r)), Some(Live(y, s))) => physical_equal(x, y) && r == s
    (Some(Phase(x)), Some(Phase(y))) => physical_equal(x, y)
    _ => false
  }
}

///|
/// An agent's history's rows (`h`, its items `loaded`), 只看收发 (`io`) or not: the items shown, and the rows (the edge's,
/// each item's, what is in flight, the phase it is in).
fn steps_rows_of(h : Json?, loaded : Array[Json], io : Bool) -> (Array[Json], Array[StepsRow]) {
  let all = loaded.filter(fn(i) { !io || !flag(Some(i), "work") })
  let live = if io { [] } else { items(h, "live") }
  let phase = field(h, "phase")
  let going = live.length() > 0 || phase is Some(Object(_))
  let rows : Array[StepsRow] = [Edge]
  for i, item in all {
    // the turn's rail runs on from an item to the next unless the next begins a turn of its own; from the last, to what
    // is in flight
    let rail = match all.get(i + 1) {
      Some(next) => !(field(Some(next), "turn") is Some(Object(_)))
      None => going
    }
    rows.push(Item(item, rail))
  }
  for i, l in live {
    rows.push(Live(l, i < live.length() - 1 || phase is Some(Object(_))))
  }
  match phase {
    Some(Object(_)) as p => rows.push(Phase(p.unwrap()))
    _ => ()
  }
  (all, rows)
}

///|
/// Each history's rows, by its list's key: worked out again as its topic changes or 只看收发 is turned (steps_rows_of,
/// a computed: sfbase derived.mbt).
// kept across runs: what it keeps is let go of by a run anew and by reset (sfbase derived.mbt)
let steps_rows : @sfbase.Kept[(Array[Json], Array[StepsRow])] = @sfbase.Kept::new()

///|
/// About how tall a row stands before it is laid out.
let steps_est : Double = 48.0

///|
/// An item (hItem): the rule of the turn it begins (if it does), then its events.
fn history_row(
  c : @ui.Ctx,
  src : Source,
  station : String,
  key : String,
  item : Json?,
  rail : Bool,
  marked? : Bool = false,
) -> Unit {
  let ik = text(item, "key")
  // gone to (an entry's): on the accent's faint ground a moment (hItem[data-focus])
  c.box(style=if marked { h_item_marked } else { h_item }, fn() {
    match field(item, "turn") {
      Some(Object(_)) as turn =>
        // when it began and what it did (hTurn), a heading: no line on to the edge (only a menu's parts are set apart
        // by one)
        c.box(style=h_turn, fn() {
          let said = match text(turn, "time") {
            "" => text(turn, "text")
            time => time + " · " + text(turn, "text")
          }
          c.text(said, style=h_turn_words, allow_ellipsis=true) |> ignore
        })
        |> ignore
      _ => ()
    }
    steps_main(c, rail, fn() { item_view(c, src, station, key, ik, item, rail) })
  })
  |> ignore
}

///|
/// The history's rows to come while it is read the first time (the library's Waiting, in its bones): a turn's items
/// of made-up words, as its list draws them, its calls' groups and the agent's own words between them, as a turn
/// mostly is.
fn steps_sample(c : @ui.Ctx, station : String, key : String) -> Unit {
  let lines = [("group", 16), ("text", 24), ("group", 12), ("group", 20), ("text", 9), ("group", 18)]
  for i, line in lines {
    let (kind, n) = line
    let words = Json::string(@sf.sample_words(n))
    let content : Json = if kind == "group" { { "summary": words } } else { { "text": words, "line": words } }
    let item : Map[String, Json] = {
      "key": Json::string("sample" + i.to_string()),
      "body": { "kind": Json::string(kind), "content": content },
    }
    // (the turn's head over its first)
    if i == 0 {
      item["turn"] = { "time": Json::string(@sf.sample_words(4)), "text": Json::string(@sf.sample_words(8)) }
    }
    let item = Json::object(item)
    c.box(style=if i == 0 { steps_row_first } else { steps_row }, fn() {
      history_row(c, @sfbase.sample_source, station, key, Some(item), i + 1 < lines.length())
    })
    |> ignore
  }
}

///|
/// An item's events, one under another (hMain), 10 apart.
fn steps_main(c : @ui.Ctx, rail : Bool, body : () -> Unit) -> Unit {
  ignore(rail)
  c.box(style=h_main, body) |> ignore
}

///|
/// One event (Ev, hEv): its mark in the gutter (on the canvas, so the turn's rail passes behind it; in a state's block on
/// its colour) and what it is beside it, 8 apart. The rail runs down from under its mark to the next event's (`rail`:
/// one follows), or on to the next item (`rail_last`). `state`: how the turn stands or ended, a block in its colour;
/// `tone`: its mark in the accent or the red. `row`: its first line a row pressed whole (one_line: a row's least high),
/// its mark in that line's middle as in a line of words', the rail from under it.
fn ev(
  c : @ui.Ctx,
  icon : String,
  state : String,
  tone : String,
  rail? : Bool = false,
  rail_last? : Bool = false,
  row? : Bool = false,
  body : () -> Unit,
) -> Unit {
  let t = @sf.theme()
  // (the first line's height: a line of words' 20, or a row's least)
  let line = if row { @sf.row_least() } else { h_mark }
  let ink = match (state, tone) {
    ("done", _) => t.p.green
    ("waiting", _) => t.p.blue
    ("human", _) => t.p.accent_text
    (_, "accent") => t.p.accent
    (_, "red") => t.p.red
    _ => t.p.muted
  }
  c.box(style=h_ev, fn() {
    if state != "" {
      // a state is a block in its colour, a little past its gutter and its words
      c.layer(fn() {
        c.box(
          style=match state {
            "waiting" => h_state.then(@ui.style(bg=Data(t.p.blue_bg)))
            "human" => h_state_human
            _ => h_state
          },
          fn() {  },
        )
        |> ignore
      })
      |> ignore
    } else if rail || rail_last {
      c.layer(fn() {
        let room = if rail_last { h_rail_room_last } else { h_rail_room }
        // (from under its mark, in the middle of its first line)
        let under = @sf.room_of((line + h_mark) / 2.0)
        c.box(style=room.then(@ui.style(pt=under)), fn() {
          c.box(style=h_rail, fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    c.box(style=h_icon.then(@ui.style(h=Fixed(line))), fn() {
      if icon == "pulse" {
        c.box(style=h_pulse, fn() {  }) |> ignore
      } else {
        @sf.icon(c, icon, size=14.0, color=ink) |> ignore
      }
    })
    |> ignore
    c.box(style=h_ev_body, body) |> ignore
  })
  |> ignore
}

///|
/// What an item is (HistoryItemView): what a prompt carried, the agent's own words, what it sent, a state, a group.
fn item_view(c : @ui.Ctx, src : Source, station : String, key : String, ik : String, item : Json?, rail : Bool) -> Unit {
  let body = field(item, "body")
  let content = field(body, "content")
  match text(body, "kind") {
    "received" => {
      let note = text(content, "note")
      let tasks = items(content, "tasks")
      let messages = items(content, "messages")
      let n = (if note != "" { 1 } else { 0 }) + tasks.length() + messages.length()
      let mut at = 0
      let next = fn() {
        at = at + 1
        at < n
      }
      if note != "" {
        let more = next()
        ev(c, "bell", "", "", rail=more, rail_last=!more && rail, row=true, fn() {
          one_line(c, ik + "/note", fn() {
            c.text(@sf.t("web-main.history.reminder", args=[("name", "still.fail")]), style=h_strong) |> ignore
          }, first_line(note), "", fn() { c.text(note, style=h_note_plain) |> ignore })
        })
      }
      for k, task in tasks {
        let more = next()
        task_view(c, ik + "/task/" + k.to_string(), Some(task), more, !more && rail)
      }
      for k, m in messages {
        let more = next()
        received(c, src, station, ik + "/message/" + k.to_string(), Some(m), more, !more && rail)
      }
    }
    // the agent's own words reach no one (only what it posts does): a grey line, whole as it is opened
    "text" =>
      ev(c, "said", "", "", rail_last=rail, row=true, fn() {
        let words = text(content, "text")
        one_line(c, ik + "/text", fn() {
          // (a chip: in bones one piece)
          let tag = c.box(style=h_tag, fn() {
            c.text(
              @sf.t(if flag(content, "subagent") { "web-main.history.subagent" } else { "web-main.history.notSent" }),
              style=h_tag_words,
            )
            |> ignore
          })
          c.bone_whole(tag)
        }, text(content, "line"), "", fn() { md_view(c, ik + "/text-md", words, field(content, "md"), small=true) })
      })
    "post" => {
      let ends = text(content, "ends")
      let failed = flag(content, "failed")
      ev(c, "send", "", if failed { "red" } else { "accent" }, rail=ends != "", rail_last=ends == "" && rail, fn() {
        c.box(style=h_label, flow=true, fn() {
          c.text(@sf.t("web-main.history.sentTo"), style=h_label_words) |> ignore
          match field(content, "place") {
            Some(Object(_)) as p => place_view(c, station, ik + "/place", p)
            _ =>
              c.box(style=h_place, fn() {
                @sf.slack_mark(c, 12.0) |> ignore
                c.text("Slack", style=h_place_words) |> ignore
              })
              |> ignore
          }
          if flag(content, "block") && ends == "" {
            @sf.pill(c, "Block", tone=Blue)
          }
          if failed {
            @sf.pill(c, @sf.t("web-main.history.sendFailed"), tone=Red)
          }
        })
        |> ignore
        c.box(style=if failed { h_card_failed } else { h_card }, fn() {
          let words = text(content, "text")
          fold(c, ik + "/post", post_lines, md_line, fn() { md_view(c, ik + "/post-md", words, field(content, "md")) })
        })
        |> ignore
      })
      if ends != "" {
        ended(c, ends, @sf.t(if ends == "human" { "web-main.history.ends.human" } else { "web-main.history.ends.done" }), rail)
      }
    }
    "mark" => mark_view(c, src, content, rail)
    "group" => group_view(c, src, station, key, ik, content, rail)
    _ => ()
  }
}

///|
/// A whole, in percent (how much of a wait has gone).
let percent : Double = 100.0

///|
/// The lines a sent message and a person's words show folded, and how tall a line of each is.
let post_lines : Int = 6

///|
let words_lines : Int = 4

///|
let md_line : Double = 23.0

///|
let words_line : Double = 20.0

///|
/// Words as Markdown, as the core read them (its tree, `md`): the panel's size, or small and grey (`small`: the agent's
/// own words, a sub-agent's answer).
fn md_view(c : @ui.Ctx, key : String, words : String, md : Json?, small? : Bool = false) -> Unit {
  let t = @sf.theme()
  @sf.markdown(c, words, key~, tree=md, size=if small { 12.0 } else { 13.0 }, ink=if small { t.p.muted } else { 0L }) |> ignore
}

///|
/// A thought whole: its Markdown small and grey, as the agent's own words are (the core's tree of them).
fn thought_md(c : @ui.Ctx, rk : String, content : Json?) -> Unit {
  md_view(c, rk + "/md", text(content, "text"), field(content, "md"), small=true)
}

///|
/// An event in one line (OneLine): its lead, then its words cut at the end; pressed (where there is more), what `whole`
/// says in whole under it, the line's words giving way to 收起.
fn one_line(c : @ui.Ctx, key : String, lead : () -> Unit, line : String, tone : String, whole : () -> Unit) -> Unit {
  let id = c.id("history-one/" + key)
  let open = steps_own.opened.contains(key)
  if c.clicked(id) {
    if open {
      steps_own.opened.remove(key)
    } else {
      steps_own.opened[key] = true
    }
  }
  let hot = c.lit(id)
  c.box(style=h_one.then(@sf.row_least_h()), id~, fn() {
    lead()
    if !open && line != "" {
      c.text(line, style=if tone == "red" {
        h_one_red
      } else if hot {
        h_one_hot
      } else {
        h_one_words
      })
      |> ignore
    }
    if open {
      c.box(style=h_grow, fn() {  }) |> ignore
      c.text(@sf.t("web-main.fold"), style=if hot { h_one_fold_hot } else { h_one_fold }) |> ignore
    }
  })
  |> ignore
  if open {
    c.box(style=h_one_body, whole) |> ignore
  }
}

///|
/// Long words folded to `lines` lines of `line` (Fold): past that they are cut, a button under them saying how many
/// more lines there are; pressed, all of them, 收起 under them.
fn fold(c : @ui.Ctx, key : String, lines : Int, line : Double, body : () -> Unit) -> Unit {
  let inner = c.id("history-fold/" + key)
  let most = lines.to_double() * line + 2.0
  let tall = match c.laid_size(inner) {
    Some((_, h)) => h
    None => 0.0
  }
  let long = tall > most + 4.0
  let open = steps_own.opened.contains(key)
  c.box(style=h_fold, fn() {
    let room = if long && !open { h_fold_room.then(@ui.style(max_h=Fixed(most))) } else { h_fold_room }
    c.box(style=room, fn() { c.box(style=h_fold_inner, id=inner, body) |> ignore }) |> ignore
    if long {
      let id = c.id("history-fold-toggle/" + key)
      if c.clicked(id) {
        if open {
          steps_own.opened.remove(key)
        } else {
          steps_own.opened[key] = true
        }
      }
      let more = dmax(1.0, ((tall - most) / line).round()).to_int()
      let words = if open {
        @sf.t("web-main.fold")
      } else {
        @sf.t("web-main.history.more", args=[("n", more.to_string())])
      }
      let b = c.box(style=h_fold_toggle, id~, fn() {
        c.text(words, style=if c.lit(id) { h_toggle_hot } else { h_toggle_words }) |> ignore
      })
      c.semantics(b, Button, id~, label=words)
    }
  })
  |> ignore
}

///|
/// A message to the agent (Received): who and where in a line, their words under it, folded to four lines; an agent's
/// (another chat's letter) as Markdown, a job's as it wrote them, in a monospaced font.
fn received(c : @ui.Ctx, src : Source, station : String, key : String, m : Json?, rail : Bool, rail_last : Bool) -> Unit {
  let notice = text(m, "notice")
  let job = notice == "job"
  ev(c, "received", "", "", rail~, rail_last~, fn() {
    c.box(style=h_label, flow=true, fn() {
      c.text(
        @sf.t(if job { "web-main.history.jobMessage.before" } else { "web-main.history.message.before" }),
        style=h_label_words,
      )
      |> ignore
      let from = field(m, "from")
      let user = text(from, "slackUser")
      if user != "" {
        slack_name(c, src, station, key, user, text(from, "name"), flag(from, "bound"))
      } else {
        c.text(if notice == "stillfail" { "still.fail" } else { text(from, "name") }, style=h_strong) |> ignore
      }
      c.text(@sf.t(if job { "web-main.history.jobMessage.after" } else { "web-main.history.message.after" }), style=h_label_words)
      |> ignore
      match field(m, "place") {
        Some(Object(_)) as p => {
          c.text(" · ", style=h_label_words) |> ignore
          place_view(c, station, key + "/place", p)
        }
        _ => ()
      }
    })
    |> ignore
    let words = text(m, "text")
    match field(m, "md") {
      Some(Array(_)) as md => fold(c, key, words_lines, md_line, fn() { md_view(c, key + "/md", words, md) })
      _ =>
        fold(c, key, words_lines, words_line, fn() {
          if job {
            c.rich([@ui.span(words, mono=true)], style=h_output) |> ignore
          } else {
            c.text(words, style=h_words) |> ignore
          }
        })
    }
  })
}

///|
/// A place as its platform's mark and its name (Where): a Slack thread opens in Slack, a still.fail chat its page.
fn place_view(c : @ui.Ctx, station : String, key : String, place : Json?) -> Unit {
  let id = c.id("history-place/" + key)
  let url = text(place, "url")
  let session = text(place, "session")
  let goes = url != "" || session != ""
  if goes {
    if c.clicked(id) {
      if url != "" {
        @sfbase.open_slack(text(place, "app"), url) |> ignore
      } else {
        @sfbase.history_push()
        app.nav.push(Chat({ station, session, title: text(place, "name"), station_name: "" }))
      }
    }
  }
  let hot = goes && c.lit(id)
  c.box(style=if hot { h_place_hot } else { h_place }, id~, fn() {
    match text(place, "surface") {
      "ember" | "stillfail" =>
        @sf.drawable(c, if @sf.theme().dark { "stillfail_mark_dark" } else { "stillfail_mark" }, 12.0) |> ignore
      "feishu" => @sf.feishu_mark(c, 12.0) |> ignore
      _ => @sf.slack_mark(c, 12.0) |> ignore
    }
    c.text(text(place, "name"), style=h_place_words) |> ignore
  })
  |> ignore
}

///|
/// A Slack user's name (SlackName): pressed, 这是我 (the station then takes that Slack user for the viewer), or 不是我
/// once it does; turning while the station is told, a red mark a few seconds if that failed.
fn slack_name(c : @ui.Ctx, src : Source, station : String, key : String, user : String, name : String, bound : Bool) -> Unit {
  let on = [("station", station), ("user", user)]
  let saying = core_doing(src, ["slack.identity"], on)
  let id = c.id("history-slack/" + key)
  if !saying {
    // its menu, the presenters' (a sheet with a finger short of Large, else at the name)
    if c.clicked(id) {
      let words = if bound { @sf.t("web-main.history.notMe") } else { @sf.t("web-main.history.isMe") }
      @sf.menu(
        [
          Some(
            @sf.menu_item_of(words, fn() {
              act(src, words, "", "slack.identity", {
                "station": Json::string(station),
                "user": Json::string(user),
                // (the core's `bound`: bound to the viewer, or let go)
                "bound": Json::boolean(!bound),
              })
            }),
          ),
        ],
        from=Of(id),
      )
    }
  }
  c.box(style=h_person, id~, fn() {
    c.rich([@ui.span(name, underline=c.lit(id) && !saying)], style=h_strong) |> ignore
    @settings.doing_mark(c, saying, core_failed(src, ["slack.identity"], on), inline=true)
  })
  |> ignore
}

///|
/// Work the agent started in the background, ended (Task): a line saying how; what a sub-agent answered in a line under
/// it, whole as the line saying how is opened.
fn task_view(c : @ui.Ctx, key : String, task : Json?, rail : Bool, rail_last : Bool) -> Unit {
  let failed = flag(task, "failed")
  let answer = text(task, "result")
  let has = field(task, "md") is Some(Array(_)) && answer != ""
  ev(c, if flag(task, "agent") { "agent" } else { "command" }, "", if failed { "red" } else { "" }, rail~, rail_last~, row=has, fn() {
    if !has {
      c.box(style=h_one, fn() { c.text(text(task, "text"), style=if failed { h_one_red } else { h_one_words }) |> ignore })
      |> ignore
    } else {
      one_line(c, key, fn() {  }, text(task, "text"), if failed { "red" } else { "" }, fn() {
        if flag(task, "agent") {
          md_view(c, key + "/md", answer, field(task, "md"), small=true)
        } else {
          c.rich([@ui.span(answer, mono=true)], style=h_output) |> ignore
        }
      })
      if !steps_own.opened.contains(key) {
        c.box(style=h_one, fn() { c.rich([@ui.span(text(task, "line"), mono=!flag(task, "agent"))], style=h_one_words) |> ignore }) |> ignore
      }
    }
  })
}

///|
/// A turn's state (MarkView): waiting on work it started (counting on while it does, a bar filling toward the most it
/// waits), done, or waiting on a person.
fn mark_view(c : @ui.Ctx, src : Source, mark : Json?, rail : Bool) -> Unit {
  let wait = field(mark, "wait")
  match wait {
    Some(Object(_)) => {
      let still = !(field(wait, "until") is Some(Number(_)))
      ev(c, "wait", if still { "waiting" } else { "waited" }, "", rail_last=rail, fn() {
        c.box(style=h_state_line, fn() {
          if still {
            let now = (src.now)()
            let since = number(wait, "since")
            let what = match text(wait, "what") {
              "" => ""
              w => w + " · "
            }
            let waited = match opt_number(wait, "seconds") {
              Some(sec) if sec > 0.0 => {
                if now - since < sec * second_ms {
                  each_second(c, now - since)
                }
                let ran = if now - since < sec * second_ms { now - since } else { sec * second_ms }
                elapsed(ran) + " / " + elapsed(sec * second_ms)
              }
              _ => {
                each_second(c, now - since)
                elapsed(now - since)
              }
            }
            c.text(what + @sf.t("web-main.activity.waiting") + " " + waited, style=h_state_words) |> ignore
          } else {
            c.text(text(mark, "text"), style=h_state_words) |> ignore
          }
        })
        |> ignore
        match opt_number(wait, "seconds") {
          Some(sec) if still && sec > 0.0 => {
            // how much of the most it waits has gone (WaitBar: a clock, not a motion)
            let gone = dmin(1.0, dmax(0.0, ((src.now)() - number(wait, "since")) / (sec * second_ms))) * percent
            c.box(style=h_wait_bar, fn() {
              c.box(style=h_wait_fill.then(@ui.style(w=Pct(gone))), fn() {  }) |> ignore
            })
            |> ignore
          }
          _ => ()
        }
      })
    }
    _ => ended(c, text(mark, "ends"), text(mark, "text"), rail)
  }
}

///|
/// How a turn ended (Ended): done, or waiting on a person (or on work it started; or words of another state).
fn ended(c : @ui.Ctx, ends : String, words : String, rail : Bool) -> Unit {
  let (icon, state) = match ends {
    "human" => ("user", "human")
    "done" => ("check-circle", "done")
    "waiting" => ("wait", "waited")
    _ => ("info", "other")
  }
  ev(c, icon, state, "", rail_last=rail, fn() {
    c.box(style=h_state_line, fn() { c.text(words, style=h_state_words) |> ignore }) |> ignore
  })
}

///|
/// A group of calls and thoughts (Group): its line (the chevron in the gutter, what it did, how many failed, how many
/// are on their way; its title in its tip), all of it opening the group; opened, a line each, beside the turn's rail.
fn group_view(c : @ui.Ctx, src : Source, station : String, key : String, ik : String, g : Json?, rail : Bool) -> Unit {
  let gk = ik + "/group"
  let open = steps_own.opened.contains(gk)
  let id = c.id("history-group/" + gk)
  if c.clicked(id) {
    if open {
      steps_own.opened.remove(gk)
    } else {
      steps_own.opened[gk] = true
    }
  }
  let failures = number(g, "failures").to_int()
  let pending = number(g, "pending").to_int()
  let rows = items(g, "rows")
  let calls = rows.iter().any(fn(r) { text(Some(r), "kind") == "step" })
  let hot = c.lit(id)
  c.box(style=h_group, fn() {
    if rail {
      c.layer(fn() { c.box(style=h_rail_room_last, fn() { c.box(style=h_rail, fn() {  }) |> ignore }) |> ignore }) |> ignore
    }
    let b = c.box(style=h_group_head.then(@sf.row_least_h()), id~, fn() {
      c.box(style=h_icon, fn() {
        @sf.icon(c, if open { "chevron-down" } else { "chevron-right" }, size=14.0, color=if hot {
          @sf.theme().p.text
        } else {
          @sf.theme().p.muted
        })
        |> ignore
      })
      |> ignore
      c.box(style=h_grow_clip, fn() {
        c.rich([@ui.span(text(g, "summary"), mono=calls)], style=if hot { h_group_hot } else { h_group_words }) |> ignore
      })
      |> ignore
      if failures > 0 {
        @sf.pill(c, @sf.t("web-main.history.failures", args=[("n", failures.to_string())]), tone=Red)
      }
      if pending > 0 {
        @sf.pill(c, @sf.t("web-main.history.pending", args=[("n", pending.to_string())]), tone=Accented)
      }
    })
    c.semantics(b, Button, id~, label=text(g, "summary"), expanded=open)
    match text(g, "title") {
      "" => ()
      title => @sf.tip(c, "history-group/" + gk, id, title)
    }
    if open {
      c.box(style=h_steps, fn() {
        for i, row in rows {
          let rv = Some(row)
          let content = field(rv, "content")
          let rk = gk + "/" + i.to_string()
          if text(rv, "kind") == "thought" {
            if calls {
              opened(c, src, station, key, rk, content, false, fn() {
                c.text(@sf.t("web-main.history.thinking"), style=h_step_name) |> ignore
                c.box(style=h_grow_clip, fn() { c.text(text(content, "first"), style=h_step_hint) |> ignore }) |> ignore
              }, fn() { c.box(style=h_step_body, fn() { thought_md(c, rk, content) }) |> ignore })
            } else {
              whole(c, src, station, key, rk, content, fn() {
                c.box(style=h_thinking, fn() { thought_md(c, rk, content) }) |> ignore
              })
            }
          } else {
            step_view(c, src, station, key, rk, content)
          }
        }
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A call (Step): its line (what it said it does, or its name and a hint of it; how long it took or how it ended);
/// opened, what it asked for and what came back.
fn step_view(c : @ui.Ctx, src : Source, station : String, key : String, rk : String, step : Json?) -> Unit {
  let failed = flag(step, "failed")
  opened(c, src, station, key, rk, step, failed, fn() {
    match text(step, "said") {
      "" => {
        c.text(text(step, "name"), style=if failed { h_step_name_red } else { h_step_name }) |> ignore
        c.box(style=h_grow_clip, fn() { c.rich([@ui.span(text(step, "hint"), mono=true)], style=h_step_hint) |> ignore })
        |> ignore
      }
      said => c.box(style=h_grow_clip, fn() { c.text(said, style=h_step_said) |> ignore }) |> ignore
    }
    c.text(text(step, "meta"), style=if failed { h_step_meta_red } else { h_step_meta }) |> ignore
  }, fn() { tool_body(c, src, rk, step) })
}

///|
/// A line of a group that opens to what is behind it (Opened, a summary's line: 5 by 6 in, round 8, the pointer's ground
/// on it); in brief, read whole as it is opened.
fn opened(
  c : @ui.Ctx,
  src : Source,
  station : String,
  key : String,
  rk : String,
  content : Json?,
  failed : Bool,
  summary : () -> Unit,
  body : () -> Unit,
) -> Unit {
  ignore(failed)
  let id = c.id("history-step/" + rk)
  let open = steps_own.opened.contains(rk)
  if c.clicked(id) {
    if open {
      steps_own.opened.remove(rk)
    } else {
      steps_own.opened[rk] = true
    }
  }
  c.box(style=h_step, fn() {
    let b = c.box(style=h_step_summary.then(@sf.row_least_h()), id~, summary)
    c.semantics(b, Button, id~, expanded=open)
    if open {
      whole(c, src, station, key, rk, content, body)
    }
  })
  |> ignore
}

///|
/// What a step or thought holds, as it shows (Whole): in brief, read whole now (`history.detail`), a line saying so till
/// it comes (or why it did not).
fn whole(c : @ui.Ctx, src : Source, station : String, key : String, rk : String, content : Json?, body : () -> Unit) -> Unit {
  if !flag(content, "brief") {
    body()
    return
  }
  let entries = items(content, "entries").map(fn(e) {
    match e {
      Number(n, ..) => n
      _ => 0.0
    }
  })
  match steps_own.detail.get(rk) {
    None if entries.length() > 0 =>
      c.after_build("history-detail/" + rk, fn() {
        if steps_own.detail.contains(rk) {
          return
        }
        steps_own.detail[rk] = (-1.0, "")
        let mut lo = entries[0]
        let mut hi = entries[0]
        for e in entries {
          lo = dmin(lo, e)
          hi = dmax(hi, e)
        }
        (src.call)(
          "history.detail",
          { "station": Json::string(station), "key": Json::string(key), "from": Json::number(lo), "to": Json::number(hi) },
          fn(res) {
            match res {
              Ok(_) => steps_own.detail[rk] = (0.0, "")
              Err(e) => steps_own.detail[rk] = (-2.0, error_words(e))
            }
          },
        )
      })
    _ => ()
  }
  match steps_own.detail.get(rk) {
    Some((-2.0, why)) =>
      c.box(style=h_step_body, fn() {
        c.text(@sf.t("web-main.history.stepUnread", args=[("error", why)]), style=h_thinking_muted) |> ignore
      })
      |> ignore
    _ => c.box(style=h_step_body, fn() { @sf.wait_line(c, "", key="history-detail/" + rk) }) |> ignore
  }
}

///|
/// A call opened (ToolStep's body): what it asked for, then what came back, as the core reads them (`history.tool`),
/// asked once as it is first shown.
fn tool_body(c : @ui.Ctx, src : Source, rk : String, step : Json?) -> Unit {
  let ask : Map[String, Json] = {
    "name": Json::string(text(step, "name")),
    "call": Json::string(text(step, "call")),
    "failed": Json::boolean(flag(step, "failed")),
    "said": Json::boolean(text(step, "said") != ""),
  }
  match field(step, "result") {
    Some(String(r)) => ask["result"] = Json::string(r)
    _ => ()
  }
  let tk = rk + "\u{1}" + Json::object(ask).stringify()
  match steps_own.tools.get(tk) {
    Some(parts) =>
      c.box(style=tool_body_box, fn() {
        c.box(style=tool_section, fn() {
          for p in items(Some(parts), "call") {
            tool_part(c, tk, Some(p))
          }
        })
        |> ignore
        match field(Some(parts), "result") {
          Some(Array(list)) => {
            let red = list.iter().any(fn(p) { text(Some(p), "kind") == "output" && flag(Some(p), "failed") })
            ignore(red)
            c.box(style=tool_result_box, fn() {
              for p in list {
                tool_part(c, tk, Some(p))
              }
            })
            |> ignore
          }
          _ => ()
        }
      })
      |> ignore
    None => {
      c.after_build("history-tool/" + tk, fn() {
        if steps_own.tools.contains(tk) {
          return
        }
        (src.call)("history.tool", Json::object(ask), fn(res) {
          match res {
            Ok(v) => steps_own.tools[tk] = v
            Err(_) => ()
          }
        })
      })
      c.box(style=h_step_body, fn() { @sf.wait_line(c, "", key="history-tool/" + rk) }) |> ignore
    }
  }
}

///|
/// A list of things to do (ToolStep.tsx PlanList), each `{text, status}`: done ✓ struck and muted, under way › in 600,
/// the rest ·. A plan call's in the history, and an agent's checklist in its card and its history's details
/// (agent_work).
pub fn plan_list(c : @ui.Ctx, list : Array[Json]) -> Unit {
  c.box(style=tool_plan, fn() {
    for it in list {
      let iv = Some(it)
      let status = text(iv, "status")
      let (mark, mark_ink, words) = match status {
        "completed" => ("✓", @sf.theme().p.green, tool_plan_done)
        "in_progress" => ("›", @sf.theme().p.accent, tool_plan_now)
        _ => ("·", @sf.theme().p.subtle, tool_plan_words)
      }
      c.box(style=tool_plan_row, fn() {
        c.box(style=tool_plan_mark, fn() { c.rich([@ui.span(mark, color=mark_ink)], style=tool_plan_words) |> ignore }) |> ignore
        c.rich([@ui.span(text(iv, "text"), strike=status == "completed")], style=words) |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// One part of a call or of what came back (ToolStep.tsx Part, ToolStep.css.ts).
fn tool_part(c : @ui.Ctx, key : String, part : Json?) -> Unit {
  match text(part, "kind") {
    "code" => @sf.code_block(c, text(part, "text"), text(part, "lang"))
    "facts" =>
      c.box(style=tool_facts, fn() {
        for f in items(part, "items") {
          let fv = Some(f)
          match field(fv, "value") {
            Some(String(v)) if !flag(fv, "plain") =>
              c.rich([@ui.span(text(fv, "key") + " "), @ui.span(v, mono=true, color=@sf.theme().p.muted, weight=500)], style=tool_fact)
              |> ignore
            _ => c.text(text(fv, "key"), style=tool_fact) |> ignore
          }
        }
      })
      |> ignore
    "path" =>
      c.box(style=tool_path, fn() {
        c.rich([@ui.span(text(part, "path"), mono=true)], style=tool_path_words) |> ignore
        match text(part, "extra") {
          "" => ()
          e => c.text(e, style=tool_path_extra) |> ignore
        }
      })
      |> ignore
    "diff" =>
      c.box(style=tool_diff, fn() {
        for r in items(part, "rows") {
          match r {
            Array([String(mark), String(line)]) =>
              c.box(
                style=match mark {
                  "-" => tool_diff_out
                  "+" => tool_diff_line.then(@ui.style(bg=Data(@sf.theme().p.green_bg)))
                  "@" => tool_diff_head
                  _ => tool_diff_line
                },
                fn() {
                  let ink = match mark {
                    "-" => @sf.theme().p.red
                    "+" => @sf.theme().p.green_ink
                    _ => @sf.theme().p.subtle
                  }
                  // (its mark in the gutter before its words, the line's ends as far in either side)
                  c.box(style=tool_diff_mark, fn() {
                    if mark == "-" || mark == "+" {
                      c.rich([@ui.span(mark, mono=true, color=ink)], style=tool_mono) |> ignore
                    }
                  })
                  |> ignore
                  c.box(style=tool_diff_words, fn() {
                    c.rich([@ui.span(if line == "" { " " } else { line }, mono=true)], style=match mark {
                      "@" => tool_mono_head
                      " " => tool_mono_muted
                      _ => tool_mono
                    })
                    |> ignore
                  })
                  |> ignore
                },
              )
              |> ignore
            _ => ()
          }
        }
      })
      |> ignore
    "markdown" =>
      c.box(style=tool_box, fn() { md_view(c, key + "/md", text(part, "text"), field(part, "md"), small=true) }) |> ignore
    "plan" => plan_list(c, items(part, "items"))
    "fields" =>
      c.box(style=tool_fields, fn() {
        for r in items(part, "rows") {
          let rv = Some(r)
          c.box(style=tool_field, fn() {
            c.box(style=tool_field_key, fn() { c.text(text(rv, "key"), style=tool_key_words) |> ignore }) |> ignore
            c.box(style=h_grow, fn() {
              match text(rv, "form") {
                "long" => c.box(style=tool_box, fn() { c.text(text(rv, "value"), style=tool_long_words) |> ignore }) |> ignore
                "json" => c.box(style=tool_box, fn() { c.rich([@ui.span(text(rv, "value"), mono=true)], style=tool_mono) |> ignore }) |> ignore
                _ => c.rich([@ui.span(text(rv, "value"), mono=true)], style=tool_value) |> ignore
              }
            })
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    "lead" => c.box(style=tool_lead, fn() { c.rich([@ui.span(text(part, "text"), mono=true)], style=tool_lead_words) |> ignore }) |> ignore
    "none" => c.box(style=tool_lead, fn() { c.text(text(part, "text"), style=tool_none) |> ignore }) |> ignore
    "output" =>
      c.box(style=if flag(part, "failed") { tool_box_red } else { tool_box }, fn() {
        c.rich([@ui.span(text(part, "text"), mono=true)], style=if flag(part, "failed") { tool_mono } else { tool_mono_muted })
        |> ignore
      })
      |> ignore
    "json" => c.box(style=tool_box, fn() { c.rich([@ui.span(text(part, "text"), mono=true)], style=tool_mono) |> ignore }) |> ignore
    _ => ()
  }
}

///|
/// Where the turn stands with the model (PhaseLine), under the last item: its pulse in the gutter, the core's words, a
/// clock running.
fn phase_line(c : @ui.Ctx, src : Source, p : Json?) -> Unit {
  let ran = (src.now)() - number(p, "since")
  each_second(c, ran)
  let secs = dmax(ran / second_ms, 0.0).to_int()
  c.box(style=h_main, fn() {
    ev(c, "pulse", "", "", fn() {
      c.box(style=h_state_line, fn() {
        c.text(text(p, "text"), style=if text(p, "phase") == "responding" { h_phase_now } else { h_phase_words }) |> ignore
        c.text("\{secs}s", style=h_phase_time) |> ignore
      })
      |> ignore
    })
  })
  |> ignore
}

///|
/// The steps (historyBody): 12 over, 16 at the sides; a row 14 under the one before; 40 under the last.
// kept across runs: a value (no field of it changes)
let steps_box : @ui.Style = @ui.css("w=Full h=Full")

///|
// kept across runs: a value (no field of it changes)
let steps_waiting : @ui.Style = @ui.css("w=Full h=Full px=S4 pt=S3")

///|
// kept across runs: a value (no field of it changes)
let steps_row_first : @ui.Style = @ui.css("w=Full px=S4 pt=S3")

///|
// kept across runs: a value (no field of it changes)
let steps_row : @ui.Style = @ui.css("w=Full px=S4 pt=S3_5")

///|
// kept across runs: a value (no field of it changes)
let steps_foot : @ui.Style = @ui.css("w=Full h=S10")

///|
/// Its top (historyEdge): 4 over and under, 12 muted, in the middle; on their way, a spinner before the words.
// kept across runs: a value (no field of it changes)
let steps_edge : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full, center=true)

///|
// kept across runs: a value (no field of it changes)
let steps_edge_wait : @ui.Style = @ui.css("row w=Full py=S1 justify=JCenter")

///|
/// An item (hItem): its turn's rule and its events, 8 apart.
// kept across runs: a value (no field of it changes)
let h_item : @ui.Style = @ui.css("w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let h_item_marked : @ui.Style = h_item.then(@ui.css("bg=A(Accent,O10)"))

///|
/// Groups and calls opened as a screen opens (a fixture's), by their keys (an item's key, `/group`, `/<its row>`).
pub fn history_open(keys : Array[String]) -> Unit {
  for k in keys {
    steps_own.opened[k] = true
  }
}

///|
/// The item last gone to (a link's entry), its history's list and its key.
pub fn history_marked() -> (String, String) {
  @signals.untracked(fn() { steps_own.marked.get() })
}

///|
/// How long an item gone to stays marked (History.tsx: 1.6 s).
pub let steps_marked_ms : Double = 1600.0

///|
/// A turn's rule (hTurn): 8 over it, 11 muted, a line on to the edge 8 after the words.
// kept across runs: a value (no field of it changes)
let h_turn : @ui.Style = @ui.css("row w=Full pt=S2 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let h_turn_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
/// An item's events (hMain), 10 apart.
// kept across runs: a value (no field of it changes)
let h_main : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
/// An event (hEv): its 20 gutter and what it is, 8 apart.
// kept across runs: a value (no field of it changes)
let h_ev : @ui.Style = @ui.css("row w=Full gap=S2 align=AStart")

///|
/// The turn's rail: 1 wide, 9.5 in, from under its mark (20) down past the event to the next one's (10 more; 14 to the
/// next item).
// kept across runs: a value (no field of it changes)
let h_rail_room : @ui.Style = @ui.style(w=Full, h=Full, pt=S5, pl=@sf.history_rail_in).then(@sf.outset_bottom(10.0))

///|
// kept across runs: a value (no field of it changes)
let h_rail_room_last : @ui.Style = @ui.style(w=Full, h=Full, pt=S5, pl=@sf.history_rail_in).then(@sf.outset_bottom(14.0))

///|
// kept across runs: a value (no field of it changes)
let h_rail : @ui.Style = @ui.css("w=SPx h=Full bg=Line")

///|
/// A state's block (hEv[data-state]::after): 6 past its gutter, over and under, round as a field, on the neutral ground
/// (waiting the blue's, on a person the accent's).
// kept across runs: a value (no field of it changes)
let h_state : @ui.Style = @ui.css("w=Full h=Full radius=Xl bg=Neutral").then(@sf.outset_start(6.0)).then(@sf.outset_top(6.0)).then(@sf.outset_bottom(6.0))


///|
// kept across runs: a value (no field of it changes)
let h_state_human : @ui.Style = h_state.then(@ui.css("bg=AccentBg"))

///|
/// An event's mark (hIcon): 20 square, on whatever it stands on (a state's block, a group's line pointed at): the
/// turn's rail runs from under it, so nothing of it covers the rail (a ground of its own would stand out as a square
/// on a pane that is not the canvas). As high as its event's first line (ev's `row`), its mark in its middle.
// kept across runs: a value (no field of it changes)
let h_icon : @ui.Style = @ui.css("w=S5 h=S5 align=ACenter justify=JCenter")

///|
/// How high an event's mark is, and a line of its words.
let h_mark : Double = 20.0

///|
/// The model's pulse (activityPulse): a 7 dot in the accent.
// kept across runs: a value (no field of it changes)
let h_pulse : @ui.Style = @ui.style(w=@sf.dot_size, h=@sf.dot_size, radius=Full, bg=Accent)

///|
// kept across runs: a value (no field of it changes)
let h_ev_body : @ui.Style = @ui.style(w=@sf.grow, gap=SPx)

///|
/// Who and where in a line (hLabel): 20 high, 12 muted, 6 apart; who in the words' ink, 600.
// kept across runs: a value (no field of it changes)
let h_label : @ui.Style = @ui.css("row w=Full min_h=S5 gap=S1_5 align=ACenter clip")

///|
// kept across runs: a value (no field of it changes)
let h_label_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let h_strong : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Semibold, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let h_person : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
/// A place (hPlace): its mark and name 4 apart; where it goes, the pointer's ground on it.
// kept across runs: a value (no field of it changes)
let h_place : @ui.Style = @ui.css("row gap=S1 align=ACenter radius=Base clip")

///|
// kept across runs: a value (no field of it changes)
let h_place_hot : @ui.Style = h_place.then(@ui.css("bg=Hover"))

///|
// kept across runs: a value (no field of it changes)
let h_place_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Semibold, color=Fg)

///|
/// A person's words (hWords: 13, the ink); a job's (hOutput: 11 mono on 1.55).
// kept across runs: a value (no field of it changes)
let h_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let h_output : @ui.TextStyle = @ui.text_style(size=Caption, color=Fg, w=Full)

///|
/// A message it sent (hCard): 4 under its line, 8 by 12 in, a line round it, round as a field, on the paper; red when it
/// failed.
// kept across runs: a value (no field of it changes)
let h_card : @ui.Style = @ui.css("w=Full mt=S1 py=S2 px=S3 radius=Xl border=B1 border_color=Line bg=Card")

///|
// kept across runs: a value (no field of it changes)
let h_card_failed : @ui.Style = h_card.then(@ui.css("border_color=Danger"))

///|
/// A fold (fold): its words, cut past its lines; its button under them at their left (textToggle: 12, muted).
// kept across runs: a value (no field of it changes)
let h_fold : @ui.Style = @ui.css("w=Full gap=SPx")

///|
// kept across runs: a value (no field of it changes)
let h_fold_room : @ui.Style = @ui.css("w=Full clip")

///|
// kept across runs: a value (no field of it changes)
let h_fold_inner : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let h_fold_toggle : @ui.Style = @ui.css("row py=S0_5")

///|
// kept across runs: a value (no field of it changes)
let h_toggle_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let h_toggle_hot : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
/// An event in one line (hOne): 20 high, 12 muted (the ink pointed at, red when it failed), 6 apart; 收起 at its end;
/// what it says in whole under it, 2 over and 4 under (hOneBody).
// kept across runs: a value (no field of it changes)
let h_one : @ui.Style = @ui.css("row w=Full min_h=S5 gap=S1_5 align=ACenter clip")

///|
// kept across runs: a value (no field of it changes)
let h_one_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let h_one_hot : @ui.TextStyle = h_one_words.then(@ui.text_style(color=Fg))

///|
// kept across runs: a value (no field of it changes)
let h_one_red : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Danger, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let h_one_fold : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let h_one_fold_hot : @ui.TextStyle = h_one_fold.then(@ui.text_style(color=Fg))

///|
// kept across runs: a value (no field of it changes)
let h_one_body : @ui.Style = @ui.css("w=Full pt=S0_5 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let h_note_plain : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
/// What kind of words a one-line event's are (hTag): 5 in, round 4, on the neutral ground, 11.
// kept across runs: a value (no field of it changes)
let h_tag : @ui.Style = @ui.css("row px=S1_25 radius=Base bg=Neutral")

///|
// kept across runs: a value (no field of it changes)
let h_tag_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let h_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let h_grow_clip : @ui.Style = @ui.style(row=true, w=@sf.grow, clip=true)

///|
/// A state's words in a line (hStateLine): 20 high, 12, 6 apart.
// kept across runs: a value (no field of it changes)
let h_state_line : @ui.Style = @ui.css("row w=Full min_h=S5 gap=S1_5 align=ACenter clip")

///|
// kept across runs: a value (no field of it changes)
let h_state_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted)

///|
/// How much of the most it waits has gone (hWaitBar): a 3 bar under the words, its fill in the blue.
// kept across runs: a value (no field of it changes)
let h_wait_bar : @ui.Style = @ui.style(row=true, w=Full, h=@sf.wait_bar_h, mt=SPx, radius=Full, clip=true, bg=A(Link, O20))

///|
// kept across runs: a value (no field of it changes)
let h_wait_fill : @ui.Style = @ui.css("h=Full bg=Link")

///|
/// A group (hGroup), its line (hGroupHead: the chevron's 20 column, its words, its pills 8 apart; 6 past the column on
/// either side, round as an option, the pointer's ground and the ink on it).
// kept across runs: a value (no field of it changes)
let h_group : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let h_group_head : @ui.Style = @ui.css("row w=Full px=S1_5 gap=S2 align=ACenter radius=Xl hovered{bg=Hover}").then(@sf.outset(6.0))

///|
// kept across runs: a value (no field of it changes)
let h_group_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let h_group_hot : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Fg, wrap=false, w=Cut)

///|
/// Its calls, opened (hSteps): in its words' column (past the 20 gutter and 8), 2 apart, 2 under its line.
// kept across runs: a value (no field of it changes)
let h_steps : @ui.Style = @ui.css("w=Full pl=S7 pt=S0_5 gap=S0_5")

///|
/// A call's line (hStep summary): 5 by 6 in, round 8, 8 apart, 12; the pointer's ground on it.
// kept across runs: a value (no field of it changes)
let h_step : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let h_step_summary : @ui.Style = @ui.css("row w=Full py=S1_25 px=S1_5 gap=S2 align=ACenter radius=Lg hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let h_step_name : @ui.TextStyle = @ui.text_style(size=Meta, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let h_step_name_red : @ui.TextStyle = @ui.text_style(size=Meta, weight=Semibold, color=Danger, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let h_step_hint : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, max_lines=1, w=Full)

///|
// kept across runs: a value (no field of it changes)
let h_step_said : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let h_step_meta : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let h_step_meta_red : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, wrap=false)

///|
/// A step's or thought's words (hStepBody: 4 by 6 in, 8 under, 12); a thought alone (hThinking: 2 over, 6 under and at
/// its start, muted).
// kept across runs: a value (no field of it changes)
let h_step_body : @ui.Style = @ui.css("w=Full pt=S1 px=S1_5 pb=S2")

///|
// kept across runs: a value (no field of it changes)
let h_thinking : @ui.Style = @ui.css("w=Full pt=S0_5 pb=S1_5 pl=S1_5")

///|
// kept across runs: a value (no field of it changes)
let h_thinking_muted : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
/// The thinking streaming in (hLiveThinking): 12 on 20, muted, a line.
// kept across runs: a value (no field of it changes)
let live_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Cut)

///|
/// Where the turn stands (hPhase: 12, muted; responding in the ink), its clock subtle.
// kept across runs: a value (no field of it changes)
let h_phase_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let h_phase_now : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let h_phase_time : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, wrap=false)

///|
/// A call opened (ToolStep.css.ts body): 4 by 6 in, 10 under, the call and what came back 8 apart; each a section, its
/// parts 6 apart (what came back 4).
// kept across runs: a value (no field of it changes)
let tool_body_box : @ui.Style = @ui.css("w=Full pt=S1 px=S1_5 pb=S2_5 gap=S2")

///|
// kept across runs: a value (no field of it changes)
let tool_section : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let tool_result_box : @ui.Style = @ui.css("w=Full gap=S1")

///|
/// A box of words (box): 8 by 12 in, round 10, the ink at 4% over the canvas, 12 mono on 1.55; red's ground when it
/// failed.
// kept across runs: a value (no field of it changes)
let tool_box : @ui.Style = @ui.style(w=Full, py=S2, px=S3, radius=@sf.custom_field_r, bg=@sf.faint_ground)

///|
// kept across runs: a value (no field of it changes)
let tool_box_red : @ui.Style = tool_box.then(@ui.css("bg=DangerBg"))

///|
// kept across runs: a value (no field of it changes)
let tool_mono : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let tool_mono_muted : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let tool_mono_head : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Link, w=Full)

///|
/// The facts (facts): 4 by 10 apart, 11 subtle, a fact's value in mono, muted.
// kept across runs: a value (no field of it changes)
let tool_facts : @ui.Style = @ui.css("row w=Full px=S0_5 gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let tool_fact : @ui.TextStyle = @ui.text_style(size=Caption, color=Subtle, wrap=false)

///|
/// A path (path): 2 in, 12 mono on 1.5, the ink; what of it after, 11 subtle.
// kept across runs: a value (no field of it changes)
let tool_path : @ui.Style = @ui.css("row w=Full px=S0_5 gap=S2 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let tool_path_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let tool_path_extra : @ui.TextStyle = @ui.text_style(size=Caption, color=Subtle, wrap=false)

///|
/// A diff (diff: the box, 6 over and under, no sides; a line's mark 9 in at its start, its words 22, its end 9 in as
/// its start is (what a line on its ground holds as far in from both sides: the web's 12 at its end, beside its mark
/// laid over the line, held it 22 and 12); taken out on the red's ground, put in on the green's, a header in the blue,
/// 4 over it).
// kept across runs: a value (no field of it changes)
let tool_diff : @ui.Style = @ui.style(w=Full, py=S1_5, radius=@sf.custom_field_r, bg=@sf.faint_ground, clip=true)

///|
// kept across runs: a value (no field of it changes)
let tool_diff_line : @ui.Style = @ui.style(row=true, w=Full, pl=@sf.diff_mark_in, pr=@sf.diff_mark_in)

///|
// kept across runs: a value (no field of it changes)
let tool_diff_out : @ui.Style = tool_diff_line.then(@ui.css("bg=DangerBg"))


///|
// kept across runs: a value (no field of it changes)
let tool_diff_head : @ui.Style = tool_diff_line.then(@ui.css("pt=S1"))

///|
/// The gutter a line's mark stands in (taken out or put in), 9 in: as far as its words are 22 in.
// kept across runs: a value (no field of it changes)
let tool_diff_mark : @ui.Style = @ui.style(w=Fixed(@sf.diff_line_in.px() - @sf.diff_mark_in.px()))

///|
/// A line's words: what the gutter leaves.
// kept across runs: a value (no field of it changes)
let tool_diff_words : @ui.Style = @ui.style(w=@sf.grow, min_w=S0)

///|
/// A plan (plan): 2 apart, 2 in, 12; its marks in a 16 column; done struck and muted, under way in 600.
// kept across runs: a value (no field of it changes)
let tool_plan : @ui.Style = @ui.css("w=Full px=S0_5 gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let tool_plan_row : @ui.Style = @ui.css("row w=Full")

///|
// kept across runs: a value (no field of it changes)
let tool_plan_mark : @ui.Style = @ui.css("w=S4")

///|
// kept across runs: a value (no field of it changes)
let tool_plan_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let tool_plan_done : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let tool_plan_now : @ui.TextStyle = @ui.text_style(size=Meta, weight=Semibold, color=Fg, w=@sf.grow)

///|
/// Fields (fields): 4 apart, 2 in; a key in a column 64 wide at least (11 subtle), its value 12 apart (12 mono), long
/// words and data in a box.
// kept across runs: a value (no field of it changes)
let tool_fields : @ui.Style = @ui.css("w=Full px=S0_5 gap=S1")

///|
// kept across runs: a value (no field of it changes)
let tool_field : @ui.Style = @ui.css("row w=Full gap=S3 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let tool_field_key : @ui.Style = @ui.css("min_w=S16")

///|
// kept across runs: a value (no field of it changes)
let tool_key_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tool_value : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let tool_long_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, w=Full)

///|
/// The one thing it asked about (lead): 2 in, 12 mono on 1.5; nothing (none): 11 subtle.
// kept across runs: a value (no field of it changes)
let tool_lead : @ui.Style = @ui.css("w=Full px=S0_5")

///|
// kept across runs: a value (no field of it changes)
let tool_lead_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let tool_none : @ui.TextStyle = @ui.text_style(size=Caption, color=Subtle, w=Full)

///|
/// What agent `key`'s history on `station` says it used, in a line (its `usageLine`): what reads it is told only as the
/// line changes, not as the rest of the history does (what streams in as the agent works: history_steps).
pub fn history_usage_line(src : Source, station : String, key : String) -> String {
  let params : Map[String, Json] = { "station": Json::string(station), "key": Json::string(key) }
  steps_usage_line.read(
    station + "\u{1}" + key,
    fn(_) { text((src.topic)("history", params).value, "usageLine") },
    same=fn(a, b) { a == b },
  )
}

///|
/// What agent `key`'s history on `station` says it used, each figure (its `usage`): told only as they change.
pub fn history_usage(src : Source, station : String, key : String) -> Array[Json] {
  let params : Map[String, Json] = { "station": Json::string(station), "key": Json::string(key) }
  let usage = steps_usage.read(
    station + "\u{1}" + key,
    fn(_) { field((src.topic)("history", params).value, "usage") },
    same=fn(a, b) {
      match (a, b) {
        (Some(x), Some(y)) => physical_equal(x, y)
        (None, None) => true
        _ => false
      }
    },
  )
  match usage {
    Some(Array(a)) => a
    _ => []
  }
}

///|
// kept across runs: what it keeps is let go of by a run anew and by reset (sfbase derived.mbt)
let steps_usage_line : @sfbase.Kept[String] = @sfbase.Kept::new()

///|
// kept across runs: what it keeps is let go of by a run anew and by reset (sfbase derived.mbt)
let steps_usage : @sfbase.Kept[Json?] = @sfbase.Kept::new()
