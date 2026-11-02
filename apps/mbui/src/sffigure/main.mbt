// Render a named share graphic to a PNG through mbui's offscreen renderer. See docs/figures.md.

///|
fn figure_valid(name : String, path : String) -> Bool {
  (name == "wrap" || name == "align" || name == "wrap-normal" || name == "wrap-reverse" ||
    name == "align-edge" || name == "align-text") && path != ""
}

///|
fn figure_usage() -> Unit {
  @film.say("figure: MBUI_FIGURE=wrap|align|wrap-normal|wrap-reverse|align-edge|align-text or MBUI_FIGURE_SCENE=<scene.json>; MBUI_FIGURE_OUT=<out.png> [MBUI_FIGURE_FONT=<font.ttf>]")
}

///|
fn figure_initialize(font : String) -> Unit {
  let font_ok = if font == "" {
    match @sfbase.bundled_ui_face() {
      Some(bytes) => @ui.face_add_bytes(@hostapi.face_ui, bytes)
      None => false
    }
  } else {
    @ui.face_add(@hostapi.face_ui, font)
  }
  if !font_ok {
    @film.say(if font == "" { "figure: could not load the bundled UI face" } else { "figure: could not load font \{font}" })
    @film.exit(1)
  }
  @sf.set_dark(Some(true))
}

///|
fn figure(name : String, path : String, font : String) -> Bool {
  let single = name == "wrap-normal" || name == "wrap-reverse" || name == "align-edge" || name == "align-text"
  // Tester resets the app's theme and faces when it starts. Give them after that reset, before the first view reads
  // either, just as sffilm's source gives the app its faces. The closure is built once for this picture.
  let initialized = Ref(false)
  let view = fn(c : @ui.Ctx) {
    if !initialized.val {
      figure_initialize(font)
      initialized.val = true
    }
    match name {
      "wrap" => @sfgraphic.wrap_figure(c)
      "align" => @sfgraphic.alignment_figure(c)
      "wrap-normal" => @sfgraphic.wrap_card_figure(c, false)
      "wrap-reverse" => @sfgraphic.wrap_card_figure(c, true)
      "align-edge" => @sfgraphic.alignment_card_figure(c, false)
      _ => @sfgraphic.alignment_card_figure(c, true)
    }
  }
  @film.picture(view, path~, w=if single { 480.0 } else { 960.0 }, h=if single { 270.0 } else { 540.0 }, scale=if single { 5.0 } else { 2.5 }, corner_faults_ok=fn(faults) {
    if name == "align" || name == "align-edge" { @sfgraphic.alignment_corner_faults_ok(faults) } else { faults.is_empty() }
  })
}

///|
fn figure_scene(scene : @sfgraphic.GraphicScene, path : String, font : String) -> Bool {
  let initialized = Ref(false)
  @film.picture(fn(c) {
    if !initialized.val {
      figure_initialize(font)
      initialized.val = true
    }
    @sfgraphic.draw_graphic_scene(c, scene)
  }, path~, w=scene.width, h=scene.height, scale=scene.scale)
}

///|
fn main {
  let font = @film.arg("MBUI_FIGURE_FONT")
  let batch = @film.arg("MBUI_FIGURE_BATCH")
  let scene_path = @film.arg("MBUI_FIGURE_SCENE")
  if scene_path != "" {
    let path = @film.arg("MBUI_FIGURE_OUT")
    if batch != "" || path == "" {
      figure_usage()
      @film.exit(2)
      return
    }
    match @sfgraphic.graphic_scene(@film.read_text(scene_path)) {
      Some(scene) => @film.exit(if figure_scene(scene, path, font) { 0 } else { 1 })
      None => {
        @film.say("figure: scene is invalid or could not be read: \{scene_path}")
        @film.exit(2)
      }
    }
    return
  }
  if batch != "" {
    let dir = @film.arg("MBUI_FIGURE_DIR")
    if dir == "" {
      @film.say("figure: MBUI_FIGURE_DIR is required for a batch")
      @film.exit(2)
      return
    }
    for part in batch.split(",") {
      let name = part.to_owned()
      if !figure_valid(name, dir) {
        figure_usage()
        @film.exit(2)
        return
      }
    }
    for part in batch.split(",") {
      let name = part.to_owned()
      if !figure(name, dir + "/" + name + ".png", font) {
        @film.exit(1)
        return
      }
    }
  } else {
    let name = @film.arg("MBUI_FIGURE")
    let path = @film.arg("MBUI_FIGURE_OUT")
    if !figure_valid(name, path) {
      figure_usage()
      @film.exit(2)
      return
    }
    if !figure(name, path, font) {
      @film.exit(1)
      return
    }
  }
  @film.exit(0)
}
