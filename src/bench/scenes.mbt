// The scenes of nanoui's hill-climb (github.com/justrach/nanoui,
// hillclimb/src/scenes.zig, MIT), built with mbui: the same counts, sizes
// and styles, and the same change every frame, as an animation would make,
// so every frame does all its work.

///|
struct State {
  mut frame : Int
  // seconds
  mut time : Double
}

///|
let state : State = { frame: 0, time: 0.0 }

///|
let scene_names : Array[String] = ["boxes", "text", "scroll", "list", "dashboard"]

///|
fn scene_view(name : String) -> (@ui.Ctx) -> Unit {
  match name {
    "boxes" => boxes
    "text" => text
    "scroll" => scroll
    "list" => list
    "glass" => glass_scene
    "glass-solid" => glass_solid_scene
    "liquid" => liquid_scene
    "liquid-flat" => liquid_flat_scene
    _ => dashboard
  }
}

///|
/// 600 rounded, shadowed boxes moving and changing color.
fn boxes(c : @ui.Ctx) -> Unit {
  let t = state.time
  c.column(w=Fill(1.0), h=Fill(1.0), pad=10.0, gap=4.0, fn() {
    for r in 0..<20 {
      c.row(gap=4.0, fn() {
        for col in 0..<30 {
          let i = (r * 30 + col).to_double()
          c.box(
            w=Px(24.0),
            h=Px(24.0),
            radius=6.0,
            bg=hsl(fmod(t * 60.0 + i * 3.0, 360.0)),
            shadow=4.0,
            shadow_color=0x00000033L,
            shadow_y=2.0,
            ty=6.0 * @dmath.sin(t * 3.0 + i * 0.1),
            fn() {  },
          )
          |> ignore
        }
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// 300 labels whose numbers change every frame.
fn text(c : @ui.Ctx) -> Unit {
  c.column(w=Fill(1.0), h=Fill(1.0), pad=10.0, gap=6.0, fn() {
    for r in 0..<15 {
      c.row(gap=4.0, fn() {
        for col in 0..<20 {
          let i = r * 20 + col
          c.column(w=Px(40.0), fn() {
            c.text("\{(state.frame * 7 + i * 13) % 10000}", size=13.0) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    }
  })
  |> ignore
}

///|
fn list_row(c : @ui.Ctx, i : Int) -> Unit {
  c.row(w=Fill(1.0), h=Px(28.0), padx=12.0, gap=8.0, align=ACenter, fn() {
    c.text("Row \{i} — a line of a long list", size=13.0) |> ignore
    c.spacer()
    c.text("\{i * 7 % 100}", size=12.0) |> ignore
  })
  |> ignore
}

///|
/// A plain column of 1000 rows, clipped, moving every frame.
fn scroll(c : @ui.Ctx) -> Unit {
  let row_h = 28.0
  let rows = 1000
  let offset = fmod(state.time * 600.0, row_h * rows.to_double() - 640.0)
  c.box(w=Fill(1.0), h=Fill(1.0), clip=true, fn() {
    c.box(w=Fill(1.0), ty=-offset, fn() {
      for i in 0..<rows {
        list_row(c, i)
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A virtual list of 100 000 rows, scrolled to another row each frame.
fn list(c : @ui.Ctx) -> Unit {
  let rows = 100000
  c.list_scroll_to("list", state.frame * 3 % (rows - 40))
  c.list("list", rows, 28.0, fn(i) { list_row(c, i) }) |> ignore
}

///|
/// 12 cards of text, a large number and a progress bar.
fn dashboard(c : @ui.Ctx) -> Unit {
  let t = state.time
  c.column(w=Fill(1.0), h=Fill(1.0), pad=16.0, gap=12.0, fn() {
    for r in 0..<3 {
      c.row(gap=12.0, fn() {
        for col in 0..<4 {
          let i = r * 4 + col
          let v = 0.5 + 0.5 * @dmath.sin(t * 2.0 + i.to_double())
          c.box(
            w=Px(200.0),
            pad=14.0,
            gap=8.0,
            radius=12.0,
            bg=0xFFFFFFFFL,
            shadow=16.0,
            shadow_color=0x0000001FL,
            shadow_y=4.0,
            fn() {
              c.text("Metric \{i}", size=13.0) |> ignore
              c.text("\{(v * 1000.0).to_int()}", size=28.0, weight=700)
              |> ignore
              c.row(w=Px(172.0), h=Px(6.0), radius=3.0, bg=0xE0E0E5FFL, fn() {
                c.box(
                  w=Px(172.0 * v),
                  h=Px(6.0),
                  radius=3.0,
                  bg=0x0A84FFFFL,
                  fn() {  },
                )
                |> ignore
              })
              |> ignore
              c.text("updated \{state.frame % 60}s ago", size=11.0) |> ignore
            },
          )
          |> ignore
        }
      })
      |> ignore
    }
  })
  |> ignore
}

///|
fn fmod(x : Double, m : Double) -> Double {
  x - (x / m).floor() * m
}

///|
/// nanoui's hsl: saturation 0.7, lightness 0.55; as 0xRRGGBBAA.
fn hsl(h : Double) -> Int64 {
  let s = 0.7
  let l = 0.55
  let f = fn(n : Double) -> Double {
    let k = fmod(n + h / 30.0, 12.0)
    let a = s * (if l < 1.0 - l { l } else { 1.0 - l })
    let m = if k - 3.0 < 9.0 - k { k - 3.0 } else { 9.0 - k }
    let m = if m > 1.0 { 1.0 } else if m < -1.0 { -1.0 } else { m }
    l - a * m
  }
  let byte = fn(v : Double) -> Int64 { (v * 255.0).round().to_int().to_int64() }
  (byte(f(0.0)) << 24) | (byte(f(8.0)) << 16) | (byte(f(4.0)) << 8) | 0xFFL
}
