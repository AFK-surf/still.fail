// A chat, read (ember apps/android chat/screens/Chat.kt ChatScreen, Messages; ui/Follow.kt): its bar over its messages
// (back, the title, its people and its agents' marks with the station they run on, "…"), the messages as the core's
// `chat` view gives them, newest at the bottom, the list following its newest while it is at its end and "jump to
// the newest" over the composer's room otherwise; the page before loaded as the reader nears the top, what is in view
// staying put. While the chat is read the first time, the messages to come breathing (Waiting.kt Messages), what is
// wrong over them in red.
//
// What the page tells the core of the reader (the chat shown and its end seen: `client.focus`, which marks it read;
// where it was left: `chat.place`) is not said with MBUI_READONLY=1 (Source.readonly): a run on a real account then
// changes nothing in it. The composer at its foot is composer.mbt's.



///|
/// The bar's height (Home's top bar's, bar_h: the two bars' lines meet as the page is swiped back) and the room
/// the list keeps under it; the composer's room at the foot (ChatHost.kt roomForList: a line of words, the capsule's
/// insets, its toolbar and margins) and the list's under it.
let chat_bar_h : Double = bar_h

///|
/// The title's line in the bar (Chat.kt BarFrame: a Text with no line height of its own, 16 on the theme's 1.4em).
let chat_title_line : Double = 16.0 * 1.4

///|
let composer_room : Double = 110.0

///|
/// The list's gap between messages (web mobile --list-gap), and under the viewer's message sent soon after the one
/// before it (`joined`).
let gap : Double = 20.0

///|
let joined_gap : Double = 4.0

///|
fn list_gap() -> Double {
  gap
}

///|
/// Where the chat's bar ends, from the list's top (the list runs on under it), and what the list keeps over its first
/// row: 14 under the bar (Chat.kt); in the wide frame (its picking's bar: pick.mbt) the web's bar's.
fn bar_foot() -> Double {
  if wide_on.val {
    wide_bar_h
  } else {
    status_top() + chat_bar_h
  }
}

///|
fn list_top() -> Double {
  status_top() + chat_bar_h + 14.0
}

///|
/// What the list keeps under its last row over the composer's room: 10 (Chat.kt).
fn list_foot() -> Double {
  10.0
}

///|
/// How far under the list's top the unread line opens: a few lines of what came before it in view (Chat.kt 85).
fn unread_lead() -> Double {
  85.0
}

///|
/// The chat's page.
fn chat_page(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef) -> Unit {
  let t = @sf.theme()
  let (view, list, error) = view_of_chat(src, r)
  // over the navigation bar (ChatHost.kt: windowInsetsPadding(keyboard.union(navigationBars)))
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, pb=nav_foot(), fn() {
    match view {
      None => {
        // until the core has it, already a chat's page: its bar (no title yet), the messages to come breathing
        bar_frame(c, "", fn() {  }, fn() {  }, false)
        let failed = match error {
          Some(e) =>
            Some(
              fill("android-chat.chat.unreadable", [("error", text(Some(e), "message"))]),
            )
          None => None
        }
        // a chat just made from a new chat (its scene leaving, its first words on their way) is the core's own:
        // nothing to read from a station, nothing breathing for the frames until the core's view of it comes
        // (Chat.kt made)
        if failed is Some(_) || !new_chat_made(c, r) {
          waiting_messages(c, failed)
        }
        c.layer(fn() { chat_foot(c, src, w, r, None) })
        |> ignore
        // its first words, as typed, till their row is in the list (flight.mbt; their wait for it counted from now)
        flight_frame(c, draft_key(r))
        flight_waiting(c, draft_key(r))
        flight_files(c, draft_key(r))
      }
      Some(v) => {
        messages(c, src, r, v, list)
        c.layer(fn() { chat_bar(c, src, w, r, v) }) |> ignore
        c.layer(fn() { chat_foot(c, src, w, r, Some(v)) })
        |> ignore
        // words sent, as typed, until their row is in the list (flight.mbt)
        flight_waiting(c, draft_key(r))
        // and the files sent with them, from their tiles to their places (flight.mbt)
        flight_files(c, draft_key(r))
        // a passage picked: its handles and its bar over the list (pick.mbt)
        pick_layer(c, src, r)
        // a link held: its menu (link_menu.mbt)
        link_menu_layer(c)
        // the station's update opened under the bar's word (station_update.mbt)
        station_update_popover(c, src, r.station, v.station_update)
      }
    }
  })
  |> ignore
}


///|
/// The chat's list, its key.
fn list_key(r : ChatRef) -> String {
  "chat/" + r.station + "/" + r.session
}

