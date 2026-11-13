// A chat's row in the chats' lists (still.fail web/src/Sidebar.tsx ChatRow, ArchiveButton, Rename.tsx TitleInput;
// web/src/mobile/Home.tsx ChatRow, SwipeArchive, useRowMenu, useRowArchive; Sidebar.css.ts navSession…, mobile/Home.css.ts
// mChatRow…): one row in every tier, the web's desktop row with a mouse and its phone row with a finger. Its state's
// mark before its title (bolder while something in it is unread), its station's mark, then where it stands or the
// last thing said, who is in it at the second line's end; pressed, its chat (where the shell has it). With a mouse:
// pointed at, its time in that place and 归档 at its top right; right clicked, its menu at the pointer; renamed in
// place. With a finger: 66 high and in the phone's type; held, its time, and held long its menu; a chat is swiped left
// to archive it. The menu is the presenters' (@sf.menu): 固定,
// 重命名, 保留, 复制会话链接, 转到频道, 归档, 分享给其他 workspace, 分享图片, each where the chat has it.
//
// One mark for one meaning everywhere (the user, 2026-10-28: 「agent 各种颜色和形状的点很混乱」).

///|
/// What the rows keep: the row whose title is being written in place (a mouse's 重命名, its key; "" none) and its field,
/// whether the field had the keyboard last frame (it losing it ends the rename); the row whose menu is open and the
/// presenter it is (lit meanwhile); the rows swiped off to be archived, until they have gone; each swiped row's being
/// past its line as last felt, and the press whose menu was last felt.
priv struct Rows {
  mut rename_for : String
  mut rename_seen : Bool
  mut rename_opened_at : Int
  rename_field : @ui.Field
  mut menu_for : String
  mut menu_serial : Int
  swiped_off : Map[String, Bool]
  felt_past : Map[String, Bool]
}

///|
let rows : Rows = {
  rename_for: "",
  rename_seen: false,
  rename_opened_at: -1,
  rename_field: @ui.Field::new(),
  menu_for: "",
  menu_serial: -1,
  swiped_off: {},
  felt_past: {},
}

///|
fn chat_rows_reset() -> Unit {
  match row_primed.val {
    Some(reader) => { row_primed.val = None; reader.cancel() }
    None => ()
  }
  row_held.val = (0, false)
  row_left.val = ("", false)
  row_left_said.set("")
  row_renaming.set("")
  rows.rename_for = ""
  rows.rename_seen = false
  rows.rename_opened_at = -1
  rows.rename_field.set("")
  rows.menu_for = ""
  rows.menu_serial = -1
  rows.swiped_off.clear()
  rows.felt_past.clear()
  match chat_menu_waits.val {
    Some(w) => w.end()
    None => ()
  }
  chat_menu_waits.val = None
}

///|
/// How long a finger holds a row before its time shows.
pub let hold_ms : Double = 450.0

///|
/// A row's chat as a page's.
fn row_ref(item : ChatItem) -> ChatRef {
  { station: item.station, session: item.session, title: item.title, station_name: item.station_name }
}

///|
/// Whether `item`'s row has its menu open (its ground stays lit, its time shown, meanwhile).
fn row_menu_open(item : ChatItem) -> Bool {
  rows.menu_for == @sfbase.row_name(item) && @sf.presented_drawn_of(rows.menu_serial)
}

///|
/// What its station has not answered yet of a chat's pin, rename or archive (the core's `doing`, Sidebar.tsx
/// useDoingState, mobile/Home.tsx useDoing): under way, or why it failed a moment ago.
fn row_busy(src : Source, item : ChatItem) -> Bool {
  core_doing(src, row_calls, [("station", item.station), ("session", item.session)])
}

///|
fn row_failed(src : Source, item : ChatItem) -> String? {
  core_failed(src, row_calls, [("station", item.station), ("session", item.session)])
}

///|
// kept across runs: a table, never written
let row_calls : Array[String] = ["chat.pin", "chat.rename", "chat.archive"]

///|
/// A row let go without opening its chat (a scroll, a hold): release only the read made by this press.
fn unprime(src : Source, r : ChatRef, reader : @sfbase.TopicLease?) -> Unit {
  if !src.read_only && !readings.contains(r.station + "\u{1}" + r.session) {
    @sfbase.chat_inputs_left_from(src, r)
  }
  match reader { Some(reader) => reader.cancel(); None => () }
}

///|
/// The row pressed last, and whether the press has been a long one (its menu's: not a tap).
// kept across runs: put back by chat_rows_reset (rows)
let row_held : Ref[(Int, Bool)] = Ref((0, false))

///|
let row_primed : Ref[@sfbase.TopicLease?] = Ref(None)

