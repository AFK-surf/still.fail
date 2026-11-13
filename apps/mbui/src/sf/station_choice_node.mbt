// Which station something is done on, at the start of a line saying where (a folder's way, what a repository is cloned
// into): the station's mark and its name; where there are others to choose from, a chevron after them, and pressed, the
// presenters' menu of them beside it (a sheet from the foot on 小屏), the one it is on checked. With none other, only
// what it is: nothing to press.

///|
/// A station to choose (station_choice_node): its address, its name, its mark (its emoji, its icon: station_mark_node's).
#derive(Eq)
pub(all) struct StationChoice {
  station : String
  name : String
  emoji : String
  icon : String
}

///|
/// The station `chosen()` of `stations()` in `parent`: its mark (a server's where it has none) and its name, 13 and
/// medium, as high as a row is at least (a press's room); where there is more than one, a chevron down after them, and
/// pressed (as a crumb of a way is: lit under the hand, its corner the theme's Md), the presenters' menu of them titled
/// `title` beside it, the one chosen checked: one chosen, `choose` given its address. Read out a button named `label` given the station's name; with one alone, words.
/// `round`: round as its height, as a foot's buttons are beside it (in a panel's foot, its corner concentric with the
/// panel's as theirs is). The node.
#callsite(autofill(loc))
pub fn station_choice_node(
  parent : @view.View,
  stations : () -> Array[StationChoice],
  chosen : () -> String,
  choose : (String) -> Unit,
  title~ : String,
  label~ : (String) -> String,
  round? : Bool = false,
  loc~ : SourceLoc,
) -> @view.View {
  let now = fn() -> StationChoice {
    let all = stations()
    match all.iter().find_first(fn(s) { s.station == chosen() }) {
      Some(s) => s
      None => all.get(0).unwrap_or({ station: chosen(), name: chosen(), emoji: "", icon: "" })
    }
  }
  let several = fn() { stations().length() > 1 }
  let opener = Opener::new()
  parent.box(made_for=loc, fn(b) {
    style_node(b, fn() { if round { station_choice_round } else { station_choice_box } }, in_row=true)
    // (shrinking to its words' least where the line is short: its name cut short, its mark and chevron whole)
    b.shrink(Is(1.0)).min_width(Is(Some(0.0))).min_height(By(fn() { Some(theme().items.least) })) |> ignore
    let lit = fn() { several() && lit_node(b) }
    b.ground(By(fn() { if lit() { @ui.tree_theme().color(Hover) } else { 0L } })) |> ignore
    presses_node(b, on=several, fn() {
      let at = @signals.untracked(chosen)
      let items : Array[MenuItem?] = @signals.untracked(stations).map(fn(s) {
        Some(menu_item_of(s.name, fn() { if s.station != at { choose(s.station) } }, chosen=s.station == at))
      })
      present(Menu(items, title, Start), Node(b))
      opener.mark()
    })
    b
    .says(By(fn() {
      if several() {
        Some(@view.said(Button, label=label(now().name), expanded=opener.open()))
      } else {
        None
      }
    }))
    |> ignore
    b.pick(fn() { (now().emoji, now().icon) }, at_once=true, fn(m, mark) {
      if has_station_mark(mark.0, mark.1) {
        station_mark_node(m, fn() { mark.0 }, fn() { mark.1 }, station_choice_mark, fn() { theme().p.muted }, fn() { 0 })
      } else {
        icon_node(m, "server", station_choice_mark, By(fn() { theme().p.muted })) |> ignore
      }
    })
    words_node(b, fn() { now().name }, fn() { station_choice_words }).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    b.show(several, at_once=true, fn(c) {
      icon_node(c, "chevron-down", station_choice_chevron, By(fn() { theme().p.muted })) |> ignore
    })
  })
}

///|
/// Its mark (14) and its chevron (12), a way's crumbs' size.
let station_choice_mark : Double = 14.0

///|
let station_choice_chevron : Double = 12.0

///|
/// A way's crumb's room round it (4 by 2, the theme's Md round), 5 between its parts.
// kept across runs: a value (no field of it changes)
let station_choice_box : @ui.Style = @ui.css("row px=S1 py=S0_5 gap=S1_25 align=ACenter radius=Md")

///|
/// The same, round as its height (station_choice_node's `round`), as far in at its ends as its corner leaves its mark.
// kept across runs: a value (no field of it changes)
let station_choice_round : @ui.Style = @ui.css("row px=S2 py=S0_5 gap=S1_25 align=ACenter radius=Full")

///|
// kept across runs: a value (no field of it changes)
let station_choice_words : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Fg, wrap=false, w=Cut)
