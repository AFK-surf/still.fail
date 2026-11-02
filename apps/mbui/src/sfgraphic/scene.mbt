// A graphic supplied as data to a prebuilt renderer. Its nodes call the same mbui and app views as a coded figure.

///|
pub(all) struct GraphicScene {
  width : Double
  height : Double
  scale : Double
  background : Int64
  children : Array[GraphicNode]
}

///|
pub(all) enum GraphicNode {
  Center(Array[GraphicNode])
  Panel(Double, Double, Double, Double, Int64, Double, Array[GraphicNode])
  Words(Double, Double, String, Double, Int64, Int, Double, Double)
  SignIn(Double, Bool, String)
}

///|
fn scene_number(m : Map[String, Json], key : String) -> Double? {
  match m.get(key) {
    Some(Number(n, ..)) if !n.is_nan() && !n.is_inf() => Some(n)
    _ => None
  }
}

///|
fn scene_number_or(m : Map[String, Json], key : String, fallback : Double) -> Double? {
  if m.get(key) is None { Some(fallback) } else { scene_number(m, key) }
}

///|
fn scene_only(m : Map[String, Json], allowed : Array[String]) -> Bool {
  m.keys().all(fn(key) { allowed.contains(key) })
}

///|
fn scene_color(m : Map[String, Json], key : String) -> Int64? {
  guard m.get(key) is Some(String(s)) && s.length() == 9 && s.has_prefix("#") else { return None }
  let mut color = 0L
  for ch in s.view(start_offset=1) {
    let d = match ch {
      '0'..='9' => ch.to_int() - '0'.to_int()
      'a'..='f' => ch.to_int() - 'a'.to_int() + 10
      'A'..='F' => ch.to_int() - 'A'.to_int() + 10
      _ => return None
    }
    color = color * 16L + d.to_int64()
  }
  Some(color)
}

///|
fn scene_children(m : Map[String, Json], depth : Int) -> Array[GraphicNode]? {
  guard depth <= 64 && m.get("children") is Some(Array(items)) else { return None }
  let out = []
  for item in items {
    match scene_node(item, depth + 1) {
      Some(node) => out.push(node)
      None => return None
    }
  }
  Some(out)
}

///|
fn scene_node(value : Json, depth : Int) -> GraphicNode? {
  guard depth <= 64 && value is Object(m) && m.get("type") is Some(String(kind)) else { return None }
  match kind {
    "center" if scene_only(m, ["type", "children"]) =>
      match scene_children(m, depth) {
        Some(children) => Some(Center(children))
        None => None
      }
    "panel" if scene_only(m, ["type", "x", "y", "width", "height", "background", "radius", "children"]) => {
      guard scene_number(m, "x") is Some(x) && scene_number(m, "y") is Some(y) &&
        scene_number(m, "width") is Some(w) && w > 0.0 && scene_number(m, "height") is Some(h) && h > 0.0 &&
        scene_color(m, "background") is Some(color) && scene_number_or(m, "radius", 0.0) is Some(radius) && radius >= 0.0 &&
        scene_children(m, depth) is Some(children) else { return None }
      Some(Panel(x, y, w, h, color, radius, children))
    }
    "words" if scene_only(m, ["type", "x", "y", "text", "size", "color", "weight", "width", "line"]) => {
      guard scene_number(m, "x") is Some(x) && scene_number(m, "y") is Some(y) &&
        m.get("text") is Some(String(words)) && scene_number(m, "size") is Some(size) && size > 0.0 &&
        scene_color(m, "color") is Some(color) && scene_number_or(m, "weight", 400.0) is Some(weight) &&
        weight >= 1.0 && weight <= 1000.0 && weight == weight.floor() &&
        scene_number_or(m, "width", 0.0) is Some(width) && width >= 0.0 &&
        scene_number_or(m, "line", 0.0) is Some(line) && line >= 0.0 else { return None }
      Some(Words(x, y, words, size, color, weight.to_int(), width, line))
    }
    "sign-in-card" if scene_only(m, ["type", "width", "reverse", "key"]) => {
      guard scene_number(m, "width") is Some(width) && width > 0.0 &&
        m.get("key") is Some(String(key)) && key != "" else { return None }
      let reverse = match m.get("reverse") {
        None | Some(False) => false
        Some(True) => true
        _ => return None
      }
      Some(SignIn(width, reverse, key))
    }
    _ => None
  }
}

///|
/// Parse and validate before drawing, so an unknown or incomplete scene cannot silently omit content.
pub fn graphic_scene(text : String) -> GraphicScene? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(m) && scene_only(m, ["version", "width", "height", "scale", "background", "children"]) &&
    scene_number(m, "version") is Some(version) && version == 1.0 &&
    scene_number(m, "width") is Some(width) && width > 0.0 &&
    scene_number(m, "height") is Some(height) && height > 0.0 &&
    scene_number(m, "scale") is Some(scale) && scale > 0.0 &&
    width * scale <= 16384.0 && height * scale <= 16384.0 &&
    scene_color(m, "background") is Some(background) && scene_children(m, 0) is Some(children) else { return None }
  Some({ width, height, scale, background, children })
}

///|
fn draw_graphic_nodes(c : @ui.Ctx, nodes : Array[GraphicNode]) -> Unit {
  for node in nodes {
    match node {
      Center(children) =>
        c.box(style=@ui.css("row w=Full h=Full align=ACenter justify=JCenter"), fn() {
          draw_graphic_nodes(c, children)
        }) |> ignore
      Panel(x, y, w, h, background, radius, children) =>
        @figure.panel(c, x, y, w, h, background, radius, fn() { draw_graphic_nodes(c, children) })
      Words(x, y, words, size, color, weight, width, line) =>
        @figure.words(c, x, y, words, size, color, weight~, width~, line~)
      SignIn(width, reverse, key) => sign_in_example(c, width, reverse, key)
    }
  }
}

///|
pub fn draw_graphic_scene(c : @ui.Ctx, scene : GraphicScene) -> Unit {
  c.set_theme(@sf.ui_theme_now())
  @figure.canvas(c, scene.width, scene.height, scene.background, fn() {
    draw_graphic_nodes(c, scene.children)
  })
}
