// The whole input area of a chat: notices, one retained draft, attachments and copy choices. Frame geometry is
// supplied by the page as it changes; no getter reads a temporary old page's pane or composer context.

///|
pub(all) struct ChatComposerNode {
  root : @view.View
  composer : ComposerNode
  room : () -> Double
  room_parts : () -> (Double, Double)
  layout_room : () -> (Double, Double, ComposerPlace, ComposerLimits?, Double)
}

///|
priv struct ComposerWidth {
  context : @view.WidthContext
  limits : () -> ComposerLimits
}

///|
let composer_width_context : @view.Lent[ComposerWidth] = @view.Lent::new()

///|
let composer_height_context : @view.Lent[@view.HeightContext] = @view.Lent::new()

///|
// A composer's pane geometry is resolved before its descendants are measured. Other inputs are captured outside
// layout, so resizing the pane cannot publish a size and then cause a second layout of the composer.
fn[K : Eq] composer_place_layout(v : @view.View, read : () -> K, apply : (ComposerPlace, K) -> Unit) -> Bool {
  match v.lent(composer_width_context) {
    Some(c) => {
      c.context.bind(v, By(fn() { ((c.limits)(), read()) }), fn(width, state) {
        apply(state.0.in_width(width).2, state.1)
      })
      true
    }
    None => false
  }
}

///|
/// The active page owns its draft's editor. A stack can hold the same chat twice: take the editor after the
/// navigation change has released its previous owner, within that same change and before any frame is drawn.
pub fn composer_on_page(parent : @view.View, active : () -> Bool, make : (@view.View) -> Unit) -> Unit {
  let ready = @signals.signal(false, same=fn(a, b) { a == b })
  let live = Ref(true)
  parent.owns(fn() { live.val = false }) |> ignore
  parent.show(fn() { ready.get() && active() }, make)
  parent.reacts(active, fn(on) {
    if on {
      @signals.after_flush(fn() {
        if live.val && @signals.untracked(active) { ready.set(true) }
      })
    } else {
      ready.set(false)
    }
  })
}

///|
pub fn chat_composer_node(
  parent : @view.View,
  src : Source,
  r : ChatRef,
  view : () -> ChatView?,
  width : () -> Double,
  height : () -> Double,
  foot : () -> Double,
  place : () -> ComposerPlace,
  sent : (String) -> Unit,
  pane_width? : (@view.WidthContext, () -> ComposerLimits),
  pane_height? : @view.HeightContext,
  tips? : @sf.TipLayer,
  active? : () -> Bool = fn() { true },
  neighbour? : (Int) -> Unit,
  drops? : @view.View,
) -> ChatComposerNode {
  let draft = r.station + ":" + r.session
  let node : Ref[ComposerNode?] = Ref(None)
  let extras : Ref[ComposerExtrasNode?] = Ref(None)
  let root_at : Ref[@view.View?] = Ref(None)
  // Inputs to the parent's layout: the open editor's minimum room and the current shape's height delta.
  // Neither reads a measured size. The parent combines them with this pass's measurements directly.
  let layout_room = fn() {
    let look = @ui.style_words(@sf.theme().t.words)
    let line = (if look.line > 0.0 { look.line } else { look.size * @ui.tree_theme().text_line }) * @ui.font_scale()
    let side = @sf.theme().round.side
    let base = @sf.composer_pad + 8.0 + line + 10.0 + side
    let (fixed, limits) = match pane_width {
      Some((_, limits)) => (composer_alone, Some(limits()))
      None => (place(), None)
    }
    (base, side, fixed, limits, (node.val.unwrap().ground)().3)
  }
  let room_parts = fn() {
    let (base, side, fixed, limits, moving) = layout_room()
    let p = match (pane_width, limits) {
      (Some((context, _)), Some(limits)) => limits.in_width(context.now().unwrap_or(parent.window().0)).2
      _ => fixed
    }
    (base + @sf.capsule_in(p.corner, side), moving)
  }
  let room = fn(settled : Bool) {
    let n = node.val.unwrap()
    let root = root_at.val.unwrap()
    let total = root.laid_size_told().map(fn(s) { s.1 }).unwrap_or(0.0)
    let cap = n.cap.laid_size_told().map(fn(s) { s.1 }).unwrap_or(0.0)
    let (opened, moving) = room_parts()
    let shape = if settled { 0.0 } else { moving }
    dmax(total + shape, total - cap + opened)
  }
  let root = parent.box(fn(root) {
    root_at.val = Some(root)
    match pane_height { Some(context) => root.lends(composer_height_context, context) |> ignore; None => () }
    root.lines_up(Is(Some(Middle))) |> ignore
    match pane_width {
      Some((context, limits)) => {
        root.lends(composer_width_context, { context, limits }) |> ignore
        context.bind(root, By(limits), fn(w, c) {
          root.padding(Is((0.0, 12.0, 0.0, c.in_width(w).1))) |> ignore
        })
      }
      None => root.padding(By(fn() { (0.0, 12.0, 0.0, foot()) })) |> ignore
    }
    let notices = composer_notices_node(root, src, r, view, width)
    let body = root.box(fn(body) {
      match pane_width {
        Some((context, limits)) => context.bind(body, By(limits), fn(w, c) {
          body.width(Is(Some(c.in_width(w).0))) |> ignore
        })
        None => body.width(By(fn() { Some(width()) })) |> ignore
      }
      node.val = Some(composer_node(body, src, draft, fn() {
        let v = view()
        { station: r.station, draft, session: r.session, placeholder: @sf.t("web-main.composer.placeholder"), toolbar: None,
          note: v.map(fn(v) { v.cc.filter(fn(o) { o.on }).map(fn(o) { (o.via, o.place) }) }).unwrap_or([]), tail: None,
          roomy: false, locked: false, offline: v.map(fn(v) { v.offline }).unwrap_or(false),
          warm_agent: !v.map(fn(v) { v.archived }).unwrap_or(false) }
      }, fn(w) {
        match view() {
          Some(v) => send_in_chat_with(src, r, v, w, fn(row, words, marks, runs) {
            let n = node.val.unwrap()
            let files = composer_flying_nodes(src, w, r.station, extras.val.unwrap(), place().corner)
            @sfbase.flight_start_from(@ui.current(), w.key, r.station + "\u{1}" + r.session, row, words, room(false), files, w.field.lines(),
              hold=(n.hold)(), desk=true, marks~, runs~)
            sent(row)
            @sfbase.chat_latest(@ui.current(), src, r, v, @sf.t("web-main.chat.toLatest"))
          })
          None => ()
        }
      }, height, fn(p, w, inner, moves) {
        extras.val = Some(composer_extras_node(p, src, w, fn() { r.station }, inner, fn() { place().corner - @sf.composer_pad },
          media_content_node, moves~, tips?=tips))
      }, place~, tail=fn(p) { cc_chooser_node(p, src, r, view) }, tips?=tips, active~, neighbour?=neighbour, drops?=drops))
    })
    // The notices stand on the composer's moving top, while the list follows the same ground's current height.
    notices.drawn_off(By(fn() {
      let delta = (node.val.unwrap().ground)()
      (0.0, delta.1)
    })) |> ignore
    body.shrink(Is(0.0)) |> ignore
  })
  composing.node_rooms[draft] = room
  root.owns(fn() {
    match composing.node_rooms.get(draft) {
      Some(f) if physical_equal(f, room) => composing.node_rooms.remove(draft)
      _ => ()
    }
  }) |> ignore
  { root, composer: node.val.unwrap(), room: fn() { room(false) }, room_parts, layout_room }
}
