// A chat's row in the chats' lists (ember web/src/Sidebar.tsx ChatRow, ArchiveButton, Rename.tsx TitleInput;
// web/src/mobile/Home.tsx ChatRow, SwipeArchive, useRowMenu, useRowArchive; Sidebar.css.ts navSession…, mobile/Home.css.ts
// mChatRow…): one row in every tier, the web's desktop row with a mouse and its phone row with a finger. Its state's
// mark before its title (bolder while something in it is unread), its station's mark, then where it stands or the
// last thing said, who is in it at the second line's end; pressed, its chat (where the shell has it). With a mouse:
// pointed at, its time in that place and 归档 at its top right; right clicked, its menu at the pointer; renamed in
// place. With a finger: 66 high and in the phone's type; held, its time, and held long its menu; a chat with nothing
// left in it has 归档 at its start and is swiped left to archive it. The menu is the presenters' (@sf.menu): 固定,
// 重命名, 保留, 复制会话链接, 转到频道, 复制 session 文件路径, 归档, each where the chat has it.

///|
/// What the rows keep: the row whose title is being written in place (a mouse's 重命名, its key; "" none) and its field,
/// whether the field had the keyboard last frame (it losing it ends the rename); the row whose menu is open and the
/// presenter it is (lit meanwhile); the rows swiped off to be archived, until they have gone; each swiped row's being
/// past its line as last felt, and the press whose menu was last felt.
priv struct Rows {
  mut renaming : String
  mut rename_for : String
  mut rename_seen : Bool
  rename_field : @ui.Field
  mut menu_for : String
  mut menu_serial : Int
  swiped_off : Map[String, Bool]
  mut transcripts : (String, Array[String])?
  felt_past : Map[String, Bool]
}

///|
let rows : Rows = {
  renaming: "",
  rename_for: "",
  rename_seen: false,
  rename_field: @ui.Field::new(),
  menu_for: "",
  menu_serial: -1,
  swiped_off: {},
  transcripts: None,
  felt_past: {},
}

///|
fn chat_rows_reset() -> Unit {
  rows.renaming = ""
  rows.rename_for = ""
  rows.rename_seen = false
  rows.rename_field.set("")
  rows.menu_for = ""
  rows.menu_serial = -1
  rows.swiped_off.clear()
  rows.transcripts = None
  rows.felt_past.clear()
}

///|
/// How long a finger holds a row before its time shows (mobile/Home.tsx: 450 ms).
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
/// A row let go without opening its chat (a scroll, a hold): what it read ahead let go too, unless its page is open.
fn unprime(src : Source, r : ChatRef) -> Unit {
  if !src.read_only && !readings.contains(r.station + "\u{1}" + r.session) {
    (src.leave)("chat", chat_params(r))
  }
}

///|
/// The row pressed last, and whether the press has been a long one (its menu's: not a tap).
// kept across runs: put back by chat_rows_reset (rows)
let row_held : Ref[(Int, Bool)] = Ref((0, false))

