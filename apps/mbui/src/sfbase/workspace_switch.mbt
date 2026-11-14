// A workspace switched (the workspaces' list's row, the rail's key, a shortcut): nothing looks like loading within
// switch_wait_ms of the press (the user, 2026-11-11: 「在三百 ms 内都不应该让用户感觉到加载」). The screen stays as it was
// till all the new workspace's first screen reads is answered, that long at most; where it is answered already, the
// press's own handler switches, drawn in its frame (「按理说一帧就能处理完」).
//
// What the press put up to choose by (the workspaces' sheet on 小屏, its popover on 中屏 and 大屏, a dialog that made or
// joined one) is part of the screen as it was: it is closed at the moment the switch is done (`closes`), with it, so its
// closing motion sets out from the switch's own frame, not from the press's with the switch falling in its middle (the
// owner on a phone, 0.1.8610: 「现在切 workspace 时收起抽屉不流畅，会卡帧」: the new Home made in a frame of the sheet's
// fastest part). Where the switch is done in the press's handler, both are in the press's frame, as before.
//
// What that screen reads is what its panes say they open on, never a list kept here: each shell gives its node
// (workspace_switch_node) the function its panes open by (`opens`: 小屏's Home, sfapp's home_opens; 中屏's and 大屏's
// rail, sidebar and the page the pane lands on, sfdesk's frame_opens), which the pages wait by too, asking each topic
// of the `ask` they are given: a page `read_now`, the switch what it holds under a name of its own (`hold`). What one
// answer says may lead to another ask (the chat the pane lands on, once the marks say it): asked as it comes. What is
// held is the same subscription the panes then read, let go of once they hold it: never let go of and asked again
// between.

///|
/// How long a switch waits for what the new workspace's first screen opens on, at most, the screen as it was meanwhile.
pub let switch_wait_ms : Double = 300.0

///|
/// Whether what a page reads is answered: a value, or why it has none.
pub fn opens_answered(s : TopicState) -> Bool {
  s.value is Some(_) || s.error is Some(_)
}

///|
/// The ask a page opens by (what its `opens` says it reads): each topic as `src` has it now, read where it is read.
pub fn read_now(src : Source) -> (String, Map[String, Json]) -> TopicState {
  fn(name, params) { src.topic(name, params).get() }
}

///|
/// The workspace a switch waits to show ("" none) and the moment it was asked for.
// kept across runs: put back as a run begins (switch_reset)
let switch_asked : @signals.Signal[(String, Double)] = @signals.signal(("", -1.0), same=fn(a, b) { a == b })

///|
/// What the switch waiting holds: the source it holds with, under what name, and what its screen opens on (the shell's
/// `opens`).
priv struct SwitchWait {
  ws : String
  src : Source
  scope : String
  opens : (Source, String, (String, Map[String, Json]) -> TopicState) -> Bool
}

///|
// kept across runs: put back as a run begins (switch_reset)
let switch_wait : Ref[SwitchWait?] = Ref(None)

///|
/// What the presses of the switch waiting put up to choose by, to close as it is done or called off (each once).
// kept across runs: put back as a run begins (switch_reset)
let switch_closes : Ref[Array[() -> Unit]] = Ref([])

///|
/// What the switch waiting is to close closed now, each once: the switch done or called off.
fn switch_closed() -> Unit {
  let closes = switch_closes.val
  switch_closes.val = []
  for c in closes {
    c()
  }
}

///|
/// The shell's node that waits (workspace_switch_node), the source it was made with, what its screen opens on and its
/// token: the last made.
// kept across runs: put back as a run begins (switch_reset)
let switch_shell : Ref[(@view.View, Source, (Source, String, (String, Map[String, Json]) -> TopicState) -> Bool, Int)?] = Ref(
  None,
)

///|
/// Told each time the switch waiting has held more than it held before (an answer led its panes to another ask), so
/// what waits reads that too.
// kept across runs: put back as a run begins (switch_reset)
let switch_held_more : @signals.Signal[Int] = @signals.signal(0, same=fn(a, b) { a == b })