///|
/// The messages (Chat.kt Messages): the list, put in place once, following its end, the page before brought in near
/// its top; the way to the newest over it.
fn messages(
  c : @ui.Ctx,
  src : Source,
  r : ChatRef,
  v : ChatView,
  read : Array[Entry],
) -> Unit {
  let key = list_key(r)
  let dkey = draft_key(r)
  let lf = list_frame(
    c,
    r,
    v,
    read,
    key~,
    draft=dkey,
    rise_ms=row_rise().0,
    history_fade=false,
    top=list_top(),
    in_front=app_in_front(),
  )
  let (rd, ek, em, turns, list, keys, flight, glides, older_came) = (
    lf.rd,
    lf.rk,
    lf.em,
    lf.turns,
    lf.list,
    lf.keys,
    lf.flight,
    lf.glides,
    lf.older_came,
  )
  let here = { station: r.station, session: r.session, view: v }
  let n = list.length()
  // a message gone to, flashing: its words' bubble (yours) or a ground under its row (flash.mbt's underlay)
  flashing.val = (rd.flash, flash_of(c, rd, rd.flash))
  // a search's words marked in the message it opened the chat at (search_marks.mbt)
  found_marking.val = (rd.found_at, rd.found_words, rd.found_drawn.get())
  find_marking.val = @sfpages.find_words_in(side_key(r))
  found_centre(c, rd, key)
  flash_row.val = None
  let carry = lf.carry
  // the room agents' lines left, less what has come in since (under the rows, over the composer's room)
  act_rooms(c, rd, key, keys)
  let floor = floor_of(c, rd, key, keys)
  let list_box = c.box(w=Fill(1.0), h=Fill(1.0), ty=carry.unwrap_or(0.0), fn() {
    c.list(
      key,
      n,
      90.0,
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
          list_gap()
        }
        match e {
          Top => c.box(h=Px(list_top()), fn() {  }) |> ignore
          Foot => c.box(h=Px(chat_foot_room(c, r, Some(v)) + list_foot() + floor), fn() {  }) |> ignore
          Working(a) => {
            // coming in, its room opens (220 ms, Ease.Out) as it fades in and grows from its avatar; its turn over,
            // it stays a moment and fades (Chat.kt Activity)
            let mk = key + "\u{1}" + keys[i]
            let open = @motion.anim(c, "open/" + mk, 1.0, global=true)
            if rd.fresh.contains(keys[i]) {
              rd.fresh.remove(keys[i])
              open.snap(0.0)
              // from when its turn came (turns.mbt), else now
              let at = turns.started_at(keys[i])
              open.animate(1.0, @motion.tween(working_turn_ms, ease=Out), start_at?=if at >= 0.0 { Some(at) } else { None })
            }
            let leaving = match rd.linger.get(a.key) {
              Some(l) => l.leaving
              None => false
            }
            let fade = @motion.animate(
              c,
              "fade/" + mk,
              if leaving { 0.0 } else { 1.0 },
              spec=@motion.tween(linger_out_ms),
            )
            let p = open.get()
            // (its room read as it was laid out whole, not opening: act_rooms)
            rd.act_whole[keys[i]] = p >= 1.0 && !open.moving()
            @motion.reveal(c, mk, p, fn() {
              let ri = c.box(w=Fill(1.0), pl=row_side(c), pr=row_side(c), pt=top, fn() {
                activity(c, src, here, a, leaving~)
              })
              @motion.keyed(c, ri, mk, exit=@motion.trans(fade=0.0, spec=@motion.tween(200.0)))
              // pushed down by what comes in above it, it glides there (Chat.kt ACTIVITY_GLIDE: spring(1, 300)), not
              // while its avatar is away flying
              if !older_came && flight is None && !emit_away(em, a.key) {
                @motion.layout(c, ri, mk, spec=@motion.spring(stiffness=300.0, threshold=1.0), listed=false)
              }
              c.look(ri, @ui.look(alpha=p * fade, scale=0.5 + 0.5 * p, ox=(row_side(c) + 9.0) / c.width, oy=0.5))
            })
          }
          _ => {
            // the row words sent go to: its bubble flies there from the composer (flight.mbt)
            let flies = flight_takes(dkey, keys[i])
            flying.val = if flies { flight } else { None }
            match flight {
              Some(f) if flies => flight_placed(c, f)
              _ => ()
            }
            let ri = c.box(w=Fill(1.0), pl=row_side(c), pr=row_side(c), pt=top, fn() {
              // (where a message out of an avatar comes in over it: emit.mbt)
              if keys[i] == em.out_key {
                @motion.measure(c, c.box(fn() {  }), "emit-out/" + ek + "/" + keys[i])
              }
              entry_view(c, src, here, e, list)
            })
            flying.val = None
            match e {
              Said(m) if m.ts == flashing.val.0 && flashing.val.1 > 0.0 && !m.system && !(m.mine && m.text != "") =>
                flash_under(c, ri, top, flashing.val.1)
              _ => ()
            }
            match flight {
              Some(_) if flies => {
                // flown in, it does not rise in as well
                rd.known[keys[i]] = true
                rd.fresh.remove(keys[i]) |> ignore
              }
              // the rows above go up with the words (ChatHost.kt sendReflow)
              Some(f) if f.placed =>
                @motion.layout(
                  c,
                  ri,
                  key + "\u{1}" + keys[i],
                  listed=false,
                  screen=true,
                  drive=flight_up(flight_p(c, f), f.desk),
                )
              // what was sent from here not in the chat yet, pushed down by a message coming in over it out of an
              // avatar (where the avatar landed): it glides there, as an agent's activity does
              None if e is Out(_) && em.current is Some(_) =>
                @motion.layout(c, ri, key + "\u{1}" + keys[i], spec=@motion.spring(stiffness=300.0, threshold=1.0), listed=false)
              _ => ()
            }
            // what is new to the list while it is followed rises in (Chat.kt rise: 14 up and from nothing, 320 ms
            // on the standard curve); what leaves the chat from the outbox fades (200 ms), not what was sent from here
            // and is now the core's (LocalSent: its row goes on as the core's)
            let mk = key + "\u{1}" + keys[i]
            match e {
              Out(o) if !local_sent(o) =>
                @motion.keyed(c, ri, mk, exit=@motion.trans(fade=0.0, spec=@motion.tween(out_leave_ms)))
              _ => @motion.keyed(c, ri, mk)
            }
            // (one out of an avatar does not rise in as well)
            let emitted = match e {
              Said(m) => emit_goes(em, m.seq)
              _ => false
            }
            if rd.fresh.contains(keys[i]) {
              rd.fresh.remove(keys[i])
              if !emitted {
                // from when its turn came (turns.mbt), else now
                let a = @motion.Anim::new(0.0)
                let at = turns.started_at(keys[i])
                let (ms, ease, _) = row_rise()
                a.animate(1.0, @motion.tween(ms, ease~), start_at?=if at >= 0.0 { Some(at) } else { None })
                rd.rises[keys[i]] = a
              }
            }
            match rd.rises.get(keys[i]) {
              Some(a) => {
                let p = a.get()
                if !a.moving() && p >= 1.0 {
                  rd.rises.remove(keys[i]) |> ignore
                } else {
                  c.look(ri, @ui.look(alpha=p, dy=row_rise().2 * (1.0 - p)))
                }
              }
              None => ()
            }
            match rd.history.get(keys[i]) {
              Some(a) if a.moving() => c.look(ri, @ui.look(alpha=a.get()))
              Some(_) => rd.history.remove(keys[i]) |> ignore
              None => ()
            }
          }
        }
      },
      stick_end=true,
      // what comes at the end while it follows is glided after (Follow.kt), half a second after it was put in place,
      // not while words sent fly (they put the list in place)
      glide_on_growth=glides && flight is None,
    )
    |> ignore
    let la = list_after(
      c,
      src,
      r,
      v,
      lf,
      top=list_top(),
      lead=unread_lead(),
      bar=bar_foot(),
      room=chat_foot_room(c, r, Some(v)),
      finding=@sfpages.find_chat() == r.station + "\u{1}" + r.session,
      on_found=found_start,
      find_around~,
    )
    let (info, ask_rows, away) = (la.info, la.ask_rows, la.away)
    jump_to_latest(c, src, r, v, rd, away || v.newer)
    // what waits to be decided and does not show: a bell over the way to the end (Chat.kt JumpToAsk)
    rd.ask = jump_to_ask(c, r, v, ask_rows, info, away || v.newer)
    // the avatar flying out of an activity to its message and back, over the list
    emit_flyer(c, ek, em, v)
    chat_bench(c, key, rd, v.more, n)
  })
  // (its row laid out in this build: where the list is to start from is measured now)
  if carry is None {
    c.look(list_box, @ui.look(alpha=0.0))
  }
}

