// A send takes its sources from the retained cards before taking the draft. Flight's timing and faces remain
// shared with other callers; none of these sources depends on an old page having measured a composer that frame.

///|
fn composer_card_state(node : @view.View) -> @ui.DrawnState? {
  guard @ui.view_tree() is Some(tree) && node.alive() else { return None }
  guard tree.drawn_of(node.id()) is Some(d) else { return None }
  let rect = (d.x, d.y, d.w, d.h)
  Some({ rect, grown: rect, clip: tree.seen_bounds(node.id(), drawing=true), alpha: d.alpha, soft: (0.0, 0.0, 0.0, 0.0) })
}

///|
fn composer_flying_face(corner : Double, draw : () -> Unit) -> Unit {
  let previous = @sf.composer_round.val
  @sf.composer_round.val = corner
  draw()
  @sf.composer_round.val = previous
}

///|
fn flying_comment_node(parent : @view.View, text : String, hint : Bool) -> Unit {
  @ui.field(parent, @ui.Field::new(text~), max_lines=1,
    size_by=fn() { @sf.theme().t.ui }, line_by=fn() { @sf.theme().t.ui_line },
    placeholder_by=fn() { @sf.t("web-main.quote.commentPlaceholder") },
    colors_by=fn() { let p = @sf.theme().p; (p.text, if hint { p.subtle } else { 0L }, p.accent) })
  .focusable(Is(false)).presses(Is(false)).hides(Is(true)) |> ignore
}

///|
/// Snapshot values belong to the send, so clearing or editing the draft cannot change what is in flight.
fn flying_quote_face_node(
  parent : @view.View,
  source : @sfbase.Quote,
  written : String,
  words_width : Double?,
  corner : Double,
  picture : (Double, Double)?,
) -> Unit {
  @sf.quote_card_node(parent, fn() { source.author }, fn() { source.text }, role=fn() { source.role },
    composer=true, corner=fn() { corner }, words_width=fn() { words_width },
    picture?=picture.map(fn(s) { fn(p) { p.width(Is(Some(s.0))).height(Is(Some(s.1))) |> ignore } }),
    comment_field=fn(p) { flying_comment_node(p, written, false) }) |> ignore
}

