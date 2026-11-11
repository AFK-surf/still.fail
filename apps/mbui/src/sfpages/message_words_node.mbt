// What a person wrote, as nodes of the window's tree, made once (message.mbt's person_words, mine_bubble, mine_message,
// and others_message's body for a person's words; their styles the same): the words in pieces as the core gave them
// (person_runs: a chat's reference its chip, a web address its link), each link pressed where it leads and held for its
// menu; the viewer's own in their bubble at the column's end, its time under it; someone else's under their picture,
// name and time. Each read through what it is given, as that changes.
// Not here yet: a link's card while it is pointed at (link_peek: peeks.mbt, with Markdown's), what it quotes and its
// files, the viewer's words flying in from the composer (flight.mbt) and its time faded in as they land.

///|
/// What a person wrote (person_words') in `v`, as `m` says it as it changes: in the face for what people wrote (the
/// theme's `words`), in pieces as the core gave them, links in blue; a link tapped opens where it leads, held (or right
/// clicked) its menu; the words `found` says in bold. The words' node.
fn person_words_node(v : @view.View, m : () -> Message, found? : () -> Array[String] = fn() { [] }) -> @view.View {
  let runs = fn() {
    let now = m()
    @sf.found_weight(@sfbase.person_runs(now.text, now.words, @sf.theme().p.accent, chat_title=chat_title_of(now)), found())
  }
  v.box(fn(w) {
    w
    .words_runs(By(runs))
    .words_look(By(fn() { @ui.style_words(@sf.theme().t.words) }))
    .runs_look(By(fn() { { ..@view.runs_plain, link: @sf.theme().p.blue, words: true } }))
    .ink(By(fn() { @ui.style_ink(@sf.theme().t.words) }))
    |> ignore
    @ui.runs_links(w, runs, fn(h) { open_link(h) }, hold=fn(href, at) { message_link_held(href, at) }) |> ignore
  })
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
/// the neutral ground, as wide as the composer sets its words at most (mine_most_of the pane's width, as it changes).
fn mine_bubble_node(v : @view.View, here : MessageNodeHere, m : () -> Message, found : () -> Array[String]) -> Unit {
  v.box(fn(b) {
    @sf.style_node(b, fn() { bubble.then(@ui.style(max_w=Fixed(mine_most_of((here.width)())))) })
    person_words_node(b, m, found~) |> ignore
  })
  |> ignore
}

///|
/// The viewer's own message (mine_message's, its words alone) in its row's room (message_row_frame_node: `key`, its
/// list's Entry::id; `side`, `top`; `over`), as `m` says it as it changes: at the column's end, its words in their
/// bubble; under it, unless their next message soon after says it under that one (`followed`), the runtime it waits
/// for where its station lacks it (blocked_line_node), else that its agents have yet to take it (agent_waiting_node),
/// else its time: one in the other's place as that changes.
fn mine_said_node(
  v : @view.View,
  src : Source,
  here : MessageNodeHere,
  key : String,
  side : () -> Double,
  top : () -> Double,
  m : () -> Message,
  found? : () -> Array[String] = fn() { [] },
  over? : (@view.View, String) -> Unit = fn(_, _) {  },
) -> MessageRowNode {
  message_row_frame_node(v, key, side, top, over~, fn(r) {
    r.box(fn(col) {
      @sf.style_node(col, fn() { mine_column })
      col.show(fn() { m().text != "" }, fn(b) { mine_bubble_node(b, here, m, found) })
      col.pick(fn() { mine_under(m()) }, fn(u, under) {
        match under {
          MineBlocked =>
            blocked_line_node(u, src, here.tips, fn() { here.station }, fn() {
              // (as it is while it is: what took its place is made once it is not)
              m().blocked.unwrap_or(mine_installed)
            })
            |> ignore
          MineWaiting => agent_waiting_node(u) |> ignore
          MineTime => message_time_node(u, here.tips, fn() { m().time })
          MineNothing => ()
        }
      })
    })
    |> ignore
  })
}

///|
/// What is under the viewer's message (mine_message's): nothing (followed), the runtime it waits for, that its agents
/// have yet to take it, its time.
priv enum MineUnder {
  MineNothing
  MineBlocked
  MineWaiting
  MineTime
} derive(Eq)

///|
/// What is under the viewer's message `m` now (mine_message's order).
fn mine_under(m : Message) -> MineUnder {
  if m.followed {
    return MineNothing
  }
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
fn person_said_node(
  v : @view.View,
  src : Source,
  here : MessageNodeHere,
  key : String,
  side : () -> Double,
  top : () -> Double,
  m : () -> Message,
  found? : () -> Array[String] = fn() { [] },
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
      fn(b) { b.show(fn() { m().text != "" }, fn(w) { person_words_node(w, m, found~) |> ignore }) },
      share~,
    )
    menu_on.val = on
  })
  { ..row, menu_on: menu_on.val }
}

///|
/// What a message in a chat's list offers of itself (others_message's `share` as message_row gives it): its key
/// (`m:<ts>`), its link, its words, its turn's picture shared from the chat's thread.
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
