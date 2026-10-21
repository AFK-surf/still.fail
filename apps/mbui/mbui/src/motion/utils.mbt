// Motion's numeric utilities (motion-utils: clamp, progress, wrap, velocityPerSecond, pipe, time conversion;
// motion-dom: mixNumber, interpolate), for numbers. Ported from Motion (motion.dev): Copyright (c) 2024 Motion B.V.,
// MIT licence. Motion's mixers of colours, strings and objects are not here: what mbui animates are numbers (a
// colour is animated by its channels).

///|
/// `v` kept within `min` … `max` (Motion's clamp: its arguments in that order).
pub fn clamp(min : Double, max : Double, v : Double) -> Double {
  if v > max {
    max
  } else if v < min {
    min
  } else {
    v
  }
}

///|
/// How far `value` is from `from` to `to` (0 at from, 1 at to; not clamped). 1 when the range is empty.
pub fn progress(from : Double, to : Double, value : Double) -> Double {
  let range = to - from
  if range != 0.0 {
    (value - from) / range
  } else {
    1.0
  }
}

///|
/// `v` wrapped into `min` … `max` (min included, max not).
pub fn wrap(min : Double, max : Double, v : Double) -> Double {
  let size = max - min
  ((v - min) % size + size) % size + min
}

///|
/// A change over a frame of `frame_ms` as a change per second (0 for a frame of no time).
pub fn velocity_per_second(velocity : Double, frame_ms : Double) -> Double {
  if frame_ms != 0.0 {
    velocity * (1000.0 / frame_ms)
  } else {
    0.0
  }
}

///|
pub fn seconds_to_ms(s : Double) -> Double {
  s * 1000.0
}

///|
pub fn ms_to_seconds(ms : Double) -> Double {
  ms / 1000.0
}

///|
/// The value `p` of the way from `from` to `to` (Motion's mixNumber, mix for numbers; not clamped).
pub fn mix(from : Double, to : Double, p : Double) -> Double {
  from + (to - from) * p
}

///|
/// The functions one after another (Motion's pipe).
pub fn pipe(fs : Array[(Double) -> Double]) -> (Double) -> Double {
  fn(v) {
    let mut x = v
    for f in fs {
      x = f(x)
    }
    x
  }
}

///|
/// What maps `input` (ascending or descending) onto `output`, piece by piece (Motion's interpolate): clamped to the
/// input's range unless `clamp` is false; each piece eased by `ease` (or by its own of `eases`); `mixer` instead of
/// mixing numbers (from, to → progress → value).
pub fn interpolate(
  input : Array[Double],
  output : Array[Double],
  clamp? : Bool = true,
  ease? : (Double) -> Double,
  eases? : Array[(Double) -> Double],
  mixer? : (Double, Double) -> (Double) -> Double,
) -> (Double) -> Double {
  let n = input.length()
  guard n == output.length() else { abort("Both input and output ranges must be the same length") }
  if n == 1 {
    let o = output[0]
    return fn(_) { o }
  }
  if n == 2 && output[0] == output[1] {
    let o = output[1]
    return fn(_) { o }
  }
  let zero_range = input[0] == input[1]
  let (input, output) = if input[0] > input[n - 1] {
    (input.rev(), output.rev())
  } else {
    (input, output)
  }
  let mixers : Array[(Double) -> Double] = []
  for i in 0..<(n - 1) {
    let m = match mixer {
      Some(f) => f(output[i], output[i + 1])
      None => {
        let a = output[i]
        let b = output[i + 1]
        fn(p) { mix(a, b, p) }
      }
    }
    let e = match (eases, ease) {
      (Some(es), _) => if i < es.length() { Some(es[i]) } else { Some(linear) }
      (None, Some(e)) => Some(e)
      (None, None) => None
    }
    mixers.push(match e {
      Some(e) => fn(p) { m(e(p)) }
      None => m
    })
  }
  let count = mixers.length()
  let at = fn(v : Double) {
    if zero_range && v < input[0] {
      return output[0]
    }
    let mut i = 0
    if count > 1 {
      while i < n - 2 {
        if v < input[i + 1] {
          break
        }
        i = i + 1
      }
    }
    (mixers[i])(progress(input[i], input[i + 1], v))
  }
  if clamp {
    let lo = input[0]
    let hi = input[n - 1]
    fn(v) { at(if v < lo { lo } else if v > hi { hi } else { v }) }
  } else {
    at
  }
}
