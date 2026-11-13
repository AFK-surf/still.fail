// What was sent from here and is not in the chat yet, as nodes of the window's tree (chat_rows.mbt's outbox_row,
// outbox_unsent, unsent_button; their styles the same): the viewer's message as it went (what it quotes, its files,
// its words in their bubble), and under it 正在发送 (or what it waits on) a while after it was sent, its time once the
// station has it, or, not sent, 未发送 with 重试 (or 编辑) and 删除, each turning while the core does it and marked red
// a moment where that failed (the core's doing). Each read through what it is given, as that changes. Not here yet:
// its files still going up as cards (the library's file_card_node has no upload yet), its words flying in from the
// composer (the list's flight).

///|
/// What is under what was sent from here (outbox_row's order): what did not go, nothing (followed), its time (the
/// station has it), 正在发送.
#derive(Eq)
priv enum OutboxUnder {
  OutUnsent
  OutNothing
  OutTime
  OutSending
}

///|
/// What is under `o` now.
fn outbox_under(o : Outgoing) -> OutboxUnder {
  if o.state == "failed" {
    OutUnsent
  } else if o.followed {
    OutNothing
  } else if o.state == "sent" {
    OutTime
  } else {
    OutSending
  }
}

///|
/// What the viewer sent, not yet the chat's (`o`), as a message of theirs: its words, no time and no place in the chat
/// yet (what its bubble draws, what a quote of it says: the viewer's, of no message).
fn outgoing_said(o : Outgoing) -> Message {
  { ..@sfbase.message_of({ "mine": true }), text: o.text, words: o.words }
}

///|
/// What was sent from here (outbox_row's, as nodes) in its row's room (message_row_frame_node: `key`, its list's
/// Entry::id `o:<id>`; `side`, `top`; `over`), as `o` says it as it changes: at the column's end, its files, its words
/// in their bubble; under them what outbox_under says, one in the other's place: 正在发送 seen once it has been on its
/// way sending_shows_ms from `since` (when it was sent, a moment of the frames' clock: the caller's, sending_line_node)
/// and not while its words fly here (`flying`: the list's); its time; what did not go (outbox_unsent_node).
// the chat's page as nodes: held by its tests, not used by the app yet
#warnings("-unused_value")
fn outbox_said_node(
  v : @view.View,
  src : Source,
  here : MessageNodeHere,
  key : String,
  side : () -> Double,
  top : () -> Double,
  o : () -> Outgoing,
  since : () -> Double,
  flying? : () -> Bool = fn() { false },
  over? : (@view.View, String) -> Unit = fn(_, _) {  },
) -> MessageRowNode {
  // (its words as a message of the viewer's for the bubble: what person_words_node reads of one)
  let said = fn() -> Message { outgoing_said(o()) }
  let place : MessageFilesAt = {
    station: fn() { here.station },
    session: fn() { here.session },
    view: here.view,
  }
  message_row_frame_node(v, key, side, top, over~, fn(r) {
    r.box(fn(col) {
      @sf.style_node(col, fn() { mine_column })
      col.box(fn(w) {
        @sf.style_node(w, fn() { outbox_words })
        // (what it quotes ahead of its files and words, as outbox_row's)
        message_quotes_node(w, src, here, fn() { o().quotes }, fn() { o().attachments }, true, key)
        message_files_node(
          w,
          src,
          here.tips,
          place,
          fn() {
            let now = o()
            beside_quotes(now.quotes, now.attachments)
          },
          fn() { true },
          fn() { None },
          key + "/f",
        )
        w.show(fn() { o().text != "" }, fn(b) { mine_bubble_node(b, here, said, fn() { [] }, fn() { None }) })
      })
      |> ignore
      // (nothing under it at all while it is followed: no box of nothing in its column, its gap with it)
      col.show(fn() { outbox_under(o()) != OutNothing }, fn(n) {
        n.pick(fn() { outbox_under(o()) }, fn(u, under) {
          match under {
            OutUnsent => outbox_unsent_node(u, src, here, o)
            OutTime => message_time_node(u, here.tips, fn() { o().time })
            OutSending =>
              sending_line_node(
                u,
                fn() {
                  let now = o()
                  if now.waits != "" {
                    now.waits
                  } else {
                    @sf.t("web-main.chat.sending")
                  }
                },
                fn() { o().progress },
                since,
                flying,
              )
              |> ignore
            OutNothing => ()
          }
        })
      })
    })
    |> ignore
  })
}

