// What a chat's list holds besides its messages, and the lines under the viewer's own, as nodes of the window's tree
// (chat_rows.mbt's unread_line, pages_coming, older_failed, chat_empty, chat_state as a line; message.mbt's
// blocked_line and the line its message waits on; chat_rows.mbt's 正在发送 under what is sent from here): the same
// lines, made once, each following what it is told as that changes. A row's room is message_row_frame_node's.

///|
/// Over the first message unread when the chat opened (unread_line's): its words in the accent, a rule each side.
// the chat's page as nodes: held by its tests, not used by the app yet
#warnings("-unused_value")
fn unread_line_node(parent : @view.View) -> @view.View {
  parent.box(fn(r) {
    @sf.style_node(r, fn() { unread_row })
    r.box(fn(x) { @sf.style_node(x, fn() { unread_rule }, in_row=true) }) |> ignore
    @sf.words_node(r, fn() { @sf.t("web-main.chat.unreadLine") }, fn() { unread_words }) |> ignore
    r.box(fn(x) { @sf.style_node(x, fn() { unread_rule }, in_row=true) }) |> ignore
  })
}

///|
/// The page before (`older`, as it is now) or after being brought in (pages_coming's): a spinner in the middle.
// the chat's page as nodes: held by its tests, not used by the app yet
#warnings("-unused_value")
fn pages_coming_node(parent : @view.View, older : () -> Bool) -> @view.View {
  parent.box(fn(r) {
    @sf.style_node(r, fn() { if older() { older_row } else { newer_row } })
    @sf.spinner_node(r) |> ignore
  })
}

///|
/// The page before that could not be read, in its place (older_failed's): why, as the core says it.
// the chat's page as nodes: held by its tests, not used by the app yet
#warnings("-unused_value")
fn older_failed_node(parent : @view.View, why : () -> String) -> @view.View {
  parent.box(fn(r) {
    @sf.style_node(r, fn() { older_row })
    @sf.words_node(r, fn() { @sf.t("web-main.chat.olderFailed", args=[("why", why())]) }, fn() { older_failed_words })
    |> ignore
  })
}

///|
/// A chat with nothing in it yet (chat_empty's).
// the chat's page as nodes: held by its tests, not used by the app yet
#warnings("-unused_value")
fn chat_empty_node(parent : @view.View) -> @view.View {
  parent.box(fn(r) {
    @sf.style_node(r, fn() { empty_row })
    @sf.words_node(r, fn() { @sf.t("web-main.chat.empty") }, fn() { chat_empty_words }) |> ignore
  })
}

///|
/// Where the chat stands, under its last message, nothing asked of the viewer (chat_state's line): `words` led as the
/// chat's row leads them where `lead` is one with an icon (need, done, wait, watch: lead_icon_node's in the theme's
/// column, then `rest`, done with nothing said its word), whole, wrapping; else `words` alone. What it needs of a person
/// in the ink, the rest quiet. Each as the core says it now.
fn chat_state_line_node(
  parent : @view.View,
  words : () -> String,
  lead : () -> String,
  rest : () -> String,
) -> @view.View {
  let said = fn() {
    let look = @sf.theme().chat_list
    (if lead() == "need" { look.state_turn } else { look.state_quiet }).then(chat_state_wraps)
  }
  parent.box(fn(s) {
    s.pick(fn() {
      match lead() {
        "need" | "done" | "wait" | "watch" => lead()
        _ => ""
      }
    }, fn(p, icon) {
      match icon {
        "" => @sf.words_node(p, words, said) |> ignore
        icon =>
          p.box(fn(line) {
            @sf.style_node(line, fn() { chat_state_row })
            // (read out whole, as its box was labelled)
            line.says(By(fn() { Some(@view.said(Text, label=words())) })) |> ignore
            line.box(fn(slot) {
              @sf.style_node(slot, fn() { @sf.theme().chat_list.state_slot }, in_row=true)
              lead_icon_node(slot, icon, fn() {
                let pal = @sf.theme().p
                if icon == "need" {
                  pal.text
                } else {
                  pal.muted
                }
              })
            })
            |> ignore
            let after = fn() {
              if rest() == "" && icon == "done" {
                @sf.t("web-main.status.done")
              } else {
                rest()
              }
            }
            line.show(fn() { after() != "" }, fn(r) {
              // (taking what is left along the line, wrapping in it, as its words did in the row)
              r.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
              @sf.words_node(r, after, said) |> ignore
            })
          })
          |> ignore
      }
    })
  })
}

///|
/// Under the viewer's message its agents have yet to take (mine_message's): a small spinner and 等待智能体接收.
fn agent_waiting_node(parent : @view.View) -> @view.View {
  parent.box(fn(w) {
    @sf.style_node(w, fn() { msg_waiting })
    @sf.spinner_node(w, size=waiting_spin) |> ignore
    @sf.words_node(w, fn() { @sf.t("web-main.chat.waitingAgent") }, fn() { msg_time }) |> ignore
  })
}

