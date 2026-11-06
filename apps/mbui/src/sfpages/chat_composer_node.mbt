// The whole input area of a chat: notices, one retained draft, attachments and copy choices. Frame geometry is
// supplied by the page as it changes; no getter reads a temporary old page's pane or composer context.

///|
pub(all) struct ChatComposerNode {
  root : @view.View
  composer : ComposerNode
  /// what of the room it takes at its page's foot is not its laid size: how tall it is opened with one line where it
  /// stands, and how far its ground is on its way to its shape (its page's layout reads them as its content)
  room_of : () -> (Double, Double)
}

///|
/// The room a composer takes at its page's foot (what the list leaves free under its last row): as tall as it is laid
/// out (`total`, its capsule `cap` of that) with its ground as drawn (a line more or less: the list's rows go with the
/// ground as it reshapes, the frame it does), at least as tall as that opened with one line: `opened` and `shape` its
/// ChatComposerNode's `room_of`. Worked out by its page's layout as it measures it (Layout::reported's "composer" and
/// "cap").
pub fn composer_room_in(total : Double, cap : Double, of : (Double, Double)) -> Double {
  let (opened, shape) = of
  dmax(total + shape, total - cap + opened)
}

///|
/// The active page owns its draft's editor (`draft`'s field is one editor's). A stack can hold the same chat twice:
/// made as its page is active and no other page's composer holds the draft, else as that one lets it go, in the same
/// change, before its page is laid out (nothing made a flush later: its page laid out again for it).
pub fn composer_on_page(
  parent : @view.View,
  src : Source,
  draft : String,
  active : () -> Bool,
  make : (@view.View) -> Unit,
) -> Unit {
  let w = @signals.untracked(fn() { @sfbase.writing(src, draft) })
  let me = parent.id()
  parent.show(fn() { active() && w.held_by.get().map_or(true, fn(h) { h == me }) }, fn(f) {
    // (said held once the layout it is made in is over, as what another page's composer of it reads: that one made or
    // let go then, not in a layout that measured it already)
    f.made_after_layout(fn() { @signals.untracked(fn() { w.held_by.set(Some(me)) }) })
    // (and let go so, as the layout that let it go is over: what holds it next made then)
    f.owns(fn() {
      f.told_after_layout(fn() { if @signals.untracked(fn() { w.held_by.get() }) == Some(me) { w.held_by.set(None) } })
    }) |> ignore
    make(f)
  })
}

///|
pub fn chat_composer_node(
  parent : @view.View,
  src : Source,
  r : ChatRef,
  view : () -> ChatView?,
  side : () -> Double,
  lines_room : (@view.View, (Double, Double) -> Double),
  foot : (Double) -> Double,
  place : () -> ComposerPlace,
  sent : (String) -> Unit,
  tips? : @sf.TipLayer,
  active? : () -> Bool = fn() { true },
  neighbour? : (Int) -> Unit,
  drops? : @view.View,
  place_in? : (Double) -> ComposerPlace,
) -> ChatComposerNode {
  let draft = r.station + ":" + r.session
  let node : Ref[ComposerNode?] = Ref(None)
  let extras : Ref[ComposerExtrasNode?] = Ref(None)
  // (how tall it is opened with one line where it stands, and how far its ground is on its way to its shape)
  let room_of = fn() {
    let n = node.val.unwrap()
    let look = @ui.style_words(@sf.theme().t.words)
    let line = (if look.line > 0.0 { look.line } else { look.size * @ui.tree_theme().text_line }) * @ui.font_scale()
    let opened = @sf.composer_pad + 8.0 + line + 10.0 + @sf.theme().round.side + @sf.capsule_in(place().corner, @sf.theme().round.side)
    (opened, (n.ground)().3)
  }
  let root_at : Ref[@view.View?] = Ref(None)
  // (as tall as it is laid out, said to its page's layout as it is measured there ("composer"): what of what holds it
  // is its own, the rest (the recent chats under a fold) not)
  parent.box(fn(holder) {
  holder.shrink(Is(0.0)) |> ignore
  let root = holder.box(fn(root) {
    // (as wide as its room leaves it `side` in from each side, its widest at most: composer_width_in, said to layout;
    // its foot in by what holds it is laid out as wide as (`parent`'s width, Roomed: in the same layout, nothing of its
    // size read back))
    root.lines_up(Is(Some(Middle))).padding(Roomed(parent, fn(pane, _) { (side(), 12.0, side(), foot(pane)) })) |> ignore
    let notices = composer_notices_node(root, src, r, view)
    let body = root.box(fn(body) {
      body.width_share(Is(1.0)).max_width(By(composer_widest)) |> ignore
      node.val = Some(composer_node(body, src, draft, fn() {
        let v = view()
        { station: r.station, draft, session: r.session, placeholder: @sf.t("web-main.composer.placeholder"), toolbar: None, toolbar_node: None,
          note: v.map(fn(v) { v.cc.filter(fn(o) { o.on }).map(fn(o) { (o.via, o.place) }) }).unwrap_or([]), tail: None,
          roomy: false, locked: false, offline: v.map(fn(v) { v.offline }).unwrap_or(false),
          warm_agent: !v.map(fn(v) { v.archived }).unwrap_or(false) }
      }, fn(w) {
        match view() {
          Some(v) => send_in_chat_with(src, r, v, w, fn(row, words, marks, runs) {
            let n = node.val.unwrap()
            let files = composer_flying_nodes(src, w, r.station, extras.val.unwrap(), place().corner)
            @sfbase.flight_start_from(@ui.current(), w.key, r.station + "\u{1}" + r.session, row, words, files, w.field.lines(),
              hold=(n.hold)(), desk=true, marks~, runs~)
            sent(row)
            @sfbase.chat_latest(@ui.current(), src, r, v, @sf.t("web-main.chat.toLatest"))
          })
          None => ()
        }
      }, lines_room, fn(p, w, inner, moves) {
        extras.val = Some(composer_extras_node(p, src, w, fn() { r.station }, inner, fn() { place().corner - @sf.composer_pad },
          media_content_node, moves~, tips?=tips))
      }, place~, place_in?=place_in.map(fn(of) { (parent, of) }), tail=fn(p) { cc_chooser_node(p, src, r, view) }, tips?=tips, active~, neighbour?=neighbour, drops?=drops))
    })
    // The notices stand on the composer's moving top, while the list follows the same ground's current height.
    notices.drawn_off(By(fn() {
      let delta = (node.val.unwrap().ground)()
      (0.0, delta.1)
    })) |> ignore
    body.shrink(Is(0.0)) |> ignore
  })
  root_at.val = Some(root)
  // (with what of its room is not its laid size ("opened", "shape": room_of), so its page's layout has all of it from
  // this one measuring, the pass it is made in too)
  holder.layout_box(By(fn() { room_of() }), sized=true, fn(l, of) {
    let (_, h) = l.measure(root, l.width)
    l.report("composer", h)
    l.report("opened", of.0)
    l.report("shape", of.1)
    l.size_to(h)
    l.place(root, 0.0, 0.0)
  }) |> ignore
  }) |> ignore
  { root: root_at.val.unwrap(), composer: node.val.unwrap(), room_of }
}