///|
/// A chat's row in a list (Sidebar.tsx ChatRow, mobile/Home.tsx ChatRow): `lead` whose pictures lead, `on` its chat the
/// page in view, `list_ground` the list's ground (round its faces), `more` another row under it (2 between, with a mouse).
/// `lifted`: how far it is in going ahead of others (its ground of its own over them; -1 not); `unghost` whether it
/// leaves the list without a copy (swiped off), or with one again. `found`: a chat a search found (pressed alone: not
/// held, archived nor swiped); `opened`: what a press does instead of opening its chat. Its answer is the box that
/// moves as the list changes.
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
) -> Int {
  let t = @sf.theme()
  // (how it looks and what it offers by the screen; how it answers by the hand: docs/architecture.md)
  let touch = @sf.touch_system()
  // (a finger rests on nothing: a press reads ahead, a hold shows the time; a pointer's over it shows them)
  let finger = !@sf.pointer_rests()
  let key = @sfbase.row_name(item)
  let id = c.id("row/" + key)
  // what in it has a tip of its own (the state line's icon, the station's mark, the unplugged one): pressed or pointed
  // at, the row is
  let slot = c.id("row/lead/" + key)
  let kind = c.id("row/kind/" + key)
  let away = c.id("row/away/" + key)
  let line = c.id("row/line/" + key)
  let archive = c.id("row/archive/" + key)
  let parts = [id, slot, kind, away, line]
  let r = row_ref(item)
  let renaming = rows.renaming == key
  let pressed = parts.iter().any(fn(p) { c.pressed(p) })
  c.cursor(id, Hand)
  // pressed by a finger, the chat is read ahead of its page (Home.kt onPress)
  if finger && pressed && row_held.val.0 != id {
    row_held.val = (id, false)
    if !src.read_only {
      (src.topic)("chat", chat_params(r)) |> ignore
    }
  }
  // (one under way still has it: Sidebar.tsx; what it asks again waits on the station)
  let menu = item.offline is None && !item.pending && !found
  // right clicked, or held long by a finger (Ctx::menu_asked, each part asked once): its menu
  let asked = parts.fold(init=None, fn(at, p) { if at is Some(_) { at } else { c.menu_asked(p) } })
  match asked {
    // (once: the frame built again as it opens asks again)
    Some((x, y)) if menu && !(rows.menu_for == key && @sf.presented_open_of(rows.menu_serial)) => {
      row_held.val = (id, true)
      row_menu(c, src, item, id, x, y)
    }
    _ => ()
  }
  // held by a finger a while: its time shows (mobile/Home.tsx `held`)
  let held = finger && !found && @kit.after(c, "row-hold/" + key, pressed && row_held.val.0 == id, hold_ms)
  let menu_on = row_menu_open(item)
  if parts.iter().any(fn(p) { c.clicked(p) }) && !renaming {
    let long = row_held.val.0 == id && row_held.val.1
    row_held.val = (0, false)
    if long {
      if finger {
        unprime(src, r)
      }
    } else {
      match opened {
        Some(f) => f(r)
        None => {
          // pressed on its state line while the core says which message that is about, nothing in it unread: its chat
          // goes there as it opens (ChatMark.tsx jumpFromLine)
          match item.state_about {
            Some(seq) if (c.clicked(line) || c.clicked(slot)) && !item.unread && item.thread is Some(_) =>
              @sfbase.go_to(r, seq)
            _ => ()
          }
          open_page(Chat(r))
        }
      }
    }
  } else if !pressed && row_held.val.0 == id && !menu_on {
    row_held.val = (0, false)
    if finger {
      unprime(src, r)
    }
  }
  // pointed at by a mouse (its menu open beside it too); a finger's, held or its menu open
  let hover = !finger && (parts.iter().any(fn(p) { c.hovered(p) }) || c.hovered(archive) || menu_on)
  let shows_time = hover || held || (finger && menu_on)
  // its 归档 key while pointed at by a mouse; a finger has 归档 at the row's start or in its menu
  let archive_key = hover && menu && !renaming
  let archivable = touch && item.archivable && item.offline is None && !item.pending && !found
  let busy = row_busy(src, item)
  let failed = row_failed(src, item)
  let offline = item.offline is Some(_)
  let look = if touch { touch_look } else { mouse_look }
  let draw = fn(tx : Double) -> Int {
    let ground = if touch {
      // held, its menu open, or pressed where it rests (not swiped over its 归档): the ink at 5%
      if held || menu_on || (pressed && tx == 0.0 && !found) {
        @sf.alpha(t.p.text, 0.05)
      } else if on {
        t.p.selected
      } else if lifted >= 0.0 {
        // going ahead of others, on a ground of its own over them: held to 60% of its 480 ms, then fading
        let p = lifted / lift_ms
        @sf.alpha(@sf.over(t.p.bg, @sf.alpha(t.p.text, 0.06)), if p < 0.6 { 1.0 } else { 1.0 - (p - 0.6) / 0.4 })
      } else if tx != 0.0 {
        t.p.bg
      } else {
        0L
      }
    } else {
      nav_ground(c, "row/" + key, hover || pressed, on)
    }
    // (what shows of it over the list's: what its faces' rings are cut in)
    let face_ground = @sf.over(list_ground, ground)
    c.box(style=if more && !touch { row_more } else { row_last }, tx~, fn() {
      c.box(style=look.row.then(@ui.style(bg=Data(ground))), id~, fn() {
        if archivable {
          archive_chip(c, src, item, busy)
        }
        c.box(style=if item.settled { look.text_settled } else { look.text }, fn() {
          c.box(style=if archive_key { look.head_room } else { look.head }, fn() {
            let tone = @sfbase.row_tone(item)
            if tone != "" {
              c.box(style=mark_slot, fn() { row_mark(c, key, tone) }) |> ignore
            }
            if renaming {
              row_rename(c, src, item)
            } else {
              let title = if item.unread { look.title_unread } else { look.title }
              c.text(item.title, style=if offline { title.then(title_dim) } else { title }) |> ignore
            }
            // the station it runs on, by its mark (the core gives one only with several stations)
            if @sf.has_station_mark(item.station_emoji, item.station_icon) && !renaming {
              let b = c.box(style=kind_slot, id=kind, fn() {
                @sf.station_mark(c, item.station_emoji, item.station_icon, kind_mark, if offline {
                  t.p.subtle
                } else {
                  t.p.muted
                })
              })
              c.semantics(b, Image, id=kind, label=item.station_name)
              @sf.tip(c, "row/kind-tip/" + key, kind, item.station_name)
            }
            // pinned, renamed or archived, until the station answers: turning; failed, a red mark a few seconds more,
            // why on it (the menu that asked has closed)
            if busy {
              c.box(style=kind_slot, label=@sf.t("common.saving"), fn() { @sf.spinner(c, size=kind_mark) |> ignore })
              |> ignore
            } else {
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
            }
            // its station offline, or its link coming back: unplugged (the core says which, row by row); one that came
            // from elsewhere (Slack) says so
            match (item.offline, item.reconnecting) {
              (Some(why), _) | (None, Some(why)) => {
                let b = c.box(style=kind_slot, id=away, fn() {
                  @sf.icon(c, "unplug", size=kind_mark, color=t.p.subtle) |> ignore
                })
                c.semantics(b, Image, id=away, label=why)
                @sf.tip(c, "row/away-tip/" + key, away, why)
              }
              _ =>
                if item.connect {
                  let said = if item.origin_text != "" { item.origin_text } else { "Slack" }
                  let b = c.box(style=kind_slot, id=away, fn() { @sf.slack_mark(c, kind_mark) |> ignore })
                  c.semantics(b, Image, id=away, label=said)
                  @sf.tip(c, "row/away-tip/" + key, away, said)
                }
            }
          })
          |> ignore
          c.box(style=if offline { look.meta.then(meta_dim) } else { look.meta }, fn() {
            let state = match item.state_text {
              Some(s) => Some(s)
              None => item.decision_text
            }
            match state {
              Some(s) =>
                c.box(style=state_box, id=line, fn() {
                  state_line(
                    c,
                    "row/state/" + key,
                    slot,
                    s,
                    lead=item.state_lead,
                    lead_text=item.state_lead_text,
                    rest=item.state_rest,
                    alert=item.unsent,
                  )
                })
                |> ignore
              None => c.text(item.last.unwrap_or(""), style=look.last) |> ignore
            }
            if shows_time {
              c.text(item.ago, style=row_time) |> ignore
            } else {
              row_aside(c, src, item, lead, face_ground)
            }
          })
          |> ignore
        })
        |> ignore
        // a chat a search found, or in the latest chats: rippled where it is pressed (a finger's)
        if found {
          @motion.ripple(c, id, 0.0)
        }
      })
      |> ignore
      // 归档, at the row's top right while a mouse points at it (Sidebar.css.ts rowArchive: 5 down, 6 in)
      if archive_key {
        c.layer(fn() {
          c.box(style=archive_at, fn() {
            c.cursor(archive, Hand)
            if c.clicked(archive) {
              archive_row(src, item)
            }
            let b = c.box(style=archive_button, id=archive, fn() {
              @sf.icon(c, "archive", size=row_icon, color=if c.lit(archive) { t.p.text } else { t.p.muted }) |> ignore
            })
            c.semantics(b, Button, id=archive, label=@sf.t("web-main.chat.archiveNamed", args=[("title", item.title)]))
            @sf.tip(c, "row/archive-tip/" + key, archive, @sf.t("web-main.chat.archive"))
          })
          |> ignore
        })
        |> ignore
      }
    })
  }
  if archivable {
    swipe_to_archive(c, src, item, busy, draw, unghost~)
  } else {
    draw(0.0)
  }
}

