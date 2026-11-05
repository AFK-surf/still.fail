// The draft's attachments kept by their identities. Upload answers and quote comments change their properties;
// neither the editor nor another attachment is replaced for them. These nodes also name the sources of a send.

///|
struct ComposerExtrasNode {
  files : Map[String, @view.View]
  quotes : Map[String, @sf.QuoteCardNode]
  comments : Map[String, @ui.Field]
  pictures : Map[String, @view.View]
}

///|
fn waiting_card_info(v : Json?) -> @sf.FileCardInfo {
  let name = text(v, "name")
  let ref_ = field(v, "ref")
  match waiting_as(v) {
    ByPath => @sf.file_card_info(name, number(v, "size"), path=text(ref_, "path"),
      dir=flag(ref_, "dir"), named=true, meta=text(ref_, "stationName") + " · " + @sf.t("web-main.file.modePath"))
    Link => {
      let link = field(v, "link")
      let url = text(link, "url")
      @sf.file_card_info(url, 0.0, path=url, title=match text(link, "title") { "" => url; title => title }, meta=text(link, "site"))
    }
    Pasted => {
      let info = field(v, "pasted")
      @sf.file_card_info(name, number(v, "size"), pending=going_now(v), error=text(v, "error"),
        title=match text(info, "preview") { "" => @sf.t("web-main.composer.pastedText"); preview => preview },
        meta=@sf.t("web-main.composer.pasteAttachment", args=[("count", @sf.grouped(number(info, "characters")))]))
    }
    AnyFile => {
      let done = field(v, "done")
      @sf.file_card_info(if flag(ref_, "dir") { name + ".zip" } else { name },
        number(done, "size") + (if done is None { number(v, "size") } else { 0.0 }),
        path=text(done, "path"), pending=going_now(v), error=text(v, "error"),
        sent=match field(v, "sent") { Some(Number(n, ..)) => Some(n); _ => None })
    }
  }
}

