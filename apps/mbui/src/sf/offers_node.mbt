// What a field offers as it is typed in, a list under it (the composer's `@` menu's look and keys, ref_menu's and the
// relay's note's: kit's popover with its focus left in the field) as nodes of the window's tree: a small panel of glass
// beside the field (under it, lined up with its start, as wide as it is laid out: View::beside's `Anchor`), grown out
// of that side as it comes and shrunk back into it as it goes (pop_in, pop_out); a head (what it offers, and the words
// typed) where one is said, then a row for each of what it offers, the one chosen on the hover's ground, what they say
// the caller's; scrolling past offers_most, or past what the window leaves it.
//
// The focus stays in the field the whole time, and what is typed is the field's: ↓ and ↑ choose (round), Enter and
// Tab take the one chosen, each as the window's keymap binds it where it is open (`Offers`: offers_bindings, actions
// the field asks before it does anything of its own with the key; closed, the field's as ever); the pointer moving onto
// a row chooses it; a press on a row takes it; what ↓ and ↑ choose is brought into sight. Escape closes it (and nothing
// else: the dialog it is in stays), and so does a press anywhere outside it and the field; once it is closed or one is
// taken, the next key is the field's or the dialog's at once, before any frame.
//
// It is made in the layer of the panel, sheet or dialog it is in (offers_layer_lent: over all of it, nothing it cuts
// cutting it, its keys and presses taken there), else in the window's root, over what it holds.

///|
/// Where what a panel's fields offer is made: the layer of the panel, sheet or dialog they are in (modal, over the
/// window), lent by its presenter (panel_node, sheet_node, panel_centred_node).
// kept across runs: what each presented layer is lent, let go with it
let offers_layer_lent : @view.Lent[@view.View] = @view.Lent::new()

///|
/// What a presenter lends its layer: itself, where what the fields it holds offer is made.
fn offers_layer_lend(layer : @view.View) -> Unit {
  layer.lends(offers_layer_lent, layer) |> ignore
}

///|
/// How tall what it offers is at most before it scrolls (ChatRef's refMenu: 320, its padding in it).
pub let offers_most : Double = 320.0

///|
/// How far under the field it stands (kit's popover: 6).
let offers_off : Double = 6.0

///|
/// Its panel (refMenu): panel_pad round what it holds, the menu's corner; on glass, a small shadow (the composer's
/// `@` menu's: ref_menu_box).
// kept across runs: a value (no field of it changes)
let offers_box : @ui.Style = @ui.style(p=room_of(panel_pad), radius=ref_menu_corner)