///|
/// What switches done held, to let go of once the new screen reads it (its source, its name).
// kept across runs: put back as a run begins (switch_reset)
let switch_handing : Ref[Array[(Source, String)]] = Ref([])

///|
/// When what is handed over is let go of (-1: nothing to).
// kept across runs: put back as a run begins (switch_reset)
let switch_hand_at : @signals.Signal[Double] = @signals.signal(-1.0, same=fn(a, b) { a == b })

///|
// kept across runs: only counted on
let switch_count : Ref[Int] = Ref(0)

///|
/// The workspace whose first screen is declared (opens_ahead_node), None none.
// kept across runs: put back as a run begins (switch_reset)
let opens_declared : Ref[String?] = Ref(None)

///|
/// What the screen opens on, each ask held under the switch's name (owned by none of what asked: held till let go of),
/// as far as what is answered leads: whether all of it is answered.
fn SwitchWait::hold_all(self : SwitchWait) -> Bool {
  let owner = @signals.set_owner(None)
  let done = @signals.untracked(fn() {
    (self.opens)(self.src, self.ws, fn(name, params) { hold(self.src, self.scope, name, params).get() })
  })
  @signals.set_owner(owner) |> ignore
  done
}

///|
/// What the screen opens on as the switch holds it now, read where it is read (the shell's reaction), holding nothing:
/// whether all of it is answered, and whether its panes ask what it does not hold yet.
fn SwitchWait::answered_now(self : SwitchWait) -> (Bool, Bool) {
  let more = Ref(false)
  let done = (self.opens)(self.src, self.ws, fn(name, params) {
    match held_state(self.src, self.scope, name, params) {
      Some(s) => s.get()
      None => {
        more.val = true
        { value: None, error: None, version: -1, waiting: false }
      }
    }
  })
  (done && !more.val, more.val)
}

///|
/// The workspace `ws` the one in view, at its top (the prefs' `workspace`), once what its first screen opens on is
/// answered or switch_wait_ms after now, whichever comes first; at once where it is answered already. Another asked
/// meanwhile takes its place; the one in view asked, the one waiting is called off. `closes`: what the press put up to
/// choose by, closed at the moment the switch is done (in the press's handler where it is done there), with the switch
/// to another asked meanwhile, at once where the one in view is asked; once (what the person closed meanwhile is closed already: a
/// presenter's close of what is no longer open closes nothing).
pub fn switch_workspace_to(src : Source, ws : String, closes? : () -> Unit = fn() {  }) -> Unit {
  if ws == "" {
    closes()
    return
  }
  let here = @signals.untracked(fn() { workspace_in_view(src).0.map(fn(w) { w.id }) })
  if here == Some(ws) {
    switch_called_off()
    closes()
    return
  }
  if switch_wait.val is Some(w) && w.ws == ws {
    switch_closes.val.push(closes)
    return
  }
  // (no shell to wait in: at once, as before there was one)
  guard switch_shell.val is Some((v, base, opens, _)) else {
    switch_picked(src, ws)
    closes()
    return
  }
  switch_count.val += 1
  // (the shell's source, not a page's that may go first)
  let wait = { ws, src: base, scope: "switch/" + switch_count.val.to_string(), opens }
  let done = wait.hold_all()
  // (the one waiting before let go of once this one is held; what it was to close closed with this one, which takes
  // its place: a second row pressed in the same sheet as it waits leaves it standing till the switch)
  let carried = switch_closes.val
  switch_closes.val = []
  switch_called_off()
  switch_wait.val = Some(wait)
  switch_closes.val = [..carried, closes]
  if done {
    switch_pick(v)
  } else {
    switch_asked.set((ws, v.cause_at()))
  }
}

///|
/// The switch waiting called off, what it held let go of, what it was to close closed.
fn switch_called_off() -> Unit {
  match switch_wait.val {
    Some(w) => {
      switch_wait.val = None
      let_go(w.src, w.scope)
    }
    None => ()
  }
  switch_asked.set(("", -1.0))
  switch_closed()
}

