///|
/// The time of a tape's first frame (its first DRAWHASH line), 0 when it has none.
fn first_frame_time(tape : String) -> Double {
  for v in tape.split("\n") {
    let line = v.to_owned()
    match line.find("DRAWHASH ") {
      Some(i) => {
        let parts = line.view(start_offset=i + 9).split(" ").map(fn(p) { p.to_owned() }).to_array()
        if parts.length() >= 2 {
          match (try Some(@json.parse(parts[1])) catch { _ => None }) {
            Some(Number(d, ..)) => return d
            _ => ()
          }
        }
      }
      None => ()
    }
  }
  0.0
}

///|
/// The controls page's draw list printed when asked (MBUI_DL_PRINT=1: scripts/render_offscreen.sh, render_check.sh):
/// of the run kept on a Mac, or (MBUI_DL_TAPE, a run's log: its text, its input and its frames) of that run, its
/// frames drawn again here, the last one's; and whether each frame here was the run's (DLFRAMES).
test "the controls page's draw list printed when asked (MBUI_DL_PRINT=1: scripts/render_check.sh)" {
  if node_env("MBUI_DL_PRINT") == "1" {
    let path = node_env("MBUI_DL_TAPE")
    let t = if path == "" {
      controls_kept()
    } else {
      let tape = node_read(path)
      let t = @ui.Tester::new(
        fn(c) { gallery(c, "controls") },
        w=960.0,
        h=720.0,
        text=tape,
        scale=1.0,
        time=first_frame_time(tape) - 16.0,
        stable=true,
      )
      let frames = t.replay_frames(tape)
      let apart = frames.filter(fn(f) { f.1 != f.2 }).length()
      println("DLFRAMES \{frames.length()} apart \{apart}")
      t
    }
    println("DLBEGIN")
    println(t.drawlist())
    println("DLEND")
  }
}

///|
/// A box 80 by 40 at (20, 20), rounded 12: cutting a red box that fills it (`cut`), or red itself. Drawn, the two are
/// the same picture to the byte (scripts/render_offscreen.sh, render_check.sh): what a rounded clip cuts covers its
/// corners as the box's own rounded ground does.
fn rounded_clip(cut : Bool) -> @ui.Tester {
  let red = 0xFF3B30FFL
  let t = @ui.Tester::new(
    fn(c) {
      c.box(pad=20.0, align=AStart, fn() {
        if cut {
          c.box(w=Px(80.0), h=Px(40.0), radius=12.0, clip=true, fn() {
            c.box(w=Fill(1.0), h=Fill(1.0), bg=red, fn() { () }) |> ignore
          })
          |> ignore
        } else {
          c.box(w=Px(80.0), h=Px(40.0), radius=12.0, bg=red, fn() { () }) |> ignore
        }
      })
      |> ignore
    },
    w=120.0,
    h=80.0,
    scale=2.0,
  )
  t.draw()
  t
}

///|
test "a rounded clip's draw lists printed when asked (MBUI_DL_PRINT=clip-cut or clip-box: scripts/render_offscreen.sh)" {
  let which = node_env("MBUI_DL_PRINT")
  if which == "clip-cut" || which == "clip-box" {
    println("DLBEGIN")
    println(rounded_clip(which == "clip-cut").drawlist())
    println("DLEND")
  }
}

