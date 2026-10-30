// A scripted run measured, offscreen (still.fail's scripts/appbench.sh, its src/sfbench): the app in a Tester of this
// host's text and pictures, as a film runs it, the script's steps on the display's frames (120 a second), and a frame
// drawn at one only where the app asks for one there, as a host draws (Tester::bench). Each frame drawn: what it did
// (@ui.FramePerf: what was built and laid out), how long its work took by this machine's clock, what of it differs
// from the frame before (src/damage, as a window's host is told) and how long working that out took, and that part
// drawn by this host's renderer as a window's frame is, its uploading and encoding and its GPU time measured
// (src/host/apple_render.m). What a run said, one line: APPBENCH and its numbers as JSON, medians and the 95th
// centiles over the frames drawn. Measured, never judged: a time is reported and compared, never a test's condition.
//
//   MBUI_BENCH_DRIVE=<script> MBUI_BENCH_NAME=<scene> [MBUI_WIN=390x844] [MBUI_FILM_SCALE=2] [MBUI_FILM_PLATFORM=0]
//   [MBUI_POINTING=finger|mouse] [MBUI_BENCH_FPS=120] [MBUI_BENCH_FRAMES=<file>: each of the display's frames, a line,
//   with what asked for it and why it was built or painted] [MBUI_BENCH_WHOLE=1: each frame from `log measure` on drawn
//   and built whole, keeping nothing]

///|
/// What one frame drawn did, as measured.
priv struct Measured {
  perf : @ui.FramePerf
  work_ms : Double
  encode_ms : Double
  gpu_ms : Double
  damage : Double
  damage_ms : Double
  bytes : Int
}