///|
/// A chat's row in a list: `lead` whose pictures lead, `on` its chat the
/// page in view, `list_ground` the list's ground (round its faces), `more` another row under it (@sf.list_more).
/// `lifted`: how far it is in going ahead of others (its ground of its own over them; -1 not); `unghost` whether it
/// leaves the list without a copy (swiped off), or with one again. `found`: a chat a search found, or a recent chat
/// under the composer (pressed alone, not held for its menu); `opened`: what a press does instead of opening its chat.
/// Its answer is the box that moves as the list changes. `at`: where its list stands (ListsFrame), its words in and
/// its ground rounded so.
pub fn chat_row(
  c : @ui.Ctx,
  src : Source,
  item : ChatItem,
  lead : String,
  on? : Bool = false,
  list_ground? : Int64 = @sf.theme().p.bg,
  more? : Bool = false,
  lifted? : Double = -1.0,
  found? : Bool = false,
  opened? : (ChatRef) -> Unit,
  unghost? : (Bool) -> Unit = fn(_) {  },
  at? : @sf.ListAt = Whole,
) -> Int {
  let t = @sf.theme()
  // (its sizes the theme's, by the screen; how it answers by the hand)
  let look = @sf.theme().chat_list
  // (a finger rests on nothing: a press reads ahead, a hold shows the time; a pointer's over it shows them)
  let finger = !@sf.pointer_rests()
  let key = @sfbase.row_name(item)
  let id = c.id("row/" + key)
  // what in it has a tip of its own (the state line's icon, the station's mark, the unplugged one) and its state line:
  // parts of it, only pointed at (Ctx::box's `points`), a press on them the row's
  let slot = c.id("row/lead/" + key)
  let kind = c.id("row/kind/" + key)
  let away = c.id("row/away/" + key)
  let line = c.id("row/line/" + key)
  let opener = c.id("row/opener/" + key)
  let archive = c.id("row/archive/" + key)
  let parts = [id, slot, kind, away, line, opener]
  let r = row_ref(item)
  let renaming = row_renaming.get() == key
  let pressed = parts.iter().any(fn(p) { c.pressed(p) })
  let down = parts.iter().any(fn(p) { c.held_down(p) })
  // Start reading when the finger goes down: the visible press can be delayed in a scrolling list.
  if finger && down && row_held.val.0 != id {
    match row_primed.val { Some(reader) => { row_primed.val = None; reader.cancel() }; None => () }
    row_held.val = (id, false)
    if !src.read_only {
      row_primed.val = Some(src.lease_topic("chat", chat_params(r)))
    }
  }
  // its chat's whole row (what its menu, its swipe's question, its time read: the list's row is made without them),
  // held while the hand is on it (pointed at, down on it, its menu open), let go of after; what reads it waits for it
  let whole_scope = "row-whole/" + key
  let wants_whole = !@sfbase.whole_already(src, item) && !item.pending &&
    (down || parts.iter().any(fn(p) { c.hovered(p) }) || c.hovered(archive) || row_menu_open(item) || c.held_down(c.id("swipe/" + key)))
  let whole : ChatItem? = if @sfbase.whole_already(src, item) {
    Some(item)
  } else if wants_whole {
    @sfbase.whole_of_state(item, @sfbase.hold(src, whole_scope, "chatRow", @sfbase.whole_params(item.station, item.session)).get())
  } else {
    @sfbase.let_go(src, whole_scope)
    None
  }
  // (what it asks again waits on the station)
  let menu = item.offline is None && !item.pending && !found
  // right clicked, or held long by a finger (Ctx::menu_asked, each part asked once): its menu
  let asked = parts.fold(init=None, fn(at, p) { if at is Some(_) { at } else { c.menu_asked(p) } })
  match asked {
    Some((x, y)) if menu => {
      row_held.val = (id, true)
      if finger {
        let reader = row_primed.val
        row_primed.val = None
        unprime(src, r, reader)
      }
      match whole {
        Some(w) => row_menu(c, src, w, id, x, y)
        None => ()
      }
    }
    _ => ()
  }
  // held by a finger a while: its time shows
  let held = finger && !found && @kit.after(c, "row-hold/" + key, pressed && row_held.val.0 == id, hold_ms)
  let menu_on = row_menu_open(item)
  // pressed and let go: its chat opened then, before the next frame is built (Ctx::on_press: a frame that built the
  // page it left and then the chat, all of it twice, 2026-10-30)
  c.on_press(id, fn() {
    // (being renamed: a press is the field's)
    if renaming {
      let reader = row_primed.val
      row_primed.val = None
      unprime(src, r, reader)
      return
    }
    let long = row_held.val.0 == id && row_held.val.1
    row_held.val = (0, false)
    if long {
      if finger {
        let reader = row_primed.val
        row_primed.val = None
        unprime(src, r, reader)
      }
    } else {
      let primed = match row_primed.val {
        Some(reader) => Some(reader)
        None if !src.read_only => Some(src.lease_topic("chat", chat_params(r)))
        None => None
      }
      row_primed.val = None
      let reader = match primed { Some(reader) => @sfbase.prepare_chat_handoff(reader); None => None }
      match opened {
        Some(f) => f(r)
        None => {
          // pressed on its state line while the core says which message that is about, nothing in it unread: its
          // chat goes there as it opens (Enter on the row, or a reader's Activate, presses the row itself: opened
          // as it is)
          match item.state_about {
            Some(seq) if c.press_within(line) && !item.unread && item.thread is Some(_) =>
              @sfbase.go_to(r, seq)
            _ => ()
          }
          open_page(Chat(r))
        }
      }
      match reader { Some(reader) => @sfbase.handoff_chat_open(r, reader); None => () }
    }
  })
  // (let go held, no press of it taken: a press taken let it go as it ran, above)
  if !down && row_held.val.0 == id && !menu_on {
    row_held.val = (0, false)
    if finger {
      let reader = row_primed.val
      row_primed.val = None
      unprime(src, r, reader)
    }
  }
  // pointed at by a mouse (its menu open beside it too); a finger's, held or its menu open
  let hover = !finger && (parts.iter().any(fn(p) { c.hovered(p) }) || c.hovered(archive) || menu_on)
  let shows_time = (hover || held || (finger && menu_on)) && whole is Some(_)
  // its 归档 key while pointed at by a mouse (shown only under the hand: Ctx::hand_lit); a finger has its swipe and its
  // menu's 归档
  let archive_key = !finger && menu && !renaming && c.hand_lit(hover) && whole is Some(_)
  // (swiped to archive, where what the row offers is not under a pointer's hover: the screen's, as its ⋯ is; a pointer
  // has its 归档 key), which rows the core says: made chats whose stations are there
  let swipes = @sf.more_held() && item.swipe_archive
  // held by a finger, it lifts off the list toward the finger (iOS's context menu): a little as its time shows, all
  // the way once its menu opens, back down as the menu goes (kind 7, a control answering: held, its menu open)
  let lift = if finger && !found { @sf.lift_of(c, "row/" + key, held, menu_on) } else { 0.0 }
  let busy = row_busy(src, item)
  let failed = row_failed(src, item)
  let offline = item.offline is Some(_)
  // (`apart`: the room its list keeps under it, outside the slot a swipe moves it in)
  // a finger's: its chat's page in view, its ground on; gone back from it, the ground stays while the page slides off
  // and a while after, then fades (the user, 2026-10-29: 「别那么快消失，留一会儿」)
  // (one row: the chat last in view; another's in view, it is that one's. Its time from the frame it was gone back
  // from, on the clock: not paused while the list is out of view)
  let left_at = c.id("row-left/" + key)
  let left = if !finger {
    false
  } else if on {
    row_left.val = (key, false)
    false
  } else if row_left.val.0 == key {
    if !row_left.val.1 {
      c.mark(left_at)
      row_left.val = (key, true)
    }
    true
  } else {
    false
  }
  let lit_on = on || (left && c.within(left_at, left_lit_ms))
  let lit = @motion.told(
    c,
    "row-lit/" + key,
    if lit_on { 1.0 } else { 0.0 },
    spec=if lit_on { @motion.Snap(0.0) } else { @motion.tween(left_fade_ms, ease=Leave) },
  )
  // (the same motion says its end for the row to forget it: no clock read as it is built)
  if left && !lit_on && lit.over(c) {
    row_left.val = ("", false)
  }
  let draw = fn(tx : Double, apart : Bool) -> Int {
    let finger_ground = fn() {
      // held, its menu open, or pressed where it rests (not swiped over its 归档): the ink at 5%
      if held || menu_on || (pressed && tx == 0.0 && !found) {
        @sf.alpha(t.p.text, 0.05)
      } else {
        let share = lit.get(c)
        if share > 0.0 {
          @sf.alpha(t.p.selected, share)
        } else if lifted >= 0.0 {
          // going ahead of others, on a ground of its own over them: held to 60% of its 480 ms, then fading
          let p = lifted / lift_ms
          @sf.alpha(@sf.over(t.p.bg, @sf.alpha(t.p.text, 0.06)), if p < 0.6 { 1.0 } else { 1.0 - (p - 0.6) / 0.4 })
        } else if tx != 0.0 {
          // moved across: over 归档's words, which it uncovers as it goes
          t.p.bg
        } else {
          0L
        }
      }
    }
    // (both the finger's selected ground and the mouse's eased ground are read as they are painted)
    let eased = if finger { finger_ground } else { @sf.nav_ground_by(c, "row/" + key, hover || pressed, on) }
    // (lifted, its card is its ground: the row's own drawn by the card round it, not square inside it)
    let lifted_ink = dmin(1.0, dmax(0.0, lift))
    let ground = 0L
    let ground_by : (() -> Int64)? = if lifted_ink <= 0.0 { Some(eased) } else { None }
    // (what shows of it over the list's: what its faces' rings are cut in)
    let face_ground = @sf.over(list_ground, if lifted_ink > 0.0 { t.p.raised } else { ground })
    let face_ground_by : (() -> Int64)? = match ground_by {
      Some(f) => Some(fn() { @sf.over(list_ground, f()) })
      None => None
    }
    // (in a side column who is in it stands in the row's foot's end corner, placed there by the corner rule; across
    // the whole screen at its second line's end; the row pointed at says when instead)
    let cornered = at != Whole && !shows_time && row_aside_shows(item, lead)
    let place = if apart { @sf.list_more(at) } else { row_last }
    let row_box = c.box(
      style=if lifted_ink > 0.0 { place.then(row_lifted(lifted_ink)) } else { place },
      tx~,
      fn() {
      // (the library's list row, a chat's as high as its row always is: @sf.list_row)
      @sf.list_row(
        c,
        id,
        at,
        ground,
        ground_by?=ground_by,
        high=true,
        // (归档 over its first line's end: Sidebar.css.ts rowArchive, 24)
        end_room=if archive_key { @sf.row_keys_room(1) } else { 0.0 },
        corner?=if cornered {
          Some(fn() { row_aside(c, src, item, lead, face_ground, ground_by?=face_ground_by) })
        } else {
          None
        },
        corner_w=if cornered { row_aside_w(c, item, lead) } else { 0.0 },
        // (swiped in its slot: the slot's corners its)
        slotted=swipes,
        // (its station's mark at its first line's end, in the column of who is in it under it)
        end_slot=kind_slot_w,
        corner_end=row_aside_end_w(item, lead),
        fn() {
            // (renamed, the field takes the head's whole width, its mark's place too: rename_box)
            let tone = @sfbase.row_tone(item)
            if tone != "" && !renaming {
              c.box(style=mark_slot, fn() { row_mark(c, key, tone) }) |> ignore
            }
            if renaming {
              row_rename(c, src, item, at)
            } else {
              let title = if item.unread { look.title_unread } else { look.title }
              let named = if item.hidden == Some(true) { item.title + " · " + @sf.t("web-main.filter.hidden") } else { item.title }
              @sf.name_words(c, named, if offline || item.settled { title.then(title_dim) } else { title }) |> ignore
            }
            // pinned, renamed or archived: nothing while its station answers (the core's list has it so at once);
            // failed, a red mark a few seconds, why on it (the menu that asked has closed, the core put it back)
            match failed {
              Some(why) =>
                c.box(style=kind_slot, fn() {
                  let mark = c.id("row/failed/" + key)
                  let b = c.box(id=mark, fn() { chat_mark(c, "alert") |> ignore })
                  c.semantics(b, Image, id=mark, label=why)
                  @sf.tip(c, "row/failed-tip/" + key, mark, why)
                })
                |> ignore
              None => ()
            }
            // its station offline, or its link coming back: unplugged (the core says which, row by row); one that came
            // from elsewhere (Slack, Feishu) says so, by its platform's mark
            match (item.offline, item.reconnecting) {
              (Some(why), _) | (None, Some(why)) => {
                let b = c.box(style=kind_slot, id=away, taps=false, points=true, fn() {
                  // (gone for its update: the update's mark, turning for the short while it takes)
                  if item.updating {
                    @sf.updating_mark(c, kind_glyph, t.p.subtle) |> ignore
                  } else {
                    @sf.icon(c, "unplug", size=kind_glyph, color=t.p.subtle) |> ignore
                  }
                })
                c.semantics(b, Image, id=away, label=why)
                @sf.tip(c, "row/away-tip/" + key, away, why)
              }
              _ =>
                if item.connect {
                  let said = if item.origin_text != "" { item.origin_text } else { "Slack" }
                  let b = c.box(style=kind_slot, id=away, taps=false, points=true, fn() {
                    // (Comma's mark is one colour: in the page's ink, as a one-colour maker's is)
                    @sf.drawable(c, @sf.origin_mark_name(item.origin_kind), kind_mark, tint?=if item.origin_kind == "comma" {
                      Some(t.p.text)
                    } else {
                      None
                    })
                    |> ignore
                  })
                  c.semantics(b, Image, id=away, label=said)
                  @sf.tip(c, "row/away-tip/" + key, away, said)
                }
            }
            // opened by another chat's agent: marked so, that chat named on it (由「…」创建), the way there in its menu
            // (a link only: the two are listed, ordered and archived each on its own)
            match item.opener {
              Some(o) if !renaming => {
                let said = if o.archived { o.text + " · " + o.note } else { o.text }
                let b = c.box(style=kind_slot, id=opener, taps=false, points=true, fn() {
                  @sf.icon(c, "spawned", size=kind_glyph, color=t.p.subtle) |> ignore
                })
                c.semantics(b, Image, id=opener, label=said)
                @sf.tip(c, "row/opener-tip/" + key, opener, said)
              }
              _ => ()
            }
            // the station it runs on, by its mark (the core gives one only with several stations): last, so it stands in
            // the same column at every row's end whatever marks come before it
            if @sf.has_station_mark(item.station_emoji, item.station_icon) && !renaming {
              let b = c.box(style=kind_slot, id=kind, taps=false, points=true, fn() {
                @sf.station_mark(c, item.station_emoji, item.station_icon, kind_mark_of(item.station_icon), if offline {
                  t.p.subtle
                } else {
                  t.p.muted
                })
              })
              c.semantics(b, Image, id=kind, label=item.station_name)
              @sf.tip(c, "row/kind-tip/" + key, kind, item.station_name)
            }
        },
        fn() {
          c.box(style=look.meta, fn() {
            let state = match item.state_text {
              Some(s) => Some(s)
              None => item.decision_text
            }
            match state {
              Some(s) =>
                c.box(style=state_box, id=line, taps=false, points=true, fn() {
                  state_line(
                    c,
                    "row/state/" + key,
                    slot,
                    s,
                    lead=@sfbase.row_lead(item),
                    lead_text=item.state_lead_text,
                    rest=item.state_rest,
                    alert=item.unsent,
                  )
                })
                |> ignore
              None => @sf.name_words(c, item.last.unwrap_or(""), look.last) |> ignore
            }
            if shows_time {
              // (its day and time over it while it is pointed at: Time's tip, `fixed`)
              let time = c.id("row/time/" + key)
              let said = whole.unwrap_or(item)
              c.box(id=time, taps=false, points=true, fn() { c.text(said.ago, style=row_time) |> ignore }) |> ignore
              @sf.tip(c, "row/time-tip/" + key, time, said.full)
            } else if at == Whole {
              row_aside(c, src, item, lead, face_ground, ground_by?=face_ground_by)
            }
          })
          |> ignore
        },
        // a chat a search found, or in the latest chats: rippled where it is pressed (a finger's)
        after=fn() {
          if found {
            let corner = match at {
              Whole => 0.0
              Side | Tape => if @sf.in_small_panel() { @sf.small_panel_inner(@sf.r_menu) } else { @sf.row_corner }
            }
            @motion.ripple(c, id, corner)
          }
        },
      )
      |> ignore
      // 归档, at the row's top right while a mouse points at it (concentric with the row's corner: @sf.row_corner_keys)
      if archive_key {
        @sf.row_corner_keys(c, fn() {
          c.on_press(archive, fn() {
            archive_row(src, whole.unwrap_or(item))
          })
          let b = c.box(style=@sf.row_key_box, id=archive, fn() {
            @sf.icon(c, "archive", size=row_icon, color=if c.lit(archive) { t.p.text } else { t.p.muted }) |> ignore
          })
          c.semantics(b, Button, id=archive, label=@sf.t("web-main.chat.archiveNamed", args=[("title", item.title)]))
          @sf.tip(c, "row/archive-tip/" + key, archive, @sf.t("web-main.chat.archive"))
        })
      }
    })
    // (a card of it, drawn in from the screen's sides; over the menu's scrim while it is up, under the menu: what the
    // menu is of stands out of what it dims)
    @sf.lift_over(c, row_box, "row/" + key, lift, 1.0 - row_lift_inset)
    row_box
  }
  if swipes {
    c.box(style=if more { @sf.list_more(at) } else { row_last }, fn() {
      // (what it asks is its whole row's, held as the finger went down, read as it is let go: not answered then, it
      // springs back as when busy)
      swipe_to_archive(c, src, item, busy, at, fn(tx) { draw(tx, false) }, whole_of=fn() {
        match whole {
          Some(w) => Some(w)
          None => @sfbase.whole_row(src, item)
        }
      }, unghost~)
      |> ignore
    })
  } else {
    draw(0.0, more)
  }
}

