// An agent's execution history's steps, in any pane (still.fail web/src/History.tsx, History.css.ts; ToolStep.tsx,
// ToolStep.css.ts): what the core put together (its `history` view) drawn turn by turn, each prompt that woke the agent
// beginning one under a rule saying when and what it did; each event a mark in the gutter on the turn's rail and what it
// is beside it. What people were sent leads, on a card; the agent's own words are a grey line; the calls and thoughts
// between fold into a group, a call opening to what it asked for and what came back (the core's reading of them:
// `history.tool`). Long words fold to a few lines. A call or thought in brief is read whole as it is opened
// (`history.detail`), the pages before as the reader nears the top (`history.older`). 只看收发 leaves out what the
// core calls `work`.
//
// They are nodes of the window's tree, laid out from the styles below (style_node), in a page's list that holds each
// row only while it shows (View::scrolls_window). It follows its newest end; the page before is asked for as the reader
// comes within a height of its top, and comes in above what is read, which stays where it is (the list's top, where
// the history begins, holding nothing: what comes in comes under it); an entry gone to is brought to the middle and
// marked a moment.

///|
/// A row of the list as it was picked: the same as another where it is (steps_row_same), so its nodes are made again
/// only as what it shows changes.
priv struct StepsPicked {
  row : StepsRow?
}

///|
impl Eq for StepsPicked with equal(a, b) {
  steps_row_same(a.row, b.row)
}

///|
/// The room kept under the last row (historyBody: 40, steps_foot's).
let steps_foot_room : Double = 40.0

///|
/// How the history stands, for what its node shows: being read the first time (0), with nothing in it (1), its rows (2).
fn steps_state(h : StepsHead) -> Int {
  if h.waiting {
    0
  } else if h.empty {
    1
  } else {
    2
  }
}

///|
/// Agent `key`'s history on `station`, its steps made once in node `v`, which they fill; tips in `tips`.
pub fn history_steps_node(v : @view.View, src : Source, station : String, key : String, tips : @sf.TipLayer) -> Unit {
  let params : Map[String, Json] = { "station": Json::string(station), "key": Json::string(key) }
  let lkey = "history-steps/" + station + "/" + key
  let head = fn() { steps_head_of(src, params, lkey) }
  steps_fills(v)
  v.pick(fn() { steps_state(head()) }, fn(p, state) {
    steps_fills(p)
    match state {
      0 =>
        steps_box_node(p, steps_waiting, fn(b) {
          @sf.waiting_node(b, fn(s) { steps_sample_node(s, station, key, tips) }, note=fn() {
            {
              reading: true,
              text: match head().edge {
                "" => @sf.t("web-main.history.reading")
                e => e
              },
              failing: match head().failed {
                "" => []
                f => [f]
              },
            }
          })
        })
      1 =>
        steps_box_node(p, steps_box, fn(b) {
          // (in the middle across, as steps_edge says: center)
          b.lines_up(Is(Some(Middle))) |> ignore
          steps_words(b, fn() { head().edge }, steps_edge)
        })
      _ => steps_list_node(p, src, station, key, params, lkey, tips)
    }
  })
}

///|
/// The list of agent `key`'s history (its `params`, its list's key `lkey`) in `v`: see the file's head.
fn steps_list_node(
  v : @view.View,
  src : Source,
  station : String,
  key : String,
  params : Map[String, Json],
  lkey : String,
  tips : @sf.TipLayer,
) -> Unit {
  let fk = station + "\u{1}" + key
  // its rows by their keys, in order: its top, each item's by the item's, what is in flight, the phase
  let rows = @signals.computed(fn(_) {
    let (_, all) = steps_rows_of_topic(src, params, lkey)
    let keys : Array[String] = []
    let by : Map[String, StepsRow] = Map([])
    let mut live = 0
    for r in all {
      let k = match r {
        Edge => "edge"
        Item(i, _) => "i/" + text(Some(i), "key")
        Live(_, _) => {
          live = live + 1
          "live/" + live.to_string()
        }
        Phase(_) => "phase"
      }
      keys.push(k)
      by[k] = r
    }
    (keys, by)
  })
  let scroll = @view.Scroll::list()
  // (the item gone to: brought to the middle, its ground the accent's faint one till steps_marked_ms on)
  let place : @view.ListPlace[String] = @view.ListPlace::new()
  let lit : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })
  let unlit = Ref(fn() {  })
  // opened at an entry: the item that draws it brought to the middle, marked a moment; one before what is loaded, the
  // pages before first (below); one 只看收发 leaves out, all of it shown again first
  v.reacts(fn() { (steps_own.focus.get(fk), rows.get().0.length()) }, fn(now) {
    guard now.0 is Some(e) else { return }
    let loaded = items(@signals.untracked(fn() { src.topic("history", params).get().value }), "items")
    match loaded.search_by(fn(i) { entries_of(Some(i)).map(fn(x) { x.0 <= e && e <= x.1 }).unwrap_or(false) }) {
      Some(at) => {
        if steps_own.only_io.untracked() && flag(loaded.get(at), "work") {
          steps_own.only_io.set(false)
        }
        let ik = text(loaded.get(at), "key")
        steps_own.focus.remove(fk)
        steps_own.went[lkey] = true
        steps_own.marked.set((lkey, ik))
        lit.set(ik)
        (unlit.val)()
        unlit.val = v.at_moment(v.cause_at() + steps_marked_ms, fn() { lit.set("") })
        place.centre("i/" + ik)
      }
      None =>
        match loaded.get(0) {
          // (the pages before asked below, as near its top)
          Some(i) if flag(@signals.untracked(fn() { src.topic("history", params).get().value }), "more") &&
            e < entries_of(Some(i)).map(fn(x) { x.0 }).unwrap_or(0) => ()
          // not there: where it opens
          _ => steps_own.focus.remove(fk)
        }
    }
  })
  // The page before, asked of the core while there is one and the core neither reads it nor waits after a read that
  // failed (it says when to ask again): as the list comes within a height of its top (the list's own to say, by where
  // it is held: View::scrolls_window's near_top; kept here as the first row shown and the first item it was told
  // with, a page come in that left that row first was never asked past, its top waiting for ever), and for an entry
  // before what is loaded, once for each first item the pages come above, till the entry is among what is loaded (by
  // the entries themselves: the entry asked for is taken off only as the rows are worked out, after the first item
  // is told, and a page more was asked for with the entry's own page just come).
  let wants_older = fn() {
    let h = steps_head_of(src, params, lkey)
    h.more && h.older == ""
  }
  // (asked once for each first item, whichever asks: near its top and an entry before what is loaded both ask as a
  // page comes, before the core says it reads; again once the core has said it reads or that a read failed)
  let asked_over : Ref[String?] = Ref(None)
  v.reacts(fn() { steps_head_of(src, params, lkey).older }, fn(older) {
    if older != "" {
      asked_over.val = None
    }
  })
  let ask_older = fn() {
    let first = @signals.untracked(fn() { steps_head_of(src, params, lkey).first })
    guard asked_over.val != Some(first) else { return }
    asked_over.val = Some(first)
    (src.call)("history.older", Json::object(params), fn(res) {
      // (an entry asked for before what could be had: where it opens; not asked: asked again as it nears its top)
      if res is Err(_) {
        steps_own.focus.remove(fk)
        asked_over.val = None
      }
    })
  }
  let entry_before = fn() {
    guard steps_own.focus.get(fk) is Some(e) else { return false }
    match items(src.topic("history", params).get().value, "items").get(0) {
      Some(i) => e < entries_of(Some(i)).map(fn(x) { x.0 }).unwrap_or(0)
      None => true
    }
  }
  v.reacts(fn() { (wants_older() && entry_before(), steps_head_of(src, params, lkey).first) }, fn(now) {
    if now.0 {
      ask_older()
    }
  })
  steps_box_node(v, steps_box, fn(b) {
    steps_fills(b)
    b.box(fn(l) {
      steps_fills(l)
      l.scrolls_window(
        scroll,
        fn() { rows.get().0 },
        est=steps_est,
        bar=@ui.tree_scroll_bar(),
        // (the room under its last entry: its foot, drawing nothing)
        foot=fn(f) { f.height(Is(Some(steps_foot_room))) |> ignore },
        // (its top, where it begins or the pages before come, stands over what comes in under it)
        holds=fn(k) { k != "edge" },
        // (followed at its newest; not once gone to an entry)
        follows=fn() { !steps_own.went.contains(lkey) },
        place~,
        // (at once, as it was: a debt of 方案 A, given its way list by list, shown to the owner: list-comes-off)
        at_once=true,
        near_top=(1.0, wants_older, ask_older),
        fn(slot, k) {
          slot.pick(fn() { StepsPicked::{ row: rows.get().1.get(k) } }, fn(p, picked) {
            guard picked.row is Some(row) else { return }
            steps_box_node(p, if row is Edge { steps_row_first } else { steps_row }, fn(r) {
              match row {
                Edge =>
                  r.pick(fn() { steps_head_of(src, params, lkey).more }, fn(e, more) {
                    if more {
                      steps_box_node(e, steps_edge_wait, fn(w) {
                        @sf.wait_line_node(w, fn() { steps_head_of(src, params, lkey).edge }) |> ignore
                      })
                    } else {
                      // (in the middle across, as steps_edge says: center)
                      e.lines_up(Is(Some(Middle))) |> ignore
                      steps_words(e, fn() { steps_head_of(src, params, lkey).edge }, steps_edge)
                    }
                  })
                Item(item, rail) =>
                  history_row_node(r, src, station, key, Some(item), rail, tips, marked=fn() {
                    lit.get() == text(Some(item), "key")
                  })
                Live(l, rail) =>
                  steps_main_node(r, fn(m) {
                    ignore(rail)
                    ev_node(m, "think", "", "", rail_last=true, fn(b) {
                      steps_words(b, fn() { text(Some(l), "text") }, live_words) |> ignore
                    })
                  })
                Phase(ph) => phase_line_node(r, src, Some(ph))
              }
            })
          })
        },
      )
      |> ignore
    })
    |> ignore
  })
}