///|
/// The switch waiting done, by shell node `v`: what it held handed over to the screen it shows, let go of once that is
/// in (the longest a page takes to come: the panes' own readers hold it by then); what its presses put up closed with
/// it, at its moment.
fn switch_pick(v : @view.View) -> Unit {
  guard switch_wait.val is Some(w) else { return }
  switch_wait.val = None
  switch_asked.set(("", -1.0))
  switch_picked(w.src, w.ws)
  switch_closed()
  switch_handing.val.push((w.src, w.scope))
  switch_hand_at.set(v.cause_at() + @ui.move_most_ms)
}

///|
/// What a switch does once done, as one act (history_act: an entry for where it left from, whenever it is done).
fn switch_picked(src : Source, ws : String) -> Unit {
  history_act(fn() {
    app.picked.set(ws)
    (src.call)("prefs.set", Json::object({ "workspace": Json::string(ws) }), answer_unread)
    nav_home()
  })
}

///|
/// What a workspace switch waits by, in the shell's node `v` (each shell makes it once, giving what its panes open on:
/// `opens`): the switch done as all its screen opens on is answered (what an answer leads to asked as it comes) or
/// switch_wait_ms after it was asked, whichever comes first; what it held let go of at the moment switch_pick said.
/// Both at their causes' moments, whatever frames are drawn.
pub fn workspace_switch_node(
  v : @view.View,
  src : Source,
  opens : (Source, String, (String, Map[String, Json]) -> TopicState) -> Bool,
) -> Unit {
  switch_count.val += 1
  let token = switch_count.val
  switch_shell.val = Some((v, src, opens, token))
  v.owns(fn() {
    if switch_shell.val is Some((_, _, _, t)) && t == token {
      switch_shell.val = None
    }
  })
  |> ignore
  let cap : Ref[() -> Unit] = Ref(fn() {  })
  v.reacts(
    fn() {
      let (ws, at) = switch_asked.get()
      switch_held_more.get() |> ignore
      match switch_wait.val {
        Some(w) if ws != "" && w.ws == ws => {
          let (done, more) = w.answered_now()
          Some((ws, at, done, more))
        }
        _ => None
      }
    },
    fn(asked) {
      (cap.val)()
      cap.val = fn() {  }
      match asked {
        Some((_, at, done, more)) => {
          // (an answer led to another ask: held now, and read where it waits from then)
          let done = if more {
            match switch_wait.val {
              Some(w) => w.hold_all()
              None => false
            }
          } else {
            done
          }
          if done {
            switch_pick(v)
          } else {
            cap.val = v.at_moment(at + switch_wait_ms, fn() { switch_pick(v) })
            if more {
              switch_held_more.set(switch_held_more.untracked() + 1)
            }
          }
        }
        None => ()
      }
    },
  )
  let hand : Ref[() -> Unit] = Ref(fn() {  })
  v.reacts(fn() { switch_hand_at.get() }, fn(at) {
    (hand.val)()
    hand.val = fn() {  }
    if at >= 0.0 {
      hand.val = v.at_moment(at, fn() {
        let handing = switch_handing.val
        switch_handing.val = []
        for h in handing {
          let_go(h.0, h.1)
        }
        switch_hand_at.set(-1.0)
      })
    }
  })
}

