// Marks drawn as nodes of the window's tree (icons.mbt's spokes and icon_parts, picture.mbt's drawable, maker_mark,
// slack_mark; waiting.mbt's updating_mark): the same drawings, made once, moved by the clock where they move.

///|
/// The spokes (spokes'), `size` across in a box `box` across (`size` where none), in `color` as it changes, turning
/// round once every eight steps (spoke_turn's) for as long as they show. The node.
pub fn spokes_node(parent : @view.View, size : Double, color : () -> Int64, box? : Double) -> @view.View {
  let box = box.unwrap_or(size)
  let u = size / 24.0
  let mid = box / 2.0
  let pi = 3.141592653589793
  let made : Ref[@view.View?] = Ref(None)
  parent.box(fn(v) {
    made.val = Some(v)
    v
    .width(Is(Some(box)))
    .height(Is(Some(box)))
    .lines(By(fn() {
      let ink = color()
      let lines = []
      for i in 0..<8 {
        let a = i.to_double() * pi / 4.0
        let dx = @dmath.sin(a) * u
        let dy = -@dmath.cos(a) * u
        lines.push(
          @ui.line(
            [(mid + dx * 4.8, mid + dy * 4.8), (mid + dx * 9.6, mid + dy * 9.6)],
            width=2.9 * u,
            color=alpha(ink, spoke_alpha[(8 - i) % 8]),
          ),
        )
      }
      lines
    }))
    .turn(
      By(fn() {
        // (held at its first step while motion is reduced, as spoke_turn's: nothing woken for it)
        if @ui.reduced_motion() {
          0.0
        } else {
          v.cycle_resident(8.0 * spoke_step_ms) * 2.0 * pi
        }
      }),
      drawn=true,
    )
    |> ignore
  })
  |> ignore
  made.val.unwrap()
}

///|
/// Of icon `name`, only its parts `parts` (icon_parts'), `size` across, in `tint` as it changes. The node.
pub fn icon_parts_node(
  parent : @view.View,
  name : String,
  parts : Array[Int],
  size : Double,
  tint : @view.Live[Int64],
) -> @view.View {
  let made : Ref[@view.View?] = Ref(None)
  parent.box(fn(v) {
    made.val = Some(v)
    v
    .width(Is(Some(size)))
    .height(Is(Some(size)))
    .shapes(Is(
      match icon_numbers(name) {
        Some(d) => icon_shapes(icon_data_parts(d, parts), size / 24.0, 0x000000FFL)
        None => []
      },
    ))
    .tint(tint)
    |> ignore
  })
  |> ignore
  made.val.unwrap()
}

///|
/// Picture `name` of the app's (drawable's) `w` wide, as tall as it is for that, in its own colours or all in `tint` as
/// it says now (None: its own). The node.
pub fn drawable_node(parent : @view.View, name : String, w : Double, tint? : () -> Int64?) -> @view.View {
  let made : Ref[@view.View?] = Ref(None)
  parent.box(fn(v) {
    made.val = Some(v)
    match drawables.get(name) {
      Some(d) => {
        let tinted = match tint {
          Some(f) => @signals.untracked(f) is Some(_)
          None => false
        }
        v.width(Is(Some(w))).height(Is(Some(w * d.h / d.w))) |> ignore
        if tinted {
          // (in one ink, the page's: its shapes in that ink as it is now)
          v
          .shapes(Is(@ui.vector_shapes(d, w, @ui.current().drawn_scale(), tint=0x000000FFL)))
          .tint(By(fn() {
            match tint {
              Some(f) => f().unwrap_or(0L)
              None => 0L
            }
          }))
          |> ignore
        } else {
          // (in its own colours: a picture, its colours its owner's, as an old view's own_colours are)
          v.picture(Is(Some(d))) |> ignore
        }
      }
      None => v.width(Is(Some(w))).height(Is(Some(w))) |> ignore
    }
  })
  |> ignore
  made.val.unwrap()
}

///|
/// The mark of the company that made a model (maker_mark's) as a node, `size` across: the core's `maker` where there
/// is a mark for it, else its runtime's maker's; the one-colour ones in the page's ink as it is now. The node.
pub fn maker_mark_node(parent : @view.View, maker : String, runtime : String, size : Double) -> @view.View {
  let id = maker_of(maker, runtime)
  let mono = mono_makers.contains(id)
  drawable_node(parent, "maker_" + id.replace_all(old="-", new="_"), size, tint=fn() {
    if mono {
      Some(theme().p.text)
    } else {
      None
    }
  })
}