///|
/// How long a row going ahead of others has a ground of its own (motion's lift).
let lift_ms : Double = 480.0

///|
/// A row's looks, by the screen (mobile/Home.css.ts mChatRow… on a touch device, Sidebar.css.ts navSession… on a
/// computer).
priv struct RowLook {
  row : @ui.Style
  text : @ui.Style
  text_settled : @ui.Style
  head : @ui.Style
  head_room : @ui.Style
  meta : @ui.Style
  title : @ui.TextStyle
  title_unread : @ui.TextStyle
  last : @ui.TextStyle
}

///|
/// A mouse's (Sidebar.css.ts navRow, navSession: 54 high, 7 by 10 in, its words from the top, its corner a sidebar row's;
/// two lines 2 apart, its title 13 on 20, 500 while something in it is unread; its second line 12 on 18).
// kept across runs: a value (no field of it changes)
let mouse_look : RowLook = {
  row: @ui.style(row=true, w=Full, h=@sf.side_row_h, px=S2_5, py=@sf.row_in, gap=S2, align=AStart, radius=@sf.side_row_radius),
  text: @ui.css("w=Full gap=S0_5"),
  text_settled: @ui.css("w=Full gap=S0_5 opacity=O45"),
  head: @ui.css("row w=Full h=S5 gap=S1_5 align=ACenter"),
  // (pointed at, room at its end for 归档: 24)
  head_room: @ui.css("row w=Full h=S5 pr=S6 gap=S1_5 align=ACenter"),
  meta: @ui.css("row w=Full h=S4_5 gap=S1_5 align=ACenter"),
  title: @ui.text_style(size=Sm, color=Fg, leading=L6, wrap=false, w=Full),
  title_unread: @ui.text_style(size=Sm, weight=Medium, color=Fg, leading=L6, wrap=false, w=Full),
  last: @ui.text_style(size=Xs, color=Muted, leading=L5, wrap=false, w=Full),
}

