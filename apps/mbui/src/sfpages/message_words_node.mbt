// What a person wrote, as nodes of the window's tree, made once (message.mbt's person_words, mine_bubble, mine_message,
// and others_message's body for a person's words; their styles the same): the words in pieces as the core gave them
// (person_runs: a chat's reference its chip, a web address its link), each link pressed where it leads and held for its
// menu; the viewer's own in their bubble at the column's end, its time under it; someone else's under their picture,
// name and time; what each quotes ahead of its words (message_quotes_node). Each read through what it is given, as
// that changes.
// Each link's card while a mouse rests on it (message_link_card: a web link's, a chat's); its files (message_files_node:
// the viewer's between what it quotes and its words, someone else's under their words). Not here yet: the viewer's
// words flying in from the composer (flight.mbt) and its time faded in as they land.

///|
/// What a person wrote (person_words') in `v`, as `m` says it as it changes: in the face for what people wrote (the
/// theme's `words`), in pieces as the core gave them, links in blue; a link tapped opens where it leads, held (or right
/// clicked) its menu; the words `found` says in bold, marked where `found_at` says (found_marks: the one the find is
/// at of them, -1 none; None not marked); each link's card while a mouse rests on it where `cards` says
/// them (drawn in its layer: a chat's link_peeks, message_link_card). The words' node.
fn person_words_node(
  v : @view.View,
  m : () -> Message,
  found? : () -> Array[String] = fn() { [] },
  found_at? : () -> Int? = fn() { None },
  cards? : (@sf.TipLayer, (@sf.LinkOf) -> @sf.LinkCard?),
) -> @view.View {
  let runs = fn() {
    let now = m()
    @sf.found_weight(@sfbase.person_runs(now.text, now.words, @sf.theme().p.accent, chat_title=chat_title_of(now)), found())
  }
  // (what a find marks of them: found_marks)
  let marks = fn() {
    match found_at() {
      Some(at) => @sf.found_marks(runs(), found(), at)
      None => []
    }
  }
  let shown : @signals.Signal[Array[(String, String, Int)]] = @signals.signal([])
  let links : Ref[@ui.RunsLinks?] = Ref(None)
  let words = v.box(fn(w) {
    w
    .words_runs(By(runs))
    .runs_marks(By(marks))
    .words_look(By(fn() { @ui.style_words(@sf.theme().t.words) }))
    .runs_look(By(fn() { { ..@view.runs_plain, link: @sf.theme().p.blue, words: true } }))
    .ink(By(fn() { @ui.style_ink(@sf.theme().t.words) }))
    |> ignore
    links.val = Some(
      @ui.runs_links(w, runs, fn(h) { open_link(h) }, hold=fn(href, at) { message_link_held(href, at) }, shown?=cards.map(fn(
        _,
      ) {
        fn(now) { shown.set(now) }
      })),
    )
  })
  match (cards, links.val) {
    (Some((layer, card_of)), Some(l)) => @sf.link_cards_node(v, layer, words, l, fn() { shown.get() }, card_of) |> ignore
    _ => ()
  }
  words
}

///|
/// A link of what a person wrote held (or right clicked: link_held's), its menu by the piece of line under the hand
/// (`at`, in the window): open it (a web address), copy it.
fn message_link_held(href : String, at : (Double, Double, Double, Double)) -> Unit {
  @sf.menu_held_node()
  @sf.link_menu(
    href,
    from=At(at.0, at.1, at.2, at.3),
    fn() { @ui.open_url(href) |> ignore },
    fn() { @sfbase.copy_out(href, said=@sf.t("common.link.copied")) },
  )
}

///|
/// How wide what the viewer sent may be at the column's end in a pane `pane` wide (mine_most's): as wide as the composer
/// sets its words, the bubble's sides round them.
fn mine_most_of(pane : Double) -> Double {
  composer_words_width(pane) + 2.0 * bubble_side
}

///|
/// The viewer's words in their bubble (mine_bubble's, as they rest: none flying in) in `v`: 8 by 14 in, 18 round, on
/// the neutral ground, as wide as the composer sets its words at most (mine_most_of the pane's width, as it changes);
/// its links' cards as `cards` says (person_words_node's: none for what is not in the chat yet, as the old one's).
fn mine_bubble_node(
  v : @view.View,
  here : MessageNodeHere,
  m : () -> Message,
  found : () -> Array[String],
  found_at : () -> Int?,
  cards? : (@sf.TipLayer, (@sf.LinkOf) -> @sf.LinkCard?),
) -> Unit {
  v.box(fn(b) {
    @sf.style_node(b, fn() { bubble.then(@ui.style(max_w=Fixed(mine_most_of((here.width)())))) })
    person_words_node(b, m, found~, found_at~, cards?) |> ignore
  })
  |> ignore
}

