// A chat's messages as nodes of the window's tree, at rest (chat_list.mbt's chat_list as it stands, its rows'
// half): a page's list (View::scrolls_window) holding a block for each of its rows by the row's key (sfbase's
// Entry::id; what was sent from here going on by the key it was sent as once the core has it: row_keys'), each made
// once as it shows by its kind's row (chat_body_row), every row read through its key as the chat's view changes,
// never made again for that; the room over each row as the one before it says (top_at's), in from the pane's sides as
// the list's width lays it out (row_side), narrow or wide by that width alone.
// Not here, each where it comes in: what moves (a row coming in or going on the list's way, words sent flying in, a
// message coming out of its agent's picture, the room an agent's line leaves; the list's line's), the composer and
// what floats over the list (the bell, 对话目录's button, the way to the newest) and what a message gone to shows of
// it (its flash through each row's `over`, a search's words marked in it) are chat_jump_node's, the page's; what else
// is laid over a row (words picked, the band of one whose menu is open: the overlays' line's), where the list opens (chat_open_place, asked here once as it is made) and what the core is told of
// what is read: those the page's, whether the list is at its foot read of its scroll (Scroll::at_foot_now), which rows
// show and how far down one is, which the list does not say yet.

///|
/// What a chat's list shows for each of its rows (chat_body_rows'): its key, what it is, the room over it.
priv struct ChatBodyRows {
  keys : Array[String]
  rows : Map[String, ChatBodyRow]
}

///|
/// A row of a chat's list: what it is (its entry as the chat's view says it now) and the room over it.
priv struct ChatBodyRow {
  entry : Entry
  gap : ChatBodyGap
}

///|
/// The room over a row (top_at's): none (the list's first, a row under its top's), joined_gap (a message close under
/// the one before), or the gap between messages (list_gap, narrow or wide).
#derive(Eq)
priv enum ChatBodyGap {
  NoGap
  Joined
  Apart
}

///|
/// What a chat's list keeps of its rows' keys as they go (row_keys' Reading's `sent` and `sent_as`), its own: the outbox
/// entry each message of the chat was sent from here as, by its seq; the key each row of the core's that took over
/// what was sent from here goes on by (the key it was sent as). Written only as
/// its keys are worked out (chat_body_rows, in the computed that does it), read by nothing else.
priv struct ChatBodyKept {
  sent : Map[Double, String]
  sent_as : Map[String, String]
}

