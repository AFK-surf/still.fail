// A quote in a message as nodes of the window's tree (quote_card's, a message's: not the composer's, its styles the
// same): the passage, two lines at most, small and quiet after a quote's mark and whose it is (a page's or an image's
// mark: its pin's number and its first line instead); its own picture under it; what is said about it. Where it leads
// to its message, its words in the text's ink under the pointer, a tip saying so, a press going there.

///|
/// One quote of a message (quote_card's) in `parent`, as what it is given says as that changes: `author`'s `words`
/// (`role` a page's or an image's mark: its pin), what is said about it (`comment`, "" none). Where it `jumps` (where it
/// leads and the message it quotes is said), pressed it does `jump`, its tip says so and its words take the text's ink
/// under the pointer; a pin's that does not, its tip its words whole. Its picture, where it `pictured`, made by
/// `picture` in its foot's corners (quote_picture's room). Its words are none of what is picked where what holds it has
/// its words picked (lent a picker that picks none: the old card's were not of what is picked). The card's node.
#callsite(autofill(loc))
pub fn quote_card_node(
  parent : @view.View,
  tips : TipLayer,
  author : () -> String,
  words : () -> String,
  role : () -> String,
  comment : () -> String,
  jumps : () -> Bool,
  jump : () -> Unit,
  pictured? : () -> Bool = fn() { false },
  picture? : (@view.View) -> Unit = fn(_) {  },
  loc~ : SourceLoc,
) -> @view.View {
  let pin = fn() { pin_of(author(), role()) }
  parent.box(made_for=loc, fn(card) {
    style_node(card, fn() { quote_box_message.then(@ui.style(clip=true)) })
    // (its words none of what is picked: what holds the list lends its picker to every words in pieces in it)
    card.lends(@view.runs_picker, fn(_) { Is((0, 0)) }) |> ignore
    card.box(fn(source) {
      // (a pin in its top corner: there the ladder's inset from both its edges, concentric with it)
      style_node(source, fn() { if pin() != "" { quote_source_pin } else { quote_source } })
      // (where it leads nowhere, a pin's tip says its words whole, shown by the pointer within it: tip_node's `within`,
      // what is pressed in it taking no press then)
      tip_node(tips, source, fn() { if !jumps() && pin() != "" { words() } else { "" } }, within=true) |> ignore
      // (what is pressed where it leads: all of its words' box, laid over it (what is pressed found past its words,
      // which take none); taking no press where it leads nowhere, and so not the words' box itself, whose tip a pin's
      // words have then)
      let hit = source.box(fn(h) {
        h.over(Is(true)) |> ignore
        presses_node(h, jump, on=jumps)
        h.says(By(fn() { if jumps() { Some(@view.said(Button, label=t("web-main.quote.jump"))) } else { None } })) |> ignore
        // (its tip saying where it leads, as a control's)
        tip_node(tips, h, fn() { if jumps() { t("web-main.quote.jump") } else { "" } }) |> ignore
      })
      // (its words' row, made anew as it comes to be a pin's or not: the pick's own box is the row, as quote_words')
      source.pick(fn() { pin() != "" }, fn(p, pinned) {
        style_node(p, fn() { quote_words })
        if pinned {
          p.box(fn(mark) {
            style_node(mark, fn() { quote_pin })
            // (its number part of a mark of a size said: at its size whatever the system's size of words, as a
            // badge's, apps/mbui/AGENTS.md; the old pin's grew out of it at 1.3, the coordinator of the migration,
            // 2026-11-12)
            mark_words_node(mark, pin, fn() { quote_pin_words }) |> ignore
          })
          |> ignore
          words_node(p, fn() { words().split("\n").next().map(fn(s) { s.to_owned() }).unwrap_or("") }, fn() {
            quote_text
          })
          |> ignore
        } else {
          p.box(fn(mark) {
            style_node(mark, fn() { quote_mark })
            icon_node(mark, "quote", quote_icon, By(fn() { theme().p.accent })) |> ignore
          })
          |> ignore
          let look = fn() { if jumps() && lit_node(hit) { quote_text_hot } else { quote_text } }
          // (beside its mark, in the room the row leaves it, as an old view's words in a row are)
          p.box(fn(w) {
            w
            .shrink(Is(1.0))
            .min_width(Is(Some(0.0)))
            .words_runs(By(fn() {
              [
                @ui.span(t("web-main.quote.author", args=[("author", author())]), weight=500, color=theme().p.text),
                @ui.span(words()),
              ]
            }))
            .words_look(By(fn() { @ui.style_words(quote_text) }))
            .ink(By(fn() { @ui.style_ink(look()) }))
            .allow_ellipsis(Is(true))
            |> ignore
          })
          |> ignore
        }
      })
    })
    |> ignore
    card.show(pictured, fn(s) {
      s.box(fn(b) {
        style_node(b, fn() { quote_picture })
        picture(b)
      })
      |> ignore
    })
    card.show(fn() { comment() != "" }, fn(s) {
      s.box(fn(b) {
        style_node(b, fn() { quote_comment })
        words_node(b, comment, fn() { quote_said }) |> ignore
      })
      |> ignore
    })
  })
}
