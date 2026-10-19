// A link held in a message (ember apps/android ui/Links.kt linkHold, in Sheet.kt MenuHost's look): its own menu, open it
// or copy it, rather than the message's (picking its words) and rather than the link opening as the finger lifts; a tap
// stays the link's. The menu is 180 wide, under the line held (over it when there is no room below), centred on the
// finger; it comes as the app's menus do (MenuSpring, from its corner by the line) over the menu's scrim.

///|
/// The link whose menu is open: where it leads, the line held (x, y, w, h in the window), where the finger went down;
/// the press it opened on (cui.down_at), so the same press picks no words.
priv struct LinkMenu {
  mut href : String
  mut x : Double
  mut top : Double
  mut bottom : Double
  mut open : Bool
  mut at : Double
}

///|
let link_menu : LinkMenu = { href: "", x: 0.0, top: 0.0, bottom: 0.0, open: false, at: -1.0 }

///|
/// What a message's words give their rich text for a link held: its menu opened there.
fn link_held(href : String, line : (Double, Double, Double, Double)) -> Unit {
  link_menu.href = href
  link_menu.x = cui.down_x
  link_menu.top = line.1
  link_menu.bottom = line.1 + line.3
  link_menu.open = true
  link_menu.at = cui.down_at
}

///|
/// The link's menu over the page, while open and as it goes.
fn link_menu_layer(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
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
  // two rows of 45 and the menu's 12 off the line; above the line when it would not fit below
  let h = 2.0 * 45.0
  let below = link_menu.bottom + 6.0
  let y = if below + h > c.height - 16.0 { dmax(16.0, link_menu.top - 6.0 - h) } else { below }
  let x = dmax(12.0, dmin(link_menu.x - 90.0, c.width - 12.0 - 180.0))
  c.layer(fn() {
    let menu = c.box(
      w=Px(180.0),
      tx=x,
      ty=y,
      radius=14.0,
      bg=t.p.card,
      shadow=18.0,
      shadow_y=6.0,
      clip=true,
      fn() {
        let item = fn(label : String, icon : String, key : String) -> Bool {
          let id = c.id("link-menu/" + key)
          c.box(
            dir=Row,
            w=Fill(1.0),
            padx=16.0,
            pady=12.0,
            align=ACenter,
            justify=JBetween,
            bg=@sf.alpha(t.p.text, 0.06 * @motion.pressing(c, id)),
            id~,
            fn() {
              c.text(label, size=15.0, color=t.p.text, wrap=false, line=21.0) |> ignore
              @sf.icon(c, icon, size=16.0, color=t.p.text) |> ignore
            },
          )
          |> ignore
          c.clicked(id) && link_menu.open
        }
        // as a tap on it: a chat's link opens it here, any other in the browser
        if item(tr("common.link.open"), "external", "open") {
          link_menu.open = false
          open_link(c, link_menu.href)
        }
        if item(tr("common.link.copy"), "copy", "copy") {
          link_menu.open = false
          c.copy_text(link_menu.href)
          say(c, tr("common.link.copied"))
        }
      },
    )
    c.look(menu, look)
    @motion.leaving(c, menu, link_menu.open)
  })
  |> ignore
}