///|
/// The rows chat view `v`'s entries `all` (the chat's list's: view_of_chat's) show, with what was sent from here the
/// core has not yet (`sending`, as sent: sfbase's sending_now) among them, by their keys: row_keys' keys (the core's
/// message sent from here by its outbox entry's key; what was sent from here, and the core's row that took it over
/// once it came, by the key it was sent as; the rest Entry::id), what is sent from here not in the chat yet after its
/// outbox and before where it stands and its agents' lines (sent_among's, its row before it followed where it is
/// joined), the agents whose card that answers at work after the rest (answered_at's), the room over each (top_at's).
/// Its Top and Foot are the list's room over and under its rows, not rows.
fn chat_body_rows(kept : ChatBodyKept, v : ChatView, all : Array[Entry], sending : Array[@sfbase.LocalSent]) -> ChatBodyRows {
  for o in v.outbox {
    if o.seq >= 0.0 {
      kept.sent[o.seq] = o.id
    }
  }
  for m in v.messages {
    if m.outgoing != "" {
      kept.sent[m.seq] = m.outgoing
    }
  }
  let core_keys = all.map(fn(e) {
    match e {
      Said(m) =>
        match kept.sent.get(m.seq) {
          Some(o) => "o:" + o
          None => e.id()
        }
      _ => e.id()
    }
  })
  let keys = core_keys.map(fn(k) { kept.sent_as.get(k).unwrap_or(k) })
  // what was sent from here: the first of the core's rows of this device's own not there as it was sent (an outbox
  // entry, or a message after the newest there then) takes it over, going on by its key (row_keys')
  let taken_by : Map[String, Bool] = Map([])
  for k in kept.sent_as.values() {
    taken_by[k] = true
  }
  let still : Array[@sfbase.LocalSent] = []
  for l in sending {
    let key = "o:" + l.row.id
    if taken_by.contains(key) {
      continue
    }
    let mut came = false
    for i, e in all {
      let k = core_keys[i]
      let mine = match e {
        Out(_) => true
        Said(m) => m.mine && !m.system && m.seq > l.newest
        _ => false
      }
      if mine && !l.before.contains(k) && !kept.sent_as.contains(k) {
        kept.sent_as[k] = key
        taken_by[key] = true
        keys[i] = key
        came = true
        break
      }
    }
    if !came {
      still.push(l)
    }
  }
  let list : Array[Entry] = []
  let at_keys : Array[String] = []
  // (its Top and Foot no rows: the list's head and foot, View::scrolls_window's; the first row under its Top close
  // under it, as under the room it was)
  let mut top_first = false
  for i, e in all {
    if e is Top && list.is_empty() {
      top_first = true
    }
    if e is Foot || e is Top {
      continue
    }
    list.push(e)
    at_keys.push(keys[i])
  }
  // (what is still on its way: after the outbox, before where it stands, its agents' lines; its row before it followed
  // where it goes close under it, as its row will say)
  if still.length() > 0 {
    let mut at = list.length()
    for i, e in list {
      if e is (State(_, _, _) | Working(_)) {
        at = i
        break
      }
    }
    for j, l in still {
      list.insert(at + j, Out(l.row))
      at_keys.insert(at + j, "o:" + l.row.id)
      if l.row.joined && at + j > 0 {
        match list[at + j - 1] {
          Said(m) if !m.followed => list[at + j - 1] = Said({ ..m, followed: true })
          Out(o) if !o.followed => list[at + j - 1] = Out({ ..o, followed: true })
          _ => ()
        }
      }
    }
  }
  // (an agent whose card what is on its way from here answers: at work from the frame it is sent, under the key its
  // line will have once the core says so (Entry::id), its line coming with the answer, after the agents' lines the
  // core says: sfbase's answered_at, as row_keys has it)
  for a in @sfbase.answered_at(v, list) {
    list.push(Working(a))
    at_keys.push("act:" + a.key)
  }
  let rows : Map[String, ChatBodyRow] = Map([])
  for i, e in list {
    let joined = match e {
      Said(m) => m.joined
      Out(o) => o.joined
      _ => false
    }
    let gap = if (i == 0 && top_first) || (i > 0 && list[i - 1] is Top) {
      NoGap
    } else if joined {
      Joined
    } else {
      Apart
    }
    rows[at_keys[i]] = { entry: e, gap }
  }
  { keys: at_keys, rows }
}

///|
/// Whether a row of entry `e` come among a chat's list's keys comes in (sfbase's row_keys' `comes`; the list says where
/// it is seen): a message the core says was said while the chat shows (Message's `said`), an outbox entry (one from
/// another device of the viewer's; what was sent from here on its own way, as the send's), an agent's line at work
/// (`started`); anything else (a message caught up on or read in, what was said elsewhere, where the chat stands, the
/// unread line) is simply there.
fn chat_body_comes(e : Entry) -> Bool {
  match e {
    Said(m) => m.said
    Out(_) => true
    Working(a) => a.started
    _ => false
  }
}

///|
/// Whether row `b` is what row `a` was: the same room over it and the same entry, an entry the same as the chat's list
/// keeps it (its message, what was said elsewhere, what was sent from here or an agent's line the same one, read again
/// only as it changed: sfbase's chat_read; the rest by what they say). What a row reads of its key (chat_body_row's)
/// changes only so: one row's entry changed, or one more come, none of the others' read again.
fn chat_body_row_same(a : ChatBodyRow, b : ChatBodyRow) -> Bool {
  a.gap == b.gap &&
  (match (a.entry, b.entry) {
    (Top, Top) | (Empty, Empty) | (Line, Line) | (Newer, Newer) | (Foot, Foot) => true
    (Older(x), Older(y)) => x == y
    (Said(x), Said(y)) => physical_equal(x, y)
    (Sent(x), Sent(y)) => physical_equal(x, y)
    (Out(x), Out(y)) => physical_equal(x, y)
    (State(w1, l1, r1), State(w2, l2, r2)) => w1 == w2 && l1 == l2 && r1 == r2
    (Working(x), Working(y)) => physical_equal(x, y)
    _ => false
  })
}

