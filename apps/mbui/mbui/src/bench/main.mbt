// mbui's hill-climb: the scenes of nanoui's hillclimb/ (scenes.mbt) built,
// laid out and painted frame after frame, then drawn by the GPU into an
// offscreen texture, as a window's frames would be. No window opens.
// Measured as nanoui measures its own: 30 frames of warm-up, then the
// measured frames, three runs per scene, the one with the lowest median frame
// kept. nanoui measures 300 frames; here a scene runs as many as fill about
// 300 ms (BENCH_MS), never fewer than 300: 300 frames of the quicker scenes
// are over in 110 ms, where a hiccup of the machine moves their median.
// BENCH_FRAMES=300 measures exactly nanoui's count. Times print in whole µs.
//
//   BENCH_SCENES=text,list BENCH_FRAMES=600 BENCH_MS=500 BENCH_REPEAT=5 BENCH_LABEL="…"
//   BENCH_HISTORY=bench/history.jsonl (where results are appended)
//   BENCH_SHOTS=dir: each scene's last frame as dir/<scene>.png

///|
let width = 900.0

///|
let height = 640.0

///|
let scale = 2.0

///|
let warmup = 30

///|
/// The fewest frames a scene is measured over (nanoui's count).
let min_frames = 300

///|
struct Result {
  scene : String
  frames : Int
  // median CPU time of building, laying out and painting a frame
  frame_ms : Double
  frame_p95 : Double
  // median CPU time of uploading and encoding it for the GPU
  encode_ms : Double
  // median GPU time of drawing it (the command buffer's timestamps)
  gpu_ms : Double
  // the process's user + system time per frame, all included
  cpu_ms : Double
  // instances drawn
  ops : Int
  // the measured frames' wall time, all included
  run_ms : Double
  build_ms : Double
  layout_ms : Double
  paint_ms : Double
  // the process's physical footprint after the run, in MB (not nanoui's)
  mem_mb : Double
}

///|
fn median(xs : Array[Double]) -> Double {
  let s = xs.copy()
  s.sort_by(fn(a, b) { a.compare(b) })
  s[s.length() / 2]
}

///|
fn p95(xs : Array[Double]) -> Double {
  let s = xs.copy()
  s.sort_by(fn(a, b) { a.compare(b) })
  s[s.length() * 95 / 100]
}

///|
/// Frames enough to fill `target_ms` at `frame_ms` a frame, at least `min_frames`.
fn frames_for(frame_ms : Double, target_ms : Int) -> Int {
  if frame_ms <= 0.0 {
    return min_frames
  }
  let n = (target_ms.to_double() / frame_ms).ceil().to_int()
  if n < min_frames {
    min_frames
  } else if n > 100000 {
    100000
  } else {
    n
  }
}

///|
/// `fixed` frames measured, or (0) as many as fill `target_ms`, judged by the
/// warm-up's frames.
fn run_scene(name : String, fixed : Int, target_ms : Int) -> Result {
  let view = scene_view(name)
  let frame_ms = []
  let encode_ms = []
  let gpu_ms = []
  let build = []
  let layout = []
  let paint = []
  let timing = FixedArray::make(2, 0.0)
  let mut cpu0 = 0.0
  let mut ops = 0
  let warm = []
  let mut frames = fixed
  let mut t_start = 0.0
  let mut i = 0
  while i < warmup + frames {
    if i == warmup {
      cpu0 = cpu_ms()
      t_start = @host.now()
    }
    state.frame = i
    state.time = i.to_double() / 120.0
    let t0 = @host.now()
    let c = @ui.frame_offscreen(view, width, height, scale, state.time * 1000.0)
    let ft = @host.now() - t0
    draw_timed(c.inst, c.ninst, timing)
    ops = c.ninst
    if i < warmup {
      warm.push(@host.now() - t0)
      if i == warmup - 1 && fixed == 0 {
        // the warm-up's later half: its first frames are the cold ones
        let late = []
        for k in (warmup / 2)..<warmup {
          late.push(warm[k])
        }
        frames = frames_for(median(late), target_ms)
      }
    } else {
      frame_ms.push(ft)
      encode_ms.push(timing[0])
      gpu_ms.push(timing[1])
      build.push(c.t_build)
      layout.push(c.t_layout)
      paint.push(c.t_paint)
    }
    i += 1
  }
  let run_ms = @host.now() - t_start
  let cpu = (cpu_ms() - cpu0) / frames.to_double()
  {
    scene: name,
    frames,
    frame_ms: median(frame_ms),
    frame_p95: p95(frame_ms),
    encode_ms: median(encode_ms),
    gpu_ms: median(gpu_ms),
    cpu_ms: cpu,
    ops,
    run_ms,
    build_ms: median(build),
    layout_ms: median(layout),
    paint_ms: median(paint),
    mem_mb: @host.mem_bytes() / 1048576.0,
  }
}

///|
fn env_int(name : String, default : Int) -> Int {
  let s = @host.env(name)
  if s == "" {
    return default
  }
  let mut n = 0
  for ch in s {
    let d = ch.to_int() - '0'.to_int()
    if d < 0 || d > 9 {
      return default
    }
    n = n * 10 + d
  }
  if n > 0 {
    n
  } else {
    default
  }
}

///|
/// A time in ms as whole µs.
fn us(ms : Double) -> String {
  (ms * 1000.0).round().to_int().to_string()
}

