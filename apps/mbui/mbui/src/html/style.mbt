// Each property's computed value, as the widget's profile has them (what is drawn of a widget: style.mbt is its list
// of properties; one not here is let go, as a browser lets go one it does not know). Keywords are kept as their
// words, checked against what each takes; lengths as Len (em worked out against the element's size of words, % kept
// as a share); colours as 0xRRGGBBAA.

///|
pub(all) struct Style {
  mut display : String
  mut position : String
  mut top : Len
  mut right : Len
  mut bottom : Len
  mut left : Len
  mut width : Len
  mut height : Len
  mut min_width : Len
  mut min_height : Len
  /// Auto: none
  mut max_width : Len
  mut max_height : Len
  mut aspect : Double
  mut box_sizing : String
  /// top, right, bottom, left
  margin : Array[Len]
  padding : Array[Len]
  border_width : Array[Double]
  border_color : Array[Int64]
  /// top left, top right, bottom right, bottom left
  radius : Array[Len]
  mut flex_direction : String
  mut flex_wrap : String
  mut justify : String
  mut align_items : String
  mut align_self : String
  mut align_content : String
  mut justify_items : String
  mut grow : Double
  mut shrink : Double
  mut basis : Len
  mut row_gap : Len
  mut column_gap : Len
  mut order : Int
  mut grid_columns : String
  mut grid_rows : String
  mut grid_column : String
  mut grid_row : String
  mut color : Int64
  mut background : Int64
  mut background_image : String
  mut font_size : Double
  mut font_weight : Int
  mut italic : Bool
  mut mono : Bool
  mut serif : Bool
  /// in points; 0: normal
  mut line_height : Double
  mut text_align : String
  mut underline : Bool
  mut strike : Bool
  mut white_space : String
  mut letter_spacing : Double
  mut text_transform : String
  mut ellipsis : Bool
  mut tabular : Bool
  mut opacity : Double
  mut overflow : String
  mut visible : Bool
  /// x, y, blur, spread, colour, inset; a blur of -1: none
  mut shadow : (Double, Double, Double, Double, Int64, Bool)
  mut list_style : String
  mut content : String?
  mut vertical_align : String
  mut cursor : String
  mut touch_action : String
  mut user_select : String
  mut transition : String
  mut z_index : Int
}

///|
/// The root's: what nothing sets is as the widget's defaults are, its words the root's size, its colour black (the
/// defaults sheet sets the theme's).
pub fn Style::root(env : Env) -> Style {
  {
    display: "inline",
    position: "static",
    top: Auto,
    right: Auto,
    bottom: Auto,
    left: Auto,
    width: Auto,
    height: Auto,
    min_width: Auto,
    min_height: Auto,
    max_width: Auto,
    max_height: Auto,
    aspect: 0.0,
    box_sizing: "content-box",
    margin: [Len::px(0.0), Len::px(0.0), Len::px(0.0), Len::px(0.0)],
    padding: [Len::px(0.0), Len::px(0.0), Len::px(0.0), Len::px(0.0)],
    border_width: [0.0, 0.0, 0.0, 0.0],
    border_color: [0x000000FFL, 0x000000FFL, 0x000000FFL, 0x000000FFL],
    radius: [Len::px(0.0), Len::px(0.0), Len::px(0.0), Len::px(0.0)],
    flex_direction: "row",
    flex_wrap: "nowrap",
    justify: "normal",
    align_items: "normal",
    align_self: "auto",
    align_content: "normal",
    justify_items: "normal",
    grow: 0.0,
    shrink: 1.0,
    basis: Auto,
    row_gap: Auto,
    column_gap: Auto,
    order: 0,
    grid_columns: "",
    grid_rows: "",
    grid_column: "",
    grid_row: "",
    color: 0x000000FFL,
    background: 0L,
    background_image: "",
    font_size: env.root_size,
    font_weight: 400,
    italic: false,
    mono: false,
    serif: false,
    line_height: 0.0,
    text_align: "start",
    underline: false,
    strike: false,
    white_space: "normal",
    letter_spacing: 0.0,
    text_transform: "none",
    ellipsis: false,
    tabular: false,
    opacity: 1.0,
    overflow: "visible",
    visible: true,
    shadow: (0.0, 0.0, -1.0, 0.0, 0L, false),
    list_style: "disc",
    content: None,
    vertical_align: "baseline",
    cursor: "auto",
    touch_action: "auto",
    user_select: "auto",
    transition: "",
    z_index: 0,
  }
}