///|
/// A lightly blurred picture with ink near each straight edge, and a strongly blurred solid picture over red.
/// Both are clipped to rounded rectangles. Their rendered pixels are checked by scripts/chk contained.
fn contained_shown() -> @ui.Tester {
  let t = @ui.Tester::new(
    fn(c) {
      c.box(w=Fill(1.0), h=Fill(1.0), pad=20.0, gap=20.0, bg=0xFF0000FFL, align=AStart, fn() {
        c.box(w=Px(160.0), h=Px(120.0), radius=26.0, clip=true, align=AStart, fn() {
          c.box(w=Fill(1.0), h=Fill(1.0), bg=0xFFFFFFFFL, fn() { () }) |> ignore
          c.layer(fn() {
            c.lines(
              [
                @ui.line([(0.25, 35.0), (0.25, 85.0)], width=0.5, color=0x000000FFL),
                @ui.line([(5.0, 35.0), (5.0, 85.0)], width=4.0, color=0x000000FFL),
                @ui.line([(155.0, 35.0), (155.0, 85.0)], width=4.0, color=0x000000FFL),
                @ui.line([(45.0, 5.0), (115.0, 5.0)], width=4.0, color=0x000000FFL),
                @ui.line([(45.0, 115.0), (115.0, 115.0)], width=4.0, color=0x000000FFL),
              ],
              w=Px(160.0),
              h=Px(120.0),
            ) |> ignore
          }) |> ignore
          c.layer(fn() {
            c.box(w=Fill(1.0), h=Fill(1.0), glass=@ui.Glass::frosted(blur=0.5, tint=0L, solid=0L, contained=true), fn() { () }) |> ignore
          }) |> ignore
        }) |> ignore
        c.box(w=Px(160.0), h=Px(120.0), radius=26.0, clip=true, align=AStart, fn() {
          c.box(w=Fill(1.0), h=Fill(1.0), bg=0x1559C4FFL, fn() { () }) |> ignore
          c.layer(fn() {
            c.box(w=Fill(1.0), h=Fill(1.0), glass=@ui.Glass::frosted(blur=14.0, tint=0L, solid=0L, contained=true), fn() { () }) |> ignore
          }) |> ignore
        }) |> ignore
      }) |> ignore
    },
    w=200.0,
    h=300.0,
    scale=2.0,
  )
  t.draw()
  t
}

///|
test "contained glass's draw list printed when asked" {
  if node_env("MBUI_DL_PRINT") == "contained" {
    println("DLBEGIN")
    println(contained_shown().drawlist())
    println("DLEND")
  }
}