///|
/// How long what leaves the chat from the outbox (sent, or deleted) takes to fade.
pub let out_leave_ms : Double = 200.0

///|
/// How far a row new to the list comes up as it fades in (Chat.kt rise: 14, over its turn's 320 ms, the standard
/// curve).
let rise_dy : Double = 14.0

///|
/// How a row new to the list comes in: 320 ms on the standard curve, from 14 under (Chat.kt rise, the phone's mRise),
/// each its turn as long (listQueue.ts).
fn row_rise() -> (Double, @motion.Ease, Double) {
  (row_turn_ms, Standard, rise_dy)
}


///|
/// A chat opened over Home from the start at its message `seq`, as a notification opens it; `held`: its flash kept at
/// its peak (screenshots of it).
pub fn open_chat_at(r : ChatRef, seq : Double, held? : Bool = false) -> Unit {
  flash_held.val = held
  go_to(r, seq)
  app.nav.push(Chat(r))
}

///|
/// The chat left (its page gone): the core told it shows no more, and where it was left (`chat.place`: the message
/// at the top, none at its end). Never with Source.readonly.
fn chat_left(src : Source, r : ChatRef) -> Unit {
  let k = r.station + "\u{1}" + r.session
  match (read_chats.get(k), readings.get(k)) {
    (Some((_, v, _)), Some(rd)) if !src.read_only => {
      (src.call)("client.focus", { "left": focus_chat(r, v, None) }, fn(_) {  })
      match v.thread {
        Some(_) if rd.placed => tell_place(src, r, v, rd)
        _ => ()
      }
    }
    _ => ()
  }
  composer_left(src, r)
  readings.remove(k)
  // what holds the chat's thread at the core with it (its jobs in the bar and their sheets, the images beside one
  // opened from it): while any is held the core keeps the thread's window as first read, and the chat opened again
  // where it was first opened, not where it was left (views.ts: chatJobs and imageNear are of the chat's topic)
  (src.leave)("chat", chat_params(r))
  (src.leave)("chatJobs", chat_params(r))
  // what its agents and other chats' wrote each other, read for its sheet: let go if it was (held only once opened)
  match dui.letters_held.get(k) {
    Some(th) => {
      (src.leave)("chatLetters", letters_params(r, th))
      dui.letters_held.remove(k)
    }
    None => ()
  }
  near_left(src, r.station)
  read_chats.remove(k)
}

