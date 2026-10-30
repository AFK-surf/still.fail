// Layouts kept from frame to frame (Ctx::flex_tree, Ctx::commit, the flex
// engine's reuse) against layouts made from nothing: each scenario runs
// twice, once as frames run, once with every frame laid out afresh
// (layout_reuse off), and every frame of the two must come out the same to
// the bit: the tree's rectangles and texts, everything drawn, the hit
// targets.

///|
fn snap_node(sb : StringBuilder, c : Ctx, i : Int, depth : Int) -> Unit {
  let n = c.nodes[i]
  sb.write_string("\{depth} k\{n.kind} \{n.x} \{n.y} \{n.fw} \{n.fh}")
  if n.kind == kind_text {
    match n.tl {
      Some(tl) =>
        sb.write_string(" \{tl.text.escape()} \{tl.line_start.length()} \{tl.w}")
      None => sb.write_string(" -")
    }
  }
  if n.kind == kind_rich {
    match n.rl {
      Some(rl) => sb.write_string(" \{rl.text.escape()} \{rl.line_start.length()} \{rl.w}")
      None => sb.write_string(" -")
    }
  }
  if n.kind == kind_editor {
    match c.editors.get(n.id) {
      Some(st) => sb.write_string(" \{st.display().escape()} \{st.ox} \{st.oy}")
      None => ()
    }
  }
  sb.write_char('\n')
  let mut ch = n.first
  while ch >= 0 {
    snap_node(sb, c, ch, depth + 1)
    ch = c.nodes[ch].next
  }
}

///|
/// The last frame, in full.
fn snap(c : Ctx) -> String {
  let sb = StringBuilder()
  snap_node(sb, c, 0, 0)
  for k in 0..<c.ninst {
    let b = k * inst_size
    for j in 0..<21 {
      sb.write_string("\{c.inst[b + j]} ")
    }
    sb.write_char('\n')
  }
  // (the ids differ from run to run: pages are numbered as they come)
  sb.write_string("hits \{c.hit_ids.length()} \{c.hit_rects}\n")
  sb.write_string("scrolls \{c.scroll_ids.length()} \{c.scroll_rects}\n")
  sb.to_string()
}

///|
/// Runs `scenario` (which makes its own state and Tester) with layouts
/// kept and with layouts made afresh, and compares them frame by frame.
/// Returns the frames compared.
fn same_both_ways(name : String, scenario : () -> Unit) -> Int raise {
  let frames : Array[Array[String]] = [[], []]
  for pass in 0..<2 {
    layout_reuse.val = pass == 0
    let out = frames[pass]
    frame_hook.val = Some(fn() { out.push(snap(g())) })
    scenario()
    frame_hook.val = None
  }
  layout_reuse.val = true
  let a = frames[0]
  let b = frames[1]
  if a.length() != b.length() {
    fail("\{name}: \{a.length()} frames kept, \{b.length()} afresh")
  }
  for k in 0..<a.length() {
    if a[k] != b[k] {
      let la = a[k].split("\n").collect()
      let lb = b[k].split("\n").collect()
      let mut j = 0
      while j < la.length() && j < lb.length() && la[j] == lb[j] {
        j = j + 1
      }
      let ka = if j < la.length() { la[j].to_string() } else { "(end)" }
      let kb = if j < lb.length() { lb[j].to_string() } else { "(end)" }
      fail("\{name}: frame \{k} line \{j}: kept \{ka}, afresh \{kb}")
    }
  }
  a.length()
}

