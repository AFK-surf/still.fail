// The system's own bars for the app's places and actions (@hostapi.nav_bar: an iPhone Duo's, iOS 27.1), as this
// frame has them: the one place the shell, the pages and the library's parts ask whether they are there and what of
// the window they take. sfdesk's rail_native.mbt hands the bars over and says here what came of it, once a frame;
// nothing else writes it. Where they are not (every other device: the host says it has none), `on` is false, every
// question here answers as it does without them, and what reads it is as it was.

///|
/// The system's bars this frame.
pub(all) struct NativeBars {
  /// whether the system shows the app's tabs now (they were handed it and it took them), a signal: what is laid out by
  /// them (the window's sides beside the bars) follows it
  on : @signals.Signal[Bool]
  /// how wide its column down the window's trailing edge is (0: across the top and foot upright, or none), a signal:
  /// what is laid out beside it (the tape's panels) follows it
  side : @signals.Signal[Double]
  /// the screen's corners where the cards along its edges follow them, each its own (top left, then round it: an
  /// iPhone Duo's outer screen 8 along its hinge, 59 on the other side; 0: the window's own, as elsewhere)
  corners : FixedArray[Double]
}

///|
// kept across runs: rail_native.mbt says it again each frame, native_bars_reset as the app begins anew
pub let native_bars : NativeBars = {
  on: @signals.signal(false, same=fn(a, b) { a == b }),
  side: @signals.signal(0.0, same=fn(a, b) { a == b }),
  corners: FixedArray::make(4, 0.0),
}

///|
/// As at the start: none.
pub fn native_bars_reset() -> Unit {
  native_bars.on.set(false)
  native_bars.side.set(0.0)
  native_bars.corners.fill(0.0)
  native_foot_made.val = None
  native_over_clear()
}

///|
/// Whether this device's system lays out the app's tabs itself in every pose of its screens (an iPhone Duo's), whether
/// or not the frame hands it any now: the app's frame then the same on each screen (one layout, the cards across).
pub fn native_able() -> Bool {
  @hostapi.nav_bar_able()
}

///|
/// Whether the system shows the app's tabs this frame.
pub fn native_on() -> Bool {
  native_bars.on.get()
}

///|
/// Whether its bars run down the window's trailing edge (on its side, its outer screen): the app's actions in that
/// column; upright they are across the top and foot.
pub fn native_side() -> Bool {
  native_bars.on.get() && native_bars.side.get() > 0.0
}

///|
/// How far in from the window's trailing edge what is pressed keeps clear of the column (0 where there is none).
pub fn native_clear() -> Double {
  if native_bars.on.get() {
    native_bars.side.get()
  } else {
    0.0
  }
}

///|
/// How much of the window's foot the system's tabs take across it (upright: the safe area's foot, the home indicator's
/// line with them), what is over the window's whole keeps clear of (a toast); 0 where they are not there.
pub fn native_foot() -> Double {
  if native_bars.on.get() && native_bars.side.get() == 0.0 {
    @ui.system_bars().bottom
  } else {
    0.0
  }
}

///|
/// How high a capsule across a card's foot stands beside the system's action at the column's foot (iOS 27's prominent
/// tab, an iPhone Duo's round one: @ui.system_nav_action): as high as it, so the two are one row (the user, 2026-10-28:
/// 输入框跟右边的对上); None where there is none (every other device, upright, none said).
pub fn native_capsule_h() -> Double? {
  if !native_side() {
    return None
  }
  match @ui.system_nav_action() {
    Some((_, _, _, h)) => Some(h)
    None => None
  }
}

