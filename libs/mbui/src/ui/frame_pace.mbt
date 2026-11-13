// How often what moves on by the clock is drawn. A frame that asks for the next only because something moves on by the
// clock (a motion going, a cycle shown: on_frame's request_frame_on) asks for as many frames a second as that motion
// needs where it is seen, worked out from what it is: how far what changed of the frame went since the frame before
// and how much its colours changed (what the frame presented is compared with the one before anyway, @damage's step),
// over the time between them. Each frame steps at most `pace_far` points and `pace_ink` of a colour; a spinner's turn,
// a slow fade or what reads the clock and draws nothing new needs fewer frames than the display shows, and the host
// draws only those, telling the display it may refresh as slowly (@hostapi.frames_paced: ProMotion's
// preferredFrameRateRange, Android's Surface.setFrameRate), as mygo's Painter.AnimationFrameRate asks of it by hand.
//
// It is how often the host draws, never what: a frame at a moment is that moment's whatever came before it, so the
// picture and the state at any moment are the same at any rate (mbui/AGENTS.md, Time in a test is declared). What else
// asks for a frame (an input, a change of what is built, a fiber stepping a frame at a time) is drawn at the display's
// next, and so is a frame whose changes are not each an instance moved or recoloured (one come or gone, a picture's
// frames, the frame drawn whole): its motion is not known. What scrolls is drawn at every frame however slowly it
// goes: a glide's slow end at a lower rate is felt under the finger that let it go (the user, 2026-11-09).

///|
/// The rates what moves on by the clock is drawn at below the display's own (frames a second), each a 120 Hz display's
/// frames evenly (40 a 60 Hz display's in twos, as 30); a motion that needs more than the first is drawn at every frame
/// of the display's.
// kept across runs: a table, never written
let pace_rates : FixedArray[Double] = [60.0, 40.0, 30.0, 20.0, 15.0]

///|
/// How far any pixel of what moves goes in a frame at most (points) at the rate it is drawn at: a spinner of 14 points
/// turning once in 800 ms, 49 points a second at its arc, is drawn at 30 Hz; a list flung, every frame.
let pace_far : Double = 2.0

///|
/// How much a colour or an opacity changes in a frame at most (of 1): a fade from none to whole in 3 s is drawn at 30
/// Hz, one in 300 ms at every frame.
let pace_ink : Double = 3.0 / 255.0

///|
/// The longest between two frames that a motion's speed is worked out over (ms): longer apart (the app away, a host's
/// late frame), what moved between them is not its speed.
let pace_span : Double = 100.0

///|
/// The frames' pace: the moment of the frame before where it asked for the next by the clock alone (-1: it did not),
/// and the rate it asked for (its place among pace_rates; -1 the display's every frame).
priv struct Pace {
  mut at : Double
  mut rung : Int
}

///|
// kept across runs: put back as a run begins (pace_none), else said by each frame as it ends
let pace : Pace = { at: -1.0, rung: -1 }

///|
/// The frame at `t` that asks for the next for nothing but what moves on by the clock: how many frames a second what
/// moves needs from now (0: the display's every frame). Falls a rate a frame (a motion slowing down, eased out), rises
/// at once (one speeding up: its next frame at the rate its speed asks).
fn pace_by_clock(t : Double) -> Double {
  let dt = t - pace.at
  // (what scrolls (moved by the hand, or gliding on by itself to its end; a list's rows moved by their header, Damage::step)
  // at every frame however slowly it goes, the user, 2026-11-09)
  let rung = match presented.step() {
    _ if scroll_paint_uncompared.val || tree_gliding(t) => -1
    Some((far, ink)) if pace.at >= 0.0 && dt > 0.0 && dt <= pace_span => {
      // the frames a second it needs: a step of `pace_far` or `pace_ink` each
      let need = dmax(far / pace_far, ink / pace_ink) * 1000.0 / dt
      let mut r = -1
      for i, hz in pace_rates {
        if hz >= need {
          r = i
        }
      }
      if r > pace.rung + 1 {
        pace.rung + 1
      } else {
        r
      }
    }
    _ => -1
  }
  pace.at = t
  pace.rung = rung
  if rung >= 0 {
    pace_rates[rung]
  } else {
    0.0
  }
}

///|
/// The frame asked for the next for something besides the clock, or for none: drawn when the host draws it.
fn pace_none() -> Unit {
  pace.at = -1.0
  pace.rung = -1
}