///|
/// Under what did not go (outbox_unsent's, as nodes) in `v`: 未发送 (refused as it is: why), why in its tip; then 重试,
/// or, refused as it is, 编辑 (its words back in the composer, the entry dropped); then 删除. Each turning while the
/// core does it, red a moment where that failed (the core's doing, as it says it now), none pressed while one is done,
/// 重试 and 编辑 not while the chat's station is not reached.
fn outbox_unsent_node(v : @view.View, src : Source, here : MessageNodeHere, o : () -> Outgoing) -> Unit {
  let on = fn() { [("station", here.station), ("id", o().id)] }
  let retrying = fn() { core_doing(src, ["chat.retry"], on()) }
  let dropping = fn() { core_doing(src, ["chat.discard"], on()) }
  let busy = fn() { retrying() || dropping() }
  let locked = fn() { (here.view)().offline }
  let why = fn() {
    let now = o()
    if now.error != "" {
      @sf.t("web-main.draft.notSent", args=[("error", now.error)])
    } else {
      @sf.t("web-main.chat.notSent")
    }
  }
  v.box(fn(row) {
    @sf.style_node(row, fn() { unsent_row })
    row.box(fn(note) {
      @sf.style_node(note, fn() { unsent_note })
      @sf.icon_node(note, "info", unsent_icon, By(fn() { @sf.theme().p.red })) |> ignore
      @sf.words_node(
        note,
        fn() {
          let now = o()
          if now.refused && now.error != "" {
            @sf.t("web-main.draft.notSent", args=[("error", now.error)])
          } else {
            @sf.t("web-main.chat.unsent")
          }
        },
        fn() { unsent_words },
      )
      |> ignore
      @sf.tip_node(here.tips, note, why) |> ignore
    })
    |> ignore
    row.pick(fn() { o().refused }, fn(p, refused) {
      if refused {
        // refused as it is (a file this station does not have): its words back in the composer, to be sent anew
        unsent_button_node(
          p,
          here.tips,
          "edit",
          @sf.t("common.edit"),
          fn() { !locked() && !busy() },
          fn() { false },
          fn() { None },
          fn() {
            let now = @signals.untracked(o)
            let w = writing(src, here.station + ":" + here.session)
            writing_text(src, w, now.text)
            outbox_node_call(src, here, "chat.discard", now.id)
          },
        )
      } else {
        unsent_button_node(
          p,
          here.tips,
          "retry",
          @sf.t("common.retry"),
          fn() { !locked() && !busy() },
          retrying,
          fn() { core_failed(src, ["chat.retry"], on()) },
          fn() { outbox_node_call(src, here, "chat.retry", @signals.untracked(o).id) },
        )
      }
    })
    unsent_button_node(
      row,
      here.tips,
      "trash",
      @sf.t("common.delete"),
      fn() { !busy() },
      dropping,
      fn() { core_failed(src, ["chat.discard"], on()) },
      fn() { outbox_node_call(src, here, "chat.discard", @signals.untracked(o).id) },
    )
  })
  |> ignore
}

///|
/// What is asked of the core of an entry of the outbox (outbox_call's): by the chat's thread, else its session.
fn outbox_node_call(src : Source, here : MessageNodeHere, call : String, id : String) -> Unit {
  let p : Map[String, Json] = { "station": Json::string(here.station), "id": Json::string(id) }
  match (here.view)().thread {
    Some(th) => p["thread"] = Json::number(th)
    None => p["session"] = Json::string(here.session)
  }
  // (the verb alone: act says it as 无法{what}：{error})
  let what = if call == "chat.retry" {
    @sf.t("android-chat.chat.retry.verb")
  } else {
    @sf.t("android-chat.chat.delete.verb")
  }
  @ui.haptic(Confirm)
  act(src, what, "", call, Json::object(p))
}

///|
/// One of the buttons under what did not go (unsent_button's, as nodes) in `v`: its icon (a spinner while `busy`; a red
/// mark while `failed` says why, why in its tip) and `label`, the hover ground and the text's ink under the pointer; at
/// 55% while it may not be pressed (`enabled`); `press` done as it is pressed while it may be. Read out a button.
fn unsent_button_node(
  v : @view.View,
  tips : @sf.TipLayer,
  icon : String,
  label : String,
  enabled : () -> Bool,
  busy : () -> Bool,
  failed : () -> String?,
  press : () -> Unit,
) -> Unit {
  v.box(fn(b) {
    let hot = fn() { enabled() && @sf.hovered_node(b) }
    @sf.style_node(b, fn() { if hot() { unsent_button_hot } else { unsent_button_box } })
    // (unsent_button_off's 55%: a style's opacity is a node's alpha)
    b.alpha(By(fn() { if enabled() { 1.0 } else { unsent_off_alpha } })) |> ignore
    b.says(By(fn() { Some(@view.said(Button, label~)) })) |> ignore
    @sf.presses_node(b, fn() { if @signals.untracked(enabled) { press() } }, on=enabled)
    b.pick(
      fn() {
        if busy() {
          1
        } else if failed() is Some(_) {
          2
        } else {
          0
        }
      },
      fn(k, which) {
        match which {
          1 => @sf.spinner_node(k, size=waiting_spin) |> ignore
          2 => @sf.icon_node(k, "info", unsent_icon, By(fn() { @sf.theme().p.red })) |> ignore
          _ =>
            @sf.icon_node(k, icon, unsent_icon, By(fn() {
              let p = @sf.theme().p
              if hot() {
                p.text
              } else {
                p.muted
              }
            }))
            |> ignore
        }
      },
    )
    @sf.words_node(b, fn() { label }, fn() { if hot() { unsent_label_hot } else { unsent_label } }) |> ignore
    @sf.tip_node(tips, b, fn() { failed().unwrap_or("") }) |> ignore
  })
  |> ignore
}

///|
/// A button under what did not go while it may not be pressed: at 55% (unsent_button_off's opacity).
let unsent_off_alpha : Double = 0.55
