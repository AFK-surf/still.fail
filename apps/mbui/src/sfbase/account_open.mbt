// An account's page opened only once what it shows is answered. Its page reads its station (`station`: the profile as
// the station has it) and the account (`profile`, one account whole: views/views.ts), and the list it is opened from
// holds neither (its rows are what they draw, ProfileRow), so an account's page opened at the press would show its
// bones till they came, where it opened whole before the list's rows were rows. So the press asks them, and the page
// opens as they are answered (press_wait: at once where they are already, else the moment they are, while what it was
// pressed in stays as it was); meanwhile the screen stays as it was (the coordinator of the migration, 2026-11-12:
// opening an account's page draws no bones). So too a choice that switches what its page reads (switch_answered).

///|
/// The workspace a station's topics are asked of (settings' station_scope): its address's, `ws` for one without it.
fn account_scope(ws : String, station : String) -> String {
  if station.contains("/") {
    @settings.workspace_of(station)
  } else {
    ws
  }
}

///|
/// What a profile's page on station `station` (of workspace `ws`), profile `id`, reads as it opens: its station whole
/// and the account it is of (settings' station_read, profile_read).
pub fn profile_page_asks(ws : String, station : String, id : String) -> Array[(String, Map[String, Json])] {
  let scope = Json::string(account_scope(ws, station))
  [
    ("station", { "scope": scope, "station": Json::string(station) }),
    ("profile", { "scope": scope, "station": Json::string(station), "id": Json::string(id) }),
  ]
}

///|
/// What an account's page of all its stations reads as it opens: the account by its key (settings'
/// profile_by_key_read).
pub fn account_page_asks(ws : String, key : String) -> Array[(String, Map[String, Json])] {
  [("profile", { "scope": Json::string(ws), "key": Json::string(key) })]
}

///|
/// What the settings' route `r` reads of the core before it may open (open_answered): a profile's page and an
/// account's; none for any other route, which opens at once.
pub fn route_asks(ws : String, r : @settings.Route) -> Array[(String, Map[String, Json])] {
  match r {
    Profile(station, id) => profile_page_asks(ws, station, id)
    ProfileAccount(key) => account_page_asks(ws, key)
    _ => []
  }
}

///|
/// `asks` asked of `src` now and held by what is returned till what opens has read them: whether each is answered (a
/// value, or an error the page says), and what holds them.
fn asked_now(src : Source, asks : Array[(String, Map[String, Json])]) -> (() -> Bool, Array[TopicLease]) {
  let leases = asks.map(fn(a) { src.lease_topic(a.0, a.1) })
  let answered = fn() {
    leases.iter().all(fn(l) {
      match l.follow() {
        Some(t) => t.value is Some(_) || t.error is Some(_)
        // (let go of: nothing to wait for)
        None => true
      }
    })
  }
  (answered, leases)
}

///|
/// `open` (what puts an account's page on top: the settings' push) done once each of `asks` is answered, asked of `src`
/// now; at once where they are answered already. What they ask is handed to the entry `open` puts on top, which takes
/// it as its view is made and lets it go at the end of the frame of its first build (pages.mbt hand_over); let go at
/// once where nothing was put on top, and where the press waits no more, with what else the press opened for it
/// (`let_go`: a draft the page was to show). Made in a press's handler, as press_wait is. What waits is returned: given
/// up by the press's control where a press after it asks for another.
pub fn open_answered(
  src : Source,
  asks : Array[(String, Map[String, Json])],
  open : () -> Unit,
  let_go? : () -> Unit = fn() {  },
) -> PressWait {
  if asks.is_empty() || src.read_only {
    return press_wait(fn() { true }, open)
  }
  let (answered, leases) = asked_now(src, asks)
  press_wait(answered, fn() { hand_over(leases, open) }, let_go=fn() {
    leases.each(fn(l) { l.cancel() })
    let_go()
  })
}

///|
/// `show` (what shows an account's page in a pane in place of the one there, no entry put on top: a place's side
/// list's pick) done once each of `asks` is answered, as open_answered; what they ask handed to the page shown for
/// `at`, taken as it is first built and let go at that frame's end (pages.mbt hand_over_shown, shown_read).
pub fn show_answered(src : Source, asks : Array[(String, Map[String, Json])], at : String, show : () -> Unit) -> Unit {
  if asks.is_empty() || src.read_only {
    show()
    return
  }
  let (answered, leases) = asked_now(src, asks)
  press_wait(answered, fn() { hand_over_shown(at, leases, show) }, let_go=fn() { leases.each(fn(l) { l.cancel() }) })
  |> ignore
}

///|
/// A choice that switches what the same page reads (用量's days and split), nothing made anew to take what it asks.
/// Pressed, `asks` (what the page reads as it is first drawn for that choice, said by the code it reads by) are asked of
/// `src` now; the page stays as it is meanwhile, the choice showing what was pressed by a state of its own. Once each is
/// answered (at once where they are already), `switch_to` writes what the page reads by, told as what the answer tells
/// (view's `answering`: what it changes comes whole, no way set out by it), at the end of what is running (the press's
/// event, the answer's, the frame): a switch told while a frame is being built would show part of each in it. What was
/// asked is handed over with it to the page's readers by `at` (hand_over_shown): each that reads it anew says so as it
/// has read it (shown_read), and the leases are let go at the end of that frame, its subscriptions then its readers' own.
/// Given up (press_wait: the page left, the workspace switched, something else put up; and by its caller where another
/// choice is pressed, by the PressWait returned), what was asked is let go and `let_go` run (the choice put back to what
/// is shown).
pub fn switch_answered(
  src : Source,
  asks : Array[(String, Map[String, Json])],
  at : String,
  switch_to : () -> Unit,
  let_go? : () -> Unit = fn() {  },
) -> PressWait {
  // (told while a frame is drawn, after it brought the window's tree: at that frame's end, so the frame shows the page
  // wholly as it was, never its words read anew over what is laid out as it was; in a press or between frames, at the
  // end of that event, before the next frame)
  let told = fn() { @ui.after_frame(fn() { @view.answering(switch_to) }) }
  // (asking nothing ahead where the source's run did not: a replay of a run from before, switched at the press)
  if asks.is_empty() || src.read_only || !(src.switches_ahead)() {
    return press_wait(fn() { true }, told)
  }
  let (answered, leases) = asked_now(src, asks)
  // (what was asked handed over with the switch, so the frame its readers read it anew in is the one after it)
  let go = fn() { @ui.after_frame(fn() { hand_over_shown(at, leases, fn() { @view.answering(switch_to) }) }) }
  press_wait(answered, go, let_go=fn() {
    leases.each(fn(l) { l.cancel() })
    let_go()
  })
}