///|
/// The cards' foot corners away from the screen's edges, their feet at `foot` in the window, beside the system's action
/// at the column's foot: the corner a capsule as high as the action (native_capsule_h), its foot on the action's,
/// stands concentric in (as far in from a card's side as from its foot), each card's the same so the gaps between them
/// run even (the user, 2026-10-28: 左边圆角也对齐); none where there is no action, or it is not over their feet (the
/// keyboard up: under it). Said by the frame once a frame, before its cards; tape_corners reads it (native_foot_corner).
/// Whether it is another than the last frame's (what was kept of the cards, drawn cut by their corners, is drawn anew).
pub fn native_foot_set(foot : Double) -> Bool {
  let was = native_foot_made.val
  native_foot_made.val = match (native_capsule_h(), @ui.system_nav_action()) {
    (Some(h), Some((_, y, _, _))) => {
      let d = foot - (y + h)
      if d < corner_fit.near || d > h {
        None
      } else {
        Some(@ui.round_like_out(h / 2.0 + d))
      }
    }
    _ => None
  }
  native_foot_made.val != was
}

///|
/// The cards' foot corners away from the screen's edges as native_foot_set said them this frame (None: the tape's own).
pub fn native_foot_corner() -> Double? {
  native_foot_made.val
}

///|
/// Whether a panel's foot left corner `r` round is one native_foot_corner made this frame (beside the system's action).
fn native_foot_corner_now(r : Double) -> Bool {
  native_foot_made.val is Some(m) && (m - r).abs() < 1.0e-6
}

///|
// kept across runs: said by native_foot_set as the frame lays out the cards, None as the app begins anew
let native_foot_made : Ref[Double?] = Ref(None)

///|
/// How far the cards stand from the window's edges and from each other beside the system's tabs (the user,
/// 2026-10-26: room for what is in use).
pub let native_in : Double = 4.0

///|
/// The corner of the cards in the screen's corner `k` (top left, then round it), beside the system's tabs (placed
/// native_in from its edges from the frame they are its, bar_in_now): concentric with the
/// screen's own there, so the screen cuts none of a card's line (the user, 2026-10-27), each corner its own (an iPhone
/// Duo's outer screen: along its hinge, its 8, the cards' 4); 0 where it says none.
pub fn native_card_corner_at(k : Int) -> Double {
  let r = native_bars.corners[k]
  if native_bars.on.get() && r > 0.0 {
    @ui.concentric(r, native_in)
  } else {
    0.0
  }
}

///|
/// The roundest of the cards' corners in the screen's (native_card_corner_at); 0 where it says none.
pub fn native_card_corner() -> Double {
  let mut most = 0.0
  for k in 0..<4 {
    most = dmax(most, native_card_corner_at(k))
  }
  most
}

// ---- what is up over the whole window (the viewer): the system's tabs put away while it is, its actions in their
// bars in place of its own (the user, 2026-10-27: as Slack's). Said by it as it is built, and kept as it said them
// while it is up (its `alive`), whether it is built again in a frame or its part kept as it was; rail_native.mbt
// hands them over as the frame ends, gone once it is not (native_over_gone). Not cleared as each frame starts: a part
// kept from a frame before says nothing again, and the bars would hand the tabs for that frame and its actions again
// after it, the system fading between them (the user, 2026-11-01: 打开图片时不停闪烁).

///|
/// What is over the whole window this frame: whether it is up, its title, its actions (an id, words, an icon's name,
/// what it does chosen) in their order.
pub(all) struct NativeOver {
  mut up : Bool
  mut title : String
  acts : Array[(String, String, String, () -> Unit)]
  active : Array[String]
  /// Whether what said them is still up (its page shown, the viewer open and not closing)
  mut alive : () -> Bool
}

///|
// kept across runs: put back as what said it is gone (native_over_gone), native_bars_reset as the app begins anew
pub let native_over : NativeOver = { up: false, title: "", acts: [], active: [], alive: fn() { false } }

///|
/// One of what has said it is up over the whole window (native_over_up): what it said, kept as it said it while it is
/// alive, by what said it (`owner`) and how high over the rest it is (`over`: the viewer over the pages it is opened
/// from).
struct NativeClaim {
  over : Int
  /// when it was said, in the order of all said (native_said_n): of two as high, the one said last handed
  said : Int
  title : String
  acts : Array[(String, String, String, () -> Unit)]
  active : Array[String]
  alive : () -> Bool
}