///|
fn composer_extras_node(
  parent : @view.View,
  src : Source,
  w : Writing,
  station : () -> String,
  corner : () -> Double,
  file_end : () -> Double,
  media : (@view.View, () -> MediaPicture, () -> Double, () -> Double, @ui.Fit, () -> Double) -> Unit,
  moves? : (@view.View) -> Unit = fn(_) { },
  tips? : @sf.TipLayer,
) -> ComposerExtrasNode {
  let made : ComposerExtrasNode = { files: {}, quotes: {}, comments: {}, pictures: {} }
  let first = Ref(true)
  let coming = fn(slot : @view.View, body : (@view.View) -> Unit) {
    moves(slot)
    slot.box(fn(item) {
      let look = @motion.presence_node(item, initial=first.val, enter=@sf.waiting_in, exit=@sf.leave)
      item.alpha(By(fn() { look().alpha })).drawn_off(By(fn() { (look().dx, look().dy) })) |> ignore
      body(item)
    }) |> ignore
  }
  parent.gap(Is(10.0)) |> ignore
  parent.show(fn() { !w.quotes.get().is_empty() }, fn(column) {
    column.gap(Is(6.0)) |> ignore
    column.each(fn() { w.quotes.get() }, fn(q) { text(Some(q), "id") }, fn(slot, quote) {
      coming(slot, fn(item) {
        let id = @signals.untracked(fn() { text(Some(quote.get()), "id") })
        let q = fn() { Some(quote.get()) }
        let f = @ui.Field::new(text=@signals.untracked(fn() { text(q(), "comment") }))
        made.comments[id] = f
        let picture = fn() { quote_picture(@ui.current(), src, w, station(), q()) }
        let card = @sf.quote_card_node(item, fn() { text(q(), "author") }, fn() { text(q(), "text") },
          role=fn() { text(q(), "role") }, composer=true, corner~, remove=fn() { writing_unquote(src, w, id) },
          picture_shown=fn() { picture() is Some(_) },
          // (a copy's room for its picture: its tile's, thumb_side square)
          picture_box=fn(room) { room.box(fn(b) { b.width(Is(Some(thumb_side))).height(Is(Some(thumb_side))) |> ignore }) |> ignore },
          picture=fn(p) {
            let first = @signals.untracked(picture).unwrap()
            let kept = fn() { picture().unwrap_or(first) }
            let tile = composer_picture_tile_node(p, fn() { kept().0 }, fn() { kept().1 }, corner, media)
            made.pictures[id] = tile
            tile.owns(fn() { made.pictures.remove(id) }) |> ignore
          },
          comment_field=fn(p) {
            let field = @ui.field(p, f, max_lines=1,
              size_by=fn() { @sf.theme().t.ui }, line_by=fn() { @sf.theme().t.ui_line },
              placeholder_by=fn() { @sf.t("web-main.quote.commentPlaceholder") },
              colors_by=fn() { let p = @sf.theme().p; (p.text, p.subtle, p.accent) },
              submitted=fn(_) { w.field.focus() })
            // A core revision is adopted before the field's edit is considered, so it is never echoed back.
            field.reacts(fn() { text(q(), "comment") }, fn(s) { if f.text() != s { f.set(s) } })
            field.reacts(fn() { f.text() }, fn(s) {
              if s != @signals.untracked(fn() { text(q(), "comment") }) { writing_comment(src, w, id, s) }
            })
            field.reacts(fn() { w.focus.get() == id }, fn(yes) {
              if yes { f.focus(); writing_focused(src, w) }
            })
            // (its quote sent or taken out while this line has the focus: the words' field has it as the line goes, not
            // the window none and the screen's keyboard down)
            let had = Ref(false)
            field.reacts(fn() { field.focused() }, fn(f) { had.val = f })
            field.owns(fn() { if had.val { w.field.focus() } }) |> ignore
          }, tips?=tips)
        made.quotes[id] = card
        item.owns(fn() { made.quotes.remove(id); made.comments.remove(id) }) |> ignore
      })
    })
  })
  parent.show(fn() { !w.files.get().is_empty() }, fn(flow) {
    flow.row(Is(true)).gap(Is(6.0)).wraps(By(fn() { Some(6.0 + @sf.corner_remove_reach(corner())) }))
    .padding(By(fn() { (0.0, 0.0, file_end(), 0.0) })).lines_up(Is(Some(Start))) |> ignore
    flow.each(fn() { w.files.get() }, fn(f) { text(Some(f), "id") }, fn(slot, file) {
      // (a card as wide as a card is at most, or as the row leaves it where that is less, its remove button's reach
      // room past it as a tile's: said to the row, so it is laid out so, not read back from the row's laid size)
      let card = fn() { waiting_picture(src, w, Some(file.get())) is None }
      slot
      .width(By(fn() { if card() { Some(@sf.file_card_w) } else { None } }))
      .max_width_within(By(fn() { if card() { Some(@sf.file_card_w) } else { None } }))
      .margin(By(fn() { (0.0, 0.0, if card() { @sf.corner_remove_reach(corner()) } else { 0.0 }, 0.0) }))
      |> ignore
      coming(slot, fn(item) {
        let id = @signals.untracked(fn() { text(Some(file.get()), "id") })
        let v = fn() { Some(file.get()) }
        let picture = fn() { waiting_picture(src, w, v()) }
        item.pick(fn() { picture() is Some(_) }, fn(p, image) {
          if image {
            @sf.with_corner_remove_node(p, fn() { remove_label(v(), text(v(), "name")) }, corner,
              fn() { writing_remove(src, w, id) }, width=fn() { Some(thumb_side) }, fn(inside) {
                let tile = composer_picture_tile_node(inside, fn() { local_media(picture().unwrap_or(""), file_kind(text(v(), "name"))) }, v, corner, media,
                  retry=fn() { writing_retry(src, w, id) })
                made.files[id] = tile
                tile.owns(fn() { made.files.remove(id) }) |> ignore
                tile.on_press(fn() {
                  match @sfbase.writing_went_to(id) {
                    Some((s, _, bytes)) => {
                      let a = composer_attachment(id, text(v(), "name"), bytes)
                      @sfbase.keep_read(s + "//" + a.path, bytes)
                      @sfbase.open_preview(s, "", a)
                    }
                    None => ()
                  }
                }).presses(By(fn() { @sfbase.writing_went_to(id) is Some(_) })) |> ignore
                tile.reacts(fn() { @sfbase.writing_went_to(id).map(fn(v) { v.0 }).unwrap_or("") }, fn(s) {
                  if s != "" {
                    @sfbase.note_thumb_node(tile, s + "//draft:" + id, corner, fn() { picture().unwrap_or("") })
                  }
                })
                tile.alpha(By(fn() {
                  match @sfbase.writing_went_to(id) {
                    Some((s, _, _)) => @sfbase.thumb_shows(s + "//draft:" + id)
                    None => 1.0
                  }
                })) |> ignore
                match tips { Some(layer) => @sf.tip_node(layer, tile, fn() { match text(v(), "error") { "" => text(v(), "name"); e => e } }) |> ignore; None => () }
              }) |> ignore
          } else {
            let card_at : Ref[@view.View?] = Ref(None)
            let open = fn() {
              match waiting_as(v()) {
                Link => open_link(text(field(v(), "link"), "url"))
                ByPath | AnyFile => if field(v(), "ref") is Some(Object(_)) {
                  let (x, y, wide, high) = card_at.val.unwrap().rect()
                  ref_panel_from(src, w, station(), id, text(v(), "name"), At(x, y, wide, high))
                }
                Pasted => ()
              }
            }
            @sf.with_corner_remove_node(p, fn() { remove_label(v(), text(v(), "name")) }, corner,
              fn() { writing_remove(src, w, id) }, fn(inside) {
                let card = @sf.file_card_node(inside, fn() { waiting_card_info(v()) }, composer=true, corner~, open~,
                  open_shown=fn() { match waiting_as(v()) { Link => true; ByPath | AnyFile => field(v(), "ref") is Some(Object(_)); _ => false } },
                  retry=fn() { match waiting_as(v()) { Pasted => @sfbase.writing_paste_again(src, w, id); _ => writing_retry(src, w, id) } },
                  retry_shown=fn() { text(v(), "error") != "" },
                  restore_shown=fn() { restorable(w, v()) },
                  restore=fn() {
                    let back = text(field(v(), "pasted"), "text")
                    let words = if w.text.get() == "" { back } else { w.text.get() + "\n" + back }
                    @sfbase.refs_put(w.key, w.field, words)
                    writing_text(src, w, words)
                    writing_remove(src, w, id)
                    w.field.focus()
                  }, tips?=tips)
                card_at.val = Some(card)
                made.files[id] = card
                card.owns(fn() { made.files.remove(id) }) |> ignore
              }) |> ignore
          }
        })
      })
    })
  })
  first.val = false
  made
}