///|
/// The viewer's own message (mine_message's, its words alone) in its row's room (message_row_frame_node: `key`, its
/// list's Entry::id; `side`, `top`; `over`), as `m` says it as it changes: at the column's end, its words in their
/// bubble; under it, unless their next message soon after says it under that one (`followed`), the runtime it waits
/// for where its station lacks it (blocked_line_node), else that its agents have yet to take it (agent_waiting_node),
/// else its time: one in the other's place as that changes. Where it offers itself (`share`), its bubble right clicked
/// offers that (message_menu_node: the old bubble's pickable's; no ⋯, as the old row had none).
///
/// What was sent from here and is not the chat's yet is the same row (`out`: Some while it is on its way, `m` then
/// outgoing_said's), one row to a person as the core's message takes it over: its words' node made once and kept, so
/// what is picked of them, its handles and its menu stay. What differs is bound to which it is now: under it 正在发送
/// seen once it has been on its way sending_shows_ms from `since` (a moment of the frames' clock: the caller's) and not
/// while its words fly here (`flying`), or what did not go (outbox_unsent_node), or its time once the station has it;
/// on its way, its files said by no one yet, its links no cards, nothing found in it and no right click's offer.
// the chat's page as nodes: held by its tests, not used by the app yet
#warnings("-unused_value")
fn mine_said_node(
  v : @view.View,
  src : Source,
  here : MessageNodeHere,
  key : String,
  side : () -> Double,
  top : () -> Double,
  m : () -> Message,
  found? : () -> Array[String] = fn() { [] },
  found_at? : () -> Int? = fn() { None },
  share? : MessageShare? = None,
  over? : (@view.View, String) -> Unit = fn(_, _) {  },
  out? : () -> Outgoing? = fn() { None },
  since? : () -> Double = fn() { 0.0 },
  flying? : () -> Bool = fn() { false },
) -> MessageRowNode {
  let said = fn() { out() is None }
  message_row_frame_node(v, key, side, top, over~, fn(r) {
    r.box(fn(col) {
      @sf.style_node(col, fn() { mine_column })
      // (what it quotes ahead of its files and words, in the order the composer held them: mine_message's; its place
      // the row's as it was made, what was sent from here its key's)
      let at = if @signals.untracked(said) { message_place(@signals.untracked(m)) } else { key }
      message_quotes_node(col, src, here, fn() { m().quotes }, fn() { m().attachments }, true, at)
      message_files_node(
        col,
        src,
        here.tips,
        message_files_at(here),
        fn() {
          let now = m()
          beside_quotes(now.quotes, now.attachments)
        },
        fn() { true },
        fn() { if said() { Some((@sf.t("web-main.chat.you"), "person", m().ts)) } else { None } },
        at + "/f",
      )
      col.show(fn() { m().text != "" }, fn(b) {
        // (what is read in it starts here, its bubble's words: View::read_from)
        b.read_from() |> ignore
        let cards = message_link_card(src, here.station, "", m)
        mine_bubble_node(
          b,
          here,
          m,
          fn() { if said() { found() } else { [] } },
          fn() { if said() { found_at() } else { None } },
          cards=(here.tips, fn(l) { if said() { cards(l) } else { None } }),
        )
        // (offered once it is the chat's, by the message it is then)
        match share {
          Some(s) =>
            b.on_menu(fn(e) {
              if said() {
                @sfbase.share_offer(e.wx, e.wy, s.go, @signals.untracked(s.link), @signals.untracked(s.words), "m:" + @signals.untracked(m).ts)
              }
            })
            |> ignore
          None => ()
        }
      })
      let under = fn() {
        match out() {
          Some(o) => outbox_mine_under(o)
          None => mine_under(m())
        }
      }
      // (nothing under it at all while it is followed, but what did not go: no box of nothing in its column, its gap
      // with it. There and gone at once, apart from the pick of what is under it: it goes in the frame the key after it
      // comes, which sets out from as tall as that gives back (the list's), where one of its states in another's place
      // leaves: what it showed fading where it is, what it shows now seen once its place holds it whole, its place
      // making its way between, no words of either cut by it (msg_part_leave_ms))
      let lone = fn() {
        match out() {
          Some(o) => o.state == "failed" || !o.followed
          None => !m().followed
        }
      }
      col.show(at_once=true, lone, fn(n) {
        n.pick(under, leave=msg_part_leave_ms, fn(u, now) {
          match now {
            MineBlocked =>
              blocked_line_node(u, src, here.tips, fn() { here.station }, fn() {
                // (as it is while it is: what took its place is made once it is not)
                m().blocked.unwrap_or(mine_installed)
              })
              |> ignore
            MineWaiting => agent_waiting_node(u) |> ignore
            MineTime =>
              message_time_node(u, here.tips, fn() {
                match out() {
                  Some(o) => o.time
                  None => m().time
                }
              })
            MineSending =>
              sending_line_node(
                u,
                fn() {
                  match out() {
                    Some(o) if o.waits != "" => o.waits
                    _ => @sf.t("web-main.chat.sending")
                  }
                },
                fn() { out().bind(fn(o) { o.progress }) },
                since,
                flying,
              )
              |> ignore
            MineUnsent => outbox_unsent_node(u, src, here, fn() { out().unwrap_or(chat_body_no_out) })
          }
        })
      })
    })
    |> ignore
  })
}