///|
/// `script` run over `view` and measured (the head of this file): the APPBENCH line said, whether the script passed.
pub fn bench(
  view : (@ui.Ctx) -> Unit,
  tree? : (@view.View) -> Unit,
  script~ : String,
  name~ : String,
  w? : Double = 390.0,
  h? : Double = 844.0,
  scale? : Double = 2.0,
  platform? : Int = 0,
  pointing? : @ui.Pointing,
  fps? : Double = 120.0,
  frames_out? : String = "",
) -> Bool {
  if !supported {
    say("bench: this host has no offscreen renderer")
    return false
  }
  let host = @hostapi.host()
  init_offscreen(w, h, scale)
  // (the work timed by this machine's clock: the Tester's is the run's)
  @ui.set_work_clock(Some(now_ms))
  let t = @ui.Tester::new(
    view,
    tree?,
    w~,
    h~,
    scale~,
    platform~,
    pointing?=pointing,
    env=[("MBUI_LOCALE", arg("MBUI_LOCALE")), ("MBUI_DARK", arg("MBUI_DARK"))],
    live={ host, turn: fn() { spin(1.0) } },
    // (a test's own check of each frame at rest not run: not the app's work)
    corners_held=false,
    words_over_held=false,
  )
  // (a frame of the looks alone drawn once, as a host draws it: a test's draws it whole too, frame_watch.mbt)
  t.check_looks(false)
  // (MBUI_BENCH_WHOLE=1: every frame measured built whole, keeping nothing: what building a frame anew costs)
  t.bench_whole(arg("MBUI_BENCH_WHOLE") == "1")
  let buf = Ref::new(FixedArray::make(0, 0.0))
  let damage = @damage.Damage::new()
  let timing = FixedArray::make(2, 0.0)
  let drawn : Array[Measured] = []
  let lines : Array[String] = []
  let mut ticks = 0
  // why the frames drawn were asked for (Tester::wanted_why as the frame before each ended): how many each thing asked for
  // (a frame counted under each that asked for it, said without when or where: why_labels)
  let whys : Map[String, Int] = {}
  let mut why = ""
  let logs = t.bench(script, fps~, each=fn(t, frame) {
    ticks = ticks + 1
    // (what asked for this frame, said on its line: FRAMES)
    let asked = why
    if frame {
      for k in why_labels(why) {
        whys[k] = whys.get(k).unwrap_or(0) + 1
      }
      // (and of those built whole, why: what of what it read changed, frame_watch.mbt)
      let built = t.built_why()
      if built != "" {
        let k = "built: " + built
        whys[k] = whys.get(k).unwrap_or(0) + 1
      }
      // (and of those painted alone, why: what of what its paint read changed)
      let painted = t.painted_why()
      if painted != "" {
        let k = "painted: " + painted
        whys[k] = whys.get(k).unwrap_or(0) + 1
      }
      // (and of the lists' rows built, why they may not be kept: kept_nodes.mbt)
      if built != "" {
        for u in @ui.rows_unkept() {
          let k = "rows built each frame: " + u.0
          whys[k] = whys.get(k).unwrap_or(0) + u.1
        }
      }
    }
    why = t.wanted_why()
    if !frame {
      if frames_out != "" {
        lines.push("\{ticks} -")
      }
      return
    }
    let perf = t.frame_perf()
    let (n, (r, g, b)) = host_frame(t, buf)
    // (what of it differs worked out as a window's host does, on its main thread before it is drawn: h_present)
    let d0 = now_ms()
    let parts = damage.next(buf.val, n, w, h, scale, r, g, b)
    let damage_ms = now_ms() - d0
    let area = parts.fold(init=0.0, fn(a, p) { if p.2 < 0.0 { a + w * h } else { a + p.2 * p.3 } })
    if parts.is_empty() {
      // (nothing differs: the window's picture as it was, nothing drawn)
      timing[0] = 0.0
      timing[1] = 0.0
    } else {
      draw_timed(buf.val, n, r, g, b, parts, timing)
    }
    let m : Measured = {
      perf,
      work_ms: perf.build_ms + perf.layout_ms + perf.paint_ms,
      encode_ms: timing[0],
      gpu_ms: timing[1],
      damage: dmin(1.0, area / (w * h)),
      damage_ms,
      // (what a frame drawn uploads: its instances, 32-bit numbers)
      bytes: if parts.is_empty() { 0 } else { n * inst_size * 4 },
    }
    drawn.push(m)
    if frames_out != "" {
      lines.push(
        "\{ticks} work=\{m.work_ms} build=\{perf.build_ms} layout=\{perf.layout_ms} paint=\{perf.paint_ms} encode=\{m.encode_ms} gpu=\{m.gpu_ms} nodes=\{perf.nodes} laid=\{perf.laid} insts=\{perf.insts} looks=\{perf.looks} painted=\{perf.painted} kept=\{perf.kept} rows=\{perf.rows} damage=\{m.damage} passes=\{perf.passes} asked=\{asked.escape()} built_why=\{t.built_why().escape()} painted_why=\{t.painted_why().escape()}",
      )
    }
  })
  @ui.set_work_clock(None)
  if frames_out != "" {
    ignore(write_text(frames_out, lines.join("\n") + "\n"))
  }
  for l in logs {
    if l.has_prefix("DRIVE") {
      say(l)
    }
  }
  let passed = logs.iter().any(fn(l) { l == "DRIVE PASS" })
  let d = fn(f : (Measured) -> Double) { drawn.map(f) }
  let stat = fn(xs : Array[Double]) -> Json {
    { "med": centile(xs, 50).to_json(), "p95": centile(xs, 95).to_json() }
  }
  let out : Json = {
    "scene": name.to_json(),
    "w": w.to_json(),
    "h": h.to_json(),
    "fps": fps.to_json(),
    "ticks": ticks.to_json(),
    "frames": drawn.length().to_json(),
    "looks": drawn.filter(fn(m) { m.perf.looks }).length().to_json(),
    "painted": drawn.filter(fn(m) { m.perf.painted }).length().to_json(),
    "kept": drawn.filter(fn(m) { m.perf.kept > 0 }).length().to_json(),
    "rows_kept": stat(d(fn(m) { m.perf.kept.to_double() })),
    "rows_built": stat(d(fn(m) { m.perf.rows.to_double() })),
    "work_ms": stat(d(fn(m) { m.work_ms })),
    "build_ms": stat(d(fn(m) { m.perf.build_ms })),
    "layout_ms": stat(d(fn(m) { m.perf.layout_ms })),
    "paint_ms": stat(d(fn(m) { m.perf.paint_ms })),
    "encode_ms": stat(d(fn(m) { m.encode_ms })),
    "gpu_ms": stat(d(fn(m) { m.gpu_ms })),
    "nodes": stat(d(fn(m) { m.perf.nodes.to_double() })),
    "laid": stat(d(fn(m) { m.perf.laid.to_double() })),
    "insts": stat(d(fn(m) { m.perf.insts.to_double() })),
    "damage": stat(d(fn(m) { m.damage })),
    "damage_ms": stat(d(fn(m) { m.damage_ms })),
    "upload_kb": stat(d(fn(m) { m.bytes.to_double() / 1024.0 })),
    "passes": d(fn(m) { m.perf.passes.to_double() }).fold(init=0.0, dmax).to_json(),
    "passed": passed.to_json(),
    "why": whys.to_json(),
  }
  say("APPBENCH " + out.stringify())
  // (and a row of the table scripts/appbench.sh prints)
  let ms = fn(xs : Array[Double]) { "\{round2(centile(xs, 50))} / \{round2(centile(xs, 95))}" }
  say(
    "APPROW | \{name} | \{drawn.length()}/\{ticks} (\{drawn.filter(fn(m) { m.perf.looks }).length()} looks, \{drawn.filter(fn(m) { m.perf.painted }).length()} painted, \{drawn.filter(fn(m) { m.perf.kept > 0 }).length()} kept rows) | \{total_ms(d(fn(m) { m.work_ms }))} | \{ms(d(fn(m) { m.work_ms }))} | \{ms(d(fn(m) { m.perf.build_ms }))} | \{ms(d(fn(m) { m.perf.layout_ms }))} | \{ms(d(fn(m) { m.perf.paint_ms }))} | \{ms(d(fn(m) { m.encode_ms }))} | \{ms(d(fn(m) { m.gpu_ms }))} | \{centile(d(fn(m) { m.perf.nodes.to_double() }), 50)} | \{centile(d(fn(m) { m.perf.laid.to_double() }), 50)} | \{centile(d(fn(m) { m.perf.insts.to_double() }), 50)} | \{round2(centile(d(fn(m) { m.damage * 100.0 }), 50))}% | \{round2(centile(d(fn(m) { m.bytes.to_double() / 1024.0 }), 50))} |",
  )
  passed
}