///|
/// What the workspace in view opens on (`opens`: the shell's, as workspace_switch_node is given it, which asks what its
/// first screen reads), declared at the moment it is known to be the one in view, in the app's node `v` that outlives
/// the splash and every shell: each topic asked of the core then (declare_topic), not as the frame that builds the
/// panes runs, and taken over by the reader that comes to read it as it reads, the same subscription never let go of
/// between. What an answer leads to (the page a pane lands on, once the marks say which) is declared at the moment that
/// answer comes, between frames, while the app's first page waits (`first_waits`: another workspace switched to later
/// declares what it knows as it comes in view, as before): what the function says is read here as held till all of it
/// is answered or the first page is shown (its reader that long, as the first page's wait is: what it read of its own
/// taken by the pages' readers by then), added to and never taken back, and not again once all of it was answered (the chat opened last changing later is no first screen;
/// the coordinator of the migration, 2026-11-12). What no reader took is let go of as another workspace comes in view,
/// or none. A bridge till the old view is gone: a page made as nodes says what it reads where
/// it is made. Known and left (the coordinator of the migration, 2026-11-12): where a page is put over Home as the app
/// starts (a notification's chat, a scripted run's files' page), what only this read held is let go of as all of it is
/// answered, between frames, and asked again by the frame after, whose old view's readers come only then (a few small
/// values, once a start); it goes as those pages are made as nodes, their readers there at the moment of their cause.
pub fn opens_ahead_node(
  v : @view.View,
  src : Source,
  opens : () -> (String, (Source, String, (String, Map[String, Json]) -> TopicState) -> Bool)?,
  first_waits~ : () -> Bool,
) -> Unit {
  // (the first screen of the shell its window's width picks as the workspace comes in view, none before the window has
  // a width; another shell come of the window's width alone declares nothing: the workspace is in view already, what
  // its first screen read taken over by its readers and the graph's since, as a page's opening is its own)
  v.reacts(
    fn() {
      match (workspace_in_view(src).0, opens()) {
        (Some(w), Some(_)) => Some(w.id)
        _ => None
      }
    },
    fn(now) {
      if opens_declared.val == now {
        return
      }
      declared_let_go()
      page_declared_let_go()
      opens_declared.val = now
      opens_declared_said.set(None)
      guard now is Some(ws) else { return }
      guard @signals.untracked(opens) is Some((_, panes)) else { return }
      panes(src, ws, fn(name, params) { declare_topic(src, name, params) }) |> ignore
      opens_declared_said.set(now)
      opens_declared_round.set(opens_declared_round.untracked() + 1)
    },
  )
  // (what the function comes to say as what it read is answered: declared at that moment; read as held till all of it
  // is, then no more)
  v.reacts(
    fn() {
      opens_declared_round.get() |> ignore
      guard opens_declared_said.get() is Some(ws) else { return None }
      if opens_all_answered.val == Some(ws) || !first_waits() {
        return None
      }
      guard @signals.untracked(opens) is Some((_, panes)) else { return None }
      let held = read_held_found(src)
      let more : Array[(String, Map[String, Json])] = []
      opens_more.val = more
      let all = panes(src, ws, fn(name, params) {
        match held(name, params) {
          Some(st) => st
          None => {
            more.push((name, params.copy()))
            { value: None, error: None, version: -1, waiting: false }
          }
        }
      })
      Some((ws, all, more.map(fn(m) { m.0 + " " + Json::object(m.1).stringify() })))
    },
    fn(said) {
      guard said is Some((ws, all, _)) else { return }
      let more = opens_more.val
      if more.length() > 0 {
        for m in more {
          declare_topic(src, m.0, m.1) |> ignore
        }
        // (read again, what it declared now followed with the rest)
        opens_declared_round.set(opens_declared_round.untracked() + 1)
      } else if all {
        opens_all_answered.val = Some(ws)
        opens_declared_round.set(opens_declared_round.untracked() + 1)
      }
    },
  )
}

///|
/// The workspace whose first screen opens_ahead_node has declared, told once it has (None: none yet, or let go):
/// what reads what that screen opens on as held reads it once this is its workspace, all of it followed then
/// (sfapp's first_page_node).
pub fn opens_declared_now() -> String? {
  // (each time more of it is declared, told again: opens_ahead_node's second reaction)
  opens_declared_round.get() |> ignore
  opens_declared_said.get()
}

///|
/// How many times opens_ahead_node has declared (the first screen, and what an answer led it to): told each time.
// kept across runs: a count, read for its changes alone
let opens_declared_round : @signals.Signal[Int] = @signals.signal(0)

///|
/// What opens_ahead_node's second reaction found the function saying that is not declared yet, as it last read it.
// kept across runs: put back as a run begins (switch_reset)
let opens_more : Ref[Array[(String, Map[String, Json])]] = Ref([])

///|
/// The workspace all of whose first screen opens_ahead_node found answered: what it declared read there no more.
// kept across runs: put back as a run begins (switch_reset)
let opens_all_answered : Ref[String?] = Ref(None)

///|
// kept across runs: put back as a run begins (switch_reset)
let opens_declared_said : @signals.Signal[String?] = @signals.signal(None, same=fn(a, b) { a == b })

