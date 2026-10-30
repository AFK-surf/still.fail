// A touch screen's fingers as each host has them (each by the system's own id for it, from its down to its end:
// Android's pointer id, a UITouch, a GDK sequence, a Windows pointer id) made the app's two: the pointer's (0 down,
// 1 moved, 2 up, 3 called off) and the second's (4 down, 5 moved, 6 up), the first let go while the second is down 8
// (the second the first from then on, the same finger: its moves come as the first's). A finger down while two are is
// none of the app's to its end, whatever is let go meanwhile: no finger is told whose down was not. One called off
// (the system took it, the window no longer the app's) calls all of it off: told once (3), as where it was, both let
// go, nothing more of either told. The hosts hand each finger's events on as they come (pointer kinds 10 down, 11
// moved, 12 up, 13 called off, the system's id where a press's button goes); what they come to is the app's input, as
// it is kept on a tape (inputrec.mbt) and given again.

///|
/// The system's ids of the app's two fingers (any number, a negative one too), and whether each is there.
// kept across runs: put back as a run begins (touches_forget)
let touch_slots : FixedArray[Int] = FixedArray::make(2, 0)

///|
// kept across runs: put back as a run begins (touches_forget)
let touch_down : FixedArray[Bool] = FixedArray::make(2, false)

///|
/// As a run begins, or the window is no longer the app's: no finger down of the app's.
fn touches_forget() -> Unit {
  touch_down[0] = false
  touch_down[1] = false
}

///|
/// A finger's event as the host has it (`phase`: 0 down, 1 moved, 2 up, 3 called off; `id`: the system's for it):
/// the app's pointer kind it comes to (as above), -1 none.
fn touch_kind(phase : Int, id : Int) -> Int {
  let first = touch_down[0] && touch_slots[0] == id
  let second = touch_down[1] && touch_slots[1] == id
  match phase {
    0 =>
      if !touch_down[0] {
        touch_slots[0] = id
        touch_down[0] = true
        0
      } else if !touch_down[1] && !first {
        touch_slots[1] = id
        touch_down[1] = true
        4
      } else {
        -1
      }
    1 => if first { 1 } else if second { 5 } else { -1 }
    2 =>
      if second {
        touch_down[1] = false
        6
      } else if first && touch_down[1] {
        touch_slots[0] = touch_slots[1]
        touch_down[1] = false
        8
      } else if first {
        touch_down[0] = false
        2
      } else {
        -1
      }
    3 =>
      if first || second {
        touches_forget()
        3
      } else {
        -1
      }
    _ => -1
  }
}

///|
/// The window no longer the app's: a finger of the app's down called off (3), all of it, as any called off is.
fn touches_off() -> Unit {
  if touch_down[0] || touch_down[1] {
    touch_in(3, if touch_down[0] { touch_slots[0] } else { touch_slots[1] }, last_touch_x.val, last_touch_y.val)
  }
}

///|
/// Where the app's first finger was last told (what one called off by the window says).
// kept across runs: where one is called off
let last_touch_x : Ref[Double] = Ref(0.0)

///|
// kept across runs: where one is called off
let last_touch_y : Ref[Double] = Ref(0.0)

///|
/// A finger's event from the host (above), as one event at its own moment (view_host.mbt): what was due before it done
/// first, then what it comes to worked out and taken as the app's pointer's, in the same event (what was due never
/// sees a finger not down yet, nor misses one that is).
fn touch_in(phase : Int, id : Int, x : Double, y : Double) -> Unit {
  view_event(fn() {
    let kind = touch_kind(phase, id)
    if kind >= 0 && kind <= 3 {
      last_touch_x.val = x
      last_touch_y.val = y
    }
    if kind >= 0 {
      // (in this event: at its moment)
      pointer_in(kind, x, y, 0, if kind == 0 { mods_held() } else { 0 }, by=1)
    }
  })
}
