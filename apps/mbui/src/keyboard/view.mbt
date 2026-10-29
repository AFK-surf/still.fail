// The keyboard as the system's input method (mbui's Keyboard.java: what it says on channel "keyboard" and what it is
// asked): the bar (what is being typed and its candidates, picked by a tap; else the scheme and putting it away),
// and the keys (keys.mbt), typed with any finger: each finger's down and up as the host says them, a key going in as
// its finger lifts or as another finger comes down (two thumbs one after the other), Back and Shift as they come down,
// Back again and again while held.

///|
/// One finger on the keys: which key, since when, whether its key has gone in, and Back's repeats so far.
priv struct Finger {
  cap : Int
  at : Double
  mut done : Bool
  mut repeats : Int
}

///|
priv struct State {
  board : Board
  /// where the keyboard keeps its files (MBUI_KEYBOARD_DIR)
  dir : String
  mut caps : Array[Cap]
  fingers : Map[Int, Finger]
  /// a new set of candidates (their strip back at its start)
  mut offered : Int
  /// dp a unit (keys.mbt: the keyboard's width over WeChat's 1080)
  mut scale : Double
}

///|
let state : Ref[State?] = Ref::new(None)

///|
/// Back held this long goes again, then every `repeat_ms`.
let repeat_after_ms : Double = 400.0

///|
let repeat_ms : Double = 50.0

///|
fn scheme_of(text : String) -> @pinyin.Scheme {
  if text.contains("scheme=full") {
    Full
  } else {
    Xiaohe
  }
}

///|
/// The keyboard's state, made as it is first drawn: its words read (a moment, once), what the person picked before,
/// the scheme chosen.
fn made() -> State {
  match state.val {
    Some(s) => s
    None => {
      let dir = @ui.env("MBUI_KEYBOARD_DIR")
      let composer = match @pinyin.Dict::load(dir + "/words.txt") {
        Some(d) => {
          let learned = match @pinyin.read_text(dir + "/learned.txt") {
            Some(t) => @pinyin.Learned::parse(t, d)
            None => @pinyin.Learned::new()
          }
          let scheme = scheme_of(@pinyin.read_text(dir + "/settings.txt").unwrap_or(""))
          Some(@pinyin.Composer::new(d, scheme, learned~))
        }
        None => None
      }
      let s = {
        board: Board::new(composer),
        dir,
        caps: [],
        fingers: Map([]),
        offered: 0,
        scale: 1.0,
      }
      state.val = Some(s)
      s
    }
  }
}

///|
/// What goes to the field, handed to the host; what the person picked kept once pinyin went in.
fn send(s : State, outs : Array[Out]) -> Unit {
  for o in outs {
    match o {
      Commit(t) => {
        if t != "" {
          let said : Map[String, Json] = Map([])
          said["text"] = Json::string(t)
          @ui.native_call("keyboard.commit", Json::object(said)) |> ignore
        }
      }
      Delete => @ui.native_call("keyboard.delete", Json::object(Map([]))) |> ignore
      Enter => @ui.native_call("keyboard.enter", Json::object(Map([]))) |> ignore
    }
  }
  match s.board.composer {
    Some(c) if outs.length() > 0 && s.board.chinese =>
      @pinyin.write_text(s.dir + "/learned.txt", c.learned.to_text(c.dict)) |> ignore
    _ => ()
  }
  s.offered += 1
}

///|
/// Finger `f`'s key gone in.
fn tap(s : State, f : Finger) -> Unit {
  if f.done || f.cap < 0 || f.cap >= s.caps.length() {
    return
  }
  f.done = true
  send(s, s.board.tap(s.caps[f.cap].key, @ui.current().moment()))
}

