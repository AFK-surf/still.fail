// What a message quotes as nodes of the window's tree (message.mbt's quotes, its styles the same): each quote a card
// of its own ahead of the message (@sf.quote_card_node), its own picture in it (the file of the message's that it
// names: a mark's screenshot, an image or a video quoted) concentric with the card; pressed, it goes to the message it
// quotes where its place says where (MessageNodeHere's `jump`). Not here: a quote sent from the composer flying in
// (the list's flight), the passage lit where it is gone to (the list's).

///|
/// What a message quotes (`quotes`, of its `files`: the one each names in its card) in `v`, as they change: the
/// viewer's (`mine`) at the column's end, as wide as the widest needs and at most as its bubble may be; anyone
/// else's across the column. `at` names where its message is (message_place: its quotes' pictures `at/q:<i>`); `said`
/// its `said` (MessageFilesAt's).
fn message_quotes_node(
  v : @view.View,
  src : Source,
  here : MessageNodeHere,
  quotes : () -> Array[Quote],
  files : () -> Array[Attachment],
  mine : Bool,
  at : String,
  said? : () -> Bool = fn() { false },
) -> Unit {
  let place = message_files_at(here, said)
  v.show(fn() { quotes().length() > 0 }, fn(s) {
    s.box(fn(cards) {
      @sf.style_node(cards, fn() {
        if mine {
          quote_cards_end.then(@ui.style(max_w=Fixed(mine_most_of((here.width)()))))
        } else {
          quote_cards
        }
      })
      let keys = fn() { quotes().mapi(fn(i, q) { q.ts + "/" + i.to_string() }) }
      cards.each(keys, fn(k) { k }, fn(slot, k) {
        // (its row as wide as the cards' column, as the old card is, w=Full in it: quote_box)
        @sf.style_node(slot, fn() { quote_card_row })
        // (read through its key, never kept: its place among the message's quotes)
        let i = fn() { keys().search(k.get()).unwrap_or(0) }
        let q = fn() -> Quote {
          match quotes().get(i()) {
            Some(q) => q
            None => { author: "", text: "", comment: "", ts: "", role: "", file: "" }
          }
        }
        let own = fn() { quote_file(q(), files()) }
        let jumps = fn() { here.jump is Some(_) && q().ts != "" }
        @sf.quote_card_node(
          slot,
          here.tips,
          fn() { q().author },
          fn() { q().text },
          fn() { q().role },
          fn() { q().comment },
          jumps,
          fn() {
            match here.jump {
              Some(go) => {
                let now = q()
                if now.ts != "" {
                  go(now.ts, now.text)
                }
              }
              None => ()
            }
          },
          pictured=fn() { own() is Some(_) },
          picture=fn(b) { quote_picture_node(b, src, here, place, own, at + "/q:" + @signals.untracked(i).to_string()) },
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// A quote's card's row among its message's quotes: across the cards' column, where its card is across it (quote_box).
// kept across runs: a value (no field of it changes)
let quote_card_row : @ui.Style = @ui.css("w=Full")

///|
/// A quote's own file in its card (`own`, as it is now), as the old card's message_files lays its one file: at most as
/// wide as the card has room for, a picture's and a video's box their data's, its corner concentric with the card's
/// (quote_picture_corner).
fn quote_picture_node(
  b : @view.View,
  src : Source,
  here : MessageNodeHere,
  place : MessageFilesAt,
  own : () -> Attachment?,
  at : String,
) -> Unit {
  let a = fn() {
    match own() {
      Some(a) => a
      None => attachment_of({ "name": Json::string(""), "path": Json::string("") })
    }
  }
  let by = fn() -> (String, String, String)? { None }
  b.box(fn(column) {
    @sf.style_node(column, fn() { files_column })
    column.by_room(fn(r, room) {
      r.pick(at_once=true, fn() { file_kind(a().name) }, fn(p, kind) {
        match kind {
          "image" =>
            p.pick(at_once=true, fn() { media_size(a(), image_least, image_min_side, room.width()) }, fn(q, size) {
              message_image_node(q, src, place, a, by, at, size.0, size.1, corner=@sf.quote_picture_corner)
            })
            |> ignore
          "video" =>
            p.pick(
              at_once=true,
              fn() { (@sfbase.file_key(a()), media_size(a(), video_least, 0.0, room.width())) },
              fn(q, made) {
                message_video_node(q, src, here.tips, place, a, by, at, made.1.0, made.1.1, corner=@sf.quote_picture_corner)
              },
            )
            |> ignore
          _ =>
            p.box(fn(item) {
              item.max_width(By(fn() { Some(room.width()) })).shrink(Is(0.0)) |> ignore
              message_file_card_node(item, src, here.tips, place, a, by, at) |> ignore
            })
            |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}
