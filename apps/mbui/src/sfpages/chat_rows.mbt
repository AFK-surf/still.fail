// What a chat's list holds on the desktop besides its messages (ember web/src/Chat.tsx ChatRows, OutboxRow, Activity,
// useSteady; Chat.css.ts chatUnreadLine, chatOlder, chatNewer, chatEmpty, msgUnsent, msgUnsentBtn, agentActivity,
// activityLine, activityAvatar, activityRing, activityTail, activityNowText, activityElapsed, activityStop): the line
// over what is new, the pages being brought in, what was sent from here and is not in the chat yet, where it stands,
// and its agents at work.

///|
/// Over the first message unread when the chat opened (chatUnreadLine): its words in the accent, a rule each side.
fn unread_line(c : @ui.Ctx) -> Unit {
  c.box(style=unread_row, fn() {
    c.box(style=unread_rule, fn() {  }) |> ignore
    c.text(@sf.t("web-main.chat.unreadLine"), style=unread_words) |> ignore
    c.box(style=unread_rule, fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// The page before or after being brought in (chatOlder, chatNewer): a spinner in the middle.
fn pages_coming(c : @ui.Ctx, older : Bool) -> Unit {
  c.box(style=if older { older_row } else { newer_row }, fn() { @sf.spinner(c) |> ignore }) |> ignore
}

///|
/// A chat with nothing in it yet (chatEmpty).
fn chat_empty(c : @ui.Ctx) -> Unit {
  c.box(style=empty_row, fn() { c.text(@sf.t("web-main.chat.empty"), style=chat_empty_words) |> ignore }) |> ignore
}

///|
/// Where the chat stands, under its last message (the core's `stateText`: its row's second line, a card waiting left
/// out as it is in the chat): led as the row's is (chat_mark.mbt: a bell, a check, the waiting arc, the radar) but
/// whole, its words wrapping where the row cuts them to a line; done with nothing said, its word (已完成) after the
/// check. What it needs of a person in ink, the rest quiet, and let go right under it (the core's `stateAsk`).
fn chat_state(c : @ui.Ctx, src : Source, here : MessageHere, words : String, lead : String, rest : String) -> Unit {
  let p = @sf.theme().p
  // (the row's words, the theme's lists', on their line: the icon's column, the theme's too, as high as it)
  let look = @sf.theme().chat_list
  let turn = lead == "need"
  let said = (if turn { look.state_turn } else { look.state_quiet }).then(chat_state_wraps)
  // what it needs of the viewer and can be let go: one card, the bell and its words, 忽略 at its end; let go (the core
  // says so at once), on screen the card stays, saying so, 忽略 no longer pressed, and out of sight it is the line
  // saying it was let go, as a post's answered options are (Turns::in_turn)
  let asking = match here.view.state_ask {
    Some(seq) if turn => Some(seq)
    _ => None
  }
  match (here.list, here.view.thread) {
    (Some(l), Some(thread)) if asking is Some(_) || lead == "dismissed" => {
      let key = here.station + "/" + thread.to_int().to_string()
      let open = l.turns.in_turn(c, "need/" + key, asking is Some(_), close_turn_ms, seen=seen_in(c, here, None))
      let start_at = l.turns.start("need/" + key)
      under_post(
        c,
        "need-card/" + key,
        open,
        exit=@motion.trans(fade=0.0, scale=options_scale, spec=@motion.tween(options_out_ms, ease=options_ease)),
        close=close_gap,
        start_at?,
        fn() { need_card(c, src, here, words, rest, asking) },
      )
      under_post(
        c,
        "need-ended/" + key,
        lead == "dismissed" && !open,
        start_at?,
        enter=@motion.trans(
          fade=0.0,
          spec=@motion.Snap(0.0),
          fade_spec=@motion.tween(options_out_ms, ease=Leave, delay=options_out_ms),
        ),
        open=close_gap,
        exit=@motion.trans(spec=@motion.Snap(0.0)),
        close=@motion.Snap(0.0),
        fn() { c.text(words, style=said) |> ignore },
      )
      return
    }
    _ =>
      if asking is Some(_) {
        need_card(c, src, here, words, rest, asking)
        return
      }
  }
  match lead {
    "need" | "done" | "wait" | "watch" =>
      c.box(style=chat_state_row, label=words, fn() {
        c.box(style=look.state_slot, fn() { lead_icon(c, lead, if turn { p.text } else { p.muted }) }) |> ignore
        let after = if rest == "" && lead == "done" { @sf.t("web-main.status.done") } else { rest }
        if after != "" {
          c.text(after, style=said) |> ignore
        }
      })
      |> ignore
    _ => c.text(words, style=said) |> ignore
  }
  match here.view.state_ask {
    Some(seq) => c.box(style=decision_box, fn() { ask_dismiss(c, src, here, seq, true, false, state=true) }) |> ignore
    None => ()
  }
}

///|
/// What the chat needs of the viewer as a card (chat_state): the bell and its words in the ink, 忽略 at its end (under
/// them where a native narrow chat has little room); `seq` the post that asks, None once let go while it shows: in its
/// place how it went (`words`, 已忽略：…), quiet, where the bell's ink began (no bell: nothing is asked any more), as
/// far in as 忽略 is from the end, 忽略 faded
/// where it was, nothing left to press. What it said fades out, then how it went fades in after it (said_in_place): the card's room never changes.
fn need_card(c : @ui.Ctx, src : Source, here : MessageHere, words : String, rest : String, seq : Double?) -> Unit {
  let look = @sf.theme().chat_list
  let stacked = @sf.native_on() && c.width <= chat_narrow_w
  let live = seq is Some(_)
  let (was, now) = said_in_place(c, "need/" + here.station + "/" + here.session, !live)
  let asking = was is Some(_)
  let said = @sf.ask_line_words((if asking { look.state_turn } else { look.state_quiet }).then(chat_state_wraps))
  let dismiss = fn() {
    match seq {
      Some(seq) => ask_dismiss(c, src, here, seq, true, false, at_end=true)
      None => need_dismiss(c, "need-dismissed/" + here.station + "/" + here.session, false)
    }
  }
  // (an option row's ground and room, @sf.ask_line_card: its corner and its sides an option's)
  @sf.ask_line_card(c, column=stacked, fn() {
    let w = c.box(style=if asking { need_card_words } else { need_card_words.then(@sf.ask_line_start(state_icon)) }, label=words, fn() {
      // (the bell where an option's number is, in the middle of its disc: concentric with the row's corner as it is)
      if asking {
        c.box(style=@sf.ask_line_mark(), fn() { lead_icon(c, "need", @sf.theme().p.text, centred=true) }) |> ignore
      }
      let line = if asking { rest } else { words }
      if line != "" {
        c.text(line, style=said) |> ignore
      }
    })
    c.look(w, if asking { was.unwrap() } else { now })
    // (忽略 the library's button ending the row, concentric with its end corner; let go, faded where it was)
    let e = if stacked { c.box(style=need_card_actions, dismiss) } else { c.box(dismiss) }
    c.look(e, was.unwrap_or(@ui.look(alpha=0.0)))
    @motion.leaving(c, e, live)
  })
  |> ignore
}

///|
/// A line under or in a card saying something else once it is answered while it shows (`answered`), in the same room:
/// what it said fading out (options_out_ms, Leave), then what it says now fading in after it (as long, Out); nothing
/// moves. Its looks: what it said while that shows (None once gone), and what it says now.
fn said_in_place(c : @ui.Ctx, key : String, answered : Bool) -> (@ui.Look?, @ui.Look) {
  let was = @motion.presence(
    c,
    "said-was/" + key,
    !answered,
    exit=@motion.trans(fade=0.0, spec=@motion.tween(options_out_ms, ease=Leave)),
  )
  let now = match was {
    Some(_) => @ui.look(alpha=0.0)
    None =>
      @motion.presence(
        c,
        "said-now/" + key,
        true,
        enter=@motion.trans(fade=0.0, spec=@motion.tween(options_out_ms, ease=Out)),
        initial=true,
      ).unwrap_or(@ui.look())
  }
  (was, now)
}

///|
/// What was sent from here and is not in the chat yet (OutboxRow): as the viewer's message (its quotes, its files, its
/// images still going up among them already; any other still going up a card saying how far: the core's; its words:
/// message.mbt mine_message's order),
/// and under it "正在发送" (or what it waits on: its files going up, how far they are together, its ring filling so)
/// once it has been on its way a while (800 ms from when it was sent) until the station takes it, then its time; not
/// sent, said briefly (why in its tip), with sending it again (or, refused as it is, its words back in the composer:
/// 编辑) and dropping it right beside.
fn outbox_row(c : @ui.Ctx, src : Source, here : MessageHere, o : Outgoing) -> Unit {
  let failed = o.state == "failed"
  c.box(style=mine_column, fn() {
    c.box(style=outbox_words, fn() {
      quotes(c, src, here, o.quotes, o.attachments, mine=true)
      message_files(c, src, here, beside_quotes(o.quotes, o.attachments), true)
      for i, u in o.uploads {
        let (name, size, sent) = u
        @sf.file_card(
          c,
          "outbox/" + o.id + "/" + i.to_string(),
          name,
          size.to_double(),
          pending=!failed,
          sent=Some(sent.to_double()),
          error=if failed { if o.error != "" { o.error } else { @sf.t("web-main.chat.notSent") } } else { "" },
        )
        |> ignore
      }
      if o.text != "" {
        mine_bubble(c, here, o.text, "o:" + o.id, marks=sent_marks(o))
      }
    })
    |> ignore
    if failed {
      outbox_unsent(c, src, here, o)
    } else if o.followed {
      ()
    } else if o.state == "sent" {
      // the station took it: its time under it, as its message has it, until the message takes its place
      let at = c.box(fn() { message_time(c, "o:" + o.id, o.time) })
      match flight_here(here) {
        Some(f) if f.text != "" => c.look(at, @ui.look(alpha=flight_settled_of(c, f)))
        _ => ()
      }
    } else {
      let words = if o.waits != "" { o.waits } else { @sf.t("web-main.chat.sending") }
      // (shown once it has been on its way a while: from when its row was first drawn)
      let shows = @kit.after(c, "sending/" + o.id, true, sending_shows_ms)
      let w = c.box(style=msg_waiting, fn() {
        @sf.progress_spinner(c, "sending/" + o.id, o.progress, size=waiting_spin) |> ignore
        c.text(words, style=msg_time) |> ignore
      })
      // (while its words fly here, its room kept and nothing of it seen)
      if !shows || flight_here(here) is Some(_) {
        c.look(w, @ui.look(alpha=0.0))
      }
    }
  })
  |> ignore
}

///|
/// Under what did not go (msgUnsent): 未发送 (why in its tip), then 重试 or 编辑, then 删除; each turning while it is
/// done (the core's doing), a red mark there a few seconds if it failed.
fn outbox_unsent(c : @ui.Ctx, src : Source, here : MessageHere, o : Outgoing) -> Unit {
  let p = @sf.theme().p
  let locked = here.view.offline || here.view.archived
  let on = [("station", here.station), ("id", o.id)]
  let retrying = core_doing(src, ["chat.retry"], on)
  let dropping = core_doing(src, ["chat.discard"], on)
  let busy = retrying || dropping
  c.box(style=unsent_row, fn() {
    let note = c.box(style=unsent_note, fn() {
      @sf.icon(c, "info", size=unsent_icon, color=p.red) |> ignore
      c.text(
        if o.final && o.error != "" {
          @sf.t("web-main.draft.notSent", args=[("error", o.error)])
        } else {
          @sf.t("web-main.chat.unsent")
        },
        style=unsent_words,
      )
      |> ignore
    })
    @sf.tip(c, "unsent/" + o.id, note, if o.error != "" {
      @sf.t("web-main.draft.notSent", args=[("error", o.error)])
    } else {
      @sf.t("web-main.chat.notSent")
    }, repeats=true)
    if o.final {
      // refused as it is (a file this station does not have): its words back in the composer, to be sent anew
      if unsent_button(c, "unsent/edit/" + o.id, "edit", @sf.t("common.edit"), !locked && !busy, false, None) {
        let draft = here.station + ":" + here.session
        let words = o.text
        let id = o.id
        c.tell("unsent/edit/" + o.id, fn() {
          let w = writing(src, draft)
          writing_text(src, w, words)
          outbox_call(src, here, "chat.discard", id)
        })
      }
    } else if unsent_button(
        c,
        "unsent/retry/" + o.id,
        "retry",
        @sf.t("common.retry"),
        !locked && !busy,
        retrying,
        core_failed(src, ["chat.retry"], on),
      ) {
      let id = o.id
      c.tell("unsent/retry/" + o.id, fn() { outbox_call(src, here, "chat.retry", id) })
    }
    if unsent_button(
        c,
        "unsent/drop/" + o.id,
        "trash",
        @sf.t("common.delete"),
        !busy,
        dropping,
        core_failed(src, ["chat.discard"], on),
      ) {
      let id = o.id
      c.tell("unsent/drop/" + o.id, fn() { outbox_call(src, here, "chat.discard", id) })
    }
  })
  |> ignore
}

///|
/// What is asked of the core of an entry of the outbox (`chat.retry`, `chat.discard`): by its thread, else its session.
fn outbox_call(src : Source, here : MessageHere, call : String, id : String) -> Unit {
  let p : Map[String, Json] = { "station": Json::string(here.station), "id": Json::string(id) }
  match here.view.thread {
    Some(th) => p["thread"] = Json::number(th)
    None => p["session"] = Json::string(here.session)
  }
  // (the verb alone: act says it as 无法{what}：{error})
  let what = if call == "chat.retry" {
    @sf.t("android-chat.chat.retry.verb")
  } else {
    @sf.t("android-chat.chat.delete.verb")
  }
  act(src, what, "", call, Json::object(p))
}

///|
/// One of the buttons under what did not go (msgUnsentBtn): its icon (a spinner while it is done; a red mark a few
/// seconds once that failed) and its word, the hover ground and the text's ink under the pointer; at 55% while it may
/// not be pressed. Whether it was pressed.
fn unsent_button(
  c : @ui.Ctx,
  key : String,
  icon : String,
  label : String,
  enabled : Bool,
  busy : Bool,
  failed : String?,
) -> Bool {
  let p = @sf.theme().p
  let id = c.id(key)
  let hot = enabled && c.hovered(id)
  let b = c.box(style=if !enabled { unsent_button_off } else if hot { unsent_button_hot } else { unsent_button_box }, id~, fn() {
    if busy {
      @sf.spinner(c, size=waiting_spin) |> ignore
    } else if failed is Some(_) {
      @sf.icon(c, "info", size=unsent_icon, color=p.red) |> ignore
    } else {
      @sf.icon(c, icon, size=unsent_icon, color=if hot { p.text } else { p.muted }) |> ignore
    }
    c.text(label, style=if hot { unsent_label_hot } else { unsent_label }) |> ignore
  })
  match failed {
    Some(why) => @sf.tip(c, key, b, why)
    None => ()
  }
  c.semantics(b, Button, id~, label~, disabled=!enabled)
  enabled && c.clicked(id)
}

///|
/// An agent at work, in one line (Activity): its picture ringed while it works (a still whole ring while it waits on
/// what it started), what it does now as the core says (each thing a moment at least, crossfading: useSteady) and how
/// long its turn has run; pressed, its history beside the chat. One of several agents: its own stop under the pointer.
/// For a message to come out of its picture the line folds to the picture, which is away while its copy flies
/// (sfbase's emit.mbt).
fn activity_row(c : @ui.Ctx, src : Source, here : MessageHere, a : Agent, em : Emits, rk : String, leaving : Bool, came : Double?) -> Unit {
  let p = @sf.theme().p
  let folded = emit_folded(em, a.key)
  let tail = @motion.animate(c, "tail/" + a.key, if folded { 0.0 } else { 1.0 }, spec=@motion.tween(fold_ms, ease=Out))
  let live = @sfbase.hold(src, @sfbase.chat_scope(here.station, here.session), "live", {
    "station": Json::string(here.station),
    "key": Json::string(a.key),
  })
  let said = match a.wait {
    Some((_, _, w)) => ("wait", if w != "" { w } else { @sf.t("web-main.activity.waiting") }, false, true)
    None => {
      let n = field(field(live.value, "activity"), "now")
      match text(n, "text") {
        "" => ("busy", @sf.t("web-main.activity.busy"), false, false)
        s => (text(n, "key"), s, flag(n, "mono"), flag(n, "important"))
      }
    }
  }
  let now = (src.now)()
  let clock = match a.wait {
    Some((since, most, _)) => {
      let waited = match most {
        Some(sec) => dmin(now, since + sec * 1000.0)
        None => now
      }
      if waited >= now {
        each_second(c, waited - since)
      }
      elapsed(waited - since) +
      (match most {
        Some(sec) => " / " + elapsed(sec * 1000.0)
        None => ""
      })
    }
    None =>
      match a.since {
        Some(s) => {
          each_second(c, now - s)
          elapsed(now - s)
        }
        None => ""
      }
  }
  let id = c.id("activity/" + a.key)
  if c.clicked(id) {
    open_detail(src, here_ref(here), a.key)
  }
  let row = c.id("activity-row/" + a.key)
  let row_key = rk + "\u{1}" + a.key
  let show_stop = here.view.agents.length() > 1 && (c.hovered(row) || c.hovered(id))
  let stop_room = if show_stop { c.space(S6) + c.space(S1) } else { 0.0 }
  let area = c.box(style=activity_row_box, id=row, fn() {
    let line = c.box(style=if here.inline { activity_line_narrow } else { activity_line }, id~, fn() {
      let face = c.box(style=activity_face, fn() {
        // The picture is only pointed at: a press still belongs to the activity line that opens its history.
        let avatar = c.id("activity-avatar/" + a.key)
        let av = c.box(id=avatar, taps=false, points=true, fn() { agent_avatar(c, src, here, "a:" + a.key, a.maker, a.runtime, "", "") })
        @motion.measure(c, av, "emit-avatar/" + rk + "/" + a.key)
        if em.copied != a.key {
          agent_hover(c, src, here, "activity-agent-hover/" + a.key, avatar, a.key)
        }
        let ring = @motion.animate(c, "ring/" + here.station + "/" + a.key, if leaving { 0.0 } else { 1.0 }, spec=@motion.tween(
          ring_out_ms,
          ease=Leave,
        ))
        let rl = c.layer(fn() { work_ring(c, a.wait is Some(_)) })
        c.look(rl, @ui.look(alpha=ring))
      })
      // away while its copy flies, its ring with it
      if em.copied == a.key {
        c.look(face, @ui.look(alpha=0.0))
      }
      // what it does now and how long: folded away to its width's share, cut there, faded
      let natural = match @motion.measured_size(c, "emit-tail/" + rk + "/" + a.key) {
        Some((w, _)) => w
        None => 0.0
      }
      let cut = tail < 1.0 && natural > 0.0
      let tb = c.box(style=if cut { activity_tail_cut.then(@ui.style(max_w=Fixed(natural * tail))) } else { activity_tail }, fn() {
        // Keep the measured content at its whole width inside the clipping room. If it stops being measured while
        // folded, the next build loses that width and opens it again, alternating between the two on every frame.
        let inner = c.box(style=activity_tail, keep=cut, fn() {
          steady_words(c, row_key, said, c.hovered(id), came, clock, stop_room)
          if clock != "" {
            let time = c.text(clock, style=activity_clock)
            // The row can be kept after its arrival cause is forgotten. Its paint stays the same: the settled look
            // is the identity whether the cause is still present or has been let go.
            let at = if c.still() { None } else { came }
            c.look_by(time, fn() {
              let k = match at {
                Some(start) => @ui.Ease::Out.at(dmax(dmin((c.moment() - start) / @ui.row_size_ms, 1.0), 0.0))
                None => 1.0
              }
              @ui.look(alpha=k)
            })
          }
        })
        @motion.measure(c, inner, "emit-tail/" + rk + "/" + a.key)
      })
      if tail < 1.0 {
        c.look(tb, @ui.look(alpha=tail))
      }
    })
    c.semantics(line, Button, id~, label=a.who + "：" + said.1)
    // one of several agents: stopped alone from its row, under the pointer
    if show_stop {
      let stop = c.id("activity-stop/" + a.key)
      let label = @sf.t("web-main.activity.stop", args=[("who", a.who)])
      @sf.tip(c, "activity-stop/" + a.key, stop, label)
      let b = c.box(style=if c.hovered(stop) { activity_stop_hot } else { activity_stop }, id=stop, fn() {
        @sf.icon(c, "stop", size=stop_icon, color=if c.hovered(stop) { p.text } else { p.muted }) |> ignore
      })
      c.semantics(b, Button, id=stop, label~)
      if c.clicked(stop) {
        let key = a.key
        let station = here.station
        c.tell("activity-stop/" + a.key, fn() {
          act(src, @sf.t("web-pages.chat.stop"), "", "session.stop", {
            "station": Json::string(station),
            "key": Json::string(key),
          }, done=@sf.t("web-pages.chat.stopAsked"))
        })
      }
    }
  })
  @motion.measure(c, area, "activity-area/" + row_key)
}

///|
/// The ring round an agent at work (activityRing): eight arcs in the accent stepping round; waiting on what it started,
/// a still whole ring in the line's ink.
fn work_ring(c : @ui.Ctx, waiting : Bool) -> Unit {
  let p = @sf.theme().p
  if waiting {
    c.box(style=ring_waiting, fn() {  }) |> ignore
  } else {
    @sf.segments(c, ring_side, ring_stroke, p.accent, p.bg) |> ignore
  }
}

///|
/// The space the activity's words can use, leaving its clock and any stop control whole at the end of the row.
fn activity_visible_width(c : @ui.Ctx, row : String, clock : String, stop_room : Double) -> Double {
  match (@motion.measured_rect(c, "activity-area/" + row), @motion.measured_rect(c, "now-room/" + row)) {
    (Some((x, _, w, _)), Some((start, _, _, _))) =>
      dmax(x + w - start - stop_room - (if clock == "" { 0.0 } else { c.words_across(clock, activity_clock) + c.space(S2) }), 0.0)
    _ => dmax(c.width - stop_room, 0.0)
  }
}

///|
/// What an activity says now, steadied: brief routine steps are coalesced, while important ones have a turn even if
/// they have finished. Each step has time to be read; each glyph gives way to the next step's at its place.
/// The line goes from the one's width to the other's (its clock with it); the same thing's new words show at once.
/// In the muted ink, the text's under the pointer.
fn steady_words(c : @ui.Ctx, row : String, said : (String, String, Bool, Bool), hot : Bool, came : Double?, clock : String, stop_room : Double) -> Unit {
  let (key, words, mono, important) = said
  let st = match steadies.get(row) {
    Some(s) => s
    None => {
      let s = { key, words, mono, important, was: "", was_mono: false, at: c.moment(), pending: None, pending_at: 0.0, important_next: None, came: @signals.signal(-1.0e9), asked: 0.0, places: 1 }
      steadies[row] = s
      s
    }
  }
  let swap = @motion.anim(c, "now-swap/" + row, 1.0, global=true)
  let reveal = @motion.anim(c, "now-glyphs/" + row, 1.0, global=true)
  let new_line = match came {
    Some(at) => at != st.came.get()
    None => false
  }
  if new_line {
    let at = came.unwrap()
    st.came.set(at)
    st.key = key
    st.words = words
    st.mono = mono
    st.important = important
    st.was = ""
    st.at = at
    st.pending = None
    st.important_next = None
    swap.snap(1.0)
    reveal.snap(0.0)
    // A list can reserve this row's turn in the future, while the message above it is still landing. A delayed
    // tween waits for that turn; an already-started turn catches up from its declared start.
    let later = dmax(at - c.moment(), 0.0)
    reveal.animate(1.0, @motion.tween(activity_glyph_in_ms, ease=Linear, delay=later), start_at?=if later > 0.0 { None } else { Some(at) })
  } else {
    let now = c.moment()
    let mut next : (String, String, Bool, Bool, Double)? = None
    if st.came.get() > now {
      // Before the reserved row's turn, its first words are whatever the agent is doing at that turn.
      st.key = key
      st.words = words
      st.mono = mono
      st.important = important
      st.pending = None
      st.important_next = None
    } else {
      if important && key != st.key && words != st.words {
        let since = match st.important_next {
          Some((old, _, _, at)) if old == key => at
          _ => now
        }
        st.important_next = Some((key, words, mono, since))
      }
      match st.important_next {
        Some((next_key, next_words, next_mono, since)) => {
          // Do not restart a change already under way, or interrupt an important step before it can be read.
          let wait = if st.important {
            steady_dwell_ms
          } else if c.reduced_motion() {
            0.0
          } else if st.was == "" {
            activity_glyph_in_ms
          } else {
            @sfbase.glyph_change_in_ms
          }
          let at = dmax(st.at + wait, since)
          if now < at {
            c.shows_until(at)
          } else {
            next = Some((next_key, next_words, next_mono, true, at))
            st.important_next = None
            // The live step may have moved on while the important one waited. Give it a turn after this one.
            if key != next_key && words != next_words {
              st.pending = Some(key)
              st.pending_at = now
              c.shows_until(dmax(at + steady_dwell_ms, now + steady_candidate_ms))
            } else {
              st.pending = None
            }
          }
        }
        None =>
          if key == st.key || words == st.words {
            st.key = key
            st.words = words
            st.mono = mono
            st.important = important
            st.pending = None
          } else {
            // A routine step gone before its own glyph change could finish never starts one.
            if st.pending != Some(key) {
              st.pending = Some(key)
              st.pending_at = now
            }
            let at = dmax(st.at + steady_dwell_ms, st.pending_at + steady_candidate_ms)
            if now < at {
              c.shows_until(at)
            } else {
              next = Some((key, words, mono, false, at))
              st.pending = None
            }
          }
      }
    }
    if next is Some((next_key, next_words, next_mono, next_important, at)) {
      st.was = st.words
      st.was_mono = st.mono
      st.key = next_key
      st.words = next_words
      st.mono = next_mono
      st.important = next_important
      st.at = at
      swap.snap(0.0)
      reveal.snap(0.0)
      // (a Move as long as the line's change in width)
      let style = if hot { now_words_hot } else { now_words }
      let old_cells = c.words_glyph_cells(st.was, style, mono=st.was_mono)
      let new_cells = c.words_glyph_cells(st.words, style, mono=st.mono)
      // The reading order spans the part that can actually be seen, even when one step is much longer than the line.
      let visible = activity_visible_width(c, row, clock, stop_room)
      st.places = activity_change_places(old_cells, new_cells, visible)
      reveal.animate(1.0, @motion.tween(@sfbase.glyph_change_in_ms, ease=Linear), start_at=at)
      let widened = dmin(c.words_across(st.words, style, mono=st.mono), visible) - dmin(c.words_across(st.was, style, mono=st.was_mono), visible)
      swap.animate(1.0, @motion.move(over=dmax(c.text_size(Meta).1, widened.abs())), start_at=at)
    }
  }
  let k = swap.get()
  let style = if hot { now_words_hot } else { now_words }
  // the line short of what they asked of it last frame: it cuts them where it ends during the turn too
  let cut = match @motion.measured_size(c, "now-room/" + row) {
    Some((w, _)) => w < st.asked - 0.5
    None => false
  }
  let room = c.box(style=now_room, fn() {
    if k < 1.0 || (!reveal.over() && st.was != "") {
      // Both steps keep their shaped text. At each place the outgoing glyph fades before the incoming one arrives,
      // so their ink does not overlap. The window keeps the line no wider than it has room for.
      let line = c.text_size(Meta).1
      let whole_from = c.words_across(st.was, style, mono=st.was_mono)
      let whole_to = c.words_across(st.words, style, mono=st.mono)
      let visible = activity_visible_width(c, row, clock, stop_room)
      // The clock travels between the widths actually visible at each end, not through text beyond the row.
      let from = dmin(whole_from, visible)
      let to = dmin(whole_to, visible)
      let old_cells = c.words_glyph_cells(st.was, style, mono=st.was_mono)
      let new_cells = c.words_glyph_cells(st.words, style, mono=st.mono)
      let across = from + (to - from) * k
      st.asked = across
      let mut changing = -1
      let window = c.box(style=@ui.style(w=Cut, max_w=Fixed(across), h=Fixed(line), clip=true), fn() {
        let wide = if whole_from > whole_to { whole_from } else { whole_to }
        let clipped = whole_from > visible + 0.5 || whole_to > visible + 0.5
        // Both lines are layered, so the incoming one cannot open a content-sized box on its own.
        let both = c.box(style=@ui.style(w=Fixed(if cut || clipped { across } else { wide }), h=Fixed(line)), fn() {
          let before = c.rich([@ui.span(st.was, mono=st.was_mono)], style~)
          activity_change_glyphs(c, before, row, reveal, false, k, old_cells, new_cells, st.places)
          c.layer(fn() {
            c.box(style=now_glyph_layer, fn() {
              let next = c.rich([@ui.span(st.words, mono=st.mono)], style~)
              activity_change_glyphs(c, next, row, reveal, true, k, old_cells, new_cells, st.places)
            }) |> ignore
          }) |> ignore
        })
        changing = both
      })
      // Fade the end where the window widens, narrows, or cuts the line short.
      let gone = (to - from).abs()
      let from_fade = if whole_from > visible + 0.5 { @ui.cut_soft_most } else { 0.0 }
      let to_fade = if whole_to > visible + 0.5 { @ui.cut_soft_most } else { 0.0 }
      let end = if cut { @ui.cut_soft_most } else {
        dmax(@ui.cut_soft(gone * k, gone * (1.0 - k)), from_fade * (1.0 - k) + to_fade * k)
      }
      c.fade_to(changing, window, end~)
    } else {
      st.asked = c.words_across(st.words, style, mono=st.mono)
      let next = c.rich([@ui.span(st.words, mono=st.mono)], style~)
      activity_glyphs(c, next, row, reveal)
    }
  })
  @motion.measure(c, room, "now-room/" + row)
}

///|
/// How many positions of either step can be seen; glyphs past the window do not make the visible change rush.
fn activity_change_places(old_cells : Array[(Double, Double)], new_cells : Array[(Double, Double)], visible : Double) -> Int {
  let mut count = 0
  let length = if old_cells.length() > new_cells.length() { old_cells.length() } else { new_cells.length() }
  for i in 0..<length {
    if (i < old_cells.length() && old_cells[i].0 < visible) || (i < new_cells.length() && new_cells[i].0 < visible) {
      count = i + 1
    }
  }
  if count > 0 { count } else { 1 }
}

///|
/// The two shaped lines share a change for each glyph's place; one fades before the other begins. Their centres go
/// together from the old line's positions to the new line's, even when their advances differ.
fn activity_change_glyphs(
  c : @ui.Ctx,
  node : Int,
  row : String,
  reveal : @motion.Anim,
  incoming : Bool,
  k : Double,
  old_cells : Array[(Double, Double)],
  new_cells : Array[(Double, Double)],
  places : Int,
) -> Unit {
  c.glyphs_by(node, fn(at) {
    let intervals = if places > 1 { places - 1 } else { 1 }
    let along = dmin(at.index.to_double() / intervals.to_double(), 1.0)
    let look = @sfbase.glyph_change(reveal.get() * @sfbase.glyph_change_in_ms, along * @sfbase.glyph_change_line_ms, at.index, row.length(), incoming)
    let (dx, sx) = if at.index < old_cells.length() && at.index < new_cells.length() {
      let (old_x, old_w) = old_cells[at.index]
      let (new_x, new_w) = new_cells[at.index]
      let distance = new_x - old_x
      let width = old_w + (new_w - old_w) * k
      let face_w = if incoming { new_w } else { old_w }
      (if incoming { -distance * (1.0 - k) } else { distance * k }, if face_w > 0.0 { dmin(width / face_w, 1.0) } else { 1.0 })
    } else if at.index < old_cells.length() && new_cells.length() > 0 {
      // The old line is longer: its tail follows the end of the paired cells instead of being run over by them.
      let n = new_cells.length() - 1
      let (old_x, old_w) = old_cells[n]
      let (new_x, new_w) = new_cells[n]
      ((new_x + new_w / 2.0 - old_x - old_w / 2.0) * k, 1.0)
    } else if at.index < new_cells.length() && old_cells.length() > 0 {
      // The new line is longer: its tail starts after the old line, preserving its own spacing as the room opens.
      let n = old_cells.length() - 1
      let (old_x, old_w) = old_cells[n]
      let (new_x, new_w) = new_cells[n]
      ((old_x + old_w / 2.0 - new_x - new_w / 2.0) * (1.0 - k), 1.0)
    } else {
      (0.0, 1.0)
    }
    { ..look, dx, sx }
  })
}

///|
/// The first activity uses the message's per-glyph arrival. Existing activity when a chat opens has no arrival clock
/// and is shown whole.
fn activity_glyphs(c : @ui.Ctx, node : Int, row : String, reveal : @motion.Anim) -> Unit {
  if reveal.over() {
    return
  }
  let key = "now-glyph-box/" + row
  @motion.measure(c, node, key)
  c.glyphs_by(node, fn(at) {
    match @motion.measured_rect(c, key) {
      Some((x, _, w, _)) => {
        let along = if w > 0.0 { dmax(dmin((at.x - x) / w, 1.0), 0.0) } else { 0.0 }
        let elapsed = reveal.get() * activity_glyph_in_ms - activity_glyph_delay_ms
        @sfbase.glyph_in(elapsed, along * @sfbase.glyph_line_ms, at.index, row.length())
      }
      None => { alpha: 0.0, dx: 0.0, dy: 0.0, scale: 1.0, sx: 1.0 }
    }
  })
}

///|
/// Let a new activity's room begin opening before its first words arrive.
let activity_glyph_delay_ms : Double = @ui.move_least_ms / 2.0

///|
let activity_glyph_in_ms : Double = activity_glyph_delay_ms + @sfbase.glyph_line_in_ms

///|
/// What each activity shows, steadied (steady_words), by its row.
priv struct Steady {
  mut key : String
  mut words : String
  mut mono : Bool
  mut important : Bool
  mut was : String
  mut was_mono : Bool
  mut at : Double
  /// the latest different step and when it was first said
  mut pending : String?
  mut pending_at : Double
  /// an important step waiting for an earlier change, and when it was first said
  mut important_next : (String, String, Bool, Double)?
  /// when this agent's current activity row came into the watched list
  came : @signals.Signal[Double]
  /// how wide the words asked their line to be, the last frame they were laid out
  mut asked : Double
  /// how many places of the current step change fit in the line
  mut places : Int
}

///|
let steadies : Map[String, Steady] = {}

///|
/// What the rows keep of their own, let go (the package's reset).
fn rows_reset() -> Unit {
  steadies.clear()
  dismissed.clear()
}

///|
/// "正在发送" shows once a message has been on its way this long (SENDING_SHOWS_MS).
pub let sending_shows_ms : Double = 800.0

///|
/// An activity's line folding to its picture (FOLD_MS), its ring going as its turn ends (160).
let fold_ms : Double = 200.0

///|
let ring_out_ms : Double = 160.0

///|
/// Each thing an activity says stays this long at least (DWELL_MS) before the next begins.
let steady_dwell_ms : Double = 700.0

///|
/// A step gone before its glyphs could have arrived does not interrupt the words shown.
let steady_candidate_ms : Double = @sfbase.glyph_change_in_ms

///|
/// The ring round the picture: 24 across, its arcs 1.5 (3 round the 18).
let ring_side : Double = 24.0

///|
let ring_stroke : Double = 1.5

///|
/// The icons under what did not go (12), and an activity's stop (12).
let unsent_icon : Double = 12.0

///|
let stop_icon : Double = 12.0

///|
/// The unread line (chatUnreadLine): its rules each side 10 from its words (12 in 500, the accent), the accent at 50%.
// kept across runs: a value (no field of it changes)
let unread_row : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let unread_rule : @ui.Style = @ui.style(w=@sf.grow, h=SPx, bg=A(Accent, O50))

///|
// kept across runs: a value (no field of it changes)
let unread_words : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=AccentText, wrap=false)

///|
/// The pages coming (chatOlder: 4 over, 8 under; chatNewer: 8 over, 4 under), a chat with nothing yet (chatEmpty).
// kept across runs: a value (no field of it changes)
let older_row : @ui.Style = @ui.css("w=Full pt=S1 pb=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let newer_row : @ui.Style = @ui.css("w=Full pt=S2 pb=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let empty_row : @ui.Style = @ui.css("w=Full py=S8 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let chat_empty_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Muted)

///|
/// What was sent from here, its words and files; what did not go as they are, not faded (at 55% its words were 3.4 to 1:
/// docs/ui-panels.md 对比度), the red under it saying so.
// kept across runs: a value (no field of it changes)
let outbox_words : @ui.Style = @ui.css("w=Full gap=S1 align=AEnd")

///|
/// Under it (msgUnsent): 4 under, at the column's end, 2 apart; its note 6 before the buttons.
// kept across runs: a value (no field of it changes)
let unsent_row : @ui.Style = @ui.css("row pt=S1 gap=SPx align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let unsent_note : @ui.Style = @ui.css("row pr=S1_5 gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let unsent_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Danger, wrap=false)

///|
/// Its buttons (msgUnsentBtn): 2 by 6 in, 4 apart, 7 round; the hover ground under the pointer; at 55% when they may
/// not be pressed.
// kept across runs: a value (no field of it changes)
let unsent_button_box : @ui.Style = @ui.css("row px=S1_5 py=S0_5 gap=S1 radius=Md align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let unsent_button_hot : @ui.Style = unsent_button_box.then(@ui.css("bg=Hover"))

///|
// kept across runs: a value (no field of it changes)
let unsent_button_off : @ui.Style = unsent_button_box.then(@ui.css("opacity=O55"))

///|
// kept across runs: a value (no field of it changes)
let unsent_label : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let unsent_label_hot : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
/// An activity's row (activityRow): its line and its stop 4 apart.
// kept across runs: a value (no field of it changes)
let activity_row_box : @ui.Style = @ui.css("row w=Full gap=S1 align=ACenter")

///|
/// Its line (activityLine): its picture where the messages' pictures are, out in the margin before the words
/// (message_avatar_out), the picture and what it does 8 apart, 6 round.
// kept across runs: a value (no field of it changes)
let activity_line : @ui.Style = @ui.style(row=true, gap=S2, radius=Md, align=ACenter, ml=@sf.message_avatar_out)

///|
/// Narrow: its picture at the row's start, as the messages' are there (inlineHeads).
// kept across runs: a value (no field of it changes)
let activity_line_narrow : @ui.Style = @ui.css("row gap=S2 radius=Md align=ACenter")

///|
/// Its picture with the ring round it (activityAvatar): 24 across, the picture in its middle; the ring reaching 3 past
/// the picture on either side (activityRing inset -3), into no room of the line's: what the line lines up is the
/// picture, in the messages' pictures' column.
// kept across runs: a value (no field of it changes)
let activity_face : @ui.Style = @ui.css("w=S6 h=S6 align=ACenter justify=JCenter").then(@sf.outset(ring_room))

///|
// kept across runs: a value (no field of it changes)
let ring_waiting : @ui.Style = @ui.css("w=S6 h=S6 radius=Full border=B1_5 border_color=Line")

///|
/// What it does and how long (activityTail): 8 apart; cut at its width's share as it folds.
// kept across runs: a value (no field of it changes)
let activity_tail : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let activity_tail_cut : @ui.Style = activity_tail.then(@ui.css("clip"))

///|
/// What it does now (activityNowText): 13, muted (the text's under the pointer), one line, cut short with an ellipsis
/// where the line has less room (its min-width 0, text-overflow): an agent's step is as long as it says it, so the
/// words give way and nothing else does; how long (activityElapsed, flex none), subtle, whole.
// kept across runs: a value (no field of it changes)
let now_room : @ui.Style = @ui.css("row")

///|
/// The incoming line starts at the same edge as the line it replaces.
// kept across runs: a value (no field of it changes)
let now_glyph_layer : @ui.Style = @ui.css("align=AStart")

///|
// kept across runs: a value (no field of it changes)
let now_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let now_words_hot : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let activity_clock : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, wrap=false)

///|
/// Its stop (activityStop): 24 round in 6, the muted ink; the hover ground and the text's under the pointer.
// kept across runs: a value (no field of it changes)
let activity_stop : @ui.Style = @ui.css("w=S6 h=S6 radius=Md align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let activity_stop_hot : @ui.Style = activity_stop.then(@ui.css("bg=Hover"))

///|
/// Where it stands (chat_state): its icon's column (the theme's lists' state_slot, as high as a line of its words: the
/// row's line, the theme's), 6 before them; its words wrapping.
// kept across runs: a value (no field of it changes)
let chat_state_row : @ui.Style = @ui.css("row w=Full gap=S1_5 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let chat_state_wraps : @ui.TextStyle = @ui.text_style(wrap=true)

///|
/// What the chat needs of the viewer, with 忽略 (chat_state): its words taking what 忽略 leaves at its end (a column of
/// them, 忽略 under them at the end, where a native narrow chat has little room); after the bell's disc as far as a
/// state line's words after its icon (no disc drawn round it, an option's 12 leaves the bare bell far off).
// kept across runs: a value (no field of it changes)
let need_card_words : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S1_5, align=AStart)

///|
// kept across runs: a value (no field of it changes)
let need_card_actions : @ui.Style = @ui.css("row w=Full pt=S1_5 justify=JEnd")
