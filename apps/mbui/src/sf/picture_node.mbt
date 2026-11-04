// The app's drawn pictures (picture.mbt's drawable, maker_mark, slack_mark, feishu_mark) as nodes of the window's tree,
// made once: which picture, and the colour it is drawn in, followed as they change; its curves cut for the pixels it is
// drawn at, as an old view's are.

///|
/// Drawable `name`'s picture (as it changes) `w` wide and as tall as it is for that, in its own colours or all in `tint`
/// (None: its own), drawn as drawable draws it: nothing `w` square where there is none so named.
pub fn drawable_node(parent : @view.View, name : () -> String, w : Double, tint? : () -> Int64? = fn() { None }) -> @view.View {
  parent.box(fn(d) {
    d
    .width(Is(Some(w)))
    .height(By(fn() {
      match drawables.get(name()) {
        Some(v) => Some(w * v.h / v.w)
        None => Some(w)
      }
    }))
    .picture(By(fn() { if tint() is None { drawables.get(name()) } else { None } }))
    .shapes(By(fn() {
      match (drawables.get(name()), tint()) {
        (Some(v), Some(ink)) => @ui.vector_shapes(v, w, @ui.current().drawn_scale(), tint=ink)
        _ => []
      }
    }))
    .drawn_as(By(fn() {
      let tk = match tint() {
        Some(t) => t.to_string()
        None => "-"
      }
      "sf/pic/\{name()}/\{w}/\{@ui.current().drawn_scale()}/\{tk}"
    }))
    |> ignore
  })
}

///|
/// The mark of the company that made a model (maker_mark's, as a node): the core's `maker` id when there is a mark for
/// it, else its runtime's maker's; those drawn in one colour in the page's ink. Each as it changes.
pub fn maker_mark_node(parent : @view.View, maker : () -> String, runtime : () -> String, size : Double) -> @view.View {
  let id = fn() { maker_of(maker(), runtime()) }
  drawable_node(parent, fn() { "maker_" + id().replace_all(old="-", new="_") }, size, tint=fn() {
    if mono_makers.contains(id()) {
      Some(theme().p.text)
    } else {
      None
    }
  })
}

///|
/// A workspace's mark or its initial, as workspace_badge draws it beside its name.
pub fn workspace_badge_node(parent : @view.View, name : () -> String, emoji : () -> String, icon : () -> String, size : Double) -> Unit {
  parent.pick(fn() { has_station_mark(emoji(), icon()) }, fn(p, marked) {
    if marked {
      station_mark_node(p, emoji, icon, size, fn() { theme().p.text }, fn() { 0 })
    } else {
      p.box(fn(b) {
        b.width(Is(Some(size))).height(Is(Some(size))).lines_up(Is(Some(Middle))).lies_along(Is(Middle))
        .words(By(fn() { initial(name()) })).words_look(By(fn() { @ui.style_words(workspace_badge_letter) }))
        .ink(By(fn() { theme().p.muted })) |> ignore
      }) |> ignore
    }
  })
}

///|
/// Slack's mark (slack_mark's) or Feishu's (`feishu`), as a node.
pub fn place_mark_node(parent : @view.View, feishu : () -> Bool, size : Double) -> @view.View {
  drawable_node(parent, fn() { if feishu() { "feishu" } else { "slack" } }, size)
}
