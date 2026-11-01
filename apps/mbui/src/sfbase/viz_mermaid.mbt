// A ```mermaid block's chart drawn by the app itself: the core makes it (`mermaid.chart`: mermaid.js lays it out
// there, client/core-ts/src/mermaid.ts, its words measured in the faces the app sets them in) and gives an SVG in the
// theme's colours, drawn here as a picture (mbui's SVG renderer, as an .svg file is): as wide as it is written, or the
// column's where that is less, in its proportions; over the whole screen, the viewer's picture (pinched, moved, kept).
// One the core refuses (mermaid does not read it, or part of it would be HTML) shows as its code. mermaid itself is not
// in the core's own script: the app gives it the one it carries (mermaid_hbc.mbt) the first time a chart is drawn.

///|
priv enum MermaidChart {
  ChartComing
  /// its SVG, the picture's key, its width and height as the chart says them
  ChartMade(Bytes, String, Double, Double)
  ChartRefused
}

///|
// kept across runs: the core's answers, by what was asked (mermaid_ask)
let mermaid_charts : Map[String, MermaidChart] = {}

///|
// kept across runs: how many answers came (a signal: a frame drawing a chart reads it, and comes again as one does)
let mermaid_made : @signals.Signal[Int] = @signals.signal(0)

///|
// kept across runs: whether the core was given mermaid (`mermaid.load`), as the core keeps it while it runs; false
// again where it says it has none (a core started anew)
let mermaid_given : Ref[Bool] = Ref(false)

///|
/// How wide a chart that fills its width (a gantt) is made: drawn as the others are, the column's where that is less.
let mermaid_filling : Int = 720

///|
/// `rgba` laid over `ground` (both 0xRRGGBBAA, the ground opaque), as `#rrggbb`: a colour of the theme as the chart
/// gets it (the core takes nothing else into its styles).
fn mermaid_hex(rgba : Int64, ground : Int64) -> String {
  let a = (rgba & 0xFFL).to_int()
  let mix = fn(shift : Int) {
    let c = ((rgba >> shift) & 0xFFL).to_int()
    let g = ((ground >> shift) & 0xFFL).to_int()
    (c * a + g * (255 - a) + 127) / 255
  }
  let hex = "0123456789abcdef"
  let out = StringBuilder::new()
  out.write_char('#')
  for shift in [24, 16, 8] {
    let v = mix(shift)
    out.write_char(hex[v / 16].unsafe_to_char())
    out.write_char(hex[v % 16].unsafe_to_char())
  }
  out.to_string()
}

///|
/// What the core is asked for chart `code` `width` wide: its colours as the theme shown has them (the web's chart
/// page's: the page, a card, the strong line, the ink, the muted ink for lines, the quiet grounds, the brand).
fn mermaid_ask(code : String, width : Int) -> Json {
  let t = @sf.theme()
  let p = t.p
  let ground = p.canvas
  let colours : Map[String, Json] = {
    "background": mermaid_hex(ground, ground).to_json(),
    "card": mermaid_hex(p.card, ground).to_json(),
    "border": mermaid_hex(p.line_strong, ground).to_json(),
    "text": mermaid_hex(p.text, ground).to_json(),
    "line": mermaid_hex(p.muted, ground).to_json(),
    "accent": mermaid_hex(p.neutral_bg, ground).to_json(),
    "muted": mermaid_hex(p.hover, ground).to_json(),
    "brand": mermaid_hex(p.accent, ground).to_json(),
  }
  { "code": code.to_json(), "dark": t.dark.to_json(), "colours": Json::object(colours), "width": width.to_json() }
}

