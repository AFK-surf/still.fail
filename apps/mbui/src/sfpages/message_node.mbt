// A chat's message (message.mbt's) as nodes of the window's tree, made once: what it says, who said it and when
// followed as the message changes (`m`, its getter), its parts made again only as what they are changes.

///|
/// When it was said (message_time's): how long ago, or when (pressed, every time in the app says the other), the other
/// way in its tip (`tips`, where the window has them); nothing where it has no time. Each as it changes.
fn message_time_node(parent : @view.View, time : () -> Stamp?, tips : @sf.TipLayer?) -> Unit {
  parent.show(fn() { time() is Some(_) }, fn(slot) {
    let said = fn(full : Bool) {
      match time() {
        Some(s) => if full { s.full } else { s.ago }
        None => ""
      }
    }
    let t = @sf.words_node(slot, fn() { said(absolute_times.get()) }, fn() { msg_time })
    @sf.presses_node(t, fn() { absolute_times.set(!@signals.untracked(fn() { absolute_times.get() })) })
    t.says(By(fn() { Some(@view.said(Button, label=said(absolute_times.get()))) })) |> ignore
    match tips {
      Some(tips) => @sf.tip_node(tips, t, fn() { said(!absolute_times.get()) }) |> ignore
      None => ()
    }
  })
}

///|
/// A name over its message (message_name's): one that goes somewhere (`press`: one of the chat's agents' to its history
/// beside the chat, another chat's agent's to that chat) underlined under the pointer; in the accent's words, cut short
/// at name_max.
fn message_name_node(parent : @view.View, name : () -> String, press : (() -> Unit)?) -> @view.View {
  parent.box(fn(room) {
    room.max_width(Is(Some(240.0))).min_width(Is(Some(0.0))) |> ignore
    room.box(fn(w) {
      w
      .words_runs(By(fn() { [@ui.span(name(), underline=press is Some(_) && w.pointed())] }))
      .words_look(By(fn() { @ui.style_words(msg_name) }))
      .ink(By(fn() { @ui.style_ink(msg_name) }))
      .cuts(Is(true))
      .min_width(Is(Some(0.0)))
      .allow_ellipsis(Is(true))
      |> ignore
      match press {
        Some(go) => {
          @sf.presses_node(w, go)
          w.says(By(fn() { Some(@view.said(Link, label=name())) })) |> ignore
        }
        None => ()
      }
    })
    |> ignore
  })
}

///|
/// A person's picture in a chat (person_avatar's): 18 round, their face where they have one (asked for on the time
/// on top of the page it is on, `stint`).
fn person_avatar_node(parent : @view.View, src : Source, id : () -> String, name : () -> String, picture : () -> String, stint : () -> Int) -> Unit {
  @sf.avatar_node(parent, id, name, fn() {
    let p = picture()
    if p != "" { (src.picture)(p, stint()) } else { "" }
  }, avatar_side)
}

///|
/// An agent's picture in a chat (agent_avatar's): its model's maker (still.fail's mark without one: `maker` and
/// `runtime` both "") on the neutral ground, 18 round; what it said gone elsewhere (`place`: slack | feishu | ""),
/// that place's mark on its corner, 9 across on the list's ground with a line round it, 6 past its end and foot.
fn agent_avatar_node(parent : @view.View, maker : () -> String, runtime : () -> String, place : () -> String) -> @view.View {
  parent.box(fn(d) {
    d
    .bone_whole(Is(true))
    .width(Is(Some(avatar_side)))
    .height(Is(Some(avatar_side)))
    .radius(Is(avatar_side / 2.0))
    .row(Is(true))
    .lies_along(Is(Middle))
    .lines_up(Is(Some(Middle)))
    .ground(By(fn() { @ui.tree_theme().color(Neutral) }))
    |> ignore
    d.pick(fn() { maker() != "" || runtime() != "" }, fn(m, known) {
      if known {
        @sf.maker_mark_node(m, maker, fn() { if runtime() != "" { runtime() } else { "claude" } }, agent_mark_side) |> ignore
      } else {
        @sf.drawable_node(m, fn() { if @sf.theme().dark { "stillfail_mark_dark" } else { "stillfail_mark" } }, agent_mark_side) |> ignore
      }
    })
    d.show(fn() { place() != "" }, fn(o) {
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
        @sf.place_mark_node(k, fn() { place() == "feishu" }, place_corner_side) |> ignore
      })
      |> ignore
    })
  })
}

///|
/// What a person wrote (person_words'): as they wrote it, the core's runs of it (references to chats their chips, one
/// bare reading as `chat_title` says; web addresses links, pressed opening them), else the runs kept as it was sent,
/// else the words as they are; the words found (`found`) in bold; in the theme's words. Each as it changes.
fn person_words_node(
  parent : @view.View,
  words : () -> String,
  runs : () -> Json?,
  found : () -> Array[String],
  chat_title : (String) -> String?,
  peeks? : (@view.View, @ui.RunsLinks, () -> Array[@ui.Run]) -> Unit = fn(_, _, _) {  },
) -> @view.View {
  let shown = fn() {
    @sf.found_weight(@sfbase.person_runs(words(), runs(), @sf.theme().p.accent, chat_title~), found())
  }
  parent.box(fn(w) {
    w
    .words_runs(By(shown))
    .words_look(By(fn() { @ui.style_words(@sf.theme().t.words) }))
    .ink(By(fn() { @ui.style_ink(@sf.theme().t.words) }))
    .runs_look(By(fn() { { ..@view.runs_plain, link: @sf.theme().p.blue, words: true } }))
    |> ignore
    let links = @ui.runs_links(w, shown, fn(h) { open_link(h) }, hold=link_held_node)
    // (each link's card while the pointer rests on it: link_peek_node.mbt)
    peeks(w, links, shown)
  })
}