///|
/// A finger's (mobile/Home.css.ts mChatRow: 66 high, 22 in on the left and 16 on the right, two lines in its middle;
/// its title 16 on 22, 600 while something in it is unread; its second line 14 on 20).
// kept across runs: a value (no field of it changes)
let touch_look : RowLook = {
  row: @ui.style(row=true, w=Full, h=Fixed(touch_row_h), pl=@sf.phone_row_in, pr=S4, gap=S1_5, align=ACenter),
  text: @ui.css("w=Full justify=JCenter"),
  text_settled: @ui.css("w=Full justify=JCenter opacity=O45"),
  head: @ui.style(row=true, w=Full, h=Fixed(touch_title_h), gap=S2, align=ACenter),
  head_room: @ui.style(row=true, w=Full, h=Fixed(touch_title_h), gap=S2, align=ACenter),
  meta: @ui.css("row w=Full h=S5 gap=S2 align=ACenter"),
  title: @ui.text_style(size=Xl, color=Fg, leading=L7, wrap=false, w=Full),
  title_unread: @ui.text_style(size=Xl, weight=Semibold, color=Fg, leading=L7, wrap=false, w=Full),
  last: @ui.text_style(size=Base, color=Muted, leading=L6, wrap=false, w=Full),
}

///|
/// A finger's row's height and its title's line (mobile/Home.css.ts mChatRow, mChatLine1).
pub let touch_row_h : Double = 66.0

///|
let touch_title_h : Double = 22.0

///|
/// A row in its list, 2 over the row under it with a mouse (Sidebar.css.ts navSessionWrap + navSessionWrap).
// kept across runs: a value (no field of it changes)
pub let row_more : @ui.Style = @ui.css("w=Full pb=S0_5")

///|
// kept across runs: a value (no field of it changes)
pub let row_last : @ui.Style = @ui.css("w=Full")

