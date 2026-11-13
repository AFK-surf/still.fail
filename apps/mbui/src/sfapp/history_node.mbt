// An agent's history as a page of the narrow shell's stack made once as nodes (narrow_made's): its bar, the agent at
// its head with what can be done to it and its tabs (seg_node), what the core says is worth a look, then its steps or
// its details, all of it nodes (its steps sfpages' history_steps_node).

///|
/// The history's tab: its steps (0) or its details (1), the same for every history while the app runs.
// kept across runs: put back as a run begins (decide_reset)
let history_tab : @signals.Signal[Int] = @signals.signal(0)

///|
/// The history of agent `key` of chat `r` made once in node `v`, its steps opened at `entry` (a transcript entry),
/// else at its newest; under the status bar and over the navigation bar as `frame` says.
fn history_node(
  v : @view.View,
  src : Source,
  r : ChatRef,
  key : String,
  entry : Int?,
  frame : () -> PageFrame,
  _serial : Int,
) -> Unit {
  let src = src.owned_by(v)
  let chat = fn() { src.topic("chat", chat_params(r)).get() }
  let agent = fn() { agent_json(chat().value, key) }
  v
  .grow(Is(1.0))
  .min_height(Is(Some(0.0)))
  .ground(By(fn() { @sf.theme().p.bg }))
  .padding(By(fn() { (0.0, 0.0, 0.0, frame().foot) }))
  |> ignore
  // its bar: back, its title, its link copied at its end (where the chat has one)
  let title = fn() { text(chat().value, "title") }
  let link = fn() {
    match chat_link(r.station, key) {
      "" => ""
      l => l + "?history=" + @codec.encode_uri_component(key)
    }
  }
  @sf.nav_bar_node(
    v,
    fn() { tr("common.back") },
    fn() { tr("android-chat.history.title") },
    fn() { @sfbase.go_back() |> ignore },
    top=fn() { frame().top },
    trailing=fn(e) {
      e.gap(By(fn() { @sf.keys_apart(size=34.0, least=4.0) })) |> ignore
      e.show(at_once=true, fn() { agent() is Some(_) && history_tab.get() == 0 }, fn(f) {
        let on = fn() { @sfpages.history_only_io() }
        @sf.round_key_node(
          f,
          "filter",
          fn() { @sf.t("web-main.history.onlyIo") },
          fn() { @sfpages.history_only_io_flip() },
          icon_size=18.0,
          ink=fn() { if on() { @sf.theme().p.accent } else { @sf.theme().p.text } },
        )
      })
      e.show(at_once=true, fn() { title() != "" && link() != "" }, fn(k) {
        @sf.round_key_node(k, "copy", fn() { tr("web-mobile.history.copyLink") }, fn() {
          copy_chat_link(@signals.untracked(title), @signals.untracked(link))
        }, icon_size=18.0)
      })
    },
  )
  // its head, once the chat says what the agent is
  v.show(at_once=true, fn() { agent() is Some(_) }, fn(h) { history_head_node(h, src, r, key, agent) })
  // the agent's history followed from then on as long as the page is, whichever tab reads it (each made as its tab is
  // shown): not let go and asked again as the tabs change
  let held : Ref[@sfbase.TopicLease?] = Ref(None)
  v.reacts(fn() { agent() is Some(_) }, fn(known) {
    if known && held.val is None {
      held.val = Some(src.lease_topic("history", history_params(r, key)))
    }
  })
  // under it, what is worth a look (its quota's chips), as tall as it is; on the details' tab its details under it,
  // all the room left, scrolling in it; while the chat does not say what the agent is yet, its rows in their bones
  // (what could not be read over them in red)
  let tips = @sf.TipLayer::new(fn() { Some(v) })
  v.show(at_once=true, fn() { agent() is None }, fn(w) {
    w.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
    @sf.waiting_node(w, fn(s) { @sfpages.steps_sample_node(s, r.station, key, tips) }, error=fn() {
      match chat().error {
        Some(e) => error_words(e)
        None => ""
      }
    }, fill=true)
  })
  v.show(at_once=true, fn() { agent() is Some(_) }, fn(h) { history_summary_node(h, agent, tips) })
  // kept per tab so switching 步骤 <-> 详情 preserves the steps scroll position
  v.box(fn(tabs) {
    tabs.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
    tabs.each(
      fn() { if agent() is Some(_) { [history_tab.get()] } else { [] } },
      fn(k) { k },
      keeps=fn() { if agent() is Some(_) { [0, 1] } else { [] } },
      fn(slot, tab) {
        slot.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
        if tab.untracked() == 1 {
          history_details_node(slot, src, r, key, agent, tips)
        } else {
          let lkey = "history/" + r.station + "/" + key
          match entry {
            Some(e) if !history_placed.contains(lkey) => {
              history_placed[lkey] = true
              @sfpages.history_focus(r.station, key, e)
            }
            _ => ()
          }
          @sfpages.history_steps_node(slot, src, r.station, key, tips)
        }
      },
    )
    |> ignore
  })
  |> ignore
}