///|
/// The way to the newest (Chat.kt JumpToLatest): over the send button, in line with it, a round capsule floating
/// over the list with ↓ (and, short of the chat's end, how many new messages wait there); it comes up growing and
/// goes the way it came. Tapped, the list glides to its end, following it again; short of the chat's end, the
/// chat's latest page is put in place of what shows.
fn jump_to_latest(
  c : @ui.Ctx,
  src : Source,
  r : ChatRef,
  v : ChatView,
  rd : Reading,
  shown : Bool,
) -> Unit {
  let t = @sf.theme()
  // (whether it shows, said before it may be gone: gone, nothing below is built, and what it was would stay)
  rd.jump = shown
  // it comes up growing and goes the way it came (Chat.kt JumpToLatest, web mJump: from 18 down at 60%; its opacity
  // 180 ms, CSS's ease, the rest 220 on the standard curve; going, 150 and 180), turned back mid-way from where it is
  let look = match
    @motion.presence(
      c,
      "chat-jump",
      shown,
      enter=float_enter(),
      exit=float_exit(),
    ) {
    Some(l) => l
    None => return
  }
  let count = if v.newer && v.unread > 0.0 { Some(v.unread.to_int()) } else { None }
  let id = c.id("chat-jump")
  if c.clicked(id) && shown {
    if !v.newer {
      c.list_to_end(list_key(r))
    } else {
      match v.thread {
        Some(th) =>
          (src.call)(
            "chat.latest",
            { "station": Json::string(r.station), "thread": Json::number(th) },
            fn(_) {  },
          )
        None => ()
      }
    }
  }
  // (in the wide frame its tip, with its keys: the web's Tip over it)
  @sf.tip(c, "chat-jump", id, tr("android-chat.chat.latest"), shortcut="chat.latest")
  let (side, ends) = float_side()
  c.layer(align=AEnd, fn() {
    c.spacer()
    // (in the wide frame right over the send button, the composer's column in the pane's middle: Chat.css.ts)
    c.box(pr=float_right(c), pb=float_foot(c, r, v), fn() {
      let pill = c.box(
        dir=Row,
        h=Px(side),
        min_w=side,
        pl=if count is Some(_) { ends.0 } else { 0.0 },
        pr=if count is Some(_) { ends.1 } else { 0.0 },
        gap=4.0,
        radius=side / 2.0,
        align=ACenter,
        justify=JCenter,
        glass=@sf.glass_floating(),
        shadow=@sf.floating.sigma,
        shadow_color=@sf.floating.color,
        shadow_y=@sf.floating.dy,
        id~,
        fn() {
          @sf.icon(c, "arrow-down", size=side / 2.0, color=t.p.text) |> ignore
          match count {
            Some(n) =>
              c.text(
                fill("android-chat.chat.newMessages", [("n", "\{n}")]),
                size=13.0,
                weight=500,
                color=t.p.text,
                wrap=false,
              )
              |> ignore
            None => ()
          }
        },
      )
      // what it is to a screen reader (Chat.kt JumpToLatest's contentDescription, its count's words with it)
      let latest = tr("android-chat.chat.latest")
      c.semantics(pill, Button, id~, label=match count {
        Some(n) => latest + " " + fill("android-chat.chat.newMessages", [("n", "\{n}")])
        None => latest
      })
      c.look(pill, look)
      // going, only drawn: a tap there goes to the rows under it
      @motion.leaving(c, pill, shown)
    })
    |> ignore
  })
  |> ignore
}

///|
/// The round buttons over the list's foot (the way to the end, the bell): 36 across, a count's pill 10 and 14 in at its
/// ends (Chat.kt JumpToLatest).
fn float_side() -> (Double, (Double, Double)) {
  (36.0, (10.0, 14.0))
}

///|
/// Where they stand from the pane's right: 18 in (Chat.kt).
fn float_right(c : @ui.Ctx) -> Double {
  18.0
}

///|
/// And from its foot: 2 over the composer's room (Chat.kt).
fn float_foot(c : @ui.Ctx, r : ChatRef, v : ChatView) -> Double {
  chat_foot_room(c, r, Some(v)) + 2.0
}

///|
/// How they come and go: growing from 60% and up from 18 under (Chat.kt JumpToLatest, web mJump: its opacity 180 ms,
/// CSS's ease, the rest 220 on the standard curve; going, 150 and 180).
fn float_enter() -> @motion.Trans {
  @motion.trans(fade=0.0, scale=0.6, dy=18.0, spec=@motion.tween(220.0), fade_spec=@motion.tween(180.0, ease=Css))
}

///|
fn float_exit() -> @motion.Trans {
  @motion.trans(fade=0.0, scale=0.6, dy=18.0, spec=@motion.tween(180.0), fade_spec=@motion.tween(150.0, ease=Css))
}

///|
/// Which of the chat's asks the bell went to last, by chat (it goes to the next one each time, round again).
let ask_turns : Map[String, Int] = {}

///|
/// How long the bell rises over the way to the end as that comes, and goes back down.
let ask_lift_ms : Double = 200.0

