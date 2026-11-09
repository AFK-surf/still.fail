// An agent's history's steps (history_steps.mbt's) as nodes of the window's tree: the same rows of what the core put
// together, laid out from the same styles (style_node), in a page's list that holds each row only while it shows
// (View::scrolls_window). It follows its newest end; the page before comes in above what is read, which stays where it
// is (the list's top, where the history begins, holding nothing: what comes in comes under it); the page before that is
// asked for as the reader nears its top again; an entry gone to is brought to the middle and marked a moment.

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
/// Agent `key`'s history on `station`, its steps (history_steps') made once in node `v`, which they fill; tips in `tips`.
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
              failing: [],
            }
          })
        })
      1 => steps_box_node(p, steps_box, fn(b) { steps_words(b, fn() { head().edge }, steps_edge) })
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
    let by : Map[String, StepsRow] = {}
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
  let goto : @signals.Signal[String?] = @signals.signal(None)
  let lit : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })
  let unlit = Ref(fn() {  })
  // opened at an entry: the item that draws it brought to the middle, marked a moment; one before what is loaded, the
  // pages before first (below); one 只看收发 leaves out, all of it shown again first
  v.reacts(fn() { (steps_own.focus.get(fk), rows.get().0.length()) }, fn(now) {
    guard now.0 is Some(e) else { return }
    let loaded = items(@signals.untracked(fn() { src.topic("history", params).get().value }), "items")
    match loaded.search_by(fn(i) { entries_of(Some(i)).map(fn(x) { x.0 <= e && e <= x.1 }).unwrap_or(false) }) {
      Some(at) => {
        if @signals.untracked(fn() { steps_own.only_io.get() }) && flag(loaded.get(at), "work") {
          steps_own.only_io.set(false)
        }
        let ik = text(loaded.get(at), "key")
        steps_own.focus.remove(fk)
        steps_own.went[lkey] = true
        steps_own.marked.set((lkey, ik))
        lit.set(ik)
        (unlit.val)()
        unlit.val = v.at_moment(v.cause_at() + steps_marked_ms, fn() { lit.set("") })
        goto.set(Some("i/" + ik))
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
  // the first row that shows, as the list is moved for what came over it, and the first item it was told with: near
  // its top while it is one of its first three rows (its top's and two items) and the items begin as they did then
  let first_shown : @signals.Signal[(String, String)] = @signals.signal(("", ""), same=fn(a, b) { a == b })
  // the pages before as it nears its top (useLoadNear), or for an entry before what is loaded, once for each first
  // item they come above
  v.reacts(
    fn() {
      let h = steps_head_of(src, params, lkey)
      let (shown, told_first) = first_shown.get()
      let near = told_first == h.first &&
        (match rows.get().0.search(shown) {
          Some(i) => i <= 2
          None => false
        })
      (h.more && (near || steps_own.focus.contains(fk)), h.first, steps_own.older.get())
    },
    fn(now) {
      let (ask, first, older) = now
      guard ask && older != first else { return }
      steps_own.older.set(first)
      (src.call)("history.older", Json::object(params), fn(res) {
        if res is Err(_) {
          steps_own.older.set("")
          // (an entry asked for before what could be had: where it opens)
          steps_own.focus.remove(fk)
        }
      })
    },
  )
  steps_box_node(v, steps_box, fn(b) {
    steps_fills(b)
    b.box(fn(l) {
      steps_fills(l)
      l.scrolls_window(
        scroll,
        fn() { rows.get().0 },
        est=steps_est,
        bar=@ui.tree_scroll_bar(),
        foot_room=fn() { steps_foot_room },
        // (its top, where it begins or the pages before come, stands over what comes in under it)
        holds=fn(k) { k != "edge" },
        // (followed at its newest; not once gone to an entry)
        follows=fn() { !steps_own.went.contains(lkey) },
        centres=fn() { goto.get() },
        first_told=fn(k) {
          first_shown.set((k, @signals.untracked(fn() { steps_head_of(src, params, lkey).first })))
        },
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
/// One of what the reader opens (a fold, a line, a group, a call), by its key, opened or shut.
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
fn steps_seconds(v : @view.View, src : Source, since : Double, till? : Double) -> () -> Int {
  let tick : @signals.Signal[Int] = @signals.signal(0)
  fn plan() -> Unit {
    let gone = (src.now)() - since
    if till is Some(t) && gone >= t {
      return
    }
    let into = if gone > 0.0 { gone - (gone / second_ms).floor() * second_ms } else { gone }
    v.at_moment(v.logic_at() + second_ms - into, later=true, fn() {
      tick.set(@signals.untracked(fn() { tick.get() }) + 1)
      plan()
    })
    |> ignore
  }

  plan()
  fn() { tick.get() }
}

///|
/// The history's rows to come while it is read the first time (steps_sample's) in `v`, as its list draws them.
fn steps_sample_node(v : @view.View, station : String, key : String, tips : @sf.TipLayer) -> Unit {
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
/// An item (history_row's) in `v`: the rule of the turn it begins, then its events; on the accent's faint ground while
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
/// One event (ev's) in `v`: its mark in the gutter and what `body` makes beside it; the turn's rail from under its mark
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
/// What an item is (item_view's) in `v`.
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
            @sf.pill_node(l, fn() { "Block" }, tone=Blue) |> ignore
          }
          if failed {
            @sf.pill_node(l, fn() { @sf.t("web-main.history.sendFailed") }, tone=Red) |> ignore
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
/// Words as Markdown (md_view's) in `v`: the panel's size, or small and grey.
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
/// An event in one line (one_line's) in `v`: `lead`, then `line` cut at its end; pressed (where there is more), what
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
    @sf.style_node(r, fn() { h_one.then(@sf.row_least_h()) })
    @sf.presses_node(r, fn() { steps_flip(key) })
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
    r.show(open, fn(o) {
      o.grow(Is(1.0)).row(Is(true)) |> ignore
      steps_box_node(o, h_grow, fn(_) {  }, in_row=true)
      @sf.words_node(o, fn() { @sf.t("web-main.fold") }, fn() { if @sf.lit_node(r) { h_one_fold_hot } else { h_one_fold } })
      |> ignore
    })
  })
  |> ignore
  // (opening and closing with its room, sizes_steady.mbt)
  @motion.reveal_node(v, open, fn(b) { steps_box_node(b, h_one_body, whole) }, lazy=true) |> ignore
}

///|
/// Long words folded to `lines` lines of `line` (fold's) in `v`: past that cut, a button under them saying how many
/// more lines there are; pressed, all of them, 收起 under them.
fn fold_node(v : @view.View, key : String, lines : Int, line : Double, body : (@view.View) -> Unit) -> Unit {
  let most = lines.to_double() * line + 2.0
  // (how tall what it holds is laid out, all of it)
  let tall : @signals.Signal[Double] = @signals.signal(0.0, same=fn(a, b) { a == b })
  let long = fn() { tall.get() > most + 4.0 }
  let open = fn() { steps_own.opened.contains(key) }
  steps_box_node(v, h_fold, fn(f) {
    steps_box_node(f, h_fold_room, fn(room) {
      room.max_height(By(fn() { if long() && !open() { Some(most) } else { None } })) |> ignore
      steps_box_node(room, h_fold_inner, fn(inner) {
        inner.shrink(Is(0.0)) |> ignore
        inner.reacts(fn() { inner.laid_size_told() }, fn(z) {
          match z {
            Some((_, h)) => tall.set(h)
            None => ()
          }
        })
        body(inner)
      })
    })
    f.show(long, fn(t) {
      let words = fn() {
        if open() {
          @sf.t("web-main.fold")
        } else {
          let more = dmax(1.0, ((tall.get() - most) / line).round()).to_int()
          @sf.t("web-main.history.more", args=[("n", more.to_string())])
        }
      }
      steps_box_node(t, h_fold_toggle, fn(b) {
        steps_pressed(b, fn() { steps_flip(key) }, label=words)
        @sf.words_node(b, words, fn() { if @sf.lit_node(b) { h_toggle_hot } else { h_toggle_words } }) |> ignore
      })
    })
  })
}

///|
/// A message to the agent (received's) in `v`.
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
        Some(Object(_)) as p => {
          steps_words(l, fn() { " · " }, h_label_words)
          place_node(l, station, p)
        }
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
/// A place as its platform's mark and its name (place_view's) in `v`: a Slack thread opens in Slack, a still.fail
/// chat its page.
fn place_node(v : @view.View, station : String, place : Json?) -> Unit {
  let url = text(place, "url")
  let session = text(place, "session")
  let goes = url != "" || session != ""
  v.box(fn(p) {
    @sf.style_node(p, fn() { h_place })
    p.ground(By(fn() { if goes && @sf.lit_node(p) { @ui.tree_theme().color(Hover) } else { 0L } })) |> ignore
    // (giving way in its line: its name wrapped where it is long)
    p.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    if goes {
      @sf.presses_node(p, fn() {
        if url != "" {
          @sfbase.open_slack(text(place, "app"), url) |> ignore
        } else {
          @sfbase.history_push()
          app.nav.push(Chat({ station, session, title: text(place, "name"), station_name: "" }))
        }
      })
    }
    match text(place, "surface") {
      "chat" | "ember" | "stillfail" =>
        p.pick(fn() { @sf.theme().dark }, fn(d, dark) {
          @sf.drawable_node(d, if dark { "stillfail_mark_dark" } else { "stillfail_mark" }, 12.0) |> ignore
        })
      "feishu" => @sf.drawable_node(p, "feishu", 12.0) |> ignore
      _ => @sf.drawable_node(p, "slack", 12.0) |> ignore
    }
    steps_words(p, fn() { text(place, "name") }, h_place_words)
  })
  |> ignore
}

///|
/// A Slack user's name (slack_name's) in `v`: pressed, 这是我 or 不是我 in its menu beside it; turning while the station
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
    steps_run(p, fn() { name }, h_strong, underline=fn() { @sf.lit_node(p) && !saying() })
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
/// Work the agent started in the background, ended (task_view's) in `v`.
fn task_node(v : @view.View, key : String, task : Json?, rail : Bool, rail_last : Bool) -> Unit {
  let failed = flag(task, "failed")
  let answer = text(task, "result")
  let has = field(task, "md") is Some(Array(_)) && answer != ""
  let agent = flag(task, "agent")
  ev_node(v, if agent { "agent" } else { "command" }, "", if failed { "red" } else { "" }, rail~, rail_last~, row=has, fn(b) {
    if !has {
      steps_box_node(b, h_one, fn(o) { steps_words(o, fn() { text(task, "text") }, if failed { h_one_red } else { h_one_words }) })
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
/// A turn's state (mark_view's) in `v`: waiting on work it started (counting on each second while it does, a bar
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
/// How a turn ended (ended's) in `v`.
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
/// A group of calls and thoughts (group_view's) in `v`: its line, all of it opening the group (its title its tip, in
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
        steps_box_node(o, h_rail_room_last, fn(room) { steps_box_node(room, h_rail, fn(_) {  }) })
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
        @sf.pill_node(h, fn() { @sf.t("web-main.history.failures", args=[("n", failures.to_string())]) }, tone=Red)
        |> ignore
      }
      if pending > 0 {
        @sf.pill_node(h, fn() { @sf.t("web-main.history.pending", args=[("n", pending.to_string())]) }, tone=Accented)
        |> ignore
      }
      match text(g, "title") {
        "" => ()
        title => @sf.tip_node(tips, h, fn() { title }) |> ignore
      }
    })
    |> ignore
    @motion.reveal_node(gv, open, lazy=true, fn(s) {
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
/// A call (step_view's) in `v`: its line; opened, what it asked for and what came back.
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
    steps_words(sum, fn() { text(step, "meta") }, if failed { h_step_meta_red } else { h_step_meta })
  }, fn(body) { tool_body_node(body, src, rk, step) })
}

///|
/// A line of a group that opens to what is behind it (opened's) in `v`; in brief, read whole as it is opened.
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
    })
    |> ignore
    @motion.reveal_node(s, open, fn(o) { whole_node(o, src, station, key, rk, content, body) }, lazy=true) |> ignore
  })
}

///|
/// What a step or thought holds as it shows (whole's) in `v`: in brief, read whole now (`history.detail`), a line saying
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
/// A call opened (tool_body's) in `v`: what it asked for, then what came back, as the core reads them (`history.tool`),
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
/// A list of things to do (plan_list's) in `v`: done ✓ struck and muted, under way › in 600, the rest ·.
fn plan_node(v : @view.View, list : Array[Json]) -> Unit {
  steps_box_node(v, tool_plan, fn(p) {
    for it in list {
      let iv = Some(it)
      let status = text(iv, "status")
      let (mark, words) = match status {
        "completed" => ("✓", tool_plan_done)
        "in_progress" => ("›", tool_plan_now)
        _ => ("·", tool_plan_words)
      }
      let mark_ink = fn() {
        match status {
          "completed" => @sf.theme().p.green
          "in_progress" => @sf.theme().p.accent
          _ => @sf.theme().p.subtle
        }
      }
      steps_box_node(p, tool_plan_row, fn(r) {
        steps_box_node(r, tool_plan_mark, fn(m) {
          m.box(fn(w) {
            w
            .words(Is(mark))
            .words_look(By(fn() { @ui.style_words(tool_plan_words) }))
            .ink(By(mark_ink))
            |> ignore
          })
          |> ignore
        })
        r.box(fn(w) {
          w.grow(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
          steps_run(w, fn() { text(iv, "text") }, words, strike=status == "completed")
        })
        |> ignore
      })
    }
  })
}

///|
/// One part of a call or of what came back (tool_part's) in `v`.
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
          w.grow(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
          steps_run(w, fn() { text(part, "path") }, tool_path_words, mono=true)
        })
        |> ignore
        match text(part, "extra") {
          "" => ()
          e => steps_words(p, fn() { e }, tool_path_extra)
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
    "plan" => plan_node(v, items(part, "items"))
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
/// Where the turn stands with the model (phase_line's) in `v`: its pulse in the gutter, the core's words, a clock
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