///|
fn composer_flying_nodes(src : Source, w : Writing, station : String, extras : ComposerExtrasNode, corner : Double) -> Array[FlyingFile] {
  let all : Array[FlyingFile] = []
  let going = going_files(w).map(fn(f) { text(Some(f), "id") })
  for f in w.files.get() {
    let v = Some(f)
    let id = text(v, "id")
    let picture = waiting_picture(src, w, v)
    let key = flying_key(v, going.contains(id), picture is Some(_))
    let shown = match extras.files.get(id) { Some(node) => composer_card_state(node); None => None }
    match shown {
      Some(shown) if key != "" => {
        let wide = shown.rect.2
        let restore = restorable(w, v)
        all.push({ key, from: shown.rect, shown: Some(shown), picture, paint: None, ground: 0L,
          leaving: None, quote_words: None, quote_to: None, source_scale: 1.0,
          node: Some(fn(p) { flying_file_face_node(p, v, picture, corner, wide, restore) }), leaving_node: None,
          face: fn() { composer_flying_face(corner, fn() {
            let c = @ui.current()
            match picture {
              Some(p) => picture_tile(c, local_media(p, file_kind(text(v, "name"))), going_now(v), gone_up(v), text(v, "error")) |> ignore
              None => c.box(style=@ui.style(w=Fixed(wide)), fn() { waiting_card(c, "flying/" + id, v, restore~) |> ignore }) |> ignore
            }
          }) },
        })
      }
      _ => ()
    }
  }
  for i, q in sent_quotes(w) {
    let v = Some(w.quotes.get()[i])
    let id = text(v, "id")
    let picture_shown = match extras.pictures.get(id) { Some(node) => composer_card_state(node); None => None }
    let picture = match (quote_picture(@ui.current(), src, w, station, v), picture_shown) {
      (Some((p, own)), Some(shown)) if flying_key(own, going.contains(text(own, "id")), true) != "" => Some((p, own, shown))
      _ => None
    }
    match extras.quotes.get(id) {
      Some(card) => match composer_card_state(card.card) {
        Some(shown) => {
          let source = @sfbase.quote_of(q)
          let written = text(v, "comment")
          let copy = @ui.Field::new(text=written)
          let wide = card.card.placed_now().2
          let source_scale = if wide > 0.0 { shown.rect.2 / wide } else { 1.0 }
          // The flight copies the words as they were placed with the source card, before the send takes the draft.
          let words_width = card.words.placed_now().2
          let hint = if written == "" {
            let lines = match extras.comments.get(id) { Some(f) => f.lines(); None => None }
            lines.map(fn(lines) {
              (lines.room, fn() {
                quote_comment_field(@ui.current(), "flying/quote-hint/" + id, @ui.Field::new()) |> ignore
              })
            })
          } else { None }
          let ground = match @ui.view_tree() {
            Some(tree) => tree.drawn_of(card.card.id()).map(fn(d) { d.ground }).unwrap_or(0L)
            None => 0L
          }
          all.push({ key: @sfbase.quote_key(i), from: shown.rect, shown: Some(shown), picture: None, paint: None, ground,
            leaving: hint, quote_words: Some(("flight/quote-words/" + id, words_width)), quote_to: None, source_scale,
            node: Some(fn(p) { flying_quote_face_node(p, source, written, Some(words_width), corner,
              picture.map(fn(p) { (p.2.rect.2, p.2.rect.3) })) }),
            leaving_node: if hint is Some(_) { Some(fn(p) { flying_comment_node(p, "", true) }) } else { None },
            face: fn() { composer_flying_face(corner, fn() {
              let c = @ui.current()
              c.box(style=@ui.style(w=Fixed(wide)), fn() {
                @sf.quote_card(c, "flying/quote/" + id, source.author, source.text, role=source.role,
                  composer=true, words_width~,
                  picture?=picture.map(fn(p) { fn() {
                    let (_, _, picture_w, picture_h) = p.2.rect
                    c.box(style=@ui.style(w=Fixed(picture_w), h=Fixed(picture_h)), fn() {  }) |> ignore
                  } }),
                  comment_field=fn() { quote_comment_field(c, "flying/quote-comment/" + id, copy, hint=hint is None) |> ignore }) |> ignore
              }) |> ignore
            }) },
          })
        }
        None => ()
      }
      None => ()
    }
    match picture {
      Some((p, own, shown)) => all.push({ key: @sfbase.quote_picture_key(i), from: shown.rect, shown: Some(shown), picture: Some(p.key),
        paint: None, ground: 0L, leaving: None, quote_words: None, quote_to: None, source_scale: 1.0,
        node: Some(fn(at) { composer_picture_tile_node(at, fn() { p }, fn() { own }, fn() { corner }, media_content_node) |> ignore }),
        leaving_node: None,
        face: fn() { composer_flying_face(corner, fn() {
          let c = @ui.current()
          let now = quote_picture(c, src, w, station, v).map(fn(p) { p.0 }).unwrap_or(p)
          let keep = if now.key == "" && p.key != "" { p } else { now }
          picture_tile(c, keep, going_now(own), gone_up(own), text(own, "error")) |> ignore
        }) },
      })
      None => ()
    }
  }
  all
}

///|
fn flying_file_face_node(parent : @view.View, value : Json?, picture : String?, corner : Double, width : Double, restore : Bool) -> Unit {
  match picture {
    Some(key) => composer_picture_tile_node(parent,
      fn() { local_media(key, file_kind(text(value, "name"))) }, fn() { value }, fn() { corner }, media_content_node) |> ignore
    None => {
      @sf.file_card_node(parent, fn() { waiting_card_info(value) }, composer=true, floating=true, corner=fn() { corner },
        retry=fn() { }, retry_shown=fn() { text(value, "error") != "" },
        restore=fn() { }, restore_shown=fn() { restore })
      .width(Is(Some(width))).hides(Is(true)) |> ignore
    }
  }
}