///|
/// The chats a chat's agent made (ChatView `opened`) as a menu's items (its info's next menu): each its title (已归档
/// after one in the archive), where it stands its mark (opened_icon); chosen, `then` (what showed them closed), its chat
/// opened.
pub fn opened_items(opened : Array[@sfbase.OpenedChat], then? : () -> Unit = fn() {  }) -> Array[@sf.MenuItem?] {
  opened.map(fn(o) {
    let label = if o.archived { o.chat.title + " · " + o.note } else { o.chat.title }
    Some(
      @sf.menu_item_of(label, icon=opened_icon(o), fn() {
        then()
        open_page(Chat(o.chat))
      }),
    )
  })
}

///|
/// The mark of a chat a chat's agent made (ChatView `opened`), where it stands: what it needs of the viewer (a bell),
/// failed, at work, done, in the archive; else the mark of a chat made by another's agent.
pub fn opened_icon(o : @sfbase.OpenedChat) -> String {
  if o.archived {
    "archive"
  } else {
    match (o.state_lead, o.mark) {
      ("need", _) | ("decision", _) | (_, "block") => "bell"
      (_, "failed") => "close"
      (_, "run") => "wait"
      ("done", _) => "check"
      _ => "spawned"
    }
  }
}

///|
/// The made-up chat of row `i` of a chats' list in its bones (chat_rows_sample): its title and line as long as a chat's
/// are, an agent in it.
pub fn sample_chat(i : Int) -> ChatItem {
  let title = sample_titles[i % sample_titles.length()]
  let line = sample_lines[i % sample_lines.length()]
  @sfbase.chat_item({
    "id": Json::string("sample/" + i.to_string()),
    "session": Json::string("sample/" + i.to_string()),
    "title": Json::string(@sf.sample_words(title)),
    "last": { "preview": Json::string(@sf.sample_words(line)) },
    "agents": [{ "key": "sample", "maker": { "id": "anthropic" } }],
  })
}