///|
/// `v` taking the room it is given down its column, no more: as tall as that whatever what it holds asks (its list
/// scrolling in it), never as tall as all of it.
fn steps_fills(v : @view.View) -> Unit {
  v.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
}

///|
/// A box of `look` (laid on it as an old view's box of that style is laid out, style_node) in `parent`, what `make`
/// makes in it; `in_row`: in a row (w=Full and a grow along it).
fn steps_box_node(parent : @view.View, look : @ui.Style, make : (@view.View) -> Unit, in_row? : Bool = false) -> Unit {
  parent.box(fn(b) {
    @sf.style_node(b, fn() { look }, in_row~)
    make(b)
  })
  |> ignore
}

///|
/// Words of `style` in `parent` as they are said: giving way in a row where they cut or wrap (min_width 0).
fn steps_words(parent : @view.View, words : () -> String, style : @ui.TextStyle) -> Unit {
  @sf.words_node(parent, words, fn() { style }).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
}

///|
/// Words of `style` in one run in `parent`: in the code face where `mono`, struck through where `strike`, underlined
/// while `underline` says (Ctx::rich's of one span).
fn steps_run(
  parent : @view.View,
  words : () -> String,
  style : @ui.TextStyle,
  mono? : Bool = false,
  strike? : Bool = false,
  underline? : () -> Bool = fn() { false },
  ink? : () -> Int64 = fn() { 0L },
) -> Unit {
  parent.box(fn(w) {
    w
    .words_runs(By(fn() { [@ui.span(words(), mono~, strike~, underline=underline(), color=ink())] }))
    .words_look(By(fn() { @ui.style_words(style) }))
    .ink(By(fn() { @ui.style_ink(style) }))
    .shrink(Is(1.0))
    .min_width(Is(Some(0.0)))
    |> ignore
    if @ui.style_cut(style) {
      w.cuts(Is(true)).allow_ellipsis(Is(true)) |> ignore
    }
  })
  |> ignore
}

///|
/// A row pressed as a whole in `b`: `press` done as it is, read out a button named `label` (one that `folds` open
/// as `open` says, or shut).
fn steps_pressed(
  b : @view.View,
  press : () -> Unit,
  label? : () -> String = fn() { "" },
  folds? : Bool = false,
  open? : () -> Bool = fn() { false },
) -> Unit {
  @sf.presses_node(b, press)
  b
  .says(By(fn() {
    Some(if folds { @view.said(Button, label=label(), expanded=open()) } else { @view.said(Button, label=label()) })
  }))
  |> ignore
}

///|
/// One of what the reader opens (a fold, a line, a group, a call), by its key, opened or shut (what was pressed
/// staying where it was: mbui's press_stays.mbt).
fn steps_flip(key : String) -> Unit {
  if steps_own.opened.contains(key) {
    steps_own.opened.remove(key)
  } else {
    steps_own.opened[key] = true
  }
}

///|
/// A clock running in `v` from `since` (the core's time: `src.now`), read again each whole second from then as it is
/// shown, no longer than `till` (ms after it, none: on), the test's idle not waiting on it (Ctx::every's): what reads
/// the time of it reads what this returns.
pub fn steps_seconds(v : @view.View, src : Source, since : Double, till? : Double) -> () -> Int {
  let tick : @signals.Signal[Int] = @signals.signal(0)
  fn plan() -> Unit {
    let gone = (src.now)() - since
    if till is Some(t) && gone >= t {
      return
    }
    let into = if gone > 0.0 { gone - (gone / second_ms).floor() * second_ms } else { gone }
    v.at_moment(v.logic_at() + second_ms - into, later=true, fn() {
      tick.set(tick.untracked() + 1)
      plan()
    })
    |> ignore
  }

  plan()
  fn() { tick.get() }
}

///|
/// The history's rows to come while it is read the first time in `v`, as its list draws them.
pub fn steps_sample_node(v : @view.View, station : String, key : String, tips : @sf.TipLayer) -> Unit {
  let lines = [("group", 16), ("text", 24), ("group", 12), ("group", 20), ("text", 9), ("group", 18)]
  for i, line in lines {
    let (kind, n) = line
    let words = Json::string(@sf.sample_words(n))
    let content : Json = if kind == "group" { { "summary": words } } else { { "text": words, "line": words } }
    let item : Map[String, Json] = {
      "key": Json::string("sample" + i.to_string()),
      "body": { "kind": Json::string(kind), "content": content },
    }
    if i == 0 {
      item["turn"] = { "time": Json::string(@sf.sample_words(4)), "text": Json::string(@sf.sample_words(8)) }
    }
    let item = Json::object(item)
    steps_box_node(v, if i == 0 { steps_row_first } else { steps_row }, fn(r) {
      history_row_node(r, @sfbase.sample_source, station, key, Some(item), i + 1 < lines.length(), tips)
    })
  }
}