///|
/// The room a row's gap is (top_at's) in a list `w` wide.
fn chat_body_gap_room(gap : ChatBodyGap, w : Double) -> Double {
  match gap {
    NoGap => 0.0
    Joined => joined_gap
    Apart => if w <= chat_narrow_w { list_gap_narrow } else { list_gap }
  }
}

///|
/// What kind of row an entry is drawn as (entry_row's and message_row's cases): what is made again only as a row of
/// one key comes to be another kind (what was sent from here coming to be the core's message).
#derive(Eq)
priv enum ChatBodyKind {
  KTop
  KOlder
  KOlderFailed
  KEmpty
  KLine
  KNewer
  KMine
  KNotice
  KPerson
  KAgent
  KSent
  KState
  KWorking
}

///|
/// What kind of row entry `e` is drawn as.
fn chat_body_kind(e : Entry) -> ChatBodyKind {
  match e {
    Top | Foot => KTop
    Older("") => KOlder
    Older(_) => KOlderFailed
    Empty => KEmpty
    Line => KLine
    Newer => KNewer
    Said(m) =>
      if m.mine {
        KMine
      } else if m.system {
        KNotice
      } else if m.author_kind == "person" {
        KPerson
      } else {
        KAgent
      }
    Sent(_) => KSent
    // (what was sent from here the viewer's own message on its way: one row with what the core's message makes of it)
    Out(_) => KMine
    State(_, _, _) => KState
    Working(_) => KWorking
  }
}

///|
/// What a chat's list keeps of its rows that is theirs, by key, across their blocks being made and let go: which
/// notices are open (notices_open, the old view's), when each said 已复制, each agent's line's words as they steadied.
priv struct ChatBodyKeeps {
  opened : @sf.LiveMap[String, Bool]
  copied : @sf.LiveMap[String, Double]
  steadies : ActivitySteadies
}

