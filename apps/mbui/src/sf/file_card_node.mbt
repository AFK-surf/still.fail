// A file's card in a message (file_card's, as a message's file draws it: card_item) as nodes of the window's tree: its
// capsule, its mark, its name over its size or what its download says or why it failed, its own ↻ and ✕ at its end,
// each following what it is told as that changes.

///|
/// A message's file as a card in `parent` (file_card's, as card_item asks it): its capsule on the neutral ground, 236
/// at most, as wide as what it says; its line mark (red where it failed), its name (cut short in its middle, never its
/// extension) over `meta` (its size, how far its download has come, why it failed: `failed` in red); `retry` its ↻,
/// `remove` its ✕ at its end, each concentric with the end where it is the last, named as `retry_label` and
/// `remove_label` say, their tips in `tips`; pressed, `on_press` with what was pressed (the card itself: Open), the
/// hover ground under the pointer; right clicked or held by a finger, `menu` where (its menu: file_menu's). Read out as
/// a group named by its name; its name whole in a tip by it while what it says shows cut short (file_card's). The
/// node.
#callsite(autofill(loc))
pub fn file_card_node(
  parent : @view.View,
  tips : TipLayer,
  name : () -> String,
  meta : () -> String,
  failed : () -> Bool,
  retry : () -> Bool,
  remove : () -> Bool,
  retry_label : () -> String,
  remove_label : () -> String,
  on_press : (FileCardPress) -> Unit,
  menu? : (Double, Double) -> Unit,
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(card) {
    style_node(card, fn() {
      let ground = if retry() || remove() {
        card_box.then(card_box_round).then(card_end_justified)
      } else {
        card_box.then(card_box_round)
      }
      if hovered_node(card) {
        ground.then(card_hot)
      } else {
        ground
      }
    })
    card.says(By(fn() { Some(@view.said(Group, label=name())) })) |> ignore
    // (its name whole by it while what it says shows cut short: file_card's tip)
    tip_node(tips, card, name, repeats=true) |> ignore
    match menu {
      // (right clicked, its menu where the pointer is; held by a finger, there, felt, the press the menu's: lifting it
      // opens nothing. A mouse's button held is a press as long as any: file_menu's, menu_asked's)
      Some(open) => menu_presses_node(card, fn() { on_press(Open) }, fn(x, y, _) { open(x, y) })
      None => presses_node(card, fn() { on_press(Open) })
    }
    // (its mark, 24, concentric with its round start)
    card.box(fn(m) {
      style_node(m, fn() { card_mark }, in_row=true)
      icon_node(m, "file", card_mark_size, By(fn() { if failed() { theme().p.red } else { theme().p.muted } }), name_now=fn() {
        file_mark(name())
      })
      |> ignore
    })
    |> ignore
    // (as wide as what it says, cut short where the card is at its widest)
    card.box(fn(w) {
      style_node(w, fn() { card_words_hug }, in_row=true)
      file_name_node(w, name)
      words_node(w, meta, fn() { if failed() { card_failed } else { card_meta } }) |> ignore
    })
    |> ignore
    card.show(retry, fn(e) {
      card_end_node(e, tips, "refresh", fn() {
        if retry_label() != "" {
          retry_label()
        } else {
          t("web-main.composer.retryUpload")
        }
      }, fn() { on_press(Retry) })
    })
    card.show(remove, fn(e) {
      card_end_node(e, tips, "close", fn() {
        if remove_label() != "" {
          remove_label()
        } else {
          t("web-main.file.remove", args=[("name", name())])
        }
      }, fn() { on_press(Remove) })
    })
  })
}

///|
/// A file's name on one line in `parent` (file_name's): what is cut short the middle of it, never its extension (7 at
/// most, its dot with it).
#callsite(autofill(loc))
fn file_name_node(parent : @view.View, name : () -> String, loc~ : SourceLoc) -> Unit {
  let split = fn() -> (String, String) {
    let n = name()
    match n.rev_find(".") {
      Some(i) if i > 0 && n.length() - i <= name_ext_most =>
        (n.exact_view(end=i).to_owned(), n.exact_view(start=i).to_owned())
      _ => (n, "")
    }
  }
  parent.box(made_for=loc, fn(row) {
    style_node(row, fn() { name_row })
    row.box(fn(stem) {
      style_node(stem, fn() { name_stem_cut }, in_row=true)
      words_node(stem, fn() { split().0 }, fn() { card_name }) |> ignore
    })
    |> ignore
    row.show(fn() { split().1 != "" }, fn(e) { words_node(e, fn() { split().1 }, fn() { card_name }) |> ignore })
  })
  |> ignore
}

///|
/// A button at the end of a message's file card (card_end's and card_button's): in a room 24, 22 round, the hover
/// ground under the hand, its icon in the muted ink (the text's under the hand), named `label`, its tip saying it.
#callsite(autofill(loc))
fn card_end_node(
  parent : @view.View,
  tips : TipLayer,
  icon : String,
  label : () -> String,
  press : () -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  parent.box(made_for=loc, fn(room) {
    style_node(room, fn() { card_end_room }, in_row=true)
    @headless.button(room, label, fn(_) { press() }, fn(b, _) {
      style_node(b, fn() { if lit_node(b) { card_button_hot } else { card_button_box } })
      icon_node(b, icon, if icon == "close" { card_close_icon } else { card_button_icon }, By(fn() {
        let p = theme().p
        if lit_node(b) {
          p.text
        } else {
          p.muted
        }
      }))
      |> ignore
      tip_node(tips, b, label) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A file's name's stem as a node: as wide as it is, giving way to the extension after it where its row is short of
/// room (as the old view's name_stem comes out, laid out by the old view: a node's `Hug` gives no way).
// kept across runs: a value (no field of it changes)
let name_stem_cut : @ui.Style = @ui.css("w=Cut")

///|
// kept across runs: a value (no field of it changes)
let card_box_round : @ui.Style = @ui.css("radius=Full")