///|
/// An item in `v`: the rule of the turn it begins, then its events; on the accent's faint ground while
/// `marked` says (an entry gone to).
fn history_row_node(
  v : @view.View,
  src : Source,
  station : String,
  key : String,
  item : Json?,
  rail : Bool,
  tips : @sf.TipLayer,
  marked? : () -> Bool = fn() { false },
) -> Unit {
  let ik = text(item, "key")
  v.box(fn(b) {
    @sf.style_node(b, fn() { h_item })
    // (gone to: on the accent's faint ground a moment, hItem[data-focus])
    b.ground(By(fn() { if marked() { @ui.tree_theme().color(A(Accent, O10)) } else { 0L } })) |> ignore
    match field(item, "turn") {
      Some(Object(_)) as turn =>
        steps_box_node(b, h_turn, fn(t) {
          let said = match text(turn, "time") {
            "" => text(turn, "text")
            time => time + " · " + text(turn, "text")
          }
          t.box(fn(w) {
            w
            .words(Is(said))
            .words_look(By(fn() { @ui.style_words(h_turn_words) }))
            .ink(By(fn() { @ui.style_ink(h_turn_words) }))
            .cuts(Is(true))
            .min_width(Is(Some(0.0)))
            .allow_ellipsis(Is(true))
            |> ignore
          })
          |> ignore
        })
      _ => ()
    }
    steps_main_node(b, fn(m) { item_node(m, src, station, key, ik, item, rail, tips) })
  })
  |> ignore
}

///|
/// An item's events, one under another (hMain).
fn steps_main_node(v : @view.View, body : (@view.View) -> Unit) -> Unit {
  steps_box_node(v, h_main, body)
}

///|
/// One event in `v`: its mark in the gutter and what `body` makes beside it; the turn's rail from under its mark
/// (`rail`: to the next event's; `rail_last`: on to the next item), or a state's block in its colour behind it.
fn ev_node(
  v : @view.View,
  icon : String,
  state : String,
  tone : String,
  rail? : Bool = false,
  rail_last? : Bool = false,
  row? : Bool = false,
  body : (@view.View) -> Unit,
) -> Unit {
  let ink = fn() {
    let t = @sf.theme()
    match (state, tone) {
      ("done", _) => t.p.green
      ("waiting", _) => t.p.blue
      ("human", _) => t.p.accent_text
      (_, "accent") => t.p.accent
      (_, "red") => t.p.red
      _ => t.p.muted
    }
  }
  steps_box_node(v, h_ev, fn(e) {
    if state != "" {
      e.box(fn(o) {
        o.over(Is(true)) |> ignore
        o.box(fn(blk) {
          @sf.style_node(blk, fn() {
            match state {
              "waiting" => h_state.then(@ui.style(bg=Data(@sf.theme().p.blue_bg)))
              "human" => h_state_human
              _ => h_state
            }
          })
        })
        |> ignore
      })
      |> ignore
    } else if rail || rail_last {
      e.box(fn(o) {
        o.over(Is(true)) |> ignore
        o.box(fn(room) {
          @sf.style_node(room, fn() {
            // (from under its mark, in the middle of its first line)
            let line = if row { @sf.row_least() } else { h_mark }
            let under = @sf.room_of((line + h_mark) / 2.0)
            (if rail_last { h_rail_room_last } else { h_rail_room }).then(@ui.style(pt=under))
          })
          steps_box_node(room, h_rail, fn(_) {  })
        })
        |> ignore
      })
      |> ignore
    }
    e.box(fn(i) {
      @sf.style_node(i, fn() {
        // (the first line's height: a line of words' 20, or a row's least)
        let line = if row { @sf.row_least() } else { h_mark }
        h_icon.then(@ui.style(h=Fixed(line)))
      })
      if icon == "pulse" {
        steps_box_node(i, h_pulse, fn(_) {  })
      } else {
        @sf.icon_node(i, icon, 14.0, By(ink)) |> ignore
      }
    })
    |> ignore
    steps_box_node(e, h_ev_body, body, in_row=true)
  })
}

///|
/// What an item is in `v`.
fn item_node(
  v : @view.View,
  src : Source,
  station : String,
  key : String,
  ik : String,
  item : Json?,
  rail : Bool,
  tips : @sf.TipLayer,
) -> Unit {
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
        ev_node(v, "bell", "", "", rail=more, rail_last=!more && rail, row=true, fn(b) {
          one_line_node(b, ik + "/note", fn(l) {
            steps_words(l, fn() { @sf.t("web-main.history.reminder", args=[("name", "still.fail")]) }, h_reminder)
          }, first_line(note), "", fn(w) { steps_words(w, fn() { note }, h_note_plain) })
        })
      }
      for k, task in tasks {
        let more = next()
        task_node(v, ik + "/task/" + k.to_string(), Some(task), more, !more && rail)
      }
      for k, m in messages {
        let more = next()
        received_node(v, src, station, ik + "/message/" + k.to_string(), Some(m), more, !more && rail, tips)
      }
    }
    // the agent's own words reach no one (only what it posts does): a grey line, whole as it is opened
    "text" =>
      ev_node(v, "said", "", "", rail_last=rail, row=true, fn(b) {
        let words = text(content, "text")
        one_line_node(b, ik + "/text", fn(l) {
          // (a chip: in bones one piece)
          l.box(fn(tag) {
            @sf.style_node(tag, fn() { h_tag })
            tag.bone_whole(Is(true)) |> ignore
            steps_words(tag, fn() {
              @sf.t(if flag(content, "subagent") { "web-main.history.subagent" } else { "web-main.history.notSent" })
            }, h_tag_words)
          })
          |> ignore
        }, text(content, "line"), "", fn(w) { md_node(w, words, field(content, "md"), small=true) })
      })
    "post" => {
      let ends = text(content, "ends")
      let failed = flag(content, "failed")
      ev_node(v, "send", "", if failed { "red" } else { "accent" }, rail=ends != "", rail_last=ends == "" && rail, fn(b) {
        steps_box_node(b, h_label, fn(l) {
          label_wraps(l)
          steps_words(l, fn() { @sf.t("web-main.history.sentTo") }, h_label_words)
          match field(content, "place") {
            Some(Object(_)) as p => place_node(l, station, p)
            _ =>
              steps_box_node(l, h_place, fn(pl) {
                @sf.drawable_node(pl, "slack", 12.0) |> ignore
                steps_words(pl, fn() { "Slack" }, h_place_words)
              })
          }
          if flag(content, "block") && ends == "" {
            @sf.badge_node(l, fn() { "Block" }, tone=Blue) |> ignore
          }
          if failed {
            @sf.badge_node(l, fn() { @sf.t("web-main.history.sendFailed") }, tone=Red) |> ignore
          }
        })
        steps_box_node(b, if failed { h_card_failed } else { h_card }, fn(card) {
          card.edge(By(fn() { (1.0, @ui.tree_theme().color(if failed { Danger } else { Line })) })) |> ignore
          let words = text(content, "text")
          fold_node(card, ik + "/post", post_lines, md_line, fn(f) { md_node(f, words, field(content, "md")) })
        })
      })
      if ends != "" {
        ended_node(
          v,
          ends,
          @sf.t(if ends == "human" { "web-main.history.ends.human" } else { "web-main.history.ends.done" }),
          rail,
        )
      }
    }
    "mark" => mark_node(v, src, content, rail)
    "group" => group_node(v, src, station, key, ik, content, rail, tips)
    _ => ()
  }
}

///|
/// Words as Markdown in `v`: the panel's size, or small and grey.
fn md_node(v : @view.View, words : String, md : Json?, small? : Bool = false) -> Unit {
  @sf.markdown_node(v, fn() { words }, tree=fn() { md }, size=fn() { if small { 12.0 } else { 13.0 } }, ink=fn() {
    if small {
      @sf.theme().p.muted
    } else {
      0L
    }
  })
  |> ignore
}

