// An agent's history as a page of the narrow shell's stack made once as nodes (narrow_made's): its bar, the agent at
// its head with what can be done to it and its tabs (seg_node), what the core says is worth a look, then its steps or
// its details. What is worth a look (its quota's chips), its steps (sfpages' history_steps, the list every pane draws
// them in) and its details (a list of one row) are one old view in it as yet, as its words waiting their bones are.

///|
/// The history's tab: its steps (0) or its details (1), the same for every history while the app runs.
// kept across runs: put back as a run begins (decide_reset)
let history_tab : @signals.Signal[Int] = @signals.signal(0)

///|
/// The history of agent `key` of chat `r` made once in node `v`, its steps opened at `entry` (a transcript entry),
/// else at its newest; under the status bar and over the navigation bar as `frame` says; `serial` the stack's page it is.
fn history_node(
  v : @view.View,
  src : Source,
  r : ChatRef,
  key : String,
  entry : Int?,
  frame : () -> PageFrame,
  serial : Int,
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
      e.show(fn() { title() != "" && link() != "" }, fn(k) {
        @sf.round_key_node(k, "copy", fn() { tr("web-mobile.history.copyLink") }, fn() {
          copy_chat_link(@signals.untracked(title), @signals.untracked(link))
        }, icon_size=18.0)
      })
    },
  )
  // its head, once the chat says what the agent is
  v.show(fn() { agent() is Some(_) }, fn(h) { history_head_node(h, src, r, agent) })
  // under it, one old view: what is worth a look (its quota's chips), then its steps or its details (what either
  // reads followed as long as the page is, as the tabs change: the history's topic not let go and asked again); the
  // chat's words in their bones while it is read the first time. Built as the stack builds its page's old view: its
  // lists' places and what they keep the page's own.
  app.nav.page_island(v, serial, fn(c, _page) {
    match agent() {
      None =>
        waiting_messages(
          c,
          match chat().error {
            Some(e) => Some(error_words(e))
            None => None
          },
        )
      Some(_) as a => {
        history_summary(c, a)
        c.box(style=history_body_box, fn() {
          if history_tab.get() == 0 {
            // its steps, as every pane draws them (sfpages' history_steps.mbt); opened at an entry, brought to it once
            let lkey = "history/" + r.station + "/" + key
            match entry {
              Some(e) if !history_placed.contains(lkey) => {
                history_placed[lkey] = true
                @sfpages.history_focus(r.station, key, e)
              }
              _ => ()
            }
            @sfpages.history_steps(c, src, r.station, key)
          } else {
            history_details(c, src, r, key, a)
          }
        })
        |> ignore
      }
    }
    // a Slack user's name tapped: its menu (link_menu.mbt)
    link_menu_layer(c)
  })
  .grow(Is(1.0))
  .min_height(Is(Some(0.0)))
  |> ignore
}

///|
/// What the history's old view holds under what is worth a look: its steps or its details, all the room left.
// kept across runs: a value (no field of it changes)
let history_body_box : @ui.Style = @ui.css("w=Full h=Full")

///|
/// The history's head: the agent's model's mark with its state's badge, its name (cut short where what it does and
/// its tabs leave it less), what can be done to it now, its tabs at the end.
fn history_head_node(v : @view.View, src : Source, r : ChatRef, agent : () -> Json?) -> Unit {
  let s = fn() { field(agent(), "session") }
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
    history_actions_node(h, src, r, agent)
    h.box(fn(e) {
      e.row(Is(true)).gap(Is(10.0)).lines_up(Is(Some(Middle))) |> ignore
      @sf.seg_node(
        e,
        fn() { [tr("android-chat.history.tab.steps"), tr("android-chat.history.tab.details")] },
        fn() { history_tab.get() },
        fn(i) { history_tab.set(i) },
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
  let one = fn(when : () -> Bool, icon : String, done : String, call : String) {
    v.show(when, fn(o) {
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
          k.pick(fn() { doing(dkey()) }, fn(i, busy) {
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
  one(
    fn() {
      let status = text(agent(), "status")
      status == "running" || status == "queued"
    },
    "stop",
    tr("android-chat.history.stopped"),
    "session.stop",
  )
  one(fn() { text(s(), "process") == "warm" }, "unplug", tr("android-chat.history.evicted"), "session.evict")
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
    m.pick(fn() { (maker(), runtime()) }, fn(i, mr) {
      @sf.maker_mark_node(i, mr.0, mr.1, size * (if xs { 0.6 } else { 0.56 })) |> ignore
    })
    let b = if xs { 11.0 } else { 15.0 }
    let ring = if xs { 1.5 } else { 2.0 }
    let inner = b - ring * 2.0
    m.box(fn(o) {
      o.over(Is(true)) |> ignore
      o.show(fn() { state() != "" }, fn(g) {
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