///|
/// Someone else's message whose parts are all nodes (others_message's): its head (its picture at its start where the
/// list is narrow, else out in the margin; its name; its time) over its words: a person's as they wrote them, an
/// agent's as Markdown. `here` where it is shown, `m` the message, each as it changes.
fn others_message_node(row : @view.View, src : Source, here : () -> MessageHere, m : () -> Message, tips : @sf.TipLayer?) -> Unit {
  let inline = fn() { here().inline }
  // (out of its agent's picture (emit.mbt): not drawn while the picture is on its way to it, its head sliding out of
  // the picture as it comes out)
  let out = fn() {
    match emits_here(here(), m()) {
      Some((em, _)) => @sfbase.emit_head_at(em, m().seq, fn() { row.drawn_at() })
      None => None
    }
  }
  let out_from = fn() {
    match emits_here(here(), m()) {
      Some((em, _)) => @sfbase.emit_out_from(em, m().seq)
      None => None
    }
  }
  // (the native mouse's header actions have their room before the row, not between the head and body:
  // msg_row_share and msg_main_share; a finger's msg_main keeps its four points below the head)
  row
  .gap(By(fn() { if message_shares(here(), m()) { 0.0 } else { @ui.Space::px(S1) } }))
  .margin(By(fn() { (0.0, if message_shares(here(), m()) { @ui.Space::px(S1_5) } else { 0.0 }, 0.0, 0.0) }))
  .alpha(By(fn() {
    match emits_here(here(), m()) {
      Some((em, _)) if emit_awaited(em, m().seq) => 0.0
      _ => 1.0
    }
  }))
  // (its words a glyph at a time as it comes out, in the order they read, each a little before or after its turn)
  .glyphs_by(By(fn() { out_from().map(fn(_) { row.drawn_at() }) }), fn(at, g) {
    match @signals.untracked(out_from) {
      Some(from) => @sfbase.emit_glyph_out(@signals.untracked(m).seq, from, at, g, row.rect())
      None => { alpha: 1.0, dx: 0.0, dy: 0.0, scale: 1.0, sx: 1.0 }
    }
  })
  |> ignore
  // (its head: 24 high at least, 6 apart; inline, 25 in from the row's start for the picture over its start)
  row.box(fn(head) {
    head
    .row(Is(true))
    .min_height(Is(Some(head_line_h)))
    .gap(Is(6.0))
    .lines_up(Is(Some(Middle)))
    .padding(By(fn() { (if inline() { 25.0 } else { 0.0 }, 0.0, 0.0, 0.0) }))
    .alpha(By(fn() { out().unwrap_or(1.0) }))
    .offset(By(fn() { (-@sfbase.emit_head_slide * (1.0 - out().unwrap_or(1.0)), 0.0) }))
    |> ignore
    // (one of the chat's agents' to its history beside the chat; another chat's agent's to that chat: message_name's)
    let now = @signals.untracked(m)
    let press = if now.by.agent != "" {
      Some(fn() { open_detail(src, here_ref(here()), m().by.agent) })
    } else if now.by.from != "" {
      Some(fn() { open_link(m().by.from) })
    } else {
      None
    }
    let name = message_name_node(head, fn() { m().by.name }, press)
    // (an agent's name: its card while the pointer rests on it, as over its picture: agent_hover's)
    if now.by.agent != "" {
      agent_hover_node(name, src, here, fn() { m().by.agent })
    }
    message_time_node(head, fn() { m().time }, tips)
    // (its words, link and turn's picture where a mouse is what it is used with, at its head's end while the pointer
    // rests on it or its menu shows: share_turn_tool's; a finger has them on the bar of what it holds picked)
    if message_shares(here(), m()) {
      head.box(fn(gap) { gap.grow(Is(1.0)) |> ignore }) |> ignore
      let anchor = Ref(head)
      let key = fn() { "m:" + m().ts + "/message-menu" }
      let close = fn() { if @sf.menu_is_open(key()) { @sf.menu_open_here("", 0.0, 0.0) } }
      head.show(fn() { row.pointed_in() || @sfbase.message_menu_on("m:" + m().ts) }, fn(more) {
        anchor.val = more
        more.width(Is(Some(24.0))).height(Is(Some(24.0))).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
        // (the library's ⋯ menu by its key, as menu_of keeps it: one open at a time, its button pressed again closing it)
        @sf.round_key_node(more, "more", fn() { @sf.t("web-main.menu.more") }, fn() {
          if @sf.menu_is_open(key()) { close() } else { @sf.menu_open_here(key(), 0.0, 0.0) }
        }, side=24.0, icon_size=16.0)
      })
      // (the menu belongs to the message, not the hover button: it finishes leaving where it hung when that
      // button disappears; beside keeps that last place after its anchor is gone)
      let popup = @sf.popup_root_node(head)
      @sf.menu_node(popup, fn() { @sf.menu_is_open(key()) }, fn(_) { anchor.val }, fn() {
        message_items_of(src, here(), m())
      }, "", End, 6.0, false, false, fn(item) {
        close()
        (item.select)()
      }, close, exit=true)
    }
  })
  |> ignore
  // (right clicked: its turn offered the window's right click menu, as pickable offers it)
  row.points(Is(true)).on_menu(fn(mn) {
    let now = @signals.untracked(m)
    let h = @signals.untracked(here)
    if message_shares(h, now) {
      @sfbase.offer_message_menu(mn.wx, mn.wy, message_share_of(src, h, now), @sfbase.message_link(h.station, h.session, now.seq), now.text, "m:" + now.ts)
    }
  })
  |> ignore
  // (its picture: inline over its head's start, 3 down; else out in the margin, 29 before its words; where a message
  // out of an agent's picture lands, away while the flying one is over it: emit.mbt)
  row.box(fn(room) {
    // (the room holds to the message's foot and, outside the head, to the same top as the old page. Inline pictures
    // go with their heads; a top far above the list leaves them where they were laid.)
    // View::sticks has no disabled value yet; -1e9 leaves inline pictures at their laid position.
    room
    .over(Is(true))
    .width(Is(Some(avatar_side)))
    .height(Is(Some(avatar_side + @ui.Space::px(@sf.message_avatar_down))))
    .sticks(By(fn() { if inline() { -1.0e9 } else { avatar_held_at } }))
    |> ignore
    room.box(fn(a) {
      a
      .over(Is(true))
      .offset(By(fn() { (if inline() { 0.0 } else { -29.0 }, 3.0) }))
      .alpha(By(fn() {
        match emits_here(here(), m()) {
          Some((em, _)) if emit_emitting(em, m().seq) || emit_awaited(em, m().seq) => 0.0
          _ => 1.0
        }
      }))
      |> ignore
      // (said as the old view's box round it was, 3 over it: emit_flight puts the face 3 down it)
      emit_place_node(a, fn() { emits_here(here(), m()).map(fn(e) { "emit-landing/" + e.1 + "/" + seq_s(m().seq) }) }, dy=-3.0)
      a.pick(fn() { m().author_kind }, fn(slot, kind) {
        match kind {
          "agent" => {
            let face = agent_avatar_node(slot, fn() { m().by.maker }, fn() { m().by.runtime }, fn() { "" })
            // (its card while the pointer rests on it: agent_hover's)
            agent_hover_node(face, src, here, fn() { m().by.agent })
          }
          "station" | "ember" | "stillfail" => agent_avatar_node(slot, fn() { "" }, fn() { "" }, fn() { "" }) |> ignore
          _ => person_avatar_node(slot, src, fn() { m().author }, fn() { m().by.name }, fn() { m().by.picture }, fn() { 0 })
        }
      })
    })
    |> ignore
  })
  |> ignore
  // (what it quotes, over its words)
  row.show(fn() { !m().quotes.is_empty() }, fn(q) {
    quotes_node(q, src, here, fn() { m().quotes }, fn() { m().attachments }, false, fn() { 0.0 }, fn() { message_place(m()) })
  })
  // (its words: a person's as written, an agent's as Markdown, the files it places drawn where it places them; picked
  // as the chat's: pick_node.mbt)
  // (its files under its words, right under them as prose_with_files has them, beside what it quotes; those its words
  // place where they place them)
  let files = fn() {
    let now = m()
    beside_quotes(now.quotes, now.attachments).filter(fn(a) { now.author_kind == "person" || !now.placed.contains(a.name) })
  }
  let files_node = fn(col : @view.View) {
    col.show(fn() { !files().is_empty() }, fn(fs) {
      message_files_node(fs, src, here, files, false, at=fn() { message_place(m()) + "/f" }, by=fn() {
        Some((m().by.name, if m().author_kind == "person" { "person" } else { "agent" }, m().ts))
      })
    })
  }
  row.pick(fn() {
    // (an agent's ask about a vault item or its person's phone: its card in place of its words, answered on it)
    match m().card {
      Some({ ask: Some(_), .. }) => 2
      Some({ phone: Some(_), .. }) => 3
      Some({ signin: Some(_), .. }) => 4
      _ => if m().author_kind == "person" { 1 } else { 0 }
    }
  }, fn(body, kind) {
    if kind == 2 {
      vault_ask_card_node(body, here, m)
      return
    }
    if kind == 3 {
      phone_ask_card_node(body, here, m)
      return
    }
    if kind == 4 {
      signin_ask_card_node(body, here, m)
      return
    }
    let person = kind == 1
    pick_row_node(row, body, fn() {
      let h = here()
      let now = m()
      guard h.list is Some(_) && now.text != "" else { return None }
      Some({
        key: now.ts,
        ts: now.ts,
        author: now.by.name,
        role: if now.author_kind == "person" { "person" } else { "agent" },
        words: now.text,
        share: h.view.thread.map(fn(thread) { fn() { open_publish(src, here_ref(h), thread, turn=Some(now.seq)) } }),
        link: @sfbase.message_link(h.station, h.session, now.seq),
      })
    })
    // (its files under its words 4 apart, as message_row's column has them; but an agent's in a chat's list right under
    // its Markdown, where picking holds them in one box with no gap (prose_with_files'); out of a list picking holds
    // nothing and the column's 4 is theirs too)
    body.gap(By(fn() { if person || here().list is None { 4.0 } else { 0.0 } })) |> ignore
    if person {
      body.show(fn() { m().text != "" }, fn(w) {
        person_words_node(w, fn() { m().text }, fn() { m().words }, fn() { marked_of(here(), m().ts) }, fn(href) {
          m().linked(href).map(fn(l) { l.title })
        }, peeks=fn(w, links, runs) {
          link_peeks_node(w, links, runs, src, here, chats=fn() { m().chats }, link_to=fn() { link_to_in(m()) })
        })
        |> ignore
      })
    } else {
      @sf.markdown_node(
        body,
        fn() { m().text },
        tree=fn() { m().md },
        size=fn() { body_size },
        found=fn() { marked_of(here(), m().ts) },
        // (out into its row's way in from the pane's sides, as its row is laid out: chat_row_bleed; else as said)
        bleed=@signals.untracked(fn() { here().gutter }),
        bleed_by?=body.lent(chat_row_bleed),
        // (a file its agent names by its path: itself, as it is now, in the preview; any other link, opened)
        on_link=fn(h) {
          let now = here()
          match placed_of(m(), @sf.file_name_of(h)) {
            // (a file its words place: a visualization over the whole screen, any other in the preview)
            Some(a) if is_viz(a.name) => viz_open_full(a.name, now.station, owner_of(now, a), a.path, now.session, linked=true)
            Some(a) => open_file(now, a, at=message_place(m()) + "/f")
            None =>
              match @sf.path_of_link(h) {
                Some((path, _)) => open_named(src, now.station, m().by.agent, path)
                None => open_link(h)
              }
          }
        },
        on_link_hold=Some(link_held_node),
        // (its links to a station's screens: a paragraph of only one its card; one bare in a sentence its title: sfbase's
        // screen_links_node)
        screens=@sfbase.screen_links_node(src, fn() {
          let h = here()
          h.station + "/" + h.session + "/" + m().ts
        }),
        // (each link's card while the pointer rests on it, a file its agent names by its path its few lines)
        links_made=Some(fn(w, links, runs) {
          link_peeks_node(w, links, runs, src, here, agent=fn() { m().by.agent }, chats=fn() { m().chats }, link_to=fn() {
            link_to_in(m())
          })
        }),
        chat_title=fn(href) { m().linked(href).map(fn(l) { l.title }) },
        paths=@signals.untracked(fn() { m().by.agent != "" }),
        // (the files its words place, where they place them: an image in a row of them as wide as it is given, any
        // other as it is under its words; a page a visualization is: viz_node's)
        files=fn(name) {
          guard placed_of(m(), name) is Some(a) else { return None }
          let by = fn() { Some((m().by.name, if m().author_kind == "person" { "person" } else { "agent" }, m().ts)) }
          let at = fn() { message_place(m()) + "/f" }
          if is_viz(a.name) {
            return Some({ draw: fn(v) { viz_placed_node(v, src, here, m, a) }, image: None })
          }
          Some({
            draw: fn(v) { message_files_node(v, src, here, fn() { [a] }, false, at~, by~) },
            image: image_ratio(a).map(fn(r) {
              (r, fn(v : @view.View, w : () -> Double) {
                ignore(media_file_node(v, src, here, fn() { a }, "image", (v.parent().unwrap(), fn(_) { Some(w()) }), at, @sf.message_file_corner, by, fills=true))
              })
            }),
          })
        },
        code=fn(lang) {
          let first = match lang.find(" ") {
            Some(i) => lang.view(end_offset=i).to_owned()
            None => lang
          }
          if first.to_lower() == "mermaid" {
            Some(fn(v, code) { mermaid_placed_node(v, src, here, m, code) })
          } else {
            None
          }
        },
      )
      |> ignore
    }
    files_node(body)
  })
  // (what it asks, under it, in its chat's list: its card, its options, 忽略)
  row.show(fn() {
    let now = m()
    here().list is Some(_) && (now.card is Some(_) || now.options is Some(_) || now.decision is Some(_) || now.asked)
  }, fn(d) { decision_node(d, src, here, m) })
}

