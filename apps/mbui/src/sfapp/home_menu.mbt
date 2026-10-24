// What can be done to a chat from its row on the phone (ember apps/android chat screens/Home.kt rowMenu, archiveRow,
// rowBusy, rowFailed; web mobile/Home.tsx useRowMenu): held long, a menu just below the row (over it when there is no
// room below), 180 wide and centred on the finger across, in Sheet.kt MenuHost's look: 固定 / 取消固定, 重命名, 复制会话链接,
// 归档. None for a new chat its station has not made yet, one on a station offline, or one whose pin or archive is under
// way (its spinner on the row). A chat keeping watch is archived only once asked (its watch runs on in the archive).
// A row with nothing left in it is swiped left to archive it, too (SwipeToArchive).

///|
/// The row whose menu is open: what it shows, where the finger held it across, the row's top and height (in the
/// window); the press it opened on (Ctx::press frame), so the same press opens it once.
priv struct RowMenu {
  mut item : ChatItem?
  mut x : Double
  mut top : Double
  mut h : Double
  mut open : Bool
  mut at : Int
}

///|
let row_menu_at : RowMenu = { item: None, x: 0.0, top: 0.0, h: 66.0, open: false, at: -1 }

///|
/// Back to no menu (as each Tester starts: app.mbt reset).
fn reset_row_menu() -> Unit {
  row_menu_at.item = None
  row_menu_at.open = false
  row_menu_at.at = -1
  swiped_off.clear()
}

///|
/// What a row's pin and archive are known by while under way and a moment after failing (AppState.isDoing, failedOf):
/// the wide list's row menu sets the same going.
fn row_key(what : String, item : ChatItem) -> String {
  what + "/" + item.station + "/" + item.session
}

///|
/// The row's pin or archive under way.
fn row_busy(item : ChatItem) -> Bool {
  doing(row_key("pin", item)) || doing(row_key("archive", item))
}

///|
/// The row's pin or archive failed a moment ago.
fn row_failed(c : @ui.Ctx, item : ChatItem) -> Bool {
  failed_lately(c, row_key("pin", item)) || failed_lately(c, row_key("archive", item))
}

///|
/// Whether the row has a menu now (rowMenu's none).
fn row_has_menu(item : ChatItem) -> Bool {
  item.offline is None && !item.pending && !row_busy(item)
}

///|
/// Held long by a finger (the row's `held` from this press on): its menu opens, once a press, felt as it opens.
fn row_held(c : @ui.Ctx, id : Int, item : ChatItem) -> Unit {
  let press = c.press()
  if row_menu_at.at == press.frame {
    return
  }
  if row_menu(c, id, item, press.x) {
    row_menu_at.at = press.frame
    // felt as it opens, once (Home.kt: HapticFeedbackType.LongPress)
    let at = row_menu_at.at
    c.after_build("haptic/row-held", fn() {
      if felt_menu.val != at {
        felt_menu.val = at
        @ui.haptic(LongPress)
      }
    })
  }
}

///|
/// Row `id`'s menu open under it, `x` across where it was asked (a finger's hold, a mouse's right click): whether it
/// has one to open.
fn row_menu(c : @ui.Ctx, id : Int, item : ChatItem, x : Double) -> Bool {
  if !row_has_menu(item) {
    return false
  }
  let (top, h) = match c.rect_of(id) {
    Some((_, y, _, h)) => (y, h)
    None => return false
  }
  row_menu_at.item = Some(item)
  row_menu_at.x = x
  row_menu_at.top = top
  row_menu_at.h = h
  row_menu_at.open = true
  true
}

///|
/// The press whose row's menu was last felt opening (row_held), and each swiped row's being past its line as last felt
/// (swipe_to_archive): felt once as it comes, whichever of a frame's builds saw it.
let felt_menu : Ref[Int] = Ref(-1)

///|
let felt_past : Map[String, Bool] = {}

///|
/// Each hold's press as last felt (`what` held: a message's words picked, a link's menu, a page's bar folded): once a
/// press, whichever of a frame's builds saw it.
let felt_holds : Map[String, Int] = {}