///|
/// Its head (refHead): what it offers, then the words typed.
// kept across runs: a value (no field of it changes)
let offers_head : @ui.Style = @ui.css("row w=Full px=S2_5 pt=S1_5 pb=S1 gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let offers_head_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let offers_typed : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
/// A row (refItem): 10 apart, as far in as a menu's row, as high as the screen's pick row at least, concentric with the
/// panel; the one chosen on the hover's ground.
// kept across runs: a value (no field of it changes)
let offers_row : @ui.Style = @ui.style(
  row=true,
  w=Full,
  px=S2_5,
  py=room_of(menu_row_over),
  gap=S2_5,
  align=ACenter,
  radius=ref_item_corner,
)

///|
// kept across runs: a value (no field of it changes)
let offers_row_on : @ui.Style = offers_row.then(@ui.css("bg=Hover"))

///|
/// The keys of what a field offers, the keymap's own, never changed: where it is open (`Offers`, the field's focus in
/// it), ↓ and ↑ choose, Enter and Tab take the one chosen (offers_node).
pub fn offers_bindings() -> Array[@view.Binding] {
  let open : @view.KeyWhen = In("Offers")
  [
    { keys: [{ code: @ui.key_code_down, mods: 0 }], action: "offers.down", when: open },
    { keys: [{ code: @ui.key_code_up, mods: 0 }], action: "offers.up", when: open },
    { keys: [{ code: @ui.key_code_enter, mods: 0 }], action: "offers.take", when: open },
    { keys: [{ code: @ui.key_tab, mods: 0 }], action: "offers.take", when: open },
  ]
}

///|
/// What a field offers, under it, while `open()` (going over pop_out_ms once not). `around`: what holds the field (its
/// keys asked there as the field has the focus: `Offers`); `anchor`: what it stands under and is as wide as (the
/// field's frame). `keys()`: what it offers, by key, in order; `current`: the one chosen, by its place among them;
/// `row`: what the row of `key` holds (in a row, 10 apart, lined up across its middle: a picture, words), `on()`
/// whether it is the one chosen; `name`: what a screen reader calls it. `take` with the place of the one taken (by
/// Enter, Tab or a press), once for each; `close` as Escape or a press outside closes it. `head()`: what it offers and
/// the words typed, over the rows ("" none: no head); `label`: what a screen reader calls it. `side`: the side of the
/// field it stands on, `offset` off it (the composer's, over it: Top, 8); `none`: what it says in place of its rows
/// while it offers none (still being found, none found), where it is open so.
#callsite(autofill(loc))
pub fn offers_node(
  around : @view.View,
  anchor : @view.View,
  open : () -> Bool,
  keys : () -> Array[String],
  current : @signals.Signal[Int],
  row : (@view.View, String, () -> Bool) -> Unit,
  name : (String) -> String,
  take : (Int) -> Unit,
  close : () -> Unit,
  label : String,
  head? : () -> (String, String) = fn() { ("", "") },
  side? : @view.Side = Bottom,
  offset? : Double = offers_off,
  none? : (@view.View) -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  // (moved by ↓ or ↑: what is chosen then brought into sight)
  let keyed : @signals.Signal[Int] = @signals.signal(0, same=fn(a, b) { a == b })
  // (open, and not leaving: what its keys and presses are for)
  let live = Ref(false)
  let step = fn(by : Int) -> Bool {
    let n = @signals.untracked(keys).length()
    if n == 0 {
      return false
    }
    current.set(((current.untracked() + by) % n + n) % n)
    keyed.set(keyed.untracked() + 1)
    true
  }
  let take_now = fn() -> Bool {
    let n = @signals.untracked(keys).length()
    let at = current.untracked()
    if at < 0 || at >= n {
      return false
    }
    take(at)
    true
  }
  let can = fn() { live.val && @signals.untracked(open) }
  around
  .key_context("Offers")
  .on_action("offers.down", fn(_) { step(1) }, can~)
  .on_action("offers.up", fn(_) { step(-1) }, can~)
  .on_action("offers.take", fn(_) { take_now() }, can~)
  // (Escape: it closed, nothing else; closed, the dialog's)
  .on_key(fn(k) {
    if k.code == @ui.key_escape && k.mods == 0 && can() {
      close()
      true
    } else {
      false
    }
  })
  |> ignore
  let layer = match around.lent(offers_layer_lent) {
    Some(l) => l
    None => around.tree.root()
  }
  layer.box(made_for=loc, fn(o) {
    // (let go as what holds the field is, out of sight as that leaves)
    o.lives_with(around).over(Is(true)) |> ignore
    o.show(open, leave=@kit.pop_out_ms, fn(shown) {
      shown.over(Is(true)) |> ignore
      live.val = true
      shown.owns(fn() { live.val = false }) |> ignore
      // (how far in it is, from the moment it opened; out from the moment it closed)
      let way = EdgeWay::new(0.0)
      shown.reacts(fn() { shown.leaving() }, fn(going) {
        if going {
          live.val = false
          way.go(shown, 0.0, @kit.pop_out_ms, ease=Leave)
        } else {
          live.val = true
          way.go(shown, 1.0, @kit.pop_ms)
        }
      })
      let look = fn() {
        let p = way.shown(shown)
        if shown.leaving() {
          @kit.pop_out.at(p, p)
        } else {
          @kit.pop_in.at(p, p)
        }
      }
      let panel : Ref[@view.View?] = Ref(None)
      // (a press anywhere in the window outside it and the field's frame: closed as it goes down, the press what it lands
      // on's as ever)
      shown.reacts(fn() { shown.window_downs() }, at_start=false, fn(_) {
        let (x, y) = shown.window_down_point()
        let on = fn(v : @view.View?) {
          match v {
            Some(p) =>
              match p.tree.target_at(x, y) {
                Pressed(id) | Dragged(id) | Hosted(id) => p.tree.holds(p.id(), id)
                _ => false
              }
            None => false
          }
        }
        // (on the field's frame anywhere, as on its trigger: kit's popover's press outside but on its trigger)
        let (ax, ay, aw, ah) = anchor.placed_window_now()
        let on_field = x >= ax && x < ax + aw && y >= ay && y < ay + ah
        if live.val && !(on(panel.val) || on_field) {
          close()
        }
      })
      shown.box(fn(p) {
        panel.val = Some(p)
        p
        .beside(anchor.id(), side~, along=Start, offset~, padding=8.0, width=Anchor)
        .max_height(By(fn() { Some(dmax(0.0, over_room(shown).1 - 16.0)) }))
        .glass(By(fn() { Some(glass_floating()) }))
        .shadow(By(fn() { (2.0, 1.0, @ui.tree_theme().shadow) }))
        .clips(Is(true))
        .alpha(By(fn() { look().alpha }))
        .scale(By(fn() { look().sx }), about=FromBeside)
        .says(Is(Some(@view.said(Dialog, label~))))
        // (a press on it its own, not outside it: on what of it takes none, nothing)
        |> ground_node
        |> ignore
        style_node(p, fn() { offers_box })
        p.box(fn(body) {
          // (all it holds as far in as its look says, past the panel's own glass and shadow: Look's `words`)
          body.alpha(By(fn() { look().words })).max_height(Is(Some(offers_most - 2.0 * panel_pad))) |> ignore
          body.scrolls(@view.Scroll::new(), slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(b) {
            b.show(fn() { head().0 != "" }, at_once=true, fn(h) {
              style_node(h, fn() { offers_head })
              words_node(h, fn() { head().0 }, fn() { offers_head_words }) |> ignore
              h.show(fn() { head().1 != "" }, at_once=true, fn(q) {
                words_node(q, fn() { head().1 }, fn() { offers_typed }) |> ignore
              })
            })
            match none {
              Some(say) => b.show(fn() { keys().is_empty() }, at_once=true, say)
              None => ()
            }
            b.each(fn() { keys() }, fn(k) { k }, fn(cell, k) {
              let key = k.untracked()
              let at = fn() {
                match keys().search(key) {
                  Some(i) => i
                  None => -1
                }
              }
              let on = fn() { current.get() == at() }
              cell.box(fn(r) {
                style_node(r, fn() { (if on() { offers_row_on } else { offers_row }).then(pick_high()) }, in_row=false)
                r
                .presses(Is(true))
                .says(By(fn() { Some(@view.said(Button, label=name(key), selected=on())) }))
                .on_press(fn() {
                  let i = @signals.untracked(at)
                  if live.val && i >= 0 {
                    current.set(i)
                    take(i)
                  }
                })
                // (the pointer moving onto it: the one chosen)
                .on_pointer_moved(fn() {
                  let i = @signals.untracked(at)
                  if i >= 0 && current.untracked() != i {
                    current.set(i)
                  }
                })
                |> ignore
                // (chosen by ↓ or ↑: in sight where it scrolls)
                r.reacts(fn() { keyed.get() }, at_start=false, fn(_) {
                  if @signals.untracked(on) {
                    r.tree.show_in_sight(r.id())
                  }
                })
                row(r, key, on)
              })
              |> ignore
            })
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
  })
  |> ignore
}