///|
/// The title's mark's column (navMarkSlot, mMarkSlot: 10, the mark in its middle).
// kept across runs: a value (no field of it changes)
let mark_slot : @ui.Style = @ui.css("w=S2_5 align=ACenter")

///|
/// An offline station's chat's title at half (navSession[data-offline]).
// kept across runs: a value (no field of it changes)
let title_dim : @ui.TextStyle = @ui.text_style(color=A(Fg, O50))

///|
// kept across runs: a value (no field of it changes)
let meta_dim : @ui.Style = @ui.css("opacity=O50")

///|
/// (its state line where the core says one: the words pressed for the message it is about)
// kept across runs: a value (no field of it changes)
let state_box : @ui.Style = @ui.css("row w=Full align=ACenter")

///|
/// When, in the aside's place while pointed at or held (navTime, mChatTime: 11 or 12, subtle).
// kept across runs: a value (no field of it changes)
let row_time : @ui.TextStyle = @ui.text_style(size=Xs, color=Subtle, wrap=false)

///|
/// What stands at a row's title's end (Sidebar.css.ts sessionKind): a column 16 wide, its mark (12) in the middle.
// kept across runs: a value (no field of it changes)
pub let kind_slot : @ui.Style = @ui.css("w=S4 align=ACenter")

///|
pub let kind_mark : Double = 12.0

///|
/// A row's icons (16).
let row_icon : Double = 16.0