///|
/// What the page on top reads as it is first built (page_opens), declared in node `v` at the moment it comes on top,
/// however it came (a row pressed, a notification or a link opened, back to it, a pane landing on it), between frames,
/// not as the frame that builds it runs; what the page on top before declared and no reader took let go of then.
pub fn page_opens_node(v : @view.View, src : Source) -> Unit {
  v.reacts(
    fn() {
      match workspace_in_view(src).0 {
        Some(_) => Some(app.nav.top())
        None => None
      }
    },
    fn(top) {
      page_declared_let_go()
      guard top is Some(p) else { return }
      // (once the change that put it on top is told whole: asked in the reaction itself, a topic's first read can set
      // what `read` follows while it runs, and the node's watch of the top then went on with none of it, never told the
      // page went: its declared never let go, sfapp's core_signal_wbtest and page_scope_*_wbtest; one no longer on top
      // by then declares nothing)
      @signals.after_flush(fn() {
        if @signals.untracked(fn() { app.nav.top() }) == p {
          page_opens(p, fn(name, params) { declare_page_topic(src, name, params) })
        }
      })
    },
  )
  // (a chat on top: what it opens on past its view (chat_opens: its posts' login cards), declared as its view, held,
  // says them, and as what they say is answered, so the first page's wait and the page's own reads find them held;
  // once all of it is answered, what it came to is kept for that page and its view followed no more here, so a long
  // chat's every change is not walked again for it)
  let opened : Ref[(Page, Array[(String, Map[String, Json])])?] = Ref(None)
  v.reacts(
    fn() {
      page_declared_now() |> ignore
      guard workspace_in_view(src).0 is Some(_) && app.nav.top() is Chat(r) else {
        opened.val = None
        return []
      }
      match opened.val {
        Some((p, more)) if p == Chat(r) => return more
        _ => opened.val = None
      }
      let held = read_held_found(src)
      let more : Array[(String, Map[String, Json])] = []
      let all = chat_opens(r, fn(name, params) {
        if name != "chat" {
          more.push((name, params))
        }
        held(name, params).unwrap_or({ value: None, error: None, version: -1, waiting: false })
      })
      if all {
        opened.val = Some((Chat(r), more))
      }
      more
    },
    fn(more) {
      // (in the change its view's answer is told in, not after it: the first page's wait looks for them held once
      // that change is told whole)
      for d in more {
        declare_page_topic(src, d.0, d.1)
      }
    },
  )
}

///|
/// What every shell reads of workspace `ws` as its frame is built, whatever page it lands on, asked of `ask`: the lock
/// and what waits in it, the marks, what is going on and going up or down, the workspace's status line, notifications'
/// state: part of what each shell's first screen opens on (sfapp's home_opens, sfdesk's frame_opens), declared with it
/// (opens_ahead_node), never waited for (Home shows, a switch is done, the splash goes, as before they were asked
/// there). Whether all of it is answered.
pub fn shell_opens(src : Source, ws : String, ask : (String, Map[String, Json]) -> TopicState) -> Bool {
  let of = Json::string(ws)
  let reads : Array[(String, Map[String, Json])] = [
    ("lock", { "workspace": of }),
    ("workspaceMarks", marks_asked()),
    ("doing", {}),
    ("driveTransfers", { "workspace": of }),
    ("status", { "workspace": of }),
    ("lockPrompts", {}),
    ("notify", {}),
    ("notify", notify_params(ws)),
  ]
  // (the stations' newer releases waiting for this person: sfpages station_updates.mbt, the bars' key of them)
  if (src.asks_station_updates)() {
    reads.push(("stationUpdates", { "scope": of }))
  }
  reads.fold(init=true, fn(all, r) { opens_answered(ask(r.0, r.1)) && all })
}

///|
fn switch_reset() -> Unit {
  switch_shell.val = None
  switch_wait.val = None
  switch_asked.set(("", -1.0))
  switch_held_more.set(0)
  switch_handing.val = []
  switch_closes.val = []
  switch_hand_at.set(-1.0)
  opens_declared.val = None
  opens_declared_said.set(None)
  opens_all_answered.val = None
  opens_more.val = []
  declared_reset()
}