///|
/// How message `m` is drawn whole by nodes now: someone else's words alone (1: others_message_node), the viewer's
/// (2: mine_message_node), its files beside its words, what it asks under them; none of it with a page
/// of its own among its files or files its words place, or a card in place of its words (0: not yet); what still.fail
/// itself says, its notice (5: notice_node).
fn message_made_whole(m : Message) -> Int {
  // (what still.fail itself says: its notice, notice_node.mbt)
  if m.system {
    return 5
  }
  if m.mine {
    2
  } else {
    1
  }
}

///|
/// What the viewer sent as its row draws it (mine_row_node): its place (message_place's: the outbox entry's, then the
/// message's), its words and their runs, what it quotes, its message's ts (what is found in it), the title the core
/// says of a chat a link of its names, and what goes under it; its files (beside what it quotes) and where in the chat
/// they are, and what of it still goes up (an outbox entry's uploads: name, size, how much is up).
struct MineRow {
  place : () -> String
  text : () -> String
  words : () -> Json?
  quotes : () -> Array[Quote]
  files : () -> Array[Attachment]
  files_at : () -> String
  /// all its files (what it quotes' own pictures among them) and where in the chat it is
  attachments : () -> Array[Attachment]
  quotes_at : () -> String
  uploads : () -> Array[(String, Int, Int)]
  failed : () -> String
  ts : () -> String
  seq : () -> Double
  /// its row's key in its chat's list (Entry::id)
  key : () -> String
  linked : (String) -> String?
  foot_shown : () -> Bool
  foot : (@view.View) -> Unit
}

