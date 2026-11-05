// What a chat's list holds besides its messages (chat_rows.mbt's) as nodes of the window's tree, made once: the line
// over what is new, the pages being brought in, a chat with nothing in it, where it stands under its last message (and
// what it needs of the viewer as a card, 忽略 at its end).

///|
/// Over the first message unread when the chat opened (unread_line's) in `row`: its words in the accent, a rule each
/// side, 10 apart.
fn unread_line_node(row : @view.View) -> Unit {
  row.row(Is(true)).gap(Is(10.0)).lines_up(Is(Some(Middle))) |> ignore
  let rule = fn() {
    row.box(fn(r) {
      r.grow(Is(1.0)).height(Is(Some(1.0))).ground(By(fn() { @sf.alpha(@sf.theme().p.accent, 0.5) })) |> ignore
    })
    |> ignore
  }
  rule()
  row.box(fn(w) {
    w
    .words(By(fn() { @sf.t("web-main.chat.unreadLine") }))
    .words_look(By(fn() { @ui.style_words(unread_words) }))
    .ink(By(fn() { @ui.style_ink(unread_words) }))
    |> ignore
  })
  |> ignore
  rule()
}

///|
/// The page before or after being brought in (pages_coming's) in `row`: a spinner in the middle, 4 over and 8 under
/// it (older), or 8 over and 4 under (newer).
fn pages_coming_node(row : @view.View, older : Bool) -> Unit {
  row.lines_up(Is(Some(Middle))).padding(Is(if older { (0.0, 4.0, 0.0, 8.0) } else { (0.0, 8.0, 0.0, 4.0) })) |> ignore
  @sf.spinner_node(row) |> ignore
}

///|
/// A chat with nothing in it yet (chat_empty's) in `row`: its words in the middle, 32 over and under them.
fn chat_empty_node(row : @view.View) -> Unit {
  row.lines_up(Is(Some(Middle))).padding(Is((0.0, 32.0, 0.0, 32.0))) |> ignore
  row.box(fn(w) {
    w
    .words(By(fn() { @sf.t("web-main.chat.empty") }))
    .words_look(By(fn() { @ui.style_words(chat_empty_words) }))
    .ink(By(fn() { @ui.style_ink(chat_empty_words) }))
    |> ignore
  })
  |> ignore
}

///|
/// Where chat `here` stands under its last message (chat_state's) in `row`, `state` as it is now (its words, what leads
/// them, what follows the lead): led by its icon, whole, its words wrapping; what it needs of the viewer that can be let
/// go, a card with the bell and 忽略 at its end, its room closing as it is let go and how it went coming in its place
/// (under_node's); something else asked of the viewer, 忽略 under the line.
fn chat_state_node(row : @view.View, src : Source, here : () -> MessageHere, state : () -> (String, String, String)) -> Unit {
  row.lines_up(Is(None)) |> ignore
  let turn = fn() { state().1 == "need" }
  let asking = fn() {
    match here().view.state_ask {
      Some(seq) if turn() => Some(seq)
      _ => None
    }
  }
  // (as a card where it can be let go in its list: 0 the line, 1 the card coming and going, 2 the card alone)
  let way = fn() {
    let h = here()
    if h.list is Some(_) && h.view.thread is Some(_) && (asking() is Some(_) || state().1 == "dismissed") {
      1
    } else if asking() is Some(_) {
      2
    } else {
      0
    }
  }
  let said = fn() {
    let look = @sf.theme().chat_list
    (if turn() { look.state_turn } else { look.state_quiet }).then(chat_state_wraps)
  }
  row.pick(way, fn(r, which) {
    r.lines_up(Is(None)) |> ignore
    match which {
      1 => {
        under_node(r, fn() { asking() is Some(_) }, fn(u) { need_card_node(u, src, here, state, asking) })
        under_node(r, fn() { state().1 == "dismissed" && asking() is None }, fades_in=true, fn(u) {
          u.box(fn(w) {
            w.words(By(fn() { state().0 })).words_look(By(fn() { @ui.style_words(said()) })).ink(By(fn() { @ui.style_ink(said()) })) |> ignore
          })
          |> ignore
        })
      }
      2 => need_card_node(r, src, here, state, asking)
      _ => {
        r.pick(fn() { state().1 }, fn(line, lead) {
          match lead {
            "need" | "done" | "wait" | "watch" => {
              line.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Start))).says(By(fn() { Some(@view.said(Text, label=state().0)) })) |> ignore
              line.box(fn(slot) {
                slot
                .width(Is(Some(10.0)))
                .height(By(fn() { Some(@sf.theme().chat_list.state_slot_h) }))
                .lies_along(Is(Middle))
                |> ignore
                lead_icon_node(slot, fn() { lead }, fn() { if turn() { @sf.theme().p.text } else { @sf.theme().p.muted } })
              })
              |> ignore
              let after = fn() {
                let (_, lead, rest) = state()
                if rest == "" && lead == "done" { @sf.t("web-main.status.done") } else { rest }
              }
              line.show(fn() { after() != "" }, fn(w) {
                w.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
                w.words(By(after)).words_look(By(fn() { @ui.style_words(said()) })).ink(By(fn() { @ui.style_ink(said()) })) |> ignore
              })
            }
            _ =>
              line.box(fn(w) {
                w.words(By(fn() { state().0 })).words_look(By(fn() { @ui.style_words(said()) })).ink(By(fn() { @ui.style_ink(said()) })) |> ignore
              })
              |> ignore
          }
        })
        // (something else asked of the viewer: 忽略 under the line)
        r.show(fn() { here().view.state_ask is Some(_) }, fn(d) {
          d.padding(Is((0.0, 6.0, 0.0, 0.0))) |> ignore
          dismiss_node(d, src, here, fn() { here().view.state_ask.unwrap_or(0.0) }, fn() { true }, fn() { false }, fn() {
            true
          }, false)
        })
      }
    }
  })
}