///|
/// Felt as the hold `what` takes the press it is (MessagePick.kt, Links.kt, Preview.kt: HapticFeedbackType.LongPress),
/// once.
fn feel_hold(c : @ui.Ctx, what : String) -> Unit {
  let at = c.press().frame
  c.after_build("haptic/hold/" + what, fn() {
    if felt_holds.get(what) != Some(at) {
      felt_holds[what] = at
      @ui.haptic(LongPress)
    }
  })
}

///|
/// Whether `item`'s row has its menu open (its ground stays lit meanwhile).
fn row_menu_open(item : ChatItem) -> Bool {
  match row_menu_at.item {
    Some(i) => row_menu_at.open && i.station == item.station && i.id == item.id
    None => false
  }
}

///|
/// The row's menu over the list, while open and as it goes (filter_menu's look and motion).
fn home_row_menu(c : @ui.Ctx, src : Source) -> Unit {
  let item = match row_menu_at.item {
    Some(i) => i
    None => return
  }
  let entries : Array[@kit.Entry] = []
  match item.pinned {
    Some(p) => entries.push(@kit.menu_item("pin", label=tr(if p { "android-chat.unpin" } else { "android-chat.pin" })))
    None => ()
  }
  entries.push(@kit.menu_item("rename", label=tr("android-chat.rename")))
  if chat_link(item.station, item.session) != "" {
    entries.push(@kit.menu_item("link", label=tr("web-main.chat.copyLink")))
  }
  entries.push(@kit.menu_item("archive", label=tr("android-chat.archive")))
  let x = dmax(12.0, dmin(row_menu_at.x - 90.0, c.width - 12.0 - 180.0))
  let m = @kit.dropdown_menu(
    c,
    "row-menu",
    row_menu_at.open,
    0,
    entries,
    at=(x, row_menu_at.top, 180.0, row_menu_at.h),
    along=Start,
    // 6 under the row (Sheet.kt MenuHost: the anchor's bottom + 6)
    offset=6.0,
    scrim=0x00000047L,
    enter=@motion.trans(fade=0.0, scale=0.9, ox=0.5, oy=0.0, spec=@motion.menu_spring, fade_spec=@motion.tween(160.0, ease=Out)),
    exit=@motion.trans(fade=0.0, scale=0.9, ox=0.5, oy=0.0, spec=@motion.menu_spring, fade_spec=@motion.tween(120.0, ease=CssOut)),
    look=menu_panel_look,
    item_look=fn(c, s) {
      let icon = match s.entry.value {
        "pin" => "pin"
        "rename" => "edit"
        "link" => "copy"
        _ => "archive"
      }
      menu_row_look(c, s, icon)
    },
  )
  row_menu_at.open = m.open
  match m.chosen {
    Some("pin") =>
      match item.pinned {
        Some(p) =>
          act(
            src,
            tr(if p { "android-chat.unpin.verb" } else { "android-chat.pin.verb" }),
            row_key("pin", item),
            "chat.pin",
            {
              "station": Json::string(item.station),
              "session": Json::string(item.session),
              "pinned": Json::boolean(!p),
            },
          )
        None => ()
      }
    Some("rename") =>
      open_sheet(
        c,
        Rename(
          { station: item.station, session: item.session, title: item.title, station_name: item.station_name },
          item.thread,
          item.title,
        ),
      )
    Some("link") => copy_chat_link(c, item.title, chat_link(item.station, item.session))
    Some("archive") => archive_from_row(src, item)
    _ => ()
  }
}

///|
/// Archives a row's chat (Home.kt archiveRow): its 归档 at the row's start or its menu's; one keeping watch only once
/// asked, in the core's words (its watch runs on in the archive). Said once done; why not, when not.
fn archive_from_row(
  src : Source,
  item : ChatItem,
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
    act(
      src,
      tr("android-chat.archive.verb"),
      row_key("archive", item),
      "chat.archive",
      Json::object(params),
      done=tr("android-chat.archived"),
      failed~,
    )
  }
  match item.watch_ask {
    Some(ask) =>
      @sf.confirm(fill("android-chat.archive.ask", [("title", item.title)]), ask, tr("android-chat.archive"), run)
    None => run()
  }
}