///|
/// What the viewer sent, whose parts are all nodes (mine_message's, outbox_row's): at the column's end, what it quotes
/// over its words in their bubble (as wide as the composer sets them and its sides round them at most, 8 by 14 in, 18
/// round, the neutral ground), what goes under it under them. Its bubble and its words said where words sent land, by
/// its place as that is now (mine_landings). `width` the pane's, as it changes.
fn mine_row_node(col : @view.View, src : Source, here : () -> MessageHere, row : MineRow, width : () -> Double) -> Unit {
  col.gap(Is(4.0)).lines_up(Is(Some(End))) |> ignore
  // (where what was sent lands, as its parts are made and let go: said by its place as that is now (the outbox
  // entry's, then the message's), the one before let go; none while it has no part)
  let text : Ref[(@view.View, @view.View)?] = Ref(None)
  let quotes : Map[String, @sf.QuoteCardNode] = {}
  let files : Map[String, @sfbase.FileLandingNode] = {}
  let said : Ref[(String, MineLanding)?] = Ref(None)
  let unsay = fn() {
    match said.val {
      Some((at, l)) =>
        match @signals.untracked(fn() { mine_landings.get(at) }) {
          Some(now) if physical_equal(now, l) => mine_landings.remove(at)
          _ => ()
        }
      None => ()
    }
    said.val = None
  }
  let say = fn(place : String) {
    unsay()
    let anchor = match text.val {
      Some((bubble, _)) => Some(bubble)
      None =>
        match quotes.get(@sfbase.quote_key(0)) {
          Some(q) => Some(q.root)
          None => files.values().next().map(fn(f) { f.view })
        }
    }
    guard anchor is Some(anchor) else { return }
    let l = { anchor, text: text.val, files: files.copy(), quotes: quotes.copy() }
    said.val = Some((place, l))
    mine_landings[place] = l
  }
  let place = fn() { @signals.untracked(row.place) }
  col.owns(unsay) |> ignore
  col.reacts(row.place, fn(p) { say(p) })
  // (what it quotes over its words, as the composer held them)
  col.show(fn() { !(row.quotes)().is_empty() }, fn(q) {
    quotes_node(q, src, here, row.quotes, row.attachments, true, width, row.quotes_at, said=fn(i, card) {
      match card {
        Some(c) => quotes[@sfbase.quote_key(i)] = c
        None => quotes.remove(@sfbase.quote_key(i))
      }
      say(place())
    }, landed=fn(k, l) {
      match l {
        Some(l) => files[k] = l
        None => files.remove(k) |> ignore
      }
      say(place())
    })
  })
  // (its files, as the composer held them, and what of them still goes up)
  col.show(fn() { !(row.files)().is_empty() }, fn(fs) {
    message_files_node(fs, src, here, row.files, true, at=row.files_at, by=fn() {
      let ts = (row.ts)()
      if ts == "" { None } else { Some((@sf.t("web-main.chat.you"), "person", ts)) }
    }, landed=fn(k, l) {
      match l {
        Some(l) => files[k] = l
        None => files.remove(k) |> ignore
      }
      say(place())
    })
  })
  col.each(fn() { (row.uploads)().mapi(fn(i, _) { i }) }, fn(i) { i }, fn(slot, i) {
    let i = @signals.untracked(fn() { i.get() })
    @sf.file_card_node(slot, fn() {
      let (name, size, sent) = (row.uploads)().get(i).unwrap_or(("", 0, 0))
      let failed = (row.failed)()
      @sf.file_card_info(name, size.to_double(), pending=failed == "", sent=Some(sent.to_double()), error=failed)
    })
    |> ignore
  })
  // (its words in their bubble, where it has any)
  col.show(fn() { (row.text)() != "" }, fn(b) {
    b
    .max_width(By(fn() { Some(composer_words_width(width()) + 2.0 * bubble_side) }))
    .padding(Is((bubble_side, bubble_in_y, bubble_side, bubble_in_y)))
    .radius(By(fn() { @ui.tree_theme().corner(Xl2) }))
    .ground(By(fn() { @ui.tree_theme().color(Neutral) }))
    |> ignore
    // (picked as the chat's, said before its words are made: pick_node.mbt; the viewer's own, by its name in the chat)
    pick_row_node(col, b, fn() {
      let h = here()
      guard h.list is Some(_) else { return None }
      let seq = (row.seq)()
      Some({
        key: (row.key)(),
        ts: (row.ts)(),
        author: @sf.t("web-main.chat.you"),
        role: "person",
        words: (row.text)(),
        share: if seq >= 0.0 { h.view.thread.map(fn(thread) { fn() { open_publish(src, here_ref(h), thread, turn=Some(seq)) } }) } else { None },
        link: if seq >= 0.0 { @sfbase.message_link(h.station, h.session, seq) } else { "" },
      })
    })
    let words = person_words_node(b, row.text, row.words, fn() { marked_of(here(), (row.ts)()) }, row.linked)
    text.val = Some((b, words))
    say(place())
    b.owns(fn() {
      match text.val {
        Some((now, _)) if physical_equal(now, b) => {
          text.val = None
          say(place())
        }
        _ => ()
      }
    })
    |> ignore
  })
  // (what goes under it comes in with the words sent to it, after they have set off: flight_node.mbt)
  col.show(row.foot_shown, fn(f) {
    f.alpha(By(fn() { @sfbase.send_row_arrived(f, here().station + ":" + here().session, (row.key)()) })) |> ignore
    (row.foot)(f)
  })
}