///|
/// What the chat needs of the viewer as a card (need_card's) in `parent`: the bell and its words in the ink, 忽略 at its
/// end (under them where a native narrow chat has little room); `seq` the post that asks, None once let go while it
/// shows: in its place how it went (its words, 已忽略：…), quiet, where the bell's ink began, 忽略 faded where it was,
/// nothing left to press. What it said fades out, then how it went fades in after it (who_node's): the card's room
/// never changes.
fn need_card_node(
  parent : @view.View,
  src : Source,
  here : () -> MessageHere,
  state : () -> (String, String, String),
  seq : () -> Double?,
) -> Unit {
  let live = fn() { seq() is Some(_) }
  let first = @signals.untracked(live)
  let was = @motion.Way::new(if first { 1.0 } else { 0.0 })
  let now = @motion.Way::new(if first { 0.0 } else { 1.0 })
  parent.reacts(live, fn(on) {
    let at = parent.cause_at()
    if on {
      was.put(1.0)
      now.put(0.0)
    } else {
      was.go(0.0, @motion.tween(options_out_ms, ease=Leave), at~)
      now.go(1.0, @motion.tween(options_out_ms, ease=Out, delay=options_out_ms), at~)
    }
  })
  let stacked = fn() { @sf.native_on() && here().inline }
  @sf.ask_line_card_node(parent, stacked, fn(card) {
    let look = @sf.theme().chat_list
    card.box(fn(words) {
      words
      .width_share(By(fn() { if stacked() { 1.0 } else { 0.0 } }))
      .grow(By(fn() { if stacked() { 0.0 } else { 1.0 } }))
      .basis(By(fn() { if stacked() { None } else { Some(0.0) } }))
      .min_width(Is(Some(0.0)))
      .says(By(fn() { Some(@view.said(Text, label=state().0)) })) |> ignore
      // (what it asks: the bell where an option's number is, what follows it)
      words.box(fn(a) {
        a.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Start))).alpha(By(fn() { way_shown(was, a) })) |> ignore
        @sf.ask_line_mark_node(a, fn(m) { lead_icon_node(m, fn() { "need" }, fn() { @sf.theme().p.text }, centred=true) }) |> ignore
        a.box(fn(w) {
          w.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
          w
          .words(By(fn() { state().2 }))
          .words_look(By(fn() { @sf.ask_line_words_look(look.state_turn.then(chat_state_wraps)) }))
          .ink(By(fn() { @ui.style_ink(look.state_turn) }))
          |> ignore
        })
        |> ignore
      })
      |> ignore
      // (how it went, in its place once let go, quiet, where the bell's ink began)
      words.show(fn() { !live() || way_shown(was, words) < 1.0 }, fn(n) {
        n.over(Is(true)).padding(Is((@sf.ask_line_start_room(state_icon), 0.0, 0.0, 0.0))).alpha(By(fn() { way_shown(now, n) })) |> ignore
        n
        .words(By(fn() { state().0 }))
        .words_look(By(fn() { @sf.ask_line_words_look(look.state_quiet.then(chat_state_wraps)) }))
        .ink(By(fn() { @ui.style_ink(look.state_quiet) }))
        |> ignore
      })
    })
    |> ignore
    // (忽略 ending it, concentric with its end corner; let go, faded where it was)
    card.box(fn(e) {
      e.lines_up(Is(Some(End))).padding(By(fn() { (0.0, if stacked() { 6.0 } else { 0.0 }, 0.0, 0.0) })).alpha(By(fn() {
        way_shown(was, e)
      }))
      |> ignore
      @sf.ask_line_button_node(e, fn() { @sf.t("web-main.chat.asks.dismiss") }, state_icon, live, fn() {
        guard seq() is Some(s) else { return }
        let h = here()
        guard h.view.thread is Some(thread) && !h.view.offline && !h.view.archived else { return }
        let k = seq_key(h.station, thread, s)
        dismissed[k] = true
        @ui.haptic(Confirm)
        act(
          src,
          @sf.t("web-main.decisions.dismissWhat"),
          "",
          "decision.dismiss",
          { "station": Json::string(h.station), "thread": Json::number(thread), "seq": Json::number(s) },
          failed=fn() { dismissed.remove(k) |> ignore },
        )
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// What an agent of the chat said in Slack (or Feishu, or another chat) rather than here, or a person's message there
/// it was given (sent_elsewhere's) in `row`, `s` as it is now: drawn as a message of theirs (others_message_node's
/// head, picture and words), that place's mark on the picture's corner and, after the name (inline, on a line of its
/// own under the head), where it went or came from: its link, red where sending it failed.
fn sent_elsewhere_node(row : @view.View, src : Source, here : () -> MessageHere, s : () -> Elsewhere) -> Unit {
  let inline = fn() { here().inline }
  let surface = fn() {
    match s().place {
      Some(p) => p.surface
      None => "slack"
    }
  }
  // (one of the chat's agents': its history beside the chat)
  let agent = fn() {
    let now = s()
    if !now.received && now.by.agent != "" && here().view.agents.iter().any(fn(a) { a.key == now.by.agent }) {
      now.by.agent
    } else {
      ""
    }
  }
  row.gap(Is(4.0)) |> ignore
  row.box(fn(head) {
    head
    .row(Is(true))
    .min_height(Is(Some(head_line_h)))
    .gap(Is(6.0))
    .lines_up(Is(Some(Middle)))
    .padding(By(fn() { (if inline() { 25.0 } else { 0.0 }, 0.0, 0.0, 0.0) }))
    |> ignore
    let press = if @signals.untracked(agent) != "" { Some(fn() { open_detail(src, here_ref(here()), agent()) }) } else { None }
    let name = message_name_node(head, fn() { s().by.name }, press)
    if @signals.untracked(agent) != "" {
      agent_hover_node(name, src, here, agent)
    }
    head.show(fn() { !inline() }, fn(r) { elsewhere_route_node(r, s) })
    message_time_node(head, fn() { s().time }, None)
  })
  |> ignore
  row.show(inline, fn(r) { elsewhere_route_node(r, s) })
  // (its picture: inline over its head's start, 3 down; else out in the margin, 29 before its words; its place's mark
  // on its corner)
  row.box(fn(a) {
    a.over(Is(true)).offset(By(fn() { (if inline() { 0.0 } else { -29.0 }, 3.0) })) |> ignore
    a.pick(fn() { s().received }, fn(slot, received) {
      if received {
        slot.width(Is(Some(avatar_side))).height(Is(Some(avatar_side))) |> ignore
        person_avatar_node(slot, src, fn() { s().by.name }, fn() { s().by.name }, fn() { s().by.picture }, fn() { 0 })
        slot.box(fn(o) {
          o.over(Is(true)).lies_along(Is(End)).lines_up(Is(Some(End))) |> ignore
          o.box(fn(k) {
            k
            .width(Is(Some(place_corner_side + 5.0)))
            .height(Is(Some(place_corner_side + 5.0)))
            .offset(Is((6.0, 6.0)))
            .radius(Is(1.0e6))
            .row(Is(true))
            .lies_along(Is(Middle))
            .lines_up(Is(Some(Middle)))
            .ground(By(fn() { @ui.tree_theme().color(Bg) }))
            .edge(By(fn() { (1.0, @ui.tree_theme().color(Line)) }))
            |> ignore
            @sf.place_mark_node(k, fn() { surface() == "feishu" }, place_corner_side) |> ignore
          })
          |> ignore
        })
        |> ignore
      } else {
        let face = agent_avatar_node(slot, fn() { s().by.maker }, fn() { s().by.runtime }, fn() {
          if surface() == "feishu" { "feishu" } else { "slack" }
        })
        if @signals.untracked(agent) != "" {
          agent_hover_node(face, src, here, agent)
        }
      }
    })
  })
  |> ignore
  // (its words as Markdown, its links opened; its files under them)
  @sf.markdown_node(row, fn() { s().text }, size=fn() { body_size }, on_link=fn(h) { open_link(h) }) |> ignore
  row.show(fn() { !s().attachments.is_empty() }, fn(fs) {
    message_files_node(fs, src, here, fn() { s().attachments }, false)
  })
}

///|
/// Where what was said went or came from (elsewhere_route's) in `r`: its mark, 发送到 or 来自 Slack, the place (its mark
/// and its name, pressed opening it where it has a link: lit under the pointer), 发送失败 in red.
fn elsewhere_route_node(r : @view.View, s : () -> Elsewhere) -> Unit {
  r.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Middle))) |> ignore
  @sf.icon_node(r, if @signals.untracked(s).received { "received" } else { "send" }, route_icon, By(fn() { @sf.theme().p.accent })) |> ignore
  r.box(fn(w) {
    w
    .words(By(fn() {
      @sf.t(if s().received { "web-main.chat.fromSlack" } else { "web-main.history.sentTo" }).trim_end(chars=" ").to_owned()
    }))
    .words_look(By(fn() { @ui.style_words(route_words) }))
    .ink(By(fn() { @ui.style_ink(route_words) }))
    |> ignore
  })
  |> ignore
  let url = fn() {
    match s().place {
      Some(p) => (p.url, p.app)
      None => ("", "")
    }
  }
  r.box(fn(place) {
    let pressed = fn() { url().0 != "" }
    place
    .row(Is(true))
    .gap(Is(4.0))
    .padding(Is((6.0, 1.0, 6.0, 1.0)))
    .radius(By(fn() { @ui.tree_theme().corner(Md) }))
    .lines_up(Is(Some(Middle)))
    .ground(By(fn() { @ui.tree_theme().color(if pressed() && place.pointed_in() { Hover } else { Neutral }) }))
    |> ignore
    if @signals.untracked(pressed) {
      @sf.presses_node(place, fn() {
        let (u, app) = url()
        @sfbase.open_slack(app, u) |> ignore
      })
    }
    place.pick(fn() {
      match s().place {
        Some(p) => p.surface
        None => "slack"
      }
    }, fn(m, mark) {
      match mark {
        "ember" | "stillfail" =>
          @sf.drawable_node(m, fn() { if @sf.theme().dark { "stillfail_mark_dark" } else { "stillfail_mark" } }, route_mark) |> ignore
        "feishu" => @sf.place_mark_node(m, fn() { true }, route_mark) |> ignore
        _ => @sf.place_mark_node(m, fn() { false }, route_mark) |> ignore
      }
    })
    place.box(fn(w) {
      w
      .words(By(fn() {
        match s().place {
          Some(p) => p.name
          None => "Slack"
        }
      }))
      .words_look(By(fn() { @ui.style_words(route_place_words) }))
      .ink(By(fn() { @ui.style_ink(route_place_words) }))
      |> ignore
    })
    |> ignore
  })
  |> ignore
  r.show(fn() { s().failed }, fn(f) {
    f.padding(Is((6.0, 1.0, 6.0, 1.0))).radius(By(fn() { @ui.tree_theme().corner(Md) })).ground(By(fn() { @ui.tree_theme().color(DangerBg) })) |> ignore
    f.box(fn(w) {
      w
      .words(By(fn() { @sf.t("web-main.history.sendFailed") }))
      .words_look(By(fn() { @ui.style_words(route_failed_words) }))
      .ink(By(fn() { @ui.style_ink(route_failed_words) }))
      |> ignore
    })
    |> ignore
  })
}
