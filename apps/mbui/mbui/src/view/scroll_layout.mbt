// A scroll viewport owns the content and the thumb. Their sizes are one
// measurement result: no size observation writes another layout property.

///|
fn View::scroll_layout(
  self : View, held : View, thumb : View?, across : Bool, bar : ScrollBar?, bar_in : Double,
  bar_clear : () -> (Double, Double),
) -> Unit {
  self.layout(By(bar_clear), fn(clear, space) {
    let content = if across {
      space.measure(held, height?=space.height(), max_width=None)
    } else {
      space.measure(held, width?=space.width(), max_height=None)
    }
    let (cw, ch) = content.size()
    let w = space.width().unwrap_or(cw)
    let extra = match bar {
      Some(b) if across && cw - w > 0.5 => {
        let st = self.tree.nodes[held.at].flex.style
        let pad = if st.padding_bottom_kind() == @flex.LEN_PT { st.padding_bottom_value() } else { 0.0 }
        dmax(0.0, b.size + b.inset * 2.0 - pad)
      }
      _ => 0.0
    }
    let h = space.height().unwrap_or(ch + extra)
    let content = if across && extra > 0.0 && space.height() is Some(_) {
      space.measure(held, height=dmax(0.0, h - extra), max_width=None)
    } else { content }
    let children = [content.at(0.0, 0.0)]
    match (thumb, bar) {
      (Some(thumb), Some(b)) => {
        let (left, top, right, bottom) = space.insets()
        let length = if across { w + left + right } else { h + top + bottom }
        // A windowed list includes its unmade rows as measured gaps. The
        // holder's measurement therefore already includes the whole extent;
        // its previous position table is not an input to this layout.
        let total = if across { content.size().0 } else { content.size().1 }
        let ends = if across { dclamp(bar_in, 0.0, dmax(0.0, length / 2.0 - b.least)) } else { 0.0 }
        let (start, end) = if across { (0.0, 0.0) } else { clear }
        let long = bar_track_of(ends, length - 2.0 * ends, length - 2.0 * ends,
          dmax(total, length) - 2.0 * ends, 0.0, start, end, b.least, b.inset).1 + b.grab * 2.0
        let thick = b.size + b.grab * 2.0
        let measured = if across {
          space.measure(thumb, width=long, height=thick)
        } else {
          space.measure(thumb, width=thick, height=long)
        }
        children.push(measured.at(-left, -top))
      }
      _ => ()
    }
    arrangement(w, h, children)
  }) |> ignore
}