///|
test "kept layouts: styles changing (padding, sizes, gaps, alignment, colours only)" {
  let n = same_both_ways("styles", fn() {
    let step = Ref::new(0)
    let t = Tester::new(
      fn(c) {
        let s = step.val
        c.column(pad=if s % 3 == 1 { 12.0 } else { 8.0 }, gap=(s % 4).to_double(), fn() {
          c.row(
            gap=4.0,
            align=if s % 2 == 0 { ACenter } else { AStart },
            justify=if s >= 5 { JBetween } else { JStart },
            fn() {
              c.box(w=Px(if s == 2 { 50.0 } else { 30.0 }), h=Px(20.0), bg=0xFF0000FFL, fn() {  })
              |> ignore
              c.text("label beside", wrap=false) |> ignore
              c.box(w=Fill(1.0), h=Px(10.0), bg=if s % 2 == 0 { 0x00FF00FFL } else { 0x0000FFFFL }, fn() {  })
              |> ignore
            },
          )
          |> ignore
          c.box(
            min_h=if s == 3 { 40.0 } else { 0.0 },
            max_w=if s == 4 { 100.0 } else { 1.0e9 },
            pad=4.0,
            bg=0xEEEEEEFFL,
            fn() { c.text("a paragraph that wraps when its box is narrow enough") |> ignore },
          )
          |> ignore
          c.text("below") |> ignore
        })
        |> ignore
      },
      w=300.0,
      h=400.0,
    )
    for s in 0..<8 {
      step.val = s
      // drawn, and drawn again with nothing changed (what was kept, kept)
      t.draw()
      t.draw()
    }
  })
  assert_true(n > 10)
}

///|
/// One property of one node changed at a time, and back (nothing else
/// changing with it), for each that layout reads.
test "kept layouts: each style property changed alone" {
  same_both_ways("one property", fn() {
    let step = Ref::new(0)
    let t = Tester::new(
      fn(c) {
        let k = step.val
        let at = fn(n : Int) { k == n }
        c.column(w=Fill(1.0), h=Fill(1.0), fn() {
          c.text("before") |> ignore
          c.row(gap=4.0, fn() {
            c.box(
              dir=if at(1) { Row } else { Column },
              w=if at(2) { Px(80.0) } else if at(3) { Fill(1.0) } else { Auto },
              h=if at(4) { Px(50.0) } else if at(5) { Fill(1.0) } else { Auto },
              pl=if at(6) { 9.0 } else { 0.0 },
              pr=if at(7) { 9.0 } else { 0.0 },
              pt=if at(8) { 9.0 } else { 0.0 },
              pb=if at(9) { 9.0 } else { 0.0 },
              gap=if at(10) { 7.0 } else { 0.0 },
              align=if at(11) { AEnd } else if at(12) { ACenter } else { AStretch },
              justify=if at(13) { JCenter } else if at(14) { JEnd } else { JStart },
              min_w=if at(15) { 120.0 } else { 0.0 },
              max_w=if at(16) { 30.0 } else { 1.0e9 },
              min_h=if at(17) { 70.0 } else { 0.0 },
              max_h=if at(18) { 12.0 } else { 1.0e9 },
              bg=0xDDDDDDFFL,
              fn() {
                c.text("one") |> ignore
                c.text("two words") |> ignore
              },
            )
            |> ignore
            c.box(w=if at(19) { Fill(2.0) } else { Fill(1.0) }, h=Px(20.0), bg=0xAA0000FFL, fn() {  })
            |> ignore
            // grows too, beside it
            c.box(w=Fill(1.0), h=Px(20.0), bg=0xAAAA00FFL, fn() {  }) |> ignore
            // grows from nothing, or is as wide as it is (basis 0 or auto)
            c.box(w=if at(20) { Fill(0.0) } else { Auto }, h=Px(20.0), bg=0x00AA00FFL, fn() {
              c.box(w=Px(15.0), h=Px(5.0), fn() {  }) |> ignore
            })
            |> ignore
          })
          |> ignore
          // room to put its words in: at its top, middle or bottom
          c.column(h=Px(40.0), justify=if at(29) { JEnd } else { JStart }, fn() {
            c.text("down") |> ignore
          })
          |> ignore
          c.column(align=ACenter, fn() {
            // stretched across a centring column, or as wide as it is
            c.box(w=if at(21) { Fill(1.0) } else { Auto }, h=Px(10.0), bg=0x222222FFL, fn() {
              c.box(w=Px(15.0), h=Px(5.0), fn() {  }) |> ignore
            })
            |> ignore
          })
          |> ignore
          let l = c.box(
            w=Px(60.0),
            h=if at(23) { Auto } else { Px(20.0) },
            bg=0x0000AAFFL,
            fn() {  },
          )
          if at(22) || at(23) {
            // laid over the column (its whole height when it says none)
            c.nodes[l].layer = true
          }
          c.text(
            "after, a few words",
            wrap=!at(24),
            w=if at(25) { Px(40.0) } else { Auto },
            weight=if at(26) { 700 } else { 400 },
            line=if at(27) { 30.0 } else { 0.0 },
          )
          |> ignore
          // a text or a list, sized the same way: only the kind differs
          if at(28) {
            c.list("k", 3, 10.0, fn(i) { c.text("item \{i}") |> ignore }, w=Auto, h=Auto)
            |> ignore
          } else {
            c.text("kind") |> ignore
          }
        })
        |> ignore
      },
      w=300.0,
      h=400.0,
    )
    // bold is wider here
    t.bold_wider(0.1)
    // each alone from none, and back; a layer's height said, then not
    let steps = [
      1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 7, 0, 8, 0, 9, 0, 10, 0, 11, 0, 12, 0,
      13, 0, 14, 0, 15, 0, 16, 0, 17, 0, 18, 0, 19, 0, 20, 0, 21, 0, 22, 23, 22,
      0, 24, 0, 25, 0, 26, 0, 27, 0, 28, 0, 29, 0,
    ]
    for k in steps {
      step.val = k
      t.frame()
      t.frame()
    }
  })
  |> ignore
}