///|
/// What is under the viewer's message while anything is (mine_message's; nothing while it is followed, which its row
/// says apart: mine_said_node's `lone`): the runtime it waits for, that its agents have yet to take it, its time; on
/// its way (outbox_row's), 正在发送, or what did not go.
#derive(Eq)
priv enum MineUnder {
  MineBlocked
  MineWaiting
  MineTime
  MineSending
  MineUnsent
}

///|
/// What is under the viewer's message `m` now, where anything is (mine_message's order).
fn mine_under(m : Message) -> MineUnder {
  match m.blocked {
    Some(b) if b.state != "installed" => MineBlocked
    _ => if m.waiting { MineWaiting } else { MineTime }
  }
}

///|
/// A runtime as it is once installed: what blocked_line_node reads where its message's has just gone, nothing drawn
/// by it then.
// kept across runs: a value (no field of it changes)
let mine_installed : Install = {
  runtime: "",
  state: "installed",
  title: "",
  note: "",
  action: "",
  percent: None,
  detail: "",
}

///|
/// What someone else wrote as a person (others_message's with person_words: no Markdown) in its row's room
/// (message_row_frame_node: `key`, its list's Entry::id; `side`, `top`; `over`), as `m` says it as it changes: their
/// picture out in the margin (inline: over the head's start), their name (one of the chat's agents' opens its history,
/// another chat's that chat), its time, their words under them; where it offers itself (`share`: in a chat's list), its
/// ⋯ and a right click's offer (message_others_node's), the row saying whether its ⋯'s menu is open.
// the chat's page as nodes: held by its tests, not used by the app yet
#warnings("-unused_value")
fn person_said_node(
  v : @view.View,
  src : Source,
  here : MessageNodeHere,
  key : String,
  side : () -> Double,
  top : () -> Double,
  m : () -> Message,
  found? : () -> Array[String] = fn() { [] },
  found_at? : () -> Int? = fn() { None },
  share? : MessageShare? = None,
  over? : (@view.View, String) -> Unit = fn(_, _) {  },
) -> MessageRowNode {
  let menu_on : Ref[() -> Bool] = Ref(fn() { false })
  let row = message_row_frame_node(v, key, side, top, over~, fn(r) {
    let (_, on) = message_others_node(
      r,
      here,
      fn() { m().time },
      fn(av) {
        person_avatar_node(av, src, here, fn() { m().author }, fn() { m().by.name }, fn() { m().by.picture })
      },
      fn(h) {
        message_name_node(h, src, here, fn() { m().by.name }, fn() { message_agent_of(here, m().by.agent) }, fn() {
          m().by.from
        })
      },
      None,
      fn(b) {
        // (what it quotes ahead of its words, its other files under them, as the old body's)
        let at = message_place(@signals.untracked(m))
        message_quotes_node(b, src, here, fn() { m().quotes }, fn() { m().attachments }, false, at)
        b.show(fn() { m().text != "" }, fn(w) {
          // (what is read in it starts here, its words under its head line: View::read_from)
          w.read_from() |> ignore
          person_words_node(w, m, found~, found_at~, cards=(here.tips, message_link_card(src, here.station, "", m))) |> ignore
        })
        message_files_node(
          b,
          src,
          here.tips,
          message_files_at(here),
          fn() {
            let now = m()
            beside_quotes(now.quotes, now.attachments)
          },
          fn() { false },
          fn() { Some((m().by.name, "person", m().ts)) },
          at + "/f",
        )
      },
      share~,
    )
    menu_on.val = on
  })
  { ..row, menu_on: menu_on.val }
}

///|
/// What a message in a chat's list offers of itself (others_message's `share` as message_row gives it): its key
/// (`m:<ts>`), its link, its words, its turn's picture shared from the chat's thread.
// the chat's page as nodes: held by its tests, not used by the app yet
#warnings("-unused_value")
fn message_share_of(src : Source, here : MessageNodeHere, m : () -> Message) -> MessageShare? {
  match (here.view)().thread {
    Some(thread) =>
      Some({
        key: "m:" + @signals.untracked(m).ts,
        link: fn() { @sfbase.message_link(here.station, here.session, m().seq) },
        words: fn() { m().text },
        go: fn() { open_publish(src, message_node_ref(here), thread, picked=Some(@signals.untracked(m).seq)) },
      })
    None => None
  }
}

///|
/// Where a message's files are (MessageFilesAt) in the chat `here` is: its station, its session, its view as it changes.
fn message_files_at(here : MessageNodeHere) -> MessageFilesAt {
  { station: fn() { here.station }, session: fn() { here.session }, view: here.view }
}
