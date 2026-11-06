// The same quote card in a message and waiting in the composer. Its source and comment stay in place as the
// quote changes; the caller supplies the picture and the editable comment, owned by this card, and the box its picture
// is laid out in without the picture (`picture_box`: a copy's room for it, the same box by what the caller says of it,
// nothing of the picture read back as laid out).

///|
pub(all) struct QuoteCardNode {
  root : @view.View
  card : @view.View
  words : @view.View
  copy : (@view.View, WordsWidth?) -> QuoteCardNode
  sent_shift : () -> (Double, Double)
}

///|
/// How wide a card's words are laid out where they are not as wide as the card (a flying copy's: its source's lines on
/// their way to its message's): `width` of how big `anchor` is laid out in the same layout (Layout::anchor: None while
/// it is laid out to nothing, or none said) and of how far `way` says it has gone.
pub(all) struct WordsWidth {
  anchor : @view.View?
  way : () -> Double
  width : ((Double, Double)?, Double) -> Double
}

///|
/// Words laid out `w` wide, whatever else is laid out (a snapshot's: as wide as they were sent).
pub fn WordsWidth::fixed(w : Double) -> WordsWidth {
  { anchor: None, way: fn() { 0.0 }, width: fn(_, _) { w } }
}

///|
pub fn quote_ground() -> Int64 {
  @ui.tree_theme().color(Over(Bg, faint_ground))
}