///|
/// How long the made-up chats' titles and lines are (letters).
// kept across runs: a table, never written
let sample_titles : Array[Int] = [7, 10, 6, 12, 8, 9, 5, 11]

///|
// kept across runs: a table, never written
let sample_lines : Array[Int] = [14, 11, 16, 9, 13, 15, 10, 12]

///|
/// A row held, all the way up: how much it is drawn in from the screen's sides (a card of it, @sf.lift_over).
let row_lift_inset : Double = 0.045

///|
/// A row lifted `ink` of the way: a card of the raised ground, a row's corner (the ladder's), its shadow as far.
fn row_lifted(ink : Double) -> @ui.Style {
  let t = @sf.theme()
  @ui.style(
    bg=Data(@sf.alpha(t.p.raised, ink)),
    radius=@sf.row_radius,
    // (what a finger holds: its shadow, coming as far as it lifts and as strong as the card that casts it: the card
    // going clear over it, a shadow at its whole strength and almost no blur showed through it as a dark row)
    shadow=Cast(
      @sf.held_raised.sigma * ink,
      @sf.held_raised.dy * ink,
      @sf.alpha(@sf.held_raised.color, ink),
    ),
  )
}

///|
/// A finger's row whose chat was gone back from: how long its ground stays (about a phone's page sliding off, 350, and
/// as long again), and how long it then takes to fade.
pub let left_lit_ms : Double = 700.0

///|
pub let left_fade_ms : Double = 400.0

///|
/// The finger's row whose chat is in view or was gone back from last, till its ground has faded, and whether its
/// going back is marked (the time its ground stays counted from).
// kept across runs: put back by chat_rows_reset, forgotten once its ground has faded
let row_left : Ref[(String, Bool)] = Ref(("", false))

///|
/// How long a row going ahead of others has a ground of its own (motion's lift).
let lift_ms : Double = 480.0

///|
/// A finger's row's height at the default size of words (higher at the system's set larger: sf's list_row_node).
pub let touch_row_h : Double = @sf.touch_list_row_h

///|
// kept across runs: a value (no field of it changes)
pub let row_last : @ui.Style = @ui.css("w=Full")

///|
/// The title's mark's column (navMarkSlot, mMarkSlot: 10, the mark in its middle).
// kept across runs: a value (no field of it changes)
let mark_slot : @ui.Style = @ui.css("w=S2_5 align=ACenter")

///|
/// The title of a chat settled (all its work done or dropped) or of an offline station's, stepped back: in the muted
/// grey (navSession[data-settled], [data-offline]); a settled one says so by the archive box leading its second line
/// (@sfbase.row_lead), its words going no lighter. Not faded: half its ink was 2.7 to 1 on the sidebar, too faint to read
/// for a row that still opens (mbui ui/contrast.mbt).
// kept across runs: a value (no field of it changes)
let title_dim : @ui.TextStyle = @ui.text_style(color=Muted)

///|
/// (its state line where the core says one: the words pressed for the message it is about)
// kept across runs: a value (no field of it changes)
let state_box : @ui.Style = @ui.css("row w=Full align=ACenter")

///|
/// When, in the aside's place while pointed at or held (navTime, mChatTime: 11 or 12, subtle).
// kept across runs: a value (no field of it changes)
let row_time : @ui.TextStyle = @ui.text_style(size=Caption, color=Subtle, wrap=false)

///|
/// What stands at a row's title's end (Sidebar.css.ts sessionKind): a column 16 wide, its mark (12) in the middle.
// kept across runs: a value (no field of it changes)
pub let kind_slot : @ui.Style = @ui.css("w=S4 align=ACenter")

///|
/// How wide that column is (kind_slot's S4).
let kind_slot_w : Double = 16.0

///|
pub let kind_mark : Double = 12.0

///|
/// The size a station's mark `icon` is drawn at in that column: a glyph (`glyph:`, and the line icons such as
/// unplugged) is drawn in a 24 grid with room of its own round it (2.5 a side), so at the column's 16 its lines span
/// 12.7, as wide as a logo, an emoji or a picture filling `kind_mark`; drawn at 12 it read smaller than the marks
/// under it and off their line.
pub fn kind_mark_of(icon : String) -> Double {
  if icon.has_prefix("glyph:") {
    kind_glyph
  } else {
    kind_mark
  }
}

///|
/// A line icon in that column (kind_mark_of): the column's width.
let kind_glyph : Double = 16.0

///|
/// A row's icons (16).
let row_icon : Double = 16.0

