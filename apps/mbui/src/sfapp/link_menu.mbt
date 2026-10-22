// A link held in a message (ember apps/android ui/Links.kt linkHold, in Sheet.kt MenuHost's look): its own menu, open it
// or copy it, rather than the message's (picking its words) and rather than the link opening as the finger lifts; a tap
// stays the link's. The menu is 180 wide, under the line held (over it when there is no room below), centred on the
// finger; it comes as the app's menus do (MenuSpring, from its corner by the line) over the menu's scrim. Other words
// that offer a menu put it up the same way under themselves (MenuSpec(bounds, items)): a Slack user's name in a history.

///|
/// The menu that is open: its items (its words and its icon), what a tap on one does, where it is put (x, the top and
/// bottom of what it is under), the link it is for when it is a link's; the press it opened on (cui.down_frame), so the
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
/// What a message's words give their rich text for a link held: its menu opened there.
fn link_held(href : String, line : (Double, Double, Double, Double)) -> Unit {
  link_menu_at(href, cui.down_x, line.1, line.1 + line.3)
  link_menu.at = cui.down_frame
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
/// The menu over the page, while open and as it goes.
fn link_menu_layer(c : @ui.Ctx) -> Unit {
  // opened by a link held: felt as it opens (Links.kt)
  if link_menu.open && link_menu.at == cui.down_frame {
    feel_hold(c, "link")
  }
  let look = match
    @motion.presence(
      c,
      "link-menu",
      link_menu.open,
      enter=@motion.trans(fade=0.0, scale=0.9, ox=0.5, oy=0.0, spec=@motion.menu_spring, fade_spec=@motion.tween(160.0, ease=Out)),
      exit=@motion.trans(fade=0.0, scale=0.9, ox=0.5, oy=0.0, spec=@motion.menu_spring, fade_spec=@motion.tween(120.0, ease=CssOut)),
    ) {
    Some(l) => l
    None => return
  }
  let shown = @motion.animate(c, "link-menu/scrim", if link_menu.open { 1.0 } else { 0.0 }, spec=@motion.tween(200.0))
  scrim(c, "link-menu-scrim", shown, open=link_menu.open, fn() { link_menu.open = false })
  // its rows of 45 and its padding (MenuHost's menuHeight), 6 off the line; above the line when it would not fit below
  let h = menu_height(link_menu.items.length())
  let below = link_menu.bottom + 6.0
  let y = if below + h > c.height - 16.0 { dmax(16.0, link_menu.top - 6.0 - h) } else { below }
  let x = dmax(12.0, dmin(link_menu.x - 90.0, c.width - 12.0 - 180.0))
  c.layer(fn() {
    let menu = phone_menu(c, tx=x, ty=y, fn() {
      for i, it in link_menu.items {
        let id = c.id("link-menu/" + i.to_string())
        phone_menu_row(c, it.0, icon=it.1, lit=@motion.pressing(c, id), id~) |> ignore
        if c.clicked(id) && link_menu.open {
          link_menu.open = false
          (link_menu.pick)(c, i)
        }
      }
    })
    c.look(menu, look)
    @motion.leaving(c, menu, link_menu.open)
  })
  |> ignore
}