///|
/// The way to what waits to be decided in the chat (Chat.kt JumpToAsk, web Chat.tsx useAsksShown): its asks whose
/// posts are not all in view (one not loaded counts as not in view), a bell (no words) floating where the way to the
/// end goes, over it while that shows; tapped, the list goes to an ask's post (as a notification's does: go_to), then
/// the next one's, round again. It comes and goes as the way to the end does. None in an archived chat.
fn jump_to_ask(
  c : @ui.Ctx,
  r : ChatRef,
  v : ChatView,
  ask_rows : Array[Int],
  info : @ui.ListInfo?,
  to_end : Bool,
) -> Bool {
  let t = @sf.theme()
  let asks = if v.archived || v.thread is None { [] } else { v.asks }
  let shown = asks.length() > 0 && !asks_in_view(ask_rows, info)
  let look = match
    @motion.presence(
      c,
      "chat-ask",
      shown,
      enter=float_enter(),
      exit=float_exit(),
    ) {
    Some(l) => l
    None => return shown
  }
  let (side, _) = float_side()
  // over the way to the end while that shows, 8 above it (the web's 40 from foot to foot: Chat.css.ts chatToAsk)
  let lift = @motion.animate(c, "chat-ask/lift", if to_end { side + 8.0 } else { 0.0 }, spec=@motion.tween(ask_lift_ms, ease=Standard))
  let id = c.id("chat-ask")
  if c.clicked(id) && shown {
    let k = r.station + "\u{1}" + r.session
    let turn = ask_turns.get(k).unwrap_or(0)
    go_to(r, asks[turn % asks.length()])
    ask_turns[k] = turn + 1
  }
  @sf.tip(c, "chat-ask", id, tr("android-chat.asks.go"))
  c.layer(align=AEnd, fn() {
    c.spacer()
    c.box(pr=float_right(c), pb=float_foot(c, r, v) + lift, fn() {
      let bell = c.box(
        w=Px(side),
        h=Px(side),
        radius=side / 2.0,
        align=ACenter,
        justify=JCenter,
        glass=@sf.glass_floating(),
        shadow=@sf.floating.sigma,
        shadow_color=@sf.floating.color,
        shadow_y=@sf.floating.dy,
        id~,
        fn() { @sf.icon(c, "bell", size=side / 2.0, color=t.p.text) |> ignore },
      )
      // (Chat.kt JumpToAsk's contentDescription)
      c.semantics(bell, Button, id~, label=tr("android-chat.asks.go"))
      c.look(bell, look)
      @motion.leaving(c, bell, shown)
    })
    |> ignore
  })
  |> ignore
  shown
}

///|
/// The least of a chat's title its bar keeps (64), and the order what follows it leaves the bar in short of room: its
/// people, then its station's update.
let bar_title_least : Double = 64.0

///|
let bar_drop_people : Int = 1

///|
let bar_drop_update : Int = 2

///|
/// The bar's frame (Chat.kt BarFrame), the same while the chat is read and once it is: back, the title, what follows
/// it, what is at its end, and "…".
fn bar_frame(
  c : @ui.Ctx,
  title : String,
  after : () -> Unit,
  trailing : () -> Unit,
  more : Bool,
  on_more? : () -> Unit = fn() {  },
) -> Unit {
  let t = @sf.theme()
  // under the status bar (Chat.kt BarFrame: windowInsetsPadding(statusBars), then TopBarHeight, as Home's bar)
  c.box(dir=Row, w=Fill(1.0), pl=4.0, pr=16.0, pt=status_top(), min_h=top_bar_h(), align=ACenter, fn() {
    let back = c.id("chat-back")
    if c.clicked(back) {
      app.nav.pop() |> ignore
    }
    c.box(
      w=Px(40.0),
      h=Px(40.0),
      radius=20.0,
      align=ACenter,
      justify=JCenter,
      id=back,
      fn() {
        @sf.icon(c, "chevron-left", size=22.0, color=t.p.accent) |> ignore
        // Chat.kt: back, clip(CircleShape).clickable
        @motion.ripple(c, back, 20.0)
      },
    )
    |> ignore
    c.box(dir=Row, w=Fill(1.0), pr=8.0, gap=8.0, align=ACenter, fn() {
      // the title as long as there is room for it beside what follows it (weight(1f, fill = false): what follows is
      // measured first, as wide as it is, and the title has what is left), a few words of it at least: short of
      // that, what follows leaves the row as it says (chat_bar: its people, then its station's update)
      let least = dmin(@ui.text_advance(title, size=16.0, weight=600), bar_title_least)
      c.box(style=@ui.style(min_w=Fixed(least)), fn() {
        c.text(title, size=16.0, weight=600, color=t.p.text, wrap=false, line=chat_title_line)
        |> ignore
      })
      |> ignore
      after()
    })
    |> ignore
    trailing()
    if more && nav_button(c, "more", 18.0, key="chat-more", said=tr("android-chat.info.title")) {
      on_more()
    }
  })
  |> ignore
}

