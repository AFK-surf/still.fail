// A chat's messages on the desktop (ember web/src/Chat.tsx ChatShown, ChatRows, useMessageList, ToLatest, ToAsk;
// Chat.css.ts chatMessages, chatToBottom, chatToAsk; styles/session.css.ts chatList): its rows in the column 760 wide
// at most in the pane's middle, running on under the composer; following its end, the pages before and after brought
// in near its edges, put in place once (the unread line, where it was left, where the core opened it), what is read and
// where the reader is told the core: all of that as the phone's list has it too (sfbase's chat_list.mbt: list_frame
// before the rows are drawn, list_after once they are). What comes in does so in its turn (list_turns.mbt): a message
// eases in, an agent's comes out of its activity's picture (emit.mbt), the viewer's own flies in from the composer the
// frame it is sent (flight.mbt), what was there as the chat opened fades in all at once. Over it, the way to its end
// (⌘↓) and to what waits to be decided.

///|
/// Chat `r`'s list (its view `v`, `read` its entries), in its pane; `room` what the composer takes of the pane's foot.
pub fn chat_list(
  c : @ui.Ctx,
  src : Source,
  r : ChatRef,
  v : ChatView,
  read : Array[Entry],
  room : Double,
  core : Core,
) -> Unit {
  let key = list_key(r)
  let draft = r.station + ":" + r.session
  let parts = chat_parts.val
  let lf = list_frame(
    c,
    r,
    v,
    read,
    key~,
    draft~,
    rise_ms=@sf.enter_ms,
    history_fade=true,
    top=list_top,
    in_front=(parts.in_front)(),
  )
  let (rd, rk, em, turns, list, keys, flight) = (lf.rd, lf.rk, lf.em, lf.turns, lf.list, lf.keys, lf.flight)
  let n = list.length()
  // a message gone to, flashing (a notification's): a ground under its row coming in and going
  let lit = (rd.flash, flash_of(c, rd, rd.flash))
  // the room agents' lines left, less what has come in since (under the rows, over the composer's room)
  act_rooms(c, rd, key, keys)
  let floor = floor_of(c, rd, key, keys)
  let side = row_side(c)
  let list_box = c.box(style=chat_list_box, ty=lf.carry.unwrap_or(0.0), fn() {
    c.list(
      key,
      n,
      chat_row_est,
      fn(i) {
        let e = list[i]
        let after_top = i > 0 && list[i - 1] is Top
        let joined = match e {
          Said(m) => m.joined
          Out(o) => o.joined
          _ => false
        }
        let top = if e is Top || e is Foot || after_top {
          0.0
        } else if joined {
          joined_gap
        } else {
          list_gap
        }
        let mk = key + "\u{1}" + keys[i]
        match e {
          Top => c.box(style=@ui.style(h=Fixed(list_top)), fn() {  }) |> ignore
          Foot => c.box(style=@ui.style(h=Fixed(room + list_foot + floor)), fn() {  }) |> ignore
          Working(a) => {
            // coming in, its room opens (220 ms, the ease out) as it fades in and grows from its picture; its turn
            // over, it stays a moment and fades (Activity)
            let open = @motion.anim(c, "open/" + mk, 1.0, global=true)
            if rd.fresh.contains(keys[i]) {
              rd.fresh.remove(keys[i])
              open.snap(0.0)
              let at = turns.started_at(keys[i])
              open.animate(1.0, @motion.tween(working_turn_ms, ease=Out), start_at?=if at >= 0.0 { Some(at) } else { None })
            }
            let leaving = match rd.linger.get(a.key) {
              Some(l) => l.leaving
              None => false
            }
            let fade = @motion.animate(c, "fade/" + mk, if leaving { 0.0 } else { 1.0 }, spec=@motion.tween(linger_out_ms))
            let p = open.get()
            rd.act_whole[keys[i]] = p >= 1.0 && !open.moving()
            let here = here_of(r, v, rk, turns, em, None, core)
            @motion.reveal(c, mk, p, fn() {
              let ri = row_box(c, side, top, fn() { activity_row(c, src, here, a, em, rk, leaving) })
              @motion.keyed(c, ri, mk, exit=@motion.trans(fade=0.0, spec=@motion.tween(leave_ms)))
              // pushed down by what comes in above it, it glides there, not while its picture is away flying
              if !lf.older_came && flight is None && !emit_away(em, a.key) {
                @motion.layout(c, ri, mk, spec=@motion.spring(stiffness=300.0, threshold=1.0), listed=false)
              }
              c.look(ri, @ui.look(alpha=p * fade, scale=0.5 + 0.5 * p, ox=(side + 9.0) / c.width, oy=0.5))
            })
          }
          _ => {
            // the row words sent go to: its bubble flies there from the composer
            let flies = flight_takes(draft, keys[i])
            match flight {
              Some(f) if flies => flight_placed(c, f)
              _ => ()
            }
            let here = here_of(r, v, rk, turns, em, if flies { flight } else { None }, core)
            let ri = row_box(c, side, top, fn() {
              // (where a message out of a picture comes in over it: emit.mbt)
              if keys[i] == em.out_key {
                @motion.measure(c, c.box(fn() {  }), "emit-out/" + rk + "/" + keys[i])
              }
              match e {
                Said(m) if m.ts == lit.0 && lit.1 > 0.0 && !(m.mine && m.text != "") => {
                  let g = c.layer(fn() { c.box(style=flash_ground, fn() {  }) |> ignore })
                  c.look(g, @ui.look(alpha=lit.1))
                }
                _ => ()
              }
              entry_row(c, src, here, e)
            })
            match flight {
              Some(_) if flies => {
                // flown in, it does not rise in as well
                rd.known[keys[i]] = true
                rd.fresh.remove(keys[i]) |> ignore
              }
              // the rows above go up with the words
              Some(f) if f.placed =>
                @motion.layout(c, ri, mk, listed=false, screen=true, drive=flight_up(flight_p(c, f), f.desk))
              // what was sent from here not in the chat yet, pushed down by a message coming in over it out of a
              // picture: it glides there, as an agent's activity does
              None if e is Out(_) && em.current is Some(_) =>
                @motion.layout(c, ri, mk, spec=@motion.spring(stiffness=300.0, threshold=1.0), listed=false)
              _ => ()
            }
            // what leaves the chat from the outbox fades, not what was sent from here and is now the core's
            match e {
              Out(o) if !local_sent(o) =>
                @motion.keyed(c, ri, mk, exit=@motion.trans(fade=0.0, spec=@motion.tween(leave_ms)))
              _ => @motion.keyed(c, ri, mk)
            }
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
                let at = turns.started_at(keys[i])
                a.animate(1.0, @motion.tween(@sf.enter_ms, ease=@sf.ease_out), start_at?=if at >= 0.0 { Some(at) } else { None })
                rd.rises[keys[i]] = a
              }
            }
            match rd.rises.get(keys[i]) {
              Some(a) => {
                let p = a.get()
                if !a.moving() && p >= 1.0 {
                  rd.rises.remove(keys[i]) |> ignore
                } else {
                  c.look(ri, @ui.look(alpha=p, dy=@sf.enter_rise * (1.0 - p)))
                }
              }
              None => ()
            }
            // what was there as it came into the list fades in, all at once (useHistoryFade)
            match rd.history.get(keys[i]) {
              Some(a) if a.moving() => c.look(ri, @ui.look(alpha=a.get()))
              Some(_) => rd.history.remove(keys[i]) |> ignore
              None => ()
            }
          }
        }
      },
      stick_end=true,
      // what comes at the end while it follows is glided after, half a second after it was put in place, not while
      // words sent fly (they put the list in place)
      glide_on_growth=lf.glides && flight is None,
    )
    |> ignore
    let la = list_after(
      c,
      src,
      r,
      v,
      lf,
      top=list_top,
      lead=unread_lead,
      bar=bar_foot,
      room~,
      finding=find_chat() == chat_key(r),
      on_found=fn(rd) { rd.found_centre = true },
      find_around~,
    )
    // the way to the newest: away from its end, or short of the chat's end
    to_latest(c, src, r, v, la.away || v.newer, room)
    // what waits to be decided and does not show: a bell over the way to the end
    rd.ask = to_ask(c, r, v, la.ask_rows, la.info, la.away || v.newer, room)
    // the picture flying out of an activity to its message and back, over the list
    emit_flyer(c, rk, em, v, src, r)
  })
  // (a new chat's first words' row laid out in this build: where the list is to start from is measured now)
  if lf.carry is None {
    c.look(list_box, @ui.look(alpha=0.0))
  }
}

