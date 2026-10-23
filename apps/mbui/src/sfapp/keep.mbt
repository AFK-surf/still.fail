// How far a drive's file has come while it is fetched (Parts.kt DownloadChip): the phone's rows'.

///|
/// How far a file of the drive has come while it is fetched (Parts.kt DownloadChip, FillChip's `progress`): the
/// allowance's rounded box, its ground filled in the accent from the left as it comes (moving smoothly to each new
/// share over 500 ms), n% on it.
fn download_chip(c : @ui.Ctx, key : String, percent : Int) -> Unit {
  let t = @sf.theme()
  let p = if percent < 0 {
    0
  } else if percent > 100 {
    100
  } else {
    percent
  }
  // (at its first share at once, as animateFloatAsState starts)
  let drawn = @motion.animate(c, "fetch/" + key, p.to_double(), spec=@motion.tween(500.0))
  c.box(h=Px(20.0), radius=@sf.fill_chip_corner, bg=t.p.chip, clip=true, justify=JCenter, fn() {
    if drawn > 0.0 {
      c.layer(fn() {
        c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), fn() {
          c.box(w=Fill(drawn), h=Fill(1.0), bg=@sf.alpha(t.p.accent, 0.2), fn() {  }) |> ignore
          if drawn < 100.0 {
            c.box(w=Fill(100.0 - drawn), h=Fill(1.0), fn() {  }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    }
    c.box(dir=Row, padx=8.0, align=ACenter, fn() {
      c.text("\{p}%", size=11.0, weight=600, color=t.p.text, wrap=false, line=13.0) |> ignore
    })
    |> ignore
  })
  |> ignore
}
