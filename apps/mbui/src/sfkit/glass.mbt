// The framework's glass (MBUI_SCREEN=glass; in a browser ?MBUI_SCREEN=glass): bands of colour and words scrolling
// under still.fail's frosted top bar and floating capsule, and liquid glass over them: three discs of one group that
// flow into each other where they are close, a capsule whose words take their ink from what is under it, and a
// bottom bar of frosted glass with its lit rim. MBUI_DARK=1 for the dark theme.

///|
let glass_bands : Array[(Int64, String)] = [
  (0xE5704AFFL, "晨光"),
  (0x1559C4FFL, "深海"),
  (0xF2F0EAFFL, "纸面"),
  (0x2F8F5BFFL, "松林"),
  (0x1B1C1FFFL, "夜色"),
  (0xD9962BFFL, "麦田"),
  (0x8E5CC4FFL, "暮紫"),
  (0xFFFFFFFFL, "雪地"),
]

///|
fn glass_view(c : @ui.Ctx) -> Unit {
  let t = @sf.begin(c)
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
    c.list("bands", 40, 132.0, fn(i) { glass_band(c, i) }) |> ignore
    c.layer(fn() {
      // still.fail's top bar
      c.box(w=Fill(1.0), glass=@sf.glass_bar(), fn() {
        c.box(dir=Row, w=Fill(1.0), h=Px(50.0), padx=16.0, align=ACenter, fn() {
          c.text("玻璃", size=24.0, weight=700, color=t.p.text, wrap=false)
          |> ignore
        })
        |> ignore
        c.box(w=Fill(1.0), h=Px(0.5), bg=t.p.line, fn() {  }) |> ignore
      })
      |> ignore
      c.spacer()
      // liquid: three discs of one group, close enough to merge, over a capsule inked by what is under it
      c.box(dir=Row, w=Fill(1.0), justify=JCenter, gap=8.0, glass_group=true, fn() {
        for icon in ["search", "settings", "more"] {
          c.box(
            w=Px(56.0),
            h=Px(56.0),
            radius=28.0,
            align=ACenter,
            justify=JCenter,
            glass=@ui.Glass::liquid(merge=24.0),
            fn() { @sf.icon(c, icon, size=22.0, color=t.p.text) |> ignore },
          )
          |> ignore
        }
      })
      |> ignore
      c.box(w=Fill(1.0), pt=14.0, align=ACenter, fn() {
        c.box(
          h=Px(48.0),
          padx=22.0,
          radius=24.0,
          align=ACenter,
          justify=JCenter,
          glass=@ui.Glass::liquid(),
          fn() {
            c.text("液态玻璃：字的颜色跟着底下走", size=15.0, weight=600, color=t.p.text, wrap=false)
            |> ignore
          },
        )
        |> ignore
      })
      |> ignore
      // still.fail's floating capsule and its bottom bar's glass, rim lit
      c.box(dir=Row, w=Fill(1.0), padx=16.0, pt=18.0, pb=24.0, gap=12.0, align=ACenter, fn() {
        c.box(
          w=Fill(1.0),
          h=Px(56.0),
          radius=28.0,
          dir=Row,
          align=ACenter,
          justify=JBetween,
          padx=24.0,
          glass=@sf.glass_bottom_bar(),
          shadow=@sf.floating.sigma,
          shadow_color=@sf.floating.color,
          shadow_y=@sf.floating.dy,
          fn() {
            for icon in ["chat", "folder", "user"] {
              @sf.icon(c, icon, size=22.0, color=t.p.text) |> ignore
            }
          },
        )
        |> ignore
        c.box(
          w=Px(56.0),
          h=Px(56.0),
          radius=28.0,
          align=ACenter,
          justify=JCenter,
          glass=@sf.glass_floating(),
          shadow=@sf.floating.sigma,
          shadow_color=@sf.floating.color,
          shadow_y=@sf.floating.dy,
          fn() { @sf.icon(c, "plus", size=22.0, color=t.p.text) |> ignore },
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A band of colour with words in it, and stripes to show what the glass bends.
fn glass_band(c : @ui.Ctx, i : Int) -> Unit {
  let (col, name) = glass_bands[i % glass_bands.length()]
  let light = i % glass_bands.length() == 2 || i % glass_bands.length() == 7
  let ink = if light { 0x24272BFFL } else { 0xFFFFFFFFL }
  c.box(w=Fill(1.0), h=Px(132.0), bg=col, padx=20.0, pt=16.0, gap=10.0, fn() {
    c.text("\{name} · 第 \{i + 1} 段", size=26.0, weight=700, color=ink, wrap=false)
    |> ignore
    c.box(dir=Row, gap=6.0, fn() {
      for k in 0..<12 {
        c.box(
          w=Px(18.0),
          h=Px(54.0),
          radius=3.0,
          bg=@sf.alpha(ink, if k % 2 == 0 { 0.85 } else { 0.25 }),
          fn() {  },
        )
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}
