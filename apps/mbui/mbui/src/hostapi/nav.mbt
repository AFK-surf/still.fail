// The system's own controls for the app's places and actions, where the platform draws them and the app hands them
// over instead of drawing its own: iOS's (ios_app.m: a column of buttons at the view's trailing edge in the system's
// glass, iOS 26's UIGlassEffect, its groups merged in a UIGlassContainerEffect), laid out as the app says, upright and
// on its side alike. What they take of the view is in the bars the system says (system.mbt `bars`: their `right`): the
// app pads for them as for the status bar. Chosen, an item comes back on the system channel as `{"nav": id}`
// (system.mbt NavTapped). Elsewhere there are none: nav_bar answers false and the app draws its own.

///|
/// An item: a place to go or an action (`id`), its words and its icon (`icon`: an icon's shapes as still.fail's icon
/// data has them, a 24 grid's strokes, sf's icon_data; none: its words' first letter), a dot over it (`dot`), set off in
/// the accent (`prominent`: the one action most wanted); with `menu`, a menu of others (id, words, checked, icon as `icon` is; id "-": a line between rows) opened from
/// it instead.
pub(all) struct NavItem {
  id : String
  title : String
  icon : String
  dot : Bool
  prominent : Bool
  menu : Array[(String, String, Bool, String)]
} derive(Eq)

///|
/// A group of items on one piece of glass: at the column's foot (`foot`: where a thumb holding the device rests) or
/// from its top in their order; folded into one menu (its first item's place) where the column has no room for all
/// (`foldable`).
pub(all) struct NavGroup {
  items : Array[NavItem]
  foot : Bool
  foldable : Bool
} derive(Eq)

///|
/// A native glass button placed in the app's content, in view points. Its menu and accessibility belong to the host.
pub(all) struct NavFloating {
  item : NavItem
  x : Double
  y : Double
  w : Double
  h : Double
  blocked : Bool
} derive(Eq)

///|
/// What the app hands over: its groups, the item chosen (lit: its ground moves to it as it changes), the ink of what is
/// in them and of the one chosen (RGBA), the icon of the menu a group folds into. No groups: none of the system's (the
/// app draws its own). `bare`: the tabs put away while something is up over the whole window (a picture looked at),
/// only the foldable group's items shown, `title` over them (none of them: the bar put away too).
pub(all) struct NavBar {
  floating : Array[NavFloating]
  groups : Array[NavGroup]
  selected : String
  ink : Int64
  chosen_ink : Int64
  more_icon : String
  bare : Bool
  title : String
} derive(Eq)

///|
fn nav_item_json(i : NavItem) -> Json {
  let menu : Array[Json] = i.menu.map(fn(m) {
    { "id": Json::string(m.0), "title": Json::string(m.1), "checked": Json::boolean(m.2), "icon": Json::string(m.3) }
  })
  {
    "id": Json::string(i.id),
    "title": Json::string(i.title),
    "icon": Json::string(i.icon),
    "dot": Json::boolean(i.dot),
    "prominent": Json::boolean(i.prominent),
    "menu": Json::array(menu),
  }
}

///|
/// The bars as JSON for the host (ios_app.m mb_host_nav_bar).
pub fn NavBar::to_json(self : NavBar) -> String {
  let groups : Array[Json] = self.groups.map(fn(g) {
    {
      "items": Json::array(g.items.map(nav_item_json)),
      "foot": Json::boolean(g.foot),
      "foldable": Json::boolean(g.foldable),
    }
  })
  let j : Json = {
    "floating": Json::array(self.floating.map(fn(f) {
      { "item": nav_item_json(f.item), "x": Json::number(f.x), "y": Json::number(f.y),
        "w": Json::number(f.w), "h": Json::number(f.h), "blocked": Json::boolean(f.blocked) }
    })),
    "groups": Json::array(groups),
    "selected": Json::string(self.selected),
    "ink": Json::number(self.ink.to_double()),
    "chosen_ink": Json::number(self.chosen_ink.to_double()),
    "more_icon": Json::string(self.more_icon),
    "bare": Json::boolean(self.bare),
    "title": Json::string(self.title),
  }
  j.stringify()
}

///|
/// What was handed to the host last (handed again only as it changes), and whether it shows them.
let nav_said : Ref[(NavBar, Bool)?] = { val: None }

///|
/// The system's controls as `bar` has them, where the host has them: true when it shows them (the app then draws none
/// of its own for them), false where it has none. Said to the host only as it changes, whatever the frames.
pub fn nav_bar(bar : NavBar) -> Bool {
  // (compared as it is, written out only as it changes: the frames hand it each time, the host rarely needs it)
  match nav_said.val {
    Some((was, shown)) if was == bar => return shown
    _ => ()
  }
  let shown = nv_bar(bar.to_json()) != 0
  nav_said.val = Some((bar, shown))
  shown
}

///|
/// The host's bars to be handed again whole at the next nav_bar, as if never handed (a fake host's that now has them,
/// or has them no longer: Tester::set_nav_able).
pub fn nav_bar_again() -> Unit {
  nav_said.val = None
}

///|
/// None of the system's: the app draws its own (a phone's frame, the outer screen).
pub fn nav_bar_none() -> Unit {
  nav_bar({ floating: [], groups: [], selected: "", ink: 0L, chosen_ink: 0L, more_icon: "", bare: false, title: "" }) |> ignore
}

///|
/// Whether the host lays out the system's controls itself in every pose of its screens (nav_bar shows them: an iPhone
/// Duo's), whatever the frame asks of it now: the app's frame then the same on each.
pub fn nav_bar_able() -> Bool {
  current.val.nv_able()
}