///|
/// The chat's bar (Chat.kt ChatBar): its title from the left, then its people, then its agents' marks (the first's
/// tile carrying the station it runs on); its services and jobs, its archive while nothing is left in it, and "…".
/// Frosted glass over the messages, no line under it (the frost alone sets it off).
fn chat_bar(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, v : ChatView) -> Unit {
  let t = @sf.theme()
  let stations = stations_of((src.topic)("stations", { "scope": Json::string(w.id) }).value)
  let station = stations.iter().find_first(fn(s) { s.address == r.station })
  let jobs = (src.topic)("chatJobs", chat_params(r))
  let has_jobs = items(jobs.value, "jobs").length() > 0
  let archive = v.archivable && !v.archived
  // 归档 comes and goes as nothing is left in the chat or something is again (Chat.kt ChatBar: 280 ms, ArchiveEase;
  // fading, from or to 85%, its width from its end)
  let archive_key = "bar-archive/" + r.station + "/" + r.session
  let archive_look = @motion.presence(
    c,
    archive_key,
    archive,
    enter=@motion.trans(fade=0.0, scale=0.85, spec=archive_tween),
  )
  let archive_w = @motion.anim(c, archive_key + "/w", if archive { 1.0 } else { 0.0 }, global=true)
  archive_w.follow(if archive { 1.0 } else { 0.0 }, archive_tween)
  let archive_share = if archive_look is None { 0.0 } else { archive_w.get() }
  let people = if v.people.length() > 5 { v.people[:5].to_array() } else { v.people }
  c.box(w=Fill(1.0), glass=@sf.glass_bar(), fn() {
    bar_frame(
      c,
      v.title,
      fn() {
        if v.agents.length() == 0 {
          match station {
            Some(s) => station_chip(c, r.station, s)
            None => ()
          }
        }
        // its station's update (station_update.mbt)
        c.box(drop=bar_drop_update, fn() { station_update_control(c, src, r.station, v.station_update) }) |> ignore
        if people.length() > 0 {
          c.box(drop=bar_drop_people, fn() { people_stack(c, src, people, 16.0) }) |> ignore
        }
        for i, a in v.agents {
          // each opens its card (AgentSheet.kt)
          let id = c.id("bar-agent/" + a.key)
          if c.clicked(id) {
            open_sheet(c, AgentOf(r, a.key))
          }
          c.box(id~, fn() {
            if i == 0 {
              agent_station_mark(c, a, station)
            } else {
              model_mark(c, a, 22.0)
            }
          })
          |> ignore
        }
      },
      fn() {
        match archive_look {
          Some(look) =>
            c.box(dir=Row, w=Px(34.0 * archive_share), justify=JEnd, fn() {
              let b = c.box(w=Px(34.0), min_w=34.0, h=Px(34.0), fn() {
                if doing("archive/" + r.station + "/" + r.session) {
                  c.box(w=Px(34.0), h=Px(34.0), align=ACenter, justify=JCenter, fn() {
                    @sf.spinner(c) |> ignore
                  })
                  |> ignore
                } else if nav_button(c, "archive", 20.0, key="chat-archive", said=tr("android-chat.archive")) && archive {
                  archive_chat(src, r, v)
                }
              })
              c.look(b, look)
              @motion.leaving(c, b, archive)
            })
            |> ignore
          None => ()
        }
        if has_jobs {
          // a dot when one died lately (red) or a service is started again (amber)
          let alarm = text(jobs.value, "alarm")
          c.box(fn() {
            if nav_button(c, "web", 20.0, key="chat-jobs") {
              dui.jobs_all = false
              open_sheet(c, JobsOf(r))
            }
            if alarm == "fail" || alarm == "restart" {
              c.layer(align=AEnd, fn() {
                c.box(pt=6.0, pr=6.0, fn() {
                  c.box(w=Px(11.0), h=Px(11.0), radius=5.5, bg=t.p.bg, pad=2.0, fn() {
                    c.box(
                      w=Fill(1.0),
                      h=Fill(1.0),
                      radius=3.5,
                      bg=if alarm == "fail" { t.p.red } else { 0xD9962BFFL },
                      fn() {  },
                    )
                    |> ignore
                  })
                  |> ignore
                })
                |> ignore
              })
              |> ignore
            }
          })
          |> ignore
        }
      },
      v.thread is Some(_),
      on_more=fn() { open_sheet(c, Info(r)) },
    )
  })
  |> ignore
}

///|
/// A station named in a small outlined tag (PageParts.kt StationTag): how it is reached as a dot, its mark, its name.
fn station_tag(c : @ui.Ctx, s : Station) -> Unit {
  let t = @sf.theme()
  c.box(
    dir=Row,
    max_w=104.0,
    padx=8.0,
    pady=2.0,
    gap=4.0,
    radius=12.0,
    border=1.0,
    border_color=t.p.line,
    align=ACenter,
    // (StationTag: its name to a screen reader)
    label=s.name,
    fn() {
      if s.via != "" {
        via_dot(c, s.via, 7.0, 0.0)
      }
      if @sf.has_station_mark(s.emoji, s.icon) {
        @sf.station_mark(c, s.emoji, s.icon, 12.0, t.p.muted)
      }
      c.box(fn() { c.text(s.name, size=12.0, color=t.p.muted, wrap=false, line=16.0) |> ignore })
      |> ignore
    },
  )
  |> ignore
}

///|
/// The station's tag in a chat's bar while no agent is in it (PageParts.kt ChatStationChip): a tap opens its card
/// (Stations.kt openStationPeek).
fn station_chip(c : @ui.Ctx, address : String, s : Station) -> Unit {
  let id = c.id("bar-station")
  c.cursor(id, Hand)
  if c.clicked(id) {
    @settings.open_station_peek(address)
  }
  c.box(id~, fn() { station_tag(c, s) }) |> ignore
}

