// A chat's messages on the desktop (still.fail web/src/Chat.tsx ChatShown, ChatRows, useMessageList, ToLatest, ToAsk;
// Chat.css.ts chatMessages, chatToBottom, chatToAsk; styles/session.css.ts chatList): its rows in the column 760 wide
// at most in the pane's middle, running on under the composer; following its end, the pages before and after brought
// in near its edges, put in place once (the unread line, where it was left, where the core opened it), what is read and
// where the reader is told the core: all of that as the phone's list has it too (sfbase's chat_list.mbt: list_frame
// before the rows are drawn, list_after once they are). What comes in does so at once (list_turns.mbt): a message
// eases in, an agent's comes out of its activity's picture (emit.mbt), the viewer's own flies in from the composer the
// frame it is sent (flight.mbt), existing messages show at once. Over it, the way to its end
// (⌘↓) and to what waits to be decided.

///|
/// Chat `r`'s list (its view `v`, `read` its entries), in its pane; `room` what the composer takes of the pane's foot,
/// `top` what the frame's bar takes of its top (and `bar` where the bar ends, `lead` how far under the top the unread
/// line is put). Its own width decides how it is laid out: narrow (700 or less: the web's phone widths and its mobile
/// page), 16 in from its sides, 20 between messages, each picture at its head's start (inlineHeads); wider, in the
/// column 760 wide at most in its middle, 28 apart, the pictures out in the margin.
pub fn chat_list(
  c : @ui.Ctx,
  src : Source,
  r : ChatRef,
  v : ChatView,
  read : Array[Entry],
  room : Double,
  core : Core,
  top? : Double = list_top,
  lead? : Double = unread_lead,
  bar? : Double = bar_foot,
  foot? : Double = list_foot,
  slotted? : Bool = false,
) -> Unit {
  let key = list_key(r)
  // (laid out by the width it is at, or on the page's way otherwise: laid_w)
  let (lay_w, held, laid_at) = laid_w(c, key)
  let narrow = lay_w <= chat_narrow_w
  let list_top = top
  let list_gap = if narrow { list_gap_narrow } else { list_gap }
  let draft = r.station + ":" + r.session
  // what a message's menu left to do (menus.mbt)
  menus_frame(c)
  // its pictures that could not be had for want of its station asked again: as the chat comes into view (its list
  // shown neither in the build before nor yet in this one: Reading's `was_shown`, `shown`), and as its station is
  // reached again
  let reading = reading_of(r.station + "\u{1}" + r.session)
  if !reading.shown && !reading.was_shown {
    src.images.again(r.station)
  }
  src.images.seen(r.station, !v.offline)
  // the way the composer's ground under the rows last set out on, as it declared it (opened, a line more, let go by
  // words sent, each from the moment it came: composer's reshape), the room the list keeps under them with it as
  // drawn: that way the Foot row's change and the list's while it has not ended, as the list is told, so that what else
  // changes the rows' heights then (a row closing over it) goes with it, one way (list_size.mbt; rows_steady.mbt holds
  // it); not a room the page gave otherwise (a new chat's, the least a phone's foot keeps); nor while words sent hold
  // its room, which is theirs then, kept where it was till they let go of it and down on their flight's clock with
  // their row from then (flight_lets_go, sfbase's shown_rows), its ground's ways then none of the list's
  let foot_way = if (room - composer_room(c, draft)).abs() < 0.01 {
    composer_way_for_list(c, draft)
  } else {
    None
  }
  // (on that way at this moment, till its declared end)
  let on_foot_way = match foot_way {
    Some((at, ms)) => c.moment() < at + ms
    None => false
  }
  let lf = list_frame(
    c,
    r,
    v,
    read,
    key~,
    draft~,
    rise_ms=@sf.enter_ms,
    top=list_top,
    in_front=app_in_front(),
    // (the way it was last held on and the width it was kept at: each row another version as a way sets off, from then;
    // not as the window or an edge dragged makes the pane narrower or wider, whatever the width it is laid out at
    // then, narrow or not: their rows there at once, laid out anew in that frame, no motion of their own)
    laid=laid_at_w(key, held, lay_w),
    laid_at~,
    foot_way?,
  )
  let (rd, rk, em, turns, list, keys, flight) = (lf.rd, lf.rk, lf.em, lf.turns, lf.list, lf.keys, lf.flight)
  let n = list.length()
  // a message gone to, flashing (a notification's): a ground under its row coming in and going
  let lit = (rd.flash, flash_of(c, rd, rd.flash))
  flashing_now.val = lit
  // the room agents' lines left, less what has come in since (under the rows, over the composer's room)

  // while something waits to be decided its bell may float over the list's end (to_ask): the end keeps clear of it,
  // its last row as far over the bell as it is over the composer's room without it, not under it (the time, 正在发送
  // under the viewer's own message, at the column's end where the bell is); not for one at the end itself (the core's
  // `askClear`), which shows whenever the end does, no bell over it
  let ask_clear = if @sfbase.ask_clears(v) { float_lift + float_side } else { 0.0 }
  // (the composer's room as it comes to stand once words sent let go of it: the list takes it there on its way)
  let let_go = @sfbase.sent_let_go(rd, flight)
  let foot_room = composer_foot_room(c, draft, room, let_go~)
  let side = row_side(lay_w)
  // the room over row `i`: none at the list's ends, a little over a message joined to the one before, else the gap
  let top_at = fn(i : Int) -> Double {
    let e = list[i]
    let joined = match e {
      Said(m) => m.joined
      Out(o) => o.joined
      _ => false
    }
    if e is Top || e is Foot || (i > 0 && list[i - 1] is Top) {
      0.0
    } else if joined {
      joined_gap
    } else {
      list_gap
    }
  }
  // the message gone to lit whole, or only what a quote that led there quoted, where its words have it (passage_lit)
  let whole = flash_whole(c, rd)
  // on the page's way to another width, in the column's middle as it is at each: laid out as at the narrower of where it
  // set off and where it goes, kept so till it is there (laid_w)
  let way = @sfbase.page_way
  let frame_w = c.width
  let list_w = lay_w
  let gutter = side
  // (and what the chat says: what came on its way is shown as it comes, the rows built anew for it)
  let rows_key = way.id +
    " " +
    [list_w, c.height, list_top, foot_room, foot, ask_clear, bar, room, lit.1].map(fn(x) { x.to_string() }).join(" ") +
    // (and what else of the frame its rows are built from: the composer's room on its way, the message lit, words
    // sent flying)
    " \{on_foot_way} \{lit.0} \{whole} \{flight is Some(_)}" +
    " " +
    n.to_string() +
    " " +
    rows_said(key, v, read).to_string()
  let list_style = if held { chat_list_box.then(@ui.style(w=Fixed(list_w))) } else { chat_list_box }
  let list_box_id = c.id("search-pane/" + key)
  let list_box = c.box(style=list_style, id=list_box_id, tx=list_shift(key, frame_w, list_w), fn() {
    c.sized(list_w, c.height, fn() {
    let rows = fn() {
    // a notice pressed to open or shut: held where it is (system_notice's notice_holds; the list by its id here, where
    // it is built)
    if notice_holds.length() > 0 {
      for i, e in list {
        match e {
          Said(m) if notice_holds.contains(m.ts) => {
            notice_holds.remove(m.ts)
            c.list_hold_row(key, i)
          }
          _ => ()
        }
      }
    }
    c.list(
      key,
      n,
      chat_row_est,
      fn(i) {
        let e = list[i]
        let top = top_at(i)
        let mk = key + "\u{1}" + keys[i]
        match e {
          Top => c.box(style=@ui.style(h=Fixed(list_top)), fn() {  }) |> ignore
          Foot => {
            // going with the composer's ground on its declared way: as drawn, its own on the rows' way, the list
            // closing only what was off as its cause came (Ctx::row_way); else where it comes to stand, on the list's
            // way
            if on_foot_way {
              ignore(c.row_way())
            }
            let h = if on_foot_way { room } else { foot_room }
            c.box(style=@ui.style(h=Fixed(h + foot + ask_clear)), fn() {  }) |> ignore
          }
          Working(a) => {
            // coming in, it comes where it is as its room opens, and leaves where it is, as any row
            // (ListRows::enter, leave); its turn over, it stays while its messages come out of its avatar (chat_tick)
            rd.fresh.remove(keys[i]) |> ignore
            let leaving = rd.rows.went(keys[i]) is Some(_)
            let here = here_of(r, v, rk, turns, em, None, core, inline=narrow, gutter~)
            let came = rd.rows.came(keys[i])
            // (a turn begun and over between two ticks, nothing of it coming out: no room, unseen, chat_tick)
            let unseen = rd.answered_unseen.contains(a.key) ||
              (match rd.linger.get(a.key) {
                Some(l) => l.unseen
                None => false
              })
            let ri = if unseen {
              c.box(style=@ui.style(h=S0, clip=true, opacity=O0), fn() {
                activity_row(c, src, here, a, em, rk, leaving, came)
              })
            } else {
              row_box(c, side, top, fn() { activity_row(c, src, here, a, em, rk, leaving, came) })
            }
            @motion.keyed(c, ri, mk, by=makes_way(lf, keys[i]))
            rd.rows.enter(c, ri, keys[i], lead=top, grown=false)
            rd.rows.leave(c, ri, keys[i], lead=top)
          }
          _ => {
            // the row words sent go to: its bubble flies there from the composer
            let flies = flight_takes(draft, keys[i])
            match flight {
              Some(f) if flies => flight_placed(c, f)
              _ => ()
            }
            // (or the row words sent before those went to, still on their way as those were sent: they go on)
            let flying = if flies { flight } else { @sfbase.flight_to(draft, keys[i]) }
            let here = here_of(r, v, rk, turns, em, flying, core, inline=narrow, gutter~)
            // what it moves for where it shows: what was sent from here not in the chat yet, the newest that came in
            // over it; any other row, the newest that came in over the rows at the end as the list followed it
            let cause = match e {
              Out(_) => makes_way(lf, keys[i])
              _ => came_over(lf)
            }
            // gone to, lit whole: a band across the list from edge to edge, half the room to the rows over and under;
            // its menu open (right clicked, its ⋯), the same band in the pointer's ground, easing in and out as a
            // row's under the pointer does
            let under = if i + 1 < n { top_at(i + 1) / 2.0 } else { 0.0 }
            let (band, band_by) = match e {
              // (a notice lights its own pill: system_notice)
              Said(m) if whole && m.ts == lit.0 && lit.1 > 0.0 && !m.system => (Some((lit.1, top / 2.0, under)), None)
              Said(m) => {
                let on = @sfbase.message_menu_on("m:" + m.ts)
                let a = @motion.told(c, "msg-menu/" + m.ts, if on { 1.0 } else { 0.0 }, spec=@sf.nav_fade)
                if on || !a.over(c) {
                  let hover = @sf.theme().p.hover
                  // (the last message's as far under it as over it: the list's foot under it, no row to meet)
                  (Some((1.0, top / 2.0, if under > 0.0 { under } else { top / 2.0 })), Some(fn() { @sf.alpha(hover, a.get(c)) }))
                } else {
                  (None, None)
                }
              }
              _ => (None, None)
            }
            let ri = row_box(c, side, top, lit=band, lit_by=band_by, fn() {
              // (where a message out of a picture comes in over it: emit.mbt; read as it changes, Emits::read)
              em.read()
              if keys[i] == em.out_key {
                @motion.measure(c, c.box(fn() {  }), "emit-out/" + rk + "/" + keys[i])
              }
              entry_row(c, src, here, e)
            })
            match flight {
              Some(_) if flies => {
                // flown in, it does not rise in as well
                rd.known[keys[i]] = true
                rd.fresh.remove(keys[i]) |> ignore
              }
              _ => ()
            }
            // where it is is where the rows before it end, as tall as each is now (Ctx::row_size): nothing of its own
            // moves it; what leaves the list goes in the middle of its room as it closes (Reading's `rows`: ListRows::leave)
            @motion.keyed(c, ri, mk, by=cause)
            rd.rows.leave(c, ri, keys[i], lead=top)
            // what comes into the list with no flight to bring it (words sent, a message out of a picture) comes where
            // it is as its room opens (ListRows::enter)
            let emitted = match e {
              Said(m) => emit_goes(em, m.seq)
              _ => false
            }
            rd.fresh.remove(keys[i]) |> ignore
            // (nor one words sent before the last still fly to: come in the middle of its room from then, what it
            // holds stepped there in that frame)
            if flying is None && !emitted {
              // (an agent's words come in a glyph at a time when there is no avatar to come out of: emit_words_only)
              let grown = match e {
                Said(m) => !emit_words_only(em, m.seq)
                _ => true
              }
              rd.rows.enter(c, ri, keys[i], lead=top, grown~)
            }
            // where it stands: its room what it leaves as a floor when it goes, as an agent's line's (act_rooms)
            if e is State(_, _, _) {
              rd.act_whole[keys[i]] = true
            }
          }
        }
      },
      stick_end=true,
      // what comes at the end while it follows is glided after, half a second after it was put in place, not while
      // words sent fly (they put the list in place), nor what came in over the rows at its end (at its end at once,
      // what is at the end staying where it shows: row_keys's `over`)
      // (what comes at its end while it is held there opens its room under what is in view, which goes up with it:
      // nothing to glide after)
      glide_on_growth=false,
      // (what came, went and changed: by its rows' keys, the list's own, mbui's ui/list_size.mbt)
      sized=rd.rows.sized(),
      // (short of the pane, its rows at its end by the composer: what comes pushes what is over it up from the first
      // message, never down till the pane is full and up from then: rows_steady.mbt)
      from_end=true,
      // (a card's field kept in view with the keyboard up: out from under the bar and the composer)
      clear_top=bar,
      clear_foot=foot_room + ask_clear,
    )
    |> ignore
    }
    // (its rows a part of their own: on a page's way, going on as they are (`rows_stay`); and through what is typed into
    // the composer beside them, the composer alone built for each word, mbui's typed_part)
    c.kept_part(c.id(key + "/rows"), rows_key, rows, read_out=true, rows_stay=held, typed_stays=true)
    let found_now = Ref(false)
    let la = list_after(
      c,
      src,
      r,
      v,
      lf,
      top=list_top,
      lead~,
      bar~,
      room~,
      finding=find_chat() == chat_key(r),
      on_found=fn(rd) {
        found_start(c, rd, find_chat() == rk)
        found_now.val = true
      },
      find_around~,
    )
    // gone to by a quote: what it quoted, low in the message, to the list's middle
    passage_centre(c, rd, key, "chat-list/" + key)
    // a search's first word (or the current occurrence) low in the message, to the middle
    if rd.found_centre && !found_now.val {
      let mut pick = rd.found_at
      for e in list {
        match e {
          Said(m) if m.ts == rd.found_at && m.mine && m.outgoing != "" => pick = "o:" + m.outgoing
          _ => ()
        }
      }
      found_centre(c, rd, key, list_box_id, pick, find_chat() == rk)
    }
    // the way to the newest: away from its end, or short of the chat's end
    let jump = la.away || v.newer
    rd.jump = jump
    to_latest(c, src, r, v, jump, room)
    // the ways into its outline (outline.mbt): its rail at its right where the page leaves it room, else a round button
    // over the way to the newest, with it; its keys
    let floated = outline_entries_of(c, src, r, v, key, list, lay_w, jump, bar, room)
    // what waits to be decided and does not show: a bell over the way to the end (and the outline's, over that)
    rd.ask = to_ask(c, r, v, la.ask_rows, la.info, if !jump { 0 } else if floated { 2 } else { 1 }, room)
    // the picture flying out of an activity to its message and back, over the list
    emit_flyer(c, rk, em, v, src, r)
    })
  })
  // (where it is, for what a quote led to to be put in its middle: passage_centre)
  @motion.measure(c, list_box, "chat-list/" + key)
  // (what of it the bar and the composer hide: its pictures, noted as its, go out from under them before they grow
  // into the viewer; under a bar of the page's nodes, in the page's slot: `slotted`)
  @sfbase.note_list(c, list_box, rk, bar, room, slot=if slotted { c.owner } else { 0 })
  // a new chat's list comes up out of the composer with its first words: drawn below its place by how far they have
  // to go, from where this frame lays their row out (flight.mbt flight_carry_shift)
  if flight_carried(lf.draft) {
    @motion.placed(c, list_box, fn() { @ui.look(dy=flight_carry_shift(c, lf.draft)) })
  }
}

