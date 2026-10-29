// A chat's messages on the desktop (ember web/src/Chat.tsx ChatShown, ChatRows, useMessageList, ToLatest, ToAsk;
// Chat.css.ts chatMessages, chatToBottom, chatToAsk; styles/session.css.ts chatList): its rows in the column 760 wide
// at most in the pane's middle, running on under the composer; following its end, the pages before and after brought
// in near its edges, put in place once (the unread line, where it was left, where the core opened it), what is read and
// where the reader is told the core: all of that as the phone's list has it too (sfbase's chat_list.mbt: list_frame
// before the rows are drawn, list_after once they are). What comes in does so in its turn (list_turns.mbt): a message
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
) -> Unit {
  let narrow = c.width <= chat_narrow_w
  let list_top = top
  let list_gap = if narrow { list_gap_narrow } else { list_gap }
  let key = list_key(r)
  let draft = r.station + ":" + r.session
  // what a message's menu left to do (menus.mbt)
  menus_frame(c)
  // its pictures that could not be had for want of its station asked again: as the chat comes into view (not drawn the
  // frame before), and as its station is reached again
  let frame = c.frame_number()
  match lists_drawn.get(key) {
    Some(f) if f == frame || f == frame - 1 => ()
    _ => src.images.again(r.station)
  }
  lists_drawn[key] = frame
  src.images.seen(r.station, !v.offline)
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
  let ask_clear = if asks_of(v).is_empty() || !v.ask_clear { 0.0 } else { float_lift + float_side }
  let side = row_side(c)
  // the sides are only the page's margin either way: wide, the pictures out in it stand by their heads' line, not by
  // the words under it, so a table scrolls out over it to the pane's edges as it does narrow
  let gutter = side
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
  let list_box = c.box(style=chat_list_box, fn() {
    c.list(
      key,
      n,
      chat_row_est,
      fn(i) {
        let e = list[i]
        let top = top_at(i)
        let mk = key + "\u{1}" + keys[i]
        // what changed its height and when (docs/list-motion.md): it came while the list showed, or it goes
        match rd.going.get(keys[i]) {
          Some(g) => c.row_size(keys[i], Goes(g.at))
          None =>
            match (rd.came_at.get(keys[i]), rd.changed_at.get(keys[i])) {
              (Some(t), Some(u)) if u > t => c.row_size(keys[i], Changed(u))
              (None, Some(u)) => c.row_size(keys[i], Changed(u))
              // (words sent flying to it: its room opens as long as their way, the rows over it going up with them)
              (Some(t), _) =>
                match flight {
                  Some(f) if flight_takes(draft, keys[i]) => c.row_size(keys[i], Comes(t), ms=@sfbase.flight_len(f.desk || f.carried))
                  _ => c.row_size(keys[i], Comes(t))
                }
              (None, None) => ()
            }
        }
        match e {
          Top => c.box(style=@ui.style(h=Fixed(list_top)), fn() {  }) |> ignore
          Foot => c.box(style=@ui.style(h=Fixed(room + foot + ask_clear)), fn() {  }) |> ignore
          Working(a) => {
            // coming in, it fades in and grows from its picture as its room opens (the list's rows' heights:
            // Ctx::row_size); its turn over, it stays a moment and fades (Activity), then its room closes (going)
            let open = @motion.anim(c, "open/" + mk, 1.0, global=true)
            if rd.fresh.contains(keys[i]) {
              rd.fresh.remove(keys[i])
              open.snap(0.0)
              let at = rd.came_at.get(keys[i]).unwrap_or(-1.0)
              open.animate(1.0, @motion.tween(working_turn_ms, ease=Out), start_at?=if at >= 0.0 { Some(at) } else { None })
            }
            let leaving = match rd.linger.get(a.key) {
              Some(l) => l.leaving
              None => false
            }
            let fade = @motion.animate(c, "fade/" + mk, if leaving { 0.0 } else { 1.0 }, spec=@motion.tween(linger_out_ms, ease=Leave))
            let p = open.get()
            let here = here_of(r, v, rk, turns, em, None, core, inline=narrow, gutter~)
            let ri = row_box(c, side, top, fn() { activity_row(c, src, here, a, em, rk, leaving) })
            @motion.keyed(c, ri, mk, by=makes_way(lf, keys[i]))
            // (growing from its picture's middle: where the messages' pictures are, at the row's start narrow, out
            // in the margin before the words wider)
            let face = side + (if narrow { 0.0 } else { -@sf.columns.avatar }) + avatar_side / 2.0
            c.look(ri, @ui.look(alpha=p * fade * gone_alpha(c, rd, mk, keys[i]), scale=0.5 + 0.5 * p, ox=face / c.width, oy=0.5))
            @motion.leaving(c, ri, !rd.going.contains(keys[i]))
          }
          _ => {
            // the row words sent go to: its bubble flies there from the composer
            let flies = flight_takes(draft, keys[i])
            match flight {
              Some(f) if flies => flight_placed(c, f)
              _ => ()
            }
            let here = here_of(r, v, rk, turns, em, if flies { flight } else { None }, core, inline=narrow, gutter~)
            // what it moves for where it shows: what was sent from here not in the chat yet, the newest that came in
            // over it; any other row, the newest that came in over the rows at the end as the list followed it
            let cause = match e {
              Out(_) => makes_way(lf, keys[i])
              _ => came_over(lf)
            }
            // gone to, lit whole: a band across the list from edge to edge, half the room to the rows over and under
            let band = match e {
              Said(m) if whole && m.ts == lit.0 && lit.1 > 0.0 =>
                Some((lit.1, top / 2.0, if i + 1 < n { top_at(i + 1) / 2.0 } else { 0.0 }))
              _ => None
            }
            let ri = row_box(c, side, top, lit=band, fn() {
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
            // moves it; what leaves the list stays in it while its room closes (Reading's `going`), fading
            @motion.keyed(c, ri, mk, by=cause)
            @motion.leaving(c, ri, !rd.going.contains(keys[i]))
            // what is new to the list while it is followed eases in ([data-enter]: 220 ms from 6 under), not one out of
            // a picture
            let emitted = match e {
              Said(m) => emit_goes(em, m.seq)
              _ => false
            }
            if rd.fresh.contains(keys[i]) {
              rd.fresh.remove(keys[i])
              if !emitted {
                let a = @motion.Anim::new(0.0)
                let at = rd.came_at.get(keys[i]).unwrap_or(-1.0)
                a.animate(1.0, @motion.tween(@sf.enter_ms, ease=@sf.ease_out), start_at?=if at >= 0.0 { Some(at) } else { None })
                rd.rises[keys[i]] = a
              }
            }
            match rd.rises.get(keys[i]) {
              Some(a) => {
                let p = a.get()
                // (risen: at its end, a tween's 1 only there)
                if p >= 1.0 {
                  rd.rises.remove(keys[i]) |> ignore
                } else {
                  c.look(ri, @ui.look(alpha=p * gone_alpha(c, rd, mk, keys[i])))
                }
              }
              None => if rd.going.contains(keys[i]) { c.look(ri, @ui.look(alpha=gone_alpha(c, rd, mk, keys[i]))) }
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
    )
    |> ignore
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
      on_found=fn(rd) { rd.found_centre = true },
      find_around~,
    )
    // gone to by a quote: what it quoted, low in the message, to the list's middle
    passage_centre(c, rd, key, "chat-list/" + key)
    // the way to the newest: away from its end, or short of the chat's end
    rd.jump = la.away || v.newer
    to_latest(c, src, r, v, la.away || v.newer, room)
    // what waits to be decided and does not show: a bell over the way to the end
    rd.ask = to_ask(c, r, v, la.ask_rows, la.info, la.away || v.newer, room)
    // the picture flying out of an activity to its message and back, over the list
    emit_flyer(c, rk, em, v, src, r)
  })
  // (where it is, for what a quote led to to be put in its middle: passage_centre)
  @motion.measure(c, list_box, "chat-list/" + key)
  // (what of it the bar and the composer hide: its pictures, noted as its, go out from under them before they grow
  // into the viewer)
  @sfbase.note_list(c, list_box, rk, bar, room)
  // a new chat's list comes up out of the composer with its first words: drawn below its place by how far they have
  // to go, from where this frame lays their row out (flight.mbt flight_carry_shift)
  if flight_carried(lf.draft) {
    @motion.placed(c, list_box, fn() { @ui.look(dy=flight_carry_shift(c, lf.draft)) })
  }
}

///|
/// A chat's messages to come while it is read the first time (the library's Waiting, in its bones): made-up messages
/// as its list draws them (row_box, message_row: the viewer's in their bubble, an agent's words under its picture, name
/// and time), as far apart and as far in as the list has them, `top` over the first as over the list's first row.
pub fn chat_messages_sample(c : @ui.Ctx, top : Double) -> Unit {
  let narrow = c.width <= chat_narrow_w
  let gap = if narrow { list_gap_narrow } else { list_gap }
  let side = row_side(c)
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
    Older => pages_coming(c, true)
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
/// turning while it comes, not pressed again meanwhile.
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
  if shown && !coming && c.clicked(id) {
    if !v.newer {
      c.list_to_end(list_key(r))
    } else {
      @sfbase.chat_latest(c, src, r, v, @sf.t("web-main.chat.toLatest"))
    }
  }
  @sf.tip(c, "chat-jump", id, @sf.t("web-main.chat.toLatest"), shortcut="chat.latest")
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
      c.semantics(b, Button, id~, label=@sf.t("web-main.chat.toLatest"))
      c.look(b, look)
      @motion.leaving(c, b, shown)
      b
    })
  })
  |> ignore
}

///|
/// The way to what waits to be decided in the chat (ToAsk: the core's `asks`) while its post does not show: a bell,
/// over the way to the end when both show; pressed, the chat goes to the post, the next one's the next time. Whether it
/// shows.
fn to_ask(
  c : @ui.Ctx,
  r : ChatRef,
  v : ChatView,
  ask_rows : Array[Int],
  info : @ui.ListInfo?,
  above : Bool,
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
  if shown && c.clicked(id) {
    let k = chat_key(r)
    let turn = ask_turns.get(k).unwrap_or(0)
    @sfbase.go_to(r, asks[turn % asks.length()])
    ask_turns[k] = turn + 1
  }
  @sf.tip(c, "chat-ask", id, @sf.t("web-main.chat.asks.go"))
  c.layer(fn() {
    let lift = if above { float_above } else { 0.0 }
    float_box(c, float_right(c), room + float_lift + lift, fn() {
      let b = c.box(style=if c.hovered(id) { float_button_hot } else { float_button }, id~, fn() {
        @sf.icon(c, "bell", size=float_icon, color=p.text) |> ignore
      })
      c.semantics(b, Button, id~, label=@sf.t("web-main.chat.asks.go"))
      c.look(b, look)
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
pub let ask_turns : Map[String, Int] = {}

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
    // where it is between its activity and where the message goes as this frame lays them out (emit_flight, in the
    // window), not where the frame before had them: it goes with the list as that glides. Moved from where it is laid
    // out, at its layer's corner: wherever the chat is in the window (beside the sidebar), not from the window's
    let agents = v.agents.map(fn(a) { a.key })
    @motion.placed(c, b, fn() {
      match emit_flight(c, rk, em, agents) {
        Some((x, y, sx, sy)) => {
          let (bx, by, _, _) = c.node_rect(b)
          @ui.look(dx=x - ring_room - bx, dy=y - ring_room - by, sx~, sy~)
        }
        None => @ui.look(alpha=0.0)
      }
    })
    c.draw_only(b)
  })
  |> ignore
}

///|
/// The list's ⌘F goes along (ChatFind.tsx `virtual`): the messages showing, the list to a message with the words marked
/// in it, its marks let go.
pub fn chat_find_list(r : ChatRef) -> FindList {
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
/// The frame each chat's list was last drawn in (chat_list): one not drawn the frame before is coming into view.
// kept across runs: put back by list_reset (reset)
let lists_drawn : Map[String, Int] = {}

///|
/// What the list keeps of its own, let go (the package's reset).
fn list_reset() -> Unit {
  lists_drawn.clear()
  flashing_now.val = ("", 0.0)
  ask_turns.clear()
  find_around.val = -1.0
}

///|
/// How far the rows stand in from the pane's sides: the column 760 wide at most in its middle, 40 in at least
/// (session.css.ts chatList).
fn native_row_inset() -> Double {
  composer_side() + @sf.composer_pad + 8.0
}

///|
fn row_side(c : @ui.Ctx) -> Double {
  // Inline avatars need no hanging-avatar gutter. Narrow beside the system's bars (an iPhone Duo's), the rows as wide
  // as the composer words under them, including its inner text padding; elsewhere 16 in.
  if c.width <= chat_narrow_w {
    return if @sf.native_on() { native_row_inset() } else { row_side_narrow }
  }
  // (beside the system's bars, an iPhone Duo's: the rows across the pane, dense_row_side in)
  if @sf.native_on() {
    return dense_row_side
  }
  dmax(row_side_least, (c.width - chat_column_w) / 2.0)
}

///|
/// (its pictures out in that room, 29 before the words, about as far from the card's edge as the chat's title: the
/// user, 2026-10-28, 头像都贴边了)
let dense_row_side : Double = 48.0

///|
/// Where the round buttons over the list go: right over the send button, the composer's column in the pane's middle
/// (Chat.css.ts chatToBottom: 6 in from it).
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
/// The rows 28 apart (session.css.ts chatList gap), one sent soon after the one before 4 under it.
let list_gap : Double = 28.0

///|
/// The widest a list is laid out narrow (Chat.css.ts `max-width: 700px`), and then 20 between its messages (the web's
/// mobile --list-gap) and 16 in from its sides (session.css.ts chatList).
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
/// runs: nothing of it in a corner; lit one after another, such grounds meet), its words where they are without it.
fn row_box(
  c : @ui.Ctx,
  side : Double,
  top : Double,
  body : () -> Unit,
  lit? : (Double, Double, Double)? = None,
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
        Some((alpha, _, _)) => {
          let g = c.layer(fn() { c.box(style=flash_ground, fn() {  }) |> ignore })
          c.look(g, @ui.look(alpha~))
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
/// A round button over the list (chatToBottom): 32 high (the desktop's: Chat.css.ts at a desktop's width), round, a line round it on the canvas, a shadow under it; its
/// count beside its arrow; the hover ground under the pointer.
// kept across runs: a value (no field of it changes)
let float_button : @ui.Style = @ui.css(
  #|row h=S8 min_w=S8 px=S2 gap=S1 radius=Full border=B1 border_color=Line bg=Surface shadow=Md align=ACenter justify=JCenter
)

///|
// kept across runs: a value (no field of it changes)
let float_button_hot : @ui.Style = float_button.then(@ui.css("bg=Hover"))

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
/// The composer's widest (dock.css.ts: 760 and its curve each side), its clearance from the pane's sides.
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


///|
/// How much of row `k` (its motion key `mk`) shows as it goes from the list (Reading's `going`): faded out on `Leave`
/// as its room closes; 1 for one not going.
fn gone_alpha(c : @ui.Ctx, rd : @sfbase.Reading, mk : String, k : String) -> Double {
  match rd.going.get(k) {
    // (gone by now: nothing to fade)
    Some(g) if c.moment() >= g.at + @sf.leave_ms => 0.0
    Some(g) => {
      // (its own for this going: one that comes again, an agent's line its next turn, shows whole)
      let a = @motion.anim(c, "gone/" + mk + "/" + g.at.to_string(), 1.0, global=true)
      if a.target() != 0.0 {
        a.animate(0.0, @motion.tween(@sf.leave_ms, ease=Leave), start_at=g.at)
      }
      a.get()
    }
    None => 1.0
  }
}