///|
/// How a station is reached (StationLink.css.ts dot, cornerDot): the online green direct, amber through the relay, red
/// offline, a grey ring while it is being reached; ringed in the page's ground on a tile's corner.
fn via_dot(c : @ui.Ctx, via : String, size : Double, ring : Double) -> Unit {
  let t = @sf.theme()
  let inner = size - ring * 2.0
  c.box(
    w=Px(size),
    h=Px(size),
    radius=size / 2.0,
    bg=if ring > 0.0 { t.p.bg } else { 0L },
    align=ACenter,
    justify=JCenter,
    fn() {
      match via {
        "direct" =>
          c.box(w=Px(inner), h=Px(inner), radius=inner / 2.0, bg=t.p.online, fn() {  })
          |> ignore
        "relay" =>
          c.box(w=Px(inner), h=Px(inner), radius=inner / 2.0, bg=0xD9962BFFL, fn() {  })
          |> ignore
        "offline" =>
          c.box(w=Px(inner), h=Px(inner), radius=inner / 2.0, bg=t.p.red, fn() {  })
          |> ignore
        _ =>
          c.box(
            w=Px(inner),
            h=Px(inner),
            radius=inner / 2.0,
            border=1.5,
            border_color=t.p.muted,
            fn() {  },
          )
          |> ignore
      }
    },
  )
  |> ignore
}

///|
/// An agent's state at its mark's corner (Parts.kt AgentStateMark): a 12 disc of the ground, red in it when it wants
/// someone, yellow spokes stepping round at work (Spokes.kt); nothing when done.
fn agent_state_mark(c : @ui.Ctx, badge : String) -> Unit {
  let t = @sf.theme()
  match badge {
    // yellow spokes 10 across stepping round, no disc round them (it showed as a dark rim)
    "run" => @sf.spokes(c, 10.0, mark_yellow, box=12.0) |> ignore
    "block" | "failed" =>
      c.box(w=Px(12.0), h=Px(12.0), radius=6.0, bg=t.p.bg, align=ACenter, justify=JCenter, fn() {
        c.box(w=Px(8.0), h=Px(8.0), radius=4.0, bg=mark_red, fn() {  }) |> ignore
      })
      |> ignore
    _ => ()
  }
}