///|
/// What an element starts from before its own declarations: its parent's inherited properties, the rest initial.
fn Style::inherit_from(p : Style, env : Env) -> Style {
  let s = Style::root(env)
  s.color = p.color
  s.font_size = p.font_size
  s.font_weight = p.font_weight
  s.italic = p.italic
  s.mono = p.mono
  s.serif = p.serif
  s.line_height = p.line_height
  s.text_align = p.text_align
  s.white_space = p.white_space
  s.letter_spacing = p.letter_spacing
  s.text_transform = p.text_transform
  s.tabular = p.tabular
  s.visible = p.visible
  s.list_style = p.list_style
  s.cursor = p.cursor
  s.user_select = p.user_select
  // text-decoration is not inherited, but it is drawn through what the element holds
  s.underline = p.underline
  s.strike = p.strike
  s.border_color[0] = p.color
  s.border_color[1] = p.color
  s.border_color[2] = p.color
  s.border_color[3] = p.color
  s
}

///|
let inherited : Array[String] = [
  "color", "font-size", "font-weight", "font-style", "font-family", "line-height", "text-align", "white-space",
  "letter-spacing", "text-transform", "visibility", "list-style-type", "cursor", "font-variant-numeric", "user-select",
]

///|
fn sides_of(v : String) -> Array[String]? {
  let w = split_words(v)
  match w.length() {
    1 => Some([w[0], w[0], w[0], w[0]])
    2 => Some([w[0], w[1], w[0], w[1]])
    3 => Some([w[0], w[1], w[2], w[1]])
    4 => Some(w)
    _ => None
  }
}

///|
let side_names : Array[String] = ["top", "right", "bottom", "left"]

///|
fn is_color_word(w : String) -> Bool {
  parse_color(w, 0L, false) is Some(_) || to_lower(w) == "currentcolor"
}

///|
fn is_border_style(w : String) -> Bool {
  [
    "none", "hidden", "solid", "dashed", "dotted", "double", "groove", "ridge", "inset", "outset",
  ].contains(to_lower(w))
}