///|
/// Under what is sent from here while it goes (outbox_row's): `words` (正在发送, or what it waits on) after a small
/// ring, how far its files have gone up filling it once that is said (`progress`); its room kept from the first, seen
/// once it has been on its way sending_shows_ms from when it was sent (`since`, a moment of the frames' clock: what
/// the row is made of, so a row made again later, scrolled back to, shows it at once; that moment declared, View::
/// at_moment, said again as `since` changes), not while its words fly here (`flying`: the list's).
// the chat's page as nodes: held by its tests, not used by the app yet
#warnings("-unused_value")
fn sending_line_node(
  parent : @view.View,
  words : () -> String,
  progress : () -> Double?,
  since : () -> Double,
  flying : () -> Bool,
) -> @view.View {
  parent.box(fn(w) {
    @sf.style_node(w, fn() { msg_waiting })
    // (seen from the moment said: at once where it has come, else as it comes)
    let shows = @signals.signal(false)
    let due : Ref[() -> Unit] = Ref(fn() {  })
    w.reacts(since, fn(at) {
      (due.val)()
      due.val = fn() {  }
      let seen = at + sending_shows_ms
      if w.cause_at() >= seen {
        shows.set(true)
      } else {
        shows.set(false)
        due.val = w.at_moment(seen, fn() { shows.set(true) })
      }
    })
    w.alpha(By(fn() { if shows.get() && !flying() { 1.0 } else { 0.0 } })) |> ignore
    @sf.progress_spinner_node(w, progress, size=waiting_spin) |> ignore
    @sf.words_node(w, words, fn() { msg_time }) |> ignore
  })
}

///|
/// Under the viewer's message that waits for a runtime its station lacks (blocked_line's), in place of its waiting:
/// how that stands (`b`, as the core says it now), in red while nothing is under way, then installing it, at 60% while
/// that is done (the core's doing); where it says how, the whole line installs it, the word underlined under the
/// hand. Its note, or why it failed, in its tip (`tips`), where the line does not say it whole.
fn blocked_line_node(
  parent : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  station : () -> String,
  b : () -> Install,
) -> @view.View {
  let stuck = fn() { b().state == "missing" || b().state == "failed" }
  let busy = fn() { install_busy(src, station(), b()) }
  let can = fn() { b().action != "" && !busy() }
  let words = fn() { if stuck() { blocked_words_stuck } else { blocked_words } }
  parent.box(fn(line) {
    @sf.style_node(line, fn() { blocked_row })
    // (blocked_row_busy's 60%)
    line.alpha(By(fn() { if busy() { 0.6 } else { 1.0 } })) |> ignore
    @sf.presses_node(line, fn() { if can() { install_runtime(src, station(), b()) } }, on=can)
    line.says(By(fn() {
      let i = b()
      if i.action != "" {
        Some(@view.said(Button, label=i.title + " · " + i.action))
      } else {
        Some(@view.said(Text, label=i.title))
      }
    }))
    |> ignore
    line.pick(fn() { if b().state == "installing" { 1 } else if stuck() { 2 } else { 0 } }, fn(k, which) {
      match which {
        1 => @sf.spinner_node(k, size=waiting_spin) |> ignore
        2 =>
          k.box(fn(m) {
            @sf.style_node(m, fn() { failed_mark }, in_row=true)
            @sf.mark_words_node(m, fn() { "!" }, fn() { failed_bang }) |> ignore
          })
          |> ignore
        _ => ()
      }
    })
    let title = fn() {
      let i = b()
      match i.percent {
        Some(p) if i.state == "installing" => i.title + " " + p.to_int().to_string() + "%"
        _ => i.title
      }
    }
    @sf.words_node(line, title, words) |> ignore
    let cut = fn(r : @view.View) { r.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore }
    // (its note, where it says no action)
    line.show(fn() { b().note != "" && b().action == "" }, fn(r) {
      @sf.words_node(r, fn() { "·" }, fn() { blocked_dot }) |> ignore
    })
    line.show(fn() { b().note != "" && b().action == "" }, fn(r) {
      cut(r)
      @sf.words_node(r, fn() { b().note }, words) |> ignore
    })
    // (what it does, in the text's ink, underlined under the hand)
    line.show(fn() { b().action != "" }, fn(r) {
      @sf.words_node(r, fn() { "·" }, fn() { blocked_dot }) |> ignore
    })
    line.show(fn() { b().action != "" }, fn(r) {
      r.box(fn(a) {
        a
        .words_runs(By(fn() { [@ui.span(b().action, underline=can() && @sf.lit_node(line))] }))
        .words_look(By(fn() { @ui.style_words(blocked_act) }))
        .ink(By(fn() { @ui.style_ink(blocked_act) }))
        |> ignore
      })
      |> ignore
    })
    // (why it failed; its note said only here where it shows its action instead: the note it shows whole, wrapping,
    // never repeated, as the old tip's `repeats` said nothing of words shown whole)
    @sf.tip_node(tips, line, fn() {
      let i = b()
      if i.detail != "" {
        i.detail
      } else if i.action != "" {
        i.note
      } else {
        ""
      }
    })
    |> ignore
  })
}