///|
/// A light picture over black, cut by a rounded frame: filling it, letterboxed, or inset between device pixels. The
/// matching references show the same frames: a white fill, a precomposed 160 × 160 picture, or an inset white box.
/// The picture and matte must share their cut to match them.
fn matte_shown(reference : Bool, which : String) -> @ui.Tester {
  let h = if which == "fill" { 40.0 } else { 80.0 }
  let t = @ui.Tester::new(
    fn(c) {
      c.box(pad=20.0, align=AStart, fn() {
        c.box(w=Px(80.0), h=Px(h), radius=12.0, tx=0.125, clip=true,
          bg=if reference && which == "inset" { 0x000000FFL } else { 0L }, fn() {
          if reference && which == "inset" {
            c.box(w=Px(59.5), h=Px(39.5), tx=10.0, ty=20.125, bg=0xFFFFFFFFL, fn() {  }) |> ignore
          } else if reference && which == "fill" {
            // The reference fills beyond the frame; the same clip alone covers its edge, even between pixels.
            c.box(w=Px(82.0), h=Px(42.0), tx= -1.0, ty= -1.0, bg=0xFFFFFFFFL, fn() {  }) |> ignore
          } else if reference {
            // The black and white bands already in these pixels: one frame, one clip, the same geometry as the image
            // under test. At scale 2 its 160 pixels land on the 80-point frame's pixels without resampling. Black
            // behind the opaque picture makes its alpha exactly one even where texture filtering rounds it down.
            c.image("mem:matte-bars", w=Px(80.0), h=Px(h), fit=FitFill, bg=0x000000FFL, fade=false, matte=true) |> ignore
          } else if which == "inset" {
            c.picture("mem:matte-white", x=10.0, y=20.125, w=59.5, h=39.5, bg=0x000000FFL, matte=true) |> ignore
          } else {
            c.image("mem:matte-white", w=Px(80.0), h=Px(h), fit=if which == "contain" { FitContain } else { FitCover },
              bg=0x000000FFL, fade=false, matte=true) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    },
    w=120.0,
    h=120.0,
    scale=2.0,
  )
  // The Tester's byte decoder makes a 4:3 picture; these matching solid-white pixels are what the renderer sees.
  @ui.add_image("mem:matte-white", @codec.from_base64("iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAIAAAA7ljmRAAAADklEQVR4nGP4jwQYcHIAu4cj3ZP55DwAAAAASUVORK5CYII="))
  @ui.add_image("mem:matte-bars", @codec.from_base64("iVBORw0KGgoAAAANSUhEUgAAAKAAAACgCAIAAAAErfB6AAAA4UlEQVR42u3RQREAAAzCMPyb3kzw4hIJbQIAAAAAAAAAAEDNMc1ggzEYgzEYgzEYgw3GYAzGYAzGYAw2GIMxGIMxGIMxGIMNxmAMxmAMxmAMNhiDMRiDMRiDMdhgDMZgDMZgDMZgDDYYgzEYgzEYgzHYYAzGYAzGYAzGYIMlMBiDMRiDMRiDMdhgDMZgDMZgDMZggzEYgzEYgzEYgzHYYAzGYAzGYAzGYIMxGIMxGIMxGIMNxmAMxmAMxmAMxmCDMRiDMRiDMRiDDcZgDMZgDMZgDDaY7cEAAAAAAAAAAADUPDtlLCFksrJqAAAAAElFTkSuQmCC"))
  t.draw()
  t
}

///|
test "a picture and its matte drawn through a rounded frame (scripts/render_dl.sh)" {
  let which = node_env("MBUI_DL_PRINT")
  if which.has_prefix("matte-") {
    let shape = if which.has_prefix("matte-fill") { "fill" } else if which.has_prefix("matte-contain") { "contain" } else { "inset" }
    let t = matte_shown(which.has_suffix("-reference"), shape)
    println("DLBEGIN")
    println(t.drawlist(bytes=true))
    println("DLEND")
  }
}

///|
/// Lines (Ctx::lines, scene.mbt's kind 10) in a window 160 by 160 at scale 2, on white (scripts/chk lines reads its
/// picture): in its top 40 a line from (20, 20) to (100, 20) 8 wide, and 40 under it a box 88 by 8 rounded 4 at (16,
/// 56), the same shape drawn as a rounded rect; under them, in a box from (0, 80), a line from (20, 10) to (60, 50) 6
/// wide, an arc about (120, 40) of radius 20 from 0 through 3π/2 3 wide, and a line from (20, 70) to (140, 70) 4 wide
/// drawn half its length; over them a red box 20 by 20 at (70, 85) turned 30° clockwise about its top left (a look's
/// `rot`).
fn lines_shown() -> @ui.Tester {
  let red = 0xFF3B30FFL
  let blue = 0x1559C4FFL
  let t = @ui.Tester::new(
    fn(c) {
      c.box(w=Fill(1.0), h=Fill(1.0), bg=0xFFFFFFFFL, align=AStart, fn() {
        c.lines([@ui.line([(20.0, 20.0), (100.0, 20.0)], width=8.0, color=red)], w=Px(160.0), h=Px(40.0)) |> ignore
        c.box(w=Px(160.0), h=Px(40.0), pl=16.0, pt=16.0, align=AStart, fn() {
          c.box(w=Px(88.0), h=Px(8.0), radius=4.0, bg=red, fn() { () }) |> ignore
        })
        |> ignore
        c.lines(
          [
            @ui.line([(20.0, 10.0), (60.0, 50.0)], width=6.0, color=blue),
            @ui.line(@ui.arc(120.0, 40.0, 20.0, from=0.0, sweep=3.0 * 3.141592653589793 / 2.0), width=3.0, color=blue),
            @ui.line([(20.0, 70.0), (140.0, 70.0)], width=4.0, color=blue, upto=0.5),
          ],
          w=Px(160.0),
          h=Px(80.0),
        )
        |> ignore
        c.layer(fn() {
          c.box(w=Fill(1.0), h=Fill(1.0), pl=70.0, pt=85.0, align=AStart, fn() {
            let b = c.box(w=Px(20.0), h=Px(20.0), bg=red, fn() { () })
            c.look(b, @ui.look(ox=0.0, oy=0.0, rot=30.0 * 3.141592653589793 / 180.0))
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    w=160.0,
    h=160.0,
    scale=2.0,
  )
  t.draw()
  t
}

///|
/// Shapes (Ctx::shapes, scene.mbt's kind 11) in a window 160 by 160 at scale 2, on white (scripts/chk shapes reads its
/// picture): a red square 60 across at (10, 10) with a hole 20 across in its middle, its outline going back (the
/// nonzero rule); a blue one at (90, 10) with its middle's outline going the same way, filled by the even-odd rule (a
/// hole too); a blue line from (10, 100) to (70, 100) and down to (70, 150), 6 wide; a red disc about (120, 125) of
/// radius 25.
fn shapes_shown() -> @ui.Tester {
  let red = 0xFF3B30FFL
  let blue = 0x1559C4FFL
  let square = fn(x : Double, y : Double, s : Double, back : Bool) -> (Array[Double], Bool) {
    if back {
      ([x, y, x, y + s, x + s, y + s, x + s, y], true)
    } else {
      ([x, y, x + s, y, x + s, y + s, x, y + s], true)
    }
  }
  let disc = []
  for k in 0..<64 {
    let a = k.to_double() * 2.0 * 3.141592653589793 / 64.0
    disc.push(120.0 + 25.0 * @dmath.cos(a))
    disc.push(125.0 + 25.0 * @dmath.sin(a))
  }
  let t = @ui.Tester::new(
    fn(c) {
      c.box(w=Fill(1.0), h=Fill(1.0), bg=0xFFFFFFFFL, align=AStart, fn() {
        c.shapes(
          [
            @ui.shape_of([square(10.0, 10.0, 60.0, false), square(30.0, 30.0, 20.0, true)], fill=red),
            @ui.shape_of([square(90.0, 10.0, 60.0, false), square(110.0, 30.0, 20.0, false)], fill=blue, even_odd=true),
            @ui.shape_of([([10.0, 100.0, 70.0, 100.0, 70.0, 150.0], false)], stroke=blue, width=6.0),
            @ui.shape_of([(disc, true)], fill=red),
          ],
          w=Px(160.0),
          h=Px(160.0),
        )
        |> ignore
      })
      |> ignore
    },
    w=160.0,
    h=160.0,
    scale=2.0,
  )
  t.draw()
  t
}

///|
test "shapes' draw list printed when asked (MBUI_DL_PRINT=shapes: scripts/render_dl.sh)" {
  if node_env("MBUI_DL_PRINT") == "shapes" {
    println("DLBEGIN")
    println(shapes_shown().drawlist())
    println("DLEND")
  }
}

///|
test "shapes cover what they are said to: their insides, not their holes, their strokes as wide as said" {
  let t = shapes_shown()
  assert_eq(t.shape_cover(15.0, 40.0), 1.0)
  assert_eq(t.shape_cover(40.0, 40.0), 0.0)
  assert_eq(t.shape_cover(95.0, 40.0), 1.0)
  assert_eq(t.shape_cover(120.0, 40.0), 0.0)
  assert_eq(t.shape_cover(40.0, 100.0), 1.0)
  assert_eq(t.shape_cover(70.0, 125.0), 1.0)
  assert_eq(t.shape_cover(40.0, 105.0), 0.0)
  assert_eq(t.shape_cover(120.0, 125.0), 1.0)
  assert_eq(t.shape_cover(148.0, 125.0), 0.0)
}

///|
test "lines' draw list printed when asked (MBUI_DL_PRINT=lines: scripts/render_dl.sh)" {
  if node_env("MBUI_DL_PRINT") == "lines" {
    println("DLBEGIN")
    println(lines_shown().drawlist())
    println("DLEND")
  }
}

///|
test "lines are drawn where they are said to be" {
  let t = lines_shown()
  let got = t.drawn_lines()
  assert_eq(got[0], (20.0, 20.0, 100.0, 20.0, 8.0, 0xFF3B30FFL))
  assert_eq(got[1], (20.0, 90.0, 60.0, 130.0, 6.0, 0x1559C4FFL))
  // the half line last: from (20, 150) to (80, 150)
  assert_eq(got[got.length() - 1], (20.0, 150.0, 80.0, 150.0, 4.0, 0x1559C4FFL))
}

///|
/// A screen of the window's tree in which only a spinner moves (docs/partial-redraw.md), in a window 240 by 200 at scale
/// 2: under a bar of frosted glass whose capture its turn reaches, a box turned with it, a card with a shadow, shapes,
/// and far from it a dot whose colour changes with it. At the spinner's first moment; `second`: then turned on to its
/// second, its scene saying where the window changed (Tester::drawlist's `parts`). The second drawn over the first only
/// there is the second drawn whole, to the byte (mbui-render MBUI_DL_FROM: scripts/render_offscreen.sh, render_check.sh).
fn partial_shown(second : Bool) -> @ui.Tester {
  let red = 0xFF3B30FFL
  let blue = 0x1559C4FFL
  let pi = 3.141592653589793
  let phase = @signals.signal(0.1)
  let t = @ui.Tester::new(fn(_) {  }, w=240.0, h=200.0, scale=2.0)
  @ui.set_view_app(fn(root) {
    root.ground(Is(0xF2F2F2FFL)) |> ignore
    root.box(fn(bar) {
      bar.row(Is(true)).height(Is(Some(36.0))) |> ignore
      bar.box(fn(b) { b.width(Is(Some(60.0))).height(Is(Some(36.0))).ground(Is(red)) |> ignore }) |> ignore
      bar.box(fn(b) { b.width(Is(Some(60.0))).height(Is(Some(36.0))).ground(Is(blue)) |> ignore }) |> ignore
    })
    |> ignore
    root.box(fn(r) {
      r.row(Is(true)).padding(Is((16.0, 8.0, 0.0, 0.0))).gap(Is(16.0)) |> ignore
      r.box(fn(s) {
        s
        .width(Is(Some(24.0)))
        .height(Is(Some(24.0)))
        .lines(By(fn() {
          [
            @paint.line(@paint.arc(12.0, 12.0, 10.0, from=0.0, sweep=2.0 * pi), width=3.0, color=0x1559C433L),
            @paint.line(@paint.arc(12.0, 12.0, 10.0, from=phase.get() * 2.0 * pi, sweep=0.6 * pi), width=3.0, color=blue),
          ]
        }))
        |> ignore
      })
      |> ignore
      r.box(fn(b) {
        b
        .width(Is(Some(16.0)))
        .height(Is(Some(16.0)))
        .radius(Is(3.0))
        .ground(Is(red))
        .turn(By(fn() { phase.get() * 2.0 * pi }))
        |> ignore
      })
      |> ignore
    })
    |> ignore
    root.box(fn(c) {
      c.padding(Is((16.0, 16.0, 0.0, 0.0))) |> ignore
      c.box(fn(card) {
        card.width(Is(Some(120.0))).height(Is(Some(40.0))).radius(Is(8.0)).ground(Is(0xFFFFFFFFL)).shadow(Is((6.0, 0.0, 0x00000040L)))
        |> ignore
      })
      |> ignore
    })
    |> ignore
    root.box(fn(sh) {
      sh
      .width(Is(Some(160.0)))
      .height(Is(Some(50.0)))
      .shapes(Is([
        @paint.shape_of([([20.0, 10.0, 60.0, 10.0, 40.0, 40.0], true)], fill=red),
        @paint.shape_of([([80.0, 10.0, 120.0, 40.0], false)], stroke=blue, width=4.0),
      ]))
      |> ignore
    })
    |> ignore
    // (a dot far from it, its colour with the turn: a part of its own)
    root.box(fn(d) {
      d
      .over(Is(true))
      .offset(Is((210.0, 176.0)))
      .width(Is(Some(12.0)))
      .height(Is(Some(12.0)))
      .radius(Is(6.0))
      .ground(By(fn() { if phase.get() < 0.25 { red } else { blue } }))
      |> ignore
    })
    |> ignore
    root.box(fn(g) {
      g
      .over(Is(true))
      .height(Is(Some(36.0)))
      .glass(Is(Some(@paint.Glass::frosted(blur=8.0, tint=0xFFFFFF80L, solid=0xFFFFFFFFL))))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  if second {
    phase.set(0.35)
    t.draw()
  }
  t
}

///|
test "a spinner's two moments' draw lists printed when asked (MBUI_DL_PRINT=partial-a or partial-b: scripts/render_offscreen.sh)" {
  let which = node_env("MBUI_DL_PRINT")
  if which == "partial-a" || which == "partial-b" {
    println("DLBEGIN")
    println(partial_shown(which == "partial-b").drawlist(parts=which == "partial-b"))
    println("DLEND")
  }
}