///|
/// An event in one line in `v`: `lead`, then `line` cut at its end; pressed (where there is more), what
/// `whole` makes under it, the line giving way to 收起.
fn one_line_node(
  v : @view.View,
  key : String,
  lead : (@view.View) -> Unit,
  line : String,
  tone : String,
  whole : (@view.View) -> Unit,
) -> Unit {
  let open = fn() { steps_own.opened.contains(key) }
  v.box(fn(r) {
    @sf.style_node(r, fn() { h_one_press.then(@sf.row_least_h()) })
    @sf.presses_node(r, fn() { steps_flip(key) })
    r
    .says(By(fn() {
      Some(@view.said(Button, label=if open() { @sf.t("web-main.fold") } else { line }, expanded=open()))
    }))
    |> ignore
    lead(r)
    r.show(fn() { !open() && line != "" }, fn(l) {
      l.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
      @sf.words_node(l, fn() { line }, fn() {
        if tone == "red" {
          h_one_red
        } else if @sf.lit_node(r) {
          h_one_hot
        } else {
          h_one_words
        }
      })
      |> ignore
    })
    r.show(fn() { !open() }, fn(i) {
      @sf.icon_node(i, "chevron-down", 12.0, By(fn() { if @sf.lit_node(r) { @sf.theme().p.blue } else { @sf.theme().p.muted } })) |> ignore
    })
    r.show(open, fn(o) {
      @sf.style_node(o, fn() { h_one_open })
      o.grow(Is(1.0)) |> ignore
      steps_box_node(o, h_grow, fn(_) {  }, in_row=true)
      @sf.words_node(o, fn() { @sf.t("web-main.fold") }, fn() { if @sf.lit_node(r) { h_one_fold_hot } else { h_one_fold } })
      |> ignore
      @sf.icon_node(o, "chevron-up", 12.0, By(fn() { if @sf.lit_node(r) { @sf.theme().p.accent } else { @sf.theme().p.blue } })) |> ignore
    })
  })
  |> ignore
  // (opening and closing with its room, sizes_steady.mbt)
  @motion.reveal_node(v, open, fn(b) { steps_box_node(b, h_one_body, whole) }, deferred=true) |> ignore
}

///|
/// Long words folded to `lines` lines of `line` in `v`: past that cut, a button under them saying how many
/// more lines there are; pressed, all of them, 收起 under them.
fn fold_node(v : @view.View, key : String, lines : Int, line : Double, body : (@view.View) -> Unit) -> Unit {
  let open = fn() { steps_own.opened.contains(key) }
  // (by the room it is given: how tall what it holds comes to whole at that width, measured as it is laid out, what
  // shows by that laid out in that same layout)
  v.by_room(fn(v, given) {
    let line_h = fn() { @sf.node_sp(v, line) }
    let most = fn() { lines.to_double() * line_h() + 2.0 }
    let inner : Ref[@view.View?] = Ref(None)
    let tall = fn() {
      match inner.val {
        Some(i) => given.tall(i)
        None => 0.0
      }
    }
    let long = fn() { tall() > most() + 4.0 }
    steps_box_node(v, h_fold, fn(f) {
      steps_box_node(f, h_fold_room, fn(room) {
        steps_box_node(room, h_fold_inner, fn(i) {
          i.shrink(Is(0.0)) |> ignore
          inner.val = Some(i)
          body(i)
        })
        // (opening and closing its way, from the moment it is pressed, a Move as long as what is past the cut is
        // tall: all of it at once was a step of that many lines in one frame, what is under it with it)
        let way = @motion.Way::new(if @signals.untracked(open) { 1.0 } else { 0.0 })
        room.reacts(open, fn(o) {
          let past = dmax(0.0, @signals.untracked(tall) - most())
          way.go(if o { 1.0 } else { 0.0 }, @motion.moved().per_unit(past), at=room.cause_at())
        })
        let shown = fn() {
          way.said()
          way.value_at(room.drawn_while(fn(t) { way.goes_at(t) }))
        }
        // (cut from the first: measured whole however short it is cut, View::holds_whole; said once what it measures
        // is made)
        room
        .holds_whole()
        .max_height(By(fn() {
          let k = shown()
          let m = most()
          if k >= 1.0 {
            None
          } else if long() {
            Some(m + (tall() - m) * dmax(0.0, k))
          } else {
            Some(m + 4.0)
          }
        }))
        |> ignore
      })
      f.show(long, fn(t) {
        let words = fn() {
          if open() {
            @sf.t("web-main.fold")
          } else {
            let more = dmax(1.0, ((tall() - most()) / line_h()).round()).to_int()
            @sf.t("web-main.history.more", args=[("n", more.to_string())])
          }
        }
        t.box(fn(b) {
          @sf.style_node(b, fn() { h_fold_toggle.then(@sf.row_least_h()) })
          steps_pressed(b, fn() { steps_flip(key) }, label=words, folds=true, open~)
          @sf.words_node(b, words, fn() { if @sf.lit_node(b) { h_toggle_hot } else { h_toggle_words } }) |> ignore
          @sf.icon_node(b, "chevron-down", 12.0, By(fn() { if @sf.lit_node(b) { @sf.theme().p.accent } else { @sf.theme().p.blue } }), name_now=fn() {
            if open() {
              "chevron-up"
            } else {
              "chevron-down"
            }
          })
          |> ignore
        })
        |> ignore
      })
    })
  })
  |> ignore
}

///|
/// A step's label in `l` going on in the next line where its line has not the room: each part as wide as its words
/// while its line has the room, giving way only alone in a line (a row of parts each giving way squeezed every one of
/// them, 收到来… with its name in two lines, desktop 0.1.7973).
fn label_wraps(l : @view.View) -> Unit {
  l.wraps(Is(Some(0.0))) |> ignore
}

///|
/// A message to the agent in `v`.
fn received_node(
  v : @view.View,
  src : Source,
  station : String,
  key : String,
  m : Json?,
  rail : Bool,
  rail_last : Bool,
  tips : @sf.TipLayer,
) -> Unit {
  let notice = text(m, "notice")
  let job = notice == "job"
  ev_node(v, "received", "", "", rail~, rail_last~, fn(b) {
    steps_box_node(b, h_label, fn(l) {
      label_wraps(l)
      steps_words(l, fn() {
        @sf.t(if job { "web-main.history.jobMessage.before" } else { "web-main.history.message.before" })
      }, h_label_words)
      let from = field(m, "from")
      let user = text(from, "slackUser")
      if user != "" {
        slack_name_node(l, src, station, user, text(from, "name"), flag(from, "bound"), tips)
      } else {
        steps_words(l, fn() { if notice == "stillfail" { @sf.product() } else { text(from, "name") } }, h_strong)
      }
      steps_words(l, fn() {
        @sf.t(if job { "web-main.history.jobMessage.after" } else { "web-main.history.message.after" })
      }, h_label_words)
      match field(m, "place") {
        Some(Object(_)) as p =>
          // (the dot going on with its place, never left at a line's end)
          steps_box_node(l, h_label_place, fn(dp) {
            dp.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
            steps_words(dp, fn() { "·" }, h_label_words)
            place_node(dp, station, p)
          })
        _ => ()
      }
    })
    let words = text(m, "text")
    match field(m, "md") {
      Some(Array(_)) as md => fold_node(b, key, words_lines, md_line, fn(f) { md_node(f, words, md) })
      _ =>
        fold_node(b, key, words_lines, words_line, fn(f) {
          if job {
            steps_run(f, fn() { words }, h_output, mono=true)
          } else {
            steps_words(f, fn() { words }, h_words)
          }
        })
    }
  })
}

///|
/// A place as its platform's mark and its name in `v` (the library's place_node): a Slack thread opens in Slack, a
/// still.fail chat its page.
fn place_node(v : @view.View, station : String, place : Json?) -> Unit {
  let url = text(place, "url")
  let session = text(place, "session")
  let press = if url != "" || session != "" {
    Some(fn() {
      if url != "" {
        @sfbase.open_slack(text(place, "app"), url) |> ignore
      } else {
        @sfbase.history_push()
        app.nav.push(Chat({ station, session, title: text(place, "name"), station_name: "" }))
      }
    })
  } else {
    None
  }
  @sf.place_node(
    v,
    fn() { text(place, "surface") },
    fn() { text(place, "name") },
    fn(hot) { if hot { h_place_hot } else { h_place } },
    match press {
      Some(_) => h_place_link_words
      None => h_place_words
    },
    press~,
  )
  |> ignore
}

