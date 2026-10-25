// What a chat's list holds on the desktop besides its messages (ember web/src/Chat.tsx ChatRows, OutboxRow, Activity,
// useSteady; Chat.css.ts chatUnreadLine, chatOlder, chatNewer, chatEmpty, msgUnsent, msgUnsentBtn, agentActivity,
// activityLine, activityAvatar, activityRing, activityTail, activityNowText, activityElapsed, activityStop): the line
// over what is new, the pages being brought in, what was sent from here and is not in the chat yet, and its agents at
// work.

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
/// What was sent from here and is not in the chat yet (OutboxRow): as the viewer's message (its quotes, its words, its
/// files; those still going up as cards saying how far), and under it "正在发送" once it has been on its way a while
/// (800 ms from when it was sent) until the station takes it, then its time; not sent, said briefly (why in its tip),
/// with sending it again (or, refused as it is, its words back in the composer: 编辑) and dropping it right beside.
fn outbox_row(c : @ui.Ctx, src : Source, here : MessageHere, o : Outgoing) -> Unit {
  let failed = o.state == "failed"
  c.box(style=mine_column, fn() {
    c.box(style=if failed { outbox_words_unsent } else { outbox_words }, fn() {
      quotes(c, src, here, o.quotes, o.attachments, mine=true)
      if o.text != "" {
        mine_bubble(c, here, o.text, "o:" + o.id)
      }
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
      let words = if o.waits != "" {
        o.waits
      } else if o.uploads.length() > 0 {
        @sf.t("common.uploading")
      } else {
        @sf.t("web-main.chat.sending")
      }
      // (shown once it has been on its way a while: from when its row was first drawn)
      let shows = @kit.after(c, "sending/" + o.id, true, sending_shows_ms)
      let w = c.box(style=msg_waiting, fn() {
        @sf.spinner(c, size=waiting_spin) |> ignore
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
    })
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
  if enabled {
    c.cursor(id, Hand)
  }
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
  c.semantics(b, Button, id~, label~)
  enabled && c.clicked(id)
}

///|
/// An agent at work, in one line (Activity): its picture ringed while it works (a still whole ring while it waits on
/// what it started), what it does now as the core says (each thing a moment at least, crossfading: useSteady) and how
/// long its turn has run; pressed, its history beside the chat. One of several agents: its own stop under the pointer.
/// For a message to come out of its picture the line folds to the picture, which is away while its copy flies
/// (sfbase's emit.mbt).
fn activity_row(c : @ui.Ctx, src : Source, here : MessageHere, a : Agent, em : Emits, rk : String, leaving : Bool) -> Unit {
  let p = @sf.theme().p
  let folded = emit_folded(em, a.key)
  let tail = @motion.animate(c, "tail/" + a.key, if folded { 0.0 } else { 1.0 }, spec=@motion.tween(fold_ms, ease=Out))
  let live = (src.topic)("live", { "station": Json::string(here.station), "key": Json::string(a.key) })
  let said = match a.wait {
    Some((_, _, w)) => ("wait", if w != "" { w } else { @sf.t("web-main.activity.waiting") })
    None => {
      let n = field(field(live.value, "activity"), "now")
      match text(n, "text") {
        "" => ("busy", @sf.t("web-main.activity.busy"))
        s => (text(n, "key"), s)
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
  c.cursor(id, Hand)
  if c.clicked(id) {
    open_detail(src, here_ref(here), a.key)
  }
  let row = c.id("activity-row/" + a.key)
  c.box(style=activity_row_box, id=row, fn() {
    let line = c.box(style=if here.inline { activity_line_narrow } else { activity_line }, id~, fn() {
      let face = c.box(style=activity_face, fn() {
        let av = c.box(fn() { agent_avatar(c, src, here, "a:" + a.key, a.maker, a.runtime, "", "") })
        @motion.measure(c, av, "emit-avatar/" + rk + "/" + a.key)
        let ring = @motion.animate(c, "ring/" + here.station + "/" + a.key, if leaving { 0.0 } else { 1.0 }, spec=@motion.tween(
          ring_out_ms,
        ))
        let rl = c.layer(fn() { work_ring(c, a.wait is Some(_)) })
        c.look(rl, @ui.look(alpha=ring))
      })
      // away while its copy flies, its ring with it
      if em.copied == a.key {
        c.look(face, @ui.look(alpha=0.0))
      }
      // what it does now and how long: folded away to its width's share, cut there, faded
      let natural = match @motion.measured_rect(c, "emit-tail/" + rk + "/" + a.key) {
        Some(r) => r.2
        None => 0.0
      }
      let cut = tail < 1.0 && natural > 0.0
      let tb = c.box(style=if cut { activity_tail_cut.then(@ui.style(max_w=Fixed(natural * tail))) } else { activity_tail }, fn() {
        let inner = c.box(style=activity_tail, fn() {
          steady_words(c, rk + "\u{1}" + a.key, said, c.hovered(id))
          if clock != "" {
            c.text(clock, style=activity_clock) |> ignore
          }
        })
        if !cut {
          @motion.measure(c, inner, "emit-tail/" + rk + "/" + a.key)
        }
      })
      if tail < 1.0 {
        c.look(tb, @ui.look(alpha=tail))
      }
    })
    c.semantics(line, Button, id~, label=a.who + "：" + said.1)
    // one of several agents: stopped alone from its row, under the pointer
    if here.view.agents.length() > 1 && (c.hovered(row) || c.hovered(id)) {
      let stop = c.id("activity-stop/" + a.key)
      c.cursor(stop, Hand)
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
  |> ignore
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
/// What an activity says now, steadied (useSteady): another thing replaces the one shown after it has stayed 700 ms,
/// crossfading (240 ms); the same thing's new words show at once. In the muted ink, the text's under the pointer.
fn steady_words(c : @ui.Ctx, row : String, said : (String, String), hot : Bool) -> Unit {
  let (key, words) = said
  let st = match steadies.get(row) {
    Some(s) => s
    None => {
      let s = { key, words, was: "", at: -1.0e9 }
      steadies[row] = s
      s
    }
  }
  let swap = @motion.anim(c, "now-swap/" + row, 1.0, global=true)
  if key == st.key || words == st.words {
    st.key = key
    st.words = words
  } else if c.now >= st.at + steady_dwell_ms {
    st.was = st.words
    st.key = key
    st.words = words
    st.at = c.now
    swap.snap(0.0)
    swap.animate(1.0, @motion.tween(steady_cross_ms, ease=Out))
  } else {
    c.wake_in(st.at + steady_dwell_ms - c.now)
  }
  let k = swap.get()
  c.box(style=now_room, fn() {
    let cur = c.text(st.words, style=if hot { now_words_hot } else { now_words })
    if k < 1.0 {
      c.look(cur, @ui.look(alpha=k))
      let was = c.layer(fn() { c.text(st.was, style=if hot { now_words_hot } else { now_words }) |> ignore })
      c.look(was, @ui.look(alpha=1.0 - k))
    }
  })
  |> ignore
}

///|
/// What each activity shows, steadied (steady_words), by its row.
priv struct Steady {
  mut key : String
  mut words : String
  mut was : String
  mut at : Double
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
/// Each thing an activity says stays this long at least, and crossfades this long (DWELL_MS, CROSS_MS).
let steady_dwell_ms : Double = 700.0

///|
let steady_cross_ms : Double = 240.0

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
let unread_words : @ui.TextStyle = @ui.text_style(size=Xs, weight=Medium, color=Accent, wrap=false)

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
let chat_empty_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted)

///|
/// What did not go, its words and files at 55%.
// kept across runs: a value (no field of it changes)
let outbox_words : @ui.Style = @ui.css("w=Full gap=S1 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let outbox_words_unsent : @ui.Style = outbox_words.then(@ui.css("opacity=O55"))

///|
/// Under it (msgUnsent): 4 under, at the column's end, 2 apart; its note 6 before the buttons.
// kept across runs: a value (no field of it changes)
let unsent_row : @ui.Style = @ui.css("row pt=S1 gap=SPx align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let unsent_note : @ui.Style = @ui.css("row pr=S1_5 gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let unsent_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Danger, wrap=false)

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
let unsent_label : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let unsent_label_hot : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

///|
/// An activity's row (activityRow): its line and its stop 4 apart.
// kept across runs: a value (no field of it changes)
let activity_row_box : @ui.Style = @ui.css("row w=Full gap=S1 align=ACenter")

///|
/// Its line (activityLine): out in the margin with the pictures (columns.activity: 35 before the words), the picture
/// and what it does 8 apart, 6 round.
// kept across runs: a value (no field of it changes)
let activity_line : @ui.Style = @ui.style(row=true, gap=S2, radius=Md, align=ACenter, ml=@sf.activity_out)

///|
/// Narrow (Chat.css.ts activityLine, max-width 700: columns.activityNarrow): 9 out into the list's 16.
// kept across runs: a value (no field of it changes)
let activity_line_narrow : @ui.Style = @ui.style(row=true, gap=S2, radius=Md, align=ACenter, ml=@sf.activity_out_narrow)

///|
/// Its picture with the ring round it (activityAvatar): 24 across, the picture in its middle.
// kept across runs: a value (no field of it changes)
let activity_face : @ui.Style = @ui.css("w=S6 h=S6 align=ACenter justify=JCenter")

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
// kept across runs: a value (no field of it changes)
let now_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let now_words_hot : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let activity_clock : @ui.TextStyle = @ui.text_style(size=Sm, color=Subtle, wrap=false)

///|
/// Its stop (activityStop): 24 round in 6, the muted ink; the hover ground and the text's under the pointer.
// kept across runs: a value (no field of it changes)
let activity_stop : @ui.Style = @ui.css("w=S6 h=S6 radius=Md align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let activity_stop_hot : @ui.Style = activity_stop.then(@ui.css("bg=Hover"))
