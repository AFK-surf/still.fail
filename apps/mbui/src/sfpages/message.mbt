// A chat's message on the desktop (ember web/src/Chat.tsx MessageRow, MineMessage, OthersMessage, SystemNotice,
// BlockedLine, AgentAvatar, MessageAvatar, Quotes, PersonWords, MineBubble, ProseWithFiles, SentElsewhere; Chat.css.ts,
// styles/conversation.css.ts, styles/chat.css.ts): the viewer's own on the right in its bubble; still.fail's own a
// pill across the chat; anyone else's with its picture out in the margin before its name and time, what it quotes, its
// words (an agent's as Markdown with the files it places in it) and its files (message_files.mbt). How a notice is
// said, which files a text places and what is the viewer's are the core's (the chat view's `notice`, `placed`, `mine`).

///|
/// Where a message is shown: its chat (its station, its session, its view), and, in a list, how that list goes to a
/// message (by its seq, and the passage of it a quote's card pressed quoted: lit alone there); None out of one (a letter, a decision's). `inline`: no margin for
/// the pictures (a side panel's: Chat.css.ts inlineHeads), each over its head's start. `gutter`: the
/// room beside the words either side that is only the page's margin (`--list-gutter`: a list's sides, narrow or wide,
/// its pictures out in it standing by their heads' line; none out of a list), which the message's own tables scroll
/// out over to the pane's edges. In its chat's list (`list`), how it moves there: its list's turns (what it asks
/// closes in one), its messages out of avatars (by the chat's key), the words sent flying to this row.
pub(all) struct MessageHere {
  station : String
  session : String
  view : ChatView
  go : ((Double, String) -> Unit)?
  inline : Bool
  gutter : Double
  list : ListMotion?
  /// the core as the settings' pages have it, over the chat's workspace (a login's card, a vault request's answer);
  /// None where nothing is answered (a letter's)
  core : Core?
}

///|
/// How a row moves in its chat's list (MessageHere's `list`).
pub(all) struct ListMotion {
  rk : String
  turns : Turns
  emits : Emits
  flight : SendFlight?
}

///|
/// The words to mark in message `ts` where it is shown: a search's that opened the chat at it, else what ⌘F found in
/// the chat (find.mbt); none out of a chat's list.
fn marked_of(here : MessageHere, ts : String) -> Array[String] {
  match here.list {
    Some(l) => {
      let rd = reading_of(l.rk)
      if rd.found_at != "" && rd.found_at == ts {
        rd.found_words
      } else {
        find_words_in(l.rk)
      }
    }
    None => []
  }
}

///|
/// A message's words in a chat's list, picked with the pointer to be quoted (useSelectionQuote: sfbase's picking), its
/// turn shared as a picture from there (`turn`: its seq; the sharing over the window, open_publish); out of a list, as
/// they are.
pub fn picking(
  here : MessageHere,
  c : @ui.Ctx,
  src : Source,
  ts : String,
  turn : Double,
  author : String,
  role : String,
  words : String,
  body : () -> Unit,
  fill? : Bool = true,
) -> Unit {
  match here.list {
    Some(_) => {
      let share = here.view.thread.map(fn(thread) { fn() { open_publish(src, here_ref(here), thread, turn=Some(turn)) } })
      let link = @sfbase.message_link(here.station, here.session, turn)
      // gone to by a quote of it: the passage quoted lit as it flashes (chat_list.mbt passage_lit)
      let lit = passage_lit(c, here, ts)
      @sfbase.pickable(c, ts, author, role, words, fill, @sfbase.mouse_picks(), body, keep=passage_wanted(here, ts), share~, link~, lit~)
    }
    None => body()
  }
}

///|
/// Words sent flying to this row, while they are on their way.
fn flight_here(here : MessageHere) -> SendFlight? {
  match here.list {
    Some(l) => l.flight
    None => None
  }
}

///|
/// The chat a message is shown in, as a page.
fn here_ref(here : MessageHere) -> ChatRef {
  { station: here.station, session: here.session, title: here.view.title, station_name: "" }
}

///|
/// A message as a chat draws it (MessageRow), out of its list (StaticMessage: no options under it).
pub fn message_row(c : @ui.Ctx, src : Source, here : MessageHere, m : Message) -> Unit {
  if m.mine {
    mine_message(c, src, here, m)
    return
  }
  let emits = match here.list {
    Some(l) if emit_goes(l.emits, m.seq) || emit_words_only(l.emits, m.seq) => Some(l)
    _ => None
  }
  // what still.fail itself says (a limit hit, a failure): a notice across the chat, not someone's message
  if m.system {
    system_notice(c, src, here.station, m)
    return
  }
  let agent = if m.by.agent != "" && here.view.agents.iter().any(fn(a) { a.key == m.by.agent }) {
    m.by.agent
  } else {
    ""
  }
  others_message(
    c,
    here.inline,
    "m:" + m.ts,
    m.time,
    emits=emits.map(fn(l) { (l.emits, l.rk, m.seq) }),
    share_link=@sfbase.message_link(here.station, here.session, m.seq),
    share=if here.list is Some(_) {
      here.view.thread.map(fn(thread) { fn() { open_publish(src, here_ref(here), thread, turn=Some(m.seq)) } })
    } else { None },
    fn() { message_avatar(c, src, here, m, agent) },
    fn() { message_name(c, src, here, "m:" + m.ts, m.by.name, agent, m.by.from) },
    None,
    fn() {
      quotes(c, src, here, m.quotes, m.attachments)
      let files = beside_quotes(m.quotes, m.attachments)
      if m.author_kind == "person" {
        if m.text != "" {
          picking(here, c, src, m.ts, m.seq, m.by.name, "person", m.text, fn() {
            person_words(c, m.text, "m:" + m.ts, found=marked_of(here, m.ts), peek=link_peeks(c, src, here, chats=m.chats), chat_title=chat_title_of(m))
          })
        }
        message_files(c, src, here, files, false, by=Some((m.by.name, "person", m.ts)))
      } else {
        picking(here, c, src, m.ts, m.seq, m.by.name, if m.author_kind == "agent" { "agent" } else { "person" }, m.text, fn() {
          prose_with_files(c, src, here, m, files)
        })
      }
      // what it asks, under it (in its chat's list: not a letter's)
      match here.list {
        Some(l) => message_decision(c, src, here, m, Some(l.turns))
        None => ()
      }
    },
  )
}