///|
/// 归档 at the row's top right (rowArchive: 5 down, 6 in, 24 square; page.css.ts iconBtn's corner, the pointer's
/// ground on it).
// kept across runs: a value (no field of it changes)
let archive_at : @ui.Style = @ui.css("w=Full pt=S1_25 pr=S1_5 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let archive_button : @ui.Style = @ui.css("w=S6 h=S6 radius=Lg align=ACenter justify=JCenter hovered{bg=Hover}")

///|
/// A row's menu (Sidebar.tsx ContextMenu, mobile/Home.tsx useRowMenu), from row `id` at (`x`, `y`): 固定 / 取消固定 (a
/// station from before pins says nothing: none), 重命名, 保留 / 取消保留 (a chat of its own: a thread), 复制会话链接,
/// 转到频道 (a thread with an agent), 复制 session 文件路径, 归档. Held by a finger, felt as it opens and from the row
/// (a sheet, or under it); right clicked, at the pointer.
fn row_menu(c : @ui.Ctx, src : Source, item : ChatItem, id : Int, x : Double, y : Double) -> Unit {
  // (held by a finger: the press is the menu's, felt; the menu from the row)
  let finger = @sf.menu_held(c, "row")
  let r = row_ref(item)
  let items : Array[@sf.MenuItem?] = []
  match item.pinned {
    Some(p) =>
      items.push(
        Some(
          @sf.menu_item_of(@sf.t(if p { "web-main.chat.unpin" } else { "web-main.chat.pin" }), icon="pin", fn() {
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
        // on a computer in place (Rename.tsx TitleInput); on a touch device asked (mobile/Home.tsx ask)
        if @sf.touch_system() {
          @sf.ask(
            @sf.t("android-chat.rename.title"),
            @sf.t("common.save"),
            fn(title) { rename(src, item, title) },
            value=item.title,
            placeholder=@sf.t("android-chat.rename.field"),
            hint=@sf.t("android-chat.rename.note"),
          )
        } else {
          rows.renaming = @sfbase.row_name(item)
        }
      }),
    ),
  )
  match item.thread {
    Some(th) =>
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
    None => ()
  }
  let link = @sfbase.chat_link(item.station, item.session)
  if link != "" {
    items.push(
      Some(
        @sf.menu_item_of(@sf.t("web-main.chat.copyLink"), icon="copy", fn() {
          @sfbase.copy_chat_link(@ui.current(), item.title, link)
        }),
      ),
    )
  }
  // relayed to a channel (docs/relay.md): a chat with an agent to go on there
  match item.thread {
    Some(th) if item.agents.length() > 0 =>
      items.push(
        Some(
          @sf.menu_item_of(@sf.t("web-main.relay.action"), icon="arrow-up-right", fn() {
            open_relay(src, r, th, from=Unanchored)
          }),
        ),
      )
    _ => ()
  }
  items.push(
    Some(
      @sf.menu_item_of(@sf.t("web-main.chat.copyTranscript"), icon="file", fn() {
        // (asked of its station once the frame after it is built: rows_frame)
        rows.transcripts = Some((item.station, match item.agents.map(fn(a) { a.key }).filter(fn(k) { k != "" }) {
          [] => [item.session]
          keys => keys
        }))
      }),
    ),
  )
  items.push(Some(@sf.menu_item_of(@sf.t("web-main.chat.archive"), icon="archive", fn() { archive_row(src, item) })))
  @sf.menu(items, from=if finger { Of(id) } else { @sf.at_point(x, y) })
  rows.menu_for = @sfbase.row_name(item)
  rows.menu_serial = @sf.last_presented()
}

///|
/// What a row's menu left to do, done as the frame's builds are over (a chat's transcripts' paths asked of its
/// station): called by the lists as they are drawn.
fn rows_frame(c : @ui.Ctx, src : Source) -> Unit {
  match rows.transcripts {
    Some((station, keys)) =>
      c.after_build("rows/transcripts", fn() {
        rows.transcripts = None
        copy_transcripts(c, src, station, keys)
      })
    None => ()
  }
}

///|
/// A chat renamed `title` (`chat.rename`): nothing when it is no different.
fn rename(src : Source, item : ChatItem, title : String) -> Unit {
  let words = title.trim(chars=" \n\t").to_string()
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
/// Where a chat's agents' sessions are kept on their station's machine (ChatRef.tsx useCopyTranscripts:
/// `session.transcript` each), copied one a line; said if none is written yet.
fn copy_transcripts(c : @ui.Ctx, src : Source, station : String, keys : Array[String]) -> Unit {
  let paths : Array[String?] = keys.map(fn(_) { None })
  let mut left = keys.length()
  let mut failed : String? = None
  let done = fn() {
    match failed {
      Some(e) => say(c, @sf.t("web-main.chat.copyFailed", args=[("error", e)]))
      None => {
        let found = paths.filter_map(fn(p) { p })
        if found.length() == 0 {
          say(c, @sf.t("web-main.chat.transcriptNone"))
        } else {
          c.copy_text(found.join("\n"))
          say(c, if found.length() > 1 {
            @sf.t("web-main.chat.transcriptsCopied", args=[("n", found.length().to_string())])
          } else {
            @sf.t("web-main.chat.transcriptCopied")
          })
        }
      }
    }
  }
  for i, key in keys {
    (src.call)("session.transcript", { "station": Json::string(station), "key": Json::string(key) }, fn(r) {
      match r {
        Ok(v) =>
          match text(Some(v), "path") {
            "" => ()
            p => paths[i] = Some(p)
          }
        Err(e) => failed = Some(text(Some(e), "message"))
      }
      left = left - 1
      if left == 0 {
        done()
      }
    })
  }
}

///|
/// A row's title as a field (Rename.tsx TitleInput, from a mouse's 重命名): Enter saves it (`chat.rename`), Esc or
/// leaving it lets it be.
fn row_rename(c : @ui.Ctx, src : Source, item : ChatItem) -> Unit {
  let key = "row/rename"
  let whose = @sfbase.row_name(item)
  if rows.rename_for != whose {
    rows.rename_for = whose
    rows.rename_field.set(item.title)
    c.focus_editor(key)
  }
  c.box(style=rename_box.then(@ui.style(border_color=Data(@sf.theme().p.line_strong))), fn() {
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
        rows.renaming = ""
        rows.rename_for = ""
        c.blur()
        rename(src, item, title)
      }
      None => if !res.focused && rows.rename_for != "" && rows.rename_seen { rows.renaming = "" }
    }
    rows.rename_seen = res.focused
  })
  |> ignore
}

///|
/// The field in the title's place (Rename.css.ts titleInput): as wide as the row's head leaves, 24 high on the canvas,
/// its words where the title's were (6 past them each side), 4 taller than the title's line without making the row
/// taller; a 1 line round it in the strong grey, 6 round; the title's words (13 on 24).
// kept across runs: a value (no field of it changes)
let rename_box : @ui.Style = @sf.bleed_x(rename_bleed)
  .then(@sf.in_line(rename_taller))
  .then(@ui.css("w=Full h=S6 radius=Md bg=Bg border=B1 justify=JCenter"))

///|
let rename_bleed : Double = 6.0

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
/// Archives a row's chat (Sidebar.tsx useArchive, mobile/Home.tsx useRowArchive): its 归档 at the row's start or end,
/// its menu's, its swipe; one keeping watch only once asked, in the core's words (its watch runs on in the archive).
/// Its chat in view goes to the chat after it in the list (else before it; else the list alone) at once. Said once
/// done; why not, when not (`failed` told then).
fn archive_row(src : Source, item : ChatItem, then? : () -> Unit = fn() {  }, failed? : () -> Unit = fn() {  }) -> Unit {
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
      done=@sf.t("web-main.chat.archived"),
      failed~,
    )
  }
  match item.watch_ask {
    Some(ask) =>
      @sf.confirm(@sf.t("android-chat.archive.ask", args=[("title", item.title)]), ask, @sf.t("android-chat.archive"), run)
    None => run()
  }
}

