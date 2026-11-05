// File cards and the remove button shared by the composer and messages, made once. What the upload, download or
// draft says is read by each property; an action reads the file it acts on at that action's moment.

///|
pub(all) struct FileCardInfo {
  name : String
  size : Double
  path : String
  dir : Bool
  named : Bool
  pending : Bool
  sent : Double?
  error : String
  download : (Double, String)?
  title : String
  meta : String
} derive(Eq)

///|
pub fn file_card_info(
  name : String,
  size : Double,
  path? : String = "",
  dir? : Bool = false,
  named? : Bool = false,
  pending? : Bool = false,
  sent? : Double? = None,
  error? : String = "",
  download? : (Double, String)? = None,
  title? : String = "",
  meta? : String = "",
) -> FileCardInfo {
  { name, size, path, dir, named, pending, sent, error, download, title, meta }
}

///|
fn file_card_meta(info : FileCardInfo) -> String {
  if info.error != "" { return info.error }
  if info.pending {
    match info.sent {
      Some(s) if info.size > 0.0 =>
        t("web-main.file.uploadingPart", args=[("percent", (s / info.size * 100.0).floor().to_int().to_string()), ("size", file_size(info.size))])
      _ => t("common.uploading")
    }
  } else if info.meta != "" {
    info.meta
  } else {
    info.download.map(fn(d) { d.1 }).unwrap_or(file_size(info.size))
  }
}

///|
/// A file name keeps its extension whole while its stem gives way, as file_name does.
pub fn file_name_node(parent : @view.View, name : () -> String) -> @view.View {
  parent.box(fn(row) {
    row.row(Is(true)).min_width(Is(Some(0.0))) |> ignore
    let parts = fn() {
      let n = name()
      match n.rev_find(".") {
        Some(i) if i > 0 && n.length() - i <= name_ext_most =>
          (n.view(end_offset=i).to_string(), n.view(start_offset=i).to_string())
        _ => (n, "")
      }
    }
    row.box(fn(w) {
      w.words(By(fn() { parts().0 })).words_look(By(fn() { @ui.style_words(card_name) }))
      .ink(By(fn() { theme().p.text })).cuts(Is(true)).min_width(Is(Some(0.0))) |> ignore
    }) |> ignore
    row.show(fn() { parts().1 != "" }, fn(w) {
      w.words(By(fn() { parts().1 })).words_look(By(fn() { @ui.style_words(card_name) }))
      .ink(By(fn() { theme().p.text })) |> ignore
    })
  })
}

///|
/// FileCard as nodes; the same card's changing information and optional end actions. `composer` is where it waits,
/// whose inner `corner` it follows. The returned node is the card, for a preview or a flight to use as its source.
pub fn file_card_node(
  parent : @view.View,
  info : () -> FileCardInfo,
  composer? : Bool = false,
  floating? : Bool = false,
  corner? : () -> Double = fn() { row_corner },
  open? : () -> Unit,
  open_shown? : () -> Bool = fn() { true },
  retry? : () -> Unit,
  retry_shown? : () -> Bool = fn() { true },
  retry_label? : () -> String = fn() { t("web-main.composer.retryUpload") },
  remove? : () -> Unit,
  remove_shown? : () -> Bool = fn() { true },
  remove_label? : () -> String = fn() { t("web-main.file.remove", args=[("name", info().name)]) },
  restore? : () -> Unit,
  restore_shown? : () -> Bool = fn() { true },
  slot? : Bool = false,
  tips? : TipLayer,
) -> @view.View {
  parent.box(fn(card) {
    let ends = fn() {
      (if retry is Some(_) && retry_shown() { 1 } else { 0 }) +
      (if restore is Some(_) && restore_shown() { 1 } else { 0 }) +
      (if remove is Some(_) && remove_shown() { 1 } else { 0 }) + (if slot { 1 } else { 0 })
    }
    let hot = fn() { open is Some(_) && open_shown() && card.pointed() }
    card.row(Is(true)).max_width(Is(Some(file_card_w)))
    .height(Is(Some(if composer { 56.0 } else { 52.0 })))
    .gap(Is(8.0)).lines_up(Is(Some(Middle)))
    .padding(By(fn() {
      if composer { (16.0, 8.0, 16.0, 8.0) } else {
        (14.0, 0.0, if ends() > 0 { 14.0 } else { file_capsule_words_end }, 0.0)
      }
    }))
    .radius(By(fn() { if composer { corner() } else { 26.0 } }))
    .ground(By(fn() {
      let ground = if info().named { 0L } else if composer && theme().dark {
        over(theme().p.raised, alpha(theme().p.text, 0.1))
      } else { @ui.tree_theme().color(Neutral) }
      let shown = if hot() { if composer && !info().named { over(ground, theme().p.hover) } else { theme().p.hover } } else { ground }
      // A copy carried above the page takes its surface with it, including the ground under a translucent tint.
      if floating { over(theme().p.bg, shown) } else { shown }
    }))
    .edge(By(fn() { if info().named { (1.0, theme().p.line_strong) } else { (0.0, 0L) } }))
    .edge_dashed(By(fn() { info().named }))
    .says(By(fn() { Some(@view.said(Group, label=if info().title != "" { info().title } else { info().name })) }))
    |> ignore
    match open {
      Some(go) => card.on_press(fn() { if open_shown() { go() } }).presses(By(open_shown)) |> ignore
      None => ()
    }
    card.pick(fn() { info().pending && info().sent is None }, fn(mark, waiting) {
      mark.lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
      if waiting {
        mark.width(Is(Some(30.0))).height(Is(Some(36.0))) |> ignore
        spinner_node(mark, size=tile_going_spinner) |> ignore
      } else {
        mark.width(Is(Some(card_mark_size))).height(Is(Some(card_mark_size))) |> ignore
        icon_node(mark, "file", card_mark_size,
          By(fn() { if info().error != "" { theme().p.red } else { theme().p.muted } }),
          name_now=fn() { if info().dir { "folder" } else { file_mark(info().name) } }) |> ignore
      }
    })
    card.box(fn(words) {
      words.min_width(Is(Some(0.0))).cuts(Is(true)) |> ignore
      if composer { words.grow(Is(1.0)).basis(Is(Some(0.0))) |> ignore }
      words.pick(fn() { info().title != "" }, fn(w, title) {
        if title {
          w.words(By(fn() { info().title })).words_look(By(fn() { @ui.style_words(card_name) }))
          .ink(By(fn() { theme().p.text })).cuts(Is(true)).min_width(Is(Some(0.0))) |> ignore
        } else {
          file_name_node(w, fn() { info().name }) |> ignore
        }
      })
      words.box(fn(w) {
        w.words(By(fn() { file_card_meta(info()) })).words_look(By(fn() { @ui.style_words(card_meta) }))
        .ink(By(fn() { if info().error != "" { theme().p.red } else { theme().p.muted } })) |> ignore
      }) |> ignore
    }) |> ignore
    for (action, shown, icon, label) in [
      (retry, retry_shown, "refresh", retry_label),
      (restore, restore_shown, "edit", fn() { t("web-main.composer.expandPaste") }),
      (remove, remove_shown, "close", remove_label),
    ] {
      match action {
        Some(press) => card.show(shown, fn(at) {
          if !composer {
            at.width(Is(Some(24.0))).height(Is(Some(24.0))).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
          }
          card_button_node(at, icon, label, press, tips?=tips) |> ignore
        })
        None => ()
      }
    }
    if slot { card.box(fn(s) { s.width(Is(Some(card_button_side))).height(Is(Some(card_button_side))) |> ignore }) |> ignore }
    match tips {
      Some(layer) => tip_node(layer, card, fn() { if info().path != "" { info().path } else if info().title != "" { file_card_meta(info()) } else { info().name } }) |> ignore
      None => ()
    }
  })
}