///|
/// A shorthand set into its longhands (`set` each, in the order it says them); a longhand as it is.
fn expand(name : String, value : String, set : (String, String) -> Unit) -> Unit {
  let v = value
  let wide = ["inherit", "initial", "unset", "revert", "revert-layer"].contains(to_lower(v.trim().to_string()))
  let each_side = fn(prefix : String, suffix : String) {
    match sides_of(v) {
      Some(s) => for k in 0..<4 { set(prefix + side_names[k] + suffix, s[k]) }
      None => ()
    }
  }
  match name {
    "margin" => each_side("margin-", "")
    "padding" => each_side("padding-", "")
    "inset" => each_side("", "")
    "margin-inline" | "padding-inline" => {
      let w = split_words(v)
      let p = if name.has_prefix("margin") { "margin-" } else { "padding-" }
      if w.length() >= 1 {
        set(p + "left", w[0])
        set(p + "right", if w.length() > 1 { w[1] } else { w[0] })
      }
    }
    "margin-block" | "padding-block" => {
      let w = split_words(v)
      let p = if name.has_prefix("margin") { "margin-" } else { "padding-" }
      if w.length() >= 1 {
        set(p + "top", w[0])
        set(p + "bottom", if w.length() > 1 { w[1] } else { w[0] })
      }
    }
    "margin-inline-start" => set("margin-left", v)
    "margin-inline-end" => set("margin-right", v)
    "padding-inline-start" => set("padding-left", v)
    "padding-inline-end" => set("padding-right", v)
    "margin-block-start" => set("margin-top", v)
    "margin-block-end" => set("margin-bottom", v)
    "padding-block-start" => set("padding-top", v)
    "padding-block-end" => set("padding-bottom", v)
    "inline-size" => set("width", v)
    "block-size" => set("height", v)
    "min-inline-size" => set("min-width", v)
    "max-inline-size" => set("max-width", v)
    "min-block-size" => set("min-height", v)
    "max-block-size" => set("max-height", v)
    "border-width" => each_side("border-", "-width")
    "border-color" => each_side("border-", "-color")
    "border-style" => each_side("border-", "-style")
    "border" | "border-top" | "border-right" | "border-bottom" | "border-left" | "border-inline" | "border-block" => {
      let sides = match name {
        "border" => side_names
        "border-inline" => ["left", "right"]
        "border-block" => ["top", "bottom"]
        _ => [name.view(start_offset=7).to_owned()]
      }
      if wide {
        for s in sides {
          set("border-" + s + "-width", v)
          set("border-" + s + "-style", v)
          set("border-" + s + "-color", v)
        }
        return
      }
      let mut width = "medium"
      let mut style = "none"
      let mut color = "currentcolor"
      for w in split_words(v) {
        if is_border_style(w) {
          style = w
        } else if is_color_word(w) {
          color = w
        } else {
          width = w
        }
      }
      for s in sides {
        set("border-" + s + "-width", width)
        set("border-" + s + "-style", style)
        set("border-" + s + "-color", color)
      }
    }
    "border-radius" => {
      let main = match v.find("/") {
        Some(at) => v.view(end_offset=at).trim().to_string()
        None => v
      }
      match sides_of(main) {
        Some(s) => {
          set("border-top-left-radius", s[0])
          set("border-top-right-radius", s[1])
          set("border-bottom-right-radius", s[2])
          set("border-bottom-left-radius", s[3])
        }
        None => ()
      }
    }
    "background" => {
      if wide {
        set("background-color", v)
        set("background-image", v)
        return
      }
      // its colour is its last layer's colour; an image is what is drawn over it
      let layers = split_top(v, ','.to_int())
      let mut color = "transparent"
      let mut image = "none"
      match layers.last() {
        Some(last) =>
          for w in split_words(last) {
            if is_color_word(w) {
              color = w
            }
          }
        None => ()
      }
      for l in layers {
        for w in split_words(l) {
          if w.contains("gradient(") || w.has_prefix("url(") {
            image = if image == "none" { w } else { image }
          }
        }
      }
      set("background-color", color)
      set("background-image", image)
    }
    "flex" => {
      let w = split_words(to_lower(v))
      match w {
        ["none"] => {
          set("flex-grow", "0")
          set("flex-shrink", "0")
          set("flex-basis", "auto")
        }
        ["auto"] => {
          set("flex-grow", "1")
          set("flex-shrink", "1")
          set("flex-basis", "auto")
        }
        ["initial"] => {
          set("flex-grow", "0")
          set("flex-shrink", "1")
          set("flex-basis", "auto")
        }
        [a] if parse_number(a) is Some(_) => {
          set("flex-grow", a)
          set("flex-shrink", "1")
          set("flex-basis", "0%")
        }
        [a] => {
          set("flex-grow", "1")
          set("flex-shrink", "1")
          set("flex-basis", a)
        }
        [a, b] if parse_number(b) is Some(_) => {
          set("flex-grow", a)
          set("flex-shrink", b)
          set("flex-basis", "0%")
        }
        [a, b] => {
          set("flex-grow", a)
          set("flex-shrink", "1")
          set("flex-basis", b)
        }
        [a, b, c, ..] => {
          set("flex-grow", a)
          set("flex-shrink", b)
          set("flex-basis", c)
        }
        _ => ()
      }
    }
    "flex-flow" =>
      for w in split_words(v) {
        if w.contains("wrap") {
          set("flex-wrap", w)
        } else {
          set("flex-direction", w)
        }
      }
    "gap" | "grid-gap" => {
      let w = split_words(v)
      if w.length() >= 1 {
        set("row-gap", w[0])
        set("column-gap", if w.length() > 1 { w[1] } else { w[0] })
      }
    }
    "grid-row-gap" => set("row-gap", v)
    "grid-column-gap" => set("column-gap", v)
    "place-items" => {
      let w = split_words(v)
      if w.length() >= 1 {
        set("align-items", w[0])
        set("justify-items", if w.length() > 1 { w[1] } else { w[0] })
      }
    }
    "place-content" => {
      let w = split_words(v)
      if w.length() >= 1 {
        set("align-content", w[0])
        set("justify-content", if w.length() > 1 { w[1] } else { w[0] })
      }
    }
    "place-self" => {
      let w = split_words(v)
      if w.length() >= 1 {
        set("align-self", w[0])
      }
    }
    "overflow" => set("overflow", split_words(v).get(0).unwrap_or(v))
    "overflow-x" | "overflow-y" => set("overflow", v)
    "text-decoration" | "text-decoration-line" => set("text-decoration-line", v)
    "list-style" =>
      for w in split_words(v) {
        if !w.has_prefix("url(") && w != "inside" && w != "outside" {
          set("list-style-type", w)
        }
      }
    "font" => {
      if wide {
        for p in ["font-style", "font-weight", "font-size", "line-height", "font-family"] {
          set(p, v)
        }
        return
      }
      // [style] [weight] size[/line] family
      let w = split_words(v)
      let mut i = 0
      let mut style = "normal"
      let mut weight = "normal"
      while i < w.length() {
        let x = to_lower(w[i])
        if x == "italic" || x == "oblique" {
          style = x
        } else if x == "bold" || x == "bolder" || x == "lighter" || parse_number(x) is Some(_) {
          weight = x
        } else if x == "normal" || x == "small-caps" {
          ()
        } else {
          break
        }
        i += 1
      }
      if i < w.length() {
        let size = w[i]
        match size.find("/") {
          Some(at) => {
            set("font-size", size.view(end_offset=at).to_owned())
            set("line-height", size.view(start_offset=at + 1).to_owned())
          }
          None => {
            set("font-size", size)
            set("line-height", "normal")
          }
        }
        let fam = w[i + 1:].iter().fold(init="", fn(a, b) { if a == "" { b } else { a + " " + b } })
        if fam != "" {
          set("font-family", fam)
        }
      }
      set("font-style", style)
      set("font-weight", weight)
    }
    "grid-area" => ()
    _ => set(name, v)
  }
}