///|
/// The rows swiped off to be archived, by their swipe's key, until they have gone off (then archived).
let swiped_off : Map[String, Bool] = {}

///|
/// Let go past this share of its width (or flung left), a swiped row is archived.
let archive_at : Double = 0.35

///|
/// How fast a fling left must be (points per ms) to archive a row that went at least `fling_from` across.
let fling_speed : Double = 0.5

///|
let fling_from : Double = 16.0

///|
/// How long a swiped row takes to go off to the left, and its 归档 to fill in ink.
let swipe_off_ms : Double = 200.0

///|
let swipe_fill_ms : Double = 140.0

///|
/// An archivable row (Home.kt SwipeToArchive), swiped left to archive it: it follows the finger, uncovering 归档 at the
/// right edge (filled in ink once letting go would archive it); let go past `archive_at` of its width or flung left,
/// it goes off to the left and is archived, else it springs back. Archiving refused, it comes back; one keeping watch
/// springs back and asks first, as its menu's 归档. Across first it is the swipe (the row's tap and hold let go); up
/// or down first it is the list's (mbui's claim by way: whichever's way the finger goes past the slop first). `row` draws the row moved across by so much;
/// `unghost` says whether it leaves the list without a copy (swiped off), or with one again (its archiving refused).
/// Its answer is the box holding it all, what moves as the list changes (Home.kt: the list's `animateItem` over the
/// whole of SwipeToArchive): the row moved alone would be cut by its swipe's clip where it is laid out.
fn swipe_to_archive(
  c : @ui.Ctx,
  src : Source,
  item : ChatItem,
  busy : Bool,
  row : (Double) -> Int,
  unghost? : (Bool) -> Unit = fn(_) {  },
) -> Int {
  let t = @sf.theme()
  let key = "swipe/" + row_name(item)
  let id = c.id(key)
  let width = dmax(c.width, 1.0)
  let off = @motion.anim(c, key, 0.0, global=true)
  let back = fn(v : Double) { off.animate(0.0, @motion.move_spring, velocity=v) }
  let going = swiped_off.contains(key)
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
        if at < -width * archive_at || fling {
          if busy {
            back(v)
          } else if item.watch_ask is Some(_) {
            back(v)
            archive_from_row(src, item)
          } else {
            // off to the left, then archived (no copy of it left behind as it leaves the list: it is out of sight)
            swiped_off[key] = true
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
  // gone off: archived (Home.kt SwipeToArchive: the call once the row has gone); refused, it comes back
  if going && off.get() <= -width + 0.5 && !off.running {
    swiped_off.remove(key)
    archive_from_row(src, item, failed=fn() {
      unghost(false)
      back(0.0)
    })
  }
  let at = off.get()
  // past the line letting go archives at: felt as it is passed (Home.kt SwipeToArchive: TextHandleMove)
  let past = at < -width * archive_at
  c.after_build("haptic/" + key, fn() {
    if past && felt_past.get(key) != Some(true) {
      @ui.haptic(TextHandleMove)
    }
    felt_past[key] = past
  })
  let fill = @motion.animate(c, key + "/fill", if at < -width * archive_at { 1.0 } else { 0.0 }, spec=@motion.tween(swipe_fill_ms))
  c.drag_area(id, axis=Horizontal, w=Fill(1.0), h=Px(66.0), fn() {
    c.box(w=Fill(1.0), h=Px(66.0), clip=true, fn() {
      // under it, at the right edge it uncovers: 归档, quiet until letting go would archive it, then filled in ink
      c.box(
        dir=Row,
        w=Fill(1.0),
        h=Px(66.0),
        min_h=66.0,
        pr=22.0,
        align=ACenter,
        justify=JEnd,
        bg=if at != 0.0 { @sf.mix(t.p.text, fill, t.p.chip) } else { 0L },
        fn() {
          if at != 0.0 {
            c.text(tr("android-chat.archive"), size=15.0, weight=600, color=@sf.mix(t.p.bg, fill, t.p.muted), wrap=false)
            |> ignore
          }
        },
      )
      |> ignore
      c.box(w=Fill(1.0), h=Px(66.0), min_h=66.0, ty=-66.0, fn() { row(at) |> ignore }) |> ignore
    })
    |> ignore
  })
}