///|
/// x with one decimal.
fn f1(x : Double) -> String {
  let m = (x * 10.0).round().to_int()
  "\{m / 10}.\{m % 10}"
}

///|
/// A time in ms to the µs, as history.jsonl keeps it: more digits are noise.
fn ms3(x : Double) -> Double {
  (x * 1000.0).round() / 1000.0
}

///|
fn lpad(s : String, n : Int) -> String {
  let mut out = s
  while out.length() < n {
    out = " " + out
  }
  out
}

///|
fn rpad(s : String, n : Int) -> String {
  let mut out = s
  while out.length() < n {
    out = out + " "
  }
  out
}

///|
fn json_string(s : String) -> String {
  let buf = StringBuilder::new()
  buf.write_char('"')
  for ch in s {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      _ => buf.write_char(ch)
    }
  }
  buf.write_char('"')
  buf.to_string()
}

///|
/// A number JSON reads (MoonBit prints whole doubles without a point).
fn json_num(x : Double) -> String {
  if x != x {
    "0"
  } else {
    x.to_string()
  }
}

///|
fn Result::to_json_string(r : Result) -> String {
  "{\"fw\":\"mbui\",\"scene\":\{json_string(r.scene)},\"frames\":\{r.frames}," +
  "\"frame_ms\":\{json_num(ms3(r.frame_ms))},\"frame_p95\":\{json_num(ms3(r.frame_p95))}," +
  "\"encode_ms\":\{json_num(ms3(r.encode_ms))},\"gpu_ms\":\{json_num(ms3(r.gpu_ms))}," +
  "\"cpu_ms\":\{json_num(ms3(r.cpu_ms))},\"ops\":\{r.ops},\"run_ms\":\{r.run_ms.round().to_int()}," +
  "\"build_ms\":\{json_num(ms3(r.build_ms))},\"layout_ms\":\{json_num(ms3(r.layout_ms))},\"paint_ms\":\{json_num(ms3(r.paint_ms))}," +
  "\"mem_mb\":\{json_num(ms3(r.mem_mb))}}"
}

///|
fn print_table(results : Array[Result]) -> Unit {
  println(
    rpad("scene", 10) + " " + rpad("metric", 20) + " " + lpad("mbui", 9),
  )
  for r in results {
    let rows : Array[(String, String)] = [
      ("frame CPU (median)", us(r.frame_ms)),
      ("frame CPU (p95)", us(r.frame_p95)),
      ("  build", us(r.build_ms)),
      ("  layout", us(r.layout_ms)),
      ("  paint", us(r.paint_ms)),
      ("encode CPU", us(r.encode_ms)),
      ("GPU", us(r.gpu_ms)),
      ("process CPU / frame", us(r.cpu_ms)),
      ("draw items", r.ops.to_string()),
      ("frames", r.frames.to_string()),
      ("run (ms)", r.run_ms.round().to_int().to_string()),
      ("memory (MB)", f1(r.mem_mb)),
    ]
    for k, row in rows {
      println(
        rpad(if k == 0 { r.scene } else { "" }, 10) +
        " " +
        rpad(row.0, 20) +
        " " +
        lpad(row.1, 9),
      )
    }
    println("")
  }
  println("times in µs a frame")
}

///|
fn main {
  if !supported {
    println("the bench draws with Metal: build it for the native target on macOS")
    return
  }
  let frames = env_int("BENCH_FRAMES", 0)
  let target_ms = env_int("BENCH_MS", 300)
  let repeat = env_int("BENCH_REPEAT", 3)
  let label = @host.env("BENCH_LABEL")
  let history = {
    let h = @host.env("BENCH_HISTORY")
    if h == "" {
      "bench/history.jsonl"
    } else {
      h
    }
  }
  let wanted = @host.env("BENCH_SCENES")
  let scenes = if wanted == "" {
    scene_names
  } else {
    let out = []
    for part in wanted.split(",") {
      let p = part.to_string()
      if scene_names.contains(p) || glass_scene_names.contains(p) {
        out.push(p)
      } else {
        println("unknown scene: \{p}")
      }
    }
    out
  }
  let measured = if frames > 0 {
    "\{frames} frames"
  } else {
    "frames filling ~\{target_ms} ms (at least \{min_frames})"
  }
  println(
    "\nmbui hill-climb · \{measured} after \{warmup} of warm-up · \{width.to_int()}×\{height.to_int()} at \{scale.to_int()}x · offscreen, no window\n",
  )
  init_offscreen(width, height, scale)
  let results = []
  for name in scenes {
    let mut best : Result? = None
    for rep in 0..<repeat {
      status("\r\u{1b}[2Kmbui · \{name} · run \{rep + 1}/\{repeat}…")
      let r = run_scene(name, frames, target_ms)
      best = match best {
        Some(b) if b.frame_ms <= r.frame_ms => Some(b)
        _ => Some(r)
      }
    }
    let shots = @host.env("BENCH_SHOTS")
    if shots != "" {
      snapshot("\{shots}/\{name}.png")
    }
    match best {
      Some(r) => results.push(r)
      None => ()
    }
  }
  status("\r\u{1b}[2K")
  print_table(results)
  let parts = results.map(fn(r) { r.to_json_string() })
  let line = "{\"time\":\{unix_time().to_int64()},\"label\":\{json_string(label)},\"results\":[" +
    parts.join(",") +
    "]}"
  if !append_line(history, line) {
    println("could not append to \{history}")
  }
}