///|
/// A Slack user's name in `v`: pressed, 这是我 or 不是我 in its menu beside it; turning while the station
/// is told, a red mark a few seconds if that failed (its tip in `tips`).
fn slack_name_node(
  v : @view.View,
  src : Source,
  station : String,
  user : String,
  name : String,
  bound : Bool,
  tips : @sf.TipLayer,
) -> Unit {
  let on = [("station", station), ("user", user)]
  let saying = fn() { core_doing(src, ["slack.identity"], on) }
  steps_box_node(v, h_person, fn(p) {
    @sf.presses_node(
      p,
      fn() {
        let words = if bound { @sf.t("web-main.history.notMe") } else { @sf.t("web-main.history.isMe") }
        let (x, y, w, h) = p.placed_window_now()
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
          from=At(x, y, w, h),
        )
      },
      on=fn() { !saying() },
    )
    steps_run(p, fn() { name }, h_strong_link, underline=fn() { @sf.lit_node(p) && !saying() })
    p.show(fn() { !saying() }, fn(i) {
      @sf.icon_node(i, "chevron-down", 10.0, By(fn() { @sf.theme().p.blue })) |> ignore
    })
    p.show(saying, fn(s) { @sf.spinner_node(s, size=12.0) |> ignore })
    p.show(fn() { !saying() && core_failed(src, ["slack.identity"], on) is Some(_) }, fn(f) {
      @sf.icon_node(f, "info", 12.0, By(fn() { @sf.theme().p.red })) |> ignore
      @sf.tip_node(tips, f, fn() {
        match core_failed(src, ["slack.identity"], on) {
          Some("") | None => @sf.t("web-main.doing.failed")
          Some(why) => why
        }
      })
      |> ignore
    })
  })
}

///|
/// Work the agent started in the background, ended in `v`.
fn task_node(v : @view.View, key : String, task : Json?, rail : Bool, rail_last : Bool) -> Unit {
  let failed = flag(task, "failed")
  let answer = text(task, "result")
  let has = field(task, "md") is Some(Array(_)) && answer != ""
  let agent = flag(task, "agent")
  ev_node(v, if agent { "agent" } else { "command" }, "", if failed { "red" } else { "" }, rail~, rail_last~, row=has, fn(b) {
    if !has {
      steps_box_node(b, h_one_wrap, fn(o) { steps_words(o, fn() { text(task, "text") }, if failed { h_one_red_wrap } else { h_one_words_wrap }) })
    } else {
      one_line_node(b, key, fn(_) {  }, text(task, "text"), if failed { "red" } else { "" }, fn(w) {
        if agent {
          md_node(w, answer, field(task, "md"), small=true)
        } else {
          steps_run(w, fn() { answer }, h_output, mono=true)
        }
      })
      b.show(fn() { !steps_own.opened.contains(key) }, fn(s) {
        steps_box_node(s, h_one, fn(o) { steps_run(o, fn() { text(task, "line") }, h_one_words, mono=!agent) })
      })
    }
  })
}

///|
/// A turn's state in `v`: waiting on work it started (counting on each second while it does, a bar
/// filling toward the most it waits), done, or waiting on a person.
fn mark_node(v : @view.View, src : Source, mark : Json?, rail : Bool) -> Unit {
  let wait = field(mark, "wait")
  guard wait is Some(Object(_)) else {
    ended_node(v, text(mark, "ends"), text(mark, "text"), rail)
    return
  }
  let still = !(field(wait, "until") is Some(Number(_)))
  let since = number(wait, "since")
  let most = match opt_number(wait, "seconds") {
    Some(sec) if sec > 0.0 => Some(sec * second_ms)
    _ => None
  }
  ev_node(v, "wait", if still { "waiting" } else { "waited" }, "", rail_last=rail, fn(b) {
    let tick = if still { steps_seconds(b, src, since, till?=most) } else { fn() { 0 } }
    steps_box_node(b, h_state_line, fn(l) {
      steps_words(l, fn() {
        if !still {
          return text(mark, "text")
        }
        tick() |> ignore
        let ran = (src.now)() - since
        let what = match text(wait, "what") {
          "" => ""
          w => w + " · "
        }
        let waited = match most {
          Some(m) => elapsed(if ran < m { ran } else { m }) + " / " + elapsed(m)
          None => elapsed(ran)
        }
        what + @sf.t("web-main.activity.waiting") + " " + waited
      }, h_state_words)
    })
    match most {
      Some(m) if still =>
        // how much of the most it waits has gone (WaitBar: a clock, not a motion)
        steps_box_node(b, h_wait_bar, fn(bar) {
          bar.box(fn(fill) {
            @sf.style_node(fill, fn() { h_wait_fill }, in_row=true)
            fill.width_share(By(fn() {
              tick() |> ignore
              dmin(1.0, dmax(0.0, ((src.now)() - since) / m))
            }))
            |> ignore
          })
          |> ignore
        })
      _ => ()
    }
  })
}

///|
/// How a turn ended in `v`.
fn ended_node(v : @view.View, ends : String, words : String, rail : Bool) -> Unit {
  let (icon, state) = match ends {
    "human" => ("user", "human")
    "done" => ("check-circle", "done")
    "waiting" => ("wait", "waited")
    _ => ("info", "other")
  }
  ev_node(v, icon, state, "", rail_last=rail, fn(b) {
    steps_box_node(b, h_state_line, fn(l) { steps_words(l, fn() { words }, h_state_words) })
  })
}

///|
/// A group of calls and thoughts in `v`: its line, all of it opening the group (its title its tip, in
/// `tips`); opened, a line each beside the turn's rail.
fn group_node(
  v : @view.View,
  src : Source,
  station : String,
  key : String,
  ik : String,
  g : Json?,
  rail : Bool,
  tips : @sf.TipLayer,
) -> Unit {
  let gk = ik + "/group"
  let open = fn() { steps_own.opened.contains(gk) }
  let failures = number(g, "failures").to_int()
  let pending = number(g, "pending").to_int()
  let rows = items(g, "rows")
  let calls = rows.iter().any(fn(r) { text(Some(r), "kind") == "step" })
  steps_box_node(v, h_group, fn(gv) {
    if rail {
      gv.box(fn(o) {
        o.over(Is(true)) |> ignore
        o.box(fn(room) {
          @sf.style_node(room, fn() {
            // (from under its chevron mark, in the middle of the group header row)
            let under = @sf.room_of((@sf.row_least() + h_mark) / 2.0)
            h_rail_room_last.then(@ui.style(pt=under))
          })
          steps_box_node(room, h_rail, fn(_) {  })
        })
        |> ignore
      })
      |> ignore
    }
    gv.box(fn(h) {
      @sf.style_node(h, fn() { h_group_head.then(@sf.row_least_h()) })
      let hot = fn() { @sf.lit_node(h) }
      h.ground(By(fn() { if @sf.lit_in_node(h) { @ui.tree_theme().color(Hover) } else { 0L } }))
      |> ignore
      steps_pressed(h, fn() { steps_flip(gk) }, label=fn() { text(g, "summary") }, folds=true, open~)
      h.box(fn(i) {
        @sf.style_node(i, fn() { h_icon })
        @sf.icon_node(i, "chevron-right", 14.0, By(fn() { if hot() { @sf.theme().p.text } else { @sf.theme().p.muted } }), name_now=fn() {
          if open() {
            "chevron-down"
          } else {
            "chevron-right"
          }
        })
        |> ignore
      })
      |> ignore
      steps_box_node(h, h_grow_clip, fn(w) {
        w.box(fn(r) {
          r
          .words_runs(By(fn() { [@ui.span(text(g, "summary"), mono=calls)] }))
          .words_look(By(fn() { @ui.style_words(h_group_words) }))
          .ink(By(fn() { @ui.style_ink(if hot() { h_group_hot } else { h_group_words }) }))
          .cuts(Is(true))
          .min_width(Is(Some(0.0)))
          .allow_ellipsis(Is(true))
          |> ignore
        })
        |> ignore
      }, in_row=true)
      if failures > 0 {
        @sf.badge_node(h, fn() { @sf.t("web-main.history.failures", args=[("n", failures.to_string())]) }, tone=Red)
        |> ignore
      }
      if pending > 0 {
        @sf.badge_node(h, fn() { @sf.t("web-main.history.pending", args=[("n", pending.to_string())]) }, tone=Accented)
        |> ignore
      }
      match text(g, "title") {
        "" => ()
        title => @sf.tip_node(tips, h, fn() { title }) |> ignore
      }
    })
    |> ignore
    @motion.reveal_node(gv, open, deferred=true, fn(s) {
      steps_box_node(s, h_steps, fn(list) {
        for i, row in rows {
          let rv = Some(row)
          let content = field(rv, "content")
          let rk = gk + "/" + i.to_string()
          if text(rv, "kind") == "thought" {
            if calls {
              opened_node(list, src, station, key, rk, content, fn(sum) {
                steps_words(sum, fn() { @sf.t("web-main.history.thinking") }, h_step_name)
                steps_box_node(sum, h_grow_clip, fn(c) { steps_words(c, fn() { text(content, "first") }, h_step_hint_line) }, in_row=true)
              }, fn(body) { steps_box_node(body, h_step_body, fn(t) { md_node(t, text(content, "text"), field(content, "md"), small=true) }) })
            } else {
              whole_node(list, src, station, key, rk, content, fn(body) {
                steps_box_node(body, h_thinking, fn(t) { md_node(t, text(content, "text"), field(content, "md"), small=true) })
              })
            }
          } else {
            step_node(list, src, station, key, rk, content)
          }
        }
      })
    })
    |> ignore
  })
}