///|
/// The viewer's own message whose parts are all nodes (mine_message's): its row (mine_row_node), under it that its agents
/// have yet to take it, or its time (none where their next message soon after says it under that one). `key` its row's in
/// its list (Entry::id, or the key it was sent as from here), its message's by default.
fn mine_message_node(
  col : @view.View,
  src : Source,
  here : () -> MessageHere,
  m : () -> Message,
  width : () -> Double,
  tips : @sf.TipLayer?,
  key? : () -> String,
) -> Unit {
  mine_row_node(col, src, here, {
    place: fn() { message_place(m()) },
    text: fn() { m().text },
    words: fn() { m().words },
    quotes: fn() { m().quotes },
    files: fn() { beside_quotes(m().quotes, m().attachments) },
    files_at: fn() { message_place(m()) + "/f" },
    attachments: fn() { m().attachments },
    quotes_at: fn() { message_place(m()) },
    uploads: fn() { [] },
    failed: fn() { "" },
    ts: fn() { m().ts },
    seq: fn() { m().seq },
    key: key.unwrap_or(fn() { "m:" + m().ts }),
    linked: fn(href) { m().linked(href).map(fn(l) { l.title }) },
    foot_shown: fn() { !m().followed },
    foot: fn(f) {
      f.pick(fn() {
        let now = m()
        if now.blocked is Some(b) && b.state != "installed" {
          3
        } else if now.waiting {
          1
        } else {
          2
        }
      }, fn(foot, which) {
        match which {
          // (the runtime it waits for, under it)
          3 =>
            blocked_line_node(foot, src, fn() { here().station }, fn() {
              m().blocked.unwrap_or({ runtime: "", state: "", title: "", note: "", action: "", percent: None, detail: "" })
            })
          1 => {
            foot.row(Is(true)).gap(Is(5.0)).lines_up(Is(Some(Middle))) |> ignore
            @sf.spinner_node(foot, size=waiting_spin) |> ignore
            @sf.words_node(foot, fn() { @sf.t("web-main.chat.waitingAgent") }, fn() { msg_time }) |> ignore
          }
          2 => {
            @sfbase.send_time_node(foot, fn() { here().station + ":" + here().session }, key.unwrap_or(fn() { "m:" + m().ts }))
            message_time_node(foot, fn() { m().time }, tips)
          }
          _ => ()
        }
      })
    },
  }, width)
}

///|
/// What the viewer sent not in the chat yet whose parts are all nodes (outbox_row's, but one not sent): its row
/// (mine_row_node, by the outbox entry's place), under it its time once the station has it, else 正在发送 (or why it waits)
/// with how far its files have gone once it has been on its way a while (sending_shows_ms from when its row was made);
/// nothing where the next soon after says it.
fn outbox_node(
  col : @view.View,
  src : Source,
  here : () -> MessageHere,
  o : () -> Outgoing,
  width : () -> Double,
  tips : @sf.TipLayer?,
  key? : () -> String,
) -> Unit {
  mine_row_node(col, src, here, {
    place: fn() { "o:" + o().id },
    text: fn() { o().text },
    words: fn() { o().words },
    quotes: fn() { o().quotes },
    files: fn() { beside_quotes(o().quotes, o().attachments) },
    files_at: fn() { "o:" + o().id + "/f" },
    attachments: fn() { o().attachments },
    quotes_at: fn() { "o:" + o().id },
    uploads: fn() { o().uploads },
    failed: fn() { if o().state == "failed" { if o().error != "" { o().error } else { @sf.t("web-main.chat.notSent") } } else { "" } },
    ts: fn() { "" },
    seq: fn() { -1.0 },
    // (its row's in the list: the same as the station gives it its own id)
    key: key.unwrap_or(fn() { "o:" + o().id }),
    linked: fn(_) { None },
    foot_shown: fn() { o().state == "failed" || !o().followed },
    foot: fn(f) {
      let shows = @signals.signal(false, same=fn(a, b) { a == b })
      f.at_moment(f.cause_at() + sending_shows_ms, fn() { shows.set(true) }) |> ignore
      f.pick(fn() {
        let now = o()
        if now.state == "failed" { 3 } else if now.state == "sent" { 2 } else { 1 }
      }, fn(foot, which) {
        match which {
          3 => outbox_unsent_node(foot, src, here, o, tips)
          1 => {
            // (its room kept from the first, nothing of it seen till it has been on its way a while: outbox_row's)
            foot.row(Is(true)).gap(Is(5.0)).lines_up(Is(Some(Middle))).alpha(By(fn() { if shows.get() { 1.0 } else { 0.0 } })) |> ignore
            @sf.spinner_node(foot, size=waiting_spin) |> ignore
            @sf.words_node(foot, fn() { if o().waits != "" { o().waits } else { @sf.t("web-main.chat.sending") } }, fn() {
              msg_time
            })
            |> ignore
          }
          2 => {
            @sfbase.send_time_node(foot, fn() { here().station + ":" + here().session }, key.unwrap_or(fn() { "o:" + o().id }))
            message_time_node(foot, fn() { o().time }, tips)
          }
          _ => ()
        }
      })
    },
  }, width)
}