///|
/// A chat's messages (chat_list's rows, at rest) in `v`, taking the room it is given: the chat `here` is (its view as
/// it changes, the list's width as it changes: narrow or wide by it), its rows the entries `entries` says as they
/// change (view_of_chat's) with what was sent from here and not in the chat yet (`sending`: sfbase's sending_now),
/// answered with `core` where something is (a login's card, a request's answer); under the chat's bar, `cover` tall
/// (where the bar is drawn to: what hides the list's top, what the list holds what is read under), `room` more over its
/// first row (the list's head, the two together: its top), `foot` under its last, then the composer `composer` builds
/// in the list's foot (its room under the rows as tall as the two are laid out, as the composer changes: at once as
/// yet). In `scroll`,
/// put where `place` asks: where it opens as chat_open_place says (its unread line `lead` under its top, where it was
/// left, else at its end, followed there), and at an unread line come after while it is still at its end; a chat too short to fill what shows at its foot, over the composer (the old
/// list's from_end); the page before asked as it nears its top. `made`, told each row's key and what holds it as its row
/// is made (a block made, or made again as its key comes to be another kind of row). `read`, given `place` and its rows,
/// for what is told the core of what is read (chat_read_node). `to`: the chat it is (none in a list's own tests), its
/// way to the newest in the list's foot over the composer and the message it is told to go to brought in
/// (chat_jump_node's), while `shows` (it is drawn) where the reader is kept for a go-to inside it.
fn chat_body_node(
  v : @view.View,
  src : Source,
  here : MessageNodeHere,
  entries : () -> Array[Entry],
  sending? : () -> Array[@sfbase.LocalSent] = fn() { [] },
  core? : @settings.Core? = None,
  cover? : () -> Double = fn() { bar_foot },
  room? : Double = list_room,
  foot? : () -> Double = fn() { list_foot },
  composer? : (@view.View) -> Unit,
  lead? : Double = unread_lead,
  scroll? : @view.Scroll = @view.Scroll::list(),
  place? : @view.ListPlace[String] = @view.ListPlace::new(),
  keeps? : ChatBodyKeeps = { opened: notices_open, copied: @sf.LiveMap::new(), steadies: ActivitySteadies::new() },
  made? : (String, @view.View) -> Unit = fn(_, _) {  },
  read? : (@view.ListPlace[String], () -> ChatBodyRows) -> Unit = fn(_, _) {  },
  to? : ChatRef,
  shows? : () -> Bool = fn() { true },
) -> @view.View {
  let jump = ChatJump::new()
  // (the list's top: the bar and the room under it, its head; where it opens, where a go-to puts a message and the
  // unread line are counted from it, as before the bar's own edge was told the list)
  let top = fn() { cover() + room }
  let kept : ChatBodyKept = { sent: {}, sent_as: {} }
  // (worked out once as the view, its entries or what is on its way change; the keys only change as rows come, go or
  // are taken over: each row reads its own by its key)
  let rows = @signals.computed(fn(_) { chat_body_rows(kept, (here.view)(), entries(), sending()) }, same=fn(_, _) {
    false
  })
  let keys = @signals.computed(fn(_) { rows.get().keys }, same=fn(a, b) { a == b })
  let width = here.width
  let side = fn() { row_side(width()) }
  // the page before asked of the core as the list nears its top (list_after's: once for each first entry it has, not
  // while the core reads one, nor while it waits after a read that failed: it says when to ask again; asked again
  // where the read failed), chat_grow_rows more each time; not while it stands where a go-to put it (ChatJump's
  // `put`: only once the reader moves it)
  let wants_older = fn() {
    let now = (here.view)()
    now.more && now.older == "" && now.thread is Some(_) && jump.put.get() == 0
  }
  let asked_from : Ref[Double?] = Ref(None)
  // (a read that failed asked again a while after, longer each time it fails again, while it is still wanted)
  let older_fails = Ref(0)
  fn ask_older(grow : Bool) -> Unit {
    let now = @signals.untracked(here.view)
    guard now.thread is Some(thread) else { return }
    let first = match now.first_entry {
      Some(f) => f
      None =>
        match now.messages.get(0) {
          Some(m) => m.seq
          None => -1.0
        }
    }
    guard asked_from.val != Some(first) else { return }
    asked_from.val = Some(first)
    let params : Map[String, Json] = { "station": Json::string(here.station), "thread": Json::number(thread) }
    if grow {
      params["rows"] = Json::number(@sfbase.chat_grow_rows.to_double())
    }
    (src.call)("chat.older", Json::object(params), fn(res) {
      if res is Err(_) {
        asked_from.val = None
        v.at_moment(v.cause_at() + ask_again_ms(older_fails.val), fn() {
          if @signals.untracked(wants_older) {
            ask_older(grow)
          }
        })
        |> ignore
        older_fails.val += 1
      } else {
        older_fails.val = 0
      }
    })
  }
  // the page after asked as the list nears its foot while the window is short of the chat's end (list_after's: once
  // for each last entry it has; asked again where the read failed)
  let wants_newer = fn() {
    let now = (here.view)()
    now.newer && now.thread is Some(_)
  }
  let asked_after : Ref[Double?] = Ref(None)
  let newer_fails = Ref(0)
  fn ask_newer() -> Unit {
    let now = @signals.untracked(here.view)
    guard now.thread is Some(thread) else { return }
    let last = match now.last_entry {
      Some(l) => l
      None =>
        match now.messages.last() {
          Some(m) => m.seq
          None => -1.0
        }
    }
    guard asked_after.val != Some(last) else { return }
    asked_after.val = Some(last)
    (src.call)("chat.newer", { "station": Json::string(here.station), "thread": Json::number(thread) }, fn(res) {
      if res is Err(_) {
        asked_after.val = None
        v.at_moment(v.cause_at() + ask_again_ms(newer_fails.val), fn() {
          if @signals.untracked(wants_newer) {
            ask_newer()
          }
        })
        |> ignore
        newer_fails.val += 1
      } else {
        newer_fails.val = 0
      }
    })
  }
  v.box(fn(o) {
    o.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
    o.scrolls_window(
      scroll,
      fn() { keys.get() },
      est=chat_row_est,
      bar=@ui.tree_scroll_bar(),
      // (what hides its top is the bar alone, as it is drawn: a message whose words start in the room under it is seen,
      // and held where it is (View::read_from). Its bar kept clear of the room too, where it was)
      top_covered=cover,
      bar_clear=fn() { (top(), 0.0) },
      // (its Top, the chat's bar and the room under it, the list's head; its Foot, the list's foot: the room under its
      // rows, then the composer (`composer`), the room under the last row as tall as both are laid out)
      head=fn(h) {
        h.height(By(fn() { Some(top()) })) |> ignore
        made("top", h)
      },
      foot=fn(f) {
        match to {
          Some(r) => {
            chat_to_newest_node(f, src, r, jump, place, here.view, width, here.tips)
            chat_outline_node(f, src, r, jump, here.view, width, here.tips, here.stint)
            chat_ask_node(f, r, src, jump, here.view, fn() { rows.get() }, width, here.tips)
          }
          None => ()
        }
        f.box(fn(g) { g.height(By(fn() { Some(foot()) })) |> ignore }) |> ignore
        match composer {
          Some(build) => build(f)
          None => ()
        }
      },
      follows=fn() { true },
      // (what comes with a way, as row_keys' `comes`: a message the core says was said while the chat shows, an outbox
      // entry, an agent at work; the rest, caught up on, read in or there as the chat opened, simply there: what was
      // said before it was shown moves not, sf/motion.mbt's head)
      comes=fn(k) {
        match rows.get().rows.get(k) {
          Some(r) => chat_body_comes(r.entry)
          None => false
        }
      },
      // (an agent's line gone at its foot leaves its room under the last row, fading where it is: a turn that ends with
      // no reply carries nothing up to let it fall back; what comes next takes that room first. The owner, 2026-11-12;
      // the coordinator of the migration, 2026-11-13: mbui's View::scrolls_window `leaves_room`)
      leaves_room=fn(k) { k.has_prefix("act:") },
      // (what shows held by what is read: not by the row saying the page before comes, which what comes in is put in
      // under, going on down with what shows)
      holds=fn(k) { k != "older" },
      from_end=true,
      place~,
      near_top=(1.0, wants_older, fn() { ask_older(true) }),
      near_foot=(1.0, wants_newer, ask_newer),
      fn(slot, k) { chat_body_row(slot, src, here, k, rows, side, top, core, keeps, made, jump) },
    )
    |> ignore
  })
  |> ignore
  // (put in place once, as it is made: chat_open_place's; else at its end, where it is made; at a message the chat is
  // to go to first, chat_goes_to's)
  let chat = here.station + "\u{1}" + here.session
  let opens = @signals.untracked(fn() {
    chat_open_place(rows.get(), (here.view)(), @sfbase.kept_places.get(chat), v.pixel_scale(), cover(), top(), lead)
  })
  if opens is Some((k, offset)) && !@sfbase.go_tos.contains(chat) {
    place.bring(k, offset~)
  }
  match to {
    Some(r) => {
      chat_goes_to(v, src, r, jump, place, fn() { rows.get() }, here.view, cover, top, fn() { ask_older(false) }, shows)
      // (over the list: a passage a mouse picked in a message quoted by its pill)
      chat_quote_node(v, src, r, here, fn() { rows.get() })
      // (a picture's 复制图片 chosen in its menu: read whole and put on the clipboard)
      menus_image_node(v)
      // something sent from here into the chat (words, an answer picked on a card: sfbase's sent_here_told), read up
      // the list: it goes to its end as it is sent (where the window is short of the chat's end, as its latest page,
      // asked by the send, comes in: chat_jump_node's)
      v.reacts(
        fn() { @sfbase.sent_here_count(chat) },
        fn(_) {
          if @signals.untracked(here.view).newer {
            jump.latest = true
          } else if !scroll.at_foot_now() {
            place.to_end()
          }
        },
        at_start=false,
      )
      // ⌘↓ (chat.latest, the keymap's Chat with the field empty): as the way to the newest is pressed
      v.on_action("chat.latest", fn(_) {
        chat_to_newest(src, r, jump, place, here.view)
        true
      })
      // ⌘G 对话目录, ⌥⇧↑ and ⌥⇧↓ the message a person said before and after the reader's (outline_entries_of's keys;
      // none in a replay of a run from before the outline, Source's `asks_outline`); ⌘G's beside the round button
      // while it shows
      .on_action("chat.outline", fn(_) {
        (src.asks_outline)() &&
        outline_open_keys(src, r, @signals.untracked(here.view), stint=@signals.untracked(here.stint), button?=jump.outline_at)
      })
      .on_action("chat.said.prev", fn(_) { (src.asks_outline)() && said_go(src, r, @signals.untracked(here.view), -1) })
      .on_action("chat.said.next", fn(_) { (src.asks_outline)() && said_go(src, r, @signals.untracked(here.view), 1) })
      |> ignore
    }
    None => ()
  }
  // the unread line come after it was made (what came while the app was away, read after the chat opened): there once,
  // as at a chat opened with it, while the list is still at its end and no message is asked to be gone to
  let lined = Ref(@signals.untracked(fn() { rows.get().rows.contains("line") }))
  v.reacts(
    fn() { rows.get().rows.contains("line") },
    fn(has) {
      guard has && !lined.val else { return }
      lined.val = true
      if scroll.at_foot_now() && !@sfbase.go_tos.contains(chat) {
        place.bring("line", offset=@sfbase.kept_place_under(@signals.untracked(top) + lead, @signals.untracked(cover)))
      }
    },
    at_start=false,
  )
  read(place, fn() { rows.get() })
  v
}