///|
/// A row's menu, from row `id` at (`x`, `y`): 固定 / 取消固定 (a
/// station from before pins says nothing: none), 重命名, 保留 / 取消保留 (a chat of its own: a thread; pinned, none: a
/// pin keeps it out of the archive already), 归档; 打开「…」 (one an agent opened: the chat it opened it from), 分享…
/// (chat_menu_items): two groups, a line between. Held by a finger, felt as it opens and from the row (a sheet, or under
/// it); right clicked, at the pointer.
fn row_menu(c : @ui.Ctx, src : Source, item : ChatItem, id : Int, x : Double, y : Double) -> Unit {
  // (held by a finger: the press is the menu's, felt; the menu from the row)
  let finger = @sf.menu_held(c, "row")
  let from : @sf.Beside = if finger { Of(id) } else { @sf.at_point(x, y) }
  @sf.menu(chat_menu_items(src, item, share_from=fn() { from }), from~)
  rows.menu_for = @sfbase.row_name(item)
  rows.menu_serial = @sf.last_presented()
}

///|
/// What a chat's menu offers (a row's, and the "…" of the chat's page, one and the same, 2026-11-06 Peng Xiao: 「这里的...和
/// 侧边栏右键点击 chat，我感觉需要统一一下」). `page`: the page's own of share_items (chat_extra_items, from its view, which it
/// has read already), in place of the row's. What shares it or takes it elsewhere (复制会话链接, 接力到频道 for a thread with an
/// agent, and share_items: 分享给其他 workspace, 分享图片, 在 Slack／飞书打开) is one item, 分享…, its own menu from
/// `share_from` (where the menu was opened), where there are two or more of them (左子健, 2026-11-09: 菜单有点太多了，只把分享收进一个).
fn chat_menu_items(
  src : Source,
  item : ChatItem,
  share_from~ : () -> @sf.Beside,
  page? : Array[@sf.MenuItem?],
) -> Array[@sf.MenuItem?] {
  let r = row_ref(item)
  let items : Array[@sf.MenuItem?] = []
  match item.pinned {
    Some(p) =>
      items.push(
        Some(
          @sf.menu_item_of(@sf.t(if p { "web-main.chat.unpin" } else { "web-main.chat.pin" }), icon="pin", fn() {
            @ui.haptic(Confirm)
            act(
              src,
              @sf.t(if p { "android-chat.unpin.verb" } else { "android-chat.pin.verb" }),
              "",
              "chat.pin",
              { "station": Json::string(item.station), "session": Json::string(item.session), "pinned": Json::boolean(!p) },
            )
          }),
        ),
      )
    None => ()
  }
  items.push(
    Some(
      @sf.menu_item_of(@sf.t("web-main.chat.rename"), icon="edit", fn() {
        // asked where the presenters ask it: with keyboard and mouse the row's title its own field, on a
        // touch over the page
        @sf.ask_here(
          @sf.t("android-chat.rename.title"),
          @sf.t("common.save"),
          fn(title) { rename(src, item, title) },
          fn() {
            rows.rename_for = ""
            rows.rename_seen = false
            row_renaming.set(@sfbase.row_name(item))
          },
          value=item.title,
          placeholder=@sf.t("android-chat.rename.field"),
          hint=@sf.t("android-chat.rename.note"),
        )
      }),
    ),
  )
  match item.thread {
    Some(th) if !item.connect && item.agents.length() > 0 =>
      items.push(
        Some(
          @sf.menu_item_of(@sf.t("web-main.chat.regenerateTitle"), icon="refresh", fn() {
            if !src.read_only {
              toast_later(@sf.t("web-main.chat.regenerateTitle.start"))
            }
            act(
              src,
              @sf.t("web-main.chat.regenerateTitle.verb"),
              "",
              "chat.regenerateTitle",
              { "station": Json::string(item.station), "thread": Json::number(th) },
              done=@sf.t("web-main.chat.regenerateTitle.done"),
            )
          }),
        ),
      )
    _ => ()
  }
  match item.thread {
    Some(th) if item.pinned != Some(true) =>
      items.push(
        Some(
          @sf.menu_item_of(@sf.t(if item.kept { "web-main.chat.unkeep" } else { "web-main.chat.keep" }), icon="shield-check", fn() {
            act(
              src,
              @sf.t(if item.kept { "web-main.chat.unkeep.what" } else { "web-main.chat.keep.what" }),
              "",
              "chat.keep",
              { "station": Json::string(item.station), "thread": Json::number(th), "kept": Json::boolean(!item.kept) },
              done=@sf.t(if item.kept { "web-main.chat.unkeep.done" } else { "web-main.chat.keep.done" }),
            )
          }),
        ),
      )
    _ => ()
  }
  match (item.thread, item.hidden) {
    (Some(_), Some(hidden)) =>
      items.push(Some(@sf.menu_item_of(@sf.t(if hidden { "web-main.chat.unhide" } else { "web-main.chat.hide" }), icon=if hidden { "eye" } else { "eye-off" }, fn() {
        hide_row(src, item, !hidden)
      })))
    _ => ()
  }
  match (item.thread, item.muted) {
    (Some(thread), Some(muted)) =>
      items.push(Some(@sf.menu_item_of(@sf.t(if muted { "web-main.chat.unmute" } else { "web-main.chat.mute" }), icon="bell", fn() {
        act(
          src,
          @sf.t(if muted { "web-main.chat.unmute" } else { "web-main.chat.mute" }),
          "",
          "chat.mute",
          { "station": Json::string(item.station), "thread": Json::number(thread), "muted": Json::boolean(!muted) },
          done=@sf.t(if muted { "web-main.chat.unmutedNotice" } else { "web-main.chat.mutedNotice" }),
          at_once=true,
        )
      })))
    _ => ()
  }
  // with the chat's own state (pinned, kept), not last: a sheet's last row is over the screen's foot, where a thumb
  // going home or back lands on it
  items.push(Some(@sf.menu_item_of(@sf.t("web-main.chat.archive"), icon="archive", fn() { archive_row(src, item) })))
  // (a line between the groups: the chat itself; where else it is and goes)
  rule_after(items)
  // the chat an agent opened it from: gone to (its own page, its row as it is)
  match item.opener {
    Some(o) =>
      items.push(
        Some(
          @sf.menu_item_of(@sf.t("web-main.chat.openOpener", args=[("title", o.chat.title)]), icon="spawned", fn() {
            open_page(Chat(o.chat))
          }),
        ),
      )
    None => ()
  }
  // what shares it or takes it elsewhere: one 分享… where there are two or more
  let shared : Array[@sf.MenuItem?] = []
  let link = @sfbase.chat_link(item.station, item.session)
  if link != "" {
    shared.push(
      Some(
        @sf.menu_item_of(@sf.t("web-main.chat.copyLink"), icon="copy", fn() {
          @sfbase.copy_chat_link(item.title, link)
        }),
      ),
    )
  }
  // relayed to a channel: a chat with an agent to go on there
  match item.thread {
    Some(th) if item.agents.length() > 0 =>
      shared.push(
        Some(
          @sf.menu_item_of(@sf.t("web-main.relay.action"), icon="arrow-up-right", fn() {
            open_relay(src, r, th, from=Unanchored)
          }),
        ),
      )
    _ => ()
  }
  // shared, a picture of it, it in Slack or Feishu: the page's and a row's alike (share_items)
  shared.append(
    match page {
      Some(own) => own
      None =>
        share_items(
          src,
          r,
          item.thread,
          may_share=item.may_share,
          may_publish=item.may_publish,
          slack_url=item.slack_url,
          slack_app=item.slack_app,
          feishu_url=item.feishu_url,
        )
    },
  )
  items.append(share_menu(shared, share_from))
  // (no line closing the menu: nothing after the chat's own group)
  if items.last() is Some(None) {
    items.pop() |> ignore
  }
  items
}