///|
/// How many times what chat list `key` shows has changed: its view or its entries given otherwise.
fn rows_said(key : String, v : ChatView, read : Array[Entry]) -> Int {
  match rows_given.get(key) {
    Some((was_v, was_read, n)) if physical_equal(was_v, v) && physical_equal(was_read, read) => n
    Some((_, _, n)) => {
      rows_given[key] = (v, read, n + 1)
      n + 1
    }
    None => {
      rows_given[key] = (v, read, 0)
      0
    }
  }
}

///|
// kept across runs: only compared with what is given next, by each list's key
let rows_given : Map[String, (ChatView, Array[Entry], Int)] = Map([])

///|
/// A chat's messages to come while it is read the first time (the library's Waiting, in its bones): made-up messages
/// as its list draws them (row_box, message_row: the viewer's in their bubble, an agent's words under its picture, name
/// and time), as far apart and as far in as the list has them, `top` over the first as over the list's first row.
pub fn chat_messages_sample(c : @ui.Ctx, top : Double) -> Unit {
  let narrow = c.width <= chat_narrow_w
  let gap = if narrow { list_gap_narrow } else { list_gap }
  let side = row_side(c.width)
  let view = @sfbase.chat_view_made({ "title": Json::string(""), "messages": [] })
  let here : MessageHere = {
    station: "",
    session: "",
    view,
    go: None,
    inline: narrow,
    gutter: side,
    list: None,
    core: None,
  }
  c.box(style=row_column, fn() {
    c.box(style=@ui.style(h=Fixed(top)), fn() {  }) |> ignore
    for i, m in sample_messages {
      let (mine, lines) = m
      let words = lines.map(@sf.sample_words)
      let said = @sfbase.message_of({
        "ts": Json::string("sample/" + i.to_string()),
        "authorKind": Json::string(if mine { "person" } else { "agent" }),
        "mine": Json::boolean(mine),
        "text": Json::string(words.join("\n\n")),
        "md": Json::array(words.map(fn(w) { Json::array([Json::string("p"), Json::array([Json::string(w)])]) })),
        "by": { "name": Json::string(@sf.sample_words(if mine { 2 } else { 6 })), "maker": { "id": "anthropic" } },
        "time": { "createdAt": { "ago": Json::string(@sf.sample_words(3)), "full": "" } },
      })
      row_box(c, side, if i == 0 { 0.0 } else { gap }, fn() { message_row(c, @sfbase.sample_source, here, said) })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The made-up messages of chat_messages_sample: whether each is the viewer's, and how long each of its paragraphs is
/// (letters): a short ask, an answer of a few lines, and so on, as a chat goes.
// kept across runs: a table, never written
let sample_messages : Array[(Bool, Array[Int])] = [
  (true, [14]),
  (false, [70, 36]),
  (true, [22]),
  (false, [110, 48, 24]),
  (true, [9]),
  (false, [56]),
]

///|
/// Where a row of chat `r`'s list is, and how it moves there.
pub fn here_of(
  r : ChatRef,
  v : ChatView,
  rk : String,
  turns : Turns,
  em : Emits,
  flight : SendFlight?,
  core : Core,
  inline? : Bool = false,
  gutter? : Double = 0.0,
) -> MessageHere {
  {
    station: r.station,
    session: r.session,
    view: v,
    go: Some(fn(seq, passage) { @sfbase.go_to(r, seq, passage~) }),
    inline: inline,
    gutter: gutter,
    list: Some({ rk, turns, emits: em, flight }),
    core: Some(core),
  }
}

///|
/// A row of the list but an agent's activity (ChatRows): its kind's.
fn entry_row(c : @ui.Ctx, src : Source, here : MessageHere, e : Entry) -> Unit {
  match e {
    Older("") => pages_coming(c, true)
    Older(why) => older_failed(c, why)
    Newer => pages_coming(c, false)
    Empty => chat_empty(c)
    Line => unread_line(c)
    Said(m) => message_row(c, src, here, m)
    Sent(s) => sent_elsewhere(c, src, here, s)
    Out(o) => outbox_row(c, src, here, o)
    State(words, lead, rest) => chat_state(c, src, here, words, lead, rest)
    Working(_) | Top | Foot => ()
  }
}

///|
/// Chat `r`'s list's key (the composer sends it to its end: the same as the phone's).
pub fn list_key(r : ChatRef) -> String {
  "chat/" + r.station + "/" + r.session
}

///|
/// The way to the newest (ToLatest): over the list right over the send button, a round button with ↓ (and, short of
/// the chat's end, how many new messages wait there), fading in and out; pressed, the list glides to its end and
/// follows it again; short of the chat's end, the chat's latest page is put in place of what shows (`chat.latest`),
/// turning while it comes, not pressed again meanwhile. Where a go-to in the chat kept where the reader was
/// (@sfbase.go_back_to), pressed it goes back there first, not flashing, named so (回到刚才的位置); pressed again, to
/// the end.
fn to_latest(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView, shown : Bool, room : Double) -> Unit {
  let p = @sf.theme().p
  let look = match
    @motion.presence(c, "chat-jump", shown, enter=float_trans(), exit=float_trans()) {
    Some(l) => l
    None => return
  }
  let on = match v.thread {
    Some(th) => [("station", r.station), ("thread", th.to_int().to_string())]
    None => [("station", r.station), ("thread", "")]
  }
  let coming = core_doing(src, ["chat.latest"], on)
  let count = if v.newer && v.unread > 0.0 { Some(v.unread.to_int()) } else { None }
  let id = c.id("chat-jump")
  // (back first where a go-to kept where the reader was)
  // (not in a replay of a run from before the outline, whose way to the newest went to the end alone: `asks_outline`)
  let back = (src.asks_outline)() && @sfbase.place_kept(chat_key(r))
  let name = @sf.t(if back { "web-main.outline.back" } else { "web-main.chat.toLatest" })
  if shown && !coming {
    // (the list by its id here: the press is outside the scope it is built in)
    let list = c.list_reader(list_key(r))
    c.on_press(id, fn() {
      if (src.asks_outline)() && @sfbase.go_back_to(r) {
        ()
      } else if !v.newer {
        list.to_end()
      } else {
        @sfbase.chat_latest(c, src, r, v, @sf.t("web-main.chat.toLatest"))
      }
    })
  }
  @sf.tip(c, "chat-jump", id, name, shortcut="chat.latest")
  c.layer(fn() {
    float_box(c, float_right(c), room + float_lift, fn() {
      let b = c.box(style=if c.hovered(id) { float_button_hot } else { float_button }, id~, fn() {
        if coming {
          @sf.spinner(c, size=float_icon) |> ignore
        } else {
          @sf.icon(c, "arrow-down", size=float_icon, color=p.text) |> ignore
        }
        match count {
          Some(k) => c.text(@sf.t("web-main.chat.newMessages", args=[("n", k.to_string())]), style=float_count) |> ignore
          None => ()
        }
      })
      c.semantics(b, Button, id~, label=name)
      c.look(b, look)
      @motion.leaving(c, b, shown)
      b
    })
  })
  |> ignore
}

///|
/// The way to what waits to be decided in the chat (ToAsk: the core's `asks`) while its post does not show: a bell,
/// over the round buttons that show under it (`under`: the way to the end, the outline's over that); pressed, the chat
/// goes to the post, the next one's the next time. Whether it shows.
fn to_ask(
  c : @ui.Ctx,
  r : ChatRef,
  v : ChatView,
  ask_rows : Array[Int],
  info : @ui.ListInfo?,
  under : Int,
  room : Double,
) -> Bool {
  let p = @sf.theme().p
  let asks = asks_of(v)
  // (out of view once the list is laid out: before it is, as a chat opens, nothing is known to be out of view, and a
  // bell shown there went out again in the frames after)
  let laid = match info {
    Some(i) => i.first >= 0
    None => false
  }
  let shown = asks.length() > 0 && laid && !asks_in_view(ask_rows, info)
  let look = match @motion.presence(c, "chat-ask", shown, enter=float_trans(), exit=float_trans()) {
    Some(l) => l
    None => return shown
  }
  let id = c.id("chat-ask")
  if shown {
    c.on_press(id, fn() {
      let k = chat_key(r)
      let turn = ask_turns.get(k).unwrap_or(0)
      @sfbase.go_to(r, asks[turn % asks.length()])
      ask_turns[k] = turn + 1
    })
  }
  @sf.tip(c, "chat-ask", id, @sf.t("web-main.chat.asks.go"))
  // (over the round buttons under it: as one comes or goes, it moves there from where it is, a Move (sf/motion.mbt
  // move_spring), set off as their coming and going is, as this is built for it; laid out where it goes, drawn the
  // rest of its way short of there)
  let lift = under.to_double() * float_above
  let lifting = @motion.told(c, "chat-ask/lift", lift, spec=@sf.move_spring)
  c.layer(fn() {
    float_box(c, float_right(c), room + float_lift + lift, fn() {
      let b = c.box(style=if c.hovered(id) { float_button_hot } else { float_button }, id~, fn() {
        @sf.icon(c, "bell", size=float_icon, color=p.text) |> ignore
      })
      c.semantics(b, Button, id~, label=@sf.t("web-main.chat.asks.go"))
      c.look_by(b, fn() { { ..look, dy: look.dy + lift - lifting.get(c) } })
      @motion.leaving(c, b, shown)
      b
    })
  })
  |> ignore
  shown
}

///|
/// What waits to be decided in the chat (the core's `asks`, their posts' seqs): none in one archived or not made yet.
fn asks_of(v : ChatView) -> Array[Double] {
  if v.archived || v.thread is None {
    []
  } else {
    v.asks
  }
}

///|
/// Which of each chat's asks the bell goes to next (by the chat's key).
pub let ask_turns : Map[String, Int] = Map([])

///|
/// What ⌘F last asked the window moved about (`chat.around`), once (-1 none).
let find_around : Ref[Double] = Ref(-1.0)

///|
/// The picture flying out of an activity to its message and back (useEmissions): the agent's, ringed, where emit.mbt
/// has it, drawn only.
fn emit_flyer(c : @ui.Ctx, rk : String, em : Emits, v : ChatView, src : Source, r : ChatRef) -> Unit {
  // (one flies from its activity's fold on, till it is home)
  let a = match em.current {
    Some(t) if t.pose != @sfbase.Pose::Fold => v.agents.iter().find_first(fn(a) { a.key == t.agent })
    _ => return
  }
  let (maker, runtime, waiting) = match a {
    Some(a) => (a.maker, a.runtime, a.wait is Some(_))
    None => ("", "", false)
  }
  let here = { station: r.station, session: r.session, view: v, go: None, inline: false, gutter: 0.0, list: None, core: None }
  c.layer(fn() {
    let b = c.box(style=activity_face, fn() {
      agent_avatar(c, src, here, "flyer", maker, runtime, "", "")
      c.layer(fn() { work_ring(c, waiting) }) |> ignore
    })
    // Where it is between its activity and the message as this frame draws them (emit_flight, in the window): it goes
    // with the list as that glides. Read their places and its clock as painted, so its movement alone does not lay out
    // the chat again. Its layer's corner is wherever the chat is in the window (beside the sidebar).
    let agents = v.agents.map(fn(a) { a.key })
    let flyer = "emit-flyer/" + rk
    @motion.measure(c, b, flyer)
    c.look_by(b, fn() {
      match (emit_flight(c, rk, em, agents), @motion.measured_rect(c, flyer)) {
        (Some((x, y, sx, sy)), Some((bx, by, _, _))) => {
          @ui.look(dx=x - ring_room - bx, dy=y - ring_room - by, sx~, sy~)
        }
        _ => @ui.look(alpha=0.0)
      }
    })
    c.draw_only(b)
  })
  |> ignore
}

///|
/// The list's ⌘F goes along: the messages showing, the list to a message with the words marked
/// in it, its marks let go. Where the chat's page is made as nodes (sfbase's chat_page_nodes), that page's list's
/// (chat_nodes_find_list).
pub fn chat_find_list(r : ChatRef) -> FindList {
  if @sfbase.chat_page_nodes.untracked() {
    return chat_nodes_find_list(r)
  }
  let k = chat_key(r)
  {
    showing: fn() {
      let rd = reading_of(k)
      (rd.top_seq, rd.bottom_seq)
    },
    go: fn(seq, words) {
      go_tos[k] = seq
      go_to_words[k] = words
    },
    forget: fn() { find_forget() },
  }
}

///|
/// ⌘F let go in the chat it is open in: the words it marked, where it was going, its bar.
pub fn find_forget() -> Unit {
  let k = find_chat()
  match readings.get(k) {
    Some(rd) => {
      rd.found_at = ""
      rd.found_words = []
    }
    None => ()
  }
  go_tos.remove(k)
  go_to_words.remove(k)
  find_around.val = -1.0
  find_close()
}

///|
/// What the list keeps of its own, let go (the package's reset).
fn list_reset() -> Unit {
  lists_set_off.clear()
  lists_held_w.clear()
  flashing_now.val = ("", 0.0)
  ask_turns.clear()
  find_around.val = -1.0
  outline_entries.clear()
  outline_presets.clear()
  rail_said.set({})
  rail_asking.clear()
}

///|
/// How far the rows stand in from the pane's sides: the column 760 wide at most in its middle, 40 in at least
/// .
fn native_row_inset() -> Double {
  @sf.pane_foot_rest(holds=@sf.theme().round.side) + @sf.composer_pad + 8.0
}

///|
/// How wide chat list `key` is laid out in a pane as wide as `c`, whether otherwise than as wide as it, in its middle
/// (held), and as of when: on the frame that finds its way over, the moment it is there (a row's room going from then,
/// whichever frame that is); else now. On the page's way to another width (@sfbase.page_way: a side panel sliding beside it, the sidebar opening or
/// folding) across one at which its rows are laid out otherwise (chat_narrow_w: 20 between messages, not 28, each
/// picture inline; or the composer under it reaching across the pane, its room under the last row 8 less:
/// composer_foot_in), as where it goes, from the frame it sets off till the one it is there: so they are laid out anew
/// only as the way sets off, whichever frames are drawn on the way, each row another version then (sfbase's
/// shown_rows), its room going on the list's way from that frame, not as a frame drawn first finds the pane past that
/// width; standing where they stood as it set off and going from there to where they come to stand as the pane goes
/// (list_shift). Laid out at the narrower end the whole way and in the pane's middle, they were narrow at once and
/// slid across the pane as a panel came in, and went on narrow to be wide at once as it was gone (the user,
/// 2026-11-09: 「打开关闭右侧面板，中间的变化不对」). On a way across none of them, as wide as where it goes once
/// both are wide enough for its column (the rows as wide either way), else as wide as it is. Not beside the system's
/// bars (native_on): each frame as it is.
fn laid_w(c : @ui.Ctx, key : String) -> (Double, Bool, Double) {
  let way = @sfbase.page_way
  let now = c.moment()
  if way.id == "" || @sf.native_on() {
    match lists_set_off.get(key) {
      // (the frame that finds its way over: laid out anew as of the moment it is there)
      Some((id, _, ends, _)) if id != "" => {
        lists_set_off[key] = ("", 0.0, dmin(ends, now), now)
        return (c.width, false, dmin(ends, now))
      }
      // (asked again at the moment that found it over: as of when it was there, whichever build asks)
      Some((_, _, at, found)) if found == now => return (c.width, false, at)
      Some(_) => lists_set_off.remove(key) |> ignore
      None => ()
    }
    return (c.width, false, now)
  }
  let from = match lists_set_off.get(key) {
    Some((id, w, _, _)) if id == way.id => w
    _ => c.width
  }
  lists_set_off[key] = (way.id, from, way.ends, now)
  let to = way.to
  if (from <= chat_narrow_w) != (to <= chat_narrow_w) || composer_across(from) != composer_across(to) {
    return (to, true, now)
  }
  if to > chat_narrow_w && dmin(c.width, to) >= chat_column_w + 2.0 * row_side_least {
    return (to, true, now)
  }
  (c.width, false, now)
}

///|
/// What chat list `key`'s rows are another version for (shown_rows' `laid`): the page's way it was held on (laid_w) and
/// the width it was held at, that one still once the way is there, so that its rows are not another version again as
/// nothing of them changed (all of them on the list's way for nothing then, a way set off over it while that goes on
/// from there: a side panel closed again as soon as it is open), and still as the pane is made another width by
/// nothing that goes (the window, its edge dragged): no cause of a row's (apps/mbui/AGENTS.md, Motion). Each way held
/// on is another (its id), so a way to a width held at before still sets the rows off on it. Where the way lets go of
/// it at another width than it held it at (a page opened over the chat's held it at that page's pane, the chat staying
/// beside its panel under it), the frame it lets go of it is the way's too: the rows another version again, for that
/// way at the width it is there, on the list's way from it, not at their new heights at once in a frame nothing moved
/// (rows_steady; view_beside_wbtest).
fn laid_at_w(key : String, held : Bool, w : Double) -> String {
  if held {
    let id = @sfbase.page_way.id
    let laid = "|" + id + "@" + w.to_string()
    lists_held_w[key] = (laid, id, w, true)
    return laid
  }
  match lists_held_w.get(key) {
    Some((laid, id, at, true)) => {
      let laid = if (at - w).abs() < 0.5 { laid } else { "|" + id + "@" + w.to_string() }
      lists_held_w[key] = (laid, id, w, false)
      laid
    }
    Some((laid, _, _, _)) => laid
    None => ""
  }
}

///|
/// What each chat list's rows were last held for on a page's way (laid_at_w): their `laid`, that way's id, the width
/// it was laid out at, and whether it was held still as it was last built.
let lists_held_w : Map[String, (String, String, Double, Bool)] = Map([])

///|
/// How far from the left of a pane `frame_w` wide chat list `key`, laid out `list_w` wide, stands: in its middle; on a
/// page's way across the width it is laid out otherwise at (laid_w: as where it goes), its rows' words where they stood
/// in the pane as it set off, going as far as the pane has gone to where they stand once it is there (its left edge),
/// not sliding across it in its middle nor stepping as it sets off.
fn list_shift(key : String, frame_w : Double, list_w : Double) -> Double {
  let way = @sfbase.page_way
  match lists_set_off.get(key) {
    Some((id, from, _, _)) if id != "" && id == way.id && list_w == way.to && from != way.to => {
      let gone = dmax(0.0, dmin(1.0, (from - frame_w) / (from - way.to)))
      (row_side(from) - row_side(way.to)) * (1.0 - gone)
    }
    _ => (frame_w - list_w) / 2.0
  }
}

///|
/// Each chat list on a page's way, or the moment it found it over: the way ("" over), how wide its pane was as it set
/// off, when it is there, and the moment last asked at (laid_w).
let lists_set_off : Map[String, (String, Double, Double, Double)] = Map([])

///|
fn row_side(w : Double) -> Double {
  // Inline avatars need no hanging-avatar gutter. Narrow beside the system's bars (an iPhone Duo's), the rows as wide
  // as the composer words under them, including its inner text padding; elsewhere 16 in.
  if w <= chat_narrow_w {
    return if @sf.native_on() { native_row_inset() } else { row_side_narrow }
  }
  // (beside the system's bars, an iPhone Duo's: the rows across the pane, dense_row_side in)
  if @sf.native_on() {
    return dense_row_side
  }
  dmax(row_side_least, (w - chat_column_w) / 2.0)
}

///|
/// How far in from a chat's column's left its rows' words start at width `w` (row_side): what the shell moves the
/// column by while it is laid out at another width than it is drawn (sfbase's chat_page_made, `narrower`).
pub fn chat_row_side(w : Double) -> Double {
  row_side(w)
}

///|
/// (its pictures out in that room, 29 before the words, about as far from the card's edge as the chat's title: the
/// user, 2026-10-28, 头像都贴边了)
let dense_row_side : Double = 48.0

///|
/// Where the round buttons over the list go: right over the send button, the composer's column in the pane's middle
/// .
fn float_right(c : @ui.Ctx) -> Double {
  (c.width - composer_width(c.width)) / 2.0 + float_in
}

///|
/// How the round buttons come and go (chatToBottom: fading, 160 ms on the ease out).
fn float_trans() -> @motion.Trans {
  @motion.trans(fade=0.0, spec=@motion.tween(float_ms, ease=Out), fade_spec=@motion.tween(float_ms, ease=Out))
}


///|
/// The column's width at most, and how far in its sides stand at least.
let chat_column_w : Double = 760.0

///|
let row_side_least : Double = 40.0

///|
/// A row's height as guessed before it is laid out.
let chat_row_est : Double = 90.0

///|
/// The rows 28 apart, one sent soon after the one before 4 under it.
let list_gap : Double = 28.0

///|
/// The widest a list is laid out narrow, and then 20 between its messages (the web's
/// mobile --list-gap) and 16 in from its sides.
pub let chat_narrow_w : Double = 700.0

///|
let list_gap_narrow : Double = 20.0

///|
let row_side_narrow : Double = 16.0

///|
let joined_gap : Double = 4.0

///|
/// The list's room over its first row (under the chat's bar: 45, and 24), under its last (24, over the composer's
/// room), and where the unread line goes under its top (about four lines of what came before it in view: 4 × 23).
let list_top : Double = 69.0

///|
/// The room under the chat's bar over the list's first row (list_top's 24): room, the bar's drawn over none of it.
let list_room : Double = list_top - bar_foot

///|
let list_foot : Double = 24.0

///|
pub let bar_foot : Double = 45.0

///|
let unread_lead : Double = 92.0

///|
/// The round buttons over the list (chatToBottom): 32 across, 6 in from the send button's side, 12 over the composer's
/// room; the bell 8 over the way to the end when both show; their icon 16; how long they come and go.
let float_side : Double = 32.0

///|
let float_in : Double = 6.0

///|
let float_lift : Double = 12.0

///|
let float_above : Double = 40.0

///|
let float_icon : Double = 16.0

///|
let float_ms : Double = 160.0

///|
/// The ring's room round a picture in it (24 round 18).
let ring_room : Double = 3.0

///|
/// The list's box: the pane.
// kept across runs: a value (no field of it changes)
let chat_list_box : @ui.Style = @ui.css("w=Full h=Full")

///|
/// A row's room (its node): in from the pane's sides to the column (`side` each), `top` over it. `lit`: how lit it is
/// as a message gone to, and how far its ground reaches over and under it (square, out to the pane's sides as the row
/// runs: nothing of it in a corner; lit one after another, such grounds meet), its words where they are without it;
/// `lit_by`, that band's ground as it is painted instead (Ctx::bg_by: a menu open for it).
fn row_box(
  c : @ui.Ctx,
  side : Double,
  top : Double,
  body : () -> Unit,
  lit? : (Double, Double, Double)? = None,
  lit_by? : (() -> Int64)? = None,
) -> Int {
  // The system column is reserved by the shell; the text still needs its own
  // inset from the card's edge, also when a details card stands beside it.
  let trailing = if @sf.native_side() { native_row_inset() } else { side }
  c.box(style=row_column, fn() {
    if top > 0.0 {
      c.box(style=@ui.style(h=Fixed(top)), fn() {  }) |> ignore
    }
    let line = match lit {
      Some((_, over, under)) =>
        row_line.then(@ui.style(pt=@sf.room_of(over), mt=@sf.room_of(-over), pb=@sf.room_of(under), mb=@sf.room_of(-under)))
      None => row_line
    }
    c.box(style=line, fn() {
      match lit {
        Some((alpha, _, _)) =>
          match lit_by {
            Some(f) => {
              let g = c.layer(fn() { c.box(style=band_ground, fn() {  }) |> ignore })
              c.bg_by(g, f)
            }
            None => {
              let g = c.layer(fn() { c.box(style=flash_ground, fn() {  }) |> ignore })
              c.look(g, @ui.look(alpha~))
            }
          }
        None => ()
      }
      c.box(style=@ui.style(w=Fixed(side)), fn() {  }) |> ignore
      c.box(style=row_middle, body) |> ignore
      c.box(style=@ui.style(w=Fixed(trailing)), fn() {  }) |> ignore
    })
    |> ignore
  })
}

///|
// kept across runs: a value (no field of it changes)
let row_column : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let row_line : @ui.Style = @ui.css("row w=Full")

///|
// kept across runs: a value (no field of it changes)
let row_middle : @ui.Style = @ui.style(w=@sf.grow)

///|
/// A round button over the list, `right` in from the pane's end and `foot` over its foot (its node).
fn float_box(c : @ui.Ctx, right : Double, foot : Double, body : () -> Int) -> Unit {
  c.box(style=float_place, fn() {
    c.spacer()
    c.box(style=row_line, fn() {
      c.box(style=row_middle, fn() {  }) |> ignore
      body() |> ignore
      c.box(style=@ui.style(w=Fixed(right)), fn() {  }) |> ignore
    })
    |> ignore
    c.box(style=@ui.style(h=Fixed(foot)), fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// A message's band in a ground drawn as it is painted (its menu open: Ctx::bg_by), the band's room alone.
// kept across runs: a value (no field of it changes)
let band_ground : @ui.Style = @ui.css("w=Full h=Full")

///|
/// A message gone to lit whole, its ground (msgFlash): the accent's, as its row's band (row_box).
// kept across runs: a value (no field of it changes)
let flash_ground : @ui.Style = @ui.css("w=Full h=Full bg=AccentBg")

///|
/// The message gone to flashing in the list drawn now and how far its flash is (its ts, 0 to 1): its row's band
/// (row_box), or the passage a quote quoted behind its words (passage_lit).
pub let flashing_now : Ref[(String, Double)] = Ref(("", 0.0))

///|
/// Whether the message gone to in a chat is lit whole: led there by no quote, or by one whose passage its words do not
/// have (Chat.tsx Quotes' jump: then the whole message); not while its words are yet to be laid out.
fn flash_whole(c : @ui.Ctx, rd : @sfbase.Reading) -> Bool {
  if rd.flash_passage == "" {
    return true
  }
  match c.words_of("pick/" + rd.flash) {
    Some(w) => @sf.find_passage(w.text, rd.flash_passage) is None
    None => false
  }
}

///|
/// The passage a quote that led to message `ts` quoted, where its words (box `key` laid out as `words`) have it, and
/// the ground it is drawn on as lit now: the accent's as a passage picked in it has it (pickable), fading with its
/// flash; None for any other message, or one lit whole.
fn passage_lit(c : @ui.Ctx, here : MessageHere, ts : String) -> (Int, Int, Int64)? {
  let rd = match here.list {
    Some(l) => reading_of(l.rk)
    None => return None
  }
  if rd.flash != ts || rd.flash_passage == "" {
    return None
  }
  let lit = flash_of(c, rd, ts)
  match c.words_of("pick/" + ts) {
    Some(w) =>
      match @sf.find_passage(w.text, rd.flash_passage) {
        Some((a, b)) if lit > 0.0 => Some((a, b, @sf.alpha(@sf.theme().p.accent, @sfbase.picked_alpha * lit)))
        _ => None
      }
    None => None
  }
}

///|
/// Whether message `ts`'s words are to be kept as laid out for a passage a quote quoted to be found in them.
fn passage_wanted(here : MessageHere, ts : String) -> Bool {
  match here.list {
    Some(l) => {
      let rd = reading_of(l.rk)
      rd.flash == ts && rd.flash_passage != ""
    }
    None => false
  }
}

///|
/// Once the message gone to is laid out: the passage a quote quoted, low in it (past 80% of the list's height, the
/// list's box measured as `pane`), comes to the list's middle (Chat.tsx Quotes' jump: the quoted words at the middle),
/// once.
fn passage_centre(c : @ui.Ctx, rd : @sfbase.Reading, list : String, pane : String) -> Unit {
  if !rd.flash_centre || rd.flash == "" {
    return
  }
  match (c.words_of("pick/" + rd.flash), @motion.measured_rect(c, pane)) {
    (Some(w), Some((_, py, _, ph))) => {
      rd.flash_centre = false
      match @sf.find_passage(w.text, rd.flash_passage) {
        Some((a, b)) => {
          let lines = w.rects(a, b)
          if lines.length() > 0 {
            let (_, y, _, _) = lines[0]
            let (_, ly, _, lh) = lines[lines.length() - 1]
            let mid = (y + ly + lh) / 2.0 - py
            if mid > ph * 0.8 {
              c.list_scroll_by(list, mid - ph / 2.0)
            }
          }
        }
        None => ()
      }
    }
    _ => ()
  }
}

///|
/// Where the round buttons go: the pane's foot, at its end.
// kept across runs: a value (no field of it changes)
let float_place : @ui.Style = @ui.css("w=Full h=Full")

///|
/// A round button over the list (chatToBottom): 32 high, round, a line round it on the canvas, a shadow under it; its
/// count beside its arrow; the hover ground under the pointer.
// kept across runs: a value (no field of it changes)
let float_button : @ui.Style = @ui.css((
  #|row h=S8 min_w=S8 px=S2 gap=S1 radius=Full border=B1 border_color=Line bg=Surface shadow=Md align=ACenter justify=JCenter
))

///|
// kept across runs: a value (no field of it changes)
let float_button_hot : @ui.Style = float_button.then(@ui.css("bg=Over(Surface, Hover)"))

///|
// kept across runs: a value (no field of it changes)
let float_count : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false)


///|
/// The composer's width on a chat's page (dock.css.ts, the chat's: the column and the capsule's curve each side, 760
/// and 22 each side at most, 12 clear of the pane's edges).
pub fn composer_width(pane : Double) -> Double {
  if @sf.native_on() {
    return pane - 2.0 * composer_side()
  }
  dmin(pane - 2.0 * composer_side(), composer_most)
}

///|
/// The composer's widest, its clearance from the pane's sides.
let composer_most : Double = 804.0

///|
/// (In a panel of its own, as far in as makes its box concentric with the panel's foot corners its round controls can
/// follow in turn in its own: @sf.pane_foot_in.)
pub fn composer_side() -> Double {
  @sf.pane_foot_in(holds=@sf.theme().round.side)
}

///|
/// What row `k` moves for when what comes in over it pushes it down (one that makes way: an agent's line, what was
/// sent not in the chat yet): the newest row that came in over it (row_keys's makes_way). The page before come in
/// above it, words sent flying in, a row over it grown or gone, a keyboard: none of them, it is put there at once.
fn makes_way(lf : @sfbase.ListFrame, k : String) -> String {
  "came " + lf.rd.makes_way.get(k).unwrap_or("")
}

///|
/// What a row moves for where it shows when the list is followed at its end and a row comes in over the rows at that
/// end: the newest that did (row_keys's `over`). The list stays at its end at once, so what is at the end stays where
/// it shows and the rows over the one that came go up for it, from where they showed.
fn came_over(lf : @sfbase.ListFrame) -> String {
  "over " + lf.rd.over
}