///|
/// An agent's mark (Parts.kt ModelMark, small, as a list's): its maker's mark on a soft tile, its state on the corner.
fn model_mark(c : @ui.Ctx, a : Agent, size : Double) -> Unit {
  let t = @sf.theme()
  let (ground, line) = mark_ground()
  c.box(w=Px(size), h=Px(size), fn() {
    c.box(
      w=Px(size),
      h=Px(size),
      radius=mark_corner(size),
      bg=ground,
      border=line,
      border_color=t.p.line,
      align=ACenter,
      justify=JCenter,
      fn() { @sf.maker_mark(c, a.maker, a.runtime, mark_logo(size)) |> ignore },
    )
    |> ignore
    if a.badge != "" {
      c.layer(fn() {
        c.box(tx=size - 9.0, ty=size - 9.0, fn() { agent_state_mark(c, a.badge) }) |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The chat's first agent with the station it runs on, one tile (PageParts.kt AgentStationMark): the maker's
/// square, then the station's mark or name; the agent's state on the maker's corner, how the station is reached on the
/// tile's. Until the station is known, the agent's mark alone.
fn agent_station_mark(c : @ui.Ctx, a : Agent, station : Station?) -> Unit {
  let t = @sf.theme()
  let m = mark_side()
  let (ground, line) = mark_ground()
  match station {
    None => model_mark(c, a, m)
    Some(s) =>
      // (AgentStationMark: 「who · station」 to a screen reader)
      c.box(label=a.who + " · " + s.name, fn() {
        c.box(
          dir=Row,
          h=Px(m),
          radius=6.0,
          bg=ground,
          border=line,
          border_color=t.p.line,
          align=ACenter,
          fn() {
            c.box(w=Px(m), h=Px(m), align=ACenter, justify=JCenter, fn() {
              @sf.maker_mark(c, a.maker, a.runtime, mark_logo(m)) |> ignore
            })
            |> ignore
            // the station's part: its mark, or its name kept short (the web's 140, its words .19 of the tile and 1 in)
            let (most, inside, said_line) = station_part_type()
            c.box(max_w=most, padx=inside, align=ACenter, fn() {
              if @sf.has_station_mark(s.emoji, s.icon) {
                @sf.station_mark(c, s.emoji, s.icon, mark_station(), t.p.muted)
              } else {
                c.text(s.name, size=12.0, color=t.p.muted, wrap=false, line=said_line)
                |> ignore
              }
            })
            |> ignore
          },
        )
        |> ignore
        // the agent's state on the maker's corner, how the station is reached on the tile's: each 3 past it
        c.layer(fn() {
          c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), fn() {
            c.box(tx=m - 9.0, ty=m - 9.0, fn() { agent_state_mark(c, a.badge) }) |> ignore
            c.spacer()
            if s.via != "" {
              c.box(tx=3.0, ty=m - 7.0, fn() { via_dot(c, s.via, 10.0, 2.0) }) |> ignore
            }
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
  }
}

///|
/// An agent's mark in the bar: 22 square on the card's ground with a line round it (PageParts.kt), its maker .6 of it,
/// a station's mark 13.
fn mark_side() -> Double {
  22.0
}

///|
fn mark_ground() -> (Int64, Double) {
  let p = @sf.theme().p
  (p.card, 1.0)
}

///|
/// Its corner: 6.
fn mark_corner(side : Double) -> Double {
  6.0
}

///|
fn mark_logo(side : Double) -> Double {
  side * 0.6
}

///|
fn mark_station() -> Double {
  13.0
}

///|
fn station_part_type() -> (Double, Double, Double) {
  (96.0, 5.0, 14.0)
}

///|
/// People overlapping a little, each ringed in the ground they are on (Parts.kt PeopleStack: Avatar(p.id,
/// p.shown.display), `ring` C.bg unless said): laid out side by side, each drawn 5 over the one before it, the first
/// over them all (zIndex(-i)).
fn people_stack(
  c : @ui.Ctx,
  src : Source,
  people : Array[Person],
  size : Double,
  ring? : Int64 = @sf.theme().p.bg,
) -> Unit {
  let step = size + 3.0
  let n = people.length()
  c.box(w=Px(step * n.to_double()), h=Px(step), fn() {
    // the last drawn first, each under the one before it
    for j in 0..<n {
      let i = n - 1 - j
      let p = people[i]
      c.layer(fn() {
        c.box(
          w=Px(step),
          h=Px(step),
          radius=step / 2.0,
          bg=ring,
          tx=(step - 5.0) * i.to_double(),
          align=ACenter,
          justify=JCenter,
          fn() {
            // coloured by their id, lettered by what the bar calls them (the viewer 「你」)
            avatar(c, src, p.id, p.display, p.picture, size)
          },
        )
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A person, round (Parts.kt Avatar): their picture once it is here, their initial on their colour until then.
fn avatar(
  c : @ui.Ctx,
  src : Source,
  id : String,
  name : String,
  picture : String,
  size : Double,
) -> Unit {
  @sf.avatar(c, id, name, if picture != "" { (src.picture)(picture, c.page_stint()) } else { "" }, size)
}

///|
/// The chat read the first time (the library's Waiting: @sf.waiting, its messages): the messages to come breathing,
/// theirs with a picture on the left, the viewer's on the right; what could not be read over them in red (the shapes
/// still).
fn waiting_messages(c : @ui.Ctx, failed : String?) -> Unit {
  @sf.waiting(c, shape=Messages, error=failed.unwrap_or(""))
}

///|
/// MBUI_CHAT_BENCH=1: once the chat is in place, the pages before are brought in (held at its top) until it has 3000
/// messages or no more (a minute at most); then from its end it is scrolled up 600 frames at 40 a frame, and the
/// frames' times are said (CHATBENCH …) and the app ends.
let bench_on : Ref[Int] = { val: -1 }

///|
fn chat_bench(c : @ui.Ctx, key : String, rd : Reading, more : Bool, rows : Int) -> Unit {
  if bench_on.val < 0 {
    bench_on.val = if @ui.env("MBUI_CHAT_BENCH") != "" { 1 } else { 0 }
  }
  if bench_on.val == 0 || !rd.placed {
    return
  }
  rd.bench = rd.bench + 1
  // every frame drawn while it runs (only in the host's bench mode: MBUI_BENCH, which the bench's script sets)
  c.bench_frames(true)
  if rd.bench_phase == 0 {
    if rows != rd.bench_rows {
      rd.bench_rows = rows
      @hostapi.log("CHATBENCH rows=\{rows} after \{rd.bench} frames")
    }
    if more && rows < 3000 && rd.bench < 3600 {
      c.list_scroll_to(key, 0)
      return
    }
    rd.bench_phase = 1
    rd.bench = 0
    c.list_to_end(key, glide=false)
    return
  }
  // settled first (a second), then measured: each frame's build, layout and paint, and its present
  if rd.bench <= 60 {
    return
  }
  if rd.bench > 61 {
    rd.bench_ms.push(c.frame_ms())
    rd.bench_present.push(c.present_ms())
  }
  if rd.bench <= 660 {
    c.list_scroll_by(key, -40.0)
    return
  }
  if rd.bench == 661 {
    let a = rd.bench_ms.copy()
    a.sort_by(fn(x, y) { x.compare(y) })
    let n = a.length()
    let mut sum = 0.0
    let mut slow = 0
    for x in rd.bench_ms {
      sum = sum + x
      if x > 8.0 {
        slow = slow + 1
      }
    }
    let mut psum = 0.0
    for x in rd.bench_present {
      psum = psum + x
    }
    let info = c.list_info(key)
    let rows = match info {
      Some(i) => i.count
      None => 0
    }
    @hostapi.log(
      "CHATBENCH frames=\{n} rows=\{rows} cpu_avg=\{sum / n.to_double()} cpu_p50=\{a[n / 2]} " +
      "cpu_p95=\{a[n * 95 / 100]} cpu_p99=\{a[n * 99 / 100]} cpu_max=\{a[n - 1]} slow(>8ms)=\{slow} " +
      "present_avg=\{psum / n.to_double()}",
    )
    // the bench's end, once its frames are counted and the frame's builds are over (MBUI_CHAT_BENCH runs only)
    c.tell("chat-bench-end", fn() { @hostapi.exit(0) })
  }
}