///|
/// What was sent from here and did not go, under it (outbox_unsent's): 未发送 in the red (why in its tip), then
/// sending it again (refused as it is: its words back in the composer, 编辑) and dropping it, each a quiet button of its
/// own, busy while the core does it, its failure said in its tip.
fn outbox_unsent_node(
  foot : @view.View,
  src : Source,
  here : () -> MessageHere,
  o : () -> Outgoing,
  tips : @sf.TipLayer?,
) -> Unit {
  let on = fn() { [("station", here().station), ("id", o().id)] }
  let retrying = fn() { core_doing(src, ["chat.retry"], on()) }
  let dropping = fn() { core_doing(src, ["chat.discard"], on()) }
  let busy = fn() { retrying() || dropping() }
  let locked = fn() { here().view.offline }
  foot.row(Is(true)).padding(Is((0.0, 4.0, 0.0, 0.0))).gap(Is(1.0)).lines_up(Is(Some(Middle))) |> ignore
  foot.box(fn(note) {
    note.row(Is(true)).padding(Is((0.0, 0.0, 6.0, 0.0))).gap(Is(4.0)).lines_up(Is(Some(Middle))) |> ignore
    @sf.icon_node(note, "info", unsent_icon, By(fn() { @sf.theme().p.red })) |> ignore
    @sf.words_node(note, fn() {
      let now = o()
      if now.final && now.error != "" {
        @sf.t("web-main.draft.notSent", args=[("error", now.error)])
      } else {
        @sf.t("web-main.chat.unsent")
      }
    }, fn() { unsent_words })
    |> ignore
    match tips {
      Some(layer) =>
        @sf.tip_node(layer, note, fn() {
          let now = o()
          if now.error != "" {
            @sf.t("web-main.draft.notSent", args=[("error", now.error)])
          } else {
            @sf.t("web-main.chat.notSent")
          }
        }, within=true)
        |> ignore
      None => ()
    }
  })
  |> ignore
  foot.pick(fn() { o().final }, fn(first, refused) {
    first.row(Is(true)) |> ignore
    if refused {
      // (refused as it is (a file this station does not have): its words back in the composer, to be sent anew)
      unsent_button_node(first, "edit", fn() { @sf.t("common.edit") }, fn() { !locked() && !busy() }, fn() { false }, fn() {
        None
      }, tips, fn() {
        let h = here()
        let now = o()
        let w = writing(src, h.station + ":" + h.session)
        writing_text(src, w, now.text)
        outbox_call(src, h, "chat.discard", now.id)
      })
    } else {
      unsent_button_node(first, "retry", fn() { @sf.t("common.retry") }, fn() { !locked() && !busy() }, retrying, fn() {
        core_failed(src, ["chat.retry"], on())
      }, tips, fn() { outbox_call(src, here(), "chat.retry", o().id) })
    }
  })
  unsent_button_node(foot, "trash", fn() { @sf.t("common.delete") }, fn() { !busy() }, dropping, fn() {
    core_failed(src, ["chat.discard"], on())
  }, tips, fn() { outbox_call(src, here(), "chat.discard", o().id) })
}

///|
/// A quiet button under what did not go (unsent_button's): its mark (a spinner while busy, the red info where it
/// failed) and its word, the hover ground under the pointer, at 55% while it may not be pressed; read out a button.
fn unsent_button_node(
  parent : @view.View,
  icon : String,
  label : () -> String,
  enabled : () -> Bool,
  busy : () -> Bool,
  failed : () -> String?,
  tips : @sf.TipLayer?,
  press : () -> Unit,
) -> Unit {
  parent.box(fn(b) {
    let hot = fn() { enabled() && @sf.pointer_rests() && b.pointed() }
    b
    .row(Is(true))
    .padding(Is((6.0, 2.0, 6.0, 2.0)))
    .gap(Is(4.0))
    .radius(By(fn() { @ui.tree_theme().corner(Md) }))
    .lines_up(Is(Some(Middle)))
    .ground(By(fn() { if hot() { @ui.tree_theme().color(Hover) } else { 0L } }))
    .alpha(By(fn() { if enabled() { 1.0 } else { 0.55 } }))
    .says(By(fn() { Some(@view.said(Button, label=label())) }))
    |> ignore
    @sf.presses_node(b, fn() { if enabled() { press() } }, on=enabled)
    b.pick(fn() { if busy() { 1 } else if failed() is Some(_) { 2 } else { 0 } }, fn(mark, which) {
      match which {
        1 => @sf.spinner_node(mark, size=waiting_spin) |> ignore
        2 => @sf.icon_node(mark, "info", unsent_icon, By(fn() { @sf.theme().p.red })) |> ignore
        _ => @sf.icon_node(mark, icon, unsent_icon, By(fn() { if hot() { @sf.theme().p.text } else { @sf.theme().p.muted } })) |> ignore
      }
    })
    @sf.words_node(b, label, fn() { if hot() { unsent_label_hot } else { unsent_label } }) |> ignore
    match tips {
      Some(layer) => @sf.tip_node(layer, b, fn() { failed().unwrap_or("") }) |> ignore
      None => ()
    }
  })
  |> ignore
}

///|
/// How message `m` is drawn whole by nodes now (message_made_whole's), for what draws or checks it.
pub fn message_made_whole_now(m : Message) -> Int {
  message_made_whole(m)
}

///|
/// Message `m` made whole by nodes in `row` (message_made_whole_now says it can be): the viewer's own, or someone
/// else's; `width` the pane's.
pub fn message_row_node(row : @view.View, src : Source, here : () -> MessageHere, m : () -> Message, width : () -> Double) -> Unit {
  let whole = message_made_whole(@signals.untracked(m))
  if whole == 2 {
    mine_message_node(row, src, here, m, width, None)
  } else if whole == 5 {
    row.box(fn(own) { notice_node(own, src, here, m) }) |> ignore
  } else {
    // (in a box of its own: what lies over it (its picture) laid over it, not over the room round it in `row`)
    row.box(fn(own) { others_message_node(own, src, here, m, None) }) |> ignore
  }
}

