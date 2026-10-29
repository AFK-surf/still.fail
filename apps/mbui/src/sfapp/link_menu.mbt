// A link held in a message (ember apps/android ui/Links.kt linkHold, in Sheet.kt MenuHost's look): its own menu, open it
// or copy it, rather than the message's (picking its words) and rather than the link opening as the finger lifts; a tap
// stays the link's. The menu is 180 wide, under the line held (over it when there is no room below), centred on the
// finger; it comes as the app's menus do (MenuSpring, from its corner by the line) over the menu's scrim. Other words
// that offer a menu put it up the same way under themselves (MenuSpec(bounds, items)): a Slack user's name in a history.

///|
/// The menu that is open: its items (its words and its icon), what a tap on one does, where it is put (x, the top and
/// bottom of what it is under), the link it is for when it is a link's; the press it opened on (Ctx::press frame), so the
/// same press picks no words.
priv struct LinkMenu {
  mut href : String
  mut items : Array[(String, String)]
  mut pick : (@ui.Ctx, Int) -> Unit
  mut x : Double
  mut top : Double
  mut bottom : Double
  mut open : Bool
  mut at : Int
}

///|
let link_menu : LinkMenu = {
  href: "",
  items: [],
  pick: fn(_, _) {  },
  x: 0.0,
  top: 0.0,
  bottom: 0.0,
  open: false,
  at: -1,
}

///|
/// What a message's words give their rich text for a link held by a finger, or right clicked: its menu opened there.
fn link_held(c : @ui.Ctx, href : String, line : (Double, Double, Double, Double)) -> Unit {
  // under the piece of line: where the finger held it; right clicked (a mouse, whose press is not the click's), its
  // middle
  let press = c.press()
  let x = @sf.menu_along(c, line.0 + line.2 / 2.0)
  link_menu_at(href, x, line.1, line.1 + line.3)
  link_menu.at = press.frame
}

///|
/// The link's menu, open it or copy it, centred on `x` under (or over) the line from `top` to `bottom`.
fn link_menu_at(href : String, x : Double, top : Double, bottom : Double) -> Unit {
  link_menu.href = href
  menu_under([(tr("common.link.open"), "external"), (tr("common.link.copy"), "copy")], x, top, bottom, fn(c, i) {
    if i == 0 {
      // as a tap on it: a chat's link opens it here, any other in the browser
      c.after_build("link-menu-open", fn() { open_link(href) })
    } else {
      c.copy_text(href)
      say(c, tr("common.link.copied"))
    }
  })
}

///|
/// A menu of `items` (its words, its icon) put up centred on `x` under what spans `top` to `bottom` (over it when there
/// is no room below); `pick` told which was tapped, the menu gone.
fn menu_under(
  items : Array[(String, String)],
  x : Double,
  top : Double,
  bottom : Double,
  pick : (@ui.Ctx, Int) -> Unit,
) -> Unit {
  link_menu.items = items
  link_menu.pick = pick
  link_menu.x = x
  link_menu.top = top
  link_menu.bottom = bottom
  link_menu.open = true
  link_menu.at = -1
}

///|
/// The menu over the page, while open and as it goes: mbui's dropdown menu (the arrows and Enter as a menu's; a tap
/// beside it, Esc or back close it) at the line held, in MenuHost's look.
fn link_menu_layer(c : @ui.Ctx) -> Unit {
  // opened by a link held: felt as it opens (Links.kt)
  if link_menu.open && link_menu.at == c.press().frame {
    feel_hold(c, "link")
  }
  // 180 wide centred on the finger, 6 under the line held (over it when there is no room below), kept 12 in
  let x = dmax(12.0, dmin(link_menu.x - 90.0, c.width - 12.0 - 180.0))
  let entries = link_menu.items.mapi(fn(i, it) { @kit.menu_item(i.to_string(), label=it.0) })
  let m = @kit.dropdown_menu(
    c,
    "link-menu",
    link_menu.open,
    0,
    entries,
    at=(x, link_menu.top, 180.0, link_menu.bottom - link_menu.top),
    along=Start,
    offset=6.0,
    scrim=0x00000047L,
    enter=@motion.trans(fade=0.0, scale=0.9, ox=0.5, oy=0.0, spec=@motion.menu_spring, fade_spec=@motion.tween(160.0, ease=Out), ground_first=true),
    exit=@motion.trans(fade=0.0, scale=0.9, ox=0.5, oy=0.0, spec=@motion.menu_spring, fade_spec=@motion.tween(120.0, ease=Leave), ground_first=true),
    look=menu_panel_look,
    item_look=fn(c, s) { menu_row_look(c, s, link_icon(s.entry.value)) },
  )
  if link_menu.open && !m.open {
    link_menu.open = false
  }
  match m.chosen {
    Some(v) =>
      for i, _ in link_menu.items {
        if i.to_string() == v {
          (link_menu.pick)(c, i)
        }
      }
    None => ()
  }
}

///|
/// The icon of the open menu's item `value` (its index).
fn link_icon(value : String) -> String {
  for i, it in link_menu.items {
    if i.to_string() == value {
      return it.1
    }
  }
  ""
}