///|
test "kept layouts: a text cut to fit, its box narrower and wider" {
  same_both_ways("cut", fn() {
    let w = Ref::new(120.0)
    let t = Tester::new(
      fn(c) {
        c.column(fn() {
          c.box(w=Px(w.val), fn() {
            c.text("a title far too long to fit on its line", wrap=false) |> ignore
          })
          |> ignore
        })
        |> ignore
      },
      w=300.0,
      h=200.0,
    )
    for x in [100.0, 100.0, 140.0, 90.0, 400.0, 120.0] {
      w.val = x
      t.frame()
    }
  })
  |> ignore
}

///|
test "kept layouts: a box moving into the row before it, the same as it was" {
  same_both_ways("into the row", fn() {
    let inside = Ref::new(false)
    let t = Tester::new(
      fn(c) {
        // (of a fixed height: the row's containing block stays the same)
        c.column(align=AStart, h=Px(100.0), fn() {
          c.row(bg=0xEEEEEEFFL, fn() {
            c.box(w=Px(20.0), h=Px(20.0), bg=0xFF0000FFL, fn() {  }) |> ignore
            if inside.val {
              c.box(w=Px(20.0), h=Px(20.0), bg=0xFF0000FFL, fn() {  }) |> ignore
            }
          })
          |> ignore
          if !inside.val {
            c.box(w=Px(20.0), h=Px(20.0), bg=0xFF0000FFL, fn() {  }) |> ignore
          }
        })
        |> ignore
      },
      w=300.0,
      h=200.0,
    )
    for v in [true, true, false, true] {
      inside.val = v
      t.frame()
    }
  })
  |> ignore
}

///|
/// What a slot held last frame is gone when it holds something else: a
/// coloured, padded box then a spacer, a pager then a plain box.
test "kept layouts: a slot holding another kind of thing" {
  same_both_ways("slot reused", fn() {
    let flip = Ref::new(false)
    let t = Tester::new(
      fn(c) {
        c.column(w=Fill(1.0), h=Fill(1.0), fn() {
          c.row(h=Px(30.0), fn() {
            if flip.val {
              c.spacer()
            } else {
              c.box(w=Px(50.0), pad=5.0, bg=0x336699FFL, radius=4.0, fn() {  }) |> ignore
            }
            c.text("right", wrap=false) |> ignore
          })
          |> ignore
          if flip.val {
            c.box(w=Fill(1.0), h=Fill(1.0), fn() {  }) |> ignore
          } else {
            c.pager("p", 3, 0, fn(k) { c.text("page \{k}") |> ignore }) |> ignore
          }
        })
        |> ignore
      },
      w=300.0,
      h=300.0,
    )
    for v in [true, false, true, true] {
      flip.val = v
      t.frame()
    }
  })
  |> ignore
}