///|
/// `v` to two places.
fn round2(v : Double) -> Double {
  (v * 100.0).round() / 100.0
}

///|
/// The `k`th centile of `xs` (0 where there are none).
fn centile(xs : Array[Double], k : Int) -> Double {
  if xs.is_empty() {
    return 0.0
  }
  let s = xs.copy()
  s.sort_by(fn(a, b) { a.compare(b) })
  s[dmin((s.length() * k / 100).to_double(), (s.length() - 1).to_double()).to_int()]
}

///|
fn dmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn dmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
/// A phone's run of scene `name` as its log said it (`log`: a host's PERF lines, MBUI_PROBE_FRAMES=1, and the scripted
/// run's DRIVE lines, from its `log measure` on): the same APPBENCH line and row as a run offscreen, the host's
/// presenting in place of encoding (its GPU time where it measures one). Whether the run passed.
pub fn bench_log(name : String, log : String) -> Bool {
  let frames : Array[Map[String, Double]] = []
  let mut measuring = false
  let mut passed = false
  let mut t0 = -1.0
  let mut t1 = -1.0
  for line in log.split("\n") {
    let l = line.to_string()
    if l.contains("DRIVE LOG measure") {
      measuring = true
    }
    if l.contains("DRIVE PASS") {
      passed = true
    }
    match l.find("PERF ") {
      Some(at) if measuring => {
        let f : Map[String, Double] = {}
        for kv in l.unsafe_substring(start=at + 5, end=l.length()).split(" ") {
          let kv = kv.to_string()
          match kv.find("=") {
            Some(eq) =>
              match number(kv.unsafe_substring(start=eq + 1, end=kv.length())) {
                Some(v) => f[kv.unsafe_substring(start=0, end=eq)] = v
                None => ()
              }
            None => ()
          }
        }
        let t = f.get("t").unwrap_or(0.0)
        if t0 < 0.0 {
          t0 = t
        }
        t1 = t
        frames.push(f)
      }
      _ => ()
    }
  }
  let col = fn(k : String) { frames.map(fn(f) { f.get(k).unwrap_or(0.0) }) }
  let gpu = col("gpu").filter(fn(v) { v >= 0.0 })
  let shown = frames.filter(fn(f) { f.get("share").unwrap_or(0.0) > 0.0 })
  let upload = frames.map(fn(f) {
    if f.get("share").unwrap_or(0.0) > 0.0 {
      f.get("insts").unwrap_or(0.0) * inst_size.to_double() * 4.0 / 1024.0
    } else {
      0.0
    }
  })
  let secs = if t1 > t0 { (t1 - t0) / 1000.0 } else { 0.0 }
  let stat = fn(xs : Array[Double]) -> Json {
    { "med": centile(xs, 50).to_json(), "p95": centile(xs, 95).to_json() }
  }
  let out : Json = {
    "scene": name.to_json(),
    "host": "phone".to_json(),
    "seconds": secs.to_json(),
    "frames": frames.length().to_json(),
    "drawn": shown.length().to_json(),
    "looks": frames.filter(fn(f) { f.get("looks").unwrap_or(0.0) > 0.0 }).length().to_json(),
    "painted": frames.filter(fn(f) { f.get("painted").unwrap_or(0.0) > 0.0 }).length().to_json(),
    "work_ms": stat(col("work")),
    "build_ms": stat(col("build")),
    "layout_ms": stat(col("layout")),
    "paint_ms": stat(col("paint")),
    "present_ms": stat(col("present")),
    "gpu_ms": stat(gpu),
    "nodes": stat(col("nodes")),
    "laid": stat(col("laid")),
    "insts": stat(col("insts")),
    "damage": stat(col("share")),
    "upload_kb": stat(upload),
    "passed": passed.to_json(),
  }
  say("APPBENCH " + out.stringify())
  let ms = fn(xs : Array[Double]) { "\{round2(centile(xs, 50))} / \{round2(centile(xs, 95))}" }
  say(
    "APPROW | \{name} | \{frames.length()} in \{round2(secs)} s (\{frames.filter(fn(f) { f.get("looks").unwrap_or(0.0) > 0.0 }).length()} looks, \{frames.filter(fn(f) { f.get("painted").unwrap_or(0.0) > 0.0 }).length()} painted) | \{total_ms(col("work"))} | \{ms(col("work"))} | \{ms(col("build"))} | \{ms(col("layout"))} | \{ms(col("paint"))} | \{ms(col("present"))} | \{if gpu.is_empty() { "-" } else { ms(gpu) }} | \{centile(col("nodes"), 50)} | \{centile(col("laid"), 50)} | \{centile(col("insts"), 50)} | \{round2(centile(col("share"), 50) * 100.0)}% | \{round2(centile(upload, 50))} |",
  )
  passed
}

