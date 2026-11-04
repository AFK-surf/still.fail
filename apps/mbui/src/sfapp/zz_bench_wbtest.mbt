///|
// kept across runs: a bench's, the frames drawn since it was last read
let zz_frames : Ref[Int] = Ref(0)

///|
// kept across runs: a bench's, any Tester to say the check is off by
let zz_any : Ref[@ui.Tester?] = Ref(None)

///|
/// A long chat opened as kept_rows_open does, measured as a host runs it: no frame drawn again to be checked
/// (frame_watch.mbt's looks_check, every Tester's), from its first frame on.
fn zz_open() -> @ui.Tester {
  // (the check is the tree's, said by any Tester: one made once before, so each frame of the next said so before it)
  let any = match zz_any.val {
    Some(t) => t
    None => {
      let t = @ui.Tester::new(fn(_) { }, w=10.0, h=10.0)
      zz_any.val = Some(t)
      t
    }
  }
  new_run()
  let src = fixture("chat-long")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2, corners_held=false,
    before=fn() { zz_frames.val += 1; any.check_looks(false) })
  t.run_for(@ui.move_most_ms)
  t
}

///|
fn zz_bench_open(n : Int) -> Unit {
  for _ in 0..<n {
    let t = zz_open()
    t.run_for(120.0)
  }
}

///|
fn zz_bench_idle(frames : Int) -> Unit {
  let t = zz_open()
  t.run_for(120.0)
  for _ in 0..<frames {
    t.frame(ms=16.0)
  }
}

///|
fn zz_bench_scroll(rounds : Int) -> Unit {
  let t = zz_open()
  t.run_for(120.0)
  for _ in 0..<rounds {
    t.drag(273.0, 590.0, 273.0, 340.0, steps=12)
    t.run_for(600.0)
    t.drag(273.0, 340.0, 273.0, 590.0, steps=12)
    t.run_for(600.0)
  }
}

///|
test "zz bench open 1" { zz_bench_open(1) }

///|
test "zz bench open 4" { zz_bench_open(4) }

///|
test "zz bench open 16" { zz_bench_open(16) }

///|
test "zz bench idle 0" { zz_bench_idle(0) }

///|
test "zz bench idle 1200" { zz_bench_idle(1200) }

///|
test "zz bench scroll 0" { zz_bench_scroll(0) }

///|
test "zz bench scroll 4" { zz_bench_scroll(4) }

///|
test "zz bench open sample" { zz_bench_open(300) }

///|
fn zz_bench_send(n : Int) -> Unit {
  let t = zz_open()
  t.run_for(120.0)
  for i in 0..<n {
    t.tap_text("发消息")
    t.type_text("第 \{i} 句")
    tap_send(t)
    t.run_for(900.0)
  }
}

///|
test "zz bench send 0" { zz_bench_send(0) }

///|
test "zz bench send 4" { zz_bench_send(4) }

///|
test "zz count open frames" {
  zz_frames.val = 0
  let t = zz_open()
  let opened = zz_frames.val
  t.run_for(120.0)
  println("ZZCOUNT frames to open \{opened}, then in 120 ms \{zz_frames.val - opened}; rows in sight \{t.visible()}, rows made \{@ui.view_tree().map(fn(tr) { tr.rows_alive().length() })}")
}