/// Hide only from this person's lists, or put the chat back; undo uses the same personal mark.
fn hide_row(src : Source, item : ChatItem, hidden : Bool) -> Unit {
  guard item.thread is Some(thread) else { return }
  let words = @sf.t(if hidden { "web-main.chat.hide" } else { "web-main.chat.unhide" })
  act(
    src,
    words,
    "",
    "chat.hide",
    { "station": Json::string(item.station), "thread": Json::number(thread), "hidden": Json::boolean(hidden) },
    done=@sf.t(if hidden { "web-main.chat.hiddenNotice" } else { "web-main.chat.unhiddenNotice" }),
    done_action=if hidden { @sf.t("android-chat.archived.undo") } else { "" },
    done_run=fn() { hide_row(src, item, false) },
    at_once=true,
  )
}

///|
/// A line ending a menu's group: after an item only (none first, none twice).
fn rule_after(items : Array[@sf.MenuItem?]) -> Unit {
  if items.last() is Some(Some(_)) {
    items.push(None)
  }
}

///|
/// A chat renamed `title` (`chat.rename`): nothing when it is no different.
fn rename(src : Source, item : ChatItem, title : String) -> Unit {
  let words = title.trim(chars=" \n\t").to_owned()
  if words == "" || words == item.title {
    return
  }
  let p : Map[String, Json] = {
    "station": Json::string(item.station),
    "session": Json::string(item.session),
    "title": Json::string(words),
  }
  match item.thread {
    Some(th) => p["thread"] = Json::number(th)
    None => ()
  }
  act(src, @sf.t("android-chat.rename.verb"), "", "chat.rename", Json::object(p))
}

///|
/// A row's title as a field (from a mouse's 重命名): Enter saves it (`chat.rename`), Esc or
/// leaving it lets it be; as far in as where its list stands (`at`) has it (rename_box).
fn row_rename(c : @ui.Ctx, src : Source, item : ChatItem, at : @sf.ListAt) -> Unit {
  let key = "row/rename"
  let whose = @sfbase.row_name(item)
  let press = c.press()
  let starting = rows.rename_for != whose
  if starting {
    rows.rename_for = whose
    rows.rename_seen = false
    rows.rename_opened_at = press.frame
    rows.rename_field.set(item.title)
    c.focus_editor(key)
  }
  // A row is not necessarily focusable, so a press on another row can leave a field holding the keyboard. A rename
  // belongs only to its field: a press elsewhere lets it go, while the press still reaches what it was on.
  if !starting && press.fresh && press.frame != rows.rename_opened_at && !c.press_within(c.id(key)) {
    if c.editor_focused(key) {
      c.blur()
    }
    stop_rename()
    return
  }
  // Check before drawing: after a focus move the title must replace the editor in that same frame.
  if !starting && rows.rename_seen && !c.editor_focused(key) {
    stop_rename()
    return
  }
  c.box(style=rename_box(at).then(@ui.style(border_color=Data(@sf.theme().p.line_strong))), fn() {
    let res = c.editor(
      key,
      font_size=rename_size,
      line=rename_line,
      max_lines=1,
      plain=true,
      color=@sf.theme().p.text,
      caret_color=@sf.theme().p.accent,
      enter_sends=true,
      field=rows.rename_field,
    )
    match res.submitted {
      Some(title) => {
        stop_rename()
        c.blur()
        rename(src, item, title)
      }
      None => ()
    }
    rows.rename_seen = res.focused
  })
  |> ignore
}

///|
/// Let a rename go, including the field's identity, so the same row can be renamed again.
fn stop_rename() -> Unit {
  row_renaming.set("")
  rows.rename_for = ""
  rows.rename_seen = false
  rows.rename_opened_at = -1
}

///|
/// The field in the title's place: the row's head across, its mark's place too (the mark
/// left out while it shows), 24 high on the canvas, 4 taller than the title's line without making the row taller; a 1
/// line round it in the strong grey; the title's words (13 on 24). In the row's top corners: a capsule (its shape its
/// height's) standing where it is concentric with both (@sf.capsule_in: the row's 18 its distance and its half, 6), as
/// far from the row's top as from its sides; all four corners alike, not the row's followed in two and its own 6 in the
/// others (the user, 2026-10-26). Its words its half in from its end, as a capsule field's are (@sf.input's), not 6 in
/// where the title's were (the user, 2026-10-26: 离首字太近). Its sides where its list stands (`at`): in a side column a
/// row's words' (band_pad_in); across the whole screen the ladder's inset, 8, as #3806 (5b8b71713d) made it (the user,
/// 2026-11-09, asked a phone's search fields back to 12, not this).
fn rename_box(at : @sf.ListAt) -> @ui.Style {
  let d = @ui.capsule_in(@sf.row_corner, rename_h)
  let words_in = match at {
    Side | Tape => @sf.band_pad_in(at)
    Whole => @sf.corner_inset
  }
  let side = words_in - d
  let over = @sf.row_top_in_y - d
  rename_look.then(
    @ui.style(
      px=@sf.room_of(rename_words_in),
      mx=@sf.room_of(-side),
      mt=@sf.room_of(-over),
      mb=@sf.room_of(over - rename_taller),
    ),
  )
}

///|
// kept across runs: a value (no field of it changes)
let rename_look : @ui.Style = @ui.css("w=Full h=S6 radius=Full bg=Bg border=B1 justify=JCenter")

///|
/// Its height (h=S6).
let rename_h : Double = 24.0

///|
/// Its words in from either end: its half, as a capsule field's are.
let rename_words_in : Double = rename_h / 2.0

///|
let rename_taller : Double = 4.0

///|
let rename_size : Double = 13.0

///|
let rename_line : Double = 24.0

///|
/// The rows of the list in view as last drawn, in order (the chat beside one archived goes to the next of them).
// kept across runs: said by the list in view as it is drawn
let listed : Ref[Array[ChatItem]] = Ref([])

///|
/// Archives a row's chat: its 归档 key, its menu's, its swipe;
/// one keeping watch only once asked, in the core's words (its swipe also one at work: `ask`, the core's swipeAsk). Its chat in view goes to
/// the chat after it in the list (else before it; else the list alone) at once. Said at once, by its title (the core's
/// list has it gone); why not, when not (`failed` told then).
fn archive_row(
  src : Source,
  item : ChatItem,
  ask? : String? = item.watch_ask,
  then? : () -> Unit = fn() {  },
  failed? : () -> Unit = fn() {  },
) -> Unit {
  let params : Map[String, Json] = {
    "station": Json::string(item.station),
    "session": Json::string(item.session),
    "archived": Json::boolean(true),
  }
  match item.thread {
    Some(th) => params["thread"] = Json::number(th)
    None => ()
  }
  let run = fn() {
    then()
    leave_archived(item)
    act(
      src,
      @sf.t("android-chat.archive.verb"),
      "",
      "chat.archive",
      Json::object(params),
      done=@sf.t("web-main.chat.archivedNamed", args=[("title", item.title)]),
      done_action=@sf.t("android-chat.archived.undo"),
      done_run=@sfbase.archive_undo(src, params),
      at_once=true,
      failed~,
    )
  }
  match ask {
    Some(ask) =>
      @sf.confirm(@sf.t("android-chat.archive.ask", args=[("title", item.title)]), ask, @sf.t("android-chat.archive"), run)
    None => run()
  }
}