///|
/// A ```mermaid block: its chart drawn as a picture (`place`: the message it is in, on `station`), with a way under it
/// to open it over the whole screen (in `subtle`, the frame's grey); while the core makes it, its place as a page's
/// while it waits; refused, its code.
pub fn viz_mermaid_block(c : @ui.Ctx, src : Source, station : String, place : String, code : String, subtle : Int64) -> Unit {
  ignore(mermaid_made.get())
  let ask = mermaid_ask(code, mermaid_filling)
  let key = ask.stringify()
  match mermaid_charts.get(key) {
    Some(ChartRefused) => @sf.code_block(c, code, "mermaid")
    Some(ChartMade(svg, picture, w, h)) =>
      c.box(style=viz_mermaid_box, fn() {
        c.box(style=@ui.style(w=Full, max_w=Fixed(w)), aspect=w / h, fn() {
          c.image(picture, w=Fill(1.0), h=Fill(1.0), fit=FitContain, bg=0L, fade=false) |> ignore
        })
        |> ignore
        mermaid_ways(c, station, place, svg, w, h, subtle)
      })
      |> ignore
    _ => {
      if mermaid_charts.get(key) is None {
        mermaid_charts[key] = ChartComing
        // (asked once the frame's builds are over: a build tells nothing outside)
        c.after_build("mermaid/" + key, fn() { mermaid_asked(src, key, ask) })
      }
      // its place while it is made, as a page's while it draws itself
      c.box(style=viz_mermaid_box, fn() {
        c.box(style=viz_wait_ground.then(@ui.style(h=Fixed(viz_first_height.to_double()))), fn() {
          let i = c.box(style=viz_wait_fill, fn() {  })
          @sf.breathe(c, i)
        })
        |> ignore
      })
      |> ignore
    }
  }
}

///|
/// Chart `ask` asked of the core (given mermaid first where it has none yet), its answer kept by `key`.
fn mermaid_asked(src : Source, key : String, ask : Json) -> Unit {
  if !mermaid_given.val {
    match viz_mermaid_script() {
      Some(script) => {
        mermaid_given.val = true
        (src.call_bytes)("mermaid.load", Json::object({}), script, fn(r) { if r is Err(_) { mermaid_given.val = false } })
      }
      None => ()
    }
  }
  (src.call)("mermaid.chart", ask, fn(r) {
    match r {
      Ok({ "svg": String(svg), "width": Number(w, ..), "height": Number(h, ..), .. }) if w > 0.0 && h > 0.0 => {
        let picture = "mem:mermaid/" + key
        let bytes = @utf8.encode(svg)
        @ui.add_image(picture, bytes)
        mermaid_charts[key] = ChartMade(bytes, picture, w, h)
      }
      // a core that has not mermaid (started anew since it was given it): given it again, asked again
      Err({ "code": String("mermaid_absent"), .. }) if mermaid_given.val => {
        mermaid_given.val = false
        mermaid_charts.remove(key)
      }
      _ => mermaid_charts[key] = ChartRefused
    }
    mermaid_made.set(mermaid_made.get() + 1)
  })
}

///|
/// Under a chart, out of its way, as a placed file has it: the whole screen, the viewer's (as a picture waiting in the
/// composer opens: from its bytes, a path of its own, no session's), its SVG `svg` `w` × `h`.
fn mermaid_ways(c : @ui.Ctx, station : String, place : String, svg : Bytes, w : Double, h : Double, subtle : Int64) -> Unit {
  c.box(style=viz_ways, fn() {
    let full = c.id("viz/full/" + place + "/mermaid/" + svg.length().to_string())
    if c.clicked(full) {
      c.tell("viz/open-mermaid", fn() {
        let a : Attachment = {
          name: "Mermaid.svg",
          path: "draft:mermaid/" + @zip.sha256(svg).view(end_offset=16).to_owned(),
          size: svg.length().to_double(),
          width: w,
          height: h,
          thumbhash: "",
          owner: "",
          upload: "",
          duration: 0.0,
          frames: 0,
          held: false,
        }
        // (the viewer's id of it, Viewer::id: its station, no session, its path)
        keep_read(station + "//" + a.path, svg)
        open_preview(station, "", a)
      })
    }
    viz_icon(c, full, "expand", viz_tr("android-misc.viz.fullscreen"), subtle)
  })
  |> ignore
}