///|
test "kept layouts: texts changing (words, size, weight, wrapping, cut to fit)" {
  same_both_ways("texts", fn() {
    let step = Ref::new(0)
    let t = Tester::new(
      fn(c) {
        let s = step.val
        c.column(w=Px(if s == 6 { 260.0 } else { 160.0 }), fn() {
          c.text(if s % 2 == 0 { "short" } else { "now much longer, it wraps onto more lines" }) |> ignore
          c.text("sized", size=if s == 3 { 22.0 } else { 15.0 }, weight=if s == 4 { 700 } else { 400 })
          |> ignore
          c.text("one line that is too long to fit in the column, cut", wrap=s != 5) |> ignore
          c.row(fn() {
            c.text("left \{s}", wrap=false) |> ignore
            c.spacer()
            c.text("\{s * 37}", wrap=false) |> ignore
          })
          |> ignore
          c.text("last")
          |> ignore
        })
        |> ignore
      },
      w=300.0,
      h=400.0,
    )
    for s in 0..<8 {
      step.val = s
      // drawn, and drawn again with nothing changed (what was kept, kept)
      t.draw()
      t.draw()
    }
  })
  |> ignore
}

///|
test "kept layouts: children added, removed, reordered, of another kind" {
  same_both_ways("children", fn() {
    let items : Array[Int] = [1, 2, 3]
    let t = Tester::new(
      fn(c) {
        c.column(gap=2.0, fn() {
          c.text("head") |> ignore
          // the last children of a row come and go, nothing after them
          c.row(fn() {
            for i in items {
              c.box(w=Px(10.0), h=Px(i.to_double() + 2.0), bg=0x445566FFL, fn() {  }) |> ignore
            }
          })
          |> ignore
          for i in items {
            if i % 5 == 0 {
              c.box(h=Px(i.to_double()), bg=0x336699FFL, fn() {  }) |> ignore
            } else {
              c.row(pad=2.0, fn() {
                c.text("item \{i}") |> ignore
                c.spacer()
                c.text("\{i * i}") |> ignore
              })
              |> ignore
            }
          }
          c.text("tail") |> ignore
        })
        |> ignore
      },
      w=240.0,
      h=400.0,
    )
    let steps : Array[() -> Unit] = [
      fn() { items.push(4) },
      fn() { items.insert(0, 0) },
      fn() { items.remove(2) |> ignore },
      fn() { items.rev_in_place() },
      fn() { items[1] = 5 },
      fn() { items[1] = 6 },
      fn() { items.clear() },
      fn() { items.push(7) },
    ]
    for f in steps {
      f()
      t.frame()
      t.frame()
    }
  })
  |> ignore
}

///|
test "kept layouts: the window resized" {
  same_both_ways("resize", fn() {
    let t = Tester::new(
      fn(c) {
        c.column(w=Fill(1.0), h=Fill(1.0), pad=10.0, fn() {
          c.row(gap=8.0, fn() {
            c.box(w=Fill(1.0), h=Px(30.0), bg=0xFF0000FFL, fn() {  }) |> ignore
            c.box(w=Fill(2.0), h=Px(30.0), bg=0x00FF00FFL, fn() {  }) |> ignore
          })
          |> ignore
          c.text("words that wrap differently as the window gets narrower and wider")
          |> ignore
          // a list's rows are computes of their own, made while it is
          // placed: what comes after it was laid out in the one before
          c.list("l", 20, 20.0, fn(i) { c.text("row \{i}") |> ignore }, h=Px(60.0))
          |> ignore
          c.text("after the list, words that wrap differently too as it all gets narrower")
          |> ignore
          c.spacer()
          c.text("bottom", wrap=false) |> ignore
        })
        |> ignore
      },
      w=300.0,
      h=300.0,
    )
    t.resize(200.0, 300.0)
    t.frame()
    t.resize(200.0, 500.0)
    t.resize(420.0, 260.0)
    t.frame()
  })
  |> ignore
}