///|
/// Row `k` of a chat's list in `slot` (entry_row's, its row's room round it: message_row_frame_node), as its kind's
/// row draws it, reading what it is by its key in `rows` as that changes; made again only as it comes to be another
/// kind. What it shows of being gone to (its flash, a search's words marked in it) as `jump` says.
fn chat_body_row(
  slot : @view.View,
  src : Source,
  here : MessageNodeHere,
  k : String,
  rows : @signals.Computed[ChatBodyRows],
  side : () -> Double,
  list_top : () -> Double,
  core : @settings.Core?,
  keeps : ChatBodyKeeps,
  made : (String, @view.View) -> Unit,
  jump : ChatJump,
) -> Unit {
  let first = @signals.untracked(fn() { rows.get().rows.get(k) })
  guard first is Some(first) else { return }
  // (as the list says it now, told only as it is another (chat_body_row_same): what changed in another row reads
  // none of this one again; one let go as its key goes reads what it last was)
  let now = @signals.computed(fn(_) { rows.get().rows.get(k).unwrap_or(first) }, same=chat_body_row_same)
  let row = fn() { now.get() }
  let entry = fn() { row().entry }
  let top = fn() { chat_body_gap_room(row().gap, (here.width)()) }
  // (the words ⌘F found while its bar is open in this chat, bold in a message's words, each coloured in and the time
  // the reader is at stroked: find_words_in, find_at_in; else a search's in the message it opened the chat at, bold,
  // each stroked: found_all)
  let chat = here.station + "\u{1}" + here.session
  let found = fn() {
    if find_chat() == chat {
      return find_words_in(chat)
    }
    match jump.found.get() {
      (at, marked) if at == k => marked
      _ => []
    }
  }
  let found_at = fn() -> Int? {
    guard find_chat() == chat else {
      return if jump.found.get().0 == k { Some(@sf.found_all) } else { None }
    }
    match entry() {
      Said(m) => Some(find_at_in(chat, m.seq))
      _ => Some(-1)
    }
  }
  // (a message gone to: its row lit across the list, a notice's pill alone)
  let over = fn(row : @view.View, key : String) { chat_flash_node(row, key, jump) }
  let pill_over = fn(pill : @view.View, key : String) { chat_flash_node(pill, key, jump, round=true) }
  slot.pick(fn() { chat_body_kind(entry()) }, fn(p, kind) {
    made(k, p)
    // (its words, picked with the pointer, are of its key: a message's quoted by it, chat_quote_node)
    @ui.picked_of(p, k) |> ignore
    let m0 = match @signals.untracked(entry) {
      Said(m) => m
      _ => chat_body_none
    }
    let m = fn() {
      match entry() {
        Said(m) => m
        _ => m0
      }
    }
    let frame = fn(body : (@view.View) -> Unit) { message_row_frame_node(p, k, side, top, body) |> ignore }
    // (a message's: under its flash, its band while its menu shows, right clicked or its ⋯'s, as the row says that)
    let more : Ref[() -> Bool] = Ref(fn() { false })
    let over = fn(row : @view.View, key : String) {
      over(row, key)
      message_menu_band_node(row, key, more)
    }
    match kind {
      KTop => p.box(fn(b) { b.height(By(fn() { Some(list_top()) })) |> ignore }) |> ignore
      KOlder => frame(fn(b) { pages_coming_node(b, fn() { true }) |> ignore })
      KOlderFailed =>
        frame(fn(b) {
          older_failed_node(b, fn() {
            match entry() {
              Older(why) => why
              _ => ""
            }
          })
          |> ignore
        })
      KEmpty => frame(fn(b) { chat_empty_node(b) |> ignore })
      KLine => frame(fn(b) { unread_line_node(b) |> ignore })
      KNewer => frame(fn(b) { pages_coming_node(b, fn() { false }) |> ignore })
      KMine => {
        // (on its way, or the core's message that took it over: one row, its words' node kept as it is taken over)
        let out = fn() -> Outgoing? {
          match entry() {
            Out(o) => Some(o)
            _ => None
          }
        }
        let mine = fn() {
          match entry() {
            Out(o) => outgoing_row(o)
            _ => m()
          }
        }
        // (正在发送 seen once it has been on its way a while, counted from when it was sent, the source's time of day
        // (chat_rows.mbt outbox_row's): that moment on the frames' clock, worked out as the row is made and as when it
        // was sent changes (the core's row taking it over), not read of the source's clock as it is drawn)
        let since = @signals.signal(0.0)
        p.reacts(fn() { out().map(fn(o) { o.created_at }) }, fn(at) {
          match at {
            Some(at) => since.set(p.cause_at() - ((src.now)() - at))
            None => ()
          }
        })
        more.val = mine_said_node(p, src, here, k, side, top, mine, found~, found_at~, share=message_share_of(src, here, mine), over~, out~, since=fn() { since.get() }).menu_on
      }
      KNotice => notice_said_node(p, src, here, k, side, top, m, keeps.opened, keeps.copied, pill_over~) |> ignore
      KPerson =>
        more.val = person_said_node(p, src, here, k, side, top, m, found~, found_at~, share=message_share_of(src, here, m), over~).menu_on
      KAgent =>
        more.val = agent_said_node(p, src, here, k, side, top, m, found~, found_at~, share=message_share_of(src, here, m), core~, over~, code=fn(lang) {
          if lang == "mermaid" {
            Some(fn(b, code) { @sfbase.viz_mermaid_node(b, src, here.station, code, fn() { @sf.theme().p.subtle }, here.tips) })
          } else {
            None
          }
        }).menu_on
      KSent => {
        let s0 = match @signals.untracked(entry) {
          Sent(s) => s
          _ => @sfbase.elsewhere_of({})
        }
        sent_elsewhere_node(p, src, here, k, side, top, fn() {
          match entry() {
            Sent(s) => s
            _ => s0
          }
        })
        |> ignore
      }
      KState => {
        let said = fn() {
          match entry() {
            State(w, l, r) => (w, l, r)
            _ => ("", "", "")
          }
        }
        frame(fn(b) { chat_state_node(b, src, here, fn() { said().0 }, fn() { said().1 }, fn() { said().2 }) })
      }
      KWorking => {
        let a0 = match @signals.untracked(entry) {
          Working(a) => a
          _ => @sfbase.agent_of({})
        }
        working_said_node(
          p,
          src,
          here,
          k,
          side,
          top,
          fn() {
            match entry() {
              Working(a) => a
              _ => a0
            }
          },
          fn() { None },
          keeps.steadies,
        )
        |> ignore
      }
    }
  })
}

///|
/// A message as none: what a row of a message reads where its key says another kind of entry for the moment before it
/// is made again (chat_body_row's).
// kept across runs: a value (no field of it changes)
let chat_body_none : Message = @sfbase.message_of({})

///|
/// What was sent from here as none (chat_body_none's, of an outbox entry).
// kept across runs: a value (no field of it changes)
let chat_body_no_out : Outgoing = {
  id: "",
  text: "",
  words: None,
  attachments: [],
  quotes: [],
  state: "",
  error: "",
  joined: false,
  followed: false,
  seq: -1.0,
  time: None,
  waits: "",
  progress: None,
  uploads: [],
  created_at: 0.0,
  refused: false,
}

///|
/// How long after a read of the pages before or after failed (its `fails`th in a row, from 0) it is asked again: 300 ms,
/// twice as long each time it fails again, 30 s at most.
fn ask_again_ms(fails : Int) -> Double {
  let mut ms = 300.0
  for _ in 0..<fails {
    ms = ms * 2.0
    if ms >= 30000.0 {
      return 30000.0
    }
  }
  ms
}
