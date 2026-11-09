// How often the frames come for what moves on by the clock (src/ui/frame_pace.mbt), on a host: one scene of the app's
// waits, chosen by MBUI_PACE_SCENE: `spinner` a 14-point ring turning once in 800 ms (the app's spinner's), `fade` a
// card fading in and out over 6 s, `still` words that do not move. MBUI_PROBE=1 says the frames drawn each second
// (`APP=pacedemo scripts/mac.sh run`, scripts/android.sh): what the frames' pace saves, measured before and after it.

///|
fn main {
  let scene = @ui.env("MBUI_PACE_SCENE")
  let pi = 3.141592653589793
  @ui.run("pacedemo", fn(_c) {  }, tree=fn(root) {
    root.box(fn(page) {
      page.grow(Is(1.0)).ground(Is(0xFFFFFFFFL)) |> ignore
      match scene {
        "spinner" =>
          page.box(fn(v) {
            let round = @ui.arc(7.0, 7.0, 6.0, from=0.0, sweep=2.0 * pi)
            let part = @ui.arc(7.0, 7.0, 6.0, from=-0.75 * pi, sweep=0.5 * pi)
            v
            .width(Is(Some(14.0)))
            .height(Is(Some(14.0)))
            .lines(Is([@ui.line(round, width=2.0, color=0xD0D0D0FFL), @ui.line(part, width=2.0, color=0x3366CCFFL)]))
            .turn(By(fn() { v.cycle(800.0) * 2.0 * pi }), drawn=true)
            |> ignore
          })
          |> ignore
        "fade" =>
          page.box(fn(v) {
            v
            .width(Is(Some(240.0)))
            .height(Is(Some(140.0)))
            .ground(Is(0x3366CCFFL))
            .alpha(By(fn() { 1.0 - (2.0 * v.cycle(6000.0) - 1.0).abs() }))
            |> ignore
          })
          |> ignore
        _ => ()
      }
    })
    |> ignore
  })
}
