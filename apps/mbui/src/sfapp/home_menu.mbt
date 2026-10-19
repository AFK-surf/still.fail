// What can be done to a chat from its row on the phone (ember apps/android chat screens/Home.kt rowMenu, archiveRow,
// rowBusy, rowFailed; web mobile/Home.tsx useRowMenu): held long, a menu just below the row (over it when there is no
// room below), 180 wide and centred on the finger across, in Sheet.kt MenuHost's look: 固定 / 取消固定, 重命名, 复制会话链接,
// 归档. None for a new chat its station has not made yet, one on a station offline, or one whose pin or archive is under
// way (its spinner on the row). A chat keeping watch is archived only once asked (its watch runs on in the archive).

///|
/// The row whose menu is open: what it shows, where the finger held it across, the row's top and height (in the
/// window); the press it opened on (cui.down_at), so the same press opens it once.
priv struct RowMenu {
  mut item : ChatItem?
  mut x : Double
  mut top : Double
  mut h : Double
  mut open : Bool
  mut at : Double
}

///|
let row_menu_at : RowMenu = { item: None, x: 0.0, top: 0.0, h: 66.0, open: false, at: -1.0 }

///|
/// Back to no menu (as each Tester starts: app.mbt reset).
fn reset_row_menu() -> Unit {
  row_menu_at.item = None
  row_menu_at.open = false
  row_menu_at.at = -1.0
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
/// Held long (the row's `held` from this press on): its menu opens, once a press.
fn row_held(c : @ui.Ctx, id : Int, item : ChatItem) -> Unit {
  if row_menu_at.at == cui.down_at || !row_has_menu(item) {
    return
  }
  let (top, h) = match c.rect_of(id) {
    Some((_, y, _, h)) => (y, h)
    None => return
  }
  row_menu_at.item = Some(item)
  row_menu_at.x = cui.down_x
  row_menu_at.top = top
  row_menu_at.h = h
  row_menu_at.open = true
  row_menu_at.at = cui.down_at
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
  let t = @sf.theme()
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
    offset=0.0,
    scrim=0x00000047L,
    enter=@motion.trans(fade=0.0, scale=0.9, ox=0.5, oy=0.0, spec=@motion.menu_spring, fade_spec=@motion.tween(160.0, ease=Out)),
    exit=@motion.trans(fade=0.0, scale=0.9, ox=0.5, oy=0.0, spec=@motion.menu_spring, fade_spec=@motion.tween(120.0, ease=CssOut)),
    look=fn(c, _min_w, body) {
      c.box(w=Px(180.0), radius=14.0, bg=t.p.card, shadow=18.0, shadow_y=6.0, clip=true, body) |> ignore
    },
    item_look=fn(c, s) {
      let icon = match s.entry.value {
        "pin" => "pin"
        "rename" => "edit"
        "link" => "copy"
        _ => "archive"
      }
      c.box(
        dir=Row,
        w=Fill(1.0),
        padx=16.0,
        pady=12.0,
        align=ACenter,
        justify=JBetween,
        bg=if s.lit { @sf.alpha(t.p.text, 0.06) } else { 0L },
        fn() {
          c.text(s.entry.label, size=15.0, color=t.p.text, wrap=false, line=21.0) |> ignore
          @sf.icon(c, icon, size=16.0, color=t.p.text) |> ignore
        },
      )
      |> ignore
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
fn archive_from_row(src : Source, item : ChatItem, then? : () -> Unit = fn() {  }) -> Unit {
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
    )
  }
  match item.watch_ask {
    Some(ask) =>
      @settings.confirm(fill("android-chat.archive.ask", [("title", item.title)]), ask, tr("android-chat.archive"), run)
    None => run()
  }
}