///|
/// `specified` (each longhand's value as declared, var() put in) over `base` (the parent's computed style).
fn compute(specified : Map[String, String], base : Style, root : Bool, env : Env, vars : Map[String, String]) -> Style {
  ignore(vars)
  let s = Style::inherit_from(base, env)
  // the size of its words first: em is of it
  let parent_size = base.font_size
  match specified.get("font-size") {
    Some(v) => {
      let t = to_lower(v)
      let b : Basis = { em: parent_size, rem: env.root_size, vw: env.width }
      let size = match t {
        "inherit" | "unset" => Some(parent_size)
        "initial" | "medium" => Some(env.root_size)
        "xx-small" => Some(env.root_size * 0.6)
        "x-small" => Some(env.root_size * 0.75)
        "small" => Some(env.root_size * 0.889)
        "large" => Some(env.root_size * 1.2)
        "x-large" => Some(env.root_size * 1.5)
        "xx-large" => Some(env.root_size * 2.0)
        "smaller" => Some(parent_size / 1.2)
        "larger" => Some(parent_size * 1.2)
        _ =>
          match parse_len(t, b) {
            Some(Of(p, f)) => Some(p + f * parent_size)
            _ => None
          }
      }
      match size {
        Some(x) if x >= 0.0 => s.font_size = x
        _ => ()
      }
    }
    None => ()
  }
  let b : Basis = { em: s.font_size, rem: env.root_size, vw: env.width }
  let initial = Style::root(env)
  let len = fn(v : String) { parse_len(v, b) }
  let nonneg = fn(v : String) {
    match len(v) {
      Some(Of(p, f)) if p >= 0.0 && f >= 0.0 => Some(Of(p, f))
      Some(Auto) => Some(Auto)
      _ => None
    }
  }
  // colour before the rest: currentColor is of it
  match specified.get("color") {
    Some(v) =>
      match to_lower(v) {
        "inherit" | "unset" => s.color = base.color
        "initial" => s.color = initial.color
        t =>
          match parse_color(t, base.color, env.dark) {
            Some(c) => s.color = c
            None => ()
          }
      }
    None => ()
  }
  for k in 0..<4 {
    s.border_color[k] = s.color
  }
  let border_style : Array[String] = ["none", "none", "none", "none"]
  let border_width : Array[Double] = [3.0, 3.0, 3.0, 3.0]
  specified.each(fn(name, raw) {
    let v = raw.trim().to_string()
    let t = to_lower(v)
    // the keywords every property takes
    let keyword = t == "inherit" || t == "initial" || t == "unset" || t == "revert" || t == "revert-layer"
    if keyword {
      let from_parent = t == "inherit" || ((t == "unset" || t.has_prefix("revert")) && inherited.contains(name))
      take_whole(s, name, if from_parent { base } else { initial }, border_style, border_width)
      return
    }
    match name {
      "display" =>
        if [
            "block", "inline", "inline-block", "flex", "inline-flex", "grid", "inline-grid", "none", "contents",
            "list-item", "table", "table-row", "table-cell", "table-row-group", "table-header-group",
            "table-footer-group", "table-caption", "flow-root", "inline-table", "table-column", "table-column-group",
          ].contains(t) {
          s.display = t
        } else if t == "block flex" || t == "flex block" {
          s.display = "flex"
        } else if t == "inline flex" {
          s.display = "inline-flex"
        }
      "position" =>
        if ["static", "relative", "absolute", "fixed", "sticky"].contains(t) {
          s.position = if t == "fixed" { "absolute" } else if t == "sticky" { "relative" } else { t }
        }
      "top" => take(len(v), fn(l) { s.top = l })
      "right" => take(len(v), fn(l) { s.right = l })
      "bottom" => take(len(v), fn(l) { s.bottom = l })
      "left" => take(len(v), fn(l) { s.left = l })
      "width" => take(size_len(t, b), fn(l) { s.width = l })
      "height" => take(size_len(t, b), fn(l) { s.height = l })
      "min-width" => take(size_len(t, b), fn(l) { s.min_width = l })
      "min-height" => take(size_len(t, b), fn(l) { s.min_height = l })
      "max-width" => if t == "none" { s.max_width = Auto } else { take(size_len(t, b), fn(l) { s.max_width = l }) }
      "max-height" => if t == "none" { s.max_height = Auto } else { take(size_len(t, b), fn(l) { s.max_height = l }) }
      "aspect-ratio" => {
        let w = t.replace_all(old="auto", new="").trim().to_string()
        match w.find("/") {
          Some(at) =>
            match
              (
                parse_number(w.view(end_offset=at).to_owned()),
                parse_number(w.view(start_offset=at + 1).to_owned()),
              ) {
              (Some(x), Some(y)) if y > 0.0 => s.aspect = x / y
              _ => ()
            }
          None => take(parse_number(w), fn(x) { s.aspect = x })
        }
      }
      "box-sizing" => if t == "border-box" || t == "content-box" { s.box_sizing = t }
      "margin-top" => take(len(v), fn(l) { s.margin[0] = l })
      "margin-right" => take(len(v), fn(l) { s.margin[1] = l })
      "margin-bottom" => take(len(v), fn(l) { s.margin[2] = l })
      "margin-left" => take(len(v), fn(l) { s.margin[3] = l })
      "padding-top" => take(nonneg(v), fn(l) { s.padding[0] = l })
      "padding-right" => take(nonneg(v), fn(l) { s.padding[1] = l })
      "padding-bottom" => take(nonneg(v), fn(l) { s.padding[2] = l })
      "padding-left" => take(nonneg(v), fn(l) { s.padding[3] = l })
      "border-top-width" | "border-right-width" | "border-bottom-width" | "border-left-width" => {
        let k = side_index(name)
        let w = match t {
          "thin" => Some(1.0)
          "medium" => Some(3.0)
          "thick" => Some(5.0)
          _ =>
            match len(v) {
              Some(Of(p, _)) if p >= 0.0 => Some(p)
              _ => None
            }
        }
        take(w, fn(x) { border_width[k] = x })
      }
      "border-top-style" | "border-right-style" | "border-bottom-style" | "border-left-style" =>
        if is_border_style(t) {
          border_style[side_index(name)] = t
        }
      "border-top-color" | "border-right-color" | "border-bottom-color" | "border-left-color" =>
        take(parse_color(t, s.color, env.dark), fn(c) { s.border_color[side_index(name)] = c })
      "border-top-left-radius" => take(radius_len(t, b), fn(l) { s.radius[0] = l })
      "border-top-right-radius" => take(radius_len(t, b), fn(l) { s.radius[1] = l })
      "border-bottom-right-radius" => take(radius_len(t, b), fn(l) { s.radius[2] = l })
      "border-bottom-left-radius" => take(radius_len(t, b), fn(l) { s.radius[3] = l })
      "flex-direction" => if ["row", "row-reverse", "column", "column-reverse"].contains(t) { s.flex_direction = t }
      "flex-wrap" => if ["nowrap", "wrap", "wrap-reverse"].contains(t) { s.flex_wrap = t }
      "justify-content" => s.justify = align_word(t)
      "align-items" => s.align_items = align_word(t)
      "align-self" => s.align_self = align_word(t)
      "align-content" => s.align_content = align_word(t)
      "justify-items" => s.justify_items = align_word(t)
      "flex-grow" => take(parse_number(t), fn(x) { if x >= 0.0 { s.grow = x } })
      "flex-shrink" => take(parse_number(t), fn(x) { if x >= 0.0 { s.shrink = x } })
      "flex-basis" => if t == "content" { s.basis = Auto } else { take(size_len(t, b), fn(l) { s.basis = l }) }
      "row-gap" => if t == "normal" { s.row_gap = Auto } else { take(nonneg(v), fn(l) { s.row_gap = l }) }
      "column-gap" => if t == "normal" { s.column_gap = Auto } else { take(nonneg(v), fn(l) { s.column_gap = l }) }
      "order" => take(parse_int(t), fn(x) { s.order = x })
      "grid-template-columns" => s.grid_columns = t
      "grid-template-rows" => s.grid_rows = t
      "grid-column" | "grid-column-start" => s.grid_column = t
      "grid-row" | "grid-row-start" => s.grid_row = t
      "background-color" => take(parse_color(t, s.color, env.dark), fn(c) { s.background = c })
      "background-image" => s.background_image = if t == "none" { "" } else { v }
      "font-weight" => {
        let w = match t {
          "normal" => Some(400)
          "bold" => Some(700)
          "bolder" => Some(if base.font_weight < 600 { 700 } else { 900 })
          "lighter" => Some(if base.font_weight > 500 { 400 } else { 100 })
          _ => parse_number(t).map(fn(x) { x.to_int() })
        }
        take(w, fn(x) { if x >= 1 && x <= 1000 { s.font_weight = x } })
      }
      "font-style" => s.italic = t.has_prefix("italic") || t.has_prefix("oblique")
      "font-family" => {
        // the face: the first generic or known family named (the app draws its own faces)
        let fams = split_top(t, ','.to_int())
        let mut picked = false
        for f in fams {
          let name = f.trim().to_string().replace_all(old="\"", new="").replace_all(old="'", new="")
          if name.contains("mono") ||
            name.contains("code") ||
            name.contains("courier") ||
            name == "menlo" ||
            name == "consolas" ||
            name.contains("sfmono") {
            s.mono = true
            s.serif = false
            picked = true
            break
          }
          if name == "serif" || name.contains("georgia") || name.contains("times") || name == "ui-serif" {
            s.mono = false
            s.serif = true
            picked = true
            break
          }
          if name.contains("sans") ||
            name == "system-ui" ||
            name.contains("apple") ||
            name.contains("inter") ||
            name.contains("helvetica") ||
            name.contains("arial") ||
            name.contains("segoe") ||
            name.contains("pingfang") {
            s.mono = false
            s.serif = false
            picked = true
            break
          }
        }
        if !picked {
          s.mono = false
          s.serif = false
        }
      }
      "line-height" =>
        if t == "normal" {
          s.line_height = 0.0
        } else {
          match parse_number(t) {
            Some(k) => s.line_height = k * s.font_size
            None =>
              match len(t) {
                Some(Of(p, f)) => s.line_height = p + f * s.font_size
                _ => ()
              }
          }
        }
      "text-align" =>
        s.text_align = match t {
          "left" | "start" | "justify" | "-webkit-left" => "start"
          "right" | "end" | "-webkit-right" => "end"
          "center" | "-webkit-center" => "center"
          _ => s.text_align
        }
      "text-decoration-line" => {
        s.underline = t.contains("underline")
        s.strike = t.contains("line-through")
      }
      "white-space" | "white-space-collapse" | "text-wrap" | "text-wrap-mode" =>
        if ["normal", "nowrap", "pre", "pre-wrap", "pre-line", "break-spaces", "wrap"].contains(t) {
          s.white_space = if t == "wrap" { "normal" } else { t }
        }
      "letter-spacing" =>
        if t == "normal" {
          s.letter_spacing = 0.0
        } else {
          match len(t) {
            Some(Of(p, _)) => s.letter_spacing = p
            _ => ()
          }
        }
      "text-transform" => if ["none", "uppercase", "lowercase", "capitalize"].contains(t) { s.text_transform = t }
      "text-overflow" => s.ellipsis = t == "ellipsis"
      "font-variant-numeric" => s.tabular = t.contains("tabular-nums")
      "opacity" => {
        let x = if t.has_suffix("%") {
          parse_number(t.view(end_offset=t.length() - 1).to_owned()).map(fn(x) { x / 100.0 })
        } else {
          parse_number(t)
        }
        take(x, fn(o) { s.opacity = if o < 0.0 { 0.0 } else if o > 1.0 { 1.0 } else { o } })
      }
      "overflow" => if ["visible", "hidden", "clip", "auto", "scroll"].contains(t) { s.overflow = t }
      "visibility" => s.visible = t == "visible"
      "box-shadow" => s.shadow = shadow_of(t, s.color, b, env.dark)
      "list-style-type" => s.list_style = t
      "content" =>
        s.content = if t == "none" || t == "normal" {
          None
        } else {
          Some(content_text(v))
        }
      "vertical-align" => s.vertical_align = t
      "cursor" => s.cursor = t
      "touch-action" => s.touch_action = t
      "user-select" | "-webkit-user-select" => s.user_select = t
      "transition" => s.transition = t
      "z-index" => take(parse_int(t), fn(x) { s.z_index = x })
      _ => ()
    }
  })
  for k in 0..<4 {
    s.border_width[k] = if border_style[k] == "none" || border_style[k] == "hidden" { 0.0 } else { border_width[k] }
  }
  // the root's display is block (the fragment's own box)
  if root {
    ()
  }
  s
}