///|
/// What a message quotes (quotes'), each a card (the library's quote_card_node, as the composer's): 4 apart, at the
/// row's start, or its end as wide as what the viewer sent may be (`mine`, `width` the pane's); pressed, the passage
/// it quotes gone to where the chat's list can. Each by its place, following the message; each card told `said` as it is
/// made and let go (by its place among them). A quote's own picture (the file of the message's `files` it names: a
/// preview mark's screenshot) in its card, as a message's file is (message_files_node: `at` where in the chat the
/// message is), its corner concentric with the card's, told `landed` by its key (quote_picture_key) as what is sent
/// lands there.
fn quotes_node(
  col : @view.View,
  src : Source,
  here : () -> MessageHere,
  quotes : () -> Array[Quote],
  files : () -> Array[Attachment],
  mine : Bool,
  width : () -> Double,
  at : () -> String,
  said? : (Int, @sf.QuoteCardNode?) -> Unit = fn(_, _) {  },
  landed? : (String, @sfbase.FileLandingNode?) -> Unit = fn(_, _) {  },
) -> Unit {
  col.box(fn(qs) {
    qs.gap(Is(4.0)).lines_up(Is(Some(if mine { End } else { Start }))) |> ignore
    if mine {
      qs.max_width(By(fn() { Some(composer_words_width(width()) + 2.0 * bubble_side) })) |> ignore
    }
    qs.each(fn() { quotes().mapi(fn(i, _) { i }) }, fn(i) { i }, fn(slot, i) {
      let i = @signals.untracked(fn() { i.get() })
      let q = fn() -> Quote {
        match quotes().get(i) {
          Some(q) => q
          None => { author: "", text: "", comment: "", ts: "", role: "", file: "" }
        }
      }
      let jump = fn() {
        let now = here()
        let quoted = q()
        match (now.go, now.view.messages.iter().find_first(fn(x) { quoted.ts != "" && x.ts == quoted.ts })) {
          (Some(go), Some(x)) => go(x.seq, quoted.text)
          _ => ()
        }
      }
      // (as wide as the card may be, not as its words are: what the viewer sends may be (the pane's, as the composer
      // sets it), else the message's column; less the card's own room)
      // (by how wide the column is laid out, in the same layout: Roomed)
      let quote_picture_most = fn(col_w : Double) {
        if mine {
          Some(@sf.quote_picture_room(composer_words_width(width()) + 2.0 * bubble_side))
        } else if col_w >= 0.0 {
          Some(@sf.quote_picture_room(col_w))
        } else {
          None
        }
      }
      let card = @sf.quote_card_node(
        slot,
        fn() { q().author },
        fn() { q().text },
        role=fn() { q().role },
        comment=fn() { q().comment },
        jump?=if @signals.untracked(fn() { q().ts != "" && here().go is Some(_) }) { Some(jump) } else { None },
        // (shown while the message has the file it names: what was sent from here has it once the core takes it over)
        picture_shown=fn() { quote_file(q(), files()) is Some(_) },
        // (a copy's room for its picture: the box media_file_node lays it out in, as image_box makes it and as wide as
        // the card lets it be, nothing of it read back)
        picture_box=fn(room) {
          room.box(fn(b) {
            let file = fn() { quote_file(q(), files()) }
            // A non-media file keeps the quote's existing placeholder; video uses its own cover's limits.
            let kind = fn(a : Attachment) { if file_kind(a.name) == "video" { "video" } else { "image" } }
            // (by the column's width where it is the column's card; a copy of the card flown elsewhere (flight's) is held
            // by no column: as wide as its picture, within what holds it)
            let held = room.tree.holds(col.id(), room.id())
            let most = fn(col_w : Double) {
              match (file(), quote_picture_most(col_w)) {
                (Some(a), Some(w)) => media_box_width(a, kind(a), Some(w), false)
                (Some(a), None) => media_box_width(a, kind(a), None, false)
                _ => 0.0
              }
            }
            let most_live = fn() -> @view.Live[Double?] {
              if held { Roomed(col, fn(w, _) { Some(most(w)) }) } else { By(fn() { Some(most(-1.0)) }) }
            }
            b.width(most_live()).max_width_within(most_live())
            .aspect(By(fn() { file().map(fn(a) { media_box_ratio(a, kind(a)) }).unwrap_or(0.0) }))
            |> ignore
          })
          |> ignore
        },
        picture=fn(pv) {
          // The local file can acquire an upload key before its previous node is released. Both occupy this
          // quote's one picture slot; releasing the previous key must not erase the new one's landing.
          let current : Ref[String?] = Ref(None)
          let own = fn() {
            match quote_file(q(), files()) {
              Some(a) => [a]
              None => []
            }
          }
          let most = quote_picture_most
          message_files_node(pv, src, here, own, false, at=fn() { at() + "/q:" + i.to_string() }, corner=@sf.quote_picture_corner, most~, landed=fn(k, l) {
            match l {
              Some(_) => {
                current.val = Some(k)
                landed(@sfbase.quote_picture_key(i), l)
              }
              None if current.val == Some(k) => {
                current.val = None
                landed(@sfbase.quote_picture_key(i), None)
              }
              _ => ()
            }
          })
        },
      )
      said(i, Some(card))
      slot.owns(fn() { said(i, None) }) |> ignore
    })
  })
  |> ignore
}

///|
/// Where what the viewer sent lands in their message's row (mine_row_node), as its parts are made: what the row is
/// found by (`anchor`: its words' bubble, else its first quote's card, else its first file), its bubble and words where
/// it has words, its files by their keys (file_key) and its quotes' cards by theirs (quote_key); what is sent flies
/// to them (flight's), read as laid out and drawn (View::laid_window_now). Said again as a part comes or goes.
pub(all) struct MineLanding {
  anchor : @view.View
  text : (@view.View, @view.View)?
  files : Map[String, @sfbase.FileLandingNode]
  quotes : Map[String, @sf.QuoteCardNode]
}

///|
/// The rows of what the viewer sent that show, by their place (message_place: the outbox entry's while it is one, then
/// the message's): their landings, let go with them.
// kept across runs: each let go as its row is; message_reset empties it
let mine_landings : @sf.LiveMap[String, MineLanding] = @sf.LiveMap::new()

///|
/// Where what was sent to place `place` lands, while its row shows (mine_landings), followed: what reads it told as
/// one is said or let go.
pub fn mine_landing(place : String) -> MineLanding? {
  mine_landings.get(place)
}

///|
/// A message's way out of an avatar in its chat's list (message_row's `emits`): the list's and its key, while it comes
/// (or came) out of one, or comes in a glyph at a time with none to come out of; None else.
fn emits_here(here : MessageHere, m : Message) -> (Emits, String)? {
  match here.list {
    Some(l) if emit_goes(l.emits, m.seq) || emit_words_only(l.emits, m.seq) => Some((l.emits, l.rk))
    _ => None
  }
}