///|
pub fn quote_card_node(
  parent : @view.View,
  author : () -> String,
  words : () -> String,
  role? : () -> String = fn() { "" },
  comment? : () -> String = fn() { "" },
  composer? : Bool = false,
  corner? : () -> Double = fn() { row_corner },
  jump? : () -> Unit,
  remove? : () -> Unit,
  picture? : (@view.View) -> Unit,
  picture_box? : (@view.View) -> Unit,
  picture_shown? : () -> Bool = fn() { true },
  comment_field? : (@view.View) -> Unit,
  words_width? : WordsWidth,
  tips? : TipLayer,
) -> QuoteCardNode {
  let hung = composer && remove is Some(_)
  let pin = fn() { pin_of(author(), role()) }
  let card_at : Ref[@view.View?] = Ref(None)
  let words_at : Ref[@view.View?] = Ref(None)
  let make = fn(outer : @view.View) {
    card_at.val = Some(outer.box(fn(card) {
      card.radius(By(fn() { if composer { corner() } else { quote_corner } }))
      .clips(Is(words_width is None))
      .gap(Is(if composer { 0.0 } else { 6.0 }))
      .padding(Is(if composer { (0.0, 0.0, 0.0, 0.0) } else { (8.0, 8.0, 8.0, 8.0) }))
      .ground(By(fn() {
        if composer {
          if theme().dark { over(theme().p.raised, alpha(theme().p.text, 0.1)) } else { @ui.tree_theme().color(Neutral) }
        } else { quote_ground() }
      })) |> ignore
      card.box(fn(source) {
        source.padding(By(fn() {
          if composer {
            let start = if pin() == "" { quote_in_composer.px() } else { quote_pin_in_composer }
            let top = if pin() == "" { quote_over_composer } else { quote_pin_in_composer }
            (start, top, if hung { quote_in_composer.px() } else { quote_end_composer }, 0.0)
          } else {
            (if pin() == "" { quote_in } else { quote_pin_in - quote_card_in },
              if pin() == "" { 0.0 } else { quote_pin_in - quote_card_in }, quote_in, 0.0)
          }
        })) |> ignore
        match jump {
          Some(go) => source.presses(Is(true)).on_press(go)
            .says(By(fn() { Some(@view.said(Button, label=t("web-main.quote.jump"))) })) |> ignore
          None => ()
        }
        match tips {
          Some(layer) => tip_node(layer, source, fn() { if jump is Some(_) { t("web-main.quote.jump") } else if pin() != "" { words() } else { "" } }) |> ignore
          None => ()
        }
        source.box(fn(row) {
          row.row(Is(true)).gap(Is(4.0)).lines_up(Is(Some(Start))) |> ignore
          row.pick(fn() { pin() != "" }, fn(mark, numbered) {
            if numbered {
              mark.height(Is(Some(quote_pin_h))).min_width(Is(Some(quote_pin_h)))
              .padding(Is((4.0, 0.0, 4.0, 0.0))).radius(Is(quote_pin_h / 2.0))
              .ground(By(fn() { theme().p.accent })).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
              mark.box(fn(n) {
                n.words(By(pin)).words_look(By(fn() { @ui.style_words(quote_pin_words) }))
                .ink(By(fn() { @ui.tree_theme().color(OnAccent) })) |> ignore
              }) |> ignore
            } else {
              mark.height(Is(Some(18.0))).lies_along(Is(Middle)) |> ignore
              icon_node(mark, "quote", quote_icon, By(fn() { theme().p.accent })) |> ignore
            }
          })
          let said = fn(text : @view.View) {
            text
            .words_runs(By(fn() {
              if pin() != "" {
                [@view.words_run(words().split("\n").next().map(fn(s) { s.to_string() }).unwrap_or(""))]
              } else {
                [@view.words_run(t("web-main.quote.author", args=[("author", author())]), weight=500, ink=theme().p.text), @view.words_run(words())]
              }
            }))
            .words_look(By(fn() { @ui.style_words(quote_text) }))
            .runs_look(Is({ ..@view.runs_plain, max_lines: 2 }))
            .ink(By(fn() { if jump is Some(_) && (source.pointed() || source.pressed()) { theme().p.text } else { theme().p.muted } })) |> ignore
          }
          words_at.val = Some(match words_width {
            None => row.box(fn(text) {
              text.min_width(Is(Some(0.0))).grow(Is(1.0)).shrink(Is(1.0)) |> ignore
              said(text)
            })
            // A flying card carries its source's line width. Flexing that width into the destination card would
            // rewrap the source before its path has begun: its words laid out as wide as it says, in its own layout.
            Some(by) => {
              let held = row.box(fn(held) { held.min_width(Is(Some(0.0))).grow(Is(1.0)).shrink(Is(1.0)) |> ignore })
              let text = held.box(said)
              held.layout_box(By(by.way), sized=true, fn(lay, way) {
                let w = (by.width)(by.anchor.bind(fn(a) { lay.anchor(a) }), way)
                let (_, h) = lay.measure(text, w)
                lay.place(text, 0.0, 0.0)
                lay.size_to(h)
              }) |> ignore
              text
            }
          })
        }) |> ignore
      }) |> ignore
      match picture {
        Some(make_picture) => card.show(picture_shown, fn(p) {
          let inset = corner_inset - quote_card_in
          p.row(Is(true)).padding(Is(if composer { (16.0, 6.0, 16.0, 0.0) } else { (inset, 0.0, inset, inset) })) |> ignore
          make_picture(p)
        })
        None => ()
      }
      let comment_in = if composer { (16.0, 3.0, 16.0, 10.0) } else { (6.0, 0.0, 6.0, 0.0) }
      match comment_field {
        Some(make_field) => card.box(fn(c) { c.padding(Is(comment_in)) |> ignore; make_field(c) }) |> ignore
        None => card.show(fn() { comment() != "" }, fn(c) {
          c.padding(Is(comment_in)) |> ignore
          c.box(fn(t) { t.words(By(comment)).words_look(By(fn() { @ui.style_words(quote_said) })).ink(By(fn() { theme().p.text })) |> ignore }) |> ignore
        })
      }
      if !composer {
        match remove {
          Some(go) => card.box(fn(over) {
            let reach = capsule_in(quote_corner, card_button_side)
            over.over(Is(true)).padding(Is((0.0, reach, reach, 0.0)))
            .lines_up(Is(Some(End))).lies_along(Is(Start)) |> ignore
            card_button_node(over, "close", fn() { t("web-main.quote.remove") }, go, tips?=tips) |> ignore
          }) |> ignore
          None => ()
        }
      }
    }))
  }
  let root = match remove {
    Some(go) if composer => with_corner_remove_node(parent, fn() { t("web-main.quote.remove") }, corner, go, make)
    _ => parent.box(make)
  }
  { root, card: card_at.val.unwrap(), words: words_at.val.unwrap(),
    sent_shift: fn() { quote_sent_shift(author(), role()) },
    copy: fn(p, width) {
      // The picture has its own flight. Repeating its factory here would register the flying copy as the real
      // message's landing and preview thumbnail, then remove that registration when the copy is released.
      // (its room as its caller says it is laid out, `picture_box`: the same box the picture is laid out in, nothing
      // of the picture's laid size read back; none said, none)
      quote_card_node(p, author, words, role~, comment~, composer~, corner~,
        picture?=picture.bind(fn(_) { picture_box }), picture_shown~, words_width?=width)
    },
  }
}

///|
/// The room a message's quote card's own picture has (quote_card_node's `picture`), the card's at most `most` wide:
/// what is left of that inside the card's padding and the picture's row's inset.
pub fn quote_picture_room(most : Double) -> Double {
  let inset = corner_inset - quote_card_in
  dmax(0.0, most - 2.0 * (8.0 + inset))
}
