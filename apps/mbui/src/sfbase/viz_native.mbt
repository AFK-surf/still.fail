// A visualization drawn by the app itself, not a page (mbui/widget: its HTML read, styled and laid out as nodes): what
// an inline visualization becomes where it needs no browser (@html.needs_browser: no script, nothing from the network,
// no element only a browser draws), written in the same design system as the page's (viz.css over HTML's own sheet,
// the app's tokens as --e-*, as viz_document gives a page), its icons the app's own. One that needs a browser is
// still the page (viz_page.mbt).

///|
/// HTML's own sheet and still.fail's visualization stylesheet, read once.
// kept across runs: read from constants, the same in every run
let viz_native_sheet : Ref[@html.Sheet?] = Ref(None)

///|
fn viz_native_defaults() -> @html.Sheet {
  match viz_native_sheet.val {
    Some(s) => s
    None => {
      let s = @html.parse_sheet(@html.ua_css + "\n" + viz_css)
      viz_native_sheet.val = Some(s)
      s
    }
  }
}

///|
/// still.fail's icons by name (viz_icons: what a figure's data-icon marks name), read once.
// kept across runs: read from a constant, the same in every run
let viz_icon_paths : Ref[Map[String, String]?] = Ref(None)

///|
fn viz_icon_path(name : String) -> String? {
  let m = match viz_icon_paths.val {
    Some(m) => m
    None => {
      let m : Map[String, String] = {}
      let j = @json.parse(viz_icons) catch { _ => Json::null() }
      if j is Object(o) {
        o.each(fn(k, v) { if v is String(s) { m[k] = s } })
      }
      viz_icon_paths.val = Some(m)
      m
    }
  }
  m.get(name)
}

///|
/// The visualization `html` (as it changes) drawn by the app in `parent`, as wide as it is given; `on_link` where a
/// link in it leads.
#callsite(autofill(loc))
pub fn viz_native_node(
  parent : @view.View,
  html : () -> String,
  on_link? : (String) -> Unit = fn(_) {  },
  loc~ : SourceLoc,
) -> @view.View {
  @widget.widget_node(
    parent,
    html,
    {
      defaults: viz_native_defaults(),
      tokens: fn() { viz_tokens(@sf.theme().dark) },
      size: fn() { @sf.theme().t.body },
      dark: fn() { @sf.theme().dark },
      element: viz_native_element,
      expand: viz_chart_html,
      on_link,
    },
    loc~,
  )
}

///|
/// What the app draws its own way in a visualization: an icon mark (data-icon, data-lucide), as the page's script
/// draws it (components.js icons: 24 square, its line 1.75, in the words' colour).
fn viz_native_element(v : @view.View, styled : @html.Styled, b : @html.Box) -> Bool {
  let e = styled.tree.els[b.el].elem
  let name = match (e.attr("data-icon"), e.attr("data-lucide")) {
    (Some(n), _) => n
    (None, Some(n)) => n
    _ => return false
  }
  let st = b.style
  let ink = viz_css_color(st.color)
  let path = viz_icon_path(name).unwrap_or("")
  let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" width=\"16\" height=\"16\" fill=\"none\" stroke=\"" +
    ink +
    "\" stroke-width=\"1.75\" stroke-linecap=\"round\" stroke-linejoin=\"round\" color=\"" +
    ink +
    "\">" +
    path.replace_all(old="currentColor", new=ink) +
    "</svg>"
  v.box(fn(i) {
    let side : @html.Style = { ..st, width: @html.Len::px(16.0), height: @html.Len::px(16.0) }
    @widget.svg_node(i, svg, side)
  })
  |> ignore
  true
}