///|
/// A call in `v`: its line; opened, what it asked for and what came back.
fn step_node(v : @view.View, src : Source, station : String, key : String, rk : String, step : Json?) -> Unit {
  let failed = flag(step, "failed")
  opened_node(v, src, station, key, rk, step, fn(sum) {
    match text(step, "said") {
      "" => {
        steps_words(sum, fn() { text(step, "name") }, if failed { h_step_name_red } else { h_step_name })
        steps_box_node(sum, h_grow_clip, fn(c) { steps_run(c, fn() { text(step, "hint") }, h_step_hint_line, mono=true) }, in_row=true)
      }
      said => steps_box_node(sum, h_grow_clip, fn(c) { steps_words(c, fn() { said }, h_step_said) }, in_row=true)
    }
    @sf.words_node(sum, fn() { text(step, "meta") }, fn() { if failed { h_step_meta_red } else { h_step_meta } }).shrink(Is(0.0)) |> ignore
  }, fn(body) { tool_body_node(body, src, rk, step) })
}

///|
/// A line of a group that opens to what is behind it in `v`; in brief, read whole as it is opened.
fn opened_node(
  v : @view.View,
  src : Source,
  station : String,
  key : String,
  rk : String,
  content : Json?,
  summary : (@view.View) -> Unit,
  body : (@view.View) -> Unit,
) -> Unit {
  let open = fn() { steps_own.opened.contains(rk) }
  steps_box_node(v, h_step, fn(s) {
    s.box(fn(line) {
      @sf.style_node(line, fn() { h_step_summary.then(@sf.row_least_h()) })
      line.ground(By(fn() { if @sf.lit_in_node(line) { @ui.tree_theme().color(Hover) } else { 0L } }))
      |> ignore
      steps_pressed(line, fn() { steps_flip(rk) }, folds=true, open~)
      summary(line)
      @sf.icon_node(
        line,
        "chevron-right",
        12.0,
        By(fn() { if @sf.lit_in_node(line) { @sf.theme().p.blue } else { @sf.theme().p.muted } }),
        name_now=fn() {
          if open() {
            "chevron-down"
          } else {
            "chevron-right"
          }
        },
      )
      |> ignore
    })
    |> ignore
    @motion.reveal_node(s, open, fn(o) { whole_node(o, src, station, key, rk, content, body) }, deferred=true) |> ignore
  })
}