///|
fn card_button_node(parent : @view.View, icon : String, label : () -> String, press : () -> Unit, tips? : TipLayer) -> @view.View {
  parent.box(fn(b) {
    let hot = fn() { b.pointed() || b.pressed() }
    b.width(Is(Some(card_button_side))).height(Is(Some(card_button_side))).radius(Is(card_button_side / 2.0))
    .lines_up(Is(Some(Middle))).lies_along(Is(Middle))
    .ground(By(fn() { if hot() { theme().p.hover } else { 0L } }))
    .presses(Is(true)).focusable(Is(true)).on_press(press)
    .says(By(fn() { Some(@view.said(Button, label=label())) })) |> ignore
    icon_node(b, icon, if icon == "close" { card_close_icon } else { card_button_icon },
      By(fn() { if hot() { theme().p.text } else { theme().p.muted } })) |> ignore
    match tips {
      Some(layer) => tip_node(layer, b, label) |> ignore
      None => ()
    }
  })
}

///|
/// A waiting picture or card with its remove button hung on the same corner as with_corner_remove. Both are nodes;
/// the button's offset moves its hit target as well as its drawing. `width` gives a tile its width; None fills a row.
/// `placed`: `width` worked out of where things are laid out, in what is laid out after them (Live's Placed: in what a
/// node holds by its room, View::by_room).
pub fn with_corner_remove_node(
  parent : @view.View,
  label : () -> String,
  corner : () -> Double,
  remove : () -> Unit,
  body : (@view.View) -> Unit,
  width? : () -> Double? = fn() { None },
  turn? : () -> Double = fn() { 0.0 },
  placed? : Bool = false,
) -> @view.View {
  let live = fn(f : () -> Double?) -> @view.Live[Double?] { if placed { Placed(f) } else { By(f) } }
  parent.box(fn(outer) {
    let reach = fn() { corner_remove_reach(corner()) }
    outer.row(Is(true)).width(live(fn() { width().map(fn(w) { w + reach() }) })) |> ignore
    outer.box(fn(inner) {
      inner.width(live(width)).min_width(Is(Some(0.0)))
      .grow(if placed { Placed(fn() { if width() is None { 1.0 } else { 0.0 } }) } else { By(fn() { if width() is None { 1.0 } else { 0.0 } }) }) |> ignore
      body(inner)
      inner.box(fn(over) {
        over.over(Is(true)).lines_up(Is(Some(End))).lies_along(Is(Start)) |> ignore
        corner_remove_face_node(over, turn~)
        .offset(By(fn() { (reach(), -reach()) })).presses(Is(true)).focusable(Is(true))
        .says(By(fn() { Some(@view.said(Button, label=label())) })).on_press(remove) |> ignore
      }) |> ignore
    }) |> ignore
  })
}

///|
/// The same corner control's face, without an action: carried away with a sent quote.
pub fn corner_remove_face_node(parent : @view.View, turn? : () -> Double = fn() { 0.0 }) -> @view.View {
  parent.box(fn(button) {
    button.width(Is(Some(corner_remove_side))).height(Is(Some(corner_remove_side)))
    .radius(Is(corner_remove_side / 2.0)).ground(By(fn() { theme().p.text }))
    .lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
    icon_node(button, "close", card_close_icon, By(fn() { theme().p.canvas })).turn(By(turn)) |> ignore
  })
}
