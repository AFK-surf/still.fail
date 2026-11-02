// A chat, read (ember apps/android chat/screens/Chat.kt ChatScreen, Messages; ui/Follow.kt): its bar over its messages
// (back, the title, its people and its agents' marks with the station they run on, "…"), the messages as the core's
// `chat` view gives them, newest at the bottom, the list following its newest while it is at its end and "jump to
// the newest" over the composer's room otherwise; the page before loaded as the reader nears the top, what is in view
// staying put. While the chat is read the first time, the messages to come in their bones (the library's Waiting), what is
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
/// Where the chat's bar ends, from the list's top (the list runs on under it), and what the list keeps over its first
/// row: 14 under the bar (Chat.kt).
fn bar_foot() -> Double {
  status_top() + chat_bar_h
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
  // (named to know where it is, not pressed: what is pressed in it is what holds it's)
  let page = c.id("chat/page")
  // words dragged in from another app and let go anywhere on it but a field (a field takes them where they were let
  // go): into the composer's field at its caret, as a paste's; not an archived chat's, whose composer a press does not
  // open either
  // files from this machine's Finder let go anywhere on it but another field, where it is a station: into the draft by
  // their station and path, as a row of the 文件 tab put there (its composer takes them, files_taken); elsewhere as
  // words, as above
  if !(view is Some({ archived: true, .. })) && @sfbase.finder_by_station() {
    match c.paths_into(page, @sfpages.composer_field_key) {
      Some(paths) =>
        for d in @sfbase.finder_dragged(src, paths) {
          @sfbase.files_into(draft_key(r), d)
        }
      None => ()
    }
  }
  if !(view is Some({ archived: true, .. })) {
    c.words_into(page, @sfpages.composer_field_key)
  }
  // over the navigation bar (ChatHost.kt: windowInsetsPadding(keyboard.union(navigationBars)))
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, pb=nav_foot(), id=page, taps=false, points=true, fn() {
    match view {
      None => {
        // until the core has it, already a chat's page: its bar with the title it was opened by (a row's, a new
        // chat's), the messages to come in their bones
        bar_frame(c, r.title, fn() {  }, fn() {  }, false)
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
        if failed is Some(_) || !@sfbase.new_chat_made(c, r) {
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
        // coming to need the viewer while open, felt (feel.mbt)
        @sfbase.feel_needed(c, r, v)
        // its messages: the pages' one list, laid out by its width (sfpages chat_list.mbt), under the bar, over the
        // composer's room
        @sfpages.chat_list(
          c,
          src,
          r,
          v,
          list,
          chat_foot_room(c, r, Some(v)),
          settings_core(src, w),
          top=list_top(),
          lead=unread_lead(),
          bar=bar_foot(),
          foot=list_foot(),
        )
        let foot = c.layer(fn() { chat_foot(c, src, w, r, Some(v)) })
        // (over the viewer's picture as it flies from the list or back into it)
        over_flight(c, foot)
        // words sent, as typed, until their row is in the list (flight.mbt)
        flight_waiting(c, draft_key(r))
        // and the files sent with them, from their tiles to their places (flight.mbt)
        flight_files(c, draft_key(r))
        // the bar over all of it (@ui.Stratum's Bar): what flies to the list goes under it, as the list does
        let bar = c.layer(fn() { chat_bar(c, src, w, r, v) })
        c.stratum(bar, Bar)
        over_flight(c, bar)
        // a passage picked: its handles and its bar over the list (pick.mbt)
        pick_layer(c, src, r)
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
/// How far a row new to the list comes up as it fades in (Chat.kt rise: 14, over its turn's 320 ms, the standard
/// curve).
let rise_dy : Double = 14.0

///|
/// A chat opened over Home from the start at its message `seq`, as a notification opens it; `held`: its flash kept at
/// its peak (screenshots of it).
pub fn open_chat_at(r : ChatRef, seq : Double, held? : Bool = false) -> Unit {
  @sfbase.history_push()
  flash_held.val = held
  go_to(r, seq)
  app.nav.push(Chat(r))
}

///|
/// The chat left (its page gone): the core told it shows no more, and where it was left (`chat.place`: the message
/// at the top, none at its end). Never with Source.readonly.
fn chat_left(src : Source, r : ChatRef) -> Unit {
  let k = r.station + "\u{1}" + r.session
  match (chat_kept(r), readings.get(k)) {
    (Some(v), Some(rd)) if !src.read_only => {
      (src.call)("client.focus", { "left": focus_chat(r, v, None) }, fn(_) {  })
      match v.thread {
        Some(_) if rd.placed => tell_place(src, r, v, rd)
        _ => ()
      }
    }
    _ => ()
  }
  pick_clear()
  readings.remove(k)
  // what holds the chat's thread at the core with it (its jobs in the bar and their sheets, the images beside one
  // opened from it): while any is held the core keeps the thread's window as first read, and the chat opened again
  // where it was first opened, not where it was left (views.ts: chatJobs and imageNear are of the chat's topic)
  (src.leave)("chat", chat_params(r))
  (src.leave)("chatJobs", chat_params(r))
  (src.leave)("chatJobs", chat_jobs_summary_params(r))
  // what its agents' lines and its jobs' sheets read: their work as it goes, their logs as they grow
  @sfbase.let_go(src, @sfbase.chat_scope(r.station, r.session))
  @sfbase.let_go(src, @sfbase.jobs_scope(r.station))
  // what its agents and other chats' wrote each other, read for its sheet: let go if it was (held only once opened)
  match dui.letters_held.get(k) {
    Some(th) => {
      (src.leave)("chatLetters", letters_params(r, th))
      dui.letters_held.remove(k)
    }
    None => ()
  }
  near_left(src, r.station)
}

///|
/// Which of the chat's asks the bell went to last, by chat (it goes to the next one each time, round again).
let ask_turns : Map[String, Int] = {}

///|
/// How long the bell rises over the way to the end as that comes, and goes back down.
let ask_lift_ms : Double = 200.0

///|
let bar_drop_people : Int = 1

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
      @sfbase.go_back() |> ignore
    }
    c.box(
      w=Px(40.0),
      h=Px(40.0),
      radius=20.0,
      align=ACenter,
      justify=JCenter,
      id=back,
      fn() {
        @sf.icon(c, "chevron-left", size=22.0, color=t.p.accent_text) |> ignore
        // Chat.kt: back, clip(CircleShape).clickable
        @motion.ripple(c, back, 20.0)
      },
    )
    |> ignore
    c.box(dir=Row, w=Fill(1.0), pr=8.0, gap=8.0, align=ACenter, fn() {
      // the title whole beside what follows it while what follows may leave the row for it (chat_bar: its people, then
      // its station's update), cut short only once nothing more may (a name: never cut while something less needed can
      // go)
      c.text(title, size=t.t.title, weight=600, color=t.p.text, wrap=false, line=chat_title_line, w=Cut, keep=true)
      |> ignore
      after()
    })
    |> ignore
    trailing()
    if more {
      c.box(style=bar_key_apart(), fn() {
        if nav_button(c, "more", 18.0, key="chat-more", said=tr("android-chat.info.title")) {
          on_more()
        }
      })
      |> ignore
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
  let jobs = (src.topic)("chatJobs", chat_jobs_summary_params(r))
  let has_jobs = flag(jobs.value, "hasJobs") || items(jobs.value, "jobs").length() > 0
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
  let glass_top = c.box(w=Fill(1.0), glass=@sf.glass_bar(), fn() {
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
        if people.length() > 0 {
          c.box(drop=bar_drop_people, fn() { people_stack(c, src, people, 16.0) }) |> ignore
        }
        for i, a in v.agents {
          // each opens its card (AgentSheet.kt)
          let id = c.id("bar-agent/" + a.key)
          if c.clicked(id) {
            open_agent(src, r, a.key)
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
            // (coming with the room before it, as the keys after it stand apart: bar_key_apart)
            c.box(dir=Row, w=Px((nav_key_side + bar_keys_apart()) * archive_share), justify=JEnd, fn() {
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
          c.box(style=bar_key_apart(), fn() {
            if nav_button(c, "web", 20.0, key="chat-jobs") {
              dui.jobs_all = false
              open_chat_jobs(src, r)
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
      // (a chat of a Slack or Feishu thread alone too: where it is, its agents, the way there: chat_info_body)
      true,
      on_more=fn() { open_info(src, r) },
    )
  })
  // over what runs under it: the scroll bar there keeps clear of it
  c.floats_over(glass_top)
}

///|
/// A station named in a small outlined tag (PageParts.kt StationTag): how it is reached as a dot, its mark, its name.
/// The dot leading it stands in its round end as far in as makes it concentric with it (20 high: its half less the
/// dot's), its words 8 in otherwise.
fn station_tag(c : @ui.Ctx, s : Station) -> Unit {
  let t = @sf.theme()
  c.box(
    dir=Row,
    max_w=104.0,
    pl=if s.via != "" { station_dot_in } else { station_tag_end },
    pr=station_tag_end,
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
        via_dot(c, s.via, via_dot_side, 0.0)
      }
      if @sf.has_station_mark(s.emoji, s.icon) {
        @sf.station_mark(c, s.emoji, s.icon, 12.0, t.p.muted)
      }
      c.box(fn() { c.text(s.name, size=t.t.caption, color=t.p.muted, wrap=false, line=16.0) |> ignore })
      |> ignore
    },
  )
  |> ignore
}

///|
/// The tag's height (its words' 16 and 2 over and under), its words' room at its ends, its dot's side.
let station_tag_h : Double = 20.0

///|
/// Where the dot leading a station's tag stands in its round end (a capsule's: round, @sf.capsule_in's room its half).
let station_dot_in : Double = @sf.capsule_in(station_tag_h / 2.0, via_dot_side, room=station_tag_h / 2.0)

///|
let station_tag_end : Double = 8.0

///|
let via_dot_side : Double = 7.0

///|
/// The station's tag in a chat's bar while no agent is in it (PageParts.kt ChatStationChip): a tap opens its card
/// (Stations.kt openStationPeek).
fn station_chip(c : @ui.Ctx, address : String, s : Station) -> Unit {
  let id = c.id("bar-station")
  if c.clicked(id) {
    @settings.open_station_peek(address, from=Of(id))
  }
  c.box(id~, fn() { station_tag(c, s) }) |> ignore
}

///|
/// How a station is reached (StationLink.css.ts dot, cornerDot): the online green direct, amber through the relay, red
/// offline, grey while it is being reached; ringed in the page's ground on a tile's corner.
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
          c.box(w=Px(inner), h=Px(inner), radius=inner / 2.0, bg=t.p.muted, fn() {  })
          |> ignore
      }
    },
  )
  |> ignore
}

///|
/// At work, as a row says it (Spokes.kt): yellow spokes 10 across stepping round in 12, no disc round them (it showed as
/// a dark rim).
fn at_work_mark(c : @ui.Ctx) -> Unit {
  @sf.spokes(c, 10.0, mark_yellow, box=12.0) |> ignore
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
    // its state on the corner, as every agent's mark has it (sfpages' agent_badge)
    @sfpages.agent_badge(c, a.badge, size, t.p.bg)
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
                c.text(s.name, size=t.t.caption, color=t.p.muted, wrap=false, line=said_line)
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
            c.box(w=Px(m), h=Px(m), fn() { @sfpages.agent_badge(c, a.badge, m, t.p.bg) }) |> ignore
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
/// The chat read the first time (the library's Waiting): its messages to come in their bones, as its list draws them,
/// the first as far under the bar as the list's first row; what could not be read over them in red (the bones still).
fn waiting_messages(c : @ui.Ctx, failed : String?) -> Unit {
  @sf.waiting(c, fn() { @sfpages.chat_messages_sample(c, list_top() - top_bar_h()) }, error=failed.unwrap_or(""))
}

///|
/// MBUI_CHAT_BENCH=1: once the chat is in place, the pages before are brought in (held at its top) until it has 3000
/// messages or no more (a minute at most); then from its end it is scrolled up 600 frames at 40 a frame, and the
/// frames' times are said (CHATBENCH …) and the app ends.
let bench_on : Ref[Int] = { val: -1 }

///|
/// The bar's keys at its end (its archive, its jobs, its "…") as far apart as makes each a press's room across
/// (@sf.keys_apart: 2 with keyboard and mouse, 10 with touch), the room before each.
fn bar_keys_apart() -> Double {
  @sf.keys_apart(size=nav_key_side)
}

///|
fn bar_key_apart() -> @ui.Style {
  @ui.style(row=true, pl=@sf.room_of(bar_keys_apart()))
}