///|
/// The viewer's own message (MineMessage, MineWords): at the column's end, in the order the composer held them as they
/// were written (what it quotes, its files, its words: composer.mbt composer_extras over its field), so that sending
/// them moves each straight up to its place, none across another (the web has its files under its words); under it,
/// unless their next message soon after says it under that one (`followed`), the runtime it waits for (BlockedLine),
/// that its agents have yet to take it, or its time.
fn mine_message(c : @ui.Ctx, src : Source, here : MessageHere, m : Message) -> Unit {
  c.box(style=mine_column, fn() {
    quotes(c, src, here, m.quotes, m.attachments, mine=true)
    message_files(c, src, here, beside_quotes(m.quotes, m.attachments), true, by=Some((@sf.t("web-main.chat.you"), "person", m.ts)))
    if m.text != "" {
      picking(here, c, src, m.ts, m.seq, @sf.t("web-main.chat.you"), "person", m.text, fn() {
        mine_bubble(c, here, m.text, "m:" + m.ts, found=marked_of(here, m.ts), peek=link_peeks(c, src, here, chats=m.chats), chat_title=chat_title_of(m))
      }, fill=false)
    }
    if !m.followed {
      match m.blocked {
        Some(b) if b.state != "installed" => blocked_line(c, src, here.station, "m:" + m.ts, b)
        _ =>
          if m.waiting {
            c.box(style=msg_waiting, fn() {
              @sf.spinner(c, size=waiting_spin) |> ignore
              c.text(@sf.t("web-main.chat.waitingAgent"), style=msg_time) |> ignore
            })
            |> ignore
          } else {
            // coming in with the words, when they fly here from the composer: seen once they are in over it, not as
            // they pass up over its place (docs/motion.md rule 4)
            let at = c.box(fn() { message_time(c, "m:" + m.ts, m.time) })
            match flight_here(here) {
              Some(f) if f.text != "" => {
                // (from their landing: before it they may still be passing up over its place; none before they set
                // out, their landing not known yet)
                let lands = f.way.ends()
                if f.placed && lands < @double.infinity && c.moment() >= lands {
                  let a = @motion.anim(c, "time-in/" + m.ts, 0.0, global=true)
                  if a.target() != 1.0 {
                    a.animate(1.0, @motion.tween(@sf.enter_ms, ease=Out), start_at=lands)
                  }
                  c.look(at, @ui.look(alpha=a.get()))
                } else {
                  // (built again as they land)
                  if f.placed && lands < @double.infinity {
                    c.shows_until(lands)
                  }
                  c.look(at, @ui.look(alpha=0.0))
                }
              }
              _ => ()
            }
          }
      }
    }
  })
  |> ignore
}