///|
/// A property set from `from` whole (inherit, initial, unset).
fn take_whole(
  s : Style,
  name : String,
  from : Style,
  border_style : Array[String],
  border_width : Array[Double],
) -> Unit {
  match name {
    "color" => s.color = from.color
    "background-color" => s.background = from.background
    "display" => s.display = from.display
    "font-weight" => s.font_weight = from.font_weight
    "font-style" => s.italic = from.italic
    "font-family" => {
      s.mono = from.mono
      s.serif = from.serif
    }
    "line-height" => s.line_height = from.line_height
    "text-align" => s.text_align = from.text_align
    "white-space" => s.white_space = from.white_space
    "width" => s.width = from.width
    "height" => s.height = from.height
    "margin-top" => s.margin[0] = from.margin[0]
    "margin-right" => s.margin[1] = from.margin[1]
    "margin-bottom" => s.margin[2] = from.margin[2]
    "margin-left" => s.margin[3] = from.margin[3]
    "padding-top" => s.padding[0] = from.padding[0]
    "padding-right" => s.padding[1] = from.padding[1]
    "padding-bottom" => s.padding[2] = from.padding[2]
    "padding-left" => s.padding[3] = from.padding[3]
    "border-top-style" | "border-right-style" | "border-bottom-style" | "border-left-style" =>
      border_style[side_index(name)] = if from.border_width[side_index(name)] > 0.0 { "solid" } else { "none" }
    "border-top-width" | "border-right-width" | "border-bottom-width" | "border-left-width" =>
      border_width[side_index(name)] = from.border_width[side_index(name)]
    "border-top-color" | "border-right-color" | "border-bottom-color" | "border-left-color" =>
      s.border_color[side_index(name)] = from.border_color[side_index(name)]
    "border-top-left-radius" => s.radius[0] = from.radius[0]
    "border-top-right-radius" => s.radius[1] = from.radius[1]
    "border-bottom-right-radius" => s.radius[2] = from.radius[2]
    "border-bottom-left-radius" => s.radius[3] = from.radius[3]
    "opacity" => s.opacity = from.opacity
    "visibility" => s.visible = from.visible
    "text-decoration-line" => {
      s.underline = from.underline
      s.strike = from.strike
    }
    "letter-spacing" => s.letter_spacing = from.letter_spacing
    "text-transform" => s.text_transform = from.text_transform
    "list-style-type" => s.list_style = from.list_style
    "cursor" => s.cursor = from.cursor
    "box-shadow" => s.shadow = from.shadow
    "flex-direction" => s.flex_direction = from.flex_direction
    "gap" | "row-gap" => s.row_gap = from.row_gap
    "column-gap" => s.column_gap = from.column_gap
    _ => ()
  }
}