///|
test "kept layouts: a column moved under a clip (the scroll scene), and lists scrolled" {
  same_both_ways("scroll", fn() {
    let off = Ref::new(0.0)
    let t = Tester::new(
      fn(c) {
        c.column(w=Fill(1.0), h=Fill(1.0), fn() {
          c.box(w=Fill(1.0), h=Px(200.0), clip=true, fn() {
            c.box(w=Fill(1.0), ty=-off.val, fn() {
              for i in 0..<40 {
                c.row(h=Px(28.0), padx=12.0, fn() {
                  c.text("Row \{i}", size=13.0) |> ignore
                  c.spacer()
                  c.text("\{i * 7 % 100}", size=12.0) |> ignore
                })
                |> ignore
              }
            })
            |> ignore
          })
          |> ignore
          c.list("rows", 300, 30.0, fn(i) {
            c.text(if i % 3 == 0 { "row \{i}, a longer one that wraps in the list" } else { "row \{i}" })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      },
      w=300.0,
      h=600.0,
    )
    for k in 0..<12 {
      off.val = k.to_double() * 13.5
      t.draw()
    }
    // and still: nothing moves
    t.frame()
    t.frame()
    t.wheel(150.0, 400.0, 120.0)
    t.drag(150.0, 500.0, 150.0, 300.0)
    t.draw()
    t.wheel(150.0, 400.0, -60.0)
  })
  |> ignore
}

///|
test "kept layouts: animations (springs moving boxes, widths, opacity)" {
  same_both_ways("animation", fn() {
    let target = Ref::new(0.0)
    let t = Tester::new(
      fn(c) {
        let x = c.spring("x", target.val)
        c.column(pad=10.0, gap=6.0, fn() {
          c.box(tx=x, w=Px(40.0), h=Px(40.0), bg=0xFF0000FFL, fn() {
            c.text("in", wrap=false) |> ignore
          })
          |> ignore
          c.box(w=Px(40.0 + x / 2.0), h=Px(20.0), bg=0x00FF00FFL, fn() {  }) |> ignore
          c.box(opacity=dclamp(x / 100.0, 0.0, 1.0), fn() { c.text("fading") |> ignore })
          |> ignore
          c.row(fn() {
            c.box(ty=x / 10.0, fn() {
              c.box(tx=-x / 5.0, fn() { c.text("nested moves") |> ignore }) |> ignore
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      },
      w=300.0,
      h=300.0,
    )
    target.val = 100.0
    t.draw()
    target.val = 20.0
    t.draw()
    // every frame of its way, to its own rest
    t.run_for(t.rest_of("\"x\"") - t.time())
  })
  |> ignore
}

///|
test "kept layouts: only something deep inside moving, nothing around it" {
  same_both_ways("deep move", fn() {
    let k = Ref::new(0)
    let t = Tester::new(
      fn(c) {
        c.column(pad=10.0, fn() {
          c.text("still") |> ignore
          c.row(fn() {
            c.box(fn() {
              // the offset down every other step, the one across every step
              c.box(ty=(k.val / 2).to_double() * 3.0, tx=-k.val.to_double(), fn() {
                c.text("moving") |> ignore
              })
              |> ignore
            })
            |> ignore
            c.box(fn() {
              let b = c.box(w=Px(30.0), h=Px(10.0), bg=0x123456FFL, fn() {  })
              let half = k.val % 2 != 0
              c.moved_by(b, fn(w, _) { (if half { w * 0.5 } else { 0.0 }, 0.0) })
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      },
      w=300.0,
      h=300.0,
    )
    for i in 0..<6 {
      k.val = i
      // drawn, and drawn again with nothing changed (what was kept, kept)
      t.draw()
      t.draw()
    }
  })
  |> ignore
}

///|
test "kept layouts: rich text changing (words, styles, colours only)" {
  same_both_ways("rich", fn() {
    let step = Ref::new(0)
    let t = Tester::new(
      fn(c) {
        let s = step.val
        c.column(w=Px(200.0), gap=4.0, fn() {
          c.rich([
            plain("some words, "),
            if s % 2 == 0 { bold("bold ones") } else { italic("slanted ones, longer") },
            plain(" and "),
            code("code"),
          ])
          |> ignore
          c.rich([plain("the same every frame, long enough to wrap in two lines")], color=if s % 2 == 0 {
            0x000000FFL
          } else {
            0x333333FFL
          })
          |> ignore
          c.rich([link("a link", "https://example.com"), plain(" \{s}")]) |> ignore
          c.text("under") |> ignore
        })
        |> ignore
      },
      w=300.0,
      h=300.0,
    )
    for s in 0..<6 {
      step.val = s
      // drawn, and drawn again with nothing changed (what was kept, kept)
      t.draw()
      t.draw()
    }
  })
  |> ignore
}

///|
test "kept layouts: an editor typed in, growing and pushing what is under it" {
  same_both_ways("editor", fn() {
    let t = Tester::new(
      fn(c) {
        c.column(w=Fill(1.0), h=Fill(1.0), fn() {
          c.text("above") |> ignore
          c.editor("e", placeholder="type", enter_sends=false) |> ignore
          c.text("under the field") |> ignore
          c.spacer()
        })
        |> ignore
      },
      w=240.0,
      h=400.0,
    )
    t.tap_text("type")
    t.type_text("hello")
    t.type_text(" and more words until the line wraps over")
    t.enter()
    t.type_text("a third line")
    t.compose("ni")
    t.type_text("你")
    t.backspace()
    t.frame()
  })
  |> ignore
}

///|
test "kept layouts: pages pushed and popped, mid-slide" {
  same_both_ways("nav", fn() {
    let nav = Nav::new(0)
    let t = Tester::new(fn(c) {
      c.nav(
        nav,
        fn(i) {
          c.column(w=Fill(1.0), h=Fill(1.0), fn() {
            c.text("title \{i}", wrap=false) |> ignore
            if c.button("open \{i + 1}") {
              nav.push(i + 1)
            }
            c.list("rows", 50, 30.0, fn(r) { c.text("row \{r} of \{i}") |> ignore }) |> ignore
          })
          |> ignore
        },
        bg=0xFFFFFFFFL,
      )
      |> ignore
    })
    t.tap_text("open 1")
    nav.push(2)
    // mid-slide: half its push
    t.draw()
    t.run_for(move_ms(390.0) / 2.0)
    nav.pop() |> ignore
    t.draw()
    t.run_for(move_ms(390.0) / 2.0)
    t.back_gesture(150.0, false)
    t.draw()
    t.back_gesture(300.0, true)
    t.draw()
  })
  |> ignore
}

///|
test "kept layouts: a pager dragged and turned, images arriving" {
  same_both_ways("pager", fn() {
    let t = Tester::new(
      fn(c) {
        c.column(w=Fill(1.0), h=Fill(1.0), fn() {
          c.image("a.png", w=Px(100.0)) |> ignore
          c.pager("p", 5, 0, fn(k) {
            c.column(pad=10.0, fn() { c.text("page \{k}") |> ignore }) |> ignore
          })
          |> ignore
        })
        |> ignore
      },
      w=300.0,
      h=500.0,
      images=[("a.png", 400, 200)],
    )
    t.draw()
    t.drag(250.0, 300.0, 120.0, 300.0)
    t.draw()
    t.drag(100.0, 300.0, 140.0, 300.0)
    t.draw()
  })
  |> ignore
}

///|
test "kept layouts: nothing that did not change is laid out again" {
  let tick = Ref::new(0)
  let t = Tester::new(
    fn(c) {
      c.column(w=Fill(1.0), h=Fill(1.0), fn() {
        for i in 0..<30 {
          c.row(pad=4.0, fn() {
            c.text("row \{i}") |> ignore
            c.spacer()
            c.text(if i == 7 { "\{tick.val}" } else { "same" }) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    },
    w=300.0,
    h=900.0,
  )
  t.frame()
  // still: no node sized, none placed, the whole left where it was
  let before = @flex.counters[0]
  let placed = commit_counts[0]
  let kept = commit_counts[2]
  t.frame()
  t.frame()
  assert_eq(@flex.counters[0], before)
  assert_eq(commit_counts[0], placed)
  assert_eq(commit_counts[2], kept + 2)
  // one label changes: its row, the column and the root, not the others
  tick.val = 1
  let before2 = @flex.counters[0]
  let placed2 = commit_counts[0]
  t.frame()
  let sized = @flex.counters[0] - before2
  assert_true(sized > 0 && sized < 20)
  // placed again: the root, the column, that row and the label; the rest
  // left where it was
  assert_eq(commit_counts[0] - placed2, 4)
}

///|
/// The list's sums (the scroll bar's place and length) against the rows'
/// heights added up one by one, as rows are measured, added and moved.
test "a list's running sums are its rows' heights added up" {
  let st : ListState = {
    anchor: 0,
    anchor_off: 0.0,
    heights: [],
    learned: 0,
    heights_learned: @signals.signal(0),
    hand_said: @signals.signal(0),
    moving_said: @signals.signal(false),
    sums: [],
    est: 30.0,
    count: 0,
    vp_h: 600.0,
    vel: 0.0,
    at_end: false,
    stick_end: false,
    last_scroll: 0.0,
    pending: 0.0,
    row: fn(_i) {  },
    seed: 0,
    bones: 0L,
    vis_first: -1,
    vis_last: -1,
    owner: 0,
    below: 0.0,
    glide: false,
    glide_t0: 0.0,
    glide_l0: 0.0,
    glide_rest: -1.0,
    glide_left: 0.0,
    glide_meant: -1.0,
    follow_item: -1,
    follow_margin: 0.0,
    built: -1,
    stepped: -1,
    fresh: true,
    rows_read: false,
    glide_shows: false,
    bar: Bar::new(),
    laid: -1,
    pinned_by: 0.0,
    began: (0, 0.0, 0.0, false, false),
    left: (0, 0.0, 0.0, false, false),
    glide_began: (0.0, 0.0, -1.0, 0.0, -1.0),
    scroll_asked: (-1, 0, 0.0),
    fling: 0,
    fling_v: 0.0,
    fling_t0: -1.0,
    fling_dist: 0.0,
    fling_dur: 0.0,
    fling_done: 0.0,
    drag_pending: 0.0,
    held: false,
    over: 0.0,
    over_edge: 0,
    over_state: 0,
    over_v: 0.0,
    back: BackPath::new(),
        ease: 0.0,
        ease_v: 0.0,
        ease_t0: 0.0,
        ease_done: 0.0,
        ease_mover: Mover::new(),
        edge_v: 0.0,
        edge_t: 0.0,
        vw: 0.0,
        vh: 0.0,
        sel: false,
        theme: Theme::light(),
        direction: Ltr,
        layer: 0,
        part: 0,
        causes: None,
        sizes: {},
        sizes_end: -1.0,
        sizes_mover: Mover::new(),
  }
  let mut seed = 7
  let next = fn(n : Int) -> Int {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff
    seed % n
  }
  for round in 0..<400 {
    let what = next(10)
    if what < 3 || st.heights.length() == 0 {
      for _ in 0..<(1 + next(20)) {
        st.add_row()
      }
    } else if what < 8 {
      st.set_height(next(st.heights.length()), (10 + next(60)).to_double() + 0.25)
    } else {
      st.moved(next(st.heights.length()), next(7) - 3)
    }
    let mut naive = 0.0
    for k in 0..=st.heights.length() {
      if (st.above(k) - naive).abs() > 1.0e-6 {
        fail("round \{round}: above(\{k}) \{st.above(k)}, rows add up to \{naive}")
      }
      if k < st.heights.length() {
        naive = naive + st.height(k)
      }
    }
  }
}

///|
/// A node reused from the pool keeps nothing of what was there before,
/// whichever builder takes it (each resets only what it does not set).
test "a slot taken by another builder starts afresh" {
  let flip = Ref::new(false)
  let t = Tester::new(
    fn(c) {
      c.column(w=Fill(1.0), h=Fill(1.0), fn() {
        c.row(h=Px(30.0), fn() {
          if flip.val {
            c.spacer()
            c.box(fn() {  }) |> ignore
          } else {
            c.box(w=Px(50.0), pad=5.0, bg=0x336699FFL, fn() {  }) |> ignore
            c.text("words", size=30.0, weight=700, color=0x00FF00FFL) |> ignore
          }
        })
        |> ignore
        if flip.val {
          c.box(w=Fill(1.0), h=Fill(1.0), fn() {  }) |> ignore
        } else {
          c.pager("p", 3, 0, fn(k) { c.text("page \{k}") |> ignore }) |> ignore
        }
      })
      |> ignore
    },
    w=300.0,
    h=300.0,
  )
  assert_true(t.drawn_rects().iter().any(fn(r) { r.4 == 0x336699FFL }))
  assert_eq(g().scroll_ids.length(), 1)
  flip.val = true
  t.frame()
  // nothing drawn: no colour, no words, no pager to drag
  assert_eq(t.drawn_rects().length(), 0)
  assert_eq(t.drawn_glyphs().length(), 0)
  assert_eq(g().scroll_ids.length(), 0)
  assert_eq(g().hit_ids.length(), 0)
  // the spacer has no padding, no colour, no id (words it may keep: only
  // texts read them)
  let n = g().nodes[3]
  assert_eq((n.pad_l, n.pad_t, n.bg, n.id), (0.0, 0.0, 0L, 0))
}