///|
/// All of `xs` (ms) as one whole number of ms: what a scene's frames took between them. A scene is sized to take some
/// 300 ms so (a whole number easy to read, far past any fixed cost, quick enough to run again and again: matklad's
/// "Benchmark In Milliseconds", 2026).
fn total_ms(xs : Array[Double]) -> String {
  let mut t = 0.0
  for x in xs {
    t = t + x
  }
  t.round().to_int().to_string()
}

///|
/// A bench run of the process's arguments (the head of this file says which), `view` the app's: the process ends with
/// 0 when the script passed, 1 when not, 2 when it was not asked for rightly. MBUI_BENCH_LOG=<file>: a phone's run
/// read from its log instead (bench_log), no Tester.
pub fn run_bench(view : (@ui.Ctx) -> Unit, tree? : (@view.View) -> Unit) -> Unit {
  let drive = arg("MBUI_BENCH_DRIVE")
  let name = arg("MBUI_BENCH_NAME")
  let log = arg("MBUI_BENCH_LOG")
  if log != "" {
    exit(if bench_log(name, read_text(log)) { 0 } else { 1 })
    return
  }
  if drive == "" || name == "" {
    say("bench: MBUI_BENCH_DRIVE=<script> MBUI_BENCH_NAME=<scene> [MBUI_WIN=390x844] [MBUI_FILM_SCALE=2] [MBUI_FILM_PLATFORM=0] [MBUI_POINTING=finger|mouse] [MBUI_BENCH_FPS=120] [MBUI_BENCH_FRAMES=<file>]")
    exit(2)
    return
  }
  let script = read_text(drive)
  if script == "" {
    say("bench: \{drive}: no script there")
    exit(2)
    return
  }
  let (w, h) = match arg("MBUI_WIN").split("x").map(fn(p) { number(p.to_owned()) }).to_array() {
    [Some(w), Some(h)] if w > 0.0 && h > 0.0 => (w, h)
    _ => (390.0, 844.0)
  }
  let ok = bench(
    view,
    tree?,
    script~,
    name~,
    w~,
    h~,
    scale=number(arg("MBUI_FILM_SCALE")).unwrap_or(2.0),
    platform=number(arg("MBUI_FILM_PLATFORM")).unwrap_or(0.0).to_int(),
    pointing?=match arg("MBUI_POINTING") {
      "finger" => Some(@ui.Pointing::Finger)
      "mouse" => Some(@ui.Pointing::Mouse)
      _ => None
    },
    fps=number(arg("MBUI_BENCH_FPS")).unwrap_or(120.0),
    frames_out=arg("MBUI_BENCH_FRAMES"),
  )
  exit(if ok { 0 } else { 1 })
}

///|
/// What asked for a frame (Tester::wanted_why: its parts, "; " between them), each said without when or where it was
/// told (a motion's name, "a wake"): what a scene's frames are counted by. "nothing" where nothing asked (a frame
/// drawn for the script's own step).
fn why_labels(why : String) -> Array[String] {
  if why == "" {
    return ["nothing"]
  }
  let out = []
  for part in why.split("; ") {
    let mut s = part.to_string()
    if s.has_prefix("moving: ") {
      s = s.unsafe_substring(start=8, end=s.length())
    }
    for cut in [", told at", " (", " by ", " in "] {
      match s.find(cut) {
        Some(i) => s = s.unsafe_substring(start=0, end=i)
        None => ()
      }
    }
    // (a motion's target, a count: not what it is)
    let s = s.trim(chars=" ").to_string()
    let s = match s.find(" to ") {
      Some(i) => s.unsafe_substring(start=0, end=i)
      None => s
    }
    if !out.contains(s) {
      out.push(s)
    }
  }
  out
}