///|
// kept across runs: what has said it is up, by what said it (its owner), put back as each is gone
// (native_over_gone), all of them by native_over_clear as the app begins anew
let native_claims : Map[String, NativeClaim] = Map([])

///|
// kept across runs: what said it is up last (native_over_up), what its actions are said for (native_over_act)
let native_claiming : Ref[String] = Ref("")

///|
// kept across runs: how many times one has said it is up (native_over_up), each claim's `said` its count then
let native_said_n : Ref[Int] = Ref(0)

///|
/// What is handed to the system's bars (native_over): of what has said it is up and is still, the one highest over the
/// rest, of two as high the one that said it last (each claim's `said`); none, none up. A page under the viewer saying
/// it again as it is built takes nothing of the viewer's place there.
fn native_over_publish() -> Unit {
  let mut top : NativeClaim? = None
  for _, c in native_claims {
    match top {
      Some(t) if t.over > c.over || (t.over == c.over && t.said > c.said) => ()
      _ => top = Some(c)
    }
  }
  match top {
    Some(c) => {
      native_over.up = true
      native_over.title = c.title
      native_over.acts.clear()
      native_over.acts.append(c.acts)
      native_over.active.clear()
      native_over.active.append(c.active)
      native_over.alive = c.alive
    }
    None => {
      native_over.up = false
      native_over.title = ""
      native_over.acts.clear()
      native_over.active.clear()
      native_over.alive = fn() { false }
    }
  }
}

///|
/// None up.
pub fn native_over_clear() -> Unit {
  native_claims.clear()
  native_claiming.val = ""
  native_said_n.val = 0
  native_over_publish()
}

///|
/// What said it no longer up (its `alive`) let go of, the one under it handed in its place, or none: the tabs back;
/// asked as the frame ends, before the bars are handed. While one is, what it said last stays, built again this frame
/// or not.
pub fn native_over_gone() -> Unit {
  let gone = []
  for k, c in native_claims {
    if !(c.alive)() {
      gone.push(k)
    }
  }
  for k in gone {
    native_claims.remove(k)
  }
  native_over_publish()
}

///|
/// Something is up over the whole window this frame, `title` its name: the system's tabs put away while it is. True
/// where the system's bars are (native_on): it then hands them its actions (native_over_act) for what it would
/// draw of its own; false elsewhere, nothing done. Its actions are one set, said whole as it is built: this begins
/// its set anew, in place of what it said before, so an action it no longer says is gone. Kept as said while `alive`
/// (it is still up: its page shown, the viewer open), whether it is built again or not; gone as the frame ends once it
/// is not (native_over_gone). Each by what says it (`owner`), `over` the rest as high as it is (a page 0, a full
/// visualization 1, the viewer 2): what is handed is the highest of them (native_over_publish), of two as high the one
/// said last.
pub fn native_over_up(title : String, alive~ : () -> Bool, owner? : String = "page", over? : Int = 0) -> Bool {
  if !native_bars.on.get() {
    return false
  }
  native_said_n.val += 1
  native_claims[owner] = { over, said: native_said_n.val, title, acts: [], active: [], alive }
  native_claiming.val = owner
  native_over_publish()
  true
}

///|
/// One of its actions in the system's bars (`id`, its words, an icon's name; `lead`: at the bar's lead, where the
/// system puts back and close), `act` what it does chosen, for what said it is up last (native_over_up). `active`: the
/// panel it controls is open, shown in the accent. One action an id in the set: said twice, the one said last, in its
/// place.
pub fn native_over_act(id : String, title : String, icon : String, act : () -> Unit, lead? : Bool = false, active? : Bool = false) -> Unit {
  let c = match native_claims.get(native_claiming.val) {
    Some(c) => c
    None => return
  }
  let key = (if lead { "lead/over/" } else { "over/" }) + id
  let at = c.acts.search_by(fn(a) { a.0 == key })
  match at {
    Some(i) => c.acts[i] = (key, title, icon, act)
    None => c.acts.push((key, title, icon, act))
  }
  c.active.retain(fn(k) { k != key })
  if active {
    c.active.push(key)
  }
  native_over_publish()
}