///|
/// What a step or thought holds as it shows in `v`: in brief, read whole now (`history.detail`), a line saying
/// so till it comes (or why it did not).
fn whole_node(
  v : @view.View,
  src : Source,
  station : String,
  key : String,
  rk : String,
  content : Json?,
  body : (@view.View) -> Unit,
) -> Unit {
  if !flag(content, "brief") {
    body(v)
    return
  }
  let entries = items(content, "entries").map(fn(e) {
    match e {
      Number(n, ..) => n
      _ => 0.0
    }
  })
  // (asked once as it first shows)
  v.reacts(fn() { steps_own.detail.contains(rk) }, fn(has) {
    guard !has && entries.length() > 0 else { return }
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
  v.pick(fn() {
    match steps_own.detail.get(rk) {
      Some((-2.0, why)) => why
      _ => "\u{0}"
    }
  }, fn(p, why) {
    steps_box_node(p, h_step_body, fn(b) {
      if why == "\u{0}" {
        @sf.wait_line_node(b, fn() { "" }) |> ignore
      } else {
        steps_words(b, fn() { @sf.t("web-main.history.stepUnread", args=[("error", why)]) }, h_thinking_muted)
      }
    })
  })
}

///|
/// A call opened in `v`: what it asked for, then what came back, as the core reads them (`history.tool`),
/// asked once as it is first shown.
fn tool_body_node(v : @view.View, src : Source, rk : String, step : Json?) -> Unit {
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
  v.reacts(fn() { steps_own.tools.contains(tk) }, fn(has) {
    guard !has else { return }
    (src.call)("history.tool", Json::object(ask), fn(res) {
      match res {
        Ok(got) => steps_own.tools[tk] = got
        Err(_) => ()
      }
    })
  })
  v.pick(fn() { steps_own.tools.contains(tk) }, fn(p, has) {
    guard has else {
      steps_box_node(p, h_step_body, fn(b) { @sf.wait_line_node(b, fn() { "" }) |> ignore })
      return
    }
    let parts = @signals.untracked(fn() { steps_own.tools.get(tk) })
    steps_box_node(p, tool_body_box, fn(b) {
      steps_box_node(b, tool_section, fn(s) {
        for part in items(parts, "call") {
          tool_part_node(s, Some(part))
        }
      })
      match field(parts, "result") {
        Some(Array(list)) =>
          steps_box_node(b, tool_result_box, fn(s) {
            for part in list {
              tool_part_node(s, Some(part))
            }
          })
        _ => ()
      }
    })
  })
}

///|
/// A list of things to do in `v`, each `{text, status}`, as `list` says it now: done ✓ struck and muted, under way › in
/// 600, the rest ·. A plan call's in the history, and an agent's checklist in the panel of its work (agent_work_node):
/// a row each by its place in the list, its mark and words as its item says them now, one more or less coming and
/// going as the list changes (View::each).
fn plan_node(v : @view.View, list : () -> Array[Json]) -> Unit {
  steps_box_node(v, tool_plan, fn(p) {
    p.each(fn() { list().mapi(fn(i, it) { (i, it) }) }, fn(x) { x.0 }, fn(row, item) {
      let status = fn() { text(Some(item.get().1), "status") }
      let words = fn() {
        match status() {
          "completed" => tool_plan_done
          "in_progress" => tool_plan_now
          _ => tool_plan_words
        }
      }
      let mark_ink = fn() {
        match status() {
          "completed" => @sf.theme().p.green
          "in_progress" => @sf.theme().p.accent
          _ => @sf.theme().p.subtle
        }
      }
      steps_box_node(row, tool_plan_row, fn(r) {
        steps_box_node(r, tool_plan_mark, fn(m) {
          m.box(fn(w) {
            w
            .words(By(fn() {
              match status() {
                "completed" => "✓"
                "in_progress" => "›"
                _ => "·"
              }
            }))
            .words_look(By(fn() { @ui.style_words(tool_plan_words) }))
            .ink(By(mark_ink))
            |> ignore
          })
          |> ignore
        })
        // (the room its mark leaves, from none: its words wrapped at that width, not at the row's)
        r.box(fn(w) {
          w.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
          w.box(fn(x) {
            x
            .words_runs(By(fn() { [@ui.span(text(Some(item.get().1), "text"), strike=status() == "completed")] }))
            .words_look(By(fn() { @ui.style_words(words()) }))
            .ink(By(fn() { @ui.style_ink(words()) }))
            .shrink(Is(1.0))
            .min_width(Is(Some(0.0)))
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
    })
  })
}

///|
/// One part of a call or of what came back in `v`.
fn tool_part_node(v : @view.View, part : Json?) -> Unit {
  let mono_box = fn(look : @ui.Style, words : String, style : @ui.TextStyle) {
    steps_box_node(v, look, fn(b) { steps_run(b, fn() { words }, style, mono=true) })
  }
  match text(part, "kind") {
    "code" =>
      v.box(fn(b) { @sf.code_block_node(b, fn() { text(part, "text") }, fn() { text(part, "lang") }, fn() { None }) })
      |> ignore
    "facts" =>
      steps_box_node(v, tool_facts, fn(f) {
        f.wraps(Is(Some(4.0))) |> ignore
        for fact in items(part, "items") {
          let fv = Some(fact)
          match field(fv, "value") {
            Some(String(value)) if !flag(fv, "plain") =>
              f.box(fn(w) {
                w
                .words_runs(By(fn() {
                  [
                    @ui.span(text(fv, "key") + " "),
                    @ui.span(value, mono=true, color=@sf.theme().p.muted, weight=500),
                  ]
                }))
                .words_look(By(fn() { @ui.style_words(tool_fact) }))
                .ink(By(fn() { @ui.style_ink(tool_fact) }))
                .shrink(Is(1.0))
                .min_width(Is(Some(0.0)))
                |> ignore
              })
              |> ignore
            _ => steps_words(f, fn() { text(fv, "key") }, tool_fact)
          }
        }
      })
    "path" =>
      steps_box_node(v, tool_path, fn(p) {
        p.box(fn(w) {
          w.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
          steps_run(w, fn() { text(part, "path") }, tool_path_words, mono=true)
        })
        |> ignore
        match text(part, "extra") {
          "" => ()
          e => @sf.words_node(p, fn() { e }, fn() { tool_path_extra }).shrink(Is(0.0)) |> ignore
        }
      })
    "diff" =>
      steps_box_node(v, tool_diff, fn(d) {
        for r in items(part, "rows") {
          match r {
            Array([String(mark), String(line)]) =>
              d.box(fn(l) {
                @sf.style_node(l, fn() {
                  match mark {
                    "-" => tool_diff_out
                    "+" => tool_diff_line.then(@ui.style(bg=Data(@sf.theme().p.green_bg)))
                    "@" => tool_diff_head
                    _ => tool_diff_line
                  }
                })
                // (in the theme's inks as it is now: the dark one's where it is told to be dark)
                let ink = fn() {
                  match mark {
                    "-" => @sf.theme().p.red
                    "+" => @sf.theme().p.green_ink
                    _ => @sf.theme().p.subtle
                  }
                }
                // (its mark in the gutter before its words, the line's ends as far in either side)
                steps_box_node(l, tool_diff_mark, fn(m) {
                  if mark == "-" || mark == "+" {
                    steps_run(m, fn() { mark }, tool_mono, mono=true, ink~)
                  }
                })
                steps_box_node(l, tool_diff_words, fn(w) {
                  steps_run(w, fn() { if line == "" { " " } else { line } }, match mark {
                    "@" => tool_mono_head
                    " " => tool_mono_muted
                    _ => tool_mono
                  }, mono=true)
                }, in_row=true)
              })
              |> ignore
            _ => ()
          }
        }
      })
    "markdown" => steps_box_node(v, tool_box, fn(b) { md_node(b, text(part, "text"), field(part, "md"), small=true) })
    "plan" => plan_node(v, fn() { items(part, "items") })
    "fields" =>
      steps_box_node(v, tool_fields, fn(fs) {
        for r in items(part, "rows") {
          let rv = Some(r)
          steps_box_node(fs, tool_field, fn(f) {
            steps_box_node(f, tool_field_key, fn(k) { steps_words(k, fn() { text(rv, "key") }, tool_key_words) })
            steps_box_node(f, h_grow, fn(g) {
              match text(rv, "form") {
                "long" => steps_box_node(g, tool_box, fn(b) { steps_words(b, fn() { text(rv, "value") }, tool_long_words) })
                "json" => steps_box_node(g, tool_box, fn(b) { steps_run(b, fn() { text(rv, "value") }, tool_mono, mono=true) })
                _ => steps_run(g, fn() { text(rv, "value") }, tool_value, mono=true)
              }
            }, in_row=true)
          })
        }
      })
    "lead" => mono_box(tool_lead, text(part, "text"), tool_lead_words)
    "none" => steps_box_node(v, tool_lead, fn(b) { steps_words(b, fn() { text(part, "text") }, tool_none) })
    "output" =>
      mono_box(if flag(part, "failed") { tool_box_red } else { tool_box }, text(part, "text"), if flag(part, "failed") {
        tool_mono
      } else {
        tool_mono_muted
      })
    "json" => mono_box(tool_box, text(part, "text"), tool_mono)
    _ => ()
  }
}

///|
/// Where the turn stands with the model in `v`: its pulse in the gutter, the core's words, a clock
/// running each second.
fn phase_line_node(v : @view.View, src : Source, p : Json?) -> Unit {
  let since = number(p, "since")
  steps_main_node(v, fn(m) {
    let tick = steps_seconds(m, src, since)
    ev_node(m, "pulse", "", "", fn(b) {
      steps_box_node(b, h_state_line, fn(l) {
        steps_words(l, fn() { text(p, "text") }, if text(p, "phase") == "responding" { h_phase_now } else { h_phase_words })
        steps_words(l, fn() {
          tick() |> ignore
          let secs = dmax(((src.now)() - since) / second_ms, 0.0).to_int()
          "\{secs}s"
        }, h_phase_time)
      })
    })
  })
}

///|
/// A call's hint and a thought's first words on their line, cut at its end (h_step_hint's, one line).
// kept across runs: a value (no field of it changes)
let h_step_hint_line : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=Cut)

///|
/// What the steps keep of their own (the rest is the core's): what the reader opened (folds, lines, groups, calls), by
/// their keys; the entries read whole (by the step's key: when they came, -1 asked, -2 failed and why); what the core
/// said each opened call is (`history.tool`, by its key). What
/// a row shows of them it reads, followed (a row is kept while nothing it read changed: history_steps_node).
priv struct StepsOwn {
  opened : @sf.LiveMap[String, Bool]
  detail : @sf.LiveMap[String, (Double, String)]
  tools : @sf.LiveMap[String, Json]
  /// an entry asked to be brought into view, by history (`<station>\u{1}<key>`); the item gone to, marked a moment
  /// (its history's list, its key), and the histories gone to an entry, not following their newest since
  focus : @sf.LiveMap[String, Int]
  marked : @signals.Signal[(String, String)]
  went : Map[String, Bool]
  /// each history's first item as its list was last built, by the list's key
  tops : Map[String, String]
  /// 只看收发, for every history (as the web keeps it): a signal, what each history's rows are worked out by
  only_io : @signals.Signal[Bool]
}

///|
let steps_own : StepsOwn = {
  opened: @sf.LiveMap::new(),
  detail: @sf.LiveMap::new(),
  tools: @sf.LiveMap::new(),
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
  steps_own.focus.clear()
  steps_own.marked.set(("", ""))
  steps_own.went.clear()
  steps_own.tops.clear()
  steps_own.only_io.set(false)
}

///|
/// Whether a history shows only what came in and went out.
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
/// How an agent's history's steps stand (what builds them reads of it): read yet, why its read failed (read again),
/// none, what its top says, whether there are pages before and how the page before stands (reading, failed, or ""),
/// how many rows and its first item's key.
#derive(Eq)
priv struct StepsHead {
  waiting : Bool
  failed : String
  empty : Bool
  edge : String
  more : Bool
  older : String
  rows : Int
  first : String
}

///|
/// Each history's StepsHead, by its list's key: told only as it comes out otherwise.
// kept across runs: what it keeps is let go of by a run anew and by reset (sfbase derived.mbt)
let steps_head : @sfbase.Kept[StepsHead] = @sfbase.Kept::new()

///|
fn steps_head_of(src : Source, params : Map[String, Json], lkey : String) -> StepsHead {
  steps_head.read(
    src,
    lkey,
    fn(_) {
      let h = src.topic("history", params).get().value
      let empty = flag(h, "empty")
      let waiting = !(h is Some(Object(_))) || (empty && !flag(h, "loaded"))
      let (all, rows) = if waiting || empty { ([], []) } else { steps_rows_of_topic(src, params, lkey) }
      {
        waiting,
        failed: text(h, "failed"),
        empty,
        edge: text(h, "edge"),
        more: flag(h, "more"),
        older: text(h, "older"),
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
  steps_rows.read(src, lkey, fn(_) {
    let h = src.topic("history", params).get().value
    steps_rows_of(h, items(h, "items"), steps_own.only_io.get())
  })
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
/// The lines a sent message and a person's words show folded, and how tall a line of each is.
let post_lines : Int = 6

///|
let words_lines : Int = 4

///|
let md_line : Double = 23.0

///|
let words_line : Double = 20.0

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
/// Groups and calls opened as a screen opens (a fixture's), by their keys (an item's key, `/group`, `/<its row>`).
pub fn history_open(keys : Array[String]) -> Unit {
  for k in keys {
    steps_own.opened[k] = true
  }
}

///|
/// The item last gone to (a link's entry), its history's list and its key.
pub fn history_marked() -> (String, String) {
  steps_own.marked.untracked()
}

///|
/// How long an item gone to stays marked.
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
let h_strong_link : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Semibold, color=Link)

///|
/// A reminder's label stays on one line; its preview gives way when the row is narrow.
// kept across runs: a value (no field of it changes)
let h_reminder : @ui.TextStyle = h_strong.then(@ui.text_style(wrap=false))

///|
// kept across runs: a value (no field of it changes)
let h_label_place : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

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
// kept across runs: a value (no field of it changes)
let h_place_link_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Semibold, color=Link)

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
let h_fold_toggle : @ui.Style = @ui.css("row py=S0_5 gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let h_toggle_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Link, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let h_toggle_hot : @ui.TextStyle = @ui.text_style(size=Meta, color=Accent, wrap=false)

///|
/// An event in one line (hOne): 20 high, 12 muted (the ink pointed at, red when it failed), 6 apart; 收起 at its end;
/// what it says in whole under it, 2 over and 4 under (hOneBody).
// kept across runs: a value (no field of it changes)
let h_one : @ui.Style = @ui.css("row w=Full min_h=S5 gap=S1_5 align=ACenter clip")

///|
// kept across runs: a value (no field of it changes)
let h_one_press : @ui.Style = h_one.then(@ui.css("radius=Lg hovered{bg=Hover}"))

///|
// kept across runs: a value (no field of it changes)
let h_one_open : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let h_one_wrap : @ui.Style = @ui.css("w=Full min_h=S5")

///|
// kept across runs: a value (no field of it changes)
let h_one_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let h_one_words_wrap : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let h_one_hot : @ui.TextStyle = h_one_words.then(@ui.text_style(color=Fg))

///|
// kept across runs: a value (no field of it changes)
let h_one_red : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Danger, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let h_one_red_wrap : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Danger, w=Full)

///|
// kept across runs: a value (no field of it changes)
let h_one_fold : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Link, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let h_one_fold_hot : @ui.TextStyle = h_one_fold.then(@ui.text_style(color=Accent))

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
let h_group_head : @ui.Style = @ui.css("row w=Full px=S1_5 gap=S2 align=ACenter radius=Lg hovered{bg=Hover}").then(@sf.outset(6.0))

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
let h_step_name : @ui.TextStyle = @ui.text_style(size=Meta, weight=Semibold, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let h_step_name_red : @ui.TextStyle = @ui.text_style(size=Meta, weight=Semibold, color=Danger, wrap=false, w=Cut)

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
/// A call opened: 4 by 6 in, 10 under, the call and what came back 8 apart; each a section, its
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
let tool_fact : @ui.TextStyle = @ui.text_style(size=Caption, color=Subtle)

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
/// line changes, not as the rest of the history does (what streams in as the agent works: history_steps_node).
pub fn history_usage_line(src : Source, station : String, key : String) -> String {
  let params : Map[String, Json] = { "station": Json::string(station), "key": Json::string(key) }
  steps_usage_line.read(
    src,
    station + "\u{1}" + key,
    fn(_) { text(src.topic("history", params).get().value, "usageLine") },
    same=fn(a, b) { a == b },
  )
}

///|
/// What agent `key`'s history on `station` says it used, each figure (its `usage`): told only as they change.
pub fn history_usage(src : Source, station : String, key : String) -> Array[Json] {
  let params : Map[String, Json] = { "station": Json::string(station), "key": Json::string(key) }
  let usage = steps_usage.read(
    src,
    station + "\u{1}" + key,
    fn(_) { field(src.topic("history", params).get().value, "usage") },
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

///|
/// What needs seeing to in an agent's history now (HistorySummary), as `a` (the chat's agent) says it, in `parent`'s
/// row: a quota running out (its chip, what it says and more over it while it is pointed at, in `tips`), the disk
/// filling up (in `amber`), an account that cannot run (in `red`).
pub fn history_attention_node(
  parent : @view.View,
  a : () -> Json?,
  tips : @sf.TipLayer,
  amber : @ui.TextStyle,
  red : @ui.TextStyle,
) -> Unit {
  let notes = fn() { items(a(), "attention") }
  parent.each(fn() { Array::makei(notes().length(), fn(i) { i }) }, fn(i) { i }, fn(c, i) {
    c.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    let k = i.untracked()
    let n = fn() { notes().get(k) }
    let q = fn() { field(n(), "quota") }
    c.pick(fn() { q() is Some(Object(_)) }, fn(x, quota) {
      if quota {
        @sf.fill_chip_node(
          x,
          fn() { number(q(), "left").to_int() },
          fn() { text(q(), "level") },
          fn() { text(q(), "mark") },
          fn() { number(q(), "left").to_int().to_string() + "%" },
          small=true,
          said=fn() {
            let more = text(n(), "more")
            text(n(), "text") + (if more != "" { "\n" + more } else { "" })
          },
          tips~,
        )
        |> ignore
      } else {
        x.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
        @sf.words_node(x, fn() { text(n(), "text") }, fn() { if text(n(), "kind") == "disk" { amber } else { red } })
        .shrink(Is(1.0))
        .min_width(Is(Some(0.0)))
        |> ignore
      }
    })
  })
}