///|
fn composer_attachment(id : String, name : String, bytes : Bytes) -> Attachment {
  { name, path: "draft:" + id, size: bytes.length().to_double(), width: 0.0, height: 0.0,
    thumbhash: "", owner: "", upload: "", duration: 0.0, frames: 0, held: false }
}

///|
fn composer_picture_tile_node(
  parent : @view.View, picture : () -> MediaPicture, value : () -> Json?, corner : () -> Double,
  media : (@view.View, () -> MediaPicture, () -> Double, () -> Double, @ui.Fit, () -> Double) -> Unit,
  retry? : () -> Unit,
) -> @view.View {
  parent.box(fn(tile) {
    tile.width(Is(Some(thumb_side))).height(Is(Some(thumb_side))).radius(By(corner)).clips(Is(true))
    .edge(By(fn() { if text(value(), "error") != "" { (2.0, @sf.theme().p.red) } else { (0.0, 0L) } })) |> ignore
    media(tile, picture, fn() { thumb_side }, fn() { thumb_side }, FitCover, fn() { 0.0 })
    tile.show(fn() { picture().kind == "video" && !going_now(value()) && text(value(), "error") == "" }, fn(play) {
      play.over(Is(true)).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
      @sf.icon_node(play, "play-mark", thumb_play_side, Is(on_veil)) |> ignore
    })
    tile.show(fn() { going_now(value()) }, fn(veil) {
      veil.over(Is(true)).ground(By(fn() { @ui.tree_theme().color(Veil) })).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
      @sf.progress_spinner_node(veil, fn() { gone_up(value()) }, size=@sf.theme().round.glyph) |> ignore
    })
    tile.show(fn() { text(value(), "error") != "" }, fn(veil) {
      veil.over(Is(true)).ground(By(fn() { @ui.tree_theme().color(Veil) })).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
      @sf.icon_node(veil, "refresh", retry_icon, Is(on_veil)) |> ignore
      match retry {
        Some(again) => veil.presses(Is(true)).on_press(again).says(By(fn() { Some(@view.said(Button, label=@sf.t("web-main.composer.retryUpload"))) })) |> ignore
        None => ()
      }
    })
  })
}