///|
/// The history's head: the agent's model's mark with its state's badge, its name (cut short where what it does and
/// its tabs leave it less), what can be done to it now, its tabs at the end. 详情 pressed, what its details read is asked
/// first and the page stays as it is, the tab shown pressed, till it is answered (in the press's frame where it is
/// already): then they open as they did at the press (sfpages' history_details_open). 步骤 pressed meanwhile gives that
/// up; 步骤 itself asks nothing.
fn history_head_node(v : @view.View, src : Source, r : ChatRef, key : String, agent : () -> Json?) -> Unit {
  let s = fn() { field(agent(), "session") }
  // (the tab pressed while what it shows is asked, and what waits for it)
  let pressed : @signals.Signal[Int?] = @signals.signal(None)
  let waiting : Ref[@sfbase.PressWait?] = Ref(None)
  let choose = fn(i : Int) {
    @signals.untracked(fn() {
      guard pressed.get() != Some(i) else { return }
      match waiting.val {
        Some(w) => {
          waiting.val = None
          w.give_up()
        }
        None => ()
      }
      pressed.set(None)
      guard i == 1 && history_tab.get() != 1 else {
        history_tab.set(i)
        return
      }
      pressed.set(Some(i))
      waiting.val = Some(
        @sfpages.history_details_open(
          src,
          history_details_asks(r, key),
          @sfpages.history_details_at(r.station, key),
          fn() {
            history_tab.set(i)
            pressed.set(None)
          },
          let_go=fn() { pressed.set(None) },
        ),
      )
    })
  }
  v.box(fn(h) {
    h.row(Is(true)).padding(Is((18.0, 4.0, 18.0, 0.0))).gap(Is(6.0)).lines_up(Is(Some(Middle))) |> ignore
    model_mark_big_node(
      h,
      fn() { text(field(s(), "maker"), "id") },
      fn() { text(s(), "runtime") },
      20.0,
      fn() { state_of_badge(text(agent(), "badge")) },
    )
    h.box(fn(n) {
      n.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
      @sf.words_node(n, fn() { text(s(), "agentText") }, fn() { history_name_words }) |> ignore
    })
    |> ignore
    h.box(fn(e) {
      e.row(Is(true)).gap(By(fn() { @sf.keys_apart(size=28.0, least=10.0) })).lines_up(Is(Some(Middle))).shrink(Is(0.0)) |> ignore
      history_actions_node(e, src, r, agent)
      @sf.seg_node(
        e,
        fn() { [tr("android-chat.history.tab.steps"), tr("android-chat.history.tab.details")] },
        fn() { pressed.get().unwrap_or(history_tab.get()) },
        choose,
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The agent's name in the history's head: a title's, strong, on one line cut short.
// kept across runs: a value (no field of it changes)
let history_name_words : @ui.TextStyle = @ui.text_style(size=Title, weight=Bold, color=Fg, wrap=false, w=Cut)

///|
/// What can be done to the agent now: stop a turn while it runs or waits, let an idle process go; each a 28 disc, a
/// spinner while it is asked.
fn history_actions_node(v : @view.View, src : Source, r : ChatRef, agent : () -> Json?) -> Unit {
  let s = fn() { field(agent(), "session") }
  let key = fn() { text(s(), "key") }
  let has_stop = fn() {
    let status = text(agent(), "status")
    status == "running" || status == "queued"
  }
  let has_evict = fn() { text(s(), "process") == "warm" }
  v.show(at_once=true, fn() { has_stop() || has_evict() }, fn(row) {
    @sf.style_node(row, fn() { @sf.keys_row(size=28.0) })
    row.shrink(Is(0.0)) |> ignore
    let one = fn(when : () -> Bool, icon : String, done : String, call : String) {
      row.show(at_once=true, when, fn(o) {
        let dkey = fn() { call + "/" + r.station + "/" + key() }
        @sf.disc_key_node(
          o,
          fn() { done },
          fn() {
            let dkey = @signals.untracked(dkey)
            if !doing(dkey) {
              act(src, done, dkey, call, { "station": Json::string(r.station), "key": Json::string(key()) }, done~)
            }
          },
          side=28.0,
          ground=fn() { @sf.theme().p.chip },
          fn(k) {
            k.pick(at_once=true, fn() { doing(dkey()) }, fn(i, busy) {
              if busy {
                @sf.spinner_node(i, size=12.0) |> ignore
              } else {
                @sf.icon_node(i, icon, 14.0, By(fn() { @sf.theme().p.text })) |> ignore
              }
            })
          },
        )
      })
    }
    one(has_stop, "stop", tr("android-chat.history.stopped"), "session.stop")
    one(has_evict, "unplug", tr("android-chat.history.evicted"), "session.evict")
  })
}

///|
/// A model's mark as the history's head has it (model_mark_big's, as nodes): its maker's mark on a tile with a
/// hairline, `size` across, and its state's badge over the corner (solid accent waiting on someone, an accent ring at
/// work, red failed) ringed in the page's ground.
fn model_mark_big_node(
  v : @view.View,
  maker : () -> String,
  runtime : () -> String,
  size : Double,
  state : () -> String,
) -> Unit {
  let xs = size < 30.0
  v.box(fn(m) {
    m
    .width(Is(Some(size)))
    .height(Is(Some(size)))
    .radius(Is(if xs { 6.0 } else { @sf.small_corner }))
    .ground(By(fn() { @sf.theme().p.card }))
    .edge(By(fn() { (1.0, @sf.theme().p.line) }))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    |> ignore
    m.pick(at_once=true, fn() { (maker(), runtime()) }, fn(i, mr) {
      @sf.maker_mark_node(i, mr.0, mr.1, size * (if xs { 0.6 } else { 0.56 })) |> ignore
    })
    let b = if xs { 11.0 } else { 15.0 }
    let ring = if xs { 1.5 } else { 2.0 }
    let inner = b - ring * 2.0
    m.box(fn(o) {
      o.over(Is(true)) |> ignore
      o.show(at_once=true, fn() { state() != "" }, fn(g) {
        g
        .width(Is(Some(b)))
        .height(Is(Some(b)))
        .radius(Is(b / 2.0))
        .offset(Is((size - b + 3.0, size - b + 3.0)))
        .ground(By(fn() { @sf.theme().p.bg }))
        .lines_up(Is(Some(Middle)))
        .lies_along(Is(Middle))
        |> ignore
        g.box(fn(d) {
          d
          .width(Is(Some(inner)))
          .height(Is(Some(inner)))
          .radius(Is(inner / 2.0))
          .ground(By(fn() {
            match state() {
              "run" => 0L
              "failed" => @sf.theme().p.red
              _ => @sf.theme().p.accent
            }
          }))
          .edge(By(fn() { if state() == "run" { (dmin(2.5, inner / 2.0), @sf.theme().p.accent) } else { (0.0, 0L) } }))
          |> ignore
        })
        |> ignore
      })
    })
    |> ignore
  })
  |> ignore
}