///|
/// Away from an archived chat's page if it is the one in view: to its neighbour in the list, else the list alone.
fn leave_archived(item : ChatItem) -> Unit {
  let open = match app.nav.top() {
    Chat(r) => @sfbase.row_is(item, r)
    _ => false
  }
  if !open {
    return
  }
  let rows = listed.val
  let at = rows.search_by(fn(i) { i.station == item.station && i.id == item.id })
  let next = match at {
    Some(k) if k + 1 < rows.length() => Some(rows[k + 1])
    Some(k) if k > 0 => Some(rows[k - 1])
    _ => None
  }
  match next {
    Some(n) => open_page(Chat(row_ref(n)))
    None => (@sfbase.shell.val.home)()
  }
}

///|
/// Let go past this share of its width (or flung left), a swiped row is archived.
let archive_at_share : Double = 0.35

///|
/// How fast a fling left must be (points per ms) to archive a row that went at least `fling_from_share` of the line
/// across: a deliberate flick, not the sideways drift of a finger scrolling the list.
let fling_speed : Double = 1.0

///|
/// How far towards the line (`archive_at_share`) a row flung left must have gone for the fling to archive it.
let fling_from_share : Double = 0.5

///|
/// Whether a row `w` wide let go `at` across (to the left: negative), its finger going `vx` (points per ms), is
/// archived: landing past the line on from that speed (@ui.lands_past), or flung left from past `fling_from_share` of
/// the way to it.
fn swipe_archives(at : Double, w : Double, vx : Double) -> Bool {
  let line = w * archive_at_share
  @ui.lands_past(at, vx, -line) || (vx < -fling_speed && at < -line * fling_from_share)
}

///|
/// Whether a finger moved (dx, dy) from where it went down on a row takes it for the row's swipe to archive: left
/// past the slop and plainly across (at most half as far up or down), so one scrolling the list that drifts a little
/// sideways as it sets off scrolls it.
fn swipe_claims(dx : Double, dy : Double) -> Bool {
  dx < -@ui.touch_slop() && dx.abs() > 2.0 * dy.abs()
}

///|
/// How long a swiped row's 归档 takes to fill in ink. Let go to archive, it goes off to the left on a Move as long as
/// what is left of its width, as fast as the finger let it go.
let swipe_fill_ms : Double = 140.0

///|
/// A finger's row, swiped left to archive it: it follows the finger in its
/// slot (cut to its corners where its list stands, `at`), uncovering 归档 at the right edge (filled in ink once letting
/// go would archive it); let go past `archive_at_share` of its width or flung left, it goes off to the left and is
/// archived, else it springs back. Archiving refused, it comes back; one the core asks about (keeping watch, at work)
/// springs back and asks first. Across first it is the swipe (the row's tap and hold let go); up or down first it is the list's.
/// `row` draws the row moved across by so much; `unghost` says whether it leaves the list without a copy (swiped off),
/// or with one again (its archiving refused). Its answer is the box holding it all.
fn swipe_to_archive(
  c : @ui.Ctx,
  src : Source,
  item : ChatItem,
  busy : Bool,
  at : @sf.ListAt,
  row : (Double) -> Int,
  whole_of~ : () -> ChatItem?,
  unghost? : (Bool) -> Unit = fn(_) {  },
) -> Int {
  let t = @sf.theme()
  let key = "swipe/" + @sfbase.row_name(item)
  let id = c.id(key)
  let width = dmax(c.width, 1.0)
  let off = @motion.anim(c, key, 0.0, global=true)
  let back = fn(v : Double) { off.animate(c, 0.0, @motion.move_spring, velocity=v) }
  let going = rows.swiped_off.contains(key)
  match c.drag_of(id) {
    // (gone off already: nothing more to swipe)
    Some(d) if !going => {
      let (dx, _) = d.take_move()
      if dx != 0.0 {
        off.snap(c, dclamp(off.get(c) + dx, -width, 0.0))
      }
      if d.take_end() {
        let at = off.get(c)
        let v = d.vx * 1000.0
        let whole = if swipe_archives(at, width, d.vx) && !busy { whole_of() } else { None }
        if swipe_archives(at, width, d.vx) {
          if busy || whole is None {
            back(v)
          } else if whole.unwrap().swipe_ask is Some(_) {
            back(v)
            archive_row(src, whole.unwrap(), ask=whole.unwrap().swipe_ask)
          } else {
            // off to the left, then archived (no copy of it left behind as it leaves the list: it is out of sight)
            rows.swiped_off[key] = true
            unghost(true)
            off.animate(c, -width, @motion.moved(), velocity=v)
          }
        } else {
          back(v)
        }
      }
    }
    _ => ()
  }
  let moved = off.get(c)
  // gone off: archived (the call once the row has gone, as declared as it set off), drawn off this frame and its place
  // forgotten, so the row asked back (its toast's 撤销) is where it rests; refused, it comes back from off to the left
  if going && off.over(c) {
    rows.swiped_off.remove(key)
    off.snap(c, 0.0)
    archive_row(src, item, failed=fn() {
      unghost(false)
      off.snap(c, -width)
      back(0.0)
    })
  }
  // past the line letting go archives at: felt as it is passed
  let past = moved < -width * archive_at_share
  // (only while it is past the line or was: a row at rest tells nothing, as one coming into view as its list scrolls
  // would tell otherwise than the frame before and build the next whole, frame_watch.mbt's told_same)
  if past || rows.felt_past.get(key) == Some(true) {
    c.after_build("haptic/" + key, fn() {
      if past && rows.felt_past.get(key) != Some(true) {
        @ui.haptic(TextHandleMove)
      }
      rows.felt_past[key] = past
    })
  }
  let fill = @motion.animate(c, key + "/fill", if past { 1.0 } else { 0.0 }, spec=@motion.tween(swipe_fill_ms, ease=Out))
  c.drag_area(id, axis=Horizontal, w=Fill(1.0), fn() {
    c.box(style=@sf.list_row_slot(at), fn() {
      if moved < 0.0 {
        // at the end it uncovers, as far as the row has gone and no further: quiet until
        // letting go would archive it, then ink. Never under the row, whose edges would show round it.
        let ground = @ui.style(w=Fixed(-moved), bg=Data(@sf.mix(t.p.text, fill, t.p.chip)))
        c.box(style=ground, top=0.0, right=0.0, bottom=0.0, fn() {  }) |> ignore
        // 归档 at that end, laid out the slot across so it is whole, under the row (what of it the row has not
        // uncovered yet, the row hides)
        c.layer(fn() {
          c.box(style=swipe_words_line, fn() {
            c.text(@sf.t("android-chat.archive"), style=swipe_words.then(@ui.text_style(color=Data(@sf.mix(t.p.bg, fill, t.p.muted)))))
            |> ignore
          })
          |> ignore
        })
        |> ignore
      }
      row(moved) |> ignore
    })
    |> ignore
  })
}

///|
// kept across runs: a value (no field of it changes)
let swipe_words_line : @ui.Style = @ui.style(
  row=true,
  w=Full,
  h=Full,
  pr=@sf.phone_row_in,
  align=ACenter,
  justify=JEnd,
)

///|
// kept across runs: a value (no field of it changes)
let swipe_words : @ui.TextStyle = @ui.text_style(size=Body, weight=Semibold, wrap=false)

