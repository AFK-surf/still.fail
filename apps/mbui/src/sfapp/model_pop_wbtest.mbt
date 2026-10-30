// The model's panel beside its control (sfpages model_triple.mbt) in a desktop's window: as wide as its columns'
// words, no wider (2026-10-26 用户「没啥内容也这么宽感觉会很奇怪」), and as wide whichever model is picked in it.

///|
/// The fixture's `mode` in a desktop's window, its model's panel open beside its control.
fn model_pop(mode : String) -> @ui.Tester {
  let src = fixture_app(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(squeeze_opening)
  t
}

///|
/// The words `name` as drawn last in the panel: how wide they are, the room they have, their weight.
fn pop_words(t : @ui.Tester, name : String) -> @ui.Laid? raise {
  let (px, py, pw, ph) = t.get(@ui.Dialog).rect
  t
  .boxes()
  .iter()
  .find_first(fn(b) { b.kind == "text" && b.text == name && b.x >= px && b.x < px + pw && b.y >= py && b.y < py + ph })
}

///|
test "wide, short names: the model's panel ends where its last column does, its models' column no wider than its least" {
  let t = model_pop("newchat-model")
  let (px, _, pw, _) = t.get(@ui.Dialog).rect
  let effort = t.get(Button, label="高").rect
  let model = t.get(Button, label="Opus 5.5").rect
  // (the panel's padding and its line past its last column, no room more)
  assert_true(px + pw - (effort.0 + effort.2) <= @sf.panel_pad + 1.5, msg="\{t.get(@ui.Dialog).rect} \{effort}")
  // (its names short: as wide as its least, not what a fixed panel left it)
  assert_true(model.2 <= @sfpages.triple_models_least + 0.5, msg="\{model}")
}

///|
test "wide, how hard it thinks and how fast taller than the models' most: the models scroll in all of the row, none cut off over room left empty" {
  let t = model_pop("newchat-tall-model")
  let fast = t.get(Button, label="Fast").rect
  let foot = fast.1 + fast.3
  let names = ["Opus 5.5", "Sonnet 5", "GPT-6 Astra", "DeepSeek V4.1 Flash", "Grok 4.7 Build Fast", "Kimi For Coding", "SWE-2", "GPT-6.1 Sol",
    "GPT-6.1 Terra",
  ]
  let (px, py, pw, ph) = t.get(@ui.Dialog).rect
  let rows = t
    .boxes()
    .filter(fn(b) { b.kind == "text" && names.contains(b.text) && b.x >= px && b.x < px + pw && b.y >= py && b.y < py + ph })
  assert_true(rows.length() > 0)
  // (each model laid out higher than the foot of the column beside it shows: none cut off over the room under them)
  for b in rows {
    if b.y < foot - 1.0 {
      assert_true(b.cut.3 > 0.0, msg="\{b.text} at \{b.y} cut off, the column beside the models down to \{foot}")
    }
  }
}

///|
test "wide: another model picked, its runtimes fewer, the panel as wide as it opened; every name whole on its line" {
  let t = model_pop("newchat-crowded-model")
  let opened = t.get(@ui.Dialog).rect
  for name in ["Opus 5.5", "Grok 4.7 Build Fast", "DeepSeek V4.1 Flash"] {
    t.click(Button, label=name)
    t.run_for(squeeze_opening)
    // (picked, in the picked weight)
    match pop_words(t, name) {
      Some(b) => {
        assert_eq(b.weight, 500, msg="\{name} not picked")
        assert_true(b.words_w <= b.w + 0.5 && b.h < 2.0 * b.font_size, msg="\{name} not whole on one line")
      }
      None => fail("\{name} not drawn")
    }
    assert_true(t.get(@ui.Dialog).rect == opened, msg="\{name} picked: \{t.get(@ui.Dialog).rect}, opened \{opened}")
  }
}