///|
/// Which maker's mark `maker` (the core's) and `runtime` (its maker's where there is none for it) come to (maker_mark's).
fn maker_of(maker : String, runtime : String) -> String {
  if maker != "" && drawables.contains("maker_" + maker.replace_all(old="-", new="_")) {
    maker
  } else {
    match runtime {
      "codex" => "openai"
      "dsh" => "dsh"
      "grok" => "xai"
      "cursor" => "cursor"
      "devin" => "devin"
      "hermes" => "hermes"
      "agy" => "gemini"
      _ => "anthropic"
    }
  }
}

///|
/// The mark of the platform a chat came from (slack_mark's, feishu_mark's), `kind` as it changes (the core's
/// originKind), as a node, `size` across: Feishu's for Feishu, else Slack's. The node.
pub fn origin_mark_node(parent : @view.View, kind : () -> String, size : Double) -> @view.View {
  let name = fn() { if kind() == "feishu" { "feishu" } else { "slack" } }
  parent.box(fn(d) {
    d
    .width(Is(Some(size)))
    .height(By(fn() {
      match drawables.get(name()) {
        Some(v) => Some(size * v.h / v.w)
        None => Some(size)
      }
    }))
    .picture(By(fn() { drawables.get(name()) }))
    |> ignore
  })
}

///|
/// A station gone for its update (updating_mark's) as a node, `size` across, in `color` as it changes: in a ring an arrow
/// up, standing a while, then off up through its top as the next comes up from its bottom, once every
/// updating_rise_ms, seen in a round window inside the ring.
pub fn updating_mark_node(parent : @view.View, size : Double, color : () -> Int64) -> Unit {
  let pi = 3.141592653589793
  let k = size / 24.0
  let stroke = 1.75 * k
  let mid = size / 2.0
  let window = 13.0 * k
  let wmid = window / 2.0
  let length = 8.0 * k
  let pitch = window + length
  let arrow = fn(top : Double, ink : Int64) -> Array[@ui.Line] {
    [
      @ui.line([(wmid, top), (wmid, top + length)], width=stroke, color=ink),
      @ui.line([(wmid - 3.0 * k, top + 3.0 * k), (wmid, top), (wmid + 3.0 * k, top + 3.0 * k)], width=stroke, color=ink),
    ]
  }
  let top = wmid - length / 2.0
  parent.box(fn(b) {
    b
    .width(Is(Some(size)))
    .height(Is(Some(size)))
    .lines(By(fn() { [@ui.line(@ui.arc(mid, mid, 8.5 * k, from=0.0, sweep=2.0 * pi), width=stroke, color=color())] }))
    |> ignore
    b.box(fn(w) {
      w
      .over(Is(true))
      .width(Is(Some(window)))
      .height(Is(Some(window)))
      .offset(Is((mid - wmid, mid - wmid)))
      .radius(Is(window / 2.0))
      .clips(Is(true))
      |> ignore
      w.box(fn(a) {
        a
        .width(Is(Some(window)))
        .height(Is(Some(window + pitch)))
        .lines(By(fn() {
          let ink = color()
          let lines = arrow(top, ink)
          lines.push_iter(arrow(top + pitch, ink).iter())
          lines
        }))
        .offset(By(fn() {
          let f = a.cycle(updating_rise_ms)
          let g = if f <= updating_stand { 0.0 } else { (f - updating_stand) / (1.0 - updating_stand) }
          let h = 2.0 - 2.0 * g
          let eased = if g < 0.5 { 4.0 * g * g * g } else { 1.0 - h * h * h / 2.0 }
          (0.0, -eased * pitch)
        }))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// Of icon `name`, its parts drawn each in its own ink as `inks` says them now (which parts, in what ink: what of it
/// breathes or lights drawn with what stays, one icon to what reads it), `size` across, in one node. The node.
pub fn icon_inks_node(
  parent : @view.View,
  name : String,
  size : Double,
  inks : (@view.View) -> Array[(Array[Int], Int64)],
) -> @view.View {
  let made : Ref[@view.View?] = Ref(None)
  parent.box(fn(v) {
    made.val = Some(v)
    v
    .width(Is(Some(size)))
    .height(Is(Some(size)))
    .shapes(By(fn() {
      match icon_numbers(name) {
        Some(d) => {
          let out : Array[@ui.Shape] = []
          for p in inks(v) {
            out.push_iter(icon_shapes(icon_data_parts(d, p.0), size / 24.0, p.1).iter())
          }
          out
        }
        None => []
      }
    }))
    |> ignore
  })
  |> ignore
  made.val.unwrap()
}
