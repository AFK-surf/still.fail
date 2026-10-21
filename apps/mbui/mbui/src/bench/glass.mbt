// Glass scenes (not nanoui's: run when named, BENCH_SCENES=glass,glass-solid,liquid): the list scene under
// still.fail's frosted top bar, a floating composer and a jump button (three captures a frame, as a chat has),
// the same with glass drawn solid (what reduce transparency draws: the cost without the passes), and three liquid
// discs of one group with a liquid capsule over the rows' words (liquid-flat: the same, nothing bent).

///|
let glass_scene_names : Array[String] = ["glass", "glass-solid", "liquid", "liquid-flat"]

///|
fn glass_scene(c : @ui.Ctx) -> Unit {
  @ui.set_glass_solid(Some(false))
  glass_frame(c, false)
}

///|
fn glass_solid_scene(c : @ui.Ctx) -> Unit {
  @ui.set_glass_solid(Some(true))
  glass_frame(c, false)
}

///|
fn liquid_scene(c : @ui.Ctx) -> Unit {
  @ui.set_glass_solid(Some(false))
  glass_frame(c, true)
}

///|
/// The liquid scene with nothing bent (no refraction, no split): what is under the discs as it is, to tell the
/// bending from (its shot against liquid's).
fn liquid_flat_scene(c : @ui.Ctx) -> Unit {
  @ui.set_glass_solid(Some(false))
  glass_frame(c, true, refraction=0.0)
}

///|
fn glass_frame(c : @ui.Ctx, liquid : Bool, refraction? : Double = 9.0) -> Unit {
  let lq = @ui.Glass::liquid(merge=24.0, refraction~, chroma=if refraction > 0.0 { 0.18 } else { 0.0 })
  let bar = @ui.Glass::frosted(blur=24.0, tint=0xF5F3EFB3L, solid=0xF5F3EFFFL)
  let float = @ui.Glass::frosted(blur=20.0, tint=0xFFFFFFB8L, solid=0xFDFCFBFFL)
  c.box(w=Fill(1.0), h=Fill(1.0), bg=0xF5F3EFFFL, fn() {
    list(c)
    c.layer(fn() {
      c.box(w=Fill(1.0), h=Px(54.0), glass=bar, fn() {
        c.box(dir=Row, h=Fill(1.0), padx=16.0, align=ACenter, fn() {
          c.text("整理发布清单", size=16.0, weight=600, wrap=false) |> ignore
        })
        |> ignore
      })
      |> ignore
      c.spacer()
      if liquid {
        // over the rows' words (at the left), so what the bezel bends is there to see
        c.box(dir=Row, w=Fill(1.0), pl=40.0, gap=8.0, glass_group=true, fn() {
          for _ in 0..<3 {
            c.box(w=Px(64.0), h=Px(64.0), radius=32.0, glass=lq, fn() {  })
            |> ignore
          }
        })
        |> ignore
        c.box(w=Fill(1.0), pl=60.0, pt=14.0, pb=14.0, align=AStart, fn() {
          c.box(h=Px(48.0), padx=22.0, radius=24.0, justify=JCenter, align=ACenter, glass=lq, fn() {
            c.text("液态玻璃", size=15.0, weight=600, wrap=false) |> ignore
          })
          |> ignore
        })
        |> ignore
      } else {
        c.box(w=Fill(1.0), align=AEnd, pr=18.0, pb=8.0, fn() {
          c.box(w=Px(36.0), h=Px(36.0), radius=18.0, glass=float, shadow=2.0, shadow_color=0x0000004DL, shadow_y=0.5, fn() {
             })
          |> ignore
        })
        |> ignore
      }
      c.box(w=Fill(1.0), pl=10.0, pr=10.0, pt=8.0, pb=10.0, fn() {
        c.box(
          w=Fill(1.0),
          h=Px(52.0),
          radius=26.0,
          pad=8.0,
          justify=JCenter,
          glass=float,
          shadow=2.0,
          shadow_color=0x0000004DL,
          shadow_y=0.5,
          fn() { c.text("发消息", size=15.0, wrap=false) |> ignore },
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}