///|
fn side_index(name : String) -> Int {
  if name.contains("top") {
    0
  } else if name.contains("right") {
    1
  } else if name.contains("bottom") {
    2
  } else {
    3
  }
}

///|
/// A size: a length, or the keywords that size by what it holds (as auto: what it holds decides).
fn size_len(t : String, b : Basis) -> Len? {
  match t {
    "fit-content" | "max-content" | "min-content" | "-webkit-fill-available" | "stretch" => Some(Auto)
    _ =>
      match parse_len(t, b) {
        Some(Of(p, f)) if p >= 0.0 && f >= 0.0 => Some(Of(p, f))
        Some(Auto) => Some(Auto)
        _ => None
      }
  }
}

///|
fn radius_len(t : String, b : Basis) -> Len? {
  // its first value (an ellipse's horizontal radius)
  let first = split_words(t).get(0).unwrap_or(t)
  match parse_len(first, b) {
    Some(Of(p, f)) if p >= 0.0 && f >= 0.0 => Some(Of(p, f))
    _ => None
  }
}

///|
fn align_word(t : String) -> String {
  let w = t.replace_all(old="safe ", new="").replace_all(old="unsafe ", new="")
  match w {
    "start" | "flex-start" | "self-start" | "left" => "start"
    "end" | "flex-end" | "self-end" | "right" => "end"
    "center" => "center"
    "stretch" => "stretch"
    "baseline" | "first baseline" | "last baseline" => "baseline"
    "space-between" => "space-between"
    "space-around" => "space-around"
    "space-evenly" => "space-evenly"
    "auto" => "auto"
    _ => "normal"
  }
}