///|
/// Someone else's message (OthersMessage): its picture out in the margin before its words, held under the pane's top
/// as a long one scrolls past; its name, where it went or came from (`route`, when not here) and its time over what
/// it says. `inline` (inlineHeads): its picture over its head's start, the head in past it, where it went on a line
/// of its own under them from the row's start.
pub fn others_message(
  c : @ui.Ctx,
  inline : Bool,
  key : String,
  time : Stamp?,
  emits? : (Emits, String, Double)? = None,
  share? : (() -> Unit)? = None,
  share_link? : String = "",
  avatar : () -> Unit,
  name : () -> Unit,
  route : (() -> Unit)?,
  body : () -> Unit,
) -> Unit {
  // its link and its turn's picture on its head where a mouse is what it is used with (laid out by the native input:
  // the head as it is whichever hand is on it now); a finger has them on the bar of what it holds picked
  let share = if @sf.more_held() { None } else { share }
  let row = if share is Some(_) { c.id("message/" + key) } else { 0 }
  if row != 0 { c.cursor(row, Arrow) }
  c.box(style=if share is Some(_) { msg_row_share } else { msg_row }, id=row, fn() {
    let head = Ref(0)
    let col = c.box(style=if share is Some(_) { msg_main_share } else { msg_main }, fn() {
      head.val = c.box(style=if inline { msg_head_inline } else { msg_head }, fn() {
        name()
        if !inline {
          match route {
            Some(r) => r()
            None => ()
          }
        }
        message_time(c, key, time)
        match share {
          Some(go) => {
            c.spacer()
            @sfbase.share_turn_tool(c, key, row, share_link, go)
          }
          None => ()
        }
      })
      if inline {
        match route {
          Some(r) => c.box(style=msg_route_line, fn() { r() }) |> ignore
          None => ()
        }
      }
      body()
    })
    // coming out of its agent's picture (sfbase's emit.mbt): its head out of the picture, unrolling from its top
    match emits {
      Some((em, _, seq)) => {
        @motion.measure(c, col, "emit-col/" + seq_s(seq))
        emit_out(c, col, head.val, em, seq)
      }
      None => ()
    }
    // (out in the margin, as far from the name as from the margin's edge: msgRow > msgAvatar; inline at the row's
    // start, 3 down; where a message out of a picture lands, hidden while the flying one is over it)
    c.layer(fn() {
      let av = if inline {
        c.box(style=msg_avatar_inline, fn() { avatar() })
      } else {
        let av = c.box(style=msg_avatar_room, fn() { avatar() })
        c.stick(av, avatar_held_at)
        av
      }
      match emits {
        Some((em, rk, seq)) => {
          @motion.measure(c, av, "emit-landing/" + rk + "/" + seq_s(seq))
          if emit_emitting(em, seq) || emit_awaited(em, seq) {
            c.look(av, @ui.look(alpha=0.0))
          }
        }
        None => ()
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// Whose a message is (MessageAvatar): an agent's model's maker, still.fail's mark, or a person's face.
fn message_avatar(c : @ui.Ctx, src : Source, here : MessageHere, m : Message, agent : String) -> Unit {
  match m.author_kind {
    "agent" => agent_avatar(c, src, here, "m:" + m.ts, m.by.maker, m.by.runtime, "", agent)
    "ember" | "stillfail" => agent_avatar(c, src, here, "m:" + m.ts, "", "", "", "")
    _ => person_avatar(c, src, m.author, m.by.name, m.by.picture)
  }
}

///|
/// A person's picture in a chat (msgAvatar: 18 round), their face where they have one.
pub fn person_avatar(c : @ui.Ctx, src : Source, id : String, name : String, picture : String) -> Unit {
  @sf.avatar(c, id, name, if picture != "" { (src.picture)(picture, c.page_stint()) } else { "" }, avatar_side)
}

///|
/// An agent's picture in a chat (AgentAvatar): its model's maker (still.fail's mark without one) on the neutral
/// ground; what it said went elsewhere (`slack`: slack | feishu), that place's mark on its corner. One of the chat's
/// (`agent`, its session's key) has its card while the pointer rests on it (AgentHover).
pub fn agent_avatar(
  c : @ui.Ctx,
  src : Source,
  here : MessageHere,
  key : String,
  maker : String,
  runtime : String,
  slack : String,
  agent : String,
) -> Unit {
  let t = @sf.theme()
  let id = if agent != "" { c.id("msg-avatar/" + key) } else { 0 }
  // (in a page's bones, one disc)
  let b = c.box(style=agent_avatar_ground, id~, fn() {
    if maker != "" || runtime != "" {
      @sf.maker_mark(c, maker, if runtime != "" { runtime } else { "claude" }, agent_mark_side) |> ignore
    } else {
      @sf.drawable(c, if t.dark { "stillfail_mark_dark" } else { "stillfail_mark" }, agent_mark_side) |> ignore
    }
    if slack != "" {
      place_corner(c, slack)
    }
  })
  c.bone_whole(b)
  if agent != "" {
    agent_hover(c, src, here, "agent-hover/" + key, id, agent)
  }
}

///|
/// Agent `agent`'s card (AgentHover) over trigger `id` while the pointer rests on it, to a finger as it holds it
/// (hover): over its picture and over its name beside its messages alike.
fn agent_hover(c : @ui.Ctx, src : Source, here : MessageHere, key : String, id : Int, agent : String) -> Unit {
  let r = here_ref(here)
  hover(c, key, id, tile=true, fn() {
    match agent_json((src.topic)("chat", chat_params(r)).value, agent) {
      Some(j) => agent_card(c, src, r, j)
      None => ()
    }
  })
  |> ignore
}

///|
/// A place's mark on the corner of a picture (msgAvatarSlack): 14 round, 6 past its right and foot, on the list's
/// ground with a line round it.
fn place_corner(c : @ui.Ctx, surface : String) -> Unit {
  c.layer(fn() {
    c.box(style=place_corner_room, fn() {
      c.box(style=place_corner_mark, fn() {
        if surface == "feishu" {
          @sf.feishu_mark(c, place_corner_side) |> ignore
        } else {
          @sf.slack_mark(c, place_corner_side) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A name over its message (msgHead msgName): one of the chat's agents' (`agent`) opens its history beside the chat
/// (chatPage.agent), with its card over it as over its picture (agent_hover); another chat's agent's (`from`, its
/// link) that chat; in the accent under the pointer then.
fn message_name(
  c : @ui.Ctx,
  src : Source,
  here : MessageHere,
  key : String,
  name : String,
  agent : String,
  from : String,
) -> Unit {
  let goes = agent != "" || from != ""
  let id = if goes { c.id("msg-name/" + key) } else { 0 }
  if goes {
    if c.clicked(id) {
      if agent != "" {
        open_detail(src, here_ref(here), agent)
      } else {
        let to = from
        c.tell("msg-name/" + key, fn() { open_link(to) })
      }
    }
  }
  c.box(style=msg_name_room, id~, fn() {
    // (the accent's words already: pointed at, underlined, docs/ui-panels.md 悬停)
    c.rich([@ui.span(name, underline=goes && c.hovered(id))], style=msg_name) |> ignore
  })
  |> ignore
  if agent != "" {
    agent_hover(c, src, here, "agent-name-hover/" + key, id, agent)
  }
}

///|
/// When it was said (Time): how long ago, or when (pressed, every time in the app says the other), the other way on
/// hover.
fn message_time(c : @ui.Ctx, key : String, time : Stamp?) -> Unit {
  match time {
    None => ()
    Some(s) => {
      let id = c.id("msg-time/" + key)
      if c.clicked(id) {
        absolute_times.val = !absolute_times.val
      }
      @sf.tip(c, "msg-time/" + key, id, if absolute_times.val { s.ago } else { s.full })
      c.box(id~, keep=true, fn() { c.text(if absolute_times.val { s.full } else { s.ago }, style=msg_time) |> ignore }) |> ignore
    }
  }
}

///|
/// What a person wrote (PersonWords): plain, as they wrote it (set as it was typed: the theme's `words`), references to
/// chats as their chips (one linked bare reading as `chat_title` says) and web addresses as links, a link's card over
/// it where `peek` (link_peeks).
pub fn person_words(
  c : @ui.Ctx,
  words : String,
  key : String,
  found? : Array[String] = [],
  peek? : ((String, String, Int) -> Unit)? = None,
  chat_title? : (String) -> String? = fn(_) { None },
  marks? : Array[(Int, Int)] = [],
) -> Unit {
  let p = @sf.theme().p
  c.rich(
    @sf.found_weight(message_runs(words, p.accent, chat_title~, marks~), found),
    key="msg-words/" + key,
    style=@sf.theme().t.words,
    link_color=p.blue,
    on_link=fn(h) { open_link(h) },
    on_link_hold=Some(fn(href, _) { link_held(c, href) }),
    on_link_shown=peek,
    words=true,
  )
  |> ignore
}

///|
/// What a message's links show while they are pointed at, the chat's station reading them (peeks.mbt): a web link's
/// card, a chat's; and where `agent` (the agent that wrote it) says whose working directory its paths are read in, a
/// file's.
fn link_peeks(
  c : @ui.Ctx,
  src : Source,
  here : MessageHere,
  agent? : String = "",
  chats? : Array[LinkedChat] = [],
) -> ((String, String, Int) -> Unit)? {
  Some(fn(href, words, id) { link_peek(c, src, here.station, href, words, id, agent~, chats~) })
}

///|
/// The title the core says with message `m` of the chat a link of its written bare names (its `chats`).
fn chat_title_of(m : Message) -> (String) -> String? {
  fn(href) { m.linked(href).map(fn(l) { l.title }) }
}

///|
/// How wide what the viewer sent may be at the column's end: its bubble, and the quotes over it. Its words break their
/// lines where the composer broke them as they were typed (as wide as it sets them, the bubble's sides round them:
/// SendText.kt, "the field, flying words and own messages share their typography and line breaks"), so that sending
/// them only moves them; a column narrower than that has them as wide as it is.
fn mine_most(c : @ui.Ctx) -> Double {
  composer_words_width(c.width) + 2.0 * bubble_side
}

///|
/// The viewer's words in their bubble (MineBubble: 78% of the column and 560 at most, 8 by 14 in, 18 round, on the
/// neutral ground).
fn mine_bubble(
  c : @ui.Ctx,
  here : MessageHere,
  words : String,
  key : String,
  found? : Array[String] = [],
  peek? : ((String, String, Int) -> Unit)? = None,
  chat_title? : (String) -> String? = fn(_) { None },
  marks? : Array[(Int, Int)] = [],
) -> Unit {
  // words sent flying here: the bubble's ground comes in round them on their way (sfbase's flight.mbt)
  let flight = flight_here(here)
  let ground = match flight {
    Some(f) if f.placed => flight_ground_of(c, f)
    _ => 1.0
  }
  // (the bubble, for what is drawn in it as it flies: flight_pieces_in)
  let bubble_node = Ref::new(-1)
  let b = c.box(
    style=(if ground < 1.0 { bubble_bare } else { bubble }).then(@ui.style(max_w=Fixed(mine_most(c)))),
    fn() {
      if ground < 1.0 {
        let g = c.layer(fn() { c.box(style=bubble_ground, fn() {  }) |> ignore })
        c.look(g, @ui.look(alpha=ground))
      }
      // words sent flying here land on its words, piece by piece (sfbase's flight.mbt)
      match flight {
        Some(f) => {
          let w = c.box(fn() { person_words(c, words, key, found~, peek~, chat_title~, marks~) })
          flight_landing_words(c, f, w)
          flight_pieces_in(c, f, bubble_node)
        }
        None => person_words(c, words, key, found~, peek~, chat_title~, marks~)
      }
    },
  )
  bubble_node.val = b
  match flight {
    Some(f) => flight_bubble(c, f, b)
    None => ()
  }
}

///|
/// An agent's (or still.fail's) Markdown with its files (ProseWithFiles): those its text places (the core's `placed`)
/// drawn there, an HTML one as a visualization (PlacedFile), the rest under it; a link within a sentence to one it
/// places opens that file; Mermaid drawn; a station's screens' links as their cards.
fn prose_with_files(c : @ui.Ctx, src : Source, here : MessageHere, m : Message, files : Array[Attachment]) -> Unit {
  // (whose its files are, quoted from their menus)
  let by = (m.by.name, if m.author_kind == "agent" { "agent" } else { "person" }, m.ts)
  // an agent's request about a vault item: its card in place of the words, answered on it (decision.mbt)
  match m.card {
    Some({ ask: Some(ask), .. } as card) => {
      vault_ask_card(c, here, m, card, ask)
      return
    }
    Some({ phone: Some(phone), .. } as card) => {
      phone_ask_card(c, here, m, card, phone)
      return
    }
    _ => ()
  }
  let placed : Map[String, Attachment] = {}
  for n in m.placed {
    match files.iter().find_first(fn(a) { a.name == n }) {
      Some(a) => placed[n] = a
      None => ()
    }
  }
  let rest = files.filter(fn(a) { !placed.contains(a.name) })
  if m.text != "" {
    let mermaid_blocks = Ref(0)
    @sf.markdown(
      c,
      m.text,
      tree=m.md,
      key="msg-md/" + m.ts,
      size=body_size,
      found=marked_of(here, m.ts),
      bleed=here.gutter,
      // (none of its tables' copy keys in a picture of the chat)
      copy=picturing.val is None,
      on_link=fn(h) {
        match placed.get(@sf.file_name_of(h)) {
          Some(a) if is_viz(a.name) => viz_open_full(a.name, here.station, owner_of(here, a), a.path, here.session, linked=true)
          Some(a) => open_file(here, a)
          None =>
            match @sf.path_of_link(h) {
              // a file its path names: itself, as it is now, in the preview (its card is the pointer's, or a finger's
              // as it holds the chip)
              Some((path, _)) => open_named(here, m.by.agent, path)
              None => open_link(h)
            }
        }
      },
      on_link_hold=Some(fn(href, _) { if @sf.path_of_link(href) is None { link_held(c, href) } }),
      on_link_shown=link_peeks(c, src, here, agent=m.by.agent, chats=m.chats),
      chat_title=chat_title_of(m),
      // the files its paths name are its agent's (Chat.tsx ProseWithFiles' PathSession): their chips
      paths=m.by.agent != "",
      files=fn(name) {
        match placed.get(name) {
          // (a page drawn live is not in a picture of the chat: its card is, to tick)
          Some(a) if is_viz(a.name) && picturing.val is None =>
            Some({
              draw: fn() {
                viz_file_of(
                  c,
                  src,
                  here.station,
                  here.session,
                  owner_of(here, a),
                  m.ts,
                  a,
                  fn() { message_files(c, src, here, [a], false, by=Some(by)) },
                  @sf.theme().p.subtle,
                )
              },
              image: None,
            })
          Some(a) =>
            Some({
              draw: fn() { message_files(c, src, here, [a], false, by=Some(by)) },
              image: image_ratio(a).map(fn(r) { (r, fn(w) { file_item(c, src, here, a, w, by=Some(by)) }) }),
            })
          None => None
        }
      },
      code=fn(lang, code) {
        let first = match lang.find(" ") {
          Some(i) => lang.view(end_offset=i).to_owned()
          None => lang
        }
        if first.to_lower() == "mermaid" && code.trim() != "" {
          // Two identical blocks in one message still occupy two places, each with its own view.
          let block = mermaid_blocks.val
          mermaid_blocks.val += 1
          Some(fn() {
            c.scope(block, fn() { viz_mermaid_block(c, src, "chat/" + here.station + ":" + here.session + "/" + m.ts, code, @sf.theme().p.subtle) })
          })
        } else {
          None
        }
      },
      screens=Some(screen_links(c, src, here.station + "/" + here.session + "/" + m.ts)),
    )
    |> ignore
  }
  message_files(c, src, here, rest, false, by=Some(by))
}

///|
/// Whether a file is drawn as a visualization where its message places it: an HTML one (PlacedFile, kindOf).
fn is_viz(name : String) -> Bool {
  let n = name.to_lower()
  n.has_suffix(".html") || n.has_suffix(".htm")
}

///|
/// What still.fail itself says (SystemNotice): a pill across the chat in one line, a failure in red (the core's
/// `notice`); pressed, all its words and its time under it. One about a profile: what went wrong links to that
/// profile's page; one saying the station lacks the chat's runtime ends in installing it; a failure the station takes
/// reports of, in reporting it.
fn system_notice(c : @ui.Ctx, src : Source, station : String, m : Message) -> Unit {
  let id = c.id("notice/" + m.ts)
  if c.clicked(id) {
    notices_open[m.ts] = !notices_open.get(m.ts).unwrap_or(false)
  }
  let open = notices_open.get(m.ts).unwrap_or(false)
  let failed = m.notice_failed
  let said = m.notice_words
  let ink : @ui.Color = if failed { Danger } else { Fg }
  let install = match m.install {
    Some(i) if i.action != "" => Some(i)
    _ => None
  }
  let linked = m.profile != "" && m.notice_link >= 0 && m.notice_link <= said.length()
  c.box(style=notice_across, fn() {
    c.box(style=notice_pill_of(failed, open), id~, fn() {
      c.box(style=notice_line, fn() {
        c.box(style=notice_words_room, fn() {
          if linked {
            let p = @sf.theme().p
            c.rich(
              [
                @ui.span(said.view(end_offset=m.notice_link).to_string()),
                @ui.span(said.view(start_offset=m.notice_link).to_string(), underline=true, link="profile"),
              ],
              key="notice-profile/" + m.ts,
              style=(if open { notice_words_open } else { notice_words }).then(@ui.text_style(color=ink)),
              link_color=if failed { p.red } else { p.text },
              on_link=fn(_) { open_page(Setting(@settings.Route::Profile(station, m.profile))) },
            )
            |> ignore
          } else {
            // its words as Markdown, as the core read them (a chat it opened: a link to it); closed, their first block
            // on one line of the size it says
            let (meta, _) = c.text_size(notice_size)
            @sf.markdown(
              c,
              said,
              key=(if open { "notice/" } else { "notice-line/" }) + m.ts,
              tree=m.notice_md,
              size=if open { body_size } else { meta },
              line=if open { 0.0 } else { c.theme().leading(notice_leading).unwrap_or(0.0) / meta },
              one_line=!open,
              ink=if failed { @sf.theme().p.red } else { 0L },
              on_link=fn(h) { open_link(h) },
              chat_title=chat_title_of(m),
            )
            |> ignore
          }
        })
        |> ignore
        match install {
          Some(i) =>
            notice_action(c, "notice-install/" + m.ts, i.action, ink, install_busy(src, station, i), fn() {
              install_runtime(src, station, i)
            })
          None =>
            if m.reportable {
              report_action(c, src, station, m, ink)
            }
        }
      })
      |> ignore
    })
    |> ignore
    if open {
      message_time(c, "m:" + m.ts, m.time)
    }
  })
  |> ignore
}

///|
/// Notices opened (all their words and their time), by message.
let notices_open : Map[String, Bool] = {}

///|
/// A word at a notice's end that acts on it (InstallAction, ReportAction): " · " at 60%, then the word, underlined;
/// not offered while it is under way.
fn notice_action(c : @ui.Ctx, key : String, action : String, ink : @ui.Color, busy : Bool, run : () -> Unit) -> Unit {
  let id = c.id(key)
  if !busy {
    if c.clicked(id) {
      c.tell(key, run)
    }
  }
  c.box(style=notice_end, keep=true, fn() {
    c.box(style=notice_dot_room, fn() {
      c.text("·", style=if ink == Danger { notice_dot_failed } else { notice_dot }) |> ignore
    })
    |> ignore
    c.box(id~, fn() {
      let look = match (ink == Danger, busy) {
        (false, false) => notice_act
        (false, true) => notice_act_busy
        (true, false) => notice_act_failed
        (true, true) => notice_act_failed_busy
      }
      c.rich([@ui.span(action, underline=true)], style=look) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// Sending a failure notice to the still.fail team (ReportAction): asked first, saying what goes; what it was filed as
/// said once sent.
fn report_action(c : @ui.Ctx, src : Source, station : String, m : Message, ink : @ui.Color) -> Unit {
  let on = [("station", station), ("thread", m.thread.to_int().to_string()), ("seq", m.seq.to_int().to_string())]
  let busy = core_doing(src, ["chat.report"], on)
  let action = @sf.t("common.report.action")
  notice_action(c, "notice-report/" + m.ts, action, ink, busy, fn() {
    @sf.confirm(
      @sf.t("common.report.title"),
      @sf.t("common.report.lead") + "\n\n" + @sf.t("common.report.sends"),
      action,
      fn() {
        act(
          src,
          action,
          "",
          "chat.report",
          { "station": Json::string(station), "thread": Json::number(m.thread), "seq": Json::number(m.seq) },
          ok=fn(v) {
            let number = match field(Some(v), "number") {
              Some(Number(n, ..)) => n.to_int().to_string()
              _ => "?"
            }
            toast_later(
              @sf.t(if flag(Some(v), "duplicate") { "common.report.again" } else { "common.report.done" }, args=[
                ("number", number),
              ]),
            )
          },
        )
      },
    )
  })
}

///|
/// Whether a runtime is being installed on `station` (`software.update` by its id).
fn install_busy(src : Source, station : String, i : Install) -> Bool {
  core_doing(src, ["software.update"], [("station", station), ("id", i.runtime)])
}

///|
/// Installs on `station` the runtime a notice or a waiting message says it lacks (`software.update`).
fn install_runtime(src : Source, station : String, i : Install) -> Unit {
  act(src, i.action, "", "software.update", { "station": Json::string(station), "id": Json::string(i.runtime) })
}

///|
/// Under the viewer's message that waits for a runtime the station does not have (BlockedLine), in place of its
/// waiting: how that stands, in red while nothing is under way, then installing it; the whole line installs it.
fn blocked_line(c : @ui.Ctx, src : Source, station : String, key : String, b : Install) -> Unit {
  let stuck = b.state == "missing" || b.state == "failed"
  let busy = install_busy(src, station, b)
  let id = if b.action != "" { c.id("blocked/" + key) } else { 0 }
  if id != 0 && !busy {
    if c.clicked(id) {
      c.tell("blocked/" + key, fn() { install_runtime(src, station, b) })
    }
  }
  let hot = id != 0 && !busy && c.hovered(id)
  let words = if stuck { blocked_words_stuck } else { blocked_words }
  let line = c.box(style=if busy { blocked_row_busy } else { blocked_row }, id~, fn() {
    if b.state == "installing" {
      @sf.spinner(c, size=waiting_spin) |> ignore
    } else if stuck {
      c.box(style=failed_mark, fn() { c.text("!", style=failed_bang) |> ignore }) |> ignore
    }
    let title = match b.percent {
      Some(p) if b.state == "installing" => b.title + " " + p.to_int().to_string() + "%"
      _ => b.title
    }
    c.text(title, style=words) |> ignore
    if b.note != "" && b.action == "" {
      c.text("·", style=blocked_dot) |> ignore
      c.text(b.note, style=words) |> ignore
    }
    if b.action != "" {
      c.text("·", style=blocked_dot) |> ignore
      c.rich([@ui.span(b.action, underline=hot)], style=blocked_act) |> ignore
    }
  })
  // (its note whole where it is cut short, or said here only: its action in its place)
  @sf.tip(c, "blocked/" + key, line, if b.detail != "" { b.detail } else { b.note }, repeats=b.detail == "" && b.action == "")
}

///|
/// Quotes as sent (Quotes): each a card of its own ahead of the message, its own picture in it (a preview mark's
/// screenshot: the file of `files` it names); pressed, the list goes to the message it quotes. Sent from the composer,
/// each flies there from its card in it (sfbase's flight.mbt).
pub fn quotes(
  c : @ui.Ctx,
  src : Source,
  here : MessageHere,
  quotes : Array[Quote],
  files : Array[Attachment],
  mine? : Bool = false,
) -> Unit {
  if quotes.length() == 0 {
    return
  }
  let style = if mine { quote_cards_end.then(@ui.style(max_w=Fixed(mine_most(c)))) } else { quote_cards }
  c.box(style~, fn() {
    for i, q in quotes {
      let own = quote_file(q, files)
      let seq = match here.view.messages.iter().find_first(fn(m) { q.ts != "" && m.ts == q.ts }) {
        Some(m) => m.seq
        None => -1.0
      }
      let done = @sf.quote_card(
        c,
        "msg-quote/" + q.ts + "/" + i.to_string(),
        q.author,
        q.text,
        role=q.role,
        comment=q.comment,
        jump=q.ts != "" && here.go is Some(_),
        // (its own box, as the message's files have theirs: at most as wide as the card has room)
        picture?=own.map(fn(a) { fn() { message_files(c, src, here, [a], false) } }),
      )
      // (the passage it quotes lit there alone, where that message's words have it)
      match here.go {
        Some(go) if done.jumped && seq >= 0.0 => go(seq, q.text)
        _ => ()
      }
      // sent from the composer: it flies here from its card there
      match flight_here(here) {
        Some(f) =>
          flight_quote_landing(c, f, done.card, @sfbase.quote_key(i), @sf.quote_sent_shift(q.author, q.role))
        None => ()
      }
    }
  })
  |> ignore
}

///|
/// The file of a message's `files` that is a quote's own (fileOf): the one it names.
fn quote_file(q : Quote, files : Array[Attachment]) -> Attachment? {
  if q.file == "" {
    return None
  }
  files.iter().find_first(fn(a) { a.name == q.file })
}

///|
/// A message's files but those shown in its quotes' cards (besideQuotes).
fn beside_quotes(quotes : Array[Quote], files : Array[Attachment]) -> Array[Attachment] {
  let own = quotes.filter_map(fn(q) { if q.file == "" { None } else { Some(q.file) } })
  if own.length() == 0 {
    files
  } else {
    files.filter(fn(a) { !own.contains(a.name) })
  }
}

///|
/// What an agent of the chat said in Slack (or Feishu, or another chat) rather than here, or a person's message there
/// it was given (SentElsewhere): drawn as a message of theirs, that place's mark on the picture's corner and, after the
/// name, where it went or came from (its link), red where sending it failed.
pub fn sent_elsewhere(c : @ui.Ctx, src : Source, here : MessageHere, s : Elsewhere) -> Unit {
  let agent = if !s.received && s.by.agent != "" && here.view.agents.iter().any(fn(a) { a.key == s.by.agent }) {
    s.by.agent
  } else {
    ""
  }
  let surface = match s.place {
    Some(p) => p.surface
    None => "slack"
  }
  let key = "e:" + s.key
  others_message(
    c,
    here.inline,
    key,
    s.time,
    fn() {
      if s.received {
        c.box(style=person_avatar_room, fn() {
          person_avatar(c, src, s.by.name, s.by.name, s.by.picture)
          place_corner(c, surface)
        })
        |> ignore
      } else {
        agent_avatar(c, src, here, key, s.by.maker, s.by.runtime, if surface == "feishu" { "feishu" } else { "slack" }, agent)
      }
    },
    fn() { message_name(c, src, here, key, s.by.name, agent, "") },
    Some(fn() { elsewhere_route(c, key, s) }),
    fn() {
      @sf.markdown(c, s.text, key="msg-elsewhere/" + s.key, size=body_size, on_link=fn(h) {
        open_link(h)
      })
      |> ignore
      message_files(c, src, here, s.attachments, false)
    },
  )
}

///|
/// Where it went or came from (msgRoute): its mark, 发送到 or 来自 Slack, the place (its mark and its name, a link
/// where it has one: hPlace), 发送失败 in red.
fn elsewhere_route(c : @ui.Ctx, key : String, s : Elsewhere) -> Unit {
  let t = @sf.theme()
  let (url, app) = match s.place {
    Some(p) => (p.url, p.app)
    None => ("", "")
  }
  let place = if url != "" { c.id("msg-place/" + key) } else { 0 }
  if place != 0 {
    if c.clicked(place) {
      c.tell("msg-place/" + key, fn() { @sfbase.open_slack(app, url) |> ignore })
    }
  }
  c.box(style=msg_route, fn() {
    @sf.icon(c, if s.received { "received" } else { "send" }, size=route_icon, color=t.p.accent) |> ignore
    c.text(@sf.t(if s.received { "web-main.chat.fromSlack" } else { "web-main.history.sentTo" }).trim_end(chars=" ").to_string(), style=route_words)
    |> ignore
    c.box(style=if place != 0 && c.hovered(place) { route_place_hot } else { route_place }, id=place, fn() {
      let (mark, name) = match s.place {
        Some(p) => (p.surface, p.name)
        None => ("slack", "Slack")
      }
      match mark {
        "ember" | "stillfail" => @sf.drawable(c, if t.dark { "stillfail_mark_dark" } else { "stillfail_mark" }, route_mark) |> ignore
        "feishu" => @sf.feishu_mark(c, route_mark) |> ignore
        _ => @sf.slack_mark(c, route_mark) |> ignore
      }
      c.text(name, style=route_place_words) |> ignore
    })
    |> ignore
    if s.failed {
      c.box(style=route_failed, fn() { c.text(@sf.t("web-main.history.sendFailed"), style=route_failed_words) |> ignore })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A message's words (styles/conversation.css.ts msg, markdown): 14, on lines 1.65 (a person's plain words 1.55: both
/// the scale's 22 here; a time's 11 its 18).
pub let body_size : Double = 14.0

///|
/// A picture in a chat (msgAvatar): 18 round; an agent's mark 12 in it.
let avatar_side : Double = 18.0

///|
let agent_mark_side : Double = 12.0

///|
/// A place's mark on a picture's corner (msgAvatarSlack): 9 in its 14.
let place_corner_side : Double = 9.0

///|
/// The viewer's bubble's sides (chat.css.ts msgMine msgBubble: `bubble`'s px=S3_5).
let bubble_side : Double = 14.0


///|
/// A message's spinner, small (Spinner inline).
let waiting_spin : Double = 12.0


///|
/// Where a message goes, its route's mark (14) and a place's mark (12).
let route_icon : Double = 14.0

///|
let route_mark : Double = 12.0

///|
/// Someone else's message (msgRow, msgMain): its words the column's width, 4 apart.
// kept across runs: a value (no field of it changes)
let msg_row : @ui.Style = @ui.css("w=Full")

///|
/// Keep the header actions clear of the preceding message's time at the same edge.
// kept across runs: a value (no field of it changes)
let msg_row_share : @ui.Style = @ui.css("w=Full mt=S1_5")

///|
// kept across runs: a value (no field of it changes)
let msg_main : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let msg_main_share : @ui.Style = @ui.css("w=Full")

///|
/// Its head (msgHead): 24 high at least, its name, route and time 6 apart.
// kept across runs: a value (no field of it changes)
let msg_head : @ui.Style = @ui.css("row w=Full min_h=S6 gap=S1_5 align=ACenter")

///|
/// Its head's line's height (S6, msg_head's and msg_head_inline's least): what goes beside it is on its middle.
let head_line_h : Double = 24.0

///|
/// An inline head (inlineHeads msgHead): in past the picture (25: its 18 and 7); where it went on a line of its own.
// kept across runs: a value (no field of it changes)
let msg_head_inline : @ui.Style = @ui.style(row=true, w=Full, min_h=S6, pl=@sf.message_head_in, gap=S1_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let msg_route_line : @ui.Style = @ui.css("row w=Full")

///|
// kept across runs: a value (no field of it changes)
let msg_avatar_inline : @ui.Style = @ui.style(pt=@sf.message_avatar_down)

///|
/// Its picture out in the margin (align.ts columns.avatar: 29 before the words, 3 down), held 8 under the pane's top
/// (sticky): under the chat's bar (45) and 8 more.
// kept across runs: a value (no field of it changes)
let msg_avatar_room : @ui.Style = @ui.style(pt=@sf.message_avatar_down, ml=@sf.message_avatar_out)

///|
let avatar_held_at : Double = 53.0

///|
/// A name (msgHead msgName): 13 in 600, the accent's ink, 240 at most; the accent itself under the pointer.
// kept across runs: a value (no field of it changes)
pub let msg_name_room : @ui.Style = @ui.style(w=Cut, max_w=@sf.name_max)

///|
// kept across runs: a value (no field of it changes)
pub let msg_name : @ui.TextStyle = @ui.text_style(size=Meta, weight=Semibold, leading=L5, color=AccentText, wrap=false, w=Cut)


///|
/// A time (msgTime): 11, muted.
// kept across runs: a value (no field of it changes)
let msg_time : @ui.TextStyle = @ui.text_style(size=Caption, leading=L5, color=Muted, wrap=false)

///|
/// The viewer's message (msgMine): at the column's end, 4 apart.
// kept across runs: a value (no field of it changes)
let mine_column : @ui.Style = @ui.css("w=Full gap=S1 align=AEnd")

///|
/// Its bubble (msgMine msgBubble): 8 by 14 in, 18 round, the neutral ground.
// kept across runs: a value (no field of it changes)
let bubble : @ui.Style = @ui.css("px=S3_5 py=S2 radius=Xl2 bg=Neutral")

///|
/// How far the bubble's words are in from its top and its foot (bubble's S2).
let bubble_in_y : Double = 8.0

///|
/// Its ground on its own (coming in round words sent flying here), and the bubble without it meanwhile.
// kept across runs: a value (no field of it changes)
let bubble_ground : @ui.Style = @ui.css("w=Full h=Full radius=Xl2 bg=Neutral")

///|
// kept across runs: a value (no field of it changes)
let bubble_bare : @ui.Style = @ui.css("px=S3_5 py=S2 radius=Xl2")

///|
/// That its agents have yet to take it (msgWaiting): a spinner and the words 5 apart.
// kept across runs: a value (no field of it changes)
let msg_waiting : @ui.Style = @ui.css("row gap=S1_25 align=ACenter")

///|
/// An agent's picture (msgAvatarAgent): 18 round on the neutral ground, its mark in the middle.
// kept across runs: a value (no field of it changes)
let agent_avatar_ground : @ui.Style = @ui.css("w=S4_5 h=S4_5 radius=Full bg=Neutral align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let person_avatar_room : @ui.Style = @ui.css("w=S4_5 h=S4_5")

///|
/// A place's mark on its corner (msgAvatarSlack): 14 round, 6 past the picture's right and foot, on the list's ground
/// with a line round it.
// kept across runs: a value (no field of it changes)
let place_corner_room : @ui.Style = @ui.css("w=Full h=Full align=AEnd justify=JEnd")

///|
// kept across runs: a value (no field of it changes)
let place_corner_mark : @ui.Style = @ui.css(
  #|w=S3_5 h=S3_5 radius=Full bg=Bg border=B1 border_color=Line align=ACenter justify=JCenter
).then(@sf.outset_end(6.0)).then(@sf.outset_bottom(6.0))

///|
/// A notice (msgSystem): across the chat, in its middle, its time 4 under it once opened.
// kept across runs: a value (no field of it changes)
let notice_across : @ui.Style = @ui.css("w=Full gap=S1 align=ACenter")

///|
/// Its pill (msgSystemBox): as wide as its words, 6 by 14 in, round at its ends (16 once opened); the hover ground, a
/// failure's red ground.
fn notice_pill_of(failed : Bool, open : Bool) -> @ui.Style {
  match (failed, open) {
    (false, false) => notice_pill
    (false, true) => notice_pill_open
    (true, false) => notice_pill_failed
    (true, true) => notice_pill_failed_open
  }
}

///|
// kept across runs: a value (no field of it changes)
let notice_pill : @ui.Style = @ui.css("max_w=Full px=S3_5 py=S1_5 radius=Full bg=Hover")

///|
// kept across runs: a value (no field of it changes)
let notice_pill_open : @ui.Style = notice_pill.then(@ui.css("radius=Xl1_5"))

///|
// kept across runs: a value (no field of it changes)
let notice_pill_failed : @ui.Style = notice_pill.then(@ui.css("bg=DangerBg"))

///|
// kept across runs: a value (no field of it changes)
let notice_pill_failed_open : @ui.Style = notice_pill_open.then(@ui.css("bg=DangerBg"))

///|
/// Its words and what is done at their end (msgSystemLine, msgSystemEnd): the words cut short before it, which keeps
/// its room whole (notice_action: kept, as a row's end).
// kept across runs: a value (no field of it changes)
let notice_line : @ui.Style = @ui.css("row align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let notice_words_room : @ui.Style = @ui.css("clip")

///|
// kept across runs: a value (no field of it changes)
let notice_end : @ui.Style = @ui.css("row align=AEnd")

///|
/// Its words closed (msgSystemBox markdown): their size and their lines', its Markdown's too.
// kept across runs: a value (never changed)
let notice_size : @ui.TextSize = Meta

///|
// kept across runs: a value (never changed)
let notice_leading : @ui.Leading = L7

///|
/// Its words about a profile (one line closed).
// kept across runs: a value (no field of it changes)
let notice_words : @ui.TextStyle = @ui.text_style(size=notice_size, leading=notice_leading, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let notice_words_open : @ui.TextStyle = @ui.text_style(size=notice_size, leading=notice_leading)

///|
/// The dot before its word (blockedDot in a notice): 6 each side, the pill's ink at 60%; the word (blockedAction),
/// underlined; at 50% while under way.
// kept across runs: a value (no field of it changes)
let notice_dot_room : @ui.Style = @ui.css("px=S1_5")

///|
// kept across runs: a value (no field of it changes)
let notice_dot : @ui.TextStyle = @ui.text_style(size=Meta, leading=L7, color=A(Fg, O60), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let notice_dot_failed : @ui.TextStyle = notice_dot.then(@ui.text_style(color=A(Danger, O60)))

///|
// kept across runs: a value (no field of it changes)
let notice_act : @ui.TextStyle = @ui.text_style(size=Meta, leading=L7, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let notice_act_busy : @ui.TextStyle = notice_act.then(@ui.text_style(color=A(Fg, O50)))

///|
// kept across runs: a value (no field of it changes)
let notice_act_failed : @ui.TextStyle = notice_act.then(@ui.text_style(color=Danger))

///|
// kept across runs: a value (no field of it changes)
let notice_act_failed_busy : @ui.TextStyle = notice_act.then(@ui.text_style(color=A(Danger, O50)))

///|
/// A blocked line (blocked): at the column's end, 4 apart, wrapping; red while stuck; at 60% while installing.
// kept across runs: a value (no field of it changes)
let blocked_row : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let blocked_row_busy : @ui.Style = blocked_row.then(@ui.css("opacity=O60"))

///|
// kept across runs: a value (no field of it changes)
let blocked_words : @ui.TextStyle = @ui.text_style(size=Caption, leading=L5, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let blocked_words_stuck : @ui.TextStyle = blocked_words.then(@ui.text_style(color=Danger))

///|
// kept across runs: a value (no field of it changes)
let blocked_dot : @ui.TextStyle = @ui.text_style(size=Caption, leading=L5, color=Muted, wrap=false)

///|
/// Installing (blockedAction): a word in the text's ink, 600, underlined under the pointer.
// kept across runs: a value (no field of it changes)
let blocked_act : @ui.TextStyle = @ui.text_style(size=Caption, leading=L5, weight=Semibold, color=Fg, wrap=false)

///|
/// A message's quote cards (quoteCards): one under another 4 apart, at its end when it is the viewer's.
// kept across runs: a value (no field of it changes)
let quote_cards : @ui.Style = @ui.css("w=Full gap=S1 align=AStart")

///|
/// The viewer's: as wide as the widest of them needs, at most as its bubble may be (mine_most), at the column's end
/// over it, as their message is one column there (msgMine: the web's quoteCards justified to its end).
// kept across runs: a value (no field of it changes)
let quote_cards_end : @ui.Style = @ui.css("gap=S1")

///|
/// Where it went (msgRoute): its mark in the accent, the words muted, the place, 6 apart.
// kept across runs: a value (no field of it changes)
let msg_route : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let route_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// The place (later.css.ts hPlace): its mark and its name, 12 in 500, 1 by 6 in, 6 round on the neutral ground; a
/// link's the hover ground under the pointer.
// kept across runs: a value (no field of it changes)
let route_place : @ui.Style = @ui.css("row px=S1_5 py=SPx gap=S1 radius=Md bg=Neutral align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let route_place_hot : @ui.Style = route_place.then(@ui.css("bg=Hover"))

///|
// kept across runs: a value (no field of it changes)
let route_place_words : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Fg, leading=L5, wrap=false)

///|
/// Sending it failed (Pill tone red).
// kept across runs: a value (no field of it changes)
let route_failed : @ui.Style = @ui.css("px=S1_5 py=SPx radius=Md bg=DangerBg")

///|
// kept across runs: a value (no field of it changes)
let route_failed_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Danger, wrap=false)

///|
/// It failed (parts.css.ts failedMark, as a blocked line has it): 12 round, red, its "!" 8 in 600, white.
// kept across runs: a value (no field of it changes)
let failed_mark : @ui.Style = @ui.css("w=S3 h=S3 radius=Full bg=Danger align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let failed_bang : @ui.TextStyle = @ui.text_style(size=Caption, leading=L3, weight=Semibold, color=OnDanger, wrap=false)