///|
/// Where a row of chat `r`'s list is, and how it moves there.
fn here_of(
  r : ChatRef,
  v : ChatView,
  rk : String,
  turns : Turns,
  em : Emits,
  flight : SendFlight?,
  core : Core,
) -> MessageHere {
  {
    station: r.station,
    session: r.session,
    view: v,
    go: Some(fn(seq) { @sfbase.go_to(r, seq) }),
    inline: false,
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
  if c.clicked(id) && shown && !coming {
    if !v.newer {
      c.list_to_end(list_key(r))
    } else {
      match v.thread {
        Some(th) => {
          let station = r.station
          c.tell("chat-jump", fn() {
            act(src, @sf.t("web-main.chat.toLatest"), "", "chat.latest", {
              "station": Json::string(station),
              "thread": Json::number(th),
            })
          })
        }
        None => ()
      }
    }
  }
  if !coming {
    c.cursor(id, Hand)
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
  let asks = if v.archived || v.thread is None { [] } else { v.asks }
  let shown = asks.length() > 0 && !asks_in_view(ask_rows, info)
  let look = match @motion.presence(c, "chat-ask", shown, enter=float_trans(), exit=float_trans()) {
    Some(l) => l
    None => return shown
  }
  let id = c.id("chat-ask")
  c.cursor(id, Hand)
  if c.clicked(id) && shown {
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
/// Which of each chat's asks the bell goes to next (by the chat's key).
let ask_turns : Map[String, Int] = {}

///|
/// What ⌘F last asked the window moved about (`chat.around`), once (-1 none).
let find_around : Ref[Double] = Ref(-1.0)

///|
/// The picture flying out of an activity to its message and back (useEmissions): the agent's, ringed, where emit.mbt
/// has it, drawn only.
fn emit_flyer(c : @ui.Ctx, rk : String, em : Emits, v : ChatView, src : Source, r : ChatRef) -> Unit {
  let (x, y, sx, sy) = match emit_flight(c, rk, em, v.agents.map(fn(a) { a.key })) {
    Some(f) => f
    None => return
  }
  let a = match em.current {
    Some(t) => v.agents.iter().find_first(fn(a) { a.key == t.agent })
    None => None
  }
  let (maker, runtime, waiting) = match a {
    Some(a) => (a.maker, a.runtime, a.wait is Some(_))
    None => ("", "", false)
  }
  let here = { station: r.station, session: r.session, view: v, go: None, inline: false, list: None, core: None }
  c.layer(fn() {
    let b = c.box(style=activity_face, fn() {
      agent_avatar(c, src, here, "flyer", maker, runtime, "", "")
      c.layer(fn() { work_ring(c, waiting) }) |> ignore
    })
    c.look(b, @ui.look(dx=x - ring_room, dy=y - ring_room, sx~, sy~))
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
/// What the list keeps of its own, let go (the package's reset).
fn list_reset() -> Unit {
  ask_turns.clear()
  find_around.val = -1.0
}

///|
/// How far the rows stand in from the pane's sides: the column 760 wide at most in its middle, 40 in at least
/// (session.css.ts chatList).
fn row_side(c : @ui.Ctx) -> Double {
  dmax(row_side_least, (c.width - chat_column_w) / 2.0)
}

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
/// What leaves the list (an agent's line, what goes from the outbox) fades this long.
let leave_ms : Double = 200.0

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
let joined_gap : Double = 4.0

///|
/// The list's room over its first row (under the chat's bar: 45, and 24), under its last (24, over the composer's
/// room), and where the unread line goes under its top (about four lines of what came before it in view: 4 × 23).
let list_top : Double = 69.0

///|
let list_foot : Double = 24.0

///|
let bar_foot : Double = 45.0

///|
let unread_lead : Double = 92.0

///|
/// The round buttons over the list (chatToBottom): 32 across, 6 in from the send button's side, 12 over the composer's
/// room; the bell 8 over the way to the end when both show; their icon 16; how long they come and go.
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
/// A row's room (its node): in from the pane's sides to the column (`side` each), `top` over it.
fn row_box(c : @ui.Ctx, side : Double, top : Double, body : () -> Unit) -> Int {
  c.box(style=row_column, fn() {
    if top > 0.0 {
      c.box(style=@ui.style(h=Fixed(top)), fn() {  }) |> ignore
    }
    c.box(style=row_line, fn() {
      c.box(style=@ui.style(w=Fixed(side)), fn() {  }) |> ignore
      c.box(style=row_middle, body) |> ignore
      c.box(style=@ui.style(w=Fixed(side)), fn() {  }) |> ignore
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
/// A message gone to, its ground (msgFlash): the accent's, round, out past its row's room.
// kept across runs: a value (no field of it changes)
let flash_ground : @ui.Style = @ui.css("w=Full h=Full radius=Xl bg=AccentBg").then(@sf.outset(8.0))

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
let float_count : @ui.TextStyle = @ui.text_style(size=Xs, weight=Medium, color=Fg, wrap=false)

///|
/// Chat `r`'s pane (ChatShown): its list running on under the composer (or, before its view is read, what waits for
/// it), `over` it (the bar), and the composer at its foot (composer.mbt chat_composer: the room it takes the list's
/// foot, among what the app still draws over the list, Pages.chat_layers, with what is let go over the pane, `pane`);
/// the words sent, as typed, till their row is in the list, and the files sent with them, over all of it.
pub fn chat_talk(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, pages : Pages, pane : Int, over : () -> Unit) -> Unit {
  let (view, read, error) = view_of_chat(src, r)
  let draft = r.station + ":" + r.session
  let room = composer_room(c, draft)
  match view {
    Some(v) => {
      latest_key(c, src, r, v)
      chat_list(c, src, r, v, read, room, (pages.core)(src, w))
    }
    None => {
      // (a chat just made from a new chat is the core's own: nothing breathing while its first view comes)
      if error is Some(_) || !new_chat_made(c, r) {
        @sf.waiting(c, shape=Messages, error=match error {
          Some(e) => @sf.t("android-chat.chat.unreadable", args=[("error", text(Some(e), "message"))])
          None => ""
        })
      }
      flight_frame(c, draft)
    }
  }
  over()
  // come to from a new chat: what it showed fading under the composer (switch.mbt)
  if view is Some(_) {
    switch_veil(c)
  }
  // a row of the 文件 tab carried over the pane: frosted under the composer (chat_layers.mbt)
  if view is Some(_) {
    drop_hint(c, pane)
  }
  c.layer(fn() {
    c.spacer()
    chat_composer(c, src, w, pages, r, view)
  })
  |> ignore
  // over it, what is picked in the messages; a row let go over the pane, into the draft
  if view is Some(_) {
    chat_layers(c, src, r, draft, pane, room)
  }
  chat_drop(c, src, r.station, draft, pane)
  flight_waiting(c, draft)
  flight_files(c, draft)
}

///|
/// Whether chat `r` was just made from a new chat, its page still leaving or its first words still carried.
fn new_chat_made(c : @ui.Ctx, r : ChatRef) -> Bool {
  match fresh.became {
    Some(b) if b == r => new_leave(c).moving() || flight_carried(r.station + ":" + r.session)
    _ => false
  }
}

///|
/// ⌘↓ (chat.latest): the list to its end, following it again; short of the chat's end, its latest page.
fn latest_key(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView) -> Unit {
  let prefs = (src.topic)("prefs", {}).value
  if @settings.action_pressed(c, prefs, "chat.latest") {
    if !v.newer {
      c.list_to_end(list_key(r))
    } else {
      match v.thread {
        Some(th) => {
          let station = r.station
          c.tell("chat.latest", fn() {
            (src.call)("chat.latest", { "station": Json::string(station), "thread": Json::number(th) }, fn(_) {  })
          })
        }
        None => ()
      }
    }
  }
}