///|
/// Away from an archived chat's page if it is the one in view: to its neighbour in the list, else the list alone.
fn leave_archived(item : ChatItem) -> Unit {
  let open = match app.nav.top() {
    Chat(r) => r.station == item.station && (r.session == item.session || r.session == item.id)
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
/// A small 归档 at a finger's row's start, for a chat with nothing left in it (mobile/Home.css.ts mRowArchive): a tap
/// archives it, not while its pin or archive is under way.
fn archive_chip(c : @ui.Ctx, src : Source, item : ChatItem, busy : Bool) -> Unit {
  let id = c.id("archive/" + @sfbase.row_name(item))
  if c.clicked(id) && !busy {
    archive_row(src, item)
  }
  let chip = c.box(style=chip_look.then(@ui.style(bg=Data(@sf.theme().p.chip))), id~, fn() {
    c.text(@sf.t("android-chat.archive"), style=chip_words) |> ignore
    if !busy {
      @motion.ripple(c, id, chip_corner)
    }
  })
  c.semantics(chip, Button, id~, label=@sf.t("android-chat.archive.named", args=[("title", item.title)]), disabled=busy)
}

///|
// kept across runs: a value (no field of it changes)
let chip_look : @ui.Style = @ui.css("px=S2_5 py=S1 radius=Xl")

///|
let chip_corner : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let chip_words : @ui.TextStyle = @ui.text_style(size=Xs, weight=Medium, color=Muted, leading=L4, wrap=false)

///|
/// Let go past this share of its width (or flung left), a swiped row is archived (mobile/Home.tsx TAKES).
let archive_at_share : Double = 0.35

///|
/// How fast a fling left must be (points per ms) to archive a row that went at least `fling_from` across.
let fling_speed : Double = 0.5

///|
let fling_from : Double = 16.0

///|
/// How long a swiped row takes to go off to the left, and its 归档 to fill in ink.
pub let swipe_off_ms : Double = 200.0

///|
let swipe_fill_ms : Double = 140.0

///|
/// A finger's archivable row (mobile/Home.tsx SwipeArchive), swiped left to archive it: it follows the finger,
/// uncovering 归档 at the right edge (filled in ink once letting go would archive it); let go past `archive_at_share`
/// of its width or flung left, it goes off to the left and is archived, else it springs back. Archiving refused, it
/// comes back; one keeping watch springs back and asks first, as its menu's 归档. Across first it is the swipe (the
/// row's tap and hold let go); up or down first it is the list's. `row` draws the row moved across by so much;
/// `unghost` says whether it leaves the list without a copy (swiped off), or with one again (its archiving refused).
/// Its answer is the box holding it all, what moves as the list changes.
fn swipe_to_archive(
  c : @ui.Ctx,
  src : Source,
  item : ChatItem,
  busy : Bool,
  row : (Double) -> Int,
  unghost? : (Bool) -> Unit = fn(_) {  },
) -> Int {
  let t = @sf.theme()
  let key = "swipe/" + @sfbase.row_name(item)
  let id = c.id(key)
  let width = dmax(c.width, 1.0)
  let off = @motion.anim(c, key, 0.0, global=true)
  let back = fn(v : Double) { off.animate(0.0, @motion.move_spring, velocity=v) }
  let going = rows.swiped_off.contains(key)
  match c.drag_of(id) {
    // (gone off already: nothing more to swipe)
    Some(d) if !going => {
      let (dx, _) = d.take_move()
      if dx != 0.0 {
        off.snap(dclamp(off.get() + dx, -width, 0.0))
      }
      if d.take_end() {
        let at = off.get()
        let v = d.vx * 1000.0
        let fling = d.vx < -fling_speed && at < -fling_from
        if at < -width * archive_at_share || fling {
          if busy {
            back(v)
          } else if item.watch_ask is Some(_) {
            back(v)
            archive_row(src, item)
          } else {
            // off to the left, then archived (no copy of it left behind as it leaves the list: it is out of sight)
            rows.swiped_off[key] = true
            unghost(true)
            off.animate(-width, @motion.tween(swipe_off_ms, ease=Standard), velocity=v)
          }
        } else {
          back(v)
        }
      }
    }
    _ => ()
  }
  // gone off: archived (the call once the row has gone); refused, it comes back
  if going && off.get() <= -width + 0.5 && !off.running {
    rows.swiped_off.remove(key)
    archive_row(src, item, failed=fn() {
      unghost(false)
      back(0.0)
    })
  }
  let at = off.get()
  // past the line letting go archives at: felt as it is passed (Home.kt SwipeToArchive: TextHandleMove)
  let past = at < -width * archive_at_share
  c.after_build("haptic/" + key, fn() {
    if past && rows.felt_past.get(key) != Some(true) {
      @ui.haptic(TextHandleMove)
    }
    rows.felt_past[key] = past
  })
  let fill = @motion.animate(c, key + "/fill", if past { 1.0 } else { 0.0 }, spec=@motion.tween(swipe_fill_ms))
  c.drag_area(id, axis=Horizontal, w=Fill(1.0), h=Px(touch_row_h), fn() {
    c.box(style=swipe_frame, fn() {
      // under it, at the right edge it uncovers: 归档, quiet until letting go would archive it, then filled in ink
      let under = if at != 0.0 { @sf.mix(t.p.text, fill, t.p.chip) } else { 0L }
      c.box(style=swipe_under.then(@ui.style(bg=Data(under))), fn() {
        if at != 0.0 {
          c.text(@sf.t("android-chat.archive"), style=swipe_words.then(@ui.text_style(color=Data(@sf.mix(t.p.bg, fill, t.p.muted)))))
          |> ignore
        }
      })
      |> ignore
      c.box(style=swipe_over, ty=-touch_row_h, fn() { row(at) |> ignore }) |> ignore
    })
    |> ignore
  })
}

///|
// kept across runs: a value (no field of it changes)
let swipe_frame : @ui.Style = @ui.style(w=Full, h=Fixed(touch_row_h), clip=true)

///|
// kept across runs: a value (no field of it changes)
let swipe_under : @ui.Style = @ui.style(
  row=true,
  w=Full,
  h=Fixed(touch_row_h),
  min_h=Fixed(touch_row_h),
  pr=@sf.phone_row_in,
  align=ACenter,
  justify=JEnd,
)

///|
// kept across runs: a value (no field of it changes)
let swipe_over : @ui.Style = @ui.style(w=Full, h=Fixed(touch_row_h), min_h=Fixed(touch_row_h))

///|
// kept across runs: a value (no field of it changes)
let swipe_words : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, wrap=false)

///|
fn dclamp(v : Double, lo : Double, hi : Double) -> Double {
  if v < lo {
    lo
  } else if v > hi {
    hi
  } else {
    v
  }
}

///|
/// Whether a row's title is being written in place (what the frame holds open meanwhile).
pub fn renaming() -> Bool {
  rows.renaming != ""
}

///|
/// Esc to a row's title being written in place: let be. Whether there was one.
pub fn rename_escape(c : @ui.Ctx) -> Bool {
  if rows.renaming == "" {
    return false
  }
  rows.renaming = ""
  c.blur()
  true
}
