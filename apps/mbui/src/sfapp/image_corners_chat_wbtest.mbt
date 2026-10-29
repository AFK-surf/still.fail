// The chat's pictures coming in as the chat opens (sfpages image_reveal in image_item's frame): nothing drawn ever past
// a picture's frame's rounded corners, on any frame.

///|
/// How much of instance `a` covers the device pixel at (`px`, `py`), as the renderers cover it: its own rect and
/// corner, cut by its clip and its outer (@ui.sd_clip, the renderers' mb_sd_clip).
fn corner_cover(a : Array[Double], px : Double, py : Double, scale : Double) -> Double {
  let cover = fn(d : Double) { dmax(0.0, dmin(1.0, 0.5 - d * scale)) }
  let own = cover(@ui.sd_box(px - (a[0] + a[2] / 2.0), py - (a[1] + a[3] / 2.0), a[2] / 2.0, a[3] / 2.0, a[4]))
  let cut = fn(k : Int) {
    cover(
      @ui.sd_clip(
        px,
        py,
        a[k],
        a[k + 1],
        a[k + 2],
        a[k + 3],
        (a[k + 4], a[k + 5], a[k + 6], a[k + 7]),
        (a[k + 8], a[k + 9], a[k + 10], a[k + 11]),
      ),
    )
  }
  // (the clip: 16-19, its corners 24-27, how smooth 28-31; the outer: 40-43, 44-47, 48-51)
  let clip = fn() {
    cover(
      @ui.sd_clip(
        px,
        py,
        a[16],
        a[17],
        a[18],
        a[19],
        (a[24], a[25], a[26], a[27]),
        (a[28], a[29], a[30], a[31]),
      ),
    )
  }
  let outer = if dmax(dmax(a[44], a[45]), dmax(a[46], a[47])) > 0.0 { cut(40) } else { 1.0 }
  own * clip() * outer
}

///|
/// The made-up chat on a screen `w` by `h` at `scale`, scrolled up to its pictures as they first show: every frame of
/// their way in, each picture's frame's corners checked pixel by pixel against what is drawn there.
fn chat_corners(w : Double, h : Double, scale : Double) -> Int raise {
  reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h~, platform=2, scale~)
  t.run_for(@ui.move_most_ms)
  // over the chat's messages, wherever the screen puts the chat
  let (mx, my) = t.find("做完了：列表、跳到最新的按钮").unwrap_or((w / 2.0, h / 2.0))
  // (a pane at the window's edge, not in use: brought over first)
  if mx > w * 0.8 {
    t.tap(mx, my)
    t.run_for(@ui.move_most_ms)
  }
  let (mx, my) = t.find("做完了：列表、跳到最新的按钮").unwrap_or((w / 2.0, h / 2.0))
  let my = dmin(my, h / 2.0)
  t.move(mx, my)
  let mut tries = 0
  let shown = fn() {
    match t.find("改好后的样子：") {
      Some((_, y)) => y > 120.0 && y < h / 3.0
      None => false
    }
  }
  while !shown() && tries < 60 {
    t.wheel(mx, my, -200.0)
    t.frame()
    tries += 1
  }
  let frames : Array[(Double, Array[Array[Double]])] = []
  let began = t.time()
  while t.time() - began < @sfpages.reveal_ms * 1.5 {
    t.frame()
    frames.push((t.time() - began, t.drawn_instances()))
  }
  // the pictures' frames, as they cut each picture once it is in
  let pictures = t.drawn_instances().filter(fn(a) { a[5] == 4.0 && a[24] >= 10.0 && a[2] > 40.0 })
  assert_true(pictures.length() > 0, msg="no picture whole in its frame")
  let side = 16.0
  let n = (side * scale).to_int()
  let mut bad = 0
  for f in frames {
    let (at, insts) = f
    for a in insts {
      if a[5] != 0.0 && a[5] != 4.0 && a[5] != 5.0 {
        continue
      }
      for p in pictures {
        let frame = p.copy()
        for j in 0..<4 {
          frame[j] = p[16 + j]
        }
        frame[2] = p[18] - p[16]
        frame[3] = p[19] - p[17]
        frame[4] = 0.0
        let (x0, y0, x1, y1) = (p[16], p[17], p[18], p[19])
        // (what is drawn in the frame: cut to within it; the page under it is not)
        if a[16] < x0 - 0.5 || a[17] < y0 - 0.5 || a[18] > x1 + 0.5 || a[19] > y1 + 0.5 {
          continue
        }
        for corner in [(x0, y0), (x1 - side, y0), (x1 - side, y1 - side), (x0, y1 - side)] {
          for i in 0..<n {
            for k in 0..<n {
              let px = corner.0 + (i.to_double() + 0.5) / scale
              let py = corner.1 + (k.to_double() + 0.5) / scale
              let have = corner_cover(a, px, py, scale)
              let want = corner_cover(frame, px, py, scale)
              if have - want > 0.5 {
                bad = bad + 1
                if bad < 30 {
                  println(
                    "CORNER \{w}x\{h} \{at} ms: kind \{a[5]} rect (\{a[0]}, \{a[1]}, \{a[2]}, \{a[3]}) r \{a[4]} covers (\{px}, \{py}) past the frame (\{x0}, \{y0}, \{x1}, \{y1}): clip \{a[16:20]} \{a[24:28]}, outer \{a[40:44]} \{a[44:48]}",
                  )
                }
                break
              }
            }
          }
        }
      }
    }
  }
  bad
}

///|
test "the chat's pictures coming in never show past their frames' rounded corners" {
  let small = chat_corners(390.0, 844.0, 3.25)
  let medium = chat_corners(690.0, 763.0, 3.25)
  assert_eq((small, medium), (0, 0))
}