///|
/// Node `v` said as where what a message flies between is (emit_places), by `key` as it is now (None: not one of them),
/// as long as it lives; `dy` below where it is.
fn emit_place_node(v : @view.View, key : () -> String?, dy? : Double = 0.0) -> Unit {
  let at = fn() -> (Double, Double, Double, Double)? {
    v.drawn_window_told().map(fn(r) { (r.0, r.1 + dy, r.2, r.3) })
  }
  let room = fn() { v.list_room().map(fn(r) { r.height }) }
  let said = Ref("")
  let unsay = fn() {
    match @sfbase.emit_places.get(said.val) {
      Some(f) if physical_equal(f, at) => @sfbase.emit_places.remove(said.val)
      _ => ()
    }
    match @sfbase.emit_rooms.get(said.val) {
      Some(f) if physical_equal(f, room) => @sfbase.emit_rooms.remove(said.val)
      _ => ()
    }
    said.val = ""
  }
  v.owns(unsay) |> ignore
  v.reacts(key, fn(k) {
    unsay()
    match k {
      Some(k) => {
        said.val = k
        @sfbase.emit_places[k] = at
        @sfbase.emit_rooms[k] = room
      }
      None => ()
    }
  })
}

///|
/// Whether message `m` offers its words, link and turn's picture of itself (others_message's `share`): in a chat's list
/// with its thread, where a mouse is what it is used with.
fn message_shares(here : MessageHere, m : Message) -> Bool {
  here.list is Some(_) && here.view.thread is Some(_) && m.seq >= 0.0 && !@sf.more_held()
}

///|
/// Message `m`'s turn shared as a picture (others_message's `share`).
fn message_share_of(src : Source, here : MessageHere, m : Message) -> () -> Unit {
  let thread = here.view.thread.unwrap_or(0.0)
  fn() { open_publish(src, here_ref(here), thread, turn=Some(m.seq)) }
}

///|
/// Message `m`'s own items (its ⋯'s menu, its right click's): sfbase's message_items.
fn message_items_of(src : Source, here : MessageHere, m : Message) -> Array[@sf.MenuItem?] {
  @sfbase.message_menu_items(@sfbase.message_link(here.station, here.session, m.seq), m.text, message_share_of(src, here, m))
}

///|
/// The runtime what the viewer sent waits for, under it (blocked_line's), in `foot`, `b` as it is now: installing, its
/// spinner and how far; missing or failed, a red mark; its title, its note where there is nothing to do, else what to
/// do, pressed doing it (`software.update`), underlined under the pointer; faded while that is under way.
fn blocked_line_node(foot : @view.View, src : Source, station : () -> String, b : () -> Install) -> Unit {
  let stuck = fn() { b().state == "missing" || b().state == "failed" }
  let busy = fn() { install_busy(src, station(), b()) }
  let acts = fn() { b().action != "" && !busy() }
  let words = fn() { if stuck() { blocked_words_stuck } else { blocked_words } }
  foot
  .row(Is(true))
  .gap(Is(4.0))
  .lines_up(Is(Some(Middle)))
  .alpha(By(fn() { if busy() { 0.6 } else { 1.0 } }))
  .says(By(fn() { if b().action != "" { Some(@view.said(Button, label=b().title + " · " + b().action)) } else { None } }))
  |> ignore
  @sf.presses_node(foot, on=acts, fn() { install_runtime(src, station(), b()) })
  foot.pick(fn() { if b().state == "installing" { 1 } else if stuck() { 2 } else { 0 } }, fn(lead, which) {
    match which {
      1 => @sf.spinner_node(lead, size=waiting_spin) |> ignore
      2 => {
        lead.width(Is(Some(12.0))).height(Is(Some(12.0))).radius(Is(6.0)).lines_up(Is(Some(Middle))).lies_along(Is(Middle)).ground(By(fn() {
          @ui.tree_theme().color(Danger)
        }))
        |> ignore
        @sf.words_node(lead, fn() { "!" }, fn() { failed_bang }) |> ignore
      }
      _ => ()
    }
  })
  @sf.words_node(foot, fn() {
    let now = b()
    match now.percent {
      Some(p) if now.state == "installing" => now.title + " " + p.to_int().to_string() + "%"
      _ => now.title
    }
  }, words)
  |> ignore
  foot.show(fn() { b().note != "" && b().action == "" }, fn(n) {
    n.row(Is(true)).gap(Is(4.0)) |> ignore
    @sf.words_node(n, fn() { "·" }, fn() { blocked_dot }) |> ignore
    @sf.words_node(n, fn() { b().note }, words) |> ignore
  })
  foot.show(fn() { b().action != "" }, fn(a) {
    a.row(Is(true)).gap(Is(4.0)) |> ignore
    @sf.words_node(a, fn() { "·" }, fn() { blocked_dot }) |> ignore
    a.box(fn(w) {
      w
      .words_runs(By(fn() { [@ui.span(b().action, underline=acts() && foot.pointed_in())] }))
      .words_look(By(fn() { @ui.style_words(blocked_act) }))
      .ink(By(fn() { @ui.style_ink(blocked_act) }))
      |> ignore
    })
    |> ignore
  })
}

///|
/// The file of message `m` its words place by `name` (prose_with_files'): one of its files beside what it quotes.
fn placed_of(m : Message, name : String) -> Attachment? {
  guard m.placed.contains(name) else { return None }
  beside_quotes(m.quotes, m.attachments).iter().find_first(fn(a) { a.name == name })
}

///|
/// A visualization message `m` places, file `a` (prose_with_files'), in `v`: its page where its words place it
/// (sfbase's viz_file_node), one that cannot be read as its file.
fn viz_placed_node(v : @view.View, src : Source, here : () -> MessageHere, m : () -> Message, a : Attachment) -> Unit {
  @sfbase.viz_file_node(
    v,
    src,
    fn() { here().station },
    fn() { here().session },
    fn() { owner_of(here(), a) },
    fn() { m().ts },
    fn() { a },
    fn(f) {
      message_files_node(f, src, here, fn() { [a] }, false, at=fn() { message_place(m()) + "/f" }, by=fn() {
        Some((m().by.name, if m().author_kind == "person" { "person" } else { "agent" }, m().ts))
      })
    },
    fn() { @sf.theme().p.subtle },
  )
}

///|
/// A ```mermaid block of message `m`'s words (prose_with_files'), `code` as it is, in `v`: its chart (sfbase's
/// viz_mermaid_node).
fn mermaid_placed_node(v : @view.View, src : Source, here : () -> MessageHere, m : () -> Message, code : () -> String) -> Unit {
  ignore(m)
  @sfbase.viz_mermaid_node(v, src, fn() { here().station }, code, fn() { @sf.theme().p.subtle })
}
