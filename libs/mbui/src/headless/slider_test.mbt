// The headless slider (@headless.slider), under a look of the tests' own: read out a slider with its range and value,
// stepped by Increment/Decrement, arrow/Home/End keys and dragging along its track; disabled, none of these. Each
// window is made by `window` (window_test.mbt), which holds that the slider's own file draws and lays out nothing.

///|
test "a slider is read out with its range and stepped by a screen reader, keys, and drag" {
  let val = @signals.signal(50.0, same=fn(a : Double, b : Double) { a == b })
  let told : Array[Double] = []
  let state : Ref[@headless.Slider?] = Ref(None)
  let t = window(fn(root) {
    @headless.slider(
      root,
      fn() { "音量" },
      fn() { val.get() },
      min=0.0,
      max=100.0,
      step=5.0,
      thumb_room=20.0,
      fn(next) {
        told.push(next)
        val.set(next)
      },
      fn(v, s) {
        state.val = Some(s)
        v.width(Is(Some(220.0))).height(Is(Some(30.0))).ground(Is(c_rest)) |> ignore
      },
    )
    |> ignore
  })
  let s0 = t.get(Slider, label="音量")
  assert_eq((s0.value, s0.range, state.val.unwrap().part()), ("50", Some((0.0, 50.0, 100.0)), 0.5))
  t.act(Slider, Increment, label="音量")
  t.act(Slider, Focus, label="音量")
  t.key(@ui.key_code_right)
  t.key(@ui.key_code_home)
  t.key(@ui.key_code_end)
  // Drag to middle of 220 wide slider (x=110 -> part=0.5 -> 50)
  t.press_at(110.0, 15.0)
  t.release(110.0, 15.0)
  assert_eq(told, [55.0, 60.0, 0.0, 100.0, 50.0])
}