///|
/// Whether a row's title is being written in place (what the frame holds open meanwhile).
pub fn renaming() -> Bool {
  row_renaming.get() != ""
}

///|
/// Esc to a row's title being written in place: let be, the keyboard let go (`blur`). Whether there was one.
pub fn rename_escape(blur : () -> Unit) -> Bool {
  if row_renaming.untracked() == "" {
    return false
  }
  stop_rename()
  blur()
  true
}

///|
/// The chat in view's "…" (a menu from `from`): its items (chat_menu_of) shown.
pub fn open_chat_menu(
  src : Source,
  scope : String,
  r : ChatRef,
  extra : Array[@sf.MenuItem?],
  from~ : @sf.Beside,
  along? : @ui.Along = Start,
) -> Unit {
  ignore(scope)
  match chat_menu_waits.val {
    Some(w) => {
      chat_menu_waits.val = None
      w.end()
    }
    None => ()
  }
  // (its chat's whole row not answered yet, asked as its page opened and held while it is open (chat_whole_held): the
  // menu opened whole the moment it is, while what it was asked in stays as it was (sfbase's press_wait: the chat
  // left, the workspace switched or something else put up, it opens nothing; what it read is the page's, let go of
  // with it). The system's bars' … too, told once the frame's builds are over (sfdesk rail_native.mbt))
  let w = @sfbase.press_wait(fn() { chat_menu_whole(src, r, extra, share_from=fn() { from }) is Some(_) }, fn() {
    match chat_menu_whole(src, r, extra, share_from=fn() { from }) {
      Some(items) => @sf.menu(items, from~, along~)
      None => ()
    }
  })
  chat_menu_waits.val = if w.waiting() { Some(w) } else { None }
}

///|
/// What waits to open the chat's "…" asked before its chat's whole row was answered (open_chat_menu): ended as
/// another is asked, or the run ends; given up as what it was asked in goes (press_wait).
// kept across runs: put back by chat_rows_reset
let chat_menu_waits : Ref[@sfbase.PressWait?] = Ref(None)


///|
/// What the chat in view's "…" offers: what a row's menu offers (chat_menu_items) for its chat's whole row (the core's
/// `chatRow`, held while its page is open: @sfbase.chat_whole_held), else (an archived one, one its station does not
/// list) its link alone; `extra` the page's own (chat_extra_items). None while that is not answered: what opens it
/// waits for it (open_chat_menu). Apart from showing them: the system's bars take them as a menu of their own
/// (rail_native.mbt bar_chat). `scope`: the workspace in view (the row is its station's own).
pub fn chat_menu_of(
  src : Source,
  scope : String,
  r : ChatRef,
  extra : Array[@sf.MenuItem?],
  share_from~ : () -> @sf.Beside,
) -> Array[@sf.MenuItem?] {
  ignore(scope)
  chat_menu_whole(src, r, extra, share_from~).unwrap_or([])
}

///|
/// chat_menu_of's items, None while its chat's whole row is not answered.
fn chat_menu_whole(
  src : Source,
  r : ChatRef,
  extra : Array[@sf.MenuItem?],
  share_from~ : () -> @sf.Beside,
) -> Array[@sf.MenuItem?]? {
  let held = @sfbase.chat_whole_held(src, r)
  let found : ChatItem? = match (held.value, held.error) {
    (Some(Object(_) as v), _) => Some(@sfbase.chat_item(v))
    (Some(_), _) | (_, Some(_)) => None
    _ => return None
  }
  let items : Array[@sf.MenuItem?] = match found {
    Some(item) => chat_menu_items(src, item, share_from~, page=extra)
    None => {
      let link = @sfbase.chat_link(r.station, r.session)
      let shared : Array[@sf.MenuItem?] = []
      if link != "" {
        shared.push(
          Some(
            @sf.menu_item_of(@sf.t("web-main.chat.copyLink"), icon="copy", fn() {
              @sfbase.copy_chat_link(r.title, link)
            }),
          ),
        )
      }
      shared.append(extra)
      share_menu(shared, share_from)
    }
  }
  let reports = feedback_reports(src, r)
  if reports.length() > 0 {
    if items.length() > 0 {
      items.push(None)
    }
    for f in reports {
      let fv = Some(f)
      let id = text(fv, "id")
      items.push(
        Some(
          @sf.menu_item_of(@sf.t("web-main.feedback.menu", args=[("label", text(fv, "label"))]), icon="said", fn() {
            open_feedback(src, r, id)
          }),
        ),
      )
    }
  }
  Some(items)
}

///|
/// What shares a chat or takes it elsewhere (`shared`), in its menu: one item, 分享…, its own menu from `share_from`, where
/// there are two or more; else as they are.
fn share_menu(shared : Array[@sf.MenuItem?], share_from : () -> @sf.Beside) -> Array[@sf.MenuItem?] {
  if shared.length() < 2 {
    return shared
  }
  [
    Some(
      @sf.menu_item_of(@sf.t("web-main.chat.share"), icon="share", fn() {
        @sf.menu(shared, from=share_from(), title=@sf.t("web-main.chat.share.title"))
      }),
    ),
  ]
}

///|
/// What the chat's page's menu has beyond the list's own (`chat`, the core's view of it): as a row's (share_items), from
/// its page's view.
pub fn chat_extra_items(src : Source, r : ChatRef, chat : Json?) -> Array[@sf.MenuItem?] {
  share_items(
    src,
    r,
    opt_number(field(chat, "thread"), "id"),
    may_share=flag(field(chat, "xshare"), "may"),
    may_publish=flag(field(chat, "publish"), "may"),
    slack_url=text(chat, "slackUrl"),
    slack_app=text(chat, "slackApp"),
    feishu_url=text(chat, "feishuUrl"),
  )
}

///|
/// What is done with chat `r` (its `thread`) beyond the list's own, in a row's menu and its page's "…" alike: 分享给其他
/// workspace, 分享图片, 在 Slack 打开 or 在飞书打开, each where the viewer may.
fn share_items(
  src : Source,
  r : ChatRef,
  thread : Double?,
  may_share~ : Bool,
  may_publish~ : Bool,
  slack_url~ : String,
  slack_app~ : String,
  feishu_url~ : String,
) -> Array[@sf.MenuItem?] {
  let items : Array[@sf.MenuItem?] = []
  if may_share {
    items.push(
      Some(
        @sf.menu_item_of(@sf.t("web-pages.chat.xshare"), icon="users", fn() {
          open_xshare(src, r, thread, from=Unanchored)
        }),
      ),
    )
  }
  match thread {
    Some(th) if may_publish =>
      items.push(
        Some(
          @sf.menu_item_of(@sf.t("web-pages.chat.shareImage"), icon="image-upload", fn() { open_publish(src, r, th) }),
        ),
      )
    _ => ()
  }
  if slack_url != "" {
    items.push(
      Some(
        @sf.menu_item_of(@sf.t("web-pages.chat.openInSlack"), icon="external", fn() {
          if !@sfbase.open_slack(slack_app, slack_url) {
            @sfbase.toast_later(@sf.t("android-chat.link.failed"))
          }
        }),
      ),
    )
  }
  if feishu_url != "" {
    items.push(
      Some(
        @sf.menu_item_of(@sf.t("web-pages.chat.openInFeishu"), icon="external", fn() {
          if !@ui.open_url(feishu_url) {
            @sfbase.toast_later(@sf.t("android-chat.link.failed"))
          }
        }),
      ),
    )
  }
  items
}