///|
/// What the host said (Keyboard.java's channel).
fn heard(json : String) -> Unit {
  let s = made()
  let m = match (try Some(@json.parse(json)) catch { _ => None }) {
    Some(Object(m)) => m
    _ => return
  }
  match m.get("start") {
    Some(Object(st)) => {
      let kind = match st.get("kind") {
        Some(String(k)) => k
        _ => "text"
      }
      let action = match st.get("action") {
        Some(String(a)) => a
        _ => "enter"
      }
      s.board.start(kind, action)
      s.fingers.clear()
      s.offered += 1
    }
    _ => ()
  }
  match m.get("finish") {
    Some(True) => {
      // what was being typed goes in as it was, not lost
      match s.board.composer {
        Some(c) if c.active() => {
          let typed = c.as_typed()
          c.clear()
          send(s, [Commit(typed)])
        }
        _ => ()
      }
      s.fingers.clear()
    }
    _ => ()
  }
  match m.get("touch") {
    Some(Object(t)) => {
      let id = match t.get("id") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      let num = fn(k : String) {
        match t.get(k) {
          Some(Number(n, ..)) => n
          _ => 0.0
        }
      }
      match t.get("kind") {
        Some(String("down")) => {
          let cap = cap_at(s.caps, num("x") / s.scale, num("y") / s.scale)
          if cap < 0 {
            return
          }
          // another finger came down while these were held: their keys go in first, in the order they came
          let held = s.fingers.values().collect()
          held.sort_by(fn(a, b) { if a.at < b.at { -1 } else if a.at > b.at { 1 } else { 0 } })
          for f in held {
            match s.caps.get(f.cap) {
              Some({ key: Back, .. }) => ()
              _ => tap(s, f)
            }
          }
          let f = { cap, at: @ui.current().moment(), done: false, repeats: 0 }
          s.fingers[id] = f
          @ui.haptic(KeyboardTap)
          // Back and Shift as they come down (Shift held with a letter: a capital)
          match s.caps[cap].key {
            Back | ShiftKey => tap(s, f)
            _ => ()
          }
        }
        Some(String("up")) =>
          match s.fingers.get(id) {
            Some(f) => {
              s.fingers.remove(id)
              tap(s, f)
            }
            None => ()
          }
        Some(String("cancel")) => s.fingers.remove(id)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
/// Colours (WeChat's keyboard's, its themes' ime_color_*), light and dark.
priv struct Paint {
  /// the keyboard's ground, from its top to its foot
  top : Int64
  foot : Int64
  light : Int64
  light_pressed : Int64
  grey : Int64
  grey_pressed : Int64
  green : Int64
  ink : Int64
  on_green : Int64
  quiet : Int64
  edge : Int64
  shadow : Int64
  grey_shadow : Int64
  /// the first candidate's words
  first : Int64
}

///|
fn paint() -> Paint {
  if @ui.system_dark() {
    {
      top: 0x2B2B2BFFL,
      foot: 0x262626FFL,
      light: 0x5F5F5FFFL,
      light_pressed: 0x414141FFL,
      grey: 0x414141FFL,
      grey_pressed: 0x5F5F5FFFL,
      green: 0x23C891FFL,
      ink: 0xFFFFFFE6L,
      on_green: 0x000000FFL,
      quiet: 0xFFFFFF66L,
      edge: 0xFFFFFF1AL,
      shadow: 0x0000008CL,
      grey_shadow: 0x0000008CL,
      first: 0x23C891FFL,
    }
  } else {
    {
      top: 0xE5E6EBFFL,
      foot: 0xD5D7DDFFL,
      light: 0xFCFCFCFFL,
      light_pressed: 0xB7BCC4FFL,
      grey: 0xB7BCC4FFL,
      grey_pressed: 0xFCFCFCFFL,
      green: 0x23C891FFL,
      ink: 0x000000E6L,
      on_green: 0xFFFFFFFFL,
      quiet: 0x00000066L,
      edge: 0x0000001AL,
      shadow: 0x00000026L,
      grey_shadow: 0x0000003FL,
      first: 0x16AC66FFL,
    }
  }
}

///|
/// `top` (its alpha its own) laid over the opaque `under` (RRGGBBAA).
fn over(under : Int64, top : Int64) -> Int64 {
  mix(under, top | 0xFFL, (top & 0xFFL).to_double() / 255.0)
}

///|
/// `a` to `b`, `t` of the way (each channel; RRGGBBAA).
fn mix(a : Int64, b : Int64, t : Double) -> Int64 {
  let mut out = 0L
  for k in 0..<4 {
    let sh = k * 8
    let x = ((a >> sh) & 0xFFL).to_double()
    let y = ((b >> sh) & 0xFFL).to_double()
    let v = (x + (y - x) * t + 0.5).to_int64()
    out = out | (v << sh)
  }
  out
}

///|
/// How many bands the ground's fall from its top colour to its foot's is drawn in (the two are 16 steps apart).
let ground_bands : Int = 16

///|
/// A round button of the bar's (WeChat's 90 units across), its words or icon in it.
fn bar_button(c : @ui.Ctx, s : State, p : Paint, x : Double, id : Int, body : () -> Unit) -> Unit {
  let u = s.scale
  c.box(
    id~,
    left=x * u,
    top=41.0 * u,
    w=Px(90.0 * u),
    h=Px(90.0 * u),
    radius=45.0 * u,
    bg=if c.pressed(id) { p.light_pressed } else { p.light },
    align=ACenter,
    justify=JCenter,
    body,
  )
  |> ignore
}

///|
/// The bar: what is being typed over its candidates, the first WeChat's green, each picked by a tap; else the scheme
/// (a tap: the other), the next input method and putting the keyboard away.
fn bar(c : @ui.Ctx, s : State, p : Paint, w : Double) -> Unit {
  let u = s.scale
  match s.board.composer {
    Some(comp) if s.board.composing() => {
      c.box(left=13.0 * u, top=2.0 * u, h=Px(52.0 * u), justify=JCenter, fn() {
        c.text(comp.preedit(), size=40.0 * u, color=p.ink, wrap=false) |> ignore
      })
      |> ignore
      c.box(left=0.0, top=60.0 * u, w=Px(w - 120.0 * u), h=Px(94.0 * u), fn() {
        c.sideways("candidates" + s.offered.to_string(), pad=0.0, fn() {
          c.row(gap=14.0 * u, padx=13.0 * u, h=Px(94.0 * u), fn() {
            let cands = comp.candidates()
            for i, cand in cands {
              if i >= candidates_most {
                break
              }
              let id = c.id("candidate/" + i.to_string())
              let lit = i == 0 || c.pressed(id)
              c.box(
                id~,
                padx=26.0 * u,
                h=Px(94.0 * u),
                justify=JCenter,
                radius=20.0 * u,
                bg=if lit { p.light } else { 0L },
                fn() {
                  c.text(cand.text, size=50.0 * u, color=if i == 0 { p.first } else { p.ink }, wrap=false)
                  |> ignore
                },
              )
              |> ignore
              if c.clicked(id) {
                send(s, s.board.pick(i))
              }
            }
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
      // (WeChat's: all the candidates opened under it; for now the strip scrolls)
      c.box(left=w - 107.0 * u, top=60.0 * u, w=Px(107.0 * u), h=Px(94.0 * u), align=ACenter, justify=JCenter, fn() {
        @sf.icon(c, "chevron-down", size=48.0 * u, color=p.ink) |> ignore
      })
      |> ignore
    }
    _ => {
      match s.board.composer {
        Some(comp) if s.board.chinese => {
          let id = c.id("scheme")
          bar_button(c, s, p, 36.0, id, fn() {
            let words = if comp.scheme() == Xiaohe { "鹤" } else { "全" }
            c.text(words, size=40.0 * u, color=p.ink) |> ignore
          })
          if c.clicked(id) {
            let next : @pinyin.Scheme = if comp.scheme() == Xiaohe { Full } else { Xiaohe }
            comp.set_scheme(next)
            let said = if next == Full { "scheme=full\n" } else { "scheme=xiaohe\n" }
            @pinyin.write_text(s.dir + "/settings.txt", said) |> ignore
          }
        }
        _ => ()
      }
      let other = c.id("other")
      bar_button(c, s, p, 828.0, other, fn() {
        @sf.icon(c, "keyboard", size=48.0 * u, color=p.ink) |> ignore
      })
      if c.clicked(other) {
        @ui.native_call("keyboard.switch", Json::object(Map([]))) |> ignore
      }
      let hide = c.id("hide")
      bar_button(c, s, p, 954.0, hide, fn() {
        @sf.icon(c, "chevron-down", size=48.0 * u, color=p.ink) |> ignore
      })
      if c.clicked(hide) {
        @ui.native_call("keyboard.hide", Json::object(Map([]))) |> ignore
      }
    }
  }
}

///|
/// The most candidates put in the bar's strip.
let candidates_most : Int = 60

///|
/// The keys: each drawn as WeChat's are (an Android drawable's order): its shadow (3 units under it), its edge (a
/// line a unit wide on its outline, half outside it, half over its own ground), then its ground; a finger on it
/// showing its pressed colour. (An mbui border is over what is behind its box, not over its own ground: the edge's
/// outer half is a box half a unit larger behind the key, its inner half the key's border in the edge's colour over
/// its ground, so neither shows the shadow through it, which was a dark ring round each key.)
fn keys(c : @ui.Ctx, s : State, p : Paint) -> Unit {
  let u = s.scale
  let down : Map[Int, Bool] = Map([])
  for _, f in s.fingers {
    down[f.cap] = true
  }
  for i, k in s.caps {
    let pressed = down.contains(i) || (k.key == ShiftKey && s.board.shift != Off)
    let (bg, shadow, ink) = match k.look {
      Light => (if pressed { p.light_pressed } else { p.light }, p.shadow, p.ink)
      Grey => (if pressed { p.grey_pressed } else { p.grey }, p.grey_shadow, p.ink)
      Green => (if pressed { p.grey } else { p.green }, p.grey_shadow, p.on_green)
    }
    let size = match k.key {
      Letter(_) => 60.0
      Words(_) => 60.0
      Back | ShiftKey => 56.0
      _ => 44.0
    }
    c.box(left=k.x * u, top=(k.y + 3.0) * u, w=Px(k.w * u), h=Px(k.h * u), radius=16.0 * u, bg=shadow, fn() {  })
    |> ignore
    c.box(
      left=(k.x - 0.5) * u,
      top=(k.y - 0.5) * u,
      w=Px((k.w + 1.0) * u),
      h=Px((k.h + 1.0) * u),
      radius=16.5 * u,
      bg=p.edge,
      fn() {  },
    )
    |> ignore
    c.box(
      left=k.x * u,
      top=k.y * u,
      w=Px(k.w * u),
      h=Px(k.h * u),
      radius=16.0 * u,
      bg~,
      border=0.5 * u,
      border_color=over(bg, p.edge),
      align=ACenter,
      justify=JCenter,
      fn() {
        match k.key {
          // 中 over 英 (or 英 over 中), the other one small at its foot's right
          Lang => {
            c.text(k.label, size=46.0 * u, color=ink, wrap=false) |> ignore
            c.text(k.small, size=30.0 * u, color=p.quiet, wrap=false) |> ignore
          }
          // ， with 。 small over it
          Words(_) if k.small != "" => {
            c.text(k.small, size=30.0 * u, color=p.quiet, wrap=false) |> ignore
            c.text(k.label, size=size * u, color=ink, wrap=false) |> ignore
          }
          _ => c.text(k.label, size=size * u, color=ink, wrap=false) |> ignore
        }
      },
    )
    |> ignore
  }
}

///|
/// A frame of the keyboard.
fn frame(c : @ui.Ctx) -> Unit {
  let s = made()
  let (w, _) = c.window_size()
  s.scale = w / unit_width
  s.caps = caps(s.board)
  // Back held: again after a while, then again and again
  for id, f in s.fingers {
    match s.caps.get(f.cap) {
      Some({ key: Back, .. }) => {
        let held = c.moment() - f.at
        let due = if held < repeat_after_ms {
          0
        } else {
          1 + ((held - repeat_after_ms) / repeat_ms).to_int()
        }
        // (what is due goes in once the frame's builds are over: each works it out alike)
        c.after_build("back-repeat/" + id.to_string(), fn() {
          while f.repeats < due {
            f.repeats += 1
            send(s, s.board.back())
          }
        })
        let next = repeat_after_ms + due.to_double() * repeat_ms
        c.wake_in(next - held)
      }
      _ => ()
    }
  }
  let p = paint()
  c.box(w=Fill(1.0), h=Fill(1.0), bg=p.foot, fn() {
    // the ground: its top colour falling to its foot's, under the bar and the keys
    let band = board_h * s.scale / ground_bands.to_double()
    for b in 0..<ground_bands {
      let t = b.to_double() / (ground_bands - 1).to_double()
      c.box(left=0.0, top=b.to_double() * band, w=Px(w), h=Px(band + 1.0), bg=mix(p.top, p.foot, t), fn() {  })
      |> ignore
    }
    bar(c, s, p, w)
    keys(c, s, p)
  })
  |> ignore
}

///|
/// The keyboard run as the program (src/stillfail's main, told MBUI_KEYBOARD by Keyboard.java).
pub fn run() -> Unit {
  @ui.on_message("keyboard", fn(json, _) { heard(json) })
  @ui.run("keyboard", frame)
}