///|
fn shadow_of(t : String, current : Int64, b : Basis, dark : Bool) -> (Double, Double, Double, Double, Int64, Bool) {
  if t == "none" {
    return (0.0, 0.0, -1.0, 0.0, 0L, false)
  }
  // its first shadow
  let first = split_top(t, ','.to_int()).get(0).unwrap_or(t)
  let nums = []
  let mut color = current
  let mut inset = false
  for w in split_words(first) {
    if w == "inset" {
      inset = true
    } else {
      match parse_len(w, b) {
        Some(Of(p, _)) => nums.push(p)
        _ =>
          match parse_color(w, current, dark) {
            Some(c) => color = c
            None => ()
          }
      }
    }
  }
  if nums.length() < 2 {
    return (0.0, 0.0, -1.0, 0.0, 0L, false)
  }
  (nums[0], nums[1], nums.get(2).unwrap_or(0.0), nums.get(3).unwrap_or(0.0), color, inset)
}

///|
/// A content property's words: its strings joined, escapes read.
fn content_text(v : String) -> String {
  let b = StringBuilder()
  for w in split_words(v) {
    if w.length() >= 2 {
      let q = w.code_unit_at(0).to_int()
      if q == '"'.to_int() || q == '\''.to_int() {
        let inner = w.view(start_offset=1, end_offset=w.length() - 1).to_owned()
        let mut i = 0
        while i < inner.length() {
          let c = inner.code_unit_at(i).to_int()
          if c == '\\'.to_int() && i + 1 < inner.length() {
            // \hex or a character
            let mut k = i + 1
            let mut v = 0
            let mut digits = 0
            while k < inner.length() && digits < 6 && hex_digit(lower(inner.code_unit_at(k).to_int())) >= 0 {
              v = v * 16 + hex_digit(lower(inner.code_unit_at(k).to_int()))
              k += 1
              digits += 1
            }
            if digits > 0 {
              b.write_char(Int::unsafe_to_char(v))
              if k < inner.length() && inner.code_unit_at(k).to_int() == ' '.to_int() {
                k += 1
              }
              i = k
            } else {
              b.write_char(Int::unsafe_to_char(inner.code_unit_at(i + 1).to_int()))
              i += 2
            }
          } else {
            b.write_char(Int::unsafe_to_char(c))
            i += 1
          }
        }
      }
    }
  }
  b.to_string()
}
